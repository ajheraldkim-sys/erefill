-- Seed script for eRefill Cantilan/Madrid water stations.
-- Preserves admin accounts and system configuration, then populates operational
-- water refilling stations for Cantilan and Madrid municipalities.
--
-- Note: Replace demo password hashes with secure environment credentials before production use.

BEGIN;

ALTER TABLE public.owner_settings
  ADD COLUMN IF NOT EXISTS rider_commission_per_gallon DOUBLE PRECISION DEFAULT 0,
  ADD COLUMN IF NOT EXISTS service_radius_km DOUBLE PRECISION DEFAULT 5,
  ADD COLUMN IF NOT EXISTS max_concurrent_orders INTEGER DEFAULT 20,
  ADD COLUMN IF NOT EXISTS empty_gallons_stock INTEGER DEFAULT 0;

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS preparation_minutes INTEGER NOT NULL DEFAULT 15,
  ADD COLUMN IF NOT EXISTS container_size TEXT NOT NULL DEFAULT '5 gallon';

ALTER TABLE public.products
  DROP CONSTRAINT IF EXISTS products_category_check;

UPDATE public.products
SET category = CASE
  WHEN lower(COALESCE(name, '') || ' ' || COALESCE(category, '')) LIKE '%alkaline%'
    THEN 'Alkaline'
  WHEN lower(COALESCE(name, '') || ' ' || COALESCE(category, '')) LIKE '%mineral%'
    THEN 'Mineral'
  ELSE 'Purified'
END
WHERE category IS NULL
   OR category NOT IN ('Purified', 'Mineral', 'Alkaline');

ALTER TABLE public.products
  ADD CONSTRAINT products_category_check
  CHECK (category IN ('Purified', 'Mineral', 'Alkaline'));

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS first_name TEXT,
  ADD COLUMN IF NOT EXISTS last_name TEXT,
  ADD COLUMN IF NOT EXISTS barangay TEXT,
  ADD COLUMN IF NOT EXISTS station_description TEXT,
  ADD COLUMN IF NOT EXISTS bio_description TEXT,
  ADD COLUMN IF NOT EXISTS price_per_gallon NUMERIC(10, 2) DEFAULT 25.00,
  ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS station_availability TEXT NOT NULL DEFAULT 'open';

-- Clear activity data while keeping admin profiles and system config
DO $$
DECLARE
  v_tables TEXT[] := ARRAY[
    'audit_logs',
    'chat_participants',
    'chat_rooms',
    'customer_addresses',
    'disputes',
    'domain_events',
    'favorites',
    'inventory_ledger',
    'ledger_entries',
    'operational_metrics',
    'order_items',
    'orders',
    'owner_inventory_ledger',
    'owner_payout_accounts',
    'payment_checkouts',
    'payment_webhook_events',
    'products',
    'quick_replies',
    'rate_limit_events',
    'reviews',
    'rider_locations',
    'suspicious_activities',
    'system_notifications'
  ];
  v_table TEXT;
BEGIN
  FOREACH v_table IN ARRAY v_tables LOOP
    IF to_regclass('public.' || v_table) IS NOT NULL THEN
      EXECUTE format('TRUNCATE TABLE public.%I RESTART IDENTITY CASCADE', v_table);
    END IF;
  END LOOP;
END $$;

DELETE FROM public.owner_settings;
DELETE FROM public.profiles
WHERE COALESCE(role::text, '') <> 'admin';

DELETE FROM auth.identities i
USING auth.users u
WHERE i.user_id = u.id
  AND NOT EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = u.id
      AND p.role::text = 'admin'
  );

DELETE FROM auth.users u
WHERE NOT EXISTS (
  SELECT 1
  FROM public.profiles p
  WHERE p.id = u.id
    AND p.role::text = 'admin'
);

DO $$
DECLARE
  r RECORD;
  v_user_id UUID;
  v_email TEXT;
  v_slug TEXT;
  v_owner_name TEXT;
BEGIN
  FOR r IN
    SELECT *
    FROM (
      VALUES
        ('Cantilan', 'WATER Kaw! Purified Water', 'Magasang', 'Magasang Barangay Road', 9.3533, 125.9812, 'water-kaw'),
        ('Cantilan', 'Aspillaga Water Refilling', 'Poblacion', 'Purok 11', 9.3514, 125.9794, 'aspillaga-water-refilling'),
        ('Cantilan', 'PERCH Water Refilling', 'Pag-antayan', 'Pag-Antayan', 9.3491, 125.9772, 'perch-water-refilling'),
        ('Cantilan', 'L. Molejon Water Station', 'Poblacion', 'R. Azarcon Street', 9.3524, 125.9798, 'l-molejon-water-station'),
        ('Cantilan', 'Aqua Mem Purified Water', 'Poblacion', 'Dela Pena Street', 9.3516, 125.9804, 'aqua-mem-purified-water'),
        ('Cantilan', 'Aqua Blue Water Station', 'Poblacion', '665 Julve Street', 9.3541, 125.9775, 'aqua-blue-water-station'),
        ('Cantilan', 'IslandFresh Purified Water', 'Poblacion', 'Main Highway Hub', 9.3495, 125.9754, 'islandfresh-purified-water'),
        ('Cantilan', 'ATM Purified Water', 'Poblacion', 'Poblacion', 9.3468, 125.9742, 'atm-purified-water'),
        ('Cantilan', 'Cantilan Water District Office', 'Poblacion', 'Ortiz Street', 9.3511, 125.9789, 'cantilan-water-district-office'),
        ('Madrid', 'Kingsville Purified Water', 'Quirino', 'Surigao - Davao Coastal Road', 9.2721, 125.9624, 'kingsville-purified-water'),
        ('Madrid', 'Aqua Store', 'Quirino', 'Surigao - Davao Coastal Road', 9.2738, 125.9641, 'aqua-store'),
        ('Madrid', 'Madrid Water District', 'Quirino', 'Purok 4, Brgy. Quirino', 9.2792, 125.9664, 'madrid-water-district')
    ) AS seed(
      town,
      station_name,
      barangay,
      street_address,
      latitude,
      longitude,
      slug
    )
  LOOP
    v_user_id := gen_random_uuid();
    v_slug := r.slug;
    v_email := v_slug || '.owner@erefill.local';
    v_owner_name := r.station_name || ' Owner';

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
      v_email,
      extensions.crypt('Erefill@StationDemo1', extensions.gen_salt('bf')),
      now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      jsonb_build_object(
        'role', 'owner',
        'username', v_slug,
        'full_name', v_owner_name,
        'first_name', r.station_name,
        'last_name', 'Owner',
        'station_name', r.station_name,
        'town', r.town,
        'barangay', r.barangay,
        'complete_address', r.street_address || ', ' || r.barangay || ', ' || r.town,
        'primary_water_type', 'Purified Water',
        'latitude', r.latitude,
        'longitude', r.longitude
      ),
      now(),
      now()
    );

    INSERT INTO auth.identities (
      id,
      user_id,
      identity_data,
      provider,
      provider_id,
      created_at,
      updated_at
    )
    VALUES (
      gen_random_uuid(),
      v_user_id,
      jsonb_build_object('sub', v_user_id::text, 'email', v_email),
      'email',
      v_user_id::text,
      now(),
      now()
    );

    INSERT INTO public.profiles (
      id,
      email,
      username,
      full_name,
      first_name,
      last_name,
      role,
      phone,
      town,
      barangay,
      complete_address,
      station_name,
      station_description,
      bio_description,
      primary_water_type,
      price_per_gallon,
      latitude,
      longitude,
      station_availability,
      is_open,
      average_rating
    )
    VALUES (
      v_user_id,
      v_email,
      v_slug,
      v_owner_name,
      r.station_name,
      'Owner',
      'owner',
      '09' || lpad((100000000 + floor(random() * 899999999))::bigint::text, 9, '0'),
      r.town,
      r.barangay,
      r.street_address || ', ' || r.barangay || ', ' || r.town,
      r.station_name,
      'Registered water refilling station serving ' || r.barangay || ', ' || r.town || '.',
      'Registered water refilling station serving ' || r.barangay || ', ' || r.town || '.',
      'Purified Water',
      25.00,
      r.latitude,
      r.longitude,
      'open',
      true,
      5.0
    );

    INSERT INTO public.owner_settings (
      owner_id,
      price_per_gallon,
      base_delivery_fee,
      rider_commission_per_gallon,
      service_radius_km,
      max_concurrent_orders,
      empty_gallons_stock
    )
    VALUES (
      v_user_id,
      25.00,
      10.00,
      5.00,
      5.0,
      20,
      50
    );

    INSERT INTO public.products (
      owner_id,
      name,
      description,
      price,
      category,
      is_available,
      stock_level,
      preparation_minutes,
      container_size
    )
    VALUES (
      v_user_id,
      'Purified Water Refill',
      '5-gallon purified drinking water refill',
      25.00,
      'Purified',
      true,
      100,
      15,
      '5 gallon'
    );
  END LOOP;
END $$;

COMMIT;
