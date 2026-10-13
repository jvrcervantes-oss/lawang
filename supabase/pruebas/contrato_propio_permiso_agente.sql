-- Prueba «contrato propio: se concede a un agente y el agente lo emite» (13-oct-2026, migracion 20261013015508_contratos_propios_conceder_emitir).
-- Se pega DESPUES de la migracion en la MISMA peticion, o sola cuando ya esta aplicada. Ensayo sin rastro: acaba en raise y todo se deshace
-- (el contrato propio de prueba, sus versiones, los permisos tocados y los contratos emitidos). Debe terminar con «FALLOS=0».
-- Reproduce el caso real del owner: un contrato propio de Lawang COPIADO de la Adenda, activado, concedido desde Permisos
-- (usuario_guarda_permisos, con la sesion del super admin) y emitido por un agente con SU sesion, una escritura cada vez.
-- destructivo-ok: prueba en transaccion que termina en raise (rollback)
create temp table _tp (et text primary key, uid uuid, em text);
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
  exception when others then t := 'ERR' || sqlstate || ':' || left(sqlerrm, 220); end;
  execute 'reset role';
  return t;
end $f$;
create or replace function pg_temp.err(t text) returns text language sql immutable as $f$ select case when t like 'ERR%' then substr(t, 4, 5) end $f$;
create or replace function pg_temp.pg(p_sql text) returns text language plpgsql as $f$
declare t text;
begin
  begin execute p_sql into t; exception when others then t := 'ERR' || sqlstate || ':' || left(sqlerrm, 220); end;
  return t;
end $f$;

insert into _tp select 'jv', user_id, email from public.usuarios where email = 'jvr.cervantes@gmail.com';
insert into _tp
  select (array['ag', 'ag2', 'agS', 'sae_S', 'libre'])[rn], user_id, email
    from (select user_id, email, row_number() over (order by email) rn
            from (select user_id, email from public.usuarios where activo and rol = 'agente' order by email limit 5) q) z;

do $todo$
declare
  r text := ''; v text; n bigint; fallos int;
  jv _tp; ag _tp; ag2 _tp; agS _tp; sae_S _tp; libre _tp;
  slug_f text; vid uuid; pL uuid; pS uuid; cid text; pago jsonb;
begin
  select * into jv from _tp where et = 'jv'; select * into ag from _tp where et = 'ag'; select * into ag2 from _tp where et = 'ag2';
  select * into agS from _tp where et = 'agS'; select * into sae_S from _tp where et = 'sae_S'; select * into libre from _tp where et = 'libre';
  r := r || pg_temp.l(jv.uid is not null and libre.uid is not null, 'P0 hay propietario y 5 agentes con los que montar las personas de la prueba');
  select id into pL from public.proyectos where activo and public.empresa_de_proyecto(id) = 'lawang' order by nombre limit 1;
  select id into pS from public.proyectos where activo and public.empresa_de_proyecto(id) = 'sandal_woods' order by nombre limit 1;
  r := r || pg_temp.l(pL is not null and pS is not null, 'P1 hay proyecto activo de Lawang y de Sandal Woods');

  -- Personas (las deshace el raise final). Las fija el propietario, como en f2_editor_e9_tipo_propio.sql.
  perform set_config('request.jwt.claims', json_build_object('sub', jv.uid, 'role', 'authenticated', 'email', jv.em)::text, true);
  update public.usuarios set rol = 'agente', ambito = 'global', empresas = '{lawang}', proyectos = array[pL], proyectos_supervisados = '{}', herramientas = '{contratos}', tipos_contrato = '{carta_reserva}' where user_id in (ag.uid, ag2.uid);
  update public.usuarios set rol = 'agente', ambito = 'global', empresas = '{sandal_woods}', proyectos = array[pS], proyectos_supervisados = '{}', tipos_contrato = '{carta_reserva}' where user_id = agS.uid;
  update public.usuarios set rol = 'super_admin_empresa', ambito = 'empresa', empresas = '{sandal_woods}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{}', tipos_contrato = '{}' where user_id = sae_S.uid;
  update public.usuarios set rol = 'agente', ambito = 'global', empresas = '{}', proyectos = '{}', proyectos_supervisados = '{}', tipos_contrato = '{carta_reserva}' where user_id = libre.uid;

  -- ============================================================ A. el contrato propio del owner: copia de la Adenda, activado
  v := pg_temp.val(jv.uid, jv.em, 'select public.plantilla_contrato_nuevo_crea(''lawang'', ''Furniture Package Purchase Commitment (prueba)'', ''copia'', ''adenda'')::text');
  r := r || pg_temp.l(v !~ '^ERR', 'A0 el super admin crea un contrato propio de Lawang copiando la Adenda (' || left(v, 100) || ')');
  slug_f := (v::jsonb) ->> 'slug'; vid := ((v::jsonb) ->> 'version_id')::uuid;
  select count(*) into n from public.plantilla_contrato_versiones where id = vid and activable;
  r := r || pg_temp.l(n = 1, 'A1 su borrador v2 es activable (copia de la Adenda sin texto de ejemplo)');
  v := pg_temp.pg(format('update public.plantilla_contrato_versiones set estado = ''activa'', activado_por = ''prueba'', activado_en = now(), confirmacion_nombre = ''Furniture'', confirmacion_texto = ''prueba'' where id = %L returning 1', vid));
  r := r || pg_temp.l(v = '1', 'A2 se activa su version (' || left(v, 120) || ')');
  v := pg_temp.val(jv.uid, jv.em, format('select count(*) from public.plantilla_contratos_propios_activos(''lawang'') where slug = %L', slug_f));
  r := r || pg_temp.l(v = '1', 'A3 sale en la lista que pinta Permisos (plantilla_contratos_propios_activos) (' || left(v, 60) || ')');

  -- ============================================================ G. conceder desde Permisos y emitir
  -- El agente guarda por contrato_guarda, como contracts/app.html (el navegador no inserta en `contratos`: no tiene GRANT).
  pago := jsonb_build_object('tipo', slug_f, 'datos', jsonb_build_object('fields', jsonb_build_object(
            'proyecto_nombre', (select nombre from public.proyectos where id = pL), 'adq1_nombre', 'Comprador de prueba')));
  v := pg_temp.val(ag.uid, ag.em, format('select public.contrato_guarda(null, %L::jsonb)::text', pago));
  r := r || pg_temp.l(pg_temp.err(v) = '42501' and v ~ 'No tienes permiso para emitir', 'G0 ANTES de concederlo, el agente no lo emite (' || left(v, 100) || ')');
  v := pg_temp.val(jv.uid, jv.em, format('select public.usuario_guarda_permisos(%L, %L::jsonb)::text', ag.uid, json_build_object('tipos_contrato', array['carta_reserva', slug_f])));
  r := r || pg_temp.l(v is null or v !~ '^ERR', 'G1 el super admin se lo concede desde Permisos (' || coalesce(left(v, 100), 'ok') || ')');
  select count(*) into n from public.usuarios where user_id = ag.uid and slug_f = any (tipos_contrato);
  r := r || pg_temp.l(n = 1, 'G1b queda guardado en usuarios.tipos_contrato');
  v := pg_temp.val(ag.uid, ag.em, format('select public.contrato_guarda(null, %L::jsonb)::text', pago));
  r := r || pg_temp.l(v !~ '^ERR', 'G2 el agente con el permiso EMITE el contrato propio con su sesion (contrato_guarda) (' || left(v, 100) || ')');
  cid := case when v !~ '^ERR' then (v::jsonb) ->> 'id' end;
  select count(*) into n from public.contratos where id::text = cid and numero ~ '^CX\d{5}$' and proyecto_id = pL;
  r := r || pg_temp.l(n = 1, 'G2b con numero de la serie CX y en el proyecto de Lawang');
  v := pg_temp.val(ag.uid, ag.em, format('select public.plantilla_contrato_fija(%L, %L)::text', cid, vid));
  r := r || pg_temp.l(v is null or v !~ '^ERR', 'G2c el agente fija su contrato a la version activa (lo que hace contracts/app.html al guardar) (' || coalesce(left(v, 100), 'ok') || ')');
  v := pg_temp.val(ag2.uid, ag2.em, format('select public.contrato_guarda(null, %L::jsonb)::text', pago));
  r := r || pg_temp.l(pg_temp.err(v) = '42501' and v ~ 'No tienes permiso para emitir', 'G3 otro agente SIN el permiso no lo emite (' || left(v, 100) || ')');
  v := pg_temp.val(jv.uid, jv.em, format('select public.usuario_guarda_permisos(%L, %L::jsonb)::text', ag.uid, json_build_object('tipos_contrato', array['carta_reserva', slug_f], 'nombre', 'Prueba')));
  r := r || pg_temp.l(v is null or v !~ '^ERR', 'G4 volver a guardar la ficha con lo que ya tiene pasa (solo se mira lo añadido) (' || coalesce(left(v, 100), 'ok') || ')');

  -- G5: un contrato NUEVO con un campo propio `cx_` tambien se guarda por la pantalla (mismo fallo de orden de triggers: antes
  -- «Este contrato no tiene empresa», porque contrato_guarda no trae proyecto_id).
  insert into public.plantilla_campos_propios (empresa, clave, etiqueta_es, tipo, autor) values ('lawang', 'cx_prueba_mobiliario', 'Pack de mobiliario', 'texto', 'prueba');
  v := pg_temp.val(ag.uid, ag.em, format('select public.contrato_guarda(null, %L::jsonb)::text',
         jsonb_set(pago, '{datos,fields,cx_prueba_mobiliario}', '"Pack Bali"'::jsonb)));
  r := r || pg_temp.l(v !~ '^ERR', 'G5 un contrato nuevo con un campo cx_ de su empresa se guarda por contrato_guarda (' || left(v, 100) || ')');
  select count(*) into n from public.contratos where id::text = ((case when v !~ '^ERR' then v end)::jsonb ->> 'id') and datos->'fields'->>'cx_prueba_mobiliario' = 'Pack Bali';
  r := r || pg_temp.l(n = 1, 'G5b ... con el valor guardado');

  -- ============================================================ R. lo que la base rechaza ahora (antes se guardaba)
  v := pg_temp.val(jv.uid, jv.em, format('select public.usuario_guarda_permisos(%L, %L::jsonb)::text', ag2.uid, '{"tipos_contrato":["carta_reserva","inventado_x"]}'));
  r := r || pg_temp.l(pg_temp.err(v) = '22023' and v ~ 'desconocido', 'R1 un tipo inventado se rechaza, tambien al super admin (' || left(v, 100) || ')');
  v := pg_temp.val(jv.uid, jv.em, format('select public.usuario_guarda_permisos(%L, %L::jsonb)::text', ag2.uid, '{"tipos_contrato":["carta_reserva","ppjb_parcela"]}'));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'R2 el slug de una plantilla DEL ESTUDIO no es un tipo concedible (' || left(v, 100) || ')');
  v := pg_temp.val(jv.uid, jv.em, format('select public.usuario_guarda_permisos(%L, %L::jsonb)::text', agS.uid, json_build_object('tipos_contrato', array['carta_reserva', slug_f])));
  r := r || pg_temp.l(pg_temp.err(v) = '42501' and v ~ 'otra empresa que la de esa persona', 'R3 el propio de Lawang no se da a un agente de Sandal Woods, ni siendo super admin (' || left(v, 100) || ')');
  v := pg_temp.val(sae_S.uid, sae_S.em, format('select public.usuario_guarda_permisos(%L, %L::jsonb)::text', agS.uid, json_build_object('tipos_contrato', array['carta_reserva', slug_f])));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'R4 el super admin de Sandal Woods no da el propio de Lawang a su gente (antes: sin comprobacion) (' || left(v, 100) || ')');
  -- regla 3 aislada: persona sin empresas (la regla 2 no aplica) y quien concede es de otra empresa
  perform set_config('request.jwt.claims', json_build_object('sub', sae_S.uid, 'role', 'authenticated', 'email', sae_S.em)::text, true);
  v := pg_temp.pg(format('update public.usuarios set tipos_contrato = array[''carta_reserva'', %L] where user_id = %L returning 1', slug_f, libre.uid));
  r := r || pg_temp.l(pg_temp.err(v) = '42501' and v ~ 'empresa que no es tuya', 'R5 con sesion, nadie concede un propio de una empresa fuera de su alcance (' || left(v, 100) || ')');
  perform set_config('request.jwt.claims', '', true);
  v := pg_temp.pg(format('update public.usuarios set tipos_contrato = array[''carta_reserva'', %L] where user_id = %L returning 1', slug_f, libre.uid));
  r := r || pg_temp.l(v = '1', 'R6 sin sesion (camino de la edge con service_role) la regla de alcance no aplica: la comprueba la edge (' || left(v, 80) || ')');
  v := pg_temp.pg(format('update public.usuarios set tipos_contrato = array[''carta_reserva'', ''basura_x''] where user_id = %L returning 1', libre.uid));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'R7 ... pero un tipo inventado se rechaza tambien sin sesion (' || left(v, 80) || ')');
  v := pg_temp.pg(format('insert into public.usuarios (user_id, email, rol, tipos_contrato, activo) values (gen_random_uuid(), ''prueba-tipos@ejemplo.invalid'', ''agente'', ''{inventado_x}'', true) returning 1'));
  r := r || pg_temp.l(pg_temp.err(v) = '22023' and v ~ 'desconocido', 'R8 un alta con un tipo inventado no entra (lo para el trigger, antes que cualquier FK) (' || left(v, 100) || ')');

  -- ============================================================ E. exposicion
  select count(*) into n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_trg_usuarios_tipos_contrato_validos', '_contrato_proyecto_de')
     and p.prosecdef and array_to_string(p.proconfig, ',') ~ 'search_path='
     and not has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('service_role', p.oid, 'execute');
  r := r || pg_temp.l(n = 2, 'E1 las dos funciones nuevas: DEFINER con search_path fijo y sin EXECUTE para nadie (' || n || ')');
  select count(*) into n from pg_trigger where tgrelid = 'public.usuarios'::regclass and tgname = 'usuarios_tipos_contrato_validos' and tgenabled = 'O';
  r := r || pg_temp.l(n = 1, 'E2 el trigger esta activo en usuarios');

  fallos := (select count(*) from regexp_matches(r, 'FALLO', 'g'));
  raise exception E'INFORME CONTRATO PROPIO PERMISO AGENTE\n%FALLOS=%', r, fallos;
end $todo$;
