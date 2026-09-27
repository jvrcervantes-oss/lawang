/* nav-montaje.js — el menú lateral de la v4 para una página que NO lo trae
 * dibujado (23-sep-2026).
 *
 * `nav.js` no crea el menú: RECABLEA el `<aside>` que Stitch dibujó en cada
 * una de las 22 pantallas de la v4 (rutas, injertos, poda por permiso, idioma,
 * cerrar sesión). El generador de contratos (`contracts/app.html`) es la
 * primera página con cara v4 que no viene de Stitch, así que no tiene ese
 * `<aside>`. Este fichero lo MONTA con la misma estructura
 * (aside > nav > div > span + a[data-path] > span icono + span texto) y
 * `nav.js` hace después con él exactamente lo mismo que con los otros 22:
 * ninguna ruta ni ninguna regla de permiso se escribe aquí.
 *
 * Diferencias a propósito con las 22 páginas de Stitch:
 * · Clases propias (`lw4-sb…`), no Tailwind: ni app.html ni el CRM cargan
 *   Tailwind. Su preflight reescribiría la piel propia de cada una. El aspecto
 *   vive en `intranet/v4/assets/nav-montaje.css`, entero bajo `html.v4`.
 * · DOS MODOS, según la página:
 *   - el generador (contracts/app.html): menú plegado por defecto que se abre
 *     por encima con ☰ — la vista de trabajo a ancho completo que decidió el
 *     owner (23-sep): el editor no cabe junto a una barra fija de 288 px;
 *   - el CRM (/intranet/leads/, 27-sep-2026, owner: «que el menú y top bar sean
 *     los de la v4 y nada más») y, el mismo día, Obra, el editor de piezas
 *     (creatividades/redes/) y el de dossiers: `html.lw4-fijo`, menú FIJO de 288 px y
 *     CABECERA fija de 64 px (buscador, campana y usuario), como las pantallas
 *     nativas de la v4; por debajo de 1024 px el menú vuelve a ser el cajón y
 *     lo abre la hamburguesa de la cabecera. La cabecera la monta este fichero;
 *     la lupa la cablea nav.js, y la campana y el usuario, cabecera.js.
 *
 * Inerte sin `html.v4` (en el generador lo pone `contracts/assets/piel.js`; el
 * CRM lo lleva escrito en su <html>). Se carga con `defer` ANTES que nav.js:
 * los `defer` corren en orden, y nav.js recablea en cuanto corre. */
(function () {
  'use strict';
  var html = document.documentElement;
  if (!html.classList.contains('v4')) return;
  if (document.querySelector('aside.lw4-sb')) return;       // idempotente
  var fijo = html.classList.contains('lw4-fijo');
  // mismo corte que maqueta.js + shell.css en las pantallas nativas
  var ancho = window.matchMedia ? window.matchMedia('(min-width:1024px)') : { matches: false };
  function aLaVista() { return fijo && ancho.matches; }

  // Lo que Stitch dibujó en las 22 sidebars (grupos, iconos y data-path). El
  // resto (Modelos, CRM, Asistente, Comisiones, Reservas, Panel de control) lo
  // injerta nav.js, como en cualquier otra pantalla.
  var GRUPOS = [
    ['Seguimiento', [['home', 'dashboard', 'Home'], ['operaciones', 'sync_alt', 'Operaciones'],
                     ['soporte', 'support_agent', 'Soporte'], ['vencimientos', 'event_busy', 'Vencimientos']]],
    ['Documentación', [['contratos', 'history_edu', 'Contratos'], ['creatividades', 'palette', 'Creatividades'],
                       ['documentacion', 'folder', 'Documentación']]],
    ['Administración', [['facturas', 'receipt_long', 'Facturas'], ['recibos', 'payments', 'Recibos']]],
    ['Base de Datos', [['proyectos', 'apartment', 'Proyectos'], ['obra', 'foundation', 'Obra'],
                       ['compradores', 'badge', 'Clientes'], ['usuarios', 'group', 'Usuarios']]]
  ];

  function enlace(p) {
    return '<a class="lw4-sb-a" data-path="' + p[0] + '" href="#">' +
      '<span class="material-symbols-outlined">' + p[1] + '</span><span>' + p[2] + '</span></a>';
  }

  var aside = document.createElement('aside');
  aside.className = 'lw4-sb';
  aside.id = 'lw4-sb';
  aside.setAttribute('aria-label', 'Menú de la intranet');
  aside.setAttribute('aria-hidden', 'true');
  aside.innerHTML =
    '<div class="lw4-sb-arriba">' +
      '<div class="lw4-sb-marca"><div><span class="lw4-sb-logo" data-lw-ficha="cabecera"></span>' +
        '<span class="lw4-sb-sub" data-lw-ficha="subcabecera"></span></div>' +
        '<button type="button" class="lw4-sb-cerrar" data-lw4-cerrar aria-label="Cerrar menú">' +
        '<span class="material-symbols-outlined">left_panel_close</span></button></div>' +
      '<nav class="lw4-sb-nav">' + GRUPOS.map(function (g) {
        return '<div class="lw4-sb-g"><span class="lw4-sb-gt">' + g[0] + '</span>' + g[1].map(enlace).join('') + '</div>';
      }).join('') + '</nav>' +
    '</div>' +
    '<div class="lw4-sb-pie">' +
      '<div class="lw4-sb-idioma"><span>Idioma</span><div class="lw4-sb-seg">' +
        '<button type="button">ES</button><button type="button">EN</button></div></div>' +
      enlace(['login', 'logout', 'Cerrar Sesión']) +
    '</div>';

  /* La herramienta activa: nav.js la marca por la RUTA (/intranet/v4/<x>/), y
     esta página vive fuera de la v4. La declara la propia página en el <html>
     (`data-lw4-herramienta="contratos"` en app.html). El CRM no se resuelve
     aquí: su entrada la injerta nav.js después, y la marca nav.js (injerta). */
  var activa = html.getAttribute('data-lw4-herramienta');
  var enlaceActivo = activa && aside.querySelector('[data-path="' + activa + '"]');
  if (enlaceActivo) enlaceActivo.setAttribute('aria-current', 'page');

  var velo = document.createElement('div');
  velo.className = 'lw4-velo';
  velo.setAttribute('data-lw4-cerrar', '');

  /* LA CABECERA (solo modo fijo). Misma estructura que la que dibujó Stitch en
     las pantallas v4, que es la que leen los demás: nav.js cablea el botón cuyo
     icono es `search` y traduce los `title` de `header button`; cabecera.js
     pinta `[data-lw="k-avisos"]` (dentro de su botón), `[data-lw-user]` y
     `[data-lw-rol]`. Ningún nombre de persona en el HTML: lo pone la sesión. */
  var cab = null;
  if (fijo) {
    cab = document.createElement('header');
    cab.className = 'lw4-cab';
    cab.innerHTML =
      '<div class="lw4-cab-izq">' +
        '<button type="button" class="lw4-cab-btn lw4-cab-menu" data-lw4-menu aria-controls="lw4-sb" aria-label="Menú">' +
          '<span class="material-symbols-outlined">menu</span></button>' +
      '</div>' +
      '<div class="lw4-cab-der">' +
        '<button type="button" class="lw4-cab-btn" title="Buscar"><span class="material-symbols-outlined">search</span></button>' +
        '<button type="button" class="lw4-cab-btn" title="Notificaciones"><span class="material-symbols-outlined">notifications</span>' +
          '<span class="lw4-cab-n" data-lw="k-avisos">—</span></button>' +
        '<div class="lw4-cab-yo"><div class="lw4-cab-quien">' +
          '<span class="lw4-cab-nom" data-lw-user></span><span class="lw4-cab-rol" data-lw-rol>—</span></div>' +
          '<div class="lw4-cab-ava" aria-hidden="true"><span class="material-symbols-outlined">person</span></div></div>' +
      '</div>';
  }

  // Primero del <body>: nav.js y su buscador toman `document.querySelector('aside')`,
  // y la página puede traer los suyos (el CRM: la ficha del bot, `#waFicha`).
  function monta() {
    if (cab) document.body.insertBefore(cab, document.body.firstChild);
    document.body.insertBefore(velo, document.body.firstChild);
    document.body.insertBefore(aside, document.body.firstChild);
  }
  if (document.body) monta(); else document.addEventListener('DOMContentLoaded', monta);

  // La marca de la barra sale de la ficha de la instancia (F3 2b, 26-sep-2026), no del código.
  var ficha = window.LW_INSTANCIA || {};
  aside.querySelectorAll('[data-lw-ficha]').forEach(function (el) {
    el.textContent = ficha[el.getAttribute('data-lw-ficha')] || '';
  });

  var volverA = null;
  function abre() {
    if (aLaVista()) return;                                  // ya está a la vista
    volverA = document.activeElement;
    html.classList.add('lw4-sb-abierto');
    aside.setAttribute('aria-hidden', 'false');
    var primero = aside.querySelector('a[href]:not([href="#"]), button');
    if (primero) primero.focus();
  }
  function cierra() {
    if (!html.classList.contains('lw4-sb-abierto')) return;
    html.classList.remove('lw4-sb-abierto');
    aside.setAttribute('aria-hidden', 'true');
    if (volverA && volverA.focus) volverA.focus();
  }
  // Delegado: cualquier [data-lw4-menu] de la página abre (el ☰ de la cabecera
  // v4 llega en la fase 3; mientras, uno provisional abajo).
  document.addEventListener('click', function (e) {
    var t = e.target.closest ? e.target : e.target.parentElement;
    if (!t) return;
    if (t.closest('[data-lw4-menu]')) { e.preventDefault(); abre(); }
    else if (t.closest('[data-lw4-cerrar]')) { e.preventDefault(); cierra(); }
  });
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') cierra(); });

  /* Modo fijo: a partir de 1024 px el menú está a la vista (ni velo ni
     aria-hidden, que ocultaría a un lector de pantalla un menú visible); por
     debajo es el cajón de siempre. Al cruzar el corte con el cajón abierto se
     cierra, para no dejar el velo encima de la página. */
  function ajustaFijo() {
    html.classList.remove('lw4-sb-abierto');
    aside.setAttribute('aria-hidden', aLaVista() ? 'false' : 'true');
  }
  if (fijo) {
    ajustaFijo();
    if (ancho.addEventListener) ancho.addEventListener('change', ajustaFijo);
    else if (ancho.addListener) ancho.addListener(ajustaFijo);
    /* Usuario y campana, cuando se sabe quién es (guard.js). */
    if (window.LW_AUTH && typeof window.LW_AUTH.then === 'function') {
      window.LW_AUTH.then(function (aut) {
        if (!aut) return;
        if (!window.LW_CABECERA) { console.error('[nav-montaje] falta intranet/v4/assets/cabecera.js: sin campana ni usuario'); return; }
        window.LW_CABECERA.pintaUsuario(aut);
        window.LW_CABECERA.campana(aut, (aut.ficha && aut.ficha.rol) || '');
      });
    }
  }

  /* ☰ PROVISIONAL (fase 2): mientras la cabecera v4 no exista, se cuelga al
     principio de la barra clásica. La fase 3 la sustituye por la cabecera de
     una fila y este bloque se va. */
  function boton() {
    if (document.querySelector('[data-lw4-menu]')) return;
    var barra = document.querySelector('.lw-topbar');
    if (!barra) return;
    var b = document.createElement('button');
    b.type = 'button';
    b.className = 'lw4-hamburguesa';
    b.setAttribute('data-lw4-menu', '');
    b.setAttribute('aria-controls', 'lw4-sb');
    b.setAttribute('aria-label', 'Abrir menú');
    b.innerHTML = '<span class="material-symbols-outlined">menu</span>';
    barra.insertBefore(b, barra.firstChild);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boton); else boton();

  window.LW_NAV4 = { abre: abre, cierra: cierra };
})();
