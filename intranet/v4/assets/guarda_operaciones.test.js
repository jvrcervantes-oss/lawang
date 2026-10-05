// Operaciones genéricas del ERP maestro (desacople del núcleo comercial, corte C: subtareas 5a + 5b, 5-oct-2026):
// node guarda_operaciones.test.js
//
// DOS cosas, las dos como ARNÉS (se ejecuta el código de verdad con una base y un DOM de mentira), no como lectura del texto:
//
//  A) LA ELECCIÓN de pantalla (el envoltorio `REG['operaciones']` al final de datos.js). Con una `operaciones` contractual
//     de mentira que pide lo suyo a la base y la genérica de mentira, se mide quién se llama en cada estado:
//       sin bandera (Lawang) → SIEMPRE la contractual, mismos argumentos, y el envoltorio no toca la base por su cuenta;
//       maestro con contratos encendido → la contractual; maestro con contratos apagado → la genérica;
//       maestro sin saber aún qué hay encendido → espera y luego decide; la comprobación falla → la contractual (falla abierto);
//       genérica sin cargar → se DICE, no se cae a la contractual (saldría vacía y se leería «no hay operaciones»);
//       pantalla móvil (sin `lw-ops-caja`) → la contractual.
//     Y se MUTA la guarda: cada mutación tiene que romper al menos una de estas comprobaciones, o el test no vale.
//
//  B) LA PANTALLA GENÉRICA (operaciones_generica.js): listado (5a) y ficha (5b) contra una base de mentira.
//       solo RPC de lectura, ninguna lectura directa de tabla, ninguna escritura, nada de contratos;
//       los importes salen TAL CUAL de la base (se prueba con cifras que NO cuadran con las facturas: nada se suma aquí);
//       «no he podido leer» y «no hay» se ven distintos; cifras vacías = «no visible» y no se piden facturas;
//       todo dato entra escapado.
const fs = require('fs'), assert = require('assert'), vm = require('vm');
const src = fs.readFileSync(__dirname + '/datos.js', 'utf8');
const generica = fs.readFileSync(__dirname + '/operaciones_generica.js', 'utf8');
const espera = (ms) => new Promise((r) => setTimeout(r, ms || 15));

// ═══════════════════ A) la elección ═══════════════════
const hIni = src.indexOf('  function moduloEncendido(m) {');
const hFin = src.indexOf('  function clientesContratosCarga');
assert.ok(hIni > 0 && hFin > hIni, 'no encuentro las guardas (moduloEncendido…esperaModulos) en datos.js');
const apoyo = src.slice(hIni, hFin);
const wIni = src.indexOf("  var operacionesContractual = REG['operaciones'];");
const wFin = src.indexOf("  REG['contratos.html'] = REG['contratos'];");
assert.ok(wIni > 0 && wFin > wIni, 'no encuentro el envoltorio REG[\'operaciones\'] en datos.js');
const envoltorio = src.slice(wIni, wFin);

function mundoA(opts, fuenteApoyo, fuenteEnvoltorio) {
  const llamadas = [], base = [], avisos = [];
  const win = Object.assign({}, opts.win || {});
  if (opts.conGenerica !== false) win.lwOperacionesGenerica = function (sb, ay) { llamadas.push('generica'); win._ayudas = ay; return 'g'; };
  const caja = opts.sinCaja ? null : { id: 'lw-ops-caja' };
  const REG = {
    operaciones: function (sb) { llamadas.push('contractual'); win._args = arguments; sb.rpc('contratos_equipo'); sb.rpc('contrato_firmas_equipo'); return 'c'; }
  };
  const sb = { rpc: (n) => { base.push('rpc:' + n); return {}; }, from: (n) => { base.push('from:' + n); return {}; } };
  const vig = (p) => { llamadas.push('vig'); return p; };
  const fallo = (d, e, c) => { avisos.push([d, c]); };
  const ctx = { window: win, document: { getElementById: (id) => (id === 'lw-ops-caja' ? caja : null) }, REG, vig, fallo, esc: (s) => s, fmt: (n) => String(n) };
  vm.createContext(ctx);
  vm.runInContext('(function(){' + fuenteApoyo + '\n' + fuenteEnvoltorio + '\n})()', ctx);
  return { REG, sb, llamadas, base, avisos, win, ctx };
}

async function escenariosA(fuenteApoyo, fuenteEnvoltorio) {
  const fallos = [];
  const comprueba = (cond, msg) => { if (!cond) fallos.push(msg); };
  let w;
  // 1) Lawang: sin bandera. Siempre la contractual, con los mismos argumentos, y el envoltorio no toca la base él mismo.
  w = mundoA({ win: {} }, fuenteApoyo, fuenteEnvoltorio);
  const r1 = w.REG.operaciones(w.sb, 'extra'); await espera();
  comprueba(r1 === 'c', 'Lawang: devuelve lo que devuelve la contractual');
  comprueba(JSON.stringify(w.llamadas) === '["contractual"]', 'Lawang: solo se llama a la contractual (' + w.llamadas + ')');
  comprueba(JSON.stringify(w.base) === '["rpc:contratos_equipo","rpc:contrato_firmas_equipo"]', 'Lawang: la base recibe SOLO lo que pide la contractual (' + w.base + ')');
  comprueba(w.win._args && w.win._args.length === 2 && w.win._args[1] === 'extra', 'Lawang: mismos argumentos');
  // 1b) Lawang aunque lleve un axwModuloActivo que diga «apagado» (no debería existir, pero la bandera manda)
  w = mundoA({ win: { axwModuloActivo: () => false, AXW_MODULOS_LISTOS: Promise.resolve(true) } }, fuenteApoyo, fuenteEnvoltorio);
  w.REG.operaciones(w.sb); await espera();
  comprueba(JSON.stringify(w.llamadas) === '["contractual"]', 'Lawang con un axwModuloActivo ajeno: sigue la contractual (' + w.llamadas + ')');
  // 2) Maestro con contratos encendido
  w = mundoA({ win: { AXW_NUCLEO_OPERACION: true, axwModuloActivo: () => true, AXW_MODULOS_LISTOS: Promise.resolve(true) } }, fuenteApoyo, fuenteEnvoltorio);
  w.REG.operaciones(w.sb); await espera();
  comprueba(w.llamadas.indexOf('contractual') > -1 && w.llamadas.indexOf('generica') === -1, 'maestro con contratos: la contractual (' + w.llamadas + ')');
  // 3) Maestro con contratos APAGADO: la genérica, y la contractual no se llama (ni sus consultas)
  w = mundoA({ win: { AXW_NUCLEO_OPERACION: true, axwModuloActivo: (m) => m !== 'contratos', AXW_MODULOS_LISTOS: Promise.resolve(true) } }, fuenteApoyo, fuenteEnvoltorio);
  w.REG.operaciones(w.sb); await espera();
  comprueba(w.llamadas.indexOf('generica') > -1 && w.llamadas.indexOf('contractual') === -1, 'maestro sin contratos: la genérica y no la contractual (' + w.llamadas + ')');
  comprueba(w.base.length === 0, 'maestro sin contratos: el envoltorio no pide nada contractual (' + w.base + ')');
  comprueba(w.win._ayudas && typeof w.win._ayudas.vig === 'function' && typeof w.win._ayudas.fmt === 'function' && typeof w.win._ayudas.esc === 'function', 'la genérica recibe vig, fmt y esc');
  // 3b) solo otro módulo apagado (soporte): contratos encendido → contractual
  w = mundoA({ win: { AXW_NUCLEO_OPERACION: true, axwModuloActivo: (m) => m !== 'soporte', AXW_MODULOS_LISTOS: Promise.resolve(true) } }, fuenteApoyo, fuenteEnvoltorio);
  w.REG.operaciones(w.sb); await espera();
  comprueba(w.llamadas.indexOf('contractual') > -1 && w.llamadas.indexOf('generica') === -1, 'maestro con soporte apagado (contratos encendido): la contractual');
  // 4) Maestro sin saber aún qué hay encendido: espera, no decide por adelantado, y luego decide
  let listo, sabe = false;
  w = mundoA({ win: { AXW_NUCLEO_OPERACION: true, axwModuloActivo: (m) => (sabe ? m !== 'contratos' : true), AXW_MODULOS_LISTOS: new Promise((r) => { listo = r; }) } }, fuenteApoyo, fuenteEnvoltorio);
  w.REG.operaciones(w.sb); await espera();
  comprueba(w.llamadas.indexOf('contractual') === -1 && w.llamadas.indexOf('generica') === -1, 'cargando lo encendido: todavía no se elige ninguna (' + w.llamadas + ')');
  comprueba(w.llamadas.indexOf('vig') > -1, 'la espera va envuelta en vig() (velo de carga)');
  sabe = true; listo(true); await espera();
  comprueba(w.llamadas.indexOf('generica') > -1 && w.llamadas.indexOf('contractual') === -1, 'tras saberlo (contratos apagado): la genérica (' + w.llamadas + ')');
  // 4b) la comprobación falla: la promesa resuelve false y axwModuloActivo dice «encendido» (falla abierto)
  w = mundoA({ win: { AXW_NUCLEO_OPERACION: true, axwModuloActivo: () => true, AXW_MODULOS_LISTOS: Promise.resolve(false) } }, fuenteApoyo, fuenteEnvoltorio);
  w.REG.operaciones(w.sb); await espera();
  comprueba(w.llamadas.indexOf('contractual') > -1 && w.llamadas.indexOf('generica') === -1, 'sin poder comprobar: la contractual (falla abierto)');
  // 5) Genérica sin cargar con contratos apagado: se DICE y no se cae a la contractual
  w = mundoA({ conGenerica: false, win: { AXW_NUCLEO_OPERACION: true, axwModuloActivo: (m) => m !== 'contratos', AXW_MODULOS_LISTOS: Promise.resolve(true) } }, fuenteApoyo, fuenteEnvoltorio);
  w.REG.operaciones(w.sb); await espera();
  comprueba(w.llamadas.indexOf('contractual') === -1, 'genérica sin cargar: NO se cae a la contractual');
  comprueba(w.avisos.length === 1 && w.avisos[0][0] === 'operaciones', 'genérica sin cargar: se avisa en pantalla');
  // 6) Pantalla móvil (sin lw-ops-caja) con contratos apagado: la de siempre
  w = mundoA({ sinCaja: true, win: { AXW_NUCLEO_OPERACION: true, axwModuloActivo: (m) => m !== 'contratos', AXW_MODULOS_LISTOS: Promise.resolve(true) } }, fuenteApoyo, fuenteEnvoltorio);
  w.REG.operaciones(w.sb); await espera();
  comprueba(w.llamadas.indexOf('contractual') > -1 && w.llamadas.indexOf('generica') === -1, 'pantalla sin lw-ops-caja: la contractual');
  return fallos;
}

// ═══════════════════ B) la pantalla genérica ═══════════════════
function elemento(clave, reg) {
  const e = { clave, style: {}, attrs: {}, handlers: {}, _html: '', textContent: '', value: '' };
  Object.defineProperty(e, 'innerHTML', { get() { return e._html; }, set(v) { e._html = String(v); e.escrituras = (e.escrituras || 0) + 1; } });
  e.querySelector = (s) => reg(clave + '>' + s);
  e.addEventListener = (ev, fn) => { (e.handlers[ev] = e.handlers[ev] || []).push(fn); };
  e.setAttribute = (k, v) => { e.attrs[k] = v; };
  e.getAttribute = (k) => e.attrs[k];
  e.hasAttribute = (k) => Object.prototype.hasOwnProperty.call(e.attrs, k);
  e.closest = (s) => reg('closest:' + clave + ':' + s);
  e.insertBefore = () => {};
  e.nextSibling = null;
  return e;
}

function mundoB(opts) {
  opts = opts || {};
  const calls = [], detalle = [], elementos = {}, toasts = [], cajones = [], consola = [];
  const reg = (k) => (elementos[k] = elementos[k] || elemento(k, reg));
  const fx = Object.assign({
    operaciones_equipo: { data: [
      { id: 'o1', referencia: 'OP-2026-0001', client_id: 'c1', tipo: 'venta', estado: 'abierta', importe_total: 1000, moneda: 'EUR', creado_por: 'ana@x.es', created_at: '2026-10-01T10:00:00Z' },
      { id: 'o2', referencia: '<img src=x onerror=alert(1)>', client_id: 'c2', tipo: 'alquiler', estado: 'borrador', importe_total: null, moneda: 'EUR', creado_por: 'luis@x.es', created_at: '2026-10-02T10:00:00Z' }
    ] },
    compradores_directorio: { data: [{ id: 'c1', full_name: 'Ana Pérez' }, { id: 'c2', full_name: '"><script>alert(2)</script>' }] },
    operacion_cifras: { data: [{ contratado: 1000, facturado: 1234, cobrado: 300, pendiente_facturar: null, pendiente_cobro: 934, a_cuenta_cliente: 50 }] },
    facturas_equipo: { data: [
      { id: 'f1', numero: 'INV-1', tipo: 'factura', total: 10, moneda: 'EUR', anulada: false, rectifica_id: null, created_at: '2026-10-03T10:00:00Z' },
      { id: 'f2', numero: 'INV-2', tipo: 'factura', total: 20, moneda: 'EUR', anulada: false, rectifica_id: null, created_at: '2026-10-04T10:00:00Z' }
    ] },
    facturas_pendiente_equipo: { data: [{ factura_id: 'f1', pendiente: 7 }, { factura_id: 'f2', pendiente: 20 }] }
  }, opts.fx || {});
  const builder = (kind, name, args) => {
    calls.push(kind + ':' + name);
    const d = { kind, name, args, select: null, eq: [], in: [], single: false };
    detalle.push(d);
    const b = {
      select(c) { d.select = c; return b; }, eq(k, v) { d.eq.push([k, v]); return b; }, in(k, v) { d.in.push([k, v]); return b; },
      order() { return b; }, limit(n) { d.limit = n; return b; }, maybeSingle() { d.single = true; return b; },
      then(ok, ko) {
        let r = fx[name];
        if (kind === 'from') r = { error: { message: 'lectura directa de tabla ' + name } };
        if (r && typeof r === 'function') r = r(d);
        r = r || { data: [] };
        if (r.reject) return Promise.reject(r.reject).then(ok, ko);
        let data = r.data;
        if (!r.error && d.in.length && Array.isArray(data)) { const [k, ids] = d.in[0]; data = data.filter((x) => ids.indexOf(x[k]) !== -1); }
        if (!r.error && d.single) data = Array.isArray(data) ? (data[0] || null) : data;
        return Promise.resolve(r.error ? { error: r.error, data: null } : { data, error: null }).then(ok, ko);
      }
    };
    return b;
  };
  const sb = { rpc: (n, a) => builder('rpc', n, a), from: (n) => builder('from', n) };
  const caja = reg('lw-ops-caja'); caja.parentNode = { insertBefore: (n) => { reg('colocada').nodo = n; } };
  const sec = elemento('seccion', reg);
  let abierto = false;
  const H = {
    seccion: (t, inner) => '[sec:' + t + ']' + inner,
    dato: (e, v, o) => '[dato:' + e + '=' + ((v == null || v === '') ? '—' : ((o && o.html) ? v : escB(v))) + ']',
    tabla: (cab, filas) => '[tabla:' + cab.join('|') + ']' + filas.map((f) => '<tr>' + f.join('|') + '</tr>').join(''),
    tag: (t, tono) => '<tag ' + tono + '>' + escB(t) + '</tag>',
    nota: (t, html) => '[nota:' + (html ? t : escB(t)) + ']',
    enlace: (h, t) => '<a href="' + escB(h) + '">' + escB(t) + '</a>',
    cifras: (l) => '[cifras:' + l.map((x) => x[0] + '=' + x[1] + (x[2] ? '(' + x[2] + ')' : '')).join(';') + ']'
  };
  function escB(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])); }
  const win = { AXW_NUCLEO_OPERACION: true, axwModuloActivo: opts.activo || (() => true), lwCajonHtml: H,
    lwCajon: (o) => { abierto = true; const c = { cabecera: o, cuerpo: elemento('cuerpo', reg), pie: elemento('pie', reg) }; cajones.push(c); return c; } };
  const doc = {
    getElementById: (id) => (id === 'lw-ops-caja' ? caja : id === 'lw-opsg' ? (opts.sinSeccion ? null : sec) : id === 'lw-cajon' ? (abierto ? {} : null) : null),
    querySelector: (s) => (s === 'main .lw-cabecera p' ? reg('cabecera-p') : reg('doc:' + s)),
    createElement: () => sec
  };
  doc.querySelector = (s) => {
    if (s === '[data-lw="k-ops"]' || s === '[data-lw="buscador"]') return { closest: () => reg('seccion-vieja:' + s) };
    if (s === 'main [data-accion="nueva-operacion"]') return reg('nueva-operacion');
    return reg('doc:' + s);
  };
  const ctx = { window: win, document: doc, location: { search: opts.search || '', href: '' }, URLSearchParams, Intl, Date, Promise, console: { error: (...a) => consola.push(a.join(' ')), log() {} },
    toast: (t) => toasts.push(['ok', t]), toastMal: (t) => toasts.push(['mal', t]) };
  win.window = win;
  Object.assign(ctx, { Array, String, Number, Object, JSON, Math });
  vm.createContext(ctx);
  vm.runInContext(generica, ctx);
  const ayudas = { vig: (p) => p, esc: escB, fmt: (n, m) => '€' + n + (m === 'EUR' ? '' : ' ' + m), fallo: (d) => toasts.push(['fallo', d]) };
  return { ctx, win, sb, calls, detalle, elementos, toasts, cajones, consola, sec, reg, ayudas, H, escB, cierra() { abierto = false; } };
}
const lista = (w) => w.reg('seccion>[data-opsg-lista]').innerHTML;
// el clic «abrir fila» (delegado en la sección): el ev.target.closest decide por selector
function clic(w, selectorBuscado, atributos) {
  const objetivo = { closest: (s) => (s === selectorBuscado ? { getAttribute: (k) => (atributos || {})[k], hasAttribute: (k) => k in (atributos || {}) } : null) };
  w.sec.handlers.click.forEach((fn) => fn({ target: objetivo, stopPropagation() {}, preventDefault() {} }));
}

(async () => {
  // ── A
  const fallosA = await escenariosA(apoyo, envoltorio);
  assert.deepStrictEqual(fallosA, [], 'la elección de pantalla no se comporta como debe:\n' + fallosA.join('\n'));
  // las mutaciones tienen que romper algo (si no, el test no protege nada)
  const mutaciones = {
    'la guarda siempre manda a la genérica (Lawang incluido)': [(e) => e.replace("if (!window.AXW_NUCLEO_OPERACION) return operacionesContractual.apply(yo, args);", '').replace('contratosActivo() || !caja', 'false || !caja'), apoyo],
    'la guarda siempre manda a la contractual': [(e) => e.replace('contratosActivo() || !caja', 'true'), apoyo],
    'se decide sin esperar a que la base conteste': [(e) => e.replace('espera ? vig(espera).then(elige, elige) : elige()', 'elige()'), apoyo],
    'se cae a la contractual si la genérica no cargó': [(e) => e.replace(/fallo\('operaciones'[^;]*;\s*return;/, 'return operacionesContractual.apply(yo, args);'), apoyo],
    'la elección de Lawang depende del módulo, no de la bandera': [(e) => e.replace("if (!window.AXW_NUCLEO_OPERACION) return operacionesContractual.apply(yo, args);", ''), (a) => a.replace('return !(window.AXW_NUCLEO_OPERACION && !(window.axwModuloActivo ? window.axwModuloActivo(m) : true));', 'return !(window.axwModuloActivo ? !window.axwModuloActivo(m) : false) === false ? false : true;')]
  };
  for (const nombre of Object.keys(mutaciones)) {
    const [fe, fa] = mutaciones[nombre];
    const e2 = fe(envoltorio), a2 = typeof fa === 'function' ? fa(apoyo) : fa;
    assert.notStrictEqual(e2 + a2, envoltorio + apoyo, 'la mutación «' + nombre + '» no cambia nada: el patrón ya no casa con datos.js');
    const f = await escenariosA(a2, e2);
    assert.ok(f.length > 0, 'la mutación «' + nombre + '» NO rompe ninguna comprobación: el test no protege esa guarda');
  }
  // (El bloque `operaciones:` contractual se comparó UNA vez, byte a byte, con el de 9e3d1e00: idéntico. No se deja como test fijo:
  // tras aterrizar, el primer cambio legítimo de esa pantalla lo pondría en rojo. Lo que se queda es la elección y sus mutaciones.)

  // ── B1) listado
  let w = mundoB();
  w.win.lwOperacionesGenerica(w.sb, w.ayudas); await espera();
  assert.deepStrictEqual(w.calls, ['rpc:operaciones_equipo', 'rpc:compradores_directorio'], 'listado: solo la lista y los nombres, y por RPC (' + w.calls + ')');
  const pedido = w.detalle.filter((d) => d.name === 'operaciones_equipo')[0];
  assert.ok(/importe_total/.test(pedido.select) && !/contrato/.test(pedido.select), 'listado: columnas de la operación, nada contractual');
  const nom = w.detalle.filter((d) => d.name === 'compradores_directorio')[0];
  assert.strictEqual(nom.select, 'id,full_name', 'nombres: solo id y nombre (minimización)');
  w.calls.forEach((c) => assert.ok(!/^from:/.test(c) && !/contrato|insert|update|delete|upsert/.test(c), 'listado: ninguna lectura directa ni nada contractual: ' + c));
  const html = lista(w);
  assert.ok(html.indexOf('OP-2026-0001') > -1 && html.indexOf('Ana Pérez') > -1, 'listado: enseña las operaciones de operaciones_equipo con el nombre del cliente');
  assert.ok(html.indexOf('data-accion="abrir-operacion"') > -1 && html.indexOf('data-op-id="o1"') > -1, 'listado: filas enganchadas por data-accion/id');
  assert.ok(html.indexOf('€1000') > -1, 'listado: el importe sale tal cual de la base');
  assert.ok(html.indexOf('sin fijar') > -1, 'listado: una operación sin importe pactado dice «sin fijar», no 0');
  assert.ok(html.indexOf('<img') === -1 && html.indexOf('<script') === -1, 'listado: todo dato escapado (<img/<script crudos en el HTML)');
  assert.ok(html.indexOf('&lt;img') > -1, 'listado: la referencia con marcado sale como texto');
  assert.strictEqual(w.reg('nueva-operacion').style.display, 'none', 'listado: «Nueva operación» (lleva a contratos) oculto, no borrado');
  assert.strictEqual(w.reg('seccion-vieja:[data-lw="k-ops"]').style.display, 'none', 'listado: tarjetas de sumas de la pantalla vieja ocultas');
  assert.strictEqual(w.reg('lw-ops-caja').style.display, 'none', 'listado: la tabla contractual oculta (su marcado no cambia)');

  // B2) cargar falla ≠ no hay operaciones
  w = mundoB({ fx: { operaciones_equipo: { error: { message: 'boom', code: '500' } } } });
  w.win.lwOperacionesGenerica(w.sb, w.ayudas); await espera();
  assert.ok(lista(w).indexOf('No se han podido cargar las operaciones') > -1 && lista(w).indexOf('Todavía no hay operaciones') === -1, 'fallo de carga: se dice que falló, no que no hay');
  assert.ok(w.consola.some((c) => /operaciones_equipo no cargó/.test(c)), 'fallo de carga: queda en consola');
  w = mundoB({ fx: { operaciones_equipo: { data: [] } } });
  w.win.lwOperacionesGenerica(w.sb, w.ayudas); await espera();
  assert.ok(lista(w).indexOf('Todavía no hay operaciones') > -1, 'vacío de verdad: «Todavía no hay operaciones»');
  assert.deepStrictEqual(w.calls, ['rpc:operaciones_equipo'], 'sin operaciones no se piden nombres');

  // B3) clientes apagado: no se piden nombres y se dice
  w = mundoB({ activo: (m) => m !== 'compradores' });
  w.win.lwOperacionesGenerica(w.sb, w.ayudas); await espera();
  assert.deepStrictEqual(w.calls, ['rpc:operaciones_equipo'], 'sin módulo de clientes: no se piden nombres');
  assert.ok(w.reg('seccion>[data-opsg-aviso]').innerHTML.indexOf('módulo de clientes no está activado') > -1, 'sin módulo de clientes: se dice');

  // B4) la ficha: cifras de la base, facturas de la base, nada sumado
  w = mundoB();
  w.win.lwOperacionesGenerica(w.sb, w.ayudas); await espera();
  w.calls.length = 0;
  clic(w, '[data-accion="abrir-operacion"]', { 'data-op-id': 'o1' }); await espera(40);
  assert.deepStrictEqual(w.calls, ['rpc:operacion_cifras', 'rpc:facturas_equipo', 'rpc:facturas_pendiente_equipo'], 'ficha: cifras, facturas y pendiente por RPC, en ese orden (' + w.calls + ')');
  assert.strictEqual(JSON.stringify(w.detalle.filter((d) => d.name === 'operacion_cifras')[0].args), JSON.stringify({ p_op: 'o1' }), 'ficha: las cifras se piden de ESA operación');
  assert.strictEqual(JSON.stringify(w.detalle.filter((d) => d.name === 'facturas_equipo')[0].eq), JSON.stringify([['operacion_id', 'o1']]), 'ficha: facturas filtradas por operación');
  const cuerpo = w.cajones[0].cuerpo.innerHTML;
  assert.ok(cuerpo.indexOf('Facturado=€1234') > -1 && cuerpo.indexOf('Cobrado=€300') > -1 && cuerpo.indexOf('Pendiente de cobro=€934') > -1 && cuerpo.indexOf('A cuenta del cliente=€50') > -1, 'ficha: las cifras son las de operacion_cifras (que aquí NO cuadran con las facturas: nada se calcula en la pantalla)');
  assert.ok(!/€30(?!\d)/.test(cuerpo), 'ficha: nadie suma las facturas (10 + 20) en el navegador');
  assert.ok(/Pendiente de facturar=<span[^>]*>—<\/span>/.test(cuerpo), 'ficha: una cifra que la base da como null se pinta «—», no 0');
  assert.ok(cuerpo.indexOf('INV-1') > -1 && cuerpo.indexOf('€7') > -1 && cuerpo.indexOf('data-accion="abrir-factura"') > -1 && cuerpo.indexOf('data-factura-id="f1"') > -1, 'ficha: facturas con su pendiente de la base y botón por data-accion');
  assert.ok(!w.cajones[0].cabecera.acciones.some((a) => /borrar/i.test(a.texto)), 'ficha: no ofrece «Borrar» (es la 5c)');
  w.calls.forEach((c) => assert.ok(!/^from:|contrato|insert|update|delete|upsert|borrar/.test(c), 'ficha: ninguna lectura directa, escritura ni nada contractual: ' + c));

  // B5) cifras vacías = no visible: no se piden facturas
  w = mundoB({ fx: { operacion_cifras: { data: [] } } });
  w.win.lwOperacionesGenerica(w.sb, w.ayudas); await espera(); w.calls.length = 0;
  clic(w, '[data-accion="abrir-operacion"]', { 'data-op-id': 'o1' }); await espera(40);
  assert.deepStrictEqual(w.calls, ['rpc:operacion_cifras'], 'cifras vacías: no se pide ninguna factura (' + w.calls + ')');
  assert.ok(w.cajones[0].cuerpo.innerHTML.indexOf('no tienes acceso') > -1 && w.cajones[0].cuerpo.innerHTML.indexOf('Facturado=') === -1, 'cifras vacías: se dice «no visible», nunca ceros');

  // B6) las cifras fallan: se dice y no se piden facturas
  w = mundoB({ fx: { operacion_cifras: { error: { message: 'rota' } } } });
  w.win.lwOperacionesGenerica(w.sb, w.ayudas); await espera(); w.calls.length = 0;
  clic(w, '[data-accion="abrir-operacion"]', { 'data-op-id': 'o1' }); await espera(40);
  assert.deepStrictEqual(w.calls, ['rpc:operacion_cifras'], 'cifras con error: no se piden facturas');
  assert.ok(w.cajones[0].cuerpo.innerHTML.indexOf('No se han podido leer las cifras') > -1, 'cifras con error: se dice');

  // B7) facturas apagado / sin facturas / facturas con error
  w = mundoB({ activo: (m) => m !== 'facturas' });
  w.win.lwOperacionesGenerica(w.sb, w.ayudas); await espera(); w.calls.length = 0;
  clic(w, '[data-accion="abrir-operacion"]', { 'data-op-id': 'o1' }); await espera(40);
  assert.deepStrictEqual(w.calls, ['rpc:operacion_cifras'], 'sin módulo de facturas: no se piden');
  assert.ok(w.cajones[0].cuerpo.innerHTML.indexOf('módulo de facturas no está activado') > -1, 'sin módulo de facturas: se dice');
  w = mundoB({ fx: { facturas_equipo: { data: [] } } });
  w.win.lwOperacionesGenerica(w.sb, w.ayudas); await espera();
  clic(w, '[data-accion="abrir-operacion"]', { 'data-op-id': 'o1' }); await espera(40);
  assert.ok(w.cajones[0].cuerpo.innerHTML.indexOf('aún no tiene facturas') > -1, 'sin facturas: se dice');
  w = mundoB({ fx: { facturas_equipo: { error: { message: 'x' } } } });
  w.win.lwOperacionesGenerica(w.sb, w.ayudas); await espera();
  clic(w, '[data-accion="abrir-operacion"]', { 'data-op-id': 'o1' }); await espera(40);
  assert.ok(w.cajones[0].cuerpo.innerHTML.indexOf('No se han podido leer las facturas') > -1, 'facturas con error: se dice (no «sin facturas»)');
  assert.ok(w.cajones[0].cuerpo.innerHTML.indexOf('aún no tiene facturas') === -1, 'facturas con error: no se confunde con «sin facturas»');

  // B8) XSS: nombre y referencia con marcado en la ficha
  w = mundoB();
  w.win.lwOperacionesGenerica(w.sb, w.ayudas); await espera();
  clic(w, '[data-accion="abrir-operacion"]', { 'data-op-id': 'o2' }); await espera(40);
  const c2 = w.cajones[0].cuerpo.innerHTML;
  assert.ok(c2.indexOf('<img') === -1 && c2.indexOf('<script') === -1, 'ficha: ni <img ni <script crudos');

  // B9) enlace profundo a una operación que la base no da a este usuario: se dice y no se rescata por otro camino
  w = mundoB({ search: '?operacion=ajena' });
  w.win.lwOperacionesGenerica(w.sb, w.ayudas); await espera();
  assert.ok(w.toasts.some((t) => t[0] === 'mal' && /No encuentro esa operación/.test(t[1])), '?operacion= ajena: se avisa');
  assert.ok(w.calls.indexOf('rpc:operacion_cifras') === -1, '?operacion= ajena: no se piden cifras');
  w = mundoB({ search: '?operacion=o1' });
  w.win.lwOperacionesGenerica(w.sb, w.ayudas); await espera(60);
  assert.ok(w.cajones.length === 1 && w.calls.indexOf('rpc:operacion_cifras') > -1, '?operacion= propia: abre su ficha');

  console.log('OK guarda_operaciones.test.js');
})().catch((e) => { console.error(e); process.exit(1); });
