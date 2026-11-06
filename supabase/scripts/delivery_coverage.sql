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
BEGIN;

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

COMMIT;

NOTIFY pgrst, 'reload schema';
