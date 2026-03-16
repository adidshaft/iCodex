-- ============================================================
-- Phase 18: Scouting Logs Pattern Insight
-- Documents the new 'pattern_insight' action_type and
-- sets up the weekly pg_cron job.
-- ============================================================
-- NOTE: agent_scouting_logs.action_type uses text (not enum),
-- so no ALTER TYPE is required. This file just sets up the cron.
--
-- The edge function generate-scouting-logs already exists.
-- When called with { "mode": "pattern_insight" } it generates
-- weekly pattern summaries per user and inserts them with
-- action_type = 'pattern_insight'.
-- ============================================================

-- ─── Weekly Pattern Insight Cron Job ─────────────────────────────────────────
-- Runs every Sunday at 20:00 UTC (01:30 IST Monday).
-- Requires: pg_cron + pg_net extensions enabled in Supabase.
-- Replace placeholders before running.

SELECT cron.schedule(
  'weekly-pattern-insight',
  '0 20 * * 0',
  $$
  SELECT net.http_post(
    url     := 'https://femzgnhpgkxktbwsnrfq.supabase.co/functions/v1/generate-scouting-logs',
    headers := jsonb_build_object(
      'x-admin-secret', 'my_ultra_secure_secret_123',
      'Content-Type',   'application/json'
    ),
    body    := '{"mode":"pattern_insight"}'::jsonb
  )
  $$
);
-- ─── Index for Pattern Insight Queries ───────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_asl_pattern_insight
  ON public.agent_scouting_logs (user_id, created_at DESC)
  WHERE action_type = 'pattern_insight';
-- ─── Verification ─────────────────────────────────────────────────────────────
-- SELECT * FROM cron.job WHERE jobname = 'weekly-pattern-insight';
-- To test manually:
-- curl -X POST https://[SUPABASE_URL]/functions/v1/generate-scouting-logs \
--   -H "x-admin-secret: [ADMIN_SECRET]" \
--   -H "Content-Type: application/json" \
--   -d '{"mode":"pattern_insight"}';
