/* node index.test.js — el `index.ts` REAL de la edge envia-correo, sin Deno y sin red (arnes.mjs).
   Idéntico en Lawang y en el maestro. Cubre lo que los dos comparten: las vías de autorización, el texto del 503
   de pausa, el texto del fallo de SMTP (del que dependen los frenos de los crons), el asunto por defecto, X-Llamante
   y el contrato de siempre (401/403/405/500). Lo que depende de la piel de cada cliente está en su plantilla.test.js. */
const assert = require('assert');
const fs = require('fs');
const path = require('path');

(async () => {
  const A = await import('./arnes.mjs');
  const { reinicia, cargaEdge, llama, lineaJson, estado } = A;
  const R = 'render-falso', E = 'envio-falso', AV = 'aviso-falso';
  const H = (o) => ({ 'content-type': 'application/json', ...o });
  const texto = { to: 'ana@cliente.es', message: 'Hola', attach: false };

  // Las regex REALES de los dos crons de Lawang, sacadas de su fuente: si alguien las cambia, esto se rompe.
  // En el maestro esos ficheros no existen (Lawang es otro repo): entonces se usan las literales y se dice.
  function regexDe(fichero, nombre) {
    const f = path.join(__dirname, '..', '..', '..', 'contracts', 'edge', fichero, 'index.ts');
    if (!fs.existsSync(f)) return null;
    const m = new RegExp('const ' + nombre + ' = (/.*/[a-z]*);').exec(fs.readFileSync(f, 'utf8'));
    assert.ok(m, `no encuentro ${nombre} en ${fichero}`);
    return eval(m[1]); // eslint-disable-line no-eval -- literal de regex de nuestro propio repo
  }
  const BLOQ_LIT = /\b554\b|5\.7\.1|Outbound sending is disabled/i, PAUSA_LIT = /en pausa \(modo mantenimiento\)/i;
  const bloqueos = [['literal', BLOQ_LIT]], pausas = [['literal', PAUSA_LIT]];
  for (const c of ['avisos-manager', 'comunicados-envio']) {
    const b = regexDe(c, 'BLOQUEO_SMTP'); if (b) { bloqueos.push([c, b]); assert.strictEqual(b.source, BLOQ_LIT.source, `${c}: BLOQUEO_SMTP cambió`); }
  }
  { const p = regexDe('avisos-manager', 'EN_PAUSA'); if (p) { pausas.push(['avisos-manager', p]); assert.strictEqual(p.source, PAUSA_LIT.source); } }
  console.log(`   regex de los crons leídas de su fuente: ${bloqueos.length - 1} BLOQUEO_SMTP, ${pausas.length - 1} EN_PAUSA`);

  // ── 1. pausa: el texto EXACTO y que casa con lo que buscan los crons ─────────────────────────────────────
  reinicia({ pausado: true });
  let m = await cargaEdge(__dirname);
  let r = await llama(m, { cabeceras: H({ 'x-render-secret': R }), cuerpo: texto });
  assert.strictEqual(r.status, 503);
  assert.strictEqual(r.cuerpo.error, 'Los envíos de correo están en pausa (modo mantenimiento). No se ha enviado nada.');
  for (const [n, re] of pausas) assert.ok(re.test(r.crudo.slice(0, 200)), 'la pausa no casa con ' + n);
  assert.strictEqual(estado.correo.correos.length, 0, 'en pausa no sale nada');
  reinicia({ pausado: 'error' });   // no se puede preguntar → no se envía (fail-closed)
  m = await cargaEdge(__dirname);
  r = await llama(m, { cabeceras: H({ 'x-render-secret': R }), cuerpo: texto });
  assert.strictEqual(r.status, 503, 'sin poder preguntar, en pausa');

  // ── 2. fallo de SMTP: 554 casa con el freno de los crons; el texto libre del servidor no sale ────────────
  reinicia();
  m = await cargaEdge(__dirname);
  estado.correo.falloSmtp = Object.assign(new Error('boom'), {
    code: 'EENVELOPE', responseCode: 554, command: 'MAIL FROM',
    response: '554 5.7.1 Outbound sending is disabled for buzon@ejemplo.com (id 8842-secreto)',
  });
  r = await llama(m, { cabeceras: H({ 'x-render-secret': R, 'x-llamante': 'aviso-test' }), cuerpo: texto });
  assert.strictEqual(r.status, 500);
  assert.strictEqual(r.cuerpo.ok, false);
  assert.strictEqual(r.cuerpo.smtp_code, 'EENVELOPE');
  assert.strictEqual(r.cuerpo.smtp_response_code, 554);
  for (const [n, re] of bloqueos) {
    assert.ok(re.test(r.cuerpo.error), 'el error no casa con BLOQUEO_SMTP de ' + n + ': ' + r.cuerpo.error);
    // lo que ven los crons: los primeros 180-200 caracteres del cuerpo CRUDO de la respuesta
    assert.ok(re.test(r.crudo.slice(0, 180)), 'los 180 primeros caracteres no casan con ' + n + ': ' + r.crudo.slice(0, 180));
  }
  assert.ok(!/buzon@|8842|secreto/.test(r.crudo), 'el texto libre del servidor no debe llegar al llamante: ' + r.crudo);
  const todoElLog = r.logs.join('\n');
  assert.ok(!/buzon@|8842|secreto|Outbound/.test(todoElLog), 'el texto libre del servidor no debe llegar al log: ' + todoElLog);
  assert.ok(/554/.test(todoElLog) && /5\.7\.1/.test(todoElLog), 'el log SÍ lleva el código numérico y el estado');
  // sin la frase pero con 5.7.1 solo en la respuesta, o solo 554: sigue casando
  for (const [rc, resp] of [[554, '554 nada'], [undefined, '250-x\n554 5.7.1 lo que sea'], [550, '550 5.7.1 rechazado']]) {
    estado.correo.falloSmtp = Object.assign(new Error('x'), { code: 'EENVELOPE', responseCode: rc, response: resp });
    r = await llama(m, { cabeceras: H({ 'x-render-secret': R }), cuerpo: texto });
    assert.ok(BLOQ_LIT.test(r.cuerpo.error), `${rc}/${resp}: ${r.cuerpo.error}`);
  }
  // un 535 (clave mal) o un timeout NO son bloqueo: no deben parar la tanda
  estado.correo.falloSmtp = Object.assign(new Error('x'), { code: 'EAUTH', responseCode: 535, response: '535 5.7.8 Error: authentication failed' });
  r = await llama(m, { cabeceras: H({ 'x-render-secret': R }), cuerpo: texto });
  assert.ok(!BLOQ_LIT.test(r.cuerpo.error), 'un 535 no es un bloqueo: ' + r.cuerpo.error);
  assert.strictEqual(r.cuerpo.smtp_response_code, 535);
  estado.correo.falloSmtp = Object.assign(new Error('x'), { code: 'ETIMEDOUT' });
  r = await llama(m, { cabeceras: H({ 'x-render-secret': R }), cuerpo: texto });
  assert.strictEqual(r.cuerpo.error, 'No se pudo enviar por SMTP (ETIMEDOUT)');
  assert.strictEqual(r.cuerpo.smtp_response_code, null);
  estado.correo.falloSmtp = new Error('sin nada');   // ni código ni respuesta
  r = await llama(m, { cabeceras: H({ 'x-render-secret': R }), cuerpo: texto });
  assert.strictEqual(r.cuerpo.error, 'No se pudo enviar por SMTP (desconocido)');
  assert.strictEqual(r.cuerpo.smtp_code, 'desconocido');
  // un fallo que NO es de SMTP no lleva campos de SMTP (el contrato de siempre)
  reinicia(); m = await cargaEdge(__dirname);
  r = await llama(m, { cabeceras: H({ 'x-render-secret': R }), cuerpo: { to: 'no-es-un-correo', message: 'x', attach: false } });
  assert.strictEqual(r.status, 400); assert.deepStrictEqual(Object.keys(r.cuerpo), ['ok', 'error']);

  // ── 3. vía servicio: ENVIO_CORREO_SECRET manda; sin él, cae a RENDER_SECRET ──────────────────────────────
  reinicia({ env: { ENVIO_CORREO_SECRET: E } }); m = await cargaEdge(__dirname);
  r = await llama(m, { cabeceras: H({ 'x-render-secret': E }), cuerpo: texto });
  assert.strictEqual(r.status, 200); assert.strictEqual(lineaJson(r).via, 'servicio');
  r = await llama(m, { cabeceras: H({ 'x-render-secret': R }), cuerpo: texto });
  assert.strictEqual(r.status, 401, 'con ENVIO_CORREO_SECRET definido, RENDER_SECRET ya NO autoriza el envío');
  r = await llama(m, { cabeceras: H({ 'x-render-secret': 'otro' }), cuerpo: texto });
  assert.strictEqual(r.status, 401);
  reinicia(); m = await cargaEdge(__dirname);   // como el maestro hoy
  r = await llama(m, { cabeceras: H({ 'x-render-secret': R }), cuerpo: texto });
  assert.strictEqual(r.status, 200, 'sin ENVIO_CORREO_SECRET, el RENDER_SECRET de siempre sigue valiendo');
  assert.strictEqual(lineaJson(r).via, 'servicio-render', 'el log distingue la vía por el secreto compartido');
  r = await llama(m, { cabeceras: H({}), cuerpo: texto });
  assert.strictEqual(r.status, 401, 'sin credencial y a un destino que no es de aviso');
  reinicia({ env: { RENDER_SECRET: '' } }); m = await cargaEdge(__dirname);   // sin ninguno de los dos: nunca autoriza con cabecera vacía
  r = await llama(m, { cabeceras: H({ 'x-render-secret': '' }), cuerpo: texto });
  assert.strictEqual(r.status, 401);
  // el PDF se pide al servicio con RENDER_SECRET (salida), aunque la entrada sea ENVIO_CORREO_SECRET
  reinicia({ env: { ENVIO_CORREO_SECRET: E } }); m = await cargaEdge(__dirname);
  r = await llama(m, { cabeceras: H({ 'x-render-secret': E }), cuerpo: { to: 'ana@cliente.es', message: 'Hola', html: '<p>doc</p>', filename: 'c.pdf' } });
  assert.strictEqual(r.status, 200);
  const pdfLlamada = estado.llamadas.find((c) => c.url.endsWith('/render-pdf'));
  assert.ok(pdfLlamada, 'se pidió el PDF');
  assert.strictEqual(pdfLlamada.cabeceras['X-Render-Secret'], R, 'hacia el servicio de PDFs va RENDER_SECRET, no el de entrada');
  assert.strictEqual(estado.correo.correos[0].attachments.length, 1);

  // ── 4. vía sesión ────────────────────────────────────────────────────────────────────────────────────────
  reinicia({ sesion: true }); m = await cargaEdge(__dirname);
  r = await llama(m, { cabeceras: H({ 'x-suite-token': 'jwt-de-alguien' }), cuerpo: texto });
  assert.strictEqual(r.status, 200); assert.strictEqual(lineaJson(r).via, 'sesion');
  r = await llama(m, { cabeceras: H({ authorization: 'Bearer anon-falsa' }), cuerpo: texto });
  assert.strictEqual(r.status, 401, 'la anon key no es una sesión');
  reinicia({ sesion: false }); m = await cargaEdge(__dirname);
  r = await llama(m, { cabeceras: H({ 'x-suite-token': 'jwt-caducado' }), cuerpo: texto });
  assert.strictEqual(r.status, 401);

  // ── 5. vía aviso ─────────────────────────────────────────────────────────────────────────────────────────
  const aviso = (o = {}) => ({ to: 'soporte@ejemplo.com', message: 'Aviso interno', attach: false, encabezado: 'TITULO-PROPIO', etiqueta: 'ETIQ-PROPIA', cta_url: 'https://ejemplo.com/x', cta_texto: 'IR', ...o });
  //   5a. con ENVIO_AVISO_SECRET: hace falta la cabecera; la puerta anónima está cerrada
  reinicia({ env: { ENVIO_AVISO_SECRET: AV } }); m = await cargaEdge(__dirname);
  r = await llama(m, { cabeceras: H({ 'x-aviso-secret': AV, 'x-llamante': 'pg_net:soporte' }), cuerpo: aviso() });
  assert.strictEqual(r.status, 200); assert.strictEqual(lineaJson(r).via, 'aviso'); assert.strictEqual(lineaJson(r).llamante, 'pg_net:soporte');
  const html = estado.correo.correos[0].html;
  assert.ok(!html.includes('TITULO-PROPIO') && !html.includes('ETIQ-PROPIA') && !html.includes('https://ejemplo.com/x'),
    'el aviso pierde encabezado, etiqueta y botón propios (anti-phishing interno)');
  r = await llama(m, { cabeceras: H({}), cuerpo: aviso() });
  assert.strictEqual(r.status, 401, 'sin X-Aviso-Secret y con la variable definida, la puerta anónima está cerrada');
  r = await llama(m, { cabeceras: H({ 'x-aviso-secret': 'mal' }), cuerpo: aviso() });
  assert.strictEqual(r.status, 401);
  r = await llama(m, { cabeceras: H({ 'x-aviso-secret': AV }), cuerpo: aviso({ to: 'otro@ejemplo.com' }) });
  assert.strictEqual(r.status, 401, 'el secreto de aviso solo abre los buzones email_avisos_*');
  r = await llama(m, { cabeceras: H({ 'x-aviso-secret': AV }), cuerpo: aviso({ to: 'ana@cliente.es' }) });
  assert.strictEqual(r.status, 401, 'ni escribir a un tercero');
  r = await llama(m, { cabeceras: H({ 'x-aviso-secret': AV }), cuerpo: aviso({ attach: true, pdf_base64: Buffer.from('%PDF-1.7 x').toString('base64') }) });
  assert.strictEqual(r.status, 401, 'ni con adjunto');
  for (const b of ['soporte@ejemplo.com', 'SISTEMA@EJEMPLO.COM', 'reservas@ejemplo.com']) {
    r = await llama(m, { cabeceras: H({ 'x-aviso-secret': AV }), cuerpo: aviso({ to: b }) });
    assert.strictEqual(r.status, 200, b);
  }
  //   5b. sin ENVIO_AVISO_SECRET: la antigua vía 3 anónima (comportamiento actual del maestro)
  reinicia(); m = await cargaEdge(__dirname);
  r = await llama(m, { cabeceras: H({}), cuerpo: aviso() });
  assert.strictEqual(r.status, 200); assert.strictEqual(lineaJson(r).via, 'aviso-interno');
  r = await llama(m, { cabeceras: H({ 'x-aviso-secret': 'da igual' }), cuerpo: aviso() });
  assert.strictEqual(r.status, 200, 'sin la variable, la cabecera no se mira');
  r = await llama(m, { cabeceras: H({}), cuerpo: aviso({ to: 'otro@ejemplo.com' }) });
  assert.strictEqual(r.status, 401, 'la puerta anónima solo abre los buzones de aviso');
  //   5c. el freno: 20 avisos por ventana y por isolate, con y sin secreto
  for (const env of [{}, { ENVIO_AVISO_SECRET: AV }]) {
    reinicia({ env }); m = await cargaEdge(__dirname);
    const cab = env.ENVIO_AVISO_SECRET ? H({ 'x-aviso-secret': AV }) : H({});
    let ultimo;
    for (let i = 0; i < 21; i++) ultimo = await llama(m, { cabeceras: cab, cuerpo: aviso() });
    assert.strictEqual(ultimo.status, 429, 'el aviso 21 se frena');
    assert.strictEqual(estado.correo.correos.length, 20);
  }
  //   5d. una vía con credencial NO gasta el freno de los avisos
  reinicia({ env: { ENVIO_AVISO_SECRET: AV } }); m = await cargaEdge(__dirname);
  for (let i = 0; i < 25; i++) { r = await llama(m, { cabeceras: H({ 'x-render-secret': R }), cuerpo: aviso() }); assert.strictEqual(r.status, 200); }
  reinicia(); m = await cargaEdge(__dirname);   // y sin la variable, donde la puerta anónima está abierta, un llamante con credencial tampoco cae en ella
  for (let i = 0; i < 25; i++) { r = await llama(m, { cabeceras: H({ 'x-render-secret': R }), cuerpo: aviso() }); assert.strictEqual(r.status, 200); }
  assert.strictEqual(lineaJson(r).via, 'servicio-render');
  assert.ok(estado.correo.correos[0].html.includes('TITULO-PROPIO'), 'con credencial, el título y el botón propios se respetan');

  // ── 6. X-Llamante: se anota saneado y recortado; no cambia la respuesta ─────────────────────────────────
  reinicia(); m = await cargaEdge(__dirname);
  r = await llama(m, { cabeceras: H({ 'x-render-secret': R, 'x-llamante': ' firma-submit <b>"x"</b>' + 'z'.repeat(60) }), cuerpo: texto });
  assert.strictEqual(r.status, 200); assert.deepStrictEqual(r.cuerpo, { ok: true });
  const ll = lineaJson(r).llamante;
  assert.ok(ll.length === 40 && /^[A-Za-z0-9._:@/-]+$/.test(ll), 'llamante saneado y de 40 como mucho: ' + ll);
  assert.ok(ll.startsWith('firma-submit__b__x__'));
  r = await llama(m, { cabeceras: H({ 'x-render-secret': R }), cuerpo: texto });
  assert.ok(!('llamante' in lineaJson(r)), 'sin cabecera, la línea de log es la de siempre');
  r = await llama(m, { cabeceras: H({ 'x-llamante': 'panel' }), cuerpo: { to: 'otro@cliente.es', message: 'x', attach: false } });   // también en los rechazos
  assert.strictEqual(lineaJson(r).llamante, 'panel'); assert.strictEqual(lineaJson(r).estado, 401);

  // ── 7. asunto por defecto ────────────────────────────────────────────────────────────────────────────────
  const asuntoEnviado = async (cfg, extra = {}) => {
    reinicia({ config: cfg }); const mm = await cargaEdge(__dirname);
    const rr = await llama(mm, { cabeceras: H({ 'x-render-secret': R }), cuerpo: { ...texto, ...extra } });
    return [rr, estado.correo.correos[0] && estado.correo.correos[0].subject];
  };
  let [, asu] = await asuntoEnviado(A.CONFIG_BASE); assert.strictEqual(asu, 'Documento — Acme', 'sin clave: «Documento — <marca>»');
  [, asu] = await asuntoEnviado([...A.CONFIG_BASE, ['asunto_por_defecto', 'Contrato — Acme Properties']]); assert.strictEqual(asu, 'Contrato — Acme Properties');
  [, asu] = await asuntoEnviado([...A.CONFIG_BASE, ['asunto_por_defecto', 'malo\r\nBcc: v@y.z']]); assert.strictEqual(asu, 'Documento — Acme', 'un valor de config con saltos se ignora');
  [, asu] = await asuntoEnviado([...A.CONFIG_BASE, ['asunto_por_defecto', 'x'.repeat(201)]]); assert.strictEqual(asu, 'Documento — Acme', 'demasiado largo: se ignora');
  [, asu] = await asuntoEnviado([...A.CONFIG_BASE, ['asunto_por_defecto', 'Contrato']], { subject: 'El mío' }); assert.strictEqual(asu, 'El mío', 'el asunto de quien llama manda');
  let rr; [rr, asu] = await asuntoEnviado(A.CONFIG_BASE, { subject: 'Hola\r\nBcc: v@y.z' });
  assert.strictEqual(rr.status, 400, 'un asunto con saltos de línea se rechaza'); assert.strictEqual(asu, undefined);
  [rr] = await asuntoEnviado(A.CONFIG_BASE, { subject: 'Hola\nBcc: v@y.z' }); assert.strictEqual(rr.status, 400);

  // ── 8. el contrato de siempre ───────────────────────────────────────────────────────────────────────────
  reinicia(); m = await cargaEdge(__dirname);
  r = await llama(m, { metodo: 'GET' }); assert.strictEqual(r.status, 405);
  r = await llama(m, { cabeceras: H({ origin: 'https://fraude.ru' }), cuerpo: texto }); assert.strictEqual(r.status, 403);
  r = await llama(m, { metodo: 'OPTIONS', cabeceras: { origin: 'https://erp.ejemplo.com' } }); assert.strictEqual(r.status, 204);
  reinicia({ config: [] }); m = await cargaEdge(__dirname);
  r = await llama(m, { cabeceras: H({ 'x-render-secret': R }), cuerpo: texto }); assert.strictEqual(r.status, 500, 'sin config_instancia no envía nada');
  reinicia({ env: { SMTP_PORT: '587' } }); m = await cargaEdge(__dirname);
  r = await llama(m, { cabeceras: H({ 'x-render-secret': R }), cuerpo: texto });
  assert.strictEqual(r.status, 500); assert.ok(/465/.test(r.cuerpo.error));
  reinicia(); m = await cargaEdge(__dirname);
  r = await llama(m, { cabeceras: H({ 'x-render-secret': R }), cuerpo: { ...texto, preview: true } });
  assert.strictEqual(r.status, 401, 'la vista previa exige sesión de la suite (un secreto de servicio no vale)');
  assert.strictEqual(estado.correo.correos.length, 0);

  console.log('OK index.test.js — la edge real, sin red: pausa, 554/535/timeout, vías servicio/sesión/aviso, freno, X-Llamante, asunto, contrato');
})().catch((e) => { console.error(e); process.exit(1); });
