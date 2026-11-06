-- Run: bash build.sh ../scripts/harden_signup_and_protected_columns.sql ../scripts/delivery_coverage.sql ../scripts/station_accessories.sql ../scripts/rider_tips.sql ../scripts/identity_verification.sql ../scripts/order_pricing_v3.sql -- accessories_test.sql

-- COD is locked when the station's service-fee wallet is at or below zero
-- (station_cod_locked); give the fixture station a funded wallet.
INSERT INTO public.station_fee_wallets (owner_id, balance)
VALUES ('00000000-0000-4000-8000-0000000000a1', 1000)
ON CONFLICT (owner_id) DO UPDATE SET balance = 1000;

-- Fixture station must be verified to take orders (identity_verification.sql).
UPDATE public.profiles SET verification_status = 'approved' WHERE id = '00000000-0000-4000-8000-0000000000a1';
-- Owner a1 has water product b1 (₱19.60).

-- owner_can_add_an_accessory
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1'); SET LOCAL ROLE authenticated;
  INSERT INTO public.products (id, owner_id, name, price, category, kind, stock_level, is_available)
  VALUES ('00000000-0000-4000-8000-0000000000b2', '00000000-0000-4000-8000-0000000000a1',
          'Gallon cap', 5, 'cap', 'accessory', 3, true);
  RESET ROLE;
  PERFORM pg_temp.assert_eq('accessory added',
    (SELECT count(*) FROM public.products WHERE owner_id = '00000000-0000-4000-8000-0000000000a1'), 2::bigint);
END $$;

-- owner_cannot_add_a_second_water_product
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1'); SET LOCAL ROLE authenticated;
  PERFORM pg_temp.expect_error('second water',
    $q$INSERT INTO public.products (owner_id, name, price, kind)
       VALUES ('00000000-0000-4000-8000-0000000000a1', 'More water', 10, 'water')$q$,
    'row-level security');
  RESET ROLE;
END $$;

-- owner_cannot_add_accessory_for_another_station
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1'); SET LOCAL ROLE authenticated;
  PERFORM pg_temp.expect_error('other station',
    $q$INSERT INTO public.products (owner_id, name, price, category, kind)
       VALUES ('00000000-0000-4000-8000-0000000000a2', 'Seal', 2, 'seal', 'accessory')$q$,
    'row-level security');
  RESET ROLE;
END $$;

-- accessory_rename_allowed_water_rename_blocked
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1'); SET LOCAL ROLE authenticated;
  UPDATE public.products SET name = 'Blue cap' WHERE id = '00000000-0000-4000-8000-0000000000b2';
  PERFORM pg_temp.expect_error('water rename',
    $q$UPDATE public.products SET name = 'Renamed' WHERE id = '00000000-0000-4000-8000-0000000000b1'$q$,
    'Stations can only change the price and availability of their water.');
  RESET ROLE;
  PERFORM pg_temp.assert_eq('renamed',
    (SELECT name FROM public.products WHERE id = '00000000-0000-4000-8000-0000000000b2'), 'Blue cap');
END $$;

-- accessory_price_does_not_overwrite_water_price
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1'); SET LOCAL ROLE authenticated;
  UPDATE public.products SET price = 7 WHERE id = '00000000-0000-4000-8000-0000000000b2';
  RESET ROLE;
  PERFORM pg_temp.assert_eq('water price kept',
    (SELECT price_per_gallon::numeric FROM public.profiles WHERE id = '00000000-0000-4000-8000-0000000000a1')
      IS DISTINCT FROM 7, true);
END $$;

-- order_with_accessory_priced_on_server_and_stock_deducted
DO $$ DECLARE r jsonb; BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  r := public.create_order_atomic(
    jsonb_build_object('owner_id', '00000000-0000-4000-8000-0000000000a1', 'payment_method', 'cod',
      'customer_name', 'T Cust', 'customer_address', 'Test', 'customer_latitude', '14.6', 'customer_longitude', '121.0'),
    jsonb_build_array(
      jsonb_build_object('product_id', '00000000-0000-4000-8000-0000000000b1', 'quantity', 2, 'product_name', 'T Water'),
      jsonb_build_object('product_id', '00000000-0000-4000-8000-0000000000b2', 'quantity', 2, 'product_name', 'Blue cap', 'price', 0.01))
  );
  PERFORM pg_temp.assert_eq('subtotal', (r->>'subtotal')::numeric, (19.6 * 2 + 7 * 2)::numeric);
  PERFORM pg_temp.assert_eq('stock deducted',
    (SELECT stock_level FROM public.products WHERE id = '00000000-0000-4000-8000-0000000000b2'), 1);
END $$;

-- accessories_do_not_count_toward_free_gallons
DO $$ DECLARE q jsonb; r jsonb; BEGIN
  UPDATE public.owner_settings SET free_delivery_min_gallons = 3, free_delivery_radius_km = 0
  WHERE owner_id = '00000000-0000-4000-8000-0000000000a1';
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  r := public.create_order_atomic(
    jsonb_build_object('owner_id', '00000000-0000-4000-8000-0000000000a1', 'payment_method', 'cod',
      'customer_name', 'T Cust', 'customer_address', 'Test', 'customer_latitude', '14.65', 'customer_longitude', '121.0'),
    jsonb_build_array(
      jsonb_build_object('product_id', '00000000-0000-4000-8000-0000000000b1', 'quantity', 2, 'product_name', 'T Water'),
      jsonb_build_object('product_id', '00000000-0000-4000-8000-0000000000b2', 'quantity', 1, 'product_name', 'Blue cap'))
  );
  PERFORM pg_temp.assert_eq('not free', (r->>'delivery_free_reason') IS NULL, true);
END $$;

SELECT 'accessories_test: all passed' AS result;
