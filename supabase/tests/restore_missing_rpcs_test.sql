-- Run: bash build.sh ../scripts/harden_signup_and_protected_columns.sql ../scripts/delivery_coverage.sql ../scripts/station_accessories.sql ../scripts/rider_tips.sql ../scripts/identity_verification.sql ../scripts/order_pricing_v3.sql ../scripts/restore_missing_rpcs.sql -- restore_missing_rpcs_test.sql

-- Fixture station a1 takes orders: verified, COD wallet funded.
UPDATE public.profiles SET verification_status = 'approved'
WHERE id = '00000000-0000-4000-8000-0000000000a1';
INSERT INTO public.station_fee_wallets (owner_id, balance)
VALUES ('00000000-0000-4000-8000-0000000000a1', 1000)
ON CONFLICT (owner_id) DO UPDATE SET balance = 1000;
UPDATE public.system_config
SET value = '{"enabled": true, "rate_per_km": 10, "minimum_fee": 20, "min_billable_distance_km": 1, "rounding_rule": "exact"}'::jsonb
WHERE key = 'delivery_fee_config';

-- customer_credits_exact_name_only
DO $$ BEGIN
  SET LOCAL session_replication_role = replica;
  INSERT INTO public.dm_credits (owner_id, credit_type, debtor_name, amount) VALUES
    ('00000000-0000-4000-8000-0000000000a1', 'customer', '  t cust ', 50),
    ('00000000-0000-4000-8000-0000000000a1', 'customer', 'T Cust Jr', 70),
    ('00000000-0000-4000-8000-0000000000a1', 'customer', 'Someone Else', 90);
  SET LOCAL session_replication_role = origin;

  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  PERFORM pg_temp.assert_eq('own credit only',
    (SELECT count(*) FROM public.get_customer_credits()), 1::bigint);

  -- A "%" name must not match everything.
  SET LOCAL session_replication_role = replica;
  UPDATE public.profiles SET full_name = '%', first_name = NULL, last_name = NULL
  WHERE id = '00000000-0000-4000-8000-0000000000c1';
  SET LOCAL session_replication_role = origin;
  PERFORM pg_temp.assert_eq('wildcard name sees nothing',
    (SELECT count(*) FROM public.get_customer_credits()), 0::bigint);
  SET LOCAL session_replication_role = replica;
  UPDATE public.profiles SET full_name = 'T Cust' WHERE id = '00000000-0000-4000-8000-0000000000c1';
  SET LOCAL session_replication_role = origin;
END $$;

-- owner_walk_in_order_and_pickup_completion
DO $$ DECLARE r jsonb; BEGIN
  SET LOCAL session_replication_role = replica;
  INSERT INTO public.orders (id, customer_id, owner_id, status, total_amount, delivery_type)
  VALUES ('00000000-0000-4000-8000-00000000f301', '00000000-0000-4000-8000-0000000000c1',
          '00000000-0000-4000-8000-0000000000a1', 'ready_for_pickup', 40, 'pickup'),
         ('00000000-0000-4000-8000-00000000f302', '00000000-0000-4000-8000-0000000000c1',
          '00000000-0000-4000-8000-0000000000a1', 'ready_for_pickup', 40, 'delivery');
  SET LOCAL session_replication_role = origin;

  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a2');
  PERFORM pg_temp.expect_error('other station',
    $q$SELECT public.complete_pickup_order_safely('00000000-0000-4000-8000-00000000f301')$q$,
    'Only this station owner');

  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
  PERFORM pg_temp.expect_error('delivery order',
    $q$SELECT public.complete_pickup_order_safely('00000000-0000-4000-8000-00000000f302')$q$,
    'Only pickup orders');
  r := public.complete_pickup_order_safely('00000000-0000-4000-8000-00000000f301');
  PERFORM pg_temp.assert_eq('completed', r->>'status', 'delivered');
  r := public.complete_pickup_order_safely('00000000-0000-4000-8000-00000000f301');
  PERFORM pg_temp.assert_eq('idempotent', (r->>'already_applied')::boolean, true);
END $$;

-- subscription_order_priced_like_checkout
DO $$ DECLARE r jsonb; q jsonb; v_sub uuid := gen_random_uuid(); BEGIN
  INSERT INTO public.customer_subscriptions (id, customer_id, station_id, station_name, quantity,
    water_type, estimated_price, delivery_address, next_delivery_date)
  VALUES (v_sub, '00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000a1',
    'T Station', 3, 'T Water', 1, 'Test address', now() - interval '1 hour');
  PERFORM pg_temp.assert_eq('product linked',
    (SELECT product_id FROM public.customer_subscriptions WHERE id = v_sub),
    '00000000-0000-4000-8000-0000000000b1'::uuid);
  PERFORM pg_temp.assert_eq('estimate from live price',
    (SELECT estimated_price FROM public.customer_subscriptions WHERE id = v_sub), 58.80::numeric);

  -- Strangers cannot run someone else's subscriptions.
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a2');
  PERFORM pg_temp.expect_error('stranger',
    $q$SELECT public.generate_due_subscription_orders('00000000-0000-4000-8000-0000000000c1', NULL)$q$,
    'Not authorized');

  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  r := public.generate_due_subscription_orders('00000000-0000-4000-8000-0000000000c1', NULL);
  PERFORM pg_temp.assert_eq('one order', jsonb_array_length(r->'created'), 1);

  -- Customer c1 is at (14.62, 121.02), outside the 1 km free zone.
  q := public.compute_delivery_quote('00000000-0000-4000-8000-0000000000a1', 14.62, 121.02, NULL, 3);
  PERFORM pg_temp.assert_eq('delivery fee from quote',
    (r->'created'->0->>'delivery_fee')::numeric, (q->>'fee')::numeric);
  PERFORM pg_temp.assert_eq('subtotal from live price',
    (r->'created'->0->>'subtotal')::numeric, 58.80::numeric);
  PERFORM pg_temp.assert_eq('distance stored',
    (SELECT delivery_distance_km IS NOT NULL FROM public.orders
     WHERE id = (r->'created'->0->>'id')::uuid), true);

  -- Same day again: no duplicate, schedule already moved on.
  UPDATE public.customer_subscriptions SET next_delivery_date = now() - interval '1 hour' WHERE id = v_sub;
  r := public.generate_due_subscription_orders('00000000-0000-4000-8000-0000000000c1', NULL);
  PERFORM pg_temp.assert_eq('no duplicate', jsonb_array_length(r->'created'), 0);
END $$;

-- unverified_station_subscription_is_skipped_not_advanced
DO $$ DECLARE r jsonb; v_sub uuid := gen_random_uuid(); v_due timestamptz := now() - interval '2 hours'; BEGIN
  DELETE FROM public.customer_subscriptions;
  SET LOCAL session_replication_role = replica;
  UPDATE public.profiles SET verification_status = 'pending' WHERE id = '00000000-0000-4000-8000-0000000000a1';
  SET LOCAL session_replication_role = origin;
  INSERT INTO public.customer_subscriptions (id, customer_id, station_id, station_name, quantity,
    water_type, delivery_address, next_delivery_date, product_id)
  VALUES (v_sub, '00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000a1',
    'T Station', 1, 'T Water', 'Test', v_due, '00000000-0000-4000-8000-0000000000b1');
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  r := public.generate_due_subscription_orders('00000000-0000-4000-8000-0000000000c1', NULL);
  PERFORM pg_temp.assert_eq('skipped', r->'skipped'->0->>'reason', 'not_allowed');
  PERFORM pg_temp.assert_eq('stays due',
    (SELECT next_delivery_date FROM public.customer_subscriptions WHERE id = v_sub), v_due);
END $$;

-- admin_can_remove_accessories_not_water
DO $$ BEGIN
  SET LOCAL session_replication_role = replica;
  INSERT INTO public.products (id, owner_id, name, price, category, kind, is_available)
  VALUES ('00000000-0000-4000-8000-0000000000b9', '00000000-0000-4000-8000-0000000000a1',
          'Old cap', 5, 'cap', 'accessory', true);
  SET LOCAL session_replication_role = origin;

  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
  PERFORM pg_temp.expect_error('owner cannot use admin delete',
    $q$SELECT public.admin_delete_product('00000000-0000-4000-8000-0000000000b9', 'x')$q$, 'Forbidden');

  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000e1');
  PERFORM pg_temp.expect_error('water stays',
    $q$SELECT public.admin_delete_product('00000000-0000-4000-8000-0000000000b1', 'x')$q$,
    'water type');
  PERFORM public.admin_delete_product('00000000-0000-4000-8000-0000000000b9', 'Listed by mistake');
  PERFORM pg_temp.assert_eq('accessory removed',
    (SELECT count(*) FROM public.products WHERE id = '00000000-0000-4000-8000-0000000000b9'), 0::bigint);
END $$;

SELECT 'restore_missing_rpcs_test: all passed' AS result;
