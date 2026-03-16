-- ============================================================
-- Phase 18: agent_positive_signals Table
-- Run AFTER phase18_profiles_columns.sql
-- ============================================================
-- Stores thumbs-up positive signals from match feedback.
-- These are used by the matchmaker to compute a positive boost (up to +10%)
-- and by update-dossier to enrich agent_strategy in the dossier.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.agent_positive_signals (
  id              uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id         uuid        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  label           text        NOT NULL, -- e.g. 'felt_known', 'energy_match', 'values_resonance'
  constraint_type text        NOT NULL DEFAULT 'positive',
  source_match_id uuid        REFERENCES public.matches(id) ON DELETE SET NULL,
  created_at      timestamptz DEFAULT now()
);
-- ─── Indexes ──────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_aps_user_id    ON public.agent_positive_signals (user_id);
CREATE INDEX IF NOT EXISTS idx_aps_label      ON public.agent_positive_signals (label);
CREATE INDEX IF NOT EXISTS idx_aps_created_at ON public.agent_positive_signals (created_at DESC);
-- ─── Row Level Security ───────────────────────────────────────────────────────
ALTER TABLE public.agent_positive_signals ENABLE ROW LEVEL SECURITY;
-- Users can read their own positive signals (e.g. for AgentConfigView display)
CREATE POLICY "Users read own positive signals"
  ON public.agent_positive_signals
  FOR SELECT
  USING (auth.uid() = user_id);
-- Inserts happen via service role (update-agent-weights edge function)
-- No user-facing insert policy needed.;
