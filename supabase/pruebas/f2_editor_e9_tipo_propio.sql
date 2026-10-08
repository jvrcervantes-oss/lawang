-- Prueba de E9 «tipo propio emitible» (20261010040000) (8-oct-2026). Se pega DESPUES de la migracion en la MISMA peticion (ensayo sin rastro: acaba en raise y todo se deshace, migracion incluida).
-- Personas por JWT simulado, como f2_editor_partes_sensibles_e9.sql. Debe terminar con «FALLOS=0». Los contratos que crea los deshace el raise.
-- destructivo-ok: prueba en transaccion que termina en raise (rollback)
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
  select (array['ae_L', 'ae_S', 'ctl_L', 'adm_G'])[rn], user_id, email
    from (select user_id, email, row_number() over (order by email) rn
            from (select user_id, email from public.usuarios where activo and ambito = 'global' and rol = 'agente' order by email limit 4) q) z;

do $todo$
declare
  r text := ''; v text; n bigint; fallos int; nglob bigint;
  jv _t9; ae_L _t9; ae_S _t9; ctl_L _t9;
  slug_l text; slug_s text; slug_c text; vid uuid; pL uuid; pS uuid;
  base text[] := array['reserva_parcela', 'construccion', 'contrato_general', 'commercial_offer', 'carta_reserva', 'carta_reserva_ampliada', 'acuerdo_comercial', 'protocolo_operativo',
                       'ppjb_bonian', 'ppjb_bonian_c2', 'hak_sewa_notario', 'carta_reserva_hak_sewa', 'poa', 'cc00014_timon', 'carta_reserva_pma', 'adenda', 'carta_reserva_investor_deck'];
  mapa text[] := array['ppjb_parcela', 'ppjb_construccion', 'ppjb_reserva', 'commercial_offer', 'carta_reserva', 'carta_reserva_ampliada', 'commercial_collaboration', 'colaborador_operativo',
                        'ppjb_bonian', 'ppjb_bonian_c2', 'hak_sewa_notario', 'carta_reserva_hak_sewa', 'poa_notario', 'cc00014_timon', 'carta_reserva_pma', 'adenda', 'carta_reserva_investor_deck'];
  pref text[] := array['RP', 'CC', 'CG', 'CO', 'CR', 'CA', 'AC', 'PO', 'PB', 'C2', 'HS', 'CH', 'PA', 'CC', 'CP', 'AD', 'CD'];
  i int;
begin
  select * into jv from _t9 where et = 'jv'; select * into ae_L from _t9 where et = 'ae_L'; select * into ae_S from _t9 where et = 'ae_S'; select * into ctl_L from _t9 where et = 'ctl_L';
  perform set_config('request.jwt.claims', json_build_object('sub', jv.uid, 'role', 'authenticated', 'email', jv.em)::text, true);
  update public.usuarios set rol = 'admin_empresa', ambito = 'empresa', empresas = '{lawang}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{}', tipos_contrato = '{}' where user_id = ae_L.uid;
  update public.usuarios set rol = 'admin_empresa', ambito = 'empresa', empresas = '{sandal_woods}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{}', tipos_contrato = '{}' where user_id = ae_S.uid;
  update public.usuarios set rol = 'agente', ambito = 'global', empresas = '{lawang}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{}', tipos_contrato = '{}' where user_id = ctl_L.uid;
  select id into pL from public.proyectos where public.empresa_de_proyecto(id) = 'lawang' limit 1;
  select id into pS from public.proyectos where public.empresa_de_proyecto(id) = 'sandal_woods' limit 1;
  r := r || pg_temp.l(pL is not null and pS is not null, 'P0 hay proyecto de Lawang y de Sandal Woods para probar');
  select count(*) into nglob from public.plantillas_contrato where empresa is null and archivada;

  -- ============================================================ A. los 17 de siempre: cada uno se inserta, se numera con SU serie y se resuelve a SU plantilla
  for i in 1 .. 17 loop
    v := pg_temp.pg(format('insert into public.contratos (tipo, proyecto_id) values (%L, %L) returning numero', base[i], pL));
    r := r || pg_temp.l(v ~ ('^' || pref[i] || '\d{5}$') or (v ~ '^ERR' and v !~ 'Tipo de contrato|contratos_tipo_check|numeracion'), 'A1.' || i || ' ' || base[i] || ' se inserta y se numera ' || pref[i] || ' (o lo para OTRA regla de negocio: parcela/techo; nunca la de tipo) (' || left(v, 90) || ')');
    r := r || pg_temp.l(public._plantilla_slug_de_tipo(base[i]) = mapa[i], 'A2.' || i || ' ' || base[i] || ' -> ' || mapa[i]);
  end loop;
  r := r || pg_temp.l(public._plantilla_slug_de_tipo('inventado_x') is null and public._plantilla_slug_de_tipo(null) is null, 'A3 un tipo que no existe no resuelve a nada');
  r := r || pg_temp.l(pg_temp.err(pg_temp.pg(format('insert into public.contratos (tipo, proyecto_id) values (''inventado_x'', %L)', pL))) = '23514', 'A4 un tipo inventado se rechaza (trigger)');
  r := r || pg_temp.l(pg_temp.err(pg_temp.pg(format('insert into public.contratos (tipo, proyecto_id) values (''Mal Formado'', %L)', pL))) = '23514', 'A5 un tipo sin forma de slug se rechaza (CHECK)');
  r := r || pg_temp.l(pg_temp.err(pg_temp.pg(format('insert into public.contratos (tipo, proyecto_id) values (''ppjb_parcela'', %L)', pL))) = '23514', 'A6 el slug de una plantilla DEL ESTUDIO no es un tipo (solo los propios lo son)');
  r := r || pg_temp.l(pg_temp.err(pg_temp.pg('insert into public.contratos (tipo) values (''inventado_x'')')) = '23514', 'A7 sin proyecto, un tipo fuera de los 17 se rechaza');
  v := pg_temp.pg('insert into public.contratos (tipo) values (''carta_reserva'') returning numero');
  r := r || pg_temp.l(v ~ '^CR\d{5}$' or (v ~ '^ERR' and v !~ 'Tipo de contrato|contratos_tipo_check|numeracion'), 'A8 un tipo de los 17 sin proyecto sigue valiendo, como antes (' || left(v, 60) || ')');

  -- ============================================================ B. contrato propio de Lawang: se emite en su empresa y solo en ella
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_nuevo_crea(''lawang'', ''Prueba tipo propio L'', ''blanco'')::text');
  r := r || pg_temp.l(v !~ '^ERR', 'B0 el administrador de Lawang crea un contrato propio (' || left(v, 80) || ')');
  slug_l := (v::jsonb) ->> 'slug';
  select count(*) into n from public.plantillas_contrato where slug = slug_l and archivada and empresa = 'lawang';
  r := r || pg_temp.l(n = 1, 'B1 nace archivada (oculto del selector)');
  r := r || pg_temp.l(public._plantilla_slug_de_tipo(slug_l) = slug_l, 'B2 el tipo propio resuelve a su propio slug');
  v := pg_temp.pg(format('insert into public.contratos (tipo, proyecto_id) values (%L, %L) returning numero', slug_l, pL));
  r := r || pg_temp.l(v ~ '^CX\d{5}$', 'B3 se emite en un proyecto de Lawang con serie CX (' || left(v, 80) || ')');
  v := pg_temp.pg(format('insert into public.contratos (tipo, proyecto_id) values (%L, %L) returning numero', slug_l, pL));
  r := r || pg_temp.l(v ~ '^CX\d{5}$', 'B3b el siguiente tambien (' || left(v, 40) || ')');
  r := r || pg_temp.l(pg_temp.err(pg_temp.pg(format('insert into public.contratos (tipo, proyecto_id) values (%L, %L)', slug_l, pS))) = '23514', 'B4 el MISMO tipo en un proyecto de Sandal Woods se rechaza');
  r := r || pg_temp.l(pg_temp.err(pg_temp.pg(format('insert into public.contratos (tipo) values (%L)', slug_l))) = '23514', 'B5 sin proyecto (sin empresa) un tipo propio se rechaza');
  -- cambio de tipo / de proyecto sobre una fila existente
  v := pg_temp.pg(format('insert into public.contratos (tipo, proyecto_id) values (%L, %L) returning id::text', slug_l, pL));
  r := r || pg_temp.l(pg_temp.err(pg_temp.pg(format('update public.contratos set proyecto_id = %L where id = %L', pS, v))) = '23514', 'B6 mover un contrato propio a otra empresa se rechaza');
  r := r || pg_temp.l(pg_temp.err(pg_temp.pg(format('update public.contratos set tipo = ''inventado_x'' where id = %L', v))) = '23514', 'B7 cambiar su tipo a uno inexistente se rechaza');
  r := r || pg_temp.l(pg_temp.pg(format('update public.contratos set tipo = ''carta_reserva'' where id = %L returning 1', v)) = '1', 'B8 cambiarlo a uno de los 17 sigue valiendo');

  -- ============================================================ C. aislamiento: el de Sandal Woods no es de Lawang
  v := pg_temp.val(ae_S.uid, ae_S.em, 'select public.plantilla_contrato_nuevo_crea(''sandal_woods'', ''Prueba tipo propio S'', ''blanco'')::text');
  r := r || pg_temp.l(v !~ '^ERR', 'C0 Sandal Woods crea el suyo (' || left(v, 80) || ')');
  slug_s := (v::jsonb) ->> 'slug';
  r := r || pg_temp.l(pg_temp.err(pg_temp.pg(format('insert into public.contratos (tipo, proyecto_id) values (%L, %L)', slug_s, pL))) = '23514', 'C1 el tipo propio de Sandal Woods se rechaza en un proyecto de Lawang');
  v := pg_temp.pg(format('insert into public.contratos (tipo, proyecto_id) values (%L, %L) returning numero', slug_s, pS));
  r := r || pg_temp.l(v ~ '^CX\d{5}$', 'C2 ... y vale en uno de Sandal Woods (' || left(v, 60) || ')');
  r := r || pg_temp.l(pg_temp.err(pg_temp.pg(format('insert into public.contratos (tipo, proyecto_id) values (%L, %L)', slug_l, pS))) = '23514', 'C3 y el de Lawang se rechaza en Sandal Woods');

  -- ============================================================ D. activar quita `archivada`; quedarse sin activa la vuelve a poner
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ae_L.uid, ae_L.em, format('select count(*) from public.plantilla_contratos_propios_activos(%L)', 'lawang'))) is null
                      and pg_temp.val(ae_L.uid, ae_L.em, 'select count(*) from public.plantilla_contratos_propios_activos(''lawang'')') = '0', 'D0 mientras ninguno esta activo, la lista esta vacia');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select public.plantilla_contrato_nuevo_crea(''lawang'', ''Oferta propia activable'', ''copia'', ''commercial_offer'')::text');
  r := r || pg_temp.l(v !~ '^ERR', 'D1 un contrato propio copiado de uno activable (' || left(v, 80) || ')');
  slug_c := (v::jsonb) ->> 'slug'; vid := ((v::jsonb) ->> 'version_id')::uuid;
  select count(*) into n from public.plantilla_contrato_versiones where id = vid and activable;
  r := r || pg_temp.l(n = 1, 'D1b su borrador es activable');
  v := pg_temp.pg(format('update public.plantilla_contrato_versiones set estado = ''activa'', activado_por = ''prueba'', activado_en = now(), confirmacion_nombre = ''Oferta propia activable'', confirmacion_texto = ''prueba'' where id = %L returning 1', vid));
  r := r || pg_temp.l(v = '1', 'D2 se activa la version (' || left(v, 120) || ')');
  select count(*) into n from public.plantillas_contrato where slug = slug_c and not archivada;
  r := r || pg_temp.l(n = 1, 'D3 al activar, `archivada` pasa a false');
  select count(*) into n from public.plantillas_contrato where slug = slug_l and archivada;
  r := r || pg_temp.l(n = 1, 'D3b el otro propio, sin activa, sigue archivado');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select string_agg(slug || ''|'' || nombre, '','') from public.plantilla_contratos_propios_activos(''lawang'')');
  r := r || pg_temp.l(v = slug_c || '|Oferta propia activable', 'D4 la lista del selector devuelve solo el activo, con slug y nombre (' || left(v, 100) || ')');
  v := pg_temp.val(ctl_L.uid, ctl_L.em, 'select count(*) from public.plantilla_contratos_propios_activos(''lawang'')');
  r := r || pg_temp.l(v = '1', 'D5 un agente de Lawang tambien la lee (' || left(v, 60) || ')');
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ae_S.uid, ae_S.em, 'select count(*) from public.plantilla_contratos_propios_activos(''lawang'')')) = '42501', 'D6 Sandal Woods no lee la lista de Lawang');
  r := r || pg_temp.l(pg_temp.val(ae_S.uid, ae_S.em, 'select count(*) from public.plantilla_contratos_propios_activos(''sandal_woods'')') = '0', 'D6b ... y la suya esta vacia (nada activo)');
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(null, null, 'select count(*) from public.plantilla_contratos_propios_activos(''lawang'')', 'anon')) = '42501', 'D7 anon no ejecuta la RPC');
  r := r || pg_temp.l(pg_temp.err(pg_temp.val(ae_L.uid, ae_L.em, 'select count(*) from public.plantilla_contratos_propios_activos(null)')) = '42501', 'D8 empresa nula se rechaza');
  v := pg_temp.val(ae_L.uid, ae_L.em, 'select string_agg(column_name, '','' order by ordinal_position) from information_schema.routine_columns where false');
  v := pg_temp.pg(format('update public.plantilla_contrato_versiones set estado = ''retirada'', retirada_por = ''prueba'', retirada_en = now() where id = %L returning 1', vid));
  r := r || pg_temp.l(v = '1', 'D9 se retira la activa (' || left(v, 120) || ')');
  select count(*) into n from public.plantillas_contrato where slug = slug_c and archivada;
  r := r || pg_temp.l(n = 1, 'D10 al quedarse sin activa, `archivada` vuelve a true');
  r := r || pg_temp.l(pg_temp.val(ae_L.uid, ae_L.em, 'select count(*) from public.plantilla_contratos_propios_activos(''lawang'')') = '0', 'D11 y desaparece de la lista');
  select count(*) into n from public.plantillas_contrato where empresa is null and archivada;
  r := r || pg_temp.l(n = nglob, 'D12 los contratos del estudio (empresa null) no cambian su `archivada` (' || n || ' vs ' || nglob || ')');

  -- ============================================================ E. exposicion
  select count(*) into n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'plantilla_contratos_propios_activos'
     and has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('service_role', p.oid, 'execute');
  r := r || pg_temp.l(n = 1, 'E1 la RPC nueva: solo authenticated (anon y service_role no)');
  select count(*) into n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_trg_contrato_tipo_valido', '_trg_plantilla_propia_archivada', '_plantilla_slug_de_tipo')
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute'));
  r := r || pg_temp.l(n = 0, 'E2 los dos triggers nuevos y el resolvedor siguen cerrados (' || n || ' abiertos)');
  select count(*) into n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'set_contrato_numero' and not p.prosecdef;
  r := r || pg_temp.l(n = 1, 'E3 set_contrato_numero sigue SIN security definer');

  fallos := (select count(*) from regexp_matches(r, 'FALLO', 'g'));
  raise exception E'INFORME E9 TIPO PROPIO\n%FALLOS=%', r, fallos;
end $todo$;
