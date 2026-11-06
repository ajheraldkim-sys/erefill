-- Rollback for station_accessories.sql. Deletes accessory rows (order history
-- keeps product_name / price_at_purchase in order_items), then restores the
-- one-product-per-station index. Re-run single_water_product_catalog.sql
-- sections 3-5 afterwards to restore the original function bodies.
BEGIN;

DROP POLICY IF EXISTS "Owners can add own accessories" ON public.products;
DROP POLICY IF EXISTS "Owners can delete own accessories" ON public.products;

DELETE FROM public.products WHERE kind = 'accessory';

DROP INDEX IF EXISTS public.products_one_water_per_station;
CREATE UNIQUE INDEX IF NOT EXISTS products_one_per_station ON public.products (owner_id);

ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_accessory_water_type_check;
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_accessory_category_check;
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_kind_check;
ALTER TABLE public.products DROP COLUMN IF EXISTS kind;

COMMIT;

NOTIFY pgrst, 'reload schema';
