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
   trabaja contra JSON local). Contratos y Facturas mantienen su propia
   comprobación porque además necesitan el cliente de Supabase para leer.

   Falla CERRADA a propósito: si el CDN no carga o la sesión no se puede
   comprobar, se va al login. Un fallo de red no debe abrir la herramienta.

   La página queda oculta hasta confirmar sesión — si no, la herramienta se
   pinta entera durante un instante antes de redirigir, y eso se lee y se
   fotografía. */
(function () {
  var URL_SB = 'https://vtulllundrfennhjddhc.supabase.co';
  var KEY_SB = 'sb_publishable_B_ot_6lNVRLiWiEMtApYOQ_3Ho3xNUg';   // publicable: el candado es la RLS
  var LOGIN  = '/contracts/login.html';

  var raiz = document.documentElement;
  raiz.style.visibility = 'hidden';

  function alLogin() {
    location.replace(LOGIN + '?next=' + encodeURIComponent(location.pathname + location.search));
  }

  window.LW_AUTH = new Promise(function (resolve) {
    function comprobar() {
      if (!window.supabase || !window.supabase.createClient) { alLogin(); return; }
      var sb = window.supabase.createClient(URL_SB, KEY_SB);
      sb.auth.getSession().then(function (r) {
        var sesion = r && r.data && r.data.session;
        if (!sesion) { alLogin(); return; }
        raiz.style.visibility = '';
        resolve({ sb: sb, session: sesion });
      }).catch(alLogin);
    }
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', comprobar);
    else comprobar();
  });
})();
