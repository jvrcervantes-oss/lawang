/* ============================================================================
   Identidad de un párrafo de contrato — FUENTE ÚNICA
   ----------------------------------------------------------------------------
   La usa `contracts/app.html` para saber a qué párrafo pertenece cada edición
   manual del boilerplate (los "overrides" del botón «✎ Editar texto»).

   🔴 POR QUÉ EXISTE ESTE FICHERO (31-jul-2026).
   Hasta hoy la identidad era el ORDINAL del párrafo dentro de la plantilla
   (0, 1, 2…). Con eso, cualquier retoque del .html —tokenizar un literal,
   añadir una cláusula, traducir un bloque— corría de sitio TODAS las ediciones
   posteriores y las aplicaba a párrafos ajenos, sin avisar de nada.
   Pasó de verdad: el contrato CR00003 tenía guardado en el ordinal 27 el bloque
   de firmas («Nombre: … — Cargo: Director»); el ordinal 27 de la plantilla de
   hoy es la cláusula de ley aplicable. Abrir ese contrato imprimía una en el
   sitio de la otra.

   La identidad pasa a salir del TEXTO del párrafo. Consecuencia buscada: si el
   párrafo cambia en la plantilla, la edición NO encuentra su sitio y se avisa
   —edición perdida, visible y rehacible— en vez de aterrizar en otro párrafo,
   que es un documento legal falso y silencioso.

   Sin módulos ES a propósito: app.html es HTML plano con <script> clásico, igual
   que entities.js. El `module.exports` del final es solo para el test en node.
   ========================================================================== */

/* FNV-1a de 32 bits. NO es criptografía y no pretende serlo: lo único que hace
   falta es que el mismo texto dé siempre la misma clave y que dos textos
   distintos casi nunca coincidan. Una colisión entre dos párrafos del mismo
   contrato la desempata `huellaBloque` por orden de aparición. */
function huellaTexto(s){
  let h = 0x811c9dc5;
  s = String(s == null ? '' : s);
  for(let i = 0; i < s.length; i++){
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h.toString(36);
}

/* Texto del párrafo normalizado: solo el contenido, con los espacios colapsados.
   Reindentar o reenvolver el .html de la plantilla no debe cambiar la identidad
   de un párrafo — si la cambiara, cada pasada del formateador tiraría todas las
   ediciones guardadas. */
function normaliza(texto){
  return String(texto == null ? '' : texto).replace(/\s+/g, ' ').trim();
}

/* Clave de un bloque. `vistas` es un contador que se comparte entre todas las
   llamadas de un mismo documento: dos párrafos con el MISMO texto (líneas de
   boilerplate repetidas, celdas iguales) comparten huella, así que se desempatan
   por orden de aparición — que entre iguales sí es estable, porque insertar un
   párrafo distinto en medio no cambia cuántos iguales hay antes. */
function huellaBloque(texto, vistas){
  const base = huellaTexto(normaliza(texto));
  const n = (vistas[base] = (vistas[base] || 0) + 1);
  return n > 1 ? base + '~' + n : base;
}

if(typeof module !== 'undefined') module.exports = { huellaTexto, normaliza, huellaBloque };
