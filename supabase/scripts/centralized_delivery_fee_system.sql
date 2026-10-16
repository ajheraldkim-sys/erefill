-- ==============================================================================
-- Centralized Delivery Fee Management System (Admin-Controlled)
-- ==============================================================================
-- 1. Ensure public.orders has historical snapshot columns for distance & rate
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS delivery_distance_km numeric(10, 2);
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS delivery_rate_per_km numeric(10, 2);

-- 2. Seed default delivery fee configuration in public.system_config
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

-- 3. Public / Authenticated read RPC for active delivery fee configuration
CREATE OR REPLACE FUNCTION public.get_delivery_fee_config()
RETURNS jsonb
LANGUAGE plpgsql
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
        -- Fallback default
        v_cfg := jsonb_build_object(
            'enabled', true,
            'rate_per_km', 10.0,
            'minimum_fee', 20.0,
            'min_billable_distance_km', 1.0,
            'rounding_rule', 'exact'
        );
    END IF;

    -- Attach updated_by email if updated_by uuid exists
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

-- 4. Authoritative Delivery Fee Calculator Function
CREATE OR REPLACE FUNCTION public.calculate_delivery_fee(p_distance_km numeric)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_cfg jsonb;
    v_enabled boolean;
    v_rate numeric;
    v_min_fee numeric;
    v_min_dist numeric;
    v_rule text;
    v_dist numeric;
    v_fee numeric;
BEGIN
    v_cfg := public.get_delivery_fee_config();
    v_enabled := coalesce((v_cfg->>'enabled')::boolean, true);
    IF NOT v_enabled THEN
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

-- 5. Admin-only RPCs for inspecting & saving delivery fee policy
CREATE OR REPLACE FUNCTION public.admin_get_delivery_fee_config()
RETURNS jsonb
LANGUAGE plpgsql
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
    v_val jsonb;
    v_admin_email text;
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

    SELECT email INTO v_admin_email
    FROM public.profiles
    WHERE id = auth.uid();

    v_val := jsonb_build_object(
        'rate_per_km', p_rate_per_km,
        'minimum_fee', p_minimum_fee,
        'min_billable_distance_km', p_min_billable_distance_km,
        'rounding_rule', v_rule,
        'enabled', coalesce(p_enabled, true),
        'reason', p_reason,
        'updated_at', now(),
        'updated_by', auth.uid(),
        'updated_by_email', v_admin_email
    );

    INSERT INTO public.system_config (key, value, updated_at, updated_by)
    VALUES ('delivery_fee_config', v_val, now(), auth.uid())
    ON CONFLICT (key) DO UPDATE
    SET value = EXCLUDED.value,
        updated_at = now(),
        updated_by = auth.uid();

    INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, details)
    VALUES (auth.uid(), 'set_delivery_fee_config', 'config', 'delivery_fee_config', v_val);

    RETURN v_val;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_get_delivery_fee_history(p_limit int DEFAULT 20)
RETURNS jsonb
LANGUAGE plpgsql
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
            a.user_id,
            p.email AS admin_email,
            p.full_name AS admin_name,
            a.details,
            a.created_at
        FROM public.audit_logs a
        LEFT JOIN public.profiles p ON p.id = a.user_id
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

-- 6. Updated Authoritative create_order_atomic() using Centralized Delivery Fee Calculation
CREATE OR REPLACE FUNCTION public.create_order_atomic(
  p_order_data jsonb,
  p_items_data jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_id uuid := auth.uid();
  v_owner_id uuid;
  v_payment_method text;
  v_idempotency_key public.orders.idempotency_key%TYPE;
  v_voucher_id uuid;
  v_order_id uuid;
  v_item record;
  v_product record;
  v_computed_subtotal numeric(10,2) := 0;
  v_delivery_fee numeric(10,2) := 0;
  v_platform_fee numeric(10,2) := 0;
  v_discount numeric(10,2) := 0;
  v_total_amount numeric(10,2) := 0;
  v_order_row public.orders%ROWTYPE;
  v_voucher public.customer_reward_vouchers%ROWTYPE;
  v_config jsonb;
  v_deliv_cfg jsonb;
  v_lat double precision;
  v_lng double precision;
  v_station_lat double precision;
  v_station_lng double precision;
  v_cosine_argument double precision;
  v_distance_km numeric(10,2) := 1.00;
  v_client_distance numeric(10,2);
  v_rate_per_km numeric(10,2) := 10.00;
  v_maintenance jsonb;
  v_is_maintenance boolean := false;
  v_customer_suspended boolean := false;
  v_owner_suspended boolean := false;
BEGIN
  -- 1. Check system maintenance mode
  SELECT value INTO v_maintenance
  FROM public.system_config
  WHERE key = 'maintenance_mode';

  IF v_maintenance IS NOT NULL THEN
    IF jsonb_typeof(v_maintenance) = 'boolean' THEN
      v_is_maintenance := v_maintenance::text::boolean;
    ELSIF jsonb_typeof(v_maintenance) = 'string' THEN
      v_is_maintenance :=
        lower(trim(both '"' from v_maintenance::text)) IN ('true', '1', 'yes');
    END IF;
  END IF;

  IF v_is_maintenance THEN
    RAISE EXCEPTION 'System is currently undergoing maintenance. New orders are temporarily paused.';
  END IF;

  -- 2. Verify customer authentication and account status
  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required to place an order.';
  END IF;

  SELECT coalesce(is_suspended, false) INTO v_customer_suspended
  FROM public.profiles
  WHERE id = v_customer_id AND role = 'customer';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Only customer accounts can place orders.';
  END IF;
  IF v_customer_suspended THEN
    RAISE EXCEPTION 'Your account has been suspended. Please contact customer support.';
  END IF;

  -- 3. Idempotency check
  v_idempotency_key := NULLIF(p_order_data->>'idempotency_key', '');
  IF v_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_order_row
    FROM public.orders
    WHERE customer_id = v_customer_id
      AND idempotency_key = v_idempotency_key;

    IF FOUND THEN
      RETURN jsonb_build_object(
        'id', v_order_row.id,
        'subtotal', v_order_row.subtotal,
        'delivery_fee', v_order_row.delivery_fee,
        'delivery_distance_km', v_order_row.delivery_distance_km,
        'delivery_rate_per_km', v_order_row.delivery_rate_per_km,
        'platform_fee', v_order_row.platform_fee,
        'total_amount', v_order_row.total_amount,
        'status', v_order_row.status
      );
    END IF;
  END IF;

  -- 4. Verify station and payment availability
  v_owner_id := NULLIF(p_order_data->>'owner_id', '')::uuid;
  v_payment_method := lower(trim(coalesce(p_order_data->>'payment_method', 'cod')));
  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'Station owner ID is required.';
  END IF;

  SELECT
    coalesce(is_suspended, false),
    latitude,
    longitude
  INTO
    v_owner_suspended,
    v_station_lat,
    v_station_lng
  FROM public.profiles
  WHERE id = v_owner_id AND role = 'owner';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Water refill station not found.';
  END IF;
  IF v_owner_suspended THEN
    RAISE EXCEPTION 'This water station is currently suspended by administration.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = v_owner_id
      AND role = 'owner'
      AND coalesce(station_availability, 'open') = 'open'
  ) THEN
    RAISE EXCEPTION 'This water station is currently closed or unavailable.';
  END IF;
  IF NOT public.is_station_payment_method_available(v_owner_id, v_payment_method) THEN
    RAISE EXCEPTION 'This payment method is not available for this station.';
  END IF;

  -- 5. Calculate verified items subtotal
  FOR v_item IN
    SELECT * FROM jsonb_to_recordset(p_items_data) AS x(
      product_id uuid,
      quantity integer,
      product_name text
    )
  LOOP
    IF v_item.quantity <= 0 THEN
      RAISE EXCEPTION 'Invalid quantity for item %', v_item.product_name;
    END IF;

    SELECT * INTO v_product
    FROM public.products
    WHERE id = v_item.product_id
      AND owner_id = v_owner_id
      AND is_available = true;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Product % is unavailable at this station.', v_item.product_name;
    END IF;

    v_computed_subtotal :=
      v_computed_subtotal + (v_product.price * v_item.quantity);
  END LOOP;

  IF v_computed_subtotal <= 0 THEN
    RAISE EXCEPTION 'Cart cannot be empty.';
  END IF;

  -- 6. Calculate Centralized Delivery Fee (Admin-Controlled)
  v_lat := NULLIF(p_order_data->>'customer_latitude', '')::double precision;
  v_lng := NULLIF(p_order_data->>'customer_longitude', '')::double precision;

  IF v_lat IS NOT NULL AND v_lng IS NOT NULL AND v_station_lat IS NOT NULL AND v_station_lng IS NOT NULL THEN
    v_cosine_argument :=
      cos(radians(v_lat)) * cos(radians(v_station_lat)) *
      cos(radians(v_station_lng) - radians(v_lng)) +
      sin(radians(v_lat)) * sin(radians(v_station_lat));
    v_distance_km := round((6371 * acos(LEAST(1.0::double precision, GREATEST(-1.0::double precision, v_cosine_argument))))::numeric, 2);
  ELSE
    v_distance_km := coalesce(NULLIF(p_order_data->>'delivery_distance_km', '')::numeric, 1.00);
  END IF;

  -- If client provided actual routed road distance, accept if valid
  v_client_distance := NULLIF(p_order_data->>'delivery_distance_km', '')::numeric;
  IF v_client_distance IS NOT NULL AND v_client_distance >= 0.05 AND v_client_distance <= 100.0 THEN
    v_distance_km := round(v_client_distance, 2);
  END IF;

  v_deliv_cfg := public.get_delivery_fee_config();
  v_rate_per_km := coalesce((v_deliv_cfg->>'rate_per_km')::numeric, 10.00);
  v_delivery_fee := public.calculate_delivery_fee(v_distance_km);

  -- 7. Calculate platform fee
  v_config := public.get_platform_fee_config();
  IF coalesce((v_config->>'enabled')::boolean, false) THEN
    v_platform_fee := round(
      ((v_computed_subtotal + v_delivery_fee)
        * coalesce((v_config->>'percent')::numeric, 0) / 100)
        + coalesce((v_config->>'fixed')::numeric, 0),
      2
    );
    v_platform_fee := greatest(v_platform_fee, 0);
  END IF;

  -- 8. Calculate voucher discount if applied
  v_voucher_id := NULLIF(p_order_data->>'voucher_id', '')::uuid;
  IF v_voucher_id IS NOT NULL THEN
    SELECT * INTO v_voucher
    FROM public.customer_reward_vouchers
    WHERE id = v_voucher_id
      AND user_id = v_customer_id
      AND is_used = false
      AND expires_at > now()
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'This reward voucher is no longer available. Refresh your vouchers and try again.';
    END IF;

    IF v_voucher.is_delivery_discount THEN
      v_discount := least(
        greatest(v_voucher.discount_amount, 0),
        v_delivery_fee
      );
    ELSE
      v_discount := least(
        greatest(v_voucher.discount_amount, 0),
        v_computed_subtotal + v_delivery_fee + v_platform_fee
      );
    END IF;
  END IF;

  -- 9. Authoritative total
  v_total_amount := greatest(
    v_computed_subtotal + v_delivery_fee + v_platform_fee - v_discount,
    0
  );

  -- 10. Insert snapshot order
  INSERT INTO public.orders (
    id,
    customer_id,
    owner_id,
    station_name,
    customer_name,
    customer_phone,
    customer_address,
    customer_barangay,
    customer_municipality,
    customer_landmark,
    idempotency_key,
    subtotal,
    delivery_fee,
    delivery_distance_km,
    delivery_rate_per_km,
    platform_fee,
    total_amount,
    payment_method,
    payment_status,
    notes,
    region_id,
    customer_latitude,
    customer_longitude,
    delivery_lat,
    delivery_lng,
    delivery_latitude,
    delivery_longitude,
    items,
    status
  ) VALUES (
    coalesce(
      NULLIF(p_order_data->>'id', '')::uuid,
      gen_random_uuid()
    ),
    v_customer_id,
    v_owner_id,
    coalesce(p_order_data->>'station_name', 'Water Station'),
    p_order_data->>'customer_name',
    p_order_data->>'customer_phone',
    p_order_data->>'customer_address',
    p_order_data->>'customer_barangay',
    p_order_data->>'customer_municipality',
    p_order_data->>'customer_landmark',
    v_idempotency_key,
    v_computed_subtotal,
    v_delivery_fee,
    v_distance_km,
    v_rate_per_km,
    v_platform_fee,
    v_total_amount,
    v_payment_method,
    'pending',
    p_order_data->>'notes',
    NULLIF(p_order_data->>'region_id', '')::uuid,
    v_lat,
    v_lng,
    v_lat,
    v_lng,
    v_lat,
    v_lng,
    coalesce(p_items_data, '[]'::jsonb),
    'pending'
  )
  ON CONFLICT DO NOTHING
  RETURNING * INTO v_order_row;

  IF NOT FOUND THEN
    IF v_idempotency_key IS NOT NULL THEN
      SELECT * INTO v_order_row
      FROM public.orders
      WHERE customer_id = v_customer_id
        AND idempotency_key = v_idempotency_key;
    END IF;

    IF v_order_row.id IS NULL THEN
      RAISE EXCEPTION 'Could not record order. Please retry.';
    END IF;

    RETURN jsonb_build_object(
      'id', v_order_row.id,
      'subtotal', v_order_row.subtotal,
      'delivery_fee', v_order_row.delivery_fee,
      'delivery_distance_km', v_order_row.delivery_distance_km,
      'delivery_rate_per_km', v_order_row.delivery_rate_per_km,
      'platform_fee', v_order_row.platform_fee,
      'total_amount', v_order_row.total_amount,
      'status', v_order_row.status
    );
  END IF;

  -- 11. Mark voucher as used if applied
  IF v_voucher_id IS NOT NULL THEN
    UPDATE public.customer_reward_vouchers
    SET
      is_used = true,
      used_at = now(),
      used_order_id = v_order_row.id
    WHERE id = v_voucher_id;
  END IF;

  RETURN jsonb_build_object(
    'id', v_order_row.id,
    'subtotal', v_order_row.subtotal,
    'delivery_fee', v_order_row.delivery_fee,
    'delivery_distance_km', v_order_row.delivery_distance_km,
    'delivery_rate_per_km', v_order_row.delivery_rate_per_km,
    'platform_fee', v_order_row.platform_fee,
    'total_amount', v_order_row.total_amount,
    'status', v_order_row.status
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_order_atomic(jsonb, jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.create_order_atomic(jsonb, jsonb) FROM PUBLIC, anon;

