-- ==============================================================================
-- Migration: Trim Realtime publication and restore default replica identity
-- ==============================================================================
-- Partially reverts enable_realtime_all_tables.sql. That script most likely
-- never took effect: on 2026-10-22 20:55:59 UTC it failed with
-- `invalid input value for enum user_role: "superadmin"` and the SQL editor
-- runs a script as one transaction. Check before running this:
--   SELECT relname FROM pg_class
--   WHERE relnamespace = 'public'::regnamespace AND relreplident = 'f';
--   SELECT tablename FROM pg_publication_tables
--   WHERE pubname = 'supabase_realtime';
-- Every statement below is a no-op when its target is already in place.
--
-- 1. REPLICA IDENTITY back to DEFAULT. FULL only matters for filtered DELETE
--    events and old_record; filtered UPDATE/INSERT events carry the whole new
--    row either way. FULL made every rider GPS update (profiles, every 20 m)
--    write the entire old row to WAL for Realtime to decode.
-- 2. Drop tables nothing subscribes to (checked against lib/ and admin/lib/).
--    rider_locations gets an INSERT every 20 m of rider movement.
-- ==============================================================================

DO $$
DECLARE
  tbl text;
BEGIN
  FOREACH tbl IN ARRAY ARRAY[
    'orders', 'order_items', 'profiles', 'rider_locations', 'water_types',
    'products', 'station_fee_wallets', 'station_fee_wallet_entries',
    'station_fee_topups', 'owner_inventory_ledger', 'owner_settings',
    'messages', 'chat_rooms', 'chat_participants', 'reviews', 'disputes',
    'system_notifications', 'payment_checkouts', 'payment_webhook_events',
    'app_releases'
  ] LOOP
    IF EXISTS (
      SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = tbl
    ) THEN
      EXECUTE format('ALTER TABLE public.%I REPLICA IDENTITY DEFAULT;', tbl);
    END IF;
  END LOOP;

  FOREACH tbl IN ARRAY ARRAY[
    'rider_locations', 'station_fee_topups', 'chat_rooms',
    'chat_participants', 'payment_checkouts'
  ] LOOP
    IF EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = tbl
    ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime DROP TABLE public.%I;', tbl);
    END IF;
  END LOOP;
END $$;
