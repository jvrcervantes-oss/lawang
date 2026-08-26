/* Aritmética y formato de dinero de las facturas de Lawang.
   Fuera del HTML para poder pasarle un test de verdad (totales.test.js).
   Se carga con <script src> en index.html y con require() en node. */

/* ═══════════════════════════════════════════════════════════════════════════
   ESTE FICHERO YA NO TIENE COPIA DE NADA — 26-ago-2026
   ═══════════════════════════════════════════════════════════════════════════
   Tenía tres: la tabla de decimales por moneda, el parser y el formateador,
   cada uno con su «respaldo por si `dinero.js` no está cargado». Los respaldos
   se escribieron con una buena intención y eran, medidos, la causa de que:

   1. **La tabla de decimales viviera dos veces.** `DECIMALES` aquí y
      `LW_DECIMALES` en `dinero.js`, con los mismos cuatro pares escritos a
      mano. Añadir una moneda a una y no a la otra da decimales distintos para
      el mismo importe según qué función lo toque, y no falla nada. Es
      literalmente el patrón que esta suite tiene anotado como fuente de fallos:
      «una lista escrita a mano en dos sitios ES el bug».

   2. **El test probara la copia y no el código.** `totales.test.js` hace
      `require('./totales.js')` y en node no existen las globales del navegador,
      así que TODAS sus aserciones caían al respaldo. Verde sobre código que
      producción no ejecuta nunca — el peor color de todos, porque el que sí se
      ejecuta no lo miraba nadie.

   Ahora `dinero.js` se PIDE: en node por `require`, y en el navegador y en la
   edge ya está cargado delante (el `<head>` de cada página; en la edge lo
   antepone `tools/empaqueta_edge.py`, que por eso lo pone primero). Una sola
   implementación en los tres sitios, y el test prueba la de verdad.
   Si falta, esto revienta con un error legible en vez de devolver cifras
   ligeramente distintas sin decir nada.

   ⚠️ SE RESUELVE AL USARLO, NO AL CARGARLO — y esto no es un detalle de estilo,
   costó una caída (26-ago-2026, misma tarde). La primera versión decidía en el
   momento de PARSEAR el fichero:

       const _LW = (typeof lwFormatoImporte === 'function') ? {...} : require(...)

   y en el navegador `require` no existe. Facturas, Compradores y Proyectos
   cargan `totales.js` ANTES que `dinero.js` —solo Operaciones tenía el orden
   bien, con su comentario del 17-ago diciéndolo—, así que el `typeof` daba
   `false`, se intentaba el `require`, y el `const` moría a medio inicializar.
   A partir de ahí CUALQUIER acceso a `_LW` daba «Cannot access before
   initialization»: `fmtMoneda` y `parseImporte` lanzaban, y las tres pantallas
   se quedaban en blanco. Los tests no lo vieron porque en node el `require` sí
   existe y el camino que se probaba era el otro.

   Resolviéndolo en la PRIMERA LLAMADA, el orden de las etiquetas deja de
   importar: para cuando alguien pide un importe, el `<head>` entero ya corrió.
   El orden se arregla igualmente y lo vigila `contracts/orden_dinero.test.js`,
   pero el código ya no depende de que nadie se equivoque. */
let _lwCache = null;
function _LW(){
  if (_lwCache) return _lwCache;
  if (typeof lwFormatoImporte === 'function')
    _lwCache = { lwParseImporte, lwFormatoImporte, LW_DECIMALES };
  else if (typeof require === 'function')
    _lwCache = require('../contracts/assets/dinero.js');
  else
    throw new Error('totales.js necesita contracts/assets/dinero.js cargado antes que él');
  return _lwCache;
}

// Decimales por moneda: la rupia no usa céntimos. Fuente única: dinero.js.
// Función y no constante, por lo mismo: al cargar aún puede no haber nada.
const DECIMALES = new Proxy({}, {
  get: (_, k) => _LW().LW_DECIMALES[k],
  has: (_, k) => k in _LW().LW_DECIMALES,
});

/* Importe tecleado a número. El agente escribe indistintamente "1.500,50",
   "1,500.50" o "1500.5": manda el ÚLTIMO separador como decimal, y solo si
   deja 1-2 dígitos detrás (si no, es separador de miles: "1.500" = 1500). */
function parseImporte(v){
  /* `?? 0` conserva el contrato de ESTA función, que no es el de `lwParseImporte`:
     una línea de factura vacía suma 0, mientras que un contrato sin precio es
     `null` y no un contrato de 0 €. Esa diferencia es la única razón por la que
     esta envoltura sigue existiendo. */
  return _LW().lwParseImporte(v) ?? 0;
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

/* Alias de `lwFormatoImporte`. Se conserva el nombre porque lo llaman
   `documento.js`, `operaciones-cuentas.js` y las pantallas de facturas; lo que
   ya no conserva es una segunda implementación detrás. */
function fmtMoneda(n, moneda){ return _LW().lwFormatoImporte(n, moneda); }

if(typeof module !== 'undefined') module.exports = { parseImporte, redondear, calcTotales, fmtMoneda, DECIMALES };
