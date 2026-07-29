-- APLICADO en producción el 29-jul-2026 por MCP (migraciones
-- `usuarios_y_permisos_tabla`, `usuarios_funciones_permisos`,
-- `es_suyo_nunca_null`, `rls_propiedad_contratos_facturas`).
-- Registro, no hace falta volver a correrlo.
--
-- ============================================================
-- USUARIOS Y PERMISOS DE LA SUITE INTERNA
-- ============================================================
-- Antes: un único flag `app_metadata.agente` (todo o nada) que solo se tocaba
-- desde el dashboard de Supabase, y cualquier agente podía editar el documento
-- de cualquier otro.
-- Ahora: ficha por usuario (rol + herramientas) gestionable desde /usuarios/,
-- y los documentos los edita quien los creó (o un admin).
--
-- COMPATIBILIDAD, y por qué existe: un usuario SIN fila en `public.usuarios`
-- (por ejemplo creado a mano en el dashboard) conserva el comportamiento
-- antiguo — permiso completo si tiene el flag legacy. Sin esa rama, cualquier
-- cuenta creada fuera del panel se quedaría muda sin que nadie entienda por qué.

create table public.usuarios (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  nombre text,
  rol text not null default 'agente' check (rol in ('super_admin','admin','agente')),
  herramientas text[] not null default '{}',
  activo boolean not null default true,
  creado_en timestamptz not null default now(),
  creado_por text default auth.email()
);
alter table public.usuarios enable row level security;

-- Alta de los usuarios existentes preservando el statu quo: quien tenía el flag
-- entra activo; quien no lo tenía (y hoy no ve nada) entra DESACTIVADO.
insert into public.usuarios (user_id, email, rol, herramientas, activo, creado_por)
select u.id, u.email,
       case when u.email = 'jvr.cervantes@gmail.com' then 'super_admin' else 'agente' end,
       array['contratos','facturas','operaciones','unidades','compradores','dossier'],
       coalesce((u.raw_app_meta_data ->> 'agente')::boolean, false),
       'migracion 29-jul-2026'
from auth.users u;
update public.usuarios set herramientas = herramientas || array['usuarios'] where rol = 'super_admin';

-- ── Funciones ────────────────────────────────────────────────────────────
-- SECURITY DEFINER es OBLIGATORIO en todas: sin él, consultar `usuarios` desde
-- una policy dispara la RLS de `usuarios`, que a su vez llama a estas funciones
-- → recursión infinita.
create or replace function public.es_agente()
returns boolean language sql stable security definer set search_path = '' as $$
  select case
    when exists (select 1 from public.usuarios u where u.user_id = (select auth.uid()))
      then exists (select 1 from public.usuarios u where u.user_id = (select auth.uid()) and u.activo)
    else coalesce(((select auth.jwt()) -> 'app_metadata' ->> 'agente')::boolean, false)
  end
$$;

create or replace function public.es_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.usuarios u
                  where u.user_id = (select auth.uid()) and u.activo
                    and u.rol in ('super_admin','admin'))
$$;

create or replace function public.puede(herramienta text)
returns boolean language sql stable security definer set search_path = '' as $$
  select case
    when public.es_admin() then true
    when exists (select 1 from public.usuarios u where u.user_id = (select auth.uid()))
      then exists (select 1 from public.usuarios u
                    where u.user_id = (select auth.uid()) and u.activo
                      and herramienta = any(u.herramientas))
    else coalesce(((select auth.jwt()) -> 'app_metadata' ->> 'agente')::boolean, false)
  end
$$;

-- El coalesce final no es adorno: `autor = auth.email()` devuelve NULL sin
-- sesión, y `false or NULL` = NULL. En RLS un NULL deniega igual, pero un
-- predicado que devuelve NULL es una trampa para quien lo reutilice fuera.
create or replace function public.es_suyo(autor text)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(autor is null or autor = (select auth.email()) or public.es_admin(), false)
$$;

-- ── RLS de la propia tabla ───────────────────────────────────────────────
create policy "cada uno lee su ficha, el admin todas" on public.usuarios
  for select to authenticated using (user_id = (select auth.uid()) or public.es_admin());
create policy "solo admin crea usuarios" on public.usuarios
  for insert to authenticated with check (public.es_admin());
create policy "solo admin edita usuarios" on public.usuarios
  for update to authenticated using (public.es_admin()) with check (public.es_admin());

-- ── Propiedad del documento ──────────────────────────────────────────────
-- Las filas con creado_por NULL (anteriores al 27-jul, cuando se añadió la
-- columna) siguen siendo editables por cualquier agente: nadie las creó a
-- efectos de la base, y bloquearlas dejaría 15 contratos vivos intocables.
-- Las LECTURAS se quedan en es_agente() a propósito: Operaciones cruza
-- contratos + facturas + firmas, y filtrar lecturas por herramienta la dejaría
-- en blanco para quien solo tuviera 'operaciones'.
drop policy if exists "agentes autenticados actualizan contratos no bloqueados" on public.contratos;
create policy "el autor o un admin editan contratos no bloqueados" on public.contratos
  for update to authenticated
  using (bloqueado = false and public.es_agente() and public.puede('contratos') and public.es_suyo(creado_por))
  with check (public.es_agente() and public.puede('contratos'));

drop policy if exists "agentes autenticados insertan contratos" on public.contratos;
create policy "agentes con la herramienta insertan contratos" on public.contratos
  for insert to authenticated with check (public.es_agente() and public.puede('contratos'));

drop policy if exists "agentes autenticados actualizan facturas no anuladas" on public.facturas;
create policy "el autor o un admin editan facturas no anuladas" on public.facturas
  for update to authenticated
  using (anulada = false and public.es_agente() and public.puede('facturas') and public.es_suyo(creado_por))
  with check (public.es_agente() and public.puede('facturas'));

drop policy if exists "agentes autenticados insertan facturas" on public.facturas;
create policy "agentes con la herramienta insertan facturas" on public.facturas
  for insert to authenticated with check (public.es_agente() and public.puede('facturas'));

drop policy if exists "agentes actualizan unidades" on public.unidades;
create policy "agentes con la herramienta actualizan unidades" on public.unidades
  for update to authenticated using (public.es_agente() and public.puede('unidades'))
  with check (public.es_agente() and public.puede('unidades'));
drop policy if exists "agentes crean unidades" on public.unidades;
create policy "agentes con la herramienta crean unidades" on public.unidades
  for insert to authenticated with check (public.es_agente() and public.puede('unidades'));
