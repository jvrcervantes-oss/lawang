-- Prueba de MCP F1-P2 (16-oct-2026, migración 20261016120000_mcp_f1_p2_herramientas.sql): las 10 `privado.mcp_*`.
-- Encargo: encargos/20261015_erp_mcp.md (Lawang F1-P2). Armazón de precio_cadena_vigente.sql / contrato_propio_permiso_agente.sql.
--   C   canarios: el rol del puente surte efecto, la sesión simulada llega a auth.uid(), e ia_puente_rol no lee una tabla
--       ni llama a un lector `public.mcp_*_lee` (solo las 10 puertas).
--   S   el super admin (SA) ve lo sembrado, sin `error`, con las cifras esperadas (una aserción por herramienta).
--   A   el agente CON las casillas (AG, su proyecto pX) no ve nada de lo sembrado en pM (0 filas de más que su pantalla) y
--       sí su parcela de pX; las herramientas de rol admin le contestan «sin_permiso».
--   N   el agente SIN casillas (AGN): «sin_permiso» en las 10.
--   K   ningún resultado lleva claves de comprador ni texto libre (email, nombre_comprador, passport, notas, concepto,
--       motivo, detalle, datos anidado), ni los textos sembrados como cebo («ZZ-SECRETO»).
--   E   exposición: dueños, volatilidad, EXECUTE, sin SQL dinámico, y las patas (d)+(e) del invariante de salud de lw_lector.
--   R   (AL FINAL) cada mcp_* corre bajo `transaction_read_only = on` con la siembra hecha y ninguna escribe fuera de la
--       puerta (el stub de la puerta no escribe). Después de esto la transacción ya no puede volver a escritura.
-- Sesión simulada = la que fijará ia_puente: request.jwt.claims {sub, email, role:'authenticated', app_metadata (el
-- raw_app_meta_data del usuario sembrado), aal:'aal1'} + request.jwt.claim.sub/email/role, todo con is_local = true, y
-- `set local role ia_puente_rol`.
-- !! CREA USUARIOS, CONTRATOS, FACTURAS Y GASTOS: SOLO EN RAMA, NUNCA EN LA BASE VIVA (P0 lo comprueba).
--    python erp/rama_prueba.py lawang --lawang <copia de Lawang> --aplica 20261016110000_mcp_f1_p1_base.sql,20261016120000_mcp_f1_p2_herramientas.sql --prueba mcp_f1_p2_herramientas.sql
-- Formato de erp/pruebas/corre.py: termina en «FIN DE PRUEBAS» y cada línea acaba en «→ ok» o «→ FALLA». Todo va marcado ZZ-MCP.
-- destructivo-ok: prueba en transacción que termina en raise (rollback); solo en rama
--
-- ── 0. STUB DE P1 ─────────────────────────────────────────────────────────────────────────────────────── stub de prueba: lo sustituye P1
-- Mientras P1 no exista: privado.mcp_puerta (siempre ok, llamada 1), privado.mcp_cierra (no hace nada), el rol
-- ia_puente_rol y su USAGE en `privado`. NINGUNO escribe. OJO: la migración P2 hace `grant … to ia_puente_rol`, así que
-- sin P1 este bloque tiene que correr ANTES de la migración (pegado delante en la misma petición); en cuanto exista P1
-- se borra este bloque entero y se pasa P1 en --aplica.
do $stub$
begin
  if not exists (select 1 from pg_roles where rolname = 'ia_puente_rol') then
    create role ia_puente_rol nologin noinherit nobypassrls;                       -- stub de prueba: lo sustituye P1
  end if;
end $stub$;
create or replace function privado.mcp_puerta(p_herramienta text, p_args jsonb)  -- stub de prueba: lo sustituye P1
returns jsonb language sql security definer set search_path = '' as $f$ select jsonb_build_object('ok', true, 'llamada', 1) $f$;
create or replace function privado.mcp_cierra(p_llamada bigint, p_filas int, p_resultado text)  -- stub de prueba: lo sustituye P1
returns void language plpgsql security definer set search_path = '' as $f$ begin null; end $f$;
revoke all on function privado.mcp_puerta(text, jsonb), privado.mcp_cierra(bigint, int, text) from public, anon, authenticated, service_role;  -- stub
grant usage on schema privado to ia_puente_rol;                                                                                  -- stub
-- (a lw_lector NADA en `privado`: ni USAGE ni EXECUTE; las puertas son de postgres, ver la cabecera de la migración)
grant ia_puente_rol to postgres;                                                                                                   -- stub: para `set local role`
-- ── fin del stub ─────────────────────────────────────────────────────────────────────────────────────────────────────

create temp table _tp (et text primary key, uid uuid, em text, app jsonb);
create or replace function pg_temp.l(c boolean, t text) returns text language sql as $f$
  select E'\n' || replace(t, E'\n', ' ') || case when coalesce(c, false) then ' → ok' else ' → FALLA' end
$f$;
-- Llamada como la hará ia_puente: claims completas + claim.* sueltas, rol ia_puente_rol; nunca como postgres.
create or replace function pg_temp.mcp(p_uid uuid, p_email text, p_app jsonb, p_sql text) returns text language plpgsql as $f$
declare t text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'email', p_email, 'role', 'authenticated',
                                                             'app_metadata', coalesce(p_app, '{}'::jsonb), 'aal', 'aal1')::text, true);
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  perform set_config('request.jwt.claim.email', p_email, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role ia_puente_rol';
  begin execute p_sql into t;
  exception when others then t := 'ERR' || sqlstate || ':' || left(sqlerrm, 200); end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.email', '', true);
  perform set_config('request.jwt.claim.role', '', true);
  return coalesce(t, '(null)');
end $f$;
-- respuesta → jsonb sin abortar el bloque: un ERR… o un (null) dan null (si no, un solo cast malo tumba la prueba entera)
create or replace function pg_temp.js(t text) returns jsonb language sql immutable as $f$
  select case when t is null or t ~ '^ERR' or t = '(null)' then null else t::jsonb end
$f$;
-- claves prohibidas en cualquier nivel, y `datos` solo arriba (la envoltura {datos, recortado}).
create or replace function pg_temp.limpio(t text) returns boolean language sql immutable as $f$
  select t !~* '"[a-z_]*(email|passport|nombre_comprador|comprador_nombre|notas|concepto|motivo|detalle|telefono|firmante)[a-z_]*"\s*:'
     and coalesce(array_length(regexp_split_to_array(t, '"datos"\s*:'), 1), 1) <= 2
     and t !~ 'ZZ-SECRETO'
     and t !~ '@'
$f$;
-- las 10 llamadas, sin argumentos (el mes y la semana por defecto = hoy en Makassar, que es cuando se siembra)
create temp table _h (herr text primary key, q text, rol_admin boolean);
insert into _h values
  ('parcelas_libres',          'select privado.mcp_parcelas_libres()::text', false),
  ('comisiones_pendientes',    'select privado.mcp_comisiones_pendientes()::text', false),
  ('cobros_por_proyecto_mes',  'select privado.mcp_cobros_por_proyecto_mes()::text', true),
  ('cambios_estado_semana',    'select privado.mcp_cambios_estado_semana()::text', true),
  ('contratos_sin_firmar',     'select privado.mcp_contratos_sin_firmar()::text', false),
  ('resumen_semana',           'select privado.mcp_resumen_semana()::text', true),
  ('facturas_no_cobradas',     'select privado.mcp_facturas_no_cobradas()::text', false),
  ('recibis_sin_aplicar',      'select privado.mcp_recibis_sin_aplicar()::text', false),
  ('ventas_facturadas_de_mas', 'select privado.mcp_ventas_facturadas_de_mas()::text', false),
  ('movimientos_mes_sociedad', 'select privado.mcp_movimientos_mes_sociedad()::text', false);

insert into _tp values ('SA',  gen_random_uuid(), 'zz-mcp-super@prueba.invalid',  '{"provider":"email","providers":["email"]}'),
                       ('AG',  gen_random_uuid(), 'zz-mcp-agente@prueba.invalid', '{"provider":"email","providers":["email"]}'),
                       ('AGN', gen_random_uuid(), 'zz-mcp-sin@prueba.invalid',    '{"provider":"email","providers":["email"]}');

do $todo$
declare
  r text := ''; v text; j jsonb; n bigint; h record; t0 timestamptz; ms numeric; cebo text;
  sa _tp; ag _tp; agn _tp;
  pM uuid; pX uuid; u1 uuid; u2 uuid; u3 uuid; c1 uuid; c2 uuid; f1 uuid; r1 uuid; g1 uuid; m1 uuid; cd1 uuid;
  v_hoy date := (now() at time zone 'Asia/Makassar')::date;
  c_fin constant text := 'FIN DE PRUEBAS MCP F1-P2 (se deshace todo):%';
begin
  if coalesce(current_setting('erp.en_rama', true), '') <> 'si' then
    raise exception 'FIN DE PRUEBAS MCP F1-P2:%', E'\nP0 esta prueba crea usuarios, contratos y facturas: solo corre en rama → FALLA';
  end if;
  select * into sa from _tp where et = 'SA'; select * into ag from _tp where et = 'AG'; select * into agn from _tp where et = 'AGN';

  -- ============================================================ P. montaje (como postgres, SIN sesión)
  perform set_config('request.jwt.claims', '', true);
  begin
    insert into public.empresas (clave, nombre) values ('zz_mcp', 'ZZ-MCP Empresa');
    insert into public.sociedades (clave, label, razon, domicilio) values ('zz_mcp', 'ZZ-MCP', 'ZZ-MCP PT', 'ZZ-domicilio')
      on conflict (clave) do nothing;
    update public.empresas set sociedad_clave = 'zz_mcp' where clave = 'zz_mcp';
    insert into public.proyectos (nombre, slug, empresa, activo) values ('ZZ-MCP Proyecto', 'zz-mcp-proyecto', 'zz_mcp', true) returning id into pM;
    insert into public.proyectos (nombre, slug, empresa, activo) values ('ZZ-MCP Proyecto agente', 'zz-mcp-proyecto-ag', 'zz_mcp', true) returning id into pX;
    insert into public.contrato_tipo_etapa (tipo, etapa, es_obra) values ('reserva_parcela', 'reserva', false), ('construccion', 'contrato', true)
      on conflict do nothing;
    insert into public.tipos_vivienda (clave, etiqueta) values ('parcela', 'Parcela') on conflict (clave) do nothing;
    insert into auth.users (id, instance_id, email, aud, role, raw_app_meta_data)
      select t.uid, '00000000-0000-0000-0000-000000000000', t.em, 'authenticated', 'authenticated', t.app from _tp t;
    insert into public.usuarios (user_id, email, nombre, rol, ambito, empresas, proyectos, proyectos_supervisados, herramientas, tipos_contrato, activo) values
      (sa.uid,  sa.em,  'ZZ-MCP Super',  'super_admin', 'global', '{}'::text[],        '{}'::uuid[],   '{}'::uuid[], '{}'::text[], '{}'::text[], true),
      (ag.uid,  ag.em,  'ZZ-MCP Agente', 'agente',      'global', array['zz_mcp'],     array[pX],      '{}'::uuid[],
       '{unidades,contratos,facturas,recibos,comisiones_reparto}'::text[], '{}'::text[], true),
      (agn.uid, agn.em, 'ZZ-MCP Sin',    'agente',      'global', array['zz_mcp'],     array[pX],      '{}'::uuid[], '{}'::text[], '{}'::text[], true);
    -- el resto SIN disparadores (como precio_cadena_vigente.sql): en la rama no hay series ni cobros con los que cuadren,
    -- y los registros que escribirían los triggers (unidades_log, contrato_eventos) van a mano, con cebos de texto.
    execute 'set local session_replication_role = replica';
    insert into public.unidades (codigo, proyecto, proyecto_id, tipo, moneda, precio, superficie_m2, estado, obra_fecha_entrega)
      values ('ZZ-MCP-1', 'ZZ-MCP Proyecto', pM, 'parcela', 'EUR', 80000, 500, 'disponible', date '2027-01-01') returning id into u1;
    insert into public.unidades (codigo, proyecto, proyecto_id, tipo, moneda, precio, superficie_m2, estado)
      values ('ZZ-MCP-2', 'ZZ-MCP Proyecto', pM, 'parcela', 'EUR', 90000, 600, 'reservada') returning id into u2;
    insert into public.unidades (codigo, proyecto, proyecto_id, tipo, moneda, precio, superficie_m2, estado)
      values ('ZZ-MCP-3', 'ZZ-MCP Proyecto agente', pX, 'parcela', 'EUR', 70000, 400, 'disponible') returning id into u3;
    -- C1: reserva de U2 sin firmar (precio 500), con la ficha del comprador en `datos` como cebo. C2: firmada hoy (5.000).
    insert into public.contratos (numero, tipo, proyecto_id, proyecto_nombre, unidad_id, moneda, precio_total, bloqueado,
                                  comprador_nombre, datos, creado_por, created_at)
      values ('ZZ-MCP-C1', 'reserva_parcela', pM, 'ZZ-MCP Proyecto', u2, 'EUR', 500, false, 'ZZ-SECRETO Comprador',
              '{"fields":{"adq1_email":"zz-secreto@prueba.invalid","adq1_passport":"ZZ-SECRETO-P"}}'::jsonb, sa.em, now() - interval '3 days')
      returning id into c1;
    insert into public.contratos (numero, tipo, proyecto_id, proyecto_nombre, moneda, precio_total, bloqueado, fecha_firma,
                                  comprador_nombre, datos, creado_por, created_at)
      values ('ZZ-MCP-C2', 'reserva_parcela', pM, 'ZZ-MCP Proyecto', 'EUR', 5000, true, v_hoy, 'ZZ-SECRETO Comprador 2',
              '{"fields":{}}'::jsonb, sa.em, now() - interval '1 day')
      returning id into c2;
    update public.unidades set contrato_id = c1 where id = u2;
    insert into public.contrato_firmas (contrato_id, token_hash, firmante_nombre, firmante_email, firmante_rol, estado, orden)
      values (c1, 'zz-mcp-token', 'ZZ-SECRETO Firmante', 'zz-secreto-firma@prueba.invalid', 'comprador', 'pendiente', 1);
    -- F1: 1.000 sobre C1 (precio 500 → 500 facturados de más), vence el 30-nov; R1: 400 de hoy, 150 aplicados a F1.
    insert into public.facturas (tipo, numero, sociedad, contrato_id, proyecto_id, total, moneda, fecha_emision, creado_por, cliente_nombre, datos)
      values ('factura', 'ZZ-MCP-F1', 'zz_mcp', c1, pM, 1000, 'EUR', v_hoy, sa.em, 'ZZ-SECRETO Cliente',
              '{"fields":{"fecha_vencimiento":"2026-11-30","cliente_email":"zz-secreto@prueba.invalid","notas":"ZZ-SECRETO nota"}}'::jsonb)
      returning id into f1;
    insert into public.facturas (tipo, numero, sociedad, contrato_id, proyecto_id, total, moneda, fecha_emision, creado_por, cliente_nombre, datos, justificante_path)
      values ('recibi', 'ZZ-MCP-R1', 'zz_mcp', c1, pM, 400, 'EUR', v_hoy, sa.em, 'ZZ-SECRETO Cliente', '{"fields":{}}'::jsonb, 'zz-mcp/justificante.pdf')
      returning id into r1;
    insert into public.recibi_aplicaciones (recibi_id, factura_id, importe_aplicado) values (r1, f1, 150);
    -- comisión pendiente de C1 (nivel closer, beneficiario SA); tramo y condición inventados: sin disparadores no hay FK
    insert into public.comisiones_devengadas (contrato_raiz_id, tramo_id, condicion_id, beneficiario_email, nivel, importe, moneda,
                                              estado, disparado_en, ajuste_motivo)
      values (c1, gen_random_uuid(), gen_random_uuid(), sa.em, 'closer', 100, 'EUR', 'pendiente', now(), 'ZZ-SECRETO motivo')
      returning id into cd1;
    -- los registros que escribirían los triggers: un cambio de estado de U2 (con `notas` en la foto) y dos eventos de C1
    insert into public.unidades_log (unidad_id, antes, despues, motivo, via, por, en)
      values (u2, '{"estado":"disponible","notas":"ZZ-SECRETO nota"}'::jsonb, '{"estado":"reservada"}'::jsonb,
              'ZZ-SECRETO motivo', 'ficha', sa.em, now() - interval '1 hour');
    insert into public.contrato_eventos (contrato_id, evento, detalle, quien, creado_en)
      values (c1, 'enviado_a_firma', '{"firmante_email":"zz-secreto@prueba.invalid"}'::jsonb, sa.em, now() - interval '2 hours'),
             (c1, 'reserva_liberada', '{"nota":"ZZ-SECRETO"}'::jsonb, 'cron:libera-reservas', now() - interval '30 minutes');
    -- gasto de hoy (77 EUR) y un movimiento de banco de hoy conciliado con R1 (400), con concepto bancario de cebo
    insert into public.cuentas_bancarias (clave, label, titular, banco, cuenta, empresa)
      values ('zz_mcp_c', 'ZZ-MCP cuenta', 'ZZ-MCP PT', 'ZZ Banco', '000', 'zz_mcp');
    insert into public.gastos (sociedad, proyecto_id, categoria, concepto, fecha, base, impuesto, pph_retenido, moneda, estado, justificantes, notas)
      values ('zz_mcp', pM, 'zz', 'ZZ-SECRETO concepto', v_hoy, 77, 0, 0, 'EUR', 'pendiente', '[]'::jsonb, 'ZZ-SECRETO nota')
      returning id into g1;
    insert into public.bancos_movimientos (cuenta_clave, fecha, concepto, importe, moneda, huella, estado)
      values ('zz_mcp_c', v_hoy, 'ZZ-SECRETO concepto bancario', 400, 'EUR', 'zz-mcp-1', 'conciliado') returning id into m1;
    insert into public.bancos_conciliacion (movimiento_id, tipo, ref_id, importe_mov, importe_doc, moneda_doc, nota)
      values (m1, 'recibi', r1, 400, 400, 'EUR', 'ZZ-SECRETO nota');
    execute 'set local session_replication_role = origin';
    r := r || pg_temp.l(true, 'P montaje: SA (super admin), AG (agente con casillas, su proyecto pX), AGN (agente sin casillas); pM con U1 libre, U2 reservada por C1 (sin firmar), C2 firmada hoy, F1/R1, comisión, log, eventos, gasto y movimiento conciliado; pX con U3 libre');
  exception when others then
    raise exception using message = replace(c_fin, '%', r || pg_temp.l(false, 'P montaje: ' || sqlstate || ' ' || left(sqlerrm, 300)));
  end;
  cebo := u1::text || '|' || u2::text || '|' || c1::text || '|' || c2::text || '|' || f1::text || '|' || r1::text || '|' || cd1::text;

  -- ============================================================ C. canarios
  v := pg_temp.mcp(sa.uid, sa.em, sa.app, 'select current_user::text || ''|'' || coalesce(current_setting(''request.jwt.claim.sub'', true), ''-'')');
  r := r || pg_temp.l(v = 'ia_puente_rol|' || sa.uid::text, 'C1 la llamada corre como ia_puente_rol con la sesión simulada de SA (' || left(v, 80) || ')');
  v := pg_temp.mcp(sa.uid, sa.em, sa.app, 'select count(*)::text from public.unidades');
  r := r || pg_temp.l(v ~ '^ERR42501', 'C2 ia_puente_rol no lee una tabla directamente: solo las mcp_* (' || left(v, 80) || ')');
  v := pg_temp.mcp(sa.uid, sa.em, sa.app, 'select privado.mcp_parcelas_libres()::text');
  r := r || pg_temp.l(coalesce(pg_temp.js(v) ? 'datos', false) and v ~ u1::text,
                      'C3 auth.uid() resuelve dentro de la mcp_* (puede() del super admin pasa y sale U1) (' || left(v, 80) || ')');

  v := pg_temp.mcp(sa.uid, sa.em, sa.app, 'select public.mcp_parcelas_libres_lee(null)::text');
  r := r || pg_temp.l(v ~ '^ERR42501', 'C4 ia_puente_rol no llama a un lector directamente (se saltaría la puerta y el registro) (' || left(v, 80) || ')');

  -- ============================================================ S. el super admin ve lo sembrado
  for h in select * from _h order by herr loop
    t0 := clock_timestamp();
    v := pg_temp.mcp(sa.uid, sa.em, sa.app, h.q);
    ms := round(extract(epoch from clock_timestamp() - t0) * 1000, 1);
    j := pg_temp.js(v);
    r := r || pg_temp.l(j is not null and not (j ? 'error') and j ? 'datos',
                        'S0 ' || h.herr || ': SA recibe {datos} sin error, ' || ms || ' ms con la siembra (' || left(v, 100) || ')');
    r := r || pg_temp.l(v ~ '^ERR' or pg_temp.limpio(v), 'K ' || h.herr || ' (SA): sin claves de comprador ni texto libre ni cebos');
    if j is null or j ? 'error' then continue; end if;
    case h.herr
      when 'parcelas_libres' then
        r := r || pg_temp.l(v ~ u1::text and v ~ u3::text and v !~ u2::text
                            and exists (select 1 from jsonb_array_elements(j->'datos') e where e->>'unidad_id' = u1::text
                                          and (e->>'precio')::numeric = 80000 and e->>'moneda' = 'EUR' and e->>'proyecto_id' = pM::text),
                            'S1 parcelas_libres: U1 y U3 libres (U1 a 80.000 EUR en pM), U2 reservada no sale');
      when 'comisiones_pendientes' then
        r := r || pg_temp.l(exists (select 1 from jsonb_array_elements(j->'datos') e where e->>'devengada_id' = cd1::text
                                      and e->>'beneficiario_usuario_id' = sa.uid::text and (e->>'importe')::numeric = 100
                                      and e->>'contrato_raiz_id' = c1::text),
                            'S2 comisiones_pendientes: la comisión de C1, beneficiario como usuario_id (no correo), 100 EUR');
      when 'cobros_por_proyecto_mes' then
        r := r || pg_temp.l(exists (select 1 from jsonb_array_elements(j->'datos') e where e->>'proyecto_id' = pM::text and e->>'moneda' = 'EUR'
                                      and (e->>'cobrado_mes')::numeric = 400 and (e->>'pendiente_hoy')::numeric = 850
                                      and (e->>'recibis_mes')::int = 1),
                            'S3 cobros_por_proyecto_mes: pM/EUR cobrado este mes 400 (R1), pendiente hoy 850 (F1 1.000 - 150)');
      when 'cambios_estado_semana' then
        r := r || pg_temp.l(exists (select 1 from jsonb_array_elements(j->'datos') e where e->>'unidad_id' = u2::text and e->>'tipo' = 'unidad'
                                      and e->>'estado_antes' = 'disponible' and e->>'estado_despues' = 'reservada'
                                      and e->>'usuario_id' = sa.uid::text and e->>'via' = 'ficha')
                            and exists (select 1 from jsonb_array_elements(j->'datos') e where e->>'contrato_id' = c1::text
                                          and e->>'evento' = 'enviado_a_firma' and e->>'usuario_id' = sa.uid::text)
                            and exists (select 1 from jsonb_array_elements(j->'datos') e where e->>'contrato_id' = c1::text
                                          and e->>'evento' = 'reserva_liberada' and e->>'via' = 'sistema' and not (e ? 'usuario_id')),
                            'S4 cambios_estado_semana: U2 disponible→reservada por SA (usuario_id), C1 enviado a firma por SA y liberado por el sistema');
      when 'contratos_sin_firmar' then
        r := r || pg_temp.l(exists (select 1 from jsonb_array_elements(j->'datos') e where e->>'contrato_id' = c1::text
                                      and (e->>'firmas_pendientes')::int = 1 and (e->>'dias_desde_alta')::int between 2 and 4
                                      and e->>'unidad_id' = u2::text)
                            and v !~ c2::text,
                            'S5 contratos_sin_firmar: C1 con 1 firma pendiente y ~3 días; C2 (firmada) no sale');
      when 'resumen_semana' then
        r := r || pg_temp.l(exists (select 1 from jsonb_array_elements(j->'datos'->'por_moneda') e where e->>'moneda' = 'EUR'
                                      and (e->>'ventas_firmadas')::int = 1 and (e->>'ventas_firmadas_importe')::numeric = 5000
                                      and (e->>'cobrado')::numeric = 400)
                            and (j->'datos'->>'reservas_caidas')::int = 1
                            and (j->'datos'->'obra'->>'entregas_con_fecha')::int = 1,
                            'S6 resumen_semana: EUR 1 venta firmada (5.000), cobrado 400, 1 reserva caída, 1 entrega con fecha');
      when 'facturas_no_cobradas' then
        r := r || pg_temp.l(exists (select 1 from jsonb_array_elements(j->'datos') e where e->>'factura_id' = f1::text
                                      and e->>'sociedad_id' = 'zz_mcp' and (e->>'pendiente')::numeric = 850
                                      and (e->>'cobrado')::numeric = 150 and e->>'vencimiento' = '2026-11-30'),
                            'S7 facturas_no_cobradas: F1 de zz_mcp, pendiente 850, cobrado 150, vence el 30-nov');
      when 'recibis_sin_aplicar' then
        r := r || pg_temp.l(exists (select 1 from jsonb_array_elements(j->'datos') e where e->>'recibi_id' = r1::text
                                      and (e->>'aplicado')::numeric = 150 and (e->>'sin_aplicar')::numeric = 250
                                      and e->>'contrato_id' = c1::text),
                            'S8 recibis_sin_aplicar: R1 400, aplicado 150, sin aplicar 250');
      when 'ventas_facturadas_de_mas' then
        r := r || pg_temp.l(exists (select 1 from jsonb_array_elements(j->'datos') e where e->>'contrato_raiz_id' = c1::text
                                      and (e->>'precio')::numeric = 500 and (e->>'facturado')::numeric = 1000
                                      and (e->>'facturado_de_mas')::numeric = 500)
                            and v !~ c2::text,
                            'S9 ventas_facturadas_de_mas: C1 precio 500, facturado 1.000, de más 500 (lo mismo que contrato_saldo); C2 no');
        -- equivalencia con la función de la pantalla, con la misma sesión y como authenticated (la que llama el navegador)
        perform set_config('request.jwt.claims', json_build_object('sub', sa.uid, 'email', sa.em, 'role', 'authenticated')::text, true);
        execute 'set local role authenticated';
        begin
          select public.contrato_saldo(c1) into j;
        exception when others then j := jsonb_build_object('err', sqlerrm);
        end;
        execute 'reset role';
        perform set_config('request.jwt.claims', '', true);
        r := r || pg_temp.l((j->>'facturado_de_mas')::numeric = 500 and (j->>'precio')::numeric = 500,
                            'S9b contrato_saldo(C1) como authenticated da el mismo facturado_de_mas (' || left(j::text, 90) || ')');
      when 'movimientos_mes_sociedad' then
        r := r || pg_temp.l(exists (select 1 from jsonb_array_elements(j->'datos'->'facturas') e where e->>'sociedad_id' = 'zz_mcp' and (e->>'importe')::numeric = 1000)
                            and exists (select 1 from jsonb_array_elements(j->'datos'->'recibis') e where e->>'sociedad_id' = 'zz_mcp' and (e->>'importe')::numeric = 400)
                            and exists (select 1 from jsonb_array_elements(j->'datos'->'gastos') e where e->>'sociedad_id' = 'zz_mcp' and (e->>'importe')::numeric = 77)
                            and exists (select 1 from jsonb_array_elements(j->'datos'->'conciliados') e where e->>'sociedad_id' = 'zz_mcp' and (e->>'importe')::numeric = 400)
                            and jsonb_array_length(j->'datos'->'sin_permiso') = 0,
                            'S10 movimientos_mes_sociedad: zz_mcp este mes facturas 1.000, recibís 400, gastos 77, conciliado 400');
    end case;
  end loop;

  -- ============================================================ A. el agente con casillas: 0 filas de pM, su parcela de pX
  for h in select * from _h order by herr loop
    v := pg_temp.mcp(ag.uid, ag.em, ag.app, h.q);
    j := pg_temp.js(v);
    if h.rol_admin then
      r := r || pg_temp.l(j->>'error' = 'sin_permiso', 'A ' || h.herr || ': AG (agente, pantalla de rol admin) → sin_permiso (' || left(v, 80) || ')');
    else
      r := r || pg_temp.l(j is not null and not (j ? 'error') and v !~ cebo,
                          'A ' || h.herr || ': AG recibe respuesta y NINGUNA fila de lo sembrado en pM (' || left(v, 100) || ')');
    end if;
    r := r || pg_temp.l(v ~ '^ERR' or pg_temp.limpio(v), 'K ' || h.herr || ' (AG): sin claves de comprador ni texto libre ni cebos');
  end loop;
  v := pg_temp.mcp(ag.uid, ag.em, ag.app, 'select privado.mcp_parcelas_libres()::text');
  r := r || pg_temp.l(v ~ u3::text and v !~ u1::text, 'A1b parcelas_libres: AG sí ve U3 (su proyecto pX) y no U1 (pM): la RLS filtra, no se vacía todo');
  v := pg_temp.mcp(ag.uid, ag.em, ag.app, 'select privado.mcp_movimientos_mes_sociedad()::text');
  j := pg_temp.js(v);
  r := r || pg_temp.l(j->'datos'->'sin_permiso' @> '["gastos", "conciliados"]'::jsonb and j->'datos'->'gastos' = 'null'::jsonb
                      and jsonb_array_length(j->'datos'->'facturas') = 0,
                      'A10b movimientos_mes_sociedad: AG (sin rol admin) no recibe gastos ni movimientos, y 0 facturas de pM');
  v := pg_temp.mcp(ag.uid, ag.em, ag.app, 'select privado.mcp_facturas_no_cobradas(''ZZ mcp; drop'')::text');
  r := r || pg_temp.l(pg_temp.js(v)->>'error' = 'argumento_invalido', 'A7b una sociedad con forma inválida → argumento_invalido (' || left(v, 60) || ')');

  -- ============================================================ N. el agente sin casillas: sin_permiso en las 10
  for h in select * from _h order by herr loop
    v := pg_temp.mcp(agn.uid, agn.em, agn.app, h.q);
    r := r || pg_temp.l(pg_temp.js(v)->>'error' = 'sin_permiso', 'N ' || h.herr || ': AGN (sin la casilla) → sin_permiso (' || left(v, 60) || ')');
  end loop;

  -- ============================================================ E. exposición
  select count(*) into n from pg_proc p
   where p.pronamespace = 'privado'::regnamespace and p.proname = any (array['mcp_parcelas_libres', 'mcp_comisiones_pendientes',
           'mcp_cobros_por_proyecto_mes', 'mcp_cambios_estado_semana', 'mcp_contratos_sin_firmar', 'mcp_resumen_semana',
           'mcp_facturas_no_cobradas', 'mcp_recibis_sin_aplicar', 'mcp_ventas_facturadas_de_mas', 'mcp_movimientos_mes_sociedad'])
     and p.prosecdef and p.provolatile = 'v' and array_to_string(p.proconfig, ',') ~ 'search_path=""'
     and pg_get_userbyid(p.proowner) = 'postgres'
     and has_function_privilege('ia_puente_rol', p.oid, 'execute')
     and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
     and not has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('lw_lector', p.oid, 'execute')
     and not exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0);
  r := r || pg_temp.l(n = 10, 'E1 las 10 puertas: DEFINER de postgres, volátiles (sin stable), search_path vacío, EXECUTE solo ia_puente_rol (' || n || ')');
  select count(*) into n from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = any (array['mcp_parcelas_libres_lee', 'mcp_comisiones_pendientes_lee',
           'mcp_cobros_por_proyecto_mes_lee', 'mcp_contratos_sin_firmar_lee', 'mcp_resumen_semana_lee', 'mcp_facturas_no_cobradas_lee',
           'mcp_recibis_sin_aplicar_lee', 'mcp_movimientos_mes_sociedad_lee'])
     and p.prosecdef and p.provolatile = 's' and array_to_string(p.proconfig, ',') ~ 'search_path=""'
     and pg_get_userbyid(p.proowner) = 'lw_lector'
     and not exists (select 1 from aclexplode(p.proacl) a where a.grantee <> p.proowner);
  r := r || pg_temp.l(n = 8, 'E2 los 8 lectores: DEFINER de lw_lector, STABLE, search_path vacío, sin EXECUTE para nadie más que su dueño (' || n || ')');
  select count(*) into n from pg_proc p
   where p.pronamespace in ('privado'::regnamespace, 'public'::regnamespace) and p.proname ~ '^mcp_' and p.proname not in ('mcp_puerta', 'mcp_cierra')
     and (p.prosrc ~* '\mexecute\M' or p.prosrc ~* '\mformat\s*\(' or p.prosrc ~* '\mauth\.');
  r := r || pg_temp.l(n = 0, 'E3 ninguna mcp_* usa EXECUTE dinámico, format() ni auth.* (' || n || ')');
  r := r || pg_temp.l(not has_schema_privilege('authenticated', 'privado', 'usage') and not has_schema_privilege('anon', 'privado', 'usage'),
                      'E4 anon y authenticated siguen sin USAGE en privado (no se llaman por /rpc)');
  -- E5 = las patas (d) y (e) del invariante «lw_lector es un lector» de tools/salud_lawang.py (líneas ~890-933), tal cual:
  -- si esto da filas, el chequeo de salud de después de aplicar también las daría.
  select string_agg(x, ', ') into v from (
    select 'ejecuta la volátil ' || p.proname as x from pg_proc p
     where p.pronamespace = 'public'::regnamespace and p.provolatile = 'v' and p.prokind in ('f', 'p')
       and has_function_privilege('lw_lector', p.oid, 'execute')
    union all
    select 'su cuerpo puede escribir ' || p.proname from pg_proc p
     where p.pronamespace = 'public'::regnamespace and has_function_privilege('lw_lector', p.oid, 'execute')
       and p.prosrc ~* '(^|[^a-z_])((insert|update|delete|perform|execute|truncate|merge|call|setval|nextval|copy|dblink[a-z_]*|create|drop|alter|grant|revoke|comment|lo_[a-z_]+|refresh|http_[a-z_]+)([^a-z_]|$)|net[.])'
    union all
    select 'create en el esquema ' || nn.nspname from pg_namespace nn
     where left(nn.nspname, 3) <> 'pg_' and nn.nspname <> 'information_schema' and has_schema_privilege('lw_lector', nn.oid, 'create')
    union all
    select 'execute en ' || nn.nspname || '.' || p.proname from pg_proc p join pg_namespace nn on nn.oid = p.pronamespace, aclexplode(p.proacl) a
     where nn.nspname <> 'public' and a.grantee = (select oid from pg_roles where rolname = 'lw_lector')
    union all
    select a.privilege_type || ' en el esquema ' || nn.nspname from pg_namespace nn, aclexplode(nn.nspacl) a
     where nn.nspname <> 'public' and a.grantee = (select oid from pg_roles where rolname = 'lw_lector')
    union all
    select 'usage de ' || rr || ' en privado' from unnest(array['anon', 'authenticated', 'service_role', 'lw_lector']) rr
     where has_schema_privilege(rr, 'privado', 'usage')) q;
  r := r || pg_temp.l(v is null, 'E5 salud «lw_lector es un lector» (d)+(e) sin filas tras la migración (' || coalesce(left(v, 200), 'ninguna') || ')');

  -- ============================================================ R. solo lectura (AL FINAL: no hay vuelta a escritura)
  -- Puerta y cierre que NO escriben, solo para R (SE QUEDA aunque exista P1: la puerta real escribe el registro y aquí
  -- daría 25006 a propósito; lo que R mide es que los CUERPOS no escriben fuera de la puerta). Exige que la de P1 tenga
  -- esta misma firma y dueño postgres; create or replace conserva dueño y permisos, y el raise final lo deshace.
  create or replace function privado.mcp_puerta(p_herramienta text, p_args jsonb)
  returns jsonb language sql security definer set search_path = '' as $r$ select jsonb_build_object('ok', true, 'llamada', 1) $r$;
  create or replace function privado.mcp_cierra(p_llamada bigint, p_filas int, p_resultado text)
  returns void language plpgsql security definer set search_path = '' as $r$ begin null; end $r$;
  perform set_config('transaction_read_only', 'on', true);
  for h in select * from _h order by herr loop
    v := pg_temp.mcp(sa.uid, sa.em, sa.app, h.q);
    r := r || pg_temp.l(pg_temp.js(v) is not null and not (pg_temp.js(v) ? 'error'),
                        'R ' || h.herr || ': corre en una transacción de solo lectura sin escribir fuera de la puerta (' || left(v, 60) || ')');
  end loop;

  raise exception using message = replace(c_fin, '%', r);
end $todo$;
