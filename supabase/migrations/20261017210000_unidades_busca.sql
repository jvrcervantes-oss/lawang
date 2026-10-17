-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68). El buscador de la cabecera es de la v4 de Lawang; si el maestro
-- lo adopta, su gemela va con su revisión.
-- BUSCADOR DE UNIDADES DE LA CABECERA (H6 de Experiencia, 17-oct-2026, sesión lawang-mejoras-ux, tren 6). El buscador de la cabecera
-- (intranet/v4/assets/nav.js, GRUPOS_DATOS, grupo «Unidades») leía `from('unidades')` desde el navegador; el gate de lecturas nuevas
-- del pre-push lo paró (norma del owner del 15-oct: la pantalla pide al servidor, no lee la tabla). Esta función hace esa búsqueda
-- en el servidor, con la misma forma que contratos_busca (20261015062313):
--   · sin tildes con LA pieza común (public.normaliza_busqueda, norma del 15-oct); tope de 200 caracteres en el servidor;
--     mínimo 2 letras ya normalizadas; sin comodines (strpos, no ilike); 10 filas.
--   · INVOKER: la RLS de `unidades` («agentes leen unidades de sus proyectos, manager de los suyos», TO authenticated, lw_lector)
--     y la de `proyectos` deciden qué se ve; no se copia a mano. Cuando L6 (LAW-338) cierre la lectura de `unidades` a
--     authenticated, esta pasa a DEFINER de lw_lector como hizo L5 con contratos_busca (apuntado en el inventario de L6).
--   · columnas explícitas: id, código, proyecto_id y el nombre de HOY del proyecto (unido por proyecto_id; si no se ve, la
--     copia de la unidad). Busca por código y por ese nombre. El enlace del front va por proyecto_id (máxima «todo por ID»).
-- PERMISOS: nace cerrada: revoke de PUBLIC, anon y service_role; EXECUTE solo a authenticated. Llamador con nombre: nav.js.
-- ORDEN: independiente del front. Sin esta función el front recibe PGRST202 y esconde solo el grupo «Unidades» (nav.js,
-- sinPermisoONoExiste); herramientas, clientes y contratos siguen buscando (agencia-cd, 17-oct: el tren 6 aterriza antes).
-- PRUEBA (solo en rama, fixture propio, rol real): supabase/pruebas/unidades_busca.sql
--   python erp/rama_prueba.py lawang --lawang <copia> --aplica 20261017210000_unidades_busca.sql --prueba unidades_busca.sql
-- VUELTA ATRÁS: supabase/reversion_unidades_busca/REVERSION.sql (el grupo vuelve a esconderse solo).
-- destructivo-ok: crea una función nueva; no toca tablas ni datos
set local lock_timeout = '5s';

create or replace function public.unidades_busca(p_q text)
 returns table(id uuid, codigo text, proyecto text, proyecto_id uuid)
 language sql
 stable
 security invoker
 set search_path = ''
as $f$
  with q as (select public.normaliza_busqueda(left(p_q, 200)) as v)   -- tope en el servidor: la pantalla corta a 120, el servidor no se fía
  select u.id, u.codigo, coalesce(pr.nombre, u.proyecto), u.proyecto_id
    from public.unidades u
    cross join q
    left join public.proyectos pr on pr.id = u.proyecto_id   -- el nombre de HOY del proyecto, no la copia de la unidad
   where public.es_agente()
     and char_length(q.v) >= 2
     and u.proyecto_id is not null
     and (strpos(public.normaliza_busqueda(u.codigo), q.v) > 0
          or strpos(public.normaliza_busqueda(coalesce(pr.nombre, u.proyecto)), q.v) > 0)
   order by coalesce(pr.nombre, u.proyecto), u.codigo_orden nulls last, u.codigo
   limit 10
$f$;
comment on function public.unidades_busca(text) is
  'Buscador de la cabecera v4 (nav.js, grupo Unidades), 17-oct-2026: unidades por código o proyecto, sin tildes, 10 filas. INVOKER: la RLS de unidades y proyectos decide qué se ve. Mínimo 2 letras.';
revoke all on function public.unidades_busca(text) from public, anon, service_role;
grant execute on function public.unidades_busca(text) to authenticated;

-- comprobación: INVOKER, search_path vacío, solo authenticated (sobre la ACL efectiva, PUBLIC por defecto incluido)
do $c$
declare x record; v_mal text := '';
begin
  select p.prosecdef, p.proconfig, pg_get_userbyid(p.proowner) as dueno,
         exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                  where a.grantee = 0 and a.privilege_type = 'EXECUTE') as pub,
         exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a join pg_roles r on r.oid = a.grantee
                  where r.rolname in ('anon', 'service_role') and a.privilege_type = 'EXECUTE') as api_mal,
         exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a join pg_roles r on r.oid = a.grantee
                  where r.rolname = 'authenticated' and a.privilege_type = 'EXECUTE') as auth
    into x
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'unidades_busca' and pg_get_function_identity_arguments(p.oid) = 'p_q text';
  if not found then raise exception 'unidades_busca no existe tras crearla'; end if;
  if x.prosecdef then v_mal := v_mal || 'es DEFINER; '; end if;
  if x.proconfig is null or not ('search_path=""' = any (x.proconfig)) then v_mal := v_mal || 'search_path no vacío; '; end if;
  if x.pub then v_mal := v_mal || 'PUBLIC ejecuta; '; end if;
  if x.api_mal then v_mal := v_mal || 'anon o service_role ejecutan; '; end if;
  if not x.auth then v_mal := v_mal || 'authenticated no ejecuta; '; end if;
  if v_mal <> '' then raise exception 'unidades_busca mal construida: %', v_mal; end if;
end $c$;
