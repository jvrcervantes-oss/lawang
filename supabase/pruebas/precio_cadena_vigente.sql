-- Prueba de precio-cadena-vigente (15-oct-2026, migración 20261015171500_precio_cadena_vigente.sql).
-- El precio de una venta solo suma la obra VIGENTE de cada parcela (la regla única de _venta_obras_vigentes); las facturas no
-- se tocan; contrato_saldo da facturado_de_mas y a_cuenta; la vista unidades_estado trae suelo_de_contrato y obra_de_contrato.
--   V1  R1 (la forma de RP00101): Bloqueo 25.000 + obra borrador 44.000 sustituida por otra firmada de 44.000, y la parcela
--       facturada dos veces (69.000 sobre el borrador + 25.000 sobre el Bloqueo). contrato_saldo, con el agente que ve la
--       raíz: precio 69.000 (antes 113.000), facturado 94.000 (la factura del borrador SIGUE contando), facturado_de_mas
--       25.000, por_facturar 0, cobrado 300 (un recibí aplicado a la factura del borrador sigue contando) y a_cuenta 400.
--   V2  el mismo agente NO ve la obra (la creó otro): contrato_saldo de la obra = 42501; el otro agente, que sí la ve, recibe
--       la misma cadena (precio 69.000).
--   V3  por la RPC que emite (factura_guarda, rol real): sobre R1 ya no se puede facturar ni 1 EUR (23514); SI de al lado:
--       sobre R2 entra justo hasta su precio vigente y el euro siguiente se rechaza.
--   V4  R2: dos parcelas y un grupo sin parcela. U2: firmada 20.000 + borrador 30.000 más nuevo → solo la firmada. U3: dos
--       borradores 15.000 y 16.000 → el más reciente. Sin unidad: borrador 5.000 cuenta; uno liberado de 7.000 no; uno en IDR
--       no. Precio = 10.000 + 20.000 + 16.000 + 5.000 = 51.000 (antes 103.000).
--   V5  la vista: suelo_de_contrato / obra_de_contrato (contrato, catálogo, sin contrato, sin permiso = null), las dos AL
--       FINAL, security_invoker, SELECT para authenticated y nada para anon. Las funciones nuevas: la regla y la cascada v2
--       no las ejecuta authenticated, anon ni service_role; unidad_cobro_reparto_v2 sí authenticated (la lee la vista) y no anon.
--   V6  la cascada (v2 y su envoltorio) y unidad_cobro_reparto dan lo mismo que la v2 en todas las unidades de la prueba; el
--       precio de la cadena = Bloqueo raíz + obras vigentes de la regla; y contra la cascada cuadra salvo la obra sin parcela
--       de una venta cuyas parcelas tienen todas obra propia (la cascada no la reparte; hoy 0 en la viva).
-- Rol REAL en cada llamada (`set local role authenticated` + claims; pg_temp.val de cliente_notas.sql).
-- !! CREA CONTRATOS, FACTURAS Y USUARIOS (gasta numeración): SOLO EN RAMA, NUNCA EN LA BASE VIVA.
--    python erp/rama_prueba.py lawang --lawang <copia de Lawang> --aplica 20261015171500_precio_cadena_vigente.sql --prueba precio_cadena_vigente.sql
-- Formato de erp/pruebas/corre.py: termina en «FIN DE PRUEBAS» y cada línea acaba en «→ ok» o «→ FALLA». Todo va marcado ZZ-PV.
-- destructivo-ok: prueba en transacción que termina en raise (rollback); solo en rama
create temp table _tp (et text primary key, uid uuid, em text);
create or replace function pg_temp.l(c boolean, t text) returns text language sql as $f$
  select E'\n' || replace(t, E'\n', ' ') || case when coalesce(c, false) then ' → ok' else ' → FALLA' end
$f$;
create or replace function pg_temp.val(p_uid uuid, p_email text, p_sql text, p_rol text default 'authenticated') returns text language plpgsql as $f$
declare t text;
begin
  perform set_config('request.jwt.claims', case when p_uid is null then '' else
          json_build_object('sub', p_uid, 'role', p_rol, 'email', p_email)::text end, true);
  execute 'set local role ' || p_rol;
  begin execute p_sql into t;
  exception when others then t := 'ERR' || sqlstate || ':' || left(sqlerrm, 200); end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return coalesce(t, '(null)');
end $f$;
-- el p_factura de la pantalla para factura_guarda (una línea de p_importe, sin impuesto)
create or replace function pg_temp.doc(p_contrato uuid, p_importe numeric) returns jsonb language sql stable as $f$
  select jsonb_build_object('tipo', 'factura', 'sociedad', 'zz_pv', 'contrato_id', p_contrato, 'moneda', 'EUR',
           'total', p_importe::text, 'cliente_nombre', 'ZZ-PV',
           'contrato_numero', (select c.numero from public.contratos c where c.id = p_contrato),
           'proyecto_nombre', 'ZZ-PV Proyecto', 'fecha_emision', '2026-10-15',
           'datos', jsonb_build_object('lineas', jsonb_build_array(jsonb_build_object('descripcion', 'ZZ-PV', 'importe', p_importe::text)),
                                       'fields', '{}'::jsonb))
$f$;
create or replace function pg_temp.saldo(p_uid uuid, p_email text, p_contrato uuid) returns text language sql as $f$
  select pg_temp.val(p_uid, p_email, format('select public.contrato_saldo(%L::uuid)::text', p_contrato))
$f$;
create or replace function pg_temp.emite(p_uid uuid, p_email text, p_contrato uuid, p_importe numeric) returns text language sql as $f$
  select pg_temp.val(p_uid, p_email, format('select (select g.id from public.factura_guarda(null, %L::jsonb) g)::text', pg_temp.doc(p_contrato, p_importe)))
$f$;

insert into _tp values ('A',  gen_random_uuid(), 'zz-pv-agente@prueba.invalid'),
                       ('B',  gen_random_uuid(), 'zz-pv-agente-obra@prueba.invalid'),
                       ('AD', gen_random_uuid(), 'zz-pv-admin@prueba.invalid');

do $todo$
declare
  r text := ''; v text; s jsonb; n bigint;
  a _tp; b _tp; ad _tp;
  pL uuid; u1 uuid; u2 uuid; u3 uuid; u4 uuid; u5 uuid;
  r1 uuid; cb uuid; cf uuid; f1 uuid; f2 uuid; rc1 uuid; rc2 uuid; rc3 uuid;
  r2 uuid; o2a uuid; o2b uuid; o3a uuid; o3b uuid; o4 uuid; o5 uuid; o6 uuid; r3 uuid;
  c_fin constant text := 'FIN DE PRUEBAS PRECIO CADENA VIGENTE (se deshace todo):%';
begin
  if coalesce(current_setting('erp.en_rama', true), '') <> 'si' then
    raise exception 'FIN DE PRUEBAS PRECIO CADENA VIGENTE:%', E'\nP0 esta prueba crea contratos, facturas y usuarios: solo corre en rama → FALLA';
  end if;
  select * into a from _tp where et = 'A'; select * into b from _tp where et = 'B'; select * into ad from _tp where et = 'AD';

  -- ============================================================ P. montaje (como postgres, SIN sesión)
  perform set_config('request.jwt.claims', '', true);
  begin
    insert into public.empresas (clave, nombre) values ('zz_pv', 'ZZ-PV Empresa');
    insert into public.sociedades (clave, label, razon, domicilio) values ('zz_pv', 'ZZ-PV', 'ZZ-PV PT', 'ZZ-domicilio')
      on conflict (clave) do nothing;
    update public.empresas set sociedad_clave = 'zz_pv' where clave = 'zz_pv';
    insert into public.proyectos (nombre, slug, empresa, activo) values ('ZZ-PV Proyecto', 'zz-pv-proyecto', 'zz_pv', true) returning id into pL;
    -- la rama nace de la ESTRUCTURA: los catálogos que siembran las migraciones vienen vacíos. Las mismas filas que la viva.
    insert into public.contrato_tipo_etapa (tipo, etapa, es_obra) values
      ('reserva_parcela', 'reserva', false), ('construccion', 'contrato', true), ('carta_reserva', 'reserva', false)
      on conflict do nothing;
    insert into public.tipos_vivienda (clave, etiqueta) values ('parcela', 'Parcela') on conflict (clave) do nothing;
    insert into auth.users (id, instance_id, email, aud, role)
      select t.uid, '00000000-0000-0000-0000-000000000000', t.em, 'authenticated', 'authenticated' from _tp t;
    insert into public.usuarios (user_id, email, nombre, rol, ambito, empresas, proyectos, proyectos_supervisados, herramientas, tipos_contrato, activo) values
      (a.uid,  a.em,  'ZZ-PV Agente',      'agente', 'global', array['zz_pv'], array[pL],    '{}'::uuid[], '{contratos,facturas,unidades}'::text[], '{reserva_parcela,construccion}'::text[], true),
      (b.uid,  b.em,  'ZZ-PV Agente obra', 'agente', 'global', array['zz_pv'], array[pL],    '{}'::uuid[], '{contratos,facturas,unidades}'::text[], '{reserva_parcela,construccion}'::text[], true),
      (ad.uid, ad.em, 'ZZ-PV Admin',       'admin',  'global', '{}'::text[],   '{}'::uuid[], '{}'::uuid[], '{contratos,facturas,unidades}'::text[], '{}'::text[], true);
    -- parcelas, contratos y documentos SIN disparadores (como invitacion_portal.sql): en la rama no hay inventario, series
    -- ni cobros con los que cuadren, y aquí solo importan las columnas que leen las funciones. Lo que rellenarían va a mano.
    execute 'set local session_replication_role = replica';
    insert into public.unidades (codigo, proyecto, proyecto_id, tipo, moneda, precio_suelo, precio_construccion, precio) values
      ('ZZ-PV-1', 'ZZ-PV Proyecto', pL, 'parcela', 'EUR', 30000, 50000, 80000) returning id into u1;
    insert into public.unidades (codigo, proyecto, proyecto_id, tipo, moneda, precio_suelo, precio_construccion, precio) values
      ('ZZ-PV-2', 'ZZ-PV Proyecto', pL, 'parcela', 'EUR', 6000, 25000, 31000) returning id into u2;
    insert into public.unidades (codigo, proyecto, proyecto_id, tipo, moneda, precio_suelo, precio_construccion, precio) values
      ('ZZ-PV-3', 'ZZ-PV Proyecto', pL, 'parcela', 'EUR', 4000, 18000, 22000) returning id into u3;
    insert into public.unidades (codigo, proyecto, proyecto_id, tipo, moneda, precio_suelo, precio_construccion, precio) values
      ('ZZ-PV-4', 'ZZ-PV Proyecto', pL, 'parcela', 'EUR', 9000, 40000, 49000) returning id into u4;   -- sin contrato
    insert into public.unidades (codigo, proyecto, proyecto_id, tipo, moneda, precio_suelo, precio_construccion, precio) values
      ('ZZ-PV-5', 'ZZ-PV Proyecto', pL, 'parcela', 'EUR', 12000, 60000, 72000) returning id into u5;  -- Bloqueo sin obra

    -- R1 = la forma de RP00101 (Bloqueo de A; las dos obras las creó B: A ve la raíz y no la obra)
    insert into public.contratos (numero, tipo, proyecto_id, proyecto_nombre, moneda, precio_total, bloqueado, datos, creado_por, created_at)
      values ('ZZ-PV-R1', 'reserva_parcela', pL, 'ZZ-PV Proyecto', 'EUR', 25000, true, '{"hitos":[]}', a.em, '2026-08-26 10:00+00') returning id into r1;
    insert into public.contratos (numero, tipo, proyecto_id, proyecto_nombre, moneda, precio_total, bloqueado, contrato_padre_id, unidad_id, datos, creado_por, created_at)
      values ('ZZ-PV-CB', 'construccion', pL, 'ZZ-PV Proyecto', 'EUR', 44000, false, r1, u1, '{"hitos":[]}', b.em, '2026-08-26 11:00+00') returning id into cb;
    insert into public.contratos (numero, tipo, proyecto_id, proyecto_nombre, moneda, precio_total, bloqueado, contrato_padre_id, unidad_id, datos, creado_por, created_at)
      values ('ZZ-PV-CF', 'construccion', pL, 'ZZ-PV Proyecto', 'EUR', 44000, true, r1, u1, '{"hitos":[]}', b.em, '2026-09-16 10:00+00') returning id into cf;
    update public.unidades set contrato_id = r1 where id = u1;
    -- la parcela facturada dos veces: 69.000 sobre el borrador sustituido y 25.000 sobre el Bloqueo
    insert into public.facturas (tipo, numero, sociedad, contrato_id, total, moneda, creado_por, cliente_nombre, datos)
      values ('factura', 'ZZ-PV-F1', 'zz_pv', cb, 69000, 'EUR', b.em, 'ZZ-PV', '{"fields": {}}'::jsonb) returning id into f1;
    insert into public.facturas (tipo, numero, sociedad, contrato_id, total, moneda, creado_por, cliente_nombre, datos)
      values ('factura', 'ZZ-PV-F2', 'zz_pv', r1, 25000, 'EUR', a.em, 'ZZ-PV', '{"fields": {}}'::jsonb) returning id into f2;
    -- recibís (históricos, sin justificante: los CHECK solo lo admiten antes del 11-ago-2026). RC1 400 sin aplicar (a
    -- cuenta); RC2 300 aplicado a F1, la factura del borrador (sigue siendo cobrado); RC3 999 anulado (no cuenta).
    insert into public.facturas (tipo, numero, sociedad, contrato_id, total, moneda, creado_por, cliente_nombre, datos, historico_sin_justificante, created_at)
      values ('recibi', 'ZZ-PV-RC1', 'zz_pv', r1, 400, 'EUR', a.em, 'ZZ-PV', '{"fields": {}}'::jsonb, true, '2026-07-01 10:00+00') returning id into rc1;
    insert into public.facturas (tipo, numero, sociedad, contrato_id, total, moneda, creado_por, cliente_nombre, datos, historico_sin_justificante, created_at)
      values ('recibi', 'ZZ-PV-RC2', 'zz_pv', cb, 300, 'EUR', b.em, 'ZZ-PV', '{"fields": {}}'::jsonb, true, '2026-07-01 10:00+00') returning id into rc2;
    insert into public.facturas (tipo, numero, sociedad, contrato_id, total, moneda, creado_por, cliente_nombre, datos, historico_sin_justificante, created_at, anulada)
      values ('recibi', 'ZZ-PV-RC3', 'zz_pv', r1, 999, 'EUR', a.em, 'ZZ-PV', '{"fields": {}}'::jsonb, true, '2026-07-01 10:00+00', true) returning id into rc3;
    insert into public.recibi_aplicaciones (recibi_id, factura_id, importe_aplicado) values (rc2, f1, 300);

    -- R2: dos parcelas y obras sin parcela (todo de A)
    insert into public.contratos (numero, tipo, proyecto_id, proyecto_nombre, moneda, precio_total, bloqueado, datos, creado_por, created_at)
      values ('ZZ-PV-R2', 'reserva_parcela', pL, 'ZZ-PV Proyecto', 'EUR', 10000, true, '{"hitos":[]}', a.em, '2026-09-01 10:00+00') returning id into r2;
    update public.unidades set contrato_id = r2 where id in (u2, u3);
    insert into public.contratos (numero, tipo, proyecto_id, proyecto_nombre, moneda, precio_total, bloqueado, contrato_padre_id, unidad_id, datos, creado_por, created_at, liberado_en) values
      ('ZZ-PV-O2A', 'construccion', pL, 'ZZ-PV Proyecto', 'EUR', 20000, true,  r2, u2,   '{"hitos":[]}', a.em, '2026-09-02 10:00+00', null),
      ('ZZ-PV-O2B', 'construccion', pL, 'ZZ-PV Proyecto', 'EUR', 30000, false, r2, u2,   '{"hitos":[]}', a.em, '2026-09-05 10:00+00', null),
      ('ZZ-PV-O3A', 'construccion', pL, 'ZZ-PV Proyecto', 'EUR', 15000, false, r2, u3,   '{"hitos":[]}', a.em, '2026-09-02 10:00+00', null),
      ('ZZ-PV-O3B', 'construccion', pL, 'ZZ-PV Proyecto', 'EUR', 16000, false, r2, u3,   '{"hitos":[]}', a.em, '2026-09-06 10:00+00', null),
      ('ZZ-PV-O4',  'construccion', pL, 'ZZ-PV Proyecto', 'EUR',  5000, false, r2, null, '{"hitos":[]}', a.em, '2026-09-03 10:00+00', null),
      ('ZZ-PV-O5',  'construccion', pL, 'ZZ-PV Proyecto', 'EUR',  7000, false, r2, null, '{"hitos":[]}', a.em, '2026-09-07 10:00+00', '2026-09-08 10:00+00'),
      ('ZZ-PV-O6',  'construccion', pL, 'ZZ-PV Proyecto', 'IDR',     9, false, r2, null, '{"hitos":[]}', a.em, '2026-09-08 10:00+00', null);
    select id into o2a from public.contratos where numero = 'ZZ-PV-O2A'; select id into o2b from public.contratos where numero = 'ZZ-PV-O2B';
    select id into o3a from public.contratos where numero = 'ZZ-PV-O3A'; select id into o3b from public.contratos where numero = 'ZZ-PV-O3B';
    select id into o4 from public.contratos where numero = 'ZZ-PV-O4';   select id into o5 from public.contratos where numero = 'ZZ-PV-O5';
    -- R3: Bloqueo sin obra (la obra de U5 sale del catálogo)
    insert into public.contratos (numero, tipo, proyecto_id, proyecto_nombre, moneda, precio_total, bloqueado, datos, creado_por, created_at)
      values ('ZZ-PV-R3', 'reserva_parcela', pL, 'ZZ-PV Proyecto', 'EUR', 11000, false, '{"hitos":[]}', a.em, '2026-09-10 10:00+00') returning id into r3;
    update public.unidades set contrato_id = r3 where id = u5;
    execute 'set local session_replication_role = origin';
    r := r || pg_temp.l(true, 'P montaje: 3 usuarios (A ve las raíces, B creó las obras de R1, admin), R1 (forma de RP00101), R2 (2 parcelas + sin parcela), R3');
  exception when others then
    raise exception using message = replace(c_fin, '%', r || pg_temp.l(false, 'P montaje: ' || sqlstate || ' ' || left(sqlerrm, 300)));
  end;

  -- ============================================================ C0 canario: el rol y las claims surten efecto
  v := pg_temp.val(a.uid, a.em, 'select current_user || ''|'' || coalesce(auth.uid()::text, ''-'')');
  r := r || pg_temp.l(v = 'authenticated|' || a.uid::text, 'C0 canario: authenticated con el uid de A (' || left(v, 60) || ')');

  -- ============================================================ V1 contrato_saldo de R1 con el agente que ve la raíz
  v := pg_temp.saldo(a.uid, a.em, r1);
  if v ~ '^ERR' then
    r := r || pg_temp.l(false, 'V1 contrato_saldo(R1) como A: ' || left(v, 160));
  else
    s := v::jsonb;
    r := r || pg_temp.l((s->>'precio')::numeric = 69000, 'V1a precio = Bloqueo 25.000 + obra VIGENTE 44.000 = 69.000; el borrador sustituido no suma (' || coalesce(s->>'precio', 'null') || ')');
    r := r || pg_temp.l((s->>'facturado')::numeric = 94000, 'V1b facturado 94.000: la factura del borrador sustituido SIGUE contando (' || coalesce(s->>'facturado', 'null') || ')');
    r := r || pg_temp.l((s->>'facturado_de_mas')::numeric = 25000 and (s->>'por_facturar')::numeric = 0,
                        'V1c facturado_de_mas 25.000 y por_facturar 0 (' || coalesce(s->>'facturado_de_mas', 'null') || ' / ' || coalesce(s->>'por_facturar', 'null') || ')');
    r := r || pg_temp.l((s->>'cobrado')::numeric = 300 and (s->>'por_cobrar')::numeric = 93700,
                        'V1d cobrado 300 (recibí aplicado a la factura del borrador) y por_cobrar 93.700 (' || coalesce(s->>'cobrado', 'null') || ' / ' || coalesce(s->>'por_cobrar', 'null') || ')');
    r := r || pg_temp.l((s->>'a_cuenta')::numeric = 400, 'V1e a_cuenta 400: RC1 sin aplicar; RC2 aplicado y RC3 anulado no (' || coalesce(s->>'a_cuenta', 'null') || ')');
    r := r || pg_temp.l(jsonb_array_length(s->'facturas') = 1 and s#>>'{facturas,0,numero}' = 'ZZ-PV-F2',
                        'V1f la lista de facturas es la del contrato pedido (solo F2)');
  end if;
  -- a_cuenta con la fórmula de _contrato_cobrado_interno: lo cobrado por la venta menos lo aplicado a sus facturas
  select coalesce(sum(public._contrato_cobrado_interno(c.id, 'EUR')), 0)
         - coalesce((select sum(ra.importe_aplicado) from public.recibi_aplicaciones ra
                       join public.facturas rr on rr.id = ra.recibi_id join public.facturas ff on ff.id = ra.factura_id
                      where ff.contrato_id in (r1, cb, cf) and not coalesce(rr.anulada, false) and not coalesce(ff.anulada, false)), 0)
    into n from public.contratos c where c.id in (r1, cb, cf);
  r := r || pg_temp.l(n = 400, 'V1g a_cuenta = Σ _contrato_cobrado_interno de la venta − lo aplicado a sus facturas (' || n || ')');
  v := pg_temp.saldo(ad.uid, ad.em, r3);
  r := r || pg_temp.l(v !~ '^ERR' and (v::jsonb->>'facturado_de_mas')::numeric = 0 and (v::jsonb->>'a_cuenta')::numeric = 0,
                      'V1h una venta sin exceso ni recibís: facturado_de_mas 0 y a_cuenta 0 (' || left(v, 120) || ')');

  -- ============================================================ V2 quien no ve la obra no ve su saldo; quien la ve, la misma cadena
  v := pg_temp.saldo(a.uid, a.em, cb);
  r := r || pg_temp.l(v like 'ERR42501:%', 'V2a A (ve la raíz, no la obra) pide el saldo de la obra: 42501 (' || left(v, 70) || ')');
  v := pg_temp.saldo(b.uid, b.em, cb);
  r := r || pg_temp.l(v !~ '^ERR' and (v::jsonb->>'precio')::numeric = 69000 and (v::jsonb->>'facturado')::numeric = 94000,
                      'V2b SI: B (creó la obra) recibe la misma cadena: precio 69.000, facturado 94.000 (' || left(v, 100) || ')');
  v := pg_temp.saldo(null, null, r1);
  r := r || pg_temp.l(v like 'ERR42501:%', 'V2c sin sesión: 42501 (' || left(v, 60) || ')');

  -- ============================================================ V3 por la RPC que emite: R1 ya no deja facturar; R2 hasta su precio
  select count(*) into n from public.facturas where contrato_id in (r1, cb, cf);
  v := pg_temp.emite(a.uid, a.em, r1, 1);
  r := r || pg_temp.l(v like 'ERR23514:%Quedan 0%' and (select count(*) from public.facturas where contrato_id in (r1, cb, cf)) = n,
                      'V3a factura_guarda de 1 EUR sobre R1 (94.000 facturados, precio 69.000): 23514 y nada nuevo (' || left(v, 110) || ')');
  v := pg_temp.emite(a.uid, a.em, r2, 51000);
  r := r || pg_temp.l(v !~ '^ERR', 'V3b SI: sobre R2 entra justo su precio vigente, 51.000 (' || left(v, 90) || ')');
  v := pg_temp.emite(a.uid, a.em, r2, 1);
  r := r || pg_temp.l(v like 'ERR23514:%Quedan 0%', 'V3c y el euro siguiente se rechaza: con la regla vieja (103.000) entraba (' || left(v, 110) || ')');

  -- ============================================================ V4 la regla por parcela, vista desde la propia función y la cadena
  select string_agg(c.numero, ',' order by c.numero) into v
    from public._venta_obras_vigentes(r2, 'EUR') o join public.contratos c on c.id = o.contrato_id;
  r := r || pg_temp.l(v = 'ZZ-PV-O2A,ZZ-PV-O3B,ZZ-PV-O4', 'V4a vigentes de R2: la firmada de U2, el borrador más reciente de U3 y el sin parcela no liberado (' || coalesce(v, 'null') || ')');
  select string_agg(c.numero, ',' order by c.numero) into v
    from public._venta_obras_vigentes(r1, 'EUR') o join public.contratos c on c.id = o.contrato_id;
  r := r || pg_temp.l(v = 'ZZ-PV-CF', 'V4b vigentes de R1: solo la firmada (' || coalesce(v, 'null') || ')');
  select s2.precio into n from public._cadena_saldo(o3a, null) s2;
  r := r || pg_temp.l(n = 51000, 'V4c el precio de la cadena pedido desde un hijo (el borrador sustituido O3A) es el de la venta: 51.000 (' || coalesce(n::text, 'null') || ')');

  -- ============================================================ V5 la vista y los permisos
  select count(*) into n from (
    select k.column_name, k.ordinal_position, max(k.ordinal_position) over () as ultima
      from information_schema.columns k where k.table_schema = 'public' and k.table_name = 'unidades_estado') x
   where (x.column_name = 'suelo_de_contrato' and x.ordinal_position = x.ultima - 1)
      or (x.column_name = 'obra_de_contrato' and x.ordinal_position = x.ultima);
  r := r || pg_temp.l(n = 2, 'V5a suelo_de_contrato y obra_de_contrato son las DOS ÚLTIMAS columnas de la vista');
  r := r || pg_temp.l((select c.reloptions::text from pg_class c where c.oid = 'public.unidades_estado'::regclass) like '%security_invoker=true%',
                      'V5b la vista sigue siendo security_invoker');
  r := r || pg_temp.l(has_table_privilege('authenticated', 'public.unidades_estado', 'select')
                      and not has_table_privilege('anon', 'public.unidades_estado', 'select')
                      and not has_table_privilege('authenticated', 'public.unidades_estado', 'insert')
                      and not has_table_privilege('authenticated', 'public.unidades_estado', 'truncate'),
                      'V5c vista: SELECT para authenticated, nada más; nada para anon');
  select count(*) into n from (values ('public._venta_obras_vigentes(uuid,text)'), ('public._unidad_cobro_cascada_v2(uuid)')) f(x)
   cross join (values ('authenticated'), ('anon'), ('service_role')) q(rol)
   where has_function_privilege(q.rol, to_regprocedure(f.x), 'execute');
  r := r || pg_temp.l(n = 0, 'V5d la regla y la cascada v2: ni authenticated, ni anon, ni service_role (' || n || ' permisos)');
  r := r || pg_temp.l(has_function_privilege('authenticated', 'public.unidad_cobro_reparto_v2(uuid)', 'execute')
                      and not has_function_privilege('anon', 'public.unidad_cobro_reparto_v2(uuid)', 'execute')
                      and not has_function_privilege('anon', 'public.unidad_cobro_reparto(uuid)', 'execute'),
                      'V5e unidad_cobro_reparto_v2: authenticated sí (la vista), anon no');
  r := r || pg_temp.l((select p.prosecdef from pg_proc p where p.oid = 'public._venta_obras_vigentes(uuid,text)'::regprocedure) = false
                      and (select 'search_path=""' = any(p.proconfig) from pg_proc p where p.oid = 'public._venta_obras_vigentes(uuid,text)'::regprocedure),
                      'V5f la regla es INVOKER con search_path vacío');
  v := pg_temp.val(ad.uid, ad.em, format(
         'select string_agg(e.codigo || ''='' || coalesce(e.suelo_de_contrato::text, ''null'') || ''/'' || coalesce(e.obra_de_contrato::text, ''null'')'
         || ' || ''/'' || coalesce(e.obra_pactada::text, ''null''), '','' order by e.codigo) from public.unidades_estado e where e.id in (%L, %L, %L, %L)', u2, u3, u4, u5));
  r := r || pg_temp.l(v = 'ZZ-PV-2=true/true/20000.00,ZZ-PV-3=true/true/16000.00,ZZ-PV-4=false/false/null,ZZ-PV-5=true/false/60000.00',
                      'V5g la vista como admin: U2 y U3 suelo y obra de contrato (20.000 y 16.000, el sin parcela no va a parcelas con obra propia), U4 sin contrato false/false, U5 obra de catálogo (' || left(v, 200) || ')');
  v := pg_temp.val(b.uid, b.em, format('select coalesce(string_agg(coalesce(e.suelo_de_contrato::text, ''null'') || ''/'' || coalesce(e.obra_de_contrato::text, ''null''), '',''), ''sin fila'') from public.unidades_estado e where e.id = %L', u1));
  r := r || pg_temp.l(v in ('null/null', 'sin fila'), 'V5h B no ve el contrato de U1: las marcas salen null (o no ve la fila), nunca false (' || left(v, 60) || ')');

  -- ============================================================ V6 la cascada, sus envoltorios y el invariante de la venta
  select count(*) into n
    from public.unidades u
    cross join lateral public._unidad_cobro_cascada(u.id) x
    cross join lateral public._unidad_cobro_cascada_v2(u.id) y
   where u.id in (u1, u2, u3, u4, u5)
     and (x.cobrado_suelo, x.cobrado_obra, x.obra_firmada, x.suelo_precio, x.obra_precio, x.suelo_de_contrato)
         is distinct from (y.cobrado_suelo, y.cobrado_obra, y.obra_firmada, y.suelo_precio, y.obra_precio, y.suelo_de_contrato);
  r := r || pg_temp.l(n = 0, 'V6a el envoltorio _unidad_cobro_cascada = las 6 primeras columnas de la v2 (' || n || ' distintas)');
  v := pg_temp.val(ad.uid, ad.em, format(
         'select count(*)::text from public.unidades u cross join lateral public.unidad_cobro_reparto(u.id) x cross join lateral public.unidad_cobro_reparto_v2(u.id) y'
         || ' where u.id in (%L, %L, %L, %L, %L) and (x.cobrado_suelo, x.cobrado_obra, x.obra_firmada, x.suelo_precio, x.obra_precio)'
         || ' is distinct from (y.cobrado_suelo, y.cobrado_obra, y.obra_firmada, y.suelo_precio, y.obra_precio)', u1, u2, u3, u4, u5));
  r := r || pg_temp.l(v = '0', 'V6b con el admin, unidad_cobro_reparto = la v2 (' || v || ' distintas)');
  -- el criterio del encargo: precio de la cadena = Bloqueo raíz + obras vigentes de la regla, sin catálogo
  select count(*) into n
    from public.contratos rz
    cross join lateral public._cadena_saldo(rz.id, null) c
   where rz.id in (r1, r2, r3)
     and c.precio is distinct from rz.precio_total + coalesce((select sum(o.precio) from public._venta_obras_vigentes(rz.id, rz.moneda) o), 0);
  r := r || pg_temp.l(n = 0, 'V6c precio de la cadena = Bloqueo raíz + obras vigentes de la regla en R1, R2 y R3 (' || n || ' que no cuadran)');
  -- y contra la cascada (lo que mira el invariante de las 141 ventas): cuadra salvo la obra SIN parcela de una venta cuyas
  -- parcelas tienen todas obra propia, que la cascada no reparte (regla de siempre, peso_sin_asignar = 0). Hoy en la viva
  -- no hay ninguna (medido el 15-oct: las 141 cuadran); aquí R2 la tiene a propósito y la diferencia es exactamente O4.
  select string_agg(x.numero || '=' || (coalesce(c.precio, 0) - coalesce(x.s, 0) - coalesce(x.o, 0))::text, ',' order by x.numero) into v
    from (select k.numero, k.id, sum(y.suelo_precio) filter (where y.suelo_de_contrato) as s,
                 sum(y.obra_precio) filter (where y.obra_de_contrato) as o
            from public.unidades u join public.contratos k on k.id = u.contrato_id
            cross join lateral public._unidad_cobro_cascada_v2(u.id) y
           where u.id in (u1, u2, u3, u5) group by k.numero, k.id) x
   cross join lateral public._cadena_saldo(x.id, null) c;
  r := r || pg_temp.l(v = 'ZZ-PV-R1=0.00,ZZ-PV-R2=5000.00,ZZ-PV-R3=0.00',
                      'V6d cadena − (suelo + obra de contrato de la cascada): 0 en R1 y R3; en R2, los 5.000 de O4 (sin parcela, todas con obra propia) (' || coalesce(v, 'null') || ')');

  raise exception using message = replace(c_fin, '%', r);
end $todo$;
