CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role public.user_role;
  v_complete_address text;
BEGIN
  v_role := COALESCE((new.raw_user_meta_data->>'role'), 'customer')::user_role;
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
    (new.raw_user_meta_data->>'town')::municipality,
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
        role = EXCLUDED.role,
        phone = EXCLUDED.phone,
        town = EXCLUDED.town,
        barangay = EXCLUDED.barangay,
        complete_address = EXCLUDED.complete_address,
        landmark = EXCLUDED.landmark,
        station_name = EXCLUDED.station_name,
        latitude = EXCLUDED.latitude,
        longitude = EXCLUDED.longitude;

  -- Auto-create initial saved address for customer accounts
  IF v_role = 'customer' AND v_complete_address IS NOT NULL THEN
    INSERT INTO public.customer_addresses (
      customer_id,
      label,
      complete_address,
      barangay,
      town,
      landmark,
      latitude,
      longitude,
      is_default
    )
    VALUES (
      new.id,
      'Home',
      v_complete_address,
      new.raw_user_meta_data->>'barangay',
      new.raw_user_meta_data->>'town',
      COALESCE(new.raw_user_meta_data->>'landmark', ''),
      COALESCE((new.raw_user_meta_data->>'latitude')::DOUBLE PRECISION, 9.3333),
      COALESCE((new.raw_user_meta_data->>'longitude')::DOUBLE PRECISION, 125.9833),
      true
    )
    ON CONFLICT DO NOTHING;
  END IF;

  RETURN new;
END;
$function$;

