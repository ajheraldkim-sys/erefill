-- QR Ph as a fifth payment method. Stations with no explicit
-- enabled_payment_methods get all five; stations that chose a list keep it.
-- Run after whole_peso_pricing.sql. Safe to re-run.
-- service_fee_wallet.sql redefines both functions again to add the COD lock.

BEGIN;

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
      ARRAY['cod', 'gcash', 'maya', 'card', 'qrph']::text[])) AS available,
    CASE WHEN method.type = ANY(COALESCE(settings.enabled_payment_methods,
      ARRAY['cod', 'gcash', 'maya', 'card', 'qrph']::text[]))
      THEN NULL ELSE 'This station has disabled this payment method.' END AS reason
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
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles owner_profile
    LEFT JOIN public.owner_settings settings
      ON settings.owner_id = owner_profile.id
    WHERE owner_profile.id = p_owner_id
      AND owner_profile.role = 'owner'
      AND COALESCE(settings.enabled_payment_methods,
        ARRAY['cod', 'gcash', 'maya', 'card', 'qrph']::text[])
        @> ARRAY[
          CASE lower(trim(p_payment_method))
            WHEN 'cash' THEN 'cod'
            WHEN 'paymaya' THEN 'maya'
            ELSE lower(trim(p_payment_method))
          END
        ]::text[]
  );
$function$;

ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_payment_method_check;
ALTER TABLE public.orders ADD CONSTRAINT orders_payment_method_check
  CHECK (payment_method = ANY (ARRAY['cod', 'gcash', 'maya', 'card', 'qrph']::text[]));

ALTER TABLE public.payment_checkouts DROP CONSTRAINT IF EXISTS payment_checkouts_payment_method_check;
ALTER TABLE public.payment_checkouts ADD CONSTRAINT payment_checkouts_payment_method_check
  CHECK (payment_method = ANY (ARRAY['gcash', 'maya', 'card', 'qrph']::text[]));

-- enabled_payment_methods is NOT NULL with a default, so most stations hold
-- the old four-method default rather than NULL. Stations still on that
-- untouched default get QR Ph; a station that chose its own list keeps it.
ALTER TABLE public.owner_settings
  ALTER COLUMN enabled_payment_methods
  SET DEFAULT ARRAY['cod', 'gcash', 'maya', 'card', 'qrph']::text[];

UPDATE public.owner_settings
SET enabled_payment_methods = ARRAY['cod', 'gcash', 'maya', 'card', 'qrph']::text[]
WHERE enabled_payment_methods = ARRAY['cod', 'gcash', 'maya', 'card']::text[];

COMMIT;
