/* node paleta_sociedad.test.js — paleta del correo por SOCIEDAD y saludo de reclamo_pago (owner, 8-oct-2026).
   1. san_dal_woods (tinta primary #662906 / deep #42210B, folio #E7E3D2) sale en tonos tierra: ni #485B37 ni #8F9B7A (verde de Lawang).
   2. Sin sociedad y con la sociedad de la casa (primary = verde de Lawang) el HTML es BYTE A BYTE el de siempre.
   3. Un color inválido o ausente cae a la paleta de hoy (nunca se cuela texto del dato al estilo).
   4. Por la edge real: los colores salen de la fila de `sociedades` (tinta/folio), no de una paleta escrita en la plantilla.
   5. Saludo SOLO de reclamo_pago: VICTOR → Víctor, MARÍA JOSÉ PÉREZ → María, JUAN → Juan, ñ y tildes respetadas, vacío → «Hola». */
const assert = require('assert');
const fs = require('fs');
const path = require('path');

(async () => {
  const { plantillaHtml } = await import('./plantilla.ts');
  const F = await import('./plantillas_fabrica.ts');
  const A = await import('./arnes.mjs');
  const gold = (f) => fs.readFileSync(path.join(__dirname, f), 'utf8');
  const m0 = { marca: 'L', dominio: 'lawangproperties.com', remitente: 'a@b.co' };
  const c0 = { url: 'https://lawangproperties.com/portal/', texto: 'Portal' };
  const hoy = new Date(Date.UTC(2026, 9, 8));
  const base = { razon: 'PT SAN DAL WOODS', marca: 'Sandal Woods', logoUrl: null };
  const SW = { ...base, tinta: { deep: '#42210B', primary: '#662906' }, folio: '#E7E3D2' };
  const TEPI = { razon: 'PT TEPI SUNGAI', marca: 'Tepi Sungai', logoUrl: null, tinta: { deep: '#104C4F', primary: '#485B37' }, folio: '#E6EFE0' };
  const render = (so) => plantillaHtml('Hola\n\n• uno', 'Titulo', c0, '', { ...m0, sociedad: so }, hoy);

  // 1 · tonos tierra
  const hs = render(SW);
  for (const lw of ['#485B37', '#8F9B7A', '#2E3437', '#BEB3A5', '#F5F0E6']) assert.ok(!hs.toUpperCase().includes(lw), 'Sandal Woods sin el ' + lw + ' de Lawang');
  for (const t of ['#662906', '#42210B', '#E7E3D2']) assert.ok(hs.toUpperCase().includes(t), 'Sandal Woods lleva ' + t);
  const hex = new Set(hs.match(/#[0-9A-Fa-f]{6}/g).map((x) => x.toUpperCase()));
  console.log('colores de Sandal Woods:', [...hex].join(' '));
  assert.ok(hs.includes('background:#42210B;border-radius:999px') && hs.includes('bgcolor="#E7E3D2"'), 'botón = deep, tarjeta = folio');

  // 2 · Lawang intacto
  assert.strictEqual(plantillaHtml('Hola\n\n• uno', 'Titulo', c0, '', m0, hoy), gold('golden_sin_sociedad.html.golden'), 'sin sociedad: golden');
  const hl = render({ razon: 'X', marca: 'X', logoUrl: null });   // sociedad sin tinta: paleta de hoy
  assert.ok(hl.includes('#485B37') && hl.includes('#8F9B7A'), 'sociedad sin tinta: verde de siempre');
  assert.strictEqual(render(TEPI), render({ ...TEPI, tinta: null, folio: null }), 'tepi_sungai (verde de Lawang) = la paleta de hoy, byte a byte');
  assert.ok(render(TEPI).includes('#485B37') && render(TEPI).includes('#8F9B7A'));

  // 3 · inválidos
  for (const mal of [{ ...SW, folio: 'rojo' }, { ...SW, folio: '#E7E3D' }, { ...SW, folio: null }, { ...SW, tinta: { deep: '#42210B' } },
    { ...SW, tinta: { deep: '#42210B', primary: 'red;background:url(x)' } }, { ...SW, tinta: [] }, { ...SW, tinta: null }, { ...SW, folio: 7 }])
    assert.strictEqual(render(mal), render({ ...base }), 'inválido → paleta de hoy · ' + JSON.stringify(mal.tinta) + JSON.stringify(mal.folio));
  assert.ok(!render({ ...SW, tinta: { deep: '#42210B', primary: 'red;background:url(x)' } }).includes('url(x)'), 'el dato malo no llega al estilo');

  // 4 · por la edge real, desde la fila de la tabla
  const H = { 'content-type': 'application/json', 'x-render-secret': 'render-falso' };
  const config = [['marca', 'Lawang'], ['dominio_web', 'lawangproperties.com'], ['url_intranet', 'https://lawangproperties.com/intranet/'],
    ['email_avisos_soporte', 'soporte@lawangproperties.com']];
  let fila = { razon: 'PT SAN DAL WOODS', marca: 'Sandal Woods', logo: null, tinta: { deep: '#123456', primary: '#ABCDEF' }, folio: '#FEDCBA' };
  const extra = async (u) => u.includes('/rest/v1/sociedades') ? (assert.ok(/select=[^&]*tinta[^&]*folio/.test(u), 'la edge pide tinta y folio'), new Response(JSON.stringify([fila]), { status: 200 })) : null;
  A.reinicia({ config, extra });
  const m = await A.cargaEdge(__dirname);
  const r = await A.llama(m, { cabeceras: H, cuerpo: { to: 'ana@cliente.es', message: 'Hola', attach: false, sociedad: 'san_dal_woods' } });
  assert.strictEqual(r.status, 200, r.crudo);
  const h = A.estado.correo.correos[0].html.toUpperCase();
  assert.ok(h.includes('#ABCDEF') && h.includes('#123456') && h.includes('#FEDCBA') && !h.includes('#485B37'), 'los colores salen de la fila de la sociedad');

  // 5 · saludo (solo reclamo_pago)
  const ID_C = '11111111-1111-4111-8111-111111111111', ID_R = '55555555-5555-4555-8555-555555555555';
  const saludoDe = async (nombre, clave = 'reclamo_pago') => {
    const rest = async () => [{ reclamo_id: ID_R, para: 'a@b.es', nombre, idioma: 'es', parcela: 'A-12', proyecto: 'P', empresa_razon: 'E', nota: null, contrato_id: ID_C,
      firmante_nombre: nombre, firmante_email: 'a@b.es', estado: 'pendiente', contrato_numero: 'C-1', enlace_firma: 'https://lawangproperties.com/f/x', id: ID_R }];
    const r = await F.resuelve(clave, { contrato_id: ID_C, factura_id: '', firma_id: ID_R }, 'a@b.es', { reclamo: ID_R }, rest, { marca: 'L', portal: 'https://lawangproperties.com/portal/', dominio: 'lawangproperties.com' });
    return r.vars ? r.vars.saludo : r;
  };
  for (const [e, s] of [['VÍCTOR', 'Hola Víctor'], ['VICTOR', 'Hola Victor'], ['MARÍA JOSÉ PÉREZ', 'Hola María'], ['MARIA JOSE PEREZ', 'Hola Maria'], ['JUAN', 'Hola Juan'],
    ['  ñandú  gómez ', 'Hola Ñandú'], ['ana', 'Hola Ana'], ['', 'Hola'], ['   ', 'Hola']])
    assert.strictEqual(await saludoDe(e), s, JSON.stringify(e));
  const fuente = fs.readFileSync(path.join(__dirname, 'plantillas_fabrica.ts'), 'utf8');
  assert.strictEqual((fuente.match(/saludo: saludoNombre\(/g) || []).length, 1, 'saludoNombre solo en reclamo_pago');
  assert.strictEqual((fuente.match(/saludo: saludo\(/g) || []).length, 4, 'las demás resoluciones conservan su saludo');

  console.log('OK paleta_sociedad.test.js — SW en tierra (#662906/#42210B/#E7E3D2, sin verde de Lawang); sin sociedad y tepi_sungai idénticos; inválido→hoy; colores desde la fila; saludo reclamo_pago capitalizado');
})().catch((e) => { console.error(e); process.exit(1); });
