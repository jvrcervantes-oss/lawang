/* node contracts/saldo_contrato.test.js
   Las reglas de las marcas por hito y del aviso de tope, con los números reales de producción del 5-oct-2026
   (CC00118: precio neto 39.000, INV00184 con dos líneas, 15.000 facturados). Se prueban las reglas, no el pintado. */
const assert = require('assert');
const path = require('path');
const S = require(path.join(__dirname, 'assets', 'saldo_contrato.js'));

const desc = h => [h.texto, h.pct ? '(' + h.pct + '% del precio acordado)' : ''].filter(Boolean).join(' ');
const hitos = [
  { texto: 'Preparación del terreno y movimiento de tierras', pct: 25, monto: 9750 },
  { texto: 'Estructura', pct: 25, monto: 9750 },
  { texto: 'Hito 3', pct: 25, monto: 9750 },
];
const fmt = n => String(n);

// INV00184: dos líneas (9.750 + 5.250). Con 1.000 cobrados se asignan por orden a la primera línea.
const f184 = { id: 'a', numero: 'INV00184', total: 15000, cobrado: 1000, lineas: [
  { descripcion: 'Preparación del terreno y movimiento de tierras (25% del precio acordado)', importe: 9750 },
  { descripcion: 'Estructura (25% del precio acordado)', importe: 5250 }] };

let m = S.lwSaldoMarcasHitos(hitos, [f184], desc);
assert.deepStrictEqual([m[0].facturado, m[0].cobrado], [9750, 1000], 'hito 1: facturado entero, cobrado 1.000');
assert.deepStrictEqual([m[1].facturado, m[1].cobrado], [5250, 0], 'hito 2: facturado a medias, nada cobrado');
assert.deepStrictEqual([m[2].facturado, m[2].cobrado], [0, 0], 'hito 3: sin tocar');
assert.deepStrictEqual(m[1].facturas, ['INV00184']);

// Cobrada del todo: el cobro llena las dos líneas en orden.
m = S.lwSaldoMarcasHitos(hitos, [{ ...f184, cobrado: 15000 }], desc);
assert.deepStrictEqual([m[0].cobrado, m[1].cobrado], [9750, 5250]);

// Una línea con la descripción reescrita a mano deja de contar para el hito (pero no rompe nada).
m = S.lwSaldoMarcasHitos(hitos, [{ id: 'b', numero: 'INV9', total: 100, cobrado: 0, lineas: [{ descripcion: 'Estructura (parte)', importe: 100 }] }], desc);
assert.strictEqual(m[1].facturado, 0);

// Dos facturas del mismo hito se suman.
m = S.lwSaldoMarcasHitos(hitos, [f184, { id: 'c', numero: 'INV9', total: 4500, cobrado: 0,
  lineas: [{ descripcion: 'Estructura (25% del precio acordado)', importe: 4500 }] }], desc);
assert.strictEqual(m[1].facturado, 9750);
assert.deepStrictEqual(m[1].facturas, ['INV00184', 'INV9']);

// Sin importes ni recibís no hay marcas.
assert.strictEqual(S.lwSaldoMarcaHTML({ facturado: 0, cobrado: 0, facturas: [] }, 'EUR', fmt), '');

// Por facturar: si el documento ya está guardado, su propio total se devuelve (se está reescribiendo).
const saldo = { moneda: 'EUR', precio: 59000, por_facturar: 24000, facturas: [{ id: 'a', total: 15000 }] };
assert.strictEqual(S.lwSaldoPorFacturar(saldo, null), 24000);
assert.strictEqual(S.lwSaldoPorFacturar(saldo, 'a'), 39000);
assert.strictEqual(S.lwSaldoPorFacturar({ ...saldo, por_facturar: null }, 'a'), null, 'sin precio no hay tope');

// Aviso: solo cuando se pasa. Con 30.000 sobre 24.000 avisa; con 24.000 exactos, no.
assert.ok(S.lwSaldoAviso(saldo, 30000, null, fmt).includes('24000'));
assert.strictEqual(S.lwSaldoAviso(saldo, 24000, null, fmt), '');
assert.strictEqual(S.lwSaldoAviso({ ...saldo, por_facturar: null }, 99999, null, fmt), '');

// HTML: sin precio no hay barra ni «por facturar» inventado.
const h = S.lwSaldoHTML({ moneda: 'EUR', cadena: 'RP1', precio: null, sin_precio: true, facturado: 69000, cobrado: 0, por_cobrar: 69000, por_facturar: null }, fmt);
assert.ok(h.includes('no tiene precio fijado') && !h.includes('lw-s-b'));

// Con impuesto: el servidor cuenta el SUBTOTAL; el documento guardado (total 1.110, subtotal 1.000) devuelve 1.000, no 1.110.
const conIva = { moneda: 'EUR', precio: 10000, por_facturar: 2000, facturas: [{ id: 'z', total: 1110, subtotal: 1000 }] };
assert.strictEqual(S.lwSaldoPorFacturar(conIva, 'z'), 3000);

// Barra en vivo del editor: el documento que se escribe es un tramo propio y lo que quedaría por facturar.
const sv = { moneda: 'EUR', cadena: 'RP00211', precio: 59000, sin_precio: false, facturado: 35000, cobrado: 35000, por_cobrar: 0, por_facturar: 24000, facturas: [] };
let v = S.lwSaldoHTML(sv, fmt, null, 9750);
assert.ok(v.includes('Este documento') && v.includes('Quedará por facturar') && v.includes('14250'), 'queda 24000-9750');
assert.ok(!v.includes('lw-s-av'), 'cabe: sin aviso');
v = S.lwSaldoHTML(sv, fmt, null, 30000);
assert.ok(v.includes('lw-s-av') && v.includes('lw-s-p lw-r'), 'se pasa: aviso y tramo en rojo');
assert.ok(v.includes('Quedará por facturar</div><div class="lw-s-v lw-r">0'), 'nunca negativo');
v = S.lwSaldoHTML(sv, fmt, null, null);
assert.ok(v.includes('Por facturar') && !v.includes('Este documento'), 'sin borrador (ficha): como antes');
// Documento ya guardado: se cuenta una vez (su importe sale de «facturado» y entra como borrador).
const sg = { ...sv, facturado: 35000, por_facturar: 24000, facturas: [{ id: 'a', total: 15000, subtotal: 15000 }] };
v = S.lwSaldoHTML(sg, fmt, 'a', 15000);
assert.ok(v.includes('24000'), 'quedan 24000+15000-15000 = 24000');
assert.ok(v.includes('<div class="lw-s-k">Facturado</div><div class="lw-s-v">20000'), 'facturado sin el propio');

console.log('saldo_contrato.test.js: ok');
