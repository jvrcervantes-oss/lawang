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

  /* CORTINA DE PRIVACIDAD (23-sep-2026, owner: «que pida una contraseña y
     cuando pasen 15 segundos sin uso vuelva a pedirla»). Pantalla -> segundos
     sin uso antes de volver a taparse. La cortina vive en assets/cortina.js;
     aquí solo se decide dónde se pone. Un fondo opaco se pone YA, en este
     mismo instante, para que no se vea nada mientras llega cortina.js (que lo
     sustituye por la suya). Sube CORTINA_V al cambiar cortina.js: no la sella
     sella_assets, que solo recorre las etiquetas de los HTML. */
  var CORTINA = { 'comision-admin': 15 };
  var CORTINA_V = '20260923b';
  (function () {
    var seg = location.pathname.replace(/\/(index\.html)?$/, '').split('/').pop();
    if (!CORTINA[seg]) return;
    var pre = document.createElement('div');
    pre.id = 'lw-cortina-pre';
    pre.style.cssText = 'position:fixed;inset:0;z-index:2147483000;background:#0F2E30';
    (document.body || document.documentElement).appendChild(pre);
    var sc = document.createElement('script');
    sc.src = ROOT + 'assets/cortina.js?v=' + CORTINA_V;
    sc.setAttribute('data-segundos', String(CORTINA[seg]));
    document.head.appendChild(sc);
  })();

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
    { path: 'comisiones', tras: 'recibos',  icono: 'request_quote',  texto: 'Comisiones' },
    /* Reservas por vencer (23-sep-2026, owner, alta prioridad): Cartas de
       Reserva vivas y cuándo vencen. En Seguimiento, tras Vencimientos. */
    { path: 'reservas',   tras: 'vencimientos', icono: 'event_upcoming', texto: 'Reservas' }
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
    /* Reparto de equipo (23-sep-2026, owner): lo generado para cada closer y qué
       ha pagado el manager. Pantalla propia para el panel «Mi equipo». */
    { path: 'reparto',       icono: 'payments',         texto: 'Reparto de equipo' },
    /* Ajustes (22-sep-2026, owner: «en el panel de control podemos controlar
       los días de gracia, las prórrogas, los techos, todo lo configurable»):
       la tabla `parametros`. Lo ve cualquier admin; escribir exige super admin
       en la base (parametro_set), como Cuentas. */
    { path: 'ajustes',       icono: 'tune',             texto: 'Ajustes' },
    /* Comunicación (23-sep-2026, owner: «algo como "Comunicación" para
       escribir yo las plantillas y que se manden a los agentes»): comunicados
       por email al equipo. Admin; la puerta real es es_admin() en
       comunicados/comunicado_encolar. */
    { path: 'comunicacion',  icono: 'campaign',         texto: 'Comunicación' }
  ];

  /* La comision de administracion va aparte del resto del Panel de control:
     aquellas tres las ve cualquier admin, y esta SOLO el super admin, porque
     abre lo que el estudio le cobra al cliente. Se configura aqui y no en
     «Comisiones» — aquella es la del equipo de ventas, y son dos cosas
     distintas que comparten palabra. */
  /* Lo que un SALES MANAGER ve del Panel de control (23-sep-2026, owner: «los
     sales manager deben tener acceso a dar de alta su equipo de ventas +
     condiciones a ellos»). Solo su equipo: la puerta de la página es
     `data-rol="admin sales_manager"` y la de los datos, la base (RPC
     equipo_miembro_* y policies «el manager configura a sus closers»).
     catalogo.test exige que cada una de estas páginas nombre sales_manager. */
  var PANEL_MANAGER = ['equipos-venta', 'condiciones', 'reparto'];

  var PANEL_CONTROL_SUPER = [
    { path: 'comision-admin', icono: 'price_change',      texto: 'Comisión de administración' },
    { path: 'sociedades',     icono: 'domain',             texto: 'Sociedades emisoras' }
  ];

  /* MENÚ POR PERMISO (S17, 23-sep-2026). Hasta hoy la sidebar enseñaba las 17
     herramientas a todo el mundo y la puerta la ponía guard.js al entrar: un
     agente sin Compradores pulsaba «Compradores» y rebotaba al hub. Ahora el
     menú solo ofrece lo que la página dejaría abrir.
     · La regla es la de `lwPermitida` (contracts/assets/herramientas.js) y la
       de guard.js: solo el super admin ve todo; admin y agente pasan por su
       lista `ficha.herramientas`. Sin ficha (guard no la pudo leer) no se
       poda nada, como lwPermitida — la RLS sigue protegiendo los datos.
     · El mapa copia el `data-herramienta` que cada página v4 declara a guard.js
       (y, en las que son redirección — leads, creatividades —, la clave de la
       herramienta viva a la que llevan). `nav.test.js` falla si una página v4
       y este mapa dejan de coincidir: no se sincroniza a ojo.
     · Sin clave = sin poda: Home, y las del Panel de control que ya gobierna
       el rol (equipos-venta, condiciones, ajustes, comision-admin,
       sociedades). Usuarios y Cuentas SÍ llevan clave: además de admin, hace
       falta tenerlas asignadas, como en el hub vivo. */
  var CLAVE_MENU = {
    leads: 'leads', operaciones: 'operaciones', soporte: 'soporte', vencimientos: 'vencimientos',
    contratos: 'contratos', asistente: 'asistente', creatividades: ['dossier', 'creatividades'],
    facturas: 'facturas', recibos: 'recibos', comisiones: 'comisiones', reservas: 'reservas',
    proyectos: 'unidades', modelos: 'modelos', obra: 'obra', compradores: 'compradores',
    usuarios: 'usuarios', cuentas: 'cuentas'
  };
  function puedeVer(path, ficha) {
    var k = CLAVE_MENU[path];
    if (!k || !ficha || ficha.rol === 'super_admin') return true;
    return [].concat(k).some(function (h) { return (ficha.herramientas || []).indexOf(h) !== -1; });
  }
  function podaMenu(aside, ficha) {
    aside.querySelectorAll('a[data-path]').forEach(function (a) {
      if (!puedeVer(a.getAttribute('data-path'), ficha)) a.style.display = 'none';
    });
    // un grupo sin ningún enlace visible se va entero, cabecera incluida
    aside.querySelectorAll('nav > div').forEach(function (g) {
      var enlaces = g.querySelectorAll('a[data-path]');
      if (!enlaces.length) return;
      var alguno = Array.prototype.some.call(enlaces, function (a) { return a.style.display !== 'none'; });
      g.style.display = alguno ? '' : 'none';
    });
  }

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
  function esManagerVentas(ficha) { return !!ficha && ficha.rol === 'sales_manager'; }

  /* Construye la seccion "Panel de control" entera (cabecera + 3 enlaces) y
     la cuelga justo detras del grupo que contiene "Usuarios" ("Base de
     Datos" en el diseno de Stitch) — mismo sitio donde vivian Cuentas/
     Equipos de venta/Condiciones antes del 15-sep, solo que ahora con
     cabecera propia en vez de ir sueltas dentro de ese grupo. */
  function injertaPanelControl(aside, ficha) {
    var soloManager = !esAdminSesion(ficha) && esManagerVentas(ficha);
    if (!esAdminSesion(ficha) && !soloManager) return;
    if (aside.querySelector('[data-seccion="panel-control"]')) return;
    var ancla = aside.querySelector('[data-path="usuarios"]');
    var grupo = ancla && ancla.parentElement;
    var cabecera = grupo && grupo.querySelector('span');
    if (!ancla || !grupo || !cabecera) return;   // sin plantilla no hay de donde clonar

    var aqui = location.pathname;
    var nuevoGrupo = grupo.cloneNode(false);      // mismo div vacio, mismas clases Tailwind
    nuevoGrupo.setAttribute('data-seccion', 'panel-control');
    var nuevaCabecera = cabecera.cloneNode(true);
    // el sales manager ve «Mi equipo»: para él es su panel, no el de la empresa
    nuevaCabecera.textContent = soloManager ? 'Mi equipo' : 'Panel de control';
    nuevoGrupo.appendChild(nuevaCabecera);
    nuevoGrupo.appendChild(ancla);                // appendChild MUEVE Usuarios: sale de "Base de Datos"

    PANEL_CONTROL.concat(esSuperSesion(ficha) ? PANEL_CONTROL_SUPER : []).filter(function (spec) {
      return !soloManager || PANEL_MANAGER.indexOf(spec.path) !== -1;
    }).forEach(function (spec) {
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
        if (dp === 'login') { cableaSalir(a); return; }
        if (aqui.indexOf('/' + ruta) !== -1) marcaActiva(a);
        return;
      }
      var texto = normaliza(a.textContent);
      if (/Cerrar Sesi|logout/i.test(texto)) { cableaSalir(a); return; }
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

  /* «Cerrar sesión» (S17, 23-sep-2026). Llevaba a `v4/entrar/`, que redirige
     al login de la intranet… con la sesión VIVA: quien pulsaba «Cerrar sesión»
     seguía dentro al volver. Ahora cierra la sesión de verdad y va a la puerta
     única, igual que el panel de usuario de la intranet de siempre (topbar.js). */
  function cableaSalir(a) {
    a.href = '/intranet/';
    a.title = T('Cerrar sesión');
    if (a._lwSalir) return;
    a._lwSalir = true;
    a.addEventListener('click', function (ev) {
      ev.preventDefault();
      var fuera = function () { location.replace('/intranet/'); };
      if (!window.LW_AUTH || typeof window.LW_AUTH.then !== 'function') return fuera();
      window.LW_AUTH.then(function (aut) { return aut.sb.auth.signOut(); }).then(fuera, fuera);
    });
  }

  /* BUSCADOR DE HERRAMIENTAS (S17, 23-sep-2026). La lupa de la cabecera solo
     avisaba «disponible en la fase de cableado». Busca entre los enlaces que
     el menú lateral YA enseña a esta sesión (después de la poda por permiso):
     no hay segunda lista, y nunca ofrece una herramienta que la puerta
     rebotaría. Enter abre la primera; Escape o pulsar fuera cierra. Navega al
     `href` del propio enlace, nunca a nada montado con lo tecleado. */
  function cableaBuscador() {
    /* Por el ICONO, no por el `title`: `traduceHeader()` corre antes y en
       inglés lo cambia a «Search» — por el title la lupa quedaba sin cablear
       justo en la sesión EN (Desarrollo, consulta de deploy S17). */
    var lupa = null;
    document.querySelectorAll('header button').forEach(function (b) {
      var ic = b.querySelector('.material-symbols-outlined');
      if (!lupa && ic && ic.textContent.trim() === 'search') lupa = b;
    });
    if (!lupa || lupa._lwBusca) return;
    lupa._lwBusca = true;
    lupa.setAttribute('data-real', '');
    lupa.setAttribute('aria-label', T('Buscar herramienta'));
    var caja = null;
    function enlaces() {
      var aside = document.querySelector('aside');
      if (!aside) return [];
      return Array.prototype.filter.call(aside.querySelectorAll('nav a[data-path]'), function (a) {
        if (a.style.display === 'none') return false;
        var g = a.parentElement; return !(g && g.style.display === 'none');
      });
    }
    function nombre(a) { var s = a.querySelectorAll('span'); return normaliza((s[1] || a).textContent); }
    function sinTildes(t) { return t.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, ''); }
    function cierra() { if (caja) { caja.remove(); caja = null; document.removeEventListener('click', fuera, true); } }
    function fuera(ev) { if (caja && !caja.contains(ev.target) && !lupa.contains(ev.target)) cierra(); }
    function abre() {
      if (caja) { cierra(); return; }
      caja = document.createElement('div');
      caja.style.cssText = 'position:fixed;top:60px;right:24px;z-index:var(--z-modal,400);width:300px;max-width:calc(100vw - 32px);' +
        'background:#fff;border:1px solid #c5c8bc;border-radius:12px;box-shadow:0 8px 24px rgba(0,0,0,.12);padding:10px;font-family:\'Neue Kabel\',sans-serif';
      var inp = document.createElement('input');
      inp.type = 'search'; inp.placeholder = T('Buscar herramienta…');
      inp.setAttribute('aria-label', T('Buscar herramienta'));
      inp.style.cssText = 'width:100%;box-sizing:border-box;padding:8px 10px;border:1px solid #c5c8bc;border-radius:8px;font:inherit;font-size:14px';
      var lista = document.createElement('div');
      lista.style.cssText = 'display:grid;gap:2px;margin-top:8px;max-height:60vh;overflow-y:auto';
      caja.appendChild(inp); caja.appendChild(lista);
      function pinta() {
        var q = sinTildes(inp.value.trim());
        lista.innerHTML = '';
        var hay = enlaces().filter(function (a) { return !q || sinTildes(nombre(a)).indexOf(q) !== -1; });
        if (!hay.length) {
          var p = document.createElement('p'); p.textContent = T('Ninguna herramienta con ese nombre.');
          p.style.cssText = 'margin:4px 6px;font-size:13px;color:#8A8474'; lista.appendChild(p); return;
        }
        hay.forEach(function (a) {
          var o = document.createElement('a');
          o.href = a.href; o.textContent = nombre(a);
          o.style.cssText = 'display:block;padding:7px 10px;border-radius:8px;color:#1b1c19;text-decoration:none;font-size:14px';
          o.addEventListener('mouseenter', function () { o.style.background = '#f5f4ee'; });
          o.addEventListener('mouseleave', function () { o.style.background = ''; });
          lista.appendChild(o);
        });
      }
      inp.addEventListener('input', pinta);
      inp.addEventListener('keydown', function (ev) {
        if (ev.key === 'Escape') { cierra(); lupa.focus(); }
        else if (ev.key === 'Enter') { var o = lista.querySelector('a'); if (o) location.href = o.href; }
      });
      document.body.appendChild(caja);
      document.addEventListener('click', fuera, true);
      pinta(); inp.focus();
    }
    lupa.addEventListener('click', function (ev) { ev.stopPropagation(); abre(); });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () { recablea(); cableaBuscador(); });
  } else { recablea(); cableaBuscador(); }

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
        // DESPUÉS del Panel de control: Usuarios y Cuentas viven ahí dentro
        podaMenu(aside, aut && aut.ficha);
        if (!nuevoGrupo || !window.lwT) return;
        var cabecera = nuevoGrupo.querySelector('span');
        if (cabecera) cabecera.textContent = T(normaliza(cabecera.textContent));
        traduceEnlaces(nuevoGrupo);
      });
    });
  }
})();
