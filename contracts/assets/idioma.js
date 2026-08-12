/* Idioma de INTERFAZ de la suite (ES/EN) — 12-ago-2026, petición del owner:
   hay agentes de habla inglesa y hace falta poder cambiar el idioma al
   entrar, que se aplique a las nueve herramientas.

   Aparte de guard.js a propósito (revisión previa, hallazgo Seguridad):
   guard.js es la puerta fail-closed de sesión de las nueve herramientas, el
   fichero con menos margen de error del repo, y esto no tiene relación con
   sesión — meterlo ahí ampliaba su diff sin necesidad.

   SIN `defer` a propósito: tiene que ejecutar en cuanto el parser lo
   alcanza, en <head>, antes de que el <script> propio de cada herramienta
   arranque y pinte nada. `defer` (lo que sí lleva topbar.js) espera a que
   termine de parsearse todo el documento — para entonces el script de la
   herramienta ya se habría ejecutado sin saber el idioma.

   NO es el idioma del DOCUMENTO IMPRESO de Contratos (ES/EN/ID, atado a cada
   contrato guardado) — ese sistema es aparte y este cambio no lo toca.

   Clave namespaced a propósito (hallazgo Seguridad): ya existen en el MISMO
   origen `lawang_lang` (index.html público, es/en/id) y `lw_portal_lang`
   (portal del comprador) — una clave compartida leería el valor de otro
   sistema sin querer. El valor se valida contra la lista conocida siempre
   que se lee, nunca se confía en lo que haya en localStorage tal cual. */
(function () {
  var CLAVE = 'lawang_idioma_ui';
  var v = null;
  try { v = localStorage.getItem(CLAVE); } catch (e) {}
  window.LW_IDIOMA = (v === 'en') ? 'en' : 'es';   // cualquier otra cosa (vacío, basura, id de otra clave) cae a español

  window.lwSetIdioma = function (idioma) {
    window.LW_IDIOMA = (idioma === 'en') ? 'en' : 'es';
    try { localStorage.setItem(CLAVE, window.LW_IDIOMA); } catch (e) {}
  };
})();
