/* node plantillas_motor.test.js — el MOTOR de plantillas de envia-correo (S5.2), con el index.ts REAL, sin red y sin enviar nada.
   Idéntico en Lawang y en el maestro (erp/test_canon_envia_correo.py lo comprueba). No depende del texto de cada cliente: lo que se
   espera sale de componeCorreo(textoFabrica(clave), …) con las variables escritas a mano aquí, y se compara con lo que SALE de
   la edge por el camino libre (subject/message) — la misma salida, byte a byte, por los dos caminos. La comparación contra el texto
   que componían los llamantes de Lawang es plantillas_dorada.test.js.
   Cubre lo que pedía la revisión previa #191: clave fuera de la lista → 400; texto inactivo/inválido/ilegible/tabla ausente → fábrica
   y nunca 500; los datos salen de la base, no del llamante (vars solo de las editables); doble escape; sin vía de aviso; sin envío
   si la base no responde; {plantilla, version} en la respuesta y en el log; el camino libre sigue igual. */
const assert = require('assert');
const path = require('path');

(async () => {
  const A = await import('./arnes.mjs');
  const P = await import('./plantillas_arnes.mjs');
  const V = await import('./valida.ts');
  const F = await import('./plantillas_fabrica.ts');
  const CAT = P.catalogosSellados();
  const CLAVES = Object.keys(V.PLANTILLAS).filter((k) => !P.SOLO_LAWANG.includes(k));   // las de una sola instancia tienen su propia prueba
  assert.deepStrictEqual(Object.keys(CAT).sort(), [...CLAVES].sort(), 'la migración siembra exactamente las claves de valida.ts → PLANTILLAS');
  const PORTAL = 'https://erp.ejemplo.com/portal/';
  const ENLACE = 'https://ejemplo.com/contracts/firmar.html?t=tok.abc-1';
  const PDF = Buffer.from('%PDF-1.7 falso').toString('base64');
  const HOLA = (n) => 'Hola' + (n ? ' ' + n : '');

  let comprobaciones = 0;
  const ok = (cond, msg) => { assert.ok(cond, msg); comprobaciones++; };
  const igual = (a, b, msg) => { assert.deepStrictEqual(a, b, msg); comprobaciones++; };

  async function corre(db, cuerpo, { cabeceras = P.SERVICIO, env = {}, config, extra = {} } = {}) {
    P.entorno(db, { env, ...(config ? { config } : {}), ...extra });
    const m = await A.cargaEdge(__dirname);
    const res = await A.llama(m, { cabeceras, cuerpo });
    return { res, correos: A.estado.correo.correos, log: A.lineaJson(res) };
  }

  // Lo que cada clave debe producir con la base falsa de partida (variables escritas a mano, no calculadas por el código bajo prueba)
  // Claves que ESTA instancia no ofrece (su esquema no tiene los datos): `resuelve` contesta 400 «no disponible» SIN consultar nada.
  const NO_DISP = [];
  for (const k of CLAVES) {
    const r = await F.resuelve(k, { contrato_id: P.ID.contrato, factura_id: P.ID.factura, firma_id: P.ID.firma }, 'x@y.test', {},
      async () => { throw new Error('no debe consultar'); }, { marca: 'Acme', portal: 'https://erp.ejemplo.com/portal/', dominio: 'ejemplo.com' }).catch(() => null);
    if (r && V.esFallo(r) && /no está disponible en esta instancia/.test(r.error)) NO_DISP.push(k);
  }
  const DISP = CLAVES.filter((k) => !NO_DISP.includes(k));
  const CASOS = {
    enlace_firma_cadena: { to: 'ana@cliente.test', attach: false, ids: { contrato_id: P.ID.contrato, firma_id: P.ID.firma },
      vars: { saludo: HOLA('Ana'), numero: 'CR00123', enlace: ENLACE, marca: 'Acme' }, variante: 'principal' },
    copia_firmada_comprador: { to: 'dora@cliente.test', attach: true, ids: { contrato_id: P.ID.contrato }, enviadas: { nombre: 'Dora Mar' },
      vars: { saludo: HOLA('Dora'), numero: 'CR00123', contrato_proyecto: 'CR00123 (Palm Field)', portal: PORTAL, marca: 'Acme' }, variante: 'principal' },
    copia_firmada_portal: { to: 'dora@cliente.test', attach: false, ids: { contrato_id: P.ID.contrato }, enviadas: { nombre: 'Dora Mar' },
      vars: { saludo: HOLA('Dora'), numero: 'CR00123', contrato_proyecto: 'CR00123 (Palm Field)', portal: PORTAL, marca: 'Acme' }, variante: 'principal' },
    copia_firmada_manual: { to: 'dora@cliente.test', attach: true, ids: { contrato_id: P.ID.contrato }, enviadas: { nombre: 'Dora Mar' },
      vars: { saludo: HOLA('Dora'), numero: 'CR00123', contrato_proyecto: 'CR00123 (Palm Field)', portal: PORTAL, marca: 'Acme' }, variante: 'principal' },
    aviso_anulacion: { to: 'beto@cliente.test', attach: false, ids: { contrato_id: P.ID.contrato },
      vars: { saludo: HOLA('Beto'), numero: 'CR00123', bloque_motivo: 'Motivo: Cambia la cláusula 4\n\n', marca: 'Acme' }, variante: 'alt' },
    factura_primer_hito: { to: 'eva@cliente.test', attach: true, ids: { factura_id: P.ID.factura }, enviadas: { nombre: 'Eva Sol' },
      vars: { saludo: HOLA('Eva'), factura: 'INV-2026-0007', numero: 'CR00123', concepto: 'Primer pago (30% del precio acordado) — a la firma', fecha: '2026-11-15', importe: '12.500,50 EUR', marca: 'Acme' }, variante: 'principal' },
    proforma_total: { to: 'eva@cliente.test', attach: true, ids: { factura_id: P.ID.proforma }, enviadas: { nombre: 'Eva Sol' },
      vars: { saludo: HOLA('Eva'), factura: 'PRO-2026-0003', numero: 'CR00123', concepto: 'Total del proyecto', fecha: '', importe: '41.668,33 EUR', marca: 'Acme' }, variante: 'principal' },
    factura_vencimiento: { to: 'eva@cliente.test', attach: true, ids: { factura_id: P.ID.factura }, enviadas: { nombre: 'Eva Sol' },
      vars: { saludo: HOLA('Eva'), factura: 'INV-2026-0007', numero: 'CR00123', concepto: 'Primer pago (30% del precio acordado) — a la firma', fecha: '2026-11-15', importe: '12.500,50 EUR', marca: 'Acme' }, variante: 'principal' },
  };
  assert.deepStrictEqual(Object.keys(CASOS).sort(), [...CLAVES].sort(), 'un caso por clave');
  const porPlantilla = (k, c = CASOS[k], extra = {}) => ({
    plantilla: k, to: c.to, attach: c.attach, ...(c.attach ? { pdf_base64: PDF, filename: 'doc.pdf' } : {}), ...c.ids, ...(c.enviadas ? { vars: c.enviadas } : {}), ...extra,
  });
  const libre = (c, texto) => ({ to: c.to, attach: c.attach, ...(c.attach ? { pdf_base64: PDF, filename: 'doc.pdf' } : {}), subject: texto.subject, message: texto.message });
  const esperado = (k, c = CASOS[k], t = F.textoFabrica(k)) => V.componeCorreo(t, c.variante, c.vars);

  // ── 1. Cada clave: lo que sale por plantilla == lo que sale por el camino libre con el mismo texto ───────────────────────────
  for (const k of DISP) {
    const c = CASOS[k], esp = esperado(k);
    ok(esp && esp.subject && esp.message, k + ': el texto de fábrica compone con las variables del caso');
    const a = await corre(P.baseFalsa(), porPlantilla(k));
    igual(a.res.status, 200, k + ': 200 · ' + a.res.crudo);
    ok(a.res.cuerpo.ok === true && a.res.cuerpo.plantilla === k && /^f:[0-9a-f]{8}$/.test(a.res.cuerpo.version), k + ': devuelve {plantilla, version de fábrica}: ' + a.res.crudo);
    igual(a.correos.length, 1, k + ': un correo');
    ok(a.log && a.log.plantilla === k && a.log.version === a.res.cuerpo.version && a.log.dominio_destino === 'cliente.test', k + ': el log lleva clave y versión');
    ok(!JSON.stringify(a.res.logs).includes(c.to) && !JSON.stringify(a.res.logs).includes('Dora') && !JSON.stringify(a.res.logs).includes('CR00123'), k + ': el log no lleva dirección, nombre ni número');
    const b = await corre(P.baseFalsa(), libre(c, esp));
    igual(b.res.status, 200, k + ' (libre): ' + b.res.crudo);
    ok(b.res.cuerpo.plantilla === undefined, k + ': el camino libre no devuelve plantilla');
    igual(P.normaliza(a.correos[0]), P.normaliza(b.correos[0]), k + ': mismo asunto, texto y HTML por plantilla que por el camino libre');
  }
  // el botón: el del enlace de firma lo pone el servidor desde contrato_firmas; el resto, el portal
  const f1 = await corre(P.baseFalsa(), porPlantilla('enlace_firma_cadena'));
  ok(f1.correos[0].html.includes('href="' + ENLACE + '"') && f1.correos[0].html.includes('Firmar el documento'), 'el botón de la cadena lleva el enlace leído de la base');
  const f2 = await corre(P.baseFalsa(), porPlantilla('copia_firmada_portal'));
  ok(f2.correos[0].html.includes('href="' + PORTAL + '"') && f2.correos[0].html.includes('Entrar'), 'las demás llevan el botón del portal');
  // la clave de servicio solo se manda a la base
  for (const l of A.estado.llamadas) ok(l.url.startsWith('https://ref.supabase.co/'), 'ninguna llamada sale fuera de Supabase: ' + l.url);

  // ── 2. Una fila ACTIVA y válida manda sobre la fábrica; si falla algo, vuelve la fábrica (nunca un 500) ──────────────────────
  const K = 'copia_firmada_portal', C = CASOS[K];
  const propio = { asunto: 'Copia {{numero}} de {{marca}}', cuerpo: '{{saludo}}: tu copia {{contrato_proyecto}} está en {{portal}}. Texto del cliente.', cuerpo_alt: null };
  const conFila = (extra = {}) => { const db = P.baseFalsa(); db.correo_plantillas = [P.filaActiva(K, CAT[K], { ...propio, ...extra })]; return db; };
  const r1 = await corre(conFila(), porPlantilla(K));
  igual(r1.res.status, 200, 'fila activa · ' + r1.res.crudo);
  igual(r1.res.cuerpo.version, 'v3', 'la versión de una fila editada es v<n>');
  const esp1 = V.componeCorreo(propio, 'principal', C.vars);
  igual(P.normaliza(r1.correos[0]), P.normaliza((await corre(P.baseFalsa(), libre(C, esp1))).correos[0]), 'el texto del cliente sale tal cual');
  ok(esp1.message.includes('Texto del cliente'), 'y es el suyo, no el de fábrica');
  // PRUEBA DE QUE LA COMPARACIÓN DISCRIMINA: con otro texto la salida NO es la de fábrica (si esto pasara, la dorada no mediría nada)
  assert.notDeepStrictEqual(P.normaliza(r1.correos[0]), P.normaliza((await corre(P.baseFalsa(), libre(C, esperado(K)))).correos[0])); comprobaciones++;

  const casosFabrica = {
    'fila inactiva': conFila({ activa: false }),
    'texto con URL': conFila({ cuerpo: '{{saludo}}: {{contrato_proyecto}} {{portal}} https://malo.example' }),
    'texto con HTML': conFila({ cuerpo: '{{saludo}}: <b>{{contrato_proyecto}}</b> {{portal}}' }),
    'falta una obligatoria': conFila({ asunto: 'Sin número' }),
    'variable que no existe': conFila({ cuerpo: '{{saludo}}: {{contrato_proyecto}} {{portal}} {{importe}}' }),
    'llave suelta': conFila({ cuerpo: '{{saludo}}: {{contrato_proyecto}} {{portal}} }' }),
    'asunto con salto de línea': conFila({ asunto: 'Copia\n{{numero}}' }),
    'versión que no es número': conFila({ version: '3' }),
    'catálogo ilegible': (() => { const db = conFila(); db.correo_plantillas[0].variables = { permitidas: 'no' }; return db; })(),
    'cuerpo vacío': conFila({ cuerpo: '   ' }),
    'tabla ausente (404)': (() => { const db = P.baseFalsa(); db.fallos.correo_plantillas = 404; return db; })(),
    'base caída (500)': (() => { const db = P.baseFalsa(); db.fallos.correo_plantillas = 500; return db; })(),
    'red caída (excepción)': (() => { const db = P.baseFalsa(); db.lanza.correo_plantillas = true; return db; })(),
  };
  const deFabrica = P.normaliza((await corre(P.baseFalsa(), libre(C, esperado(K)))).correos[0]);
  for (const [nombre, db] of Object.entries(casosFabrica)) {
    const r = await corre(db, porPlantilla(K));
    igual(r.res.status, 200, nombre + ' → 200 con el texto de fábrica · ' + r.res.crudo);
    ok(/^f:[0-9a-f]{8}$/.test(r.res.cuerpo.version), nombre + ' → versión de fábrica');
    igual(P.normaliza(r.correos[0]), deFabrica, nombre + ' → sale EXACTAMENTE el texto de fábrica');
  }
  for (const k of NO_DISP) {   // lo no disponible: 400 explícito, sin correo y sin consultar la base
    const db = P.baseFalsa(); const r = await corre(db, porPlantilla(k));
    ok(r.res.status === 400 && /no está disponible/.test(r.res.cuerpo.error) && r.correos.length === 0 && db.lecturas.every((l) => !/contrato_firmas/.test(l)), k + ': no disponible → 400 · ' + r.res.crudo);
  }
  if (!NO_DISP.includes('aviso_anulacion')) {   // aviso_anulacion: dos cuerpos; si el catálogo pide cuerpo_alt y la fila no lo trae, fábrica
  {
    const k = 'aviso_anulacion', c = CASOS[k], db = P.baseFalsa();
    db.correo_plantillas = [P.filaActiva(k, CAT[k], { asunto: 'Cambio de {{numero}}', cuerpo: '{{saludo}}: cambia {{numero}}.', cuerpo_alt: null })];
    const r = await corre(db, porPlantilla(k));
    igual(r.res.status, 200); ok(/^f:/.test(r.res.cuerpo.version), 'aviso sin cuerpo_alt → fábrica');
    db.correo_plantillas = [P.filaActiva(k, CAT[k], { asunto: 'Cambio de {{numero}}', cuerpo: '{{saludo}}: cambia {{numero}}.', cuerpo_alt: '{{saludo}}: firmaste y cambia {{numero}}.\n{{bloque_motivo}}Gracias.' })];
    const r2 = await corre(db, porPlantilla(k));
    ok(r2.res.cuerpo.version === 'v3' && r2.correos[0].text.includes('firmaste y cambia CR00123') && r2.correos[0].text.includes('Motivo: Cambia la cláusula 4'), 'aviso con dos cuerpos: sale el de quien ya firmó, con su motivo');
    const r3 = await corre(db, porPlantilla(k, { ...c, to: 'carla@cliente.test' }));
    ok(r3.correos[0].text.includes('cambia CR00123.') && !r3.correos[0].text.includes('firmaste'), 'quien no había firmado recibe el cuerpo principal');
  }
  }

  // ── 3. Doble escape y un valor no se vuelve a expandir ────────────────────────────────────────────────────────────────────────
  {
    const db = P.baseFalsa();
    db.contratos[0].numero = 'CR&1 <b>';
    const r = await corre(db, porPlantilla('copia_firmada_comprador', CASOS.copia_firmada_comprador, { vars: { nombre: '{{numero}}<i>' } }));
    igual(r.res.status, 200, r.res.crudo);
    const m = r.correos[0];
    ok(m.subject === 'Tu contrato firmado · CR&1 <b>' || m.subject.includes('CR&1 <b>'), 'el asunto va SIN escape HTML: ' + m.subject);
    ok(m.html.includes('CR&amp;1 &lt;b&gt;') && !m.html.includes('&amp;amp;') && !m.html.includes('&amp;lt;'), 'el HTML escapa UNA vez');
    ok(m.html.includes('{{numero}}&lt;i&gt;') && m.text.includes('Hola {{numero}}<i>'), 'un valor con {{numero}} no se vuelve a expandir; el texto alterno va sin escape');
  }

  // ── 4. Forma de la petición, autorización y datos ─────────────────────────────────────────────────────────────────────────────
  const rechaza = async (cuerpo, status, trozo, opts, db = P.baseFalsa()) => {
    const r = await corre(db, cuerpo, opts);
    igual(r.res.status, status, JSON.stringify(cuerpo).slice(0, 90) + ' → ' + r.res.crudo);
    if (trozo) ok(String(r.res.cuerpo.error).includes(trozo), 'mensaje «' + trozo + '» en ' + r.res.crudo);
    igual(r.correos.length, 0, 'no sale correo');
    return r;
  };
  const base = (k = 'copia_firmada_portal', extra = {}) => porPlantilla(k, CASOS[k], extra);
  await rechaza(base('copia_firmada_portal', { plantilla: 'otra_cosa' }), 400, 'no reconocida');
  for (const mala of ['__proto__', 'constructor', 'toString', 'hasOwnProperty']) await rechaza(base('copia_firmada_portal', { plantilla: mala }), 400, 'no reconocida');
  await rechaza({ ...base(), contrato_id: undefined }, 400, 'contrato_id');
  await rechaza(base('copia_firmada_portal', { contrato_id: 'no-es-uuid' }), 400, 'contrato_id');
  await rechaza(base('copia_firmada_portal', { factura_id: P.ID.factura }), 400, 'no se admite');
  await rechaza(base('enlace_firma_cadena', { firma_id: undefined }), 400, 'firma_id');
  await rechaza(base('copia_firmada_portal', { attach: true, pdf_base64: PDF }), 400, 'sin adjunto');
  await rechaza({ ...base('copia_firmada_comprador'), attach: false, pdf_base64: undefined }, 400, 'PDF adjunto');
  await rechaza(base('copia_firmada_portal', { vars: { importe: '1' } }), 400, 'no admitida');
  await rechaza(base('enlace_firma_cadena', { vars: { nombre: 'Ana' } }), 400, 'no admitida');
  await rechaza(base('copia_firmada_portal', { vars: { nombre: 'x'.repeat(301) } }), 400, 'no válido');
  await rechaza(base('copia_firmada_portal', { vars: { nombre: 'a\u0007b' } }), 400, 'no válido');
  await rechaza(base('copia_firmada_portal', { vars: { nombre: 42 } }), 400, 'no válido');
  // sin credencial → 401; la vía de aviso (con su secreto, a un buzón de aviso) NO admite plantilla
  await rechaza(base(), 401, null, { cabeceras: {} });
  await rechaza(base('enlace_firma_cadena', { to: 'soporte@ejemplo.com' }), 401, 'plantilla', { cabeceras: {}, env: {} });
  await rechaza(base('enlace_firma_cadena', { to: 'soporte@ejemplo.com' }), 401, 'plantilla', { cabeceras: { 'x-aviso-secret': 'aviso-falso' }, env: { ENVIO_AVISO_SECRET: 'aviso-falso' } });
  await rechaza(base(), 401, null, { cabeceras: { 'x-render-secret': 'otro' } });
  // en pausa: ni se lee la base
  { const db = P.baseFalsa(); await rechaza(base(), 503, 'pausa', { extra: { pausado: true } }, db); igual(db.lecturas.length, 0, 'en pausa no se consulta la base'); }
  // los datos tienen que cuadrar con el destinatario y el estado del documento
  const mal = async (nombre, k, retoca, extra, trozo) => { const db = P.baseFalsa(); retoca(db); await rechaza(base(k, extra), 400, trozo, undefined, db); };
  await mal('firma de otro contrato', 'enlace_firma_cadena', (db) => { db.contrato_firmas[0].contrato_id = P.ID.contrato2; }, {}, 'no pertenece');
  await mal('destinatario distinto', 'enlace_firma_cadena', () => {}, { to: 'otra@cliente.test' }, 'no es el firmante');
  await mal('enlace ya no vivo', 'enlace_firma_cadena', (db) => { db.contrato_firmas[0].estado = 'firmado'; }, {}, 'ya no está vivo');
  await mal('enlace de otro dominio', 'enlace_firma_cadena', (db) => { db.contrato_firmas[0].enlace_firma = 'https://malo.example/contracts/firmar.html?t=x'; }, {}, 'no es válido');
  await mal('enlace con otra ruta', 'enlace_firma_cadena', (db) => { db.contrato_firmas[0].enlace_firma = 'https://ejemplo.com/otra/ruta?t=x'; }, {}, 'no es válido');
  await mal('contrato inexistente', 'copia_firmada_portal', (db) => { db.contratos = []; }, {}, 'no encontrado');
  await mal('contrato sin PDF firmado', 'copia_firmada_portal', (db) => { db.contratos[0].pdf_firmado_path = null; }, {}, 'PDF firmado');
  if (DISP.includes('aviso_anulacion')) await mal('aviso a quien no tiene firma anulada', 'aviso_anulacion', () => {}, { to: 'ana@cliente.test' }, 'firma anulada');
  if (DISP.includes('aviso_anulacion')) await mal('aviso a quien no es firmante', 'aviso_anulacion', () => {}, { to: 'otro@cliente.test' }, 'firma anulada');
  await mal('factura anulada', 'factura_primer_hito', (db) => { db.facturas[0].anulada = true; }, {}, 'anulada');
  await mal('proforma con una factura', 'proforma_total', () => {}, { factura_id: P.ID.factura }, 'tipo');
  await mal('factura con una proforma', 'factura_vencimiento', () => {}, { factura_id: P.ID.proforma }, 'tipo');
  await mal('vencimiento sin fecha', 'factura_vencimiento', (db) => { db.facturas[0].venc = null; }, {}, 'vencimiento');
  await mal('factura sin concepto', 'factura_primer_hito', (db) => { db.facturas[0].lineas = []; }, {}, 'concepto');
  await mal('factura inexistente', 'proforma_total', (db) => { db.facturas = []; }, {}, 'no encontrada');
  // si la base no contesta no hay correo (502), no un correo a medias
  { const db = P.baseFalsa(); db.fallos.facturas = 500; await rechaza(base('factura_vencimiento'), 502, 'No se pudieron leer', undefined, db); }
  { const db = P.baseFalsa(); db.lanza.contratos = true; await rechaza(base('copia_firmada_portal'), 502, 'No se pudieron leer', undefined, db); }
  // subject, message y botón del llamante se IGNORAN con plantilla
  { const r = await corre(P.baseFalsa(), base('copia_firmada_portal', { subject: 'ASUNTO MALO', message: 'mensaje malo https://malo.example', cta_url: 'https://ejemplo.com/x', cta_texto: 'Malo', encabezado: 'Malo', etiqueta: 'Malo' }));
    igual(r.res.status, 200, r.res.crudo);
    ok(!/malo/i.test(r.correos[0].subject + r.correos[0].text + r.correos[0].html), 'lo que el llamante mande de texto no llega al correo'); }
  // con sesión de la suite también vale (la vía 2), y la vista previa devuelve el HTML sin enviar
  { const ses = { authorization: 'Bearer jwt-de-equipo' };
    const r = await corre(P.baseFalsa(), base(), { cabeceras: ses, extra: { sesion: true } });
    igual(r.res.status, 200, r.res.crudo); ok(r.log.via === 'sesion' && r.log.plantilla === 'copia_firmada_portal', 'vía sesión');
    const pv = await corre(P.baseFalsa(), { ...base('copia_firmada_comprador'), preview: true, attach: undefined, pdf_base64: undefined }, { cabeceras: ses, extra: { sesion: true } });
    igual(pv.res.status, 200, pv.res.crudo);
    ok(pv.res.cuerpo.html.includes('CR00123 (Palm Field)') && pv.res.cuerpo.plantilla === 'copia_firmada_comprador' && /^f:/.test(pv.res.cuerpo.version) && pv.correos.length === 0, 'vista previa: HTML + plantilla + versión, sin SMTP');
    const pv2 = await corre(P.baseFalsa(), { ...base(), preview: true }, { cabeceras: P.SERVICIO });
    igual(pv2.res.status, 401, 'la vista previa sigue exigiendo sesión'); }
  // el camino libre sigue exactamente igual
  { const r = await corre(P.baseFalsa(), { to: 'x@cliente.test', attach: false, subject: 'Hola', message: 'Texto libre' });
    igual(r.res.status, 200); ok(r.res.cuerpo.plantilla === undefined && r.correos[0].subject === 'Hola', 'el camino libre no cambia'); }

  // ── 5. Las reglas del texto (mismos casos que prueba_correo_plantillas.sql) ──────────────────────────────────────────────────────
  const cat = V.catalogoDe(CAT.copia_firmada_comprador);
  ok(cat && cat.variantes === 1, 'el catálogo sellado se lee');
  const ASU = 'Tu contrato firmado · {{numero}}', CUE = '{{saludo}}, aquí {{contrato_proyecto}}.';
  igual(V.validaTextoPlantilla(ASU, 'asunto', cat), [], 'asunto válido'); igual(V.validaTextoPlantilla(CUE, 'cuerpo', cat), [], 'cuerpo válido');
  const INVALIDOS = [
    ['HTML', 'cuerpo', '{{saludo}}, <b>hola</b> {{contrato_proyecto}}'], ['URL', 'cuerpo', '{{saludo}}, mira https://malo.example {{contrato_proyecto}}'],
    ['correo suelto', 'cuerpo', '{{saludo}}, escribe a x@malo.example {{contrato_proyecto}}'], ['variable desconocida', 'cuerpo', '{{saludo}} {{importe}} {{contrato_proyecto}}'],
    ['falta obligatoria', 'asunto', 'Tu contrato firmado'], ['llave suelta', 'cuerpo', '{{saludo}} {contrato_proyecto}} {{contrato_proyecto}}'],
    ['asunto con salto', 'asunto', 'Tu contrato\nfirmado · {{numero}}'], ['carácter de control', 'cuerpo', '{{saludo}} \u0007 {{contrato_proyecto}}'],
    ['demasiado largo', 'cuerpo', '{{saludo}} {{contrato_proyecto}} ' + 'a'.repeat(5001)], ['javascript:', 'cuerpo', '{{saludo}} javascript:alert {{contrato_proyecto}}'],
    ['vacío', 'cuerpo', '   '],
  ];
  for (const [n, campo, t] of INVALIDOS) ok(V.validaTextoPlantilla(t, campo, cat).length > 0, 'se rechaza: ' + n);
  const catAviso = V.catalogoDe(CAT.aviso_anulacion);
  ok(V.validaTextoPlantilla('{{saludo}} {{numero}} sin motivo', 'cuerpo_alt', catAviso).length > 0, 'el cuerpo de quien firmó tiene que llevar {{bloque_motivo}}');
  igual(V.validaTextoPlantilla('{{saludo}} {{numero}}\n{{bloque_motivo}}', 'cuerpo_alt', catAviso), [], 'y con él vale');
  igual(V.limpiaValor('  Ana \n  María '), 'Ana María', 'limpiaValor junta espacios y saltos'); igual(V.limpiaValor('a\u0007'), null); igual(V.limpiaValor(3), null);
  igual(V.sustituye('a {{x}} {{y}}', { x: '{{y}}', y: 'Y' }), 'a {{y}} Y', 'sin doble expansión'); igual(V.sustituye('{{z}}', {}), null, 'variable sin valor → null');
  // todo lo que la fábrica dice que puede usar existe en el catálogo sellado
  for (const k of CLAVES) {
    const t = F.textoFabrica(k), c = V.catalogoDe(CAT[k]);
    ok(t && c, k + ': hay texto de fábrica y catálogo');
    for (const [campo, tx] of [['asunto', t.asunto], ['cuerpo', t.cuerpo], ['cuerpo_alt', t.cuerpo_alt]]) {
      if (tx === null) { ok(campo !== 'cuerpo_alt' || c.variantes === 1, k + ': variantes del catálogo = cuerpos de fábrica'); continue; }
      igual(V.validaTextoPlantilla(tx, campo, c), [], k + '/' + campo + ': el texto de fábrica cumple las reglas del catálogo');
    }
  }
  console.log(`OK plantillas_motor.test.js — ${CLAVES.length} claves (plantilla == camino libre, byte a byte) · ${Object.keys(casosFabrica).length} causas de caída a fábrica sin 500 · doble escape · ids/vars/vías/datos · ${comprobaciones} comprobaciones`);
})().catch((e) => { console.error(e); process.exit(1); });
