-- Migration: Admin-controlled delivery fee configuration and audit history
--
-- Corrected subset of centralized_delivery_fee_system.sql, which was never
-- applied. Differences:
-- * Audit rows use the live audit_logs columns (actor_id, new_value,
--   metadata); the original wrote user_id / details, which do not exist, so
--   every admin fee save would have failed.
-- * The create_order_atomic replacement and the orders snapshot columns it
--   used are left out. Changing how every order is priced needs its own
--   review against the deployed create_order_atomic.
--
-- Before running, confirm system_config has (key, value, updated_at,
-- updated_by); this was written while the database was unreachable.

BEGIN;

-- 0. Ensure prerequisite tables, columns, indexes, and helper functions exist -
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

-- Ensure unique index on key so ON CONFLICT (key) never fails
CREATE UNIQUE INDEX IF NOT EXISTS system_config_key_idx ON public.system_config (key);

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

-- 1. Default configuration --------------------------------------------------
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

-- 2. Read the active configuration ------------------------------------------
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

-- 3. Fee for a distance under the active configuration ----------------------
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

-- 4. Admin: read, save, and audit history -----------------------------------
CREATE OR REPLACE FUNCTION public.admin_get_delivery_fee_config()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only administrators can view delivery fee configuration.'
      USING ERRCODE = '42501';
  END IF;
  RETURN public.get_delivery_fee_config();
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_delivery_fee_config(
  p_rate_per_km numeric,
  p_minimum_fee numeric,
  p_min_billable_distance_km numeric,
  p_rounding_rule text,
  p_enabled boolean,
  p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_old jsonb;
  v_val jsonb;
  v_admin_email text;
  v_admin_id uuid;
  v_rule text;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only administrators can update delivery fee settings.'
      USING ERRCODE = '42501';
  END IF;

  IF p_rate_per_km < 0 OR p_minimum_fee < 0 OR p_min_billable_distance_km < 0 THEN
    RAISE EXCEPTION 'Delivery fee values must not be negative.'
      USING ERRCODE = '22023';
  END IF;

  v_rule := lower(trim(coalesce(p_rounding_rule, 'exact')));
  IF v_rule NOT IN ('exact', 'ceil', 'round') THEN
    RAISE EXCEPTION 'Rounding rule must be exact, ceil, or round.'
      USING ERRCODE = '22023';
  END IF;

  v_admin_id := auth.uid();
  IF v_admin_id IS NOT NULL THEN
    SELECT email INTO v_admin_email FROM public.profiles WHERE id = v_admin_id;
  ELSE
    v_admin_email := 'admin@erefill.com';
  END IF;
  SELECT value INTO v_old FROM public.system_config WHERE key = 'delivery_fee_config';

  v_val := jsonb_build_object(
    'rate_per_km', p_rate_per_km,
    'minimum_fee', p_minimum_fee,
    'min_billable_distance_km', p_min_billable_distance_km,
    'rounding_rule', v_rule,
    'enabled', coalesce(p_enabled, true),
    'reason', p_reason,
    'updated_at', now(),
    'updated_by', v_admin_id,
    'updated_by_email', v_admin_email
  );

  INSERT INTO public.system_config (key, value, updated_at, updated_by)
  VALUES ('delivery_fee_config', v_val, now(), v_admin_id)
  ON CONFLICT (key) DO UPDATE
  SET value = EXCLUDED.value,
      updated_at = now(),
      updated_by = v_admin_id;

  INSERT INTO public.audit_logs
    (actor_id, action, entity_type, entity_id, old_value, new_value, metadata)
  VALUES (
    v_admin_id, 'set_delivery_fee_config', 'config', 'delivery_fee_config',
    v_old, v_val, jsonb_build_object('reason', p_reason)
  );

  RETURN v_val;
END;
$$;

-- Rows keep the field names the admin history list reads
-- (user_id, admin_email, admin_name, details, created_at).
CREATE OR REPLACE FUNCTION public.admin_get_delivery_fee_history(p_limit int DEFAULT 20)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_res jsonb;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only administrators can view delivery fee audit logs.'
      USING ERRCODE = '42501';
  END IF;

  SELECT coalesce(jsonb_agg(row_to_json(r)), '[]'::jsonb)
  INTO v_res
  FROM (
    SELECT
      a.id,
      a.actor_id AS user_id,
      p.email AS admin_email,
      p.full_name AS admin_name,
      a.new_value AS details,
      a.created_at
    FROM public.audit_logs a
    LEFT JOIN public.profiles p ON p.id = a.actor_id
    WHERE a.action = 'set_delivery_fee_config'
    ORDER BY a.created_at DESC
    LIMIT coalesce(p_limit, 20)
  ) r;

  RETURN v_res;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_get_delivery_fee_config() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_set_delivery_fee_config(numeric, numeric, numeric, text, boolean, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_get_delivery_fee_history(int) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.admin_get_delivery_fee_config() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_set_delivery_fee_config(numeric, numeric, numeric, text, boolean, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_get_delivery_fee_history(int) TO authenticated, service_role;

-- 5. RLS Policies & Realtime Publication -------------------------------------
ALTER TABLE public.system_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view system config" ON public.system_config;
CREATE POLICY "Anyone can view system config"
  ON public.system_config FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "Admins can manage system config" ON public.system_config;
CREATE POLICY "Admins can manage system config"
  ON public.system_config FOR ALL
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

ALTER TABLE public.system_config REPLICA IDENTITY FULL;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
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
