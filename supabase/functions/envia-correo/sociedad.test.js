/* node sociedad.test.js — marca del correo por SOCIEDAD (encargos/20261008_lawang_reclamo_pago_parcela.md, hallazgos 3 de Datos y 5 de Seguridad).
   1. SIN `sociedad` el HTML y el texto son IDÉNTICOS a los de antes del cambio (golden_sin_sociedad.*, sacados del código previo;
      el PHP gemelo lo vigila dorada.test.js).
   2. Con san_dal_woods por la vía de servicio sale la marca/razón/logo de Sandal Woods y NADA de Lawang en el pie, el rótulo ni el logo.
   3. Por la vía de navegador (sesión) o sin credencial, `sociedad` NO cambia la marca: 400 y no sale correo.
   4. Lista cerrada: clave inexistente, inactiva, con formato raro o no-texto → 400 sin correo; base ilegible → 502; nunca cae a Lawang.
   5. Logo: solo https de dominio propio o del storage de este proyecto; un logo ajeno se descarta (nombre en texto). Campos escapados. */
const assert = require('assert');
const fs = require('fs');
const path = require('path');

(async () => {
  const { plantillaHtml, plantillaTexto } = await import('./plantilla.ts');
  const A = await import('./arnes.mjs');
  const { reinicia, cargaEdge, llama, estado } = A;
  const gold = (f) => fs.readFileSync(path.join(__dirname, f), 'utf8');

  // 1 · golden sin sociedad
  const m0 = { marca: 'L', dominio: 'lawangproperties.com', remitente: 'a@b.co' };
  const c0 = { url: 'https://lawangproperties.com/portal/', texto: 'Portal' };
  const hoy = new Date(Date.UTC(2026, 9, 8));
  assert.strictEqual(plantillaHtml('Hola\n\n• uno', 'Titulo', c0, '', m0, hoy), gold('golden_sin_sociedad.html.golden'), 'sin sociedad: HTML distinto del de antes');
  assert.strictEqual(plantillaHtml('Hola\n\n• uno', 'Titulo', c0, '', { ...m0, sociedad: null }, hoy), gold('golden_sin_sociedad.html.golden'), 'sociedad:null debe ser como ausente');
  assert.strictEqual(plantillaTexto('Hola\n\n• uno', 'Titulo', c0, m0), gold('golden_sin_sociedad.txt'), 'sin sociedad: texto distinto del de antes');

  // 2 · plantilla con sociedad
  const SW = { razon: 'PT SAN DAL WOODS', marca: 'Sandal Woods', logoUrl: 'https://lawangproperties.com/contracts/assets/brand/sandalwoods-lockup.png' };
  const hs = plantillaHtml('Hola', 'T', c0, '', { ...m0, sociedad: SW }, hoy);
  assert.ok(hs.includes('alt="Sandal Woods"') && hs.includes(SW.logoUrl), 'logo y alt de la sociedad');
  assert.ok(hs.includes('>PT SAN DAL WOODS</p>') && hs.includes('&copy; 2026 PT SAN DAL WOODS'), 'pie y copyright con la razón');
  for (const lw of ['Lawang Tropical Properties', 'alt="LAWANG"', 'lawang-logo-correo-halo', 'correo-moanito', '>Properties<', 'Lawang Properties'])
    assert.ok(!hs.includes(lw), 'con sociedad no puede quedar de Lawang: ' + lw);
  assert.ok(hs.includes('Sandal Woods</td>'), 'rótulo de la barra = marca');
  const tx = plantillaTexto('Hola', 'T', c0, { ...m0, sociedad: SW });
  assert.ok(tx.includes('--\nPT SAN DAL WOODS\n') && !tx.includes('Lawang Tropical'), 'texto plano con la razón');
  const hx = plantillaHtml('Hola', '', null, '', { ...m0, sociedad: { razon: 'A "<b>" & Co', marca: '<i>M</i>', logoUrl: null } }, hoy);
  assert.ok(!hx.includes('<b>') && !hx.includes('<i>M') && hx.includes('A &quot;&lt;b&gt;&quot; &amp; Co') && hx.includes('&lt;i&gt;M&lt;/i&gt;'), 'razón y marca escapadas');
  assert.ok(!hx.includes('<img src="https://lawangproperties.com/contracts'), 'sin logo: nombre en texto');

  // 3-5 · por la edge real
  const H = (o) => ({ 'content-type': 'application/json', ...o });
  const SERV = { 'x-render-secret': 'render-falso' };
  const config = [['marca', 'Lawang'], ['dominio_web', 'lawangproperties.com'], ['url_intranet', 'https://lawangproperties.com/intranet/'],
    ['email_avisos_soporte', 'soporte@lawangproperties.com']];
  const SWFILA = { razon: 'PT SAN DAL WOODS', marca: 'Sandal Woods', logo: '/contracts/assets/brand/sandalwoods-lockup.png' };
  let filas = { san_dal_woods: SWFILA };
  let errSoc = false, consultas = [];
  const extra = async (u) => {
    if (!u.includes('/rest/v1/sociedades')) return null;
    consultas.push(u);
    if (errSoc) return new Response('x', { status: 500 });
    const k = /clave=eq\.([^&]+)/.exec(u)?.[1];
    return new Response(JSON.stringify(filas[k] ? [filas[k]] : []), { status: 200 });
  };
  const nuevo = async (o = {}) => { reinicia({ config, extra, ...o }); consultas = []; errSoc = false; return cargaEdge(__dirname); };
  const cuerpo = (x = {}) => ({ to: 'ana@cliente.es', message: 'Hola', attach: false, ...x });

  let m = await nuevo();
  let r = await llama(m, { cabeceras: H(SERV), cuerpo: cuerpo() });
  assert.strictEqual(r.status, 200, r.crudo);
  const sinSoc = estado.correo.correos[0];
  assert.ok(sinSoc.html.includes('alt="LAWANG"') && sinSoc.html.includes('Lawang Tropical Properties') && consultas.length === 0, 'sin sociedad: Lawang y ni una consulta a sociedades');

  m = await nuevo();
  r = await llama(m, { cabeceras: H(SERV), cuerpo: cuerpo({ sociedad: 'san_dal_woods' }) });
  assert.strictEqual(r.status, 200, r.crudo);
  const sw = estado.correo.correos[0];
  assert.ok(sw.html.includes('>PT SAN DAL WOODS</p>') && sw.html.includes('alt="Sandal Woods"') && sw.html.includes('https://lawangproperties.com/contracts/assets/brand/sandalwoods-lockup.png'), 'servicio + san_dal_woods: marca de Sandal Woods');
  assert.ok(!sw.html.includes('Lawang Tropical Properties') && !sw.html.includes('alt="LAWANG"'), 'ya no Lawang');
  assert.ok(sw.text.includes('PT SAN DAL WOODS') && !sw.text.includes('Lawang Tropical'), 'texto plano de Sandal Woods');
  assert.ok(consultas.length === 1 && consultas[0].includes('activa=is.true'), 'una consulta, solo sociedades activas');

  // navegador / anónimo: no cambia la marca y no sale nada
  m = await nuevo({ sesion: true });
  r = await llama(m, { cabeceras: H({ 'x-suite-token': 'jwt' }), cuerpo: cuerpo({ sociedad: 'san_dal_woods' }) });
  assert.strictEqual(r.status, 400, 'sesión con sociedad = 400');
  r = await llama(m, { cabeceras: H({ 'x-suite-token': 'jwt' }), cuerpo: { message: 'Hola', preview: true, sociedad: 'san_dal_woods' } });
  assert.strictEqual(r.status, 400, 'vista previa con sociedad = 400');
  assert.strictEqual(estado.correo.correos.length, 0, 'sesión: no sale correo'); assert.strictEqual(consultas.length, 0, 'sesión: ni se consulta la tabla');
  r = await llama(m, { cabeceras: H({ 'x-suite-token': 'jwt' }), cuerpo: cuerpo() });
  assert.strictEqual(r.status, 200); assert.ok(estado.correo.correos[0].html.includes('alt="LAWANG"'), 'la sesión sin sociedad sigue con la marca de Lawang');
  m = await nuevo();
  r = await llama(m, { cabeceras: H({}), cuerpo: cuerpo({ sociedad: 'san_dal_woods' }) });
  assert.ok(r.status === 400 || r.status === 401, 'anónimo: ' + r.status);
  assert.strictEqual(estado.correo.correos.length, 0, 'anónimo: no sale correo'); assert.strictEqual(consultas.length, 0);
  // aviso interno (sin credencial, a un buzón de aviso): tampoco admite sociedad
  r = await llama(m, { cabeceras: H({}), cuerpo: { to: 'soporte@lawangproperties.com', message: 'x', attach: false, sociedad: 'san_dal_woods' } });
  assert.strictEqual(r.status, 400, 'aviso interno con sociedad = 400'); assert.strictEqual(estado.correo.correos.length, 0);

  // lista cerrada
  m = await nuevo();
  for (const s of ['no_existe', 'SAN_DAL_WOODS', '../x', 'a b', 'x'.repeat(60), 7, { a: 1 }, ['san_dal_woods']]) {
    r = await llama(m, { cabeceras: H(SERV), cuerpo: cuerpo({ sociedad: s }) });
    assert.strictEqual(r.status, 400, JSON.stringify(s) + ' → ' + r.status);
  }
  assert.strictEqual(estado.correo.correos.length, 0, 'ninguna clave mala envía');
  m = await nuevo(); filas = {};
  r = await llama(m, { cabeceras: H(SERV), cuerpo: cuerpo({ sociedad: 'san_dal_woods' }) });
  assert.strictEqual(r.status, 400, 'inactiva/ausente de la tabla = 400'); assert.strictEqual(estado.correo.correos.length, 0);
  filas = { san_dal_woods: SWFILA };
  m = await nuevo();
  errSoc = true;
  r = await llama(m, { cabeceras: H(SERV), cuerpo: cuerpo({ sociedad: 'san_dal_woods' }) });
  assert.strictEqual(r.status, 502, 'base ilegible = 502, nunca la marca de Lawang'); assert.strictEqual(estado.correo.correos.length, 0);

  // logo ajeno, marca vacía → razón
  filas = { san_dal_woods: { razon: 'PT SAN DAL WOODS', marca: '', logo: 'https://evil.example/pixel.png' } };
  m = await nuevo();
  r = await llama(m, { cabeceras: H(SERV), cuerpo: cuerpo({ sociedad: 'san_dal_woods' }) });
  assert.strictEqual(r.status, 200, r.crudo);
  const aj = estado.correo.correos[0].html;
  assert.ok(!aj.includes('evil.example') && !aj.includes('<img src="https://lawangproperties.com/contracts') && aj.includes('PT SAN DAL WOODS'), 'logo ajeno descartado; marca vacía → razón');

  console.log('OK sociedad.test.js — sin sociedad idéntico al golden (HTML+texto); san_dal_woods por servicio sale con su marca; sesión/anónimo/previa/aviso → 400 sin correo; lista cerrada y 502 sin caer a Lawang; logo ajeno descartado; campos escapados');
})().catch((e) => { console.error(e); process.exit(1); });
