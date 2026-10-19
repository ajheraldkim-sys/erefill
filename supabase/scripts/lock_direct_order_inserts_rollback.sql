-- Rollback for lock_direct_order_inserts.sql: restores the three policies
-- exactly as they were before phase 2.

BEGIN;

DROP POLICY IF EXISTS "Customers can create orders" ON public.orders;
CREATE POLICY "Customers can create orders" ON public.orders
  FOR INSERT TO public WITH CHECK (auth.uid() = customer_id);

DROP POLICY IF EXISTS "Users can create their own orders" ON public.orders;
CREATE POLICY "Users can create their own orders" ON public.orders
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = customer_id);

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

NOTIFY pgrst, 'reload schema';

COMMIT;
