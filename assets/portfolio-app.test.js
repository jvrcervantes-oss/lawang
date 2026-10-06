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

function arranca(doc, { hash = '' } = {}) {
  const llamadas = [];
  const el = () => ({ style: {}, classList: { add() {}, remove() {}, toggle() {}, contains() { return false; } }, setAttribute() {}, addEventListener() {}, querySelector() { return null; }, querySelectorAll() { return []; } });
  const root = Object.assign(el(), { innerHTML: '' });
  const ahora = Date.now();
  let off = 0;
  const Dt = { now: () => ahora + off };
  const win = {
    LW_COLECCION_PRELOAD: doc, LW_COLECCION_V2: true, LW_LANG: 'en', addEventListener() {}, scrollTo() {}, scrollY: 0,
    location: { pathname: '/thecollection-v2', hash, search: '' }, history: { pushState() {}, replaceState() {} },
    sessionStorage: { getItem() { return null; }, setItem() {} }, localStorage: { getItem() { return null; }, setItem() {} },
    requestAnimationFrame: f => f(), performance: { getEntriesByType: () => [] }
  };
  const documento = Object.assign(el(), { getElementById: id => (id === 'portfolio-root' ? root : null), documentElement: el(), body: el(), readyState: 'complete', title: '',
    querySelectorAll: () => [], querySelector: () => null, addEventListener() {} });
  win.document = documento; win.window = win;
  win.fetch = u => { llamadas.push(String(u)); return Promise.resolve({ ok: true, json: () => Promise.resolve({ result: 'x' }), text: () => Promise.resolve('') }); };
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

  if (fallos) { console.log(fallos + ' FALLO(S)'); process.exit(1); }
  console.log('OK: SPA en vivo (fresco pinta estado; stale y dato viejo nunca afirman disponible; sin llamadas a Supabase).');
})();
