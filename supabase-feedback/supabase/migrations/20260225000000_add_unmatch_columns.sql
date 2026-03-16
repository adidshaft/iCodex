-- Migration to add Unmatch reason and triggered by columns to the matches table
ALTER TABLE "public"."matches" 
  ADD COLUMN IF NOT EXISTS "unmatch_reason" text,
  ADD COLUMN IF NOT EXISTS "unmatched_by" uuid REFERENCES "public"."profiles"("id") ON DELETE SET NULL;
