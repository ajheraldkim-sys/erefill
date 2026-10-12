-- Function to allow station owners to unlink a rider from their station
CREATE OR REPLACE FUNCTION public.owner_unlink_rider(p_rider_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'auth', 'extensions'
AS $$
DECLARE
  v_owner_id uuid;
BEGIN
  v_owner_id := auth.uid();
  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Verify that the caller is the owner of this rider or is platform admin
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = p_rider_id
      AND role = 'rider'::user_role
      AND (owner_id = v_owner_id OR public.is_admin())
  ) THEN
    RAISE EXCEPTION 'Not authorized to unlink this rider';
  END IF;

  -- Detach rider from station
  UPDATE public.profiles
  SET
    owner_id = NULL,
    station_id = NULL,
    updated_at = now()
  WHERE id = p_rider_id;

  RETURN jsonb_build_object(
    'success', true,
    'message', 'Rider successfully unlinked from station'
  );
END;
$$;

-- Function to allow station owners to suspend or activate a rider
CREATE OR REPLACE FUNCTION public.owner_set_rider_status(
  p_rider_id uuid,
  p_is_suspended boolean,
  p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'auth', 'extensions'
AS $$
DECLARE
  v_owner_id uuid;
BEGIN
  v_owner_id := auth.uid();
  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Verify that caller owns this rider or is admin
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = p_rider_id
      AND role = 'rider'::user_role
      AND (owner_id = v_owner_id OR public.is_admin())
  ) THEN
    RAISE EXCEPTION 'Not authorized to change status of this rider';
  END IF;

  UPDATE public.profiles
  SET
    is_suspended = p_is_suspended,
    suspended_at = CASE WHEN p_is_suspended THEN now() ELSE NULL END,
    suspended_reason = CASE WHEN p_is_suspended THEN COALESCE(p_reason, 'Suspended by station owner') ELSE NULL END,
    updated_at = now()
  WHERE id = p_rider_id;

  RETURN jsonb_build_object(
    'success', true,
    'is_suspended', p_is_suspended,
    'message', CASE WHEN p_is_suspended THEN 'Rider suspended' ELSE 'Rider activated' END
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.owner_unlink_rider(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.owner_set_rider_status(uuid, boolean, text) TO authenticated;

