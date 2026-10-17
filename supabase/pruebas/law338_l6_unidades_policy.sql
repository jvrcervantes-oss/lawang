-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Prueba de LAW-338 L6 · policy de lectura de unidades (17-oct-2026, sesión lawang-mejoras-ux, tren 6).
-- Migración: 20261017205000_law338_l6_unidades_policy.sql. Mide que la policy nueva deja ver EXACTAMENTE lo mismo que la de antes,
-- «es_agente() AND unidad_visible(proyecto_id)», persona a persona y con los dos roles de la policy (authenticated y lw_lector), y
-- que la lista de proyectos se calcula una vez por consulta (initPlan en el plan), no por fila.
--
-- !! SOLO EN RAMA: monta empresas, proyectos, personas y unidades.
--    python erp/rama_prueba.py lawang --lawang <copia de Lawang> --aplica 20261017205000_law338_l6_unidades_policy.sql --prueba law338_l6_unidades_policy.sql
--    Fuera de una rama (sin `erp.en_rama = si`, que pone rama_prueba) se niega a empezar, antes de tocar nada.
-- Formato de erp/pruebas/corre.py: termina en «FIN DE PRUEBAS» y cada línea acaba en «→ ok» o «→ FALLA». Todo se deshace con el raise final.
-- FIXTURE PROPIO (la rama recibe solo la estructura), como postgres y SIN sesión (así pasa el candado de alta de `usuarios`):
--   empresas zz_l6a (p1, p2) y zz_l6b (p3); una unidad en cada proyecto y una SIN proyecto; personas: super_admin global, admin de
--   empresa de zz_l6a, agente global sin empresas con p1 y p3, agente global acotado a zz_l6a con p1 y p3 (pierde p3), project
--   manager que solo ve p2 por supervisados, agente INACTIVO con p1 y una persona en auth.users sin fila en usuarios.
-- LO DE ANTES se calcula como postgres (sin RLS: E0 lo comprueba) con las claims de cada persona y la expresión vieja en el WHERE;
-- LO DE AHORA, con el rol real (`set local role`) leyendo la tabla. Además, para los perfiles cuya respuesta no depende de cómo
-- defina es_admin a cada rol, se fija lo esperado a mano: si la policy vieja y la nueva cambiaran a la vez, también se vería.
-- destructivo-ok: prueba en transacción que termina en raise (rollback); solo en rama; la vuelta atrás (V1) se ensaya dentro de la transacción
create temp table _tp (et text primary key, uid uuid, em text);
create or replace function pg_temp.l(c boolean, t text) returns text language sql as $f$
  select E'\n' || replace(t, E'\n', ' ') || case when coalesce(c, false) then ' → ok' else ' → FALLA' end
$f$;
create or replace function pg_temp.val(p_uid uuid, p_email text, p_sql text, p_rol text default 'authenticated') returns text language plpgsql as $f$
declare t text;
begin
  perform set_config('request.jwt.claims', case when p_uid is null then '' else
          json_build_object('sub', p_uid, 'role', 'authenticated', 'email', p_email)::text end, true);
  execute format('set local role %I', p_rol);
  begin execute p_sql into t;
  exception when others then t := 'ERR' || sqlstate || ':' || left(sqlerrm, 200); end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return coalesce(t, 'null');
end $f$;
-- lo de ANTES: como postgres (sin RLS) con las claims de la persona y la expresión vieja de la policy
create or replace function pg_temp.antes(p_uid uuid, p_email text) returns text language plpgsql as $f$
declare t text;
begin
  perform set_config('request.jwt.claims', case when p_uid is null then '' else
          json_build_object('sub', p_uid, 'role', 'authenticated', 'email', p_email)::text end, true);
  begin
    select coalesce(string_agg(u.codigo, ',' order by u.codigo), '') into t from public.unidades u
     where u.codigo like 'ZZL6-%' and public.es_agente() and public.unidad_visible(u.proyecto_id);
  exception when others then t := 'ERR' || sqlstate || ':' || left(sqlerrm, 200); end;
  perform set_config('request.jwt.claims', '', true);
  return t;
end $f$;
create or replace function pg_temp.e(t text) returns text language sql immutable as $f$ select case when t like 'ERR%' then left(t, 110) else t end $f$;

insert into _tp values ('S',  gen_random_uuid(), 'zz-l6-super@prueba.invalid'),
                       ('AE', gen_random_uuid(), 'zz-l6-admin-empresa@prueba.invalid'),
                       ('G0', gen_random_uuid(), 'zz-l6-global@prueba.invalid'),
                       ('G1', gen_random_uuid(), 'zz-l6-acotado@prueba.invalid'),
                       ('PM', gen_random_uuid(), 'zz-l6-manager@prueba.invalid'),
                       ('IN', gen_random_uuid(), 'zz-l6-inactivo@prueba.invalid'),
                       ('X',  gen_random_uuid(), 'zz-l6-fuera@prueba.invalid');   -- en auth.users, sin fila en usuarios

do $todo$
declare
  r text := ''; rp text := ''; v text; v2 text; w text; x record; pz _tp; plan jsonb; filtro text; t0 timestamptz; ms_nuevo numeric; ms_antes numeric;
  p1 uuid; p2 uuid; p3 uuid; n_sub int := 0;
  c_ea constant text := 'zz_l6a'; c_eb constant text := 'zz_l6b';
  c_q constant text := 'select coalesce(string_agg(codigo, '','' order by codigo), '''') from public.unidades where codigo like ''ZZL6-%''';
  c_fin constant text := 'FIN DE PRUEBAS LAW-338 L6 UNIDADES (se deshace todo):%';
begin
  if coalesce(current_setting('erp.en_rama', true), '') <> 'si' then
    raise exception 'FIN DE PRUEBAS LAW-338 L6 UNIDADES:%', E'\nP0 esta prueba monta filas: solo corre en rama → FALLA';
  end if;

  -- ============================================================ P. montaje del fixture propio (como postgres, SIN sesión)
  perform set_config('request.jwt.claims', '', true);
  begin
    insert into public.empresas (clave, nombre) values (c_ea, 'ZZ-L6 Empresa A'), (c_eb, 'ZZ-L6 Empresa B');
    insert into public.proyectos (nombre, slug, empresa, activo) values ('ZZ-L6 Uno', 'zz-l6-uno', c_ea, true) returning id into p1;
    insert into public.proyectos (nombre, slug, empresa, activo) values ('ZZ-L6 Dos', 'zz-l6-dos', c_ea, true) returning id into p2;
    insert into public.proyectos (nombre, slug, empresa, activo) values ('ZZ-L6 Tres', 'zz-l6-tres', c_eb, true) returning id into p3;
    insert into auth.users (id, instance_id, email, aud, role)
      select t.uid, '00000000-0000-0000-0000-000000000000', t.em, 'authenticated', 'authenticated' from _tp t;
    insert into public.usuarios (user_id, email, nombre, rol, ambito, empresas, proyectos, proyectos_supervisados, herramientas, tipos_contrato, activo)
      select t.uid, t.em, 'ZZ-L6 ' || t.et, f.rol, f.ambito, f.empresas, f.proyectos, f.sup, '{proyectos}'::text[], '{contrato_general}'::text[], f.activo
        from _tp t join (values
          ('S',  'super_admin',     'global',  '{}'::text[],    '{}'::uuid[],       '{}'::uuid[],  true),
          ('AE', 'admin_empresa',   'empresa', array[c_ea],     '{}'::uuid[],       '{}'::uuid[],  true),
          ('G0', 'agente',          'global',  '{}'::text[],    array[p1, p3],      '{}'::uuid[],  true),
          ('G1', 'agente',          'global',  array[c_ea],     array[p1, p3],      '{}'::uuid[],  true),
          ('PM', 'project_manager', 'global',  '{}'::text[],    '{}'::uuid[],       array[p2],     true),
          ('IN', 'agente',          'global',  '{}'::text[],    array[p1],          '{}'::uuid[],  false)
        ) f(et, rol, ambito, empresas, proyectos, sup, activo) on f.et = t.et;
    -- unidades.tipo apunta a tipos_vivienda(clave) y la rama sale sin filas: como carta_liberada_mismo_comprador.sql:81
    insert into public.tipos_vivienda (clave, etiqueta) values ('parcela', 'Parcela') on conflict (clave) do nothing;
    insert into public.unidades (codigo, proyecto, proyecto_id, tipo) values
      ('ZZL6-0', 'ZZ-L6 sin proyecto', null, 'parcela'),
      ('ZZL6-1', 'ZZ-L6 Uno', p1, 'parcela'), ('ZZL6-2', 'ZZ-L6 Dos', p2, 'parcela'), ('ZZL6-3', 'ZZ-L6 Tres', p3, 'parcela');
  exception when others then
    raise exception using message = replace(c_fin, '%', r || pg_temp.l(false, 'P0 montaje del fixture propio: ' || sqlstate || ' ' || left(sqlerrm, 300)
                                                                 || ' [session_user=' || session_user::text || ']'));
  end;
  rp := rp || pg_temp.l((select count(*) from _tp) = 7 and p3 is not null, 'P0 fixture propio montado: 2 empresas, 3 proyectos, 7 personas, 4 unidades [session_user=' || session_user::text || ']');
  rp := rp || pg_temp.l((select coalesce(string_agg(codigo, ',' order by codigo), '') from public.unidades where codigo like 'ZZL6-%') = 'ZZL6-0,ZZL6-1,ZZL6-2,ZZL6-3',
                        'E0 como postgres sin sesión se ven las 4 (lo de ANTES se calcula sin RLS)');
  v := pg_temp.val((select uid from _tp where et = 'G0'), (select em from _tp where et = 'G0'), 'select (select auth.uid())::text || ''|'' || current_user::text');
  rp := rp || pg_temp.l(v = (select uid from _tp where et = 'G0')::text || '|authenticated', 'S0 la sesión simulada es la de G0 con el rol authenticated (' || pg_temp.e(v) || ')');
  r := r || rp;
  if rp ~ 'FALLA' then
    raise exception using message = replace(c_fin, '%', r || pg_temp.l(false, 'PARADA: el fixture o la sesión no valen; los casos no se corren'));
  end if;

  -- ============================================================ N. cómo quedó: función y policy
  select p.prosecdef, pg_get_userbyid(p.proowner) dueno, p.proconfig,
         has_function_privilege('anon', p.oid, 'execute') anon, has_function_privilege('service_role', p.oid, 'execute') srv,
         has_function_privilege('authenticated', p.oid, 'execute') auth, has_function_privilege('lw_lector', p.oid, 'execute') lec
    into x from pg_proc p where p.oid = 'public.mis_proyectos_visibles()'::regprocedure;
  r := r || pg_temp.l(x.prosecdef and x.dueno = 'postgres' and x.proconfig @> array['search_path=""']::text[] and not x.anon and not x.srv and x.auth and x.lec,
                      'N1 mis_proyectos_visibles: DEFINER de postgres, search_path vacío, solo authenticated y lw_lector (anon=' || x.anon::text
                      || ' service_role=' || x.srv::text || ' authenticated=' || x.auth::text || ' lw_lector=' || x.lec::text || ')');
  select (select array_agg(s.n order by s.n) from (select coalesce(ro.rolname::text, case when o = 0 then 'public' else '#' || o::text end) as n
                                                     from unnest(pl.polroles) o left join pg_roles ro on ro.oid = o) s) roles,
         pl.polcmd, (select count(*) from pg_policy q where q.polrelid = pl.polrelid and q.polcmd in ('r', '*')) n_lect
    into x from pg_policy pl
   where pl.polrelid = 'public.unidades'::regclass and pl.polname = 'agentes leen unidades de sus proyectos, manager de los suyos';
  r := r || pg_temp.l(x.roles = array['authenticated', 'lw_lector'] and x.polcmd = 'r' and x.n_lect = 1,
                      'N2 la policy sigue siendo la única de lectura, de SELECT, para authenticated y lw_lector (' || coalesce(x.roles::text, 'sin policy')
                      || ', lectura: ' || coalesce(x.n_lect::text, '0') || ')');

  -- ============================================================ Q. lo mismo que antes, persona a persona y con los dos roles
  for pz in select * from _tp order by et loop
    w := pg_temp.antes(pz.uid, pz.em);
    v := pg_temp.val(pz.uid, pz.em, c_q);
    v2 := pg_temp.val(pz.uid, pz.em, c_q, 'lw_lector');
    r := r || pg_temp.l(v = w and v2 = w and w not like 'ERR%',
                        'Q ' || pz.et || ': antes «' || pg_temp.e(w) || '» · authenticated «' || pg_temp.e(v) || '» · lw_lector «' || pg_temp.e(v2) || '»');
    if w <> '' and w <> 'ZZL6-0,ZZL6-1,ZZL6-2,ZZL6-3' then n_sub := n_sub + 1; end if;
  end loop;
  r := r || pg_temp.l(n_sub >= 3, 'Q no es una comparación de vacíos ni de todo: ' || n_sub || ' personas ven una parte propia');
  -- lo esperado a mano (no depende de cómo trate es_admin a cada rol)
  select string_agg(et || '=' || pg_temp.val(uid, em, c_q), ' ' order by et) into v from _tp where et in ('S', 'G0', 'G1', 'PM', 'IN', 'X');
  r := r || pg_temp.l(v = 'G0=ZZL6-1,ZZL6-3 G1=ZZL6-1 IN= PM=ZZL6-2 S=ZZL6-0,ZZL6-1,ZZL6-2,ZZL6-3 X=',
                      'Q0 a mano: el super admin todo (también sin proyecto), el global sus dos, el acotado pierde el de la otra empresa, el manager por supervisados, inactivo y ajeno nada (' || v || ')');
  v := pg_temp.val(null, null, c_q, 'anon');
  r := r || pg_temp.l(v = '' or v like 'ERR42501%', 'Q anon: nada (' || pg_temp.e(v) || ')');

  -- ============================================================ I. una vez por consulta: initPlan, ninguna llamada por fila
  select * into pz from _tp where et = 'G0';
  v := pg_temp.val(pz.uid, pz.em, 'explain (verbose, format json) select id from public.unidades');
  if v like 'ERR%' then
    r := r || pg_temp.l(false, 'I1 explain como G0: ' || pg_temp.e(v));
  else
    plan := v::jsonb;
    select string_agg(f #>> '{}', ' | ') into filtro
      from jsonb_path_query(plan, 'lax $.** ? (@."Relation Name" == "unidades")."Filter"') f;
    r := r || pg_temp.l(filtro is not null and filtro !~ '(unidad_visible|proyecto_visible|mis_proyectos_visibles|es_agente|es_admin)\(' and v ~ 'InitPlan' and v ~ 'mis_proyectos_visibles\(',
                        'I1 el filtro de unidades no llama a ninguna función por fila; mis_proyectos_visibles va en un InitPlan (filtro: ' || left(coalesce(filtro, 'sin filtro'), 160) || ')');
  end if;

  -- ============================================================ C. coste con volumen (600 más en p1, como la prueba de unidades_busca)
  insert into public.unidades (codigo, proyecto, proyecto_id, tipo)
    select 'ZZL6-V' || lpad(g::text, 4, '0'), 'ZZ-L6 Uno', p1, 'parcela' from generate_series(1, 600) g;
  t0 := clock_timestamp();
  v := pg_temp.val(pz.uid, pz.em, 'select count(*) from public.unidades where codigo like ''ZZL6-%''');
  ms_nuevo := round(extract(epoch from clock_timestamp() - t0) * 1000);
  perform set_config('request.jwt.claims', json_build_object('sub', pz.uid, 'role', 'authenticated', 'email', pz.em)::text, true);
  t0 := clock_timestamp();
  select count(*)::text into v2 from public.unidades u where u.codigo like 'ZZL6-%' and public.es_agente() and public.unidad_visible(u.proyecto_id);
  ms_antes := round(extract(epoch from clock_timestamp() - t0) * 1000);
  perform set_config('request.jwt.claims', '', true);
  r := r || pg_temp.l(v = '602' and v2 = '602' and ms_nuevo < 150,
                      'C1 G0 con 602 unidades visibles: ahora ' || pg_temp.e(v) || ' en ' || ms_nuevo || ' ms (tope 150) · con la regla vieja por fila ' || v2 || ' en ' || ms_antes || ' ms');

  -- ============================================================ H. huella para tools/salud_lawang.py (_MCP_COPIAS), medida como allí
  perform set_config('search_path', '"$user", public, extensions', true);
  select coalesce(p.qual, '') as q, md5(coalesce(p.qual, '')) as h into x from pg_policies p
   where p.schemaname = 'public' and p.tablename = 'unidades' and p.policyname = 'agentes leen unidades de sus proyectos, manager de los suyos';
  r := r || pg_temp.l(x.h is not null and x.h <> 'ba7ae87af69245a9b5305663e66f74ee',
                      'H1 huella nueva de la policy para _MCP_COPIAS: ' || coalesce(x.h, 'sin policy') || ' (qual: ' || left(coalesce(x.q, ''), 200) || ')');

  -- ============================================================ V. la vuelta atrás deja la policy EXACTA de antes (ensayada aquí; se deshace con el resto)
  begin
    alter policy "agentes leen unidades de sus proyectos, manager de los suyos" on public.unidades
      using (public.es_agente() and public.unidad_visible(proyecto_id));
    drop function public.mis_proyectos_visibles();
    select md5(coalesce(p.qual, '')) into v from pg_policies p
     where p.schemaname = 'public' and p.tablename = 'unidades' and p.policyname = 'agentes leen unidades de sus proyectos, manager de los suyos';
  exception when others then v := 'ERR' || sqlstate || ':' || left(sqlerrm, 200);
  end;
  r := r || pg_temp.l(v = 'ba7ae87af69245a9b5305663e66f74ee',
                      'V1 la REVERSION (alter policy + drop) devuelve la huella de antes, ba7ae87a… (' || pg_temp.e(v) || ')');

  raise exception 'FIN DE PRUEBAS LAW-338 L6 UNIDADES (se deshace todo):%', r;
end $todo$;
