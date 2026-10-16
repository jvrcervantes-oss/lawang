-- LAW-338 L5 (16-oct-2026): el CIERRE (supabase/por_aplicar/law338_l5_revoke.sql) probado como ATAQUE, en rama y con el cierre ya puesto.
--   python erp/rama_prueba.py lawang --lawang <copia de Lawang> --aplica por_aplicar:law338_l5_revoke.sql --prueba law338_l5_ataque.sql
-- (sobre un volcado que ya trae 20261016063536; la paridad de las RPC contra la lectura directa de antes la midió el ensayo
--  lawang-202610161424-3802d033 con law338_l5_paridad.sql, y esta prueba enlaza con ella: lo que dan las RPC con el cierre = lo que dan sin él).
-- Formato de erp/pruebas/corre.py: termina en «FIN DE PRUEBAS» y cada línea acaba en «→ ok» o «→ FALLA». Todo en una transacción que
-- acaba en raise = rollback; crea funciones temporales y deshace el cierre a mitad, así que solo corre en rama.
-- Qué mide:
--  P1 ATAQUE usuario × tabla: cada sesión (usuarios activos y portal, con sus claims completas) y anon leen directo las 8 → 42501, no `[]`
--     (un `[]` sería la RLS filtrando: el cierre no estaría puesto). Se comprueba el rol EN EJECUCIÓN (current_user) en cada intento.
--     Solo vale «42501 permission denied for table|view» (revisor 16-oct): otro 42501 (una función que se niega) no es el cierre.
--  P1c LECTORES CIEGOS: el último bloque del cierre, ejecutado aquí tal cual. Sin control no salta; con un rol LOGIN nobypassrls que
--     lee clients, salta y lo nombra (si no saltase, la guarda no protegería la copia diaria en la viva).
--  P1d POLICIES CRUZADAS: el bloque de policies del cierre, ejecutado aquí tal cual. Sin control no salta; con dos policies de una tabla
--     de control que leen clients como las reescribe Postgres (esquema entre comillas, alias, subconsulta con IN; «FROM» en mayúsculas
--     en pg_policies, se comprueba), salta y nombra las dos. La versión con `~ '(from|join)\s'` no las veía (revisión previa de L6, 16-oct).
--  P2 las 11 RPC con el cierre puesto: ninguna da «permission denied for table/view» (una DEFINER que hubiese perdido la lectura) y cada
--     una devuelve algo a alguien (llenos > 0: un «igual» sobre vacíos no prueba nada).
--  P3 los roles que no son authenticated/anon y leen estas tablas (copia diaria axw_lectura, service_role, supabase_read_only_user,
--     supabase_etl_admin): con el cierre puesto cuentan las filas y saltan la RLS (estrechar las policies no les quita nada).
--  P4 la VUELTA ATRÁS de la cabecera del cierre, ejecutada aquí tal cual: authenticated vuelve a leer las 8 y las policies vuelven a sus roles.
--  P5 las 11 RPC dan EXACTAMENTE lo mismo, usuario a usuario, con el cierre y sin él (jsonb entero, errores incluidos).
--  P6 los roles de P3 cuentan lo mismo con el cierre y sin él.
-- FILAS PROPIAS: la rama de Lawang se restaura sin filas; P0 monta el mismo fixture ZZ-L5 que law338_l5_paridad.sql.
-- Los nombres de las tablas aparecen en SQL dinámico de pg_temp: no son funciones INVOKER de public.

create temp table _u (uid uuid, em text, rol text, portal boolean);
create temp table _a (fase text, k text, uid uuid, j jsonb);
create temp table _c (fase text, rol text, t text, n bigint, err text);

-- ejecuta como p_rol (authenticated por defecto) con las claims de la persona: {"v": jsonb, "__rol": rol en ejecución} o
-- {"__err": sqlstate mensaje, "__rol": …}. El rol se cambia FUERA del bloque de excepción (dentro, el error lo desharía).
create function pg_temp.q(p_uid uuid, p_em text, p_sql text, p_portal boolean default false, p_rol text default 'authenticated')
returns jsonb language plpgsql as $f$
declare r jsonb; v_rol text; v_err text;
begin
  perform set_config('request.jwt.claims', case when p_uid is null then '' else
          json_build_object('sub', p_uid, 'role', p_rol, 'email', p_em,
                            'app_metadata', json_build_object('portal', coalesce(p_portal, false)))::text end, true);
  execute format('set local role %I', p_rol);
  v_rol := current_user;
  begin execute p_sql into r;
  exception when others then v_err := sqlstate || ' ' || left(sqlerrm, 160); end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return case when v_err is null then jsonb_build_object('v', r, '__rol', v_rol)
              else jsonb_build_object('__err', v_err, '__rol', v_rol) end;
end $f$;
create function pg_temp.lleno(j jsonb) returns boolean language sql as $f$
  select case when j is null or j = 'null'::jsonb then false
              when jsonb_typeof(j) = 'array' then jsonb_array_length(j) > 0
              when jsonb_typeof(j) = 'object' then exists (select 1 from jsonb_each(j) e where e.key not like '\_\_%' and pg_temp.lleno(e.value))
              else true end
$f$;
create function pg_temp.l(c boolean, t text) returns text language sql as $f$
  select E'\n' || replace(t, E'\n', ' ') || case when coalesce(c, false) then ' → ok' else ' → FALLA' end
$f$;
-- las 11 RPC de una persona, en la fase dada
create function pg_temp.rpcs(p_fase text, u _u, fichas uuid[], k uuid, cs uuid[], f uuid) returns void language plpgsql as $f$
declare x uuid;
begin
  insert into _a values (p_fase, 'clientes_lista_datos', u.uid, pg_temp.q(u.uid, u.em, 'select public.clientes_lista_datos()', u.portal));
  foreach x in array fichas loop
    insert into _a values (p_fase, 'comprador_ficha_datos ' || x, u.uid, pg_temp.q(u.uid, u.em,
      format('select public.comprador_ficha_datos(%L, array[''ficha'',''documento'',''documentos'',''portal'',''soporte''])', x), u.portal));
    insert into _a values (p_fase, 'documentos_desactualizados_datos ' || x, u.uid, pg_temp.q(u.uid, u.em,
      format('select public.documentos_desactualizados_datos(null, %L, null)', x), u.portal));
  end loop;
  insert into _a values (p_fase, 'operacion_compradores_datos', u.uid, pg_temp.q(u.uid, u.em,
    format('select public.operacion_compradores_datos(%L, %L::uuid[])', k, cs), u.portal));
  insert into _a values (p_fase, 'operaciones_compradores_datos', u.uid, pg_temp.q(u.uid, u.em, 'select public.operaciones_compradores_datos()', u.portal));
  insert into _a values (p_fase, 'soporte_datos', u.uid, pg_temp.q(u.uid, u.em, 'select public.soporte_datos()', u.portal));
  insert into _a values (p_fase, 'notificaciones_datos', u.uid, pg_temp.q(u.uid, u.em, 'select public.notificaciones_datos(400)', u.portal));
  insert into _a values (p_fase, 'correos_registro_datos(contratos)', u.uid, pg_temp.q(u.uid, u.em,
    format('select public.correos_registro_datos(%L::uuid[], null)', array[k]), u.portal));
  insert into _a values (p_fase, 'correos_registro_datos(factura)', u.uid, pg_temp.q(u.uid, u.em,
    format('select public.correos_registro_datos(null, %L)', f), u.portal));
  insert into _a values (p_fase, 'documentos_desactualizados_datos(tipo)', u.uid, pg_temp.q(u.uid, u.em,
    'select public.documentos_desactualizados_datos(''contrato'', null, null)', u.portal));
  insert into _a values (p_fase, 'clientes_busca', u.uid, pg_temp.q(u.uid, u.em,
    'select coalesce(jsonb_agg(to_jsonb(b) order by b.id), ''[]'') from public.clientes_busca(''zz-l5'') b', u.portal));
  insert into _a values (p_fase, 'contratos_busca', u.uid, pg_temp.q(u.uid, u.em,
    'select coalesce(jsonb_agg(to_jsonb(b) order by b.id), ''[]'') from public.contratos_busca('''') b', u.portal));
  insert into _a values (p_fase, 'bot_pendientes', u.uid, pg_temp.q(u.uid, u.em,
    format('select coalesce(jsonb_agg(to_jsonb(b) order by b.ref nulls last, b.motivo), ''[]'') from public.bot_pendientes(%L) b', k), u.portal));
end $f$;
-- filas que ve cada rol de P3 (los que postgres puede adoptar en la rama; el resto se declara sin medir con su rolbypassrls)
create function pg_temp.cuenta(p_fase text, tablas text[]) returns void language plpgsql as $f$
declare r text; t text; n bigint; ns bigint[]; es text[]; i int;
begin
  foreach r in array array['axw_lectura', 'service_role', 'supabase_read_only_user', 'supabase_etl_admin'] loop
    continue when not exists (select 1 from pg_roles where rolname = r);
    -- ser miembro no basta (PG16 separa SET de la pertenencia: en la rama postgres es miembro de axw_lectura y no puede adoptarlo, ensayo
    -- lawang-202610161511-524c78db): se intenta y, si no deja, se apunta sin medir. Un SET LOCAL de un bloque que termina bien se queda.
    ns := '{}'; es := '{}';
    perform set_config('request.jwt.claims', '', true);
    begin
      execute format('set local role %I', r);
    exception when others then
      insert into _c values (p_fase, r, null, null, 'no adoptable');
      continue;
    end;
    -- con el rol ajeno puesto no se escribe en _c (es de postgres): se junta en variables y se apunta tras volver
    foreach t in array tablas loop
      n := null;
      begin
        execute format('select count(*) from public.%I', t) into n;
        es := es || null::text;
      exception when others then es := es || (sqlstate || ' ' || left(sqlerrm, 80)); end;
      ns := ns || n;
    end loop;
    execute 'reset role';
    for i in 1..cardinality(tablas) loop
      insert into _c values (p_fase, r, tablas[i], ns[i], es[i]);
    end loop;
  end loop;
end $f$;

do $todo$
declare
  u _u; t text; v jsonb; res text := ''; n_tot int; n_ok int; v_mal text; v_n int; v_g text; v_p text;
  tablas constant text[] := array['clients', 'documents', 'hilo_soporte', 'mensajes_comprador', 'portal_accesos', 'notificaciones',
                                  'correos_enviados', 'documentos_desactualizados'];
  c_emp constant text := 'zz_l5'; pL uuid; kZ uuid; hZ uuid; cA uuid; cA2 uuid; cB uuid; cB2 uuid;
  uS uuid := gen_random_uuid(); uA uuid := gen_random_uuid(); uB uuid := gen_random_uuid(); uE uuid := gen_random_uuid();
  uP uuid := gen_random_uuid(); fZ uuid := gen_random_uuid(); uM uuid := gen_random_uuid();
  eM constant text := 'zz-l5-pm@prueba.invalid';
  eS constant text := 'zz-l5-super@prueba.invalid'; eA constant text := 'zz-l5-a@prueba.invalid';
  eB constant text := 'zz-l5-b@prueba.invalid'; eE constant text := 'zz-l5-ae@prueba.invalid';
  eP constant text := 'zz-l5-portal@prueba.invalid';
  fichas uuid[]; cs uuid[];
begin
  if coalesce(current_setting('erp.en_rama', true), '') <> 'si' then
    raise exception 'FIN DE PRUEBAS LAW-338 L5 ataque:%', E'\nP0 esta prueba deshace el cierre a mitad y crea funciones temporales: solo corre en rama → FALLA';
  end if;
  perform set_config('request.jwt.claims', '', true);
  -- el cierre tiene que estar puesto: sin él P1 saldría «[]» y no 42501
  if has_table_privilege('authenticated', 'public.clients', 'select') then
    raise exception 'FIN DE PRUEBAS LAW-338 L5 ataque:%', pg_temp.l(false, 'P0 el cierre no está aplicado en la rama (authenticated lee clients): falta --aplica por_aplicar:law338_l5_revoke.sql');
  end if;

  -- ── P0 montaje del fixture propio (como postgres, sin sesión): el mismo de law338_l5_paridad.sql ─────────────────────────
  begin
    insert into public.empresas (clave, nombre) values (c_emp, 'ZZ-L5 Empresa');
    insert into public.proyectos (nombre, slug, empresa, activo) values ('ZZ-L5 Proyecto', 'zz-l5-proyecto', c_emp, true) returning id into pL;
    insert into auth.users (id, instance_id, email, aud, role) values
      (uS, '00000000-0000-0000-0000-000000000000', eS, 'authenticated', 'authenticated'),
      (uA, '00000000-0000-0000-0000-000000000000', eA, 'authenticated', 'authenticated'),
      (uB, '00000000-0000-0000-0000-000000000000', eB, 'authenticated', 'authenticated'),
      (uE, '00000000-0000-0000-0000-000000000000', eE, 'authenticated', 'authenticated'),
      (uP, '00000000-0000-0000-0000-000000000000', eP, 'authenticated', 'authenticated'),
      (uM, '00000000-0000-0000-0000-000000000000', eM, 'authenticated', 'authenticated');
    insert into public.usuarios (user_id, email, nombre, rol, ambito, empresas, proyectos, proyectos_supervisados, herramientas, tipos_contrato, activo) values
      (uS, eS, 'ZZ-L5 Super admin', 'super_admin', 'global', '{}'::text[], '{}'::uuid[], '{}'::uuid[], '{}'::text[], '{}'::text[], true),
      (uA, eA, 'ZZ-L5 Agente A', 'agente', 'global', array[c_emp], array[pL], '{}'::uuid[], '{contratos,asistente}'::text[], '{contrato_general}'::text[], true),
      (uB, eB, 'ZZ-L5 Agente B', 'agente', 'global', array[c_emp], array[pL], '{}'::uuid[], '{contratos}'::text[], '{contrato_general}'::text[], true),
      (uE, eE, 'ZZ-L5 Admin empresa', 'admin_empresa', 'empresa', array[c_emp], '{}'::uuid[], '{}'::uuid[], '{contratos}'::text[], '{}'::text[], true),
      (uM, eM, 'ZZ-L5 PM', 'project_manager', 'global', array[c_emp], '{}'::uuid[], array[pL], '{contratos}'::text[], '{}'::text[], true);
    insert into public.clients (full_name, propietario, passport_number, email, phone, address, nationality, kyc_status)
      values ('ZZ-L5 Ana de A', eA, 'ZZL5A1', 'zz-l5-ana@ejemplo.invalid', '+00 000 0101', 'ZZ-domicilio A1', 'ZZ', 'pending') returning id into cA;
    insert into public.clients (full_name, propietario, passport_number, email, phone, address, nationality)
      values ('ZZ-L5 Segundo de A', eA, 'ZZL5A2', 'zz-l5-a2@ejemplo.invalid', '+00 000 0102', 'ZZ-domicilio A2', 'ZZ') returning id into cA2;
    insert into public.clients (full_name, propietario, passport_number, email, phone, address, nationality)
      values ('ZZ-L5 Bea de B', eB, 'ZZL5B1', 'zz-l5-bea@ejemplo.invalid', '+00 000 0201', 'ZZ-domicilio B1', 'ZZ') returning id into cB;
    insert into public.clients (full_name, propietario, passport_number, email, phone, address, nationality)
      values ('ZZ-L5 Segundo de B', eB, 'ZZL5B2', 'zz-l5-b2@ejemplo.invalid', '+00 000 0202', 'ZZ-domicilio B2', 'ZZ') returning id into cB2;
    set local session_replication_role = replica;
    insert into public.sociedades (clave, label, razon, domicilio) values ('zz_l5_soc', 'ZZ-L5 Soc', 'ZZ-L5 Sociedad SA', 'ZZ-domicilio soc');
    insert into public.cuentas_bancarias (clave, label, banco, cuenta, titular, empresa)
      values ('zz_l5_cta', 'ZZ-L5 Cuenta', 'ZZ Banco', '000-L5', 'ZZ-L5 Otro Titular', c_emp);
    insert into public.contratos (numero, tipo, proyecto_id, proyecto_nombre, fecha_firma, datos, datos_fields)
      values ('ZZ-L5-001', 'contrato_general', pL, 'ZZ-L5 Proyecto', current_date,
              jsonb_build_object('fields', jsonb_build_object('cuenta_bancaria', 'zz_l5_cta', 'sociedad_firmante', 'zz_l5_soc')),
              jsonb_build_object('adq1_nombre', 'ZZ-L5 Ana Antigua', 'adq1_pasaporte', 'ZZL5A1', 'adq1_email', 'zz-l5-ana@ejemplo.invalid'))
      returning id into kZ;
    insert into public.contrato_compradores (contrato_id, client_id, rol) values (kZ, cA, 'adquiriente_1'), (kZ, cB, 'adquiriente_2');
    insert into public.documents (client_id, contrato_id, doc_type, storage_path, status, uploaded_at, caduca_el) values
      (cA, null, 'passport', 'zz-l5/a1-pasaporte.pdf', 'verified', now() - interval '3 day', current_date + 400),
      (cA, kZ, 'signed_contract', 'zz-l5/a1-contrato.pdf', 'pending', now() - interval '2 day', null),
      (cB, null, 'passport', 'zz-l5/b1-pasaporte.pdf', 'pending', now() - interval '1 day', current_date + 30),
      (cB2, null, 'npwp', 'zz-l5/b2-npwp.pdf', 'pending', now(), null);
    insert into public.portal_accesos (client_id, email, activo) values (cA, eP, true);
    insert into public.hilo_soporte (client_id, categoria, estado, contrato_id) values (cA, 'Pagos', 'abierto', kZ) returning id into hZ;
    insert into public.hilo_soporte (client_id, categoria, estado, factura_id) values (cB, 'General', 'resuelto', fZ);
    insert into public.mensajes_comprador (hilo_id, client_id, de, autor, texto, creado_en) values
      (hZ, cA, 'cliente', null, 'ZZ-L5 consulta de pago', now() - interval '1 hour'),
      (hZ, cA, 'equipo', eA, 'ZZ-L5 respuesta del equipo', now());
    insert into public.notificaciones (tipo, titulo, detalle, enlace, destinatario, contrato_id) values
      ('aviso', 'ZZ-L5 aviso para A', 'detalle A', '/v4/', eA, kZ),
      ('aviso', 'ZZ-L5 aviso para B', 'detalle B', null, eB, null),
      ('aviso', 'ZZ-L5 aviso del portal', null, null, eP, null),
      ('aviso', 'ZZ-L5 aviso general', null, null, null, null);
    insert into public.correos_enviados (para, asunto, via, enviado_por, enviado_en, contrato_id, factura_id) values
      ('zz-l5-ana@ejemplo.invalid', 'ZZ-L5 enlace de firma', 'enlace_firma', eA, now() - interval '2 hour', kZ, null),
      ('zz-l5-bea@ejemplo.invalid', 'ZZ-L5 copia', 'manual', eB, now() - interval '1 hour', kZ, null),
      ('zz-l5-bea@ejemplo.invalid', 'ZZ-L5 factura', 'factura', eS, now(), null, fZ);
    set local session_replication_role = origin;
  exception when others then
    raise exception 'FIN DE PRUEBAS LAW-338 L5 ataque (se deshace todo):%', pg_temp.l(false, 'P0 montaje del fixture propio: ' || sqlstate || ' ' || left(sqlerrm, 300));
  end;
  fichas := array[cA, cA2, cB, cB2];
  cs := array[cA, cB];

  -- quién: usuarios activos + la sesión del portal (sin ficha en usuarios)
  insert into _u select u2.user_id, u2.email, u2.rol, false from public.usuarios u2 where u2.activo;
  insert into _u values (uP, eP, 'portal', true);
  res := res || pg_temp.l((select count(*) from _u) >= 6,
    format('P0 fixture: %s sesiones (%s de portal), 4 fichas, 1 contrato con 2 compradores', (select count(*) from _u), (select count(*) from _u where portal)));

  -- ── P1 ATAQUE usuario × tabla (y anon) → 42501 ────────────────────────────────────────────────────────────────────────
  n_tot := 0; n_ok := 0; v_mal := null;
  for u in select * from _u loop
    foreach t in array tablas loop
      v := pg_temp.q(u.uid, u.em, format('select to_jsonb(count(*)) from public.%I', t), u.portal);
      n_tot := n_tot + 1;
      if coalesce(v->>'__err', '') ~ '^42501 permission denied for (table|view) ' and v->>'__rol' = 'authenticated' then n_ok := n_ok + 1;
      else v_mal := coalesce(v_mal || '; ', '') || u.rol || '×' || t || '=' || left(v::text, 60); end if;
    end loop;
  end loop;
  foreach t in array tablas loop
    v := pg_temp.q(null, null, format('select to_jsonb(count(*)) from public.%I', t), false, 'anon');
    n_tot := n_tot + 1;
    if coalesce(v->>'__err', '') ~ '^42501 permission denied for (table|view) ' and v->>'__rol' = 'anon' then n_ok := n_ok + 1;
    else v_mal := coalesce(v_mal || '; ', '') || 'anon×' || t || '=' || left(v::text, 60); end if;
  end loop;
  res := res || pg_temp.l(n_ok = n_tot and n_tot > 0, format('P1 ataque directo a las 8 (sesiones × tablas + anon): %s/%s → 42501%s', n_ok, n_tot, coalesce(' (' || left(v_mal, 300) || ')', '')));

  -- ── P1c LECTORES CIEGOS: el último bloque de law338_l5_revoke.sql, letra a letra (P4 hace lo mismo con la vuelta atrás) ──
  v_g := $g$
do $$
declare v_n int; v_lista text;
begin
  select count(*), string_agg(distinct r.rolname, ', ') into v_n, v_lista
    from pg_roles r cross join pg_class c
   where c.relnamespace = 'public'::regnamespace
     and c.relname = any(array['clients', 'documents', 'hilo_soporte', 'mensajes_comprador', 'portal_accesos', 'notificaciones',
                               'correos_enviados', 'documentos_desactualizados'])
     and r.rolcanlogin and not r.rolsuper and not r.rolbypassrls
     and not (r.oid = c.relowner and not c.relforcerowsecurity)
     and has_any_column_privilege(r.oid, c.oid, 'select');
  if v_n > 0 then
    raise exception 'L5 revoke: roles con LOGIN que leen estas tablas sin saltarse la RLS (se quedarían a cero sin error): %', v_lista;
  end if;
end $$;
$g$;
  v_mal := null;
  begin execute v_g; exception when others then v_mal := sqlstate || ' ' || sqlerrm; end;
  res := res || pg_temp.l(v_mal is null, 'P1c la guarda de lectores ciegos no salta con los roles de la rama' || coalesce(' (' || left(v_mal, 200) || ')', ''));
  v_mal := null;
  begin
    create role zz_l5_ciego login nobypassrls;
    grant select on public.clients to zz_l5_ciego;
  exception when others then v_mal := 'montaje del control: ' || sqlstate || ' ' || left(sqlerrm, 160); end;
  if v_mal is null then
    begin execute v_g; v_mal := 'no saltó';
    exception when others then
      v_mal := case when strpos(sqlerrm, 'roles con LOGIN que leen estas tablas sin saltarse la RLS') > 0
                         and sqlerrm ~ ': zz_l5_ciego$' then null else sqlstate || ' ' || sqlerrm end;
    end;
    revoke select on public.clients from zz_l5_ciego;
    drop role zz_l5_ciego;
  end if;
  res := res || pg_temp.l(v_mal is null, 'P1c con un rol LOGIN nobypassrls que lee clients, la guarda salta y lo nombra' || coalesce(' (' || left(v_mal, 200) || ')', ''));

  -- ── P1d POLICIES CRUZADAS: el bloque de policies de law338_l5_revoke.sql, letra a letra ──
  v_p := $p$
do $$
declare v_n int; v_lista text;
begin
  select count(*), string_agg(schemaname || '.' || tablename || '.' || policyname, ', ') into v_n, v_lista
    from pg_policies
   where (coalesce(qual, '') || ' ' || coalesce(with_check, ''))
         ~* '\m(clients|documents|hilo_soporte|mensajes_comprador|portal_accesos|notificaciones|correos_enviados|documentos_desactualizados)\M'
     and not (schemaname = 'public' and tablename = any(array['clients', 'documents', 'hilo_soporte', 'mensajes_comprador', 'portal_accesos',
                                                             'notificaciones', 'correos_enviados', 'documentos_desactualizados']))
     and not (schemaname = 'public' and tablename = 'cliente_notas' and policyname = 'notas: las de las fichas que ves');
  if v_n > 0 then raise exception 'L5 revoke: % policies de otras tablas o de storage consultan estas tablas: %', v_n, v_lista; end if;
end $$;
$p$;
  v_mal := null;
  begin execute v_p; exception when others then v_mal := sqlstate || ' ' || sqlerrm; end;
  res := res || pg_temp.l(v_mal is null, 'P1d la guarda de policies cruzadas no salta en la rama (solo cliente_notas, exceptuada)' || coalesce(' (' || left(v_mal, 200) || ')', ''));
  v_mal := null;
  begin
    create table public.zz_l5_cruce (id uuid);
    alter table public.zz_l5_cruce enable row level security;
    create policy "zz cruce comillas" on public.zz_l5_cruce for select to authenticated
      using (exists (select 1 from "public"."clients" c where c.id = zz_l5_cruce.id));
    create policy "zz cruce subconsulta" on public.zz_l5_cruce for select to authenticated
      using (id in (select k.id from public.clients k));
  exception when others then v_mal := 'montaje del control: ' || sqlstate || ' ' || left(sqlerrm, 160); end;
  if v_mal is null and not exists (select 1 from pg_policies where tablename = 'zz_l5_cruce' and policyname = 'zz cruce comillas'
                                                               and qual ~ 'FROM' and qual !~ 'from') then
    v_mal := 'el control no reproduce la forma guardada («FROM» en mayúsculas): ' || coalesce((select left(qual, 160) from pg_policies
              where tablename = 'zz_l5_cruce' and policyname = 'zz cruce comillas'), 'sin policy');
  end if;
  if v_mal is null then
    begin execute v_p; v_mal := 'no saltó';
    exception when others then
      v_mal := case when strpos(sqlerrm, 'policies de otras tablas o de storage consultan estas tablas') > 0
                         and strpos(sqlerrm, 'public.zz_l5_cruce.zz cruce comillas') > 0
                         and strpos(sqlerrm, 'public.zz_l5_cruce.zz cruce subconsulta') > 0 then null else sqlstate || ' ' || sqlerrm end;
    end;
  end if;
  drop table if exists public.zz_l5_cruce;
  res := res || pg_temp.l(v_mal is null, 'P1d con dos policies cruzadas como las guarda Postgres, la guarda salta y nombra las dos' || coalesce(' (' || left(v_mal, 200) || ')', ''));

  -- ── P2 las 11 RPC con el cierre puesto ────────────────────────────────────────────────────────────────────────────────
  for u in select * from _u loop perform pg_temp.rpcs('cerrado', u, fichas, kZ, cs, fZ); end loop;
  select count(*), string_agg(distinct a.k || ': ' || left(a.j->>'__err', 80), '; ') into v_n, v_mal
    from _a a where a.fase = 'cerrado' and a.j->>'__err' ~* 'permission denied for (table|view|relation)';
  res := res || pg_temp.l(v_n = 0, format('P2a ninguna RPC da «permission denied for table/view» con el cierre: %s%s', v_n, coalesce(' (' || left(v_mal, 300) || ')', '')));
  select string_agg(z.k, ', ') into v_mal from (
    select split_part(a.k, ' ', 1) k from _a a where a.fase = 'cerrado' group by 1 having not bool_or(pg_temp.lleno(a.j))) z;
  res := res || pg_temp.l(v_mal is null, 'P2b cada RPC devuelve algo a alguien con el cierre' || coalesce(' (vacías para todos: ' || v_mal || ')', ''));

  -- ── P3 los otros lectores con el cierre puesto ───────────────────────────────────────────────────────────────────────
  perform pg_temp.cuenta('cerrado', tablas);
  for v_mal in select distinct c.rol from _c c where c.fase = 'cerrado' loop
    if exists (select 1 from _c c where c.fase = 'cerrado' and c.rol = v_mal and c.err = 'no adoptable') then
      -- la rama recrea el rol a su manera (ensayo lawang-202610161519-4d9ccb13: axw_lectura sin SET para postgres y sin bypassrls, en la
      -- viva lo tiene): aquí no se puede medir; su rolbypassrls de la VIVA se mide fuera, en solo lectura, y va al informe del cierre
      res := res || E'\n' || format('P3 %s: postgres no lo puede adoptar en la rama (aquí rolbypassrls=%s) → ok (sin medir: filas; el rolbypassrls de la viva se mide con sql.py en solo lectura)',
               v_mal, (select r.rolbypassrls from pg_roles r where r.rolname = v_mal));
    else
      res := res || pg_temp.l(not exists (select 1 from _c c where c.fase = 'cerrado' and c.rol = v_mal and (c.err is not null or c.n is null))
                              and (select sum(c.n) from _c c where c.fase = 'cerrado' and c.rol = v_mal) > 0,
        format('P3 %s lee las 8 con el cierre: %s filas, errores: %s', v_mal,
               (select sum(c.n) from _c c where c.fase = 'cerrado' and c.rol = v_mal),
               coalesce((select string_agg(c.t || ' ' || c.err, '; ') from _c c where c.fase = 'cerrado' and c.rol = v_mal and c.err is not null), '0')));
    end if;
  end loop;

  -- ── P4 VUELTA ATRÁS de la cabecera del cierre, tal cual ──────────────────────────────────────────────────────────────
  grant select on public.clients, public.documents, public.hilo_soporte, public.mensajes_comprador, public.portal_accesos,
    public.notificaciones, public.correos_enviados, public.documentos_desactualizados to authenticated;
  alter policy "cada uno lo suyo, el manager lo de su proyecto, admin todo" on public.clients to authenticated, lw_lector;
  alter policy "correos: leer lo propio o del contrato visible" on public.correos_enviados to authenticated, lw_lector;
  alter policy "agentes leen documentos de sus compradores" on public.documents to authenticated, lw_lector;
  alter policy "comprador lee su estado" on public.hilo_soporte to authenticated, lw_lector;
  alter policy "equipo lee los tickets" on public.hilo_soporte to authenticated, lw_lector;
  alter policy "comprador ve su hilo de mensajes" on public.mensajes_comprador to authenticated, lw_lector;
  alter policy "equipo ve hilos de mensajes" on public.mensajes_comprador to authenticated, lw_lector;
  alter policy "cada uno ve lo suyo, el admin todo" on public.notificaciones to public;
  alter policy "agentes ven accesos del portal" on public.portal_accesos to authenticated, lw_lector;
  res := res || pg_temp.l(
    (select bool_and(has_table_privilege('authenticated', 'public.' || z, 'select')) from unnest(tablas) z)
    and (select count(*) from pg_policies p where p.schemaname = 'public' and p.tablename = any(tablas) and p.cmd in ('SELECT', 'ALL')
          and (select array_agg(x order by x) from unnest(p.roles::text[]) x)
              <> case when p.tablename = 'notificaciones' then array['public'] else array['authenticated', 'lw_lector'] end) = 0
    and (select count(*) from pg_policies p where p.schemaname = 'public' and p.tablename = any(tablas) and p.cmd in ('SELECT', 'ALL')) = 9,
    'P4 vuelta atrás: authenticated vuelve a leer las 8 y las 9 policies de lectura vuelven a sus roles de antes');
  -- tras la vuelta, el ataque de P1 ya no da 42501 (si lo diese, P1 no estaría midiendo el cierre)
  select * into u from _u w where w.rol = 'super_admin' limit 1;
  v := pg_temp.q(u.uid, u.em, 'select to_jsonb(count(*)) from public.clients', false);
  res := res || pg_temp.l(v->>'__err' is null and (v->>'v')::int >= 4, 'P4b sin el cierre el super_admin vuelve a leer clients directo (' || left(v::text, 60) || ')');

  -- ── P5 las 11 RPC sin el cierre = con el cierre ──────────────────────────────────────────────────────────────────────
  for u in select * from _u loop perform pg_temp.rpcs('abierto', u, fichas, kZ, cs, fZ); end loop;
  select count(*), string_agg(distinct split_part(a.k, ' ', 1), ', ') into v_n, v_mal
    from _a a join _a b on b.fase = 'abierto' and b.k = a.k and b.uid = a.uid
   where a.fase = 'cerrado' and a.j is distinct from b.j;
  res := res || pg_temp.l(v_n = 0 and (select count(*) from _a where fase = 'cerrado') = (select count(*) from _a where fase = 'abierto'),
    format('P5 las 11 RPC dan lo mismo con el cierre y sin él: %s llamadas, %s distintas%s', (select count(*) from _a where fase = 'cerrado'), v_n,
           coalesce(' (' || v_mal || ')', '')));

  -- ── P6 los otros lectores cuentan lo mismo con el cierre y sin él ───────────────────────────────────────────────────
  perform pg_temp.cuenta('abierto', tablas);
  select count(*) into v_n from _c a join _c b on b.fase = 'abierto' and b.rol = a.rol and b.t is not distinct from a.t
   where a.fase = 'cerrado' and (a.n is distinct from b.n or a.err is distinct from b.err);
  res := res || pg_temp.l(v_n = 0, format('P6 los otros lectores ven las mismas filas con el cierre y sin él: %s diferencias', v_n));

  raise exception 'FIN DE PRUEBAS LAW-338 L5 ataque (se deshace todo):%', res;
end $todo$;
