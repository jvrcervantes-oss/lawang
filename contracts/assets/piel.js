/* ═══════════════════════════════════════════════════════════════════════════
   PIEL · la cara v4 del generador — 23-sep-2026, INCONDICIONAL desde el 27-sep
   ═══════════════════════════════════════════════════════════════════════════
   QUÉ ES. El generador de contratos (`contracts/app.html`) tuvo dos caras, la
   clásica y la de la intranet v4, y este fichero decidía cuál encender (con
   `?v4=1`, viniendo de /intranet/v4/ o por sessionStorage).

   27-sep-2026 (owner, «Archivar lo muerto + v4 en todo lo vivo»): la clásica
   se retira. La v4 se enciende SIEMPRE, sin parámetro ni salida `?v4=0`, y
   cualquier enlace que llegue aquí —CRM «Crear contrato», correos viejos,
   portal, Facturas, marcadores— acaba en la cara v4 sin tener que acordarse de
   nada. Por eso ya no hay `sessionStorage` (`lw-piel`) ni mirada al referrer.

   La v3 tampoco entra: `movimiento-v3.js` y sus hojas salieron de app.html ese
   mismo día, así que la llave `lw3-on` de otra herramienta de la pestaña no
   puede apilar una segunda capa encima (ese era el bug de tener dos).

   Va SÍNCRONO y en la <head>, antes de cualquier hoja: la clase tiene que
   estar puesta antes del primer pintado. `window.LW_PIEL` se queda en 'v4'
   porque lo leen nav.js y el motor.
   ═══════════════════════════════════════════════════════════════════════════ */
(function () {
  'use strict';
  var q = new URLSearchParams(location.search);
  window.LW_PIEL = 'v4';

  /* No hay listado propio aquí: el listado es /intranet/v4/contratos/. Dos
     listados es la duplicación que el stub `v4/generador-contratos/` ya
     prohíbe (revisión previa #55, Desarrollo). Solo entran al editor las
     cuatro puertas que init() de app.html conoce; `/contracts/` a pelo (el
     listado clásico de antes) va al de la v4. */
  var editor = q.has('contrato') || q.has('nuevo') || q.has('cliente') || q.has('lead');
  if (!editor) { location.replace('/intranet/v4/contratos/'); return; }

  document.documentElement.classList.add('v4');

  /* Fuentes de la v4. Se cuelgan aquí, después de decidir la puerta, para
     que `/contracts/` a pelo (que redirige al listado v4) no las pida. */
  [
    'https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:wght,FILL@100..700,0..1&display=swap',
    // Jost de las ventanas del generador con la piel del alta (27-sep-2026)
    'https://fonts.googleapis.com/css2?family=Jost:wght@400;500;600;700&display=swap',
    '/intranet/v4/assets/fonts/fonts.css'
  ].forEach(function (href) {
    var l = document.createElement('link');
    l.rel = 'stylesheet';
    l.href = href;
    document.head.appendChild(l);
  });
})();
