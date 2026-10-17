-- Prueba de H7 (17-oct-2026, migracion 20261017200000_notificaciones_leidas): un aviso se marca como leido al pulsarlo.
-- Cada llamada va con el rol REAL (`set local role authenticated` + las claims de la persona, armazon de cliente_notas.sql) y cada
-- NO lleva al lado un SI que solo cambia en lo que se prueba. Revision previa #429 (Seguridad y Backend):
-- L0 la policy de notificaciones que hay en la base es la que se dio por buena (TO lw_lector, tres ramas): la RPC la PREGUNTA, no la copia.
-- L1 A marca un aviso suyo: de 0 a 1, y notificaciones_datos se lo devuelve con leida = true. L2 A marca uno de B: nada.
-- L3 un id que no existe responde EXACTAMENTE igual que uno ajeno (no se sondean ids). L4 repetir no duplica.
-- L5 lo que marca A no sale leido para otro. L6 admin global sin «comisiones»: marca un aviso general y no una solicitud_pago.
-- L7 admin de empresa: marca el de un contrato de SU empresa y no el de otra. L8 mas de 50 ids se rechaza; vacio y nulo no hacen nada.
-- L9 anonimo sin permiso (RPC y lectura). L10 la tabla no se lee ni se escribe directo. L11 quien no esta en usuarios: nada, sin error.
-- L12 borrar el aviso borra su marca. L13 forma: dueños, DEFINER, search_path y permisos de las tres funciones y de la tabla.
-- !! CREA USUARIOS, CONTRATOS Y AVISOS: SOLO EN RAMA, NUNCA EN LA BASE VIVA.
--    python erp/rama_prueba.py lawang --lawang <copia de Lawang> --aplica 20261017200000_notificaciones_leidas.sql --prueba notificaciones_leidas.sql
--    Si el volcado es anterior a 20261016112502_law338_l5_revoke (el nombre del volcado va en hora local +8; las versiones, en UTC),
--    van antes en el mismo --aplica las aplicadas en la viva despues del volcado: sin ellas L0 sale TO public y no es la base de verdad.
-- Formato de erp/pruebas/corre.py: termina en «FIN DE PRUEBAS» y cada linea acaba en «→ ok» o «→ FALLA». Todo va marcado ZZ-NL.
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); solo en rama
create temp table _tp (et text primary key, uid uuid, em text);
create or replace function pg_temp.l(c boolean, t text) returns text language sql as $f$
  select E'\n' || replace(t, E'\n', ' ') || case when coalesce(c, false) then ' → ok' else ' → FALLA' end
$f$;
-- ejecuta p_sql con la sesion de quien se dice (rol authenticated o anon): el resultado en texto, o el error
create or replace function pg_temp.val(p_uid uuid, p_email text, p_sql text, p_rol text default 'authenticated') returns text language plpgsql as $f$
declare t text;
begin
  perform set_config('request.jwt.claims', case when p_uid is null then '' else
          json_build_object('sub', p_uid, 'role', p_rol, 'email', p_email)::text end, true);
  execute 'set local role ' || p_rol;
  begin execute p_sql into t;
  exception when others then t := 'ERR' || sqlstate || ':' || left(sqlerrm, 200); end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return coalesce(t, '(null)');
end $f$;

insert into _tp values ('A',  gen_random_uuid(), 'zz-nl-agente-a@prueba.invalid'),
                       ('B',  gen_random_uuid(), 'zz-nl-agente-b@prueba.invalid'),
                       ('AD', gen_random_uuid(), 'zz-nl-admin@prueba.invalid'),
                       ('AE', gen_random_uuid(), 'zz-nl-admin-empresa@prueba.invalid'),
                       ('P',  gen_random_uuid(), 'zz-nl-sin-ficha@prueba.invalid');

do $todo$
declare
  r text := ''; v text; v2 text; n bigint;
  a _tp; b _tp; ad _tp; ae _tp; p _tp;
  -- empresas.clave es ^[a-z][a-z0-9_]{2,40}$ (20261007000500): en minusculas (ensayo ca31f63d, 23514 con 'ZZNL1')
  c_e1 constant text := 'zz_nl_e1'; c_e2 constant text := 'zz_nl_e2';
  p1 uuid; p2 uuid; k1 uuid; k2 uuid;
  nA uuid; nB uuid; nG uuid; nSP uuid; nE1 uuid; nE2 uuid; nP uuid;
  q_leida constant text := 'select coalesce((select x->>''leida'' from jsonb_array_elements((public.notificaciones_datos(400))->''notificaciones'') x where x->>''id'' = %L), ''no-la-ve'')';
  c_fin constant text := 'FIN DE PRUEBAS AVISOS LEIDOS (se deshace todo):%';
  x record;
begin
  if coalesce(current_setting('erp.en_rama', true), '') <> 'si' then
    raise exception 'FIN DE PRUEBAS AVISOS LEIDOS:%', E'\nP0 esta prueba crea usuarios y avisos: solo corre en rama → FALLA';
  end if;
  select * into a from _tp where et = 'A'; select * into b from _tp where et = 'B';
  select * into ad from _tp where et = 'AD'; select * into ae from _tp where et = 'AE'; select * into p from _tp where et = 'P';

  -- ============================================================ L0 la policy que la RPC pregunta (condicion previa de Seguridad #429)
  -- el oid 0 de polroles es PUBLIC y no tiene fila en pg_roles: se escribe «public» (ensayo ca31f63d salio «TO ,» = la policy de antes de L5)
  select array_to_string(array(select coalesce((select ro.rolname::text from pg_roles ro where ro.oid = o),
                                               case when o = 0 then 'public' else '#' || o::text end)
                                 from unnest(pl.polroles) o order by 1), ',') as roles,
         pg_get_expr(pl.polqual, pl.polrelid) as qual into x
    from pg_policy pl where pl.polrelid = 'public.notificaciones'::regclass and pl.polcmd in ('r', '*') order by pl.polname limit 1;
  n := (select count(*) from pg_policy where polrelid = 'public.notificaciones'::regclass);
  r := r || pg_temp.l(x.roles = 'lw_lector' and x.qual ~ 'es_admin' and x.qual ~ 'solicitud_pago' and x.qual ~ 'email'
                      and x.qual ~ 'mis_contratos_admin_empresa' and n = 1,
                      'L0 notificaciones tiene UNA policy (hay ' || n || '), TO ' || coalesce(x.roles, '?') || ', con sus tres ramas (admin sin solicitud_pago, destinatario, admin de empresa)'
                      || case when x.qual is null then ' [sin policy de lectura]'
                              when x.qual ~ 'mis_contratos_admin_empresa' and x.qual ~ 'email' and x.qual ~ 'es_admin' then '' else ' [falta alguna rama]' end
                      || case when x.roles = 'public' then ' [TO public = antes de 20261016112502_law338_l5_revoke: aplicala antes en la rama]' else '' end);

  -- ============================================================ P. montaje (como postgres, SIN sesion)
  perform set_config('request.jwt.claims', '', true);
  begin
    insert into public.empresas (clave, nombre) values (c_e1, 'ZZ-NL Empresa uno'), (c_e2, 'ZZ-NL Empresa dos');
    insert into public.proyectos (nombre, slug, empresa, activo) values ('ZZ-NL Proyecto uno', 'zz-nl-proyecto-uno', c_e1, true) returning id into p1;
    insert into public.proyectos (nombre, slug, empresa, activo) values ('ZZ-NL Proyecto dos', 'zz-nl-proyecto-dos', c_e2, true) returning id into p2;
    insert into auth.users (id, instance_id, email, aud, role)
      select t.uid, '00000000-0000-0000-0000-000000000000', t.em, 'authenticated', 'authenticated' from _tp t;
    insert into public.usuarios (user_id, email, nombre, rol, ambito, empresas, proyectos, proyectos_supervisados, herramientas, tipos_contrato, activo) values
      (a.uid,  a.em,  'ZZ-NL Agente A',          'agente',        'global',  '{}'::text[],   '{}'::uuid[], '{}'::uuid[], '{}'::text[], '{}'::text[], true),
      (b.uid,  b.em,  'ZZ-NL Agente B',          'agente',        'global',  '{}'::text[],   '{}'::uuid[], '{}'::uuid[], '{}'::text[], '{}'::text[], true),
      (ad.uid, ad.em, 'ZZ-NL Admin sin comisiones','admin',       'global',  '{}'::text[],   '{}'::uuid[], '{}'::uuid[], '{}'::text[], '{}'::text[], true),
      (ae.uid, ae.em, 'ZZ-NL Admin de empresa',  'admin_empresa', 'empresa', array[c_e1],    '{}'::uuid[], '{}'::uuid[], '{}'::text[], '{}'::text[], true);
    alter table public.contratos disable trigger user;
    insert into public.contratos (tipo, numero, comprador_nombre, datos, proyecto_id, proyecto_nombre, creado_por, created_at)
      values ('contrato_general', 'ZZNL-0001', 'ZZ-NL Comprador uno', '{}'::jsonb, p1, 'ZZ-NL Proyecto uno', ad.em, now()) returning id into k1;
    insert into public.contratos (tipo, numero, comprador_nombre, datos, proyecto_id, proyecto_nombre, creado_por, created_at)
      values ('contrato_general', 'ZZNL-0002', 'ZZ-NL Comprador dos', '{}'::jsonb, p2, 'ZZ-NL Proyecto dos', ad.em, now()) returning id into k2;
    alter table public.contratos enable trigger user;
    insert into public.notificaciones (tipo, titulo, destinatario) values ('zz_prueba', 'ZZ-NL para A', a.em) returning id into nA;
    insert into public.notificaciones (tipo, titulo, destinatario) values ('zz_prueba', 'ZZ-NL para B', b.em) returning id into nB;
    insert into public.notificaciones (tipo, titulo) values ('zz_prueba', 'ZZ-NL general') returning id into nG;
    insert into public.notificaciones (tipo, titulo) values ('solicitud_pago', 'ZZ-NL solicitud de pago') returning id into nSP;
    insert into public.notificaciones (tipo, titulo, contrato_id) values ('zz_prueba', 'ZZ-NL contrato empresa uno', k1) returning id into nE1;
    insert into public.notificaciones (tipo, titulo, contrato_id) values ('zz_prueba', 'ZZ-NL contrato empresa dos', k2) returning id into nE2;
    insert into public.notificaciones (tipo, titulo, destinatario) values ('zz_prueba', 'ZZ-NL para quien no tiene ficha', p.em) returning id into nP;
    r := r || pg_temp.l(true, 'P montaje: 2 empresas, 2 contratos, 5 personas (2 agentes, admin sin comisiones, admin de empresa uno, sin ficha) y 7 avisos');
  exception when others then
    raise exception using message = replace(c_fin, '%', r || pg_temp.l(false, 'P montaje: ' || sqlstate || ' ' || left(sqlerrm, 300)
                                                                 || ' [session_user=' || session_user::text || ']'));
  end;
  perform set_config('request.jwt.claims', json_build_object('sub', ae.uid, 'role', 'authenticated', 'email', ae.em)::text, true);
  r := r || pg_temp.l(not public.es_admin() and k1 = any (public.mis_contratos_admin_empresa()) and not (k2 = any (public.mis_contratos_admin_empresa())),
                      'P1 el admin de empresa NO es admin global y solo tiene el contrato de su empresa');
  perform set_config('request.jwt.claims', json_build_object('sub', ad.uid, 'role', 'authenticated', 'email', ad.em)::text, true);
  r := r || pg_temp.l(public.es_admin() and not public.puede('comisiones'), 'P2 el admin global no tiene «comisiones»');
  perform set_config('request.jwt.claims', '', true);

  -- ============================================================ L1 / L2 / L3 / L4 el agente
  v := pg_temp.val(a.uid, a.em, format(q_leida, nA));
  r := r || pg_temp.l(v = 'false', 'L1a antes de pulsar, A ve su aviso sin leer (' || v || ')');
  v := pg_temp.val(a.uid, a.em, format('select public.notificaciones_marca_leidas(array[%L]::uuid[])::text', nA));
  r := r || pg_temp.l(v not like 'ERR%' and (select count(*) from public.notificaciones_leidas where user_id = a.uid and notificacion_id = nA) = 1,
                      'L1 A marca su aviso: de 0 a 1 fila (' || left(v, 60) || ')');
  v := pg_temp.val(a.uid, a.em, format(q_leida, nA));
  r := r || pg_temp.l(v = 'true', 'L1b notificaciones_datos se lo devuelve con leida = true: lw_lector lee la tabla (' || v || ')');
  v := pg_temp.val(a.uid, a.em, format('select public.notificaciones_marca_leidas(array[%L]::uuid[])::text', nB));
  v2 := pg_temp.val(a.uid, a.em, format('select public.notificaciones_marca_leidas(array[%L]::uuid[])::text', gen_random_uuid()));
  r := r || pg_temp.l(v not like 'ERR%' and not exists (select 1 from public.notificaciones_leidas where notificacion_id = nB),
                      'L2 A marca el aviso de B: nada (' || left(v, 60) || ')');
  r := r || pg_temp.l(v = v2, 'L3 un id que no existe responde igual que uno ajeno [' || left(v, 40) || '] = [' || left(v2, 40) || ']');
  v := pg_temp.val(a.uid, a.em, format('select public.notificaciones_marca_leidas(array[%L, %L]::uuid[])::text', nA, nA));
  r := r || pg_temp.l(v not like 'ERR%' and (select count(*) from public.notificaciones_leidas where user_id = a.uid) = 1,
                      'L4 repetir (y repetido en la misma llamada) deja una sola fila (' || left(v, 60) || ')');

  -- ============================================================ L5 / L6 el admin global sin comisiones
  v := pg_temp.val(ad.uid, ad.em, format(q_leida, nA));
  r := r || pg_temp.l(v = 'false', 'L5 el admin ve el aviso de A, y para el sigue sin leer (las marcas son de cada uno) (' || v || ')');
  v := pg_temp.val(ad.uid, ad.em, format('select public.notificaciones_marca_leidas(array[%L, %L]::uuid[])::text', nG, nSP));
  r := r || pg_temp.l(v not like 'ERR%' and exists (select 1 from public.notificaciones_leidas where user_id = ad.uid and notificacion_id = nG)
                      and not exists (select 1 from public.notificaciones_leidas where user_id = ad.uid and notificacion_id = nSP),
                      'L6 admin sin «comisiones»: marca el general y NO la solicitud_pago, que no ve (' || left(v, 60) || ')');
  v := pg_temp.val(ad.uid, ad.em, format(q_leida, nSP));
  r := r || pg_temp.l(v = 'no-la-ve', 'L6b y la lectura tampoco se la enseña (' || v || ')');

  -- ============================================================ L7 el admin de empresa
  v := pg_temp.val(ae.uid, ae.em, format('select public.notificaciones_marca_leidas(array[%L, %L, %L]::uuid[])::text', nE1, nE2, nG));
  r := r || pg_temp.l(v not like 'ERR%' and (select array_agg(notificacion_id) from public.notificaciones_leidas where user_id = ae.uid) = array[nE1],
                      'L7 admin de empresa: marca el aviso del contrato de su empresa, no el de la otra ni el general (' || left(v, 60) || ')');
  v := pg_temp.val(ae.uid, ae.em, 'select (' || format(q_leida, nE1) || ') || ''/'' || (' || format(q_leida, nE2) || ')');
  r := r || pg_temp.l(v = 'true/no-la-ve', 'L7b su lectura: el suyo leido, el de la otra empresa no lo ve (' || v || ')');

  -- ============================================================ L8 tope y vacios
  v := pg_temp.val(a.uid, a.em, 'select public.notificaciones_marca_leidas(array(select gen_random_uuid() from generate_series(1, 51)))::text');
  r := r || pg_temp.l(v like 'ERR22023:%', 'L8 51 ids se rechazan (' || left(v, 80) || ')');
  v := pg_temp.val(a.uid, a.em, 'select public.notificaciones_marca_leidas(array(select gen_random_uuid() from generate_series(1, 50)))::text');
  r := r || pg_temp.l(v not like 'ERR%', 'L8b 50 ids pasan (' || left(v, 60) || ')');
  v := pg_temp.val(a.uid, a.em, 'select public.notificaciones_marca_leidas(null)::text') || '|' ||
       pg_temp.val(a.uid, a.em, 'select public.notificaciones_marca_leidas(''{}''::uuid[])::text');
  r := r || pg_temp.l(v not like '%ERR%' and (select count(*) from public.notificaciones_leidas where user_id = a.uid) = 1,
                      'L8c nulo y vacio no hacen nada (' || left(v, 60) || ')');

  -- ============================================================ L9 anonimo
  v := pg_temp.val(null, null, format('select public.notificaciones_marca_leidas(array[%L]::uuid[])::text', nG), 'anon');
  r := r || pg_temp.l(v like 'ERR42501:%', 'L9 anonimo no puede marcar (' || left(v, 70) || ')');
  v := pg_temp.val(null, null, 'select public.notificaciones_datos(10)::text', 'anon');
  r := r || pg_temp.l(v like 'ERR42501:%', 'L9b anonimo no puede leer (' || left(v, 70) || ')');
  v := pg_temp.val(null, null, 'select public.notificaciones_marca_leidas(null)::text');
  r := r || pg_temp.l(v like 'ERR42501:%', 'L9c authenticated sin claims (sin sesion): 42501 (' || left(v, 70) || ')');

  -- ============================================================ L10 la tabla no se toca directo
  v := pg_temp.val(a.uid, a.em, 'select count(*)::text from public.notificaciones_leidas');
  r := r || pg_temp.l(v like 'ERR42501:%', 'L10 authenticated no lee la tabla directamente (' || left(v, 60) || ')');
  v := pg_temp.val(a.uid, a.em, format('insert into public.notificaciones_leidas (user_id, notificacion_id) values (%L, %L) returning 1::text', b.uid, nB));
  r := r || pg_temp.l(v like 'ERR42501:%', 'L10b authenticated no inserta directamente (ni a nombre de otro) (' || left(v, 60) || ')');
  v := pg_temp.val(a.uid, a.em, format('delete from public.notificaciones_leidas where user_id = %L returning 1::text', a.uid));
  r := r || pg_temp.l(v like 'ERR42501:%' and (select count(*) from public.notificaciones_leidas where user_id = a.uid) = 1,
                      'L10c authenticated no borra sus marcas directamente (' || left(v, 60) || ')');
  v := pg_temp.val(a.uid, a.em, 'select public._notificaciones_visibles(array[gen_random_uuid()])::text');
  r := r || pg_temp.l(v like 'ERR42501:%', 'L10d el ayudante no se puede llamar por la API (' || left(v, 60) || ')');

  -- ============================================================ L11 sin ficha en usuarios
  v := pg_temp.val(p.uid, p.em, format('select public.notificaciones_marca_leidas(array[%L]::uuid[])::text', nP));
  r := r || pg_temp.l(v not like 'ERR%' and not exists (select 1 from public.notificaciones_leidas where notificacion_id = nP),
                      'L11 quien no esta en usuarios ve su aviso pero no deja marca, sin error (' || left(v, 60) || ')');

  -- ============================================================ L12 cascada
  delete from public.notificaciones where id = nA;
  r := r || pg_temp.l(not exists (select 1 from public.notificaciones_leidas where notificacion_id = nA), 'L12 borrar el aviso borra su marca');

  -- ============================================================ L13 forma
  for x in select pr.proname, pr.prosecdef, pr.proconfig, pg_get_userbyid(pr.proowner) dueno,
                  has_function_privilege('anon', pr.oid, 'execute') anon, has_function_privilege('authenticated', pr.oid, 'execute') auth,
                  exists (select 1 from aclexplode(coalesce(pr.proacl, acldefault('f', pr.proowner))) ac where ac.grantee = 0) pub
             from pg_proc pr where pr.pronamespace = 'public'::regnamespace
              and pr.proname in ('notificaciones_datos', 'notificaciones_marca_leidas', '_notificaciones_visibles') loop
    r := r || pg_temp.l(x.prosecdef and x.proconfig @> array['search_path=""']::text[] and not x.anon and not x.pub
                        and case x.proname when '_notificaciones_visibles' then x.dueno = 'lw_lector' and not x.auth
                                           when 'notificaciones_datos' then x.dueno = 'lw_lector' and x.auth
                                           else x.dueno = 'postgres' and x.auth end,
                        'L13 ' || x.proname::text || ' definer=' || x.prosecdef::text || ' dueño=' || x.dueno || ' anon=' || x.anon::text
                        || ' public=' || x.pub::text || ' authenticated=' || x.auth::text);
  end loop;
  r := r || pg_temp.l(not has_table_privilege('authenticated', 'public.notificaciones_leidas', 'select,insert,update,delete')
                      and not has_table_privilege('anon', 'public.notificaciones_leidas', 'select,insert,update,delete')
                      and has_table_privilege('lw_lector', 'public.notificaciones_leidas', 'select')
                      and not has_table_privilege('lw_lector', 'public.notificaciones_leidas', 'insert,update,delete')
                      and (select relrowsecurity from pg_class where oid = 'public.notificaciones_leidas'::regclass),
                      'L13b la tabla: RLS, nada para anon ni authenticated, lw_lector solo lee');

  raise exception using message = replace(c_fin, '%', r);
end $todo$;
