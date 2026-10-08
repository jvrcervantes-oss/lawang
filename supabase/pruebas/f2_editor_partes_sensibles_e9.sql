-- Prueba de «partes sensibles editables» (20261010020000) y E9 «contrato nuevo creado por el cliente» (20261010030000) (8-oct-2026).
-- Se pega DESPUES de las dos migraciones en la MISMA peticion (ensayo sin rastro: el bloque acaba en raise y todo se deshace, migraciones incluidas). Personas por JWT simulado, como f2_editor_e8_campos_propios.sql.
-- NO activa nada en produccion ni toca contratos reales. Debe terminar con «FALLOS=0».
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); los borradores, contratos propios, campos y registros de prueba se deshacen
create temp table _t9 (et text primary key, uid uuid, em text);
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

insert into _t9 select 'jv', user_id, email from public.usuarios where email = 'jvr.cervantes@gmail.com';
insert into _t9
  select (array['ae_L', 'se_L', 'ae_S', 'se_S', 'ctl_L', 'adm_G'])[rn], user_id, email
    from (select user_id, email, row_number() over (order by email) rn
            from (select user_id, email from public.usuarios where activo and ambito = 'global' and rol = 'agente' order by email limit 6) q) z;

do $todo$
declare
  r text := ''; v text; n bigint; bb boolean; fallos int; j jsonb; i int;
  jv _t9; ae_L _t9; se_L _t9; ae_S _t9; se_S _t9; ctl_L _t9; adm_G _t9;
  body text; body_sens text; body_libre text; body_otra text; cand text; m text[]; razS text; vid uuid; nver_antes bigint; naud_antes bigint; ntipos bigint;
  slugA text; slugB text; slugC text; v2 uuid; esqid uuid; src_borr uuid;
  nuevas text[] := array['plantilla_contrato_guarda_borrador(text,text,text,text,text,boolean)', 'plantilla_contrato_cambios_sensibles(text,text,integer)',
                         'plantilla_contrato_nuevo_crea(text,text,text,text,uuid,jsonb)'];
  cerradas text[] := array['_plantilla_bloque_motivo(text,text)', '_plantilla_bloques_tocados(text,text,text)', '_plantilla_esqueleto_en_blanco(text,text[],text)',
                           '_trg_plantilla_bloque_cambios_solo_anade()', '_trg_plantilla_version_empresa_propia()'];
  f text;
begin
  select * into jv from _t9 where et = 'jv'; select * into ae_L from _t9 where et = 'ae_L'; select * into se_L from _t9 where et = 'se_L'; select * into ae_S from _t9 where et = 'ae_S';
  select * into se_S from _t9 where et = 'se_S'; select * into ctl_L from _t9 where et = 'ctl_L'; select * into adm_G from _t9 where et = 'adm_G';
  perform set_config('request.jwt.claims', json_build_object('sub', jv.uid, 'role', 'authenticated', 'email', jv.em)::text, true);
  update public.usuarios set rol = 'admin_empresa', ambito = 'empresa', empresas = '{lawang}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{}', tipos_contrato = '{}' where user_id = ae_L.uid;
  update public.usuarios set rol = 'super_admin_empresa', ambito = 'empresa', empresas = '{lawang}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{}', tipos_contrato = '{}' where user_id = se_L.uid;
  update public.usuarios set rol = 'admin_empresa', ambito = 'empresa', empresas = '{sandal_woods}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{}', tipos_contrato = '{}' where user_id = ae_S.uid;
  update public.usuarios set rol = 'super_admin_empresa', ambito = 'empresa', empresas = '{sandal_woods}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{}', tipos_contrato = '{}' where user_id = se_S.uid;
  update public.usuarios set rol = 'agente', ambito = 'global', empresas = '{lawang}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{}', tipos_contrato = '{}' where user_id = ctl_L.uid;
  update public.usuarios set rol = 'admin', ambito = 'global', empresas = '{}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{}', tipos_contrato = '{}' where user_id = adm_G.uid;
  select count(*) into ntipos from public.plantillas_contrato;
  select razon into razS from public.sociedades where clave = 'san_dal_woods';

  -- ============================================================ A. exposicion
  select count(*) into n from pg_class where relname = 'plantilla_bloque_cambios' and relrowsecurity
     and not (has_table_privilege('authenticated', oid, 'select') or has_table_privilege('authenticated', oid, 'insert') or has_table_privilege('authenticated', oid, 'update')
              or has_table_privilege('authenticated', oid, 'delete') or has_table_privilege('anon', oid, 'select') or has_table_privilege('service_role', oid, 'select'));
  r := r || pg_temp.l(n = 1, 'A1 el registro de partes sensibles tiene RLS y ningun GRANT directo (ni authenticated, ni anon, ni service_role)');
  select count(*) into n from unnest(nuevas) x where has_function_privilege('authenticated', 'public.' || x, 'execute');
  r := r || pg_temp.l(n = 3, 'A2 authenticated ejecuta las 3 RPC (guarda_borrador nueva firma, cambios_sensibles, nuevo_crea) (' || n || ')');
  select count(*) into n from unnest(nuevas) x where has_function_privilege('anon', 'public.' || x, 'execute') or has_function_privilege('service_role', 'public.' || x, 'execute');
  r := r || pg_temp.l(n = 0, 'A3 anon y service_role no ejecutan ninguna (' || n || ')');
  select count(*) into n from unnest(cerradas) x where has_function_privilege('authenticated', 'public.' || x, 'execute') or has_function_privilege('anon', 'public.' || x, 'execute') or has_function_privilege('service_role', 'public.' || x, 'execute');
  r := r || pg_temp.l(n = 0, 'A4 los 5 ayudantes internos no son ejecutables por el API (' || n || ')');
  select count(*) into n from pg_proc where proname = 'plantilla_contrato_guarda_borrador' and pronamespace = 'public'::regnamespace;
  r := r || pg_temp.l(n = 1, 'A5 solo existe UNA plantilla_contrato_guarda_borrador (la firma vieja se retiro; sin sobrecarga ambigua) (' || n || ')');
  select count(*) into n from pg_proc p where p.proname in ('plantilla_contrato_guarda_borrador', 'plantilla_contrato_cambios_sensibles', 'plantilla_contrato_nuevo_crea') and p.pronamespace = 'public'::regnamespace
     and p.prosecdef and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%');
  r := r || pg_temp.l(n = 3, 'A6 las 3 RPC son SECURITY DEFINER con search_path vacio (' || n || ')');

  -- ============================================================ B. partes sensibles
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select (public.plantilla_contrato_edicion(''lawang'', ''commercial_offer'') ->> ''cuerpo_html'')');
  body := v;
  r := r || pg_temp.l(v !~ '^ERR' and length(v) > 2000, 'B0 el admin de Lawang lee el texto de commercial_offer (' || length(v) || ' bytes)');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select jsonb_array_length(public.plantilla_contrato_edicion(''lawang'', ''commercial_offer'') -> ''bloques_fijos'') || ''/'' || jsonb_array_length(public.plantilla_contrato_edicion(''lawang'', ''commercial_offer'') -> ''bloques_fijos_motivos'')');
  r := r || pg_temp.l(v ~ '^[1-9][0-9]*/[1-9][0-9]*$' and split_part(v, '/', 1) = split_part(v, '/', 2), 'B1 edicion devuelve un motivo por cada bloque fijo, en el mismo numero y orden (' || v || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select count(*) from jsonb_array_elements(public.plantilla_contrato_edicion(''lawang'', ''commercial_offer'') -> ''bloques_fijos_motivos'') e where coalesce(e ->> ''motivo'', '''') = '''' or (e ->> ''clase'') not in (''region'', ''elemento'', ''seccion'', ''residuo'')');
  r := r || pg_temp.l(v = '0', 'B2 todo motivo es no vacio y toda clase conocida (' || v || ' mal)');
  v := pg_temp.val(jv.uid, jv.em, 'select jsonb_array_length(public.plantilla_contrato_edicion(''lawang'', ''commercial_offer'') -> ''bloques_fijos_motivos'')');
  r := r || pg_temp.l(v = '0', 'B3 el super GLOBAL no ve bloques fijos (nada le sale bloqueado) (' || v || ')');

  body_sens := replace(body, 'NPWP {{prom_npwp}}', 'NPWP de {{prom_npwp}}');
  r := r || pg_temp.l(body_sens <> body, 'B4 datos de partida: el texto de Lawang trae «NPWP {{prom_npwp}}» (identidad de la sociedad = bloque fijo)');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_revisa(''lawang'', ''commercial_offer'', %L)::text', body_sens));
  j := case when v like 'ERR%' then null else v::jsonb end;
  r := r || pg_temp.l(j is not null and (j ->> 'ok')::boolean and (j ->> 'sensibles')::boolean and jsonb_array_length(j -> 'bloques_tocados') >= 1
                      and (j -> 'bloques_tocados' -> 0 ->> 'motivo') like '%identidad%' and (j -> 'bloques_tocados' -> 0 ->> 'antes') like '%NPWP%' and (j -> 'bloques_tocados' -> 0 ->> 'despues') like '%NPWP de%',
                      'B5 el ensayo ya NO rechaza el cambio: devuelve ok, sensibles y el bloque tocado con motivo, antes y despues (' || left(coalesce(j -> 'bloques_tocados' -> 0 ->> 'motivo', v), 60) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_revisa(''lawang'', ''commercial_offer'', %L)::text', body));
  j := case when v like 'ERR%' then null else v::jsonb end;
  r := r || pg_temp.l(j is not null and (j ->> 'ok')::boolean and not (j ->> 'sensibles')::boolean and jsonb_array_length(j -> 'bloques_tocados') = 0, 'B6 el texto sin tocar no marca nada como sensible');

  select count(*) into nver_antes from public.plantilla_contrato_versiones where empresa = 'lawang' and slug = 'commercial_offer';
  select count(*) into naud_antes from public.plantilla_bloque_cambios;
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_guarda_borrador(''lawang'', ''commercial_offer'', %L, ''actualizo la identidad'')', body_sens));
  r := r || pg_temp.l(pg_temp.err(v) = '22023' and v like '%confirma que has leido el aviso%', 'B7 guardar un bloque fijo SIN confirmar el aviso se rechaza en llano (' || left(v, 120) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_guarda_borrador(''lawang'', ''commercial_offer'', %L, ''actualizo la identidad'', ''estandar'', false)', body_sens));
  r := r || pg_temp.l(pg_temp.err(v) = '22023' and v like '%confirma que has leido%', 'B7b ... tambien con p_confirma_sensibles = false explicito');
  select count(*) into n from public.plantilla_contrato_versiones where empresa = 'lawang' and slug = 'commercial_offer';
  r := r || pg_temp.l(n = nver_antes and (select count(*) from public.plantilla_bloque_cambios) = naud_antes, 'B8 el rechazo no deja version ni registro (' || n || ' versiones, ' || (select count(*) from public.plantilla_bloque_cambios) || ' registros)');

  -- un cambio libre no pide confirmacion ni deja registro
  body_libre := null;
  for m in select regexp_matches(body, '<p data-lang="es">([^<{&]{25,120})</p>', 'g') loop
    cand := replace(body, m[1], m[1] || ' (revisado)');
    exit when body_libre is not null;
    if jsonb_array_length(public._plantilla_bloques_tocados(cand, public._plantilla_esqueleto('lawang', 'commercial_offer'), 'commercial_offer')) = 0 then body_libre := cand; end if;
  end loop;
  r := r || pg_temp.l(body_libre is not null, 'B17 datos de partida: hay un parrafo libre que editar sin tocar bloques fijos');
  select count(*) into naud_antes from public.plantilla_bloque_cambios;
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_guarda_borrador(''lawang'', ''commercial_offer'', %L, ''retoque un parrafo libre'')', coalesce(body_libre, body)));
  r := r || pg_temp.l(v !~ '^ERR' and (select count(*) from public.plantilla_bloque_cambios) = naud_antes, 'B18 un cambio en texto libre se guarda sin confirmar y sin registro (' || left(v, 60) || ')');

  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_guarda_borrador(''lawang'', ''commercial_offer'', %L, ''actualizo la identidad'', ''estandar'', true)', body_sens));
  r := r || pg_temp.l(v !~ '^ERR', 'B9 con el aviso confirmado el admin de empresa SI guarda el cambio de una parte sensible (' || left(v, 70) || ')');
  vid := case when v !~ '^ERR' then v::uuid end;
  select count(*) into n from public.plantilla_bloque_cambios c where c.version_id = vid and c.empresa = 'lawang' and c.slug = 'commercial_offer' and c.aviso_confirmado
     and c.autor = ae_L.em and c.autor_uid = ae_L.uid and c.antes like '%NPWP {{prom_npwp}}%' and c.despues like '%NPWP de {{prom_npwp}}%' and c.motivo like '%identidad%' and c.motivo_cambio = 'actualizo la identidad' and c.fecha > now() - interval '1 minute';
  r := r || pg_temp.l(n >= 1, 'B10 queda registrado: quien, cuando, motivo del bloque, texto antes y despues, aviso confirmado (' || n || ' fila/s)');
  r := r || pg_temp.l(pg_temp.pg('update public.plantilla_bloque_cambios set despues = ''x''') like 'ERR55000%', 'B11 el registro no se modifica (ni como dueno): solo se anade');
  r := r || pg_temp.l(pg_temp.pg('delete from public.plantilla_bloque_cambios') like 'ERR55000%', 'B11b ... ni se borra');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select count(*) from public.plantilla_bloque_cambios');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'B12 el navegador no lee el registro por la tabla (' || left(v, 60) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select jsonb_array_length(public.plantilla_contrato_cambios_sensibles(''lawang'', ''commercial_offer'') -> ''cambios'')');
  r := r || pg_temp.l(v ~ '^[0-9]+$' and v::int >= 1, 'B13 el admin lee el registro de su empresa por la RPC (' || v || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, 'select public.plantilla_contrato_cambios_sensibles(''lawang'')::text');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'B14 un admin de Sandal Woods no lee el registro de Lawang (' || left(v, 50) || ')');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, 'select public.plantilla_contrato_cambios_sensibles(''lawang'')::text');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'B15 un agente (no administrador) no lo lee (' || left(v, 50) || ')');
  v := pg_temp.val(null, null, 'select public.plantilla_contrato_cambios_sensibles(''lawang'')::text', 'anon');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'B16 anon no lo lee (' || left(v, 50) || ')');

  -- guardar de nuevo el borrador que ya llevaba el cambio confirmado, con un retoque libre: NO pide aviso otra vez ni duplica el registro
  select count(*) into naud_antes from public.plantilla_bloque_cambios;
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_revisa(''lawang'', ''commercial_offer'', %L)::text', replace(coalesce(body_libre, body), 'NPWP {{prom_npwp}}', 'NPWP de {{prom_npwp}}')));
  j := case when v like 'ERR%' then null else v::jsonb end;
  r := r || pg_temp.l(j is not null and (j ->> 'ok')::boolean and not (j ->> 'sensibles')::boolean, 'B20a el ensayo compara con lo ya guardado: el borrador ya llevaba el cambio, ya no es «sensible» (' || left(coalesce(j ->> 'sensibles', v), 40) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_guarda_borrador(''lawang'', ''commercial_offer'', %L, ''retoque libre despues del aviso'')', replace(coalesce(body_libre, body), 'NPWP {{prom_npwp}}', 'NPWP de {{prom_npwp}}')));
  r := r || pg_temp.l(v !~ '^ERR' and (select count(*) from public.plantilla_bloque_cambios) = naud_antes, 'B20b ... y guardar sin confirmar otra vez va, sin registro duplicado (' || left(v, 70) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_guarda_borrador(''lawang'', ''commercial_offer'', %L, ''deshago el cambio'')', body));
  r := r || pg_temp.l(pg_temp.err(v) = '22023' and v like '%confirma que has leido%', 'B20c ... pero deshacer el cambio sensible SI vuelve a pedir el aviso (' || left(v, 80) || ')');

  -- el super GLOBAL no necesita confirmar, pero queda registrado
  select count(*) into naud_antes from public.plantilla_bloque_cambios where autor = jv.em;
  v := pg_temp.val(jv.uid, jv.em, format('select public.plantilla_contrato_guarda_borrador(''lawang'', ''commercial_offer'', %L, ''el global ajusta la identidad'')', replace(body, 'NPWP {{prom_npwp}}', 'NPWP del {{prom_npwp}}')));
  r := r || pg_temp.l(v !~ '^ERR', 'B19 el super GLOBAL guarda sin confirmar (' || left(v, 60) || ')');
  select count(*) into n from public.plantilla_bloque_cambios where autor = jv.em and not aviso_confirmado;
  r := r || pg_temp.l(n > naud_antes, 'B20 ... y queda registrado con aviso_confirmado = false (' || n || ' fila/s)');

  -- protecciones tecnicas que NO cambian
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_guarda_borrador(''lawang'', ''commercial_offer'', %L, ''prueba script'', ''estandar'', true)', body_sens || '<script>alert(1)</script>'));
  r := r || pg_temp.l(pg_temp.err(v) = '22023' and v like '%script%', 'B21 <script> sigue rechazado aunque se confirme el aviso (' || left(v, 90) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_guarda_borrador(''lawang'', ''commercial_offer'', %L, ''prueba marcador'', ''estandar'', true)', replace(body_sens, 'NPWP de {{prom_npwp}}', 'NPWP de {{no_existe_ese}}')));
  r := r || pg_temp.l(pg_temp.err(v) = '22023' and v like '%marcador desconocido%', 'B22 un marcador inventado sigue rechazado (' || left(v, 90) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_guarda_borrador(''lawang'', ''commercial_offer'', %L, ''prueba estructura'', ''estandar'', true)', body_sens || '<table><tr><td>x</td></tr></table>'));
  r := r || pg_temp.l(pg_temp.err(v) = '22023' and v like '%esqueleto%', 'B23 cambiar la estructura (anadir una tabla) sigue rechazado (' || left(v, 90) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_guarda_borrador(''lawang'', ''commercial_offer'', %L, ''prueba onclick'', ''estandar'', true)', replace(body_sens, '<p data-lang="es">', '<p onclick="x()" data-lang="es">')));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'B24 un manejador on* sigue rechazado (' || left(v, 90) || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, format('select public.plantilla_contrato_guarda_borrador(''lawang'', ''commercial_offer'', %L, ''intruso'', ''estandar'', true)', body_sens));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'B25 un admin de Sandal Woods no guarda texto de Lawang (' || left(v, 70) || ')');

  -- texto de otra sociedad: se guarda, pero NO se puede activar
  body_otra := null;
  for m in select regexp_matches(body, '<p data-lang="es">([^<{&]{25,120})</p>', 'g') loop
    cand := replace(body, m[1], m[1] || ' ' || razS);
    exit when body_otra is not null;
    if jsonb_array_length(public._plantilla_bloques_tocados(cand, public._plantilla_esqueleto('lawang', 'commercial_offer'), 'commercial_offer')) = 0 then body_otra := cand; end if;
  end loop;
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_guarda_borrador(''lawang'', ''commercial_offer'', %L, ''prueba otra sociedad'', ''estandar'', true)', coalesce(body_otra, body)));
  select (activable is false and bloqueo_motivo like '%otra sociedad%') into bb from public.plantilla_contrato_versiones
        where empresa = 'lawang' and slug = 'commercial_offer' and estado = 'borrador' and origen = 'empresa' and variante = 'estandar';
  r := r || pg_temp.l(v !~ '^ERR' and body_otra is not null and bb, 'B26 el texto que nombra a otra sociedad se guarda pero queda NO activable (F1 intacto)');
  src_borr := (select id from public.plantilla_contrato_versiones where empresa = 'lawang' and slug = 'commercial_offer' and estado = 'borrador' and origen = 'empresa' and variante = 'estandar');

  -- solo-global y nunca-activable siguen
  select count(*) into n from public.plantilla_solo_global;
  r := r || pg_temp.l(n >= 1, 'B27 plantilla_solo_global sigue con sus filas (' || n || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, 'select (public.plantilla_contrato_edicion(''sandal_woods'', ''estatutos_sw'') ->> ''cuerpo_html'')');
  if v !~ '^ERR' then
    v := pg_temp.val(ae_S.uid, ae_S.em, format('select public.plantilla_contrato_guarda_borrador(''sandal_woods'', ''estatutos_sw'', %L, ''intento'', ''estandar'', true)', replace(v, '</p>', ' X</p>')));
    r := r || pg_temp.l(pg_temp.err(v) = '42501' and v like '%no lo cambia una empresa sola%', 'B28 estatutos_sw (solo global) sigue sin cambiar por una empresa ni confirmando el aviso (' || left(v, 90) || ')');
  else
    r := r || pg_temp.l(false, 'B28 no se pudo leer estatutos_sw de Sandal Woods (' || v || ')');
  end if;

  -- ============================================================ C. E9 contrato nuevo
  select count(*) into n from public.plantillas_contrato where empresa is null;
  r := r || pg_temp.l(n = ntipos, 'C0 los contratos del estudio siguen siendo ' || ntipos || ' y todos con empresa null (' || n || ')');
  -- campos propios de Lawang
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_guarda(''lawang'', ''cx_ref_proyecto'', ''Referencia del proyecto'', null, null, ''texto'', null, false)')) is null, 'C1 datos de partida: campo cx_ref_proyecto');
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_guarda(''lawang'', ''cx_resp_obra'', ''Responsable & obra'', ''Site manager'', ''Penanggung jawab'', ''texto'', null, false)')) is null, 'C2 datos de partida: campo cx_resp_obra (con «&» en la etiqueta)');
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_guarda(''lawang'', ''cx_viejo'', ''Campo viejo'', null, null, ''texto'', null, false)')) is null, 'C3 datos de partida: campo cx_viejo');
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_campo_propio_archiva(''lawang'', ''cx_viejo'', true)')) is null, 'C3b ... archivado');

  -- aislamiento previo a crear: sin permiso
  v := pg_temp.val(ctl_L.uid, ctl_L.em, 'select public.plantilla_contrato_nuevo_crea(''lawang'', ''Contrato sin permiso'', ''blanco'')::text');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'C4 un agente (no administrador) no crea contratos (' || left(v, 60) || ')');
  v := pg_temp.val(null, null, 'select public.plantilla_contrato_nuevo_crea(''lawang'', ''Contrato anonimo'', ''blanco'')::text', 'anon');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'C4b anon no crea (' || left(v, 60) || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, 'select public.plantilla_contrato_nuevo_crea(''lawang'', ''Contrato intruso'', ''blanco'')::text');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'C5 un admin de Sandal Woods no crea contratos en Lawang (' || left(v, 60) || ')');

  -- blanco con campos
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_nuevo_crea(''lawang'', ''Contrato de prueba Alfa'', ''blanco'', null, null, ''["cx_ref_proyecto","cx_resp_obra","cx_ref_proyecto"]'')::text');
  j := case when v like 'ERR%' then null else v::jsonb end;
  r := r || pg_temp.l(j is not null, 'C6 un admin de empresa crea un contrato EN BLANCO con 2 campos (' || left(v, 120) || ')');
  slugA := j ->> 'slug'; v2 := (j ->> 'version_id')::uuid; esqid := (j ->> 'esqueleto_id')::uuid;
  r := r || pg_temp.l(slugA = 'lawang_contrato_de_prueba_alfa', 'C7 slug generado con prefijo de empresa y nombre normalizado (' || coalesce(slugA, '-') || ')');
  select count(*) into n from public.plantillas_contrato where slug = slugA and empresa = 'lawang' and archivada and campos = '["cx_ref_proyecto","cx_resp_obra"]'::jsonb and nombre = 'Contrato de prueba Alfa';
  r := r || pg_temp.l(n = 1, 'C8 fila en plantillas_contrato: de Lawang, archivada (no se ofrece a contratos reales), campos sin duplicados y en orden');
  select count(*) into n from public.plantilla_contrato_versiones where slug = slugA and empresa = 'lawang'
     and ((version = 1 and origen = 'semilla' and estado = 'borrador' and not activable and id = esqid) or (version = 2 and origen = 'empresa' and estado = 'borrador' and hereda_de = esqid and id = v2));
  r := r || pg_temp.l(n = 2, 'C9 v1 = esqueleto (semilla, no activable) y v2 = borrador editable de la empresa, heredando de v1');
  select (activable is false and bloqueo_motivo like '%Escribe%') into bb from public.plantilla_contrato_versiones where id = v2;
  r := r || pg_temp.l(bb, 'C10 el borrador en blanco nace NO activable por los textos de ejemplo');
  select c.cuerpo_html into body from public.plantilla_contrato_cuerpos c where c.version_id = v2;
  r := r || pg_temp.l(body like '%{{cx_ref_proyecto}}%' and body like '%{{cx_resp_obra}}%' and body like '%Responsable &amp; obra%' and body like '%Site manager%' and body like '%Penanggung jawab%', 'C11 el cuerpo lleva los 2 campos con sus etiquetas en es/en/id');
  r := r || pg_temp.l(cardinality(public._plantilla_bloques_fijos(body, slugA)) = 0, 'C12 el esqueleto en blanco no cae en ningun bloque fijo (el cliente escribe sin avisos)');
  select count(*) into n from public.plantilla_contrato_versiones v join public.plantilla_contrato_cuerpos c on c.version_id = v.id where v.slug = slugA and v.hash = public._plantilla_hash(c.cuerpo_html) and v.bytes = octet_length(c.cuerpo_html);
  r := r || pg_temp.l(n = 2, 'C13 hash y tamano de las dos versiones casan con su cuerpo');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_revisa(''lawang'', %L, %L)::text', slugA, body));
  j := case when v like 'ERR%' then null else v::jsonb end;
  r := r || pg_temp.l(j is not null and (j ->> 'ok')::boolean and not (j ->> 'activable')::boolean, 'C14 el ensayo valida el texto en blanco pero lo da por no activable');

  -- aislamiento Lawang / Sandal Woods
  v := pg_temp.val(ae_S.uid, ae_S.em, format('select count(*) from public.plantillas_contrato where slug = %L', slugA));
  r := r || pg_temp.l(v = '0', 'C15 un admin de Sandal Woods NO ve el contrato propio de Lawang en plantillas_contrato (' || v || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, format('select count(*) from public.plantillas_pago where slug = %L', slugA));
  r := r || pg_temp.l(v = '0' or pg_temp.err(v) = '42501', 'C15b ... ni por la vista de compatibilidad plantillas_pago (sin GRANT para el API, y security_invoker) (' || left(v, 50) || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, 'select count(*) from public.plantillas_contrato');
  r := r || pg_temp.l(v = ntipos::text, 'C16 la lista de tipos de Sandal Woods sigue siendo la de siempre (' || v || ' de ' || ntipos || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select count(*) from public.plantillas_contrato where slug = %L', slugA));
  r := r || pg_temp.l(v = '1', 'C17 el admin de Lawang SI ve su contrato propio (' || v || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select count(*) from public.plantillas_contrato');
  r := r || pg_temp.l(v = (ntipos + 1)::text, 'C17b ... y su lista suma el propio a los del estudio (' || v || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, format('select public.plantilla_contrato_guarda_borrador(''sandal_woods'', %L, %L, ''me cuelo'', ''estandar'', true)', slugA, body));
  r := r || pg_temp.l(v ~ '^ERR', 'C18 Sandal Woods no puede guardar texto en el contrato de Lawang (' || left(v, 90) || ')');
  r := r || pg_temp.l(pg_temp.pg(format('insert into public.plantilla_contrato_versiones (empresa, slug, version, origen, idioma_set, hash, bytes, activable, bloqueo_motivo, autor, motivo) values (''sandal_woods'', %L, 9, ''empresa'', ''{es}'', repeat(''a'', 64), 1, false, ''x'', ''t'', ''t'')', slugA)) like 'ERR42501%', 'C19 el trigger impide una version de otra empresa sobre un contrato propio (defensa en profundidad)');
  v := pg_temp.val(ae_S.uid, ae_S.em, format('select count(*) from public.plantilla_contrato_versiones_lista(null, null) where slug = %L', slugA));
  r := r || pg_temp.l(v = '0', 'C20 la lista de versiones de Sandal Woods no trae el contrato de Lawang (' || v || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, format('select public.plantilla_contrato_nuevo_crea(''sandal_woods'', ''Copia ajena'', ''copia'', ''commercial_offer'', %L)::text', src_borr));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'C21 Sandal Woods no copia una version de Lawang por su id (' || left(v, 80) || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, format('select public.plantilla_contrato_nuevo_crea(''sandal_woods'', ''Copia del propio de Lawang'', ''copia'', %L)::text', slugA));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'C21b ni parte de un contrato propio de Lawang por su slug (' || left(v, 80) || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, 'select public.plantilla_contrato_nuevo_crea(''sandal_woods'', ''Campos ajenos'', ''blanco'', null, null, ''["cx_ref_proyecto"]'')::text');
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'C22 los campos propios son de cada empresa: Sandal Woods no usa los de Lawang (' || left(v, 80) || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, 'select public.plantilla_contrato_nuevo_crea(''sandal_woods'', ''Estatutos propios'', ''copia'', ''estatutos_sw'')::text');
  r := r || pg_temp.l(pg_temp.err(v) = '42501' and v like '%no se copia%', 'C23 un contrato solo-global no se copia (se saltaria la proteccion) (' || left(v, 80) || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, 'select public.plantilla_contrato_nuevo_crea(''sandal_woods'', ''Alfa de SW'', ''blanco'')::text');
  j := case when v like 'ERR%' then null else v::jsonb end;
  r := r || pg_temp.l(j is not null and j ->> 'slug' = 'sandal_woods_alfa_de_sw', 'C24 Sandal Woods crea el suyo en blanco con su propio prefijo (' || left(v, 90) || ')');

  -- activacion: un contrato en blanco no se activa sin escribirlo
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_activa(%L, ''Persona Prueba'', true)::text', v2));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'C25 el admin de empresa (no super) no activa (' || left(v, 60) || ')');
  v := pg_temp.val(se_L.uid, se_L.em, format('select public.plantilla_contrato_activa(%L, ''Persona Prueba'', true)::text', v2));
  r := r || pg_temp.l(pg_temp.err(v) = '55000' and v like '%Version no activable%', 'C26 ni el super de la empresa activa el texto en blanco (' || left(v, 120) || ')');
  update public.plantilla_contrato_versiones set activable = true, bloqueo_motivo = null where id = v2;
  v := pg_temp.val(se_L.uid, se_L.em, format('select public.plantilla_contrato_activa(%L, ''Persona Prueba'', true)::text', v2));
  r := r || pg_temp.l(pg_temp.err(v) = '55000' and v like '%textos de ejemplo%', 'C27 aunque la marca activable se forzara, la activacion vuelve a validar el cuerpo y lo frena (' || left(v, 140) || ')');
  update public.plantilla_contrato_versiones set activable = false, bloqueo_motivo = 'Quedan textos de ejemplo por escribir' where id = v2;
  -- escribirlo de verdad
  body_libre := replace(replace(replace(body, '[Escribe aquí el texto de esta cláusula]', 'Las partes acuerdan el objeto descrito.'), '[Write here the text of this clause]', 'The parties agree the purpose described.'), '[Tulis di sini isi klausul ini]', 'Para pihak menyetujui objek yang diuraikan.');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_guarda_borrador(''lawang'', %L, %L, ''escribo el contrato'')', slugA, body_libre));
  r := r || pg_temp.l(v !~ '^ERR' and v::uuid = v2, 'C28 el cliente escribe el texto y se guarda sobre el mismo borrador sin pedir confirmacion de partes sensibles (' || left(v, 90) || ')');
  select (activable and bloqueo_motivo is null) into bb from public.plantilla_contrato_versiones where id = v2;
  r := r || pg_temp.l(bb, 'C29 ya sin textos de ejemplo, el borrador es activable');
  v := pg_temp.val(se_L.uid, se_L.em, format('select public.plantilla_contrato_activa(%L, ''Persona Prueba'', true)::text', v2));
  r := r || pg_temp.l(v !~ '^ERR', 'C30 el super de la empresa lo activa con su confirmacion (' || left(v, 80) || ')');
  select count(*) into n from public.plantilla_contrato_versiones where id = v2 and estado = 'activa';
  r := r || pg_temp.l(n = 1, 'C31 queda activa');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_guarda_borrador(''lawang'', %L, %L, ''quito una region'', ''estandar'', true)', slugA, replace(body_libre, '<h2><span data-lang="es">Condiciones</span>', '<table><tr><td>x</td></tr></table><h2><span data-lang="es">Condiciones</span>')));
  r := r || pg_temp.l(pg_temp.err(v) = '22023' and v like '%esqueleto%', 'C32 el esqueleto del contrato propio protege su estructura (' || left(v, 90) || ')');

  -- copia
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_nuevo_crea(''lawang'', ''Oferta con mi plazo'', ''copia'', ''commercial_offer'', %L, ''["cx_ref_proyecto"]'')::text', src_borr));
  j := case when v like 'ERR%' then null else v::jsonb end;
  r := r || pg_temp.l(j is not null and (j ->> 'activable')::boolean is false and (j ->> 'bloqueo') like '%otra sociedad%', 'C33 copiar un texto que nombra a otra sociedad crea el borrador pero NO activable (' || left(v, 120) || ')');
  slugB := j ->> 'slug';
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_nuevo_crea(''lawang'', ''Oferta copia limpia'', ''copia'', ''commercial_offer'')::text');
  j := case when v like 'ERR%' then null else v::jsonb end;
  slugC := j ->> 'slug';
  r := r || pg_temp.l(j is not null and slugC = 'lawang_oferta_copia_limpia' and (j ->> 'campos') = '[]', 'C34 copia desde la version vigente de la empresa (sin version indicada) (' || left(v, 100) || ')');
  select count(*) into n from public.plantilla_contrato_versiones v join public.plantilla_contrato_cuerpos c on c.version_id = v.id where v.slug = slugC and public._plantilla_ws(c.cuerpo_html) = public._plantilla_ws(public._plantilla_sin_notas(public._plantilla_esqueleto('lawang', 'commercial_offer')));
  r := r || pg_temp.l(n = 2, 'C35 el texto copiado es el del origen sin notas de autor, en las dos versiones');
  select count(*) into n from public.plantilla_solo_global where slug = 'commercial_offer';
  r := r || pg_temp.l(n = 0, 'C36 (control) commercial_offer no es solo-global');

  -- reglas de entrada
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_nuevo_crea(''lawang'', ''Contrato de prueba Alfa'', ''blanco'')::text')) = '22023', 'C37 un nombre repetido se rechaza');
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_nuevo_crea(''lawang'', ''CONTRATO DE PRUEBA ALFA'', ''blanco'')::text')) = '22023', 'C37b ... aunque cambien las mayusculas');
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_nuevo_crea(''lawang'', ''Carta de Reserva'', ''blanco'')::text')) = '22023', 'C38 ni el nombre de un contrato del estudio');
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_nuevo_crea(''lawang'', ''<script>alert(1)</script>'', ''blanco'')::text')) = '22023', 'C39 un nombre con < > se rechaza');
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_nuevo_crea(''lawang'', ''Con {{marcador}}'', ''blanco'')::text')) = '22023', 'C39b ... y uno con llaves');
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_nuevo_crea(''lawang'', ''Ab'', ''blanco'')::text')) = '22023', 'C40 un nombre de menos de 3 letras se rechaza');
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_nuevo_crea(''lawang'', ''Punto raro'', ''pdf'')::text')) = '22023', 'C41 un punto de partida que no es copia ni blanco se rechaza');
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_nuevo_crea(''lawang'', ''Sin origen'', ''copia'')::text')) = '22023', 'C42 copia sin contrato de origen se rechaza');
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_nuevo_crea(''lawang'', ''Campo archivado'', ''blanco'', null, null, ''["cx_viejo"]'')::text')) = '22023', 'C43 un campo archivado no se puede usar');
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_nuevo_crea(''lawang'', ''Campo inventado'', ''blanco'', null, null, ''["cx_no_existe"]'')::text')) = '22023', 'C44 un campo que no esta en el catalogo se rechaza');
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_nuevo_crea(''lawang'', ''Campo sistema'', ''blanco'', null, null, ''["prom_razon"]'')::text')) = '22023', 'C45 un campo del sistema no entra por la lista de campos propios');
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_nuevo_crea(''lawang'', ''Campos mal'', ''blanco'', null, null, ''{"a":1}'')::text')) = '22023', 'C46 una lista de campos que no es lista se rechaza');
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_nuevo_crea(''lawang'', ''Campos num'', ''blanco'', null, null, ''[1,2]'')::text')) = '22023', 'C46b ... ni una lista de numeros');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_nuevo_crea(''lawang'', ''Contrato A-B'', ''blanco'')::text');
  j := case when v like 'ERR%' then null else v::jsonb end;
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_nuevo_crea(''lawang'', ''Contrato A B'', ''blanco'')::text');
  r := r || pg_temp.l(j ->> 'slug' = 'lawang_contrato_a_b' and v ~ 'lawang_contrato_a_b_2', 'C47 dos nombres que normalizan igual reciben slugs distintos (_2) (' || coalesce(j ->> 'slug', '-') || ' / ' || left(v, 60) || ')');
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_nuevo_crea(''no_existe'', ''Empresa falsa'', ''blanco'')::text')) = '42501', 'C48 una empresa que no existe se rechaza (' || 'sin alcance' || ')');

  -- tope de 30 contratos propios por empresa
  select count(*) into n from public.plantillas_contrato where empresa = 'lawang';
  insert into public.plantillas_contrato (slug, nombre, orden, cobra, archivada, empresa, campos, creada_por)
    select 'lawang_relleno_' || g, 'Relleno de prueba ' || g, 600, false, true, 'lawang', '[]'::jsonb, 'prueba' from generate_series(1, 30 - n::int) g;
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_nuevo_crea(''lawang'', ''Contrato numero treinta y uno'', ''blanco'')::text');
  r := r || pg_temp.l(pg_temp.err(v) = '54000' and v like '%30 contratos propios%', 'C49 con 30 contratos propios, el 31.o se rechaza (' || left(v, 90) || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, 'select public.plantilla_contrato_nuevo_crea(''sandal_woods'', ''Otro de SW'', ''blanco'')::text');
  r := r || pg_temp.l(v !~ '^ERR', 'C50 el tope es por empresa: Sandal Woods sigue pudiendo crear (' || left(v, 70) || ')');

  -- invariantes
  select count(*) into n from public.plantilla_contrato_versiones where origen = 'semilla' and (estado <> 'borrador' or activable);
  r := r || pg_temp.l(n = 0, 'D1 toda semilla sigue siendo borrador no activable (' || n || ' mal)');
  select count(*) into n from (select empresa, slug, variante from public.plantilla_contrato_versiones where estado = 'activa' and borrada_en is null group by 1, 2, 3 having count(*) > 1) q;
  r := r || pg_temp.l(n = 0, 'D2 nunca hay dos activas en la misma revision (' || n || ')');
  select count(*) into n from public.plantilla_contrato_versiones v join public.plantilla_contrato_cuerpos c on c.version_id = v.id where v.hash <> public._plantilla_hash(c.cuerpo_html);
  r := r || pg_temp.l(n = 0, 'D3 el hash de cada version casa con su cuerpo (' || n || ' mal)');
  select count(*) into n from public.plantillas_contrato t where t.empresa is not null and not exists (select 1 from public.plantilla_contrato_versiones v where v.slug = t.slug and v.empresa = t.empresa and v.origen = 'semilla') and t.slug not like 'lawang\_relleno\_%';
  r := r || pg_temp.l(n = 0, 'D4 todo contrato propio (salvo el relleno de la prueba) tiene su esqueleto (' || n || ' sin el)');
  select count(*) into n from public.plantilla_contrato_versiones v join public.plantillas_contrato t on t.slug = v.slug where t.empresa is not null and t.empresa <> v.empresa;
  r := r || pg_temp.l(n = 0, 'D5 ninguna version de un contrato propio es de otra empresa (' || n || ')');

  fallos := (select count(*) from regexp_matches(r, 'FALLO', 'g'));
  raise exception E'INFORME PARTES SENSIBLES + E9\n%FALLOS=%', r, fallos;
end $todo$;
