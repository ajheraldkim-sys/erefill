-- Migration: Station Setup Enforcement & Product Management
-- 1. Adds operating schedule and setup tracking to owner_settings
-- 2. Creates check_station_setup_status RPC function
-- 3. Enforces CLOSED / INCOMPLETE_SETUP state machine via database triggers
-- 4. Seeds standard products (Empty 5-Gallon Container & Non-spill Cap)

BEGIN;

-- 1. Extend owner_settings with schedule and setup status
ALTER TABLE public.owner_settings
    ADD COLUMN IF NOT EXISTS opening_time text DEFAULT '08:00',
    ADD COLUMN IF NOT EXISTS closing_time text DEFAULT '17:00',
    ADD COLUMN IF NOT EXISTS operating_days text[] DEFAULT ARRAY['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'],
    ADD COLUMN IF NOT EXISTS delivery_ack boolean DEFAULT true,
    ADD COLUMN IF NOT EXISTS setup_completed boolean DEFAULT false,
    ADD COLUMN IF NOT EXISTS setup_completed_at timestamptz;

-- Backfill existing rows with defaults
UPDATE public.owner_settings
SET 
    opening_time = COALESCE(opening_time, '08:00'),
    closing_time = COALESCE(closing_time, '17:00'),
    operating_days = COALESCE(operating_days, ARRAY['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']),
    delivery_ack = COALESCE(delivery_ack, true)
WHERE opening_time IS NULL OR closing_time IS NULL OR operating_days IS NULL OR delivery_ack IS NULL;

-- Ensure default payment methods are set if null
UPDATE public.owner_settings
SET enabled_payment_methods = ARRAY['cod'::text, 'gcash'::text, 'maya'::text, 'card'::text]
WHERE enabled_payment_methods IS NULL OR array_length(enabled_payment_methods, 1) IS NULL;

-- 2. Central Station Setup Status Function
CREATE OR REPLACE FUNCTION public.check_station_setup_status(p_owner_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_profile record;
    v_settings record;
    v_product_count integer;
    
    v_profile_complete boolean := false;
    v_schedule_complete boolean := false;
    v_delivery_complete boolean := false;
    v_products_complete boolean := false;
    v_payments_complete boolean := false;
    
    v_completed_count integer := 0;
    v_total_sections integer := 5;
    v_percentage integer := 0;
    v_is_complete boolean := false;
    
    v_missing_fields text[] := ARRAY[]::text[];
    v_sections jsonb;
BEGIN
    -- 1. Fetch Station Profile
    SELECT 
        id, station_name, phone, town, barangay, 
        complete_address, latitude, longitude, lat, lng,
        is_open, station_availability, role
    INTO v_profile
    FROM public.profiles
    WHERE id = p_owner_id;

    IF v_profile.id IS NULL THEN
        RETURN jsonb_build_object(
            'is_complete', false,
            'percentage', 0,
            'eligible_to_open', false,
            'error', 'Station profile not found'
        );
    END IF;

    -- 2. Fetch Station Settings
    SELECT *
    INTO v_settings
    FROM public.owner_settings
    WHERE owner_id = p_owner_id;

    -- 3. Count Orderable Products with positive price
    SELECT count(*)
    INTO v_product_count
    FROM public.products
    WHERE owner_id = p_owner_id
      AND is_available = true
      AND price > 0;

    -- Section 1: Station Profile (Identity & Location)
    IF v_profile.station_name IS NOT NULL AND length(trim(v_profile.station_name)) > 0
       AND v_profile.phone IS NOT NULL AND length(trim(v_profile.phone)) > 0
       AND v_profile.town IS NOT NULL AND length(trim(v_profile.town::text)) > 0
       AND v_profile.barangay IS NOT NULL AND length(trim(v_profile.barangay)) > 0
       AND COALESCE(v_profile.latitude, v_profile.lat) IS NOT NULL
       AND COALESCE(v_profile.longitude, v_profile.lng) IS NOT NULL
       AND COALESCE(v_profile.latitude, v_profile.lat) != 0
       AND COALESCE(v_profile.longitude, v_profile.lng) != 0
    THEN
        v_profile_complete := true;
        v_completed_count := v_completed_count + 1;
    ELSE
        IF v_profile.station_name IS NULL OR length(trim(v_profile.station_name)) = 0 THEN
            v_missing_fields := array_append(v_missing_fields, 'Station Name');
        END IF;
        IF v_profile.phone IS NULL OR length(trim(v_profile.phone)) = 0 THEN
            v_missing_fields := array_append(v_missing_fields, 'Phone Number');
        END IF;
        IF v_profile.town IS NULL OR length(trim(v_profile.town::text)) = 0 THEN
            v_missing_fields := array_append(v_missing_fields, 'Town / Municipality');
        END IF;
        IF v_profile.barangay IS NULL OR length(trim(v_profile.barangay)) = 0 THEN
            v_missing_fields := array_append(v_missing_fields, 'Barangay');
        END IF;
        IF COALESCE(v_profile.latitude, v_profile.lat) IS NULL OR COALESCE(v_profile.latitude, v_profile.lat) = 0 THEN
            v_missing_fields := array_append(v_missing_fields, 'GPS Map Pin');
        END IF;
    END IF;

    -- Section 2: Operating Schedule
    IF v_settings.owner_id IS NOT NULL 
       AND v_settings.opening_time IS NOT NULL AND length(trim(v_settings.opening_time)) > 0
       AND v_settings.closing_time IS NOT NULL AND length(trim(v_settings.closing_time)) > 0
       AND v_settings.operating_days IS NOT NULL AND array_length(v_settings.operating_days, 1) > 0
    THEN
        v_schedule_complete := true;
        v_completed_count := v_completed_count + 1;
    ELSE
        v_missing_fields := array_append(v_missing_fields, 'Operating Schedule (Hours & Days)');
    END IF;

    -- Section 3: Delivery Configuration (Acknowledged centralized delivery system)
    IF v_settings.owner_id IS NOT NULL AND COALESCE(v_settings.delivery_ack, true) = true THEN
        v_delivery_complete := true;
        v_completed_count := v_completed_count + 1;
    ELSE
        v_missing_fields := array_append(v_missing_fields, 'Delivery Configuration');
    END IF;

    -- Section 4: Products & Pricing (At least 1 orderable active product)
    IF v_product_count > 0 THEN
        v_products_complete := true;
        v_completed_count := v_completed_count + 1;
    ELSE
        v_missing_fields := array_append(v_missing_fields, 'At least 1 active product with price');
    END IF;

    -- Section 5: Payment Configuration (At least 1 payment method enabled)
    IF v_settings.owner_id IS NOT NULL 
       AND v_settings.enabled_payment_methods IS NOT NULL 
       AND array_length(v_settings.enabled_payment_methods, 1) > 0 
    THEN
        v_payments_complete := true;
        v_completed_count := v_completed_count + 1;
    ELSE
        v_missing_fields := array_append(v_missing_fields, 'At least 1 payment method');
    END IF;

    -- Overall calculation
    v_percentage := ROUND((v_completed_count::numeric / v_total_sections::numeric) * 100);
    v_is_complete := (v_completed_count = v_total_sections);

    -- Build structured sections object
    v_sections := jsonb_build_object(
        'station_profile', jsonb_build_object(
            'complete', v_profile_complete,
            'title', 'Station details',
            'missing', CASE WHEN v_profile_complete THEN 'Complete' ELSE 'Missing details or map pin' END
        ),
        'operating_schedule', jsonb_build_object(
            'complete', v_schedule_complete,
            'title', 'Operating schedule',
            'opening_time', COALESCE(v_settings.opening_time, '08:00'),
            'closing_time', COALESCE(v_settings.closing_time, '17:00'),
            'operating_days', COALESCE(v_settings.operating_days, ARRAY[]::text[]),
            'missing', CASE WHEN v_schedule_complete THEN 'Complete' ELSE 'Set opening hours and operating days' END
        ),
        'delivery_rules', jsonb_build_object(
            'complete', v_delivery_complete,
            'title', 'Pricing & delivery rules',
            'missing', CASE WHEN v_delivery_complete THEN 'Complete' ELSE 'Review delivery policy' END
        ),
        'products_pricing', jsonb_build_object(
            'complete', v_products_complete,
            'title', 'Water products & catalog',
            'active_products_count', v_product_count,
            'missing', CASE WHEN v_products_complete THEN 'Complete' ELSE 'Add at least 1 orderable product' END
        ),
        'payment_methods', jsonb_build_object(
            'complete', v_payments_complete,
            'title', 'Accepted payment methods',
            'enabled_methods', COALESCE(v_settings.enabled_payment_methods, ARRAY[]::text[]),
            'missing', CASE WHEN v_payments_complete THEN 'Complete' ELSE 'Select accepted payment methods' END
        )
    );

    RETURN jsonb_build_object(
        'is_complete', v_is_complete,
        'completed_count', v_completed_count,
        'total_sections', v_total_sections,
        'percentage', v_percentage,
        'eligible_to_open', v_is_complete,
        'current_availability', COALESCE(v_profile.station_availability, 'closed'),
        'is_open', COALESCE(v_profile.is_open, false),
        'sections', v_sections,
        'missing_fields', v_missing_fields
    );
END;
$$;

ALTER FUNCTION public.check_station_setup_status(uuid) OWNER TO postgres;
GRANT ALL ON FUNCTION public.check_station_setup_status(uuid) TO anon;
GRANT ALL ON FUNCTION public.check_station_setup_status(uuid) TO authenticated;
GRANT ALL ON FUNCTION public.check_station_setup_status(uuid) TO service_role;

-- 3. Trigger on profiles to enforce CLOSED / INCOMPLETE_SETUP state
CREATE OR REPLACE FUNCTION public.enforce_station_setup_before_open()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_status jsonb;
    v_is_complete boolean;
BEGIN
    -- Only applies to owners
    IF NEW.role = 'owner' THEN
        -- Evaluate current setup status
        v_status := public.check_station_setup_status(NEW.id);
        v_is_complete := (v_status->>'is_complete')::boolean;

        IF NOT v_is_complete THEN
            -- Incomplete setup stations MUST NOT be open
            IF NEW.is_open = true OR NEW.station_availability = 'open' THEN
                RAISE EXCEPTION 'Cannot open station: Setup is incomplete (missing: %)', 
                    v_status->>'missing_fields';
            END IF;
            -- Set authoritative availability state to incomplete_setup
            NEW.station_availability := 'incomplete_setup';
            NEW.is_open := false;
        ELSE
            -- Setup is complete: if it was incomplete_setup, move to closed so owner can toggle open
            IF NEW.station_availability = 'incomplete_setup' THEN
                NEW.station_availability := 'closed';
            END IF;
            -- If owner sets is_open = true, set station_availability to open
            IF NEW.is_open = true AND NEW.station_availability NOT IN ('open', 'busy', 'maintenance') THEN
                NEW.station_availability := 'open';
            ELSIF NEW.is_open = false AND NEW.station_availability = 'open' THEN
                NEW.station_availability := 'closed';
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_station_setup_before_open ON public.profiles;
CREATE TRIGGER trg_enforce_station_setup_before_open
BEFORE UPDATE OF is_open, station_availability ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.enforce_station_setup_before_open();

-- 4. Update check_station_availability RPC to block orders if station setup incomplete
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
    v_availability TEXT;
    v_is_open BOOLEAN;
    v_max_capacity INTEGER;
    v_current_active INTEGER;
    v_distance DOUBLE PRECISION;
    v_setup_status jsonb;
BEGIN
    -- Get Station Location and Settings
    SELECT 
        p.latitude, 
        p.longitude,
        p.station_availability,
        p.is_open,
        COALESCE(s.max_concurrent_orders, 20)
    INTO v_station_lat, v_station_lng, v_availability, v_is_open, v_max_capacity
    FROM public.profiles p
    LEFT JOIN public.owner_settings s ON s.owner_id = p.id
    WHERE p.id = p_station_id;

    -- Check station existence & coordinates
    IF v_station_lat IS NULL OR v_station_lng IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'STATION_RECORDS_INCOMPLETE', 
            'message', 'Station records are incomplete (missing coordinates).'
        );
    END IF;

    -- Check availability state & setup
    IF v_availability = 'incomplete_setup' THEN
        RETURN jsonb_build_object(
            'status', 'INCOMPLETE_SETUP',
            'message', 'This station is currently completing required setup and cannot accept orders yet.'
        );
    END IF;

    IF v_is_open IS NOT TRUE OR v_availability != 'open' THEN
        RETURN jsonb_build_object(
            'status', 'CLOSED',
            'message', 'This water station is currently closed.'
        );
    END IF;

    -- Calculate Distance (Spherical Law of Cosines) in KM
    v_distance := 6371 * acos(
        pmin(1.0, 
            cos(radians(p_customer_lat)) * cos(radians(v_station_lat)) * 
            cos(radians(v_station_lng) - radians(p_customer_lng)) + 
            sin(radians(p_customer_lat)) * sin(radians(v_station_lat))
        )
    );

    -- Check Operational Capacity
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

    -- Station Available
    RETURN jsonb_build_object(
        'status', 'OK', 
        'message', 'Station available.',
        'distance', ROUND(v_distance::numeric, 2)
    );
END;
$$;

-- 5. Helper function to seed the 2 standard products safely & idempotently for a station
CREATE OR REPLACE FUNCTION public.seed_station_standard_products(p_owner_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Product 1: Empty 5 Gallon Round Water Container
    IF NOT EXISTS (
        SELECT 1 FROM public.products 
        WHERE owner_id = p_owner_id 
          AND lower(trim(name)) = lower('Empty 5 Gallon Round Water Container')
    ) THEN
        INSERT INTO public.products (
            owner_id,
            name,
            description,
            price,
            category,
            container_size,
            stock_level,
            low_stock_threshold,
            preparation_minutes,
            is_available
        ) VALUES (
            p_owner_id,
            'Empty 5 Gallon Round Water Container',
            'Empty reusable 5-gallon round water container for water refilling use.',
            180.00,
            'Accessories',
            '5 gallon',
            50,
            10,
            5,
            true
        );
    END IF;

    -- Product 2: Non spill Cap for 5 Gallon Round
    IF NOT EXISTS (
        SELECT 1 FROM public.products 
        WHERE owner_id = p_owner_id 
          AND lower(trim(name)) = lower('Non spill Cap for 5 Gallon Round')
    ) THEN
        INSERT INTO public.products (
            owner_id,
            name,
            description,
            price,
            category,
            container_size,
            stock_level,
            low_stock_threshold,
            preparation_minutes,
            is_available
        ) VALUES (
            p_owner_id,
            'Non spill Cap for 5 Gallon Round',
            'Non-spill cap designed for compatible 5-gallon round water containers.',
            15.00,
            'Accessories',
            'Cap',
            100,
            20,
            2,
            true
        );
    END IF;
END;
$$;

ALTER FUNCTION public.seed_station_standard_products(uuid) OWNER TO postgres;
GRANT ALL ON FUNCTION public.seed_station_standard_products(uuid) TO authenticated;
GRANT ALL ON FUNCTION public.seed_station_standard_products(uuid) TO service_role;

-- Seed existing owners with standard products if they don't already have them
DO $$
DECLARE
    r record;
BEGIN
    FOR r IN SELECT id FROM public.profiles WHERE role = 'owner' LOOP
        PERFORM public.seed_station_standard_products(r.id);
    END LOOP;
END;
$$;

COMMIT;

