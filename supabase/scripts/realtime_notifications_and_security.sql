-- ==============================================================================
-- EREFILL REAL-TIME NOTIFICATIONS, BADGES, AND ACCOUNT SECURITY MIGRATION
-- ==============================================================================

-- 1. Orders table enhancement for Owner & Admin Acknowledgment
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS owner_acknowledged_at timestamptz DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS admin_acknowledged_at timestamptz DEFAULT NULL;

CREATE INDEX IF NOT EXISTS idx_orders_owner_unacknowledged
  ON public.orders (owner_id, created_at DESC)
  WHERE (status = 'pending' AND owner_acknowledged_at IS NULL);

-- 2. Push Device Tokens Table
CREATE TABLE IF NOT EXISTS public.push_device_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token text NOT NULL,
  platform text NOT NULL CHECK (platform IN ('android', 'ios', 'web', 'other')),
  device_info text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, token)
);

CREATE INDEX IF NOT EXISTS idx_push_device_tokens_user
  ON public.push_device_tokens (user_id)
  WHERE is_active = true;

ALTER TABLE public.push_device_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own device tokens" ON public.push_device_tokens;
CREATE POLICY "Users can view own device tokens"
  ON public.push_device_tokens FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can insert own device tokens" ON public.push_device_tokens;
CREATE POLICY "Users can insert own device tokens"
  ON public.push_device_tokens FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can update own device tokens" ON public.push_device_tokens;
CREATE POLICY "Users can update own device tokens"
  ON public.push_device_tokens FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can delete own device tokens" ON public.push_device_tokens;
CREATE POLICY "Users can delete own device tokens"
  ON public.push_device_tokens FOR DELETE
  TO authenticated
  USING (user_id = auth.uid());

-- 3. Notification Delivery Logs & Transactional Outbox
CREATE TABLE IF NOT EXISTS public.notification_delivery_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  notification_id uuid REFERENCES public.system_notifications(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  channel text NOT NULL CHECK (channel IN ('in_app', 'push', 'email', 'sms')),
  recipient_target text NOT NULL,
  event_id text,
  status text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'sent', 'delivered', 'failed', 'bounced')),
  error_message text,
  retry_count integer NOT NULL DEFAULT 0,
  provider_response jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  delivered_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_notification_delivery_logs_user
  ON public.notification_delivery_logs (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notification_delivery_logs_status
  ON public.notification_delivery_logs (status, created_at ASC);

ALTER TABLE public.notification_delivery_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users view own delivery logs" ON public.notification_delivery_logs;
CREATE POLICY "Users view own delivery logs"
  ON public.notification_delivery_logs FOR SELECT
  TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

-- 4. Notification Preferences Table
CREATE TABLE IF NOT EXISTS public.user_notification_preferences (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  in_app_enabled boolean NOT NULL DEFAULT true,
  push_enabled boolean NOT NULL DEFAULT true,
  email_enabled boolean NOT NULL DEFAULT true,
  sms_enabled boolean NOT NULL DEFAULT false,
  order_updates boolean NOT NULL DEFAULT true,
  promotions boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.user_notification_preferences ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own notification preferences" ON public.user_notification_preferences;
CREATE POLICY "Users manage own notification preferences"
  ON public.user_notification_preferences FOR ALL
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- 5. RPC: Order Acknowledgment for Station Owners & Admin
CREATE OR REPLACE FUNCTION public.acknowledge_order(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_role text;
  v_updated boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
  END IF;

  SELECT role INTO v_role FROM public.profiles WHERE id = v_uid;

  IF v_role = 'owner' THEN
    UPDATE public.orders
    SET owner_acknowledged_at = coalesce(owner_acknowledged_at, now())
    WHERE id = p_order_id AND owner_id = v_uid;
    v_updated := FOUND;
  ELSIF v_role = 'admin' OR public.is_admin() THEN
    UPDATE public.orders
    SET admin_acknowledged_at = coalesce(admin_acknowledged_at, now())
    WHERE id = p_order_id;
    v_updated := FOUND;
  END IF;

  RETURN jsonb_build_object(
    'success', v_updated,
    'order_id', p_order_id,
    'acknowledged_at', now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.acknowledge_order(uuid) TO authenticated, service_role;

-- 6. RPC: Accurate Station New Orders Count (Unacknowledged)
CREATE OR REPLACE FUNCTION public.get_station_new_orders_count()
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_count integer := 0;
BEGIN
  IF v_uid IS NULL THEN
    RETURN 0;
  END IF;

  SELECT count(*)::integer INTO v_count
  FROM public.orders
  WHERE owner_id = v_uid
    AND status = 'pending'
    AND owner_acknowledged_at IS NULL;

  RETURN coalesce(v_count, 0);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_station_new_orders_count() TO authenticated, service_role;

-- 7. RPC: Accurate Total Unread Chat Count Across All Rooms
CREATE OR REPLACE FUNCTION public.get_total_unread_chat_count()
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_count integer := 0;
BEGIN
  IF v_uid IS NULL THEN
    RETURN 0;
  END IF;

  SELECT count(*)::integer INTO v_count
  FROM public.messages m
  JOIN public.chat_participants cp ON cp.room_id = m.room_id AND cp.user_id = v_uid
  WHERE m.sender_id IS DISTINCT FROM v_uid
    AND m.deleted_at IS NULL
    AND NOT (
      (m.read_by @> jsonb_build_array(v_uid::text))
      OR (m.read_by @> jsonb_build_array(v_uid))
    );

  RETURN coalesce(v_count, 0);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_total_unread_chat_count() TO authenticated, service_role;

-- 8. RPC: Unified User Notification & Badge Counts
CREATE OR REPLACE FUNCTION public.get_user_notification_counts()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_role text;
  v_unread_notifications integer := 0;
  v_unread_chat integer := 0;
  v_new_orders integer := 0;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object(
      'unread_notifications', 0,
      'unread_chat', 0,
      'new_orders', 0
    );
  END IF;

  SELECT role INTO v_role FROM public.profiles WHERE id = v_uid;

  -- System notifications unread
  SELECT count(*)::integer INTO v_unread_notifications
  FROM public.system_notifications
  WHERE user_id = v_uid AND is_read = false;

  -- Chat messages unread
  v_unread_chat := public.get_total_unread_chat_count();

  -- Station new orders unacknowledged
  IF v_role = 'owner' THEN
    v_new_orders := public.get_station_new_orders_count();
  ELSIF v_role = 'admin' OR public.is_admin() THEN
    SELECT count(*)::integer INTO v_new_orders
    FROM public.orders
    WHERE status = 'pending' AND admin_acknowledged_at IS NULL;
  END IF;

  RETURN jsonb_build_object(
    'unread_notifications', coalesce(v_unread_notifications, 0),
    'unread_chat', coalesce(v_unread_chat, 0),
    'new_orders', coalesce(v_new_orders, 0)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_user_notification_counts() TO authenticated, service_role;

-- 9. RPC: Register & Unregister Device Push Tokens
CREATE OR REPLACE FUNCTION public.register_device_push_token(
  p_token text,
  p_platform text,
  p_device_info text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
  END IF;

  IF p_token IS NULL OR trim(p_token) = '' THEN
    RETURN;
  END IF;

  INSERT INTO public.push_device_tokens (user_id, token, platform, device_info, is_active, updated_at)
  VALUES (v_uid, trim(p_token), lower(trim(p_platform)), p_device_info, true, now())
  ON CONFLICT (user_id, token) DO UPDATE
  SET is_active = true,
      platform = EXCLUDED.platform,
      device_info = coalesce(EXCLUDED.device_info, push_device_tokens.device_info),
      updated_at = now();
END;
$$;

CREATE OR REPLACE FUNCTION public.unregister_device_push_token(p_token text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN;
  END IF;

  UPDATE public.push_device_tokens
  SET is_active = false, updated_at = now()
  WHERE user_id = v_uid AND token = trim(p_token);
END;
$$;

GRANT EXECUTE ON FUNCTION public.register_device_push_token(text, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.unregister_device_push_token(text) TO authenticated, service_role;

-- 10. RPC: Hardened Account Deletion
CREATE OR REPLACE FUNCTION public.delete_user_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_email text;
  v_role text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
  END IF;

  SELECT email, role INTO v_email, v_role
  FROM public.profiles
  WHERE id = v_user_id;

  -- 1. Active delivery protection: Cannot delete account while active delivery is in transit
  IF EXISTS (
    SELECT 1 FROM public.orders
    WHERE (customer_id = v_user_id OR owner_id = v_user_id OR assigned_rider_id = v_user_id)
      AND status IN ('in_preparation', 'out_for_delivery')
  ) THEN
    RAISE EXCEPTION 'Cannot delete account while you have active deliveries in progress. Please wait for completion.'
      USING ERRCODE = '23503';
  END IF;

  -- 2. Cancel pending refill orders
  UPDATE public.orders
  SET status = 'cancelled', updated_at = now()
  WHERE customer_id = v_user_id AND status = 'pending';

  -- 3. Cleanup Historical Links to preserve records for the counterparty without constraint failure
  UPDATE public.orders SET customer_id = NULL WHERE customer_id = v_user_id;
  UPDATE public.orders SET owner_id = NULL WHERE owner_id = v_user_id;
  UPDATE public.orders SET assigned_rider_id = NULL WHERE assigned_rider_id = v_user_id;

  -- 4. Delete tokens, preferences, and notifications
  DELETE FROM public.push_device_tokens WHERE user_id = v_user_id;
  DELETE FROM public.user_notification_preferences WHERE user_id = v_user_id;
  DELETE FROM public.system_notifications WHERE user_id = v_user_id;
  DELETE FROM public.chat_participants WHERE user_id = v_user_id;
  DELETE FROM public.rider_locations WHERE rider_id = v_user_id;

  -- 5. Audit Log Entry
  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, old_value, metadata)
  VALUES (
    v_user_id,
    'USER_ACCOUNT_DELETION',
    'user',
    v_user_id::text,
    jsonb_build_object('email', v_email, 'role', v_role),
    jsonb_build_object('deleted_at', now(), 'source', 'settings_danger_zone')
  );

  -- 6. Wipe profile and auth record
  DELETE FROM public.profiles WHERE id = v_user_id;
  DELETE FROM auth.users WHERE id = v_user_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_user_account() TO authenticated, service_role;

-- 11. Trigger: Automatic Notifications on Order Creation (Owner & Customer)
CREATE OR REPLACE FUNCTION public.notify_order_created()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_short_id text;
  v_customer_label text;
BEGIN
  v_short_id := upper(substr(NEW.id::text, 1, 8));
  v_customer_label := coalesce(nullif(trim(NEW.customer_name), ''), 'A customer');

  -- A. Notify Station Owner of New Refill Order
  IF NEW.owner_id IS NOT NULL THEN
    INSERT INTO public.system_notifications (
      user_id,
      type,
      priority,
      title,
      content,
      action_url,
      metadata
    ) VALUES (
      NEW.owner_id,
      'system_alert',
      'urgent',
      'New Refill Order #' || v_short_id,
      v_customer_label || ' placed an order for ₱' || trim(to_char(NEW.total_amount, '999,999,990.00')) || '.',
      '/orders/' || NEW.id::text,
      jsonb_build_object(
        'order_id', NEW.id,
        'status', NEW.status,
        'total_amount', NEW.total_amount,
        'customer_name', NEW.customer_name,
        'event', 'new_order'
      )
    );
  END IF;

  -- B. Confirm Order Placement to Customer
  IF NEW.customer_id IS NOT NULL THEN
    INSERT INTO public.system_notifications (
      user_id,
      type,
      priority,
      title,
      content,
      action_url,
      metadata
    ) VALUES (
      NEW.customer_id,
      'system_alert',
      'high',
      'Order Placed #' || v_short_id,
      'Your water refill order with ' || coalesce(NEW.station_name, 'the station') || ' has been placed.',
      '/orders/' || NEW.id::text,
      jsonb_build_object(
        'order_id', NEW.id,
        'status', NEW.status,
        'station_name', NEW.station_name,
        'event', 'order_placed'
      )
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_order_created ON public.orders;
CREATE TRIGGER trg_notify_order_created
  AFTER INSERT ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.notify_order_created();

-- 12. Trigger: Automatic Notifications on Order Status Lifecycle Changes
CREATE OR REPLACE FUNCTION public.notify_order_status_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_short_id text;
  v_station text;
BEGIN
  -- Only trigger on status transition
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN
    RETURN NEW;
  END IF;

  v_short_id := upper(substr(NEW.id::text, 1, 8));
  v_station := coalesce(NEW.station_name, 'Water Station');

  -- If order status transitioned away from pending, ensure acknowledged_at is stamped
  IF OLD.status = 'pending' AND NEW.status != 'pending' THEN
    IF NEW.owner_acknowledged_at IS NULL THEN
      NEW.owner_acknowledged_at := now();
    END IF;
  END IF;

  -- Customer Lifecycle Notifications
  IF NEW.status = 'accepted' AND NEW.customer_id IS NOT NULL THEN
    INSERT INTO public.system_notifications (user_id, type, priority, title, content, action_url, metadata)
    VALUES (
      NEW.customer_id, 'system_alert', 'high', 'Order Accepted',
      v_station || ' accepted your refill order #' || v_short_id || '.',
      '/orders/' || NEW.id::text,
      jsonb_build_object('order_id', NEW.id, 'status', 'accepted')
    );
  ELSIF NEW.status = 'preparing' AND NEW.customer_id IS NOT NULL THEN
    INSERT INTO public.system_notifications (user_id, type, priority, title, content, action_url, metadata)
    VALUES (
      NEW.customer_id, 'system_alert', 'normal', 'Refill in Preparation',
      'Your containers for order #' || v_short_id || ' are currently being refilled.',
      '/orders/' || NEW.id::text,
      jsonb_build_object('order_id', NEW.id, 'status', 'preparing')
    );
  ELSIF NEW.status = 'ready_for_pickup' AND NEW.customer_id IS NOT NULL THEN
    INSERT INTO public.system_notifications (user_id, type, priority, title, content, action_url, metadata)
    VALUES (
      NEW.customer_id, 'system_alert', 'normal', 'Refill Ready',
      'Your refill order #' || v_short_id || ' is ready for rider dispatch.',
      '/orders/' || NEW.id::text,
      jsonb_build_object('order_id', NEW.id, 'status', 'ready_for_pickup')
    );
  ELSIF NEW.status = 'out_for_delivery' AND NEW.customer_id IS NOT NULL THEN
    INSERT INTO public.system_notifications (user_id, type, priority, title, content, action_url, metadata)
    VALUES (
      NEW.customer_id, 'system_alert', 'high', 'Out for Delivery',
      'Your rider is heading to your delivery address with order #' || v_short_id || '.',
      '/orders/' || NEW.id::text,
      jsonb_build_object('order_id', NEW.id, 'status', 'out_for_delivery')
    );
  ELSIF NEW.status = 'delivered' THEN
    IF NEW.customer_id IS NOT NULL THEN
      INSERT INTO public.system_notifications (user_id, type, priority, title, content, action_url, metadata)
      VALUES (
        NEW.customer_id, 'system_alert', 'high', 'Delivery Completed',
        'Order #' || v_short_id || ' has been delivered. Thank you for choosing ' || v_station || '!',
        '/orders/' || NEW.id::text,
        jsonb_build_object('order_id', NEW.id, 'status', 'delivered')
      );
    END IF;
    IF NEW.owner_id IS NOT NULL THEN
      INSERT INTO public.system_notifications (user_id, type, priority, title, content, action_url, metadata)
      VALUES (
        NEW.owner_id, 'system_alert', 'normal', 'Order Delivered #' || v_short_id,
        'Refill delivery for #' || v_short_id || ' was successfully completed.',
        '/orders/' || NEW.id::text,
        jsonb_build_object('order_id', NEW.id, 'status', 'delivered')
      );
    END IF;
  ELSIF NEW.status = 'cancelled' THEN
    IF NEW.customer_id IS NOT NULL THEN
      INSERT INTO public.system_notifications (user_id, type, priority, title, content, action_url, metadata)
      VALUES (
        NEW.customer_id, 'order_cancelled', 'urgent', 'Order Cancelled #' || v_short_id,
        'Refill order #' || v_short_id || ' was cancelled.',
        '/orders/' || NEW.id::text,
        jsonb_build_object('order_id', NEW.id, 'status', 'cancelled')
      );
    END IF;
    IF NEW.owner_id IS NOT NULL THEN
      INSERT INTO public.system_notifications (user_id, type, priority, title, content, action_url, metadata)
      VALUES (
        NEW.owner_id, 'order_cancelled', 'high', 'Order Cancelled #' || v_short_id,
        'Order #' || v_short_id || ' was marked as cancelled.',
        '/orders/' || NEW.id::text,
        jsonb_build_object('order_id', NEW.id, 'status', 'cancelled')
      );
    END IF;
  END IF;

  -- Rider Assignment Notification
  IF (OLD.assigned_rider_id IS DISTINCT FROM NEW.assigned_rider_id) AND NEW.assigned_rider_id IS NOT NULL THEN
    INSERT INTO public.system_notifications (user_id, type, priority, title, content, action_url, metadata)
    VALUES (
      NEW.assigned_rider_id, 'order_assigned', 'urgent', 'New Delivery Assigned',
      'You have been assigned to deliver order #' || v_short_id || '.',
      '/orders/' || NEW.id::text,
      jsonb_build_object('order_id', NEW.id, 'status', NEW.status)
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_order_status_change ON public.orders;
CREATE TRIGGER trg_notify_order_status_change
  BEFORE UPDATE OF status, assigned_rider_id ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.notify_order_status_change();

-- 13. Ensure Realtime Publication includes orders and messages
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'orders'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.orders;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'system_notifications'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.system_notifications;
  END IF;
END $$;

