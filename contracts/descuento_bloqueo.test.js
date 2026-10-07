/* Descuento del Bloqueo en % e importe enlazados (7-oct-2026). `node descuento_bloqueo.test.js`.
   La cuenta vive en lwDescuentoBloqueo (assets/dinero.js); el asistente solo la llama. */
const assert = require('assert');
const { lwDescuentoBloqueo: d, lwImporteCanonico } = require('./assets/dinero.js');

// % manda: el importe baja al céntimo
let r = d(100000, 15, { pct: '10', imp: '', ult: 'pct' });
assert.strictEqual(r.imp, 10000); assert.strictEqual(r.pct, 10); assert.strictEqual(r.fuera, false);
r = d(100.5, 15, { pct: '15', ult: 'pct' });
assert.strictEqual(r.imp, 15.07); assert.strictEqual(r.fuera, false);

// importe manda: el % se deriva, y ida y vuelta no cambia el importe
r = d(100000, 15, { imp: '12500', ult: 'imp' });
assert.strictEqual(r.imp, 12500); assert.strictEqual(r.pct, 12.5); assert.strictEqual(r.fuera, false);

// justo en el tope pasa; un poco por encima no
assert.strictEqual(d(100000, 15, { imp: '15000', ult: 'imp' }).fuera, false);
assert.strictEqual(d(100000, 15, { imp: '15000,01', ult: 'imp' }).fuera, true);
// rupias: 1 IDR por encima del tope (6,7e-8 %) NO se pierde por redondeo
const idr = 1500000000;
assert.strictEqual(d(idr, 15, { imp: '225000000', ult: 'imp' }).fuera, false);
assert.strictEqual(d(idr, 15, { imp: '225000001', ult: 'imp' }).fuera, true);
// admin 50 %, super admin sin tope
assert.strictEqual(d(100000, 50, { imp: '50000', ult: 'imp' }).fuera, false);
assert.strictEqual(d(100000, 50, { imp: '50001', ult: 'imp' }).fuera, true);
assert.strictEqual(d(100000, Infinity, { imp: '99999', ult: 'imp' }).fuera, false);
assert.strictEqual(d(100000, Infinity, { pct: '99', ult: 'pct' }).fuera, false);

// % por encima del tope
assert.strictEqual(d(100000, 15, { pct: '15,5', ult: 'pct' }).fuera, true);

// vacío, cero, negativo, sin lista
r = d(100000, 15, { pct: '', imp: '', ult: 'pct' });
assert.strictEqual(r.imp, 0); assert.strictEqual(r.pct, 0);
assert.ok(d(100000, 15, { imp: '-5', ult: 'imp' }).pct < 0);
r = d(null, 15, { pct: '10', imp: '9999', ult: 'imp' });   // sin lista manda el %
assert.strictEqual(r.imp, 0); assert.strictEqual(r.pct, 10);
assert.strictEqual(d(null, 15, { pct: '20', ult: 'pct' }).fuera, true);

// estado antiguo (sin imp ni ult) cae a modo %
assert.strictEqual(d(100000, 15, { pct: '5' }).imp, 5000);
console.log('descuento_bloqueo.test.js OK');
