-- ==============================================================================
-- After apply_panel_features.sql (2026-11-06)
-- ==============================================================================
-- Safe to run more than once. Paste the whole file into the SQL Editor.
-- ==============================================================================

-- PART 1 (for the demo): approve every existing station so they keep taking
-- orders. New stations registered from now on still need ID review.
-- Delete this statement if you want to review each station's ID in the admin
-- app instead.
UPDATE public.profiles
SET verification_status = 'approved'
WHERE role = 'owner' AND verification_status <> 'approved';

-- PART 2: scheduled jobs (enables pg_cron if it isn't on yet).
CREATE EXTENSION IF NOT EXISTS pg_cron;

DO $$
DECLARE
  j record;
BEGIN
  FOR j IN SELECT * FROM (VALUES
    ('purge_old_rider_locations',     '7 * * * *',   'SELECT public.purge_old_rider_locations()'),
    -- 01:00 UTC = 09:00 Asia/Manila
    ('send_refill_reminders',         '0 1 * * *',   'SELECT public.send_refill_reminders()'),
    -- 16:15 UTC = 00:15 Asia/Manila
    ('expire_station_certifications', '15 16 * * *', 'SELECT public.expire_station_certifications()')
  ) AS t(name, schedule, command)
  LOOP
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = j.name;
    PERFORM cron.schedule(j.name, j.schedule, j.command);
  END LOOP;
END $$;

-- Check: expect 3 active jobs and 10 approved stations.
SELECT jobname, schedule, active FROM cron.job ORDER BY jobname;
