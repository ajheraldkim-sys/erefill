-- Migration: Order acknowledgment, badge counts, and push device tokens
--
-- Corrected replacement for realtime_notifications_and_security.sql, which
-- was never applied. Checked against the live schema (2026-10-23):
-- * Its notify_order_created / notify_order_status_change triggers are left
--   out: create_order_atomic, transition_order_status_safely, and
--   assign_rider_safely already send those notifications, so the triggers
--   would have duplicated every one of them.
-- * Its delete_user_account replacement is left out: the deployed version
--   stays, and the replacement checked an 'in_preparation' status that the
--   order_status enum does not have.
-- * The realtime publication already includes orders, messages, and
--   system_notifications.

BEGIN;

-- 1. Owner and admin acknowledgment of new orders ---------------------------
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS owner_acknowledged_at timestamptz DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS admin_acknowledged_at timestamptz DEFAULT NULL;

CREATE INDEX IF NOT EXISTS idx_orders_owner_unacknowledged
  ON public.orders (owner_id, created_at DESC)
  WHERE (status = 'pending' AND owner_acknowledged_at IS NULL);

-- An order the station has acted on counts as acknowledged.
CREATE OR REPLACE FUNCTION public.stamp_order_acknowledged()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF OLD.status = 'pending' AND NEW.status <> 'pending'
     AND NEW.owner_acknowledged_at IS NULL THEN
    NEW.owner_acknowledged_at := now();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_stamp_order_acknowledged ON public.orders;
CREATE TRIGGER trg_stamp_order_acknowledged
  BEFORE UPDATE OF status ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.stamp_order_acknowledged();

-- 2. Push device tokens -----------------------------------------------------
CREATE TABLE IF NOT EXISTS public.push_device_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token text NOT NULL,
  platform text NOT NULL CHECK (platform IN ('android', 'ios', 'web', 'other')),
  device_info text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, token)
);

CREATE INDEX IF NOT EXISTS idx_push_device_tokens_user
  ON public.push_device_tokens (user_id)
  WHERE is_active = true;

ALTER TABLE public.push_device_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own device tokens" ON public.push_device_tokens;
CREATE POLICY "Users can view own device tokens"
  ON public.push_device_tokens FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can insert own device tokens" ON public.push_device_tokens;
CREATE POLICY "Users can insert own device tokens"
  ON public.push_device_tokens FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can update own device tokens" ON public.push_device_tokens;
CREATE POLICY "Users can update own device tokens"
  ON public.push_device_tokens FOR UPDATE TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can delete own device tokens" ON public.push_device_tokens;
CREATE POLICY "Users can delete own device tokens"
  ON public.push_device_tokens FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- 3. Notification delivery logs ---------------------------------------------
CREATE TABLE IF NOT EXISTS public.notification_delivery_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  notification_id uuid REFERENCES public.system_notifications(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  channel text NOT NULL CHECK (channel IN ('in_app', 'push', 'email', 'sms')),
  recipient_target text NOT NULL,
  event_id text,
  status text NOT NULL DEFAULT 'queued'
    CHECK (status IN ('queued', 'sent', 'delivered', 'failed', 'bounced')),
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
  ON public.notification_delivery_logs FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

-- 4. Notification preferences -----------------------------------------------
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
  ON public.user_notification_preferences FOR ALL TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- 5. RPC: acknowledge an order ----------------------------------------------
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

-- 6. RPC: unacknowledged new orders for the signed-in station ---------------
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

-- 7. RPC: unread chat messages across the user's rooms ----------------------
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

-- 8. RPC: all badge counts in one call --------------------------------------
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
    RETURN jsonb_build_object('unread_notifications', 0, 'unread_chat', 0, 'new_orders', 0);
  END IF;

  SELECT role INTO v_role FROM public.profiles WHERE id = v_uid;

  SELECT count(*)::integer INTO v_unread_notifications
  FROM public.system_notifications
  WHERE user_id = v_uid AND is_read = false;

  v_unread_chat := public.get_total_unread_chat_count();

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

-- 9. RPC: register and unregister push tokens -------------------------------
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

COMMIT;

NOTIFY pgrst, 'reload schema';
