-- Migration to allow users to update their own matches (accept, archive, unmatch)
-- Without this policy, any client-side update to the matches table fails due to RLS.

ALTER TABLE public.matches ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE tablename = 'matches' AND policyname = 'Users can update their own matches'
    ) THEN
        CREATE POLICY "Users can update their own matches"
        ON public.matches FOR UPDATE
        USING (auth.uid() = user_a OR auth.uid() = user_b)
        WITH CHECK (auth.uid() = user_a OR auth.uid() = user_b);
    END IF;
END
$$;
