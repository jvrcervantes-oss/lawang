// Ajustes › plazos: qué filas de `parametros` se pintan según el módulo `reservas` (idiomas-pH, 12-oct-2026): node parametros_visibles.test.js
//
// Corre de verdad moduloEncendido() y parametrosVisibles() extraídos de datos.js tal cual, con y sin la bandera de instancia:
//   1. sin bandera (Lawang): se pintan TODAS las filas, también las reservas.*, y la sección no se oculta nunca;
//   2. instancia con reservas encendido: todas;
//   3. instancia con reservas apagado: fuera las reservas.*, se quedan las del núcleo (construccion.*, que lee hitos_fechas.js);
//   4. instancia sin saber aún qué hay encendido (axwModuloActivo falla abierto): todas.
const fs = require('fs'), assert = require('assert');
const src = fs.readFileSync(__dirname + '/datos.js', 'utf8');
const ini = src.indexOf('  function moduloEncendido(m) {');
const fin = src.indexOf('  function soporteActivo()');
assert.ok(ini > 0 && fin > ini, 'no encuentro moduloEncendido/parametrosVisibles en datos.js');
const trozo = src.slice(ini, fin);
assert.ok(trozo.indexOf('function parametrosVisibles(') > -1, 'parametrosVisibles ya no está junto a moduloEncendido');

function corre(window) {
  return new Function('window', trozo + '\nreturn { moduloEncendido: moduloEncendido, parametrosVisibles: parametrosVisibles };')(window);
}
const FILAS = [{ clave: 'reservas.dias_gracia' }, { clave: 'reservas.techo_prorrogas' }, { clave: 'construccion.pago_unico_max_dias' }];
const claves = (rs) => rs.map((r) => r.clave).join(',');

// 1. Lawang: sin bandera
let w = corre({});
assert.strictEqual(claves(w.parametrosVisibles(FILAS, w.moduloEncendido)), claves(FILAS), 'Lawang: tienen que salir todas las filas');
assert.strictEqual(w.moduloEncendido('reservas'), true, 'Lawang: reservas cuenta como encendido (la sección nunca se oculta)');

// 2. instancia con reservas encendido
w = corre({ AXW_NUCLEO_OPERACION: true, axwModuloActivo: (m) => m === 'reservas' });
assert.strictEqual(claves(w.parametrosVisibles(FILAS, w.moduloEncendido)), claves(FILAS), 'reservas encendido: todas las filas');

// 3. instancia con reservas apagado
w = corre({ AXW_NUCLEO_OPERACION: true, axwModuloActivo: () => false });
assert.strictEqual(claves(w.parametrosVisibles(FILAS, w.moduloEncendido)), 'construccion.pago_unico_max_dias', 'reservas apagado: solo fuera las reservas.*');
assert.strictEqual(w.parametrosVisibles([{ clave: 'reservas.dias_gracia' }], w.moduloEncendido).length, 0, 'solo filas de reservas: no queda ninguna');
assert.strictEqual(w.moduloEncendido('reservas'), false);

// 4. instancia sin saber todavía (apagados_instancia.js falla abierto con true)
w = corre({ AXW_NUCLEO_OPERACION: true, axwModuloActivo: () => true });
assert.strictEqual(claves(w.parametrosVisibles(FILAS, w.moduloEncendido)), claves(FILAS), 'sin saber: todas');

// entradas raras: sin filas, fila sin clave
assert.deepStrictEqual(w.parametrosVisibles(null, w.moduloEncendido), []);
assert.strictEqual(corre({ AXW_NUCLEO_OPERACION: true, axwModuloActivo: () => false }).parametrosVisibles([{}], () => false).length, 1, 'una fila sin clave no es de reservas');

// REG.ajustes usa el filtro y no oculta la sección entera sin mirar las filas
const a0 = src.indexOf("  REG['ajustes'] = function (sb) {");
const a1 = src.indexOf('  function impuestosAjustes(sb, soloLee) {');
assert.ok(a0 > 0 && a1 > a0, 'no encuentro REG.ajustes');
const ajustes = src.slice(a0, a1);
assert.ok(ajustes.indexOf('parametrosVisibles(rows, moduloEncendido)') > -1, 'REG.ajustes ya no filtra las filas con parametrosVisibles');
assert.ok(/secPlazos\.hidden = !rows\.length && !moduloEncendido\('reservas'\)/.test(ajustes), 'la sección solo se oculta si no queda ninguna fila y reservas está apagado');
console.log('ok parametros_visibles.test.js');
