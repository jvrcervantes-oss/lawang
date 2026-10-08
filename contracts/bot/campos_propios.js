// >>> camposPropios
/* Campos propios de la empresa ({{cx_*}}, E8 del 8-oct-2026). El valor de un cx_ lo escribe una persona de la
   empresa y puede ser un dato personal: el bot y la IA SOLO ven los que el catalogo marca como NO sensibles
   (plantilla_campos_cx_publicos, calculado en el servidor). Un cx_ que no esta en esa lista —sensible, fuera
   de catalogo, o la lectura fallo— no entra al contexto ni al texto de la plantilla. Funcion PURA: misma copia
   en contracts/bot/campos_propios.js. */
function cxVisible(k, publicos) {
  return !/^cx_/.test(String(k)) || (publicos != null && typeof publicos.has === 'function' && publicos.has(k));
}
// <<< camposPropios

if (typeof module !== 'undefined') module.exports = { cxVisible };
