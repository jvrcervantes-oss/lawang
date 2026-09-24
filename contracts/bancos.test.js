/* node contracts/bancos.test.js — lectura de extractos y sugerencias.
   Datos INVENTADOS a propósito: el repo es público y un concepto bancario real
   lleva nombres de compradores (revisión previa #67, Seguridad). */
const assert = require('assert');
const path = require('path');
global.lwParseImporte = require(path.join(__dirname, 'assets', 'dinero.js')).lwParseImporte;
const B = require(path.join(__dirname, 'assets', 'bancos.js'));
let n = 0;
const caso = (nombre, fn) => { fn(); n++; };

caso('CSV: comillas, comas dentro de un campo, BOM y separador detectado', () => {
  const t = '﻿Date;Description;Amount\n24/09/2026;"PAGO; REF 1";1.000,50\n25/09/2026;Otro;-20\n';
  assert.strictEqual(B.bancosSeparador(t), ';');
  const f = B.bancosCSV(t);
  assert.deepStrictEqual(f[1], ['24/09/2026', 'PAGO; REF 1', '1.000,50']);
  assert.strictEqual(f.length, 3);
});

caso('fechas: ISO, día primero, mes en letras (inglés y español) y MM/DD cuando el día pasa de 12', () => {
  assert.strictEqual(B.bancosFecha('2026-09-24'), '2026-09-24');
  assert.strictEqual(B.bancosFecha('24/09/2026', 'dmy'), '2026-09-24');
  assert.strictEqual(B.bancosFecha('24 Sep 2026'), '2026-09-24');
  assert.strictEqual(B.bancosFecha('24-Sep-26'), '2026-09-24');
  assert.strictEqual(B.bancosFecha('Sep 24, 2026'), '2026-09-24');
  assert.strictEqual(B.bancosFecha('3 dic 2026'), '2026-12-03');
  assert.strictEqual(B.bancosFecha('31/02/2026', 'dmy'), null);        // no existe
  assert.strictEqual(B.bancosFormatoFecha(['09/24/2026', '09/01/2026']), 'mdy');
  assert.strictEqual(B.bancosFormatoFecha(['01/02/2026']), 'dmy');      // ambiguo: día primero
});

caso('importes: miles con coma o con punto, y los dos negativos de los bancos', () => {
  assert.strictEqual(B.bancosImporte('1,234.56'), 1234.56);
  assert.strictEqual(B.bancosImporte('1.234,56'), 1234.56);
  assert.strictEqual(B.bancosImporte('(1,234.56)'), -1234.56);
  assert.strictEqual(B.bancosImporte('1,234.56-'), -1234.56);
  assert.strictEqual(B.bancosImporte('HKD 2,000.00'), 2000);
  assert.strictEqual(B.bancosImporte(''), null);
});

caso('perfil propuesto: encuentra la cabecera aunque haya líneas antes y separa cargo/abono de saldo', () => {
  const filas = B.bancosCSV('Statement of account\nAccount: XXXX\nTransaction Date,Description,Withdrawal,Deposit,Balance,Currency\n01/09/2026,A,,100.00,100.00,USD\n');
  const p = B.bancosProponerPerfil(filas);
  assert.strictEqual(p.cabecera, 2);
  assert.strictEqual(p.fecha, 0);
  assert.strictEqual(p.cargo, 2);
  assert.strictEqual(p.abono, 3);
  assert.strictEqual(p.saldo, 4);
  assert.strictEqual(p.moneda, 5);
  assert.strictEqual(p.importe, null);
});

caso('leer: signo único desde cargo/abono, moneda por fila, pies del extracto fuera y errores con su línea', () => {
  const t = 'Transaction Date,Description,Withdrawal,Deposit,Balance,Currency\n' +
            '01/09/2026,Cobro cliente ficticio,,5000.00,5000.00,EUR\n' +
            '02/09/2026,Pago proveedor ficticio,1200.00,,3800.00,EUR\n' +
            '99/99/2026,Fecha rota,,1.00,,EUR\n' +
            ',Closing balance,,,3800.00,\n';
  const f = B.bancosCSV(t);
  const r = B.bancosLeer(f, B.bancosProponerPerfil(f), 'cuenta_x', 'EUR');
  assert.deepStrictEqual(r.movimientos.map(m => m.importe), [5000, -1200]);
  assert.strictEqual(r.movimientos[1].saldo, 3800);
  assert.strictEqual(r.errores.length, 1);
  assert.strictEqual(r.errores[0].linea, 4);
});

caso('huella: dos transferencias IDÉNTICAS el mismo día son dos movimientos; reimportar da las mismas huellas', () => {
  const t = 'Date,Description,Amount\n05/09/2026,Transfer,100\n05/09/2026,Transfer,100\n06/09/2026,Transfer,100\n';
  const f = B.bancosCSV(t), p = B.bancosProponerPerfil(f);
  const a = B.bancosLeer(f, p, 'c', 'EUR').movimientos.map(m => m.huella);
  assert.strictEqual(new Set(a).size, 3);
  // un segundo extracto que solo trae el día 05 (solapa): mismas huellas que antes
  const f2 = B.bancosCSV('Date,Description,Amount\n05/09/2026,Transfer,100\n05/09/2026,Transfer,100\n');
  const b = B.bancosLeer(f2, B.bancosProponerPerfil(f2), 'c', 'EUR').movimientos.map(m => m.huella);
  assert.deepStrictEqual(b, a.slice(0, 2));
});

caso('huella: el saldo NO entra (un export lo trae y otro no) y el concepto se normaliza', () => {
  const con = B.bancosLeer(B.bancosCSV('Date,Description,Amount,Balance\n05/09/2026,Pago  x,100,900\n'), null, 'c', 'EUR');
  const f = B.bancosCSV('Date,Description,Amount\n05/09/2026,PAGO X,100\n');
  const sin = B.bancosLeer(f, B.bancosProponerPerfil(f), 'c', 'EUR');
  const fc = B.bancosCSV('Date,Description,Amount,Balance\n05/09/2026,Pago  x,100,900\n');
  const con2 = B.bancosLeer(fc, B.bancosProponerPerfil(fc), 'c', 'EUR');
  assert.strictEqual(con2.movimientos[0].huella, sin.movimientos[0].huella);
  assert.ok(con);
});

caso('sugerencias: mismo signo y moneda, fecha cercana primero, y el número en el concepto gana', () => {
  const mov = { importe: 5000, moneda: 'EUR', fecha: '2026-09-10', concepto: 'PAYMENT REC00123' };
  const cand = [
    { tipo: 'recibi', id: 'a', importe: 5000, moneda: 'EUR', fecha: '2026-09-09', numero: 'REC00100' },
    { tipo: 'recibi', id: 'b', importe: 5000, moneda: 'EUR', fecha: '2026-09-01', numero: 'REC00123' },
    { tipo: 'recibi', id: 'c', importe: 5000, moneda: 'USD', fecha: '2026-09-10', numero: 'REC9' },     // otra moneda
    { tipo: 'gasto',  id: 'd', importe: 5000, moneda: 'EUR', fecha: '2026-09-10', numero: 'G1' },       // otro signo
    { tipo: 'recibi', id: 'e', importe: 5000, moneda: 'EUR', fecha: '2026-08-01', numero: 'REC1' },     // fuera de ventana
  ];
  const s = B.bancosSugerencias(mov, cand);
  assert.deepStrictEqual(s.map(x => x.id), ['b', 'a']);
  assert.strictEqual(s[0].nombra, true);
});

caso('sugerencias: una SWIFT recortada por comisión se sugiere con su diferencia; el pendiente manda sobre el total', () => {
  const mov = { importe: 49985, moneda: 'EUR', fecha: '2026-09-10' };
  const s = B.bancosSugerencias(mov, [{ tipo: 'recibi', id: 'x', importe: 50000, moneda: 'EUR', fecha: '2026-09-10' }]);
  assert.strictEqual(s.length, 1);
  assert.strictEqual(s[0].diferencia, -15);
  assert.strictEqual(B.bancosTolerancia(50000), 50);
  assert.strictEqual(B.bancosTolerancia(300), 1);
  // un recibí ya cobrado a medias: se compara con lo que le FALTA
  const s2 = B.bancosSugerencias({ importe: 2000, moneda: 'EUR', fecha: '2026-09-10' },
    [{ tipo: 'recibi', id: 'y', importe: 5000, pendiente: 2000, moneda: 'EUR', fecha: '2026-09-09' }]);
  assert.strictEqual(s2.length, 1);
});

caso('salidas: sugiere gastos, PPh y comisiones, nunca recibís', () => {
  const s = B.bancosSugerencias({ importe: -980, moneda: 'EUR', fecha: '2026-09-10' }, [
    { tipo: 'gasto', id: 'g', importe: 980, moneda: 'EUR', fecha: '2026-09-11' },
    { tipo: 'recibi', id: 'r', importe: 980, moneda: 'EUR', fecha: '2026-09-10' }]);
  assert.deepStrictEqual(s.map(x => x.tipo), ['gasto']);
});

caso('traspaso entre cuentas propias: se sugiere tanto en la entrada como en la salida', () => {
  const c = [{ tipo: 'traspaso', id: 'm2', importe: 3000, moneda: 'USD', fecha: '2026-09-11' }];
  assert.strictEqual(B.bancosSugerencias({ importe: 3000, moneda: 'USD', fecha: '2026-09-12' }, c).length, 1);
  assert.strictEqual(B.bancosSugerencias({ importe: -3000, moneda: 'USD', fecha: '2026-09-10' }, c).length, 1);
});

caso('celda segura para exportar: fórmulas neutralizadas', () => {
  assert.strictEqual(B.bancosCeldaSegura('=HYPERLINK("x")'), '\'=HYPERLINK("x")');
  assert.strictEqual(B.bancosCeldaSegura('-5'), "'-5");
  assert.strictEqual(B.bancosCeldaSegura('Pago normal'), 'Pago normal');
});

caso('saldo por cuenta y moneda: el último que da el banco; sin saldo, nada inventado', () => {
  const s = B.bancosSaldos([
    { cuenta_clave: 'c', moneda: 'EUR', fecha: '2026-09-01', saldo: 100, orden: 1 },
    { cuenta_clave: 'c', moneda: 'EUR', fecha: '2026-09-02', saldo: 250, orden: 2 },
    { cuenta_clave: 'c', moneda: 'USD', fecha: '2026-09-02', saldo: 7, orden: 3 },
    { cuenta_clave: 'd', moneda: 'EUR', fecha: '2026-09-02', saldo: null },
  ]);
  assert.deepStrictEqual(s.map(x => x.cuenta_clave + x.moneda + x.saldo).sort(), ['cEUR250', 'cUSD7']);
});

console.log('bancos.test.js OK — ' + n + ' casos');
