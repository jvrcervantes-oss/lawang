/* Puerta de acceso de las herramientas internas de Lawang — 28-jul-2026.
   Regla del estudio: ninguna herramienta se sirve sin sesión. Antes se cumplía
   a mano y tres páginas se habían quedado fuera (el maquetador de dossiers, el
   constructor de diseño y la portada), públicas para cualquiera con la URL.

   Se carga en el <head>, DESPUÉS del CDN de supabase-js y sin `defer`:
     <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.min.js"></script>
     <script src="/contracts/assets/guard.js"></script>

   ⚠️ Esto es una PUERTA, no el candado. Una página estática siempre se puede
   leer con el navegador apagando el JS: lo que de verdad protege los datos es
   la RLS de Supabase. Sirve para páginas que no traen datos propios (el dossier
   trabaja contra JSON local).

   DESDE EL 4-ago-2026 PASAN POR AQUÍ LAS NUEVE, Contratos y Facturas incluidas,
   pero esas dos SIN `data-herramienta`. El motivo: su permiso lo comprueban
   ellas y lo comprueban MEJOR —Facturas exime al modo `?vista=1`, con el que el
   visor de Operaciones embebe un documento ya emitido para consultarlo, y eso
   guard.js no lo sabe—. Lo que sí aporta la puerta aquí es lo que faltaba:
   sesión, cuenta activa y UN SOLO cliente de Supabase por página, publicado en
   `LW_SB`. Sin eso, la barra compartida (panel de usuario y campana) no tenía de
   dónde colgarse y no salía en las dos herramientas más usadas.

   Falla CERRADA a propósito: si el CDN no carga o la sesión no se puede
   comprobar, se va al login. Un fallo de red no debe abrir la herramienta.

   La página queda oculta hasta confirmar sesión — si no, la herramienta se
   pinta entera durante un instante antes de redirigir, y eso se lee y se
   fotografía.

   PERMISO POR HERRAMIENTA (29-jul-2026). Declararlo en la propia etiqueta:
     <script src="/contracts/assets/guard.js" data-herramienta="contratos"></script>
   Si el usuario tiene ficha en `public.usuarios` y esa herramienta no está en
   su lista, se le devuelve a la intranet. **Sin ficha ya NO se permite**
   (8-sep-2026): esa compatibilidad con las cuentas anteriores al panel dejaba
   entrar a cualquier sesión que no fuera del equipo — ver la nota junto al
   `if (!ficha)`. Las funciones SQL conservan la suya; ésta era la puerta.
   ⚠️ Esto decide lo que se VE. Lo que de verdad impide escribir es la RLS
   (`puede('herramienta')` en las policies) — esto solo evita enseñar una
   herramienta que luego fallaría al guardar.

   VARIAS HERRAMIENTAS, con coma (7-ago-2026): `data-herramienta="dossier,creatividades"`
   deja pasar con CUALQUIERA de las dos. Lo usa el visor de /intranet/creatividades/,
   que enlaza a Dossier y a Creatividades de redes sin ser ninguna de las
   dos — bloquearlo a una sola dejaría fuera a quien solo tiene la otra.
   Con un solo valor se comporta exactamente igual que antes. */
(function () {
  /* Base de la instancia (ERP F3, 25-sep-2026): ÚNICA fuente del host y la clave publicable. El resto de la suite
     (editores.js, datos.js, asistente…) las lee de window.LW_SB_URL / LW_SB_KEY en vez de escribirlas otra vez:
     cinco copias a mano eran cinco sitios que una instancia nueva del ERP tenía que acordarse de cambiar. Van
     ANTES del modo QA para que existan también con el doble local. */
  var FICHA = window.LW_INSTANCIA;
  if (!FICHA || !/^https:\/\/[a-z0-9]+\.supabase\.co$/.test(FICHA.sb_url || '')) {
    // sin ficha no hay base: se para aquí (la página no carga nada, igual que si faltara guard.js)
    throw new Error('[guard] falta /contracts/assets/instancia.js antes de guard.js');
  }
  var URL_SB = FICHA.sb_url;
  var KEY_SB = FICHA.sb_key;   // publicable: el candado es la RLS
  /* Solo lectura, y las edges se piden SOLO con window.lwEdge(nombre) (consulta de deploy 21c54a71, Seguridad): si
     guard.js no llegara (404, CDN viejo), llamar a lwEdge lanza ANTES de construir la petición, así que el token de
     la sesión nunca sale hacia una ruta relativa de la propia web; y un elemento con id="lwEdge"/"LW_SB_URL" inyectado
     en el HTML no se puede llamar ni pisa estas propiedades. try: si la página cargara guard.js dos veces, la segunda
     no revienta (la primera ya fijó los mismos valores). */
  function fija(k, v) { try { Object.defineProperty(window, k, { value: v, writable: false, configurable: false, enumerable: true }); } catch (e) {} }
  fija('LW_SB_URL', URL_SB);
  fija('LW_SB_KEY', KEY_SB);
  fija('lwEdge', function (nombre) {
    if (!/^[a-z0-9-]+$/.test(String(nombre))) throw new Error('lwEdge: nombre de edge no válido');
    return URL_SB + '/functions/v1/' + nombre;
  });
  /* MODO QA (28-ago-2026) — revisión previa: Desarrollo + Datos + Seguridad,
     CEO/revisiones/estado.json. Único punto de entrada para las herramientas
     que cargan guard.js: nunca se copia este `if` en cada index.html (los
     tres departamentos lo pidieron independientemente — "una lista a mano en
     dos sitios ES el bug", ya escrito en contexto/suite_lawang.md).
     Solo se alcanza con localhost + ?qa=1; fuera de eso, código muerto. El
     doble (_qa_double_guard.js) está gitignored y nunca llega a Hostinger,
     así que fuera de localhost esto ni siquiera puede cargar. Detalle y
     límites conocidos: cabecera de _qa_double_guard.js. */
  try {
    if (location.hostname === 'localhost' &&
        new URLSearchParams(location.search).get('qa') === '1') {
      document.write('<script src="/_qa_double_guard.js"><\/script>');
      return;
    }
  } catch (e) { /* si algo falla aquí, se sigue por el camino real de abajo */ }

  /* 1-sep-2026: /intranet/ tiene login propio (antes /entrar/, puerta
     compartida con el portal del cliente, retirada como punto de entrada
     — sigue viva por si algo externo aún apunta ahí, pero nada del estudio
     enlaza a ella desde hoy). */
  var LOGIN  = '/intranet/';
  var HUB    = '/intranet/';

  var propia = document.currentScript;
  var HERRAMIENTA = propia && propia.getAttribute('data-herramienta');
  var HERRAMIENTAS_REQ = HERRAMIENTA ? HERRAMIENTA.split(',') : null;
  /* `data-rol` (23-sep-2026, LAW-275, decisión del owner): las pantallas del
     Panel de control de la v4 no son una herramienta asignable sino de
     dirección — Ajustes, Condiciones, Equipos de venta, Cuentas, Usuarios
     (`admin`) y Comisión de administración, Sociedades (`super_admin`). Hasta
     hoy el menú las escondía por rol pero la puerta dejaba pasar a cualquier
     ficha activa que tecleara la URL (los datos ya los protegía la RLS; la
     cáscara no). Se SUMA a `data-herramienta`, no la sustituye: con las dos,
     hacen falta las dos. Sin ficha legible no se entra (al revés que la regla
     general de abajo): una puerta de dirección no se abre por no poder mirar. */
  var ROL_REQ = propia && propia.getAttribute('data-rol');
  /* `data-rol` admite una LISTA separada por espacios (23-sep-2026, owner:
     «los sales manager deben tener acceso a dar de alta su equipo de ventas
     + condiciones a ellos»): `data-rol="admin sales_manager"`. El super_admin
     entra siempre; `admin` incluye al super_admin como hasta hoy; cualquier otro
     rol listado entra solo si es el suyo. Un `data-rol` sin ningún rol conocido
     se trata como `admin` (lo de siempre): nunca se abre por un typo. */
  var ROLES_REQ = (ROL_REQ || '').split(/\s+/).filter(function (x) { return x; });
  function rolBasta(ficha) {
    if (!ROL_REQ) return true;
    if (!ficha) return false;
    if (ficha.rol === 'super_admin') return true;
    if (ROLES_REQ.length === 1 && ROLES_REQ[0] === 'super_admin') return false;
    var otros = ROLES_REQ.filter(function (x) { return x !== 'admin' && x !== 'super_admin'; });
    if (ficha.rol === 'admin') return ROLES_REQ.indexOf('admin') !== -1 || !otros.length;
    return otros.indexOf(ficha.rol) !== -1;
  }

  var raiz = document.documentElement;
  raiz.style.visibility = 'hidden';

  /* Indicador de carga (11-ago-2026): la puerta hace dos viajes de red seguidos
     (sesión + ficha de usuarios.rol) antes de pintar nada, y hasta ahora esos
     ~300-600ms eran una pantalla en blanco — se leía como que la intranet iba
     lenta. No se toca el fail-closed (sigue sin pintarse NADA del contenido
     real hasta confirmar sesión): esto es un `visibility:visible` propio por
     encima del `hidden` del <html>, con la marca del estudio, nada de datos. */
  var carga = document.createElement('div');
  carga.id = 'lw-gate-carga';
  carga.style.cssText = 'visibility:visible;position:fixed;inset:0;display:flex;' +
    'align-items:center;justify-content:center;background:var(--rl,#F5F0E6);z-index:2147483647';
  carga.innerHTML = '<div style="width:32px;height:32px;border:2.5px solid rgba(16,76,79,.16);' +
    'border-top-color:var(--dl,#104C4F);border-radius:50%;animation:lw-gate-girar .75s linear infinite">' +
    '</div><style>@keyframes lw-gate-girar{to{transform:rotate(360deg)}}</style>';
  raiz.appendChild(carga);
  function quitarCarga() { if (carga.parentNode) carga.parentNode.removeChild(carga); }

  function alLogin() {
    location.replace(LOGIN + '?next=' + encodeURIComponent(location.pathname + location.search));
  }

  window.LW_AUTH = new Promise(function (resolve) {
    function comprobar() {
      if (!window.supabase || !window.supabase.createClient) { alLogin(); return; }
      /* UN SOLO CLIENTE POR PÁGINA (4-ago-2026). Contratos y Facturas se montaban
         el suyo además de este, y dos clientes de supabase-js sobre el mismo
         almacenamiento de sesión se pisan al refrescar el token. Se publica el de
         aquí y esas herramientas lo toman en vez de crear otro. */
      var sb = window.LW_SB || window.supabase.createClient(URL_SB, KEY_SB);
      window.LW_SB = sb;
      sb.auth.getSession().then(function (r) {
        var sesion = r && r.data && r.data.session;
        if (!sesion) { alLogin(); return; }
        /* MODO MANTENIMIENTO (23-sep-2026): el estado se pide YA, en paralelo a
           la ficha, para no sumar un viaje. La lógica vive en cierre.js (la
           comparte el hub). Su lectura nunca rechaza —un fallo es `null` y se
           pasa—, así que no puede tumbar la ficha si la base no contesta. */
        var cierre = window.lwCierre;
        if (!cierre) console.error('[guard] falta /contracts/assets/cierre.js antes de guard.js: el modo mantenimiento no se aplica en esta página');
        var pEstado = cierre ? cierre.leer(sb) : Promise.resolve(null);
        function entrar(ficha) {
          var sigue = cierre ? cierre.puerta(sb, ficha, pEstado).catch(function () { return true; }) : Promise.resolve(true);
          sigue.then(function (ok) {
            quitarCarga();
            if (!ok) return;          // pantalla de mantenimiento puesta: la herramienta no arranca
            raiz.style.visibility = '';
            resolve({ sb: sb, session: sesion, ficha: ficha });
          });
        }
        // la ficha manda qué herramientas ve. La RLS de `usuarios` ya limita
        // esta consulta a la fila propia (o a todas, si es admin).
        // `notif_visto_hasta` lo usa la campana de topbar.js para saber qué es
        // nuevo. Se pide aquí y no allí porque esta consulta ya se hace: pedirla
        // dos veces sería dos viajes para la misma fila.
        /* ⚠️ 14-sep-2026 — EL CLAIM `portal` YA NO ECHA POR SI SOLO, Y EL ORDEN
           ES LO IMPORTANTE. Hasta hoy esto miraba `app_metadata.portal` ANTES
           de leer la ficha de `usuarios` y mandaba a /portal/ a cualquiera que
           lo tuviera. Con la decision del owner de que una misma cuenta pueda
           ser del equipo Y comprador (hay 8 personas del equipo con ficha de
           comprador, 6 de ellas con contrato), poner el claim a un admin lo
           habria echado de su propia intranet — un candado que se cierra por
           dentro.
           Manda la FICHA: si existe y esta activa, es del equipo y entra, tenga
           el claim o no. El claim solo decide a donde va quien NO es del equipo,
           y eso se decide abajo, ya con la ficha leida. La regla de fondo del
           8-sep no se toca: sin ficha de equipo no se entra a /intranet/. */
        sb.from('usuarios').select('rol, herramientas, activo, nombre, notif_visto_hasta')
          .eq('user_id', sesion.user.id).maybeSingle()
          .then(function (f) {
            var ficha = (f && f.data) || null;
            if (ficha && !ficha.activo) { alLogin(); return; }   // desactivado = fuera
            /* SIN FICHA = NO ES DEL EQUIPO -> FUERA (8-sep-2026, orden del owner:
               «los clientes no deben entrar nunca en /intranet/»).
               Hasta hoy aqui habia una compatibilidad heredada: «sin ficha se
               permite», pensada para las cuentas anteriores al panel de usuarios.
               El claim `portal` (que hasta el 14-sep se miraba ANTES de llegar
               aqui, ver la nota de arriba) tapaba el caso conocido, pero no el
               peligroso: una cuenta de cliente a la que le FALTE ese claim no era
               del equipo y aun asi entraba — con las herramientas vacias por RLS,
               si, pero dentro. Un cliente no debe ver ni la cascara.
               Se puede cerrar hoy porque ya no hay a quien dejar fuera: medido
               contra auth.users el 8-sep, de 43 cuentas 24 tienen ficha de equipo
               y 19 el claim del portal — CERO huerfanas.
               Cierra hacia fuera a proposito: se cierra la sesion antes de mandar
               al login, para no dejar una sesion viva rebotando entre dos puertas. */
            if (!ficha) {
              /* Sin ficha de equipo. Si trae el claim del portal es un
                 comprador: a su casa, con la sesion viva (cerrarla le obligaria
                 a volver a pedir el enlace de entrada por nada). Sin el claim no
                 es de ninguno de los dos mundos: fuera, y cerrando la sesion
                 para no dejarla rebotando entre las dos puertas. */
              if ((sesion.user.app_metadata || {}).portal) { location.replace('/portal/'); return; }
              sb.auth.signOut().then(alLogin, alLogin); return;
            }
            /* Solo el SUPER admin se salta la comprobación (18-ago-2026): un
               admin normal pasa por su lista de herramientas como cualquiera.
               Ver la nota de lwPermitida en assets/herramientas.js — y `puede()`
               en la base, que es quien lo impide de verdad. */
            var sinLimite = ficha && ficha.rol === 'super_admin';
            if (HERRAMIENTAS_REQ && ficha && !sinLimite &&
                !HERRAMIENTAS_REQ.some(function (h) { return (ficha.herramientas || []).indexOf(h) !== -1; })) {
              location.replace(HUB + '?sin_permiso=' + encodeURIComponent(HERRAMIENTA));
              return;
            }
            if (!rolBasta(ficha)) {
              location.replace(HUB + '?sin_permiso=' + encodeURIComponent('Panel de control'));
              return;
            }
            entrar(ficha);
          })
          .catch(function () {   // sin poder leer la ficha se entra igual: la RLS sigue protegiendo los datos
            if (!rolBasta(null)) { location.replace(HUB + '?sin_permiso=' + encodeURIComponent('Panel de control')); return; }
            entrar(null);         // …salvo con la intranet cerrada: sin ficha no se puede probar que sea admin
          });
      }).catch(alLogin);
    }
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', comprobar);
    else comprobar();
  });
})();
