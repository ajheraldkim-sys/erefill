-- Migration: Remove Service Radius Restrictions
-- Centralized delivery fee calculation handles distance dynamically per km.
-- Stations can deliver without service radius limits.

BEGIN;

-- 1. Update check_station_availability to remove service zone check
CREATE OR REPLACE FUNCTION public.check_station_availability(
    p_station_id uuid,
    p_customer_lat double precision,
    p_customer_lng double precision
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_station_lat DOUBLE PRECISION;
    v_station_lng DOUBLE PRECISION;
    v_max_capacity INTEGER;
    v_current_active INTEGER;
    v_distance DOUBLE PRECISION;
BEGIN
    -- Get Station Location and Settings with Fallbacks
    SELECT 
        p.latitude, 
        p.longitude, 
        COALESCE(s.max_concurrent_orders, 20)
    INTO v_station_lat, v_station_lng, v_max_capacity
    FROM public.profiles p
    LEFT JOIN public.owner_settings s ON s.owner_id = p.id
    WHERE p.id = p_station_id;

    -- CRITICAL CHECK: If station has no coordinates, we cannot calculate distance.
    IF v_station_lat IS NULL OR v_station_lng IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'STATION_RECORDS_INCOMPLETE', 
            'message', 'Station records are incomplete (missing coordinates). Please contact the station owner.'
        );
    END IF;

    -- 1. Calculate Distance (Spherical Law of Cosines) in KM
    v_distance := 6371 * acos(
        pmin(1.0, 
            cos(radians(p_customer_lat)) * cos(radians(v_station_lat)) * 
            cos(radians(v_station_lng) - radians(p_customer_lng)) + 
            sin(radians(p_customer_lat)) * sin(radians(v_station_lat))
        )
    );

    -- Service radius removed: No OUT_OF_ZONE distance limit.
    -- The calculated distance is returned and used for distance-based delivery fee calculations.

    -- 2. Check Operational Capacity (Active and Non-Failed orders)
    SELECT COUNT(*) INTO v_current_active
    FROM public.orders
    WHERE owner_id = p_station_id 
      AND status IN ('pending', 'accepted', 'preparing', 'out_for_delivery')
      AND payment_status NOT IN ('failed', 'refunded');

    IF v_current_active >= v_max_capacity THEN
        RETURN jsonb_build_object(
            'status', 'CAPACITY_EXCEEDED', 
            'message', 'Station is at maximum capacity. Please wait or try another station.',
            'load', v_current_active,
            'limit', v_max_capacity,
            'distance', ROUND(v_distance::numeric, 2)
        );
    END IF;

    -- Success Status
    RETURN jsonb_build_object(
        'status', 'OK', 
        'message', 'Station available.',
        'distance', ROUND(v_distance::numeric, 2)
    );
END;
$$;

ALTER FUNCTION public.check_station_availability(uuid, double precision, double precision) OWNER TO postgres;
GRANT ALL ON FUNCTION public.check_station_availability(uuid, double precision, double precision) TO anon;
GRANT ALL ON FUNCTION public.check_station_availability(uuid, double precision, double precision) TO authenticated;
GRANT ALL ON FUNCTION public.check_station_availability(uuid, double precision, double precision) TO service_role;

-- 2. Update verify_order_delivery_location trigger to remove service radius check
CREATE OR REPLACE FUNCTION public.verify_order_delivery_location()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  station_latitude double precision;
  station_longitude double precision;
  max_active_orders integer;
  active_orders integer;
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
    COALESCE(settings.max_concurrent_orders, 20)
  INTO
    station_latitude,
    station_longitude,
    max_active_orders
  FROM public.profiles AS station
  LEFT JOIN public.owner_settings AS settings ON settings.owner_id = station.id
  WHERE station.id = NEW.owner_id
    AND station.role = 'owner'
    AND COALESCE(station.station_availability, 'open') = 'open';

  IF station_latitude IS NULL OR station_longitude IS NULL THEN
    RAISE EXCEPTION 'This water station is currently closed or unavailable.';
  END IF;

  -- Service radius removed: No distance threshold check. Delivery fees are applied dynamically per km.

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

DROP TRIGGER IF EXISTS verify_order_delivery_location_trigger ON public.orders;
CREATE TRIGGER verify_order_delivery_location_trigger
BEFORE INSERT ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.verify_order_delivery_location();

COMMIT;
