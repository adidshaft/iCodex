-- ============================================================
-- Phase 21: Personalised Match Reasoning
-- Adds per-user notes to the matches table.
--
-- Previously a single match_reasoning was shown to both users.
-- Now the matchmaker generates two notes:
--   match_reasoning_a: addressed to user_a by first name
--   match_reasoning_b: addressed to user_b by first name
--
-- Fallback: if these columns are NULL, the app falls back to the
-- shared match_reasoning column (backwards compat for old rows).
-- ============================================================

ALTER TABLE public.matches
  ADD COLUMN IF NOT EXISTS match_reasoning_a text,
  ADD COLUMN IF NOT EXISTS match_reasoning_b text;
COMMENT ON COLUMN public.matches.match_reasoning_a IS
  'Personalised 3-sentence introduction note addressed to user_a by first name.';
COMMENT ON COLUMN public.matches.match_reasoning_b IS
  'Personalised 3-sentence introduction note addressed to user_b by first name.';
-- Backfill: for existing rows that have match_reasoning, copy it to both columns
-- so old matches also show something meaningful (even if not personalised).
UPDATE public.matches
SET
  match_reasoning_a = match_reasoning,
  match_reasoning_b = match_reasoning
WHERE
  match_reasoning IS NOT NULL
  AND (match_reasoning_a IS NULL OR match_reasoning_b IS NULL);
