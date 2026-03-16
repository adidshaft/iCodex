-- ============================================================
-- Phase 18: New Matches Audit Columns
-- Run AFTER phase18_profiles_columns.sql
-- ============================================================

-- ─── Behavioral Score Sub-Components ─────────────────────────────────────────

-- intention_multiplier: joint relationship-intention compatibility.
--   1.0 = neutral (either field null). <1.0 = penalty. Range: ~0.75–1.025
ALTER TABLE public.matches
  ADD COLUMN IF NOT EXISTS intention_multiplier float;
-- behavioral_score: composite of attachment + values + mutual_influence.
--   0.40 × attachment_compatibility
-- + 0.35 × values_alignment
-- + 0.25 × mutual_influence_proxy
ALTER TABLE public.matches
  ADD COLUMN IF NOT EXISTS behavioral_score float;
-- attachment_compatibility: compatibility score from the 10-pair attachment matrix.
--   Range: 0.0–1.0, weighted by min(confidence_a, confidence_b).
ALTER TABLE public.matches
  ADD COLUMN IF NOT EXISTS attachment_compatibility float;
-- values_alignment: cosine similarity of values_embedding vectors.
--   Fallback: agent_embedding cosine if either values_embedding is null.
ALTER TABLE public.matches
  ADD COLUMN IF NOT EXISTS values_alignment float;
-- mutual_influence_proxy: 1 - abs(score_a - score_b) on mutual_influence_score.
--   Measures how closely two people's self-determination scores mirror each other.
ALTER TABLE public.matches
  ADD COLUMN IF NOT EXISTS mutual_influence_proxy float;
-- ─── Stress Test (Phase 3 Negotiation) ───────────────────────────────────────
-- Only populated for matches with final_score >= 0.85.

ALTER TABLE public.matches
  ADD COLUMN IF NOT EXISTS friction_score float;
-- 0.0–1.0, how much conflict

ALTER TABLE public.matches
  ADD COLUMN IF NOT EXISTS repair_score float;
-- 0.0–1.0, how well they repaired

ALTER TABLE public.matches
  ADD COLUMN IF NOT EXISTS stress_test_scenario text;
-- scenario key from taxonomy

-- ─── Serendipity Slot (Frequency Anomaly) ────────────────────────────────────
-- Only populated for Wednesday-run anomaly matches (score 0.72–0.79, one spike ≥ 0.92).

ALTER TABLE public.matches
  ADD COLUMN IF NOT EXISTS is_frequency_anomaly boolean NOT NULL DEFAULT false;
ALTER TABLE public.matches
  ADD COLUMN IF NOT EXISTS anomaly_dimension text;
-- e.g. "values_alignment", "lifestyle_sim"

-- ─── Indexes ──────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_matches_behavioral_score
  ON public.matches (behavioral_score);
CREATE INDEX IF NOT EXISTS idx_matches_frequency_anomaly
  ON public.matches (is_frequency_anomaly)
  WHERE is_frequency_anomaly = true;
