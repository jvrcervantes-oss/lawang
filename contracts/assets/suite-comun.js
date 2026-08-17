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

/* EL AVISO SE ANUNCIA, NO SOLO SE PINTA — 17-ago-2026, auditoría de accesibilidad.
   En buena parte de la suite este aviso es la ÚNICA confirmación de que algo se
   guardó, y su nodo era un `<div>` mudo: quien no ve la pantalla no recibía ni
   «guardado» ni «no se pudieron leer las facturas». En toda la suite había un solo
   `aria-live`, y estaba en el login.

   Se arregla aquí y no en las catorce copias del marcado a propósito: `toast()` es
   el único sitio por el que pasan todos los avisos, así que poniendo los atributos
   al usarlo quedan puestos en las catorce sin tocar catorce ficheros — y en las que
   se añadan mañana. Si el nodo no existe, se crea: así una herramienta nueva no
   puede quedarse sin avisos por haber olvidado el `<div>`.

   `role="status"` + `aria-live="polite"` y no `alert`/`assertive`: un guardado
   correcto no debe cortar lo que el lector esté leyendo. Los errores de verdad de
   esta suite no van por aquí, van por `lwConfirmar()` y por los avisos de campo.
   `aria-atomic` para que se lea el mensaje entero y no la parte que cambió. */
function nodoToast() {
  let t = document.querySelector('#toast');
  if (!t) {
    t = document.createElement('div');
    t.id = 'toast';
    t.className = 'toast';
    document.body.appendChild(t);
  }
  if (!t.getAttribute('role')) t.setAttribute('role', 'status');
  if (!t.getAttribute('aria-live')) t.setAttribute('aria-live', 'polite');
  if (!t.getAttribute('aria-atomic')) t.setAttribute('aria-atomic', 'true');
  return t;
}

const toast = (m, ms) => {
  const t = nodoToast();
  if (!t) return;
  t.textContent = m;
  /* Quitar las clases, forzar un reflujo y volver a ponerlas. Sin esto, un
     segundo aviso que llega con el primero AÚN VISIBLE no reinicia la barra de
     cuenta atrás —las clases ya estaban puestas, así que el navegador no
     reproduce la animación otra vez— y la barra terminaría a mitad del aviso
     nuevo. Leer `offsetWidth` es lo que obliga al reflujo; parece una línea
     inútil y es justo la que hace que funcione. */
  t.classList.remove('show', 'on');
  void t.offsetWidth;
  t.classList.add('show', 'on');
  clearTimeout(t._h);
  t._h = setTimeout(() => t.classList.remove('show', 'on'), ms || duracionToast());
};

/* El vocabulario de negocio (nombres de los tipos de contrato, qué tipos NO
   suman precio) vive en assets/vocabulario.js, no aquí: contracts/app.html lo
   necesita y no puede cargar ESTE fichero, porque su `esc()` local chocaria con
   el de aqui y reventaria la pagina entera. */
