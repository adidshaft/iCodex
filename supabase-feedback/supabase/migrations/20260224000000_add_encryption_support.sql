-- Phase 19: Add encryption support for audio and transcripts
-- Enables E2E encryption for interview data at rest

-- Flag interview_metadata to support encryption
ALTER TABLE public.interview_metadata
    ADD COLUMN IF NOT EXISTS encryption_enabled BOOLEAN NOT NULL DEFAULT true;
-- Flag interview_transcripts to indicate encrypted transcripts
ALTER TABLE public.interview_transcripts
    ADD COLUMN IF NOT EXISTS is_encrypted BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS encrypted_user_answer TEXT;
-- Create index on encryption flags for efficient filtering
CREATE INDEX IF NOT EXISTS idx_interview_transcripts_encrypted
    ON public.interview_transcripts(is_encrypted);
COMMENT ON COLUMN public.interview_metadata.encryption_enabled IS 'If true, all audio and transcripts for this user are E2E encrypted';
COMMENT ON COLUMN public.interview_transcripts.is_encrypted IS 'If true, encrypted_user_answer contains the AES-256-GCM ciphertext; if false, user_answer_text is plaintext';
COMMENT ON COLUMN public.interview_transcripts.encrypted_user_answer IS 'Hex-encoded AES-256-GCM ciphertext of user answer (nonce + ciphertext)';
