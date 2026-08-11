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

-- ── Permisos de ejecución ────────────────────────────────────────────────
-- Postgres concede EXECUTE a PUBLIC al crear una función, y `anon` lo hereda:
-- revocar solo de `anon` no hace nada. Hay que quitarlo de PUBLIC y devolverlo.
-- ⚠️ `authenticated` LO NECESITA: las policies evalúan estas funciones con los
-- privilegios de la sesión; sin EXECUTE, cada comprobación de RLS fallaría con
-- "permission denied" y la suite entera quedaría fuera.
revoke execute on function public.es_agente()   from public;
revoke execute on function public.es_admin()    from public;
revoke execute on function public.puede(text)   from public;
revoke execute on function public.es_suyo(text) from public;
grant  execute on function public.es_agente()   to authenticated, service_role;
grant  execute on function public.es_admin()    to authenticated, service_role;
grant  execute on function public.puede(text)   to authenticated, service_role;
grant  execute on function public.es_suyo(text) to authenticated, service_role;

-- ============================================================
-- APLICADO en producción el 11-ago-2026 por MCP (migración
-- `usuarios_admin_no_toca_super_admin`). Registro, no hace falta volver a
-- correrlo.
--
-- Auditoría de suite: `es_admin()` no distingue admin de super_admin, y la
-- policy de UPDATE de `usuarios` solo miraba eso — un admin normal podía
-- ascenderse a sí mismo a super_admin, o degradar a uno, con una llamada
-- directa a la API. Los botones `disabled` del panel no son una barrera real.
-- ============================================================
create or replace function public.es_super_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.usuarios u
                  where u.user_id = (select auth.uid()) and u.activo
                    and u.rol = 'super_admin')
$$;

-- `revoke ... from public` NO basta en Supabase: al crear la función ya queda
-- un grant EXPLÍCITO a `anon`, aparte del que hereda de PUBLIC — hay que
-- revocárselo también a él, o la función queda invocable sin sesión.
revoke execute on function public.es_super_admin() from public;
revoke execute on function public.es_super_admin() from anon;
grant  execute on function public.es_super_admin() to authenticated, service_role;

drop policy if exists "solo admin edita usuarios" on public.usuarios;
create policy "admin edita, pero no toca una fila super_admin sin serlo" on public.usuarios
  for update to authenticated
  using   (public.es_admin() and (rol <> 'super_admin' or public.es_super_admin()))
  with check (public.es_admin() and (rol <> 'super_admin' or public.es_super_admin()));

-- ── Cómo se verificó (29-jul-2026), para repetirlo ───────────────────────
-- La conexión del MCP es PROPIETARIA de las tablas y por tanto BYPASEA la RLS:
-- un `select count(*)` desde ahí devuelve todo aunque la política esté mal, así
-- que no prueba nada. Hay que asumir el rol de verdad, y `set_config('role',…)`
-- dentro de un LATERAL no basta: se necesita `SET LOCAL ROLE authenticated`
-- dentro de una función plpgsql temporal (creada, usada y BORRADA).
-- Resultado sobre el contrato RP00016 (autor admin@):
--   sales@ → 0 filas (denegado) · su autor → 1 · super_admin → 1 · desactivado → 0
-- Y en lectura: un agente ve 1 ficha de usuario (la suya), el super_admin las 7,
-- y un usuario desactivado ve 0 contratos y 0 facturas.
