/* node cobrado_venta.test.js — factura-vencimiento descuenta lo cobrado de la VENTA con la regla «primero la parcela,
   luego la obra» (owner, 14-oct-2026; F5 del encargo de la agencia 20261014_lawang_cobro_primero_parcela). Comprueba:
   1. lo cobrado sale de _contrato_cobrado_venta (la base reparte la venta; la edge no recalcula la cascada);
   2. solo cae a lo de siempre (contrato_cobrado + sus Cartas) cuando la función NO existe (PGRST202: bbm, demo);
   3. ningún error de lectura de lo cobrado se convierte en 0: con 0 se facturaría el hito bruto (el fallo del 11-ago). */
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const src = fs.readFileSync(path.join(__dirname, 'index.ts'), 'utf8').replace(/\r\n/g, '\n');
const ini = src.indexOf('// ── lo pendiente DE VERDAD');
const fin = src.indexOf('const anotados = C.cascada(');
assert(ini > 0 && fin > ini, 'no encuentro el bloque de lo cobrado');
const bloque = src.slice(ini, fin);

// 1
assert(/sb\.rpc\('_contrato_cobrado_venta', \{ p_contrato: v\.contrato_id \}\)/.test(bloque), 'lo cobrado no sale de _contrato_cobrado_venta');

// 2: la rama de respaldo va colgada de PGRST202 y es la única que llama a contrato_cobrado
const respaldo = bloque.indexOf("=== 'PGRST202'");
assert(respaldo > 0, 'el respaldo no está limitado a PGRST202');
const primeraVieja = bloque.indexOf("sb.rpc('contrato_cobrado'");
assert(primeraVieja > respaldo, 'contrato_cobrado se llama fuera de la rama PGRST202');

// 3: cada lectura de lo cobrado comprueba su error antes de usar .data
for (const [lectura, uso] of [
  ['cobVenta.error', 'Number(cobVenta.data)'],
  ['cobradoPropio.error', 'Number(cobradoPropio.data)'],
  ['r.error', 'Number(r.data)'],
]) {
  const e = bloque.indexOf(lectura), u = bloque.indexOf(uso);
  assert(e > 0 && u > 0 && e < u, uso + ' se usa sin mirar antes ' + lectura);
}
assert(/else \{\s*throw new Error\('lo cobrado de la venta: '/.test(bloque), 'un error que no es PGRST202 no frena la factura');

console.log('ok cobrado_venta.test.js — 3 comprobaciones');
