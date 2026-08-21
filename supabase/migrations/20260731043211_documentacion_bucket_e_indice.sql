insert into storage.buckets (id, name, public, file_size_limit)
values ('documentacion', 'documentacion', false, 52428800)
on conflict (id) do update set public = false;

create table if not exists public.documentos_proyecto (
  id           uuid primary key default gen_random_uuid(),
  proyecto     text not null,
  categoria    text not null default 'otros',
  titulo       text not null,
  descripcion  text,
  path         text not null unique,
  mime         text,
  bytes        bigint,
  confidencial boolean not null default true,
  creado_en    timestamptz not null default now(),
  creado_por   text default auth.email()
);

create index if not exists documentos_proyecto_proyecto_idx
  on public.documentos_proyecto (proyecto, categoria, creado_en desc);

alter table public.documentos_proyecto
  drop constraint if exists documentos_proyecto_categoria_check;
alter table public.documentos_proyecto
  add constraint documentos_proyecto_categoria_check
  check (categoria in ('precios','planos','legal','comercial','tecnico','fotos','otros'));

alter table public.documentos_proyecto enable row level security;

drop policy if exists "agentes gestionan documentacion" on public.documentos_proyecto;
create policy "agentes gestionan documentacion" on public.documentos_proyecto
  for all to authenticated
  using (public.es_agente()) with check (public.es_agente());

drop policy if exists "documentacion: agentes leen"     on storage.objects;
drop policy if exists "documentacion: agentes escriben" on storage.objects;
drop policy if exists "documentacion: agentes borran"   on storage.objects;

create policy "documentacion: agentes leen" on storage.objects
  for select to authenticated
  using (bucket_id = 'documentacion' and public.es_agente());

create policy "documentacion: agentes escriben" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'documentacion' and public.es_agente());

create policy "documentacion: agentes borran" on storage.objects
  for delete to authenticated
  using (bucket_id = 'documentacion' and public.es_agente());;
