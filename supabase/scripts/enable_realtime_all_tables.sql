-- ==============================================================================
-- Migration: Enable Full Realtime Sync & Replica Identity Across All Tables
-- ==============================================================================
-- This script ensures all essential eRefill tables are:
-- 1. Added to the `supabase_realtime` publication for instant WebSocket delivery.
-- 2. Configured with REPLICA IDENTITY FULL so PostgreSQL write-ahead logs (WAL)
--    emit all row columns during UPDATE and DELETE operations. Without this,
--    Supabase Realtime filters (e.g. customer_id, owner_id, assigned_rider_id)
--    silently drop update events whenever the filtered column wasn't modified!
-- 3. Equipped with permissive SELECT RLS policies so Realtime can broadcast to
--    authenticated clients.
-- ==============================================================================

-- 1. Set REPLICA IDENTITY FULL on all core tables
DO $$
DECLARE
  tbl text;
  tables text[] := ARRAY[
    'orders',
    'order_items',
    'profiles',
    'rider_locations',
    'water_types',
    'products',
    'station_fee_wallets',
    'station_fee_wallet_entries',
    'station_fee_topups',
    'owner_inventory_ledger',
    'owner_settings',
    'messages',
    'chat_rooms',
    'chat_participants',
    'reviews',
    'disputes',
    'system_notifications',
    'payment_checkouts',
    'payment_webhook_events',
    'app_releases'
  ];
BEGIN
  FOREACH tbl IN ARRAY tables LOOP
    IF EXISTS (
      SELECT 1 FROM pg_tables
      WHERE schemaname = 'public' AND tablename = tbl
    ) THEN
      EXECUTE format('ALTER TABLE public.%I REPLICA IDENTITY FULL;', tbl);
      RAISE NOTICE 'Set REPLICA IDENTITY FULL on public.%', tbl;
    END IF;
  END LOOP;
END $$;

-- 2. Ensure publication `supabase_realtime` exists and add all tables to it
DO $$
DECLARE
  tbl text;
  tables text[] := ARRAY[
    'orders',
    'order_items',
    'profiles',
    'rider_locations',
    'water_types',
    'products',
    'station_fee_wallets',
    'station_fee_wallet_entries',
    'station_fee_topups',
    'owner_inventory_ledger',
    'owner_settings',
    'messages',
    'chat_rooms',
    'chat_participants',
    'reviews',
    'disputes',
    'system_notifications',
    'payment_checkouts',
    'payment_webhook_events',
    'app_releases'
  ];
BEGIN
  -- Create publication if missing
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    CREATE PUBLICATION supabase_realtime;
    RAISE NOTICE 'Created publication supabase_realtime';
  END IF;

  FOREACH tbl IN ARRAY tables LOOP
    IF EXISTS (
      SELECT 1 FROM pg_tables
      WHERE schemaname = 'public' AND tablename = tbl
    ) THEN
      IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND schemaname = 'public'
          AND tablename = tbl
      ) THEN
        EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I;', tbl);
        RAISE NOTICE 'Added public.% to supabase_realtime publication', tbl;
      ELSE
        RAISE NOTICE 'public.% is already in supabase_realtime', tbl;
      END IF;
    END IF;
  END LOOP;
END $$;

-- 3. Ensure SELECT RLS policies allow Realtime broadcasting to clients

-- Water Types: Publicly viewable by anyone (customers, owners, riders, admins)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'water_types') THEN
    ALTER TABLE public.water_types ENABLE ROW LEVEL SECURITY;
    IF NOT EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public' AND tablename = 'water_types' AND policyname = 'Anyone can view water types'
    ) THEN
      CREATE POLICY "Anyone can view water types"
        ON public.water_types FOR SELECT
        TO anon, authenticated
        USING (true);
    END IF;
  END IF;
END $$;

-- App Releases: Viewable by anyone
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'app_releases') THEN
    ALTER TABLE public.app_releases ENABLE ROW LEVEL SECURITY;
    IF NOT EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public' AND tablename = 'app_releases' AND policyname = 'Anyone can view active app releases'
    ) THEN
      CREATE POLICY "Anyone can view active app releases"
        ON public.app_releases FOR SELECT
        TO anon, authenticated
        USING (true);
    END IF;
  END IF;
END $$;

-- Station Fee Wallets: Owners can view their own wallet; Admins can view all
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'station_fee_wallets') THEN
    ALTER TABLE public.station_fee_wallets ENABLE ROW LEVEL SECURITY;
    IF NOT EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public' AND tablename = 'station_fee_wallets' AND policyname = 'Owners and admins can view fee wallets'
    ) THEN
      CREATE POLICY "Owners and admins can view fee wallets"
        ON public.station_fee_wallets FOR SELECT
        TO authenticated
        USING (
          owner_id = auth.uid() OR
          EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid() AND role IN ('admin', 'superadmin')
          )
        );
    END IF;
  END IF;
END $$;

-- Station Fee Wallet Entries: Owners can view their entries; Admins can view all
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'station_fee_wallet_entries') THEN
    ALTER TABLE public.station_fee_wallet_entries ENABLE ROW LEVEL SECURITY;
    IF NOT EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public' AND tablename = 'station_fee_wallet_entries' AND policyname = 'Owners and admins can view fee entries'
    ) THEN
      CREATE POLICY "Owners and admins can view fee entries"
        ON public.station_fee_wallet_entries FOR SELECT
        TO authenticated
        USING (
          owner_id = auth.uid() OR
          EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid() AND role IN ('admin', 'superadmin')
          )
        );
    END IF;
  END IF;
END $$;

-- Synchronize rider_id and assigned_rider_id trigger for complete coverage
CREATE OR REPLACE FUNCTION public.sync_order_rider_columns()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.assigned_rider_id IS NOT NULL AND NEW.rider_id IS NULL THEN
    NEW.rider_id := NEW.assigned_rider_id;
  ELSIF NEW.rider_id IS NOT NULL AND NEW.assigned_rider_id IS NULL THEN
    NEW.assigned_rider_id := NEW.rider_id;
  ELSIF NEW.assigned_rider_id IS NOT NULL AND NEW.rider_id IS NOT NULL AND NEW.assigned_rider_id <> NEW.rider_id THEN
    IF OLD.assigned_rider_id IS DISTINCT FROM NEW.assigned_rider_id THEN
      NEW.rider_id := NEW.assigned_rider_id;
    ELSIF OLD.rider_id IS DISTINCT FROM NEW.rider_id THEN
      NEW.assigned_rider_id := NEW.rider_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_sync_order_rider_columns ON public.orders;
CREATE TRIGGER trg_sync_order_rider_columns
BEFORE INSERT OR UPDATE ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.sync_order_rider_columns();

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';

