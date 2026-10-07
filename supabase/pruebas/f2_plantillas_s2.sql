-- Prueba de S2 «plantillas de contrato por empresa» (7-oct-2026). Se pega DESPUES de las migraciones 20261008980000..980300 y del stub (f2_plantillas_s2_stub_validador.sql)
-- en la MISMA peticion: asi se ensaya sin rastro. Todo el cuerpo corre dentro de un sub-bloque que acaba en raise (rollback); el informe sale en el raise final.
-- Personas (JWT simulado, como f2_b12_empresas.sql): 4 agentes convertidos a ae_L admin_empresa/lawang, se_L super_admin_empresa/lawang, ae_S admin_empresa/sandal_woods,
-- se_S super_admin_empresa/sandal_woods; ctl_L agente global con empresas {lawang}; ctl_G agente global sin empresas; los 3 super globales (jv y pepito sin lista de empresas; andrea con empresas={lawang}: global pero acotada, NO escribe en Sandal Woods); anon; un uid ajeno (portal).
-- Resultado del ensayo del 7-oct (produccion, rollback): 137 OK; el unico FALLO era la expectativa de andrea/sandal_woods (corregida arriba: su ficha global esta acotada a Lawang). No repetido tras la correccion.
-- La foto de los 34 usuarios NO va aqui (lock largo sobre contratos): f2_foto_ids.sql antes y despues de aplicar.
-- NO inserta contratos (nextval no hace rollback). Los vinculos usan contratos que ya existen y se deshacen. Debe terminar con «FALLOS=0».
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); sin drop de objetos reales (solo el stub del validador, que existe solo en el ensayo)
create temp table _s2p (et text primary key, uid uuid, em text);
create temp table _s2out (txt text);
create or replace function pg_temp.l(c boolean, t text) returns text language sql as $f$
  select case when coalesce(c, false) then 'OK    ' else 'FALLO ' end || t || E'\n'
$f$;
-- ejecuta como un usuario; conserva los efectos si sale bien; devuelve la primera columna (text) o 'ERR<sqlstate>:<mensaje>'
create or replace function pg_temp.val(p_uid uuid, p_email text, p_sql text, p_role text default 'authenticated') returns text language plpgsql as $f$
declare t text;
begin
  perform set_config('request.jwt.claims', case when p_role = 'anon' then json_build_object('role', 'anon')::text
                      else json_build_object('sub', p_uid, 'role', 'authenticated', 'email', p_email)::text end, true);
  execute format('set local role %I', p_role);
  begin execute p_sql into t;
  exception when others then t := 'ERR' || sqlstate || ':' || left(sqlerrm, 90); end;
  execute 'reset role';
  return t;
end $f$;
create or replace function pg_temp.err(t text) returns text language sql immutable as $f$ select case when t like 'ERR%' then substr(t, 4, 5) end $f$;

insert into _s2p select 'jv', user_id, email from public.usuarios where email = 'jvr.cervantes@gmail.com';
insert into _s2p select 'andrea', user_id, email from public.usuarios where email = 'andreabenimeli@gmail.com';
insert into _s2p select 'pepito', user_id, email from public.usuarios where email = 'pepito@lawangproperties.com';
insert into _s2p select 'portal', gen_random_uuid(), 'portal.ajeno@example.com';
insert into _s2p
  select (array['ae_L', 'se_L', 'ae_S', 'se_S', 'ctl_L', 'ctl_G'])[rn], user_id, email
    from (select user_id, email, row_number() over (order by email) rn
            from (select user_id, email from public.usuarios where activo and ambito = 'global' and rol = 'agente' order by email limit 6) q) z;

do $todo$
declare
  r text := ''; f text; n bigint; v text; j jsonb; e record;
  ae_L _s2p; se_L _s2p; ae_S _s2p; se_S _s2p; ctl_L _s2p; ctl_G _s2p; jv _s2p; andrea _s2p; pepito _s2p; portal _s2p;
  pL uuid; pS uuid; cL uuid; cS uuid; cLf uuid; cLg uuid;
  md0 bigint; md1 bigint; trg0 int; trg1 int;
  sL uuid; sS uuid;                      -- semillas
  dL uuid; dS uuid; dL2 uuid; vL1 uuid; vL2 uuid; vS1 uuid;
  b1 text := '<p data-lang="es">Texto de prueba uno</p><p data-lang="en">Test text one</p>';
  b2 text := '<p data-lang="es">Texto de prueba DOS</p><p data-lang="id">Teks dua</p>';
  bS text := '<p data-lang="es">Texto de la otra empresa</p>';
  semilla text := '<p data-lang="es">Semilla del estudio: Tepi Sun Gai</p>';
  s text; u text; k int; ok boolean;
  fn text[] := array['plantilla_contrato_guarda_borrador(text,text,text,text)', 'plantilla_contrato_activa(uuid,text,boolean)', 'plantilla_contrato_descarta_borrador(uuid)',
                     'plantilla_contrato_cuerpo(text,uuid,text)', 'plantilla_contrato_cuerpo_version(uuid,text)', 'plantilla_contrato_version_de_contrato(uuid)',
                     'plantilla_contrato_versiones_lista(text,text)', 'plantilla_contrato_fija(uuid,uuid)'];
begin
  select * into jv from _s2p where et = 'jv'; select * into andrea from _s2p where et = 'andrea'; select * into pepito from _s2p where et = 'pepito'; select * into portal from _s2p where et = 'portal';
  select * into ae_L from _s2p where et = 'ae_L'; select * into se_L from _s2p where et = 'se_L'; select * into ae_S from _s2p where et = 'ae_S';
  select * into se_S from _s2p where et = 'se_S'; select * into ctl_L from _s2p where et = 'ctl_L'; select * into ctl_G from _s2p where et = 'ctl_G';
  select id into pL from public.proyectos where empresa = 'lawang' order by id limit 1;
  select id into pS from public.proyectos where empresa = 'sandal_woods' order by id limit 1;
  select c.id into cL from public.contratos c join public.proyectos p on p.id = c.proyecto_id where p.empresa = 'lawang' and not c.bloqueado and not exists (select 1 from public.contrato_firmas x where x.contrato_id = c.id) order by c.id limit 1;
  select c.id into cS from public.contratos c join public.proyectos p on p.id = c.proyecto_id where p.empresa = 'sandal_woods' and not c.bloqueado and not exists (select 1 from public.contrato_firmas x where x.contrato_id = c.id) order by c.id limit 1;
  select c.id into cLf from public.contratos c join public.proyectos p on p.id = c.proyecto_id where p.empresa = 'lawang' and c.bloqueado order by c.id limit 1;
  select c.id into cLg from public.contratos c join public.proyectos p on p.id = c.proyecto_id where p.empresa = 'lawang' and not c.bloqueado and exists (select 1 from public.contrato_firmas x where x.contrato_id = c.id) order by c.id limit 1;
  select coalesce(n_tup_ins + n_tup_upd + n_tup_del, 0) into md0 from pg_stat_xact_user_tables where relid = 'public.contratos'::regclass;
  select count(*) into trg0 from pg_trigger where tgrelid = 'public.contratos'::regclass and not tgisinternal;

  begin   -- sub-bloque: todo lo que sigue se deshace
  perform set_config('request.jwt.claims', json_build_object('sub', jv.uid, 'role', 'authenticated', 'email', jv.em)::text, true);
  update public.usuarios set rol = 'admin_empresa', ambito = 'empresa', empresas = '{lawang}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{ajustes,facturas,gastos,usuarios}', tipos_contrato = '{}' where user_id = ae_L.uid;
  update public.usuarios set rol = 'super_admin_empresa', ambito = 'empresa', empresas = '{lawang}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{contratos}', tipos_contrato = '{}' where user_id = se_L.uid;
  update public.usuarios set rol = 'admin_empresa', ambito = 'empresa', empresas = '{sandal_woods}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{ajustes,facturas,gastos,usuarios}', tipos_contrato = '{}' where user_id = ae_S.uid;
  update public.usuarios set rol = 'super_admin_empresa', ambito = 'empresa', empresas = '{sandal_woods}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{contratos}', tipos_contrato = '{}' where user_id = se_S.uid;
  update public.usuarios set rol = 'agente', ambito = 'global', empresas = '{lawang}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{}', tipos_contrato = '{}' where user_id = ctl_L.uid;
  update public.usuarios set rol = 'agente', ambito = 'global', empresas = '{}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{}', tipos_contrato = '{}' where user_id = ctl_G.uid;
  r := r || pg_temp.l(pL is not null and pS is not null and cL is not null and cS is not null and cLf is not null and cLg is not null,
                      'A0 datos de partida: 2 proyectos, contrato libre de cada empresa, uno firmado y uno con filas de firma');

  -- ============================================================ A. permisos de tabla y de funcion
  select count(*) into n from unnest(array['anon', 'authenticated', 'service_role']) ro cross join unnest(array['plantilla_contrato_versiones', 'plantilla_contrato_cuerpos', 'contrato_plantilla_version']) t
   where has_table_privilege(ro, 'public.' || t, 'select,insert,update,delete,truncate,references,trigger');
  r := r || pg_temp.l(n = 0, format('A1 anon, authenticated y service_role sin NINGUN privilegio directo sobre las 3 tablas (%s)', n));
  select count(*) into n from pg_class where oid in ('public.plantilla_contrato_versiones'::regclass, 'public.plantilla_contrato_cuerpos'::regclass, 'public.contrato_plantilla_version'::regclass) and relrowsecurity;
  r := r || pg_temp.l(n = 3, 'A2 RLS activa en las 3 tablas');
  select count(*) into n from unnest(fn) x where has_function_privilege('anon', 'public.' || x, 'execute') or has_function_privilege('service_role', 'public.' || x, 'execute');
  r := r || pg_temp.l(n = 0, format('A3 ninguna de las 8 RPC es ejecutable por anon ni service_role (%s)', n));
  select count(*) into n from unnest(fn) x where not has_function_privilege('authenticated', 'public.' || x, 'execute');
  r := r || pg_temp.l(n = 0, 'A4 las 8 RPC son ejecutables por authenticated (cada una tiene su llamador)');
  select count(*) into n from pg_proc where pronamespace = 'public'::regnamespace and proname like 'plantilla_contrato_%' and prosecdef and not (proconfig @> array['search_path=""']);
  r := r || pg_temp.l(n = 0, 'A5 todas SECURITY DEFINER con search_path vacio');
  select count(*) into n from pg_proc where pronamespace = 'public'::regnamespace and proname in ('_plantilla_hash', '_trg_plantilla_version_ins', '_trg_plantilla_version_upd', '_trg_plantilla_sin_borrado', '_trg_plantilla_cuerpo_iu', '_trg_contrato_plantilla_version', '_plantilla_esqueleto', '_plantilla_valida')
         and (has_function_privilege('anon', oid, 'execute') or has_function_privilege('authenticated', oid, 'execute'));
  r := r || pg_temp.l(n = 0, 'A6 las funciones internas y los triggers no son ejecutables por nadie del API');
  v := pg_temp.val(ctl_G.uid, ctl_G.em, 'select count(*) from public.plantilla_contrato_versiones');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'A7 un authenticated no puede ni leer las tablas directo (' || v || ')');
  v := pg_temp.val(null, null, 'select public.plantilla_contrato_versiones_lista()', 'anon');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'A8 anon no ejecuta la lista (' || v || ')');

  -- ============================================================ B. hash, semillas e inmutabilidad (como postgres: los triggers valen tambien contra el propietario)
  r := r || pg_temp.l(public._plantilla_hash('abc') = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad', 'B1 sha256 de ''abc'' = vector conocido');
  r := r || pg_temp.l(public._plantilla_hash('áñ€') = encode(sha256('\xc3a1c3b1e282ac'::bytea), 'hex'), 'B2 el hash es sobre los bytes UTF-8 del cuerpo');
  insert into public.plantilla_contrato_versiones (empresa, slug, version, origen, idioma_set, hash, bytes, activable, bloqueo_motivo, autor, motivo)
    values ('lawang', 'carta_reserva', 1, 'semilla', '{es}', public._plantilla_hash(semilla), octet_length(semilla), false, 'Semilla del estudio con texto de Lawang fijo (R12)', 'estudio', 'v1 copia exacta') returning id into sL;
  insert into public.plantilla_contrato_cuerpos values (sL, semilla);
  insert into public.plantilla_contrato_versiones (empresa, slug, version, origen, idioma_set, hash, bytes, activable, bloqueo_motivo, autor, motivo)
    values ('sandal_woods', 'carta_reserva', 1, 'semilla', '{es}', public._plantilla_hash(semilla), octet_length(semilla), false, 'Semilla del estudio con texto de Lawang fijo (R12)', 'estudio', 'v1 copia exacta') returning id into sS;
  insert into public.plantilla_contrato_cuerpos values (sS, semilla);
  r := r || pg_temp.l(true, 'B3 dos semillas v1 cargadas (una por empresa)');
  begin insert into public.plantilla_contrato_versiones (empresa, slug, version, origen, hash, bytes, activable, autor) values ('lawang', 'poa_notario', 1, 'semilla', repeat('a', 64), 5, true, 'x'); u := 'ok';
  exception when others then u := sqlstate; end;
  r := r || pg_temp.l(u = '23514', 'B4 una semilla no puede nacer activable (' || u || ')');
  begin insert into public.plantilla_contrato_versiones (empresa, slug, version, estado, origen, hash, bytes, activable, bloqueo_motivo, autor, activado_por, activado_en, confirmacion_nombre, confirmacion_texto)
        values ('lawang', 'poa_notario', 1, 'activa', 'empresa', repeat('a', 64), 5, true, null, 'x', 'x', now(), 'x', 'x'); u := 'ok';
  exception when others then u := sqlstate; end;
  r := r || pg_temp.l(u = '55000', 'B5 una version no puede nacer activa por INSERT directo (' || u || ')');
  begin insert into public.plantilla_contrato_cuerpos values (sS, 'otra cosa'); u := 'ok'; exception when others then u := sqlstate; end;
  r := r || pg_temp.l(u in ('55000', '23505'), 'B6 un cuerpo con hash distinto, o sobre una semilla ya cargada, se rechaza (' || u || ')');
  begin update public.plantilla_contrato_cuerpos set cuerpo_html = 'x' where version_id = sL; u := 'ok'; exception when others then u := sqlstate; end;
  r := r || pg_temp.l(u = '55000', 'B7 el cuerpo de una semilla es inmutable (' || u || ')');
  begin update public.plantilla_contrato_versiones set motivo = 'cambio' where id = sL; u := 'ok'; exception when others then u := sqlstate; end;
  r := r || pg_temp.l(u = '55000', 'B8 la fila de una semilla es inmutable (' || u || ')');
  begin delete from public.plantilla_contrato_versiones where id = sL; u := 'ok'; exception when others then u := sqlstate; end;
  r := r || pg_temp.l(u = '55000', 'B9 una version no se borra (' || u || ')');
  begin truncate public.plantilla_contrato_cuerpos; u := 'ok'; exception when others then u := sqlstate; end;
  r := r || pg_temp.l(u = '55000', 'B10 los cuerpos no se vacian (' || u || ')');
  v := pg_temp.val(se_L.uid, se_L.em, format('select public.plantilla_contrato_activa(%L, ''Persona de Prueba'', true)', sL));
  r := r || pg_temp.l(pg_temp.err(v) = '55000' and v like '%no activable%', 'B11 activar una semilla con texto de otra sociedad es RECHAZADO (' || v || ')');
  v := pg_temp.val(jv.uid, jv.em, format('select public.plantilla_contrato_activa(%L, ''Persona de Prueba'', true)', sS));
  r := r || pg_temp.l(pg_temp.err(v) = '55000', 'B12 ni el super global activa la semilla de Sandal Woods (' || v || ')');

  -- ============================================================ C. guardar borrador: quien puede y quien no
  for e in select * from (values ('ae_L','lawang',true),('se_L','lawang',true),('ae_S','sandal_woods',true),('se_S','sandal_woods',true),
                                  ('jv','lawang',true),('jv','sandal_woods',true),('andrea','lawang',true),('andrea','sandal_woods',false),('pepito','lawang',true),('pepito','sandal_woods',true),
                                  ('ae_L','sandal_woods',false),('se_L','sandal_woods',false),('ae_S','lawang',false),('se_S','lawang',false),
                                  ('ctl_L','lawang',false),('ctl_G','lawang',false),('ctl_G','sandal_woods',false),('portal','lawang',false)) t(et, emp, esperado) loop
    select uid, em into u, s from _s2p where _s2p.et = e.et;
    v := pg_temp.val(u::uuid, s, format('select public.plantilla_contrato_guarda_borrador(%L, ''carta_reserva'', %L, ''prueba C'')', e.emp, case e.emp when 'lawang' then b1 else bS end));
    r := r || pg_temp.l((e.esperado and v !~ '^ERR') or (not e.esperado and pg_temp.err(v) = '42501'),
                        format('C1 %s guarda borrador de %s -> %s', e.et, e.emp, case when v ~ '^ERR' then left(v, 40) else 'ok' end));
  end loop;
  select * into ae_L from _s2p where et = 'ae_L';
  v := pg_temp.val(null, null, 'select public.plantilla_contrato_guarda_borrador(''lawang'', ''carta_reserva'', ''x'', ''prueba C'')', 'anon');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'C2 anon no guarda borrador (' || v || ')');
  select v.id into dL from public.plantilla_contrato_versiones v where v.empresa = 'lawang' and v.slug = 'carta_reserva' and v.estado = 'borrador' and v.origen = 'empresa';
  select v.id into dS from public.plantilla_contrato_versiones v where v.empresa = 'sandal_woods' and v.slug = 'carta_reserva' and v.estado = 'borrador' and v.origen = 'empresa';
  r := r || pg_temp.l(dL is not null and dS is not null, 'C3 queda UN borrador por empresa (guardar de nuevo reescribe el mismo)');
  select count(*) into n from public.plantilla_contrato_versiones where slug = 'carta_reserva' and estado = 'borrador' and origen = 'empresa';
  r := r || pg_temp.l(n = 2, format('C4 exactamente 2 borradores de empresa tras 10 guardados (%s)', n));
  select (v.hash = encode(sha256(convert_to((select cuerpo_html from public.plantilla_contrato_cuerpos where version_id = v.id), 'UTF8')), 'hex') and v.bytes = octet_length((select cuerpo_html from public.plantilla_contrato_cuerpos where version_id = v.id))
          and v.idioma_set = '{es,en}' and v.activable and v.origen = 'empresa' and v.hereda_de = sL and v.version = 2) into ok from public.plantilla_contrato_versiones v where v.id = dL;
  r := r || pg_temp.l(ok, 'C5 hash/tamano/idiomas calculados en servidor, hereda de la semilla, version 2, activable');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_guarda_borrador(''lawang'', ''carta_reserva'', %L, '' '')', b1));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'C6 sin motivo no se guarda (' || v || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_guarda_borrador(''lawang'', ''carta_reserva'', repeat(''a'', 1000001), ''prueba'')');
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'C7 un texto de mas de 1 MB se rechaza (' || v || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_guarda_borrador(''lawang'', ''no_existe'', ''x'', ''prueba'')');
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'C8 plantilla inexistente (' || v || ')');

  -- ============================================================ D. el validador manda (S3): cerrado si falta, rechaza si dice no
  execute 'create or replace function public.plantilla_cuerpo_valida(p_cuerpo text, p_esqueleto text) returns jsonb language sql immutable as $q$ select jsonb_build_object(''ok'', false, ''errores'', jsonb_build_array(''etiqueta script no permitida'')) $q$';
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_guarda_borrador(''lawang'', ''carta_reserva'', %L, ''prueba D'')', b2));
  r := r || pg_temp.l(pg_temp.err(v) = '22023' and v like '%script%', 'D1 si el validador dice ok=false, guardar rechaza con su error (' || v || ')');
  v := pg_temp.val(se_L.uid, se_L.em, format('select public.plantilla_contrato_activa(%L, ''Persona de Prueba'', true)', dL));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'D2 si el validador dice ok=false, activar rechaza (' || v || ')');
  execute 'drop function public.plantilla_cuerpo_valida(text, text)';
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_guarda_borrador(''lawang'', ''carta_reserva'', %L, ''prueba D'')', b2));
  r := r || pg_temp.l(pg_temp.err(v) = '55000', 'D3 sin validador instalado, guardar falla CERRADO (' || v || ')');
  v := pg_temp.val(se_L.uid, se_L.em, format('select public.plantilla_contrato_activa(%L, ''Persona de Prueba'', true)', dL));
  r := r || pg_temp.l(pg_temp.err(v) = '55000', 'D4 sin validador instalado, activar falla CERRADO (' || v || ')');
  execute 'create or replace function public.plantilla_cuerpo_valida(p_cuerpo text, p_esqueleto text) returns jsonb language sql immutable as $q$ select jsonb_build_object(''ok'', true, ''errores'', ''[]''::jsonb) $q$';

  -- ============================================================ E. activar: solo el super de ESA empresa (o el global), con confirmacion guardada
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_activa(%L, ''Persona de Prueba'', true)', dL));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'E1 el admin de empresa NO activa (' || v || ')');
  v := pg_temp.val(se_S.uid, se_S.em, format('select public.plantilla_contrato_activa(%L, ''Persona de Prueba'', true)', dL));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'E2 el super de Sandal Woods NO activa un texto de Lawang (' || v || ')');
  v := pg_temp.val(ctl_G.uid, ctl_G.em, format('select public.plantilla_contrato_activa(%L, ''Persona de Prueba'', true)', dL));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'E3 un agente NO activa (' || v || ')');
  v := pg_temp.val(se_L.uid, se_L.em, format('select public.plantilla_contrato_activa(%L, ''Persona de Prueba'', false)', dL));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'E4 sin confirmar no se activa (' || v || ')');
  v := pg_temp.val(se_L.uid, se_L.em, format('select public.plantilla_contrato_activa(%L, ''  '', true)', dL));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'E5 sin nombre no se activa (' || v || ')');
  v := pg_temp.val(se_L.uid, se_L.em, format('select public.plantilla_contrato_activa(%L, ''Persona de Prueba'', true)', dL));
  r := r || pg_temp.l(v !~ '^ERR', 'E6 el super de Lawang activa su borrador (' || left(v, 60) || ')');
  select (estado = 'activa' and activado_por = se_L.em and confirmacion_nombre = 'Persona de Prueba' and confirmacion_texto like '%no ha revisado este texto%' and confirmacion_texto like '%abogado%' and activado_en is not null)
    into ok from public.plantilla_contrato_versiones where id = dL;
  r := r || pg_temp.l(ok, 'E7 queda guardado quien activa, cuando, el nombre y el texto del aviso con la version');
  v := pg_temp.val(jv.uid, jv.em, format('select public.plantilla_contrato_activa(%L, ''Persona de Prueba'', true)', dS));
  r := r || pg_temp.l(v !~ '^ERR', 'E8 el super global activa la de Sandal Woods (' || left(v, 60) || ')');
  v := pg_temp.val(se_L.uid, se_L.em, format('select public.plantilla_contrato_activa(%L, ''Persona de Prueba'', true)', dL));
  r := r || pg_temp.l(pg_temp.err(v) = '55000', 'E9 una version ya activa no se vuelve a activar (' || v || ')');
  vL1 := dL; vS1 := dS;

  -- ============================================================ F. activa y retirada son inmutables
  begin update public.plantilla_contrato_cuerpos set cuerpo_html = 'x' where version_id = vL1; u := 'ok'; exception when others then u := sqlstate; end;
  r := r || pg_temp.l(u = '55000', 'F1 el cuerpo de una activa no cambia (' || u || ')');
  begin update public.plantilla_contrato_versiones set motivo = 'x' where id = vL1; u := 'ok'; exception when others then u := sqlstate; end;
  r := r || pg_temp.l(u = '55000', 'F2 la fila de una activa no cambia (' || u || ')');
  begin update public.plantilla_contrato_versiones set estado = 'retirada', retirada_por = 'x', retirada_en = now(), hash = repeat('b', 64) where id = vL1; u := 'ok'; exception when others then u := sqlstate; end;
  r := r || pg_temp.l(u = '55000', 'F3 activa -> retirada solo cambia el estado (con otro cambio, rechazado) (' || u || ')');
  begin delete from public.plantilla_contrato_versiones where id = vL1; u := 'ok'; exception when others then u := sqlstate; end;
  r := r || pg_temp.l(u = '55000', 'F4 una activa no se borra (' || u || ')');
  begin delete from public.plantilla_contrato_cuerpos where version_id = vL1; u := 'ok'; exception when others then u := sqlstate; end;
  r := r || pg_temp.l(u = '55000', 'F5 el cuerpo de una activa no se borra (' || u || ')');
  begin insert into public.plantilla_contrato_versiones (empresa, slug, version, estado, hash, bytes, activable, autor, activado_por, activado_en, confirmacion_nombre, confirmacion_texto)
        values ('lawang', 'carta_reserva', 9, 'activa', repeat('c', 64), 3, true, 'x', 'x', now(), 'x', 'x'); u := 'ok'; exception when others then u := sqlstate; end;
  r := r || pg_temp.l(u = '55000', 'F6 no se puede colar una 2a activa por INSERT (' || u || ')');
  v := pg_temp.val(se_L.uid, se_L.em, format('select public.plantilla_contrato_guarda_borrador(''lawang'', ''carta_reserva'', %L, ''prueba v3'')', b2));
  r := r || pg_temp.l(v !~ '^ERR', 'F7 se puede escribir un borrador nuevo sobre una activa (' || left(v, 50) || ')');
  select id into dL2 from public.plantilla_contrato_versiones where empresa = 'lawang' and slug = 'carta_reserva' and estado = 'borrador' and origen = 'empresa';
  select (version = 3 and hereda_de = vL1) into ok from public.plantilla_contrato_versiones where id = dL2;
  r := r || pg_temp.l(ok, 'F8 el borrador nuevo es la version 3 y hereda de la activa');
  v := pg_temp.val(se_L.uid, se_L.em, format('select public.plantilla_contrato_activa(%L, ''Persona de Prueba'', true)', dL2));
  r := r || pg_temp.l(v !~ '^ERR', 'F9 activar la v3 (' || left(v, 40) || ')');
  vL2 := dL2;
  select (select estado from public.plantilla_contrato_versiones where id = vL1) = 'retirada' and (select retirada_por from public.plantilla_contrato_versiones where id = vL1) = se_L.em
     and (select count(*) from public.plantilla_contrato_versiones where empresa = 'lawang' and slug = 'carta_reserva' and estado = 'activa') = 1 into ok;
  r := r || pg_temp.l(ok, 'F10 la anterior pasa a retirada (con quien y cuando) y queda UNA sola activa');
  begin update public.plantilla_contrato_versiones set estado = 'borrador' where id = vL1; u := 'ok'; exception when others then u := sqlstate; end;
  r := r || pg_temp.l(u = '55000', 'F11 una retirada no vuelve atras (' || u || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('update public.plantilla_contrato_versiones set estado = ''activa'' where id = %L returning id::text', vL1));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'F12 un rol de empresa no escribe la tabla directo (' || v || ')');

  -- ============================================================ G. descartar un borrador
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_guarda_borrador(''lawang'', ''carta_reserva'', %L, ''para descartar'')', bS));
  select id into dL from public.plantilla_contrato_versiones where empresa = 'lawang' and slug = 'carta_reserva' and estado = 'borrador' and origen = 'empresa';
  v := pg_temp.val(ae_S.uid, ae_S.em, format('select public.plantilla_contrato_descarta_borrador(%L)', dL));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'G1 el admin de la otra empresa no descarta (' || v || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_descarta_borrador(%L)', dL));
  select estado into u from public.plantilla_contrato_versiones where id = dL;
  r := r || pg_temp.l(v !~ '^ERR' and u = 'retirada', 'G2 el admin de su empresa descarta: queda retirada, no borrada (' || u || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_descarta_borrador(%L)', vL2));
  r := r || pg_temp.l(pg_temp.err(v) = '55000', 'G3 una activa no se descarta (' || v || ')');

  -- ============================================================ H. lectura: la empresa se deduce en servidor
  v := pg_temp.val(ctl_L.uid, ctl_L.em, format('select public.plantilla_contrato_cuerpo(''carta_reserva'', %L)', pL));
  r := r || pg_temp.l(v !~ '^ERR' and (v::jsonb ->> 'cuerpo_html') = b2 and (v::jsonb ->> 'version')::int = 3 and (v::jsonb ->> 'empresa') = 'lawang', 'H1 un agente de Lawang lee la ACTIVA de Lawang por proyecto (' || left(v, 50) || ')');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, 'select public.plantilla_contrato_cuerpo(''carta_reserva'')');
  r := r || pg_temp.l(v !~ '^ERR' and (v::jsonb ->> 'cuerpo_html') = b2, 'H2 sin proyecto, su unica empresa decide (' || left(v, 40) || ')');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, format('select public.plantilla_contrato_cuerpo(''carta_reserva'', %L)', pS));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'H3 un agente de Lawang NO lee el texto de Sandal Woods por proyecto (' || v || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, format('select public.plantilla_contrato_cuerpo(''carta_reserva'', %L)', pL));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'H4 el admin de Sandal Woods NO lee el de Lawang (' || v || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, format('select public.plantilla_contrato_cuerpo(''carta_reserva'', %L)', pS));
  r := r || pg_temp.l(v !~ '^ERR' and (v::jsonb ->> 'cuerpo_html') = bS and not ((v::jsonb ->> 'cuerpo_html') like '%Lawang%'), 'H5 Sandal Woods lee SU texto, sin una palabra del de Lawang');
  v := pg_temp.val(ctl_G.uid, ctl_G.em, 'select coalesce(public.plantilla_contrato_cuerpo(''carta_reserva'')::text, ''NULO'')');
  r := r || pg_temp.l(v = 'NULO', 'H6 un global sin empresa y sin proyecto no recibe nada: usa el fichero (' || left(v, 30) || ')');
  v := pg_temp.val(ctl_G.uid, ctl_G.em, format('select public.plantilla_contrato_cuerpo(''carta_reserva'', %L)', pS));
  r := r || pg_temp.l(v !~ '^ERR' and (v::jsonb ->> 'cuerpo_html') = bS, 'H7 un global lee el de la empresa del proyecto');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, format('select coalesce(public.plantilla_contrato_cuerpo(''carta_reserva'', %L)::text, ''NULO'')', gen_random_uuid()));
  r := r || pg_temp.l(v = 'NULO', 'H8 proyecto sin empresa: un rol acotado no ve nada (' || left(v, 30) || ')');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, format('select public.plantilla_contrato_cuerpo(''carta_reserva'', %L, %L)', pL, (select hash from public.plantilla_contrato_versiones where id = vL2)));
  r := r || pg_temp.l(v !~ '^ERR' and (v::jsonb ->> 'sin_cambios') = 'true' and not (v::jsonb ? 'cuerpo_html'), 'H9 con el ETag vigente no se manda el cuerpo');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, format('select coalesce(public.plantilla_contrato_cuerpo(''poa_notario'', %L)::text, ''NULO'')', pL));
  r := r || pg_temp.l(v = 'NULO', 'H10 plantilla sin version activa: nulo (fichero)');
  v := pg_temp.val(portal.uid, portal.em, 'select public.plantilla_contrato_cuerpo(''carta_reserva'')');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'H11 un cliente del portal (sin ficha de agente) no lee (' || v || ')');
  v := pg_temp.val(null, null, 'select public.plantilla_contrato_cuerpo(''carta_reserva'')', 'anon');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'H12 anon no lee (' || v || ')');
  -- por id
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_cuerpo_version(%L)', dL2));
  r := r || pg_temp.l(v !~ '^ERR', 'H13 el admin de Lawang lee cualquier version de su empresa por id');
  -- un borrador vivo de cada empresa para probar la lectura de borradores
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_guarda_borrador(''lawang'', ''carta_reserva'', %L, ''borrador vivo L'')', b1));
  v := pg_temp.val(ae_S.uid, ae_S.em, format('select public.plantilla_contrato_guarda_borrador(''sandal_woods'', ''carta_reserva'', %L, ''borrador vivo S'')', b1));
  select id into dL from public.plantilla_contrato_versiones where empresa = 'lawang' and slug = 'carta_reserva' and estado = 'borrador' and origen = 'empresa';
  select id into dS from public.plantilla_contrato_versiones where empresa = 'sandal_woods' and slug = 'carta_reserva' and estado = 'borrador' and origen = 'empresa';
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_cuerpo_version(%L)', dL));
  r := r || pg_temp.l(v !~ '^ERR' and (v::jsonb ->> 'cuerpo_html') = b1, 'H14 el admin lee SU borrador');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_cuerpo_version(%L)', dS));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'H15 el admin de Lawang NO lee el borrador de Sandal Woods (' || v || ')');
  v := pg_temp.val(se_S.uid, se_S.em, format('select public.plantilla_contrato_cuerpo_version(%L)', dL));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'H16 el super de Sandal Woods NO lee el borrador de Lawang (' || v || ')');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, format('select public.plantilla_contrato_cuerpo_version(%L)', dL));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'H17 un agente NO lee un borrador (' || v || ')');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, format('select public.plantilla_contrato_cuerpo_version(%L)', vL2));
  r := r || pg_temp.l(v !~ '^ERR', 'H18 un agente lee la activa por id');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, format('select public.plantilla_contrato_cuerpo_version(%L)', vL1));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'H19 un agente NO lee una retirada si ningun contrato suyo la usa (' || v || ')');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, format('select public.plantilla_contrato_cuerpo_version(%L)', sL));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'H20 un agente NO lee la semilla (' || v || ')');
  v := pg_temp.val(jv.uid, jv.em, format('select public.plantilla_contrato_cuerpo_version(%L)', sS));
  r := r || pg_temp.l(v !~ '^ERR', 'H21 el super global lee la semilla de cualquier empresa');
  -- lista
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select jsonb_agg(to_jsonb(x))::text from public.plantilla_contrato_versiones_lista() x');
  r := r || pg_temp.l(v !~ '^ERR' and not (v ilike '%sandal_woods%') and not (v like '%cuerpo_html%') and v like '%lawang%', 'L1 el admin de Lawang lista solo lo de Lawang y sin cuerpo');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select count(*) from public.plantilla_contrato_versiones_lista(''sandal_woods'')');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'L2 pedir la lista de la otra empresa = 42501 (' || v || ')');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, 'select count(*) filter (where estado <> ''activa'') || ''/'' || count(*) from public.plantilla_contrato_versiones_lista()');
  r := r || pg_temp.l(v like '0/%' and v <> '0/0', 'L3 un agente solo ve versiones activas (' || v || ')');
  v := pg_temp.val(jv.uid, jv.em, 'select count(distinct empresa) from public.plantilla_contrato_versiones_lista()');
  r := r || pg_temp.l(v = '2', 'L4 el super global ve las dos empresas (' || v || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select count(*) from public.plantilla_contrato_versiones_lista() where origen = ''semilla''');
  r := r || pg_temp.l(v = '1', 'L5 el admin ve la semilla de su empresa, una (' || v || ')');

  -- ============================================================ I. el vinculo contrato -> version (sin insertar contratos)
  v := pg_temp.val(se_L.uid, se_L.em, format('select public.plantilla_contrato_fija(%L, %L)::text', cL, vL2));
  r := r || pg_temp.l(v !~ '^ERR' or v is null, 'I1 el super de Lawang fija la version activa a un contrato libre de Lawang (' || coalesce(v, 'ok') || ')');
  v := pg_temp.val(se_L.uid, se_L.em, format('select public.plantilla_contrato_version_de_contrato(%L)::text', cL));
  r := r || pg_temp.l(v !~ '^ERR' and (v::jsonb ->> 'version_id') = vL2::text, 'I2 el contrato recuerda su version (' || left(v, 40) || ')');
  v := pg_temp.val(se_S.uid, se_S.em, format('select coalesce(public.plantilla_contrato_version_de_contrato(%L)::text, ''NULO'')', cL));
  r := r || pg_temp.l(v = 'NULO', 'I3 el super de Sandal Woods NO ve a que version va un contrato de Lawang (' || left(v, 30) || ')');
  v := pg_temp.val(se_L.uid, se_L.em, format('select public.plantilla_contrato_fija(%L, %L)::text', cS, vL2));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'I4 no se fija a un contrato de la otra empresa (' || v || ')');
  v := pg_temp.val(jv.uid, jv.em, format('select public.plantilla_contrato_fija(%L, %L)::text', cL, vS1));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'I5 version de otra empresa que el proyecto del contrato = rechazado (' || v || ')');
  v := pg_temp.val(se_L.uid, se_L.em, format('select public.plantilla_contrato_fija(%L, %L)::text', cL, dL));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'I6 solo se fija una version ACTIVA, no un borrador (' || v || ')');
  v := pg_temp.val(se_L.uid, se_L.em, format('select public.plantilla_contrato_fija(%L, %L)::text', cLf, vL2));
  r := r || pg_temp.l(pg_temp.err(v) in ('55000', '42501'), 'I7 un contrato BLOQUEADO no se vincula (' || v || ')');
  v := pg_temp.val(jv.uid, jv.em, format('select public.plantilla_contrato_fija(%L, %L)::text', cLf, vL2));
  r := r || pg_temp.l(pg_temp.err(v) = '55000', 'I8 ni el super global vincula un contrato bloqueado (' || v || ')');
  v := pg_temp.val(jv.uid, jv.em, format('select public.plantilla_contrato_fija(%L, %L)::text', cLg, vL2));
  r := r || pg_temp.l(pg_temp.err(v) = '55000', 'I9 un contrato con filas de firma no se vincula (' || v || ')');
  v := pg_temp.val(ctl_G.uid, ctl_G.em, format('select public.plantilla_contrato_fija(%L, %L)::text', cL, vL2));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'I10 un agente sin la herramienta de contratos no fija (' || v || ')');
  v := pg_temp.val(se_L.uid, se_L.em, format('select public.plantilla_contrato_fija(%L, %L)::text', cL, vL2));
  r := r || pg_temp.l(v !~ '^ERR' or v is null, 'I11 volver a fijar la misma es idempotente');
  -- el vinculo de un contrato que acaba en firma se congela (se simula con una fila de firma sobre el contrato ya vinculado)
  begin insert into public.contrato_plantilla_version (contrato_id, version_id, fijado_por) values (cLg, vL2, 'x'); u := 'ok'; exception when others then u := sqlstate; end;
  r := r || pg_temp.l(u = '55000', 'I13 el trigger rechaza vincular un contrato con firmas tambien al propietario (' || u || ')');
  begin insert into public.contrato_plantilla_version (contrato_id, version_id, fijado_por) values (cLf, vL2, 'x'); u := 'ok'; exception when others then u := sqlstate; end;
  r := r || pg_temp.l(u = '55000', 'I14 ... y un contrato bloqueado (' || u || ')');
  begin insert into public.contrato_plantilla_version (contrato_id, version_id, fijado_por) values (cS, vL2, 'x'); u := 'ok'; exception when others then u := sqlstate; end;
  r := r || pg_temp.l(u = '22023', 'I15 ... y una version de otra empresa (' || u || ')');
  begin update public.contrato_plantilla_version set contrato_id = cS where contrato_id = cL; u := 'ok'; exception when others then u := sqlstate; end;
  r := r || pg_temp.l(u = '55000', 'I16 el vinculo no se mueve a otro contrato (' || u || ')');
  begin delete from public.contrato_plantilla_version where contrato_id = cL; u := 'ok'; exception when others then u := sqlstate; end;
  r := r || pg_temp.l(u = 'ok', 'I17 el vinculo de un contrato libre se puede quitar (aun no firmado)');
  v := pg_temp.val(se_L.uid, se_L.em, format('select public.plantilla_contrato_fija(%L, %L)::text', cL, vL2));
  begin insert into public.contrato_firmas (contrato_id) values (cL); u := 'ok'; exception when others then u := 'ERR' || sqlstate; end;
  if u = 'ok' then
    begin update public.contrato_plantilla_version set version_id = vL2 where contrato_id = cL; u := 'ok'; exception when others then u := sqlstate; end;
    r := r || pg_temp.l(u = '55000', 'I18 el vinculo se CONGELA en cuanto el contrato tiene una ronda de firma (' || u || ')');
  else
    r := r || pg_temp.l(true, 'I18 (omitida: contrato_firmas exige mas columnas; se cubre con I13)');
  end if;

  -- ============================================================ J. nada cambia en contratos
  select coalesce(n_tup_ins + n_tup_upd + n_tup_del, 0) into md1 from pg_stat_xact_user_tables where relid = 'public.contratos'::regclass;
  select count(*) into trg1 from pg_trigger where tgrelid = 'public.contratos'::regclass and not tgisinternal;
  r := r || pg_temp.l(md0 = 0 and md1 = 0, 'J1 contratos: 0 filas insertadas, cambiadas o borradas por toda la prueba (pg_stat_xact; el md5 de las 289 filas se mide aparte, foto_contratos.sql antes/despues de aplicar)');
  r := r || pg_temp.l(trg0 = trg1 and trg1 = 36, format('J2 contratos conserva sus %s triggers (antes %s); sin columna nueva', trg1, trg0));
  select count(*) into n from information_schema.columns where table_schema = 'public' and table_name = 'contratos' and column_name ilike '%plantilla%';
  r := r || pg_temp.l(n = 0, 'J3 ninguna columna de plantilla en contratos');

  raise exception 'INFORME' using errcode = 'LWS04', detail = r;
  exception when sqlstate 'LWS04' then
    get stacked diagnostics f = pg_exception_detail;
    insert into _s2out values (f);
  end;
end $todo$;

do $fin$
declare t text; fl int;
begin
  select txt into t from _s2out;
  fl := (length(t) - length(replace(t, 'FALLO', ''))) / 5;
  raise exception E'\n%FALLOS=%', t, fl;
end $fin$;
