-- ==============================================================================
-- "Water tested" ranking boost (2026-11-06)
-- ==============================================================================
-- profiles.water_tested_until = latest expiry of the station's approved,
-- unexpired lab tests (bacteriological / physical-chemical), else NULL.
-- Kept in sync by a trigger on station_certifications (submit, review,
-- daily expiry job), so the station list can rank tested stations slightly
-- higher without an extra query. Protected like average_rating: only
-- admins and SECURITY DEFINER code can change it.
--
-- Run after: harden_signup_and_protected_columns.sql, water_quality_certs.sql.
-- Run BEFORE shipping an app build that selects water_tested_until.
-- Test: supabase/tests/water_tested_badge_test.sql
-- ==============================================================================

BEGIN;

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS water_tested_until date;

CREATE OR REPLACE FUNCTION public.refresh_water_tested(p_owner_id uuid)
RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path TO 'public' AS $$
  UPDATE public.profiles p
  SET water_tested_until = (
    SELECT max(c.expires_on) FROM public.station_certifications c
    WHERE c.owner_id = p_owner_id AND c.status = 'approved'
      AND c.cert_type IN ('bacteriological', 'physical_chemical')
      AND c.expires_on > current_date)
  WHERE p.id = p_owner_id;
$$;
REVOKE ALL ON FUNCTION public.refresh_water_tested(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.trg_station_cert_refresh_water_tested()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF TG_OP <> 'INSERT' THEN
    PERFORM public.refresh_water_tested(OLD.owner_id);
  END IF;
  IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND NEW.owner_id IS DISTINCT FROM OLD.owner_id) THEN
    PERFORM public.refresh_water_tested(NEW.owner_id);
  END IF;
  RETURN NULL;
END; $$;

DROP TRIGGER IF EXISTS trg_station_cert_water_tested ON public.station_certifications;
CREATE TRIGGER trg_station_cert_water_tested
  AFTER INSERT OR UPDATE OR DELETE ON public.station_certifications
  FOR EACH ROW EXECUTE FUNCTION public.trg_station_cert_refresh_water_tested();

-- Same guard as harden_signup_and_protected_columns.sql, plus water_tested_until.
CREATE OR REPLACE FUNCTION public.guard_profile_protected_columns()
RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;

  IF NEW.average_rating IS NOT DISTINCT FROM OLD.average_rating
    AND NEW.review_count IS NOT DISTINCT FROM OLD.review_count
    AND NEW.reliability_score IS NOT DISTINCT FROM OLD.reliability_score
    AND NEW.flagged_count IS NOT DISTINCT FROM OLD.flagged_count
    AND NEW.verification_status IS NOT DISTINCT FROM OLD.verification_status
    AND NEW.water_tested_until IS NOT DISTINCT FROM OLD.water_tested_until
  THEN
    RETURN NEW;
  END IF;

  IF public.is_admin() THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'Unauthorized: You cannot alter protected account fields.';
END;
$$;

-- Backfill.
SELECT public.refresh_water_tested(id) FROM public.profiles WHERE role = 'owner';

COMMIT;

NOTIFY pgrst, 'reload schema';
