-- PRUEBA de LAW-557 (alta con documento en una operación) y LAW-558 (retención de copias KYC), 13-oct-2026.
-- Se pasa DESPUÉS de aplicar 20261013230000_law557_558_alta_con_documento_y_retencion_kyc (MCP supabase-lawang,
-- execute_sql). Cada bloque es UNA petición: setup + casos + raise final que lo revierte todo (no queda rastro salvo
-- números de la secuencia de clientes, que se gastan aunque se revierta: CLI-xxxxx con huecos).
-- Las RPC se llaman con el rol REAL: service_role (la edge) con el p_uid de una persona real del equipo, y
-- authenticated para comprobar que el navegador no las alcanza. Agentes con alcance por empresa (empresas no vacías):
-- el caso que de verdad tiene que pasar (memoria reference_lawang_datos_prueba_proyecto_con_empresa).
-- Cada línea debe empezar por «OK». Una «FALLO» es un agujero o una regresión.
-- destructivo-ok: prueba en transacción que termina en raise (rollback)

create function pg_temp.como(p_rol text, p_uid uuid, p_email text, p_sql text) returns text language plpgsql as $f$
declare got text; m text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', p_rol, 'email', p_email)::text, true);
  execute format('set local role %I', p_rol);
  begin
    execute p_sql into got; got := coalesce(got, 'null');
  exception when others then get stacked diagnostics m = message_text; got := sqlstate || ':' || m;
  end;
  reset role;
  return got;
end $f$;
create function pg_temp.ok(p_got text, p_esp text, p_et text) returns text language sql as $f$
  select case when p_got like p_esp then 'OK    ' else 'FALLO ' end || p_et || '  [' || left(p_got, 160) || ' | esp ' || p_esp || ']' || E'\n'
$f$;

-- ─── BLOQUE 1: el alta con documento (RPC de la edge) ──────────────────────────────────────────────────────────────
do $t$
declare
  a uuid; ea text; b uuid; eb text; ina uuid; eina text;
  al1 uuid; al2 uuid; al3 uuid; al4 uuid; al5 uuid; alx uuid;
  p1 text; p1b text; p2 text; p3 text; p5 text; sob text;
  em text := 'law557.prueba.' || substr(md5(random()::text), 1, 8) || '@example.invalid';
  pas text := 'ZZ557' || upper(substr(md5(random()::text), 1, 6));
  d jsonb; got text; r text := ''; n int; j jsonb; i int;
begin
  insert into public.config_instancia (clave, valor) values ('alta_exige_documento', 'true'::jsonb)
  on conflict (clave) do update set valor = excluded.valor;
  select u.user_id, lower(u.email) into a, ea from public.usuarios u
   where u.activo and u.rol = 'agente' and u.user_id is not null and cardinality(coalesce(u.empresas, '{}')) > 0 order by u.email limit 1;
  select u.user_id, lower(u.email) into b, eb from public.usuarios u
   where u.activo and u.rol = 'agente' and u.user_id is not null and cardinality(coalesce(u.empresas, '{}')) > 0 and u.user_id <> a order by u.email limit 1;
  select u.user_id, lower(u.email) into ina, eina from public.usuarios u where not u.activo and u.user_id is not null limit 1;
  d := jsonb_build_object('full_name', 'Prueba Law557', 'email', em, 'phone', '+34600000557', 'nationality', 'ES',
                          'passport_number', pas, 'tipo', 'persona', 'idioma_comunicacion', 'es');

  -- el navegador NO alcanza ninguna RPC nueva
  r := r || pg_temp.ok(pg_temp.como('authenticated', a, ea, format('select public.kyc_alta_reserva(%L::uuid)::text', a)), '42501:%', '1.1 authenticated no ejecuta kyc_alta_reserva');
  r := r || pg_temp.ok(pg_temp.como('authenticated', a, ea, format('select public.cliente_alta_con_documentos(%L::uuid, %L::uuid, %L::jsonb, array[]::text[])::text', a, gen_random_uuid(), d)), '42501:%', '1.2 authenticated no ejecuta cliente_alta_con_documentos');
  r := r || pg_temp.ok(pg_temp.como('anon', gen_random_uuid(), '', format('select public.kyc_alta_descarta(%L::uuid, %L::uuid)::text', a, gen_random_uuid())), '42501:%', '1.3 anon no ejecuta kyc_alta_descarta');
  r := r || pg_temp.ok(pg_temp.como('authenticated', a, ea, format('select public._cliente_crea(null, %L::jsonb)::text', d)), '42501:%', '1.4 authenticated no ejecuta _cliente_crea');
  r := r || pg_temp.ok(pg_temp.como('service_role', a, ea, format('select public._cliente_crea(null, %L::jsonb)::text', d)), '42501:%', '1.5 ni service_role ejecuta _cliente_crea');

  -- reservar
  al1 := pg_temp.como('service_role', a, ea, format('select public.kyc_alta_reserva(%L::uuid)::text', a))::uuid;
  r := r || pg_temp.ok((select count(*)::text from public.kyc_altas_pendientes where id = al1 and uid = a and urls_firmadas = 1), '1', '1.6 A reserva una alta: la base genera el id');
  r := r || pg_temp.ok(pg_temp.como('service_role', b, eb, format('select public.kyc_alta_reserva(%L::uuid, %L::uuid)::text', b, al1)), 'PT403:alta_no_valida', '1.7 B no pide URL en la alta de A');
  if ina is not null then
    r := r || pg_temp.ok(pg_temp.como('service_role', ina, eina, format('select public.kyc_alta_reserva(%L::uuid)::text', ina)), '42501:%', '1.8 cuenta desactivada no reserva');
  end if;
  r := r || pg_temp.ok(pg_temp.como('service_role', gen_random_uuid(), '', format('select public.kyc_alta_reserva(%L::uuid)::text', gen_random_uuid())), '42501:%', '1.9 uid que no es del equipo no reserva');

  -- ficheros «subidos» (fila en storage.objects, como el bloque 2 de prueba_frontera_b2_compradores_kyc.sql)
  p1 := al1 || '/' || gen_random_uuid() || '.jpg';
  sob := al1 || '/' || gen_random_uuid() || '.png';          -- subido y quitado en pantalla: sobrante
  insert into storage.objects (bucket_id, name) values ('kyc', p1), ('kyc', sob);
  al2 := pg_temp.como('service_role', a, ea, format('select public.kyc_alta_reserva(%L::uuid)::text', a))::uuid;
  p2 := al2 || '/' || gen_random_uuid() || '.pdf';
  insert into storage.objects (bucket_id, name) values ('kyc', p2);

  -- validación que falla → 0 clientes y 0 documentos, la pendiente sigue
  got := pg_temp.como('service_role', a, ea, format('select public.cliente_alta_con_documentos(%L::uuid, %L::uuid, %L::jsonb, array[%L])::text', a, al1, d - 'email', p1));
  r := r || pg_temp.ok(got, '22023:No se puede crear la ficha, falta: Email%', '1.10 falta el email: error de la base tal cual (22023)');
  r := r || pg_temp.ok((select count(*)::text from public.clients where id = al1) || '/' || (select count(*) from public.documents where storage_path = p1)
                       || '/' || (select count(*) from public.kyc_altas_pendientes where id = al1), '0/0/1', '1.11 tras el error: 0 clientes, 0 documentos, la pendiente sigue');
  -- ruta de otra alta, repetida, más de 4, ninguna
  r := r || pg_temp.ok(pg_temp.como('service_role', a, ea, format('select public.cliente_alta_con_documentos(%L::uuid, %L::uuid, %L::jsonb, array[%L])::text', a, al1, d, p2)), 'PT400:ruta_invalida', '1.12 ruta de OTRA alta (aunque sea tuya): ruta_invalida');
  r := r || pg_temp.ok(pg_temp.como('service_role', a, ea, format('select public.cliente_alta_con_documentos(%L::uuid, %L::uuid, %L::jsonb, array[%L, %L])::text', a, al1, d, p1, p1)), 'PT400:ruta_invalida', '1.13 la misma ruta dos veces: ruta_invalida');
  r := r || pg_temp.ok(pg_temp.como('service_role', a, ea, format('select public.cliente_alta_con_documentos(%L::uuid, %L::uuid, %L::jsonb, array[]::text[])::text', a, al1, d)), 'PT400:faltan_ficheros', '1.14 sin ficheros: faltan_ficheros');
  r := r || pg_temp.ok(pg_temp.como('service_role', a, ea, format('select public.cliente_alta_con_documentos(%L::uuid, %L::uuid, %L::jsonb, array[%L,%L,%L,%L,%L])::text', a, al1, d,
                         al1||'/'||gen_random_uuid()||'.jpg', al1||'/'||gen_random_uuid()||'.jpg', al1||'/'||gen_random_uuid()||'.jpg', al1||'/'||gen_random_uuid()||'.jpg', al1||'/'||gen_random_uuid()||'.jpg')),
                       'PT400:demasiados_ficheros', '1.15 cinco ficheros: demasiados_ficheros');
  -- pendiente de otro usuario
  r := r || pg_temp.ok(pg_temp.como('service_role', b, eb, format('select public.cliente_alta_con_documentos(%L::uuid, %L::uuid, %L::jsonb, array[%L])::text', b, al1, d, p1)), 'PT403:alta_no_valida', '1.16 B no completa la alta de A');
  r := r || pg_temp.ok((select count(*)::text from public.clients where id = al1), '0', '1.17 ... y no se ha creado nada');
  r := r || pg_temp.ok(pg_temp.como('service_role', b, eb, format('select coalesce(public.kyc_alta_estado(%L::uuid, %L::uuid), ''null'')', b, al1)), 'null', '1.18 kyc_alta_estado de B sobre la alta de A: nada');
  r := r || pg_temp.ok(pg_temp.como('service_role', b, eb, format('select cardinality(public.kyc_alta_descarta(%L::uuid, %L::uuid))::text', b, al1)), '0', '1.19 B no descarta la alta de A ...');
  r := r || pg_temp.ok((select count(*)::text from public.kyc_altas_pendientes where id = al1), '1', '1.20 ... y la pendiente de A sigue');

  -- alta ok (con claves de más en datos: se ignoran)
  got := pg_temp.como('service_role', a, ea, format('select public.cliente_alta_con_documentos(%L::uuid, %L::uuid, %L::jsonb, array[%L], %L::date)::text', a, al1,
                         d || '{"kyc_status":"verified","propietario":"otro@x.com","notes":"inyectado"}'::jsonb, p1, '2031-01-31'));
  j := got::jsonb;
  r := r || pg_temp.ok(j->>'id', al1::text, '1.21 alta ok: el id del cliente es el de la alta');
  r := r || pg_temp.ok((select c.kyc_status || '/' || lower(c.propietario) || '/' || coalesce(c.notes, 'sin notas') from public.clients c where c.id = al1), 'pending/' || ea || '/sin notas', '1.22 ficha: KYC pending, dueño A, claves de más ignoradas');
  r := r || pg_temp.ok((select string_agg(d2.doc_type || '/' || d2.status || '/' || d2.caduca_el || '/' || (d2.subido_por = a), ',') from public.documents d2 where d2.client_id = al1), 'passport/pending/2031-01-31/true', '1.23 un documento: passport, pending, con caducidad y subido por A');
  r := r || pg_temp.ok((select count(*)::text from public.kyc_altas_pendientes where id = al1), '0', '1.24 la pendiente se consume');
  r := r || pg_temp.ok(j->'sobrantes'->>0, sob, '1.25 el fichero subido y descartado vuelve como sobrante (lo borra la edge)');
  r := r || pg_temp.ok(pg_temp.como('authenticated', a, ea, format('select count(*)::text from public.documents where client_id = %L', al1)), '1', '1.26 A (con alcance por empresa) ve el documento de su cliente nuevo');
  -- reintento tras confirmar
  got := pg_temp.como('service_role', a, ea, format('select public.cliente_alta_con_documentos(%L::uuid, %L::uuid, %L::jsonb, array[%L])::text', a, al1, d, p1));
  r := r || pg_temp.ok((got::jsonb->>'id') || '/' || (got::jsonb->>'ya_existia') || '/' || (select count(*) from public.documents where client_id = al1), al1 || '/true/1', '1.27 reintento: misma ficha, ya_existia, sin duplicar documentos');
  r := r || pg_temp.ok(pg_temp.como('service_role', b, eb, format('select public.cliente_alta_con_documentos(%L::uuid, %L::uuid, %L::jsonb, array[%L])::text', b, al1, d, p1)), 'PT403:alta_no_valida', '1.28 B reintentando la alta ya creada de A: nada');
  r := r || pg_temp.ok(pg_temp.como('service_role', a, ea, format('select public.kyc_alta_estado(%L::uuid, %L::uuid)', a, al1)), 'creado', '1.29 estado para A: creado');
  -- descarte de una alta ya creada → nada
  r := r || pg_temp.ok(pg_temp.como('service_role', a, ea, format('select cardinality(public.kyc_alta_descarta(%L::uuid, %L::uuid))::text', a, al1)), '0', '1.30 descartar una alta ya creada: no devuelve nada');
  r := r || pg_temp.ok((select count(*)::text from public.clients where id = al1) || '/' || (select count(*) from public.documents where client_id = al1), '1/1', '1.31 ... y la ficha y su documento siguen');
  -- email repetido: 22023 propio, sin datos de la otra ficha
  al3 := pg_temp.como('service_role', a, ea, format('select public.kyc_alta_reserva(%L::uuid)::text', a))::uuid;
  p3 := al3 || '/' || gen_random_uuid() || '.jpg';
  insert into storage.objects (bucket_id, name) values ('kyc', p3);
  got := pg_temp.como('service_role', a, ea, format('select public.cliente_alta_con_documentos(%L::uuid, %L::uuid, %L::jsonb, array[%L])::text', a, al3,
                         d || jsonb_build_object('passport_number', pas || 'X'), p3));
  r := r || pg_temp.ok(got, '22023:Ya hay una ficha con ese email%', '1.32 email repetido: 22023 con mensaje propio');
  r := r || pg_temp.ok((position(pas in got) = 0 and position('Prueba' in got) = 0)::text, 'true', '1.33 ... sin nada de la otra ficha en el mensaje');
  r := r || pg_temp.ok((select count(*)::text from public.kyc_altas_pendientes where id = al3), '1', '1.34 ... y la pendiente sigue para corregir');
  -- descarte de una pendiente propia: devuelve sus ficheros
  r := r || pg_temp.ok(pg_temp.como('service_role', a, ea, format('select array_to_string(public.kyc_alta_descarta(%L::uuid, %L::uuid), '','')', a, al3)), p3, '1.35 A descarta su pendiente: vuelve su fichero');
  r := r || pg_temp.ok((select count(*)::text from public.kyc_altas_pendientes where id = al3), '0', '1.36 ... y la pendiente desaparece');
  -- empresa → other
  al4 := pg_temp.como('service_role', a, ea, format('select public.kyc_alta_reserva(%L::uuid)::text', a))::uuid;
  insert into storage.objects (bucket_id, name) values ('kyc', al4 || '/' || '00000000-0000-4000-8000-000000000557.pdf');
  got := pg_temp.como('service_role', a, ea, format('select public.cliente_alta_con_documentos(%L::uuid, %L::uuid, %L::jsonb, array[%L])::text', a, al4,
                         jsonb_build_object('full_name', 'PT Prueba Law557', 'email', 'e' || em, 'phone', '+62800000557', 'nationality', 'ID', 'passport_number', 'NPWP' || pas,
                                            'tipo', 'empresa', 'forma_juridica', 'PT', 'rep_nombre', 'Rep Prueba'), al4 || '/00000000-0000-4000-8000-000000000557.pdf'));
  r := r || pg_temp.ok((select string_agg(doc_type, ',') from public.documents where client_id = al4) || '/' || (select tipo || ':' || coalesce(rep_nombre, '') from public.clients where id = al4),
                       'other/empresa:Rep Prueba', '1.37 empresa: el servidor registra el documento como other');
  -- tipo no válido
  al5 := pg_temp.como('service_role', a, ea, format('select public.kyc_alta_reserva(%L::uuid)::text', a))::uuid;
  p5 := al5 || '/' || gen_random_uuid() || '.jpg';
  insert into storage.objects (bucket_id, name) values ('kyc', p5);
  r := r || pg_temp.ok(pg_temp.como('service_role', a, ea, format('select public.cliente_alta_con_documentos(%L::uuid, %L::uuid, %L::jsonb, array[%L])::text', a, al5, d || '{"tipo":"otro"}'::jsonb, p5)), '22023:Tipo de cliente no válido', '1.38 tipo inventado: 22023');
  -- caducada (25 h)
  update public.kyc_altas_pendientes set creado_en = now() - interval '25 hours' where id = al5;
  r := r || pg_temp.ok(pg_temp.como('service_role', a, ea, format('select public.cliente_alta_con_documentos(%L::uuid, %L::uuid, %L::jsonb, array[%L])::text', a, al5, d || jsonb_build_object('email', 'c' || em, 'passport_number', 'C' || pas), p5)), 'PT403:alta_no_valida', '1.39 alta de más de 24 h: alta_no_valida');
  r := r || pg_temp.ok(pg_temp.como('service_role', a, ea, format('select public.kyc_alta_reserva(%L::uuid, %L::uuid)::text', a, al5)), 'PT403:alta_no_valida', '1.40 ... ni pide más URLs');
  -- tope de 8 URLs por alta (al2 lleva 1)
  for i in 1..7 loop perform pg_temp.como('service_role', a, ea, format('select public.kyc_alta_reserva(%L::uuid, %L::uuid)::text', a, al2)); end loop;
  r := r || pg_temp.ok(pg_temp.como('service_role', a, ea, format('select public.kyc_alta_reserva(%L::uuid, %L::uuid)::text', a, al2)), 'PT409:demasiados_ficheros', '1.41 la 9.ª URL de una alta: demasiados_ficheros');
  -- tope de 3 abiertas por usuario (abiertas en plazo ahora: al2; al5 caducada no cuenta)
  perform pg_temp.como('service_role', a, ea, format('select public.kyc_alta_reserva(%L::uuid)::text', a));
  perform pg_temp.como('service_role', a, ea, format('select public.kyc_alta_reserva(%L::uuid)::text', a));
  r := r || pg_temp.ok(pg_temp.como('service_role', a, ea, format('select public.kyc_alta_reserva(%L::uuid)::text', a)), 'PT409:demasiadas_altas_abiertas', '1.42 la 4.ª alta abierta: demasiadas_altas_abiertas');
  r := r || pg_temp.ok((select count(*)::text from public.kyc_altas_pendientes where uid = a and creado_en > now() - interval '24 hours'), '3', '1.43 ... y quedan exactamente 3 abiertas');
  -- kyc_sueltos_de: una carpeta con pendiente viva no es suelta
  r := r || pg_temp.ok((select count(*)::text from public.kyc_sueltos_de(al2)), '0', '1.44 kyc_sueltos_de no ve los ficheros de una alta pendiente viva');

  n := (length(r) - length(replace(r, 'FALLO', ''))) / 5;
  raise exception E'RES BLOQUE 1\n%FALLOS=%', r, n;
end $t$;

-- ─── BLOQUE 2: el interruptor (cliente_guarda y el CRM de leads) ───────────────────────────────────────────────────
-- (las dos funciones pg_temp de arriba van delante en esta misma petición)
do $t$
declare a uuid; ea text; adm uuid; eadm text; idc uuid; got text; r text := ''; n int; lead_sin uuid; lead_con uuid;
  em text := 'law557.b2.' || substr(md5(random()::text), 1, 8) || '@example.invalid';
  d jsonb;
begin
  select u.user_id, lower(u.email) into a, ea from public.usuarios u
   where u.activo and u.rol = 'agente' and u.user_id is not null and cardinality(coalesce(u.empresas, '{}')) > 0 order by u.email limit 1;
  select u.user_id, lower(u.email) into adm, eadm from public.usuarios u where u.activo and u.rol = 'admin' and u.ambito = 'global' and u.user_id is not null limit 1;
  d := jsonb_build_object('full_name', 'Prueba Law557 B2', 'email', em, 'phone', '+34600000558', 'nationality', 'ES', 'passport_number', 'ZZB2' || upper(substr(md5(random()::text), 1, 6)));
  -- sin interruptor (false): el alta de siempre
  insert into public.config_instancia (clave, valor) values ('alta_exige_documento', 'false'::jsonb)
  on conflict (clave) do update set valor = excluded.valor;
  got := pg_temp.como('authenticated', a, ea, format('select public.cliente_guarda(null, %L::jsonb)::text', d));
  r := r || pg_temp.ok(got, '________-____-____-____-____________', '2.1 interruptor apagado: cliente_guarda(null) crea como siempre');
  idc := got::uuid;
  r := r || pg_temp.ok((select lower(propietario) || '/' || kyc_status from public.clients where id = idc), ea || '/pending', '2.2 ... con el mismo dueño y KYC que antes');
  r := r || pg_temp.ok(pg_temp.como('authenticated', a, ea, format('select public.cliente_guarda(null, %L::jsonb)::text', d || '{"kyc_status":"verified","email":"x2@example.invalid","passport_number":"ZZB2OTRO1"}'::jsonb)), '42501:Aprobar o rechazar%', '2.3 ... y un agente sigue sin aprobar su KYC al crear');
  -- encendido
  update public.config_instancia set valor = 'true'::jsonb where clave = 'alta_exige_documento';
  r := r || pg_temp.ok(pg_temp.como('authenticated', a, ea, format('select public.cliente_guarda(null, %L::jsonb)::text', d || '{"email":"x3@example.invalid","passport_number":"ZZB2OTRO2"}'::jsonb)),
                       '22023:El alta de un cliente va con su documento de identidad%', '2.4 interruptor encendido: cliente_guarda(null) se niega (22023)');
  r := r || pg_temp.ok(pg_temp.como('authenticated', a, ea, format('select public.cliente_guarda(%L, %L::jsonb)::text', idc, '{"notes":"prueba law557"}')), idc::text, '2.5 editar sigue igual con el interruptor');
  r := r || pg_temp.ok((select notes from public.clients where id = idc), 'prueba law557', '2.6 ... y la edición se guarda');
  r := r || pg_temp.ok(pg_temp.como('authenticated', gen_random_uuid(), 'nadie@example.invalid', format('select public.cliente_guarda(null, %L::jsonb)::text', d)), '42501:%', '2.7 quien no es del equipo sigue parando en 42501 (antes que el interruptor)');
  -- CRM de leads (como admin global, que tiene la herramienta leads)
  select l.id into lead_sin from public.leads l
   where nullif(btrim(coalesce(l.name, '')), '') is not null and nullif(btrim(coalesce(l.email, '')), '') is not null
     and not exists (select 1 from public.clients c where c.email is not null and lower(c.email) = lower(btrim(l.email)) and c.tipo = 'persona') limit 1;
  select l.id into lead_con from public.leads l
   where nullif(btrim(coalesce(l.name, '')), '') is not null
     and exists (select 1 from public.clients c where c.email is not null and lower(c.email) = lower(btrim(l.email)) and c.tipo = 'persona') limit 1;
  if lead_sin is not null then
    r := r || pg_temp.ok(pg_temp.como('authenticated', adm, eadm, format('select (public.crm_lead_ficha_crear(%L)).client_id::text', lead_sin)),
                         'PT400:Este lead aún no tiene ficha de cliente%', '2.8 CRM con interruptor: no crea la ficha, manda a Clientes');
    update public.config_instancia set valor = 'false'::jsonb where clave = 'alta_exige_documento';
    r := r || pg_temp.ok(pg_temp.como('authenticated', adm, eadm, format('select (public.crm_lead_ficha_crear(%L)).ya_existia::text', lead_sin)), 'false', '2.9 CRM sin interruptor: crea como siempre');
    update public.config_instancia set valor = 'true'::jsonb where clave = 'alta_exige_documento';
  else
    r := r || 'SIN DATOS 2.8/2.9: no hay lead con nombre y email sin ficha' || E'\n';
  end if;
  if lead_con is not null then
    r := r || pg_temp.ok(pg_temp.como('authenticated', adm, eadm, format('select (public.crm_lead_ficha_crear(%L)).ya_existia::text', lead_con)), 'true', '2.10 CRM con interruptor y ficha existente: la devuelve igual');
  else
    r := r || 'SIN DATOS 2.10: no hay lead con ficha' || E'\n';
  end if;
  n := (length(r) - length(replace(r, 'FALLO', ''))) / 5;
  raise exception E'RES BLOQUE 2\n%FALLOS=%', r, n;
end $t$;

-- ─── BLOQUE 3: la retención (fechas forzadas dentro de la transacción) ─────────────────────────────────────────────
do $t$
declare a uuid; ea text; r text := ''; n int; j jsonb; c1 uuid; c2 uuid; c3 uuid; c4 uuid; c5 uuid; c6 uuid; cf uuid; cc uuid;
  viejo timestamptz := now() - interval '13 months'; i int; ids uuid[] := '{}'; x uuid; f1 text; f6 text;
begin
  select u.user_id, lower(u.email) into a, ea from public.usuarios u
   where u.activo and u.rol = 'agente' and u.user_id is not null and cardinality(coalesce(u.empresas, '{}')) > 0 order by u.email limit 1;
  r := r || pg_temp.ok((select valor::text from public.config_instancia where clave = 'kyc_meses_retencion'), '12', '3.0 la migración deja kyc_meses_retencion = 12');
  -- clientes de prueba (como postgres, con la fecha de alta forzada) y sus documentos
  for i in 1..6 loop
    insert into public.clients (full_name, email, phone, nationality, passport_number, tipo, kyc_status, propietario, created_at)
    values ('PRUEBA RETENCION ' || i, 'law558.' || i || '.' || substr(md5(random()::text), 1, 6) || '@example.invalid', '+34600000000', 'ES',
            'ZZ558' || i || upper(substr(md5(random()::text), 1, 5)), 'persona', case when i = 6 then 'verified' else 'pending' end, ea,
            case when i = 5 then now() - interval '2 months' else viejo end)
    returning id into x;
    ids := ids || x;
    insert into public.documents (client_id, doc_type, storage_path, status, uploaded_at, subido_por)
    values (x, 'passport', x || '/' || gen_random_uuid() || '.jpg', 'pending', case when i = 5 then now() - interval '2 months' else viejo end, a);
  end loop;
  c1 := ids[1]; c2 := ids[2]; c3 := ids[3]; c4 := ids[4]; c5 := ids[5]; c6 := ids[6];
  update public.clients set kyc_verificado_el = viejo where id = c6;
  insert into public.documents (client_id, doc_type, storage_path, status, uploaded_at) values (c2, 'signed_contract', c2 || '/' || gen_random_uuid() || '.pdf', 'pending', viejo);
  insert into public.portal_accesos (email, client_id) values ('law558.portal@example.invalid', c3);
  insert into public.reservations (client_id, property_slug) values (c4, 'prueba-law558');
  select storage_path into f1 from public.documents where client_id = c1;
  select storage_path into f6 from public.documents where client_id = c6;

  -- cliente real con factura / con contrato: la condición de referencias los deja fuera (sin tocar sus fechas: corte en el futuro)
  select c.id into cf from public.clients c where exists (select 1 from public.facturas f where f.client_id = c.id)
     and not exists (select 1 from public.contrato_compradores cc2 where cc2.client_id = c.id)
     and exists (select 1 from public.documents d where d.client_id = c.id and d.retirado_el is null and d.doc_type <> 'signed_contract')
     and not exists (select 1 from public.documents d where d.client_id = c.id and (d.doc_type = 'signed_contract' or d.contrato_id is not null or d.reservation_id is not null)) limit 1;
  select c.id into cc from public.clients c where exists (select 1 from public.contrato_compradores cc2 where cc2.client_id = c.id)
     and exists (select 1 from public.documents d where d.client_id = c.id and d.retirado_el is null and d.doc_type <> 'signed_contract')
     and not exists (select 1 from public.documents d where d.client_id = c.id and (d.doc_type = 'signed_contract' or d.contrato_id is not null or d.reservation_id is not null)) limit 1;
  if cf is not null then
    r := r || pg_temp.ok(public._kyc_retencion_candidato(cf, now() + interval '100 years')::text, 'false', '3.1 cliente con factura (y nada más que lo frene): no es candidato');
  else r := r || 'SIN DATOS 3.1: no hay cliente con factura, documento borrable y sin contrato' || E'\n'; end if;
  if cc is not null then
    r := r || pg_temp.ok(public._kyc_retencion_candidato(cc, now() + interval '100 years')::text, 'false', '3.2 cliente con contrato (y nada más que lo frene): no es candidato');
  else r := r || 'SIN DATOS 3.2: no hay cliente con contrato y documento borrable sin vínculo' || E'\n'; end if;

  -- dry: cuenta, no borra
  j := public.kyc_retencion(true);
  r := r || pg_temp.ok((j->>'candidatos') || '/' || (select string_agg(v, ',' order by v) from jsonb_array_elements_text(j->'clientes') v),
                       '2/' || (select string_agg(v::text, ',' order by v::text) from unnest(array[c1, c6]) v), '3.3 dry: candidatos = solo pasaporte viejo (c1) y verificado viejo (c6)');
  r := r || pg_temp.ok((select count(*)::text from public.documents where client_id in (c1, c6)), '2', '3.4 dry no borra nada');
  -- real
  j := public.kyc_retencion(false);
  r := r || pg_temp.ok((j->>'aplicados') || '/' || (select string_agg(v, ',' order by v) from jsonb_array_elements_text(j->'rutas') v),
                       '2/' || (select string_agg(v, ',' order by v) from unnest(array[f1, f6]) v), '3.5 real: 2 aplicados y devuelve SUS dos ficheros');
  r := r || pg_temp.ok((select count(*)::text from public.documents where client_id in (c1, c6)), '0', '3.6 se borran sus filas de documents');
  r := r || pg_temp.ok((select count(*)::text from public.clients where id in (c1, c6) and passport_number is not null and full_name is not null), '2', '3.7 la ficha se queda entera, con su pasaporte escrito');
  r := r || pg_temp.ok((select count(*)::text from public.documents where client_id in (c2, c3, c4, c5)), '5', '3.8 signed_contract, portal, reserva y reciente: intactos');
  r := r || pg_temp.ok((select kyc_status || '/' || coalesce(kyc_verificado_el::text, 'null') from public.clients where id = c6), 'submitted/null', '3.9 verificado → submitted, como documento_kyc_retira');
  r := r || pg_temp.ok((select string_agg(campo || '=' || valor_nuevo || '@' || corregido_por, ' | ' order by campo) from public.correcciones_datos where fila_id = c6),
                       'documentos_kyc=1 documentos borrados por retención@retencion-automatica | kyc_status=submitted@retencion-automatica', '3.10 una línea de correcciones por cliente (+ la del KYC), firmada retencion-automatica');
  r := r || pg_temp.ok((select count(*)::text from public.borrados b2 where b2.tabla = 'documents' and (b2.fila->>'client_id')::uuid = c1), '1', '3.11 la fila borrada queda en borrados (metadatos, no el fichero)');
  r := r || pg_temp.ok(public.kyc_retencion(false)->>'candidatos', '0', '3.12 una segunda pasada ya no encuentra nada');
  n := (length(r) - length(replace(r, 'FALLO', ''))) / 5;
  raise exception E'RES BLOQUE 3\n%FALLOS=%', r, n;
end $t$;

-- ─── BLOQUE 4: retención sin clave, mínimo 12 meses, tope 20 y sin parámetro de meses ─────────────────────────────
do $t$
declare ea text; r text := ''; n int; j jsonb; i int; x uuid; ids uuid[] := '{}';
begin
  select lower(u.email) into ea from public.usuarios u where u.activo and u.rol = 'agente' and u.user_id is not null limit 1;
  for i in 1..21 loop
    insert into public.clients (full_name, email, phone, nationality, passport_number, tipo, kyc_status, propietario, created_at)
    values ('PRUEBA TOPE ' || i, 'law558.tope.' || i || '.' || substr(md5(random()::text), 1, 6) || '@example.invalid', '+34600000000', 'ES',
            'ZZT' || i || upper(substr(md5(random()::text), 1, 6)), 'persona', 'pending', ea, now() - interval '13 months')
    returning id into x;
    ids := ids || x;
    insert into public.documents (client_id, doc_type, storage_path, status, uploaded_at) values (x, 'passport', x || '/' || gen_random_uuid() || '.jpg', 'pending', now() - interval '13 months');
  end loop;
  j := public.kyc_retencion(false);
  r := r || pg_temp.ok((j->>'aviso') || '/' || (j->>'aplicados'), 'mas_de_20_candidatos/0', '4.1 más de 20 candidatos: no borra NINGUNO y avisa');
  r := r || pg_temp.ok((select count(*)::text from public.documents where client_id = any (ids)), '21', '4.2 ... sus 21 documentos siguen');
  -- mínimo 12 meses aunque la clave diga menos: un cliente de 7 meses no es candidato con kyc_meses_retencion = 6
  update public.config_instancia set valor = '6'::jsonb where clave = 'kyc_meses_retencion';
  update public.clients set created_at = now() - interval '7 months' where id = any (ids);
  update public.documents set uploaded_at = now() - interval '7 months' where client_id = any (ids);
  j := public.kyc_retencion(true);
  r := r || pg_temp.ok((j->>'meses') || '/' || (j->>'candidatos'), '12/0', '4.3 kyc_meses_retencion = 6 se lee como 12: nada de 7 meses');
  -- sin la clave: no hace nada
  update public.config_instancia set clave = 'kyc_meses_retencion_apagada' where clave = 'kyc_meses_retencion';
  update public.clients set created_at = now() - interval '13 months' where id = any (ids[1:3]);
  update public.documents set uploaded_at = now() - interval '13 months' where client_id = any (ids[1:3]);
  j := public.kyc_retencion(false);
  r := r || pg_temp.ok(j::text, '{"activa": false}', '4.4 sin kyc_meses_retencion: no hace nada');
  r := r || pg_temp.ok((select count(*)::text from public.documents where client_id = any (ids)), '21', '4.5 ... ni un documento menos');
  -- los meses no se pueden pasar desde fuera
  r := r || pg_temp.ok(pg_temp.como('service_role', gen_random_uuid(), '', 'select public.kyc_retencion(false, 1)::text'), '42883:%', '4.6 kyc_retencion no admite un parámetro de meses');
  r := r || pg_temp.ok(pg_temp.como('authenticated', gen_random_uuid(), 'x@example.invalid', 'select public.kyc_retencion(true)::text'), '42501:%', '4.7 authenticated no ejecuta kyc_retencion');
  r := r || pg_temp.ok(pg_temp.como('authenticated', gen_random_uuid(), 'x@example.invalid', 'select public.cron_kyc_retencion_secret()'), '42501:%', '4.8 authenticated no lee el secreto del cron');
  n := (length(r) - length(replace(r, 'FALLO', ''))) / 5;
  raise exception E'RES BLOQUE 4\n%FALLOS=%', r, n;
end $t$;

-- ─── BLOQUE 5: barrido de pendientes y ficheros huérfanos ──────────────────────────────────────────────────────────
do $t$
declare a uuid; ea text; r text := ''; n int; j jsonb; vieja uuid; viva uuid; cli uuid; fv text; fw text; fh text; fc text;
begin
  select u.user_id, lower(u.email) into a, ea from public.usuarios u
   where u.activo and u.rol = 'agente' and u.user_id is not null and cardinality(coalesce(u.empresas, '{}')) > 0 order by u.email limit 1;
  insert into public.kyc_altas_pendientes (uid, creado_en) values (a, now() - interval '40 hours') returning id into vieja;
  insert into public.kyc_altas_pendientes (uid, creado_en) values (a, now() - interval '2 hours') returning id into viva;
  select id into cli from public.clients order by created_at limit 1;
  fv := vieja || '/' || gen_random_uuid() || '.jpg';                -- de una pendiente caducada: se barre
  fw := viva  || '/' || gen_random_uuid() || '.jpg';                -- de una pendiente viva (aunque el fichero sea viejo): no
  fh := gen_random_uuid() || '/' || gen_random_uuid() || '.pdf';    -- huérfano sin dueño: se barre
  fc := cli   || '/' || gen_random_uuid() || '.pdf';                -- en la carpeta de un cliente existente: no (eso es de kyc_sueltos_de)
  insert into storage.objects (bucket_id, name, created_at) values ('kyc', fv, now() - interval '39 hours'), ('kyc', fw, now() - interval '39 hours'),
                                                                   ('kyc', fh, now() - interval '50 hours'), ('kyc', fc, now() - interval '50 hours'),
                                                                   ('kyc', gen_random_uuid() || '/' || gen_random_uuid() || '.pdf', now() - interval '3 hours');  -- reciente: no
  j := public.kyc_barrido(true);
  r := r || pg_temp.ok((j->>'pendientes_caducadas') || '/' || (select string_agg(v, ',' order by v) from jsonb_array_elements_text(j->'rutas') v),
                       '1/' || (select string_agg(v, ',' order by v) from unnest(array[fv, fh]) v), '5.1 dry: 1 pendiente caducada y solo los dos ficheros sin dueño de más de 36 h');
  r := r || pg_temp.ok((select count(*)::text from public.kyc_altas_pendientes where id in (vieja, viva)), '2', '5.2 dry no borra pendientes');
  j := public.kyc_barrido(false);
  r := r || pg_temp.ok((select count(*)::text from public.kyc_altas_pendientes where id = vieja) || '/' || (select count(*) from public.kyc_altas_pendientes where id = viva), '0/1', '5.3 real: la caducada se va, la viva sigue');
  r := r || pg_temp.ok(pg_temp.como('authenticated', a, ea, 'select public.kyc_barrido(true)::text'), '42501:%', '5.4 authenticated no ejecuta kyc_barrido');
  n := (length(r) - length(replace(r, 'FALLO', ''))) / 5;
  raise exception E'RES BLOQUE 5\n%FALLOS=%', r, n;
end $t$;

-- ─── BLOQUE 6: permisos (consulta de solo lectura) ─────────────────────────────────────────────────────────────────
-- Esperado: la tabla sin NINGÚN privilegio para anon/authenticated/service_role (0 filas en la 1.ª); _cliente_crea y
-- _kyc_retencion_candidato sin execute para nadie; el resto de lo nuevo solo service_role; cliente_guarda y
-- crm_lead_ficha_crear como antes (authenticated + service_role); kyc_sueltos_de solo service_role.
-- select r, p from unnest(array['anon','authenticated','service_role']) r, unnest(array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER']) p
--  where has_table_privilege(r, 'public.kyc_altas_pendientes', p);
-- select f, r from unnest(array['public._cliente_crea(uuid,jsonb)','public._kyc_retencion_candidato(uuid,timestamptz)','public.kyc_alta_reserva(uuid,uuid)',
--        'public.kyc_alta_estado(uuid,uuid)','public.kyc_alta_descarta(uuid,uuid)','public.cliente_alta_con_documentos(uuid,uuid,jsonb,text[],date)',
--        'public.kyc_barrido(boolean)','public.kyc_retencion(boolean)','public.cron_kyc_retencion_secret()','public.cliente_guarda(uuid,jsonb)',
--        'public.crm_lead_ficha_crear(uuid)','public.kyc_sueltos_de(uuid)']) f, unnest(array['public','anon','authenticated','service_role']) r
--  where has_function_privilege(r, f::regprocedure, 'execute') order by 1, 2;
