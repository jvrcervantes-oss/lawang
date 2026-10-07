-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · bloque 5 (USUARIOS, EQUIPO Y EDGES) · migracion 1 (8-oct-2026): ayudas, registro de cambios de nivel y quien ve que fichas de `usuarios`.
--   1) `_gestor_empresas()` / `_gestor_herramientas()` / `_usuario_gestionable(uuid)` / `_alta_empresa_permitida(...)`: UNA sola definicion de «a quien puede gestionar un rol de empresa».
--      Un rol de empresa gestiona SOLO personas con rol agente / sales_manager / project_manager, ambito global, con al menos una empresa marcada y TODAS dentro de las suyas,
--      que no sean el propietario ni el propio llamador. Ojo: '{}' <@ cualquier-cosa es true, por eso se exige cardinality > 0 (sin ello gestionaria a los 34 globales).
--      Un admin_empresa ademas necesita la casilla «usuarios» (como un admin global); un super_admin_empresa no (como el super global: `_puede_admin_de`).
--      Sin EXECUTE para nadie: las llaman funciones DEFINER (las 3 puertas de personas y los triggers de `usuarios`) que corren como su duenyo.
--   2) `mis_empresas()`: las empresas del llamador (para la policy). EXECUTE authenticated y lw_lector (la llama una policy: leccion G1).
--   3) Registro `usuarios_cambios_alcance`: una fila por cada cambio de nivel / empresas / proyectos que hace una funcion (quien, a quien, antes y despues).
--      Solo lo lee el propietario; nadie escribe por la API (lo escribe la propia funcion como su duenyo).
--   4) Policy «el equipo se ve entre si» de `usuarios`: un llamador con alcance restringido (rol de empresa, o agente con empresas marcadas) solo ve su ficha, las fichas
--      que comparten alguna empresa con el, y las de personas globales sin empresas (el estudio y los agentes sin restringir: autores y closers de lo que ve). NO ve las
--      fichas de gente que solo es de la otra empresa. Los 34 usuarios de hoy (0 restringidos, medido) ven exactamente lo mismo.
--      LIMITE conocido y aceptado: la RLS filtra FILAS, no columnas; las fichas globales que ve siguen llevando herramientas/proyectos. Un directorio solo de nombres seria una funcion nueva para el front (bloque 7).
-- destructivo-ok: tablas y funciones nuevas; alter policy de una lectura (no toca datos)
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b5.sql
set local lock_timeout = '3s';

-- ---------------------------------------------------------------- ayudas privadas
create or replace function public._gestor_empresas() returns text[]
language sql stable security definer set search_path = '' as $$
  select u.empresas from public.usuarios u
   where u.user_id = (select auth.uid()) and u.activo and u.ambito = 'empresa' and cardinality(u.empresas) > 0
     and (u.rol = 'super_admin_empresa' or (u.rol = 'admin_empresa' and 'usuarios' = any (u.herramientas)))
$$;

create or replace function public._gestor_herramientas() returns text[]
language sql stable security definer set search_path = '' as $$
  select u.herramientas from public.usuarios u where u.user_id = (select auth.uid()) and u.activo
$$;

create or replace function public._usuario_gestionable(p_user_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((
    select true
      from public.usuarios t
     where t.user_id = p_user_id
       and public._gestor_empresas() is not null
       and t.user_id is distinct from (select auth.uid())
       and not t.es_propietario
       and t.ambito = 'global'
       and t.rol in ('agente', 'sales_manager', 'project_manager')
       and cardinality(t.empresas) > 0
       and t.empresas <@ public._gestor_empresas()
  ), false)
$$;

create or replace function public._alta_empresa_permitida(p_rol text, p_ambito text, p_empresas text[], p_herramientas text[], p_proyectos uuid[], p_es_prop boolean)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((
    select true
      from public.usuarios c
     where c.user_id = (select auth.uid()) and c.activo and c.ambito = 'empresa'
       and (c.rol = 'super_admin_empresa' or (c.rol = 'admin_empresa' and 'usuarios' = any (c.herramientas)))
       and not coalesce(p_es_prop, false)
       and p_ambito = 'global'
       and cardinality(coalesce(p_empresas, '{}')) > 0
       and p_empresas <@ c.empresas
       and p_rol = any (case when c.rol = 'super_admin_empresa' then array['agente','sales_manager','project_manager'] else array['agente'] end)
       and coalesce(p_herramientas, '{}') <@ c.herramientas
       and not exists (select 1 from unnest(coalesce(p_proyectos, '{}'::uuid[])) x(id)
                         left join public.proyectos p on p.id = x.id
                        where p.empresa is null or not (p.empresa = any (p_empresas)))
  ), false)
$$;

-- ---------------------------------------------------------------- las empresas del llamador (la llama la policy de `usuarios`)
create or replace function public.mis_empresas() returns text[]
language sql stable security definer set search_path = '' as $$
  select coalesce((select u.empresas from public.usuarios u where u.user_id = (select auth.uid()) and u.activo), '{}'::text[])
$$;

revoke all on function public._gestor_empresas(), public._gestor_herramientas(), public._usuario_gestionable(uuid),
  public._alta_empresa_permitida(text, text, text[], text[], uuid[], boolean), public.mis_empresas() from public, anon, authenticated;
grant execute on function public.mis_empresas() to authenticated, lw_lector;

-- ---------------------------------------------------------------- registro de cambios de nivel y alcance
create table if not exists public.usuarios_cambios_alcance (
  id          bigint generated always as identity primary key,
  cuando      timestamptz not null default now(),
  quien       uuid,
  quien_email text,
  a_quien     uuid not null,
  a_email     text,
  accion      text not null check (accion in ('nivel','alta')),
  antes       jsonb not null,
  despues     jsonb not null
);
comment on table public.usuarios_cambios_alcance is 'Fase 2 b5: quien dio o cambio el nivel/empresas/proyectos de quien, con antes y despues. Solo lo lee el propietario; lo escriben usuario_da_alcance y usuario_alta_empresa.';
alter table public.usuarios_cambios_alcance enable row level security;
revoke all on public.usuarios_cambios_alcance from public, anon, authenticated, lw_lector;
grant select on public.usuarios_cambios_alcance to authenticated;
create policy "cambios de alcance: solo el propietario" on public.usuarios_cambios_alcance
  for select to authenticated using ((select public.es_propietario()));

-- ---------------------------------------------------------------- quien ve que fichas de `usuarios`
alter policy "el equipo se ve entre si" on public.usuarios
  using ((select public.es_agente())
         and (not (select public.alcance_restringido())
              or user_id = (select auth.uid())
              or cardinality(empresas) = 0
              or empresas && (select public.mis_empresas())));
