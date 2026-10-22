-- Run: BEGIN; qrph_payment_method.sql; _fixtures.sql; this file; ROLLBACK;

-- qrph_available_by_default (owner a1 has no enabled_payment_methods)
DO $$ DECLARE n int; BEGIN
  PERFORM pg_temp.assert_eq('qrph default',
    public.is_station_payment_method_available('00000000-0000-4000-8000-0000000000a1', 'qrph'), true);
  SELECT count(*) INTO n
  FROM public.get_station_available_payment_methods('00000000-0000-4000-8000-0000000000a1');
  PERFORM pg_temp.assert_eq('method rows', n, 5);
  PERFORM pg_temp.assert_eq('qrph label',
    (SELECT label FROM public.get_station_available_payment_methods('00000000-0000-4000-8000-0000000000a1') WHERE type = 'qrph'),
    'QR Ph');
END $$;

-- qrph_respects_explicit_station_list
DO $$ BEGIN
  UPDATE public.owner_settings SET enabled_payment_methods = ARRAY['cod', 'gcash']
  WHERE owner_id = '00000000-0000-4000-8000-0000000000a1';
  PERFORM pg_temp.assert_eq('qrph explicit off',
    public.is_station_payment_method_available('00000000-0000-4000-8000-0000000000a1', 'qrph'), false);
  PERFORM pg_temp.assert_eq('gcash explicit on',
    public.is_station_payment_method_available('00000000-0000-4000-8000-0000000000a1', 'gcash'), true);
  UPDATE public.owner_settings SET enabled_payment_methods = DEFAULT
  WHERE owner_id = '00000000-0000-4000-8000-0000000000a1';
END $$;

-- station_without_settings_row_gets_qrph
DO $$ BEGIN
  DELETE FROM public.owner_settings WHERE owner_id = '00000000-0000-4000-8000-0000000000a2';
  PERFORM pg_temp.assert_eq('qrph no settings row',
    public.is_station_payment_method_available('00000000-0000-4000-8000-0000000000a2', 'qrph'), true);
END $$;

-- qrph_order_can_be_placed
DO $$ DECLARE r jsonb; BEGIN
  r := pg_temp.place_order('qrph');
  PERFORM pg_temp.assert_eq('qrph order method',
    (SELECT payment_method FROM public.orders WHERE id = (r->>'id')::uuid), 'qrph');
  INSERT INTO public.payment_checkouts (order_id, customer_id, owner_id, payment_method, provider_checkout_id, checkout_url, amount, status)
  VALUES ((r->>'id')::uuid, '00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000a1', 'qrph', 'cs_test_qrph', 'https://example.test', 25.25, 'active');
END $$;

SELECT 'qrph_payment_method_test: all passed' AS result;
