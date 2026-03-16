-- ============================================================
-- Phase 18: generate-match-reflection Configuration
-- Documents webhook setup and cron jobs for triggering
-- the new generate-match-reflection edge function.
-- ============================================================
--
-- SETUP STEPS:
-- 1. Deploy generate-match-reflection edge function (done in code)
-- 2. Set up two Supabase Database Webhooks (Dashboard → Database → Webhooks):
--    a) match_feedback INSERT → generate-match-reflection
--    b) matches UPDATE (when status changes to 'rejected' or 'expired')
--       → generate-match-reflection
-- 3. Run the cron job below for the 72-hour silence check.
--
-- The function is IDEMPOTENT. Duplicate webhook retries are safe —
-- the UNIQUE(user_id, source_match_id, source) constraint on agent_memories
-- causes duplicate inserts to silently no-op.
-- ============================================================

-- ─── WEBHOOK A: Thumbs-down feedback → agent reflection ──────────────────────
-- Dashboard → Database → Webhooks → New Webhook:
--   Name:    match-feedback-reflection
--   Table:   match_feedback
--   Events:  INSERT
--   URL:     https://[SUPABASE_URL]/functions/v1/generate-match-reflection
--   Headers: { "x-admin-secret": "[ADMIN_SECRET]", "Content-Type": "application/json" }
--   Payload: { "mode": "feedback", "record": {entire NEW record} }


-- ─── WEBHOOK B: Match status change → agent reflection ───────────────────────
-- Dashboard → Database → Webhooks → New Webhook:
--   Name:    match-status-reflection
--   Table:   matches
--   Events:  UPDATE
--   Filter:  new.status IN ('rejected', 'expired') AND old.status != new.status
--   URL:     https://[SUPABASE_URL]/functions/v1/generate-match-reflection
--   Headers: { "x-admin-secret": "[ADMIN_SECRET]", "Content-Type": "application/json" }
--   Payload: { "mode": "status_change", "record": {entire NEW record} }


-- ─── CRON C: 72-hour conversation silence check ───────────────────────────────
-- Runs daily at 10:00 UTC. Finds matches with no messages in 72h
-- after at least 3 messages were exchanged.
SELECT cron.schedule(
  'conversation-silence-check',
  '0 10 * * *',
  $$
  SELECT net.http_post(
    url     := 'https://femzgnhpgkxktbwsnrfq.supabase.co/functions/v1/generate-match-reflection',
    headers := jsonb_build_object(
      'x-admin-secret', 'my_ultra_secure_secret_123',
      'Content-Type',   'application/json'
    ),
    body    := '{"mode":"silence_check"}'::jsonb
  )
  $$
);
-- ─── Verification ─────────────────────────────────────────────────────────────
-- SELECT * FROM cron.job WHERE jobname = 'conversation-silence-check';
-- After triggering via webhook or cron:
-- SELECT * FROM agent_memories WHERE source = 'agent_reflection' ORDER BY created_at DESC LIMIT 5;;
