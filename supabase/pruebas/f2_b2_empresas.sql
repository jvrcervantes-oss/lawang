-- Prueba del bloque 2 (DINERO) de la Fase 2 (8-oct-2026): facturas, recibis, proformas, solicitudes de pago y retenciones, gastos, proveedores, bancos, cuentas de cobro y sociedades por empresa.
-- (Los documentos de fixture llevan created_at de enero: la regla «una factura nueva exige contrato» solo vale para las creadas desde el 12-ago; asi se pueden crear sin contrato dentro del rollback.)
-- Se ejecuta DESPUES de las migraciones 20261008200000..206000 (o pegada tras ellas en la misma peticion para ensayarlas sin rastro). Todo dentro de una transaccion que acaba en raise (rollback).
-- NO crea usuarios: convierte fichas existentes dentro de la transaccion (como f2_2b_empresas.sql). Las fixtures (facturas con numero explicito para no gastar la numeracion, gastos,
--   proveedores, movimientos, lineas, logs) se insertan como postgres dentro del mismo rollback.
-- Personas:  ya = admin_empresa/lawang CON casillas · cr = super_admin_empresa/sandal_woods SIN casillas · ad4 = admin_empresa con las dos CON casillas · ad0 = admin_empresa/lawang SIN casillas
--            ctl = agente de control (no se toca) · ar = agente con empresas={lawang} (alcance restringido) · gad = admin global no super · jv = propietario (super global)
-- Cada caso corre en su propio subtransaccion: «ok» = la llamada pasa; «42501» = rechazada; «no42501» = pasa la puerta (puede fallar mas adelante por otra regla del dato, p.ej. el tope de cadena o el justificante);
-- «n:<numero>» = cuenta de filas, «le:<numero>» = como mucho esas filas; persona con «!» (p.ej. 'ya!') = se llama como postgres con sus claims (para funciones privadas, p.ej. _retencion_puerta, que authenticated no puede ejecutar).
-- Nota: solicitud_pago_retencion_guarda/_rectifica no tienen EXECUTE para authenticated hoy (reducir exposicion: sin llamador en pantalla); la puerta se prueba por _retencion_puerta. Debe terminar con «FALLOS=0».
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); borra solo proformas de fixture (numero TESTB2-*) dentro de la prueba
do $t$
declare
  per jsonb := '{}'::jsonb;
  pe record; uid uuid;
  jv uuid; ya uuid; cr uuid; ad4 uuid; ad0 uuid; ctl uuid; ar uuid; gad uuid;
  pl uuid; ps uuid; pk uuid; cl uuid; cs uuid; nl text; ns text; ml text; ms text;
  soc_l text; soc_s text; soc_ltd text; cat text;
  f_pl uuid; f_ps uuid; f_pk uuid; f_pl2 uuid; f_ps2 uuid; f_pl3 uuid; f_pl4 uuid; f_al uuid; f_as uuid; f_fl uuid; f_fs uuid; f_fl2 uuid; f_fs2 uuid;
  s_l uuid; s_s uuid;
  g_l uuid; g_s uuid; g_ltd uuid; g_pl uuid; pv_l uuid; pv_s uuid; pv_g uuid;
  m_l uuid; m_s uuid; m_n uuid; lin_s bigint;
  cs_ids jsonb := '[]'::jsonb; c jsonb; res text; n bigint; r text := ''; fallos int := 0; ex text; ok boolean; sub text; mail text;
  hoy text := to_char(current_date, 'YYYY-MM-DD');
  pay_l text; pay_s text;
begin
  select user_id into jv from public.usuarios where email = 'jvr.cervantes@gmail.com';
  perform set_config('request.jwt.claims', json_build_object('sub', jv, 'role', 'authenticated', 'email', 'jvr.cervantes@gmail.com')::text, true);
  for pe in select * from (values
      ('ya',  'yanayjefferson@gmail.com',      'admin_empresa',       'empresa', '{lawang}',              '{facturas,gastos,bancos,comisiones}'),
      ('cr',  'cris.blueiestates@gmail.com',   'super_admin_empresa', 'empresa', '{sandal_woods}',        '{}'),
      ('ad4', 'adenovit.b@gmail.com',          'admin_empresa',       'empresa', '{lawang,sandal_woods}', '{facturas,gastos,bancos,comisiones}'),
      ('ad0', 'dortegag@gmail.com',            'admin_empresa',       'empresa', '{lawang}',              '{}')) v(k, email, rol, amb, emps, herr) loop
    update public.usuarios set rol = pe.rol, ambito = pe.amb, empresas = pe.emps::text[], proyectos = '{}', proyectos_supervisados = '{}',
           herramientas = pe.herr::text[], tipos_contrato = '{}' where email = pe.email returning user_id into uid;
    per := per || jsonb_build_object(pe.k, jsonb_build_object('sub', uid, 'email', pe.email));
  end loop;
  select user_id into ctl from public.usuarios where email = 'eduxzone@gmail.com';
  select user_id into ar from public.usuarios where email = 'santiator97@gmail.com';
  update public.usuarios set empresas = '{lawang}' where user_id = ar;
  select user_id into gad from public.usuarios where email = 'balianhills@gmail.com';
  per := per || jsonb_build_object('ctl', jsonb_build_object('sub', ctl, 'email', 'eduxzone@gmail.com'),
                                    'ar',  jsonb_build_object('sub', ar,  'email', 'santiator97@gmail.com'),
                                    'gad', jsonb_build_object('sub', gad, 'email', 'balianhills@gmail.com'),
                                    'jv',  jsonb_build_object('sub', jv,  'email', 'jvr.cervantes@gmail.com'));

  select e2.sociedad_clave into soc_l from public.empresas e2 where e2.clave = 'lawang';
  select e2.sociedad_clave into soc_s from public.empresas e2 where e2.clave = 'sandal_woods';
  select s.clave into soc_ltd from public.sociedades s where s.activa and not exists (select 1 from public.empresas x where x.sociedad_clave = s.clave) limit 1;
  select pr.id into pl from public.proyectos pr where pr.empresa = 'lawang' order by pr.nombre limit 1;
  select pr.id into ps from public.proyectos pr where pr.empresa = 'sandal_woods' order by pr.nombre limit 1;
  select pr.id into pk from public.proyectos pr where pr.empresa is null order by pr.nombre limit 1;
  select c1.id, c1.numero into cl, nl from public.contratos c1 join public.proyectos pr on pr.id = c1.proyecto_id where pr.empresa = 'lawang' and c1.contrato_padre_id is null order by c1.created_at desc limit 1;
  select c1.id, c1.numero into cs, ns from public.contratos c1 join public.proyectos pr on pr.id = c1.proyecto_id where pr.empresa = 'sandal_woods' and c1.contrato_padre_id is null order by c1.created_at desc limit 1;
  select nombre into ml from public.proyectos where id = pl;
  select nombre into ms from public.proyectos where id = ps;
  select g.clave into cat from public.gasto_categorias g order by g.orden limit 1;
  if soc_ltd is null then r := r || 'AVISO sin sociedad sin empresa activa: se omiten los casos de sociedad HK' || E'\n'; end if;

  reset role;
  insert into public.facturas (numero, tipo, sociedad, proyecto_id, total, moneda, fecha_emision, creado_por, created_at) values
    ('TESTB2-PL', 'proforma', soc_l, pl, 11, 'EUR', current_date, 'ajeno@test.b2', '2026-01-01') returning id into f_pl;
  insert into public.facturas (numero, tipo, sociedad, proyecto_id, total, moneda, fecha_emision, creado_por, created_at) values
    ('TESTB2-PL2', 'proforma', soc_l, pl, 12, 'EUR', current_date, 'ajeno@test.b2', '2026-01-01') returning id into f_pl2;
  insert into public.facturas (numero, tipo, sociedad, proyecto_id, total, moneda, fecha_emision, creado_por, created_at) values
    ('TESTB2-PL3', 'proforma', soc_l, pl, 13, 'EUR', current_date, 'ajeno@test.b2', '2026-01-01') returning id into f_pl3;
  insert into public.facturas (numero, tipo, sociedad, proyecto_id, total, moneda, fecha_emision, creado_por, created_at) values
    ('TESTB2-PL4', 'proforma', soc_l, pl, 14, 'EUR', current_date, 'ajeno@test.b2', '2026-01-01') returning id into f_pl4;
  insert into public.facturas (numero, tipo, sociedad, proyecto_id, total, moneda, fecha_emision, creado_por, created_at) values
    ('TESTB2-PS', 'proforma', soc_s, ps, 21, 'EUR', current_date, 'ajeno@test.b2', '2026-01-01') returning id into f_ps;
  insert into public.facturas (numero, tipo, sociedad, proyecto_id, total, moneda, fecha_emision, creado_por, created_at) values
    ('TESTB2-PS2', 'proforma', soc_s, ps, 22, 'EUR', current_date, 'ajeno@test.b2', '2026-01-01') returning id into f_ps2;
  insert into public.facturas (numero, tipo, sociedad, proyecto_id, total, moneda, fecha_emision, creado_por, created_at) values
    ('TESTB2-PK', 'proforma', soc_l, null, 31, 'EUR', current_date, 'ajeno@test.b2', '2026-01-01') returning id into f_pk;
  insert into public.facturas (numero, tipo, sociedad, proyecto_id, total, moneda, fecha_emision, creado_por, anulada, created_at) values
    ('TESTB2-AL', 'proforma', soc_l, pl, 41, 'EUR', current_date, 'ajeno@test.b2', true, '2026-01-01') returning id into f_al;
  insert into public.facturas (numero, tipo, sociedad, proyecto_id, total, moneda, fecha_emision, creado_por, anulada, created_at) values
    ('TESTB2-AS', 'proforma', soc_s, ps, 42, 'EUR', current_date, 'ajeno@test.b2', true, '2026-01-01') returning id into f_as;
  insert into public.facturas (numero, tipo, sociedad, proyecto_id, total, moneda, fecha_emision, creado_por, created_at) values
    ('TESTB2-FL', 'factura', soc_l, pl, 51, 'EUR', current_date, 'ajeno@test.b2', '2026-01-01') returning id into f_fl;
  insert into public.facturas (numero, tipo, sociedad, proyecto_id, total, moneda, fecha_emision, creado_por, created_at) values
    ('TESTB2-FL2', 'factura', soc_l, pl, 52, 'EUR', current_date, 'ajeno@test.b2', '2026-01-01') returning id into f_fl2;
  insert into public.facturas (numero, tipo, sociedad, proyecto_id, total, moneda, fecha_emision, creado_por, created_at) values
    ('TESTB2-FS', 'factura', soc_s, ps, 61, 'EUR', current_date, 'ajeno@test.b2', '2026-01-01') returning id into f_fs;
  insert into public.facturas (numero, tipo, sociedad, proyecto_id, total, moneda, fecha_emision, creado_por, created_at) values
    ('TESTB2-FS2', 'factura', soc_s, ps, 62, 'EUR', current_date, 'ajeno@test.b2', '2026-01-01') returning id into f_fs2;

  select s.id into s_l from public.solicitudes_pago s join public.contratos c1 on c1.id = s.contrato_id join public.proyectos pr on pr.id = c1.proyecto_id
   where s.estado = 'pendiente' and pr.empresa = 'lawang' order by s.creado_en limit 1;
  select s.id into s_s from public.solicitudes_pago s join public.contratos c1 on c1.id = s.contrato_id join public.proyectos pr on pr.id = c1.proyecto_id
   where s.estado = 'pendiente' and pr.empresa = 'sandal_woods' order by s.creado_en limit 1;

  insert into public.proveedores (nombre, empresa) values ('TESTB2 prov lawang', 'lawang') returning id into pv_l;
  insert into public.proveedores (nombre, empresa) values ('TESTB2 prov sandal', 'sandal_woods') returning id into pv_s;
  insert into public.proveedores (nombre, empresa) values ('TESTB2 prov global', null) returning id into pv_g;
  insert into public.gastos (sociedad, categoria, concepto, fecha, base) values (soc_l, cat, 'TESTB2 gasto lawang', current_date, 10) returning id into g_l;
  insert into public.gastos (sociedad, categoria, concepto, fecha, base) values (soc_s, cat, 'TESTB2 gasto sandal', current_date, 20) returning id into g_s;
  insert into public.gastos (sociedad, proyecto_id, categoria, concepto, fecha, base) values (soc_s, pl, cat, 'TESTB2 gasto sandal con proyecto lawang', current_date, 30) returning id into g_pl;
  if soc_ltd is not null then
    insert into public.gastos (sociedad, categoria, concepto, fecha, base) values (soc_ltd, cat, 'TESTB2 gasto sin empresa', current_date, 40) returning id into g_ltd;
  end if;
  insert into public.bancos_movimientos (cuenta_clave, fecha, importe, moneda, huella, concepto) values ('contractor_tepisungai', current_date, -10, 'EUR', 'TESTB2:l', 'TESTB2 mov lawang') returning id into m_l;
  insert into public.bancos_movimientos (cuenta_clave, fecha, importe, moneda, huella, concepto) values ('sandalwoods_danamon_eur', current_date, -20, 'EUR', 'TESTB2:s', 'TESTB2 mov sandal') returning id into m_s;
  insert into public.bancos_movimientos (cuenta_clave, fecha, importe, moneda, huella, concepto) values ('sw_ltd_lux', current_date, -30, 'EUR', 'TESTB2:n', 'TESTB2 mov sin empresa') returning id into m_n;
  insert into public.bancos_perfiles (cuenta_clave, mapeo) values ('contractor_tepisungai', '{"fecha":1}'), ('sandalwoods_danamon_eur', '{"fecha":1}'), ('sw_ltd_lux', '{"fecha":1}');
  insert into public.bancos_conciliacion (movimiento_id, tipo, ref_id, importe_mov) values (m_s, 'gasto', g_s, -20) returning id into lin_s;
  insert into public.sociedades_log (clave, antes, accion, quien) values (soc_l, '{}', 'update', 'TESTB2'), (soc_s, '{}', 'update', 'TESTB2');

  pay_l := format('{"tipo":"factura","contrato_id":"%s","moneda":"EUR","total":"1","sociedad":"%s","datos":{"lineas":[{"importe":"1"}]}}', cl, soc_l);
  pay_s := format('{"tipo":"factura","contrato_id":"%s","moneda":"EUR","total":"1","sociedad":"%s","datos":{"lineas":[{"importe":"1"}]}}', cs, soc_s);

  create or replace function pg_temp.ce(p text, q text, ex text, l text) returns jsonb language sql as $f$ select jsonb_build_object('p', p, 'q', q, 'ex', ex, 'l', l) $f$;
  cs_ids := cs_ids ||
    pg_temp.ce('ya',  format('select public.factura_borra(%L)', f_pl),  'ok',    'A1 admin_empresa borra proforma de su empresa') ||
    pg_temp.ce('ya',  format('select public.factura_borra(%L)', f_ps),  '42501', 'A2 admin_empresa NO borra proforma de la otra empresa') ||
    pg_temp.ce('ya',  format('select public.factura_borra(%L)', f_pk),  '42501', 'A3 admin_empresa NO borra proforma sin proyecto') ||
    pg_temp.ce('cr',  format('select public.factura_borra(%L)', f_ps),  'ok',    'A4 super_admin_empresa borra proforma de su empresa (sin casillas)') ||
    pg_temp.ce('cr',  format('select public.factura_borra(%L)', f_pl2), '42501', 'A5 super_admin_empresa NO borra la de la otra empresa') ||
    pg_temp.ce('ad4', format('select public.factura_borra(%L)', f_pl2), 'ok',    'A6 admin con las dos borra de Lawang') ||
    pg_temp.ce('ad4', format('select public.factura_borra(%L)', f_ps2), 'ok',    'A7 admin con las dos borra de Sandal Woods') ||
    pg_temp.ce('ad0', format('select public.factura_borra(%L)', f_pl3), 'ok',    'A8 admin_empresa sin casillas borra proforma (como un admin global: no pide casilla)') ||
    pg_temp.ce('ctl', format('select public.factura_borra(%L)', f_pl4), '42501', 'A9 agente de control NO borra') ||
    pg_temp.ce('gad', format('select public.factura_borra(%L)', f_pk),  'ok',    'A10 admin global borra la sin proyecto') ||
    pg_temp.ce('jv',  format('select public.factura_borra(%L)', f_ps),  'ok',    'A11 propietario borra de cualquiera') ||
    pg_temp.ce('ya',  format('select public.factura_anula(%L)', f_fl),  'ok',    'A12 admin_empresa anula factura de su empresa') ||
    pg_temp.ce('ya',  format('select public.factura_anula(%L)', f_fs),  '42501', 'A13 admin_empresa NO anula la de la otra empresa') ||
    pg_temp.ce('ad0', format('select public.factura_anula(%L)', f_fl),  '42501', 'A14 admin_empresa sin casilla Facturas NO anula (igual que un admin global sin ella)') ||
    pg_temp.ce('cr',  format('select public.factura_anula(%L)', f_fs),  'ok',    'A15 super_admin_empresa anula la de su empresa') ||
    pg_temp.ce('cr',  format('select public.factura_anula(%L)', f_fl),  '42501', 'A16 super_admin_empresa NO anula la de la otra') ||
    pg_temp.ce('ctl', format('select public.factura_anula(%L)', f_fl),  '42501', 'A17 agente de control NO anula la de otro') ||
    pg_temp.ce('gad', format('select public.factura_anula(%L)', f_fs),  'ok',    'A18 admin global anula cualquiera') ||
    pg_temp.ce('ya',  format('select public.factura_marca_enviada(%L)', f_fl2), 'ok',    'A19 admin_empresa marca enviada la de su empresa') ||
    pg_temp.ce('ya',  format('select public.factura_marca_enviada(%L)', f_fs2), '42501', 'A20 admin_empresa NO marca enviada la de la otra') ||
    pg_temp.ce('cr',  format('select public.factura_marca_enviada(%L)', f_fs2), 'ok',    'A21 super_admin_empresa marca enviada la de su empresa') ||
    pg_temp.ce('ya',  format('select public.factura_reactiva(%L)', f_al), '42501', 'A22 admin_empresa NO reactiva (solo super)') ||
    pg_temp.ce('cr',  format('select public.factura_reactiva(%L)', f_as), 'ok',    'A23 super_admin_empresa reactiva la de su empresa') ||
    pg_temp.ce('cr',  format('select public.factura_reactiva(%L)', f_al), '42501', 'A24 super_admin_empresa NO reactiva la de la otra') ||
    pg_temp.ce('jv',  format('select public.factura_reactiva(%L)', f_al), 'ok',    'A25 propietario reactiva') ||
    pg_temp.ce('ya',  format('select * from public.factura_guarda(null, %L::jsonb)', pay_l), 'no42501', 'A26 admin_empresa emite sobre contrato de su empresa con su sociedad') ||
    pg_temp.ce('ya',  format('select * from public.factura_guarda(null, %L::jsonb)', pay_s), '42501', 'A27 admin_empresa NO emite sobre contrato de la otra empresa') ||
    pg_temp.ce('ya',  format('select * from public.factura_guarda(null, %L::jsonb)', replace(pay_l, soc_l, soc_s)), '42501', 'A28 admin_empresa NO emite con la sociedad de la otra empresa') ||
    pg_temp.ce('cr',  format('select * from public.factura_guarda(null, %L::jsonb)', pay_s), 'no42501', 'A29 super_admin_empresa emite sobre su contrato con su sociedad (sin casillas)') ||
    pg_temp.ce('cr',  format('select * from public.factura_guarda(null, %L::jsonb)', pay_l), '42501', 'A30 super_admin_empresa NO emite sobre contrato de la otra') ||
    pg_temp.ce('ad4', format('select * from public.factura_guarda(null, %L::jsonb)', replace(pay_l, soc_l, soc_s)), '42501', 'A31 admin con las dos NO mezcla: contrato Lawang con sociedad Sandal Woods') ||
    pg_temp.ce('ad4', format('select * from public.factura_guarda(null, %L::jsonb)', replace(pay_s, soc_s, soc_l)), '42501', 'A32 admin con las dos NO mezcla: contrato Sandal Woods con sociedad Lawang') ||
    pg_temp.ce('ad4', format('select * from public.factura_guarda(null, %L::jsonb)', pay_s), 'no42501', 'A33 admin con las dos emite en Sandal Woods con su sociedad') ||
    pg_temp.ce('ad0', format('select * from public.factura_guarda(null, %L::jsonb)', pay_l), '42501', 'A34 admin_empresa sin casilla Facturas NO emite') ||
    pg_temp.ce('ar',  format('select * from public.factura_guarda(null, %L::jsonb)', pay_s), '42501', 'A35 agente con empresas marcadas NO emite sobre la otra') ||
    pg_temp.ce('gad', format('select * from public.factura_guarda(null, %L::jsonb)', replace(pay_s, soc_s, soc_l)), 'no42501', 'A36 admin global sin restriccion (la regla de sociedad no le toca)') ||
    pg_temp.ce('ya',  format('select * from public.factura_guarda(null, %L::jsonb)', jsonb_set(pay_l::jsonb, '{contrato_id}', 'null'::jsonb) #>> '{}'), '42501', 'A37 admin_empresa NO emite sin contrato ni proyecto') ||
    pg_temp.ce('ya',  format('select * from public.factura_guarda(null, %L::jsonb)', (jsonb_set(jsonb_set(pay_l::jsonb, '{contrato_id}', 'null'::jsonb), '{proyecto_nombre}', to_jsonb(ms)))::text), '42501', 'A38 admin_empresa NO emite sobre un proyecto de la otra empresa por nombre') ||
    pg_temp.ce('ya',  format('select * from public.factura_guarda(%L, %L::jsonb)', f_fl2, (jsonb_set(jsonb_set(pay_l::jsonb, '{contrato_id}', 'null'::jsonb), '{proyecto_nombre}', to_jsonb(ml)))::text), 'no42501', 'A39 admin_empresa edita un documento de su empresa que no creo') ||
    pg_temp.ce('ya',  format('select * from public.factura_guarda(%L, %L::jsonb)', f_fs2, pay_l), '42501', 'A40 admin_empresa NO edita un documento de la otra empresa') ||
    pg_temp.ce('ctl', format('select * from public.factura_guarda(%L, %L::jsonb)', f_fl2, pay_l), '42501', 'A41 agente de control NO edita un documento ajeno') ||
    pg_temp.ce('ya',  format('select public.guardar_recibi(null, %L::jsonb, %L::jsonb)', format('{"contrato_id":"%s","sociedad":"%s"}', cs, soc_s), '[]'), '42501', 'A42 admin_empresa NO emite recibi sobre contrato de la otra empresa') ||
    pg_temp.ce('ya',  format('select public.guardar_recibi(null, %L::jsonb, %L::jsonb)', format('{"contrato_id":"%s","sociedad":"%s"}', cl, soc_s), '[]'), '42501', 'A43 admin_empresa NO emite recibi con la sociedad de la otra empresa') ||
    pg_temp.ce('ya',  format('select public.guardar_recibi(null, %L::jsonb, %L::jsonb)', format('{"contrato_id":"%s","sociedad":"%s"}', cl, soc_l), '[]'), 'no42501', 'A44 admin_empresa pasa la puerta del recibi de su empresa (despues pide el justificante)') ||
    pg_temp.ce('cr',  format('select public.guardar_recibi(null, %L::jsonb, %L::jsonb)', format('{"contrato_id":"%s","sociedad":"%s"}', cs, soc_s), '[]'), 'no42501', 'A45 super_admin_empresa pasa la puerta del recibi de su empresa sin casillas') ||
    pg_temp.ce('ya',  format('select public.solicitud_pago_resuelve(%L, %L)', s_l, 'aprobada'), 'ok',    'B1 admin_empresa con Comisiones aprueba solicitud de su empresa') ||
    pg_temp.ce('ya',  format('select public.solicitud_pago_resuelve(%L, %L)', s_s, 'aprobada'), '42501', 'B2 admin_empresa NO aprueba la de la otra') ||
    pg_temp.ce('ad0', format('select public.solicitud_pago_resuelve(%L, %L)', s_l, 'aprobada'), '42501', 'B3 admin_empresa sin la casilla Comisiones NO aprueba') ||
    pg_temp.ce('cr',  format('select public.solicitud_pago_resuelve(%L, %L)', s_s, 'aprobada'), 'ok',    'B4 super_admin_empresa aprueba la de su empresa sin casillas') ||
    pg_temp.ce('cr',  format('select public.solicitud_pago_resuelve(%L, %L)', s_l, 'aprobada'), '42501', 'B5 super_admin_empresa NO aprueba la de la otra') ||
    pg_temp.ce('ad4', format('select public.solicitud_pago_resuelve(%L, %L)', s_s, 'aprobada'), 'ok',    'B6 admin con las dos aprueba la de Sandal Woods') ||
    pg_temp.ce('ctl', format('select public.solicitud_pago_resuelve(%L, %L)', s_l, 'aprobada'), '42501', 'B7 agente de control NO aprueba') ||
    pg_temp.ce('gad', format('select public.solicitud_pago_resuelve(%L, %L)', s_l, 'aprobada'), 'ok',    'B8 admin global aprueba cualquiera') ||
    pg_temp.ce('ya!', format('select public._retencion_puerta(%L)', s_l), '22023', 'B9 retencion: admin_empresa pasa la puerta de su empresa (22023 = la solicitud aun no esta pagada)') ||
    pg_temp.ce('ya!', format('select public._retencion_puerta(%L)', s_s), '42501', 'B10 retencion: admin_empresa NO toca la de la otra empresa') ||
    pg_temp.ce('cr!', format('select public._retencion_puerta(%L)', s_s), '22023', 'B11 retencion: super_admin_empresa pasa la puerta sin casillas') ||
    pg_temp.ce('ad0!', format('select public._retencion_puerta(%L)', s_l), '42501', 'B12 retencion: sin la casilla Comisiones NO') ||
    pg_temp.ce('ctl', format('select public.solicitud_pago_retencion_rectifica(%L, %L, %L)', s_l, 'batal', 'x'), '42501', 'B13 retencion: agente NO rectifica') ||
    pg_temp.ce('ya',  format('select public.gasto_anula(%L, %L)', g_l, 'test'), 'ok',    'C1 admin_empresa anula gasto de su empresa') ||
    pg_temp.ce('ya',  format('select public.gasto_anula(%L, %L)', g_s, 'test'), '42501', 'C2 admin_empresa NO anula gasto de la otra') ||
    pg_temp.ce('ya',  format('select public.gasto_anula(%L, %L)', g_pl, 'test'), 'ok',   'C3 el proyecto manda: gasto con sociedad Sandal Woods pero proyecto de Lawang es de Lawang') ||
    pg_temp.ce('cr',  format('select public.gasto_anula(%L, %L)', g_s, 'test'), 'ok',    'C4 super_admin_empresa anula gasto de su empresa (sin casillas)') ||
    pg_temp.ce('cr',  format('select public.gasto_anula(%L, %L)', g_pl, 'test'), '42501', 'C5 super_admin_empresa NO anula el gasto con proyecto de Lawang') ||
    pg_temp.ce('ad0', format('select public.gasto_anula(%L, %L)', g_l, 'test'), '42501', 'C6 admin_empresa sin la casilla Gastos NO') ||
    pg_temp.ce('ctl', format('select public.gasto_anula(%L, %L)', g_l, 'test'), '42501', 'C7 agente de control NO') ||
    pg_temp.ce('gad', format('select public.gasto_anula(%L, %L)', g_s, 'test'), 'ok',    'C8 admin global con casilla anula cualquiera') ||
    pg_temp.ce('ya',  format('select public.gasto_marca_pagado(%L, %L::date, %L)', g_l, hoy, 'contractor_tepisungai'), 'ok', 'C9 admin_empresa marca pagado desde cuenta de su empresa') ||
    pg_temp.ce('ya',  format('select public.gasto_marca_pagado(%L, %L::date, %L)', g_l, hoy, 'sandalwoods_danamon_eur'), '42501', 'C10 admin_empresa NO paga desde cuenta de la otra empresa') ||
    pg_temp.ce('ya',  format('select public.gasto_marca_pagado(%L, %L::date, %L)', g_l, hoy, 'sandalwoods_dbs'), '42501', 'C11 admin_empresa NO paga desde cuenta propia sin empresa') ||
    pg_temp.ce('ya',  format('select public.gasto_historial_datos(%L)', g_l), 'ok',    'C12 historial del gasto de su empresa') ||
    pg_temp.ce('ya',  format('select public.gasto_historial_datos(%L)', g_s), 'ok', 'C13 historial del gasto de la otra empresa: vacio (la RLS de gastos_log lo oculta)') ||
    pg_temp.ce('ya',  format('select public.gasto_guarda(null, %L::jsonb)', format('{"base":"5","sociedad":"%s","categoria":"%s","concepto":"t","fecha":"%s"}', soc_l, cat, hoy)), 'ok', 'C14 admin_empresa crea gasto con su sociedad') ||
    pg_temp.ce('ya',  format('select public.gasto_guarda(null, %L::jsonb)', format('{"base":"5","sociedad":"%s","categoria":"%s","concepto":"t","fecha":"%s"}', soc_s, cat, hoy)), '42501', 'C15 admin_empresa NO crea gasto con la sociedad de la otra') ||
    pg_temp.ce('ya',  format('select public.gasto_guarda(null, %L::jsonb)', format('{"base":"5","sociedad":"%s","proyecto_id":"%s","categoria":"%s","concepto":"t","fecha":"%s"}', soc_l, ps, cat, hoy)), '42501', 'C16 admin_empresa NO crea gasto sobre un proyecto de la otra') ||
    pg_temp.ce('ya',  format('select public.gasto_guarda(null, %L::jsonb)', format('{"base":"5","sociedad":"%s","proveedor_id":"%s","categoria":"%s","concepto":"t","fecha":"%s"}', soc_l, pv_s, cat, hoy)), '42501', 'C17 admin_empresa NO usa un proveedor de la otra') ||
    pg_temp.ce('ya',  format('select public.gasto_guarda(null, %L::jsonb)', format('{"base":"5","sociedad":"%s","proveedor_id":"%s","categoria":"%s","concepto":"t","fecha":"%s"}', soc_l, pv_l, cat, hoy)), 'ok', 'C18 admin_empresa usa un proveedor de su empresa') ||
    pg_temp.ce('ya',  format('select public.gasto_guarda(null, %L::jsonb)', format('{"base":"5","sociedad":"%s","proveedor_id":"%s","categoria":"%s","concepto":"t","fecha":"%s"}', soc_l, pv_g, cat, hoy)), '42501', 'C19 admin_empresa NO usa un proveedor global (sin empresa)') ||
    pg_temp.ce('cr',  format('select public.gasto_guarda(null, %L::jsonb)', format('{"base":"5","sociedad":"%s","categoria":"%s","concepto":"t","fecha":"%s"}', soc_s, cat, hoy)), 'ok', 'C20 super_admin_empresa crea gasto de su empresa (sin casillas)') ||
    pg_temp.ce('ya',  format('select public.gasto_guarda(%L, %L::jsonb)', g_s, format('{"base":"5","sociedad":"%s","categoria":"%s","concepto":"t","fecha":"%s"}', soc_l, cat, hoy)), '42501', 'C21 admin_empresa NO edita un gasto de la otra pasandolo a la suya') ||
    pg_temp.ce('ya',  format('select public.proveedor_guarda(null, %L::jsonb)', '{"nombre":"nuevo"}'), 'ok', 'C22 admin_empresa crea proveedor (su empresa la pone el servidor)') ||
    pg_temp.ce('ad4', format('select public.proveedor_guarda(null, %L::jsonb)', '{"nombre":"nuevo"}'), '42501', 'C23 con dos empresas hay que elegir una') ||
    pg_temp.ce('ad4', format('select public.proveedor_guarda(null, %L::jsonb)', '{"nombre":"nuevo","empresa":"sandal_woods"}'), 'ok', 'C24 con dos empresas, elige una de las suyas') ||
    pg_temp.ce('ya',  format('select public.proveedor_guarda(null, %L::jsonb)', '{"nombre":"nuevo","empresa":"sandal_woods"}'), 'ok', 'C25 con una sola empresa, el parametro se ignora (lo fija el servidor)') ||
    pg_temp.ce('ya',  format('select public.proveedor_guarda(%L, %L::jsonb)', pv_s, '{"nombre":"x"}'), '42501', 'C26 admin_empresa NO edita proveedor de la otra') ||
    pg_temp.ce('ya',  format('select public.proveedor_guarda(%L, %L::jsonb)', pv_g, '{"nombre":"x"}'), '42501', 'C27 admin_empresa NO edita proveedor global') ||
    pg_temp.ce('ya',  format('select public.proveedor_guarda(%L, %L::jsonb)', pv_l, '{"nombre":"x"}'), 'ok', 'C28 admin_empresa edita proveedor de su empresa') ||
    pg_temp.ce('gad', format('select public.proveedor_guarda(%L, %L::jsonb)', pv_g, '{"nombre":"x"}'), 'ok', 'C29 admin global edita proveedor global') ||
    pg_temp.ce('ya',  format('select public.bancos_ignorar(%L, %L)', m_l, 'x'), 'ok',    'D1 admin_empresa con Bancos ignora movimiento de su cuenta') ||
    pg_temp.ce('ya',  format('select public.bancos_ignorar(%L, %L)', m_s, 'x'), '42501', 'D2 admin_empresa NO ignora movimiento de la cuenta de la otra') ||
    pg_temp.ce('ya',  format('select public.bancos_ignorar(%L, %L)', m_n, 'x'), '42501', 'D3 admin_empresa NO toca un extracto de cuenta sin empresa') ||
    pg_temp.ce('cr',  format('select public.bancos_ignorar(%L, %L)', m_s, 'x'), 'no42501', 'D4 super_admin_empresa ignora movimiento de su cuenta (sin casillas)') ||
    pg_temp.ce('cr',  format('select public.bancos_ignorar(%L, %L)', m_n, 'x'), '42501', 'D5 super_admin_empresa NO toca extracto de cuenta sin empresa') ||
    pg_temp.ce('ad0', format('select public.bancos_ignorar(%L, %L)', m_l, 'x'), '42501', 'D6 sin la casilla Bancos NO') ||
    pg_temp.ce('gad', format('select public.bancos_ignorar(%L, %L)', m_n, 'x'), 'ok',    'D7 admin global con Bancos ignora cualquiera') ||
    pg_temp.ce('ya',  format('select public.bancos_importar(%L, %L, %L::jsonb)', 'sandalwoods_danamon_eur', 'f.csv', format('[{"fecha":"%s","importe":1,"moneda":"EUR","huella":"b2x"}]', hoy)), '42501', 'D8 admin_empresa NO importa extracto de la cuenta de la otra') ||
    pg_temp.ce('cr',  format('select public.bancos_importar(%L, %L, %L::jsonb)', 'sandalwoods_danamon_eur', 'f.csv', format('[{"fecha":"%s","importe":1,"moneda":"EUR","huella":"b2x"}]', hoy)), 'ok', 'D9 super_admin_empresa importa extracto de su cuenta') ||
    pg_temp.ce('cr',  format('select public.bancos_importar(%L, %L, %L::jsonb)', 'sandalwoods_dbs', 'f.csv', format('[{"fecha":"%s","importe":1,"moneda":"EUR","huella":"b2y"}]', hoy)), '42501', 'D10 super_admin_empresa NO importa en cuenta propia sin empresa') ||
    pg_temp.ce('ya',  format('select public.banco_perfil_guarda(%L, %L::jsonb)', 'contractor_tepisungai', '{"fecha":2}'), 'ok', 'D11 admin_empresa edita perfil de importacion de su cuenta') ||
    pg_temp.ce('ya',  format('select public.banco_perfil_guarda(%L, %L::jsonb)', 'sandalwoods_danamon_eur', '{"fecha":2}'), '42501', 'D12 admin_empresa NO edita perfil de la cuenta de la otra') ||
    pg_temp.ce('ya',  format('select public.bancos_conciliar(%L, %L::jsonb)', m_l, format('[{"tipo":"gasto","ref_id":"%s","importe_mov":-10}]', g_s)), '42501', 'D13 NO concilia un movimiento de Lawang contra un gasto de Sandal Woods') ||
    pg_temp.ce('ya',  format('select public.bancos_conciliar(%L, %L::jsonb)', m_l, format('[{"tipo":"gasto","ref_id":"%s","importe_mov":-10}]', g_l)), 'no42501', 'D14 SI contra un gasto de su empresa (despues pide que el gasto este pagado)') ||
    pg_temp.ce('ya',  format('select public.bancos_desconciliar(%L)', lin_s), '42501', 'D15 admin_empresa NO deshace una linea de la otra empresa') ||
    pg_temp.ce('cr',  format('select public.bancos_desconciliar(%L)', lin_s), 'ok',    'D16 super_admin_empresa deshace una linea de su empresa') ||
    pg_temp.ce('ya',  format('select public.bancos_designorar(%L)', m_s), '42501', 'D17 admin_empresa NO quita la marca de ignorado de la otra') ||
    pg_temp.ce('ya',  format('select public.cuenta_bancaria_guarda(%L, %L::jsonb, true)', 'zz_b2_cuenta', '{"label":"x","titular":"x","cuenta":"1"}'), '42501', 'E1 admin_empresa NO crea cuentas (como un admin global)') ||
    pg_temp.ce('cr',  format('select public.cuenta_bancaria_guarda(%L, %L::jsonb, true)', 'zz_b2_cuenta', '{"label":"x","titular":"x","cuenta":"1"}'), 'ok', 'E2 super_admin_empresa crea una cuenta en su empresa') ||
    pg_temp.ce('cr',  format('select public.cuenta_bancaria_guarda(%L, %L::jsonb, false)', 'sandalwoods_danamon_eur', '{"label":"Danamon EUR"}'), 'ok', 'E3 super_admin_empresa edita cuenta de su empresa') ||
    pg_temp.ce('cr',  format('select public.cuenta_bancaria_guarda(%L, %L::jsonb, false)', 'contractor_tepisungai', '{"label":"x"}'), '42501', 'E4 super_admin_empresa NO edita cuenta de la otra empresa') ||
    pg_temp.ce('cr',  format('select public.cuenta_bancaria_guarda(%L, %L::jsonb, false)', 'sandalwoods_dbs', '{"label":"x"}'), '42501', 'E5 super_admin_empresa NO edita cuenta sin empresa') ||
    pg_temp.ce('cr',  format('select public.cuenta_bancaria_guarda(%L, %L::jsonb, false, %L::jsonb)', 'sandalwoods_danamon_eur', '{"label":"Danamon EUR"}', format('[{"proyecto_id":"%s","slug":"*","claves":["sandalwoods_danamon_eur"]}]', ps)), 'no42501', 'E6 reparto a un proyecto de su empresa con cuentas suyas') ||
    pg_temp.ce('cr',  format('select public.cuenta_bancaria_guarda(%L, %L::jsonb, false, %L::jsonb)', 'sandalwoods_danamon_eur', '{"label":"Danamon EUR"}', format('[{"proyecto_id":"%s","slug":"*","claves":["sandalwoods_danamon_eur"]}]', pl)), '42501', 'E7 reparto a un proyecto de la otra empresa NO') ||
    pg_temp.ce('cr',  format('select public.cuenta_bancaria_guarda(%L, %L::jsonb, false, %L::jsonb)', 'sandalwoods_danamon_eur', '{"label":"Danamon EUR"}', format('[{"proyecto_id":"%s","slug":"*","claves":["contractor_tepisungai"]}]', ps)), '42501', 'E8 reparto con una cuenta de la otra empresa NO') ||
    pg_temp.ce('cr',  format('select public.cuenta_bancaria_guarda(%L, %L::jsonb, false, %L::jsonb)', 'sandalwoods_danamon_eur', '{"label":"Danamon EUR"}', '[{"slug":"ppjb","claves":["sandalwoods_danamon_eur"]}]'), '42501', 'E9 reparto de la plantilla global NO') ||
    pg_temp.ce('jv',  format('select public.cuenta_bancaria_guarda(%L, %L::jsonb, false)', 'contractor_tepisungai', '{"label":"OCBC"}'), 'ok', 'E10 el propietario edita cualquiera') ||
    pg_temp.ce('cr',  format('select public.sociedad_guarda(%L, %L::jsonb, false)', soc_s, '{"label":"PT San Dal Woods"}'), 'ok', 'E11 super_admin_empresa edita la sociedad de su empresa') ||
    pg_temp.ce('cr',  format('select public.sociedad_guarda(%L, %L::jsonb, false)', soc_l, '{"label":"x"}'), '42501', 'E12 super_admin_empresa NO edita la sociedad de la otra') ||
    pg_temp.ce('cr',  format('select public.sociedad_guarda(%L, %L::jsonb, true)', 'zz_nueva_b2', '{"label":"x","razon":"x","domicilio":"x"}'), '42501', 'E13 super_admin_empresa NO da de alta sociedades') ||
    pg_temp.ce('ya',  format('select public.sociedad_guarda(%L, %L::jsonb, false)', soc_l, '{"label":"x"}'), '42501', 'E14 admin_empresa NO edita sociedades (solo super)') ||
    pg_temp.ce('jv',  format('select public.sociedad_guarda(%L, %L::jsonb, false)', soc_l, '{"label":"Tepi Sun Gai"}'), 'ok', 'E15 el propietario edita cualquiera');
  if soc_ltd is not null then
    cs_ids := cs_ids ||
      pg_temp.ce('cr', format('select public.gasto_anula(%L, %L)', g_ltd, 'test'), '42501', 'C30 gasto de sociedad sin empresa: super_admin_empresa NO') ||
      pg_temp.ce('ya', format('select public.gasto_guarda(null, %L::jsonb)', format('{"base":"5","sociedad":"%s","categoria":"%s","concepto":"t","fecha":"%s"}', soc_ltd, cat, hoy)), '42501', 'C31 admin_empresa NO crea gasto con una sociedad sin empresa') ||
      pg_temp.ce('gad', format('select public.gasto_anula(%L, %L)', g_ltd, 'test'), 'ok', 'C32 admin global anula el gasto sin empresa');
  end if;

  cs_ids := cs_ids ||
    pg_temp.ce('ya',  'select count(*) from public.gastos', 'n:' || (select count(*) from public.gastos g left join public.proyectos p on p.id = g.proyecto_id left join public.empresas x on x.sociedad_clave = g.sociedad where (case when g.proyecto_id is not null then p.empresa else x.clave end) = 'lawang'), 'F1 gastos que ve admin_empresa Lawang') ||
    pg_temp.ce('cr',  'select count(*) from public.gastos', 'n:' || (select count(*) from public.gastos g left join public.proyectos p on p.id = g.proyecto_id left join public.empresas x on x.sociedad_clave = g.sociedad where (case when g.proyecto_id is not null then p.empresa else x.clave end) = 'sandal_woods'), 'F2 gastos que ve super_admin_empresa Sandal Woods') ||
    pg_temp.ce('ad4', 'select count(*) from public.gastos', 'n:' || (select count(*) from public.gastos g left join public.proyectos p on p.id = g.proyecto_id left join public.empresas x on x.sociedad_clave = g.sociedad where (case when g.proyecto_id is not null then p.empresa else x.clave end) in ('lawang','sandal_woods')), 'F3 gastos que ve admin con las dos') ||
    pg_temp.ce('ad0', 'select count(*) from public.gastos', 'n:0', 'F4 sin la casilla Gastos no ve ninguno') ||
    pg_temp.ce('ctl', 'select count(*) from public.gastos', 'n:0', 'F5 agente de control no ve ninguno') ||
    pg_temp.ce('gad', 'select count(*) from public.gastos', 'n:' || (select count(*) from public.gastos), 'F6 admin global con casilla los ve todos') ||
    pg_temp.ce('ya',  'select jsonb_array_length(public.gastos_panel_datos()->''gastos'')', 'n:' || (select count(*) from public.gastos g left join public.proyectos p on p.id = g.proyecto_id left join public.empresas x on x.sociedad_clave = g.sociedad where (case when g.proyecto_id is not null then p.empresa else x.clave end) = 'lawang'), 'F7 gastos_panel_datos: gastos de su empresa') ||
    pg_temp.ce('ya',  'select jsonb_array_length(public.gastos_panel_datos()->''proveedores'')', 'n:' || (select count(*) from public.proveedores where empresa = 'lawang'), 'F8 gastos_panel_datos: proveedores de su empresa') ||
    pg_temp.ce('gad', 'select jsonb_array_length(public.gastos_panel_datos()->''proveedores'')', 'n:' || (select count(*) from public.proveedores), 'F9 gastos_panel_datos: el admin global ve todos los proveedores') ||
    pg_temp.ce('ya',  'select jsonb_array_length(public.gastos_panel_datos()->''proyectos'')', 'n:' || (select count(*) from public.proyectos where empresa = 'lawang'), 'F10 gastos_panel_datos: proyectos de su empresa') ||
    pg_temp.ce('cr',  'select jsonb_array_length(public.gastos_panel_datos()->''cuentas'')', 'n:' || (select count(*) from public.cuentas_bancarias where empresa = 'sandal_woods'), 'F11 gastos_panel_datos: cuentas de su empresa (las sin empresa NO)') ||
    pg_temp.ce('ya',  'select count(*) from public.proveedores', '42501', 'F12 proveedores: la tabla directa no es de authenticated (solo por RPC)') ||
    pg_temp.ce('ya',  'select jsonb_array_length(public.panel_bancos_datos()->''movimientos'')', 'n:' || (select count(*) from public.bancos_movimientos m join public.cuentas_bancarias c on c.clave = m.cuenta_clave where c.empresa = 'lawang'), 'F13 panel de bancos: movimientos de las cuentas de su empresa') ||
    pg_temp.ce('cr',  'select jsonb_array_length(public.panel_bancos_datos()->''movimientos'')', 'n:' || (select count(*) from public.bancos_movimientos m join public.cuentas_bancarias c on c.clave = m.cuenta_clave where c.empresa = 'sandal_woods'), 'F14 panel de bancos: super_admin_empresa') ||
    pg_temp.ce('ad4', 'select jsonb_array_length(public.panel_bancos_datos()->''movimientos'')', 'n:' || (select count(*) from public.bancos_movimientos m join public.cuentas_bancarias c on c.clave = m.cuenta_clave where c.empresa in ('lawang','sandal_woods')), 'F15 panel de bancos: admin con las dos') ||
    pg_temp.ce('gad', 'select jsonb_array_length(public.panel_bancos_datos()->''movimientos'')', 'n:' || (select count(*) from public.bancos_movimientos), 'F16 panel de bancos: el admin global los ve todos (incluidos los de cuentas sin empresa)') ||
    pg_temp.ce('ya',  'select jsonb_array_length(public.panel_bancos_datos()->''perfiles'')', 'n:' || (select count(*) from public.bancos_perfiles p join public.cuentas_bancarias c on c.clave = p.cuenta_clave where c.empresa = 'lawang'), 'F17 panel de bancos: perfiles de su empresa') ||
    pg_temp.ce('ya',  'select jsonb_array_length(public.panel_bancos_datos()->''cuentas'')', 'n:' || (select count(*) from public.cuentas_bancarias where empresa = 'lawang'), 'F18 panel de bancos: cuentas de su empresa') ||
    pg_temp.ce('ya',  'select jsonb_array_length(public.panel_bancos_datos()->''gastos'')', 'n:' || (select count(*) from public.gastos g left join public.proyectos p on p.id = g.proyecto_id left join public.empresas x on x.sociedad_clave = g.sociedad where g.estado <> 'anulado' and (case when g.proyecto_id is not null then p.empresa else x.clave end) = 'lawang'), 'F19 panel de bancos: gastos conciliables de su empresa') ||
    pg_temp.ce('ya',  'select jsonb_array_length(public.panel_bancos_datos()->''recibis'')', 'n:' || (select count(*) from public.facturas f join public.proyectos p on p.id = f.proyecto_id where f.tipo = 'recibi' and f.anulada is not true and p.empresa = 'lawang'), 'F20 panel de bancos: recibis de su empresa') ||
    pg_temp.ce('ya',  'select jsonb_array_length(public.panel_bancos_datos()->''comisiones'')', 'le:' || (select count(*) from public.comisiones_devengadas d join public.contratos c1 on c1.id = d.contrato_raiz_id join public.proyectos p on p.id = c1.proyecto_id where d.estado = 'pagada' and p.empresa = 'lawang'), 'F21 panel de bancos: comisiones pagadas de su empresa') ||
    pg_temp.ce('ya',  'select count(*) from jsonb_array_elements(coalesce(public.bancos_resumen(), ''[]''::jsonb)) x where x->>''cuenta'' = ''sandalwoods_danamon_eur''', 'n:0', 'F22 bancos_resumen: sin la cuenta de la otra empresa') ||
    pg_temp.ce('ctl', 'select jsonb_array_length(coalesce(public.bancos_resumen(), ''[]''::jsonb))', 'n:0', 'F23 bancos_resumen: el agente de control no recibe nada') ||
    pg_temp.ce('ctl', 'select jsonb_array_length(public.panel_bancos_datos()->''movimientos'')', '42501', 'F24 panel de bancos: agente de control rechazado') ||
    pg_temp.ce('cr',  'select count(*) from public.sociedades_log', 'n:' || (select count(*) from public.sociedades_log where clave = (select e3.sociedad_clave from public.empresas e3 where e3.clave = 'sandal_woods')), 'F26 sociedades_log: super_admin_empresa ve el de su sociedad') ||
    pg_temp.ce('ya',  'select count(*) from public.sociedades_log', 'n:0', 'F27 sociedades_log: admin_empresa (no super) no ve ninguno') ||
    pg_temp.ce('jv',  'select count(*) from public.sociedades_log', 'n:' || (select count(*) from public.sociedades_log), 'F28 sociedades_log: el propietario los ve todos') ||
    pg_temp.ce('ya',  'select count(*) from public.cuentas_uso()', 'n:0', 'F29 cuentas_uso: admin_empresa no ve ninguna') ||
    pg_temp.ce('cr',  'select count(*) from public.cuentas_uso()', 'n:' || (select count(*) from public.cuentas_bancarias where empresa = 'sandal_woods'), 'F30 cuentas_uso: super_admin_empresa ve las de su empresa') ||
    pg_temp.ce('jv',  'select count(*) from public.cuentas_uso()', 'n:' || (select count(*) from public.cuentas_bancarias), 'F31 cuentas_uso: propietario todas') ||
    pg_temp.ce('ya',  'select jsonb_array_length(public.sociedades_ajustes_datos()->''sociedades'')', 'n:1', 'F32 sociedades_ajustes_datos: admin_empresa ve solo la de su empresa') ||
    pg_temp.ce('ad4', 'select jsonb_array_length(public.sociedades_ajustes_datos()->''sociedades'')', 'n:2', 'F33 sociedades_ajustes_datos: admin con las dos') ||
    pg_temp.ce('gad', 'select jsonb_array_length(public.sociedades_ajustes_datos()->''sociedades'')', 'n:' || (select count(*) from public.sociedades), 'F34 sociedades_ajustes_datos: admin global todas') ||
    pg_temp.ce('ctl', 'select jsonb_array_length(public.sociedades_ajustes_datos()->''sociedades'')', '42501', 'F35 sociedades_ajustes_datos: agente de control rechazado') ||
    pg_temp.ce('ya',  'select count(*) from public.solicitudes_pago s where public.empresa_de_solicitud_pago(s.id) = ''sandal_woods'' and s.creado_por is distinct from (select auth.uid()) and s.beneficiario_email is distinct from (select auth.email())', 'n:0', 'F36 solicitudes_pago: admin_empresa no ve las ajenas de la otra empresa') ||
    pg_temp.ce('ya',  'select count(*) from public.solicitudes_pago s where public.empresa_de_solicitud_pago(s.id) = ''lawang''', 'n:' || (select count(*) from public.solicitudes_pago s join public.contratos c1 on c1.id = s.contrato_id join public.proyectos p on p.id = c1.proyecto_id where p.empresa = 'lawang'), 'F37 solicitudes_pago: ve todas las de su empresa') ||
    pg_temp.ce('ad0', 'select count(*) from public.solicitudes_pago s where public.empresa_de_solicitud_pago(s.id) = ''lawang'' and s.creado_por is distinct from (select auth.uid()) and s.beneficiario_email is distinct from (select auth.email())', 'n:0', 'F38 solicitudes_pago: sin la casilla Comisiones solo ve las suyas') ||
    pg_temp.ce('ya',  'select count(*) from public.recibi_aplicaciones ra where exists (select 1 from public.facturas d join public.proyectos p on p.id = d.proyecto_id where d.id in (ra.recibi_id, ra.factura_id) and p.empresa = ''sandal_woods'') and not exists (select 1 from public.facturas d join public.proyectos p on p.id = d.proyecto_id where d.id in (ra.recibi_id, ra.factura_id) and p.empresa = ''lawang'')', 'n:0', 'F39 recibi_aplicaciones: ninguna aplicacion solo de la otra empresa') ||
    pg_temp.ce('ya',  'select count(*) from public.recibi_aplicaciones', 'n:' || (select count(*) from public.recibi_aplicaciones ra where exists (select 1 from public.facturas d join public.proyectos p on p.id = d.proyecto_id where d.id in (ra.recibi_id, ra.factura_id) and p.empresa = 'lawang')), 'F40 recibi_aplicaciones: ve las de los documentos de su empresa') ||
    pg_temp.ce('ya',  'select 1', 'ok', 'F41 (control de la propia prueba: una llamada trivial corre como authenticated)');

  for c in select * from jsonb_array_elements(cs_ids) loop
    sub := per->rtrim(c->>'p', '!')->>'sub'; mail := per->rtrim(c->>'p', '!')->>'email';
    perform set_config('request.jwt.claims', json_build_object('sub', sub, 'role', 'authenticated', 'email', mail)::text, true);
    begin
      if right(c->>'p', 1) <> '!' then set local role authenticated; end if;
      if (c->>'ex') like 'n:%' or (c->>'ex') like 'le:%' then
        execute c->>'q' into n;
        res := 'n:' || n;
      else
        execute c->>'q';
        res := 'ok';
      end if;
      raise exception 'F2B2OK' using errcode = 'F2B2K';
    exception
      when sqlstate 'F2B2K' then null;
      when others then res := sqlstate;
    end;
    ex := c->>'ex';
    ok := case when ex = 'no42501' then res <> '42501'
               when ex like 'le:%' then res like 'n:%' and substr(res, 3)::bigint <= substr(ex, 4)::bigint
               when ex like 'n:%' then res = ex
               else res = ex end;
    if not ok then
      r := r || format('FALLO [%s] %s -> %s (esperado %s)', c->>'p', c->>'l', res, ex) || E'\n';
      fallos := fallos + 1;
    end if;
  end loop;
  r := r || format('(%s casos ejecutados)', jsonb_array_length(cs_ids)) || E'\n';

  perform set_config('request.jwt.claims', json_build_object('sub', per->'ya'->>'sub', 'role', 'authenticated', 'email', per->'ya'->>'email')::text, true);
  set local role authenticated;
  perform public.proveedor_guarda(null, '{"nombre":"TESTB2 forzado","empresa":"sandal_woods"}'::jsonb);
  reset role;
  select count(*) into n from public.proveedores where nombre = 'TESTB2 forzado' and empresa = 'lawang';
  if n <> 1 then r := r || format('FALLO [efecto] proveedor de admin_empresa queda en su empresa (%s)', n) || E'\n'; fallos := fallos + 1; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', per->'cr'->>'sub', 'role', 'authenticated', 'email', per->'cr'->>'email')::text, true);
  set local role authenticated;
  perform public.cuenta_bancaria_guarda('zz_b2_cuenta2', '{"label":"x","titular":"x","cuenta":"1","empresa":"lawang"}'::jsonb, true);
  reset role;
  select count(*) into n from public.cuentas_bancarias where clave = 'zz_b2_cuenta2' and empresa = 'sandal_woods';
  if n <> 1 then r := r || format('FALLO [efecto] cuenta de super_admin_empresa queda en su empresa aunque mande otra (%s)', n) || E'\n'; fallos := fallos + 1; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', per->'ya'->>'sub', 'role', 'authenticated', 'email', per->'ya'->>'email')::text, true);
  set local role authenticated;
  ok := public.gasto_ruta_visible(g_l || '/x.pdf') and not public.gasto_ruta_visible(g_s || '/x.pdf') and not public.gasto_ruta_visible('basura/x.pdf');
  reset role;
  if not ok then r := r || 'FALLO [efecto] gasto_ruta_visible: suya si, ajena y basura no' || E'\n'; fallos := fallos + 1; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', per->'ya'->>'sub', 'role', 'authenticated', 'email', per->'ya'->>'email')::text, true);
  begin
    set local role authenticated;
    perform public.factura_guarda(null, jsonb_set(pay_l::jsonb, '{proyecto_nombre}', to_jsonb(ms)));
    reset role;
    select count(*) into n from public.facturas f where f.creado_por = per->'ya'->>'email' and f.contrato_id = cl and f.proyecto_id = (select c2.proyecto_id from public.contratos c2 where c2.id = cl) and f.created_at > now() - interval '5 minutes';
    if n < 1 then r := r || format('FALLO [efecto] la factura de un rol restringido cuelga del proyecto del contrato (%s)', n) || E'\n'; fallos := fallos + 1; end if;
  exception when others then
    reset role;
    r := r || format('AVISO [efecto] factura_guarda del caso 4 no llego a insertar (%s): normal si el tope de cadena del contrato esta agotado', sqlstate) || E'\n';
  end;

  raise exception E'\n%FALLOS=%', r, fallos;
end $t$;
