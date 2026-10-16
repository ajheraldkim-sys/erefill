-- Automated, idempotent proof-of-delivery receipt and chat workflow.

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS delivery_note text;

CREATE TABLE IF NOT EXISTS public.delivery_receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL UNIQUE REFERENCES public.orders(id) ON DELETE RESTRICT,
  receipt_number text NOT NULL UNIQUE,
  chat_room_id uuid NOT NULL REFERENCES public.chat_rooms(id) ON DELETE RESTRICT,
  message_id uuid REFERENCES public.messages(id) ON DELETE RESTRICT,
  snapshot jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS delivery_receipts_chat_room_idx
  ON public.delivery_receipts(chat_room_id);

ALTER TABLE public.delivery_receipts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authorized users can view delivery receipts"
  ON public.delivery_receipts;
CREATE POLICY "Authorized users can view delivery receipts"
  ON public.delivery_receipts
  FOR SELECT
  TO authenticated
  USING (
    public.is_admin()
    OR EXISTS (
      SELECT 1
      FROM public.orders o
      WHERE o.id = delivery_receipts.order_id
        AND auth.uid() IN (
          o.customer_id,
          o.owner_id,
          o.assigned_rider_id
        )
    )
  );

REVOKE ALL ON public.delivery_receipts FROM anon, authenticated;
GRANT SELECT ON public.delivery_receipts TO authenticated;

CREATE UNIQUE INDEX IF NOT EXISTS system_notifications_delivery_receipt_idx
  ON public.system_notifications (
    user_id,
    (metadata->>'delivery_receipt_id')
  )
  WHERE metadata ? 'delivery_receipt_id';

UPDATE storage.buckets
SET public = false,
    file_size_limit = 10485760,
    allowed_mime_types = ARRAY['image/jpeg', 'image/png']::text[]
WHERE id = 'delivery_proofs';

DROP POLICY IF EXISTS "Public can view delivery proofs" ON storage.objects;
DROP POLICY IF EXISTS "Riders can upload delivery proofs" ON storage.objects;
DROP POLICY IF EXISTS "Assigned riders can upload delivery proofs"
  ON storage.objects;
DROP POLICY IF EXISTS "Authorized users can view delivery proofs"
  ON storage.objects;
DROP POLICY IF EXISTS "Assigned riders can replace pending delivery proofs"
  ON storage.objects;

CREATE POLICY "Authorized users can view delivery proofs"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'delivery_proofs'
    AND (
      public.is_admin()
      OR EXISTS (
        SELECT 1
        FROM public.orders o
        WHERE o.id::text = (storage.foldername(name))[1]
          AND auth.uid() IN (
            o.customer_id,
            o.owner_id,
            o.assigned_rider_id
          )
        )
    )
  );

CREATE POLICY "Assigned riders can upload delivery proofs"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'delivery_proofs'
    AND EXISTS (
      SELECT 1
      FROM public.orders o
      WHERE o.id::text = (storage.foldername(name))[1]
        AND o.assigned_rider_id = auth.uid()
        AND o.status = 'out_for_delivery'
    )
  );

CREATE POLICY "Assigned riders can replace pending delivery proofs"
  ON storage.objects
  FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'delivery_proofs'
    AND EXISTS (
      SELECT 1
      FROM public.orders o
      WHERE o.id::text = (storage.foldername(name))[1]
        AND o.assigned_rider_id = auth.uid()
        AND o.status = 'out_for_delivery'
    )
  )
  WITH CHECK (
    bucket_id = 'delivery_proofs'
    AND EXISTS (
      SELECT 1
      FROM public.orders o
      WHERE o.id::text = (storage.foldername(name))[1]
        AND o.assigned_rider_id = auth.uid()
        AND o.status = 'out_for_delivery'
    )
  );

CREATE OR REPLACE FUNCTION public.guard_rider_delivery_record_updates()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role public.user_role;
BEGIN
  SELECT role INTO v_role
  FROM public.profiles
  WHERE id = auth.uid();

  IF v_role = 'rider'
     AND auth.uid() = OLD.assigned_rider_id
     AND coalesce(
       current_setting('app.delivery_receipt_rpc', true),
       'off'
     ) <> 'on'
  THEN
    IF NEW.status IS DISTINCT FROM OLD.status
       AND NEW.status <> 'out_for_delivery' THEN
      RAISE EXCEPTION
        'Riders must use verified delivery confirmation to complete an order.';
    END IF;

    IF ROW(
         NEW.assigned_rider_id,
         NEW.rider_id,
         NEW.total_amount,
         NEW.subtotal,
         NEW.delivery_fee,
         NEW.platform_fee,
         NEW.payment_status,
         NEW.delivery_photo_url,
         NEW.delivery_signature_url,
         NEW.actual_completion_at,
         NEW.delivery_note,
         NEW.empty_gallons_returned,
         NEW.delivery_latitude,
         NEW.delivery_longitude
       ) IS DISTINCT FROM ROW(
         OLD.assigned_rider_id,
         OLD.rider_id,
         OLD.total_amount,
         OLD.subtotal,
         OLD.delivery_fee,
         OLD.platform_fee,
         OLD.payment_status,
         OLD.delivery_photo_url,
         OLD.delivery_signature_url,
         OLD.actual_completion_at,
         OLD.delivery_note,
         OLD.empty_gallons_returned,
         OLD.delivery_latitude,
         OLD.delivery_longitude
       )
    THEN
      RAISE EXCEPTION
        'Riders cannot change order amounts, payment status, or delivery evidence directly.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_rider_delivery_record_updates
  ON public.orders;
CREATE TRIGGER trg_guard_rider_delivery_record_updates
BEFORE UPDATE ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.guard_rider_delivery_record_updates();

CREATE OR REPLACE FUNCTION public.guard_verified_delivery_record_mutations()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_old_evidence jsonb;
  v_new_evidence jsonb;
BEGIN
  IF OLD.status = 'delivered' THEN
    v_old_evidence := jsonb_build_object(
      'delivery_photo_url', OLD.delivery_photo_url,
      'delivery_signature_url', OLD.delivery_signature_url,
      'actual_completion_at', OLD.actual_completion_at,
      'delivery_note', OLD.delivery_note,
      'empty_gallons_returned', OLD.empty_gallons_returned,
      'delivery_latitude', OLD.delivery_latitude,
      'delivery_longitude', OLD.delivery_longitude,
      'payment_status', OLD.payment_status,
      'total_amount', OLD.total_amount,
      'subtotal', OLD.subtotal,
      'delivery_fee', OLD.delivery_fee,
      'platform_fee', OLD.platform_fee
    );
    v_new_evidence := jsonb_build_object(
      'delivery_photo_url', NEW.delivery_photo_url,
      'delivery_signature_url', NEW.delivery_signature_url,
      'actual_completion_at', NEW.actual_completion_at,
      'delivery_note', NEW.delivery_note,
      'empty_gallons_returned', NEW.empty_gallons_returned,
      'delivery_latitude', NEW.delivery_latitude,
      'delivery_longitude', NEW.delivery_longitude,
      'payment_status', NEW.payment_status,
      'total_amount', NEW.total_amount,
      'subtotal', NEW.subtotal,
      'delivery_fee', NEW.delivery_fee,
      'platform_fee', NEW.platform_fee
    );

    IF v_old_evidence IS DISTINCT FROM v_new_evidence THEN
      IF auth.role() IS DISTINCT FROM 'service_role'
         AND NOT public.is_admin() THEN
        RAISE EXCEPTION
          'Verified delivery evidence and receipt amounts cannot be modified.';
      END IF;

      IF public.is_admin() THEN
        INSERT INTO public.audit_logs (
          actor_id,
          action,
          entity_type,
          entity_id,
          old_value,
          new_value,
          metadata
        )
        VALUES (
          auth.uid(),
          'ADMIN_CORRECT_DELIVERY_RECORD',
          'order',
          OLD.id::text,
          v_old_evidence,
          v_new_evidence,
          jsonb_build_object('receipt_preserved', true)
        );
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_verified_delivery_record_mutations
  ON public.orders;
CREATE TRIGGER trg_guard_verified_delivery_record_mutations
BEFORE UPDATE ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.guard_verified_delivery_record_mutations();

CREATE OR REPLACE FUNCTION public.guard_system_message_spoofing()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF (NEW.sender_id IS NULL OR NEW.message_type = 'system')
     AND coalesce(
       current_setting('app.delivery_receipt_rpc', true),
       'off'
     ) <> 'on'
     AND auth.role() IS DISTINCT FROM 'service_role'
     AND NOT EXISTS (
       SELECT 1 FROM public.profiles
       WHERE id = auth.uid() AND role = 'admin'
     )
  THEN
    RAISE EXCEPTION
      'Unauthorized: Only the system, an administrator, or the delivery confirmation workflow can issue system messages.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_system_message_spoofing ON public.messages;
CREATE TRIGGER trg_guard_system_message_spoofing
BEFORE INSERT ON public.messages
FOR EACH ROW EXECUTE FUNCTION public.guard_system_message_spoofing();

CREATE OR REPLACE FUNCTION public.guard_delivery_receipt_message_mutations()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.metadata ? 'delivery_receipt_id' THEN
    IF TG_OP = 'UPDATE' THEN
      IF ROW(
           NEW.room_id,
           NEW.sender_id,
           NEW.content,
           NEW.message_type,
           NEW.metadata,
           NEW.reply_to,
           NEW.created_at,
           NEW.deleted_at
         ) IS NOT DISTINCT FROM ROW(
           OLD.room_id,
           OLD.sender_id,
           OLD.content,
           OLD.message_type,
           OLD.metadata,
           OLD.reply_to,
           OLD.created_at,
           OLD.deleted_at
         )
      THEN
        RETURN NEW;
      END IF;
    END IF;

    IF auth.role() IS DISTINCT FROM 'service_role'
       AND NOT public.is_admin() THEN
      RAISE EXCEPTION 'Delivery receipt messages cannot be changed or deleted.';
    END IF;

    IF public.is_admin() THEN
      INSERT INTO public.audit_logs (
        actor_id,
        action,
        entity_type,
        entity_id,
        old_value,
        new_value,
        metadata
      )
      VALUES (
        auth.uid(),
        CASE WHEN TG_OP = 'DELETE'
          THEN 'DELETE_DELIVERY_RECEIPT_MESSAGE'
          ELSE 'UPDATE_DELIVERY_RECEIPT_MESSAGE'
        END,
        'message',
        OLD.id::text,
        to_jsonb(OLD),
        CASE WHEN TG_OP = 'DELETE' THEN NULL ELSE to_jsonb(NEW) END,
        jsonb_build_object(
          'delivery_receipt_id', OLD.metadata->>'delivery_receipt_id',
          'order_id', OLD.metadata->'delivery_receipt'->>'order_id'
        )
      );
    END IF;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_delivery_receipt_message_mutations
  ON public.messages;
CREATE TRIGGER trg_guard_delivery_receipt_message_mutations
BEFORE UPDATE OR DELETE ON public.messages
FOR EACH ROW EXECUTE FUNCTION public.guard_delivery_receipt_message_mutations();

CREATE OR REPLACE FUNCTION public.notify_chat_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sender_name text;
  v_part record;
  v_body text;
  v_receipt_id text;
BEGIN
  IF NEW.deleted_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  v_receipt_id := NEW.metadata->>'delivery_receipt_id';
  IF v_receipt_id IS NOT NULL THEN
    v_sender_name := 'Erefill Delivery Receipt';
    v_body := 'Delivery completed. Receipt '
      || coalesce(NEW.metadata->'delivery_receipt'->>'receipt_number', '')
      || ' is available in your order chat.';
  ELSE
    IF NEW.sender_id IS NOT NULL THEN
      SELECT coalesce(nullif(trim(full_name), ''), nullif(trim(username), ''), 'Someone')
      INTO v_sender_name
      FROM public.profiles
      WHERE id = NEW.sender_id;
      IF v_sender_name IS NULL THEN
        v_sender_name := 'New Message';
      END IF;
    ELSE
      v_sender_name := 'eRefill System';
    END IF;

    IF NEW.message_type = 'image' THEN
      v_body := '📷 Photo message';
    ELSIF NEW.message_type = 'quick_reply' THEN
      v_body := coalesce(NEW.content, 'Quick response');
    ELSE
      v_body := coalesce(NEW.content, 'New message');
    END IF;
  END IF;

  FOR v_part IN
    SELECT user_id
    FROM public.chat_participants
    WHERE room_id = NEW.room_id
      AND user_id IS NOT NULL
      AND user_id <> coalesce(
        NEW.sender_id,
        '00000000-0000-0000-0000-000000000000'::uuid
      )
  LOOP
    INSERT INTO public.system_notifications (
      user_id,
      type,
      priority,
      title,
      content,
      action_url,
      metadata
    )
    VALUES (
      v_part.user_id,
      'new_message',
      'high',
      v_sender_name,
      v_body,
      '/chat?roomId=' || NEW.room_id::text,
      jsonb_build_object(
        'room_id', NEW.room_id,
        'sender_id', NEW.sender_id,
        'sender_name', v_sender_name
      ) || CASE
        WHEN v_receipt_id IS NULL THEN '{}'::jsonb
        ELSE jsonb_build_object('delivery_receipt_id', v_receipt_id)
      END
    )
    ON CONFLICT DO NOTHING;
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_chat_message ON public.messages;
CREATE TRIGGER trg_notify_chat_message
AFTER INSERT ON public.messages
FOR EACH ROW EXECUTE FUNCTION public.notify_chat_message();

DROP FUNCTION IF EXISTS public.confirm_delivery_safely(
  uuid, double precision, double precision, text, text
);

CREATE OR REPLACE FUNCTION public.confirm_delivery_safely(
  p_order_id uuid,
  p_lat double precision DEFAULT NULL,
  p_lng double precision DEFAULT NULL,
  p_photo_url text DEFAULT NULL,
  p_signature_url text DEFAULT NULL,
  p_delivery_note text DEFAULT NULL,
  p_empty_gallons_returned integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_rider_name text;
  v_room_id uuid;
  v_receipt_id uuid;
  v_receipt_number text;
  v_message_id uuid;
  v_delivered_at timestamptz;
  v_snapshot jsonb;
  v_message text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'Order not found');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'rider'
  ) OR auth.uid() <> v_order.assigned_rider_id THEN
    RAISE EXCEPTION 'Only the assigned rider can confirm this delivery.';
  END IF;

  IF v_order.status = 'delivered' THEN
    SELECT id, receipt_number, message_id
    INTO v_receipt_id, v_receipt_number, v_message_id
    FROM public.delivery_receipts
    WHERE order_id = p_order_id;

    IF v_receipt_id IS NULL THEN
      RETURN jsonb_build_object(
        'success', false,
        'message', 'This order was completed without a digital proof-of-delivery receipt.'
      );
    END IF;

    RETURN jsonb_build_object(
      'success', true,
      'message', 'Delivery receipt already exists.',
      'receipt_id', v_receipt_id,
      'receipt_number', v_receipt_number,
      'message_id', v_message_id
    );
  END IF;

  IF v_order.status <> 'out_for_delivery' THEN
    RAISE EXCEPTION 'Only an order out for delivery can be completed.';
  END IF;
  IF v_order.customer_id IS NULL THEN
    RAISE EXCEPTION 'The order has no customer conversation to receive its receipt.';
  END IF;

  IF nullif(trim(p_photo_url), '') IS NULL
     OR nullif(trim(p_signature_url), '') IS NULL THEN
    RAISE EXCEPTION 'A delivery photo and recipient signature are required.';
  END IF;

  IF (storage.foldername(p_photo_url))[1] IS DISTINCT FROM p_order_id::text
     OR (storage.foldername(p_signature_url))[1] IS DISTINCT FROM p_order_id::text THEN
    RAISE EXCEPTION 'Delivery evidence must be stored under this order.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM storage.objects
    WHERE bucket_id = 'delivery_proofs' AND name = p_photo_url
  ) OR NOT EXISTS (
    SELECT 1 FROM storage.objects
    WHERE bucket_id = 'delivery_proofs' AND name = p_signature_url
  ) THEN
    RAISE EXCEPTION 'The delivery photo and signature must finish uploading before confirmation.';
  END IF;

  IF p_empty_gallons_returned < 0 THEN
    RAISE EXCEPTION 'Returned empty gallons cannot be negative.';
  END IF;
  IF p_lat IS NOT NULL AND (p_lat < -90 OR p_lat > 90) THEN
    RAISE EXCEPTION 'Invalid delivery latitude.';
  END IF;
  IF p_lng IS NOT NULL AND (p_lng < -180 OR p_lng > 180) THEN
    RAISE EXCEPTION 'Invalid delivery longitude.';
  END IF;

  SELECT coalesce(nullif(trim(full_name), ''), username, 'Assigned Rider')
  INTO v_rider_name
  FROM public.profiles
  WHERE id = auth.uid();

  v_delivered_at := now();
  v_receipt_number :=
    'ER-' || to_char(v_delivered_at AT TIME ZONE 'UTC', 'YYYY')
    || '-' || upper(substr(p_order_id::text, 1, 8));

  PERFORM set_config('app.delivery_receipt_rpc', 'on', true);
  UPDATE public.orders
  SET status = 'delivered',
      actual_completion_at = v_delivered_at,
      delivery_photo_url = p_photo_url,
      delivery_signature_url = p_signature_url,
      delivery_note = nullif(trim(p_delivery_note), ''),
      empty_gallons_returned = coalesce(
        p_empty_gallons_returned,
        empty_gallons_returned,
        0
      ),
      delivery_latitude = coalesce(p_lat, delivery_latitude),
      delivery_longitude = coalesce(p_lng, delivery_longitude),
      updated_at = v_delivered_at
  WHERE id = p_order_id;

  SELECT cr.id INTO v_room_id
  FROM public.chat_rooms cr
  WHERE cr.reference_id = p_order_id
    AND cr.room_type = 'order_delivery'
    AND EXISTS (
      SELECT 1 FROM public.chat_participants cp
      WHERE cp.room_id = cr.id AND cp.user_id = v_order.customer_id
    )
  ORDER BY (cr.metadata->>'channel' = 'customer_rider') DESC,
           cr.created_at
  LIMIT 1;

  IF v_room_id IS NULL THEN
    INSERT INTO public.chat_rooms (
      room_type, reference_id, owner_id, title, status, metadata
    )
    VALUES (
      'order_delivery',
      p_order_id,
      v_order.owner_id,
      'Order Delivery',
      'active',
      jsonb_build_object(
        'channel', 'customer_rider',
        'order_id', p_order_id,
        'customer_name', v_order.customer_name,
        'rider_name', v_rider_name
      )
    )
    RETURNING id INTO v_room_id;
  END IF;

  INSERT INTO public.chat_participants (room_id, user_id, role_in_room)
  VALUES (v_room_id, v_order.customer_id, 'customer')
  ON CONFLICT (room_id, user_id)
  DO UPDATE SET role_in_room = EXCLUDED.role_in_room;

  IF v_order.owner_id IS NOT NULL THEN
    INSERT INTO public.chat_participants (room_id, user_id, role_in_room)
    VALUES (v_room_id, v_order.owner_id, 'owner')
    ON CONFLICT (room_id, user_id)
    DO UPDATE SET role_in_room = EXCLUDED.role_in_room;
  END IF;

  INSERT INTO public.chat_participants (room_id, user_id, role_in_room)
  VALUES (v_room_id, auth.uid(), 'rider')
  ON CONFLICT (room_id, user_id)
  DO UPDATE SET role_in_room = EXCLUDED.role_in_room;

  v_snapshot := jsonb_build_object(
    'receipt_number', v_receipt_number,
    'order_id', p_order_id,
    'reference_number', upper(substr(p_order_id::text, 1, 8)),
    'delivery_status', 'Delivered',
    'customer_name', coalesce(v_order.customer_name, 'Customer'),
    'recipient_name', coalesce(v_order.customer_name, 'Customer'),
    'customer_phone', v_order.customer_phone,
    'delivery_address', concat_ws(
      ', ',
      nullif(v_order.customer_address, ''),
      nullif(v_order.customer_barangay, ''),
      nullif(v_order.customer_municipality, '')
    ),
    'station_name', coalesce(v_order.station_name, 'Water Station'),
    'rider_name', coalesce(v_rider_name, 'Assigned Rider'),
    'items', CASE
      WHEN EXISTS (
        SELECT 1 FROM public.order_items oi WHERE oi.order_id = p_order_id
      ) THEN (
        SELECT jsonb_agg(
          jsonb_build_object(
            'product_name', oi.product_name,
            'quantity', oi.quantity,
            'unit_price', oi.price_at_purchase,
            'total_price', coalesce(
              nullif(oi.subtotal, 0),
              oi.price_at_purchase * oi.quantity
            )
          )
          ORDER BY oi.created_at, oi.id
        )
        FROM public.order_items oi
        WHERE oi.order_id = p_order_id
      )
      WHEN jsonb_array_length(coalesce(v_order.items, '[]'::jsonb)) > 0
        THEN v_order.items
      ELSE jsonb_build_array(jsonb_build_object(
        'product_name', coalesce(v_order.water_type, 'Water Refill'),
        'quantity', coalesce(v_order.quantity, 1),
        'unit_price', coalesce(v_order.subtotal, v_order.total_amount),
        'total_price', coalesce(v_order.subtotal, v_order.total_amount)
      ))
    END,
    'subtotal', v_order.subtotal,
    'delivery_fee', v_order.delivery_fee,
    'platform_fee', v_order.platform_fee,
    'total_amount', v_order.total_amount,
    'payment_method', v_order.payment_method,
    'payment_status', v_order.payment_status,
    'amount_paid', CASE
      WHEN v_order.payment_status::text IN ('success', 'paid')
        THEN v_order.total_amount
      ELSE 0
    END,
    'outstanding_balance', CASE
      WHEN v_order.payment_status::text IN ('success', 'paid')
        THEN 0
      ELSE v_order.total_amount
    END,
    'delivered_at', v_delivered_at,
    'photo_path', p_photo_url,
    'signature_path', p_signature_url
  );

  INSERT INTO public.delivery_receipts (
    order_id, receipt_number, chat_room_id, snapshot
  )
  VALUES (p_order_id, v_receipt_number, v_room_id, v_snapshot)
  RETURNING id INTO v_receipt_id;

  v_message := format(
    E'Your Erefill order has been delivered.\nOrder No.: %s\nDelivery Status: Delivered\nDelivered At: %s UTC\nRider: %s\nTotal Amount: PHP %s\nPayment Status: %s',
    upper(substr(p_order_id::text, 1, 8)),
    to_char(v_delivered_at AT TIME ZONE 'UTC', 'FMMonth DD, YYYY, HH12:MI AM'),
    coalesce(v_rider_name, 'Assigned Rider'),
    to_char(v_order.total_amount, 'FM999,999,990.00'),
    upper(v_order.payment_status::text)
  );

  PERFORM set_config('app.delivery_receipt_rpc', 'on', true);
  INSERT INTO public.messages (
    room_id, sender_id, content, message_type, metadata
  )
  VALUES (
    v_room_id,
    auth.uid(),
    v_message,
    'system',
    jsonb_build_object(
      'kind', 'delivery_receipt',
      'delivery_receipt_id', v_receipt_id,
      'delivery_receipt', v_snapshot
    )
  )
  RETURNING id INTO v_message_id;
  PERFORM set_config('app.delivery_receipt_rpc', 'off', true);

  UPDATE public.delivery_receipts
  SET message_id = v_message_id
  WHERE id = v_receipt_id;

  UPDATE public.chat_rooms
  SET status = 'active',
      archived_at = NULL,
      updated_at = v_delivered_at
  WHERE id = v_room_id;

  PERFORM set_config('app.delivery_receipt_rpc', 'off', true);

  RETURN jsonb_build_object(
    'success', true,
    'message', 'Delivery confirmed and receipt sent.',
    'receipt_id', v_receipt_id,
    'receipt_number', v_receipt_number,
    'message_id', v_message_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.confirm_delivery_safely(
  uuid, double precision, double precision, text, text, text, integer
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_delivery_safely(
  uuid, double precision, double precision, text, text, text, integer
) TO authenticated, service_role;
