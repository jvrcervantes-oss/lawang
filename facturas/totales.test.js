/* node facturas/totales.test.js — falla si la aritmética de dinero se rompe. */
const assert = require('assert');
const { parseImporte, calcTotales, fmtMoneda } = require('./totales.js');

// lectura de importes tecleados a mano
assert.strictEqual(parseImporte('1.500,50'), 1500.5);   // formato europeo
assert.strictEqual(parseImporte('1,500.50'), 1500.5);   // formato anglosajón
assert.strictEqual(parseImporte('1.500'), 1500);        // punto de miles, no decimal
assert.strictEqual(parseImporte('1500'), 1500);
assert.strictEqual(parseImporte('€ 12.345,67'), 12345.67);
assert.strictEqual(parseImporte('250.000.000'), 250000000);  // rupias
assert.strictEqual(parseImporte(''), 0);
assert.strictEqual(parseImporte(null), 0);
assert.strictEqual(parseImporte('abc'), 0);
assert.strictEqual(parseImporte('-300,25'), -300.25);

// suma sin arrastrar error de coma flotante
const t1 = calcTotales([{importe:'0,10'},{importe:'0,20'}], 'EUR', null);
assert.strictEqual(t1.subtotal, 0.3);
assert.strictEqual(t1.total, 0.3);
assert.strictEqual(t1.impuesto, 0);

// impuesto opcional: sin porcentaje no hay fila
const base = [{importe:'1.000'},{importe:'500,50'}];
assert.strictEqual(calcTotales(base, 'EUR', {pct:''}).total, 1500.5);
const t2 = calcTotales(base, 'EUR', {pct:'11'});
assert.strictEqual(t2.subtotal, 1500.5);
assert.strictEqual(t2.impuesto, 165.06);          // 165.055 → 165.06
assert.strictEqual(t2.total, 1665.56);

// la rupia no lleva céntimos
const t3 = calcTotales([{importe:'250.000.000'}], 'IDR', {pct:'11'});
assert.strictEqual(t3.impuesto, 27500000);
assert.strictEqual(t3.total, 277500000);
assert.strictEqual(fmtMoneda(t3.total, 'IDR'), '277.500.000 IDR');
assert.strictEqual(fmtMoneda(1500.5, 'EUR'), '1.500,50 EUR');

// factura vacía
assert.deepStrictEqual(calcTotales([], 'EUR', null), {subtotal:0, pct:0, impuesto:0, total:0});

console.log('OK totales de facturas');
