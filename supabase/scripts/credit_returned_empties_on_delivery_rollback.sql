-- Rollback for credit_returned_empties_on_delivery.sql. Credits and ledger
-- rows already written are kept.

BEGIN;

DROP TRIGGER IF EXISTS trg_credit_returned_empties ON public.orders;
DROP FUNCTION IF EXISTS public.proc_credit_returned_empties();

COMMIT;
