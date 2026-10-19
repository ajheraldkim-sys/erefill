-- Rollback for views_security_invoker.sql: restores definer semantics and
-- anon SELECT (the previous, insecure state).

BEGIN;

ALTER VIEW public.dispatch_urgency_queue          RESET (security_invoker);
ALTER VIEW public.integrity_violations            RESET (security_invoker);
ALTER VIEW public.sla_violations                  RESET (security_invoker);
ALTER VIEW public.v_barangay_demand_heatmap       RESET (security_invoker);
ALTER VIEW public.v_rider_performance_leaderboard RESET (security_invoker);
ALTER VIEW public.v_tax_reconciliation            RESET (security_invoker);

GRANT SELECT ON public.dispatch_urgency_queue,
                public.integrity_violations,
                public.sla_violations,
                public.v_barangay_demand_heatmap,
                public.v_rider_performance_leaderboard,
                public.v_tax_reconciliation
  TO anon;

COMMIT;
