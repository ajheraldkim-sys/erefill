-- Whole-peso pricing: subtotal, delivery fee and voucher discount are rounded
-- to whole pesos; the service (platform) fee keeps its exact percentage to the
-- centavo. One function, price_order(), owns the rule; every order path uses it.
-- Run after payments_wallet_snapshot.sql. Safe to re-run.

BEGIN;

CREATE OR REPLACE FUNCTION public.price_order(
  p_subtotal_raw numeric,
  p_delivery_raw numeric,
  p_discount_raw numeric DEFAULT 0
)
RETURNS TABLE (
  subtotal numeric,
  delivery_fee numeric,
  service_fee numeric,
  discount numeric,
  total numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_cfg jsonb := public.get_platform_fee_config();
BEGIN
  subtotal := round(greatest(coalesce(p_subtotal_raw, 0), 0), 0);
  delivery_fee := round(greatest(coalesce(p_delivery_raw, 0), 0), 0);
  discount := round(greatest(coalesce(p_discount_raw, 0), 0), 0);

  IF coalesce((v_cfg->>'enabled')::boolean, false) THEN
    service_fee := greatest(
      round(
        (subtotal + delivery_fee) * coalesce((v_cfg->>'percent')::numeric, 0) / 100
          + coalesce((v_cfg->>'fixed')::numeric, 0),
        2
      ),
      0
    );
  ELSE
    service_fee := 0;
  END IF;

  total := greatest(subtotal + delivery_fee + service_fee - discount, 0);
  RETURN NEXT;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.price_order(numeric, numeric, numeric) TO authenticated;

CREATE OR REPLACE FUNCTION public.calculate_platform_fee(p_subtotal numeric, p_delivery_fee numeric DEFAULT 0)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT service_fee FROM public.price_order(p_subtotal, p_delivery_fee, 0);
$function$;

-- Live create_order_atomic (2026-10-22) with its pricing arithmetic replaced
-- by price_order(). Everything else is unchanged.
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
  v_idempotency_key public.orders.idempotency_key%TYPE;
  v_voucher_id uuid;
  v_order_id uuid;
  v_item record;
  v_product record;
  v_raw_subtotal numeric := 0;
  v_raw_delivery numeric := 0;
  v_raw_discount numeric := 0;
  v_computed_subtotal numeric(10,2) := 0;
  v_delivery_fee numeric(10,2) := 0;
  v_platform_fee numeric(10,2) := 0;
  v_discount numeric(10,2) := 0;
  v_total_amount numeric(10,2) := 0;
  v_order_row public.orders%ROWTYPE;
  v_voucher public.customer_reward_vouchers%ROWTYPE;
  v_lat double precision;
  v_lng double precision;
  v_maintenance jsonb;
  v_is_maintenance boolean := false;
  v_customer_suspended boolean := false;
  v_owner_suspended boolean := false;
BEGIN
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
        'platform_fee', v_order_row.platform_fee,
        'total_amount', v_order_row.total_amount,
        'status', v_order_row.status
      );
    END IF;
  END IF;

  v_owner_id := NULLIF(p_order_data->>'owner_id', '')::uuid;
  v_payment_method := lower(trim(coalesce(p_order_data->>'payment_method', 'cod')));
  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'Station owner ID is required.';
  END IF;

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
    WHERE id = v_owner_id
      AND role = 'owner'
      AND coalesce(station_availability, 'open') = 'open'
  ) THEN
    RAISE EXCEPTION 'This water station is currently closed or unavailable.';
  END IF;
  IF NOT public.is_station_payment_method_available(v_owner_id, v_payment_method) THEN
    RAISE EXCEPTION 'This payment method is not available for this station.';
  END IF;

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

    v_raw_subtotal := v_raw_subtotal + (v_product.price * v_item.quantity);
  END LOOP;

  IF v_raw_subtotal <= 0 THEN
    RAISE EXCEPTION 'Cart cannot be empty.';
  END IF;

  SELECT coalesce(base_delivery_fee, 0) INTO v_raw_delivery
  FROM public.owner_settings
  WHERE owner_id = v_owner_id;
  v_raw_delivery := coalesce(v_raw_delivery, 0);

  SELECT p.subtotal, p.delivery_fee, p.service_fee
  INTO v_computed_subtotal, v_delivery_fee, v_platform_fee
  FROM public.price_order(v_raw_subtotal, v_raw_delivery, 0) AS p;

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
      v_raw_discount := least(
        greatest(v_voucher.discount_amount, 0),
        v_delivery_fee
      );
    ELSE
      v_raw_discount := least(
        greatest(v_voucher.discount_amount, 0),
        v_computed_subtotal + v_delivery_fee + v_platform_fee
      );
    END IF;
  END IF;

  SELECT p.discount, p.total
  INTO v_discount, v_total_amount
  FROM public.price_order(v_raw_subtotal, v_raw_delivery, v_raw_discount) AS p;

  v_lat := NULLIF(p_order_data->>'customer_latitude', '')::double precision;
  v_lng := NULLIF(p_order_data->>'customer_longitude', '')::double precision;

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

      IF FOUND THEN
        RETURN jsonb_build_object(
          'id', v_order_row.id,
          'subtotal', v_order_row.subtotal,
          'delivery_fee', v_order_row.delivery_fee,
          'platform_fee', v_order_row.platform_fee,
          'total_amount', v_order_row.total_amount,
          'status', v_order_row.status
        );
      END IF;
    END IF;
    RAISE EXCEPTION 'Order could not be created because of a conflicting order record.';
  END IF;

  v_order_id := v_order_row.id;

  FOR v_item IN
    SELECT * FROM jsonb_to_recordset(p_items_data) AS x(
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

  IF v_voucher_id IS NOT NULL THEN
    UPDATE public.customer_reward_vouchers
    SET is_used = true
    WHERE id = v_voucher_id
      AND user_id = v_customer_id
      AND is_used = false;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'This reward voucher was already used by another order.';
    END IF;
  END IF;

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
    coalesce(p_order_data->>'customer_name', 'A customer')
      || ' placed a new refill order of PHP '
      || trim(to_char(v_total_amount, '999999990.00'))
      || ' (' || upper(coalesce(p_order_data->>'payment_method', 'cod')) || ').',
    jsonb_build_object(
      'order_id', v_order_id,
      'status', 'pending',
      'total_amount', v_total_amount
    )
  );

  RETURN jsonb_build_object(
    'id', v_order_id,
    'subtotal', v_computed_subtotal,
    'delivery_fee', v_delivery_fee,
    'platform_fee', v_platform_fee,
    'discount_amount', v_discount,
    'total_amount', v_total_amount,
    'status', 'pending'
  );
END;
$function$;

-- Live process_due_customer_subscriptions (2026-10-22), now priced with
-- price_order() and recording the service fee. Auto-orders also carry the
-- customer's profile map pin (verify_order_delivery_location rejected every
-- auto-order without one), and a subscription that cannot be ordered is
-- skipped instead of aborting the whole run. Scheduling is unchanged.
CREATE OR REPLACE FUNCTION public.process_due_customer_subscriptions()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    sub RECORD;
    v_order_id UUID;
    v_date_str TEXT;
    v_idempotency_key TEXT;
    v_next_date TIMESTAMPTZ;
    v_orders_created INT := 0;
    v_unit_price NUMERIC;
    v_price RECORD;
    v_lat DOUBLE PRECISION;
    v_lng DOUBLE PRECISION;
    v_orders_skipped INT := 0;
BEGIN
    v_date_str := to_char(CURRENT_DATE, 'YYYY-MM-DD');

    FOR sub IN
        SELECT *
        FROM public.customer_subscriptions
        WHERE is_active = true
          AND next_delivery_date <= NOW() + INTERVAL '1 hour'
    LOOP
        v_idempotency_key := 'auto_sub_' || sub.id || '_' || v_date_str;

        IF NOT EXISTS (
            SELECT 1 FROM public.orders WHERE idempotency_key = v_idempotency_key
        ) THEN
          BEGIN
            v_order_id := gen_random_uuid();
            SELECT * INTO v_price FROM public.price_order(sub.estimated_price, 0, 0);
            SELECT latitude, longitude INTO v_lat, v_lng
            FROM public.profiles WHERE id = sub.customer_id;
            v_unit_price := CASE
                WHEN sub.quantity > 0 THEN ROUND(v_price.subtotal / sub.quantity, 2)
                ELSE v_price.subtotal
            END;

            INSERT INTO public.orders (
                id,
                customer_id,
                owner_id,
                station_name,
                customer_address,
                idempotency_key,
                subtotal,
                delivery_fee,
                platform_fee,
                total_amount,
                payment_method,
                status,
                notes,
                items,
                customer_latitude,
                customer_longitude,
                delivery_latitude,
                delivery_longitude,
                created_at,
                updated_at
            ) VALUES (
                v_order_id,
                sub.customer_id,
                sub.station_id,
                sub.station_name,
                sub.delivery_address,
                v_idempotency_key,
                v_price.subtotal,
                v_price.delivery_fee,
                v_price.service_fee,
                v_price.total,
                sub.payment_method,
                'pending',
                'Auto-Refill Routine (' || sub.frequency || ') - Slot: ' || sub.preferred_time_slot,
                jsonb_build_array(jsonb_build_object(
                    'product_name', sub.water_type || ' Refill',
                    'quantity', sub.quantity,
                    'price', v_unit_price,
                    'total_price', v_price.subtotal
                )),
                v_lat,
                v_lng,
                v_lat,
                v_lng,
                NOW(),
                NOW()
            );

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
                v_price.subtotal,
                v_unit_price,
                v_price.subtotal
            );

            v_orders_created := v_orders_created + 1;
          EXCEPTION WHEN OTHERS THEN
            v_orders_skipped := v_orders_skipped + 1;
            RAISE WARNING 'Auto-order skipped for subscription %: %', sub.id, SQLERRM;
          END;
        END IF;

        v_next_date := CASE sub.frequency
            WHEN 'every_3_days' THEN sub.next_delivery_date + INTERVAL '3 days'
            WHEN 'twice_weekly' THEN sub.next_delivery_date + INTERVAL '4 days'
            WHEN 'weekly'       THEN sub.next_delivery_date + INTERVAL '7 days'
            WHEN 'bi_weekly'    THEN sub.next_delivery_date + INTERVAL '14 days'
            WHEN 'monthly'      THEN sub.next_delivery_date + INTERVAL '1 month'
            ELSE sub.next_delivery_date + INTERVAL '7 days'
        END;

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

        UPDATE public.customer_subscriptions
        SET next_delivery_date = v_next_date,
            updated_at = NOW()
        WHERE id = sub.id;

    END LOOP;

    RETURN jsonb_build_object(
        'success', true,
        'orders_created', v_orders_created,
        'orders_skipped', v_orders_skipped,
        'timestamp', NOW()
    );
END;
$function$;

-- One-off: existing prices and base delivery fees become whole pesos.
UPDATE public.products SET price = round(price) WHERE price <> round(price);
UPDATE public.owner_settings
SET base_delivery_fee = round(base_delivery_fee)
WHERE base_delivery_fee <> round(base_delivery_fee);

COMMIT;
