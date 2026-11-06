-- water_tested_badge: rolled-back test. Paste into the SQL Editor; ends with 'all passed'.
BEGIN;
-- ==============================================================================
-- Harden signup roles and protect trust columns on profiles (2026-11-05)
-- ==============================================================================
-- 1. Self-signup could claim role 'admin' or 'rider' through user metadata.
--    Only accounts created by a trusted server function (admin_create_user,
--    create_rider_account, admin_create_station) may get privileged roles.
--    Self-signups arrive through the Auth server, whose session user is
--    supabase_auth_admin; those are limited to customer/owner.
-- 2. Users could UPDATE their own average_rating / review_count /
--    reliability_score / flagged_count. Those are now writable only by admins
--    or by SECURITY DEFINER functions (e.g. update_station_stats()).
-- 3. Adds profiles.verification_status (used by identity verification), which is
--    protected the same way.
--
-- Run after: single_water_product_catalog.sql. Test: supabase/tests/protected_columns_test.sql
-- ==============================================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS verification_status text NOT NULL DEFAULT 'unverified';
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_verification_status_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_verification_status_check
  CHECK (verification_status IN ('unverified', 'pending', 'approved', 'rejected'));

-- 1. Role resolution -----------------------------------------------------------
CREATE OR REPLACE FUNCTION public.resolve_signup_role(p_requested text, p_trusted boolean)
RETURNS public.user_role
LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN p_requested IN ('customer', 'owner') THEN p_requested::public.user_role
    WHEN p_trusted AND p_requested IN ('rider', 'admin') THEN p_requested::public.user_role
    ELSE 'customer'::public.user_role
  END;
$$;
REVOKE ALL ON FUNCTION public.resolve_signup_role(text, boolean) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_role public.user_role;
  v_town public.municipality;
  v_complete_address text;
  v_full_name text;
  v_first_name text;
  v_last_name text;
  v_username text;
  v_avatar_url text;
  v_water_type text;
BEGIN
  -- 1. Role: self-signups (Auth server session) may only be customer or owner.
  v_role := public.resolve_signup_role(
    new.raw_user_meta_data->>'role',
    session_user <> 'supabase_auth_admin'
  );

  -- 2. Safe municipality enum resolution
  IF lower(trim(COALESCE(new.raw_user_meta_data->>'town', ''))) = 'cantilan' THEN
    v_town := 'Cantilan'::public.municipality;
  ELSIF lower(trim(COALESCE(new.raw_user_meta_data->>'town', ''))) = 'madrid' THEN
    v_town := 'Madrid'::public.municipality;
  ELSE
    v_town := NULL;
  END IF;

  v_complete_address := NULLIF(TRIM(COALESCE(new.raw_user_meta_data->>'complete_address', '')), '');

  -- 3. Names (Google OAuth sends 'name', 'given_name', 'family_name', 'picture')
  v_first_name := COALESCE(
    NULLIF(TRIM(new.raw_user_meta_data->>'first_name'), ''),
    NULLIF(TRIM(new.raw_user_meta_data->>'given_name'), '')
  );
  v_last_name := COALESCE(
    NULLIF(TRIM(new.raw_user_meta_data->>'last_name'), ''),
    NULLIF(TRIM(new.raw_user_meta_data->>'family_name'), '')
  );
  v_full_name := COALESCE(
    NULLIF(TRIM(new.raw_user_meta_data->>'full_name'), ''),
    NULLIF(TRIM(new.raw_user_meta_data->>'name'), ''),
    NULLIF(TRIM(COALESCE(v_first_name, '') || ' ' || COALESCE(v_last_name, '')), ''),
    'New User'
  );
  v_username := COALESCE(
    NULLIF(TRIM(new.raw_user_meta_data->>'username'), ''),
    NULLIF(TRIM(split_part(COALESCE(new.email, ''), '@', 1)), ''),
    'user_' || substr(new.id::text, 1, 8)
  );
  v_avatar_url := COALESCE(
    NULLIF(TRIM(new.raw_user_meta_data->>'avatar_url'), ''),
    NULLIF(TRIM(new.raw_user_meta_data->>'picture'), '')
  );

  -- 4. Station water type: the registration choice, if it is an active catalog entry
  IF v_role = 'owner' THEN
    SELECT name INTO v_water_type FROM public.water_types
    WHERE name = NULLIF(TRIM(new.raw_user_meta_data->>'primary_water_type'), '')
      AND is_active;
    IF v_water_type IS NULL THEN
      SELECT name INTO v_water_type FROM public.water_types
      WHERE is_active ORDER BY sort_order, name LIMIT 1;
    END IF;
  END IF;

  -- 5. Upsert profile
  INSERT INTO public.profiles (
    id, email, username, full_name, first_name, last_name, mi, suffix, role,
    phone, town, barangay, complete_address, landmark, station_name,
    avatar_url, latitude, longitude, primary_water_type
  )
  VALUES (
    new.id, new.email, v_username, v_full_name, v_first_name, v_last_name,
    new.raw_user_meta_data->>'mi', new.raw_user_meta_data->>'suffix', v_role,
    new.raw_user_meta_data->>'phone', v_town, new.raw_user_meta_data->>'barangay',
    v_complete_address, new.raw_user_meta_data->>'landmark',
    new.raw_user_meta_data->>'station_name', v_avatar_url,
    (new.raw_user_meta_data->>'latitude')::DOUBLE PRECISION,
    (new.raw_user_meta_data->>'longitude')::DOUBLE PRECISION,
    v_water_type
  )
  ON CONFLICT (id) DO UPDATE
    SET email = EXCLUDED.email,
        username = COALESCE(profiles.username, EXCLUDED.username),
        full_name = COALESCE(NULLIF(profiles.full_name, 'New User'), EXCLUDED.full_name),
        first_name = COALESCE(profiles.first_name, EXCLUDED.first_name),
        last_name = COALESCE(profiles.last_name, EXCLUDED.last_name),
        avatar_url = COALESCE(profiles.avatar_url, EXCLUDED.avatar_url),
        phone = COALESCE(EXCLUDED.phone, profiles.phone),
        town = COALESCE(EXCLUDED.town, profiles.town),
        barangay = COALESCE(EXCLUDED.barangay, profiles.barangay),
        complete_address = COALESCE(EXCLUDED.complete_address, profiles.complete_address),
        landmark = COALESCE(EXCLUDED.landmark, profiles.landmark),
        station_name = COALESCE(EXCLUDED.station_name, profiles.station_name),
        latitude = COALESCE(EXCLUDED.latitude, profiles.latitude),
        longitude = COALESCE(EXCLUDED.longitude, profiles.longitude),
        primary_water_type = COALESCE(profiles.primary_water_type, EXCLUDED.primary_water_type);

  RETURN new;
END;
$$;

-- 2. Protected trust columns -----------------------------------------------------
-- SECURITY INVOKER on purpose: current_user is 'authenticated'/'anon' for direct
-- client writes, and the function owner (postgres) inside SECURITY DEFINER
-- functions such as update_station_stats() and the admin RPCs.
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
  THEN
    RETURN NEW;
  END IF;

  IF public.is_admin() THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'Unauthorized: You cannot alter protected account fields.';
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_profile_protected_columns ON public.profiles;
CREATE TRIGGER trg_guard_profile_protected_columns
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.guard_profile_protected_columns();


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Seller and customer ID verification (2026-11-05)
-- ==============================================================================
-- Users upload a government ID (front, back, selfie; owners also a business
-- permit) to the private bucket verification_docs under <their uid>/.
-- An admin reviews and approves or rejects. profiles.verification_status
-- (added and write-protected by harden_signup_and_protected_columns.sql) is
-- only changed by the RPCs below.
--
-- Gates (enforced in create_order_atomic, order_pricing_v3.sql):
--   * stations must be 'approved' to receive orders
--   * unverified customers: cash-on-delivery up to PHP 1,000 and at most
--     2 active COD orders; verified customers have no limit
-- Backfill: owners who already completed a delivery are approved (legacy).
--
-- Run after: harden_signup_and_protected_columns.sql
-- Run before: order_pricing_v3.sql. Test: supabase/tests/identity_verification_test.sql
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.identity_verifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role text NOT NULL,
  id_type text NOT NULL CHECK (id_type IN (
    'philsys', 'drivers_license', 'umid', 'passport', 'postal', 'voters', 'prc', 'other')),
  id_number_last4 text CHECK (id_number_last4 ~ '^[0-9A-Za-z]{4}$'),
  front_path text NOT NULL,
  back_path text,
  selfie_path text NOT NULL,
  business_permit_path text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  reviewer_id uuid REFERENCES public.profiles(id),
  reviewed_at timestamptz,
  rejection_reason text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_identity_verifications_user ON public.identity_verifications (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_identity_verifications_pending ON public.identity_verifications (created_at) WHERE status = 'pending';

ALTER TABLE public.identity_verifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users read own verifications" ON public.identity_verifications;
CREATE POLICY "Users read own verifications" ON public.identity_verifications
  FOR SELECT TO authenticated USING (auth.uid() = user_id OR public.is_admin());
-- Writes only through the RPCs below.
REVOKE INSERT, UPDATE, DELETE ON public.identity_verifications FROM anon, authenticated;
GRANT SELECT ON public.identity_verifications TO authenticated;

-- Private bucket, one folder per user.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('verification_docs', 'verification_docs', false, 8388608,
        ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
ON CONFLICT (id) DO UPDATE SET public = false;

DROP POLICY IF EXISTS "Verification docs: owner upload" ON storage.objects;
CREATE POLICY "Verification docs: owner upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'verification_docs' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "Verification docs: owner or admin read" ON storage.objects;
CREATE POLICY "Verification docs: owner or admin read" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'verification_docs'
         AND ((storage.foldername(name))[1] = auth.uid()::text OR public.is_admin()));

CREATE OR REPLACE FUNCTION public.submit_identity_verification(
  p_id_type text,
  p_id_number_last4 text,
  p_front_path text,
  p_back_path text,
  p_selfie_path text,
  p_business_permit_path text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_role text;
  v_status text;
  v_prefix text;
  v_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required.'; END IF;
  SELECT role::text, verification_status INTO v_role, v_status FROM public.profiles WHERE id = v_uid;
  IF v_role NOT IN ('customer', 'owner') THEN
    RAISE EXCEPTION 'Only customers and station owners verify their ID here.';
  END IF;
  IF v_status = 'approved' THEN RAISE EXCEPTION 'Your ID is already verified.'; END IF;
  IF v_status = 'pending' THEN RAISE EXCEPTION 'Your ID is already being reviewed.'; END IF;

  v_prefix := v_uid::text || '/';
  IF p_front_path IS NULL OR p_selfie_path IS NULL
     OR left(p_front_path, length(v_prefix)) <> v_prefix
     OR left(p_selfie_path, length(v_prefix)) <> v_prefix
     OR (p_back_path IS NOT NULL AND left(p_back_path, length(v_prefix)) <> v_prefix)
     OR (p_business_permit_path IS NOT NULL AND left(p_business_permit_path, length(v_prefix)) <> v_prefix) THEN
    RAISE EXCEPTION 'Upload your ID photos before submitting.';
  END IF;
  IF v_role = 'owner' AND p_business_permit_path IS NULL THEN
    RAISE EXCEPTION 'Stations must also upload a business or sanitary permit.';
  END IF;

  INSERT INTO public.identity_verifications (
    user_id, role, id_type, id_number_last4, front_path, back_path, selfie_path, business_permit_path)
  VALUES (v_uid, v_role, p_id_type, NULLIF(p_id_number_last4, ''), p_front_path, p_back_path,
          p_selfie_path, p_business_permit_path)
  RETURNING id INTO v_id;

  UPDATE public.profiles SET verification_status = 'pending' WHERE id = v_uid;
  RETURN jsonb_build_object('id', v_id, 'status', 'pending');
END; $$;

CREATE OR REPLACE FUNCTION public.admin_review_identity_verification(
  p_verification_id uuid,
  p_approve boolean,
  p_reason text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_row public.identity_verifications%ROWTYPE;
  v_status text := CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  IF NOT p_approve AND coalesce(trim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'Give the user a reason for the rejection.';
  END IF;

  UPDATE public.identity_verifications
  SET status = v_status, reviewer_id = auth.uid(), reviewed_at = now(),
      rejection_reason = CASE WHEN p_approve THEN NULL ELSE trim(p_reason) END
  WHERE id = p_verification_id AND status = 'pending'
  RETURNING * INTO v_row;
  IF NOT FOUND THEN RAISE EXCEPTION 'This verification was already reviewed.'; END IF;

  UPDATE public.profiles SET verification_status = v_status WHERE id = v_row.user_id;

  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (
    v_row.user_id, 'system_alert', 'high',
    CASE WHEN p_approve THEN 'Your ID is verified' ELSE 'ID verification needs another try' END,
    CASE WHEN p_approve
      THEN CASE WHEN v_row.role = 'owner'
        THEN 'Your station is verified and can now receive orders.'
        ELSE 'Your account is verified. Order limits are lifted.' END
      ELSE 'Reason: ' || trim(p_reason) || '. You can submit new photos.' END,
    jsonb_build_object('verification_id', v_row.id, 'status', v_status)
  );

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, new_value, metadata)
  VALUES (auth.uid(), 'identity_verification_' || v_status, 'identity_verifications', v_row.id::text,
          jsonb_build_object('status', v_status),
          jsonb_build_object('user_id', v_row.user_id, 'reason', p_reason));

  RETURN jsonb_build_object('id', v_row.id, 'status', v_status);
END; $$;

REVOKE ALL ON FUNCTION public.submit_identity_verification(text, text, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_identity_verification(text, text, text, text, text, text) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_review_identity_verification(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_review_identity_verification(uuid, boolean, text) TO authenticated;

-- Order gate helper, used by create_order_atomic.
CREATE OR REPLACE FUNCTION public.assert_order_allowed_by_verification(
  p_customer_id uuid, p_owner_id uuid, p_payment_method text, p_total numeric
) RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_owner_status text;
  v_customer_status text;
  v_active int;
BEGIN
  SELECT verification_status INTO v_owner_status FROM public.profiles WHERE id = p_owner_id;
  IF coalesce(v_owner_status, 'unverified') <> 'approved' THEN
    RAISE EXCEPTION 'This station is not verified yet and cannot take orders.';
  END IF;

  SELECT verification_status INTO v_customer_status FROM public.profiles WHERE id = p_customer_id;
  IF coalesce(v_customer_status, 'unverified') = 'approved'
     OR lower(coalesce(p_payment_method, 'cod')) NOT IN ('cod', 'cash') THEN
    RETURN;
  END IF;

  IF p_total > 1000 THEN
    RAISE EXCEPTION 'Verify your ID to place cash-on-delivery orders above PHP 1,000.';
  END IF;
  SELECT count(*) INTO v_active FROM public.orders
  WHERE customer_id = p_customer_id
    AND lower(coalesce(payment_method, 'cod')) IN ('cod', 'cash')
    AND status NOT IN ('delivered', 'cancelled', 'failed');
  IF v_active >= 2 THEN
    RAISE EXCEPTION 'Verify your ID to have more than 2 cash-on-delivery orders at a time.';
  END IF;
END; $$;
REVOKE ALL ON FUNCTION public.assert_order_allowed_by_verification(uuid, uuid, text, numeric) FROM PUBLIC, anon, authenticated;

-- Backfill: stations that already delivered orders keep working.
UPDATE public.profiles p SET verification_status = 'approved'
WHERE p.role = 'owner' AND p.verification_status = 'unverified'
  AND EXISTS (SELECT 1 FROM public.orders o WHERE o.owner_id = p.id AND o.status = 'delivered');


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Water quality transparency (2026-11-05)
-- ==============================================================================
-- Stations upload lab test results and permits (bacteriological /
-- physical-chemical water analysis, sanitary permit, business permit) with
-- issue and expiry dates. Admins approve them; approved, unexpired lab tests
-- give the station a "Water tested" badge and a small ranking boost.
-- Files live in the private verification_docs bucket under <uid>/certs/.
-- Approved certificate files are viewable by any signed-in user.
-- Daily job: marks expired certificates and warns owners 14 days ahead.
--
-- Run after: identity_verification.sql (bucket). Test: supabase/tests/water_quality_certs_test.sql
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.station_certifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  cert_type text NOT NULL CHECK (cert_type IN (
    'bacteriological', 'physical_chemical', 'sanitary_permit', 'business_permit')),
  issued_on date NOT NULL,
  expires_on date NOT NULL,
  file_path text NOT NULL,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected', 'expired')),
  reviewer_id uuid REFERENCES public.profiles(id),
  reviewed_at timestamptz,
  rejection_reason text,
  expiry_warned_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (expires_on > issued_on)
);
CREATE INDEX IF NOT EXISTS idx_station_certs_owner ON public.station_certifications (owner_id, status);

ALTER TABLE public.station_certifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Approved certs are public, owners see their own" ON public.station_certifications;
CREATE POLICY "Approved certs are public, owners see their own" ON public.station_certifications
  FOR SELECT TO authenticated
  USING (status = 'approved' OR owner_id = auth.uid() OR public.is_admin());
REVOKE INSERT, UPDATE, DELETE ON public.station_certifications FROM anon, authenticated;
GRANT SELECT ON public.station_certifications TO authenticated;

-- Approved certificate files are readable by signed-in users.
DROP POLICY IF EXISTS "Verification docs: approved certs readable" ON storage.objects;
CREATE POLICY "Verification docs: approved certs readable" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'verification_docs' AND EXISTS (
    SELECT 1 FROM public.station_certifications c
    WHERE c.file_path = storage.objects.name AND c.status = 'approved'));

CREATE OR REPLACE FUNCTION public.submit_station_certification(
  p_cert_type text, p_issued_on date, p_expires_on date, p_file_path text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_uid AND role = 'owner') THEN
    RAISE EXCEPTION 'Only station owners upload certificates.';
  END IF;
  IF p_file_path IS NULL OR left(p_file_path, length(v_uid::text) + 7) <> v_uid::text || '/certs/' THEN
    RAISE EXCEPTION 'Upload the certificate file first.';
  END IF;
  IF p_expires_on <= current_date THEN
    RAISE EXCEPTION 'This certificate has already expired.';
  END IF;
  IF p_issued_on > current_date THEN
    RAISE EXCEPTION 'The issue date cannot be in the future.';
  END IF;
  INSERT INTO public.station_certifications (owner_id, cert_type, issued_on, expires_on, file_path)
  VALUES (v_uid, p_cert_type, p_issued_on, p_expires_on, p_file_path)
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('id', v_id, 'status', 'pending');
END; $$;

CREATE OR REPLACE FUNCTION public.admin_review_station_certification(
  p_cert_id uuid, p_approve boolean, p_reason text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_row public.station_certifications%ROWTYPE;
  v_status text := CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  IF NOT p_approve AND coalesce(trim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'Give the station a reason for the rejection.';
  END IF;
  UPDATE public.station_certifications
  SET status = v_status, reviewer_id = auth.uid(), reviewed_at = now(),
      rejection_reason = CASE WHEN p_approve THEN NULL ELSE trim(p_reason) END
  WHERE id = p_cert_id AND status = 'pending'
  RETURNING * INTO v_row;
  IF NOT FOUND THEN RAISE EXCEPTION 'This certificate was already reviewed.'; END IF;

  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (v_row.owner_id, 'system_alert', 'normal',
    CASE WHEN p_approve THEN 'Certificate approved' ELSE 'Certificate rejected' END,
    CASE WHEN p_approve THEN 'Customers can now see your certificate.'
         ELSE 'Reason: ' || trim(p_reason) END,
    jsonb_build_object('certificate_id', v_row.id, 'status', v_status));
  RETURN jsonb_build_object('id', v_row.id, 'status', v_status);
END; $$;

REVOKE ALL ON FUNCTION public.submit_station_certification(text, date, date, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_station_certification(text, date, date, text) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_review_station_certification(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_review_station_certification(uuid, boolean, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.expire_station_certifications()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_n integer;
BEGIN
  UPDATE public.station_certifications SET status = 'expired'
  WHERE status = 'approved' AND expires_on <= current_date;
  GET DIAGNOSTICS v_n = ROW_COUNT;

  WITH soon AS (
    UPDATE public.station_certifications SET expiry_warned_at = now()
    WHERE status = 'approved' AND expiry_warned_at IS NULL
      AND expires_on <= current_date + 14
    RETURNING owner_id, id, cert_type, expires_on
  )
  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  SELECT owner_id, 'system_alert', 'high', 'Certificate expiring soon',
         'Your ' || replace(cert_type, '_', ' ') || ' certificate expires on '
           || to_char(expires_on, 'Mon DD, YYYY') || '. Upload a new one to keep your badge.',
         jsonb_build_object('certificate_id', id)
  FROM soon;
  RETURN v_n;
END; $$;
REVOKE ALL ON FUNCTION public.expire_station_certifications() FROM PUBLIC, anon, authenticated;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'expire_station_certifications';
    PERFORM cron.schedule('expire_station_certifications', '15 16 * * *', 'SELECT public.expire_station_certifications()');
  END IF;
END $$;


NOTIFY pgrst, 'reload schema';
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


NOTIFY pgrst, 'reload schema';
-- Shared fixtures for the SQL tests in this folder. Every test runs as
--   BEGIN; <scripts under test, BEGIN/COMMIT stripped>; _fixtures.sql; <test>; ROLLBACK;
-- through the Supabase MCP execute_sql tool, so nothing persists.
--
-- Fixture rows are inserted with triggers off (replica role) to skip station
-- setup checks; triggers are back on before the test body runs.
--
-- ids: owner ...a1, second owner ...a2, customer ...c1, rider ...d1,
--      admin ...e1, product ...b1 (₱19.60, owner a1).

SET LOCAL session_replication_role = replica;

INSERT INTO auth.users (id, instance_id, aud, role, email, raw_user_meta_data, raw_app_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_owner@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000a2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_owner2@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_cust@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_rider@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_admin@example.test', '{}', '{}', now(), now());

INSERT INTO public.profiles (id, role, full_name, station_name, station_availability, latitude, longitude)
VALUES
  ('00000000-0000-4000-8000-0000000000a1', 'owner', 'T Owner', 'T Station', 'open', 14.60, 121.00),
  ('00000000-0000-4000-8000-0000000000a2', 'owner', 'T Owner 2', 'T Station 2', 'open', 14.61, 121.01),
  ('00000000-0000-4000-8000-0000000000c1', 'customer', 'T Cust', NULL, 'open', 14.62, 121.02),
  ('00000000-0000-4000-8000-0000000000d1', 'rider', 'T Rider', NULL, 'open', NULL, NULL),
  ('00000000-0000-4000-8000-0000000000e1', 'admin', 'T Admin', NULL, 'open', NULL, NULL);

INSERT INTO public.owner_settings (owner_id, base_delivery_fee)
VALUES
  ('00000000-0000-4000-8000-0000000000a1', 5.4),
  ('00000000-0000-4000-8000-0000000000a2', 0);

INSERT INTO public.products (id, owner_id, name, price, is_available)
VALUES ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000a1', 'T Water', 19.6, true);

-- Fee config used by every test unless a test overrides it.
UPDATE public.system_config SET value = '{"enabled": true, "percent": 1, "fixed": 0}'::jsonb
WHERE key = 'platform_fee';

SET LOCAL session_replication_role = origin;

-- Helpers (temporary: dropped with the transaction).
CREATE OR REPLACE FUNCTION pg_temp.act_as(p_user uuid) RETURNS void
LANGUAGE sql AS $$
  SELECT set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text,
    true
  );
$$;

CREATE OR REPLACE FUNCTION pg_temp.place_order(p_method text, p_qty integer DEFAULT 1)
RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  RETURN public.create_order_atomic(
    jsonb_build_object(
      'owner_id', '00000000-0000-4000-8000-0000000000a1',
      'payment_method', p_method,
      'customer_name', 'T Cust',
      'customer_address', 'Test address',
      'customer_latitude', '14.6',
      'customer_longitude', '121.0'
    ),
    jsonb_build_array(jsonb_build_object(
      'product_id', '00000000-0000-4000-8000-0000000000b1',
      'quantity', p_qty,
      'product_name', 'T Water'
    ))
  );
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.assert_eq(p_label text, p_actual anyelement, p_expected anyelement)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF p_actual IS DISTINCT FROM p_expected THEN
    RAISE EXCEPTION '% — expected %, got %', p_label, p_expected, p_actual;
  END IF;
END;
$$;

-- Runs p_sql and fails unless it raises an error containing p_message.
CREATE OR REPLACE FUNCTION pg_temp.expect_error(p_label text, p_sql text, p_message text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    IF position(p_message IN SQLERRM) = 0 THEN
      RAISE EXCEPTION '% — expected error "%", got "%"', p_label, p_message, SQLERRM;
    END IF;
    RETURN;
  END;
  RAISE EXCEPTION '% — expected error "%", but it succeeded', p_label, p_message;
END;
$$;
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
ROLLBACK;
