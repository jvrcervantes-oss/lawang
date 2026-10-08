-- Prueba de S7 «plantillas de contrato por empresa · pantalla Textos de contrato» (8-oct-2026). Se pega DESPUES de la migracion 20261009010000 en la MISMA peticion
-- (ensayo sin rastro: el bloque acaba en raise y todo se deshace). Personas por JWT simulado, como f2_plantillas_s2.sql / _s5.sql, mas un admin GLOBAL.
-- NO inserta contratos (nextval no hace rollback). NO activa nada en produccion: toda activacion de aqui se deshace. Debe terminar con «FALLOS=0».
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); los borradores y activaciones de prueba se deshacen
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
  exception when others then t := 'ERR' || sqlstate || ':' || left(sqlerrm, 160); end;
  execute 'reset role';
  return t;
end $f$;
create or replace function pg_temp.err(t text) returns text language sql immutable as $f$ select case when t like 'ERR%' then substr(t, 4, 5) end $f$;

create or replace function pg_temp.f2(p_cuerpo text, p_esq text, p_emp text, p_slug text, p_uid uuid, p_email text) returns text language plpgsql as $f$
begin  -- F2 directa (sin pasar por S3): _plantilla_exige_bloques como postgres con el JWT de la persona.
  -- 8-oct-2026 (owner): tocar un bloque fijo ya NO se rechaza; se DETECTA (_plantilla_bloques_tocados) para avisar y registrar. 'TOCA' = pasa pero toca un bloque fijo; 'OK' = no toca ninguno;
  -- 'ERR42501' = sigue rechazado (solo-global).
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'email', p_email)::text, true);
  perform public._plantilla_exige_bloques(p_cuerpo, p_esq, p_emp, p_slug);
  return case when jsonb_array_length(public._plantilla_bloques_tocados(p_cuerpo, p_esq, p_slug)) > 0 then 'TOCA' else 'OK' end;
exception when others then return 'ERR' || sqlstate;
end $f$;

insert into _t7 select 'jv', user_id, email from public.usuarios where email = 'jvr.cervantes@gmail.com';
insert into _t7
  select (array['ae_L', 'se_L', 'ae_S', 'se_S', 'ctl_L', 'adm_G'])[rn], user_id, email
    from (select user_id, email, row_number() over (order by email) rn
            from (select user_id, email from public.usuarios where activo and ambito = 'global' and rol = 'agente' order by email limit 6) q) z;

do $todo$
declare
  r text := ''; v text; n bigint; k int; fallos int; j jsonb; md_antes text; md_despues text; n_ver_antes bigint; n_ver_despues bigint;
  jv _t7; ae_L _t7; se_L _t7; ae_S _t7; se_S _t7; ctl_L _t7; adm_G _t7;
  s text; emp text; u _t7; cl text; cl2 text; pL uuid; id1 uuid; id2 uuid; id3 uuid; body text; fix text;
  fn7 text[] := array['plantilla_contrato_versiones_lista(text,text)', 'plantilla_contrato_cuerpo_version(uuid,text)', 'plantilla_contrato_guarda_borrador(text,text,text,text,text,boolean)',
                      'plantilla_contrato_activa(uuid,text,boolean)', 'plantilla_contrato_descarta_borrador(uuid)', 'plantilla_contrato_edicion(text,text,text)', 'plantilla_contrato_revisa(text,text,text,text)'];
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
  select count(*) into n_ver_antes from public.plantilla_contrato_versiones;

  -- ============================================================ A. exposicion: las 7 con llamador (esta pantalla), las demas cerradas
  select count(*) into n from unnest(fn7) x where has_function_privilege('authenticated', 'public.' || x, 'execute');
  r := r || pg_temp.l(n = 7, 'A1 authenticated ejecuta las 7 RPC de la pantalla (' || n || ')');
  select count(*) into n from unnest(fn7) x where has_function_privilege('anon', 'public.' || x, 'execute') or has_function_privilege('service_role', 'public.' || x, 'execute');
  r := r || pg_temp.l(n = 0, 'A2 anon y service_role no ejecutan ninguna de las 7 (' || n || ')');
  select count(*) into n from unnest(array['plantilla_contrato_version_de_contrato(uuid)', 'plantilla_cuerpo_valida(text,text)', 'plantilla_cuerpo_valida_semilla(text,text)', '_plantilla_sin_notas(text)',
        '_plantilla_exige_bloques(text,text,text,text)', '_plantilla_valida(text,text,boolean)', '_plantilla_esqueleto(text,text)']) x
   where has_function_privilege('authenticated', 'public.' || x, 'execute') or has_function_privilege('anon', 'public.' || x, 'execute');
  r := r || pg_temp.l(n = 0, 'A3 version_de_contrato, los validadores y los ayudantes siguen SIN EXECUTE para authenticated ni anon (' || n || ')');
  select count(*) into n from pg_proc where pronamespace = 'public'::regnamespace and proname in ('plantilla_contrato_edicion', 'plantilla_contrato_revisa', '_plantilla_sin_notas')
     and not (prosecdef and proconfig @> array['search_path=""']);
  r := r || pg_temp.l(n = 0, 'A4 las 3 funciones nuevas: SECURITY DEFINER con search_path vacio (' || n || ' mal)');
  select count(*) into n from pg_class where relname in ('plantilla_contrato_versiones', 'plantilla_contrato_cuerpos', 'contrato_plantilla_version')
     and (has_table_privilege('authenticated', oid, 'select') or has_table_privilege('authenticated', oid, 'insert') or has_table_privilege('authenticated', oid, 'update') or has_table_privilege('authenticated', oid, 'delete')
          or has_table_privilege('anon', oid, 'select'));
  r := r || pg_temp.l(n = 0, 'A5 ningun GRANT directo sobre las tablas a authenticated ni anon (' || n || ')');

  -- ============================================================ B. _plantilla_sin_notas
  v := public._plantilla_sin_notas('<p>a</p><!-- nota de autor --><!--if:tipo=x--><p>b</p><!--/if:tipo--><!--opt:cuenta--><!--/opt:cuenta--><!--hitos--><!--cuenta:UNA--><!--bloque-fijo:foro_ley--><!--/bloque-fijo:foro_ley--><!-- otra
  con salto --><p>c</p>');
  r := r || pg_temp.l(v = '<p>a</p><!--if:tipo=x--><p>b</p><!--/if:tipo--><!--opt:cuenta--><!--/opt:cuenta--><!--hitos--><!--cuenta:UNA--><!--bloque-fijo:foro_ley--><!--/bloque-fijo:foro_ley--><p>c</p>',
                      'B1 quita las notas de autor (una con salto de linea) y conserva TODOS los comentarios del motor');
  r := r || pg_temp.l(public._plantilla_sin_notas('<!--if: mal formado y largo--><p>x</p>') = '<!--if: mal formado y largo--><p>x</p>', 'B2 un comentario que empieza como el motor pero esta mal formado se queda (el validador lo rechaza por su nombre)');
  select count(*) into n from public.plantilla_contrato_versiones v join public.plantilla_contrato_cuerpos c on c.version_id = v.id
   where v.origen = 'semilla'
     and (public._plantilla_valida(public._plantilla_sin_notas(c.cuerpo_html), c.cuerpo_html, false) ->> 'ok')::boolean;
  r := r || pg_temp.l(n = 40, 'B3 las 40 semillas, sin notas, pasan el validador de cuerpos normal contra si mismas (' || n || ' de 40)');
  select count(*) into n from public.plantilla_contrato_versiones v join public.plantilla_contrato_cuerpos c on c.version_id = v.id
   where v.origen = 'semilla' and public._plantilla_sin_notas(c.cuerpo_html) ~ '<!--(?!if:|/if:|opt:|/opt:|seccion-|/seccion-|extra-clauses|firmas-adquirientes|compradores-extra|datos-bancarios|hitos|extras-construccion|cuenta:|bloque-fijo:|/bloque-fijo:)';
  r := r || pg_temp.l(n = 0, 'B4 en ninguna semilla limpia queda un comentario que no sea del motor (' || n || ')');

  -- ============================================================ C. edicion: quien puede leer el texto a editar
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_edicion(''lawang'', ''commercial_offer'')::text');
  j := case when v like 'ERR%' then null else v::jsonb end;
  r := r || pg_temp.l(j is not null and j ->> 'origen' = 'semilla' and j ->> 'empresa' = 'lawang' and j ->> 'cuerpo_html' not like '%<!-- %' and (j ->> 'notas_quitadas')::int > 0,
                      'C1 admin de Lawang: recibe la semilla v1 de su empresa SIN notas de autor (' || coalesce(j ->> 'notas_quitadas', left(v, 60)) || ' bytes quitados)');
  r := r || pg_temp.l((j ->> 'puede_activar')::boolean is false and j -> 'bloques_fijos' is not null and jsonb_array_length(j -> 'bloques_fijos') > 0 and j ->> 'solo_global' is null,
                      'C2 un admin NO puede activar, ve los bloques fijos (' || jsonb_array_length(j -> 'bloques_fijos') || ') y esta plantilla no es solo-global');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_edicion(''sandal_woods'', ''commercial_offer'')::text');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'C3 un admin de Lawang NO lee el texto a editar de Sandal Woods (' || left(v, 60) || ')');
  v := pg_temp.val(se_S.uid, se_S.em, 'select public.plantilla_contrato_edicion(''lawang'', ''commercial_offer'')::text');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'C4 y el de Sandal Woods no lee el de Lawang (' || left(v, 60) || ')');
  v := pg_temp.val(se_L.uid, se_L.em, 'select (public.plantilla_contrato_edicion(''lawang'', ''commercial_offer'')->>''puede_activar'')');
  r := r || pg_temp.l(v = 'true', 'C5 el super de Lawang SI puede activar en Lawang (' || v || ')');
  v := pg_temp.val(se_L.uid, se_L.em, 'select (public.plantilla_contrato_edicion(''sandal_woods'', ''no_existe'')->>''slug'')');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'C6 un super de Lawang no entra en Sandal Woods aunque el slug no exista (la empresa se comprueba antes) (' || left(v, 40) || ')');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, 'select public.plantilla_contrato_edicion(''lawang'', ''commercial_offer'')::text');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'C7 un agente (ni admin) no lee el texto a editar (' || left(v, 60) || ')');
  v := pg_temp.val(null, null, 'select public.plantilla_contrato_edicion(''lawang'', ''commercial_offer'')::text', 'anon');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'C8 anon no ejecuta (' || left(v, 60) || ')');
  v := pg_temp.val(gen_random_uuid(), 'portal.ajeno@example.com', 'select public.plantilla_contrato_edicion(''lawang'', ''commercial_offer'')::text');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'C9 un cliente del portal (sin ficha de agente) no lee (' || left(v, 60) || ')');
  v := pg_temp.val(jv.uid, jv.em, 'select public.plantilla_contrato_edicion(''sandal_woods'', ''estatutos_sw'')::text');
  j := case when v like 'ERR%' then null else v::jsonb end;
  r := r || pg_temp.l(j is not null and j ->> 'solo_global' is null and jsonb_array_length(j -> 'bloques_fijos') = 0 and (j ->> 'puede_activar')::boolean,
                      'C10 el super global lee las dos empresas, nada le sale bloqueado (solo_global y bloques_fijos vacios) y puede activar');
  v := pg_temp.val(ae_S.uid, ae_S.em, 'select (public.plantilla_contrato_edicion(''sandal_woods'', ''estatutos_sw'')->>''solo_global'')');
  r := r || pg_temp.l(v like 'Estatutos%', 'C11 un admin de Sandal Woods ve estatutos_sw como solo-global con su motivo (' || left(v, 40) || ')');
  v := pg_temp.val(adm_G.uid, adm_G.em, 'select (public.plantilla_contrato_edicion(''lawang'', ''commercial_offer'')->>''puede_activar'')');
  r := r || pg_temp.l(v = 'false', 'C12 un admin GLOBAL (no super) lee las dos empresas pero NO activa (' || v || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, 'select (public.plantilla_contrato_edicion(''sandal_woods'', ''cc00014_timon'')->>''nunca_activable'')');
  r := r || pg_temp.l(v is not null and v not like 'ERR%', 'C13 cc00014_timon de Sandal Woods avisa de que no es activable nunca (' || left(v, 50) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_edicion(''lawang'', ''no_existe'')::text');
  r := r || pg_temp.l(pg_temp.err(v) in ('22023', '42501'), 'C14 un slug que no existe falla con un error limpio (' || left(v, 50) || ')');

  -- ============================================================ D. el hallazgo: una empresa puede guardar su texto (las 20 plantillas x 2 empresas)
  k := 0; n := 0;
  foreach emp in array array['lawang', 'sandal_woods'] loop
    u := case when emp = 'lawang' then ae_L else ae_S end;
    for s in select distinct slug from public.plantilla_contrato_versiones order by 1 loop
      v := pg_temp.val(u.uid, u.em, format('select public.plantilla_contrato_edicion(%L, %L)->>''cuerpo_html''', emp, s));
      if v like 'ERR%' then k := k + 1; r := r || '   edicion ' || emp || ' ' || s || ' ' || left(v, 80) || E'\n'; continue; end if;
      cl := v;
      v := pg_temp.val(u.uid, u.em, format('select public.plantilla_contrato_guarda_borrador(%L, %L, %L, ''S7 sin cambios'')', emp, s, cl));
      if v like 'ERR%' then k := k + 1; r := r || '   guarda ' || emp || ' ' || s || ' ' || left(v, 100) || E'\n'; else n := n + 1; end if;
    end loop;
  end loop;
  r := r || pg_temp.l(n = 40 and k = 0, 'D1 las 40 (20 plantillas x 2 empresas): el texto de edicion se guarda tal cual como borrador del admin de su empresa (' || n || ' guardados, ' || k || ' rechazados)');
  select count(*) into n from public.plantilla_contrato_versiones where origen = 'empresa' and estado = 'borrador' and motivo = 'S7 sin cambios';
  r := r || pg_temp.l(n = 40, 'D2 hay 40 borradores de empresa nuevos, uno por plantilla y empresa (' || n || ')');
  select count(*) into n from public.plantilla_contrato_versiones v where v.motivo = 'S7 sin cambios' and v.empresa = 'sandal_woods' and not v.activable;
  r := r || pg_temp.l(n = 20, 'D3 los 20 de Sandal Woods se guardan pero NO son activables (marca de Lawang a fuego / nunca activables) (' || n || ')');
  select count(*) into n from public.plantilla_contrato_versiones v join public.plantilla_contrato_cuerpos c on c.version_id = v.id
   where v.origen = 'empresa' and v.motivo = 'S7 sin cambios' and v.hash <> public._plantilla_hash(c.cuerpo_html);
  r := r || pg_temp.l(n = 0, 'D4 el hash de cada borrador lo puso el servidor y casa con su cuerpo (' || n || ' mal)');
  -- las semillas no se tocan
  select count(*) into n from public.plantilla_contrato_versiones v join public.plantilla_contrato_cuerpos c on c.version_id = v.id
   where v.origen = 'semilla' and v.hash <> public._plantilla_hash(c.cuerpo_html);
  r := r || pg_temp.l(n = 0, 'D5 las 40 semillas v1 siguen siendo exactamente lo que eran (hash = sha256 del cuerpo) (' || n || ' mal)');

  -- ============================================================ E. revisa: el ensayo que usa la pantalla (no guarda)
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_edicion(''lawang'', ''commercial_offer'')->>''cuerpo_html''');
  body := v;
  fix := replace(body, 'acabados de alta calidad', 'acabados de calidad superior');
  r := r || pg_temp.l(fix <> body, 'E0 datos de partida: el texto libre de prueba existe en la plantilla');
  select count(*) into n_ver_antes from public.plantilla_contrato_versiones;
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_revisa(''lawang'', ''commercial_offer'', %L)::text', fix));
  j := case when v like 'ERR%' then null else v::jsonb end;
  r := r || pg_temp.l(j is not null and (j ->> 'ok')::boolean and (j ->> 'activable')::boolean and j ->> 'bloqueo' is null, 'E1 un cambio de texto libre en Lawang: ok y activable (' || left(coalesce(j::text, v), 90) || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, format('select public.plantilla_contrato_revisa(''sandal_woods'', ''commercial_offer'', %L)::text', fix));
  j := case when v like 'ERR%' then null else v::jsonb end;
  r := r || pg_temp.l(j is not null and (j ->> 'ok')::boolean and not (j ->> 'activable')::boolean and j ->> 'bloqueo' like '%otra sociedad%', 'E2 el mismo cambio en Sandal Woods: valido pero NO activable (texto de otra sociedad) y lo dice (' || left(coalesce(j ->> 'bloqueo', v), 70) || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, format('select public.plantilla_contrato_revisa(''sandal_woods'', ''commercial_offer'', %L)::text', replace(fix, 'acabados de calidad superior', 'acabados de calidad superior {{prom_cargo}}')));
  j := case when v like 'ERR%' then null else v::jsonb end;
  r := r || pg_temp.l(j is not null and (j ->> 'ok')::boolean, 'E3 anadir un marcador de la lista cerrada ({{prom_cargo}}) es valido');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_revisa(''lawang'', ''commercial_offer'', %L)::text', replace(fix, 'acabados de calidad superior', 'acabados {{no_existe_ese}}')));
  j := case when v like 'ERR%' then null else v::jsonb end;
  r := r || pg_temp.l(j is not null and not (j ->> 'ok')::boolean and j -> 'errores' ->> 0 like '%marcador desconocido%', 'E4 un marcador inventado se rechaza con su nombre (' || left(coalesce(j -> 'errores' ->> 0, v), 70) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_revisa(''lawang'', ''commercial_offer'', %L)::text', replace(fix, 'acabados de calidad superior', '<script>alert(1)</script>')));
  j := case when v like 'ERR%' then null else v::jsonb end;
  r := r || pg_temp.l(j is not null and not (j ->> 'ok')::boolean and j::text like '%script%', 'E5 <script> se rechaza (' || left(coalesce(j -> 'errores' ->> 0, v), 70) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_revisa(''lawang'', ''commercial_offer'', %L)::text', replace(fix, '<p data-lang="es">Construcci', '<table><tr><td>x</td></tr></table><p data-lang="es">Construcci')));
  j := case when v like 'ERR%' then null else v::jsonb end;
  r := r || pg_temp.l(j is not null and not (j ->> 'ok')::boolean and j::text like '%esqueleto%', 'E6 cambiar la estructura (anadir una tabla) se rechaza: el esqueleto no se toca (' || left(coalesce(j -> 'errores' ->> 0, v), 80) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_revisa(''lawang'', ''commercial_offer'', %L)::text', replace(body, 'NPWP {{prom_npwp}}', 'NPWP de {{prom_npwp}}')));
  j := case when v like 'ERR%' then null else v::jsonb end;
  r := r || pg_temp.l(j is not null and (j ->> 'ok')::boolean and (j ->> 'sensibles')::boolean and jsonb_array_length(j -> 'bloques_tocados') >= 1 and j -> 'bloques_tocados' -> 0 ->> 'motivo' is not null and j -> 'bloques_tocados' -> 0 ->> 'antes' like '%NPWP%', 'E7 tocar un bloque fijo (partes/NPWP) YA NO se rechaza para un admin de empresa: el ensayo pasa y lista el bloque tocado con su motivo (' || left(coalesce(j -> 'bloques_tocados' -> 0 ->> 'motivo', v), 60) || ')');
  v := pg_temp.val(jv.uid, jv.em, format('select public.plantilla_contrato_revisa(''lawang'', ''commercial_offer'', %L)::text', replace(body, 'NPWP {{prom_npwp}}', 'NPWP de {{prom_npwp}}')));
  j := case when v like 'ERR%' then null else v::jsonb end;
  r := r || pg_temp.l(j is not null and (j ->> 'ok')::boolean, 'E8 ... y el super GLOBAL si puede tocarlo');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, format('select public.plantilla_contrato_revisa(''lawang'', ''commercial_offer'', %L)::text', fix));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'E9 un agente no ejecuta el ensayo (' || left(v, 50) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_revisa(''sandal_woods'', ''commercial_offer'', %L)::text', fix));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'E10 un admin de Lawang no ensaya texto de Sandal Woods (' || left(v, 50) || ')');
  v := pg_temp.val(null, null, format('select public.plantilla_contrato_revisa(''lawang'', ''commercial_offer'', %L)::text', fix), 'anon');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'E11 anon no ejecuta (' || left(v, 50) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_revisa(''lawang'', ''commercial_offer'', '''')::text');
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'E12 texto vacio: 22023 (' || left(v, 50) || ')');
  select count(*) into n_ver_despues from public.plantilla_contrato_versiones;
  r := r || pg_temp.l(n_ver_antes = n_ver_despues, 'E13 revisa no guarda nada (versiones antes ' || n_ver_antes || ', despues ' || n_ver_despues || ')');

  -- ============================================================ F. lista e historial: cada empresa ve lo suyo
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select count(*) from public.plantilla_contrato_versiones_lista(''lawang'', null)');
  r := r || pg_temp.l(v::int >= 40, 'F1 el admin de Lawang lista su empresa: semillas + borradores, 20 plantillas (' || v || ' filas)');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select count(distinct empresa) from public.plantilla_contrato_versiones_lista(null, null)');
  r := r || pg_temp.l(v = '1', 'F2 y sin pedir empresa solo ve la suya (' || v || ' empresa)');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select count(*) from public.plantilla_contrato_versiones_lista(''sandal_woods'', null)');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'F3 pedir la lista de Sandal Woods: 42501 (' || left(v, 50) || ')');
  v := pg_temp.val(jv.uid, jv.em, 'select count(distinct empresa) from public.plantilla_contrato_versiones_lista(null, null)');
  r := r || pg_temp.l(v = '2', 'F4 el super global ve las dos empresas (' || v || ')');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, 'select count(*) from public.plantilla_contrato_versiones_lista(''lawang'', null)');
  r := r || pg_temp.l(v = '0', 'F5 un agente solo ve las versiones ACTIVAS (hoy ninguna): 0 filas, sin error (' || v || ')');
  v := pg_temp.val(null, null, 'select count(*) from public.plantilla_contrato_versiones_lista(''lawang'', null)', 'anon');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'F6 anon no ejecuta (' || left(v, 50) || ')');
  select v2.id into id1 from public.plantilla_contrato_versiones v2 where v2.empresa = 'lawang' and v2.slug = 'commercial_offer' and v2.origen = 'empresa' and v2.estado = 'borrador';
  select v2.id into id2 from public.plantilla_contrato_versiones v2 where v2.empresa = 'sandal_woods' and v2.slug = 'commercial_offer' and v2.origen = 'empresa' and v2.estado = 'borrador';
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select length(public.plantilla_contrato_cuerpo_version(%L)->>''cuerpo_html'')', id1));
  r := r || pg_temp.l(v ~ '^[0-9]+$' and v::int > 1000, 'F7 el admin lee el cuerpo de su borrador por id (' || v || ' caracteres)');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_cuerpo_version(%L, %L)::text', id1, (select hash from public.plantilla_contrato_versiones where id = id1)));
  r := r || pg_temp.l(v like '%sin_cambios%' and v not like '%cuerpo_html%', 'F8 con el etag al dia no reenvia el cuerpo');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_cuerpo_version(%L)::text', id2));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'F9 un admin de Lawang no lee un borrador de Sandal Woods por su id (' || left(v, 50) || ')');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, format('select public.plantilla_contrato_cuerpo_version(%L)::text', id1));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'F10 un agente no lee el borrador de la empresa (' || left(v, 50) || ')');
  v := pg_temp.val(null, null, format('select public.plantilla_contrato_cuerpo_version(%L)::text', id1), 'anon');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'F11 anon no ejecuta (' || left(v, 50) || ')');
  v := pg_temp.val(gen_random_uuid(), 'portal.ajeno@example.com', format('select public.plantilla_contrato_cuerpo_version(%L)::text', id1));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'F12 un cliente del portal no lee (' || left(v, 50) || ')');

  -- ============================================================ G. guardar y activar (todo en rollback)
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_guarda_borrador(''lawang'', ''commercial_offer'', %L, ''Cambio de redaccion del alcance'')', fix));
  r := r || pg_temp.l(v !~ '^ERR', 'G1 el admin de Lawang guarda su cambio de texto libre (' || left(v, 60) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_guarda_borrador(''lawang'', ''commercial_offer'', %L, ''  '')', fix));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'G2 sin motivo no se guarda (' || left(v, 50) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_guarda_borrador(''sandal_woods'', ''commercial_offer'', %L, ''de otra empresa'')', fix));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'G3 un admin de Lawang no guarda en Sandal Woods (' || left(v, 50) || ')');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, format('select public.plantilla_contrato_guarda_borrador(''lawang'', ''commercial_offer'', %L, ''un agente'')', fix));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'G4 un agente no guarda (' || left(v, 50) || ')');
  select v2.id into id1 from public.plantilla_contrato_versiones v2 where v2.empresa = 'lawang' and v2.slug = 'commercial_offer' and v2.origen = 'empresa' and v2.estado = 'borrador';
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_activa(%L, ''Persona de Prueba'', true)', id1));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'G5 un admin de empresa NO activa (' || left(v, 60) || ')');
  v := pg_temp.val(adm_G.uid, adm_G.em, format('select public.plantilla_contrato_activa(%L, ''Persona de Prueba'', true)', id1));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'G6 un admin global (no super) NO activa (' || left(v, 60) || ')');
  v := pg_temp.val(se_S.uid, se_S.em, format('select public.plantilla_contrato_activa(%L, ''Persona de Prueba'', true)', id1));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'G7 el super de Sandal Woods NO activa en Lawang (' || left(v, 60) || ')');
  v := pg_temp.val(se_L.uid, se_L.em, format('select public.plantilla_contrato_activa(%L, ''Persona de Prueba'', false)', id1));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'G8 sin marcar la confirmacion no se activa (' || left(v, 60) || ')');
  v := pg_temp.val(se_L.uid, se_L.em, format('select public.plantilla_contrato_activa(%L, ''ab'', true)', id1));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'G9 sin nombre no se activa (' || left(v, 60) || ')');
  v := pg_temp.val(null, null, format('select public.plantilla_contrato_activa(%L, ''Persona de Prueba'', true)', id1), 'anon');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'G10 anon no activa (' || left(v, 50) || ')');
  v := pg_temp.val(se_L.uid, se_L.em, format('select public.plantilla_contrato_activa(%L, ''Persona de Prueba'', true)', id1));
  r := r || pg_temp.l(v !~ '^ERR', 'G11 el super de Lawang activa el borrador de Lawang (ensayo, se deshace) (' || left(v, 70) || ')');
  select (estado = 'activa' and activado_por = se_L.em and confirmacion_nombre = 'Persona de Prueba' and activado_en is not null
          and confirmacion_texto like '%no sustituye a un abogado indonesio colegiado%' and confirmacion_texto like 'Responde esta empresa. El estudio no ha revisado este texto.%')
    into f from public.plantilla_contrato_versiones where id = id1;
  r := r || pg_temp.l(coalesce(f::boolean, false), 'G12 la activacion guarda quien, cuando, el nombre escrito y el texto de la confirmacion con el aviso del abogado');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_cuerpo(''commercial_offer'', ' || quote_literal(pL) || ')->>''origen''');
  r := r || pg_temp.l(v = 'empresa', 'G13 desde ese momento el generador (cuerpo) sirve el texto de la empresa, no la semilla (' || v || ')');
  begin
    update public.plantilla_contrato_cuerpos set cuerpo_html = cuerpo_html || ' ' where version_id = id1;
    r := r || pg_temp.l(false, 'G14 una version activa es inmutable (el UPDATE del cuerpo no se rechazo)');
  exception when others then r := r || pg_temp.l(true, 'G14 una version activa es inmutable: el UPDATE del cuerpo se rechaza (' || left(sqlerrm, 50) || ')'); end;
  begin
    delete from public.plantilla_contrato_versiones where id = id1;
    r := r || pg_temp.l(false, 'G15 nada se borra (el DELETE no se rechazo)');
  exception when others then r := r || pg_temp.l(true, 'G15 nada se borra: el DELETE de una version se rechaza (' || left(sqlerrm, 50) || ')'); end;
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_descarta_borrador(%L)::text', id1));
  r := r || pg_temp.l(pg_temp.err(v) = '55000', 'G16 una version activa no se descarta (' || left(v, 60) || ')');
  -- una segunda version retira la anterior; el historial conserva las dos
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_guarda_borrador(''lawang'', ''commercial_offer'', %L, ''Segundo cambio'')', replace(fix, 'calidad superior', 'calidad excelente')));
  r := r || pg_temp.l(v !~ '^ERR', 'G17 se puede guardar un segundo borrador sobre la activa (' || left(v, 60) || ')');
  select v2.id into id3 from public.plantilla_contrato_versiones v2 where v2.empresa = 'lawang' and v2.slug = 'commercial_offer' and v2.origen = 'empresa' and v2.estado = 'borrador';
  v := pg_temp.val(se_L.uid, se_L.em, format('select public.plantilla_contrato_activa(%L, ''Persona de Prueba'', true)', id3));
  select count(*) into n from public.plantilla_contrato_versiones where empresa = 'lawang' and slug = 'commercial_offer' and estado = 'activa';
  select count(*) into k from public.plantilla_contrato_versiones where empresa = 'lawang' and slug = 'commercial_offer' and estado = 'retirada' and retirada_por = se_L.em;
  r := r || pg_temp.l(v !~ '^ERR' and n = 1 and k = 1, 'G18 activar la segunda retira la primera: 1 activa, 1 retirada con su autor (' || n || '/' || k || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select count(*) from public.plantilla_contrato_versiones_lista(''lawang'', ''commercial_offer'')');
  r := r || pg_temp.l(v::int = 3, 'G19 el historial de commercial_offer en Lawang lista semilla v1 + las dos versiones de empresa, ninguna borrada (' || v || ' filas)');
  -- descartar un borrador: pasa a retirada, no se borra
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_edicion(''lawang'', ''colaborador_operativo'')->>''version_id''');
  id1 := (select v2.id from public.plantilla_contrato_versiones v2 where v2.empresa = 'lawang' and v2.slug = 'colaborador_operativo' and v2.origen = 'empresa' and v2.estado = 'borrador');
  select count(*) into n_ver_antes from public.plantilla_contrato_versiones;
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_descarta_borrador(%L)::text', id1));
  select count(*) into n_ver_despues from public.plantilla_contrato_versiones;
  r := r || pg_temp.l(v !~ '^ERR' and n_ver_antes = n_ver_despues and (select estado from public.plantilla_contrato_versiones where id = id1) = 'retirada', 'G20 descartar un borrador lo RETIRA y no borra ninguna fila (' || n_ver_antes || ' = ' || n_ver_despues || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, format('select public.plantilla_contrato_descarta_borrador(%L)::text', id1));
  r := r || pg_temp.l(pg_temp.err(v) in ('42501', '55000'), 'G21 un admin de Sandal Woods no descarta lo de Lawang (' || left(v, 40) || ')');
  -- Sandal Woods: el super NO puede activar un texto con la marca de Lawang
  select v2.id into id2 from public.plantilla_contrato_versiones v2 where v2.empresa = 'sandal_woods' and v2.slug = 'commercial_offer' and v2.origen = 'empresa' and v2.estado = 'borrador';
  v := pg_temp.val(se_S.uid, se_S.em, format('select public.plantilla_contrato_activa(%L, ''Persona de Prueba'', true)', id2));
  r := r || pg_temp.l(pg_temp.err(v) = '55000', 'G22 el super de Sandal Woods no activa un texto que nombra a otra sociedad (' || left(v, 70) || ')');
  -- el global activa en las dos
  v := pg_temp.val(jv.uid, jv.em, 'select public.plantilla_contrato_edicion(''lawang'', ''adenda'')->>''cuerpo_html''');
  v := pg_temp.val(jv.uid, jv.em, format('select public.plantilla_contrato_guarda_borrador(''lawang'', ''adenda'', %L, ''El global guarda'')', v));
  id1 := v::uuid;
  v := pg_temp.val(jv.uid, jv.em, format('select public.plantilla_contrato_activa(%L, ''Persona de Prueba'', true)', id1));
  r := r || pg_temp.l(v !~ '^ERR', 'G23 el super global guarda y activa en Lawang (' || left(v, 60) || ')');

  -- ============================================================ I. S7.2: consultas de Seguridad y Legal (alcance de empresa, div/span, poderes, reserva, REV04)
  select public._plantilla_sin_notas(public._plantilla_esqueleto('lawang', 'commercial_offer')) into fix;
  r := r || pg_temp.l(pg_temp.f2(fix, public._plantilla_esqueleto('lawang', 'commercial_offer'), 'lawang', 'commercial_offer', ae_L.uid, ae_L.em) = 'OK', 'I0 control: el esqueleto limpio de notas pasa F2 contra si mismo para el admin');
  body := fix || '<div>Propiedad Hak Milik via nominee</div><span>escrow y BPHTB</span><p>Hak Milik</p>';
  v := pg_temp.f2(body, public._plantilla_esqueleto('lawang', 'commercial_offer'), 'lawang', 'commercial_offer', ae_L.uid, ae_L.em);
  r := r || pg_temp.l(v = 'TOCA', 'I1 tenencia/escrow en div, span y p: detectado como parte sensible (' || v || ')');
  v := pg_temp.f2(fix || '<div>Propiedad Hak Milik via nominee</div>', public._plantilla_esqueleto('lawang', 'commercial_offer'), 'lawang', 'commercial_offer', ae_L.uid, ae_L.em);
  r := r || pg_temp.l(v = 'TOCA', 'I1b solo el div (antes invisible para F2): detectado (' || v || ')');
  v := pg_temp.f2(fix || '<span>escrow y BPHTB</span>', public._plantilla_esqueleto('lawang', 'commercial_offer'), 'lawang', 'commercial_offer', ae_L.uid, ae_L.em);
  r := r || pg_temp.l(v = 'TOCA', 'I1c solo el span: detectado (' || v || ')');
  v := pg_temp.f2(fix || '<div>Hak <span>Milik</span> con <strong>nomi</strong>nee</div>', public._plantilla_esqueleto('lawang', 'commercial_offer'), 'lawang', 'commercial_offer', ae_L.uid, ae_L.em);
  r := r || pg_temp.l(v = 'TOCA', 'I1d partido por etiquetas en linea (Hak <span>Milik</span>): detectado (' || v || ')');
  v := pg_temp.f2(fix || 'Hak&nbsp;Milik suelto', public._plantilla_esqueleto('lawang', 'commercial_offer'), 'lawang', 'commercial_offer', ae_L.uid, ae_L.em);
  r := r || pg_temp.l(v = 'TOCA', 'I1e texto suelto con &nbsp;: detectado (' || v || ')');
  v := pg_temp.f2(fix || '<p>El comprador otorga poder notarial irrevocable al vendedor</p>', public._plantilla_esqueleto('lawang', 'commercial_offer'), 'lawang', 'commercial_offer', ae_L.uid, ae_L.em);
  r := r || pg_temp.l(v = 'TOCA', 'I2 poder notarial irrevocable: detectado (' || v || ')');
  foreach f in array array['<p>kuasa mutlak</p>', '<p>power of attorney</p>', '<p>un apoderado</p>', '<p>sociedad fiduciaria</p>', '<p>titular registral</p>', '<p>a nombre de tercero</p>', '<p>atas nama pihak lain</p>'] loop
    v := pg_temp.f2(fix || f, public._plantilla_esqueleto('lawang', 'commercial_offer'), 'lawang', 'commercial_offer', ae_L.uid, ae_L.em);
    r := r || pg_temp.l(v = 'TOCA', 'I2b ' || f || ' -> ' || v);
  end loop;
  foreach f in array array['<p>El plazo de la reserva es de 90 dias</p>', '<span>reservation period</span>', '<div>masa reservasi</div>', '<p>plazo de reserva</p>'] loop
    v := pg_temp.f2(fix || f, public._plantilla_esqueleto('lawang', 'commercial_offer'), 'lawang', 'commercial_offer', ae_L.uid, ae_L.em);
    r := r || pg_temp.l(v = 'TOCA', 'I3 plazo de reserva ' || f || ' -> ' || v);
  end loop;
  v := pg_temp.f2(fix || '<div>Texto libre sin ningun tema reservado</div>', public._plantilla_esqueleto('lawang', 'commercial_offer'), 'lawang', 'commercial_offer', ae_L.uid, ae_L.em);
  r := r || pg_temp.l(v = 'OK', 'I4 un div de texto libre no se confunde con un bloque fijo (' || v || ')');
  v := pg_temp.f2(body, public._plantilla_esqueleto('lawang', 'commercial_offer'), 'lawang', 'commercial_offer', jv.uid, jv.em);
  r := r || pg_temp.l(v = 'TOCA', 'I5 el super GLOBAL pasa el validador aunque toque bloques fijos (' || v || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select public.plantilla_contrato_revisa(''lawang'', ''commercial_offer'', %L)::text', fix || '<p>Se nombra un apoderado</p>'));
  j := case when v like 'ERR%' then null else v::jsonb end;
  r := r || pg_temp.l(j is not null and (j ->> 'ok')::boolean and (j ->> 'sensibles')::boolean, 'I6 de punta a punta (revisa): una palabra de poderes en un parrafo libre pasa y se marca como parte sensible (' || left(coalesce(j -> 'bloques_tocados' -> 0 ->> 'motivo', v), 50) || ')');
  -- alcance entre empresas: id1 = la adenda de Lawang que el global activo en G23
  v := pg_temp.val(ae_S.uid, ae_S.em, format('select public.plantilla_contrato_cuerpo_version(%L)::text', id1));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'I7 un admin de Sandal Woods no lee por id un texto ACTIVO de Lawang (' || left(v, 40) || ')');
  v := pg_temp.val(se_S.uid, se_S.em, format('select public.plantilla_contrato_cuerpo_version(%L)::text', id1));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'I7b ni su super (' || left(v, 40) || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, 'select count(*) from public.plantilla_contrato_versiones_lista(null, null) where empresa = ''lawang''');
  r := r || pg_temp.l(v = '0', 'I8 la lista sin empresa de Sandal Woods no trae versiones activas de Lawang (' || v || ')');
  v := pg_temp.val(ae_S.uid, ae_S.em, 'select count(*) from public.plantilla_contrato_versiones_lista(''lawang'', ''adenda'')');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'I8b pedirla con la empresa: 42501 (' || left(v, 40) || ')');
  v := pg_temp.val(ae_L.uid, ae_L.em, format('select length(public.plantilla_contrato_cuerpo_version(%L)->>''cuerpo_html'')', id1));
  r := r || pg_temp.l(v ~ '^[0-9]+$' and v::int > 1000, 'I9 el admin de Lawang sigue leyendo su texto activo (' || v || ')');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, format('select length(public.plantilla_contrato_cuerpo_version(%L)->>''cuerpo_html'')', id1));
  r := r || pg_temp.l(v ~ '^[0-9]+$', 'I9b y un agente de Lawang lee el ACTIVO de su empresa (' || v || ')');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, 'select count(*) from public.plantilla_contrato_versiones_lista(null, null) where estado = ''activa''');
  r := r || pg_temp.l(v ~ '^[0-9]+$' and v::int >= 1, 'I9c el agente ve las activas de su empresa en la lista (' || v || ')');
  v := pg_temp.val(null, null, format('select public.plantilla_contrato_cuerpo_version(%L)::text', id1), 'anon');
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'I10 anon: 42501');
  v := pg_temp.val(gen_random_uuid(), 'portal.ajeno@example.com', format('select public.plantilla_contrato_cuerpo_version(%L)::text', id1));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'I10b portal: 42501');
  v := pg_temp.val(jv.uid, jv.em, 'select count(distinct empresa) from public.plantilla_contrato_versiones_lista(null, null)');
  r := r || pg_temp.l(v = '2', 'I10c el super global sigue viendo las dos empresas (' || v || ')');
  -- REV04: ppjb_parcela y ppjb_construccion
  foreach s in array array['ppjb_parcela', 'ppjb_construccion'] loop
    foreach emp in array array['lawang', 'sandal_woods'] loop
      u := case when emp = 'lawang' then ae_L else ae_S end;
      v := pg_temp.val(u.uid, u.em, format('select concat_ws(''/'', public.plantilla_contrato_edicion(%L, %L)->>''solo_global'', public.plantilla_contrato_edicion(%L, %L)->>''nunca_activable'')', emp, s, emp, s));
      r := r || pg_temp.l(v like '%REV04%/%REV04%', 'I11 ' || emp || ' ' || s || ': el admin ve solo-global y nunca-activable con su motivo');
      cl := pg_temp.val(u.uid, u.em, format('select public.plantilla_contrato_edicion(%L, %L)->>''cuerpo_html''', emp, s));
      v := pg_temp.val(u.uid, u.em, format('select public.plantilla_contrato_guarda_borrador(%L, %L, %L, ''cambio de texto'')', emp, s, regexp_replace(cl, '</p>', ' extra</p>')));
      r := r || pg_temp.l(pg_temp.err(v) = '42501', 'I12 ' || emp || ' ' || s || ': un cambio de texto del admin se rechaza (solo global) (' || left(v, 30) || ')');
      v := pg_temp.val(u.uid, u.em, format('select public.plantilla_contrato_guarda_borrador(%L, %L, %L, ''igual al esqueleto'')', emp, s, cl));
      r := r || pg_temp.l(v !~ '^ERR', 'I13 ' || emp || ' ' || s || ': el texto identico al esqueleto se guarda como borrador (' || left(v, 30) || ')');
      select (not activable and bloqueo_motivo like '%REV04%')::text into f from public.plantilla_contrato_versiones where empresa = emp and slug = s and origen = 'empresa' and estado = 'borrador';
      r := r || pg_temp.l(coalesce(f::boolean, false), 'I14 ' || emp || ' ' || s || ': ese borrador queda NO activable por REV04');
    end loop;
    select v2.id into id2 from public.plantilla_contrato_versiones v2 where v2.empresa = 'lawang' and v2.slug = s and v2.origen = 'empresa' and v2.estado = 'borrador';
    v := pg_temp.val(se_L.uid, se_L.em, format('select public.plantilla_contrato_activa(%L, ''Persona de Prueba'', true)', id2));
    r := r || pg_temp.l(pg_temp.err(v) = '55000', 'I15 ' || s || ': el super de Lawang no activa una copia identica al esqueleto (' || left(v, 40) || ')');
    v := pg_temp.val(jv.uid, jv.em, format('select public.plantilla_contrato_activa(%L, ''Persona de Prueba'', true)', id2));
    r := r || pg_temp.l(pg_temp.err(v) = '55000', 'I15b ni el super global (nunca activable hasta que Legal reclasifique) (' || left(v, 40) || ')');
  end loop;
  select count(*) into n from public.plantilla_solo_global where slug in ('ppjb_parcela', 'ppjb_construccion');
  select count(*) into k from public.plantilla_nunca_activable where slug in ('ppjb_parcela', 'ppjb_construccion');
  r := r || pg_temp.l(n = 2 and k = 4, 'I16 politica REV04: 2 solo-global y 4 nunca-activables (' || n || '/' || k || ')');
  -- medida informativa: bloques fijos por tipo en las 40 semillas (R = residuo div/span/suelto)
  select count(*) filter (where b like 'R|%'), count(*) filter (where b like 'E|%'), count(*) filter (where b like 'S|%'), count(distinct v.id) filter (where b like 'R|%')
    into n, k, cl2, cl
    from public.plantilla_contrato_versiones v join public.plantilla_contrato_cuerpos c on c.version_id = v.id
         cross join lateral unnest(public._plantilla_bloques_fijos(public._plantilla_sin_notas(c.cuerpo_html), v.slug)) b
   where v.origen = 'semilla';
  r := r || 'INFO  bloques fijos en las 40 semillas: R=' || n || ' (en ' || cl || ' semillas) E=' || k || ' S=' || cl2 || E'\n';

  -- ============================================================ H. contratos intactos y nada fuera de lo previsto
  select md5(string_agg(c::text, '|' order by c.id)) into md_despues from public.contratos c;
  r := r || pg_temp.l(md_antes = md_despues, 'H1 las filas de contratos son byte a byte las mismas antes y despues');
  select count(*) into n from pg_trigger where tgrelid = 'public.contratos'::regclass and not tgisinternal and tgname ilike '%plantilla%';
  r := r || pg_temp.l(n = 0, 'H2 ningun trigger de plantillas en contratos (' || n || ')');
  select count(*) into n from information_schema.columns where table_name = 'contratos' and column_name ilike '%plantilla%';
  r := r || pg_temp.l(n = 0, 'H3 ninguna columna de plantillas en contratos (' || n || ')');
  select count(*) into n from public.contrato_plantilla_version where fijado_por <> 'S5 carga inicial';
  r := r || pg_temp.l(n = 0, 'H4 ningun vinculo contrato-version nuevo: esta pantalla no fija versiones (' || n || ' fuera de los de S5)');

  fallos := (select count(*) from regexp_matches(r, 'FALLO', 'g'));
  raise exception E'INFORME S7\n%FALLOS=%', r, fallos;
end $todo$;
