/* node contracts/facturas_contratos.test.js
   ============================================================================
   Las reglas que deciden cómo va de cobrado un contrato. Cada caso de aquí es
   un fallo REAL que se corrigió con dinero delante, no un caso inventado:
   mientras vivieron dentro del HTML de una herramienta no tuvieron test, y las
   dos primeras se descubrieron mirando la pantalla con los datos de producción.

   Se prueban las REGLAS, no el pintado. */
const assert = require('assert');
const path = require('path');
const { lwAgrupaPorContrato } = require(path.join(__dirname, 'assets', 'facturas_contratos.js'));

/* `facturas_contratos.js` usa las globales de dinero.js, igual que en el
   navegador. Se cargan al ámbito global ANTES de llamar a nada — y no con un
   `require` dentro del módulo, que es exactamente el fallo que tiró cuatro
   pantallas el 26-ago: en node `require` existe y en el navegador no, así que
   el test corría por un camino que producción no toma nunca. */
Object.assign(globalThis, require(path.join(__dirname, 'assets', 'dinero.js')));

let fallos = 0;
const ok = (t, f) => { try { f(); console.log('  ok   ' + t); }
                       catch (e) { fallos++; console.log('  FALLA ' + t + '\n         ' + e.message); } };

const doc = (o) => ({ tipo:'factura', total:0, moneda:'EUR', anulada:false,
                      contrato_id:'c1', contrato_numero:'CC1', fecha_emision:'2026-01-01', ...o });
const uno = (docs) => lwAgrupaPorContrato(docs)[0];

ok('🔴 «solo proforma» EXIGE que tampoco se haya cobrado', () => {
  // 26-ago-2026: sin esta condición, dos contratos con 190.620 € YA COBRADOS
  // salían rotulados «solo proforma» — el cartel decía que allí no había
  // pasado nada.
  const c = uno([doc({ tipo:'proforma', total:44000 }), doc({ tipo:'recibi', total:12500 })]);
  assert.strictEqual(c.soloProforma, false, 'hay dinero cobrado: eso no es «solo proforma»');
  assert.strictEqual(c.cobradoSinFactura, true, 'y ese caso tiene nombre propio');
});

ok('cobro sin factura que lo respalde es su propio estado', () => {
  const c = uno([doc({ tipo:'recibi', total:9000 })]);
  assert.strictEqual(c.cobradoSinFactura, true);
  assert.strictEqual(c.soloProforma, false);
  assert.strictEqual(c.sinRecibi, false);
});

ok('solo proforma de verdad: ni factura ni cobro', () => {
  const c = uno([doc({ tipo:'proforma', total:25000 })]);
  assert.strictEqual(c.soloProforma, true);
  assert.strictEqual(c.cobradoSinFactura, false);
});

ok('facturado y sin un solo recibí', () => {
  const c = uno([doc({ tipo:'factura', total:44000 })]);
  assert.strictEqual(c.sinRecibi, true);
  assert.strictEqual(c.pct, 0);
});

ok('🔴 el porcentaje NO se recorta a 100', () => {
  // Cobrar más de lo facturado es una NOTICIA —falta una factura, o hay un
  // cobro duplicado—. Un Math.min(100, …) la convertía en un contrato
  // perfectamente cerrado: 277 % se leía «100 %».
  const c = uno([doc({ tipo:'factura', total:60000 }), doc({ tipo:'recibi', total:166610 })]);
  assert.ok(c.pct > 100, `se esperaba más de 100, dio ${c.pct}`);
  assert.strictEqual(Math.round(c.pct), 278);
});

ok('un documento ANULADO no suma, pero sigue en el grupo', () => {
  const c = uno([doc({ tipo:'factura', total:44000 }),
                 doc({ tipo:'factura', total:99999, anulada:true })]);
  assert.strictEqual(c.totalFacturado, 44000, 'anular es decir que ese importe no cuenta');
  assert.strictEqual(c.docs.length, 2, 'pero el documento se sigue viendo');
});

ok('🔴 dos monedas: se suman por separado y NO hay porcentaje', () => {
  // Dividir entre divisas distintas da una cifra que no existe en ninguna parte
  // — el fallo que costó el arreglo de Proyectos el 26-ago.
  const c = uno([doc({ tipo:'factura', total:44000, moneda:'EUR' }),
                 doc({ tipo:'factura', total:11038000000, moneda:'IDR' }),
                 doc({ tipo:'recibi',  total:12500, moneda:'EUR' })]);
  assert.strictEqual(c.unaMoneda, null, 'con dos monedas no se elige una');
  assert.strictEqual(c.pct, 0, 'sin porcentaje: mezclarlas sería inventar');
  assert.strictEqual(c.facturado.EUR, 44000);
  assert.strictEqual(c.facturado.IDR, 11038000000);
});

ok('🔴 los documentos SIN contrato no se suman entre sí', () => {
  // 26-ago-2026: caían todos en una tarjeta con el nombre del PRIMER cliente y
  // la suma de los doce — 60.000 € facturados contra 166.610 € cobrados,
  // atribuidos a una persona que no tenía que ver con diez de ellos.
  const c = uno([doc({ contrato_id:null, cliente_nombre:'Ana',  total:1000 }),
                 doc({ contrato_id:null, cliente_nombre:'Luis', total:2000 })]);
  assert.strictEqual(c.sinContrato, true);
  assert.strictEqual(c.variosClientes, true, 'no hay UN cliente de ese grupo');
});

ok('cada contrato es su propio grupo', () => {
  const g = lwAgrupaPorContrato([
    doc({ contrato_id:'a', contrato_numero:'CC1', total:100 }),
    doc({ contrato_id:'b', contrato_numero:'CC2', total:200 }),
  ]);
  assert.strictEqual(g.length, 2);
});

ok('el orden lo manda la actividad más reciente', () => {
  const g = lwAgrupaPorContrato([
    doc({ contrato_id:'a', contrato_numero:'A', fecha_emision:'2026-01-01' }),
    doc({ contrato_id:'b', contrato_numero:'B', fecha_emision:'2026-06-01' }),
  ]);
  assert.deepStrictEqual(g.map(x => x.numero), ['B', 'A']);
});

console.log(fallos ? `\n${fallos} fallo(s)` : '\nOK facturas_contratos.test.js — 10 reglas de cobro, todas con su fallo real detrás');
process.exit(fallos ? 1 : 0);
