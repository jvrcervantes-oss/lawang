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

/* Node lo necesita para el test; el navegador lo ignora. Sin `module.exports`
   la constante queda global, que es como la usan las nueve herramientas. */
if(typeof module !== 'undefined' && module.exports) module.exports = { lwParseImporte };
