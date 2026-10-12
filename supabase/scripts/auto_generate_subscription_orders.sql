-- ============================================================================
-- eRefill Auto-Order Generation Engine & Subscriptions Schema
-- File: supabase/scripts/auto_generate_subscription_orders.sql
-- Description:
--   1. Creates `customer_subscriptions` table, indexes, and RLS policies.
--   2. Ensures `order_items` and `orders` support routine recurring refills.
--   3. Defines `process_due_customer_subscriptions()` engine for automated orders.
-- ============================================================================

-- 1. Create customer_subscriptions table
CREATE TABLE IF NOT EXISTS public.customer_subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    station_id UUID NOT NULL,
    station_name TEXT NOT NULL,
    station_photo_url TEXT,
    quantity INT NOT NULL DEFAULT 1 CHECK (quantity > 0),
    water_type TEXT NOT NULL DEFAULT 'Purified',
    estimated_price NUMERIC(10,2) NOT NULL DEFAULT 30.00 CHECK (estimated_price >= 0),
    frequency TEXT NOT NULL DEFAULT 'weekly',
    preferred_time_slot TEXT NOT NULL DEFAULT 'morning',
    delivery_address TEXT NOT NULL,
    payment_method TEXT NOT NULL DEFAULT 'cod',
    is_active BOOLEAN NOT NULL DEFAULT true,
    next_delivery_date TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '7 days'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_customer_subscriptions_customer 
    ON public.customer_subscriptions(customer_id);

CREATE INDEX IF NOT EXISTS idx_customer_subscriptions_station 
    ON public.customer_subscriptions(station_id);

CREATE INDEX IF NOT EXISTS idx_customer_subscriptions_due 
    ON public.customer_subscriptions(is_active, next_delivery_date);

-- Enable RLS
ALTER TABLE public.customer_subscriptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own subscriptions" ON public.customer_subscriptions;
CREATE POLICY "Users can view own subscriptions"
    ON public.customer_subscriptions FOR SELECT
    USING (auth.uid() = customer_id OR auth.uid() = station_id);

DROP POLICY IF EXISTS "Users can create own subscriptions" ON public.customer_subscriptions;
CREATE POLICY "Users can create own subscriptions"
    ON public.customer_subscriptions FOR INSERT
    WITH CHECK (auth.uid() = customer_id);

DROP POLICY IF EXISTS "Users can update own subscriptions" ON public.customer_subscriptions;
CREATE POLICY "Users can update own subscriptions"
    ON public.customer_subscriptions FOR UPDATE
    USING (auth.uid() = customer_id OR auth.uid() = station_id);

DROP POLICY IF EXISTS "Users can delete own subscriptions" ON public.customer_subscriptions;
CREATE POLICY "Users can delete own subscriptions"
    ON public.customer_subscriptions FOR DELETE
    USING (auth.uid() = customer_id);

GRANT ALL ON TABLE public.customer_subscriptions TO authenticated, service_role;

-- 2. Ensure schema compatibility on orders & order_items
ALTER TABLE public.orders ALTER COLUMN idempotency_key TYPE text;

ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS water_type text;
ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS unit_price numeric(10,2);
ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS price_per_gallon numeric(10,2);
ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS total_price numeric(10,2);

-- 3. Stored procedure to process due subscriptions
CREATE OR REPLACE FUNCTION public.process_due_customer_subscriptions()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    sub RECORD;
    v_order_id UUID;
    v_date_str TEXT;
    v_idempotency_key TEXT;
    v_next_date TIMESTAMPTZ;
    v_orders_created INT := 0;
    v_unit_price NUMERIC;
BEGIN
    v_date_str := to_char(CURRENT_DATE, 'YYYY-MM-DD');

    FOR sub IN
        SELECT *
        FROM public.customer_subscriptions
        WHERE is_active = true
          AND next_delivery_date <= NOW() + INTERVAL '1 hour'
    LOOP
        v_idempotency_key := 'auto_sub_' || sub.id || '_' || v_date_str;

        -- Check if order was already generated for this cycle
        IF NOT EXISTS (
            SELECT 1 FROM public.orders WHERE idempotency_key = v_idempotency_key
        ) THEN
            v_order_id := gen_random_uuid();
            v_unit_price := CASE 
                WHEN sub.quantity > 0 THEN ROUND(sub.estimated_price / sub.quantity, 2)
                ELSE sub.estimated_price 
            END;

            -- 1. Insert order
            INSERT INTO public.orders (
                id,
                customer_id,
                owner_id,
                station_name,
                customer_address,
                idempotency_key,
                subtotal,
                delivery_fee,
                total_amount,
                payment_method,
                status,
                notes,
                items,
                created_at,
                updated_at
            ) VALUES (
                v_order_id,
                sub.customer_id,
                sub.station_id,
                sub.station_name,
                sub.delivery_address,
                v_idempotency_key,
                sub.estimated_price,
                0.00,
                sub.estimated_price,
                sub.payment_method,
                'pending',
                'Auto-Refill Routine (' || sub.frequency || ') - Slot: ' || sub.preferred_time_slot,
                jsonb_build_array(jsonb_build_object(
                    'product_name', sub.water_type || ' Refill',
                    'quantity', sub.quantity,
                    'price', v_unit_price,
                    'total_price', sub.estimated_price
                )),
                NOW(),
                NOW()
            );

            -- 2. Insert line item
            INSERT INTO public.order_items (
                order_id,
                product_name,
                water_type,
                quantity,
                unit_price,
                price_per_gallon,
                total_price,
                price_at_purchase,
                subtotal
            ) VALUES (
                v_order_id,
                sub.water_type || ' Refill',
                sub.water_type,
                sub.quantity,
                v_unit_price,
                v_unit_price,
                sub.estimated_price,
                v_unit_price,
                sub.estimated_price
            );

            v_orders_created := v_orders_created + 1;
        END IF;

        -- 3. Calculate next delivery date
        v_next_date := CASE sub.frequency
            WHEN 'every_3_days' THEN sub.next_delivery_date + INTERVAL '3 days'
            WHEN 'twice_weekly' THEN sub.next_delivery_date + INTERVAL '4 days'
            WHEN 'weekly'       THEN sub.next_delivery_date + INTERVAL '7 days'
            WHEN 'bi_weekly'    THEN sub.next_delivery_date + INTERVAL '14 days'
            WHEN 'monthly'      THEN sub.next_delivery_date + INTERVAL '1 month'
            ELSE sub.next_delivery_date + INTERVAL '7 days'
        END;

        -- Ensure next delivery date advances into future
        WHILE v_next_date <= NOW() LOOP
            v_next_date := CASE sub.frequency
                WHEN 'every_3_days' THEN v_next_date + INTERVAL '3 days'
                WHEN 'twice_weekly' THEN v_next_date + INTERVAL '4 days'
                WHEN 'weekly'       THEN v_next_date + INTERVAL '7 days'
                WHEN 'bi_weekly'    THEN v_next_date + INTERVAL '14 days'
                WHEN 'monthly'      THEN v_next_date + INTERVAL '1 month'
                ELSE v_next_date + INTERVAL '7 days'
            END;
        END LOOP;

        -- 4. Advance subscription schedule
        UPDATE public.customer_subscriptions
        SET next_delivery_date = v_next_date,
            updated_at = NOW()
        WHERE id = sub.id;

    END LOOP;

    RETURN jsonb_build_object(
        'success', true,
        'orders_created', v_orders_created,
        'timestamp', NOW()
    );
END;
$$;

-- Grant execution to authenticated users / service role
GRANT EXECUTE ON FUNCTION public.process_due_customer_subscriptions() TO authenticated;
GRANT EXECUTE ON FUNCTION public.process_due_customer_subscriptions() TO service_role;

-- 4. Update create_order_atomic to support text idempotency_key
CREATE OR REPLACE FUNCTION public.create_order_atomic(p_order_data jsonb, p_items_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  -- 3. Verify line items against products catalog (or fallback if routine refill)
  IF p_items_data IS NOT NULL AND jsonb_array_length(p_items_data) > 0 THEN
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items_data) AS x(
      product_id uuid,
      quantity integer,
      product_name text
    )
    LOOP
      IF v_item.quantity <= 0 THEN
        RAISE EXCEPTION 'Invalid quantity for item %', v_item.product_name;
      END IF;

      IF v_item.product_id IS NOT NULL THEN
        SELECT * INTO v_product FROM public.products
        WHERE id = v_item.product_id AND owner_id = v_owner_id AND is_available = true;

        IF NOT FOUND THEN
          RAISE EXCEPTION 'Product % is unavailable at this station.', v_item.product_name;
        END IF;

        v_computed_subtotal := v_computed_subtotal + (v_product.price * v_item.quantity);
      END IF;
    END LOOP;
  END IF;

  IF v_computed_subtotal <= 0 THEN
    v_computed_subtotal := coalesce((p_order_data->>'subtotal')::numeric, (p_order_data->>'total_amount')::numeric, 0);
  END IF;

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
    NULLIF(p_order_data->>'idempotency_key', ''),
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
    product_name text,
    price_per_gallon numeric,
    unit_price numeric,
    total_price numeric,
    price_at_purchase numeric
  )
  LOOP
    IF v_item.product_id IS NOT NULL THEN
      SELECT * INTO v_product FROM public.products WHERE id = v_item.product_id;
    END IF;

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
      coalesce(v_product.name, v_item.product_name, 'Refill'),
      coalesce(v_item.quantity, 1),
      coalesce(v_product.price, v_item.price_at_purchase, v_item.unit_price, v_item.price_per_gallon, 0),
      coalesce(v_item.total_price, (coalesce(v_product.price, v_item.price_at_purchase, v_item.unit_price, 0) * coalesce(v_item.quantity, 1)))
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
$function$;

GRANT EXECUTE ON FUNCTION public.create_order_atomic(jsonb, jsonb) TO authenticated;
