-- Run: bash build.sh ../scripts/harden_signup_and_protected_columns.sql ../scripts/identity_verification.sql ../scripts/water_quality_certs.sql -- water_quality_certs_test.sql

-- owner_submits_and_admin_approves
DO $$ DECLARE v jsonb; BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
  v := public.submit_station_certification('bacteriological', current_date - 30, current_date + 150,
         '00000000-0000-4000-8000-0000000000a1/certs/lab.pdf');

  -- not public while pending
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1'); SET LOCAL ROLE authenticated;
  PERFORM pg_temp.assert_eq('hidden pending', (SELECT count(*) FROM public.station_certifications), 0::bigint);
  RESET ROLE;

  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000e1');
  PERFORM public.admin_review_station_certification((v->>'id')::uuid, true);

  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1'); SET LOCAL ROLE authenticated;
  PERFORM pg_temp.assert_eq('public approved', (SELECT count(*) FROM public.station_certifications), 1::bigint);
  RESET ROLE;
END $$;

-- path_must_be_own_certs_folder
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
  PERFORM pg_temp.expect_error('path',
    $q$SELECT public.submit_station_certification('sanitary_permit', current_date - 1, current_date + 100,
       '00000000-0000-4000-8000-0000000000a1/front.jpg')$q$, 'Upload the certificate file first');
END $$;

-- expired_cert_rejected_on_submit
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
  PERFORM pg_temp.expect_error('expired',
    $q$SELECT public.submit_station_certification('sanitary_permit', current_date - 400, current_date - 1,
       '00000000-0000-4000-8000-0000000000a1/certs/old.pdf')$q$, 'already expired');
END $$;

-- daily_job_expires_and_warns
DO $$ BEGIN
  UPDATE public.station_certifications SET expires_on = current_date + 10, issued_on = current_date - 300;
  PERFORM public.expire_station_certifications();
  PERFORM pg_temp.assert_eq('warned',
    (SELECT count(*) FROM public.system_notifications
     WHERE user_id = '00000000-0000-4000-8000-0000000000a1' AND title = 'Certificate expiring soon'), 1::bigint);
  UPDATE public.station_certifications SET expires_on = current_date;
  PERFORM public.expire_station_certifications();
  PERFORM pg_temp.assert_eq('expired',
    (SELECT status FROM public.station_certifications LIMIT 1), 'expired');
END $$;

SELECT 'water_quality_certs_test: all passed' AS result;
