# iCodex Website

Static Vite landing page for iCodex.

## Local development

```bash
npm install
npm run dev -- --host
```

Copy `.env.example` to `.env` and fill in:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`

## Build

```bash
npm run build
```

## Update links

Edit `/Users/amanpandey/Desktop/iCodex/iCodex-website/src/main.js`:

- `appLinks.ios` for the final App Store listing URL
- `appLinks.dmg` for the DMG download
- `appLinks.appZip` for the direct Mac app zip

Current downloads already point at the local files in `public/downloads/`.

## Routes

- `/` landing page
- `/privacy/` privacy policy
- `/support/` support page

## Feedback backend

The support page posts to a shared Supabase project through:

- edge function: `icodex-feedback`
- table: `public.icodex_feedback_submissions`

The iCodex-owned deployment source now lives in:

- `/Users/amanpandey/Desktop/iCodex/supabase-feedback/supabase/functions/icodex-feedback/index.ts`
- `/Users/amanpandey/Desktop/iCodex/supabase-feedback/supabase/migrations/20260316000100_create_icodex_feedback_submissions.sql`
