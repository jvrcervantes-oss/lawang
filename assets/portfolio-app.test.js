/* Arnes de la SPA con documento en vivo:  node assets/portfolio-app.test.js   (tools/test.py lo recoge).
   F7, 6-oct-2026. Ejecuta assets/portfolio-app.js REAL (con el bloque de datos de thecollection.php y
   lawang-card.js) sobre un DOM minimo y afirma lo que pinta, sobre todo lo que NO debe afirmar nunca:
   «disponible» con dato viejo. Sin red: fetch y Supabase son stubs que registran las llamadas.
   Casos: dato fresco / dato stale / dato fresco pero la pestaña lleva > 30 min (Date.now adelantado). */
const vm = require('vm'), fs = require('fs'), path = require('path');
const raiz = path.resolve(__dirname, '..');
const leer = f => fs.readFileSync(path.join(raiz, f), 'utf8').split('\r\n').join('\n'); // el checkout de Windows trae CRLF
let fallos = 0;
function ok(c, m) { if (!c) { fallos++; console.log('FALLO: ' + m); } }

// bloque de datos (DICT, LAWANG) de thecollection.php sin los trozos PHP; la rama `!$LIVE` (credenciales) se quita: es la v2
const php = leer('thecollection.php');
const i0 = php.indexOf('<script>\n(function () {\n  var RATES');
const datos = php.slice(i0 + 9, php.indexOf('</script>', i0))
  .replace(/<\?php if \(!\$LIVE\): \?>.*?<\?php endif; \?>/s, '');
ok(i0 > 0 && !/<\?/.test(datos), 'el bloque de datos de thecollection.php se extrae sin PHP');

const rpc = JSON.parse(leer('coleccion/tests/rpc_real_20261006.json')).properties;
const palm = () => JSON.parse(JSON.stringify(rpc.find(p => p.id === 'palm-field-bali')));

// `datajson: true` = la fuente de hoy en produccion: SIN documento precargado; la SPA baja data.json en crudo (el stub
// de fetch lo sirve), que trae TODAS las fichas, tambien las ocultas.
function arranca(doc, { hash = '', datajson = false } = {}) {
  const llamadas = [];
  const el = () => ({ style: {}, classList: { add() {}, remove() {}, toggle() {}, contains() { return false; } }, setAttribute() {}, addEventListener() {}, querySelector() { return null; }, querySelectorAll() { return []; } });
  const root = Object.assign(el(), { innerHTML: '' });
  const ahora = Date.now();
  let off = 0;
  const Dt = { now: () => ahora + off };
  const win = {
    LW_COLECCION_PRELOAD: datajson ? undefined : doc, LW_COLECCION_V2: !datajson, LW_LANG: 'en', addEventListener() {}, scrollTo() {}, scrollY: 0,
    location: { pathname: datajson ? '/thecollection' : '/thecollection-v2', hash, search: '' }, history: { pushState() {}, replaceState() {} },
    sessionStorage: { getItem() { return null; }, setItem() {} }, localStorage: { getItem() { return null; }, setItem() {} },
    requestAnimationFrame: f => f(), performance: { getEntriesByType: () => [] }
  };
  const documento = Object.assign(el(), { getElementById: id => (id === 'portfolio-root' ? root : null), documentElement: el(), body: el(), readyState: 'complete', title: '',
    querySelectorAll: () => [], querySelector: () => null, addEventListener() {} });
  win.document = documento; win.window = win;
  win.fetch = u => {
    llamadas.push(String(u));
    const cuerpo = datajson && /^data\.json/.test(String(u)) ? JSON.stringify(doc) : '';
    return Promise.resolve({ ok: true, json: () => Promise.resolve({ result: 'x' }), text: () => Promise.resolve(cuerpo) });
  };
  const ctx = vm.createContext(Object.assign(win, { Date: Object.assign(function () { return new Date(Dt.now()); }, { now: Dt.now }), console, setTimeout, clearTimeout, encodeURIComponent, JSON, Math, Object, Array, String, Number, Promise, parseInt, isFinite, isNaN, RegExp, Error }));
  vm.runInContext(datos, ctx);
  vm.runInContext(leer('assets/lawang-card.js'), ctx);
  vm.runInContext(leer('assets/portfolio-app.js'), ctx);
  const pasa = ms => { off += ms; win.LW_AL_CAMBIAR_IDIOMA('en'); return root.innerHTML; }; // el tiempo pasa y la SPA se repinta
  return new Promise(r => setTimeout(() => r({ get html() { return root.innerHTML; }, llamadas, win, pasa }), 60));
}

(async () => {
  const fresco = { properties: rpc.concat([]), settings: {}, downloads: [], live: true, stale: false };
  const viejo = { properties: rpc.concat([]), settings: {}, downloads: [], live: true, stale: true };

  // 1. listado fresco: chips y precios
  let r = await arranca(fresco);
  ok(/lw-prop-state st-ok/.test(r.html) && />Available</.test(r.html), 'fresco: hay chip de estado');
  ok(!r.llamadas.some(u => /supabase|data\.json/.test(u)), 'ninguna llamada a Supabase ni a data.json: ' + JSON.stringify(r.llamadas));

  // 2. ficha fresca de Palm Field: bloque Availability con 36 parcelas, 25 libres enlazadas al configurador
  r = await arranca(fresco, { hash: '#property/palm-field-bali' });
  ok(/class="avail"/.test(r.html) && /<b>25<\/b> of 36 plots available/.test(r.html), 'ficha fresca: bloque Availability 25 of 36');
  ok((r.html.match(/pl pl-ok pl-link/g) || []).length === 25, 'ficha fresca: 25 parcelas libres clicables');
  ok(/Units<\/[^>]+>[^<]*<[^>]+>[^<]*25 ?\/ ?36|25\/36/.test(r.html), 'ficha fresca: Units 25/36');

  // 3. DATO VIEJO (stale): nada afirma disponibilidad, ni tarjetas, ni bloque, ni units, ni pines, ni detalle
  const conMasterplan = palm();
  conMasterplan.masterplanImage = '/x.webp';
  conMasterplan.masterplanPlots = [{ code: 'A2', x: 10, y: 10 }, { code: 'A1', x: 20, y: 20 }];
  conMasterplan.unitsAvailable = 23; // el respaldo trae contadores escritos a mano
  const afirmaSinDato = (nombre, html) => {
    ok(/class="avail av-na"/.test(html) && /can't confirm availability/.test(html), nombre + ': bloque «no podemos confirmar»');
    ok(!/class="pl /.test(html) && !/of 36 plots available/.test(html), nombre + ': ninguna parcela ni contador');
    ok(!/mp-pin mp-ok/.test(html) && !/mp-pin mp-gone/.test(html) && !/mp-pin mp-held/.test(html), nombre + ': ningun pin con estado afirmado');
    ok(!/23 ?\/ ?36/.test(html), nombre + ': unitsAvailable escrito a mano no sale');
    ok(!/>Available</.test(html.replace(/Ask about availability|Ask for availability/g, '')), nombre + ': ningun «Available» suelto: ' + (html.match(/.{30}>Available<.{10}/) || [''])[0]);
  };
  r = await arranca({ properties: [conMasterplan], settings: {}, downloads: [], live: true, stale: true }, { hash: '#property/palm-field-bali' });
  afirmaSinDato('stale del servidor', r.html);
  ok(/mp-pin mp-unknown/.test(r.html), 'stale: los pines del masterplan salen «unknown»');
  ok(/Ask for availability/.test(r.html) || /can't confirm/.test(r.html), 'stale: se dice que se consulte');

  // 4. la edad cuenta: fresco al cargar; 31 min despues, al repintar, se degrada TODO (tarjetas, bloque, pines, units)
  const coherente = Object.assign({}, conMasterplan, { unitsAvailable: 25 });
  r = await arranca({ properties: [coherente], settings: {}, downloads: [], live: true, stale: false }, { hash: '#property/palm-field-bali' });
  ok(/class="avail"/.test(r.html) && /mp-pin mp-ok/.test(r.html), 'caso 4: fresco al cargar (bloque y pines con estado)');
  afirmaSinDato('31 min despues', r.pasa(31 * 60 * 1000));
  // contadores que no cuadran (unitsAvailable=23 vs 25 parcelas libres) con dato fresco: tampoco se afirma
  r = await arranca({ properties: [conMasterplan], settings: {}, downloads: [], live: true, stale: false }, { hash: '#property/palm-field-bali' });
  ok(/class="avail av-na"/.test(r.html), 'contadores que no cuadran: «no podemos confirmar»');

  // 5. ficha sin unidades cargadas (owner 6-oct): chip «Ask for availability» en el listado y NINGUN bloque Availability
  //    en la ficha (un «no podemos confirmar ahora» seria falso: no es un fallo, no hay datos); en la ficha, nada de «0/0».
  r = await arranca(fresco);
  ok((r.html.match(/lw-prop-state st-na/g) || []).length >= 2, 'sin unidades: chip st-na en el listado (riverfront-iii y rurung-anyar)');
  r = await arranca(fresco, { hash: '#property/riverfront-iii' });
  ok(!/class="avail/.test(r.html), 'sin unidades: la ficha no pinta bloque Availability');
  ok(!/0 ?\/ ?0|0 of 0/.test(r.html), 'sin unidades: ningun «0/0» ni «0 of 0»');

  // 6. QUE FICHAS SE VEN (14-oct-2026), con la fuente de hoy (data.json en crudo, que trae tambien las ocultas).
  //    Solo `visible: true` con id valido. Antes la rejilla pintaba todo lo que no fuera exactamente false (una ficha
  //    sin la clave, con null, con "false" en texto...) y la ficha abierta por #property/<id> no se filtraba: un
  //    borrador oculto se abria por su enlace mientras /property/<id> respondia 404.
  const f = (id, visible, extra) => Object.assign({ id, line: 'villa', region: 'Bali', regionKey: 'bali', priceEUR: 100000,
    title: { en: 'TITULO-' + id }, sub: { en: 's' }, desc: { en: 'd' }, images: [] }, visible === undefined ? {} : { visible }, extra || {});
  const crudo = { settings: {}, downloads: {}, properties: [
    f('vista-a', true), f('vista-b', true, { featured: true }),
    f('oculta', false, { featured: true }), f('sin-clave'), f('nula', null), f('texto-true', 'true'), f('texto-false', 'false'),
    f('uno-num', 1), f('cero-num', 0), f('mal id', true) ] };
  const NO = ['oculta', 'sin-clave', 'nula', 'texto-true', 'texto-false', 'uno-num', 'cero-num', 'mal id'];
  r = await arranca(crudo, { datajson: true });
  ok(r.llamadas.some(u => /^data\.json/.test(u)), 'datajson: la SPA baja data.json');
  ok(/TITULO-vista-a/.test(r.html) && /TITULO-vista-b/.test(r.html), 'datajson: las dos fichas publicadas salen en la rejilla');
  for (const id of NO) ok(!r.html.includes('TITULO-' + id), 'datajson: «' + id + '» NO sale en la rejilla ni como destacada');
  ok((r.html.match(/<article class="lw-prop/g) || []).length === 2, 'datajson: 2 tarjetas en la rejilla, las 2 publicadas: ' + (r.html.match(/<article class="lw-prop/g) || []).length);
  for (const id of ['oculta', 'sin-clave', 'nula', 'texto-true']) {
    r = await arranca(crudo, { datajson: true, hash: '#property/' + id });
    ok(/Property not found\./.test(r.html) && !r.html.includes('TITULO-' + id), 'datajson: #property/' + id + ' no abre una ficha que no esta publicada');
  }
  r = await arranca(crudo, { datajson: true, hash: '#property/vista-a' });
  ok(r.html.includes('TITULO-vista-a') && !/Property not found\./.test(r.html), 'datajson: #property/vista-a abre la ficha publicada');
  ok(r.html.includes('TITULO-vista-b'), 'datajson: «mas en esta linea» enseña la otra publicada');
  for (const id of NO) ok(!r.html.includes('TITULO-' + id), 'datajson: «mas en esta linea» no enseña «' + id + '»');
  // catalogo que llega pero sin ninguna ficha publicada: «no hay nada», no «no se pudo cargar»
  r = await arranca({ settings: {}, downloads: {}, properties: [f('oculta', false)] }, { datajson: true });
  ok(/No properties match these filters\./.test(r.html) && !/could not be loaded/.test(r.html), 'catalogo sin fichas publicadas: «no hay», no «no se pudo cargar»');
  const errorDeConsola = console.error;
  const avisos = [];
  console.error = (...a) => avisos.push(a.join(' '));   // la SPA avisa por consola de que no pudo cargar: se recoge, no se imprime
  try { r = await arranca('esto no es un catalogo', { datajson: true }); } finally { console.error = errorDeConsola; }
  ok(/Properties could not be loaded\./.test(r.html), 'data.json ilegible: «no se pudo cargar»');
  ok(avisos.length === 1 && /no se pudo cargar data\.json/.test(avisos[0]), 'data.json ilegible: lo dice por consola una vez: ' + JSON.stringify(avisos));

  if (fallos) { console.log(fallos + ' FALLO(S)'); process.exit(1); }
  console.log('OK: SPA en vivo (fresco pinta estado; stale y dato viejo nunca afirman disponible; sin llamadas a Supabase) y regla unica de fichas visibles.');
})();
