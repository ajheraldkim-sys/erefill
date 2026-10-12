-- Run this in Supabase Dashboard → SQL Editor when `supabase db push` fails
-- due to migration history conflicts (duplicate version keys like 20260318).
-- Safe to re-run: every change uses IF NOT EXISTS.

BEGIN;

-- Customer profile address fields
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS purok text,
  ADD COLUMN IF NOT EXISTS zip_code text,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT timezone('utc'::text, now());

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS preferred_water_type text;

COMMENT ON COLUMN public.profiles.purok IS
  'Selected purok for customer delivery address.';
COMMENT ON COLUMN public.profiles.zip_code IS
  'Postal code based on selected municipality.';
COMMENT ON COLUMN public.profiles.preferred_water_type IS
  'Customer preferred water type at registration (Purified, Mineral, Alkaline).';

-- Water refill products category check & attributes
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS preparation_minutes integer NOT NULL DEFAULT 15,
  ADD COLUMN IF NOT EXISTS container_size text NOT NULL DEFAULT '5 gallon';

ALTER TABLE public.products
  DROP CONSTRAINT IF EXISTS products_category_check;

ALTER TABLE public.products
  ADD CONSTRAINT products_category_check
  CHECK (category IN ('Purified', 'Mineral', 'Alkaline', 'Refill', 'Products', 'Accessories'));

-- Owner empty-gallon inventory (20260601)
ALTER TABLE public.owner_settings
  ADD COLUMN IF NOT EXISTS empty_gallons_stock integer NOT NULL DEFAULT 0;

ALTER TABLE public.owner_settings DROP CONSTRAINT IF EXISTS empty_gallons_stock_non_negative;
ALTER TABLE public.owner_settings
  ADD CONSTRAINT empty_gallons_stock_non_negative CHECK (empty_gallons_stock >= 0);

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS empty_gallons_returned integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS customer_latitude double precision,
  ADD COLUMN IF NOT EXISTS customer_longitude double precision;

ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS empty_gallons_returned_non_negative;
ALTER TABLE public.orders
  ADD CONSTRAINT empty_gallons_returned_non_negative CHECK (empty_gallons_returned >= 0);

CREATE TABLE IF NOT EXISTS public.owner_inventory_ledger (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    tx_type text NOT NULL CHECK (
        tx_type IN (
            'load_filled',
            'adjust_filled',
            'load_empty',
            'adjust_empty',
            'empty_return'
        )
    ),
    gallons integer NOT NULL CHECK (gallons <> 0),
    product_id uuid REFERENCES public.products(id) ON DELETE SET NULL,
    order_id uuid REFERENCES public.orders(id) ON DELETE SET NULL,
    notes text,
    actor_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_owner_inventory_ledger_owner_created
    ON public.owner_inventory_ledger (owner_id, created_at DESC);

ALTER TABLE public.owner_inventory_ledger ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Owners view own inventory ledger" ON public.owner_inventory_ledger;
CREATE POLICY "Owners view own inventory ledger"
ON public.owner_inventory_ledger FOR SELECT TO authenticated
USING (auth.uid() = owner_id);

ALTER TABLE public.owner_inventory_ledger REPLICA IDENTITY FULL;

-- Inventory RPC (copy from 20260601 migration — idempotent replace)
CREATE OR REPLACE FUNCTION public.log_owner_inventory_tx(
    p_tx_type text,
    p_gallons integer,
    p_notes text DEFAULT NULL,
    p_product_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_owner_id uuid := auth.uid();
    v_product record;
    v_new_stock integer;
    v_empty_stock integer;
BEGIN
    IF v_owner_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'Authentication required.');
    END IF;

    IF p_gallons = 0 THEN
        RETURN jsonb_build_object('success', false, 'message', 'Gallon amount must not be zero.');
    END IF;

    IF p_tx_type IN ('load_filled', 'adjust_filled') THEN
        IF p_product_id IS NULL THEN
            RETURN jsonb_build_object('success', false, 'message', 'Product is required for filled-gallon updates.');
        END IF;

        SELECT * INTO v_product
        FROM public.products
        WHERE id = p_product_id AND owner_id = v_owner_id
        FOR UPDATE;

        IF NOT FOUND THEN
            RETURN jsonb_build_object('success', false, 'message', 'Product not found for this station.');
        END IF;

        IF p_tx_type = 'load_filled' AND p_gallons < 0 THEN
            RETURN jsonb_build_object('success', false, 'message', 'Load amount must be positive.');
        END IF;

        v_new_stock := coalesce(v_product.stock_level, 0) + p_gallons;

        IF v_new_stock < 0 THEN
            RETURN jsonb_build_object('success', false, 'message', 'Filled stock cannot go below zero.');
        END IF;

        UPDATE public.products SET stock_level = v_new_stock WHERE id = p_product_id;

        INSERT INTO public.owner_inventory_ledger (
            owner_id, tx_type, gallons, product_id, notes, actor_id
        ) VALUES (
            v_owner_id, p_tx_type, p_gallons, p_product_id,
            nullif(trim(p_notes), ''), v_owner_id
        );
    ELSIF p_tx_type IN ('load_empty', 'adjust_empty') THEN
        IF p_tx_type = 'load_empty' AND p_gallons < 0 THEN
            RETURN jsonb_build_object('success', false, 'message', 'Load amount must be positive.');
        END IF;

        INSERT INTO public.owner_settings (owner_id, empty_gallons_stock)
        VALUES (v_owner_id, 0)
        ON CONFLICT (owner_id) DO NOTHING;

        SELECT empty_gallons_stock INTO v_empty_stock
        FROM public.owner_settings
        WHERE owner_id = v_owner_id
        FOR UPDATE;

        IF coalesce(v_empty_stock, 0) + p_gallons < 0 THEN
            RETURN jsonb_build_object(
                'success', false,
                'message', 'Empty gallon stock cannot go below zero.'
            );
        END IF;

        UPDATE public.owner_settings
        SET empty_gallons_stock = empty_gallons_stock + p_gallons,
            updated_at = now()
        WHERE owner_id = v_owner_id;

        INSERT INTO public.owner_inventory_ledger (
            owner_id, tx_type, gallons, notes, actor_id
        ) VALUES (
            v_owner_id, p_tx_type, p_gallons,
            nullif(trim(p_notes), ''), v_owner_id
        );
    ELSE
        RETURN jsonb_build_object('success', false, 'message', 'Unsupported inventory transaction type.');
    END IF;

    RETURN jsonb_build_object('success', true, 'message', 'Inventory updated.');
END;
$$;

GRANT EXECUTE ON FUNCTION public.log_owner_inventory_tx(text, integer, text, uuid) TO authenticated;

-- Station availability column (20260528)
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS station_availability text NOT NULL DEFAULT 'open';

UPDATE public.profiles
SET station_availability = CASE
  WHEN coalesce(is_open, true) THEN 'open'
  ELSE 'closed'
END
WHERE role::text = 'owner';

-- Customer saved addresses (20260529)
CREATE TABLE IF NOT EXISTS public.customer_addresses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  label text NOT NULL DEFAULT 'Home',
  complete_address text NOT NULL,
  barangay text,
  town text,
  landmark text,
  latitude double precision NOT NULL,
  longitude double precision NOT NULL,
  is_default boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS customer_addresses_customer_idx
  ON public.customer_addresses (customer_id, is_default DESC, created_at DESC);

ALTER TABLE public.customer_addresses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Customers manage own addresses" ON public.customer_addresses;
CREATE POLICY "Customers manage own addresses"
ON public.customer_addresses
FOR ALL TO authenticated
USING (customer_id = auth.uid())
WITH CHECK (customer_id = auth.uid());

-- Payment methods RPC (20260527) — per-station methods, enabled by default
ALTER TABLE public.owner_settings
  ADD COLUMN IF NOT EXISTS enabled_payment_methods text[] NOT NULL
  DEFAULT ARRAY['cod', 'gcash', 'maya', 'card']::text[];

CREATE OR REPLACE FUNCTION public.get_station_available_payment_methods(
  p_owner_id uuid
)
RETURNS TABLE (
  type text,
  label text,
  available boolean,
  reason text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    method.type,
    method.label,
    method.type = ANY(COALESCE(settings.enabled_payment_methods,
      ARRAY['cod', 'gcash', 'maya', 'card']::text[])) AS available,
    CASE WHEN method.type = ANY(COALESCE(settings.enabled_payment_methods,
      ARRAY['cod', 'gcash', 'maya', 'card']::text[]))
      THEN NULL ELSE 'This station has disabled this payment method.' END AS reason
  FROM (
    VALUES
      ('cod'::text, 'Cash on Delivery'::text),
      ('gcash'::text, 'GCash'::text),
      ('maya'::text, 'Maya'::text),
      ('card'::text, 'Credit/Debit Card'::text)
  ) AS method(type, label)
  LEFT JOIN public.owner_settings settings ON settings.owner_id = p_owner_id
  WHERE EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = p_owner_id AND role = 'owner'
  );
$$;

REVOKE ALL ON FUNCTION public.get_station_available_payment_methods(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_station_available_payment_methods(uuid)
  TO authenticated;

-- Verify payment method availability for checkout sessions
CREATE OR REPLACE FUNCTION public.is_station_payment_method_available(
  p_owner_id uuid,
  p_payment_method text
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles owner_profile
    LEFT JOIN public.owner_settings settings
      ON settings.owner_id = owner_profile.id
    WHERE owner_profile.id = p_owner_id
      AND owner_profile.role = 'owner'
      AND COALESCE(settings.enabled_payment_methods,
        ARRAY['cod', 'gcash', 'maya', 'card']::text[])
        @> ARRAY[
          CASE lower(trim(p_payment_method))
            WHEN 'cash' THEN 'cod'
            WHEN 'paymaya' THEN 'maya'
            ELSE lower(trim(p_payment_method))
          END
        ]::text[]
  );
$$;

REVOKE ALL ON FUNCTION public.is_station_payment_method_available(uuid, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_station_payment_method_available(uuid, text)
  TO authenticated, service_role;

-- Ensure payment fields on orders
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS payment_checkout_id text,
  ADD COLUMN IF NOT EXISTS payment_checkout_url text,
  ADD COLUMN IF NOT EXISTS payment_error text;

-- Payment checkouts tracking table
CREATE TABLE IF NOT EXISTS public.payment_checkouts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  customer_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  provider text NOT NULL DEFAULT 'paymongo',
  payment_method text NOT NULL,
  provider_checkout_id text NOT NULL,
  checkout_url text NOT NULL,
  amount numeric(10,2) NOT NULL,
  currency text NOT NULL DEFAULT 'PHP',
  status text NOT NULL DEFAULT 'pending',
  raw_response jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_payment_checkouts_provider_id
  ON public.payment_checkouts (provider_checkout_id);
CREATE INDEX IF NOT EXISTS idx_payment_checkouts_order_id
  ON public.payment_checkouts (order_id);

ALTER TABLE public.payment_checkouts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Customers and owners can read payment checkouts" ON public.payment_checkouts;
CREATE POLICY "Customers and owners can read payment checkouts"
  ON public.payment_checkouts
  FOR SELECT TO authenticated
  USING (customer_id = auth.uid() OR owner_id = auth.uid());

DROP POLICY IF EXISTS "Service role manages checkouts" ON public.payment_checkouts;
CREATE POLICY "Service role manages checkouts"
  ON public.payment_checkouts
  FOR ALL TO service_role
  USING (true)
  WITH CHECK (true);

CREATE OR REPLACE FUNCTION public.record_payment_checkout(
  p_order_id uuid,
  p_customer_id uuid,
  p_owner_id uuid,
  p_payment_method text,
  p_provider_checkout_id text,
  p_checkout_url text,
  p_amount numeric,
  p_status text,
  p_raw_response jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'Only the payment service can record checkout sessions.';
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND
    OR v_order.customer_id IS DISTINCT FROM p_customer_id
    OR v_order.owner_id IS DISTINCT FROM p_owner_id
    OR lower(v_order.payment_method) IS DISTINCT FROM lower(p_payment_method)
    OR v_order.total_amount IS DISTINCT FROM p_amount
    OR v_order.payment_status = 'success'
    OR v_order.status IN ('cancelled', 'delivered')
  THEN
    RAISE EXCEPTION 'Order is not eligible for this checkout session.';
  END IF;

  IF v_order.payment_status = 'processing'
    AND EXISTS (
      SELECT 1
      FROM public.payment_checkouts checkout
      WHERE checkout.order_id = p_order_id
        AND lower(checkout.status) NOT IN (
          'failed', 'expired', 'cancelled', 'canceled', 'paid', 'succeeded', 'completed'
        )
    )
  THEN
    RAISE EXCEPTION 'An active checkout session already exists for this order.';
  END IF;

  INSERT INTO public.payment_checkouts (
    order_id, customer_id, owner_id, provider, payment_method,
    provider_checkout_id, checkout_url, amount, currency, status, raw_response
  ) VALUES (
    p_order_id, p_customer_id, p_owner_id, 'paymongo', p_payment_method,
    p_provider_checkout_id, p_checkout_url, p_amount, 'PHP', p_status,
    p_raw_response
  );

  UPDATE public.orders
  SET payment_checkout_id = p_provider_checkout_id,
      payment_checkout_url = p_checkout_url,
      payment_status = 'processing',
      payment_error = NULL,
      updated_at = now()
  WHERE id = p_order_id;
END;
$$;

REVOKE ALL ON FUNCTION public.record_payment_checkout(
  uuid, uuid, uuid, text, text, text, numeric, text, jsonb
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_payment_checkout(
  uuid, uuid, uuid, text, text, text, numeric, text, jsonb
) TO service_role;

-- Payment webhook events audit log
CREATE TABLE IF NOT EXISTS public.payment_webhook_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  checkout_id uuid REFERENCES public.payment_checkouts(id) ON DELETE SET NULL,
  provider_event_id text,
  order_id uuid REFERENCES public.orders(id) ON DELETE CASCADE,
  customer_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  owner_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  provider_checkout_id text,
  event_type text NOT NULL,
  provider_status text NOT NULL,
  processing_status text NOT NULL DEFAULT 'received',
  processing_error text,
  raw_payload jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz
);

-- CREATE TABLE IF NOT EXISTS does not add columns to an existing table.
-- Older webhook-event tables may not yet have this column.
ALTER TABLE public.payment_webhook_events
  ADD COLUMN IF NOT EXISTS provider_event_id text;

CREATE INDEX IF NOT EXISTS idx_payment_webhook_events_provider_event
  ON public.payment_webhook_events (provider_event_id);
CREATE INDEX IF NOT EXISTS idx_payment_webhook_events_order
  ON public.payment_webhook_events (order_id);

ALTER TABLE public.payment_webhook_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins and service role read webhook events" ON public.payment_webhook_events;
CREATE POLICY "Admins and service role read webhook events"
  ON public.payment_webhook_events
  FOR ALL TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
  );

-- System notifications table for in-app alert tracking and real-time delivery
CREATE TABLE IF NOT EXISTS public.system_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  type text NOT NULL DEFAULT 'system_alert',
  priority text NOT NULL DEFAULT 'normal',
  title text NOT NULL,
  content text NOT NULL,
  metadata jsonb DEFAULT '{}'::jsonb,
  is_read boolean NOT NULL DEFAULT false,
  read_at timestamptz,
  action_url text,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_system_notifications_user_id
  ON public.system_notifications (user_id, created_at DESC);

ALTER TABLE public.system_notifications ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'system_notifications' AND policyname = 'system_notifications_user_select'
  ) THEN
    CREATE POLICY "system_notifications_user_select"
      ON public.system_notifications FOR SELECT
      TO authenticated
      USING (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'system_notifications' AND policyname = 'system_notifications_user_update'
  ) THEN
    CREATE POLICY "system_notifications_user_update"
      ON public.system_notifications FOR UPDATE
      TO authenticated
      USING (user_id = auth.uid())
      WITH CHECK (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'system_notifications' AND policyname = 'system_notifications_auth_insert'
  ) THEN
    CREATE POLICY "system_notifications_auth_insert"
      ON public.system_notifications FOR INSERT
      TO authenticated
      WITH CHECK (true);
  END IF;
END $$;

-- Customer saved payment methods
CREATE TABLE IF NOT EXISTS public.customer_payment_methods (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  type text NOT NULL,
  label text NOT NULL,
  masked_value text NOT NULL,
  gateway_payment_method_id text,
  card_brand text,
  card_last4 text,
  status text NOT NULL DEFAULT 'active',
  is_default boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.customer_payment_methods ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Customers manage their payment methods" ON public.customer_payment_methods;
CREATE POLICY "Customers manage their payment methods"
  ON public.customer_payment_methods
  FOR ALL TO authenticated
  USING (customer_id = auth.uid())
  WITH CHECK (customer_id = auth.uid());

-- Owner payout accounts
CREATE TABLE IF NOT EXISTS public.owner_payout_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  type text NOT NULL,
  label text NOT NULL,
  masked_value text NOT NULL,
  encrypted_account_ref text,
  provider_name text,
  status text NOT NULL DEFAULT 'active',
  is_default boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.owner_payout_accounts
  ADD COLUMN IF NOT EXISTS label text,
  ADD COLUMN IF NOT EXISTS masked_value text;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'owner_payout_accounts'
      AND column_name = 'account_name'
  ) THEN
    EXECUTE format(
      'UPDATE public.owner_payout_accounts SET label = COALESCE(NULLIF(label, %L), %I) WHERE label IS NULL OR label = %L',
      '', 'account_name', ''
    );
    EXECUTE
      'ALTER TABLE public.owner_payout_accounts ALTER COLUMN account_name DROP NOT NULL';
  END IF;
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'owner_payout_accounts'
      AND column_name = 'masked_account'
  ) THEN
    EXECUTE format(
      'UPDATE public.owner_payout_accounts SET masked_value = COALESCE(NULLIF(masked_value, %L), %I) WHERE masked_value IS NULL OR masked_value = %L',
      '', 'masked_account', ''
    );
    EXECUTE
      'ALTER TABLE public.owner_payout_accounts ALTER COLUMN masked_account DROP NOT NULL';
  END IF;
END;
$$;

UPDATE public.owner_payout_accounts
SET label = COALESCE(NULLIF(label, ''), type),
    masked_value = COALESCE(NULLIF(masked_value, ''), 'Unavailable')
WHERE label IS NULL OR label = '' OR masked_value IS NULL OR masked_value = '';

ALTER TABLE public.owner_payout_accounts
  ALTER COLUMN label SET NOT NULL,
  ALTER COLUMN masked_value SET NOT NULL;

WITH ranked_defaults AS (
  SELECT id, row_number() OVER (
    PARTITION BY customer_id ORDER BY created_at, id
  ) AS position
  FROM public.customer_payment_methods
  WHERE is_default
)
UPDATE public.customer_payment_methods accounts
SET is_default = false
FROM ranked_defaults
WHERE accounts.id = ranked_defaults.id
  AND ranked_defaults.position > 1;

WITH ranked_defaults AS (
  SELECT id, row_number() OVER (
    PARTITION BY owner_id ORDER BY created_at, id
  ) AS position
  FROM public.owner_payout_accounts
  WHERE is_default
)
UPDATE public.owner_payout_accounts accounts
SET is_default = false
FROM ranked_defaults
WHERE accounts.id = ranked_defaults.id
  AND ranked_defaults.position > 1;

CREATE UNIQUE INDEX IF NOT EXISTS idx_customer_payment_methods_one_default
  ON public.customer_payment_methods (customer_id)
  WHERE is_default;
CREATE UNIQUE INDEX IF NOT EXISTS idx_owner_payout_accounts_one_default
  ON public.owner_payout_accounts (owner_id)
  WHERE is_default;

CREATE OR REPLACE FUNCTION public.set_payment_account_default(
  p_user_id uuid,
  p_account_id uuid,
  p_scope text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'Only the payment service can update default accounts.';
  END IF;

  SELECT role INTO v_role
  FROM public.profiles
  WHERE id = p_user_id
  FOR UPDATE;

  IF (p_scope = 'customer_payment_methods' AND v_role IS DISTINCT FROM 'customer')
    OR (p_scope = 'owner_payout_accounts' AND v_role IS DISTINCT FROM 'owner')
    OR p_scope NOT IN ('customer_payment_methods', 'owner_payout_accounts')
  THEN
    RAISE EXCEPTION 'Invalid payment account scope.';
  END IF;

  IF p_scope = 'customer_payment_methods' THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.customer_payment_methods
      WHERE id = p_account_id AND customer_id = p_user_id
    ) THEN
      RAISE EXCEPTION 'Payment account not found.';
    END IF;
    UPDATE public.customer_payment_methods
    SET is_default = false
    WHERE customer_id = p_user_id AND is_default;
    UPDATE public.customer_payment_methods
    SET is_default = true, updated_at = now()
    WHERE id = p_account_id AND customer_id = p_user_id;
  ELSE
    IF NOT EXISTS (
      SELECT 1 FROM public.owner_payout_accounts
      WHERE id = p_account_id AND owner_id = p_user_id
    ) THEN
      RAISE EXCEPTION 'Payout account not found.';
    END IF;
    UPDATE public.owner_payout_accounts
    SET is_default = false
    WHERE owner_id = p_user_id AND is_default;
    UPDATE public.owner_payout_accounts
    SET is_default = true, updated_at = now()
    WHERE id = p_account_id AND owner_id = p_user_id;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.set_payment_account_default(uuid, uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_payment_account_default(uuid, uuid, text)
  TO service_role;

ALTER TABLE public.owner_payout_accounts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Owners manage their payout accounts" ON public.owner_payout_accounts;
CREATE POLICY "Owners manage their payout accounts"
  ON public.owner_payout_accounts
  FOR ALL TO authenticated
  USING (owner_id = auth.uid())
  WITH CHECK (owner_id = auth.uid());

-- Water refill product metadata (20260528_01)
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS preparation_minutes integer NOT NULL DEFAULT 15,
  ADD COLUMN IF NOT EXISTS container_size text NOT NULL DEFAULT '5 gallon';

-- Ordering & pricing hardening (20260604)
DROP POLICY IF EXISTS "Authenticated users can read station pricing" ON public.owner_settings;
CREATE POLICY "Authenticated users can read station pricing"
ON public.owner_settings FOR SELECT TO authenticated USING (true);

CREATE OR REPLACE FUNCTION public.sync_owner_default_product(p_owner_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_price numeric(10,2); v_water_type text; v_category text; v_name text;
  v_product_id uuid; v_row public.products%ROWTYPE;
BEGIN
  IF p_owner_id IS NULL OR auth.uid() IS NULL THEN RETURN NULL; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_owner_id AND role = 'owner') THEN RETURN NULL; END IF;
  IF auth.role() <> 'service_role'
    AND auth.uid() <> p_owner_id
    AND NOT EXISTS (
      SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'
    )
  THEN
    RAISE EXCEPTION 'You cannot synchronize another station''s product.';
  END IF;
  SELECT price_per_gallon INTO v_price FROM public.owner_settings WHERE owner_id = p_owner_id;
  IF v_price IS NULL OR v_price <= 0 THEN RETURN NULL; END IF;
  SELECT primary_water_type INTO v_water_type FROM public.profiles WHERE id = p_owner_id;
  v_water_type := COALESCE(NULLIF(trim(v_water_type), ''), 'Purified Water');
  IF lower(v_water_type) LIKE '%alkaline%' THEN v_category := 'Alkaline'; v_name := 'Alkaline Water';
  ELSIF lower(v_water_type) LIKE '%mineral%' THEN v_category := 'Mineral'; v_name := 'Mineral Water';
  ELSE v_category := 'Purified'; v_name := 'Purified Water'; END IF;
  SELECT id INTO v_product_id FROM public.products WHERE owner_id = p_owner_id
    ORDER BY is_available DESC, created_at ASC NULLS LAST LIMIT 1 FOR UPDATE;
  IF v_product_id IS NOT NULL THEN
    UPDATE public.products SET price = v_price, name = v_name, category = v_category, is_available = true
    WHERE id = v_product_id RETURNING * INTO v_row;
    RETURN to_jsonb(v_row);
  END IF;
  INSERT INTO public.products (owner_id, name, description, price, category, is_available)
  VALUES (p_owner_id, v_name, v_name || ' refill service', v_price, v_category, true)
  RETURNING * INTO v_row;
  RETURN to_jsonb(v_row);
END; $$;

CREATE OR REPLACE FUNCTION public.trigger_sync_owner_default_product()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.price_per_gallon IS NOT NULL AND NEW.price_per_gallon > 0 THEN
    PERFORM public.sync_owner_default_product(NEW.owner_id);
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_sync_owner_default_product ON public.owner_settings;
CREATE TRIGGER trg_sync_owner_default_product
AFTER INSERT OR UPDATE OF price_per_gallon ON public.owner_settings
FOR EACH ROW EXECUTE FUNCTION public.trigger_sync_owner_default_product();

DO $$ DECLARE v_owner_id uuid; BEGIN
  FOR v_owner_id IN
    SELECT p.id FROM public.profiles p
    JOIN public.owner_settings s ON s.owner_id = p.id
    WHERE p.role = 'owner' AND COALESCE(s.price_per_gallon, 0) > 0
  LOOP
    PERFORM public.sync_owner_default_product(v_owner_id);
  END LOOP;
END; $$;

-- ── Performance Optimization: High-traffic composite indexes ──
CREATE INDEX IF NOT EXISTS idx_orders_owner_status_created 
  ON public.orders (owner_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_orders_rider_status_created 
  ON public.orders (assigned_rider_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_messages_room_created 
  ON public.messages (room_id, created_at ASC);

-- ── Security Guard: Prevent unauthorized role escalation & suspension modification ──
DROP POLICY IF EXISTS "profiles_users_update_own" ON public.profiles;
CREATE POLICY "profiles_users_update_own"
  ON public.profiles
  FOR UPDATE TO authenticated
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

CREATE OR REPLACE FUNCTION public.guard_profile_role_changes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF (NEW.role IS DISTINCT FROM OLD.role)
    OR (NEW.is_suspended IS DISTINCT FROM OLD.is_suspended)
    OR (NEW.owner_id IS DISTINCT FROM OLD.owner_id)
  THEN
    -- Only service_role or a verified admin can change privileged account fields.
    IF auth.role() IS DISTINCT FROM 'service_role' AND NOT EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE id = auth.uid() AND role = 'admin'
    ) THEN
      RAISE EXCEPTION 'Unauthorized: You cannot alter protected account fields.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_profile_role_changes ON public.profiles;
CREATE TRIGGER trg_guard_profile_role_changes
BEFORE UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.guard_profile_role_changes();

-- ── Security Guard: Prevent regular authenticated users from forging system messages ──
CREATE OR REPLACE FUNCTION public.guard_system_message_spoofing()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF (NEW.sender_id IS NULL OR NEW.message_type = 'system') THEN
    IF auth.role() IS DISTINCT FROM 'service_role' AND NOT EXISTS (
      SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'
    ) THEN
      RAISE EXCEPTION 'Unauthorized: Only system service or administrator can issue system messages.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_system_message_spoofing ON public.messages;
CREATE TRIGGER trg_guard_system_message_spoofing
BEFORE INSERT ON public.messages
FOR EACH ROW EXECUTE FUNCTION public.guard_system_message_spoofing();

-- ── Chat Message Notification Trigger ──
-- Automatically notifies all other chat room participants via system_notifications table
CREATE OR REPLACE FUNCTION public.notify_chat_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sender_name text;
  v_part record;
  v_body text;
BEGIN
  -- Do not notify on deleted or blank messages
  IF NEW.deleted_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  -- Resolve sender name
  IF NEW.sender_id IS NOT NULL THEN
    SELECT coalesce(nullif(trim(full_name), ''), nullif(trim(username), ''), 'Someone')
    INTO v_sender_name
    FROM public.profiles
    WHERE id = NEW.sender_id;
    IF v_sender_name IS NULL THEN
      v_sender_name := 'New Message';
    END IF;
  ELSE
    v_sender_name := 'eRefill System';
  END IF;

  -- Preview content based on type
  IF NEW.message_type = 'image' THEN
    v_body := '📷 Photo message';
  ELSIF NEW.message_type = 'quick_reply' THEN
    v_body := coalesce(NEW.content, 'Quick response');
  ELSE
    v_body := coalesce(NEW.content, 'New message');
  END IF;

  -- Insert push notification for each other participant in this chat room
  FOR v_part IN
    SELECT user_id FROM public.chat_participants
    WHERE room_id = NEW.room_id
      AND user_id IS NOT NULL
      AND user_id <> coalesce(NEW.sender_id, '00000000-0000-0000-0000-000000000000'::uuid)
  LOOP
    INSERT INTO public.system_notifications (
      user_id,
      type,
      priority,
      title,
      content,
      action_url,
      metadata
    ) VALUES (
      v_part.user_id,
      'new_message',
      'high',
      v_sender_name,
      v_body,
      '/chat?roomId=' || NEW.room_id::text,
      jsonb_build_object(
        'room_id', NEW.room_id,
        'sender_id', NEW.sender_id,
        'sender_name', v_sender_name
      )
    );
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_chat_message ON public.messages;
CREATE TRIGGER trg_notify_chat_message
AFTER INSERT ON public.messages
FOR EACH ROW
EXECUTE FUNCTION public.notify_chat_message();

-- ── Order Creation: Atomic order insertion with server-verified line item pricing ──
CREATE OR REPLACE FUNCTION public.create_order_atomic(
  p_order_data jsonb,
  p_items_data jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
    p_order_data->>'idempotency_key',
    v_computed_subtotal,
    v_delivery_fee,
    v_total_amount,
    v_payment_method,
    'pending',
    p_order_data->>'notes',
    (p_order_data->>'region_id')::uuid,
    (p_order_data->>'customer_latitude')::double precision,
    (p_order_data->>'customer_longitude')::double precision,
    'pending'
  )
  RETURNING * INTO v_order_row;

  v_order_id := v_order_row.id;

  -- 6. Insert order items
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
      price,
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
$$;

GRANT EXECUTE ON FUNCTION public.create_order_atomic(jsonb, jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.create_order_atomic(jsonb, jsonb) FROM PUBLIC, anon;

-- Transition order status safely and notify customer/owner
CREATE OR REPLACE FUNCTION public.transition_order_status_safely(
  p_order_id uuid,
  p_new_status text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_role text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'Order not found');
  END IF;

  SELECT role INTO v_role FROM public.profiles WHERE id = auth.uid();

  IF v_role = 'owner' AND auth.uid() = v_order.owner_id THEN
    IF NOT (
      (v_order.status = 'pending' AND p_new_status IN ('accepted', 'cancelled'))
      OR (v_order.status = 'accepted' AND p_new_status IN ('preparing', 'cancelled'))
      OR (v_order.status = 'preparing' AND p_new_status IN ('ready_for_pickup', 'cancelled'))
    ) THEN
      RAISE EXCEPTION 'Invalid station order status transition.';
    END IF;
  ELSIF v_role = 'rider'
      AND auth.uid() = v_order.assigned_rider_id
      AND v_order.status = 'assigned_to_rider'
      AND p_new_status = 'out_for_delivery' THEN
    NULL;
  ELSIF v_role = 'customer'
      AND auth.uid() = v_order.customer_id
      AND v_order.status = 'pending'
      AND p_new_status = 'cancelled' THEN
    NULL;
  ELSE
    RAISE EXCEPTION 'You are not authorized to make this order status change.';
  END IF;

  UPDATE public.orders
  SET
    status = p_new_status,
    updated_at = now()
  WHERE id = p_order_id;

  -- Lifecycle status notifications for customer
  IF p_new_status = 'accepted' THEN
    INSERT INTO public.system_notifications (
      user_id, type, priority, title, content, metadata
    ) VALUES (
      v_order.customer_id, 'system_alert', 'high', 'Order Accepted',
      'The water station accepted your refill order and is preparing to refill.',
      jsonb_build_object('order_id', p_order_id, 'status', 'accepted')
    );
  ELSIF p_new_status = 'preparing' THEN
    INSERT INTO public.system_notifications (
      user_id, type, priority, title, content, metadata
    ) VALUES (
      v_order.customer_id, 'system_alert', 'normal', 'Refill in Preparation',
      'Your water containers are now being refilled and inspected.',
      jsonb_build_object('order_id', p_order_id, 'status', 'preparing')
    );
  ELSIF p_new_status = 'ready_for_pickup' THEN
    INSERT INTO public.system_notifications (
      user_id, type, priority, title, content, metadata
    ) VALUES (
      v_order.customer_id, 'system_alert', 'normal', 'Refill Ready for Dispatch',
      'Your containers are refilled and ready for rider pickup.',
      jsonb_build_object('order_id', p_order_id, 'status', 'ready_for_pickup')
    );
  ELSIF p_new_status = 'out_for_delivery' THEN
    INSERT INTO public.system_notifications (
      user_id, type, priority, title, content, metadata
    ) VALUES (
      v_order.customer_id, 'system_alert', 'high', 'Out for Delivery',
      'Your rider picked up your refill and is heading to your address.',
      jsonb_build_object('order_id', p_order_id, 'status', 'out_for_delivery')
    );
  ELSIF p_new_status = 'delivered' THEN
    INSERT INTO public.system_notifications (
      user_id, type, priority, title, content, metadata
    ) VALUES (
      v_order.customer_id, 'system_alert', 'high', 'Refill Delivered',
      'Your water refill delivery has been completed. Thank you!',
      jsonb_build_object('order_id', p_order_id, 'status', 'delivered')
    );
  ELSIF p_new_status = 'cancelled' THEN
    IF auth.uid() = v_order.owner_id THEN
      INSERT INTO public.system_notifications (
        user_id, type, priority, title, content, metadata
      ) VALUES (
        v_order.customer_id, 'order_cancelled', 'urgent', 'Order Cancelled',
        'Your refill order #' || upper(substr(p_order_id::text, 1, 8)) || ' was cancelled by the station.',
        jsonb_build_object('order_id', p_order_id, 'status', 'cancelled')
      );
    ELSE
      INSERT INTO public.system_notifications (
        user_id, type, priority, title, content, metadata
      ) VALUES (
        v_order.owner_id, 'order_cancelled', 'high', 'Order Cancelled by Customer',
        coalesce(v_order.customer_name, 'Customer') || ' cancelled refill order #' || upper(substr(p_order_id::text, 1, 8)) || '.',
        jsonb_build_object('order_id', p_order_id, 'status', 'cancelled')
      );
    END IF;
  END IF;

  RETURN jsonb_build_object('success', true, 'message', 'Order status updated successfully');
END;
$$;

GRANT EXECUTE ON FUNCTION public.transition_order_status_safely(uuid, text) TO authenticated;
REVOKE ALL ON FUNCTION public.transition_order_status_safely(uuid, text) FROM PUBLIC, anon;

-- Safely assigns rider to refill order and notifies both rider and customer
CREATE OR REPLACE FUNCTION public.assign_rider_safely(
  p_order_id uuid,
  p_rider_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_rider public.profiles%ROWTYPE;
  v_rider_name text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order no longer exists.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'owner'
  ) OR auth.uid() <> v_order.owner_id THEN
    RAISE EXCEPTION 'Only this station owner can assign its order.';
  END IF;

  IF v_order.assigned_rider_id IS NOT NULL THEN
    RAISE EXCEPTION 'Order is already assigned to a rider.';
  END IF;

  IF v_order.status <> 'ready_for_pickup' THEN
    RAISE EXCEPTION 'Order status is %, not ready_for_pickup.', v_order.status;
  END IF;

  SELECT * INTO v_rider
  FROM public.profiles
  WHERE id = p_rider_id
    AND role = 'rider'
    AND owner_id = v_order.owner_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Selected rider is not assigned to this station.';
  END IF;

  v_rider_name := coalesce(v_rider.full_name, v_rider.username, 'Rider');

  UPDATE public.orders
  SET
    assigned_rider_id = p_rider_id,
    status = 'assigned_to_rider',
    updated_at = now()
  WHERE id = p_order_id;

  -- Notify Rider
  INSERT INTO public.system_notifications (
    user_id,
    type,
    priority,
    title,
    content,
    metadata
  ) VALUES (
    p_rider_id,
    'order_assigned',
    'urgent',
    'New Delivery Assignment',
    'You have been assigned order #' || upper(substr(p_order_id::text, 1, 8)) || ' for ' || coalesce(v_order.customer_name, 'a customer') || '.',
    jsonb_build_object('order_id', p_order_id, 'status', 'assigned_to_rider')
  );

  -- Notify Customer
  INSERT INTO public.system_notifications (
    user_id,
    type,
    priority,
    title,
    content,
    metadata
  ) VALUES (
    v_order.customer_id,
    'order_assigned',
    'high',
    'Rider Assigned to Refill',
    v_rider_name || ' has been assigned to deliver your water refill.',
    jsonb_build_object('order_id', p_order_id, 'rider_id', p_rider_id, 'rider_name', v_rider_name)
  );

  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.assign_rider_safely(uuid, uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.assign_rider_safely(uuid, uuid) FROM PUBLIC, anon;

-- Safely confirms delivery with proof metadata, empty gallon return tracking, and COD payment resolution
CREATE OR REPLACE FUNCTION public.confirm_delivery_safely(
  p_order_id uuid,
  p_lat double precision DEFAULT NULL,
  p_lng double precision DEFAULT NULL,
  p_photo_url text DEFAULT NULL,
  p_signature_url text DEFAULT NULL,
  p_delivery_note text DEFAULT NULL,
  p_empty_gallons_returned integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'Order not found');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'rider'
  ) OR auth.uid() <> v_order.assigned_rider_id THEN
    RAISE EXCEPTION 'Only the assigned rider can confirm this delivery.';
  END IF;

  IF v_order.status = 'delivered' THEN
    RETURN jsonb_build_object('success', true, 'message', 'Order is already delivered');
  END IF;

  IF v_order.status <> 'out_for_delivery' THEN
    RAISE EXCEPTION 'Only an order out for delivery can be completed.';
  END IF;

  UPDATE public.orders
  SET
    status = 'delivered',
    delivered_at = coalesce(delivered_at, now()),
    proof_of_delivery_url = coalesce(p_photo_url, proof_of_delivery_url),
    delivery_signature_url = coalesce(p_signature_url, delivery_signature_url),
    delivery_note = coalesce(p_delivery_note, delivery_note),
    empty_gallons_returned = coalesce(p_empty_gallons_returned, empty_gallons_returned, 0),
    delivery_lat = coalesce(p_lat, delivery_lat),
    delivery_lng = coalesce(p_lng, delivery_lng),
    payment_status = CASE
      WHEN lower(coalesce(payment_method, 'cod')) IN ('cod', 'cash') THEN 'success'
      ELSE payment_status
    END,
    updated_at = now()
  WHERE id = p_order_id;

  -- Notify Customer
  INSERT INTO public.system_notifications (
    user_id, type, priority, title, content, metadata
  ) VALUES (
    v_order.customer_id, 'system_alert', 'high', 'Refill Delivered',
    'Your water refill delivery has been completed. Thank you!',
    jsonb_build_object('order_id', p_order_id, 'status', 'delivered')
  );

  -- Notify Owner
  INSERT INTO public.system_notifications (
    user_id, type, priority, title, content, metadata
  ) VALUES (
    v_order.owner_id, 'system_alert', 'high', 'Delivery Completed',
    'Order #' || upper(substr(p_order_id::text, 1, 8)) || ' was successfully delivered to ' || coalesce(v_order.customer_name, 'customer') || '.',
    jsonb_build_object('order_id', p_order_id, 'status', 'delivered')
  );

  RETURN jsonb_build_object('success', true, 'message', 'Delivery confirmed successfully');
END;
$$;

GRANT EXECUTE ON FUNCTION public.confirm_delivery_safely(uuid, double precision, double precision, text, text, text, integer) TO authenticated;
REVOKE ALL ON FUNCTION public.confirm_delivery_safely(uuid, double precision, double precision, text, text, text, integer) FROM PUBLIC, anon;

-- Realtime streams need their source tables in Supabase's publication.
DO $$
DECLARE
  v_table text;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    FOREACH v_table IN ARRAY ARRAY[
      'profiles',
      'products',
      'orders',
      'order_items',
      'system_notifications',
      'payment_checkouts',
      'payment_webhook_events',
      'owner_inventory_ledger',
      'owner_settings',
      'customer_addresses',
      'customer_payment_methods',
      'owner_payout_accounts',
      'favorites',
      'messages',
      'reviews'
    ] LOOP
      IF to_regclass(format('public.%I', v_table)) IS NOT NULL
         AND NOT EXISTS (
           SELECT 1
           FROM pg_publication_tables
           WHERE pubname = 'supabase_realtime'
             AND schemaname = 'public'
             AND tablename = v_table
         ) THEN
        EXECUTE format(
          'ALTER PUBLICATION supabase_realtime ADD TABLE public.%I',
          v_table
        );
      END IF;
    END LOOP;
  END IF;
END $$;

COMMIT;

-- ── Admin role and RPCs ──
-- Deploy administrator RPC migrations using Supabase CLI or Dashboard SQL editor.
-- Keep administrative accounts managed via secure environment variables or auth vault.
