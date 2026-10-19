-- Rollback for subscription_orders_server_pricing.sql
-- Orders already generated are kept. The product_id column is kept too
-- (dropping it would discard the backfilled links); it is harmless to older
-- app versions, which never read it.

BEGIN;

DROP FUNCTION IF EXISTS public.generate_due_subscription_orders(uuid, uuid);
DROP TRIGGER IF EXISTS trg_subscription_pricing ON public.customer_subscriptions;
DROP FUNCTION IF EXISTS public.proc_subscription_pricing();
DROP FUNCTION IF EXISTS public._resolve_subscription_product(uuid, text, numeric, integer);

-- To remove the column as well (loses the product links), run separately:
--   ALTER TABLE public.customer_subscriptions DROP COLUMN product_id;

NOTIFY pgrst, 'reload schema';

COMMIT;
