-- ============================================================
-- Migration: Add 'cancelled' status + extend scouting logs
-- ============================================================

-- 1. Add 'cancelled' to matches status CHECK constraint
--    'cancelled' = permanently blocked pair, never re-matched
ALTER TABLE public.matches
  DROP CONSTRAINT IF EXISTS matches_status_check;
ALTER TABLE public.matches
  ADD CONSTRAINT matches_status_check
  CHECK (status IN ('pending', 'accepted', 'archived', 'unmatched', 'cancelled'));
-- Also add the unmatch columns if not already present (idempotent)
ALTER TABLE public.matches
  ADD COLUMN IF NOT EXISTS unmatch_reason  text,
  ADD COLUMN IF NOT EXISTS unmatched_by    uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS updated_at      timestamptz DEFAULT now();
-- 2. RLS: Allow users to update their own matches (set status = cancelled/unmatched)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'matches' AND policyname = 'Users can update their own matches'
  ) THEN
    CREATE POLICY "Users can update their own matches"
    ON public.matches FOR UPDATE
    USING (auth.uid() = user_a OR auth.uid() = user_b)
    WITH CHECK (auth.uid() = user_a OR auth.uid() = user_b);
  END IF;
END $$;
-- 3. Extend agent_scouting_logs with real match intelligence columns
ALTER TABLE public.agent_scouting_logs
  ADD COLUMN IF NOT EXISTS candidate_id        uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS match_score         float,
  ADD COLUMN IF NOT EXISTS conversation_summary text;
-- 4. Index for filtering high-score scouting entries
CREATE INDEX IF NOT EXISTS idx_scouting_logs_match_score
  ON public.agent_scouting_logs(user_id, match_score DESC)
  WHERE match_score IS NOT NULL;
