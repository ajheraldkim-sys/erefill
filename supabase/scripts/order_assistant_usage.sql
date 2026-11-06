-- ==============================================================================
-- AI ordering assistant: per-user daily message limit (2026-11-05)
-- ==============================================================================
-- The order-assistant Edge Function records one row per message (with the
-- service role) and refuses more than 20 per user in 24 hours.
-- Users can read their own usage; nobody writes from the app.
-- ==============================================================================
BEGIN;

CREATE TABLE IF NOT EXISTS public.assistant_usage (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  input_tokens integer NOT NULL DEFAULT 0,
  output_tokens integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_assistant_usage_user_time ON public.assistant_usage (user_id, created_at DESC);

ALTER TABLE public.assistant_usage ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users read own assistant usage" ON public.assistant_usage;
CREATE POLICY "Users read own assistant usage" ON public.assistant_usage
  FOR SELECT TO authenticated USING (user_id = auth.uid());
REVOKE INSERT, UPDATE, DELETE ON public.assistant_usage FROM anon, authenticated;
GRANT SELECT ON public.assistant_usage TO authenticated;

COMMIT;
