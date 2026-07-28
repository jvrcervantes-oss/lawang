-- Lawang · unidades (5) + KYC de compradores (6) + bucket privado de documentos
-- 28-jul-2026
--
-- Ejecutar UNA vez en el proyecto Lawang BD:
--   https://supabase.com/dashboard/project/vtulllundrfennhjddhc/sql/new
--
-- Todas las policies cuelgan de public.es_agente(), igual que contratos y
-- facturas: estar autenticado NO basta, porque el registro de Supabase Auth
-- está abierto y cualquiera puede crearse una cuenta.
-- Es idempotente: correrlo dos veces no rompe nada.

-- ═════════════════════════════════════════════════════════════
-- 5) UNIDADES — qué hay a la venta y en qué estado
-- ═════════════════════════════════════════════════════════════
-- El objetivo real es no vender dos veces la misma parcela. Por eso el estado
-- es lista cerrada y no texto libre: "reservada", "Reservada" y "RESERV." son
-- tres estados distintos para la base de datos y uno solo para una persona.
--
-- El enlace con el contrato vive AQUÍ y no al revés: una unidad tiene como
-- mucho un contrato vivo, mientras que un contrato que toque varias unidades es
-- un caso que hoy no existe. Si aparece, esto pasa a tabla intermedia sin tener
-- que tocar `contratos`.

create table if not exists public.unidades (
  id            uuid primary key default gen_random_uuid(),
  codigo        text not null unique,       -- el mismo texto que imprime el contrato
  proyecto      text,
  tipo          text not null default 'parcela',
  superficie_m2 numeric,
  precio        numeric,
  moneda        text default 'EUR',
  estado        text not null default 'disponible',
  contrato_id   uuid references public.contratos(id) on delete set null,
  notas         text,
  created_at    timestamptz not null default now()
);

do $$ begin
  alter table public.unidades add constraint unidades_estado_check
    check (estado in ('disponible','reservada','vendida','bloqueada','no_disponible'));
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.unidades add constraint unidades_tipo_check
    check (tipo in ('parcela','villa','apartamento','local'));
exception when duplicate_object then null; end $$;

create index if not exists unidades_proyecto_idx    on public.unidades(proyecto);
create index if not exists unidades_estado_idx      on public.unidades(estado);
create index if not exists unidades_contrato_id_idx on public.unidades(contrato_id);

comment on table  public.unidades        is 'Inventario vendible. `codigo` es el mismo texto que imprime el contrato.';
comment on column public.unidades.estado is 'disponible | reservada | vendida | bloqueada | no_disponible. Lista cerrada: evita vender dos veces la misma unidad por una diferencia de mayusculas.';

alter table public.unidades enable row level security;

drop policy if exists "agentes leen unidades"       on public.unidades;
drop policy if exists "agentes crean unidades"      on public.unidades;
drop policy if exists "agentes actualizan unidades" on public.unidades;
create policy "agentes leen unidades"       on public.unidades for select to authenticated using (public.es_agente());
create policy "agentes crean unidades"      on public.unidades for insert to authenticated with check (public.es_agente());
create policy "agentes actualizan unidades" on public.unidades for update to authenticated using (public.es_agente()) with check (public.es_agente());

-- ═════════════════════════════════════════════════════════════
-- 6) KYC — `clients` y `documents` existen desde el 14-jul con RLS
--    activa y CERO políticas: en deny-all. Ninguna app puede leerlas.
--    Esto las abre a los agentes. No se toca su esquema; los datos se conservan.
-- ═════════════════════════════════════════════════════════════
alter table public.clients   enable row level security;
alter table public.documents enable row level security;

drop policy if exists "agentes leen clientes"        on public.clients;
drop policy if exists "agentes crean clientes"       on public.clients;
drop policy if exists "agentes actualizan clientes"  on public.clients;
create policy "agentes leen clientes"       on public.clients for select to authenticated using (public.es_agente());
create policy "agentes crean clientes"      on public.clients for insert to authenticated with check (public.es_agente());
create policy "agentes actualizan clientes" on public.clients for update to authenticated using (public.es_agente()) with check (public.es_agente());

drop policy if exists "agentes leen documentos"       on public.documents;
drop policy if exists "agentes crean documentos"      on public.documents;
drop policy if exists "agentes actualizan documentos" on public.documents;
create policy "agentes leen documentos"       on public.documents for select to authenticated using (public.es_agente());
create policy "agentes crean documentos"      on public.documents for insert to authenticated with check (public.es_agente());
create policy "agentes actualizan documentos" on public.documents for update to authenticated using (public.es_agente()) with check (public.es_agente());

-- Un pasaporte vencido invalida el KYC y hoy no hay dónde anotarlo.
alter table public.documents
  add column if not exists caduca_el   date,
  add column if not exists contrato_id uuid references public.contratos(id) on delete set null;

create index if not exists documents_caduca_idx      on public.documents(caduca_el);
create index if not exists documents_contrato_id_idx on public.documents(contrato_id);

comment on column public.documents.caduca_el is
  'Caducidad del documento (pasaporte, visado). Se avisa desde /operaciones.';

-- ═════════════════════════════════════════════════════════════
-- BUCKET de los ficheros KYC — PRIVADO
-- ═════════════════════════════════════════════════════════════
-- `documents.storage_path` apuntaba a un bucket que no existía. Se crea aquí
-- con public=false: un bucket publico con pasaportes dentro no es un detalle de
-- configuracion, es una fuga de datos personales. Mismo criterio que
-- `contratos-firmados`.
insert into storage.buckets (id, name, public)
values ('kyc', 'kyc', false)
on conflict (id) do update set public = false;   -- si ya existia publico, lo cierra

drop policy if exists "agentes leen kyc"        on storage.objects;
drop policy if exists "agentes suben kyc"       on storage.objects;
drop policy if exists "agentes actualizan kyc"  on storage.objects;
drop policy if exists "agentes borran kyc"      on storage.objects;
create policy "agentes leen kyc"       on storage.objects for select to authenticated using      (bucket_id = 'kyc' and public.es_agente());
create policy "agentes suben kyc"      on storage.objects for insert to authenticated with check (bucket_id = 'kyc' and public.es_agente());
create policy "agentes actualizan kyc" on storage.objects for update to authenticated using      (bucket_id = 'kyc' and public.es_agente());
create policy "agentes borran kyc"     on storage.objects for delete to authenticated using      (bucket_id = 'kyc' and public.es_agente());

-- ═════════════════════════════════════════════════════════════
-- COMPROBACIÓN — debe devolver 3 / 3 / 3 / 4 y publico=false
-- ═════════════════════════════════════════════════════════════
select
  (select count(*) from pg_policies where tablename='unidades')  as pol_unidades,
  (select count(*) from pg_policies where tablename='clients')   as pol_clients,
  (select count(*) from pg_policies where tablename='documents') as pol_documents,
  (select count(*) from pg_policies where tablename='objects' and schemaname='storage' and policyname like '%kyc%') as pol_bucket,
  (select public from storage.buckets where id='kyc') as bucket_publico;
