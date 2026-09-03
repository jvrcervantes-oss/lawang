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
    ['Home', ''],
    ['Operaciones', 'operaciones/'],
    ['Soporte', 'soporte/'],
    ['Vencimientos', 'vencimientos/'],
    ['Contratos', 'contratos/'],
    ['Creatividades', 'creatividades/'],
    ['Documentación', 'documentacion/'],
    ['Facturas', 'facturas/'],
    ['Recibos', 'recibos/'],
    ['Proyectos', 'proyectos/'],
    ['Obra', 'obra/'],
    ['Compradores', 'compradores/'],
    ['Usuarios', 'usuarios/']
  ];

  function normaliza(t) { return (t || '').replace(/\s+/g, ' ').trim(); }

  function recablea() {
    var aqui = location.pathname;
    document.querySelectorAll('aside a[href="#"], nav a[href="#"]').forEach(function (a) {
      var texto = normaliza(a.textContent);
      if (/Cerrar Sesi|logout/i.test(texto)) {
        a.title = 'Maqueta — sin sesión real';
        a.setAttribute('data-maqueta', 'inerte');
        return;
      }
      for (var i = 0; i < RUTAS.length; i++) {
        if (texto === RUTAS[i][0] || texto.slice(-RUTAS[i][0].length) === RUTAS[i][0]) {
          a.href = ROOT + RUTAS[i][1];
          if (RUTAS[i][1] && aqui.indexOf('/' + RUTAS[i][1]) !== -1) {
            a.setAttribute('aria-current', 'page');
            a.style.outline = '1px solid rgba(200,155,92,.6)';
            a.style.outlineOffset = '-1px';
          }
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
    d.style.cssText = 'position:fixed;bottom:14px;right:14px;z-index:9999;' +
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
})();
