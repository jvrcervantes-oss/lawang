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
// LAW-338 L5 (16-oct-2026): el resumen de soporte se pide al servidor (comprador_ficha_datos, parte «soporte»)
assert.ok(/comprador_ficha_datos[^\n]*p_partes: \['soporte'\]/.test(apoyo), 'clientesSoporteResumen ya no pide el soporte');
assert.ok(bloque.indexOf("p_partes: ['soporte']") === -1, 'el bloque compradores pide el soporte por su cuenta: debe vivir solo en clientesSoporteResumen');

// ── DOM y base de mentira
function el(clave, reg) {
  const e = { clave, style: {}, attrs: {}, innerHTML: '', textContent: '', classList: { add() {}, remove() {}, toggle() {} },
    querySelector() { return null; }, querySelectorAll() { return []; }, addEventListener() {}, insertAdjacentHTML() {},
    setAttribute(k, v) { e.attrs[k] = v; }, getAttribute(k) { return e.attrs[k]; }, appendChild() {}, cloneNode() { return el(clave + '*', reg); },
    closest(s) { return reg('closest:' + clave + ':' + s); }, get firstElementChild() { return null; } };
  return e;
}
function mundo(opts) {
  const calls = [], elementos = {}, cajones = [], eqs = [];
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
      select() { return b; }, eq(k, v) { eqs.push(name + ':' + k + '=' + v); return b; }, in() { return b; }, or() { return b; }, order() { return b; }, limit() { return b; },
      maybeSingle() { b._u = true; return b; },
      then(ok, ko) {
        let data = fx[kind + ':' + name]; if (data === undefined) data = [];
        if (data && data.__error) return Promise.resolve({ data: null, error: { message: data.__error } }).then(ok, ko);
        if (b._u) data = Array.isArray(data) ? (data[0] || null) : data;
        return Promise.resolve({ data, error: null }).then(ok, ko);
      }
    };
    return b;
  };
  const sb = { rpc: (n) => mk('rpc', n), from: (n) => mk('from', n), auth: { getSession: () => Promise.resolve({ data: { session: null } }) } };
  const H = {};
  ['dato', 'nota', 'tag', 'enlace', 'tabla', 'cifras'].forEach((k) => { H[k] = () => ''; });
  if (opts.notas) { H.nota = (t) => '[nota:' + t + ']'; H.enlace = (h, t) => '[a:' + h + '|' + t + ']'; }
  H.seccion = (titulo, html, id) => '[sec:' + id + ']';
  /* LAW-338 L5: las lecturas `*_datos` (window.lwDatos). Se apuntan como 'rpc:<nombre>' (la ficha, con sus partes: 'rpc:comprador_ficha_datos:soporte')
     y se contestan con las mismas fixtures que antes servían la tabla. */
  const fxDe = (k) => { const d = fx[k]; return d && d.__error ? { error: { message: d.__error } } : { data: d === undefined ? [] : d }; };
  const lwDatos = (n, a) => {
    calls.push('rpc:' + n + (a && a.p_partes ? ':' + a.p_partes.join(',') : ''));
    if (a && a.p_client) eqs.push(n + ':p_client=' + a.p_client);
    let r;
    if (n === 'clientes_lista_datos') { const x = fxDe('from:clients'); r = x.error ? x : { data: { clientes: x.data, recortado: [] } }; }
    else if (n === 'comprador_ficha_datos') {
      const x = fxDe('from:clients');
      // como el servidor: si la ficha no se ve entera, solo {ve:false} (sin ninguna parte)
      r = x.error ? x : (!x.data.length ? { data: { ve: false, recortado: [] } }
        : { data: { ve: true, recortado: [], ficha: x.data[0], documento: x.data[0], documentos: [], portal: [], soporte: { ultimo: null, hilos: [] } } });
    } else if (n === 'documentos_desactualizados_datos') { const x = fxDe('from:documentos_desactualizados'); r = x.error ? x : { data: { documentos: x.data, recortado: [] } }; }
    else if (n === 'correos_registro_datos') r = { data: { correos: [], recortado: [] } };
    else r = { data: {} };
    return Promise.resolve(Object.assign({ data: null, error: null }, r));
  };
  const win = Object.assign({
    lwDatos,
    LW_V4: { esSuperAdmin: false, esAdmin: false, miEmail: 'a@x.es' }, lwCajonHtml: H,
    lwCajon(o) { cajones.push(o); return { cuerpo: opts.cuerpo ? opts.cuerpo() : el('cuerpo', reg), cierra() {} }; }
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
  if (opts.s) Object.assign(S, opts.s);
  const fabrica = new Function('S', 'with (S) { ' + apoyo + '\n return ({' + bloque + '}); }');
  const reg4 = fabrica(proxy);
  return { reg: reg4, sb, calls, eqs, tabla, cabecera, elementos, cajones, win };
}
const espera = (ms) => new Promise((r) => setTimeout(r, ms || 15));
const CONTRACTUALES = ['rpc:contratos_equipo', 'from:contrato_compradores', 'rpc:contratos_cobrado_equipo', 'rpc:contrato_firmas_equipo'];
const ORDEN_LAWANG = ['rpc:compradores_lista'].concat(CONTRACTUALES, ['from:usuarios', 'rpc:compradores_numeros']);
const ocultas = (fl) => [3, 4, 5].map((i) => fl.cells[i].style.display === 'none');

(async function () {
  // 1) Lawang: sin bandera. El orden de las llamadas es el de ANTES del corte (7 y luego qué fichas ve enteras). La vista de
  //    divergencias ya NO se pide en la lista (15-oct-2026): solo pintaba el total de todos en la consola; la pide cada ficha.
  let w = mundo({});
  w.reg.compradores(w.sb); await espera();
  assert.deepStrictEqual(w.calls.slice(0, 7), ORDEN_LAWANG, 'Lawang: las 7 primeras llamadas, en su orden de siempre');
  assert.deepStrictEqual(w.calls.slice(7), ['rpc:clientes_lista_datos'], 'Lawang: tras las siete, solo qué fichas ve enteras (clientes_lista_datos); la vista de divergencias no se pide en la lista');
  assert.strictEqual(w.tabla.rows.length, 2, 'cabecera + 1 fila');
  w.tabla.rows.forEach((fl) => assert.deepStrictEqual(ocultas(fl), [false, false, false], 'Lawang: columnas visibles'));
  assert.ok(!w.elementos['[data-lw-tarjeta="capital"]'] || w.elementos['[data-lw-tarjeta="capital"]'].style.display !== 'none', 'Lawang: la tarjeta de capital se ve');
  // ficha
  w.win.LW_V4.abreFichaComprador('c1'); await espera();
  let cuerpo = w.cajones[0].cuerpo;
  ['contratos', 'cuentas', 'facturas', 'envios', 'soporte', 'docs', 'portal'].forEach((s) => assert.ok(cuerpo.indexOf('[sec:' + s + ']') > -1, 'Lawang: la ficha pinta ' + s));
  assert.deepStrictEqual(w.cajones[0].lado, ['cuentas'], 'Lawang: «cuentas» en la columna lateral');
  assert.ok(w.cajones[0].acciones.some((a) => a.texto === 'Crear contrato'), 'Lawang: ofrece Crear contrato');
  ['rpc:comprador_contratos_resumen', 'rpc:comprador_ficha_datos:soporte', 'rpc:facturas_equipo', 'rpc:correos_registro_datos', 'rpc:documentos_desactualizados_datos'].forEach((c) => assert.ok(w.calls.indexOf(c) > -1, 'Lawang: la ficha pide ' + c));
  assert.ok(w.eqs.indexOf('documentos_desactualizados_datos:p_client=c1') > -1, 'Lawang: la ficha pide SUS divergencias, por el id del cliente');

  // 2) Maestro con todo encendido: idéntico a Lawang (la bandera sola no cambia nada)
  w = mundo({ win: { AXW_NUCLEO_OPERACION: true, axwModuloActivo: () => true, AXW_MODULOS_LISTOS: Promise.resolve(true) } });
  w.reg.compradores(w.sb); await espera();
  assert.deepStrictEqual(w.calls.slice(0, 7), ORDEN_LAWANG, 'maestro con todo encendido: mismas llamadas, mismo orden');
  w.tabla.rows.forEach((fl) => assert.deepStrictEqual(ocultas(fl), [false, false, false]));

  // 2b) «Ficha ≠» DE ESTE CLIENTE (15-oct-2026): vivos y cerrados en dos notas, «no he podido mirar» distinto de «ninguno»,
  //     y nada se pinta en una ficha que ya no está abierta.
  const pintado = [];
  const sitio = { insertAdjacentHTML(_d, h) { pintado.push(h); } };
  let conectado = true;
  const cuerpoFicha = () => ({ get isConnected() { return conectado; }, querySelector: (s) => (s === '[data-cajon-sec="identidad"] > div' ? sitio : null), querySelectorAll: () => [], insertAdjacentHTML() {} });
  const txS = { tx: (t, h) => { let v = String(t); for (const k in (h || {})) v = v.split('%' + k).join(h[k]); return v; } };
  const difs = [
    { tipo: 'contrato', id: 'k1', numero: 'N1', congelado: false, diferencias: [{ campo: 'email', documento: 'a@y.es', ficha: 'a@x.es' }] },
    { tipo: 'factura', id: 'f9', numero: 'F-9', congelado: true, diferencias: [{ campo: 'nombre', documento: 'Ana B', ficha: 'Ana' }] },
    { tipo: 'factura', id: 'f8', numero: 'F-8', congelado: false, diferencias: [] }
  ];
  w = mundo({ notas: true, cuerpo: cuerpoFicha, s: txS, fx: { 'from:documentos_desactualizados': difs } });
  w.reg.compradores(w.sb); await espera();
  w.win.LW_V4.abreFichaComprador('c1'); await espera();
  assert.strictEqual(pintado.length, 1, 'Ficha ≠: se pinta una vez en Identidad');
  assert.ok(pintado[0].indexOf('[nota:<b>1</b> documento(s) sin cerrar') > -1 && pintado[0].indexOf('[nota:<b>1</b> documento(s) ya cerrados') > -1, 'Ficha ≠: una nota de vivos y otra de cerrados, cada una con su cuenta (el que no difiere no cuenta)');
  assert.ok(pintado[0].indexOf('[a:/intranet/v4/contratos/?contrato=N1|N1]') > -1 && pintado[0].indexOf('[a:/intranet/v4/facturas/?id=f9|F-9]') > -1, 'Ficha ≠: enlace al contrato por número y a la factura por id');
  assert.ok(pintado[0].indexOf('F-8') === -1, 'Ficha ≠: un documento sin diferencias no sale');
  pintado.length = 0;
  w = mundo({ notas: true, cuerpo: cuerpoFicha, s: txS, fx: { 'from:documentos_desactualizados': { __error: 'x' } } });
  w.reg.compradores(w.sb); await espera();
  w.win.LW_V4.abreFichaComprador('c1'); await espera();
  assert.ok(pintado.length === 1 && pintado[0].indexOf('No se ha podido comprobar') > -1, 'Ficha ≠: si la consulta falla, lo DICE');
  pintado.length = 0;
  w = mundo({ notas: true, cuerpo: cuerpoFicha, s: txS, fx: { 'from:documentos_desactualizados': [] } });
  w.reg.compradores(w.sb); await espera();
  w.win.LW_V4.abreFichaComprador('c1'); await espera();
  assert.strictEqual(pintado.length, 0, 'Ficha ≠: sin diferencias no se pinta nada');
  conectado = false;
  w = mundo({ notas: true, cuerpo: cuerpoFicha, s: txS, fx: { 'from:documentos_desactualizados': difs } });
  w.reg.compradores(w.sb); await espera();
  w.win.LW_V4.abreFichaComprador('c1'); await espera();
  assert.strictEqual(pintado.length, 0, 'Ficha ≠: en una ficha que ya no está en la página no se pinta');

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
  ['rpc:comprador_contratos_resumen', 'rpc:comprador_ficha_datos:soporte', 'rpc:facturas_equipo', 'rpc:correos_registro_datos'].forEach((c) => assert.ok(w.calls.indexOf(c) === -1, 'apagado: la ficha NO pide ' + c));

  // 3b) Solo soporte apagado: contratos sigue igual que en Lawang
  w = mundo({ win: { AXW_NUCLEO_OPERACION: true, axwModuloActivo: (m) => m !== 'soporte', AXW_MODULOS_LISTOS: Promise.resolve(true) } });
  w.reg.compradores(w.sb); await espera();
  assert.deepStrictEqual(w.calls.slice(0, 7), ORDEN_LAWANG, 'solo soporte apagado: la carga es la de siempre');
  w.win.LW_V4.abreFichaComprador('c1'); await espera();
  assert.ok(w.cajones[0].cuerpo.indexOf('[sec:soporte]') === -1 && w.cajones[0].cuerpo.indexOf('[sec:contratos]') > -1, 'solo soporte apagado: sin Soporte, con Contratos');
  assert.ok(w.calls.indexOf('rpc:comprador_ficha_datos:soporte') === -1 && w.calls.indexOf('rpc:comprador_contratos_resumen') > -1);

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

  // 5) FICHA BÁSICA (7-oct-2026, directorio global): una ficha que la base no deja leer entera (clients sin fila, sin error) se abre
  //    en SOLO LECTURA con lo que trae la lista; sin secciones de contratos/cuentas/facturas/KYC/portal y sin botones de escribir.
  //    Y la lista marca (data-ficha-basica) las que no se ven enteras, y no las cuenta como «sin contrato».
  const sinFilas = { 'from:clients': [] };
  w = mundo({ fx: sinFilas, win: { LW_V4: { esSuperAdmin: false, esAdmin: false, miEmail: 'a@x.es', ficha: { ambito: 'global', empresas: [] } } } });
  w.reg.compradores(w.sb); await espera();
  w.win.LW_V4.abreFichaComprador('c1'); await espera();
  assert.strictEqual(w.cajones.length, 1, 'ficha básica: abre un cajón');
  cuerpo = w.cajones[0].cuerpo;
  assert.ok(cuerpo.indexOf('data-ficha-basica') > -1 && cuerpo.indexOf('[sec:basica]') > -1, 'ficha básica: lleva su aviso y su sección estable');
  ['contratos', 'cuentas', 'facturas', 'envios', 'soporte', 'docs', 'portal', 'responsable'].forEach((s) => assert.ok(cuerpo.indexOf('[sec:' + s + ']') === -1, 'ficha básica: NO pinta ' + s));
  assert.ok(!w.cajones[0].acciones.some((a) => ['Editar datos', 'Pedir borrado', 'Borrar la ficha'].indexOf(a.texto) > -1), 'ficha básica: ningún botón de escribir');
  assert.ok(!w.cajones[0].acciones.some((a) => a.texto === 'Crear contrato'), 'ficha básica, sin alcance acotado: sin Crear contrato (LAW-E55: comprador_ficha ya no le da la ficha entera)');
  ['rpc:comprador_contratos_resumen', 'rpc:comprador_ficha_datos:soporte', 'rpc:facturas_equipo', 'rpc:correos_registro_datos', 'rpc:comprador_ficha_datos:documentos', 'rpc:comprador_ficha_datos:portal'].forEach((c) => assert.ok(w.calls.indexOf(c) === -1, 'ficha básica: NO pide ' + c));
  assert.ok(w.calls.indexOf('rpc:comprador_ficha_datos:ficha') > -1, 'ficha básica: la ficha sí se pide (y el servidor dice ve=false)');
  assert.strictEqual(w.win.LW_V4.comprador, null, 'ficha básica: ningún editor hereda una ficha');
  // con alcance acotado (empresas marcadas) tampoco: la ficha entera no se le da y el botón acabaría en error
  w = mundo({ fx: sinFilas, win: { LW_V4: { esSuperAdmin: false, esAdmin: false, miEmail: 'a@x.es', ficha: { ambito: 'empresa', empresas: ['lawang'] } } } });
  w.reg.compradores(w.sb); await espera();
  w.win.LW_V4.abreFichaComprador('c1'); await espera();
  assert.ok(!w.cajones[0].acciones.some((a) => a.texto === 'Crear contrato'), 'ficha básica, alcance acotado: sin Crear contrato');
  assert.strictEqual(w.cajones[0].acciones.length, 1, 'ficha básica: solo «Cerrar»');
  // si la lectura de las fichas visibles FALLA no se marca ninguna ni se oculta nada
  w = mundo({ fx: { 'from:clients': { __error: 'x' } } });
  w.reg.compradores(w.sb); await espera();
  assert.ok(w.calls.indexOf('rpc:clientes_lista_datos') > -1, 'la lectura de fichas visibles va por clientes_lista_datos');
  assert.strictEqual(w.tabla.rows.length, 2, 'si falla la lectura de fichas visibles: la lista se pinta igual');

  console.log('OK guarda_clientes.test.js');
})().catch((e) => { console.error(e); process.exit(1); });
