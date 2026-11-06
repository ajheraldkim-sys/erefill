-- Run: BEGIN; pay_before_fulfilment_guard.sql; _fixtures.sql; this file; ROLLBACK;

-- three_orders_marked_paid
DO $$ BEGIN
  PERFORM pg_temp.assert_eq('three marked paid',
    (SELECT count(*) FROM public.orders
     WHERE id IN ('8d2dc6e9-c8c3-4fd1-aa97-be2bbc4f60c8', '74ba3859-06d0-4b77-b086-a84078bfdfdf', '0ce436d4-a5c7-4d1f-96af-035985f71cfe')
       AND payment_status = 'success'), 3::bigint);
END $$;

-- guard_blocks_accept_of_unpaid_online_order
DO $$ DECLARE r jsonb; BEGIN
  r := pg_temp.place_order('gcash');
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
  PERFORM pg_temp.expect_error('accept unpaid gcash',
    format('SELECT public.transition_order_status_safely(%L, %L)', r->>'id', 'accepted'),
    'This order is waiting for online payment.');
END $$;

-- guard_allows_paid_online_order
DO $$ DECLARE r jsonb; BEGIN
  r := pg_temp.place_order('card');
  UPDATE public.orders SET payment_status = 'success' WHERE id = (r->>'id')::uuid;
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
  PERFORM public.transition_order_status_safely((r->>'id')::uuid, 'accepted');
  PERFORM pg_temp.assert_eq('paid accepted',
    (SELECT status::text FROM public.orders WHERE id = (r->>'id')::uuid), 'accepted');
END $$;

-- guard_allows_cod
DO $$ DECLARE r jsonb; BEGIN
  r := pg_temp.place_order('cod');
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
  PERFORM public.transition_order_status_safely((r->>'id')::uuid, 'accepted');
  PERFORM pg_temp.assert_eq('cod accepted',
    (SELECT status::text FROM public.orders WHERE id = (r->>'id')::uuid), 'accepted');
END $$;

-- guard_allows_cancel_of_unpaid_online_order (owner, then customer)
DO $$ DECLARE r jsonb; r2 jsonb; BEGIN
  r := pg_temp.place_order('maya');
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
  PERFORM public.transition_order_status_safely((r->>'id')::uuid, 'cancelled');
  PERFORM pg_temp.assert_eq('owner cancel',
    (SELECT status::text FROM public.orders WHERE id = (r->>'id')::uuid), 'cancelled');
  r2 := pg_temp.place_order('card');
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  PERFORM public.transition_order_status_safely((r2->>'id')::uuid, 'cancelled');
  PERFORM pg_temp.assert_eq('customer cancel',
    (SELECT status::text FROM public.orders WHERE id = (r2->>'id')::uuid), 'cancelled');
END $$;

-- guard_blocks_confirm_delivery_unpaid (order forced out for delivery while unpaid)
DO $$ DECLARE r jsonb; BEGIN
  r := pg_temp.place_order('gcash');
  SET LOCAL session_replication_role = replica;
  UPDATE public.orders
  SET status = 'out_for_delivery', assigned_rider_id = '00000000-0000-4000-8000-0000000000d1'
  WHERE id = (r->>'id')::uuid;
  SET LOCAL session_replication_role = origin;
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000d1');
  PERFORM pg_temp.expect_error('confirm unpaid',
    format('SELECT public.confirm_delivery_safely(%L)', r->>'id'),
    'This order is waiting for online payment.');
END $$;

SELECT 'pay_before_fulfilment_guard_test: all passed' AS result;
