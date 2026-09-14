/* Las cuentas del área de clientes (/portal/) — 14-sep-2026.

   POR QUÉ EXISTE ESTE FICHERO, y no unas líneas más dentro de index.html:
   el portal sumaba TODOS los contratos del comprador, Carta de Reserva
   incluida, y enseñaba el doble de lo que el cliente debe. Es el mismo fallo
   que la suite ya pagó dos veces por aprender —12-ago en compradores/ (una
   Carta + Construcción de 76.500 € daba 153.000 € por la misma villa) y 14-ago
   en operaciones/ (328.000 € por una villa de 164.000)— y que quedó escrito en
   `contracts/assets/vocabulario.js` (`lwEsPreliminar`) y probado en
   `intranet/vencimientos/logica.test.js`. El portal nunca lo aplicó, y es la
   única pantalla que ve el CLIENTE: ahí una cifra inflada no es un número feo,
   es una reclamación.

   Medido sobre producción el 14-sep-2026, compradores con acceso activo:
     · dprabante@gmail.com        327.065 € enseñados · 163.565 € reales
     · bemyguest.holdings@gmail.com  222.000 € · 76.500 €
     · ptnusalifeventures@gmail.com  148.400 € · 41.200 €
     · ruben.carrasco@nettaro.com     36.000 € · 18.000 €

   LAS REGLAS NO SE INVENTAN AQUÍ. Son, literalmente, las de
   `intranet/compradores/index.html` (la ficha que abre el agente cuando el
   cliente llama por teléfono). Si las dos pantallas contaran distinto tendríamos
   el problema de partida multiplicado por dos:
   · el PRECIO no cuenta los preliminares (`lwEsPreliminar`): una Carta de
     Reserva declara el mismo importe que luego reparten el Bloqueo de Parcela y
     la Construcción que la sustituyen;
   · si NO hay ningún contrato definitivo todavía, se enseña la CUOTA de reserva
     (`precio_reserva`), no el precio de la villa: es un pago exigible de verdad
     —5 días hábiles tras la firma, con retención si el reservante desiste
     (carta_reserva_hak_sewa, cl. 4.1/7.2)— y dejarlo en blanco se leería como
     «no debes nada», que es lo contrario;
   · el COBRADO cuenta TODO recibí, venga de la reserva o del contrato real: es
     dinero que entró, y se le descuenta al pendiente.

   Aquí no hay DOM ni red —entran filas y sale un modelo— para que
   `resumen.test.js` pueda probarlo en node con los datos reales de arriba. */

/* Importes: una sola forma de leerlos en toda la suite (`assets/dinero.js`).
   `precio_reserva` viene del formulario del contrato y llega tal cual se
   escribió: unos ponen «5000» y otros «1.000». */
function _imp(v){
  if (v == null || v === '') return null;
  if (typeof v === 'number') return isNaN(v) ? null : v;
  return (typeof lwParseImporte === 'function') ? lwParseImporte(v) : Number(v);
}

/* El precio de un contrato: la columna si la hay, y si no el texto del
   formulario — el mismo orden que ya usaba el portal. */
function precioContrato(x){
  const n = _imp(x.precio);
  return n != null ? n : _imp(x.precio_txt);
}

/* Lo que vale un preliminar: su cuota si la fijó, y si no el precio total como
   aproximación. Mismo criterio que `cuotaReserva` en compradores/. */
function cuotaReserva(x){
  const c = _imp(x.precio_reserva);
  return c != null ? c : precioContrato(x);
}

/* ── el resumen que ve el cliente en su Inicio ─────────────────────────────
   Devuelve, además de las cifras, QUÉ contratos quedaron fuera del precio: el
   rótulo tiene que poder nombrarlos. Un número que no cuadra con su propio
   rótulo es un número en el que se deja de confiar (la lección de operaciones/,
   14-ago), y en el portal quien desconfía es el cliente.

   `base` es la lista de contratos sobre la que se calcula el precio — y también
   la única de la que puede salir el «Próximo pago»: el calendario de una Carta
   sustituida son los mismos hitos que ya trae su Bloqueo, y enseñarlo reclamaba
   dos veces el mismo pago. */
function resumenPortal(contratos){
  const cts = (contratos || []).filter(Boolean);
  const prelim = t => (typeof lwEsPreliminar === 'function') ? lwEsPreliminar(t) : false;
  const sumables = cts.filter(x => !prelim(x.tipo));
  const soloReserva = cts.length > 0 && sumables.length === 0;
  const base = soloReserva ? cts : sumables;
  const excluidos = soloReserva ? [] : cts.filter(x => prelim(x.tipo));

  let total = 0, hayPrecio = false;
  base.forEach(x => {
    const p = soloReserva ? cuotaReserva(x) : precioContrato(x);
    if (p != null && !isNaN(p)){ total += p; hayPrecio = true; }
  });
  // El cobrado cuenta TODOS los contratos, preliminares incluidos: lo que el
  // cliente pagó con la Carta es dinero entregado a cuenta de esa misma
  // operación, y no contarlo le abultaría el pendiente.
  const cobrado = cts.reduce((a,x) => a + (Number(x.cobrado) || 0), 0);

  return {
    soloReserva: soloReserva,
    base: base,
    excluidos: excluidos,
    // null, nunca 0: «no sabemos su precio» y «vale 0 €» no son lo mismo, y un
    // 0 falso se cree (la regla de lwParseImporte y de importeVencimiento).
    total: hayPrecio ? total : null,
    cobrado: cobrado,
    pendiente: hayPrecio ? Math.max(0, total - cobrado) : null,
    moneda: (cts[0] || {}).moneda || 'EUR',
  };
}

/* ── contra qué se mide el avance de UN contrato ───────────────────────────
   El de una Carta todavía sin contrato definitivo es su CUOTA, no el precio de
   la villa: lo exigible hoy son los 2.000 € de la reserva, no los 109.000 € que
   el documento bloquea. Medirlo contra el precio dejaba «109.000 € pendiente»
   en la tarjeta debajo de un resumen que decía 2.000 € — dos cifras del mismo
   dinero que no cuadran, y la de la tarjeta es la que asusta. Si la Carta no
   fija cuota, `cuotaReserva` cae al precio y nada cambia. */
function baseAvance(x){
  const prelim = t => (typeof lwEsPreliminar === 'function') ? lwEsPreliminar(t) : false;
  if (!prelim(x.tipo)) return precioContrato(x);
  const c = cuotaReserva(x);
  return c != null ? c : precioContrato(x);
}

/* ── ¿este contrato ya está sustituido por los definitivos? ────────────────
   Se usa en la tarjeta de cada contrato: la Carta sigue viéndose entera (es un
   documento suyo, firmado, con su PDF), pero su barra de «pendiente» mentiría —
   ese importe no es un cargo aparte, lo reparten los contratos reales. */
function estaSustituido(x, contratos){
  const prelim = t => (typeof lwEsPreliminar === 'function') ? lwEsPreliminar(t) : false;
  if (!prelim(x.tipo)) return false;
  return (contratos || []).some(y => y && !prelim(y.tipo));
}

if (typeof module !== 'undefined' && module.exports)
  module.exports = { resumenPortal, estaSustituido, cuotaReserva, precioContrato, baseAvance };
