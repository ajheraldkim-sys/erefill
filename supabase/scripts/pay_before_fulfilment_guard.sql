-- Online orders (GCash, Maya, Card, QR Ph) cannot be accepted, prepared,
-- dispatched or delivered until PayMongo confirms the payment. Cancelling is
-- always allowed; admins are not blocked. Run after qrph_payment_method.sql.
-- Safe to re-run.

BEGIN;

-- Three GCash orders were delivered before this guard existed and never
-- paid. Owner decision (2026-10-22): mark them paid as test data.
-- guard_verified_delivery_record_mutations only lets the service role change
-- a delivered order's payment status, so act as it for this one statement.
SELECT set_config('request.jwt.claims', '{"role": "service_role"}', true);
UPDATE public.orders
SET payment_status = 'success',
    payment_error = 'Marked paid as test data (2026-10-22)'
WHERE id IN (
  '8d2dc6e9-c8c3-4fd1-aa97-be2bbc4f60c8',
  '74ba3859-06d0-4b77-b086-a84078bfdfdf',
  '0ce436d4-a5c7-4d1f-96af-035985f71cfe'
)
AND payment_status <> 'success';
SELECT set_config('request.jwt.claims', '', true);

CREATE OR REPLACE FUNCTION public.order_awaits_online_payment(p_order public.orders)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT lower(coalesce(p_order.payment_method, 'cod')) IN ('gcash', 'maya', 'card', 'qrph')
     AND coalesce(p_order.payment_status::text, 'pending') <> 'success';
$function$;

-- Live transition_order_status_safely (2026-10-22) plus the payment guard.
CREATE OR REPLACE FUNCTION public.transition_order_status_safely(p_order_id uuid, p_new_status text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_order public.orders%ROWTYPE;
  v_role text;
  v_rider_name text;
  v_is_staff boolean := false;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'Order not found');
  END IF;

  SELECT role INTO v_role FROM public.profiles WHERE id = auth.uid();

  -- OWNER Transitions
  IF v_role = 'owner' AND auth.uid() = v_order.owner_id THEN
    v_is_staff := true;
    IF NOT (
      (v_order.status = 'pending' AND p_new_status IN ('accepted', 'cancelled'))
      OR (v_order.status = 'accepted' AND p_new_status IN ('preparing', 'cancelled'))
      OR (v_order.status = 'preparing' AND p_new_status IN ('ready_for_pickup', 'assigned_to_rider', 'out_for_delivery', 'delivered', 'cancelled'))
      OR (v_order.status = 'ready_for_pickup' AND p_new_status IN ('assigned_to_rider', 'out_for_delivery', 'delivered', 'cancelled'))
      OR (v_order.status = 'assigned_to_rider' AND p_new_status IN ('out_for_delivery', 'delivered', 'cancelled'))
      OR (v_order.status = 'out_for_delivery' AND p_new_status IN ('delivered', 'cancelled'))
    ) THEN
      RAISE EXCEPTION 'Invalid station order status transition from % to %.', v_order.status, p_new_status;
    END IF;

  -- RIDER Transitions
  ELSIF v_role = 'rider'
      AND (auth.uid() = v_order.assigned_rider_id OR auth.uid() = v_order.rider_id) THEN
    v_is_staff := true;
    IF NOT (
      (v_order.status = 'assigned_to_rider' AND p_new_status = 'out_for_delivery')
      OR (v_order.status = 'ready_for_pickup' AND p_new_status = 'out_for_delivery')
      OR (v_order.status = 'out_for_delivery' AND p_new_status = 'delivered')
    ) THEN
      RAISE EXCEPTION 'Invalid rider order status transition from % to %.', v_order.status, p_new_status;
    END IF;

  -- CUSTOMER Transitions
  ELSIF v_role = 'customer'
      AND auth.uid() = v_order.customer_id
      AND v_order.status = 'pending'
      AND p_new_status = 'cancelled' THEN
    NULL;

  -- ADMIN Transitions
  ELSIF public.is_admin() THEN
    NULL;

  ELSE
    RAISE EXCEPTION 'You are not authorized to make this order status change.';
  END IF;

  IF v_is_staff
     AND p_new_status <> 'cancelled'
     AND public.order_awaits_online_payment(v_order) THEN
    RAISE EXCEPTION 'This order is waiting for online payment.';
  END IF;

  UPDATE public.orders
  SET
    status = p_new_status::public.order_status,
    updated_at = now(),
    delivered_at = CASE WHEN p_new_status = 'delivered' THEN COALESCE(delivered_at, now()) ELSE delivered_at END,
    actual_completion_at = CASE WHEN p_new_status = 'delivered' THEN COALESCE(actual_completion_at, now()) ELSE actual_completion_at END
  WHERE id = p_order_id;

  -- Lifecycle status notifications for customer
  IF p_new_status = 'accepted' THEN
    INSERT INTO public.system_notifications (
      user_id, type, priority, title, content, metadata
    ) VALUES (
      v_order.customer_id, 'system_alert', 'high', 'Order Accepted',
      'The water station accepted your refill order and is preparing to refill.',
      jsonb_build_object('order_id', p_order_id, 'status', 'accepted')
    );
  ELSIF p_new_status = 'preparing' THEN
    INSERT INTO public.system_notifications (
      user_id, type, priority, title, content, metadata
    ) VALUES (
      v_order.customer_id, 'system_alert', 'normal', 'Refill in Preparation',
      'Your water containers are now being refilled and inspected.',
      jsonb_build_object('order_id', p_order_id, 'status', 'preparing')
    );
  ELSIF p_new_status = 'ready_for_pickup' THEN
    INSERT INTO public.system_notifications (
      user_id, type, priority, title, content, metadata
    ) VALUES (
      v_order.customer_id, 'system_alert', 'high', 'Ready for Pickup / Dispatch',
      'Your refill order is ready for station pickup or rider dispatch.',
      jsonb_build_object('order_id', p_order_id, 'status', 'ready_for_pickup')
    );
  ELSIF p_new_status = 'out_for_delivery' THEN
    INSERT INTO public.system_notifications (
      user_id, type, priority, title, content, metadata
    ) VALUES (
      v_order.customer_id, 'system_alert', 'high', 'Out for Delivery',
      'Your assigned rider is on the way with your water delivery.',
      jsonb_build_object('order_id', p_order_id, 'status', 'out_for_delivery')
    );
  ELSIF p_new_status = 'delivered' THEN
    INSERT INTO public.system_notifications (
      user_id, type, priority, title, content, metadata
    ) VALUES (
      v_order.customer_id, 'system_alert', 'high', 'Order Delivered',
      'Your water refill order has been delivered! Enjoy your pure water.',
      jsonb_build_object('order_id', p_order_id, 'status', 'delivered')
    );
  ELSIF p_new_status = 'cancelled' THEN
    INSERT INTO public.system_notifications (
      user_id, type, priority, title, content, metadata
    ) VALUES (
      v_order.customer_id, 'system_alert', 'high', 'Order Cancelled',
      'Your water refill order was cancelled.',
      jsonb_build_object('order_id', p_order_id, 'status', 'cancelled')
    );
  END IF;

  RETURN jsonb_build_object('success', true, 'status', p_new_status);
END;
$function$;

-- Live confirm_delivery_safely (2026-10-22) plus the payment guard.
CREATE OR REPLACE FUNCTION public.confirm_delivery_safely(
  p_order_id uuid,
  p_lat double precision DEFAULT NULL::double precision,
  p_lng double precision DEFAULT NULL::double precision,
  p_photo_url text DEFAULT NULL::text,
  p_signature_url text DEFAULT NULL::text,
  p_delivery_note text DEFAULT NULL::text,
  p_empty_gallons_returned integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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

  IF public.order_awaits_online_payment(v_order) THEN
    RAISE EXCEPTION 'This order is waiting for online payment.';
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
$function$;

COMMIT;
