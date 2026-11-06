-- Run FIRST, before whole_peso_pricing.sql, qrph_payment_method.sql,
-- pay_before_fulfilment_guard.sql and service_fee_wallet.sql.
-- Saves the live definitions those scripts replace so
-- payments_wallet_rollback.sql can restore them. Safe to re-run: an existing
-- snapshot under the same label is kept, never overwritten.

BEGIN;

CREATE TABLE IF NOT EXISTS public.function_snapshots (
  label text NOT NULL,
  function_name text NOT NULL,
  definition text NOT NULL,
  taken_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (label, function_name)
);

ALTER TABLE public.function_snapshots ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.function_snapshots FROM anon, authenticated;

INSERT INTO public.function_snapshots (label, function_name, definition)
SELECT 'payments_wallet_2026_10_22', p.proname, pg_get_functiondef(p.oid)
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname IN (
    'create_order_atomic',
    'calculate_platform_fee',
    'get_station_available_payment_methods',
    'is_station_payment_method_available',
    'transition_order_status_safely',
    'confirm_delivery_safely',
    'proc_finalize_order_finances',
    'process_due_customer_subscriptions',
    'record_payment_checkout'
  )
ON CONFLICT (label, function_name) DO NOTHING;

COMMIT;
