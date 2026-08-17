/* Aritmética y formato de dinero de las facturas de Lawang.
   Fuera del HTML para poder pasarle un test de verdad (totales.test.js).
   Se carga con <script src> en index.html y con require() en node. */

// Decimales por moneda: la rupia no usa céntimos.
const DECIMALES = { EUR:2, USD:2, AUD:2, IDR:0 };

/* Importe tecleado a número. El agente escribe indistintamente "1.500,50",
   "1,500.50" o "1500.5": manda el ÚLTIMO separador como decimal, y solo si
   deja 1-2 dígitos detrás (si no, es separador de miles: "1.500" = 1500). */
function parseImporte(v){
  /* La version buena vive en contracts/assets/dinero.js desde el 17-ago-2026.
     Aqui se DELEGA, y `?? 0` conserva el contrato de esta funcion: una linea de
     factura vacia suma 0, mientras que un contrato sin precio es `null` y no un
     contrato de 0 €.

     ⚠️ EL RESPALDO DE ABAJO NO ES CODIGO MUERTO, pero desde el 17-ago-2026 lo es
     por OTRO motivo — y el anterior ya no vale, asi que se reescribe entero en vez
     de dejarlo dando una razon caducada:
       · YA NO es por `firma-submit`. Esa funcion dejo de descargarse este fichero
         por HTTP (auditoria, hallazgo 01): ahora lleva los cinco dentro, generados
         por `tools/empaqueta_edge.py`, y dinero.js va PRIMERO en ese paquete.
       · SIGUE vivo mientras haya alguna pagina que cargue este fichero sin cargar
         `contracts/assets/dinero.js` delante. Hoy no queda ninguna —se le añadio a
         operaciones/, que era la ultima— pero el respaldo se queda: cuesta ocho
         lineas y evita que la proxima pantalla que se olvide de dinero.js empiece a
         devolver 0 en cada importe sin dar ningun error.
       · ⚠️ Mientras `firma-submit` no se REDESPLIEGUE, la version que corre en
         produccion sigue siendo la que se lo descarga con la lista vieja de cuatro
         rutas. Ese es un estado que se comprueba leyendo la funcion desplegada, no
         el repo. */
  if(typeof lwParseImporte === 'function') return lwParseImporte(v) ?? 0;
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

/* Se DELEGA en contracts/assets/dinero.js desde el 17-ago-2026, igual que
   `parseImporte`: esta era la única de las cuatro formas de imprimir un importe
   que conocía la moneda, así que subió a la capa común y las otras tres pasaron a
   llamarla. El respaldo de abajo existe por el mismo motivo que el de
   `parseImporte` — ver la nota larga de ahí arriba, que es la que explica por qué
   no se quita. */
function fmtMoneda(n, moneda){
  if(typeof lwFormatoImporte === 'function') return lwFormatoImporte(n, moneda);
  const d = DECIMALES[moneda] != null ? DECIMALES[moneda] : 2;
  return new Intl.NumberFormat('de-DE', { minimumFractionDigits:d, maximumFractionDigits:d })
    .format(n || 0) + ' ' + (moneda || '');
}

if(typeof module !== 'undefined') module.exports = { parseImporte, redondear, calcTotales, fmtMoneda, DECIMALES };
