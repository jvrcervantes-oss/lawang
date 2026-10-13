-- Prueba «el traspaso SIEMPRE arrastra todo» (13-oct-2026, migraciones 20261013143832_traspaso_cliente_arrastra_todo,
-- 20261013150447_traspaso_receptor_ve_lo_que_recibe 20261013150901_traspaso_solo_lo_del_cliente y 20261013153444_traspaso_bloquea_lo_que_mueve).
-- Casos del revisor (13-oct): K* cocomprador con factura de otro client_id (no se mueve), R7 admin_empresa sin la empresa de una factura
-- sin cliente colgada de su contrato, R8 receptor de otra empresa con un admin GLOBAL, M* la marca puesta como authenticated.
-- Se pega DESPUES de la migracion en la MISMA peticion (ensayo), o sola cuando ya esta aplicada. Sin rastro: acaba en raise y todo se deshace.
-- Debe terminar con «FALLOS=0». Unico rastro que el rollback no deshace: dos numeros de la secuencia CLI- de clients (las fichas de prueba);
-- contratos y facturas llevan numero PRB- explicito y no tocan sus secuencias fiscales.
-- Reproduce el caso real (RP00261 de IVAN REBOLLO MARCAS): ficha con dueno NULL, un contrato de OTRO autor, uno FIRMADO y una factura SIN autor;
-- lo hace un admin_empresa (antes solo super) con SU sesion, y se comprueba como el receptor (puede_ver_contrato y la policy real de facturas).
-- destructivo-ok: prueba en transaccion que termina en raise (rollback)
create temp table _tp (et text primary key, uid uuid, em text);
create or replace function pg_temp.l(c boolean, t text) returns text language sql as $f$
  select case when coalesce(c, false) then 'OK    ' else 'FALLO ' end || t || E'\n'
$f$;
create or replace function pg_temp.val(p_uid uuid, p_email text, p_sql text) returns text language plpgsql as $f$
declare t text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'email', p_email)::text, true);
  execute 'set local role authenticated';
  begin execute p_sql into t;
  exception when others then t := 'ERR' || sqlstate || ':' || left(sqlerrm, 200); end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return t;
end $f$;
create or replace function pg_temp.err(t text) returns text language sql immutable as $f$ select case when t like 'ERR%' then substr(t, 4, 5) end $f$;
-- foto de lo escrito en la transaccion (pg_stat_xact): sirve para ver QUE tablas toca una llamada
create or replace function pg_temp.foto() returns jsonb language sql as $f$
  select coalesce(jsonb_object_agg(relname, n_tup_ins + n_tup_upd + n_tup_del), '{}') from pg_stat_xact_all_tables where schemaname = 'public'
$f$;

insert into _tp select 'jv', user_id, email from public.usuarios where email = 'jvr.cervantes@gmail.com';
insert into _tp
  select (array['A', 'B', 'R', 'X', 'G'])[rn], user_id, email
    from (select user_id, email, row_number() over (order by email) rn
            from (select user_id, email from public.usuarios where activo and rol = 'agente' order by email limit 5) q) z;

do $todo$
declare
  r text := ''; v text; n bigint; fallos int; f0 jsonb; f1 jsonb; tocadas text;
  jv _tp; a _tp; b _tp; rc _tp; x _tp; g _tp;
  pL uuid; pLn text; soc text; cl uuid; cl2 uuid; c1 uuid; c2 uuid; c3 uuid; fa uuid; fb uuid; fc uuid; fs uuid; res record;
  pS uuid; socS text; kR uuid; clR uuid; fR uuid; autR text;
begin
  select * into jv from _tp where et = 'jv'; select * into a from _tp where et = 'A'; select * into b from _tp where et = 'B';
  select * into rc from _tp where et = 'R'; select * into x from _tp where et = 'X'; select * into g from _tp where et = 'G';
  r := r || pg_temp.l(jv.uid is not null and g.uid is not null, 'P0 hay propietario y 5 agentes con los que montar las personas');
  select id, nombre into pL, pLn from public.proyectos where activo and public.empresa_de_proyecto(id) = 'lawang' order by nombre limit 1;
  select clave into soc from public.sociedades where clave = 'tepi_sungai';
  r := r || pg_temp.l(pL is not null and soc is not null, 'P1 hay proyecto activo de Lawang y su sociedad');

  -- Personas (las deshace el raise final), fijadas con la sesion del propietario
  perform set_config('request.jwt.claims', json_build_object('sub', jv.uid, 'role', 'authenticated', 'email', jv.em)::text, true);
  update public.usuarios set rol = 'admin_empresa', ambito = 'empresa', empresas = '{lawang}', proyectos = '{}', proyectos_supervisados = '{}' where user_id = a.uid;
  update public.usuarios set rol = 'admin_empresa', ambito = 'empresa', empresas = '{sandal_woods}', proyectos = '{}', proyectos_supervisados = '{}' where user_id = b.uid;
  update public.usuarios set rol = 'agente', ambito = 'global', empresas = '{lawang}', proyectos = array[pL], proyectos_supervisados = '{}', herramientas = '{contratos,facturas}' where user_id in (rc.uid, x.uid, g.uid);
  perform set_config('request.jwt.claims', '', true);

  -- Fixture: la ficha SIN dueno, otra ficha que comparte c1, c1 de OTRO autor (X), c2 FIRMADO (de X), fa SIN autor (sobre c1), fb recibi ANULADO (de X, sobre c2)
  insert into public.clients (full_name) values ('PRB Traspaso Arrastra') returning id into cl;
  insert into public.clients (full_name, propietario) values ('PRB Cocomprador', x.em) returning id into cl2;
  update public.clients set propietario = null where id = cl;
  insert into public.contratos (tipo, numero, proyecto_id, proyecto_nombre, moneda, creado_por, bloqueado, datos)
  values ('contrato_general', 'PRB-TR-C1', pL, pLn, 'IDR', x.em, false, jsonb_build_object('fields', jsonb_build_object('proyecto_nombre', pLn))) returning id into c1;
  insert into public.contratos (tipo, numero, proyecto_id, proyecto_nombre, moneda, creado_por, bloqueado, datos)
  values ('contrato_general', 'PRB-TR-C2', pL, pLn, 'IDR', x.em, true, jsonb_build_object('fields', jsonb_build_object('proyecto_nombre', pLn))) returning id into c2;
  insert into public.contrato_compradores (contrato_id, client_id, rol) values (c1, cl, 'adquiriente_1'), (c1, cl2, 'adquiriente_2'), (c2, cl, 'adquiriente_1');
  insert into public.facturas (tipo, numero, sociedad, client_id, contrato_id, proyecto_id, total, moneda, datos, creado_por)
  values ('proforma', 'PRB-TR-F1', soc, cl, c1, pL, 10, (select moneda from public.contratos where id = c1), '{}', null) returning id into fa;
  insert into public.facturas (tipo, numero, sociedad, client_id, contrato_id, proyecto_id, total, moneda, datos, creado_por, anulada, justificante_path)
  values ('recibi', 'PRB-TR-R1', soc, cl, c2, pL, 5, (select moneda from public.contratos where id = c2), '{}', x.em, true, 'prb/traspaso.pdf') returning id into fb;
  select count(*) into n from public.facturas where id in (fa, fb) and ((id = fa and creado_por is null) or (id = fb and creado_por = x.em));
  r := r || pg_temp.l(n = 2 and (select propietario from public.clients where id = cl) is null, 'P2 fixture: ficha sin dueno, c1 de X (compartido), c2 firmado, factura sin autor, recibi anulado');
  -- fc: factura del COCOMPRADOR (client_id = cl2) colgada de c1 → no se mueve. c3: contrato donde cl es solo adquiriente_2 (sin adquiriente_1), y fs:
  -- factura SIN cliente sobre c3 pero de un proyecto de Sandal Woods → el admin_empresa de Lawang no puede traspasar mientras cuelgue de ahi.
  select id into pS from public.proyectos where activo and public.empresa_de_proyecto(id) = 'sandal_woods' order by nombre limit 1;
  select sociedad_clave into socS from public.empresas where clave = 'sandal_woods';
  -- (recibi anulado: una proforma chocaria con facturas_proforma_activa_por_contrato, c1 ya tiene la suya)
  insert into public.facturas (tipo, numero, sociedad, client_id, contrato_id, proyecto_id, total, moneda, datos, creado_por, anulada, justificante_path)
  values ('recibi', 'PRB-TR-R3', soc, cl2, c1, pL, 7, (select moneda from public.contratos where id = c1), '{}', x.em, true, 'prb/traspaso3.pdf') returning id into fc;
  insert into public.contratos (tipo, numero, proyecto_id, proyecto_nombre, moneda, creado_por, bloqueado, datos)
  values ('contrato_general', 'PRB-TR-C3', pL, pLn, 'IDR', x.em, false, jsonb_build_object('fields', jsonb_build_object('proyecto_nombre', pLn))) returning id into c3;
  insert into public.contrato_compradores (contrato_id, client_id, rol) values (c3, cl, 'adquiriente_2');
  insert into public.facturas (tipo, numero, sociedad, client_id, contrato_id, proyecto_id, total, moneda, datos, creado_por)
  values ('proforma', 'PRB-TR-FS', socS, null, c3, pS, 3, (select moneda from public.contratos where id = c3), '{}', x.em) returning id into fs;
  r := r || pg_temp.l((select client_id from public.facturas where id = fs) is null and public.empresa_de_factura(fs) = 'sandal_woods'
                      and (select client_id from public.facturas where id = fc) = cl2,
                      'P3 fixture: fc del cocomprador sobre c1; fs sin cliente sobre c3 y de Sandal Woods (' || coalesce(public.empresa_de_factura(fs), '∅') || ')');

  -- ANTES: el receptor no ve nada de esto
  v := pg_temp.val(rc.uid, rc.em, format('select (public.puede_ver_contrato(%L) or public.puede_ver_contrato(%L))::text', c1, c2));
  r := r || pg_temp.l(v = 'false', 'A0 antes, el receptor no ve c1 ni c2 (' || v || ')');
  v := pg_temp.val(rc.uid, rc.em, format('select count(*)::text from public.facturas where id in (%L, %L)', fa, fb));
  r := r || pg_temp.l(v = '0', 'A1 antes, el receptor no lee la factura ni el recibi (policy real) (' || v || ')');

  -- RECHAZOS
  v := pg_temp.val(g.uid, g.em, format('select (public.traspasar_cliente_con_documentos(%L, %L, ''PRB motivo'')).contratos_movidos::text', cl, rc.em));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'R1 un agente sin rol admin no traspasa: 42501 (' || left(v, 90) || ')');
  v := pg_temp.val(b.uid, b.em, format('select (public.traspasar_cliente_con_documentos(%L, %L, ''PRB motivo'')).contratos_movidos::text', cl, b.em));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'R2 un admin_empresa de OTRA empresa (Sandal Woods) no traspasa un cliente de Lawang: 42501 (' || left(v, 90) || ')');
  v := pg_temp.val(a.uid, a.em, format('select (public.traspasar_cliente_con_documentos(%L, %L, ''  '')).contratos_movidos::text', cl, rc.em));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'R3 sin motivo no se traspasa: 22023 (' || left(v, 90) || ')');
  v := pg_temp.val(a.uid, a.em, format('select (public.traspasar_cliente_con_documentos(%L, %L, ''PRB motivo'')).contratos_movidos::text', cl, 'nadie@ejemplo.invalid'));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'R4 a quien no es del equipo no se traspasa: 22023 (' || left(v, 90) || ')');
  v := pg_temp.val(a.uid, a.em, format('select (public.traspasar_cliente_con_documentos(%L, %L, ''PRB motivo'')).contratos_movidos::text', cl, b.em));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'R5 un admin_empresa no traspasa a alguien que no es de su empresa: 22023 (' || left(v, 90) || ')');
  select count(*) into n from public.contratos where id in (c1, c2) and creado_por = x.em;
  r := r || pg_temp.l(n = 2 and (select propietario from public.clients where id = cl) is null, 'R6 tras los rechazos no se ha movido nada');
  -- R7: admin_de_cliente le deja pasar (todos los contratos son de Lawang y fs no tiene client_id), pero fs es de Sandal Woods → 42501 nombrando fs
  v := pg_temp.val(a.uid, a.em, format('select (public.traspasar_cliente_con_documentos(%L, %L, ''PRB motivo'')).contratos_movidos::text', cl, rc.em));
  r := r || pg_temp.l(pg_temp.err(v) = '42501' and v like '%PRB-TR-FS%sandal_woods%', 'R7 un admin_empresa de Lawang no traspasa si se moveria una factura sin cliente de Sandal Woods: 42501 (' || left(v, 140) || ')');
  -- (admin_de_cliente no se ejecuta como authenticated: se mira con los claims de A, como lo ve la funcion DEFINER)
  perform set_config('request.jwt.claims', json_build_object('sub', a.uid, 'role', 'authenticated', 'email', a.em)::text, true);
  r := r || pg_temp.l(public.admin_de_cliente(cl, true), 'R7b ... y es justo el hueco: admin_de_cliente solo le daba el si');
  perform set_config('request.jwt.claims', '', true);
  -- c3 deja de ser de cl (sin borrar nada: facturas_contrato_obligatorio no deja soltar fs) para que el resto de la prueba trabaje sobre Lawang
  update public.contrato_compradores set client_id = cl2 where contrato_id = c3 and client_id = cl;
  -- R8: un admin GLOBAL tampoco traspasa a alguien que no podria verlo (antes se saltaba la comprobacion del receptor entera)
  v := pg_temp.val(jv.uid, jv.em, format('select (public.traspasar_cliente_con_documentos(%L, %L, ''PRB motivo'')).contratos_movidos::text', cl, b.em));
  r := r || pg_temp.l(pg_temp.err(v) = '22023' and v like '%no podria ver lo que recibe%', 'R8 un admin global no traspasa a un admin_empresa solo de Sandal Woods: 22023 «no podria ver» (' || left(v, 160) || ')');
  -- M: la marca puesta como authenticated no abre nada: authenticated no escribe en contratos ni facturas (42501 antes de cualquier trigger) y ninguna
  -- funcion de public hace set_config con nombre variable; solo las dos que deben ponen app.via_traspaso_autor
  v := pg_temp.val(x.uid, x.em, format('with u as (update public.contratos set creado_por = %L where id = %L returning 1) select set_config(''app.via_traspaso_autor'', ''on'', true) || count(*)::text from u', x.em, c1));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'M1 como authenticated, con la marca puesta, un UPDATE directo de contratos: 42501 (' || left(v, 90) || ')');
  v := pg_temp.val(x.uid, x.em, format('with u as (update public.facturas set creado_por = %L where id = %L returning 1) select set_config(''app.via_traspaso_autor'', ''on'', true) || count(*)::text from u', x.em, fa));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'M2 ... y de facturas: 42501 (' || left(v, 90) || ')');
  select count(*) into n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
     and pg_get_functiondef(p.oid) ~* 'set_config\s*\(\s*[^''\s]';
  r := r || pg_temp.l(n = 0, 'M3 ninguna funcion de public llama a set_config con un nombre que no sea literal (' || n || ')');
  select string_agg(p.proname, ',' order by p.proname) into v from pg_proc p where p.pronamespace = 'public'::regnamespace
     and pg_get_functiondef(p.oid) ~ 'set_config\(''app\.via_traspaso_autor'', ''on''';
  r := r || pg_temp.l(v = 'reasigna_autor,traspasar_cliente_con_documentos', 'M4 solo reasigna_autor y el traspaso encienden la marca (' || coalesce(v, '-') || ')');
  r := r || pg_temp.l(coalesce(current_setting('app.via_traspaso_autor', true), '') <> 'on', 'M5 la marca no se quedo encendida tras los intentos');

  -- EL TRASPASO: lo hace el admin_empresa de Lawang, con el email del receptor en MAYUSCULAS
  f0 := pg_temp.foto();
  v := pg_temp.val(a.uid, a.em, format('select row_to_json(t)::text from public.traspasar_cliente_con_documentos(%L, %L, ''PRB Ariadna lleva este cliente'') t', cl, upper(rc.em)));
  f1 := pg_temp.foto();
  r := r || pg_temp.l(v !~ '^ERR', 'T0 el admin_empresa de Lawang traspasa con su sesion (' || left(v, 330) || ')');
  if v !~ '^ERR' then
    r := r || pg_temp.l((v::jsonb ->> 'contratos_movidos')::int = 2 and (v::jsonb ->> 'facturas_movidas')::int = 2
                        and (v::jsonb ->> 'facturas_movidas_anuladas')::int = 1 and (v::jsonb ->> 'propietario_anterior') is null
                        and (v::jsonb ->> 'contratos_omitidos_firmados')::int + (v::jsonb ->> 'contratos_omitidos_otro_autor')::int + (v::jsonb ->> 'contratos_omitidos_sin_autor')::int
                          + (v::jsonb ->> 'facturas_omitidas_sin_autor')::int = 0
                        and (v::jsonb ->> 'facturas_omitidas_otro_autor')::int = 1,
                        'T1 la devolucion (mismas columnas que antes): 2 contratos, 2 documentos (1 anulado), dueno anterior NULL, 1 factura de otro comprador omitida');
  end if;
  r := r || pg_temp.l((select creado_por from public.facturas where id = fc) = x.em, 'K1 la factura del COCOMPRADOR (client_id de otro) sigue con su autor');
  r := r || pg_temp.l((select creado_por from public.contratos where id = c1) = lower(rc.em), 'K2 ... aunque el contrato compartido c1 si se ha movido');
  r := r || pg_temp.l(not exists (select 1 from public.correcciones_datos where fila_id = fc and motivo = 'PRB Ariadna lleva este cliente'), 'K3 ... y no deja rastro de traspaso');
  select count(*) into n from public.contratos where id in (c1, c2) and creado_por = lower(rc.em);
  r := r || pg_temp.l(n = 2, 'T2 c1 (de otro autor) y c2 (FIRMADO) son ahora del receptor, en minusculas (' || n || ')');
  select count(*) into n from public.facturas where id in (fa, fb) and creado_por = lower(rc.em);
  r := r || pg_temp.l(n = 2, 'T3 la factura SIN autor y el recibi ANULADO son del receptor: fija_autor no lo deshizo aunque quien traspasa no es admin global (' || n || ')');
  r := r || pg_temp.l((select propietario from public.clients where id = cl) = lower(rc.em), 'T4 la ficha es del receptor');
  select count(*) into n from public.correcciones_datos
   where (tabla, fila_id, campo) in (('clients', cl, 'propietario'), ('contratos', c1, 'creado_por'), ('contratos', c2, 'creado_por'), ('facturas', fa, 'creado_por'), ('facturas', fb, 'creado_por'))
     and motivo = 'PRB Ariadna lleva este cliente' and corregido_por = a.em and valor_nuevo = lower(rc.em);
  r := r || pg_temp.l(n = 5, 'T5 una fila de rastro por cada cosa movida, con motivo y quien (' || n || ')');
  select count(*) into n from public.correcciones_datos
   where ((fila_id = c1 and valor_anterior = x.em) or (fila_id = fa and valor_anterior is null) or (fila_id = cl and valor_anterior is null)) and motivo = 'PRB Ariadna lleva este cliente';
  r := r || pg_temp.l(n = 3, 'T6 el rastro guarda el autor REAL de antes (X en c1, nadie en la factura y en la ficha) (' || n || ')');
  select count(*) into n from public.contrato_eventos where contrato_id = c2 and evento = 'editado_estando_firmado';
  r := r || pg_temp.l(n = 1, 'T7 el firmado deja su evento editado_estando_firmado en contrato_eventos (' || n || ')');
  select string_agg(k || '+' || ((f1 ->> k)::int - coalesce((f0 ->> k)::int, 0)), ' ' order by k) into tocadas
    from jsonb_object_keys(f1) k where (f1 ->> k)::int <> coalesce((f0 ->> k)::int, 0);
  r := r || pg_temp.l(tocadas !~ '(unidades|comisiones|comision_admin|solicitudes_pago|notificaciones)', 'T8 el traspaso no toca unidades, comisiones, solicitudes de pago ni avisos (escrito: ' || coalesce(tocadas, '-') || ')');
  r := r || pg_temp.l(coalesce(current_setting('app.via_traspaso_autor', true), '') <> 'on', 'T9 la marca app.via_traspaso_autor queda apagada al salir');

  -- DESPUES: el receptor, con SU sesion
  v := pg_temp.val(rc.uid, rc.em, format('select (public.puede_ver_contrato(%L) and public.puede_ver_contrato(%L))::text', c1, c2));
  r := r || pg_temp.l(v = 'true', 'V1 el receptor ve c1 y c2 (puede_ver_contrato con su sesion) (' || v || ')');
  v := pg_temp.val(rc.uid, rc.em, format('select count(*)::text from public.facturas where id in (%L, %L)', fa, fb));
  r := r || pg_temp.l(v = '2', 'V2 el receptor lee la factura y el recibi por la policy real de facturas (' || v || ')');

  -- REPETIR: todo ya es suyo → 22023; y si queda algo de otro (ficha ya suya), lo arrastra sin tocar la ficha
  v := pg_temp.val(a.uid, a.em, format('select (public.traspasar_cliente_con_documentos(%L, %L, ''PRB otra vez'')).contratos_movidos::text', cl, rc.em));
  r := r || pg_temp.l(pg_temp.err(v) = '22023', 'S1 si ficha y documentos ya son todos suyos: 22023 (' || left(v, 90) || ')');
  update public.contratos set creado_por = x.em where id = c1;
  v := pg_temp.val(a.uid, a.em, format('select row_to_json(t)::text from public.traspasar_cliente_con_documentos(%L, %L, ''PRB recupera lo que falta'') t', cl, rc.em));
  r := r || pg_temp.l(v !~ '^ERR' and (v::jsonb ->> 'propietario_anterior') = lower(rc.em) and (v::jsonb ->> 'contratos_movidos')::int = 1
                      and (v::jsonb ->> 'facturas_movidas')::int = 0
                      and not exists (select 1 from public.correcciones_datos where fila_id = cl and motivo = 'PRB recupera lo que falta'),
                      'S2 con la ficha ya suya, arrastra lo que faltaba (1 contrato) sin tocar la ficha (' || left(v, 260) || ')');

  -- cliente_traspasa (pantalla vieja): envoltorio, arrastra lo mismo
  v := pg_temp.val(a.uid, a.em, format('select (public.cliente_traspasa(%L, %L, null) = %L)::text', cl, x.em, cl));
  r := r || pg_temp.l(v = 'true', 'W1 cliente_traspasa (pantalla vieja, sin motivo) sigue funcionando (' || left(v, 90) || ')');
  select count(*) into n from public.contratos where id in (c1, c2) and creado_por = lower(x.em);
  select n + count(*) into n from public.facturas where id in (fa, fb) and creado_por = lower(x.em);
  r := r || pg_temp.l(n = 4 and (select propietario from public.clients where id = cl) = lower(x.em), 'W2 ... y tambien arrastra contratos y facturas (' || n || ')');
  v := pg_temp.val(g.uid, g.em, format('select public.cliente_traspasa(%L, %L, ''PRB'')::text', cl, rc.em));
  r := r || pg_temp.l(pg_temp.err(v) = '42501', 'W3 cliente_traspasa conserva la puerta: un agente, 42501 (' || left(v, 90) || ')');

  -- CASO REAL (13-oct): PRO00218 cuelga de RP00208 con el client_id de OTRO comprador. Se traspasa un comprador de RP00208 que no es el de PRO00218
  -- (lo hace el propietario, admin global, a si mismo: ese comprador tambien tiene CC00117 de Sandal Woods, y R solo es de Lawang, asi que
  -- con R el receptor se rechazaria, con razon) y PRO00218 no se mueve. Rollback: no queda nada.
  select f.id, f.contrato_id, f.creado_por into fR, kR, autR from public.facturas f where f.numero = 'PRO00218';
  select cc.client_id into clR from public.contrato_compradores cc join public.facturas f on f.id = fR
   where cc.contrato_id = kR and cc.client_id <> f.client_id order by cc.rol limit 1;
  if clR is null then
    r := r || pg_temp.l(false, 'K4 PRO00218 / RP00208 ya no tiene el caso (factura de otro comprador): revisar la prueba');
  else
    v := pg_temp.val(jv.uid, jv.em, format('select row_to_json(t)::text from public.traspasar_cliente_con_documentos(%L, %L, ''PRB caso real'') t', clR, jv.em));
    r := r || pg_temp.l(v !~ '^ERR' and (v::jsonb ->> 'facturas_omitidas_otro_autor')::int >= 1
                        and (select creado_por from public.facturas where id = fR) is not distinct from autR
                        and (select lower(creado_por) from public.contratos where id = kR) = lower(jv.em),
                        'K4 caso real: RP00208 pasa al receptor y PRO00218 (de otro comprador) se queda con su autor (' || left(v, 200) || ')');
  end if;

  -- EXPOSICION
  select count(*) into n from pg_proc p
   where p.oid in ('public.traspasar_cliente_con_documentos(uuid,text,text)'::regprocedure, 'public.cliente_traspasa(uuid,text,text)'::regprocedure)
     and p.prosecdef and 'search_path=""' = any (p.proconfig)
     and has_function_privilege('authenticated', p.oid, 'execute') and has_function_privilege('service_role', p.oid, 'execute')
     and not has_function_privilege('anon', p.oid, 'execute');
  r := r || pg_temp.l(n = 2, 'E1 las dos: DEFINER, search_path vacio, authenticated y service_role si, anon no (' || n || ')');

  fallos := (select count(*) from regexp_matches(r, 'FALLO', 'g'));
  raise exception E'INFORME TRASPASO ARRASTRA TODO\n%FALLOS=%', r, fallos;
end $todo$;
