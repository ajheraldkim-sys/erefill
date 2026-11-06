-- ==============================================================================
-- Restore missing functions safely (2026-11-06)
-- ==============================================================================
-- The app calls these, but on the live database they only existed inside
-- older scripts that also replace newer work (create_order_atomic,
-- transition_order_status_safely). This script adds just the missing pieces,
-- updated to current rules, and touches nothing else.
--
--   1. get_customer_credits()          customer's credits from the station's
--      offline ledger, by exact name (the old ILIKE let "%" match everyone).
--   2. orders.delivery_type + complete_pickup_order_safely()
--      (the owner "Add order" dialog writes delivery_type; it failed without
--      the column).
--   3. Subscriptions: product_id link, live-price estimate, and
--      generate_due_subscription_orders() priced like checkout
--      (create_order_atomic v3: delivery quote, platform fee, ID gates).
--      process_due_customer_subscriptions() now uses the same generator;
--      it used to call price_order(), which does not exist.
--   4. admin_delete_product(): admins may remove accessories (water stays).
--
-- Run after: order_pricing_v3.sql (needs compute_delivery_quote and
-- assert_order_allowed_by_verification).
-- Test: supabase/tests/restore_missing_rpcs_test.sql
-- ==============================================================================

BEGIN;

-- 1. Customer credits ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_customer_credits()
RETURNS SETOF public.dm_credits
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  WITH me AS (
    SELECT lower(btrim(regexp_replace(n, '\s+', ' ', 'g'))) AS n
    FROM public.profiles p,
         LATERAL (VALUES (p.full_name),
                         (concat_ws(' ', nullif(btrim(p.first_name), ''), nullif(btrim(p.last_name), '')))) v(n)
    WHERE p.id = auth.uid()
  ), names AS (
    SELECT DISTINCT n FROM me
    WHERE n IS NOT NULL AND length(n) >= 3 AND n <> 'new user'
  )
  SELECT c.* FROM public.dm_credits c
  WHERE c.credit_type = 'customer'
    AND lower(btrim(regexp_replace(c.debtor_name, '\s+', ' ', 'g'))) IN (SELECT n FROM names)
  ORDER BY c.created_at DESC;
$$;
REVOKE ALL ON FUNCTION public.get_customer_credits() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_customer_credits() TO authenticated, service_role;

-- 2. Pickup orders ---------------------------------------------------------------

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS delivery_type text NOT NULL DEFAULT 'delivery';
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_delivery_type_check;
ALTER TABLE public.orders ADD CONSTRAINT orders_delivery_type_check
  CHECK (delivery_type IN ('delivery', 'pickup'));

CREATE OR REPLACE FUNCTION public.complete_pickup_order_safely(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_order public.orders%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required.'; END IF;

  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'Order not found');
  END IF;
  IF auth.uid() IS DISTINCT FROM v_order.owner_id
     OR NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'owner') THEN
    RAISE EXCEPTION 'Only this station owner can complete a pickup order.';
  END IF;
  IF v_order.delivery_type <> 'pickup' THEN
    RAISE EXCEPTION 'Only pickup orders can be completed by the station.';
  END IF;

  IF v_order.status::text = 'delivered' THEN
    IF EXISTS (SELECT 1 FROM public.audit_logs
               WHERE action = 'OWNER_COMPLETE_PICKUP' AND entity_type = 'order'
                 AND entity_id = p_order_id::text) THEN
      RETURN jsonb_build_object('success', true, 'status', 'delivered', 'already_applied', true);
    END IF;
    RAISE EXCEPTION 'Pickup order is already delivered without an owner completion record.';
  END IF;
  IF v_order.status::text <> 'ready_for_pickup' THEN
    RAISE EXCEPTION 'Only a ready pickup order can be completed.';
  END IF;

  UPDATE public.orders
  SET status = 'delivered',
      actual_completion_at = coalesce(actual_completion_at, now()),
      updated_at = now()
  WHERE id = p_order_id;

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, old_value, new_value, metadata)
  VALUES (auth.uid(), 'OWNER_COMPLETE_PICKUP', 'order', p_order_id::text,
          jsonb_build_object('status', v_order.status),
          jsonb_build_object('status', 'delivered'),
          jsonb_build_object('delivery_type', 'pickup'));

  IF v_order.customer_id IS NOT NULL THEN
    INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
    VALUES (v_order.customer_id, 'system_alert', 'high', 'Pickup order completed',
            'Your refill order was collected from the water station.',
            jsonb_build_object('order_id', p_order_id, 'status', 'delivered'));
  END IF;
  RETURN jsonb_build_object('success', true, 'status', 'delivered');
END; $$;
REVOKE ALL ON FUNCTION public.complete_pickup_order_safely(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_pickup_order_safely(uuid) TO authenticated;

-- 3. Subscriptions ---------------------------------------------------------------

ALTER TABLE public.customer_subscriptions
  ADD COLUMN IF NOT EXISTS product_id uuid REFERENCES public.products(id) ON DELETE SET NULL;

-- Each station sells exactly one water product (station_accessories.sql), so
-- a subscription is for that product.
CREATE OR REPLACE FUNCTION public.proc_subscription_pricing()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_price numeric;
BEGIN
  IF NEW.product_id IS NULL OR (TG_OP = 'UPDATE' AND NEW.station_id IS DISTINCT FROM OLD.station_id) THEN
    SELECT id INTO NEW.product_id FROM public.products
    WHERE owner_id = NEW.station_id AND kind = 'water';
  END IF;
  IF NEW.product_id IS NOT NULL THEN
    SELECT price INTO v_price FROM public.products
    WHERE id = NEW.product_id AND owner_id = NEW.station_id AND kind = 'water';
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Subscriptions are for the station''s water only.' USING ERRCODE = '23514';
    END IF;
    -- Display only; orders are priced when they are generated.
    NEW.estimated_price := round(v_price * greatest(NEW.quantity, 1), 2);
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_subscription_pricing ON public.customer_subscriptions;
CREATE TRIGGER trg_subscription_pricing
  BEFORE INSERT OR UPDATE OF product_id, station_id, quantity, estimated_price
  ON public.customer_subscriptions
  FOR EACH ROW EXECUTE FUNCTION public.proc_subscription_pricing();

-- Backfill existing subscriptions (fires the trigger).
UPDATE public.customer_subscriptions SET product_id = NULL WHERE product_id IS NULL;

-- Generator without caller checks; only the two wrappers below may run it.
CREATE OR REPLACE FUNCTION public._generate_due_subscription_orders(
  p_customer_id uuid, p_station_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_sub public.customer_subscriptions%ROWTYPE;
  v_product public.products%ROWTYPE;
  v_cust public.profiles%ROWTYPE;
  v_key text;
  v_method text;
  v_order_id uuid;
  v_quote jsonb;
  v_subtotal numeric(10,2);
  v_delivery_fee numeric(10,2);
  v_platform_fee numeric(10,2);
  v_total numeric(10,2);
  v_config jsonb := public.get_platform_fee_config();
  v_next timestamptz;
  v_created jsonb := '[]'::jsonb;
  v_skipped jsonb := '[]'::jsonb;
BEGIN
  FOR v_sub IN
    SELECT * FROM public.customer_subscriptions
    WHERE is_active
      AND next_delivery_date <= now() + interval '5 minutes'
      AND (p_customer_id IS NULL OR customer_id = p_customer_id)
      AND (p_station_id IS NULL OR station_id = p_station_id)
    ORDER BY next_delivery_date
    FOR UPDATE SKIP LOCKED
  LOOP
    -- One order per subscription per Manila day.
    v_key := 'auto_sub_' || v_sub.id || '_' || to_char(now() AT TIME ZONE 'Asia/Manila', 'YYYY-MM-DD');
    v_method := lower(coalesce(v_sub.payment_method, 'cod'));

    IF NOT EXISTS (SELECT 1 FROM public.orders WHERE idempotency_key = v_key) THEN
      SELECT * INTO v_product FROM public.products
      WHERE id = v_sub.product_id AND owner_id = v_sub.station_id
        AND kind = 'water' AND is_available AND price > 0;
      IF NOT FOUND THEN
        v_skipped := v_skipped || jsonb_build_object('subscription_id', v_sub.id, 'reason', 'product_unavailable');
        CONTINUE;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM public.profiles
                     WHERE id = v_sub.station_id AND role = 'owner'
                       AND NOT coalesce(is_suspended, false)
                       AND coalesce(station_availability, 'open') = 'open') THEN
        v_skipped := v_skipped || jsonb_build_object('subscription_id', v_sub.id, 'reason', 'station_unavailable');
        CONTINUE;
      END IF;
      IF NOT public.is_station_payment_method_available(v_sub.station_id, v_method) THEN
        v_skipped := v_skipped || jsonb_build_object('subscription_id', v_sub.id, 'reason', 'payment_method_unavailable');
        CONTINUE;
      END IF;

      SELECT * INTO v_cust FROM public.profiles WHERE id = v_sub.customer_id;

      -- Pricing: same as create_order_atomic v3.
      v_subtotal := round(v_product.price * v_sub.quantity, 2);
      v_quote := public.compute_delivery_quote(
        v_sub.station_id,
        coalesce(v_cust.latitude, v_cust.lat), coalesce(v_cust.longitude, v_cust.lng),
        v_cust.barangay, v_sub.quantity);
      v_delivery_fee := coalesce((v_quote->>'fee')::numeric, 0);
      v_platform_fee := 0;
      IF coalesce((v_config->>'enabled')::boolean, false) THEN
        v_platform_fee := greatest(round(
          ((v_subtotal + v_delivery_fee) * coalesce((v_config->>'percent')::numeric, 0) / 100)
          + coalesce((v_config->>'fixed')::numeric, 0), 2), 0);
      END IF;
      v_total := v_subtotal + v_delivery_fee + v_platform_fee;

      -- Verified station; COD limits for unverified customers.
      BEGIN
        PERFORM public.assert_order_allowed_by_verification(
          v_sub.customer_id, v_sub.station_id, v_method, v_total);
      EXCEPTION WHEN OTHERS THEN
        v_skipped := v_skipped || jsonb_build_object(
          'subscription_id', v_sub.id, 'reason', 'not_allowed', 'message', SQLERRM);
        CONTINUE;
      END;

      v_order_id := gen_random_uuid();
      INSERT INTO public.orders (
        id, customer_id, owner_id, station_name, customer_name, customer_phone,
        customer_address, customer_barangay, idempotency_key, subtotal, delivery_fee,
        platform_fee, total_amount, payment_method, payment_status, status, notes, items,
        customer_latitude, customer_longitude, delivery_latitude, delivery_longitude,
        delivery_distance_km, delivery_rate_per_km, delivery_free_reason, tip_amount
      ) VALUES (
        v_order_id, v_sub.customer_id, v_sub.station_id, v_sub.station_name,
        v_cust.full_name, v_cust.phone, v_sub.delivery_address, v_cust.barangay, v_key,
        v_subtotal, v_delivery_fee, v_platform_fee, v_total, v_method, 'pending', 'pending',
        'Auto-refill (' || v_sub.frequency || ', ' || v_sub.preferred_time_slot || ')',
        jsonb_build_array(jsonb_build_object(
          'product_id', v_product.id, 'product_name', v_product.name,
          'quantity', v_sub.quantity, 'price', v_product.price, 'total_price', v_subtotal)),
        coalesce(v_cust.latitude, v_cust.lat), coalesce(v_cust.longitude, v_cust.lng),
        coalesce(v_cust.latitude, v_cust.lat), coalesce(v_cust.longitude, v_cust.lng),
        (v_quote->>'distance_km')::numeric, (v_quote->>'rate_per_km')::numeric,
        v_quote->>'free_reason', 0
      );

      INSERT INTO public.order_items (order_id, product_id, product_name, quantity, price_at_purchase, subtotal)
      VALUES (v_order_id, v_product.id, v_product.name, v_sub.quantity, v_product.price, v_subtotal);

      INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
      VALUES (v_sub.station_id, 'system_alert', 'high', 'New auto-refill order',
              coalesce(v_cust.full_name, 'A customer') || '''s auto-refill order of PHP '
                || trim(to_char(v_total, '999999990.00')) || ' is ready to prepare.',
              jsonb_build_object('order_id', v_order_id, 'status', 'pending', 'total_amount', v_total));

      v_created := v_created || jsonb_build_object(
        'id', v_order_id, 'subscription_id', v_sub.id, 'subtotal', v_subtotal,
        'delivery_fee', v_delivery_fee, 'platform_fee', v_platform_fee, 'total_amount', v_total);
    END IF;

    -- Advance only once this cycle has an order (new or existing).
    v_next := v_sub.next_delivery_date;
    LOOP
      v_next := CASE v_sub.frequency
        WHEN 'every_3_days' THEN v_next + interval '3 days'
        WHEN 'twice_weekly' THEN v_next + interval '4 days'
        WHEN 'weekly'       THEN v_next + interval '7 days'
        WHEN 'bi_weekly'    THEN v_next + interval '14 days'
        WHEN 'monthly'      THEN v_next + interval '1 month'
        ELSE v_next + interval '7 days'
      END;
      EXIT WHEN v_next > now();
    END LOOP;
    UPDATE public.customer_subscriptions SET next_delivery_date = v_next, updated_at = now()
    WHERE id = v_sub.id;
  END LOOP;

  RETURN jsonb_build_object('created', v_created, 'skipped', v_skipped);
END; $$;
REVOKE ALL ON FUNCTION public._generate_due_subscription_orders(uuid, uuid) FROM PUBLIC, anon, authenticated;

-- App entry point: the customer (own), the station owner (own station) or an admin.
CREATE OR REPLACE FUNCTION public.generate_due_subscription_orders(
  p_customer_id uuid DEFAULT NULL, p_station_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501'; END IF;
  IF NOT public.is_admin() THEN
    IF p_customer_id IS DISTINCT FROM v_uid AND p_station_id IS DISTINCT FROM v_uid THEN
      RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
    END IF;
    IF p_customer_id IS DISTINCT FROM v_uid
       AND NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_uid AND role = 'owner') THEN
      RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN public._generate_due_subscription_orders(p_customer_id, p_station_id);
END; $$;
REVOKE ALL ON FUNCTION public.generate_due_subscription_orders(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.generate_due_subscription_orders(uuid, uuid) TO authenticated, service_role;

-- Scheduled-job entry point (all due subscriptions). Kept for old callers.
CREATE OR REPLACE FUNCTION public.process_due_customer_subscriptions()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  r jsonb;
BEGIN
  IF current_user IN ('authenticated', 'anon') AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
  END IF;
  r := public._generate_due_subscription_orders(NULL, NULL);
  RETURN jsonb_build_object(
    'success', true,
    'orders_created', jsonb_array_length(r->'created'),
    'orders_skipped', jsonb_array_length(r->'skipped'),
    'skipped', r->'skipped',
    'timestamp', now());
END; $$;
REVOKE ALL ON FUNCTION public.process_due_customer_subscriptions() FROM PUBLIC, anon;

-- 4. Admin product moderation ------------------------------------------------------

CREATE OR REPLACE FUNCTION public.admin_delete_product(p_product_id uuid, p_reason text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_p public.products%ROWTYPE;
  v_used boolean;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  SELECT * INTO v_p FROM public.products WHERE id = p_product_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Product not found.'; END IF;
  IF v_p.kind = 'water' THEN
    RAISE EXCEPTION 'Each station sells its water type only. Change the station''s water type instead.';
  END IF;

  -- Accessories already on orders are hidden instead of deleted, so receipts
  -- and order history keep their item.
  v_used := EXISTS (SELECT 1 FROM public.order_items WHERE product_id = p_product_id);
  IF v_used THEN
    UPDATE public.products SET is_available = false WHERE id = p_product_id;
  ELSE
    DELETE FROM public.products WHERE id = p_product_id;
  END IF;

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, old_value, metadata)
  VALUES (auth.uid(), CASE WHEN v_used THEN 'admin_hide_product' ELSE 'admin_delete_product' END,
          'products', p_product_id::text,
          jsonb_build_object('name', v_p.name, 'price', v_p.price, 'owner_id', v_p.owner_id),
          jsonb_build_object('reason', p_reason));
  RETURN jsonb_build_object('id', p_product_id, 'deleted', NOT v_used, 'hidden', v_used);
END; $$;
REVOKE ALL ON FUNCTION public.admin_delete_product(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_product(uuid, text) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
