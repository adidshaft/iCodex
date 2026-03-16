-- ============================================================
-- Phase 20: Vedic birth details, age preference, zodiac columns
-- ============================================================

-- vedic_birth_details: copied from voice_dossier.vedic_astrology_details at graduation.
--   Stores user's birth data (DOB, TOB, POB) as a text string or JSON object.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS vedic_birth_details JSONB DEFAULT NULL;
-- age_preference_center: the age this user prefers in a partner (integer, e.g. 28).
--   Soft-extracted from interview language ("I prefer someone around my age", etc.)
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS age_preference_center INT DEFAULT NULL;
-- age_preference_flexibility: how many years +/- they're flexible on (e.g. 5 = ±5 years).
--   Default NULL = no strong preference detected.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS age_preference_flexibility INT DEFAULT NULL;
-- ─── Indexes ──────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_profiles_age_pref_center
  ON public.profiles (age_preference_center)
  WHERE age_preference_center IS NOT NULL;
