-- Run: bash build.sh ../scripts/harden_signup_and_protected_columns.sql ../scripts/identity_verification.sql ../scripts/water_quality_certs.sql ../scripts/water_tested_badge.sql -- water_tested_badge_test.sql

-- approved_lab_test_sets_water_tested_until
DO $$ DECLARE v jsonb; BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
  v := public.submit_station_certification('bacteriological', current_date - 30, current_date + 150,
         '00000000-0000-4000-8000-0000000000a1/certs/lab.pdf');
  PERFORM pg_temp.assert_eq('pending: not tested',
    (SELECT water_tested_until FROM public.profiles WHERE id = '00000000-0000-4000-8000-0000000000a1'), NULL::date);

  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000e1');
  PERFORM public.admin_review_station_certification((v->>'id')::uuid, true);
  PERFORM pg_temp.assert_eq('approved: tested until expiry',
    (SELECT water_tested_until FROM public.profiles WHERE id = '00000000-0000-4000-8000-0000000000a1'), current_date + 150);
END $$;

-- permits_do_not_count
DO $$ DECLARE v jsonb; BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a2');
  v := public.submit_station_certification('sanitary_permit', current_date - 30, current_date + 300,
         '00000000-0000-4000-8000-0000000000a2/certs/permit.pdf');
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000e1');
  PERFORM public.admin_review_station_certification((v->>'id')::uuid, true);
  PERFORM pg_temp.assert_eq('permit only',
    (SELECT water_tested_until FROM public.profiles WHERE id = '00000000-0000-4000-8000-0000000000a2'), NULL::date);
END $$;

-- expiry_clears_it
DO $$ BEGIN
  UPDATE public.station_certifications SET expires_on = current_date, issued_on = current_date - 300
  WHERE owner_id = '00000000-0000-4000-8000-0000000000a1';
  PERFORM public.expire_station_certifications();
  PERFORM pg_temp.assert_eq('expired',
    (SELECT water_tested_until FROM public.profiles WHERE id = '00000000-0000-4000-8000-0000000000a1'), NULL::date);
END $$;

-- owner_cannot_set_it
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1'); SET LOCAL ROLE authenticated;
  PERFORM pg_temp.expect_error('self set',
    $q$UPDATE public.profiles SET water_tested_until = current_date + 999
       WHERE id = '00000000-0000-4000-8000-0000000000a1'$q$,
    'Unauthorized: You cannot alter protected account fields.');
  RESET ROLE;
END $$;

SELECT 'water_tested_badge_test: all passed' AS result;
