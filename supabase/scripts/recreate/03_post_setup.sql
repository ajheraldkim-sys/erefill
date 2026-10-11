-- ==============================================================================
-- Step 3: Post-Schema Setup
-- 1. Create water_refill_stations table & synchronization trigger
-- 2. Configure storage buckets & storage RLS policies
-- 3. Register tables in supabase_realtime publication
-- 4. Set on_auth_user_created trigger on auth.users
-- 5. Seed default system configuration
-- 6. Create the Admin account (Admin@gmail.com / admin123)
-- ==============================================================================

-- 1. Water Refill Stations Table & Trigger
CREATE TABLE IF NOT EXISTS public.water_refill_stations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
    name text NOT NULL,
    address text,
    town text,
    barangay text,
    latitude double precision,
    longitude double precision,
    phone text,
    is_accepting_orders boolean DEFAULT true,
    status text DEFAULT 'active',
    rating numeric(3, 2) DEFAULT 5.00,
    price_per_gallon numeric(10, 2) DEFAULT 25.00,
    base_delivery_fee numeric(10, 2) DEFAULT 10.00,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    CONSTRAINT uq_water_refill_stations_owner UNIQUE (owner_id)
);

ALTER TABLE public.water_refill_stations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "water_refill_stations_select_all" ON public.water_refill_stations;
CREATE POLICY "water_refill_stations_select_all"
    ON public.water_refill_stations FOR SELECT
    TO anon, authenticated
    USING (true);

DROP POLICY IF EXISTS "water_refill_stations_owner_admin_all" ON public.water_refill_stations;
CREATE POLICY "water_refill_stations_owner_admin_all"
    ON public.water_refill_stations FOR ALL
    TO authenticated
    USING (owner_id = auth.uid() OR public.is_admin())
    WITH CHECK (owner_id = auth.uid() OR public.is_admin());

CREATE OR REPLACE FUNCTION public.sync_owner_station()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.role::text = 'owner' THEN
    INSERT INTO public.water_refill_stations (
      owner_id, name, address, town, barangay, latitude, longitude, phone,
      is_accepting_orders, status, rating, price_per_gallon, updated_at
    ) VALUES (
      NEW.id,
      COALESCE(NULLIF(trim(NEW.station_name), ''), NULLIF(trim(NEW.full_name), ''), 'Water Refilling Station'),
      COALESCE(NEW.complete_address, ''),
      NEW.town::text,
      NEW.barangay,
      NEW.latitude,
      NEW.longitude,
      NEW.phone,
      (COALESCE(NEW.station_availability, 'open') = 'open' AND COALESCE(NEW.is_open, true)),
      CASE WHEN NEW.is_suspended THEN 'suspended' ELSE 'active' END,
      COALESCE(NEW.average_rating, 5.00),
      COALESCE(NEW.price_per_gallon, 25.00),
      now()
    )
    ON CONFLICT (owner_id) DO UPDATE SET
      name = EXCLUDED.name,
      address = EXCLUDED.address,
      town = EXCLUDED.town,
      barangay = EXCLUDED.barangay,
      latitude = EXCLUDED.latitude,
      longitude = EXCLUDED.longitude,
      phone = EXCLUDED.phone,
      is_accepting_orders = EXCLUDED.is_accepting_orders,
      status = EXCLUDED.status,
      rating = EXCLUDED.rating,
      price_per_gallon = EXCLUDED.price_per_gallon,
      updated_at = now();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_owner_station ON public.profiles;
CREATE TRIGGER trg_sync_owner_station
AFTER INSERT OR UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.sync_owner_station();

-- 2. Storage Buckets
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  ('avatars', 'avatars', true, 5242880, ARRAY['image/png', 'image/jpeg', 'image/jpg', 'image/webp']::text[]),
  ('product_images', 'product_images', true, 5242880, ARRAY['image/png', 'image/jpeg', 'image/jpg', 'image/webp']::text[]),
  ('chat_attachments', 'chat_attachments', false, 10485760, NULL),
  ('delivery_proofs', 'delivery_proofs', false, 10485760, NULL),
  ('payment_proofs', 'payment_proofs', false, 10485760, NULL)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Storage Policies
DROP POLICY IF EXISTS "Public read access for avatars" ON storage.objects;
CREATE POLICY "Public read access for avatars" ON storage.objects
  FOR SELECT USING (bucket_id = 'avatars');

DROP POLICY IF EXISTS "Authenticated users can manage avatars" ON storage.objects;
CREATE POLICY "Authenticated users can manage avatars" ON storage.objects
  FOR ALL TO authenticated
  USING (bucket_id = 'avatars')
  WITH CHECK (bucket_id = 'avatars');

DROP POLICY IF EXISTS "Public can view product images" ON storage.objects;
CREATE POLICY "Public can view product images" ON storage.objects
  FOR SELECT USING (bucket_id = 'product_images');

DROP POLICY IF EXISTS "Allow owners to upload product images" ON storage.objects;
CREATE POLICY "Allow owners to upload product images" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'product_images');

DROP POLICY IF EXISTS "Allow authenticated uploads" ON storage.objects;
CREATE POLICY "Allow authenticated uploads" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'chat_attachments');

DROP POLICY IF EXISTS "Authenticated users can upload chat images" ON storage.objects;
CREATE POLICY "Authenticated users can upload chat images" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'chat_attachments');

DROP POLICY IF EXISTS "Allow users to delete own files" ON storage.objects;
CREATE POLICY "Allow users to delete own files" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'chat_attachments');

DROP POLICY IF EXISTS "Public can view delivery proofs" ON storage.objects;
CREATE POLICY "Public can view delivery proofs" ON storage.objects
  FOR SELECT USING (bucket_id = 'delivery_proofs');

DROP POLICY IF EXISTS "Riders can upload delivery proofs" ON storage.objects;
CREATE POLICY "Riders can upload delivery proofs" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'delivery_proofs');

DROP POLICY IF EXISTS "Authenticated users can upload payment proofs" ON storage.objects;
CREATE POLICY "Authenticated users can upload payment proofs" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'payment_proofs');

-- 3. Supabase Realtime Publication
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE 
    public.profiles,
    public.orders,
    public.products,
    public.order_items,
    public.reviews,
    public.system_notifications,
    public.chat_rooms,
    public.chat_participants,
    public.messages,
    public.rider_locations,
    public.owner_settings,
    public.disputes,
    public.owner_inventory_ledger,
    public.customer_addresses,
    public.payment_checkouts,
    public.payment_webhook_events,
    public.customer_payment_methods,
    public.owner_payout_accounts,
    public.favorites,
    public.water_refill_stations;
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;

-- 4. Auth User Signup Trigger
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 5. Default System Configuration
INSERT INTO public.system_config (key, value, description)
VALUES
  ('maintenance_mode', 'false'::jsonb, 'Toggle platform maintenance mode'),
  ('allow_signups', 'true'::jsonb, 'Toggle user registrations'),
  ('platform_fee', '{"percent": 5.0, "fixed": 2.0, "enabled": true}'::jsonb, 'Platform commission settings'),
  ('default_service_radius_km', '5.0'::jsonb, 'Default delivery radius for stations')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

-- 6. Create the Admin Account (Admin@gmail.com / admin123)
DO $$
DECLARE
  v_admin_id uuid := gen_random_uuid();
  v_email text := 'admin@gmail.com';
  v_password text := 'admin123';
  v_encrypted_pw text;
BEGIN
  -- Hash password with pgcrypto / bcrypt
  v_encrypted_pw := extensions.crypt(v_password, extensions.gen_salt('bf', 10));

  -- Insert auth.user
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
    is_sso_user,
    is_anonymous,
    confirmation_token,
    recovery_token,
    email_change,
    email_change_token_new,
    email_change_token_current,
    phone_change,
    phone_change_token,
    reauthentication_token,
    created_at,
    updated_at
  )
  VALUES (
    '00000000-0000-0000-0000-000000000000',
    v_admin_id,
    'authenticated',
    'authenticated',
    v_email,
    v_encrypted_pw,
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object(
      'role', 'admin',
      'full_name', 'System Administrator',
      'username', 'admin',
      'email', v_email
    ),
    false,
    false,
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    now(),
    now()
  );

  -- Insert auth.identity
  INSERT INTO auth.identities (
    id,
    user_id,
    identity_data,
    provider,
    provider_id,
    last_sign_in_at,
    created_at,
    updated_at
  )
  VALUES (
    gen_random_uuid(),
    v_admin_id,
    jsonb_build_object('sub', v_admin_id::text, 'email', v_email),
    'email',
    v_admin_id::text,
    now(),
    now(),
    now()
  );

  -- Ensure profile exists with role=admin and admin_tier=super
  INSERT INTO public.profiles (
    id,
    email,
    username,
    full_name,
    first_name,
    last_name,
    role,
    admin_tier,
    is_suspended,
    created_at,
    updated_at
  )
  VALUES (
    v_admin_id,
    v_email,
    'admin',
    'System Administrator',
    'System',
    'Administrator',
    'admin'::public.user_role,
    'super',
    false,
    now(),
    now()
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    username = EXCLUDED.username,
    full_name = EXCLUDED.full_name,
    role = 'admin'::public.user_role,
    admin_tier = 'super',
    is_suspended = false,
    updated_at = now();

END $$;
