/* Aritmética y formato de dinero de las facturas de Lawang.
   Fuera del HTML para poder pasarle un test de verdad (totales.test.js).
   Se carga con <script src> en index.html y con require() en node. */

// Decimales por moneda: la rupia no usa céntimos.
const DECIMALES = { EUR:2, USD:2, AUD:2, IDR:0 };

/* Importe tecleado a número. El agente escribe indistintamente "1.500,50",
   "1,500.50" o "1500.5": manda el ÚLTIMO separador como decimal, y solo si
   deja 1-2 dígitos detrás (si no, es separador de miles: "1.500" = 1500). */
function parseImporte(v){
  const s = String(v == null ? '' : v).replace(/[^\d.,-]/g, '');
  if(!s) return 0;
  const neg = s.startsWith('-');
  const cuerpo = s.replace(/-/g, '');
  const corte = Math.max(cuerpo.lastIndexOf(','), cuerpo.lastIndexOf('.'));
  let n;
  if(corte >= 0 && cuerpo.length - corte - 1 <= 2 && cuerpo.length - corte - 1 > 0){
    n = Number(cuerpo.slice(0, corte).replace(/[.,]/g, '') + '.' + cuerpo.slice(corte + 1));
  }else{
    n = Number(cuerpo.replace(/[.,]/g, ''));
  }
  if(!isFinite(n)) return 0;
  return neg ? -n : n;
}

// Redondeo a los decimales de la moneda, en enteros para no arrastrar
// el error binario de coma flotante (0.1+0.2 y compañía).
function redondear(n, moneda){
  const d = DECIMALES[moneda] != null ? DECIMALES[moneda] : 2;
  const f = Math.pow(10, d);
  return Math.round((n + Number.EPSILON) * f) / f;
}

/* Totales de la factura. `lineas` = [{descripcion, importe}], `impuesto` =
   {etiqueta, pct} y sin pct (o 0) no hay fila de impuesto: el tipo que aplica
   en Indonesia lo confirma el cliente, aquí no se inventa ninguno. */
function calcTotales(lineas, moneda, impuesto){
  const subtotal = redondear((lineas || []).reduce((a, l) => a + parseImporte(l.importe), 0), moneda);
  const pct = impuesto ? parseImporte(impuesto.pct) : 0;
  const imp = pct ? redondear(subtotal * pct / 100, moneda) : 0;
  return { subtotal, pct, impuesto: imp, total: redondear(subtotal + imp, moneda) };
}

function fmtMoneda(n, moneda){
  const d = DECIMALES[moneda] != null ? DECIMALES[moneda] : 2;
  return new Intl.NumberFormat('de-DE', { minimumFractionDigits:d, maximumFractionDigits:d })
    .format(n || 0) + ' ' + (moneda || '');
}

if(typeof module !== 'undefined') module.exports = { parseImporte, redondear, calcTotales, fmtMoneda, DECIMALES };
