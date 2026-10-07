-- Prueba de la migracion 20261008990100 (S2 · bloqueos F1 y F2 de plantillas por empresa), 7-oct-2026. Se pega DESPUES de la migracion y de S2+S3 en la MISMA peticion (o con todo ya aplicado):
-- corre en una transaccion que acaba en raise (rollback), con GRANT temporal a authenticated de las 8 RPC (en produccion no lo tienen hasta S5/S7). Debe terminar con «FALLOS=0».
-- No imprime ni escribe ningun dato de sociedad: los textos de la bateria se construyen en vuelo desde `sociedades`. No inserta contratos.
-- Compone con las pruebas de S2 (f2_plantillas_s2.sql, con su stub del validador; ver tambien su parte H, que ahora necesita el GRANT temporal) y de S3 (f2_plantillas_s3.sql: su parte D se acota a SUS 9 funciones).
-- destructivo-ok: prueba en transaccion que termina en raise (rollback)
create temp table _t5 (et text primary key, uid uuid, em text);
create temp table _t5out (txt text);
create or replace function pg_temp.l(c boolean, t text) returns text language sql as $f$ select case when coalesce(c, false) then 'OK    ' else 'FALLO ' end || t || E'\n' $f$;
create or replace function pg_temp.val(p_uid uuid, p_email text, p_sql text, p_role text default 'authenticated') returns text language plpgsql as $f$
declare t text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'email', p_email)::text, true);
  execute format('set local role %I', p_role);
  begin execute p_sql into t; exception when others then t := 'ERR' || sqlstate || ':' || left(sqlerrm, 160); end;
  execute 'reset role';
  return t;
end $f$;
create or replace function pg_temp.err(t text) returns text language sql immutable as $f$ select case when t like 'ERR%' then substr(t, 4, 5) end $f$;
-- ancho completo: cada letra ASCII -> su forma de U+FF21..FF5A
create or replace function pg_temp.ancho(t text) returns text language sql immutable as $f$
  select string_agg(case when c ~ '[A-Za-z]' then chr(ascii(c) + 65248) else c end, '' order by o) from regexp_split_to_table(t, '') with ordinality as x(c, o) $f$;

insert into _t5 select 'jv', user_id, email from public.usuarios where email = 'jvr.cervantes@gmail.com';
insert into _t5 select (array['ae_L', 'se_L', 'ae_S', 'se_S'])[rn], user_id, email
  from (select user_id, email, row_number() over (order by email) rn from (select user_id, email from public.usuarios where activo and ambito = 'global' and rol = 'agente' order by email limit 4) q) z;

do $todo$
declare
  r text := ''; n bigint; v text; u text; ok boolean; t0 timestamptz; ms numeric;
  jv _t5; ae_L _t5; se_L _t5; ae_S _t5; se_S _t5;
  skel text := '<h2><span data-lang="es">Las Partes</span></h2><p data-lang="es">{{prom_razon}}, con NPWP {{prom_npwp}}.</p><h2><span data-lang="es">Objeto</span></h2><p data-lang="es">Texto libre uno de la plantilla.</p><h2><span data-lang="es">Ley aplicable, arbitraje e idioma</span></h2><p data-lang="es">Las controversias van a arbitraje SIAC en Singapur.</p><p data-lang="es">Texto final libre.</p>';
  skel_m text := '<p data-lang="es">Libre A</p><!--bloque-fijo:tenencia--><p data-lang="es">Estructura fija X</p><!--/bloque-fijo:tenencia--><p data-lang="es">Libre B</p>';
  razT text; npwpT text; domT text; razS text; seg text; id1 uuid; k int;
  fn8 text[] := array['plantilla_contrato_guarda_borrador(text,text,text,text)', 'plantilla_contrato_activa(uuid,text,boolean)', 'plantilla_contrato_descarta_borrador(uuid)',
                      'plantilla_contrato_cuerpo(text,uuid,text)', 'plantilla_contrato_cuerpo_version(uuid,text)', 'plantilla_contrato_version_de_contrato(uuid)',
                      'plantilla_contrato_versiones_lista(text,text)', 'plantilla_contrato_fija(uuid,uuid)'];
  f9 text;
begin
  select * into jv from _t5 where et = 'jv'; select * into ae_L from _t5 where et = 'ae_L'; select * into se_L from _t5 where et = 'se_L';
  select * into ae_S from _t5 where et = 'ae_S'; select * into se_S from _t5 where et = 'se_S';
  select razon, regexp_replace(npwp, '[^0-9]', '', 'g'), domicilio into razT, npwpT, domT from public.sociedades where clave = 'tepi_sungai';
  select razon into razS from public.sociedades where clave = 'san_dal_woods';

  begin
  perform set_config('request.jwt.claims', json_build_object('sub', jv.uid, 'role', 'authenticated', 'email', jv.em)::text, true);
  update public.usuarios set rol = 'admin_empresa', ambito = 'empresa', empresas = '{lawang}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{ajustes,facturas,gastos,usuarios}', tipos_contrato = '{}' where user_id = ae_L.uid;
  update public.usuarios set rol = 'super_admin_empresa', ambito = 'empresa', empresas = '{lawang}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{contratos}', tipos_contrato = '{}' where user_id = se_L.uid;
  update public.usuarios set rol = 'admin_empresa', ambito = 'empresa', empresas = '{sandal_woods}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{ajustes,facturas,gastos,usuarios}', tipos_contrato = '{}' where user_id = ae_S.uid;
  update public.usuarios set rol = 'super_admin_empresa', ambito = 'empresa', empresas = '{sandal_woods}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{contratos}', tipos_contrato = '{}' where user_id = se_S.uid;

  -- ============================================================ A. permisos (antes del GRANT temporal)
  select count(*) into n from unnest(array['anon', 'authenticated', 'service_role']) ro cross join unnest(array['plantilla_sociedad_cruce', 'plantilla_nunca_activable', 'plantilla_solo_global', 'plantilla_ficha', 'plantilla_bloque_regla']) t
   where has_table_privilege(ro, 'public.' || t, 'select,insert,update,delete,truncate,references,trigger');
  r := r || pg_temp.l(n = 0, format('A1 las 5 tablas de politica no tienen ningun privilegio para anon, authenticated ni service_role (%s)', n));
  select count(*) into n from pg_class where oid in ('public.plantilla_sociedad_cruce'::regclass, 'public.plantilla_nunca_activable'::regclass, 'public.plantilla_solo_global'::regclass, 'public.plantilla_ficha'::regclass, 'public.plantilla_bloque_regla'::regclass) and relrowsecurity;
  r := r || pg_temp.l(n = 5, 'A2 RLS activa en las 5');
  select count(*) into n from unnest(fn8) x where has_function_privilege('authenticated', 'public.' || x, 'execute') or has_function_privilege('anon', 'public.' || x, 'execute') or has_function_privilege('service_role', 'public.' || x, 'execute');
  r := r || pg_temp.l(n = 0, format('A3 las 8 RPC de usuario de S2 no son ejecutables por nadie del API hasta que S5/S7 las llamen (%s)', n));
  select count(*) into n from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname like '\_plantilla\_%' or p.proname like 'plantilla\_cuerpo\_valida%')
     and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute'));
  r := r || pg_temp.l(n = 0, format('A4 ninguna funcion interna (S2, S3, F1/F2) es ejecutable por anon, authenticated ni service_role (%s)', n));
  select count(*) into n from public.plantilla_bloque_regla where '' ~* patron is null;
  r := r || pg_temp.l(n = 0, 'A5 todas las reglas de bloques compilan como regex');
  r := r || pg_temp.l(public._plantilla_marcadores() @> array['prom_cargo', 'promotora_razon'], 'A6 prom_cargo y promotora_razon entran en la lista cerrada de S3');
  -- GRANT temporal (solo dentro del rollback)
  foreach f9 in array fn8 loop execute 'grant execute on function public.' || f9 || ' to authenticated'; end loop;

  -- ============================================================ semillas (como postgres, igual que las cargara S4)
  insert into public.plantilla_contrato_versiones (empresa, slug, version, origen, idioma_set, hash, bytes, activable, bloqueo_motivo, autor, motivo)
  select e, s, 1, 'semilla', '{es}', public._plantilla_hash(b), octet_length(b), false, 'Semilla del estudio', 'estudio', 'v1'
    from (values ('sandal_woods', 'carta_reserva', skel), ('lawang', 'carta_reserva', skel), ('sandal_woods', 'cc00014_timon', skel), ('lawang', 'cc00014_timon', skel),
                 ('sandal_woods', 'estatutos_sw', skel), ('sandal_woods', 'adenda', skel_m)) t(e, s, b);
  insert into public.plantilla_contrato_cuerpos select v.id, case v.slug when 'adenda' then skel_m else skel end from public.plantilla_contrato_versiones v where v.origen = 'semilla';

  -- ============================================================ B. F1 texto de otra sociedad
  v := pg_temp.val(ae_S.uid, ae_S.em, format('select public.plantilla_contrato_guarda_borrador(''sandal_woods'', ''carta_reserva'', %L, ''edicion legitima'')', replace(skel, 'Texto libre uno', 'Texto libre DOS')));
  r := r || pg_temp.l(v !~ '^ERR', 'B1 una edicion legitima de Sandal Woods se guarda (' || left(v, 70) || ')');
  select (activable and bloqueo_motivo is null) into ok from public.plantilla_contrato_versiones where empresa = 'sandal_woods' and slug = 'carta_reserva' and estado = 'borrador' and origen = 'empresa';
  r := r || pg_temp.l(ok, 'B2 ... y es activable (la marca vacia de la sociedad propia no casa con todo)');
  v := pg_temp.val(ae_S.uid, ae_S.em, format('select public.plantilla_contrato_guarda_borrador(''sandal_woods'', ''carta_reserva'', %L, ''con razon social ajena'')',
                   replace(skel, 'Texto libre uno', 'Texto libre de ' || razT || ' NPWP ' || npwpT)));
  select (not activable and bloqueo_motivo like '%otra sociedad%' and bloqueo_motivo not like '%' || npwpT || '%' and position(lower(regexp_replace(razT, '^PT ', '', 'i')) in lower(bloqueo_motivo)) = 0) into ok
    from public.plantilla_contrato_versiones where empresa = 'sandal_woods' and slug = 'carta_reserva' and estado = 'borrador' and origen = 'empresa';
  r := r || pg_temp.l(v !~ '^ERR' and ok, 'B3 con razon social y NPWP reales de la otra sociedad se guarda pero NO es activable, y el motivo no repite el dato');
  id1 := (select id from public.plantilla_contrato_versiones where empresa = 'sandal_woods' and slug = 'carta_reserva' and estado = 'borrador' and origen = 'empresa');
  v := pg_temp.val(se_S.uid, se_S.em, format('select public.plantilla_contrato_activa(%L, ''Persona de Prueba'', true)', id1));
  r := r || pg_temp.l(pg_temp.err(v) = '55000' and v like '%otra sociedad%', 'B4 activarla se rechaza (' || left(v, 110) || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, format('select public.plantilla_contrato_guarda_borrador(''sandal_woods'', ''carta_reserva'', %L, ''ancho completo'')',
                   replace(skel, 'Texto libre uno', 'Texto de ' || pg_temp.ancho(regexp_replace(razT, '^PT ', '', 'i')))));
  select (not activable and bloqueo_motivo like '%otra sociedad%') into ok from public.plantilla_contrato_versiones where empresa = 'sandal_woods' and slug = 'carta_reserva' and estado = 'borrador' and origen = 'empresa';
  r := r || pg_temp.l(v !~ '^ERR' and ok, 'B5 la razon social en ANCHO COMPLETO tampoco se activa (' || left(v, 60) || ')');
  r := r || pg_temp.l(cardinality(public._plantilla_otra_sociedad('T&#101;pi Su<i>n</i> G&#x61;i', 'sandal_woods')) > 0 or public._plantilla_norm(razT) <> 'tepisungai',
                      'B6 entidad numerica y etiqueta en medio de la palabra se decodifican antes de buscar');
  r := r || pg_temp.l(cardinality(public._plantilla_otra_sociedad(razS || ' y sus socios', 'sandal_woods')) = 0, 'B7 el nombre de la sociedad PROPIA no cuenta como otra');
  r := r || pg_temp.l(cardinality(public._plantilla_otra_sociedad('{{prom_razon}} <!-- ' || razT || ' --> texto', 'sandal_woods')) = 0, 'B8 un marcador {{}} y un comentario no cuentan como texto de la otra sociedad');
  seg := (regexp_split_to_array(domT, '[,;\n]+'))[1];
  r := r || pg_temp.l(length(public._plantilla_norm(seg)) < 12 or position(public._plantilla_norm(seg) in public._plantilla_norm((select domicilio from public.sociedades where clave = 'san_dal_woods'))) > 0
                      or 'domicilio de tepi_sungai' = any (public._plantilla_otra_sociedad('Oficina en ' || seg, 'sandal_woods')), 'B9 un tramo largo del domicilio de la otra sociedad se detecta');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_guarda_borrador(''lawang'', ''carta_reserva'', %L, ''la propia'')', replace(skel, 'Texto libre uno', 'Texto de ' || razT)));
  select activable into ok from public.plantilla_contrato_versiones where empresa = 'lawang' and slug = 'carta_reserva' and estado = 'borrador' and origen = 'empresa';
  r := r || pg_temp.l(v !~ '^ERR' and ok, 'B10 la razon social de Lawang en un texto de Lawang SI es activable');
  v := pg_temp.val(ae_S.uid, ae_S.em, format('select public.plantilla_contrato_guarda_borrador(''sandal_woods'', ''cc00014_timon'', %L, ''un solo ejemplar'')', replace(skel, 'Texto libre uno', 'Texto libre DOS')));
  select (not activable and bloqueo_motivo like '%un solo ejemplar%') into ok from public.plantilla_contrato_versiones where empresa = 'sandal_woods' and slug = 'cc00014_timon' and estado = 'borrador' and origen = 'empresa';
  r := r || pg_temp.l(v !~ '^ERR' and ok, 'B11 cc00014_timon de Sandal Woods: nunca activable');
  id1 := (select id from public.plantilla_contrato_versiones where empresa = 'sandal_woods' and slug = 'cc00014_timon' and estado = 'borrador' and origen = 'empresa');
  v := pg_temp.val(se_S.uid, se_S.em, format('select public.plantilla_contrato_activa(%L, ''Persona de Prueba'', true)', id1));
  r := r || pg_temp.l(pg_temp.err(v) = '55000', 'B12 ... y activarla se rechaza (' || left(v, 70) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_guarda_borrador(''lawang'', ''cc00014_timon'', %L, ''de Lawang'')', replace(skel, 'Texto libre uno', 'Texto libre DOS')));
  select activable into ok from public.plantilla_contrato_versiones where empresa = 'lawang' and slug = 'cc00014_timon' and estado = 'borrador' and origen = 'empresa';
  r := r || pg_temp.l(v !~ '^ERR' and ok, 'B13 el mismo slug para Lawang no esta bloqueado por esa lista');
  -- activar una legitima: pasa por S3 y por la re-comprobacion de servidor
  v := pg_temp.val(ae_S.uid, ae_S.em, format('select public.plantilla_contrato_guarda_borrador(''sandal_woods'', ''carta_reserva'', %L, ''de nuevo legitima'')', replace(skel, 'Texto libre uno', 'Texto libre TRES con {{prom_cargo}}')));
  id1 := v::uuid;
  v := pg_temp.val(se_S.uid, se_S.em, format('select public.plantilla_contrato_activa(%L, ''Persona de Prueba'', true)', id1));
  r := r || pg_temp.l(v !~ '^ERR', 'B14 una edicion legitima (con {{prom_cargo}}) se activa (' || left(v, 70) || ')');
  -- estatutos_sw: solo global y exige promotora_razon
  v := pg_temp.val(ae_S.uid, ae_S.em, format('select public.plantilla_contrato_guarda_borrador(''sandal_woods'', ''estatutos_sw'', %L, ''igual'')', skel));
  select (not activable and bloqueo_motivo like '%promotora_razon%') into ok from public.plantilla_contrato_versiones where empresa = 'sandal_woods' and slug = 'estatutos_sw' and estado = 'borrador' and origen = 'empresa';
  r := r || pg_temp.l(v !~ '^ERR' and ok, 'B15 estatutos_sw no es activable mientras promotora_razon este vacio');
  insert into public.plantilla_ficha values ('sandal_woods', 'promotora_razon', 'Valor de prueba');
  v := pg_temp.val(ae_S.uid, ae_S.em, format('select public.plantilla_contrato_guarda_borrador(''sandal_woods'', ''estatutos_sw'', %L, ''igual otra vez'')', skel));
  select activable into ok from public.plantilla_contrato_versiones where empresa = 'sandal_woods' and slug = 'estatutos_sw' and estado = 'borrador' and origen = 'empresa';
  r := r || pg_temp.l(v !~ '^ERR' and ok, 'B16 ... y con la ficha rellena si lo es');

  -- ============================================================ C. F2 bloques fijos
  v := pg_temp.val(ae_S.uid, ae_S.em, format('select public.plantilla_contrato_guarda_borrador(''sandal_woods'', ''carta_reserva'', %L, ''cambio el foro'')', replace(skel, 'arbitraje SIAC en Singapur', 'arbitraje BANI en Denpasar')));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'C1 el admin de empresa NO cambia un parrafo de foro/arbitraje (' || left(v, 90) || ')');
  v := pg_temp.val(se_S.uid, se_S.em, format('select public.plantilla_contrato_guarda_borrador(''sandal_woods'', ''carta_reserva'', %L, ''cambio el foro'')', replace(skel, 'arbitraje SIAC en Singapur', 'arbitraje BANI en Denpasar')));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'C2 ni el super de la empresa (' || left(v, 60) || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, format('select public.plantilla_contrato_guarda_borrador(''sandal_woods'', ''carta_reserva'', %L, ''toco un libre dentro de la seccion de ley'')', replace(skel, 'Texto final libre', 'Texto final distinto')));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'C3 ni un parrafo libre dentro de la seccion «Ley aplicable» (' || left(v, 60) || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, format('select public.plantilla_contrato_guarda_borrador(''sandal_woods'', ''carta_reserva'', %L, ''toco las partes'')', replace(skel, 'con NPWP', 'con el NPWP')));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'C4 ni la identidad de las partes (' || left(v, 60) || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, format('select public.plantilla_contrato_guarda_borrador(''sandal_woods'', ''carta_reserva'', %L, ''anado arbitraje a un libre'')', replace(skel, 'Texto libre uno', 'Texto libre sobre arbitraje')));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'C5 tampoco se anade a un parrafo libre una palabra de esos temas (' || left(v, 60) || ')');
  v := pg_temp.val(jv.uid, jv.em, format('select public.plantilla_contrato_guarda_borrador(''sandal_woods'', ''carta_reserva'', %L, ''el global cambia el foro'')', replace(skel, 'arbitraje SIAC en Singapur', 'arbitraje BANI en Denpasar')));
  r := r || pg_temp.l(v !~ '^ERR', 'C6 el super GLOBAL si cambia el foro (' || left(v, 60) || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, format('select public.plantilla_contrato_guarda_borrador(''sandal_woods'', ''estatutos_sw'', %L, ''cambio estatutos'')', replace(skel, 'Texto libre uno', 'Otro')));
  r := r || pg_temp.l(pg_temp.err(v) = '42501' and v like '%no lo cambia una empresa sola%', 'C7 estatutos_sw (solo global) no cambia ni una palabra por una empresa (' || left(v, 70) || ')');
  v := pg_temp.val(jv.uid, jv.em, format('select public.plantilla_contrato_guarda_borrador(''sandal_woods'', ''estatutos_sw'', %L, ''el global cambia'')', replace(skel, 'Texto libre uno', 'Otro')));
  r := r || pg_temp.l(v !~ '^ERR', 'C8 ... el global si (' || left(v, 60) || ')');
  -- marcas bloque-fijo
  v := pg_temp.val(ae_S.uid, ae_S.em, format('select public.plantilla_contrato_guarda_borrador(''sandal_woods'', ''adenda'', %L, ''edito libres'')', replace(replace(skel_m, 'Libre A', 'Libre AA'), 'Libre B', 'Libre BB')));
  r := r || pg_temp.l(v !~ '^ERR', 'C9 con <!--bloque-fijo:tenencia--> se editan los parrafos libres de alrededor (' || left(v, 90) || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, format('select public.plantilla_contrato_guarda_borrador(''sandal_woods'', ''adenda'', %L, ''edito el fijo'')', replace(skel_m, 'Estructura fija X', 'Estructura fija Y')));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'C10 ... y el contenido de la region marcada no se edita (' || left(v, 70) || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, format('select public.plantilla_contrato_guarda_borrador(''sandal_woods'', ''adenda'', %L, ''quito la marca'')', replace(replace(skel_m, '<!--bloque-fijo:tenencia-->', ''), '<!--/bloque-fijo:tenencia-->', '')));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'C11 quitar la marca es cambiar el esqueleto: lo rechaza S3 (' || left(v, 70) || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, format('select public.plantilla_contrato_guarda_borrador(''sandal_woods'', ''adenda'', %L, ''marca inventada'')', replace(skel_m, 'tenencia', 'inventada')));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'C12 un nombre de bloque fuera de la lista cerrada se rechaza (' || left(v, 70) || ')');
  -- rendimiento sobre un cuerpo grande
  t0 := clock_timestamp();
  n := cardinality(public._plantilla_bloques_fijos(repeat(skel, 120), 'carta_reserva'));
  ms := extract(epoch from clock_timestamp() - t0) * 1000;
  r := r || pg_temp.l(ms < 3000, format('C13 bloques fijos de un cuerpo de %s KB en %s ms (%s bloques)', octet_length(repeat(skel, 120)) / 1000, round(ms), n));

  raise exception 'INFORME' using errcode = 'LWS05', detail = r;
  exception when sqlstate 'LWS05' then
    get stacked diagnostics u = pg_exception_detail;
    insert into _t5out values (u);
  end;
end $todo$;

do $fin$
declare t text; fl int;
begin
  select txt into t from _t5out;
  fl := (length(t) - length(replace(t, 'FALLO', ''))) / 5;
  raise exception E'\n%FALLOS=%', t, fl;
end $fin$;
