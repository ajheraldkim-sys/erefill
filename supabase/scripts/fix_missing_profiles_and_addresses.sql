-- ============================================================================
-- Fix Missing Profiles, Foreign Key Constraint 23503, and Address Migration
-- ============================================================================

-- 1. Limit self-service profile creation to supported signup roles.
-- Admin roles and rider-to-owner links must be assigned by trusted provisioning.
DROP POLICY IF EXISTS "profiles_users_insert_own" ON public.profiles;
CREATE POLICY "profiles_users_insert_own"
  ON public.profiles
  FOR INSERT
  TO authenticated
  WITH CHECK (
    id = auth.uid()
    AND role IN (
      'customer'::public.user_role,
      'owner'::public.user_role,
      'rider'::public.user_role
    )
    AND owner_id IS NULL
  );

DROP POLICY IF EXISTS "profiles_users_update_own" ON public.profiles;
CREATE POLICY "profiles_users_update_own"
  ON public.profiles
  FOR UPDATE
  TO authenticated
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

-- 2. Backfill any existing users in auth.users missing in public.profiles
INSERT INTO public.profiles (
  id,
  email,
  username,
  full_name,
  role,
  town
)
SELECT
  u.id,
  u.email,
  COALESCE(u.raw_user_meta_data->>'username', 'user_' || substr(u.id::text, 1, 8)),
  COALESCE(u.raw_user_meta_data->>'full_name', 'User'),
  CASE
    WHEN u.raw_user_meta_data->>'role' IN ('customer', 'owner', 'rider') THEN (u.raw_user_meta_data->>'role')::public.user_role
    ELSE 'customer'::public.user_role
  END,
  CASE
    WHEN lower(trim(COALESCE(u.raw_user_meta_data->>'town', ''))) = 'cantilan' THEN 'Cantilan'::public.municipality
    WHEN lower(trim(COALESCE(u.raw_user_meta_data->>'town', ''))) = 'madrid' THEN 'Madrid'::public.municipality
    ELSE NULL
  END
FROM auth.users u
LEFT JOIN public.profiles p ON p.id = u.id
WHERE p.id IS NULL
ON CONFLICT (id) DO NOTHING;

-- 3. Create ensure_user_profile() RPC with SECURITY DEFINER
-- Allows clients to self-heal their profile row safely regardless of RLS
CREATE OR REPLACE FUNCTION public.ensure_user_profile()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_user auth.users%ROWTYPE;
  v_role public.user_role;
  v_town public.municipality;
  v_complete_address text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Not authenticated');
  END IF;

  -- If profile already exists, return success immediately
  IF EXISTS (SELECT 1 FROM public.profiles WHERE id = v_uid) THEN
    RETURN jsonb_build_object('success', true, 'message', 'Profile exists');
  END IF;

  -- Fetch user from auth.users
  SELECT * INTO v_user FROM auth.users WHERE id = v_uid;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'Auth user not found');
  END IF;

  -- Safe role parsing
  BEGIN
    IF v_user.raw_user_meta_data->>'role' IN ('customer', 'owner', 'rider') THEN
      v_role := (v_user.raw_user_meta_data->>'role')::public.user_role;
    ELSE
      v_role := 'customer'::public.user_role;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_role := 'customer'::public.user_role;
  END;

  -- Safe town parsing
  BEGIN
    IF lower(trim(COALESCE(v_user.raw_user_meta_data->>'town', ''))) = 'cantilan' THEN
      v_town := 'Cantilan'::public.municipality;
    ELSIF lower(trim(COALESCE(v_user.raw_user_meta_data->>'town', ''))) = 'madrid' THEN
      v_town := 'Madrid'::public.municipality;
    ELSE
      v_town := NULL;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_town := NULL;
  END;
  v_complete_address := NULLIF(TRIM(COALESCE(v_user.raw_user_meta_data->>'complete_address', '')), '');

  INSERT INTO public.profiles (
    id,
    email,
    username,
    full_name,
    first_name,
    last_name,
    mi,
    suffix,
    role,
    phone,
    town,
    barangay,
    complete_address,
    landmark,
    station_name,
    latitude,
    longitude
  ) VALUES (
    v_user.id,
    v_user.email,
    COALESCE(v_user.raw_user_meta_data->>'username', 'user_' || substr(v_user.id::text, 1, 8)),
    COALESCE(v_user.raw_user_meta_data->>'full_name', 'User'),
    v_user.raw_user_meta_data->>'first_name',
    v_user.raw_user_meta_data->>'last_name',
    v_user.raw_user_meta_data->>'mi',
    v_user.raw_user_meta_data->>'suffix',
    v_role,
    v_user.raw_user_meta_data->>'phone',
    v_town,
    v_user.raw_user_meta_data->>'barangay',
    v_complete_address,
    v_user.raw_user_meta_data->>'landmark',
    v_user.raw_user_meta_data->>'station_name',
    (v_user.raw_user_meta_data->>'latitude')::DOUBLE PRECISION,
    (v_user.raw_user_meta_data->>'longitude')::DOUBLE PRECISION
  )
  ON CONFLICT (id) DO NOTHING;

  RETURN jsonb_build_object('success', true, 'message', 'Profile created successfully');
END;
$$;

GRANT EXECUTE ON FUNCTION public.ensure_user_profile() TO authenticated;

-- 4. Harden handle_new_user() trigger function against invalid enum casting
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role public.user_role;
  v_town public.municipality;
  v_complete_address text;
BEGIN
  -- Safe role resolution
  IF new.raw_user_meta_data->>'role' IN ('customer', 'owner', 'rider') THEN
    v_role := (new.raw_user_meta_data->>'role')::public.user_role;
  ELSE
    v_role := 'customer'::public.user_role;
  END IF;

  -- Safe municipality enum resolution
  IF lower(trim(COALESCE(new.raw_user_meta_data->>'town', ''))) = 'cantilan' THEN
    v_town := 'Cantilan'::public.municipality;
  ELSIF lower(trim(COALESCE(new.raw_user_meta_data->>'town', ''))) = 'madrid' THEN
    v_town := 'Madrid'::public.municipality;
  ELSE
    v_town := NULL;
  END IF;
  v_complete_address := NULLIF(TRIM(COALESCE(new.raw_user_meta_data->>'complete_address', '')), '');

  INSERT INTO public.profiles (
    id,
    email,
    username,
    full_name,
    first_name,
    last_name,
    mi,
    suffix,
    role,
    phone,
    town,
    barangay,
    complete_address,
    landmark,
    station_name,
    latitude,
    longitude
  )
  VALUES (
    new.id,
    new.email,
    COALESCE(new.raw_user_meta_data->>'username', 'user_' || substr(new.id::text, 1, 8)),
    COALESCE(new.raw_user_meta_data->>'full_name', 'New User'),
    new.raw_user_meta_data->>'first_name',
    new.raw_user_meta_data->>'last_name',
    new.raw_user_meta_data->>'mi',
    new.raw_user_meta_data->>'suffix',
    v_role,
    new.raw_user_meta_data->>'phone',
    v_town,
    new.raw_user_meta_data->>'barangay',
    v_complete_address,
    new.raw_user_meta_data->>'landmark',
    new.raw_user_meta_data->>'station_name',
    (new.raw_user_meta_data->>'latitude')::DOUBLE PRECISION,
    (new.raw_user_meta_data->>'longitude')::DOUBLE PRECISION
  )
  ON CONFLICT (id) DO UPDATE
    SET email = EXCLUDED.email,
        username = EXCLUDED.username,
        full_name = EXCLUDED.full_name,
        first_name = EXCLUDED.first_name,
        last_name = EXCLUDED.last_name,
        mi = EXCLUDED.mi,
        suffix = EXCLUDED.suffix,
        phone = COALESCE(EXCLUDED.phone, profiles.phone),
        town = COALESCE(EXCLUDED.town, profiles.town),
        barangay = COALESCE(EXCLUDED.barangay, profiles.barangay),
        complete_address = COALESCE(EXCLUDED.complete_address, profiles.complete_address),
        landmark = COALESCE(EXCLUDED.landmark, profiles.landmark),
        station_name = COALESCE(EXCLUDED.station_name, profiles.station_name),
        latitude = COALESCE(EXCLUDED.latitude, profiles.latitude),
        longitude = COALESCE(EXCLUDED.longitude, profiles.longitude);

  RETURN new;
END;
$$;
