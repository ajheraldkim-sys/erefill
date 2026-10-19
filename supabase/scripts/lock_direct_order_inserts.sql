-- =============================================================================
-- Phase 2: customers can no longer INSERT orders / order_items directly
-- =============================================================================
-- Why: these policies only check customer_id = auth.uid(), and no INSERT
-- trigger validates prices, so a customer could create an order with any
-- total_amount, bypassing create_order_atomic's server-side pricing.
--
-- Apply ONLY after all of the following:
--   1. security_hardening_rls_and_rpc_guards.sql is applied.
--   2. subscription_orders_server_pricing.sql is applied.
--   3. The app version that calls generate_due_subscription_orders is
--      released AND set as the minimum required version (App Releases screen),
--      so no installed app still inserts auto-refill orders directly.
--
-- Unaffected: checkout and offline queue (create_order_atomic, definer),
-- auto-refill (generate_due_subscription_orders, definer), and owner walk-in
-- orders (policy "Owners manage station orders").
--
-- Rollback: lock_direct_order_inserts_rollback.sql
-- =============================================================================

BEGIN;

DROP POLICY IF EXISTS "Customers can create orders" ON public.orders;
DROP POLICY IF EXISTS "Users can create their own orders" ON public.orders;
DROP POLICY IF EXISTS "Transitional: parties add items to new pending order" ON public.order_items;

NOTIFY pgrst, 'reload schema';

COMMIT;
