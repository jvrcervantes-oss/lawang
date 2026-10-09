/* Test de la pestaña Calendario del portal. `node calendario.test.js`. Lo corre tools/test.py, y con él el gate de push.

   Lo que vigila es lo que la revisión previa del 9-oct-2026 dijo que se rompería:
   · la Carta sustituida no repite en el calendario los pagos de su Bloqueo (Datos);
   · «vencida» sale de la factura, no de la fecha: un hito con fecha pasada sin factura no se pinta vencido, y una
     factura cubierta por un recibí sin aplicar no sale vencida (la regla de Inicio y Facturas);
   · un borrador no aparece; un hito sin fecha no se coloca pero se cuenta;
   · las fechas son días locales, sin el desfase de un día de `new Date('AAAA-MM-DD')`;
   · el texto llega tal cual (sin HTML montado aquí) y el enlace de firma con su token no aparece en ningún evento (Seguridad).

   `estadosHitos` y `num` viven en index.html: se sacan de su código y se evalúan, no se copian — una copia en el test
   pasaría aunque la pantalla cambiara la regla. */
const path = require('path');
const fs = require('fs');

const AQUI = __dirname;
const RAIZ = path.join(__dirname, '..');
const dinero = require(path.join(RAIZ, 'contracts', 'assets', 'dinero.js'));
global.lwParseImporte = dinero.lwParseImporte;
const voc = fs.readFileSync(path.join(RAIZ, 'contracts', 'assets', 'vocabulario.js'), 'utf8');
new Function(voc + '; globalThis.lwEsPreliminar = lwEsPreliminar;')();

const R = require(path.join(AQUI, 'resumen.js'));
const C = require(path.join(AQUI, 'calendario.js'));

function sacaFuncion(src, nombre){
  const i = src.indexOf('function ' + nombre + '(');
  if (i < 0) throw new Error('no encuentro ' + nombre + ' en index.html');
  let j = src.indexOf('{', i), n = 0;
  for (let k = j; k < src.length; k++){
    if (src[k] === '{') n++;
    else if (src[k] === '}' && --n === 0) return src.slice(i, k + 1);
  }
  throw new Error('llaves sin cerrar en ' + nombre);
}
const html = fs.readFileSync(path.join(AQUI, 'index.html'), 'utf8');
const estadosHitos = new Function(sacaFuncion(html, 'num') + '\n' + sacaFuncion(html, 'estadosHitos') + '\nreturn estadosHitos;')();
const DEP = Object.assign({}, R, { estadosHitos: estadosHitos });

let fallos = 0;
const es = (que, dio, esperado) => {
  const ok = JSON.stringify(dio) === JSON.stringify(esperado);
  if (!ok){ fallos++; console.error(`  FALLA  ${que}\n         dio ${JSON.stringify(dio)} · esperaba ${JSON.stringify(esperado)}`); }
};

const HOY = new Date(2026, 9, 9, 10, 0);   // 9-oct-2026, 10:00 local

/* ── fechas ─────────────────────────────────────────────────────────── */
es('diaCal de una cadena de fecha no se va al día anterior', C.diaCal('2026-10-14'), '2026-10-14');
es('diaCal de un Date local', C.diaCal(new Date(2026, 0, 3, 23, 59)), '2026-01-03');
es('diaCal vacío', C.diaCal(''), null);
es('diaCal ilegible', C.diaCal('mañana'), null);
es('diasEntre cruza el cambio de hora', C.diasEntre('2026-10-20', '2026-11-03'), 14);
es('lunesDe un domingo', C.lunesDe('2026-10-11'), '2026-10-05');
es('rejilla de octubre 2026 empieza el lunes 28-sep', C.rejillaMes(2026, 9)[0], '2026-09-28');
es('rejilla de octubre 2026 tiene 5 semanas', C.rejillaMes(2026, 9).length, 35);
es('rejilla de marzo 2026 tiene 6 semanas', C.rejillaMes(2026, 2).length, 42);

/* ── el comprador de prueba: Carta + Bloqueo + Construcción de la misma villa (el caso P-07 de la demo) ── */
const h = (es, fecha, monto) => ({ es: es, en: es, timing: '', fecha: fecha, monto: monto });
const datos = {
  contratos: [
    { id: 'cr', numero: 'P-07-CR', tipo: 'carta_reserva', proyecto: 'Palm Field W5', parcela: 'P-07', precio: 164500, cobrado: 0, moneda: 'USD', firmado: true,
      hitos: [h('Reserva', '2026-05-01', 5000), h('Resto', '2026-11-01', 159500)] },
    { id: 'bp', numero: 'P-07-BP', tipo: 'reserva_parcela', proyecto: 'Palm Field W5', parcela: 'P-07', precio: 38000, cobrado: 38000, moneda: 'USD', firmado: true,
      hitos: [h('Reserva', '2026-06-01', 19000), h('Escritura', '2026-09-01', 19000)] },
    { id: 'co', numero: 'P-07-CO', tipo: 'construccion', proyecto: 'Palm Field W5', parcela: 'P-07', precio: 126500, cobrado: 40300, moneda: 'USD', firmado: true,
      hitos: [h('Anticipo 20 %', '2026-07-01', 25300), h('Cimentación', '2026-10-15', 37950), h('Estructura', '2027-01-06', 37950), h('Entrega <img src=x onerror=alert(1)>', null, 25300)] },
    { id: 'bv', numero: 'BV-01-BP', tipo: 'reserva_parcela', proyecto: 'Bonian Village', parcela: 'BV-01', precio: 30000, cobrado: 3000, moneda: 'USD', firmado: true,
      hitos: [h('Reserva', '2026-08-01', 3000), h('Escritura', '2026-10-04', 27000)] },
    { id: 'sh', numero: 'SH-03-CO', tipo: 'construccion', proyecto: 'Sumba Hills', parcela: 'SH-03', precio: 98000, cobrado: 0, moneda: 'USD', firmado: false,
      hitos: [h('Anticipo 20 %', '2026-10-20', 19600)] },
  ],
  facturas: [
    // el anticipo, facturado y saldado por su recibí: sin él, el cobrado de P-07-CO quedaría «sin aplicar» y cubriría la cimentación
    { id: 'f3', numero: 'LW-0131', tipo: 'factura', contrato_id: 'co', contrato_numero: 'P-07-CO', fecha: '2026-06-28', total: 25300, moneda: 'USD', aplicado: 25300,
      lineas: [{ descripcion: 'Anticipo 20 %', importe: 25300 }], fields: { fecha_vencimiento: '2026-07-01' } },
    { id: 'f1', numero: 'LW-0142', tipo: 'factura', contrato_id: 'co', contrato_numero: 'P-07-CO', fecha: '2026-10-06', total: 37950, moneda: 'USD', aplicado: 15000,
      lineas: [{ descripcion: 'Cimentación', importe: 37950 }], fields: { fecha_vencimiento: '2026-10-15' } },
    { id: 'f8', numero: 'LW-0147', tipo: 'factura', contrato_id: 'bv', contrato_numero: 'BV-01-BP', fecha: '2026-09-19', total: 27000, moneda: 'USD', aplicado: 0,
      lineas: [{ descripcion: 'Escritura', importe: 27000 }], fields: { fecha_vencimiento: '2026-10-04' } },
    { id: 'f9', numero: 'LW-0150', tipo: 'factura', contrato_id: 'co', contrato_numero: 'P-07-CO', fecha: '2026-10-01', total: 1200, moneda: 'USD', aplicado: 0,
      lineas: [{ descripcion: 'Extra: piscina', importe: 1200 }], fields: { fecha_vencimiento: '2026-10-25' } },
    { id: 'r1', numero: 'REC-2026-0061', tipo: 'recibi', contrato_numero: 'P-07-CO', fecha: '2026-10-08', total: 15000, moneda: 'USD' },
  ],
  firma_pendiente: [{ contrato_id: 'sh', enlace: 'https://firma.example/?t=SECRETO123', enviado_en: '2026-10-06T03:00:00Z', expira_en: '2026-10-20T03:00:00Z' }],
  obra: [
    { unidad: 'P-07', proyecto: 'Palm Field W5', contrato_numero: 'P-07-CO', fase: 'estructura', fecha_entrega: '2027-08-15',
      fotos: [{ titulo: 'Estructura norte', fecha: '2026-10-05' }, { titulo: 'Pilares', fecha: '2026-10-05' }, { titulo: 'Losa', fecha: '2026-09-28' }] },
  ],
  proyectos: [{ id: 'pr1', nombre: 'Palm Field W5', entrega: '2027-09-01' }, { id: 'pr3', nombre: 'Bonian Village', entrega: '2027-12-01' }],
  kyc: [{ tipo: 'passport', caduca: '2026-10-22' }, { tipo: 'kitas', caduca: '2026-11-28' }, { tipo: 'id', caduca: '2027-12-02' }, { tipo: 'npwp', caduca: null }],
};
const ev = C.eventosCalendario(datos, HOY, DEP);
const de = pref => ev.filter(e => e.id.indexOf(pref) === 0);
const uno = id => ev.filter(e => e.id === id)[0] || null;

/* Carta sustituida: ninguno de sus hitos sale */
es('la Carta sustituida no pinta sus hitos', de('hito:cr:').length, 0);
/* Borrador: sin pagos; su firma sí */
es('un borrador no pinta pagos', de('hito:sh:').length, 0);
es('la firma pendiente sale el día local en que caduca el enlace', uno('firma:sh') && uno('firma:sh').dia, '2026-10-20');
es('la firma pendiente pide algo y su estado es «por firmar», no «pendiente» de pago', [uno('firma:sh').pide, uno('firma:sh').estado], [true, 'firmar']);
es('el token del enlace de firma no aparece en ningún evento', JSON.stringify(ev).indexOf('SECRETO123'), -1);

/* Construcción: anticipo pagado, cimentación parcial con su factura, estructura pendiente, entrega sin fecha */
es('anticipo pagado', uno('hito:co:0').estado, 'pagado');
es('cimentación parcial, falta lo no cobrado', [uno('hito:co:1').estado, uno('hito:co:1').falta, uno('hito:co:1').factura], ['parcial', 22950, 'LW-0142']);
es('estructura pendiente sin factura lleva a Contratos', [uno('hito:co:2').estado, uno('hito:co:2').ir], ['pendiente', 'contratos']);
es('un hito sin fecha no se coloca', de('hito:co:3').length, 0);
es('y se cuenta como sin fecha', C.hitosSinFecha(datos, DEP), 1);
es('el texto del hito llega tal cual, sin montar HTML', uno('hito:co:2').hito.es, 'Estructura');

/* Bonian: la escritura con factura vencida es vencida; su factura no se repite como evento suelto */
es('escritura BV-01 vencida por su factura', [uno('hito:bv:1').estado, uno('hito:bv:1').clase], ['vencida', 'vencida']);
es('la factura del hito no sale dos veces', de('factura:f8').length, 0);
/* Bloqueo P-07 pagado entero: sus hitos salen como pagados (escritura con fecha pasada, sin factura, no vencida) */
es('bloqueo pagado', uno('hito:bp:1').estado, 'pagado');

/* «vencida» nunca por la fecha sola: hito pasado sin factura */
const sinFactura = C.eventosCalendario({ contratos: [{ id: 'x', numero: 'X-1', tipo: 'construccion', precio: 1000, cobrado: 0, moneda: 'USD', firmado: true,
  hitos: [h('Pago', '2026-09-01', 1000)] }], facturas: [] }, HOY, DEP);
es('hito con fecha pasada y sin factura no se pinta vencido', sinFactura[0].estado, 'pendiente');
/* factura cubierta por un recibí sin aplicar: pagada, no vencida (saldoSinAplicar) */
const cubierta = C.eventosCalendario({ contratos: [{ id: 'y', numero: 'Y-1', tipo: 'construccion', precio: 1000, cobrado: 1000, moneda: 'USD', firmado: true,
  hitos: [h('Pago', '2026-09-01', 1000)] }], facturas: [{ id: 'fy', numero: 'LW-9', tipo: 'factura', contrato_id: 'y', contrato_numero: 'Y-1', fecha: '2026-08-25', total: 1000,
  aplicado: 0, lineas: [{ descripcion: 'Pago', importe: 1000 }], fields: { fecha_vencimiento: '2026-09-01' } }] }, HOY, DEP);
es('factura cubierta por un recibí sin aplicar no sale vencida', cubierta[0].estado, 'pagado');

/* Factura suelta (no es de ningún hito) y pendiente: sale en su vencimiento */
es('factura suelta pendiente', [uno('factura:f9') && uno('factura:f9').dia, uno('factura:f9') && uno('factura:f9').estado], ['2026-10-25', 'pendiente']);
/* Recibo */
es('el recibo sale como recibido', uno('recibo:r1') && uno('recibo:r1').estado, 'recibido');

/* Obra: una entrega por unidad; la del proyecto solo si no hay unidad; un evento por día de fotos */
es('entrega de la unidad', uno('entrega:P-07') && uno('entrega:P-07').dia, '2027-08-15');
es('la entrega del proyecto con unidad no se repite', de('entrega-proy:pr1').length, 0);
es('la entrega del proyecto sin unidad sí sale', de('entrega-proy:pr3').length, 1);
es('dos fotos del mismo día son un evento', uno('fotos:P-07:2026-10-05') && uno('fotos:P-07:2026-10-05').n, 2);

/* Documentos: misma cuenta que Inicio y Mi perfil (30 días) */
es('pasaporte caduca pronto y pide', [uno('doc:passport:0').estado, uno('doc:passport:0').pide], ['pronto', true]);
es('KITAS a 50 días no pide todavía', [uno('doc:kitas:1').estado, uno('doc:kitas:1').pide], ['ok', false]);
es('un documento sin caducidad no sale', de('doc:npwp').length, 0);

/* Pendiente de ti: vencido primero, luego por fecha */
es('pendientes en orden', C.pendientesCalendario(ev).map(e => e.id),
   ['hito:bv:1', 'hito:co:1', 'firma:sh', 'doc:passport:0', 'factura:f9']);

/* Comprador sin nada: no rompe */
es('sin datos, sin eventos', C.eventosCalendario({}, HOY, DEP).length, 0);
es('sin datos, sin hitos sin fecha', C.hitosSinFecha({}, DEP), 0);

if (fallos){ console.error(`calendario.test.js: ${fallos} fallo(s)`); process.exit(1); }
console.log('calendario.test.js: ok');
