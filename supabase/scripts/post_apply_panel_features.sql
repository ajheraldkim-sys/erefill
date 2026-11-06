-- ==============================================================================
-- After apply_panel_features.sql (2026-11-06)
-- ==============================================================================
-- Run each part you need in the Supabase SQL Editor.
-- ==============================================================================

-- PART 1 (optional, for the demo): approve every existing station so they keep
-- taking orders. New stations registered from now on still need ID review.
-- Skip this if you want to review each station's ID in the admin app instead.
UPDATE public.profiles
SET verification_status = 'approved'
WHERE role = 'owner' AND verification_status <> 'approved';


-- PART 2: scheduled jobs. First enable the extension:
--   Dashboard -> Database -> Extensions -> search "pg_cron" -> Enable.
-- Then run:
SELECT cron.schedule('purge_old_rider_locations', '7 * * * *',
                     'SELECT public.purge_old_rider_locations()');
-- 01:00 UTC = 09:00 Asia/Manila
SELECT cron.schedule('send_refill_reminders', '0 1 * * *',
                     'SELECT public.send_refill_reminders()');
-- 16:15 UTC = 00:15 Asia/Manila
SELECT cron.schedule('expire_station_certifications', '15 16 * * *',
                     'SELECT public.expire_station_certifications()');

-- Check:
SELECT jobname, schedule, active FROM cron.job ORDER BY jobname;
