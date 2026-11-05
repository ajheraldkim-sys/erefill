-- ==============================================================================
-- Station accessories (2026-11-05)
-- ==============================================================================
-- Stations keep exactly one water product (single_water_product_catalog.sql)
-- and may now also sell accessories: empty gallons, caps, seals, dispensers…
--
--   products.kind = 'water' | 'accessory'
--   * one 'water' row per station (partial unique index)
--   * owners may insert / edit / delete their own 'accessory' rows
--   * the water row keeps today's rules (owners change price/availability only)
--   * price mirroring to owner_settings/profiles only follows the water row
-- Stock: existing order_items/orders triggers (handle_inventory_deduction,
-- proc_restore_inventory_on_cancellation) already deduct and restore
-- stock_level for every product, accessories included.
--
-- Rollback: station_accessories_rollback.sql
-- Test: supabase/tests/accessories_test.sql
-- ==============================================================================
BEGIN;

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS kind text NOT NULL DEFAULT 'water';
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_kind_check;
ALTER TABLE public.products ADD CONSTRAINT products_kind_check
  CHECK (kind IN ('water', 'accessory'));
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_accessory_category_check;
ALTER TABLE public.products ADD CONSTRAINT products_accessory_category_check
  CHECK (kind = 'water' OR category IN ('gallon', 'cap', 'seal', 'dispenser', 'other'));
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_accessory_water_type_check;
ALTER TABLE public.products ADD CONSTRAINT products_accessory_water_type_check
  CHECK (kind = 'water' OR water_type IS NULL);

DROP INDEX IF EXISTS public.products_one_per_station;
CREATE UNIQUE INDEX IF NOT EXISTS products_one_water_per_station
  ON public.products (owner_id) WHERE kind = 'water';

-- Water row lookup must ignore accessories.
CREATE OR REPLACE FUNCTION public.ensure_station_product(p_owner_id uuid)
RETURNS public.products
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_type public.water_types%ROWTYPE;
  v_price numeric(10,2);
  v_row public.products%ROWTYPE;
BEGIN
  SELECT wt.* INTO v_type
  FROM public.profiles p
  JOIN public.water_types wt ON wt.name = p.primary_water_type
  WHERE p.id = p_owner_id AND p.role = 'owner';
  IF v_type.id IS NULL THEN RETURN NULL; END IF;

  SELECT * INTO v_row FROM public.products
  WHERE owner_id = p_owner_id AND kind = 'water' FOR UPDATE;

  IF v_row.id IS NOT NULL THEN
    UPDATE public.products
    SET name = v_type.name,
        category = v_type.short_name,
        description = v_type.description,
        water_type = v_type.name
    WHERE id = v_row.id
      AND (name, category, description, water_type)
          IS DISTINCT FROM (v_type.name, v_type.short_name, v_type.description, v_type.name)
    RETURNING * INTO v_row;
    IF NOT FOUND THEN
      SELECT * INTO v_row FROM public.products
      WHERE owner_id = p_owner_id AND kind = 'water';
    END IF;
    RETURN v_row;
  END IF;

  SELECT COALESCE(
    NULLIF((SELECT price_per_gallon FROM public.owner_settings WHERE owner_id = p_owner_id), 0),
    NULLIF((SELECT price_per_gallon FROM public.profiles WHERE id = p_owner_id), 0),
    25
  ) INTO v_price;

  INSERT INTO public.products (owner_id, name, description, price, category, water_type, is_available, kind)
  VALUES (p_owner_id, v_type.name, v_type.description, v_price, v_type.short_name, v_type.name, true, 'water')
  RETURNING * INTO v_row;
  RETURN v_row;
END; $$;

CREATE OR REPLACE FUNCTION public.guard_station_product_update()
RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  IF current_user IN ('authenticated', 'anon') AND NOT public.is_admin() THEN
    IF NEW.owner_id IS DISTINCT FROM OLD.owner_id
       OR NEW.kind IS DISTINCT FROM OLD.kind THEN
      RAISE EXCEPTION 'Products cannot be moved between stations or kinds.';
    END IF;
    IF OLD.kind = 'water' AND (
         NEW.name IS DISTINCT FROM OLD.name
         OR NEW.category IS DISTINCT FROM OLD.category
         OR NEW.description IS DISTINCT FROM OLD.description
         OR NEW.water_type IS DISTINCT FROM OLD.water_type) THEN
      RAISE EXCEPTION 'Stations can only change the price and availability of their water.';
    END IF;
    IF NEW.price IS NULL OR NEW.price <= 0 THEN
      RAISE EXCEPTION 'Price must be greater than zero.';
    END IF;
  END IF;
  RETURN NEW;
END; $$;

CREATE OR REPLACE FUNCTION public.trigger_mirror_station_product_price()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NEW.kind IS DISTINCT FROM 'water' THEN
    RETURN NEW;
  END IF;
  UPDATE public.owner_settings SET price_per_gallon = NEW.price
  WHERE owner_id = NEW.owner_id AND price_per_gallon IS DISTINCT FROM NEW.price::double precision;
  UPDATE public.profiles SET price_per_gallon = NEW.price
  WHERE id = NEW.owner_id AND price_per_gallon IS DISTINCT FROM NEW.price;
  RETURN NEW;
END; $$;

-- Owners manage their own accessories (water rows stay update-only).
DROP POLICY IF EXISTS "Owners can add own accessories" ON public.products;
CREATE POLICY "Owners can add own accessories" ON public.products
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = owner_id
    AND kind = 'accessory'
    AND EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'owner')
  );

DROP POLICY IF EXISTS "Owners can delete own accessories" ON public.products;
CREATE POLICY "Owners can delete own accessories" ON public.products
  FOR DELETE TO authenticated
  USING (auth.uid() = owner_id AND kind = 'accessory');

COMMIT;

NOTIFY pgrst, 'reload schema';
