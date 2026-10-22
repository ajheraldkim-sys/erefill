-- Prepaid service fee wallet. Online orders are paid into the eRefill
-- PayMongo account, so eRefill already holds their service fee; a COD (or
-- store credit) order's fee is taken from the station's wallet when it is
-- delivered. A wallet at or below `cod_lock_at_or_below` switches off COD for
-- that station only — online methods keep working.
-- Run after pay_before_fulfilment_guard.sql. Safe to re-run.

BEGIN;

INSERT INTO public.system_config (key, value, description)
VALUES (
  'service_fee_wallet',
  '{"min_topup": 100, "low_balance_alert": 100, "cod_lock_at_or_below": 0}'::jsonb,
  'Station service fee wallet: minimum top-up, low-balance alert and COD lock thresholds (PHP).'
)
ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.station_fee_wallets (
  owner_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  balance numeric(10,2) NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.station_fee_topups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  amount numeric(10,2) NOT NULL CHECK (amount > 0),
  payment_method text NOT NULL CHECK (payment_method IN ('gcash', 'maya', 'card', 'qrph')),
  provider_checkout_id text UNIQUE,
  checkout_url text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'paid', 'failed', 'expired')),
  livemode boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  paid_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.station_fee_wallet_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  amount numeric(10,2) NOT NULL,
  kind text NOT NULL CHECK (kind IN ('topup', 'service_fee', 'adjustment')),
  order_id uuid REFERENCES public.orders(id) ON DELETE SET NULL,
  topup_id uuid REFERENCES public.station_fee_topups(id) ON DELETE SET NULL,
  note text,
  actor_id uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS station_fee_wallet_entries_one_fee_per_order
  ON public.station_fee_wallet_entries (order_id) WHERE kind = 'service_fee';
CREATE UNIQUE INDEX IF NOT EXISTS station_fee_wallet_entries_one_credit_per_topup
  ON public.station_fee_wallet_entries (topup_id) WHERE kind = 'topup';
CREATE INDEX IF NOT EXISTS station_fee_wallet_entries_owner_created
  ON public.station_fee_wallet_entries (owner_id, created_at DESC);
CREATE INDEX IF NOT EXISTS station_fee_topups_owner_created
  ON public.station_fee_topups (owner_id, created_at DESC);

ALTER TABLE public.station_fee_wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.station_fee_topups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.station_fee_wallet_entries ENABLE ROW LEVEL SECURITY;

-- Read-only to their owner and to admins; every write goes through the
-- SECURITY DEFINER functions below.
DROP POLICY IF EXISTS station_fee_wallets_read ON public.station_fee_wallets;
CREATE POLICY station_fee_wallets_read ON public.station_fee_wallets
  FOR SELECT TO authenticated
  USING (owner_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS station_fee_topups_read ON public.station_fee_topups;
CREATE POLICY station_fee_topups_read ON public.station_fee_topups
  FOR SELECT TO authenticated
  USING (owner_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS station_fee_wallet_entries_read ON public.station_fee_wallet_entries;
CREATE POLICY station_fee_wallet_entries_read ON public.station_fee_wallet_entries
  FOR SELECT TO authenticated
  USING (owner_id = auth.uid() OR public.is_admin());

REVOKE INSERT, UPDATE, DELETE ON public.station_fee_wallets FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.station_fee_topups FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.station_fee_wallet_entries FROM anon, authenticated;
GRANT SELECT ON public.station_fee_wallets, public.station_fee_topups, public.station_fee_wallet_entries TO authenticated;

CREATE OR REPLACE FUNCTION public.service_fee_wallet_config()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT coalesce(
    (SELECT value FROM public.system_config WHERE key = 'service_fee_wallet'),
    '{"min_topup": 100, "low_balance_alert": 100, "cod_lock_at_or_below": 0}'::jsonb
  );
$function$;

GRANT EXECUTE ON FUNCTION public.service_fee_wallet_config() TO authenticated;

-- Adds one signed entry and moves the balance in the same transaction.
-- A second service_fee entry for the same order, or a second topup entry for
-- the same top-up, is ignored. Returns the balance afterwards.
CREATE OR REPLACE FUNCTION public.apply_wallet_entry(
  p_owner_id uuid,
  p_amount numeric,
  p_kind text,
  p_order_id uuid DEFAULT NULL,
  p_topup_id uuid DEFAULT NULL,
  p_note text DEFAULT NULL
)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_old numeric;
  v_new numeric;
  v_entry_id uuid;
  v_alert numeric := coalesce((public.service_fee_wallet_config()->>'low_balance_alert')::numeric, 100);
BEGIN
  INSERT INTO public.station_fee_wallets (owner_id) VALUES (p_owner_id)
  ON CONFLICT (owner_id) DO NOTHING;

  SELECT balance INTO v_old FROM public.station_fee_wallets
  WHERE owner_id = p_owner_id FOR UPDATE;

  IF p_kind = 'service_fee' AND p_order_id IS NOT NULL THEN
    INSERT INTO public.station_fee_wallet_entries (owner_id, amount, kind, order_id, note, actor_id)
    VALUES (p_owner_id, p_amount, p_kind, p_order_id, p_note, auth.uid())
    ON CONFLICT (order_id) WHERE kind = 'service_fee' DO NOTHING
    RETURNING id INTO v_entry_id;
  ELSIF p_kind = 'topup' AND p_topup_id IS NOT NULL THEN
    INSERT INTO public.station_fee_wallet_entries (owner_id, amount, kind, topup_id, note, actor_id)
    VALUES (p_owner_id, p_amount, p_kind, p_topup_id, p_note, auth.uid())
    ON CONFLICT (topup_id) WHERE kind = 'topup' DO NOTHING
    RETURNING id INTO v_entry_id;
  ELSE
    INSERT INTO public.station_fee_wallet_entries (owner_id, amount, kind, order_id, topup_id, note, actor_id)
    VALUES (p_owner_id, p_amount, p_kind, p_order_id, p_topup_id, p_note, auth.uid())
    RETURNING id INTO v_entry_id;
  END IF;

  IF v_entry_id IS NULL THEN
    RETURN v_old;
  END IF;

  UPDATE public.station_fee_wallets
  SET balance = balance + p_amount, updated_at = now()
  WHERE owner_id = p_owner_id
  RETURNING balance INTO v_new;

  IF v_old >= v_alert AND v_new < v_alert THEN
    INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
    VALUES (
      p_owner_id, 'system_alert', 'high',
      'Service fee balance is low',
      'Top up to keep Cash on Delivery on.',
      jsonb_build_object('kind', 'fee_wallet_low', 'balance', v_new)
    );
  END IF;

  RETURN v_new;
END;
$function$;

REVOKE ALL ON FUNCTION public.apply_wallet_entry(uuid, numeric, text, uuid, uuid, text) FROM PUBLIC, anon, authenticated;

-- True when the platform fee is on and the station's wallet (no wallet = ₱0)
-- is at or below the COD lock threshold.
CREATE OR REPLACE FUNCTION public.station_cod_locked(p_owner_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT coalesce((public.get_platform_fee_config()->>'enabled')::boolean, false)
     AND coalesce(
           (SELECT balance FROM public.station_fee_wallets WHERE owner_id = p_owner_id),
           0
         ) <= coalesce((public.service_fee_wallet_config()->>'cod_lock_at_or_below')::numeric, 0);
$function$;

GRANT EXECUTE ON FUNCTION public.station_cod_locked(uuid) TO authenticated;

-- qrph_payment_method.sql versions plus the COD lock.
CREATE OR REPLACE FUNCTION public.get_station_available_payment_methods(p_owner_id uuid)
RETURNS TABLE(type text, label text, available boolean, reason text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT
    method.type,
    method.label,
    method.type = ANY(COALESCE(settings.enabled_payment_methods,
        ARRAY['cod', 'gcash', 'maya', 'card', 'qrph']::text[]))
      AND NOT (method.type = 'cod' AND public.station_cod_locked(p_owner_id)) AS available,
    CASE
      WHEN NOT method.type = ANY(COALESCE(settings.enabled_payment_methods,
          ARRAY['cod', 'gcash', 'maya', 'card', 'qrph']::text[]))
        THEN 'This station has disabled this payment method.'
      WHEN method.type = 'cod' AND public.station_cod_locked(p_owner_id)
        THEN 'Cash on Delivery is unavailable for this station right now.'
      ELSE NULL
    END AS reason
  FROM (
    VALUES
      ('cod'::text, 'Cash on Delivery'::text),
      ('gcash'::text, 'GCash'::text),
      ('maya'::text, 'Maya'::text),
      ('card'::text, 'Credit/Debit Card'::text),
      ('qrph'::text, 'QR Ph'::text)
  ) AS method(type, label)
  LEFT JOIN public.owner_settings settings ON settings.owner_id = p_owner_id
  WHERE EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = p_owner_id AND role = 'owner'
  );
$function$;

CREATE OR REPLACE FUNCTION public.is_station_payment_method_available(p_owner_id uuid, p_payment_method text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  WITH normalized AS (
    SELECT CASE lower(trim(p_payment_method))
      WHEN 'cash' THEN 'cod'
      WHEN 'paymaya' THEN 'maya'
      ELSE lower(trim(p_payment_method))
    END AS method
  )
  SELECT EXISTS (
    SELECT 1
    FROM normalized
    CROSS JOIN public.profiles owner_profile
    LEFT JOIN public.owner_settings settings
      ON settings.owner_id = owner_profile.id
    WHERE owner_profile.id = p_owner_id
      AND owner_profile.role = 'owner'
      AND COALESCE(settings.enabled_payment_methods,
        ARRAY['cod', 'gcash', 'maya', 'card', 'qrph']::text[])
        @> ARRAY[normalized.method]::text[]
      AND NOT (normalized.method = 'cod' AND public.station_cod_locked(p_owner_id))
  );
$function$;

-- Live proc_finalize_order_finances (2026-10-22): the station's SALE now
-- excludes the service fee, which is recorded as platform revenue, and a
-- COD/credit order's fee comes off the station's wallet. Rider commission
-- is unchanged.
CREATE OR REPLACE FUNCTION public.proc_finalize_order_finances()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_commission NUMERIC;
    v_fee NUMERIC := greatest(coalesce(NEW.platform_fee, 0), 0);
BEGIN
    IF NEW.status = 'delivered' AND OLD.status != 'delivered' THEN

        INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
        VALUES (NEW.owner_id, NEW.id, NEW.total_amount - v_fee, 'SALE', 'Order completion payment');

        IF v_fee > 0 THEN
            INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description, metadata)
            VALUES (
                NEW.owner_id, NEW.id, v_fee, 'SERVICE_FEE', 'Platform service fee',
                jsonb_build_object('payee', 'platform', 'payment_method', NEW.payment_method)
            );

            IF lower(coalesce(NEW.payment_method, 'cod')) IN ('cod', 'cash', 'credit') THEN
                PERFORM public.apply_wallet_entry(
                    NEW.owner_id, -v_fee, 'service_fee', NEW.id, NULL,
                    'Service fee for order ' || upper(substr(NEW.id::text, 1, 8))
                );
            END IF;
        END IF;

        -- Hardcoded 10% for now or from owner_settings if implemented
        v_commission := NEW.total_amount * 0.10;

        IF NEW.assigned_rider_id IS NOT NULL THEN
            INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
            VALUES (NEW.assigned_rider_id, NEW.id, v_commission, 'COMMISSION', 'Delivery commission for order');
        END IF;

        INSERT INTO public.domain_events (event_type, payload, actor_id)
        VALUES ('ORDER_COMPLETED', jsonb_build_object('order_id', NEW.id, 'total', NEW.total_amount, 'rider_id', NEW.assigned_rider_id), auth.uid());

    END IF;
    RETURN NEW;
END;
$function$;

-- whole_peso_pricing.sql version, plus: a COD subscription whose station has
-- COD locked is skipped (schedule not advanced) and the owner and customer
-- are told once per day.
CREATE OR REPLACE FUNCTION public.process_due_customer_subscriptions()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    sub RECORD;
    v_order_id UUID;
    v_date_str TEXT;
    v_idempotency_key TEXT;
    v_next_date TIMESTAMPTZ;
    v_orders_created INT := 0;
    v_unit_price NUMERIC;
    v_price RECORD;
    v_lat DOUBLE PRECISION;
    v_lng DOUBLE PRECISION;
    v_orders_skipped INT := 0;
BEGIN
    v_date_str := to_char(CURRENT_DATE, 'YYYY-MM-DD');

    FOR sub IN
        SELECT *
        FROM public.customer_subscriptions
        WHERE is_active = true
          AND next_delivery_date <= NOW() + INTERVAL '1 hour'
    LOOP
        v_idempotency_key := 'auto_sub_' || sub.id || '_' || v_date_str;

        IF lower(coalesce(sub.payment_method, 'cod')) IN ('cod', 'cash')
           AND public.station_cod_locked(sub.station_id) THEN
            IF NOT EXISTS (
                SELECT 1 FROM public.system_notifications
                WHERE metadata->>'kind' = 'cod_locked_skip'
                  AND metadata->>'subscription_id' = sub.id::text
                  AND metadata->>'date' = v_date_str
            ) THEN
                INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
                VALUES
                  (sub.station_id, 'system_alert', 'high', 'Auto-refill skipped',
                   'A customer''s Cash on Delivery auto-refill was skipped because Cash on Delivery is off. Top up your service fee balance to turn it back on.',
                   jsonb_build_object('kind', 'cod_locked_skip', 'subscription_id', sub.id, 'date', v_date_str)),
                  (sub.customer_id, 'system_alert', 'high', 'Auto-refill delayed',
                   'Your Cash on Delivery auto-refill from ' || coalesce(sub.station_name, 'your station') || ' is delayed because the station cannot take Cash on Delivery right now.',
                   jsonb_build_object('kind', 'cod_locked_skip', 'subscription_id', sub.id, 'date', v_date_str));
            END IF;
            v_orders_skipped := v_orders_skipped + 1;
            CONTINUE;
        END IF;

        IF NOT EXISTS (
            SELECT 1 FROM public.orders WHERE idempotency_key = v_idempotency_key
        ) THEN
          BEGIN
            v_order_id := gen_random_uuid();
            SELECT * INTO v_price FROM public.price_order(sub.estimated_price, 0, 0);
            SELECT latitude, longitude INTO v_lat, v_lng
            FROM public.profiles WHERE id = sub.customer_id;
            v_unit_price := CASE
                WHEN sub.quantity > 0 THEN ROUND(v_price.subtotal / sub.quantity, 2)
                ELSE v_price.subtotal
            END;

            INSERT INTO public.orders (
                id,
                customer_id,
                owner_id,
                station_name,
                customer_address,
                idempotency_key,
                subtotal,
                delivery_fee,
                platform_fee,
                total_amount,
                payment_method,
                status,
                notes,
                items,
                customer_latitude,
                customer_longitude,
                delivery_latitude,
                delivery_longitude,
                created_at,
                updated_at
            ) VALUES (
                v_order_id,
                sub.customer_id,
                sub.station_id,
                sub.station_name,
                sub.delivery_address,
                v_idempotency_key,
                v_price.subtotal,
                v_price.delivery_fee,
                v_price.service_fee,
                v_price.total,
                sub.payment_method,
                'pending',
                'Auto-Refill Routine (' || sub.frequency || ') - Slot: ' || sub.preferred_time_slot,
                jsonb_build_array(jsonb_build_object(
                    'product_name', sub.water_type || ' Refill',
                    'quantity', sub.quantity,
                    'price', v_unit_price,
                    'total_price', v_price.subtotal
                )),
                v_lat,
                v_lng,
                v_lat,
                v_lng,
                NOW(),
                NOW()
            );

            INSERT INTO public.order_items (
                order_id,
                product_name,
                water_type,
                quantity,
                unit_price,
                price_per_gallon,
                total_price,
                price_at_purchase,
                subtotal
            ) VALUES (
                v_order_id,
                sub.water_type || ' Refill',
                sub.water_type,
                sub.quantity,
                v_unit_price,
                v_unit_price,
                v_price.subtotal,
                v_unit_price,
                v_price.subtotal
            );

            v_orders_created := v_orders_created + 1;
          EXCEPTION WHEN OTHERS THEN
            v_orders_skipped := v_orders_skipped + 1;
            RAISE WARNING 'Auto-order skipped for subscription %: %', sub.id, SQLERRM;
          END;
        END IF;

        v_next_date := CASE sub.frequency
            WHEN 'every_3_days' THEN sub.next_delivery_date + INTERVAL '3 days'
            WHEN 'twice_weekly' THEN sub.next_delivery_date + INTERVAL '4 days'
            WHEN 'weekly'       THEN sub.next_delivery_date + INTERVAL '7 days'
            WHEN 'bi_weekly'    THEN sub.next_delivery_date + INTERVAL '14 days'
            WHEN 'monthly'      THEN sub.next_delivery_date + INTERVAL '1 month'
            ELSE sub.next_delivery_date + INTERVAL '7 days'
        END;

        WHILE v_next_date <= NOW() LOOP
            v_next_date := CASE sub.frequency
                WHEN 'every_3_days' THEN v_next_date + INTERVAL '3 days'
                WHEN 'twice_weekly' THEN v_next_date + INTERVAL '4 days'
                WHEN 'weekly'       THEN v_next_date + INTERVAL '7 days'
                WHEN 'bi_weekly'    THEN v_next_date + INTERVAL '14 days'
                WHEN 'monthly'      THEN v_next_date + INTERVAL '1 month'
                ELSE v_next_date + INTERVAL '7 days'
            END;
        END LOOP;

        UPDATE public.customer_subscriptions
        SET next_delivery_date = v_next_date,
            updated_at = NOW()
        WHERE id = sub.id;

    END LOOP;

    RETURN jsonb_build_object(
        'success', true,
        'orders_created', v_orders_created,
        'orders_skipped', v_orders_skipped,
        'timestamp', NOW()
    );
END;
$function$;

-- Wallet top-ups, paid through the eRefill PayMongo account. Called by the
-- create-payment-checkout and paymongo-webhook edge functions (service role).
CREATE OR REPLACE FUNCTION public.create_wallet_topup(
  p_owner_id uuid,
  p_amount numeric,
  p_payment_method text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_min numeric := coalesce((public.service_fee_wallet_config()->>'min_topup')::numeric, 100);
  v_method text := replace(lower(trim(coalesce(p_payment_method, ''))), 'paymaya', 'maya');
  v_id uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_owner_id AND role = 'owner') THEN
    RAISE EXCEPTION 'Only station owners can top up a service fee wallet.';
  END IF;
  IF p_amount IS NULL OR p_amount <> round(p_amount) OR p_amount < v_min THEN
    RAISE EXCEPTION 'Top-up must be a whole peso amount of at least ₱%.', trim(to_char(v_min, 'FM999999990'));
  END IF;
  IF v_method NOT IN ('gcash', 'maya', 'card', 'qrph') THEN
    RAISE EXCEPTION 'Unsupported payment method.';
  END IF;

  INSERT INTO public.station_fee_topups (owner_id, amount, payment_method)
  VALUES (p_owner_id, p_amount, v_method)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.record_wallet_topup_checkout(
  p_topup_id uuid,
  p_provider_checkout_id text,
  p_checkout_url text,
  p_livemode boolean
)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  UPDATE public.station_fee_topups
  SET provider_checkout_id = p_provider_checkout_id,
      checkout_url = p_checkout_url,
      livemode = p_livemode
  WHERE id = p_topup_id AND status = 'pending';
$function$;

-- Marks a top-up paid and credits the wallet exactly once; later calls (a
-- webhook retry, or the app's verify racing the webhook) change nothing.
-- Returns the wallet balance.
CREATE OR REPLACE FUNCTION public.credit_wallet_topup(p_topup_id uuid)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_topup public.station_fee_topups%ROWTYPE;
BEGIN
  SELECT * INTO v_topup FROM public.station_fee_topups WHERE id = p_topup_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Top-up not found.';
  END IF;

  IF v_topup.status <> 'paid' THEN
    UPDATE public.station_fee_topups
    SET status = 'paid', paid_at = now()
    WHERE id = p_topup_id;
  END IF;

  RETURN public.apply_wallet_entry(
    v_topup.owner_id, v_topup.amount, 'topup', NULL, v_topup.id,
    CASE WHEN v_topup.livemode THEN 'Top-up' ELSE 'Top-up (test mode)' END
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.create_wallet_topup(uuid, numeric, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_wallet_topup_checkout(uuid, text, text, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.credit_wallet_topup(uuid) FROM PUBLIC, anon, authenticated;

-- Admin overview: every station's wallet plus fees collected (COD fees taken
-- from wallets and the service fee on delivered online orders) and top-ups in
-- the optional date range.
CREATE OR REPLACE FUNCTION public.admin_list_fee_wallets(
  p_from timestamptz DEFAULT NULL,
  p_to timestamptz DEFAULT NULL
)
RETURNS TABLE (
  owner_id uuid,
  station_name text,
  balance numeric,
  cod_locked boolean,
  last_topup_at timestamptz,
  fees_collected numeric,
  topups_received numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin access required.';
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    coalesce(nullif(trim(p.station_name), ''), p.full_name, 'Station')::text,
    coalesce(w.balance, 0),
    public.station_cod_locked(p.id),
    (SELECT max(t.paid_at) FROM public.station_fee_topups t
      WHERE t.owner_id = p.id AND t.status = 'paid'),
    coalesce((SELECT sum(-e.amount) FROM public.station_fee_wallet_entries e
      WHERE e.owner_id = p.id AND e.kind = 'service_fee'
        AND (p_from IS NULL OR e.created_at >= p_from)
        AND (p_to IS NULL OR e.created_at < p_to)), 0)
    + coalesce((SELECT sum(o.platform_fee) FROM public.orders o
      WHERE o.owner_id = p.id AND o.status = 'delivered'
        AND lower(coalesce(o.payment_method, 'cod')) IN ('gcash', 'maya', 'card', 'qrph')
        AND (p_from IS NULL OR coalesce(o.actual_completion_at, o.updated_at) >= p_from)
        AND (p_to IS NULL OR coalesce(o.actual_completion_at, o.updated_at) < p_to)), 0),
    coalesce((SELECT sum(e.amount) FROM public.station_fee_wallet_entries e
      WHERE e.owner_id = p.id AND e.kind = 'topup'
        AND (p_from IS NULL OR e.created_at >= p_from)
        AND (p_to IS NULL OR e.created_at < p_to)), 0)
  FROM public.profiles p
  LEFT JOIN public.station_fee_wallets w ON w.owner_id = p.id
  WHERE p.role = 'owner'
  ORDER BY coalesce(w.balance, 0) ASC, 2;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_adjust_fee_wallet(
  p_owner_id uuid,
  p_amount numeric,
  p_reason text
)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_old numeric;
  v_new numeric;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin access required.';
  END IF;
  IF nullif(trim(coalesce(p_reason, '')), '') IS NULL THEN
    RAISE EXCEPTION 'A reason is required for a wallet adjustment.';
  END IF;
  IF p_amount IS NULL OR p_amount = 0 THEN
    RAISE EXCEPTION 'Adjustment amount cannot be zero.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_owner_id AND role = 'owner') THEN
    RAISE EXCEPTION 'Station not found.';
  END IF;

  SELECT coalesce((SELECT balance FROM public.station_fee_wallets WHERE owner_id = p_owner_id), 0)
  INTO v_old;
  v_new := public.apply_wallet_entry(p_owner_id, p_amount, 'adjustment', NULL, NULL, trim(p_reason));

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, old_value, new_value, metadata)
  VALUES (
    auth.uid(), 'FEE_WALLET_ADJUST', 'station_fee_wallet', p_owner_id::text,
    jsonb_build_object('balance', v_old),
    jsonb_build_object('balance', v_new),
    jsonb_build_object('amount', p_amount, 'reason', trim(p_reason))
  );
  RETURN v_new;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.admin_list_fee_wallets(timestamptz, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_adjust_fee_wallet(uuid, numeric, text) TO authenticated;

COMMIT;
