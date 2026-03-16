-- ============================================================
-- Phase 18: New Profiles Columns
-- Run this FIRST in Supabase SQL Editor or via migration.
-- ============================================================

-- relationship_intention: soft-extracted from interview language.
--   Shape: { type: "casual"|"serious"|"open"|"marriage"|"unsure",
--             flexibility: 1|2|3,
--             raw_quote: "verbatim phrase they used" }
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS relationship_intention jsonb;
-- attachment_style: inferred from intimacy_needs / past_experiences language.
--   Shape: { style: "secure"|"anxious"|"avoidant"|"fearful-avoidant",
--             confidence: 0.0–1.0,
--             signals: ["phrase 1", "phrase 2"] }
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS attachment_style jsonb;
-- mutual_influence_score: float 0.0–1.0.
--   High = growth/compromise language. Low = rigid self-sufficiency framing.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS mutual_influence_score float;
-- values_embedding: gemini-embedding-001 on core_beliefs text only.
--   Written by update-dossier after each dossier regeneration.
--   Read by matchmaker for values_alignment sub-score.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS values_embedding vector(3072);
-- vedic_weight_preference: 0=skeptic, 1=neutral (default), 2=believer.
--   Inferred from interview (never asked). Controls Vedic score weight in formula.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS vedic_weight_preference smallint NOT NULL DEFAULT 1;
-- covenant_acknowledged: UX gate before the interview starts.
--   Set to true by iOS when user confirms the pre-interview Covenant screen.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS covenant_acknowledged boolean NOT NULL DEFAULT false;
-- ─── Indexes ──────────────────────────────────────────────────────────────────
-- NOTE: Index for values_embedding (3072 dims) omitted due to 2000-dim limit on HNSW/IVFFlat.
-- Sequential scan is fine for Phase 18 early adoption.

CREATE INDEX IF NOT EXISTS idx_profiles_vedic_pref
  ON public.profiles (vedic_weight_preference);
CREATE INDEX IF NOT EXISTS idx_profiles_covenant
  ON public.profiles (covenant_acknowledged);
