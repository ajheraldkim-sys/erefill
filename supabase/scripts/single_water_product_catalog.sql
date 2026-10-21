-- Migration: Admin-managed water types, one refill product per station
--
-- * water_types is the catalog. Only admins create, update, or delete rows;
--   everyone (including signed-out visitors on the registration screen) can
--   read them.
-- * profiles.primary_water_type (picked at owner registration) references
--   water_types(name). Owners cannot change it; admins can.
-- * Every station has exactly one product: the refill of its water type.
--   Containers, caps, and other accessories are removed.
-- * Owners can only change that product's price, availability, and stock
--   fields. products.price is the source of truth and is mirrored into
--   owner_settings.price_per_gallon and profiles.price_per_gallon.

BEGIN;

-- 1. Catalog ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.water_types (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE CHECK (length(trim(name)) > 0),
  short_name text NOT NULL CHECK (length(trim(short_name)) > 0),
  tagline text NOT NULL DEFAULT '',
  description text NOT NULL DEFAULT '',
  badge text NOT NULL DEFAULT '',
  benefits text[] NOT NULL DEFAULT '{}',
  icon_key text NOT NULL DEFAULT 'water_drop',
  sort_order integer NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.water_types
  (name, short_name, tagline, description, badge, benefits, icon_key, sort_order)
VALUES
  ('Purified Water', 'Purified', 'Ultra-clean, every drop',
   'Reverse-osmosis filtered for a pure, neutral taste — no impurities, no aftertaste.',
   'Ultra Clean', ARRAY['RO filtered', 'Neutral taste', 'Family safe'], 'water_drop', 10),
  ('Mineral Water', 'Mineral', 'Refreshingly natural',
   'Filtered spring water enriched with calcium and magnesium for a crisp, refreshing taste.',
   'Natural Minerals', ARRAY['Natural minerals', 'Crisp taste', 'Daily hydration'], 'spa', 20),
  ('Alkaline Water', 'Alkaline', 'Smooth & balanced',
   'Ionized to pH 8.0–9.0 for a smoother taste and lower acidity.',
   'pH Balanced', ARRAY['Higher pH', 'Smooth taste', 'Low acidity'], 'science', 30)
ON CONFLICT (name) DO NOTHING;

ALTER TABLE public.water_types ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Water types are viewable by everyone" ON public.water_types;
CREATE POLICY "Water types are viewable by everyone"
  ON public.water_types FOR SELECT TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "Admins manage water types" ON public.water_types;
CREATE POLICY "Admins manage water types"
  ON public.water_types FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

GRANT SELECT ON public.water_types TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.water_types TO authenticated;

CREATE OR REPLACE FUNCTION public.touch_water_type_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_touch_water_type ON public.water_types;
CREATE TRIGGER trg_touch_water_type
  BEFORE UPDATE ON public.water_types
  FOR EACH ROW EXECUTE FUNCTION public.touch_water_type_updated_at();

-- 2. Station water type references the catalog -----------------------------
ALTER TABLE public.profiles
  ALTER COLUMN primary_water_type TYPE text USING primary_water_type::text;

-- Owners whose registration choice was lost: infer it from their existing
-- refill product, otherwise fall back to the first catalog entry.
UPDATE public.profiles p
SET primary_water_type = COALESCE(
  (SELECT wt.name
     FROM public.products pr
     JOIN public.water_types wt
       ON lower(pr.category) = lower(wt.short_name)
       OR lower(pr.name) LIKE lower(wt.short_name) || '%'
    WHERE pr.owner_id = p.id
    ORDER BY pr.is_available DESC, pr.created_at ASC NULLS LAST
    LIMIT 1),
  (SELECT name FROM public.water_types ORDER BY sort_order, name LIMIT 1)
)
WHERE p.role = 'owner'
  AND (p.primary_water_type IS NULL
       OR NOT EXISTS (SELECT 1 FROM public.water_types wt
                       WHERE wt.name = p.primary_water_type));

UPDATE public.profiles
SET primary_water_type = NULL
WHERE role <> 'owner'
  AND primary_water_type IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.water_types wt
                   WHERE wt.name = profiles.primary_water_type);

ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_primary_water_type_fkey;
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_primary_water_type_fkey
  FOREIGN KEY (primary_water_type) REFERENCES public.water_types(name)
  ON UPDATE CASCADE ON DELETE RESTRICT;

-- Owners cannot switch their water type after registration.
CREATE OR REPLACE FUNCTION public.guard_primary_water_type()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  IF current_user IN ('authenticated', 'anon')
     AND NOT public.is_admin()
     AND OLD.primary_water_type IS NOT NULL
     AND NEW.primary_water_type IS DISTINCT FROM OLD.primary_water_type THEN
    RAISE EXCEPTION 'Only an admin can change a station''s water type.';
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_guard_primary_water_type ON public.profiles;
CREATE TRIGGER trg_guard_primary_water_type
  BEFORE UPDATE OF primary_water_type ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.guard_primary_water_type();

-- 3. One product per station -----------------------------------------------
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_category_check;

-- Keep the oldest available product that matches the station's water type
-- (falling back to any refill product), so existing ids stay valid.
CREATE TEMP TABLE _station_product_keep ON COMMIT DROP AS
SELECT DISTINCT ON (p.id)
  p.id AS owner_id,
  pr.id AS product_id
FROM public.profiles p
JOIN public.water_types wt ON wt.name = p.primary_water_type
JOIN public.products pr ON pr.owner_id = p.id
WHERE p.role = 'owner'
  AND lower(COALESCE(pr.category, '')) NOT IN ('accessories', 'products', 'containers')
ORDER BY p.id,
  (lower(pr.category) = lower(wt.short_name)) DESC,
  pr.is_available DESC,
  pr.created_at ASC NULLS LAST;

-- Re-point references to removed refill duplicates onto the kept product.
UPDATE public.subscriptions s SET product_id = k.product_id
FROM public.products pr JOIN _station_product_keep k ON k.owner_id = pr.owner_id
WHERE s.product_id = pr.id AND pr.id <> k.product_id;

UPDATE public.inventory_ledger l SET product_id = k.product_id
FROM public.products pr JOIN _station_product_keep k ON k.owner_id = pr.owner_id
WHERE l.product_id = pr.id AND pr.id <> k.product_id;

UPDATE public.owner_inventory_ledger l SET product_id = k.product_id
FROM public.products pr JOIN _station_product_keep k ON k.owner_id = pr.owner_id
WHERE l.product_id = pr.id AND pr.id <> k.product_id;

UPDATE public.order_items oi SET product_id = k.product_id
FROM public.products pr JOIN _station_product_keep k ON k.owner_id = pr.owner_id
WHERE oi.product_id = pr.id AND pr.id <> k.product_id
  AND lower(COALESCE(pr.category, '')) NOT IN ('accessories', 'products', 'containers');

-- subscriptions and inventory_ledger require a product; stop rather than
-- lose rows that point at a container/accessory with no replacement.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.subscriptions s
    WHERE NOT EXISTS (SELECT 1 FROM _station_product_keep k WHERE k.product_id = s.product_id)
  ) OR EXISTS (
    SELECT 1 FROM public.inventory_ledger l
    WHERE NOT EXISTS (SELECT 1 FROM _station_product_keep k WHERE k.product_id = l.product_id)
  ) THEN
    RAISE EXCEPTION 'Subscriptions or inventory_ledger rows reference products that will be removed; resolve them first.';
  END IF;
END $$;

-- order_items and owner_inventory_ledger use ON DELETE SET NULL; order
-- history keeps its product_name / price_at_purchase snapshot.
DELETE FROM public.products pr
WHERE NOT EXISTS (SELECT 1 FROM _station_product_keep k WHERE k.product_id = pr.id);

CREATE UNIQUE INDEX IF NOT EXISTS products_one_per_station
  ON public.products (owner_id);

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS water_type text;

ALTER TABLE public.products
  DROP CONSTRAINT IF EXISTS products_water_type_fkey;
ALTER TABLE public.products
  ADD CONSTRAINT products_water_type_fkey
  FOREIGN KEY (water_type) REFERENCES public.water_types(name)
  ON UPDATE CASCADE ON DELETE RESTRICT;

-- 4. Keeping the station product in sync -----------------------------------
-- Internal: creates or refreshes the station's single refill product from its
-- water type. Price comes from the existing product, then station settings.
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

  SELECT * INTO v_row FROM public.products WHERE owner_id = p_owner_id FOR UPDATE;

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
      SELECT * INTO v_row FROM public.products WHERE owner_id = p_owner_id;
    END IF;
    RETURN v_row;
  END IF;

  SELECT COALESCE(
    NULLIF((SELECT price_per_gallon FROM public.owner_settings WHERE owner_id = p_owner_id), 0),
    NULLIF((SELECT price_per_gallon FROM public.profiles WHERE id = p_owner_id), 0),
    25
  ) INTO v_price;

  INSERT INTO public.products (owner_id, name, description, price, category, water_type, is_available)
  VALUES (p_owner_id, v_type.name, v_type.description, v_price, v_type.short_name, v_type.name, true)
  RETURNING * INTO v_row;
  RETURN v_row;
END; $$;

REVOKE ALL ON FUNCTION public.ensure_station_product(uuid) FROM PUBLIC, anon, authenticated;

-- Kept for existing app builds; now just returns the station's product.
CREATE OR REPLACE FUNCTION public.sync_owner_default_product(p_owner_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF p_owner_id IS NULL OR auth.uid() IS NULL THEN RETURN NULL; END IF;
  IF auth.uid() <> p_owner_id AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'You cannot synchronize another station''s product.';
  END IF;
  RETURN to_jsonb(public.ensure_station_product(p_owner_id));
END; $$;

CREATE OR REPLACE FUNCTION public.seed_station_standard_products_unguarded(p_owner_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  PERFORM public.ensure_station_product(p_owner_id);
END; $$;

-- Profile changes (registration, admin water type change) refresh the product.
CREATE OR REPLACE FUNCTION public.trigger_profile_station_product()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NEW.role = 'owner' AND NEW.primary_water_type IS NOT NULL THEN
    PERFORM public.ensure_station_product(NEW.id);
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_profile_station_product ON public.profiles;
CREATE TRIGGER trg_profile_station_product
  AFTER INSERT OR UPDATE OF primary_water_type, role ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.trigger_profile_station_product();

-- Catalog edits flow into every station selling that water type.
CREATE OR REPLACE FUNCTION public.trigger_water_type_station_products()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  UPDATE public.products
  SET name = NEW.name, category = NEW.short_name, description = NEW.description
  WHERE water_type = NEW.name
    AND (name, category, description) IS DISTINCT FROM (NEW.name, NEW.short_name, NEW.description);
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_water_type_station_products ON public.water_types;
CREATE TRIGGER trg_water_type_station_products
  AFTER UPDATE ON public.water_types
  FOR EACH ROW EXECUTE FUNCTION public.trigger_water_type_station_products();

-- Settings price edits (older app builds) flow into the product.
CREATE OR REPLACE FUNCTION public.trigger_sync_owner_default_product()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NEW.price_per_gallon IS NOT NULL AND NEW.price_per_gallon > 0 THEN
    PERFORM public.ensure_station_product(NEW.owner_id);
    UPDATE public.products SET price = NEW.price_per_gallon
    WHERE owner_id = NEW.owner_id AND price IS DISTINCT FROM NEW.price_per_gallon::numeric(10,2);
  END IF;
  RETURN NEW;
END; $$;

-- Product price is mirrored back to the station price fields.
CREATE OR REPLACE FUNCTION public.trigger_mirror_station_product_price()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  UPDATE public.owner_settings SET price_per_gallon = NEW.price
  WHERE owner_id = NEW.owner_id AND price_per_gallon IS DISTINCT FROM NEW.price::double precision;
  UPDATE public.profiles SET price_per_gallon = NEW.price
  WHERE id = NEW.owner_id AND price_per_gallon IS DISTINCT FROM NEW.price;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_mirror_station_product_price ON public.products;
CREATE TRIGGER trg_mirror_station_product_price
  AFTER INSERT OR UPDATE OF price ON public.products
  FOR EACH ROW EXECUTE FUNCTION public.trigger_mirror_station_product_price();

-- Owners may only edit price, availability, and stock fields.
CREATE OR REPLACE FUNCTION public.guard_station_product_update()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  IF current_user IN ('authenticated', 'anon') AND NOT public.is_admin() THEN
    IF NEW.owner_id IS DISTINCT FROM OLD.owner_id
       OR NEW.name IS DISTINCT FROM OLD.name
       OR NEW.category IS DISTINCT FROM OLD.category
       OR NEW.description IS DISTINCT FROM OLD.description
       OR NEW.water_type IS DISTINCT FROM OLD.water_type THEN
      RAISE EXCEPTION 'Stations can only change the price and availability of their water.';
    END IF;
    IF NEW.price IS NULL OR NEW.price <= 0 THEN
      RAISE EXCEPTION 'Price must be greater than zero.';
    END IF;
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_guard_station_product_update ON public.products;
CREATE TRIGGER trg_guard_station_product_update
  BEFORE UPDATE ON public.products
  FOR EACH ROW EXECUTE FUNCTION public.guard_station_product_update();

-- 5. Product policies: owners update only; no owner inserts or deletes -------
DROP POLICY IF EXISTS "Owners can delete own products" ON public.products;
DROP POLICY IF EXISTS "Owners can insert own products" ON public.products;
DROP POLICY IF EXISTS "Owners manage own products" ON public.products;
DROP POLICY IF EXISTS "Owners can update own products" ON public.products;
CREATE POLICY "Owners can update own products"
  ON public.products FOR UPDATE TO authenticated
  USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

-- Admin per-station product RPCs: one product per station, so admins adjust
-- it instead of adding or deleting products.
CREATE OR REPLACE FUNCTION public.admin_upsert_product(
  p_product_id uuid, p_owner_id uuid, p_name text, p_description text,
  p_price numeric, p_category text, p_stock_level integer,
  p_is_available boolean, p_reason text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_id uuid;
  v_row jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;

  SELECT id INTO v_id FROM public.products
  WHERE id = p_product_id OR (p_product_id IS NULL AND owner_id = p_owner_id);
  IF v_id IS NULL THEN
    v_id := (public.ensure_station_product(p_owner_id)).id;
  END IF;
  IF v_id IS NULL THEN RAISE EXCEPTION 'Station has no water type'; END IF;

  UPDATE public.products
  SET price = coalesce(p_price, price),
      stock_level = coalesce(p_stock_level, stock_level),
      is_available = coalesce(p_is_available, is_available)
  WHERE id = v_id;

  SELECT to_jsonb(p.*) INTO v_row FROM public.products p WHERE p.id = v_id;

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, new_value, metadata)
  VALUES (auth.uid(), 'admin_upsert_product', 'product', v_id::text, v_row,
    jsonb_build_object('reason', p_reason));

  RETURN jsonb_build_object('success', true, 'product', v_row);
END; $$;

CREATE OR REPLACE FUNCTION public.admin_delete_product(p_product_id uuid, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  RAISE EXCEPTION 'Each station sells its water type only. Change the station''s water type instead.';
END; $$;

-- 6. Registration stores the chosen water type -----------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_role public.user_role;
  v_town public.municipality;
  v_complete_address text;
  v_full_name text;
  v_first_name text;
  v_last_name text;
  v_username text;
  v_avatar_url text;
  v_water_type text;
BEGIN
  -- 1. Safe role resolution (OAuth signups default to 'customer')
  IF new.raw_user_meta_data->>'role' IN ('customer', 'owner', 'rider', 'admin') THEN
    v_role := (new.raw_user_meta_data->>'role')::public.user_role;
  ELSE
    v_role := 'customer'::public.user_role;
  END IF;

  -- 2. Safe municipality enum resolution
  IF lower(trim(COALESCE(new.raw_user_meta_data->>'town', ''))) = 'cantilan' THEN
    v_town := 'Cantilan'::public.municipality;
  ELSIF lower(trim(COALESCE(new.raw_user_meta_data->>'town', ''))) = 'madrid' THEN
    v_town := 'Madrid'::public.municipality;
  ELSE
    v_town := NULL;
  END IF;

  v_complete_address := NULLIF(TRIM(COALESCE(new.raw_user_meta_data->>'complete_address', '')), '');

  -- 3. Extract Name & Details (Google OAuth sends 'name', 'given_name', 'family_name', 'picture')
  v_first_name := COALESCE(
    NULLIF(TRIM(new.raw_user_meta_data->>'first_name'), ''),
    NULLIF(TRIM(new.raw_user_meta_data->>'given_name'), '')
  );

  v_last_name := COALESCE(
    NULLIF(TRIM(new.raw_user_meta_data->>'last_name'), ''),
    NULLIF(TRIM(new.raw_user_meta_data->>'family_name'), '')
  );

  v_full_name := COALESCE(
    NULLIF(TRIM(new.raw_user_meta_data->>'full_name'), ''),
    NULLIF(TRIM(new.raw_user_meta_data->>'name'), ''),
    NULLIF(TRIM(COALESCE(v_first_name, '') || ' ' || COALESCE(v_last_name, '')), ''),
    'New User'
  );

  v_username := COALESCE(
    NULLIF(TRIM(new.raw_user_meta_data->>'username'), ''),
    NULLIF(TRIM(split_part(COALESCE(new.email, ''), '@', 1)), ''),
    'user_' || substr(new.id::text, 1, 8)
  );

  v_avatar_url := COALESCE(
    NULLIF(TRIM(new.raw_user_meta_data->>'avatar_url'), ''),
    NULLIF(TRIM(new.raw_user_meta_data->>'picture'), '')
  );

  -- 4. Station water type: the registration choice, if it is an active catalog entry
  IF v_role = 'owner' THEN
    SELECT name INTO v_water_type FROM public.water_types
    WHERE name = NULLIF(TRIM(new.raw_user_meta_data->>'primary_water_type'), '')
      AND is_active;
    IF v_water_type IS NULL THEN
      SELECT name INTO v_water_type FROM public.water_types
      WHERE is_active ORDER BY sort_order, name LIMIT 1;
    END IF;
  END IF;

  -- 5. Upsert Profile
  INSERT INTO public.profiles (
    id, email, username, full_name, first_name, last_name, mi, suffix, role,
    phone, town, barangay, complete_address, landmark, station_name,
    avatar_url, latitude, longitude, primary_water_type
  )
  VALUES (
    new.id,
    new.email,
    v_username,
    v_full_name,
    v_first_name,
    v_last_name,
    new.raw_user_meta_data->>'mi',
    new.raw_user_meta_data->>'suffix',
    v_role,
    new.raw_user_meta_data->>'phone',
    v_town,
    new.raw_user_meta_data->>'barangay',
    v_complete_address,
    new.raw_user_meta_data->>'landmark',
    new.raw_user_meta_data->>'station_name',
    v_avatar_url,
    (new.raw_user_meta_data->>'latitude')::DOUBLE PRECISION,
    (new.raw_user_meta_data->>'longitude')::DOUBLE PRECISION,
    v_water_type
  )
  ON CONFLICT (id) DO UPDATE
    SET email = EXCLUDED.email,
        username = COALESCE(profiles.username, EXCLUDED.username),
        full_name = COALESCE(NULLIF(profiles.full_name, 'New User'), EXCLUDED.full_name),
        first_name = COALESCE(profiles.first_name, EXCLUDED.first_name),
        last_name = COALESCE(profiles.last_name, EXCLUDED.last_name),
        avatar_url = COALESCE(profiles.avatar_url, EXCLUDED.avatar_url),
        phone = COALESCE(EXCLUDED.phone, profiles.phone),
        town = COALESCE(EXCLUDED.town, profiles.town),
        barangay = COALESCE(EXCLUDED.barangay, profiles.barangay),
        complete_address = COALESCE(EXCLUDED.complete_address, profiles.complete_address),
        landmark = COALESCE(EXCLUDED.landmark, profiles.landmark),
        station_name = COALESCE(EXCLUDED.station_name, profiles.station_name),
        latitude = COALESCE(EXCLUDED.latitude, profiles.latitude),
        longitude = COALESCE(EXCLUDED.longitude, profiles.longitude),
        primary_water_type = COALESCE(profiles.primary_water_type, EXCLUDED.primary_water_type);

  RETURN new;
END;
$$;

-- 7. Backfill: every owner gets exactly one up-to-date product --------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT id FROM public.profiles WHERE role = 'owner' AND primary_water_type IS NOT NULL LOOP
    PERFORM public.ensure_station_product(r.id);
  END LOOP;
END $$;

-- The owner's configured price (what customers were shown) wins over a
-- leftover duplicate's price; the mirror trigger then syncs the profile.
UPDATE public.products pr SET price = s.price_per_gallon
FROM public.owner_settings s
WHERE s.owner_id = pr.owner_id
  AND s.price_per_gallon > 0
  AND pr.price IS DISTINCT FROM s.price_per_gallon::numeric(10,2);

-- Station price fields follow the kept product's price.
UPDATE public.owner_settings s SET price_per_gallon = pr.price
FROM public.products pr
WHERE pr.owner_id = s.owner_id AND s.price_per_gallon IS DISTINCT FROM pr.price::double precision;

UPDATE public.profiles p SET price_per_gallon = pr.price
FROM public.products pr
WHERE pr.owner_id = p.id AND p.price_per_gallon IS DISTINCT FROM pr.price;

COMMIT;

NOTIFY pgrst, 'reload schema';
