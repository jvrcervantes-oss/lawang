create table public.contrato_documentos (
  id uuid primary key default gen_random_uuid(),
  contrato_id uuid not null references public.contratos(id),
  doc_type text not null default 'signed_contract',
  storage_path text not null,
  matched_by text not null check (matched_by in ('numero_exacto','nombre_exacto','nombre_confirmado_usuario')),
  uploaded_at timestamptz not null default now()
);

alter table public.contrato_documentos enable row level security;

insert into storage.buckets (id, name, public)
values ('contratos-firmados', 'contratos-firmados', false);;
