-- Run: bash build.sh ../scripts/harden_signup_and_protected_columns.sql ../scripts/delivery_coverage.sql ../scripts/station_accessories.sql ../scripts/rider_tips.sql ../scripts/identity_verification.sql ../scripts/order_pricing_v3.sql -- delivery_quote_test.sql

-- Fixture station must be verified to take orders (identity_verification.sql).
UPDATE public.profiles SET verification_status = 'approved' WHERE id = '00000000-0000-4000-8000-0000000000a1';
-- Owner a1 is at (14.60, 121.00). Config below: ₱10/km, ₱20 minimum, 1 km minimum billable, exact distance, whole-peso fee.

UPDATE public.system_config
SET value = '{"enabled": true, "rate_per_km": 10, "minimum_fee": 20, "min_billable_distance_km": 1, "rounding_rule": "exact"}'::jsonb
WHERE key = 'delivery_fee_config';
INSERT INTO public.system_config (key, value)
SELECT 'delivery_fee_config', '{"enabled": true, "rate_per_km": 10, "minimum_fee": 20, "min_billable_distance_km": 1, "rounding_rule": "exact"}'::jsonb
WHERE NOT EXISTS (SELECT 1 FROM public.system_config WHERE key = 'delivery_fee_config');

-- free_inside_default_radius (same point -> 0 km, default 1 km radius)
DO $$ DECLARE q jsonb; BEGIN
  q := public.compute_delivery_quote('00000000-0000-4000-8000-0000000000a1', 14.60, 121.00);
  PERFORM pg_temp.assert_eq('free radius', (q->>'is_free')::boolean, true);
  PERFORM pg_temp.assert_eq('reason radius', q->>'free_reason', 'radius');
  PERFORM pg_temp.assert_eq('fee 0', (q->>'fee')::numeric, 0::numeric);
END $$;

-- per_km_outside_radius (~0.05 deg lat = 5.56 km * 1.3 = 7.23 km -> round(72.3) = 72)
DO $$ DECLARE q jsonb; BEGIN
  q := public.compute_delivery_quote('00000000-0000-4000-8000-0000000000a1', 14.65, 121.00);
  PERFORM pg_temp.assert_eq('not free', (q->>'is_free')::boolean, false);
  PERFORM pg_temp.assert_eq('distance', round((q->>'distance_km')::numeric, 1), 7.2::numeric);
  PERFORM pg_temp.assert_eq('fee per km', (q->>'fee')::numeric, 72::numeric);
END $$;

-- minimum_fee_applies_just_outside_radius (~1.3 km road -> 13 -> minimum 20)
DO $$ DECLARE q jsonb; BEGIN
  q := public.compute_delivery_quote('00000000-0000-4000-8000-0000000000a1', 14.609, 121.00);
  PERFORM pg_temp.assert_eq('minimum', (q->>'fee')::numeric, 20::numeric);
END $$;

-- free_barangay_list_is_case_insensitive
DO $$ DECLARE q jsonb; BEGIN
  UPDATE public.owner_settings SET free_delivery_barangays = ARRAY['Poblacion']
  WHERE owner_id = '00000000-0000-4000-8000-0000000000a1';
  q := public.compute_delivery_quote('00000000-0000-4000-8000-0000000000a1', 14.65, 121.00, ' poblacion ');
  PERFORM pg_temp.assert_eq('barangay free', q->>'free_reason', 'barangay');
END $$;

-- free_by_minimum_gallons
DO $$ DECLARE q jsonb; BEGIN
  UPDATE public.owner_settings SET free_delivery_min_gallons = 5
  WHERE owner_id = '00000000-0000-4000-8000-0000000000a1';
  q := public.compute_delivery_quote('00000000-0000-4000-8000-0000000000a1', 14.65, 121.00, NULL, 4);
  PERFORM pg_temp.assert_eq('4 gal pays', (q->>'is_free')::boolean, false);
  q := public.compute_delivery_quote('00000000-0000-4000-8000-0000000000a1', 14.65, 121.00, NULL, 5);
  PERFORM pg_temp.assert_eq('5 gal free', q->>'free_reason', 'min_gallons');
END $$;

-- missing_customer_pin_charges_minimum
DO $$ DECLARE q jsonb; BEGIN
  q := public.compute_delivery_quote('00000000-0000-4000-8000-0000000000a1', NULL, NULL);
  PERFORM pg_temp.assert_eq('no pin minimum', (q->>'fee')::numeric, 20::numeric);
END $$;

-- order_charges_server_quote_not_client_fee
DO $$ DECLARE r jsonb; BEGIN
  UPDATE public.owner_settings
  SET free_delivery_barangays = '{}', free_delivery_min_gallons = NULL, base_delivery_fee = 99
  WHERE owner_id = '00000000-0000-4000-8000-0000000000a1';
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  r := public.create_order_atomic(
    jsonb_build_object(
      'owner_id', '00000000-0000-4000-8000-0000000000a1',
      'payment_method', 'cod',
      'customer_name', 'T Cust',
      'customer_address', 'Test address',
      'customer_latitude', '14.65',
      'customer_longitude', '121.0',
      'delivery_fee', 0
    ),
    jsonb_build_array(jsonb_build_object(
      'product_id', '00000000-0000-4000-8000-0000000000b1', 'quantity', 1, 'product_name', 'T Water'))
  );
  PERFORM pg_temp.assert_eq('order fee', (r->>'delivery_fee')::numeric, 72::numeric);
  PERFORM pg_temp.assert_eq('stored distance',
    (SELECT round(delivery_distance_km, 1) FROM public.orders WHERE id = (r->>'id')::uuid), 7.2::numeric);
END $$;

-- order_inside_zone_is_free
DO $$ DECLARE r jsonb; BEGIN
  r := pg_temp.place_order('cod');  -- customer pin (14.6, 121.0) = station
  PERFORM pg_temp.assert_eq('free order', (r->>'delivery_fee')::numeric, 0::numeric);
  PERFORM pg_temp.assert_eq('free reason', r->>'delivery_free_reason', 'radius');
END $$;

SELECT 'delivery_quote_test: all passed' AS result;
