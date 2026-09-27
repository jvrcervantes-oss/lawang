/* node contracts/assets/version.test.js — aviso de pestaña con código viejo (LAW-386, 27-sep-2026).
   1) decide(): la decisión pura (con/sin huella, igual/distinta, 2ª lectura, ya recargué).
   2) version.js REAL en un sandbox con reloj falso: página H1 y servidor H2 → banda solo tras la
      segunda lectura; iguales → nada; un 403 → comprobación; tras recargar a H2 sin éxito → no insiste.
   3) El hecho contra todos los sitios donde vive: toda página que carga instancia.js carga
      version.js detrás, lleva su huella, y el generador avisa de que recargar pierde lo no guardado. */
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const { decide, extrae, TEXTOS } = require('./version.js');

// ── 1. decide() ─────────────────────────────────────────────────────────────
const cero = { pendiente: null, recargue: null, mostrada: false };
assert.strictEqual(decide(cero, { local: null, remota: 'b' }).accion, 'desconocido', 'sin huella local no se decide');
assert.strictEqual(decide(cero, { local: 'a', remota: null }).accion, 'desconocido', 'sin huella remota no se decide');
assert.strictEqual(decide(cero, { local: 'a', remota: 'a' }).accion, 'nada');
let d = decide(cero, { local: 'a', remota: 'b' });
assert.strictEqual(d.accion, 'confirmar', 'una sola lectura distinta no basta');
assert.strictEqual(d.estado.pendiente, 'b');
const d2 = decide(d.estado, { local: 'a', remota: 'b' });
assert.strictEqual(d2.accion, 'mostrar', 'la segunda lectura igual de distinta confirma');
assert.strictEqual(decide(d2.estado, { local: 'a', remota: 'b' }).accion, 'nada', 'la banda no se pone dos veces');
assert.strictEqual(decide(d.estado, { local: 'a', remota: 'c' }).accion, 'confirmar', 'otra huella distinta vuelve a esperar');
assert.strictEqual(decide(d.estado, { local: 'a', remota: 'a' }).estado.pendiente, null, 'si vuelve a cuadrar se olvida la sospecha');
assert.strictEqual(decide({ pendiente: 'b', recargue: 'b', mostrada: false }, { local: 'a', remota: 'b' }).accion, 'callar',
  'ya se recargó para ir a b y sigue sin cuadrar: no insiste');
assert.strictEqual(decide({ pendiente: null, recargue: 'b', mostrada: false }, { local: 'a', remota: 'c' }).accion, 'confirmar',
  'una huella nueva distinta de la recargada sí se avisa');
assert.strictEqual(extrae('<head>\n<meta name="lw-version" content="0a1b2c3d4e5f">'), '0a1b2c3d4e5f');
assert.strictEqual(extrae('<head><title>x</title>'), null);
assert.strictEqual(extrae(null), null);
for (const l of Object.keys(TEXTOS)) assert.ok(!/intranet/i.test(TEXTOS[l].msg + TEXTOS[l].pierde), 'texto neutro: portal y firma son del comprador');

// ── 2. version.js en un sandbox ──────────────────────────────────────────────
const CODIGO = fs.readFileSync(path.join(__dirname, 'version.js'), 'utf8');

function monta(opc) {
  let ahora = 1e12;
  const timers = [];
  const oyentes = {};
  const hijos = [];
  const store = Object.assign({}, opc.store || {});
  const pedidas = [];
  const infos = [];
  let recargas = 0;
  function el(tag) {
    return { tagName: tag, style: {}, hijos: [], attrs: {}, _ev: {}, textContent: '',
      setAttribute(k, v) { this.attrs[k] = v; }, appendChild(h) { this.hijos.push(h); return h; },
      addEventListener(n, f) { this._ev[n] = f; } };
  }
  const body = el('body');
  body.appendChild = (h) => { hijos.push(h); return h; };
  const doc = {
    visibilityState: 'visible', body, documentElement: { getAttribute: () => opc.lang || 'es' },
    currentScript: { hasAttribute: (a) => (opc.attrs || []).includes(a) },
    querySelector: (s) => (s === 'meta[name="lw-version"]' && opc.local ? { getAttribute: () => opc.local } : null),
    getElementById: (id) => hijos.find((h) => h.id === id) || null,
    createElement: el,
    addEventListener: (n, f) => { (oyentes['doc:' + n] = oyentes['doc:' + n] || []).push(f); }
  };
  const win = {
    document: doc, LW_IDIOMA: opc.idioma,
    location: { pathname: '/contracts/app.html', reload: () => { recargas++; } },
    sessionStorage: { getItem: (k) => (k in store ? store[k] : null), setItem: (k, v) => { store[k] = String(v); }, removeItem: (k) => { delete store[k]; } },
    fetch: (url, init) => {
      pedidas.push({ url, init });
      const r = typeof opc.servidor === 'function' ? opc.servidor() : opc.servidor;
      if (r === 'red') return Promise.reject(new Error('offline'));
      const [status, html] = r;
      return Promise.resolve({ ok: status >= 200 && status < 300, status, text: () => Promise.resolve(html) });
    },
    addEventListener: (n, f) => { (oyentes[n] = oyentes[n] || []).push(f); },
    dispatchEvent: (e) => { (oyentes[e.type] || []).forEach((f) => f(e)); }
  };
  const sandbox = {
    window: win, JSON, Promise, Object, String,
    Date: { now: () => ahora },
    setTimeout: (f, ms) => { const t = { f, en: ahora + ms }; timers.push(t); return t; },
    clearTimeout: (t) => { const i = timers.indexOf(t); if (i >= 0) timers.splice(i, 1); },
    console: { info: (m) => infos.push(m) }
  };
  vm.createContext(sandbox);
  vm.runInContext(CODIGO, sandbox);
  const flush = () => new Promise((r) => setImmediate(r));
  return {
    win, doc, store, pedidas, infos, hijos, recargas: () => recargas,
    async avanza(ms) {
      ahora += ms;
      for (;;) {
        await flush(); await flush();
        const t = timers.filter((x) => x.en <= ahora).sort((a, b) => a.en - b.en)[0];
        if (!t) break;
        timers.splice(timers.indexOf(t), 1);
        t.f();
      }
      await flush(); await flush();
    },
    async vuelve() { (oyentes['doc:visibilitychange'] || []).forEach((f) => f()); await flush(); await flush(); await flush(); },
    async error(status) { win.dispatchEvent({ type: 'lw:version-vieja', detail: { status } }); await flush(); await flush(); await flush(); },
    banda() { return hijos.find((h) => h.id === 'lw-version-banda') || null; }
  };
}
const pag = (h) => [200, '<!doctype html><html><head>\n<meta name="lw-version" content="' + h + '">\n</head></html>'];

(async () => {
  // H1 en la página, H2 en el servidor: banda SOLO tras la segunda lectura
  let s = monta({ local: 'aaaaaaaaaaaa', servidor: pag('bbbbbbbbbbbb'), attrs: ['data-pierde-al-recargar'] });
  await s.vuelve();
  assert.strictEqual(s.pedidas.length, 0, 'recién cargada no pregunta: máximo una vez cada 5 min');
  await s.avanza(5 * 60 * 1000);
  await s.vuelve();
  assert.strictEqual(s.pedidas.length, 1, 'al volver pasados 5 min, una lectura');
  assert.ok(/^\/contracts\/app\.html\?lwv=\d+$/.test(s.pedidas[0].url), s.pedidas[0].url);
  assert.strictEqual(s.pedidas[0].init.cache, 'no-store');
  assert.strictEqual(s.banda(), null, 'una lectura distinta no pone banda (git pull a medias)');
  await s.avanza(30 * 1000);
  assert.strictEqual(s.pedidas.length, 2, 'segunda lectura a los 30 s');
  const b = s.banda();
  assert.ok(b, 'confirmada: banda');
  const texto = b.hijos[0].hijos.map((p) => p.textContent).join(' ');
  assert.ok(texto.includes('Hay una versión nueva') && texto.includes('se pierde lo que no esté guardado'), texto);
  assert.strictEqual(s.recargas(), 0, 'NUNCA recarga sola');
  b.hijos[1]._ev.click();
  assert.strictEqual(s.recargas(), 1);
  assert.deepStrictEqual(JSON.parse(s.store.lw_version_recargue), { ruta: '/contracts/app.html', h: 'bbbbbbbbbbbb' });

  // tras recargar, la página sigue siendo H1 (caché intermedia): no insiste
  const s2 = monta({ local: 'aaaaaaaaaaaa', servidor: pag('bbbbbbbbbbbb'), store: s.store });
  await s2.error(403);
  await s2.avanza(30 * 1000);
  assert.strictEqual(s2.banda(), null, 'ya recargó para ir a bbbb: no hay bucle');
  assert.ok(s2.infos.some((m) => /no insisto/.test(m)), 'pero lo dice en consola');
  // la recarga sí trajo H2: se olvida la marca
  const s3 = monta({ local: 'bbbbbbbbbbbb', servidor: pag('bbbbbbbbbbbb'), store: Object.assign({}, s.store) });
  assert.strictEqual(s3.store.lw_version_recargue, undefined, 'recarga con éxito: se borra la marca');

  // iguales: nada
  s = monta({ local: 'aaaaaaaaaaaa', servidor: pag('aaaaaaaaaaaa') });
  await s.error(403);
  await s.avanza(60 * 1000);
  assert.strictEqual(s.pedidas.length, 1, 'un 403 comprueba enseguida (sin esperar los 5 min)');
  assert.strictEqual(s.banda(), null);

  // 403 → comprobación; varios seguidos → una sola; distinta dos veces → banda en inglés
  s = monta({ local: 'aaaaaaaaaaaa', servidor: pag('cccccccccccc'), idioma: 'en' });
  await s.error(403); await s.error(401); await s.error(404);
  assert.strictEqual(s.pedidas.length, 1, 'errores seguidos: una comprobación (máx. 1 por minuto)');
  await s.avanza(30 * 1000);
  assert.ok(s.banda() && /new version/.test(s.banda().hijos[0].hijos[0].textContent), 'idioma de la página');

  // firma del comprador: bilingüe
  s = monta({ local: 'aaaaaaaaaaaa', servidor: pag('cccccccccccc'), attrs: ['data-bilingue'] });
  await s.error(403); await s.avanza(30 * 1000);
  assert.strictEqual(s.banda().hijos[0].hijos.length, 2, 'firma: ES + EN');

  // sin huella en el servidor, 404 o sin red: silencio para la persona, info en consola
  for (const serv of [[200, '<html><head></head></html>'], [404, 'no'], 'red']) {
    s = monta({ local: 'aaaaaaaaaaaa', servidor: serv });
    await s.error(403); await s.avanza(30 * 1000);
    assert.strictEqual(s.banda(), null, 'no se ha podido mirar: nada en pantalla');
    assert.ok(s.infos.length >= 1, 'pero una comprobación que no pudo mirar lo dice');
  }
  // página sin huella: no pregunta nunca
  s = monta({ local: null, servidor: pag('cccccccccccc') });
  await s.error(403); await s.avanza(10 * 60 * 1000); await s.vuelve();
  assert.strictEqual(s.pedidas.length, 0);

  // comprueba(): una lectura para el mensaje de error del generador
  s = monta({ local: 'aaaaaaaaaaaa', servidor: pag('cccccccccccc') });
  assert.strictEqual(await s.win.lwVersion.comprueba(5000), 'vieja');
  assert.strictEqual(s.banda(), null, 'el mensaje no espera; la banda sí espera su segunda lectura');
  await s.avanza(30 * 1000);
  assert.ok(s.banda(), 'y a los 30 s la banda');
  s = monta({ local: 'aaaaaaaaaaaa', servidor: pag('aaaaaaaaaaaa') });
  assert.strictEqual(await s.win.lwVersion.comprueba(5000), 'igual', 'si cuadra, el permiso falta de verdad');
  s = monta({ local: 'aaaaaaaaaaaa', servidor: 'red' });
  assert.strictEqual(await s.win.lwVersion.comprueba(5000), 'desconocido');

  // ── 3. el hecho contra todas las páginas ────────────────────────────────────
  const RAIZ = path.join(__dirname, '..', '..');
  const FUERA = new Set(['Backups', '_archive', 'node_modules', '.git']);
  const paginas = [];
  (function recorre(dir) {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      if (FUERA.has(e.name)) continue;
      const p = path.join(dir, e.name);
      if (e.isDirectory()) recorre(p);
      else if (/\.(html|php)$/.test(e.name) && !e.name.startsWith('_qa_')) paginas.push(p);
    }
  })(RAIZ);
  let n = 0;
  for (const p of paginas) {
    const t = fs.readFileSync(p, 'utf8');
    if (!t.includes('/contracts/assets/instancia.js')) continue;
    n++;
    const rel = path.relative(RAIZ, p).split(path.sep).join('/');
    const iI = t.indexOf('/contracts/assets/instancia.js');
    const iV = t.indexOf('/contracts/assets/version.js?v=');
    assert.ok(iV > iI, rel + ': carga instancia.js y no version.js detrás');
    const iG = t.indexOf('/contracts/assets/guard.js');
    assert.ok(iG < 0 || iV < iG, rel + ': version.js tiene que ir antes de guard.js');
    assert.ok(!/version\.js\?v=[^"]*"[^>]*\b(defer|async)\b/.test(t), rel + ': version.js sin defer');
    assert.ok(extrae(t), rel + ': sin huella lw-version (python tools/sella_assets.py)');
  }
  assert.ok(n >= 45, 'páginas con instancia.js: ' + n);
  const app = fs.readFileSync(path.join(RAIZ, 'contracts', 'app.html'), 'utf8');
  assert.ok(/version\.js\?v=[^"]+" data-pierde-al-recargar/.test(app), 'el generador pierde lo no guardado al recargar: la banda lo tiene que decir');
  const firmar = fs.readFileSync(path.join(RAIZ, 'contracts', 'firmar.html'), 'utf8');
  assert.ok(/version\.js\?v=[^"]+" data-bilingue/.test(firmar), 'la firma del comprador es bilingüe');

  // los ganchos de guard.js: fetchContado + las tres edges de ficheros que usan fetch directo
  const guard = fs.readFileSync(path.join(__dirname, 'guard.js'), 'utf8');
  assert.strictEqual((guard.match(/sospechaVersion\((?:r|res)\.status\)/g) || []).length, 4,
    'guard.js avisa de 401/403/404 en fetchContado, lwFicheros, lwKyc y lwFichero');
  assert.ok(/'lw:version-vieja'/.test(guard) && /raiz\.addEventListener\('lw:version-vieja'/.test(CODIGO),
    'el evento que emite guard.js es el que escucha version.js');

  console.log('version.test.js OK (' + n + ' páginas con instancia.js, todas con version.js y huella)');
})().catch((e) => { console.error(e); process.exit(1); });
