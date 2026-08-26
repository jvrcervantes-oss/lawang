/* node contracts/assets/paginacion.test.js
   Los tres fallos clásicos de un paginador, que no dan error cuando ocurren:
   la página huérfana al filtrar, el recorte silencioso y el pie que se queda
   puesto cuando ya no hace falta. */
const assert = require('assert');
const fs = require('fs');
const path = require('path');

/* Un DOM mínimo: la pieza solo necesita crear un div, colgarlo y leer/escribir
   textContent, hidden y disabled. Montar jsdom para esto sería traerse una
   dependencia entera para tres propiedades. */
function elemento(tag){
  const el = {
    tagName: tag.toUpperCase(), className: '', hidden: false, disabled: false,
    textContent: '', innerHTML: '', hijos: [], parentNode: null, _ev: {},
    addEventListener(n, f){ (this._ev[n] = this._ev[n] || []).push(f); },
    click(){ (this._ev.click || []).forEach(f => f()); },
    querySelector(sel){
      const m = /\[data-pag="(\w+)"\]/.exec(sel);
      if (m) return this.hijos.find(h => h._pag === m[1]);
      if (sel === '.n') return this.hijos.find(h => h.className === 'n');
      return null;
    },
    getBoundingClientRect(){ return { top: 10 }; },
    scrollIntoView(){},
  };
  return el;
}
global.matchMedia = () => ({ matches: true });
global.document = {
  createElement: elemento,
  querySelector(){ return global.__ancla; },
};

const src = fs.readFileSync(path.join(__dirname, 'paginacion.js'), 'utf8');
const caja = {};
new Function('caja', 'document', 'matchMedia', 'module',
  src + '\n;Object.assign(caja,{lwPaginador,LW_POR_PAGINA});')(caja, global.document, global.matchMedia, undefined);
const { lwPaginador, LW_POR_PAGINA } = caja;

/* El `innerHTML` de la pieza no se parsea en este DOM de mentira, así que los
   tres hijos se declaran a mano igual que los crearía el navegador. Es la parte
   que este test NO prueba, y se dice: prueba la ARITMÉTICA del paginador. */
function nuevo(conAncla){
  const ancla = conAncla === false ? null : elemento('div');
  if (ancla) ancla.parentNode = { insertBefore(){} };
  global.__ancla = ancla;
  let pie = null;
  const orig = document.createElement;
  document.createElement = (t) => {
    pie = orig(t);
    const a = orig('button'); a._pag = 'antes';
    const n = orig('span');   n.className = 'n';
    const d = orig('button'); d._pag = 'despues';
    pie.hijos = [a, n, d];
    return pie;
  };
  const p = lwPaginador('#x');
  document.createElement = orig;
  /* Se devuelve el PIE para poder pulsarlo: un test de paginador que nunca pulsa
     «Siguientes» no prueba el paginador, prueba un `slice`. */
  return { p, pie,
    antes:   pie.hijos[0],
    info:    pie.hijos[1],
    despues: pie.hijos[2] };
}

const filas = n => Array.from({ length: n }, (_, i) => i);
let fallos = 0;
const ok = (t, f) => { try { f(); console.log('  ok   ' + t); } catch (e) { fallos++; console.log('  FALLA ' + t + '\n         ' + e.message); } };

ok('25 por pagina, y el pie dice el TOTAL — no solo las flechas', () => {
  const { p, info } = nuevo();
  const t = p.pagina(filas(165));
  assert.strictEqual(t.length, 25);
  assert.strictEqual(t[0], 0);
  assert.strictEqual(info.textContent, '1–25 de 165',
    'un recorte que no se anuncia es una lista a la que le falta algo sin que nadie lo sepa');
});

ok('«Siguientes» avanza de verdad, y el pie lo cuenta', () => {
  const { p, despues, info } = nuevo();
  let pintadas = null;
  p.alCambiar(() => { pintadas = p.pagina(filas(165)); });
  p.pagina(filas(165));
  despues.click();
  assert.strictEqual(pintadas[0], 25, 'la 2a pagina empieza donde acabo la 1a');
  assert.strictEqual(info.textContent, '26–50 de 165');
  despues.click();
  assert.strictEqual(pintadas[0], 50);
});

ok('en la primera pagina «Anteriores» esta apagado; en la ultima, «Siguientes»', () => {
  const { p, antes, despues } = nuevo();
  p.alCambiar(() => p.pagina(filas(30)));
  p.pagina(filas(30));
  assert.strictEqual(antes.disabled, true, 'no se puede ir antes de la primera');
  despues.click();
  assert.strictEqual(despues.disabled, true, 'ni despues de la ultima');
  assert.strictEqual(antes.disabled, false);
});

ok('FILTRAR devuelve a la pagina 1 — el fallo clasico', () => {
  const { p, despues } = nuevo();
  let vistas = null;
  p.alCambiar(() => { vistas = p.pagina(filas(165)); });
  p.pagina(filas(165));
  despues.click(); despues.click();                 // el usuario esta en la 3a
  assert.strictEqual(vistas[0], 50, 'preparado: esta en la 3a pagina');
  const pocas = p.pagina(filas(4));                 // ahora el filtro deja 4
  assert.strictEqual(pocas.length, 4, 'con 4 filas se ven las 4');
  assert.strictEqual(pocas[0], 0, 'y desde la primera, no una lista vacia');
});

ok('si CABE ENTERO el paginador no se enseña', () => {
  const { p, pie } = nuevo();
  p.pagina(filas(LW_POR_PAGINA));
  assert.strictEqual(pie.hidden, true, 'un control que no hace nada enseña que hay algo que hacer');
  p.pagina(filas(LW_POR_PAGINA + 1));
  assert.strictEqual(pie.hidden, false);
});

ok('una lista vacia no rompe ni deja un rango imposible en el pie', () => {
  const { p, info } = nuevo();
  assert.deepStrictEqual(p.pagina([]), []);
  assert.strictEqual(info.textContent, '', 'nada que contar, nada que decir');
});

ok('volver de muchas filas a pocas no deja la pagina fuera de rango', () => {
  const { p, despues } = nuevo();
  p.alCambiar(() => p.pagina(filas(165)));
  p.pagina(filas(165));
  despues.click(); despues.click(); despues.click();
  const t = p.pagina(filas(60));   // 60 filas = 3 paginas; estaba en la 4a
  assert.ok(t.length > 0, 'nunca una pagina vacia por quedarse mas alla del final');
});

ok('sin ancla en el DOM la herramienta sigue viva (lista entera, sin pie)', () => {
  const { p } = nuevo(false);
  assert.strictEqual(p.pagina(filas(30)).length, 25,
    'una pieza de adorno no puede tumbar una pantalla que enseña dinero');
});

ok('el tamaño de página es UNO para toda la suite', () => {
  assert.strictEqual(LW_POR_PAGINA, 25);
});

console.log(fallos ? '\n' + fallos + ' fallo(s)' : '\nOK paginacion.test.js — la aritmética del paginador se sostiene');
process.exit(fallos ? 1 : 0);
