-- Run: BEGIN; whole_peso_pricing.sql; qrph_payment_method.sql;
--      pay_before_fulfilment_guard.sql; service_fee_wallet.sql;
--      _fixtures.sql; this file; ROLLBACK;
-- Fixture station a1 has no wallet yet (balance ₱0), so COD starts locked;
-- tests that place COD orders credit it first.

CREATE OR REPLACE FUNCTION pg_temp.deliver(p_order_id uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
  PERFORM public.transition_order_status_safely(p_order_id, 'accepted');
  PERFORM public.transition_order_status_safely(p_order_id, 'preparing');
  PERFORM public.transition_order_status_safely(p_order_id, 'delivered');
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.balance() RETURNS numeric
LANGUAGE sql AS $$
  SELECT coalesce((SELECT balance FROM public.station_fee_wallets
    WHERE owner_id = '00000000-0000-4000-8000-0000000000a1'), 0);
$$;

-- cod_locked_at_zero
DO $$ BEGIN
  PERFORM pg_temp.assert_eq('locked at zero',
    public.station_cod_locked('00000000-0000-4000-8000-0000000000a1'), true);
  PERFORM pg_temp.assert_eq('cod unavailable',
    public.is_station_payment_method_available('00000000-0000-4000-8000-0000000000a1', 'cod'), false);
  PERFORM pg_temp.assert_eq('gcash still available',
    public.is_station_payment_method_available('00000000-0000-4000-8000-0000000000a1', 'gcash'), true);
  PERFORM pg_temp.assert_eq('cod reason',
    (SELECT reason FROM public.get_station_available_payment_methods('00000000-0000-4000-8000-0000000000a1') WHERE type = 'cod'),
    'Cash on Delivery is unavailable for this station right now.');
  PERFORM pg_temp.expect_error('cod order rejected',
    'SELECT pg_temp.place_order(''cod'')',
    'This payment method is not available for this station.');
END $$;

-- cod_unlocked_after_credit
DO $$ BEGIN
  PERFORM public.apply_wallet_entry('00000000-0000-4000-8000-0000000000a1', 100, 'topup');
  PERFORM pg_temp.assert_eq('unlocked', public.station_cod_locked('00000000-0000-4000-8000-0000000000a1'), false);
  PERFORM pg_temp.assert_eq('cod available',
    public.is_station_payment_method_available('00000000-0000-4000-8000-0000000000a1', 'cod'), true);
END $$;

-- deducts_fee_on_cod_delivery + sale_entry_excludes_fee (₱20 + ₱5 + ₱0.25 fee)
DO $$ DECLARE r jsonb; v_id uuid; BEGIN
  r := pg_temp.place_order('cod');
  v_id := (r->>'id')::uuid;
  PERFORM pg_temp.deliver(v_id);
  PERFORM pg_temp.assert_eq('balance after cod', pg_temp.balance(), 99.75::numeric);
  PERFORM pg_temp.assert_eq('fee entry',
    (SELECT amount FROM public.station_fee_wallet_entries WHERE order_id = v_id AND kind = 'service_fee'), -0.25::numeric);
  PERFORM pg_temp.assert_eq('sale excludes fee',
    (SELECT amount FROM public.ledger_entries WHERE order_id = v_id AND entry_type = 'SALE'), 25.00::numeric);
  PERFORM pg_temp.assert_eq('service fee ledger',
    (SELECT amount FROM public.ledger_entries WHERE order_id = v_id AND entry_type = 'SERVICE_FEE'
       AND metadata->>'payee' = 'platform'), 0.25::numeric);
END $$;

-- deduction_is_idempotent
DO $$ DECLARE v_id uuid; v_before numeric; BEGIN
  SELECT order_id INTO v_id FROM public.station_fee_wallet_entries WHERE kind = 'service_fee' LIMIT 1;
  v_before := pg_temp.balance();
  PERFORM public.apply_wallet_entry('00000000-0000-4000-8000-0000000000a1', -0.25, 'service_fee', v_id);
  PERFORM pg_temp.assert_eq('one fee entry',
    (SELECT count(*) FROM public.station_fee_wallet_entries WHERE order_id = v_id AND kind = 'service_fee'), 1::bigint);
  PERFORM pg_temp.assert_eq('balance unchanged', pg_temp.balance(), v_before);
END $$;

-- no_deduction_for_online_order
DO $$ DECLARE r jsonb; v_id uuid; v_before numeric; BEGIN
  v_before := pg_temp.balance();
  r := pg_temp.place_order('gcash');
  v_id := (r->>'id')::uuid;
  UPDATE public.orders SET payment_status = 'success' WHERE id = v_id;
  PERFORM pg_temp.deliver(v_id);
  PERFORM pg_temp.assert_eq('online no deduction', pg_temp.balance(), v_before);
  PERFORM pg_temp.assert_eq('online no fee entry',
    (SELECT count(*) FROM public.station_fee_wallet_entries WHERE order_id = v_id), 0::bigint);
END $$;

-- deduction_allows_negative_balance + low_balance_notifies_once
DO $$ DECLARE r jsonb; v_id uuid; n int; BEGIN
  -- Bring the balance to ₱0.10, then accept an order while COD is still on.
  PERFORM public.apply_wallet_entry('00000000-0000-4000-8000-0000000000a1', 0.10 - pg_temp.balance(), 'adjustment', NULL, NULL, 'test setup');
  r := pg_temp.place_order('cod');
  v_id := (r->>'id')::uuid;
  PERFORM pg_temp.deliver(v_id);
  PERFORM pg_temp.assert_eq('negative balance', pg_temp.balance(), -0.15::numeric);
  PERFORM pg_temp.assert_eq('locked when negative', public.station_cod_locked('00000000-0000-4000-8000-0000000000a1'), true);
  SELECT count(*) INTO n FROM public.system_notifications
  WHERE user_id = '00000000-0000-4000-8000-0000000000a1' AND title = 'Service fee balance is low';
  PERFORM pg_temp.assert_eq('low balance notified once', n, 1);
END $$;

-- cod_never_locked_when_fee_disabled
DO $$ BEGIN
  UPDATE public.system_config SET value = '{"enabled": false, "percent": 1, "fixed": 0}'::jsonb WHERE key = 'platform_fee';
  PERFORM pg_temp.assert_eq('fee off unlocked', public.station_cod_locked('00000000-0000-4000-8000-0000000000a1'), false);
  UPDATE public.system_config SET value = '{"enabled": true, "percent": 1, "fixed": 0}'::jsonb WHERE key = 'platform_fee';
END $$;

-- subscription_skips_cod_when_locked
DO $$ DECLARE v_sub uuid; n int; BEGIN
  INSERT INTO public.customer_subscriptions (
    customer_id, station_id, station_name, delivery_address, water_type,
    quantity, estimated_price, frequency, preferred_time_slot,
    payment_method, is_active, next_delivery_date
  ) VALUES (
    '00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000a1',
    'T Station', 'Test address', 'Purified', 1, 20, 'weekly', 'morning',
    'cod', true, now() - interval '1 minute'
  ) RETURNING id INTO v_sub;
  PERFORM public.process_due_customer_subscriptions();
  PERFORM public.process_due_customer_subscriptions();
  PERFORM pg_temp.assert_eq('no locked cod auto-order',
    (SELECT count(*) FROM public.orders WHERE idempotency_key LIKE 'auto_sub_' || v_sub || '%'), 0::bigint);
  SELECT count(*) INTO n FROM public.system_notifications
  WHERE metadata->>'subscription_id' = v_sub::text AND metadata->>'kind' = 'cod_locked_skip';
  PERFORM pg_temp.assert_eq('owner + customer notified once', n, 2);
END $$;

-- topup_rejects_below_minimum / topup_rejects_centavos
DO $$ BEGIN
  PERFORM pg_temp.expect_error('topup below minimum',
    'SELECT public.create_wallet_topup(''00000000-0000-4000-8000-0000000000a1'', 99, ''gcash'')',
    'Top-up must be a whole peso amount of at least ₱100.');
  PERFORM pg_temp.expect_error('topup centavos',
    'SELECT public.create_wallet_topup(''00000000-0000-4000-8000-0000000000a1'', 100.5, ''gcash'')',
    'Top-up must be a whole peso amount of at least ₱100.');
  PERFORM pg_temp.expect_error('topup by COD',
    'SELECT public.create_wallet_topup(''00000000-0000-4000-8000-0000000000a1'', 100, ''cod'')',
    'Unsupported payment method.');
END $$;

-- topup_credit_is_idempotent + topup_unlocks_cod (balance is -0.15 here)
DO $$ DECLARE v_topup uuid; v_before numeric; BEGIN
  v_before := pg_temp.balance();
  v_topup := public.create_wallet_topup('00000000-0000-4000-8000-0000000000a1', 100, 'qrph');
  PERFORM public.record_wallet_topup_checkout(v_topup, 'cs_test_topup_1', 'https://pay.example/t', false);
  PERFORM pg_temp.assert_eq('pending before pay',
    (SELECT status FROM public.station_fee_topups WHERE id = v_topup), 'pending');
  PERFORM public.credit_wallet_topup(v_topup);
  PERFORM public.credit_wallet_topup(v_topup);
  PERFORM pg_temp.assert_eq('one topup entry',
    (SELECT count(*) FROM public.station_fee_wallet_entries WHERE topup_id = v_topup AND kind = 'topup'), 1::bigint);
  PERFORM pg_temp.assert_eq('credited once', pg_temp.balance(), v_before + 100);
  PERFORM pg_temp.assert_eq('paid', (SELECT status FROM public.station_fee_topups WHERE id = v_topup), 'paid');
  PERFORM pg_temp.assert_eq('topup unlocks cod', public.station_cod_locked('00000000-0000-4000-8000-0000000000a1'), false);
END $$;

-- admin_rpcs_require_admin / admin_adjust_requires_reason / admin_adjust_writes_entry_and_audit
DO $$ DECLARE v_before numeric; v_after numeric; BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
  PERFORM pg_temp.expect_error('owner cannot list wallets',
    'SELECT * FROM public.admin_list_fee_wallets()', 'Admin access required.');
  PERFORM pg_temp.expect_error('owner cannot adjust',
    'SELECT public.admin_adjust_fee_wallet(''00000000-0000-4000-8000-0000000000a1'', 50, ''x'')', 'Admin access required.');

  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000e1');
  PERFORM pg_temp.expect_error('blank reason',
    'SELECT public.admin_adjust_fee_wallet(''00000000-0000-4000-8000-0000000000a1'', 50, ''  '')',
    'A reason is required for a wallet adjustment.');
  v_before := pg_temp.balance();
  v_after := public.admin_adjust_fee_wallet('00000000-0000-4000-8000-0000000000a1', 50, 'Demo credit');
  PERFORM pg_temp.assert_eq('adjusted', v_after, v_before + 50);
  PERFORM pg_temp.assert_eq('adjust entry',
    (SELECT note FROM public.station_fee_wallet_entries WHERE kind = 'adjustment' ORDER BY created_at DESC LIMIT 1), 'Demo credit');
  PERFORM pg_temp.assert_eq('audit row',
    (SELECT count(*) FROM public.audit_logs WHERE action = 'FEE_WALLET_ADJUST' AND entity_id = '00000000-0000-4000-8000-0000000000a1'), 1::bigint);
  PERFORM pg_temp.assert_eq('listed balance',
    (SELECT balance FROM public.admin_list_fee_wallets() WHERE owner_id = '00000000-0000-4000-8000-0000000000a1'), v_after);
END $$;

-- rls_owner_reads_own_wallet_only (no pg_temp helpers: they belong to postgres)
DO $$ BEGIN
  PERFORM public.apply_wallet_entry('00000000-0000-4000-8000-0000000000a2', 50, 'topup');
END $$;
SELECT set_config('request.jwt.claims', '{"sub": "00000000-0000-4000-8000-0000000000a1", "role": "authenticated"}', true);
SET LOCAL ROLE authenticated;
DO $$ DECLARE n int; BEGIN
  SELECT count(*) INTO n FROM public.station_fee_wallets;
  IF n <> 1 THEN RAISE EXCEPTION 'owner sees own wallet only — got % rows', n; END IF;
  BEGIN
    INSERT INTO public.station_fee_wallet_entries (owner_id, amount, kind)
    VALUES ('00000000-0000-4000-8000-0000000000a1', 1000, 'topup');
    RAISE EXCEPTION 'owner could write a wallet entry';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.apply_wallet_entry('00000000-0000-4000-8000-0000000000a1', 1000, 'topup');
    RAISE EXCEPTION 'owner could call apply_wallet_entry';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
RESET ROLE;

SELECT 'service_fee_wallet_test: all passed' AS result;
