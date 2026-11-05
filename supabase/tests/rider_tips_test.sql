-- Run: bash build.sh ../scripts/delivery_coverage.sql ../scripts/station_accessories.sql ../scripts/rider_tips.sql ../scripts/order_pricing_v3.sql -- rider_tips_test.sql

-- tip_added_to_total
DO $$ DECLARE r jsonb; BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  r := public.create_order_atomic(
    jsonb_build_object('owner_id', '00000000-0000-4000-8000-0000000000a1', 'payment_method', 'cod',
      'customer_name', 'T Cust', 'customer_address', 'Test', 'customer_latitude', '14.6',
      'customer_longitude', '121.0', 'tip_amount', '20'),
    jsonb_build_array(jsonb_build_object('product_id', '00000000-0000-4000-8000-0000000000b1', 'quantity', 1, 'product_name', 'T Water')));
  PERFORM pg_temp.assert_eq('tip echoed', (r->>'tip_amount')::numeric, 20::numeric);
  PERFORM pg_temp.assert_eq('total includes tip',
    (r->>'total_amount')::numeric,
    (r->>'subtotal')::numeric + (r->>'delivery_fee')::numeric + (r->>'platform_fee')::numeric + 20);
END $$;

-- tip_over_500_rejected
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  PERFORM pg_temp.expect_error('tip cap',
    $q$SELECT public.create_order_atomic(
      jsonb_build_object('owner_id', '00000000-0000-4000-8000-0000000000a1', 'payment_method', 'cod',
        'customer_name', 'T', 'customer_address', 'T', 'customer_latitude', '14.6', 'customer_longitude', '121.0',
        'tip_amount', '501'),
      jsonb_build_array(jsonb_build_object('product_id', '00000000-0000-4000-8000-0000000000b1', 'quantity', 1, 'product_name', 'T Water')))$q$,
    'Tip must be between');
END $$;

-- delivered_order_pays_tip_to_rider_not_station
DO $$ DECLARE r jsonb; v_id uuid; v_total numeric; v_fee numeric; BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  r := public.create_order_atomic(
    jsonb_build_object('owner_id', '00000000-0000-4000-8000-0000000000a1', 'payment_method', 'cod',
      'customer_name', 'T Cust', 'customer_address', 'Test', 'customer_latitude', '14.6',
      'customer_longitude', '121.0', 'tip_amount', 50),
    jsonb_build_array(jsonb_build_object('product_id', '00000000-0000-4000-8000-0000000000b1', 'quantity', 2, 'product_name', 'T Water')));
  v_id := (r->>'id')::uuid;
  v_total := (r->>'total_amount')::numeric;
  v_fee := (r->>'platform_fee')::numeric;
  SET LOCAL session_replication_role = replica;
  UPDATE public.orders SET status = 'out_for_delivery', assigned_rider_id = '00000000-0000-4000-8000-0000000000d1' WHERE id = v_id;
  SET LOCAL session_replication_role = origin;
  UPDATE public.orders SET status = 'delivered' WHERE id = v_id;

  PERFORM pg_temp.assert_eq('rider tip',
    (SELECT amount FROM public.ledger_entries WHERE order_id = v_id AND entry_type = 'RIDER_TIP'), 50::numeric);
  PERFORM pg_temp.assert_eq('station sale excludes tip',
    (SELECT amount FROM public.ledger_entries WHERE order_id = v_id AND entry_type = 'SALE'), v_total - v_fee - 50);
  PERFORM pg_temp.assert_eq('commission excludes tip',
    (SELECT round(amount, 2) FROM public.ledger_entries WHERE order_id = v_id AND entry_type = 'COMMISSION'),
    round((v_total - 50) * 0.10, 2));
END $$;

SELECT 'rider_tips_test: all passed' AS result;
