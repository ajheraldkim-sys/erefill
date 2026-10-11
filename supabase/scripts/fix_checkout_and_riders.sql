-- 1. Fix guard_profile_role_changes to allow direct DB maintenance, admin, and owners assigning their own riders
CREATE OR REPLACE FUNCTION public.guard_profile_role_changes()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_is_admin boolean := false;
  v_is_owner boolean := false;
BEGIN
  -- If nothing privileged changed, allow immediately
  IF (NEW.role IS NOT DISTINCT FROM OLD.role)
    AND (NEW.is_suspended IS NOT DISTINCT FROM OLD.is_suspended)
    AND (NEW.owner_id IS NOT DISTINCT FROM OLD.owner_id)
  THEN
    RETURN NEW;
  END IF;

  -- Allow service_role or direct database superuser operations (auth.uid() is null in direct migrations/CLI)
  IF auth.role() = 'service_role' OR auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  -- Platform Admin always allowed
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'admin'
  ) INTO v_is_admin;

  IF v_is_admin THEN
    RETURN NEW;
  END IF;

  -- Station owner assigning / managing a rider for their own station
  IF (NEW.role = 'rider' OR OLD.role = 'rider')
    AND (NEW.is_suspended IS NOT DISTINCT FROM OLD.is_suspended)
  THEN
    IF auth.uid() = NEW.owner_id AND (OLD.owner_id IS NULL OR OLD.owner_id = auth.uid()) THEN
      SELECT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role = 'owner'
      ) INTO v_is_owner;
      
      IF v_is_owner THEN
        RETURN NEW;
      END IF;
    END IF;
  END IF;

  RAISE EXCEPTION 'Unauthorized: You cannot alter protected account fields.';
END;
$function$;

-- 2. Fix create_order_atomic (type casting for idempotency_key/region_id, items jsonb, and order_items.price_at_purchase)
CREATE OR REPLACE FUNCTION public.create_order_atomic(p_order_data jsonb, p_items_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_customer_id uuid := auth.uid();
  v_owner_id uuid;
  v_payment_method text;
  v_order_id uuid;
  v_item record;
  v_product record;
  v_computed_subtotal numeric(10,2) := 0;
  v_delivery_fee numeric(10,2) := 0;
  v_total_amount numeric(10,2) := 0;
  v_order_row public.orders%ROWTYPE;
  v_lat double precision;
  v_lng double precision;
BEGIN
  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required to place an order.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = v_customer_id AND role = 'customer'
  ) THEN
    RAISE EXCEPTION 'Only customer accounts can place orders.';
  END IF;

  v_owner_id := (p_order_data->>'owner_id')::uuid;
  v_payment_method := lower(trim(coalesce(p_order_data->>'payment_method', 'cod')));
  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'Station owner ID is required.';
  END IF;

  -- 1. Verify owner station exists and is open
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles 
    WHERE id = v_owner_id AND role = 'owner' AND coalesce(station_availability, 'open') = 'open'
  ) THEN
    RAISE EXCEPTION 'This water station is currently closed or unavailable.';
  END IF;

  IF NOT public.is_station_payment_method_available(v_owner_id, v_payment_method) THEN
    RAISE EXCEPTION 'This payment method is not available for this station.';
  END IF;

  -- 2. Verify line items against products catalog
  FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items_data) AS x(
    product_id uuid,
    quantity integer,
    product_name text
  )
  LOOP
    IF v_item.quantity <= 0 THEN
      RAISE EXCEPTION 'Invalid quantity for item %', v_item.product_name;
    END IF;

    SELECT * INTO v_product FROM public.products
    WHERE id = v_item.product_id AND owner_id = v_owner_id AND is_available = true;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Product % is unavailable at this station.', v_item.product_name;
    END IF;

    v_computed_subtotal := v_computed_subtotal + (v_product.price * v_item.quantity);
  END LOOP;

  IF v_computed_subtotal <= 0 THEN
    RAISE EXCEPTION 'Cart cannot be empty.';
  END IF;

  -- 3. Get server-side base delivery fee from owner_settings
  SELECT coalesce(base_delivery_fee, 0) INTO v_delivery_fee
  FROM public.owner_settings WHERE owner_id = v_owner_id;

  -- 4. Calculate server-verified total amount
  v_total_amount := v_computed_subtotal + v_delivery_fee;
  
  v_lat := (p_order_data->>'customer_latitude')::double precision;
  v_lng := (p_order_data->>'customer_longitude')::double precision;

  -- 5. Insert order
  INSERT INTO public.orders (
    customer_id,
    owner_id,
    station_name,
    customer_name,
    customer_phone,
    customer_address,
    customer_barangay,
    customer_municipality,
    customer_landmark,
    idempotency_key,
    subtotal,
    delivery_fee,
    total_amount,
    payment_method,
    payment_status,
    notes,
    region_id,
    customer_latitude,
    customer_longitude,
    delivery_lat,
    delivery_lng,
    delivery_latitude,
    delivery_longitude,
    items,
    status
  ) VALUES (
    v_customer_id,
    v_owner_id,
    coalesce(p_order_data->>'station_name', 'Water Station'),
    p_order_data->>'customer_name',
    p_order_data->>'customer_phone',
    p_order_data->>'customer_address',
    p_order_data->>'customer_barangay',
    p_order_data->>'customer_municipality',
    p_order_data->>'customer_landmark',
    NULLIF(p_order_data->>'idempotency_key', '')::uuid,
    v_computed_subtotal,
    v_delivery_fee,
    v_total_amount,
    v_payment_method,
    'pending',
    p_order_data->>'notes',
    NULLIF(p_order_data->>'region_id', '')::uuid,
    v_lat,
    v_lng,
    v_lat,
    v_lng,
    v_lat,
    v_lng,
    coalesce(p_items_data, '[]'::jsonb),
    'pending'
  )
  RETURNING * INTO v_order_row;

  v_order_id := v_order_row.id;

  -- 6. Insert order items with correct column name price_at_purchase
  FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items_data) AS x(
    product_id uuid,
    quantity integer,
    product_name text
  )
  LOOP
    SELECT * INTO v_product FROM public.products WHERE id = v_item.product_id;

    INSERT INTO public.order_items (
      order_id,
      product_id,
      product_name,
      quantity,
      price_at_purchase,
      subtotal
    ) VALUES (
      v_order_id,
      v_item.product_id,
      v_product.name,
      v_item.quantity,
      v_product.price,
      (v_product.price * v_item.quantity)
    );
  END LOOP;

  -- 7. Notify Station Owner of incoming refill order
  INSERT INTO public.system_notifications (
    user_id,
    type,
    priority,
    title,
    content,
    metadata
  ) VALUES (
    v_owner_id,
    'system_alert',
    'high',
    'New Refill Order',
    coalesce(p_order_data->>'customer_name', 'A customer') || ' placed a new refill order of PHP ' || trim(to_char(v_total_amount, '999999990.00')) || ' (' || upper(coalesce(p_order_data->>'payment_method', 'cod')) || ').',
    jsonb_build_object('order_id', v_order_id, 'status', 'pending', 'total_amount', v_total_amount)
  );

  RETURN jsonb_build_object(
    'id', v_order_id,
    'total_amount', v_total_amount,
    'status', 'pending'
  );
END;
$function$;

-- 3. Fix handle_new_user trigger to preserve owner_id
CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role public.user_role;
  v_complete_address text;
  v_owner_id uuid;
BEGIN
  v_role := COALESCE((new.raw_user_meta_data->>'role'), 'customer')::user_role;
  v_complete_address := NULLIF(TRIM(COALESCE(new.raw_user_meta_data->>'complete_address', '')), '');
  v_owner_id := NULLIF(new.raw_user_meta_data->>'owner_id', '')::uuid;

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
    longitude,
    owner_id
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
    (new.raw_user_meta_data->>'longitude')::DOUBLE PRECISION,
    v_owner_id
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
        longitude = EXCLUDED.longitude,
        owner_id = COALESCE(EXCLUDED.owner_id, profiles.owner_id);

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

-- 4. Fix create_rider_account function to always ensure profile has owner_id and role = 'rider'
CREATE OR REPLACE FUNCTION public.create_rider_account(
    p_email text,
    p_password text,
    p_username text,
    p_full_name text,
    p_owner_id uuid
) RETURNS text
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path TO 'public', 'auth', 'extensions'
AS $$
DECLARE
    v_user_id uuid;
    v_hashed_password text;
BEGIN
    -- Ensure pgcrypto is available
    PERFORM public.ensure_pgcrypto();
    
    -- Check if user already exists
    SELECT id INTO v_user_id FROM auth.users WHERE lower(email) = lower(p_email);
    IF v_user_id IS NOT NULL THEN
        -- Link existing rider if not yet assigned to an owner
        UPDATE public.profiles
        SET owner_id = p_owner_id, role = 'rider'::user_role
        WHERE id = v_user_id;

        UPDATE auth.users
        SET raw_user_meta_data = COALESCE(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('owner_id', p_owner_id, 'role', 'rider')
        WHERE id = v_user_id;

        RETURN 'success';
    END IF;

    -- Generate UUID for new user
    v_user_id := gen_random_uuid();
    
    -- Hash password using pgcrypto
    BEGIN
        v_hashed_password := crypt(p_password, gen_salt('bf'));
    EXCEPTION
        WHEN undefined_function THEN
            v_hashed_password := extensions.crypt(p_password, extensions.gen_salt('bf'));
    END;
    
    -- Insert into auth.users
    INSERT INTO auth.users (
        instance_id,
        id,
        aud,
        role,
        email,
        encrypted_password,
        email_confirmed_at,
        raw_app_meta_data,
        raw_user_meta_data,
        created_at,
        updated_at
    )
    VALUES (
        '00000000-0000-0000-0000-000000000000',
        v_user_id,
        'authenticated',
        'authenticated',
        p_email,
        v_hashed_password,
        now(),
        '{"provider": "email", "providers": ["email"]}'::jsonb,
        jsonb_build_object('role', 'rider', 'username', p_username, 'full_name', p_full_name, 'owner_id', p_owner_id),
        now(),
        now()
    );

    -- Insert into auth.identities
    INSERT INTO auth.identities (
        provider_id, 
        user_id, 
        identity_data, 
        provider, 
        last_sign_in_at, 
        created_at, 
        updated_at, 
        id
    ) 
    VALUES (
        v_user_id::text, 
        v_user_id, 
        jsonb_build_object('sub', v_user_id::text, 'email', p_email), 
        'email', 
        now(), 
        now(), 
        now(), 
        gen_random_uuid()
    );

    -- Explicitly ensure public.profiles record exists and has owner_id set
    INSERT INTO public.profiles (
        id,
        email,
        username,
        full_name,
        role,
        owner_id
    )
    VALUES (
        v_user_id,
        p_email,
        p_username,
        p_full_name,
        'rider'::user_role,
        p_owner_id
    )
    ON CONFLICT (id) DO UPDATE
    SET role = 'rider'::user_role,
        owner_id = p_owner_id,
        full_name = p_full_name,
        username = p_username;

    RETURN 'success';
EXCEPTION
    WHEN unique_violation THEN
        RETURN 'error: user_already_exists';
    WHEN OTHERS THEN
        RETURN 'error: ' || SQLERRM;
END;
$$;

-- 5. Backfill existing riders whose owner_id is missing in public.profiles
UPDATE public.profiles p
SET owner_id = (u.raw_user_meta_data->>'owner_id')::uuid
FROM auth.users u
WHERE p.id = u.id
  AND p.role = 'rider'
  AND p.owner_id IS NULL
  AND u.raw_user_meta_data->>'owner_id' IS NOT NULL;

