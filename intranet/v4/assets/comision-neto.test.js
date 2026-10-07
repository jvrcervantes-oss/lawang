const assert = require('assert');
const f = require('./comision-neto.js').lwAbonoSinEfecto;
const m = { a: { anulada: true, estado: 'pendiente' }, b: { anulada: true, estado: 'facturada' },
            c: { anulada: true, estado: 'cobrada' }, d: { anulada: true, estado: 'exenta' } };
assert.strictEqual(f({ tipo_linea: 'abono', linea_origen_id: 'a' }, m), true);
assert.strictEqual(f({ tipo_linea: 'abono', linea_origen_id: 'd' }, m), true);
assert.strictEqual(f({ tipo_linea: 'abono', linea_origen_id: 'b' }, m), true); // facturada anulada: cuentan los dos o ninguno
assert.strictEqual(f({ tipo_linea: 'abono', linea_origen_id: 'c' }, m), false);
assert.strictEqual(f({ tipo_linea: 'abono', linea_origen_id: 'zz' }, m), false);
assert.strictEqual(f({ tipo_linea: 'devengo', linea_origen_id: 'a' }, m), false);
console.log('OK comision-neto.test.js — 6 casos');
