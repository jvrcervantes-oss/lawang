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
    ['Usuarios', 'usuarios/']
  ];

  function normaliza(t) { return (t || '').replace(/\s+/g, ' ').trim(); }

  function marcaActiva(a) {
    a.setAttribute('aria-current', 'page');
    // píldora activa de la cáscara canónica (creatividades, 3-sep-2026)
    a.classList.remove('text-on-surface-variant');
    a.classList.add('bg-primary-container', 'text-on-primary', 'font-bold');
  }

  /* Modelos no existe en el diseno de Stitch: la herramienta nacio el 7-sep-2026,
     despues de la descarga, y su pantalla la construyo el estudio con los tokens
     del sistema. El item de menu se INYECTA aqui en vez de anadirlo a mano en las
     19 sidebars: la cascara esta duplicada por ser maqueta, pero la navegacion no
     — una lista copiada en dos sitios ES el bug, y con 19 copias la siguiente
     herramienta se olvidaria en alguna. Se cuelga detras de Proyectos, que es
     donde va en la suite viva (herramientas.js). */
  function injertaModelos(aside) {
    if (aside.querySelector('[data-path="modelos"]')) return;
    var ancla = aside.querySelector('[data-path="proyectos"]');
    if (!ancla) return;                       // sin Proyectos no hay donde colgarlo
    var a = ancla.cloneNode(true);            // clon: hereda las clases exactas
    a.setAttribute('data-path', 'modelos');
    a.removeAttribute('aria-current');
    var spans = a.querySelectorAll('span');
    if (spans.length < 2) return;
    spans[0].textContent = 'villa';           // ligadura de material-symbols
    spans[1].textContent = 'Modelos';
    ancla.insertAdjacentElement('afterend', a);
  }

  function recablea() {
    var aqui = location.pathname;
    document.querySelectorAll('aside').forEach(injertaModelos);
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
          a.href = ROOT + RUTAS[i][1];
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
