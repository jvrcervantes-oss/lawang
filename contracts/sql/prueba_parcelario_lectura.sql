-- PRUEBA — parcelario_proyectos() / parcelario_unidades(uuid) (Parcelario de AI Tools, 9-oct-2026). Cubre
-- 20261009041027_parcelario_lectura_panel.sql y su paso a INVOKER. Se ejecuta con execute_sql (MCP) o psql como postgres,
-- UN BLOQUE: acaba en `raise exception 'RES: …'`, que revierte todo y enseña el resultado. NO ESCRIBE NADA.
-- Cada punto debe decir «ok»; «FALLO» es un agujero o una regresión.
-- Las columnas permitidas son una COPIA de PARC_UNIDAD_COLS / PARC_PROYECTO_COLS de infraestructura/panel-web/server.py
-- (repo de la agencia): si alguien añade comprador, precio, contrato o socio a la función, esto cae.
do $t$
declare
  r text := '';
  n int;
  cols_u text; cols_p text;
  pid uuid;
begin
  -- (a) permisos: solo service_role ejecuta; anon, authenticated, lw_lector y PUBLIC no
  r := r || case when has_function_privilege('service_role', 'public.parcelario_unidades(uuid)', 'execute')
                  and has_function_privilege('service_role', 'public.parcelario_proyectos()', 'execute') then 'a1 ok; ' else 'a1 FALLO service_role no puede; ' end;
  r := r || case when not has_function_privilege('anon', 'public.parcelario_unidades(uuid)', 'execute')
                  and not has_function_privilege('authenticated', 'public.parcelario_unidades(uuid)', 'execute')
                  and not has_function_privilege('anon', 'public.parcelario_proyectos()', 'execute')
                  and not has_function_privilege('authenticated', 'public.parcelario_proyectos()', 'execute') then 'a2 ok; ' else 'a2 FALLO execute de más; ' end;
  if exists (select 1 from pg_roles where rolname = 'lw_lector') then
    r := r || case when not has_function_privilege('lw_lector', 'public.parcelario_unidades(uuid)', 'execute')
                    and not has_function_privilege('lw_lector', 'public.parcelario_proyectos()', 'execute') then 'a3 ok; ' else 'a3 FALLO lw_lector ejecuta; ' end;
  else r := r || 'a3 omitido (no existe lw_lector); '; end if;
  -- PUBLIC no aparece en el ACL (el permiso de PUBLIC es el que se cuela, seguridad_2026.md §1.ter)
  select count(*) into n from pg_proc p join pg_namespace s on s.oid = p.pronamespace, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
   where s.nspname = 'public' and p.proname in ('parcelario_unidades', 'parcelario_proyectos') and a.grantee = 0 and a.privilege_type = 'EXECUTE';
  r := r || case when n = 0 then 'a4 ok; ' else 'a4 FALLO PUBLIC tiene EXECUTE; ' end;
  -- (b) INVOKER, stable y search_path VACÍO (no basta con que haya uno: `public` volvería a abrir la sustitución de objetos)
  select count(*) into n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
   where s.nspname = 'public' and p.proname in ('parcelario_unidades', 'parcelario_proyectos')
     and not p.prosecdef and p.provolatile = 's' and 'search_path=""' = any (coalesce(p.proconfig, '{}'::text[]));
  r := r || case when n = 2 then 'b1 ok (invoker, stable, search_path vacío); ' else 'b1 FALLO ficha de las funciones; ' end;
  -- (c) columnas EXACTAS que devuelven
  select pg_get_function_result('public.parcelario_unidades(uuid)'::regprocedure) into cols_u;
  select pg_get_function_result('public.parcelario_proyectos()'::regprocedure) into cols_p;
  r := r || case when cols_u = 'TABLE(codigo text, proyecto text, tipo text, superficie_m2 numeric, estado text, fase_masterplan text, zona_masterplan text, publicado_investor_deck boolean)'
                 then 'c1 ok; ' else 'c1 FALLO columnas de unidades: ' || cols_u || '; ' end;
  r := r || case when cols_p = 'TABLE(id uuid, nombre text, parcela_master_m2 numeric, unidades bigint)'
                 then 'c2 ok; ' else 'c2 FALLO columnas de proyectos: ' || cols_p || '; ' end;
  -- (d) como service_role devuelve las filas del proyecto, todas y solo las suyas
  select id into pid from public.proyectos where nombre like 'Palm Field%' limit 1;
  if pid is null then r := r || 'd1 omitido (no hay Palm Field); ';
  else
    set local role service_role;
    select count(*) into n from public.parcelario_unidades(pid);
    reset role;
    r := r || case when n = (select count(*) from public.unidades where proyecto_id = pid) and n > 0 then 'd1 ok (' || n || ' unidades); ' else 'd1 FALLO filas: ' || n || '; ' end;
  end if;
  -- (e) como authenticated (sin EXECUTE) la llamada se rechaza con 42501
  begin
    set local role authenticated;
    perform * from public.parcelario_unidades(coalesce(pid, gen_random_uuid()));
    reset role;
    r := r || 'e1 FALLO authenticated pudo llamarla; ';
  exception when insufficient_privilege then
    reset role;
    r := r || 'e1 ok (42501); ';
  end;
  raise exception 'RES: %', r;
end $t$;
