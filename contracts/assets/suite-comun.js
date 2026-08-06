/* Lo que las nueve pantallas de la suite copiaban — 4-ago-2026
   ----------------------------------------------------------------------------
   Contado antes de escribir esto: `esc()` estaba nueve veces y `toast()` ocho.
   No es solo repetición: al copiarlas se separaron, y una de las separaciones
   era un fallo de verdad.

   `esc` — siete copias BYTE A BYTE iguales (solo cambiaba el nombre del
   parámetro). Aquí una.

   `toast` — divergió en tres cosas a la vez: la clase que enciende el aviso
   (`.on` en Facturas y Usuarios, `.show` en las demás), la duración (2600, 2800
   y 3000 ms) y —esto es el fallo— si se limpia el temporizador anterior. Donde
   no se limpiaba, dos avisos seguidos se pisan: el temporizador del primero
   apaga el segundo a mitad. Pasaba en Operaciones, Compradores, Unidades y
   Documentación, que son justo las que más avisos encadenan.

   Se ponen las DOS clases a propósito. La hoja de estilos de cada herramienta
   sigue como está —una espera `.on`, otra `.show`— y cambiar seis hojas para
   unificar el nombre es mucho riesgo para cero beneficio visible. Poniendo las
   dos, funciona con cualquiera de las dos y el día que se unifiquen no hay que
   volver aquí.

   Se carga ANTES del script de cada página: son `const` de primer nivel, y dos
   declaraciones del mismo nombre en el mismo ámbito global revientan la página
   entera con «Identifier has already been declared». Por eso al añadir esto hay
   que QUITAR la copia local, no dejar las dos. */

/* Escapa para meter texto en HTML. Los cuatro caracteres que importan: `&` el
   primero, o se re-escaparían los que se escriban después. */
const esc = v => String(v == null ? '' : v)
  .replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

/* Cuánto dura el aviso lo dice `--t-toast` de suite.css, no este fichero
   (6-ago-2026). La barra de cuenta atrás del aviso se anima con esa MISMA
   variable, así que si el número viviera aquí y en el CSS, cambiar uno dejaría
   la barra terminando antes o después que el aviso — y una barra que miente es
   peor que no tenerla.
   Sube de 2.800 a 4.200 ms: en la revisión de diseño el aviso se iba antes de
   poder leerlo, y en esta suite varios avisos son la única confirmación de que
   algo se guardó.
   El fallback cubre a quien cargue este script sin suite.css (dossier, firmar).
   Se lee en el PRIMER aviso y no al cargar el script: este fichero puede
   evaluarse antes de que la hoja de estilos haya aplicado, y ahí la variable
   saldría vacía y se quedaría en el fallback para toda la sesión. */
let TOAST_MS = 0;
function duracionToast(){
  if (TOAST_MS) return TOAST_MS;
  const v = getComputedStyle(document.documentElement).getPropertyValue('--t-toast').trim();
  const n = parseFloat(v);
  TOAST_MS = !n ? 4200 : (v.endsWith('ms') ? n : n * 1000);   // acepta 4200ms y 4.2s
  return TOAST_MS;
}

const toast = (m, ms) => {
  const t = document.querySelector('#toast');
  if (!t) return;
  t.textContent = m;
  t.classList.add('show', 'on');
  clearTimeout(t._h);
  t._h = setTimeout(() => t.classList.remove('show', 'on'), ms || duracionToast());
};
