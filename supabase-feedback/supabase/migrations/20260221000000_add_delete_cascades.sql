-- Phase 16: Account Deletion — Foreign Key Cascade & Set-Null Setup
-- ─────────────────────────────────────────────────────────────────────────────
-- ON DELETE CASCADE  → personal user data (profiles, matches, messages, logs, memories)
-- ON DELETE SET NULL → ML training data (interview_transcripts, model_training_logs)
--                      Row is preserved, user reference is anonymized to NULL.
-- ─────────────────────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────────────────────
-- Helper: Drop all FK constraints on a given table.column by querying the
-- information_schema (works regardless of what the constraint was named).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION pg_temp.drop_fk_by_column(p_table TEXT, p_column TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT tc.constraint_name
        FROM   information_schema.table_constraints   tc
        JOIN   information_schema.key_column_usage    kcu
               ON  tc.constraint_name = kcu.constraint_name
               AND tc.table_schema    = kcu.table_schema
        WHERE  tc.table_schema    = 'public'
          AND  tc.table_name      = p_table
          AND  kcu.column_name    = p_column
          AND  tc.constraint_type = 'FOREIGN KEY'
    LOOP
        EXECUTE format(
            'ALTER TABLE public.%I DROP CONSTRAINT %I',
            p_table, r.constraint_name
        );
        RAISE NOTICE 'Dropped FK % on public.%.%',
            r.constraint_name, p_table, p_column;
    END LOOP;
END;
$$;
-- ─────────────────────────────────────────────────────────────────────────────
-- 1. profiles.id → auth.users(id)  ON DELETE CASCADE
--    When a Supabase Auth user is deleted, their profile row is deleted too.
--    Everything else cascades from this root deletion.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT pg_temp.drop_fk_by_column('profiles', 'id');
ALTER TABLE public.profiles
    ADD CONSTRAINT profiles_id_fkey
    FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
-- ─────────────────────────────────────────────────────────────────────────────
-- 2. matches.user_a / user_b → profiles(id)  ON DELETE CASCADE
--    A match is deleted if either participant's profile is deleted.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT pg_temp.drop_fk_by_column('matches', 'user_a');
ALTER TABLE public.matches
    ADD CONSTRAINT matches_user_a_fkey
    FOREIGN KEY (user_a) REFERENCES public.profiles(id) ON DELETE CASCADE;
SELECT pg_temp.drop_fk_by_column('matches', 'user_b');
ALTER TABLE public.matches
    ADD CONSTRAINT matches_user_b_fkey
    FOREIGN KEY (user_b) REFERENCES public.profiles(id) ON DELETE CASCADE;
-- ─────────────────────────────────────────────────────────────────────────────
-- 3. messages.match_id → matches(id)  ON DELETE CASCADE
--    messages.sender_id → profiles(id)  ON DELETE CASCADE
--    Messages are deleted when their match or sender's profile is deleted.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT pg_temp.drop_fk_by_column('messages', 'match_id');
ALTER TABLE public.messages
    ADD CONSTRAINT messages_match_id_fkey
    FOREIGN KEY (match_id) REFERENCES public.matches(id) ON DELETE CASCADE;
SELECT pg_temp.drop_fk_by_column('messages', 'sender_id');
ALTER TABLE public.messages
    ADD CONSTRAINT messages_sender_id_fkey
    FOREIGN KEY (sender_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
-- ─────────────────────────────────────────────────────────────────────────────
-- 4. agent_scouting_logs.user_id → profiles(id)  ON DELETE CASCADE
-- ─────────────────────────────────────────────────────────────────────────────
SELECT pg_temp.drop_fk_by_column('agent_scouting_logs', 'user_id');
ALTER TABLE public.agent_scouting_logs
    ADD CONSTRAINT agent_scouting_logs_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
-- ─────────────────────────────────────────────────────────────────────────────
-- 5. agent_constraints.user_id → profiles(id)  ON DELETE CASCADE
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'agent_constraints'
    ) THEN
        PERFORM pg_temp.drop_fk_by_column('agent_constraints', 'user_id');
        ALTER TABLE public.agent_constraints
            ADD CONSTRAINT agent_constraints_user_id_fkey
            FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
    END IF;
END $$;
-- ─────────────────────────────────────────────────────────────────────────────
-- 6. agent_memories.user_id  — already CASCADE from Phase 14 migration.
--    No change needed; listed here for audit completeness.
-- ─────────────────────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. interview_transcripts.user_id → profiles(id)  ON DELETE SET NULL
--    CRITICAL: ML training data must be preserved. The row survives;
--    user_id is set to NULL so the record is fully anonymized.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT pg_temp.drop_fk_by_column('interview_transcripts', 'user_id');
-- Column was originally NOT NULL; make it nullable to allow SET NULL semantics.
ALTER TABLE public.interview_transcripts
    ALTER COLUMN user_id DROP NOT NULL;
ALTER TABLE public.interview_transcripts
    ADD CONSTRAINT interview_transcripts_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE SET NULL;
-- ─────────────────────────────────────────────────────────────────────────────
-- 8. model_training_logs — ON DELETE SET NULL on all user reference columns.
--    CRITICAL: Proprietary ML dataset. Rows are never deleted.
--    Supports user_a / user_b column layout (matching matches table schema)
--    and a single user_id column layout as a fallback.
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'model_training_logs'
    ) THEN
        RAISE NOTICE 'model_training_logs does not exist — skipping FK update';
        RETURN;
    END IF;

    -- user_a column
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name   = 'model_training_logs'
          AND column_name  = 'user_a'
    ) THEN
        PERFORM pg_temp.drop_fk_by_column('model_training_logs', 'user_a');
        ALTER TABLE public.model_training_logs ALTER COLUMN user_a DROP NOT NULL;
        ALTER TABLE public.model_training_logs
            ADD CONSTRAINT model_training_logs_user_a_fkey
            FOREIGN KEY (user_a) REFERENCES public.profiles(id) ON DELETE SET NULL;
    END IF;

    -- user_b column
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name   = 'model_training_logs'
          AND column_name  = 'user_b'
    ) THEN
        PERFORM pg_temp.drop_fk_by_column('model_training_logs', 'user_b');
        ALTER TABLE public.model_training_logs ALTER COLUMN user_b DROP NOT NULL;
        ALTER TABLE public.model_training_logs
            ADD CONSTRAINT model_training_logs_user_b_fkey
            FOREIGN KEY (user_b) REFERENCES public.profiles(id) ON DELETE SET NULL;
    END IF;

    -- user_id column (alternative single-user schema)
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name   = 'model_training_logs'
          AND column_name  = 'user_id'
    ) THEN
        PERFORM pg_temp.drop_fk_by_column('model_training_logs', 'user_id');
        ALTER TABLE public.model_training_logs ALTER COLUMN user_id DROP NOT NULL;
        ALTER TABLE public.model_training_logs
            ADD CONSTRAINT model_training_logs_user_id_fkey
            FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE SET NULL;
    END IF;
END $$;
