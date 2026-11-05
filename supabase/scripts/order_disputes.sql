-- ==============================================================================
-- Order disputes and refunds (2026-11-05)
-- ==============================================================================
-- Extends the existing public.disputes table (status enum: open,
-- investigating, resolved, dismissed) with the customer -> station -> admin
-- flow:
--   1. Customer opens a dispute within 48 h of delivery, one per order,
--      with optional photo evidence (private bucket dispute_evidence).
--   2. Station accepts (refund amount) -> resolved, or explains -> the
--      dispute is escalated ('investigating') for an admin.
--   3. Customer may escalate if the station has not answered in 24 h.
--   4. Admin resolves with an optional refund, or dismisses.
-- A granted refund books a REFUND ledger entry against the station, notifies
-- the customer, and refunds against the station increase flagged_count.
-- Money movement: COD refunds are returned by the station in cash; online
-- payments are refunded by the admin in PayMongo (orders.payment_status is
-- set to 'refunded' when the full total is refunded).
--
-- Test: supabase/tests/order_disputes_test.sql
-- ==============================================================================
BEGIN;

ALTER TABLE public.disputes
  ADD COLUMN IF NOT EXISTS evidence_paths text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS owner_response text,
  ADD COLUMN IF NOT EXISTS owner_responded_at timestamptz,
  ADD COLUMN IF NOT EXISTS refund_amount numeric(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS escalated_at timestamptz;
ALTER TABLE public.disputes DROP CONSTRAINT IF EXISTS disputes_reason_check;
ALTER TABLE public.disputes ADD CONSTRAINT disputes_reason_check CHECK (reason IN (
  'missing_items', 'wrong_item', 'quality', 'damaged', 'not_delivered', 'overcharged', 'other'));
ALTER TABLE public.disputes DROP CONSTRAINT IF EXISTS disputes_refund_check;
ALTER TABLE public.disputes ADD CONSTRAINT disputes_refund_check CHECK (refund_amount >= 0);
CREATE UNIQUE INDEX IF NOT EXISTS disputes_one_per_order ON public.disputes (order_id);

-- Owners no longer update disputes directly; they use owner_respond_dispute.
DROP POLICY IF EXISTS "Owners can update disputes for their station" ON public.disputes;
REVOKE INSERT, DELETE ON public.disputes FROM anon, authenticated;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('dispute_evidence', 'dispute_evidence', false, 8388608,
        ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO UPDATE SET public = false;
DROP POLICY IF EXISTS "Dispute evidence: reporter upload" ON storage.objects;
CREATE POLICY "Dispute evidence: reporter upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'dispute_evidence' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "Dispute evidence: parties read" ON storage.objects;
CREATE POLICY "Dispute evidence: parties read" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'dispute_evidence' AND (
    (storage.foldername(name))[1] = auth.uid()::text
    OR public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.disputes d JOIN public.orders o ON o.id = d.order_id
      WHERE storage.objects.name = ANY (d.evidence_paths) AND o.owner_id = auth.uid())));

CREATE OR REPLACE FUNCTION public.open_dispute(
  p_order_id uuid, p_reason text, p_description text, p_evidence_paths text[] DEFAULT '{}'
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_order public.orders%ROWTYPE;
  v_done_at timestamptz;
  v_id uuid;
  v_path text;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id AND customer_id = v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order not found.'; END IF;
  IF v_order.status::text <> 'delivered' THEN
    RAISE EXCEPTION 'You can report a problem once the order is delivered.';
  END IF;
  v_done_at := coalesce(v_order.actual_completion_at, v_order.updated_at, v_order.created_at);
  IF v_done_at < now() - interval '48 hours' THEN
    RAISE EXCEPTION 'Problems must be reported within 48 hours of delivery.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.disputes WHERE order_id = p_order_id) THEN
    RAISE EXCEPTION 'A problem was already reported for this order.';
  END IF;
  IF coalesce(trim(p_description), '') = '' THEN
    RAISE EXCEPTION 'Tell the station what went wrong.';
  END IF;
  FOREACH v_path IN ARRAY coalesce(p_evidence_paths, '{}') LOOP
    IF left(v_path, length(v_uid::text) + 1) <> v_uid::text || '/' THEN
      RAISE EXCEPTION 'Invalid evidence photo.';
    END IF;
  END LOOP;

  INSERT INTO public.disputes (order_id, reporter_id, reason, description, status, evidence_paths)
  VALUES (p_order_id, v_uid, p_reason, trim(p_description), 'open', coalesce(p_evidence_paths, '{}'))
  RETURNING id INTO v_id;

  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (v_order.owner_id, 'system_alert', 'high', 'A customer reported a problem',
    'Order #' || upper(substr(p_order_id::text, 1, 8)) || ': ' || replace(p_reason, '_', ' ')
      || '. Please respond within 24 hours.',
    jsonb_build_object('dispute_id', v_id, 'order_id', p_order_id));
  RETURN jsonb_build_object('id', v_id, 'status', 'open');
END; $$;

-- Shared by station and admin resolutions.
CREATE OR REPLACE FUNCTION public.apply_dispute_refund(p_dispute_id uuid, p_amount numeric, p_note text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_d public.disputes%ROWTYPE;
  v_o public.orders%ROWTYPE;
BEGIN
  SELECT * INTO v_d FROM public.disputes WHERE id = p_dispute_id;
  SELECT * INTO v_o FROM public.orders WHERE id = v_d.order_id;
  IF p_amount < 0 OR p_amount > v_o.total_amount THEN
    RAISE EXCEPTION 'Refund must be between PHP 0 and the order total.';
  END IF;
  UPDATE public.disputes SET refund_amount = p_amount, status = 'resolved',
         resolution_notes = p_note, updated_at = now()
  WHERE id = p_dispute_id;
  IF p_amount > 0 THEN
    INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
    VALUES (v_o.owner_id, v_o.id, -p_amount, 'REFUND', 'Refund for reported problem');
    UPDATE public.profiles SET flagged_count = coalesce(flagged_count, 0) + 1 WHERE id = v_o.owner_id;
    IF p_amount >= v_o.total_amount THEN
      UPDATE public.orders SET payment_status = 'refunded' WHERE id = v_o.id;
    END IF;
  END IF;
  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (v_d.reporter_id, 'system_alert', 'high',
    CASE WHEN p_amount > 0 THEN 'Refund approved' ELSE 'Your report was reviewed' END,
    CASE WHEN p_amount > 0
      THEN 'PHP ' || trim(to_char(p_amount, '999990.00')) || ' will be returned '
        || CASE WHEN lower(coalesce(v_o.payment_method, 'cod')) IN ('cod', 'cash')
                THEN 'by the station in cash.' ELSE 'to your original payment method.' END
      ELSE coalesce(p_note, 'No refund was given.') END,
    jsonb_build_object('dispute_id', p_dispute_id, 'order_id', v_o.id, 'refund_amount', p_amount));
END; $$;
REVOKE ALL ON FUNCTION public.apply_dispute_refund(uuid, numeric, text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.owner_respond_dispute(
  p_dispute_id uuid, p_accept boolean, p_response text, p_refund_amount numeric DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_d public.disputes%ROWTYPE;
BEGIN
  SELECT d.* INTO v_d FROM public.disputes d JOIN public.orders o ON o.id = d.order_id
  WHERE d.id = p_dispute_id AND o.owner_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Dispute not found.'; END IF;
  IF v_d.status::text <> 'open' OR v_d.owner_responded_at IS NOT NULL THEN
    RAISE EXCEPTION 'This dispute was already answered.';
  END IF;
  IF coalesce(trim(p_response), '') = '' THEN RAISE EXCEPTION 'Write a reply to the customer.'; END IF;

  UPDATE public.disputes SET owner_response = trim(p_response), owner_responded_at = now(), updated_at = now()
  WHERE id = p_dispute_id;

  IF p_accept THEN
    PERFORM public.apply_dispute_refund(p_dispute_id, coalesce(p_refund_amount, 0), 'Station: ' || trim(p_response));
    RETURN jsonb_build_object('status', 'resolved');
  END IF;

  UPDATE public.disputes SET status = 'investigating', escalated_at = now() WHERE id = p_dispute_id;
  RETURN jsonb_build_object('status', 'investigating');
END; $$;

CREATE OR REPLACE FUNCTION public.escalate_dispute(p_dispute_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  UPDATE public.disputes SET status = 'investigating', escalated_at = now(), updated_at = now()
  WHERE id = p_dispute_id AND reporter_id = auth.uid() AND status = 'open'
    AND owner_responded_at IS NULL AND created_at < now() - interval '24 hours';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'You can ask eRefill to step in 24 hours after reporting if the station has not replied.';
  END IF;
  RETURN jsonb_build_object('status', 'investigating');
END; $$;

CREATE OR REPLACE FUNCTION public.admin_resolve_dispute(
  p_dispute_id uuid, p_refund_amount numeric, p_notes text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.disputes WHERE id = p_dispute_id AND status IN ('open', 'investigating')) THEN
    RAISE EXCEPTION 'This dispute is already closed.';
  END IF;
  UPDATE public.disputes SET resolved_by = auth.uid() WHERE id = p_dispute_id;
  PERFORM public.apply_dispute_refund(p_dispute_id, coalesce(p_refund_amount, 0), p_notes);
  IF coalesce(p_refund_amount, 0) = 0 THEN
    UPDATE public.disputes SET status = 'dismissed' WHERE id = p_dispute_id;
  END IF;
  RETURN jsonb_build_object('status', CASE WHEN coalesce(p_refund_amount, 0) > 0 THEN 'resolved' ELSE 'dismissed' END);
END; $$;

REVOKE ALL ON FUNCTION public.open_dispute(uuid, text, text, text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.open_dispute(uuid, text, text, text[]) TO authenticated;
REVOKE ALL ON FUNCTION public.owner_respond_dispute(uuid, boolean, text, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.owner_respond_dispute(uuid, boolean, text, numeric) TO authenticated;
REVOKE ALL ON FUNCTION public.escalate_dispute(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.escalate_dispute(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_resolve_dispute(uuid, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_resolve_dispute(uuid, numeric, text) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
