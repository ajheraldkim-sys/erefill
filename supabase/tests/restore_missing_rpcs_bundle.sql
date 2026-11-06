-- restore_missing_rpcs: rolled-back test. Paste into the SQL Editor; ends with 'all passed'.
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
-- Restore missing functions safely (2026-11-06)
-- ==============================================================================
-- The app calls these, but on the live database they only existed inside
-- older scripts that also replace newer work (create_order_atomic,
-- transition_order_status_safely). This script adds just the missing pieces,
-- updated to current rules, and touches nothing else.
--
--   1. get_customer_credits()          customer's credits from the station's
--      offline ledger, by exact name (the old ILIKE let "%" match everyone).
--   2. orders.delivery_type + complete_pickup_order_safely()
--      (the owner "Add order" dialog writes delivery_type; it failed without
--      the column).
--   3. Subscriptions: product_id link, live-price estimate, and
--      generate_due_subscription_orders() priced like checkout
--      (create_order_atomic v3: delivery quote, platform fee, ID gates).
--      process_due_customer_subscriptions() now uses the same generator;
--      it used to call price_order(), which does not exist.
--   4. admin_delete_product(): admins may remove accessories (water stays).
--
-- Run after: order_pricing_v3.sql (needs compute_delivery_quote and
-- assert_order_allowed_by_verification).
-- Test: supabase/tests/restore_missing_rpcs_test.sql
-- ==============================================================================


-- 1. Customer credits ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_customer_credits()
RETURNS SETOF public.dm_credits
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  WITH me AS (
    SELECT lower(btrim(regexp_replace(n, '\s+', ' ', 'g'))) AS n
    FROM public.profiles p,
         LATERAL (VALUES (p.full_name),
                         (concat_ws(' ', nullif(btrim(p.first_name), ''), nullif(btrim(p.last_name), '')))) v(n)
    WHERE p.id = auth.uid()
  ), names AS (
    SELECT DISTINCT n FROM me
    WHERE n IS NOT NULL AND length(n) >= 3 AND n <> 'new user'
  )
  SELECT c.* FROM public.dm_credits c
  WHERE c.credit_type = 'customer'
    AND lower(btrim(regexp_replace(c.debtor_name, '\s+', ' ', 'g'))) IN (SELECT n FROM names)
  ORDER BY c.created_at DESC;
$$;
REVOKE ALL ON FUNCTION public.get_customer_credits() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_customer_credits() TO authenticated, service_role;

-- 2. Pickup orders ---------------------------------------------------------------

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS delivery_type text NOT NULL DEFAULT 'delivery';
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_delivery_type_check;
ALTER TABLE public.orders ADD CONSTRAINT orders_delivery_type_check
  CHECK (delivery_type IN ('delivery', 'pickup'));

CREATE OR REPLACE FUNCTION public.complete_pickup_order_safely(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_order public.orders%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required.'; END IF;

  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'Order not found');
  END IF;
  IF auth.uid() IS DISTINCT FROM v_order.owner_id
     OR NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'owner') THEN
    RAISE EXCEPTION 'Only this station owner can complete a pickup order.';
  END IF;
  IF v_order.delivery_type <> 'pickup' THEN
    RAISE EXCEPTION 'Only pickup orders can be completed by the station.';
  END IF;

  IF v_order.status::text = 'delivered' THEN
    IF EXISTS (SELECT 1 FROM public.audit_logs
               WHERE action = 'OWNER_COMPLETE_PICKUP' AND entity_type = 'order'
                 AND entity_id = p_order_id::text) THEN
      RETURN jsonb_build_object('success', true, 'status', 'delivered', 'already_applied', true);
    END IF;
    RAISE EXCEPTION 'Pickup order is already delivered without an owner completion record.';
  END IF;
  IF v_order.status::text <> 'ready_for_pickup' THEN
    RAISE EXCEPTION 'Only a ready pickup order can be completed.';
  END IF;

  UPDATE public.orders
  SET status = 'delivered',
      actual_completion_at = coalesce(actual_completion_at, now()),
      updated_at = now()
  WHERE id = p_order_id;

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, old_value, new_value, metadata)
  VALUES (auth.uid(), 'OWNER_COMPLETE_PICKUP', 'order', p_order_id::text,
          jsonb_build_object('status', v_order.status),
          jsonb_build_object('status', 'delivered'),
          jsonb_build_object('delivery_type', 'pickup'));

  IF v_order.customer_id IS NOT NULL THEN
    INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
    VALUES (v_order.customer_id, 'system_alert', 'high', 'Pickup order completed',
            'Your refill order was collected from the water station.',
            jsonb_build_object('order_id', p_order_id, 'status', 'delivered'));
  END IF;
  RETURN jsonb_build_object('success', true, 'status', 'delivered');
END; $$;
REVOKE ALL ON FUNCTION public.complete_pickup_order_safely(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_pickup_order_safely(uuid) TO authenticated;

-- 3. Subscriptions ---------------------------------------------------------------

ALTER TABLE public.customer_subscriptions
  ADD COLUMN IF NOT EXISTS product_id uuid REFERENCES public.products(id) ON DELETE SET NULL;

-- Each station sells exactly one water product (station_accessories.sql), so
-- a subscription is for that product.
CREATE OR REPLACE FUNCTION public.proc_subscription_pricing()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_price numeric;
BEGIN
  IF NEW.product_id IS NULL OR (TG_OP = 'UPDATE' AND NEW.station_id IS DISTINCT FROM OLD.station_id) THEN
    SELECT id INTO NEW.product_id FROM public.products
    WHERE owner_id = NEW.station_id AND kind = 'water';
  END IF;
  IF NEW.product_id IS NOT NULL THEN
    SELECT price INTO v_price FROM public.products
    WHERE id = NEW.product_id AND owner_id = NEW.station_id AND kind = 'water';
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Subscriptions are for the station''s water only.' USING ERRCODE = '23514';
    END IF;
    -- Display only; orders are priced when they are generated.
    NEW.estimated_price := round(v_price * greatest(NEW.quantity, 1), 2);
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_subscription_pricing ON public.customer_subscriptions;
CREATE TRIGGER trg_subscription_pricing
  BEFORE INSERT OR UPDATE OF product_id, station_id, quantity, estimated_price
  ON public.customer_subscriptions
  FOR EACH ROW EXECUTE FUNCTION public.proc_subscription_pricing();

-- Backfill existing subscriptions (fires the trigger).
UPDATE public.customer_subscriptions SET product_id = NULL WHERE product_id IS NULL;

-- Generator without caller checks; only the two wrappers below may run it.
CREATE OR REPLACE FUNCTION public._generate_due_subscription_orders(
  p_customer_id uuid, p_station_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_sub public.customer_subscriptions%ROWTYPE;
  v_product public.products%ROWTYPE;
  v_cust public.profiles%ROWTYPE;
  v_key text;
  v_method text;
  v_order_id uuid;
  v_quote jsonb;
  v_subtotal numeric(10,2);
  v_delivery_fee numeric(10,2);
  v_platform_fee numeric(10,2);
  v_total numeric(10,2);
  v_config jsonb := public.get_platform_fee_config();
  v_next timestamptz;
  v_created jsonb := '[]'::jsonb;
  v_skipped jsonb := '[]'::jsonb;
BEGIN
  FOR v_sub IN
    SELECT * FROM public.customer_subscriptions
    WHERE is_active
      AND next_delivery_date <= now() + interval '5 minutes'
      AND (p_customer_id IS NULL OR customer_id = p_customer_id)
      AND (p_station_id IS NULL OR station_id = p_station_id)
    ORDER BY next_delivery_date
    FOR UPDATE SKIP LOCKED
  LOOP
    -- One order per subscription per Manila day.
    v_key := 'auto_sub_' || v_sub.id || '_' || to_char(now() AT TIME ZONE 'Asia/Manila', 'YYYY-MM-DD');
    v_method := lower(coalesce(v_sub.payment_method, 'cod'));

    IF NOT EXISTS (SELECT 1 FROM public.orders WHERE idempotency_key = v_key) THEN
      SELECT * INTO v_product FROM public.products
      WHERE id = v_sub.product_id AND owner_id = v_sub.station_id
        AND kind = 'water' AND is_available AND price > 0;
      IF NOT FOUND THEN
        v_skipped := v_skipped || jsonb_build_object('subscription_id', v_sub.id, 'reason', 'product_unavailable');
        CONTINUE;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM public.profiles
                     WHERE id = v_sub.station_id AND role = 'owner'
                       AND NOT coalesce(is_suspended, false)
                       AND coalesce(station_availability, 'open') = 'open') THEN
        v_skipped := v_skipped || jsonb_build_object('subscription_id', v_sub.id, 'reason', 'station_unavailable');
        CONTINUE;
      END IF;
      IF NOT public.is_station_payment_method_available(v_sub.station_id, v_method) THEN
        v_skipped := v_skipped || jsonb_build_object('subscription_id', v_sub.id, 'reason', 'payment_method_unavailable');
        CONTINUE;
      END IF;

      SELECT * INTO v_cust FROM public.profiles WHERE id = v_sub.customer_id;

      -- Pricing: same as create_order_atomic v3.
      v_subtotal := round(v_product.price * v_sub.quantity, 2);
      v_quote := public.compute_delivery_quote(
        v_sub.station_id,
        coalesce(v_cust.latitude, v_cust.lat), coalesce(v_cust.longitude, v_cust.lng),
        v_cust.barangay, v_sub.quantity);
      v_delivery_fee := coalesce((v_quote->>'fee')::numeric, 0);
      v_platform_fee := 0;
      IF coalesce((v_config->>'enabled')::boolean, false) THEN
        v_platform_fee := greatest(round(
          ((v_subtotal + v_delivery_fee) * coalesce((v_config->>'percent')::numeric, 0) / 100)
          + coalesce((v_config->>'fixed')::numeric, 0), 2), 0);
      END IF;
      v_total := v_subtotal + v_delivery_fee + v_platform_fee;

      -- Verified station; COD limits for unverified customers.
      BEGIN
        PERFORM public.assert_order_allowed_by_verification(
          v_sub.customer_id, v_sub.station_id, v_method, v_total);
      EXCEPTION WHEN OTHERS THEN
        v_skipped := v_skipped || jsonb_build_object(
          'subscription_id', v_sub.id, 'reason', 'not_allowed', 'message', SQLERRM);
        CONTINUE;
      END;

      v_order_id := gen_random_uuid();
      INSERT INTO public.orders (
        id, customer_id, owner_id, station_name, customer_name, customer_phone,
        customer_address, customer_barangay, idempotency_key, subtotal, delivery_fee,
        platform_fee, total_amount, payment_method, payment_status, status, notes, items,
        customer_latitude, customer_longitude, delivery_latitude, delivery_longitude,
        delivery_distance_km, delivery_rate_per_km, delivery_free_reason, tip_amount
      ) VALUES (
        v_order_id, v_sub.customer_id, v_sub.station_id, v_sub.station_name,
        v_cust.full_name, v_cust.phone, v_sub.delivery_address, v_cust.barangay, v_key,
        v_subtotal, v_delivery_fee, v_platform_fee, v_total, v_method, 'pending', 'pending',
        'Auto-refill (' || v_sub.frequency || ', ' || v_sub.preferred_time_slot || ')',
        jsonb_build_array(jsonb_build_object(
          'product_id', v_product.id, 'product_name', v_product.name,
          'quantity', v_sub.quantity, 'price', v_product.price, 'total_price', v_subtotal)),
        coalesce(v_cust.latitude, v_cust.lat), coalesce(v_cust.longitude, v_cust.lng),
        coalesce(v_cust.latitude, v_cust.lat), coalesce(v_cust.longitude, v_cust.lng),
        (v_quote->>'distance_km')::numeric, (v_quote->>'rate_per_km')::numeric,
        v_quote->>'free_reason', 0
      );

      INSERT INTO public.order_items (order_id, product_id, product_name, quantity, price_at_purchase, subtotal)
      VALUES (v_order_id, v_product.id, v_product.name, v_sub.quantity, v_product.price, v_subtotal);

      INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
      VALUES (v_sub.station_id, 'system_alert', 'high', 'New auto-refill order',
              coalesce(v_cust.full_name, 'A customer') || '''s auto-refill order of PHP '
                || trim(to_char(v_total, '999999990.00')) || ' is ready to prepare.',
              jsonb_build_object('order_id', v_order_id, 'status', 'pending', 'total_amount', v_total));

      v_created := v_created || jsonb_build_object(
        'id', v_order_id, 'subscription_id', v_sub.id, 'subtotal', v_subtotal,
        'delivery_fee', v_delivery_fee, 'platform_fee', v_platform_fee, 'total_amount', v_total);
    END IF;

    -- Advance only once this cycle has an order (new or existing).
    v_next := v_sub.next_delivery_date;
    LOOP
      v_next := CASE v_sub.frequency
        WHEN 'every_3_days' THEN v_next + interval '3 days'
        WHEN 'twice_weekly' THEN v_next + interval '4 days'
        WHEN 'weekly'       THEN v_next + interval '7 days'
        WHEN 'bi_weekly'    THEN v_next + interval '14 days'
        WHEN 'monthly'      THEN v_next + interval '1 month'
        ELSE v_next + interval '7 days'
      END;
      EXIT WHEN v_next > now();
    END LOOP;
    UPDATE public.customer_subscriptions SET next_delivery_date = v_next, updated_at = now()
    WHERE id = v_sub.id;
  END LOOP;

  RETURN jsonb_build_object('created', v_created, 'skipped', v_skipped);
END; $$;
REVOKE ALL ON FUNCTION public._generate_due_subscription_orders(uuid, uuid) FROM PUBLIC, anon, authenticated;

-- App entry point: the customer (own), the station owner (own station) or an admin.
CREATE OR REPLACE FUNCTION public.generate_due_subscription_orders(
  p_customer_id uuid DEFAULT NULL, p_station_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501'; END IF;
  IF NOT public.is_admin() THEN
    IF p_customer_id IS DISTINCT FROM v_uid AND p_station_id IS DISTINCT FROM v_uid THEN
      RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
    END IF;
    IF p_customer_id IS DISTINCT FROM v_uid
       AND NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_uid AND role = 'owner') THEN
      RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN public._generate_due_subscription_orders(p_customer_id, p_station_id);
END; $$;
REVOKE ALL ON FUNCTION public.generate_due_subscription_orders(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.generate_due_subscription_orders(uuid, uuid) TO authenticated, service_role;

-- Scheduled-job entry point (all due subscriptions). Kept for old callers.
CREATE OR REPLACE FUNCTION public.process_due_customer_subscriptions()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  r jsonb;
BEGIN
  IF current_user IN ('authenticated', 'anon') AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
  END IF;
  r := public._generate_due_subscription_orders(NULL, NULL);
  RETURN jsonb_build_object(
    'success', true,
    'orders_created', jsonb_array_length(r->'created'),
    'orders_skipped', jsonb_array_length(r->'skipped'),
    'skipped', r->'skipped',
    'timestamp', now());
END; $$;
REVOKE ALL ON FUNCTION public.process_due_customer_subscriptions() FROM PUBLIC, anon;

-- 4. Admin product moderation ------------------------------------------------------

CREATE OR REPLACE FUNCTION public.admin_delete_product(p_product_id uuid, p_reason text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_p public.products%ROWTYPE;
  v_used boolean;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  SELECT * INTO v_p FROM public.products WHERE id = p_product_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Product not found.'; END IF;
  IF v_p.kind = 'water' THEN
    RAISE EXCEPTION 'Each station sells its water type only. Change the station''s water type instead.';
  END IF;

  -- Accessories already on orders are hidden instead of deleted, so receipts
  -- and order history keep their item.
  v_used := EXISTS (SELECT 1 FROM public.order_items WHERE product_id = p_product_id);
  IF v_used THEN
    UPDATE public.products SET is_available = false WHERE id = p_product_id;
  ELSE
    DELETE FROM public.products WHERE id = p_product_id;
  END IF;

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, old_value, metadata)
  VALUES (auth.uid(), CASE WHEN v_used THEN 'admin_hide_product' ELSE 'admin_delete_product' END,
          'products', p_product_id::text,
          jsonb_build_object('name', v_p.name, 'price', v_p.price, 'owner_id', v_p.owner_id),
          jsonb_build_object('reason', p_reason));
  RETURN jsonb_build_object('id', p_product_id, 'deleted', NOT v_used, 'hidden', v_used);
END; $$;
REVOKE ALL ON FUNCTION public.admin_delete_product(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_product(uuid, text) TO authenticated;


NOTIFY pgrst, 'reload schema';
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
-- Run: bash build.sh ../scripts/harden_signup_and_protected_columns.sql ../scripts/delivery_coverage.sql ../scripts/station_accessories.sql ../scripts/rider_tips.sql ../scripts/identity_verification.sql ../scripts/order_pricing_v3.sql ../scripts/restore_missing_rpcs.sql -- restore_missing_rpcs_test.sql

-- Fixture station a1 takes orders: verified, COD wallet funded.
UPDATE public.profiles SET verification_status = 'approved'
WHERE id = '00000000-0000-4000-8000-0000000000a1';
INSERT INTO public.station_fee_wallets (owner_id, balance)
VALUES ('00000000-0000-4000-8000-0000000000a1', 1000)
ON CONFLICT (owner_id) DO UPDATE SET balance = 1000;
UPDATE public.system_config
SET value = '{"enabled": true, "rate_per_km": 10, "minimum_fee": 20, "min_billable_distance_km": 1, "rounding_rule": "exact"}'::jsonb
WHERE key = 'delivery_fee_config';

-- customer_credits_exact_name_only
DO $$ BEGIN
  SET LOCAL session_replication_role = replica;
  INSERT INTO public.dm_credits (owner_id, credit_type, debtor_name, amount) VALUES
    ('00000000-0000-4000-8000-0000000000a1', 'customer', '  t cust ', 50),
    ('00000000-0000-4000-8000-0000000000a1', 'customer', 'T Cust Jr', 70),
    ('00000000-0000-4000-8000-0000000000a1', 'customer', 'Someone Else', 90);
  SET LOCAL session_replication_role = origin;

  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  PERFORM pg_temp.assert_eq('own credit only',
    (SELECT count(*) FROM public.get_customer_credits()), 1::bigint);

  -- A "%" name must not match everything.
  SET LOCAL session_replication_role = replica;
  UPDATE public.profiles SET full_name = '%', first_name = NULL, last_name = NULL
  WHERE id = '00000000-0000-4000-8000-0000000000c1';
  SET LOCAL session_replication_role = origin;
  PERFORM pg_temp.assert_eq('wildcard name sees nothing',
    (SELECT count(*) FROM public.get_customer_credits()), 0::bigint);
  SET LOCAL session_replication_role = replica;
  UPDATE public.profiles SET full_name = 'T Cust' WHERE id = '00000000-0000-4000-8000-0000000000c1';
  SET LOCAL session_replication_role = origin;
END $$;

-- owner_walk_in_order_and_pickup_completion
DO $$ DECLARE r jsonb; BEGIN
  SET LOCAL session_replication_role = replica;
  INSERT INTO public.orders (id, customer_id, owner_id, status, total_amount, delivery_type)
  VALUES ('00000000-0000-4000-8000-00000000f301', '00000000-0000-4000-8000-0000000000c1',
          '00000000-0000-4000-8000-0000000000a1', 'ready_for_pickup', 40, 'pickup'),
         ('00000000-0000-4000-8000-00000000f302', '00000000-0000-4000-8000-0000000000c1',
          '00000000-0000-4000-8000-0000000000a1', 'ready_for_pickup', 40, 'delivery');
  SET LOCAL session_replication_role = origin;

  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a2');
  PERFORM pg_temp.expect_error('other station',
    $q$SELECT public.complete_pickup_order_safely('00000000-0000-4000-8000-00000000f301')$q$,
    'Only this station owner');

  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
  PERFORM pg_temp.expect_error('delivery order',
    $q$SELECT public.complete_pickup_order_safely('00000000-0000-4000-8000-00000000f302')$q$,
    'Only pickup orders');
  r := public.complete_pickup_order_safely('00000000-0000-4000-8000-00000000f301');
  PERFORM pg_temp.assert_eq('completed', r->>'status', 'delivered');
  r := public.complete_pickup_order_safely('00000000-0000-4000-8000-00000000f301');
  PERFORM pg_temp.assert_eq('idempotent', (r->>'already_applied')::boolean, true);
END $$;

-- subscription_order_priced_like_checkout
DO $$ DECLARE r jsonb; q jsonb; v_sub uuid := gen_random_uuid(); BEGIN
  INSERT INTO public.customer_subscriptions (id, customer_id, station_id, station_name, quantity,
    water_type, estimated_price, delivery_address, next_delivery_date)
  VALUES (v_sub, '00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000a1',
    'T Station', 3, 'T Water', 1, 'Test address', now() - interval '1 hour');
  PERFORM pg_temp.assert_eq('product linked',
    (SELECT product_id FROM public.customer_subscriptions WHERE id = v_sub),
    '00000000-0000-4000-8000-0000000000b1'::uuid);
  PERFORM pg_temp.assert_eq('estimate from live price',
    (SELECT estimated_price FROM public.customer_subscriptions WHERE id = v_sub), 58.80::numeric);

  -- Strangers cannot run someone else's subscriptions.
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a2');
  PERFORM pg_temp.expect_error('stranger',
    $q$SELECT public.generate_due_subscription_orders('00000000-0000-4000-8000-0000000000c1', NULL)$q$,
    'Not authorized');

  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  r := public.generate_due_subscription_orders('00000000-0000-4000-8000-0000000000c1', NULL);
  PERFORM pg_temp.assert_eq('one order', jsonb_array_length(r->'created'), 1);

  -- Customer c1 is at (14.62, 121.02), outside the 1 km free zone.
  q := public.compute_delivery_quote('00000000-0000-4000-8000-0000000000a1', 14.62, 121.02, NULL, 3);
  PERFORM pg_temp.assert_eq('delivery fee from quote',
    (r->'created'->0->>'delivery_fee')::numeric, (q->>'fee')::numeric);
  PERFORM pg_temp.assert_eq('subtotal from live price',
    (r->'created'->0->>'subtotal')::numeric, 58.80::numeric);
  PERFORM pg_temp.assert_eq('distance stored',
    (SELECT delivery_distance_km IS NOT NULL FROM public.orders
     WHERE id = (r->'created'->0->>'id')::uuid), true);

  -- Same day again: no duplicate, schedule already moved on.
  UPDATE public.customer_subscriptions SET next_delivery_date = now() - interval '1 hour' WHERE id = v_sub;
  r := public.generate_due_subscription_orders('00000000-0000-4000-8000-0000000000c1', NULL);
  PERFORM pg_temp.assert_eq('no duplicate', jsonb_array_length(r->'created'), 0);
END $$;

-- unverified_station_subscription_is_skipped_not_advanced
DO $$ DECLARE r jsonb; v_sub uuid := gen_random_uuid(); v_due timestamptz := now() - interval '2 hours'; BEGIN
  DELETE FROM public.customer_subscriptions;
  SET LOCAL session_replication_role = replica;
  UPDATE public.profiles SET verification_status = 'pending' WHERE id = '00000000-0000-4000-8000-0000000000a1';
  SET LOCAL session_replication_role = origin;
  INSERT INTO public.customer_subscriptions (id, customer_id, station_id, station_name, quantity,
    water_type, delivery_address, next_delivery_date, product_id)
  VALUES (v_sub, '00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000a1',
    'T Station', 1, 'T Water', 'Test', v_due, '00000000-0000-4000-8000-0000000000b1');
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  r := public.generate_due_subscription_orders('00000000-0000-4000-8000-0000000000c1', NULL);
  PERFORM pg_temp.assert_eq('skipped', r->'skipped'->0->>'reason', 'not_allowed');
  PERFORM pg_temp.assert_eq('stays due',
    (SELECT next_delivery_date FROM public.customer_subscriptions WHERE id = v_sub), v_due);
END $$;

-- admin_can_remove_accessories_not_water
DO $$ BEGIN
  SET LOCAL session_replication_role = replica;
  INSERT INTO public.products (id, owner_id, name, price, category, kind, is_available)
  VALUES ('00000000-0000-4000-8000-0000000000b9', '00000000-0000-4000-8000-0000000000a1',
          'Old cap', 5, 'cap', 'accessory', true);
  SET LOCAL session_replication_role = origin;

  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
  PERFORM pg_temp.expect_error('owner cannot use admin delete',
    $q$SELECT public.admin_delete_product('00000000-0000-4000-8000-0000000000b9', 'x')$q$, 'Forbidden');

  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000e1');
  PERFORM pg_temp.expect_error('water stays',
    $q$SELECT public.admin_delete_product('00000000-0000-4000-8000-0000000000b1', 'x')$q$,
    'water type');
  PERFORM public.admin_delete_product('00000000-0000-4000-8000-0000000000b9', 'Listed by mistake');
  PERFORM pg_temp.assert_eq('accessory removed',
    (SELECT count(*) FROM public.products WHERE id = '00000000-0000-4000-8000-0000000000b9'), 0::bigint);
END $$;

SELECT 'restore_missing_rpcs_test: all passed' AS result;
ROLLBACK;
