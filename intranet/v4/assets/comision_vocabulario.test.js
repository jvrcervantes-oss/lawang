// Condiciones de comisión con base POR TRAMO (comisiones desde el 1-nov-2026, 13-oct-2026):
// node intranet/v4/assets/comision_vocabulario.test.js
//
// Se ejecuta el código de verdad (trozos de editores.js y datos.js en un vm, con un DOM de mentira) y se mide:
//  1) EL VOCABULARIO vive en cinco formas (las listas de datos.js, DISPARADOR/BASE_LLANO/MOMENTO para frases y la copia de
//     respaldo de editores.js): todas cubren las mismas claves. El dato repetido que se separa es la familia de fallo
//     más cara del estudio (el depósito a 500 y a 1.000).
//  2) EL RIESGO CRÍTICO: abrir y guardar una condición cuyo disparador o base el editor no ofrece (la sucesora del
//     1-nov en el ERP maestro o antes de la migración, o un valor futuro) devuelve EXACTAMENTE lo guardado; nunca la
//     primera opción del <select>.
//  3) La suma va por base efectiva (como valida_suma_tramos_comision), y base_calculo viaja SIEMPRE explícita.
//  4) Mutación: si montaTramos deja de meter el valor guardado entre las opciones, este test tiene que fallar.
const fs = require('fs'), assert = require('assert'), vm = require('vm');
const ed = fs.readFileSync(__dirname + '/editores.js', 'utf8');
const da = fs.readFileSync(__dirname + '/datos.js', 'utf8');

const eIni = ed.indexOf('  // copia de respaldo de LW_V4.DISPARADORES');
const eFin = ed.indexOf('  /* ---------- Entrega estimada del proyecto');
assert.ok(eIni > 0 && eFin > eIni, 'no encuentro el bloque de tramos (respaldo…montaTramos) en editores.js');
const trozoEd = ed.slice(eIni, eFin);
const dIni = da.indexOf('  var DISPARADOR = {');
const dFin = da.indexOf('  // roles de equipo que cobran del manager');
assert.ok(dIni > 0 && dFin > dIni, 'no encuentro el vocabulario (DISPARADOR…momentoLlano) en datos.js');
const trozoDa = da.slice(dIni, dFin);

// ── DOM de mentira: lo justo para montaTramos. Un <select> se comporta como el del navegador: un value que no está
//    entre sus opciones lo deja sin elegir ('') y, sin tocarlo, vale la PRIMERA opción.
function el(tag) {
  const e = {
    tagName: tag.toUpperCase(), children: [], style: {}, attrs: {}, className: '', textContent: '', _l: {}, parentNode: null,
    appendChild(c) { this.children.push(c); c.parentNode = this; return c; },
    removeChild(c) { this.children = this.children.filter((x) => x !== c); },
    setAttribute(k, v) { this.attrs[k] = String(v); }, getAttribute(k) { return this.attrs[k]; },
    addEventListener(t, f) { (this._l[t] = this._l[t] || []).push(f); },
    dispara(t) { (this._l[t] || []).forEach((f) => f({ target: this })); },
    closest() { return null; }
  };
  if (tag === 'select') {
    e._i = 0;
    Object.defineProperty(e, 'options', { get() { return this.children; } });
    Object.defineProperty(e, 'value', {
      get() { const o = this.children[this._i]; return o ? o.value : ''; },
      set(v) { this._i = this.children.findIndex((o) => o.value === String(v)); }
    });
  } else e.value = '';
  return e;
}
class Event {}

function mundo(fuenteEd, lw) {
  const win = { LW_V4: lw || {} };
  const ctx = { window: win, document: { createElement: el }, Event, Promise, console };
  vm.createContext(ctx);
  vm.runInContext(trozoDa + '\n' + fuenteEd +
    '\nthis.T = { DISPARADORES_TRAMO_FALLBACK, BASES_CALCULO_FALLBACK, conValorGuardado, ofreciblesComision, sumasPorBase,' +
    ' validaTramosPorBase, tramosParaServidor, montaTramos, DISPARADORES_NUEVOS_1NOV, BASES_NUEVAS_1NOV,' +
    ' DISPARADORES_LISTA, BASES_LISTA, DISPARADOR, BASE_LLANO, MOMENTO, textoTramo, momentoLlano };', ctx);
  return { T: ctx.T, win };
}
const espera = () => new Promise((r) => setTimeout(r, 5));
const filasDe = (host) => host.children[0].children[1].children;   // wrap → lista → filas
const claves = (l) => l.map((o) => o[0]).sort();

// La sucesora tal como la deja la migración del 1-nov
const SUCESORA = [
  { orden: 1, disparador_tipo: 'pct_cobrado_suelo_firmado', umbral: 50, pct_tramo: 100, base_calculo: 'precio_suelo_firmado' },
  { orden: 2, disparador_tipo: 'pct_cobrado_obra_firmada', umbral: 25, pct_tramo: 100, base_calculo: 'precio_obra_firmada' }
];

async function comprueba(fuenteEd) {
  const fallos = [];
  const ok = (c, m) => { if (!c) fallos.push(m); };
  let w = mundo(fuenteEd).T;

  // 1 · vocabulario a la par
  ok(JSON.stringify(w.DISPARADORES_TRAMO_FALLBACK) === JSON.stringify(w.DISPARADORES_LISTA), 'la copia de disparadores de editores.js no es la de datos.js');
  ok(JSON.stringify(w.BASES_CALCULO_FALLBACK) === JSON.stringify(w.BASES_LISTA), 'la copia de bases de editores.js no es la de datos.js');
  ok(JSON.stringify(Object.keys(w.DISPARADOR).sort()) === JSON.stringify(claves(w.DISPARADORES_LISTA)), 'DISPARADOR (frases) no cubre las mismas claves que la lista');
  ok(JSON.stringify(Object.keys(w.BASE_LLANO).sort()) === JSON.stringify(claves(w.BASES_LISTA)), 'BASE_LLANO no cubre las mismas claves que la lista');
  ok(JSON.stringify(Object.keys(w.MOMENTO).sort()) === JSON.stringify(claves(w.DISPARADORES_LISTA)), 'MOMENTO (frases del comercial) no cubre las mismas claves que la lista');
  w.DISPARADORES_NUEVOS_1NOV.forEach((k) => ok(claves(w.DISPARADORES_LISTA).indexOf(k) !== -1, 'falta el disparador ' + k));
  w.BASES_NUEVAS_1NOV.forEach((k) => ok(claves(w.BASES_LISTA).indexOf(k) !== -1, 'falta la base ' + k));

  // 2 · lo que se ofrece y lo que se conserva
  const sinNuevo = w.ofreciblesComision(w.BASES_LISTA, w.BASES_NUEVAS_1NOV, false);
  ok(claves(sinNuevo).indexOf('por_tramo') === -1, 'sin soporte en la base no se ofrece «según cada tramo»');
  const conGuardado = w.conValorGuardado(sinNuevo, 'por_tramo', w.BASES_LISTA);
  ok(conGuardado.some((o) => o[0] === 'por_tramo' && o[1] === 'Según cada tramo'), 'el valor guardado vuelve a entrar con su etiqueta');
  ok(w.conValorGuardado(w.BASES_LISTA, 'precio_total', w.BASES_LISTA).length === w.BASES_LISTA.length, 'un valor conocido no se duplica');
  ok(w.conValorGuardado([], 'base_del_futuro', w.BASES_LISTA).some((o) => o[0] === 'base_del_futuro'), 'un valor que nadie conoce se conserva tal cual');

  // 3 · montaTramos en el ERP maestro (sin soporte): abrir y guardar la sucesora devuelve lo guardado
  w = mundo(fuenteEd, {}).T;
  let host = el('div');
  let get = w.montaTramos(host, SUCESORA, { conBase: true, baseInicial: 'por_tramo' });
  let r = get();
  ok(r.length === 2, 'dos tramos');
  ok(r[0].disparador_tipo === 'pct_cobrado_suelo_firmado' && r[1].disparador_tipo === 'pct_cobrado_obra_firmada',
    'sin soporte, el disparador guardado se conserva (salió ' + r.map((x) => x.disparador_tipo) + ')');
  ok(r[0].base_calculo === 'precio_suelo_firmado' && r[1].base_calculo === 'precio_obra_firmada',
    'sin soporte, la base guardada de cada tramo se conserva (salió ' + r.map((x) => x.base_calculo) + ')');
  ok(String(r[0].umbral) === '50' && String(r[1].umbral) === '25', 'los umbrales se conservan');
  ok(w.validaTramosPorBase('por_tramo', r) === null, 'la sucesora (100 + 100 en dos bases) es válida: ' + w.validaTramosPorBase('por_tramo', r));
  const srv = w.tramosParaServidor(r, 'por_tramo');
  ok(JSON.stringify(srv) === JSON.stringify([
    { disparador_tipo: 'pct_cobrado_suelo_firmado', umbral: 50, pct_tramo: 100, base_calculo: 'precio_suelo_firmado' },
    { disparador_tipo: 'pct_cobrado_obra_firmada', umbral: 25, pct_tramo: 100, base_calculo: 'precio_obra_firmada' }]),
  'lo que viaja al servidor es la sucesora tal cual: ' + JSON.stringify(srv));
  // un disparador que el front no conoce tampoco cae en «Al firmar el contrato»
  host = el('div');
  get = w.montaTramos(host, [{ disparador_tipo: 'disparo_futuro', pct_tramo: 100 }], {});
  ok(get()[0].disparador_tipo === 'disparo_futuro', 'un disparador desconocido se conserva (salió ' + get()[0].disparador_tipo + ')');
  // alta en el maestro: ni disparadores ni bases nuevas en las opciones
  host = el('div');
  w.montaTramos(host, null, { conBase: false });
  const opsDisp = filasDe(host)[0].children[0].options.map((o) => o.value);
  ok(opsDisp.indexOf('pct_cobrado_suelo_firmado') === -1, 'sin soporte no se ofrecen los disparadores del 1-nov');
  ok(filasDe(host)[0].children.length === 4, 'sin soporte no hay selector de base por tramo');

  // 4 · con soporte: se ofrecen, y la base de la condición manda (importe fijo → null)
  w = mundo(fuenteEd, { COMISION_BASE_POR_TRAMO: true }).T;
  host = el('div');
  const selCond = el('select'); ['precio_total', 'por_tramo', 'importe_fijo'].forEach((v) => { const o = el('option'); o.value = v; selCond.appendChild(o); });
  selCond.value = 'por_tramo';
  host.closest = () => ({ querySelector: (q) => (q === '[data-k="base_calculo"]' ? selCond : null) });
  get = w.montaTramos(host, SUCESORA, { conBase: true });
  await espera();
  const fila0 = filasDe(host)[0];
  ok(fila0.children[0].options.some((o) => o.value === 'pct_cobrado_obra_firmada'), 'con soporte se ofrecen los disparadores del 1-nov');
  const selB = fila0.children[4];
  ok(selB && selB.attrs['data-lw-tramo-base'] === '1', 'el selector de base engancha por data-lw-tramo-base');
  ok(selB.options.every((o) => o.value !== 'importe_fijo' && o.value !== 'por_tramo'), 'la base de un tramo nunca es «importe fijo» ni «según cada tramo»');
  ok(/elige/.test(selB.options[0].textContent), 'con «según cada tramo» la base del tramo se pide (sin «hereda»)');
  selCond.value = 'importe_fijo'; selCond.dispara('change');
  ok(selB.style.display === 'none', 'con importe fijo se oculta la base del tramo');
  ok(get().every((t) => t.base_calculo === null), 'con importe fijo los tramos viajan sin base');

  // 4b · con «según cada tramo», un tramo sin precio elegido no sale en verde (la suma en vivo dice lo mismo que guardar)
  host = el('div');
  const selCond2 = el('select'); ['precio_total', 'por_tramo'].forEach((v) => { const o = el('option'); o.value = v; selCond2.appendChild(o); });
  selCond2.value = 'por_tramo';
  host.closest = () => ({ querySelector: () => selCond2 });
  w.montaTramos(host, [{ disparador_tipo: 'contrato_firmado', pct_tramo: 100 }], { conBase: true });
  await espera();
  const badge = host.children[0].children[0].children[1];
  ok(badge.textContent.indexOf('✓') === -1 && /Sin precio elegido/.test(badge.textContent), 'la suma en vivo no da por bueno un tramo sin precio: «' + badge.textContent + '»');

  // 5 · reglas de suma por base
  ok(w.validaTramosPorBase('precio_total', [{ pct_tramo: 50 }, { pct_tramo: 50 }]) === null, 'precio total 50 + 50 vale');
  ok(/suman 200%/.test(w.validaTramosPorBase('precio_total', [{ pct_tramo: 100 }, { pct_tramo: 100 }]) || ''), '100 + 100 en una sola base no vale');
  ok(/necesita su base/.test(w.validaTramosPorBase('por_tramo', [{ pct_tramo: 100 }]) || ''), 'con «según cada tramo», un tramo sin base no vale');
  ok(/parcela/.test(w.validaTramosPorBase('por_tramo', [{ pct_tramo: 50, base_calculo: 'precio_suelo_firmado' }, { pct_tramo: 100, base_calculo: 'precio_obra_firmada' }]) || ''),
    'con dos bases, la que no llega a 100 se nombra');
  ok(w.validaTramosPorBase('importe_fijo', [{ pct_tramo: 50, base_calculo: 'precio_total' }, { pct_tramo: 50 }]) === null, 'con importe fijo la base del tramo no cuenta');
  ok(w.tramosParaServidor([{ disparador_tipo: 'contrato_firmado', umbral: '7', pct_tramo: '100' }], 'precio_total')[0].umbral === null, 'umbral solo en «% cobrado…»');
  ok('base_calculo' in w.tramosParaServidor([{ disparador_tipo: 'contrato_firmado', pct_tramo: 100 }], 'precio_total')[0], 'base_calculo siempre explícita');

  // 6 · frases de datos.js
  ok(w.textoTramo(SUCESORA[0], 'por_tramo') === '100 % al 50 % cobrado de la parcela firmada · s/ precio firmado de la parcela', 'resumen del tramo: ' + w.textoTramo(SUCESORA[0], 'por_tramo'));
  ok(w.textoTramo({ pct_tramo: 50, disparador_tipo: 'contrato_firmado' }, 'precio_total') === '50 % al firmar el contrato', 'resumen de un tramo viejo');
  ok(w.momentoLlano(SUCESORA[1]) === 'cuando se haya cobrado el 25 % de la construcción', 'momento en llano: ' + w.momentoLlano(SUCESORA[1]));
  return fallos;
}

(async function () {
  const fallos = await comprueba(trozoEd);
  assert.deepStrictEqual(fallos, [], 'fallos:\n  ' + fallos.join('\n  '));
  // mutación: montaTramos sin el valor guardado entre las opciones → el test TIENE que caer
  const marca = 'conValorGuardado(opciones, esTramo ? valores.disparador_tipo : null, listaDisparadores())';
  assert.strictEqual(trozoEd.split(marca).length, 2, 'la marca de la mutación ya no está una sola vez en montaTramos');
  const mutados = await comprueba(trozoEd.replace(marca, 'opciones'));
  assert.ok(mutados.some((m) => /disparador guardado se conserva|desconocido se conserva/.test(m)), 'la mutación no rompió el test: no mide lo que dice');
  const marcaB = 'conValorGuardado(opcionesBase, esTramo ? valores.base_calculo : null, listaBases())';
  assert.strictEqual(trozoEd.split(marcaB).length, 2, 'la marca de la mutación de base ya no está una sola vez');
  const mutB = await comprueba(trozoEd.replace(marcaB, 'opcionesBase'));
  assert.ok(mutB.some((m) => /base guardada de cada tramo se conserva/.test(m)), 'la mutación de base no rompió el test');
  console.log('comision_vocabulario: OK (vocabulario a la par, valores guardados conservados, suma por base, 2 mutaciones cazadas)');
})().catch((e) => { console.error(e.message || e); process.exit(1); });
