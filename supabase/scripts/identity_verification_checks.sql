-- ==============================================================================
-- On-device ID checks saved with each verification (2026-11-06)
-- ==============================================================================
-- The app now screens ID photos on the phone with Google ML Kit (free,
-- offline): name and ID number read from the card, face on the ID, the
-- PhilSys National ID QR, and a live selfie (head turn + blink). The result
-- is stored in identity_verifications.auto_checks for the admin reviewer.
--
-- It is reported by the user's device, so it is advice only: nothing here
-- approves a user. Size is capped and the value is tagged device_reported.
--
-- Replaces submit_identity_verification (identity_verification.sql) with
-- one extra optional parameter; older app builds keep working.
-- Test: supabase/tests/identity_verification_checks_test.sql
-- ==============================================================================

BEGIN;

ALTER TABLE public.identity_verifications
  ADD COLUMN IF NOT EXISTS auto_checks jsonb;

DROP FUNCTION IF EXISTS public.submit_identity_verification(text, text, text, text, text, text);

CREATE OR REPLACE FUNCTION public.submit_identity_verification(
  p_id_type text,
  p_id_number_last4 text,
  p_front_path text,
  p_back_path text,
  p_selfie_path text,
  p_business_permit_path text DEFAULT NULL,
  p_auto_checks jsonb DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_role text;
  v_status text;
  v_prefix text;
  v_id uuid;
  v_checks jsonb;
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

  -- Advice from the device: keep small JSON objects only, and label them.
  IF p_auto_checks IS NOT NULL
     AND jsonb_typeof(p_auto_checks) = 'object'
     AND octet_length(p_auto_checks::text) <= 8192 THEN
    v_checks := p_auto_checks || jsonb_build_object('device_reported', true);
  END IF;

  INSERT INTO public.identity_verifications (
    user_id, role, id_type, id_number_last4, front_path, back_path, selfie_path,
    business_permit_path, auto_checks)
  VALUES (v_uid, v_role, p_id_type, NULLIF(p_id_number_last4, ''), p_front_path, p_back_path,
          p_selfie_path, p_business_permit_path, v_checks)
  RETURNING id INTO v_id;

  UPDATE public.profiles SET verification_status = 'pending' WHERE id = v_uid;
  RETURN jsonb_build_object('id', v_id, 'status', 'pending');
END; $$;

REVOKE ALL ON FUNCTION public.submit_identity_verification(text, text, text, text, text, text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_identity_verification(text, text, text, text, text, text, jsonb) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
