-- ============================================================
-- Migration: Apply remaining schema from 20260227000000
-- (previous migration was partially applied / tracker conflict)
-- ============================================================

-- 1. Add 'cancelled' + 'unmatched' to matches status with a clean constraint
--    Drop old constraint first, then recreate including 'cancelled'
ALTER TABLE public.matches
  DROP CONSTRAINT IF EXISTS matches_status_check;
ALTER TABLE public.matches
  ADD CONSTRAINT matches_status_check
  CHECK (status IN ('pending', 'accepted', 'archived', 'unmatched', 'cancelled'));
-- 2. Ensure updated_at column exists
ALTER TABLE public.matches
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();
-- 3. RLS: Allow users to update their own matches (set status = cancelled/unmatched)
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
-- 4. Add real match intelligence columns to scouting logs
ALTER TABLE public.agent_scouting_logs
  ADD COLUMN IF NOT EXISTS candidate_id        uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS match_score         float,
  ADD COLUMN IF NOT EXISTS conversation_summary text;
-- 5. Index for match_score filtering on the scouting feed (≥75%)
CREATE INDEX IF NOT EXISTS idx_scouting_logs_match_score
  ON public.agent_scouting_logs(user_id, match_score DESC)
  WHERE match_score IS NOT NULL;
