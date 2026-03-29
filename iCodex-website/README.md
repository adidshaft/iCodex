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

Edit `src/main.js`:

- `appLinks.ios` for the final App Store listing URL
- `appLinks.dmg` for the DMG download
- `appLinks.appZip` for the direct Mac app zip

Current downloads point at the rolling GitHub release assets under `main-build`.
The website also reads release metadata from `releases/tags/main-build`, so each new
main push that republishes the rolling release shows up on the site without editing
the website again.

## Routes

- `/` landing page
- `/privacy/` privacy policy
- `/support/` support page

## Feedback backend

The support page posts to a shared Supabase project through:

- edge function: `icodex-feedback`
- table: `public.icodex_feedback_submissions`

The iCodex-owned deployment source now lives in:

- `../supabase-feedback/supabase/functions/icodex-feedback/index.ts`
- `../supabase-feedback/supabase/migrations/20260316000100_create_icodex_feedback_submissions.sql`
