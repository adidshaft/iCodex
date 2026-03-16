# iCodex Feedback Supabase Ops

This folder keeps the iCodex website feedback backend separate from other repos,
while still allowing deployment to the same Supabase project.

## What lives here

- `supabase/functions/icodex-feedback/index.ts`
  Browser-safe edge function that accepts support, feedback, and feature requests.
- `supabase/migrations/20260316000100_create_icodex_feedback_submissions.sql`
  Table and policy for storing feedback submissions.
- `supabase/config.toml`
  Minimal local Supabase function config for this iCodex-specific deployment unit.

## Deploy to the shared Supabase project

Link this folder to the same Supabase project used elsewhere, then run:

```bash
supabase db push
supabase functions deploy icodex-feedback --no-verify-jwt
```

The website itself only needs:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`

Those public values can point at the shared Supabase project even though this
deployment source lives in the iCodex repo.
