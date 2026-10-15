// La cifra que cuenta es un adorno, nunca el dato (motion.js → cuenta(), 15-oct-2026, Calidad).
//   node motion.test.js [ruta a otro motion.js]     (sin ruta, el motion.js de al lado)
//
// Por qué: cuenta() escribía «0» en el TEXTO real de cada contador [data-lw^="k-"] y lo subía con
// requestAnimationFrame. Hasta el primer fotograma —y para siempre en una pestaña oculta, donde rAF no corre—
// el contador decía 0 con el dato real al lado (Experiencia, Usuarios de bbm, 14-oct: «0 activos» con 2 en la
// lista). Se ejecuta el código de verdad (trozo de motion.js) con un DOM mínimo, rAF y temporizadores a mano.
// Casos: A pestaña oculta → no anima y el texto sigue siendo el dato · B visible → el texto es el dato TODO el
// tiempo, la cifra animada va en una capa aria-hidden y al acabar no queda capa ni estilos · C otra escritura a
// media animación manda · D la pestaña se oculta a medias → se termina en el acto · E rAF parado → el
// temporizador de seguridad destapa el dato.
// Con el motion.js de antes del arreglo (git show <sha>:intranet/v4/assets/motion.js > viejo.js) TIENE que fallar.
'use strict';
const fs = require('fs'), path = require('path'), vm = require('vm'), assert = require('assert');
const ruta = process.argv[2] || path.join(__dirname, 'motion.js');
const src = fs.readFileSync(ruta, 'utf8');
const a = src.indexOf('  var NUM = '), b = src.indexOf('  function entra() {');
assert.ok(a > 0 && b > a, 'no encuentro cuenta() en ' + ruta);
const TROZO = src.slice(a, b) + '\nthis.cuenta = cuenta;';

function nodo(tag) {
  const n = { tag, parentNode: null, hijos: [], attrs: {}, style: {}, _texto: '', className: '' };
  n.setAttribute = (k, v) => { n.attrs[k] = String(v); };
  n.getAttribute = (k) => (k in n.attrs ? n.attrs[k] : null);
  n.appendChild = (c) => { c.parentNode = n; n.hijos.push(c); return c; };
  n.removeChild = (c) => { n.hijos = n.hijos.filter((x) => x !== c); c.parentNode = null; return c; };
  Object.defineProperty(n, 'textContent', {
    get: () => n._texto + n.hijos.map((c) => c.textContent).join(''),   // la capa no tiene texto propio (lo pinta ::after)
    set: (v) => { n.hijos.forEach((c) => { c.parentNode = null; }); n.hijos = []; n._texto = String(v); }
  });
  Object.defineProperty(n, 'isConnected', { get: () => n.tag === 'main' || (!!n.parentNode && n.parentNode.isConnected) });
  return n;
}
function mundo(oculta) {
  const raf = [], timers = [], oyentes = {};
  let ahora = 1000;
  const main = nodo('main'), el = nodo('span');
  main.appendChild(el); el.textContent = '2';
  const document = {
    hidden: oculta, head: nodo('head'),
    createElement: (t) => nodo(t),
    addEventListener: (ev, f) => { (oyentes[ev] = oyentes[ev] || []).push(f); },
    removeEventListener: (ev, f) => { oyentes[ev] = (oyentes[ev] || []).filter((x) => x !== f); }
  };
  const ctx = {
    document, performance: { now: () => ahora },
    requestAnimationFrame: (f) => { raf.push(f); return raf.length; },
    setTimeout: (f, ms) => { timers.push({ f, en: ahora + ms }); return timers.length; },
    getComputedStyle: () => ({ color: 'rgb(10, 20, 30)', textAlign: 'left', position: 'static' }),
    Math, String, parseInt
  };
  vm.createContext(ctx);
  vm.runInContext(TROZO, ctx);
  const w = {
    el, ctx, document,
    fotograma(ms) { ahora += ms; const fs2 = raf.splice(0); fs2.forEach((f) => f(ahora)); },
    reloj(ms) { ahora += ms; timers.filter((t) => t.en <= ahora && !t.hecho).forEach((t) => { t.hecho = true; t.f(); }); },
    oculta() { document.hidden = true; (oyentes.visibilitychange || []).slice().forEach((f) => f()); },
    capa() { return el.hijos.find((c) => c.className === 'lw-cifra-capa') || null; },
    limpio() { return !w.capa() && !el.style.color && !el.style.position && !el.style.fontVariantNumeric; }
  };
  return w;
}

let fallos = 0;
const ok = (n, c, extra) => { if (!c) { fallos++; console.log('FALLA  ' + n + (extra !== undefined ? ' → ' + JSON.stringify(extra) : '')); } else console.log('ok     ' + n); };

// A · pestaña oculta y rAF que nunca llega
let w = mundo(true);
const animaOculta = w.ctx.cuenta(w.el, 0);
ok('A oculta: el texto sigue siendo el dato', w.el.textContent === '2', w.el.textContent);
ok('A oculta: no anima ni deja capa ni estilos', !animaOculta && w.limpio(), { anima: animaOculta, style: w.el.style });

// B · visible: el texto es el dato todo el tiempo; la cifra animada, en una capa aria-hidden
w = mundo(false);
const anima = w.ctx.cuenta(w.el, 0);
ok('B visible: anima', anima === true);
ok('B visible: justo después el texto es el dato (no «0»)', w.el.textContent === '2', w.el.textContent);
const capa = w.capa();
ok('B la cifra animada va en una capa aria-hidden', !!capa && capa.getAttribute('aria-hidden') === 'true', capa && capa.attrs);
ok('B la capa empieza en 0 y lleva el color del dato', !!capa && capa.getAttribute('data-v') === '0' && capa.style.color === 'rgb(10, 20, 30)', capa && [capa.attrs, capa.style]);
let siempre = true;
for (let i = 0; i < 80; i++) { w.fotograma(16); if (w.el.textContent !== '2') siempre = false; }
ok('B el texto no deja de ser el dato en ningún fotograma', siempre);
ok('B al acabar no queda capa y los estilos vuelven', w.limpio(), { capa: !!w.capa(), style: w.el.style });

// C · otra escritura a media animación manda
w = mundo(false); w.ctx.cuenta(w.el, 0); w.fotograma(16); w.fotograma(16);
w.el.textContent = '5'; w.fotograma(16);
ok('C otra escritura: se queda el dato nuevo, sin capa ni estilos', w.el.textContent === '5' && w.limpio(), { t: w.el.textContent, style: w.el.style });

// D · la pestaña se oculta a medias → se termina en el acto
w = mundo(false); w.ctx.cuenta(w.el, 0); w.fotograma(16);
w.oculta();
ok('D se oculta a medias: termina en el acto (sin capa ni estilos)', w.el.textContent === '2' && w.limpio(), { capa: !!w.capa(), style: w.el.style });

// E · rAF parado: el temporizador de seguridad destapa el dato
w = mundo(false); w.ctx.cuenta(w.el, 0);
w.reloj(900 + 1600);
ok('E rAF parado: a los 2,5 s no queda capa ni el dato transparente', w.el.textContent === '2' && w.limpio(), { capa: !!w.capa(), style: w.el.style });

console.log(fallos ? `motion.test.js: ${fallos} FALLO(S)` : 'motion.test.js OK (cuenta(): el dato siempre en el texto)');
process.exit(fallos ? 1 : 0);
