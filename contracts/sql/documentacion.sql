-- ============================================================================
-- Documentación de proyectos — bucket privado + índice
-- 31-jul-2026
-- ----------------------------------------------------------------------------
-- POR QUÉ NO VA EN EL REPO. El owner dejó la documentación en
-- `intranet/Documentacion/`, dentro del árbol que se despliega. Ese árbol lo
-- sirve Hostinger con 200 para CUALQUIER fichero (comprobado), `guard.js` solo
-- tapa páginas HTML, y encima el repo `jvrcervantes-oss/lawang` es PÚBLICO: un
-- PDF de precios por parcela habría quedado descargable por cualquiera y para
-- siempre en el historial de GitHub.
-- Su sitio es un bucket privado servido con URL firmada que caduca, igual que
-- `contratos-firmados` y `kyc`, que ya funcionan así y tienen la RLS cerrada.
--
-- El fichero vive en Storage; la FILA de esta tabla es el índice (qué es, de qué
-- proyecto, quién lo subió). Separado a propósito: `storage.objects` no admite
-- columnas propias y filtrar por convención de nombre de fichero es la clase de
-- lista a mano que se rompe al primer fichero con guion de más.
-- ============================================================================

-- ---- bucket privado -------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit)
values ('documentacion', 'documentacion', false, 52428800)   -- 50 MB por fichero
on conflict (id) do update set public = false;

-- ---- índice ---------------------------------------------------------------
create table if not exists public.documentos_proyecto (
  id           uuid primary key default gen_random_uuid(),
  proyecto     text not null,            -- mismo nombre que en los contratos
  categoria    text not null default 'otros',
  titulo       text not null,
  descripcion  text,
  path         text not null unique,     -- ruta dentro del bucket
  mime         text,
  bytes        bigint,
  -- Confidencial por defecto. Un precio por parcela, un plano o un BOQ no son
  -- material de marketing, y el que decide lo contrario debe hacerlo a mano.
  confidencial boolean not null default true,
  creado_en    timestamptz not null default now(),
  creado_por   text default auth.email()
);

create index if not exists documentos_proyecto_proyecto_idx
  on public.documentos_proyecto (proyecto, categoria, creado_en desc);

-- Categorías cerradas: una lista libre acaba con "planos", "Planos" y "plano"
-- como tres cosas distintas y el filtro deja de servir.
alter table public.documentos_proyecto
  drop constraint if exists documentos_proyecto_categoria_check;
alter table public.documentos_proyecto
  add constraint documentos_proyecto_categoria_check
  check (categoria in ('precios','planos','legal','comercial','tecnico','fotos','otros'));

-- ---- RLS: lo mismo que el resto de la suite --------------------------------
-- `es_agente()` lee el claim `agente` de app_metadata del JWT. Registrarse en
-- Supabase Auth NO basta: el flag lo pone un admin. Ver rls_claim_agente.sql.
alter table public.documentos_proyecto enable row level security;

drop policy if exists "agentes gestionan documentacion" on public.documentos_proyecto;
create policy "agentes gestionan documentacion" on public.documentos_proyecto
  for all to authenticated
  using (public.es_agente()) with check (public.es_agente());

-- ---- RLS del bucket --------------------------------------------------------
-- El fichero se protege aquí, no en la app: la app enseña lo que la RLS deja
-- leer. Sin esto, la URL del objeto sería adivinable por cualquier autenticado.
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
  using (bucket_id = 'documentacion' and public.es_agente());
