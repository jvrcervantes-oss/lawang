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
const TOAST_MS = {};
function duracionToast(variable, fallback){
  const k = variable || '--t-toast';
  if (TOAST_MS[k]) return TOAST_MS[k];
  const v = getComputedStyle(document.documentElement).getPropertyValue(k).trim();
  const n = parseFloat(v);
  TOAST_MS[k] = !n ? (fallback || 4200) : (v.endsWith('ms') ? n : n * 1000);   // acepta 4200ms y 4.2s
  return TOAST_MS[k];
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
   correcto no debe cortar lo que el lector esté leyendo. Los errores SÍ — desde el
   14-sep-2026 van por `toastMal()`, que usa su propia región con `alert`.
   `aria-atomic` para que se lea el mensaje entero y no la parte que cambió. */
function nodoToast(id, clase, rol, live) {
  let t = document.querySelector('#' + (id || 'toast'));
  if (!t) {
    t = document.createElement('div');
    t.id = id || 'toast';
    document.body.appendChild(t);
  }
  /* Las clases se ponen SIEMPRE, no solo al crear el nodo: catorce herramientas
     traen su `<div id="toast">` escrito a mano en el HTML, y al de error hay que
     añadirle `mal` aunque el nodo ya existiera. */
  (clase || 'toast').split(' ').forEach(c => { if (c) t.classList.add(c); });
  if (!t.getAttribute('role')) t.setAttribute('role', rol || 'status');
  if (!t.getAttribute('aria-live')) t.setAttribute('aria-live', live || 'polite');
  if (!t.getAttribute('aria-atomic')) t.setAttribute('aria-atomic', 'true');
  return t;
}

const pintarAviso = (t, m, ms) => {
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
  t._h = setTimeout(() => t.classList.remove('show', 'on'), ms);
};

const toast = (m, ms) => pintarAviso(nodoToast(), m, ms || duracionToast());

/* ── EL AVISO DE ERROR NO SE PARECE AL DE «guardado» — 14-sep-2026 ───────────
   Owner, textual: «si da algun error el pop up ponlo en el centro y en rojo, que
   destaque que ha habido algun problema. Eso aplicalo a todos los pop-up de
   errores». Hasta hoy los cuatrocientos y pico avisos de la suite salian
   EXACTAMENTE iguales: «Ficha actualizada» y «No se pudo guardar» compartian pie
   de pantalla, gris y duracion. Un fallo se leia como una confirmacion — y con
   la barra de cuenta atras corriendo, desaparecia antes de entenderlo.

   Es una funcion APARTE y no un `toast(m, {error:true})` a proposito: el segundo
   argumento de `toast()` YA es la duracion en ms y hay llamadas que la usan, asi
   que meter un objeto ahi es una compatibilidad que se rompe sola. Y un nombre
   propio se busca con grep para siempre, que es como se audita si un `catch`
   nuevo se olvido de usarlo.

   Nodo propio, no el mismo con otra clase: `role`/`aria-live` no se cambian en
   caliente de forma fiable —el lector de pantalla ya tiene registrada la region
   con el modo que tenia— y aqui el modo es el contrario. Un error SI debe cortar
   lo que se este leyendo: `alert` + `assertive`. Esto DEROGA la nota de arriba
   («los errores de verdad no van por aqui, van por lwConfirmar»): desde hoy si
   pasan por aqui, y por eso necesitan su propia region.

   Y dura mas (`--t-toast-mal`, 7 s): centrado y en rojo se ve, pero el texto de
   estos avisos es largo —varios explican que hacer a continuacion— y 4,2 s no
   dan para leerlo. */
const toastMal = (m, ms) => pintarAviso(
  nodoToast('toastMal', 'toast mal', 'alert', 'assertive'),
  m, ms || duracionToast('--t-toast-mal', 7000));

/* ── EL ERROR SE TRADUCE ANTES DE ENSEÑARLO — 22-sep-2026 ───────────────────
   Había 24 `toastMal(... + error.message)` repartidos por la suite: cuando
   fallaba algo, el usuario leía el inglés de Postgres («update or delete on
   table "clients" violates foreign key constraint…») y no sabía qué hacer.
   El owner, textual: «cada vez que voy a hacer algo me encuentro un bug nuevo».
   Parte de esos «bugs» eran errores legítimos mal contados.

   Regla: nuestros propios RAISE (P0001, o 42501/23503/23514 con texto en
   castellano escrito para el usuario, como los de guardar_recibi o
   borrar_comprador) se enseñan TAL CUAL: están escritos para eso. Lo que se
   traduce es SOLO lo que Postgres/PostgREST/Storage generan solos, y se
   reconoce por sus plantillas inglesas, no por el código SQLSTATE — el código
   no discrimina (nuestros RAISE reutilizan 23503 y 42501 a propósito, para que
   las policies y los catch existentes los traten igual). Hallazgo de Desarrollo
   en la revisión previa: un mapa por código tapaba mensajes ya escritos.

   El crudo va SIEMPRE a console.error: la consola es para nosotros, el aviso
   para la persona. `window.lwErrorHumano` y no `const`: `contracts/app.html`
   no carga este fichero (choque de `esc`), y sus scripts compartidos hacen
   `(window.lwErrorHumano || …)` para no reventar dentro de un catch. */
window.lwErrorHumano = function (error, prefijo) {
  const e = error || {};
  const msg = String(e.message || (typeof e === 'string' ? e : '') || '');
  const code = String(e.code || '');
  const status = Number(e.statusCode || e.status || 0);
  let texto = null;
  if (/^new row violates row-level security|^permission denied/i.test(msg)) {
    texto = 'No tienes permiso para hacer esto';
  } else if (/^duplicate key value/i.test(msg)) {
    texto = 'Ya existe uno igual';
  } else if (/^update or delete on table .* violates foreign key/i.test(msg)) {
    texto = 'Está enlazado a otros datos y no se puede borrar';
  } else if (/^insert or update on table .* violates foreign key/i.test(msg)) {
    texto = 'Apunta a un dato que ya no existe: recarga y vuelve a intentarlo';
  } else if (/^null value in column/i.test(msg)) {
    texto = 'Falta un dato obligatorio';
  } else if (/violates check constraint/i.test(msg)) {
    texto = 'Un dato no cumple una regla del sistema';
  } else if (code === 'PGRST116' || /^JSON object requested, multiple \(or no\) rows/i.test(msg)) {
    texto = 'No existe o no tienes acceso';
  } else if (code === 'PGRST301' || /JWT expired|jwt expired/i.test(msg)) {
    texto = 'Tu sesión ha caducado: vuelve a entrar';
  } else if (/Failed to fetch|NetworkError|Load failed|ERR_NETWORK/i.test(msg) || (e instanceof TypeError && !code)) {
    texto = 'No hay conexión con la base: comprueba la red y vuelve a intentarlo';
  } else if (status === 413 || /exceeded the maximum allowed size|Payload too large/i.test(msg)) {
    texto = 'El fichero es demasiado grande';
  } else if (/^Bucket not found|^Object not found|^The resource was not found/i.test(msg)) {
    texto = 'El fichero no está donde debería';
  } else if (/^PGRST20[0-4]$/.test(String(code || '')) ||
             /^(invalid input syntax for type|column "?[\w.]+"? does not exist|relation "[^"]*" does not exist|function [^\s(]+\([^)]*\) does not exist|operator does not exist)/i.test(msg)) {
    /* Errores de ESQUEMA (columna que ya no está, uuid mal formado, relación que
       PostgREST no encuentra): son un bug nuestro, no algo que la persona pueda
       arreglar, y el texto crudo son nombres de tablas. Seguridad, 22-sep. */
    texto = 'Error interno: avisa al estudio (el detalle queda en la consola)';
  } else if (msg) {
    texto = msg;                       // nuestro: ya está escrito para la persona
  } else {
    texto = 'Algo ha fallado';
  }
  try { console.error('[lawang]', prefijo || '', error); } catch (_) { /* consola cerrada */ }
  /* El prefijo puede venir con su «: » de antes (`lwT('No se pudo guardar: ')`):
     la clave de traducción de lwT es la frase exacta, así que no se toca la
     llamada y se limpia aquí. */
  const pre = prefijo ? String(prefijo).replace(/[\s:]+$/, '') : '';
  return pre ? pre + ': ' + texto : texto;
};

/* Node lo necesita para el test (contracts/assets/errores.test.js); el
   navegador lo ignora. */
if (typeof module !== 'undefined' && module.exports)
  module.exports = { lwErrorHumano: window.lwErrorHumano };

/* El vocabulario de negocio (nombres de los tipos de contrato, qué tipos NO
   suman precio) vive en assets/vocabulario.js, no aquí: contracts/app.html lo
   necesita y no puede cargar ESTE fichero, porque su `esc()` local chocaria con
   el de aqui y reventaria la pagina entera. */
