/* nav.js — v4 MAQUETA. La navegación de la maqueta vive SOLO aquí.
 *
 * Stitch pinta en cada pantalla la misma sidebar (Home + 12 herramientas +
 * logout) con todos los enlaces en href="#". En vez de editar 18 HTML, este
 * fichero recablea esa sidebar por el TEXTO del enlace, marca la herramienta
 * activa, injerta el aviso de maqueta con enlace al hub, y desactiva los
 * href="#" restantes (acciones simuladas) para que el clic no salte arriba.
 * Regla de la suite: una lista copiada en dos sitios ES el bug — por eso el
 * mapa de rutas existe una sola vez, aquí. */
(function () {
  'use strict';

  // <base> de la maqueta: carpeta v4/, deducida de la ruta de ESTE script.
  var self = document.currentScript || document.querySelector('script[src*="nav.js"]');
  var ROOT = self ? self.src.replace(/assets\/nav\.js.*$/, '') : '../';

  // etiqueta visible (fin del textContent del enlace) -> carpeta de la herramienta
  var RUTAS = [
    ['Home', 'home/'],
    ['Operaciones', 'operaciones/'],
    ['Soporte', 'soporte/'],
    ['Vencimientos', 'vencimientos/'],
    ['Contratos', 'contratos/'],
    ['Creatividades', 'creatividades/'],
    ['Documentación', 'documentacion/'],
    ['Facturas', 'facturas/'],
    ['Recibos', 'recibos/'],
    ['Proyectos', 'proyectos/'],
    ['Modelos', 'modelos/'],
    ['Obra', 'obra/'],
    ['Compradores', 'compradores/'],
    ['Usuarios', 'usuarios/'],
    /* Las tres que Stitch no dibujo nunca: nacieron despues de la descarga.
       Se enlazan aqui igual que las demas y se INJERTAN abajo (INJERTOS).
       CRM sale de la v4 a proposito: conserva su vista propia en /intranet/leads/
       (owner, 14-sep). Ruta ABSOLUTA, no relativa a ROOT: lo que hay en
       v4/leads/ es solo una redireccion para los enlaces viejos. */
    ['CRM', '/intranet/leads/'],
    ['Comisiones', 'comisiones/'],
    ['Cuentas', 'cuentas/']
  ];

  function normaliza(t) { return (t || '').replace(/\s+/g, ' ').trim(); }

  function marcaActiva(a) {
    a.setAttribute('aria-current', 'page');
    // píldora activa de la cáscara canónica (creatividades, 3-sep-2026)
    a.classList.remove('text-on-surface-variant');
    a.classList.add('bg-primary-container', 'text-on-primary', 'font-bold');
  }

  /* Herramientas que NO existen en el diseno de Stitch: nacieron despues de la
     descarga (Modelos el 7-sep; CRM, Solicitudes/Comisiones y Cuentas ya
     estaban vivas en /intranet/ y la maqueta se habia quedado atras). Sus
     items de menu se INYECTAN aqui en vez de anadirlos a mano en las 22
     sidebars: la cascara esta duplicada por ser maqueta, pero la navegacion
     no — una lista copiada en dos sitios ES el bug, y con 22 copias la
     siguiente herramienta se olvidaria en alguna.
     El orden y el grupo salen de `contracts/assets/herramientas.js`, que es la
     fuente unica del catalogo vivo: cada uno se cuelga detras de su vecino de
     alli (CRM abre Seguimiento -> tras Home; Comisiones (antes «Solicitudes»,
     renombrada 14-sep) cierra Administracion -> tras Recibos; Cuentas es de
     Equipo -> tras Usuarios, que es el ultimo del menu de la maqueta). */
  var INJERTOS = [
    { path: 'leads',      tras: 'home',     icono: 'person_search',  texto: 'CRM',
      href: '/intranet/leads/' },   // vista propia: sale de la v4
    { path: 'comisiones', tras: 'recibos',  icono: 'request_quote',  texto: 'Comisiones' },
    { path: 'cuentas',    tras: 'usuarios', icono: 'account_balance', texto: 'Cuentas' }
  ];

  /* Injertos SOLO para admin/super_admin (14-sep-2026, encargo del owner:
     "Equipos de venta" y "Condiciones" — administración de comisiones).
     Van en un array aparte y no dentro de INJERTOS de arriba porque esos se
     inyectan siempre, para cualquier sesión; estos dos exigen comprobar el rol
     y eso solo se sabe tras `window.LW_AUTH` (guard.js), que resuelve DESPUES
     de este primer pase sincrono. Mismo criterio de rol que `es_admin()` en la
     base (`ficha.rol IN ('admin','super_admin')`) — es la puerta del menu, la
     de verdad la pone la RLS de las cuatro tablas que tocan.
     `tras:'cuentas'` porque 'cuentas' ya esta en el DOM cuando esto corre: lo
     injerto INJERTOS de arriba ya paso en el primer pase sincrono, sea cual
     sea el rol de la sesion. */
  var INJERTOS_ADMIN = [
    { path: 'equipos-venta', tras: 'cuentas',       icono: 'groups',  texto: 'Equipos de venta' },
    { path: 'condiciones',   tras: 'equipos-venta',  icono: 'percent', texto: 'Condiciones' }
  ];

  /* Documentacion se fusiono dentro de Proyectos (owner, 8-sep): la pestana
     desaparece de la v4. Se oculta desde aqui — un solo fichero — en vez de
     editar 22 sidebars; el fichero de la pantalla queda como redireccion. */
  function retiraDocumentacion(aside) {
    var a = aside.querySelector('[data-path="documentacion"]');
    if (a) a.style.display = 'none';
  }

  /* Un solo injertador para los cuatro casos. Clona el enlace vecino para
     heredar sus clases exactas: escribirlas a mano seria la misma lista de
     Tailwind copiada, y divergiria al primer retoque de la cascara. */
  function injerta(aside, spec) {
    if (aside.querySelector('[data-path="' + spec.path + '"]')) return;
    var ancla = aside.querySelector('[data-path="' + spec.tras + '"]');
    if (!ancla) return;                       // sin el vecino no hay donde colgarlo
    var a = ancla.cloneNode(true);            // clon: hereda las clases exactas
    a.setAttribute('data-path', spec.path);
    a.removeAttribute('aria-current');
    var spans = a.querySelectorAll('span');
    if (spans.length < 2) return;
    spans[0].textContent = spec.icono;        // ligadura de material-symbols
    spans[1].textContent = spec.texto;
    /* Con href propio deja de ser href="#", y recablea() ya no lo mira: solo
       recorre `a[href="#"]`. Es el enganche para una herramienta que vive
       fuera de la v4, como el CRM. */
    if (spec.href) a.href = spec.href;
    ancla.insertAdjacentElement('afterend', a);
  }

  function injertaNuevas(aside) {
    injerta(aside, { path: 'modelos', tras: 'proyectos', icono: 'villa', texto: 'Modelos' });
    INJERTOS.forEach(function (spec) { injerta(aside, spec); });
  }

  /* Rol de la sesion -> se enteran solo cuando `window.LW_AUTH` resuelve, que
     en la practica ya ha pasado para cuando la pagina se hace visible (guard.js
     quita `visibility:hidden` justo despues de resolver la promesa), asi que no
     hay parpadeo: el usuario nunca llega a ver el menu sin estos dos items y
     luego perderlos. */
  function esAdminSesion(ficha) { return !!ficha && (ficha.rol === 'admin' || ficha.rol === 'super_admin'); }
  function injertaAdmin(aside, ficha) {
    if (!esAdminSesion(ficha)) return;
    var aqui = location.pathname;
    INJERTOS_ADMIN.forEach(function (spec) {
      if (aside.querySelector('[data-path="' + spec.path + '"]')) return;
      var ancla = aside.querySelector('[data-path="' + spec.tras + '"]');
      if (!ancla) return;
      var a = ancla.cloneNode(true);
      a.setAttribute('data-path', spec.path);
      a.removeAttribute('aria-current');
      var spans = a.querySelectorAll('span');
      if (spans.length < 2) return;
      spans[0].textContent = spec.icono;
      spans[1].textContent = spec.texto;
      // href absoluto ya aqui: el pase generico de `a[href="#"]` de recablea()
      // ya paso cuando esto corre, y no volvera a pasar por este elemento.
      a.href = ROOT + spec.path + '/';
      if (aqui.indexOf('/' + spec.path + '/') !== -1) marcaActiva(a);
      ancla.insertAdjacentElement('afterend', a);
    });
  }

  function recablea() {
    var aqui = location.pathname;
    document.querySelectorAll('aside').forEach(injertaNuevas);
    document.querySelectorAll('aside').forEach(retiraDocumentacion);
    document.querySelectorAll('aside a[href="#"], nav a[href="#"]').forEach(function (a) {
      // 1º por data-path (cáscara canónica); 2º por texto (páginas sin él)
      var dp = a.getAttribute('data-path');
      if (dp) {
        var ruta = dp === 'login' ? 'entrar/' : dp + '/';
        a.href = ROOT + ruta;
        if (dp === 'login') { a.title = 'Maqueta — vuelve a la pantalla de acceso'; return; }
        if (aqui.indexOf('/' + ruta) !== -1) marcaActiva(a);
        return;
      }
      var texto = normaliza(a.textContent);
      if (/Cerrar Sesi|logout/i.test(texto)) {
        a.href = ROOT + 'entrar/';
        a.title = 'Maqueta — vuelve a la pantalla de acceso';
        return;
      }
      for (var i = 0; i < RUTAS.length; i++) {
        if (texto === RUTAS[i][0] || texto.slice(-RUTAS[i][0].length) === RUTAS[i][0]) {
          a.href = RUTAS[i][1].charAt(0) === '/' ? RUTAS[i][1] : ROOT + RUTAS[i][1];
          if (RUTAS[i][1] && aqui.indexOf('/' + RUTAS[i][1]) !== -1) marcaActiva(a);
          return;
        }
      }
    });

    // Acciones simuladas: el resto de href="#" no navega ni salta arriba.
    document.addEventListener('click', function (e) {
      var a = e.target.closest && e.target.closest('a[href="#"]');
      if (a) { e.preventDefault(); a.setAttribute('data-maqueta', 'inerte'); }
    });
  }

  function banner() {
    if (document.getElementById('lw-maqueta')) return;
    var d = document.createElement('div');
    d.id = 'lw-maqueta';
    d.setAttribute('role', 'note');
    d.style.cssText = 'position:fixed;bottom:14px;right:14px;z-index:var(--z-banderin,300);' +
      'background:#070907;color:#F5F0E6;border:1px solid #C89B5C;border-radius:4px;' +
      'font:600 11px/1.4 Manrope,system-ui,sans-serif;letter-spacing:.08em;' +
      'padding:7px 12px;opacity:.92;text-transform:uppercase';
    d.innerHTML = 'Maqueta v4 · datos ficticios · <a href="' + ROOT +
      '" style="color:#DFB376;text-decoration:underline">Hub</a>';
    document.body.appendChild(d);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () { recablea(); banner(); });
  } else { recablea(); banner(); }

  /* Segundo pase, solo para los dos items de administracion: espera al rol de
     la sesion (guard.js) y entonces injerta — o no injerta nada, que es la
     forma en que "visible en el nav SOLO para admin/super_admin" se cumple. */
  if (window.LW_AUTH && typeof window.LW_AUTH.then === 'function') {
    window.LW_AUTH.then(function (aut) {
      document.querySelectorAll('aside').forEach(function (aside) {
        injertaAdmin(aside, aut && aut.ficha);
      });
    });
  }
})();
