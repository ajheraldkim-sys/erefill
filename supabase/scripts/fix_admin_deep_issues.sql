-- ==============================================================================
-- eRefill Admin Deep Issues Fix Migration
-- Fixes:
-- 1. RLS policies on system_config allowing admins to manage configurations.
-- 2. RLS policies on profiles allowing admins to update profiles (e.g. suspend/reactivate).
-- 3. Harmonize get_platform_fee_config() to support both composite object and discrete rows.
-- 4. Guard create_order_atomic() against maintenance mode and user/station suspensions.
-- ==============================================================================

-- 1. Enable RLS and add admin management policy on system_config
ALTER TABLE public.system_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can manage system config" ON public.system_config;
CREATE POLICY "Admins can manage system config"
ON public.system_config FOR ALL
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- Ensure system_config is viewable by authenticated users
DROP POLICY IF EXISTS "System config is viewable by all authenticated users" ON public.system_config;
CREATE POLICY "System config is viewable by all authenticated users"
ON public.system_config FOR SELECT
TO authenticated
USING (true);

-- 2. Add policy for Admins to update profiles (suspend, reactivate, reason)
DROP POLICY IF EXISTS "Admins can update all profiles" ON public.profiles;
CREATE POLICY "Admins can update all profiles"
ON public.profiles FOR UPDATE
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- 3. Harmonize get_platform_fee_config()
CREATE OR REPLACE FUNCTION public.get_platform_fee_config()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_obj jsonb;
  v_enabled boolean := false;
  v_percent numeric := 0;
  v_fixed numeric := 0;
BEGIN
  -- First check composite object 'platform_fee'
  SELECT value INTO v_obj FROM public.system_config WHERE key = 'platform_fee';
  IF v_obj IS NOT NULL AND jsonb_typeof(v_obj) = 'object' THEN
    v_enabled := coalesce((v_obj->>'enabled')::boolean, true);
    v_percent := coalesce((v_obj->>'percent')::numeric, 0);
    v_fixed := coalesce((v_obj->>'fixed')::numeric, 0);
    
    RETURN jsonb_build_object(
      'enabled', v_enabled,
      'percent', v_percent,
      'fixed', v_fixed
    );
  END IF;

  -- Fallback to discrete keys if composite object is absent
  RETURN jsonb_build_object(
    'enabled', coalesce((
      SELECT CASE
        WHEN jsonb_typeof(value) = 'boolean' THEN (value)::text::boolean
        WHEN jsonb_typeof(value) = 'string' THEN lower(trim(both '"' from value::text)) IN ('true', '1', 'yes')
        ELSE false
      END
      FROM public.system_config WHERE key = 'platform_fee_enabled'
    ), false),
    'percent', coalesce((
      SELECT CASE
        WHEN jsonb_typeof(value) = 'number' THEN (value)::text::numeric
        ELSE nullif(trim(both '"' from value::text), '')::numeric
      END
      FROM public.system_config WHERE key = 'platform_fee_percent'
    ), 0),
    'fixed', coalesce((
      SELECT CASE
        WHEN jsonb_typeof(value) = 'number' THEN (value)::text::numeric
        ELSE nullif(trim(both '"' from value::text), '')::numeric
      END
      FROM public.system_config WHERE key = 'platform_fee_fixed'
    ), 0)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_platform_fee_config() TO authenticated, anon;

-- 4. Guard create_order_atomic() with maintenance mode and suspension checks
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
  v_order_id uuid;
  v_item record;
  v_product record;
  v_computed_subtotal numeric(10,2) := 0;
  v_delivery_fee numeric(10,2) := 0;
  v_total_amount numeric(10,2) := 0;
  v_order_row public.orders%ROWTYPE;
  v_lat double precision;
  v_lng double precision;
  v_maintenance jsonb;
  v_is_maintenance boolean := false;
  v_customer_suspended boolean := false;
  v_owner_suspended boolean := false;
BEGIN
  -- 0. Check System Maintenance Mode
  SELECT value INTO v_maintenance FROM public.system_config WHERE key = 'maintenance_mode';
  IF v_maintenance IS NOT NULL THEN
    IF jsonb_typeof(v_maintenance) = 'boolean' THEN
      v_is_maintenance := v_maintenance::text::boolean;
    ELSIF jsonb_typeof(v_maintenance) = 'string' THEN
      v_is_maintenance := lower(trim(both '"' from v_maintenance::text)) IN ('true', '1', 'yes');
    END IF;
  END IF;

  IF v_is_maintenance THEN
    RAISE EXCEPTION 'System is currently undergoing maintenance. New orders are temporarily paused.';
  END IF;

  -- 1. Check Customer Authentication & Suspension
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

  v_owner_id := (p_order_data->>'owner_id')::uuid;
  v_payment_method := lower(trim(coalesce(p_order_data->>'payment_method', 'cod')));
  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'Station owner ID is required.';
  END IF;

  -- 2. Verify owner station exists, is not suspended, and is open
  SELECT coalesce(is_suspended, false) INTO v_owner_suspended
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
    WHERE id = v_owner_id AND role = 'owner' AND coalesce(station_availability, 'open') = 'open'
  ) THEN
    RAISE EXCEPTION 'This water station is currently closed or unavailable.';
  END IF;

  IF NOT public.is_station_payment_method_available(v_owner_id, v_payment_method) THEN
    RAISE EXCEPTION 'This payment method is not available for this station.';
  END IF;

  -- 3. Verify line items against products catalog
  FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items_data) AS x(
    product_id uuid,
    quantity integer,
    product_name text
  )
  LOOP
    IF v_item.quantity <= 0 THEN
      RAISE EXCEPTION 'Invalid quantity for item %', v_item.product_name;
    END IF;

    SELECT * INTO v_product FROM public.products
    WHERE id = v_item.product_id AND owner_id = v_owner_id AND is_available = true;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Product % is unavailable at this station.', v_item.product_name;
    END IF;

    v_computed_subtotal := v_computed_subtotal + (v_product.price * v_item.quantity);
  END LOOP;

  IF v_computed_subtotal <= 0 THEN
    RAISE EXCEPTION 'Cart cannot be empty.';
  END IF;

  -- 4. Get server-side base delivery fee from owner_settings
  SELECT coalesce(base_delivery_fee, 0) INTO v_delivery_fee
  FROM public.owner_settings WHERE owner_id = v_owner_id;

  -- 5. Calculate server-verified total amount
  v_total_amount := v_computed_subtotal + v_delivery_fee;
  
  v_lat := (p_order_data->>'customer_latitude')::double precision;
  v_lng := (p_order_data->>'customer_longitude')::double precision;

  -- 6. Insert order
  INSERT INTO public.orders (
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
    v_customer_id,
    v_owner_id,
    coalesce(p_order_data->>'station_name', 'Water Station'),
    p_order_data->>'customer_name',
    p_order_data->>'customer_phone',
    p_order_data->>'customer_address',
    p_order_data->>'customer_barangay',
    p_order_data->>'customer_municipality',
    p_order_data->>'customer_landmark',
    NULLIF(p_order_data->>'idempotency_key', '')::uuid,
    v_computed_subtotal,
    v_delivery_fee,
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
  RETURNING * INTO v_order_row;

  v_order_id := v_order_row.id;

  -- 7. Insert order items with correct column name price_at_purchase
  FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items_data) AS x(
    product_id uuid,
    quantity integer,
    product_name text
  )
  LOOP
    SELECT * INTO v_product FROM public.products WHERE id = v_item.product_id;

    INSERT INTO public.order_items (
      order_id,
      product_id,
      product_name,
      quantity,
      price_at_purchase,
      subtotal
    ) VALUES (
      v_order_id,
      v_item.product_id,
      v_product.name,
      v_item.quantity,
      v_product.price,
      (v_product.price * v_item.quantity)
    );
  END LOOP;

  -- 8. Notify Station Owner of incoming refill order
  INSERT INTO public.system_notifications (
    user_id,
    type,
    priority,
    title,
    content,
    metadata
  ) VALUES (
    v_owner_id,
    'system_alert',
    'high',
    'New Refill Order',
    coalesce(p_order_data->>'customer_name', 'A customer') || ' placed a new refill order of PHP ' || trim(to_char(v_total_amount, '999999990.00')) || ' (' || upper(coalesce(p_order_data->>'payment_method', 'cod')) || ').',
    jsonb_build_object('order_id', v_order_id, 'status', 'pending', 'total_amount', v_total_amount)
  );

  RETURN jsonb_build_object(
    'id', v_order_id,
    'total_amount', v_total_amount,
    'status', 'pending'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_order_atomic(jsonb, jsonb) TO authenticated;

