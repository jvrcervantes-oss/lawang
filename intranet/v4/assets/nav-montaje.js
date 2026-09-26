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
 * · Clases propias (`lw4-sb…`), no Tailwind: app.html no carga Tailwind. Su
 *   preflight reescribiría la cara clásica, que tiene que seguir intacta. El
 *   aspecto vive en `contracts/assets/suite-v4-generador.css`, entero bajo
 *   `html.v4`.
 * · Plegado por defecto y se abre por encima con ☰: es la vista de trabajo a
 *   ancho completo que decidió el owner (23-sep). El editor no cabe junto a
 *   una barra fija de 288 px.
 *
 * Inerte sin `html.v4` (lo pone `contracts/assets/piel.js`). Se carga con
 * `defer` ANTES que nav.js: los `defer` corren en orden, y nav.js recablea en
 * cuanto corre. */
(function () {
  'use strict';
  var html = document.documentElement;
  if (!html.classList.contains('v4')) return;
  if (document.querySelector('aside.lw4-sb')) return;       // idempotente

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
                       ['compradores', 'badge', 'Compradores'], ['usuarios', 'group', 'Usuarios']]]
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
     (`data-lw4-herramienta="contratos"` en app.html). */
  var activa = html.getAttribute('data-lw4-herramienta');
  var enlaceActivo = activa && aside.querySelector('[data-path="' + activa + '"]');
  if (enlaceActivo) enlaceActivo.setAttribute('aria-current', 'page');

  var velo = document.createElement('div');
  velo.className = 'lw4-velo';
  velo.setAttribute('data-lw4-cerrar', '');

  // Primero del <body>: nav.js y su buscador toman `document.querySelector('aside')`
  // y el panel de usuario de topbar.js también es un <aside> (llega después).
  function monta() {
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
