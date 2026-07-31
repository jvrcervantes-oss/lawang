/* node facturas/documento.test.js
   Prueba el documento de la factura Y la forma en que lo carga la Edge Function
   `firma-submit` para emitir sola la del primer hito: los cuatro ficheros
   compartidos evaluados juntos en un ámbito, igual que allí. Si esa composición
   se rompe (una global que se renombra, un fichero que deja de exportar lo que
   exportaba), la factura automática dejaría de salir en producción y aquí falla
   antes. */
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const raiz = path.join(__dirname, '..');
const RUTAS = ['contracts/assets/entities.js', 'facturas/totales.js',
               'facturas/compradores.js', 'facturas/documento.js'];

/* Mismo montaje que firma-submit: los cuatro <script> clásicos concatenados y
   evaluados de una vez, publicando lo que hace falta en una caja. */
const caja = {};
new Function('caja',
  RUTAS.map(p => fs.readFileSync(path.join(raiz, p), 'utf8')).join('\n;\n') +
  '\n;Object.assign(caja,{SOCIEDADES,CUENTAS_BANCARIAS,calcTotales,fmtMoneda,parseImporte,' +
  'compradoresDeContrato,nombresFactura,documentosFactura,primerDato,documentoPagina,documentoHTML,TIPOS_DOC});'
)(caja);

['SOCIEDADES','CUENTAS_BANCARIAS','calcTotales','fmtMoneda','parseImporte','compradoresDeContrato',
 'nombresFactura','documentosFactura','primerDato','documentoPagina','documentoHTML','TIPOS_DOC']
  .forEach(k => assert.ok(caja[k], 'firma-submit espera ' + k + ' y no está'));

/* ---- un contrato real-ish: dos compradores y cuatro hitos ---- */
const fields = {
  adq1_nombre: 'Ana López Ruiz', adq1_email: 'ana@example.com',
  adq1_pasaporte: 'X1234567', adq1_domicilio: 'Calle Mayor 1, Madrid',
  proyecto_nombre: 'Bonian Village by Balian Hills', parcela_codigo: 'W8',
  precio_total: '180.000', moneda: 'EUR', sociedad_firmante: 'tepi_sungai',
};
const extras = [{ nombre: 'Marc Vidal', email: 'marc@example.com', pasaporte: 'Y7654321' }];
const hitos = [
  { pct: '25', monto: '', timing: 'a la firma', es: 'Firma y movilización' },
  { pct: '25', monto: '', timing: '', es: 'Fase de obra 1' },
];

const compradores = caja.compradoresDeContrato(fields, extras);
assert.strictEqual(compradores.length, 2, 'la factura va a nombre de los dos que firman');
assert.strictEqual(caja.nombresFactura(compradores), 'Ana López Ruiz · Marc Vidal');

/* ---- el importe del primer hito sale del % sobre el precio, no de la nada ---- */
const precio = caja.parseImporte(fields.precio_total);
assert.strictEqual(precio, 180000, '"180.000" es ciento ochenta mil, no ciento ochenta');
const pct = caja.parseImporte(hitos[0].pct);
const monto = caja.parseImporte(hitos[0].monto) || Math.round(precio * pct / 100 * 100) / 100;
assert.strictEqual(monto, 45000);

const lineas = [{ descripcion: 'Firma y movilización (25% del precio acordado) — a la firma',
                  importe: String(monto) }];
const totales = caja.calcTotales(lineas, 'EUR', { pct: '' });
assert.strictEqual(totales.total, 45000);
assert.strictEqual(totales.impuesto, 0, 'sin porcentaje confirmado, la factura no lleva impuesto');

/* ---- el documento ---- */
const campos = {
  tipo: 'factura', sociedad: 'tepi_sungai', cuenta: '', moneda: 'EUR',
  fecha_emision: '2026-07-31', contrato_numero: 'RP00022',
  cliente_nombre: caja.nombresFactura(compradores),
  cliente_documento: caja.documentosFactura(compradores),
  cliente_email: caja.primerDato(compradores, 'email'),
  proyecto_nombre: 'Bonian Village by Balian Hills — W8',
  imp_etiqueta: '', imp_pct: '', notas: 'Primer hito del contrato RP00022.', lineas,
};
const html = caja.documentoHTML(campos, { numero: 'INV00042' });
assert.ok(html.includes('INV00042'), 'el número emitido va impreso');
assert.ok(html.includes('RP00022'), 'y el contrato del que sale');
assert.ok(html.includes('Ana López Ruiz · Marc Vidal'), 'a nombre de los dos');
assert.ok(html.includes('Ana López Ruiz: X1234567'), 'con varios compradores, cada pasaporte va etiquetado');
assert.ok(/45\.000,00 EUR/.test(html), 'el importe, en formato de la moneda');
assert.ok(!/Impuesto/.test(html), 'sin impuesto configurado no se imprime la fila');

/* ---- sin número (borrador) no se pinta la línea del número ---- */
assert.ok(!caja.documentoHTML(campos, {}).includes('class="num"'),
  'un documento sin número es uno que aún no se ha emitido');

/* ---- página autónoma para el renderizador de PDF ---- */
const pag = caja.documentoPagina(campos, { numero: 'INV00042', base: 'https://lawangproperties.com' });
assert.ok(pag.startsWith('<!DOCTYPE html>'));
assert.ok(pag.includes('https://lawangproperties.com/facturas/documento.css'),
  'el PDF tiene que cargar el MISMO css que la pantalla');
assert.ok(pag.includes('size:A4'));
assert.ok(!/src="\/[^/]/.test(pag),
  'ninguna ruta relativa: el renderizador carga el HTML desde otro sitio y no resolvería');

/* ---- cuenta "Otros": se imprime lo tecleado, y sin nada no se imprime nada ---- */
const conOtros = caja.documentoHTML({ ...campos, cuenta: 'otros', banco_titular: 'PT TEPI SUN GAI',
                                      banco_cuenta: '3692536026' }, {});
assert.ok(conOtros.includes('3692536026') && conOtros.includes('Datos bancarios'));
assert.ok(!caja.documentoHTML({ ...campos, cuenta: 'otros' }, {}).includes('Datos bancarios'),
  'una cabecera "Datos bancarios" con seis guiones es peor que no ponerla');

/* ---- una cuenta dada de alta sigue saliendo de entities.js ---- */
const claveReal = Object.keys(caja.CUENTAS_BANCARIAS)[0];
assert.ok(caja.documentoHTML({ ...campos, cuenta: claveReal }, {})
  .includes(caja.CUENTAS_BANCARIAS[claveReal].cuenta));

console.log('documento.test.js OK');
