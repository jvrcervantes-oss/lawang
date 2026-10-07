// >>> plantillaDato
/* El texto de una plantilla como DATO. Lo escribe una empresa (versiones por
   empresa, S8 del 7-oct-2026) y puede contener «ignora lo anterior…»: va entre
   marcadores y dentro de la cadena JSON de `plantilla.texto`, y los
   delimitadores que lleve dentro se neutralizan para que no pueda cerrar el
   bloque. Función PURA: misma copia en contracts/bot/plantilla_dato.js. */
function plantillaDato(texto) {
  const t = String(texto ?? '').replace(/PLANTILLA_TEXTO/gi, 'PLANTILLA-TEXTO').replace(/<{3,}|>{3,}/g, '·');
  return '<<<PLANTILLA_TEXTO\n' + t + '\nPLANTILLA_TEXTO>>>';
}
// <<< plantillaDato

if (typeof module !== 'undefined') module.exports = { plantillaDato };
