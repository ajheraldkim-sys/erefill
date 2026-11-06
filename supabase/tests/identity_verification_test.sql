-- Run: bash build.sh ../scripts/harden_signup_and_protected_columns.sql ../scripts/delivery_coverage.sql ../scripts/station_accessories.sql ../scripts/rider_tips.sql ../scripts/identity_verification.sql ../scripts/order_pricing_v3.sql -- identity_verification_test.sql

-- COD is locked when the station's service-fee wallet is at or below zero
-- (station_cod_locked); give the fixture station a funded wallet.
INSERT INTO public.station_fee_wallets (owner_id, balance)
VALUES ('00000000-0000-4000-8000-0000000000a1', 1000)
ON CONFLICT (owner_id) DO UPDATE SET balance = 1000;
-- Fixture owner a1 starts 'unverified' (no delivered orders).

-- unverified_station_cannot_take_orders
DO $$ BEGIN
  PERFORM pg_temp.expect_error('unverified station', $q$SELECT pg_temp.place_order('cod')$q$,
    'This station is not verified yet');
END $$;

-- customer_cannot_self_approve_via_table
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1'); SET LOCAL ROLE authenticated;
  PERFORM pg_temp.expect_error('direct insert',
    $q$INSERT INTO public.identity_verifications (user_id, role, id_type, front_path, selfie_path, status)
       VALUES ('00000000-0000-4000-8000-0000000000c1', 'customer', 'philsys', 'x', 'y', 'approved')$q$,
    'permission denied');
  RESET ROLE;
END $$;

-- submit_rejects_paths_outside_own_folder
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  PERFORM pg_temp.expect_error('foreign path',
    $q$SELECT public.submit_identity_verification('philsys', '1234',
       '00000000-0000-4000-8000-0000000000a1/front.jpg', NULL,
       '00000000-0000-4000-8000-0000000000c1/selfie.jpg')$q$,
    'Upload your ID photos');
END $$;

-- owner_needs_permit
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
  PERFORM pg_temp.expect_error('permit',
    $q$SELECT public.submit_identity_verification('umid', '9876',
       '00000000-0000-4000-8000-0000000000a1/front.jpg', NULL,
       '00000000-0000-4000-8000-0000000000a1/selfie.jpg')$q$,
    'business or sanitary permit');
END $$;

-- owner_submits_admin_approves_orders_flow
DO $$ DECLARE v jsonb; r jsonb; BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
  v := public.submit_identity_verification('umid', '9876',
       '00000000-0000-4000-8000-0000000000a1/front.jpg', '00000000-0000-4000-8000-0000000000a1/back.jpg',
       '00000000-0000-4000-8000-0000000000a1/selfie.jpg', '00000000-0000-4000-8000-0000000000a1/permit.pdf');
  PERFORM pg_temp.assert_eq('pending', (SELECT verification_status FROM public.profiles WHERE id = '00000000-0000-4000-8000-0000000000a1'), 'pending');

  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  PERFORM pg_temp.expect_error('non-admin review',
    format('SELECT public.admin_review_identity_verification(%L, true)', v->>'id'), 'Forbidden');

  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000e1');
  PERFORM public.admin_review_identity_verification((v->>'id')::uuid, true);
  PERFORM pg_temp.assert_eq('approved', (SELECT verification_status FROM public.profiles WHERE id = '00000000-0000-4000-8000-0000000000a1'), 'approved');

  r := pg_temp.place_order('cod');
  PERFORM pg_temp.assert_eq('order placed', r ? 'id', true);
END $$;

-- unverified_customer_cod_limits
DO $$ BEGIN
  PERFORM pg_temp.expect_error('cod over 1000', $q$SELECT pg_temp.place_order('cod', 60)$q$,
    'above PHP 1,000');
  PERFORM pg_temp.place_order('cod');  -- second active COD order (first placed above)
  PERFORM pg_temp.expect_error('third cod', $q$SELECT pg_temp.place_order('cod')$q$,
    'more than 2 cash-on-delivery');
END $$;

-- rejection_needs_reason
DO $$ DECLARE v jsonb; BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  v := public.submit_identity_verification('philsys', '1234',
       '00000000-0000-4000-8000-0000000000c1/front.jpg', NULL, '00000000-0000-4000-8000-0000000000c1/selfie.jpg');
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000e1');
  PERFORM pg_temp.expect_error('no reason',
    format('SELECT public.admin_review_identity_verification(%L, false)', v->>'id'), 'reason');
  PERFORM public.admin_review_identity_verification((v->>'id')::uuid, false, 'Photo is blurry');
  PERFORM pg_temp.assert_eq('rejected', (SELECT verification_status FROM public.profiles WHERE id = '00000000-0000-4000-8000-0000000000c1'), 'rejected');
END $$;

SELECT 'identity_verification_test: all passed' AS result;
