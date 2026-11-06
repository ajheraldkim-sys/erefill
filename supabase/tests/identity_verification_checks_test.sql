-- Run: bash build.sh ../scripts/harden_signup_and_protected_columns.sql ../scripts/identity_verification.sql ../scripts/identity_verification_checks.sql -- identity_verification_checks_test.sql

-- checks_are_saved_and_tagged
DO $$ DECLARE v jsonb; BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  v := public.submit_identity_verification('philsys', '1234',
       '00000000-0000-4000-8000-0000000000c1/front.jpg', NULL,
       '00000000-0000-4000-8000-0000000000c1/selfie.jpg', NULL,
       '{"version": 1, "name_match": 1.0, "liveness": {"passed": true}}'::jsonb);
  PERFORM pg_temp.assert_eq('saved',
    (SELECT (auto_checks->>'name_match')::numeric FROM public.identity_verifications WHERE id = (v->>'id')::uuid), 1.0::numeric);
  PERFORM pg_temp.assert_eq('tagged as device-reported',
    (SELECT (auto_checks->>'device_reported')::boolean FROM public.identity_verifications WHERE id = (v->>'id')::uuid), true);
  PERFORM pg_temp.assert_eq('still pending, never auto-approved',
    (SELECT verification_status FROM public.profiles WHERE id = '00000000-0000-4000-8000-0000000000c1'), 'pending');
END $$;

-- old_app_builds_still_submit_without_checks
DO $$ DECLARE v jsonb; BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
  v := public.submit_identity_verification('umid', '9876',
       '00000000-0000-4000-8000-0000000000a1/front.jpg', NULL,
       '00000000-0000-4000-8000-0000000000a1/selfie.jpg', '00000000-0000-4000-8000-0000000000a1/permit.pdf');
  PERFORM pg_temp.assert_eq('no checks',
    (SELECT auto_checks FROM public.identity_verifications WHERE id = (v->>'id')::uuid), NULL::jsonb);
END $$;

-- oversized_or_non_object_checks_are_dropped
DO $$ DECLARE v jsonb; BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a2');
  v := public.submit_identity_verification('umid', '5555',
       '00000000-0000-4000-8000-0000000000a2/front.jpg', NULL,
       '00000000-0000-4000-8000-0000000000a2/selfie.jpg', '00000000-0000-4000-8000-0000000000a2/permit.pdf',
       jsonb_build_object('junk', repeat('x', 9000)));
  PERFORM pg_temp.assert_eq('dropped',
    (SELECT auto_checks FROM public.identity_verifications WHERE id = (v->>'id')::uuid), NULL::jsonb);
END $$;

SELECT 'identity_verification_checks_test: all passed' AS result;
