-- Rolls back whole_peso_pricing.sql, qrph_payment_method.sql,
-- pay_before_fulfilment_guard.sql and service_fee_wallet.sql by restoring the
-- function definitions saved by payments_wallet_snapshot.sql and dropping the
-- wallet objects.
--
-- Does NOT restore: product prices / base delivery fees rounded to whole
-- pesos, or the three GCash orders marked paid as test data.
-- Dropping the wallet tables deletes every wallet balance and top-up record.

BEGIN;

DO $$
DECLARE
  v_row record;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.function_snapshots
    WHERE label = 'payments_wallet_2026_10_22'
  ) THEN
    RAISE EXCEPTION 'No snapshot found; run payments_wallet_snapshot.sql before the rollout.';
  END IF;

  FOR v_row IN
    SELECT definition FROM public.function_snapshots
    WHERE label = 'payments_wallet_2026_10_22'
  LOOP
    EXECUTE v_row.definition;
  END LOOP;
END $$;

DROP TRIGGER IF EXISTS trg_service_fee_wallet_on_delivery ON public.orders;

DROP FUNCTION IF EXISTS public.admin_adjust_fee_wallet(uuid, numeric, text);
DROP FUNCTION IF EXISTS public.admin_list_fee_wallets(timestamptz, timestamptz);
DROP FUNCTION IF EXISTS public.credit_wallet_topup(uuid);
DROP FUNCTION IF EXISTS public.record_wallet_topup_checkout(uuid, text, text, boolean);
DROP FUNCTION IF EXISTS public.create_wallet_topup(uuid, numeric, text);
DROP FUNCTION IF EXISTS public.station_cod_locked(uuid);
DROP FUNCTION IF EXISTS public.service_fee_wallet_config();
DROP FUNCTION IF EXISTS public.apply_wallet_entry(uuid, numeric, text, uuid, uuid, text);
DROP FUNCTION IF EXISTS public.price_order(numeric, numeric, numeric);
DROP FUNCTION IF EXISTS public.order_awaits_online_payment(public.orders);

DROP TABLE IF EXISTS public.station_fee_wallet_entries;
DROP TABLE IF EXISTS public.station_fee_topups;
DROP TABLE IF EXISTS public.station_fee_wallets;

DELETE FROM public.system_config WHERE key = 'service_fee_wallet';

-- QR Ph: fails if any qrph order or checkout exists; change those first.
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_payment_method_check;
ALTER TABLE public.orders ADD CONSTRAINT orders_payment_method_check
  CHECK (payment_method = ANY (ARRAY['cod', 'gcash', 'maya', 'card']::text[]));
ALTER TABLE public.payment_checkouts DROP CONSTRAINT IF EXISTS payment_checkouts_payment_method_check;
ALTER TABLE public.payment_checkouts ADD CONSTRAINT payment_checkouts_payment_method_check
  CHECK (payment_method = ANY (ARRAY['gcash', 'maya', 'card']::text[]));
ALTER TABLE public.owner_settings
  ALTER COLUMN enabled_payment_methods
  SET DEFAULT ARRAY['cod', 'gcash', 'maya', 'card']::text[];
UPDATE public.owner_settings
SET enabled_payment_methods = array_remove(enabled_payment_methods, 'qrph');

COMMIT;
