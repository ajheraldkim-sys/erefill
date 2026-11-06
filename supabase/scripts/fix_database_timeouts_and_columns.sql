-- ==============================================================================
-- Migration: Fix Database Timeouts, Missing Columns, and RPCs
-- ==============================================================================
-- This script resolves the errors observed in Supabase Dashboard logs:
-- 1. Error 42703: "Column orders.owner_acknowledged_at does not exist"
-- 2. Error 57014: "canceling statement due to statement timeout"
-- 3. PostgREST: "Warp server error: Thread killed by timeout manager"
-- ==============================================================================

BEGIN;

-- 1. Add missing acknowledgment columns to orders table -----------------------
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS owner_acknowledged_at timestamptz DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS admin_acknowledged_at timestamptz DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS delivery_distance_km numeric(10, 2),
  ADD COLUMN IF NOT EXISTS delivery_rate_per_km numeric(10, 2);

-- 2. Add high-performance indexes to eliminate full table scans & timeouts -----
CREATE INDEX IF NOT EXISTS idx_orders_owner_status_ack
  ON public.orders (owner_id, status, owner_acknowledged_at)
  WHERE (status = 'pending');

CREATE INDEX IF NOT EXISTS idx_orders_customer_status
  ON public.orders (customer_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_orders_owner_created
  ON public.orders (owner_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_messages_room_created
  ON public.messages (room_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_chat_participants_user
  ON public.chat_participants (user_id, room_id);

-- 3. Ensure system_config table exists with proper unique constraint ----------
CREATE TABLE IF NOT EXISTS public.system_config (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    key text NOT NULL,
    value jsonb NOT NULL,
    description text,
    updated_at timestamptz DEFAULT now(),
    updated_by uuid
);

ALTER TABLE public.system_config ADD COLUMN IF NOT EXISTS updated_by uuid;
ALTER TABLE public.system_config ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();
ALTER TABLE public.system_config ADD COLUMN IF NOT EXISTS description text;

CREATE UNIQUE INDEX IF NOT EXISTS system_config_key_idx ON public.system_config (key);

-- Ensure audit_logs exists
CREATE TABLE IF NOT EXISTS public.audit_logs (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    created_at timestamptz DEFAULT now(),
    actor_id uuid,
    action text NOT NULL,
    entity_type text NOT NULL,
    entity_id text NOT NULL,
    old_value jsonb,
    new_value jsonb,
    metadata jsonb
);

ALTER TABLE public.audit_logs ADD COLUMN IF NOT EXISTS actor_id uuid;
ALTER TABLE public.audit_logs ADD COLUMN IF NOT EXISTS action text;
ALTER TABLE public.audit_logs ADD COLUMN IF NOT EXISTS entity_type text;
ALTER TABLE public.audit_logs ADD COLUMN IF NOT EXISTS entity_id text;
ALTER TABLE public.audit_logs ADD COLUMN IF NOT EXISTS old_value jsonb;
ALTER TABLE public.audit_logs ADD COLUMN IF NOT EXISTS new_value jsonb;
ALTER TABLE public.audit_logs ADD COLUMN IF NOT EXISTS metadata jsonb;

-- 4. Admin authorization helper -----------------------------------------------
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF current_user IN ('postgres', 'service_role') THEN
    RETURN true;
  END IF;

  IF auth.uid() IS NULL THEN
    RETURN false;
  END IF;

  RETURN EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role IN ('admin', 'superadmin')
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated, anon, service_role;

-- 5. Seed default delivery fee configuration ----------------------------------
INSERT INTO public.system_config (key, value, updated_at)
VALUES (
  'delivery_fee_config',
  jsonb_build_object(
    'enabled', true,
    'rate_per_km', 10.0,
    'minimum_fee', 20.0,
    'min_billable_distance_km', 1.0,
    'rounding_rule', 'exact',
    'reason', 'Initial centralized delivery fee configuration'
  ),
  now()
)
ON CONFLICT (key) DO NOTHING;

-- 6. RPC: Fast, index-backed badge counts -------------------------------------
CREATE OR REPLACE FUNCTION public.get_station_new_orders_count()
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_count integer := 0;
BEGIN
  IF v_uid IS NULL THEN
    RETURN 0;
  END IF;

  SELECT count(*)::integer INTO v_count
  FROM public.orders
  WHERE owner_id = v_uid
    AND status = 'pending'
    AND owner_acknowledged_at IS NULL;

  RETURN coalesce(v_count, 0);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_station_new_orders_count() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_total_unread_chat_count()
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_count integer := 0;
BEGIN
  IF v_uid IS NULL THEN
    RETURN 0;
  END IF;

  SELECT count(*)::integer INTO v_count
  FROM public.messages m
  JOIN public.chat_participants cp ON cp.room_id = m.room_id AND cp.user_id = v_uid
  WHERE m.sender_id <> v_uid
    AND (m.read_by IS NULL OR NOT (m.read_by ? v_uid::text));

  RETURN coalesce(v_count, 0);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_total_unread_chat_count() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_user_notification_counts()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_role text;
  v_unread_notifications integer := 0;
  v_unread_chat integer := 0;
  v_new_orders integer := 0;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('unread_notifications', 0, 'unread_chat', 0, 'new_orders', 0);
  END IF;

  SELECT role INTO v_role FROM public.profiles WHERE id = v_uid;

  SELECT count(*)::integer INTO v_unread_notifications
  FROM public.system_notifications
  WHERE user_id = v_uid AND is_read = false;

  v_unread_chat := public.get_total_unread_chat_count();

  IF v_role = 'owner' THEN
    v_new_orders := public.get_station_new_orders_count();
  ELSIF v_role IN ('admin', 'superadmin') OR public.is_admin() THEN
    SELECT count(*)::integer INTO v_new_orders
    FROM public.orders
    WHERE status = 'pending' AND admin_acknowledged_at IS NULL;
  END IF;

  RETURN jsonb_build_object(
    'unread_notifications', coalesce(v_unread_notifications, 0),
    'unread_chat', coalesce(v_unread_chat, 0),
    'new_orders', coalesce(v_new_orders, 0)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_user_notification_counts() TO authenticated, service_role;

-- 7. Delivery fee RPCs --------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_delivery_fee_config()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cfg jsonb;
  v_admin_email text;
BEGIN
  SELECT value INTO v_cfg
  FROM public.system_config
  WHERE key = 'delivery_fee_config';

  IF v_cfg IS NULL THEN
    v_cfg := jsonb_build_object(
      'enabled', true,
      'rate_per_km', 10.0,
      'minimum_fee', 20.0,
      'min_billable_distance_km', 1.0,
      'rounding_rule', 'exact'
    );
  END IF;

  IF v_cfg->>'updated_by' IS NOT NULL THEN
    SELECT email INTO v_admin_email
    FROM public.profiles
    WHERE id = (v_cfg->>'updated_by')::uuid;
    v_cfg := v_cfg || jsonb_build_object('updated_by_email', v_admin_email);
  END IF;

  RETURN v_cfg;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_delivery_fee_config() TO authenticated, anon;

CREATE OR REPLACE FUNCTION public.calculate_delivery_fee(p_distance_km numeric)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cfg jsonb := public.get_delivery_fee_config();
  v_rate numeric;
  v_min_fee numeric;
  v_min_dist numeric;
  v_rule text;
  v_dist numeric;
  v_fee numeric;
BEGIN
  IF NOT coalesce((v_cfg->>'enabled')::boolean, true) THEN
    RETURN 0.00;
  END IF;

  v_rate := greatest(coalesce((v_cfg->>'rate_per_km')::numeric, 10.0), 0);
  v_min_fee := greatest(coalesce((v_cfg->>'minimum_fee')::numeric, 0), 0);
  v_min_dist := greatest(coalesce((v_cfg->>'min_billable_distance_km')::numeric, 0), 0);
  v_rule := coalesce(v_cfg->>'rounding_rule', 'exact');

  v_dist := greatest(coalesce(p_distance_km, 0), v_min_dist);
  IF v_rule = 'ceil' THEN
    v_dist := ceil(v_dist);
  ELSIF v_rule = 'round' THEN
    v_dist := round(v_dist);
  END IF;

  v_fee := round(v_dist * v_rate, 2);
  IF v_min_fee > 0 AND v_fee < v_min_fee THEN
    v_fee := v_min_fee;
  END IF;

  RETURN greatest(v_fee, 0);
END;
$$;

GRANT EXECUTE ON FUNCTION public.calculate_delivery_fee(numeric) TO authenticated, anon;

-- 8. Auto-stamp owner acknowledgment on status change -------------------------
CREATE OR REPLACE FUNCTION public.stamp_order_acknowledged()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF OLD.status = 'pending' AND NEW.status <> 'pending'
     AND NEW.owner_acknowledged_at IS NULL THEN
    NEW.owner_acknowledged_at := now();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_stamp_order_acknowledged ON public.orders;
CREATE TRIGGER trg_stamp_order_acknowledged
  BEFORE UPDATE OF status ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.stamp_order_acknowledged();

-- 9. Realtime Publication & RLS -----------------------------------------------
ALTER TABLE public.system_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view system config" ON public.system_config;
CREATE POLICY "Anyone can view system config"
  ON public.system_config FOR SELECT
  TO anon, authenticated
  USING (true);

ALTER TABLE public.orders REPLICA IDENTITY FULL;
ALTER TABLE public.system_config REPLICA IDENTITY FULL;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'orders'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.orders;
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'system_config'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.system_config;
    END IF;
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

