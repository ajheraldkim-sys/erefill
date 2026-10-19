-- =============================================================================
-- Credit returned empty gallons to the station when an order is delivered
-- =============================================================================
-- Why (verified against production 2026-10-19):
--   Riders record returned empties at delivery (confirm_delivery_safely stores
--   orders.empty_gallons_returned), and the app then tried to add them to
--   owner_settings.empty_gallons_stock from the client. Riders may not write
--   owner_settings (owner-only RLS) and owner_inventory_ledger has no INSERT
--   policy, so every attempt failed silently: 8 rider deliveries, 10 returned
--   empties, none credited.
--
-- Filled stock is NOT touched here: it is already reserved when the order is
-- placed (trigger handle_inventory_deduction on order_items) and restored on
-- cancellation (proc_restore_inventory_on_cancellation). That rule is unchanged.
--
-- On the transition to 'delivered' (any path: rider proof RPC, owner, admin),
-- in the same transaction, once per order:
--   owner_settings.empty_gallons_stock += orders.empty_gallons_returned
--   owner_inventory_ledger row (tx_type empty_return, positive gallons)
--
-- Past deliveries are NOT back-filled by this script.
-- Rollback: credit_returned_empties_on_delivery_rollback.sql
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.proc_credit_returned_empties()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_empties integer := coalesce(NEW.empty_gallons_returned, 0);
BEGIN
  IF v_empties <= 0
     OR NEW.owner_id IS NULL
     OR EXISTS (
       SELECT 1 FROM public.owner_inventory_ledger
       WHERE order_id = NEW.id AND tx_type = 'empty_return'
     ) THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.owner_settings (owner_id, empty_gallons_stock)
  VALUES (NEW.owner_id, 0)
  ON CONFLICT (owner_id) DO NOTHING;

  UPDATE public.owner_settings
  SET empty_gallons_stock = coalesce(empty_gallons_stock, 0) + v_empties,
      updated_at = now()
  WHERE owner_id = NEW.owner_id;

  INSERT INTO public.owner_inventory_ledger
    (owner_id, tx_type, gallons, order_id, notes, actor_id)
  VALUES
    (NEW.owner_id, 'empty_return', v_empties, NEW.id,
     'Order #' || upper(left(NEW.id::text, 8)) || ': empties returned',
     auth.uid());

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.proc_credit_returned_empties() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_credit_returned_empties ON public.orders;
CREATE TRIGGER trg_credit_returned_empties
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW
  WHEN (NEW.status = 'delivered' AND OLD.status IS DISTINCT FROM 'delivered')
  EXECUTE FUNCTION public.proc_credit_returned_empties();

COMMIT;
