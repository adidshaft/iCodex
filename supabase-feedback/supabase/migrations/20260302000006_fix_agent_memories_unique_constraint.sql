-- Fix: agent_memories unique constraint blocked all user-authored memories after the first.
--
-- The original UNIQUE NULLS NOT DISTINCT (user_id, source_match_id, source) constraint
-- treated NULL source_match_id values as equal, meaning every user memory
-- (source='user', source_match_id=NULL) conflicted with the next one.
--
-- Replaced with a partial unique index scoped only to agent_reflection rows
-- where source_match_id is non-NULL — the original intent was just to deduplicate
-- auto-reflections per match, not to limit user-typed memories.

ALTER TABLE agent_memories
  DROP CONSTRAINT IF EXISTS uq_agent_memories_reflection;
CREATE UNIQUE INDEX IF NOT EXISTS uq_agent_memories_reflection
  ON agent_memories (user_id, source_match_id)
  WHERE source = 'agent_reflection' AND source_match_id IS NOT NULL;
