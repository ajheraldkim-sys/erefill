-- ==============================================================================
-- Rider live location privacy (2026-11-05)
-- ==============================================================================
-- rider_locations was readable by everyone ("Public can view rider
-- locations"). Now only these can read a rider's points:
--   * the rider, admins
--   * the customer or station of an order that rider is delivering right now
--     (assigned_to_rider / out_for_delivery)
-- After delivery the customer loses access. Points older than 24 h are purged
-- hourly (pg_cron, when the extension is available).
-- Test: supabase/tests/rider_live_location_test.sql
-- ==============================================================================
BEGIN;

DROP POLICY IF EXISTS "Public can view rider locations" ON public.rider_locations;
DROP POLICY IF EXISTS "Rider location visible to active delivery parties" ON public.rider_locations;
CREATE POLICY "Rider location visible to active delivery parties" ON public.rider_locations
  FOR SELECT TO authenticated
  USING (
    rider_id = auth.uid()
    OR public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.orders o
      WHERE (o.assigned_rider_id = rider_locations.rider_id OR o.rider_id = rider_locations.rider_id)
        AND o.status IN ('assigned_to_rider', 'out_for_delivery')
        AND (o.customer_id = auth.uid() OR o.owner_id = auth.uid())
    )
  );

DROP POLICY IF EXISTS "Riders can update their own location" ON public.rider_locations;
CREATE POLICY "Riders can update their own location" ON public.rider_locations
  FOR INSERT TO authenticated
  WITH CHECK (rider_id = auth.uid());
REVOKE ALL ON public.rider_locations FROM anon;

CREATE OR REPLACE FUNCTION public.purge_old_rider_locations()
RETURNS integer
LANGUAGE sql SECURITY DEFINER SET search_path TO 'public' AS $$
  WITH d AS (
    DELETE FROM public.rider_locations WHERE "timestamp" < now() - interval '24 hours' RETURNING 1
  ) SELECT count(*)::int FROM d;
$$;
REVOKE ALL ON FUNCTION public.purge_old_rider_locations() FROM PUBLIC, anon, authenticated;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'purge_old_rider_locations';
    PERFORM cron.schedule('purge_old_rider_locations', '7 * * * *', 'SELECT public.purge_old_rider_locations()');
  END IF;
END $$;

COMMIT;
