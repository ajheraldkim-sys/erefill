-- Apply after automated_proof_of_delivery.sql.
-- This is the authoritative order lifecycle RPC implementation.

BEGIN;

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS delivery_type text NOT NULL DEFAULT 'delivery';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.orders'::regclass
      AND conname = 'orders_delivery_type_check'
  ) THEN
    ALTER TABLE public.orders
      ADD CONSTRAINT orders_delivery_type_check
      CHECK (delivery_type IN ('delivery', 'pickup'));
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.transition_order_status_safely(
  p_order_id uuid,
  p_new_status text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_role text;
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

  SELECT role INTO v_role
  FROM public.profiles
  WHERE id = auth.uid();

  IF NOT (
    (v_role = 'owner' AND auth.uid() = v_order.owner_id)
    OR (v_role = 'rider' AND auth.uid() IN (
      v_order.assigned_rider_id, v_order.rider_id
    ))
    OR (v_role = 'customer' AND auth.uid() = v_order.customer_id)
    OR public.is_admin()
  ) THEN
    RAISE EXCEPTION 'You are not authorized to make this order status change.';
  END IF;

  IF p_new_status = 'delivered' THEN
    RAISE EXCEPTION
      'Orders must be completed through verified delivery or pickup confirmation.';
  END IF;

  IF v_order.status::text = p_new_status THEN
    RETURN jsonb_build_object(
      'success', true,
      'status', p_new_status,
      'already_applied', true
    );
  END IF;

  IF v_role = 'owner' AND auth.uid() = v_order.owner_id THEN
    IF NOT (
      (v_order.status = 'pending' AND p_new_status IN ('accepted', 'cancelled'))
      OR (v_order.status = 'accepted' AND p_new_status IN ('preparing', 'cancelled'))
      OR (v_order.status = 'preparing' AND p_new_status IN ('ready_for_pickup', 'cancelled'))
      OR (v_order.status IN ('ready_for_pickup', 'assigned_to_rider', 'out_for_delivery')
          AND p_new_status = 'cancelled')
    ) THEN
      RAISE EXCEPTION
        'Invalid station order status transition from % to %.',
        v_order.status, p_new_status;
    END IF;
  ELSIF v_role = 'rider'
      AND auth.uid() IN (v_order.assigned_rider_id, v_order.rider_id) THEN
    IF NOT (
      (v_order.status IN ('assigned_to_rider', 'ready_for_pickup')
       AND p_new_status = 'out_for_delivery')
    ) THEN
      RAISE EXCEPTION
        'Invalid rider order status transition from % to %.',
        v_order.status, p_new_status;
    END IF;
  ELSIF v_role = 'customer'
      AND auth.uid() = v_order.customer_id
      AND v_order.status = 'pending'
      AND p_new_status = 'cancelled' THEN
    NULL;
  ELSIF public.is_admin() THEN
    NULL;
  ELSE
    RAISE EXCEPTION 'You are not authorized to make this order status change.';
  END IF;

  UPDATE public.orders
  SET status = p_new_status::public.order_status,
      updated_at = now()
  WHERE id = p_order_id;

  IF v_order.customer_id IS NOT NULL THEN
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
    ELSIF p_new_status = 'cancelled' THEN
      INSERT INTO public.system_notifications (
        user_id, type, priority, title, content, metadata
      ) VALUES (
        v_order.customer_id, 'system_alert', 'high', 'Order Cancelled',
        'Your water refill order was cancelled.',
        jsonb_build_object('order_id', p_order_id, 'status', 'cancelled')
      );
    END IF;
  END IF;

  RETURN jsonb_build_object('success', true, 'status', p_new_status);
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_pickup_order_safely(
  p_order_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
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
    WHERE id = auth.uid() AND role = 'owner'
  ) OR auth.uid() <> v_order.owner_id THEN
    RAISE EXCEPTION 'Only this station owner can complete a pickup order.';
  END IF;

  IF v_order.delivery_type <> 'pickup' THEN
    RAISE EXCEPTION 'Only pickup orders can be completed by the station.';
  END IF;

  IF v_order.status = 'delivered' THEN
    IF EXISTS (
      SELECT 1 FROM public.audit_logs
      WHERE action = 'OWNER_COMPLETE_PICKUP'
        AND entity_type = 'order'
        AND entity_id = p_order_id::text
    ) THEN
      RETURN jsonb_build_object(
        'success', true,
        'status', 'delivered',
        'already_applied', true
      );
    END IF;
    RAISE EXCEPTION
      'Pickup order is already delivered without an owner completion audit record.';
  END IF;

  IF v_order.status <> 'ready_for_pickup' THEN
    RAISE EXCEPTION 'Only a ready pickup order can be completed.';
  END IF;

  UPDATE public.orders
  SET status = 'delivered',
      actual_completion_at = coalesce(actual_completion_at, now()),
      updated_at = now()
  WHERE id = p_order_id;

  INSERT INTO public.audit_logs (
    actor_id, action, entity_type, entity_id, old_value, new_value, metadata
  ) VALUES (
    auth.uid(),
    'OWNER_COMPLETE_PICKUP',
    'order',
    p_order_id::text,
    jsonb_build_object('status', v_order.status),
    jsonb_build_object('status', 'delivered'),
    jsonb_build_object('delivery_type', 'pickup')
  );

  IF v_order.customer_id IS NOT NULL THEN
    INSERT INTO public.system_notifications (
      user_id, type, priority, title, content, metadata
    ) VALUES (
      v_order.customer_id, 'system_alert', 'high', 'Pickup Order Completed',
      'Your refill order was collected from the water station.',
      jsonb_build_object('order_id', p_order_id, 'status', 'delivered')
    );
  END IF;

  RETURN jsonb_build_object('success', true, 'status', 'delivered');
END;
$$;

GRANT EXECUTE ON FUNCTION public.transition_order_status_safely(uuid, text)
  TO authenticated;
REVOKE ALL ON FUNCTION public.transition_order_status_safely(uuid, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_pickup_order_safely(uuid)
  TO authenticated;
REVOKE ALL ON FUNCTION public.complete_pickup_order_safely(uuid)
  FROM PUBLIC, anon;

COMMIT;
