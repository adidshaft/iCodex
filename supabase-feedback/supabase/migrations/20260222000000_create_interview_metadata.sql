-- Phase 17: interview_metadata table for hold-to-speak interview system

CREATE TABLE IF NOT EXISTS public.interview_metadata (
    id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id               UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Session tracking
    session_count         INT         NOT NULL DEFAULT 0,
    total_questions_asked INT         NOT NULL DEFAULT 0,
    last_skipped_topic    TEXT,
    skipped_topics        TEXT[]      NOT NULL DEFAULT '{}',

    -- Intimacy progression
    intimacy_level        INT         NOT NULL DEFAULT 0, -- 0=basic only, 1=mixed, 2=deep
    topics_covered        TEXT[]      NOT NULL DEFAULT '{}',

    -- Conversation context (last 3-5 turns for adaptive logic)
    last_user_response    TEXT,
    last_ai_question      TEXT,
    conversation_summary  TEXT,

    -- Graduation status
    is_graduated          BOOLEAN     NOT NULL DEFAULT FALSE,
    graduation_reason     TEXT,       -- "all_fields_filled", "user_requested_skip", etc.

    UNIQUE(user_id)
);
-- Enable RLS
ALTER TABLE public.interview_metadata ENABLE ROW LEVEL SECURITY;
-- Users can read their own metadata
CREATE POLICY "Users can read own interview_metadata"
    ON public.interview_metadata
    FOR SELECT
    TO authenticated
    USING (auth.uid() = user_id);
-- Index for fast lookup by user_id
CREATE INDEX IF NOT EXISTS idx_interview_metadata_user_id
    ON public.interview_metadata(user_id);
-- Auto-update updated_at trigger
CREATE OR REPLACE FUNCTION public.update_interview_metadata_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER interview_metadata_updated_at
    BEFORE UPDATE ON public.interview_metadata
    FOR EACH ROW
    EXECUTE FUNCTION public.update_interview_metadata_updated_at();
