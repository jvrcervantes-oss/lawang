// motion.test.js — lo puro de motion.js: qué perfil entra en cada pantalla, cómo recorre una cifra y cuándo
// cambia la clave que decide si se anima. Lo visual lo cubre el arnés de capturas.
const M = require('./motion.js');
let fallos = 0;
function ok(c, m) { if (!c) { fallos++; console.error('FALLO:', m); } }

// perfiles de la intranet: B la primera vez de Inicio, D en dinero, A el resto
ok(M.perfil('inicio', []) === 'B', 'Inicio la primera vez entra con B');
ok(M.perfil('inicio', ['inicio']) === 'A', 'Inicio después entra con A');
ok(M.perfil('facturas', []) === 'D', 'Facturas es siempre D, también la primera vez');
ok(M.perfil('facturas', ['inicio']) === 'D', 'Facturas sigue siendo D');
['contratos', 'obra', 'documentos', 'soporte', 'perfil'].forEach(s => ok(M.perfil(s, []) === 'A', s + ' entra con A'));

// la cifra: empieza en 0, acaba EXACTA y nunca pasa del final ni baja
ok(M.valorCuenta(19000, 0) === 0, 'k=0 → 0');
ok(M.valorCuenta(19000, 1) === 19000, 'k=1 → el valor exacto, sin decimales de más');
ok(M.valorCuenta(19000, 1.5) === 19000, 'k>1 → el valor exacto');
ok(M.valorCuenta(19000, -1) === 0, 'k<0 → 0');
let prev = -1;
for (let k = 0; k <= 1.0001; k += 0.05) { const v = M.valorCuenta(123456.78, Math.min(1, k)); ok(v >= prev && v <= 123456.78, 'monótona y acotada en k=' + k); prev = v; }
ok(M.valorCuenta(0, 0.5) === 0, 'un importe 0 sigue en 0');

// la clave: solo cambia al cambiar de sección o de carpeta; un repintado por idioma o datos no la cambia
ok(M.claveVista('inicio', null) === 'inicio|', 'inicio no depende de la carpeta');
ok(M.claveVista('inicio', 'abc') === 'inicio|', 'una carpeta en otra sección se ignora');
ok(M.claveVista('documentos', null) === 'documentos|', 'documentos sin carpeta');
ok(M.claveVista('documentos', 'pf') !== M.claveVista('documentos', null), 'abrir una carpeta cambia la clave');
ok(M.claveVista('documentos', 'pf') !== M.claveVista('documentos', 'sh'), 'cambiar de carpeta cambia la clave');
ok(M.claveVista('documentos', 'pf') === M.claveVista('documentos', 'pf'), 'repintar la misma carpeta NO cambia la clave');

// sin navegador no hace nada ni falla
ok(M.puede() === false, 'en node no hay animate: puede() es false');
M.pantalla(null, 'inicio'); M.menu(null); M.campana(null, 3); M.abrePanel(null);
let llamado = false; M.cajon(null, null, true, () => { llamado = true; });
ok(llamado, 'cajon sin animación llama igualmente a fin');
// las piezas nuevas, sin navegador, tampoco hacen nada ni fallan; el aviso dice que no ha animado
M.selectores(null); M.recuerdaPortada(null);
let pintado = false; M.reordena(null, () => { pintado = true; }, 'data-doc');
ok(pintado, 'reordena sin movimiento pinta igualmente');
ok(M.aviso(null, true) === false, 'aviso sin movimiento devuelve false (el portal sigue con su fundido)');

// el recorte de la foto de la tarjeta dentro de la portada: la ventana exacta, nunca negativa
const dest = { top: 100, right: 500, bottom: 400, left: 50 };
ok(M.recorte({ top: 110, right: 300, bottom: 200, left: 100 }, dest, 12) === 'inset(10px 200px 200px 50px round 12px)', 'recorte de una tarjeta dentro de la portada');
ok(M.recorte(dest, dest) === 'inset(0px 0px 0px 0px round 0px)', 'la misma caja: sin recorte');
ok(M.recorte({ top: 20, right: 600, bottom: 450, left: 0 }, dest, 8) === 'inset(0px 0px 0px 0px round 8px)', 'una tarjeta más grande que la portada no da recortes negativos');

// cuenta() con DOM (15-oct-2026, Calidad): el importe es SIEMPRE el texto; lo que cuenta es una capa aria-hidden encima.
// Antes escribía fmt(0) en el propio texto: el importe decía 0 hasta el primer fotograma y, con la pestaña oculta, hasta el
// temporizador. Se ejecuta el trozo real de motion.js (del comentario «El dinero que se recorre» a «Entrada de una pantalla»).
// `node motion.test.js <otro motion.js>` lo corre sobre otro fichero: con el de antes del arreglo TIENE que fallar.
(function () {
  const fs = require('fs'), path = require('path'), vm = require('vm');
  const src = fs.readFileSync(process.argv[2] || path.join(__dirname, 'motion.js'), 'utf8');
  const a = src.indexOf('  /* El dinero que se recorre'), b = src.indexOf('  /* Entrada de una pantalla');
  if (!(a > 0 && b > a)) { fallos++; console.error('FALLO: no encuentro cuenta() en motion.js'); return; }
  function nodo(tag) {
    const n = { tag, parentNode: null, hijos: [], attrs: {}, style: {}, _t: '', className: '' };
    n.setAttribute = (k, v) => { n.attrs[k] = String(v); };
    n.getAttribute = (k) => (k in n.attrs ? n.attrs[k] : null);
    n.appendChild = (c) => { c.parentNode = n; n.hijos.push(c); return c; };
    n.removeChild = (c) => { n.hijos = n.hijos.filter((x) => x !== c); c.parentNode = null; return c; };
    Object.defineProperty(n, 'textContent', {
      get: () => n._t + n.hijos.map((c) => c.textContent).join(''),
      set: (v) => { n.hijos.forEach((c) => { c.parentNode = null; }); n.hijos = []; n._t = String(v); }
    });
    Object.defineProperty(n, 'isConnected', { get: () => n.tag === 'main' || (!!n.parentNode && n.parentNode.isConnected) });
    return n;
  }
  function mundo(oculta) {
    const raf = [], timers = [], oyentes = {};
    let ahora = 0;
    const main = nodo('main'), el = nodo('b');
    main.appendChild(el); el.textContent = '19.000 €'; el.setAttribute('data-cuenta', '19000');
    const document = { hidden: oculta, head: nodo('head'), createElement: (t) => nodo(t),
      addEventListener: (e, f) => { (oyentes[e] = oyentes[e] || []).push(f); },
      removeEventListener: (e, f) => { oyentes[e] = (oyentes[e] || []).filter((x) => x !== f); } };
    const root = { document, requestAnimationFrame: (f) => { raf.push(f); return raf.length; },
      setTimeout: (f, ms) => { timers.push({ f, en: ahora + ms }); return timers.length; },
      getComputedStyle: () => ({ color: 'rgb(1, 2, 3)', textAlign: 'right', position: 'static', paddingTop: '2px', paddingRight: '8px', paddingBottom: '2px', paddingLeft: '8px' }) };
    const ctx = { root, M: { formatoDinero: (v) => Math.round(v) + ' €' }, valorCuenta: M.valorCuenta, Math, Number, isFinite, String };
    vm.createContext(ctx);
    vm.runInContext(src.slice(a, b) + '\nthis.cuenta = cuenta;', ctx);
    const w = { el, cuenta: ctx.cuenta,
      reloj(ms) { ahora += ms; timers.filter((t) => t.en <= ahora && !t.hecho).forEach((t) => { t.hecho = true; t.f(); }); },
      fotograma(ms) { w.reloj(ms); raf.splice(0).forEach((f) => f(ahora)); },
      oculta() { document.hidden = true; (oyentes.visibilitychange || []).slice().forEach((f) => f()); },
      capa() { return el.hijos.find((c) => c.className === 'lw-cifra-capa') || null; },
      limpio() { return !w.capa() && !el.style.color && !el.style.position && !el.style.fontVariantNumeric; } };
    return w;
  }
  let w = mundo(true); w.cuenta(w.el, 0);
  ok(w.el.textContent === '19.000 €' && w.limpio(), 'cuenta, pestaña oculta: el importe se queda y no anima (era «0 €»)');
  w = mundo(false); w.cuenta(w.el, 220);
  ok(w.el.textContent === '19.000 €', 'cuenta, visible: nada más llamar, el texto es el importe (era «0 €»)');
  const capa = w.capa();
  ok(!!capa && capa.getAttribute('aria-hidden') === 'true' && capa.getAttribute('data-v') === '0 €', 'cuenta: la cifra que sube va en una capa aria-hidden que empieza en 0');
  let siempre = true;
  for (let i = 0; i < 80; i++) { w.fotograma(16); if (w.el.textContent !== '19.000 €') siempre = false; }
  ok(siempre, 'cuenta: el texto es el importe en todos los fotogramas');
  ok(w.limpio(), 'cuenta: al acabar no queda capa ni estilos');
  w = mundo(false); w.cuenta(w.el, 0); w.fotograma(16); w.fotograma(16); w.el.textContent = '20.000 €'; w.fotograma(16);
  ok(w.el.textContent === '20.000 €' && w.limpio(), 'cuenta: si se repinta a medias, manda lo nuevo y no queda capa');
  w = mundo(false); w.cuenta(w.el, 0); w.fotograma(16); w.oculta();
  ok(w.el.textContent === '19.000 €' && w.limpio(), 'cuenta: si la pestaña se oculta a medias, termina en el acto');
  w = mundo(false); w.cuenta(w.el, 0);
  const cF = w.capa();
  ok(!!cF && cF.style.paddingLeft === '8px' && cF.style.paddingTop === '2px', 'cuenta: la capa copia el relleno del importe (si no, la cifra que sube va corrida)');
  w = mundo(false); w.cuenta(w.el, 0); w.fotograma(16); w.el.style.color = 'red'; w.el.style.position = 'absolute';
  for (let i = 0; i < 80; i++) w.fotograma(16);
  ok(w.el.style.color === 'red' && w.el.style.position === 'absolute' && !w.capa(), 'cuenta: si otro script cambió un estilo a medias, se queda el suyo');
  w = mundo(false); w.cuenta(w.el, 0); w.reloj(800 + 1600);
  ok(w.el.textContent === '19.000 €' && w.limpio(), 'cuenta: sin fotogramas, el temporizador destapa el importe');
})();

if (fallos) { console.error(fallos + ' fallo(s)'); process.exit(1); }
console.log('motion.test.js — OK');
