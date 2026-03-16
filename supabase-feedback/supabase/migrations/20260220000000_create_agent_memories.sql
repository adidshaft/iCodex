-- Phase 14: Memory Vault
-- Creates agent_memories table with pgvector support and a cosine similarity RPC.
-- Note: IVFFlat/HNSW indexes are limited to 2000 dims in pgvector.
-- At this app's scale (user_id filter → small row set), a sequential scan is sufficient.

-- 1. Create the table
CREATE TABLE IF NOT EXISTS public.agent_memories (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    memory_text TEXT        NOT NULL,
    embedding   vector(3072),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- 2. Enable RLS
ALTER TABLE public.agent_memories ENABLE ROW LEVEL SECURITY;
-- 3. RLS Policies
CREATE POLICY "Users can read own memories"
    ON public.agent_memories
    FOR SELECT
    TO authenticated
    USING (auth.uid() = user_id);
CREATE POLICY "Service role can insert memories"
    ON public.agent_memories
    FOR INSERT
    TO service_role
    WITH CHECK (true);
-- 4. B-tree index on user_id to narrow scans per user (the vector scan sees only this user's rows)
CREATE INDEX IF NOT EXISTS agent_memories_user_id_idx
    ON public.agent_memories (user_id);
-- 5. RPC: match_memories
-- Returns the top-k memories for a given user ordered by cosine similarity.
-- similarity = 1.0 means identical vectors; 0.0 means orthogonal.
CREATE OR REPLACE FUNCTION public.match_memories(
    query_embedding   vector(3072),
    match_count       INT,
    user_identifier   UUID
)
RETURNS TABLE (
    id          UUID,
    memory_text TEXT,
    similarity  FLOAT
)
LANGUAGE sql STABLE
AS $$
    SELECT
        am.id,
        am.memory_text,
        1 - (am.embedding <=> query_embedding) AS similarity
    FROM public.agent_memories am
    WHERE am.user_id = user_identifier
      AND am.embedding IS NOT NULL
    ORDER BY am.embedding <=> query_embedding
    LIMIT match_count;
$$;
