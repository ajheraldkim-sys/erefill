-- ==============================================================================
-- Smart refill reminders (2026-11-05)
-- ==============================================================================
-- Learns each customer's refill rhythm (median days between their last
-- delivered orders, needs >= 3 orders) and reminds them a day before they
-- usually reorder. At most one reminder per 3 days, never while an order is
-- active, and only when profiles.refill_reminders_enabled.
--   * customer_refill_rhythm()  -> for the app's home banner (current user)
--   * send_refill_reminders()   -> daily 9:00 PH pg_cron job, inserts notifications
-- Test: supabase/tests/refill_reminders_test.sql
-- ==============================================================================
BEGIN;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS refill_reminders_enabled boolean NOT NULL DEFAULT true;

CREATE OR REPLACE FUNCTION public.refill_rhythm_for(p_customer_id uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  WITH recent AS (
    SELECT created_at, owner_id, station_name
    FROM public.orders
    WHERE customer_id = p_customer_id AND status = 'delivered'
    ORDER BY created_at DESC
    LIMIT 6
  ), gaps AS (
    SELECT extract(epoch FROM (created_at - lead(created_at) OVER (ORDER BY created_at DESC))) / 86400.0 AS days
    FROM recent
  ), stats AS (
    SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY days) AS median_days,
           count(*) AS gap_count
    FROM gaps WHERE days IS NOT NULL AND days > 0.5
  ), last AS (
    SELECT * FROM recent ORDER BY created_at DESC LIMIT 1
  )
  SELECT CASE
    WHEN (SELECT gap_count FROM stats) < 2 THEN jsonb_build_object('has_rhythm', false)
    ELSE jsonb_build_object(
      'has_rhythm', true,
      'median_days', round((SELECT median_days FROM stats)::numeric, 1),
      'last_order_at', (SELECT created_at FROM last),
      'station_id', (SELECT owner_id FROM last),
      'station_name', (SELECT station_name FROM last),
      'due_at', (SELECT created_at FROM last)
                + make_interval(secs => greatest((SELECT median_days FROM stats) - 1, 1) * 86400),
      'is_due', now() >= (SELECT created_at FROM last)
                + make_interval(secs => greatest((SELECT median_days FROM stats) - 1, 1) * 86400),
      'has_active_order', EXISTS (
        SELECT 1 FROM public.orders
        WHERE customer_id = p_customer_id
          AND status NOT IN ('delivered', 'cancelled', 'failed'))
    )
  END;
$$;
REVOKE ALL ON FUNCTION public.refill_rhythm_for(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.customer_refill_rhythm()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT CASE WHEN auth.uid() IS NULL THEN '{"has_rhythm": false}'::jsonb
              ELSE public.refill_rhythm_for(auth.uid()) END;
$$;
REVOKE ALL ON FUNCTION public.customer_refill_rhythm() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.customer_refill_rhythm() TO authenticated;

CREATE OR REPLACE FUNCTION public.send_refill_reminders()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_row record;
  v_r jsonb;
  v_sent integer := 0;
BEGIN
  FOR v_row IN
    SELECT p.id FROM public.profiles p
    WHERE p.role = 'customer' AND p.refill_reminders_enabled AND NOT coalesce(p.is_suspended, false)
  LOOP
    v_r := public.refill_rhythm_for(v_row.id);
    CONTINUE WHEN NOT coalesce((v_r->>'has_rhythm')::boolean, false)
               OR NOT (v_r->>'is_due')::boolean
               OR (v_r->>'has_active_order')::boolean;
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM public.system_notifications n
      WHERE n.user_id = v_row.id
        AND n.metadata->>'kind' = 'refill_reminder'
        AND n.created_at > now() - interval '3 days');

    INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
    VALUES (
      v_row.id, 'system_alert', 'normal', 'Time for a refill?',
      'You usually reorder every ' || round((v_r->>'median_days')::numeric) || ' days. '
        || 'Tap to reorder from ' || coalesce(v_r->>'station_name', 'your station') || '.',
      jsonb_build_object('kind', 'refill_reminder', 'station_id', v_r->>'station_id')
    );
    v_sent := v_sent + 1;
  END LOOP;
  RETURN v_sent;
END; $$;
REVOKE ALL ON FUNCTION public.send_refill_reminders() FROM PUBLIC, anon, authenticated;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'send_refill_reminders';
    -- 9:00 Asia/Manila = 01:00 UTC, so reminders arrive in the morning.
    PERFORM cron.schedule('send_refill_reminders', '0 1 * * *', 'SELECT public.send_refill_reminders()');
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';
