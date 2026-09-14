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

/* ── dprabante@gmail.com — el caso que destapó el fallo ──────────────────── */
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

/* ── ptnusalifeventures@gmail.com — el cobrado de la Carta SÍ descuenta ──── */
const nusa = [
  {numero:'CR00020', tipo:'carta_reserva',   precio:107200, precio_reserva:'1.000', moneda:'EUR', cobrado:1000},
  {numero:'RP00140', tipo:'reserva_parcela', precio:41200,  precio_reserva:'1.000', moneda:'EUR', cobrado:19596.41},
];
const rn = R.resumenPortal(nusa);
es('precio: solo el Bloqueo firmado', rn.total, 41200);
es('cobrado: lo pagado con la Carta cuenta igual que lo del Bloqueo', rn.cobrado, 20596.41);
es('pendiente = precio real − todo lo entregado', Math.round(rn.pendiente*100)/100, 20603.59);

/* ── ruben.carrasco@nettaro.com — la variante hak_sewa también es preliminar
   (la copia de 12-ago se la dejaba fuera y por eso se centralizó la lista) ── */
const ruben = [
  {numero:'CH00001', tipo:'carta_reserva_hak_sewa', precio:18000, precio_reserva:'5000', moneda:'EUR', cobrado:0},
  {numero:'RP00121', tipo:'reserva_parcela',        precio:18000, precio_reserva:'5000', moneda:'EUR', cobrado:5000},
  {numero:'PA00006', tipo:'poa',                    precio:null,  precio_reserva:null,   moneda:'EUR', cobrado:0},
];
es('la Carta hak_sewa no duplica los 18.000 €', R.resumenPortal(ruben).total, 18000);
es('los 5.000 € entregados siguen contando como pagados', R.resumenPortal(ruben).cobrado, 5000);

/* ── malogus84@gmail.com — SOLO Carta: entonces manda la CUOTA ────────────
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

if(fallos){ console.error(`\n${fallos} fallo(s) en las cuentas del portal.`); process.exit(1); }
console.log('resumen.test.js — OK');
