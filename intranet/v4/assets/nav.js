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
    ['Cuentas', 'cuentas/'],
    ['Equipos de venta', 'equipos-venta/'],
    ['Condiciones', 'condiciones/']
  ];

  function normaliza(t) { return (t || '').replace(/\s+/g, ' ').trim(); }

  /* Idioma ES/EN de la sidebar — 21-sep-2026 (S20). El mecanismo entero
     (idioma.js + i18n.js) es de la intranet clasica desde el 11-sep; aqui
     solo se cablea sobre el marcado que YA dibujo Stitch (par de botones
     ES/EN bajo «Idioma» en cada una de las 17 herramientas reales — las
     paginas puramente de redireccion no llevan sidebar y se quedan fuera).
     `T` cae a identidad si la pagina no cargo i18n.js (las 3 vistas
     moviles y cualquier redireccion que arrastre nav.js sin el par de
     scripts): nunca se asume que `window.lwT` existe. */
  var T = window.lwT || function (s) { return s; };

  /* Busca el par de botones "ES"/"EN" por TEXTO EXACTO, no por clase de
     Tailwind — mismo criterio que `ata()` de editores.js: el marcado de
     Stitch se repite en 17 sidebars y no hay un id comun donde colgarse.
     Recarga entera al cambiar (nunca traduccion en caliente) — mismo
     criterio que ya usa topbar.js en la clasica: una herramienta con el
     cajon abierto es mas fragil de re-traducir en vivo que perder el
     scroll. */
  var IDIOMA_ACTIVO = ['bg-deep-lagoon', 'text-on-primary'];
  var IDIOMA_INACTIVO = ['text-on-surface-variant', 'hover:text-on-surface'];
  function wireIdiomaToggle(aside) {
    if (!window.lwSetIdioma) return;               // idioma.js no cargo en esta pagina
    aside.querySelectorAll('button').forEach(function (b) {
      var t = normaliza(b.textContent);
      if (t !== 'ES' && t !== 'EN') return;
      var destino = t.toLowerCase();
      if (destino === window.LW_IDIOMA) {
        b.classList.remove.apply(b.classList, IDIOMA_INACTIVO);
        b.classList.add.apply(b.classList, IDIOMA_ACTIVO);
      } else {
        b.classList.remove.apply(b.classList, IDIOMA_ACTIVO);
        b.classList.add.apply(b.classList, IDIOMA_INACTIVO);
        b.addEventListener('click', function () {
          window.lwSetIdioma(destino);
          location.reload();
        });
      }
    });
  }

  /* Traduce lo ESTATICO compartido de la sidebar: las 4 cabeceras de grupo
     (+ «Panel de control», injertada aparte — ver mas abajo), la etiqueta
     de cada herramienta (RUTAS/INJERTOS ya dejaron el texto en español
     antes de que esto corra) y «Cerrar Sesión». Nunca antes de
     `recablea()`: esta necesita el texto español para casar `RUTAS` por
     texto, y traducir primero lo dejaria ciego. */
  // Traduce los enlaces (icono + etiqueta) de CUALQUIER contenedor — toda la
  // sidebar, o solo el grupo recien injertado (ver el pase de LW_AUTH.then
  // mas abajo: re-escanear los 14-17 enlaces ya traducidos en cada pagina
  // con sesion iniciada era trabajo de sobra por los 3-4 nuevos).
  function traduceEnlaces(scope) {
    scope.querySelectorAll('a').forEach(function (a) {
      var spans = a.querySelectorAll('span');
      if (spans.length < 2) return;
      var etiqueta = spans[spans.length - 1];        // spans[0] es la ligadura del icono
      etiqueta.textContent = T(normaliza(etiqueta.textContent));
    });
  }

  function traduceSidebar(aside) {
    if (!window.lwT) return;
    aside.querySelectorAll('nav > div > span').forEach(function (sp) {
      sp.textContent = T(normaliza(sp.textContent));
    });
    traduceEnlaces(aside);
    aside.querySelectorAll('span').forEach(function (sp) {
      if (normaliza(sp.textContent) === 'Idioma') sp.textContent = T('Idioma');
    });
  }

  /* «Buscar»/«Notificaciones» del header (fuera del aside, uno por pagina). */
  function traduceHeader() {
    if (!window.lwT) return;
    document.querySelectorAll('header button[title]').forEach(function (b) {
      b.title = T(b.title);
    });
  }

  function marcaActiva(a) {
    a.setAttribute('aria-current', 'page');
    // píldora activa de la cáscara canónica (creatividades, 3-sep-2026)
    a.classList.remove('text-on-surface-variant');
    a.classList.add('bg-primary-container', 'text-on-primary', 'font-bold');
  }

  /* Herramientas que NO existen en el diseno de Stitch: nacieron despues de la
     descarga (Modelos el 7-sep; CRM y Solicitudes/Comisiones ya estaban vivas
     en /intranet/ y la maqueta se habia quedado atras). Sus items de menu se
     INYECTAN aqui en vez de anadirlos a mano en las 22 sidebars: la cascara
     esta duplicada por ser maqueta, pero la navegacion no — una lista copiada
     en dos sitios ES el bug, y con 22 copias la siguiente herramienta se
     olvidaria en alguna.
     El orden y el grupo salen de `contracts/assets/herramientas.js`, que es la
     fuente unica del catalogo vivo: cada uno se cuelga detras de su vecino de
     alli (CRM abre Seguimiento -> tras Home; Comisiones (antes «Solicitudes»,
     renombrada 14-sep) cierra Administracion -> tras Recibos). Cuentas ya NO
     va aqui desde el 15-sep: se movio a la seccion "Panel de control", ver
     mas abajo — visible siempre para cualquier sesion nunca fue correcto,
     el propio catalogo la marca `soloAdmin:true`. */
  var INJERTOS = [
    { path: 'leads',      tras: 'home',     icono: 'person_search',  texto: 'CRM',
      href: '/intranet/leads/' },   // vista propia: sale de la v4
    /* Asistente de respuestas (22-sep-2026, S5 de
       encargos/20260922_lawang_bot_apoyo_agentes.md): tras Contratos, en
       Documentación, como en herramientas.js. OJO: este fichero NO lee el
       catálogo (pese a lo que dice el comentario de arriba, RUTAS e INJERTOS
       son listas propias) — una tarjeta nueva en herramientas.js sale en el
       hub y en la barra clásica, pero en esta sidebar solo si se injerta
       aquí. Y SOLO aquí: una fila en RUTAS no hace falta (el clon lleva
       data-path y recablea() lo resuelve por esa rama, nunca por texto —
       code-review, 22-sep). Se deja dicho para que la próxima herramienta
       no se quede fuera. */
    { path: 'asistente',  tras: 'contratos', icono: 'smart_toy',     texto: 'Asistente' },
    { path: 'comisiones', tras: 'recibos',  icono: 'request_quote',  texto: 'Comisiones' }
  ];

  /* "Panel de control" (15-sep-2026, encargo del owner): seccion nueva del
     menu, admin/super_admin solamente, para las herramientas de
     configuracion de la intranet — Usuarios, Cuentas, Equipos de venta,
     Condiciones. Usuarios se quedo fuera del 15 al 22-sep (el owner la queria
     separada por ser la que mas se toca); el 22-sep pidio llevarsela dentro:
     va la PRIMERA del grupo, y no se clona — se MUEVE el enlace que Stitch
     dibujo en "Base de Datos", asi conserva su data-path, su traduccion y su
     marca de activo del primer pase.
     Stitch nunca dibujo esta seccion, asi que no hay cabecera+enlaces que
     clonar de uno en uno como en INJERTOS de arriba: `injertaPanelControl`
     construye el grupo entero (cabecera incluida) clonando el div de "Base
     de Datos" (vacio) y su span de cabecera, y cuelga los tres enlaces
     dentro. Mismo criterio de rol que `es_admin()` en la base
     (`ficha.rol IN ('admin','super_admin')`) — es la puerta del menu, la de
     verdad la pone la RLS de las tablas que tocan. Solo se sabe el rol de la
     sesion tras `window.LW_AUTH` (guard.js), que resuelve DESPUES del primer
     pase sincrono — por eso corre en un segundo pase, igual que antes. */
  var PANEL_CONTROL = [
    { path: 'cuentas',       icono: 'account_balance', texto: 'Cuentas' },
    { path: 'equipos-venta', icono: 'groups',           texto: 'Equipos de venta' },
    { path: 'condiciones',   icono: 'percent',          texto: 'Condiciones' },
    /* Ajustes (22-sep-2026, owner: «en el panel de control podemos controlar
       los días de gracia, las prórrogas, los techos, todo lo configurable»):
       la tabla `parametros`. Lo ve cualquier admin; escribir exige super admin
       en la base (parametro_set), como Cuentas. */
    { path: 'ajustes',       icono: 'tune',             texto: 'Ajustes' }
  ];

  /* La comision de administracion va aparte del resto del Panel de control:
     aquellas tres las ve cualquier admin, y esta SOLO el super admin, porque
     abre lo que el estudio le cobra al cliente. Se configura aqui y no en
     «Comisiones» — aquella es la del equipo de ventas, y son dos cosas
     distintas que comparten palabra. */
  var PANEL_CONTROL_SUPER = [
    { path: 'comision-admin', icono: 'price_change',      texto: 'Comisión de administración' },
    { path: 'sociedades',     icono: 'domain',             texto: 'Sociedades emisoras' }
  ];

  /* Documentacion se fusiono dentro de Proyectos (owner, 8-sep): la pestana
     desaparece de la v4. Se oculta desde aqui — un solo fichero — en vez de
     editar 22 sidebars; el fichero de la pantalla queda como redireccion. */
  function retiraDocumentacion(aside) {
    var a = aside.querySelector('[data-path="documentacion"]');
    if (a) a.style.display = 'none';
  }

  /* Un solo injertador para los tres casos. Clona el enlace vecino para
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
  function esSuperSesion(ficha) { return !!ficha && ficha.rol === 'super_admin'; }

  /* Construye la seccion "Panel de control" entera (cabecera + 3 enlaces) y
     la cuelga justo detras del grupo que contiene "Usuarios" ("Base de
     Datos" en el diseno de Stitch) — mismo sitio donde vivian Cuentas/
     Equipos de venta/Condiciones antes del 15-sep, solo que ahora con
     cabecera propia en vez de ir sueltas dentro de ese grupo. */
  function injertaPanelControl(aside, ficha) {
    if (!esAdminSesion(ficha)) return;
    if (aside.querySelector('[data-seccion="panel-control"]')) return;
    var ancla = aside.querySelector('[data-path="usuarios"]');
    var grupo = ancla && ancla.parentElement;
    var cabecera = grupo && grupo.querySelector('span');
    if (!ancla || !grupo || !cabecera) return;   // sin plantilla no hay de donde clonar

    var aqui = location.pathname;
    var nuevoGrupo = grupo.cloneNode(false);      // mismo div vacio, mismas clases Tailwind
    nuevoGrupo.setAttribute('data-seccion', 'panel-control');
    var nuevaCabecera = cabecera.cloneNode(true);
    nuevaCabecera.textContent = 'Panel de control';
    nuevoGrupo.appendChild(nuevaCabecera);
    nuevoGrupo.appendChild(ancla);                // appendChild MUEVE Usuarios: sale de "Base de Datos"

    PANEL_CONTROL.concat(esSuperSesion(ficha) ? PANEL_CONTROL_SUPER : []).forEach(function (spec) {
      var a = ancla.cloneNode(true);              // clon de "Usuarios": hereda las clases exactas
      a.setAttribute('data-path', spec.path);
      a.removeAttribute('aria-current');
      var spans = a.querySelectorAll('span');
      if (spans.length < 2) return;
      spans[0].textContent = spec.icono;
      spans[1].textContent = spec.texto;
      a.href = ROOT + spec.path + '/';
      if (aqui.indexOf('/' + spec.path + '/') !== -1) marcaActiva(a);
      nuevoGrupo.appendChild(a);
    });

    grupo.insertAdjacentElement('afterend', nuevoGrupo);
    return nuevoGrupo;
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

    // Idioma: SIEMPRE despues del bucle de arriba — traduceSidebar reescribe
    // el textContent que ese bucle necesita en español para casar RUTAS.
    document.querySelectorAll('aside').forEach(function (aside) {
      wireIdiomaToggle(aside);
      traduceSidebar(aside);
    });
    traduceHeader();
    // El marcado ESTATICO propio de cada pantalla (comision-admin, 48
    // `data-lwt`; el que se vaya marcando en el resto) no lo toca lo de
    // arriba — eso es solo la sidebar. Sin esta llamada, `data-lwt` es
    // decoracion muerta: nadie lo lee. i18n.js no la carga ninguna pagina
    // clasica tampoco (ahi la pone topbar.js) — aqui no hay topbar.js.
    if (window.lwIdiomaAplicar) window.lwIdiomaAplicar();

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
    d.innerHTML = T('Maqueta v4 · datos ficticios') + ' · <a href="' + ROOT +
      '" style="color:#DFB376;text-decoration:underline">Hub</a>';
    document.body.appendChild(d);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () { recablea(); banner(); });
  } else { recablea(); banner(); }

  /* Segundo pase, solo para "Panel de control": espera al rol de la sesion
     (guard.js) y entonces injerta la seccion entera — o no injerta nada, que
     es la forma en que "visible en el nav SOLO para admin/super_admin" se
     cumple. */
  if (window.LW_AUTH && typeof window.LW_AUTH.then === 'function') {
    window.LW_AUTH.then(function (aut) {
      document.querySelectorAll('aside').forEach(function (aside) {
        // «Panel de control» nace DESPUES del primer traduceSidebar (este
        // pase espera a LW_AUTH) — sin traducir el grupo nuevo se queda en
        // español aunque el resto de la sidebar ya este en ingles. Se
        // traduce SOLO `nuevoGrupo` (code-review, 21-sep): volver a barrer
        // los 14-17 enlaces ya traducidos en cada carga con sesion no
        // cambia nada que ya no estuviera en ingles, solo trabajo de mas.
        var nuevoGrupo = injertaPanelControl(aside, aut && aut.ficha);
        if (!nuevoGrupo || !window.lwT) return;
        var cabecera = nuevoGrupo.querySelector('span');
        if (cabecera) cabecera.textContent = T(normaliza(cabecera.textContent));
        traduceEnlaces(nuevoGrupo);
      });
    });
  }
})();
