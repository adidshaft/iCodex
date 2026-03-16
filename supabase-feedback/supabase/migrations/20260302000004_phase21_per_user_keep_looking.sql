-- ============================================================
-- Phase 21b: Per-user "Keep Looking" flags
--
-- Instead of mutating the shared match status to 'pending_later'
-- (which would also remove the match from the other user's view),
-- we add per-user boolean flags. When user_a taps "Keep Looking",
-- only user_a_keep_looking = true is set — user_b still sees the
-- reveal screen normally and their status is unaffected.
--
-- The iOS app now:
--   1. Sets the current user's keep_looking flag = true (PATCH)
--   2. Locally hides the match (pendingLaterMatches)
--   3. fetchPendingMatch excludes rows where the current user's flag is true
-- ============================================================

ALTER TABLE public.matches
  ADD COLUMN IF NOT EXISTS user_a_keep_looking boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS user_b_keep_looking boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN public.matches.user_a_keep_looking IS
  'True when user_a tapped Keep Looking — hides match from user_a reveal only.';
COMMENT ON COLUMN public.matches.user_b_keep_looking IS
  'True when user_b tapped Keep Looking — hides match from user_b reveal only.';
-- Migrate existing pending_later rows: set both flags so old behaviour is preserved
UPDATE public.matches
SET
  user_a_keep_looking = true,
  user_b_keep_looking = true
WHERE status = 'pending_later';
-- RPC: user_keep_looking(p_match_id, p_user_id)
-- Sets the calling user's keep_looking flag without touching the other user's state.
CREATE OR REPLACE FUNCTION public.user_keep_looking(p_match_id uuid, p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
    v_match record;
BEGIN
    SELECT * INTO v_match
    FROM public.matches
    WHERE id = p_match_id
      AND (user_a = p_user_id OR user_b = p_user_id)
      AND status IN ('pending', 'pending_later');

    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Match not found');
    END IF;

    IF v_match.user_a = p_user_id THEN
        UPDATE public.matches
        SET user_a_keep_looking = true, updated_at = now()
        WHERE id = p_match_id;
    ELSE
        UPDATE public.matches
        SET user_b_keep_looking = true, updated_at = now()
        WHERE id = p_match_id;
    END IF;

    RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.user_keep_looking(uuid, uuid) TO authenticated;
