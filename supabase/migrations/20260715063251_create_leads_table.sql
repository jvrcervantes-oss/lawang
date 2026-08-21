create table public.leads (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  email text not null,
  source text,
  project text,
  ip text
);

alter table public.leads enable row level security;

create policy "anon can insert leads"
  on public.leads
  for insert
  to anon
  with check (true);
;
