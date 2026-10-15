-- destructivo-ok: ensayo deshecho de 20261014223000 en la viva; todo termina en raise (rollback), nada queda escrito
-- ENSAYO DE 2159 EN UNA LLAMADA (15-oct-2026, lawang-cola-2, generado por contracts/sql/genera_ensayo_2159.py; NO se edita a mano).
-- Qué hace, en UNA transacción que acaba en `raise exception 'RES 2159 …'` (se deshace todo):
--   0. f2_foto_b2 antes · 1. la migración 20261014223000 tal cual (sha256 08c84d8112cfe3f5) · 2. tres pruebas en sub-bloques que
--   capturan su resultado · 4. f2_foto_b2 después (mismo MD5 = la migración no cambia lo que ve nadie) · 5. flujos_lawang.
-- ESPERADO para aplicar (cualquier otra cosa = PARAR y pasar el RES entero a lawang-cola-2):
--   factura_moneda_del_contrato: ninguna línea con FALLA (b1 incluido) · facturas_tope_cadena_y_recibi_pendiente: resultados sin error
--   f2_b2_empresas: FALLOS=0 · f2_foto_b2: «MD5 igual antes y despues → ok» · flujos_lawang N/N → ok
--   Un 55P03 (lock_timeout) en cualquier sección = tabla ocupada: REINTENTAR más tarde, no es un fallo.
-- f2_foto_b2_ab NO va (decisión por defecto, revertible añadiéndola como sección): compara funciones de gastos contra una instantánea,
-- no guardar_recibi; el A/B de 2159 es la foto antes/después de la sección 0/4, en la misma transacción.
-- Huellas: migración 08c84d8112cfe3f545f86f99c819ab5d0e756062a20ccfd10f17b82013be3c75 · flujos 13152abb8a05f84d3397d15e6f80b9bace6d05c2742b6b09665042b34bb22c03 · factura_moneda_del_contrato b7704baee9072e77 · facturas_tope_cadena_y_recibi_pendiente ac3b0473052d539b · f2_b2_empresas a98d61e5bf2faf8f · f2_foto_b2 07b5a8f511b0844c
select set_config('lock_timeout', '5s', true);
create or replace function pg_temp.e2159_resume(t text) returns text language sql as $r$
  -- cuenta las líneas y deja solo las que no dicen ok (el RES entero de 140 KB lo corta el cliente)
  select (select count(*) from regexp_split_to_table(coalesce(t, ''), E'\n') l where l ~ '(→ ok|: ok|\mok\M)')::text || ' ok · '
      || coalesce((select string_agg(l, E'\n') from regexp_split_to_table(coalesce(t, ''), E'\n') l
                    where l !~ '(→ ok|: ok|\mok\M)' and btrim(l) <> ''), '')
$r$;
do $ens2159$
declare res text := ''; v text; antes text; despues text; n_ok int; n_tot int;
begin
  -- 0 · foto de lo que ve cada usuario ANTES de la migración (misma transacción: no hay datos que cambien entre las dos)
  begin execute $p2159_3$-- Foto del bloque 2 (DINERO) de la Fase 2 (8-oct-2026): para CADA usuario (los 34 de hoy), con su JWT (email) y `set local role authenticated`,
--   (a) md5 de lo que ve de cada tabla del bloque (gastos, proveedores, bancos_*, categorias, aplicaciones, retenciones, logs, cuentas...),
--   (b) md5 del resultado de cada RPC de lectura del bloque, o el sqlstate si falla,
--   (c) sqlstate de cada RPC de ESCRITURA llamada con ids que no existen (nada se toca; ademas todo acaba en rollback).
-- Por defecto solo imprime el md5; con `set local f2b2.v = '1';` delante imprime tambien la linea de cada usuario (para ver QUIEN cambio).
-- No incluye lo del 2A/2B (eso es f2_foto_ids.sql). El md5 final debe ser IDENTICO antes y despues de cada migracion del bloque.
-- Produccion esta viva: si cambia una fila entre foto y foto, aparece en la linea de ese usuario; se regenera la previa justo antes de aplicar.
-- destructivo-ok: solo lectura y llamadas a ids inexistentes; termina en raise (rollback)
do $t$
declare
  u record; out text := ''; linea text; h text; t text; sql text; i int;
  fantasma constant uuid := '00000000-0000-4000-8000-00000000f2b2';
  tablas constant text[] := array['gastos','gastos_log','proveedores','gasto_categorias','bancos_movimientos','bancos_conciliacion','bancos_perfiles',
                                  'recibi_aplicaciones','solicitudes_pago_retencion','sociedades_log','ajustes_log','solicitudes_cambio','cuentas_bancarias',
                                  'solicitudes_pago','facturas','sociedades'];
  lecturas constant text[] := array[
    'public.gastos_panel_datos()', 'public.panel_bancos_datos()', 'public.bancos_resumen()', 'public.sociedades_ajustes_datos()',
    'public.cuentas_uso()', 'public.cuentas_cobro_visibles()', 'public.sociedades_visibles()',
    format('public.gasto_historial_datos(%L::uuid)', fantasma)];
  escrituras constant text[] := array[
    format('public.factura_borra(%L::uuid)', fantasma),
    format('public.factura_anula(%L::uuid)', fantasma),
    format('public.factura_reactiva(%L::uuid)', fantasma),
    format('public.factura_marca_enviada(%L::uuid)', fantasma),
    format('public.factura_guarda(%L::uuid, %L::jsonb)', fantasma, '{"tipo":"factura","moneda":"EUR","total":"1","sociedad":"tepi_sungai","datos":{"lineas":[{"d":"x","q":1,"p":1}]}}'),
    format('public.guardar_recibi(null::uuid, %L::jsonb, %L::jsonb)', '{"contrato_id":"00000000-0000-4000-8000-00000000f2b2","sociedad":"tepi_sungai"}', '[]'),
    format('public.gasto_guarda(%L::uuid, %L::jsonb)', fantasma, '{"base":"1","sociedad":"tepi_sungai"}'),
    format('public.gasto_anula(%L::uuid, %L)', fantasma, 'x'),
    format('public.gasto_marca_pagado(%L::uuid, current_date, %L)', fantasma, 'x'),
    format('public.gasto_pph_ingresado(%L::uuid, current_date)', fantasma),
    format('public.gasto_anade_justificante(%L::uuid, %L, %L)', fantasma, fantasma || '/x.pdf', 'n'),
    format('public.proveedor_guarda(%L::uuid, %L::jsonb)', fantasma, '{"nombre":"x"}'),
    format('public.solicitud_pago_guarda(%L::uuid, %L::jsonb)', fantasma, '{"importe":1,"concepto":"x"}'),
    format('public.solicitud_pago_resuelve(%L::uuid, %L)', fantasma, 'aprobada'),
    format('public.solicitud_pago_retencion_guarda(%L::uuid, %L::jsonb)', fantasma, '{}'),
    format('public.solicitud_pago_retencion_rectifica(%L::uuid, %L, %L)', fantasma, 'batal', 'x'),
    format('public.bancos_conciliar(%L::uuid, %L::jsonb)', fantasma, '[]'),
    'public.bancos_desconciliar(-1)',
    format('public.bancos_designorar(%L::uuid)', fantasma),
    format('public.bancos_ignorar(%L::uuid, %L)', fantasma, 'x'),
    format('public.bancos_importar(%L, %L, %L::jsonb)', 'cuenta_fantasma', 'f.csv', '[{"fecha":"2026-01-01","importe":1,"moneda":"EUR","huella":"x"}]'),
    format('public.banco_perfil_guarda(%L, %L::jsonb)', 'cuenta_fantasma', '{}'),
    format('public.cuenta_bancaria_guarda(%L, %L::jsonb, false)', 'zzz_fantasma', '{}'),
    format('public.sociedad_guarda(%L, %L::jsonb, false)', 'zzz_fantasma', '{}')];
begin
  for u in select user_id, email from public.usuarios order by email loop
    linea := u.email;
    perform set_config('request.jwt.claims', json_build_object('sub',u.user_id,'role','authenticated','email',u.email)::text, true);
    set local role authenticated;
    foreach t in array tablas loop
      begin
        execute format('select md5(coalesce(string_agg(x::text, '','' order by x::text),'''')) from public.%I x', t) into h;
        linea := linea || '|' || left(h, 5);
      exception when others then linea := linea || '|E' || sqlstate; end;
    end loop;
    foreach sql in array lecturas loop
      begin
        execute format('select md5(coalesce((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from (select * from (select %s) q) x)::text, ''-''))', sql) into h;
        linea := linea || '|' || left(h, 5);
      exception when others then
        begin
          execute format('select md5(%s::text)', sql) into h;
          linea := linea || '|' || left(h, 5);
        exception when others then linea := linea || '|E' || sqlstate; end;
      end;
    end loop;
    foreach sql in array escrituras loop
      begin
        execute format('select %s', sql);
        linea := linea || '|ok';
      exception when others then linea := linea || '|E' || sqlstate; end;
    end loop;
    reset role;
    out := out || linea || E'\n';
  end loop;
  raise exception E'FOTOB2\nMD5=%\n%', md5(out), case when current_setting('f2b2.v', true) = '1' then out else '(lineas por usuario: ejecutar con set local f2b2.v = ''1'' delante)' end;
end $t$;
$p2159_3$; exception when others then antes := sqlstate || ' ' || sqlerrm; end;
  -- 1 · la migración, FUERA de sub-bloque: si su $antes$ o una guarda lanza, para todo (sha256 08c84d8112cfe3f5)
  execute $mig2159$-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68). El maestro tiene su propio guardar_recibi (sin la columna
--   historico_sin_justificante, que es solo de Lawang, LAW-40); llevar A1-A4 y C3 al maestro va en su fila de pendientes (AXW-333).
-- GUARDAR_RECIBI: EL TOTAL ES LA SUMA DE LO QUE SE APLICA, EL PAPEL LO ESCRIBE EL SERVIDOR, SE VALIDA TODO ANTES DE NUMERAR, SIN
--   IMPUESTO, «OTROS» SOLO ADMIN Y EL HISTORICO SIN JUSTIFICANTE SE PUEDE APLICAR POR SU MISMO TOTAL (14-oct-2026, Backend; 2.a vuelta
--   del revisor el 15-oct). Bloque A + C3-recibis del plan «arreglos seguros y reversibles de Contratos y Facturas» (revision previa
--   de Backend #337 y de Seguridad #338, plan cerrado) + fallo 1 de los que encontro el orquestador al aplicar REC00015 (decision
--   del owner del 14-oct, opcion A: dinero real).
-- QUE HACE (y por que):
--   Orden de permisos primero (Seguridad #338): herramienta -> contrato que ves -> alcance restringido (como hoy) -> si se EDITA, se
--     bloquea la fila vieja con su filtro de autoria (y «ya se envio») ANTES de cualquier otra validacion o mensaje.
--   Fallo 1 · JUSTIFICANTE: un recibi marcado historico_sin_justificante (LAW-40, recibis de antes del 11-ago sin justificante; la
--     marca solo la pone una migracion, trg_facturas_historico_solo_migracion) se puede volver a guardar sin justificante SOLO si
--     total, contrato y moneda son los de la fila guardada (caso REC00015: 39.220 = 39.220). Sin ese limite un historico se podia
--     inflar sin justificante (revisor, 15-oct). La exencion sale SOLO de la fila guardada y bloqueada (v_viejo), nunca del payload
--     ni de una fecha. Un recibi nuevo sigue exigiendo justificante. Medido el 14-oct: 12 recibis vivos con la marca y sin
--     justificante. Por eso la comprobacion de «sin justificante» va DESPUES de calcular el total (A4).
--     CAMBIOS DE SEGURIDAD (consulta de deploy, 15-oct-2026), dos huecos de la exencion:
--     (1) La exencion exige ademas que la fila guardada SIGA sin justificante (justificantes = '[]' y justificante_path vacio).
--         Hueco: con un justificante adjunto la comprobacion de «sin justificante» no corre, asi que se podian cambiar total,
--         contrato y moneda (caso H6); una 2.a llamada SIN justificante con esos valores nuevos coincidia con la fila guardada y
--         pasaba -> un recibi inflado o movido de contrato que se queda sin justificante y con la marca LAW-40. LAW-40 solo marco
--         filas con justificante_path is null (20261010163654:131-132) y justificantes es jsonb not null default '[]'
--         (20260824101413:9); el espejo trg_espejo_justificante (20260824101413:20-22) no borra justificante_path cuando
--         justificantes vuelve a '[]', por eso se miran los dos. Caso H7.
--     (2) Un historico SIN justificante solo salda facturas de SU contrato (v_otro_contrato). Hueco: por la rama
--         contratos_mismo_comprador podia saldar facturas de otro contrato del mismo comprador, y _contrato_cobrado_interno
--         cuenta por f.contrato_id: creaba cobrado sin evidencia en el otro contrato (puede marcar la parcela vendida y mover
--         comisiones). La misma marca cierra, con la exencion activa, los caminos de super_admin a factura huerfana y a otro
--         comprador (v_factura_contrato null o distinto tambien es «otro contrato»). Con justificante esos caminos siguen igual.
--         Caso H8 (y H8b, su SI; H8c con justificante). El rechazo va antes del update, y la exencion solo existe al EDITAR
--         (v_exento solo se pone con p_id), que no numera: trg_set_factura_numero es BEFORE INSERT
--         (20260922170000_rescate_objetos_sin_migracion.sql:409) y set_factura_numero solo numera si numero is null
--         (20260917082716_facturas_emisor_congelado_y_permisos.sql:57). H8 parte de un RH3 ya aplicado (H8b) y comprueba que
--         el rechazo deja sus aplicaciones como estaban.
--   A1 · NUMERACION: TODAS las aplicaciones se validan antes del insert, para que un rechazo no gaste numero (nextval de
--     facturas_recibi_seq en trg_set_factura_numero, 20260917082716_facturas_emisor_congelado_y_permisos.sql:60). Reduce los
--     huecos, no los evita (nextval se gasta igual si falla algo despues). registra_privilegio va despues de escribir (necesita el
--     numero). Al editar, el pendiente de cada factura excluye las aplicaciones del propio recibi. Una factura repetida (comparada
--     como uuid: el mismo id en mayusculas es la misma factura) se rechaza.
--     MONEDA (15-oct): la factura tiene que ir en la moneda del recibi. Antes lo frenaba despues del insert el disparador
--     valida_recibi_aplicacion (20260925030855_recibi_aplicaciones_ignora_anulados.sql:40) con el numero ya gastado.
--     TOLERANCIA (15-oct): pendiente + 0,01, la MISMA del disparador (misma migracion, :27). Antes era una unidad minima de la
--     moneda (1 en IDR): entre 0,01 y 1 IDR la funcion dejaba pasar y el disparador frenaba con el numero gastado.
--   VISIBILIDAD: el mensaje «no es un documento que veas» ya no da el NUMERO de la factura (lo daba a quien no la ve: oraculo). La
--     moneda se compara DESPUES de la visibilidad, para no decir en que moneda va una factura que no ves.
--   A2 · IMPORTES: el total y cada aplicacion se leen con ::numeric si llegan como numero JSON (lo que manda la pantalla) y con
--     lw_parse_importe si llegan como texto (con «120.000», ::numeric daba 120). Se redondean a los decimales de la moneda.
--   A4 · TOTAL: el servidor CALCULA el total como la suma de las aplicaciones y rechaza el recibi si el de la pantalla no casa. Sin
--     salto para nadie. Antes un recibi podia decir 100.000 aplicando 1, y _contrato_cobrado_interno contaba los 99.999 de mas como
--     cobrado (movia la parcela a «vendida» y las comisiones). _contrato_cobrado_interno NO se toca (F2 y comisiones).
--   PAPEL (15-oct, revisor): el papel, el PDF y el portal pintan el recibi con datos.lineas / datos.fields.lineas, datos.totales y
--     el impuesto de datos.fields (documento.js:131 y :149; el portal prefiere fields.lineas, portal/index.html:5174). Todo eso
--     llegaba del navegador: se podia guardar un recibi de 50 cuyo papel dijera 999.999. Ahora lo ESCRIBE el servidor desde lo
--     aplicado: datos.lineas = datos.fields.lineas = una linea por factura con el texto de conceptoCobroRecibi (documento.js:40) y
--     el importe aplicado como TEXTO con los decimales de la moneda («100.50», «39220»: la pantalla clasica hace .trim() del
--     importe, intranet/facturas/index.html:2325); datos.totales = {subtotal, pct 0, impuesto 0, total} (la forma de
--     calcTotales, totales.js:98); fields.tipo = 'recibi' (sin eso el papel se titula «Factura») y fields.moneda = la del recibi.
--     Lo que la pantalla mande en esas claves se ignora.
--   A3 · IMPUESTO: un recibi no lleva impuesto: se quitan imp_pct, imp_etiqueta e impuestos_sel (el del catalogo, que
--     impuestoDelDocumento de totales.js:194 prefiere) de datos.fields, y rectifica_* (un recibi no rectifica). Medido el 14-oct:
--     0 recibis con impuesto. La pantalla quita su campo (editores.js). banco_de_servidor ya lo quita el disparador
--     facturas_sin_banco_de_servidor (20261002123000) y aqui tambien.
--   C3 · CUENTA «OTROS» (titular y numero escritos a mano, que salen en el papel sin comprobar): solo la usa un admin de la empresa
--     del contrato. Un no admin no puede elegir «otros»; en un recibi que YA la lleva (7 de los 13 documentos con «otros» son
--     recibis) solo puede guardar si la cuenta y todos sus banco_* quedan exactamente igual. Con otra cuenta, sus banco_* se descartan
--     (el papel solo los imprime con «otros», documento.js:64).
--   registra_privilegio guarda el importe ya leido (v_importe_aplic), no el texto que mando la pantalla.
--   CONTRATO DEL PAPEL (15-oct-2026, code-review hallazgo 2; patron ENLACE + ESPEJO de contexto/patrones_tecnicos.md): contrato_numero
--     se copiaba de lo que mandaba el navegador, asi que el papel podia decir un contrato mientras el dinero iba a otro. Ahora la
--     columna contrato_numero y datos.fields.contrato_numero (lo que imprime el papel, documento.js:179) salen de contratos.numero
--     del contrato ya comprobado; lo mandado se ignora.
--   PROYECTO DEL RECIBI (15-oct-2026, code-review 3.a vuelta, hallazgo 1 y BAJA 5): el proyecto sale SOLO del contrato comprobado.
--     Se lee despues de la puerta de visibilidad (DEFINER: antes seria un oraculo), junto al numero, en una sola consulta.
--     - proyecto_id = contratos.proyecto_id, escrito en el INSERT y en el UPDATE SIEMPRE, tambien cuando es null. Antes el UPDATE
--       no lo tocaba: al editar un recibi y pasarlo a un contrato de otro proyecto (la pantalla lo hace, editores.js cambioContrato)
--       se quedaba el proyecto_id viejo, porque trg_espejo_proyecto parte de new.proyecto_id y factura_hereda_cliente solo lo
--       rellena si esta vacio. Con el, _empresa_doc daba la empresa vieja (decide que admin edita) y comision_admin_lineas copiaba
--       el proyecto viejo. Y al crear, el id salia de buscar el NOMBRE (_contrato_proyecto_de, limit 1, proyectos.nombre sin
--       indice unico). Con el id puesto, el espejo ya no busca por nombre.
--     - proyecto_nombre (columna y datos.fields.proyecto_nombre, documento.js:201) = «<nombre del proyecto del contrato> — <unidad
--       del contrato>», con la unidad de datos.fields del contrato: parcela_codigo, si no villa_nombre, si no tipologia_villa. Es
--       la MISMA formula que el espejo de 20261014220000_facturas_conservan_parcela (trg_espejo_proyecto en facturas) y lo mismo
--       que ya mandaba la pantalla (editores.js:2625, aplicaContratoDoc). La version anterior de este arreglo guardaba el nombre
--       a secas tambien en el papel: el recibi perdia la parcela impresa. Decision por defecto (Backend, 15-oct, reversible:
--       volver al nombre a secas es quitar la unidad de la formula).
--       La columna la reescribe despues trg_espejo_proyecto: CON 20261014220000 aplicada (va antes, 220000 < 223000) da el mismo
--       texto, columna = papel; SIN ella (el espejo vivo del 13-oct) la columna queda con el nombre a secas y el papel con la
--       parcela, que es el fallo 4 que arregla 220000, no este. El proyecto_id es el del contrato en los dos casos. Para que
--       no pase, la guarda (d) del bloque $antes$ exige 220000 aplicada.
--     - Contrato SIN proyecto: proyecto_id null y proyecto_nombre null (columna y papel sin «Proyecto»). Lo que mande la pantalla
--       se ignora: con proyecto_id null, trg_espejo_proyecto busca el proyecto por ese nombre y se lo pondria al recibi (y con el
--       una empresa). Es lo que ya hacia el alcance restringido. Alternativa descartada: copiar contratos.proyecto_nombre (si un
--       proyecto se creara despues con ese nombre, el espejo lo enlazaria al recibi y no al contrato). factura_hereda_cliente
--       tampoco lo rellena: copia contratos.proyecto_id, que es null.
--     - El proyecto_nombre que mande la pantalla (en el payload y en datos.fields) se ignora SIEMPRE, con o sin alcance
--       restringido. El alcance restringido ya tomaba id y nombre del contrato; lo unico que cambia para el es que el nombre
--       ahora lleva la unidad.
--     Prueba: K1b/K3 (recibi nuevo con proyecto ajeno), K4 (editar hacia un contrato de otro proyecto: proyecto_id, columna y
--     papel; y hacia un contrato de OTRA empresa: _empresa_doc da la empresa 2 y el admin de la empresa 1, que no es autor,
--     ya no lo edita, K4d-K4f) y K5 (contrato sin proyecto).
--   CLIENTE DEL RECIBI (15-oct-2026, Seguridad, 4.a vuelta de la consulta de deploy): al EDITAR, si cambia el contrato, client_id
--     se pone a null en el UPDATE y trg_factura_hereda_cliente (20260822021026: before update of contrato_id, client_id,
--     proyecto_id; rellena solo si llega null, del adquiriente_1 de contrato_compradores y si no de datos.adq1_client_id) lo
--     saca del contrato NUEVO. Antes se quedaba el client_id del comprador A al mover el recibi al contrato de B: la vista
--     documentos_desactualizados ofrecia meter nombre/pasaporte/email de A en el recibi de B, y el traspaso de cliente
--     (20261013150447:116, x.client_id = p_client_id) cambiaba el autor del recibi de B al traspasar A. Mismo contrato: se
--     conserva. Prueba: K6 (el recibi con el cliente A pasa a un contrato cuyo adquiriente_1 es B: client_id = B).
--     NO se tocan cliente_nombre ni sociedad (client_id si, ver «CLIENTE DEL RECIBI»): su fuente en el contrato no es inequivoca y factura_guarda tampoco los saca del
--     contrato (20261013074408, insert y update: los toma del payload; sociedad solo se ata para el alcance restringido, como aqui).
--     cliente_nombre: un contrato puede tener varios compradores (comprador_nombre compuesto con «·») y la pantalla deja escribir
--     la razon social; sociedad: la elige un admin, y al editar el alcance restringido conserva la de la fila.
-- LO QUE NO HACE: no toca datos (REC00015 lo aplica el orquestador por la pantalla, con el OK del owner). Si el owner aplica
--   REC00015 a INV00212 (39.220 = 39.220) entra la aplicacion entera o nada: todo va en la misma transaccion. Los recibis ya
--   guardados conservan sus datos.lineas/totales hasta que alguien los vuelva a guardar.
-- Se REESCRIBE ENTERA desde su definicion viva (7,4 KB), md5 de pg_get_functiondef sin retorno de carro medido el 14-oct-2026 en la
--   sesion 1014-2159 (solo lectura): guardar_recibi(uuid,jsonb,jsonb) 43a4c655711c0ef218b670ebe01c1585. Si ya no tiene ese md5 ni
--   lleva este arreglo, el bloque $antes$ lanza y no se aplica NADA. Idempotente. create or replace conserva dueno y permisos
--   (authenticated si, anon no, service_role si, medido el 14-oct); el bloque $cierre$ lo comprueba.
-- GUARDAS DE DATOS (code-review del 15-oct: estaban solo en comentario; ahora el bloque $antes$ LANZA y no se aplica nada).
--   Solo leen, por id/numero y por las aplicaciones de los historicos marcados, nunca contratos entero. En una rama sin filas
--   salen vacias y no paran.
--   (a) REC00015 e INV00212 en el MISMO contrato (sin medir aun; se esperaba RP00025). Con el cambio (2) un historico sin
--       justificante solo salda facturas de su contrato: si no coinciden, la operacion LAW-614 que eligio el owner
--       (REC00015 -> INV00212, 39.220) se rechazaria. Si lanza: la alternativa es dejar pasar el otro contrato del mismo
--       comprador con rastro (registra_privilegio 'cobro_historico_otro_contrato'), y lo decide el owner.
--   (a2) Ningun historico marcado y aun sin justificante tiene YA aplicaciones a facturas de otro contrato: si las tuviera,
--       el cambio (2) lo dejaria sin poder re-guardarse (ni para cambiar la fecha) sin adjuntar justificante. Si lanza, da
--       cuantos; se decide antes de aplicar.
--   (b) La escritura directa sobre facturas sigue cerrada para anon y authenticated (la exencion se fia de la fila guardada;
--       si se pudiera vaciar justificantes o cambiar contrato_id por PostgREST, se saltaria guardar_recibi entero). Revocada en
--       20260926092317_facturas_cierra_escritura_directa.sql:7; has_any_column_privilege porque un grant por columnas daria
--       un falso verde con has_table_privilege. Se mira en $antes$ y otra vez en $cierre$.
--   (c) Ningun recibi vivo lleva impuesto en el papel (A3; consulta de Administracion del 15-oct: la medida del 14-oct era
--       solo un comentario). Si lanza, da cuantos; que hacer con ellos (anular y emitir otro, nota, asesor) se decide antes.
--   (d) 20261014220000_facturas_conservan_parcela ya esta aplicada (su marca en trg_espejo_proyecto). Va antes por orden, pero
--       si esta se aplicara sola, el espejo del 13-oct dejaria la columna con el nombre a secas y el papel con la parcela
--       (columna <> papel). No es de seguridad, pero rompe lo que esta cabecera promete; mejor parar que divergir. Decision por
--       defecto (Backend, 15-oct, reversible: quitar el bloque (d) del $antes$).
-- ACEPTADO (orquestador agencia-c0 y sesión lawang-cola-2, 15-oct-2026, por la congelación del owner): las pruebas que montan sobre datos reales no corren en rama. Antes de aplicar esta migración en la viva se corren con ROLLBACK: factura_moneda_del_contrato b1, facturas_tope_cadena_y_recibi_pendiente, f2_b2_empresas A42-A45, f2_foto_b2 / f2_foto_b2_ab y tools/flujos_lawang.py.
--   4.a vuelta de Seguridad (15-oct-2026): al cambiar de contrato client_id se vuelve a heredar del contrato nuevo (prueba K6) y
--   K4 pasa ademas el recibi a un contrato de OTRA empresa (K4d-K4f: el admin de la empresa 1 ya no lo edita, 42501).
-- REVERTIR: supabase/reversion_recibi_total_suma_y_exento/REVERSION.sql (el texto vivo de antes, tal cual).
-- Prueba: supabase/pruebas/recibi_total_suma_y_exento.sql (crea contratos y documentos: SOLO en rama):
--   python erp/rama_prueba.py lawang --lawang <copia> --aplica 20261014220000_facturas_conservan_parcela.sql,20261014223000_recibi_total_suma_y_exento.sql
--          --prueba recibi_total_suma_y_exento.sql
--   (desde la 3.a vuelta, 15-oct, 220000 va en --aplica: la guarda (d) y K4b la necesitan, y la rama solo aplica lo que se le
--   lista sobre el ultimo volcado; la copia tiene que traer ese fichero de main)

set local lock_timeout = '5s';

do $antes$
declare n int;
begin
  if md5(replace(pg_get_functiondef('public.guardar_recibi(uuid,jsonb,jsonb)'::regprocedure), chr(13), '')) <> '43a4c655711c0ef218b670ebe01c1585'
     and position('v_exento' in pg_get_functiondef('public.guardar_recibi(uuid,jsonb,jsonb)'::regprocedure)) = 0 then
    raise exception 'recibi_total_suma_y_exento: guardar_recibi no es la definicion viva leida el 14-oct (md5 distinto) ni lleva ya el arreglo; no se aplica nada';
  end if;
  -- (a) LAW-614: REC00015 e INV00212 en el mismo contrato (si existen los dos)
  if exists (select 1 from public.facturas r, public.facturas i
              where r.numero = 'REC00015' and r.tipo = 'recibi' and i.numero = 'INV00212' and i.tipo = 'factura'
                and r.contrato_id is distinct from i.contrato_id) then
    raise exception 'recibi_total_suma_y_exento: REC00015 e INV00212 no son del mismo contrato; con este cambio LAW-614 se rechazaria. No se aplica nada: lo decide el owner';
  end if;
  -- (a2) historicos sin justificante ya aplicados fuera de su contrato
  select count(distinct rc.id) into n
    from public.facturas rc
    join public.recibi_aplicaciones ra on ra.recibi_id = rc.id
    join public.facturas f on f.id = ra.factura_id
   where rc.tipo = 'recibi' and rc.historico_sin_justificante and not coalesce(rc.anulada, false)
     and rc.justificantes = '[]'::jsonb and nullif(rc.justificante_path, '') is null
     and f.contrato_id is distinct from rc.contrato_id;
  if n > 0 then
    raise exception 'recibi_total_suma_y_exento: % recibi(s) historico(s) sin justificante ya aplicados a facturas de otro contrato; con este cambio no se podrian re-guardar. No se aplica nada', n;
  end if;
  -- (b) escritura directa sobre facturas cerrada
  if exists (select 1 from unnest(array['anon', 'authenticated']) r
              where has_any_column_privilege(r, 'public.facturas', 'INSERT')
                 or has_any_column_privilege(r, 'public.facturas', 'UPDATE')
                 or has_table_privilege(r, 'public.facturas', 'DELETE')) then
    raise exception 'recibi_total_suma_y_exento: anon o authenticated pueden escribir directamente en facturas; la exencion no se puede fiar de la fila guardada. No se aplica nada';
  end if;
  -- (c) A3 da por hecho «0 recibis con impuesto» (medido el 14-oct): si hay alguno vivo, al re-guardarlo su papel bajaria
  --     el importe en silencio, y uno enviado ya no se corrige re-guardando. Texto con regex, sin cast (imp_pct es texto libre).
  select count(*) into n
    from public.facturas
   where tipo = 'recibi' and not coalesce(anulada, false)
     and (   coalesce(datos #>> '{fields,imp_pct}', '')   ~ '[1-9]'
          or coalesce(datos #>> '{totales,impuesto}', '') ~ '[1-9]'
          or coalesce(datos #>> '{totales,pct}', '')      ~ '[1-9]'
          or (jsonb_typeof(datos #> '{fields,impuestos_sel}') = 'array'
              and jsonb_array_length(datos #> '{fields,impuestos_sel}') > 0));
  if n > 0 then
    raise exception 'recibi_total_suma_y_exento: % recibi(s) vivo(s) llevan impuesto en el papel; con A3 lo perderian al re-guardarse. No se aplica nada: se decide antes que hacer con ellos (Administracion recomienda anular y emitir otro sin impuesto)', n;
  end if;
  -- (d) el espejo de facturas ya es el de 20261014220000 (columna = papel: «<proyecto> — <unidad>»)
  if position('espejo desde el enlace (15-oct-2026)' in pg_get_functiondef('public.trg_espejo_proyecto()'::regprocedure)) = 0 then
    raise exception 'recibi_total_suma_y_exento: falta 20261014220000_facturas_conservan_parcela (trg_espejo_proyecto sin su marca); se aplica antes. No se aplica nada';
  end if;
end $antes$;

CREATE OR REPLACE FUNCTION public.guardar_recibi(p_id uuid, p_factura jsonb, p_aplicaciones jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_id uuid;
  v_numero text;
  v_aplicacion jsonb;
  v_contrato_id uuid;
  v_justificantes jsonb;
  v_factura_id uuid;
  v_factura_numero text;
  v_factura_contrato uuid;
  v_factura_autor text;
  v_factura_proyecto uuid;
  v_importe_aplic numeric;
  v_pend_factura numeric;
  v_moneda_factura text;
  v_rest boolean := public.alcance_restringido() and not public.es_admin();
  v_pnombre text;              -- 15-oct-2026 (3.a vuelta): del contrato comprobado, nunca del navegador
  v_pid uuid; v_emp text; v_emp_fac text;
  v_viejo public.facturas%rowtype;
  -- 14-oct-2026 (bloque A + C3 + fallo 1) y 15-oct-2026 (2.a vuelta del revisor)
  v_exento boolean := false;
  v_otro_contrato boolean := false;   -- 15-oct-2026 (Seguridad): alguna factura no es del contrato del recibi
  v_moneda text := p_factura->>'moneda';
  v_dec int := public.lw_decimales(p_factura->>'moneda');
  v_total numeric := 0;
  v_total_pantalla numeric;
  v_apl jsonb := '[]'::jsonb;
  v_lineas jsonb := '[]'::jsonb;
  v_priv jsonb := '[]'::jsonb;
  v_p jsonb;
  v_datos jsonb;
  v_campos jsonb;
  v_admin boolean;
  v_contrato_numero text;      -- 15-oct-2026 (code-review, hallazgo 2): sale del contrato comprobado, no del navegador
  v_pnombre_contrato text;     -- 15-oct-2026: el proyecto del contrato comprobado
  v_unidad text;               -- 15-oct-2026 (3.a vuelta): la unidad del contrato (la misma formula que 20261014220000)
  c_banco constant text[] := array['banco_titular', 'banco_nombre', 'banco_cuenta', 'banco_codigo', 'banco_direccion', 'banco_extra'];
  c_fuera constant text[] := array['imp_pct', 'imp_etiqueta', 'impuestos_sel', 'banco_de_servidor',
                                   'rectifica_numero', 'rectifica_fecha', 'rectificacion_motivo'];
begin
  if not public._puede_herr('facturas') then
    raise exception 'sin permiso para crear recibis' using errcode = '42501';
  end if;

  v_contrato_id := nullif(p_factura->>'contrato_id', '')::uuid;
  if v_contrato_id is null then
    raise exception 'el recibi necesita un contrato' using errcode = '23514';
  end if;

  if not public.es_super_admin_de(public._empresa_doc(null::uuid, v_contrato_id))
     and not exists (select 1 from public.contratos c
                      where c.id = v_contrato_id and public.puede_ver_contrato(c.id)) then
    raise exception 'No puedes emitir un recibí sobre un contrato que no ves' using errcode = '42501';
  end if;

  -- 15-oct-2026 (code-review, hallazgo 2 y 3.a vuelta): numero de contrato, proyecto_id y proyecto salen del contrato YA
  -- comprobado (enlace manda, texto espejo). Se leen DESPUES de la puerta: la funcion es DEFINER y antes seria un oraculo.
  -- El texto es «<proyecto> — <unidad>», la formula de trg_espejo_proyecto en facturas (20261014220000). Sin proyecto en el
  -- contrato: id y nombre null (con el nombre del navegador, el espejo buscaria un proyecto por nombre).
  select c.numero, c.proyecto_id, pr.nombre,
         coalesce(nullif(btrim(c.datos #>> '{fields,parcela_codigo}'), ''),
                  nullif(btrim(c.datos #>> '{fields,villa_nombre}'), ''),
                  nullif(btrim(c.datos #>> '{fields,tipologia_villa}'), ''))
    into v_contrato_numero, v_pid, v_pnombre_contrato, v_unidad
    from public.contratos c left join public.proyectos pr on pr.id = c.proyecto_id
   where c.id = v_contrato_id;
  v_pnombre := v_pnombre_contrato || coalesce(' — ' || v_unidad, '');

  v_emp := public._empresa_doc(null::uuid, v_contrato_id);
  if v_rest then
    if v_emp is null or not public.puede_empresa(v_emp) then
      raise exception 'Ese recibí no es de ninguna de tus empresas' using errcode = '42501';
    end if;
    if (p_id is null or (p_factura->>'sociedad') is distinct from (select f.sociedad from public.facturas f where f.id = p_id))
       and not exists (select 1 from public.empresas e where e.clave = v_emp and e.sociedad_clave = p_factura->>'sociedad') then
      raise exception 'Ese recibí tiene que salir por la sociedad de la empresa del proyecto' using errcode = '42501';
    end if;
  end if;

  -- Editar: la fila vieja se bloquea con el MISMO filtro de autoria que el UPDATE de abajo, ANTES de cualquier otra validacion
  -- (14-oct-2026, Seguridad #338: los permisos van primero). LAW-37: un recibi enviado no se edita.
  if p_id is not null then
    select * into v_viejo from public.facturas f
     where f.id = p_id and f.tipo = 'recibi' and f.anulada = false
       and (public.es_suyo(f.creado_por) or public.es_admin_de(public._empresa_doc(f.proyecto_id, f.contrato_id)))
     for update;
    if not found then
      raise exception 'no se pudo actualizar: no existe, esta anulado, o no es tuyo' using errcode = '42501';
    end if;
    if coalesce(v_viejo.enviada, false) then
      raise exception 'El recibí % ya se envió al cliente: no se edita. Anúlalo y emite otro si hace falta corregirlo.',
        coalesce(v_viejo.numero, '?') using errcode = '23514';
    end if;
    -- LAW-40 (fallo 1, 14-oct-2026): la exencion de justificante sale SOLO de la marca de la fila guardada; abajo, tras
    -- calcular el total, solo vale si total, contrato y moneda son los guardados (15-oct-2026), y solo mientras la fila
    -- guardada SIGA sin justificante (15-oct-2026, Seguridad: si ya se le adjunto uno, ya no es el historico de LAW-40)
    v_exento := coalesce(v_viejo.historico_sin_justificante, false)
                and v_viejo.justificantes = '[]'::jsonb
                and nullif(v_viejo.justificante_path, '') is null;
  end if;

  v_justificantes := case when jsonb_typeof(p_factura->'justificantes') = 'array'
                          then p_factura->'justificantes' else '[]'::jsonb end;
  if jsonb_array_length(v_justificantes) = 0
     and nullif(p_factura->>'justificante_path', '') is not null then
    v_justificantes := jsonb_build_array(jsonb_build_object('path', p_factura->>'justificante_path'));
  end if;

  if jsonb_array_length(v_justificantes) > 8 then
    raise exception 'demasiados justificantes en un recibi (maximo 8)' using errcode = '23514';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_justificantes) j
     where nullif(j->>'path', '') is null
        or not exists (select 1 from storage.objects o
                        where o.bucket_id = 'justificantes' and o.name = j->>'path')
  ) then
    raise exception 'algun justificante adjunto no existe en el almacenamiento' using errcode = '23514';
  end if;

  if jsonb_typeof(p_aplicaciones) is distinct from 'array' or jsonb_array_length(p_aplicaciones) = 0 then
    raise exception 'el recibi necesita al menos una factura que salde' using errcode = '23514';
  end if;
  if exists (select 1 from jsonb_array_elements(p_aplicaciones) a where nullif(a->>'factura_id', '') is null) then
    raise exception 'la aplicacion referencia una factura invalida o anulada' using errcode = '23514';
  end if;
  -- como uuid (15-oct-2026): el mismo id en mayusculas o en minusculas es la misma factura
  if (select count(*) from jsonb_array_elements(p_aplicaciones) a)
     <> (select count(distinct (a->>'factura_id')::uuid) from jsonb_array_elements(p_aplicaciones) a) then
    raise exception 'la misma factura aparece dos veces en el recibi: junta sus importes en una sola linea' using errcode = '23514';
  end if;

  -- A1 (14-oct-2026): TODAS las aplicaciones se validan ANTES de escribir, para que un rechazo no gaste numero
  perform 1 from public.facturas fl
   where fl.id in (select (a->>'factura_id')::uuid from jsonb_array_elements(p_aplicaciones) a)
   order by fl.id for update;
  for v_aplicacion in select * from jsonb_array_elements(p_aplicaciones) loop
    v_factura_id := (v_aplicacion->>'factura_id')::uuid;

    select f.numero, f.contrato_id, f.creado_por, f.proyecto_id, f.moneda
      into v_factura_numero, v_factura_contrato, v_factura_autor, v_factura_proyecto, v_moneda_factura
      from public.facturas f
     where f.id = v_factura_id
       and f.tipo = 'factura' and not coalesce(f.anulada, false);
    if not found then
      raise exception 'la aplicacion referencia una factura invalida o anulada' using errcode = '23514';
    end if;
    v_emp_fac := public._empresa_doc(v_factura_proyecto, v_factura_contrato);

    -- sin numero: quien no ve la factura no se entera de cual es (14-oct-2026, Seguridad #338)
    if not public.es_super_admin_de(v_emp_fac)
       and not public.documento_visible(v_factura_autor, v_factura_proyecto, v_factura_contrato) then
      raise exception 'una de las facturas no es un documento que veas: no le puedes aplicar un cobro' using errcode = '42501';
    end if;

    -- 15-oct-2026: la misma regla que valida_recibi_aplicacion, pero ANTES de numerar
    if v_moneda_factura is distinct from v_moneda then
      raise exception 'la factura % va en % y el recibí en %: un recibí solo salda facturas de su misma moneda',
        coalesce(v_factura_numero, '?'), coalesce(v_moneda_factura, 'ninguna'), coalesce(v_moneda, 'ninguna') using errcode = '23514';
    end if;

    -- A2: numero JSON tal cual; texto por el parser de importes («120.000» = 120000, no 120)
    v_importe_aplic := case jsonb_typeof(v_aplicacion->'importe')
                         when 'number' then (v_aplicacion->>'importe')::numeric
                         when 'string' then public.lw_parse_importe(v_aplicacion->>'importe')
                       end;
    v_importe_aplic := round(v_importe_aplic, v_dec);
    if v_importe_aplic is null or v_importe_aplic <= 0 then
      raise exception 'el importe que se aplica a la factura % tiene que ser mayor que cero', coalesce(v_factura_numero, '?') using errcode = '23514';
    end if;

    if v_factura_contrato is null then
      if public.es_super_admin_de(v_emp_fac) then
        v_priv := v_priv || jsonb_build_array(jsonb_build_object('evento', 'cobro_a_factura_huerfana', 'factura', v_factura_numero));
      else
        raise exception 'la factura % no cuelga de ningun contrato: no se le puede aplicar un cobro (LAW-38)',
          coalesce(v_factura_numero, '?') using errcode = '23514';
      end if;
    elsif not public.contratos_mismo_comprador(v_contrato_id, v_factura_contrato) then
      if public.es_super_admin_de(v_emp) and public.es_super_admin_de(v_emp_fac) then
        v_priv := v_priv || jsonb_build_array(jsonb_build_object('evento', 'cobro_a_otro_comprador', 'factura', v_factura_numero,
                                                                 'importe', v_importe_aplic));
      else
        raise exception 'la factura % es de otro comprador que el recibi', coalesce(v_factura_numero, '?')
          using errcode = '23514';
      end if;
    end if;
    -- 15-oct-2026 (Seguridad): huerfana, otro comprador u otro contrato del mismo comprador. Un historico SIN justificante
    -- no salda nada fuera de su contrato (se mira abajo, junto al resto de la exencion)
    if v_factura_contrato is distinct from v_contrato_id then
      v_otro_contrato := true;
    end if;

    -- al editar, lo ya aplicado por ESTE recibi no cuenta como cobrado de antes
    select f.total - coalesce((select sum(ra.importe_aplicado) from public.recibi_aplicaciones ra
                                 join public.facturas rc on rc.id = ra.recibi_id
                                where ra.factura_id = f.id and not coalesce(rc.anulada, false)
                                  and ra.recibi_id is distinct from p_id), 0)
      into v_pend_factura from public.facturas f where f.id = v_factura_id;
    -- tolerancia 0,01: la MISMA de valida_recibi_aplicacion (20260925030855_recibi_aplicaciones_ignora_anulados.sql:27)
    if v_importe_aplic > v_pend_factura + 0.01 then
      raise exception 'la factura % solo tiene % pendiente de cobro y este recibí le aplica %', coalesce(v_factura_numero, '?'), v_pend_factura, v_importe_aplic using errcode = '23514';
    end if;
    v_total := v_total + v_importe_aplic;
    v_apl := v_apl || jsonb_build_array(jsonb_build_object('factura_id', v_factura_id, 'importe', v_importe_aplic));
    -- PAPEL: la linea la escribe el servidor, con el texto de conceptoCobroRecibi (documento.js:40)
    v_lineas := v_lineas || jsonb_build_array(jsonb_build_object(
      'descripcion', case when nullif(btrim(coalesce(v_factura_numero, '')), '') is null then 'Cobro · Payment'
                          else 'Cobro de la factura ' || btrim(v_factura_numero) || ' · Payment of invoice ' || btrim(v_factura_numero) end,
      -- texto (no numero JSON): la pantalla clasica hace (l.importe || '').trim() (intranet/facturas/index.html:2325) y
      -- con la escala ya fijada a los decimales de la moneda («100.50», «39220») lwParseImporte no lo lee como miles
      'importe', v_importe_aplic::text));
  end loop;

  -- A4 (14-oct-2026): el total del recibi es la suma de lo que aplica; el de la pantalla solo se compara
  v_total_pantalla := case jsonb_typeof(p_factura->'total')
                        when 'number' then (p_factura->>'total')::numeric
                        when 'string' then public.lw_parse_importe(p_factura->>'total')
                      end;
  if v_total_pantalla is null or round(v_total_pantalla, v_dec) <> v_total then
    raise exception 'el total del recibí (%) no es la suma de lo que aplica a sus facturas (%): un recibí solo cobra lo que salda',
      coalesce(v_total_pantalla::text, 'vacío'), v_total using errcode = '23514';
  end if;

  -- Fallo 1 (LAW-40), con limite (15-oct-2026): sin justificante solo un historico que se guarda con SU total, contrato y moneda,
  -- y sobre facturas de SU contrato (Seguridad, 15-oct-2026)
  if jsonb_array_length(v_justificantes) = 0 then
    if not v_exento then
      raise exception 'el recibi necesita un justificante de pago adjunto' using errcode = '23514';
    end if;
    if round(v_viejo.total, v_dec) is distinct from v_total
       or v_viejo.contrato_id is distinct from v_contrato_id
       or v_viejo.moneda is distinct from v_moneda
       or v_otro_contrato then
      raise exception 'el recibí histórico % no tiene justificante: solo se puede aplicar por su total guardado (% %) y sobre facturas de su contrato. Para cambiar el importe o aplicarlo a otro contrato, adjunta el justificante.',
        coalesce(v_viejo.numero, '?'), v_viejo.total, coalesce(v_viejo.moneda, '') using errcode = '23514';
    end if;
  end if;

  -- PAPEL + A3 (sin impuesto) + C3 (cuenta «otros» solo admin de la empresa): datos lo arma el servidor
  v_datos := case when jsonb_typeof(p_factura->'datos') = 'object' then p_factura->'datos' else '{}'::jsonb end;
  v_campos := case when jsonb_typeof(v_datos->'fields') = 'object' then v_datos->'fields' else '{}'::jsonb end;
  v_campos := v_campos - c_fuera;
  v_admin := public.es_admin_de(v_emp);
  if not v_admin then
    if v_campos->>'cuenta' = 'otros' then
      if p_id is null
         or (v_viejo.datos->'fields'->>'cuenta') is distinct from 'otros'
         or exists (select 1 from unnest(c_banco) k
                     where (v_campos->>k) is distinct from (v_viejo.datos->'fields'->>k)) then
        raise exception 'La cuenta «Otros» (escrita a mano) solo la puede usar un administrador de la empresa: elige una cuenta de la lista.'
          using errcode = '42501';
      end if;
    else
      v_campos := v_campos - c_banco;
    end if;
  end if;
  v_campos := v_campos || jsonb_build_object('tipo', 'recibi', 'moneda', v_moneda, 'lineas', v_lineas);
  -- 15-oct-2026 (hallazgo 2): el papel imprime fields.contrato_numero y fields.proyecto_nombre (documento.js:179 y :201): los
  -- mismos que la fila (con 20261014220000; ver cabecera). Si el contrato no tiene numero (o no hay proyecto), la clave se
  -- quita: el papel no imprime uno inventado
  v_campos := (v_campos - array['contrato_numero', 'proyecto_nombre'])
              || jsonb_strip_nulls(jsonb_build_object('contrato_numero', v_contrato_numero, 'proyecto_nombre', v_pnombre));
  v_datos := v_datos || jsonb_build_object(
    'fields', v_campos,
    'lineas', v_lineas,
    'totales', jsonb_build_object('subtotal', v_total, 'pct', 0, 'impuesto', 0, 'total', v_total));

  if p_id is null then
    insert into public.facturas
      (tipo, sociedad, cliente_nombre, proyecto_id, proyecto_nombre, contrato_numero, contrato_id,
       total, moneda, fecha_emision, justificantes, datos)
    values
      ('recibi', p_factura->>'sociedad', p_factura->>'cliente_nombre', v_pid, v_pnombre,
       v_contrato_numero, v_contrato_id, v_total, v_moneda,
       nullif(p_factura->>'fecha_emision','')::date, v_justificantes, v_datos)
    returning id, numero into v_id, v_numero;
  else
    update public.facturas set
      sociedad = p_factura->>'sociedad', cliente_nombre = p_factura->>'cliente_nombre',
      -- 15-oct-2026 (Seguridad, 4.a vuelta): a la derecha del SET, contrato_id es el VIEJO. Si cambia el contrato, client_id
      -- queda null y trg_factura_hereda_cliente (update of contrato_id, client_id, proyecto_id; 20260822021026) lo vuelve a
      -- sacar del adquiriente_1 del contrato nuevo. Mismo contrato: se conserva
      client_id = case when contrato_id = v_contrato_id then client_id end,
      proyecto_id = v_pid, proyecto_nombre = v_pnombre, contrato_numero = v_contrato_numero,
      contrato_id = v_contrato_id, total = v_total, moneda = v_moneda,
      fecha_emision = nullif(p_factura->>'fecha_emision','')::date, justificantes = v_justificantes,
      datos = v_datos
    where id = p_id and tipo = 'recibi' and anulada = false
      and (public.es_suyo(creado_por) or public.es_admin_de(public._empresa_doc(proyecto_id, contrato_id)))
    returning id, numero into v_id, v_numero;
    if v_id is null then
      raise exception 'no se pudo actualizar: no existe, esta anulado, o no es tuyo' using errcode = '42501';
    end if;
    delete from public.recibi_aplicaciones where recibi_id = v_id;
  end if;

  for v_p in select * from jsonb_array_elements(v_priv) loop
    perform public.registra_privilegio(v_contrato_id, v_p->>'evento',
      (v_p - 'evento') || jsonb_build_object('recibi', v_numero));
  end loop;

  for v_aplicacion in select * from jsonb_array_elements(v_apl) loop
    insert into public.recibi_aplicaciones (recibi_id, factura_id, importe_aplicado, creado_por)
    values (v_id, (v_aplicacion->>'factura_id')::uuid, (v_aplicacion->>'importe')::numeric, (select auth.email()));
  end loop;

  return jsonb_build_object('id', v_id, 'numero', v_numero);
end;
$function$;

do $cierre$
begin
  if not has_function_privilege('authenticated', 'public.guardar_recibi(uuid,jsonb,jsonb)', 'execute')
     or has_function_privilege('anon', 'public.guardar_recibi(uuid,jsonb,jsonb)', 'execute')
     or not has_function_privilege('service_role', 'public.guardar_recibi(uuid,jsonb,jsonb)', 'execute') then
    raise exception 'recibi_total_suma_y_exento: los permisos de guardar_recibi cambiaron; no se aplica';
  end if;
  if exists (select 1 from unnest(array['anon', 'authenticated']) r
              where has_any_column_privilege(r, 'public.facturas', 'INSERT')
                 or has_any_column_privilege(r, 'public.facturas', 'UPDATE')
                 or has_table_privilege(r, 'public.facturas', 'DELETE')) then
    raise exception 'recibi_total_suma_y_exento: anon o authenticated pueden escribir directamente en facturas; no se aplica';
  end if;
end $cierre$;
$mig2159$;
  -- factura_moneda_del_contrato (sha256 b7704baee9072e77)
  begin
    execute $p2159_0$-- Prueba de LAW-553 (13-oct-2026): la moneda de un documento la decide su contrato, el tope de una venta se mide por
-- cadena Y moneda, y la moneda de un contrato con documentos no cambia por debajo. Migración:
-- supabase/migrations/20261013074408_factura_moneda_del_contrato.sql, con 20261013081849_factura_tope_proforma_y_reactiva
-- (a12, a13, h1, h2, c3) y 20261013105140_factura_reactiva_moneda (h3, h4: reactivar vuelve a comprobar la moneda).
--
-- Se ejecuta por execute_sql DESPUÉS de aplicar (o pegada detrás de la migración, antes de aplicarla): todo va en un
-- único bloque que termina con un raise a propósito, así que no deja rastro (contratos ZZ-L553-*, proyecto, facturas,
-- eventos y el trigger auxiliar de numeración se deshacen; la cola de pg_net también).
-- NO gasta números de la serie fiscal: los documentos de prueba llevan número explícito, y los que da de alta una RPC
-- (factura_guarda, guardar_recibi) lo reciben del trigger auxiliar trg_00a_zz_l553_num, que corre antes de
-- trg_set_factura_numero (mismo truco que tools/flujos_lawang.py).
-- Perfiles con el ROL REAL (`set local role authenticated` + claims JWT, como tools/flujos_lawang.py): el MCP corre
-- como postgres con bypassrls y sin cambiar de rol ninguna policy se evalúa. Identidades resueltas desde la base:
-- un agente con la herramienta Facturas y empresa, un admin y un super_admin; ningún uid ni email en el fichero.
-- Cada línea dice OK, MAL o PENDIENTE (solo g3-g5 y h1, ver allí); ninguna debe decir MAL. El canario C0 tiene que salir OK o lo demás no vale.
do $t$
declare
  out text := ''; v_p uuid; v_e uuid; v_i uuid; v_i2 uuid; v_n uuid; v_hs uuid; v_e2 uuid; v_f uuid; v_pro uuid;
  v_rec uuid; v_venc uuid; v_soc text; v_ag_sub text; v_ag_mail text; v_ag_emp text; v_ad_sub text; v_ad_mail text;
  v_sa_sub text; v_sa_mail text; v_ev int; acl_ok boolean;
  v_venc2 uuid; v_c3 uuid; v_c3i uuid; v_h1 uuid; v_h2 uuid; v_n0 int; v_n1 int; v_n2 int; v_e0 int; v_e1 int;
  v_ok boolean; v_m uuid; v_h3 uuid; v_h4 uuid;
begin
  -- ── identidades ────────────────────────────────────────────────────────────────────────────────────────────────
  select u.user_id::text, u.email, coalesce(u.empresas[1], '') into v_ag_sub, v_ag_mail, v_ag_emp
    from public.usuarios u where u.activo and u.rol = 'agente' and 'facturas' = any(u.herramientas)
     and coalesce(array_length(u.empresas, 1), 0) > 0 and coalesce(array_length(u.proyectos_supervisados, 1), 0) = 0
   order by u.creado_en limit 1;
  select u.user_id::text, u.email into v_ad_sub, v_ad_mail
    from public.usuarios u where u.activo and u.rol = 'admin' order by u.creado_en limit 1;
  select u.user_id::text, u.email into v_sa_sub, v_sa_mail
    from public.usuarios u where u.activo and u.rol = 'super_admin' order by u.creado_en limit 1;
  select coalesce((select e.sociedad_clave from public.empresas e where e.clave = v_ag_emp),
                  (select clave from public.sociedades order by clave limit 1)) into v_soc;
  out := out || 'identidades: agente=' || (v_ag_sub is not null) || ' admin=' || (v_ad_sub is not null)
             || ' super_admin=' || (v_sa_sub is not null) || E'\n';

  -- ── datos (como postgres, con las claims del super_admin: hay triggers que miran auth.uid()) ───────────────────
  perform set_config('request.jwt.claims', json_build_object('sub', v_sa_sub, 'email', v_sa_mail, 'role', 'authenticated')::text, true);
  create function public.zz_l553_num() returns trigger language plpgsql as $f$ begin
    if new.numero is null then new.numero := 'ZZ-L553-N' || left(gen_random_uuid()::text, 8); end if; return new; end $f$;
  create trigger trg_00a_zz_l553_num before insert on public.facturas for each row execute function public.zz_l553_num();
  insert into storage.objects (bucket_id, name) values ('justificantes', 'zz-l553/justificante.pdf');

  insert into public.proyectos (nombre, slug, empresa) values ('ZZ L553 PROYECTO', 'zz-l553-proyecto', nullif(v_ag_emp, '')) returning id into v_p;
  -- E: venta en EUR con precio 1.000, del agente
  insert into public.contratos (numero, tipo, proyecto_id, moneda, precio_total, datos, creado_por)
    values ('ZZ-L553-E', 'contrato_general', v_p, 'EUR', 1000, '{"hitos":[]}', v_ag_mail) returning id into v_e;
  -- E2: otra venta en EUR. I: hija de E en IDR con precio 5.000.000; I2: hija de E2 en IDR sin precio. Van en ventas
  -- distintas a propósito: un miembro en IDR sin precio deja «sin precio» TODA la parte en IDR de su venta, y entonces
  -- la factura en IDR se rechaza (es la regla: en otra moneda, sin precio no hay tope y se para).
  -- contrato_general y no construccion: una Construcción exige tipología y techo. Alta firmada y luego la moneda: el
  -- trigger de moneda no toca un contrato firmado y, sin documentos, el guarda nuevo deja cambiarla.
  insert into public.contratos (numero, tipo, proyecto_id, moneda, precio_total, datos, creado_por)
    values ('ZZ-L553-E2', 'contrato_general', v_p, 'EUR', 1000, '{"hitos":[]}', v_ag_mail) returning id into v_e2;
  insert into public.contratos (numero, tipo, proyecto_id, precio_total, contrato_padre_id, datos, creado_por, bloqueado)
    values ('ZZ-L553-I', 'contrato_general', v_p, 5000000, v_e, '{"hitos":[]}', v_ag_mail, true) returning id into v_i;
  insert into public.contratos (numero, tipo, proyecto_id, precio_total, contrato_padre_id, datos, creado_por, bloqueado)
    values ('ZZ-L553-I2', 'contrato_general', v_p, null, v_e2, '{"hitos":[]}', v_ag_mail, true) returning id into v_i2;
  update public.contratos set moneda = 'IDR' where id in (v_i, v_i2);
  -- N: contrato sin moneda (ni unidad ni padre); HS: Hak Sewa hijo de E (hereda EUR)
  insert into public.contratos (numero, tipo, proyecto_id, moneda, precio_total, datos, creado_por)
    values ('ZZ-L553-N', 'contrato_general', v_p, null, 1000, '{"hitos":[]}', v_ag_mail) returning id into v_n;
  insert into public.contratos (numero, tipo, proyecto_id, precio_total, contrato_padre_id, datos, creado_por)
    values ('ZZ-L553-HS', 'hak_sewa_notario', v_p, null, v_e, '{"hitos":[]}', v_ag_mail) returning id into v_hs;
  insert into public.contrato_vencimientos (contrato_id, orden, descripcion, monto, fecha)
    values (v_e, 1, 'ZZ L553', 100, current_date + 1) returning id into v_venc;
  insert into public.contrato_vencimientos (contrato_id, orden, descripcion, monto, fecha)
    values (v_e, 2, 'ZZ L553 b', 100, current_date + 2) returning id into v_venc2;
  -- h1/h2 (reactivar): en E2 (precio 1.000) una factura viva de 500 y dos anuladas sin enviar, de 600 y de 400.
  insert into public.facturas (numero, sociedad, tipo, contrato_id, datos, total, moneda, creado_por)
    values ('ZZ-L553-H0', v_soc, 'factura', v_e2, '{}'::jsonb, 500, 'EUR', v_ag_mail);
  insert into public.facturas (numero, sociedad, tipo, contrato_id, datos, total, moneda, creado_por, anulada)
    values ('ZZ-L553-H1', v_soc, 'factura', v_e2, '{}'::jsonb, 600, 'EUR', v_ag_mail, true) returning id into v_h1;
  insert into public.facturas (numero, sociedad, tipo, contrato_id, datos, total, moneda, creado_por, anulada)
    values ('ZZ-L553-H2', v_soc, 'factura', v_e2, '{}'::jsonb, 400, 'EUR', v_ag_mail, true) returning id into v_h2;
  -- h3/h4 (revisión de código sobre b40a8a2f8, 13-oct; migración 20261013105140_factura_reactiva_moneda): M, venta EUR con una factura y una
  -- proforma en EUR. Se anulan, M pasa a IDR (con todo anulado, trg_zz_00 lo deja) y se intenta reactivarlas.
  -- Alta firmada (bloqueado) para que trg_contrato_moneda_desde_unidad no recalcule la moneda.
  insert into public.contratos (numero, tipo, proyecto_id, moneda, precio_total, datos, creado_por, bloqueado)
    values ('ZZ-L553-M', 'contrato_general', v_p, 'EUR', 1000, '{"hitos":[]}', v_ag_mail, true) returning id into v_m;
  insert into public.facturas (numero, sociedad, tipo, contrato_id, datos, total, moneda, creado_por)
    values ('ZZ-L553-H3', v_soc, 'factura', v_m, '{}'::jsonb, 100, 'EUR', v_ag_mail) returning id into v_h3;
  insert into public.facturas (numero, sociedad, tipo, contrato_id, datos, total, moneda, creado_por)
    values ('ZZ-L553-H4', v_soc, 'proforma', v_m, '{}'::jsonb, 10, 'EUR', v_ag_mail) returning id into v_h4;
  update public.facturas set anulada = true where id in (v_h3, v_h4);
  begin update public.contratos set moneda = 'IDR' where id = v_m;
    out := out || case when (select moneda from public.contratos where id = v_m) = 'IDR' then 'OK ' else 'MAL ' end
               || E'h0 montaje: con sus documentos anulados, M pasa de EUR a IDR\n';
  exception when others then out := out || 'MAL h0 montaje (M a IDR): ' || sqlstate || ' ' || left(sqlerrm, 100) || E'\n'; end;
  -- c3: copia INVOKER, sin tope, de factura_vencimiento_emite tal como la dejó 20260926160000 (la de antes de LAW-553),
  -- para comparar lo que deja el robot en su versión DEFINER con lo que dejaba antes.
  create function public.zz_l553_venc_invoker(p_venc_id uuid, p_fila jsonb)
    returns table (id uuid, numero text, datos jsonb) language plpgsql security invoker set search_path to '' as $f$
  declare v_contrato uuid; v_factura uuid; f public.facturas; n int;
  begin
    select cv.contrato_id, cv.factura_id into v_contrato, v_factura
      from public.contrato_vencimientos cv where cv.id = p_venc_id for update;
    if not found then raise exception 'vencimiento % no existe', p_venc_id using hint = 'sin_fila'; end if;
    if v_factura is not null then raise exception 'vencimiento % ya tiene factura', p_venc_id using hint = 'ya_facturado'; end if;
    insert into public.facturas (tipo, sociedad, cliente_nombre, proyecto_nombre, contrato_numero, contrato_id,
                                 total, moneda, fecha_emision, datos)
    values (p_fila->>'tipo', p_fila->>'sociedad', p_fila->>'cliente_nombre', p_fila->>'proyecto_nombre',
            p_fila->>'contrato_numero', v_contrato, (p_fila->>'total')::numeric, p_fila->>'moneda',
            (p_fila->>'fecha_emision')::date, p_fila->'datos')
    returning * into f;
    update public.contrato_vencimientos cv set factura_id = f.id where cv.id = p_venc_id;
    get diagnostics n = row_count;
    if n <> 1 then raise exception 'no se pudo marcar el vencimiento %', p_venc_id using hint = 'sin_fila'; end if;
    return query select f.id, f.numero, f.datos;
  end $f$;
  revoke all on function public.zz_l553_venc_invoker(uuid, jsonb) from public, anon, authenticated;
  grant execute on function public.zz_l553_venc_invoker(uuid, jsonb) to service_role;
  out := out || 'datos: E=' || (select moneda from public.contratos where id = v_e) || ' I=' || (select moneda from public.contratos where id = v_i)
             || ' N=' || coalesce((select moneda from public.contratos where id = v_n), 'null')
             || ' HS=' || coalesce((select moneda from public.contratos where id = v_hs), 'null') || E'\n';

  -- ── como AGENTE ─────────────────────────────────────────────────────────────────────────────────────────────────
  perform set_config('request.jwt.claims', json_build_object('sub', v_ag_sub, 'email', v_ag_mail, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  out := out || case when current_user = 'authenticated' and auth.uid()::text = v_ag_sub and not public.es_super_admin()
                     then 'OK ' else 'MAL ' end || E'C0 canario agente: rol y claims\n';

  begin perform public.factura_guarda(null, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_id', v_e, 'moneda', 'IDR', 'total', '500',
                 'datos', jsonb_build_object('lineas', jsonb_build_array(jsonb_build_object('descripcion', 'x', 'importe', '500')), 'fields', '{}'::jsonb)));
    out := out || E'MAL a1 factura IDR sobre venta EUR: PASA\n';
  exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%va en EUR%' then 'OK ' else 'MAL ' end
                                       || 'a1 factura IDR sobre venta EUR: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;

  begin perform public.factura_guarda(null, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_id', v_e, 'total', '500',
                 'datos', jsonb_build_object('lineas', jsonb_build_array(jsonb_build_object('descripcion', 'x', 'importe', '500')), 'fields', '{}'::jsonb)));
    out := out || E'MAL a2 factura sin moneda: PASA\n';
  exception when others then out := out || case when sqlstate = '23514' then 'OK ' else 'MAL ' end
                                       || 'a2 factura sin moneda: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;

  begin
    select id into v_f from public.factura_guarda(null, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_id', v_e, 'moneda', 'EUR', 'total', '500',
                 'datos', jsonb_build_object('lineas', jsonb_build_array(jsonb_build_object('descripcion', 'x', 'importe', '500')), 'fields', '{}'::jsonb)));
    out := out || E'OK a3 factura EUR 500 sobre venta EUR 1.000: pasa\n';
  exception when others then out := out || 'MAL a3 factura EUR 500: ' || sqlstate || ' ' || left(sqlerrm, 100) || E'\n'; end;

  begin perform public.factura_guarda(null, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_id', v_e, 'moneda', 'EUR', 'total', '600',
                 'datos', jsonb_build_object('lineas', jsonb_build_array(jsonb_build_object('descripcion', 'x', 'importe', '600')), 'fields', '{}'::jsonb)));
    out := out || E'MAL a4 tope EUR 500+600 sobre 1.000: PASA\n';
  exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%precio acordado%' then 'OK ' else 'MAL ' end
                                       || 'a4 tope EUR 500+600 sobre 1.000: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;

  begin perform public.factura_guarda(null, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_id', v_i, 'moneda', 'IDR', 'total', '4000000',
                 'datos', jsonb_build_object('lineas', jsonb_build_array(jsonb_build_object('descripcion', 'x', 'importe', '4000000')), 'fields', '{}'::jsonb)));
    out := out || E'OK a5 hija IDR 4.000.000 sobre su precio 5.000.000: pasa\n';
  exception when others then out := out || 'MAL a5 hija IDR 4.000.000: ' || sqlstate || ' ' || left(sqlerrm, 100) || E'\n'; end;

  begin perform public.factura_guarda(null, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_id', v_i, 'moneda', 'IDR', 'total', '2000000',
                 'datos', jsonb_build_object('lineas', jsonb_build_array(jsonb_build_object('descripcion', 'x', 'importe', '2000000')), 'fields', '{}'::jsonb)));
    out := out || E'MAL a6 tope IDR 4M+2M sobre 5M: PASA (antes de LAW-553 pasaba sin tope)\n';
  exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%precio acordado%IDR%' then 'OK ' else 'MAL ' end
                                       || 'a6 tope IDR 4M+2M sobre 5M: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;

  begin perform public.factura_guarda(null, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_id', v_i2, 'moneda', 'IDR', 'total', '100',
                 'datos', jsonb_build_object('lineas', jsonb_build_array(jsonb_build_object('descripcion', 'x', 'importe', '100')), 'fields', '{}'::jsonb)));
    out := out || E'MAL a7 hija IDR sin precio: PASA\n';
  exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%con precio en IDR%' then 'OK ' else 'MAL ' end
                                       || 'a7 hija IDR sin precio: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;

  begin perform public.factura_guarda(null, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_id', v_n, 'moneda', 'EUR', 'total', '10',
                 'datos', jsonb_build_object('lineas', jsonb_build_array(jsonb_build_object('descripcion', 'x', 'importe', '10')), 'fields', '{}'::jsonb)));
    out := out || E'MAL a8 contrato sin moneda: PASA\n';
  exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%no tiene moneda%' then 'OK ' else 'MAL ' end
                                       || 'a8 contrato sin moneda: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;

  begin perform public.factura_guarda(null, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_id', v_hs, 'moneda', 'EUR', 'total', '10',
                 'datos', jsonb_build_object('lineas', jsonb_build_array(jsonb_build_object('descripcion', 'x', 'importe', '10')), 'fields', '{}'::jsonb)));
    out := out || E'MAL a9 Hak Sewa (agente): PASA\n';
  exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%Hak Sewa%' then 'OK ' else 'MAL ' end
                                       || 'a9 Hak Sewa (agente): ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;

  begin perform public.factura_guarda(null, jsonb_build_object('tipo', 'proforma', 'sociedad', v_soc, 'contrato_id', v_e, 'moneda', 'IDR', 'total', '10',
                 'datos', jsonb_build_object('lineas', jsonb_build_array(jsonb_build_object('descripcion', 'x', 'importe', '10')), 'fields', '{}'::jsonb)));
    out := out || E'MAL a10 proforma IDR sobre venta EUR: PASA\n';
  exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%va en EUR%' then 'OK ' else 'MAL ' end
                                       || 'a10 proforma IDR sobre venta EUR: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;

  -- a11: editar la factura de a3 llevándola a la hija en IDR sin cambiar la moneda → para por moneda
  begin perform public.factura_guarda(v_f, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_id', v_i, 'moneda', 'EUR', 'total', '500',
                 'datos', jsonb_build_object('lineas', jsonb_build_array(jsonb_build_object('descripcion', 'x', 'importe', '500')), 'fields', '{}'::jsonb)));
    out := out || E'MAL a11 edición a contrato en otra moneda: PASA\n';
  exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%va en IDR%' then 'OK ' else 'MAL ' end
                                       || 'a11 edición a contrato en otra moneda: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;

  -- a12/a13 (revisión de código, 13-oct): una proforma convertida en factura cuenta entera en el tope; el atajo de
  -- «editar sin subir el importe» solo vale para una factura que ya contaba. a3 ya factura 500 de los 1.000 de E.
  begin
    select id into v_pro from public.factura_guarda(null, jsonb_build_object('tipo', 'proforma', 'sociedad', v_soc, 'contrato_id', v_e, 'moneda', 'EUR', 'total', '600',
                 'datos', jsonb_build_object('lineas', jsonb_build_array(jsonb_build_object('descripcion', 'x', 'importe', '600')), 'fields', '{}'::jsonb)));
    begin perform public.factura_guarda(v_pro, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_id', v_e, 'moneda', 'EUR', 'total', '600',
                 'datos', jsonb_build_object('lineas', jsonb_build_array(jsonb_build_object('descripcion', 'x', 'importe', '600')), 'fields', '{}'::jsonb)));
      out := out || E'MAL a12 proforma de 600 pasada a factura con 500 de 1.000 facturados: PASA\n';
    exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%precio acordado%' then 'OK ' else 'MAL ' end
                                         || 'a12 proforma de 600 pasada a factura con 500 de 1.000 facturados: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;
  exception when others then out := out || 'MAL a12 montaje (proforma): ' || sqlstate || ' ' || left(sqlerrm, 100) || E'\n'; end;
  -- a13: la MISMA proforma de a12 (solo puede haber una proforma viva por contrato: facturas_proforma_activa_por_contrato)
  -- pasada a factura por 300: 500+300 de 1.000, pasa. La conversión no gasta número (set_factura_numero solo en INSERT).
  begin
    if v_pro is null then raise exception 'sin la proforma de a12'; end if;
    perform public.factura_guarda(v_pro, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_id', v_e, 'moneda', 'EUR', 'total', '300',
                 'datos', jsonb_build_object('lineas', jsonb_build_array(jsonb_build_object('descripcion', 'x', 'importe', '300')), 'fields', '{}'::jsonb)));
    out := out || case when (select tipo from public.facturas where id = v_pro) = 'factura' then 'OK ' else 'MAL ' end
               || E'a13 proforma de 300 pasada a factura dentro del tope (500+300 de 1.000): pasa\n';
  exception when others then out := out || 'MAL a13 proforma pasada a factura por 300: ' || sqlstate || ' ' || left(sqlerrm, 100) || E'\n'; end;

  -- b1: recibí del agente sobre su venta EUR mandando IDR → para (trigger, camino de guardar_recibi; la RPC exige al
  -- menos una factura que saldar, así que se aplica a la de a3)
  begin perform public.guardar_recibi(null, jsonb_build_object('contrato_id', v_e, 'sociedad', v_soc, 'total', '1', 'moneda', 'IDR',
                 'justificantes', jsonb_build_array(jsonb_build_object('path', 'zz-l553/justificante.pdf')), 'datos', '{}'::jsonb),
                 jsonb_build_array(jsonb_build_object('factura_id', v_f, 'importe', '1')));
    out := out || E'MAL b1 recibí IDR sobre venta EUR: PASA\n';
  exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%va en EUR%' then 'OK ' else 'MAL ' end
                                       || 'b1 recibí IDR sobre venta EUR: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;

  execute 'reset role';

  -- ── como ADMIN (no super): el Hak Sewa sigue parado ─────────────────────────────────────────────────────────────
  if v_ad_sub is not null then
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad_sub, 'email', v_ad_mail, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    begin perform public.factura_guarda(null, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_id', v_hs, 'moneda', 'EUR', 'total', '10',
                   'datos', jsonb_build_object('lineas', jsonb_build_array(jsonb_build_object('descripcion', 'x', 'importe', '10')), 'fields', '{}'::jsonb)));
      out := out || E'MAL g1 Hak Sewa (admin): PASA\n';
    exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%Hak Sewa%' then 'OK ' else 'MAL ' end
                                         || 'g1 Hak Sewa (admin): ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;
    execute 'reset role';
  else
    out := out || E'MAL g1 sin admin activo para probar\n';
  end if;

  -- ── como SUPER_ADMIN: la moneda no tiene salida; Hak Sewa y tope sin precio pasan CON rastro ───────────────────
  perform set_config('request.jwt.claims', json_build_object('sub', v_sa_sub, 'email', v_sa_mail, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  out := out || case when current_user = 'authenticated' and public.es_super_admin() then 'OK ' else 'MAL ' end || E'C0 canario super_admin\n';
  begin perform public.factura_guarda(null, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_id', v_e, 'moneda', 'IDR', 'total', '500',
                 'datos', jsonb_build_object('lineas', jsonb_build_array(jsonb_build_object('descripcion', 'x', 'importe', '500')), 'fields', '{}'::jsonb)));
    out := out || E'MAL g2 super_admin factura IDR sobre venta EUR: PASA\n';
  exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%va en EUR%' then 'OK ' else 'MAL ' end
                                       || 'g2 super_admin moneda ajena: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;
  begin perform public.factura_guarda(null, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_id', v_hs, 'moneda', 'EUR', 'total', '10',
                 'datos', jsonb_build_object('lineas', jsonb_build_array(jsonb_build_object('descripcion', 'x', 'importe', '10')), 'fields', '{}'::jsonb)));
    out := out || E'OK g3 super_admin Hak Sewa: pasa\n';
  -- PENDIENTE (no MAL) mientras contrato_eventos_evento_check no admita el evento del rastro: la salida falla cerrada
  -- (contracts/sql/contrato_eventos_privilegios.sql, la aplica el owner). Cualquier otro error sí es MAL.
  exception when others then out := out || case when sqlerrm like '%contrato_eventos_evento_check%' then 'PENDIENTE ' else 'MAL ' end
                                       || 'g3 super_admin Hak Sewa: ' || sqlstate || ' ' || left(sqlerrm, 100) || E'\n'; end;
  begin perform public.factura_guarda(null, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_id', v_i2, 'moneda', 'IDR', 'total', '100',
                 'datos', jsonb_build_object('lineas', jsonb_build_array(jsonb_build_object('descripcion', 'x', 'importe', '100')), 'fields', '{}'::jsonb)));
    out := out || E'OK g4 super_admin hija IDR sin precio: pasa\n';
  exception when others then out := out || case when sqlerrm like '%contrato_eventos_evento_check%' then 'PENDIENTE ' else 'MAL ' end
                                       || 'g4 super_admin hija IDR sin precio: ' || sqlstate || ' ' || left(sqlerrm, 100) || E'\n'; end;
  -- h1/h2 (revisión de código, 13-oct): reactivar una factura anulada la devuelve al tope. E2: 500 vivos de 1.000.
  -- h1, 600 → 1.100: el super_admin solo pasa con rastro 'factura_sobre_tope' (PENDIENTE mientras LAW-560 no amplíe
  -- contrato_eventos_evento_check); pasar SIN rastro es MAL (era lo de antes). h2, 400 → 900: pasa.
  select count(*) into v_e0 from public.contrato_eventos where contrato_id = v_e2 and evento = 'factura_sobre_tope';
  begin perform public.factura_reactiva(v_h1);
    select count(*) into v_e1 from public.contrato_eventos where contrato_id = v_e2 and evento = 'factura_sobre_tope';
    out := out || case when v_e1 > v_e0 then 'OK ' else 'MAL ' end || 'h1 reactivar 600 sobre 500 de 1.000: pasa con rastro=' || (v_e1 > v_e0) || E'\n';
  -- 23514 por sí solo no basta (la constraint de contrato_eventos también lo da): tiene que ser el mensaje del tope
  exception when others then out := out || case when sqlerrm like '%contrato_eventos_evento_check%' then 'PENDIENTE '
                                                  when sqlstate = '23514' and sqlerrm like '%precio acordado%' then 'OK ' else 'MAL ' end
                                       || 'h1 reactivar 600 sobre 500 de 1.000: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;
  begin perform public.factura_reactiva(v_h2);
    out := out || case when not (select anulada from public.facturas where id = v_h2) then 'OK ' else 'MAL ' end
               || E'h2 reactivar 400 dentro del tope: pasa\n';
  exception when others then out := out || 'MAL h2 reactivar 400 dentro del tope: ' || sqlstate || ' ' || left(sqlerrm, 100) || E'\n'; end;
  -- h3: la factura EUR anulada de M, ahora en IDR → no se reactiva (ni el super_admin: integridad, no tope)
  begin perform public.factura_reactiva(v_h3);
    out := out || E'MAL h3 reactivar factura EUR sobre contrato que pasó a IDR: PASA\n';
  exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%va en IDR%' then 'OK ' else 'MAL ' end
                                       || 'h3 reactivar factura EUR sobre contrato que pasó a IDR: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;
  execute 'reset role';
  select count(*) into v_ev from public.contrato_eventos
   where (contrato_id = v_hs and evento = 'documento_sobre_hak_sewa') or (contrato_id = v_i2 and evento = 'factura_sobre_tope');
  out := out || case when v_ev = 2 then 'OK '
                     when v_ev = 0 and not exists (select 1 from pg_constraint where conname = 'contrato_eventos_evento_check'
                                                     and pg_get_constraintdef(oid) like '%factura_sobre_tope%') then 'PENDIENTE '
                     else 'MAL ' end || 'g5 rastro de los dos pases del super_admin: ' || v_ev || E' (deben ser 2)\n';

  -- ── robot (service_role): factura_vencimiento_emite con moneda ajena ───────────────────────────────────────────
  perform set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
  execute 'set local role service_role';
  begin perform public.factura_vencimiento_emite(v_venc, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_numero', 'ZZ-L553-E',
                 'total', 100, 'moneda', 'IDR', 'fecha_emision', current_date, 'datos', '{}'::jsonb));
    out := out || E'MAL c1 robot con moneda ajena: PASA\n';
  exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%va en EUR%' then 'OK ' else 'MAL ' end
                                       || 'c1 robot con moneda ajena: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;
  begin perform public.factura_vencimiento_emite(v_venc, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_numero', 'ZZ-L553-E',
                 'total', 900, 'moneda', 'EUR', 'fecha_emision', current_date, 'datos', jsonb_build_object('totales', jsonb_build_object('subtotal', 900))));
    out := out || E'MAL c2 robot sobre el tope (800+900 sobre 1.000): PASA\n';
  exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%precio acordado%' then 'OK ' else 'MAL ' end
                                       || 'c2 robot sobre el tope: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;
  -- c3: caso POSITIVO del robot (DEFINER desde 20261013074408). Dentro del tope (500+300 de a3/a13, +50 y +50: sin
  -- llegar a 1.000, porque saldar la venta dispara un aviso 'operacion_saldada' más y la comparación saldría falsa) y con la
  -- moneda buena: inserta y marca el vencimiento. Y deja lo mismo que la versión INVOKER de antes (copia de arriba,
  -- otro vencimiento del mismo contrato): creado_por (fija_autor devuelve la fila sin tocar con auth.role() =
  -- 'service_role'; el default auth.email() es null), created_at = now(), y los mismos avisos de los triggers AFTER.
  select count(*) into v_n0 from public.notificaciones where contrato_id = v_e;
  begin
    select id into v_c3 from public.factura_vencimiento_emite(v_venc, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_numero', 'ZZ-L553-E',
                 'total', 50, 'moneda', 'EUR', 'fecha_emision', current_date, 'datos', jsonb_build_object('totales', jsonb_build_object('subtotal', 50))));
    select count(*) into v_n1 from public.notificaciones where contrato_id = v_e;
    select id into v_c3i from public.zz_l553_venc_invoker(v_venc2, jsonb_build_object('tipo', 'factura', 'sociedad', v_soc, 'contrato_numero', 'ZZ-L553-E',
                 'total', 50, 'moneda', 'EUR', 'fecha_emision', current_date, 'datos', jsonb_build_object('totales', jsonb_build_object('subtotal', 50))));
    select count(*) into v_n2 from public.notificaciones where contrato_id = v_e;
  exception when others then out := out || 'MAL c3 robot dentro del tope: ' || sqlstate || ' ' || left(sqlerrm, 100) || E'\n'; end;
  -- h4: el camino del TRIGGER. service_role (las edges) revive por UPDATE directo la proforma EUR anulada de M (ahora
  -- IDR): factura_anulada_solo_cambia_autor no mira nada sin auth.uid(), así que solo la para trg_01_moneda_del_contrato.
  out := out || case when current_user = 'service_role' then 'OK ' else 'MAL ' end || E'C0 canario service_role\n';
  begin update public.facturas set anulada = false where id = v_h4;
    out := out || E'MAL h4 service_role revive proforma EUR sobre contrato que pasó a IDR: PASA\n';
  exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%va en IDR%' then 'OK ' else 'MAL ' end
                                       || 'h4 service_role revive proforma EUR sobre contrato IDR: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;
  execute 'reset role';
  if v_c3 is not null and v_c3i is not null then
    select a.creado_por is null and a.created_at = now()
           and (a.creado_por, a.created_at, a.tipo, a.moneda, a.total, a.anulada, a.enviada, a.sociedad, a.contrato_id, a.proyecto_id)
               is not distinct from (b.creado_por, b.created_at, b.tipo, b.moneda, b.total, b.anulada, b.enviada, b.sociedad, b.contrato_id, b.proyecto_id)
           and (select cv.factura_id from public.contrato_vencimientos cv where cv.id = v_venc) = v_c3
           and (select cv.factura_id from public.contrato_vencimientos cv where cv.id = v_venc2) = v_c3i
           and v_n1 - v_n0 = v_n2 - v_n1
      into v_ok
      from public.facturas a, public.facturas b where a.id = v_c3 and b.id = v_c3i;
    out := out || case when v_ok then 'OK ' else 'MAL ' end
               || 'c3 robot dentro del tope: inserta, marca el vencimiento y deja lo mismo que la versión INVOKER (avisos '
               || (v_n1 - v_n0) || '/' || (v_n2 - v_n1) || E')\n';
  end if;

  -- ── contrato con documentos (como postgres —los cambios de contrato van por RPCs DEFINER—, con las claims del
  --    agente: no es super_admin, así que no hay salida con rastro) ──────────────────────────────────────────────
  perform set_config('request.jwt.claims', json_build_object('sub', v_ag_sub, 'email', v_ag_mail, 'role', 'authenticated')::text, true);
  begin update public.contratos set moneda = 'IDR' where id = v_e;
    out := out || E'MAL d1 cambiar la moneda de una venta con documentos: PASA\n';
  exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%moneda de un contrato con documentos%' then 'OK ' else 'MAL ' end
                                       || 'd1 cambiar la moneda de una venta con documentos: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;
  begin update public.contratos set datos = datos where id = v_e;
    out := out || E'OK d2 volver a guardar la venta sin cambiar moneda: pasa\n';
  exception when others then out := out || 'MAL d2 volver a guardar la venta: ' || sqlstate || ' ' || left(sqlerrm, 100) || E'\n'; end;
  begin update public.contratos set contrato_padre_id = v_e2 where id = v_i;
    out := out || E'MAL e1 colgar de otra venta un contrato con facturas: PASA\n';
  exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%otra venta%' then 'OK ' else 'MAL ' end
                                       || 'e1 colgar de otra venta un contrato con facturas: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;

  -- f1: un recibí aplicado a la factura de a3 no cambia de moneda, ni siquiera pasándolo a la vez a un contrato de la
  -- otra moneda (el único cambio que la regla de contrato dejaría pasar; facturas_contrato_obligatorio impide el
  -- documento sin contrato)
  begin
    insert into public.facturas (numero, sociedad, tipo, contrato_id, datos, total, moneda, creado_por, justificante_path, justificantes)
      values ('ZZ-L553-REC', v_soc, 'recibi', v_e, '{}'::jsonb, 100, 'EUR', v_ag_mail, 'zz-l553/justificante.pdf',
              jsonb_build_array(jsonb_build_object('path', 'zz-l553/justificante.pdf'))) returning id into v_rec;
    insert into public.recibi_aplicaciones (recibi_id, factura_id, importe_aplicado) values (v_rec, v_f, 100);
    begin update public.facturas set contrato_id = v_i, moneda = 'IDR' where id = v_rec;
      out := out || E'MAL f1 cambiar la moneda de un recibí aplicado: PASA\n';
    exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%cobros aplicados%' then 'OK ' else 'MAL ' end
                                         || 'f1 cambiar la moneda de un recibí aplicado: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;
  exception when others then out := out || 'MAL f1 montaje (aplicación): ' || sqlstate || ' ' || left(sqlerrm, 100) || E'\n'; end;

  -- b2: moneda fuera de la lista cerrada. El contrato N (sin documentos) se pone en «XXX» para que la regla del
  -- contrato deje pasar y sea la constraint la que pare.
  update public.contratos set moneda = 'XXX' where id = v_n;
  begin insert into public.facturas (numero, sociedad, tipo, contrato_id, datos, total, moneda, creado_por)
          values ('ZZ-L553-X', v_soc, 'proforma', v_n, '{}'::jsonb, 1, 'XXX', v_ag_mail);
    out := out || E'MAL b2 moneda XXX: PASA\n';
  exception when others then out := out || case when sqlstate = '23514' and sqlerrm like '%facturas_moneda_admitida%' then 'OK ' else 'MAL ' end
                                       || 'b2 moneda XXX: ' || sqlstate || ' ' || left(sqlerrm, 80) || E'\n'; end;

  -- ── privilegios: las piezas nuevas no son de nadie de fuera ────────────────────────────────────────────────────
  select bool_and(not has_function_privilege(r, f, 'execute')) into acl_ok
    from unnest(array['anon', 'authenticated', 'service_role']) r,
         unnest(array['public._factura_moneda_valida(uuid,text,boolean)', 'public.trg_factura_moneda_del_contrato()',
                      'public.trg_contrato_moneda_con_documentos()', 'public._cadena_saldo_en(uuid,text,uuid)',
                      'public._cadena_saldo(uuid,uuid)', 'public._factura_tope_cadena(uuid,uuid,text,numeric,text)']) f;
  out := out || case when acl_ok then 'OK ' else 'MAL ' end || E'privilegios: sin execute para anon/authenticated/service_role\n';
  out := out || case when has_function_privilege('service_role', 'public.factura_vencimiento_emite(uuid,jsonb)', 'execute')
                      and not has_function_privilege('authenticated', 'public.factura_vencimiento_emite(uuid,jsonb)', 'execute')
                      and not has_function_privilege('anon', 'public.factura_vencimiento_emite(uuid,jsonb)', 'execute')
                     then 'OK ' else 'MAL ' end || E'privilegios: factura_vencimiento_emite solo service_role\n';
  -- factura_reactiva: la ACL de siempre (authenticated, que dentro exige super_admin, y service_role), nunca anon
  out := out || case when has_function_privilege('authenticated', 'public.factura_reactiva(uuid)', 'execute')
                      and not has_function_privilege('anon', 'public.factura_reactiva(uuid)', 'execute')
                     then 'OK ' else 'MAL ' end || E'privilegios: factura_reactiva para authenticated, no anon\n';

  raise exception E'RESULTADOS\n%', out;
end $t$;
$p2159_0$;
    v := 'sin raise final';
  exception when others then v := sqlstate || ' ' || sqlerrm;
  end;
  res := res || E'\n== factura_moneda_del_contrato\n' || pg_temp.e2159_resume(v);
  -- facturas_tope_cadena_y_recibi_pendiente (sha256 ac3b0473052d539b)
  begin
    execute $p2159_1$-- Prueba de facturas_tope_cadena_y_recibi_pendiente (5-oct-2026). Se ejecuta DESPUÉS de aplicar la migración, por
-- execute_sql: termina con un raise a propósito, así que no deja rastro (las altas, los recibís y el fichero de
-- prueba en storage se deshacen). Resultado del 5-oct: alta de 30.000 sobre CC00118 bloqueada, alta de 100 pasa,
-- RP00106 (ya excedida) edita sin subir y bloquea al subir, otra moneda y proforma no se tocan, recibí con pendiente
-- + 1 bloqueado, importe 0 bloqueado, privilegios: helpers sin execute para anon/authenticated, contrato_saldo solo
-- para authenticated. Datos de producción de ese día: ajustar los números si cambiaron.
do $t$
declare out text := ''; u record; c1 uuid; c2 uuid; f1 uuid; f2 uuid; soc text; j jsonb; pend numeric; r jsonb;
begin
  select user_id, email into u from public.usuarios where activo and rol='admin' and email like 'p@p%' limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub',u.user_id,'role','authenticated','email',u.email)::text, true);
  out := out || 'es_admin='||public.es_admin()||' es_agente='||public.es_agente()||' puede_fact='||public.puede('facturas')||E'\n';
  select id into c1 from public.contratos where numero='CC00118';
  begin out := out || 'SALDO CC00118: '||left(public.contrato_saldo(c1)::text,420)||E'\n'; exception when others then out := out||'SALDO ERR '||sqlerrm||E'\n'; end;
  select sociedad into soc from public.facturas where numero='INV00184';
  begin
    perform public.factura_guarda(null, jsonb_build_object('tipo','factura','contrato_id',c1,'sociedad',soc,'moneda','EUR','total','30000','fecha_emision','2026-10-05','datos',jsonb_build_object('lineas',jsonb_build_array(jsonb_build_object('descripcion','x','importe','30000')),'fields','{}'::jsonb)));
    out := out||'ALTA 30000: PASO (MAL)'||E'\n';
  exception when others then out := out||'ALTA 30000 bloqueada: '||sqlerrm||E'\n'; end;
  begin
    perform public.factura_guarda(null, jsonb_build_object('tipo','factura','contrato_id',c1,'sociedad',soc,'moneda','EUR','total','100','fecha_emision','2026-10-05','datos',jsonb_build_object('lineas',jsonb_build_array(jsonb_build_object('descripcion','x','importe','100')),'fields','{}'::jsonb)));
    out := out||'ALTA 100: ok'||E'\n';
  exception when others then out := out||'ALTA 100 ERR '||sqlerrm||E'\n'; end;
  select f.id, f.contrato_id into f1, c2 from public.facturas f where f.numero='INV00159';
  begin perform public._factura_tope_cadena(f1, c2, 'EUR', 25000, 'factura'); out := out||'RP00106 sin subir: ok'||E'\n'; exception when others then out := out||'RP00106 sin subir ERR '||sqlerrm||E'\n'; end;
  begin perform public._factura_tope_cadena(f1, c2, 'EUR', 26000, 'factura'); out := out||'RP00106 subiendo: PASO (MAL)'||E'\n'; exception when others then out := out||'RP00106 subiendo bloqueada: '||left(sqlerrm,160)||E'\n'; end;
  begin perform public._factura_tope_cadena(null, c2, 'IDR', 99999999, 'factura'); out := out||'otra moneda: ok'||E'\n'; exception when others then out := out||'otra moneda ERR '||sqlerrm||E'\n'; end;
  begin perform public._factura_tope_cadena(null, c2, 'EUR', 99999999, 'proforma'); out := out||'proforma: ok'||E'\n'; exception when others then out := out||'proforma ERR '||sqlerrm||E'\n'; end;
  insert into storage.objects (bucket_id, name) values ('justificantes','test-5oct/x.pdf');
  select id into f2 from public.facturas where numero='INV00184';
  select total - coalesce((select sum(importe_aplicado) from public.recibi_aplicaciones ra join public.facturas rc on rc.id=ra.recibi_id and not coalesce(rc.anulada,false) where ra.factura_id=f2),0) into pend from public.facturas where id=f2;
  out := out||'pendiente INV00184='||pend||E'\n';
  j := jsonb_build_object('contrato_id',c1,'sociedad',soc,'cliente_nombre','t','proyecto_nombre','t','contrato_numero','CC00118','total',(pend+500)::text,'moneda','EUR','fecha_emision','2026-10-05','justificantes',jsonb_build_array(jsonb_build_object('path','test-5oct/x.pdf')),'datos','{}'::jsonb);
  begin r := public.guardar_recibi(null, j, jsonb_build_array(jsonb_build_object('factura_id',f2,'importe',pend+500))); out := out||'RECIBI pend+500: PASO (MAL)'||E'\n'; exception when others then out := out||'RECIBI pend+500 bloqueado: '||sqlerrm||E'\n'; end;
  begin r := public.guardar_recibi(null, j, jsonb_build_array(jsonb_build_object('factura_id',f2,'importe',0))); out := out||'RECIBI 0: PASO (MAL)'||E'\n'; exception when others then out := out||'RECIBI 0 bloqueado: '||sqlerrm||E'\n'; end;
  begin r := public.guardar_recibi(null, jsonb_set(j, '{total}', to_jsonb(pend::text)), jsonb_build_array(jsonb_build_object('factura_id',f2,'importe',pend))); out := out||'RECIBI pend: ok '||r::text||E'\n'; exception when others then out := out||'RECIBI pend ERR '||sqlerrm||E'\n'; end;
  begin r := public.guardar_recibi(null, j, jsonb_build_array(jsonb_build_object('factura_id',f2,'importe',1))); out := out||'RECIBI 1 sobre cobrada: PASO (MAL)'||E'\n'; exception when others then out := out||'RECIBI 1 sobre cobrada bloqueado: '||sqlerrm||E'\n'; end;
  out := out||'privilegios: tope anon='||has_function_privilege('anon','public._factura_tope_cadena(uuid,uuid,text,numeric,text)','execute')||' auth='||has_function_privilege('authenticated','public._factura_tope_cadena(uuid,uuid,text,numeric,text)','execute')||' cadena auth='||has_function_privilege('authenticated','public._cadena_saldo(uuid,uuid)','execute')||' saldo anon='||has_function_privilege('anon','public.contrato_saldo(uuid)','execute')||' saldo auth='||has_function_privilege('authenticated','public.contrato_saldo(uuid)','execute');
  raise exception E'RESULTADOS\n%', out;
end $t$;$p2159_1$;
    v := 'sin raise final';
  exception when others then v := sqlstate || ' ' || sqlerrm;
  end;
  res := res || E'\n== facturas_tope_cadena_y_recibi_pendiente\n' || pg_temp.e2159_resume(v);
  -- f2_b2_empresas (sha256 a98d61e5bf2faf8f)
  begin
    execute $p2159_2$-- Prueba del bloque 2 (DINERO) de la Fase 2 (8-oct-2026): facturas, recibis, proformas, solicitudes de pago y retenciones, gastos, proveedores, bancos, cuentas de cobro y sociedades por empresa.
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
$p2159_2$;
    v := 'sin raise final';
  exception when others then v := sqlstate || ' ' || sqlerrm;
  end;
  res := res || E'\n== f2_b2_empresas\n' || pg_temp.e2159_resume(v);
  -- 4 · la misma foto DESPUÉS
  begin execute $p2159_3$-- Foto del bloque 2 (DINERO) de la Fase 2 (8-oct-2026): para CADA usuario (los 34 de hoy), con su JWT (email) y `set local role authenticated`,
--   (a) md5 de lo que ve de cada tabla del bloque (gastos, proveedores, bancos_*, categorias, aplicaciones, retenciones, logs, cuentas...),
--   (b) md5 del resultado de cada RPC de lectura del bloque, o el sqlstate si falla,
--   (c) sqlstate de cada RPC de ESCRITURA llamada con ids que no existen (nada se toca; ademas todo acaba en rollback).
-- Por defecto solo imprime el md5; con `set local f2b2.v = '1';` delante imprime tambien la linea de cada usuario (para ver QUIEN cambio).
-- No incluye lo del 2A/2B (eso es f2_foto_ids.sql). El md5 final debe ser IDENTICO antes y despues de cada migracion del bloque.
-- Produccion esta viva: si cambia una fila entre foto y foto, aparece en la linea de ese usuario; se regenera la previa justo antes de aplicar.
-- destructivo-ok: solo lectura y llamadas a ids inexistentes; termina en raise (rollback)
do $t$
declare
  u record; out text := ''; linea text; h text; t text; sql text; i int;
  fantasma constant uuid := '00000000-0000-4000-8000-00000000f2b2';
  tablas constant text[] := array['gastos','gastos_log','proveedores','gasto_categorias','bancos_movimientos','bancos_conciliacion','bancos_perfiles',
                                  'recibi_aplicaciones','solicitudes_pago_retencion','sociedades_log','ajustes_log','solicitudes_cambio','cuentas_bancarias',
                                  'solicitudes_pago','facturas','sociedades'];
  lecturas constant text[] := array[
    'public.gastos_panel_datos()', 'public.panel_bancos_datos()', 'public.bancos_resumen()', 'public.sociedades_ajustes_datos()',
    'public.cuentas_uso()', 'public.cuentas_cobro_visibles()', 'public.sociedades_visibles()',
    format('public.gasto_historial_datos(%L::uuid)', fantasma)];
  escrituras constant text[] := array[
    format('public.factura_borra(%L::uuid)', fantasma),
    format('public.factura_anula(%L::uuid)', fantasma),
    format('public.factura_reactiva(%L::uuid)', fantasma),
    format('public.factura_marca_enviada(%L::uuid)', fantasma),
    format('public.factura_guarda(%L::uuid, %L::jsonb)', fantasma, '{"tipo":"factura","moneda":"EUR","total":"1","sociedad":"tepi_sungai","datos":{"lineas":[{"d":"x","q":1,"p":1}]}}'),
    format('public.guardar_recibi(null::uuid, %L::jsonb, %L::jsonb)', '{"contrato_id":"00000000-0000-4000-8000-00000000f2b2","sociedad":"tepi_sungai"}', '[]'),
    format('public.gasto_guarda(%L::uuid, %L::jsonb)', fantasma, '{"base":"1","sociedad":"tepi_sungai"}'),
    format('public.gasto_anula(%L::uuid, %L)', fantasma, 'x'),
    format('public.gasto_marca_pagado(%L::uuid, current_date, %L)', fantasma, 'x'),
    format('public.gasto_pph_ingresado(%L::uuid, current_date)', fantasma),
    format('public.gasto_anade_justificante(%L::uuid, %L, %L)', fantasma, fantasma || '/x.pdf', 'n'),
    format('public.proveedor_guarda(%L::uuid, %L::jsonb)', fantasma, '{"nombre":"x"}'),
    format('public.solicitud_pago_guarda(%L::uuid, %L::jsonb)', fantasma, '{"importe":1,"concepto":"x"}'),
    format('public.solicitud_pago_resuelve(%L::uuid, %L)', fantasma, 'aprobada'),
    format('public.solicitud_pago_retencion_guarda(%L::uuid, %L::jsonb)', fantasma, '{}'),
    format('public.solicitud_pago_retencion_rectifica(%L::uuid, %L, %L)', fantasma, 'batal', 'x'),
    format('public.bancos_conciliar(%L::uuid, %L::jsonb)', fantasma, '[]'),
    'public.bancos_desconciliar(-1)',
    format('public.bancos_designorar(%L::uuid)', fantasma),
    format('public.bancos_ignorar(%L::uuid, %L)', fantasma, 'x'),
    format('public.bancos_importar(%L, %L, %L::jsonb)', 'cuenta_fantasma', 'f.csv', '[{"fecha":"2026-01-01","importe":1,"moneda":"EUR","huella":"x"}]'),
    format('public.banco_perfil_guarda(%L, %L::jsonb)', 'cuenta_fantasma', '{}'),
    format('public.cuenta_bancaria_guarda(%L, %L::jsonb, false)', 'zzz_fantasma', '{}'),
    format('public.sociedad_guarda(%L, %L::jsonb, false)', 'zzz_fantasma', '{}')];
begin
  for u in select user_id, email from public.usuarios order by email loop
    linea := u.email;
    perform set_config('request.jwt.claims', json_build_object('sub',u.user_id,'role','authenticated','email',u.email)::text, true);
    set local role authenticated;
    foreach t in array tablas loop
      begin
        execute format('select md5(coalesce(string_agg(x::text, '','' order by x::text),'''')) from public.%I x', t) into h;
        linea := linea || '|' || left(h, 5);
      exception when others then linea := linea || '|E' || sqlstate; end;
    end loop;
    foreach sql in array lecturas loop
      begin
        execute format('select md5(coalesce((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from (select * from (select %s) q) x)::text, ''-''))', sql) into h;
        linea := linea || '|' || left(h, 5);
      exception when others then
        begin
          execute format('select md5(%s::text)', sql) into h;
          linea := linea || '|' || left(h, 5);
        exception when others then linea := linea || '|E' || sqlstate; end;
      end;
    end loop;
    foreach sql in array escrituras loop
      begin
        execute format('select %s', sql);
        linea := linea || '|ok';
      exception when others then linea := linea || '|E' || sqlstate; end;
    end loop;
    reset role;
    out := out || linea || E'\n';
  end loop;
  raise exception E'FOTOB2\nMD5=%\n%', md5(out), case when current_setting('f2b2.v', true) = '1' then out else '(lineas por usuario: ejecutar con set local f2b2.v = ''1'' delante)' end;
end $t$;
$p2159_3$; exception when others then despues := sqlstate || ' ' || sqlerrm; end;
  res := res || E'\n== f2_foto_b2: ' || case when antes is null or despues is null then 'SIN FOTO (FALLA)'
         when substring(antes from 'MD5=([0-9a-f]{32})') = substring(despues from 'MD5=([0-9a-f]{32})') then 'MD5 igual antes y despues → ok'
         else 'MD5 DISTINTO antes/despues → FALLA' end;
  -- 5 · flujos críticos (tools/flujos_lawang.py --sql, sha256 13152abb8a05f84d): se leen las filas de _arnes antes de deshacer
  begin
    execute $fl2159$-- destructivo-ok: arnés de flujos críticos (tools/flujos_lawang.py); TODO dentro de una transacción que acaba en ROLLBACK
create temporary table _arnes(caso text, ok boolean, detalle text) on commit drop;
grant all on _arnes to authenticated, anon;
-- guardar_recibi no admite numero explicito: sin esto R3/R5 quemarian numeros REC reales
-- (nextval no se revierte). La funcion y el trigger mueren en el ROLLBACK.
create function public.zz_arnes_num() returns trigger language plpgsql as $f$ begin if new.numero is null then new.numero := 'ZZ-ARNES-N' || left(gen_random_uuid()::text, 8); end if; return new; end $f$;
create trigger trg_00a_zz_arnes_num before insert on public.facturas for each row execute function public.zz_arnes_num();
-- identidades resueltas desde la base, como postgres; solo viajan por GUCs de sesión
select set_config('arnes.admin_sub', u.user_id::text, true), set_config('arnes.admin_email', u.email, true)
  from public.usuarios u where u.activo and u.rol = 'super_admin' order by u.creado_en limit 1;
select set_config('arnes.agente_sub', u.user_id::text, true), set_config('arnes.agente_email', u.email, true),
       set_config('arnes.agente_empresa', coalesce(u.empresas[1], ''), true)
  from public.usuarios u where u.activo and u.rol = 'agente'
   and coalesce(array_length(u.proyectos_supervisados, 1), 0) = 0
  order by ('facturas' = any(u.herramientas)) desc, u.creado_en limit 1;
select set_config('arnes.sociedad', (select clave from public.sociedades order by clave limit 1), true);
-- R1-R5: guardar_recibi exige a quien tiene alcance por empresa la sociedad de la empresa del proyecto
select set_config('arnes.sociedad_r', coalesce((select e.sociedad_clave from public.empresas e
  where e.clave = nullif(current_setting('arnes.agente_empresa'), '')), current_setting('arnes.sociedad')), true);
select set_config('request.jwt.claim.sub', current_setting('arnes.admin_sub'), true),
       set_config('request.jwt.claim.email', current_setting('arnes.admin_email'), true),
       set_config('request.jwt.claims', json_build_object('sub', current_setting('arnes.admin_sub'),
                  'email', current_setting('arnes.admin_email'), 'role', 'authenticated')::text, true);

-- Datos de prueba, como postgres (sin RLS). Números explícitos: no se quema
-- ninguna secuencia real. Todo desaparece en el ROLLBACK final.
do $$
declare v_c uuid; v_c2 uuid; v_c6 uuid; v_cli uuid; v_p uuid; v_u uuid; v_cond uuid; v_tramo uuid;
begin
  -- C1: contrato con factura viva. Los contratos que llevan documentos tienen moneda (IDR, la de sus facturas): desde
  -- LAW-553 (13-oct) un documento solo se guarda en la moneda de su contrato, y un contrato sin moneda no admite ninguno.
  insert into public.contratos (numero, tipo, moneda, datos, creado_por)
    values ('ZZ-ARNES-C1', 'acuerdo_comercial', 'IDR', '{}'::jsonb, current_setting('arnes.admin_email')) returning id into v_c;
  insert into public.facturas (numero, sociedad, tipo, contrato_id, datos, total, moneda, creado_por)
    values ('ZZ-ARNES-F1', current_setting('arnes.sociedad'), 'factura', v_c, '{}'::jsonb, 1, 'IDR', current_setting('arnes.admin_email'));
  perform set_config('arnes.c1', v_c::text, true);

  -- C3: comprador con factura a su nombre
  insert into public.clients (full_name) values ('ZZ ARNES COMPRADOR') returning id into v_cli;
  insert into public.facturas (numero, sociedad, tipo, client_id, datos, total, moneda, creado_por, anulada)
    values ('ZZ-ARNES-F3', current_setting('arnes.sociedad'), 'factura', v_cli, '{}'::jsonb, 1, 'IDR', current_setting('arnes.admin_email'), true);
  perform set_config('arnes.cli', v_cli::text, true);

  -- C4/C5/C7/C8: proyecto con contrato (ajeno para el agente), unidad atada al contrato, vencimiento y firma.
  -- De la empresa del agente: sin ella el contrato ya le queda oculto por empresa nula (F2, 7-oct) y
  -- C7/C8 darian verde aunque faltara la barrera de autoria que prueban (revisor, 10-oct).
  insert into public.proyectos (nombre, empresa) values ('ZZ ARNES PROYECTO', nullif(current_setting('arnes.agente_empresa'), '')) returning id into v_p;
  insert into public.contratos (numero, tipo, datos, creado_por, proyecto_id)
    values ('ZZ-ARNES-C4', 'acuerdo_comercial', '{}'::jsonb, current_setting('arnes.admin_email'), v_p) returning id into v_c2;
  insert into public.unidades (codigo, proyecto, proyecto_id, contrato_id) values ('ZZ-1', 'ZZ ARNES PROYECTO', v_p, v_c2) returning id into v_u;
  update public.contratos set unidad_id = v_u where id = v_c2;
  insert into public.contrato_vencimientos (contrato_id, orden, descripcion, monto) values (v_c2, 1, 'ZZ', 1);
  insert into public.contrato_firmas (contrato_id, token_hash, firmante_rol) values (v_c2, 'zz-arnes-hash', 'comprador');
  perform set_config('arnes.u', v_u::text, true);
  perform set_config('arnes.c4', v_c2::text, true);

  -- C4: un segundo proyecto SOLO con contrato (sin unidad), para que el
  -- pre-check nuevo de contratos sea el que salte y no el viejo de unidades
  insert into public.proyectos (nombre) values ('ZZ ARNES PROYECTO 2') returning id into v_p;
  insert into public.contratos (numero, tipo, datos, creado_por, proyecto_id)
    values ('ZZ-ARNES-C4B', 'acuerdo_comercial', '{}'::jsonb, current_setting('arnes.admin_email'), v_p);

  -- C6: factura ANULADA de un contrato VIVO
  insert into public.contratos (numero, tipo, moneda, datos, creado_por)
    values ('ZZ-ARNES-C6', 'acuerdo_comercial', 'IDR', '{}'::jsonb, current_setting('arnes.admin_email')) returning id into v_c6;
  insert into public.facturas (numero, sociedad, tipo, contrato_id, datos, total, moneda, creado_por, anulada)
    values ('ZZ-ARNES-F6', current_setting('arnes.sociedad'), 'factura', v_c6, '{}'::jsonb, 1, 'IDR', current_setting('arnes.admin_email'), true);

  -- C2: contrato con una comisión de closer ya PAGADA (sin solicitud: el CHECK lo exige para closer)
  insert into public.contratos (numero, tipo, datos, creado_por)
    values ('ZZ-ARNES-C2', 'acuerdo_comercial', '{}'::jsonb, current_setting('arnes.admin_email')) returning id into v_c;
  perform set_config('arnes.c2', v_c::text, true);
  select cc.id, ct.id into v_cond, v_tramo
    from public.condiciones_comision cc join public.condicion_tramos ct on ct.condicion_id = cc.id
   order by cc.id limit 1;
  if v_cond is not null then
    insert into public.comisiones_devengadas (contrato_raiz_id, tramo_id, condicion_id, beneficiario_email, nivel, importe, moneda, estado)
      values (v_c, v_tramo, v_cond, current_setting('arnes.agente_email'), 'closer', 1, 'IDR', 'pagada');
  else
    insert into _arnes values ('D datos de prueba', false, 'no hay condiciones_comision con tramos: C2 no se puede montar');
  end if;

  -- R1-R5 (barrera de guardar_recibi, 27-sep): contrato del super_admin (ajeno para el agente) y
  -- contrato del agente, con el MISMO comprador por email (contratos_mismo_comprador = true), una
  -- factura en cada uno y un justificante en storage. Todo con numero explicito.
  -- Los dos cuelgan de un proyecto de la empresa del agente: desde F2 2A (7-oct) un contrato sin
  -- proyecto no es de ninguna empresa y queda fuera para quien tiene lista de empresas («nace
  -- cerrado»), asi que sin proyecto R3 paraba en la visibilidad y R1/R2/R4 pasaban por la razon equivocada.
  insert into public.proyectos (nombre, empresa) values ('ZZ ARNES PROYECTO R', nullif(current_setting('arnes.agente_empresa'), '')) returning id into v_p;
  insert into public.clients (full_name) values ('ZZ ARNES RECIBI') returning id into v_cli;
  insert into public.contratos (numero, tipo, moneda, datos, creado_por, proyecto_id)
    values ('ZZ-ARNES-RX', 'acuerdo_comercial', 'IDR', '{"fields":{"adq1_email":"zz-arnes@example.invalid"}}'::jsonb, current_setting('arnes.admin_email'), v_p) returning id into v_c;
  perform set_config('arnes.rx', v_c::text, true);
  insert into public.contrato_compradores (contrato_id, client_id, rol) values (v_c, v_cli, 'adquiriente_1');
  insert into public.facturas (numero, sociedad, tipo, contrato_id, datos, total, moneda, creado_por)
    values ('ZZ-ARNES-FRX', current_setting('arnes.sociedad_r'), 'factura', v_c, '{}'::jsonb, 100, 'IDR', current_setting('arnes.admin_email')) returning id into v_u;
  perform set_config('arnes.frx', v_u::text, true);
  insert into public.contratos (numero, tipo, moneda, datos, creado_por, proyecto_id)
    values ('ZZ-ARNES-RA', 'acuerdo_comercial', 'IDR', '{"fields":{"adq1_email":"zz-arnes@example.invalid"}}'::jsonb, current_setting('arnes.agente_email'), v_p) returning id into v_c;
  perform set_config('arnes.ra', v_c::text, true);
  insert into public.contrato_compradores (contrato_id, client_id, rol) values (v_c, v_cli, 'adquiriente_1');
  insert into public.facturas (numero, sociedad, tipo, contrato_id, datos, total, moneda, creado_por)
    values ('ZZ-ARNES-FRA', current_setting('arnes.sociedad_r'), 'factura', v_c, '{}'::jsonb, 100, 'IDR', current_setting('arnes.agente_email')) returning id into v_u;
  perform set_config('arnes.fra', v_u::text, true);
  insert into storage.objects (bucket_id, name) values ('justificantes', 'zz-arnes/justificante.pdf');

  -- R6 (LAW-37, 11-oct): recibi del agente sobre su contrato RA, total 5, ya ENVIADO. Se inserta sin
  -- enviar y se marca despues, como hace la vida real (el alta nunca nace enviada).
  insert into public.facturas (numero, sociedad, tipo, contrato_id, datos, total, moneda, creado_por, justificante_path, justificantes)
    values ('ZZ-ARNES-REC6', current_setting('arnes.sociedad_r'), 'recibi', v_c, '{}'::jsonb, 5, 'IDR', current_setting('arnes.agente_email'),
            'zz-arnes/justificante.pdf', jsonb_build_array(jsonb_build_object('path', 'zz-arnes/justificante.pdf'))) returning id into v_u;
  update public.facturas set enviada = true, fecha_envio = now() where id = v_u;
  perform set_config('arnes.rec6', v_u::text, true);

  -- R7 (LAW-37, 11-oct): factura ANULADA y sin enviar, para factura_marca_enviada
  insert into public.facturas (numero, sociedad, tipo, contrato_id, datos, total, moneda, creado_por, anulada)
    values ('ZZ-ARNES-F7', current_setting('arnes.sociedad'), 'factura', v_c6, '{}'::jsonb, 1, 'IDR', current_setting('arnes.admin_email'), true) returning id into v_u;
  perform set_config('arnes.f7', v_u::text, true);

  insert into _arnes values ('D datos de prueba', true, 'ok');
exception when others then insert into _arnes values ('D datos de prueba', false, sqlstate || ' ' || sqlerrm);
end $$;
-- ── como super_admin autenticado ──
select set_config('request.jwt.claim.sub', current_setting('arnes.admin_sub'), true),
       set_config('request.jwt.claim.email', current_setting('arnes.admin_email'), true),
       set_config('request.jwt.claims', json_build_object('sub', current_setting('arnes.admin_sub'),
                  'email', current_setting('arnes.admin_email'), 'role', 'authenticated')::text, true);
set local role authenticated;

do $$ begin insert into _arnes values ('C0 canario: rol y claims',
          current_user = 'authenticated' and auth.uid() is not null and auth.email() is not null and public.es_super_admin(),
          'current_user=' || current_user || ' uid=' || (auth.uid() is not null)::text || ' super=' || public.es_super_admin()::text);
exception when others then insert into _arnes values ('(reventó)', false, sqlstate || ' ' || sqlerrm); end $$;
do $$ declare r jsonb; v_num text; v_cid uuid; v_an boolean;
        begin
          r := public.borrar_operacion(current_setting('arnes.c1')::uuid);
          select contrato_numero, contrato_id, anulada into v_num, v_cid, v_an from public.facturas where numero = 'ZZ-ARNES-F1';
          insert into _arnes values ('C1 borrar_operacion: contrato fuera, factura anulada con numero congelado',
            not exists (select 1 from public.contratos where numero = 'ZZ-ARNES-C1') and v_an and v_num = 'ZZ-ARNES-C1' and v_cid is null,
            r::text);
exception when others then insert into _arnes values ('(reventó)', false, sqlstate || ' ' || sqlerrm); end $$;
do $$ begin
          perform public.borrar_operacion(current_setting('arnes.c2')::uuid);
          insert into _arnes values ('C2 borrar_operacion con comision pagada DEBE parar', false, 'no paro: borro un contrato con comision pagada');
        exception when others then
          insert into _arnes values ('C2 borrar_operacion con comision pagada DEBE parar',
            sqlerrm like '%comisi%pagada%' and exists (select 1 from public.contratos where numero = 'ZZ-ARNES-C2'),
            sqlstate || ' ' || left(sqlerrm, 90));
          return;
        end; $$;
do $$ begin
          -- desde el 27-sep solo por la edge ficheros-kyc: borrar_comprador_edge como service_role, actuando
          -- como el super admin (la sesión ya no puede ejecutar borrar_comprador directamente)
          set local role service_role;
          perform public.borrar_comprador_edge(current_setting('arnes.admin_sub')::uuid, current_setting('arnes.cli')::uuid);
          set local role authenticated;
          insert into _arnes values ('C3 borrar_comprador con factura DEBE parar con palabras', false, 'no paro');
        exception when others then
          set local role authenticated;
          insert into _arnes values ('C3 borrar_comprador con factura DEBE parar con palabras',
            sqlstate = '23503' and sqlerrm like '%documentos a su nombre%', sqlstate || ' ' || left(sqlerrm, 90));
          return;
        end; $$;
do $$ begin
          perform public.borrar_proyecto('ZZ ARNES PROYECTO 2');
          insert into _arnes values ('C4 borrar_proyecto con contrato DEBE parar con palabras', false, 'no paro');
        exception when others then
          insert into _arnes values ('C4 borrar_proyecto con contrato DEBE parar con palabras',
            sqlstate = '23503' and sqlerrm like '%tiene contratos%', sqlstate || ' ' || left(sqlerrm, 90));
          return;
        end; $$;
do $$ begin
          -- desde el 30-sep la sesión no ejecuta borrar_unidad (revoke; la UI no la llama): el pre-check se prueba como postgres,
          -- con las claims del super admin ya puestas. Arnés actualizado el 7-oct-2026: pedía rol authenticated y estaba en rojo.
          reset role;
          perform public.borrar_unidad(current_setting('arnes.u')::uuid);
          set local role authenticated;
          insert into _arnes values ('C5 borrar_unidad con contrato DEBE parar con palabras', false, 'no paro');
        exception when others then
          set local role authenticated;
          insert into _arnes values ('C5 borrar_unidad con contrato DEBE parar con palabras',
            -- el texto REAL del pre-check: si desapareciera, la FK cruda tambien daria
            -- 23503 con «…on table "contratos"» y un like '%contrato%' lo aprobaria (Datos, 22-sep)
            sqlstate = '23503' and sqlerrm like '%la parcela tiene%contrato(s)%', sqlstate || ' ' || left(sqlerrm, 90));
          return;
        end; $$;
do $$ begin
          update public.facturas set contrato_id = null where numero = 'ZZ-ARNES-F6';
          insert into _arnes values ('C6 factura anulada: desvincular a mano de un contrato vivo DEBE parar', false, 'no paro (o 0 filas)');
        exception when others then
          insert into _arnes values ('C6 factura anulada: desvincular a mano de un contrato vivo DEBE parar',
            sqlstate = '42501', sqlstate || ' ' || left(sqlerrm, 90));
          return;
        end; $$;
do $$ begin
          perform public.guardar_recibi(null, jsonb_build_object('contrato_id', current_setting('arnes.ra'), 'sociedad', current_setting('arnes.sociedad_r'), 'total', '1', 'moneda', 'IDR', 'justificantes', jsonb_build_array(jsonb_build_object('path', 'zz-arnes/justificante.pdf')), 'datos', '{}'::jsonb), jsonb_build_array(jsonb_build_object('factura_id', current_setting('arnes.fra'), 'importe', '1')));
          insert into _arnes values ('R5 guardar_recibi: super_admin sobre contrato ajeno pasa', true, 'paso');
        exception when others then
          insert into _arnes values ('R5 guardar_recibi: super_admin sobre contrato ajeno pasa', false, sqlstate || ' ' || left(sqlerrm, 90));
          return;
        end; $$;
do $$ begin
          perform public.guardar_recibi(current_setting('arnes.rec6')::uuid, jsonb_build_object('contrato_id', current_setting('arnes.ra'), 'sociedad', current_setting('arnes.sociedad_r'), 'total', '1', 'moneda', 'IDR', 'justificantes', jsonb_build_array(jsonb_build_object('path', 'zz-arnes/justificante.pdf')), 'datos', '{}'::jsonb), jsonb_build_array(jsonb_build_object('factura_id', current_setting('arnes.fra'), 'importe', '1')));
          insert into _arnes values ('R6 guardar_recibi: recibi enviado no se edita (super admin)', false, 'ENTRO: edito un recibi enviado');
        exception when others then
          insert into _arnes values ('R6 guardar_recibi: recibi enviado no se edita (super admin)',
            sqlstate = '23514' and sqlerrm like '%ya se envió al cliente: no se edita%'
            and exists (select 1 from public.facturas where id = current_setting('arnes.rec6')::uuid and total = 5 and enviada),
            sqlstate || ' ' || left(sqlerrm, 90));
          return;
        end; $$;
do $$ begin
          perform public.factura_marca_enviada(current_setting('arnes.f7')::uuid);
          insert into _arnes values ('R7 factura_marca_enviada: un documento anulado no se marca enviado', false, 'ENTRO: marco un anulado');
        exception when others then
          insert into _arnes values ('R7 factura_marca_enviada: un documento anulado no se marca enviado',
            sqlstate = '42501' and sqlerrm like '%está anulado: no se marca como enviado%'
            and exists (select 1 from public.facturas where id = current_setting('arnes.f7')::uuid and not coalesce(enviada, false)),
            sqlstate || ' ' || left(sqlerrm, 90));
          return;
        end; $$;
do $$ declare f text; d text := ''; n int := 0;
        begin
          foreach f in array array[
            'select public.investor_deck_activa_como(gen_random_uuid(), gen_random_uuid(), true)',
            'select public.deck_transicion_empieza(gen_random_uuid(), gen_random_uuid(), true)',
            'select public.deck_transicion_termina(gen_random_uuid())',
            'select count(*) from public.deck_fotos_desajustes()',
            'select count(*) from public.deck_fotos_ubicacion(gen_random_uuid(), array[]::uuid[])',
            'select public.deck_bucket_debido(''modelo'', gen_random_uuid())',
            'select count(*) from public.deck_transiciones',
            'select public.cron_deck_sincroniza_secret()'] loop          -- S6 (10-oct): el secreto del cron, solo service_role
            begin
              execute f; d := d || 'ENTRO:' || left(f, 40) || ' ';
            exception when insufficient_privilege then n := n + 1;
            when others then d := d || sqlstate || ':' || left(f, 40) || ' ';
            end;
          end loop;
          insert into _arnes values ('D1 deck (AXW-66): ni un super_admin llama a las funciones nuevas del deck desde su sesión', n = 8, coalesce(nullif(d, ''), '8/8 permission denied'));
exception when others then insert into _arnes values ('(reventó)', false, sqlstate || ' ' || sqlerrm); end $$;
reset role;
-- ── como agente raso autenticado ──
select set_config('request.jwt.claim.sub', current_setting('arnes.agente_sub'), true),
       set_config('request.jwt.claim.email', current_setting('arnes.agente_email'), true),
       set_config('request.jwt.claims', json_build_object('sub', current_setting('arnes.agente_sub'),
                  'email', current_setting('arnes.agente_email'), 'role', 'authenticated')::text, true);
set local role authenticated;

do $$ declare ok_vieja boolean := false; ok_nueva boolean := false; d text := '';
        begin
          begin
            perform public.investor_deck_activar('ZZ ARNES PROYECTO', true); d := d || 'vieja:ENTRO ';
          exception when undefined_function then ok_vieja := true; d := d || 'vieja:no existe ';
          when others then d := d || 'vieja:' || sqlstate || ' ';
          end;
          begin
            perform public.investor_deck_activa_como(auth.uid(), gen_random_uuid(), true); d := d || 'nueva:ENTRO ';
          exception when insufficient_privilege then ok_nueva := true;
          when others then d := d || 'nueva:' || sqlstate || ' ';
          end;
          insert into _arnes values ('D2 deck (AXW-66): agente raso no abre un deck ni por la función vieja ni por la nueva', ok_vieja and ok_nueva, d);
exception when others then insert into _arnes values ('(reventó)', false, sqlstate || ' ' || sqlerrm); end $$;
do $$ declare ids uuid[]; n_fn int; n_rls int;
        begin
          execute 'reset role';
          select array_agg(id) into ids from (select id from public.deck_fotos order by id limit 200) s;
          select count(*) into n_fn from public.deck_fotos_ubicacion(current_setting('arnes.agente_sub')::uuid, ids);
          perform set_config('request.jwt.claims', json_build_object('sub', current_setting('arnes.agente_sub'),
                  'email', current_setting('arnes.agente_email'), 'role', 'authenticated')::text, true);
          execute 'set local role authenticated';
          select count(*) into n_rls from public.deck_fotos where id = any(ids);
          insert into _arnes values ('D4 deck (AXW-66): la edge no enseña más fotos que la RLS de deck_fotos',
            n_fn = n_rls, format('funcion %s, rls %s', n_fn, n_rls));
exception when others then insert into _arnes values ('(reventó)', false, sqlstate || ' ' || sqlerrm); end $$;
do $$ declare nv int; nf int; nu int; nc int;
        begin
          select count(*) into nc from public.contratos where numero = 'ZZ-ARNES-C4';
          select count(*) into nv from public.contrato_vencimientos where contrato_id = current_setting('arnes.c4')::uuid;
          select count(*) into nf from public.contrato_firmas where contrato_id = current_setting('arnes.c4')::uuid;
          begin
            update public.contrato_vencimientos set nota = 'zz' where contrato_id = current_setting('arnes.c4')::uuid;
            get diagnostics nu = row_count;
          exception when insufficient_privilege then nu := 0;   -- desde el 26-sep la sesión no escribe vencimientos
          end;
          insert into _arnes values ('C7 agente raso no ve ni edita vencimientos/firmas de un contrato ajeno',
            nc = 0 and nv = 0 and nf = 0 and nu = 0, format('ve %s contratos, %s venc, %s firmas, edita %s', nc, nv, nf, nu));
exception when others then insert into _arnes values ('(reventó)', false, sqlstate || ' ' || sqlerrm); end $$;
do $$ begin
          perform public.borrar_operacion(current_setting('arnes.c4')::uuid);
          insert into _arnes values ('C8 agente raso no borra una operacion ajena', false, 'no paro');
        exception when others then
          -- paró: aprueba solo si es uno de los RAISE propios de borrar_operacion (la RLS
          -- le esconde el contrato, así que no puede comprobar desde aquí que sigue
          -- existiendo; lo hace C7 por él). Un fallo crudo (FK, permiso de tabla) NO aprueba.
          insert into _arnes values ('C8 agente raso no borra una operacion ajena',
            -- sin «esa operacion no existe»: el contrato es de la empresa del agente, solo la autoria lo para (10-oct)
            sqlerrm like '%no autorizado%' or sqlerrm like '%solo la puede borrar un super admin%',
            sqlstate || ' ' || left(sqlerrm, 90));
          return;
        end; $$;
do $$ begin
          perform public.guardar_recibi(null, jsonb_build_object('contrato_id', current_setting('arnes.rx'), 'sociedad', current_setting('arnes.sociedad_r'), 'total', '1', 'moneda', 'IDR', 'justificantes', jsonb_build_array(jsonb_build_object('path', 'zz-arnes/justificante.pdf')), 'datos', '{}'::jsonb), jsonb_build_array(jsonb_build_object('factura_id', current_setting('arnes.frx'), 'importe', '1')));
          insert into _arnes values ('R1 guardar_recibi: agente sobre contrato ajeno DEBE parar', false, 'ENTRO: la barrera no paro');
        exception when others then
          insert into _arnes values ('R1 guardar_recibi: agente sobre contrato ajeno DEBE parar',
            sqlstate = '42501' and sqlerrm like '%contrato que no ves%', sqlstate || ' ' || left(sqlerrm, 90));
          return;
        end; $$;
do $$ begin
          perform public.guardar_recibi(null, jsonb_build_object('contrato_id', current_setting('arnes.ra'), 'sociedad', current_setting('arnes.sociedad_r'), 'total', '1', 'moneda', 'IDR', 'justificantes', jsonb_build_array(jsonb_build_object('path', 'zz-arnes/justificante.pdf')), 'datos', '{}'::jsonb), jsonb_build_array(jsonb_build_object('factura_id', current_setting('arnes.frx'), 'importe', '1')));
          insert into _arnes values ('R2 guardar_recibi: contrato propio aplicado a factura ajena DEBE parar', false, 'ENTRO: la barrera no paro');
        exception when others then
          insert into _arnes values ('R2 guardar_recibi: contrato propio aplicado a factura ajena DEBE parar',
            sqlstate = '42501' and sqlerrm like '%no es un documento que veas%', sqlstate || ' ' || left(sqlerrm, 90));
          return;
        end; $$;
do $$ begin
          perform set_config('arnes.r3', (public.guardar_recibi(null, jsonb_build_object('contrato_id', current_setting('arnes.ra'), 'sociedad', current_setting('arnes.sociedad_r'), 'total', '1', 'moneda', 'IDR', 'justificantes', jsonb_build_array(jsonb_build_object('path', 'zz-arnes/justificante.pdf')), 'datos', '{}'::jsonb), jsonb_build_array(jsonb_build_object('factura_id', current_setting('arnes.fra'), 'importe', '1'))))->>'id', true);
          insert into _arnes values ('R3 guardar_recibi: recibi propio pasa', true, 'paso');
        exception when others then
          insert into _arnes values ('R3 guardar_recibi: recibi propio pasa', false, sqlstate || ' ' || left(sqlerrm, 90));
          return;
        end; $$;
do $$ begin
          if nullif(current_setting('arnes.r3', true), '') is null then
            insert into _arnes values ('R4 guardar_recibi: editar el propio moviendolo a contrato ajeno DEBE parar', false, 'R3 no dejo recibi: sin el, R4 es un alta y no prueba el UPDATE');
            return;
          end if;
          perform public.guardar_recibi(nullif(current_setting('arnes.r3', true), '')::uuid, jsonb_build_object('contrato_id', current_setting('arnes.rx'), 'sociedad', current_setting('arnes.sociedad_r'), 'total', '1', 'moneda', 'IDR', 'justificantes', jsonb_build_array(jsonb_build_object('path', 'zz-arnes/justificante.pdf')), 'datos', '{}'::jsonb), jsonb_build_array(jsonb_build_object('factura_id', current_setting('arnes.fra'), 'importe', '1')));
          insert into _arnes values ('R4 guardar_recibi: editar el propio moviendolo a contrato ajeno DEBE parar', false, 'ENTRO: la barrera no paro');
        exception when others then
          insert into _arnes values ('R4 guardar_recibi: editar el propio moviendolo a contrato ajeno DEBE parar',
            sqlstate = '42501' and sqlerrm like '%contrato que no ves%', sqlstate || ' ' || left(sqlerrm, 90));
          return;
        end; $$;
do $$ begin
          perform public.guardar_recibi(current_setting('arnes.rec6')::uuid, jsonb_build_object('contrato_id', current_setting('arnes.ra'), 'sociedad', current_setting('arnes.sociedad_r'), 'total', '1', 'moneda', 'IDR', 'justificantes', jsonb_build_array(jsonb_build_object('path', 'zz-arnes/justificante.pdf')), 'datos', '{}'::jsonb), jsonb_build_array(jsonb_build_object('factura_id', current_setting('arnes.fra'), 'importe', '1')));
          insert into _arnes values ('R6 guardar_recibi: recibi enviado no se edita (agente autor)', false, 'ENTRO: edito un recibi enviado');
        exception when others then
          insert into _arnes values ('R6 guardar_recibi: recibi enviado no se edita (agente autor)',
            sqlstate = '23514' and sqlerrm like '%ya se envió al cliente: no se edita%'
            and exists (select 1 from public.facturas where id = current_setting('arnes.rec6')::uuid and total = 5 and enviada),
            sqlstate || ' ' || left(sqlerrm, 90));
          return;
        end; $$;
reset role;
-- ── como anónimo ──
set local role anon;
do $$ declare ok_lead boolean := false; ok_clients boolean := false; ok_contratos boolean := false; d text := '';
        begin
          begin
            insert into public.leads (name, email, source) values ('ZZ ARNES', 'zz-arnes@example.invalid', 'arnes');
            d := d || 'lead:ENTRO ';
          exception when insufficient_privilege then ok_lead := true;
          when others then d := d || 'lead:' || sqlstate || ' '; end;
          begin
            perform 1 from public.clients limit 1; d := d || 'clients:leyo ';
          exception when insufficient_privilege then ok_clients := true;
          when others then d := d || 'clients:' || sqlstate || ' '; end;
          begin
            perform 1 from public.contratos limit 1; d := d || 'contratos:leyo ';
          exception when insufficient_privilege then ok_contratos := true;
          when others then d := d || 'contratos:' || sqlstate || ' '; end;
          insert into _arnes values ('C9 anon: no inserta leads (LAW-385) ni lee nada', ok_lead and ok_clients and ok_contratos, coalesce(nullif(d, ''), 'ok'));
exception when others then insert into _arnes values ('(reventó)', false, sqlstate || ' ' || sqlerrm); end $$;
do $$ declare n int := 0; d text := '';
        begin
          begin perform public.investor_deck_activar('ZZ ARNES PROYECTO', true); d := d || 'vieja:ENTRO ';
          exception when undefined_function then n := n + 1; when others then d := d || 'vieja:' || sqlstate || ' '; end;   -- retirada en S4b
          begin perform public.investor_deck_activa_como(gen_random_uuid(), gen_random_uuid(), true); d := d || 'nueva:ENTRO ';
          exception when insufficient_privilege then n := n + 1; when others then d := d || 'nueva:' || sqlstate || ' '; end;
          begin perform public.cron_deck_sincroniza_secret(); d := d || 'secreto_cron:ENTRO ';                              -- S6 (10-oct)
          exception when insufficient_privilege then n := n + 1; when others then d := d || 'secreto_cron:' || sqlstate || ' '; end;
          insert into _arnes values ('D3 deck (AXW-66): anon no ejecuta ni la función vieja ni la nueva de abrir un deck', n = 3, coalesce(nullif(d, ''), 'vieja no existe, nueva y secreto del cron permission denied'));
exception when others then insert into _arnes values ('(reventó)', false, sqlstate || ' ' || sqlerrm); end $$;
reset role;
-- ── como service_role (el camino de las edges) ──
select set_config('request.jwt.claim.sub', current_setting('arnes.admin_sub'), true),
       set_config('request.jwt.claim.email', current_setting('arnes.admin_email'), true),
       set_config('request.jwt.claims', json_build_object('sub', current_setting('arnes.admin_sub'),
                  'email', current_setting('arnes.admin_email'), 'role', 'authenticated')::text, true);

do $$ declare v_p uuid; v_admin uuid := current_setting('arnes.admin_sub')::uuid; v_mail text := current_setting('arnes.admin_email');
                v_abierto boolean; v_2a text := 'no probada'; v_sin text := 'no probada'; v_reves text := 'no probada'; v_alta int; v_baja int; v_des int; v_marcas int; ok boolean;
        begin
          execute 'reset role';
          select id into v_p from public.proyectos where nombre = 'ZZ ARNES PROYECTO';
          execute 'set local role service_role';
          begin perform public.investor_deck_activa_como(v_admin, v_p, true); v_sin := 'ENTRO';          -- sin marca: no abre
          exception when sqlstate '55000' then v_sin := '55000'; when others then v_sin := sqlstate; end;
          perform public.deck_transicion_empieza(v_admin, v_p, true);
          begin perform public.deck_transicion_empieza(v_admin, v_p, true); v_2a := 'ENTRO';
          exception when sqlstate '55P03' then v_2a := '55P03'; when others then v_2a := sqlstate; end;
          perform public.investor_deck_activa_como(v_admin, v_p, true);
          perform public.deck_transicion_termina(v_p);
          execute 'reset role';
          select bool_and(publicado_investor_deck) into v_abierto from public.unidades where proyecto_id = v_p;
          execute 'set local role service_role';
          perform public.deck_transicion_empieza(v_admin, v_p, false);
          begin perform public.investor_deck_activa_como(v_admin, v_p, true); v_reves := 'ENTRO';         -- marca de cerrar, pide abrir
          exception when sqlstate '55000' then v_reves := '55000'; when others then v_reves := sqlstate; end;
          perform public.investor_deck_activa_como(v_admin, v_p, false);
          perform public.deck_transicion_termina(v_p);
          select count(*) into v_des from public.deck_fotos_desajustes(v_p);
          execute 'reset role';
          select count(*) filter (where accion = 'alta' and quien = v_mail), count(*) filter (where accion = 'baja' and quien = v_mail)
            into v_alta, v_baja from public.deck_publicaciones where tabla = 'investor_deck_activacion' and fila_id = v_p;
          select count(*) into v_marcas from public.deck_transiciones where proyecto_id = v_p;
          ok := v_abierto and v_2a = '55P03' and v_sin = '55000' and v_reves = '55000' and v_alta = 1 and v_baja = 1 and v_des = 0 and v_marcas = 0
                and not exists (select 1 from public.unidades where proyecto_id = v_p and publicado_investor_deck);
          insert into _arnes values ('D5 deck (AXW-66): la secuencia de deck_activa en SQL deja alta, baja y marca libre; sin marca o con la marca al reves no abre',
            ok, format('sin_marca=%s abierto=%s 2a_marca=%s marca_al_reves=%s alta=%s baja=%s desajustes=%s marcas=%s', v_sin, v_abierto, v_2a, v_reves, v_alta, v_baja, v_des, v_marcas));
exception when others then insert into _arnes values ('(reventó)', false, sqlstate || ' ' || sqlerrm); end $$;
reset role;
$fl2159$;
    execute $q$select count(*) filter (where ok), count(*), coalesce(string_agg(caso || ' → FALLA ' || coalesce(detalle, ''), E'\n' order by caso)
                filter (where not ok), '') from _arnes$q$ into n_ok, n_tot, v;
    res := res || E'\n== flujos_lawang ' || n_ok || '/' || n_tot || case when n_ok = n_tot then ' → ok' else E'\n' || v end;
    raise exception 'deshaz_flujos';
  exception when others then
    if sqlerrm <> 'deshaz_flujos' then res := res || E'\n== flujos_lawang: ' || pg_temp.e2159_resume(sqlstate || ' ' || sqlerrm); end if;
  end;
  raise exception E'RES 2159%', res;
end $ens2159$;
