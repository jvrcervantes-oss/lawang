-- Prueba de guardar_recibi del 14-oct-2026 (migracion 20261014223000_recibi_total_suma_y_exento): total = suma de lo aplicado (A4),
-- importes en texto con el parser (A2), una factura repetida se rechaza, al editar el pendiente excluye lo del propio recibi (A1),
-- sin impuesto (A3), cuenta «otros» solo admin de la empresa (C3) y el recibi historico se guarda sin justificante (fallo 1, LAW-40).
-- 2.a vuelta del revisor (15-oct): el papel lo escribe el servidor (L: lineas, totales, impuesto, tipo y moneda fabricados se
-- ignoran), el historico sin justificante solo con su mismo total (H5), la moneda y la tolerancia se miran antes de numerar (M:
-- la serie facturas_recibi_seq NO se mueve en un rechazo; con el codigo de antes la frenaba el disparador con el numero gastado),
-- repetidas comparadas como uuid (A1d).
-- Rol REAL: cada llamada va con `set local role authenticated` y los claims de la persona (pg_temp.val, armazon de
-- cf_borrar_cierre_anula.sql). Cada NO lleva al lado un SI que solo cambia en lo que se prueba.
-- !! CREA CONTRATOS Y DOCUMENTOS (gasta numeracion): SOLO EN RAMA, NUNCA EN LA BASE VIVA.
--    python erp/rama_prueba.py lawang --lawang <copia de Lawang> --aplica 20261014223000_recibi_total_suma_y_exento.sql
--           --prueba recibi_total_suma_y_exento.sql
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
-- el p_factura de la pantalla: total, justificantes y datos.fields (cuenta, banco_*, impuesto) los pone quien llama
create or replace function pg_temp.rec(p_contrato uuid, p_total jsonb, p_just jsonb, p_fields jsonb) returns jsonb language sql immutable as $f$
  select jsonb_build_object('contrato_id', p_contrato, 'sociedad', 'zz_rt', 'cliente_nombre', 'ZZ-RT', 'proyecto_nombre', 'ZZ-RT Proyecto',
           'contrato_numero', 'ZZ-RT-K1', 'total', p_total, 'moneda', 'EUR', 'fecha_emision', '2026-10-14',
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
                       ('AE', gen_random_uuid(), 'zz-rt-admin-empresa@prueba.invalid');

do $todo$
declare
  r text := ''; v text; n bigint; s0 text;
  a _tp; ae _tp;
  pL uuid; k1 uuid; k2 uuid; f1 uuid; f2 uuid; f3 uuid; f4 uuid; f5 uuid; f6 uuid; f8 uuid; r1 uuid; rh uuid; rh2 uuid; ro uuid;
  d jsonb;
  j  constant jsonb := '[{"path": "zz-rt/justificante.pdf"}]';
  c_emp constant text := 'zz_rt';
  c_fin constant text := 'FIN DE PRUEBAS RECIBI TOTAL SUMA Y EXENTO (se deshace todo):%';
  c_otros constant jsonb := '{"cuenta": "otros", "banco_titular": "ZZ-RT titular", "banco_cuenta": "ZZ-RT 0001"}';
begin
  if coalesce(current_setting('erp.en_rama', true), '') <> 'si' then
    raise exception 'FIN DE PRUEBAS RECIBI TOTAL SUMA Y EXENTO:%', E'\nP0 esta prueba crea contratos y documentos: solo corre en rama → FALLA';
  end if;
  select * into a from _tp where et = 'A'; select * into ae from _tp where et = 'AE';

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
      (ae.uid, ae.em, 'ZZ-RT Admin empresa', 'admin_empresa', 'empresa', array[c_emp], '{}'::uuid[], '{}'::uuid[], '{contratos,facturas}'::text[], '{}'::text[], true);
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

  raise exception using message = replace(c_fin, '%', r);
end $todo$;
