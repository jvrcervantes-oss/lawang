/* Test de las cuentas del área de clientes. `node resumen.test.js`.
   Lo corre tools/test.py, y con él el gate de push.

   Los casos NO son inventados: son los cuatro compradores con acceso activo al
   portal que el 14-sep-2026 veían el doble de lo que deben, sacados de la base
   de producción con sus importes exactos. Si esta pantalla vuelve a sumar la
   Carta de Reserva, estos números lo dicen antes de que lo diga el cliente. */
const path = require('path');
const fs = require('fs');

const AQUI = __dirname;
const RAIZ = path.join(__dirname, '..');
/* Las globales de la suite se cargan igual que las carga el navegador: el
   parseo de importes (dinero.js) y la lista de tipos preliminares
   (vocabulario.js). Se evalúan, no se copian — una lista a mano dentro del
   guardrail ES el bug que el guardrail viene a cazar. */
const dinero = require(path.join(RAIZ, 'contracts', 'assets', 'dinero.js'));
global.lwParseImporte = dinero.lwParseImporte;
const voc = fs.readFileSync(path.join(RAIZ, 'contracts', 'assets', 'vocabulario.js'), 'utf8');
new Function(voc + '; globalThis.lwEsPreliminar = lwEsPreliminar;')();

const R = require(path.join(AQUI, 'resumen.js'));

let fallos = 0;
const es = (que, dio, esperado) => {
  const ok = JSON.stringify(dio) === JSON.stringify(esperado);
  if(!ok){ fallos++; console.error(`  FALLA  ${que}\n         dio ${JSON.stringify(dio)} · esperaba ${JSON.stringify(esperado)}`); }
};

/* ── comprador A — el caso que destapó el fallo ──────────────────── */
const prabante = [
  {numero:'CR00035', tipo:'carta_reserva',    precio:163500, precio_reserva:'1000', moneda:'EUR', cobrado:0},
  {numero:'RP00122', tipo:'reserva_parcela',  precio:64565,  precio_reserva:'1000', moneda:'EUR', cobrado:0},
  {numero:'CC00078', tipo:'construccion',     precio:99000,  precio_reserva:null,   moneda:'EUR', cobrado:0},
  {numero:'HS00007', tipo:'hak_sewa_notario', precio:null,   precio_reserva:null,   moneda:'EUR', cobrado:0},
];
const rp = R.resumenPortal(prabante);
es('la villa se cuenta UNA vez: Bloqueo + Construcción, sin la Carta', rp.total, 163565);
es('…y no las 327.065 € que el portal le enseñaba', rp.total === 327065, false);
es('la Carta queda fuera del precio y se puede nombrar', rp.excluidos.map(x=>x.numero), ['CR00035']);
es('un contrato sin precio (Hak Sewa) no aporta ni estorba', rp.pendiente, 163565);

/* ── comprador C — el cobrado de la Carta SÍ descuenta ──── */
const nusa = [
  {numero:'CR00020', tipo:'carta_reserva',   precio:107200, precio_reserva:'1.000', moneda:'EUR', cobrado:1000},
  {numero:'RP00140', tipo:'reserva_parcela', precio:41200,  precio_reserva:'1.000', moneda:'EUR', cobrado:19596.41},
];
const rn = R.resumenPortal(nusa);
es('precio: solo el Bloqueo firmado', rn.total, 41200);
es('cobrado: lo pagado con la Carta cuenta igual que lo del Bloqueo', rn.cobrado, 20596.41);
es('pendiente = precio real − todo lo entregado', Math.round(rn.pendiente*100)/100, 20603.59);

/* ── comprador D — la variante hak_sewa también es preliminar
   (la copia de 12-ago se la dejaba fuera y por eso se centralizó la lista) ── */
const ruben = [
  {numero:'CH00001', tipo:'carta_reserva_hak_sewa', precio:18000, precio_reserva:'5000', moneda:'EUR', cobrado:0},
  {numero:'RP00121', tipo:'reserva_parcela',        precio:18000, precio_reserva:'5000', moneda:'EUR', cobrado:5000},
  {numero:'PA00006', tipo:'poa',                    precio:null,  precio_reserva:null,   moneda:'EUR', cobrado:0},
];
es('la Carta hak_sewa no duplica los 18.000 €', R.resumenPortal(ruben).total, 18000);
es('los 5.000 € entregados siguen contando como pagados', R.resumenPortal(ruben).cobrado, 5000);

/* ── comprador E — SOLO Carta: entonces manda la CUOTA ────────────
   Dejar el resumen en blanco aquí se leería como «no debes nada», y la cuota es
   exigible de verdad (hallazgo Legal ALTA, 12-ago-2026). Enseñar en cambio los
   109.000 € de la villa sería prometerle un precio que aún no ha firmado. */
const malogus = [
  {numero:'CR00054', tipo:'carta_reserva', precio:109000, precio_reserva:'2000', moneda:'EUR', cobrado:0},
];
const rm = R.resumenPortal(malogus);
es('solo Carta: el importe es su cuota de reserva, no el precio de la villa', rm.total, 2000);
es('…y se marca como tal para que el rótulo lo diga', rm.soloReserva, true);
es('sin contrato definitivo no hay nada que excluir', rm.excluidos.length, 0);

/* Una Carta sin cuota fijada: se cae al precio total como aproximación, que es
   lo que hace la ficha del agente. Peor sería no enseñar nada. */
es('solo Carta y sin cuota escrita: se aproxima con el precio total',
   R.resumenPortal([{numero:'CR0', tipo:'carta_reserva', precio:80000, precio_reserva:null, moneda:'EUR', cobrado:0}]).total,
   80000);

/* ── un importe desconocido es null, nunca 0 ─────────────────────────────── */
const sinPrecio = R.resumenPortal([{numero:'HS1', tipo:'hak_sewa_notario', precio:null, moneda:'EUR', cobrado:0}]);
es('sin ningún precio conocido: null, que se pinta «—», no un 0 que se cree', sinPrecio.total, null);
es('…y el pendiente tampoco se inventa', sinPrecio.pendiente, null);
es('sin contratos, nada que resumir', R.resumenPortal([]).total, null);

/* El precio escrito a mano en el formulario (precio_txt) se lee a la española,
   con lwParseImporte y no con un parseo propio: ya hubo cuatro y divergían. */
es('precio_txt «163.565» se lee como 163565',
   R.resumenPortal([{numero:'X', tipo:'reserva_parcela', precio:null, precio_txt:'163.565', moneda:'EUR', cobrado:0}]).total,
   163565);

/* ── la barra de avance de cada tarjeta ──────────────────────────────────
   La de una Carta suelta se mide contra su cuota: con el precio de la villa la
   tarjeta decia «109.000 EUR pendiente» justo debajo de un resumen que decia
   2.000 EUR. Las dos cifras eran del mismo dinero. */
es('Carta suelta: la barra se mide contra la cuota', R.baseAvance(malogus[0]), 2000);
es('Carta sin cuota escrita: contra su precio, que es lo unico que hay',
   R.baseAvance({tipo:'carta_reserva', precio:80000, precio_reserva:null}), 80000);
es('un contrato definitivo se mide contra su precio, como siempre',
   R.baseAvance(prabante[1]), 64565);

/* ── la tarjeta de cada contrato ─────────────────────────────────────────── */
es('la Carta de prabante está sustituida: su barra de pendiente mentiría',
   R.estaSustituido(prabante[0], prabante), true);
es('el Bloqueo NO está sustituido (no es preliminar)',
   R.estaSustituido(prabante[1], prabante), false);
es('una Carta suelta, sin contrato real todavía, NO está sustituida',
   R.estaSustituido(malogus[0], malogus), false);

/* ── la factura del próximo pago (7-oct-2026) ───────────────────────────── */
const hAnt = { es:'Anticipo', pct:'25', timing:'A la firma', monto:25000 };
const hFin = { es:'Entrega', pct:'25', timing:'Mes 12', monto:25000 };
const hCim = { es:'Cimentación', timing:'Mes 3', monto:30000 };
const fac = (numero, contrato, desc, extra) => Object.assign({ numero, tipo:'factura', contrato_numero:contrato, moneda:'USD', total:25000, lineas:[{ descripcion:desc, importe:25000 }] }, extra);
es('descripción del hito igual que la intranet',
   R.descHito(hAnt), 'Anticipo (25% del precio acordado) — A la firma');
es('sin porcentaje, sin paréntesis', R.descHito(hCim), 'Cimentación — Mes 3');
const C1 = { id:'id-c1', numero:'C-1' }, C2 = { id:'id-c2', numero:'C-2' };
const BP = { id:'id-bp', numero:'P-07-BP' }, CO = { id:'id-co', numero:'P-07-CO' };
const fs1 = [fac('F2', 'C-1', 'Anticipo (25% del precio acordado) — A la firma')];
es('dos hitos del mismo importe: la factura del anticipo NO es la de la entrega',
   R.facturaDelHito(fs1, C1, hFin, 'USD'), null);
es('la factura de su hito sí se encuentra',
   R.facturaDelHito(fs1, C1, hAnt, 'USD').numero, 'F2');
es('otro contrato no cuenta',
   R.facturaDelHito(fs1, C2, hAnt, 'USD'), null);
/* villa: el hito de la Construcción se cobra en una factura del Bloqueo, con prefijo y origen_contrato_id */
const fVinc = [fac('F3', 'P-07-BP', '[Construcción] Cimentación — Mes 3', { lineas:[{ descripcion:'[Construcción] Cimentación — Mes 3', importe:30000, origen_contrato_id:'id-co' }] })];
es('línea del contrato vinculado en factura del Bloqueo: es la del hito de la Construcción',
   R.facturaDelHito(fVinc, CO, hCim, 'USD').numero, 'F3');
es('esa misma línea NO es de un hito del Bloqueo escrito igual',
   R.facturaDelHito(fVinc, BP, hCim, 'USD'), null);
es('una línea con prefijo pero sin origen no se le atribuye a nadie por quitarle el prefijo',
   R.facturaDelHito([fac('F6', 'P-07-CO', '[Construcción] Cimentación — Mes 3')], CO, hCim, 'USD'), null);
es('otra moneda no cuenta',
   R.facturaDelHito([fac('F4', 'C-1', 'Anticipo (25% del precio acordado) — A la firma', { moneda:'EUR' })], C1, hAnt, 'USD'), null);
es('un recibí o una proforma no son la factura',
   R.facturaDelHito([fac('R1', 'C-1', 'Anticipo (25% del precio acordado) — A la firma', { tipo:'recibi' })], C1, hAnt, 'USD'), null);
es('sin fecha de vencimiento se encuentra igual (la fecha la decide quien pinta)',
   R.facturaDelHito([fac('F5', 'C-1', 'Cimentación — Mes 3', { fields:{} })], C1, hCim, 'USD').numero, 'F5');

/* ── Contratos por villa (7-oct-2026): agrupar no puede perder contratos ── */
{
  const cts = [
    {id:'a', numero:'P-07-CR', tipo:'carta_reserva',   proyecto_id:'pr1', proyecto:'Palm Field', parcela:'P-07'},
    {id:'b', numero:'P-07-BP', tipo:'reserva_parcela', proyecto_id:'pr1', proyecto:'Palm Field', parcela:'P-07'},
    {id:'c', numero:'P-07-CO', tipo:'construccion',    proyecto_id:'pr1', proyecto:'Palm Field', parcela:'P-07'},
    {id:'d', numero:'SH-03-BP', tipo:'reserva_parcela', proyecto_id:'pr2', proyecto:'Sumba Hills', parcela:'SH-03'},
    {id:'e', numero:'HS00009', tipo:'hak_sewa_notario', proyecto_id:'pr2', proyecto:'Sumba Hills', parcela:''},
    {id:'f', numero:'X-1', tipo:'construccion', proyecto_id:null, proyecto:'Sin catálogo', parcela:'X-1'},
  ];
  const vs = R.villasPortal(cts);
  es('agrupar por villa no pierde ningún contrato', vs.reduce((n,v)=>n+v.contratos.length,0), cts.length);
  es('una villa por proyecto + unidad, en el orden en que aparecen', vs.map(v=>v.key), ['pr1|P-07','pr2|SH-03','pr2|','n:Sin catálogo|X-1']);
  es('la Carta sustituida va al final de su villa', vs[0].contratos.map(x=>x.numero), ['P-07-BP','P-07-CO','P-07-CR']);
  es('la Carta enlaza a los definitivos de su villa', R.sustitutosDe(cts[0], cts).map(x=>x.numero), ['P-07-BP','P-07-CO']);
  es('un definitivo no enlaza a nadie', R.sustitutosDe(cts[1], cts), []);

  // La Carta sin unidad sigue sustituida (la regla mira todo el comprador), pero sin definitivos en su villa no
  // se inventa a quién enlazar, y su villa no tiene cifra propia.
  const sueltas = [
    {id:'g', numero:'CR00040', tipo:'carta_reserva',   proyecto_id:'pr3', proyecto:'Bonian', parcela:''},
    {id:'h', numero:'BV-01-BP', tipo:'reserva_parcela', proyecto_id:'pr3', proyecto:'Bonian', parcela:'BV-01'},
  ];
  const vs2 = R.villasPortal(sueltas);
  es('la Carta sin unidad no se pierde', vs2.map(v=>v.contratos.map(x=>x.numero)), [['CR00040'],['BV-01-BP']]);
  es('…su villa no tiene cifra propia (solo Cartas sustituidas)', vs2.map(v=>v.soloSustituidos), [true,false]);
  es('…y no enlaza a un contrato de otra unidad', R.sustitutosDe(sueltas[0], sueltas), []);

  // Solo Carta (estado B del artifact): no está sustituida y su villa sí tiene cifra (la cuota).
  const soloCarta = [{id:'i', numero:'BV-04-CR', tipo:'carta_reserva', proyecto_id:'pr3', proyecto:'Bonian', parcela:'BV-04'}];
  es('solo Carta: su villa tiene cifra', R.villasPortal(soloCarta)[0].soloSustituidos, false);
  es('vacío: sin villas', R.villasPortal([]), []);
}

/* ── estado de pago de cada documento (Facturas, 8-oct-2026) ──────────────────
   Los importes de las facturas son los de un comprador real con acceso al portal (8-oct, solo lectura):
   INV00164 saldada entera, INV00159 con 20.000 de 25.000 aplicados, INV00160 sin nada aplicado. */
{
  const HOY = new Date(2026, 9, 8, 12, 0, 0);
  const fac = (numero, total, aplicado, vence, extra) => Object.assign({ id:numero, numero, tipo:'factura', total, aplicado,
    contrato_numero:'CC1', contrato_id:'c1', moneda:'EUR', fields:{ fecha_vencimiento:vence } }, extra);
  es('aplicada entera: pagada', R.estadoFactura(fac('INV00164', 22250, 22250, '2026-09-01'), 0, HOY).estado, 'pagada');
  const parcial = R.estadoFactura(fac('INV00159', 25000, 20000, '2026-12-01'), 0, HOY);
  es('aplicada en parte y sin vencer: pago parcial', parcial.estado, 'parcial');
  es('…con lo que falta', parcial.falta, 5000);
  es('nada aplicado y sin vencer: pendiente', R.estadoFactura(fac('INV00160', 25250, 0, '2026-10-14'), 0, HOY).estado, 'pendiente');
  es('nada aplicado y vencida ayer: vencida', R.estadoFactura(fac('INV00160', 25250, 0, '2026-10-07'), 0, HOY).estado, 'vencida');
  es('vence HOY: todavía no está vencida', R.estadoFactura(fac('INV00160', 25250, 0, '2026-10-08'), 0, HOY).estado, 'pendiente');
  es('en parte y vencida: vencida, con lo que falta', R.estadoFactura(fac('INV00159', 25000, 20000, '2026-10-01'), 0, HOY),
     { estado:'vencida', vence:'2026-10-01', falta:5000 });
  es('el fin del día es el LOCAL, no medianoche UTC', R.finDelDia('2026-10-14'), new Date(2026, 9, 14, 23, 59, 59, 999).getTime());
  es('sin aplicado: no se sabe, no se pinta', R.estadoFactura(fac('X', 100, null, null), 0, HOY).estado, null);
  es('recibí', R.estadoFactura({ tipo:'recibi', total:5 }, 0, HOY).estado, 'recibo');
  es('proforma: sin estado de pago', R.estadoFactura({ tipo:'proforma', total:5, aplicado:null }, 0, HOY).estado, 'proforma');

  // Administración: el recibí del contrato NO se aplicó a la factura. El dinero entró: la factura sale pagada.
  const contrato = { id:'c1', numero:'CC1', cobrado:10000 };
  const sinAplicar = [fac('F1', 10000, 0, '2026-09-01', { fecha:'2026-08-01' })];
  const ex1 = R.saldoSinAplicar(sinAplicar, [contrato]);
  es('recibí sin aplicar: su dinero cubre la factura impagada', ex1, { F1:10000 });
  es('…y no sale «Vencida» sobre lo ya pagado', R.estadoFactura(sinAplicar[0], ex1.F1, HOY).estado, 'pagada');

  // Revisor: 10.000 cobrados y aplicados ENTEROS a F2. F1 no tiene nada: no puede salir pagada con dinero de otra.
  const dos = [fac('F1', 10000, 0, '2026-12-01', { fecha:'2026-08-01' }), fac('F2', 10000, 10000, '2026-12-01', { fecha:'2026-09-01' })];
  const ex2 = R.saldoSinAplicar(dos, [contrato]);
  es('dinero aplicado a otra factura: no queda resto que repartir', ex2, {});
  es('…F1 sigue pendiente', R.estadoFactura(dos[0], ex2.F1, HOY).estado, 'pendiente');
  es('…F2 pagada', R.estadoFactura(dos[1], ex2.F2, HOY).estado, 'pagada');

  // El resto se reparte de la más antigua a la más reciente y nunca pasa de lo que falta de cada una.
  const tres = [fac('B', 10000, 0, '2026-12-01', { fecha:'2026-09-01' }), fac('A', 10000, 4000, '2026-12-01', { fecha:'2026-08-01' })];
  const ex3 = R.saldoSinAplicar(tres, [{ id:'c1', numero:'CC1', cobrado:4000 + 9000 }]);
  es('reparto: primero completa la más antigua, luego la siguiente', ex3, { A:6000, B:3000 });
  es('…la siguiente queda en pago parcial, con lo que falta', R.estadoFactura(tres[0], ex3.B, HOY), { estado:'parcial', vence:'2026-12-01', falta:7000 });
  es('facturas de otro contrato no reciben nada', R.saldoSinAplicar([fac('Z', 100, 0, null, { contrato_id:'otro' })], [contrato]), {});
  // El caso del revisor: una factura del contrato con la copia del número distinta. Por id se resta igual.
  const copiaMala = [fac('P', 10000, 10000, null, { fecha:'2026-08-01', contrato_numero:'CC1-viejo' }), fac('Q', 10000, 0, null, { fecha:'2026-09-01' })];
  es('se empareja por id: una copia del número distinta no infla el resto', R.saldoSinAplicar(copiaMala, [contrato]), {});
  es('sin contrato_id no se reparte nada (no se adivina)', R.saldoSinAplicar([fac('S', 100, 0, null, { contrato_id:null })], [contrato]), {});
}

if(fallos){ console.error(`\n${fallos} fallo(s) en las cuentas del portal.`); process.exit(1); }
console.log('resumen.test.js — OK');
