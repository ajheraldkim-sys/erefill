-- Keeps the selected default delivery address, profile municipality, and
-- order delivery coordinates consistent. Run once in the Supabase SQL editor.
-- Safe to re-run.

BEGIN;

-- Existing concurrent client updates may have left more than one default.
-- Keep the most recently changed address for each customer before enforcing
-- the invariant below.
WITH ranked_defaults AS (
  SELECT
    id,
    row_number() OVER (
      PARTITION BY customer_id
      ORDER BY updated_at DESC, created_at DESC, id DESC
    ) AS position
  FROM public.customer_addresses
  WHERE is_default
)
UPDATE public.customer_addresses AS address
SET is_default = false
FROM ranked_defaults
WHERE address.id = ranked_defaults.id
  AND ranked_defaults.position > 1;

CREATE UNIQUE INDEX IF NOT EXISTS customer_addresses_one_default_per_customer
  ON public.customer_addresses (customer_id)
  WHERE is_default;

-- A coordinate alone does not tell us whether it was selected for Cantilan
-- or Madrid. New/edited addresses record that confirmation explicitly;
-- legacy rows remain NULL until their owner reviews the pin.
ALTER TABLE public.customer_addresses
  ADD COLUMN IF NOT EXISTS map_pin_town text;
ALTER TABLE public.customer_addresses
  DROP CONSTRAINT IF EXISTS customer_addresses_pin_matches_town;
ALTER TABLE public.customer_addresses
  ADD CONSTRAINT customer_addresses_pin_matches_town
  CHECK (map_pin_town IS NULL OR map_pin_town = town) NOT VALID;

-- Invalid historical rows are retained for review, while every new or edited
-- address must have a usable map pin.
ALTER TABLE public.customer_addresses
  DROP CONSTRAINT IF EXISTS customer_addresses_valid_coordinates;
ALTER TABLE public.customer_addresses
  ADD CONSTRAINT customer_addresses_valid_coordinates
  CHECK (
    latitude BETWEEN -90 AND 90
    AND longitude BETWEEN -180 AND 180
    AND (latitude <> 0 OR longitude <> 0)
  ) NOT VALID;

CREATE OR REPLACE FUNCTION public.sync_default_customer_address()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  replacement_id uuid;
  postal_code text;
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.is_default THEN
      SELECT id
      INTO replacement_id
      FROM public.customer_addresses
      WHERE customer_id = OLD.customer_id
      ORDER BY updated_at DESC, created_at DESC, id DESC
      LIMIT 1;

      IF replacement_id IS NULL THEN
        UPDATE public.profiles
        SET complete_address = '',
            town = NULL,
            barangay = NULL,
            landmark = '',
            purok = NULL,
            zip_code = NULL,
            latitude = NULL,
            longitude = NULL
        WHERE id = OLD.customer_id;
      ELSE
        -- This update invokes the INSERT/UPDATE branch below, which syncs
        -- the replacement address to the profile in the same transaction.
        UPDATE public.customer_addresses
        SET is_default = true
        WHERE id = replacement_id;
      END IF;
    END IF;
    RETURN OLD;
  END IF;

  -- The account-creation trigger already receives the municipality and its
  -- Ensure map_pin_town defaults to town on insert if not provided
  IF TG_OP = 'INSERT' AND NEW.map_pin_town IS NULL THEN
    NEW.map_pin_town := NEW.town;
  END IF;

  IF NEW.is_default THEN
    IF NEW.map_pin_town IS DISTINCT FROM NEW.town THEN
      RAISE EXCEPTION
        'Confirm this address on the map before making it the default.';
    END IF;

    -- This trigger also protects direct table updates and concurrent address
    -- selections, not just the app's normal selection flow.
    UPDATE public.customer_addresses
    SET is_default = false
    WHERE customer_id = NEW.customer_id
      AND id <> NEW.id
      AND is_default;

    postal_code := CASE NEW.town
      WHEN 'Cantilan' THEN '8317'
      WHEN 'Madrid' THEN '8316'
      ELSE NULL
    END;

    UPDATE public.profiles
    SET complete_address = NEW.complete_address,
        town = NEW.town::public.municipality,
        barangay = NEW.barangay,
        landmark = NEW.landmark,
        -- Saved addresses intentionally do not model purok; keeping one from
        -- a previous municipality creates an invalid profile address.
        purok = NULL,
        zip_code = postal_code,
        latitude = NEW.latitude,
        longitude = NEW.longitude
    WHERE id = NEW.customer_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sync_default_customer_address_trigger
  ON public.customer_addresses;
CREATE TRIGGER sync_default_customer_address_trigger
BEFORE INSERT OR UPDATE ON public.customer_addresses
FOR EACH ROW
EXECUTE FUNCTION public.sync_default_customer_address();

DROP TRIGGER IF EXISTS promote_customer_address_after_delete
  ON public.customer_addresses;
CREATE TRIGGER promote_customer_address_after_delete
AFTER DELETE ON public.customer_addresses
FOR EACH ROW
EXECUTE FUNCTION public.sync_default_customer_address();

-- Availability was previously checked only in Flutter. Any outdated client,
-- race, or direct API call could place an order outside the service radius.
CREATE OR REPLACE FUNCTION public.verify_order_delivery_location()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  station_latitude double precision;
  station_longitude double precision;
  service_radius double precision;
  max_active_orders integer;
  active_orders integer;
  distance_km double precision;
  cosine_argument double precision;
BEGIN
  IF NEW.customer_latitude IS NULL
     OR NEW.customer_longitude IS NULL
     OR NEW.customer_latitude NOT BETWEEN -90 AND 90
     OR NEW.customer_longitude NOT BETWEEN -180 AND 180
     OR (NEW.customer_latitude = 0 AND NEW.customer_longitude = 0) THEN
    RAISE EXCEPTION 'A valid delivery map pin is required.';
  END IF;

  SELECT
    station.latitude,
    station.longitude,
    COALESCE(settings.service_radius_km, 10.0),
    COALESCE(settings.max_concurrent_orders, 20)
  INTO
    station_latitude,
    station_longitude,
    service_radius,
    max_active_orders
  FROM public.profiles AS station
  LEFT JOIN public.owner_settings AS settings ON settings.owner_id = station.id
  WHERE station.id = NEW.owner_id
    AND station.role = 'owner'
    AND COALESCE(station.station_availability, 'open') = 'open';

  IF station_latitude IS NULL OR station_longitude IS NULL THEN
    RAISE EXCEPTION 'This water station is currently closed or unavailable.';
  END IF;

  cosine_argument :=
    cos(radians(NEW.customer_latitude)) * cos(radians(station_latitude)) *
    cos(radians(station_longitude) - radians(NEW.customer_longitude)) +
    sin(radians(NEW.customer_latitude)) * sin(radians(station_latitude));
  distance_km := 6371 * acos(LEAST(1.0, GREATEST(-1.0, cosine_argument)));

  IF distance_km > service_radius THEN
    RAISE EXCEPTION 'This station is not available for the selected delivery address.';
  END IF;

  -- Serialize capacity checks per station so two concurrent checkouts cannot
  -- both observe the final available delivery slot.
  PERFORM pg_advisory_xact_lock(hashtextextended(NEW.owner_id::text, 0));
  SELECT count(*)
  INTO active_orders
  FROM public.orders
  WHERE owner_id = NEW.owner_id
    AND status IN ('pending', 'accepted', 'preparing', 'out_for_delivery')
    AND COALESCE(payment_status, 'pending') NOT IN ('failed', 'refunded');

  IF active_orders >= max_active_orders THEN
    RAISE EXCEPTION 'This station is at maximum capacity. Please try again later.';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS verify_order_delivery_location_trigger
  ON public.orders;
CREATE TRIGGER verify_order_delivery_location_trigger
BEFORE INSERT ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.verify_order_delivery_location();

COMMIT;
