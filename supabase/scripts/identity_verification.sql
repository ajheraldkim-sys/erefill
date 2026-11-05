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
BEGIN;

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

COMMIT;

NOTIFY pgrst, 'reload schema';
