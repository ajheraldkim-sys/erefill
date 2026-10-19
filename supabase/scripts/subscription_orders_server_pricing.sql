-- =============================================================================
-- Auto-refill (subscription) orders: server-side generation with live pricing
-- =============================================================================
-- Why: subscription orders were priced from customer_subscriptions.
-- estimated_price, a value the customer's app writes, with a PHP 0 delivery
-- fee. The app composed and inserted the order rows itself (create_order_atomic
-- could never accept them: the items had no product_id, and it rejects
-- non-customer callers such as the owner dashboard). A modified client could
-- therefore place auto-refill orders at any price.
--
-- Business rule (confirmed 2026-10-19): auto-refill orders are priced like
-- checkout at generation time:
--   product.price * quantity + owner_settings.base_delivery_fee + platform fee.
--
-- Changes (non-destructive; no existing order is modified):
--   1. customer_subscriptions.product_id (nullable FK) + one-off backfill when
--      exactly one station product matches.
--   2. Trigger: validates product_id belongs to the station and recomputes
--      estimated_price (now display-only) from the live product price.
--   3. generate_due_subscription_orders(): the only path that creates
--      subscription orders. Callable by the customer (own subscriptions), the
--      station owner (own station) or an admin. Skipped subscriptions are
--      returned with a reason and are NOT advanced, so no delivery is lost
--      silently.
--
-- Rollback: subscription_orders_server_pricing_rollback.sql
-- Rollout:  apply this, release the app version that calls the new RPC, then
--           apply lock_direct_order_inserts.sql.
-- =============================================================================

BEGIN;

-- 1. Link subscriptions to a concrete station product -------------------------

ALTER TABLE public.customer_subscriptions
  ADD COLUMN IF NOT EXISTS product_id uuid
  REFERENCES public.products(id) ON DELETE SET NULL;

-- Resolve a product for a subscription that has none: a refill product of the
-- station whose category matches the water type, else whose unit price equals
-- the price the customer saw. Only an unambiguous single match is returned.
CREATE OR REPLACE FUNCTION public._resolve_subscription_product(
  p_station_id uuid, p_water_type text, p_estimated_price numeric, p_quantity integer
)
RETURNS uuid
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_ids uuid[];
BEGIN
  SELECT array_agg(id) INTO v_ids
  FROM public.products
  WHERE owner_id = p_station_id
    AND is_available
    AND price > 0
    AND coalesce(category, '') <> 'Accessories'
    AND lower(category) = lower(trim(p_water_type));
  IF coalesce(array_length(v_ids, 1), 0) = 1 THEN
    RETURN v_ids[1];
  END IF;

  IF p_quantity > 0 AND p_estimated_price > 0 THEN
    SELECT array_agg(id) INTO v_ids
    FROM public.products
    WHERE owner_id = p_station_id
      AND is_available
      AND coalesce(category, '') <> 'Accessories'
      AND price = round(p_estimated_price / p_quantity, 2);
    IF coalesce(array_length(v_ids, 1), 0) = 1 THEN
      RETURN v_ids[1];
    END IF;
  END IF;

  RETURN NULL;
END;
$$;
REVOKE EXECUTE ON FUNCTION public._resolve_subscription_product(uuid, text, numeric, integer)
  FROM PUBLIC, anon, authenticated;

UPDATE public.customer_subscriptions s
SET product_id = public._resolve_subscription_product(
      s.station_id, s.water_type, s.estimated_price, s.quantity)
WHERE s.product_id IS NULL;

-- 2. Keep product_id honest and estimated_price server-computed ---------------

CREATE OR REPLACE FUNCTION public.proc_subscription_pricing()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_price numeric;
BEGIN
  IF NEW.product_id IS NULL THEN
    NEW.product_id := public._resolve_subscription_product(
      NEW.station_id, NEW.water_type, NEW.estimated_price, NEW.quantity);
  END IF;

  IF NEW.product_id IS NOT NULL THEN
    SELECT price INTO v_price
    FROM public.products
    WHERE id = NEW.product_id AND owner_id = NEW.station_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Selected product is not sold by this station.'
        USING ERRCODE = '23514';
    END IF;
    NEW.estimated_price := round(v_price * greatest(NEW.quantity, 1), 2);
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_subscription_pricing ON public.customer_subscriptions;
CREATE TRIGGER trg_subscription_pricing
  BEFORE INSERT OR UPDATE OF product_id, station_id, quantity, estimated_price, water_type
  ON public.customer_subscriptions
  FOR EACH ROW EXECUTE FUNCTION public.proc_subscription_pricing();

-- 3. Authoritative generator --------------------------------------------------

CREATE OR REPLACE FUNCTION public.generate_due_subscription_orders(
  p_customer_id uuid DEFAULT NULL,
  p_station_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_is_admin boolean := public.is_admin();
  v_sub public.customer_subscriptions%ROWTYPE;
  v_product public.products%ROWTYPE;
  v_key text;
  v_order_id uuid;
  v_subtotal numeric(10,2);
  v_delivery_fee numeric(10,2);
  v_platform_fee numeric(10,2);
  v_total numeric(10,2);
  v_config jsonb := public.get_platform_fee_config();
  v_next timestamptz;
  v_created jsonb := '[]'::jsonb;
  v_skipped jsonb := '[]'::jsonb;
  v_customer_name text;
  v_customer_phone text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
  END IF;
  IF NOT v_is_admin AND p_customer_id IS DISTINCT FROM v_uid AND p_station_id IS DISTINCT FROM v_uid THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
  END IF;
  IF p_station_id IS NOT NULL AND p_station_id = v_uid AND NOT v_is_admin
     AND NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_uid AND role::text = 'owner') THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
  END IF;

  FOR v_sub IN
    SELECT * FROM public.customer_subscriptions
    WHERE is_active
      AND next_delivery_date <= now() + interval '5 minutes'
      AND (p_customer_id IS NULL OR customer_id = p_customer_id)
      AND (p_station_id IS NULL OR station_id = p_station_id)
    ORDER BY next_delivery_date
    FOR UPDATE SKIP LOCKED
  LOOP
    -- Same per-day key the app used, so a cycle generated earlier is not repeated.
    v_key := 'auto_sub_' || v_sub.id || '_' || to_char(now() AT TIME ZONE 'Asia/Manila', 'YYYY-MM-DD');

    IF NOT EXISTS (SELECT 1 FROM public.orders WHERE idempotency_key = v_key) THEN
      SELECT * INTO v_product
      FROM public.products
      WHERE id = v_sub.product_id AND owner_id = v_sub.station_id AND is_available AND price > 0;
      IF NOT FOUND THEN
        v_skipped := v_skipped || jsonb_build_object(
          'subscription_id', v_sub.id, 'reason', 'product_unavailable');
        CONTINUE;
      END IF;

      IF NOT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = v_sub.station_id AND role::text = 'owner'
          AND NOT coalesce(is_suspended, false)
          AND coalesce(station_availability, 'open') = 'open'
      ) THEN
        v_skipped := v_skipped || jsonb_build_object(
          'subscription_id', v_sub.id, 'reason', 'station_unavailable');
        CONTINUE;
      END IF;

      IF NOT public.is_station_payment_method_available(v_sub.station_id, lower(coalesce(v_sub.payment_method, 'cod'))) THEN
        v_skipped := v_skipped || jsonb_build_object(
          'subscription_id', v_sub.id, 'reason', 'payment_method_unavailable');
        CONTINUE;
      END IF;

      -- Pricing: identical formula to create_order_atomic.
      v_subtotal := round(v_product.price * v_sub.quantity, 2);
      SELECT coalesce(base_delivery_fee, 0) INTO v_delivery_fee
      FROM public.owner_settings WHERE owner_id = v_sub.station_id;
      v_delivery_fee := coalesce(v_delivery_fee, 0);
      v_platform_fee := 0;
      IF coalesce((v_config->>'enabled')::boolean, false) THEN
        v_platform_fee := greatest(round(
          ((v_subtotal + v_delivery_fee) * coalesce((v_config->>'percent')::numeric, 0) / 100)
          + coalesce((v_config->>'fixed')::numeric, 0), 2), 0);
      END IF;
      v_total := v_subtotal + v_delivery_fee + v_platform_fee;

      SELECT full_name, phone INTO v_customer_name, v_customer_phone
      FROM public.profiles WHERE id = v_sub.customer_id;

      v_order_id := gen_random_uuid();
      INSERT INTO public.orders (
        id, customer_id, owner_id, station_name, customer_name, customer_phone,
        customer_address, idempotency_key, subtotal, delivery_fee, platform_fee,
        total_amount, payment_method, payment_status, status, notes, items
      ) VALUES (
        v_order_id, v_sub.customer_id, v_sub.station_id, v_sub.station_name,
        v_customer_name, v_customer_phone, v_sub.delivery_address, v_key,
        v_subtotal, v_delivery_fee, v_platform_fee, v_total,
        lower(coalesce(v_sub.payment_method, 'cod')), 'pending', 'pending',
        'Auto-Refill Routine (' || v_sub.frequency || ') - Slot: ' || v_sub.preferred_time_slot,
        jsonb_build_array(jsonb_build_object(
          'product_id', v_product.id, 'product_name', v_product.name,
          'quantity', v_sub.quantity, 'price', v_product.price, 'total_price', v_subtotal))
      );

      INSERT INTO public.order_items (
        order_id, product_id, product_name, water_type, quantity,
        price_at_purchase, unit_price, price_per_gallon, subtotal, total_price
      ) VALUES (
        v_order_id, v_product.id, v_product.name, v_sub.water_type, v_sub.quantity,
        v_product.price, v_product.price, v_product.price, v_subtotal, v_subtotal
      );

      INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
      VALUES (
        v_sub.station_id, 'system_alert', 'high', 'New Auto-Refill Order',
        coalesce(v_customer_name, 'A customer') || '''s auto-refill order of PHP '
          || trim(to_char(v_total, '999999990.00')) || ' is ready to prepare.',
        jsonb_build_object('order_id', v_order_id, 'status', 'pending', 'total_amount', v_total)
      );

      v_created := v_created || jsonb_build_object(
        'id', v_order_id, 'subscription_id', v_sub.id,
        'subtotal', v_subtotal, 'delivery_fee', v_delivery_fee,
        'platform_fee', v_platform_fee, 'total_amount', v_total);
    END IF;

    -- Advance only after this cycle has an order (new or pre-existing).
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

    UPDATE public.customer_subscriptions
    SET next_delivery_date = v_next, updated_at = now()
    WHERE id = v_sub.id;
  END LOOP;

  RETURN jsonb_build_object('created', v_created, 'skipped', v_skipped);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.generate_due_subscription_orders(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.generate_due_subscription_orders(uuid, uuid) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

COMMIT;
