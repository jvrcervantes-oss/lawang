/* Post-chequeo del bot de apoyo a agentes (encargo 20260922_lawang_bot_apoyo_agentes, S3).
   ============================================================================
   Copia EXACTA de la función que corre en la Edge Function
   contracts/edge/bot-agentes/index.ts, entre los marcadores >>> postCheck y
   <<< postCheck. Vive aquí para poder probarla con `node` sin Deno ni red;
   postcheck.test.js falla si las dos copias se separan. Si hay que cambiar el
   freno, se cambia en la edge y se pega aquí tal cual (o al revés). */

// >>> postCheck
/* Post-chequeo del borrador. Función PURA, sin red ni Deno: la misma copia
   vive en contracts/bot/postcheck.js con su test (postcheck.test.js), que
   además comprueba que las dos copias son byte a byte iguales.

   Descarta el borrador si:
   (a) contiene una secuencia de ≥8 dígitos que no está en contextoTexto. Se
       comparan con los separadores de miles/agrupación quitados (espacio,
       punto o coma seguidos de un grupo de 3-4 dígitos): «1234 5678 9012» y
       «1.234.567.890» son la misma secuencia. Un separador seguido de OTRA
       cosa no se toca: «250,000.00» son decimales (no 25000000) y «hito 2
       600000000» son dos números, no uno. NO se quitan «/» ni «-»: son
       fechas, y una fecha del contexto reescrita con otro separador no es
       una cuenta ajena.
   (b) casa algún patron_salida (regex, insensible a mayúsculas) de bloqueos.
   Un patron_salida que no compila DESCARTA (fail closed): un freno roto no
   puede leerse como "sin freno". */
function postCheck(borrador, contextoTexto, bloqueos) {
  const colapsa = (s) => String(s ?? '').replace(/(\d)[ .,](?=\d{3,4}(?!\d))/g, '$1');
  const ctx = colapsa(contextoTexto);
  const secuencias = colapsa(borrador).match(/\d{8,}/g) || [];
  for (const seq of secuencias) {
    if (!ctx.includes(seq)) {
      return { ok: false, motivo: 'cifra_ajena_al_contexto', detalle: seq.length + ' dígitos' };
    }
  }
  for (const b of bloqueos || []) {
    if (!b || !b.patron_salida) continue;
    let re;
    try { re = new RegExp(b.patron_salida, 'i'); }
    catch (_) { return { ok: false, motivo: 'patron_salida_invalido', detalle: b.motivo || '' }; }
    if (re.test(String(borrador ?? ''))) {
      return { ok: false, motivo: 'patron_salida', detalle: b.motivo || '' };
    }
  }
  return { ok: true };
}
// <<< postCheck

if (typeof module !== 'undefined') module.exports = { postCheck };
