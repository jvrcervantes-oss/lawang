-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · bloque 5 (USUARIOS, EQUIPO Y EDGES) · migracion 0 (8-oct-2026): INSTANTANEA de lo que el bloque va a cambiar.
--   Guarda, tal y como estan VIVAS justo antes (pg_get_functiondef / pg_policies), las 5 funciones y la policy de `usuarios` que tocan las migraciones 1..4 de este bloque.
--   La reversion (supabase/reversion_f2/REVERSION_f2_b5.sql) las reaplica de ahi: la unica forma de que la vuelta atras sea exacta.
--   Tabla sin ningun permiso (ni authenticated, ni anon, ni lw_lector): solo la lee quien administra la base. Se borra cuando el bloque lleve una semana estable (ultima linea de la reversion).
-- destructivo-ok: tabla nueva sin datos de negocio; sin borrar nada existente
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b5.sql
create table if not exists public._f2_b5_originales (
  nombre text primary key,
  tipo   text not null check (tipo in ('funcion','policy')),
  ddl    text not null,
  creado timestamptz not null default now()
);
alter table public._f2_b5_originales enable row level security;
revoke all on public._f2_b5_originales from public, anon, authenticated, lw_lector;

insert into public._f2_b5_originales (nombre, tipo, ddl)
select 'f:' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')', 'funcion', pg_get_functiondef(p.oid)
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname in ('usuario_guarda_permisos','usuario_supervisa_proyecto','usuario_da_alcance',
                     'usuarios_bloquea_cambio_rol_herramientas','usuarios_candado_alta')
on conflict (nombre) do nothing;

insert into public._f2_b5_originales (nombre, tipo, ddl)
select 'p:' || pp.schemaname || '.' || pp.tablename || ':' || pp.policyname, 'policy',
       format('alter policy %I on %I.%I using (%s)%s', pp.policyname, pp.schemaname, pp.tablename, pp.qual,
              case when pp.with_check is not null then format(' with check (%s)', pp.with_check) else '' end)
  from pg_policies pp
 where (pp.schemaname, pp.tablename, pp.policyname) in (('public','usuarios','el equipo se ve entre si'))
on conflict (nombre) do nothing;

do $$
begin
  if (select count(*) from public._f2_b5_originales) <> 6 then
    raise exception 'La instantanea del bloque 5 no esta completa (se esperaban 5 funciones y 1 policy)';
  end if;
end $$;
