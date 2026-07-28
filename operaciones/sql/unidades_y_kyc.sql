-- Lawang · inventario de unidades (5) y documentación KYC del comprador (6)
-- 28-jul-2026
--
-- Ejecutar en el proyecto Lawang BD:
--   https://supabase.com/dashboard/project/vtulllundrfennhjddhc/sql/new
--
-- Las policies cuelgan de public.es_agente(), igual que contratos y facturas:
-- estar autenticado NO basta, porque el registro de Supabase Auth está abierto.

-- ─────────────────────────────────────────────────────────────
-- 5) UNIDADES — qué hay a la venta y en qué estado
-- ─────────────────────────────────────────────────────────────
-- El objetivo real es no vender dos veces la misma parcela. Por eso el estado
-- es una columna con lista cerrada y no texto libre: "reservada", "Reservada"
-- y "RESERV." serían tres estados distintos para la base de datos y ninguno
-- para una persona.
--
-- El enlace con el contrato vive AQUÍ (unidades.contrato_id) y no al revés:
-- una unidad tiene como mucho un contrato vivo, mientras que un contrato puede
-- tocar varias unidades solo en casos raros que hoy no existen. Si aparecen,
-- esto se convierte en tabla intermedia sin tocar `contratos`.

create table if not exists public.unidades (
  id            uuid primary key default gen_random_uuid(),
  codigo        text not null unique,          -- el que se imprime en el contrato (parcela_codigo / villa_nombre)
  proyecto      text,                          -- Palm Field, Tamarind Rise…
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
comment on column public.unidades.estado is 'disponible | reservada | vendida | bloqueada | no_disponible. Lista cerrada a proposito: evita vender dos veces la misma unidad por una diferencia de mayusculas.';

alter table public.unidades enable row level security;

create policy "agentes autenticados leen unidades"
  on public.unidades for select to authenticated using (public.es_agente());
create policy "agentes autenticados escriben unidades"
  on public.unidades for insert to authenticated with check (public.es_agente());
create policy "agentes autenticados actualizan unidades"
  on public.unidades for update to authenticated using (public.es_agente()) with check (public.es_agente());

-- ─────────────────────────────────────────────────────────────
-- 6) KYC — las tablas YA EXISTEN pero con RLS activa y CERO políticas
-- ─────────────────────────────────────────────────────────────
-- `clients` y `documents` se crearon el 14-jul y quedaron en deny-all: la app
-- no puede leerlas ni escribirlas. Esto las abre a los agentes, nada más.
-- No se toca su esquema: los datos que hay se conservan.

alter table public.clients   enable row level security;
alter table public.documents enable row level security;

create policy "agentes autenticados leen clientes"
  on public.clients for select to authenticated using (public.es_agente());
create policy "agentes autenticados escriben clientes"
  on public.clients for insert to authenticated with check (public.es_agente());
create policy "agentes autenticados actualizan clientes"
  on public.clients for update to authenticated using (public.es_agente()) with check (public.es_agente());

create policy "agentes autenticados leen documentos"
  on public.documents for select to authenticated using (public.es_agente());
create policy "agentes autenticados escriben documentos"
  on public.documents for insert to authenticated with check (public.es_agente());
create policy "agentes autenticados actualizan documentos"
  on public.documents for update to authenticated using (public.es_agente()) with check (public.es_agente());

-- Caducidad: un pasaporte vencido invalida el KYC y hoy no hay dónde anotarlo.
alter table public.documents
  add column if not exists caduca_el date,
  add column if not exists contrato_id uuid references public.contratos(id) on delete set null;

create index if not exists documents_caduca_idx      on public.documents(caduca_el);
create index if not exists documents_contrato_id_idx on public.documents(contrato_id);

comment on column public.documents.caduca_el is
  'Fecha de caducidad del documento (pasaporte, visado). Se avisa desde /operaciones.';

-- ⚠️ PENDIENTE, decision del owner: el bucket de Storage para los ficheros KYC.
-- `documents.storage_path` apunta a un bucket que TODAVIA NO EXISTE. Hay que
-- crearlo PRIVADO y con policy de es_agente(), igual que `contratos-firmados`.
-- Un bucket publico con pasaportes dentro es una fuga de datos personales, no
-- un detalle de configuracion.

-- Comprobación:
-- select tablename, count(*) from pg_policies
--  where tablename in ('unidades','clients','documents') group by tablename;
