-- Prueba de E7 «editor de textos de contrato · revisiones multiples activas» (10-oct-2026). Se pega DESPUES de la migracion 20261010000000 en la MISMA peticion
-- (ensayo sin rastro: el bloque acaba en raise y todo se deshace, migracion incluida si se pega junta). Personas por JWT simulado, como f2_plantillas_s7.sql.
-- NO inserta contratos (nextval no hace rollback): reutiliza el unico contrato libre de commercial_offer de Lawang y su vinculo se vuelve a su sitio al deshacer.
-- NO activa nada en produccion: toda activacion de aqui se deshace. Debe terminar con «FALLOS=0».
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); los borradores, activaciones, archivados y borrados de prueba se deshacen
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
  r text := ''; v text; n bigint; k int; fallos int; j jsonb; md_antes text; md_despues text;
  jv _t7; ae_L _t7; se_L _t7; ae_S _t7; se_S _t7; ctl_L _t7; adm_G _t7;
  pL uuid; ct uuid; ct_antes uuid; body text; fix text; idE uuid; idR1 uuid; idR2 uuid; idR3 uuid; idR1b uuid; id_x uuid; h1 text; h2 text; i int;
  nuevas text[] := array['plantilla_contrato_revision_crea(text,text,uuid,text,text,text)', 'plantilla_contrato_revision_archiva(text,text,text)',
                         'plantilla_contrato_revision_restaura(text,text,text)', 'plantilla_contrato_revision_borra(text,text,text)', 'plantilla_contrato_revisiones_lista(text,text)'];
  cambiadas text[] := array['plantilla_contrato_cuerpo(text,uuid,text,uuid)', 'plantilla_contrato_cuerpo_de_contrato(uuid,text)', 'plantilla_contrato_cuerpo_version(uuid,text)',
                            'plantilla_contrato_versiones_lista(text,text)', 'plantilla_contrato_edicion(text,text,text)', 'plantilla_contrato_guarda_borrador(text,text,text,text,text)',
                            'plantilla_contrato_descarta_borrador(uuid)', 'plantilla_contrato_activa(uuid,text,boolean)', 'plantilla_contrato_fija(uuid,uuid)'];
  f text;
begin
  select * into jv from _t7 where et = 'jv'; select * into ae_L from _t7 where et = 'ae_L'; select * into se_L from _t7 where et = 'se_L'; select * into ae_S from _t7 where et = 'ae_S';
  select * into se_S from _t7 where et = 'se_S'; select * into ctl_L from _t7 where et = 'ctl_L'; select * into adm_G from _t7 where et = 'adm_G';
  select id into pL from public.proyectos where empresa = 'lawang' order by id limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', jv.uid, 'role', 'authenticated', 'email', jv.em)::text, true);
  update public.usuarios set rol = 'admin_empresa', ambito = 'empresa', empresas = '{lawang}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{}', tipos_contrato = '{}' where user_id = ae_L.uid;
  update public.usuarios set rol = 'super_admin_empresa', ambito = 'empresa', empresas = '{lawang}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{}', tipos_contrato = '{}' where user_id = se_L.uid;
  update public.usuarios set rol = 'admin_empresa', ambito = 'empresa', empresas = '{sandal_woods}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{}', tipos_contrato = '{}' where user_id = ae_S.uid;
  update public.usuarios set rol = 'super_admin_empresa', ambito = 'empresa', empresas = '{sandal_woods}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{}', tipos_contrato = '{}' where user_id = se_S.uid;
  update public.usuarios set rol = 'agente', ambito = 'global', empresas = '{lawang}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{}', tipos_contrato = '{}' where user_id = ctl_L.uid;
  update public.usuarios set rol = 'admin', ambito = 'global', empresas = '{}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{}', tipos_contrato = '{}' where user_id = adm_G.uid;
  select md5(string_agg(c::text, '|' order by c.id)) into md_antes from public.contratos c;
  select c.id into ct from public.contratos c join public.proyectos pr on pr.id = c.proyecto_id
   where pr.empresa = 'lawang' and public._plantilla_slug_de_tipo(c.tipo) = 'commercial_offer' and not coalesce(c.bloqueado, false)
     and not exists (select 1 from public.contrato_firmas f where f.contrato_id = c.id) limit 1;
  select l.version_id into ct_antes from public.contrato_plantilla_version l where l.contrato_id = ct;
  r := r || pg_temp.l(ct is not null, 'Z0 datos de partida: hay un contrato libre de commercial_offer en Lawang para probar la fijacion');

  -- ============================================================ A. estructura y exposicion
  select count(*) into n from public.plantilla_contrato_versiones where variante <> 'estandar' or variante_nombre is not null or borrada_en is not null or archivada_en is not null;
  r := r || pg_temp.l(n = 0, 'A1 todas las versiones que ya existian quedan en la revision ''estandar'', sin borrar ni archivar (' || n || ' fuera)');
  select count(*) into n from pg_indexes where tablename = 'plantilla_contrato_versiones'
     and ((indexname = 'plantilla_una_activa' and indexdef like '%(empresa, slug, variante)%' and indexdef like '%activa%')
       or (indexname = 'plantilla_un_borrador' and indexdef like '%(empresa, slug, variante)%' and indexdef like '%borrador%')
       or (indexname = 'plantilla_una_archivada_v' and indexdef like '%(empresa, slug, variante)%'));
  r := r || pg_temp.l(n = 3, 'A2 los indices unicos parciales de activa, borrador y archivada son por (empresa, slug, variante) (' || n || ' de 3)');
  select count(*) into n from unnest(nuevas) x where has_function_privilege('authenticated', 'public.' || x, 'execute');
  r := r || pg_temp.l(n = 5, 'A3 authenticated ejecuta las 5 RPC nuevas (' || n || ')');
  select count(*) into n from unnest(nuevas || cambiadas) x where has_function_privilege('anon', 'public.' || x, 'execute') or has_function_privilege('service_role', 'public.' || x, 'execute');
  r := r || pg_temp.l(n = 0, 'A4 anon y service_role no ejecutan ninguna de las 14 (' || n || ')');
  select count(*) into n from unnest(cambiadas) x where has_function_privilege('authenticated', 'public.' || x, 'execute');
  r := r || pg_temp.l(n = 9, 'A5 las 9 RPC que ya tenian llamador siguen abiertas a authenticated (' || n || ')');
  select count(*) into n from pg_proc where pronamespace = 'public'::regnamespace and proname in ('plantilla_contrato_cuerpo', 'plantilla_contrato_versiones_lista', 'plantilla_contrato_edicion', 'plantilla_contrato_guarda_borrador')
    group by proname having count(*) > 1;
  r := r || pg_temp.l(coalesce(n, 0) = 0, 'A6 ninguna de las 4 funciones de firma nueva conserva una sobrecarga vieja (ambiguedad con los parametros por defecto)');
  select count(*) into n from pg_proc where pronamespace = 'public'::regnamespace and proname like 'plantilla_contrato_revision%'
     and not (prosecdef and proconfig @> array['search_path=""']);
  r := r || pg_temp.l(n = 0, 'A7 las RPC nuevas son SECURITY DEFINER con search_path vacio (' || n || ' mal)');
  select count(*) into n from pg_proc where pronamespace = 'public'::regnamespace
     and proname in ('plantilla_contrato_cuerpo', 'plantilla_contrato_cuerpo_de_contrato', 'plantilla_contrato_cuerpo_version', 'plantilla_contrato_version_de_contrato', 'plantilla_contrato_versiones_lista')
     and pg_get_userbyid(proowner) = 'lw_lector';
  r := r || pg_temp.l(n = 5, 'A8 las 5 lecturas siguen con duenno lw_lector (la RLS filtra como el que llama) (' || n || ')');
  r := r || pg_temp.l(not has_function_privilege('authenticated', 'public._plantilla_parrafos(text)', 'execute') and not has_function_privilege('anon', 'public._plantilla_parrafos(text)', 'execute'),
                      'A9 el ayudante _plantilla_parrafos no tiene EXECUTE para nadie de fuera');
  select count(*) into n from pg_class where relname in ('plantilla_contrato_versiones', 'plantilla_contrato_cuerpos', 'contrato_plantilla_version')
     and (has_table_privilege('authenticated', oid, 'select') or has_table_privilege('authenticated', oid, 'insert') or has_table_privilege('authenticated', oid, 'update')
          or has_table_privilege('authenticated', oid, 'delete') or has_table_privilege('anon', oid, 'select'));
  r := r || pg_temp.l(n = 0, 'A10 ningun GRANT directo sobre las tablas a authenticated ni anon (' || n || ')');
  select count(*) into n from pg_trigger where tgrelid in ('public.plantilla_contrato_versiones'::regclass, 'public.plantilla_contrato_cuerpos'::regclass) and tgname in ('trg_plantilla_version_del', 'trg_plantilla_cuerpo_del', 'trg_plantilla_version_trunc', 'trg_plantilla_cuerpo_trunc');
  r := r || pg_temp.l(n = 4, 'A11 los 4 triggers de no-borrado siguen donde estaban (' || n || ' de 4)');

  -- ============================================================ B. alta de las revisiones (el front actual sigue funcionando sin parametro de variante)
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_edicion(''lawang'', ''commercial_offer'')->>''cuerpo_html''');
  body := v;
  fix := replace(body, 'acabados de alta calidad', 'acabados de calidad superior');
  r := r || pg_temp.l(v not like 'ERR%' and fix <> body, 'B0 la edicion con 2 parametros (front actual) sigue sirviendo el texto de la revision estandar');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_edicion(''lawang'', ''commercial_offer'')->>''variante''');
  r := r || pg_temp.l(v = 'estandar', 'B0b y dice que es la ''estandar'' (' || v || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_guarda_borrador(''lawang'', ''commercial_offer'', %L, ''E7 base'')', body));
  idE := pg_temp.u(v);
  r := r || pg_temp.l(idE is not null, 'B1 guarda_borrador con 4 parametros (front actual) crea el borrador de la revision estandar (' || left(v, 60) || ')');
  v := pg_temp.val(se_L.uid, se_L.em, format('select (public.plantilla_contrato_activa(%L, ''Persona de Prueba'', true))->>''variante''', idE));
  r := r || pg_temp.l(v = 'estandar', 'B2 el super de Lawang activa la estandar (' || left(v, 60) || ')');

  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_revision_crea(''lawang'', ''commercial_offer'', %L, ''Revision de verano'', ''E7 prueba'')', idE));
  idR1 := pg_temp.u(v);
  r := r || pg_temp.l(idR1 is not null, 'B3 el admin crea una revision copiando la estandar (' || left(v, 80) || ')');
  select count(*) into n from public.plantilla_contrato_versiones where id = idR1 and variante = 'rev_1' and variante_nombre = 'Revision de verano' and estado = 'borrador' and origen = 'empresa' and hereda_de = idE and activable;
  r := r || pg_temp.l(n = 1, 'B4 nace borrador de empresa, variante rev_1 con su nombre, heredada de la estandar y activable');
  select count(*) into n from public.plantilla_contrato_versiones v1 join public.plantilla_contrato_cuerpos c1 on c1.version_id = v1.id join public.plantilla_contrato_cuerpos c0 on c0.version_id = idE
   where v1.id = idR1 and c1.cuerpo_html = c0.cuerpo_html and v1.hash = (select hash from public.plantilla_contrato_versiones where id = idE);
  r := r || pg_temp.l(n = 1, 'B5 la copia es identica a su origen (mismo cuerpo, mismo hash)');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_revision_crea(''lawang'', ''commercial_offer'', %L, ''Copia exacta'', ''E7 prueba'')', idE));
  idR2 := pg_temp.u(v);
  select variante into v from public.plantilla_contrato_versiones where id = idR2;
  r := r || pg_temp.l(idR2 is not null and v = 'rev_2', 'B6 la segunda revision recibe la clave rev_2 sola (' || coalesce(v, '?') || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_guarda_borrador(''lawang'', ''commercial_offer'', %L, ''E7 cambio'', ''rev_1'')', fix));
  r := r || pg_temp.l(pg_temp.u(v) = idR1, 'B7 guardar en rev_1 actualiza SU borrador (mismo id), no abre otro (' || left(v, 40) || ')');
  select count(*) into n from public.plantilla_contrato_versiones where empresa = 'lawang' and slug = 'commercial_offer' and variante = 'estandar' and estado = 'borrador' and origen = 'empresa';
  r := r || pg_temp.l(n = 0, 'B8 y la estandar no ha recibido ningun borrador nuevo (' || n || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_guarda_borrador(''lawang'', ''commercial_offer'', %L, ''E7 cambio'', ''rev_9'')', fix));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'B9 guardar en una revision que no existe: 22023, no la inventa (' || left(v, 70) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_guarda_borrador(''lawang'', ''commercial_offer'', %L, ''E7 cambio'', ''MAL!'')', fix));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'B10 una clave de revision con simbolos: 22023 (' || left(v, 50) || ')');
  v := pg_temp.val(se_L.uid, se_L.em, format('select (public.plantilla_contrato_activa(%L, ''Persona de Prueba'', true))->>''variante''', idR1));
  r := r || pg_temp.l(v = 'rev_1', 'B11 el super activa rev_1 (' || left(v, 60) || ')');
  v := pg_temp.val(se_L.uid, se_L.em, format('select (public.plantilla_contrato_activa(%L, ''Persona de Prueba'', true))->>''variante''', idR2));
  r := r || pg_temp.l(v = 'rev_2', 'B12 y rev_2 (' || left(v, 60) || ')');
  select count(*) into n from public.plantilla_contrato_versiones where empresa = 'lawang' and slug = 'commercial_offer' and estado = 'activa';
  r := r || pg_temp.l(n = 3, 'B13 la plantilla tiene TRES versiones activas a la vez (estandar, rev_1, rev_2): ninguna retiro a otra (' || n || ')');
  select count(*) into n from public.plantilla_contrato_versiones where id in (idE, idR1, idR2) and estado = 'activa';
  r := r || pg_temp.l(n = 3, 'B14 las tres siguen activas por id (' || n || ')');

  -- ============================================================ C. cada consumidor devuelve la version que corresponde
  v := pg_temp.val(ctl_L.uid, ctl_L.em, format('select (public.plantilla_contrato_cuerpo(''commercial_offer'', %L))->>''version_id''', pL));
  r := r || pg_temp.l(pg_temp.u(v) = idE, 'C1 plantilla_contrato_cuerpo sin elegir sigue sirviendo la revision estandar (compatible con lo de siempre) (' || left(v, 40) || ')');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, format('select (public.plantilla_contrato_cuerpo(''commercial_offer'', %L, null, %L))->>''version_id''', pL, idR1));
  r := r || pg_temp.l(pg_temp.u(v) = idR1, 'C2 eligiendo rev_1 sirve rev_1 (' || left(v, 40) || ')');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, format('select (public.plantilla_contrato_cuerpo(''commercial_offer'', %L, null, %L))->>''cuerpo_html''', pL, idR1));
  r := r || pg_temp.l(v like '%calidad superior%' and v not like '%alta calidad%', 'C3 y trae el texto DE rev_1 (el cambio), no el de la estandar');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, format('select (public.plantilla_contrato_cuerpo(''commercial_offer'', %L, null, %L))->>''variante_nombre''', pL, idR1));
  r := r || pg_temp.l(v = 'Revision de verano', 'C3b y dice como se llama (' || v || ')');
  select v0.id into id_x from public.plantilla_contrato_versiones v0 where v0.empresa = 'lawang' and v0.slug = 'carta_reserva' and v0.origen = 'semilla';
  v := pg_temp.val(ctl_L.uid, ctl_L.em, format('select (public.plantilla_contrato_cuerpo(''commercial_offer'', %L, null, %L))->>''version_id''', pL, id_x));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'C4 pedir con otra plantilla una revision de ESTA: 22023 (' || left(v, 60) || ')');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, format('select (public.plantilla_contrato_cuerpo_version(%L))->>''variante''', idR1));
  r := r || pg_temp.l(v = 'rev_1', 'C5 cuerpo_version de una activa para un agente que no es admin: la lee y dice su variante (' || left(v, 40) || ')');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, 'select count(*) from public.plantilla_contrato_versiones_lista(''lawang'', ''commercial_offer'') where estado = ''activa''');
  r := r || pg_temp.l(v = '3', 'C6 el selector (versiones_lista de un agente) ofrece las 3 activas (' || v || ')');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, 'select string_agg(distinct variante, '','' order by variante) from public.plantilla_contrato_versiones_lista(''lawang'', ''commercial_offer'')');
  r := r || pg_temp.l(v = 'estandar,rev_1,rev_2', 'C7 con su variante a la vista (' || v || ')');
  v := pg_temp.pg('select public._plantilla_esqueleto(''lawang'', ''commercial_offer'') = (select cuerpo_html from public.plantilla_contrato_cuerpos where version_id = ''' || idE || ''')');
  r := r || pg_temp.l(v = 'true', 'C8 el esqueleto de validacion es uno solo: el de la estandar, aunque haya otras activas');

  -- fijar un contrato a una revision
  v := pg_temp.val(jv.uid, jv.em, format('select public.plantilla_contrato_fija(%L, null)', ct));
  r := r || pg_temp.l(pg_temp.err(v) = '22023' and v like '%varias revisiones%', 'C9 fijar SIN elegir cuando hay revisiones: error claro y no adivina (' || left(v, 90) || ')');
  v := pg_temp.val(jv.uid, jv.em, format('select public.plantilla_contrato_fija(%L, %L)', ct, idR1));
  r := r || pg_temp.l(v not like 'ERR%', 'C10 fijar eligiendo rev_1 (' || left(v, 60) || ')');
  v := pg_temp.val(jv.uid, jv.em, format('select (public.plantilla_contrato_cuerpo_de_contrato(%L))->>''version_id''', ct));
  r := r || pg_temp.l(pg_temp.u(v) = idR1, 'C11 el contrato lee la version que se le fijo, no la estandar (' || left(v, 40) || ')');
  v := pg_temp.val(jv.uid, jv.em, format('select (public.plantilla_contrato_cuerpo_de_contrato(%L))->>''variante_nombre''', ct));
  r := r || pg_temp.l(v = 'Revision de verano', 'C12 y trae el nombre de la revision para el bot (slug/nombre/version salen de la version fijada) (' || v || ')');
  v := pg_temp.pg(format('select public.plantilla_contrato_version_de_contrato(%L)->>''variante''', ct));
  r := r || pg_temp.l(v = 'rev_1', 'C13 version_de_contrato tambien dice la variante');
  v := pg_temp.val(jv.uid, jv.em, format('select public.plantilla_contrato_fija(%L, %L)', ct, id_x));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'C14 fijar una version de OTRA plantilla: 22023 (' || left(v, 60) || ')');
  v := pg_temp.val(jv.uid, jv.em, format('select public.plantilla_contrato_fija(%L, %L)', ct, idE));
  v := pg_temp.val(jv.uid, jv.em, format('select (public.plantilla_contrato_cuerpo_de_contrato(%L))->>''version_id''', ct));
  r := r || pg_temp.l(pg_temp.u(v) = idE, 'C15 cambiar de revision es un acto explicito y funciona (' || left(v, 40) || ')');
  v := pg_temp.val(jv.uid, jv.em, format('select public.plantilla_contrato_fija(%L, %L)', ct, idR1));

  -- nueva version dentro de rev_1: solo retira la anterior de rev_1
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_guarda_borrador(''lawang'', ''commercial_offer'', %L, ''E7 segunda'', ''rev_1'')', replace(fix, 'calidad superior', 'calidad excelente')));
  idR1b := pg_temp.u(v);
  r := r || pg_temp.l(idR1b is not null and idR1b <> idR1, 'C16 una vez activa rev_1, guardar abre un borrador NUEVO dentro de rev_1 (' || left(v, 40) || ')');
  v := pg_temp.val(se_L.uid, se_L.em, format('select (public.plantilla_contrato_activa(%L, ''Persona de Prueba'', true))->>''variante''', idR1b));
  select count(*) into n from public.plantilla_contrato_versiones where empresa = 'lawang' and slug = 'commercial_offer' and estado = 'activa';
  r := r || pg_temp.l(v = 'rev_1' and n = 3, 'C17 activar la nueva de rev_1 retira SOLO la anterior de rev_1: siguen 3 activas, una por revision (' || n || ')');
  select estado into v from public.plantilla_contrato_versiones where id = idR1;
  r := r || pg_temp.l(v = 'retirada', 'C18 la anterior de rev_1 queda retirada (' || v || ')');
  select count(*) into n from public.plantilla_contrato_versiones where id in (idE, idR2) and estado = 'activa';
  r := r || pg_temp.l(n = 2, 'C19 la estandar y rev_2 no se movieron (' || n || ')');
  v := pg_temp.val(jv.uid, jv.em, format('select (public.plantilla_contrato_cuerpo_de_contrato(%L))->>''version_id''', ct));
  r := r || pg_temp.l(pg_temp.u(v) = idR1, 'C20 el contrato fijado a la version retirada de rev_1 sigue leyendo SU texto (' || left(v, 40) || ')');

  -- ============================================================ D. archivar y restaurar
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select count(*) from public.plantilla_contrato_revisiones_lista(''lawang'', ''commercial_offer'')');
  r := r || pg_temp.l(v = '3', 'D0 la lista de revisiones trae estandar, rev_1 y rev_2 (' || v || ')');
  select md5(c.cuerpo_html), v0.hash into h1, h2 from public.plantilla_contrato_cuerpos c join public.plantilla_contrato_versiones v0 on v0.id = c.version_id where c.version_id = idR2;
  v := pg_temp.val(jv.uid, jv.em, format('select public.plantilla_contrato_fija(%L, %L)', ct, idR2));
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_revision_archiva(''lawang'', ''commercial_offer'', ''rev_2'')');
  r := r || pg_temp.l(v not like 'ERR%', 'D1 el admin archiva rev_2 (' || left(v, 60) || ')');
  select estado into v from public.plantilla_contrato_versiones where id = idR2;
  r := r || pg_temp.l(v = 'archivada', 'D2 queda archivada (' || v || ')');
  select count(*) into n from public.plantilla_contrato_cuerpos c join public.plantilla_contrato_versiones v0 on v0.id = c.version_id where c.version_id = idR2 and md5(c.cuerpo_html) = h1 and v0.hash = h2;
  r := r || pg_temp.l(n = 1, 'D3 archivar no mueve ni cambia el cuerpo ni el hash');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, 'select count(*) from public.plantilla_contrato_versiones_lista(''lawang'', ''commercial_offer'') where estado = ''activa'' and variante = ''rev_2''');
  r := r || pg_temp.l(v = '0', 'D4 la archivada ya no sale entre las activas que se ofrecen (' || v || ')');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, format('select (public.plantilla_contrato_cuerpo(''commercial_offer'', %L, null, %L))->>''version_id''', pL, idR2));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'D5 y no se puede elegir para un contrato nuevo (' || left(v, 50) || ')');
  v := pg_temp.val(jv.uid, jv.em, format('select public.plantilla_contrato_fija(%L, %L)', ct, idR2));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'D6 ni fijar a ella (' || left(v, 50) || ')');
  v := pg_temp.val(jv.uid, jv.em, format('select (public.plantilla_contrato_cuerpo_de_contrato(%L))->>''version_id''', ct));
  r := r || pg_temp.l(pg_temp.u(v) = idR2, 'D7 el contrato que YA la usaba la sigue leyendo aunque este archivada (' || left(v, 40) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_revision_archiva(''lawang'', ''commercial_offer'', ''estandar'')');
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'D8 la estandar no se archiva (' || left(v, 60) || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, 'select public.plantilla_contrato_revision_archiva(''lawang'', ''commercial_offer'', ''rev_1'')');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'D9 un admin de Sandal Woods no archiva en Lawang (' || left(v, 40) || ')');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, 'select public.plantilla_contrato_revision_archiva(''lawang'', ''commercial_offer'', ''rev_1'')');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'D10 un agente que no es admin no archiva (' || left(v, 40) || ')');
  v := pg_temp.val(null, null, 'select public.plantilla_contrato_revision_archiva(''lawang'', ''commercial_offer'', ''rev_1'')', 'anon');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'D11 anon no ejecuta (' || left(v, 40) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_revision_restaura(''lawang'', ''commercial_offer'', ''rev_2'')');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'D12 restaurar (volver a poner un texto en uso) no es de un admin simple (' || left(v, 40) || ')');
  v := pg_temp.val(se_S.uid, se_S.em, 'select public.plantilla_contrato_revision_restaura(''lawang'', ''commercial_offer'', ''rev_2'')');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'D13 ni el super de OTRA empresa (' || left(v, 40) || ')');
  v := pg_temp.val(se_L.uid, se_L.em, 'select (public.plantilla_contrato_revision_restaura(''lawang'', ''commercial_offer'', ''rev_2''))->>''variante''');
  r := r || pg_temp.l(v = 'rev_2', 'D14 el super de Lawang la restaura (' || left(v, 60) || ')');
  select estado into v from public.plantilla_contrato_versiones where id = idR2;
  r := r || pg_temp.l(v = 'activa', 'D15 vuelve a estar activa (' || v || ')');
  v := pg_temp.val(se_L.uid, se_L.em, 'select public.plantilla_contrato_revision_restaura(''lawang'', ''commercial_offer'', ''rev_2'')');
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'D16 restaurar una que no esta archivada: 22023 (' || left(v, 50) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_revision_archiva(''lawang'', ''commercial_offer'', ''rev_2'')');

  -- ============================================================ E. borrar: solo si ningun contrato la usa
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_revision_borra(''lawang'', ''commercial_offer'', ''rev_2'')');
  r := r || pg_temp.l(pg_temp.err(v) = '55000' and v like '%1 contrato%', 'E1 borrar una revision con un contrato vinculado FALLA y lo dice en llano (' || left(v, 120) || ')');
  select count(*) into n from public.plantilla_contrato_versiones where id = idR2 and borrada_en is null and estado = 'archivada';
  r := r || pg_temp.l(n = 1, 'E2 y no se ha tocado nada');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_revision_borra(''lawang'', ''commercial_offer'', ''rev_1'')');
  r := r || pg_temp.l(pg_temp.err(v) = '55000', 'E3 una revision ACTIVA no se borra, hay que archivarla antes (' || left(v, 80) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_revision_borra(''lawang'', ''commercial_offer'', ''estandar'')');
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'E4 la estandar no se borra (' || left(v, 50) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_revision_borra(''lawang'', ''commercial_offer'', ''rev_77'')');
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'E5 una que no existe: 22023 (' || left(v, 50) || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, 'select public.plantilla_contrato_revision_borra(''lawang'', ''commercial_offer'', ''rev_2'')');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'E6 otra empresa no borra (' || left(v, 40) || ')');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, 'select public.plantilla_contrato_revision_borra(''lawang'', ''commercial_offer'', ''rev_2'')');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'E7 un agente que no es admin no borra (' || left(v, 40) || ')');
  -- una sin contratos: se crea, se ve en la lista con 0 contratos y se borra
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_revision_crea(''lawang'', ''commercial_offer'', %L, ''Para borrar'', ''E7 prueba'', ''para_borrar'')', idE));
  idR3 := pg_temp.u(v);
  r := r || pg_temp.l(idR3 is not null, 'E8 crear una revision con clave propia (' || left(v, 60) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_revision_borra(''lawang'', ''commercial_offer'', ''para_borrar'')');
  r := r || pg_temp.l(v not like 'ERR%', 'E9 borrar una revision sin contratos funciona (' || left(v, 80) || ')');
  select count(*) into n from public.plantilla_contrato_versiones where id = idR3 and borrada_en is not null and borrada_por is not null;
  r := r || pg_temp.l(n = 1, 'E10 es un borrado LOGICO: la fila sigue, marcada con quien y cuando');
  select count(*) into n from public.plantilla_contrato_cuerpos where version_id = idR3;
  r := r || pg_temp.l(n = 1, 'E11 y su cuerpo sigue en su sitio (nada se mueve ni se borra)');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select count(*) from public.plantilla_contrato_revisiones_lista(''lawang'', ''commercial_offer'') where variante = ''para_borrar''');
  r := r || pg_temp.l(v = '0', 'E12 la borrada no sale en la lista de revisiones (' || v || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select count(*) from public.plantilla_contrato_versiones_lista(''lawang'', ''commercial_offer'') where variante = ''para_borrar''');
  r := r || pg_temp.l(v = '0', 'E13 ni en la lista de versiones');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_edicion(''lawang'', ''commercial_offer'', ''para_borrar'')::text');
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'E14 ni se puede abrir para editar (' || left(v, 50) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_cuerpo_version(%L)::text', idR3));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'E15 ni leer su cuerpo (' || left(v, 40) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_descarta_borrador(%L)', idR3));
  r := r || pg_temp.l(pg_temp.err(v) = '55000', 'E16 ni descartar su borrador (' || left(v, 50) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_guarda_borrador(''lawang'', ''commercial_offer'', %L, ''E7 x'', ''para_borrar'')', fix));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'E17 ni guardar en ella (' || left(v, 60) || ')');
  v := pg_temp.pg(format('update public.plantilla_contrato_versiones set borrada_en = null, borrada_por = null where id = %L', idR3));
  r := r || pg_temp.l(pg_temp.err(v) = '55000', 'E18 una borrada no se recupera ni por SQL directo (trigger) (' || left(v, 60) || ')');
  v := pg_temp.pg(format('delete from public.plantilla_contrato_versiones where id = %L', idR3));
  r := r || pg_temp.l(pg_temp.err(v) = '55000', 'E19 el borrado fisico sigue prohibido (trigger de no-borrado) (' || left(v, 60) || ')');
  v := pg_temp.val(jv.uid, jv.em, format('select public.plantilla_contrato_fija(%L, %L)', ct, idR3));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'E20 y no se puede fijar un contrato a una borrada (' || left(v, 50) || ')');
  v := pg_temp.val(jv.uid, jv.em, format('select public.plantilla_contrato_fija(%L, %L)', ct, idE));
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_revision_borra(''lawang'', ''commercial_offer'', ''rev_2'')');
  r := r || pg_temp.l(v not like 'ERR%', 'E21 cuando el contrato ya no la usa, rev_2 (archivada) se puede borrar (' || left(v, 80) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_revision_crea(''lawang'', ''commercial_offer'', ''' || idE || ''', ''Otra vez'', ''E7 prueba'', ''rev_2'')');
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'E22 y su clave no se reutiliza: 22023 (' || left(v, 70) || ')');

  -- ============================================================ F. lista de revisiones: contratos que la usan y parrafos distintos del origen
  v := pg_temp.val(jv.uid, jv.em, format('select public.plantilla_contrato_fija(%L, %L)', ct, idR1b));
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select contratos || ''/'' || coalesce(parrafos_distintos::text, ''null'') from public.plantilla_contrato_revisiones_lista(''lawang'', ''commercial_offer'') where variante = ''rev_1''');
  r := r || pg_temp.l(v like '1/%' and v not like '%/0' and v not like '%null', 'F1 rev_1: 1 contrato la usa y tiene parrafos distintos de su origen (' || v || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select coalesce(parrafos_distintos::text, ''null'') || ''/'' || contratos from public.plantilla_contrato_revisiones_lista(''lawang'', ''commercial_offer'') where variante = ''estandar''');
  r := r || pg_temp.l(v = 'null/0', 'F2 la estandar no tiene origen que comparar y 0 contratos (ahora el contrato esta en rev_1) (' || v || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_revision_crea(''lawang'', ''commercial_offer'', %L, ''Identica'', ''E7 prueba'')', idE));
  idR3 := pg_temp.u(v);
  select variante into h1 from public.plantilla_contrato_versiones where id = idR3;
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select parrafos_distintos::text from public.plantilla_contrato_revisiones_lista(''lawang'', ''commercial_offer'') where variante = %L', h1));
  r := r || pg_temp.l(v = '0', 'F3 una copia sin tocar tiene 0 parrafos distintos (' || v || ')');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, 'select count(*) from public.plantilla_contrato_revisiones_lista(''lawang'', null)');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'F4 un agente que no es admin no ve la lista de revisiones (' || left(v, 40) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select count(*) from public.plantilla_contrato_revisiones_lista(''sandal_woods'', null)');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'F5 ni un admin de Lawang la de Sandal Woods (' || left(v, 40) || ')');

  -- ============================================================ G. aislamiento entre empresas
  v := pg_temp.val(ae_S.uid, ae_S.em, format('select public.plantilla_contrato_revision_crea(''sandal_woods'', ''commercial_offer'', %L, ''Robada'', ''E7 prueba'')', idE));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'G1 crear una revision en Sandal Woods copiando un texto de LAWANG: 22023 (' || left(v, 60) || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, format('select public.plantilla_contrato_revision_crea(''lawang'', ''commercial_offer'', %L, ''Robada'', ''E7 prueba'')', idE));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'G2 ni crear en Lawang siendo de Sandal Woods (' || left(v, 40) || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, format('select (public.plantilla_contrato_cuerpo(''commercial_offer'', null, null, %L))->>''version_id''', idR1b));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'G3 un agente de Sandal Woods no obtiene por id una revision de Lawang (' || left(v, 50) || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, format('select public.plantilla_contrato_cuerpo_version(%L)::text', idR1b));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'G4 ni por cuerpo_version (' || left(v, 40) || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, 'select count(*) from public.plantilla_contrato_versiones_lista(null, null) where empresa = ''lawang''');
  r := r || pg_temp.l(v = '0', 'G5 su lista no trae ninguna fila de Lawang (' || v || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, 'select public.plantilla_contrato_edicion(''lawang'', ''commercial_offer'', ''rev_1'')::text');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'G6 ni abrir para editar una revision de Lawang (' || left(v, 40) || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, format('select public.plantilla_contrato_guarda_borrador(''lawang'', ''commercial_offer'', %L, ''E7 x'', ''rev_1'')', fix));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'G7 ni guardar en ella (' || left(v, 40) || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, 'select count(*) from public.plantilla_contrato_versiones_lista(''sandal_woods'', ''commercial_offer'') where variante <> ''estandar''');
  r := r || pg_temp.l(v = '0', 'G8 Sandal Woods no hereda revisiones de Lawang: solo ve la estandar (' || v || ')');

  -- ============================================================ H. claves y tope
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_revision_crea(''lawang'', ''commercial_offer'', %L, ''Duplicada'', ''E7 prueba'', ''rev_1'')', idE));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'H1 clave ya usada: 22023 (' || left(v, 50) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_revision_crea(''lawang'', ''commercial_offer'', %L, ''Estandar'', ''E7 prueba'', ''estandar'')', idE));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'H2 la clave ''estandar'' esta reservada (' || left(v, 50) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_revision_crea(''lawang'', ''commercial_offer'', %L, ''Mal'', ''E7 prueba'', ''Rev-1;drop'')', idE));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'H3 una clave con simbolos: 22023 (' || left(v, 50) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_revision_crea(''lawang'', ''commercial_offer'', %L, ''  '', ''E7 prueba'')', idE));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'H4 sin nombre: 22023 (' || left(v, 50) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_revision_crea(''lawang'', ''commercial_offer'', %L, ''Sin motivo'', ''x'')', idE));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'H5 sin motivo: 22023 (' || left(v, 50) || ')');
  k := 0;
  for i in 1..25 loop
    v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_revision_crea(''lawang'', ''commercial_offer'', %L, %L, ''E7 tope'')', idE, 'Tope ' || i));
    exit when v like 'ERR%';
    k := k + 1;
  end loop;
  select count(distinct variante) into n from public.plantilla_contrato_versiones where empresa = 'lawang' and slug = 'commercial_offer' and borrada_en is null;
  r := r || pg_temp.l(v like 'ERR22023%' and n = 20, 'H6 tope de 20 revisiones por contrato: la 21 se rechaza (' || n || ' revisiones; ' || left(v, 60) || ')');

  -- ============================================================ I. inmutabilidad (por SQL directo, saltandose las RPC)
  v := pg_temp.pg(format('update public.plantilla_contrato_versiones set variante = ''otra'' where id = %L', idE));
  r := r || pg_temp.l(pg_temp.err(v) = '55000', 'I1 la variante de una version no se cambia (identidad inmutable) (' || left(v, 40) || ')');
  v := pg_temp.pg(format('update public.plantilla_contrato_versiones set hash = repeat(''a'', 64) where id = %L', idR1b));
  r := r || pg_temp.l(pg_temp.err(v) = '55000', 'I2 una activa sigue inmutable salvo su estado (' || left(v, 40) || ')');
  v := pg_temp.pg(format('update public.plantilla_contrato_versiones set estado = ''borrador'' where id = %L', idR1b));
  r := r || pg_temp.l(pg_temp.err(v) = '55000', 'I3 una activa no vuelve a borrador (' || left(v, 40) || ')');
  select v0.id into id_x from public.plantilla_contrato_versiones v0 where v0.empresa = 'lawang' and v0.slug = 'commercial_offer' and v0.variante = 'rev_2' and v0.estado = 'archivada';
  v := pg_temp.pg(format('update public.plantilla_contrato_cuerpos set cuerpo_html = cuerpo_html || '' '' where version_id = %L', coalesce(id_x, idR2)));
  r := r || pg_temp.l(pg_temp.err(v) = '55000', 'I4 el cuerpo de una archivada no se modifica (' || left(v, 40) || ')');
  v := pg_temp.pg(format('update public.plantilla_contrato_versiones set estado = ''archivada'' where id = %L', idR3));
  r := r || pg_temp.l(pg_temp.err(v) = '55000', 'I5 un borrador no se archiva por la puerta de atras (' || left(v, 40) || ')');
  -- indice unico de verdad: un borrador REAL en rev_1 (por la RPC) y luego, saltandose las RPC, un segundo borrador y una segunda activa
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_guarda_borrador(''lawang'', ''commercial_offer'', %L, ''E7 indice'', ''rev_1'')', replace(fix, 'calidad superior', 'calidad notable')));
  id_x := pg_temp.u(v);
  r := r || pg_temp.l(id_x is not null, 'I6a un borrador real nuevo en rev_1 (' || left(v, 40) || ')');
  v := pg_temp.run('insert into public.plantilla_contrato_versiones (empresa, slug, version, estado, origen, idioma_set, hash, bytes, activable, autor, variante) values (''lawang'', ''commercial_offer'', 998, ''borrador'', ''empresa'', ''{es}'', repeat(''a'', 64), 1, true, ''x'', ''rev_1'')');
  r := r || pg_temp.l(pg_temp.err(v) = '23505', 'I6 dos borradores en la misma revision chocan en el indice unico (' || left(v, 60) || ')');
  v := pg_temp.run(format('update public.plantilla_contrato_versiones set estado = ''activa'', activado_por = ''x'', activado_en = now(), confirmacion_nombre = ''x'', confirmacion_texto = ''x'' where id = %L', id_x));
  r := r || pg_temp.l(pg_temp.err(v) = '23505', 'I7 una segunda activa en la MISMA revision no cabe: salta el indice unico, no otra cosa (' || left(v, 60) || ')');

  select md5(string_agg(c::text, '|' order by c.id)) into md_despues from public.contratos c;
  r := r || pg_temp.l(md_antes = md_despues, 'J1 las filas de contratos son byte a byte las mismas antes y despues');
  select count(*) into n from pg_trigger where tgrelid = 'public.contratos'::regclass and not tgisinternal and tgname ilike '%plantilla%';
  r := r || pg_temp.l(n = 0, 'J2 ningun trigger de plantillas en contratos (' || n || ')');
  select count(*) into n from public.plantilla_contrato_versiones v join public.plantilla_contrato_cuerpos c on c.version_id = v.id where v.hash <> public._plantilla_hash(c.cuerpo_html);
  r := r || pg_temp.l(n = 0, 'J3 el hash de cada version casa con su cuerpo (' || n || ' mal)');
  select count(*) into n from public.plantilla_contrato_versiones where origen = 'semilla' and (estado <> 'borrador' or variante <> 'estandar');
  r := r || pg_temp.l(n = 0, 'J4 las 40 semillas siguen intactas: borrador, estandar (' || n || ' mal)');
  select count(*) into n from (select empresa, slug, variante from public.plantilla_contrato_versiones where estado = 'activa' and borrada_en is null group by 1, 2, 3 having count(*) > 1) q;
  r := r || pg_temp.l(n = 0, 'J5 nunca hay dos activas en la misma revision (' || n || ')');

  fallos := (select count(*) from regexp_matches(r, 'FALLO', 'g'));
  raise exception E'INFORME E7\n%FALLOS=%', r, fallos;
end $todo$;
