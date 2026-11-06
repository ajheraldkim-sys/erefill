-- Run: bash build.sh ../scripts/refill_reminders.sql -- refill_reminders_test.sql
-- Customer c1 ordered every 5 days; last delivered order 6 days ago -> due.
SET LOCAL session_replication_role = replica;
INSERT INTO public.orders (customer_id, owner_id, status, total_amount, station_name, created_at) VALUES
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000a1', 'delivered', 50, 'T Station', now() - interval '21 days'),
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000a1', 'delivered', 50, 'T Station', now() - interval '16 days'),
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000a1', 'delivered', 50, 'T Station', now() - interval '11 days'),
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000a1', 'delivered', 50, 'T Station', now() - interval '6 days');
SET LOCAL session_replication_role = origin;

-- rhythm_is_median_gap
DO $$ DECLARE r jsonb; BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  r := public.customer_refill_rhythm();
  PERFORM pg_temp.assert_eq('has rhythm', (r->>'has_rhythm')::boolean, true);
  PERFORM pg_temp.assert_eq('median 5', (r->>'median_days')::numeric, 5.0::numeric);
  PERFORM pg_temp.assert_eq('due', (r->>'is_due')::boolean, true);
END $$;

-- one_reminder_then_quiet_for_3_days
DO $$ BEGIN
  PERFORM public.send_refill_reminders();
  PERFORM public.send_refill_reminders();
  PERFORM pg_temp.assert_eq('one reminder',
    (SELECT count(*) FROM public.system_notifications
     WHERE user_id = '00000000-0000-4000-8000-0000000000c1'
       AND metadata->>'kind' = 'refill_reminder'),
    1::bigint);
END $$;

-- opt_out_respected
DO $$ BEGIN
  DELETE FROM public.system_notifications WHERE metadata->>'kind' = 'refill_reminder';
  UPDATE public.profiles SET refill_reminders_enabled = false
  WHERE id = '00000000-0000-4000-8000-0000000000c1';
  PERFORM public.send_refill_reminders();
  PERFORM pg_temp.assert_eq('none when off',
    (SELECT count(*) FROM public.system_notifications
     WHERE metadata->>'kind' = 'refill_reminder'),
    0::bigint);
END $$;

-- too_few_orders_no_rhythm
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a2');
  PERFORM pg_temp.assert_eq('no rhythm',
    (public.customer_refill_rhythm()->>'has_rhythm')::boolean, false);
END $$;

SELECT 'refill_reminders_test: all passed' AS result;
