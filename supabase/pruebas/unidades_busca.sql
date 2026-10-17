-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Prueba de UNIDADES_BUSCA (17-oct-2026, sesión lawang-mejoras-ux, tren 6): el grupo «Unidades» del buscador de la cabecera
-- (intranet/v4/assets/nav.js) pide al servidor en vez de leer `unidades`. Migración 20261017210000_unidades_busca.
-- Rol REAL: cada llamada va con `set local role authenticated` (o anon) y los claims de la persona (pg_temp.val). Un caso que ENTRA
-- por cada caso que se NIEGA.
--
-- !! SOLO EN RAMA: monta empresa, dos proyectos, personas y unidades.
--    python erp/rama_prueba.py lawang --lawang <copia de Lawang> --aplica 20261017210000_unidades_busca.sql --prueba unidades_busca.sql
--    Fuera de una rama (sin `erp.en_rama = si`, que pone rama_prueba) se niega a empezar, antes de tocar nada.
-- Formato de erp/pruebas/corre.py: termina en «FIN DE PRUEBAS» y cada línea acaba en «→ ok» o «→ FALLA». Todo se deshace con el raise final.
-- FIXTURE PROPIO (la rama recibe solo la estructura), como postgres y SIN sesión (así pasa el candado de alta de `usuarios`):
--   empresa zz_ubusca con dos proyectos («ZZ-UBUSCA Jardín Ñandú» y «ZZ-UBUSCA Otro»); un super_admin global; el agente A ACOTADO
--   al primero (como los reales); una persona en auth.users sin fila en usuarios (no es del equipo); 12 unidades en el primero
--   (una con tildes en el código) y una en el segundo. La herramienta del menú no es barrera aquí: lo que el agente ve lo decide la
--   RLS de `unidades`, la misma que ya le deja leer esas filas en Proyectos (se revisa al pasar a DEFINER en L6).
-- destructivo-ok: prueba en transacción que termina en raise (rollback); solo en rama; apaga los disparadores de usuario de `proyectos` solo para un renombrado dentro de la transacción
create temp table _tp (et text primary key, uid uuid, em text);
create or replace function pg_temp.l(c boolean, t text) returns text language sql as $f$
  select E'\n' || replace(t, E'\n', ' ') || case when coalesce(c, false) then ' → ok' else ' → FALLA' end
$f$;
create or replace function pg_temp.val(p_uid uuid, p_email text, p_sql text, p_rol text default 'authenticated') returns text language plpgsql as $f$
declare t text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', p_rol, 'email', p_email)::text, true);
  execute format('set local role %I', p_rol);
  begin execute p_sql into t;
  exception when others then t := 'ERR' || sqlstate || ':' || left(sqlerrm, 200); end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return coalesce(t, 'null');
end $f$;
create or replace function pg_temp.err(t text) returns text language sql immutable as $f$ select case when t like 'ERR%' then substr(t, 4, 5) end $f$;
create or replace function pg_temp.e(t text) returns text language sql immutable as $f$ select case when t like 'ERR%' then left(t, 110) else t end $f$;

insert into _tp values ('jv', gen_random_uuid(), 'zz-ubusca-super@prueba.invalid'),
                       ('A',  gen_random_uuid(), 'zz-ubusca-agente-a@prueba.invalid'),
                       ('X',  gen_random_uuid(), 'zz-ubusca-fuera@prueba.invalid');   -- en auth.users, sin fila en usuarios

do $todo$
declare
  r text := ''; rp text := ''; v text; v2 text; x record; t0 timestamptz; ms numeric;
  jv _tp; a _tp; fx _tp;
  p1 uuid; p2 uuid; uTilde uuid; uOtro uuid; i int;
  c_emp constant text := 'zz_ubusca';
  c_fin constant text := 'FIN DE PRUEBAS UNIDADES_BUSCA (se deshace todo):%';
begin
  if coalesce(current_setting('erp.en_rama', true), '') <> 'si' then
    raise exception 'FIN DE PRUEBAS UNIDADES_BUSCA:%', E'\nP0 esta prueba monta filas: solo corre en rama → FALLA';
  end if;
  select * into jv from _tp where et = 'jv'; select * into a from _tp where et = 'A'; select * into fx from _tp where et = 'X';

  -- ============================================================ N. cómo nace: INVOKER, search_path vacío, solo authenticated
  select p.prosecdef, p.proconfig, has_function_privilege('anon', p.oid, 'execute') anon,
         has_function_privilege('public', p.oid, 'execute') pub, has_function_privilege('authenticated', p.oid, 'execute') auth,
         has_function_privilege('service_role', p.oid, 'execute') srv, pg_get_functiondef(p.oid) def
    into x from pg_proc p where p.oid = 'public.unidades_busca(text)'::regprocedure;
  r := r || pg_temp.l(not x.prosecdef and x.proconfig @> array['search_path=""']::text[] and not x.anon and not x.pub and not x.srv and x.auth,
                      'N1 INVOKER, search_path vacío, solo authenticated (definer=' || x.prosecdef::text || ' anon=' || x.anon::text
                      || ' public=' || x.pub::text || ' service_role=' || x.srv::text || ' authenticated=' || x.auth::text || ')');
  r := r || pg_temp.l(x.def ~ 'normaliza_busqueda' and x.def ~* 'limit 10' and x.def !~* 'ilike',
                      'N2 compara con la pieza común, sin ilike, como mucho 10');

  -- ============================================================ P. montaje del fixture propio (como postgres, SIN sesión)
  perform set_config('request.jwt.claims', '', true);
  begin
    insert into public.empresas (clave, nombre) values (c_emp, 'ZZ-UBUSCA Empresa');
    insert into public.proyectos (nombre, slug, empresa, activo) values ('ZZ-UBUSCA Jardín Ñandú', 'zz-ubusca-jardin', c_emp, true) returning id into p1;
    insert into public.proyectos (nombre, slug, empresa, activo) values ('ZZ-UBUSCA Otro', 'zz-ubusca-otro', c_emp, true) returning id into p2;
    insert into auth.users (id, instance_id, email, aud, role) values
      (jv.uid, '00000000-0000-0000-0000-000000000000', jv.em, 'authenticated', 'authenticated'),
      (a.uid,  '00000000-0000-0000-0000-000000000000', a.em,  'authenticated', 'authenticated'),
      (fx.uid, '00000000-0000-0000-0000-000000000000', fx.em, 'authenticated', 'authenticated');
    insert into public.usuarios (user_id, email, nombre, rol, ambito, empresas, proyectos, proyectos_supervisados, herramientas, tipos_contrato, activo) values
      (jv.uid, jv.em, 'ZZ-UBUSCA Super admin', 'super_admin', 'global', '{}'::text[], '{}'::uuid[], '{}'::uuid[], '{}'::text[], '{}'::text[], true),
      (a.uid,  a.em,  'ZZ-UBUSCA Agente A',    'agente',      'global', array[c_emp], array[p1],   '{}'::uuid[], '{proyectos}'::text[], '{contrato_general}'::text[], true);
    insert into public.unidades (codigo, proyecto, proyecto_id, tipo) values ('ZZU-Ñ1 Bambú', 'ZZ-UBUSCA Jardín Ñandú', p1, 'parcela') returning id into uTilde;
    for i in 1..11 loop
      insert into public.unidades (codigo, proyecto, proyecto_id, tipo) values ('ZZU-' || lpad(i::text, 2, '0'), 'ZZ-UBUSCA Jardín Ñandú', p1, 'parcela');
    end loop;
    insert into public.unidades (codigo, proyecto, proyecto_id, tipo) values ('ZZU-OTRO-1', 'ZZ-UBUSCA Otro', p2, 'parcela') returning id into uOtro;
  exception when others then
    raise exception using message = replace(c_fin, '%', r || pg_temp.l(false, 'P0 montaje del fixture propio: ' || sqlstate || ' ' || left(sqlerrm, 300)
                                                                 || ' [session_user=' || session_user::text || ']'));
  end;
  rp := rp || pg_temp.l(p1 is not null and p2 is not null and uTilde is not null and uOtro is not null,
                        'P0 fixture propio montado: empresa, 2 proyectos, 3 personas, 13 unidades [session_user=' || session_user::text || ']');
  perform set_config('request.jwt.claims', json_build_object('sub', a.uid, 'role', 'authenticated', 'email', a.em)::text, true);
  rp := rp || pg_temp.l(public.es_agente() and not public.es_admin(), 'P1 A es agente activo y no es admin');
  rp := rp || pg_temp.l(public.unidad_visible(p1) and not public.unidad_visible(p2), 'P2 A ve el proyecto 1 y no el 2 (unidad_visible)');
  perform set_config('request.jwt.claims', json_build_object('sub', fx.uid, 'role', 'authenticated', 'email', fx.em)::text, true);
  rp := rp || pg_temp.l(not public.es_agente(), 'P3 X no es del equipo (es_agente = false)');
  perform set_config('request.jwt.claims', '', true);
  v := pg_temp.val(a.uid, a.em, 'select (select auth.uid())::text || ''|'' || current_user::text');
  rp := rp || pg_temp.l(v = a.uid::text || '|authenticated', 'S0 la sesión simulada es la de A con el rol authenticated (' || pg_temp.e(v) || ')');
  r := r || rp;
  if rp ~ 'FALLA' then
    raise exception using message = replace(c_fin, '%', r || pg_temp.l(false, 'PARADA: el fixture o la sesión no valen; los casos U no se corren'));
  end if;

  -- ============================================================ U. lo que devuelve, por perfil
  v := pg_temp.val(a.uid, a.em, format('select count(*) from public.unidades_busca(%L) where id = %L', 'zzu n1 bambu', uTilde));
  r := r || pg_temp.l(v = '1', 'U1 ENTRA: A encuentra «ZZU-Ñ1 Bambú» tecleando «zzu n1 bambu» (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, format('select proyecto || ''|'' || proyecto_id from public.unidades_busca(%L) where id = %L', 'jardin nandu', uTilde));
  r := r || pg_temp.l(v = 'ZZ-UBUSCA Jardín Ñandú|' || p1::text, 'U2 ENTRA: por el nombre del proyecto sin tildes, y trae el id del proyecto (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, 'select count(*) from public.unidades_busca(''zzu otro'')');
  r := r || pg_temp.l(v = '0', 'U3 NIEGA: A no recibe la unidad del proyecto que no ve (la RLS de unidades decide) (' || pg_temp.e(v) || ')');
  v := pg_temp.val(jv.uid, jv.em, format('select count(*) from public.unidades_busca(%L) where id = %L', 'zzu otro', uOtro));
  r := r || pg_temp.l(v = '1', 'U4 ENTRA: el super admin sí la recibe (' || pg_temp.e(v) || ')');
  v  := pg_temp.val(a.uid, a.em, 'select count(*) from public.unidades_busca(''zz ubusca'')');
  r := r || pg_temp.l(v = '10', 'U5 tope: con 12 que casan devuelve 10 (' || pg_temp.e(v) || ')');
  v  := pg_temp.val(a.uid, a.em, 'select string_agg(id::text, '','' order by id) from public.unidades_busca(''zzu 0'')');
  v2 := pg_temp.val(a.uid, a.em, 'select string_agg(id::text, '','' order by id) from public.unidades where codigo like ''ZZU-0%''');
  r := r || pg_temp.l(v = v2 and v <> 'null', 'U6 lo que devuelve a A es exactamente lo que A lee de unidades con su RLS');
  v := pg_temp.val(a.uid, a.em, 'select count(*) from public.unidades_busca(''z'')');
  r := r || pg_temp.l(v = '0', 'U7 NIEGA: menos de 2 letras, nada (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, format('select count(*) from public.unidades_busca(%L)', 'z'''''));
  r := r || pg_temp.l(v = '0', 'U8 NIEGA: «z» con dos apóstrofos plegado es 1 letra: nada (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, 'select count(*) from public.unidades_busca(''%%'')');
  r := r || pg_temp.l(v = '0', 'U9 NIEGA: un «%%» tecleado no es comodín (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, format('select count(*) from public.unidades_busca(%L)', repeat('x', 5000) || 'zzu'));
  r := r || pg_temp.l(v = '0', 'U10 un texto enorme se corta a 200 en el servidor y no rompe (' || pg_temp.e(v) || ')');
  v := pg_temp.val(fx.uid, fx.em, 'select count(*) from public.unidades_busca(''zzu'')');
  r := r || pg_temp.l(v = '0', 'U11 NIEGA: quien no es del equipo no recibe nada (' || pg_temp.e(v) || ')');
  v := pg_temp.val(null, null, 'select count(*) from public.unidades_busca(''zzu'')', 'anon');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'U12 NIEGA: anon no puede llamarla (' || pg_temp.e(v) || ')');

  -- ============================================================ R. el nombre de HOY del proyecto (la unidad guarda una copia)
  -- Se renombra con los disparadores de `proyectos` apagados (propaga_nombre_proyecto reescribiría la copia de la unidad y R1
  -- pasaría sin el join: buscador de fallos, 17-oct). Así la copia queda vieja a propósito y solo el join da el nombre nuevo.
  alter table public.proyectos disable trigger user;
  update public.proyectos set nombre = 'ZZ-UBUSCA Kebun Baru' where id = p1;
  alter table public.proyectos enable trigger user;
  r := r || pg_temp.l((select proyecto from public.unidades where id = uTilde) = 'ZZ-UBUSCA Jardín Ñandú',
                      'R0 la copia de la unidad sigue con el nombre viejo (el caso mide el join, no la copia)');
  v := pg_temp.val(a.uid, a.em, format('select proyecto from public.unidades_busca(%L) where id = %L', 'kebun baru', uTilde));
  r := r || pg_temp.l(v = 'ZZ-UBUSCA Kebun Baru', 'R1 ENTRA: renombrado el proyecto, se encuentra por el nombre nuevo y lo enseña (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, format('select count(*) from public.unidades_busca(%L) where id = %L', 'jardin nandu', uTilde));
  r := r || pg_temp.l(v = '0', 'R3 NIEGA: ya no sale por el nombre viejo que guarda la copia (' || pg_temp.e(v) || ')');
  v := pg_temp.val(a.uid, a.em, format('select count(*) from public.unidades_busca(%L) where id = %L', 'zzu n1', uTilde));
  r := r || pg_temp.l(v = '1', 'R2 ENTRA: el enlace no depende del nombre: sigue saliendo por su código (' || pg_temp.e(v) || ')');

  -- ============================================================ T. coste con el volumen de Lawang (Backend, 17-oct: la RLS de unidades
  -- llama a proyecto_visible por fila; la rama trae la estructura sin datos, así que el volumen lo pone el fixture: 600 más en p1)
  insert into public.unidades (codigo, proyecto, proyecto_id, tipo)
    select 'ZZU-V' || lpad(g::text, 4, '0'), 'ZZ-UBUSCA Kebun Baru', p1, 'parcela' from generate_series(1, 600) g;
  t0 := clock_timestamp();
  v := pg_temp.val(a.uid, a.em, 'select count(*) from public.unidades_busca(''zzu v05'')');
  ms := round(extract(epoch from clock_timestamp() - t0) * 1000);
  r := r || pg_temp.l(v = '10' and ms < 300, 'T1 agente acotado con 612 unidades visibles: ' || pg_temp.e(v) || ' filas en ' || ms || ' ms (tope 300; por encima, la policy de L6, no un índice)');
  t0 := clock_timestamp();
  v := pg_temp.val(a.uid, a.em, 'select count(*) from public.unidades_busca(''nada que case'')');
  ms := round(extract(epoch from clock_timestamp() - t0) * 1000);
  r := r || pg_temp.l(v = '0' and ms < 300, 'T2 sin coincidencias recorre todo: ' || pg_temp.e(v) || ' filas en ' || ms || ' ms (tope 300)');

  raise exception 'FIN DE PRUEBAS UNIDADES_BUSCA (se deshace todo):%', r;
end $todo$;
