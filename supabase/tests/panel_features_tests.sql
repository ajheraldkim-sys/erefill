-- Panel features: rolled-back tests. Paste into the SQL Editor and run.
-- Every block ends in ROLLBACK, so nothing is saved. It stops at the first failing assert.

-- ===== protected_columns_test =====
BEGIN;
-- ==============================================================================
-- Harden signup roles and protect trust columns on profiles (2026-11-05)
-- ==============================================================================
-- 1. Self-signup could claim role 'admin' or 'rider' through user metadata.
--    Only accounts created by a trusted server function (admin_create_user,
--    create_rider_account, admin_create_station) may get privileged roles.
--    Self-signups arrive through the Auth server, whose session user is
--    supabase_auth_admin; those are limited to customer/owner.
-- 2. Users could UPDATE their own average_rating / review_count /
--    reliability_score / flagged_count. Those are now writable only by admins
--    or by SECURITY DEFINER functions (e.g. update_station_stats()).
-- 3. Adds profiles.verification_status (used by identity verification), which is
--    protected the same way.
--
-- Run after: single_water_product_catalog.sql. Test: supabase/tests/protected_columns_test.sql
-- ==============================================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS verification_status text NOT NULL DEFAULT 'unverified';
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_verification_status_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_verification_status_check
  CHECK (verification_status IN ('unverified', 'pending', 'approved', 'rejected'));

-- 1. Role resolution -----------------------------------------------------------
CREATE OR REPLACE FUNCTION public.resolve_signup_role(p_requested text, p_trusted boolean)
RETURNS public.user_role
LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN p_requested IN ('customer', 'owner') THEN p_requested::public.user_role
    WHEN p_trusted AND p_requested IN ('rider', 'admin') THEN p_requested::public.user_role
    ELSE 'customer'::public.user_role
  END;
$$;
REVOKE ALL ON FUNCTION public.resolve_signup_role(text, boolean) FROM PUBLIC, anon, authenticated;

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
  -- 1. Role: self-signups (Auth server session) may only be customer or owner.
  v_role := public.resolve_signup_role(
    new.raw_user_meta_data->>'role',
    session_user <> 'supabase_auth_admin'
  );

  -- 2. Safe municipality enum resolution
  IF lower(trim(COALESCE(new.raw_user_meta_data->>'town', ''))) = 'cantilan' THEN
    v_town := 'Cantilan'::public.municipality;
  ELSIF lower(trim(COALESCE(new.raw_user_meta_data->>'town', ''))) = 'madrid' THEN
    v_town := 'Madrid'::public.municipality;
  ELSE
    v_town := NULL;
  END IF;

  v_complete_address := NULLIF(TRIM(COALESCE(new.raw_user_meta_data->>'complete_address', '')), '');

  -- 3. Names (Google OAuth sends 'name', 'given_name', 'family_name', 'picture')
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

  -- 5. Upsert profile
  INSERT INTO public.profiles (
    id, email, username, full_name, first_name, last_name, mi, suffix, role,
    phone, town, barangay, complete_address, landmark, station_name,
    avatar_url, latitude, longitude, primary_water_type
  )
  VALUES (
    new.id, new.email, v_username, v_full_name, v_first_name, v_last_name,
    new.raw_user_meta_data->>'mi', new.raw_user_meta_data->>'suffix', v_role,
    new.raw_user_meta_data->>'phone', v_town, new.raw_user_meta_data->>'barangay',
    v_complete_address, new.raw_user_meta_data->>'landmark',
    new.raw_user_meta_data->>'station_name', v_avatar_url,
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

-- 2. Protected trust columns -----------------------------------------------------
-- SECURITY INVOKER on purpose: current_user is 'authenticated'/'anon' for direct
-- client writes, and the function owner (postgres) inside SECURITY DEFINER
-- functions such as update_station_stats() and the admin RPCs.
CREATE OR REPLACE FUNCTION public.guard_profile_protected_columns()
RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;

  IF NEW.average_rating IS NOT DISTINCT FROM OLD.average_rating
    AND NEW.review_count IS NOT DISTINCT FROM OLD.review_count
    AND NEW.reliability_score IS NOT DISTINCT FROM OLD.reliability_score
    AND NEW.flagged_count IS NOT DISTINCT FROM OLD.flagged_count
    AND NEW.verification_status IS NOT DISTINCT FROM OLD.verification_status
  THEN
    RETURN NEW;
  END IF;

  IF public.is_admin() THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'Unauthorized: You cannot alter protected account fields.';
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_profile_protected_columns ON public.profiles;
CREATE TRIGGER trg_guard_profile_protected_columns
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.guard_profile_protected_columns();


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Delivery coverage: free-delivery zones + distance-based fees (2026-11-05)
-- ==============================================================================
-- Each station defines where delivery is free:
--   * within free_delivery_radius_km of the station (default 1 km), OR
--   * to any barangay listed in free_delivery_barangays, OR
--   * when the order has at least free_delivery_min_gallons water gallons.
-- Everywhere else pays the platform's per-km rate from
-- system_config.delivery_fee_config (rate_per_km, minimum_fee,
-- min_billable_distance_km, rounding_rule, enabled).
--
-- Distance = straight-line (haversine) x 1.3 road factor, so it approximates
-- real road distance without calling a routing service from the database.
--
-- Self-contained: does not depend on delivery_fee_config_rpcs.sql.
-- Run before: order_pricing_v3.sql. Test: supabase/tests/delivery_quote_test.sql
-- ==============================================================================

ALTER TABLE public.owner_settings
  ADD COLUMN IF NOT EXISTS free_delivery_radius_km numeric(4,1) NOT NULL DEFAULT 1.0,
  ADD COLUMN IF NOT EXISTS free_delivery_barangays text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS free_delivery_min_gallons integer;

ALTER TABLE public.owner_settings DROP CONSTRAINT IF EXISTS owner_settings_free_radius_check;
ALTER TABLE public.owner_settings ADD CONSTRAINT owner_settings_free_radius_check
  CHECK (free_delivery_radius_km >= 0 AND free_delivery_radius_km <= 10);
ALTER TABLE public.owner_settings DROP CONSTRAINT IF EXISTS owner_settings_free_min_gallons_check;
ALTER TABLE public.owner_settings ADD CONSTRAINT owner_settings_free_min_gallons_check
  CHECK (free_delivery_min_gallons IS NULL OR free_delivery_min_gallons BETWEEN 1 AND 100);

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS delivery_distance_km numeric(6,2),
  ADD COLUMN IF NOT EXISTS delivery_rate_per_km numeric(8,2),
  ADD COLUMN IF NOT EXISTS delivery_free_reason text;

-- Road factor applied to straight-line distance.
CREATE OR REPLACE FUNCTION public.delivery_road_distance_km(
  p_lat1 double precision, p_lng1 double precision,
  p_lat2 double precision, p_lng2 double precision
) RETURNS numeric
LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN p_lat1 IS NULL OR p_lng1 IS NULL OR p_lat2 IS NULL OR p_lng2 IS NULL THEN NULL
    ELSE round((
      2 * 6371 * asin(sqrt(
        power(sin(radians(p_lat2 - p_lat1) / 2), 2)
        + cos(radians(p_lat1)) * cos(radians(p_lat2))
          * power(sin(radians(p_lng2 - p_lng1) / 2), 2)
      )) * 1.3
    )::numeric, 2)
  END;
$$;

-- Fee for a distance outside the free zone, from the admin's config.
CREATE OR REPLACE FUNCTION public.delivery_fee_for_distance(p_km numeric)
RETURNS numeric
LANGUAGE plpgsql STABLE SET search_path TO 'public' AS $$
DECLARE
  v_cfg jsonb;
  v_rate numeric;
  v_min numeric;
  v_min_km numeric;
  v_rule text;
  v_fee numeric;
BEGIN
  SELECT value INTO v_cfg FROM public.system_config WHERE key = 'delivery_fee_config';
  v_cfg := coalesce(v_cfg, '{}'::jsonb);
  IF NOT coalesce((v_cfg->>'enabled')::boolean, true) THEN
    RETURN 0;
  END IF;
  v_rate := greatest(coalesce((v_cfg->>'rate_per_km')::numeric, 10), 0);
  v_min := greatest(coalesce((v_cfg->>'minimum_fee')::numeric, 20), 0);
  v_min_km := greatest(coalesce((v_cfg->>'min_billable_distance_km')::numeric, 1), 0);
  v_rule := lower(trim(coalesce(v_cfg->>'rounding_rule', 'exact')));

  IF p_km IS NULL THEN
    RETURN v_min;
  END IF;

  -- Same rule as CheckoutRules.calculateDeliveryFee in the app: the rounding
  -- rule applies to the billable distance; the fee is whole pesos.
  v_fee := greatest(p_km, v_min_km);
  v_fee := CASE
    WHEN v_rule IN ('ceil', 'round_up') THEN ceil(v_fee)
    WHEN v_rule IN ('round', 'round_nearest') THEN round(v_fee)
    ELSE v_fee
  END;
  IF v_rate <= 0 THEN
    RETURN 0;
  END IF;
  RETURN round(greatest(v_rate * v_fee, v_min));
END;
$$;

-- Quote shown at checkout and charged by create_order_atomic.
CREATE OR REPLACE FUNCTION public.compute_delivery_quote(
  p_station_id uuid,
  p_lat double precision,
  p_lng double precision,
  p_barangay text DEFAULT NULL,
  p_gallons integer DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_slat double precision;
  v_slng double precision;
  v_radius numeric;
  v_barangays text[];
  v_min_gallons integer;
  v_km numeric;
  v_reason text;
  v_cfg jsonb;
BEGIN
  SELECT coalesce(p.latitude, p.lat), coalesce(p.longitude, p.lng)
  INTO v_slat, v_slng
  FROM public.profiles p
  WHERE p.id = p_station_id AND p.role = 'owner';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Water refill station not found.';
  END IF;

  SELECT coalesce(os.free_delivery_radius_km, 1.0),
         coalesce(os.free_delivery_barangays, '{}'),
         os.free_delivery_min_gallons
  INTO v_radius, v_barangays, v_min_gallons
  FROM public.owner_settings os WHERE os.owner_id = p_station_id;
  v_radius := coalesce(v_radius, 1.0);
  v_barangays := coalesce(v_barangays, '{}');

  v_km := public.delivery_road_distance_km(v_slat, v_slng, p_lat, p_lng);

  IF v_km IS NOT NULL AND v_km <= v_radius THEN
    v_reason := 'radius';
  ELSIF p_barangay IS NOT NULL AND EXISTS (
    SELECT 1 FROM unnest(v_barangays) b
    WHERE lower(trim(b)) = lower(trim(p_barangay))
  ) THEN
    v_reason := 'barangay';
  ELSIF v_min_gallons IS NOT NULL AND coalesce(p_gallons, 0) >= v_min_gallons THEN
    v_reason := 'min_gallons';
  END IF;

  SELECT value INTO v_cfg FROM public.system_config WHERE key = 'delivery_fee_config';

  RETURN jsonb_build_object(
    'distance_km', v_km,
    'is_free', v_reason IS NOT NULL,
    'free_reason', v_reason,
    'fee', CASE WHEN v_reason IS NOT NULL THEN 0 ELSE public.delivery_fee_for_distance(v_km) END,
    'rate_per_km', coalesce((v_cfg->>'rate_per_km')::numeric, 10),
    'minimum_fee', coalesce((v_cfg->>'minimum_fee')::numeric, 20),
    'free_radius_km', v_radius,
    'free_barangays', to_jsonb(v_barangays),
    'free_min_gallons', v_min_gallons
  );
END;
$$;

REVOKE ALL ON FUNCTION public.compute_delivery_quote(uuid, double precision, double precision, text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.compute_delivery_quote(uuid, double precision, double precision, text, integer) TO authenticated;
REVOKE ALL ON FUNCTION public.delivery_fee_for_distance(numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delivery_fee_for_distance(numeric) TO authenticated;


NOTIFY pgrst, 'reload schema';
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


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Rider tips (2026-11-05)
-- ==============================================================================
-- Customers can add an optional tip (₱0–₱500, whole pesos) at checkout for
-- delivery orders. It is part of the single charge (COD or PayMongo), so no
-- second payment is needed, and 100% goes to the rider:
--   * excluded from the station SALE and from the 10% commission base
--   * booked as a RIDER_TIP ledger entry to the assigned rider
--   * if no rider was assigned (station delivered itself) it stays with the
--     station as part of the SALE
-- create_order_atomic reads p_order_data->>'tip_amount' (order_pricing_v3.sql).
--
-- Run before: order_pricing_v3.sql. Test: supabase/tests/rider_tips_test.sql
-- ==============================================================================

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS tip_amount numeric(10,2) NOT NULL DEFAULT 0;
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_tip_amount_check;
ALTER TABLE public.orders ADD CONSTRAINT orders_tip_amount_check
  CHECK (tip_amount >= 0 AND tip_amount <= 500);

CREATE OR REPLACE FUNCTION public.proc_finalize_order_finances()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    v_commission NUMERIC;
    v_fee NUMERIC := greatest(coalesce(NEW.platform_fee, 0), 0);
    v_tip NUMERIC := greatest(coalesce(NEW.tip_amount, 0), 0);
    v_rider_tip NUMERIC := 0;
BEGIN
    IF NEW.status = 'delivered' AND OLD.status != 'delivered' THEN
        -- The tip belongs to the rider; without a rider it stays in the sale.
        IF NEW.assigned_rider_id IS NOT NULL THEN
            v_rider_tip := v_tip;
        END IF;

        INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
        VALUES (NEW.owner_id, NEW.id, NEW.total_amount - v_fee - v_rider_tip, 'SALE', 'Order completion payment');

        IF v_fee > 0 THEN
            INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description, metadata)
            VALUES (
                NEW.owner_id, NEW.id, v_fee, 'SERVICE_FEE', 'Platform service fee',
                jsonb_build_object('payee', 'platform', 'payment_method', NEW.payment_method)
            );

            IF lower(coalesce(NEW.payment_method, 'cod')) IN ('cod', 'cash', 'credit') THEN
                PERFORM public.apply_wallet_entry(
                    NEW.owner_id, -v_fee, 'service_fee', NEW.id, NULL,
                    'Service fee for order ' || upper(substr(NEW.id::text, 1, 8))
                );
            END IF;
        END IF;

        -- Commission excludes the tip.
        v_commission := (NEW.total_amount - v_tip) * 0.10;

        IF NEW.assigned_rider_id IS NOT NULL THEN
            INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
            VALUES (NEW.assigned_rider_id, NEW.id, v_commission, 'COMMISSION', 'Delivery commission for order');

            IF v_rider_tip > 0 THEN
                INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
                VALUES (NEW.assigned_rider_id, NEW.id, v_rider_tip, 'RIDER_TIP', 'Customer tip');

                INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
                VALUES (
                    NEW.assigned_rider_id, 'system_alert', 'normal', 'You got a tip!',
                    'A customer tipped you PHP ' || trim(to_char(v_rider_tip, '999990')) || '. Thank you for the great service.',
                    jsonb_build_object('order_id', NEW.id, 'tip_amount', v_rider_tip)
                );
            END IF;
        END IF;

        INSERT INTO public.domain_events (event_type, payload, actor_id)
        VALUES ('ORDER_COMPLETED', jsonb_build_object(
            'order_id', NEW.id, 'total', NEW.total_amount,
            'rider_id', NEW.assigned_rider_id, 'tip', v_tip), auth.uid());
    END IF;
    RETURN NEW;
END;
$$;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Seller and customer ID verification (2026-11-05)
-- ==============================================================================
-- Users upload a government ID (front, back, selfie; owners also a business
-- permit) to the private bucket verification_docs under <their uid>/.
-- An admin reviews and approves or rejects. profiles.verification_status
-- (added and write-protected by harden_signup_and_protected_columns.sql) is
-- only changed by the RPCs below.
--
-- Gates (enforced in create_order_atomic, order_pricing_v3.sql):
--   * stations must be 'approved' to receive orders
--   * unverified customers: cash-on-delivery up to PHP 1,000 and at most
--     2 active COD orders; verified customers have no limit
-- Backfill: owners who already completed a delivery are approved (legacy).
--
-- Run after: harden_signup_and_protected_columns.sql
-- Run before: order_pricing_v3.sql. Test: supabase/tests/identity_verification_test.sql
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.identity_verifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role text NOT NULL,
  id_type text NOT NULL CHECK (id_type IN (
    'philsys', 'drivers_license', 'umid', 'passport', 'postal', 'voters', 'prc', 'other')),
  id_number_last4 text CHECK (id_number_last4 ~ '^[0-9A-Za-z]{4}$'),
  front_path text NOT NULL,
  back_path text,
  selfie_path text NOT NULL,
  business_permit_path text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  reviewer_id uuid REFERENCES public.profiles(id),
  reviewed_at timestamptz,
  rejection_reason text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_identity_verifications_user ON public.identity_verifications (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_identity_verifications_pending ON public.identity_verifications (created_at) WHERE status = 'pending';

ALTER TABLE public.identity_verifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users read own verifications" ON public.identity_verifications;
CREATE POLICY "Users read own verifications" ON public.identity_verifications
  FOR SELECT TO authenticated USING (auth.uid() = user_id OR public.is_admin());
-- Writes only through the RPCs below.
REVOKE INSERT, UPDATE, DELETE ON public.identity_verifications FROM anon, authenticated;
GRANT SELECT ON public.identity_verifications TO authenticated;

-- Private bucket, one folder per user.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('verification_docs', 'verification_docs', false, 8388608,
        ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
ON CONFLICT (id) DO UPDATE SET public = false;

DROP POLICY IF EXISTS "Verification docs: owner upload" ON storage.objects;
CREATE POLICY "Verification docs: owner upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'verification_docs' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "Verification docs: owner or admin read" ON storage.objects;
CREATE POLICY "Verification docs: owner or admin read" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'verification_docs'
         AND ((storage.foldername(name))[1] = auth.uid()::text OR public.is_admin()));

CREATE OR REPLACE FUNCTION public.submit_identity_verification(
  p_id_type text,
  p_id_number_last4 text,
  p_front_path text,
  p_back_path text,
  p_selfie_path text,
  p_business_permit_path text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_role text;
  v_status text;
  v_prefix text;
  v_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required.'; END IF;
  SELECT role::text, verification_status INTO v_role, v_status FROM public.profiles WHERE id = v_uid;
  IF v_role NOT IN ('customer', 'owner') THEN
    RAISE EXCEPTION 'Only customers and station owners verify their ID here.';
  END IF;
  IF v_status = 'approved' THEN RAISE EXCEPTION 'Your ID is already verified.'; END IF;
  IF v_status = 'pending' THEN RAISE EXCEPTION 'Your ID is already being reviewed.'; END IF;

  v_prefix := v_uid::text || '/';
  IF p_front_path IS NULL OR p_selfie_path IS NULL
     OR left(p_front_path, length(v_prefix)) <> v_prefix
     OR left(p_selfie_path, length(v_prefix)) <> v_prefix
     OR (p_back_path IS NOT NULL AND left(p_back_path, length(v_prefix)) <> v_prefix)
     OR (p_business_permit_path IS NOT NULL AND left(p_business_permit_path, length(v_prefix)) <> v_prefix) THEN
    RAISE EXCEPTION 'Upload your ID photos before submitting.';
  END IF;
  IF v_role = 'owner' AND p_business_permit_path IS NULL THEN
    RAISE EXCEPTION 'Stations must also upload a business or sanitary permit.';
  END IF;

  INSERT INTO public.identity_verifications (
    user_id, role, id_type, id_number_last4, front_path, back_path, selfie_path, business_permit_path)
  VALUES (v_uid, v_role, p_id_type, NULLIF(p_id_number_last4, ''), p_front_path, p_back_path,
          p_selfie_path, p_business_permit_path)
  RETURNING id INTO v_id;

  UPDATE public.profiles SET verification_status = 'pending' WHERE id = v_uid;
  RETURN jsonb_build_object('id', v_id, 'status', 'pending');
END; $$;

CREATE OR REPLACE FUNCTION public.admin_review_identity_verification(
  p_verification_id uuid,
  p_approve boolean,
  p_reason text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_row public.identity_verifications%ROWTYPE;
  v_status text := CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  IF NOT p_approve AND coalesce(trim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'Give the user a reason for the rejection.';
  END IF;

  UPDATE public.identity_verifications
  SET status = v_status, reviewer_id = auth.uid(), reviewed_at = now(),
      rejection_reason = CASE WHEN p_approve THEN NULL ELSE trim(p_reason) END
  WHERE id = p_verification_id AND status = 'pending'
  RETURNING * INTO v_row;
  IF NOT FOUND THEN RAISE EXCEPTION 'This verification was already reviewed.'; END IF;

  UPDATE public.profiles SET verification_status = v_status WHERE id = v_row.user_id;

  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (
    v_row.user_id, 'system_alert', 'high',
    CASE WHEN p_approve THEN 'Your ID is verified' ELSE 'ID verification needs another try' END,
    CASE WHEN p_approve
      THEN CASE WHEN v_row.role = 'owner'
        THEN 'Your station is verified and can now receive orders.'
        ELSE 'Your account is verified. Order limits are lifted.' END
      ELSE 'Reason: ' || trim(p_reason) || '. You can submit new photos.' END,
    jsonb_build_object('verification_id', v_row.id, 'status', v_status)
  );

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, new_value, metadata)
  VALUES (auth.uid(), 'identity_verification_' || v_status, 'identity_verifications', v_row.id::text,
          jsonb_build_object('status', v_status),
          jsonb_build_object('user_id', v_row.user_id, 'reason', p_reason));

  RETURN jsonb_build_object('id', v_row.id, 'status', v_status);
END; $$;

REVOKE ALL ON FUNCTION public.submit_identity_verification(text, text, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_identity_verification(text, text, text, text, text, text) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_review_identity_verification(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_review_identity_verification(uuid, boolean, text) TO authenticated;

-- Order gate helper, used by create_order_atomic.
CREATE OR REPLACE FUNCTION public.assert_order_allowed_by_verification(
  p_customer_id uuid, p_owner_id uuid, p_payment_method text, p_total numeric
) RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_owner_status text;
  v_customer_status text;
  v_active int;
BEGIN
  SELECT verification_status INTO v_owner_status FROM public.profiles WHERE id = p_owner_id;
  IF coalesce(v_owner_status, 'unverified') <> 'approved' THEN
    RAISE EXCEPTION 'This station is not verified yet and cannot take orders.';
  END IF;

  SELECT verification_status INTO v_customer_status FROM public.profiles WHERE id = p_customer_id;
  IF coalesce(v_customer_status, 'unverified') = 'approved'
     OR lower(coalesce(p_payment_method, 'cod')) NOT IN ('cod', 'cash') THEN
    RETURN;
  END IF;

  IF p_total > 1000 THEN
    RAISE EXCEPTION 'Verify your ID to place cash-on-delivery orders above PHP 1,000.';
  END IF;
  SELECT count(*) INTO v_active FROM public.orders
  WHERE customer_id = p_customer_id
    AND lower(coalesce(payment_method, 'cod')) IN ('cod', 'cash')
    AND status NOT IN ('delivered', 'cancelled', 'failed');
  IF v_active >= 2 THEN
    RAISE EXCEPTION 'Verify your ID to have more than 2 cash-on-delivery orders at a time.';
  END IF;
END; $$;
REVOKE ALL ON FUNCTION public.assert_order_allowed_by_verification(uuid, uuid, text, numeric) FROM PUBLIC, anon, authenticated;

-- Backfill: stations that already delivered orders keep working.
UPDATE public.profiles p SET verification_status = 'approved'
WHERE p.role = 'owner' AND p.verification_status = 'unverified'
  AND EXISTS (SELECT 1 FROM public.orders o WHERE o.owner_id = p.id AND o.status = 'delivered');


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- create_order_atomic v3 (2026-11-05)
-- ==============================================================================
-- Starts from the LIVE definition (pg_get_functiondef on 2026-11-05; note the
-- live function does not use price_order() from whole_peso_pricing.sql).
-- Changes:
--   * Delivery fee comes from compute_delivery_quote() (free zone or per-km),
--     never from the client and no longer from owner_settings.base_delivery_fee.
--   * Writes delivery_distance_km, delivery_rate_per_km, delivery_free_reason.
--   * Accessories (products.kind = 'accessory') are sold alongside water;
--     only water gallons count toward the free-delivery gallon threshold.
--   * Optional rider tip (tip_amount, ₱0–₱500) added to the total.
--   * ID verification gates: approved stations only; COD limits for
--     unverified customers.
-- This is the single place later features (accessories, tips, verification
-- gates) extend create_order_atomic. Do not redefine it in other scripts.
--
-- Run order: harden_signup_and_protected_columns.sql -> delivery_coverage.sql ->
--   station_accessories.sql -> rider_tips.sql -> identity_verification.sql -> this file.
-- Tests: supabase/tests/delivery_quote_test.sql, accessories_test.sql
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.create_order_atomic(p_order_data jsonb, p_items_data jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_customer_id uuid := auth.uid();
  v_owner_id uuid;
  v_payment_method text;
  v_idempotency_key public.orders.idempotency_key%TYPE;
  v_voucher_id uuid;
  v_order_id uuid;
  v_item record;
  v_product record;
  v_computed_subtotal numeric(10,2) := 0;
  v_delivery_fee numeric(10,2) := 0;
  v_platform_fee numeric(10,2) := 0;
  v_discount numeric(10,2) := 0;
  v_total_amount numeric(10,2) := 0;
  v_order_row public.orders%ROWTYPE;
  v_voucher public.customer_reward_vouchers%ROWTYPE;
  v_config jsonb;
  v_lat double precision;
  v_lng double precision;
  v_maintenance jsonb;
  v_is_maintenance boolean := false;
  v_customer_suspended boolean := false;
  v_owner_suspended boolean := false;
  v_gallons integer := 0;
  v_quote jsonb;
  v_tip numeric(10,2) := 0;
BEGIN
  SELECT value INTO v_maintenance
  FROM public.system_config
  WHERE key = 'maintenance_mode';

  IF v_maintenance IS NOT NULL THEN
    IF jsonb_typeof(v_maintenance) = 'boolean' THEN
      v_is_maintenance := v_maintenance::text::boolean;
    ELSIF jsonb_typeof(v_maintenance) = 'string' THEN
      v_is_maintenance :=
        lower(trim(both '"' from v_maintenance::text)) IN ('true', '1', 'yes');
    END IF;
  END IF;

  IF v_is_maintenance THEN
    RAISE EXCEPTION 'System is currently undergoing maintenance. New orders are temporarily paused.';
  END IF;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required to place an order.';
  END IF;

  SELECT coalesce(is_suspended, false) INTO v_customer_suspended
  FROM public.profiles
  WHERE id = v_customer_id AND role = 'customer';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Only customer accounts can place orders.';
  END IF;
  IF v_customer_suspended THEN
    RAISE EXCEPTION 'Your account has been suspended. Please contact customer support.';
  END IF;

  v_idempotency_key := NULLIF(p_order_data->>'idempotency_key', '');
  IF v_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_order_row
    FROM public.orders
    WHERE customer_id = v_customer_id
      AND idempotency_key = v_idempotency_key;

    IF FOUND THEN
      RETURN jsonb_build_object(
        'id', v_order_row.id,
        'subtotal', v_order_row.subtotal,
        'delivery_fee', v_order_row.delivery_fee,
        'platform_fee', v_order_row.platform_fee,
        'total_amount', v_order_row.total_amount,
        'status', v_order_row.status
      );
    END IF;
  END IF;

  v_owner_id := NULLIF(p_order_data->>'owner_id', '')::uuid;
  v_payment_method := lower(trim(coalesce(p_order_data->>'payment_method', 'cod')));
  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'Station owner ID is required.';
  END IF;

  SELECT coalesce(is_suspended, false) INTO v_owner_suspended
  FROM public.profiles
  WHERE id = v_owner_id AND role = 'owner';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Water refill station not found.';
  END IF;
  IF v_owner_suspended THEN
    RAISE EXCEPTION 'This water station is currently suspended by administration.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = v_owner_id
      AND role = 'owner'
      AND coalesce(station_availability, 'open') = 'open'
  ) THEN
    RAISE EXCEPTION 'This water station is currently closed or unavailable.';
  END IF;
  IF NOT public.is_station_payment_method_available(v_owner_id, v_payment_method) THEN
    RAISE EXCEPTION 'This payment method is not available for this station.';
  END IF;

  FOR v_item IN
    SELECT * FROM jsonb_to_recordset(p_items_data) AS x(
      product_id uuid,
      quantity integer,
      product_name text
    )
  LOOP
    IF v_item.quantity <= 0 THEN
      RAISE EXCEPTION 'Invalid quantity for item %', v_item.product_name;
    END IF;

    SELECT * INTO v_product
    FROM public.products
    WHERE id = v_item.product_id
      AND owner_id = v_owner_id
      AND is_available = true;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Product % is unavailable at this station.', v_item.product_name;
    END IF;

    v_computed_subtotal :=
      v_computed_subtotal + (v_product.price * v_item.quantity);
    -- Only water counts toward the free-delivery gallon threshold.
    IF v_product.kind = 'water' THEN
      v_gallons := v_gallons + v_item.quantity;
    END IF;
  END LOOP;

  IF v_computed_subtotal <= 0 THEN
    RAISE EXCEPTION 'Cart cannot be empty.';
  END IF;

  v_lat := NULLIF(p_order_data->>'customer_latitude', '')::double precision;
  v_lng := NULLIF(p_order_data->>'customer_longitude', '')::double precision;

  -- Delivery fee: server-side quote (free zone or per-km). Client fee ignored.
  v_quote := public.compute_delivery_quote(
    v_owner_id, v_lat, v_lng,
    NULLIF(p_order_data->>'customer_barangay', ''),
    v_gallons
  );
  v_delivery_fee := coalesce((v_quote->>'fee')::numeric, 0);

  v_config := public.get_platform_fee_config();
  IF coalesce((v_config->>'enabled')::boolean, false) THEN
    v_platform_fee := round(
      ((v_computed_subtotal + v_delivery_fee)
        * coalesce((v_config->>'percent')::numeric, 0) / 100)
        + coalesce((v_config->>'fixed')::numeric, 0),
      2
    );
    v_platform_fee := greatest(v_platform_fee, 0);
  END IF;

  v_voucher_id := NULLIF(p_order_data->>'voucher_id', '')::uuid;
  IF v_voucher_id IS NOT NULL THEN
    SELECT * INTO v_voucher
    FROM public.customer_reward_vouchers
    WHERE id = v_voucher_id
      AND user_id = v_customer_id
      AND is_used = false
      AND expires_at > now()
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'This reward voucher is no longer available. Refresh your vouchers and try again.';
    END IF;

    IF v_voucher.is_delivery_discount THEN
      v_discount := least(
        greatest(v_voucher.discount_amount, 0),
        v_delivery_fee
      );
    ELSE
      v_discount := least(
        greatest(v_voucher.discount_amount, 0),
        v_computed_subtotal + v_delivery_fee + v_platform_fee
      );
    END IF;
  END IF;

  -- Optional rider tip: whole pesos, ₱0–₱500, paid on top (no fees, no voucher).
  v_tip := round(coalesce(NULLIF(p_order_data->>'tip_amount', '')::numeric, 0));
  IF v_tip < 0 OR v_tip > 500 THEN
    RAISE EXCEPTION 'Tip must be between PHP 0 and PHP 500.';
  END IF;

  v_total_amount := greatest(
    v_computed_subtotal + v_delivery_fee + v_platform_fee - v_discount,
    0
  ) + v_tip;

  -- ID verification gates (identity_verification.sql).
  PERFORM public.assert_order_allowed_by_verification(
    v_customer_id, v_owner_id, v_payment_method, v_total_amount
  );

  INSERT INTO public.orders (
    id,
    customer_id,
    owner_id,
    station_name,
    customer_name,
    customer_phone,
    customer_address,
    customer_barangay,
    customer_municipality,
    customer_landmark,
    idempotency_key,
    subtotal,
    delivery_fee,
    platform_fee,
    total_amount,
    payment_method,
    payment_status,
    notes,
    region_id,
    customer_latitude,
    customer_longitude,
    delivery_lat,
    delivery_lng,
    delivery_latitude,
    delivery_longitude,
    delivery_distance_km,
    delivery_rate_per_km,
    delivery_free_reason,
    tip_amount,
    items,
    status
  ) VALUES (
    coalesce(
      NULLIF(p_order_data->>'id', '')::uuid,
      gen_random_uuid()
    ),
    v_customer_id,
    v_owner_id,
    coalesce(p_order_data->>'station_name', 'Water Station'),
    p_order_data->>'customer_name',
    p_order_data->>'customer_phone',
    p_order_data->>'customer_address',
    p_order_data->>'customer_barangay',
    p_order_data->>'customer_municipality',
    p_order_data->>'customer_landmark',
    v_idempotency_key,
    v_computed_subtotal,
    v_delivery_fee,
    v_platform_fee,
    v_total_amount,
    v_payment_method,
    'pending',
    p_order_data->>'notes',
    NULLIF(p_order_data->>'region_id', '')::uuid,
    v_lat,
    v_lng,
    v_lat,
    v_lng,
    v_lat,
    v_lng,
    (v_quote->>'distance_km')::numeric,
    (v_quote->>'rate_per_km')::numeric,
    v_quote->>'free_reason',
    v_tip,
    coalesce(p_items_data, '[]'::jsonb),
    'pending'
  )
  ON CONFLICT DO NOTHING
  RETURNING * INTO v_order_row;

  IF NOT FOUND THEN
    IF v_idempotency_key IS NOT NULL THEN
      SELECT * INTO v_order_row
      FROM public.orders
      WHERE customer_id = v_customer_id
        AND idempotency_key = v_idempotency_key;

      IF FOUND THEN
        RETURN jsonb_build_object(
          'id', v_order_row.id,
          'subtotal', v_order_row.subtotal,
          'delivery_fee', v_order_row.delivery_fee,
          'platform_fee', v_order_row.platform_fee,
          'total_amount', v_order_row.total_amount,
          'status', v_order_row.status
        );
      END IF;
    END IF;
    RAISE EXCEPTION 'Order could not be created because of a conflicting order record.';
  END IF;

  v_order_id := v_order_row.id;

  FOR v_item IN
    SELECT * FROM jsonb_to_recordset(p_items_data) AS x(
      product_id uuid,
      quantity integer,
      product_name text
    )
  LOOP
    SELECT * INTO v_product FROM public.products WHERE id = v_item.product_id;
    INSERT INTO public.order_items (
      order_id,
      product_id,
      product_name,
      quantity,
      price_at_purchase,
      subtotal
    ) VALUES (
      v_order_id,
      v_item.product_id,
      v_product.name,
      v_item.quantity,
      v_product.price,
      (v_product.price * v_item.quantity)
    );
  END LOOP;

  IF v_voucher_id IS NOT NULL THEN
    UPDATE public.customer_reward_vouchers
    SET is_used = true
    WHERE id = v_voucher_id
      AND user_id = v_customer_id
      AND is_used = false;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'This reward voucher was already used by another order.';
    END IF;
  END IF;

  INSERT INTO public.system_notifications (
    user_id,
    type,
    priority,
    title,
    content,
    metadata
  ) VALUES (
    v_owner_id,
    'system_alert',
    'high',
    'New Refill Order',
    coalesce(p_order_data->>'customer_name', 'A customer')
      || ' placed a new refill order of PHP '
      || trim(to_char(v_total_amount, '999999990.00'))
      || ' (' || upper(coalesce(p_order_data->>'payment_method', 'cod')) || ').',
    jsonb_build_object(
      'order_id', v_order_id,
      'status', 'pending',
      'total_amount', v_total_amount
    )
  );

  RETURN jsonb_build_object(
    'id', v_order_id,
    'subtotal', v_computed_subtotal,
    'delivery_fee', v_delivery_fee,
    'delivery_distance_km', (v_quote->>'distance_km')::numeric,
    'delivery_free_reason', v_quote->>'free_reason',
    'platform_fee', v_platform_fee,
    'discount_amount', v_discount,
    'tip_amount', v_tip,
    'total_amount', v_total_amount,
    'status', 'pending'
  );
END;
$function$;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Rider live location privacy (2026-11-05)
-- ==============================================================================
-- rider_locations was readable by everyone ("Public can view rider
-- locations"). Now only these can read a rider's points:
--   * the rider, admins
--   * the customer or station of an order that rider is delivering right now
--     (assigned_to_rider / out_for_delivery)
-- After delivery the customer loses access. Points older than 24 h are purged
-- hourly (pg_cron, when the extension is available).
-- Test: supabase/tests/rider_live_location_test.sql
-- ==============================================================================

DROP POLICY IF EXISTS "Public can view rider locations" ON public.rider_locations;
DROP POLICY IF EXISTS "Rider location visible to active delivery parties" ON public.rider_locations;
CREATE POLICY "Rider location visible to active delivery parties" ON public.rider_locations
  FOR SELECT TO authenticated
  USING (
    rider_id = auth.uid()
    OR public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.orders o
      WHERE (o.assigned_rider_id = rider_locations.rider_id OR o.rider_id = rider_locations.rider_id)
        AND o.status IN ('assigned_to_rider', 'out_for_delivery')
        AND (o.customer_id = auth.uid() OR o.owner_id = auth.uid())
    )
  );

DROP POLICY IF EXISTS "Riders can update their own location" ON public.rider_locations;
CREATE POLICY "Riders can update their own location" ON public.rider_locations
  FOR INSERT TO authenticated
  WITH CHECK (rider_id = auth.uid());
REVOKE ALL ON public.rider_locations FROM anon;

CREATE OR REPLACE FUNCTION public.purge_old_rider_locations()
RETURNS integer
LANGUAGE sql SECURITY DEFINER SET search_path TO 'public' AS $$
  WITH d AS (
    DELETE FROM public.rider_locations WHERE "timestamp" < now() - interval '24 hours' RETURNING 1
  ) SELECT count(*)::int FROM d;
$$;
REVOKE ALL ON FUNCTION public.purge_old_rider_locations() FROM PUBLIC, anon, authenticated;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'purge_old_rider_locations';
    PERFORM cron.schedule('purge_old_rider_locations', '7 * * * *', 'SELECT public.purge_old_rider_locations()');
  END IF;
END $$;

-- ==============================================================================
-- Smart refill reminders (2026-11-05)
-- ==============================================================================
-- Learns each customer's refill rhythm (median days between their last
-- delivered orders, needs >= 3 orders) and reminds them a day before they
-- usually reorder. At most one reminder per 3 days, never while an order is
-- active, and only when profiles.refill_reminders_enabled.
--   * customer_refill_rhythm()  -> for the app's home banner (current user)
--   * send_refill_reminders()   -> daily 9:00 PH pg_cron job, inserts notifications
-- Test: supabase/tests/refill_reminders_test.sql
-- ==============================================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS refill_reminders_enabled boolean NOT NULL DEFAULT true;

CREATE OR REPLACE FUNCTION public.refill_rhythm_for(p_customer_id uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  WITH recent AS (
    SELECT created_at, owner_id, station_name
    FROM public.orders
    WHERE customer_id = p_customer_id AND status = 'delivered'
    ORDER BY created_at DESC
    LIMIT 6
  ), gaps AS (
    SELECT extract(epoch FROM (created_at - lead(created_at) OVER (ORDER BY created_at DESC))) / 86400.0 AS days
    FROM recent
  ), stats AS (
    SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY days) AS median_days,
           count(*) AS gap_count
    FROM gaps WHERE days IS NOT NULL AND days > 0.5
  ), last AS (
    SELECT * FROM recent ORDER BY created_at DESC LIMIT 1
  )
  SELECT CASE
    WHEN (SELECT gap_count FROM stats) < 2 THEN jsonb_build_object('has_rhythm', false)
    ELSE jsonb_build_object(
      'has_rhythm', true,
      'median_days', round((SELECT median_days FROM stats)::numeric, 1),
      'last_order_at', (SELECT created_at FROM last),
      'station_id', (SELECT owner_id FROM last),
      'station_name', (SELECT station_name FROM last),
      'due_at', (SELECT created_at FROM last)
                + make_interval(secs => greatest((SELECT median_days FROM stats) - 1, 1) * 86400),
      'is_due', now() >= (SELECT created_at FROM last)
                + make_interval(secs => greatest((SELECT median_days FROM stats) - 1, 1) * 86400),
      'has_active_order', EXISTS (
        SELECT 1 FROM public.orders
        WHERE customer_id = p_customer_id
          AND status NOT IN ('delivered', 'cancelled', 'failed'))
    )
  END;
$$;
REVOKE ALL ON FUNCTION public.refill_rhythm_for(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.customer_refill_rhythm()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT CASE WHEN auth.uid() IS NULL THEN '{"has_rhythm": false}'::jsonb
              ELSE public.refill_rhythm_for(auth.uid()) END;
$$;
REVOKE ALL ON FUNCTION public.customer_refill_rhythm() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.customer_refill_rhythm() TO authenticated;

CREATE OR REPLACE FUNCTION public.send_refill_reminders()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_row record;
  v_r jsonb;
  v_sent integer := 0;
BEGIN
  FOR v_row IN
    SELECT p.id FROM public.profiles p
    WHERE p.role = 'customer' AND p.refill_reminders_enabled AND NOT coalesce(p.is_suspended, false)
  LOOP
    v_r := public.refill_rhythm_for(v_row.id);
    CONTINUE WHEN NOT coalesce((v_r->>'has_rhythm')::boolean, false)
               OR NOT (v_r->>'is_due')::boolean
               OR (v_r->>'has_active_order')::boolean;
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM public.system_notifications n
      WHERE n.user_id = v_row.id
        AND n.metadata->>'kind' = 'refill_reminder'
        AND n.created_at > now() - interval '3 days');

    INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
    VALUES (
      v_row.id, 'system_alert', 'normal', 'Time for a refill?',
      'You usually reorder every ' || round((v_r->>'median_days')::numeric) || ' days. '
        || 'Tap to reorder from ' || coalesce(v_r->>'station_name', 'your station') || '.',
      jsonb_build_object('kind', 'refill_reminder', 'station_id', v_r->>'station_id')
    );
    v_sent := v_sent + 1;
  END LOOP;
  RETURN v_sent;
END; $$;
REVOKE ALL ON FUNCTION public.send_refill_reminders() FROM PUBLIC, anon, authenticated;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'send_refill_reminders';
    -- 9:00 Asia/Manila = 01:00 UTC, so reminders arrive in the morning.
    PERFORM cron.schedule('send_refill_reminders', '0 1 * * *', 'SELECT public.send_refill_reminders()');
  END IF;
END $$;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Water quality transparency (2026-11-05)
-- ==============================================================================
-- Stations upload lab test results and permits (bacteriological /
-- physical-chemical water analysis, sanitary permit, business permit) with
-- issue and expiry dates. Admins approve them; approved, unexpired lab tests
-- give the station a "Water tested" badge and a small ranking boost.
-- Files live in the private verification_docs bucket under <uid>/certs/.
-- Approved certificate files are viewable by any signed-in user.
-- Daily job: marks expired certificates and warns owners 14 days ahead.
--
-- Run after: identity_verification.sql (bucket). Test: supabase/tests/water_quality_certs_test.sql
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.station_certifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  cert_type text NOT NULL CHECK (cert_type IN (
    'bacteriological', 'physical_chemical', 'sanitary_permit', 'business_permit')),
  issued_on date NOT NULL,
  expires_on date NOT NULL,
  file_path text NOT NULL,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected', 'expired')),
  reviewer_id uuid REFERENCES public.profiles(id),
  reviewed_at timestamptz,
  rejection_reason text,
  expiry_warned_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (expires_on > issued_on)
);
CREATE INDEX IF NOT EXISTS idx_station_certs_owner ON public.station_certifications (owner_id, status);

ALTER TABLE public.station_certifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Approved certs are public, owners see their own" ON public.station_certifications;
CREATE POLICY "Approved certs are public, owners see their own" ON public.station_certifications
  FOR SELECT TO authenticated
  USING (status = 'approved' OR owner_id = auth.uid() OR public.is_admin());
REVOKE INSERT, UPDATE, DELETE ON public.station_certifications FROM anon, authenticated;
GRANT SELECT ON public.station_certifications TO authenticated;

-- Approved certificate files are readable by signed-in users.
DROP POLICY IF EXISTS "Verification docs: approved certs readable" ON storage.objects;
CREATE POLICY "Verification docs: approved certs readable" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'verification_docs' AND EXISTS (
    SELECT 1 FROM public.station_certifications c
    WHERE c.file_path = storage.objects.name AND c.status = 'approved'));

CREATE OR REPLACE FUNCTION public.submit_station_certification(
  p_cert_type text, p_issued_on date, p_expires_on date, p_file_path text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_uid AND role = 'owner') THEN
    RAISE EXCEPTION 'Only station owners upload certificates.';
  END IF;
  IF p_file_path IS NULL OR left(p_file_path, length(v_uid::text) + 7) <> v_uid::text || '/certs/' THEN
    RAISE EXCEPTION 'Upload the certificate file first.';
  END IF;
  IF p_expires_on <= current_date THEN
    RAISE EXCEPTION 'This certificate has already expired.';
  END IF;
  IF p_issued_on > current_date THEN
    RAISE EXCEPTION 'The issue date cannot be in the future.';
  END IF;
  INSERT INTO public.station_certifications (owner_id, cert_type, issued_on, expires_on, file_path)
  VALUES (v_uid, p_cert_type, p_issued_on, p_expires_on, p_file_path)
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('id', v_id, 'status', 'pending');
END; $$;

CREATE OR REPLACE FUNCTION public.admin_review_station_certification(
  p_cert_id uuid, p_approve boolean, p_reason text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_row public.station_certifications%ROWTYPE;
  v_status text := CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  IF NOT p_approve AND coalesce(trim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'Give the station a reason for the rejection.';
  END IF;
  UPDATE public.station_certifications
  SET status = v_status, reviewer_id = auth.uid(), reviewed_at = now(),
      rejection_reason = CASE WHEN p_approve THEN NULL ELSE trim(p_reason) END
  WHERE id = p_cert_id AND status = 'pending'
  RETURNING * INTO v_row;
  IF NOT FOUND THEN RAISE EXCEPTION 'This certificate was already reviewed.'; END IF;

  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (v_row.owner_id, 'system_alert', 'normal',
    CASE WHEN p_approve THEN 'Certificate approved' ELSE 'Certificate rejected' END,
    CASE WHEN p_approve THEN 'Customers can now see your certificate.'
         ELSE 'Reason: ' || trim(p_reason) END,
    jsonb_build_object('certificate_id', v_row.id, 'status', v_status));
  RETURN jsonb_build_object('id', v_row.id, 'status', v_status);
END; $$;

REVOKE ALL ON FUNCTION public.submit_station_certification(text, date, date, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_station_certification(text, date, date, text) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_review_station_certification(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_review_station_certification(uuid, boolean, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.expire_station_certifications()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_n integer;
BEGIN
  UPDATE public.station_certifications SET status = 'expired'
  WHERE status = 'approved' AND expires_on <= current_date;
  GET DIAGNOSTICS v_n = ROW_COUNT;

  WITH soon AS (
    UPDATE public.station_certifications SET expiry_warned_at = now()
    WHERE status = 'approved' AND expiry_warned_at IS NULL
      AND expires_on <= current_date + 14
    RETURNING owner_id, id, cert_type, expires_on
  )
  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  SELECT owner_id, 'system_alert', 'high', 'Certificate expiring soon',
         'Your ' || replace(cert_type, '_', ' ') || ' certificate expires on '
           || to_char(expires_on, 'Mon DD, YYYY') || '. Upload a new one to keep your badge.',
         jsonb_build_object('certificate_id', id)
  FROM soon;
  RETURN v_n;
END; $$;
REVOKE ALL ON FUNCTION public.expire_station_certifications() FROM PUBLIC, anon, authenticated;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'expire_station_certifications';
    PERFORM cron.schedule('expire_station_certifications', '15 16 * * *', 'SELECT public.expire_station_certifications()');
  END IF;
END $$;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Order disputes and refunds (2026-11-05)
-- ==============================================================================
-- Extends the existing public.disputes table (status enum: open,
-- investigating, resolved, dismissed) with the customer -> station -> admin
-- flow:
--   1. Customer opens a dispute within 48 h of delivery, one per order,
--      with optional photo evidence (private bucket dispute_evidence).
--   2. Station accepts (refund amount) -> resolved, or explains -> the
--      dispute is escalated ('investigating') for an admin.
--   3. Customer may escalate if the station has not answered in 24 h.
--   4. Admin resolves with an optional refund, or dismisses.
-- A granted refund books a REFUND ledger entry against the station, notifies
-- the customer, and refunds against the station increase flagged_count.
-- Money movement: COD refunds are returned by the station in cash; online
-- payments are refunded by the admin in PayMongo (orders.payment_status is
-- set to 'refunded' when the full total is refunded).
--
-- Test: supabase/tests/order_disputes_test.sql
-- ==============================================================================

ALTER TABLE public.disputes
  ADD COLUMN IF NOT EXISTS evidence_paths text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS owner_response text,
  ADD COLUMN IF NOT EXISTS owner_responded_at timestamptz,
  ADD COLUMN IF NOT EXISTS refund_amount numeric(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS escalated_at timestamptz;
ALTER TABLE public.disputes DROP CONSTRAINT IF EXISTS disputes_reason_check;
ALTER TABLE public.disputes ADD CONSTRAINT disputes_reason_check CHECK (reason IN (
  'missing_items', 'wrong_item', 'quality', 'damaged', 'not_delivered', 'overcharged', 'other'));
ALTER TABLE public.disputes DROP CONSTRAINT IF EXISTS disputes_refund_check;
ALTER TABLE public.disputes ADD CONSTRAINT disputes_refund_check CHECK (refund_amount >= 0);
CREATE UNIQUE INDEX IF NOT EXISTS disputes_one_per_order ON public.disputes (order_id);

-- Owners no longer update disputes directly; they use owner_respond_dispute.
DROP POLICY IF EXISTS "Owners can update disputes for their station" ON public.disputes;
REVOKE INSERT, DELETE ON public.disputes FROM anon, authenticated;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('dispute_evidence', 'dispute_evidence', false, 8388608,
        ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO UPDATE SET public = false;
DROP POLICY IF EXISTS "Dispute evidence: reporter upload" ON storage.objects;
CREATE POLICY "Dispute evidence: reporter upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'dispute_evidence' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "Dispute evidence: parties read" ON storage.objects;
CREATE POLICY "Dispute evidence: parties read" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'dispute_evidence' AND (
    (storage.foldername(name))[1] = auth.uid()::text
    OR public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.disputes d JOIN public.orders o ON o.id = d.order_id
      WHERE storage.objects.name = ANY (d.evidence_paths) AND o.owner_id = auth.uid())));

CREATE OR REPLACE FUNCTION public.open_dispute(
  p_order_id uuid, p_reason text, p_description text, p_evidence_paths text[] DEFAULT '{}'
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_order public.orders%ROWTYPE;
  v_done_at timestamptz;
  v_id uuid;
  v_path text;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id AND customer_id = v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order not found.'; END IF;
  IF v_order.status::text <> 'delivered' THEN
    RAISE EXCEPTION 'You can report a problem once the order is delivered.';
  END IF;
  v_done_at := coalesce(v_order.actual_completion_at, v_order.updated_at, v_order.created_at);
  IF v_done_at < now() - interval '48 hours' THEN
    RAISE EXCEPTION 'Problems must be reported within 48 hours of delivery.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.disputes WHERE order_id = p_order_id) THEN
    RAISE EXCEPTION 'A problem was already reported for this order.';
  END IF;
  IF coalesce(trim(p_description), '') = '' THEN
    RAISE EXCEPTION 'Tell the station what went wrong.';
  END IF;
  FOREACH v_path IN ARRAY coalesce(p_evidence_paths, '{}') LOOP
    IF left(v_path, length(v_uid::text) + 1) <> v_uid::text || '/' THEN
      RAISE EXCEPTION 'Invalid evidence photo.';
    END IF;
  END LOOP;

  INSERT INTO public.disputes (order_id, reporter_id, reason, description, status, evidence_paths)
  VALUES (p_order_id, v_uid, p_reason, trim(p_description), 'open', coalesce(p_evidence_paths, '{}'))
  RETURNING id INTO v_id;

  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (v_order.owner_id, 'system_alert', 'high', 'A customer reported a problem',
    'Order #' || upper(substr(p_order_id::text, 1, 8)) || ': ' || replace(p_reason, '_', ' ')
      || '. Please respond within 24 hours.',
    jsonb_build_object('dispute_id', v_id, 'order_id', p_order_id));
  RETURN jsonb_build_object('id', v_id, 'status', 'open');
END; $$;

-- Shared by station and admin resolutions.
CREATE OR REPLACE FUNCTION public.apply_dispute_refund(p_dispute_id uuid, p_amount numeric, p_note text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_d public.disputes%ROWTYPE;
  v_o public.orders%ROWTYPE;
BEGIN
  SELECT * INTO v_d FROM public.disputes WHERE id = p_dispute_id;
  SELECT * INTO v_o FROM public.orders WHERE id = v_d.order_id;
  IF p_amount < 0 OR p_amount > v_o.total_amount THEN
    RAISE EXCEPTION 'Refund must be between PHP 0 and the order total.';
  END IF;
  UPDATE public.disputes SET refund_amount = p_amount, status = 'resolved',
         resolution_notes = p_note, updated_at = now()
  WHERE id = p_dispute_id;
  IF p_amount > 0 THEN
    INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
    VALUES (v_o.owner_id, v_o.id, -p_amount, 'REFUND', 'Refund for reported problem');
    UPDATE public.profiles SET flagged_count = coalesce(flagged_count, 0) + 1 WHERE id = v_o.owner_id;
    IF p_amount >= v_o.total_amount THEN
      UPDATE public.orders SET payment_status = 'refunded' WHERE id = v_o.id;
    END IF;
  END IF;
  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (v_d.reporter_id, 'system_alert', 'high',
    CASE WHEN p_amount > 0 THEN 'Refund approved' ELSE 'Your report was reviewed' END,
    CASE WHEN p_amount > 0
      THEN 'PHP ' || trim(to_char(p_amount, '999990.00')) || ' will be returned '
        || CASE WHEN lower(coalesce(v_o.payment_method, 'cod')) IN ('cod', 'cash')
                THEN 'by the station in cash.' ELSE 'to your original payment method.' END
      ELSE coalesce(p_note, 'No refund was given.') END,
    jsonb_build_object('dispute_id', p_dispute_id, 'order_id', v_o.id, 'refund_amount', p_amount));
END; $$;
REVOKE ALL ON FUNCTION public.apply_dispute_refund(uuid, numeric, text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.owner_respond_dispute(
  p_dispute_id uuid, p_accept boolean, p_response text, p_refund_amount numeric DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_d public.disputes%ROWTYPE;
BEGIN
  SELECT d.* INTO v_d FROM public.disputes d JOIN public.orders o ON o.id = d.order_id
  WHERE d.id = p_dispute_id AND o.owner_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Dispute not found.'; END IF;
  IF v_d.status::text <> 'open' OR v_d.owner_responded_at IS NOT NULL THEN
    RAISE EXCEPTION 'This dispute was already answered.';
  END IF;
  IF coalesce(trim(p_response), '') = '' THEN RAISE EXCEPTION 'Write a reply to the customer.'; END IF;

  UPDATE public.disputes SET owner_response = trim(p_response), owner_responded_at = now(), updated_at = now()
  WHERE id = p_dispute_id;

  IF p_accept THEN
    PERFORM public.apply_dispute_refund(p_dispute_id, coalesce(p_refund_amount, 0), 'Station: ' || trim(p_response));
    RETURN jsonb_build_object('status', 'resolved');
  END IF;

  UPDATE public.disputes SET status = 'investigating', escalated_at = now() WHERE id = p_dispute_id;
  RETURN jsonb_build_object('status', 'investigating');
END; $$;

CREATE OR REPLACE FUNCTION public.escalate_dispute(p_dispute_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  UPDATE public.disputes SET status = 'investigating', escalated_at = now(), updated_at = now()
  WHERE id = p_dispute_id AND reporter_id = auth.uid() AND status = 'open'
    AND owner_responded_at IS NULL AND created_at < now() - interval '24 hours';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'You can ask eRefill to step in 24 hours after reporting if the station has not replied.';
  END IF;
  RETURN jsonb_build_object('status', 'investigating');
END; $$;

CREATE OR REPLACE FUNCTION public.admin_resolve_dispute(
  p_dispute_id uuid, p_refund_amount numeric, p_notes text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.disputes WHERE id = p_dispute_id AND status IN ('open', 'investigating')) THEN
    RAISE EXCEPTION 'This dispute is already closed.';
  END IF;
  UPDATE public.disputes SET resolved_by = auth.uid() WHERE id = p_dispute_id;
  PERFORM public.apply_dispute_refund(p_dispute_id, coalesce(p_refund_amount, 0), p_notes);
  IF coalesce(p_refund_amount, 0) = 0 THEN
    UPDATE public.disputes SET status = 'dismissed' WHERE id = p_dispute_id;
  END IF;
  RETURN jsonb_build_object('status', CASE WHEN coalesce(p_refund_amount, 0) > 0 THEN 'resolved' ELSE 'dismissed' END);
END; $$;

REVOKE ALL ON FUNCTION public.open_dispute(uuid, text, text, text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.open_dispute(uuid, text, text, text[]) TO authenticated;
REVOKE ALL ON FUNCTION public.owner_respond_dispute(uuid, boolean, text, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.owner_respond_dispute(uuid, boolean, text, numeric) TO authenticated;
REVOKE ALL ON FUNCTION public.escalate_dispute(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.escalate_dispute(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_resolve_dispute(uuid, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_resolve_dispute(uuid, numeric, text) TO authenticated;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- AI ordering assistant: per-user daily message limit (2026-11-05)
-- ==============================================================================
-- The order-assistant Edge Function records one row per message (with the
-- service role) and refuses more than 20 per user in 24 hours.
-- Users can read their own usage; nobody writes from the app.
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.assistant_usage (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  input_tokens integer NOT NULL DEFAULT 0,
  output_tokens integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_assistant_usage_user_time ON public.assistant_usage (user_id, created_at DESC);

ALTER TABLE public.assistant_usage ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users read own assistant usage" ON public.assistant_usage;
CREATE POLICY "Users read own assistant usage" ON public.assistant_usage
  FOR SELECT TO authenticated USING (user_id = auth.uid());
REVOKE INSERT, UPDATE, DELETE ON public.assistant_usage FROM anon, authenticated;
GRANT SELECT ON public.assistant_usage TO authenticated;

-- Shared fixtures for the SQL tests in this folder. Every test runs as
--   BEGIN; <scripts under test, BEGIN/COMMIT stripped>; _fixtures.sql; <test>; ROLLBACK;
-- through the Supabase MCP execute_sql tool, so nothing persists.
--
-- Fixture rows are inserted with triggers off (replica role) to skip station
-- setup checks; triggers are back on before the test body runs.
--
-- ids: owner ...a1, second owner ...a2, customer ...c1, rider ...d1,
--      admin ...e1, product ...b1 (₱19.60, owner a1).

SET LOCAL session_replication_role = replica;

INSERT INTO auth.users (id, instance_id, aud, role, email, raw_user_meta_data, raw_app_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_owner@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000a2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_owner2@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_cust@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_rider@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_admin@example.test', '{}', '{}', now(), now());

INSERT INTO public.profiles (id, role, full_name, station_name, station_availability, latitude, longitude)
VALUES
  ('00000000-0000-4000-8000-0000000000a1', 'owner', 'T Owner', 'T Station', 'open', 14.60, 121.00),
  ('00000000-0000-4000-8000-0000000000a2', 'owner', 'T Owner 2', 'T Station 2', 'open', 14.61, 121.01),
  ('00000000-0000-4000-8000-0000000000c1', 'customer', 'T Cust', NULL, 'open', 14.62, 121.02),
  ('00000000-0000-4000-8000-0000000000d1', 'rider', 'T Rider', NULL, 'open', NULL, NULL),
  ('00000000-0000-4000-8000-0000000000e1', 'admin', 'T Admin', NULL, 'open', NULL, NULL);

INSERT INTO public.owner_settings (owner_id, base_delivery_fee)
VALUES
  ('00000000-0000-4000-8000-0000000000a1', 5.4),
  ('00000000-0000-4000-8000-0000000000a2', 0);

INSERT INTO public.products (id, owner_id, name, price, is_available)
VALUES ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000a1', 'T Water', 19.6, true);

-- Fee config used by every test unless a test overrides it.
UPDATE public.system_config SET value = '{"enabled": true, "percent": 1, "fixed": 0}'::jsonb
WHERE key = 'platform_fee';

SET LOCAL session_replication_role = origin;

-- Helpers (temporary: dropped with the transaction).
CREATE OR REPLACE FUNCTION pg_temp.act_as(p_user uuid) RETURNS void
LANGUAGE sql AS $$
  SELECT set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text,
    true
  );
$$;

CREATE OR REPLACE FUNCTION pg_temp.place_order(p_method text, p_qty integer DEFAULT 1)
RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  RETURN public.create_order_atomic(
    jsonb_build_object(
      'owner_id', '00000000-0000-4000-8000-0000000000a1',
      'payment_method', p_method,
      'customer_name', 'T Cust',
      'customer_address', 'Test address',
      'customer_latitude', '14.6',
      'customer_longitude', '121.0'
    ),
    jsonb_build_array(jsonb_build_object(
      'product_id', '00000000-0000-4000-8000-0000000000b1',
      'quantity', p_qty,
      'product_name', 'T Water'
    ))
  );
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.assert_eq(p_label text, p_actual anyelement, p_expected anyelement)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF p_actual IS DISTINCT FROM p_expected THEN
    RAISE EXCEPTION '% — expected %, got %', p_label, p_expected, p_actual;
  END IF;
END;
$$;

-- Runs p_sql and fails unless it raises an error containing p_message.
CREATE OR REPLACE FUNCTION pg_temp.expect_error(p_label text, p_sql text, p_message text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    IF position(p_message IN SQLERRM) = 0 THEN
      RAISE EXCEPTION '% — expected error "%", got "%"', p_label, p_message, SQLERRM;
    END IF;
    RETURN;
  END;
  RAISE EXCEPTION '% — expected error "%", but it succeeded', p_label, p_message;
END;
$$;
-- Run: BEGIN; harden_signup_and_protected_columns.sql; _fixtures.sql; this file; ROLLBACK;

-- self_signup_cannot_claim_admin_or_rider
DO $$ BEGIN
  PERFORM pg_temp.assert_eq('self admin -> customer',
    public.resolve_signup_role('admin', false)::text, 'customer');
  PERFORM pg_temp.assert_eq('self rider -> customer',
    public.resolve_signup_role('rider', false)::text, 'customer');
  PERFORM pg_temp.assert_eq('self owner ok',
    public.resolve_signup_role('owner', false)::text, 'owner');
  PERFORM pg_temp.assert_eq('self junk -> customer',
    public.resolve_signup_role('superuser', false)::text, 'customer');
  PERFORM pg_temp.assert_eq('trusted rider ok',
    public.resolve_signup_role('rider', true)::text, 'rider');
  PERFORM pg_temp.assert_eq('trusted admin ok',
    public.resolve_signup_role('admin', true)::text, 'admin');
END $$;

-- owner_cannot_edit_own_rating
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1'); SET LOCAL ROLE authenticated;
  PERFORM pg_temp.expect_error('owner rating',
    $q$UPDATE public.profiles SET average_rating = 5, review_count = 99
       WHERE id = '00000000-0000-4000-8000-0000000000a1'$q$,
    'Unauthorized: You cannot alter protected account fields.');
END $$;

-- owner_cannot_self_verify
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1'); SET LOCAL ROLE authenticated;
  PERFORM pg_temp.expect_error('owner verify',
    $q$UPDATE public.profiles SET verification_status = 'approved'
       WHERE id = '00000000-0000-4000-8000-0000000000a1'$q$,
    'Unauthorized: You cannot alter protected account fields.');
END $$;

-- owner_can_still_edit_normal_fields
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1'); SET LOCAL ROLE authenticated;
  UPDATE public.profiles SET station_name = 'Renamed'
  WHERE id = '00000000-0000-4000-8000-0000000000a1';
  RESET ROLE;
  PERFORM pg_temp.assert_eq('rename',
    (SELECT station_name FROM public.profiles WHERE id = '00000000-0000-4000-8000-0000000000a1'), 'Renamed');
END $$;

-- review_trigger_still_updates_stats
DO $$ BEGIN
  RESET ROLE;
  SET LOCAL session_replication_role = replica;
  INSERT INTO public.orders (id, customer_id, owner_id, status, total_amount)
  VALUES ('00000000-0000-4000-8000-00000000f001', '00000000-0000-4000-8000-0000000000c1',
          '00000000-0000-4000-8000-0000000000a1', 'delivered', 50);
  SET LOCAL session_replication_role = origin;
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1'); SET LOCAL ROLE authenticated;
  INSERT INTO public.reviews (station_id, customer_id, order_id, rating)
  VALUES ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000c1',
          '00000000-0000-4000-8000-00000000f001', 4);
  RESET ROLE;
  PERFORM pg_temp.assert_eq('stats count',
    (SELECT review_count::bigint FROM public.profiles WHERE id = '00000000-0000-4000-8000-0000000000a1'), 1::bigint);
END $$;

-- admin_can_set_verification
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000e1'); SET LOCAL ROLE authenticated;
  UPDATE public.profiles SET verification_status = 'approved'
  WHERE id = '00000000-0000-4000-8000-0000000000a1';
  RESET ROLE;
  PERFORM pg_temp.assert_eq('admin verify',
    (SELECT verification_status FROM public.profiles WHERE id = '00000000-0000-4000-8000-0000000000a1'), 'approved');
END $$;

SELECT 'protected_columns_test: all passed' AS result;
ROLLBACK;

-- ===== delivery_quote_test =====
BEGIN;
-- ==============================================================================
-- Harden signup roles and protect trust columns on profiles (2026-11-05)
-- ==============================================================================
-- 1. Self-signup could claim role 'admin' or 'rider' through user metadata.
--    Only accounts created by a trusted server function (admin_create_user,
--    create_rider_account, admin_create_station) may get privileged roles.
--    Self-signups arrive through the Auth server, whose session user is
--    supabase_auth_admin; those are limited to customer/owner.
-- 2. Users could UPDATE their own average_rating / review_count /
--    reliability_score / flagged_count. Those are now writable only by admins
--    or by SECURITY DEFINER functions (e.g. update_station_stats()).
-- 3. Adds profiles.verification_status (used by identity verification), which is
--    protected the same way.
--
-- Run after: single_water_product_catalog.sql. Test: supabase/tests/protected_columns_test.sql
-- ==============================================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS verification_status text NOT NULL DEFAULT 'unverified';
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_verification_status_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_verification_status_check
  CHECK (verification_status IN ('unverified', 'pending', 'approved', 'rejected'));

-- 1. Role resolution -----------------------------------------------------------
CREATE OR REPLACE FUNCTION public.resolve_signup_role(p_requested text, p_trusted boolean)
RETURNS public.user_role
LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN p_requested IN ('customer', 'owner') THEN p_requested::public.user_role
    WHEN p_trusted AND p_requested IN ('rider', 'admin') THEN p_requested::public.user_role
    ELSE 'customer'::public.user_role
  END;
$$;
REVOKE ALL ON FUNCTION public.resolve_signup_role(text, boolean) FROM PUBLIC, anon, authenticated;

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
  -- 1. Role: self-signups (Auth server session) may only be customer or owner.
  v_role := public.resolve_signup_role(
    new.raw_user_meta_data->>'role',
    session_user <> 'supabase_auth_admin'
  );

  -- 2. Safe municipality enum resolution
  IF lower(trim(COALESCE(new.raw_user_meta_data->>'town', ''))) = 'cantilan' THEN
    v_town := 'Cantilan'::public.municipality;
  ELSIF lower(trim(COALESCE(new.raw_user_meta_data->>'town', ''))) = 'madrid' THEN
    v_town := 'Madrid'::public.municipality;
  ELSE
    v_town := NULL;
  END IF;

  v_complete_address := NULLIF(TRIM(COALESCE(new.raw_user_meta_data->>'complete_address', '')), '');

  -- 3. Names (Google OAuth sends 'name', 'given_name', 'family_name', 'picture')
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

  -- 5. Upsert profile
  INSERT INTO public.profiles (
    id, email, username, full_name, first_name, last_name, mi, suffix, role,
    phone, town, barangay, complete_address, landmark, station_name,
    avatar_url, latitude, longitude, primary_water_type
  )
  VALUES (
    new.id, new.email, v_username, v_full_name, v_first_name, v_last_name,
    new.raw_user_meta_data->>'mi', new.raw_user_meta_data->>'suffix', v_role,
    new.raw_user_meta_data->>'phone', v_town, new.raw_user_meta_data->>'barangay',
    v_complete_address, new.raw_user_meta_data->>'landmark',
    new.raw_user_meta_data->>'station_name', v_avatar_url,
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

-- 2. Protected trust columns -----------------------------------------------------
-- SECURITY INVOKER on purpose: current_user is 'authenticated'/'anon' for direct
-- client writes, and the function owner (postgres) inside SECURITY DEFINER
-- functions such as update_station_stats() and the admin RPCs.
CREATE OR REPLACE FUNCTION public.guard_profile_protected_columns()
RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;

  IF NEW.average_rating IS NOT DISTINCT FROM OLD.average_rating
    AND NEW.review_count IS NOT DISTINCT FROM OLD.review_count
    AND NEW.reliability_score IS NOT DISTINCT FROM OLD.reliability_score
    AND NEW.flagged_count IS NOT DISTINCT FROM OLD.flagged_count
    AND NEW.verification_status IS NOT DISTINCT FROM OLD.verification_status
  THEN
    RETURN NEW;
  END IF;

  IF public.is_admin() THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'Unauthorized: You cannot alter protected account fields.';
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_profile_protected_columns ON public.profiles;
CREATE TRIGGER trg_guard_profile_protected_columns
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.guard_profile_protected_columns();


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Delivery coverage: free-delivery zones + distance-based fees (2026-11-05)
-- ==============================================================================
-- Each station defines where delivery is free:
--   * within free_delivery_radius_km of the station (default 1 km), OR
--   * to any barangay listed in free_delivery_barangays, OR
--   * when the order has at least free_delivery_min_gallons water gallons.
-- Everywhere else pays the platform's per-km rate from
-- system_config.delivery_fee_config (rate_per_km, minimum_fee,
-- min_billable_distance_km, rounding_rule, enabled).
--
-- Distance = straight-line (haversine) x 1.3 road factor, so it approximates
-- real road distance without calling a routing service from the database.
--
-- Self-contained: does not depend on delivery_fee_config_rpcs.sql.
-- Run before: order_pricing_v3.sql. Test: supabase/tests/delivery_quote_test.sql
-- ==============================================================================

ALTER TABLE public.owner_settings
  ADD COLUMN IF NOT EXISTS free_delivery_radius_km numeric(4,1) NOT NULL DEFAULT 1.0,
  ADD COLUMN IF NOT EXISTS free_delivery_barangays text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS free_delivery_min_gallons integer;

ALTER TABLE public.owner_settings DROP CONSTRAINT IF EXISTS owner_settings_free_radius_check;
ALTER TABLE public.owner_settings ADD CONSTRAINT owner_settings_free_radius_check
  CHECK (free_delivery_radius_km >= 0 AND free_delivery_radius_km <= 10);
ALTER TABLE public.owner_settings DROP CONSTRAINT IF EXISTS owner_settings_free_min_gallons_check;
ALTER TABLE public.owner_settings ADD CONSTRAINT owner_settings_free_min_gallons_check
  CHECK (free_delivery_min_gallons IS NULL OR free_delivery_min_gallons BETWEEN 1 AND 100);

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS delivery_distance_km numeric(6,2),
  ADD COLUMN IF NOT EXISTS delivery_rate_per_km numeric(8,2),
  ADD COLUMN IF NOT EXISTS delivery_free_reason text;

-- Road factor applied to straight-line distance.
CREATE OR REPLACE FUNCTION public.delivery_road_distance_km(
  p_lat1 double precision, p_lng1 double precision,
  p_lat2 double precision, p_lng2 double precision
) RETURNS numeric
LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN p_lat1 IS NULL OR p_lng1 IS NULL OR p_lat2 IS NULL OR p_lng2 IS NULL THEN NULL
    ELSE round((
      2 * 6371 * asin(sqrt(
        power(sin(radians(p_lat2 - p_lat1) / 2), 2)
        + cos(radians(p_lat1)) * cos(radians(p_lat2))
          * power(sin(radians(p_lng2 - p_lng1) / 2), 2)
      )) * 1.3
    )::numeric, 2)
  END;
$$;

-- Fee for a distance outside the free zone, from the admin's config.
CREATE OR REPLACE FUNCTION public.delivery_fee_for_distance(p_km numeric)
RETURNS numeric
LANGUAGE plpgsql STABLE SET search_path TO 'public' AS $$
DECLARE
  v_cfg jsonb;
  v_rate numeric;
  v_min numeric;
  v_min_km numeric;
  v_rule text;
  v_fee numeric;
BEGIN
  SELECT value INTO v_cfg FROM public.system_config WHERE key = 'delivery_fee_config';
  v_cfg := coalesce(v_cfg, '{}'::jsonb);
  IF NOT coalesce((v_cfg->>'enabled')::boolean, true) THEN
    RETURN 0;
  END IF;
  v_rate := greatest(coalesce((v_cfg->>'rate_per_km')::numeric, 10), 0);
  v_min := greatest(coalesce((v_cfg->>'minimum_fee')::numeric, 20), 0);
  v_min_km := greatest(coalesce((v_cfg->>'min_billable_distance_km')::numeric, 1), 0);
  v_rule := lower(trim(coalesce(v_cfg->>'rounding_rule', 'exact')));

  IF p_km IS NULL THEN
    RETURN v_min;
  END IF;

  -- Same rule as CheckoutRules.calculateDeliveryFee in the app: the rounding
  -- rule applies to the billable distance; the fee is whole pesos.
  v_fee := greatest(p_km, v_min_km);
  v_fee := CASE
    WHEN v_rule IN ('ceil', 'round_up') THEN ceil(v_fee)
    WHEN v_rule IN ('round', 'round_nearest') THEN round(v_fee)
    ELSE v_fee
  END;
  IF v_rate <= 0 THEN
    RETURN 0;
  END IF;
  RETURN round(greatest(v_rate * v_fee, v_min));
END;
$$;

-- Quote shown at checkout and charged by create_order_atomic.
CREATE OR REPLACE FUNCTION public.compute_delivery_quote(
  p_station_id uuid,
  p_lat double precision,
  p_lng double precision,
  p_barangay text DEFAULT NULL,
  p_gallons integer DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_slat double precision;
  v_slng double precision;
  v_radius numeric;
  v_barangays text[];
  v_min_gallons integer;
  v_km numeric;
  v_reason text;
  v_cfg jsonb;
BEGIN
  SELECT coalesce(p.latitude, p.lat), coalesce(p.longitude, p.lng)
  INTO v_slat, v_slng
  FROM public.profiles p
  WHERE p.id = p_station_id AND p.role = 'owner';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Water refill station not found.';
  END IF;

  SELECT coalesce(os.free_delivery_radius_km, 1.0),
         coalesce(os.free_delivery_barangays, '{}'),
         os.free_delivery_min_gallons
  INTO v_radius, v_barangays, v_min_gallons
  FROM public.owner_settings os WHERE os.owner_id = p_station_id;
  v_radius := coalesce(v_radius, 1.0);
  v_barangays := coalesce(v_barangays, '{}');

  v_km := public.delivery_road_distance_km(v_slat, v_slng, p_lat, p_lng);

  IF v_km IS NOT NULL AND v_km <= v_radius THEN
    v_reason := 'radius';
  ELSIF p_barangay IS NOT NULL AND EXISTS (
    SELECT 1 FROM unnest(v_barangays) b
    WHERE lower(trim(b)) = lower(trim(p_barangay))
  ) THEN
    v_reason := 'barangay';
  ELSIF v_min_gallons IS NOT NULL AND coalesce(p_gallons, 0) >= v_min_gallons THEN
    v_reason := 'min_gallons';
  END IF;

  SELECT value INTO v_cfg FROM public.system_config WHERE key = 'delivery_fee_config';

  RETURN jsonb_build_object(
    'distance_km', v_km,
    'is_free', v_reason IS NOT NULL,
    'free_reason', v_reason,
    'fee', CASE WHEN v_reason IS NOT NULL THEN 0 ELSE public.delivery_fee_for_distance(v_km) END,
    'rate_per_km', coalesce((v_cfg->>'rate_per_km')::numeric, 10),
    'minimum_fee', coalesce((v_cfg->>'minimum_fee')::numeric, 20),
    'free_radius_km', v_radius,
    'free_barangays', to_jsonb(v_barangays),
    'free_min_gallons', v_min_gallons
  );
END;
$$;

REVOKE ALL ON FUNCTION public.compute_delivery_quote(uuid, double precision, double precision, text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.compute_delivery_quote(uuid, double precision, double precision, text, integer) TO authenticated;
REVOKE ALL ON FUNCTION public.delivery_fee_for_distance(numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delivery_fee_for_distance(numeric) TO authenticated;


NOTIFY pgrst, 'reload schema';
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


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Rider tips (2026-11-05)
-- ==============================================================================
-- Customers can add an optional tip (₱0–₱500, whole pesos) at checkout for
-- delivery orders. It is part of the single charge (COD or PayMongo), so no
-- second payment is needed, and 100% goes to the rider:
--   * excluded from the station SALE and from the 10% commission base
--   * booked as a RIDER_TIP ledger entry to the assigned rider
--   * if no rider was assigned (station delivered itself) it stays with the
--     station as part of the SALE
-- create_order_atomic reads p_order_data->>'tip_amount' (order_pricing_v3.sql).
--
-- Run before: order_pricing_v3.sql. Test: supabase/tests/rider_tips_test.sql
-- ==============================================================================

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS tip_amount numeric(10,2) NOT NULL DEFAULT 0;
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_tip_amount_check;
ALTER TABLE public.orders ADD CONSTRAINT orders_tip_amount_check
  CHECK (tip_amount >= 0 AND tip_amount <= 500);

CREATE OR REPLACE FUNCTION public.proc_finalize_order_finances()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    v_commission NUMERIC;
    v_fee NUMERIC := greatest(coalesce(NEW.platform_fee, 0), 0);
    v_tip NUMERIC := greatest(coalesce(NEW.tip_amount, 0), 0);
    v_rider_tip NUMERIC := 0;
BEGIN
    IF NEW.status = 'delivered' AND OLD.status != 'delivered' THEN
        -- The tip belongs to the rider; without a rider it stays in the sale.
        IF NEW.assigned_rider_id IS NOT NULL THEN
            v_rider_tip := v_tip;
        END IF;

        INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
        VALUES (NEW.owner_id, NEW.id, NEW.total_amount - v_fee - v_rider_tip, 'SALE', 'Order completion payment');

        IF v_fee > 0 THEN
            INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description, metadata)
            VALUES (
                NEW.owner_id, NEW.id, v_fee, 'SERVICE_FEE', 'Platform service fee',
                jsonb_build_object('payee', 'platform', 'payment_method', NEW.payment_method)
            );

            IF lower(coalesce(NEW.payment_method, 'cod')) IN ('cod', 'cash', 'credit') THEN
                PERFORM public.apply_wallet_entry(
                    NEW.owner_id, -v_fee, 'service_fee', NEW.id, NULL,
                    'Service fee for order ' || upper(substr(NEW.id::text, 1, 8))
                );
            END IF;
        END IF;

        -- Commission excludes the tip.
        v_commission := (NEW.total_amount - v_tip) * 0.10;

        IF NEW.assigned_rider_id IS NOT NULL THEN
            INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
            VALUES (NEW.assigned_rider_id, NEW.id, v_commission, 'COMMISSION', 'Delivery commission for order');

            IF v_rider_tip > 0 THEN
                INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
                VALUES (NEW.assigned_rider_id, NEW.id, v_rider_tip, 'RIDER_TIP', 'Customer tip');

                INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
                VALUES (
                    NEW.assigned_rider_id, 'system_alert', 'normal', 'You got a tip!',
                    'A customer tipped you PHP ' || trim(to_char(v_rider_tip, '999990')) || '. Thank you for the great service.',
                    jsonb_build_object('order_id', NEW.id, 'tip_amount', v_rider_tip)
                );
            END IF;
        END IF;

        INSERT INTO public.domain_events (event_type, payload, actor_id)
        VALUES ('ORDER_COMPLETED', jsonb_build_object(
            'order_id', NEW.id, 'total', NEW.total_amount,
            'rider_id', NEW.assigned_rider_id, 'tip', v_tip), auth.uid());
    END IF;
    RETURN NEW;
END;
$$;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Seller and customer ID verification (2026-11-05)
-- ==============================================================================
-- Users upload a government ID (front, back, selfie; owners also a business
-- permit) to the private bucket verification_docs under <their uid>/.
-- An admin reviews and approves or rejects. profiles.verification_status
-- (added and write-protected by harden_signup_and_protected_columns.sql) is
-- only changed by the RPCs below.
--
-- Gates (enforced in create_order_atomic, order_pricing_v3.sql):
--   * stations must be 'approved' to receive orders
--   * unverified customers: cash-on-delivery up to PHP 1,000 and at most
--     2 active COD orders; verified customers have no limit
-- Backfill: owners who already completed a delivery are approved (legacy).
--
-- Run after: harden_signup_and_protected_columns.sql
-- Run before: order_pricing_v3.sql. Test: supabase/tests/identity_verification_test.sql
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.identity_verifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role text NOT NULL,
  id_type text NOT NULL CHECK (id_type IN (
    'philsys', 'drivers_license', 'umid', 'passport', 'postal', 'voters', 'prc', 'other')),
  id_number_last4 text CHECK (id_number_last4 ~ '^[0-9A-Za-z]{4}$'),
  front_path text NOT NULL,
  back_path text,
  selfie_path text NOT NULL,
  business_permit_path text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  reviewer_id uuid REFERENCES public.profiles(id),
  reviewed_at timestamptz,
  rejection_reason text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_identity_verifications_user ON public.identity_verifications (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_identity_verifications_pending ON public.identity_verifications (created_at) WHERE status = 'pending';

ALTER TABLE public.identity_verifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users read own verifications" ON public.identity_verifications;
CREATE POLICY "Users read own verifications" ON public.identity_verifications
  FOR SELECT TO authenticated USING (auth.uid() = user_id OR public.is_admin());
-- Writes only through the RPCs below.
REVOKE INSERT, UPDATE, DELETE ON public.identity_verifications FROM anon, authenticated;
GRANT SELECT ON public.identity_verifications TO authenticated;

-- Private bucket, one folder per user.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('verification_docs', 'verification_docs', false, 8388608,
        ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
ON CONFLICT (id) DO UPDATE SET public = false;

DROP POLICY IF EXISTS "Verification docs: owner upload" ON storage.objects;
CREATE POLICY "Verification docs: owner upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'verification_docs' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "Verification docs: owner or admin read" ON storage.objects;
CREATE POLICY "Verification docs: owner or admin read" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'verification_docs'
         AND ((storage.foldername(name))[1] = auth.uid()::text OR public.is_admin()));

CREATE OR REPLACE FUNCTION public.submit_identity_verification(
  p_id_type text,
  p_id_number_last4 text,
  p_front_path text,
  p_back_path text,
  p_selfie_path text,
  p_business_permit_path text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_role text;
  v_status text;
  v_prefix text;
  v_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required.'; END IF;
  SELECT role::text, verification_status INTO v_role, v_status FROM public.profiles WHERE id = v_uid;
  IF v_role NOT IN ('customer', 'owner') THEN
    RAISE EXCEPTION 'Only customers and station owners verify their ID here.';
  END IF;
  IF v_status = 'approved' THEN RAISE EXCEPTION 'Your ID is already verified.'; END IF;
  IF v_status = 'pending' THEN RAISE EXCEPTION 'Your ID is already being reviewed.'; END IF;

  v_prefix := v_uid::text || '/';
  IF p_front_path IS NULL OR p_selfie_path IS NULL
     OR left(p_front_path, length(v_prefix)) <> v_prefix
     OR left(p_selfie_path, length(v_prefix)) <> v_prefix
     OR (p_back_path IS NOT NULL AND left(p_back_path, length(v_prefix)) <> v_prefix)
     OR (p_business_permit_path IS NOT NULL AND left(p_business_permit_path, length(v_prefix)) <> v_prefix) THEN
    RAISE EXCEPTION 'Upload your ID photos before submitting.';
  END IF;
  IF v_role = 'owner' AND p_business_permit_path IS NULL THEN
    RAISE EXCEPTION 'Stations must also upload a business or sanitary permit.';
  END IF;

  INSERT INTO public.identity_verifications (
    user_id, role, id_type, id_number_last4, front_path, back_path, selfie_path, business_permit_path)
  VALUES (v_uid, v_role, p_id_type, NULLIF(p_id_number_last4, ''), p_front_path, p_back_path,
          p_selfie_path, p_business_permit_path)
  RETURNING id INTO v_id;

  UPDATE public.profiles SET verification_status = 'pending' WHERE id = v_uid;
  RETURN jsonb_build_object('id', v_id, 'status', 'pending');
END; $$;

CREATE OR REPLACE FUNCTION public.admin_review_identity_verification(
  p_verification_id uuid,
  p_approve boolean,
  p_reason text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_row public.identity_verifications%ROWTYPE;
  v_status text := CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  IF NOT p_approve AND coalesce(trim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'Give the user a reason for the rejection.';
  END IF;

  UPDATE public.identity_verifications
  SET status = v_status, reviewer_id = auth.uid(), reviewed_at = now(),
      rejection_reason = CASE WHEN p_approve THEN NULL ELSE trim(p_reason) END
  WHERE id = p_verification_id AND status = 'pending'
  RETURNING * INTO v_row;
  IF NOT FOUND THEN RAISE EXCEPTION 'This verification was already reviewed.'; END IF;

  UPDATE public.profiles SET verification_status = v_status WHERE id = v_row.user_id;

  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (
    v_row.user_id, 'system_alert', 'high',
    CASE WHEN p_approve THEN 'Your ID is verified' ELSE 'ID verification needs another try' END,
    CASE WHEN p_approve
      THEN CASE WHEN v_row.role = 'owner'
        THEN 'Your station is verified and can now receive orders.'
        ELSE 'Your account is verified. Order limits are lifted.' END
      ELSE 'Reason: ' || trim(p_reason) || '. You can submit new photos.' END,
    jsonb_build_object('verification_id', v_row.id, 'status', v_status)
  );

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, new_value, metadata)
  VALUES (auth.uid(), 'identity_verification_' || v_status, 'identity_verifications', v_row.id::text,
          jsonb_build_object('status', v_status),
          jsonb_build_object('user_id', v_row.user_id, 'reason', p_reason));

  RETURN jsonb_build_object('id', v_row.id, 'status', v_status);
END; $$;

REVOKE ALL ON FUNCTION public.submit_identity_verification(text, text, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_identity_verification(text, text, text, text, text, text) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_review_identity_verification(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_review_identity_verification(uuid, boolean, text) TO authenticated;

-- Order gate helper, used by create_order_atomic.
CREATE OR REPLACE FUNCTION public.assert_order_allowed_by_verification(
  p_customer_id uuid, p_owner_id uuid, p_payment_method text, p_total numeric
) RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_owner_status text;
  v_customer_status text;
  v_active int;
BEGIN
  SELECT verification_status INTO v_owner_status FROM public.profiles WHERE id = p_owner_id;
  IF coalesce(v_owner_status, 'unverified') <> 'approved' THEN
    RAISE EXCEPTION 'This station is not verified yet and cannot take orders.';
  END IF;

  SELECT verification_status INTO v_customer_status FROM public.profiles WHERE id = p_customer_id;
  IF coalesce(v_customer_status, 'unverified') = 'approved'
     OR lower(coalesce(p_payment_method, 'cod')) NOT IN ('cod', 'cash') THEN
    RETURN;
  END IF;

  IF p_total > 1000 THEN
    RAISE EXCEPTION 'Verify your ID to place cash-on-delivery orders above PHP 1,000.';
  END IF;
  SELECT count(*) INTO v_active FROM public.orders
  WHERE customer_id = p_customer_id
    AND lower(coalesce(payment_method, 'cod')) IN ('cod', 'cash')
    AND status NOT IN ('delivered', 'cancelled', 'failed');
  IF v_active >= 2 THEN
    RAISE EXCEPTION 'Verify your ID to have more than 2 cash-on-delivery orders at a time.';
  END IF;
END; $$;
REVOKE ALL ON FUNCTION public.assert_order_allowed_by_verification(uuid, uuid, text, numeric) FROM PUBLIC, anon, authenticated;

-- Backfill: stations that already delivered orders keep working.
UPDATE public.profiles p SET verification_status = 'approved'
WHERE p.role = 'owner' AND p.verification_status = 'unverified'
  AND EXISTS (SELECT 1 FROM public.orders o WHERE o.owner_id = p.id AND o.status = 'delivered');


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- create_order_atomic v3 (2026-11-05)
-- ==============================================================================
-- Starts from the LIVE definition (pg_get_functiondef on 2026-11-05; note the
-- live function does not use price_order() from whole_peso_pricing.sql).
-- Changes:
--   * Delivery fee comes from compute_delivery_quote() (free zone or per-km),
--     never from the client and no longer from owner_settings.base_delivery_fee.
--   * Writes delivery_distance_km, delivery_rate_per_km, delivery_free_reason.
--   * Accessories (products.kind = 'accessory') are sold alongside water;
--     only water gallons count toward the free-delivery gallon threshold.
--   * Optional rider tip (tip_amount, ₱0–₱500) added to the total.
--   * ID verification gates: approved stations only; COD limits for
--     unverified customers.
-- This is the single place later features (accessories, tips, verification
-- gates) extend create_order_atomic. Do not redefine it in other scripts.
--
-- Run order: harden_signup_and_protected_columns.sql -> delivery_coverage.sql ->
--   station_accessories.sql -> rider_tips.sql -> identity_verification.sql -> this file.
-- Tests: supabase/tests/delivery_quote_test.sql, accessories_test.sql
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.create_order_atomic(p_order_data jsonb, p_items_data jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_customer_id uuid := auth.uid();
  v_owner_id uuid;
  v_payment_method text;
  v_idempotency_key public.orders.idempotency_key%TYPE;
  v_voucher_id uuid;
  v_order_id uuid;
  v_item record;
  v_product record;
  v_computed_subtotal numeric(10,2) := 0;
  v_delivery_fee numeric(10,2) := 0;
  v_platform_fee numeric(10,2) := 0;
  v_discount numeric(10,2) := 0;
  v_total_amount numeric(10,2) := 0;
  v_order_row public.orders%ROWTYPE;
  v_voucher public.customer_reward_vouchers%ROWTYPE;
  v_config jsonb;
  v_lat double precision;
  v_lng double precision;
  v_maintenance jsonb;
  v_is_maintenance boolean := false;
  v_customer_suspended boolean := false;
  v_owner_suspended boolean := false;
  v_gallons integer := 0;
  v_quote jsonb;
  v_tip numeric(10,2) := 0;
BEGIN
  SELECT value INTO v_maintenance
  FROM public.system_config
  WHERE key = 'maintenance_mode';

  IF v_maintenance IS NOT NULL THEN
    IF jsonb_typeof(v_maintenance) = 'boolean' THEN
      v_is_maintenance := v_maintenance::text::boolean;
    ELSIF jsonb_typeof(v_maintenance) = 'string' THEN
      v_is_maintenance :=
        lower(trim(both '"' from v_maintenance::text)) IN ('true', '1', 'yes');
    END IF;
  END IF;

  IF v_is_maintenance THEN
    RAISE EXCEPTION 'System is currently undergoing maintenance. New orders are temporarily paused.';
  END IF;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required to place an order.';
  END IF;

  SELECT coalesce(is_suspended, false) INTO v_customer_suspended
  FROM public.profiles
  WHERE id = v_customer_id AND role = 'customer';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Only customer accounts can place orders.';
  END IF;
  IF v_customer_suspended THEN
    RAISE EXCEPTION 'Your account has been suspended. Please contact customer support.';
  END IF;

  v_idempotency_key := NULLIF(p_order_data->>'idempotency_key', '');
  IF v_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_order_row
    FROM public.orders
    WHERE customer_id = v_customer_id
      AND idempotency_key = v_idempotency_key;

    IF FOUND THEN
      RETURN jsonb_build_object(
        'id', v_order_row.id,
        'subtotal', v_order_row.subtotal,
        'delivery_fee', v_order_row.delivery_fee,
        'platform_fee', v_order_row.platform_fee,
        'total_amount', v_order_row.total_amount,
        'status', v_order_row.status
      );
    END IF;
  END IF;

  v_owner_id := NULLIF(p_order_data->>'owner_id', '')::uuid;
  v_payment_method := lower(trim(coalesce(p_order_data->>'payment_method', 'cod')));
  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'Station owner ID is required.';
  END IF;

  SELECT coalesce(is_suspended, false) INTO v_owner_suspended
  FROM public.profiles
  WHERE id = v_owner_id AND role = 'owner';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Water refill station not found.';
  END IF;
  IF v_owner_suspended THEN
    RAISE EXCEPTION 'This water station is currently suspended by administration.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = v_owner_id
      AND role = 'owner'
      AND coalesce(station_availability, 'open') = 'open'
  ) THEN
    RAISE EXCEPTION 'This water station is currently closed or unavailable.';
  END IF;
  IF NOT public.is_station_payment_method_available(v_owner_id, v_payment_method) THEN
    RAISE EXCEPTION 'This payment method is not available for this station.';
  END IF;

  FOR v_item IN
    SELECT * FROM jsonb_to_recordset(p_items_data) AS x(
      product_id uuid,
      quantity integer,
      product_name text
    )
  LOOP
    IF v_item.quantity <= 0 THEN
      RAISE EXCEPTION 'Invalid quantity for item %', v_item.product_name;
    END IF;

    SELECT * INTO v_product
    FROM public.products
    WHERE id = v_item.product_id
      AND owner_id = v_owner_id
      AND is_available = true;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Product % is unavailable at this station.', v_item.product_name;
    END IF;

    v_computed_subtotal :=
      v_computed_subtotal + (v_product.price * v_item.quantity);
    -- Only water counts toward the free-delivery gallon threshold.
    IF v_product.kind = 'water' THEN
      v_gallons := v_gallons + v_item.quantity;
    END IF;
  END LOOP;

  IF v_computed_subtotal <= 0 THEN
    RAISE EXCEPTION 'Cart cannot be empty.';
  END IF;

  v_lat := NULLIF(p_order_data->>'customer_latitude', '')::double precision;
  v_lng := NULLIF(p_order_data->>'customer_longitude', '')::double precision;

  -- Delivery fee: server-side quote (free zone or per-km). Client fee ignored.
  v_quote := public.compute_delivery_quote(
    v_owner_id, v_lat, v_lng,
    NULLIF(p_order_data->>'customer_barangay', ''),
    v_gallons
  );
  v_delivery_fee := coalesce((v_quote->>'fee')::numeric, 0);

  v_config := public.get_platform_fee_config();
  IF coalesce((v_config->>'enabled')::boolean, false) THEN
    v_platform_fee := round(
      ((v_computed_subtotal + v_delivery_fee)
        * coalesce((v_config->>'percent')::numeric, 0) / 100)
        + coalesce((v_config->>'fixed')::numeric, 0),
      2
    );
    v_platform_fee := greatest(v_platform_fee, 0);
  END IF;

  v_voucher_id := NULLIF(p_order_data->>'voucher_id', '')::uuid;
  IF v_voucher_id IS NOT NULL THEN
    SELECT * INTO v_voucher
    FROM public.customer_reward_vouchers
    WHERE id = v_voucher_id
      AND user_id = v_customer_id
      AND is_used = false
      AND expires_at > now()
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'This reward voucher is no longer available. Refresh your vouchers and try again.';
    END IF;

    IF v_voucher.is_delivery_discount THEN
      v_discount := least(
        greatest(v_voucher.discount_amount, 0),
        v_delivery_fee
      );
    ELSE
      v_discount := least(
        greatest(v_voucher.discount_amount, 0),
        v_computed_subtotal + v_delivery_fee + v_platform_fee
      );
    END IF;
  END IF;

  -- Optional rider tip: whole pesos, ₱0–₱500, paid on top (no fees, no voucher).
  v_tip := round(coalesce(NULLIF(p_order_data->>'tip_amount', '')::numeric, 0));
  IF v_tip < 0 OR v_tip > 500 THEN
    RAISE EXCEPTION 'Tip must be between PHP 0 and PHP 500.';
  END IF;

  v_total_amount := greatest(
    v_computed_subtotal + v_delivery_fee + v_platform_fee - v_discount,
    0
  ) + v_tip;

  -- ID verification gates (identity_verification.sql).
  PERFORM public.assert_order_allowed_by_verification(
    v_customer_id, v_owner_id, v_payment_method, v_total_amount
  );

  INSERT INTO public.orders (
    id,
    customer_id,
    owner_id,
    station_name,
    customer_name,
    customer_phone,
    customer_address,
    customer_barangay,
    customer_municipality,
    customer_landmark,
    idempotency_key,
    subtotal,
    delivery_fee,
    platform_fee,
    total_amount,
    payment_method,
    payment_status,
    notes,
    region_id,
    customer_latitude,
    customer_longitude,
    delivery_lat,
    delivery_lng,
    delivery_latitude,
    delivery_longitude,
    delivery_distance_km,
    delivery_rate_per_km,
    delivery_free_reason,
    tip_amount,
    items,
    status
  ) VALUES (
    coalesce(
      NULLIF(p_order_data->>'id', '')::uuid,
      gen_random_uuid()
    ),
    v_customer_id,
    v_owner_id,
    coalesce(p_order_data->>'station_name', 'Water Station'),
    p_order_data->>'customer_name',
    p_order_data->>'customer_phone',
    p_order_data->>'customer_address',
    p_order_data->>'customer_barangay',
    p_order_data->>'customer_municipality',
    p_order_data->>'customer_landmark',
    v_idempotency_key,
    v_computed_subtotal,
    v_delivery_fee,
    v_platform_fee,
    v_total_amount,
    v_payment_method,
    'pending',
    p_order_data->>'notes',
    NULLIF(p_order_data->>'region_id', '')::uuid,
    v_lat,
    v_lng,
    v_lat,
    v_lng,
    v_lat,
    v_lng,
    (v_quote->>'distance_km')::numeric,
    (v_quote->>'rate_per_km')::numeric,
    v_quote->>'free_reason',
    v_tip,
    coalesce(p_items_data, '[]'::jsonb),
    'pending'
  )
  ON CONFLICT DO NOTHING
  RETURNING * INTO v_order_row;

  IF NOT FOUND THEN
    IF v_idempotency_key IS NOT NULL THEN
      SELECT * INTO v_order_row
      FROM public.orders
      WHERE customer_id = v_customer_id
        AND idempotency_key = v_idempotency_key;

      IF FOUND THEN
        RETURN jsonb_build_object(
          'id', v_order_row.id,
          'subtotal', v_order_row.subtotal,
          'delivery_fee', v_order_row.delivery_fee,
          'platform_fee', v_order_row.platform_fee,
          'total_amount', v_order_row.total_amount,
          'status', v_order_row.status
        );
      END IF;
    END IF;
    RAISE EXCEPTION 'Order could not be created because of a conflicting order record.';
  END IF;

  v_order_id := v_order_row.id;

  FOR v_item IN
    SELECT * FROM jsonb_to_recordset(p_items_data) AS x(
      product_id uuid,
      quantity integer,
      product_name text
    )
  LOOP
    SELECT * INTO v_product FROM public.products WHERE id = v_item.product_id;
    INSERT INTO public.order_items (
      order_id,
      product_id,
      product_name,
      quantity,
      price_at_purchase,
      subtotal
    ) VALUES (
      v_order_id,
      v_item.product_id,
      v_product.name,
      v_item.quantity,
      v_product.price,
      (v_product.price * v_item.quantity)
    );
  END LOOP;

  IF v_voucher_id IS NOT NULL THEN
    UPDATE public.customer_reward_vouchers
    SET is_used = true
    WHERE id = v_voucher_id
      AND user_id = v_customer_id
      AND is_used = false;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'This reward voucher was already used by another order.';
    END IF;
  END IF;

  INSERT INTO public.system_notifications (
    user_id,
    type,
    priority,
    title,
    content,
    metadata
  ) VALUES (
    v_owner_id,
    'system_alert',
    'high',
    'New Refill Order',
    coalesce(p_order_data->>'customer_name', 'A customer')
      || ' placed a new refill order of PHP '
      || trim(to_char(v_total_amount, '999999990.00'))
      || ' (' || upper(coalesce(p_order_data->>'payment_method', 'cod')) || ').',
    jsonb_build_object(
      'order_id', v_order_id,
      'status', 'pending',
      'total_amount', v_total_amount
    )
  );

  RETURN jsonb_build_object(
    'id', v_order_id,
    'subtotal', v_computed_subtotal,
    'delivery_fee', v_delivery_fee,
    'delivery_distance_km', (v_quote->>'distance_km')::numeric,
    'delivery_free_reason', v_quote->>'free_reason',
    'platform_fee', v_platform_fee,
    'discount_amount', v_discount,
    'tip_amount', v_tip,
    'total_amount', v_total_amount,
    'status', 'pending'
  );
END;
$function$;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Rider live location privacy (2026-11-05)
-- ==============================================================================
-- rider_locations was readable by everyone ("Public can view rider
-- locations"). Now only these can read a rider's points:
--   * the rider, admins
--   * the customer or station of an order that rider is delivering right now
--     (assigned_to_rider / out_for_delivery)
-- After delivery the customer loses access. Points older than 24 h are purged
-- hourly (pg_cron, when the extension is available).
-- Test: supabase/tests/rider_live_location_test.sql
-- ==============================================================================

DROP POLICY IF EXISTS "Public can view rider locations" ON public.rider_locations;
DROP POLICY IF EXISTS "Rider location visible to active delivery parties" ON public.rider_locations;
CREATE POLICY "Rider location visible to active delivery parties" ON public.rider_locations
  FOR SELECT TO authenticated
  USING (
    rider_id = auth.uid()
    OR public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.orders o
      WHERE (o.assigned_rider_id = rider_locations.rider_id OR o.rider_id = rider_locations.rider_id)
        AND o.status IN ('assigned_to_rider', 'out_for_delivery')
        AND (o.customer_id = auth.uid() OR o.owner_id = auth.uid())
    )
  );

DROP POLICY IF EXISTS "Riders can update their own location" ON public.rider_locations;
CREATE POLICY "Riders can update their own location" ON public.rider_locations
  FOR INSERT TO authenticated
  WITH CHECK (rider_id = auth.uid());
REVOKE ALL ON public.rider_locations FROM anon;

CREATE OR REPLACE FUNCTION public.purge_old_rider_locations()
RETURNS integer
LANGUAGE sql SECURITY DEFINER SET search_path TO 'public' AS $$
  WITH d AS (
    DELETE FROM public.rider_locations WHERE "timestamp" < now() - interval '24 hours' RETURNING 1
  ) SELECT count(*)::int FROM d;
$$;
REVOKE ALL ON FUNCTION public.purge_old_rider_locations() FROM PUBLIC, anon, authenticated;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'purge_old_rider_locations';
    PERFORM cron.schedule('purge_old_rider_locations', '7 * * * *', 'SELECT public.purge_old_rider_locations()');
  END IF;
END $$;

-- ==============================================================================
-- Smart refill reminders (2026-11-05)
-- ==============================================================================
-- Learns each customer's refill rhythm (median days between their last
-- delivered orders, needs >= 3 orders) and reminds them a day before they
-- usually reorder. At most one reminder per 3 days, never while an order is
-- active, and only when profiles.refill_reminders_enabled.
--   * customer_refill_rhythm()  -> for the app's home banner (current user)
--   * send_refill_reminders()   -> daily 9:00 PH pg_cron job, inserts notifications
-- Test: supabase/tests/refill_reminders_test.sql
-- ==============================================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS refill_reminders_enabled boolean NOT NULL DEFAULT true;

CREATE OR REPLACE FUNCTION public.refill_rhythm_for(p_customer_id uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  WITH recent AS (
    SELECT created_at, owner_id, station_name
    FROM public.orders
    WHERE customer_id = p_customer_id AND status = 'delivered'
    ORDER BY created_at DESC
    LIMIT 6
  ), gaps AS (
    SELECT extract(epoch FROM (created_at - lead(created_at) OVER (ORDER BY created_at DESC))) / 86400.0 AS days
    FROM recent
  ), stats AS (
    SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY days) AS median_days,
           count(*) AS gap_count
    FROM gaps WHERE days IS NOT NULL AND days > 0.5
  ), last AS (
    SELECT * FROM recent ORDER BY created_at DESC LIMIT 1
  )
  SELECT CASE
    WHEN (SELECT gap_count FROM stats) < 2 THEN jsonb_build_object('has_rhythm', false)
    ELSE jsonb_build_object(
      'has_rhythm', true,
      'median_days', round((SELECT median_days FROM stats)::numeric, 1),
      'last_order_at', (SELECT created_at FROM last),
      'station_id', (SELECT owner_id FROM last),
      'station_name', (SELECT station_name FROM last),
      'due_at', (SELECT created_at FROM last)
                + make_interval(secs => greatest((SELECT median_days FROM stats) - 1, 1) * 86400),
      'is_due', now() >= (SELECT created_at FROM last)
                + make_interval(secs => greatest((SELECT median_days FROM stats) - 1, 1) * 86400),
      'has_active_order', EXISTS (
        SELECT 1 FROM public.orders
        WHERE customer_id = p_customer_id
          AND status NOT IN ('delivered', 'cancelled', 'failed'))
    )
  END;
$$;
REVOKE ALL ON FUNCTION public.refill_rhythm_for(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.customer_refill_rhythm()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT CASE WHEN auth.uid() IS NULL THEN '{"has_rhythm": false}'::jsonb
              ELSE public.refill_rhythm_for(auth.uid()) END;
$$;
REVOKE ALL ON FUNCTION public.customer_refill_rhythm() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.customer_refill_rhythm() TO authenticated;

CREATE OR REPLACE FUNCTION public.send_refill_reminders()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_row record;
  v_r jsonb;
  v_sent integer := 0;
BEGIN
  FOR v_row IN
    SELECT p.id FROM public.profiles p
    WHERE p.role = 'customer' AND p.refill_reminders_enabled AND NOT coalesce(p.is_suspended, false)
  LOOP
    v_r := public.refill_rhythm_for(v_row.id);
    CONTINUE WHEN NOT coalesce((v_r->>'has_rhythm')::boolean, false)
               OR NOT (v_r->>'is_due')::boolean
               OR (v_r->>'has_active_order')::boolean;
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM public.system_notifications n
      WHERE n.user_id = v_row.id
        AND n.metadata->>'kind' = 'refill_reminder'
        AND n.created_at > now() - interval '3 days');

    INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
    VALUES (
      v_row.id, 'system_alert', 'normal', 'Time for a refill?',
      'You usually reorder every ' || round((v_r->>'median_days')::numeric) || ' days. '
        || 'Tap to reorder from ' || coalesce(v_r->>'station_name', 'your station') || '.',
      jsonb_build_object('kind', 'refill_reminder', 'station_id', v_r->>'station_id')
    );
    v_sent := v_sent + 1;
  END LOOP;
  RETURN v_sent;
END; $$;
REVOKE ALL ON FUNCTION public.send_refill_reminders() FROM PUBLIC, anon, authenticated;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'send_refill_reminders';
    -- 9:00 Asia/Manila = 01:00 UTC, so reminders arrive in the morning.
    PERFORM cron.schedule('send_refill_reminders', '0 1 * * *', 'SELECT public.send_refill_reminders()');
  END IF;
END $$;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Water quality transparency (2026-11-05)
-- ==============================================================================
-- Stations upload lab test results and permits (bacteriological /
-- physical-chemical water analysis, sanitary permit, business permit) with
-- issue and expiry dates. Admins approve them; approved, unexpired lab tests
-- give the station a "Water tested" badge and a small ranking boost.
-- Files live in the private verification_docs bucket under <uid>/certs/.
-- Approved certificate files are viewable by any signed-in user.
-- Daily job: marks expired certificates and warns owners 14 days ahead.
--
-- Run after: identity_verification.sql (bucket). Test: supabase/tests/water_quality_certs_test.sql
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.station_certifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  cert_type text NOT NULL CHECK (cert_type IN (
    'bacteriological', 'physical_chemical', 'sanitary_permit', 'business_permit')),
  issued_on date NOT NULL,
  expires_on date NOT NULL,
  file_path text NOT NULL,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected', 'expired')),
  reviewer_id uuid REFERENCES public.profiles(id),
  reviewed_at timestamptz,
  rejection_reason text,
  expiry_warned_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (expires_on > issued_on)
);
CREATE INDEX IF NOT EXISTS idx_station_certs_owner ON public.station_certifications (owner_id, status);

ALTER TABLE public.station_certifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Approved certs are public, owners see their own" ON public.station_certifications;
CREATE POLICY "Approved certs are public, owners see their own" ON public.station_certifications
  FOR SELECT TO authenticated
  USING (status = 'approved' OR owner_id = auth.uid() OR public.is_admin());
REVOKE INSERT, UPDATE, DELETE ON public.station_certifications FROM anon, authenticated;
GRANT SELECT ON public.station_certifications TO authenticated;

-- Approved certificate files are readable by signed-in users.
DROP POLICY IF EXISTS "Verification docs: approved certs readable" ON storage.objects;
CREATE POLICY "Verification docs: approved certs readable" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'verification_docs' AND EXISTS (
    SELECT 1 FROM public.station_certifications c
    WHERE c.file_path = storage.objects.name AND c.status = 'approved'));

CREATE OR REPLACE FUNCTION public.submit_station_certification(
  p_cert_type text, p_issued_on date, p_expires_on date, p_file_path text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_uid AND role = 'owner') THEN
    RAISE EXCEPTION 'Only station owners upload certificates.';
  END IF;
  IF p_file_path IS NULL OR left(p_file_path, length(v_uid::text) + 7) <> v_uid::text || '/certs/' THEN
    RAISE EXCEPTION 'Upload the certificate file first.';
  END IF;
  IF p_expires_on <= current_date THEN
    RAISE EXCEPTION 'This certificate has already expired.';
  END IF;
  IF p_issued_on > current_date THEN
    RAISE EXCEPTION 'The issue date cannot be in the future.';
  END IF;
  INSERT INTO public.station_certifications (owner_id, cert_type, issued_on, expires_on, file_path)
  VALUES (v_uid, p_cert_type, p_issued_on, p_expires_on, p_file_path)
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('id', v_id, 'status', 'pending');
END; $$;

CREATE OR REPLACE FUNCTION public.admin_review_station_certification(
  p_cert_id uuid, p_approve boolean, p_reason text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_row public.station_certifications%ROWTYPE;
  v_status text := CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  IF NOT p_approve AND coalesce(trim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'Give the station a reason for the rejection.';
  END IF;
  UPDATE public.station_certifications
  SET status = v_status, reviewer_id = auth.uid(), reviewed_at = now(),
      rejection_reason = CASE WHEN p_approve THEN NULL ELSE trim(p_reason) END
  WHERE id = p_cert_id AND status = 'pending'
  RETURNING * INTO v_row;
  IF NOT FOUND THEN RAISE EXCEPTION 'This certificate was already reviewed.'; END IF;

  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (v_row.owner_id, 'system_alert', 'normal',
    CASE WHEN p_approve THEN 'Certificate approved' ELSE 'Certificate rejected' END,
    CASE WHEN p_approve THEN 'Customers can now see your certificate.'
         ELSE 'Reason: ' || trim(p_reason) END,
    jsonb_build_object('certificate_id', v_row.id, 'status', v_status));
  RETURN jsonb_build_object('id', v_row.id, 'status', v_status);
END; $$;

REVOKE ALL ON FUNCTION public.submit_station_certification(text, date, date, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_station_certification(text, date, date, text) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_review_station_certification(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_review_station_certification(uuid, boolean, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.expire_station_certifications()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_n integer;
BEGIN
  UPDATE public.station_certifications SET status = 'expired'
  WHERE status = 'approved' AND expires_on <= current_date;
  GET DIAGNOSTICS v_n = ROW_COUNT;

  WITH soon AS (
    UPDATE public.station_certifications SET expiry_warned_at = now()
    WHERE status = 'approved' AND expiry_warned_at IS NULL
      AND expires_on <= current_date + 14
    RETURNING owner_id, id, cert_type, expires_on
  )
  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  SELECT owner_id, 'system_alert', 'high', 'Certificate expiring soon',
         'Your ' || replace(cert_type, '_', ' ') || ' certificate expires on '
           || to_char(expires_on, 'Mon DD, YYYY') || '. Upload a new one to keep your badge.',
         jsonb_build_object('certificate_id', id)
  FROM soon;
  RETURN v_n;
END; $$;
REVOKE ALL ON FUNCTION public.expire_station_certifications() FROM PUBLIC, anon, authenticated;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'expire_station_certifications';
    PERFORM cron.schedule('expire_station_certifications', '15 16 * * *', 'SELECT public.expire_station_certifications()');
  END IF;
END $$;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Order disputes and refunds (2026-11-05)
-- ==============================================================================
-- Extends the existing public.disputes table (status enum: open,
-- investigating, resolved, dismissed) with the customer -> station -> admin
-- flow:
--   1. Customer opens a dispute within 48 h of delivery, one per order,
--      with optional photo evidence (private bucket dispute_evidence).
--   2. Station accepts (refund amount) -> resolved, or explains -> the
--      dispute is escalated ('investigating') for an admin.
--   3. Customer may escalate if the station has not answered in 24 h.
--   4. Admin resolves with an optional refund, or dismisses.
-- A granted refund books a REFUND ledger entry against the station, notifies
-- the customer, and refunds against the station increase flagged_count.
-- Money movement: COD refunds are returned by the station in cash; online
-- payments are refunded by the admin in PayMongo (orders.payment_status is
-- set to 'refunded' when the full total is refunded).
--
-- Test: supabase/tests/order_disputes_test.sql
-- ==============================================================================

ALTER TABLE public.disputes
  ADD COLUMN IF NOT EXISTS evidence_paths text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS owner_response text,
  ADD COLUMN IF NOT EXISTS owner_responded_at timestamptz,
  ADD COLUMN IF NOT EXISTS refund_amount numeric(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS escalated_at timestamptz;
ALTER TABLE public.disputes DROP CONSTRAINT IF EXISTS disputes_reason_check;
ALTER TABLE public.disputes ADD CONSTRAINT disputes_reason_check CHECK (reason IN (
  'missing_items', 'wrong_item', 'quality', 'damaged', 'not_delivered', 'overcharged', 'other'));
ALTER TABLE public.disputes DROP CONSTRAINT IF EXISTS disputes_refund_check;
ALTER TABLE public.disputes ADD CONSTRAINT disputes_refund_check CHECK (refund_amount >= 0);
CREATE UNIQUE INDEX IF NOT EXISTS disputes_one_per_order ON public.disputes (order_id);

-- Owners no longer update disputes directly; they use owner_respond_dispute.
DROP POLICY IF EXISTS "Owners can update disputes for their station" ON public.disputes;
REVOKE INSERT, DELETE ON public.disputes FROM anon, authenticated;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('dispute_evidence', 'dispute_evidence', false, 8388608,
        ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO UPDATE SET public = false;
DROP POLICY IF EXISTS "Dispute evidence: reporter upload" ON storage.objects;
CREATE POLICY "Dispute evidence: reporter upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'dispute_evidence' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "Dispute evidence: parties read" ON storage.objects;
CREATE POLICY "Dispute evidence: parties read" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'dispute_evidence' AND (
    (storage.foldername(name))[1] = auth.uid()::text
    OR public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.disputes d JOIN public.orders o ON o.id = d.order_id
      WHERE storage.objects.name = ANY (d.evidence_paths) AND o.owner_id = auth.uid())));

CREATE OR REPLACE FUNCTION public.open_dispute(
  p_order_id uuid, p_reason text, p_description text, p_evidence_paths text[] DEFAULT '{}'
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_order public.orders%ROWTYPE;
  v_done_at timestamptz;
  v_id uuid;
  v_path text;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id AND customer_id = v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order not found.'; END IF;
  IF v_order.status::text <> 'delivered' THEN
    RAISE EXCEPTION 'You can report a problem once the order is delivered.';
  END IF;
  v_done_at := coalesce(v_order.actual_completion_at, v_order.updated_at, v_order.created_at);
  IF v_done_at < now() - interval '48 hours' THEN
    RAISE EXCEPTION 'Problems must be reported within 48 hours of delivery.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.disputes WHERE order_id = p_order_id) THEN
    RAISE EXCEPTION 'A problem was already reported for this order.';
  END IF;
  IF coalesce(trim(p_description), '') = '' THEN
    RAISE EXCEPTION 'Tell the station what went wrong.';
  END IF;
  FOREACH v_path IN ARRAY coalesce(p_evidence_paths, '{}') LOOP
    IF left(v_path, length(v_uid::text) + 1) <> v_uid::text || '/' THEN
      RAISE EXCEPTION 'Invalid evidence photo.';
    END IF;
  END LOOP;

  INSERT INTO public.disputes (order_id, reporter_id, reason, description, status, evidence_paths)
  VALUES (p_order_id, v_uid, p_reason, trim(p_description), 'open', coalesce(p_evidence_paths, '{}'))
  RETURNING id INTO v_id;

  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (v_order.owner_id, 'system_alert', 'high', 'A customer reported a problem',
    'Order #' || upper(substr(p_order_id::text, 1, 8)) || ': ' || replace(p_reason, '_', ' ')
      || '. Please respond within 24 hours.',
    jsonb_build_object('dispute_id', v_id, 'order_id', p_order_id));
  RETURN jsonb_build_object('id', v_id, 'status', 'open');
END; $$;

-- Shared by station and admin resolutions.
CREATE OR REPLACE FUNCTION public.apply_dispute_refund(p_dispute_id uuid, p_amount numeric, p_note text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_d public.disputes%ROWTYPE;
  v_o public.orders%ROWTYPE;
BEGIN
  SELECT * INTO v_d FROM public.disputes WHERE id = p_dispute_id;
  SELECT * INTO v_o FROM public.orders WHERE id = v_d.order_id;
  IF p_amount < 0 OR p_amount > v_o.total_amount THEN
    RAISE EXCEPTION 'Refund must be between PHP 0 and the order total.';
  END IF;
  UPDATE public.disputes SET refund_amount = p_amount, status = 'resolved',
         resolution_notes = p_note, updated_at = now()
  WHERE id = p_dispute_id;
  IF p_amount > 0 THEN
    INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
    VALUES (v_o.owner_id, v_o.id, -p_amount, 'REFUND', 'Refund for reported problem');
    UPDATE public.profiles SET flagged_count = coalesce(flagged_count, 0) + 1 WHERE id = v_o.owner_id;
    IF p_amount >= v_o.total_amount THEN
      UPDATE public.orders SET payment_status = 'refunded' WHERE id = v_o.id;
    END IF;
  END IF;
  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (v_d.reporter_id, 'system_alert', 'high',
    CASE WHEN p_amount > 0 THEN 'Refund approved' ELSE 'Your report was reviewed' END,
    CASE WHEN p_amount > 0
      THEN 'PHP ' || trim(to_char(p_amount, '999990.00')) || ' will be returned '
        || CASE WHEN lower(coalesce(v_o.payment_method, 'cod')) IN ('cod', 'cash')
                THEN 'by the station in cash.' ELSE 'to your original payment method.' END
      ELSE coalesce(p_note, 'No refund was given.') END,
    jsonb_build_object('dispute_id', p_dispute_id, 'order_id', v_o.id, 'refund_amount', p_amount));
END; $$;
REVOKE ALL ON FUNCTION public.apply_dispute_refund(uuid, numeric, text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.owner_respond_dispute(
  p_dispute_id uuid, p_accept boolean, p_response text, p_refund_amount numeric DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_d public.disputes%ROWTYPE;
BEGIN
  SELECT d.* INTO v_d FROM public.disputes d JOIN public.orders o ON o.id = d.order_id
  WHERE d.id = p_dispute_id AND o.owner_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Dispute not found.'; END IF;
  IF v_d.status::text <> 'open' OR v_d.owner_responded_at IS NOT NULL THEN
    RAISE EXCEPTION 'This dispute was already answered.';
  END IF;
  IF coalesce(trim(p_response), '') = '' THEN RAISE EXCEPTION 'Write a reply to the customer.'; END IF;

  UPDATE public.disputes SET owner_response = trim(p_response), owner_responded_at = now(), updated_at = now()
  WHERE id = p_dispute_id;

  IF p_accept THEN
    PERFORM public.apply_dispute_refund(p_dispute_id, coalesce(p_refund_amount, 0), 'Station: ' || trim(p_response));
    RETURN jsonb_build_object('status', 'resolved');
  END IF;

  UPDATE public.disputes SET status = 'investigating', escalated_at = now() WHERE id = p_dispute_id;
  RETURN jsonb_build_object('status', 'investigating');
END; $$;

CREATE OR REPLACE FUNCTION public.escalate_dispute(p_dispute_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  UPDATE public.disputes SET status = 'investigating', escalated_at = now(), updated_at = now()
  WHERE id = p_dispute_id AND reporter_id = auth.uid() AND status = 'open'
    AND owner_responded_at IS NULL AND created_at < now() - interval '24 hours';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'You can ask eRefill to step in 24 hours after reporting if the station has not replied.';
  END IF;
  RETURN jsonb_build_object('status', 'investigating');
END; $$;

CREATE OR REPLACE FUNCTION public.admin_resolve_dispute(
  p_dispute_id uuid, p_refund_amount numeric, p_notes text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.disputes WHERE id = p_dispute_id AND status IN ('open', 'investigating')) THEN
    RAISE EXCEPTION 'This dispute is already closed.';
  END IF;
  UPDATE public.disputes SET resolved_by = auth.uid() WHERE id = p_dispute_id;
  PERFORM public.apply_dispute_refund(p_dispute_id, coalesce(p_refund_amount, 0), p_notes);
  IF coalesce(p_refund_amount, 0) = 0 THEN
    UPDATE public.disputes SET status = 'dismissed' WHERE id = p_dispute_id;
  END IF;
  RETURN jsonb_build_object('status', CASE WHEN coalesce(p_refund_amount, 0) > 0 THEN 'resolved' ELSE 'dismissed' END);
END; $$;

REVOKE ALL ON FUNCTION public.open_dispute(uuid, text, text, text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.open_dispute(uuid, text, text, text[]) TO authenticated;
REVOKE ALL ON FUNCTION public.owner_respond_dispute(uuid, boolean, text, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.owner_respond_dispute(uuid, boolean, text, numeric) TO authenticated;
REVOKE ALL ON FUNCTION public.escalate_dispute(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.escalate_dispute(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_resolve_dispute(uuid, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_resolve_dispute(uuid, numeric, text) TO authenticated;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- AI ordering assistant: per-user daily message limit (2026-11-05)
-- ==============================================================================
-- The order-assistant Edge Function records one row per message (with the
-- service role) and refuses more than 20 per user in 24 hours.
-- Users can read their own usage; nobody writes from the app.
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.assistant_usage (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  input_tokens integer NOT NULL DEFAULT 0,
  output_tokens integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_assistant_usage_user_time ON public.assistant_usage (user_id, created_at DESC);

ALTER TABLE public.assistant_usage ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users read own assistant usage" ON public.assistant_usage;
CREATE POLICY "Users read own assistant usage" ON public.assistant_usage
  FOR SELECT TO authenticated USING (user_id = auth.uid());
REVOKE INSERT, UPDATE, DELETE ON public.assistant_usage FROM anon, authenticated;
GRANT SELECT ON public.assistant_usage TO authenticated;

-- Shared fixtures for the SQL tests in this folder. Every test runs as
--   BEGIN; <scripts under test, BEGIN/COMMIT stripped>; _fixtures.sql; <test>; ROLLBACK;
-- through the Supabase MCP execute_sql tool, so nothing persists.
--
-- Fixture rows are inserted with triggers off (replica role) to skip station
-- setup checks; triggers are back on before the test body runs.
--
-- ids: owner ...a1, second owner ...a2, customer ...c1, rider ...d1,
--      admin ...e1, product ...b1 (₱19.60, owner a1).

SET LOCAL session_replication_role = replica;

INSERT INTO auth.users (id, instance_id, aud, role, email, raw_user_meta_data, raw_app_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_owner@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000a2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_owner2@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_cust@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_rider@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_admin@example.test', '{}', '{}', now(), now());

INSERT INTO public.profiles (id, role, full_name, station_name, station_availability, latitude, longitude)
VALUES
  ('00000000-0000-4000-8000-0000000000a1', 'owner', 'T Owner', 'T Station', 'open', 14.60, 121.00),
  ('00000000-0000-4000-8000-0000000000a2', 'owner', 'T Owner 2', 'T Station 2', 'open', 14.61, 121.01),
  ('00000000-0000-4000-8000-0000000000c1', 'customer', 'T Cust', NULL, 'open', 14.62, 121.02),
  ('00000000-0000-4000-8000-0000000000d1', 'rider', 'T Rider', NULL, 'open', NULL, NULL),
  ('00000000-0000-4000-8000-0000000000e1', 'admin', 'T Admin', NULL, 'open', NULL, NULL);

INSERT INTO public.owner_settings (owner_id, base_delivery_fee)
VALUES
  ('00000000-0000-4000-8000-0000000000a1', 5.4),
  ('00000000-0000-4000-8000-0000000000a2', 0);

INSERT INTO public.products (id, owner_id, name, price, is_available)
VALUES ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000a1', 'T Water', 19.6, true);

-- Fee config used by every test unless a test overrides it.
UPDATE public.system_config SET value = '{"enabled": true, "percent": 1, "fixed": 0}'::jsonb
WHERE key = 'platform_fee';

SET LOCAL session_replication_role = origin;

-- Helpers (temporary: dropped with the transaction).
CREATE OR REPLACE FUNCTION pg_temp.act_as(p_user uuid) RETURNS void
LANGUAGE sql AS $$
  SELECT set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text,
    true
  );
$$;

CREATE OR REPLACE FUNCTION pg_temp.place_order(p_method text, p_qty integer DEFAULT 1)
RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  RETURN public.create_order_atomic(
    jsonb_build_object(
      'owner_id', '00000000-0000-4000-8000-0000000000a1',
      'payment_method', p_method,
      'customer_name', 'T Cust',
      'customer_address', 'Test address',
      'customer_latitude', '14.6',
      'customer_longitude', '121.0'
    ),
    jsonb_build_array(jsonb_build_object(
      'product_id', '00000000-0000-4000-8000-0000000000b1',
      'quantity', p_qty,
      'product_name', 'T Water'
    ))
  );
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.assert_eq(p_label text, p_actual anyelement, p_expected anyelement)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF p_actual IS DISTINCT FROM p_expected THEN
    RAISE EXCEPTION '% — expected %, got %', p_label, p_expected, p_actual;
  END IF;
END;
$$;

-- Runs p_sql and fails unless it raises an error containing p_message.
CREATE OR REPLACE FUNCTION pg_temp.expect_error(p_label text, p_sql text, p_message text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    IF position(p_message IN SQLERRM) = 0 THEN
      RAISE EXCEPTION '% — expected error "%", got "%"', p_label, p_message, SQLERRM;
    END IF;
    RETURN;
  END;
  RAISE EXCEPTION '% — expected error "%", but it succeeded', p_label, p_message;
END;
$$;
-- Run: bash build.sh ../scripts/harden_signup_and_protected_columns.sql ../scripts/delivery_coverage.sql ../scripts/station_accessories.sql ../scripts/rider_tips.sql ../scripts/identity_verification.sql ../scripts/order_pricing_v3.sql -- delivery_quote_test.sql

-- Fixture station must be verified to take orders (identity_verification.sql).
UPDATE public.profiles SET verification_status = 'approved' WHERE id = '00000000-0000-4000-8000-0000000000a1';
-- Owner a1 is at (14.60, 121.00). Config below: ₱10/km, ₱20 minimum, 1 km minimum billable, exact distance, whole-peso fee.

UPDATE public.system_config
SET value = '{"enabled": true, "rate_per_km": 10, "minimum_fee": 20, "min_billable_distance_km": 1, "rounding_rule": "exact"}'::jsonb
WHERE key = 'delivery_fee_config';
INSERT INTO public.system_config (key, value)
SELECT 'delivery_fee_config', '{"enabled": true, "rate_per_km": 10, "minimum_fee": 20, "min_billable_distance_km": 1, "rounding_rule": "exact"}'::jsonb
WHERE NOT EXISTS (SELECT 1 FROM public.system_config WHERE key = 'delivery_fee_config');

-- free_inside_default_radius (same point -> 0 km, default 1 km radius)
DO $$ DECLARE q jsonb; BEGIN
  q := public.compute_delivery_quote('00000000-0000-4000-8000-0000000000a1', 14.60, 121.00);
  PERFORM pg_temp.assert_eq('free radius', (q->>'is_free')::boolean, true);
  PERFORM pg_temp.assert_eq('reason radius', q->>'free_reason', 'radius');
  PERFORM pg_temp.assert_eq('fee 0', (q->>'fee')::numeric, 0::numeric);
END $$;

-- per_km_outside_radius (~0.05 deg lat = 5.56 km * 1.3 = 7.23 km -> round(72.3) = 72)
DO $$ DECLARE q jsonb; BEGIN
  q := public.compute_delivery_quote('00000000-0000-4000-8000-0000000000a1', 14.65, 121.00);
  PERFORM pg_temp.assert_eq('not free', (q->>'is_free')::boolean, false);
  PERFORM pg_temp.assert_eq('distance', round((q->>'distance_km')::numeric, 1), 7.2::numeric);
  PERFORM pg_temp.assert_eq('fee per km', (q->>'fee')::numeric, 72::numeric);
END $$;

-- minimum_fee_applies_just_outside_radius (~1.3 km road -> 13 -> minimum 20)
DO $$ DECLARE q jsonb; BEGIN
  q := public.compute_delivery_quote('00000000-0000-4000-8000-0000000000a1', 14.609, 121.00);
  PERFORM pg_temp.assert_eq('minimum', (q->>'fee')::numeric, 20::numeric);
END $$;

-- free_barangay_list_is_case_insensitive
DO $$ DECLARE q jsonb; BEGIN
  UPDATE public.owner_settings SET free_delivery_barangays = ARRAY['Poblacion']
  WHERE owner_id = '00000000-0000-4000-8000-0000000000a1';
  q := public.compute_delivery_quote('00000000-0000-4000-8000-0000000000a1', 14.65, 121.00, ' poblacion ');
  PERFORM pg_temp.assert_eq('barangay free', q->>'free_reason', 'barangay');
END $$;

-- free_by_minimum_gallons
DO $$ DECLARE q jsonb; BEGIN
  UPDATE public.owner_settings SET free_delivery_min_gallons = 5
  WHERE owner_id = '00000000-0000-4000-8000-0000000000a1';
  q := public.compute_delivery_quote('00000000-0000-4000-8000-0000000000a1', 14.65, 121.00, NULL, 4);
  PERFORM pg_temp.assert_eq('4 gal pays', (q->>'is_free')::boolean, false);
  q := public.compute_delivery_quote('00000000-0000-4000-8000-0000000000a1', 14.65, 121.00, NULL, 5);
  PERFORM pg_temp.assert_eq('5 gal free', q->>'free_reason', 'min_gallons');
END $$;

-- missing_customer_pin_charges_minimum
DO $$ DECLARE q jsonb; BEGIN
  q := public.compute_delivery_quote('00000000-0000-4000-8000-0000000000a1', NULL, NULL);
  PERFORM pg_temp.assert_eq('no pin minimum', (q->>'fee')::numeric, 20::numeric);
END $$;

-- order_charges_server_quote_not_client_fee
DO $$ DECLARE r jsonb; BEGIN
  UPDATE public.owner_settings
  SET free_delivery_barangays = '{}', free_delivery_min_gallons = NULL, base_delivery_fee = 99
  WHERE owner_id = '00000000-0000-4000-8000-0000000000a1';
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  r := public.create_order_atomic(
    jsonb_build_object(
      'owner_id', '00000000-0000-4000-8000-0000000000a1',
      'payment_method', 'cod',
      'customer_name', 'T Cust',
      'customer_address', 'Test address',
      'customer_latitude', '14.65',
      'customer_longitude', '121.0',
      'delivery_fee', 0
    ),
    jsonb_build_array(jsonb_build_object(
      'product_id', '00000000-0000-4000-8000-0000000000b1', 'quantity', 1, 'product_name', 'T Water'))
  );
  PERFORM pg_temp.assert_eq('order fee', (r->>'delivery_fee')::numeric, 72::numeric);
  PERFORM pg_temp.assert_eq('stored distance',
    (SELECT round(delivery_distance_km, 1) FROM public.orders WHERE id = (r->>'id')::uuid), 7.2::numeric);
END $$;

-- order_inside_zone_is_free
DO $$ DECLARE r jsonb; BEGIN
  r := pg_temp.place_order('cod');  -- customer pin (14.6, 121.0) = station
  PERFORM pg_temp.assert_eq('free order', (r->>'delivery_fee')::numeric, 0::numeric);
  PERFORM pg_temp.assert_eq('free reason', r->>'delivery_free_reason', 'radius');
END $$;

SELECT 'delivery_quote_test: all passed' AS result;
ROLLBACK;

-- ===== accessories_test =====
BEGIN;
-- ==============================================================================
-- Harden signup roles and protect trust columns on profiles (2026-11-05)
-- ==============================================================================
-- 1. Self-signup could claim role 'admin' or 'rider' through user metadata.
--    Only accounts created by a trusted server function (admin_create_user,
--    create_rider_account, admin_create_station) may get privileged roles.
--    Self-signups arrive through the Auth server, whose session user is
--    supabase_auth_admin; those are limited to customer/owner.
-- 2. Users could UPDATE their own average_rating / review_count /
--    reliability_score / flagged_count. Those are now writable only by admins
--    or by SECURITY DEFINER functions (e.g. update_station_stats()).
-- 3. Adds profiles.verification_status (used by identity verification), which is
--    protected the same way.
--
-- Run after: single_water_product_catalog.sql. Test: supabase/tests/protected_columns_test.sql
-- ==============================================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS verification_status text NOT NULL DEFAULT 'unverified';
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_verification_status_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_verification_status_check
  CHECK (verification_status IN ('unverified', 'pending', 'approved', 'rejected'));

-- 1. Role resolution -----------------------------------------------------------
CREATE OR REPLACE FUNCTION public.resolve_signup_role(p_requested text, p_trusted boolean)
RETURNS public.user_role
LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN p_requested IN ('customer', 'owner') THEN p_requested::public.user_role
    WHEN p_trusted AND p_requested IN ('rider', 'admin') THEN p_requested::public.user_role
    ELSE 'customer'::public.user_role
  END;
$$;
REVOKE ALL ON FUNCTION public.resolve_signup_role(text, boolean) FROM PUBLIC, anon, authenticated;

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
  -- 1. Role: self-signups (Auth server session) may only be customer or owner.
  v_role := public.resolve_signup_role(
    new.raw_user_meta_data->>'role',
    session_user <> 'supabase_auth_admin'
  );

  -- 2. Safe municipality enum resolution
  IF lower(trim(COALESCE(new.raw_user_meta_data->>'town', ''))) = 'cantilan' THEN
    v_town := 'Cantilan'::public.municipality;
  ELSIF lower(trim(COALESCE(new.raw_user_meta_data->>'town', ''))) = 'madrid' THEN
    v_town := 'Madrid'::public.municipality;
  ELSE
    v_town := NULL;
  END IF;

  v_complete_address := NULLIF(TRIM(COALESCE(new.raw_user_meta_data->>'complete_address', '')), '');

  -- 3. Names (Google OAuth sends 'name', 'given_name', 'family_name', 'picture')
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

  -- 5. Upsert profile
  INSERT INTO public.profiles (
    id, email, username, full_name, first_name, last_name, mi, suffix, role,
    phone, town, barangay, complete_address, landmark, station_name,
    avatar_url, latitude, longitude, primary_water_type
  )
  VALUES (
    new.id, new.email, v_username, v_full_name, v_first_name, v_last_name,
    new.raw_user_meta_data->>'mi', new.raw_user_meta_data->>'suffix', v_role,
    new.raw_user_meta_data->>'phone', v_town, new.raw_user_meta_data->>'barangay',
    v_complete_address, new.raw_user_meta_data->>'landmark',
    new.raw_user_meta_data->>'station_name', v_avatar_url,
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

-- 2. Protected trust columns -----------------------------------------------------
-- SECURITY INVOKER on purpose: current_user is 'authenticated'/'anon' for direct
-- client writes, and the function owner (postgres) inside SECURITY DEFINER
-- functions such as update_station_stats() and the admin RPCs.
CREATE OR REPLACE FUNCTION public.guard_profile_protected_columns()
RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;

  IF NEW.average_rating IS NOT DISTINCT FROM OLD.average_rating
    AND NEW.review_count IS NOT DISTINCT FROM OLD.review_count
    AND NEW.reliability_score IS NOT DISTINCT FROM OLD.reliability_score
    AND NEW.flagged_count IS NOT DISTINCT FROM OLD.flagged_count
    AND NEW.verification_status IS NOT DISTINCT FROM OLD.verification_status
  THEN
    RETURN NEW;
  END IF;

  IF public.is_admin() THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'Unauthorized: You cannot alter protected account fields.';
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_profile_protected_columns ON public.profiles;
CREATE TRIGGER trg_guard_profile_protected_columns
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.guard_profile_protected_columns();


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Delivery coverage: free-delivery zones + distance-based fees (2026-11-05)
-- ==============================================================================
-- Each station defines where delivery is free:
--   * within free_delivery_radius_km of the station (default 1 km), OR
--   * to any barangay listed in free_delivery_barangays, OR
--   * when the order has at least free_delivery_min_gallons water gallons.
-- Everywhere else pays the platform's per-km rate from
-- system_config.delivery_fee_config (rate_per_km, minimum_fee,
-- min_billable_distance_km, rounding_rule, enabled).
--
-- Distance = straight-line (haversine) x 1.3 road factor, so it approximates
-- real road distance without calling a routing service from the database.
--
-- Self-contained: does not depend on delivery_fee_config_rpcs.sql.
-- Run before: order_pricing_v3.sql. Test: supabase/tests/delivery_quote_test.sql
-- ==============================================================================

ALTER TABLE public.owner_settings
  ADD COLUMN IF NOT EXISTS free_delivery_radius_km numeric(4,1) NOT NULL DEFAULT 1.0,
  ADD COLUMN IF NOT EXISTS free_delivery_barangays text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS free_delivery_min_gallons integer;

ALTER TABLE public.owner_settings DROP CONSTRAINT IF EXISTS owner_settings_free_radius_check;
ALTER TABLE public.owner_settings ADD CONSTRAINT owner_settings_free_radius_check
  CHECK (free_delivery_radius_km >= 0 AND free_delivery_radius_km <= 10);
ALTER TABLE public.owner_settings DROP CONSTRAINT IF EXISTS owner_settings_free_min_gallons_check;
ALTER TABLE public.owner_settings ADD CONSTRAINT owner_settings_free_min_gallons_check
  CHECK (free_delivery_min_gallons IS NULL OR free_delivery_min_gallons BETWEEN 1 AND 100);

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS delivery_distance_km numeric(6,2),
  ADD COLUMN IF NOT EXISTS delivery_rate_per_km numeric(8,2),
  ADD COLUMN IF NOT EXISTS delivery_free_reason text;

-- Road factor applied to straight-line distance.
CREATE OR REPLACE FUNCTION public.delivery_road_distance_km(
  p_lat1 double precision, p_lng1 double precision,
  p_lat2 double precision, p_lng2 double precision
) RETURNS numeric
LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN p_lat1 IS NULL OR p_lng1 IS NULL OR p_lat2 IS NULL OR p_lng2 IS NULL THEN NULL
    ELSE round((
      2 * 6371 * asin(sqrt(
        power(sin(radians(p_lat2 - p_lat1) / 2), 2)
        + cos(radians(p_lat1)) * cos(radians(p_lat2))
          * power(sin(radians(p_lng2 - p_lng1) / 2), 2)
      )) * 1.3
    )::numeric, 2)
  END;
$$;

-- Fee for a distance outside the free zone, from the admin's config.
CREATE OR REPLACE FUNCTION public.delivery_fee_for_distance(p_km numeric)
RETURNS numeric
LANGUAGE plpgsql STABLE SET search_path TO 'public' AS $$
DECLARE
  v_cfg jsonb;
  v_rate numeric;
  v_min numeric;
  v_min_km numeric;
  v_rule text;
  v_fee numeric;
BEGIN
  SELECT value INTO v_cfg FROM public.system_config WHERE key = 'delivery_fee_config';
  v_cfg := coalesce(v_cfg, '{}'::jsonb);
  IF NOT coalesce((v_cfg->>'enabled')::boolean, true) THEN
    RETURN 0;
  END IF;
  v_rate := greatest(coalesce((v_cfg->>'rate_per_km')::numeric, 10), 0);
  v_min := greatest(coalesce((v_cfg->>'minimum_fee')::numeric, 20), 0);
  v_min_km := greatest(coalesce((v_cfg->>'min_billable_distance_km')::numeric, 1), 0);
  v_rule := lower(trim(coalesce(v_cfg->>'rounding_rule', 'exact')));

  IF p_km IS NULL THEN
    RETURN v_min;
  END IF;

  -- Same rule as CheckoutRules.calculateDeliveryFee in the app: the rounding
  -- rule applies to the billable distance; the fee is whole pesos.
  v_fee := greatest(p_km, v_min_km);
  v_fee := CASE
    WHEN v_rule IN ('ceil', 'round_up') THEN ceil(v_fee)
    WHEN v_rule IN ('round', 'round_nearest') THEN round(v_fee)
    ELSE v_fee
  END;
  IF v_rate <= 0 THEN
    RETURN 0;
  END IF;
  RETURN round(greatest(v_rate * v_fee, v_min));
END;
$$;

-- Quote shown at checkout and charged by create_order_atomic.
CREATE OR REPLACE FUNCTION public.compute_delivery_quote(
  p_station_id uuid,
  p_lat double precision,
  p_lng double precision,
  p_barangay text DEFAULT NULL,
  p_gallons integer DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_slat double precision;
  v_slng double precision;
  v_radius numeric;
  v_barangays text[];
  v_min_gallons integer;
  v_km numeric;
  v_reason text;
  v_cfg jsonb;
BEGIN
  SELECT coalesce(p.latitude, p.lat), coalesce(p.longitude, p.lng)
  INTO v_slat, v_slng
  FROM public.profiles p
  WHERE p.id = p_station_id AND p.role = 'owner';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Water refill station not found.';
  END IF;

  SELECT coalesce(os.free_delivery_radius_km, 1.0),
         coalesce(os.free_delivery_barangays, '{}'),
         os.free_delivery_min_gallons
  INTO v_radius, v_barangays, v_min_gallons
  FROM public.owner_settings os WHERE os.owner_id = p_station_id;
  v_radius := coalesce(v_radius, 1.0);
  v_barangays := coalesce(v_barangays, '{}');

  v_km := public.delivery_road_distance_km(v_slat, v_slng, p_lat, p_lng);

  IF v_km IS NOT NULL AND v_km <= v_radius THEN
    v_reason := 'radius';
  ELSIF p_barangay IS NOT NULL AND EXISTS (
    SELECT 1 FROM unnest(v_barangays) b
    WHERE lower(trim(b)) = lower(trim(p_barangay))
  ) THEN
    v_reason := 'barangay';
  ELSIF v_min_gallons IS NOT NULL AND coalesce(p_gallons, 0) >= v_min_gallons THEN
    v_reason := 'min_gallons';
  END IF;

  SELECT value INTO v_cfg FROM public.system_config WHERE key = 'delivery_fee_config';

  RETURN jsonb_build_object(
    'distance_km', v_km,
    'is_free', v_reason IS NOT NULL,
    'free_reason', v_reason,
    'fee', CASE WHEN v_reason IS NOT NULL THEN 0 ELSE public.delivery_fee_for_distance(v_km) END,
    'rate_per_km', coalesce((v_cfg->>'rate_per_km')::numeric, 10),
    'minimum_fee', coalesce((v_cfg->>'minimum_fee')::numeric, 20),
    'free_radius_km', v_radius,
    'free_barangays', to_jsonb(v_barangays),
    'free_min_gallons', v_min_gallons
  );
END;
$$;

REVOKE ALL ON FUNCTION public.compute_delivery_quote(uuid, double precision, double precision, text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.compute_delivery_quote(uuid, double precision, double precision, text, integer) TO authenticated;
REVOKE ALL ON FUNCTION public.delivery_fee_for_distance(numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delivery_fee_for_distance(numeric) TO authenticated;


NOTIFY pgrst, 'reload schema';
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


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Rider tips (2026-11-05)
-- ==============================================================================
-- Customers can add an optional tip (₱0–₱500, whole pesos) at checkout for
-- delivery orders. It is part of the single charge (COD or PayMongo), so no
-- second payment is needed, and 100% goes to the rider:
--   * excluded from the station SALE and from the 10% commission base
--   * booked as a RIDER_TIP ledger entry to the assigned rider
--   * if no rider was assigned (station delivered itself) it stays with the
--     station as part of the SALE
-- create_order_atomic reads p_order_data->>'tip_amount' (order_pricing_v3.sql).
--
-- Run before: order_pricing_v3.sql. Test: supabase/tests/rider_tips_test.sql
-- ==============================================================================

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS tip_amount numeric(10,2) NOT NULL DEFAULT 0;
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_tip_amount_check;
ALTER TABLE public.orders ADD CONSTRAINT orders_tip_amount_check
  CHECK (tip_amount >= 0 AND tip_amount <= 500);

CREATE OR REPLACE FUNCTION public.proc_finalize_order_finances()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    v_commission NUMERIC;
    v_fee NUMERIC := greatest(coalesce(NEW.platform_fee, 0), 0);
    v_tip NUMERIC := greatest(coalesce(NEW.tip_amount, 0), 0);
    v_rider_tip NUMERIC := 0;
BEGIN
    IF NEW.status = 'delivered' AND OLD.status != 'delivered' THEN
        -- The tip belongs to the rider; without a rider it stays in the sale.
        IF NEW.assigned_rider_id IS NOT NULL THEN
            v_rider_tip := v_tip;
        END IF;

        INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
        VALUES (NEW.owner_id, NEW.id, NEW.total_amount - v_fee - v_rider_tip, 'SALE', 'Order completion payment');

        IF v_fee > 0 THEN
            INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description, metadata)
            VALUES (
                NEW.owner_id, NEW.id, v_fee, 'SERVICE_FEE', 'Platform service fee',
                jsonb_build_object('payee', 'platform', 'payment_method', NEW.payment_method)
            );

            IF lower(coalesce(NEW.payment_method, 'cod')) IN ('cod', 'cash', 'credit') THEN
                PERFORM public.apply_wallet_entry(
                    NEW.owner_id, -v_fee, 'service_fee', NEW.id, NULL,
                    'Service fee for order ' || upper(substr(NEW.id::text, 1, 8))
                );
            END IF;
        END IF;

        -- Commission excludes the tip.
        v_commission := (NEW.total_amount - v_tip) * 0.10;

        IF NEW.assigned_rider_id IS NOT NULL THEN
            INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
            VALUES (NEW.assigned_rider_id, NEW.id, v_commission, 'COMMISSION', 'Delivery commission for order');

            IF v_rider_tip > 0 THEN
                INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
                VALUES (NEW.assigned_rider_id, NEW.id, v_rider_tip, 'RIDER_TIP', 'Customer tip');

                INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
                VALUES (
                    NEW.assigned_rider_id, 'system_alert', 'normal', 'You got a tip!',
                    'A customer tipped you PHP ' || trim(to_char(v_rider_tip, '999990')) || '. Thank you for the great service.',
                    jsonb_build_object('order_id', NEW.id, 'tip_amount', v_rider_tip)
                );
            END IF;
        END IF;

        INSERT INTO public.domain_events (event_type, payload, actor_id)
        VALUES ('ORDER_COMPLETED', jsonb_build_object(
            'order_id', NEW.id, 'total', NEW.total_amount,
            'rider_id', NEW.assigned_rider_id, 'tip', v_tip), auth.uid());
    END IF;
    RETURN NEW;
END;
$$;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Seller and customer ID verification (2026-11-05)
-- ==============================================================================
-- Users upload a government ID (front, back, selfie; owners also a business
-- permit) to the private bucket verification_docs under <their uid>/.
-- An admin reviews and approves or rejects. profiles.verification_status
-- (added and write-protected by harden_signup_and_protected_columns.sql) is
-- only changed by the RPCs below.
--
-- Gates (enforced in create_order_atomic, order_pricing_v3.sql):
--   * stations must be 'approved' to receive orders
--   * unverified customers: cash-on-delivery up to PHP 1,000 and at most
--     2 active COD orders; verified customers have no limit
-- Backfill: owners who already completed a delivery are approved (legacy).
--
-- Run after: harden_signup_and_protected_columns.sql
-- Run before: order_pricing_v3.sql. Test: supabase/tests/identity_verification_test.sql
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.identity_verifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role text NOT NULL,
  id_type text NOT NULL CHECK (id_type IN (
    'philsys', 'drivers_license', 'umid', 'passport', 'postal', 'voters', 'prc', 'other')),
  id_number_last4 text CHECK (id_number_last4 ~ '^[0-9A-Za-z]{4}$'),
  front_path text NOT NULL,
  back_path text,
  selfie_path text NOT NULL,
  business_permit_path text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  reviewer_id uuid REFERENCES public.profiles(id),
  reviewed_at timestamptz,
  rejection_reason text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_identity_verifications_user ON public.identity_verifications (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_identity_verifications_pending ON public.identity_verifications (created_at) WHERE status = 'pending';

ALTER TABLE public.identity_verifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users read own verifications" ON public.identity_verifications;
CREATE POLICY "Users read own verifications" ON public.identity_verifications
  FOR SELECT TO authenticated USING (auth.uid() = user_id OR public.is_admin());
-- Writes only through the RPCs below.
REVOKE INSERT, UPDATE, DELETE ON public.identity_verifications FROM anon, authenticated;
GRANT SELECT ON public.identity_verifications TO authenticated;

-- Private bucket, one folder per user.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('verification_docs', 'verification_docs', false, 8388608,
        ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
ON CONFLICT (id) DO UPDATE SET public = false;

DROP POLICY IF EXISTS "Verification docs: owner upload" ON storage.objects;
CREATE POLICY "Verification docs: owner upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'verification_docs' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "Verification docs: owner or admin read" ON storage.objects;
CREATE POLICY "Verification docs: owner or admin read" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'verification_docs'
         AND ((storage.foldername(name))[1] = auth.uid()::text OR public.is_admin()));

CREATE OR REPLACE FUNCTION public.submit_identity_verification(
  p_id_type text,
  p_id_number_last4 text,
  p_front_path text,
  p_back_path text,
  p_selfie_path text,
  p_business_permit_path text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_role text;
  v_status text;
  v_prefix text;
  v_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required.'; END IF;
  SELECT role::text, verification_status INTO v_role, v_status FROM public.profiles WHERE id = v_uid;
  IF v_role NOT IN ('customer', 'owner') THEN
    RAISE EXCEPTION 'Only customers and station owners verify their ID here.';
  END IF;
  IF v_status = 'approved' THEN RAISE EXCEPTION 'Your ID is already verified.'; END IF;
  IF v_status = 'pending' THEN RAISE EXCEPTION 'Your ID is already being reviewed.'; END IF;

  v_prefix := v_uid::text || '/';
  IF p_front_path IS NULL OR p_selfie_path IS NULL
     OR left(p_front_path, length(v_prefix)) <> v_prefix
     OR left(p_selfie_path, length(v_prefix)) <> v_prefix
     OR (p_back_path IS NOT NULL AND left(p_back_path, length(v_prefix)) <> v_prefix)
     OR (p_business_permit_path IS NOT NULL AND left(p_business_permit_path, length(v_prefix)) <> v_prefix) THEN
    RAISE EXCEPTION 'Upload your ID photos before submitting.';
  END IF;
  IF v_role = 'owner' AND p_business_permit_path IS NULL THEN
    RAISE EXCEPTION 'Stations must also upload a business or sanitary permit.';
  END IF;

  INSERT INTO public.identity_verifications (
    user_id, role, id_type, id_number_last4, front_path, back_path, selfie_path, business_permit_path)
  VALUES (v_uid, v_role, p_id_type, NULLIF(p_id_number_last4, ''), p_front_path, p_back_path,
          p_selfie_path, p_business_permit_path)
  RETURNING id INTO v_id;

  UPDATE public.profiles SET verification_status = 'pending' WHERE id = v_uid;
  RETURN jsonb_build_object('id', v_id, 'status', 'pending');
END; $$;

CREATE OR REPLACE FUNCTION public.admin_review_identity_verification(
  p_verification_id uuid,
  p_approve boolean,
  p_reason text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_row public.identity_verifications%ROWTYPE;
  v_status text := CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  IF NOT p_approve AND coalesce(trim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'Give the user a reason for the rejection.';
  END IF;

  UPDATE public.identity_verifications
  SET status = v_status, reviewer_id = auth.uid(), reviewed_at = now(),
      rejection_reason = CASE WHEN p_approve THEN NULL ELSE trim(p_reason) END
  WHERE id = p_verification_id AND status = 'pending'
  RETURNING * INTO v_row;
  IF NOT FOUND THEN RAISE EXCEPTION 'This verification was already reviewed.'; END IF;

  UPDATE public.profiles SET verification_status = v_status WHERE id = v_row.user_id;

  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (
    v_row.user_id, 'system_alert', 'high',
    CASE WHEN p_approve THEN 'Your ID is verified' ELSE 'ID verification needs another try' END,
    CASE WHEN p_approve
      THEN CASE WHEN v_row.role = 'owner'
        THEN 'Your station is verified and can now receive orders.'
        ELSE 'Your account is verified. Order limits are lifted.' END
      ELSE 'Reason: ' || trim(p_reason) || '. You can submit new photos.' END,
    jsonb_build_object('verification_id', v_row.id, 'status', v_status)
  );

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, new_value, metadata)
  VALUES (auth.uid(), 'identity_verification_' || v_status, 'identity_verifications', v_row.id::text,
          jsonb_build_object('status', v_status),
          jsonb_build_object('user_id', v_row.user_id, 'reason', p_reason));

  RETURN jsonb_build_object('id', v_row.id, 'status', v_status);
END; $$;

REVOKE ALL ON FUNCTION public.submit_identity_verification(text, text, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_identity_verification(text, text, text, text, text, text) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_review_identity_verification(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_review_identity_verification(uuid, boolean, text) TO authenticated;

-- Order gate helper, used by create_order_atomic.
CREATE OR REPLACE FUNCTION public.assert_order_allowed_by_verification(
  p_customer_id uuid, p_owner_id uuid, p_payment_method text, p_total numeric
) RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_owner_status text;
  v_customer_status text;
  v_active int;
BEGIN
  SELECT verification_status INTO v_owner_status FROM public.profiles WHERE id = p_owner_id;
  IF coalesce(v_owner_status, 'unverified') <> 'approved' THEN
    RAISE EXCEPTION 'This station is not verified yet and cannot take orders.';
  END IF;

  SELECT verification_status INTO v_customer_status FROM public.profiles WHERE id = p_customer_id;
  IF coalesce(v_customer_status, 'unverified') = 'approved'
     OR lower(coalesce(p_payment_method, 'cod')) NOT IN ('cod', 'cash') THEN
    RETURN;
  END IF;

  IF p_total > 1000 THEN
    RAISE EXCEPTION 'Verify your ID to place cash-on-delivery orders above PHP 1,000.';
  END IF;
  SELECT count(*) INTO v_active FROM public.orders
  WHERE customer_id = p_customer_id
    AND lower(coalesce(payment_method, 'cod')) IN ('cod', 'cash')
    AND status NOT IN ('delivered', 'cancelled', 'failed');
  IF v_active >= 2 THEN
    RAISE EXCEPTION 'Verify your ID to have more than 2 cash-on-delivery orders at a time.';
  END IF;
END; $$;
REVOKE ALL ON FUNCTION public.assert_order_allowed_by_verification(uuid, uuid, text, numeric) FROM PUBLIC, anon, authenticated;

-- Backfill: stations that already delivered orders keep working.
UPDATE public.profiles p SET verification_status = 'approved'
WHERE p.role = 'owner' AND p.verification_status = 'unverified'
  AND EXISTS (SELECT 1 FROM public.orders o WHERE o.owner_id = p.id AND o.status = 'delivered');


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- create_order_atomic v3 (2026-11-05)
-- ==============================================================================
-- Starts from the LIVE definition (pg_get_functiondef on 2026-11-05; note the
-- live function does not use price_order() from whole_peso_pricing.sql).
-- Changes:
--   * Delivery fee comes from compute_delivery_quote() (free zone or per-km),
--     never from the client and no longer from owner_settings.base_delivery_fee.
--   * Writes delivery_distance_km, delivery_rate_per_km, delivery_free_reason.
--   * Accessories (products.kind = 'accessory') are sold alongside water;
--     only water gallons count toward the free-delivery gallon threshold.
--   * Optional rider tip (tip_amount, ₱0–₱500) added to the total.
--   * ID verification gates: approved stations only; COD limits for
--     unverified customers.
-- This is the single place later features (accessories, tips, verification
-- gates) extend create_order_atomic. Do not redefine it in other scripts.
--
-- Run order: harden_signup_and_protected_columns.sql -> delivery_coverage.sql ->
--   station_accessories.sql -> rider_tips.sql -> identity_verification.sql -> this file.
-- Tests: supabase/tests/delivery_quote_test.sql, accessories_test.sql
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.create_order_atomic(p_order_data jsonb, p_items_data jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_customer_id uuid := auth.uid();
  v_owner_id uuid;
  v_payment_method text;
  v_idempotency_key public.orders.idempotency_key%TYPE;
  v_voucher_id uuid;
  v_order_id uuid;
  v_item record;
  v_product record;
  v_computed_subtotal numeric(10,2) := 0;
  v_delivery_fee numeric(10,2) := 0;
  v_platform_fee numeric(10,2) := 0;
  v_discount numeric(10,2) := 0;
  v_total_amount numeric(10,2) := 0;
  v_order_row public.orders%ROWTYPE;
  v_voucher public.customer_reward_vouchers%ROWTYPE;
  v_config jsonb;
  v_lat double precision;
  v_lng double precision;
  v_maintenance jsonb;
  v_is_maintenance boolean := false;
  v_customer_suspended boolean := false;
  v_owner_suspended boolean := false;
  v_gallons integer := 0;
  v_quote jsonb;
  v_tip numeric(10,2) := 0;
BEGIN
  SELECT value INTO v_maintenance
  FROM public.system_config
  WHERE key = 'maintenance_mode';

  IF v_maintenance IS NOT NULL THEN
    IF jsonb_typeof(v_maintenance) = 'boolean' THEN
      v_is_maintenance := v_maintenance::text::boolean;
    ELSIF jsonb_typeof(v_maintenance) = 'string' THEN
      v_is_maintenance :=
        lower(trim(both '"' from v_maintenance::text)) IN ('true', '1', 'yes');
    END IF;
  END IF;

  IF v_is_maintenance THEN
    RAISE EXCEPTION 'System is currently undergoing maintenance. New orders are temporarily paused.';
  END IF;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required to place an order.';
  END IF;

  SELECT coalesce(is_suspended, false) INTO v_customer_suspended
  FROM public.profiles
  WHERE id = v_customer_id AND role = 'customer';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Only customer accounts can place orders.';
  END IF;
  IF v_customer_suspended THEN
    RAISE EXCEPTION 'Your account has been suspended. Please contact customer support.';
  END IF;

  v_idempotency_key := NULLIF(p_order_data->>'idempotency_key', '');
  IF v_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_order_row
    FROM public.orders
    WHERE customer_id = v_customer_id
      AND idempotency_key = v_idempotency_key;

    IF FOUND THEN
      RETURN jsonb_build_object(
        'id', v_order_row.id,
        'subtotal', v_order_row.subtotal,
        'delivery_fee', v_order_row.delivery_fee,
        'platform_fee', v_order_row.platform_fee,
        'total_amount', v_order_row.total_amount,
        'status', v_order_row.status
      );
    END IF;
  END IF;

  v_owner_id := NULLIF(p_order_data->>'owner_id', '')::uuid;
  v_payment_method := lower(trim(coalesce(p_order_data->>'payment_method', 'cod')));
  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'Station owner ID is required.';
  END IF;

  SELECT coalesce(is_suspended, false) INTO v_owner_suspended
  FROM public.profiles
  WHERE id = v_owner_id AND role = 'owner';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Water refill station not found.';
  END IF;
  IF v_owner_suspended THEN
    RAISE EXCEPTION 'This water station is currently suspended by administration.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = v_owner_id
      AND role = 'owner'
      AND coalesce(station_availability, 'open') = 'open'
  ) THEN
    RAISE EXCEPTION 'This water station is currently closed or unavailable.';
  END IF;
  IF NOT public.is_station_payment_method_available(v_owner_id, v_payment_method) THEN
    RAISE EXCEPTION 'This payment method is not available for this station.';
  END IF;

  FOR v_item IN
    SELECT * FROM jsonb_to_recordset(p_items_data) AS x(
      product_id uuid,
      quantity integer,
      product_name text
    )
  LOOP
    IF v_item.quantity <= 0 THEN
      RAISE EXCEPTION 'Invalid quantity for item %', v_item.product_name;
    END IF;

    SELECT * INTO v_product
    FROM public.products
    WHERE id = v_item.product_id
      AND owner_id = v_owner_id
      AND is_available = true;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Product % is unavailable at this station.', v_item.product_name;
    END IF;

    v_computed_subtotal :=
      v_computed_subtotal + (v_product.price * v_item.quantity);
    -- Only water counts toward the free-delivery gallon threshold.
    IF v_product.kind = 'water' THEN
      v_gallons := v_gallons + v_item.quantity;
    END IF;
  END LOOP;

  IF v_computed_subtotal <= 0 THEN
    RAISE EXCEPTION 'Cart cannot be empty.';
  END IF;

  v_lat := NULLIF(p_order_data->>'customer_latitude', '')::double precision;
  v_lng := NULLIF(p_order_data->>'customer_longitude', '')::double precision;

  -- Delivery fee: server-side quote (free zone or per-km). Client fee ignored.
  v_quote := public.compute_delivery_quote(
    v_owner_id, v_lat, v_lng,
    NULLIF(p_order_data->>'customer_barangay', ''),
    v_gallons
  );
  v_delivery_fee := coalesce((v_quote->>'fee')::numeric, 0);

  v_config := public.get_platform_fee_config();
  IF coalesce((v_config->>'enabled')::boolean, false) THEN
    v_platform_fee := round(
      ((v_computed_subtotal + v_delivery_fee)
        * coalesce((v_config->>'percent')::numeric, 0) / 100)
        + coalesce((v_config->>'fixed')::numeric, 0),
      2
    );
    v_platform_fee := greatest(v_platform_fee, 0);
  END IF;

  v_voucher_id := NULLIF(p_order_data->>'voucher_id', '')::uuid;
  IF v_voucher_id IS NOT NULL THEN
    SELECT * INTO v_voucher
    FROM public.customer_reward_vouchers
    WHERE id = v_voucher_id
      AND user_id = v_customer_id
      AND is_used = false
      AND expires_at > now()
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'This reward voucher is no longer available. Refresh your vouchers and try again.';
    END IF;

    IF v_voucher.is_delivery_discount THEN
      v_discount := least(
        greatest(v_voucher.discount_amount, 0),
        v_delivery_fee
      );
    ELSE
      v_discount := least(
        greatest(v_voucher.discount_amount, 0),
        v_computed_subtotal + v_delivery_fee + v_platform_fee
      );
    END IF;
  END IF;

  -- Optional rider tip: whole pesos, ₱0–₱500, paid on top (no fees, no voucher).
  v_tip := round(coalesce(NULLIF(p_order_data->>'tip_amount', '')::numeric, 0));
  IF v_tip < 0 OR v_tip > 500 THEN
    RAISE EXCEPTION 'Tip must be between PHP 0 and PHP 500.';
  END IF;

  v_total_amount := greatest(
    v_computed_subtotal + v_delivery_fee + v_platform_fee - v_discount,
    0
  ) + v_tip;

  -- ID verification gates (identity_verification.sql).
  PERFORM public.assert_order_allowed_by_verification(
    v_customer_id, v_owner_id, v_payment_method, v_total_amount
  );

  INSERT INTO public.orders (
    id,
    customer_id,
    owner_id,
    station_name,
    customer_name,
    customer_phone,
    customer_address,
    customer_barangay,
    customer_municipality,
    customer_landmark,
    idempotency_key,
    subtotal,
    delivery_fee,
    platform_fee,
    total_amount,
    payment_method,
    payment_status,
    notes,
    region_id,
    customer_latitude,
    customer_longitude,
    delivery_lat,
    delivery_lng,
    delivery_latitude,
    delivery_longitude,
    delivery_distance_km,
    delivery_rate_per_km,
    delivery_free_reason,
    tip_amount,
    items,
    status
  ) VALUES (
    coalesce(
      NULLIF(p_order_data->>'id', '')::uuid,
      gen_random_uuid()
    ),
    v_customer_id,
    v_owner_id,
    coalesce(p_order_data->>'station_name', 'Water Station'),
    p_order_data->>'customer_name',
    p_order_data->>'customer_phone',
    p_order_data->>'customer_address',
    p_order_data->>'customer_barangay',
    p_order_data->>'customer_municipality',
    p_order_data->>'customer_landmark',
    v_idempotency_key,
    v_computed_subtotal,
    v_delivery_fee,
    v_platform_fee,
    v_total_amount,
    v_payment_method,
    'pending',
    p_order_data->>'notes',
    NULLIF(p_order_data->>'region_id', '')::uuid,
    v_lat,
    v_lng,
    v_lat,
    v_lng,
    v_lat,
    v_lng,
    (v_quote->>'distance_km')::numeric,
    (v_quote->>'rate_per_km')::numeric,
    v_quote->>'free_reason',
    v_tip,
    coalesce(p_items_data, '[]'::jsonb),
    'pending'
  )
  ON CONFLICT DO NOTHING
  RETURNING * INTO v_order_row;

  IF NOT FOUND THEN
    IF v_idempotency_key IS NOT NULL THEN
      SELECT * INTO v_order_row
      FROM public.orders
      WHERE customer_id = v_customer_id
        AND idempotency_key = v_idempotency_key;

      IF FOUND THEN
        RETURN jsonb_build_object(
          'id', v_order_row.id,
          'subtotal', v_order_row.subtotal,
          'delivery_fee', v_order_row.delivery_fee,
          'platform_fee', v_order_row.platform_fee,
          'total_amount', v_order_row.total_amount,
          'status', v_order_row.status
        );
      END IF;
    END IF;
    RAISE EXCEPTION 'Order could not be created because of a conflicting order record.';
  END IF;

  v_order_id := v_order_row.id;

  FOR v_item IN
    SELECT * FROM jsonb_to_recordset(p_items_data) AS x(
      product_id uuid,
      quantity integer,
      product_name text
    )
  LOOP
    SELECT * INTO v_product FROM public.products WHERE id = v_item.product_id;
    INSERT INTO public.order_items (
      order_id,
      product_id,
      product_name,
      quantity,
      price_at_purchase,
      subtotal
    ) VALUES (
      v_order_id,
      v_item.product_id,
      v_product.name,
      v_item.quantity,
      v_product.price,
      (v_product.price * v_item.quantity)
    );
  END LOOP;

  IF v_voucher_id IS NOT NULL THEN
    UPDATE public.customer_reward_vouchers
    SET is_used = true
    WHERE id = v_voucher_id
      AND user_id = v_customer_id
      AND is_used = false;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'This reward voucher was already used by another order.';
    END IF;
  END IF;

  INSERT INTO public.system_notifications (
    user_id,
    type,
    priority,
    title,
    content,
    metadata
  ) VALUES (
    v_owner_id,
    'system_alert',
    'high',
    'New Refill Order',
    coalesce(p_order_data->>'customer_name', 'A customer')
      || ' placed a new refill order of PHP '
      || trim(to_char(v_total_amount, '999999990.00'))
      || ' (' || upper(coalesce(p_order_data->>'payment_method', 'cod')) || ').',
    jsonb_build_object(
      'order_id', v_order_id,
      'status', 'pending',
      'total_amount', v_total_amount
    )
  );

  RETURN jsonb_build_object(
    'id', v_order_id,
    'subtotal', v_computed_subtotal,
    'delivery_fee', v_delivery_fee,
    'delivery_distance_km', (v_quote->>'distance_km')::numeric,
    'delivery_free_reason', v_quote->>'free_reason',
    'platform_fee', v_platform_fee,
    'discount_amount', v_discount,
    'tip_amount', v_tip,
    'total_amount', v_total_amount,
    'status', 'pending'
  );
END;
$function$;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Rider live location privacy (2026-11-05)
-- ==============================================================================
-- rider_locations was readable by everyone ("Public can view rider
-- locations"). Now only these can read a rider's points:
--   * the rider, admins
--   * the customer or station of an order that rider is delivering right now
--     (assigned_to_rider / out_for_delivery)
-- After delivery the customer loses access. Points older than 24 h are purged
-- hourly (pg_cron, when the extension is available).
-- Test: supabase/tests/rider_live_location_test.sql
-- ==============================================================================

DROP POLICY IF EXISTS "Public can view rider locations" ON public.rider_locations;
DROP POLICY IF EXISTS "Rider location visible to active delivery parties" ON public.rider_locations;
CREATE POLICY "Rider location visible to active delivery parties" ON public.rider_locations
  FOR SELECT TO authenticated
  USING (
    rider_id = auth.uid()
    OR public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.orders o
      WHERE (o.assigned_rider_id = rider_locations.rider_id OR o.rider_id = rider_locations.rider_id)
        AND o.status IN ('assigned_to_rider', 'out_for_delivery')
        AND (o.customer_id = auth.uid() OR o.owner_id = auth.uid())
    )
  );

DROP POLICY IF EXISTS "Riders can update their own location" ON public.rider_locations;
CREATE POLICY "Riders can update their own location" ON public.rider_locations
  FOR INSERT TO authenticated
  WITH CHECK (rider_id = auth.uid());
REVOKE ALL ON public.rider_locations FROM anon;

CREATE OR REPLACE FUNCTION public.purge_old_rider_locations()
RETURNS integer
LANGUAGE sql SECURITY DEFINER SET search_path TO 'public' AS $$
  WITH d AS (
    DELETE FROM public.rider_locations WHERE "timestamp" < now() - interval '24 hours' RETURNING 1
  ) SELECT count(*)::int FROM d;
$$;
REVOKE ALL ON FUNCTION public.purge_old_rider_locations() FROM PUBLIC, anon, authenticated;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'purge_old_rider_locations';
    PERFORM cron.schedule('purge_old_rider_locations', '7 * * * *', 'SELECT public.purge_old_rider_locations()');
  END IF;
END $$;

-- ==============================================================================
-- Smart refill reminders (2026-11-05)
-- ==============================================================================
-- Learns each customer's refill rhythm (median days between their last
-- delivered orders, needs >= 3 orders) and reminds them a day before they
-- usually reorder. At most one reminder per 3 days, never while an order is
-- active, and only when profiles.refill_reminders_enabled.
--   * customer_refill_rhythm()  -> for the app's home banner (current user)
--   * send_refill_reminders()   -> daily 9:00 PH pg_cron job, inserts notifications
-- Test: supabase/tests/refill_reminders_test.sql
-- ==============================================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS refill_reminders_enabled boolean NOT NULL DEFAULT true;

CREATE OR REPLACE FUNCTION public.refill_rhythm_for(p_customer_id uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  WITH recent AS (
    SELECT created_at, owner_id, station_name
    FROM public.orders
    WHERE customer_id = p_customer_id AND status = 'delivered'
    ORDER BY created_at DESC
    LIMIT 6
  ), gaps AS (
    SELECT extract(epoch FROM (created_at - lead(created_at) OVER (ORDER BY created_at DESC))) / 86400.0 AS days
    FROM recent
  ), stats AS (
    SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY days) AS median_days,
           count(*) AS gap_count
    FROM gaps WHERE days IS NOT NULL AND days > 0.5
  ), last AS (
    SELECT * FROM recent ORDER BY created_at DESC LIMIT 1
  )
  SELECT CASE
    WHEN (SELECT gap_count FROM stats) < 2 THEN jsonb_build_object('has_rhythm', false)
    ELSE jsonb_build_object(
      'has_rhythm', true,
      'median_days', round((SELECT median_days FROM stats)::numeric, 1),
      'last_order_at', (SELECT created_at FROM last),
      'station_id', (SELECT owner_id FROM last),
      'station_name', (SELECT station_name FROM last),
      'due_at', (SELECT created_at FROM last)
                + make_interval(secs => greatest((SELECT median_days FROM stats) - 1, 1) * 86400),
      'is_due', now() >= (SELECT created_at FROM last)
                + make_interval(secs => greatest((SELECT median_days FROM stats) - 1, 1) * 86400),
      'has_active_order', EXISTS (
        SELECT 1 FROM public.orders
        WHERE customer_id = p_customer_id
          AND status NOT IN ('delivered', 'cancelled', 'failed'))
    )
  END;
$$;
REVOKE ALL ON FUNCTION public.refill_rhythm_for(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.customer_refill_rhythm()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT CASE WHEN auth.uid() IS NULL THEN '{"has_rhythm": false}'::jsonb
              ELSE public.refill_rhythm_for(auth.uid()) END;
$$;
REVOKE ALL ON FUNCTION public.customer_refill_rhythm() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.customer_refill_rhythm() TO authenticated;

CREATE OR REPLACE FUNCTION public.send_refill_reminders()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_row record;
  v_r jsonb;
  v_sent integer := 0;
BEGIN
  FOR v_row IN
    SELECT p.id FROM public.profiles p
    WHERE p.role = 'customer' AND p.refill_reminders_enabled AND NOT coalesce(p.is_suspended, false)
  LOOP
    v_r := public.refill_rhythm_for(v_row.id);
    CONTINUE WHEN NOT coalesce((v_r->>'has_rhythm')::boolean, false)
               OR NOT (v_r->>'is_due')::boolean
               OR (v_r->>'has_active_order')::boolean;
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM public.system_notifications n
      WHERE n.user_id = v_row.id
        AND n.metadata->>'kind' = 'refill_reminder'
        AND n.created_at > now() - interval '3 days');

    INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
    VALUES (
      v_row.id, 'system_alert', 'normal', 'Time for a refill?',
      'You usually reorder every ' || round((v_r->>'median_days')::numeric) || ' days. '
        || 'Tap to reorder from ' || coalesce(v_r->>'station_name', 'your station') || '.',
      jsonb_build_object('kind', 'refill_reminder', 'station_id', v_r->>'station_id')
    );
    v_sent := v_sent + 1;
  END LOOP;
  RETURN v_sent;
END; $$;
REVOKE ALL ON FUNCTION public.send_refill_reminders() FROM PUBLIC, anon, authenticated;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'send_refill_reminders';
    -- 9:00 Asia/Manila = 01:00 UTC, so reminders arrive in the morning.
    PERFORM cron.schedule('send_refill_reminders', '0 1 * * *', 'SELECT public.send_refill_reminders()');
  END IF;
END $$;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Water quality transparency (2026-11-05)
-- ==============================================================================
-- Stations upload lab test results and permits (bacteriological /
-- physical-chemical water analysis, sanitary permit, business permit) with
-- issue and expiry dates. Admins approve them; approved, unexpired lab tests
-- give the station a "Water tested" badge and a small ranking boost.
-- Files live in the private verification_docs bucket under <uid>/certs/.
-- Approved certificate files are viewable by any signed-in user.
-- Daily job: marks expired certificates and warns owners 14 days ahead.
--
-- Run after: identity_verification.sql (bucket). Test: supabase/tests/water_quality_certs_test.sql
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.station_certifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  cert_type text NOT NULL CHECK (cert_type IN (
    'bacteriological', 'physical_chemical', 'sanitary_permit', 'business_permit')),
  issued_on date NOT NULL,
  expires_on date NOT NULL,
  file_path text NOT NULL,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected', 'expired')),
  reviewer_id uuid REFERENCES public.profiles(id),
  reviewed_at timestamptz,
  rejection_reason text,
  expiry_warned_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (expires_on > issued_on)
);
CREATE INDEX IF NOT EXISTS idx_station_certs_owner ON public.station_certifications (owner_id, status);

ALTER TABLE public.station_certifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Approved certs are public, owners see their own" ON public.station_certifications;
CREATE POLICY "Approved certs are public, owners see their own" ON public.station_certifications
  FOR SELECT TO authenticated
  USING (status = 'approved' OR owner_id = auth.uid() OR public.is_admin());
REVOKE INSERT, UPDATE, DELETE ON public.station_certifications FROM anon, authenticated;
GRANT SELECT ON public.station_certifications TO authenticated;

-- Approved certificate files are readable by signed-in users.
DROP POLICY IF EXISTS "Verification docs: approved certs readable" ON storage.objects;
CREATE POLICY "Verification docs: approved certs readable" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'verification_docs' AND EXISTS (
    SELECT 1 FROM public.station_certifications c
    WHERE c.file_path = storage.objects.name AND c.status = 'approved'));

CREATE OR REPLACE FUNCTION public.submit_station_certification(
  p_cert_type text, p_issued_on date, p_expires_on date, p_file_path text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_uid AND role = 'owner') THEN
    RAISE EXCEPTION 'Only station owners upload certificates.';
  END IF;
  IF p_file_path IS NULL OR left(p_file_path, length(v_uid::text) + 7) <> v_uid::text || '/certs/' THEN
    RAISE EXCEPTION 'Upload the certificate file first.';
  END IF;
  IF p_expires_on <= current_date THEN
    RAISE EXCEPTION 'This certificate has already expired.';
  END IF;
  IF p_issued_on > current_date THEN
    RAISE EXCEPTION 'The issue date cannot be in the future.';
  END IF;
  INSERT INTO public.station_certifications (owner_id, cert_type, issued_on, expires_on, file_path)
  VALUES (v_uid, p_cert_type, p_issued_on, p_expires_on, p_file_path)
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('id', v_id, 'status', 'pending');
END; $$;

CREATE OR REPLACE FUNCTION public.admin_review_station_certification(
  p_cert_id uuid, p_approve boolean, p_reason text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_row public.station_certifications%ROWTYPE;
  v_status text := CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  IF NOT p_approve AND coalesce(trim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'Give the station a reason for the rejection.';
  END IF;
  UPDATE public.station_certifications
  SET status = v_status, reviewer_id = auth.uid(), reviewed_at = now(),
      rejection_reason = CASE WHEN p_approve THEN NULL ELSE trim(p_reason) END
  WHERE id = p_cert_id AND status = 'pending'
  RETURNING * INTO v_row;
  IF NOT FOUND THEN RAISE EXCEPTION 'This certificate was already reviewed.'; END IF;

  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (v_row.owner_id, 'system_alert', 'normal',
    CASE WHEN p_approve THEN 'Certificate approved' ELSE 'Certificate rejected' END,
    CASE WHEN p_approve THEN 'Customers can now see your certificate.'
         ELSE 'Reason: ' || trim(p_reason) END,
    jsonb_build_object('certificate_id', v_row.id, 'status', v_status));
  RETURN jsonb_build_object('id', v_row.id, 'status', v_status);
END; $$;

REVOKE ALL ON FUNCTION public.submit_station_certification(text, date, date, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_station_certification(text, date, date, text) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_review_station_certification(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_review_station_certification(uuid, boolean, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.expire_station_certifications()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_n integer;
BEGIN
  UPDATE public.station_certifications SET status = 'expired'
  WHERE status = 'approved' AND expires_on <= current_date;
  GET DIAGNOSTICS v_n = ROW_COUNT;

  WITH soon AS (
    UPDATE public.station_certifications SET expiry_warned_at = now()
    WHERE status = 'approved' AND expiry_warned_at IS NULL
      AND expires_on <= current_date + 14
    RETURNING owner_id, id, cert_type, expires_on
  )
  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  SELECT owner_id, 'system_alert', 'high', 'Certificate expiring soon',
         'Your ' || replace(cert_type, '_', ' ') || ' certificate expires on '
           || to_char(expires_on, 'Mon DD, YYYY') || '. Upload a new one to keep your badge.',
         jsonb_build_object('certificate_id', id)
  FROM soon;
  RETURN v_n;
END; $$;
REVOKE ALL ON FUNCTION public.expire_station_certifications() FROM PUBLIC, anon, authenticated;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'expire_station_certifications';
    PERFORM cron.schedule('expire_station_certifications', '15 16 * * *', 'SELECT public.expire_station_certifications()');
  END IF;
END $$;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Order disputes and refunds (2026-11-05)
-- ==============================================================================
-- Extends the existing public.disputes table (status enum: open,
-- investigating, resolved, dismissed) with the customer -> station -> admin
-- flow:
--   1. Customer opens a dispute within 48 h of delivery, one per order,
--      with optional photo evidence (private bucket dispute_evidence).
--   2. Station accepts (refund amount) -> resolved, or explains -> the
--      dispute is escalated ('investigating') for an admin.
--   3. Customer may escalate if the station has not answered in 24 h.
--   4. Admin resolves with an optional refund, or dismisses.
-- A granted refund books a REFUND ledger entry against the station, notifies
-- the customer, and refunds against the station increase flagged_count.
-- Money movement: COD refunds are returned by the station in cash; online
-- payments are refunded by the admin in PayMongo (orders.payment_status is
-- set to 'refunded' when the full total is refunded).
--
-- Test: supabase/tests/order_disputes_test.sql
-- ==============================================================================

ALTER TABLE public.disputes
  ADD COLUMN IF NOT EXISTS evidence_paths text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS owner_response text,
  ADD COLUMN IF NOT EXISTS owner_responded_at timestamptz,
  ADD COLUMN IF NOT EXISTS refund_amount numeric(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS escalated_at timestamptz;
ALTER TABLE public.disputes DROP CONSTRAINT IF EXISTS disputes_reason_check;
ALTER TABLE public.disputes ADD CONSTRAINT disputes_reason_check CHECK (reason IN (
  'missing_items', 'wrong_item', 'quality', 'damaged', 'not_delivered', 'overcharged', 'other'));
ALTER TABLE public.disputes DROP CONSTRAINT IF EXISTS disputes_refund_check;
ALTER TABLE public.disputes ADD CONSTRAINT disputes_refund_check CHECK (refund_amount >= 0);
CREATE UNIQUE INDEX IF NOT EXISTS disputes_one_per_order ON public.disputes (order_id);

-- Owners no longer update disputes directly; they use owner_respond_dispute.
DROP POLICY IF EXISTS "Owners can update disputes for their station" ON public.disputes;
REVOKE INSERT, DELETE ON public.disputes FROM anon, authenticated;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('dispute_evidence', 'dispute_evidence', false, 8388608,
        ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO UPDATE SET public = false;
DROP POLICY IF EXISTS "Dispute evidence: reporter upload" ON storage.objects;
CREATE POLICY "Dispute evidence: reporter upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'dispute_evidence' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "Dispute evidence: parties read" ON storage.objects;
CREATE POLICY "Dispute evidence: parties read" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'dispute_evidence' AND (
    (storage.foldername(name))[1] = auth.uid()::text
    OR public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.disputes d JOIN public.orders o ON o.id = d.order_id
      WHERE storage.objects.name = ANY (d.evidence_paths) AND o.owner_id = auth.uid())));

CREATE OR REPLACE FUNCTION public.open_dispute(
  p_order_id uuid, p_reason text, p_description text, p_evidence_paths text[] DEFAULT '{}'
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_order public.orders%ROWTYPE;
  v_done_at timestamptz;
  v_id uuid;
  v_path text;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id AND customer_id = v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order not found.'; END IF;
  IF v_order.status::text <> 'delivered' THEN
    RAISE EXCEPTION 'You can report a problem once the order is delivered.';
  END IF;
  v_done_at := coalesce(v_order.actual_completion_at, v_order.updated_at, v_order.created_at);
  IF v_done_at < now() - interval '48 hours' THEN
    RAISE EXCEPTION 'Problems must be reported within 48 hours of delivery.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.disputes WHERE order_id = p_order_id) THEN
    RAISE EXCEPTION 'A problem was already reported for this order.';
  END IF;
  IF coalesce(trim(p_description), '') = '' THEN
    RAISE EXCEPTION 'Tell the station what went wrong.';
  END IF;
  FOREACH v_path IN ARRAY coalesce(p_evidence_paths, '{}') LOOP
    IF left(v_path, length(v_uid::text) + 1) <> v_uid::text || '/' THEN
      RAISE EXCEPTION 'Invalid evidence photo.';
    END IF;
  END LOOP;

  INSERT INTO public.disputes (order_id, reporter_id, reason, description, status, evidence_paths)
  VALUES (p_order_id, v_uid, p_reason, trim(p_description), 'open', coalesce(p_evidence_paths, '{}'))
  RETURNING id INTO v_id;

  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (v_order.owner_id, 'system_alert', 'high', 'A customer reported a problem',
    'Order #' || upper(substr(p_order_id::text, 1, 8)) || ': ' || replace(p_reason, '_', ' ')
      || '. Please respond within 24 hours.',
    jsonb_build_object('dispute_id', v_id, 'order_id', p_order_id));
  RETURN jsonb_build_object('id', v_id, 'status', 'open');
END; $$;

-- Shared by station and admin resolutions.
CREATE OR REPLACE FUNCTION public.apply_dispute_refund(p_dispute_id uuid, p_amount numeric, p_note text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_d public.disputes%ROWTYPE;
  v_o public.orders%ROWTYPE;
BEGIN
  SELECT * INTO v_d FROM public.disputes WHERE id = p_dispute_id;
  SELECT * INTO v_o FROM public.orders WHERE id = v_d.order_id;
  IF p_amount < 0 OR p_amount > v_o.total_amount THEN
    RAISE EXCEPTION 'Refund must be between PHP 0 and the order total.';
  END IF;
  UPDATE public.disputes SET refund_amount = p_amount, status = 'resolved',
         resolution_notes = p_note, updated_at = now()
  WHERE id = p_dispute_id;
  IF p_amount > 0 THEN
    INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
    VALUES (v_o.owner_id, v_o.id, -p_amount, 'REFUND', 'Refund for reported problem');
    UPDATE public.profiles SET flagged_count = coalesce(flagged_count, 0) + 1 WHERE id = v_o.owner_id;
    IF p_amount >= v_o.total_amount THEN
      UPDATE public.orders SET payment_status = 'refunded' WHERE id = v_o.id;
    END IF;
  END IF;
  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (v_d.reporter_id, 'system_alert', 'high',
    CASE WHEN p_amount > 0 THEN 'Refund approved' ELSE 'Your report was reviewed' END,
    CASE WHEN p_amount > 0
      THEN 'PHP ' || trim(to_char(p_amount, '999990.00')) || ' will be returned '
        || CASE WHEN lower(coalesce(v_o.payment_method, 'cod')) IN ('cod', 'cash')
                THEN 'by the station in cash.' ELSE 'to your original payment method.' END
      ELSE coalesce(p_note, 'No refund was given.') END,
    jsonb_build_object('dispute_id', p_dispute_id, 'order_id', v_o.id, 'refund_amount', p_amount));
END; $$;
REVOKE ALL ON FUNCTION public.apply_dispute_refund(uuid, numeric, text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.owner_respond_dispute(
  p_dispute_id uuid, p_accept boolean, p_response text, p_refund_amount numeric DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_d public.disputes%ROWTYPE;
BEGIN
  SELECT d.* INTO v_d FROM public.disputes d JOIN public.orders o ON o.id = d.order_id
  WHERE d.id = p_dispute_id AND o.owner_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Dispute not found.'; END IF;
  IF v_d.status::text <> 'open' OR v_d.owner_responded_at IS NOT NULL THEN
    RAISE EXCEPTION 'This dispute was already answered.';
  END IF;
  IF coalesce(trim(p_response), '') = '' THEN RAISE EXCEPTION 'Write a reply to the customer.'; END IF;

  UPDATE public.disputes SET owner_response = trim(p_response), owner_responded_at = now(), updated_at = now()
  WHERE id = p_dispute_id;

  IF p_accept THEN
    PERFORM public.apply_dispute_refund(p_dispute_id, coalesce(p_refund_amount, 0), 'Station: ' || trim(p_response));
    RETURN jsonb_build_object('status', 'resolved');
  END IF;

  UPDATE public.disputes SET status = 'investigating', escalated_at = now() WHERE id = p_dispute_id;
  RETURN jsonb_build_object('status', 'investigating');
END; $$;

CREATE OR REPLACE FUNCTION public.escalate_dispute(p_dispute_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  UPDATE public.disputes SET status = 'investigating', escalated_at = now(), updated_at = now()
  WHERE id = p_dispute_id AND reporter_id = auth.uid() AND status = 'open'
    AND owner_responded_at IS NULL AND created_at < now() - interval '24 hours';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'You can ask eRefill to step in 24 hours after reporting if the station has not replied.';
  END IF;
  RETURN jsonb_build_object('status', 'investigating');
END; $$;

CREATE OR REPLACE FUNCTION public.admin_resolve_dispute(
  p_dispute_id uuid, p_refund_amount numeric, p_notes text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.disputes WHERE id = p_dispute_id AND status IN ('open', 'investigating')) THEN
    RAISE EXCEPTION 'This dispute is already closed.';
  END IF;
  UPDATE public.disputes SET resolved_by = auth.uid() WHERE id = p_dispute_id;
  PERFORM public.apply_dispute_refund(p_dispute_id, coalesce(p_refund_amount, 0), p_notes);
  IF coalesce(p_refund_amount, 0) = 0 THEN
    UPDATE public.disputes SET status = 'dismissed' WHERE id = p_dispute_id;
  END IF;
  RETURN jsonb_build_object('status', CASE WHEN coalesce(p_refund_amount, 0) > 0 THEN 'resolved' ELSE 'dismissed' END);
END; $$;

REVOKE ALL ON FUNCTION public.open_dispute(uuid, text, text, text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.open_dispute(uuid, text, text, text[]) TO authenticated;
REVOKE ALL ON FUNCTION public.owner_respond_dispute(uuid, boolean, text, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.owner_respond_dispute(uuid, boolean, text, numeric) TO authenticated;
REVOKE ALL ON FUNCTION public.escalate_dispute(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.escalate_dispute(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_resolve_dispute(uuid, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_resolve_dispute(uuid, numeric, text) TO authenticated;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- AI ordering assistant: per-user daily message limit (2026-11-05)
-- ==============================================================================
-- The order-assistant Edge Function records one row per message (with the
-- service role) and refuses more than 20 per user in 24 hours.
-- Users can read their own usage; nobody writes from the app.
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.assistant_usage (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  input_tokens integer NOT NULL DEFAULT 0,
  output_tokens integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_assistant_usage_user_time ON public.assistant_usage (user_id, created_at DESC);

ALTER TABLE public.assistant_usage ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users read own assistant usage" ON public.assistant_usage;
CREATE POLICY "Users read own assistant usage" ON public.assistant_usage
  FOR SELECT TO authenticated USING (user_id = auth.uid());
REVOKE INSERT, UPDATE, DELETE ON public.assistant_usage FROM anon, authenticated;
GRANT SELECT ON public.assistant_usage TO authenticated;

-- Shared fixtures for the SQL tests in this folder. Every test runs as
--   BEGIN; <scripts under test, BEGIN/COMMIT stripped>; _fixtures.sql; <test>; ROLLBACK;
-- through the Supabase MCP execute_sql tool, so nothing persists.
--
-- Fixture rows are inserted with triggers off (replica role) to skip station
-- setup checks; triggers are back on before the test body runs.
--
-- ids: owner ...a1, second owner ...a2, customer ...c1, rider ...d1,
--      admin ...e1, product ...b1 (₱19.60, owner a1).

SET LOCAL session_replication_role = replica;

INSERT INTO auth.users (id, instance_id, aud, role, email, raw_user_meta_data, raw_app_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_owner@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000a2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_owner2@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_cust@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_rider@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_admin@example.test', '{}', '{}', now(), now());

INSERT INTO public.profiles (id, role, full_name, station_name, station_availability, latitude, longitude)
VALUES
  ('00000000-0000-4000-8000-0000000000a1', 'owner', 'T Owner', 'T Station', 'open', 14.60, 121.00),
  ('00000000-0000-4000-8000-0000000000a2', 'owner', 'T Owner 2', 'T Station 2', 'open', 14.61, 121.01),
  ('00000000-0000-4000-8000-0000000000c1', 'customer', 'T Cust', NULL, 'open', 14.62, 121.02),
  ('00000000-0000-4000-8000-0000000000d1', 'rider', 'T Rider', NULL, 'open', NULL, NULL),
  ('00000000-0000-4000-8000-0000000000e1', 'admin', 'T Admin', NULL, 'open', NULL, NULL);

INSERT INTO public.owner_settings (owner_id, base_delivery_fee)
VALUES
  ('00000000-0000-4000-8000-0000000000a1', 5.4),
  ('00000000-0000-4000-8000-0000000000a2', 0);

INSERT INTO public.products (id, owner_id, name, price, is_available)
VALUES ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000a1', 'T Water', 19.6, true);

-- Fee config used by every test unless a test overrides it.
UPDATE public.system_config SET value = '{"enabled": true, "percent": 1, "fixed": 0}'::jsonb
WHERE key = 'platform_fee';

SET LOCAL session_replication_role = origin;

-- Helpers (temporary: dropped with the transaction).
CREATE OR REPLACE FUNCTION pg_temp.act_as(p_user uuid) RETURNS void
LANGUAGE sql AS $$
  SELECT set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text,
    true
  );
$$;

CREATE OR REPLACE FUNCTION pg_temp.place_order(p_method text, p_qty integer DEFAULT 1)
RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  RETURN public.create_order_atomic(
    jsonb_build_object(
      'owner_id', '00000000-0000-4000-8000-0000000000a1',
      'payment_method', p_method,
      'customer_name', 'T Cust',
      'customer_address', 'Test address',
      'customer_latitude', '14.6',
      'customer_longitude', '121.0'
    ),
    jsonb_build_array(jsonb_build_object(
      'product_id', '00000000-0000-4000-8000-0000000000b1',
      'quantity', p_qty,
      'product_name', 'T Water'
    ))
  );
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.assert_eq(p_label text, p_actual anyelement, p_expected anyelement)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF p_actual IS DISTINCT FROM p_expected THEN
    RAISE EXCEPTION '% — expected %, got %', p_label, p_expected, p_actual;
  END IF;
END;
$$;

-- Runs p_sql and fails unless it raises an error containing p_message.
CREATE OR REPLACE FUNCTION pg_temp.expect_error(p_label text, p_sql text, p_message text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    IF position(p_message IN SQLERRM) = 0 THEN
      RAISE EXCEPTION '% — expected error "%", got "%"', p_label, p_message, SQLERRM;
    END IF;
    RETURN;
  END;
  RAISE EXCEPTION '% — expected error "%", but it succeeded', p_label, p_message;
END;
$$;
-- Run: bash build.sh ../scripts/harden_signup_and_protected_columns.sql ../scripts/delivery_coverage.sql ../scripts/station_accessories.sql ../scripts/rider_tips.sql ../scripts/identity_verification.sql ../scripts/order_pricing_v3.sql -- accessories_test.sql

-- Fixture station must be verified to take orders (identity_verification.sql).
UPDATE public.profiles SET verification_status = 'approved' WHERE id = '00000000-0000-4000-8000-0000000000a1';
-- Owner a1 has water product b1 (₱19.60).

-- owner_can_add_an_accessory
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1'); SET LOCAL ROLE authenticated;
  INSERT INTO public.products (id, owner_id, name, price, category, kind, stock_level, is_available)
  VALUES ('00000000-0000-4000-8000-0000000000b2', '00000000-0000-4000-8000-0000000000a1',
          'Gallon cap', 5, 'cap', 'accessory', 3, true);
  RESET ROLE;
  PERFORM pg_temp.assert_eq('accessory added',
    (SELECT count(*) FROM public.products WHERE owner_id = '00000000-0000-4000-8000-0000000000a1'), 2::bigint);
END $$;

-- owner_cannot_add_a_second_water_product
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1'); SET LOCAL ROLE authenticated;
  PERFORM pg_temp.expect_error('second water',
    $q$INSERT INTO public.products (owner_id, name, price, kind)
       VALUES ('00000000-0000-4000-8000-0000000000a1', 'More water', 10, 'water')$q$,
    'row-level security');
  RESET ROLE;
END $$;

-- owner_cannot_add_accessory_for_another_station
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1'); SET LOCAL ROLE authenticated;
  PERFORM pg_temp.expect_error('other station',
    $q$INSERT INTO public.products (owner_id, name, price, category, kind)
       VALUES ('00000000-0000-4000-8000-0000000000a2', 'Seal', 2, 'seal', 'accessory')$q$,
    'row-level security');
  RESET ROLE;
END $$;

-- accessory_rename_allowed_water_rename_blocked
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1'); SET LOCAL ROLE authenticated;
  UPDATE public.products SET name = 'Blue cap' WHERE id = '00000000-0000-4000-8000-0000000000b2';
  PERFORM pg_temp.expect_error('water rename',
    $q$UPDATE public.products SET name = 'Renamed' WHERE id = '00000000-0000-4000-8000-0000000000b1'$q$,
    'Stations can only change the price and availability of their water.');
  RESET ROLE;
  PERFORM pg_temp.assert_eq('renamed',
    (SELECT name FROM public.products WHERE id = '00000000-0000-4000-8000-0000000000b2'), 'Blue cap');
END $$;

-- accessory_price_does_not_overwrite_water_price
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1'); SET LOCAL ROLE authenticated;
  UPDATE public.products SET price = 7 WHERE id = '00000000-0000-4000-8000-0000000000b2';
  RESET ROLE;
  PERFORM pg_temp.assert_eq('water price kept',
    (SELECT price_per_gallon::numeric FROM public.profiles WHERE id = '00000000-0000-4000-8000-0000000000a1')
      IS DISTINCT FROM 7, true);
END $$;

-- order_with_accessory_priced_on_server_and_stock_deducted
DO $$ DECLARE r jsonb; BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  r := public.create_order_atomic(
    jsonb_build_object('owner_id', '00000000-0000-4000-8000-0000000000a1', 'payment_method', 'cod',
      'customer_name', 'T Cust', 'customer_address', 'Test', 'customer_latitude', '14.6', 'customer_longitude', '121.0'),
    jsonb_build_array(
      jsonb_build_object('product_id', '00000000-0000-4000-8000-0000000000b1', 'quantity', 2, 'product_name', 'T Water'),
      jsonb_build_object('product_id', '00000000-0000-4000-8000-0000000000b2', 'quantity', 2, 'product_name', 'Blue cap', 'price', 0.01))
  );
  PERFORM pg_temp.assert_eq('subtotal', (r->>'subtotal')::numeric, (19.6 * 2 + 7 * 2)::numeric);
  PERFORM pg_temp.assert_eq('stock deducted',
    (SELECT stock_level FROM public.products WHERE id = '00000000-0000-4000-8000-0000000000b2'), 1);
END $$;

-- accessories_do_not_count_toward_free_gallons
DO $$ DECLARE q jsonb; r jsonb; BEGIN
  UPDATE public.owner_settings SET free_delivery_min_gallons = 3, free_delivery_radius_km = 0
  WHERE owner_id = '00000000-0000-4000-8000-0000000000a1';
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  r := public.create_order_atomic(
    jsonb_build_object('owner_id', '00000000-0000-4000-8000-0000000000a1', 'payment_method', 'cod',
      'customer_name', 'T Cust', 'customer_address', 'Test', 'customer_latitude', '14.65', 'customer_longitude', '121.0'),
    jsonb_build_array(
      jsonb_build_object('product_id', '00000000-0000-4000-8000-0000000000b1', 'quantity', 2, 'product_name', 'T Water'),
      jsonb_build_object('product_id', '00000000-0000-4000-8000-0000000000b2', 'quantity', 1, 'product_name', 'Blue cap'))
  );
  PERFORM pg_temp.assert_eq('not free', (r->>'delivery_free_reason') IS NULL, true);
END $$;

SELECT 'accessories_test: all passed' AS result;
ROLLBACK;

-- ===== rider_tips_test =====
BEGIN;
-- ==============================================================================
-- Harden signup roles and protect trust columns on profiles (2026-11-05)
-- ==============================================================================
-- 1. Self-signup could claim role 'admin' or 'rider' through user metadata.
--    Only accounts created by a trusted server function (admin_create_user,
--    create_rider_account, admin_create_station) may get privileged roles.
--    Self-signups arrive through the Auth server, whose session user is
--    supabase_auth_admin; those are limited to customer/owner.
-- 2. Users could UPDATE their own average_rating / review_count /
--    reliability_score / flagged_count. Those are now writable only by admins
--    or by SECURITY DEFINER functions (e.g. update_station_stats()).
-- 3. Adds profiles.verification_status (used by identity verification), which is
--    protected the same way.
--
-- Run after: single_water_product_catalog.sql. Test: supabase/tests/protected_columns_test.sql
-- ==============================================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS verification_status text NOT NULL DEFAULT 'unverified';
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_verification_status_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_verification_status_check
  CHECK (verification_status IN ('unverified', 'pending', 'approved', 'rejected'));

-- 1. Role resolution -----------------------------------------------------------
CREATE OR REPLACE FUNCTION public.resolve_signup_role(p_requested text, p_trusted boolean)
RETURNS public.user_role
LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN p_requested IN ('customer', 'owner') THEN p_requested::public.user_role
    WHEN p_trusted AND p_requested IN ('rider', 'admin') THEN p_requested::public.user_role
    ELSE 'customer'::public.user_role
  END;
$$;
REVOKE ALL ON FUNCTION public.resolve_signup_role(text, boolean) FROM PUBLIC, anon, authenticated;

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
  -- 1. Role: self-signups (Auth server session) may only be customer or owner.
  v_role := public.resolve_signup_role(
    new.raw_user_meta_data->>'role',
    session_user <> 'supabase_auth_admin'
  );

  -- 2. Safe municipality enum resolution
  IF lower(trim(COALESCE(new.raw_user_meta_data->>'town', ''))) = 'cantilan' THEN
    v_town := 'Cantilan'::public.municipality;
  ELSIF lower(trim(COALESCE(new.raw_user_meta_data->>'town', ''))) = 'madrid' THEN
    v_town := 'Madrid'::public.municipality;
  ELSE
    v_town := NULL;
  END IF;

  v_complete_address := NULLIF(TRIM(COALESCE(new.raw_user_meta_data->>'complete_address', '')), '');

  -- 3. Names (Google OAuth sends 'name', 'given_name', 'family_name', 'picture')
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

  -- 5. Upsert profile
  INSERT INTO public.profiles (
    id, email, username, full_name, first_name, last_name, mi, suffix, role,
    phone, town, barangay, complete_address, landmark, station_name,
    avatar_url, latitude, longitude, primary_water_type
  )
  VALUES (
    new.id, new.email, v_username, v_full_name, v_first_name, v_last_name,
    new.raw_user_meta_data->>'mi', new.raw_user_meta_data->>'suffix', v_role,
    new.raw_user_meta_data->>'phone', v_town, new.raw_user_meta_data->>'barangay',
    v_complete_address, new.raw_user_meta_data->>'landmark',
    new.raw_user_meta_data->>'station_name', v_avatar_url,
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

-- 2. Protected trust columns -----------------------------------------------------
-- SECURITY INVOKER on purpose: current_user is 'authenticated'/'anon' for direct
-- client writes, and the function owner (postgres) inside SECURITY DEFINER
-- functions such as update_station_stats() and the admin RPCs.
CREATE OR REPLACE FUNCTION public.guard_profile_protected_columns()
RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;

  IF NEW.average_rating IS NOT DISTINCT FROM OLD.average_rating
    AND NEW.review_count IS NOT DISTINCT FROM OLD.review_count
    AND NEW.reliability_score IS NOT DISTINCT FROM OLD.reliability_score
    AND NEW.flagged_count IS NOT DISTINCT FROM OLD.flagged_count
    AND NEW.verification_status IS NOT DISTINCT FROM OLD.verification_status
  THEN
    RETURN NEW;
  END IF;

  IF public.is_admin() THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'Unauthorized: You cannot alter protected account fields.';
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_profile_protected_columns ON public.profiles;
CREATE TRIGGER trg_guard_profile_protected_columns
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.guard_profile_protected_columns();


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Delivery coverage: free-delivery zones + distance-based fees (2026-11-05)
-- ==============================================================================
-- Each station defines where delivery is free:
--   * within free_delivery_radius_km of the station (default 1 km), OR
--   * to any barangay listed in free_delivery_barangays, OR
--   * when the order has at least free_delivery_min_gallons water gallons.
-- Everywhere else pays the platform's per-km rate from
-- system_config.delivery_fee_config (rate_per_km, minimum_fee,
-- min_billable_distance_km, rounding_rule, enabled).
--
-- Distance = straight-line (haversine) x 1.3 road factor, so it approximates
-- real road distance without calling a routing service from the database.
--
-- Self-contained: does not depend on delivery_fee_config_rpcs.sql.
-- Run before: order_pricing_v3.sql. Test: supabase/tests/delivery_quote_test.sql
-- ==============================================================================

ALTER TABLE public.owner_settings
  ADD COLUMN IF NOT EXISTS free_delivery_radius_km numeric(4,1) NOT NULL DEFAULT 1.0,
  ADD COLUMN IF NOT EXISTS free_delivery_barangays text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS free_delivery_min_gallons integer;

ALTER TABLE public.owner_settings DROP CONSTRAINT IF EXISTS owner_settings_free_radius_check;
ALTER TABLE public.owner_settings ADD CONSTRAINT owner_settings_free_radius_check
  CHECK (free_delivery_radius_km >= 0 AND free_delivery_radius_km <= 10);
ALTER TABLE public.owner_settings DROP CONSTRAINT IF EXISTS owner_settings_free_min_gallons_check;
ALTER TABLE public.owner_settings ADD CONSTRAINT owner_settings_free_min_gallons_check
  CHECK (free_delivery_min_gallons IS NULL OR free_delivery_min_gallons BETWEEN 1 AND 100);

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS delivery_distance_km numeric(6,2),
  ADD COLUMN IF NOT EXISTS delivery_rate_per_km numeric(8,2),
  ADD COLUMN IF NOT EXISTS delivery_free_reason text;

-- Road factor applied to straight-line distance.
CREATE OR REPLACE FUNCTION public.delivery_road_distance_km(
  p_lat1 double precision, p_lng1 double precision,
  p_lat2 double precision, p_lng2 double precision
) RETURNS numeric
LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN p_lat1 IS NULL OR p_lng1 IS NULL OR p_lat2 IS NULL OR p_lng2 IS NULL THEN NULL
    ELSE round((
      2 * 6371 * asin(sqrt(
        power(sin(radians(p_lat2 - p_lat1) / 2), 2)
        + cos(radians(p_lat1)) * cos(radians(p_lat2))
          * power(sin(radians(p_lng2 - p_lng1) / 2), 2)
      )) * 1.3
    )::numeric, 2)
  END;
$$;

-- Fee for a distance outside the free zone, from the admin's config.
CREATE OR REPLACE FUNCTION public.delivery_fee_for_distance(p_km numeric)
RETURNS numeric
LANGUAGE plpgsql STABLE SET search_path TO 'public' AS $$
DECLARE
  v_cfg jsonb;
  v_rate numeric;
  v_min numeric;
  v_min_km numeric;
  v_rule text;
  v_fee numeric;
BEGIN
  SELECT value INTO v_cfg FROM public.system_config WHERE key = 'delivery_fee_config';
  v_cfg := coalesce(v_cfg, '{}'::jsonb);
  IF NOT coalesce((v_cfg->>'enabled')::boolean, true) THEN
    RETURN 0;
  END IF;
  v_rate := greatest(coalesce((v_cfg->>'rate_per_km')::numeric, 10), 0);
  v_min := greatest(coalesce((v_cfg->>'minimum_fee')::numeric, 20), 0);
  v_min_km := greatest(coalesce((v_cfg->>'min_billable_distance_km')::numeric, 1), 0);
  v_rule := lower(trim(coalesce(v_cfg->>'rounding_rule', 'exact')));

  IF p_km IS NULL THEN
    RETURN v_min;
  END IF;

  -- Same rule as CheckoutRules.calculateDeliveryFee in the app: the rounding
  -- rule applies to the billable distance; the fee is whole pesos.
  v_fee := greatest(p_km, v_min_km);
  v_fee := CASE
    WHEN v_rule IN ('ceil', 'round_up') THEN ceil(v_fee)
    WHEN v_rule IN ('round', 'round_nearest') THEN round(v_fee)
    ELSE v_fee
  END;
  IF v_rate <= 0 THEN
    RETURN 0;
  END IF;
  RETURN round(greatest(v_rate * v_fee, v_min));
END;
$$;

-- Quote shown at checkout and charged by create_order_atomic.
CREATE OR REPLACE FUNCTION public.compute_delivery_quote(
  p_station_id uuid,
  p_lat double precision,
  p_lng double precision,
  p_barangay text DEFAULT NULL,
  p_gallons integer DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_slat double precision;
  v_slng double precision;
  v_radius numeric;
  v_barangays text[];
  v_min_gallons integer;
  v_km numeric;
  v_reason text;
  v_cfg jsonb;
BEGIN
  SELECT coalesce(p.latitude, p.lat), coalesce(p.longitude, p.lng)
  INTO v_slat, v_slng
  FROM public.profiles p
  WHERE p.id = p_station_id AND p.role = 'owner';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Water refill station not found.';
  END IF;

  SELECT coalesce(os.free_delivery_radius_km, 1.0),
         coalesce(os.free_delivery_barangays, '{}'),
         os.free_delivery_min_gallons
  INTO v_radius, v_barangays, v_min_gallons
  FROM public.owner_settings os WHERE os.owner_id = p_station_id;
  v_radius := coalesce(v_radius, 1.0);
  v_barangays := coalesce(v_barangays, '{}');

  v_km := public.delivery_road_distance_km(v_slat, v_slng, p_lat, p_lng);

  IF v_km IS NOT NULL AND v_km <= v_radius THEN
    v_reason := 'radius';
  ELSIF p_barangay IS NOT NULL AND EXISTS (
    SELECT 1 FROM unnest(v_barangays) b
    WHERE lower(trim(b)) = lower(trim(p_barangay))
  ) THEN
    v_reason := 'barangay';
  ELSIF v_min_gallons IS NOT NULL AND coalesce(p_gallons, 0) >= v_min_gallons THEN
    v_reason := 'min_gallons';
  END IF;

  SELECT value INTO v_cfg FROM public.system_config WHERE key = 'delivery_fee_config';

  RETURN jsonb_build_object(
    'distance_km', v_km,
    'is_free', v_reason IS NOT NULL,
    'free_reason', v_reason,
    'fee', CASE WHEN v_reason IS NOT NULL THEN 0 ELSE public.delivery_fee_for_distance(v_km) END,
    'rate_per_km', coalesce((v_cfg->>'rate_per_km')::numeric, 10),
    'minimum_fee', coalesce((v_cfg->>'minimum_fee')::numeric, 20),
    'free_radius_km', v_radius,
    'free_barangays', to_jsonb(v_barangays),
    'free_min_gallons', v_min_gallons
  );
END;
$$;

REVOKE ALL ON FUNCTION public.compute_delivery_quote(uuid, double precision, double precision, text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.compute_delivery_quote(uuid, double precision, double precision, text, integer) TO authenticated;
REVOKE ALL ON FUNCTION public.delivery_fee_for_distance(numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delivery_fee_for_distance(numeric) TO authenticated;


NOTIFY pgrst, 'reload schema';
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


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Rider tips (2026-11-05)
-- ==============================================================================
-- Customers can add an optional tip (₱0–₱500, whole pesos) at checkout for
-- delivery orders. It is part of the single charge (COD or PayMongo), so no
-- second payment is needed, and 100% goes to the rider:
--   * excluded from the station SALE and from the 10% commission base
--   * booked as a RIDER_TIP ledger entry to the assigned rider
--   * if no rider was assigned (station delivered itself) it stays with the
--     station as part of the SALE
-- create_order_atomic reads p_order_data->>'tip_amount' (order_pricing_v3.sql).
--
-- Run before: order_pricing_v3.sql. Test: supabase/tests/rider_tips_test.sql
-- ==============================================================================

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS tip_amount numeric(10,2) NOT NULL DEFAULT 0;
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_tip_amount_check;
ALTER TABLE public.orders ADD CONSTRAINT orders_tip_amount_check
  CHECK (tip_amount >= 0 AND tip_amount <= 500);

CREATE OR REPLACE FUNCTION public.proc_finalize_order_finances()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    v_commission NUMERIC;
    v_fee NUMERIC := greatest(coalesce(NEW.platform_fee, 0), 0);
    v_tip NUMERIC := greatest(coalesce(NEW.tip_amount, 0), 0);
    v_rider_tip NUMERIC := 0;
BEGIN
    IF NEW.status = 'delivered' AND OLD.status != 'delivered' THEN
        -- The tip belongs to the rider; without a rider it stays in the sale.
        IF NEW.assigned_rider_id IS NOT NULL THEN
            v_rider_tip := v_tip;
        END IF;

        INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
        VALUES (NEW.owner_id, NEW.id, NEW.total_amount - v_fee - v_rider_tip, 'SALE', 'Order completion payment');

        IF v_fee > 0 THEN
            INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description, metadata)
            VALUES (
                NEW.owner_id, NEW.id, v_fee, 'SERVICE_FEE', 'Platform service fee',
                jsonb_build_object('payee', 'platform', 'payment_method', NEW.payment_method)
            );

            IF lower(coalesce(NEW.payment_method, 'cod')) IN ('cod', 'cash', 'credit') THEN
                PERFORM public.apply_wallet_entry(
                    NEW.owner_id, -v_fee, 'service_fee', NEW.id, NULL,
                    'Service fee for order ' || upper(substr(NEW.id::text, 1, 8))
                );
            END IF;
        END IF;

        -- Commission excludes the tip.
        v_commission := (NEW.total_amount - v_tip) * 0.10;

        IF NEW.assigned_rider_id IS NOT NULL THEN
            INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
            VALUES (NEW.assigned_rider_id, NEW.id, v_commission, 'COMMISSION', 'Delivery commission for order');

            IF v_rider_tip > 0 THEN
                INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
                VALUES (NEW.assigned_rider_id, NEW.id, v_rider_tip, 'RIDER_TIP', 'Customer tip');

                INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
                VALUES (
                    NEW.assigned_rider_id, 'system_alert', 'normal', 'You got a tip!',
                    'A customer tipped you PHP ' || trim(to_char(v_rider_tip, '999990')) || '. Thank you for the great service.',
                    jsonb_build_object('order_id', NEW.id, 'tip_amount', v_rider_tip)
                );
            END IF;
        END IF;

        INSERT INTO public.domain_events (event_type, payload, actor_id)
        VALUES ('ORDER_COMPLETED', jsonb_build_object(
            'order_id', NEW.id, 'total', NEW.total_amount,
            'rider_id', NEW.assigned_rider_id, 'tip', v_tip), auth.uid());
    END IF;
    RETURN NEW;
END;
$$;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Seller and customer ID verification (2026-11-05)
-- ==============================================================================
-- Users upload a government ID (front, back, selfie; owners also a business
-- permit) to the private bucket verification_docs under <their uid>/.
-- An admin reviews and approves or rejects. profiles.verification_status
-- (added and write-protected by harden_signup_and_protected_columns.sql) is
-- only changed by the RPCs below.
--
-- Gates (enforced in create_order_atomic, order_pricing_v3.sql):
--   * stations must be 'approved' to receive orders
--   * unverified customers: cash-on-delivery up to PHP 1,000 and at most
--     2 active COD orders; verified customers have no limit
-- Backfill: owners who already completed a delivery are approved (legacy).
--
-- Run after: harden_signup_and_protected_columns.sql
-- Run before: order_pricing_v3.sql. Test: supabase/tests/identity_verification_test.sql
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.identity_verifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role text NOT NULL,
  id_type text NOT NULL CHECK (id_type IN (
    'philsys', 'drivers_license', 'umid', 'passport', 'postal', 'voters', 'prc', 'other')),
  id_number_last4 text CHECK (id_number_last4 ~ '^[0-9A-Za-z]{4}$'),
  front_path text NOT NULL,
  back_path text,
  selfie_path text NOT NULL,
  business_permit_path text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  reviewer_id uuid REFERENCES public.profiles(id),
  reviewed_at timestamptz,
  rejection_reason text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_identity_verifications_user ON public.identity_verifications (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_identity_verifications_pending ON public.identity_verifications (created_at) WHERE status = 'pending';

ALTER TABLE public.identity_verifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users read own verifications" ON public.identity_verifications;
CREATE POLICY "Users read own verifications" ON public.identity_verifications
  FOR SELECT TO authenticated USING (auth.uid() = user_id OR public.is_admin());
-- Writes only through the RPCs below.
REVOKE INSERT, UPDATE, DELETE ON public.identity_verifications FROM anon, authenticated;
GRANT SELECT ON public.identity_verifications TO authenticated;

-- Private bucket, one folder per user.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('verification_docs', 'verification_docs', false, 8388608,
        ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
ON CONFLICT (id) DO UPDATE SET public = false;

DROP POLICY IF EXISTS "Verification docs: owner upload" ON storage.objects;
CREATE POLICY "Verification docs: owner upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'verification_docs' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "Verification docs: owner or admin read" ON storage.objects;
CREATE POLICY "Verification docs: owner or admin read" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'verification_docs'
         AND ((storage.foldername(name))[1] = auth.uid()::text OR public.is_admin()));

CREATE OR REPLACE FUNCTION public.submit_identity_verification(
  p_id_type text,
  p_id_number_last4 text,
  p_front_path text,
  p_back_path text,
  p_selfie_path text,
  p_business_permit_path text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_role text;
  v_status text;
  v_prefix text;
  v_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required.'; END IF;
  SELECT role::text, verification_status INTO v_role, v_status FROM public.profiles WHERE id = v_uid;
  IF v_role NOT IN ('customer', 'owner') THEN
    RAISE EXCEPTION 'Only customers and station owners verify their ID here.';
  END IF;
  IF v_status = 'approved' THEN RAISE EXCEPTION 'Your ID is already verified.'; END IF;
  IF v_status = 'pending' THEN RAISE EXCEPTION 'Your ID is already being reviewed.'; END IF;

  v_prefix := v_uid::text || '/';
  IF p_front_path IS NULL OR p_selfie_path IS NULL
     OR left(p_front_path, length(v_prefix)) <> v_prefix
     OR left(p_selfie_path, length(v_prefix)) <> v_prefix
     OR (p_back_path IS NOT NULL AND left(p_back_path, length(v_prefix)) <> v_prefix)
     OR (p_business_permit_path IS NOT NULL AND left(p_business_permit_path, length(v_prefix)) <> v_prefix) THEN
    RAISE EXCEPTION 'Upload your ID photos before submitting.';
  END IF;
  IF v_role = 'owner' AND p_business_permit_path IS NULL THEN
    RAISE EXCEPTION 'Stations must also upload a business or sanitary permit.';
  END IF;

  INSERT INTO public.identity_verifications (
    user_id, role, id_type, id_number_last4, front_path, back_path, selfie_path, business_permit_path)
  VALUES (v_uid, v_role, p_id_type, NULLIF(p_id_number_last4, ''), p_front_path, p_back_path,
          p_selfie_path, p_business_permit_path)
  RETURNING id INTO v_id;

  UPDATE public.profiles SET verification_status = 'pending' WHERE id = v_uid;
  RETURN jsonb_build_object('id', v_id, 'status', 'pending');
END; $$;

CREATE OR REPLACE FUNCTION public.admin_review_identity_verification(
  p_verification_id uuid,
  p_approve boolean,
  p_reason text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_row public.identity_verifications%ROWTYPE;
  v_status text := CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  IF NOT p_approve AND coalesce(trim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'Give the user a reason for the rejection.';
  END IF;

  UPDATE public.identity_verifications
  SET status = v_status, reviewer_id = auth.uid(), reviewed_at = now(),
      rejection_reason = CASE WHEN p_approve THEN NULL ELSE trim(p_reason) END
  WHERE id = p_verification_id AND status = 'pending'
  RETURNING * INTO v_row;
  IF NOT FOUND THEN RAISE EXCEPTION 'This verification was already reviewed.'; END IF;

  UPDATE public.profiles SET verification_status = v_status WHERE id = v_row.user_id;

  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (
    v_row.user_id, 'system_alert', 'high',
    CASE WHEN p_approve THEN 'Your ID is verified' ELSE 'ID verification needs another try' END,
    CASE WHEN p_approve
      THEN CASE WHEN v_row.role = 'owner'
        THEN 'Your station is verified and can now receive orders.'
        ELSE 'Your account is verified. Order limits are lifted.' END
      ELSE 'Reason: ' || trim(p_reason) || '. You can submit new photos.' END,
    jsonb_build_object('verification_id', v_row.id, 'status', v_status)
  );

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, new_value, metadata)
  VALUES (auth.uid(), 'identity_verification_' || v_status, 'identity_verifications', v_row.id::text,
          jsonb_build_object('status', v_status),
          jsonb_build_object('user_id', v_row.user_id, 'reason', p_reason));

  RETURN jsonb_build_object('id', v_row.id, 'status', v_status);
END; $$;

REVOKE ALL ON FUNCTION public.submit_identity_verification(text, text, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_identity_verification(text, text, text, text, text, text) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_review_identity_verification(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_review_identity_verification(uuid, boolean, text) TO authenticated;

-- Order gate helper, used by create_order_atomic.
CREATE OR REPLACE FUNCTION public.assert_order_allowed_by_verification(
  p_customer_id uuid, p_owner_id uuid, p_payment_method text, p_total numeric
) RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_owner_status text;
  v_customer_status text;
  v_active int;
BEGIN
  SELECT verification_status INTO v_owner_status FROM public.profiles WHERE id = p_owner_id;
  IF coalesce(v_owner_status, 'unverified') <> 'approved' THEN
    RAISE EXCEPTION 'This station is not verified yet and cannot take orders.';
  END IF;

  SELECT verification_status INTO v_customer_status FROM public.profiles WHERE id = p_customer_id;
  IF coalesce(v_customer_status, 'unverified') = 'approved'
     OR lower(coalesce(p_payment_method, 'cod')) NOT IN ('cod', 'cash') THEN
    RETURN;
  END IF;

  IF p_total > 1000 THEN
    RAISE EXCEPTION 'Verify your ID to place cash-on-delivery orders above PHP 1,000.';
  END IF;
  SELECT count(*) INTO v_active FROM public.orders
  WHERE customer_id = p_customer_id
    AND lower(coalesce(payment_method, 'cod')) IN ('cod', 'cash')
    AND status NOT IN ('delivered', 'cancelled', 'failed');
  IF v_active >= 2 THEN
    RAISE EXCEPTION 'Verify your ID to have more than 2 cash-on-delivery orders at a time.';
  END IF;
END; $$;
REVOKE ALL ON FUNCTION public.assert_order_allowed_by_verification(uuid, uuid, text, numeric) FROM PUBLIC, anon, authenticated;

-- Backfill: stations that already delivered orders keep working.
UPDATE public.profiles p SET verification_status = 'approved'
WHERE p.role = 'owner' AND p.verification_status = 'unverified'
  AND EXISTS (SELECT 1 FROM public.orders o WHERE o.owner_id = p.id AND o.status = 'delivered');


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- create_order_atomic v3 (2026-11-05)
-- ==============================================================================
-- Starts from the LIVE definition (pg_get_functiondef on 2026-11-05; note the
-- live function does not use price_order() from whole_peso_pricing.sql).
-- Changes:
--   * Delivery fee comes from compute_delivery_quote() (free zone or per-km),
--     never from the client and no longer from owner_settings.base_delivery_fee.
--   * Writes delivery_distance_km, delivery_rate_per_km, delivery_free_reason.
--   * Accessories (products.kind = 'accessory') are sold alongside water;
--     only water gallons count toward the free-delivery gallon threshold.
--   * Optional rider tip (tip_amount, ₱0–₱500) added to the total.
--   * ID verification gates: approved stations only; COD limits for
--     unverified customers.
-- This is the single place later features (accessories, tips, verification
-- gates) extend create_order_atomic. Do not redefine it in other scripts.
--
-- Run order: harden_signup_and_protected_columns.sql -> delivery_coverage.sql ->
--   station_accessories.sql -> rider_tips.sql -> identity_verification.sql -> this file.
-- Tests: supabase/tests/delivery_quote_test.sql, accessories_test.sql
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.create_order_atomic(p_order_data jsonb, p_items_data jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_customer_id uuid := auth.uid();
  v_owner_id uuid;
  v_payment_method text;
  v_idempotency_key public.orders.idempotency_key%TYPE;
  v_voucher_id uuid;
  v_order_id uuid;
  v_item record;
  v_product record;
  v_computed_subtotal numeric(10,2) := 0;
  v_delivery_fee numeric(10,2) := 0;
  v_platform_fee numeric(10,2) := 0;
  v_discount numeric(10,2) := 0;
  v_total_amount numeric(10,2) := 0;
  v_order_row public.orders%ROWTYPE;
  v_voucher public.customer_reward_vouchers%ROWTYPE;
  v_config jsonb;
  v_lat double precision;
  v_lng double precision;
  v_maintenance jsonb;
  v_is_maintenance boolean := false;
  v_customer_suspended boolean := false;
  v_owner_suspended boolean := false;
  v_gallons integer := 0;
  v_quote jsonb;
  v_tip numeric(10,2) := 0;
BEGIN
  SELECT value INTO v_maintenance
  FROM public.system_config
  WHERE key = 'maintenance_mode';

  IF v_maintenance IS NOT NULL THEN
    IF jsonb_typeof(v_maintenance) = 'boolean' THEN
      v_is_maintenance := v_maintenance::text::boolean;
    ELSIF jsonb_typeof(v_maintenance) = 'string' THEN
      v_is_maintenance :=
        lower(trim(both '"' from v_maintenance::text)) IN ('true', '1', 'yes');
    END IF;
  END IF;

  IF v_is_maintenance THEN
    RAISE EXCEPTION 'System is currently undergoing maintenance. New orders are temporarily paused.';
  END IF;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required to place an order.';
  END IF;

  SELECT coalesce(is_suspended, false) INTO v_customer_suspended
  FROM public.profiles
  WHERE id = v_customer_id AND role = 'customer';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Only customer accounts can place orders.';
  END IF;
  IF v_customer_suspended THEN
    RAISE EXCEPTION 'Your account has been suspended. Please contact customer support.';
  END IF;

  v_idempotency_key := NULLIF(p_order_data->>'idempotency_key', '');
  IF v_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_order_row
    FROM public.orders
    WHERE customer_id = v_customer_id
      AND idempotency_key = v_idempotency_key;

    IF FOUND THEN
      RETURN jsonb_build_object(
        'id', v_order_row.id,
        'subtotal', v_order_row.subtotal,
        'delivery_fee', v_order_row.delivery_fee,
        'platform_fee', v_order_row.platform_fee,
        'total_amount', v_order_row.total_amount,
        'status', v_order_row.status
      );
    END IF;
  END IF;

  v_owner_id := NULLIF(p_order_data->>'owner_id', '')::uuid;
  v_payment_method := lower(trim(coalesce(p_order_data->>'payment_method', 'cod')));
  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'Station owner ID is required.';
  END IF;

  SELECT coalesce(is_suspended, false) INTO v_owner_suspended
  FROM public.profiles
  WHERE id = v_owner_id AND role = 'owner';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Water refill station not found.';
  END IF;
  IF v_owner_suspended THEN
    RAISE EXCEPTION 'This water station is currently suspended by administration.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = v_owner_id
      AND role = 'owner'
      AND coalesce(station_availability, 'open') = 'open'
  ) THEN
    RAISE EXCEPTION 'This water station is currently closed or unavailable.';
  END IF;
  IF NOT public.is_station_payment_method_available(v_owner_id, v_payment_method) THEN
    RAISE EXCEPTION 'This payment method is not available for this station.';
  END IF;

  FOR v_item IN
    SELECT * FROM jsonb_to_recordset(p_items_data) AS x(
      product_id uuid,
      quantity integer,
      product_name text
    )
  LOOP
    IF v_item.quantity <= 0 THEN
      RAISE EXCEPTION 'Invalid quantity for item %', v_item.product_name;
    END IF;

    SELECT * INTO v_product
    FROM public.products
    WHERE id = v_item.product_id
      AND owner_id = v_owner_id
      AND is_available = true;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Product % is unavailable at this station.', v_item.product_name;
    END IF;

    v_computed_subtotal :=
      v_computed_subtotal + (v_product.price * v_item.quantity);
    -- Only water counts toward the free-delivery gallon threshold.
    IF v_product.kind = 'water' THEN
      v_gallons := v_gallons + v_item.quantity;
    END IF;
  END LOOP;

  IF v_computed_subtotal <= 0 THEN
    RAISE EXCEPTION 'Cart cannot be empty.';
  END IF;

  v_lat := NULLIF(p_order_data->>'customer_latitude', '')::double precision;
  v_lng := NULLIF(p_order_data->>'customer_longitude', '')::double precision;

  -- Delivery fee: server-side quote (free zone or per-km). Client fee ignored.
  v_quote := public.compute_delivery_quote(
    v_owner_id, v_lat, v_lng,
    NULLIF(p_order_data->>'customer_barangay', ''),
    v_gallons
  );
  v_delivery_fee := coalesce((v_quote->>'fee')::numeric, 0);

  v_config := public.get_platform_fee_config();
  IF coalesce((v_config->>'enabled')::boolean, false) THEN
    v_platform_fee := round(
      ((v_computed_subtotal + v_delivery_fee)
        * coalesce((v_config->>'percent')::numeric, 0) / 100)
        + coalesce((v_config->>'fixed')::numeric, 0),
      2
    );
    v_platform_fee := greatest(v_platform_fee, 0);
  END IF;

  v_voucher_id := NULLIF(p_order_data->>'voucher_id', '')::uuid;
  IF v_voucher_id IS NOT NULL THEN
    SELECT * INTO v_voucher
    FROM public.customer_reward_vouchers
    WHERE id = v_voucher_id
      AND user_id = v_customer_id
      AND is_used = false
      AND expires_at > now()
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'This reward voucher is no longer available. Refresh your vouchers and try again.';
    END IF;

    IF v_voucher.is_delivery_discount THEN
      v_discount := least(
        greatest(v_voucher.discount_amount, 0),
        v_delivery_fee
      );
    ELSE
      v_discount := least(
        greatest(v_voucher.discount_amount, 0),
        v_computed_subtotal + v_delivery_fee + v_platform_fee
      );
    END IF;
  END IF;

  -- Optional rider tip: whole pesos, ₱0–₱500, paid on top (no fees, no voucher).
  v_tip := round(coalesce(NULLIF(p_order_data->>'tip_amount', '')::numeric, 0));
  IF v_tip < 0 OR v_tip > 500 THEN
    RAISE EXCEPTION 'Tip must be between PHP 0 and PHP 500.';
  END IF;

  v_total_amount := greatest(
    v_computed_subtotal + v_delivery_fee + v_platform_fee - v_discount,
    0
  ) + v_tip;

  -- ID verification gates (identity_verification.sql).
  PERFORM public.assert_order_allowed_by_verification(
    v_customer_id, v_owner_id, v_payment_method, v_total_amount
  );

  INSERT INTO public.orders (
    id,
    customer_id,
    owner_id,
    station_name,
    customer_name,
    customer_phone,
    customer_address,
    customer_barangay,
    customer_municipality,
    customer_landmark,
    idempotency_key,
    subtotal,
    delivery_fee,
    platform_fee,
    total_amount,
    payment_method,
    payment_status,
    notes,
    region_id,
    customer_latitude,
    customer_longitude,
    delivery_lat,
    delivery_lng,
    delivery_latitude,
    delivery_longitude,
    delivery_distance_km,
    delivery_rate_per_km,
    delivery_free_reason,
    tip_amount,
    items,
    status
  ) VALUES (
    coalesce(
      NULLIF(p_order_data->>'id', '')::uuid,
      gen_random_uuid()
    ),
    v_customer_id,
    v_owner_id,
    coalesce(p_order_data->>'station_name', 'Water Station'),
    p_order_data->>'customer_name',
    p_order_data->>'customer_phone',
    p_order_data->>'customer_address',
    p_order_data->>'customer_barangay',
    p_order_data->>'customer_municipality',
    p_order_data->>'customer_landmark',
    v_idempotency_key,
    v_computed_subtotal,
    v_delivery_fee,
    v_platform_fee,
    v_total_amount,
    v_payment_method,
    'pending',
    p_order_data->>'notes',
    NULLIF(p_order_data->>'region_id', '')::uuid,
    v_lat,
    v_lng,
    v_lat,
    v_lng,
    v_lat,
    v_lng,
    (v_quote->>'distance_km')::numeric,
    (v_quote->>'rate_per_km')::numeric,
    v_quote->>'free_reason',
    v_tip,
    coalesce(p_items_data, '[]'::jsonb),
    'pending'
  )
  ON CONFLICT DO NOTHING
  RETURNING * INTO v_order_row;

  IF NOT FOUND THEN
    IF v_idempotency_key IS NOT NULL THEN
      SELECT * INTO v_order_row
      FROM public.orders
      WHERE customer_id = v_customer_id
        AND idempotency_key = v_idempotency_key;

      IF FOUND THEN
        RETURN jsonb_build_object(
          'id', v_order_row.id,
          'subtotal', v_order_row.subtotal,
          'delivery_fee', v_order_row.delivery_fee,
          'platform_fee', v_order_row.platform_fee,
          'total_amount', v_order_row.total_amount,
          'status', v_order_row.status
        );
      END IF;
    END IF;
    RAISE EXCEPTION 'Order could not be created because of a conflicting order record.';
  END IF;

  v_order_id := v_order_row.id;

  FOR v_item IN
    SELECT * FROM jsonb_to_recordset(p_items_data) AS x(
      product_id uuid,
      quantity integer,
      product_name text
    )
  LOOP
    SELECT * INTO v_product FROM public.products WHERE id = v_item.product_id;
    INSERT INTO public.order_items (
      order_id,
      product_id,
      product_name,
      quantity,
      price_at_purchase,
      subtotal
    ) VALUES (
      v_order_id,
      v_item.product_id,
      v_product.name,
      v_item.quantity,
      v_product.price,
      (v_product.price * v_item.quantity)
    );
  END LOOP;

  IF v_voucher_id IS NOT NULL THEN
    UPDATE public.customer_reward_vouchers
    SET is_used = true
    WHERE id = v_voucher_id
      AND user_id = v_customer_id
      AND is_used = false;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'This reward voucher was already used by another order.';
    END IF;
  END IF;

  INSERT INTO public.system_notifications (
    user_id,
    type,
    priority,
    title,
    content,
    metadata
  ) VALUES (
    v_owner_id,
    'system_alert',
    'high',
    'New Refill Order',
    coalesce(p_order_data->>'customer_name', 'A customer')
      || ' placed a new refill order of PHP '
      || trim(to_char(v_total_amount, '999999990.00'))
      || ' (' || upper(coalesce(p_order_data->>'payment_method', 'cod')) || ').',
    jsonb_build_object(
      'order_id', v_order_id,
      'status', 'pending',
      'total_amount', v_total_amount
    )
  );

  RETURN jsonb_build_object(
    'id', v_order_id,
    'subtotal', v_computed_subtotal,
    'delivery_fee', v_delivery_fee,
    'delivery_distance_km', (v_quote->>'distance_km')::numeric,
    'delivery_free_reason', v_quote->>'free_reason',
    'platform_fee', v_platform_fee,
    'discount_amount', v_discount,
    'tip_amount', v_tip,
    'total_amount', v_total_amount,
    'status', 'pending'
  );
END;
$function$;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Rider live location privacy (2026-11-05)
-- ==============================================================================
-- rider_locations was readable by everyone ("Public can view rider
-- locations"). Now only these can read a rider's points:
--   * the rider, admins
--   * the customer or station of an order that rider is delivering right now
--     (assigned_to_rider / out_for_delivery)
-- After delivery the customer loses access. Points older than 24 h are purged
-- hourly (pg_cron, when the extension is available).
-- Test: supabase/tests/rider_live_location_test.sql
-- ==============================================================================

DROP POLICY IF EXISTS "Public can view rider locations" ON public.rider_locations;
DROP POLICY IF EXISTS "Rider location visible to active delivery parties" ON public.rider_locations;
CREATE POLICY "Rider location visible to active delivery parties" ON public.rider_locations
  FOR SELECT TO authenticated
  USING (
    rider_id = auth.uid()
    OR public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.orders o
      WHERE (o.assigned_rider_id = rider_locations.rider_id OR o.rider_id = rider_locations.rider_id)
        AND o.status IN ('assigned_to_rider', 'out_for_delivery')
        AND (o.customer_id = auth.uid() OR o.owner_id = auth.uid())
    )
  );

DROP POLICY IF EXISTS "Riders can update their own location" ON public.rider_locations;
CREATE POLICY "Riders can update their own location" ON public.rider_locations
  FOR INSERT TO authenticated
  WITH CHECK (rider_id = auth.uid());
REVOKE ALL ON public.rider_locations FROM anon;

CREATE OR REPLACE FUNCTION public.purge_old_rider_locations()
RETURNS integer
LANGUAGE sql SECURITY DEFINER SET search_path TO 'public' AS $$
  WITH d AS (
    DELETE FROM public.rider_locations WHERE "timestamp" < now() - interval '24 hours' RETURNING 1
  ) SELECT count(*)::int FROM d;
$$;
REVOKE ALL ON FUNCTION public.purge_old_rider_locations() FROM PUBLIC, anon, authenticated;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'purge_old_rider_locations';
    PERFORM cron.schedule('purge_old_rider_locations', '7 * * * *', 'SELECT public.purge_old_rider_locations()');
  END IF;
END $$;

-- ==============================================================================
-- Smart refill reminders (2026-11-05)
-- ==============================================================================
-- Learns each customer's refill rhythm (median days between their last
-- delivered orders, needs >= 3 orders) and reminds them a day before they
-- usually reorder. At most one reminder per 3 days, never while an order is
-- active, and only when profiles.refill_reminders_enabled.
--   * customer_refill_rhythm()  -> for the app's home banner (current user)
--   * send_refill_reminders()   -> daily 9:00 PH pg_cron job, inserts notifications
-- Test: supabase/tests/refill_reminders_test.sql
-- ==============================================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS refill_reminders_enabled boolean NOT NULL DEFAULT true;

CREATE OR REPLACE FUNCTION public.refill_rhythm_for(p_customer_id uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  WITH recent AS (
    SELECT created_at, owner_id, station_name
    FROM public.orders
    WHERE customer_id = p_customer_id AND status = 'delivered'
    ORDER BY created_at DESC
    LIMIT 6
  ), gaps AS (
    SELECT extract(epoch FROM (created_at - lead(created_at) OVER (ORDER BY created_at DESC))) / 86400.0 AS days
    FROM recent
  ), stats AS (
    SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY days) AS median_days,
           count(*) AS gap_count
    FROM gaps WHERE days IS NOT NULL AND days > 0.5
  ), last AS (
    SELECT * FROM recent ORDER BY created_at DESC LIMIT 1
  )
  SELECT CASE
    WHEN (SELECT gap_count FROM stats) < 2 THEN jsonb_build_object('has_rhythm', false)
    ELSE jsonb_build_object(
      'has_rhythm', true,
      'median_days', round((SELECT median_days FROM stats)::numeric, 1),
      'last_order_at', (SELECT created_at FROM last),
      'station_id', (SELECT owner_id FROM last),
      'station_name', (SELECT station_name FROM last),
      'due_at', (SELECT created_at FROM last)
                + make_interval(secs => greatest((SELECT median_days FROM stats) - 1, 1) * 86400),
      'is_due', now() >= (SELECT created_at FROM last)
                + make_interval(secs => greatest((SELECT median_days FROM stats) - 1, 1) * 86400),
      'has_active_order', EXISTS (
        SELECT 1 FROM public.orders
        WHERE customer_id = p_customer_id
          AND status NOT IN ('delivered', 'cancelled', 'failed'))
    )
  END;
$$;
REVOKE ALL ON FUNCTION public.refill_rhythm_for(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.customer_refill_rhythm()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT CASE WHEN auth.uid() IS NULL THEN '{"has_rhythm": false}'::jsonb
              ELSE public.refill_rhythm_for(auth.uid()) END;
$$;
REVOKE ALL ON FUNCTION public.customer_refill_rhythm() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.customer_refill_rhythm() TO authenticated;

CREATE OR REPLACE FUNCTION public.send_refill_reminders()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_row record;
  v_r jsonb;
  v_sent integer := 0;
BEGIN
  FOR v_row IN
    SELECT p.id FROM public.profiles p
    WHERE p.role = 'customer' AND p.refill_reminders_enabled AND NOT coalesce(p.is_suspended, false)
  LOOP
    v_r := public.refill_rhythm_for(v_row.id);
    CONTINUE WHEN NOT coalesce((v_r->>'has_rhythm')::boolean, false)
               OR NOT (v_r->>'is_due')::boolean
               OR (v_r->>'has_active_order')::boolean;
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM public.system_notifications n
      WHERE n.user_id = v_row.id
        AND n.metadata->>'kind' = 'refill_reminder'
        AND n.created_at > now() - interval '3 days');

    INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
    VALUES (
      v_row.id, 'system_alert', 'normal', 'Time for a refill?',
      'You usually reorder every ' || round((v_r->>'median_days')::numeric) || ' days. '
        || 'Tap to reorder from ' || coalesce(v_r->>'station_name', 'your station') || '.',
      jsonb_build_object('kind', 'refill_reminder', 'station_id', v_r->>'station_id')
    );
    v_sent := v_sent + 1;
  END LOOP;
  RETURN v_sent;
END; $$;
REVOKE ALL ON FUNCTION public.send_refill_reminders() FROM PUBLIC, anon, authenticated;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'send_refill_reminders';
    -- 9:00 Asia/Manila = 01:00 UTC, so reminders arrive in the morning.
    PERFORM cron.schedule('send_refill_reminders', '0 1 * * *', 'SELECT public.send_refill_reminders()');
  END IF;
END $$;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Water quality transparency (2026-11-05)
-- ==============================================================================
-- Stations upload lab test results and permits (bacteriological /
-- physical-chemical water analysis, sanitary permit, business permit) with
-- issue and expiry dates. Admins approve them; approved, unexpired lab tests
-- give the station a "Water tested" badge and a small ranking boost.
-- Files live in the private verification_docs bucket under <uid>/certs/.
-- Approved certificate files are viewable by any signed-in user.
-- Daily job: marks expired certificates and warns owners 14 days ahead.
--
-- Run after: identity_verification.sql (bucket). Test: supabase/tests/water_quality_certs_test.sql
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.station_certifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  cert_type text NOT NULL CHECK (cert_type IN (
    'bacteriological', 'physical_chemical', 'sanitary_permit', 'business_permit')),
  issued_on date NOT NULL,
  expires_on date NOT NULL,
  file_path text NOT NULL,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected', 'expired')),
  reviewer_id uuid REFERENCES public.profiles(id),
  reviewed_at timestamptz,
  rejection_reason text,
  expiry_warned_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (expires_on > issued_on)
);
CREATE INDEX IF NOT EXISTS idx_station_certs_owner ON public.station_certifications (owner_id, status);

ALTER TABLE public.station_certifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Approved certs are public, owners see their own" ON public.station_certifications;
CREATE POLICY "Approved certs are public, owners see their own" ON public.station_certifications
  FOR SELECT TO authenticated
  USING (status = 'approved' OR owner_id = auth.uid() OR public.is_admin());
REVOKE INSERT, UPDATE, DELETE ON public.station_certifications FROM anon, authenticated;
GRANT SELECT ON public.station_certifications TO authenticated;

-- Approved certificate files are readable by signed-in users.
DROP POLICY IF EXISTS "Verification docs: approved certs readable" ON storage.objects;
CREATE POLICY "Verification docs: approved certs readable" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'verification_docs' AND EXISTS (
    SELECT 1 FROM public.station_certifications c
    WHERE c.file_path = storage.objects.name AND c.status = 'approved'));

CREATE OR REPLACE FUNCTION public.submit_station_certification(
  p_cert_type text, p_issued_on date, p_expires_on date, p_file_path text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_uid AND role = 'owner') THEN
    RAISE EXCEPTION 'Only station owners upload certificates.';
  END IF;
  IF p_file_path IS NULL OR left(p_file_path, length(v_uid::text) + 7) <> v_uid::text || '/certs/' THEN
    RAISE EXCEPTION 'Upload the certificate file first.';
  END IF;
  IF p_expires_on <= current_date THEN
    RAISE EXCEPTION 'This certificate has already expired.';
  END IF;
  IF p_issued_on > current_date THEN
    RAISE EXCEPTION 'The issue date cannot be in the future.';
  END IF;
  INSERT INTO public.station_certifications (owner_id, cert_type, issued_on, expires_on, file_path)
  VALUES (v_uid, p_cert_type, p_issued_on, p_expires_on, p_file_path)
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('id', v_id, 'status', 'pending');
END; $$;

CREATE OR REPLACE FUNCTION public.admin_review_station_certification(
  p_cert_id uuid, p_approve boolean, p_reason text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_row public.station_certifications%ROWTYPE;
  v_status text := CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  IF NOT p_approve AND coalesce(trim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'Give the station a reason for the rejection.';
  END IF;
  UPDATE public.station_certifications
  SET status = v_status, reviewer_id = auth.uid(), reviewed_at = now(),
      rejection_reason = CASE WHEN p_approve THEN NULL ELSE trim(p_reason) END
  WHERE id = p_cert_id AND status = 'pending'
  RETURNING * INTO v_row;
  IF NOT FOUND THEN RAISE EXCEPTION 'This certificate was already reviewed.'; END IF;

  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (v_row.owner_id, 'system_alert', 'normal',
    CASE WHEN p_approve THEN 'Certificate approved' ELSE 'Certificate rejected' END,
    CASE WHEN p_approve THEN 'Customers can now see your certificate.'
         ELSE 'Reason: ' || trim(p_reason) END,
    jsonb_build_object('certificate_id', v_row.id, 'status', v_status));
  RETURN jsonb_build_object('id', v_row.id, 'status', v_status);
END; $$;

REVOKE ALL ON FUNCTION public.submit_station_certification(text, date, date, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_station_certification(text, date, date, text) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_review_station_certification(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_review_station_certification(uuid, boolean, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.expire_station_certifications()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_n integer;
BEGIN
  UPDATE public.station_certifications SET status = 'expired'
  WHERE status = 'approved' AND expires_on <= current_date;
  GET DIAGNOSTICS v_n = ROW_COUNT;

  WITH soon AS (
    UPDATE public.station_certifications SET expiry_warned_at = now()
    WHERE status = 'approved' AND expiry_warned_at IS NULL
      AND expires_on <= current_date + 14
    RETURNING owner_id, id, cert_type, expires_on
  )
  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  SELECT owner_id, 'system_alert', 'high', 'Certificate expiring soon',
         'Your ' || replace(cert_type, '_', ' ') || ' certificate expires on '
           || to_char(expires_on, 'Mon DD, YYYY') || '. Upload a new one to keep your badge.',
         jsonb_build_object('certificate_id', id)
  FROM soon;
  RETURN v_n;
END; $$;
REVOKE ALL ON FUNCTION public.expire_station_certifications() FROM PUBLIC, anon, authenticated;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'expire_station_certifications';
    PERFORM cron.schedule('expire_station_certifications', '15 16 * * *', 'SELECT public.expire_station_certifications()');
  END IF;
END $$;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Order disputes and refunds (2026-11-05)
-- ==============================================================================
-- Extends the existing public.disputes table (status enum: open,
-- investigating, resolved, dismissed) with the customer -> station -> admin
-- flow:
--   1. Customer opens a dispute within 48 h of delivery, one per order,
--      with optional photo evidence (private bucket dispute_evidence).
--   2. Station accepts (refund amount) -> resolved, or explains -> the
--      dispute is escalated ('investigating') for an admin.
--   3. Customer may escalate if the station has not answered in 24 h.
--   4. Admin resolves with an optional refund, or dismisses.
-- A granted refund books a REFUND ledger entry against the station, notifies
-- the customer, and refunds against the station increase flagged_count.
-- Money movement: COD refunds are returned by the station in cash; online
-- payments are refunded by the admin in PayMongo (orders.payment_status is
-- set to 'refunded' when the full total is refunded).
--
-- Test: supabase/tests/order_disputes_test.sql
-- ==============================================================================

ALTER TABLE public.disputes
  ADD COLUMN IF NOT EXISTS evidence_paths text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS owner_response text,
  ADD COLUMN IF NOT EXISTS owner_responded_at timestamptz,
  ADD COLUMN IF NOT EXISTS refund_amount numeric(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS escalated_at timestamptz;
ALTER TABLE public.disputes DROP CONSTRAINT IF EXISTS disputes_reason_check;
ALTER TABLE public.disputes ADD CONSTRAINT disputes_reason_check CHECK (reason IN (
  'missing_items', 'wrong_item', 'quality', 'damaged', 'not_delivered', 'overcharged', 'other'));
ALTER TABLE public.disputes DROP CONSTRAINT IF EXISTS disputes_refund_check;
ALTER TABLE public.disputes ADD CONSTRAINT disputes_refund_check CHECK (refund_amount >= 0);
CREATE UNIQUE INDEX IF NOT EXISTS disputes_one_per_order ON public.disputes (order_id);

-- Owners no longer update disputes directly; they use owner_respond_dispute.
DROP POLICY IF EXISTS "Owners can update disputes for their station" ON public.disputes;
REVOKE INSERT, DELETE ON public.disputes FROM anon, authenticated;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('dispute_evidence', 'dispute_evidence', false, 8388608,
        ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO UPDATE SET public = false;
DROP POLICY IF EXISTS "Dispute evidence: reporter upload" ON storage.objects;
CREATE POLICY "Dispute evidence: reporter upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'dispute_evidence' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "Dispute evidence: parties read" ON storage.objects;
CREATE POLICY "Dispute evidence: parties read" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'dispute_evidence' AND (
    (storage.foldername(name))[1] = auth.uid()::text
    OR public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.disputes d JOIN public.orders o ON o.id = d.order_id
      WHERE storage.objects.name = ANY (d.evidence_paths) AND o.owner_id = auth.uid())));

CREATE OR REPLACE FUNCTION public.open_dispute(
  p_order_id uuid, p_reason text, p_description text, p_evidence_paths text[] DEFAULT '{}'
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_order public.orders%ROWTYPE;
  v_done_at timestamptz;
  v_id uuid;
  v_path text;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id AND customer_id = v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order not found.'; END IF;
  IF v_order.status::text <> 'delivered' THEN
    RAISE EXCEPTION 'You can report a problem once the order is delivered.';
  END IF;
  v_done_at := coalesce(v_order.actual_completion_at, v_order.updated_at, v_order.created_at);
  IF v_done_at < now() - interval '48 hours' THEN
    RAISE EXCEPTION 'Problems must be reported within 48 hours of delivery.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.disputes WHERE order_id = p_order_id) THEN
    RAISE EXCEPTION 'A problem was already reported for this order.';
  END IF;
  IF coalesce(trim(p_description), '') = '' THEN
    RAISE EXCEPTION 'Tell the station what went wrong.';
  END IF;
  FOREACH v_path IN ARRAY coalesce(p_evidence_paths, '{}') LOOP
    IF left(v_path, length(v_uid::text) + 1) <> v_uid::text || '/' THEN
      RAISE EXCEPTION 'Invalid evidence photo.';
    END IF;
  END LOOP;

  INSERT INTO public.disputes (order_id, reporter_id, reason, description, status, evidence_paths)
  VALUES (p_order_id, v_uid, p_reason, trim(p_description), 'open', coalesce(p_evidence_paths, '{}'))
  RETURNING id INTO v_id;

  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (v_order.owner_id, 'system_alert', 'high', 'A customer reported a problem',
    'Order #' || upper(substr(p_order_id::text, 1, 8)) || ': ' || replace(p_reason, '_', ' ')
      || '. Please respond within 24 hours.',
    jsonb_build_object('dispute_id', v_id, 'order_id', p_order_id));
  RETURN jsonb_build_object('id', v_id, 'status', 'open');
END; $$;

-- Shared by station and admin resolutions.
CREATE OR REPLACE FUNCTION public.apply_dispute_refund(p_dispute_id uuid, p_amount numeric, p_note text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_d public.disputes%ROWTYPE;
  v_o public.orders%ROWTYPE;
BEGIN
  SELECT * INTO v_d FROM public.disputes WHERE id = p_dispute_id;
  SELECT * INTO v_o FROM public.orders WHERE id = v_d.order_id;
  IF p_amount < 0 OR p_amount > v_o.total_amount THEN
    RAISE EXCEPTION 'Refund must be between PHP 0 and the order total.';
  END IF;
  UPDATE public.disputes SET refund_amount = p_amount, status = 'resolved',
         resolution_notes = p_note, updated_at = now()
  WHERE id = p_dispute_id;
  IF p_amount > 0 THEN
    INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
    VALUES (v_o.owner_id, v_o.id, -p_amount, 'REFUND', 'Refund for reported problem');
    UPDATE public.profiles SET flagged_count = coalesce(flagged_count, 0) + 1 WHERE id = v_o.owner_id;
    IF p_amount >= v_o.total_amount THEN
      UPDATE public.orders SET payment_status = 'refunded' WHERE id = v_o.id;
    END IF;
  END IF;
  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (v_d.reporter_id, 'system_alert', 'high',
    CASE WHEN p_amount > 0 THEN 'Refund approved' ELSE 'Your report was reviewed' END,
    CASE WHEN p_amount > 0
      THEN 'PHP ' || trim(to_char(p_amount, '999990.00')) || ' will be returned '
        || CASE WHEN lower(coalesce(v_o.payment_method, 'cod')) IN ('cod', 'cash')
                THEN 'by the station in cash.' ELSE 'to your original payment method.' END
      ELSE coalesce(p_note, 'No refund was given.') END,
    jsonb_build_object('dispute_id', p_dispute_id, 'order_id', v_o.id, 'refund_amount', p_amount));
END; $$;
REVOKE ALL ON FUNCTION public.apply_dispute_refund(uuid, numeric, text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.owner_respond_dispute(
  p_dispute_id uuid, p_accept boolean, p_response text, p_refund_amount numeric DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_d public.disputes%ROWTYPE;
BEGIN
  SELECT d.* INTO v_d FROM public.disputes d JOIN public.orders o ON o.id = d.order_id
  WHERE d.id = p_dispute_id AND o.owner_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Dispute not found.'; END IF;
  IF v_d.status::text <> 'open' OR v_d.owner_responded_at IS NOT NULL THEN
    RAISE EXCEPTION 'This dispute was already answered.';
  END IF;
  IF coalesce(trim(p_response), '') = '' THEN RAISE EXCEPTION 'Write a reply to the customer.'; END IF;

  UPDATE public.disputes SET owner_response = trim(p_response), owner_responded_at = now(), updated_at = now()
  WHERE id = p_dispute_id;

  IF p_accept THEN
    PERFORM public.apply_dispute_refund(p_dispute_id, coalesce(p_refund_amount, 0), 'Station: ' || trim(p_response));
    RETURN jsonb_build_object('status', 'resolved');
  END IF;

  UPDATE public.disputes SET status = 'investigating', escalated_at = now() WHERE id = p_dispute_id;
  RETURN jsonb_build_object('status', 'investigating');
END; $$;

CREATE OR REPLACE FUNCTION public.escalate_dispute(p_dispute_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  UPDATE public.disputes SET status = 'investigating', escalated_at = now(), updated_at = now()
  WHERE id = p_dispute_id AND reporter_id = auth.uid() AND status = 'open'
    AND owner_responded_at IS NULL AND created_at < now() - interval '24 hours';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'You can ask eRefill to step in 24 hours after reporting if the station has not replied.';
  END IF;
  RETURN jsonb_build_object('status', 'investigating');
END; $$;

CREATE OR REPLACE FUNCTION public.admin_resolve_dispute(
  p_dispute_id uuid, p_refund_amount numeric, p_notes text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.disputes WHERE id = p_dispute_id AND status IN ('open', 'investigating')) THEN
    RAISE EXCEPTION 'This dispute is already closed.';
  END IF;
  UPDATE public.disputes SET resolved_by = auth.uid() WHERE id = p_dispute_id;
  PERFORM public.apply_dispute_refund(p_dispute_id, coalesce(p_refund_amount, 0), p_notes);
  IF coalesce(p_refund_amount, 0) = 0 THEN
    UPDATE public.disputes SET status = 'dismissed' WHERE id = p_dispute_id;
  END IF;
  RETURN jsonb_build_object('status', CASE WHEN coalesce(p_refund_amount, 0) > 0 THEN 'resolved' ELSE 'dismissed' END);
END; $$;

REVOKE ALL ON FUNCTION public.open_dispute(uuid, text, text, text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.open_dispute(uuid, text, text, text[]) TO authenticated;
REVOKE ALL ON FUNCTION public.owner_respond_dispute(uuid, boolean, text, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.owner_respond_dispute(uuid, boolean, text, numeric) TO authenticated;
REVOKE ALL ON FUNCTION public.escalate_dispute(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.escalate_dispute(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_resolve_dispute(uuid, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_resolve_dispute(uuid, numeric, text) TO authenticated;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- AI ordering assistant: per-user daily message limit (2026-11-05)
-- ==============================================================================
-- The order-assistant Edge Function records one row per message (with the
-- service role) and refuses more than 20 per user in 24 hours.
-- Users can read their own usage; nobody writes from the app.
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.assistant_usage (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  input_tokens integer NOT NULL DEFAULT 0,
  output_tokens integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_assistant_usage_user_time ON public.assistant_usage (user_id, created_at DESC);

ALTER TABLE public.assistant_usage ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users read own assistant usage" ON public.assistant_usage;
CREATE POLICY "Users read own assistant usage" ON public.assistant_usage
  FOR SELECT TO authenticated USING (user_id = auth.uid());
REVOKE INSERT, UPDATE, DELETE ON public.assistant_usage FROM anon, authenticated;
GRANT SELECT ON public.assistant_usage TO authenticated;

-- Shared fixtures for the SQL tests in this folder. Every test runs as
--   BEGIN; <scripts under test, BEGIN/COMMIT stripped>; _fixtures.sql; <test>; ROLLBACK;
-- through the Supabase MCP execute_sql tool, so nothing persists.
--
-- Fixture rows are inserted with triggers off (replica role) to skip station
-- setup checks; triggers are back on before the test body runs.
--
-- ids: owner ...a1, second owner ...a2, customer ...c1, rider ...d1,
--      admin ...e1, product ...b1 (₱19.60, owner a1).

SET LOCAL session_replication_role = replica;

INSERT INTO auth.users (id, instance_id, aud, role, email, raw_user_meta_data, raw_app_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_owner@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000a2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_owner2@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_cust@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_rider@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_admin@example.test', '{}', '{}', now(), now());

INSERT INTO public.profiles (id, role, full_name, station_name, station_availability, latitude, longitude)
VALUES
  ('00000000-0000-4000-8000-0000000000a1', 'owner', 'T Owner', 'T Station', 'open', 14.60, 121.00),
  ('00000000-0000-4000-8000-0000000000a2', 'owner', 'T Owner 2', 'T Station 2', 'open', 14.61, 121.01),
  ('00000000-0000-4000-8000-0000000000c1', 'customer', 'T Cust', NULL, 'open', 14.62, 121.02),
  ('00000000-0000-4000-8000-0000000000d1', 'rider', 'T Rider', NULL, 'open', NULL, NULL),
  ('00000000-0000-4000-8000-0000000000e1', 'admin', 'T Admin', NULL, 'open', NULL, NULL);

INSERT INTO public.owner_settings (owner_id, base_delivery_fee)
VALUES
  ('00000000-0000-4000-8000-0000000000a1', 5.4),
  ('00000000-0000-4000-8000-0000000000a2', 0);

INSERT INTO public.products (id, owner_id, name, price, is_available)
VALUES ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000a1', 'T Water', 19.6, true);

-- Fee config used by every test unless a test overrides it.
UPDATE public.system_config SET value = '{"enabled": true, "percent": 1, "fixed": 0}'::jsonb
WHERE key = 'platform_fee';

SET LOCAL session_replication_role = origin;

-- Helpers (temporary: dropped with the transaction).
CREATE OR REPLACE FUNCTION pg_temp.act_as(p_user uuid) RETURNS void
LANGUAGE sql AS $$
  SELECT set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text,
    true
  );
$$;

CREATE OR REPLACE FUNCTION pg_temp.place_order(p_method text, p_qty integer DEFAULT 1)
RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  RETURN public.create_order_atomic(
    jsonb_build_object(
      'owner_id', '00000000-0000-4000-8000-0000000000a1',
      'payment_method', p_method,
      'customer_name', 'T Cust',
      'customer_address', 'Test address',
      'customer_latitude', '14.6',
      'customer_longitude', '121.0'
    ),
    jsonb_build_array(jsonb_build_object(
      'product_id', '00000000-0000-4000-8000-0000000000b1',
      'quantity', p_qty,
      'product_name', 'T Water'
    ))
  );
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.assert_eq(p_label text, p_actual anyelement, p_expected anyelement)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF p_actual IS DISTINCT FROM p_expected THEN
    RAISE EXCEPTION '% — expected %, got %', p_label, p_expected, p_actual;
  END IF;
END;
$$;

-- Runs p_sql and fails unless it raises an error containing p_message.
CREATE OR REPLACE FUNCTION pg_temp.expect_error(p_label text, p_sql text, p_message text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    IF position(p_message IN SQLERRM) = 0 THEN
      RAISE EXCEPTION '% — expected error "%", got "%"', p_label, p_message, SQLERRM;
    END IF;
    RETURN;
  END;
  RAISE EXCEPTION '% — expected error "%", but it succeeded', p_label, p_message;
END;
$$;
-- Run: bash build.sh ../scripts/harden_signup_and_protected_columns.sql ../scripts/delivery_coverage.sql ../scripts/station_accessories.sql ../scripts/rider_tips.sql ../scripts/identity_verification.sql ../scripts/order_pricing_v3.sql -- rider_tips_test.sql

-- Fixture station must be verified to take orders (identity_verification.sql).
UPDATE public.profiles SET verification_status = 'approved' WHERE id = '00000000-0000-4000-8000-0000000000a1';

-- tip_added_to_total
DO $$ DECLARE r jsonb; BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  r := public.create_order_atomic(
    jsonb_build_object('owner_id', '00000000-0000-4000-8000-0000000000a1', 'payment_method', 'cod',
      'customer_name', 'T Cust', 'customer_address', 'Test', 'customer_latitude', '14.6',
      'customer_longitude', '121.0', 'tip_amount', '20'),
    jsonb_build_array(jsonb_build_object('product_id', '00000000-0000-4000-8000-0000000000b1', 'quantity', 1, 'product_name', 'T Water')));
  PERFORM pg_temp.assert_eq('tip echoed', (r->>'tip_amount')::numeric, 20::numeric);
  PERFORM pg_temp.assert_eq('total includes tip',
    (r->>'total_amount')::numeric,
    (r->>'subtotal')::numeric + (r->>'delivery_fee')::numeric + (r->>'platform_fee')::numeric + 20);
END $$;

-- tip_over_500_rejected
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  PERFORM pg_temp.expect_error('tip cap',
    $q$SELECT public.create_order_atomic(
      jsonb_build_object('owner_id', '00000000-0000-4000-8000-0000000000a1', 'payment_method', 'cod',
        'customer_name', 'T', 'customer_address', 'T', 'customer_latitude', '14.6', 'customer_longitude', '121.0',
        'tip_amount', '501'),
      jsonb_build_array(jsonb_build_object('product_id', '00000000-0000-4000-8000-0000000000b1', 'quantity', 1, 'product_name', 'T Water')))$q$,
    'Tip must be between');
END $$;

-- delivered_order_pays_tip_to_rider_not_station
DO $$ DECLARE r jsonb; v_id uuid; v_total numeric; v_fee numeric; BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  r := public.create_order_atomic(
    jsonb_build_object('owner_id', '00000000-0000-4000-8000-0000000000a1', 'payment_method', 'cod',
      'customer_name', 'T Cust', 'customer_address', 'Test', 'customer_latitude', '14.6',
      'customer_longitude', '121.0', 'tip_amount', 50),
    jsonb_build_array(jsonb_build_object('product_id', '00000000-0000-4000-8000-0000000000b1', 'quantity', 2, 'product_name', 'T Water')));
  v_id := (r->>'id')::uuid;
  v_total := (r->>'total_amount')::numeric;
  v_fee := (r->>'platform_fee')::numeric;
  SET LOCAL session_replication_role = replica;
  UPDATE public.orders SET status = 'out_for_delivery', assigned_rider_id = '00000000-0000-4000-8000-0000000000d1' WHERE id = v_id;
  SET LOCAL session_replication_role = origin;
  UPDATE public.orders SET status = 'delivered' WHERE id = v_id;

  PERFORM pg_temp.assert_eq('rider tip',
    (SELECT amount FROM public.ledger_entries WHERE order_id = v_id AND entry_type = 'RIDER_TIP'), 50::numeric);
  PERFORM pg_temp.assert_eq('station sale excludes tip',
    (SELECT amount FROM public.ledger_entries WHERE order_id = v_id AND entry_type = 'SALE'), v_total - v_fee - 50);
  PERFORM pg_temp.assert_eq('commission excludes tip',
    (SELECT round(amount, 2) FROM public.ledger_entries WHERE order_id = v_id AND entry_type = 'COMMISSION'),
    round((v_total - 50) * 0.10, 2));
END $$;

SELECT 'rider_tips_test: all passed' AS result;
ROLLBACK;

-- ===== identity_verification_test =====
BEGIN;
-- ==============================================================================
-- Harden signup roles and protect trust columns on profiles (2026-11-05)
-- ==============================================================================
-- 1. Self-signup could claim role 'admin' or 'rider' through user metadata.
--    Only accounts created by a trusted server function (admin_create_user,
--    create_rider_account, admin_create_station) may get privileged roles.
--    Self-signups arrive through the Auth server, whose session user is
--    supabase_auth_admin; those are limited to customer/owner.
-- 2. Users could UPDATE their own average_rating / review_count /
--    reliability_score / flagged_count. Those are now writable only by admins
--    or by SECURITY DEFINER functions (e.g. update_station_stats()).
-- 3. Adds profiles.verification_status (used by identity verification), which is
--    protected the same way.
--
-- Run after: single_water_product_catalog.sql. Test: supabase/tests/protected_columns_test.sql
-- ==============================================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS verification_status text NOT NULL DEFAULT 'unverified';
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_verification_status_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_verification_status_check
  CHECK (verification_status IN ('unverified', 'pending', 'approved', 'rejected'));

-- 1. Role resolution -----------------------------------------------------------
CREATE OR REPLACE FUNCTION public.resolve_signup_role(p_requested text, p_trusted boolean)
RETURNS public.user_role
LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN p_requested IN ('customer', 'owner') THEN p_requested::public.user_role
    WHEN p_trusted AND p_requested IN ('rider', 'admin') THEN p_requested::public.user_role
    ELSE 'customer'::public.user_role
  END;
$$;
REVOKE ALL ON FUNCTION public.resolve_signup_role(text, boolean) FROM PUBLIC, anon, authenticated;

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
  -- 1. Role: self-signups (Auth server session) may only be customer or owner.
  v_role := public.resolve_signup_role(
    new.raw_user_meta_data->>'role',
    session_user <> 'supabase_auth_admin'
  );

  -- 2. Safe municipality enum resolution
  IF lower(trim(COALESCE(new.raw_user_meta_data->>'town', ''))) = 'cantilan' THEN
    v_town := 'Cantilan'::public.municipality;
  ELSIF lower(trim(COALESCE(new.raw_user_meta_data->>'town', ''))) = 'madrid' THEN
    v_town := 'Madrid'::public.municipality;
  ELSE
    v_town := NULL;
  END IF;

  v_complete_address := NULLIF(TRIM(COALESCE(new.raw_user_meta_data->>'complete_address', '')), '');

  -- 3. Names (Google OAuth sends 'name', 'given_name', 'family_name', 'picture')
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

  -- 5. Upsert profile
  INSERT INTO public.profiles (
    id, email, username, full_name, first_name, last_name, mi, suffix, role,
    phone, town, barangay, complete_address, landmark, station_name,
    avatar_url, latitude, longitude, primary_water_type
  )
  VALUES (
    new.id, new.email, v_username, v_full_name, v_first_name, v_last_name,
    new.raw_user_meta_data->>'mi', new.raw_user_meta_data->>'suffix', v_role,
    new.raw_user_meta_data->>'phone', v_town, new.raw_user_meta_data->>'barangay',
    v_complete_address, new.raw_user_meta_data->>'landmark',
    new.raw_user_meta_data->>'station_name', v_avatar_url,
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

-- 2. Protected trust columns -----------------------------------------------------
-- SECURITY INVOKER on purpose: current_user is 'authenticated'/'anon' for direct
-- client writes, and the function owner (postgres) inside SECURITY DEFINER
-- functions such as update_station_stats() and the admin RPCs.
CREATE OR REPLACE FUNCTION public.guard_profile_protected_columns()
RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;

  IF NEW.average_rating IS NOT DISTINCT FROM OLD.average_rating
    AND NEW.review_count IS NOT DISTINCT FROM OLD.review_count
    AND NEW.reliability_score IS NOT DISTINCT FROM OLD.reliability_score
    AND NEW.flagged_count IS NOT DISTINCT FROM OLD.flagged_count
    AND NEW.verification_status IS NOT DISTINCT FROM OLD.verification_status
  THEN
    RETURN NEW;
  END IF;

  IF public.is_admin() THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'Unauthorized: You cannot alter protected account fields.';
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_profile_protected_columns ON public.profiles;
CREATE TRIGGER trg_guard_profile_protected_columns
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.guard_profile_protected_columns();


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Delivery coverage: free-delivery zones + distance-based fees (2026-11-05)
-- ==============================================================================
-- Each station defines where delivery is free:
--   * within free_delivery_radius_km of the station (default 1 km), OR
--   * to any barangay listed in free_delivery_barangays, OR
--   * when the order has at least free_delivery_min_gallons water gallons.
-- Everywhere else pays the platform's per-km rate from
-- system_config.delivery_fee_config (rate_per_km, minimum_fee,
-- min_billable_distance_km, rounding_rule, enabled).
--
-- Distance = straight-line (haversine) x 1.3 road factor, so it approximates
-- real road distance without calling a routing service from the database.
--
-- Self-contained: does not depend on delivery_fee_config_rpcs.sql.
-- Run before: order_pricing_v3.sql. Test: supabase/tests/delivery_quote_test.sql
-- ==============================================================================

ALTER TABLE public.owner_settings
  ADD COLUMN IF NOT EXISTS free_delivery_radius_km numeric(4,1) NOT NULL DEFAULT 1.0,
  ADD COLUMN IF NOT EXISTS free_delivery_barangays text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS free_delivery_min_gallons integer;

ALTER TABLE public.owner_settings DROP CONSTRAINT IF EXISTS owner_settings_free_radius_check;
ALTER TABLE public.owner_settings ADD CONSTRAINT owner_settings_free_radius_check
  CHECK (free_delivery_radius_km >= 0 AND free_delivery_radius_km <= 10);
ALTER TABLE public.owner_settings DROP CONSTRAINT IF EXISTS owner_settings_free_min_gallons_check;
ALTER TABLE public.owner_settings ADD CONSTRAINT owner_settings_free_min_gallons_check
  CHECK (free_delivery_min_gallons IS NULL OR free_delivery_min_gallons BETWEEN 1 AND 100);

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS delivery_distance_km numeric(6,2),
  ADD COLUMN IF NOT EXISTS delivery_rate_per_km numeric(8,2),
  ADD COLUMN IF NOT EXISTS delivery_free_reason text;

-- Road factor applied to straight-line distance.
CREATE OR REPLACE FUNCTION public.delivery_road_distance_km(
  p_lat1 double precision, p_lng1 double precision,
  p_lat2 double precision, p_lng2 double precision
) RETURNS numeric
LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN p_lat1 IS NULL OR p_lng1 IS NULL OR p_lat2 IS NULL OR p_lng2 IS NULL THEN NULL
    ELSE round((
      2 * 6371 * asin(sqrt(
        power(sin(radians(p_lat2 - p_lat1) / 2), 2)
        + cos(radians(p_lat1)) * cos(radians(p_lat2))
          * power(sin(radians(p_lng2 - p_lng1) / 2), 2)
      )) * 1.3
    )::numeric, 2)
  END;
$$;

-- Fee for a distance outside the free zone, from the admin's config.
CREATE OR REPLACE FUNCTION public.delivery_fee_for_distance(p_km numeric)
RETURNS numeric
LANGUAGE plpgsql STABLE SET search_path TO 'public' AS $$
DECLARE
  v_cfg jsonb;
  v_rate numeric;
  v_min numeric;
  v_min_km numeric;
  v_rule text;
  v_fee numeric;
BEGIN
  SELECT value INTO v_cfg FROM public.system_config WHERE key = 'delivery_fee_config';
  v_cfg := coalesce(v_cfg, '{}'::jsonb);
  IF NOT coalesce((v_cfg->>'enabled')::boolean, true) THEN
    RETURN 0;
  END IF;
  v_rate := greatest(coalesce((v_cfg->>'rate_per_km')::numeric, 10), 0);
  v_min := greatest(coalesce((v_cfg->>'minimum_fee')::numeric, 20), 0);
  v_min_km := greatest(coalesce((v_cfg->>'min_billable_distance_km')::numeric, 1), 0);
  v_rule := lower(trim(coalesce(v_cfg->>'rounding_rule', 'exact')));

  IF p_km IS NULL THEN
    RETURN v_min;
  END IF;

  -- Same rule as CheckoutRules.calculateDeliveryFee in the app: the rounding
  -- rule applies to the billable distance; the fee is whole pesos.
  v_fee := greatest(p_km, v_min_km);
  v_fee := CASE
    WHEN v_rule IN ('ceil', 'round_up') THEN ceil(v_fee)
    WHEN v_rule IN ('round', 'round_nearest') THEN round(v_fee)
    ELSE v_fee
  END;
  IF v_rate <= 0 THEN
    RETURN 0;
  END IF;
  RETURN round(greatest(v_rate * v_fee, v_min));
END;
$$;

-- Quote shown at checkout and charged by create_order_atomic.
CREATE OR REPLACE FUNCTION public.compute_delivery_quote(
  p_station_id uuid,
  p_lat double precision,
  p_lng double precision,
  p_barangay text DEFAULT NULL,
  p_gallons integer DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_slat double precision;
  v_slng double precision;
  v_radius numeric;
  v_barangays text[];
  v_min_gallons integer;
  v_km numeric;
  v_reason text;
  v_cfg jsonb;
BEGIN
  SELECT coalesce(p.latitude, p.lat), coalesce(p.longitude, p.lng)
  INTO v_slat, v_slng
  FROM public.profiles p
  WHERE p.id = p_station_id AND p.role = 'owner';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Water refill station not found.';
  END IF;

  SELECT coalesce(os.free_delivery_radius_km, 1.0),
         coalesce(os.free_delivery_barangays, '{}'),
         os.free_delivery_min_gallons
  INTO v_radius, v_barangays, v_min_gallons
  FROM public.owner_settings os WHERE os.owner_id = p_station_id;
  v_radius := coalesce(v_radius, 1.0);
  v_barangays := coalesce(v_barangays, '{}');

  v_km := public.delivery_road_distance_km(v_slat, v_slng, p_lat, p_lng);

  IF v_km IS NOT NULL AND v_km <= v_radius THEN
    v_reason := 'radius';
  ELSIF p_barangay IS NOT NULL AND EXISTS (
    SELECT 1 FROM unnest(v_barangays) b
    WHERE lower(trim(b)) = lower(trim(p_barangay))
  ) THEN
    v_reason := 'barangay';
  ELSIF v_min_gallons IS NOT NULL AND coalesce(p_gallons, 0) >= v_min_gallons THEN
    v_reason := 'min_gallons';
  END IF;

  SELECT value INTO v_cfg FROM public.system_config WHERE key = 'delivery_fee_config';

  RETURN jsonb_build_object(
    'distance_km', v_km,
    'is_free', v_reason IS NOT NULL,
    'free_reason', v_reason,
    'fee', CASE WHEN v_reason IS NOT NULL THEN 0 ELSE public.delivery_fee_for_distance(v_km) END,
    'rate_per_km', coalesce((v_cfg->>'rate_per_km')::numeric, 10),
    'minimum_fee', coalesce((v_cfg->>'minimum_fee')::numeric, 20),
    'free_radius_km', v_radius,
    'free_barangays', to_jsonb(v_barangays),
    'free_min_gallons', v_min_gallons
  );
END;
$$;

REVOKE ALL ON FUNCTION public.compute_delivery_quote(uuid, double precision, double precision, text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.compute_delivery_quote(uuid, double precision, double precision, text, integer) TO authenticated;
REVOKE ALL ON FUNCTION public.delivery_fee_for_distance(numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delivery_fee_for_distance(numeric) TO authenticated;


NOTIFY pgrst, 'reload schema';
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


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Rider tips (2026-11-05)
-- ==============================================================================
-- Customers can add an optional tip (₱0–₱500, whole pesos) at checkout for
-- delivery orders. It is part of the single charge (COD or PayMongo), so no
-- second payment is needed, and 100% goes to the rider:
--   * excluded from the station SALE and from the 10% commission base
--   * booked as a RIDER_TIP ledger entry to the assigned rider
--   * if no rider was assigned (station delivered itself) it stays with the
--     station as part of the SALE
-- create_order_atomic reads p_order_data->>'tip_amount' (order_pricing_v3.sql).
--
-- Run before: order_pricing_v3.sql. Test: supabase/tests/rider_tips_test.sql
-- ==============================================================================

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS tip_amount numeric(10,2) NOT NULL DEFAULT 0;
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_tip_amount_check;
ALTER TABLE public.orders ADD CONSTRAINT orders_tip_amount_check
  CHECK (tip_amount >= 0 AND tip_amount <= 500);

CREATE OR REPLACE FUNCTION public.proc_finalize_order_finances()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    v_commission NUMERIC;
    v_fee NUMERIC := greatest(coalesce(NEW.platform_fee, 0), 0);
    v_tip NUMERIC := greatest(coalesce(NEW.tip_amount, 0), 0);
    v_rider_tip NUMERIC := 0;
BEGIN
    IF NEW.status = 'delivered' AND OLD.status != 'delivered' THEN
        -- The tip belongs to the rider; without a rider it stays in the sale.
        IF NEW.assigned_rider_id IS NOT NULL THEN
            v_rider_tip := v_tip;
        END IF;

        INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
        VALUES (NEW.owner_id, NEW.id, NEW.total_amount - v_fee - v_rider_tip, 'SALE', 'Order completion payment');

        IF v_fee > 0 THEN
            INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description, metadata)
            VALUES (
                NEW.owner_id, NEW.id, v_fee, 'SERVICE_FEE', 'Platform service fee',
                jsonb_build_object('payee', 'platform', 'payment_method', NEW.payment_method)
            );

            IF lower(coalesce(NEW.payment_method, 'cod')) IN ('cod', 'cash', 'credit') THEN
                PERFORM public.apply_wallet_entry(
                    NEW.owner_id, -v_fee, 'service_fee', NEW.id, NULL,
                    'Service fee for order ' || upper(substr(NEW.id::text, 1, 8))
                );
            END IF;
        END IF;

        -- Commission excludes the tip.
        v_commission := (NEW.total_amount - v_tip) * 0.10;

        IF NEW.assigned_rider_id IS NOT NULL THEN
            INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
            VALUES (NEW.assigned_rider_id, NEW.id, v_commission, 'COMMISSION', 'Delivery commission for order');

            IF v_rider_tip > 0 THEN
                INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
                VALUES (NEW.assigned_rider_id, NEW.id, v_rider_tip, 'RIDER_TIP', 'Customer tip');

                INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
                VALUES (
                    NEW.assigned_rider_id, 'system_alert', 'normal', 'You got a tip!',
                    'A customer tipped you PHP ' || trim(to_char(v_rider_tip, '999990')) || '. Thank you for the great service.',
                    jsonb_build_object('order_id', NEW.id, 'tip_amount', v_rider_tip)
                );
            END IF;
        END IF;

        INSERT INTO public.domain_events (event_type, payload, actor_id)
        VALUES ('ORDER_COMPLETED', jsonb_build_object(
            'order_id', NEW.id, 'total', NEW.total_amount,
            'rider_id', NEW.assigned_rider_id, 'tip', v_tip), auth.uid());
    END IF;
    RETURN NEW;
END;
$$;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Seller and customer ID verification (2026-11-05)
-- ==============================================================================
-- Users upload a government ID (front, back, selfie; owners also a business
-- permit) to the private bucket verification_docs under <their uid>/.
-- An admin reviews and approves or rejects. profiles.verification_status
-- (added and write-protected by harden_signup_and_protected_columns.sql) is
-- only changed by the RPCs below.
--
-- Gates (enforced in create_order_atomic, order_pricing_v3.sql):
--   * stations must be 'approved' to receive orders
--   * unverified customers: cash-on-delivery up to PHP 1,000 and at most
--     2 active COD orders; verified customers have no limit
-- Backfill: owners who already completed a delivery are approved (legacy).
--
-- Run after: harden_signup_and_protected_columns.sql
-- Run before: order_pricing_v3.sql. Test: supabase/tests/identity_verification_test.sql
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.identity_verifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role text NOT NULL,
  id_type text NOT NULL CHECK (id_type IN (
    'philsys', 'drivers_license', 'umid', 'passport', 'postal', 'voters', 'prc', 'other')),
  id_number_last4 text CHECK (id_number_last4 ~ '^[0-9A-Za-z]{4}$'),
  front_path text NOT NULL,
  back_path text,
  selfie_path text NOT NULL,
  business_permit_path text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  reviewer_id uuid REFERENCES public.profiles(id),
  reviewed_at timestamptz,
  rejection_reason text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_identity_verifications_user ON public.identity_verifications (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_identity_verifications_pending ON public.identity_verifications (created_at) WHERE status = 'pending';

ALTER TABLE public.identity_verifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users read own verifications" ON public.identity_verifications;
CREATE POLICY "Users read own verifications" ON public.identity_verifications
  FOR SELECT TO authenticated USING (auth.uid() = user_id OR public.is_admin());
-- Writes only through the RPCs below.
REVOKE INSERT, UPDATE, DELETE ON public.identity_verifications FROM anon, authenticated;
GRANT SELECT ON public.identity_verifications TO authenticated;

-- Private bucket, one folder per user.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('verification_docs', 'verification_docs', false, 8388608,
        ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
ON CONFLICT (id) DO UPDATE SET public = false;

DROP POLICY IF EXISTS "Verification docs: owner upload" ON storage.objects;
CREATE POLICY "Verification docs: owner upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'verification_docs' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "Verification docs: owner or admin read" ON storage.objects;
CREATE POLICY "Verification docs: owner or admin read" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'verification_docs'
         AND ((storage.foldername(name))[1] = auth.uid()::text OR public.is_admin()));

CREATE OR REPLACE FUNCTION public.submit_identity_verification(
  p_id_type text,
  p_id_number_last4 text,
  p_front_path text,
  p_back_path text,
  p_selfie_path text,
  p_business_permit_path text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_role text;
  v_status text;
  v_prefix text;
  v_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required.'; END IF;
  SELECT role::text, verification_status INTO v_role, v_status FROM public.profiles WHERE id = v_uid;
  IF v_role NOT IN ('customer', 'owner') THEN
    RAISE EXCEPTION 'Only customers and station owners verify their ID here.';
  END IF;
  IF v_status = 'approved' THEN RAISE EXCEPTION 'Your ID is already verified.'; END IF;
  IF v_status = 'pending' THEN RAISE EXCEPTION 'Your ID is already being reviewed.'; END IF;

  v_prefix := v_uid::text || '/';
  IF p_front_path IS NULL OR p_selfie_path IS NULL
     OR left(p_front_path, length(v_prefix)) <> v_prefix
     OR left(p_selfie_path, length(v_prefix)) <> v_prefix
     OR (p_back_path IS NOT NULL AND left(p_back_path, length(v_prefix)) <> v_prefix)
     OR (p_business_permit_path IS NOT NULL AND left(p_business_permit_path, length(v_prefix)) <> v_prefix) THEN
    RAISE EXCEPTION 'Upload your ID photos before submitting.';
  END IF;
  IF v_role = 'owner' AND p_business_permit_path IS NULL THEN
    RAISE EXCEPTION 'Stations must also upload a business or sanitary permit.';
  END IF;

  INSERT INTO public.identity_verifications (
    user_id, role, id_type, id_number_last4, front_path, back_path, selfie_path, business_permit_path)
  VALUES (v_uid, v_role, p_id_type, NULLIF(p_id_number_last4, ''), p_front_path, p_back_path,
          p_selfie_path, p_business_permit_path)
  RETURNING id INTO v_id;

  UPDATE public.profiles SET verification_status = 'pending' WHERE id = v_uid;
  RETURN jsonb_build_object('id', v_id, 'status', 'pending');
END; $$;

CREATE OR REPLACE FUNCTION public.admin_review_identity_verification(
  p_verification_id uuid,
  p_approve boolean,
  p_reason text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_row public.identity_verifications%ROWTYPE;
  v_status text := CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  IF NOT p_approve AND coalesce(trim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'Give the user a reason for the rejection.';
  END IF;

  UPDATE public.identity_verifications
  SET status = v_status, reviewer_id = auth.uid(), reviewed_at = now(),
      rejection_reason = CASE WHEN p_approve THEN NULL ELSE trim(p_reason) END
  WHERE id = p_verification_id AND status = 'pending'
  RETURNING * INTO v_row;
  IF NOT FOUND THEN RAISE EXCEPTION 'This verification was already reviewed.'; END IF;

  UPDATE public.profiles SET verification_status = v_status WHERE id = v_row.user_id;

  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (
    v_row.user_id, 'system_alert', 'high',
    CASE WHEN p_approve THEN 'Your ID is verified' ELSE 'ID verification needs another try' END,
    CASE WHEN p_approve
      THEN CASE WHEN v_row.role = 'owner'
        THEN 'Your station is verified and can now receive orders.'
        ELSE 'Your account is verified. Order limits are lifted.' END
      ELSE 'Reason: ' || trim(p_reason) || '. You can submit new photos.' END,
    jsonb_build_object('verification_id', v_row.id, 'status', v_status)
  );

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, new_value, metadata)
  VALUES (auth.uid(), 'identity_verification_' || v_status, 'identity_verifications', v_row.id::text,
          jsonb_build_object('status', v_status),
          jsonb_build_object('user_id', v_row.user_id, 'reason', p_reason));

  RETURN jsonb_build_object('id', v_row.id, 'status', v_status);
END; $$;

REVOKE ALL ON FUNCTION public.submit_identity_verification(text, text, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_identity_verification(text, text, text, text, text, text) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_review_identity_verification(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_review_identity_verification(uuid, boolean, text) TO authenticated;

-- Order gate helper, used by create_order_atomic.
CREATE OR REPLACE FUNCTION public.assert_order_allowed_by_verification(
  p_customer_id uuid, p_owner_id uuid, p_payment_method text, p_total numeric
) RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_owner_status text;
  v_customer_status text;
  v_active int;
BEGIN
  SELECT verification_status INTO v_owner_status FROM public.profiles WHERE id = p_owner_id;
  IF coalesce(v_owner_status, 'unverified') <> 'approved' THEN
    RAISE EXCEPTION 'This station is not verified yet and cannot take orders.';
  END IF;

  SELECT verification_status INTO v_customer_status FROM public.profiles WHERE id = p_customer_id;
  IF coalesce(v_customer_status, 'unverified') = 'approved'
     OR lower(coalesce(p_payment_method, 'cod')) NOT IN ('cod', 'cash') THEN
    RETURN;
  END IF;

  IF p_total > 1000 THEN
    RAISE EXCEPTION 'Verify your ID to place cash-on-delivery orders above PHP 1,000.';
  END IF;
  SELECT count(*) INTO v_active FROM public.orders
  WHERE customer_id = p_customer_id
    AND lower(coalesce(payment_method, 'cod')) IN ('cod', 'cash')
    AND status NOT IN ('delivered', 'cancelled', 'failed');
  IF v_active >= 2 THEN
    RAISE EXCEPTION 'Verify your ID to have more than 2 cash-on-delivery orders at a time.';
  END IF;
END; $$;
REVOKE ALL ON FUNCTION public.assert_order_allowed_by_verification(uuid, uuid, text, numeric) FROM PUBLIC, anon, authenticated;

-- Backfill: stations that already delivered orders keep working.
UPDATE public.profiles p SET verification_status = 'approved'
WHERE p.role = 'owner' AND p.verification_status = 'unverified'
  AND EXISTS (SELECT 1 FROM public.orders o WHERE o.owner_id = p.id AND o.status = 'delivered');


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- create_order_atomic v3 (2026-11-05)
-- ==============================================================================
-- Starts from the LIVE definition (pg_get_functiondef on 2026-11-05; note the
-- live function does not use price_order() from whole_peso_pricing.sql).
-- Changes:
--   * Delivery fee comes from compute_delivery_quote() (free zone or per-km),
--     never from the client and no longer from owner_settings.base_delivery_fee.
--   * Writes delivery_distance_km, delivery_rate_per_km, delivery_free_reason.
--   * Accessories (products.kind = 'accessory') are sold alongside water;
--     only water gallons count toward the free-delivery gallon threshold.
--   * Optional rider tip (tip_amount, ₱0–₱500) added to the total.
--   * ID verification gates: approved stations only; COD limits for
--     unverified customers.
-- This is the single place later features (accessories, tips, verification
-- gates) extend create_order_atomic. Do not redefine it in other scripts.
--
-- Run order: harden_signup_and_protected_columns.sql -> delivery_coverage.sql ->
--   station_accessories.sql -> rider_tips.sql -> identity_verification.sql -> this file.
-- Tests: supabase/tests/delivery_quote_test.sql, accessories_test.sql
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.create_order_atomic(p_order_data jsonb, p_items_data jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_customer_id uuid := auth.uid();
  v_owner_id uuid;
  v_payment_method text;
  v_idempotency_key public.orders.idempotency_key%TYPE;
  v_voucher_id uuid;
  v_order_id uuid;
  v_item record;
  v_product record;
  v_computed_subtotal numeric(10,2) := 0;
  v_delivery_fee numeric(10,2) := 0;
  v_platform_fee numeric(10,2) := 0;
  v_discount numeric(10,2) := 0;
  v_total_amount numeric(10,2) := 0;
  v_order_row public.orders%ROWTYPE;
  v_voucher public.customer_reward_vouchers%ROWTYPE;
  v_config jsonb;
  v_lat double precision;
  v_lng double precision;
  v_maintenance jsonb;
  v_is_maintenance boolean := false;
  v_customer_suspended boolean := false;
  v_owner_suspended boolean := false;
  v_gallons integer := 0;
  v_quote jsonb;
  v_tip numeric(10,2) := 0;
BEGIN
  SELECT value INTO v_maintenance
  FROM public.system_config
  WHERE key = 'maintenance_mode';

  IF v_maintenance IS NOT NULL THEN
    IF jsonb_typeof(v_maintenance) = 'boolean' THEN
      v_is_maintenance := v_maintenance::text::boolean;
    ELSIF jsonb_typeof(v_maintenance) = 'string' THEN
      v_is_maintenance :=
        lower(trim(both '"' from v_maintenance::text)) IN ('true', '1', 'yes');
    END IF;
  END IF;

  IF v_is_maintenance THEN
    RAISE EXCEPTION 'System is currently undergoing maintenance. New orders are temporarily paused.';
  END IF;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required to place an order.';
  END IF;

  SELECT coalesce(is_suspended, false) INTO v_customer_suspended
  FROM public.profiles
  WHERE id = v_customer_id AND role = 'customer';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Only customer accounts can place orders.';
  END IF;
  IF v_customer_suspended THEN
    RAISE EXCEPTION 'Your account has been suspended. Please contact customer support.';
  END IF;

  v_idempotency_key := NULLIF(p_order_data->>'idempotency_key', '');
  IF v_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_order_row
    FROM public.orders
    WHERE customer_id = v_customer_id
      AND idempotency_key = v_idempotency_key;

    IF FOUND THEN
      RETURN jsonb_build_object(
        'id', v_order_row.id,
        'subtotal', v_order_row.subtotal,
        'delivery_fee', v_order_row.delivery_fee,
        'platform_fee', v_order_row.platform_fee,
        'total_amount', v_order_row.total_amount,
        'status', v_order_row.status
      );
    END IF;
  END IF;

  v_owner_id := NULLIF(p_order_data->>'owner_id', '')::uuid;
  v_payment_method := lower(trim(coalesce(p_order_data->>'payment_method', 'cod')));
  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'Station owner ID is required.';
  END IF;

  SELECT coalesce(is_suspended, false) INTO v_owner_suspended
  FROM public.profiles
  WHERE id = v_owner_id AND role = 'owner';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Water refill station not found.';
  END IF;
  IF v_owner_suspended THEN
    RAISE EXCEPTION 'This water station is currently suspended by administration.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = v_owner_id
      AND role = 'owner'
      AND coalesce(station_availability, 'open') = 'open'
  ) THEN
    RAISE EXCEPTION 'This water station is currently closed or unavailable.';
  END IF;
  IF NOT public.is_station_payment_method_available(v_owner_id, v_payment_method) THEN
    RAISE EXCEPTION 'This payment method is not available for this station.';
  END IF;

  FOR v_item IN
    SELECT * FROM jsonb_to_recordset(p_items_data) AS x(
      product_id uuid,
      quantity integer,
      product_name text
    )
  LOOP
    IF v_item.quantity <= 0 THEN
      RAISE EXCEPTION 'Invalid quantity for item %', v_item.product_name;
    END IF;

    SELECT * INTO v_product
    FROM public.products
    WHERE id = v_item.product_id
      AND owner_id = v_owner_id
      AND is_available = true;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Product % is unavailable at this station.', v_item.product_name;
    END IF;

    v_computed_subtotal :=
      v_computed_subtotal + (v_product.price * v_item.quantity);
    -- Only water counts toward the free-delivery gallon threshold.
    IF v_product.kind = 'water' THEN
      v_gallons := v_gallons + v_item.quantity;
    END IF;
  END LOOP;

  IF v_computed_subtotal <= 0 THEN
    RAISE EXCEPTION 'Cart cannot be empty.';
  END IF;

  v_lat := NULLIF(p_order_data->>'customer_latitude', '')::double precision;
  v_lng := NULLIF(p_order_data->>'customer_longitude', '')::double precision;

  -- Delivery fee: server-side quote (free zone or per-km). Client fee ignored.
  v_quote := public.compute_delivery_quote(
    v_owner_id, v_lat, v_lng,
    NULLIF(p_order_data->>'customer_barangay', ''),
    v_gallons
  );
  v_delivery_fee := coalesce((v_quote->>'fee')::numeric, 0);

  v_config := public.get_platform_fee_config();
  IF coalesce((v_config->>'enabled')::boolean, false) THEN
    v_platform_fee := round(
      ((v_computed_subtotal + v_delivery_fee)
        * coalesce((v_config->>'percent')::numeric, 0) / 100)
        + coalesce((v_config->>'fixed')::numeric, 0),
      2
    );
    v_platform_fee := greatest(v_platform_fee, 0);
  END IF;

  v_voucher_id := NULLIF(p_order_data->>'voucher_id', '')::uuid;
  IF v_voucher_id IS NOT NULL THEN
    SELECT * INTO v_voucher
    FROM public.customer_reward_vouchers
    WHERE id = v_voucher_id
      AND user_id = v_customer_id
      AND is_used = false
      AND expires_at > now()
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'This reward voucher is no longer available. Refresh your vouchers and try again.';
    END IF;

    IF v_voucher.is_delivery_discount THEN
      v_discount := least(
        greatest(v_voucher.discount_amount, 0),
        v_delivery_fee
      );
    ELSE
      v_discount := least(
        greatest(v_voucher.discount_amount, 0),
        v_computed_subtotal + v_delivery_fee + v_platform_fee
      );
    END IF;
  END IF;

  -- Optional rider tip: whole pesos, ₱0–₱500, paid on top (no fees, no voucher).
  v_tip := round(coalesce(NULLIF(p_order_data->>'tip_amount', '')::numeric, 0));
  IF v_tip < 0 OR v_tip > 500 THEN
    RAISE EXCEPTION 'Tip must be between PHP 0 and PHP 500.';
  END IF;

  v_total_amount := greatest(
    v_computed_subtotal + v_delivery_fee + v_platform_fee - v_discount,
    0
  ) + v_tip;

  -- ID verification gates (identity_verification.sql).
  PERFORM public.assert_order_allowed_by_verification(
    v_customer_id, v_owner_id, v_payment_method, v_total_amount
  );

  INSERT INTO public.orders (
    id,
    customer_id,
    owner_id,
    station_name,
    customer_name,
    customer_phone,
    customer_address,
    customer_barangay,
    customer_municipality,
    customer_landmark,
    idempotency_key,
    subtotal,
    delivery_fee,
    platform_fee,
    total_amount,
    payment_method,
    payment_status,
    notes,
    region_id,
    customer_latitude,
    customer_longitude,
    delivery_lat,
    delivery_lng,
    delivery_latitude,
    delivery_longitude,
    delivery_distance_km,
    delivery_rate_per_km,
    delivery_free_reason,
    tip_amount,
    items,
    status
  ) VALUES (
    coalesce(
      NULLIF(p_order_data->>'id', '')::uuid,
      gen_random_uuid()
    ),
    v_customer_id,
    v_owner_id,
    coalesce(p_order_data->>'station_name', 'Water Station'),
    p_order_data->>'customer_name',
    p_order_data->>'customer_phone',
    p_order_data->>'customer_address',
    p_order_data->>'customer_barangay',
    p_order_data->>'customer_municipality',
    p_order_data->>'customer_landmark',
    v_idempotency_key,
    v_computed_subtotal,
    v_delivery_fee,
    v_platform_fee,
    v_total_amount,
    v_payment_method,
    'pending',
    p_order_data->>'notes',
    NULLIF(p_order_data->>'region_id', '')::uuid,
    v_lat,
    v_lng,
    v_lat,
    v_lng,
    v_lat,
    v_lng,
    (v_quote->>'distance_km')::numeric,
    (v_quote->>'rate_per_km')::numeric,
    v_quote->>'free_reason',
    v_tip,
    coalesce(p_items_data, '[]'::jsonb),
    'pending'
  )
  ON CONFLICT DO NOTHING
  RETURNING * INTO v_order_row;

  IF NOT FOUND THEN
    IF v_idempotency_key IS NOT NULL THEN
      SELECT * INTO v_order_row
      FROM public.orders
      WHERE customer_id = v_customer_id
        AND idempotency_key = v_idempotency_key;

      IF FOUND THEN
        RETURN jsonb_build_object(
          'id', v_order_row.id,
          'subtotal', v_order_row.subtotal,
          'delivery_fee', v_order_row.delivery_fee,
          'platform_fee', v_order_row.platform_fee,
          'total_amount', v_order_row.total_amount,
          'status', v_order_row.status
        );
      END IF;
    END IF;
    RAISE EXCEPTION 'Order could not be created because of a conflicting order record.';
  END IF;

  v_order_id := v_order_row.id;

  FOR v_item IN
    SELECT * FROM jsonb_to_recordset(p_items_data) AS x(
      product_id uuid,
      quantity integer,
      product_name text
    )
  LOOP
    SELECT * INTO v_product FROM public.products WHERE id = v_item.product_id;
    INSERT INTO public.order_items (
      order_id,
      product_id,
      product_name,
      quantity,
      price_at_purchase,
      subtotal
    ) VALUES (
      v_order_id,
      v_item.product_id,
      v_product.name,
      v_item.quantity,
      v_product.price,
      (v_product.price * v_item.quantity)
    );
  END LOOP;

  IF v_voucher_id IS NOT NULL THEN
    UPDATE public.customer_reward_vouchers
    SET is_used = true
    WHERE id = v_voucher_id
      AND user_id = v_customer_id
      AND is_used = false;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'This reward voucher was already used by another order.';
    END IF;
  END IF;

  INSERT INTO public.system_notifications (
    user_id,
    type,
    priority,
    title,
    content,
    metadata
  ) VALUES (
    v_owner_id,
    'system_alert',
    'high',
    'New Refill Order',
    coalesce(p_order_data->>'customer_name', 'A customer')
      || ' placed a new refill order of PHP '
      || trim(to_char(v_total_amount, '999999990.00'))
      || ' (' || upper(coalesce(p_order_data->>'payment_method', 'cod')) || ').',
    jsonb_build_object(
      'order_id', v_order_id,
      'status', 'pending',
      'total_amount', v_total_amount
    )
  );

  RETURN jsonb_build_object(
    'id', v_order_id,
    'subtotal', v_computed_subtotal,
    'delivery_fee', v_delivery_fee,
    'delivery_distance_km', (v_quote->>'distance_km')::numeric,
    'delivery_free_reason', v_quote->>'free_reason',
    'platform_fee', v_platform_fee,
    'discount_amount', v_discount,
    'tip_amount', v_tip,
    'total_amount', v_total_amount,
    'status', 'pending'
  );
END;
$function$;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Rider live location privacy (2026-11-05)
-- ==============================================================================
-- rider_locations was readable by everyone ("Public can view rider
-- locations"). Now only these can read a rider's points:
--   * the rider, admins
--   * the customer or station of an order that rider is delivering right now
--     (assigned_to_rider / out_for_delivery)
-- After delivery the customer loses access. Points older than 24 h are purged
-- hourly (pg_cron, when the extension is available).
-- Test: supabase/tests/rider_live_location_test.sql
-- ==============================================================================

DROP POLICY IF EXISTS "Public can view rider locations" ON public.rider_locations;
DROP POLICY IF EXISTS "Rider location visible to active delivery parties" ON public.rider_locations;
CREATE POLICY "Rider location visible to active delivery parties" ON public.rider_locations
  FOR SELECT TO authenticated
  USING (
    rider_id = auth.uid()
    OR public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.orders o
      WHERE (o.assigned_rider_id = rider_locations.rider_id OR o.rider_id = rider_locations.rider_id)
        AND o.status IN ('assigned_to_rider', 'out_for_delivery')
        AND (o.customer_id = auth.uid() OR o.owner_id = auth.uid())
    )
  );

DROP POLICY IF EXISTS "Riders can update their own location" ON public.rider_locations;
CREATE POLICY "Riders can update their own location" ON public.rider_locations
  FOR INSERT TO authenticated
  WITH CHECK (rider_id = auth.uid());
REVOKE ALL ON public.rider_locations FROM anon;

CREATE OR REPLACE FUNCTION public.purge_old_rider_locations()
RETURNS integer
LANGUAGE sql SECURITY DEFINER SET search_path TO 'public' AS $$
  WITH d AS (
    DELETE FROM public.rider_locations WHERE "timestamp" < now() - interval '24 hours' RETURNING 1
  ) SELECT count(*)::int FROM d;
$$;
REVOKE ALL ON FUNCTION public.purge_old_rider_locations() FROM PUBLIC, anon, authenticated;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'purge_old_rider_locations';
    PERFORM cron.schedule('purge_old_rider_locations', '7 * * * *', 'SELECT public.purge_old_rider_locations()');
  END IF;
END $$;

-- ==============================================================================
-- Smart refill reminders (2026-11-05)
-- ==============================================================================
-- Learns each customer's refill rhythm (median days between their last
-- delivered orders, needs >= 3 orders) and reminds them a day before they
-- usually reorder. At most one reminder per 3 days, never while an order is
-- active, and only when profiles.refill_reminders_enabled.
--   * customer_refill_rhythm()  -> for the app's home banner (current user)
--   * send_refill_reminders()   -> daily 9:00 PH pg_cron job, inserts notifications
-- Test: supabase/tests/refill_reminders_test.sql
-- ==============================================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS refill_reminders_enabled boolean NOT NULL DEFAULT true;

CREATE OR REPLACE FUNCTION public.refill_rhythm_for(p_customer_id uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  WITH recent AS (
    SELECT created_at, owner_id, station_name
    FROM public.orders
    WHERE customer_id = p_customer_id AND status = 'delivered'
    ORDER BY created_at DESC
    LIMIT 6
  ), gaps AS (
    SELECT extract(epoch FROM (created_at - lead(created_at) OVER (ORDER BY created_at DESC))) / 86400.0 AS days
    FROM recent
  ), stats AS (
    SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY days) AS median_days,
           count(*) AS gap_count
    FROM gaps WHERE days IS NOT NULL AND days > 0.5
  ), last AS (
    SELECT * FROM recent ORDER BY created_at DESC LIMIT 1
  )
  SELECT CASE
    WHEN (SELECT gap_count FROM stats) < 2 THEN jsonb_build_object('has_rhythm', false)
    ELSE jsonb_build_object(
      'has_rhythm', true,
      'median_days', round((SELECT median_days FROM stats)::numeric, 1),
      'last_order_at', (SELECT created_at FROM last),
      'station_id', (SELECT owner_id FROM last),
      'station_name', (SELECT station_name FROM last),
      'due_at', (SELECT created_at FROM last)
                + make_interval(secs => greatest((SELECT median_days FROM stats) - 1, 1) * 86400),
      'is_due', now() >= (SELECT created_at FROM last)
                + make_interval(secs => greatest((SELECT median_days FROM stats) - 1, 1) * 86400),
      'has_active_order', EXISTS (
        SELECT 1 FROM public.orders
        WHERE customer_id = p_customer_id
          AND status NOT IN ('delivered', 'cancelled', 'failed'))
    )
  END;
$$;
REVOKE ALL ON FUNCTION public.refill_rhythm_for(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.customer_refill_rhythm()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT CASE WHEN auth.uid() IS NULL THEN '{"has_rhythm": false}'::jsonb
              ELSE public.refill_rhythm_for(auth.uid()) END;
$$;
REVOKE ALL ON FUNCTION public.customer_refill_rhythm() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.customer_refill_rhythm() TO authenticated;

CREATE OR REPLACE FUNCTION public.send_refill_reminders()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_row record;
  v_r jsonb;
  v_sent integer := 0;
BEGIN
  FOR v_row IN
    SELECT p.id FROM public.profiles p
    WHERE p.role = 'customer' AND p.refill_reminders_enabled AND NOT coalesce(p.is_suspended, false)
  LOOP
    v_r := public.refill_rhythm_for(v_row.id);
    CONTINUE WHEN NOT coalesce((v_r->>'has_rhythm')::boolean, false)
               OR NOT (v_r->>'is_due')::boolean
               OR (v_r->>'has_active_order')::boolean;
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM public.system_notifications n
      WHERE n.user_id = v_row.id
        AND n.metadata->>'kind' = 'refill_reminder'
        AND n.created_at > now() - interval '3 days');

    INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
    VALUES (
      v_row.id, 'system_alert', 'normal', 'Time for a refill?',
      'You usually reorder every ' || round((v_r->>'median_days')::numeric) || ' days. '
        || 'Tap to reorder from ' || coalesce(v_r->>'station_name', 'your station') || '.',
      jsonb_build_object('kind', 'refill_reminder', 'station_id', v_r->>'station_id')
    );
    v_sent := v_sent + 1;
  END LOOP;
  RETURN v_sent;
END; $$;
REVOKE ALL ON FUNCTION public.send_refill_reminders() FROM PUBLIC, anon, authenticated;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'send_refill_reminders';
    -- 9:00 Asia/Manila = 01:00 UTC, so reminders arrive in the morning.
    PERFORM cron.schedule('send_refill_reminders', '0 1 * * *', 'SELECT public.send_refill_reminders()');
  END IF;
END $$;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Water quality transparency (2026-11-05)
-- ==============================================================================
-- Stations upload lab test results and permits (bacteriological /
-- physical-chemical water analysis, sanitary permit, business permit) with
-- issue and expiry dates. Admins approve them; approved, unexpired lab tests
-- give the station a "Water tested" badge and a small ranking boost.
-- Files live in the private verification_docs bucket under <uid>/certs/.
-- Approved certificate files are viewable by any signed-in user.
-- Daily job: marks expired certificates and warns owners 14 days ahead.
--
-- Run after: identity_verification.sql (bucket). Test: supabase/tests/water_quality_certs_test.sql
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.station_certifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  cert_type text NOT NULL CHECK (cert_type IN (
    'bacteriological', 'physical_chemical', 'sanitary_permit', 'business_permit')),
  issued_on date NOT NULL,
  expires_on date NOT NULL,
  file_path text NOT NULL,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected', 'expired')),
  reviewer_id uuid REFERENCES public.profiles(id),
  reviewed_at timestamptz,
  rejection_reason text,
  expiry_warned_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (expires_on > issued_on)
);
CREATE INDEX IF NOT EXISTS idx_station_certs_owner ON public.station_certifications (owner_id, status);

ALTER TABLE public.station_certifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Approved certs are public, owners see their own" ON public.station_certifications;
CREATE POLICY "Approved certs are public, owners see their own" ON public.station_certifications
  FOR SELECT TO authenticated
  USING (status = 'approved' OR owner_id = auth.uid() OR public.is_admin());
REVOKE INSERT, UPDATE, DELETE ON public.station_certifications FROM anon, authenticated;
GRANT SELECT ON public.station_certifications TO authenticated;

-- Approved certificate files are readable by signed-in users.
DROP POLICY IF EXISTS "Verification docs: approved certs readable" ON storage.objects;
CREATE POLICY "Verification docs: approved certs readable" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'verification_docs' AND EXISTS (
    SELECT 1 FROM public.station_certifications c
    WHERE c.file_path = storage.objects.name AND c.status = 'approved'));

CREATE OR REPLACE FUNCTION public.submit_station_certification(
  p_cert_type text, p_issued_on date, p_expires_on date, p_file_path text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_uid AND role = 'owner') THEN
    RAISE EXCEPTION 'Only station owners upload certificates.';
  END IF;
  IF p_file_path IS NULL OR left(p_file_path, length(v_uid::text) + 7) <> v_uid::text || '/certs/' THEN
    RAISE EXCEPTION 'Upload the certificate file first.';
  END IF;
  IF p_expires_on <= current_date THEN
    RAISE EXCEPTION 'This certificate has already expired.';
  END IF;
  IF p_issued_on > current_date THEN
    RAISE EXCEPTION 'The issue date cannot be in the future.';
  END IF;
  INSERT INTO public.station_certifications (owner_id, cert_type, issued_on, expires_on, file_path)
  VALUES (v_uid, p_cert_type, p_issued_on, p_expires_on, p_file_path)
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('id', v_id, 'status', 'pending');
END; $$;

CREATE OR REPLACE FUNCTION public.admin_review_station_certification(
  p_cert_id uuid, p_approve boolean, p_reason text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_row public.station_certifications%ROWTYPE;
  v_status text := CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  IF NOT p_approve AND coalesce(trim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'Give the station a reason for the rejection.';
  END IF;
  UPDATE public.station_certifications
  SET status = v_status, reviewer_id = auth.uid(), reviewed_at = now(),
      rejection_reason = CASE WHEN p_approve THEN NULL ELSE trim(p_reason) END
  WHERE id = p_cert_id AND status = 'pending'
  RETURNING * INTO v_row;
  IF NOT FOUND THEN RAISE EXCEPTION 'This certificate was already reviewed.'; END IF;

  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (v_row.owner_id, 'system_alert', 'normal',
    CASE WHEN p_approve THEN 'Certificate approved' ELSE 'Certificate rejected' END,
    CASE WHEN p_approve THEN 'Customers can now see your certificate.'
         ELSE 'Reason: ' || trim(p_reason) END,
    jsonb_build_object('certificate_id', v_row.id, 'status', v_status));
  RETURN jsonb_build_object('id', v_row.id, 'status', v_status);
END; $$;

REVOKE ALL ON FUNCTION public.submit_station_certification(text, date, date, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_station_certification(text, date, date, text) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_review_station_certification(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_review_station_certification(uuid, boolean, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.expire_station_certifications()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_n integer;
BEGIN
  UPDATE public.station_certifications SET status = 'expired'
  WHERE status = 'approved' AND expires_on <= current_date;
  GET DIAGNOSTICS v_n = ROW_COUNT;

  WITH soon AS (
    UPDATE public.station_certifications SET expiry_warned_at = now()
    WHERE status = 'approved' AND expiry_warned_at IS NULL
      AND expires_on <= current_date + 14
    RETURNING owner_id, id, cert_type, expires_on
  )
  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  SELECT owner_id, 'system_alert', 'high', 'Certificate expiring soon',
         'Your ' || replace(cert_type, '_', ' ') || ' certificate expires on '
           || to_char(expires_on, 'Mon DD, YYYY') || '. Upload a new one to keep your badge.',
         jsonb_build_object('certificate_id', id)
  FROM soon;
  RETURN v_n;
END; $$;
REVOKE ALL ON FUNCTION public.expire_station_certifications() FROM PUBLIC, anon, authenticated;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'expire_station_certifications';
    PERFORM cron.schedule('expire_station_certifications', '15 16 * * *', 'SELECT public.expire_station_certifications()');
  END IF;
END $$;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Order disputes and refunds (2026-11-05)
-- ==============================================================================
-- Extends the existing public.disputes table (status enum: open,
-- investigating, resolved, dismissed) with the customer -> station -> admin
-- flow:
--   1. Customer opens a dispute within 48 h of delivery, one per order,
--      with optional photo evidence (private bucket dispute_evidence).
--   2. Station accepts (refund amount) -> resolved, or explains -> the
--      dispute is escalated ('investigating') for an admin.
--   3. Customer may escalate if the station has not answered in 24 h.
--   4. Admin resolves with an optional refund, or dismisses.
-- A granted refund books a REFUND ledger entry against the station, notifies
-- the customer, and refunds against the station increase flagged_count.
-- Money movement: COD refunds are returned by the station in cash; online
-- payments are refunded by the admin in PayMongo (orders.payment_status is
-- set to 'refunded' when the full total is refunded).
--
-- Test: supabase/tests/order_disputes_test.sql
-- ==============================================================================

ALTER TABLE public.disputes
  ADD COLUMN IF NOT EXISTS evidence_paths text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS owner_response text,
  ADD COLUMN IF NOT EXISTS owner_responded_at timestamptz,
  ADD COLUMN IF NOT EXISTS refund_amount numeric(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS escalated_at timestamptz;
ALTER TABLE public.disputes DROP CONSTRAINT IF EXISTS disputes_reason_check;
ALTER TABLE public.disputes ADD CONSTRAINT disputes_reason_check CHECK (reason IN (
  'missing_items', 'wrong_item', 'quality', 'damaged', 'not_delivered', 'overcharged', 'other'));
ALTER TABLE public.disputes DROP CONSTRAINT IF EXISTS disputes_refund_check;
ALTER TABLE public.disputes ADD CONSTRAINT disputes_refund_check CHECK (refund_amount >= 0);
CREATE UNIQUE INDEX IF NOT EXISTS disputes_one_per_order ON public.disputes (order_id);

-- Owners no longer update disputes directly; they use owner_respond_dispute.
DROP POLICY IF EXISTS "Owners can update disputes for their station" ON public.disputes;
REVOKE INSERT, DELETE ON public.disputes FROM anon, authenticated;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('dispute_evidence', 'dispute_evidence', false, 8388608,
        ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO UPDATE SET public = false;
DROP POLICY IF EXISTS "Dispute evidence: reporter upload" ON storage.objects;
CREATE POLICY "Dispute evidence: reporter upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'dispute_evidence' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "Dispute evidence: parties read" ON storage.objects;
CREATE POLICY "Dispute evidence: parties read" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'dispute_evidence' AND (
    (storage.foldername(name))[1] = auth.uid()::text
    OR public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.disputes d JOIN public.orders o ON o.id = d.order_id
      WHERE storage.objects.name = ANY (d.evidence_paths) AND o.owner_id = auth.uid())));

CREATE OR REPLACE FUNCTION public.open_dispute(
  p_order_id uuid, p_reason text, p_description text, p_evidence_paths text[] DEFAULT '{}'
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_order public.orders%ROWTYPE;
  v_done_at timestamptz;
  v_id uuid;
  v_path text;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id AND customer_id = v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order not found.'; END IF;
  IF v_order.status::text <> 'delivered' THEN
    RAISE EXCEPTION 'You can report a problem once the order is delivered.';
  END IF;
  v_done_at := coalesce(v_order.actual_completion_at, v_order.updated_at, v_order.created_at);
  IF v_done_at < now() - interval '48 hours' THEN
    RAISE EXCEPTION 'Problems must be reported within 48 hours of delivery.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.disputes WHERE order_id = p_order_id) THEN
    RAISE EXCEPTION 'A problem was already reported for this order.';
  END IF;
  IF coalesce(trim(p_description), '') = '' THEN
    RAISE EXCEPTION 'Tell the station what went wrong.';
  END IF;
  FOREACH v_path IN ARRAY coalesce(p_evidence_paths, '{}') LOOP
    IF left(v_path, length(v_uid::text) + 1) <> v_uid::text || '/' THEN
      RAISE EXCEPTION 'Invalid evidence photo.';
    END IF;
  END LOOP;

  INSERT INTO public.disputes (order_id, reporter_id, reason, description, status, evidence_paths)
  VALUES (p_order_id, v_uid, p_reason, trim(p_description), 'open', coalesce(p_evidence_paths, '{}'))
  RETURNING id INTO v_id;

  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (v_order.owner_id, 'system_alert', 'high', 'A customer reported a problem',
    'Order #' || upper(substr(p_order_id::text, 1, 8)) || ': ' || replace(p_reason, '_', ' ')
      || '. Please respond within 24 hours.',
    jsonb_build_object('dispute_id', v_id, 'order_id', p_order_id));
  RETURN jsonb_build_object('id', v_id, 'status', 'open');
END; $$;

-- Shared by station and admin resolutions.
CREATE OR REPLACE FUNCTION public.apply_dispute_refund(p_dispute_id uuid, p_amount numeric, p_note text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_d public.disputes%ROWTYPE;
  v_o public.orders%ROWTYPE;
BEGIN
  SELECT * INTO v_d FROM public.disputes WHERE id = p_dispute_id;
  SELECT * INTO v_o FROM public.orders WHERE id = v_d.order_id;
  IF p_amount < 0 OR p_amount > v_o.total_amount THEN
    RAISE EXCEPTION 'Refund must be between PHP 0 and the order total.';
  END IF;
  UPDATE public.disputes SET refund_amount = p_amount, status = 'resolved',
         resolution_notes = p_note, updated_at = now()
  WHERE id = p_dispute_id;
  IF p_amount > 0 THEN
    INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
    VALUES (v_o.owner_id, v_o.id, -p_amount, 'REFUND', 'Refund for reported problem');
    UPDATE public.profiles SET flagged_count = coalesce(flagged_count, 0) + 1 WHERE id = v_o.owner_id;
    IF p_amount >= v_o.total_amount THEN
      UPDATE public.orders SET payment_status = 'refunded' WHERE id = v_o.id;
    END IF;
  END IF;
  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (v_d.reporter_id, 'system_alert', 'high',
    CASE WHEN p_amount > 0 THEN 'Refund approved' ELSE 'Your report was reviewed' END,
    CASE WHEN p_amount > 0
      THEN 'PHP ' || trim(to_char(p_amount, '999990.00')) || ' will be returned '
        || CASE WHEN lower(coalesce(v_o.payment_method, 'cod')) IN ('cod', 'cash')
                THEN 'by the station in cash.' ELSE 'to your original payment method.' END
      ELSE coalesce(p_note, 'No refund was given.') END,
    jsonb_build_object('dispute_id', p_dispute_id, 'order_id', v_o.id, 'refund_amount', p_amount));
END; $$;
REVOKE ALL ON FUNCTION public.apply_dispute_refund(uuid, numeric, text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.owner_respond_dispute(
  p_dispute_id uuid, p_accept boolean, p_response text, p_refund_amount numeric DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_d public.disputes%ROWTYPE;
BEGIN
  SELECT d.* INTO v_d FROM public.disputes d JOIN public.orders o ON o.id = d.order_id
  WHERE d.id = p_dispute_id AND o.owner_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Dispute not found.'; END IF;
  IF v_d.status::text <> 'open' OR v_d.owner_responded_at IS NOT NULL THEN
    RAISE EXCEPTION 'This dispute was already answered.';
  END IF;
  IF coalesce(trim(p_response), '') = '' THEN RAISE EXCEPTION 'Write a reply to the customer.'; END IF;

  UPDATE public.disputes SET owner_response = trim(p_response), owner_responded_at = now(), updated_at = now()
  WHERE id = p_dispute_id;

  IF p_accept THEN
    PERFORM public.apply_dispute_refund(p_dispute_id, coalesce(p_refund_amount, 0), 'Station: ' || trim(p_response));
    RETURN jsonb_build_object('status', 'resolved');
  END IF;

  UPDATE public.disputes SET status = 'investigating', escalated_at = now() WHERE id = p_dispute_id;
  RETURN jsonb_build_object('status', 'investigating');
END; $$;

CREATE OR REPLACE FUNCTION public.escalate_dispute(p_dispute_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  UPDATE public.disputes SET status = 'investigating', escalated_at = now(), updated_at = now()
  WHERE id = p_dispute_id AND reporter_id = auth.uid() AND status = 'open'
    AND owner_responded_at IS NULL AND created_at < now() - interval '24 hours';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'You can ask eRefill to step in 24 hours after reporting if the station has not replied.';
  END IF;
  RETURN jsonb_build_object('status', 'investigating');
END; $$;

CREATE OR REPLACE FUNCTION public.admin_resolve_dispute(
  p_dispute_id uuid, p_refund_amount numeric, p_notes text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.disputes WHERE id = p_dispute_id AND status IN ('open', 'investigating')) THEN
    RAISE EXCEPTION 'This dispute is already closed.';
  END IF;
  UPDATE public.disputes SET resolved_by = auth.uid() WHERE id = p_dispute_id;
  PERFORM public.apply_dispute_refund(p_dispute_id, coalesce(p_refund_amount, 0), p_notes);
  IF coalesce(p_refund_amount, 0) = 0 THEN
    UPDATE public.disputes SET status = 'dismissed' WHERE id = p_dispute_id;
  END IF;
  RETURN jsonb_build_object('status', CASE WHEN coalesce(p_refund_amount, 0) > 0 THEN 'resolved' ELSE 'dismissed' END);
END; $$;

REVOKE ALL ON FUNCTION public.open_dispute(uuid, text, text, text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.open_dispute(uuid, text, text, text[]) TO authenticated;
REVOKE ALL ON FUNCTION public.owner_respond_dispute(uuid, boolean, text, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.owner_respond_dispute(uuid, boolean, text, numeric) TO authenticated;
REVOKE ALL ON FUNCTION public.escalate_dispute(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.escalate_dispute(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_resolve_dispute(uuid, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_resolve_dispute(uuid, numeric, text) TO authenticated;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- AI ordering assistant: per-user daily message limit (2026-11-05)
-- ==============================================================================
-- The order-assistant Edge Function records one row per message (with the
-- service role) and refuses more than 20 per user in 24 hours.
-- Users can read their own usage; nobody writes from the app.
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.assistant_usage (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  input_tokens integer NOT NULL DEFAULT 0,
  output_tokens integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_assistant_usage_user_time ON public.assistant_usage (user_id, created_at DESC);

ALTER TABLE public.assistant_usage ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users read own assistant usage" ON public.assistant_usage;
CREATE POLICY "Users read own assistant usage" ON public.assistant_usage
  FOR SELECT TO authenticated USING (user_id = auth.uid());
REVOKE INSERT, UPDATE, DELETE ON public.assistant_usage FROM anon, authenticated;
GRANT SELECT ON public.assistant_usage TO authenticated;

-- Shared fixtures for the SQL tests in this folder. Every test runs as
--   BEGIN; <scripts under test, BEGIN/COMMIT stripped>; _fixtures.sql; <test>; ROLLBACK;
-- through the Supabase MCP execute_sql tool, so nothing persists.
--
-- Fixture rows are inserted with triggers off (replica role) to skip station
-- setup checks; triggers are back on before the test body runs.
--
-- ids: owner ...a1, second owner ...a2, customer ...c1, rider ...d1,
--      admin ...e1, product ...b1 (₱19.60, owner a1).

SET LOCAL session_replication_role = replica;

INSERT INTO auth.users (id, instance_id, aud, role, email, raw_user_meta_data, raw_app_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_owner@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000a2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_owner2@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_cust@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_rider@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_admin@example.test', '{}', '{}', now(), now());

INSERT INTO public.profiles (id, role, full_name, station_name, station_availability, latitude, longitude)
VALUES
  ('00000000-0000-4000-8000-0000000000a1', 'owner', 'T Owner', 'T Station', 'open', 14.60, 121.00),
  ('00000000-0000-4000-8000-0000000000a2', 'owner', 'T Owner 2', 'T Station 2', 'open', 14.61, 121.01),
  ('00000000-0000-4000-8000-0000000000c1', 'customer', 'T Cust', NULL, 'open', 14.62, 121.02),
  ('00000000-0000-4000-8000-0000000000d1', 'rider', 'T Rider', NULL, 'open', NULL, NULL),
  ('00000000-0000-4000-8000-0000000000e1', 'admin', 'T Admin', NULL, 'open', NULL, NULL);

INSERT INTO public.owner_settings (owner_id, base_delivery_fee)
VALUES
  ('00000000-0000-4000-8000-0000000000a1', 5.4),
  ('00000000-0000-4000-8000-0000000000a2', 0);

INSERT INTO public.products (id, owner_id, name, price, is_available)
VALUES ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000a1', 'T Water', 19.6, true);

-- Fee config used by every test unless a test overrides it.
UPDATE public.system_config SET value = '{"enabled": true, "percent": 1, "fixed": 0}'::jsonb
WHERE key = 'platform_fee';

SET LOCAL session_replication_role = origin;

-- Helpers (temporary: dropped with the transaction).
CREATE OR REPLACE FUNCTION pg_temp.act_as(p_user uuid) RETURNS void
LANGUAGE sql AS $$
  SELECT set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text,
    true
  );
$$;

CREATE OR REPLACE FUNCTION pg_temp.place_order(p_method text, p_qty integer DEFAULT 1)
RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  RETURN public.create_order_atomic(
    jsonb_build_object(
      'owner_id', '00000000-0000-4000-8000-0000000000a1',
      'payment_method', p_method,
      'customer_name', 'T Cust',
      'customer_address', 'Test address',
      'customer_latitude', '14.6',
      'customer_longitude', '121.0'
    ),
    jsonb_build_array(jsonb_build_object(
      'product_id', '00000000-0000-4000-8000-0000000000b1',
      'quantity', p_qty,
      'product_name', 'T Water'
    ))
  );
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.assert_eq(p_label text, p_actual anyelement, p_expected anyelement)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF p_actual IS DISTINCT FROM p_expected THEN
    RAISE EXCEPTION '% — expected %, got %', p_label, p_expected, p_actual;
  END IF;
END;
$$;

-- Runs p_sql and fails unless it raises an error containing p_message.
CREATE OR REPLACE FUNCTION pg_temp.expect_error(p_label text, p_sql text, p_message text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    IF position(p_message IN SQLERRM) = 0 THEN
      RAISE EXCEPTION '% — expected error "%", got "%"', p_label, p_message, SQLERRM;
    END IF;
    RETURN;
  END;
  RAISE EXCEPTION '% — expected error "%", but it succeeded', p_label, p_message;
END;
$$;
-- Run: bash build.sh ../scripts/harden_signup_and_protected_columns.sql ../scripts/delivery_coverage.sql ../scripts/station_accessories.sql ../scripts/rider_tips.sql ../scripts/identity_verification.sql ../scripts/order_pricing_v3.sql -- identity_verification_test.sql
-- Fixture owner a1 starts 'unverified' (no delivered orders).

-- unverified_station_cannot_take_orders
DO $$ BEGIN
  PERFORM pg_temp.expect_error('unverified station', $q$SELECT pg_temp.place_order('cod')$q$,
    'This station is not verified yet');
END $$;

-- customer_cannot_self_approve_via_table
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1'); SET LOCAL ROLE authenticated;
  PERFORM pg_temp.expect_error('direct insert',
    $q$INSERT INTO public.identity_verifications (user_id, role, id_type, front_path, selfie_path, status)
       VALUES ('00000000-0000-4000-8000-0000000000c1', 'customer', 'philsys', 'x', 'y', 'approved')$q$,
    'permission denied');
  RESET ROLE;
END $$;

-- submit_rejects_paths_outside_own_folder
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  PERFORM pg_temp.expect_error('foreign path',
    $q$SELECT public.submit_identity_verification('philsys', '1234',
       '00000000-0000-4000-8000-0000000000a1/front.jpg', NULL,
       '00000000-0000-4000-8000-0000000000c1/selfie.jpg')$q$,
    'Upload your ID photos');
END $$;

-- owner_needs_permit
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
  PERFORM pg_temp.expect_error('permit',
    $q$SELECT public.submit_identity_verification('umid', '9876',
       '00000000-0000-4000-8000-0000000000a1/front.jpg', NULL,
       '00000000-0000-4000-8000-0000000000a1/selfie.jpg')$q$,
    'business or sanitary permit');
END $$;

-- owner_submits_admin_approves_orders_flow
DO $$ DECLARE v jsonb; r jsonb; BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
  v := public.submit_identity_verification('umid', '9876',
       '00000000-0000-4000-8000-0000000000a1/front.jpg', '00000000-0000-4000-8000-0000000000a1/back.jpg',
       '00000000-0000-4000-8000-0000000000a1/selfie.jpg', '00000000-0000-4000-8000-0000000000a1/permit.pdf');
  PERFORM pg_temp.assert_eq('pending', (SELECT verification_status FROM public.profiles WHERE id = '00000000-0000-4000-8000-0000000000a1'), 'pending');

  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  PERFORM pg_temp.expect_error('non-admin review',
    format('SELECT public.admin_review_identity_verification(%L, true)', v->>'id'), 'Forbidden');

  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000e1');
  PERFORM public.admin_review_identity_verification((v->>'id')::uuid, true);
  PERFORM pg_temp.assert_eq('approved', (SELECT verification_status FROM public.profiles WHERE id = '00000000-0000-4000-8000-0000000000a1'), 'approved');

  r := pg_temp.place_order('cod');
  PERFORM pg_temp.assert_eq('order placed', r ? 'id', true);
END $$;

-- unverified_customer_cod_limits
DO $$ BEGIN
  PERFORM pg_temp.expect_error('cod over 1000', $q$SELECT pg_temp.place_order('cod', 60)$q$,
    'above PHP 1,000');
  PERFORM pg_temp.place_order('cod');  -- second active COD order (first placed above)
  PERFORM pg_temp.expect_error('third cod', $q$SELECT pg_temp.place_order('cod')$q$,
    'more than 2 cash-on-delivery');
END $$;

-- rejection_needs_reason
DO $$ DECLARE v jsonb; BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  v := public.submit_identity_verification('philsys', '1234',
       '00000000-0000-4000-8000-0000000000c1/front.jpg', NULL, '00000000-0000-4000-8000-0000000000c1/selfie.jpg');
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000e1');
  PERFORM pg_temp.expect_error('no reason',
    format('SELECT public.admin_review_identity_verification(%L, false)', v->>'id'), 'reason');
  PERFORM public.admin_review_identity_verification((v->>'id')::uuid, false, 'Photo is blurry');
  PERFORM pg_temp.assert_eq('rejected', (SELECT verification_status FROM public.profiles WHERE id = '00000000-0000-4000-8000-0000000000c1'), 'rejected');
END $$;

SELECT 'identity_verification_test: all passed' AS result;
ROLLBACK;

-- ===== rider_live_location_test =====
BEGIN;
-- ==============================================================================
-- Harden signup roles and protect trust columns on profiles (2026-11-05)
-- ==============================================================================
-- 1. Self-signup could claim role 'admin' or 'rider' through user metadata.
--    Only accounts created by a trusted server function (admin_create_user,
--    create_rider_account, admin_create_station) may get privileged roles.
--    Self-signups arrive through the Auth server, whose session user is
--    supabase_auth_admin; those are limited to customer/owner.
-- 2. Users could UPDATE their own average_rating / review_count /
--    reliability_score / flagged_count. Those are now writable only by admins
--    or by SECURITY DEFINER functions (e.g. update_station_stats()).
-- 3. Adds profiles.verification_status (used by identity verification), which is
--    protected the same way.
--
-- Run after: single_water_product_catalog.sql. Test: supabase/tests/protected_columns_test.sql
-- ==============================================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS verification_status text NOT NULL DEFAULT 'unverified';
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_verification_status_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_verification_status_check
  CHECK (verification_status IN ('unverified', 'pending', 'approved', 'rejected'));

-- 1. Role resolution -----------------------------------------------------------
CREATE OR REPLACE FUNCTION public.resolve_signup_role(p_requested text, p_trusted boolean)
RETURNS public.user_role
LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN p_requested IN ('customer', 'owner') THEN p_requested::public.user_role
    WHEN p_trusted AND p_requested IN ('rider', 'admin') THEN p_requested::public.user_role
    ELSE 'customer'::public.user_role
  END;
$$;
REVOKE ALL ON FUNCTION public.resolve_signup_role(text, boolean) FROM PUBLIC, anon, authenticated;

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
  -- 1. Role: self-signups (Auth server session) may only be customer or owner.
  v_role := public.resolve_signup_role(
    new.raw_user_meta_data->>'role',
    session_user <> 'supabase_auth_admin'
  );

  -- 2. Safe municipality enum resolution
  IF lower(trim(COALESCE(new.raw_user_meta_data->>'town', ''))) = 'cantilan' THEN
    v_town := 'Cantilan'::public.municipality;
  ELSIF lower(trim(COALESCE(new.raw_user_meta_data->>'town', ''))) = 'madrid' THEN
    v_town := 'Madrid'::public.municipality;
  ELSE
    v_town := NULL;
  END IF;

  v_complete_address := NULLIF(TRIM(COALESCE(new.raw_user_meta_data->>'complete_address', '')), '');

  -- 3. Names (Google OAuth sends 'name', 'given_name', 'family_name', 'picture')
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

  -- 5. Upsert profile
  INSERT INTO public.profiles (
    id, email, username, full_name, first_name, last_name, mi, suffix, role,
    phone, town, barangay, complete_address, landmark, station_name,
    avatar_url, latitude, longitude, primary_water_type
  )
  VALUES (
    new.id, new.email, v_username, v_full_name, v_first_name, v_last_name,
    new.raw_user_meta_data->>'mi', new.raw_user_meta_data->>'suffix', v_role,
    new.raw_user_meta_data->>'phone', v_town, new.raw_user_meta_data->>'barangay',
    v_complete_address, new.raw_user_meta_data->>'landmark',
    new.raw_user_meta_data->>'station_name', v_avatar_url,
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

-- 2. Protected trust columns -----------------------------------------------------
-- SECURITY INVOKER on purpose: current_user is 'authenticated'/'anon' for direct
-- client writes, and the function owner (postgres) inside SECURITY DEFINER
-- functions such as update_station_stats() and the admin RPCs.
CREATE OR REPLACE FUNCTION public.guard_profile_protected_columns()
RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;

  IF NEW.average_rating IS NOT DISTINCT FROM OLD.average_rating
    AND NEW.review_count IS NOT DISTINCT FROM OLD.review_count
    AND NEW.reliability_score IS NOT DISTINCT FROM OLD.reliability_score
    AND NEW.flagged_count IS NOT DISTINCT FROM OLD.flagged_count
    AND NEW.verification_status IS NOT DISTINCT FROM OLD.verification_status
  THEN
    RETURN NEW;
  END IF;

  IF public.is_admin() THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'Unauthorized: You cannot alter protected account fields.';
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_profile_protected_columns ON public.profiles;
CREATE TRIGGER trg_guard_profile_protected_columns
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.guard_profile_protected_columns();


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Delivery coverage: free-delivery zones + distance-based fees (2026-11-05)
-- ==============================================================================
-- Each station defines where delivery is free:
--   * within free_delivery_radius_km of the station (default 1 km), OR
--   * to any barangay listed in free_delivery_barangays, OR
--   * when the order has at least free_delivery_min_gallons water gallons.
-- Everywhere else pays the platform's per-km rate from
-- system_config.delivery_fee_config (rate_per_km, minimum_fee,
-- min_billable_distance_km, rounding_rule, enabled).
--
-- Distance = straight-line (haversine) x 1.3 road factor, so it approximates
-- real road distance without calling a routing service from the database.
--
-- Self-contained: does not depend on delivery_fee_config_rpcs.sql.
-- Run before: order_pricing_v3.sql. Test: supabase/tests/delivery_quote_test.sql
-- ==============================================================================

ALTER TABLE public.owner_settings
  ADD COLUMN IF NOT EXISTS free_delivery_radius_km numeric(4,1) NOT NULL DEFAULT 1.0,
  ADD COLUMN IF NOT EXISTS free_delivery_barangays text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS free_delivery_min_gallons integer;

ALTER TABLE public.owner_settings DROP CONSTRAINT IF EXISTS owner_settings_free_radius_check;
ALTER TABLE public.owner_settings ADD CONSTRAINT owner_settings_free_radius_check
  CHECK (free_delivery_radius_km >= 0 AND free_delivery_radius_km <= 10);
ALTER TABLE public.owner_settings DROP CONSTRAINT IF EXISTS owner_settings_free_min_gallons_check;
ALTER TABLE public.owner_settings ADD CONSTRAINT owner_settings_free_min_gallons_check
  CHECK (free_delivery_min_gallons IS NULL OR free_delivery_min_gallons BETWEEN 1 AND 100);

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS delivery_distance_km numeric(6,2),
  ADD COLUMN IF NOT EXISTS delivery_rate_per_km numeric(8,2),
  ADD COLUMN IF NOT EXISTS delivery_free_reason text;

-- Road factor applied to straight-line distance.
CREATE OR REPLACE FUNCTION public.delivery_road_distance_km(
  p_lat1 double precision, p_lng1 double precision,
  p_lat2 double precision, p_lng2 double precision
) RETURNS numeric
LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN p_lat1 IS NULL OR p_lng1 IS NULL OR p_lat2 IS NULL OR p_lng2 IS NULL THEN NULL
    ELSE round((
      2 * 6371 * asin(sqrt(
        power(sin(radians(p_lat2 - p_lat1) / 2), 2)
        + cos(radians(p_lat1)) * cos(radians(p_lat2))
          * power(sin(radians(p_lng2 - p_lng1) / 2), 2)
      )) * 1.3
    )::numeric, 2)
  END;
$$;

-- Fee for a distance outside the free zone, from the admin's config.
CREATE OR REPLACE FUNCTION public.delivery_fee_for_distance(p_km numeric)
RETURNS numeric
LANGUAGE plpgsql STABLE SET search_path TO 'public' AS $$
DECLARE
  v_cfg jsonb;
  v_rate numeric;
  v_min numeric;
  v_min_km numeric;
  v_rule text;
  v_fee numeric;
BEGIN
  SELECT value INTO v_cfg FROM public.system_config WHERE key = 'delivery_fee_config';
  v_cfg := coalesce(v_cfg, '{}'::jsonb);
  IF NOT coalesce((v_cfg->>'enabled')::boolean, true) THEN
    RETURN 0;
  END IF;
  v_rate := greatest(coalesce((v_cfg->>'rate_per_km')::numeric, 10), 0);
  v_min := greatest(coalesce((v_cfg->>'minimum_fee')::numeric, 20), 0);
  v_min_km := greatest(coalesce((v_cfg->>'min_billable_distance_km')::numeric, 1), 0);
  v_rule := lower(trim(coalesce(v_cfg->>'rounding_rule', 'exact')));

  IF p_km IS NULL THEN
    RETURN v_min;
  END IF;

  -- Same rule as CheckoutRules.calculateDeliveryFee in the app: the rounding
  -- rule applies to the billable distance; the fee is whole pesos.
  v_fee := greatest(p_km, v_min_km);
  v_fee := CASE
    WHEN v_rule IN ('ceil', 'round_up') THEN ceil(v_fee)
    WHEN v_rule IN ('round', 'round_nearest') THEN round(v_fee)
    ELSE v_fee
  END;
  IF v_rate <= 0 THEN
    RETURN 0;
  END IF;
  RETURN round(greatest(v_rate * v_fee, v_min));
END;
$$;

-- Quote shown at checkout and charged by create_order_atomic.
CREATE OR REPLACE FUNCTION public.compute_delivery_quote(
  p_station_id uuid,
  p_lat double precision,
  p_lng double precision,
  p_barangay text DEFAULT NULL,
  p_gallons integer DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_slat double precision;
  v_slng double precision;
  v_radius numeric;
  v_barangays text[];
  v_min_gallons integer;
  v_km numeric;
  v_reason text;
  v_cfg jsonb;
BEGIN
  SELECT coalesce(p.latitude, p.lat), coalesce(p.longitude, p.lng)
  INTO v_slat, v_slng
  FROM public.profiles p
  WHERE p.id = p_station_id AND p.role = 'owner';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Water refill station not found.';
  END IF;

  SELECT coalesce(os.free_delivery_radius_km, 1.0),
         coalesce(os.free_delivery_barangays, '{}'),
         os.free_delivery_min_gallons
  INTO v_radius, v_barangays, v_min_gallons
  FROM public.owner_settings os WHERE os.owner_id = p_station_id;
  v_radius := coalesce(v_radius, 1.0);
  v_barangays := coalesce(v_barangays, '{}');

  v_km := public.delivery_road_distance_km(v_slat, v_slng, p_lat, p_lng);

  IF v_km IS NOT NULL AND v_km <= v_radius THEN
    v_reason := 'radius';
  ELSIF p_barangay IS NOT NULL AND EXISTS (
    SELECT 1 FROM unnest(v_barangays) b
    WHERE lower(trim(b)) = lower(trim(p_barangay))
  ) THEN
    v_reason := 'barangay';
  ELSIF v_min_gallons IS NOT NULL AND coalesce(p_gallons, 0) >= v_min_gallons THEN
    v_reason := 'min_gallons';
  END IF;

  SELECT value INTO v_cfg FROM public.system_config WHERE key = 'delivery_fee_config';

  RETURN jsonb_build_object(
    'distance_km', v_km,
    'is_free', v_reason IS NOT NULL,
    'free_reason', v_reason,
    'fee', CASE WHEN v_reason IS NOT NULL THEN 0 ELSE public.delivery_fee_for_distance(v_km) END,
    'rate_per_km', coalesce((v_cfg->>'rate_per_km')::numeric, 10),
    'minimum_fee', coalesce((v_cfg->>'minimum_fee')::numeric, 20),
    'free_radius_km', v_radius,
    'free_barangays', to_jsonb(v_barangays),
    'free_min_gallons', v_min_gallons
  );
END;
$$;

REVOKE ALL ON FUNCTION public.compute_delivery_quote(uuid, double precision, double precision, text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.compute_delivery_quote(uuid, double precision, double precision, text, integer) TO authenticated;
REVOKE ALL ON FUNCTION public.delivery_fee_for_distance(numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delivery_fee_for_distance(numeric) TO authenticated;


NOTIFY pgrst, 'reload schema';
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


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Rider tips (2026-11-05)
-- ==============================================================================
-- Customers can add an optional tip (₱0–₱500, whole pesos) at checkout for
-- delivery orders. It is part of the single charge (COD or PayMongo), so no
-- second payment is needed, and 100% goes to the rider:
--   * excluded from the station SALE and from the 10% commission base
--   * booked as a RIDER_TIP ledger entry to the assigned rider
--   * if no rider was assigned (station delivered itself) it stays with the
--     station as part of the SALE
-- create_order_atomic reads p_order_data->>'tip_amount' (order_pricing_v3.sql).
--
-- Run before: order_pricing_v3.sql. Test: supabase/tests/rider_tips_test.sql
-- ==============================================================================

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS tip_amount numeric(10,2) NOT NULL DEFAULT 0;
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_tip_amount_check;
ALTER TABLE public.orders ADD CONSTRAINT orders_tip_amount_check
  CHECK (tip_amount >= 0 AND tip_amount <= 500);

CREATE OR REPLACE FUNCTION public.proc_finalize_order_finances()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    v_commission NUMERIC;
    v_fee NUMERIC := greatest(coalesce(NEW.platform_fee, 0), 0);
    v_tip NUMERIC := greatest(coalesce(NEW.tip_amount, 0), 0);
    v_rider_tip NUMERIC := 0;
BEGIN
    IF NEW.status = 'delivered' AND OLD.status != 'delivered' THEN
        -- The tip belongs to the rider; without a rider it stays in the sale.
        IF NEW.assigned_rider_id IS NOT NULL THEN
            v_rider_tip := v_tip;
        END IF;

        INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
        VALUES (NEW.owner_id, NEW.id, NEW.total_amount - v_fee - v_rider_tip, 'SALE', 'Order completion payment');

        IF v_fee > 0 THEN
            INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description, metadata)
            VALUES (
                NEW.owner_id, NEW.id, v_fee, 'SERVICE_FEE', 'Platform service fee',
                jsonb_build_object('payee', 'platform', 'payment_method', NEW.payment_method)
            );

            IF lower(coalesce(NEW.payment_method, 'cod')) IN ('cod', 'cash', 'credit') THEN
                PERFORM public.apply_wallet_entry(
                    NEW.owner_id, -v_fee, 'service_fee', NEW.id, NULL,
                    'Service fee for order ' || upper(substr(NEW.id::text, 1, 8))
                );
            END IF;
        END IF;

        -- Commission excludes the tip.
        v_commission := (NEW.total_amount - v_tip) * 0.10;

        IF NEW.assigned_rider_id IS NOT NULL THEN
            INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
            VALUES (NEW.assigned_rider_id, NEW.id, v_commission, 'COMMISSION', 'Delivery commission for order');

            IF v_rider_tip > 0 THEN
                INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
                VALUES (NEW.assigned_rider_id, NEW.id, v_rider_tip, 'RIDER_TIP', 'Customer tip');

                INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
                VALUES (
                    NEW.assigned_rider_id, 'system_alert', 'normal', 'You got a tip!',
                    'A customer tipped you PHP ' || trim(to_char(v_rider_tip, '999990')) || '. Thank you for the great service.',
                    jsonb_build_object('order_id', NEW.id, 'tip_amount', v_rider_tip)
                );
            END IF;
        END IF;

        INSERT INTO public.domain_events (event_type, payload, actor_id)
        VALUES ('ORDER_COMPLETED', jsonb_build_object(
            'order_id', NEW.id, 'total', NEW.total_amount,
            'rider_id', NEW.assigned_rider_id, 'tip', v_tip), auth.uid());
    END IF;
    RETURN NEW;
END;
$$;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Seller and customer ID verification (2026-11-05)
-- ==============================================================================
-- Users upload a government ID (front, back, selfie; owners also a business
-- permit) to the private bucket verification_docs under <their uid>/.
-- An admin reviews and approves or rejects. profiles.verification_status
-- (added and write-protected by harden_signup_and_protected_columns.sql) is
-- only changed by the RPCs below.
--
-- Gates (enforced in create_order_atomic, order_pricing_v3.sql):
--   * stations must be 'approved' to receive orders
--   * unverified customers: cash-on-delivery up to PHP 1,000 and at most
--     2 active COD orders; verified customers have no limit
-- Backfill: owners who already completed a delivery are approved (legacy).
--
-- Run after: harden_signup_and_protected_columns.sql
-- Run before: order_pricing_v3.sql. Test: supabase/tests/identity_verification_test.sql
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.identity_verifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role text NOT NULL,
  id_type text NOT NULL CHECK (id_type IN (
    'philsys', 'drivers_license', 'umid', 'passport', 'postal', 'voters', 'prc', 'other')),
  id_number_last4 text CHECK (id_number_last4 ~ '^[0-9A-Za-z]{4}$'),
  front_path text NOT NULL,
  back_path text,
  selfie_path text NOT NULL,
  business_permit_path text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  reviewer_id uuid REFERENCES public.profiles(id),
  reviewed_at timestamptz,
  rejection_reason text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_identity_verifications_user ON public.identity_verifications (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_identity_verifications_pending ON public.identity_verifications (created_at) WHERE status = 'pending';

ALTER TABLE public.identity_verifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users read own verifications" ON public.identity_verifications;
CREATE POLICY "Users read own verifications" ON public.identity_verifications
  FOR SELECT TO authenticated USING (auth.uid() = user_id OR public.is_admin());
-- Writes only through the RPCs below.
REVOKE INSERT, UPDATE, DELETE ON public.identity_verifications FROM anon, authenticated;
GRANT SELECT ON public.identity_verifications TO authenticated;

-- Private bucket, one folder per user.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('verification_docs', 'verification_docs', false, 8388608,
        ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
ON CONFLICT (id) DO UPDATE SET public = false;

DROP POLICY IF EXISTS "Verification docs: owner upload" ON storage.objects;
CREATE POLICY "Verification docs: owner upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'verification_docs' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "Verification docs: owner or admin read" ON storage.objects;
CREATE POLICY "Verification docs: owner or admin read" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'verification_docs'
         AND ((storage.foldername(name))[1] = auth.uid()::text OR public.is_admin()));

CREATE OR REPLACE FUNCTION public.submit_identity_verification(
  p_id_type text,
  p_id_number_last4 text,
  p_front_path text,
  p_back_path text,
  p_selfie_path text,
  p_business_permit_path text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_role text;
  v_status text;
  v_prefix text;
  v_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required.'; END IF;
  SELECT role::text, verification_status INTO v_role, v_status FROM public.profiles WHERE id = v_uid;
  IF v_role NOT IN ('customer', 'owner') THEN
    RAISE EXCEPTION 'Only customers and station owners verify their ID here.';
  END IF;
  IF v_status = 'approved' THEN RAISE EXCEPTION 'Your ID is already verified.'; END IF;
  IF v_status = 'pending' THEN RAISE EXCEPTION 'Your ID is already being reviewed.'; END IF;

  v_prefix := v_uid::text || '/';
  IF p_front_path IS NULL OR p_selfie_path IS NULL
     OR left(p_front_path, length(v_prefix)) <> v_prefix
     OR left(p_selfie_path, length(v_prefix)) <> v_prefix
     OR (p_back_path IS NOT NULL AND left(p_back_path, length(v_prefix)) <> v_prefix)
     OR (p_business_permit_path IS NOT NULL AND left(p_business_permit_path, length(v_prefix)) <> v_prefix) THEN
    RAISE EXCEPTION 'Upload your ID photos before submitting.';
  END IF;
  IF v_role = 'owner' AND p_business_permit_path IS NULL THEN
    RAISE EXCEPTION 'Stations must also upload a business or sanitary permit.';
  END IF;

  INSERT INTO public.identity_verifications (
    user_id, role, id_type, id_number_last4, front_path, back_path, selfie_path, business_permit_path)
  VALUES (v_uid, v_role, p_id_type, NULLIF(p_id_number_last4, ''), p_front_path, p_back_path,
          p_selfie_path, p_business_permit_path)
  RETURNING id INTO v_id;

  UPDATE public.profiles SET verification_status = 'pending' WHERE id = v_uid;
  RETURN jsonb_build_object('id', v_id, 'status', 'pending');
END; $$;

CREATE OR REPLACE FUNCTION public.admin_review_identity_verification(
  p_verification_id uuid,
  p_approve boolean,
  p_reason text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_row public.identity_verifications%ROWTYPE;
  v_status text := CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  IF NOT p_approve AND coalesce(trim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'Give the user a reason for the rejection.';
  END IF;

  UPDATE public.identity_verifications
  SET status = v_status, reviewer_id = auth.uid(), reviewed_at = now(),
      rejection_reason = CASE WHEN p_approve THEN NULL ELSE trim(p_reason) END
  WHERE id = p_verification_id AND status = 'pending'
  RETURNING * INTO v_row;
  IF NOT FOUND THEN RAISE EXCEPTION 'This verification was already reviewed.'; END IF;

  UPDATE public.profiles SET verification_status = v_status WHERE id = v_row.user_id;

  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (
    v_row.user_id, 'system_alert', 'high',
    CASE WHEN p_approve THEN 'Your ID is verified' ELSE 'ID verification needs another try' END,
    CASE WHEN p_approve
      THEN CASE WHEN v_row.role = 'owner'
        THEN 'Your station is verified and can now receive orders.'
        ELSE 'Your account is verified. Order limits are lifted.' END
      ELSE 'Reason: ' || trim(p_reason) || '. You can submit new photos.' END,
    jsonb_build_object('verification_id', v_row.id, 'status', v_status)
  );

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, new_value, metadata)
  VALUES (auth.uid(), 'identity_verification_' || v_status, 'identity_verifications', v_row.id::text,
          jsonb_build_object('status', v_status),
          jsonb_build_object('user_id', v_row.user_id, 'reason', p_reason));

  RETURN jsonb_build_object('id', v_row.id, 'status', v_status);
END; $$;

REVOKE ALL ON FUNCTION public.submit_identity_verification(text, text, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_identity_verification(text, text, text, text, text, text) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_review_identity_verification(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_review_identity_verification(uuid, boolean, text) TO authenticated;

-- Order gate helper, used by create_order_atomic.
CREATE OR REPLACE FUNCTION public.assert_order_allowed_by_verification(
  p_customer_id uuid, p_owner_id uuid, p_payment_method text, p_total numeric
) RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_owner_status text;
  v_customer_status text;
  v_active int;
BEGIN
  SELECT verification_status INTO v_owner_status FROM public.profiles WHERE id = p_owner_id;
  IF coalesce(v_owner_status, 'unverified') <> 'approved' THEN
    RAISE EXCEPTION 'This station is not verified yet and cannot take orders.';
  END IF;

  SELECT verification_status INTO v_customer_status FROM public.profiles WHERE id = p_customer_id;
  IF coalesce(v_customer_status, 'unverified') = 'approved'
     OR lower(coalesce(p_payment_method, 'cod')) NOT IN ('cod', 'cash') THEN
    RETURN;
  END IF;

  IF p_total > 1000 THEN
    RAISE EXCEPTION 'Verify your ID to place cash-on-delivery orders above PHP 1,000.';
  END IF;
  SELECT count(*) INTO v_active FROM public.orders
  WHERE customer_id = p_customer_id
    AND lower(coalesce(payment_method, 'cod')) IN ('cod', 'cash')
    AND status NOT IN ('delivered', 'cancelled', 'failed');
  IF v_active >= 2 THEN
    RAISE EXCEPTION 'Verify your ID to have more than 2 cash-on-delivery orders at a time.';
  END IF;
END; $$;
REVOKE ALL ON FUNCTION public.assert_order_allowed_by_verification(uuid, uuid, text, numeric) FROM PUBLIC, anon, authenticated;

-- Backfill: stations that already delivered orders keep working.
UPDATE public.profiles p SET verification_status = 'approved'
WHERE p.role = 'owner' AND p.verification_status = 'unverified'
  AND EXISTS (SELECT 1 FROM public.orders o WHERE o.owner_id = p.id AND o.status = 'delivered');


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- create_order_atomic v3 (2026-11-05)
-- ==============================================================================
-- Starts from the LIVE definition (pg_get_functiondef on 2026-11-05; note the
-- live function does not use price_order() from whole_peso_pricing.sql).
-- Changes:
--   * Delivery fee comes from compute_delivery_quote() (free zone or per-km),
--     never from the client and no longer from owner_settings.base_delivery_fee.
--   * Writes delivery_distance_km, delivery_rate_per_km, delivery_free_reason.
--   * Accessories (products.kind = 'accessory') are sold alongside water;
--     only water gallons count toward the free-delivery gallon threshold.
--   * Optional rider tip (tip_amount, ₱0–₱500) added to the total.
--   * ID verification gates: approved stations only; COD limits for
--     unverified customers.
-- This is the single place later features (accessories, tips, verification
-- gates) extend create_order_atomic. Do not redefine it in other scripts.
--
-- Run order: harden_signup_and_protected_columns.sql -> delivery_coverage.sql ->
--   station_accessories.sql -> rider_tips.sql -> identity_verification.sql -> this file.
-- Tests: supabase/tests/delivery_quote_test.sql, accessories_test.sql
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.create_order_atomic(p_order_data jsonb, p_items_data jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_customer_id uuid := auth.uid();
  v_owner_id uuid;
  v_payment_method text;
  v_idempotency_key public.orders.idempotency_key%TYPE;
  v_voucher_id uuid;
  v_order_id uuid;
  v_item record;
  v_product record;
  v_computed_subtotal numeric(10,2) := 0;
  v_delivery_fee numeric(10,2) := 0;
  v_platform_fee numeric(10,2) := 0;
  v_discount numeric(10,2) := 0;
  v_total_amount numeric(10,2) := 0;
  v_order_row public.orders%ROWTYPE;
  v_voucher public.customer_reward_vouchers%ROWTYPE;
  v_config jsonb;
  v_lat double precision;
  v_lng double precision;
  v_maintenance jsonb;
  v_is_maintenance boolean := false;
  v_customer_suspended boolean := false;
  v_owner_suspended boolean := false;
  v_gallons integer := 0;
  v_quote jsonb;
  v_tip numeric(10,2) := 0;
BEGIN
  SELECT value INTO v_maintenance
  FROM public.system_config
  WHERE key = 'maintenance_mode';

  IF v_maintenance IS NOT NULL THEN
    IF jsonb_typeof(v_maintenance) = 'boolean' THEN
      v_is_maintenance := v_maintenance::text::boolean;
    ELSIF jsonb_typeof(v_maintenance) = 'string' THEN
      v_is_maintenance :=
        lower(trim(both '"' from v_maintenance::text)) IN ('true', '1', 'yes');
    END IF;
  END IF;

  IF v_is_maintenance THEN
    RAISE EXCEPTION 'System is currently undergoing maintenance. New orders are temporarily paused.';
  END IF;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required to place an order.';
  END IF;

  SELECT coalesce(is_suspended, false) INTO v_customer_suspended
  FROM public.profiles
  WHERE id = v_customer_id AND role = 'customer';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Only customer accounts can place orders.';
  END IF;
  IF v_customer_suspended THEN
    RAISE EXCEPTION 'Your account has been suspended. Please contact customer support.';
  END IF;

  v_idempotency_key := NULLIF(p_order_data->>'idempotency_key', '');
  IF v_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_order_row
    FROM public.orders
    WHERE customer_id = v_customer_id
      AND idempotency_key = v_idempotency_key;

    IF FOUND THEN
      RETURN jsonb_build_object(
        'id', v_order_row.id,
        'subtotal', v_order_row.subtotal,
        'delivery_fee', v_order_row.delivery_fee,
        'platform_fee', v_order_row.platform_fee,
        'total_amount', v_order_row.total_amount,
        'status', v_order_row.status
      );
    END IF;
  END IF;

  v_owner_id := NULLIF(p_order_data->>'owner_id', '')::uuid;
  v_payment_method := lower(trim(coalesce(p_order_data->>'payment_method', 'cod')));
  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'Station owner ID is required.';
  END IF;

  SELECT coalesce(is_suspended, false) INTO v_owner_suspended
  FROM public.profiles
  WHERE id = v_owner_id AND role = 'owner';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Water refill station not found.';
  END IF;
  IF v_owner_suspended THEN
    RAISE EXCEPTION 'This water station is currently suspended by administration.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = v_owner_id
      AND role = 'owner'
      AND coalesce(station_availability, 'open') = 'open'
  ) THEN
    RAISE EXCEPTION 'This water station is currently closed or unavailable.';
  END IF;
  IF NOT public.is_station_payment_method_available(v_owner_id, v_payment_method) THEN
    RAISE EXCEPTION 'This payment method is not available for this station.';
  END IF;

  FOR v_item IN
    SELECT * FROM jsonb_to_recordset(p_items_data) AS x(
      product_id uuid,
      quantity integer,
      product_name text
    )
  LOOP
    IF v_item.quantity <= 0 THEN
      RAISE EXCEPTION 'Invalid quantity for item %', v_item.product_name;
    END IF;

    SELECT * INTO v_product
    FROM public.products
    WHERE id = v_item.product_id
      AND owner_id = v_owner_id
      AND is_available = true;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Product % is unavailable at this station.', v_item.product_name;
    END IF;

    v_computed_subtotal :=
      v_computed_subtotal + (v_product.price * v_item.quantity);
    -- Only water counts toward the free-delivery gallon threshold.
    IF v_product.kind = 'water' THEN
      v_gallons := v_gallons + v_item.quantity;
    END IF;
  END LOOP;

  IF v_computed_subtotal <= 0 THEN
    RAISE EXCEPTION 'Cart cannot be empty.';
  END IF;

  v_lat := NULLIF(p_order_data->>'customer_latitude', '')::double precision;
  v_lng := NULLIF(p_order_data->>'customer_longitude', '')::double precision;

  -- Delivery fee: server-side quote (free zone or per-km). Client fee ignored.
  v_quote := public.compute_delivery_quote(
    v_owner_id, v_lat, v_lng,
    NULLIF(p_order_data->>'customer_barangay', ''),
    v_gallons
  );
  v_delivery_fee := coalesce((v_quote->>'fee')::numeric, 0);

  v_config := public.get_platform_fee_config();
  IF coalesce((v_config->>'enabled')::boolean, false) THEN
    v_platform_fee := round(
      ((v_computed_subtotal + v_delivery_fee)
        * coalesce((v_config->>'percent')::numeric, 0) / 100)
        + coalesce((v_config->>'fixed')::numeric, 0),
      2
    );
    v_platform_fee := greatest(v_platform_fee, 0);
  END IF;

  v_voucher_id := NULLIF(p_order_data->>'voucher_id', '')::uuid;
  IF v_voucher_id IS NOT NULL THEN
    SELECT * INTO v_voucher
    FROM public.customer_reward_vouchers
    WHERE id = v_voucher_id
      AND user_id = v_customer_id
      AND is_used = false
      AND expires_at > now()
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'This reward voucher is no longer available. Refresh your vouchers and try again.';
    END IF;

    IF v_voucher.is_delivery_discount THEN
      v_discount := least(
        greatest(v_voucher.discount_amount, 0),
        v_delivery_fee
      );
    ELSE
      v_discount := least(
        greatest(v_voucher.discount_amount, 0),
        v_computed_subtotal + v_delivery_fee + v_platform_fee
      );
    END IF;
  END IF;

  -- Optional rider tip: whole pesos, ₱0–₱500, paid on top (no fees, no voucher).
  v_tip := round(coalesce(NULLIF(p_order_data->>'tip_amount', '')::numeric, 0));
  IF v_tip < 0 OR v_tip > 500 THEN
    RAISE EXCEPTION 'Tip must be between PHP 0 and PHP 500.';
  END IF;

  v_total_amount := greatest(
    v_computed_subtotal + v_delivery_fee + v_platform_fee - v_discount,
    0
  ) + v_tip;

  -- ID verification gates (identity_verification.sql).
  PERFORM public.assert_order_allowed_by_verification(
    v_customer_id, v_owner_id, v_payment_method, v_total_amount
  );

  INSERT INTO public.orders (
    id,
    customer_id,
    owner_id,
    station_name,
    customer_name,
    customer_phone,
    customer_address,
    customer_barangay,
    customer_municipality,
    customer_landmark,
    idempotency_key,
    subtotal,
    delivery_fee,
    platform_fee,
    total_amount,
    payment_method,
    payment_status,
    notes,
    region_id,
    customer_latitude,
    customer_longitude,
    delivery_lat,
    delivery_lng,
    delivery_latitude,
    delivery_longitude,
    delivery_distance_km,
    delivery_rate_per_km,
    delivery_free_reason,
    tip_amount,
    items,
    status
  ) VALUES (
    coalesce(
      NULLIF(p_order_data->>'id', '')::uuid,
      gen_random_uuid()
    ),
    v_customer_id,
    v_owner_id,
    coalesce(p_order_data->>'station_name', 'Water Station'),
    p_order_data->>'customer_name',
    p_order_data->>'customer_phone',
    p_order_data->>'customer_address',
    p_order_data->>'customer_barangay',
    p_order_data->>'customer_municipality',
    p_order_data->>'customer_landmark',
    v_idempotency_key,
    v_computed_subtotal,
    v_delivery_fee,
    v_platform_fee,
    v_total_amount,
    v_payment_method,
    'pending',
    p_order_data->>'notes',
    NULLIF(p_order_data->>'region_id', '')::uuid,
    v_lat,
    v_lng,
    v_lat,
    v_lng,
    v_lat,
    v_lng,
    (v_quote->>'distance_km')::numeric,
    (v_quote->>'rate_per_km')::numeric,
    v_quote->>'free_reason',
    v_tip,
    coalesce(p_items_data, '[]'::jsonb),
    'pending'
  )
  ON CONFLICT DO NOTHING
  RETURNING * INTO v_order_row;

  IF NOT FOUND THEN
    IF v_idempotency_key IS NOT NULL THEN
      SELECT * INTO v_order_row
      FROM public.orders
      WHERE customer_id = v_customer_id
        AND idempotency_key = v_idempotency_key;

      IF FOUND THEN
        RETURN jsonb_build_object(
          'id', v_order_row.id,
          'subtotal', v_order_row.subtotal,
          'delivery_fee', v_order_row.delivery_fee,
          'platform_fee', v_order_row.platform_fee,
          'total_amount', v_order_row.total_amount,
          'status', v_order_row.status
        );
      END IF;
    END IF;
    RAISE EXCEPTION 'Order could not be created because of a conflicting order record.';
  END IF;

  v_order_id := v_order_row.id;

  FOR v_item IN
    SELECT * FROM jsonb_to_recordset(p_items_data) AS x(
      product_id uuid,
      quantity integer,
      product_name text
    )
  LOOP
    SELECT * INTO v_product FROM public.products WHERE id = v_item.product_id;
    INSERT INTO public.order_items (
      order_id,
      product_id,
      product_name,
      quantity,
      price_at_purchase,
      subtotal
    ) VALUES (
      v_order_id,
      v_item.product_id,
      v_product.name,
      v_item.quantity,
      v_product.price,
      (v_product.price * v_item.quantity)
    );
  END LOOP;

  IF v_voucher_id IS NOT NULL THEN
    UPDATE public.customer_reward_vouchers
    SET is_used = true
    WHERE id = v_voucher_id
      AND user_id = v_customer_id
      AND is_used = false;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'This reward voucher was already used by another order.';
    END IF;
  END IF;

  INSERT INTO public.system_notifications (
    user_id,
    type,
    priority,
    title,
    content,
    metadata
  ) VALUES (
    v_owner_id,
    'system_alert',
    'high',
    'New Refill Order',
    coalesce(p_order_data->>'customer_name', 'A customer')
      || ' placed a new refill order of PHP '
      || trim(to_char(v_total_amount, '999999990.00'))
      || ' (' || upper(coalesce(p_order_data->>'payment_method', 'cod')) || ').',
    jsonb_build_object(
      'order_id', v_order_id,
      'status', 'pending',
      'total_amount', v_total_amount
    )
  );

  RETURN jsonb_build_object(
    'id', v_order_id,
    'subtotal', v_computed_subtotal,
    'delivery_fee', v_delivery_fee,
    'delivery_distance_km', (v_quote->>'distance_km')::numeric,
    'delivery_free_reason', v_quote->>'free_reason',
    'platform_fee', v_platform_fee,
    'discount_amount', v_discount,
    'tip_amount', v_tip,
    'total_amount', v_total_amount,
    'status', 'pending'
  );
END;
$function$;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Rider live location privacy (2026-11-05)
-- ==============================================================================
-- rider_locations was readable by everyone ("Public can view rider
-- locations"). Now only these can read a rider's points:
--   * the rider, admins
--   * the customer or station of an order that rider is delivering right now
--     (assigned_to_rider / out_for_delivery)
-- After delivery the customer loses access. Points older than 24 h are purged
-- hourly (pg_cron, when the extension is available).
-- Test: supabase/tests/rider_live_location_test.sql
-- ==============================================================================

DROP POLICY IF EXISTS "Public can view rider locations" ON public.rider_locations;
DROP POLICY IF EXISTS "Rider location visible to active delivery parties" ON public.rider_locations;
CREATE POLICY "Rider location visible to active delivery parties" ON public.rider_locations
  FOR SELECT TO authenticated
  USING (
    rider_id = auth.uid()
    OR public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.orders o
      WHERE (o.assigned_rider_id = rider_locations.rider_id OR o.rider_id = rider_locations.rider_id)
        AND o.status IN ('assigned_to_rider', 'out_for_delivery')
        AND (o.customer_id = auth.uid() OR o.owner_id = auth.uid())
    )
  );

DROP POLICY IF EXISTS "Riders can update their own location" ON public.rider_locations;
CREATE POLICY "Riders can update their own location" ON public.rider_locations
  FOR INSERT TO authenticated
  WITH CHECK (rider_id = auth.uid());
REVOKE ALL ON public.rider_locations FROM anon;

CREATE OR REPLACE FUNCTION public.purge_old_rider_locations()
RETURNS integer
LANGUAGE sql SECURITY DEFINER SET search_path TO 'public' AS $$
  WITH d AS (
    DELETE FROM public.rider_locations WHERE "timestamp" < now() - interval '24 hours' RETURNING 1
  ) SELECT count(*)::int FROM d;
$$;
REVOKE ALL ON FUNCTION public.purge_old_rider_locations() FROM PUBLIC, anon, authenticated;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'purge_old_rider_locations';
    PERFORM cron.schedule('purge_old_rider_locations', '7 * * * *', 'SELECT public.purge_old_rider_locations()');
  END IF;
END $$;

-- ==============================================================================
-- Smart refill reminders (2026-11-05)
-- ==============================================================================
-- Learns each customer's refill rhythm (median days between their last
-- delivered orders, needs >= 3 orders) and reminds them a day before they
-- usually reorder. At most one reminder per 3 days, never while an order is
-- active, and only when profiles.refill_reminders_enabled.
--   * customer_refill_rhythm()  -> for the app's home banner (current user)
--   * send_refill_reminders()   -> daily 9:00 PH pg_cron job, inserts notifications
-- Test: supabase/tests/refill_reminders_test.sql
-- ==============================================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS refill_reminders_enabled boolean NOT NULL DEFAULT true;

CREATE OR REPLACE FUNCTION public.refill_rhythm_for(p_customer_id uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  WITH recent AS (
    SELECT created_at, owner_id, station_name
    FROM public.orders
    WHERE customer_id = p_customer_id AND status = 'delivered'
    ORDER BY created_at DESC
    LIMIT 6
  ), gaps AS (
    SELECT extract(epoch FROM (created_at - lead(created_at) OVER (ORDER BY created_at DESC))) / 86400.0 AS days
    FROM recent
  ), stats AS (
    SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY days) AS median_days,
           count(*) AS gap_count
    FROM gaps WHERE days IS NOT NULL AND days > 0.5
  ), last AS (
    SELECT * FROM recent ORDER BY created_at DESC LIMIT 1
  )
  SELECT CASE
    WHEN (SELECT gap_count FROM stats) < 2 THEN jsonb_build_object('has_rhythm', false)
    ELSE jsonb_build_object(
      'has_rhythm', true,
      'median_days', round((SELECT median_days FROM stats)::numeric, 1),
      'last_order_at', (SELECT created_at FROM last),
      'station_id', (SELECT owner_id FROM last),
      'station_name', (SELECT station_name FROM last),
      'due_at', (SELECT created_at FROM last)
                + make_interval(secs => greatest((SELECT median_days FROM stats) - 1, 1) * 86400),
      'is_due', now() >= (SELECT created_at FROM last)
                + make_interval(secs => greatest((SELECT median_days FROM stats) - 1, 1) * 86400),
      'has_active_order', EXISTS (
        SELECT 1 FROM public.orders
        WHERE customer_id = p_customer_id
          AND status NOT IN ('delivered', 'cancelled', 'failed'))
    )
  END;
$$;
REVOKE ALL ON FUNCTION public.refill_rhythm_for(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.customer_refill_rhythm()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT CASE WHEN auth.uid() IS NULL THEN '{"has_rhythm": false}'::jsonb
              ELSE public.refill_rhythm_for(auth.uid()) END;
$$;
REVOKE ALL ON FUNCTION public.customer_refill_rhythm() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.customer_refill_rhythm() TO authenticated;

CREATE OR REPLACE FUNCTION public.send_refill_reminders()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_row record;
  v_r jsonb;
  v_sent integer := 0;
BEGIN
  FOR v_row IN
    SELECT p.id FROM public.profiles p
    WHERE p.role = 'customer' AND p.refill_reminders_enabled AND NOT coalesce(p.is_suspended, false)
  LOOP
    v_r := public.refill_rhythm_for(v_row.id);
    CONTINUE WHEN NOT coalesce((v_r->>'has_rhythm')::boolean, false)
               OR NOT (v_r->>'is_due')::boolean
               OR (v_r->>'has_active_order')::boolean;
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM public.system_notifications n
      WHERE n.user_id = v_row.id
        AND n.metadata->>'kind' = 'refill_reminder'
        AND n.created_at > now() - interval '3 days');

    INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
    VALUES (
      v_row.id, 'system_alert', 'normal', 'Time for a refill?',
      'You usually reorder every ' || round((v_r->>'median_days')::numeric) || ' days. '
        || 'Tap to reorder from ' || coalesce(v_r->>'station_name', 'your station') || '.',
      jsonb_build_object('kind', 'refill_reminder', 'station_id', v_r->>'station_id')
    );
    v_sent := v_sent + 1;
  END LOOP;
  RETURN v_sent;
END; $$;
REVOKE ALL ON FUNCTION public.send_refill_reminders() FROM PUBLIC, anon, authenticated;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'send_refill_reminders';
    -- 9:00 Asia/Manila = 01:00 UTC, so reminders arrive in the morning.
    PERFORM cron.schedule('send_refill_reminders', '0 1 * * *', 'SELECT public.send_refill_reminders()');
  END IF;
END $$;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Water quality transparency (2026-11-05)
-- ==============================================================================
-- Stations upload lab test results and permits (bacteriological /
-- physical-chemical water analysis, sanitary permit, business permit) with
-- issue and expiry dates. Admins approve them; approved, unexpired lab tests
-- give the station a "Water tested" badge and a small ranking boost.
-- Files live in the private verification_docs bucket under <uid>/certs/.
-- Approved certificate files are viewable by any signed-in user.
-- Daily job: marks expired certificates and warns owners 14 days ahead.
--
-- Run after: identity_verification.sql (bucket). Test: supabase/tests/water_quality_certs_test.sql
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.station_certifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  cert_type text NOT NULL CHECK (cert_type IN (
    'bacteriological', 'physical_chemical', 'sanitary_permit', 'business_permit')),
  issued_on date NOT NULL,
  expires_on date NOT NULL,
  file_path text NOT NULL,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected', 'expired')),
  reviewer_id uuid REFERENCES public.profiles(id),
  reviewed_at timestamptz,
  rejection_reason text,
  expiry_warned_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (expires_on > issued_on)
);
CREATE INDEX IF NOT EXISTS idx_station_certs_owner ON public.station_certifications (owner_id, status);

ALTER TABLE public.station_certifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Approved certs are public, owners see their own" ON public.station_certifications;
CREATE POLICY "Approved certs are public, owners see their own" ON public.station_certifications
  FOR SELECT TO authenticated
  USING (status = 'approved' OR owner_id = auth.uid() OR public.is_admin());
REVOKE INSERT, UPDATE, DELETE ON public.station_certifications FROM anon, authenticated;
GRANT SELECT ON public.station_certifications TO authenticated;

-- Approved certificate files are readable by signed-in users.
DROP POLICY IF EXISTS "Verification docs: approved certs readable" ON storage.objects;
CREATE POLICY "Verification docs: approved certs readable" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'verification_docs' AND EXISTS (
    SELECT 1 FROM public.station_certifications c
    WHERE c.file_path = storage.objects.name AND c.status = 'approved'));

CREATE OR REPLACE FUNCTION public.submit_station_certification(
  p_cert_type text, p_issued_on date, p_expires_on date, p_file_path text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_uid AND role = 'owner') THEN
    RAISE EXCEPTION 'Only station owners upload certificates.';
  END IF;
  IF p_file_path IS NULL OR left(p_file_path, length(v_uid::text) + 7) <> v_uid::text || '/certs/' THEN
    RAISE EXCEPTION 'Upload the certificate file first.';
  END IF;
  IF p_expires_on <= current_date THEN
    RAISE EXCEPTION 'This certificate has already expired.';
  END IF;
  IF p_issued_on > current_date THEN
    RAISE EXCEPTION 'The issue date cannot be in the future.';
  END IF;
  INSERT INTO public.station_certifications (owner_id, cert_type, issued_on, expires_on, file_path)
  VALUES (v_uid, p_cert_type, p_issued_on, p_expires_on, p_file_path)
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('id', v_id, 'status', 'pending');
END; $$;

CREATE OR REPLACE FUNCTION public.admin_review_station_certification(
  p_cert_id uuid, p_approve boolean, p_reason text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_row public.station_certifications%ROWTYPE;
  v_status text := CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  IF NOT p_approve AND coalesce(trim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'Give the station a reason for the rejection.';
  END IF;
  UPDATE public.station_certifications
  SET status = v_status, reviewer_id = auth.uid(), reviewed_at = now(),
      rejection_reason = CASE WHEN p_approve THEN NULL ELSE trim(p_reason) END
  WHERE id = p_cert_id AND status = 'pending'
  RETURNING * INTO v_row;
  IF NOT FOUND THEN RAISE EXCEPTION 'This certificate was already reviewed.'; END IF;

  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (v_row.owner_id, 'system_alert', 'normal',
    CASE WHEN p_approve THEN 'Certificate approved' ELSE 'Certificate rejected' END,
    CASE WHEN p_approve THEN 'Customers can now see your certificate.'
         ELSE 'Reason: ' || trim(p_reason) END,
    jsonb_build_object('certificate_id', v_row.id, 'status', v_status));
  RETURN jsonb_build_object('id', v_row.id, 'status', v_status);
END; $$;

REVOKE ALL ON FUNCTION public.submit_station_certification(text, date, date, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_station_certification(text, date, date, text) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_review_station_certification(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_review_station_certification(uuid, boolean, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.expire_station_certifications()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_n integer;
BEGIN
  UPDATE public.station_certifications SET status = 'expired'
  WHERE status = 'approved' AND expires_on <= current_date;
  GET DIAGNOSTICS v_n = ROW_COUNT;

  WITH soon AS (
    UPDATE public.station_certifications SET expiry_warned_at = now()
    WHERE status = 'approved' AND expiry_warned_at IS NULL
      AND expires_on <= current_date + 14
    RETURNING owner_id, id, cert_type, expires_on
  )
  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  SELECT owner_id, 'system_alert', 'high', 'Certificate expiring soon',
         'Your ' || replace(cert_type, '_', ' ') || ' certificate expires on '
           || to_char(expires_on, 'Mon DD, YYYY') || '. Upload a new one to keep your badge.',
         jsonb_build_object('certificate_id', id)
  FROM soon;
  RETURN v_n;
END; $$;
REVOKE ALL ON FUNCTION public.expire_station_certifications() FROM PUBLIC, anon, authenticated;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'expire_station_certifications';
    PERFORM cron.schedule('expire_station_certifications', '15 16 * * *', 'SELECT public.expire_station_certifications()');
  END IF;
END $$;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Order disputes and refunds (2026-11-05)
-- ==============================================================================
-- Extends the existing public.disputes table (status enum: open,
-- investigating, resolved, dismissed) with the customer -> station -> admin
-- flow:
--   1. Customer opens a dispute within 48 h of delivery, one per order,
--      with optional photo evidence (private bucket dispute_evidence).
--   2. Station accepts (refund amount) -> resolved, or explains -> the
--      dispute is escalated ('investigating') for an admin.
--   3. Customer may escalate if the station has not answered in 24 h.
--   4. Admin resolves with an optional refund, or dismisses.
-- A granted refund books a REFUND ledger entry against the station, notifies
-- the customer, and refunds against the station increase flagged_count.
-- Money movement: COD refunds are returned by the station in cash; online
-- payments are refunded by the admin in PayMongo (orders.payment_status is
-- set to 'refunded' when the full total is refunded).
--
-- Test: supabase/tests/order_disputes_test.sql
-- ==============================================================================

ALTER TABLE public.disputes
  ADD COLUMN IF NOT EXISTS evidence_paths text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS owner_response text,
  ADD COLUMN IF NOT EXISTS owner_responded_at timestamptz,
  ADD COLUMN IF NOT EXISTS refund_amount numeric(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS escalated_at timestamptz;
ALTER TABLE public.disputes DROP CONSTRAINT IF EXISTS disputes_reason_check;
ALTER TABLE public.disputes ADD CONSTRAINT disputes_reason_check CHECK (reason IN (
  'missing_items', 'wrong_item', 'quality', 'damaged', 'not_delivered', 'overcharged', 'other'));
ALTER TABLE public.disputes DROP CONSTRAINT IF EXISTS disputes_refund_check;
ALTER TABLE public.disputes ADD CONSTRAINT disputes_refund_check CHECK (refund_amount >= 0);
CREATE UNIQUE INDEX IF NOT EXISTS disputes_one_per_order ON public.disputes (order_id);

-- Owners no longer update disputes directly; they use owner_respond_dispute.
DROP POLICY IF EXISTS "Owners can update disputes for their station" ON public.disputes;
REVOKE INSERT, DELETE ON public.disputes FROM anon, authenticated;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('dispute_evidence', 'dispute_evidence', false, 8388608,
        ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO UPDATE SET public = false;
DROP POLICY IF EXISTS "Dispute evidence: reporter upload" ON storage.objects;
CREATE POLICY "Dispute evidence: reporter upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'dispute_evidence' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "Dispute evidence: parties read" ON storage.objects;
CREATE POLICY "Dispute evidence: parties read" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'dispute_evidence' AND (
    (storage.foldername(name))[1] = auth.uid()::text
    OR public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.disputes d JOIN public.orders o ON o.id = d.order_id
      WHERE storage.objects.name = ANY (d.evidence_paths) AND o.owner_id = auth.uid())));

CREATE OR REPLACE FUNCTION public.open_dispute(
  p_order_id uuid, p_reason text, p_description text, p_evidence_paths text[] DEFAULT '{}'
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_order public.orders%ROWTYPE;
  v_done_at timestamptz;
  v_id uuid;
  v_path text;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id AND customer_id = v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order not found.'; END IF;
  IF v_order.status::text <> 'delivered' THEN
    RAISE EXCEPTION 'You can report a problem once the order is delivered.';
  END IF;
  v_done_at := coalesce(v_order.actual_completion_at, v_order.updated_at, v_order.created_at);
  IF v_done_at < now() - interval '48 hours' THEN
    RAISE EXCEPTION 'Problems must be reported within 48 hours of delivery.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.disputes WHERE order_id = p_order_id) THEN
    RAISE EXCEPTION 'A problem was already reported for this order.';
  END IF;
  IF coalesce(trim(p_description), '') = '' THEN
    RAISE EXCEPTION 'Tell the station what went wrong.';
  END IF;
  FOREACH v_path IN ARRAY coalesce(p_evidence_paths, '{}') LOOP
    IF left(v_path, length(v_uid::text) + 1) <> v_uid::text || '/' THEN
      RAISE EXCEPTION 'Invalid evidence photo.';
    END IF;
  END LOOP;

  INSERT INTO public.disputes (order_id, reporter_id, reason, description, status, evidence_paths)
  VALUES (p_order_id, v_uid, p_reason, trim(p_description), 'open', coalesce(p_evidence_paths, '{}'))
  RETURNING id INTO v_id;

  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (v_order.owner_id, 'system_alert', 'high', 'A customer reported a problem',
    'Order #' || upper(substr(p_order_id::text, 1, 8)) || ': ' || replace(p_reason, '_', ' ')
      || '. Please respond within 24 hours.',
    jsonb_build_object('dispute_id', v_id, 'order_id', p_order_id));
  RETURN jsonb_build_object('id', v_id, 'status', 'open');
END; $$;

-- Shared by station and admin resolutions.
CREATE OR REPLACE FUNCTION public.apply_dispute_refund(p_dispute_id uuid, p_amount numeric, p_note text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_d public.disputes%ROWTYPE;
  v_o public.orders%ROWTYPE;
BEGIN
  SELECT * INTO v_d FROM public.disputes WHERE id = p_dispute_id;
  SELECT * INTO v_o FROM public.orders WHERE id = v_d.order_id;
  IF p_amount < 0 OR p_amount > v_o.total_amount THEN
    RAISE EXCEPTION 'Refund must be between PHP 0 and the order total.';
  END IF;
  UPDATE public.disputes SET refund_amount = p_amount, status = 'resolved',
         resolution_notes = p_note, updated_at = now()
  WHERE id = p_dispute_id;
  IF p_amount > 0 THEN
    INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
    VALUES (v_o.owner_id, v_o.id, -p_amount, 'REFUND', 'Refund for reported problem');
    UPDATE public.profiles SET flagged_count = coalesce(flagged_count, 0) + 1 WHERE id = v_o.owner_id;
    IF p_amount >= v_o.total_amount THEN
      UPDATE public.orders SET payment_status = 'refunded' WHERE id = v_o.id;
    END IF;
  END IF;
  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (v_d.reporter_id, 'system_alert', 'high',
    CASE WHEN p_amount > 0 THEN 'Refund approved' ELSE 'Your report was reviewed' END,
    CASE WHEN p_amount > 0
      THEN 'PHP ' || trim(to_char(p_amount, '999990.00')) || ' will be returned '
        || CASE WHEN lower(coalesce(v_o.payment_method, 'cod')) IN ('cod', 'cash')
                THEN 'by the station in cash.' ELSE 'to your original payment method.' END
      ELSE coalesce(p_note, 'No refund was given.') END,
    jsonb_build_object('dispute_id', p_dispute_id, 'order_id', v_o.id, 'refund_amount', p_amount));
END; $$;
REVOKE ALL ON FUNCTION public.apply_dispute_refund(uuid, numeric, text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.owner_respond_dispute(
  p_dispute_id uuid, p_accept boolean, p_response text, p_refund_amount numeric DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_d public.disputes%ROWTYPE;
BEGIN
  SELECT d.* INTO v_d FROM public.disputes d JOIN public.orders o ON o.id = d.order_id
  WHERE d.id = p_dispute_id AND o.owner_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Dispute not found.'; END IF;
  IF v_d.status::text <> 'open' OR v_d.owner_responded_at IS NOT NULL THEN
    RAISE EXCEPTION 'This dispute was already answered.';
  END IF;
  IF coalesce(trim(p_response), '') = '' THEN RAISE EXCEPTION 'Write a reply to the customer.'; END IF;

  UPDATE public.disputes SET owner_response = trim(p_response), owner_responded_at = now(), updated_at = now()
  WHERE id = p_dispute_id;

  IF p_accept THEN
    PERFORM public.apply_dispute_refund(p_dispute_id, coalesce(p_refund_amount, 0), 'Station: ' || trim(p_response));
    RETURN jsonb_build_object('status', 'resolved');
  END IF;

  UPDATE public.disputes SET status = 'investigating', escalated_at = now() WHERE id = p_dispute_id;
  RETURN jsonb_build_object('status', 'investigating');
END; $$;

CREATE OR REPLACE FUNCTION public.escalate_dispute(p_dispute_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  UPDATE public.disputes SET status = 'investigating', escalated_at = now(), updated_at = now()
  WHERE id = p_dispute_id AND reporter_id = auth.uid() AND status = 'open'
    AND owner_responded_at IS NULL AND created_at < now() - interval '24 hours';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'You can ask eRefill to step in 24 hours after reporting if the station has not replied.';
  END IF;
  RETURN jsonb_build_object('status', 'investigating');
END; $$;

CREATE OR REPLACE FUNCTION public.admin_resolve_dispute(
  p_dispute_id uuid, p_refund_amount numeric, p_notes text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.disputes WHERE id = p_dispute_id AND status IN ('open', 'investigating')) THEN
    RAISE EXCEPTION 'This dispute is already closed.';
  END IF;
  UPDATE public.disputes SET resolved_by = auth.uid() WHERE id = p_dispute_id;
  PERFORM public.apply_dispute_refund(p_dispute_id, coalesce(p_refund_amount, 0), p_notes);
  IF coalesce(p_refund_amount, 0) = 0 THEN
    UPDATE public.disputes SET status = 'dismissed' WHERE id = p_dispute_id;
  END IF;
  RETURN jsonb_build_object('status', CASE WHEN coalesce(p_refund_amount, 0) > 0 THEN 'resolved' ELSE 'dismissed' END);
END; $$;

REVOKE ALL ON FUNCTION public.open_dispute(uuid, text, text, text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.open_dispute(uuid, text, text, text[]) TO authenticated;
REVOKE ALL ON FUNCTION public.owner_respond_dispute(uuid, boolean, text, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.owner_respond_dispute(uuid, boolean, text, numeric) TO authenticated;
REVOKE ALL ON FUNCTION public.escalate_dispute(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.escalate_dispute(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_resolve_dispute(uuid, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_resolve_dispute(uuid, numeric, text) TO authenticated;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- AI ordering assistant: per-user daily message limit (2026-11-05)
-- ==============================================================================
-- The order-assistant Edge Function records one row per message (with the
-- service role) and refuses more than 20 per user in 24 hours.
-- Users can read their own usage; nobody writes from the app.
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.assistant_usage (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  input_tokens integer NOT NULL DEFAULT 0,
  output_tokens integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_assistant_usage_user_time ON public.assistant_usage (user_id, created_at DESC);

ALTER TABLE public.assistant_usage ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users read own assistant usage" ON public.assistant_usage;
CREATE POLICY "Users read own assistant usage" ON public.assistant_usage
  FOR SELECT TO authenticated USING (user_id = auth.uid());
REVOKE INSERT, UPDATE, DELETE ON public.assistant_usage FROM anon, authenticated;
GRANT SELECT ON public.assistant_usage TO authenticated;

-- Shared fixtures for the SQL tests in this folder. Every test runs as
--   BEGIN; <scripts under test, BEGIN/COMMIT stripped>; _fixtures.sql; <test>; ROLLBACK;
-- through the Supabase MCP execute_sql tool, so nothing persists.
--
-- Fixture rows are inserted with triggers off (replica role) to skip station
-- setup checks; triggers are back on before the test body runs.
--
-- ids: owner ...a1, second owner ...a2, customer ...c1, rider ...d1,
--      admin ...e1, product ...b1 (₱19.60, owner a1).

SET LOCAL session_replication_role = replica;

INSERT INTO auth.users (id, instance_id, aud, role, email, raw_user_meta_data, raw_app_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_owner@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000a2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_owner2@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_cust@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_rider@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_admin@example.test', '{}', '{}', now(), now());

INSERT INTO public.profiles (id, role, full_name, station_name, station_availability, latitude, longitude)
VALUES
  ('00000000-0000-4000-8000-0000000000a1', 'owner', 'T Owner', 'T Station', 'open', 14.60, 121.00),
  ('00000000-0000-4000-8000-0000000000a2', 'owner', 'T Owner 2', 'T Station 2', 'open', 14.61, 121.01),
  ('00000000-0000-4000-8000-0000000000c1', 'customer', 'T Cust', NULL, 'open', 14.62, 121.02),
  ('00000000-0000-4000-8000-0000000000d1', 'rider', 'T Rider', NULL, 'open', NULL, NULL),
  ('00000000-0000-4000-8000-0000000000e1', 'admin', 'T Admin', NULL, 'open', NULL, NULL);

INSERT INTO public.owner_settings (owner_id, base_delivery_fee)
VALUES
  ('00000000-0000-4000-8000-0000000000a1', 5.4),
  ('00000000-0000-4000-8000-0000000000a2', 0);

INSERT INTO public.products (id, owner_id, name, price, is_available)
VALUES ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000a1', 'T Water', 19.6, true);

-- Fee config used by every test unless a test overrides it.
UPDATE public.system_config SET value = '{"enabled": true, "percent": 1, "fixed": 0}'::jsonb
WHERE key = 'platform_fee';

SET LOCAL session_replication_role = origin;

-- Helpers (temporary: dropped with the transaction).
CREATE OR REPLACE FUNCTION pg_temp.act_as(p_user uuid) RETURNS void
LANGUAGE sql AS $$
  SELECT set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text,
    true
  );
$$;

CREATE OR REPLACE FUNCTION pg_temp.place_order(p_method text, p_qty integer DEFAULT 1)
RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  RETURN public.create_order_atomic(
    jsonb_build_object(
      'owner_id', '00000000-0000-4000-8000-0000000000a1',
      'payment_method', p_method,
      'customer_name', 'T Cust',
      'customer_address', 'Test address',
      'customer_latitude', '14.6',
      'customer_longitude', '121.0'
    ),
    jsonb_build_array(jsonb_build_object(
      'product_id', '00000000-0000-4000-8000-0000000000b1',
      'quantity', p_qty,
      'product_name', 'T Water'
    ))
  );
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.assert_eq(p_label text, p_actual anyelement, p_expected anyelement)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF p_actual IS DISTINCT FROM p_expected THEN
    RAISE EXCEPTION '% — expected %, got %', p_label, p_expected, p_actual;
  END IF;
END;
$$;

-- Runs p_sql and fails unless it raises an error containing p_message.
CREATE OR REPLACE FUNCTION pg_temp.expect_error(p_label text, p_sql text, p_message text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    IF position(p_message IN SQLERRM) = 0 THEN
      RAISE EXCEPTION '% — expected error "%", got "%"', p_label, p_message, SQLERRM;
    END IF;
    RETURN;
  END;
  RAISE EXCEPTION '% — expected error "%", but it succeeded', p_label, p_message;
END;
$$;
-- Run: bash build.sh ../scripts/rider_live_location.sql -- rider_live_location_test.sql
INSERT INTO public.rider_locations (rider_id, latitude, longitude)
VALUES ('00000000-0000-4000-8000-0000000000d1', 14.6, 121.0);

-- stranger_cannot_see_rider
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a2'); SET LOCAL ROLE authenticated;
  PERFORM pg_temp.assert_eq('hidden', (SELECT count(*) FROM public.rider_locations), 0::bigint);
  RESET ROLE;
END $$;

-- customer_sees_rider_only_during_delivery
DO $$ BEGIN
  SET LOCAL session_replication_role = replica;
  INSERT INTO public.orders (id, customer_id, owner_id, assigned_rider_id, status, total_amount)
  VALUES ('00000000-0000-4000-8000-00000000f101', '00000000-0000-4000-8000-0000000000c1',
          '00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000d1', 'out_for_delivery', 50);
  SET LOCAL session_replication_role = origin;
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1'); SET LOCAL ROLE authenticated;
  PERFORM pg_temp.assert_eq('visible', (SELECT count(*) FROM public.rider_locations), 1::bigint);
  RESET ROLE;
  SET LOCAL session_replication_role = replica;
  UPDATE public.orders SET status = 'delivered' WHERE id = '00000000-0000-4000-8000-00000000f101';
  SET LOCAL session_replication_role = origin;
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1'); SET LOCAL ROLE authenticated;
  PERFORM pg_temp.assert_eq('hidden after delivery', (SELECT count(*) FROM public.rider_locations), 0::bigint);
  RESET ROLE;
END $$;

-- rider_cannot_post_for_someone_else
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000d1'); SET LOCAL ROLE authenticated;
  PERFORM pg_temp.expect_error('spoof',
    $q$INSERT INTO public.rider_locations (rider_id, latitude, longitude)
       VALUES ('00000000-0000-4000-8000-0000000000a1', 1, 1)$q$, 'row-level security');
  RESET ROLE;
END $$;

SELECT 'rider_live_location_test: all passed' AS result;
ROLLBACK;

-- ===== refill_reminders_test =====
BEGIN;
-- ==============================================================================
-- Harden signup roles and protect trust columns on profiles (2026-11-05)
-- ==============================================================================
-- 1. Self-signup could claim role 'admin' or 'rider' through user metadata.
--    Only accounts created by a trusted server function (admin_create_user,
--    create_rider_account, admin_create_station) may get privileged roles.
--    Self-signups arrive through the Auth server, whose session user is
--    supabase_auth_admin; those are limited to customer/owner.
-- 2. Users could UPDATE their own average_rating / review_count /
--    reliability_score / flagged_count. Those are now writable only by admins
--    or by SECURITY DEFINER functions (e.g. update_station_stats()).
-- 3. Adds profiles.verification_status (used by identity verification), which is
--    protected the same way.
--
-- Run after: single_water_product_catalog.sql. Test: supabase/tests/protected_columns_test.sql
-- ==============================================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS verification_status text NOT NULL DEFAULT 'unverified';
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_verification_status_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_verification_status_check
  CHECK (verification_status IN ('unverified', 'pending', 'approved', 'rejected'));

-- 1. Role resolution -----------------------------------------------------------
CREATE OR REPLACE FUNCTION public.resolve_signup_role(p_requested text, p_trusted boolean)
RETURNS public.user_role
LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN p_requested IN ('customer', 'owner') THEN p_requested::public.user_role
    WHEN p_trusted AND p_requested IN ('rider', 'admin') THEN p_requested::public.user_role
    ELSE 'customer'::public.user_role
  END;
$$;
REVOKE ALL ON FUNCTION public.resolve_signup_role(text, boolean) FROM PUBLIC, anon, authenticated;

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
  -- 1. Role: self-signups (Auth server session) may only be customer or owner.
  v_role := public.resolve_signup_role(
    new.raw_user_meta_data->>'role',
    session_user <> 'supabase_auth_admin'
  );

  -- 2. Safe municipality enum resolution
  IF lower(trim(COALESCE(new.raw_user_meta_data->>'town', ''))) = 'cantilan' THEN
    v_town := 'Cantilan'::public.municipality;
  ELSIF lower(trim(COALESCE(new.raw_user_meta_data->>'town', ''))) = 'madrid' THEN
    v_town := 'Madrid'::public.municipality;
  ELSE
    v_town := NULL;
  END IF;

  v_complete_address := NULLIF(TRIM(COALESCE(new.raw_user_meta_data->>'complete_address', '')), '');

  -- 3. Names (Google OAuth sends 'name', 'given_name', 'family_name', 'picture')
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

  -- 5. Upsert profile
  INSERT INTO public.profiles (
    id, email, username, full_name, first_name, last_name, mi, suffix, role,
    phone, town, barangay, complete_address, landmark, station_name,
    avatar_url, latitude, longitude, primary_water_type
  )
  VALUES (
    new.id, new.email, v_username, v_full_name, v_first_name, v_last_name,
    new.raw_user_meta_data->>'mi', new.raw_user_meta_data->>'suffix', v_role,
    new.raw_user_meta_data->>'phone', v_town, new.raw_user_meta_data->>'barangay',
    v_complete_address, new.raw_user_meta_data->>'landmark',
    new.raw_user_meta_data->>'station_name', v_avatar_url,
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

-- 2. Protected trust columns -----------------------------------------------------
-- SECURITY INVOKER on purpose: current_user is 'authenticated'/'anon' for direct
-- client writes, and the function owner (postgres) inside SECURITY DEFINER
-- functions such as update_station_stats() and the admin RPCs.
CREATE OR REPLACE FUNCTION public.guard_profile_protected_columns()
RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;

  IF NEW.average_rating IS NOT DISTINCT FROM OLD.average_rating
    AND NEW.review_count IS NOT DISTINCT FROM OLD.review_count
    AND NEW.reliability_score IS NOT DISTINCT FROM OLD.reliability_score
    AND NEW.flagged_count IS NOT DISTINCT FROM OLD.flagged_count
    AND NEW.verification_status IS NOT DISTINCT FROM OLD.verification_status
  THEN
    RETURN NEW;
  END IF;

  IF public.is_admin() THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'Unauthorized: You cannot alter protected account fields.';
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_profile_protected_columns ON public.profiles;
CREATE TRIGGER trg_guard_profile_protected_columns
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.guard_profile_protected_columns();


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Delivery coverage: free-delivery zones + distance-based fees (2026-11-05)
-- ==============================================================================
-- Each station defines where delivery is free:
--   * within free_delivery_radius_km of the station (default 1 km), OR
--   * to any barangay listed in free_delivery_barangays, OR
--   * when the order has at least free_delivery_min_gallons water gallons.
-- Everywhere else pays the platform's per-km rate from
-- system_config.delivery_fee_config (rate_per_km, minimum_fee,
-- min_billable_distance_km, rounding_rule, enabled).
--
-- Distance = straight-line (haversine) x 1.3 road factor, so it approximates
-- real road distance without calling a routing service from the database.
--
-- Self-contained: does not depend on delivery_fee_config_rpcs.sql.
-- Run before: order_pricing_v3.sql. Test: supabase/tests/delivery_quote_test.sql
-- ==============================================================================

ALTER TABLE public.owner_settings
  ADD COLUMN IF NOT EXISTS free_delivery_radius_km numeric(4,1) NOT NULL DEFAULT 1.0,
  ADD COLUMN IF NOT EXISTS free_delivery_barangays text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS free_delivery_min_gallons integer;

ALTER TABLE public.owner_settings DROP CONSTRAINT IF EXISTS owner_settings_free_radius_check;
ALTER TABLE public.owner_settings ADD CONSTRAINT owner_settings_free_radius_check
  CHECK (free_delivery_radius_km >= 0 AND free_delivery_radius_km <= 10);
ALTER TABLE public.owner_settings DROP CONSTRAINT IF EXISTS owner_settings_free_min_gallons_check;
ALTER TABLE public.owner_settings ADD CONSTRAINT owner_settings_free_min_gallons_check
  CHECK (free_delivery_min_gallons IS NULL OR free_delivery_min_gallons BETWEEN 1 AND 100);

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS delivery_distance_km numeric(6,2),
  ADD COLUMN IF NOT EXISTS delivery_rate_per_km numeric(8,2),
  ADD COLUMN IF NOT EXISTS delivery_free_reason text;

-- Road factor applied to straight-line distance.
CREATE OR REPLACE FUNCTION public.delivery_road_distance_km(
  p_lat1 double precision, p_lng1 double precision,
  p_lat2 double precision, p_lng2 double precision
) RETURNS numeric
LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN p_lat1 IS NULL OR p_lng1 IS NULL OR p_lat2 IS NULL OR p_lng2 IS NULL THEN NULL
    ELSE round((
      2 * 6371 * asin(sqrt(
        power(sin(radians(p_lat2 - p_lat1) / 2), 2)
        + cos(radians(p_lat1)) * cos(radians(p_lat2))
          * power(sin(radians(p_lng2 - p_lng1) / 2), 2)
      )) * 1.3
    )::numeric, 2)
  END;
$$;

-- Fee for a distance outside the free zone, from the admin's config.
CREATE OR REPLACE FUNCTION public.delivery_fee_for_distance(p_km numeric)
RETURNS numeric
LANGUAGE plpgsql STABLE SET search_path TO 'public' AS $$
DECLARE
  v_cfg jsonb;
  v_rate numeric;
  v_min numeric;
  v_min_km numeric;
  v_rule text;
  v_fee numeric;
BEGIN
  SELECT value INTO v_cfg FROM public.system_config WHERE key = 'delivery_fee_config';
  v_cfg := coalesce(v_cfg, '{}'::jsonb);
  IF NOT coalesce((v_cfg->>'enabled')::boolean, true) THEN
    RETURN 0;
  END IF;
  v_rate := greatest(coalesce((v_cfg->>'rate_per_km')::numeric, 10), 0);
  v_min := greatest(coalesce((v_cfg->>'minimum_fee')::numeric, 20), 0);
  v_min_km := greatest(coalesce((v_cfg->>'min_billable_distance_km')::numeric, 1), 0);
  v_rule := lower(trim(coalesce(v_cfg->>'rounding_rule', 'exact')));

  IF p_km IS NULL THEN
    RETURN v_min;
  END IF;

  -- Same rule as CheckoutRules.calculateDeliveryFee in the app: the rounding
  -- rule applies to the billable distance; the fee is whole pesos.
  v_fee := greatest(p_km, v_min_km);
  v_fee := CASE
    WHEN v_rule IN ('ceil', 'round_up') THEN ceil(v_fee)
    WHEN v_rule IN ('round', 'round_nearest') THEN round(v_fee)
    ELSE v_fee
  END;
  IF v_rate <= 0 THEN
    RETURN 0;
  END IF;
  RETURN round(greatest(v_rate * v_fee, v_min));
END;
$$;

-- Quote shown at checkout and charged by create_order_atomic.
CREATE OR REPLACE FUNCTION public.compute_delivery_quote(
  p_station_id uuid,
  p_lat double precision,
  p_lng double precision,
  p_barangay text DEFAULT NULL,
  p_gallons integer DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_slat double precision;
  v_slng double precision;
  v_radius numeric;
  v_barangays text[];
  v_min_gallons integer;
  v_km numeric;
  v_reason text;
  v_cfg jsonb;
BEGIN
  SELECT coalesce(p.latitude, p.lat), coalesce(p.longitude, p.lng)
  INTO v_slat, v_slng
  FROM public.profiles p
  WHERE p.id = p_station_id AND p.role = 'owner';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Water refill station not found.';
  END IF;

  SELECT coalesce(os.free_delivery_radius_km, 1.0),
         coalesce(os.free_delivery_barangays, '{}'),
         os.free_delivery_min_gallons
  INTO v_radius, v_barangays, v_min_gallons
  FROM public.owner_settings os WHERE os.owner_id = p_station_id;
  v_radius := coalesce(v_radius, 1.0);
  v_barangays := coalesce(v_barangays, '{}');

  v_km := public.delivery_road_distance_km(v_slat, v_slng, p_lat, p_lng);

  IF v_km IS NOT NULL AND v_km <= v_radius THEN
    v_reason := 'radius';
  ELSIF p_barangay IS NOT NULL AND EXISTS (
    SELECT 1 FROM unnest(v_barangays) b
    WHERE lower(trim(b)) = lower(trim(p_barangay))
  ) THEN
    v_reason := 'barangay';
  ELSIF v_min_gallons IS NOT NULL AND coalesce(p_gallons, 0) >= v_min_gallons THEN
    v_reason := 'min_gallons';
  END IF;

  SELECT value INTO v_cfg FROM public.system_config WHERE key = 'delivery_fee_config';

  RETURN jsonb_build_object(
    'distance_km', v_km,
    'is_free', v_reason IS NOT NULL,
    'free_reason', v_reason,
    'fee', CASE WHEN v_reason IS NOT NULL THEN 0 ELSE public.delivery_fee_for_distance(v_km) END,
    'rate_per_km', coalesce((v_cfg->>'rate_per_km')::numeric, 10),
    'minimum_fee', coalesce((v_cfg->>'minimum_fee')::numeric, 20),
    'free_radius_km', v_radius,
    'free_barangays', to_jsonb(v_barangays),
    'free_min_gallons', v_min_gallons
  );
END;
$$;

REVOKE ALL ON FUNCTION public.compute_delivery_quote(uuid, double precision, double precision, text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.compute_delivery_quote(uuid, double precision, double precision, text, integer) TO authenticated;
REVOKE ALL ON FUNCTION public.delivery_fee_for_distance(numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delivery_fee_for_distance(numeric) TO authenticated;


NOTIFY pgrst, 'reload schema';
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


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Rider tips (2026-11-05)
-- ==============================================================================
-- Customers can add an optional tip (₱0–₱500, whole pesos) at checkout for
-- delivery orders. It is part of the single charge (COD or PayMongo), so no
-- second payment is needed, and 100% goes to the rider:
--   * excluded from the station SALE and from the 10% commission base
--   * booked as a RIDER_TIP ledger entry to the assigned rider
--   * if no rider was assigned (station delivered itself) it stays with the
--     station as part of the SALE
-- create_order_atomic reads p_order_data->>'tip_amount' (order_pricing_v3.sql).
--
-- Run before: order_pricing_v3.sql. Test: supabase/tests/rider_tips_test.sql
-- ==============================================================================

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS tip_amount numeric(10,2) NOT NULL DEFAULT 0;
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_tip_amount_check;
ALTER TABLE public.orders ADD CONSTRAINT orders_tip_amount_check
  CHECK (tip_amount >= 0 AND tip_amount <= 500);

CREATE OR REPLACE FUNCTION public.proc_finalize_order_finances()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    v_commission NUMERIC;
    v_fee NUMERIC := greatest(coalesce(NEW.platform_fee, 0), 0);
    v_tip NUMERIC := greatest(coalesce(NEW.tip_amount, 0), 0);
    v_rider_tip NUMERIC := 0;
BEGIN
    IF NEW.status = 'delivered' AND OLD.status != 'delivered' THEN
        -- The tip belongs to the rider; without a rider it stays in the sale.
        IF NEW.assigned_rider_id IS NOT NULL THEN
            v_rider_tip := v_tip;
        END IF;

        INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
        VALUES (NEW.owner_id, NEW.id, NEW.total_amount - v_fee - v_rider_tip, 'SALE', 'Order completion payment');

        IF v_fee > 0 THEN
            INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description, metadata)
            VALUES (
                NEW.owner_id, NEW.id, v_fee, 'SERVICE_FEE', 'Platform service fee',
                jsonb_build_object('payee', 'platform', 'payment_method', NEW.payment_method)
            );

            IF lower(coalesce(NEW.payment_method, 'cod')) IN ('cod', 'cash', 'credit') THEN
                PERFORM public.apply_wallet_entry(
                    NEW.owner_id, -v_fee, 'service_fee', NEW.id, NULL,
                    'Service fee for order ' || upper(substr(NEW.id::text, 1, 8))
                );
            END IF;
        END IF;

        -- Commission excludes the tip.
        v_commission := (NEW.total_amount - v_tip) * 0.10;

        IF NEW.assigned_rider_id IS NOT NULL THEN
            INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
            VALUES (NEW.assigned_rider_id, NEW.id, v_commission, 'COMMISSION', 'Delivery commission for order');

            IF v_rider_tip > 0 THEN
                INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
                VALUES (NEW.assigned_rider_id, NEW.id, v_rider_tip, 'RIDER_TIP', 'Customer tip');

                INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
                VALUES (
                    NEW.assigned_rider_id, 'system_alert', 'normal', 'You got a tip!',
                    'A customer tipped you PHP ' || trim(to_char(v_rider_tip, '999990')) || '. Thank you for the great service.',
                    jsonb_build_object('order_id', NEW.id, 'tip_amount', v_rider_tip)
                );
            END IF;
        END IF;

        INSERT INTO public.domain_events (event_type, payload, actor_id)
        VALUES ('ORDER_COMPLETED', jsonb_build_object(
            'order_id', NEW.id, 'total', NEW.total_amount,
            'rider_id', NEW.assigned_rider_id, 'tip', v_tip), auth.uid());
    END IF;
    RETURN NEW;
END;
$$;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Seller and customer ID verification (2026-11-05)
-- ==============================================================================
-- Users upload a government ID (front, back, selfie; owners also a business
-- permit) to the private bucket verification_docs under <their uid>/.
-- An admin reviews and approves or rejects. profiles.verification_status
-- (added and write-protected by harden_signup_and_protected_columns.sql) is
-- only changed by the RPCs below.
--
-- Gates (enforced in create_order_atomic, order_pricing_v3.sql):
--   * stations must be 'approved' to receive orders
--   * unverified customers: cash-on-delivery up to PHP 1,000 and at most
--     2 active COD orders; verified customers have no limit
-- Backfill: owners who already completed a delivery are approved (legacy).
--
-- Run after: harden_signup_and_protected_columns.sql
-- Run before: order_pricing_v3.sql. Test: supabase/tests/identity_verification_test.sql
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.identity_verifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role text NOT NULL,
  id_type text NOT NULL CHECK (id_type IN (
    'philsys', 'drivers_license', 'umid', 'passport', 'postal', 'voters', 'prc', 'other')),
  id_number_last4 text CHECK (id_number_last4 ~ '^[0-9A-Za-z]{4}$'),
  front_path text NOT NULL,
  back_path text,
  selfie_path text NOT NULL,
  business_permit_path text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  reviewer_id uuid REFERENCES public.profiles(id),
  reviewed_at timestamptz,
  rejection_reason text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_identity_verifications_user ON public.identity_verifications (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_identity_verifications_pending ON public.identity_verifications (created_at) WHERE status = 'pending';

ALTER TABLE public.identity_verifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users read own verifications" ON public.identity_verifications;
CREATE POLICY "Users read own verifications" ON public.identity_verifications
  FOR SELECT TO authenticated USING (auth.uid() = user_id OR public.is_admin());
-- Writes only through the RPCs below.
REVOKE INSERT, UPDATE, DELETE ON public.identity_verifications FROM anon, authenticated;
GRANT SELECT ON public.identity_verifications TO authenticated;

-- Private bucket, one folder per user.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('verification_docs', 'verification_docs', false, 8388608,
        ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
ON CONFLICT (id) DO UPDATE SET public = false;

DROP POLICY IF EXISTS "Verification docs: owner upload" ON storage.objects;
CREATE POLICY "Verification docs: owner upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'verification_docs' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "Verification docs: owner or admin read" ON storage.objects;
CREATE POLICY "Verification docs: owner or admin read" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'verification_docs'
         AND ((storage.foldername(name))[1] = auth.uid()::text OR public.is_admin()));

CREATE OR REPLACE FUNCTION public.submit_identity_verification(
  p_id_type text,
  p_id_number_last4 text,
  p_front_path text,
  p_back_path text,
  p_selfie_path text,
  p_business_permit_path text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_role text;
  v_status text;
  v_prefix text;
  v_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required.'; END IF;
  SELECT role::text, verification_status INTO v_role, v_status FROM public.profiles WHERE id = v_uid;
  IF v_role NOT IN ('customer', 'owner') THEN
    RAISE EXCEPTION 'Only customers and station owners verify their ID here.';
  END IF;
  IF v_status = 'approved' THEN RAISE EXCEPTION 'Your ID is already verified.'; END IF;
  IF v_status = 'pending' THEN RAISE EXCEPTION 'Your ID is already being reviewed.'; END IF;

  v_prefix := v_uid::text || '/';
  IF p_front_path IS NULL OR p_selfie_path IS NULL
     OR left(p_front_path, length(v_prefix)) <> v_prefix
     OR left(p_selfie_path, length(v_prefix)) <> v_prefix
     OR (p_back_path IS NOT NULL AND left(p_back_path, length(v_prefix)) <> v_prefix)
     OR (p_business_permit_path IS NOT NULL AND left(p_business_permit_path, length(v_prefix)) <> v_prefix) THEN
    RAISE EXCEPTION 'Upload your ID photos before submitting.';
  END IF;
  IF v_role = 'owner' AND p_business_permit_path IS NULL THEN
    RAISE EXCEPTION 'Stations must also upload a business or sanitary permit.';
  END IF;

  INSERT INTO public.identity_verifications (
    user_id, role, id_type, id_number_last4, front_path, back_path, selfie_path, business_permit_path)
  VALUES (v_uid, v_role, p_id_type, NULLIF(p_id_number_last4, ''), p_front_path, p_back_path,
          p_selfie_path, p_business_permit_path)
  RETURNING id INTO v_id;

  UPDATE public.profiles SET verification_status = 'pending' WHERE id = v_uid;
  RETURN jsonb_build_object('id', v_id, 'status', 'pending');
END; $$;

CREATE OR REPLACE FUNCTION public.admin_review_identity_verification(
  p_verification_id uuid,
  p_approve boolean,
  p_reason text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_row public.identity_verifications%ROWTYPE;
  v_status text := CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  IF NOT p_approve AND coalesce(trim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'Give the user a reason for the rejection.';
  END IF;

  UPDATE public.identity_verifications
  SET status = v_status, reviewer_id = auth.uid(), reviewed_at = now(),
      rejection_reason = CASE WHEN p_approve THEN NULL ELSE trim(p_reason) END
  WHERE id = p_verification_id AND status = 'pending'
  RETURNING * INTO v_row;
  IF NOT FOUND THEN RAISE EXCEPTION 'This verification was already reviewed.'; END IF;

  UPDATE public.profiles SET verification_status = v_status WHERE id = v_row.user_id;

  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (
    v_row.user_id, 'system_alert', 'high',
    CASE WHEN p_approve THEN 'Your ID is verified' ELSE 'ID verification needs another try' END,
    CASE WHEN p_approve
      THEN CASE WHEN v_row.role = 'owner'
        THEN 'Your station is verified and can now receive orders.'
        ELSE 'Your account is verified. Order limits are lifted.' END
      ELSE 'Reason: ' || trim(p_reason) || '. You can submit new photos.' END,
    jsonb_build_object('verification_id', v_row.id, 'status', v_status)
  );

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, new_value, metadata)
  VALUES (auth.uid(), 'identity_verification_' || v_status, 'identity_verifications', v_row.id::text,
          jsonb_build_object('status', v_status),
          jsonb_build_object('user_id', v_row.user_id, 'reason', p_reason));

  RETURN jsonb_build_object('id', v_row.id, 'status', v_status);
END; $$;

REVOKE ALL ON FUNCTION public.submit_identity_verification(text, text, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_identity_verification(text, text, text, text, text, text) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_review_identity_verification(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_review_identity_verification(uuid, boolean, text) TO authenticated;

-- Order gate helper, used by create_order_atomic.
CREATE OR REPLACE FUNCTION public.assert_order_allowed_by_verification(
  p_customer_id uuid, p_owner_id uuid, p_payment_method text, p_total numeric
) RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_owner_status text;
  v_customer_status text;
  v_active int;
BEGIN
  SELECT verification_status INTO v_owner_status FROM public.profiles WHERE id = p_owner_id;
  IF coalesce(v_owner_status, 'unverified') <> 'approved' THEN
    RAISE EXCEPTION 'This station is not verified yet and cannot take orders.';
  END IF;

  SELECT verification_status INTO v_customer_status FROM public.profiles WHERE id = p_customer_id;
  IF coalesce(v_customer_status, 'unverified') = 'approved'
     OR lower(coalesce(p_payment_method, 'cod')) NOT IN ('cod', 'cash') THEN
    RETURN;
  END IF;

  IF p_total > 1000 THEN
    RAISE EXCEPTION 'Verify your ID to place cash-on-delivery orders above PHP 1,000.';
  END IF;
  SELECT count(*) INTO v_active FROM public.orders
  WHERE customer_id = p_customer_id
    AND lower(coalesce(payment_method, 'cod')) IN ('cod', 'cash')
    AND status NOT IN ('delivered', 'cancelled', 'failed');
  IF v_active >= 2 THEN
    RAISE EXCEPTION 'Verify your ID to have more than 2 cash-on-delivery orders at a time.';
  END IF;
END; $$;
REVOKE ALL ON FUNCTION public.assert_order_allowed_by_verification(uuid, uuid, text, numeric) FROM PUBLIC, anon, authenticated;

-- Backfill: stations that already delivered orders keep working.
UPDATE public.profiles p SET verification_status = 'approved'
WHERE p.role = 'owner' AND p.verification_status = 'unverified'
  AND EXISTS (SELECT 1 FROM public.orders o WHERE o.owner_id = p.id AND o.status = 'delivered');


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- create_order_atomic v3 (2026-11-05)
-- ==============================================================================
-- Starts from the LIVE definition (pg_get_functiondef on 2026-11-05; note the
-- live function does not use price_order() from whole_peso_pricing.sql).
-- Changes:
--   * Delivery fee comes from compute_delivery_quote() (free zone or per-km),
--     never from the client and no longer from owner_settings.base_delivery_fee.
--   * Writes delivery_distance_km, delivery_rate_per_km, delivery_free_reason.
--   * Accessories (products.kind = 'accessory') are sold alongside water;
--     only water gallons count toward the free-delivery gallon threshold.
--   * Optional rider tip (tip_amount, ₱0–₱500) added to the total.
--   * ID verification gates: approved stations only; COD limits for
--     unverified customers.
-- This is the single place later features (accessories, tips, verification
-- gates) extend create_order_atomic. Do not redefine it in other scripts.
--
-- Run order: harden_signup_and_protected_columns.sql -> delivery_coverage.sql ->
--   station_accessories.sql -> rider_tips.sql -> identity_verification.sql -> this file.
-- Tests: supabase/tests/delivery_quote_test.sql, accessories_test.sql
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.create_order_atomic(p_order_data jsonb, p_items_data jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_customer_id uuid := auth.uid();
  v_owner_id uuid;
  v_payment_method text;
  v_idempotency_key public.orders.idempotency_key%TYPE;
  v_voucher_id uuid;
  v_order_id uuid;
  v_item record;
  v_product record;
  v_computed_subtotal numeric(10,2) := 0;
  v_delivery_fee numeric(10,2) := 0;
  v_platform_fee numeric(10,2) := 0;
  v_discount numeric(10,2) := 0;
  v_total_amount numeric(10,2) := 0;
  v_order_row public.orders%ROWTYPE;
  v_voucher public.customer_reward_vouchers%ROWTYPE;
  v_config jsonb;
  v_lat double precision;
  v_lng double precision;
  v_maintenance jsonb;
  v_is_maintenance boolean := false;
  v_customer_suspended boolean := false;
  v_owner_suspended boolean := false;
  v_gallons integer := 0;
  v_quote jsonb;
  v_tip numeric(10,2) := 0;
BEGIN
  SELECT value INTO v_maintenance
  FROM public.system_config
  WHERE key = 'maintenance_mode';

  IF v_maintenance IS NOT NULL THEN
    IF jsonb_typeof(v_maintenance) = 'boolean' THEN
      v_is_maintenance := v_maintenance::text::boolean;
    ELSIF jsonb_typeof(v_maintenance) = 'string' THEN
      v_is_maintenance :=
        lower(trim(both '"' from v_maintenance::text)) IN ('true', '1', 'yes');
    END IF;
  END IF;

  IF v_is_maintenance THEN
    RAISE EXCEPTION 'System is currently undergoing maintenance. New orders are temporarily paused.';
  END IF;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required to place an order.';
  END IF;

  SELECT coalesce(is_suspended, false) INTO v_customer_suspended
  FROM public.profiles
  WHERE id = v_customer_id AND role = 'customer';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Only customer accounts can place orders.';
  END IF;
  IF v_customer_suspended THEN
    RAISE EXCEPTION 'Your account has been suspended. Please contact customer support.';
  END IF;

  v_idempotency_key := NULLIF(p_order_data->>'idempotency_key', '');
  IF v_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_order_row
    FROM public.orders
    WHERE customer_id = v_customer_id
      AND idempotency_key = v_idempotency_key;

    IF FOUND THEN
      RETURN jsonb_build_object(
        'id', v_order_row.id,
        'subtotal', v_order_row.subtotal,
        'delivery_fee', v_order_row.delivery_fee,
        'platform_fee', v_order_row.platform_fee,
        'total_amount', v_order_row.total_amount,
        'status', v_order_row.status
      );
    END IF;
  END IF;

  v_owner_id := NULLIF(p_order_data->>'owner_id', '')::uuid;
  v_payment_method := lower(trim(coalesce(p_order_data->>'payment_method', 'cod')));
  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'Station owner ID is required.';
  END IF;

  SELECT coalesce(is_suspended, false) INTO v_owner_suspended
  FROM public.profiles
  WHERE id = v_owner_id AND role = 'owner';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Water refill station not found.';
  END IF;
  IF v_owner_suspended THEN
    RAISE EXCEPTION 'This water station is currently suspended by administration.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = v_owner_id
      AND role = 'owner'
      AND coalesce(station_availability, 'open') = 'open'
  ) THEN
    RAISE EXCEPTION 'This water station is currently closed or unavailable.';
  END IF;
  IF NOT public.is_station_payment_method_available(v_owner_id, v_payment_method) THEN
    RAISE EXCEPTION 'This payment method is not available for this station.';
  END IF;

  FOR v_item IN
    SELECT * FROM jsonb_to_recordset(p_items_data) AS x(
      product_id uuid,
      quantity integer,
      product_name text
    )
  LOOP
    IF v_item.quantity <= 0 THEN
      RAISE EXCEPTION 'Invalid quantity for item %', v_item.product_name;
    END IF;

    SELECT * INTO v_product
    FROM public.products
    WHERE id = v_item.product_id
      AND owner_id = v_owner_id
      AND is_available = true;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Product % is unavailable at this station.', v_item.product_name;
    END IF;

    v_computed_subtotal :=
      v_computed_subtotal + (v_product.price * v_item.quantity);
    -- Only water counts toward the free-delivery gallon threshold.
    IF v_product.kind = 'water' THEN
      v_gallons := v_gallons + v_item.quantity;
    END IF;
  END LOOP;

  IF v_computed_subtotal <= 0 THEN
    RAISE EXCEPTION 'Cart cannot be empty.';
  END IF;

  v_lat := NULLIF(p_order_data->>'customer_latitude', '')::double precision;
  v_lng := NULLIF(p_order_data->>'customer_longitude', '')::double precision;

  -- Delivery fee: server-side quote (free zone or per-km). Client fee ignored.
  v_quote := public.compute_delivery_quote(
    v_owner_id, v_lat, v_lng,
    NULLIF(p_order_data->>'customer_barangay', ''),
    v_gallons
  );
  v_delivery_fee := coalesce((v_quote->>'fee')::numeric, 0);

  v_config := public.get_platform_fee_config();
  IF coalesce((v_config->>'enabled')::boolean, false) THEN
    v_platform_fee := round(
      ((v_computed_subtotal + v_delivery_fee)
        * coalesce((v_config->>'percent')::numeric, 0) / 100)
        + coalesce((v_config->>'fixed')::numeric, 0),
      2
    );
    v_platform_fee := greatest(v_platform_fee, 0);
  END IF;

  v_voucher_id := NULLIF(p_order_data->>'voucher_id', '')::uuid;
  IF v_voucher_id IS NOT NULL THEN
    SELECT * INTO v_voucher
    FROM public.customer_reward_vouchers
    WHERE id = v_voucher_id
      AND user_id = v_customer_id
      AND is_used = false
      AND expires_at > now()
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'This reward voucher is no longer available. Refresh your vouchers and try again.';
    END IF;

    IF v_voucher.is_delivery_discount THEN
      v_discount := least(
        greatest(v_voucher.discount_amount, 0),
        v_delivery_fee
      );
    ELSE
      v_discount := least(
        greatest(v_voucher.discount_amount, 0),
        v_computed_subtotal + v_delivery_fee + v_platform_fee
      );
    END IF;
  END IF;

  -- Optional rider tip: whole pesos, ₱0–₱500, paid on top (no fees, no voucher).
  v_tip := round(coalesce(NULLIF(p_order_data->>'tip_amount', '')::numeric, 0));
  IF v_tip < 0 OR v_tip > 500 THEN
    RAISE EXCEPTION 'Tip must be between PHP 0 and PHP 500.';
  END IF;

  v_total_amount := greatest(
    v_computed_subtotal + v_delivery_fee + v_platform_fee - v_discount,
    0
  ) + v_tip;

  -- ID verification gates (identity_verification.sql).
  PERFORM public.assert_order_allowed_by_verification(
    v_customer_id, v_owner_id, v_payment_method, v_total_amount
  );

  INSERT INTO public.orders (
    id,
    customer_id,
    owner_id,
    station_name,
    customer_name,
    customer_phone,
    customer_address,
    customer_barangay,
    customer_municipality,
    customer_landmark,
    idempotency_key,
    subtotal,
    delivery_fee,
    platform_fee,
    total_amount,
    payment_method,
    payment_status,
    notes,
    region_id,
    customer_latitude,
    customer_longitude,
    delivery_lat,
    delivery_lng,
    delivery_latitude,
    delivery_longitude,
    delivery_distance_km,
    delivery_rate_per_km,
    delivery_free_reason,
    tip_amount,
    items,
    status
  ) VALUES (
    coalesce(
      NULLIF(p_order_data->>'id', '')::uuid,
      gen_random_uuid()
    ),
    v_customer_id,
    v_owner_id,
    coalesce(p_order_data->>'station_name', 'Water Station'),
    p_order_data->>'customer_name',
    p_order_data->>'customer_phone',
    p_order_data->>'customer_address',
    p_order_data->>'customer_barangay',
    p_order_data->>'customer_municipality',
    p_order_data->>'customer_landmark',
    v_idempotency_key,
    v_computed_subtotal,
    v_delivery_fee,
    v_platform_fee,
    v_total_amount,
    v_payment_method,
    'pending',
    p_order_data->>'notes',
    NULLIF(p_order_data->>'region_id', '')::uuid,
    v_lat,
    v_lng,
    v_lat,
    v_lng,
    v_lat,
    v_lng,
    (v_quote->>'distance_km')::numeric,
    (v_quote->>'rate_per_km')::numeric,
    v_quote->>'free_reason',
    v_tip,
    coalesce(p_items_data, '[]'::jsonb),
    'pending'
  )
  ON CONFLICT DO NOTHING
  RETURNING * INTO v_order_row;

  IF NOT FOUND THEN
    IF v_idempotency_key IS NOT NULL THEN
      SELECT * INTO v_order_row
      FROM public.orders
      WHERE customer_id = v_customer_id
        AND idempotency_key = v_idempotency_key;

      IF FOUND THEN
        RETURN jsonb_build_object(
          'id', v_order_row.id,
          'subtotal', v_order_row.subtotal,
          'delivery_fee', v_order_row.delivery_fee,
          'platform_fee', v_order_row.platform_fee,
          'total_amount', v_order_row.total_amount,
          'status', v_order_row.status
        );
      END IF;
    END IF;
    RAISE EXCEPTION 'Order could not be created because of a conflicting order record.';
  END IF;

  v_order_id := v_order_row.id;

  FOR v_item IN
    SELECT * FROM jsonb_to_recordset(p_items_data) AS x(
      product_id uuid,
      quantity integer,
      product_name text
    )
  LOOP
    SELECT * INTO v_product FROM public.products WHERE id = v_item.product_id;
    INSERT INTO public.order_items (
      order_id,
      product_id,
      product_name,
      quantity,
      price_at_purchase,
      subtotal
    ) VALUES (
      v_order_id,
      v_item.product_id,
      v_product.name,
      v_item.quantity,
      v_product.price,
      (v_product.price * v_item.quantity)
    );
  END LOOP;

  IF v_voucher_id IS NOT NULL THEN
    UPDATE public.customer_reward_vouchers
    SET is_used = true
    WHERE id = v_voucher_id
      AND user_id = v_customer_id
      AND is_used = false;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'This reward voucher was already used by another order.';
    END IF;
  END IF;

  INSERT INTO public.system_notifications (
    user_id,
    type,
    priority,
    title,
    content,
    metadata
  ) VALUES (
    v_owner_id,
    'system_alert',
    'high',
    'New Refill Order',
    coalesce(p_order_data->>'customer_name', 'A customer')
      || ' placed a new refill order of PHP '
      || trim(to_char(v_total_amount, '999999990.00'))
      || ' (' || upper(coalesce(p_order_data->>'payment_method', 'cod')) || ').',
    jsonb_build_object(
      'order_id', v_order_id,
      'status', 'pending',
      'total_amount', v_total_amount
    )
  );

  RETURN jsonb_build_object(
    'id', v_order_id,
    'subtotal', v_computed_subtotal,
    'delivery_fee', v_delivery_fee,
    'delivery_distance_km', (v_quote->>'distance_km')::numeric,
    'delivery_free_reason', v_quote->>'free_reason',
    'platform_fee', v_platform_fee,
    'discount_amount', v_discount,
    'tip_amount', v_tip,
    'total_amount', v_total_amount,
    'status', 'pending'
  );
END;
$function$;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Rider live location privacy (2026-11-05)
-- ==============================================================================
-- rider_locations was readable by everyone ("Public can view rider
-- locations"). Now only these can read a rider's points:
--   * the rider, admins
--   * the customer or station of an order that rider is delivering right now
--     (assigned_to_rider / out_for_delivery)
-- After delivery the customer loses access. Points older than 24 h are purged
-- hourly (pg_cron, when the extension is available).
-- Test: supabase/tests/rider_live_location_test.sql
-- ==============================================================================

DROP POLICY IF EXISTS "Public can view rider locations" ON public.rider_locations;
DROP POLICY IF EXISTS "Rider location visible to active delivery parties" ON public.rider_locations;
CREATE POLICY "Rider location visible to active delivery parties" ON public.rider_locations
  FOR SELECT TO authenticated
  USING (
    rider_id = auth.uid()
    OR public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.orders o
      WHERE (o.assigned_rider_id = rider_locations.rider_id OR o.rider_id = rider_locations.rider_id)
        AND o.status IN ('assigned_to_rider', 'out_for_delivery')
        AND (o.customer_id = auth.uid() OR o.owner_id = auth.uid())
    )
  );

DROP POLICY IF EXISTS "Riders can update their own location" ON public.rider_locations;
CREATE POLICY "Riders can update their own location" ON public.rider_locations
  FOR INSERT TO authenticated
  WITH CHECK (rider_id = auth.uid());
REVOKE ALL ON public.rider_locations FROM anon;

CREATE OR REPLACE FUNCTION public.purge_old_rider_locations()
RETURNS integer
LANGUAGE sql SECURITY DEFINER SET search_path TO 'public' AS $$
  WITH d AS (
    DELETE FROM public.rider_locations WHERE "timestamp" < now() - interval '24 hours' RETURNING 1
  ) SELECT count(*)::int FROM d;
$$;
REVOKE ALL ON FUNCTION public.purge_old_rider_locations() FROM PUBLIC, anon, authenticated;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'purge_old_rider_locations';
    PERFORM cron.schedule('purge_old_rider_locations', '7 * * * *', 'SELECT public.purge_old_rider_locations()');
  END IF;
END $$;

-- ==============================================================================
-- Smart refill reminders (2026-11-05)
-- ==============================================================================
-- Learns each customer's refill rhythm (median days between their last
-- delivered orders, needs >= 3 orders) and reminds them a day before they
-- usually reorder. At most one reminder per 3 days, never while an order is
-- active, and only when profiles.refill_reminders_enabled.
--   * customer_refill_rhythm()  -> for the app's home banner (current user)
--   * send_refill_reminders()   -> daily 9:00 PH pg_cron job, inserts notifications
-- Test: supabase/tests/refill_reminders_test.sql
-- ==============================================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS refill_reminders_enabled boolean NOT NULL DEFAULT true;

CREATE OR REPLACE FUNCTION public.refill_rhythm_for(p_customer_id uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  WITH recent AS (
    SELECT created_at, owner_id, station_name
    FROM public.orders
    WHERE customer_id = p_customer_id AND status = 'delivered'
    ORDER BY created_at DESC
    LIMIT 6
  ), gaps AS (
    SELECT extract(epoch FROM (created_at - lead(created_at) OVER (ORDER BY created_at DESC))) / 86400.0 AS days
    FROM recent
  ), stats AS (
    SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY days) AS median_days,
           count(*) AS gap_count
    FROM gaps WHERE days IS NOT NULL AND days > 0.5
  ), last AS (
    SELECT * FROM recent ORDER BY created_at DESC LIMIT 1
  )
  SELECT CASE
    WHEN (SELECT gap_count FROM stats) < 2 THEN jsonb_build_object('has_rhythm', false)
    ELSE jsonb_build_object(
      'has_rhythm', true,
      'median_days', round((SELECT median_days FROM stats)::numeric, 1),
      'last_order_at', (SELECT created_at FROM last),
      'station_id', (SELECT owner_id FROM last),
      'station_name', (SELECT station_name FROM last),
      'due_at', (SELECT created_at FROM last)
                + make_interval(secs => greatest((SELECT median_days FROM stats) - 1, 1) * 86400),
      'is_due', now() >= (SELECT created_at FROM last)
                + make_interval(secs => greatest((SELECT median_days FROM stats) - 1, 1) * 86400),
      'has_active_order', EXISTS (
        SELECT 1 FROM public.orders
        WHERE customer_id = p_customer_id
          AND status NOT IN ('delivered', 'cancelled', 'failed'))
    )
  END;
$$;
REVOKE ALL ON FUNCTION public.refill_rhythm_for(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.customer_refill_rhythm()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT CASE WHEN auth.uid() IS NULL THEN '{"has_rhythm": false}'::jsonb
              ELSE public.refill_rhythm_for(auth.uid()) END;
$$;
REVOKE ALL ON FUNCTION public.customer_refill_rhythm() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.customer_refill_rhythm() TO authenticated;

CREATE OR REPLACE FUNCTION public.send_refill_reminders()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_row record;
  v_r jsonb;
  v_sent integer := 0;
BEGIN
  FOR v_row IN
    SELECT p.id FROM public.profiles p
    WHERE p.role = 'customer' AND p.refill_reminders_enabled AND NOT coalesce(p.is_suspended, false)
  LOOP
    v_r := public.refill_rhythm_for(v_row.id);
    CONTINUE WHEN NOT coalesce((v_r->>'has_rhythm')::boolean, false)
               OR NOT (v_r->>'is_due')::boolean
               OR (v_r->>'has_active_order')::boolean;
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM public.system_notifications n
      WHERE n.user_id = v_row.id
        AND n.metadata->>'kind' = 'refill_reminder'
        AND n.created_at > now() - interval '3 days');

    INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
    VALUES (
      v_row.id, 'system_alert', 'normal', 'Time for a refill?',
      'You usually reorder every ' || round((v_r->>'median_days')::numeric) || ' days. '
        || 'Tap to reorder from ' || coalesce(v_r->>'station_name', 'your station') || '.',
      jsonb_build_object('kind', 'refill_reminder', 'station_id', v_r->>'station_id')
    );
    v_sent := v_sent + 1;
  END LOOP;
  RETURN v_sent;
END; $$;
REVOKE ALL ON FUNCTION public.send_refill_reminders() FROM PUBLIC, anon, authenticated;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'send_refill_reminders';
    -- 9:00 Asia/Manila = 01:00 UTC, so reminders arrive in the morning.
    PERFORM cron.schedule('send_refill_reminders', '0 1 * * *', 'SELECT public.send_refill_reminders()');
  END IF;
END $$;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Water quality transparency (2026-11-05)
-- ==============================================================================
-- Stations upload lab test results and permits (bacteriological /
-- physical-chemical water analysis, sanitary permit, business permit) with
-- issue and expiry dates. Admins approve them; approved, unexpired lab tests
-- give the station a "Water tested" badge and a small ranking boost.
-- Files live in the private verification_docs bucket under <uid>/certs/.
-- Approved certificate files are viewable by any signed-in user.
-- Daily job: marks expired certificates and warns owners 14 days ahead.
--
-- Run after: identity_verification.sql (bucket). Test: supabase/tests/water_quality_certs_test.sql
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.station_certifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  cert_type text NOT NULL CHECK (cert_type IN (
    'bacteriological', 'physical_chemical', 'sanitary_permit', 'business_permit')),
  issued_on date NOT NULL,
  expires_on date NOT NULL,
  file_path text NOT NULL,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected', 'expired')),
  reviewer_id uuid REFERENCES public.profiles(id),
  reviewed_at timestamptz,
  rejection_reason text,
  expiry_warned_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (expires_on > issued_on)
);
CREATE INDEX IF NOT EXISTS idx_station_certs_owner ON public.station_certifications (owner_id, status);

ALTER TABLE public.station_certifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Approved certs are public, owners see their own" ON public.station_certifications;
CREATE POLICY "Approved certs are public, owners see their own" ON public.station_certifications
  FOR SELECT TO authenticated
  USING (status = 'approved' OR owner_id = auth.uid() OR public.is_admin());
REVOKE INSERT, UPDATE, DELETE ON public.station_certifications FROM anon, authenticated;
GRANT SELECT ON public.station_certifications TO authenticated;

-- Approved certificate files are readable by signed-in users.
DROP POLICY IF EXISTS "Verification docs: approved certs readable" ON storage.objects;
CREATE POLICY "Verification docs: approved certs readable" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'verification_docs' AND EXISTS (
    SELECT 1 FROM public.station_certifications c
    WHERE c.file_path = storage.objects.name AND c.status = 'approved'));

CREATE OR REPLACE FUNCTION public.submit_station_certification(
  p_cert_type text, p_issued_on date, p_expires_on date, p_file_path text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_uid AND role = 'owner') THEN
    RAISE EXCEPTION 'Only station owners upload certificates.';
  END IF;
  IF p_file_path IS NULL OR left(p_file_path, length(v_uid::text) + 7) <> v_uid::text || '/certs/' THEN
    RAISE EXCEPTION 'Upload the certificate file first.';
  END IF;
  IF p_expires_on <= current_date THEN
    RAISE EXCEPTION 'This certificate has already expired.';
  END IF;
  IF p_issued_on > current_date THEN
    RAISE EXCEPTION 'The issue date cannot be in the future.';
  END IF;
  INSERT INTO public.station_certifications (owner_id, cert_type, issued_on, expires_on, file_path)
  VALUES (v_uid, p_cert_type, p_issued_on, p_expires_on, p_file_path)
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('id', v_id, 'status', 'pending');
END; $$;

CREATE OR REPLACE FUNCTION public.admin_review_station_certification(
  p_cert_id uuid, p_approve boolean, p_reason text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_row public.station_certifications%ROWTYPE;
  v_status text := CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  IF NOT p_approve AND coalesce(trim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'Give the station a reason for the rejection.';
  END IF;
  UPDATE public.station_certifications
  SET status = v_status, reviewer_id = auth.uid(), reviewed_at = now(),
      rejection_reason = CASE WHEN p_approve THEN NULL ELSE trim(p_reason) END
  WHERE id = p_cert_id AND status = 'pending'
  RETURNING * INTO v_row;
  IF NOT FOUND THEN RAISE EXCEPTION 'This certificate was already reviewed.'; END IF;

  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (v_row.owner_id, 'system_alert', 'normal',
    CASE WHEN p_approve THEN 'Certificate approved' ELSE 'Certificate rejected' END,
    CASE WHEN p_approve THEN 'Customers can now see your certificate.'
         ELSE 'Reason: ' || trim(p_reason) END,
    jsonb_build_object('certificate_id', v_row.id, 'status', v_status));
  RETURN jsonb_build_object('id', v_row.id, 'status', v_status);
END; $$;

REVOKE ALL ON FUNCTION public.submit_station_certification(text, date, date, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_station_certification(text, date, date, text) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_review_station_certification(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_review_station_certification(uuid, boolean, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.expire_station_certifications()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_n integer;
BEGIN
  UPDATE public.station_certifications SET status = 'expired'
  WHERE status = 'approved' AND expires_on <= current_date;
  GET DIAGNOSTICS v_n = ROW_COUNT;

  WITH soon AS (
    UPDATE public.station_certifications SET expiry_warned_at = now()
    WHERE status = 'approved' AND expiry_warned_at IS NULL
      AND expires_on <= current_date + 14
    RETURNING owner_id, id, cert_type, expires_on
  )
  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  SELECT owner_id, 'system_alert', 'high', 'Certificate expiring soon',
         'Your ' || replace(cert_type, '_', ' ') || ' certificate expires on '
           || to_char(expires_on, 'Mon DD, YYYY') || '. Upload a new one to keep your badge.',
         jsonb_build_object('certificate_id', id)
  FROM soon;
  RETURN v_n;
END; $$;
REVOKE ALL ON FUNCTION public.expire_station_certifications() FROM PUBLIC, anon, authenticated;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'expire_station_certifications';
    PERFORM cron.schedule('expire_station_certifications', '15 16 * * *', 'SELECT public.expire_station_certifications()');
  END IF;
END $$;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Order disputes and refunds (2026-11-05)
-- ==============================================================================
-- Extends the existing public.disputes table (status enum: open,
-- investigating, resolved, dismissed) with the customer -> station -> admin
-- flow:
--   1. Customer opens a dispute within 48 h of delivery, one per order,
--      with optional photo evidence (private bucket dispute_evidence).
--   2. Station accepts (refund amount) -> resolved, or explains -> the
--      dispute is escalated ('investigating') for an admin.
--   3. Customer may escalate if the station has not answered in 24 h.
--   4. Admin resolves with an optional refund, or dismisses.
-- A granted refund books a REFUND ledger entry against the station, notifies
-- the customer, and refunds against the station increase flagged_count.
-- Money movement: COD refunds are returned by the station in cash; online
-- payments are refunded by the admin in PayMongo (orders.payment_status is
-- set to 'refunded' when the full total is refunded).
--
-- Test: supabase/tests/order_disputes_test.sql
-- ==============================================================================

ALTER TABLE public.disputes
  ADD COLUMN IF NOT EXISTS evidence_paths text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS owner_response text,
  ADD COLUMN IF NOT EXISTS owner_responded_at timestamptz,
  ADD COLUMN IF NOT EXISTS refund_amount numeric(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS escalated_at timestamptz;
ALTER TABLE public.disputes DROP CONSTRAINT IF EXISTS disputes_reason_check;
ALTER TABLE public.disputes ADD CONSTRAINT disputes_reason_check CHECK (reason IN (
  'missing_items', 'wrong_item', 'quality', 'damaged', 'not_delivered', 'overcharged', 'other'));
ALTER TABLE public.disputes DROP CONSTRAINT IF EXISTS disputes_refund_check;
ALTER TABLE public.disputes ADD CONSTRAINT disputes_refund_check CHECK (refund_amount >= 0);
CREATE UNIQUE INDEX IF NOT EXISTS disputes_one_per_order ON public.disputes (order_id);

-- Owners no longer update disputes directly; they use owner_respond_dispute.
DROP POLICY IF EXISTS "Owners can update disputes for their station" ON public.disputes;
REVOKE INSERT, DELETE ON public.disputes FROM anon, authenticated;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('dispute_evidence', 'dispute_evidence', false, 8388608,
        ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO UPDATE SET public = false;
DROP POLICY IF EXISTS "Dispute evidence: reporter upload" ON storage.objects;
CREATE POLICY "Dispute evidence: reporter upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'dispute_evidence' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "Dispute evidence: parties read" ON storage.objects;
CREATE POLICY "Dispute evidence: parties read" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'dispute_evidence' AND (
    (storage.foldername(name))[1] = auth.uid()::text
    OR public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.disputes d JOIN public.orders o ON o.id = d.order_id
      WHERE storage.objects.name = ANY (d.evidence_paths) AND o.owner_id = auth.uid())));

CREATE OR REPLACE FUNCTION public.open_dispute(
  p_order_id uuid, p_reason text, p_description text, p_evidence_paths text[] DEFAULT '{}'
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_order public.orders%ROWTYPE;
  v_done_at timestamptz;
  v_id uuid;
  v_path text;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id AND customer_id = v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order not found.'; END IF;
  IF v_order.status::text <> 'delivered' THEN
    RAISE EXCEPTION 'You can report a problem once the order is delivered.';
  END IF;
  v_done_at := coalesce(v_order.actual_completion_at, v_order.updated_at, v_order.created_at);
  IF v_done_at < now() - interval '48 hours' THEN
    RAISE EXCEPTION 'Problems must be reported within 48 hours of delivery.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.disputes WHERE order_id = p_order_id) THEN
    RAISE EXCEPTION 'A problem was already reported for this order.';
  END IF;
  IF coalesce(trim(p_description), '') = '' THEN
    RAISE EXCEPTION 'Tell the station what went wrong.';
  END IF;
  FOREACH v_path IN ARRAY coalesce(p_evidence_paths, '{}') LOOP
    IF left(v_path, length(v_uid::text) + 1) <> v_uid::text || '/' THEN
      RAISE EXCEPTION 'Invalid evidence photo.';
    END IF;
  END LOOP;

  INSERT INTO public.disputes (order_id, reporter_id, reason, description, status, evidence_paths)
  VALUES (p_order_id, v_uid, p_reason, trim(p_description), 'open', coalesce(p_evidence_paths, '{}'))
  RETURNING id INTO v_id;

  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (v_order.owner_id, 'system_alert', 'high', 'A customer reported a problem',
    'Order #' || upper(substr(p_order_id::text, 1, 8)) || ': ' || replace(p_reason, '_', ' ')
      || '. Please respond within 24 hours.',
    jsonb_build_object('dispute_id', v_id, 'order_id', p_order_id));
  RETURN jsonb_build_object('id', v_id, 'status', 'open');
END; $$;

-- Shared by station and admin resolutions.
CREATE OR REPLACE FUNCTION public.apply_dispute_refund(p_dispute_id uuid, p_amount numeric, p_note text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_d public.disputes%ROWTYPE;
  v_o public.orders%ROWTYPE;
BEGIN
  SELECT * INTO v_d FROM public.disputes WHERE id = p_dispute_id;
  SELECT * INTO v_o FROM public.orders WHERE id = v_d.order_id;
  IF p_amount < 0 OR p_amount > v_o.total_amount THEN
    RAISE EXCEPTION 'Refund must be between PHP 0 and the order total.';
  END IF;
  UPDATE public.disputes SET refund_amount = p_amount, status = 'resolved',
         resolution_notes = p_note, updated_at = now()
  WHERE id = p_dispute_id;
  IF p_amount > 0 THEN
    INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
    VALUES (v_o.owner_id, v_o.id, -p_amount, 'REFUND', 'Refund for reported problem');
    UPDATE public.profiles SET flagged_count = coalesce(flagged_count, 0) + 1 WHERE id = v_o.owner_id;
    IF p_amount >= v_o.total_amount THEN
      UPDATE public.orders SET payment_status = 'refunded' WHERE id = v_o.id;
    END IF;
  END IF;
  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (v_d.reporter_id, 'system_alert', 'high',
    CASE WHEN p_amount > 0 THEN 'Refund approved' ELSE 'Your report was reviewed' END,
    CASE WHEN p_amount > 0
      THEN 'PHP ' || trim(to_char(p_amount, '999990.00')) || ' will be returned '
        || CASE WHEN lower(coalesce(v_o.payment_method, 'cod')) IN ('cod', 'cash')
                THEN 'by the station in cash.' ELSE 'to your original payment method.' END
      ELSE coalesce(p_note, 'No refund was given.') END,
    jsonb_build_object('dispute_id', p_dispute_id, 'order_id', v_o.id, 'refund_amount', p_amount));
END; $$;
REVOKE ALL ON FUNCTION public.apply_dispute_refund(uuid, numeric, text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.owner_respond_dispute(
  p_dispute_id uuid, p_accept boolean, p_response text, p_refund_amount numeric DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_d public.disputes%ROWTYPE;
BEGIN
  SELECT d.* INTO v_d FROM public.disputes d JOIN public.orders o ON o.id = d.order_id
  WHERE d.id = p_dispute_id AND o.owner_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Dispute not found.'; END IF;
  IF v_d.status::text <> 'open' OR v_d.owner_responded_at IS NOT NULL THEN
    RAISE EXCEPTION 'This dispute was already answered.';
  END IF;
  IF coalesce(trim(p_response), '') = '' THEN RAISE EXCEPTION 'Write a reply to the customer.'; END IF;

  UPDATE public.disputes SET owner_response = trim(p_response), owner_responded_at = now(), updated_at = now()
  WHERE id = p_dispute_id;

  IF p_accept THEN
    PERFORM public.apply_dispute_refund(p_dispute_id, coalesce(p_refund_amount, 0), 'Station: ' || trim(p_response));
    RETURN jsonb_build_object('status', 'resolved');
  END IF;

  UPDATE public.disputes SET status = 'investigating', escalated_at = now() WHERE id = p_dispute_id;
  RETURN jsonb_build_object('status', 'investigating');
END; $$;

CREATE OR REPLACE FUNCTION public.escalate_dispute(p_dispute_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  UPDATE public.disputes SET status = 'investigating', escalated_at = now(), updated_at = now()
  WHERE id = p_dispute_id AND reporter_id = auth.uid() AND status = 'open'
    AND owner_responded_at IS NULL AND created_at < now() - interval '24 hours';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'You can ask eRefill to step in 24 hours after reporting if the station has not replied.';
  END IF;
  RETURN jsonb_build_object('status', 'investigating');
END; $$;

CREATE OR REPLACE FUNCTION public.admin_resolve_dispute(
  p_dispute_id uuid, p_refund_amount numeric, p_notes text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.disputes WHERE id = p_dispute_id AND status IN ('open', 'investigating')) THEN
    RAISE EXCEPTION 'This dispute is already closed.';
  END IF;
  UPDATE public.disputes SET resolved_by = auth.uid() WHERE id = p_dispute_id;
  PERFORM public.apply_dispute_refund(p_dispute_id, coalesce(p_refund_amount, 0), p_notes);
  IF coalesce(p_refund_amount, 0) = 0 THEN
    UPDATE public.disputes SET status = 'dismissed' WHERE id = p_dispute_id;
  END IF;
  RETURN jsonb_build_object('status', CASE WHEN coalesce(p_refund_amount, 0) > 0 THEN 'resolved' ELSE 'dismissed' END);
END; $$;

REVOKE ALL ON FUNCTION public.open_dispute(uuid, text, text, text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.open_dispute(uuid, text, text, text[]) TO authenticated;
REVOKE ALL ON FUNCTION public.owner_respond_dispute(uuid, boolean, text, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.owner_respond_dispute(uuid, boolean, text, numeric) TO authenticated;
REVOKE ALL ON FUNCTION public.escalate_dispute(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.escalate_dispute(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_resolve_dispute(uuid, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_resolve_dispute(uuid, numeric, text) TO authenticated;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- AI ordering assistant: per-user daily message limit (2026-11-05)
-- ==============================================================================
-- The order-assistant Edge Function records one row per message (with the
-- service role) and refuses more than 20 per user in 24 hours.
-- Users can read their own usage; nobody writes from the app.
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.assistant_usage (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  input_tokens integer NOT NULL DEFAULT 0,
  output_tokens integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_assistant_usage_user_time ON public.assistant_usage (user_id, created_at DESC);

ALTER TABLE public.assistant_usage ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users read own assistant usage" ON public.assistant_usage;
CREATE POLICY "Users read own assistant usage" ON public.assistant_usage
  FOR SELECT TO authenticated USING (user_id = auth.uid());
REVOKE INSERT, UPDATE, DELETE ON public.assistant_usage FROM anon, authenticated;
GRANT SELECT ON public.assistant_usage TO authenticated;

-- Shared fixtures for the SQL tests in this folder. Every test runs as
--   BEGIN; <scripts under test, BEGIN/COMMIT stripped>; _fixtures.sql; <test>; ROLLBACK;
-- through the Supabase MCP execute_sql tool, so nothing persists.
--
-- Fixture rows are inserted with triggers off (replica role) to skip station
-- setup checks; triggers are back on before the test body runs.
--
-- ids: owner ...a1, second owner ...a2, customer ...c1, rider ...d1,
--      admin ...e1, product ...b1 (₱19.60, owner a1).

SET LOCAL session_replication_role = replica;

INSERT INTO auth.users (id, instance_id, aud, role, email, raw_user_meta_data, raw_app_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_owner@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000a2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_owner2@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_cust@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_rider@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_admin@example.test', '{}', '{}', now(), now());

INSERT INTO public.profiles (id, role, full_name, station_name, station_availability, latitude, longitude)
VALUES
  ('00000000-0000-4000-8000-0000000000a1', 'owner', 'T Owner', 'T Station', 'open', 14.60, 121.00),
  ('00000000-0000-4000-8000-0000000000a2', 'owner', 'T Owner 2', 'T Station 2', 'open', 14.61, 121.01),
  ('00000000-0000-4000-8000-0000000000c1', 'customer', 'T Cust', NULL, 'open', 14.62, 121.02),
  ('00000000-0000-4000-8000-0000000000d1', 'rider', 'T Rider', NULL, 'open', NULL, NULL),
  ('00000000-0000-4000-8000-0000000000e1', 'admin', 'T Admin', NULL, 'open', NULL, NULL);

INSERT INTO public.owner_settings (owner_id, base_delivery_fee)
VALUES
  ('00000000-0000-4000-8000-0000000000a1', 5.4),
  ('00000000-0000-4000-8000-0000000000a2', 0);

INSERT INTO public.products (id, owner_id, name, price, is_available)
VALUES ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000a1', 'T Water', 19.6, true);

-- Fee config used by every test unless a test overrides it.
UPDATE public.system_config SET value = '{"enabled": true, "percent": 1, "fixed": 0}'::jsonb
WHERE key = 'platform_fee';

SET LOCAL session_replication_role = origin;

-- Helpers (temporary: dropped with the transaction).
CREATE OR REPLACE FUNCTION pg_temp.act_as(p_user uuid) RETURNS void
LANGUAGE sql AS $$
  SELECT set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text,
    true
  );
$$;

CREATE OR REPLACE FUNCTION pg_temp.place_order(p_method text, p_qty integer DEFAULT 1)
RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  RETURN public.create_order_atomic(
    jsonb_build_object(
      'owner_id', '00000000-0000-4000-8000-0000000000a1',
      'payment_method', p_method,
      'customer_name', 'T Cust',
      'customer_address', 'Test address',
      'customer_latitude', '14.6',
      'customer_longitude', '121.0'
    ),
    jsonb_build_array(jsonb_build_object(
      'product_id', '00000000-0000-4000-8000-0000000000b1',
      'quantity', p_qty,
      'product_name', 'T Water'
    ))
  );
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.assert_eq(p_label text, p_actual anyelement, p_expected anyelement)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF p_actual IS DISTINCT FROM p_expected THEN
    RAISE EXCEPTION '% — expected %, got %', p_label, p_expected, p_actual;
  END IF;
END;
$$;

-- Runs p_sql and fails unless it raises an error containing p_message.
CREATE OR REPLACE FUNCTION pg_temp.expect_error(p_label text, p_sql text, p_message text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    IF position(p_message IN SQLERRM) = 0 THEN
      RAISE EXCEPTION '% — expected error "%", got "%"', p_label, p_message, SQLERRM;
    END IF;
    RETURN;
  END;
  RAISE EXCEPTION '% — expected error "%", but it succeeded', p_label, p_message;
END;
$$;
-- Run: bash build.sh ../scripts/refill_reminders.sql -- refill_reminders_test.sql
-- Customer c1 ordered every 5 days; last delivered order 6 days ago -> due.
SET LOCAL session_replication_role = replica;
INSERT INTO public.orders (customer_id, owner_id, status, total_amount, station_name, created_at) VALUES
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000a1', 'delivered', 50, 'T Station', now() - interval '21 days'),
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000a1', 'delivered', 50, 'T Station', now() - interval '16 days'),
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000a1', 'delivered', 50, 'T Station', now() - interval '11 days'),
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000a1', 'delivered', 50, 'T Station', now() - interval '6 days');
SET LOCAL session_replication_role = origin;

-- rhythm_is_median_gap
DO $$ DECLARE r jsonb; BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  r := public.customer_refill_rhythm();
  PERFORM pg_temp.assert_eq('has rhythm', (r->>'has_rhythm')::boolean, true);
  PERFORM pg_temp.assert_eq('median 5', (r->>'median_days')::numeric, 5.0::numeric);
  PERFORM pg_temp.assert_eq('due', (r->>'is_due')::boolean, true);
END $$;

-- one_reminder_then_quiet_for_3_days
DO $$ BEGIN
  PERFORM public.send_refill_reminders();
  PERFORM public.send_refill_reminders();
  PERFORM pg_temp.assert_eq('one reminder',
    (SELECT count(*) FROM public.system_notifications
     WHERE user_id = '00000000-0000-4000-8000-0000000000c1'
       AND metadata->>'kind' = 'refill_reminder'),
    1::bigint);
END $$;

-- opt_out_respected
DO $$ BEGIN
  DELETE FROM public.system_notifications WHERE metadata->>'kind' = 'refill_reminder';
  UPDATE public.profiles SET refill_reminders_enabled = false
  WHERE id = '00000000-0000-4000-8000-0000000000c1';
  PERFORM public.send_refill_reminders();
  PERFORM pg_temp.assert_eq('none when off',
    (SELECT count(*) FROM public.system_notifications
     WHERE metadata->>'kind' = 'refill_reminder'),
    0::bigint);
END $$;

-- too_few_orders_no_rhythm
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a2');
  PERFORM pg_temp.assert_eq('no rhythm',
    (public.customer_refill_rhythm()->>'has_rhythm')::boolean, false);
END $$;

SELECT 'refill_reminders_test: all passed' AS result;
ROLLBACK;

-- ===== water_quality_certs_test =====
BEGIN;
-- ==============================================================================
-- Harden signup roles and protect trust columns on profiles (2026-11-05)
-- ==============================================================================
-- 1. Self-signup could claim role 'admin' or 'rider' through user metadata.
--    Only accounts created by a trusted server function (admin_create_user,
--    create_rider_account, admin_create_station) may get privileged roles.
--    Self-signups arrive through the Auth server, whose session user is
--    supabase_auth_admin; those are limited to customer/owner.
-- 2. Users could UPDATE their own average_rating / review_count /
--    reliability_score / flagged_count. Those are now writable only by admins
--    or by SECURITY DEFINER functions (e.g. update_station_stats()).
-- 3. Adds profiles.verification_status (used by identity verification), which is
--    protected the same way.
--
-- Run after: single_water_product_catalog.sql. Test: supabase/tests/protected_columns_test.sql
-- ==============================================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS verification_status text NOT NULL DEFAULT 'unverified';
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_verification_status_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_verification_status_check
  CHECK (verification_status IN ('unverified', 'pending', 'approved', 'rejected'));

-- 1. Role resolution -----------------------------------------------------------
CREATE OR REPLACE FUNCTION public.resolve_signup_role(p_requested text, p_trusted boolean)
RETURNS public.user_role
LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN p_requested IN ('customer', 'owner') THEN p_requested::public.user_role
    WHEN p_trusted AND p_requested IN ('rider', 'admin') THEN p_requested::public.user_role
    ELSE 'customer'::public.user_role
  END;
$$;
REVOKE ALL ON FUNCTION public.resolve_signup_role(text, boolean) FROM PUBLIC, anon, authenticated;

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
  -- 1. Role: self-signups (Auth server session) may only be customer or owner.
  v_role := public.resolve_signup_role(
    new.raw_user_meta_data->>'role',
    session_user <> 'supabase_auth_admin'
  );

  -- 2. Safe municipality enum resolution
  IF lower(trim(COALESCE(new.raw_user_meta_data->>'town', ''))) = 'cantilan' THEN
    v_town := 'Cantilan'::public.municipality;
  ELSIF lower(trim(COALESCE(new.raw_user_meta_data->>'town', ''))) = 'madrid' THEN
    v_town := 'Madrid'::public.municipality;
  ELSE
    v_town := NULL;
  END IF;

  v_complete_address := NULLIF(TRIM(COALESCE(new.raw_user_meta_data->>'complete_address', '')), '');

  -- 3. Names (Google OAuth sends 'name', 'given_name', 'family_name', 'picture')
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

  -- 5. Upsert profile
  INSERT INTO public.profiles (
    id, email, username, full_name, first_name, last_name, mi, suffix, role,
    phone, town, barangay, complete_address, landmark, station_name,
    avatar_url, latitude, longitude, primary_water_type
  )
  VALUES (
    new.id, new.email, v_username, v_full_name, v_first_name, v_last_name,
    new.raw_user_meta_data->>'mi', new.raw_user_meta_data->>'suffix', v_role,
    new.raw_user_meta_data->>'phone', v_town, new.raw_user_meta_data->>'barangay',
    v_complete_address, new.raw_user_meta_data->>'landmark',
    new.raw_user_meta_data->>'station_name', v_avatar_url,
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

-- 2. Protected trust columns -----------------------------------------------------
-- SECURITY INVOKER on purpose: current_user is 'authenticated'/'anon' for direct
-- client writes, and the function owner (postgres) inside SECURITY DEFINER
-- functions such as update_station_stats() and the admin RPCs.
CREATE OR REPLACE FUNCTION public.guard_profile_protected_columns()
RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;

  IF NEW.average_rating IS NOT DISTINCT FROM OLD.average_rating
    AND NEW.review_count IS NOT DISTINCT FROM OLD.review_count
    AND NEW.reliability_score IS NOT DISTINCT FROM OLD.reliability_score
    AND NEW.flagged_count IS NOT DISTINCT FROM OLD.flagged_count
    AND NEW.verification_status IS NOT DISTINCT FROM OLD.verification_status
  THEN
    RETURN NEW;
  END IF;

  IF public.is_admin() THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'Unauthorized: You cannot alter protected account fields.';
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_profile_protected_columns ON public.profiles;
CREATE TRIGGER trg_guard_profile_protected_columns
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.guard_profile_protected_columns();


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Delivery coverage: free-delivery zones + distance-based fees (2026-11-05)
-- ==============================================================================
-- Each station defines where delivery is free:
--   * within free_delivery_radius_km of the station (default 1 km), OR
--   * to any barangay listed in free_delivery_barangays, OR
--   * when the order has at least free_delivery_min_gallons water gallons.
-- Everywhere else pays the platform's per-km rate from
-- system_config.delivery_fee_config (rate_per_km, minimum_fee,
-- min_billable_distance_km, rounding_rule, enabled).
--
-- Distance = straight-line (haversine) x 1.3 road factor, so it approximates
-- real road distance without calling a routing service from the database.
--
-- Self-contained: does not depend on delivery_fee_config_rpcs.sql.
-- Run before: order_pricing_v3.sql. Test: supabase/tests/delivery_quote_test.sql
-- ==============================================================================

ALTER TABLE public.owner_settings
  ADD COLUMN IF NOT EXISTS free_delivery_radius_km numeric(4,1) NOT NULL DEFAULT 1.0,
  ADD COLUMN IF NOT EXISTS free_delivery_barangays text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS free_delivery_min_gallons integer;

ALTER TABLE public.owner_settings DROP CONSTRAINT IF EXISTS owner_settings_free_radius_check;
ALTER TABLE public.owner_settings ADD CONSTRAINT owner_settings_free_radius_check
  CHECK (free_delivery_radius_km >= 0 AND free_delivery_radius_km <= 10);
ALTER TABLE public.owner_settings DROP CONSTRAINT IF EXISTS owner_settings_free_min_gallons_check;
ALTER TABLE public.owner_settings ADD CONSTRAINT owner_settings_free_min_gallons_check
  CHECK (free_delivery_min_gallons IS NULL OR free_delivery_min_gallons BETWEEN 1 AND 100);

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS delivery_distance_km numeric(6,2),
  ADD COLUMN IF NOT EXISTS delivery_rate_per_km numeric(8,2),
  ADD COLUMN IF NOT EXISTS delivery_free_reason text;

-- Road factor applied to straight-line distance.
CREATE OR REPLACE FUNCTION public.delivery_road_distance_km(
  p_lat1 double precision, p_lng1 double precision,
  p_lat2 double precision, p_lng2 double precision
) RETURNS numeric
LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN p_lat1 IS NULL OR p_lng1 IS NULL OR p_lat2 IS NULL OR p_lng2 IS NULL THEN NULL
    ELSE round((
      2 * 6371 * asin(sqrt(
        power(sin(radians(p_lat2 - p_lat1) / 2), 2)
        + cos(radians(p_lat1)) * cos(radians(p_lat2))
          * power(sin(radians(p_lng2 - p_lng1) / 2), 2)
      )) * 1.3
    )::numeric, 2)
  END;
$$;

-- Fee for a distance outside the free zone, from the admin's config.
CREATE OR REPLACE FUNCTION public.delivery_fee_for_distance(p_km numeric)
RETURNS numeric
LANGUAGE plpgsql STABLE SET search_path TO 'public' AS $$
DECLARE
  v_cfg jsonb;
  v_rate numeric;
  v_min numeric;
  v_min_km numeric;
  v_rule text;
  v_fee numeric;
BEGIN
  SELECT value INTO v_cfg FROM public.system_config WHERE key = 'delivery_fee_config';
  v_cfg := coalesce(v_cfg, '{}'::jsonb);
  IF NOT coalesce((v_cfg->>'enabled')::boolean, true) THEN
    RETURN 0;
  END IF;
  v_rate := greatest(coalesce((v_cfg->>'rate_per_km')::numeric, 10), 0);
  v_min := greatest(coalesce((v_cfg->>'minimum_fee')::numeric, 20), 0);
  v_min_km := greatest(coalesce((v_cfg->>'min_billable_distance_km')::numeric, 1), 0);
  v_rule := lower(trim(coalesce(v_cfg->>'rounding_rule', 'exact')));

  IF p_km IS NULL THEN
    RETURN v_min;
  END IF;

  -- Same rule as CheckoutRules.calculateDeliveryFee in the app: the rounding
  -- rule applies to the billable distance; the fee is whole pesos.
  v_fee := greatest(p_km, v_min_km);
  v_fee := CASE
    WHEN v_rule IN ('ceil', 'round_up') THEN ceil(v_fee)
    WHEN v_rule IN ('round', 'round_nearest') THEN round(v_fee)
    ELSE v_fee
  END;
  IF v_rate <= 0 THEN
    RETURN 0;
  END IF;
  RETURN round(greatest(v_rate * v_fee, v_min));
END;
$$;

-- Quote shown at checkout and charged by create_order_atomic.
CREATE OR REPLACE FUNCTION public.compute_delivery_quote(
  p_station_id uuid,
  p_lat double precision,
  p_lng double precision,
  p_barangay text DEFAULT NULL,
  p_gallons integer DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_slat double precision;
  v_slng double precision;
  v_radius numeric;
  v_barangays text[];
  v_min_gallons integer;
  v_km numeric;
  v_reason text;
  v_cfg jsonb;
BEGIN
  SELECT coalesce(p.latitude, p.lat), coalesce(p.longitude, p.lng)
  INTO v_slat, v_slng
  FROM public.profiles p
  WHERE p.id = p_station_id AND p.role = 'owner';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Water refill station not found.';
  END IF;

  SELECT coalesce(os.free_delivery_radius_km, 1.0),
         coalesce(os.free_delivery_barangays, '{}'),
         os.free_delivery_min_gallons
  INTO v_radius, v_barangays, v_min_gallons
  FROM public.owner_settings os WHERE os.owner_id = p_station_id;
  v_radius := coalesce(v_radius, 1.0);
  v_barangays := coalesce(v_barangays, '{}');

  v_km := public.delivery_road_distance_km(v_slat, v_slng, p_lat, p_lng);

  IF v_km IS NOT NULL AND v_km <= v_radius THEN
    v_reason := 'radius';
  ELSIF p_barangay IS NOT NULL AND EXISTS (
    SELECT 1 FROM unnest(v_barangays) b
    WHERE lower(trim(b)) = lower(trim(p_barangay))
  ) THEN
    v_reason := 'barangay';
  ELSIF v_min_gallons IS NOT NULL AND coalesce(p_gallons, 0) >= v_min_gallons THEN
    v_reason := 'min_gallons';
  END IF;

  SELECT value INTO v_cfg FROM public.system_config WHERE key = 'delivery_fee_config';

  RETURN jsonb_build_object(
    'distance_km', v_km,
    'is_free', v_reason IS NOT NULL,
    'free_reason', v_reason,
    'fee', CASE WHEN v_reason IS NOT NULL THEN 0 ELSE public.delivery_fee_for_distance(v_km) END,
    'rate_per_km', coalesce((v_cfg->>'rate_per_km')::numeric, 10),
    'minimum_fee', coalesce((v_cfg->>'minimum_fee')::numeric, 20),
    'free_radius_km', v_radius,
    'free_barangays', to_jsonb(v_barangays),
    'free_min_gallons', v_min_gallons
  );
END;
$$;

REVOKE ALL ON FUNCTION public.compute_delivery_quote(uuid, double precision, double precision, text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.compute_delivery_quote(uuid, double precision, double precision, text, integer) TO authenticated;
REVOKE ALL ON FUNCTION public.delivery_fee_for_distance(numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delivery_fee_for_distance(numeric) TO authenticated;


NOTIFY pgrst, 'reload schema';
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


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Rider tips (2026-11-05)
-- ==============================================================================
-- Customers can add an optional tip (₱0–₱500, whole pesos) at checkout for
-- delivery orders. It is part of the single charge (COD or PayMongo), so no
-- second payment is needed, and 100% goes to the rider:
--   * excluded from the station SALE and from the 10% commission base
--   * booked as a RIDER_TIP ledger entry to the assigned rider
--   * if no rider was assigned (station delivered itself) it stays with the
--     station as part of the SALE
-- create_order_atomic reads p_order_data->>'tip_amount' (order_pricing_v3.sql).
--
-- Run before: order_pricing_v3.sql. Test: supabase/tests/rider_tips_test.sql
-- ==============================================================================

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS tip_amount numeric(10,2) NOT NULL DEFAULT 0;
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_tip_amount_check;
ALTER TABLE public.orders ADD CONSTRAINT orders_tip_amount_check
  CHECK (tip_amount >= 0 AND tip_amount <= 500);

CREATE OR REPLACE FUNCTION public.proc_finalize_order_finances()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    v_commission NUMERIC;
    v_fee NUMERIC := greatest(coalesce(NEW.platform_fee, 0), 0);
    v_tip NUMERIC := greatest(coalesce(NEW.tip_amount, 0), 0);
    v_rider_tip NUMERIC := 0;
BEGIN
    IF NEW.status = 'delivered' AND OLD.status != 'delivered' THEN
        -- The tip belongs to the rider; without a rider it stays in the sale.
        IF NEW.assigned_rider_id IS NOT NULL THEN
            v_rider_tip := v_tip;
        END IF;

        INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
        VALUES (NEW.owner_id, NEW.id, NEW.total_amount - v_fee - v_rider_tip, 'SALE', 'Order completion payment');

        IF v_fee > 0 THEN
            INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description, metadata)
            VALUES (
                NEW.owner_id, NEW.id, v_fee, 'SERVICE_FEE', 'Platform service fee',
                jsonb_build_object('payee', 'platform', 'payment_method', NEW.payment_method)
            );

            IF lower(coalesce(NEW.payment_method, 'cod')) IN ('cod', 'cash', 'credit') THEN
                PERFORM public.apply_wallet_entry(
                    NEW.owner_id, -v_fee, 'service_fee', NEW.id, NULL,
                    'Service fee for order ' || upper(substr(NEW.id::text, 1, 8))
                );
            END IF;
        END IF;

        -- Commission excludes the tip.
        v_commission := (NEW.total_amount - v_tip) * 0.10;

        IF NEW.assigned_rider_id IS NOT NULL THEN
            INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
            VALUES (NEW.assigned_rider_id, NEW.id, v_commission, 'COMMISSION', 'Delivery commission for order');

            IF v_rider_tip > 0 THEN
                INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
                VALUES (NEW.assigned_rider_id, NEW.id, v_rider_tip, 'RIDER_TIP', 'Customer tip');

                INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
                VALUES (
                    NEW.assigned_rider_id, 'system_alert', 'normal', 'You got a tip!',
                    'A customer tipped you PHP ' || trim(to_char(v_rider_tip, '999990')) || '. Thank you for the great service.',
                    jsonb_build_object('order_id', NEW.id, 'tip_amount', v_rider_tip)
                );
            END IF;
        END IF;

        INSERT INTO public.domain_events (event_type, payload, actor_id)
        VALUES ('ORDER_COMPLETED', jsonb_build_object(
            'order_id', NEW.id, 'total', NEW.total_amount,
            'rider_id', NEW.assigned_rider_id, 'tip', v_tip), auth.uid());
    END IF;
    RETURN NEW;
END;
$$;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Seller and customer ID verification (2026-11-05)
-- ==============================================================================
-- Users upload a government ID (front, back, selfie; owners also a business
-- permit) to the private bucket verification_docs under <their uid>/.
-- An admin reviews and approves or rejects. profiles.verification_status
-- (added and write-protected by harden_signup_and_protected_columns.sql) is
-- only changed by the RPCs below.
--
-- Gates (enforced in create_order_atomic, order_pricing_v3.sql):
--   * stations must be 'approved' to receive orders
--   * unverified customers: cash-on-delivery up to PHP 1,000 and at most
--     2 active COD orders; verified customers have no limit
-- Backfill: owners who already completed a delivery are approved (legacy).
--
-- Run after: harden_signup_and_protected_columns.sql
-- Run before: order_pricing_v3.sql. Test: supabase/tests/identity_verification_test.sql
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.identity_verifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role text NOT NULL,
  id_type text NOT NULL CHECK (id_type IN (
    'philsys', 'drivers_license', 'umid', 'passport', 'postal', 'voters', 'prc', 'other')),
  id_number_last4 text CHECK (id_number_last4 ~ '^[0-9A-Za-z]{4}$'),
  front_path text NOT NULL,
  back_path text,
  selfie_path text NOT NULL,
  business_permit_path text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  reviewer_id uuid REFERENCES public.profiles(id),
  reviewed_at timestamptz,
  rejection_reason text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_identity_verifications_user ON public.identity_verifications (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_identity_verifications_pending ON public.identity_verifications (created_at) WHERE status = 'pending';

ALTER TABLE public.identity_verifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users read own verifications" ON public.identity_verifications;
CREATE POLICY "Users read own verifications" ON public.identity_verifications
  FOR SELECT TO authenticated USING (auth.uid() = user_id OR public.is_admin());
-- Writes only through the RPCs below.
REVOKE INSERT, UPDATE, DELETE ON public.identity_verifications FROM anon, authenticated;
GRANT SELECT ON public.identity_verifications TO authenticated;

-- Private bucket, one folder per user.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('verification_docs', 'verification_docs', false, 8388608,
        ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
ON CONFLICT (id) DO UPDATE SET public = false;

DROP POLICY IF EXISTS "Verification docs: owner upload" ON storage.objects;
CREATE POLICY "Verification docs: owner upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'verification_docs' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "Verification docs: owner or admin read" ON storage.objects;
CREATE POLICY "Verification docs: owner or admin read" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'verification_docs'
         AND ((storage.foldername(name))[1] = auth.uid()::text OR public.is_admin()));

CREATE OR REPLACE FUNCTION public.submit_identity_verification(
  p_id_type text,
  p_id_number_last4 text,
  p_front_path text,
  p_back_path text,
  p_selfie_path text,
  p_business_permit_path text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_role text;
  v_status text;
  v_prefix text;
  v_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required.'; END IF;
  SELECT role::text, verification_status INTO v_role, v_status FROM public.profiles WHERE id = v_uid;
  IF v_role NOT IN ('customer', 'owner') THEN
    RAISE EXCEPTION 'Only customers and station owners verify their ID here.';
  END IF;
  IF v_status = 'approved' THEN RAISE EXCEPTION 'Your ID is already verified.'; END IF;
  IF v_status = 'pending' THEN RAISE EXCEPTION 'Your ID is already being reviewed.'; END IF;

  v_prefix := v_uid::text || '/';
  IF p_front_path IS NULL OR p_selfie_path IS NULL
     OR left(p_front_path, length(v_prefix)) <> v_prefix
     OR left(p_selfie_path, length(v_prefix)) <> v_prefix
     OR (p_back_path IS NOT NULL AND left(p_back_path, length(v_prefix)) <> v_prefix)
     OR (p_business_permit_path IS NOT NULL AND left(p_business_permit_path, length(v_prefix)) <> v_prefix) THEN
    RAISE EXCEPTION 'Upload your ID photos before submitting.';
  END IF;
  IF v_role = 'owner' AND p_business_permit_path IS NULL THEN
    RAISE EXCEPTION 'Stations must also upload a business or sanitary permit.';
  END IF;

  INSERT INTO public.identity_verifications (
    user_id, role, id_type, id_number_last4, front_path, back_path, selfie_path, business_permit_path)
  VALUES (v_uid, v_role, p_id_type, NULLIF(p_id_number_last4, ''), p_front_path, p_back_path,
          p_selfie_path, p_business_permit_path)
  RETURNING id INTO v_id;

  UPDATE public.profiles SET verification_status = 'pending' WHERE id = v_uid;
  RETURN jsonb_build_object('id', v_id, 'status', 'pending');
END; $$;

CREATE OR REPLACE FUNCTION public.admin_review_identity_verification(
  p_verification_id uuid,
  p_approve boolean,
  p_reason text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_row public.identity_verifications%ROWTYPE;
  v_status text := CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  IF NOT p_approve AND coalesce(trim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'Give the user a reason for the rejection.';
  END IF;

  UPDATE public.identity_verifications
  SET status = v_status, reviewer_id = auth.uid(), reviewed_at = now(),
      rejection_reason = CASE WHEN p_approve THEN NULL ELSE trim(p_reason) END
  WHERE id = p_verification_id AND status = 'pending'
  RETURNING * INTO v_row;
  IF NOT FOUND THEN RAISE EXCEPTION 'This verification was already reviewed.'; END IF;

  UPDATE public.profiles SET verification_status = v_status WHERE id = v_row.user_id;

  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (
    v_row.user_id, 'system_alert', 'high',
    CASE WHEN p_approve THEN 'Your ID is verified' ELSE 'ID verification needs another try' END,
    CASE WHEN p_approve
      THEN CASE WHEN v_row.role = 'owner'
        THEN 'Your station is verified and can now receive orders.'
        ELSE 'Your account is verified. Order limits are lifted.' END
      ELSE 'Reason: ' || trim(p_reason) || '. You can submit new photos.' END,
    jsonb_build_object('verification_id', v_row.id, 'status', v_status)
  );

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, new_value, metadata)
  VALUES (auth.uid(), 'identity_verification_' || v_status, 'identity_verifications', v_row.id::text,
          jsonb_build_object('status', v_status),
          jsonb_build_object('user_id', v_row.user_id, 'reason', p_reason));

  RETURN jsonb_build_object('id', v_row.id, 'status', v_status);
END; $$;

REVOKE ALL ON FUNCTION public.submit_identity_verification(text, text, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_identity_verification(text, text, text, text, text, text) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_review_identity_verification(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_review_identity_verification(uuid, boolean, text) TO authenticated;

-- Order gate helper, used by create_order_atomic.
CREATE OR REPLACE FUNCTION public.assert_order_allowed_by_verification(
  p_customer_id uuid, p_owner_id uuid, p_payment_method text, p_total numeric
) RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_owner_status text;
  v_customer_status text;
  v_active int;
BEGIN
  SELECT verification_status INTO v_owner_status FROM public.profiles WHERE id = p_owner_id;
  IF coalesce(v_owner_status, 'unverified') <> 'approved' THEN
    RAISE EXCEPTION 'This station is not verified yet and cannot take orders.';
  END IF;

  SELECT verification_status INTO v_customer_status FROM public.profiles WHERE id = p_customer_id;
  IF coalesce(v_customer_status, 'unverified') = 'approved'
     OR lower(coalesce(p_payment_method, 'cod')) NOT IN ('cod', 'cash') THEN
    RETURN;
  END IF;

  IF p_total > 1000 THEN
    RAISE EXCEPTION 'Verify your ID to place cash-on-delivery orders above PHP 1,000.';
  END IF;
  SELECT count(*) INTO v_active FROM public.orders
  WHERE customer_id = p_customer_id
    AND lower(coalesce(payment_method, 'cod')) IN ('cod', 'cash')
    AND status NOT IN ('delivered', 'cancelled', 'failed');
  IF v_active >= 2 THEN
    RAISE EXCEPTION 'Verify your ID to have more than 2 cash-on-delivery orders at a time.';
  END IF;
END; $$;
REVOKE ALL ON FUNCTION public.assert_order_allowed_by_verification(uuid, uuid, text, numeric) FROM PUBLIC, anon, authenticated;

-- Backfill: stations that already delivered orders keep working.
UPDATE public.profiles p SET verification_status = 'approved'
WHERE p.role = 'owner' AND p.verification_status = 'unverified'
  AND EXISTS (SELECT 1 FROM public.orders o WHERE o.owner_id = p.id AND o.status = 'delivered');


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- create_order_atomic v3 (2026-11-05)
-- ==============================================================================
-- Starts from the LIVE definition (pg_get_functiondef on 2026-11-05; note the
-- live function does not use price_order() from whole_peso_pricing.sql).
-- Changes:
--   * Delivery fee comes from compute_delivery_quote() (free zone or per-km),
--     never from the client and no longer from owner_settings.base_delivery_fee.
--   * Writes delivery_distance_km, delivery_rate_per_km, delivery_free_reason.
--   * Accessories (products.kind = 'accessory') are sold alongside water;
--     only water gallons count toward the free-delivery gallon threshold.
--   * Optional rider tip (tip_amount, ₱0–₱500) added to the total.
--   * ID verification gates: approved stations only; COD limits for
--     unverified customers.
-- This is the single place later features (accessories, tips, verification
-- gates) extend create_order_atomic. Do not redefine it in other scripts.
--
-- Run order: harden_signup_and_protected_columns.sql -> delivery_coverage.sql ->
--   station_accessories.sql -> rider_tips.sql -> identity_verification.sql -> this file.
-- Tests: supabase/tests/delivery_quote_test.sql, accessories_test.sql
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.create_order_atomic(p_order_data jsonb, p_items_data jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_customer_id uuid := auth.uid();
  v_owner_id uuid;
  v_payment_method text;
  v_idempotency_key public.orders.idempotency_key%TYPE;
  v_voucher_id uuid;
  v_order_id uuid;
  v_item record;
  v_product record;
  v_computed_subtotal numeric(10,2) := 0;
  v_delivery_fee numeric(10,2) := 0;
  v_platform_fee numeric(10,2) := 0;
  v_discount numeric(10,2) := 0;
  v_total_amount numeric(10,2) := 0;
  v_order_row public.orders%ROWTYPE;
  v_voucher public.customer_reward_vouchers%ROWTYPE;
  v_config jsonb;
  v_lat double precision;
  v_lng double precision;
  v_maintenance jsonb;
  v_is_maintenance boolean := false;
  v_customer_suspended boolean := false;
  v_owner_suspended boolean := false;
  v_gallons integer := 0;
  v_quote jsonb;
  v_tip numeric(10,2) := 0;
BEGIN
  SELECT value INTO v_maintenance
  FROM public.system_config
  WHERE key = 'maintenance_mode';

  IF v_maintenance IS NOT NULL THEN
    IF jsonb_typeof(v_maintenance) = 'boolean' THEN
      v_is_maintenance := v_maintenance::text::boolean;
    ELSIF jsonb_typeof(v_maintenance) = 'string' THEN
      v_is_maintenance :=
        lower(trim(both '"' from v_maintenance::text)) IN ('true', '1', 'yes');
    END IF;
  END IF;

  IF v_is_maintenance THEN
    RAISE EXCEPTION 'System is currently undergoing maintenance. New orders are temporarily paused.';
  END IF;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required to place an order.';
  END IF;

  SELECT coalesce(is_suspended, false) INTO v_customer_suspended
  FROM public.profiles
  WHERE id = v_customer_id AND role = 'customer';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Only customer accounts can place orders.';
  END IF;
  IF v_customer_suspended THEN
    RAISE EXCEPTION 'Your account has been suspended. Please contact customer support.';
  END IF;

  v_idempotency_key := NULLIF(p_order_data->>'idempotency_key', '');
  IF v_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_order_row
    FROM public.orders
    WHERE customer_id = v_customer_id
      AND idempotency_key = v_idempotency_key;

    IF FOUND THEN
      RETURN jsonb_build_object(
        'id', v_order_row.id,
        'subtotal', v_order_row.subtotal,
        'delivery_fee', v_order_row.delivery_fee,
        'platform_fee', v_order_row.platform_fee,
        'total_amount', v_order_row.total_amount,
        'status', v_order_row.status
      );
    END IF;
  END IF;

  v_owner_id := NULLIF(p_order_data->>'owner_id', '')::uuid;
  v_payment_method := lower(trim(coalesce(p_order_data->>'payment_method', 'cod')));
  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'Station owner ID is required.';
  END IF;

  SELECT coalesce(is_suspended, false) INTO v_owner_suspended
  FROM public.profiles
  WHERE id = v_owner_id AND role = 'owner';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Water refill station not found.';
  END IF;
  IF v_owner_suspended THEN
    RAISE EXCEPTION 'This water station is currently suspended by administration.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = v_owner_id
      AND role = 'owner'
      AND coalesce(station_availability, 'open') = 'open'
  ) THEN
    RAISE EXCEPTION 'This water station is currently closed or unavailable.';
  END IF;
  IF NOT public.is_station_payment_method_available(v_owner_id, v_payment_method) THEN
    RAISE EXCEPTION 'This payment method is not available for this station.';
  END IF;

  FOR v_item IN
    SELECT * FROM jsonb_to_recordset(p_items_data) AS x(
      product_id uuid,
      quantity integer,
      product_name text
    )
  LOOP
    IF v_item.quantity <= 0 THEN
      RAISE EXCEPTION 'Invalid quantity for item %', v_item.product_name;
    END IF;

    SELECT * INTO v_product
    FROM public.products
    WHERE id = v_item.product_id
      AND owner_id = v_owner_id
      AND is_available = true;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Product % is unavailable at this station.', v_item.product_name;
    END IF;

    v_computed_subtotal :=
      v_computed_subtotal + (v_product.price * v_item.quantity);
    -- Only water counts toward the free-delivery gallon threshold.
    IF v_product.kind = 'water' THEN
      v_gallons := v_gallons + v_item.quantity;
    END IF;
  END LOOP;

  IF v_computed_subtotal <= 0 THEN
    RAISE EXCEPTION 'Cart cannot be empty.';
  END IF;

  v_lat := NULLIF(p_order_data->>'customer_latitude', '')::double precision;
  v_lng := NULLIF(p_order_data->>'customer_longitude', '')::double precision;

  -- Delivery fee: server-side quote (free zone or per-km). Client fee ignored.
  v_quote := public.compute_delivery_quote(
    v_owner_id, v_lat, v_lng,
    NULLIF(p_order_data->>'customer_barangay', ''),
    v_gallons
  );
  v_delivery_fee := coalesce((v_quote->>'fee')::numeric, 0);

  v_config := public.get_platform_fee_config();
  IF coalesce((v_config->>'enabled')::boolean, false) THEN
    v_platform_fee := round(
      ((v_computed_subtotal + v_delivery_fee)
        * coalesce((v_config->>'percent')::numeric, 0) / 100)
        + coalesce((v_config->>'fixed')::numeric, 0),
      2
    );
    v_platform_fee := greatest(v_platform_fee, 0);
  END IF;

  v_voucher_id := NULLIF(p_order_data->>'voucher_id', '')::uuid;
  IF v_voucher_id IS NOT NULL THEN
    SELECT * INTO v_voucher
    FROM public.customer_reward_vouchers
    WHERE id = v_voucher_id
      AND user_id = v_customer_id
      AND is_used = false
      AND expires_at > now()
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'This reward voucher is no longer available. Refresh your vouchers and try again.';
    END IF;

    IF v_voucher.is_delivery_discount THEN
      v_discount := least(
        greatest(v_voucher.discount_amount, 0),
        v_delivery_fee
      );
    ELSE
      v_discount := least(
        greatest(v_voucher.discount_amount, 0),
        v_computed_subtotal + v_delivery_fee + v_platform_fee
      );
    END IF;
  END IF;

  -- Optional rider tip: whole pesos, ₱0–₱500, paid on top (no fees, no voucher).
  v_tip := round(coalesce(NULLIF(p_order_data->>'tip_amount', '')::numeric, 0));
  IF v_tip < 0 OR v_tip > 500 THEN
    RAISE EXCEPTION 'Tip must be between PHP 0 and PHP 500.';
  END IF;

  v_total_amount := greatest(
    v_computed_subtotal + v_delivery_fee + v_platform_fee - v_discount,
    0
  ) + v_tip;

  -- ID verification gates (identity_verification.sql).
  PERFORM public.assert_order_allowed_by_verification(
    v_customer_id, v_owner_id, v_payment_method, v_total_amount
  );

  INSERT INTO public.orders (
    id,
    customer_id,
    owner_id,
    station_name,
    customer_name,
    customer_phone,
    customer_address,
    customer_barangay,
    customer_municipality,
    customer_landmark,
    idempotency_key,
    subtotal,
    delivery_fee,
    platform_fee,
    total_amount,
    payment_method,
    payment_status,
    notes,
    region_id,
    customer_latitude,
    customer_longitude,
    delivery_lat,
    delivery_lng,
    delivery_latitude,
    delivery_longitude,
    delivery_distance_km,
    delivery_rate_per_km,
    delivery_free_reason,
    tip_amount,
    items,
    status
  ) VALUES (
    coalesce(
      NULLIF(p_order_data->>'id', '')::uuid,
      gen_random_uuid()
    ),
    v_customer_id,
    v_owner_id,
    coalesce(p_order_data->>'station_name', 'Water Station'),
    p_order_data->>'customer_name',
    p_order_data->>'customer_phone',
    p_order_data->>'customer_address',
    p_order_data->>'customer_barangay',
    p_order_data->>'customer_municipality',
    p_order_data->>'customer_landmark',
    v_idempotency_key,
    v_computed_subtotal,
    v_delivery_fee,
    v_platform_fee,
    v_total_amount,
    v_payment_method,
    'pending',
    p_order_data->>'notes',
    NULLIF(p_order_data->>'region_id', '')::uuid,
    v_lat,
    v_lng,
    v_lat,
    v_lng,
    v_lat,
    v_lng,
    (v_quote->>'distance_km')::numeric,
    (v_quote->>'rate_per_km')::numeric,
    v_quote->>'free_reason',
    v_tip,
    coalesce(p_items_data, '[]'::jsonb),
    'pending'
  )
  ON CONFLICT DO NOTHING
  RETURNING * INTO v_order_row;

  IF NOT FOUND THEN
    IF v_idempotency_key IS NOT NULL THEN
      SELECT * INTO v_order_row
      FROM public.orders
      WHERE customer_id = v_customer_id
        AND idempotency_key = v_idempotency_key;

      IF FOUND THEN
        RETURN jsonb_build_object(
          'id', v_order_row.id,
          'subtotal', v_order_row.subtotal,
          'delivery_fee', v_order_row.delivery_fee,
          'platform_fee', v_order_row.platform_fee,
          'total_amount', v_order_row.total_amount,
          'status', v_order_row.status
        );
      END IF;
    END IF;
    RAISE EXCEPTION 'Order could not be created because of a conflicting order record.';
  END IF;

  v_order_id := v_order_row.id;

  FOR v_item IN
    SELECT * FROM jsonb_to_recordset(p_items_data) AS x(
      product_id uuid,
      quantity integer,
      product_name text
    )
  LOOP
    SELECT * INTO v_product FROM public.products WHERE id = v_item.product_id;
    INSERT INTO public.order_items (
      order_id,
      product_id,
      product_name,
      quantity,
      price_at_purchase,
      subtotal
    ) VALUES (
      v_order_id,
      v_item.product_id,
      v_product.name,
      v_item.quantity,
      v_product.price,
      (v_product.price * v_item.quantity)
    );
  END LOOP;

  IF v_voucher_id IS NOT NULL THEN
    UPDATE public.customer_reward_vouchers
    SET is_used = true
    WHERE id = v_voucher_id
      AND user_id = v_customer_id
      AND is_used = false;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'This reward voucher was already used by another order.';
    END IF;
  END IF;

  INSERT INTO public.system_notifications (
    user_id,
    type,
    priority,
    title,
    content,
    metadata
  ) VALUES (
    v_owner_id,
    'system_alert',
    'high',
    'New Refill Order',
    coalesce(p_order_data->>'customer_name', 'A customer')
      || ' placed a new refill order of PHP '
      || trim(to_char(v_total_amount, '999999990.00'))
      || ' (' || upper(coalesce(p_order_data->>'payment_method', 'cod')) || ').',
    jsonb_build_object(
      'order_id', v_order_id,
      'status', 'pending',
      'total_amount', v_total_amount
    )
  );

  RETURN jsonb_build_object(
    'id', v_order_id,
    'subtotal', v_computed_subtotal,
    'delivery_fee', v_delivery_fee,
    'delivery_distance_km', (v_quote->>'distance_km')::numeric,
    'delivery_free_reason', v_quote->>'free_reason',
    'platform_fee', v_platform_fee,
    'discount_amount', v_discount,
    'tip_amount', v_tip,
    'total_amount', v_total_amount,
    'status', 'pending'
  );
END;
$function$;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Rider live location privacy (2026-11-05)
-- ==============================================================================
-- rider_locations was readable by everyone ("Public can view rider
-- locations"). Now only these can read a rider's points:
--   * the rider, admins
--   * the customer or station of an order that rider is delivering right now
--     (assigned_to_rider / out_for_delivery)
-- After delivery the customer loses access. Points older than 24 h are purged
-- hourly (pg_cron, when the extension is available).
-- Test: supabase/tests/rider_live_location_test.sql
-- ==============================================================================

DROP POLICY IF EXISTS "Public can view rider locations" ON public.rider_locations;
DROP POLICY IF EXISTS "Rider location visible to active delivery parties" ON public.rider_locations;
CREATE POLICY "Rider location visible to active delivery parties" ON public.rider_locations
  FOR SELECT TO authenticated
  USING (
    rider_id = auth.uid()
    OR public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.orders o
      WHERE (o.assigned_rider_id = rider_locations.rider_id OR o.rider_id = rider_locations.rider_id)
        AND o.status IN ('assigned_to_rider', 'out_for_delivery')
        AND (o.customer_id = auth.uid() OR o.owner_id = auth.uid())
    )
  );

DROP POLICY IF EXISTS "Riders can update their own location" ON public.rider_locations;
CREATE POLICY "Riders can update their own location" ON public.rider_locations
  FOR INSERT TO authenticated
  WITH CHECK (rider_id = auth.uid());
REVOKE ALL ON public.rider_locations FROM anon;

CREATE OR REPLACE FUNCTION public.purge_old_rider_locations()
RETURNS integer
LANGUAGE sql SECURITY DEFINER SET search_path TO 'public' AS $$
  WITH d AS (
    DELETE FROM public.rider_locations WHERE "timestamp" < now() - interval '24 hours' RETURNING 1
  ) SELECT count(*)::int FROM d;
$$;
REVOKE ALL ON FUNCTION public.purge_old_rider_locations() FROM PUBLIC, anon, authenticated;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'purge_old_rider_locations';
    PERFORM cron.schedule('purge_old_rider_locations', '7 * * * *', 'SELECT public.purge_old_rider_locations()');
  END IF;
END $$;

-- ==============================================================================
-- Smart refill reminders (2026-11-05)
-- ==============================================================================
-- Learns each customer's refill rhythm (median days between their last
-- delivered orders, needs >= 3 orders) and reminds them a day before they
-- usually reorder. At most one reminder per 3 days, never while an order is
-- active, and only when profiles.refill_reminders_enabled.
--   * customer_refill_rhythm()  -> for the app's home banner (current user)
--   * send_refill_reminders()   -> daily 9:00 PH pg_cron job, inserts notifications
-- Test: supabase/tests/refill_reminders_test.sql
-- ==============================================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS refill_reminders_enabled boolean NOT NULL DEFAULT true;

CREATE OR REPLACE FUNCTION public.refill_rhythm_for(p_customer_id uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  WITH recent AS (
    SELECT created_at, owner_id, station_name
    FROM public.orders
    WHERE customer_id = p_customer_id AND status = 'delivered'
    ORDER BY created_at DESC
    LIMIT 6
  ), gaps AS (
    SELECT extract(epoch FROM (created_at - lead(created_at) OVER (ORDER BY created_at DESC))) / 86400.0 AS days
    FROM recent
  ), stats AS (
    SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY days) AS median_days,
           count(*) AS gap_count
    FROM gaps WHERE days IS NOT NULL AND days > 0.5
  ), last AS (
    SELECT * FROM recent ORDER BY created_at DESC LIMIT 1
  )
  SELECT CASE
    WHEN (SELECT gap_count FROM stats) < 2 THEN jsonb_build_object('has_rhythm', false)
    ELSE jsonb_build_object(
      'has_rhythm', true,
      'median_days', round((SELECT median_days FROM stats)::numeric, 1),
      'last_order_at', (SELECT created_at FROM last),
      'station_id', (SELECT owner_id FROM last),
      'station_name', (SELECT station_name FROM last),
      'due_at', (SELECT created_at FROM last)
                + make_interval(secs => greatest((SELECT median_days FROM stats) - 1, 1) * 86400),
      'is_due', now() >= (SELECT created_at FROM last)
                + make_interval(secs => greatest((SELECT median_days FROM stats) - 1, 1) * 86400),
      'has_active_order', EXISTS (
        SELECT 1 FROM public.orders
        WHERE customer_id = p_customer_id
          AND status NOT IN ('delivered', 'cancelled', 'failed'))
    )
  END;
$$;
REVOKE ALL ON FUNCTION public.refill_rhythm_for(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.customer_refill_rhythm()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT CASE WHEN auth.uid() IS NULL THEN '{"has_rhythm": false}'::jsonb
              ELSE public.refill_rhythm_for(auth.uid()) END;
$$;
REVOKE ALL ON FUNCTION public.customer_refill_rhythm() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.customer_refill_rhythm() TO authenticated;

CREATE OR REPLACE FUNCTION public.send_refill_reminders()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_row record;
  v_r jsonb;
  v_sent integer := 0;
BEGIN
  FOR v_row IN
    SELECT p.id FROM public.profiles p
    WHERE p.role = 'customer' AND p.refill_reminders_enabled AND NOT coalesce(p.is_suspended, false)
  LOOP
    v_r := public.refill_rhythm_for(v_row.id);
    CONTINUE WHEN NOT coalesce((v_r->>'has_rhythm')::boolean, false)
               OR NOT (v_r->>'is_due')::boolean
               OR (v_r->>'has_active_order')::boolean;
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM public.system_notifications n
      WHERE n.user_id = v_row.id
        AND n.metadata->>'kind' = 'refill_reminder'
        AND n.created_at > now() - interval '3 days');

    INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
    VALUES (
      v_row.id, 'system_alert', 'normal', 'Time for a refill?',
      'You usually reorder every ' || round((v_r->>'median_days')::numeric) || ' days. '
        || 'Tap to reorder from ' || coalesce(v_r->>'station_name', 'your station') || '.',
      jsonb_build_object('kind', 'refill_reminder', 'station_id', v_r->>'station_id')
    );
    v_sent := v_sent + 1;
  END LOOP;
  RETURN v_sent;
END; $$;
REVOKE ALL ON FUNCTION public.send_refill_reminders() FROM PUBLIC, anon, authenticated;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'send_refill_reminders';
    -- 9:00 Asia/Manila = 01:00 UTC, so reminders arrive in the morning.
    PERFORM cron.schedule('send_refill_reminders', '0 1 * * *', 'SELECT public.send_refill_reminders()');
  END IF;
END $$;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Water quality transparency (2026-11-05)
-- ==============================================================================
-- Stations upload lab test results and permits (bacteriological /
-- physical-chemical water analysis, sanitary permit, business permit) with
-- issue and expiry dates. Admins approve them; approved, unexpired lab tests
-- give the station a "Water tested" badge and a small ranking boost.
-- Files live in the private verification_docs bucket under <uid>/certs/.
-- Approved certificate files are viewable by any signed-in user.
-- Daily job: marks expired certificates and warns owners 14 days ahead.
--
-- Run after: identity_verification.sql (bucket). Test: supabase/tests/water_quality_certs_test.sql
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.station_certifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  cert_type text NOT NULL CHECK (cert_type IN (
    'bacteriological', 'physical_chemical', 'sanitary_permit', 'business_permit')),
  issued_on date NOT NULL,
  expires_on date NOT NULL,
  file_path text NOT NULL,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected', 'expired')),
  reviewer_id uuid REFERENCES public.profiles(id),
  reviewed_at timestamptz,
  rejection_reason text,
  expiry_warned_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (expires_on > issued_on)
);
CREATE INDEX IF NOT EXISTS idx_station_certs_owner ON public.station_certifications (owner_id, status);

ALTER TABLE public.station_certifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Approved certs are public, owners see their own" ON public.station_certifications;
CREATE POLICY "Approved certs are public, owners see their own" ON public.station_certifications
  FOR SELECT TO authenticated
  USING (status = 'approved' OR owner_id = auth.uid() OR public.is_admin());
REVOKE INSERT, UPDATE, DELETE ON public.station_certifications FROM anon, authenticated;
GRANT SELECT ON public.station_certifications TO authenticated;

-- Approved certificate files are readable by signed-in users.
DROP POLICY IF EXISTS "Verification docs: approved certs readable" ON storage.objects;
CREATE POLICY "Verification docs: approved certs readable" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'verification_docs' AND EXISTS (
    SELECT 1 FROM public.station_certifications c
    WHERE c.file_path = storage.objects.name AND c.status = 'approved'));

CREATE OR REPLACE FUNCTION public.submit_station_certification(
  p_cert_type text, p_issued_on date, p_expires_on date, p_file_path text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_uid AND role = 'owner') THEN
    RAISE EXCEPTION 'Only station owners upload certificates.';
  END IF;
  IF p_file_path IS NULL OR left(p_file_path, length(v_uid::text) + 7) <> v_uid::text || '/certs/' THEN
    RAISE EXCEPTION 'Upload the certificate file first.';
  END IF;
  IF p_expires_on <= current_date THEN
    RAISE EXCEPTION 'This certificate has already expired.';
  END IF;
  IF p_issued_on > current_date THEN
    RAISE EXCEPTION 'The issue date cannot be in the future.';
  END IF;
  INSERT INTO public.station_certifications (owner_id, cert_type, issued_on, expires_on, file_path)
  VALUES (v_uid, p_cert_type, p_issued_on, p_expires_on, p_file_path)
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('id', v_id, 'status', 'pending');
END; $$;

CREATE OR REPLACE FUNCTION public.admin_review_station_certification(
  p_cert_id uuid, p_approve boolean, p_reason text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_row public.station_certifications%ROWTYPE;
  v_status text := CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  IF NOT p_approve AND coalesce(trim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'Give the station a reason for the rejection.';
  END IF;
  UPDATE public.station_certifications
  SET status = v_status, reviewer_id = auth.uid(), reviewed_at = now(),
      rejection_reason = CASE WHEN p_approve THEN NULL ELSE trim(p_reason) END
  WHERE id = p_cert_id AND status = 'pending'
  RETURNING * INTO v_row;
  IF NOT FOUND THEN RAISE EXCEPTION 'This certificate was already reviewed.'; END IF;

  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (v_row.owner_id, 'system_alert', 'normal',
    CASE WHEN p_approve THEN 'Certificate approved' ELSE 'Certificate rejected' END,
    CASE WHEN p_approve THEN 'Customers can now see your certificate.'
         ELSE 'Reason: ' || trim(p_reason) END,
    jsonb_build_object('certificate_id', v_row.id, 'status', v_status));
  RETURN jsonb_build_object('id', v_row.id, 'status', v_status);
END; $$;

REVOKE ALL ON FUNCTION public.submit_station_certification(text, date, date, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_station_certification(text, date, date, text) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_review_station_certification(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_review_station_certification(uuid, boolean, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.expire_station_certifications()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_n integer;
BEGIN
  UPDATE public.station_certifications SET status = 'expired'
  WHERE status = 'approved' AND expires_on <= current_date;
  GET DIAGNOSTICS v_n = ROW_COUNT;

  WITH soon AS (
    UPDATE public.station_certifications SET expiry_warned_at = now()
    WHERE status = 'approved' AND expiry_warned_at IS NULL
      AND expires_on <= current_date + 14
    RETURNING owner_id, id, cert_type, expires_on
  )
  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  SELECT owner_id, 'system_alert', 'high', 'Certificate expiring soon',
         'Your ' || replace(cert_type, '_', ' ') || ' certificate expires on '
           || to_char(expires_on, 'Mon DD, YYYY') || '. Upload a new one to keep your badge.',
         jsonb_build_object('certificate_id', id)
  FROM soon;
  RETURN v_n;
END; $$;
REVOKE ALL ON FUNCTION public.expire_station_certifications() FROM PUBLIC, anon, authenticated;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'expire_station_certifications';
    PERFORM cron.schedule('expire_station_certifications', '15 16 * * *', 'SELECT public.expire_station_certifications()');
  END IF;
END $$;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Order disputes and refunds (2026-11-05)
-- ==============================================================================
-- Extends the existing public.disputes table (status enum: open,
-- investigating, resolved, dismissed) with the customer -> station -> admin
-- flow:
--   1. Customer opens a dispute within 48 h of delivery, one per order,
--      with optional photo evidence (private bucket dispute_evidence).
--   2. Station accepts (refund amount) -> resolved, or explains -> the
--      dispute is escalated ('investigating') for an admin.
--   3. Customer may escalate if the station has not answered in 24 h.
--   4. Admin resolves with an optional refund, or dismisses.
-- A granted refund books a REFUND ledger entry against the station, notifies
-- the customer, and refunds against the station increase flagged_count.
-- Money movement: COD refunds are returned by the station in cash; online
-- payments are refunded by the admin in PayMongo (orders.payment_status is
-- set to 'refunded' when the full total is refunded).
--
-- Test: supabase/tests/order_disputes_test.sql
-- ==============================================================================

ALTER TABLE public.disputes
  ADD COLUMN IF NOT EXISTS evidence_paths text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS owner_response text,
  ADD COLUMN IF NOT EXISTS owner_responded_at timestamptz,
  ADD COLUMN IF NOT EXISTS refund_amount numeric(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS escalated_at timestamptz;
ALTER TABLE public.disputes DROP CONSTRAINT IF EXISTS disputes_reason_check;
ALTER TABLE public.disputes ADD CONSTRAINT disputes_reason_check CHECK (reason IN (
  'missing_items', 'wrong_item', 'quality', 'damaged', 'not_delivered', 'overcharged', 'other'));
ALTER TABLE public.disputes DROP CONSTRAINT IF EXISTS disputes_refund_check;
ALTER TABLE public.disputes ADD CONSTRAINT disputes_refund_check CHECK (refund_amount >= 0);
CREATE UNIQUE INDEX IF NOT EXISTS disputes_one_per_order ON public.disputes (order_id);

-- Owners no longer update disputes directly; they use owner_respond_dispute.
DROP POLICY IF EXISTS "Owners can update disputes for their station" ON public.disputes;
REVOKE INSERT, DELETE ON public.disputes FROM anon, authenticated;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('dispute_evidence', 'dispute_evidence', false, 8388608,
        ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO UPDATE SET public = false;
DROP POLICY IF EXISTS "Dispute evidence: reporter upload" ON storage.objects;
CREATE POLICY "Dispute evidence: reporter upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'dispute_evidence' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "Dispute evidence: parties read" ON storage.objects;
CREATE POLICY "Dispute evidence: parties read" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'dispute_evidence' AND (
    (storage.foldername(name))[1] = auth.uid()::text
    OR public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.disputes d JOIN public.orders o ON o.id = d.order_id
      WHERE storage.objects.name = ANY (d.evidence_paths) AND o.owner_id = auth.uid())));

CREATE OR REPLACE FUNCTION public.open_dispute(
  p_order_id uuid, p_reason text, p_description text, p_evidence_paths text[] DEFAULT '{}'
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_order public.orders%ROWTYPE;
  v_done_at timestamptz;
  v_id uuid;
  v_path text;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id AND customer_id = v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order not found.'; END IF;
  IF v_order.status::text <> 'delivered' THEN
    RAISE EXCEPTION 'You can report a problem once the order is delivered.';
  END IF;
  v_done_at := coalesce(v_order.actual_completion_at, v_order.updated_at, v_order.created_at);
  IF v_done_at < now() - interval '48 hours' THEN
    RAISE EXCEPTION 'Problems must be reported within 48 hours of delivery.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.disputes WHERE order_id = p_order_id) THEN
    RAISE EXCEPTION 'A problem was already reported for this order.';
  END IF;
  IF coalesce(trim(p_description), '') = '' THEN
    RAISE EXCEPTION 'Tell the station what went wrong.';
  END IF;
  FOREACH v_path IN ARRAY coalesce(p_evidence_paths, '{}') LOOP
    IF left(v_path, length(v_uid::text) + 1) <> v_uid::text || '/' THEN
      RAISE EXCEPTION 'Invalid evidence photo.';
    END IF;
  END LOOP;

  INSERT INTO public.disputes (order_id, reporter_id, reason, description, status, evidence_paths)
  VALUES (p_order_id, v_uid, p_reason, trim(p_description), 'open', coalesce(p_evidence_paths, '{}'))
  RETURNING id INTO v_id;

  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (v_order.owner_id, 'system_alert', 'high', 'A customer reported a problem',
    'Order #' || upper(substr(p_order_id::text, 1, 8)) || ': ' || replace(p_reason, '_', ' ')
      || '. Please respond within 24 hours.',
    jsonb_build_object('dispute_id', v_id, 'order_id', p_order_id));
  RETURN jsonb_build_object('id', v_id, 'status', 'open');
END; $$;

-- Shared by station and admin resolutions.
CREATE OR REPLACE FUNCTION public.apply_dispute_refund(p_dispute_id uuid, p_amount numeric, p_note text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_d public.disputes%ROWTYPE;
  v_o public.orders%ROWTYPE;
BEGIN
  SELECT * INTO v_d FROM public.disputes WHERE id = p_dispute_id;
  SELECT * INTO v_o FROM public.orders WHERE id = v_d.order_id;
  IF p_amount < 0 OR p_amount > v_o.total_amount THEN
    RAISE EXCEPTION 'Refund must be between PHP 0 and the order total.';
  END IF;
  UPDATE public.disputes SET refund_amount = p_amount, status = 'resolved',
         resolution_notes = p_note, updated_at = now()
  WHERE id = p_dispute_id;
  IF p_amount > 0 THEN
    INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
    VALUES (v_o.owner_id, v_o.id, -p_amount, 'REFUND', 'Refund for reported problem');
    UPDATE public.profiles SET flagged_count = coalesce(flagged_count, 0) + 1 WHERE id = v_o.owner_id;
    IF p_amount >= v_o.total_amount THEN
      UPDATE public.orders SET payment_status = 'refunded' WHERE id = v_o.id;
    END IF;
  END IF;
  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (v_d.reporter_id, 'system_alert', 'high',
    CASE WHEN p_amount > 0 THEN 'Refund approved' ELSE 'Your report was reviewed' END,
    CASE WHEN p_amount > 0
      THEN 'PHP ' || trim(to_char(p_amount, '999990.00')) || ' will be returned '
        || CASE WHEN lower(coalesce(v_o.payment_method, 'cod')) IN ('cod', 'cash')
                THEN 'by the station in cash.' ELSE 'to your original payment method.' END
      ELSE coalesce(p_note, 'No refund was given.') END,
    jsonb_build_object('dispute_id', p_dispute_id, 'order_id', v_o.id, 'refund_amount', p_amount));
END; $$;
REVOKE ALL ON FUNCTION public.apply_dispute_refund(uuid, numeric, text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.owner_respond_dispute(
  p_dispute_id uuid, p_accept boolean, p_response text, p_refund_amount numeric DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_d public.disputes%ROWTYPE;
BEGIN
  SELECT d.* INTO v_d FROM public.disputes d JOIN public.orders o ON o.id = d.order_id
  WHERE d.id = p_dispute_id AND o.owner_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Dispute not found.'; END IF;
  IF v_d.status::text <> 'open' OR v_d.owner_responded_at IS NOT NULL THEN
    RAISE EXCEPTION 'This dispute was already answered.';
  END IF;
  IF coalesce(trim(p_response), '') = '' THEN RAISE EXCEPTION 'Write a reply to the customer.'; END IF;

  UPDATE public.disputes SET owner_response = trim(p_response), owner_responded_at = now(), updated_at = now()
  WHERE id = p_dispute_id;

  IF p_accept THEN
    PERFORM public.apply_dispute_refund(p_dispute_id, coalesce(p_refund_amount, 0), 'Station: ' || trim(p_response));
    RETURN jsonb_build_object('status', 'resolved');
  END IF;

  UPDATE public.disputes SET status = 'investigating', escalated_at = now() WHERE id = p_dispute_id;
  RETURN jsonb_build_object('status', 'investigating');
END; $$;

CREATE OR REPLACE FUNCTION public.escalate_dispute(p_dispute_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  UPDATE public.disputes SET status = 'investigating', escalated_at = now(), updated_at = now()
  WHERE id = p_dispute_id AND reporter_id = auth.uid() AND status = 'open'
    AND owner_responded_at IS NULL AND created_at < now() - interval '24 hours';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'You can ask eRefill to step in 24 hours after reporting if the station has not replied.';
  END IF;
  RETURN jsonb_build_object('status', 'investigating');
END; $$;

CREATE OR REPLACE FUNCTION public.admin_resolve_dispute(
  p_dispute_id uuid, p_refund_amount numeric, p_notes text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.disputes WHERE id = p_dispute_id AND status IN ('open', 'investigating')) THEN
    RAISE EXCEPTION 'This dispute is already closed.';
  END IF;
  UPDATE public.disputes SET resolved_by = auth.uid() WHERE id = p_dispute_id;
  PERFORM public.apply_dispute_refund(p_dispute_id, coalesce(p_refund_amount, 0), p_notes);
  IF coalesce(p_refund_amount, 0) = 0 THEN
    UPDATE public.disputes SET status = 'dismissed' WHERE id = p_dispute_id;
  END IF;
  RETURN jsonb_build_object('status', CASE WHEN coalesce(p_refund_amount, 0) > 0 THEN 'resolved' ELSE 'dismissed' END);
END; $$;

REVOKE ALL ON FUNCTION public.open_dispute(uuid, text, text, text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.open_dispute(uuid, text, text, text[]) TO authenticated;
REVOKE ALL ON FUNCTION public.owner_respond_dispute(uuid, boolean, text, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.owner_respond_dispute(uuid, boolean, text, numeric) TO authenticated;
REVOKE ALL ON FUNCTION public.escalate_dispute(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.escalate_dispute(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_resolve_dispute(uuid, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_resolve_dispute(uuid, numeric, text) TO authenticated;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- AI ordering assistant: per-user daily message limit (2026-11-05)
-- ==============================================================================
-- The order-assistant Edge Function records one row per message (with the
-- service role) and refuses more than 20 per user in 24 hours.
-- Users can read their own usage; nobody writes from the app.
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.assistant_usage (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  input_tokens integer NOT NULL DEFAULT 0,
  output_tokens integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_assistant_usage_user_time ON public.assistant_usage (user_id, created_at DESC);

ALTER TABLE public.assistant_usage ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users read own assistant usage" ON public.assistant_usage;
CREATE POLICY "Users read own assistant usage" ON public.assistant_usage
  FOR SELECT TO authenticated USING (user_id = auth.uid());
REVOKE INSERT, UPDATE, DELETE ON public.assistant_usage FROM anon, authenticated;
GRANT SELECT ON public.assistant_usage TO authenticated;

-- Shared fixtures for the SQL tests in this folder. Every test runs as
--   BEGIN; <scripts under test, BEGIN/COMMIT stripped>; _fixtures.sql; <test>; ROLLBACK;
-- through the Supabase MCP execute_sql tool, so nothing persists.
--
-- Fixture rows are inserted with triggers off (replica role) to skip station
-- setup checks; triggers are back on before the test body runs.
--
-- ids: owner ...a1, second owner ...a2, customer ...c1, rider ...d1,
--      admin ...e1, product ...b1 (₱19.60, owner a1).

SET LOCAL session_replication_role = replica;

INSERT INTO auth.users (id, instance_id, aud, role, email, raw_user_meta_data, raw_app_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_owner@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000a2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_owner2@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_cust@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_rider@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_admin@example.test', '{}', '{}', now(), now());

INSERT INTO public.profiles (id, role, full_name, station_name, station_availability, latitude, longitude)
VALUES
  ('00000000-0000-4000-8000-0000000000a1', 'owner', 'T Owner', 'T Station', 'open', 14.60, 121.00),
  ('00000000-0000-4000-8000-0000000000a2', 'owner', 'T Owner 2', 'T Station 2', 'open', 14.61, 121.01),
  ('00000000-0000-4000-8000-0000000000c1', 'customer', 'T Cust', NULL, 'open', 14.62, 121.02),
  ('00000000-0000-4000-8000-0000000000d1', 'rider', 'T Rider', NULL, 'open', NULL, NULL),
  ('00000000-0000-4000-8000-0000000000e1', 'admin', 'T Admin', NULL, 'open', NULL, NULL);

INSERT INTO public.owner_settings (owner_id, base_delivery_fee)
VALUES
  ('00000000-0000-4000-8000-0000000000a1', 5.4),
  ('00000000-0000-4000-8000-0000000000a2', 0);

INSERT INTO public.products (id, owner_id, name, price, is_available)
VALUES ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000a1', 'T Water', 19.6, true);

-- Fee config used by every test unless a test overrides it.
UPDATE public.system_config SET value = '{"enabled": true, "percent": 1, "fixed": 0}'::jsonb
WHERE key = 'platform_fee';

SET LOCAL session_replication_role = origin;

-- Helpers (temporary: dropped with the transaction).
CREATE OR REPLACE FUNCTION pg_temp.act_as(p_user uuid) RETURNS void
LANGUAGE sql AS $$
  SELECT set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text,
    true
  );
$$;

CREATE OR REPLACE FUNCTION pg_temp.place_order(p_method text, p_qty integer DEFAULT 1)
RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  RETURN public.create_order_atomic(
    jsonb_build_object(
      'owner_id', '00000000-0000-4000-8000-0000000000a1',
      'payment_method', p_method,
      'customer_name', 'T Cust',
      'customer_address', 'Test address',
      'customer_latitude', '14.6',
      'customer_longitude', '121.0'
    ),
    jsonb_build_array(jsonb_build_object(
      'product_id', '00000000-0000-4000-8000-0000000000b1',
      'quantity', p_qty,
      'product_name', 'T Water'
    ))
  );
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.assert_eq(p_label text, p_actual anyelement, p_expected anyelement)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF p_actual IS DISTINCT FROM p_expected THEN
    RAISE EXCEPTION '% — expected %, got %', p_label, p_expected, p_actual;
  END IF;
END;
$$;

-- Runs p_sql and fails unless it raises an error containing p_message.
CREATE OR REPLACE FUNCTION pg_temp.expect_error(p_label text, p_sql text, p_message text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    IF position(p_message IN SQLERRM) = 0 THEN
      RAISE EXCEPTION '% — expected error "%", got "%"', p_label, p_message, SQLERRM;
    END IF;
    RETURN;
  END;
  RAISE EXCEPTION '% — expected error "%", but it succeeded', p_label, p_message;
END;
$$;
-- Run: bash build.sh ../scripts/harden_signup_and_protected_columns.sql ../scripts/identity_verification.sql ../scripts/water_quality_certs.sql -- water_quality_certs_test.sql

-- owner_submits_and_admin_approves
DO $$ DECLARE v jsonb; BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
  v := public.submit_station_certification('bacteriological', current_date - 30, current_date + 150,
         '00000000-0000-4000-8000-0000000000a1/certs/lab.pdf');

  -- not public while pending
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1'); SET LOCAL ROLE authenticated;
  PERFORM pg_temp.assert_eq('hidden pending', (SELECT count(*) FROM public.station_certifications), 0::bigint);
  RESET ROLE;

  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000e1');
  PERFORM public.admin_review_station_certification((v->>'id')::uuid, true);

  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1'); SET LOCAL ROLE authenticated;
  PERFORM pg_temp.assert_eq('public approved', (SELECT count(*) FROM public.station_certifications), 1::bigint);
  RESET ROLE;
END $$;

-- path_must_be_own_certs_folder
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
  PERFORM pg_temp.expect_error('path',
    $q$SELECT public.submit_station_certification('sanitary_permit', current_date - 1, current_date + 100,
       '00000000-0000-4000-8000-0000000000a1/front.jpg')$q$, 'Upload the certificate file first');
END $$;

-- expired_cert_rejected_on_submit
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
  PERFORM pg_temp.expect_error('expired',
    $q$SELECT public.submit_station_certification('sanitary_permit', current_date - 400, current_date - 1,
       '00000000-0000-4000-8000-0000000000a1/certs/old.pdf')$q$, 'already expired');
END $$;

-- daily_job_expires_and_warns
DO $$ BEGIN
  UPDATE public.station_certifications SET expires_on = current_date + 10, issued_on = current_date - 300;
  PERFORM public.expire_station_certifications();
  PERFORM pg_temp.assert_eq('warned',
    (SELECT count(*) FROM public.system_notifications
     WHERE user_id = '00000000-0000-4000-8000-0000000000a1' AND title = 'Certificate expiring soon'), 1::bigint);
  UPDATE public.station_certifications SET expires_on = current_date;
  PERFORM public.expire_station_certifications();
  PERFORM pg_temp.assert_eq('expired',
    (SELECT status FROM public.station_certifications LIMIT 1), 'expired');
END $$;

SELECT 'water_quality_certs_test: all passed' AS result;
ROLLBACK;

-- ===== order_disputes_test =====
BEGIN;
-- ==============================================================================
-- Harden signup roles and protect trust columns on profiles (2026-11-05)
-- ==============================================================================
-- 1. Self-signup could claim role 'admin' or 'rider' through user metadata.
--    Only accounts created by a trusted server function (admin_create_user,
--    create_rider_account, admin_create_station) may get privileged roles.
--    Self-signups arrive through the Auth server, whose session user is
--    supabase_auth_admin; those are limited to customer/owner.
-- 2. Users could UPDATE their own average_rating / review_count /
--    reliability_score / flagged_count. Those are now writable only by admins
--    or by SECURITY DEFINER functions (e.g. update_station_stats()).
-- 3. Adds profiles.verification_status (used by identity verification), which is
--    protected the same way.
--
-- Run after: single_water_product_catalog.sql. Test: supabase/tests/protected_columns_test.sql
-- ==============================================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS verification_status text NOT NULL DEFAULT 'unverified';
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_verification_status_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_verification_status_check
  CHECK (verification_status IN ('unverified', 'pending', 'approved', 'rejected'));

-- 1. Role resolution -----------------------------------------------------------
CREATE OR REPLACE FUNCTION public.resolve_signup_role(p_requested text, p_trusted boolean)
RETURNS public.user_role
LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN p_requested IN ('customer', 'owner') THEN p_requested::public.user_role
    WHEN p_trusted AND p_requested IN ('rider', 'admin') THEN p_requested::public.user_role
    ELSE 'customer'::public.user_role
  END;
$$;
REVOKE ALL ON FUNCTION public.resolve_signup_role(text, boolean) FROM PUBLIC, anon, authenticated;

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
  -- 1. Role: self-signups (Auth server session) may only be customer or owner.
  v_role := public.resolve_signup_role(
    new.raw_user_meta_data->>'role',
    session_user <> 'supabase_auth_admin'
  );

  -- 2. Safe municipality enum resolution
  IF lower(trim(COALESCE(new.raw_user_meta_data->>'town', ''))) = 'cantilan' THEN
    v_town := 'Cantilan'::public.municipality;
  ELSIF lower(trim(COALESCE(new.raw_user_meta_data->>'town', ''))) = 'madrid' THEN
    v_town := 'Madrid'::public.municipality;
  ELSE
    v_town := NULL;
  END IF;

  v_complete_address := NULLIF(TRIM(COALESCE(new.raw_user_meta_data->>'complete_address', '')), '');

  -- 3. Names (Google OAuth sends 'name', 'given_name', 'family_name', 'picture')
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

  -- 5. Upsert profile
  INSERT INTO public.profiles (
    id, email, username, full_name, first_name, last_name, mi, suffix, role,
    phone, town, barangay, complete_address, landmark, station_name,
    avatar_url, latitude, longitude, primary_water_type
  )
  VALUES (
    new.id, new.email, v_username, v_full_name, v_first_name, v_last_name,
    new.raw_user_meta_data->>'mi', new.raw_user_meta_data->>'suffix', v_role,
    new.raw_user_meta_data->>'phone', v_town, new.raw_user_meta_data->>'barangay',
    v_complete_address, new.raw_user_meta_data->>'landmark',
    new.raw_user_meta_data->>'station_name', v_avatar_url,
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

-- 2. Protected trust columns -----------------------------------------------------
-- SECURITY INVOKER on purpose: current_user is 'authenticated'/'anon' for direct
-- client writes, and the function owner (postgres) inside SECURITY DEFINER
-- functions such as update_station_stats() and the admin RPCs.
CREATE OR REPLACE FUNCTION public.guard_profile_protected_columns()
RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;

  IF NEW.average_rating IS NOT DISTINCT FROM OLD.average_rating
    AND NEW.review_count IS NOT DISTINCT FROM OLD.review_count
    AND NEW.reliability_score IS NOT DISTINCT FROM OLD.reliability_score
    AND NEW.flagged_count IS NOT DISTINCT FROM OLD.flagged_count
    AND NEW.verification_status IS NOT DISTINCT FROM OLD.verification_status
  THEN
    RETURN NEW;
  END IF;

  IF public.is_admin() THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'Unauthorized: You cannot alter protected account fields.';
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_profile_protected_columns ON public.profiles;
CREATE TRIGGER trg_guard_profile_protected_columns
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.guard_profile_protected_columns();


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Delivery coverage: free-delivery zones + distance-based fees (2026-11-05)
-- ==============================================================================
-- Each station defines where delivery is free:
--   * within free_delivery_radius_km of the station (default 1 km), OR
--   * to any barangay listed in free_delivery_barangays, OR
--   * when the order has at least free_delivery_min_gallons water gallons.
-- Everywhere else pays the platform's per-km rate from
-- system_config.delivery_fee_config (rate_per_km, minimum_fee,
-- min_billable_distance_km, rounding_rule, enabled).
--
-- Distance = straight-line (haversine) x 1.3 road factor, so it approximates
-- real road distance without calling a routing service from the database.
--
-- Self-contained: does not depend on delivery_fee_config_rpcs.sql.
-- Run before: order_pricing_v3.sql. Test: supabase/tests/delivery_quote_test.sql
-- ==============================================================================

ALTER TABLE public.owner_settings
  ADD COLUMN IF NOT EXISTS free_delivery_radius_km numeric(4,1) NOT NULL DEFAULT 1.0,
  ADD COLUMN IF NOT EXISTS free_delivery_barangays text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS free_delivery_min_gallons integer;

ALTER TABLE public.owner_settings DROP CONSTRAINT IF EXISTS owner_settings_free_radius_check;
ALTER TABLE public.owner_settings ADD CONSTRAINT owner_settings_free_radius_check
  CHECK (free_delivery_radius_km >= 0 AND free_delivery_radius_km <= 10);
ALTER TABLE public.owner_settings DROP CONSTRAINT IF EXISTS owner_settings_free_min_gallons_check;
ALTER TABLE public.owner_settings ADD CONSTRAINT owner_settings_free_min_gallons_check
  CHECK (free_delivery_min_gallons IS NULL OR free_delivery_min_gallons BETWEEN 1 AND 100);

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS delivery_distance_km numeric(6,2),
  ADD COLUMN IF NOT EXISTS delivery_rate_per_km numeric(8,2),
  ADD COLUMN IF NOT EXISTS delivery_free_reason text;

-- Road factor applied to straight-line distance.
CREATE OR REPLACE FUNCTION public.delivery_road_distance_km(
  p_lat1 double precision, p_lng1 double precision,
  p_lat2 double precision, p_lng2 double precision
) RETURNS numeric
LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN p_lat1 IS NULL OR p_lng1 IS NULL OR p_lat2 IS NULL OR p_lng2 IS NULL THEN NULL
    ELSE round((
      2 * 6371 * asin(sqrt(
        power(sin(radians(p_lat2 - p_lat1) / 2), 2)
        + cos(radians(p_lat1)) * cos(radians(p_lat2))
          * power(sin(radians(p_lng2 - p_lng1) / 2), 2)
      )) * 1.3
    )::numeric, 2)
  END;
$$;

-- Fee for a distance outside the free zone, from the admin's config.
CREATE OR REPLACE FUNCTION public.delivery_fee_for_distance(p_km numeric)
RETURNS numeric
LANGUAGE plpgsql STABLE SET search_path TO 'public' AS $$
DECLARE
  v_cfg jsonb;
  v_rate numeric;
  v_min numeric;
  v_min_km numeric;
  v_rule text;
  v_fee numeric;
BEGIN
  SELECT value INTO v_cfg FROM public.system_config WHERE key = 'delivery_fee_config';
  v_cfg := coalesce(v_cfg, '{}'::jsonb);
  IF NOT coalesce((v_cfg->>'enabled')::boolean, true) THEN
    RETURN 0;
  END IF;
  v_rate := greatest(coalesce((v_cfg->>'rate_per_km')::numeric, 10), 0);
  v_min := greatest(coalesce((v_cfg->>'minimum_fee')::numeric, 20), 0);
  v_min_km := greatest(coalesce((v_cfg->>'min_billable_distance_km')::numeric, 1), 0);
  v_rule := lower(trim(coalesce(v_cfg->>'rounding_rule', 'exact')));

  IF p_km IS NULL THEN
    RETURN v_min;
  END IF;

  -- Same rule as CheckoutRules.calculateDeliveryFee in the app: the rounding
  -- rule applies to the billable distance; the fee is whole pesos.
  v_fee := greatest(p_km, v_min_km);
  v_fee := CASE
    WHEN v_rule IN ('ceil', 'round_up') THEN ceil(v_fee)
    WHEN v_rule IN ('round', 'round_nearest') THEN round(v_fee)
    ELSE v_fee
  END;
  IF v_rate <= 0 THEN
    RETURN 0;
  END IF;
  RETURN round(greatest(v_rate * v_fee, v_min));
END;
$$;

-- Quote shown at checkout and charged by create_order_atomic.
CREATE OR REPLACE FUNCTION public.compute_delivery_quote(
  p_station_id uuid,
  p_lat double precision,
  p_lng double precision,
  p_barangay text DEFAULT NULL,
  p_gallons integer DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_slat double precision;
  v_slng double precision;
  v_radius numeric;
  v_barangays text[];
  v_min_gallons integer;
  v_km numeric;
  v_reason text;
  v_cfg jsonb;
BEGIN
  SELECT coalesce(p.latitude, p.lat), coalesce(p.longitude, p.lng)
  INTO v_slat, v_slng
  FROM public.profiles p
  WHERE p.id = p_station_id AND p.role = 'owner';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Water refill station not found.';
  END IF;

  SELECT coalesce(os.free_delivery_radius_km, 1.0),
         coalesce(os.free_delivery_barangays, '{}'),
         os.free_delivery_min_gallons
  INTO v_radius, v_barangays, v_min_gallons
  FROM public.owner_settings os WHERE os.owner_id = p_station_id;
  v_radius := coalesce(v_radius, 1.0);
  v_barangays := coalesce(v_barangays, '{}');

  v_km := public.delivery_road_distance_km(v_slat, v_slng, p_lat, p_lng);

  IF v_km IS NOT NULL AND v_km <= v_radius THEN
    v_reason := 'radius';
  ELSIF p_barangay IS NOT NULL AND EXISTS (
    SELECT 1 FROM unnest(v_barangays) b
    WHERE lower(trim(b)) = lower(trim(p_barangay))
  ) THEN
    v_reason := 'barangay';
  ELSIF v_min_gallons IS NOT NULL AND coalesce(p_gallons, 0) >= v_min_gallons THEN
    v_reason := 'min_gallons';
  END IF;

  SELECT value INTO v_cfg FROM public.system_config WHERE key = 'delivery_fee_config';

  RETURN jsonb_build_object(
    'distance_km', v_km,
    'is_free', v_reason IS NOT NULL,
    'free_reason', v_reason,
    'fee', CASE WHEN v_reason IS NOT NULL THEN 0 ELSE public.delivery_fee_for_distance(v_km) END,
    'rate_per_km', coalesce((v_cfg->>'rate_per_km')::numeric, 10),
    'minimum_fee', coalesce((v_cfg->>'minimum_fee')::numeric, 20),
    'free_radius_km', v_radius,
    'free_barangays', to_jsonb(v_barangays),
    'free_min_gallons', v_min_gallons
  );
END;
$$;

REVOKE ALL ON FUNCTION public.compute_delivery_quote(uuid, double precision, double precision, text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.compute_delivery_quote(uuid, double precision, double precision, text, integer) TO authenticated;
REVOKE ALL ON FUNCTION public.delivery_fee_for_distance(numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delivery_fee_for_distance(numeric) TO authenticated;


NOTIFY pgrst, 'reload schema';
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


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Rider tips (2026-11-05)
-- ==============================================================================
-- Customers can add an optional tip (₱0–₱500, whole pesos) at checkout for
-- delivery orders. It is part of the single charge (COD or PayMongo), so no
-- second payment is needed, and 100% goes to the rider:
--   * excluded from the station SALE and from the 10% commission base
--   * booked as a RIDER_TIP ledger entry to the assigned rider
--   * if no rider was assigned (station delivered itself) it stays with the
--     station as part of the SALE
-- create_order_atomic reads p_order_data->>'tip_amount' (order_pricing_v3.sql).
--
-- Run before: order_pricing_v3.sql. Test: supabase/tests/rider_tips_test.sql
-- ==============================================================================

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS tip_amount numeric(10,2) NOT NULL DEFAULT 0;
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_tip_amount_check;
ALTER TABLE public.orders ADD CONSTRAINT orders_tip_amount_check
  CHECK (tip_amount >= 0 AND tip_amount <= 500);

CREATE OR REPLACE FUNCTION public.proc_finalize_order_finances()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    v_commission NUMERIC;
    v_fee NUMERIC := greatest(coalesce(NEW.platform_fee, 0), 0);
    v_tip NUMERIC := greatest(coalesce(NEW.tip_amount, 0), 0);
    v_rider_tip NUMERIC := 0;
BEGIN
    IF NEW.status = 'delivered' AND OLD.status != 'delivered' THEN
        -- The tip belongs to the rider; without a rider it stays in the sale.
        IF NEW.assigned_rider_id IS NOT NULL THEN
            v_rider_tip := v_tip;
        END IF;

        INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
        VALUES (NEW.owner_id, NEW.id, NEW.total_amount - v_fee - v_rider_tip, 'SALE', 'Order completion payment');

        IF v_fee > 0 THEN
            INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description, metadata)
            VALUES (
                NEW.owner_id, NEW.id, v_fee, 'SERVICE_FEE', 'Platform service fee',
                jsonb_build_object('payee', 'platform', 'payment_method', NEW.payment_method)
            );

            IF lower(coalesce(NEW.payment_method, 'cod')) IN ('cod', 'cash', 'credit') THEN
                PERFORM public.apply_wallet_entry(
                    NEW.owner_id, -v_fee, 'service_fee', NEW.id, NULL,
                    'Service fee for order ' || upper(substr(NEW.id::text, 1, 8))
                );
            END IF;
        END IF;

        -- Commission excludes the tip.
        v_commission := (NEW.total_amount - v_tip) * 0.10;

        IF NEW.assigned_rider_id IS NOT NULL THEN
            INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
            VALUES (NEW.assigned_rider_id, NEW.id, v_commission, 'COMMISSION', 'Delivery commission for order');

            IF v_rider_tip > 0 THEN
                INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
                VALUES (NEW.assigned_rider_id, NEW.id, v_rider_tip, 'RIDER_TIP', 'Customer tip');

                INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
                VALUES (
                    NEW.assigned_rider_id, 'system_alert', 'normal', 'You got a tip!',
                    'A customer tipped you PHP ' || trim(to_char(v_rider_tip, '999990')) || '. Thank you for the great service.',
                    jsonb_build_object('order_id', NEW.id, 'tip_amount', v_rider_tip)
                );
            END IF;
        END IF;

        INSERT INTO public.domain_events (event_type, payload, actor_id)
        VALUES ('ORDER_COMPLETED', jsonb_build_object(
            'order_id', NEW.id, 'total', NEW.total_amount,
            'rider_id', NEW.assigned_rider_id, 'tip', v_tip), auth.uid());
    END IF;
    RETURN NEW;
END;
$$;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Seller and customer ID verification (2026-11-05)
-- ==============================================================================
-- Users upload a government ID (front, back, selfie; owners also a business
-- permit) to the private bucket verification_docs under <their uid>/.
-- An admin reviews and approves or rejects. profiles.verification_status
-- (added and write-protected by harden_signup_and_protected_columns.sql) is
-- only changed by the RPCs below.
--
-- Gates (enforced in create_order_atomic, order_pricing_v3.sql):
--   * stations must be 'approved' to receive orders
--   * unverified customers: cash-on-delivery up to PHP 1,000 and at most
--     2 active COD orders; verified customers have no limit
-- Backfill: owners who already completed a delivery are approved (legacy).
--
-- Run after: harden_signup_and_protected_columns.sql
-- Run before: order_pricing_v3.sql. Test: supabase/tests/identity_verification_test.sql
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.identity_verifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role text NOT NULL,
  id_type text NOT NULL CHECK (id_type IN (
    'philsys', 'drivers_license', 'umid', 'passport', 'postal', 'voters', 'prc', 'other')),
  id_number_last4 text CHECK (id_number_last4 ~ '^[0-9A-Za-z]{4}$'),
  front_path text NOT NULL,
  back_path text,
  selfie_path text NOT NULL,
  business_permit_path text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  reviewer_id uuid REFERENCES public.profiles(id),
  reviewed_at timestamptz,
  rejection_reason text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_identity_verifications_user ON public.identity_verifications (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_identity_verifications_pending ON public.identity_verifications (created_at) WHERE status = 'pending';

ALTER TABLE public.identity_verifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users read own verifications" ON public.identity_verifications;
CREATE POLICY "Users read own verifications" ON public.identity_verifications
  FOR SELECT TO authenticated USING (auth.uid() = user_id OR public.is_admin());
-- Writes only through the RPCs below.
REVOKE INSERT, UPDATE, DELETE ON public.identity_verifications FROM anon, authenticated;
GRANT SELECT ON public.identity_verifications TO authenticated;

-- Private bucket, one folder per user.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('verification_docs', 'verification_docs', false, 8388608,
        ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
ON CONFLICT (id) DO UPDATE SET public = false;

DROP POLICY IF EXISTS "Verification docs: owner upload" ON storage.objects;
CREATE POLICY "Verification docs: owner upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'verification_docs' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "Verification docs: owner or admin read" ON storage.objects;
CREATE POLICY "Verification docs: owner or admin read" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'verification_docs'
         AND ((storage.foldername(name))[1] = auth.uid()::text OR public.is_admin()));

CREATE OR REPLACE FUNCTION public.submit_identity_verification(
  p_id_type text,
  p_id_number_last4 text,
  p_front_path text,
  p_back_path text,
  p_selfie_path text,
  p_business_permit_path text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_role text;
  v_status text;
  v_prefix text;
  v_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required.'; END IF;
  SELECT role::text, verification_status INTO v_role, v_status FROM public.profiles WHERE id = v_uid;
  IF v_role NOT IN ('customer', 'owner') THEN
    RAISE EXCEPTION 'Only customers and station owners verify their ID here.';
  END IF;
  IF v_status = 'approved' THEN RAISE EXCEPTION 'Your ID is already verified.'; END IF;
  IF v_status = 'pending' THEN RAISE EXCEPTION 'Your ID is already being reviewed.'; END IF;

  v_prefix := v_uid::text || '/';
  IF p_front_path IS NULL OR p_selfie_path IS NULL
     OR left(p_front_path, length(v_prefix)) <> v_prefix
     OR left(p_selfie_path, length(v_prefix)) <> v_prefix
     OR (p_back_path IS NOT NULL AND left(p_back_path, length(v_prefix)) <> v_prefix)
     OR (p_business_permit_path IS NOT NULL AND left(p_business_permit_path, length(v_prefix)) <> v_prefix) THEN
    RAISE EXCEPTION 'Upload your ID photos before submitting.';
  END IF;
  IF v_role = 'owner' AND p_business_permit_path IS NULL THEN
    RAISE EXCEPTION 'Stations must also upload a business or sanitary permit.';
  END IF;

  INSERT INTO public.identity_verifications (
    user_id, role, id_type, id_number_last4, front_path, back_path, selfie_path, business_permit_path)
  VALUES (v_uid, v_role, p_id_type, NULLIF(p_id_number_last4, ''), p_front_path, p_back_path,
          p_selfie_path, p_business_permit_path)
  RETURNING id INTO v_id;

  UPDATE public.profiles SET verification_status = 'pending' WHERE id = v_uid;
  RETURN jsonb_build_object('id', v_id, 'status', 'pending');
END; $$;

CREATE OR REPLACE FUNCTION public.admin_review_identity_verification(
  p_verification_id uuid,
  p_approve boolean,
  p_reason text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_row public.identity_verifications%ROWTYPE;
  v_status text := CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  IF NOT p_approve AND coalesce(trim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'Give the user a reason for the rejection.';
  END IF;

  UPDATE public.identity_verifications
  SET status = v_status, reviewer_id = auth.uid(), reviewed_at = now(),
      rejection_reason = CASE WHEN p_approve THEN NULL ELSE trim(p_reason) END
  WHERE id = p_verification_id AND status = 'pending'
  RETURNING * INTO v_row;
  IF NOT FOUND THEN RAISE EXCEPTION 'This verification was already reviewed.'; END IF;

  UPDATE public.profiles SET verification_status = v_status WHERE id = v_row.user_id;

  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (
    v_row.user_id, 'system_alert', 'high',
    CASE WHEN p_approve THEN 'Your ID is verified' ELSE 'ID verification needs another try' END,
    CASE WHEN p_approve
      THEN CASE WHEN v_row.role = 'owner'
        THEN 'Your station is verified and can now receive orders.'
        ELSE 'Your account is verified. Order limits are lifted.' END
      ELSE 'Reason: ' || trim(p_reason) || '. You can submit new photos.' END,
    jsonb_build_object('verification_id', v_row.id, 'status', v_status)
  );

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, new_value, metadata)
  VALUES (auth.uid(), 'identity_verification_' || v_status, 'identity_verifications', v_row.id::text,
          jsonb_build_object('status', v_status),
          jsonb_build_object('user_id', v_row.user_id, 'reason', p_reason));

  RETURN jsonb_build_object('id', v_row.id, 'status', v_status);
END; $$;

REVOKE ALL ON FUNCTION public.submit_identity_verification(text, text, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_identity_verification(text, text, text, text, text, text) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_review_identity_verification(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_review_identity_verification(uuid, boolean, text) TO authenticated;

-- Order gate helper, used by create_order_atomic.
CREATE OR REPLACE FUNCTION public.assert_order_allowed_by_verification(
  p_customer_id uuid, p_owner_id uuid, p_payment_method text, p_total numeric
) RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_owner_status text;
  v_customer_status text;
  v_active int;
BEGIN
  SELECT verification_status INTO v_owner_status FROM public.profiles WHERE id = p_owner_id;
  IF coalesce(v_owner_status, 'unverified') <> 'approved' THEN
    RAISE EXCEPTION 'This station is not verified yet and cannot take orders.';
  END IF;

  SELECT verification_status INTO v_customer_status FROM public.profiles WHERE id = p_customer_id;
  IF coalesce(v_customer_status, 'unverified') = 'approved'
     OR lower(coalesce(p_payment_method, 'cod')) NOT IN ('cod', 'cash') THEN
    RETURN;
  END IF;

  IF p_total > 1000 THEN
    RAISE EXCEPTION 'Verify your ID to place cash-on-delivery orders above PHP 1,000.';
  END IF;
  SELECT count(*) INTO v_active FROM public.orders
  WHERE customer_id = p_customer_id
    AND lower(coalesce(payment_method, 'cod')) IN ('cod', 'cash')
    AND status NOT IN ('delivered', 'cancelled', 'failed');
  IF v_active >= 2 THEN
    RAISE EXCEPTION 'Verify your ID to have more than 2 cash-on-delivery orders at a time.';
  END IF;
END; $$;
REVOKE ALL ON FUNCTION public.assert_order_allowed_by_verification(uuid, uuid, text, numeric) FROM PUBLIC, anon, authenticated;

-- Backfill: stations that already delivered orders keep working.
UPDATE public.profiles p SET verification_status = 'approved'
WHERE p.role = 'owner' AND p.verification_status = 'unverified'
  AND EXISTS (SELECT 1 FROM public.orders o WHERE o.owner_id = p.id AND o.status = 'delivered');


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- create_order_atomic v3 (2026-11-05)
-- ==============================================================================
-- Starts from the LIVE definition (pg_get_functiondef on 2026-11-05; note the
-- live function does not use price_order() from whole_peso_pricing.sql).
-- Changes:
--   * Delivery fee comes from compute_delivery_quote() (free zone or per-km),
--     never from the client and no longer from owner_settings.base_delivery_fee.
--   * Writes delivery_distance_km, delivery_rate_per_km, delivery_free_reason.
--   * Accessories (products.kind = 'accessory') are sold alongside water;
--     only water gallons count toward the free-delivery gallon threshold.
--   * Optional rider tip (tip_amount, ₱0–₱500) added to the total.
--   * ID verification gates: approved stations only; COD limits for
--     unverified customers.
-- This is the single place later features (accessories, tips, verification
-- gates) extend create_order_atomic. Do not redefine it in other scripts.
--
-- Run order: harden_signup_and_protected_columns.sql -> delivery_coverage.sql ->
--   station_accessories.sql -> rider_tips.sql -> identity_verification.sql -> this file.
-- Tests: supabase/tests/delivery_quote_test.sql, accessories_test.sql
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.create_order_atomic(p_order_data jsonb, p_items_data jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_customer_id uuid := auth.uid();
  v_owner_id uuid;
  v_payment_method text;
  v_idempotency_key public.orders.idempotency_key%TYPE;
  v_voucher_id uuid;
  v_order_id uuid;
  v_item record;
  v_product record;
  v_computed_subtotal numeric(10,2) := 0;
  v_delivery_fee numeric(10,2) := 0;
  v_platform_fee numeric(10,2) := 0;
  v_discount numeric(10,2) := 0;
  v_total_amount numeric(10,2) := 0;
  v_order_row public.orders%ROWTYPE;
  v_voucher public.customer_reward_vouchers%ROWTYPE;
  v_config jsonb;
  v_lat double precision;
  v_lng double precision;
  v_maintenance jsonb;
  v_is_maintenance boolean := false;
  v_customer_suspended boolean := false;
  v_owner_suspended boolean := false;
  v_gallons integer := 0;
  v_quote jsonb;
  v_tip numeric(10,2) := 0;
BEGIN
  SELECT value INTO v_maintenance
  FROM public.system_config
  WHERE key = 'maintenance_mode';

  IF v_maintenance IS NOT NULL THEN
    IF jsonb_typeof(v_maintenance) = 'boolean' THEN
      v_is_maintenance := v_maintenance::text::boolean;
    ELSIF jsonb_typeof(v_maintenance) = 'string' THEN
      v_is_maintenance :=
        lower(trim(both '"' from v_maintenance::text)) IN ('true', '1', 'yes');
    END IF;
  END IF;

  IF v_is_maintenance THEN
    RAISE EXCEPTION 'System is currently undergoing maintenance. New orders are temporarily paused.';
  END IF;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required to place an order.';
  END IF;

  SELECT coalesce(is_suspended, false) INTO v_customer_suspended
  FROM public.profiles
  WHERE id = v_customer_id AND role = 'customer';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Only customer accounts can place orders.';
  END IF;
  IF v_customer_suspended THEN
    RAISE EXCEPTION 'Your account has been suspended. Please contact customer support.';
  END IF;

  v_idempotency_key := NULLIF(p_order_data->>'idempotency_key', '');
  IF v_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_order_row
    FROM public.orders
    WHERE customer_id = v_customer_id
      AND idempotency_key = v_idempotency_key;

    IF FOUND THEN
      RETURN jsonb_build_object(
        'id', v_order_row.id,
        'subtotal', v_order_row.subtotal,
        'delivery_fee', v_order_row.delivery_fee,
        'platform_fee', v_order_row.platform_fee,
        'total_amount', v_order_row.total_amount,
        'status', v_order_row.status
      );
    END IF;
  END IF;

  v_owner_id := NULLIF(p_order_data->>'owner_id', '')::uuid;
  v_payment_method := lower(trim(coalesce(p_order_data->>'payment_method', 'cod')));
  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'Station owner ID is required.';
  END IF;

  SELECT coalesce(is_suspended, false) INTO v_owner_suspended
  FROM public.profiles
  WHERE id = v_owner_id AND role = 'owner';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Water refill station not found.';
  END IF;
  IF v_owner_suspended THEN
    RAISE EXCEPTION 'This water station is currently suspended by administration.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = v_owner_id
      AND role = 'owner'
      AND coalesce(station_availability, 'open') = 'open'
  ) THEN
    RAISE EXCEPTION 'This water station is currently closed or unavailable.';
  END IF;
  IF NOT public.is_station_payment_method_available(v_owner_id, v_payment_method) THEN
    RAISE EXCEPTION 'This payment method is not available for this station.';
  END IF;

  FOR v_item IN
    SELECT * FROM jsonb_to_recordset(p_items_data) AS x(
      product_id uuid,
      quantity integer,
      product_name text
    )
  LOOP
    IF v_item.quantity <= 0 THEN
      RAISE EXCEPTION 'Invalid quantity for item %', v_item.product_name;
    END IF;

    SELECT * INTO v_product
    FROM public.products
    WHERE id = v_item.product_id
      AND owner_id = v_owner_id
      AND is_available = true;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Product % is unavailable at this station.', v_item.product_name;
    END IF;

    v_computed_subtotal :=
      v_computed_subtotal + (v_product.price * v_item.quantity);
    -- Only water counts toward the free-delivery gallon threshold.
    IF v_product.kind = 'water' THEN
      v_gallons := v_gallons + v_item.quantity;
    END IF;
  END LOOP;

  IF v_computed_subtotal <= 0 THEN
    RAISE EXCEPTION 'Cart cannot be empty.';
  END IF;

  v_lat := NULLIF(p_order_data->>'customer_latitude', '')::double precision;
  v_lng := NULLIF(p_order_data->>'customer_longitude', '')::double precision;

  -- Delivery fee: server-side quote (free zone or per-km). Client fee ignored.
  v_quote := public.compute_delivery_quote(
    v_owner_id, v_lat, v_lng,
    NULLIF(p_order_data->>'customer_barangay', ''),
    v_gallons
  );
  v_delivery_fee := coalesce((v_quote->>'fee')::numeric, 0);

  v_config := public.get_platform_fee_config();
  IF coalesce((v_config->>'enabled')::boolean, false) THEN
    v_platform_fee := round(
      ((v_computed_subtotal + v_delivery_fee)
        * coalesce((v_config->>'percent')::numeric, 0) / 100)
        + coalesce((v_config->>'fixed')::numeric, 0),
      2
    );
    v_platform_fee := greatest(v_platform_fee, 0);
  END IF;

  v_voucher_id := NULLIF(p_order_data->>'voucher_id', '')::uuid;
  IF v_voucher_id IS NOT NULL THEN
    SELECT * INTO v_voucher
    FROM public.customer_reward_vouchers
    WHERE id = v_voucher_id
      AND user_id = v_customer_id
      AND is_used = false
      AND expires_at > now()
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'This reward voucher is no longer available. Refresh your vouchers and try again.';
    END IF;

    IF v_voucher.is_delivery_discount THEN
      v_discount := least(
        greatest(v_voucher.discount_amount, 0),
        v_delivery_fee
      );
    ELSE
      v_discount := least(
        greatest(v_voucher.discount_amount, 0),
        v_computed_subtotal + v_delivery_fee + v_platform_fee
      );
    END IF;
  END IF;

  -- Optional rider tip: whole pesos, ₱0–₱500, paid on top (no fees, no voucher).
  v_tip := round(coalesce(NULLIF(p_order_data->>'tip_amount', '')::numeric, 0));
  IF v_tip < 0 OR v_tip > 500 THEN
    RAISE EXCEPTION 'Tip must be between PHP 0 and PHP 500.';
  END IF;

  v_total_amount := greatest(
    v_computed_subtotal + v_delivery_fee + v_platform_fee - v_discount,
    0
  ) + v_tip;

  -- ID verification gates (identity_verification.sql).
  PERFORM public.assert_order_allowed_by_verification(
    v_customer_id, v_owner_id, v_payment_method, v_total_amount
  );

  INSERT INTO public.orders (
    id,
    customer_id,
    owner_id,
    station_name,
    customer_name,
    customer_phone,
    customer_address,
    customer_barangay,
    customer_municipality,
    customer_landmark,
    idempotency_key,
    subtotal,
    delivery_fee,
    platform_fee,
    total_amount,
    payment_method,
    payment_status,
    notes,
    region_id,
    customer_latitude,
    customer_longitude,
    delivery_lat,
    delivery_lng,
    delivery_latitude,
    delivery_longitude,
    delivery_distance_km,
    delivery_rate_per_km,
    delivery_free_reason,
    tip_amount,
    items,
    status
  ) VALUES (
    coalesce(
      NULLIF(p_order_data->>'id', '')::uuid,
      gen_random_uuid()
    ),
    v_customer_id,
    v_owner_id,
    coalesce(p_order_data->>'station_name', 'Water Station'),
    p_order_data->>'customer_name',
    p_order_data->>'customer_phone',
    p_order_data->>'customer_address',
    p_order_data->>'customer_barangay',
    p_order_data->>'customer_municipality',
    p_order_data->>'customer_landmark',
    v_idempotency_key,
    v_computed_subtotal,
    v_delivery_fee,
    v_platform_fee,
    v_total_amount,
    v_payment_method,
    'pending',
    p_order_data->>'notes',
    NULLIF(p_order_data->>'region_id', '')::uuid,
    v_lat,
    v_lng,
    v_lat,
    v_lng,
    v_lat,
    v_lng,
    (v_quote->>'distance_km')::numeric,
    (v_quote->>'rate_per_km')::numeric,
    v_quote->>'free_reason',
    v_tip,
    coalesce(p_items_data, '[]'::jsonb),
    'pending'
  )
  ON CONFLICT DO NOTHING
  RETURNING * INTO v_order_row;

  IF NOT FOUND THEN
    IF v_idempotency_key IS NOT NULL THEN
      SELECT * INTO v_order_row
      FROM public.orders
      WHERE customer_id = v_customer_id
        AND idempotency_key = v_idempotency_key;

      IF FOUND THEN
        RETURN jsonb_build_object(
          'id', v_order_row.id,
          'subtotal', v_order_row.subtotal,
          'delivery_fee', v_order_row.delivery_fee,
          'platform_fee', v_order_row.platform_fee,
          'total_amount', v_order_row.total_amount,
          'status', v_order_row.status
        );
      END IF;
    END IF;
    RAISE EXCEPTION 'Order could not be created because of a conflicting order record.';
  END IF;

  v_order_id := v_order_row.id;

  FOR v_item IN
    SELECT * FROM jsonb_to_recordset(p_items_data) AS x(
      product_id uuid,
      quantity integer,
      product_name text
    )
  LOOP
    SELECT * INTO v_product FROM public.products WHERE id = v_item.product_id;
    INSERT INTO public.order_items (
      order_id,
      product_id,
      product_name,
      quantity,
      price_at_purchase,
      subtotal
    ) VALUES (
      v_order_id,
      v_item.product_id,
      v_product.name,
      v_item.quantity,
      v_product.price,
      (v_product.price * v_item.quantity)
    );
  END LOOP;

  IF v_voucher_id IS NOT NULL THEN
    UPDATE public.customer_reward_vouchers
    SET is_used = true
    WHERE id = v_voucher_id
      AND user_id = v_customer_id
      AND is_used = false;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'This reward voucher was already used by another order.';
    END IF;
  END IF;

  INSERT INTO public.system_notifications (
    user_id,
    type,
    priority,
    title,
    content,
    metadata
  ) VALUES (
    v_owner_id,
    'system_alert',
    'high',
    'New Refill Order',
    coalesce(p_order_data->>'customer_name', 'A customer')
      || ' placed a new refill order of PHP '
      || trim(to_char(v_total_amount, '999999990.00'))
      || ' (' || upper(coalesce(p_order_data->>'payment_method', 'cod')) || ').',
    jsonb_build_object(
      'order_id', v_order_id,
      'status', 'pending',
      'total_amount', v_total_amount
    )
  );

  RETURN jsonb_build_object(
    'id', v_order_id,
    'subtotal', v_computed_subtotal,
    'delivery_fee', v_delivery_fee,
    'delivery_distance_km', (v_quote->>'distance_km')::numeric,
    'delivery_free_reason', v_quote->>'free_reason',
    'platform_fee', v_platform_fee,
    'discount_amount', v_discount,
    'tip_amount', v_tip,
    'total_amount', v_total_amount,
    'status', 'pending'
  );
END;
$function$;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Rider live location privacy (2026-11-05)
-- ==============================================================================
-- rider_locations was readable by everyone ("Public can view rider
-- locations"). Now only these can read a rider's points:
--   * the rider, admins
--   * the customer or station of an order that rider is delivering right now
--     (assigned_to_rider / out_for_delivery)
-- After delivery the customer loses access. Points older than 24 h are purged
-- hourly (pg_cron, when the extension is available).
-- Test: supabase/tests/rider_live_location_test.sql
-- ==============================================================================

DROP POLICY IF EXISTS "Public can view rider locations" ON public.rider_locations;
DROP POLICY IF EXISTS "Rider location visible to active delivery parties" ON public.rider_locations;
CREATE POLICY "Rider location visible to active delivery parties" ON public.rider_locations
  FOR SELECT TO authenticated
  USING (
    rider_id = auth.uid()
    OR public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.orders o
      WHERE (o.assigned_rider_id = rider_locations.rider_id OR o.rider_id = rider_locations.rider_id)
        AND o.status IN ('assigned_to_rider', 'out_for_delivery')
        AND (o.customer_id = auth.uid() OR o.owner_id = auth.uid())
    )
  );

DROP POLICY IF EXISTS "Riders can update their own location" ON public.rider_locations;
CREATE POLICY "Riders can update their own location" ON public.rider_locations
  FOR INSERT TO authenticated
  WITH CHECK (rider_id = auth.uid());
REVOKE ALL ON public.rider_locations FROM anon;

CREATE OR REPLACE FUNCTION public.purge_old_rider_locations()
RETURNS integer
LANGUAGE sql SECURITY DEFINER SET search_path TO 'public' AS $$
  WITH d AS (
    DELETE FROM public.rider_locations WHERE "timestamp" < now() - interval '24 hours' RETURNING 1
  ) SELECT count(*)::int FROM d;
$$;
REVOKE ALL ON FUNCTION public.purge_old_rider_locations() FROM PUBLIC, anon, authenticated;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'purge_old_rider_locations';
    PERFORM cron.schedule('purge_old_rider_locations', '7 * * * *', 'SELECT public.purge_old_rider_locations()');
  END IF;
END $$;

-- ==============================================================================
-- Smart refill reminders (2026-11-05)
-- ==============================================================================
-- Learns each customer's refill rhythm (median days between their last
-- delivered orders, needs >= 3 orders) and reminds them a day before they
-- usually reorder. At most one reminder per 3 days, never while an order is
-- active, and only when profiles.refill_reminders_enabled.
--   * customer_refill_rhythm()  -> for the app's home banner (current user)
--   * send_refill_reminders()   -> daily 9:00 PH pg_cron job, inserts notifications
-- Test: supabase/tests/refill_reminders_test.sql
-- ==============================================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS refill_reminders_enabled boolean NOT NULL DEFAULT true;

CREATE OR REPLACE FUNCTION public.refill_rhythm_for(p_customer_id uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  WITH recent AS (
    SELECT created_at, owner_id, station_name
    FROM public.orders
    WHERE customer_id = p_customer_id AND status = 'delivered'
    ORDER BY created_at DESC
    LIMIT 6
  ), gaps AS (
    SELECT extract(epoch FROM (created_at - lead(created_at) OVER (ORDER BY created_at DESC))) / 86400.0 AS days
    FROM recent
  ), stats AS (
    SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY days) AS median_days,
           count(*) AS gap_count
    FROM gaps WHERE days IS NOT NULL AND days > 0.5
  ), last AS (
    SELECT * FROM recent ORDER BY created_at DESC LIMIT 1
  )
  SELECT CASE
    WHEN (SELECT gap_count FROM stats) < 2 THEN jsonb_build_object('has_rhythm', false)
    ELSE jsonb_build_object(
      'has_rhythm', true,
      'median_days', round((SELECT median_days FROM stats)::numeric, 1),
      'last_order_at', (SELECT created_at FROM last),
      'station_id', (SELECT owner_id FROM last),
      'station_name', (SELECT station_name FROM last),
      'due_at', (SELECT created_at FROM last)
                + make_interval(secs => greatest((SELECT median_days FROM stats) - 1, 1) * 86400),
      'is_due', now() >= (SELECT created_at FROM last)
                + make_interval(secs => greatest((SELECT median_days FROM stats) - 1, 1) * 86400),
      'has_active_order', EXISTS (
        SELECT 1 FROM public.orders
        WHERE customer_id = p_customer_id
          AND status NOT IN ('delivered', 'cancelled', 'failed'))
    )
  END;
$$;
REVOKE ALL ON FUNCTION public.refill_rhythm_for(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.customer_refill_rhythm()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT CASE WHEN auth.uid() IS NULL THEN '{"has_rhythm": false}'::jsonb
              ELSE public.refill_rhythm_for(auth.uid()) END;
$$;
REVOKE ALL ON FUNCTION public.customer_refill_rhythm() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.customer_refill_rhythm() TO authenticated;

CREATE OR REPLACE FUNCTION public.send_refill_reminders()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_row record;
  v_r jsonb;
  v_sent integer := 0;
BEGIN
  FOR v_row IN
    SELECT p.id FROM public.profiles p
    WHERE p.role = 'customer' AND p.refill_reminders_enabled AND NOT coalesce(p.is_suspended, false)
  LOOP
    v_r := public.refill_rhythm_for(v_row.id);
    CONTINUE WHEN NOT coalesce((v_r->>'has_rhythm')::boolean, false)
               OR NOT (v_r->>'is_due')::boolean
               OR (v_r->>'has_active_order')::boolean;
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM public.system_notifications n
      WHERE n.user_id = v_row.id
        AND n.metadata->>'kind' = 'refill_reminder'
        AND n.created_at > now() - interval '3 days');

    INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
    VALUES (
      v_row.id, 'system_alert', 'normal', 'Time for a refill?',
      'You usually reorder every ' || round((v_r->>'median_days')::numeric) || ' days. '
        || 'Tap to reorder from ' || coalesce(v_r->>'station_name', 'your station') || '.',
      jsonb_build_object('kind', 'refill_reminder', 'station_id', v_r->>'station_id')
    );
    v_sent := v_sent + 1;
  END LOOP;
  RETURN v_sent;
END; $$;
REVOKE ALL ON FUNCTION public.send_refill_reminders() FROM PUBLIC, anon, authenticated;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'send_refill_reminders';
    -- 9:00 Asia/Manila = 01:00 UTC, so reminders arrive in the morning.
    PERFORM cron.schedule('send_refill_reminders', '0 1 * * *', 'SELECT public.send_refill_reminders()');
  END IF;
END $$;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Water quality transparency (2026-11-05)
-- ==============================================================================
-- Stations upload lab test results and permits (bacteriological /
-- physical-chemical water analysis, sanitary permit, business permit) with
-- issue and expiry dates. Admins approve them; approved, unexpired lab tests
-- give the station a "Water tested" badge and a small ranking boost.
-- Files live in the private verification_docs bucket under <uid>/certs/.
-- Approved certificate files are viewable by any signed-in user.
-- Daily job: marks expired certificates and warns owners 14 days ahead.
--
-- Run after: identity_verification.sql (bucket). Test: supabase/tests/water_quality_certs_test.sql
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.station_certifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  cert_type text NOT NULL CHECK (cert_type IN (
    'bacteriological', 'physical_chemical', 'sanitary_permit', 'business_permit')),
  issued_on date NOT NULL,
  expires_on date NOT NULL,
  file_path text NOT NULL,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected', 'expired')),
  reviewer_id uuid REFERENCES public.profiles(id),
  reviewed_at timestamptz,
  rejection_reason text,
  expiry_warned_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (expires_on > issued_on)
);
CREATE INDEX IF NOT EXISTS idx_station_certs_owner ON public.station_certifications (owner_id, status);

ALTER TABLE public.station_certifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Approved certs are public, owners see their own" ON public.station_certifications;
CREATE POLICY "Approved certs are public, owners see their own" ON public.station_certifications
  FOR SELECT TO authenticated
  USING (status = 'approved' OR owner_id = auth.uid() OR public.is_admin());
REVOKE INSERT, UPDATE, DELETE ON public.station_certifications FROM anon, authenticated;
GRANT SELECT ON public.station_certifications TO authenticated;

-- Approved certificate files are readable by signed-in users.
DROP POLICY IF EXISTS "Verification docs: approved certs readable" ON storage.objects;
CREATE POLICY "Verification docs: approved certs readable" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'verification_docs' AND EXISTS (
    SELECT 1 FROM public.station_certifications c
    WHERE c.file_path = storage.objects.name AND c.status = 'approved'));

CREATE OR REPLACE FUNCTION public.submit_station_certification(
  p_cert_type text, p_issued_on date, p_expires_on date, p_file_path text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_uid AND role = 'owner') THEN
    RAISE EXCEPTION 'Only station owners upload certificates.';
  END IF;
  IF p_file_path IS NULL OR left(p_file_path, length(v_uid::text) + 7) <> v_uid::text || '/certs/' THEN
    RAISE EXCEPTION 'Upload the certificate file first.';
  END IF;
  IF p_expires_on <= current_date THEN
    RAISE EXCEPTION 'This certificate has already expired.';
  END IF;
  IF p_issued_on > current_date THEN
    RAISE EXCEPTION 'The issue date cannot be in the future.';
  END IF;
  INSERT INTO public.station_certifications (owner_id, cert_type, issued_on, expires_on, file_path)
  VALUES (v_uid, p_cert_type, p_issued_on, p_expires_on, p_file_path)
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('id', v_id, 'status', 'pending');
END; $$;

CREATE OR REPLACE FUNCTION public.admin_review_station_certification(
  p_cert_id uuid, p_approve boolean, p_reason text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_row public.station_certifications%ROWTYPE;
  v_status text := CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  IF NOT p_approve AND coalesce(trim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'Give the station a reason for the rejection.';
  END IF;
  UPDATE public.station_certifications
  SET status = v_status, reviewer_id = auth.uid(), reviewed_at = now(),
      rejection_reason = CASE WHEN p_approve THEN NULL ELSE trim(p_reason) END
  WHERE id = p_cert_id AND status = 'pending'
  RETURNING * INTO v_row;
  IF NOT FOUND THEN RAISE EXCEPTION 'This certificate was already reviewed.'; END IF;

  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (v_row.owner_id, 'system_alert', 'normal',
    CASE WHEN p_approve THEN 'Certificate approved' ELSE 'Certificate rejected' END,
    CASE WHEN p_approve THEN 'Customers can now see your certificate.'
         ELSE 'Reason: ' || trim(p_reason) END,
    jsonb_build_object('certificate_id', v_row.id, 'status', v_status));
  RETURN jsonb_build_object('id', v_row.id, 'status', v_status);
END; $$;

REVOKE ALL ON FUNCTION public.submit_station_certification(text, date, date, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_station_certification(text, date, date, text) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_review_station_certification(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_review_station_certification(uuid, boolean, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.expire_station_certifications()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_n integer;
BEGIN
  UPDATE public.station_certifications SET status = 'expired'
  WHERE status = 'approved' AND expires_on <= current_date;
  GET DIAGNOSTICS v_n = ROW_COUNT;

  WITH soon AS (
    UPDATE public.station_certifications SET expiry_warned_at = now()
    WHERE status = 'approved' AND expiry_warned_at IS NULL
      AND expires_on <= current_date + 14
    RETURNING owner_id, id, cert_type, expires_on
  )
  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  SELECT owner_id, 'system_alert', 'high', 'Certificate expiring soon',
         'Your ' || replace(cert_type, '_', ' ') || ' certificate expires on '
           || to_char(expires_on, 'Mon DD, YYYY') || '. Upload a new one to keep your badge.',
         jsonb_build_object('certificate_id', id)
  FROM soon;
  RETURN v_n;
END; $$;
REVOKE ALL ON FUNCTION public.expire_station_certifications() FROM PUBLIC, anon, authenticated;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'expire_station_certifications';
    PERFORM cron.schedule('expire_station_certifications', '15 16 * * *', 'SELECT public.expire_station_certifications()');
  END IF;
END $$;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- Order disputes and refunds (2026-11-05)
-- ==============================================================================
-- Extends the existing public.disputes table (status enum: open,
-- investigating, resolved, dismissed) with the customer -> station -> admin
-- flow:
--   1. Customer opens a dispute within 48 h of delivery, one per order,
--      with optional photo evidence (private bucket dispute_evidence).
--   2. Station accepts (refund amount) -> resolved, or explains -> the
--      dispute is escalated ('investigating') for an admin.
--   3. Customer may escalate if the station has not answered in 24 h.
--   4. Admin resolves with an optional refund, or dismisses.
-- A granted refund books a REFUND ledger entry against the station, notifies
-- the customer, and refunds against the station increase flagged_count.
-- Money movement: COD refunds are returned by the station in cash; online
-- payments are refunded by the admin in PayMongo (orders.payment_status is
-- set to 'refunded' when the full total is refunded).
--
-- Test: supabase/tests/order_disputes_test.sql
-- ==============================================================================

ALTER TABLE public.disputes
  ADD COLUMN IF NOT EXISTS evidence_paths text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS owner_response text,
  ADD COLUMN IF NOT EXISTS owner_responded_at timestamptz,
  ADD COLUMN IF NOT EXISTS refund_amount numeric(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS escalated_at timestamptz;
ALTER TABLE public.disputes DROP CONSTRAINT IF EXISTS disputes_reason_check;
ALTER TABLE public.disputes ADD CONSTRAINT disputes_reason_check CHECK (reason IN (
  'missing_items', 'wrong_item', 'quality', 'damaged', 'not_delivered', 'overcharged', 'other'));
ALTER TABLE public.disputes DROP CONSTRAINT IF EXISTS disputes_refund_check;
ALTER TABLE public.disputes ADD CONSTRAINT disputes_refund_check CHECK (refund_amount >= 0);
CREATE UNIQUE INDEX IF NOT EXISTS disputes_one_per_order ON public.disputes (order_id);

-- Owners no longer update disputes directly; they use owner_respond_dispute.
DROP POLICY IF EXISTS "Owners can update disputes for their station" ON public.disputes;
REVOKE INSERT, DELETE ON public.disputes FROM anon, authenticated;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('dispute_evidence', 'dispute_evidence', false, 8388608,
        ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO UPDATE SET public = false;
DROP POLICY IF EXISTS "Dispute evidence: reporter upload" ON storage.objects;
CREATE POLICY "Dispute evidence: reporter upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'dispute_evidence' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "Dispute evidence: parties read" ON storage.objects;
CREATE POLICY "Dispute evidence: parties read" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'dispute_evidence' AND (
    (storage.foldername(name))[1] = auth.uid()::text
    OR public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.disputes d JOIN public.orders o ON o.id = d.order_id
      WHERE storage.objects.name = ANY (d.evidence_paths) AND o.owner_id = auth.uid())));

CREATE OR REPLACE FUNCTION public.open_dispute(
  p_order_id uuid, p_reason text, p_description text, p_evidence_paths text[] DEFAULT '{}'
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_order public.orders%ROWTYPE;
  v_done_at timestamptz;
  v_id uuid;
  v_path text;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id AND customer_id = v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order not found.'; END IF;
  IF v_order.status::text <> 'delivered' THEN
    RAISE EXCEPTION 'You can report a problem once the order is delivered.';
  END IF;
  v_done_at := coalesce(v_order.actual_completion_at, v_order.updated_at, v_order.created_at);
  IF v_done_at < now() - interval '48 hours' THEN
    RAISE EXCEPTION 'Problems must be reported within 48 hours of delivery.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.disputes WHERE order_id = p_order_id) THEN
    RAISE EXCEPTION 'A problem was already reported for this order.';
  END IF;
  IF coalesce(trim(p_description), '') = '' THEN
    RAISE EXCEPTION 'Tell the station what went wrong.';
  END IF;
  FOREACH v_path IN ARRAY coalesce(p_evidence_paths, '{}') LOOP
    IF left(v_path, length(v_uid::text) + 1) <> v_uid::text || '/' THEN
      RAISE EXCEPTION 'Invalid evidence photo.';
    END IF;
  END LOOP;

  INSERT INTO public.disputes (order_id, reporter_id, reason, description, status, evidence_paths)
  VALUES (p_order_id, v_uid, p_reason, trim(p_description), 'open', coalesce(p_evidence_paths, '{}'))
  RETURNING id INTO v_id;

  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (v_order.owner_id, 'system_alert', 'high', 'A customer reported a problem',
    'Order #' || upper(substr(p_order_id::text, 1, 8)) || ': ' || replace(p_reason, '_', ' ')
      || '. Please respond within 24 hours.',
    jsonb_build_object('dispute_id', v_id, 'order_id', p_order_id));
  RETURN jsonb_build_object('id', v_id, 'status', 'open');
END; $$;

-- Shared by station and admin resolutions.
CREATE OR REPLACE FUNCTION public.apply_dispute_refund(p_dispute_id uuid, p_amount numeric, p_note text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_d public.disputes%ROWTYPE;
  v_o public.orders%ROWTYPE;
BEGIN
  SELECT * INTO v_d FROM public.disputes WHERE id = p_dispute_id;
  SELECT * INTO v_o FROM public.orders WHERE id = v_d.order_id;
  IF p_amount < 0 OR p_amount > v_o.total_amount THEN
    RAISE EXCEPTION 'Refund must be between PHP 0 and the order total.';
  END IF;
  UPDATE public.disputes SET refund_amount = p_amount, status = 'resolved',
         resolution_notes = p_note, updated_at = now()
  WHERE id = p_dispute_id;
  IF p_amount > 0 THEN
    INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
    VALUES (v_o.owner_id, v_o.id, -p_amount, 'REFUND', 'Refund for reported problem');
    UPDATE public.profiles SET flagged_count = coalesce(flagged_count, 0) + 1 WHERE id = v_o.owner_id;
    IF p_amount >= v_o.total_amount THEN
      UPDATE public.orders SET payment_status = 'refunded' WHERE id = v_o.id;
    END IF;
  END IF;
  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (v_d.reporter_id, 'system_alert', 'high',
    CASE WHEN p_amount > 0 THEN 'Refund approved' ELSE 'Your report was reviewed' END,
    CASE WHEN p_amount > 0
      THEN 'PHP ' || trim(to_char(p_amount, '999990.00')) || ' will be returned '
        || CASE WHEN lower(coalesce(v_o.payment_method, 'cod')) IN ('cod', 'cash')
                THEN 'by the station in cash.' ELSE 'to your original payment method.' END
      ELSE coalesce(p_note, 'No refund was given.') END,
    jsonb_build_object('dispute_id', p_dispute_id, 'order_id', v_o.id, 'refund_amount', p_amount));
END; $$;
REVOKE ALL ON FUNCTION public.apply_dispute_refund(uuid, numeric, text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.owner_respond_dispute(
  p_dispute_id uuid, p_accept boolean, p_response text, p_refund_amount numeric DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_d public.disputes%ROWTYPE;
BEGIN
  SELECT d.* INTO v_d FROM public.disputes d JOIN public.orders o ON o.id = d.order_id
  WHERE d.id = p_dispute_id AND o.owner_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Dispute not found.'; END IF;
  IF v_d.status::text <> 'open' OR v_d.owner_responded_at IS NOT NULL THEN
    RAISE EXCEPTION 'This dispute was already answered.';
  END IF;
  IF coalesce(trim(p_response), '') = '' THEN RAISE EXCEPTION 'Write a reply to the customer.'; END IF;

  UPDATE public.disputes SET owner_response = trim(p_response), owner_responded_at = now(), updated_at = now()
  WHERE id = p_dispute_id;

  IF p_accept THEN
    PERFORM public.apply_dispute_refund(p_dispute_id, coalesce(p_refund_amount, 0), 'Station: ' || trim(p_response));
    RETURN jsonb_build_object('status', 'resolved');
  END IF;

  UPDATE public.disputes SET status = 'investigating', escalated_at = now() WHERE id = p_dispute_id;
  RETURN jsonb_build_object('status', 'investigating');
END; $$;

CREATE OR REPLACE FUNCTION public.escalate_dispute(p_dispute_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  UPDATE public.disputes SET status = 'investigating', escalated_at = now(), updated_at = now()
  WHERE id = p_dispute_id AND reporter_id = auth.uid() AND status = 'open'
    AND owner_responded_at IS NULL AND created_at < now() - interval '24 hours';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'You can ask eRefill to step in 24 hours after reporting if the station has not replied.';
  END IF;
  RETURN jsonb_build_object('status', 'investigating');
END; $$;

CREATE OR REPLACE FUNCTION public.admin_resolve_dispute(
  p_dispute_id uuid, p_refund_amount numeric, p_notes text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.disputes WHERE id = p_dispute_id AND status IN ('open', 'investigating')) THEN
    RAISE EXCEPTION 'This dispute is already closed.';
  END IF;
  UPDATE public.disputes SET resolved_by = auth.uid() WHERE id = p_dispute_id;
  PERFORM public.apply_dispute_refund(p_dispute_id, coalesce(p_refund_amount, 0), p_notes);
  IF coalesce(p_refund_amount, 0) = 0 THEN
    UPDATE public.disputes SET status = 'dismissed' WHERE id = p_dispute_id;
  END IF;
  RETURN jsonb_build_object('status', CASE WHEN coalesce(p_refund_amount, 0) > 0 THEN 'resolved' ELSE 'dismissed' END);
END; $$;

REVOKE ALL ON FUNCTION public.open_dispute(uuid, text, text, text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.open_dispute(uuid, text, text, text[]) TO authenticated;
REVOKE ALL ON FUNCTION public.owner_respond_dispute(uuid, boolean, text, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.owner_respond_dispute(uuid, boolean, text, numeric) TO authenticated;
REVOKE ALL ON FUNCTION public.escalate_dispute(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.escalate_dispute(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_resolve_dispute(uuid, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_resolve_dispute(uuid, numeric, text) TO authenticated;


NOTIFY pgrst, 'reload schema';
-- ==============================================================================
-- AI ordering assistant: per-user daily message limit (2026-11-05)
-- ==============================================================================
-- The order-assistant Edge Function records one row per message (with the
-- service role) and refuses more than 20 per user in 24 hours.
-- Users can read their own usage; nobody writes from the app.
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.assistant_usage (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  input_tokens integer NOT NULL DEFAULT 0,
  output_tokens integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_assistant_usage_user_time ON public.assistant_usage (user_id, created_at DESC);

ALTER TABLE public.assistant_usage ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users read own assistant usage" ON public.assistant_usage;
CREATE POLICY "Users read own assistant usage" ON public.assistant_usage
  FOR SELECT TO authenticated USING (user_id = auth.uid());
REVOKE INSERT, UPDATE, DELETE ON public.assistant_usage FROM anon, authenticated;
GRANT SELECT ON public.assistant_usage TO authenticated;

-- Shared fixtures for the SQL tests in this folder. Every test runs as
--   BEGIN; <scripts under test, BEGIN/COMMIT stripped>; _fixtures.sql; <test>; ROLLBACK;
-- through the Supabase MCP execute_sql tool, so nothing persists.
--
-- Fixture rows are inserted with triggers off (replica role) to skip station
-- setup checks; triggers are back on before the test body runs.
--
-- ids: owner ...a1, second owner ...a2, customer ...c1, rider ...d1,
--      admin ...e1, product ...b1 (₱19.60, owner a1).

SET LOCAL session_replication_role = replica;

INSERT INTO auth.users (id, instance_id, aud, role, email, raw_user_meta_data, raw_app_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_owner@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000a2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_owner2@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_cust@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_rider@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_admin@example.test', '{}', '{}', now(), now());

INSERT INTO public.profiles (id, role, full_name, station_name, station_availability, latitude, longitude)
VALUES
  ('00000000-0000-4000-8000-0000000000a1', 'owner', 'T Owner', 'T Station', 'open', 14.60, 121.00),
  ('00000000-0000-4000-8000-0000000000a2', 'owner', 'T Owner 2', 'T Station 2', 'open', 14.61, 121.01),
  ('00000000-0000-4000-8000-0000000000c1', 'customer', 'T Cust', NULL, 'open', 14.62, 121.02),
  ('00000000-0000-4000-8000-0000000000d1', 'rider', 'T Rider', NULL, 'open', NULL, NULL),
  ('00000000-0000-4000-8000-0000000000e1', 'admin', 'T Admin', NULL, 'open', NULL, NULL);

INSERT INTO public.owner_settings (owner_id, base_delivery_fee)
VALUES
  ('00000000-0000-4000-8000-0000000000a1', 5.4),
  ('00000000-0000-4000-8000-0000000000a2', 0);

INSERT INTO public.products (id, owner_id, name, price, is_available)
VALUES ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000a1', 'T Water', 19.6, true);

-- Fee config used by every test unless a test overrides it.
UPDATE public.system_config SET value = '{"enabled": true, "percent": 1, "fixed": 0}'::jsonb
WHERE key = 'platform_fee';

SET LOCAL session_replication_role = origin;

-- Helpers (temporary: dropped with the transaction).
CREATE OR REPLACE FUNCTION pg_temp.act_as(p_user uuid) RETURNS void
LANGUAGE sql AS $$
  SELECT set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text,
    true
  );
$$;

CREATE OR REPLACE FUNCTION pg_temp.place_order(p_method text, p_qty integer DEFAULT 1)
RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  RETURN public.create_order_atomic(
    jsonb_build_object(
      'owner_id', '00000000-0000-4000-8000-0000000000a1',
      'payment_method', p_method,
      'customer_name', 'T Cust',
      'customer_address', 'Test address',
      'customer_latitude', '14.6',
      'customer_longitude', '121.0'
    ),
    jsonb_build_array(jsonb_build_object(
      'product_id', '00000000-0000-4000-8000-0000000000b1',
      'quantity', p_qty,
      'product_name', 'T Water'
    ))
  );
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.assert_eq(p_label text, p_actual anyelement, p_expected anyelement)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF p_actual IS DISTINCT FROM p_expected THEN
    RAISE EXCEPTION '% — expected %, got %', p_label, p_expected, p_actual;
  END IF;
END;
$$;

-- Runs p_sql and fails unless it raises an error containing p_message.
CREATE OR REPLACE FUNCTION pg_temp.expect_error(p_label text, p_sql text, p_message text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    IF position(p_message IN SQLERRM) = 0 THEN
      RAISE EXCEPTION '% — expected error "%", got "%"', p_label, p_message, SQLERRM;
    END IF;
    RETURN;
  END;
  RAISE EXCEPTION '% — expected error "%", but it succeeded', p_label, p_message;
END;
$$;
-- Run: bash build.sh ../scripts/order_disputes.sql -- order_disputes_test.sql
SET LOCAL session_replication_role = replica;
INSERT INTO public.orders (id, customer_id, owner_id, status, total_amount, payment_method, updated_at, created_at) VALUES
  ('00000000-0000-4000-8000-00000000f201', '00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000a1', 'delivered', 80, 'cod', now() - interval '2 hours', now() - interval '3 hours'),
  ('00000000-0000-4000-8000-00000000f202', '00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000a1', 'delivered', 80, 'gcash', now() - interval '3 days', now() - interval '3 days'),
  ('00000000-0000-4000-8000-00000000f203', '00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000a1', 'pending', 80, 'cod', now(), now());
SET LOCAL session_replication_role = origin;

-- only_recent_delivered_orders
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  PERFORM pg_temp.expect_error('too old',
    $q$SELECT public.open_dispute('00000000-0000-4000-8000-00000000f202', 'quality', 'Smells odd')$q$, '48 hours');
  PERFORM pg_temp.expect_error('not delivered',
    $q$SELECT public.open_dispute('00000000-0000-4000-8000-00000000f203', 'quality', 'x')$q$, 'once the order is delivered');
END $$;

-- open_then_station_refunds_partially
DO $$ DECLARE d jsonb; BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  d := public.open_dispute('00000000-0000-4000-8000-00000000f201', 'missing_items', 'Only 2 of 3 gallons arrived');
  PERFORM pg_temp.expect_error('duplicate',
    $q$SELECT public.open_dispute('00000000-0000-4000-8000-00000000f201', 'other', 'again')$q$, 'already reported');

  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a2');
  PERFORM pg_temp.expect_error('other station',
    format('SELECT public.owner_respond_dispute(%L, true, %L, 20)', d->>'id', 'sorry'), 'not found');

  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
  PERFORM public.owner_respond_dispute((d->>'id')::uuid, true, 'Sorry, refunding one gallon', 25);

  PERFORM pg_temp.assert_eq('resolved', (SELECT status::text FROM public.disputes WHERE id = (d->>'id')::uuid), 'resolved');
  PERFORM pg_temp.assert_eq('ledger refund',
    (SELECT amount FROM public.ledger_entries WHERE order_id = '00000000-0000-4000-8000-00000000f201' AND entry_type = 'REFUND'), -25::numeric);
  PERFORM pg_temp.assert_eq('flagged',
    (SELECT flagged_count FROM public.profiles WHERE id = '00000000-0000-4000-8000-0000000000a1') >= 1, true);
  PERFORM pg_temp.assert_eq('partial keeps payment status',
    (SELECT payment_status::text FROM public.orders WHERE id = '00000000-0000-4000-8000-00000000f201') <> 'refunded', true);
END $$;

-- station_explains_then_admin_dismisses
DO $$ DECLARE d jsonb; BEGIN
  DELETE FROM public.disputes;
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  d := public.open_dispute('00000000-0000-4000-8000-00000000f201', 'quality', 'Cloudy water');
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
  PERFORM public.owner_respond_dispute((d->>'id')::uuid, false, 'Our lab test from last week is clean');
  PERFORM pg_temp.assert_eq('escalated', (SELECT status::text FROM public.disputes WHERE id = (d->>'id')::uuid), 'investigating');

  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000e1');
  PERFORM public.admin_resolve_dispute((d->>'id')::uuid, 0, 'Lab test confirms water is safe');
  PERFORM pg_temp.assert_eq('dismissed', (SELECT status::text FROM public.disputes WHERE id = (d->>'id')::uuid), 'dismissed');
END $$;

-- customer_cannot_insert_directly
DO $$ BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1'); SET LOCAL ROLE authenticated;
  PERFORM pg_temp.expect_error('direct',
    $q$INSERT INTO public.disputes (order_id, reporter_id, reason, description, status)
       VALUES ('00000000-0000-4000-8000-00000000f203', '00000000-0000-4000-8000-0000000000c1', 'other', 'x', 'resolved')$q$,
    'permission denied');
  RESET ROLE;
END $$;

SELECT 'order_disputes_test: all passed' AS result;
ROLLBACK;
