-- Phase 22: Match Stacking — efficient index for nightly-reveal-selector
-- Matches with reveal_at IS NULL are "queued candidates" waiting to be activated.
-- The nightly-reveal-selector edge function runs at 23:11 UTC and picks the
-- highest-scored unrevealed match for each user who has no reveal in the last 24h.

-- Index for efficient lookup of unrevealed pending matches (sorted by score DESC)
CREATE INDEX IF NOT EXISTS idx_matches_unrevealed
  ON matches(final_score DESC)
  WHERE status = 'pending' AND reveal_at IS NULL;
-- pg_cron job: fire nightly-reveal-selector at 23:11 UTC every day
-- Prerequisites:
--   1. pg_cron extension enabled  (Supabase dashboard → Database → Extensions)
--   2. pg_net  extension enabled  (same)
--   3. app.admin_secret GUC set   (ALTER DATABASE postgres SET "app.admin_secret" = '...')
SELECT cron.schedule(
  'nightly-reveal-selector',
  '11 23 * * *',
  $$
  SELECT net.http_post(
    url     := 'https://femzgnhpgkxktbwsnrfq.supabase.co/functions/v1/nightly-reveal-selector',
    headers := format(
                 '{"x-admin-secret": "%s", "Content-Type": "application/json"}',
                 current_setting('app.admin_secret', true)
               )::jsonb,
    body    := '{}'::jsonb
  ) AS request_id;
  $$
);
