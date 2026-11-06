-- Run: BEGIN; harden_signup_and_protected_columns.sql; _fixtures.sql; this file; ROLLBACK;

-- self_signup_cannot_claim_admin_or_rider
DO $$ BEGIN
  PERFORM pg_temp.assert_eq('self admin -> customer',
    public.resolve_signup_role('admin', false)::text, 'customer');
  PERFORM pg_temp.assert_eq('self rider -> customer',
    public.resolve_signup_role('rider', false)::text, 'customer');
  PERFORM pg_temp.assert_eq('self owner ok',
    public.resolve_signup_role('owner', false)::text, 'owner');
  PERFORM pg_temp.assert_eq('self junk -> customer',
    public.resolve_signup_role('superuser', false)::text, 'customer');
  PERFORM pg_temp.assert_eq('trusted rider ok',
    public.resolve_signup_role('rider', true)::text, 'rider');
  PERFORM pg_temp.assert_eq('trusted admin ok',
    public.resolve_signup_role('admin', true)::text, 'admin');
END $$;

-- owner_cannot_edit_own_rating
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1'); SET LOCAL ROLE authenticated;
  PERFORM pg_temp.expect_error('owner rating',
    $q$UPDATE public.profiles SET average_rating = 5, review_count = 99
       WHERE id = '00000000-0000-4000-8000-0000000000a1'$q$,
    'Unauthorized: You cannot alter protected account fields.');
END $$;

-- owner_cannot_self_verify
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1'); SET LOCAL ROLE authenticated;
  PERFORM pg_temp.expect_error('owner verify',
    $q$UPDATE public.profiles SET verification_status = 'approved'
       WHERE id = '00000000-0000-4000-8000-0000000000a1'$q$,
    'Unauthorized: You cannot alter protected account fields.');
END $$;

-- owner_can_still_edit_normal_fields
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1'); SET LOCAL ROLE authenticated;
  UPDATE public.profiles SET station_name = 'Renamed'
  WHERE id = '00000000-0000-4000-8000-0000000000a1';
  RESET ROLE;
  PERFORM pg_temp.assert_eq('rename',
    (SELECT station_name FROM public.profiles WHERE id = '00000000-0000-4000-8000-0000000000a1'), 'Renamed');
END $$;

-- review_trigger_still_updates_stats
DO $$ BEGIN
  RESET ROLE;
  SET LOCAL session_replication_role = replica;
  INSERT INTO public.orders (id, customer_id, owner_id, status, total_amount)
  VALUES ('00000000-0000-4000-8000-00000000f001', '00000000-0000-4000-8000-0000000000c1',
          '00000000-0000-4000-8000-0000000000a1', 'delivered', 50);
  SET LOCAL session_replication_role = origin;
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1'); SET LOCAL ROLE authenticated;
  INSERT INTO public.reviews (station_id, customer_id, order_id, rating)
  VALUES ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000c1',
          '00000000-0000-4000-8000-00000000f001', 4);
  RESET ROLE;
  PERFORM pg_temp.assert_eq('stats count',
    (SELECT review_count::bigint FROM public.profiles WHERE id = '00000000-0000-4000-8000-0000000000a1'), 1::bigint);
END $$;

-- admin_can_set_verification
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000e1'); SET LOCAL ROLE authenticated;
  UPDATE public.profiles SET verification_status = 'approved'
  WHERE id = '00000000-0000-4000-8000-0000000000a1';
  RESET ROLE;
  PERFORM pg_temp.assert_eq('admin verify',
    (SELECT verification_status FROM public.profiles WHERE id = '00000000-0000-4000-8000-0000000000a1'), 'approved');
END $$;

SELECT 'protected_columns_test: all passed' AS result;
