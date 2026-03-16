-- Phase 20: Add memory_affinity audit column to matches table.
-- Stores the symmetric average of the two users' Memory Vault affinity scores
-- so we can track how well the Memory Vault contributed to each match.
ALTER TABLE public.matches
    ADD COLUMN IF NOT EXISTS memory_affinity FLOAT;
COMMENT ON COLUMN public.matches.memory_affinity IS
    'Phase 20: Average cosine similarity between each user''s memory vault fingerprint '
    'and the other user''s agent_embedding. NULL when neither user has Memory Vault entries.';
