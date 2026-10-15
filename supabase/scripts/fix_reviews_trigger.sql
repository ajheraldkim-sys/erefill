-- ==============================================================================
-- Migration: Fix Review Stats Trigger & Sync Profile Rating/Counts
-- ==============================================================================
-- Root Cause:
-- The function `public.update_station_stats()` was previously defined without
-- `SECURITY DEFINER`. When normal customers (authenticated users) submit a
-- review, the trigger executes with customer permissions. Because Row Level
-- Security (RLS) on `public.profiles` only allows users to update their own profile
-- (auth.uid() = id), the trigger's UPDATE query on the station owner's profile
-- silently updated 0 rows.
--
-- Fix:
-- 1. Mark `public.update_station_stats()` as `SECURITY DEFINER` so it runs with
--    elevated privileges and bypasses RLS on `profiles`.
-- 2. Trigger on INSERT, UPDATE, and DELETE to keep stats accurate under all conditions.
-- 3. Synchronize existing reviews to `profiles.average_rating` and `profiles.review_count`.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.update_station_stats()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_station_id uuid;
BEGIN
  v_station_id := COALESCE(NEW.station_id, OLD.station_id);

  IF v_station_id IS NOT NULL THEN
    UPDATE public.profiles
    SET
      average_rating = (
        SELECT COALESCE(ROUND(AVG(rating)::numeric, 1), 0)
        FROM public.reviews
        WHERE station_id = v_station_id
      ),
      review_count = (
        SELECT COUNT(*)
        FROM public.reviews
        WHERE station_id = v_station_id
      )
    WHERE id = v_station_id;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

ALTER FUNCTION public.update_station_stats() OWNER TO postgres;
GRANT ALL ON FUNCTION public.update_station_stats() TO authenticated;
GRANT ALL ON FUNCTION public.update_station_stats() TO service_role;

-- Recreate trigger on reviews table
DROP TRIGGER IF EXISTS on_review_added ON public.reviews;
DROP TRIGGER IF EXISTS trg_update_station_stats ON public.reviews;

CREATE TRIGGER on_review_added
  AFTER INSERT OR UPDATE OR DELETE ON public.reviews
  FOR EACH ROW
  EXECUTE FUNCTION public.update_station_stats();

-- One-time sync for all stations with existing reviews
UPDATE public.profiles p
SET
  average_rating = COALESCE(sub.avg_rating, 0),
  review_count = COALESCE(sub.cnt, 0)
FROM (
  SELECT
    station_id,
    ROUND(AVG(rating)::numeric, 1) AS avg_rating,
    COUNT(*) AS cnt
  FROM public.reviews
  GROUP BY station_id
) sub
WHERE p.id = sub.station_id;

