-- Fix Order Transitions, Sync Rider Columns, and Enhance Realtime Reliability

-- 1. Synchronize rider_id and assigned_rider_id trigger
CREATE OR REPLACE FUNCTION public.sync_order_rider_columns()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.assigned_rider_id IS NOT NULL AND NEW.rider_id IS NULL THEN
    NEW.rider_id := NEW.assigned_rider_id;
  ELSIF NEW.rider_id IS NOT NULL AND NEW.assigned_rider_id IS NULL THEN
    NEW.assigned_rider_id := NEW.rider_id;
  ELSIF NEW.assigned_rider_id IS NOT NULL AND NEW.rider_id IS NOT NULL AND NEW.assigned_rider_id <> NEW.rider_id THEN
    IF OLD.assigned_rider_id IS DISTINCT FROM NEW.assigned_rider_id THEN
      NEW.rider_id := NEW.assigned_rider_id;
    ELSIF OLD.rider_id IS DISTINCT FROM NEW.rider_id THEN
      NEW.assigned_rider_id := NEW.rider_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_sync_order_rider_columns ON public.orders;
CREATE TRIGGER trg_sync_order_rider_columns
BEFORE INSERT OR UPDATE ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.sync_order_rider_columns();

-- 2. Backfill existing orders where one is populated and the other is null
UPDATE public.orders
SET rider_id = assigned_rider_id
WHERE assigned_rider_id IS NOT NULL AND rider_id IS NULL;

UPDATE public.orders
SET assigned_rider_id = rider_id
WHERE rider_id IS NOT NULL AND assigned_rider_id IS NULL;

-- After this rider-column repair, apply automated_proof_of_delivery.sql,
-- then harden_order_status_transitions.sql.
