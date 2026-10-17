-- LAW-338 L5 (16-oct-2026): PARIDAD de las 8 lecturas nuevas contra la lectura directa de hoy, usuario a usuario, con el rol real.
-- Migración: 20261016063536_law338_l5_compradores_datos.sql. Revisión previa #396 (Seguridad 2 y 3, Backend 4 y 5).
--   python erp/rama_prueba.py lawang --lawang <copia de Lawang> --aplica 20261016063536_law338_l5_compradores_datos.sql --prueba law338_l5_paridad.sql
-- DESDE EL REVOKE (18-oct, ensayo 13f3f2c9 de la 200000: 15 P1, P4b y P5b en rojo por «42501 permission denied for table …» de la
-- lectura directa, no de las RPC): 20261016112502_law338_l5_revoke (viva desde el 16-oct; posterior al volcado 1859, así que va en
-- --aplica) quita a authenticated la lectura de las 8. La referencia de P1 y P5b se lee ahora como lw_lector con las mismas claims
-- (mismo cuerpo de policy que tenía authenticated) y cada caso exige además que authenticated leyendo directo dé 42501. Sin la
-- 112502 aplicada, P1 sale «ABIERTA».
-- Formato de erp/pruebas/corre.py: termina en «FIN DE PRUEBAS» y cada línea acaba en «→ ok» o «→ FALLA». Solo LEE (todo en una
-- transacción que acaba en raise = rollback); va en rama porque crea funciones temporales y las RPC aún no están en la viva.
-- Qué mide:
--  P1 por cada usuario ACTIVO de `usuarios` y por cada sesión de PORTAL (correos de portal_accesos activos y destinatarios de
--     notificaciones sin ficha en `usuarios`), como `authenticated` con las claims COMPLETAS (sub, role, email: 4 de las 7 tablas
--     filtran por auth.email(); sin él todo sale a cero y la paridad saldría verde sin comparar nada), el jsonb ENTERO de cada RPC
--     (contenido, no solo ids: un cruce conserva los ids y cambia el pasaporte) contra el mismo jsonb armado con la lectura directa.
--     Una línea por comprobación: «dif» = usuarios con respuesta distinta; «llenos» = usuarios con algo dentro (tiene que ser > 0:
--     una paridad sobre vacíos no prueba nada); «err» = errores.
--  P2 ve=false: algún agente pide una ficha que no ve y no recibe ninguna parte (Seguridad #396.2).
--  P3 sin sesión → 42501 en las 8 y en clientes_busca; anon y service_role sin EXECUTE en las 11 (proacl).
--  P4 clientes_busca: `%@%` no lista nada; el correo exacto de una ficha visible la encuentra; sin la herramienta del asistente, 42501.
--  P5 contratos_busca y bot_pendientes como authenticated (DEFINER-lw_lector) dan lo mismo que su cuerpo leído directo.
--  P6 tiempo de documentos_desactualizados_datos por cliente y por id: 7 llamadas seguidas (la 6.ª ya puede ir con plan genérico).
-- Los nombres de las tablas aparecen en SQL dinámico de pg_temp: no son funciones INVOKER de public.
-- FILAS PROPIAS (16-oct): la rama de Lawang se restaura SIN filas (rama_prueba: «cada prueba de Lawang trae sus filas»), así
-- que P0 monta un fixture ZZ-L5 como postgres: empresa, proyecto, 5 usuarios (super_admin, agente A con el asistente, agente B
-- sin él, admin_empresa y una sesión de portal), 4 fichas (2 de A, 2 de B), un contrato con dos compradores y datos de comprador
-- que difieren de la ficha (fila en documentos_desactualizados), documentos, acceso al portal, hilo con mensajes, avisos y
-- correos. Contratos, documentos, soporte, avisos y correos se siembran con session_replication_role = replica (sin los ~40
-- disparadores del contrato ni las claves ajenas de factura: lo que se prueba es la LECTURA); usuarios y fichas, con sus
-- disparadores (numero_usuario y numero_cliente salen de ellos).

create temp table _u (uid uuid, em text, rol text, portal boolean);
create temp table _r (chk text, uid uuid, ok boolean, lleno boolean, err text);
create temp table _s (k text, v uuid, vs uuid[]);

-- ejecuta como authenticated con las claims de la persona: el jsonb o {"__err": sqlstate}
-- p_portal: la sesión del portal lleva app_metadata.portal=true en el JWT (es_portal() lo lee), como el token real
-- p_rol: el rol de base de datos (las claims siguen siendo las de authenticated); lw_lector solo para la lectura de referencia
create function pg_temp.q(p_uid uuid, p_em text, p_sql text, p_portal boolean default false, p_rol text default 'authenticated') returns jsonb language plpgsql as $f$
declare r jsonb;
begin
  perform set_config('request.jwt.claims', case when p_uid is null then '' else
          json_build_object('sub', p_uid, 'role', 'authenticated', 'email', p_em,
                            'app_metadata', json_build_object('portal', coalesce(p_portal, false)))::text end, true);
  execute format('set local role %I', p_rol);
  begin execute p_sql into r;
  exception when others then r := jsonb_build_object('__err', sqlstate || ' ' || left(sqlerrm, 160)); end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return r;
end $f$;
create function pg_temp.lleno(j jsonb) returns boolean language sql as $f$
  select case when j is null or j = 'null'::jsonb then false
              when jsonb_typeof(j) = 'array' then jsonb_array_length(j) > 0
              when jsonb_typeof(j) = 'object' then exists (select 1 from jsonb_each(j) e where pg_temp.lleno(e.value))
              else true end
$f$;
-- compara directo vs RPC para un usuario. Desde 20261016112502 (L5 revoke, viva) authenticated ya no lee estas tablas: la lectura
-- de referencia va como lw_lector con las MISMAS claims (las policies pasaron a «to lw_lector» con el cuerpo que tenían para
-- authenticated: lo que la persona veía antes del revoke), y además authenticated leyendo directo tiene que dar 42501.
-- p_cerrada = false solo donde la lectura directa nombra tablas que siguen abiertas (contratos_busca lee contratos).
create function pg_temp.par(p_chk text, u _u, p_dir text, p_rpc text, p_cerrada boolean default true) returns void language plpgsql as $f$
declare d jsonb; r jsonb; a jsonb;
begin
  d := pg_temp.q(u.uid, u.em, p_dir, u.portal, case when p_cerrada then 'lw_lector' else 'authenticated' end);
  r := pg_temp.q(u.uid, u.em, p_rpc, u.portal);
  if p_cerrada then a := pg_temp.q(u.uid, u.em, p_dir, u.portal); end if;
  insert into _r values (p_chk, u.uid, d is not distinct from r, pg_temp.lleno(r),
                         coalesce('directo ' || (d->>'__err'), 'rpc ' || (r->>'__err'),
                                  case when p_cerrada and coalesce(a->>'__err', '') not like '42501%'
                                       then 'ABIERTA: authenticated lee directo sin 42501' end));
end $f$;
create function pg_temp.l(c boolean, t text) returns text language sql as $f$
  select E'\n' || replace(t, E'\n', ' ') || case when coalesce(c, false) then ' → ok' else ' → FALLA' end
$f$;

do $todo$
declare
  u _u; x uuid; k uuid; ks uuid[]; cs uuid[]; f uuid; res text := ''; v jsonb; t0 timestamptz; ms int[] := '{}';
  v_chk text; n_u int; dif int; llenos int; errs int; agente _u; nove uuid; fichas uuid[];
  fdd uuid; em_x text;
  c_emp constant text := 'zz_l5'; pL uuid; kZ uuid; hZ uuid; cA uuid; cA2 uuid; cB uuid; cB2 uuid;
  uS uuid := gen_random_uuid(); uA uuid := gen_random_uuid(); uB uuid := gen_random_uuid(); uE uuid := gen_random_uuid();
  uP uuid := gen_random_uuid(); fZ uuid := gen_random_uuid(); uM uuid := gen_random_uuid();
  eM constant text := 'zz-l5-pm@prueba.invalid';
  eS constant text := 'zz-l5-super@prueba.invalid'; eA constant text := 'zz-l5-a@prueba.invalid';
  eB constant text := 'zz-l5-b@prueba.invalid'; eE constant text := 'zz-l5-ae@prueba.invalid';
  eP constant text := 'zz-l5-portal@prueba.invalid';
  DOCF constant text := 'jsonb_build_object(''id'', d.id, ''doc_type'', d.doc_type, ''storage_path'', d.storage_path, ''uploaded_at'', d.uploaded_at, ''caduca_el'', d.caduca_el)';
begin
  if coalesce(current_setting('erp.en_rama', true), '') <> 'si' then
    raise exception 'FIN DE PRUEBAS LAW-338 L5:%', E'\nP0 esta prueba crea funciones temporales: solo corre en rama → FALLA';
  end if;
  perform set_config('request.jwt.claims', '', true);

  -- ── P0 montaje del fixture propio (como postgres, sin sesión) ─────────────────────────────────────────────────────────
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
    -- A con el asistente (busca clientes), B sin él (P4c); el admin de empresa ve por la empresa de quien es dueño de la ficha
    insert into public.usuarios (user_id, email, nombre, rol, ambito, empresas, proyectos, proyectos_supervisados, herramientas, tipos_contrato, activo) values
      (uS, eS, 'ZZ-L5 Super admin', 'super_admin', 'global', '{}'::text[], '{}'::uuid[], '{}'::uuid[], '{}'::text[], '{}'::text[], true),
      (uA, eA, 'ZZ-L5 Agente A', 'agente', 'global', array[c_emp], array[pL], '{}'::uuid[], '{contratos,asistente}'::text[], '{contrato_general}'::text[], true),
      (uB, eB, 'ZZ-L5 Agente B', 'agente', 'global', array[c_emp], array[pL], '{}'::uuid[], '{contratos}'::text[], '{contrato_general}'::text[], true),
      (uE, eE, 'ZZ-L5 Admin empresa', 'admin_empresa', 'empresa', array[c_emp], '{}'::uuid[], '{}'::uuid[], '{contratos}'::text[], '{}'::text[], true),
      -- el manager: la rama «el manager lo de su proyecto» de la RLS (supervisa el proyecto del contrato)
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
    -- LAW-124 de bot_pendientes: la cuenta de cobro a nombre de otro que la sociedad firmante (lee sociedades.clave/razon: el grant de columnas)
    insert into public.sociedades (clave, label, razon, domicilio) values ('zz_l5_soc', 'ZZ-L5 Soc', 'ZZ-L5 Sociedad SA', 'ZZ-domicilio soc');
    insert into public.cuentas_bancarias (clave, label, banco, cuenta, titular, empresa)
      values ('zz_l5_cta', 'ZZ-L5 Cuenta', 'ZZ Banco', '000-L5', 'ZZ-L5 Otro Titular', c_emp);
    -- contrato de A con dos compradores; el adquiriente_1 firmó con otro nombre → fila de documentos_desactualizados
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
    raise exception 'FIN DE PRUEBAS LAW-338 L5 (se deshace todo):%', pg_temp.l(false, 'P0 montaje del fixture propio: ' || sqlstate || ' ' || left(sqlerrm, 300));
  end;

  -- ── quién: usuarios activos + sesiones de portal (sin ficha en usuarios) ─────────────────────────────────────────────
  insert into _u select u2.user_id, u2.email, u2.rol, false from public.usuarios u2 where u2.activo;
  insert into _u
    select coalesce((select au.id from auth.users au where lower(au.email) = e.em limit 1), gen_random_uuid()), e.em, 'portal', true
      from (select distinct lower(pa.email) em from public.portal_accesos pa where pa.activo
            union select distinct lower(n.destinatario) from public.notificaciones n
             where n.destinatario is not null and not exists (select 1 from public.usuarios u3 where lower(u3.email) = lower(n.destinatario))) e
     limit 8;

  -- ── muestras (como postgres): fichas con documentos, con portal, con soporte y una cualquiera; un contrato con compradores;
  --    contratos y una factura con correos ───────────────────────────────────────────────────────────────────────────────
  select array_agg(distinct z) into fichas from (
    (select d.client_id z from public.documents d where d.client_id is not null and d.retirado_el is null order by d.uploaded_at desc nulls last limit 3)
    union all (select pa.client_id from public.portal_accesos pa order by pa.creado_en desc limit 2)
    union all (select h.client_id from public.hilo_soporte h order by h.actualizado_en desc limit 1)
    union all (select c.id from public.clients c order by c.created_at limit 2)) s;
  select cc.contrato_id into k from public.contrato_compradores cc
   where exists (select 1 from public.documents d where d.client_id = cc.client_id) order by cc.contrato_id limit 1;
  select coalesce((select d.client_id from public.documentos_desactualizados d where d.client_id = any(fichas)
                     and jsonb_typeof(d.diferencias) = 'array' and jsonb_array_length(d.diferencias) > 0 limit 1), fichas[1]) into fdd;
  select array_agg(cc.client_id order by cc.client_id) into cs from public.contrato_compradores cc where cc.contrato_id = k;
  select array_agg(z) into ks from (select distinct e.contrato_id z from public.correos_enviados e where e.contrato_id is not null limit 4) s;
  select e.factura_id into f from public.correos_enviados e where e.factura_id is not null order by e.enviado_en desc limit 1;
  res := res || pg_temp.l(cardinality(fichas) >= 4 and k is not null and cardinality(ks) >= 1 and f is not null,
    format('P0 muestras: %s fichas, contrato con compradores %s, %s contratos y 1 factura con correos, %s sesiones (%s de portal)',
           cardinality(fichas), k is not null, cardinality(ks), (select count(*) from _u), (select count(*) from _u where portal)));

  -- ── P1 paridad ────────────────────────────────────────────────────────────────────────────────────────────────────────
  for u in select * from _u loop
    perform pg_temp.par('clientes_lista', u,
      'select coalesce(jsonb_agg(jsonb_build_object(''id'', c.id, ''full_name'', c.full_name) order by c.full_name, c.id), ''[]'') from public.clients c',
      'select public.clientes_lista_datos()->''clientes''');
    perform pg_temp.par('clientes_lista(ids)', u,
      format('select coalesce(jsonb_agg(jsonb_build_object(''id'', c.id, ''full_name'', c.full_name) order by c.full_name, c.id), ''[]'') from public.clients c where c.id = any(%L::uuid[])', fichas),
      format('select public.clientes_lista_datos(%L::uuid[])->''clientes''', fichas));
    foreach x in array fichas loop
      perform pg_temp.par('ficha', u,
        format('select jsonb_build_object(''ve'', exists (select 1 from public.clients c where c.id = %1$L), ''ficha'', (select jsonb_build_object(''id'', c.id, ''numero_cliente'', c.numero_cliente, ''full_name'', c.full_name, ''email'', c.email, ''phone'', c.phone, ''nationality'', c.nationality, ''passport_number'', c.passport_number, ''tipo'', c.tipo, ''forma_juridica'', c.forma_juridica, ''registro_num'', c.registro_num, ''rep_nombre'', c.rep_nombre, ''rep_cargo'', c.rep_cargo, ''kyc_status'', c.kyc_status, ''idioma_comunicacion'', c.idioma_comunicacion, ''propietario'', c.propietario, ''created_at'', c.created_at) from public.clients c where c.id = %1$L))', x),
        format('select jsonb_build_object(''ve'', r->''ve'', ''ficha'', r->''ficha'') from (select public.comprador_ficha_datos(%L, array[''ficha'']) r) s', x));
      perform pg_temp.par('documento', u,
        format('select (select jsonb_build_object(''id'', c.id, ''full_name'', c.full_name, ''email'', c.email, ''passport_number'', c.passport_number, ''registro_num'', c.registro_num, ''address'', c.address) from public.clients c where c.id = %L)', x),
        format('select public.comprador_ficha_datos(%L, array[''documento''])->''documento''', x));
      perform pg_temp.par('documentos', u,
        format('select coalesce(jsonb_agg(%s order by d.uploaded_at desc nulls last, d.id desc), ''[]'') from public.documents d where d.client_id = %L', DOCF, x),
        format('select coalesce(public.comprador_ficha_datos(%L, array[''documentos''])->''documentos'', ''[]'')', x));
      perform pg_temp.par('portal', u,
        format('select coalesce(jsonb_agg(jsonb_build_object(''email'', p.email, ''activo'', p.activo, ''ultimo_acceso'', p.ultimo_acceso, ''accesos'', p.accesos) order by p.creado_en, p.id), ''[]'') from public.portal_accesos p where p.client_id = %L', x),
        format('select coalesce(public.comprador_ficha_datos(%L, array[''portal''])->''portal'', ''[]'')', x));
      -- soporte: solo cuando ve la ficha (con ve=false la RPC no da partes a propósito: P2)
      perform pg_temp.par('soporte', u,
        format('select case when exists (select 1 from public.clients c where c.id = %1$L) then jsonb_build_object(''ultimo'', (select jsonb_build_object(''de'', m.de, ''texto'', m.texto, ''creado_en'', m.creado_en) from public.mensajes_comprador m where m.client_id = %1$L order by m.creado_en desc, m.id desc limit 1), ''hilos'', (select coalesce(jsonb_agg(jsonb_build_object(''estado'', h.estado, ''actualizado_en'', h.actualizado_en) order by h.actualizado_en desc, h.id desc), ''[]'') from public.hilo_soporte h where h.client_id = %1$L)) end', x),
        format('select public.comprador_ficha_datos(%L, array[''soporte''])->''soporte''', x));
    end loop;
    perform pg_temp.par('operacion_compradores', u,
      format('select jsonb_build_object(''clientes'', (select coalesce(jsonb_agg(jsonb_build_object(''id'', c.id, ''full_name'', c.full_name, ''kyc_status'', c.kyc_status) order by c.full_name, c.id), ''[]'') from public.clients c where c.id = any(%2$L::uuid[])), ''documentos'', (select coalesce(jsonb_agg(jsonb_build_object(''doc_type'', d.doc_type, ''uploaded_at'', d.uploaded_at, ''caduca_el'', d.caduca_el, ''client_id'', d.client_id) order by d.uploaded_at desc nulls last, d.id desc), ''[]'') from public.documents d where d.contrato_id = %1$L or d.client_id = any(%2$L::uuid[])))', k, cs),
      format('select jsonb_build_object(''clientes'', r->''clientes'', ''documentos'', r->''documentos'') from (select public.operacion_compradores_datos(%L, %L::uuid[]) r) s', k, cs));
    perform pg_temp.par('operaciones_compradores', u,
      'select jsonb_build_object(''vinculos'', (select coalesce(jsonb_agg(jsonb_build_object(''contrato_id'', cc.contrato_id, ''rol'', cc.rol, ''cliente'', (select jsonb_build_object(''id'', c.id, ''full_name'', c.full_name, ''email'', c.email, ''phone'', c.phone, ''kyc_status'', c.kyc_status) from public.clients c where c.id = cc.client_id)) order by cc.contrato_id, cc.client_id), ''[]'') from public.contrato_compradores cc), ''documentos'', (select coalesce(jsonb_agg(jsonb_build_object(''id'', d.id, ''client_id'', d.client_id, ''contrato_id'', d.contrato_id, ''doc_type'', d.doc_type, ''storage_path'', d.storage_path, ''status'', d.status, ''uploaded_at'', d.uploaded_at, ''caduca_el'', d.caduca_el) order by d.uploaded_at desc nulls last, d.id desc), ''[]'') from public.documents d))',
      'select jsonb_build_object(''vinculos'', r->''vinculos'', ''documentos'', r->''documentos'') from (select public.operaciones_compradores_datos() r) s');
    perform pg_temp.par('soporte_datos', u,
      'select jsonb_build_object(''hilos'', (select coalesce(jsonb_agg(jsonb_build_object(''id'', h.id, ''client_id'', h.client_id, ''categoria'', h.categoria, ''estado'', h.estado, ''actualizado_en'', h.actualizado_en, ''factura_id'', h.factura_id, ''contrato_id'', h.contrato_id) order by h.actualizado_en desc, h.id desc), ''[]'') from public.hilo_soporte h), ''mensajes'', (select coalesce(jsonb_agg(jsonb_build_object(''hilo_id'', m.hilo_id, ''client_id'', m.client_id, ''de'', m.de, ''autor'', m.autor, ''texto'', m.texto, ''creado_en'', m.creado_en) order by m.creado_en desc, m.id desc), ''[]'') from (select * from public.mensajes_comprador mc order by mc.creado_en desc, mc.id desc limit 600) m), ''clientes'', (select coalesce(jsonb_agg(jsonb_build_object(''id'', c.id, ''full_name'', c.full_name, ''email'', c.email, ''phone'', c.phone, ''tipo'', c.tipo) order by c.full_name, c.id), ''[]'') from public.clients c where c.id in (select h.client_id from public.hilo_soporte h union select mc.client_id from public.mensajes_comprador mc)))',
      'select jsonb_build_object(''hilos'', r->''hilos'', ''mensajes'', r->''mensajes'', ''clientes'', r->''clientes'') from (select public.soporte_datos() r) s');
    perform pg_temp.par('notificaciones', u,
      'select coalesce(jsonb_agg(jsonb_build_object(''tipo'', t.tipo, ''titulo'', t.titulo, ''detalle'', t.detalle, ''enlace'', t.enlace, ''creado_en'', t.creado_en, ''destinatario'', t.destinatario) order by t.creado_en desc, t.id desc), ''[]'') from (select * from public.notificaciones n order by n.creado_en desc, n.id desc limit 400) t',
      -- sin id ni leida (20261017200000, H7): la paridad con L5 es la de los campos de entonces, antes y después de esa migración
      'select coalesce(jsonb_agg(e.v - ''id'' - ''leida'' order by e.i), ''[]'') from jsonb_array_elements(public.notificaciones_datos(400)->''notificaciones'') with ordinality e(v, i)');
    perform pg_temp.par('correos(contratos)', u,
      format('select coalesce(jsonb_agg(jsonb_build_object(''para'', e.para, ''asunto'', e.asunto, ''via'', e.via, ''enviado_por'', e.enviado_por, ''enviado_en'', e.enviado_en, ''contrato_id'', e.contrato_id, ''factura_id'', e.factura_id) order by e.enviado_en desc, e.id desc), ''[]'') from (select * from public.correos_enviados x where x.contrato_id = any(%L::uuid[]) order by x.enviado_en desc, x.id desc limit 200) e', ks),
      format('select public.correos_registro_datos(%L::uuid[], null)->''correos''', ks));
    perform pg_temp.par('correos(factura)', u,
      format('select coalesce(jsonb_agg(jsonb_build_object(''para'', e.para, ''asunto'', e.asunto, ''via'', e.via, ''enviado_por'', e.enviado_por, ''enviado_en'', e.enviado_en, ''contrato_id'', e.contrato_id, ''factura_id'', e.factura_id) order by e.enviado_en desc, e.id desc), ''[]'') from (select * from public.correos_enviados x where x.factura_id = %L order by x.enviado_en desc, x.id desc limit 200) e', f),
      format('select public.correos_registro_datos(null, %L)->''correos''', f));
    perform pg_temp.par('ficha_distinta(cliente)', u,
      format('select coalesce(jsonb_agg(jsonb_build_object(''tipo'', d.tipo, ''id'', d.id, ''numero'', d.numero, ''congelado'', d.congelado, ''ficha'', d.ficha, ''diferencias'', d.diferencias) order by d.tipo, d.id), ''[]'') from public.documentos_desactualizados d where d.client_id = %L and jsonb_typeof(d.diferencias) = ''array'' and jsonb_array_length(d.diferencias) > 0', fdd),
      format('select public.documentos_desactualizados_datos(null, %L, null)->''documentos''', fdd));
  end loop;
  -- la vista por TIPO es cara (~12 s): un usuario por rol
  for u in select distinct on (rol) * from _u order by rol, uid loop
    perform pg_temp.par('ficha_distinta(tipo)', u,
      'select coalesce(jsonb_agg(jsonb_build_object(''tipo'', d.tipo, ''id'', d.id, ''numero'', d.numero, ''congelado'', d.congelado, ''ficha'', d.ficha, ''diferencias'', d.diferencias) order by d.tipo, d.id), ''[]'') from public.documentos_desactualizados d where d.tipo = ''contrato'' and jsonb_typeof(d.diferencias) = ''array'' and jsonb_array_length(d.diferencias) > 0',
      'select public.documentos_desactualizados_datos(''contrato'', null, null)->''documentos''');
  end loop;
  for v_chk in select distinct r.chk from _r r order by 1 loop
    select count(*), count(*) filter (where not r.ok), count(*) filter (where r.lleno), count(*) filter (where r.err is not null)
      into n_u, dif, llenos, errs from _r r where r.chk = v_chk;
    res := res || pg_temp.l(dif = 0 and errs = 0 and llenos > 0,
      format('P1 %s: %s sesiones, dif=%s, llenos=%s, err=%s%s', v_chk, n_u, dif, llenos, errs,
             coalesce(' (' || (select string_agg(distinct left(r.err, 60), '; ') from _r r where r.chk = v_chk and r.err is not null) || ')', '')));
  end loop;

  -- ── P2 ve=false: un agente con una ficha que no ve ───────────────────────────────────────────────────────────────────
  select * into agente from _u w where not w.portal and w.rol = 'agente'
     and exists (select 1 from unnest(fichas) z where (pg_temp.q(w.uid, w.em, format('select public.clientes_lista_datos(%L::uuid[])', array[z]))->'clientes') = '[]'::jsonb)
   limit 1;
  if agente.uid is null then
    res := res || pg_temp.l(false, 'P2 no hay agente que deje de ver alguna ficha de la muestra: caso sin medir');
  else
    select z into nove from unnest(fichas) z
     where (pg_temp.q(agente.uid, agente.em, format('select public.clientes_lista_datos(%L::uuid[])', array[z]))->'clientes') = '[]'::jsonb limit 1;
    v := pg_temp.q(agente.uid, agente.em, format('select public.comprador_ficha_datos(%L, array[''ficha'',''documento'',''documentos'',''portal'',''soporte''])', nove));
    res := res || pg_temp.l(v = '{"ve": false, "recortado": []}'::jsonb, 'P2 ficha que no ve: solo {ve:false}, ninguna parte (' || left(v::text, 80) || ')');
  end if;

  -- ── P3 sin sesión y ACL ────────────────────────────────────────────────────────────────────────────────────────────────
  res := res || pg_temp.l(
    (select bool_and(coalesce(pg_temp.q(null, null, s)->>'__err', '') like '42501%') from unnest(array[
      'select public.clientes_lista_datos()', format('select public.comprador_ficha_datos(%L, array[''ficha''])', fichas[1]),
      format('select public.operacion_compradores_datos(%L, %L::uuid[])', k, cs), 'select public.operaciones_compradores_datos()',
      'select public.soporte_datos()', 'select public.notificaciones_datos(5)', format('select public.correos_registro_datos(null, %L)', f),
      'select public.documentos_desactualizados_datos(''contrato'', null, null)',
      'select to_jsonb(array_agg(b)) from public.clientes_busca(''ana'') b']) s),
    'P3a sin sesión: 42501 en las 8 y en clientes_busca');
  res := res || pg_temp.l(
    (select bool_and(not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('service_role', p.oid, 'execute')
                     and has_function_privilege('authenticated', p.oid, 'execute') and pg_get_userbyid(p.proowner) = 'lw_lector'
                     and p.prosecdef and p.proconfig @> array['search_path=""'])
       from pg_proc p where p.pronamespace = 'public'::regnamespace
        and p.proname in ('clientes_lista_datos', 'comprador_ficha_datos', 'operacion_compradores_datos', 'operaciones_compradores_datos',
                          'soporte_datos', 'notificaciones_datos', 'correos_registro_datos', 'documentos_desactualizados_datos',
                          'clientes_busca', 'contratos_busca', 'bot_pendientes'))
    and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
          and p.proname in ('clientes_lista_datos', 'comprador_ficha_datos', 'operacion_compradores_datos', 'operaciones_compradores_datos',
                            'soporte_datos', 'notificaciones_datos', 'correos_registro_datos', 'documentos_desactualizados_datos',
                            'clientes_busca', 'contratos_busca', 'bot_pendientes')) = 11,
    'P3b las 11: DEFINER, dueño lw_lector, search_path vacío, solo authenticated (sin anon ni service_role)');

  -- ── P4 clientes_busca ──────────────────────────────────────────────────────────────────────────────────────────────────
  select * into u from _u w where not w.portal and w.rol in ('super_admin', 'admin') order by w.rol desc, w.uid limit 1;
  v := pg_temp.q(u.uid, u.em, 'select coalesce(jsonb_agg(b), ''[]'') from public.clientes_busca(''%@%'') b');
  res := res || pg_temp.l(v = '[]'::jsonb, 'P4a clientes_busca(''%@%'') no lista nada (' || left(v::text, 60) || ')');
  -- el correo se saca aquí, como postgres: dentro de la sesión, leer clients ya es 42501 desde el revoke (ensayo 13f3f2c9)
  select c.id, upper(c.email) into x, em_x from public.clients c where c.email like '%@%' order by c.created_at limit 1;
  v := pg_temp.q(u.uid, u.em, format('select coalesce(jsonb_agg(b.id), ''[]'') from public.clientes_busca(%L) b', em_x));
  res := res || pg_temp.l(v @> to_jsonb(array[x]), 'P4b el correo exacto (en mayúsculas) de una ficha visible la encuentra (' || left(v::text, 60) || ')');
  select * into agente from _u w where not w.portal and w.rol = 'agente'
     and not exists (select 1 from public.usuarios u4 where u4.user_id = w.uid and 'asistente' = any(u4.herramientas)) limit 1;
  v := pg_temp.q(agente.uid, agente.em, 'select coalesce(jsonb_agg(b), ''[]'') from public.clientes_busca(''ana'') b');
  res := res || pg_temp.l(agente.uid is not null and coalesce(v->>'__err', '') like '42501%',
    'P4c sin la herramienta del asistente: 42501 (' || coalesce(left(v::text, 60), 'sin agente así') || ')');

  -- ── P5 contratos_busca y bot_pendientes por la RPC como authenticated ──────────────────────────────────────────────────
  for u in select * from _u w where not w.portal loop
    perform pg_temp.par('contratos_busca', u,
      'select coalesce(jsonb_agg(to_jsonb(b) order by b.created_at desc, b.id), ''[]'') from (select c.id, c.numero, c.created_at from public.contratos c where public.es_agente() and c.numero is not null order by c.created_at desc limit 10) b',
      'select coalesce(jsonb_agg(jsonb_build_object(''id'', b.id, ''numero'', b.numero, ''created_at'', b.created_at) order by b.created_at desc, b.id), ''[]'') from public.contratos_busca('''') b',
      false);
  end loop;
  select count(*), count(*) filter (where not r.ok), count(*) filter (where r.lleno), count(*) filter (where r.err is not null)
    into n_u, dif, llenos, errs from _r r where r.chk = 'contratos_busca';
  res := res || pg_temp.l(dif = 0 and errs = 0 and llenos > 0, format('P5a contratos_busca(''''): %s sesiones, dif=%s, llenos=%s, err=%s', n_u, dif, llenos, errs));
  -- P5b bot_pendientes: el cuerpo de hoy (INVOKER) leído directo como cada persona contra la RPC (DEFINER-lw_lector), y en el
  -- contrato del fixture salen las DOS ramas: LAW-124 (cuenta ≠ sociedad, lee sociedades.clave/razon) y «no coincide con la ficha»
  for u in select * from _u w where not w.portal loop
    perform pg_temp.par('bot_pendientes', u,
      format('select coalesce(jsonb_agg(jsonb_build_object(''motivo'', b.motivo, ''ref'', b.ref) order by b.ref nulls last, b.motivo), ''[]'') from (select ''La cuenta de cobro está a nombre de '' || cb.titular || '' y el contrato lo firma '' || s.razon || '': quién cobra está pendiente de confirmación del promotor.'' as motivo, ''LAW-124''::text as ref from public.contratos c join public.cuentas_bancarias cb on cb.clave = c.datos->''fields''->>''cuenta_bancaria'' join public.sociedades s on s.clave = c.datos->''fields''->>''sociedad_firmante'' where c.id = %1$L and lower(regexp_replace(btrim(cb.titular), ''[[:space:]]+'', '' '', ''g'')) <> lower(regexp_replace(btrim(s.razon), ''[[:space:]]+'', '' '', ''g'')) union all select ''El documento impreso no coincide con la ficha: '' || (select string_agg(e->>''campo'', '', '' order by e->>''campo'') from jsonb_array_elements(d.diferencias) e), null::text from public.documentos_desactualizados d where d.tipo = ''contrato'' and d.id = %1$L and jsonb_typeof(d.diferencias) = ''array'' and jsonb_array_length(d.diferencias) > 0) b', k),
      format('select coalesce(jsonb_agg(jsonb_build_object(''motivo'', b.motivo, ''ref'', b.ref) order by b.ref nulls last, b.motivo), ''[]'') from public.bot_pendientes(%L) b', k));
  end loop;
  select count(*), count(*) filter (where not r.ok), count(*) filter (where r.lleno), count(*) filter (where r.err is not null)
    into n_u, dif, llenos, errs from _r r where r.chk = 'bot_pendientes';
  select * into u from _u w where not w.portal and w.rol in ('super_admin', 'admin') order by w.rol desc, w.uid limit 1;
  v := pg_temp.q(u.uid, u.em, format('select coalesce(jsonb_agg(b.ref), ''[]'') from public.bot_pendientes(%L) b', k));
  res := res || pg_temp.l(dif = 0 and errs = 0 and llenos > 0 and v @> '["LAW-124"]'::jsonb and v @> '[null]'::jsonb,
    format('P5b bot_pendientes: %s sesiones, dif=%s, llenos=%s, err=%s; el super_admin ve las dos ramas (LAW-124 y ficha): %s', n_u, dif, llenos, errs, v));

  -- ── P6 tiempo de documentos_desactualizados_datos (7 seguidas; la 6.ª y la 7.ª ya pueden ir con plan genérico) ──────────
  for i in 1..7 loop
    t0 := clock_timestamp();
    v := pg_temp.q(u.uid, u.em, format('select public.documentos_desactualizados_datos(null, %L, null)', fichas[1 + (i % cardinality(fichas))]));
    ms := ms || (extract(epoch from clock_timestamp() - t0) * 1000)::int;
  end loop;
  res := res || pg_temp.l((select max(z) from unnest(ms) z) < 4000, 'P6 por cliente, 7 llamadas (ms): ' || array_to_string(ms, ','));

  raise exception 'FIN DE PRUEBAS LAW-338 L5 (se deshace todo):%', res;
end $todo$;
