-- ==============================================================================
-- Rider tips (2026-11-05)
-- ==============================================================================
-- Customers can add an optional tip (₱0–₱500, whole pesos) at checkout for
-- delivery orders. It is part of the single charge (COD or PayMongo), so no
-- second payment is needed, and 100% goes to the rider:
--   * excluded from the station SALE and from the 10% commission base
--   * booked as a RIDER_TIP ledger entry to the assigned rider
--   * if no rider was assigned (station delivered itself) it stays with the
--     station as part of the SALE
-- create_order_atomic reads p_order_data->>'tip_amount' (order_pricing_v3.sql).
--
-- Run before: order_pricing_v3.sql. Test: supabase/tests/rider_tips_test.sql
-- ==============================================================================
BEGIN;

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS tip_amount numeric(10,2) NOT NULL DEFAULT 0;
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_tip_amount_check;
ALTER TABLE public.orders ADD CONSTRAINT orders_tip_amount_check
  CHECK (tip_amount >= 0 AND tip_amount <= 500);

CREATE OR REPLACE FUNCTION public.proc_finalize_order_finances()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    v_commission NUMERIC;
    v_fee NUMERIC := greatest(coalesce(NEW.platform_fee, 0), 0);
    v_tip NUMERIC := greatest(coalesce(NEW.tip_amount, 0), 0);
    v_rider_tip NUMERIC := 0;
BEGIN
    IF NEW.status = 'delivered' AND OLD.status != 'delivered' THEN
        -- The tip belongs to the rider; without a rider it stays in the sale.
        IF NEW.assigned_rider_id IS NOT NULL THEN
            v_rider_tip := v_tip;
        END IF;

        INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
        VALUES (NEW.owner_id, NEW.id, NEW.total_amount - v_fee - v_rider_tip, 'SALE', 'Order completion payment');

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

        -- Commission excludes the tip.
        v_commission := (NEW.total_amount - v_tip) * 0.10;

        IF NEW.assigned_rider_id IS NOT NULL THEN
            INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
            VALUES (NEW.assigned_rider_id, NEW.id, v_commission, 'COMMISSION', 'Delivery commission for order');

            IF v_rider_tip > 0 THEN
                INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
                VALUES (NEW.assigned_rider_id, NEW.id, v_rider_tip, 'RIDER_TIP', 'Customer tip');

                INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
                VALUES (
                    NEW.assigned_rider_id, 'system_alert', 'normal', 'You got a tip!',
                    'A customer tipped you PHP ' || trim(to_char(v_rider_tip, '999990')) || '. Thank you for the great service.',
                    jsonb_build_object('order_id', NEW.id, 'tip_amount', v_rider_tip)
                );
            END IF;
        END IF;

        INSERT INTO public.domain_events (event_type, payload, actor_id)
        VALUES ('ORDER_COMPLETED', jsonb_build_object(
            'order_id', NEW.id, 'total', NEW.total_amount,
            'rider_id', NEW.assigned_rider_id, 'tip', v_tip), auth.uid());
    END IF;
    RETURN NEW;
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';
