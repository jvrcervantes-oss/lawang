/* Leer un importe de dinero — UNA sola forma para toda la suite. 17-ago-2026
   ============================================================================
   POR QUE EXISTE. Habia DOS implementaciones de esto, una en `contracts/app.html`
   y otra en `facturas/totales.js`, y no coincidian. Medido antes de unificarlas,
   discrepaban en seis casos y ninguna era mejor que la otra: cada una acertaba
   justo donde la otra fallaba.

     entrada      Contratos   Facturas   quien acertaba
     -5.000       +5000       -5000      Facturas — Contratos se comia el signo
     ""           null        0          las dos, en su contexto (ver abajo)
     1.2345       1.2345      12345      Contratos — un tipo de cambio lleva
                                         cuatro decimales, no son miles
     12.34.56     123456      1234.56    Contratos — dos separadores son miles
     1,2,3        123         12.3       Contratos

   Un mismo importe leido con distinto SIGNO segun que herramienta lo tocara, en
   un ERP que mueve mas de 100 M€. Es la misma familia de fallo que costo una
   semana de cobros dobles en B2K: el mismo dato en dos sitios que se separan.

   ESTA FUNCION ES LA SUMA DE LAS DOS, no una tercera version: se conserva la
   regla de separadores de Contratos y el tratamiento del signo de Facturas.

   QUE DEVUELVE CUANDO NO HAY NUMERO. `null`, y no 0. La diferencia importa: un
   contrato SIN precio no es un contrato de 0 €, y guardarlo como 0 lo mete en
   las sumas de Operaciones y en el calculo de lo cobrado. Donde 0 sea la
   respuesta correcta —una linea de factura vacia no suma— el que llama escribe
   `?? 0`, que es explicito y se lee. */

/* Reglas del separador, con el caso que justifica cada una:
   · el ULTIMO separador es el decimal … "1.500,50" → 1500.5
   · salvo que aparezca mas de una vez … "1.000.000" y "12.34.56" son miles
   · salvo que le sigan EXACTAMENTE 3 cifras … "79.000" y "1,500" son miles
   ponytail asumido: "79.500" queriendo decir 79 con 5 decimas se lee 79500. En
   estos contratos no se escribe asi, y romper "79.500" = 79.500 € seria peor. */
function lwParseImporte(v){
  const bruto = String(v == null ? '' : v);
  // El signo se mira ANTES de limpiar: `[^\d.,]` se lo llevaba por delante y
  // por eso Contratos convertia -5.000 en +5000.
  const negativo = /-/.test(bruto.trim().charAt(0)) || /^\s*-/.test(bruto);
  const s = bruto.replace(/[^\d.,]/g, '');
  if(!/\d/.test(s)) return null;
  const d = s.lastIndexOf('.'), c = s.lastIndexOf(',');
  let sep = d > c ? '.' : (c > d ? ',' : '');
  const resto = s.slice(s.lastIndexOf(sep) + 1);
  if(sep && (s.split(sep).length > 2 || /^\d{3}$/.test(resto))) sep = '';
  const n = parseFloat(sep ? s.replace(/[.,]/g, m => m === sep ? '.' : '')
                           : s.replace(/[.,]/g, ''));
  if(!isFinite(n)) return null;
  return negativo ? -n : n;
}

/* ============================================================================
   ESCRIBIR UN IMPORTE — la otra mitad, 17-ago-2026 (auditoría)
   ============================================================================
   Este fichero nació esta misma semana para que hubiera UNA forma de LEER un
   importe, después de medir seis discrepancias entre Contratos y Facturas. La
   mitad simétrica —imprimirlo— se quedó fuera, y para cuando se auditó ya había
   cuatro implementaciones vivas que tampoco coincidían. Medido ejecutándolas:

     valor          Facturas · Operaciones   Compradores · Panel
     1234.5         1.234,50 €               1234,5 €
     164000         164.000,00 €             164.000 €
     1234567.891    1.234.567,89 €           1.234.567,891 €

   El mismo importe con tres decimales en una pantalla y dos en otra. Y peor que
   la estética: `toLocaleString('es')` no recibe la moneda, así que un importe en
   rupias sale con decimales que en rupias NO EXISTEN — la rupia no tiene
   céntimos, y por eso `DECIMALES` existe desde el primer día en las facturas.

   La implementación es la de `facturas/totales.js`, que era la única de las
   cuatro que conocía la moneda. No es una quinta versión: es esa, mudada aquí,
   con `totales.js` delegando igual que ya delega `parseImporte`.

   `de-DE` y no `es-ES`: los dos dan «1.234.567,89», pero el alemán agrupa de
   tres en tres también en los números de cuatro cifras («1.500») y el español
   los deja pegados («1500»). En una columna de importes eso es una fila que no
   alinea con las demás.
   ========================================================================== */

/* Decimales por moneda. La rupia no usa céntimos. Si aparece una moneda nueva,
   se añade AQUÍ y no en la herramienta que la necesite primero. */
const LW_DECIMALES = { EUR:2, USD:2, AUD:2, IDR:0 };

/* Importe a texto para enseñarlo. Devuelve SIEMPRE con su moneda detrás: un
   número suelto en esta suite no significa nada, porque se opera en cuatro. */
function lwFormatoImporte(n, moneda){
  const d = LW_DECIMALES[moneda] != null ? LW_DECIMALES[moneda] : 2;
  return new Intl.NumberFormat('de-DE', { minimumFractionDigits:d, maximumFractionDigits:d })
    .format(Number(n) || 0) + (moneda ? ' ' + moneda : '');
}

/* ═══════════════════════════════════════════════════════════════════════════
   LA FORMA CANÓNICA DE UN CAMPO DE IMPORTE — 26-ago-2026
   ═══════════════════════════════════════════════════════════════════════════
   Al salir de un campo de dinero, lo escrito se reescribe en forma canónica
   («44000» → «44.000», «44000,5» → «44.000,50») para que lo que se VE sea
   exactamente lo que se GUARDA, en vez de quedar a merced de cómo escribió los
   separadores cada agente.

   Estaba escrita DOS veces, idéntica y por separado: `fmtImporte` en
   `contracts/app.html` y una lambda dentro del `blur` de `facturas/index.html`.
   Dos copias de la misma regla son dos reglas: el día que una acepte tres
   decimales, el mismo importe se guardará distinto según por qué pantalla haya
   entrado, y nada dará error.

   NO es `lwFormatoImporte`, y por eso vive aparte en vez de reutilizarla:
     · aquí NO va la moneda detrás — es el valor de un `<input>`, y «44.000 EUR»
       dentro del campo no se puede volver a parsear como número;
     · los decimales salen del NÚMERO, no de la moneda: quien teclea 44000 ve
       «44.000» y no «44.000,00», que en un campo editable se lee como ruido.
   Imprimir un importe en pantalla sigue siendo `lwFormatoImporte`, siempre.   */
/* ⚠️ CERO Y VACÍO NO SON LO MISMO, y las dos copias no se ponían de acuerdo.
   `contracts/app.html` hacía `n === null ? '' : fmtImporte(n)` → un 0 tecleado
   se quedaba «0». `facturas/index.html` hacía `n ? fmt(n) : ''` → como 0 es
   falso en JS, **el campo se vaciaba solo al escribir 0**. El mismo gesto, dos
   resultados, y ninguno de los dos ficheros sabía del otro. Manda el primero:
   quien teclea un cero lo teclea a propósito y tiene que verlo. `null` (campo
   vacío, que es lo que devuelve `lwParseImporte` sin nada escrito) sí es «». */
function lwImporteCanonico(n){
  if(n === null || n === undefined || n === '') return '';
  const v = Number(n);
  if(!isFinite(v)) return '';
  return v.toLocaleString('es-ES', { minimumFractionDigits: v % 1 ? 2 : 0,
                                     maximumFractionDigits: 2 });
}

/* Node lo necesita para el test; el navegador lo ignora. Sin `module.exports`
   las constantes quedan globales, que es como las usan las nueve herramientas. */
if(typeof module !== 'undefined' && module.exports)
  module.exports = { lwParseImporte, lwFormatoImporte, lwImporteCanonico, LW_DECIMALES };

/* ═══════════════════════════════════════════════════════════════════════════
   SUMAR CUANDO HAY VARIAS MONEDAS — 26-ago-2026
   ═══════════════════════════════════════════════════════════════════════════
   Se saca aquí porque ya se ha tropezado dos veces con lo mismo. La auditoría
   del 19-ago-2026 lo encontró en el listado de Facturas: sumaba EUR con USD en
   una sola cifra y la etiquetaba con la moneda de la PRIMERA fila — un total
   que no existe en ninguna divisa. Se arregló allí, a mano, y al escribir la
   v3 de Operaciones y la de Facturas volvió a aparecer el mismo error, porque
   el arreglo vivía dentro de una función de una pantalla.

   Sumar importes de monedas distintas no es un redondeo mal hecho: es una
   frase falsa. Aquí no se convierte nada —no hay tipo de cambio en el sistema
   y meter uno inventado sería peor— : se suma por separado y se enseñan las
   dos.

       lwSumaPorMoneda(facturas, f => f.total, f => f.moneda)
         → { EUR: 3686187, USD: 12000 }
       lwSumaTexto(mapa)  → "3.686.187,00 EUR · 12.000,00 USD"
   ═══════════════════════════════════════════════════════════════════════════ */
function lwSumaPorMoneda(lista, importeDe, monedaDe){
  const out = {};
  (lista || []).forEach(function(x){
    const m = (monedaDe ? monedaDe(x) : x.moneda) || 'EUR';
    out[m] = (out[m] || 0) + (Number(importeDe ? importeDe(x) : x.total) || 0);
  });
  return out;
}
/* Una sola moneda se lee como siempre. Con varias, se enseñan todas: esconder
   la segunda por que "casi todo es en euros" es exactamente cómo se cuela un
   total que miente. */
function lwSumaTexto(mapa){
  const claves = Object.keys(mapa || {});
  if(!claves.length) return lwFormatoImporte(0, 'EUR');
  return claves.sort(function(a,b){ return mapa[b] - mapa[a]; })
               .map(function(m){ return lwFormatoImporte(mapa[m], m); })
               .join(' · ');
}
/* La moneda dominante, para cuando hace falta UNA (una barra de progreso, un
   porcentaje). Si hay varias, quien llame debe decir que el porcentaje es de
   esa; no vale mezclarlas por debajo. */
function lwMonedaPrincipal(mapa){
  const claves = Object.keys(mapa || {});
  if(!claves.length) return 'EUR';
  return claves.sort(function(a,b){ return mapa[b] - mapa[a]; })[0];
}
