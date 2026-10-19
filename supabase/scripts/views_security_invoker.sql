-- =============================================================================
-- Reporting views: run with the caller's permissions (security_invoker)
-- =============================================================================
-- Why (Supabase security advisor, ERROR security_definer_view, 2026-10-19):
--   These views ran as their owner, bypassing RLS, and were readable by the
--   anon role. Anyone with the app's public key could read customer names and
--   barangays for every station's orders, every station's monthly revenue and
--   VAT estimate, and rider names with behaviour flags.
--
-- With security_invoker = true each view applies the caller's RLS on the
-- underlying tables: an owner sees only their station's rows, an admin sees
-- everything (is_admin() policies), anon sees nothing. The only client user,
-- the owner notifications screen, already filters sla_violations by its own
-- owner_id, so it keeps working.
--
-- Rollback: views_security_invoker_rollback.sql
-- =============================================================================

BEGIN;

ALTER VIEW public.dispatch_urgency_queue          SET (security_invoker = true);
ALTER VIEW public.integrity_violations            SET (security_invoker = true);
ALTER VIEW public.sla_violations                  SET (security_invoker = true);
ALTER VIEW public.v_barangay_demand_heatmap       SET (security_invoker = true);
ALTER VIEW public.v_rider_performance_leaderboard SET (security_invoker = true);
ALTER VIEW public.v_tax_reconciliation            SET (security_invoker = true);

REVOKE ALL ON public.dispatch_urgency_queue,
              public.integrity_violations,
              public.sla_violations,
              public.v_barangay_demand_heatmap,
              public.v_rider_performance_leaderboard,
              public.v_tax_reconciliation
  FROM anon;

COMMIT;
