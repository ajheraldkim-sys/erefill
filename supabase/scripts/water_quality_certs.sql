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
BEGIN;

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

COMMIT;

NOTIFY pgrst, 'reload schema';
