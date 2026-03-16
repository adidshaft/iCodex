-- Add voice_dossier column to profiles to store audio interview extracted fields separately.
-- This keeps the raw 9-domain voice data distinct from the synthesized agent_dossier.
ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS voice_dossier jsonb;
