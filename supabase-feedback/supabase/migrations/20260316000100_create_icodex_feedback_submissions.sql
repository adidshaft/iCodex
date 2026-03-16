create table if not exists public.icodex_feedback_submissions (
    id uuid primary key default gen_random_uuid(),
    created_at timestamptz not null default now(),
    category text not null check (category in ('support', 'feedback', 'feature')),
    name text,
    email text,
    message text not null,
    page_context text,
    source text not null default 'icodex-website',
    status text not null default 'new' check (status in ('new', 'reviewed', 'closed')),
    user_agent text,
    metadata jsonb not null default '{}'::jsonb
);

create index if not exists icodex_feedback_submissions_created_at_idx
    on public.icodex_feedback_submissions (created_at desc);

create index if not exists icodex_feedback_submissions_category_idx
    on public.icodex_feedback_submissions (category);

alter table public.icodex_feedback_submissions enable row level security;

drop policy if exists "service role manages icodex feedback submissions"
    on public.icodex_feedback_submissions;

create policy "service role manages icodex feedback submissions"
    on public.icodex_feedback_submissions
    for all
    using (auth.role() = 'service_role')
    with check (auth.role() = 'service_role');
