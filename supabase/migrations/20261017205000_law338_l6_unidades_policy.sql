-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- LAW-338 L6 (17-oct-2026, sesión lawang-mejoras-ux, tren 6): la policy de LECTURA de `unidades` con la lista de proyectos visibles
-- calculada UNA vez por consulta en vez de llamar a proyecto_visible (DEFINER) por fila. Misma regla, más barata.
-- POR QUÉ: el ensayo 7a125126 de 20261017210000_unidades_busca midió 617 y 634 ms por búsqueda de un agente con 612 unidades
-- visibles (tope 300; el buscador de la cabecera pregunta en cada tecla). El coste es la RLS: «es_agente() AND
-- unidad_visible(proyecto_id)» evalúa unidad_visible → proyecto_visible por cada fila (0,18 s/464 filas ya en 20261007000950:3).
-- Lo mismo paga Proyectos y la vista unidades_estado (security_invoker). agencia-cd decidió (17-oct, CEO por defecto) que esto va
-- antes que la 210000, con su migración y su prueba.
-- ARREGLO (patrón de facturas y contratos, 20261007001500): mis_proyectos_visibles() = los ids de `proyectos` para los que
-- proyecto_visible da true, leída la ficha una vez; la policy la toma como initPlan `(select …)`, igual que es_agente y es_admin.
-- EQUIVALENCIA con «es_agente() AND unidad_visible(proyecto_id)» (unidad_visible = proyecto_visible, 20260911033802:62):
--   · admin: proyecto_visible da true siempre, también con proyecto_id nulo → la rama `(select es_admin())` lo conserva.
--   · resto: con proyecto_id nulo, false en las dos (null = any(...) no es true). Con proyecto_id no nulo, la clave ajena
--     unidades.proyecto_id → proyectos(id) on delete set null (20260817150634:26) garantiza que el id está en `proyectos`, que es
--     justo donde mis_proyectos_visibles mira; proyecto_visible podría dar true para un id que no está en `proyectos` (agente
--     global con el id en usuarios.proyectos), pero esa unidad no puede existir.
--   · la regla NO se reescribe: la función llama a la misma proyecto_visible. Si proyecto_visible cambia, esto la sigue.
-- QUÉ NO CAMBIA: las policies de UPDATE e INSERT de unidades siguen con unidad_visible (una fila por escritura: no hay coste que
-- arreglar); unidad_visible y proyecto_visible no se tocan (las usan otras policies, unidades_estado y la copia del MCP).
-- PERMISOS: mis_proyectos_visibles nace con EXECUTE solo para authenticated y lw_lector, los dos roles de la policy (una policy se
-- evalúa con los privilegios de quien consulta). Llamador con nombre: esta policy. Precedente: mis_proyectos_admin_empresa y
-- alcance_restringido (20261007001500:51-61). Sin anon ni service_role (service_role se salta la RLS: nunca la evalúa).
-- Devuelve ids de proyectos, no datos: quien la llame directamente solo sabe qué proyectos ve, lo mismo que ya le enseña Proyectos.
-- HUELLA: tools/salud_lawang.py (_MCP_COPIAS) congela md5(qual) de esta policy (ba7ae87af69245a9b5305663e66f74ee). Tras aplicar,
-- la huella nueva (la imprime la prueba, línea H1) se pone allí en el mismo aterrizaje; la copia de mcp_cambios_estado_semana
-- (20261016073333:454, «es_agente() and unidad_visible(u.proyecto_id)») sigue valiendo porque la prueba demuestra que es la misma regla.
-- PRUEBA (solo en rama, fixture propio, rol real): supabase/pruebas/law338_l6_unidades_policy.sql
--   python erp/rama_prueba.py lawang --lawang <copia> --aplica 20261017205000_law338_l6_unidades_policy.sql --prueba law338_l6_unidades_policy.sql
-- VUELTA ATRÁS (exacta): supabase/reversion_law338_l6_unidades/REVERSION.sql (devuelve la policy de hoy y borra la función).
-- destructivo-ok: una función nueva y alter policy con la misma regla; no cambia roles de la policy ni toca datos ni da acceso nuevo
set local lock_timeout = '5s';

create or replace function public.mis_proyectos_visibles() returns uuid[]
language sql stable security definer set search_path = '' as $$
  select coalesce(array_agg(pr.id), '{}'::uuid[]) from public.proyectos pr where public.proyecto_visible(pr.id)
$$;
comment on function public.mis_proyectos_visibles() is
  'Ids de proyectos que la persona ve (proyecto_visible), calculados una vez por consulta. Llamador: la policy de lectura de unidades (LAW-338 L6, 17-oct-2026).';
revoke all on function public.mis_proyectos_visibles() from public, anon, service_role;
grant execute on function public.mis_proyectos_visibles() to authenticated, lw_lector;

-- sin TO: la policy conserva sus roles (authenticated, lw_lector)
alter policy "agentes leen unidades de sus proyectos, manager de los suyos" on public.unidades
  using ((select public.es_agente()) and ((select public.es_admin()) or proyecto_id = any ((select public.mis_proyectos_visibles()))));

-- comprobación: la función bien construida y la policy con sus roles y la regla nueva
do $c$
declare x record; v_mal text := '';
begin
  select p.prosecdef, p.proconfig, pg_get_userbyid(p.proowner) as dueno,
         exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                  where a.grantee = 0 and a.privilege_type = 'EXECUTE') as pub,
         exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a join pg_roles r on r.oid = a.grantee
                  where r.rolname in ('anon', 'service_role') and a.privilege_type = 'EXECUTE') as api_mal,
         (select count(*) from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a join pg_roles r on r.oid = a.grantee
           where r.rolname in ('authenticated', 'lw_lector') and a.privilege_type = 'EXECUTE') as n_ok
    into x
    from pg_proc p
   where p.oid = to_regprocedure('public.mis_proyectos_visibles()');
  if not found then raise exception 'mis_proyectos_visibles no existe tras crearla'; end if;
  if not x.prosecdef then v_mal := v_mal || 'no es DEFINER; '; end if;
  if x.dueno <> 'postgres' then v_mal := v_mal || 'dueño ' || x.dueno || '; '; end if;
  if x.proconfig is null or not ('search_path=""' = any (x.proconfig)) then v_mal := v_mal || 'search_path no vacío; '; end if;
  if x.pub then v_mal := v_mal || 'PUBLIC ejecuta; '; end if;
  if x.api_mal then v_mal := v_mal || 'anon o service_role ejecutan; '; end if;
  if x.n_ok <> 2 then v_mal := v_mal || 'authenticated y lw_lector no ejecutan los dos; '; end if;

  select pl.polcmd, pg_get_expr(pl.polqual, pl.polrelid) as qual,
         (select array_agg(s.n order by s.n)
            from (select coalesce(ro.rolname::text, case when o = 0 then 'public' else '#' || o::text end) as n
                    from unnest(pl.polroles) o left join pg_roles ro on ro.oid = o) s) as roles
    into x
    from pg_policy pl
   where pl.polrelid = 'public.unidades'::regclass and pl.polname = 'agentes leen unidades de sus proyectos, manager de los suyos';
  if not found then raise exception 'la policy de lectura de unidades no existe'; end if;
  if x.polcmd <> 'r' then v_mal := v_mal || 'la policy ya no es de SELECT; '; end if;
  if x.roles is distinct from array['authenticated', 'lw_lector'] then v_mal := v_mal || 'roles ' || x.roles::text || '; '; end if;
  if x.qual !~ 'mis_proyectos_visibles' or x.qual ~ 'unidad_visible' then v_mal := v_mal || 'regla no aplicada: ' || x.qual || '; '; end if;
  if v_mal <> '' then raise exception 'L6 unidades mal aplicada: %', v_mal; end if;
end $c$;
