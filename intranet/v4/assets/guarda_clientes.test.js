// Pantalla Clientes (bloque `compradores` de datos.js) sin contratos ni soporte — desacople del núcleo comercial, corte 3
// (D1 + D2), 5-oct-2026: node guarda_clientes.test.js
//
// Es un ARNÉS, no una lectura del texto: corre de verdad el bloque `compradores` y sus funciones de apoyo (extraídos de
// datos.js tal cual) con una base y un DOM de mentira, y cuenta qué se pide a la base en cada estado:
//   1. sin bandera (Lawang): MISMAS llamadas, en el MISMO orden que antes del corte, y las columnas visibles;
//   2. maestro con todo encendido: lo mismo;
//   3. maestro con contratos y soporte apagados: no se pide NADA contractual (ni contrato_firmas_equipo), se OCULTAN las
//      columnas (Proyecto(s), Inversión, Pagado), el KPI de capital y los filtros de contrato, y la ficha no pinta sus
//      secciones ni pide su resumen;
//   4. maestro todavía sin saber qué hay encendido: espera (no pide nada) y luego decide.
const fs = require('fs'), assert = require('assert');
const src = fs.readFileSync(__dirname + '/datos.js', 'utf8');

const ini = src.indexOf('  function moduloEncendido(m) {');
const finH = src.indexOf('  function enlaceFichaContrato');
assert.ok(ini > 0 && finH > ini, 'no encuentro las funciones de apoyo de Clientes en datos.js');
const apoyo = src.slice(ini, finH);
const b0 = src.indexOf('    compradores: function (sb) {');
const b1 = src.indexOf('    operaciones: function (sb) {');
assert.ok(b0 > 0 && b1 > b0, 'no encuentro el bloque compradores en datos.js');
const bloque = src.slice(b0, b1);

// ── lo que el registro de módulos necesita: lo contractual y de soporte NO está en el cuerpo del bloque, solo en las
//    dos funciones puente (erp/modulos.py → PUENTES_FRONT['compradores']); si vuelve a aparecer aquí, la arista vuelve.
['contrato_firmas_equipo', 'contratos_cobrado_equipo', 'contrato_compradores', 'hilo_soporte', 'mensajes_comprador'].forEach(function (o) {
  assert.ok(bloque.indexOf(o) === -1, 'el bloque compradores nombra ' + o + ': debe vivir solo en clientesContratosCarga/clientesSoporteResumen');
});
['contrato_firmas_equipo', 'contratos_cobrado_equipo', 'contrato_compradores'].forEach(function (o) {
  assert.ok(apoyo.indexOf(o) > -1, 'clientesContratosCarga ya no pide ' + o);
});
assert.ok(apoyo.indexOf('hilo_soporte') > -1 && apoyo.indexOf('mensajes_comprador') > -1, 'clientesSoporteResumen ya no pide el soporte');

// ── DOM y base de mentira
function el(clave, reg) {
  const e = { clave, style: {}, attrs: {}, innerHTML: '', textContent: '', classList: { add() {}, remove() {}, toggle() {} },
    querySelector() { return null; }, querySelectorAll() { return []; }, addEventListener() {}, insertAdjacentHTML() {},
    setAttribute(k, v) { e.attrs[k] = v; }, getAttribute(k) { return e.attrs[k]; }, appendChild() {}, cloneNode() { return el(clave + '*', reg); },
    closest(s) { return reg('closest:' + clave + ':' + s); }, get firstElementChild() { return null; } };
  return e;
}
function mundo(opts) {
  const calls = [], elementos = {}, cajones = [];
  const reg = (k) => (elementos[k] = elementos[k] || el(k, reg));
  const cabecera = { cells: Array.from({ length: 9 }, () => ({ style: {} })) };
  const tabla = { rows: [cabecera], tBodies: [{}] };
  const fx = Object.assign({
    'rpc:compradores_lista': [{ id: 'c1', full_name: 'Ana', email: 'a@x.es', nationality: 'ES', tipo: 'persona', kyc_status: 'verified', propietario: 'a@x.es', created_at: '2026-01-01' }],
    'rpc:contratos_equipo': [{ id: 'k1', numero: 'N1', tipo: 'compraventa', proyecto_nombre: 'P', precio_total: 100, moneda: 'EUR', bloqueado: true }],
    'from:contrato_compradores': [{ contrato_id: 'k1', client_id: 'c1', rol: 'adquiriente_1' }],
    'rpc:contratos_cobrado_equipo': [{ contrato_id: 'k1', cobrado: 50 }],
    'rpc:compradores_numeros': [{ id: 'c1', numero_cliente: 'CLI-1' }],
    'from:clients': [{ id: 'c1', full_name: 'Ana', email: 'a@x.es', tipo: 'persona', kyc_status: 'verified', created_at: '2026-01-01' }]
  }, opts.fx || {});
  const mk = (kind, name) => {
    calls.push(kind + ':' + name);
    const b = {
      select() { return b; }, eq() { return b; }, in() { return b; }, or() { return b; }, order() { return b; }, limit() { return b; },
      maybeSingle() { b._u = true; return b; },
      then(ok, ko) {
        let data = fx[kind + ':' + name]; if (data === undefined) data = [];
        if (b._u) data = Array.isArray(data) ? (data[0] || null) : data;
        return Promise.resolve({ data, error: null }).then(ok, ko);
      }
    };
    return b;
  };
  const sb = { rpc: (n) => mk('rpc', n), from: (n) => mk('from', n), auth: { getSession: () => Promise.resolve({ data: { session: null } }) } };
  const H = {};
  ['dato', 'nota', 'tag', 'enlace', 'tabla', 'cifras'].forEach((k) => { H[k] = () => ''; });
  H.seccion = (titulo, html, id) => '[sec:' + id + ']';
  const win = Object.assign({
    LW_V4: { esSuperAdmin: false, esAdmin: false, miEmail: 'a@x.es' }, lwCajonHtml: H,
    lwCajon(o) { cajones.push(o); return { cuerpo: el('cuerpo', reg), cierra() {} }; }
  }, opts.win || {});
  const S = {
    LW_ROL: { esEmpresa: () => false, esAdmin: () => false, esGlobal: () => true, esSuperGlobal: () => false, esSuperAdmin: () => false, efectivo: (f) => (f && f.rol) || '', empresas: () => [] },   // guard.js lo publica en la página real
    window: win, document: { querySelector: (s) => (s === 'table[data-lw="tabla-clientes"]' ? tabla : reg(s)), getElementById: (i) => reg('#' + i), createElement: (n) => reg('new:' + n) },
    location: { href: 'https://x.test/intranet/v4/compradores/', search: '', pathname: '/intranet/v4/compradores/' }, history: { replaceState() {} },
    tablaPor: () => tabla,
    q: (p) => Promise.resolve(p).then((r) => (r.error ? null : (r.data || []))),
    vig: (p) => p, fallo() {}, pon2() {}, kpi() {}, bandaNota() {}, toast() {}, toastMal() {},
    esc: (s) => String(s == null ? '' : s), fmt: (n) => String(n), fFecha: (x) => String(x), fFechaHoraCorta: (x) => String(x),
    htmlAutor: () => '', tipoC: (t) => t, lwEsPreliminar: () => false, lwConfirmar() { return Promise.resolve(false); },
    cablearChipsFiltro() {}, URL_FACTURA: (i) => '/f/' + i,
    plantillaFilas: () => ({ tbody: { lastElementChild: null, addEventListener() {} }, base: {} }),
    fila: () => {
      const celdas = Array.from({ length: 9 }, () => ({ style: {} }));
      tabla.rows.push({ cells: celdas, style: {}, querySelector: () => null, querySelectorAll: () => celdas.map(() => ({ innerHTML: '' })), setAttribute() {}, lastElementChild: { innerHTML: '' } });
      tabla.tbody = tabla.tbody || {};
    }
  };
  // `fila` lee `pl.tbody.lastElementChild`: se lo damos como la última fila pintada
  S.plantillaFilas = () => ({ tbody: { get lastElementChild() { return tabla.rows[tabla.rows.length - 1]; }, addEventListener() {} }, base: {} });
  const reales = new Set(['Promise', 'Object', 'Array', 'Math', 'Number', 'String', 'JSON', 'Date', 'URL', 'URLSearchParams', 'console', 'setTimeout', 'clearTimeout', 'Boolean', 'Error', 'parseInt', 'parseFloat', 'isNaN', 'encodeURIComponent', 'decodeURIComponent', 'undefined', 'RegExp']);
  const proxy = new Proxy(S, {
    has: () => true,
    get(t, k) { if (k === Symbol.unscopables) return undefined; if (k in t) return t[k]; if (reales.has(k)) return globalThis[k]; return function () { return undefined; }; }
  });
  const fabrica = new Function('S', 'with (S) { ' + apoyo + '\n return ({' + bloque + '}); }');
  const reg4 = fabrica(proxy);
  return { reg: reg4, sb, calls, tabla, cabecera, elementos, cajones, win };
}
const espera = (ms) => new Promise((r) => setTimeout(r, ms || 15));
const CONTRACTUALES = ['rpc:contratos_equipo', 'from:contrato_compradores', 'rpc:contratos_cobrado_equipo', 'rpc:contrato_firmas_equipo'];
const ORDEN_LAWANG = ['rpc:compradores_lista'].concat(CONTRACTUALES, ['from:usuarios', 'rpc:compradores_numeros']);
const ocultas = (fl) => [3, 4, 5].map((i) => fl.cells[i].style.display === 'none');

(async function () {
  // 1) Lawang: sin bandera. El orden de las llamadas es el de ANTES del corte (7 y luego la vista de divergencias).
  let w = mundo({});
  w.reg.compradores(w.sb); await espera();
  assert.deepStrictEqual(w.calls.slice(0, 7), ORDEN_LAWANG, 'Lawang: las 7 primeras llamadas, en su orden de siempre');
  assert.deepStrictEqual(w.calls.slice(7), ['from:documentos_desactualizados'], 'Lawang: nada más al cargar');
  assert.strictEqual(w.tabla.rows.length, 2, 'cabecera + 1 fila');
  w.tabla.rows.forEach((fl) => assert.deepStrictEqual(ocultas(fl), [false, false, false], 'Lawang: columnas visibles'));
  assert.ok(!w.elementos['[data-lw-tarjeta="capital"]'] || w.elementos['[data-lw-tarjeta="capital"]'].style.display !== 'none', 'Lawang: la tarjeta de capital se ve');
  // ficha
  w.win.LW_V4.abreFichaComprador('c1'); await espera();
  let cuerpo = w.cajones[0].cuerpo;
  ['contratos', 'cuentas', 'facturas', 'envios', 'soporte', 'docs', 'portal'].forEach((s) => assert.ok(cuerpo.indexOf('[sec:' + s + ']') > -1, 'Lawang: la ficha pinta ' + s));
  assert.deepStrictEqual(w.cajones[0].lado, ['cuentas'], 'Lawang: «cuentas» en la columna lateral');
  assert.ok(w.cajones[0].acciones.some((a) => a.texto === 'Crear contrato'), 'Lawang: ofrece Crear contrato');
  ['rpc:comprador_contratos_resumen', 'from:mensajes_comprador', 'from:hilo_soporte', 'rpc:facturas_equipo', 'from:correos_enviados'].forEach((c) => assert.ok(w.calls.indexOf(c) > -1, 'Lawang: la ficha pide ' + c));

  // 2) Maestro con todo encendido: idéntico a Lawang (la bandera sola no cambia nada)
  w = mundo({ win: { AXW_NUCLEO_OPERACION: true, axwModuloActivo: () => true, AXW_MODULOS_LISTOS: Promise.resolve(true) } });
  w.reg.compradores(w.sb); await espera();
  assert.deepStrictEqual(w.calls.slice(0, 7), ORDEN_LAWANG, 'maestro con todo encendido: mismas llamadas, mismo orden');
  w.tabla.rows.forEach((fl) => assert.deepStrictEqual(ocultas(fl), [false, false, false]));

  // 3) Maestro con contratos y soporte APAGADOS
  w = mundo({ win: { AXW_NUCLEO_OPERACION: true, axwModuloActivo: (m) => m !== 'contratos' && m !== 'soporte', AXW_MODULOS_LISTOS: Promise.resolve(true) } });
  w.reg.compradores(w.sb); await espera();
  assert.deepStrictEqual(w.calls.slice(0, 3), ['rpc:compradores_lista', 'from:usuarios', 'rpc:compradores_numeros'], 'apagado: solo la carga propia de Clientes');
  CONTRACTUALES.forEach((c) => assert.ok(w.calls.indexOf(c) === -1, 'apagado: NO se pide ' + c));
  assert.ok(w.calls.indexOf('rpc:contrato_firmas_equipo') === -1, 'apagado: contrato_firmas_equipo no se llama');
  assert.strictEqual(w.tabla.rows.length, 2);
  w.tabla.rows.forEach((fl) => assert.deepStrictEqual(ocultas(fl), [true, true, true], 'apagado: columnas Proyecto(s), Inversión y Pagado OCULTAS (cabecera y filas)'));
  assert.strictEqual(w.elementos['[data-lw-tarjeta="capital"]'].style.display, 'none', 'apagado: tarjeta de capital oculta');
  ['cc-contrato', 'cc-firma', 'cc-prospectos'].forEach((k) => assert.strictEqual(w.elementos['closest:[data-lw="' + k + '"]:button'].style.display, 'none', 'apagado: filtro ' + k + ' oculto'));
  w.win.LW_V4.abreFichaComprador('c1'); await espera();
  cuerpo = w.cajones[0].cuerpo;
  ['contratos', 'cuentas', 'facturas', 'envios', 'soporte'].forEach((s) => assert.ok(cuerpo.indexOf('[sec:' + s + ']') === -1, 'apagado: la ficha NO pinta ' + s));
  ['docs', 'portal', 'responsable'].forEach((s) => assert.ok(cuerpo.indexOf('[sec:' + s + ']') > -1, 'apagado: la ficha sí pinta ' + s));
  assert.strictEqual(w.cajones[0].lado, undefined, 'apagado: sin columna lateral de cuentas');
  assert.ok(!w.cajones[0].acciones.some((a) => a.texto === 'Crear contrato'), 'apagado: no ofrece Crear contrato');
  ['rpc:comprador_contratos_resumen', 'from:mensajes_comprador', 'from:hilo_soporte', 'rpc:facturas_equipo', 'from:correos_enviados'].forEach((c) => assert.ok(w.calls.indexOf(c) === -1, 'apagado: la ficha NO pide ' + c));

  // 3b) Solo soporte apagado: contratos sigue igual que en Lawang
  w = mundo({ win: { AXW_NUCLEO_OPERACION: true, axwModuloActivo: (m) => m !== 'soporte', AXW_MODULOS_LISTOS: Promise.resolve(true) } });
  w.reg.compradores(w.sb); await espera();
  assert.deepStrictEqual(w.calls.slice(0, 7), ORDEN_LAWANG, 'solo soporte apagado: la carga es la de siempre');
  w.win.LW_V4.abreFichaComprador('c1'); await espera();
  assert.ok(w.cajones[0].cuerpo.indexOf('[sec:soporte]') === -1 && w.cajones[0].cuerpo.indexOf('[sec:contratos]') > -1, 'solo soporte apagado: sin Soporte, con Contratos');
  assert.ok(w.calls.indexOf('from:hilo_soporte') === -1 && w.calls.indexOf('rpc:comprador_contratos_resumen') > -1);

  // 4) Maestro sin saber aún qué hay encendido: espera y luego decide (no pide lo contractual «por si acaso»)
  let listo; let sabe = false;
  w = mundo({ win: { AXW_NUCLEO_OPERACION: true, axwModuloActivo: (m) => (sabe ? m !== 'contratos' : true), AXW_MODULOS_LISTOS: new Promise((r) => { listo = r; }) } });
  w.reg.compradores(w.sb); await espera();
  assert.deepStrictEqual(w.calls, [], 'cargando lo encendido: no se pide nada todavía');
  sabe = true; listo(true); await espera();
  CONTRACTUALES.forEach((c) => assert.ok(w.calls.indexOf(c) === -1, 'tras saberlo (contratos apagado): NO se pide ' + c));
  assert.ok(w.calls.indexOf('rpc:compradores_lista') > -1, 'tras saberlo: carga Clientes');

  // 4b) la comprobación de lo encendido falla: la promesa resuelve false y el helper cae a «encendido» (falla abierto)
  w = mundo({ win: { AXW_NUCLEO_OPERACION: true, axwModuloActivo: () => true, AXW_MODULOS_LISTOS: Promise.resolve(false) } });
  w.reg.compradores(w.sb); await espera();
  assert.deepStrictEqual(w.calls.slice(0, 7), ORDEN_LAWANG, 'sin poder comprobar: se comporta como siempre');

  console.log('OK guarda_clientes.test.js');
})().catch((e) => { console.error(e); process.exit(1); });
