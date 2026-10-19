-- Rollback for security_hardening_rls_and_rpc_guards.sql
-- Restores the previous (insecure) state exactly. Only run this if the
-- hardening script broke a workflow and you need time to fix it.

BEGIN;

-- 3. Remove guard wrappers and restore the original functions + grants.
DROP FUNCTION IF EXISTS public.create_rider_account(text, text, text, text, uuid);
DROP FUNCTION IF EXISTS public.broadcast_to_riders(uuid, text, text, notification_type, notification_priority);
DROP FUNCTION IF EXISTS public.create_support_chat_room(uuid, uuid, text);
DROP FUNCTION IF EXISTS public.get_or_create_customer_owner_chat_room(uuid, uuid, uuid, text, text);
DROP FUNCTION IF EXISTS public.get_or_create_customer_rider_chat_room(uuid, uuid, uuid, text, text);
DROP FUNCTION IF EXISTS public.get_or_create_owner_rider_chat_room(uuid, uuid, uuid, text, text);
DROP FUNCTION IF EXISTS public.get_unread_notification_count(uuid);
DROP FUNCTION IF EXISTS public.mark_messages_as_read(uuid, uuid);
DROP FUNCTION IF EXISTS public.check_station_setup_status(uuid);
DROP FUNCTION IF EXISTS public.seed_station_standard_products(uuid);

ALTER FUNCTION public.create_rider_account_unguarded(text, text, text, text, uuid) RENAME TO create_rider_account;
ALTER FUNCTION public.broadcast_to_riders_unguarded(uuid, text, text, notification_type, notification_priority) RENAME TO broadcast_to_riders;
ALTER FUNCTION public.create_support_chat_room_unguarded(uuid, uuid, text) RENAME TO create_support_chat_room;
ALTER FUNCTION public.get_or_create_customer_owner_chat_room_unguarded(uuid, uuid, uuid, text, text) RENAME TO get_or_create_customer_owner_chat_room;
ALTER FUNCTION public.get_or_create_customer_rider_chat_room_unguarded(uuid, uuid, uuid, text, text) RENAME TO get_or_create_customer_rider_chat_room;
ALTER FUNCTION public.get_or_create_owner_rider_chat_room_unguarded(uuid, uuid, uuid, text, text) RENAME TO get_or_create_owner_rider_chat_room;
ALTER FUNCTION public.get_unread_notification_count_unguarded(uuid) RENAME TO get_unread_notification_count;
ALTER FUNCTION public.mark_messages_as_read_unguarded(uuid, uuid) RENAME TO mark_messages_as_read;
ALTER FUNCTION public.check_station_setup_status_unguarded(uuid) RENAME TO check_station_setup_status;
ALTER FUNCTION public.seed_station_standard_products_unguarded(uuid) RENAME TO seed_station_standard_products;

GRANT EXECUTE ON FUNCTION public.create_rider_account(text, text, text, text, uuid) TO PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.broadcast_to_riders(uuid, text, text, notification_type, notification_priority) TO PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_support_chat_room(uuid, uuid, text) TO PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_or_create_customer_owner_chat_room(uuid, uuid, uuid, text, text) TO PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_or_create_customer_rider_chat_room(uuid, uuid, uuid, text, text) TO PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_or_create_owner_rider_chat_room(uuid, uuid, uuid, text, text) TO PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_unread_notification_count(uuid) TO PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_messages_as_read(uuid, uuid) TO PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_station_setup_status(uuid) TO PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.seed_station_standard_products(uuid) TO PUBLIC, anon, authenticated;

DROP FUNCTION IF EXISTS public._require(boolean);

-- 2. Restore client EXECUTE on internal functions.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
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
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO PUBLIC, anon, authenticated', r.sig);
  END LOOP;
END
$$;

-- 1. Drop new policies and disable RLS again.
ALTER FUNCTION public.proc_log_dispute_event() SECURITY INVOKER;
ALTER FUNCTION public.proc_log_dispute_event() RESET search_path;

DROP POLICY IF EXISTS "Order parties can view order items" ON public.order_items;
DROP POLICY IF EXISTS "Customers add items to own pending order" ON public.order_items;
DROP POLICY IF EXISTS "Users log own domain events" ON public.domain_events;
DROP POLICY IF EXISTS "Users read own domain events" ON public.domain_events;
DROP POLICY IF EXISTS "Admins read ledger entries" ON public.ledger_entries;
DROP POLICY IF EXISTS "Admins read operational metrics" ON public.operational_metrics;
DROP POLICY IF EXISTS "Admins read rate limit events" ON public.rate_limit_events;
DROP POLICY IF EXISTS "Admins read suspicious activities" ON public.suspicious_activities;
DROP POLICY IF EXISTS "Signed-in users read regions" ON public.regions;
DROP POLICY IF EXISTS "Admins read remittances" ON public.remittances;

ALTER TABLE public.order_items           DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.domain_events         DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.ledger_entries        DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.operational_metrics   DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.rate_limit_events     DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.regions               DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.remittances           DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.suspicious_activities DISABLE ROW LEVEL SECURITY;

NOTIFY pgrst, 'reload schema';

COMMIT;
