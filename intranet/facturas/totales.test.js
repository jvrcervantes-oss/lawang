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

/* Impuestos del catálogo (ERP maestro, AXW-39): réplica de public.factura_totales.
   Cada caso es una cifra que el servidor da igual; si no, factura_guarda rechaza. */
const { impuestoDelDocumento } = require('./totales.js');
const PPN_FR = { nombre: 'PPN 12 % (base 11/12)', clase: 'suma', porcentaje: 12, coef_base: 0.916667, coef_base_num: 11, coef_base_den: 12 };
const PPN_SIN = { nombre: 'PPN 12 % (base 0,916667)', clase: 'suma', porcentaje: 12, coef_base: 0.916667 };
const IVA21 = { nombre: 'IVA 21 %', clase: 'suma', porcentaje: 21, coef_base: 1 };
const IRPF15 = { nombre: 'IRPF 15 %', clase: 'retiene', porcentaje: 15, coef_base: 1 };
const EXENTA = { nombre: 'Exenta de IVA', clase: 'exenta', porcentaje: 0, coef_base: 1, motivo_legal: 'Operación exenta de IVA, art. 20.Uno LIVA' };
// PPN sobre 11/12 exacto: la cabecera de B1 midió 277.500.000 con la fracción y 277.500.010 con 0,916667
const p1 = calcTotales([{importe:'250.000.000'}], 'IDR', { lista: [PPN_FR] });
assert.strictEqual(p1.resumen[0].base_imponible, 229166667);
assert.strictEqual(p1.impuesto, 27500000);
assert.strictEqual(p1.total, 277500000);
assert.strictEqual(calcTotales([{importe:'250.000.000'}], 'IDR', { lista: [PPN_SIN] }).total, 277500010);
// IVA + IRPF: 1.000 + 210 − 150
const p2 = calcTotales([{importe:'600'},{importe:'400'}], 'EUR', { lista: [IVA21, IRPF15] });
assert.strictEqual(p2.impuesto, 210);
assert.strictEqual(p2.retenido, 150);
assert.strictEqual(p2.total, 1060);
// exenta: cuota 0, la mención viaja en el resumen
const p3 = calcTotales([{importe:'500'}], 'EUR', { lista: [EXENTA] });
assert.strictEqual(p3.total, 500);
assert.strictEqual(p3.resumen[0].cuota, 0);
assert.strictEqual(p3.resumen[0].motivo_legal, EXENTA.motivo_legal);
// medio céntimo hacia arriba (36,245 → 36,25), como round(numeric)
assert.strictEqual(calcTotales([{importe:'329,50'}], 'EUR', { lista: [{ nombre: 'x', clase: 'suma', porcentaje: 11, coef_base: 1 }] }).total, 365.75);
// rectificativa (líneas en negativo): alejándose de cero
const p4 = calcTotales([{importe:'-1.000'}], 'EUR', { lista: [IVA21] });
assert.strictEqual(p4.impuesto, -210);
assert.strictEqual(p4.total, -1210);
// selección vacía o ausente → el porcentaje libre de siempre (Lawang)
assert.deepStrictEqual(impuestoDelDocumento({ imp_pct: '11' }), { pct: '11' });
assert.deepStrictEqual(impuestoDelDocumento({ imp_pct: '11', impuestos_sel: [] }), { pct: '11' });
assert.deepStrictEqual(impuestoDelDocumento({ impuestos_sel: [IVA21] }), { lista: [IVA21] });
// decimales = public.moneda_decimales (JPY, KRW, VND, CLP sin decimales)
assert.strictEqual(fmtMoneda(1500, 'JPY'), '1.500 JPY');
assert.strictEqual(fmtMoneda(1500, 'CLP'), '1.500 CLP');

console.log('OK totales de facturas');
