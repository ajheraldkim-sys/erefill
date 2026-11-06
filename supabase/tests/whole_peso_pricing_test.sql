-- Run: BEGIN; whole_peso_pricing.sql; _fixtures.sql; this file; ROLLBACK;

-- price_order_rounds_subtotal_and_delivery
DO $$ DECLARE r record; BEGIN
  SELECT * INTO r FROM public.price_order(119.6, 20.4);
  PERFORM pg_temp.assert_eq('subtotal', r.subtotal, 120::numeric);
  PERFORM pg_temp.assert_eq('delivery', r.delivery_fee, 20::numeric);
  PERFORM pg_temp.assert_eq('fee', r.service_fee, 1.40::numeric);
  PERFORM pg_temp.assert_eq('total', r.total, 141.40::numeric);
END $$;

-- price_order_keeps_fee_centavos
DO $$ DECLARE r record; BEGIN
  SELECT * INTO r FROM public.price_order(25, 0);
  PERFORM pg_temp.assert_eq('fee', r.service_fee, 0.25::numeric);
  PERFORM pg_temp.assert_eq('total', r.total, 25.25::numeric);
END $$;

-- price_order_rounds_discount
DO $$ DECLARE r record; BEGIN
  SELECT * INTO r FROM public.price_order(120, 20, 10.5);
  PERFORM pg_temp.assert_eq('discount', r.discount, 11::numeric);
  PERFORM pg_temp.assert_eq('total', r.total, 130.40::numeric);
END $$;

-- price_order_floors_total_at_zero
DO $$ DECLARE r record; BEGIN
  SELECT * INTO r FROM public.price_order(20, 5, 100);
  PERFORM pg_temp.assert_eq('total', r.total, 0::numeric);
END $$;

-- calculate_platform_fee_uses_rule
DO $$ BEGIN
  PERFORM pg_temp.assert_eq('calc fee', public.calculate_platform_fee(119.6, 20.4), 1.40::numeric);
END $$;

-- create_order_atomic_uses_rule (₱19.60 product, ₱5.40 base delivery)
DO $$ DECLARE r jsonb; BEGIN
  r := pg_temp.place_order('cod');
  PERFORM pg_temp.assert_eq('order subtotal', (r->>'subtotal')::numeric, 20::numeric);
  PERFORM pg_temp.assert_eq('order delivery', (r->>'delivery_fee')::numeric, 5::numeric);
  PERFORM pg_temp.assert_eq('order fee', (r->>'platform_fee')::numeric, 0.25::numeric);
  PERFORM pg_temp.assert_eq('order total', (r->>'total_amount')::numeric, 25.25::numeric);
END $$;

-- subscription_order_uses_rule
DO $$ DECLARE o record; BEGIN
  INSERT INTO public.customer_subscriptions (
    customer_id, station_id, station_name, delivery_address, water_type,
    quantity, estimated_price, frequency, preferred_time_slot,
    payment_method, is_active, next_delivery_date
  ) VALUES (
    '00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000a1',
    'T Station', 'Test address', 'Purified', 2, 39.5, 'weekly', 'morning',
    'cod', true, now() - interval '1 minute'
  );
  PERFORM public.process_due_customer_subscriptions();
  SELECT * INTO o FROM public.orders
  WHERE customer_id = '00000000-0000-4000-8000-0000000000c1'
    AND idempotency_key LIKE 'auto_sub_%';
  PERFORM pg_temp.assert_eq('sub subtotal', o.subtotal, 40::numeric);
  PERFORM pg_temp.assert_eq('sub delivery', o.delivery_fee, 0::numeric);
  PERFORM pg_temp.assert_eq('sub fee', o.platform_fee, 0.40::numeric);
  PERFORM pg_temp.assert_eq('sub total', o.total_amount, 40.40::numeric);
END $$;

-- fee_disabled_means_no_fee
DO $$ DECLARE r record; BEGIN
  UPDATE public.system_config SET value = '{"enabled": false, "percent": 1, "fixed": 0}'::jsonb
  WHERE key = 'platform_fee';
  SELECT * INTO r FROM public.price_order(120, 20);
  PERFORM pg_temp.assert_eq('fee off', r.service_fee, 0::numeric);
  PERFORM pg_temp.assert_eq('total off', r.total, 140::numeric);
  -- Later test files in the same batch expect the fee on.
  UPDATE public.system_config SET value = '{"enabled": true, "percent": 1, "fixed": 0}'::jsonb
  WHERE key = 'platform_fee';
END $$;

SELECT 'whole_peso_pricing_test: all passed' AS result;
