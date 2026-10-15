-- Fix Order Transitions, Sync Rider Columns, and Enhance Realtime Reliability

-- 1. Synchronize rider_id and assigned_rider_id trigger
CREATE OR REPLACE FUNCTION public.sync_order_rider_columns()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.assigned_rider_id IS NOT NULL AND NEW.rider_id IS NULL THEN
    NEW.rider_id := NEW.assigned_rider_id;
  ELSIF NEW.rider_id IS NOT NULL AND NEW.assigned_rider_id IS NULL THEN
    NEW.assigned_rider_id := NEW.rider_id;
  ELSIF NEW.assigned_rider_id IS NOT NULL AND NEW.rider_id IS NOT NULL AND NEW.assigned_rider_id <> NEW.rider_id THEN
    IF OLD.assigned_rider_id IS DISTINCT FROM NEW.assigned_rider_id THEN
      NEW.rider_id := NEW.assigned_rider_id;
    ELSIF OLD.rider_id IS DISTINCT FROM NEW.rider_id THEN
      NEW.assigned_rider_id := NEW.rider_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_sync_order_rider_columns ON public.orders;
CREATE TRIGGER trg_sync_order_rider_columns
BEFORE INSERT OR UPDATE ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.sync_order_rider_columns();

-- 2. Backfill existing orders where one is populated and the other is null
UPDATE public.orders
SET rider_id = assigned_rider_id
WHERE assigned_rider_id IS NOT NULL AND rider_id IS NULL;

UPDATE public.orders
SET assigned_rider_id = rider_id
WHERE rider_id IS NOT NULL AND assigned_rider_id IS NULL;

-- 3. Comprehensive order status transition function
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

GRANT EXECUTE ON FUNCTION public.transition_order_status_safely(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.transition_order_status_safely(uuid, text) TO service_role;

