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
     · comprador A                327.065 € enseñados · 163.565 € reales
     · comprador B                   222.000 € · 76.500 €
     · comprador C                   148.400 € · 41.200 €
     · comprador D                    36.000 € · 18.000 €

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

/* ── el resumen de UNA parte de los contratos (8-oct-2026, Inicio con filtro de propiedad) ──────────────────
   Qué es preliminar se decide sobre TODOS los contratos del comprador y luego se filtra, nunca al revés:
   resumenPortal() sobre los contratos de una sola carpeta trataría como «solo reserva» una Carta cuyo Bloqueo
   cayó en otra carpeta (LAW-499) y sumaría su cuota otra vez. Así la cifra de «Todas» es siempre la suma de las
   propiedades (revisión previa de Administración, 8-oct). Mismo motivo que `estaSustituido`: la regla mira
   todo el comprador.
   Y no se suman monedas distintas (104 compradores, 1 con contratos en dos monedas, medido el 8-oct): con más
   de una, `mixta` y las cifras por moneda en `porMoneda`; total/cobrado/pendiente quedan en null para que nadie
   pinte una suma de euros y rupias. Un contrato sin moneda cuenta como EUR, que es lo que `dinero()` le pinta. */
function resumenVista(contratos, enVista){
  const cts = (contratos || []).filter(Boolean);
  const dentro = typeof enVista === 'function' ? enVista : () => true;
  const r = resumenPortal(cts);
  const base = r.base.filter(dentro);
  const vistos = cts.filter(dentro);
  const mon = x => x.moneda || 'EUR';
  const grupos = {}, orden = [];
  const g = m => { if (!grupos[m]){ grupos[m] = { moneda: m, total: 0, hayPrecio: false, cobrado: 0 }; orden.push(m); } return grupos[m]; };
  base.forEach(x => {
    const p = r.soloReserva ? cuotaReserva(x) : precioContrato(x);
    const k = g(mon(x));
    if (p != null && !isNaN(p)){ k.total += p; k.hayPrecio = true; }
  });
  vistos.forEach(x => { g(mon(x)).cobrado += Number(x.cobrado) || 0; });
  const porMoneda = orden.map(m => {
    const k = grupos[m];
    return { moneda: m, total: k.hayPrecio ? k.total : null, cobrado: k.cobrado,
             pendiente: k.hayPrecio ? Math.max(0, k.total - k.cobrado) : null };
  });
  const mixta = porMoneda.length > 1;
  const una = porMoneda[0] || { moneda: r.moneda, total: null, cobrado: 0, pendiente: null };
  return {
    soloReserva: r.soloReserva,
    base: base,
    excluidos: r.excluidos.filter(dentro),
    mixta: mixta,
    porMoneda: porMoneda,
    total: mixta ? null : una.total,
    cobrado: mixta ? null : una.cobrado,
    pendiente: mixta ? null : una.pendiente,
    moneda: mixta ? null : una.moneda,
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

/* La factura de un hito (7-oct-2026, revisor: emparejar por importe enseñaba la factura YA PAGADA del hito
   anterior cuando dos hitos valen lo mismo). Las facturas no guardan su hito, pero cada línea lleva la
   descripción que la intranet le puso al traerlo: `descHito()` de intranet/facturas — texto, «(N% del precio
   acordado)» si tiene porcentaje y « — plazo» —, con el prefijo «[Etiqueta] » si vino de un contrato
   vinculado. Es la MISMA regla con la que la intranet decide que un hito ya está facturado
   (HITOS_OTRA_FACTURA), así que las dos pantallas no pueden discrepar. Sin línea idéntica no hay factura:
   el portal enseña el plazo del contrato y no una fecha adivinada. */
function descHito(h){
  if (!h) return '';
  const pct = _imp(h.pct);
  return [h.es || h.en || '', pct ? '(' + pct + '% del precio acordado)' : ''].filter(Boolean).join(' ')
       + (h.timing ? ' — ' + h.timing : '');
}
/* De qué contrato es una línea: la que trajo un hito del contrato VINCULADO lleva `origen_contrato_id` (y la
   descripción con «[Etiqueta] » delante) aunque la factura sea del otro — en una villa, los hitos de la
   Construcción se cobran en facturas del Bloqueo (intranet/facturas, traerVinculado). La que no lo lleva es del
   contrato de su factura. Solo así un hito del Bloqueo y otro de la Construcción escritos igual no se confunden. */
function facturaDelHito(facturas, contrato, hito, moneda){
  const d = descHito(hito).trim();
  if (!d || !contrato || !(contrato.id || contrato.numero)) return null;
  const sinPrefijo = s => String(s || '').trim().replace(/^\[[^\]]*\]\s*/, '');
  const esDelHito = (f, l) => {
    if (!l) return false;
    if (l.origen_contrato_id) return l.origen_contrato_id === contrato.id && sinPrefijo(l.descripcion) === d;
    return f.contrato_numero === contrato.numero && String(l.descripcion || '').trim() === d;
  };
  return (facturas || []).filter(f =>
    f && f.tipo === 'factura' &&
    (!moneda || !f.moneda || f.moneda === moneda) &&
    (f.lineas || []).some(l => esDelHito(f, l))
  )[0] || null;
}

/* ── Contratos agrupados por villa (7-oct-2026, artifact «Lawang · Contratos (propuesta)») ──
   Una villa = proyecto + unidad. Es solo cómo se enseñan: ningún contrato se pierde por el camino (lección de la
   v3 de Proyectos, 26-ago: agrupar por una columna borra lo que no la tiene). El que no trae unidad va a la villa
   «sin unidad» de su proyecto; el que no trae proyecto, a la de su nombre — mismo criterio que `carpetasProyecto`.
   Dentro de cada villa, la Carta ya sustituida va al final: es un documento suyo, pero no le pide nada. La regla de
   «sustituida» es la de siempre (`estaSustituido` sobre TODOS los contratos del comprador), no una por villa: si
   una Carta no trae la misma unidad que su Bloqueo, mirarlo por villa la haría reclamar otra vez su cuota. Que una
   Carta de OTRA villa salga como recogida es el coste conocido de esa regla: decisión del owner pendiente, LAW-499. */
/* Qué es «la misma villa»: una sola definición para agrupar y para enlazar una Carta con sus definitivos. */
function claveVilla(x){
  return (x.proyecto_id || ('n:' + (x.proyecto || ''))) + '|' + (x.parcela || '');
}
function villasPortal(contratos){
  const cts = (contratos || []).filter(Boolean);
  const mapa = {}, orden = [];
  cts.forEach(x => {
    const key = claveVilla(x);
    if (!mapa[key]){ mapa[key] = { key: key, proyecto_id: x.proyecto_id || null, proyecto: x.proyecto || '', parcela: x.parcela || '', contratos: [] }; orden.push(key); }
    mapa[key].contratos.push(x);
  });
  return orden.map(k => {
    const v = mapa[k];
    const vivos = v.contratos.filter(x => !estaSustituido(x, cts));
    const sust = v.contratos.filter(x => estaSustituido(x, cts));
    v.contratos = vivos.concat(sust);
    // Una villa que solo tiene Cartas ya sustituidas no tiene cifra propia: su dinero lo cuentan los definitivos.
    v.soloSustituidos = vivos.length === 0;
    return v;
  });
}

/* Los contratos que recogen una Carta sustituida, para enlazarlos desde ella: los definitivos de su misma villa.
   Si la Carta no comparte unidad con ninguno, no se enlaza nada (la frase ya lo explica) — nunca se adivina. */
function sustitutosDe(x, contratos){
  const prelim = t => (typeof lwEsPreliminar === 'function') ? lwEsPreliminar(t) : false;
  if (!x || !prelim(x.tipo)) return [];
  const k = claveVilla(x);
  return (contratos || []).filter(y => y && y !== x && !prelim(y.tipo) && claveVilla(y) === k);
}

/* ── El estado de pago de cada documento de la pantalla Facturas (8-oct-2026) ─────────────────────────────────
   Dos fuentes, y ninguna basta sola (revisión previa de Administración y revisor de código, 8-oct):
   · `aplicado` (portal_situacion → factura_aplicado()): lo que los recibís APLICADOS a esa factura han saldado.
     Es la misma suma con la que la intranet calcula lo pendiente de una factura (facturas_pendiente_equipo).
   · el dinero del contrato que NO está aplicado a ninguna factura. `contrato_cobrado()` es, por construcción,
     lo aplicado a las facturas del contrato MÁS el resto sin aplicar de sus recibís; así que ese resto es
     `cobrado − Σ aplicado` de sus facturas, sin inventar nada.
   Solo con `aplicado`, un recibí sin aplicar dejaba «Vencida» una factura ya pagada (Administración). Con la
   cascada de hitos entera, una factura salía «Pagada» con dinero que estaba aplicado a OTRA (revisor). Por eso
   lo que se reparte es solo el resto sin aplicar, sobre las facturas impagadas del contrato, de la más antigua a
   la más reciente — el mismo orden en que se cobra un plan de pagos. Orden de estados: pagada → vencida →
   parcial → pendiente. */
function saldoSinAplicar(facturas, contratos){
  const extra = {};
  (contratos || []).forEach(x => {
    // Por id, la misma clave con la que el servidor calcula `cobrado` (contrato_cobrado). La copia `contrato_numero`
    // de la factura no vale: una distinta o vacía dejaría su `aplicado` sin restar e inflaría el resto (revisor, 8-oct).
    if (!x || !x.id) return;
    const suyas = (facturas || []).filter(f => f && f.tipo === 'factura' && f.contrato_id && f.contrato_id === x.id && f.aplicado != null);
    const aplicado = suyas.reduce((s, f) => s + (Number(f.aplicado) || 0), 0);
    let resto = Math.max(0, (Number(x.cobrado) || 0) - aplicado);
    suyas.slice().sort((a, b) => String(a.fecha || '').localeCompare(String(b.fecha || '')) || String(a.numero || '').localeCompare(String(b.numero || '')))
      .forEach(f => {
        if (resto <= 0.005) return;
        const falta = Math.max(0, Number(f.total) - (Number(f.aplicado) || 0));
        if (!(falta > 0.005)) return;
        const usa = Math.min(falta, resto);
        extra[f.id] = (extra[f.id] || 0) + usa;
        resto -= usa;
      });
  });
  return extra;
}

/* El último instante de un día «AAAA-MM-DD» en la hora LOCAL de quien mira. `new Date('2026-10-14')` es medianoche
   UTC: al oeste de Greenwich cae el día 13, y la factura salía vencida un día antes (revisor, 8-oct). */
function finDelDia(s){
  if (!s) return NaN;
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(s).slice(0, 10));
  const d = m ? new Date(+m[1], +m[2] - 1, +m[3]) : new Date(s);
  return isNaN(d) ? NaN : d.setHours(23, 59, 59, 999);
}

/* `extra`: lo que le toca de `saldoSinAplicar`. `hoy` es un Date (o ms). Sin `aplicado` no se sabe nada: estado
   null y la pantalla no pinta etiqueta — «no sabemos» no es «pendiente» (la regla de importeVencimiento). */
function estadoFactura(f, extra, hoy){
  if (!f) return { estado: null };
  if (f.tipo === 'recibi') return { estado: 'recibo' };
  if (f.tipo === 'proforma') return { estado: 'proforma' };
  if (f.aplicado == null || f.aplicado === '') return { estado: null };
  const total = Number(f.total);
  if (isNaN(total)) return { estado: null };
  const cubierto = (Number(f.aplicado) || 0) + (Number(extra) || 0);
  const vence = (f.fields && f.fields.fecha_vencimiento) || null;
  if (cubierto >= total - 0.005) return { estado: 'pagada', vence: vence };
  const falta = cubierto > 0.005 ? Math.max(0, total - cubierto) : null;
  const fin = finDelDia(vence);
  if (!isNaN(fin) && fin < Number(hoy)) return { estado: 'vencida', vence: vence, falta: falta };
  return { estado: cubierto > 0.005 ? 'parcial' : 'pendiente', vence: vence, falta: falta };
}

/* ── Cuál es «el próximo pago» cuando hay varios contratos (8-oct-2026, owner: «la vencida primero») ──────────
   Antes se enseñaba el primer hito sin pagar del PRIMER contrato de la lista, aunque otro contrato tuviera ya una
   factura vencida: el bloque más visible de Inicio y de Facturas mandaba pagar algo que vence en 6 días mientras otra
   llevaba días vencida. Cada candidato es el próximo pago de UN contrato (proximoDe, sin cambiar su importe) con el
   vencimiento de su factura si la tiene. Orden: (1) vencidos, el más antiguo primero; (2) con vencimiento, el más
   cercano primero; (3) sin factura todavía, en el orden de los contratos, como hasta ahora. */
function eligeProximo(cands, hoy){
  const ahora = Number(hoy);
  const clase = c => { const fin = finDelDia(c.vence); return isNaN(fin) ? 2 : (fin < ahora ? 0 : 1); };
  return (cands || []).filter(c => c && c.proximo)
    .map((c, i) => ({ c: c, i: i, k: clase(c), fin: finDelDia(c.vence) }))
    .sort((a, b) => (a.k - b.k) || (a.k < 2 ? a.fin - b.fin : 0) || (a.i - b.i))
    .map(x => x.c)[0] || null;
}

if (typeof module !== 'undefined' && module.exports)
  module.exports = { resumenPortal, resumenVista, estaSustituido, cuotaReserva, precioContrato, baseAvance, descHito, facturaDelHito, villasPortal, sustitutosDe,
                     saldoSinAplicar, finDelDia, estadoFactura, eligeProximo };
