/* Texto articulado de una plantilla de contrato, en UN idioma y con los campos
   del ejemplar puestos. Función PURA: la misma copia vive en la Edge Function
   (contracts/edge/bot-agentes/index.ts, entre los marcadores >>> y <<< de
   plantillaTexto) y plantilla_texto.test.js comprueba que son iguales
   byte a byte y que el resultado sobre las plantillas reales es el esperado.

   POR QUÉ EXISTE. `plantillas_contrato` guarda nombre y fecha, no el texto: los
   artículos viven en contracts/templates/*.html, que el sitio sirve en abierto.
   La edge los lee de ahí y el modelo puede citar «Art. 6 — Plazo de ejecución»
   en vez de decir que no tiene la plantilla. Un campo sin rellenar sale como
   «(en blanco)» — que es exactamente lo que verá el comprador en el documento —
   y uno reservado (pasaporte, email…) como «(dato reservado)», nunca su valor. */
// >>> plantillaTexto
function plantillaTexto(html, lang, fields, esReservado) {
  const f = fields && typeof fields === 'object' ? fields : {};
  const vacio = (v) => v === null || v === undefined || String(v).trim() === '';
  let s = String(html ?? '');
  s = s.replace(/<(script|style)\b[\s\S]*?<\/\1>/gi, '');
  // <!--if:campo=valor--> … <!--/if:campo--> : solo si el campo vale eso
  s = s.replace(/<!--if:([a-z0-9_]+)=([^>]*?)-->([\s\S]*?)<!--\/if:\1-->/gi, (_m, k, v, inner) => String(f[k] ?? '') === v ? inner : '');
  // <!--opt:campo--> … <!--/opt:campo--> : solo si el campo no está vacío
  s = s.replace(/<!--opt:([a-z0-9_]+)-->([\s\S]*?)<!--\/opt:\1-->/gi, (_m, k, inner) => vacio(f[k]) ? '' : inner);
  s = s.replace(/<!--[\s\S]*?-->/g, '');
  const idioma = ['es', 'en', 'id'].includes(lang) ? lang : 'es';
  for (const otro of ['es', 'en', 'id']) {
    if (otro === idioma) continue;
    s = s.replace(new RegExp('<(p|ul|ol|span|div|li|h[1-6]|td|th|tr)\\b[^>]*\\bdata-lang="' + otro + '"[^>]*>[\\s\\S]*?<\\/\\1>', 'gi'), '');
  }
  s = s.replace(/\{\{([a-z0-9_]+)\}\}/gi, (_m, k) =>
    (typeof esReservado === 'function' && esReservado(k)) ? '(dato reservado)' : vacio(f[k]) ? '(en blanco)' : String(f[k]));
  s = s.replace(/<(h[1-6])\b[^>]*>/gi, '\n\n').replace(/<\/h[1-6]>/gi, '\n');
  s = s.replace(/<br\s*\/?>/gi, '\n').replace(/<li\b[^>]*>/gi, '\n• ').replace(/<\/(p|li|tr|div|ul|ol|table|thead|tbody)>/gi, '\n');
  s = s.replace(/<[^>]+>/g, '');
  s = s.replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&laquo;/g, '«').replace(/&raquo;/g, '»')
    .replace(/&ndash;/g, '–').replace(/&mdash;/g, '—');
  s = s.replace(/[ \t ]+/g, ' ').replace(/ *\n */g, '\n').replace(/\n{3,}/g, '\n\n').trim();
  return s;
}
// <<< plantillaTexto

if (typeof module !== 'undefined') module.exports = { plantillaTexto };
