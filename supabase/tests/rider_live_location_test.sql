-- Run: bash build.sh ../scripts/rider_live_location.sql -- rider_live_location_test.sql
INSERT INTO public.rider_locations (rider_id, latitude, longitude)
VALUES ('00000000-0000-4000-8000-0000000000d1', 14.6, 121.0);

-- stranger_cannot_see_rider
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a2'); SET LOCAL ROLE authenticated;
  PERFORM pg_temp.assert_eq('hidden', (SELECT count(*) FROM public.rider_locations), 0::bigint);
  RESET ROLE;
END $$;

-- customer_sees_rider_only_during_delivery
DO $$ BEGIN
  SET LOCAL session_replication_role = replica;
  INSERT INTO public.orders (id, customer_id, owner_id, assigned_rider_id, status, total_amount)
  VALUES ('00000000-0000-4000-8000-00000000f101', '00000000-0000-4000-8000-0000000000c1',
          '00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000d1', 'out_for_delivery', 50);
  SET LOCAL session_replication_role = origin;
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1'); SET LOCAL ROLE authenticated;
  PERFORM pg_temp.assert_eq('visible', (SELECT count(*) FROM public.rider_locations), 1::bigint);
  RESET ROLE;
  SET LOCAL session_replication_role = replica;
  UPDATE public.orders SET status = 'delivered' WHERE id = '00000000-0000-4000-8000-00000000f101';
  SET LOCAL session_replication_role = origin;
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1'); SET LOCAL ROLE authenticated;
  PERFORM pg_temp.assert_eq('hidden after delivery', (SELECT count(*) FROM public.rider_locations), 0::bigint);
  RESET ROLE;
END $$;

-- rider_cannot_post_for_someone_else
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000d1'); SET LOCAL ROLE authenticated;
  PERFORM pg_temp.expect_error('spoof',
    $q$INSERT INTO public.rider_locations (rider_id, latitude, longitude)
       VALUES ('00000000-0000-4000-8000-0000000000a1', 1, 1)$q$, 'row-level security');
  RESET ROLE;
END $$;

SELECT 'rider_live_location_test: all passed' AS result;
