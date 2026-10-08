-- Prueba de E10 «revisiones activas para el agente» (8-oct-2026). Se pega con la migracion 20261010000500 (E7 ya aplicada). Ensayo sin rastro: acaba en raise y todo se deshace.
-- NO inserta contratos. NO activa nada en produccion: toda activacion se deshace. Debe terminar con «FALLOS=0».
-- destructivo-ok: prueba en transaccion que termina en raise (rollback)
create temp table _t7 (et text primary key, uid uuid, em text);
create or replace function pg_temp.l(c boolean, t text) returns text language sql as $f$
  select case when coalesce(c, false) then 'OK    ' else 'FALLO ' end || t || E'\n'
$f$;
create or replace function pg_temp.val(p_uid uuid, p_email text, p_sql text, p_role text default 'authenticated') returns text language plpgsql as $f$
declare t text;
begin
  perform set_config('request.jwt.claims', case when p_role = 'anon' then json_build_object('role', 'anon')::text
                      else json_build_object('sub', p_uid, 'role', 'authenticated', 'email', p_email)::text end, true);
  execute format('set local role %I', p_role);
  begin execute p_sql into t;
  exception when others then t := 'ERR' || sqlstate || ':' || left(sqlerrm, 200); end;
  execute 'reset role';
  return t;
end $f$;
create or replace function pg_temp.err(t text) returns text language sql immutable as $f$ select case when t like 'ERR%' then substr(t, 4, 5) end $f$;
create or replace function pg_temp.u(t text) returns uuid language sql immutable as $f$ select case when t is null or t like 'ERR%' or t = '' then null else t::uuid end $f$;
-- ejecuta como postgres (sin rol) y devuelve el error si lo hay
create or replace function pg_temp.pg(p_sql text) returns text language plpgsql as $f$
declare t text;
begin
  begin execute p_sql into t; exception when others then t := 'ERR' || sqlstate || ':' || left(sqlerrm, 200); end;
  return t;
end $f$;

-- ejecuta una sentencia que no devuelve filas (insert/update) como postgres: 'OK' o el error
create or replace function pg_temp.run(p_sql text) returns text language plpgsql as $f$
begin
  begin execute p_sql; exception when others then return 'ERR' || sqlstate || ':' || left(sqlerrm, 200); end;
  return 'OK';
end $f$;

insert into _t7 select 'jv', user_id, email from public.usuarios where email = 'jvr.cervantes@gmail.com';
insert into _t7
  select (array['ae_L', 'se_L', 'ae_S', 'se_S', 'ctl_L', 'adm_G'])[rn], user_id, email
    from (select user_id, email, row_number() over (order by email) rn
            from (select user_id, email from public.usuarios where activo and ambito = 'global' and rol = 'agente' order by email limit 6) q) z;

do $todo$
declare
  r text := ''; v text; n bigint; fallos int; body text; idE uuid; idR1 uuid; idR2 uuid; idR3 uuid; idR4 uuid;
  ae_L _t7; se_L _t7; ae_S _t7; ctl_L _t7; jv _t7;
begin
  select * into jv from _t7 where et = 'jv'; select * into ae_L from _t7 where et = 'ae_L'; select * into se_L from _t7 where et = 'se_L'; select * into ae_S from _t7 where et = 'ae_S';
  select * into ctl_L from _t7 where et = 'ctl_L';
  perform set_config('request.jwt.claims', json_build_object('sub', jv.uid, 'role', 'authenticated', 'email', jv.em)::text, true);
  update public.usuarios set rol = 'admin_empresa', ambito = 'empresa', empresas = '{lawang}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{}', tipos_contrato = '{}' where user_id = ae_L.uid;
  update public.usuarios set rol = 'super_admin_empresa', ambito = 'empresa', empresas = '{lawang}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{}', tipos_contrato = '{}' where user_id = se_L.uid;
  update public.usuarios set rol = 'admin_empresa', ambito = 'empresa', empresas = '{sandal_woods}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{}', tipos_contrato = '{}' where user_id = ae_S.uid;
  update public.usuarios set rol = 'agente', ambito = 'global', empresas = '{lawang}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{}', tipos_contrato = '{}' where user_id = ctl_L.uid;

  -- A. exposicion
  r := r || pg_temp.l(has_function_privilege('authenticated', 'public.plantilla_contrato_revisiones_activas(text,text)', 'execute'), 'A1 authenticated ejecuta la RPC');
  r := r || pg_temp.l(not has_function_privilege('anon', 'public.plantilla_contrato_revisiones_activas(text,text)', 'execute') and not has_function_privilege('service_role', 'public.plantilla_contrato_revisiones_activas(text,text)', 'execute'), 'A2 anon y service_role no');
  select count(*) into n from pg_proc where proname = 'plantilla_contrato_revisiones_activas' and prosecdef and proconfig @> array['search_path=""'] and provolatile = 's';
  r := r || pg_temp.l(n = 1, 'A3 SECURITY DEFINER, search_path vacio, STABLE (solo lectura)');
  select count(*) into n from pg_class where relname in ('plantilla_contrato_versiones', 'plantilla_contrato_cuerpos', 'contrato_plantilla_version')
     and (has_table_privilege('authenticated', oid, 'select') or has_table_privilege('authenticated', oid, 'insert') or has_table_privilege('authenticated', oid, 'update') or has_table_privilege('authenticated', oid, 'delete') or has_table_privilege('anon', oid, 'select'));
  r := r || pg_temp.l(n = 0, 'A4 ningun GRANT directo sobre las tablas (' || n || ')');
  select count(*) into n from pg_proc p, unnest(p.proargmodes) m where p.proname = 'plantilla_contrato_revisiones_activas' and m = 't';
  r := r || pg_temp.l(n = 4, 'A5 devuelve exactamente 4 campos (' || n || ')');

  -- B. montaje: estandar activa, rev_1 activa, rev_2 activa y luego archivada, rev_3 solo borrador, rev_4 borrada
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_edicion(''lawang'', ''commercial_offer'')->>''cuerpo_html''');
  body := v;
  idE := pg_temp.u(pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_guarda_borrador(''lawang'', ''commercial_offer'', %L, ''E10 base'')', body)));
  v := pg_temp.val(se_L.uid, se_L.em, format('select (public.plantilla_contrato_activa(%L, ''Persona de Prueba'', true))->>''variante''', idE));
  r := r || pg_temp.l(v = 'estandar', 'B1 estandar activa (' || left(v, 40) || ')');
  idR1 := pg_temp.u(pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_revision_crea(''lawang'', ''commercial_offer'', %L, ''Revision de verano'', ''E10 prueba'')', idE)));
  idR2 := pg_temp.u(pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_revision_crea(''lawang'', ''commercial_offer'', %L, ''Revision archivada'', ''E10 prueba'')', idE)));
  idR3 := pg_temp.u(pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_revision_crea(''lawang'', ''commercial_offer'', %L, ''Solo borrador'', ''E10 prueba'')', idE)));
  idR4 := pg_temp.u(pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_revision_crea(''lawang'', ''commercial_offer'', %L, ''Revision borrada'', ''E10 prueba'')', idE)));
  v := pg_temp.val(se_L.uid, se_L.em, format('select (public.plantilla_contrato_activa(%L, ''Persona de Prueba'', true))->>''variante''', idR1));
  r := r || pg_temp.l(v = 'rev_1', 'B2 rev_1 activa (' || left(v, 40) || ')');
  v := pg_temp.val(se_L.uid, se_L.em, format('select (public.plantilla_contrato_activa(%L, ''Persona de Prueba'', true))->>''variante''', idR2));
  r := r || pg_temp.l(v = 'rev_2', 'B3 rev_2 activa (' || left(v, 40) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_revision_archiva(''lawang'', ''commercial_offer'', ''rev_2'')');
  r := r || pg_temp.l(v not like 'ERR%', 'B4 rev_2 archivada (' || left(coalesce(v, 'ok'), 60) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_revision_borra(''lawang'', ''commercial_offer'', ''rev_4'')');
  r := r || pg_temp.l(v not like 'ERR%', 'B5 rev_4 borrada (' || left(coalesce(v, 'ok'), 60) || ')');

  -- C. lo que ve cada quien
  v := pg_temp.val(ctl_L.uid, ctl_L.em, 'select string_agg(variante, '','' order by variante) from public.plantilla_contrato_revisiones_activas(''lawang'', ''commercial_offer'')');
  r := r || pg_temp.l(v = 'estandar,rev_1', 'C1 un agente normal de Lawang lee solo las ACTIVAS: estandar y rev_1; ni la archivada, ni el borrador, ni la borrada (' || coalesce(v, '?') || ')');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, format('select count(*) from public.plantilla_contrato_revisiones_activas(''lawang'', ''commercial_offer'') where (variante = ''rev_1'' and version_id = %L and nombre = ''Revision de verano'' and version > 0) or (variante = ''estandar'' and version_id = %L and nombre = ''Estándar'')', idR1, idE));
  r := r || pg_temp.l(v = '2', 'C2 con version_id, rotulo y numero de version correctos (' || coalesce(v, '?') || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select count(*) from public.plantilla_contrato_revisiones_activas(''lawang'', ''commercial_offer'')');
  r := r || pg_temp.l(v = '2', 'C3 la administracion ve lo mismo (' || v || ')');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, 'select count(*) from public.plantilla_contrato_revisiones_activas(''sandal_woods'', ''commercial_offer'')');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'C4 el agente de Lawang pidiendo otra empresa: 42501 (' || left(v, 60) || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, 'select count(*) from public.plantilla_contrato_revisiones_activas(''lawang'', ''commercial_offer'')');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'C5 el admin de OTRA empresa pidiendo Lawang: 42501 (' || left(v, 60) || ')');
  v := pg_temp.val(null, null, 'select count(*) from public.plantilla_contrato_revisiones_activas(''lawang'', ''commercial_offer'')', 'anon');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'C6 anon: sin permiso, 42501 (' || left(v, 60) || ')');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, 'select count(*) from public.plantilla_contrato_revisiones_activas(''lawang'', ''carta_reserva'')');
  r := r || pg_temp.l(v ~ '^[0-9]+$', 'C7 otra plantilla de la misma empresa responde sin error con lo suyo (' || coalesce(v, '?') || ')');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, 'select count(*) from public.plantilla_contrato_revisiones_activas(null, ''commercial_offer'')');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'C8 sin empresa no devuelve nada: 42501 (' || left(v, 40) || ')');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, 'select count(*) from public.plantilla_contrato_cuerpos');
  r := r || pg_temp.l(pg_temp.err(v) is not null, 'C9 y el agente sigue sin poder leer cuerpos por tabla (' || left(v, 40) || ')');

  fallos := (select count(*) from regexp_matches(r, 'FALLO', 'g'));
  raise exception E'INFORME E10\n%FALLOS=%', r, fallos;
end $todo$;
