-- Extend admin onboarding to persist the same profile details collected by
-- the customer, owner, and rider signup flows.
-- Run after admin_complete_setup.sql and remote_catchup.sql.

BEGIN;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS mi text,
  ADD COLUMN IF NOT EXISTS suffix text,
  ADD COLUMN IF NOT EXISTS preferred_water_type text,
  ADD COLUMN IF NOT EXISTS primary_water_type text,
  ADD COLUMN IF NOT EXISTS landmark text,
  ADD COLUMN IF NOT EXISTS latitude double precision,
  ADD COLUMN IF NOT EXISTS longitude double precision,
  ADD COLUMN IF NOT EXISTS first_name text,
  ADD COLUMN IF NOT EXISTS last_name text,
  ADD COLUMN IF NOT EXISTS station_name text,
  ADD COLUMN IF NOT EXISTS complete_address text,
  ADD COLUMN IF NOT EXISTS station_availability text NOT NULL DEFAULT 'open',
  ADD COLUMN IF NOT EXISTS is_open boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS price_per_gallon numeric(10, 2) DEFAULT 25.00;

ALTER TABLE public.owner_settings
  ADD COLUMN IF NOT EXISTS base_delivery_fee numeric(10, 2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS price_per_gallon numeric(10, 2) NOT NULL DEFAULT 25.00;

CREATE OR REPLACE FUNCTION public.admin_create_user(
  p_email text,
  p_password text,
  p_role text,
  p_full_name text,
  p_phone text DEFAULT NULL,
  p_town text DEFAULT NULL,
  p_barangay text DEFAULT NULL,
  p_owner_id uuid DEFAULT NULL,
  p_region_id uuid DEFAULT NULL,
  p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions
AS $$
DECLARE
  v_user_id uuid := gen_random_uuid();
  v_username text := split_part(lower(p_email), '@', 1);
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only administrators can create accounts'
      USING ERRCODE = '42501';
  END IF;

  IF p_role IS NULL OR p_role NOT IN ('customer', 'rider', 'owner') THEN
    RAISE EXCEPTION 'Unsupported account role: %', p_role
      USING ERRCODE = '22023';
  END IF;

  IF p_email IS NULL OR btrim(p_email) = ''
     OR p_full_name IS NULL OR btrim(p_full_name) = ''
     OR p_password IS NULL OR length(btrim(p_password)) < 8
     OR p_password !~ '[A-Za-z]' OR p_password !~ '[0-9]' THEN
    RAISE EXCEPTION 'A valid email and password of at least 8 characters with a letter and number are required'
      USING ERRCODE = '22023';
  END IF;

  IF p_role = 'rider' AND p_owner_id IS NULL THEN
    RAISE EXCEPTION 'A station owner must be assigned to every rider'
      USING ERRCODE = '22023';
  END IF;

  IF p_role = 'rider' AND NOT EXISTS (
    SELECT 1
    FROM public.profiles owner_profile
    WHERE owner_profile.id = p_owner_id
      AND owner_profile.role::text = 'owner'
      AND lower(btrim(owner_profile.town)) = lower(btrim(p_town))
  ) THEN
    RAISE EXCEPTION 'The assigned rider owner must belong to the selected municipality'
      USING ERRCODE = '22023';
  END IF;

  INSERT INTO auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000000',
    v_user_id,
    'authenticated',
    'authenticated',
    lower(btrim(p_email)),
    extensions.crypt(p_password, extensions.gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object(
      'role', p_role,
      'full_name', p_full_name,
      'username', v_username,
      'phone', p_phone,
      'town', p_town,
      'barangay', p_barangay,
      'owner_id', p_owner_id
    ),
    now(),
    now()
  );

  INSERT INTO auth.identities (
    id, user_id, identity_data, provider, provider_id, created_at, updated_at
  ) VALUES (
    gen_random_uuid(),
    v_user_id,
    jsonb_build_object('sub', v_user_id::text, 'email', lower(btrim(p_email))),
    'email',
    v_user_id::text,
    now(),
    now()
  );

  INSERT INTO public.profiles (
    id, email, username, full_name, role, phone, town, barangay, owner_id,
    created_at, updated_at
  ) VALUES (
    v_user_id, lower(btrim(p_email)), v_username, p_full_name, p_role, p_phone,
    p_town, p_barangay, p_owner_id, now(), now()
  )
  ON CONFLICT (id) DO UPDATE
  SET email = EXCLUDED.email,
      username = EXCLUDED.username,
      full_name = EXCLUDED.full_name,
      role = EXCLUDED.role,
      phone = EXCLUDED.phone,
      town = EXCLUDED.town,
      barangay = EXCLUDED.barangay,
      owner_id = EXCLUDED.owner_id,
      updated_at = now();

  INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id, details)
  VALUES (
    auth.uid(),
    'create_user',
    'user',
    v_user_id::text,
    jsonb_build_object('role', p_role, 'reason', p_reason, 'region_id', p_region_id)
  );

  RETURN jsonb_build_object('id', v_user_id, 'role', p_role);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_create_station(
  p_email text,
  p_password text,
  p_station_name text,
  p_owner_name text,
  p_phone text DEFAULT NULL,
  p_town text DEFAULT NULL,
  p_barangay text DEFAULT NULL,
  p_complete_address text DEFAULT NULL,
  p_latitude double precision DEFAULT NULL,
  p_longitude double precision DEFAULT NULL,
  p_region_id uuid DEFAULT NULL,
  p_base_delivery_fee numeric DEFAULT 0,
  p_price_per_gallon numeric DEFAULT 25,
  p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_user jsonb;
  v_owner_id uuid;
  v_station_data jsonb;
  v_columns text;
  v_values text;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only administrators can create stations'
      USING ERRCODE = '42501';
  END IF;

  IF p_station_name IS NULL OR btrim(p_station_name) = ''
     OR p_owner_name IS NULL OR btrim(p_owner_name) = ''
     OR p_latitude IS NULL OR p_latitude NOT BETWEEN -90 AND 90
     OR p_longitude IS NULL OR p_longitude NOT BETWEEN -180 AND 180 THEN
    RAISE EXCEPTION 'Station name, owner name, and valid coordinates are required'
      USING ERRCODE = '22023';
  END IF;

  v_user := public.admin_create_user(
    p_email, p_password, 'owner', p_owner_name, p_phone, p_town, p_barangay,
    NULL, p_region_id, p_reason
  );
  v_owner_id := (v_user->>'id')::uuid;

  UPDATE public.profiles
  SET station_name = p_station_name,
      complete_address = p_complete_address,
      latitude = p_latitude,
      longitude = p_longitude,
      station_availability = 'pending',
      is_open = false,
      price_per_gallon = p_price_per_gallon,
      updated_at = now()
  WHERE id = v_owner_id;

  INSERT INTO public.owner_settings (
    owner_id, base_delivery_fee, price_per_gallon
  ) VALUES (
    v_owner_id, p_base_delivery_fee, p_price_per_gallon
  )
  ON CONFLICT (owner_id) DO UPDATE
  SET base_delivery_fee = EXCLUDED.base_delivery_fee,
      price_per_gallon = EXCLUDED.price_per_gallon;

  v_station_data := jsonb_build_object(
    'id', v_owner_id,
    'owner_id', v_owner_id,
    'name', p_station_name,
    'station_name', p_station_name,
    'town', p_town,
    'barangay', p_barangay,
    'address', p_complete_address,
    'latitude', p_latitude,
    'longitude', p_longitude,
    'is_accepting_orders', false,
    'status', 'pending',
    'created_at', now()
  );

  SELECT string_agg(format('%I', attr.attname), ', ' ORDER BY attr.attnum),
         string_agg(format('%L', v.value), ', ' ORDER BY attr.attnum)
  INTO v_columns, v_values
  FROM jsonb_each_text(v_station_data) v
  JOIN pg_attribute attr
    ON attr.attrelid = 'public.water_refill_stations'::regclass
   AND attr.attname = v.key
   AND attr.attnum > 0
   AND attr.attgenerated = ''
   AND attr.attidentity = ''
   AND NOT attr.attisdropped;

  IF v_columns IS NULL THEN
    RAISE EXCEPTION 'Could not map station fields to water_refill_stations';
  END IF;

  EXECUTE format(
    'INSERT INTO public.water_refill_stations (%s) VALUES (%s) ON CONFLICT DO NOTHING',
    v_columns,
    v_values
  );

  PERFORM public.sync_owner_default_product(v_owner_id);

  RETURN jsonb_build_object('id', v_owner_id, 'role', 'owner');
END;
$$;

REVOKE ALL ON FUNCTION public.admin_create_user(
  text, text, text, text, text, text, text, uuid, uuid, text
) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_create_station(
  text, text, text, text, text, text, text, text, double precision,
  double precision, uuid, numeric, numeric, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_create_user(
  text, text, text, text, text, text, text, uuid, uuid, text
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_create_station(
  text, text, text, text, text, text, text, text, double precision,
  double precision, uuid, numeric, numeric, text
) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_create_signup_user(
  p_email text,
  p_password text,
  p_role text,
  p_full_name text,
  p_phone text,
  p_town text,
  p_barangay text,
  p_owner_id uuid,
  p_region_id uuid,
  p_reason text,
  p_username text,
  p_first_name text,
  p_last_name text,
  p_middle_initial text,
  p_suffix text,
  p_complete_address text,
  p_landmark text,
  p_latitude double precision,
  p_longitude double precision,
  p_water_type text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only administrators can create accounts'
      USING ERRCODE = '42501';
  END IF;

  IF p_role IS NULL OR p_role NOT IN ('customer', 'rider') THEN
    RAISE EXCEPTION 'Unsupported signup role: %', p_role
      USING ERRCODE = '22023';
  END IF;

  IF (p_latitude IS NOT NULL AND p_latitude NOT BETWEEN -90 AND 90)
     OR (p_longitude IS NOT NULL AND p_longitude NOT BETWEEN -180 AND 180) THEN
    RAISE EXCEPTION 'The selected account location is invalid'
      USING ERRCODE = '22023';
  END IF;

  IF p_role = 'customer' AND (
    p_water_type IS NULL OR
    p_water_type NOT IN ('Purified Water', 'Mineral Water', 'Alkaline Water')
  ) THEN
    RAISE EXCEPTION 'Unsupported customer water preference: %', p_water_type
      USING ERRCODE = '22023';
  END IF;

  IF p_role = 'rider' THEN
    IF p_owner_id IS NULL THEN
      RAISE EXCEPTION 'A station owner must be assigned to every rider'
        USING ERRCODE = '22023';
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM public.profiles owner_profile
      WHERE owner_profile.id = p_owner_id
        AND owner_profile.role::text = 'owner'
        AND lower(btrim(owner_profile.town)) = lower(btrim(p_town))
    ) THEN
      RAISE EXCEPTION 'The assigned owner must belong to the selected municipality'
        USING ERRCODE = '22023';
    END IF;
  END IF;

  PERFORM public.admin_create_user(
    p_email,
    p_password,
    p_role,
    p_full_name,
    p_phone,
    p_town,
    p_barangay,
    p_owner_id,
    p_region_id,
    p_reason
  );

  SELECT profile.id
  INTO v_user_id
  FROM public.profiles profile
  WHERE lower(profile.email) = lower(p_email)
  ORDER BY profile.created_at DESC
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'The new account profile was not created'
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.profiles
  SET username = p_username,
      first_name = p_first_name,
      last_name = p_last_name,
      mi = nullif(btrim(p_middle_initial), ''),
      suffix = nullif(btrim(p_suffix), ''),
      complete_address = nullif(btrim(p_complete_address), ''),
      landmark = nullif(btrim(p_landmark), ''),
      latitude = p_latitude,
      longitude = p_longitude,
      preferred_water_type = CASE
        WHEN p_role = 'customer' THEN p_water_type
        ELSE preferred_water_type
      END,
      owner_id = CASE WHEN p_role = 'rider' THEN p_owner_id ELSE owner_id END,
      updated_at = now()
  WHERE id = v_user_id;

  UPDATE auth.users
  SET raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) ||
    jsonb_strip_nulls(jsonb_build_object(
      'username', p_username,
      'first_name', p_first_name,
      'last_name', p_last_name,
      'mi', nullif(btrim(p_middle_initial), ''),
      'suffix', nullif(btrim(p_suffix), ''),
      'complete_address', nullif(btrim(p_complete_address), ''),
      'landmark', nullif(btrim(p_landmark), ''),
      'latitude', p_latitude,
      'longitude', p_longitude,
      'preferred_water_type', CASE
        WHEN p_role = 'customer' THEN p_water_type
        ELSE NULL
      END,
      'owner_id', CASE
        WHEN p_role = 'rider' THEN p_owner_id::text
        ELSE NULL
      END
    )),
      updated_at = now()
  WHERE id = v_user_id;

  RETURN jsonb_build_object('id', v_user_id, 'role', p_role);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_create_signup_station(
  p_email text,
  p_password text,
  p_station_name text,
  p_owner_name text,
  p_phone text,
  p_town text,
  p_barangay text,
  p_complete_address text,
  p_latitude double precision,
  p_longitude double precision,
  p_region_id uuid,
  p_base_delivery_fee numeric,
  p_price_per_gallon numeric,
  p_reason text,
  p_username text,
  p_first_name text,
  p_last_name text,
  p_middle_initial text,
  p_suffix text,
  p_primary_water_type text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only administrators can create station accounts'
      USING ERRCODE = '42501';
  END IF;

  IF p_primary_water_type IS NULL OR p_primary_water_type NOT IN (
    'Purified Water', 'Mineral Water', 'Alkaline Water'
  ) THEN
    RAISE EXCEPTION 'Unsupported station water type: %', p_primary_water_type
      USING ERRCODE = '22023';
  END IF;

  IF p_latitude IS NULL OR p_latitude NOT BETWEEN -90 AND 90
     OR p_longitude IS NULL OR p_longitude NOT BETWEEN -180 AND 180 THEN
    RAISE EXCEPTION 'The selected station location is invalid'
      USING ERRCODE = '22023';
  END IF;

  PERFORM public.admin_create_station(
    p_email,
    p_password,
    p_station_name,
    p_owner_name,
    p_phone,
    p_town,
    p_barangay,
    p_complete_address,
    p_latitude,
    p_longitude,
    p_region_id,
    p_base_delivery_fee,
    p_price_per_gallon,
    p_reason
  );

  SELECT profile.id
  INTO v_user_id
  FROM public.profiles profile
  WHERE lower(profile.email) = lower(p_email)
    AND profile.role::text = 'owner'
  ORDER BY profile.created_at DESC
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'The new station owner profile was not created'
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.profiles
  SET username = p_username,
      first_name = p_first_name,
      last_name = p_last_name,
      mi = nullif(btrim(p_middle_initial), ''),
      suffix = nullif(btrim(p_suffix), ''),
      station_name = p_station_name,
      primary_water_type = p_primary_water_type,
      latitude = p_latitude,
      longitude = p_longitude,
      town = p_town,
      barangay = p_barangay,
      complete_address = p_complete_address,
      updated_at = now()
  WHERE id = v_user_id;

  PERFORM public.sync_owner_default_product(v_user_id);

  UPDATE auth.users
  SET raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) ||
    jsonb_strip_nulls(jsonb_build_object(
      'username', p_username,
      'first_name', p_first_name,
      'last_name', p_last_name,
      'mi', nullif(btrim(p_middle_initial), ''),
      'suffix', nullif(btrim(p_suffix), ''),
      'station_name', p_station_name,
      'primary_water_type', p_primary_water_type,
      'latitude', p_latitude,
      'longitude', p_longitude,
      'town', p_town,
      'barangay', p_barangay,
      'complete_address', p_complete_address
    )),
      updated_at = now()
  WHERE id = v_user_id;

  RETURN jsonb_build_object('id', v_user_id, 'role', 'owner');
END;
$$;

REVOKE ALL ON FUNCTION public.admin_create_signup_user(
  text, text, text, text, text, text, text, uuid, uuid, text,
  text, text, text, text, text, text, text, double precision,
  double precision, text
) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_create_signup_station(
  text, text, text, text, text, text, text, text, double precision,
  double precision, uuid, numeric, numeric, text, text, text, text,
  text, text, text
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.admin_create_signup_user(
  text, text, text, text, text, text, text, uuid, uuid, text,
  text, text, text, text, text, text, text, double precision,
  double precision, text
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_create_signup_station(
  text, text, text, text, text, text, text, text, double precision,
  double precision, uuid, numeric, numeric, text, text, text, text,
  text, text, text
) TO authenticated;

COMMIT;
