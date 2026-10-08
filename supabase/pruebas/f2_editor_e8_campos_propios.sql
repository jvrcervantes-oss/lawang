-- Prueba de E8 «editor de textos de contrato · campos propios por empresa» (10-oct-2026). Se pega DESPUES de la migracion 20261010010000 en la MISMA peticion
-- (ensayo sin rastro: el bloque acaba en raise y todo se deshace, migracion incluida si se pega junta). Personas por JWT simulado, como f2_editor_e7_variantes.sql.
-- NO inserta contratos: usa el unico contrato libre de commercial_offer de Lawang y su dato vuelve a su sitio al deshacer. NO activa nada en produccion.
-- Incluye la prueba NEGATIVA: <img onerror=x>, "><script>, {{otro}}, cx_ de otra empresa, cambiar el tipo de un campo usado, borrar un campo usado, aislamiento Lawang / Sandal Woods.
-- Debe terminar con «FALLOS=0».
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); los campos, borradores y valores de prueba se deshacen
create temp table _t8 (et text primary key, uid uuid, em text);
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
create or replace function pg_temp.pg(p_sql text) returns text language plpgsql as $f$
declare t text;
begin
  begin execute p_sql into t; exception when others then t := 'ERR' || sqlstate || ':' || left(sqlerrm, 200); end;
  return t;
end $f$;
create or replace function pg_temp.run(p_sql text) returns text language plpgsql as $f$
begin
  begin execute p_sql; exception when others then return 'ERR' || sqlstate || ':' || left(sqlerrm, 200); end;
  return 'OK';
end $f$;

insert into _t8 select 'jv', user_id, email from public.usuarios where email = 'jvr.cervantes@gmail.com';
insert into _t8
  select (array['ae_L', 'se_L', 'ae_S', 'se_S', 'ctl_L', 'adm_G'])[rn], user_id, email
    from (select user_id, email, row_number() over (order by email) rn
            from (select user_id, email from public.usuarios where activo and ambito = 'global' and rol = 'agente' order by email limit 6) q) z;

do $todo$
declare
  r text := ''; v text; n bigint; fallos int; j jsonb;
  jv _t8; ae_L _t8; se_L _t8; ae_S _t8; ctl_L _t8; adm_G _t8;
  ct uuid; body text; bcx text; cx_antes bigint; vid uuid; i int; largo text;
  nuevas text[] := array['plantilla_campo_propio_guarda(text,text,text,text,text,text,jsonb,boolean,boolean)', 'plantilla_campo_propio_archiva(text,text,boolean)',
                         'plantilla_campo_propio_borra(text,text)', 'plantilla_campo_propio_lista(text,boolean)', 'plantilla_campo_propio_valida(text,jsonb)',
                         'plantilla_campos_cx_publicos(text,uuid)'];
  cerradas text[] := array['_cx_opciones_ok(jsonb)', '_cx_valor(text,jsonb,jsonb)', '_cx_en_uso(text,text)', '_cx_autoriza(text,boolean)', '_plantilla_cx_contexto(text,boolean)',
                           '_trg_cx_campo_ins()', '_trg_cx_campo_upd()', '_trg_cx_campo_del()', '_trg_contrato_campos_propios()', '_plantilla_exige_valido(text,text,text)'];
  f text;
begin
  select * into jv from _t8 where et = 'jv'; select * into ae_L from _t8 where et = 'ae_L'; select * into se_L from _t8 where et = 'se_L'; select * into ae_S from _t8 where et = 'ae_S';
  select * into ctl_L from _t8 where et = 'ctl_L'; select * into adm_G from _t8 where et = 'adm_G';
  perform set_config('request.jwt.claims', json_build_object('sub', jv.uid, 'role', 'authenticated', 'email', jv.em)::text, true);
  update public.usuarios set rol = 'admin_empresa', ambito = 'empresa', empresas = '{lawang}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{}', tipos_contrato = '{}' where user_id = ae_L.uid;
  update public.usuarios set rol = 'super_admin_empresa', ambito = 'empresa', empresas = '{lawang}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{}', tipos_contrato = '{}' where user_id = se_L.uid;
  update public.usuarios set rol = 'admin_empresa', ambito = 'empresa', empresas = '{sandal_woods}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{}', tipos_contrato = '{}' where user_id = ae_S.uid;
  update public.usuarios set rol = 'agente', ambito = 'global', empresas = '{lawang}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{}', tipos_contrato = '{}' where user_id = ctl_L.uid;
  update public.usuarios set rol = 'admin', ambito = 'global', empresas = '{}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{}', tipos_contrato = '{}' where user_id = adm_G.uid;
  select c.id into ct from public.contratos c join public.proyectos pr on pr.id = c.proyecto_id
   where pr.empresa = 'lawang' and public._plantilla_slug_de_tipo(c.tipo) = 'commercial_offer' and not coalesce(c.bloqueado, false)
     and not exists (select 1 from public.contrato_firmas f where f.contrato_id = c.id) limit 1;
  select count(*) into cx_antes from public.contratos where datos_fields::text like '%"cx\_%';
  r := r || pg_temp.l(ct is not null, 'Z0 hay un contrato libre de commercial_offer en Lawang para probar el guardado de valores');
  r := r || pg_temp.l(cx_antes = 0, 'Z1 ningun contrato de hoy guarda una clave cx_ (' || cx_antes || '): la migracion no puede romper uno existente');

  -- ============================================================ A. estructura y exposicion
  select count(*) into n from pg_class where relname = 'plantilla_campos_propios' and relrowsecurity
     and not (has_table_privilege('authenticated', oid, 'select') or has_table_privilege('authenticated', oid, 'insert') or has_table_privilege('authenticated', oid, 'update')
              or has_table_privilege('authenticated', oid, 'delete') or has_table_privilege('anon', oid, 'select') or has_table_privilege('service_role', oid, 'select'));
  r := r || pg_temp.l(n = 1, 'A1 el catalogo tiene RLS y ningun GRANT directo (ni authenticated, ni anon, ni service_role)');
  select count(*) into n from unnest(nuevas) x where has_function_privilege('authenticated', 'public.' || x, 'execute');
  r := r || pg_temp.l(n = 6, 'A2 authenticated ejecuta las 6 RPC nuevas (' || n || ')');
  select count(*) into n from unnest(nuevas) x where has_function_privilege('anon', 'public.' || x, 'execute') or has_function_privilege('service_role', 'public.' || x, 'execute');
  r := r || pg_temp.l(n = 0, 'A3 anon y service_role no ejecutan ninguna (' || n || ')');
  select count(*) into n from unnest(cerradas) x where has_function_privilege('authenticated', 'public.' || x, 'execute') or has_function_privilege('anon', 'public.' || x, 'execute')
                                                      or has_function_privilege('service_role', 'public.' || x, 'execute');
  r := r || pg_temp.l(n = 0, 'A4 ninguno de los 10 ayudantes internos tiene EXECUTE fuera (' || n || ')');
  select count(*) into n from pg_proc where pronamespace = 'public'::regnamespace and (proname like 'plantilla_campo_propio%' or proname = 'plantilla_campos_cx_publicos')
     and prosecdef and proconfig @> array['search_path=""'];
  r := r || pg_temp.l(n = 6, 'A5 las 6 RPC son SECURITY DEFINER con search_path vacio (' || n || ' de 6)');
  select count(*) into n from pg_proc where pronamespace = 'public'::regnamespace
     and proname in ('_plantilla_texto', '_plantilla_analiza', '_plantilla_valida', 'plantilla_cuerpo_valida', 'plantilla_cuerpo_valida_semilla') and provolatile = 's';
  r := r || pg_temp.l(n = 5, 'A6 las 5 funciones del validador pasaron de immutable a stable porque leen el catalogo de la transaccion (' || n || ' de 5)');
  select count(*) into n from pg_trigger where tgrelid = 'public.contratos'::regclass and tgname = 'trg_contrato_campos_propios' and not tgisinternal;
  r := r || pg_temp.l(n = 1, 'A7 el trigger de valores esta en contratos');
  r := r || pg_temp.l(pg_get_triggerdef((select oid from pg_trigger where tgname = 'trg_contrato_campos_propios')) like '%BEFORE INSERT OR UPDATE OF datos%',
                      'A8 el trigger de valores solo se dispara si el guardado toca la columna datos');

  -- ============================================================ B. catalogo: altas, permisos y errores
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_guarda(''lawang'', ''cx_nota'', ''Nota interna'', ''Internal note'', ''Catatan'', ''texto'', null, false)');
  r := r || pg_temp.l(v not like 'ERR%' and (v::jsonb ->> 'nuevo')::boolean, 'B1 el admin de la empresa da de alta un campo propio de texto (' || left(v, 60) || ')');
  r := r || pg_temp.l((select sensible from public.plantilla_campos_propios where empresa = 'lawang' and clave = 'cx_nota'), 'B2 un campo nuevo nace SENSIBLE por defecto (el bot y la IA no lo ven)');
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_guarda(''lawang'', ''cx_plazo_extra'', ''Plazo extra'', null, null, ''numero'', null, true)')) is null, 'B3 campo numero');
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_guarda(''lawang'', ''cx_fecha_hito'', ''Fecha del hito'', null, null, ''fecha'', null, false)')) is null, 'B4 campo fecha');
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_guarda(''lawang'', ''cx_monto'', ''Monto'', null, null, ''importe'', null, false, false)')) is null, 'B5 campo importe, no sensible');
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_guarda(''lawang'', ''cx_zona'', ''Zona'', null, null, ''lista'', ''["norte","sur"]''::jsonb, false, false)')) is null, 'B6 campo lista, no sensible');
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_guarda(''lawang'', ''cx_acepta'', ''Acepta'', null, null, ''si_no'', null, false)')) is null, 'B7 campo si/no');
  v := pg_temp.val(ae_S.uid, ae_S.em, 'select public.plantilla_campo_propio_guarda(''sandal_woods'', ''cx_solo_sw'', ''Solo SW'', null, null, ''texto'', null, false, false)');
  r := r || pg_temp.l(v not like 'ERR%', 'B8 el admin de Sandal Woods da de alta el suyo (' || left(v, 40) || ')');
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ae_S.uid, ae_S.em, 'select public.plantilla_campo_propio_guarda(''lawang'', ''cx_intruso'', ''X'', null, null, ''texto'', null, false)')) = '42501', 'B9 el admin de otra empresa NO escribe en el catalogo de Lawang');
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ctl_L.uid, ctl_L.em, 'select public.plantilla_campo_propio_guarda(''lawang'', ''cx_intruso'', ''X'', null, null, ''texto'', null, false)')) = '42501', 'B10 un agente que no es admin NO escribe');
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(null, null, 'select public.plantilla_campo_propio_lista(''lawang'')', 'anon')) is not null, 'B11 anon no lee el catalogo');
  for f in select unnest(array['CX_Mayus', 'nota', 'cx_', 'cx_con-guion', 'cx_' || repeat('a', 41), 'cx_ñ']) loop
    r := r || pg_temp.l(pg_temp.err(pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_campo_propio_guarda(''lawang'', %L, ''X'', null, null, ''texto'', null, false)', f))) = '22023', 'B12 clave no valida rechazada: ' || left(f, 20));
  end loop;
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_guarda(''lawang'', ''cx_malo'', ''X'', null, null, ''blob'', null, false)')) = '22023', 'B13 tipo fuera del conjunto cerrado rechazado');
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_guarda(''lawang'', ''cx_malo'', ''X'', null, null, ''lista'', null, false)')) = '22023', 'B14 una lista sin opciones se rechaza');
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_guarda(''lawang'', ''cx_malo'', ''X'', null, null, ''texto'', ''["a"]''::jsonb, false)')) = '22023', 'B15 solo una lista lleva opciones');
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_guarda(''lawang'', ''cx_malo'', ''X'', null, null, ''lista'', ''["<b>"]''::jsonb, false)')) = '22023', 'B16 una opcion con < > se rechaza');
  r := r || pg_temp.l(pg_temp.pg('insert into public.plantilla_campos_propios (empresa, clave, etiqueta_es, tipo, autor) values (''lawang'', ''cx_e'', ''<script>'', ''texto'', ''x'')') like 'ERR23514%', 'B17 una etiqueta con < > no entra ni por la puerta de atras (CHECK)');
  r := r || pg_temp.l(pg_temp.pg('insert into public.plantilla_campos_propios (empresa, clave, etiqueta_es, tipo, autor) values (''lawang'', ''precio_total'', ''x'', ''texto'', ''x'')') ~ '^ERR(23514|22023)', 'B18 la clave tiene que empezar por cx_: no hay forma de pisar una del sistema');
  r := r || pg_temp.l(pg_temp.pg('insert into public.plantilla_campos_propios (empresa, clave, etiqueta_es, tipo, autor) values (''no_existe'', ''cx_x'', ''x'', ''texto'', ''x'')') like 'ERR23503%', 'B19 la empresa tiene que existir');

  -- ============================================================ C. lista y aislamiento entre empresas
  v := pg_temp.val(ctl_L.uid, ctl_L.em, 'select jsonb_array_length(public.plantilla_campo_propio_lista(''lawang''))::text');
  r := r || pg_temp.l(v = '6', 'C1 un agente de Lawang ve los 6 campos de Lawang (' || v || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select (select count(*) from jsonb_array_elements(public.plantilla_campo_propio_lista(''lawang'')) e where e->>''clave'' = ''cx_solo_sw'')::text');
  r := r || pg_temp.l(v = '0', 'C2 el catalogo de Lawang no contiene el campo de Sandal Woods (' || v || ')');
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_lista(''sandal_woods'')')) = '42501', 'C3 Lawang no lee el catalogo de Sandal Woods');
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ae_S.uid, ae_S.em, 'select public.plantilla_campo_propio_lista(''lawang'')')) = '42501', 'C4 Sandal Woods no lee el de Lawang');
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ae_S.uid, ae_S.em, 'select public.plantilla_campo_propio_valida(''lawang'', ''{"cx_nota":"hola"}''::jsonb)')) = '42501', 'C5 Sandal Woods no valida valores contra el catalogo de Lawang');
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ctl_L.uid, ctl_L.em, 'select public.plantilla_campo_propio_lista(''lawang'', true)')) = '42501', 'C6 el uso de cada campo solo lo ve la administracion');

  -- ============================================================ D. VALIDADOR DE MARCADORES (la pieza que decide si un texto entra)
  body := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_edicion(''lawang'', ''commercial_offer'')->>''cuerpo_html''');
  r := r || pg_temp.l(body not like 'ERR%' and position('acabados de alta calidad' in body) > 0, 'D0 hay un texto de partida con la frase que se va a tocar');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_revisa(''lawang'', ''commercial_offer'', %L)->>''ok''', body));
  r := r || pg_temp.l(v = 'true', 'D1 el texto de partida sin tocar pasa el ensayo (' || left(v, 60) || ')');
  bcx := replace(body, 'acabados de alta calidad', 'acabados de alta calidad ({{cx_nota}})');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_revisa(''lawang'', ''commercial_offer'', %L)->>''ok''', bcx));
  r := r || pg_temp.l(v = 'true', 'D2 {{cx_nota}} del catalogo de Lawang pasa el ensayo (' || left(v, 60) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_revisa(''lawang'', ''commercial_offer'', %L)->>''ok''', replace(body, 'acabados de alta calidad', 'acabados {{cx_no_existe}}')));
  r := r || pg_temp.l(v = 'false', 'D3 un cx_ que no esta en el catalogo se rechaza (' || v || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_revisa(''lawang'', ''commercial_offer'', %L)->>''ok''', replace(body, 'acabados de alta calidad', 'acabados {{cx_solo_sw}}')));
  r := r || pg_temp.l(v = 'false', 'D4 un cx_ del catalogo de OTRA empresa (Sandal Woods) se rechaza en el texto de Lawang (' || v || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_revisa(''lawang'', ''commercial_offer'', %L)#>>''{errores,0}''', replace(body, 'acabados de alta calidad', 'acabados {{cx_solo_sw}}')));
  r := r || pg_temp.l(v like '%cx_solo_sw%catalogo%', 'D5 el mensaje dice que el campo no esta en el catalogo de la empresa (' || left(v, 90) || ')');
  for f in select unnest(array['{{cx_}}', '{{CX_nota}}', '{{cx_nota }}', '{{{cx_nota}}}', '{{cx_' || repeat('a', 41) || '}}', '{{cx-nota}}', '{{ cx_nota }}']) loop
    v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_revisa(''lawang'', ''commercial_offer'', %L)->>''ok''', replace(body, 'acabados de alta calidad', 'acabados ' || f)));
    r := r || pg_temp.l(v = 'false', 'D6 forma no permitida rechazada: ' || left(f, 24));
  end loop;
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_revisa(''lawang'', ''commercial_offer'', %L)->>''ok''', replace(body, 'acabados de alta calidad', 'acabados <!--if:cx_nota=si-->x<!--/if:cx_nota-->')));
  r := r || pg_temp.l(v = 'false', 'D7 un cx_ NO entra en un <!--if:--> (el motor de condiciones sigue cerrado)');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_revisa(''lawang'', ''commercial_offer'', %L)->>''ok''', replace(body, 'acabados de alta calidad', 'acabados <span data-campo="cx_nota">x</span>')));
  r := r || pg_temp.l(v = 'false', 'D8 un cx_ NO entra en un atributo data-campo');
  v := pg_temp.pg(format('select public.plantilla_cuerpo_valida(%L, public._plantilla_esqueleto(''lawang'', ''commercial_offer''))->>''ok''', bcx));
  r := r || pg_temp.l(v = 'false', 'D9 sin empresa en el contexto (llamada directa al validador) todo cx_ se rechaza: lo nuevo nace cerrado (' || v || ')');
  v := pg_temp.pg(format('select public.plantilla_cuerpo_valida_semilla(%L)->>''ok''', '<p>{{cx_nota}}</p>'));
  r := r || pg_temp.l(v = 'false', 'D10 el modo semilla tampoco acepta cx_ (' || v || ')');
  v := coalesce(current_setting('lw.cx_catalogo', true), '');
  r := r || pg_temp.l(v = '', 'D11 el ajuste local del catalogo queda vacio al acabar cada validacion (' || left(v, 40) || ')');
  v := coalesce(current_setting('lw.cx_abierto', true), '');
  r := r || pg_temp.l(v = '', 'D12 el modo abierto del esqueleto tambien queda apagado (' || left(v, 40) || ')');
  -- guardar de verdad (el camino que decide): entra el de Lawang, no entra el de otra empresa ni el inexistente
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_guarda_borrador(''lawang'', ''commercial_offer'', %L, ''E8 prueba'')', bcx));
  vid := case when v like 'ERR%' then null else v::uuid end;
  r := r || pg_temp.l(vid is not null, 'D13 el borrador con {{cx_nota}} se GUARDA (' || left(v, 70) || ')');
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_guarda_borrador(''lawang'', ''commercial_offer'', %L, ''E8 ajeno'')', replace(body, 'acabados de alta calidad', 'acabados {{cx_solo_sw}}')))) = '22023',
                      'D14 guardar con el cx_ de otra empresa falla con 22023');
  v := pg_temp.pg(format('select (select 1 from public.plantilla_contrato_cuerpos where version_id = %L and position(''{{cx_nota}}'' in cuerpo_html) > 0)::text', vid));
  r := r || pg_temp.l(v = '1', 'D15 el cuerpo guardado conserva el marcador tal cual');

  -- ============================================================ E. inmutabilidad: tipo, clave, borrado y archivo de un campo EN USO
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_guarda(''lawang'', ''cx_nota'', ''Nota interna'', null, null, ''numero'', null, false)');
  r := r || pg_temp.l(pg_temp.err(v) = '55000', 'E1 cambiar el TIPO de un campo que usa una version se niega (' || left(v, 90) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_borra(''lawang'', ''cx_nota'')');
  r := r || pg_temp.l(pg_temp.err(v) = '55000', 'E2 BORRAR un campo que referencia una version se niega (' || left(v, 90) || ')');
  v := pg_temp.pg('update public.plantilla_campos_propios set clave = ''cx_otra'' where empresa = ''lawang'' and clave = ''cx_nota''');
  r := r || pg_temp.l(pg_temp.err(v) = '55000', 'E3 la clave no cambia nunca, ni por la puerta de atras (' || left(v, 60) || ')');
  v := pg_temp.pg('update public.plantilla_campos_propios set empresa = ''sandal_woods'' where empresa = ''lawang'' and clave = ''cx_nota''');
  r := r || pg_temp.l(pg_temp.err(v) = '55000', 'E4 el campo no se cambia de empresa (' || left(v, 60) || ')');
  v := pg_temp.pg('delete from public.plantilla_campos_propios where empresa = ''lawang'' and clave = ''cx_nota''');
  r := r || pg_temp.l(pg_temp.err(v) = '55000', 'E5 el trigger niega el borrado aunque no pase por la RPC (' || left(v, 60) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select (select (e->''uso''->>''versiones'')::int from jsonb_array_elements(public.plantilla_campo_propio_lista(''lawang'', true)) e where e->>''clave'' = ''cx_nota'')::text');
  r := r || pg_temp.l(v::int >= 1, 'E6 la lista con uso cuenta la version que lo referencia (' || v || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_guarda(''lawang'', ''cx_nota'', ''Nota (renombrada)'', ''Note'', ''Catatan'', ''texto'', null, true, true)');
  r := r || pg_temp.l(v not like 'ERR%', 'E7 lo que NO es identidad (etiquetas, obligatorio) si se edita en un campo usado (' || left(v, 60) || ')');
  -- sin uso: el tipo si cambia y el campo se borra
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_guarda(''lawang'', ''cx_acepta'', ''Acepta'', null, null, ''texto'', null, false)');
  r := r || pg_temp.l(v not like 'ERR%', 'E8 un campo sin uso SI puede cambiar de tipo (' || left(v, 60) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_borra(''lawang'', ''cx_acepta'')');
  r := r || pg_temp.l(v is null or v not like 'ERR%', 'E9 un campo sin uso SI se borra (' || coalesce(left(v, 60), 'ok') || ')');
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_borra(''lawang'', ''cx_acepta'')')) = '22023', 'E10 borrarlo otra vez dice que no existe');
  -- cx_zona: las opciones, si esta en uso, solo crecen. Primero se usa en un contrato (F), luego se comprueba en F9.

  -- ============================================================ F. VALORES: la RPC de validacion (misma verdad que el trigger)
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_valida(''lawang'', ''{"cx_nota":"<img onerror=x>"}''::jsonb)->>''ok''');
  r := r || pg_temp.l(v = 'false', 'F1 NEGATIVA: <img onerror=x> en un texto se rechaza (' || v || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_valida(''lawang'', jsonb_build_object(''cx_nota'', ''"><script>alert(1)</script>''))->>''ok''');
  r := r || pg_temp.l(v = 'false', 'F2 NEGATIVA: "><script> se rechaza (' || v || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_valida(''lawang'', ''{"cx_nota":"{{adq1_nombre}}"}''::jsonb)->>''ok''');
  r := r || pg_temp.l(v = 'false', 'F3 NEGATIVA: {{otro}} dentro de un valor se rechaza (no se podra re-expandir) (' || v || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_valida(''lawang'', jsonb_build_object(''cx_nota'', ''Pedro & Hijos, S.L. y "especial"''))->>''ok''');
  r := r || pg_temp.l(v = 'true', 'F4 un texto normal con & y comillas SI entra (se escapa al pintarlo) (' || v || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_valida(''lawang'', jsonb_build_object(''cx_nota'', ''a'' || chr(8238) || ''b'' || chr(8203) || ''c'' || chr(1) || ''d''))->''valores''->>''cx_nota''');
  r := r || pg_temp.l(v = 'abcd', 'F5 bidi, ancho cero y control se ELIMINAN del valor (queda «' || coalesce(v, '?') || '»)');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_campo_propio_valida(''lawang'', jsonb_build_object(''cx_nota'', %L))->>''ok''', repeat('x', 201)));
  r := r || pg_temp.l(v = 'false', 'F6 mas de 200 caracteres se rechaza');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_campo_propio_valida(''lawang'', jsonb_build_object(''cx_nota'', %L))->>''ok''', repeat('x', 200)));
  r := r || pg_temp.l(v = 'true', 'F7 exactamente 200 caracteres entra');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_valida(''lawang'', ''{"cx_plazo_extra":"120.000"}''::jsonb)->''valores''->>''cx_plazo_extra''');
  r := r || pg_temp.l(v = '120000', 'F8 numero «120.000» se guarda canonico «120000» (parser unico lw_importe; ::numeric daria 120) (' || v || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_valida(''lawang'', ''{"cx_plazo_extra":"1,5"}''::jsonb)->''valores''->>''cx_plazo_extra''');
  r := r || pg_temp.l(v = '1.5', 'F9 numero «1,5» -> «1.5» (' || v || ')');
  for f in select unnest(array['abc', '12abc', '--3', '1e5', '', ' ']) loop
    v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_campo_propio_valida(''lawang'', jsonb_build_object(''cx_plazo_extra'', %L))->''valores''->>''cx_plazo_extra''', f));
    r := r || pg_temp.l((f in ('', ' ') and v = '') or (f not in ('', ' ') and v is null), 'F10 numero no numerico «' || f || '»: ' || case when f in ('', ' ') then 'vacio vale vacio' else 'se rechaza' end || ' (' || coalesce(v, 'rechazado') || ')');
  end loop;
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_valida(''lawang'', ''{"cx_monto":"12.50"}''::jsonb)->''valores''->>''cx_monto''');
  r := r || pg_temp.l(v = '12.5', 'F11 importe 12.50 canonico (' || v || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_valida(''lawang'', ''{"cx_monto":"-3"}''::jsonb)->>''ok''');
  r := r || pg_temp.l(v = 'false', 'F12 un importe negativo se rechaza');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_valida(''lawang'', ''{"cx_monto":"1,2345"}''::jsonb)->>''ok''');
  r := r || pg_temp.l(v = 'false', 'F13 un importe con 3 decimales se rechaza');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_valida(''lawang'', ''{"cx_fecha_hito":"2026-02-30"}''::jsonb)->>''ok''');
  r := r || pg_temp.l(v = 'false', 'F14 la fecha 2026-02-30 no existe y se rechaza');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_valida(''lawang'', ''{"cx_fecha_hito":"09/10/2026"}''::jsonb)->>''ok''');
  r := r || pg_temp.l(v = 'false', 'F15 fecha que no es ISO se rechaza');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_valida(''lawang'', ''{"cx_fecha_hito":"2026-10-09"}''::jsonb)->>''ok''');
  r := r || pg_temp.l(v = 'true', 'F16 fecha ISO real entra');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_valida(''lawang'', ''{"cx_fecha_hito":"1500-01-01"}''::jsonb)->>''ok''');
  r := r || pg_temp.l(v = 'false', 'F17 fecha fuera de 1900-2200 se rechaza');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_valida(''lawang'', ''{"cx_zona":"norte"}''::jsonb)->>''ok''');
  r := r || pg_temp.l(v = 'true', 'F18 valor dentro de las opciones de la lista entra');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_valida(''lawang'', ''{"cx_zona":"oeste"}''::jsonb)->>''ok''');
  r := r || pg_temp.l(v = 'false', 'F19 valor fuera de las opciones se rechaza');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_valida(''lawang'', ''{"cx_solo_sw":"hola"}''::jsonb)->''errores''->>''cx_solo_sw''');
  r := r || pg_temp.l(v like '%catalogo%', 'F20 la clave de OTRA empresa no esta en el catalogo de Lawang (' || left(v, 60) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_valida(''lawang'', ''{"precio_total":"1"}''::jsonb)->>''ok''');
  r := r || pg_temp.l(v = 'false', 'F21 una clave del sistema (precio_total) no se cuela por esta puerta');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_valida(''lawang'', ''{"cx_nota":{"a":1}}''::jsonb)->>''ok''');
  r := r || pg_temp.l(v = 'false', 'F22 un objeto como valor se rechaza');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_valida(''lawang'', ''{"cx_nota":""}''::jsonb)->''vacios_obligatorios''->>0');
  r := r || pg_temp.l(v = 'cx_nota', 'F23 un obligatorio vacio se avisa en vacios_obligatorios (cx_nota ahora es obligatorio) (' || coalesce(v, '-') || ')');

  -- ============================================================ G. EL TRIGGER DE CONTRATOS: el servidor decide, no la pantalla
  perform set_config('request.jwt.claims', json_build_object('sub', jv.uid, 'role', 'authenticated', 'email', jv.em)::text, true);   -- pg_temp.val deja los claims del ultimo; los triggers de rol de contratos los leen
  v := pg_temp.run(format('update public.contratos set datos = jsonb_set(datos, ''{fields}'', coalesce(datos->''fields'', ''{}''::jsonb) || jsonb_build_object(''cx_nota'', %L::text)) where id = %L', 'hola', ct));
  r := r || pg_temp.l(v = 'OK', 'G1 un valor valido de un campo del catalogo se guarda en el contrato (' || v || ')');
  v := pg_temp.pg(format('select datos->''fields''->>''cx_nota'' || ''|'' || (datos_fields->>''cx_nota'') from public.contratos where id = %L', ct));
  r := r || pg_temp.l(v = 'hola|hola', 'G2 el valor queda en datos.fields y en su copia datos_fields (' || v || ')');
  for f in select unnest(array['<img src=x onerror=x>', '"><script>alert(1)</script>', '{{adq1_nombre}}', '<b>x</b>']) loop
    v := pg_temp.run(format('update public.contratos set datos = jsonb_set(datos, ''{fields,cx_nota}'', to_jsonb(%L::text)) where id = %L', f, ct));
    r := r || pg_temp.l(pg_temp.err(v) = '22023', 'G3 NEGATIVA en el servidor: «' || left(f, 28) || '» no se guarda en el contrato (' || left(v, 70) || ')');
  end loop;
  v := pg_temp.pg(format('select datos->''fields''->>''cx_nota'' from public.contratos where id = %L', ct));
  r := r || pg_temp.l(v = 'hola', 'G4 tras los rechazos el contrato conserva el valor bueno (' || v || ')');
  v := pg_temp.run(format('update public.contratos set datos = jsonb_set(datos, ''{fields,cx_inexistente}'', to_jsonb(''x''::text)) where id = %L', ct));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'G5 una clave cx_ que no esta en el catalogo no se guarda (' || left(v, 70) || ')');
  v := pg_temp.run(format('update public.contratos set datos = jsonb_set(datos, ''{fields,cx_solo_sw}'', to_jsonb(''x''::text)) where id = %L', ct));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'G6 la clave cx_ de OTRA empresa no se guarda en un contrato de Lawang (' || left(v, 70) || ')');
  v := pg_temp.run(format('update public.contratos set datos = jsonb_set(datos, ''{fields,cx_plazo_extra}'', to_jsonb(''120.000''::text)) where id = %L', ct));
  v := v || '|' || coalesce(pg_temp.pg(format('select datos->''fields''->>''cx_plazo_extra'' || ''|'' || (datos_fields->>''cx_plazo_extra'') from public.contratos where id = %L', ct)), '?');
  r := r || pg_temp.l(v = 'OK|120000|120000', 'G7 el numero se guarda en forma canonica «120000» (datos y copia) (' || v || ')');
  v := pg_temp.run(format('update public.contratos set datos = jsonb_set(datos, ''{fields,cx_plazo_extra}'', to_jsonb(12.5::numeric)) where id = %L', ct));
  v := v || '|' || coalesce(pg_temp.pg(format('select jsonb_typeof(datos->''fields''->''cx_plazo_extra'') from public.contratos where id = %L', ct)), '?');
  r := r || pg_temp.l(v = 'OK|string', 'G8 un numero JSON se guarda como texto canonico, no como tipo mezclado (' || v || ')');
  v := pg_temp.run(format('update public.contratos set datos = jsonb_set(datos, ''{fields,cx_plazo_extra}'', to_jsonb(''abc''::text)) where id = %L', ct));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'G9 un numero que no lo es no se guarda (' || left(v, 70) || ')');
  v := pg_temp.run(format('update public.contratos set datos = jsonb_set(datos, ''{fields,cx_zona}'', to_jsonb(''sur''::text)) where id = %L', ct));
  r := r || pg_temp.l(v = 'OK', 'G10 un valor de lista dentro de las opciones se guarda');
  v := pg_temp.run(format('update public.contratos set datos = jsonb_set(datos, ''{fields,cx_nota}'', to_jsonb(''''::text)) where id = %L', ct));
  r := r || pg_temp.l(v = 'OK', 'G11 vaciar un campo siempre se puede');
  v := pg_temp.run(format('update public.contratos set created_at = created_at where id = %L', ct));
  r := r || pg_temp.l(v = 'OK', 'G12 un guardado que no toca datos ni lo mira (OK)');
  -- el contrato ya usa cx_zona/cx_plazo_extra: el tipo y las opciones quedan fijados por los CONTRATOS aunque ninguna version los use
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_guarda(''lawang'', ''cx_plazo_extra'', ''Plazo extra'', null, null, ''texto'', null, true)');
  r := r || pg_temp.l(pg_temp.err(v) = '55000', 'G13 cambiar el tipo de un campo con valores en contratos se niega (' || left(v, 70) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_guarda(''lawang'', ''cx_zona'', ''Zona'', null, null, ''lista'', ''["norte"]''::jsonb, false, false)');
  r := r || pg_temp.l(pg_temp.err(v) = '55000', 'G14 quitar una opcion de una lista en uso se niega (' || left(v, 70) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_guarda(''lawang'', ''cx_zona'', ''Zona'', null, null, ''lista'', ''["norte","sur","este"]''::jsonb, false, false)');
  r := r || pg_temp.l(v not like 'ERR%', 'G15 anadir una opcion a una lista en uso SI se puede (' || left(v, 70) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_borra(''lawang'', ''cx_zona'')');
  r := r || pg_temp.l(pg_temp.err(v) = '55000', 'G16 borrar un campo con valores en contratos se niega aunque ninguna version lo use (' || left(v, 70) || ')');
  -- archivar: lo viejo sigue, lo nuevo no
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_archiva(''lawang'', ''cx_zona'')');
  r := r || pg_temp.l(v is null or v not like 'ERR%', 'G17 un campo en uso se ARCHIVA (' || coalesce(left(v, 60), 'ok') || ')');
  v := pg_temp.run(format('update public.contratos set datos = jsonb_set(datos, ''{fields,cx_nota}'', to_jsonb(''otra''::text)) where id = %L', ct));
  r := r || pg_temp.l(v = 'OK', 'G18 con un campo archivado en el contrato, otro guardado que no lo cambia sigue funcionando (' || left(v, 60) || ')');
  v := pg_temp.run(format('update public.contratos set datos = jsonb_set(datos, ''{fields,cx_zona}'', to_jsonb(''este''::text)) where id = %L', ct));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'G19 un valor NUEVO en un campo archivado se niega (' || left(v, 70) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_valida(''lawang'', ''{"cx_zona":"sur"}''::jsonb)->>''ok''');
  r := r || pg_temp.l(v = 'false', 'G20 la validacion tambien rechaza el archivado');
  -- texto: archivar cx_nota (usado por el borrador) y ver que el validador lo rechaza; restaurarlo y que vuelve
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_archiva(''lawang'', ''cx_nota'')');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_revisa(''lawang'', ''commercial_offer'', %L)->>''ok''', bcx));
  r := r || pg_temp.l(v = 'false', 'G21 con cx_nota ARCHIVADO el ensayo rechaza el texto que lo usa (' || v || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_revisa(''lawang'', ''commercial_offer'', %L)->>''ok''', body));
  r := r || pg_temp.l(v = 'true', 'G22 y el texto sin el campo sigue pasando: el esqueleto no se rompe por archivar (' || v || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_archiva(''lawang'', ''cx_nota'', false)');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_revisa(''lawang'', ''commercial_offer'', %L)->>''ok''', bcx));
  r := r || pg_temp.l(v = 'true', 'G23 restaurado, el campo vuelve a valer en el texto (' || v || ')');

  -- ============================================================ H. EXPOSICION al bot y a la IA
  v := pg_temp.val(ctl_L.uid, ctl_L.em, 'select array_to_string(public.plantilla_campos_cx_publicos(''lawang''), '','')');
  r := r || pg_temp.l(v = 'cx_monto,cx_zona', 'H1 por empresa: solo los NO sensibles (cx_monto, cx_zona), nunca cx_nota ni cx_plazo_extra (' || coalesce(v, '-') || ')');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, format('select array_to_string(public.plantilla_campos_cx_publicos(null, %L), '','')', ct));
  r := r || pg_temp.l(v = 'cx_monto,cx_zona', 'H2 por contrato: la misma lista, derivada en el servidor de la empresa del contrato (' || coalesce(v, '-') || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, format('select cardinality(public.plantilla_campos_cx_publicos(null, %L))::text', ct));
  r := r || pg_temp.l(v = '0', 'H3 un agente de otra empresa no obtiene nada de un contrato que no es suyo (' || coalesce(v, '-') || ')');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, 'select cardinality(public.plantilla_campos_cx_publicos(null, gen_random_uuid()))::text');
  r := r || pg_temp.l(v = '0', 'H4 un contrato que no existe devuelve vacio (cerrado por defecto)');
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ctl_L.uid, ctl_L.em, 'select public.plantilla_campos_cx_publicos(''lawang'', gen_random_uuid())')) = '22023', 'H5 se pide la empresa O el contrato, no los dos');
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ctl_L.uid, ctl_L.em, 'select public.plantilla_campos_cx_publicos()')) = '22023', 'H6 ni ninguno');
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ae_S.uid, ae_S.em, 'select public.plantilla_campos_cx_publicos(''lawang'')')) = '42501', 'H7 por empresa, solo la tuya');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_guarda(''lawang'', ''cx_nota'', ''Nota'', null, null, ''texto'', null, true, false)');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, 'select array_to_string(public.plantilla_campos_cx_publicos(''lawang''), '','')');
  r := r || pg_temp.l(v = 'cx_monto,cx_nota,cx_zona', 'H8 marcar un campo como NO sensible lo abre al bot; volver a sensible lo cierra de nuevo (' || coalesce(v, '-') || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_guarda(''lawang'', ''cx_nota'', ''Nota'', null, null, ''texto'', null, true, true)');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, 'select array_to_string(public.plantilla_campos_cx_publicos(''lawang''), '','')');
  r := r || pg_temp.l(v = 'cx_monto,cx_zona', 'H9 y vuelve a cerrarse (' || coalesce(v, '-') || ')');

  -- ============================================================ I. NADA MAS SE MUEVE
  select count(*) into n from public.contratos where datos_fields::text like '%"cx\_%' and id <> ct;
  r := r || pg_temp.l(n = 0, 'I1 ningun otro contrato recibio claves cx_ (' || n || ')');
  select count(*) into n from public.plantilla_contrato_versiones where origen = 'semilla' and (estado <> 'borrador' or variante <> 'estandar');
  r := r || pg_temp.l(n = 0, 'I2 las semillas siguen intactas (' || n || ' mal)');
  select count(*) into n from (select empresa, slug, variante from public.plantilla_contrato_versiones where estado = 'activa' and borrada_en is null group by 1, 2, 3 having count(*) > 1) q;
  r := r || pg_temp.l(n = 0, 'I3 nunca hay dos activas en la misma revision (' || n || ')');
  select count(*) into n from public.plantilla_contrato_versiones v join public.plantilla_contrato_cuerpos c on c.version_id = v.id where v.hash <> public._plantilla_hash(c.cuerpo_html);
  r := r || pg_temp.l(n = 0, 'I4 el hash de cada version casa con su cuerpo (' || n || ' mal)');

  fallos := (select count(*) from regexp_matches(r, 'FALLO', 'g'));
  raise exception E'INFORME E8\n%FALLOS=%', r, fallos;
end $todo$;
