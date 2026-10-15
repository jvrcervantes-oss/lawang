-- Prueba de guardar_recibi del 14-oct-2026 (migracion 20261014223000_recibi_total_suma_y_exento): total = suma de lo aplicado (A4),
-- importes en texto con el parser (A2), una factura repetida se rechaza, al editar el pendiente excluye lo del propio recibi (A1),
-- sin impuesto (A3), cuenta «otros» solo admin de la empresa (C3) y el recibi historico se guarda sin justificante (fallo 1, LAW-40).
-- 2.a vuelta del revisor (15-oct): el papel lo escribe el servidor (L: lineas, totales, impuesto, tipo y moneda fabricados se
-- ignoran), el historico sin justificante solo con su mismo total (H5), la moneda y la tolerancia se miran antes de numerar (M:
-- la serie facturas_recibi_seq NO se mueve en un rechazo; con el codigo de antes la frenaba el disparador con el numero gastado),
-- repetidas comparadas como uuid (A1d).
-- Cambios de Seguridad (consulta de deploy, 15-oct): la exencion solo mientras la fila guardada SIGA sin justificante (H7: tras
-- H6, que le adjunta uno y la sube a 500, guardarla sin justificante con 500 se rechaza) y un historico sin justificante solo
-- salda facturas de SU contrato (H8: otro contrato del MISMO comprador se rechaza; H8b su SI con una factura de su contrato;
-- H8c con justificante el otro contrato del mismo comprador sigue entrando).
-- Hallazgo 2 del code-review (15-oct): el numero de contrato y el proyecto del papel salen del contrato comprobado (K1: un
-- recibi nuevo que manda el numero y el proyecto de OTRO contrato se guarda con los suyos, en la columna y en datos.fields, y su
-- proyecto_id es el del contrato; K2: al editar, un numero inventado tampoco entra; M3b: el SI, en otro contrato, guarda el suyo).
-- 3.a vuelta del code-review (15-oct, hallazgo 1 y BAJA 5): el proyecto sale SOLO del contrato comprobado, tambien al EDITAR.
-- K4: un recibi de K1 (proyecto 1) se edita y pasa a ZZ-RT-K5 (proyecto 2, parcela ZZ-C5): proyecto_id = proyecto 2 (antes el
-- UPDATE no lo tocaba y se quedaba el 1), columna y papel = «ZZ-RT Proyecto 2 — ZZ-C5» exactamente, la parcela del contrato
-- aunque la pantalla mande otra (« — ZZ-OTRA») y sin parcela doble. K5: contrato SIN proyecto que manda el nombre de un proyecto real: proyecto_id
-- y proyecto_nombre null y el papel sin proyecto (antes el espejo lo enlazaba por nombre). Se ensaya con 20261015055003 aplicada.
-- 4.a vuelta de Seguridad (15-oct): K6: el recibi de K4 lleva el cliente A (K6pre) y al pasar a ZZ-RT-K5, cuyo adquiriente_1 es B,
-- su client_id pasa a ser B (antes se quedaba A). K4d-K4f: el recibi pasa despues a ZZ-RT-K7, de un proyecto de OTRA empresa
-- (zz_rt2): _empresa_doc da la empresa 2 y el admin de la empresa 1, que no es su autor, recibe 42501 de la fila bloqueada (K4d,
-- su SI, edita mientras el recibi es de su empresa). Antes, con el proyecto_id viejo, la empresa seguia siendo la 1 y si editaba.
-- Rol REAL: cada llamada va con `set local role authenticated` y los claims de la persona (pg_temp.val, armazon de
-- cf_borrar_cierre_anula.sql). Cada NO lleva al lado un SI que solo cambia en lo que se prueba.
-- !! CREA CONTRATOS Y DOCUMENTOS (gasta numeracion): SOLO EN RAMA, NUNCA EN LA BASE VIVA.
--    python erp/rama_prueba.py lawang --lawang <copia de Lawang> --aplica 20261015055003_facturas_conservan_parcela.sql,20261014223000_recibi_total_suma_y_exento.sql
--           --prueba recibi_total_suma_y_exento.sql
--    (220000 en --aplica desde la 3.a vuelta: K4b y la guarda (d) de la migracion la necesitan)
-- Formato de erp/pruebas/corre.py: termina en «FIN DE PRUEBAS» y cada linea acaba en «→ ok» o «→ FALLA». Todo va marcado ZZ-RT.
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); solo en rama
create temp table _tp (et text primary key, uid uuid, em text);
create or replace function pg_temp.l(c boolean, t text) returns text language sql as $f$
  select E'\n' || replace(t, E'\n', ' ') || case when coalesce(c, false) then ' → ok' else ' → FALLA' end
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
-- el p_factura de la pantalla: total, justificantes y datos.fields (cuenta, banco_*, impuesto) los pone quien llama.
-- Numero de contrato y proyecto: los del contrato que se pasa, como hace la pantalla (editores.js, pFactura con
-- estadoContrato.numero). Hasta el 15-oct ponia siempre 'ZZ-RT-K1' y escondia que guardar_recibi copiaba el del navegador
-- (code-review, hallazgo 2): M2/M3 (K2) y H8* (K3) guardaban «ZZ-RT-K1» sin que nada lo mirara. Lee tablas: stable.
create or replace function pg_temp.rec(p_contrato uuid, p_total jsonb, p_just jsonb, p_fields jsonb) returns jsonb language sql stable as $f$
  select jsonb_build_object('contrato_id', p_contrato, 'sociedad', 'zz_rt', 'cliente_nombre', 'ZZ-RT',
           'proyecto_nombre', (select pr.nombre from public.contratos c join public.proyectos pr on pr.id = c.proyecto_id where c.id = p_contrato),
           'contrato_numero', (select c.numero from public.contratos c where c.id = p_contrato),
           'total', p_total, 'moneda', 'EUR', 'fecha_emision', '2026-10-14',
           'justificantes', p_just, 'datos', jsonb_build_object('fields', p_fields, 'lineas', '[]'::jsonb))
$f$;
-- donde esta la serie de los recibis (trg_set_factura_numero hace nextval de facturas_recibi_seq; nextval no se deshace con
-- el rollback): si un rechazo la mueve, se gasto un numero. Se lee como postgres, fuera de la sesion de la persona.
create or replace function pg_temp.serie() returns text language sql volatile as $f$
  select last_value::text || '/' || is_called::text from public.facturas_recibi_seq
$f$;
-- guardar_recibi con la sesion de quien se dice: el id del recibi, o el error
create or replace function pg_temp.guarda(p_uid uuid, p_email text, p_id uuid, p_fac jsonb, p_apl jsonb) returns text language sql as $f$
  select pg_temp.val(p_uid, p_email, format('select (public.guardar_recibi(%L::uuid, %L::jsonb, %L::jsonb))->>''id''', p_id, p_fac, p_apl))
$f$;

insert into _tp values ('A',  gen_random_uuid(), 'zz-rt-agente@prueba.invalid'),
                       ('AE', gen_random_uuid(), 'zz-rt-admin-empresa@prueba.invalid'),
                       ('AD', gen_random_uuid(), 'zz-rt-admin-global@prueba.invalid');   -- 15-oct: sin alcance restringido (K3)

do $todo$
declare
  r text := ''; v text; n bigint; s0 text;
  a _tp; ae _tp; ad _tp;
  pL uuid; p2 uuid; p3 uuid; k7 uuid; f13 uuid; cA uuid; cB uuid; rk uuid; rk4 uuid; k5 uuid; k6 uuid; f11 uuid; f12 uuid; k1 uuid; k2 uuid; k3 uuid; k4 uuid; f9 uuid; f10 uuid; rh3 uuid; f1 uuid; f2 uuid; f3 uuid; f4 uuid; f5 uuid; f6 uuid; f8 uuid; r1 uuid; rh uuid; rh2 uuid; ro uuid;
  d jsonb;
  j  constant jsonb := '[{"path": "zz-rt/justificante.pdf"}]';
  c_emp constant text := 'zz_rt';
  c_fin constant text := 'FIN DE PRUEBAS RECIBI TOTAL SUMA Y EXENTO (se deshace todo):%';
  c_otros constant jsonb := '{"cuenta": "otros", "banco_titular": "ZZ-RT titular", "banco_cuenta": "ZZ-RT 0001"}';
begin
  if coalesce(current_setting('erp.en_rama', true), '') <> 'si' then
    raise exception 'FIN DE PRUEBAS RECIBI TOTAL SUMA Y EXENTO:%', E'\nP0 esta prueba crea contratos y documentos: solo corre en rama → FALLA';
  end if;
  select * into a from _tp where et = 'A'; select * into ae from _tp where et = 'AE'; select * into ad from _tp where et = 'AD';

  -- ============================================================ P. montaje (como postgres, SIN sesion)
  perform set_config('request.jwt.claims', '', true);
  begin
    insert into public.empresas (clave, nombre) values (c_emp, 'ZZ-RT Empresa');
    insert into public.sociedades (clave, label, razon, domicilio) values ('zz_rt', 'ZZ-RT', 'ZZ-RT PT', 'ZZ-domicilio')
      on conflict (clave) do nothing;
    update public.empresas set sociedad_clave = 'zz_rt' where clave = c_emp;
    insert into public.proyectos (nombre, slug, empresa, activo) values ('ZZ-RT Proyecto', 'zz-rt-proyecto', c_emp, true) returning id into pL;
    insert into auth.users (id, instance_id, email, aud, role)
      select t.uid, '00000000-0000-0000-0000-000000000000', t.em, 'authenticated', 'authenticated' from _tp t;
    insert into public.usuarios (user_id, email, nombre, rol, ambito, empresas, proyectos, proyectos_supervisados, herramientas, tipos_contrato, activo) values
      (a.uid,  a.em,  'ZZ-RT Agente',        'agente',        'global',  array[c_emp], array[pL],    '{}'::uuid[], '{contratos,facturas}'::text[], '{contrato_general}'::text[], true),
      (ae.uid, ae.em, 'ZZ-RT Admin empresa', 'admin_empresa', 'empresa', array[c_emp], '{}'::uuid[], '{}'::uuid[], '{contratos,facturas}'::text[], '{}'::text[], true),
      (ad.uid, ad.em, 'ZZ-RT Admin global',  'admin',         'global',  '{}'::text[], '{}'::uuid[], '{}'::uuid[], '{contratos,facturas}'::text[], '{}'::text[], true);
    insert into public.contratos (numero, tipo, proyecto_id, moneda, precio_total, datos, creado_por)
      values ('ZZ-RT-K1', 'contrato_general', pL, 'EUR', 100000, '{"hitos":[]}', a.em) returning id into k1;
    -- la rama nace de la ESTRUCTURA del volcado: storage.buckets viene sin filas (el bucket lo creo 20260811034859, un dato).
    -- Se crea aqui como en esa migracion si falta; en la viva ya existe y el «on conflict» no toca nada (rama del 15-oct: 23503).
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
      values ('justificantes', 'justificantes', false, 10485760, array['image/jpeg','image/png','image/webp','application/pdf'])
      on conflict (id) do nothing;
    insert into storage.objects (bucket_id, name) values ('justificantes', 'zz-rt/justificante.pdf');
    insert into public.facturas (tipo, numero, sociedad, contrato_id, total, moneda, creado_por, cliente_nombre, datos)
      values ('factura', 'ZZ-RT-F1', 'zz_rt', k1, 300, 'EUR', a.em, 'ZZ-RT', '{"fields": {}}'::jsonb) returning id into f1;
    insert into public.facturas (tipo, numero, sociedad, contrato_id, total, moneda, creado_por, cliente_nombre, datos)
      values ('factura', 'ZZ-RT-F2', 'zz_rt', k1, 200, 'EUR', a.em, 'ZZ-RT', '{"fields": {}}'::jsonb) returning id into f2;
    insert into public.facturas (tipo, numero, sociedad, contrato_id, total, moneda, creado_por, cliente_nombre, datos)
      values ('factura', 'ZZ-RT-F3', 'zz_rt', k1, 95000, 'EUR', a.em, 'ZZ-RT', '{"fields": {}}'::jsonb) returning id into f3;
    insert into public.facturas (tipo, numero, sociedad, contrato_id, total, moneda, creado_por, cliente_nombre, datos)
      values ('factura', 'ZZ-RT-F4', 'zz_rt', k1, 500, 'EUR', a.em, 'ZZ-RT', '{"fields": {}}'::jsonb) returning id into f4;
    insert into public.facturas (tipo, numero, sociedad, contrato_id, total, moneda, creado_por, cliente_nombre, datos)
      values ('factura', 'ZZ-RT-F5', 'zz_rt', k1, 400, 'EUR', a.em, 'ZZ-RT', '{"fields": {}}'::jsonb) returning id into f5;
    -- recibi historico (LAW-40): sin justificante y sin aplicar, como REC00015; como postgres la marca se puede poner
    -- (los CHECK solo admiten la marca y la falta de justificante en recibis de antes del 11-ago-2026)
    insert into public.facturas (tipo, numero, sociedad, contrato_id, total, moneda, creado_por, cliente_nombre, datos, historico_sin_justificante, created_at)
      values ('recibi', 'ZZ-RT-RH', 'zz_rt', k1, 400, 'EUR', a.em, 'ZZ-RT', '{"fields": {}}'::jsonb, true, '2026-07-01 10:00+00') returning id into rh;
    -- 2.a vuelta: otro historico (para inflarlo), una factura EUR mas, y un contrato en IDR con su factura de 1000
    insert into public.facturas (tipo, numero, sociedad, contrato_id, total, moneda, creado_por, cliente_nombre, datos, historico_sin_justificante, created_at)
      values ('recibi', 'ZZ-RT-RH2', 'zz_rt', k1, 400, 'EUR', a.em, 'ZZ-RT', '{"fields": {}}'::jsonb, true, '2026-07-01 10:00+00') returning id into rh2;
    insert into public.facturas (tipo, numero, sociedad, contrato_id, total, moneda, creado_por, cliente_nombre, datos)
      values ('factura', 'ZZ-RT-F8', 'zz_rt', k1, 600, 'EUR', a.em, 'ZZ-RT', '{"fields": {}}'::jsonb) returning id into f8;
    insert into public.contratos (numero, tipo, proyecto_id, moneda, precio_total, datos, creado_por)
      values ('ZZ-RT-K2', 'contrato_general', pL, 'IDR', 100000, '{"hitos":[]}', a.em) returning id into k2;
    insert into public.facturas (tipo, numero, sociedad, contrato_id, total, moneda, creado_por, cliente_nombre, datos)
      values ('factura', 'ZZ-RT-F6', 'zz_rt', k2, 1000, 'IDR', a.em, 'ZZ-RT', '{"fields": {}}'::jsonb) returning id into f6;
  exception when others then
    raise exception using message = replace(c_fin, '%', pg_temp.l(false, 'P0 montaje: ' || sqlstate || ' ' || left(sqlerrm, 300)));
  end;

  -- Seguridad (15-oct): montaje de H8 en su propio bloque (contratos con datos.fields.adq1_email, que ningun otro contrato de
  -- esta prueba lleva): si falla, solo caen H8*, no la bateria. Dos contratos EUR del MISMO comprador (contrato_identificadores),
  -- un historico sin justificante en K3, una factura en K3 (F10) y otra en K4 (F9)
  begin
    insert into public.contratos (numero, tipo, proyecto_id, moneda, precio_total, datos, creado_por)
      values ('ZZ-RT-K3', 'contrato_general', pL, 'EUR', 100000, '{"hitos":[], "fields": {"adq1_email": "zz-rt-comprador@prueba.invalid"}}', a.em) returning id into k3;
    insert into public.contratos (numero, tipo, proyecto_id, moneda, precio_total, datos, creado_por)
      values ('ZZ-RT-K4', 'contrato_general', pL, 'EUR', 100000, '{"hitos":[], "fields": {"adq1_email": "zz-rt-comprador@prueba.invalid"}}', a.em) returning id into k4;
    insert into public.facturas (tipo, numero, sociedad, contrato_id, total, moneda, creado_por, cliente_nombre, datos, historico_sin_justificante, created_at)
      values ('recibi', 'ZZ-RT-RH3', 'zz_rt', k3, 400, 'EUR', a.em, 'ZZ-RT', '{"fields": {}}'::jsonb, true, '2026-07-01 10:00+00') returning id into rh3;
    insert into public.facturas (tipo, numero, sociedad, contrato_id, total, moneda, creado_por, cliente_nombre, datos)
      values ('factura', 'ZZ-RT-F10', 'zz_rt', k3, 400, 'EUR', a.em, 'ZZ-RT', '{"fields": {}}'::jsonb) returning id into f10;
    insert into public.facturas (tipo, numero, sociedad, contrato_id, total, moneda, creado_por, cliente_nombre, datos)
      values ('factura', 'ZZ-RT-F9', 'zz_rt', k4, 400, 'EUR', a.em, 'ZZ-RT', '{"fields": {}}'::jsonb) returning id into f9;
  exception when others then
    k3 := null;
    r := r || pg_temp.l(false, 'P1 montaje de H8: ' || sqlstate || ' ' || left(sqlerrm, 300));
  end;

  -- ============================================================ A4 · el total es la suma de lo aplicado
  v := pg_temp.guarda(a.uid, a.em, null, pg_temp.rec(k1, '999', j, '{}'), jsonb_build_array(jsonb_build_object('factura_id', f1, 'importe', 300)));
  r := r || pg_temp.l(v like 'ERR23514:el total del recib%', 'A4a total 999 aplicando 300: se rechaza (' || left(v, 90) || ')');
  v := pg_temp.guarda(a.uid, a.em, null, pg_temp.rec(k1, '300', j, '{}'), jsonb_build_array(jsonb_build_object('factura_id', f1, 'importe', 300)));
  r := r || pg_temp.l(v !~ '^ERR', 'A4b total 300 aplicando 300: entra (' || left(v, 90) || ')');
  if v !~ '^ERR' then
    r1 := v::uuid;
    r := r || pg_temp.l((select total from public.facturas where id = r1) = 300, 'A4c el total guardado es 300');
  end if;
  -- A1 · un rechazo no deja fila (validacion antes del insert)
  select count(*) into n from public.facturas where tipo = 'recibi' and contrato_id = k1;
  s0 := pg_temp.serie();
  v := pg_temp.guarda(a.uid, a.em, null, pg_temp.rec(k1, '1', j, '{}'), jsonb_build_array(jsonb_build_object('factura_id', f1, 'importe', 1)));
  r := r || pg_temp.l(v like 'ERR23514:la factura ZZ-RT-F1 solo tiene%'
                      and (select count(*) from public.facturas where tipo = 'recibi' and contrato_id = k1) = n
                      and pg_temp.serie() = s0,
                      'A1a aplicar 1 a una factura ya cobrada se rechaza, no deja fila y no gasta numero (' || left(v, 70) || ')');
  -- A1 · al editar, lo aplicado por el propio recibi no cuenta como cobrado de antes
  if r1 is not null then
    v := pg_temp.guarda(a.uid, a.em, r1, pg_temp.rec(k1, '300', j, '{}'), jsonb_build_array(jsonb_build_object('factura_id', f1, 'importe', 300)));
    r := r || pg_temp.l(v = r1::text, 'A1b re-guardar el mismo recibi con sus 300 entra (' || left(v, 90) || ')');
  end if;
  -- repetida
  v := pg_temp.guarda(a.uid, a.em, null, pg_temp.rec(k1, '200', j, '{}'),
         jsonb_build_array(jsonb_build_object('factura_id', f2, 'importe', 100), jsonb_build_object('factura_id', f2, 'importe', 100)));
  r := r || pg_temp.l(v like 'ERR23514:la misma factura aparece dos veces%', 'A1c la misma factura dos veces se rechaza (' || left(v, 70) || ')');
  -- el mismo uuid en mayusculas es la misma factura (como texto contaba como dos: entraban dos lineas de la misma factura)
  s0 := pg_temp.serie();
  v := pg_temp.guarda(a.uid, a.em, null, pg_temp.rec(k1, '100', j, '{}'),
         jsonb_build_array(jsonb_build_object('factura_id', f2, 'importe', 50), jsonb_build_object('factura_id', upper(f2::text), 'importe', 50)));
  r := r || pg_temp.l(v like 'ERR23514:la misma factura aparece dos veces%' and pg_temp.serie() = s0,
                      'A1d la misma factura con el uuid en mayusculas se rechaza sin gastar numero (' || left(v, 70) || ')');

  -- ============================================================ A2 · importes en texto
  v := pg_temp.guarda(a.uid, a.em, null, pg_temp.rec(k1, '"90.000"', j, '{}'), jsonb_build_array(jsonb_build_object('factura_id', f3, 'importe', '90.000')));
  r := r || pg_temp.l(v !~ '^ERR' and (select total from public.facturas where id = nullif(v, '')::uuid) = 90000
                      and (select ra.importe_aplicado from public.recibi_aplicaciones ra where ra.recibi_id = nullif(v, '')::uuid) = 90000,
                      'A2a «90.000» en texto = 90000 en total y en la aplicacion (' || left(v, 60) || ')');
  v := pg_temp.guarda(a.uid, a.em, null, pg_temp.rec(k1, '"100,50"', j, '{}'), jsonb_build_array(jsonb_build_object('factura_id', f2, 'importe', '100,50')));
  r := r || pg_temp.l(v !~ '^ERR' and (select total from public.facturas where id = nullif(v, '')::uuid) = 100.50, 'A2b «100,50» = 100.50 (' || left(v, 60) || ')');

  -- ============================================================ A3 · sin impuesto
  v := pg_temp.guarda(a.uid, a.em, null, pg_temp.rec(k1, '50', j, '{"imp_pct": "11", "imp_etiqueta": "PPN", "notas": "zz"}'),
         jsonb_build_array(jsonb_build_object('factura_id', f4, 'importe', 50)));
  r := r || pg_temp.l(v !~ '^ERR' and not ((select datos->'fields' from public.facturas where id = nullif(v, '')::uuid) ?| array['imp_pct', 'imp_etiqueta'])
                      and (select datos->'fields'->>'notas' from public.facturas where id = nullif(v, '')::uuid) = 'zz',
                      'A3 el impuesto se quita de datos.fields y lo demas se queda (' || left(v, 60) || ')');

  -- ============================================================ C3 · cuenta «otros» solo admin de la empresa
  v := pg_temp.guarda(a.uid, a.em, null, pg_temp.rec(k1, '10', j, c_otros), jsonb_build_array(jsonb_build_object('factura_id', f4, 'importe', 10)));
  r := r || pg_temp.l(v like 'ERR42501:La cuenta %', 'C3a el agente no usa «otros» (' || left(v, 70) || ')');
  v := pg_temp.guarda(ae.uid, ae.em, null, pg_temp.rec(k1, '10', j, c_otros), jsonb_build_array(jsonb_build_object('factura_id', f4, 'importe', 10)));
  r := r || pg_temp.l(v !~ '^ERR', 'C3b el admin de la empresa si (' || left(v, 70) || ')');
  if v !~ '^ERR' then
    ro := v::uuid;
    update public.facturas set creado_por = a.em where id = ro;   -- que sea del agente: puede editarlo por autoria
    v := pg_temp.guarda(a.uid, a.em, ro, pg_temp.rec(k1, '10', j, c_otros), jsonb_build_array(jsonb_build_object('factura_id', f4, 'importe', 10)));
    r := r || pg_temp.l(v = ro::text, 'C3c el agente re-guarda uno que YA la lleva, con la cuenta igual (' || left(v, 70) || ')');
    v := pg_temp.guarda(a.uid, a.em, ro, pg_temp.rec(k1, '10', j, c_otros || '{"banco_cuenta": "ZZ-RT 9999"}'), jsonb_build_array(jsonb_build_object('factura_id', f4, 'importe', 10)));
    r := r || pg_temp.l(v like 'ERR42501:La cuenta %', 'C3d pero no le cambia el numero de cuenta (' || left(v, 70) || ')');
  end if;
  v := pg_temp.guarda(a.uid, a.em, null, pg_temp.rec(k1, '5', j, '{"cuenta": "", "banco_titular": "ZZ-RT colado"}'), jsonb_build_array(jsonb_build_object('factura_id', f4, 'importe', 5)));
  r := r || pg_temp.l(v !~ '^ERR' and not ((select datos->'fields' from public.facturas where id = nullif(v, '')::uuid) ? 'banco_titular'),
                      'C3e sin «otros», los banco_* que mande un agente se descartan (' || left(v, 60) || ')');

  -- ============================================================ L · el papel lo escribe el servidor (lineas, totales, impuesto)
  -- llamada fabricada: aplica 20 a F4 y manda lineas de 999.999, totales de 999.999, impuesto del catalogo, tipo factura y USD
  v := pg_temp.guarda(a.uid, a.em, null,
         jsonb_set(pg_temp.rec(k1, '20', j, '{}'), '{datos}', jsonb_build_object(
           'fields', jsonb_build_object('imp_pct', '11', 'imp_etiqueta', 'PPN', 'tipo', 'factura', 'moneda', 'USD', 'notas', 'zz-l1',
                       'impuestos_sel', jsonb_build_array(jsonb_build_object('id', 'x', 'nombre', 'IVA 21', 'clase', 'suma', 'porcentaje', 21, 'coef_base', 1)),
                       'rectifica_numero', 'ZZ-RT-R1',
                       'lineas', jsonb_build_array(jsonb_build_object('descripcion', 'Villa entera', 'importe', '999.999'))),
           'lineas', jsonb_build_array(jsonb_build_object('descripcion', 'Villa entera', 'importe', '999.999')),
           'totales', jsonb_build_object('subtotal', 999999, 'pct', 11, 'impuesto', 109999.89, 'total', 1109998.89))),
         jsonb_build_array(jsonb_build_object('factura_id', f4, 'importe', 20)));
  if v ~ '^ERR' then
    r := r || pg_temp.l(false, 'L1 la llamada fabricada (aplica 20) entra (' || left(v, 90) || ')');
  else
    select datos into d from public.facturas where id = v::uuid;
    r := r || pg_temp.l(jsonb_array_length(d->'lineas') = 1
                        and d->'lineas'->0->>'descripcion' = 'Cobro de la factura ZZ-RT-F4 · Payment of invoice ZZ-RT-F4'
                        and d->'lineas'->0->>'importe' = '20.00' and jsonb_typeof(d->'lineas'->0->'importe') = 'string',
                        'L1 datos.lineas = la aplicada (1 linea de «20.00» en texto con el texto de conceptoCobroRecibi), no la fabricada (' || left(d->>'lineas', 110) || ')');
    r := r || pg_temp.l(d->'fields'->'lineas' = d->'lineas', 'L2 datos.fields.lineas (la que prefiere el portal) es la misma');
    r := r || pg_temp.l((d->'totales'->>'total')::numeric = 20 and (d->'totales'->>'subtotal')::numeric = 20
                        and (d->'totales'->>'impuesto')::numeric = 0 and (d->'totales'->>'pct')::numeric = 0,
                        'L3 datos.totales = {20, pct 0, impuesto 0, 20} (' || left(d->>'totales', 90) || ')');
    r := r || pg_temp.l(not ((d->'fields') ?| array['imp_pct', 'imp_etiqueta', 'impuestos_sel', 'rectifica_numero'])
                        and d->'fields'->>'notas' = 'zz-l1',
                        'L4 sin imp_pct, imp_etiqueta, impuestos_sel ni rectifica_*, y lo demas se queda');
    r := r || pg_temp.l(d->'fields'->>'tipo' = 'recibi' and d->'fields'->>'moneda' = 'EUR',
                        'L5 fields.tipo = recibi y fields.moneda = la del recibi (EUR), no las mandadas (' || coalesce(d->'fields'->>'tipo', '-') || ' ' || coalesce(d->'fields'->>'moneda', '-') || ')');
  end if;
  -- datos que no es un objeto: el servidor lo arma igual
  v := pg_temp.guarda(a.uid, a.em, null, jsonb_set(pg_temp.rec(k1, '5', j, '{}'), '{datos}', '"basura"'::jsonb),
         jsonb_build_array(jsonb_build_object('factura_id', f4, 'importe', 5)));
  r := r || pg_temp.l(v !~ '^ERR' and (select jsonb_array_length(datos->'lineas') = 1 and datos->'fields'->>'tipo' = 'recibi'
                                         from public.facturas where id = nullif(v, '')::uuid),
                      'L6 con datos que no es un objeto entra y el papel lo arma el servidor (' || left(v, 60) || ')');

  -- ============================================================ M · moneda y tolerancia antes de numerar
  s0 := pg_temp.serie();
  v := pg_temp.guarda(a.uid, a.em, null, pg_temp.rec(k1, '10', j, '{}'), jsonb_build_array(jsonb_build_object('factura_id', f6, 'importe', 10)));
  r := r || pg_temp.l(v like 'ERR23514:la factura ZZ-RT-F6 va en IDR y el recib% en EUR%' and pg_temp.serie() = s0,
                      'M1 un recibi EUR que aplica a una factura IDR se rechaza con el mensaje de guardar_recibi y sin gastar numero (' || left(v, 80) || ')');
  s0 := pg_temp.serie();
  v := pg_temp.guarda(a.uid, a.em, null, pg_temp.rec(k2, '1001', j, '{}') || '{"moneda": "IDR"}',
         jsonb_build_array(jsonb_build_object('factura_id', f6, 'importe', 1001)));
  r := r || pg_temp.l(v like 'ERR23514:la factura ZZ-RT-F6 solo tiene%' and pg_temp.serie() = s0,
                      'M2 en IDR, aplicar 1001 a una de 1000 se rechaza antes de numerar (tolerancia 0,01 como el disparador) (' || left(v, 80) || ')');
  v := pg_temp.guarda(a.uid, a.em, null, pg_temp.rec(k2, '1000', j, '{}') || '{"moneda": "IDR"}',
         jsonb_build_array(jsonb_build_object('factura_id', f6, 'importe', 1000)));
  r := r || pg_temp.l(v !~ '^ERR' and (select total from public.facturas where id = nullif(v, '')::uuid) = 1000,
                      'M3 en IDR, aplicar 1000 a una de 1000 entra (' || left(v, 70) || ')');
  -- M3b (15-oct, hallazgo 2): el recibi de K2 dice K2 (con el rec() de antes se guardaba «ZZ-RT-K1» y nada lo miraba)
  r := r || pg_temp.l(v !~ '^ERR' and (select f.contrato_numero = 'ZZ-RT-K2' and f.datos->'fields'->>'contrato_numero' = 'ZZ-RT-K2'
                                         from public.facturas f where f.id = nullif(v, '')::uuid),
                      'M3b el recibi de K2 guarda «ZZ-RT-K2» en la columna y en el papel (' || left(v, 60) || ')');

  -- ============================================================ K · el contrato del papel sale del contrato (hallazgo 2, 15-oct)
  -- otro proyecto con nombre real: si guardar_recibi se creyera el nombre mandado, trg_espejo_proyecto le pondria su proyecto_id
  begin
    insert into public.proyectos (nombre, slug, empresa, activo) values ('ZZ-RT Proyecto 2', 'zz-rt-proyecto-2', c_emp, true) returning id into p2;
  exception when others then
    r := r || pg_temp.l(false, 'K0 montaje del proyecto 2: ' || sqlstate || ' ' || left(sqlerrm, 300));
  end;
  if p2 is not null then
    -- K1 (NO): recibi NUEVO de K1 que manda el numero de K2, otro proyecto, y lo mismo en datos.fields (lo que imprime el papel)
    v := pg_temp.guarda(a.uid, a.em, null,
           pg_temp.rec(k1, '10', j, '{"contrato_numero": "ZZ-RT-K2", "proyecto_nombre": "ZZ-RT Proyecto 2", "notas": "zz-k1"}')
             || '{"contrato_numero": "ZZ-RT-K2", "proyecto_nombre": "ZZ-RT Proyecto 2"}',
           jsonb_build_array(jsonb_build_object('factura_id', f4, 'importe', 10)));
    if v ~ '^ERR' then
      r := r || pg_temp.l(false, 'K1 el recibi con numero y proyecto ajenos entra (con los suyos) (' || left(v, 90) || ')');
    else
      rk := v::uuid;
      select datos into d from public.facturas where id = rk;
      r := r || pg_temp.l((select f.contrato_numero from public.facturas f where f.id = rk) = 'ZZ-RT-K1'
                          and d->'fields'->>'contrato_numero' = 'ZZ-RT-K1',
                          'K1 manda «ZZ-RT-K2» y se guarda «ZZ-RT-K1» en la columna y en datos.fields (' ||
                          coalesce((select f.contrato_numero from public.facturas f where f.id = rk), '-') || ' / ' || coalesce(d->'fields'->>'contrato_numero', '-') || ')');
      r := r || pg_temp.l((select f.proyecto_nombre = 'ZZ-RT Proyecto' and f.proyecto_id = pL from public.facturas f where f.id = rk)
                          and d->'fields'->>'proyecto_nombre' = 'ZZ-RT Proyecto' and d->'fields'->>'notas' = 'zz-k1',
                          'K1b el proyecto es el del contrato (nombre, proyecto_id y papel), no «ZZ-RT Proyecto 2», y lo demas se queda (el agente tiene alcance restringido: eso ya lo hacia; el NO que discrimina es K3)');
      -- K2 (NO, al editar): el mismo recibi con un numero inventado en la columna y en el papel
      v := pg_temp.guarda(a.uid, a.em, rk,
             pg_temp.rec(k1, '10', j, '{"contrato_numero": "ZZ-RT-FALSO"}') || '{"contrato_numero": "ZZ-RT-FALSO"}',
             jsonb_build_array(jsonb_build_object('factura_id', f4, 'importe', 10)));
      r := r || pg_temp.l(v = rk::text
                          and (select f.contrato_numero = 'ZZ-RT-K1' and f.datos->'fields'->>'contrato_numero' = 'ZZ-RT-K1'
                                 from public.facturas f where f.id = rk),
                          'K2 al editar, «ZZ-RT-FALSO» no entra: sigue «ZZ-RT-K1» en la columna y en el papel (' || left(v, 60) || ')');
    end if;
    -- K3 (NO, sin alcance restringido): hasta el 15-oct el admin global guardaba el proyecto mandado, y con el su proyecto_id
    -- (trg_espejo_proyecto lo busca por nombre) y la empresa que _empresa_doc le atribuye al recibi
    v := pg_temp.val(ad.uid, ad.em, 'select (public.alcance_restringido() and not public.es_admin())::text');
    r := r || pg_temp.l(v = 'false', 'K3pre el admin global NO tiene alcance restringido (v_rest falso; si no, K3 no probaria nada) (' || coalesce(v, '-') || ')');
    v := pg_temp.guarda(ad.uid, ad.em, null,
           pg_temp.rec(k1, '10', j, '{"contrato_numero": "ZZ-RT-K2", "proyecto_nombre": "ZZ-RT Proyecto 2"}')
             || '{"contrato_numero": "ZZ-RT-K2", "proyecto_nombre": "ZZ-RT Proyecto 2"}',
           jsonb_build_array(jsonb_build_object('factura_id', f4, 'importe', 10)));
    -- si entra con ERR, la etiqueta no puede convertir v a uuid (rompería la batería entera): rama aparte, como K1
    if v ~ '^ERR' then
      r := r || pg_temp.l(false, 'K3 el admin global guarda un recibi de K1 (necesita _puede_herr, puede_ver_contrato y documento_visible de F4) (' || left(v, 90) || ')');
    else
      r := r || pg_temp.l((select f.contrato_numero = 'ZZ-RT-K1' and f.proyecto_nombre = 'ZZ-RT Proyecto' and f.proyecto_id = pL
                                  and f.datos->'fields'->>'contrato_numero' = 'ZZ-RT-K1' and f.datos->'fields'->>'proyecto_nombre' = 'ZZ-RT Proyecto'
                             from public.facturas f where f.id = v::uuid),
                          'K3 el admin global (sin alcance restringido) manda K2 y «ZZ-RT Proyecto 2»: se guardan K1, su proyecto y su proyecto_id (' ||
                          coalesce((select coalesce(f.contrato_numero, '-') || ' / ' || coalesce(f.proyecto_nombre, '-') from public.facturas f where f.id = v::uuid), '-') || ')');
    end if;

    -- K4 (3.a vuelta, hallazgo 1): EDITAR un recibi y pasarlo a un contrato de OTRO proyecto (editores.js, cambioContrato).
    -- Hasta el 15-oct el UPDATE no tocaba proyecto_id: trg_espejo_proyecto parte de new.proyecto_id y factura_hereda_cliente
    -- solo lo rellena si esta vacio, asi que se quedaba el proyecto 1 (y con el la empresa de _empresa_doc). Montaje en su
    -- bloque: si falla, solo cae K4. Lo hace el admin global (ve los dos proyectos; crea el recibi, asi es_suyo cubre editarlo).
    begin
      insert into public.contratos (numero, tipo, proyecto_id, moneda, precio_total, datos, creado_por)
        values ('ZZ-RT-K5', 'contrato_general', p2, 'EUR', 100000, '{"hitos":[], "fields": {"parcela_codigo": "ZZ-C5"}}', a.em) returning id into k5;
      insert into public.facturas (tipo, numero, sociedad, contrato_id, total, moneda, creado_por, cliente_nombre, datos)
        values ('factura', 'ZZ-RT-F11', 'zz_rt', k5, 400, 'EUR', a.em, 'ZZ-RT', '{"fields": {}}'::jsonb) returning id into f11;
    exception when others then
      k5 := null;
      r := r || pg_temp.l(false, 'K4 montaje (contrato ZZ-RT-K5 en el proyecto 2 con parcela ZZ-C5): ' || sqlstate || ' ' || left(sqlerrm, 300));
    end;
    -- K6 (Seguridad, 4.a vuelta): dos compradores; B es el adquiriente_1 de ZZ-RT-K5. En su bloque: si falla, cae K6 (K6pre en
    -- FALLA) y K4 sigue. propietario explicito: sin sesion, trg_clients_pone_dueno caeria a auth.email(), que aqui es null
    if k5 is not null then
      begin
        insert into public.clients (full_name, propietario) values ('ZZ-RT Cliente A', a.em) returning id into cA;
        insert into public.clients (full_name, propietario) values ('ZZ-RT Cliente B', a.em) returning id into cB;
        insert into public.contrato_compradores (contrato_id, client_id, rol) values (k5, cB, 'adquiriente_1');
      exception when others then
        cA := null; cB := null;
        r := r || pg_temp.l(false, 'K6 montaje (clientes A y B, B adquiriente_1 de ZZ-RT-K5): ' || sqlstate || ' ' || left(sqlerrm, 300));
      end;
    end if;
    if k5 is not null then
      v := pg_temp.guarda(ad.uid, ad.em, null, pg_temp.rec(k1, '10', j, '{}'), jsonb_build_array(jsonb_build_object('factura_id', f4, 'importe', 10)));
      if v ~ '^ERR' then
        r := r || pg_temp.l(false, 'K4pre el admin global crea un recibi de K1 (' || left(v, 90) || ')');
      else
        rk4 := v::uuid;
        r := r || pg_temp.l((select f.proyecto_id = pL and f.proyecto_nombre = 'ZZ-RT Proyecto' from public.facturas f where f.id = rk4),
                            'K4pre el recibi nace en K1 con el proyecto 1 (si no, K4 no probaria el cambio)');
        -- K6pre: el recibi lleva el cliente A, como uno ya heredado del comprador de su contrato (ZZ-RT-K1 no tiene comprador:
        -- sin esto client_id seria null, el disparador lo rellenaria igual con B y K6 pasaria tambien con el codigo de antes)
        if cA is not null then update public.facturas set client_id = cA where id = rk4; end if;
        r := r || pg_temp.l((select f.client_id = cA from public.facturas f where f.id = rk4),
                            'K6pre el recibi de K1 lleva el cliente A antes de cambiarlo de contrato (si no, K6 no probaria nada)');
        -- la pantalla manda el proyecto CON la parcela (editores.js, aplicaContratoDoc); aqui con OTRA parcela (ZZ-OTRA), para
        -- que la linea distinga «sale del contrato» de «se copia lo mandado» y vea que no se dobla
        v := pg_temp.guarda(ad.uid, ad.em, rk4,
               pg_temp.rec(k5, '10', j, '{"proyecto_nombre": "ZZ-RT Proyecto 2 — ZZ-OTRA"}') || '{"proyecto_nombre": "ZZ-RT Proyecto 2 — ZZ-OTRA"}',
               jsonb_build_array(jsonb_build_object('factura_id', f11, 'importe', 10)));
        if v is distinct from rk4::text then
          r := r || pg_temp.l(false, 'K4 el admin global pasa el recibi de K1 a K5 (' || left(coalesce(v, '-'), 90) || ')');
        else
          select datos into d from public.facturas where id = rk4;
          r := r || pg_temp.l((select f.proyecto_id = p2 from public.facturas f where f.id = rk4),
                              'K4 al pasar el recibi a un contrato del proyecto 2, su proyecto_id pasa a ser el 2 (antes se quedaba el 1)');
          r := r || pg_temp.l((select f.proyecto_nombre = 'ZZ-RT Proyecto 2 — ZZ-C5' from public.facturas f where f.id = rk4)
                              and d->'fields'->>'proyecto_nombre' = 'ZZ-RT Proyecto 2 — ZZ-C5',
                              'K4b manda «… — ZZ-OTRA» y columna y papel = «ZZ-RT Proyecto 2 — ZZ-C5» (la parcela del contrato), iguales y sin parcela doble (' ||
                              coalesce((select f.proyecto_nombre from public.facturas f where f.id = rk4), '-') || ' / ' || coalesce(d->'fields'->>'proyecto_nombre', '-') || ')');
          r := r || pg_temp.l((select f.contrato_id = k5 and f.contrato_numero = 'ZZ-RT-K5' from public.facturas f where f.id = rk4)
                              and d->'fields'->>'contrato_numero' = 'ZZ-RT-K5'
                              and (select count(*) = 1 and bool_and(ra.factura_id = f11) from public.recibi_aplicaciones ra where ra.recibi_id = rk4),
                              'K4c contrato_id, contrato_numero (columna y papel) y la aplicacion son los de K5');
          -- K6 (Seguridad, 4.a vuelta): al cambiar de contrato, el cliente se vuelve a heredar del contrato NUEVO. Antes el UPDATE
          -- dejaba el client_id de A (no null: trg_factura_hereda_cliente no lo tocaba) en el recibi ya del contrato de B
          r := r || pg_temp.l((select f.client_id = cB and f.client_id is distinct from cA from public.facturas f where f.id = rk4),
                              'K6 el recibi del cliente A pasa a ZZ-RT-K5 (adquiriente_1 = B) y su client_id pasa a ser B, no A (' ||
                              coalesce((select case f.client_id when cA then 'A' when cB then 'B' else coalesce(f.client_id::text, 'null') end
                                          from public.facturas f where f.id = rk4), '-') || ')');

          -- K4d-K4f (Seguridad, 4.a vuelta): el recibi pasa a un contrato de OTRA empresa y el admin de la empresa 1, que no es su
          -- autor, ya no lo edita. Con el UPDATE de antes (proyecto_id viejo) _empresa_doc seguia dando la empresa 1 y si podia.
          -- Montaje en su bloque: si falla, solo caen K4d-K4f
          begin
            insert into public.empresas (clave, nombre) values ('zz_rt2', 'ZZ-RT Empresa 2');
            insert into public.proyectos (nombre, slug, empresa, activo) values ('ZZ-RT Proyecto 3', 'zz-rt-proyecto-3', 'zz_rt2', true) returning id into p3;
            insert into public.contratos (numero, tipo, proyecto_id, moneda, precio_total, datos, creado_por)
              values ('ZZ-RT-K7', 'contrato_general', p3, 'EUR', 100000, '{"hitos":[], "fields": {"parcela_codigo": "ZZ-C7"}}', a.em) returning id into k7;
            insert into public.facturas (tipo, numero, sociedad, contrato_id, total, moneda, creado_por, cliente_nombre, datos)
              values ('factura', 'ZZ-RT-F13', 'zz_rt', k7, 400, 'EUR', a.em, 'ZZ-RT', '{"fields": {}}'::jsonb) returning id into f13;
          exception when others then
            k7 := null;
            r := r || pg_temp.l(false, 'K4d montaje (empresa zz_rt2, proyecto 3, contrato ZZ-RT-K7): ' || sqlstate || ' ' || left(sqlerrm, 300));
          end;
          if k7 is not null then
            -- pre: ae es admin de la empresa 1 y no de la 2, y no es el autor del recibi (si lo fuera, es_suyo le dejaria editar)
            v := pg_temp.val(ae.uid, ae.em, 'select public.es_admin_de(''zz_rt'')::text || ''/'' || public.es_admin_de(''zz_rt2'')::text');
            r := r || pg_temp.l(v = 'true/false' and (select lower(coalesce(f.creado_por, '')) <> lower(ae.em) from public.facturas f where f.id = rk4),
                                'K4dpre el admin de la empresa 1 lo es de zz_rt y no de zz_rt2, y no es el autor del recibi (' || coalesce(v, '-') || ')');
            -- SI: mientras el recibi es de la empresa 1, ae lo edita (mismo contrato ZZ-RT-K5: el cliente B se conserva)
            v := pg_temp.guarda(ae.uid, ae.em, rk4, pg_temp.rec(k5, '10', j, '{}'), jsonb_build_array(jsonb_build_object('factura_id', f11, 'importe', 10)));
            r := r || pg_temp.l(v = rk4::text and (select f.client_id = cB from public.facturas f where f.id = rk4),
                                'K4d SI el admin de la empresa 1 edita el recibi mientras es de su empresa, y en el mismo contrato el cliente B se queda (' || left(coalesce(v, '-'), 70) || ')');
            -- el admin global lo pasa a ZZ-RT-K7 (empresa 2)
            v := pg_temp.guarda(ad.uid, ad.em, rk4, pg_temp.rec(k7, '10', j, '{}'), jsonb_build_array(jsonb_build_object('factura_id', f13, 'importe', 10)));
            r := r || pg_temp.l(v = rk4::text
                                and (select f.contrato_id = k7 and f.proyecto_id = p3 and public._empresa_doc(f.proyecto_id, f.contrato_id) = 'zz_rt2'
                                       from public.facturas f where f.id = rk4),
                                'K4e el admin global lo pasa a ZZ-RT-K7 y _empresa_doc(proyecto_id, contrato_id) da la empresa 2 (' ||
                                left(coalesce(v, '-'), 40) || ' / ' || coalesce((select public._empresa_doc(f.proyecto_id, f.contrato_id) from public.facturas f where f.id = rk4), '-') || ')');
            -- NO: ae manda un contrato que SI ve (ZZ-RT-K1), para que lo pare la fila bloqueada con su filtro de autoria y no la
            -- puerta de «contrato que no ves»
            v := pg_temp.guarda(ae.uid, ae.em, rk4, pg_temp.rec(k1, '10', j, '{}'), jsonb_build_array(jsonb_build_object('factura_id', f4, 'importe', 10)));
            r := r || pg_temp.l(v like 'ERR42501:no se pudo actualizar%'
                                and (select f.contrato_id = k7 from public.facturas f where f.id = rk4)
                                and (select count(*) = 1 and bool_and(ra.factura_id = f13) from public.recibi_aplicaciones ra where ra.recibi_id = rk4),
                                'K4f NO el admin de la empresa 1 ya no edita el recibi de la empresa 2: 42501 y sigue en ZZ-RT-K7 con su aplicacion (' || left(coalesce(v, '-'), 70) || ')');
          end if;
        end if;
      end if;
    end if;

    -- K5 (BAJA 5): contrato SIN proyecto. Lo que mande la pantalla como proyecto se ignora: proyecto_id y proyecto_nombre null
    -- y el papel sin «Proyecto». Antes, con proyecto_id null, trg_espejo_proyecto buscaba el proyecto por el nombre mandado y
    -- se lo ponia al recibi (y con el una empresa). Montaje en su bloque.
    begin
      insert into public.contratos (numero, tipo, proyecto_id, moneda, precio_total, datos, creado_por)
        values ('ZZ-RT-K6', 'contrato_general', null, 'EUR', 100000, '{"hitos":[], "fields": {"parcela_codigo": "ZZ-C6"}}', a.em) returning id into k6;
      insert into public.facturas (tipo, numero, sociedad, contrato_id, total, moneda, creado_por, cliente_nombre, datos)
        values ('factura', 'ZZ-RT-F12', 'zz_rt', k6, 400, 'EUR', a.em, 'ZZ-RT', '{"fields": {}}'::jsonb) returning id into f12;
    exception when others then
      k6 := null;
      r := r || pg_temp.l(false, 'K5 montaje (contrato ZZ-RT-K6 sin proyecto): ' || sqlstate || ' ' || left(sqlerrm, 300));
    end;
    if k6 is not null then
      r := r || pg_temp.l((select c.proyecto_id is null from public.contratos c where c.id = k6),
                          'K5pre el contrato ZZ-RT-K6 no tiene proyecto (si no, K5 no probaria nada)');
      v := pg_temp.guarda(ad.uid, ad.em, null,
             pg_temp.rec(k6, '10', j, '{"proyecto_nombre": "ZZ-RT Proyecto 2"}') || '{"proyecto_nombre": "ZZ-RT Proyecto 2"}',
             jsonb_build_array(jsonb_build_object('factura_id', f12, 'importe', 10)));
      if v ~ '^ERR' then
        r := r || pg_temp.l(false, 'K5 el admin global guarda un recibi de un contrato sin proyecto (' || left(v, 90) || ')');
      else
        r := r || pg_temp.l((select f.proyecto_id is null and f.proyecto_nombre is null and f.contrato_numero = 'ZZ-RT-K6'
                                    and not ((f.datos->'fields') ? 'proyecto_nombre')
                               from public.facturas f where f.id = v::uuid),
                            'K5 contrato sin proyecto y «ZZ-RT Proyecto 2» mandado: proyecto_id y proyecto_nombre null, papel sin proyecto (' ||
                            coalesce((select coalesce(f.proyecto_id::text, '-') || ' / ' || coalesce(f.proyecto_nombre, '-') from public.facturas f where f.id = v::uuid), '-') || ')');
      end if;
    end if;
  end if;

  -- ============================================================ fallo 1 · el historico sin justificante se aplica (LAW-40)
  v := pg_temp.guarda(a.uid, a.em, rh, pg_temp.rec(k1, '400', '[]', '{}'), jsonb_build_array(jsonb_build_object('factura_id', f5, 'importe', 400)));
  r := r || pg_temp.l(v = rh::text, 'H1 el recibi historico se aplica sin justificante (' || left(v, 90) || ')');
  r := r || pg_temp.l((select coalesce(sum(importe_aplicado), 0) from public.recibi_aplicaciones where recibi_id = rh) = 400, 'H1b y queda aplicado entero: 400');
  v := pg_temp.guarda(a.uid, a.em, null, pg_temp.rec(k1, '1', '[]', '{}'), jsonb_build_array(jsonb_build_object('factura_id', f2, 'importe', 1)));
  r := r || pg_temp.l(v like 'ERR23514:el recibi necesita un justificante%', 'H2 un recibi NUEVO sin justificante sigue rechazado (' || left(v, 70) || ')');
  v := pg_temp.guarda(a.uid, a.em, null, pg_temp.rec(k1, '1', '[]', '{}') || '{"historico_sin_justificante": true}', jsonb_build_array(jsonb_build_object('factura_id', f2, 'importe', 1)));
  r := r || pg_temp.l(v like 'ERR23514:el recibi necesita un justificante%', 'H3 mandar la marca en el payload no exime (' || left(v, 70) || ')');
  v := pg_temp.guarda(a.uid, a.em, rh, pg_temp.rec(k1, '0', '[]', '{}'), '[]'::jsonb);
  r := r || pg_temp.l(v like 'ERR23514:el recibi necesita al menos una factura%'
                      and (select coalesce(sum(importe_aplicado), 0) from public.recibi_aplicaciones where recibi_id = rh) = 400,
                      'H4 el historico no se puede dejar a 0: sin aplicaciones se rechaza y sigue con sus 400 (' || left(v, 60) || ')');
  -- la exencion tiene limite (15-oct): un historico sin justificante no se infla
  v := pg_temp.guarda(a.uid, a.em, rh2, pg_temp.rec(k1, '500', '[]', '{}'), jsonb_build_array(jsonb_build_object('factura_id', f8, 'importe', 500)));
  r := r || pg_temp.l(v like 'ERR23514:el recib% hist%rico ZZ-RT-RH2 no tiene justificante%'
                      and (select total from public.facturas where id = rh2) = 400
                      and not exists (select 1 from public.recibi_aplicaciones where recibi_id = rh2),
                      'H5 inflar un historico sin justificante (400 -> 500) se rechaza y sigue en 400 sin aplicar (' || left(v, 70) || ')');
  v := pg_temp.guarda(a.uid, a.em, rh2, pg_temp.rec(k1, '500', j, '{}'), jsonb_build_array(jsonb_build_object('factura_id', f8, 'importe', 500)));
  r := r || pg_temp.l(v = rh2::text and (select total from public.facturas where id = rh2) = 500,
                      'H6 con justificante el mismo historico si cambia a 500 (' || left(v, 70) || ')');
  -- Seguridad (15-oct), cambio 1: tras H6 la fila ya tiene justificante; guardarla SIN el con los valores nuevos (500) coincidia
  -- con la fila guardada y pasaba (recibi inflado que se quedaba sin justificante y con la marca LAW-40)
  v := pg_temp.guarda(a.uid, a.em, rh2, pg_temp.rec(k1, '500', '[]', '{}'), jsonb_build_array(jsonb_build_object('factura_id', f8, 'importe', 500)));
  r := r || pg_temp.l(v like 'ERR23514:el recibi necesita un justificante%'
                      and (select total from public.facturas where id = rh2) = 500
                      and (select jsonb_array_length(justificantes) from public.facturas where id = rh2) = 1
                      and (select coalesce(sum(importe_aplicado), 0) from public.recibi_aplicaciones where recibi_id = rh2) = 500,
                      'H7 un historico que ya tiene justificante no se guarda sin el: se rechaza y sigue con su justificante y sus 500 (' || left(v, 70) || ')');

  -- Seguridad (15-oct), cambio 2: un historico sin justificante solo salda facturas de SU contrato
  if k3 is not null then
    r := r || pg_temp.l(k3 <> k4 and public.contratos_mismo_comprador(k3, k4),
                        'H8pre K3 y K4 son contratos distintos del MISMO comprador (si no, H8 probaria la rama de otro comprador)');
    -- H8b primero (SI): el historico sin justificante, a una factura de SU contrato, entra; asi H8 parte de un recibi CON
    -- aplicaciones y puede comprobar que el rechazo no las toca (code-review 15-oct: con RH3 vacio no se podia ver)
    v := pg_temp.guarda(a.uid, a.em, rh3, pg_temp.rec(k3, '400', '[]', '{}'), jsonb_build_array(jsonb_build_object('factura_id', f10, 'importe', 400)));
    r := r || pg_temp.l(v = rh3::text
                        and (select coalesce(sum(importe_aplicado), 0) from public.recibi_aplicaciones where recibi_id = rh3 and factura_id = f10) = 400,
                        'H8b el historico sin justificante, a una factura de SU contrato, entra (' || left(v, 70) || ')');
    v := pg_temp.guarda(a.uid, a.em, rh3, pg_temp.rec(k3, '400', '[]', '{}'), jsonb_build_array(jsonb_build_object('factura_id', f9, 'importe', 400)));
    r := r || pg_temp.l(v like 'ERR23514:el recib% hist%rico ZZ-RT-RH3 no tiene justificante%sobre facturas de su contrato%'
                        and (select count(*) from public.recibi_aplicaciones where recibi_id = rh3) = 1
                        and (select coalesce(sum(importe_aplicado), 0) from public.recibi_aplicaciones where recibi_id = rh3 and factura_id = f10) = 400
                        and not exists (select 1 from public.recibi_aplicaciones where factura_id = f9),
                        'H8 un historico sin justificante no se mueve a una factura de OTRO contrato del mismo comprador: se rechaza y sigue aplicado a F10 (' || left(v, 70) || ')');
    v := pg_temp.guarda(a.uid, a.em, rh3, pg_temp.rec(k3, '400', j, '{}'), jsonb_build_array(jsonb_build_object('factura_id', f9, 'importe', 400)));
    r := r || pg_temp.l(v = rh3::text
                        and (select coalesce(sum(importe_aplicado), 0) from public.recibi_aplicaciones where recibi_id = rh3 and factura_id = f9) = 400,
                        'H8c con justificante, el otro contrato del mismo comprador sigue entrando (' || left(v, 70) || ')');
  end if;

  raise exception using message = replace(c_fin, '%', r);
end $todo$;
