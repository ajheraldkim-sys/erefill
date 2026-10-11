-- ==============================================================================
-- eRefill Complete Admin Setup Migration
-- Idempotent script providing complete schema, tables, stored procedures,
-- and RLS policies for admin oversight, moderation, and operations.
-- ==============================================================================

-- 0. Ensure Profiles Columns
ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT timezone('utc'::text, now());

-- 1. System Config Table
CREATE TABLE IF NOT EXISTS public.system_config (
    key text PRIMARY KEY,
    value jsonb NOT NULL,
    updated_at timestamptz DEFAULT now(),
    updated_by uuid REFERENCES auth.users(id)
);

-- Seed default configuration if empty
INSERT INTO public.system_config (key, value)
VALUES
    ('maintenance_mode', 'false'::jsonb),
    ('allow_signups', 'true'::jsonb),
    ('platform_fee', '{"percent": 5.0, "fixed": 2.0, "enabled": true}'::jsonb),
    ('default_service_radius_km', '5.0'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- 2. Audit Logs Table
CREATE TABLE IF NOT EXISTS public.audit_logs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid REFERENCES auth.users(id),
    action text NOT NULL,
    entity_type text,
    entity_id text,
    details jsonb DEFAULT '{}'::jsonb,
    ip_address text,
    created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON public.audit_logs (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_user_id ON public.audit_logs (user_id);

-- 3. Security Definer Permission Checks
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_role text;
BEGIN
    SELECT role INTO v_role
    FROM public.profiles
    WHERE id = auth.uid();

    RETURN (v_role = 'admin');
END;
$$;

CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_role text;
BEGIN
    SELECT role INTO v_role
    FROM public.profiles
    WHERE id = auth.uid();

    RETURN (v_role = 'admin' OR v_role = 'super_admin');
END;
$$;

-- 4. Admin Dashboard Stats RPC
CREATE OR REPLACE FUNCTION public.admin_dashboard_stats()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_customers int := 0;
    v_owners int := 0;
    v_riders int := 0;
    v_admins int := 0;
    v_total_users int := 0;
    v_stations_count int := 0;
    v_open_stations int := 0;
    v_pending_stations int := 0;
    v_suspended_stations int := 0;
    v_orders_count int := 0;
    v_pending_orders int := 0;
    v_preparing_orders int := 0;
    v_out_for_delivery_orders int := 0;
    v_delivered_orders int := 0;
    v_cancelled_orders int := 0;
    v_total_gmv numeric := 0;
    v_today_gmv numeric := 0;
    v_maintenance boolean := false;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Only administrators can view dashboard statistics.'
            USING ERRCODE = '42501';
    END IF;

    -- User counts
    SELECT count(*) INTO v_customers FROM public.profiles WHERE role = 'customer';
    SELECT count(*) INTO v_owners FROM public.profiles WHERE role = 'owner';
    SELECT count(*) INTO v_riders FROM public.profiles WHERE role = 'rider';
    SELECT count(*) INTO v_admins FROM public.profiles WHERE role = 'admin';
    v_total_users := v_customers + v_owners + v_riders + v_admins;

    -- Station counts
    SELECT count(*) INTO v_stations_count FROM public.water_refill_stations;
    SELECT count(*) INTO v_open_stations FROM public.water_refill_stations WHERE is_accepting_orders = true;
    SELECT count(*) INTO v_pending_stations FROM public.water_refill_stations WHERE status IN ('pending', 'pending_verification');
    SELECT count(*) INTO v_suspended_stations FROM public.water_refill_stations WHERE status = 'suspended';

    -- Orders breakdown
    SELECT count(*) INTO v_orders_count FROM public.orders;
    SELECT count(*) INTO v_pending_orders FROM public.orders WHERE status = 'pending';
    SELECT count(*) INTO v_preparing_orders FROM public.orders WHERE status IN ('preparing', 'accepted');
    SELECT count(*) INTO v_out_for_delivery_orders FROM public.orders WHERE status IN ('out_for_delivery', 'assigned_to_rider');
    SELECT count(*) INTO v_delivered_orders FROM public.orders WHERE status = 'delivered';
    SELECT count(*) INTO v_cancelled_orders FROM public.orders WHERE status = 'cancelled';

    -- Financial GMV
    SELECT COALESCE(sum(total_amount), 0) INTO v_total_gmv FROM public.orders WHERE status = 'delivered';
    SELECT COALESCE(sum(total_amount), 0) INTO v_today_gmv FROM public.orders
        WHERE status = 'delivered' AND created_at >= date_trunc('day', now());

    -- Maintenance mode
    SELECT COALESCE((value->>'maintenance_mode')::boolean, (value)::boolean, false)
    INTO v_maintenance
    FROM public.system_config
    WHERE key = 'maintenance_mode';

    RETURN jsonb_build_object(
        'customers', v_customers,
        'owners', v_owners,
        'riders', v_riders,
        'admins', v_admins,
        'total_users', v_total_users,
        'stations_count', v_stations_count,
        'open_stations', v_open_stations,
        'pending_stations', v_pending_stations,
        'suspended_stations', v_suspended_stations,
        'orders_count', v_orders_count,
        'pending_orders', v_pending_orders,
        'preparing_orders', v_preparing_orders,
        'out_for_delivery_orders', v_out_for_delivery_orders,
        'delivered_orders', v_delivered_orders,
        'cancelled_orders', v_cancelled_orders,
        'total_gmv', v_total_gmv,
        'today_gmv', v_today_gmv,
        'maintenance_mode', COALESCE(v_maintenance, false)
    );
END;
$$;

-- 5. Admin Revenue Analytics RPC
CREATE OR REPLACE FUNCTION public.admin_revenue_analytics()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_total_revenue numeric := 0;
    v_series jsonb;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Only administrators can view revenue analytics.'
            USING ERRCODE = '42501';
    END IF;

    SELECT COALESCE(sum(total_amount), 0)
    INTO v_total_revenue
    FROM public.orders
    WHERE status = 'delivered';

    WITH daily AS (
        SELECT
            d::date AS dt,
            COALESCE(sum(o.total_amount), 0) AS daily_rev
        FROM generate_series(now() - interval '6 days', now(), '1 day'::interval) d
        LEFT JOIN public.orders o
            ON o.status = 'delivered'
            AND date_trunc('day', o.created_at) = date_trunc('day', d)
        GROUP BY 1
        ORDER BY 1
    )
    SELECT jsonb_agg(
        jsonb_build_object(
            'date', dt::text,
            'revenue', daily_rev
        )
    ) INTO v_series
    FROM daily;

    RETURN jsonb_build_object(
        'total_revenue', v_total_revenue,
        'platform_cut', round(v_total_revenue * 0.05, 2),
        'daily_series', COALESCE(v_series, '[]'::jsonb)
    );
END;
$$;

-- 6. Admin List Stations with Pagination & Filter
CREATE OR REPLACE FUNCTION public.admin_list_stations(
    p_limit int DEFAULT 50,
    p_offset int DEFAULT 0,
    p_search text DEFAULT NULL,
    p_region_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_total int;
    v_rows jsonb;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Only administrators can view stations.'
            USING ERRCODE = '42501';
    END IF;

    SELECT count(*) INTO v_total
    FROM public.water_refill_stations s
    WHERE (p_search IS NULL OR s.name ILIKE '%' || p_search || '%' OR s.town ILIKE '%' || p_search || '%')
      AND (p_region_id IS NULL OR lower(p_region_id) = 'all' OR lower(btrim(s.town)) = lower(btrim(p_region_id)));

    SELECT jsonb_agg(row_to_json(r)) INTO v_rows
    FROM (
        SELECT
            s.*,
            p.full_name AS owner_name,
            p.phone AS owner_phone,
            p.email AS owner_email
        FROM public.water_refill_stations s
        LEFT JOIN public.profiles p ON p.id = s.owner_id
        WHERE (p_search IS NULL OR s.name ILIKE '%' || p_search || '%' OR s.town ILIKE '%' || p_search || '%')
          AND (p_region_id IS NULL OR lower(p_region_id) = 'all' OR lower(btrim(s.town)) = lower(btrim(p_region_id)))
        ORDER BY s.created_at DESC
        LIMIT p_limit OFFSET p_offset
    ) r;

    RETURN jsonb_build_object(
        'total', v_total,
        'rows', COALESCE(v_rows, '[]'::jsonb)
    );
END;
$$;

-- 7. Admin List Users with Pagination & Filter
CREATE OR REPLACE FUNCTION public.admin_list_users(
    p_role text DEFAULT NULL,
    p_limit int DEFAULT 50,
    p_offset int DEFAULT 0,
    p_search text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_total int;
    v_rows jsonb;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Only administrators can view user accounts.'
            USING ERRCODE = '42501';
    END IF;

    SELECT count(*) INTO v_total
    FROM public.profiles p
    WHERE (p_role IS NULL OR p_role = 'all' OR p.role = p_role)
      AND (p_search IS NULL OR p.full_name ILIKE '%' || p_search || '%' OR p.email ILIKE '%' || p_search || '%' OR p.phone ILIKE '%' || p_search || '%');

    SELECT jsonb_agg(row_to_json(r)) INTO v_rows
    FROM (
        SELECT *
        FROM public.profiles p
        WHERE (p_role IS NULL OR p_role = 'all' OR p.role = p_role)
          AND (p_search IS NULL OR p.full_name ILIKE '%' || p_search || '%' OR p.email ILIKE '%' || p_search || '%' OR p.phone ILIKE '%' || p_search || '%')
        ORDER BY p.created_at DESC
        LIMIT p_limit OFFSET p_offset
    ) r;

    RETURN jsonb_build_object(
        'total', v_total,
        'rows', COALESCE(v_rows, '[]'::jsonb)
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_list_regions()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Only administrators can view municipalities.'
            USING ERRCODE = '42501';
    END IF;

    RETURN jsonb_build_array(
        jsonb_build_object('id', 'cantilan', 'name', 'Cantilan'),
        jsonb_build_object('id', 'madrid', 'name', 'Madrid')
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_list_orders(
    p_limit int DEFAULT 50,
    p_offset int DEFAULT 0,
    p_status text DEFAULT NULL,
    p_search text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_total int;
    v_rows jsonb;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Only administrators can view orders.'
            USING ERRCODE = '42501';
    END IF;

    SELECT count(*) INTO v_total
    FROM public.orders o
    WHERE (
        p_status IS NULL OR p_status = 'all'
        OR (p_status = 'pending' AND lower(o.status) = 'pending')
        OR (p_status = 'delivering' AND lower(o.status) IN (
            'accepted', 'preparing', 'ready_for_pickup', 'assigned_to_rider', 'out_for_delivery'
        ))
        OR (p_status = 'delivered' AND lower(o.status) = 'delivered')
        OR (p_status = 'cancelled' AND lower(o.status) IN ('cancelled', 'failed'))
    )
    AND (
        p_search IS NULL OR btrim(p_search) = ''
        OR o.id::text ILIKE '%' || btrim(p_search) || '%'
        OR COALESCE(o.station_name, '') ILIKE '%' || btrim(p_search) || '%'
        OR COALESCE(o.customer_name, '') ILIKE '%' || btrim(p_search) || '%'
    );

    SELECT jsonb_agg(row_to_json(r)) INTO v_rows
    FROM (
        SELECT o.*
        FROM public.orders o
        WHERE (
            p_status IS NULL OR p_status = 'all'
            OR (p_status = 'pending' AND lower(o.status) = 'pending')
            OR (p_status = 'delivering' AND lower(o.status) IN (
                'accepted', 'preparing', 'ready_for_pickup', 'assigned_to_rider', 'out_for_delivery'
            ))
            OR (p_status = 'delivered' AND lower(o.status) = 'delivered')
            OR (p_status = 'cancelled' AND lower(o.status) IN ('cancelled', 'failed'))
        )
        AND (
            p_search IS NULL OR btrim(p_search) = ''
            OR o.id::text ILIKE '%' || btrim(p_search) || '%'
            OR COALESCE(o.station_name, '') ILIKE '%' || btrim(p_search) || '%'
            OR COALESCE(o.customer_name, '') ILIKE '%' || btrim(p_search) || '%'
        )
        ORDER BY o.created_at DESC, o.id DESC
        LIMIT greatest(0, least(COALESCE(p_limit, 50), 200))
        OFFSET greatest(0, COALESCE(p_offset, 0))
    ) r;

    RETURN jsonb_build_object(
        'total', v_total,
        'rows', COALESCE(v_rows, '[]'::jsonb)
    );
END;
$$;

-- 8. Admin Moderation & Control Functions
CREATE OR REPLACE FUNCTION public.admin_set_station_availability(
    p_owner_id uuid,
    p_availability text,
    p_reason text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Only administrators can change station availability.'
            USING ERRCODE = '42501';
    END IF;

    IF p_availability NOT IN ('open', 'busy', 'closed', 'maintenance', 'suspended') THEN
        RAISE EXCEPTION 'Unsupported station availability: %', p_availability
            USING ERRCODE = '22023';
    END IF;

    UPDATE public.water_refill_stations
    SET is_accepting_orders = (p_availability = 'open'),
        updated_at = now()
    WHERE owner_id = p_owner_id;

    INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, details)
    VALUES (
        auth.uid(),
        'set_station_availability',
        'station',
        p_owner_id::text,
        jsonb_build_object('availability', p_availability, 'reason', p_reason)
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_suspend_user(
    p_user_id uuid,
    p_reason text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Only administrators can suspend users.'
            USING ERRCODE = '42501';
    END IF;

    UPDATE public.profiles
    SET is_suspended = true,
        suspended_reason = COALESCE(p_reason, 'Suspended by admin'),
        updated_at = now()
    WHERE id = p_user_id;

    INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, details)
    VALUES (
        auth.uid(),
        'suspend_user',
        'user',
        p_user_id::text,
        jsonb_build_object('reason', p_reason)
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_unsuspend_user(
    p_user_id uuid,
    p_reason text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Only administrators can reactivate users.'
            USING ERRCODE = '42501';
    END IF;

    UPDATE public.profiles
    SET is_suspended = false,
        suspended_reason = NULL,
        updated_at = now()
    WHERE id = p_user_id;

    INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, details)
    VALUES (
        auth.uid(),
        'unsuspend_user',
        'user',
        p_user_id::text,
        jsonb_build_object('reason', p_reason)
    );
END;
$$;

-- 9. Admin Platform Fee RPCs
CREATE OR REPLACE FUNCTION public.admin_get_platform_fee()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_val jsonb;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Only administrators can view platform fee settings.'
            USING ERRCODE = '42501';
    END IF;

    SELECT value INTO v_val FROM public.system_config WHERE key = 'platform_fee';
    RETURN COALESCE(v_val, '{"percent": 5.0, "fixed": 2.0, "enabled": true}'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_platform_fee(
    p_percent numeric,
    p_fixed numeric,
    p_enabled boolean,
    p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_val jsonb;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Only administrators can update platform fee settings.'
            USING ERRCODE = '42501';
    END IF;

    IF p_percent < 0 OR p_fixed < 0 THEN
        RAISE EXCEPTION 'Platform fee values must not be negative.'
            USING ERRCODE = '22023';
    END IF;

    v_val := jsonb_build_object(
        'percent', p_percent,
        'fixed', p_fixed,
        'enabled', p_enabled,
        'reason', p_reason,
        'updated_at', now()
    );

    INSERT INTO public.system_config (key, value, updated_at, updated_by)
    VALUES ('platform_fee', v_val, now(), auth.uid())
    ON CONFLICT (key) DO UPDATE
    SET value = EXCLUDED.value,
        updated_at = now(),
        updated_by = auth.uid();

    INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, details)
    VALUES (auth.uid(), 'set_platform_fee', 'config', 'platform_fee', v_val);

    RETURN v_val;
END;
$$;

-- SECURITY DEFINER functions are executable by PUBLIC unless explicitly
-- restricted. Expose admin RPCs only to authenticated callers and retain
-- their in-function is_admin() checks as the authorization boundary.
REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_super_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_super_admin() TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.admin_dashboard_stats() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_revenue_analytics() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_list_stations(int, int, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_list_users(text, int, int, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_list_regions() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_list_orders(int, int, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_set_station_availability(uuid, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_suspend_user(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_unsuspend_user(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_get_platform_fee() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_set_platform_fee(numeric, numeric, boolean, text) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.admin_dashboard_stats() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_revenue_analytics() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_list_stations(int, int, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_list_users(text, int, int, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_list_regions() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_list_orders(int, int, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_set_station_availability(uuid, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_suspend_user(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_unsuspend_user(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_get_platform_fee() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_set_platform_fee(numeric, numeric, boolean, text) TO authenticated, service_role;
