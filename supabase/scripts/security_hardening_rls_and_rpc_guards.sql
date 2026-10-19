-- =============================================================================
-- Security hardening: RLS on exposed tables + authorization guards on RPCs
-- =============================================================================
-- Why: the anon key ships inside the Flutter app, so anything granted to the
-- `anon` / `authenticated` roles is reachable by anyone who installs the APK.
-- Supabase's security advisor reported (2026-10-19):
--   * 8 public tables with RLS disabled (full read/write/delete for anon),
--     including order_items (prices), ledger_entries and remittances (PII/cash).
--   * SECURITY DEFINER functions executable by anon with no caller check, e.g.
--     create_rider_account (can reset ANY user's password by email),
--     _admin_cleanup_user_links (detaches a user's orders), send_system_message.
--
-- Approach (non-destructive, no data is modified):
--   1. Enable RLS on the 8 tables and add policies matching current app usage.
--   2. Revoke client EXECUTE on definer functions that no client calls
--      (they keep working when called from triggers, cron or other definer
--      functions, which run as `postgres`).
--   3. For definer functions the apps DO call, rename the original to
--      `<name>_unguarded`, revoke client access to it, and put a wrapper with
--      the identical signature in front that checks auth.uid() first.
--
-- Rollback: supabase/scripts/security_hardening_rls_and_rpc_guards_rollback.sql
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Row Level Security on previously unprotected tables
-- -----------------------------------------------------------------------------

ALTER TABLE public.order_items           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.domain_events         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ledger_entries        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.operational_metrics   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rate_limit_events     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.regions               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.remittances           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suspicious_activities ENABLE ROW LEVEL SECURITY;

-- order_items: visible to the parties of the parent order, mirroring the
-- existing policies on public.orders. No client UPDATE/DELETE policy:
-- purchase prices are immutable from the app.
DROP POLICY IF EXISTS "Order parties can view order items" ON public.order_items;
CREATE POLICY "Order parties can view order items" ON public.order_items
  FOR SELECT TO authenticated
  USING (
    public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = order_items.order_id
        AND auth.uid() IN (o.customer_id, o.owner_id, o.assigned_rider_id, o.rider_id)
    )
  );

-- TRANSITIONAL: app versions released before generate_due_subscription_orders
-- insert auto-refill orders and their items directly (as the customer or the
-- station owner). Allow item inserts only onto a pending order the caller is
-- a party to, created in the last 10 minutes. Removed by
-- lock_direct_order_inserts.sql once the new app version is mandatory.
DROP POLICY IF EXISTS "Transitional: parties add items to new pending order" ON public.order_items;
CREATE POLICY "Transitional: parties add items to new pending order" ON public.order_items
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = order_items.order_id
        AND auth.uid() IN (o.customer_id, o.owner_id)
        AND o.status = 'pending'
        AND o.created_at > now() - interval '10 minutes'
    )
  );

-- domain_events: the app logs events as the signed-in user and owners read
-- back their own DELIVERY_SYNC_FAILED events. Admins can read everything.
DROP POLICY IF EXISTS "Users log own domain events" ON public.domain_events;
CREATE POLICY "Users log own domain events" ON public.domain_events
  FOR INSERT TO authenticated
  WITH CHECK (actor_id = auth.uid());

DROP POLICY IF EXISTS "Users read own domain events" ON public.domain_events;
CREATE POLICY "Users read own domain events" ON public.domain_events
  FOR SELECT TO authenticated
  USING (actor_id = auth.uid() OR public.is_admin());

-- The dispute trigger inserts on behalf of the reporter; run it as definer so
-- it is not subject to the policy above (e.g. disputes filed by an admin).
ALTER FUNCTION public.proc_log_dispute_event() SECURITY DEFINER;
ALTER FUNCTION public.proc_log_dispute_event() SET search_path = public;

-- Internal/analytics tables: admin read-only from clients; server-side
-- definer functions and cron keep full access.
DROP POLICY IF EXISTS "Admins read ledger entries" ON public.ledger_entries;
CREATE POLICY "Admins read ledger entries" ON public.ledger_entries
  FOR SELECT TO authenticated USING (public.is_admin());

DROP POLICY IF EXISTS "Admins read operational metrics" ON public.operational_metrics;
CREATE POLICY "Admins read operational metrics" ON public.operational_metrics
  FOR SELECT TO authenticated USING (public.is_admin());

DROP POLICY IF EXISTS "Admins read rate limit events" ON public.rate_limit_events;
CREATE POLICY "Admins read rate limit events" ON public.rate_limit_events
  FOR SELECT TO authenticated USING (public.is_admin());

DROP POLICY IF EXISTS "Admins read suspicious activities" ON public.suspicious_activities;
CREATE POLICY "Admins read suspicious activities" ON public.suspicious_activities
  FOR SELECT TO authenticated USING (public.is_admin());

-- regions is reference data (names, base fees); signed-in users may read it,
-- only admins (via admin_* RPCs) change it.
DROP POLICY IF EXISTS "Signed-in users read regions" ON public.regions;
CREATE POLICY "Signed-in users read regions" ON public.regions
  FOR SELECT TO authenticated USING (true);

-- remittances already had owner SELECT/UPDATE policies that were inert while
-- RLS was off; enabling RLS above activates them. Add admin read.
DROP POLICY IF EXISTS "Admins read remittances" ON public.remittances;
CREATE POLICY "Admins read remittances" ON public.remittances
  FOR SELECT TO authenticated USING (public.is_admin());

-- -----------------------------------------------------------------------------
-- 2. Revoke client EXECUTE on internal-only SECURITY DEFINER functions
-- -----------------------------------------------------------------------------
-- None of these is called by lib/, admin/lib/ or supabase/functions/, and none
-- is referenced by an RLS policy or view. Callers that remain valid:
--   admin_delete_user -> _admin_cleanup_user_links
--   admin_dashboard_stats -> admin_failed_payments_count
--   check_app_version_compatibility -> get_active_app_version_policy
--   cron_nightly_ops_refined -> run_integrity_watchdog
-- (all run as postgres). The room-membership helpers used inside chat RLS
-- policies (is_room_owner, is_room_participant, sec_def_*) are left untouched.
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        '_admin_cleanup_user_links', 'admin_failed_payments_count',
        'check_app_compatibility', 'cleanup_old_notifications',
        'create_order_chat_room', 'get_active_app_version_policy',
        'get_digital_receipt_data', 'get_dispatch_recommendation',
        'get_order_batch_suggestions', 'get_peak_hour_stats',
        'get_unread_count', 'mark_message_delivered', 'mark_room_as_seen',
        'process_due_customer_subscriptions', 'run_integrity_watchdog',
        'send_system_message', 'smart_dispatch_rider',
        'smart_dispatch_rider_regional'
      )
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated', r.sig);
  END LOOP;
END
$$;

-- -----------------------------------------------------------------------------
-- 3. Guard wrappers for client-called SECURITY DEFINER functions
-- -----------------------------------------------------------------------------

-- Helper: raise a uniform authorization error.
CREATE OR REPLACE FUNCTION public._require(p_allowed boolean)
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT coalesce(p_allowed, false) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
  END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION public._require(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._require(boolean) TO authenticated;

-- Rename originals out of the way and lock them down.
ALTER FUNCTION public.create_rider_account(text, text, text, text, uuid)
  RENAME TO create_rider_account_unguarded;
ALTER FUNCTION public.broadcast_to_riders(uuid, text, text, notification_type, notification_priority)
  RENAME TO broadcast_to_riders_unguarded;
ALTER FUNCTION public.create_support_chat_room(uuid, uuid, text)
  RENAME TO create_support_chat_room_unguarded;
ALTER FUNCTION public.get_or_create_customer_owner_chat_room(uuid, uuid, uuid, text, text)
  RENAME TO get_or_create_customer_owner_chat_room_unguarded;
ALTER FUNCTION public.get_or_create_customer_rider_chat_room(uuid, uuid, uuid, text, text)
  RENAME TO get_or_create_customer_rider_chat_room_unguarded;
ALTER FUNCTION public.get_or_create_owner_rider_chat_room(uuid, uuid, uuid, text, text)
  RENAME TO get_or_create_owner_rider_chat_room_unguarded;
ALTER FUNCTION public.get_unread_notification_count(uuid)
  RENAME TO get_unread_notification_count_unguarded;
ALTER FUNCTION public.mark_messages_as_read(uuid, uuid)
  RENAME TO mark_messages_as_read_unguarded;
ALTER FUNCTION public.check_station_setup_status(uuid)
  RENAME TO check_station_setup_status_unguarded;
ALTER FUNCTION public.seed_station_standard_products(uuid)
  RENAME TO seed_station_standard_products_unguarded;

REVOKE EXECUTE ON FUNCTION public.create_rider_account_unguarded(text, text, text, text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.broadcast_to_riders_unguarded(uuid, text, text, notification_type, notification_priority) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.create_support_chat_room_unguarded(uuid, uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_or_create_customer_owner_chat_room_unguarded(uuid, uuid, uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_or_create_customer_rider_chat_room_unguarded(uuid, uuid, uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_or_create_owner_rider_chat_room_unguarded(uuid, uuid, uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_unread_notification_count_unguarded(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.mark_messages_as_read_unguarded(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.check_station_setup_status_unguarded(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.seed_station_standard_products_unguarded(uuid) FROM PUBLIC, anon, authenticated;

-- create_rider_account: only the owner themself (or an admin) may create a
-- rider for a station, and an existing account may only be (re)linked when it
-- is already an unlinked rider or a rider of this same station. Previously
-- anyone could pass an admin's or customer's email and overwrite its role and
-- password.
CREATE FUNCTION public.create_rider_account(
  p_email text, p_password text, p_username text, p_full_name text, p_owner_id uuid
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions
AS $$
DECLARE
  v_existing_id uuid;
  v_existing_role text;
  v_existing_owner uuid;
BEGIN
  PERFORM public._require(
    public.is_admin()
    OR (
      auth.uid() = p_owner_id
      AND EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role::text = 'owner')
    )
  );

  SELECT id INTO v_existing_id FROM auth.users WHERE lower(email) = lower(trim(p_email));
  IF v_existing_id IS NOT NULL THEN
    SELECT role::text, owner_id INTO v_existing_role, v_existing_owner
    FROM public.profiles WHERE id = v_existing_id;

    IF v_existing_role IS NOT NULL
       AND NOT (v_existing_role = 'rider' AND (v_existing_owner IS NULL OR v_existing_owner = p_owner_id))
    THEN
      RETURN 'error: email_already_exists';
    END IF;
  END IF;

  RETURN public.create_rider_account_unguarded(p_email, p_password, p_username, p_full_name, p_owner_id);
END;
$$;

CREATE FUNCTION public.broadcast_to_riders(
  p_owner_id uuid, p_title text, p_content text,
  p_type notification_type DEFAULT 'station_broadcast'::notification_type,
  p_priority notification_priority DEFAULT 'normal'::notification_priority
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public._require(auth.uid() = p_owner_id OR public.is_admin());
  RETURN public.broadcast_to_riders_unguarded(p_owner_id, p_title, p_content, p_type, p_priority);
END;
$$;

CREATE FUNCTION public.create_support_chat_room(
  p_customer_id uuid, p_owner_id uuid, p_title text DEFAULT 'Customer Support'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public._require(auth.uid() IN (p_customer_id, p_owner_id) OR public.is_admin());
  RETURN public.create_support_chat_room_unguarded(p_customer_id, p_owner_id, p_title);
END;
$$;

CREATE FUNCTION public.get_or_create_customer_owner_chat_room(
  p_order_id uuid, p_customer_id uuid, p_owner_id uuid,
  p_station_name text DEFAULT NULL::text, p_customer_name text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public._require(auth.uid() IN (p_customer_id, p_owner_id) OR public.is_admin());
  RETURN public.get_or_create_customer_owner_chat_room_unguarded(
    p_order_id, p_customer_id, p_owner_id, p_station_name, p_customer_name);
END;
$$;

-- The station owner may also open the customer<->rider thread for an order
-- they own (dispatch flow), in addition to the two participants.
CREATE FUNCTION public.get_or_create_customer_rider_chat_room(
  p_order_id uuid, p_customer_id uuid, p_rider_id uuid,
  p_customer_name text DEFAULT NULL::text, p_rider_name text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public._require(
    auth.uid() IN (p_customer_id, p_rider_id)
    OR public.is_admin()
    OR EXISTS (SELECT 1 FROM public.orders o WHERE o.id = p_order_id AND o.owner_id = auth.uid())
  );
  RETURN public.get_or_create_customer_rider_chat_room_unguarded(
    p_order_id, p_customer_id, p_rider_id, p_customer_name, p_rider_name);
END;
$$;

CREATE FUNCTION public.get_or_create_owner_rider_chat_room(
  p_order_id uuid, p_owner_id uuid, p_rider_id uuid,
  p_station_name text DEFAULT NULL::text, p_rider_name text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public._require(auth.uid() IN (p_owner_id, p_rider_id) OR public.is_admin());
  RETURN public.get_or_create_owner_rider_chat_room_unguarded(
    p_order_id, p_owner_id, p_rider_id, p_station_name, p_rider_name);
END;
$$;

CREATE FUNCTION public.get_unread_notification_count(p_user_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public._require(auth.uid() = p_user_id);
  RETURN public.get_unread_notification_count_unguarded(p_user_id);
END;
$$;

CREATE FUNCTION public.mark_messages_as_read(p_room_id uuid, p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public._require(auth.uid() = p_user_id);
  PERFORM public.mark_messages_as_read_unguarded(p_room_id, p_user_id);
END;
$$;

CREATE FUNCTION public.check_station_setup_status(p_owner_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public._require(auth.uid() = p_owner_id OR public.is_admin());
  RETURN public.check_station_setup_status_unguarded(p_owner_id);
END;
$$;

CREATE FUNCTION public.seed_station_standard_products(p_owner_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public._require(auth.uid() = p_owner_id OR public.is_admin());
  PERFORM public.seed_station_standard_products_unguarded(p_owner_id);
END;
$$;

-- Wrappers: signed-in users only.
REVOKE EXECUTE ON FUNCTION public.create_rider_account(text, text, text, text, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.broadcast_to_riders(uuid, text, text, notification_type, notification_priority) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.create_support_chat_room(uuid, uuid, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_or_create_customer_owner_chat_room(uuid, uuid, uuid, text, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_or_create_customer_rider_chat_room(uuid, uuid, uuid, text, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_or_create_owner_rider_chat_room(uuid, uuid, uuid, text, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_unread_notification_count(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.mark_messages_as_read(uuid, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.check_station_setup_status(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.seed_station_standard_products(uuid) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.create_rider_account(text, text, text, text, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.broadcast_to_riders(uuid, text, text, notification_type, notification_priority) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.create_support_chat_room(uuid, uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_or_create_customer_owner_chat_room(uuid, uuid, uuid, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_or_create_customer_rider_chat_room(uuid, uuid, uuid, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_or_create_owner_rider_chat_room(uuid, uuid, uuid, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_unread_notification_count(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.mark_messages_as_read(uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.check_station_setup_status(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.seed_station_standard_products(uuid) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

COMMIT;
