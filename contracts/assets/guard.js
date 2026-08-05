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
   su lista, se le devuelve a la intranet. Sin ficha (cuentas anteriores al
   panel) se permite: mismo criterio de compatibilidad que las funciones SQL.
   ⚠️ Esto decide lo que se VE. Lo que de verdad impide escribir es la RLS
   (`puede('herramienta')` en las policies) — esto solo evita enseñar una
   herramienta que luego fallaría al guardar. */
(function () {
  var URL_SB = 'https://vtulllundrfennhjddhc.supabase.co';
  var KEY_SB = 'sb_publishable_B_ot_6lNVRLiWiEMtApYOQ_3Ho3xNUg';   // publicable: el candado es la RLS
  var LOGIN  = '/contracts/login.html';
  var HUB    = '/intranet/';

  var propia = document.currentScript;
  var HERRAMIENTA = propia && propia.getAttribute('data-herramienta');

  var raiz = document.documentElement;
  raiz.style.visibility = 'hidden';

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
        // la ficha manda qué herramientas ve. La RLS de `usuarios` ya limita
        // esta consulta a la fila propia (o a todas, si es admin).
        // `notif_visto_hasta` lo usa la campana de topbar.js para saber qué es
        // nuevo. Se pide aquí y no allí porque esta consulta ya se hace: pedirla
        // dos veces sería dos viajes para la misma fila.
        /* Un comprador del portal (app_metadata.portal) NO es del equipo: a su
           casa. Sin esto, la compatibilidad "sin ficha se permite" de abajo le
           abriría las herramientas internas (vacías por RLS, pero abiertas). */
        if ((sesion.user.app_metadata || {}).portal) {
          location.replace('/portal/');
          return;
        }
        sb.from('usuarios').select('rol, herramientas, activo, nombre, notif_visto_hasta')
          .eq('user_id', sesion.user.id).maybeSingle()
          .then(function (f) {
            var ficha = (f && f.data) || null;
            if (ficha && !ficha.activo) { alLogin(); return; }   // desactivado = fuera
            var admin = ficha && (ficha.rol === 'super_admin' || ficha.rol === 'admin');
            if (HERRAMIENTA && ficha && !admin &&
                (ficha.herramientas || []).indexOf(HERRAMIENTA) === -1) {
              location.replace(HUB + '?sin_permiso=' + encodeURIComponent(HERRAMIENTA));
              return;
            }
            raiz.style.visibility = '';
            resolve({ sb: sb, session: sesion, ficha: ficha });
          })
          .catch(function () {   // sin poder leer la ficha se entra igual: la RLS sigue protegiendo los datos
            raiz.style.visibility = '';
            resolve({ sb: sb, session: sesion, ficha: null });
          });
      }).catch(alLogin);
    }
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', comprobar);
    else comprobar();
  });
})();
