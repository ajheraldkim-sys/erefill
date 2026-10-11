CREATE OR REPLACE FUNCTION public.owner_update_rider_credentials(
  p_rider_id uuid,
  p_first_name text DEFAULT NULL,
  p_last_name text DEFAULT NULL,
  p_mi text DEFAULT NULL,
  p_suffix text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_vehicle_type text DEFAULT NULL,
  p_license_number text DEFAULT NULL,
  p_password text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'auth', 'extensions'
AS $$
DECLARE
  v_owner_id uuid;
  v_full_name text;
BEGIN
  v_owner_id := auth.uid();
  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Ensure caller is owner of this rider or admin
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles 
    WHERE id = p_rider_id 
      AND role = 'rider'::user_role 
      AND (owner_id = v_owner_id OR public.is_admin())
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage this rider';
  END IF;

  -- Build full name
  v_full_name := trim(regexp_replace(
    concat_ws(' ', nullif(trim(p_first_name), ''), nullif(trim(p_mi), ''), nullif(trim(p_last_name), ''), nullif(trim(p_suffix), '')),
    '\s+', ' ', 'g'
  ));

  -- Update profile
  UPDATE public.profiles
  SET 
    first_name = COALESCE(p_first_name, first_name),
    last_name = COALESCE(p_last_name, last_name),
    mi = p_mi,
    suffix = p_suffix,
    full_name = CASE WHEN v_full_name <> '' THEN v_full_name ELSE full_name END,
    phone = COALESCE(p_phone, phone),
    vehicle_type = COALESCE(p_vehicle_type, vehicle_type),
    license_number = COALESCE(p_license_number, license_number)
  WHERE id = p_rider_id;

  -- Update password if provided
  IF p_password IS NOT NULL AND length(trim(p_password)) >= 6 THEN
    UPDATE auth.users
    SET encrypted_password = extensions.crypt(trim(p_password), extensions.gen_salt('bf'))
    WHERE id = p_rider_id;
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.owner_update_rider_credentials(uuid, text, text, text, text, text, text, text, text) TO authenticated;

