-- Phase 18: Add questions_asked array column to interview_metadata for anti-repetition tracking
ALTER TABLE public.interview_metadata
    ADD COLUMN IF NOT EXISTS questions_asked TEXT[] NOT NULL DEFAULT '{}';
COMMENT ON COLUMN public.interview_metadata.questions_asked IS 'Array of the last 5 questions asked (verbatim) to prevent near-identical rephrasing and enable anti-repetition logic.';
