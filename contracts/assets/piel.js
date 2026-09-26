/* ═══════════════════════════════════════════════════════════════════════════
   PIEL · el interruptor de la cara v4 del generador — 23-sep-2026
   ═══════════════════════════════════════════════════════════════════════════
   QUÉ ES. El generador de contratos (`contracts/app.html`) es UNO solo y tiene
   dos caras: la clásica y la de la intranet v4. Decisión del owner (23-sep):
   «nunca dejes obsoleta la versión antigua» → no hay un segundo generador, hay
   una capa de CSS entera bajo `html.v4` y este fichero decide si se enciende.
   Sin él encendido, app.html es exactamente la de siempre.

     /contracts/app.html?nuevo=1&v4=1   enciende la v4 y la deja en ESTA pestaña
     /contracts/app.html?...&v4=0       la apaga (salida de emergencia en caliente)
     /contracts/app.html?nuevo=1        hereda lo que tenga la pestaña

   Por qué `sessionStorage` y no solo el parámetro: `pantallaC()` reescribe la
   URL con `history.replaceState` al pasar de listado a editor y se come el
   `v4=1`; y el CRM abre el generador con sus propios enlaces, sin parámetro.
   El owner decidió (23-sep) que esa entrada HEREDE la piel de la pestaña.
   Es el mismo mecanismo que ya usa la v3 (`movimiento-v3.js`, llave `lw3-on`).

   v3 y v4 son EXCLUYENTES: dos capas de override apiladas es el bug. Todo se
   decide AQUÍ y no en `movimiento-v3.js`, que cargan otras diez páginas (tocarlo
   obliga a resellar las diez): `?v3=1` apaga la v4, y con la v4 puesta la llave
   de la v3 se baja ANTES de que movimiento-v3.js la lea (va al final de la
   <head>; esto, al principio). En el generador, la v4 gana.

   Va SÍNCRONO y en la <head>, antes de cualquier hoja: la clase tiene que
   estar puesta antes del primer pintado o se ve la clásica un instante.
   `window.LW_PIEL` = 'v4' | null — lo leen nav.js y el motor.
   ═══════════════════════════════════════════════════════════════════════════ */
(function () {
  'use strict';
  var LLAVE = 'lw-piel';
  var piel = null;
  function vieneDeLaV4() {
    try {
      var r = new URL(document.referrer);
      return r.origin === location.origin && r.pathname.indexOf('/intranet/v4/') === 0;
    } catch (_) { return false; }
  }
  var q = new URLSearchParams(location.search);
  try {
    if (q.has('v4')) {
      if (q.get('v4') !== '0') {
        piel = 'v4';
        sessionStorage.setItem(LLAVE, 'v4');
        sessionStorage.setItem('lw3-on', '0');     // excluyentes: la v3 se apaga
      } else {
        sessionStorage.removeItem(LLAVE);
      }
    } else if (q.has('v3') && q.get('v3') !== '0') {
      sessionStorage.removeItem(LLAVE);            // pedir la v3 apaga la v4
    } else if (vieneDeLaV4()) {
      /* Se llega desde una pantalla de la v4 («Nuevo contrato», «Editar en el
         generador», el panel, el viejo /v4/generador-contratos/): cara v4. Así
         ningún enlace de la v4 tiene que acordarse de añadir `?v4=1` —cuatro
         sitios que habría que mantener a mano— y se deja en la pestaña. */
      piel = 'v4';
      sessionStorage.setItem(LLAVE, 'v4');
      sessionStorage.setItem('lw3-on', '0');
    } else if (sessionStorage.getItem(LLAVE) === 'v4') {
      piel = 'v4';
      sessionStorage.setItem('lw3-on', '0');       // la v3 pudo encenderse en otra herramienta
    }
  } catch (_) {
    // sessionStorage lanza en ventana privada: vale el parámetro, no se recuerda
    if (q.has('v4') && q.get('v4') !== '0') piel = 'v4';
  }
  window.LW_PIEL = piel;
  if (piel !== 'v4') return;

  /* Con la v4 no hay listado propio aquí: el listado de la v4 es
     /intranet/v4/contratos/. Dos listados es la duplicación que el stub
     `v4/generador-contratos/` ya prohíbe (revisión previa #55, Desarrollo).
     Solo entran al editor las cuatro puertas que init() de app.html conoce. */
  var editor = q.has('contrato') || q.has('nuevo') || q.has('cliente') || q.has('lead');
  if (!editor) { location.replace('/intranet/v4/contratos/'); return; }

  document.documentElement.classList.add('v4');

  /* Fuentes de la v4, SOLO aquí: una hoja de Google puesta en la <head> de
     app.html bloquearía el pintado de la cara clásica, que no las usa. */
  [
    'https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:wght,FILL@100..700,0..1&display=swap',
    // Jost de las ventanas del generador con la piel del alta (27-sep-2026): aquí y no con un @import en
    // suite-v4-generador.css, que se enlaza también en la clásica y le bloquearía el pintado (revisor, 27-sep)
    'https://fonts.googleapis.com/css2?family=Jost:wght@400;500;600;700&display=swap',
    '/intranet/v4/assets/fonts/fonts.css'
  ].forEach(function (href) {
    var l = document.createElement('link');
    l.rel = 'stylesheet';
    l.href = href;
    document.head.appendChild(l);
  });
})();
