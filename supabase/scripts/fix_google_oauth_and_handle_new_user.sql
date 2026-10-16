-- ==============================================================================
-- Migration: Fix Google OAuth Signup & Login Profile Trigger
-- Description: Ensures Google OAuth users (and other social logins) get valid
-- profiles created automatically in public.profiles without crashing on:
-- 1. Metadata field discrepancies (name vs full_name, picture vs avatar_url, given_name/family_name)
-- 2. Municipality enum casting errors when town is null or empty
-- 3. Defaulting role to 'customer' for OAuth users
-- ==============================================================================

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
  v_full_name text;
  v_first_name text;
  v_last_name text;
  v_username text;
  v_avatar_url text;
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

  -- 4. Upsert Profile
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
    avatar_url,
    latitude,
    longitude
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
    (new.raw_user_meta_data->>'longitude')::DOUBLE PRECISION
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
        longitude = COALESCE(EXCLUDED.longitude, profiles.longitude);

  RETURN new;
END;
$$;

-- Ensure trigger is active
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

