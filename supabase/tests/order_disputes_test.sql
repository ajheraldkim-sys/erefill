-- Run: bash build.sh ../scripts/order_disputes.sql -- order_disputes_test.sql
SET LOCAL session_replication_role = replica;
INSERT INTO public.orders (id, customer_id, owner_id, status, total_amount, payment_method, updated_at, created_at) VALUES
  ('00000000-0000-4000-8000-00000000f201', '00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000a1', 'delivered', 80, 'cod', now() - interval '2 hours', now() - interval '3 hours'),
  ('00000000-0000-4000-8000-00000000f202', '00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000a1', 'delivered', 80, 'gcash', now() - interval '3 days', now() - interval '3 days'),
  ('00000000-0000-4000-8000-00000000f203', '00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000a1', 'pending', 80, 'cod', now(), now());
SET LOCAL session_replication_role = origin;

-- only_recent_delivered_orders
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  PERFORM pg_temp.expect_error('too old',
    $q$SELECT public.open_dispute('00000000-0000-4000-8000-00000000f202', 'quality', 'Smells odd')$q$, '48 hours');
  PERFORM pg_temp.expect_error('not delivered',
    $q$SELECT public.open_dispute('00000000-0000-4000-8000-00000000f203', 'quality', 'x')$q$, 'once the order is delivered');
END $$;

-- open_then_station_refunds_partially
DO $$ DECLARE d jsonb; BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  d := public.open_dispute('00000000-0000-4000-8000-00000000f201', 'missing_items', 'Only 2 of 3 gallons arrived');
  PERFORM pg_temp.expect_error('duplicate',
    $q$SELECT public.open_dispute('00000000-0000-4000-8000-00000000f201', 'other', 'again')$q$, 'already reported');

  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a2');
  PERFORM pg_temp.expect_error('other station',
    format('SELECT public.owner_respond_dispute(%L, true, %L, 20)', d->>'id', 'sorry'), 'not found');

  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
  PERFORM public.owner_respond_dispute((d->>'id')::uuid, true, 'Sorry, refunding one gallon', 25);

  PERFORM pg_temp.assert_eq('resolved', (SELECT status::text FROM public.disputes WHERE id = (d->>'id')::uuid), 'resolved');
  PERFORM pg_temp.assert_eq('ledger refund',
    (SELECT amount FROM public.ledger_entries WHERE order_id = '00000000-0000-4000-8000-00000000f201' AND entry_type = 'REFUND'), -25::numeric);
  PERFORM pg_temp.assert_eq('flagged',
    (SELECT flagged_count FROM public.profiles WHERE id = '00000000-0000-4000-8000-0000000000a1') >= 1, true);
  PERFORM pg_temp.assert_eq('partial keeps payment status',
    (SELECT payment_status::text FROM public.orders WHERE id = '00000000-0000-4000-8000-00000000f201') <> 'refunded', true);
END $$;

-- station_explains_then_admin_dismisses
DO $$ DECLARE d jsonb; BEGIN
  DELETE FROM public.disputes;
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  d := public.open_dispute('00000000-0000-4000-8000-00000000f201', 'quality', 'Cloudy water');
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
  PERFORM public.owner_respond_dispute((d->>'id')::uuid, false, 'Our lab test from last week is clean');
  PERFORM pg_temp.assert_eq('escalated', (SELECT status::text FROM public.disputes WHERE id = (d->>'id')::uuid), 'investigating');

  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000e1');
  PERFORM public.admin_resolve_dispute((d->>'id')::uuid, 0, 'Lab test confirms water is safe');
  PERFORM pg_temp.assert_eq('dismissed', (SELECT status::text FROM public.disputes WHERE id = (d->>'id')::uuid), 'dismissed');
END $$;

-- customer_cannot_insert_directly
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1'); SET LOCAL ROLE authenticated;
  PERFORM pg_temp.expect_error('direct',
    $q$INSERT INTO public.disputes (order_id, reporter_id, reason, description, status)
       VALUES ('00000000-0000-4000-8000-00000000f203', '00000000-0000-4000-8000-0000000000c1', 'other', 'x', 'resolved')$q$,
    'permission denied');
  RESET ROLE;
END $$;

SELECT 'order_disputes_test: all passed' AS result;
