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

  /* COMISIONES: una entrada de menú y hasta cuatro pestañas (23-sep-2026, plan
     aprobado por el owner). Cada pestaña es una página v4 con SU casilla en
     Usuarios; la barra de pestañas se pinta aquí, igual en las cuatro, y solo
     con las que la ficha tiene. La casilla decide si la pestaña aparece; lo que
     se ve dentro lo decide el rol en la base (el closer lo suyo, el manager su
     equipo). `rotulo` cambia el nombre según el rol, no lo que enseña.
     `rol` (27-sep-2026): Condiciones y Equipos piden en la puerta rol admin o
     sales manager además de la casilla (PUERTA_FIJA de catalogo.test.js); sin
     él, la pestaña se ofrecía a un agente con la casilla y rebotaba. */
  var PESTANAS_COMISIONES = [
    { path: 'comisiones',    clave: 'comisiones',             texto: 'Pagos de %marca' },
    { path: 'reparto',       clave: 'comisiones_reparto',     texto: 'Reparto a closers',
      rotulo: { agente: 'Mis comisiones', project_manager: 'Mis comisiones' } },
    { path: 'condiciones',   clave: 'comisiones_condiciones', texto: 'Condiciones', rol: 'admin sales_manager' },
    { path: 'equipos-venta', clave: 'comisiones_equipos',     texto: 'Equipos', rol: 'admin sales_manager', rotulo: { sales_manager: 'Mi equipo' } }
  ];

  /* EL MENÚ DE LA v4, DECLARADO UNA VEZ (27-sep-2026, owner: «Separa las herramientas
     con secciones como en el menú» + Finanzas en 5 entradas con pestañas). Es la
     fuente de las SECCIONES y los NOMBRES que usan:
       · este fichero: qué entradas llevan pestañas (Cobros, Comisiones, Ajustes),
         en qué orden va Finanzas y Comunicación, y qué ofrece el buscador;
       · /v4/usuarios/ (editores.js): las casillas de permiso, agrupadas por sección
         y con el nombre de la entrada del menú — por eso se expone en
         `window.LW_MENU_V4` ANTES de la salida de abajo.
     Qué claves EXISTEN lo sigue diciendo `LW_PERMISOS` (contracts/assets/herramientas.js,
     comparado con la edge admin-usuarios por listas.test.js); nav.test.js falla si una
     clave de allí no tiene sitio aquí, si una de aquí no existe allí, o si una entrada
     de la sidebar no está declarada aquí con el mismo texto.
     Cada entrada: `path` (carpeta v4) o `grupo` (entrada con `pestanas`), `texto` (lo
     que se lee en el menú), `clave` (la casilla que la abre), `rol` (el que exige la
     puerta además de la casilla), `extra` (casillas que viven DENTRO de esa pantalla
     y no tienen entrada propia), `claves` (una entrada que abre cualquiera de varias).
     Sin `clave`: la abre el rol y en Usuarios sale como fila informativa. */
  var MENU_V4 = [
    { seccion: 'Seguimiento', entradas: [
      { path: 'home', texto: 'Home' },
      { path: 'leads', texto: 'CRM', clave: 'leads', extra: [
        { clave: 'ranking', texto: 'Ranking de closers' },
        { clave: 'reparto', texto: 'Reparto de leads' },
        { clave: 'closers', texto: 'Agenda de cierre' },
        { clave: 'bot_conversaciones_ver', texto: 'Conversaciones del bot' }] },
      { path: 'operaciones', texto: 'Operaciones', clave: 'operaciones' },
      { path: 'reservas', texto: 'Reservas', clave: 'reservas' }] },
    { seccion: 'Documentación', entradas: [
      /* Clientes va ANTES de Contratos (14-oct-2026, owner, tras el recorrido de un agente de prueba): es por donde empieza toda
         venta y era la última línea del menú, fuera de la vista a 1440×900 y en el móvil. El `<aside>` de cada página la sigue
         dibujando en «Base de Datos»: la mueve `subeClientes`, que lee el orden de AQUÍ (la entrada que le sigue). Antes y no
         después de Contratos: Emitir, Plantillas y Asistente se cuelgan `afterend` de Contratos y la empujarían hacia abajo.
         La casilla es la misma (`compradores`); en /v4/usuarios/ pasa a salir bajo «Documentación». */
      { path: 'compradores', texto: 'Clientes', clave: 'compradores' },
      { path: 'contratos', texto: 'Contratos', clave: 'contratos' },
      /* Plantillas (AxisWorks ERP, 28-sep-2026, subtarea 6b): solo con AXW_NUCLEO_OPERACION, como Productos.
         Junto a Contratos y no en el Panel de control: la usa quien hace contratos (es su materia prima), no
         es un ajuste de la intranet. Escribir exige además admin, y lo decide la base. */
      { path: 'plantillas', texto: 'Plantillas', clave: 'plantillas', nucleo: true },
      /* Textos de contrato DENTRO de Plantillas (owner, 12-oct-2026: «Textos de contrato (esto es plantillas)»). En Lawang no hay
         motor de plantillas del ERP: su «Plantillas» es /textos-contrato/ (el texto de cada contrato por empresa, 8-oct). `sinNucleo`:
         solo SIN AXW_NUCLEO_OPERACION — en una instancia la entrada es la de arriba y el paquete ya no lleva /textos-contrato/. Sin
         casilla, como antes: la abre el rol (admin o rol de empresa, `data-rol="admin"` en la puerta) y la base decide qué empresa ve
         cada uno (es_admin_de) y quién activa (es_super_admin_de). Nace en el pase con rol (PANEL_CONTROL) y se cuelga tras Contratos. */
      { path: 'textos-contrato', texto: 'Plantillas', rol: 'admin', sinNucleo: true, alias: 'Textos de contrato' },
      /* Emitir contrato (AxisWorks ERP, 30-sep-2026, plantillas MVP subtarea M5): emitir desde una versión
         ACTIVA. Solo con AXW_NUCLEO_OPERACION. Abre con la MISMA casilla que Contratos (la base exige
         es_agente() y puede('contratos') en contrato_desde_plantilla): `mismaCasilla` le dice a nav.test.js
         que no es una casilla repetida, y permisosPorMenu (editores.js) ya no pinta dos veces una clave. */
      { path: 'emitir', texto: 'Emitir contrato', clave: 'contratos', nucleo: true, mismaCasilla: true },
      { path: 'asistente', texto: 'Asistente', clave: 'asistente' },
      { path: 'creatividades', texto: 'Creatividades', claves: [
        { clave: 'dossier', texto: 'crear dossiers' },
        { clave: 'creatividades', texto: 'crear piezas para redes' },
        { clave: 'creatividades_ver', texto: 'solo ver y descargar lo aprobado' }] }] },
    { seccion: 'Finanzas', entradas: [
      { path: 'finanzas', texto: 'Resumen', rol: 'admin' },
      { grupo: 'cobros', texto: 'Cobros', icono: 'payments', pestanas: [
        { path: 'vencimientos', clave: 'vencimientos', texto: 'Vencimientos' },
        { path: 'facturas', clave: 'facturas', texto: 'Facturas' },
        { path: 'recibos', clave: 'recibos', texto: 'Recibos' },
        { path: 'productos', clave: 'productos', texto: 'Productos', nucleo: true }] },
      { grupo: 'comisiones', texto: 'Comisiones', icono: 'request_quote', pestanas: PESTANAS_COMISIONES },
      { path: 'gastos', texto: 'Gastos', clave: 'gastos', rol: 'admin' },
      /* Tesorería (12-oct-2026): era una entrada con dos pestañas, Bancos y Cuentas bancarias; Cuentas pasó a Ajustes (owner: «Cuentas
         bancarias debería ir en ajustes») y una entrada con una sola pestaña era un clic de más. Queda como entrada simple a /bancos/. */
      { path: 'bancos', texto: 'Tesorería', clave: 'bancos', rol: 'admin', alias: 'Bancos' }] },
    { seccion: 'Comunicación', entradas: [
      { path: 'comunicacion', texto: 'Comunicados', clave: 'comunicacion', rol: 'admin' },
      { path: 'soporte', texto: 'Soporte', clave: 'soporte' }] },
    { seccion: 'Base de Datos', entradas: [
      /* La documentación de cada proyecto (y la de la empresa, «Empresa (general)»)
         vive dentro de Proyectos desde el 8-sep; su casilla escribe enlaces y FAQ. */
      { path: 'proyectos', texto: 'Proyectos', clave: 'unidades', extra: [
        { clave: 'documentacion', texto: 'documentación (enlaces, FAQ y ficheros)' }] },
      { path: 'modelos', texto: 'Modelos de casas', clave: 'modelos', alias: 'Modelos' },   // «Modelos» hasta el 12-oct-2026 (owner: «se puede renombrar a 'Modelos de casas'»)
      { path: 'obra', texto: 'Obra', clave: 'obra' }] },
    { seccion: 'Panel de control', entradas: [
      { path: 'usuarios', texto: 'Usuarios', clave: 'usuarios', rol: 'admin' },
      /* Textos de contrato vive en Documentación, como «Plantillas», desde el 12-oct-2026 (ver arriba). */
      /* Ajustes con pestañas (owner, 12-oct-2026: «toda la configuración del ERP debe salir desde aquí» · «Cuentas bancarias debería ir
         en ajustes»). Cada pestaña sigue siendo SU pantalla con SU puerta, su casilla y su URL: Cuentas NO es un panel dentro de
         /ajustes/ porque su puerta es más abierta que la de Ajustes (admin + `cuentas`, sin ámbito: entra un admin de EMPRESA; Ajustes
         pide admin GLOBAL + `ajustes`). Así quien abría Cuentas la sigue abriendo —desde «Ajustes», que le lleva a la primera pestaña que
         tiene— y quien no, no gana nada. `global` en una pestaña: un rol de empresa no la ve (pestanaVisible), como su puerta. El nombre
         del grupo no puede ser una carpeta (GRUPOS y puedeVer se miran por la misma clave). */
      { grupo: 'configuracion', texto: 'Ajustes', icono: 'tune', conEntrada: true, pestanas: [
        { path: 'ajustes', clave: 'ajustes', texto: 'General', rol: 'admin', global: true },
        { path: 'cuentas', clave: 'cuentas', texto: 'Cuentas bancarias', rol: 'admin' }] },
      /* `solo` (7-oct-2026, owner): la puerta de la página lleva data-ambito igual — comision-admin: «super-global» (solo los super admins
         globales; un super de EMPRESA no la ve ni entra). Sociedades emisoras («propietario») dejó el menú el 12-oct: es una pestaña de Ajustes.
         nav.test.js casa menú y puerta. */
      { path: 'comision-admin', texto: 'Comisión de administración', rol: 'super_admin', solo: 'super-global' }] }
      /* Sociedades emisoras ya no es entrada del menú (owner, 12-oct-2026: «sobra, va en Ajustes»): es una pestaña de Ajustes y
         /sociedades/ redirige a /ajustes/#sociedades. */
  ];
  if (typeof window !== 'undefined') window.LW_MENU_V4 = MENU_V4;

  /* Fuera de /intranet/v4/ solo corre si la página lleva la cara v4 puesta
     (`html.v4`). Hoy son dos: el generador de contratos (la pone
     contracts/assets/piel.js; en su cara clásica no se le puede tocar nada: ni
     rutas, ni idioma, ni el `preventDefault` de los href="#", 23-sep) y el CRM
     (/intranet/leads/, la lleva escrita en su <html> desde el 27-sep-2026). A
     las dos les monta el menú assets/nav-montaje.js. */
  if (location.pathname.indexOf('/intranet/v4/') === -1 && !document.documentElement.classList.contains('v4')) return;

  /* FALLOS QUE VE LA PERSONA (25-sep-2026, owner: «¿puede detectar si ha habido un
     fallo y que mande el feedback, o un botón para mandarlo y que me llegue a
     Telegram?»). Se apuntan aquí, lo antes posible y en todas las páginas v4,
     para que el Asistente (mascota.js, que llega tarde: espera a LW_AUTH) pueda
     ofrecer «Avisar al estudio» con los detalles. Solo se APUNTA: nada sale de
     aquí sin que la persona lo pida. Tres fuentes:
     · error de código sin capturar, solo de ficheros del propio dominio (el
       «Script error.» de un CDN no dice nada y no es nuestro);
     · promesa rechazada sin `catch`;
     · el aviso rojo (`#toastMal` de suite-comun.js), lo que la persona LEE. Es
       una constante de aquel fichero y no se puede envolver: se vigila su nodo.
     Tope 8, sin repetir el mismo texto en 3 s. Encargo:
     encargos/20260925_lawang_asistente_mascota.md → «Ampliación». */
  (function () {
    if (window.__lwFallos || location.pathname.indexOf('/intranet/v4/') === -1) return;
    var B = window.__lwFallos = [];
    function apunta(tipo, msg) {
      msg = String(msg == null ? '' : msg).replace(/\s+/g, ' ').trim().slice(0, 300);
      if (!msg) return;
      var u = B[B.length - 1];
      if (u && u.msg === msg && Date.now() - u.t < 3000) return;
      B.push({ tipo: tipo, msg: msg, t: Date.now() });
      if (B.length > 8) B.shift();
      try { document.dispatchEvent(new CustomEvent('lw:fallo', { detail: B[B.length - 1] })); } catch (e) { /* MUDO A PROPÓSITO: navegador sin CustomEvent, queda apuntado igual */ }
    }
    window.addEventListener('error', function (ev) {
      var f = (ev && ev.filename) || '';
      if (!ev || !ev.message || ev.message === 'Script error.' || (f && f.indexOf(location.origin) !== 0)) return;
      apunta('codigo', ev.message + (f ? ' (' + f.slice(location.origin.length).split('?')[0] + ':' + ev.lineno + ')' : ''));
    });
    /* Una promesa rechazada no trae fichero, como sí trae el «error» de arriba: lo trae su pila (SC-33, 15-oct-2026:
       «reading 'M_ID'» dos veces en Home, una propiedad que ninguna versión de la intranet ni de supabase-js ha
       leído nunca; no se pudo decir de dónde venía). Si TODA la pila es de una extensión del navegador, no es
       nuestro y no se apunta, la misma regla que el «error» con fichero ajeno. Si trae una línea del propio
       dominio, se apunta con ella, para que el aviso diga dónde. Sin pila (un `throw` de texto, un error de
       supabase), como antes. */
    var EXTENSION = /^(chrome-extension|moz-extension|safari-extension|safari-web-extension|webkit-masked-url):/;
    window.addEventListener('unhandledrejection', function (ev) {
      var r = ev && ev.reason;
      var msg = r && r.message ? r.message : r;
      if (msg == null || String(msg).trim() === '') return;   // un reject() sin valor no dice nada (antes tampoco se apuntaba)
      msg = String(msg).replace(/\s+/g, ' ').trim();
      // las URLs se buscan en la pila SIN el mensaje: un texto que cite una dirección nuestra no la hace «nuestra»
      var pila = String((r && r.stack) || '');
      var k = r && r.message ? pila.indexOf(String(r.message)) : -1;   // solo la 1.ª vez: la de la cabecera «Error: …»
      if (k !== -1) pila = pila.slice(0, k) + ' ' + pila.slice(k + String(r.message).length);
      var urls = pila.match(/[a-z][a-z-]*:\/\/[^\s()]+/g) || [];
      if (urls.length && urls.every(function (u) { return EXTENSION.test(u); })) return;
      var donde = '';
      for (var i = 0; i < urls.length && !donde; i++) {
        var m = urls[i].indexOf(location.origin + '/') === 0 && urls[i].slice(location.origin.length).match(/^([^?#:]+)(?:[?#][^:]*)?:(\d+)/);
        if (m) donde = ' (' + m[1] + ':' + m[2] + ')';
      }
      apunta('codigo', msg.slice(0, 300 - donde.length) + donde);   // el tope de apunta() no se come el «(ruta:línea)»
    });
    function vigila(n) {
      new MutationObserver(function () {
        if (n.classList.contains('show')) apunta('aviso', n.textContent);
      }).observe(n, { attributes: true, attributeFilter: ['class'] });
    }
    function empieza() {
      var n = document.getElementById('toastMal');
      if (n) return vigila(n);
      // suite-comun.js lo crea al primer aviso, colgado de <body>: solo hijos directos
      var mo = new MutationObserver(function () {
        var t = document.getElementById('toastMal');
        if (t) { mo.disconnect(); vigila(t); if (t.classList.contains('show')) apunta('aviso', t.textContent); }
      });
      mo.observe(document.body, { childList: true });
    }
    if (document.body) empieza(); else document.addEventListener('DOMContentLoaded', empieza);
  })();

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
  var CORTINA = { 'comision-admin': 60 };   // 26-sep-2026, owner: de 15 s a 1 minuto
  var CORTINA_V = '20260926a';
  /* mascota.js (el Asistente acoplado) tampoco lo sella sella_assets: sube MASCOTA_V al cambiarlo. */
  var MASCOTA_V = '20261017a';
  /* novedades.js (el pop-up de novedades, 30-sep-2026) tampoco lo sella sella_assets: sube NOVEDADES_V al cambiarlo. */
  var NOVEDADES_V = '20261014';
  /* aviso-ia.js (la invitación de la cabecera a conectar el asistente de IA, 16-oct-2026) tampoco: sube AVISO_IA_V al cambiarlo. */
  var AVISO_IA_V = '20261017';
  /* MOVIMIENTO (26-sep-2026, owner: mezcla A+B+D). La entrada de cada pantalla
     vive en assets/motion.js; aquí solo se MARCA `html.lw-mov`, ya, antes de que
     vuelva ninguna consulta, para que shell.css retenga el contenido hasta que
     motion.js tome el control, llegue cuando llegue (revisión previa, 26-sep).
     Si la pantalla ya está destapada no hay nada que retener: sin marca, y
     motion.js anima el primer lote que pinte su script (modo tardío). Con
     «reducir movimiento» en el sistema, ni marca ni motion.js. MOTION_V = 8 primeros del sha1 de
     motion.js con fin de línea LF (lo desplegado): nav.test.js falla si no casan, porque sella_assets no lo sella. */
  var MOTION_V = '92fedc21';
  (function () {
    try {
      /* Solo en /intranet/v4/ (27-sep-2026): la entrada anima `main` cuando datos.js
         marca `body.lw-listo`, y ni el generador ni el CRM (fuera de la v4, con el
         menú montado) lo marcan nunca — el observer de motion.js se quedaba
         esperando para nada. El CRM queda fuera también por decisión (cabecera
         de motion.js: «es una vertical con diseño propio»). */
      if (location.pathname.indexOf('/intranet/v4/') === -1) return;
      if (window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches) return;
      if (!(document.body && document.body.classList.contains('lw-listo'))) document.documentElement.classList.add('lw-mov');
      var sm = document.createElement('script');
      sm.src = ROOT + 'assets/motion.js?v=' + MOTION_V;
      sm.onerror = function () { document.documentElement.classList.remove('lw-mov'); };
      document.head.appendChild(sm);
    } catch (e) { document.documentElement.classList.remove('lw-mov'); }
  })();

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
    /* Documentación vive dentro de Proyectos (8-sep); la entrada del menú se esconde
       (retiraDocumentacion) y v4/documentacion/ es solo una redirección. La vuelta a
       la clásica del corte (f1a3aeaa) se deshizo el 27-sep-2026: los documentos de la
       empresa ya están en Proyectos, apartado «Empresa (general)». */
    ['Documentación', 'documentacion/'],
    ['Facturas', 'facturas/'],
    ['Recibos', 'recibos/'],
    ['Proyectos', 'proyectos/'],
    ['Modelos', 'modelos/'],
    ['Obra', 'obra/'],
    ['Clientes', 'compradores/'],
    ['Usuarios', 'usuarios/'],
    /* Las tres que Stitch no dibujo nunca: nacieron despues de la descarga.
       Se enlazan aqui igual que las demas y se INJERTAN abajo (INJERTOS).
       CRM vive fuera de /intranet/v4/ a proposito: conserva su vista propia en
       /intranet/leads/ (owner, 14-sep), con el menu y la cabecera de la v4 desde
       el 27-sep-2026 (nav-montaje.js). Ruta ABSOLUTA, no relativa a ROOT: lo que
       hay en v4/leads/ es solo una redireccion para los enlaces viejos. */
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
  function traduceEnlace(a) {
    if (!window.lwT) return;
    var spans = a.querySelectorAll('span');
    if (spans.length < 2) return;
    var etiqueta = spans[spans.length - 1];          // spans[0] es la ligadura del icono
    etiqueta.textContent = T(normaliza(etiqueta.textContent));
  }
  function traduceEnlaces(scope) {
    scope.querySelectorAll('a').forEach(traduceEnlace);
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

  /* Inversa de marcaActiva, para los CLONES (25-sep-2026). injertaPanelControl
     corre en el segundo pase y clona «Usuarios», que en /usuarios/ ya salió
     marcado del primero: quitar solo aria-current dejaba la píldora verde en
     Resumen, Gastos, Bancos, Cuentas, Ajustes y Comunicados a la vez. */
  function desmarca(a) {
    a.removeAttribute('aria-current');
    a.classList.remove('bg-primary-container', 'text-on-primary', 'font-bold');
    a.classList.add('text-on-surface-variant');
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
      href: '/intranet/leads/' },   // vista propia fuera de /intranet/v4/ (con el cromo v4)
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
    /* 25-sep-2026: /asistente/ pasa a ser el sitio de PETICIONES (cambiar un dato, anular o
       borrar un documento, borrar una operación — aprueba dirección por Telegram). El asistente
       de respuestas a compradores sigue en /asistente-correos/, sin entrada en el menú, hasta
       que se termine (owner). */
    { path: 'asistente',  tras: 'contratos', icono: 'smart_toy',     texto: 'Asistente' },
    { path: 'comisiones', tras: 'recibos',  icono: 'request_quote',  texto: 'Comisiones' },
    /* Reservas por vencer (23-sep-2026, owner, alta prioridad): Cartas de
       Reserva vivas y cuándo vencen. En Seguimiento, tras Vencimientos. */
    { path: 'reservas',   tras: 'vencimientos', icono: 'event_upcoming', texto: 'Reservas' },
    /* Productos (AxisWorks ERP, 26-sep-2026): catálogo de lo que se factura por líneas. `nucleo`: SOLO con
       `window.AXW_NUCLEO_OPERACION` (la enciende el build de las instancias del ERP) — la base de Lawang no
       tiene la tabla y el enlace llevaría a una pantalla vacía. Tras Recibos; es pestaña de «Cobros» (MENU_V4). */
    { path: 'productos',  tras: 'recibos',  icono: 'inventory_2',    texto: 'Productos', nucleo: true },
    /* Plantillas (AxisWorks ERP, 28-sep-2026): tras Contratos. Va DESPUÉS del Asistente en esta lista a
       propósito: los dos se cuelgan tras Contratos, y el último en colgarse queda pegado a él. */
    { path: 'plantillas', tras: 'contratos', icono: 'description',   texto: 'Plantillas', nucleo: true },
    /* Emitir contrato (30-sep-2026): último de la lista para quedar pegado a Contratos (Contratos · Emitir ·
       Plantillas · Asistente). Misma bandera que Plantillas: sin núcleo no hay motor de plantillas en la base. */
    { path: 'emitir',     tras: 'contratos', icono: 'edit_document', texto: 'Emitir contrato', nucleo: true }
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
    /* Finanzas (24-sep-2026, owner: «un dashboard financiero»): la primera del
       grupo porque es la que se mira, no la que se configura. Admin, como la
       puerta (`data-rol="admin"`); lo que ve cada cifra lo decide la RLS y el
       panel dice «sin permiso» donde la ficha no llega. Solo lectura. */
    /* Finanzas, Gastos y Bancos nacen aquí (misma puerta de rol) pero se MUDAN a la
       sección «Finanzas» (ordenaFinanzas, más abajo); Bancos como «Tesorería» (12-oct-2026;
       hasta entonces, Bancos y Cuentas eran pestañas de Tesorería). La cabecera ya dice «Finanzas», así que la
       entrada del panel es «Resumen». Sociedades se queda en el Panel (27-sep). */
    { path: 'finanzas',      icono: 'monitoring',       texto: 'Resumen' },
    /* Gastos y proveedores (24-sep-2026): admin + casilla `gastos` (la poda la
       hace CLAVE_MENU; la puerta de verdad, la RLS). */
    { path: 'gastos',        icono: 'receipt_long',     texto: 'Gastos' },
    /* Bancos (24-sep-2026, owner: «Usan Statrys, bancos de Hong Kong y Singapur»):
       extractos y conciliación. Admin + casilla `bancos`; la puerta, la RLS. */
    { path: 'bancos',        icono: 'account_balance', texto: 'Tesorería' },   // «Bancos» hasta el 12-oct-2026: entrada simple de Finanzas
    /* Cuentas y Ajustes nacen aquí (misma puerta de rol) y se juntan en la entrada «Ajustes» con pestañas (agrupaPestanas). */
    { path: 'cuentas',       icono: 'account_balance', texto: 'Cuentas' },
    /* Textos de contrato (8-oct-2026): admin o rol de empresa; sin casilla (ver MENU_V4). Desde el 12-oct-2026 se llama «Plantillas»
       y se cuelga en Documentación tras Contratos (`tras`); `sinNucleo`: en una instancia no nace (allí Plantillas es la del ERP). */
    { path: 'textos-contrato', icono: 'description',    texto: 'Plantillas', tras: 'contratos', sinNucleo: true },
    /* Equipos de venta, Condiciones y Reparto ya NO van aquí (23-sep-2026, plan
       del owner: «agrupar y controlar lo que se ve por permisos»): son pestañas
       de la entrada «Comisiones», ver PESTANAS_COMISIONES más abajo. */
    /* Ajustes (22-sep-2026, owner: «en el panel de control podemos controlar
       los días de gracia, las prórrogas, los techos, todo lo configurable»):
       la tabla `parametros`. Admin + casilla `ajustes` desde el 27-sep-2026 (la
       exige también mantenimiento_intranet/_envios); escribir un parámetro exige
       super admin en la base (parametro_set), como Cuentas. */
    { path: 'ajustes',       icono: 'tune',             texto: 'Ajustes', global: true },
    /* Comunicación (23-sep-2026, owner: «algo como "Comunicación" para
       escribir yo las plantillas y que se manden a los agentes»): comunicados
       por email al equipo. Admin + casilla `comunicacion` (27-sep-2026; la puerta
       real es es_admin() y puede('comunicacion') en las RPC y la RLS de
       comunicados). Nace aquí por la puerta de rol, pero se
       MUDA a su propia sección (owner, 24-sep: «Comunicación necesita su
       sección, no en panel de control que no pega nada») — ver
       ordenaComunicacion. La cabecera ya dice «Comunicación»: el enlace, «Comunicados». */
    { path: 'comunicacion',  icono: 'campaign',         texto: 'Comunicados' }
  ];

  /* La comision de administracion va aparte del resto del Panel de control:
     aquellas tres las ve cualquier admin, y esta SOLO el super admin, porque
     abre lo que el estudio le cobra al cliente. Se configura aqui y no en
     «Comisiones» — aquella es la del equipo de ventas, y son dos cosas
     distintas que comparten palabra. */
  /* COMISIONES y las demás entradas con pestañas: PESTANAS_COMISIONES y MENU_V4, arriba
     del todo (27-sep-2026). */

  var PANEL_CONTROL_SUPER = [
    { path: 'comision-admin', icono: 'price_change',      texto: 'Comisión de administración', solo: 'super-global' }
  ];
  /* Quién ve cada entrada de PANEL_CONTROL_SUPER (7-oct-2026): la Comisión de administración, solo un super admin GLOBAL. Un super admin de empresa ya no
     la ve (ni la base le contesta: es_super_admin()). Sociedades emisoras («propietario») dejó el panel el 12-oct: es una pestaña de Ajustes; la rama
     'propietario' de veSolo se queda para cualquier entrada futura de ese ámbito. */
  function veSolo(solo, ficha) {
    if (solo === 'propietario') return LW_ROL.esPropietario(ficha);
    if (solo === 'super-global') return LW_ROL.esSuperGlobal(ficha);
    return LW_ROL.esSuperAdmin(ficha);
  }

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
     · Sin clave = sin poda: Home, Resumen (finanzas) y las del super admin
       (comision-admin, sociedades), que gobierna el rol. Usuarios, Cuentas,
       Bancos, Gastos, Ajustes y Comunicados SÍ llevan clave: además de admin,
       hace falta tenerlas asignadas. Las entradas con pestañas (Cobros,
       Comisiones, Ajustes) se ven si la sesión abre alguna de sus pestañas. */
  var CLAVE_MENU = {
    leads: 'leads', operaciones: 'operaciones', soporte: 'soporte', vencimientos: 'vencimientos',
    contratos: 'contratos', asistente: 'asistente', 'asistente-correos': 'asistente', creatividades: ['dossier', 'creatividades', 'creatividades_ver'],
    facturas: 'facturas', recibos: 'recibos', comisiones: ['comisiones', 'comisiones_reparto', 'comisiones_condiciones', 'comisiones_equipos'], reservas: 'reservas', reparto: 'comisiones_reparto', condiciones: 'comisiones_condiciones', 'equipos-venta': 'comisiones_equipos',
    proyectos: 'unidades', modelos: 'modelos', obra: 'obra', compradores: 'compradores',
    usuarios: 'usuarios', cuentas: 'cuentas', gastos: 'gastos', bancos: 'bancos', productos: 'productos', plantillas: 'plantillas', emitir: 'contratos',
    /* Comunicados y Ajustes llevan clave desde el 27-sep-2026 (la exige también la base:
       migración 20260927040933). Documentación ya NO: vive dentro de Proyectos. */
    comunicacion: 'comunicacion', ajustes: 'ajustes'
  };

  /* ENTRADAS CON PESTAÑAS (Cobros, Comisiones — 27-sep-2026, owner; Ajustes desde el 12-oct-2026). Salen de
     MENU_V4: una entrada del menú y una barra de pestañas encima de cada pantalla. Cada
     pestaña sigue siendo SU pantalla con SU puerta (guard.js) y SU casilla, y su URL no
     cambia (enlaces de correos, `?id=`). La entrada lleva a la primera pestaña que la
     sesión puede abrir; si no puede abrir ninguna, la entrada no sale. */
  var GRUPOS = {};
  var FICHA_SESION = null;   // la ficha de la sesión, cuando LW_AUTH resuelve (la usa el buscador)
  MENU_V4.forEach(function (s) {
    s.entradas.forEach(function (e) { if (e.grupo) GRUPOS[e.grupo] = e; });
  });
  function rolPasa(rol, ficha) {
    if (!rol) return true;
    if (!ficha) return true;                          // sin ficha no se poda (como puedeVer)
    var efectivo = LW_ROL.efectivo(ficha);              // admin_empresa = admin, super_admin_empresa = super (guard.js)
    if (efectivo === 'super_admin') return true;
    var lista = rol.split(/\s+/);
    return lista.indexOf(efectivo) !== -1;
  }
  function pestanaVisible(t, ficha) {
    if (t.nucleo && !window.AXW_NUCLEO_OPERACION) return false;
    if (!ficha || LW_ROL.esSuperGlobal(ficha)) return true;   // las casillas solo se las salta el super global (como puede() en la base)
    if (t.global && !LW_ROL.esGlobal(ficha)) return false;     // Ajustes › General: de toda la instancia, como su data-ambito="global" (12-oct-2026)
    return rolPasa(t.rol, ficha) && (!t.clave || (ficha.herramientas || []).indexOf(t.clave) !== -1);
  }
  function pestanasDe(grupo, ficha) {
    return (GRUPOS[grupo] ? GRUPOS[grupo].pestanas : []).filter(function (t) { return pestanaVisible(t, ficha); });
  }
  /* La entrada activa: la de la pestaña en la que se está. */
  function grupoDeAqui() {
    var aqui = location.pathname;
    for (var g in GRUPOS) {
      var t = GRUPOS[g].pestanas.filter(function (p) { return aqui.indexOf('/' + p.path + '/') !== -1; })[0];
      /* `hondo` (12-oct-2026): una página DENTRO de la carpeta de una pestaña (/ajustes/configurar/ de las instancias) marca su
         entrada, pero no lleva la barra de pestañas: no es ninguna de ellas. */
      if (t) return { grupo: g, pestana: t, hondo: !new RegExp('/' + t.path + '/(index\\.html)?$').test(aqui) };
    }
    return null;
  }
  function puedeVer(path, ficha) {
    if (GRUPOS[path]) return !ficha || pestanasDe(path, ficha).length > 0;
    var k = CLAVE_MENU[path];
    if (!k || !ficha || LW_ROL.esSuperGlobal(ficha)) return true;
    return [].concat(k).some(function (h) { return (ficha.herramientas || []).indexOf(h) !== -1; });
  }
  /* SUBMENÚ (30-sep-2026, owner: «al clicar en Cobros que se abra Vencimientos, Facturas y
     Recibos; si no, es un coñazo»). Bajo cada entrada con pestañas cuelgan SUS pestañas —
     las mismas `mias` que la barra, ya filtradas por casilla y rol—, así que no nace ningún
     permiso nuevo. Pulsar la entrada abre/cierra; no navega (su href sigue apuntando a la
     primera pestaña para clic central o sin JS). Abierta de salida en la que se está, con la
     pestaña actual en píldora. Los hijos se enganchan por `data-lw-pestana` (el path), no
     por el rótulo, y NO llevan `data-path`: la poda de podaMenu es solo de la entrada. */
  var SUBS = 0;
  function submenu(entrada, g, mias, aquiG, ficha) {
    var previo = entrada.parentNode && entrada.parentNode.querySelector('[data-lw-sub="' + g + '"]');
    if (previo) previo.parentNode.removeChild(previo);
    var rol = (ficha && LW_ROL.efectivo(ficha)) || '';
    var aqui = aquiG && aquiG.grupo === g;
    var sub = document.createElement('div');
    sub.setAttribute('data-lw-sub', g);
    sub.id = 'lw-sub-' + g + '-' + (++SUBS);   // puede haber más de un aside en la página
    sub.style.cssText = 'display:flex;flex-direction:column;gap:2px;margin:2px 0 4px';
    mias.forEach(function (t) {
      var a = entrada.cloneNode(true);          // clon: mismas clases que el resto del menú
      a.removeAttribute('data-path');
      a.removeAttribute('aria-expanded');
      a.removeAttribute('aria-controls');
      a.setAttribute('data-lw-pestana', t.path);
      desmarca(a);
      a.href = ROOT + t.path + '/';
      a.style.paddingLeft = '44px';
      var spans = a.querySelectorAll('span');
      for (var i = spans.length - 1; i >= 0; i--) {
        if (spans[i].hasAttribute('data-lw-flecha') || i === 0) spans[i].parentNode.removeChild(spans[i]);
      }
      var txt = a.querySelector('span');
      if (txt) txt.textContent = T((t.rotulo && t.rotulo[rol]) || t.texto);
      if (aqui && t === aquiG.pestana) marcaActiva(a);
      sub.appendChild(a);
    });
    entrada.insertAdjacentElement('afterend', sub);

    desmarca(entrada);                          // la píldora la lleva la pestaña, no el grupo
    entrada.setAttribute('aria-controls', sub.id);
    var flecha = entrada.querySelector('[data-lw-flecha]');
    if (!flecha) {
      flecha = document.createElement('span');
      flecha.className = 'material-symbols-outlined text-[18px] nav-text-item';
      flecha.setAttribute('data-lw-flecha', '');
      flecha.setAttribute('aria-hidden', 'true');
      flecha.style.cssText = 'margin-left:auto;transition:transform .2s';
      flecha.textContent = 'expand_more';
      entrada.appendChild(flecha);
    }
    function pon(abierto) {
      sub.style.display = abierto ? 'flex' : 'none';
      entrada.setAttribute('aria-expanded', abierto ? 'true' : 'false');
      flecha.style.transform = abierto ? 'rotate(180deg)' : '';
      if (aqui) entrada.classList.toggle('font-bold', !abierto);   // cerrada, que se sepa dónde se está
    }
    pon(aqui);
    entrada._lwSub = { sub: sub, pon: pon };   // si se rehace, el clic usa el submenú nuevo
    if (!entrada.hasAttribute('data-lw-plegable')) {
      entrada.setAttribute('data-lw-plegable', '');
      entrada.addEventListener('click', function (ev) {
        if (ev.button !== 0 || ev.ctrlKey || ev.metaKey || ev.shiftKey) return;   // abrir en pestaña nueva sigue valiendo
        var s = entrada._lwSub;
        if (!s) return;
        ev.preventDefault();
        s.pon(s.sub.style.display === 'none');
      });
    }
  }

  /* Cada entrada con pestañas lleva a la PRIMERA pestaña que la ficha tiene (un closer
     solo tiene «Mis comisiones») y se marca activa en todas sus páginas. La barra se
     pinta una vez, justo bajo la cabecera, solo con las pestañas que la ficha abre. */
  function cableaPestanas(aside, ficha) {
    var aquiG = grupoDeAqui();
    Object.keys(GRUPOS).forEach(function (g) {
      var entrada = aside.querySelector('a[data-path="' + g + '"]');
      var mias = pestanasDe(g, ficha);
      if (entrada && mias.length) entrada.href = ROOT + mias[0].path + '/';
      if (entrada && mias.length) submenu(entrada, g, mias, aquiG, ficha);
      else if (entrada && aquiG && aquiG.grupo === g) marcaActiva(entrada);
    });
    if (!aquiG || aquiG.hondo) return;
    var idBarra = 'lw-pestanas-' + aquiG.grupo;
    if (document.getElementById(idBarra)) return;
    var mias = pestanasDe(aquiG.grupo, ficha);
    var main = document.querySelector('main');
    if (!main || !mias.length) return;
    var rol = (ficha && LW_ROL.efectivo(ficha)) || '';
    var barra = document.createElement('nav');
    barra.id = idBarra;
    barra.setAttribute('aria-label', T(GRUPOS[aquiG.grupo].texto));
    barra.style.cssText = 'display:flex;flex-wrap:wrap;gap:4px;padding:6px;background:#fff;border-radius:999px;box-shadow:0 1px 3px rgba(0,0,0,.06);width:fit-content;max-width:100%;margin:0 0 24px';
    mias.forEach(function (t) {
      var a = document.createElement('a');
      var on = t === aquiG.pestana;
      a.href = ROOT + t.path + '/';
      a.textContent = T((t.rotulo && t.rotulo[rol]) || t.texto);
      a.style.cssText = 'padding:9px 18px;border-radius:999px;font:600 14px/1 "Neue Kabel",sans-serif;text-decoration:none;white-space:nowrap;' +
        (on ? 'background:#485B37;color:#fff' : 'color:#44483f');
      if (on) a.setAttribute('aria-current', 'page');
      barra.appendChild(a);
    });
    var cab = main.querySelector('.lw-cabecera');
    if (cab && cab.parentNode) cab.parentNode.insertBefore(barra, cab.nextSibling);
    else main.insertBefore(barra, main.firstChild);
    /* Closer en «Mis comisiones»: es la misma pantalla que la del manager, solo
       con sus filas. Se esconde lo que es del manager (configurar el reparto,
       marcar pagada, ajustar, anular) — la base ya se lo impediría. */
    if (aquiG.pestana.path === 'reparto' && (rol === 'agente' || rol === 'project_manager')) {
      var st = document.createElement('style');
      st.textContent = 'main a[href="../condiciones/"],[data-eq-pagar],[data-eq-ajustar],[data-eq-anular]{display:none!important}';
      document.head.appendChild(st);
      var h1 = main.querySelector('h1');
      if (h1) h1.textContent = T('Mis comisiones');
      /* La pestaña también: lwFichaAplicar compone «<data-lw-base> — <marca>» y lo repite al cambiar de idioma. */
      var tt = document.querySelector('title[data-lw-titulo]');
      if (tt) {
        tt.setAttribute('data-lw-base', 'Mis comisiones');
        var corte = document.title.indexOf(' — ');
        document.title = T('Mis comisiones') + (corte >= 0 ? document.title.slice(corte) : '');
      }
      var sub = h1 && h1.parentNode && h1.parentNode.querySelector('p');
      if (sub) sub.textContent = T('Lo que te toca por cada venta y si tu manager ya te lo ha pagado. Solo ves lo tuyo.');
    }
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
     editar 22 sidebars; el fichero de la pantalla queda como redireccion.
     El corte de la clásica (f1a3aeaa) la había vuelto a sacar hacia
     /intranet/documentacion/ porque los documentos de la EMPRESA solo se veían
     allí; el 27-sep-2026 (owner: «la tenemos duplicada») esos documentos pasan a
     Proyectos, apartado «Empresa (general)», y la clásica se retira. */
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
    desmarca(a);
    var spans = a.querySelectorAll('span');
    if (spans.length < 2) return;
    spans[0].textContent = spec.icono;        // ligadura de material-symbols
    spans[1].textContent = spec.texto;
    /* Con href propio deja de ser href="#", y recablea() ya no lo mira: solo
       recorre `a[href="#"]`. Es el enganche para una herramienta que vive
       fuera de la v4, como el CRM — y por eso la marca de activa va aquí: desde
       el 27-sep-2026 el CRM lleva este menú y tiene que salir marcado en él. */
    if (spec.href) {
      a.href = spec.href;
      if (location.pathname.indexOf(spec.href) === 0) marcaActiva(a);
    }
    ancla.insertAdjacentElement('afterend', a);
  }

  /* SECCIÓN «FINANZAS» (24-sep-2026, owner, opción A): todo lo que mueve
     dinero en un solo grupo, en vez de repartido entre Seguimiento,
     Administración y Panel de control. Es el grupo «Administración» que dibujó
     Stitch, renombrado: no se editan las 22 sidebars. Cada entrada se MUEVE
     (appendChild) con su data-path, su traducción y su marca de activo; la que
     no está en la página (Resumen/Gastos/Cuentas sin rol admin, Sociedades sin
     super) simplemente no aparece. Quién ve cada una lo siguen decidiendo su
     casilla y la RLS: cambiar de grupo no cambia permisos.
     27-sep-2026 (owner): de 9 entradas a 5 — Resumen · Cobros [Vencimientos |
     Facturas | Recibos] · Comisiones [sus 4 pestañas] · Gastos · Tesorería
     (entrada simple a Bancos desde el 12-oct-2026: Cuentas bancarias pasó a Ajustes). El orden
     y las pestañas salen de MENU_V4. Una entrada con pestañas se CREA clonando su
     primera pestaña (mismas clases) y los enlaces de las pestañas SALEN de la
     sidebar: quedan en la barra de pestañas de su pantalla y en el buscador.
     Se llama en el pase síncrono DESPUÉS de injertaNuevas (Reservas se injerta
     `tras: 'vencimientos'`, Comisiones y Productos `tras: 'recibos'`: esos
     enlaces tienen que existir todavía) y ANTES de traduceSidebar (la cabecera
     y las entradas nuevas pasan por T allí). En el segundo pase (tras LW_AUTH)
     se vuelve a llamar con `traducir`: Tesorería (Bancos) llega entonces, del
     enlace que injerta el Panel de control. */
  var FINANZAS_V4 = MENU_V4.filter(function (s) { return s.seccion === 'Finanzas'; })[0].entradas;
  function ordenaFinanzas(aside, traducir) {
    var g = aside.querySelector('[data-seccion="finanzas"]');
    if (!g) {
      var ancla = aside.querySelector('nav a[data-path="facturas"]');
      g = ancla && ancla.parentElement;
      var cab = g && g.querySelector(':scope > span');
      if (!g || !cab) return;                    // sin el grupo de Stitch no hay dónde
      g.setAttribute('data-seccion', 'finanzas');
      cab.textContent = 'Finanzas';
    }
    var aquiG = grupoDeAqui();
    FINANZAS_V4.forEach(function (e) {
      var a;
      if (e.path || e.grupo === 'comisiones') {
        a = aside.querySelector('nav a[data-path="' + (e.path || e.grupo) + '"]');
        if (a) g.appendChild(a);
        return;
      }
      a = entradaDeGrupo(aside, e, traducir, aquiG);
      if (a) g.appendChild(a);
    });
  }

  /* La entrada de un grupo con pestañas (Cobros, Ajustes…): si no está, se CREA clonando su primera pestaña presente (mismas
     clases) y se pone en el sitio de esa pestaña; los enlaces de las pestañas SALEN de la sidebar (quedan en el submenú, la barra
     de su pantalla y el buscador). Sin ninguna pestaña en la página no hay entrada. La usan ordenaFinanzas y agrupaPestanas. */
  function entradaDeGrupo(aside, e, traducir, aquiG) {
    var tabs = e.pestanas.map(function (t) { return aside.querySelector('nav a[data-path="' + t.path + '"]'); }).filter(Boolean);
    var a = aside.querySelector('nav a[data-path="' + e.grupo + '"]');
    if (!a && tabs.length) {
      a = tabs[0].cloneNode(true);               // clon: hereda las clases exactas
      a.setAttribute('data-path', e.grupo);
      desmarca(a);
      var spans = a.querySelectorAll('span');
      if (spans.length >= 2) { spans[0].textContent = e.icono; spans[1].textContent = traducir ? T(e.texto) : e.texto; }
      var primera = e.pestanas.filter(function (t) { return !t.nucleo || window.AXW_NUCLEO_OPERACION; })[0];
      a.href = ROOT + primera.path + '/';        // href propio: recablea() ya no lo toca
      if (aquiG && aquiG.grupo === e.grupo) marcaActiva(a);
      tabs[0].parentNode.insertBefore(a, tabs[0]);
    }
    tabs.forEach(function (t) { if (t.parentNode) t.parentNode.removeChild(t); });
    return a;
  }

  /* Las entradas con pestañas FUERA de Finanzas (12-oct-2026: «Ajustes» con General · Cuentas bancarias, en el Panel de control):
     la entrada queda donde estaba su primera pestaña, sin mudarse de sección. Segundo pase, tras injertaPanelControl: sus pestañas
     nacen allí, con el rol de la sesión. */
  function agrupaPestanas(aside, traducir) {
    var aquiG = grupoDeAqui();
    MENU_V4.forEach(function (s) {
      if (s.entradas === FINANZAS_V4) return;    // las suyas las coloca ordenaFinanzas
      s.entradas.forEach(function (e) { if (e.grupo) entradaDeGrupo(aside, e, traducir, aquiG); });
    });
  }

  /* SECCIÓN «COMUNICACIÓN» (24-sep-2026, owner). Comunicados al equipo (admin)
     + Soporte, que son los tickets de los compradores: lo que se habla con la
     gente, dentro y fuera. Stitch no la dibujó, así que se CREA clonando el
     grupo de Finanzas vacío (mismas clases) y va justo detrás. Mismo contrato
     que ordenaFinanzas: pase síncrono (Soporte ya está en la página) y
     segundo pase (Comunicados solo existe tras saber el rol). Sin ningún
     enlace se esconde entera: podaMenu no toca un grupo sin enlaces. */
  var ORDEN_COMUNICACION = MENU_V4.filter(function (s) { return s.seccion === 'Comunicación'; })[0]
    .entradas.map(function (e) { return e.path; });
  function ordenaComunicacion(aside) {
    var g = aside.querySelector('[data-seccion="comunicacion"]');
    if (!g) {
      var fin = aside.querySelector('[data-seccion="finanzas"]');
      var cab = fin && fin.querySelector(':scope > span');
      if (!fin || !cab) return;
      g = fin.cloneNode(false);
      g.removeAttribute('style');
      g.setAttribute('data-seccion', 'comunicacion');
      var c = cab.cloneNode(true);
      c.textContent = T('Comunicación');
      g.appendChild(c);
      fin.insertAdjacentElement('afterend', g);
    }
    ORDEN_COMUNICACION.forEach(function (p) {
      var a = aside.querySelector('nav a[data-path="' + p + '"]');
      if (a) g.appendChild(a);
    });
    g.style.display = g.querySelector('a[data-path]') ? '' : 'none';
  }

  /* «Clientes» sube junto a «Contratos» (14-oct-2026). El sitio sale de MENU_V4: se coloca delante de la entrada que allí la
     sigue. Se MUEVE el enlace que ya dibujó la página (con su data-path, su traducción y su marca de activa), no se clona.
     Sin ese vecino en la página se queda donde estaba; quién la ve lo siguen decidiendo su casilla y la poda. */
  var TRAS_CLIENTES = (function () {
    var p = '';
    MENU_V4.forEach(function (s) {
      s.entradas.forEach(function (e, i) { if (e.path === 'compradores' && s.entradas[i + 1]) p = s.entradas[i + 1].path || ''; });
    });
    return p;
  })();
  function subeClientes(aside) {
    var c = aside.querySelector('nav a[data-path="compradores"]');
    var vecino = TRAS_CLIENTES && aside.querySelector('nav a[data-path="' + TRAS_CLIENTES + '"]');
    if (c && vecino && vecino.previousElementSibling !== c) vecino.insertAdjacentElement('beforebegin', c);
  }

  function injertaNuevas(aside) {
    injerta(aside, { path: 'modelos', tras: 'proyectos', icono: 'villa', texto: 'Modelos de casas' });
    INJERTOS.forEach(function (spec) { if (!spec.nucleo || window.AXW_NUCLEO_OPERACION) injerta(aside, spec); });
  }

  /* «APPS CONECTADAS» (MCP de Lawang F1-P4, 16-oct-2026): los asistentes de IA que la persona ha conectado con SU usuario.
     Es de cada persona, no una herramienta del negocio: va en el pie de la barra, junto a «Idioma» y «Cerrar Sesión» (lo que es de
     la cuenta), y por eso NO está en MENU_V4 ni lleva casilla — en /v4/usuarios/ no hay nada que conceder (el permiso de IA lo da el
     super admin en Ajustes › IA) y la página la abre cualquier ficha (su guard.js va sin data-herramienta ni data-rol).
     Se clona el enlace de salida (mismas clases) y va encima de él. En una instancia del ERP no nace: las ia_* solo existen en Lawang. */
  function injertaCuenta(aside) {
    if (window.AXW_NUCLEO_OPERACION || aside.querySelector('a[data-path="ia"]')) return;
    var salir = aside.querySelector('a[data-path="login"]');
    var spans = salir && salir.querySelectorAll('span');
    if (!salir || !spans || spans.length < 2) return;
    var a = salir.cloneNode(true);              // sin los listeners de cableaSalir: cloneNode no los copia
    a.setAttribute('data-path', 'ia');
    a.removeAttribute('title');
    desmarca(a);
    var s = a.querySelectorAll('span');
    s[0].textContent = 'apps';                  // ligadura de material-symbols
    s[s.length - 1].textContent = 'Apps conectadas';   // en español a propósito: traduceSidebar() la pasa por lwT después (corre tras recablea)
    a.href = ROOT + 'ia/';                      // href propio: recablea() ya no lo toca
    if (location.pathname.indexOf('/intranet/v4/ia/') !== -1) marcaActiva(a);
    salir.insertAdjacentElement('beforebegin', a);
  }

  /* Rol de la sesion -> se enteran solo cuando `window.LW_AUTH` resuelve, que
     en la practica ya ha pasado para cuando la pagina se hace visible (guard.js
     quita `visibility:hidden` justo despues de resolver la promesa), asi que no
     hay parpadeo: el usuario nunca llega a ver el menu sin estos dos items y
     luego perderlos. */
  function esAdminSesion(ficha) { return LW_ROL.esAdmin(ficha); }         // un rol de empresa cuenta como admin para MOSTRAR

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

    PANEL_CONTROL.concat(PANEL_CONTROL_SUPER.filter(function (s) { return veSolo(s.solo, ficha); })).forEach(function (spec) {
      if (spec.global && !LW_ROL.esGlobal(ficha)) return;   // Ajustes: de toda la instancia, un rol de empresa no la ve
      if (spec.sinNucleo && window.AXW_NUCLEO_OPERACION) return;   // Plantillas de Lawang (textos-contrato): en una instancia, la del ERP
      var a = ancla.cloneNode(true);              // clon de "Usuarios": hereda las clases exactas
      a.setAttribute('data-path', spec.path);
      desmarca(a);
      var spans = a.querySelectorAll('span');
      if (spans.length < 2) return;
      spans[0].textContent = spec.icono;
      spans[1].textContent = spec.texto;
      a.href = ROOT + spec.path + '/';
      if (aqui.indexOf('/' + spec.path + '/') !== -1) marcaActiva(a);
      /* `tras` (12-oct-2026): nace con la puerta de rol de aquí pero vive en OTRA sección, tras ese vecino (Plantillas tras Contratos).
         Sin el vecino en la página, se queda en el Panel. Fuera de `nuevoGrupo` hay que traducirla aquí: el pase de abajo solo traduce el grupo. */
      var vecino = spec.tras && aside.querySelector('nav a[data-path="' + spec.tras + '"]');
      if (vecino) { traduceEnlace(a); vecino.insertAdjacentElement('afterend', a); }
      else nuevoGrupo.appendChild(a);
    });

    grupo.insertAdjacentElement('afterend', nuevoGrupo);
    return nuevoGrupo;
  }

  function recablea() {
    var aqui = location.pathname;
    document.querySelectorAll('aside').forEach(injertaNuevas);
    document.querySelectorAll('aside').forEach(injertaCuenta);
    document.querySelectorAll('aside').forEach(retiraDocumentacion);
    document.querySelectorAll('aside').forEach(function (aside) { ordenaFinanzas(aside, false); });
    document.querySelectorAll('aside').forEach(ordenaComunicacion);
    document.querySelectorAll('aside').forEach(subeClientes);
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
    /* Cada resultado es {nombre, href, alias}. Una entrada con pestañas (Cobros, Comisiones,
       Ajustes) se abre en sus pestañas: el buscador sigue encontrando «Facturas» por su nombre
       aunque ya no tenga enlace propio en la sidebar (27-sep). Desde el 12-oct-2026: con
       `conEntrada` la pestaña sale como «Ajustes · General» (buscar «ajustes» la encuentra), y
       `alias` es el nombre de antes de un renombre («Bancos», «Textos de contrato», «Modelos»):
       también casa, aunque se enseña el nombre de ahora. */
    var ALIAS = {};
    MENU_V4.forEach(function (s) { s.entradas.forEach(function (e) { if (e.path && e.alias) ALIAS[e.path] = e.alias; }); });
    function enlaces() {
      var aside = document.querySelector('aside');
      if (!aside) return [];
      var out = [];
      Array.prototype.forEach.call(aside.querySelectorAll('nav a[data-path]'), function (a) {
        if (a.style.display === 'none') return;
        var g = a.parentElement; if (g && g.style.display === 'none') return;
        var dp = a.getAttribute('data-path');
        if (GRUPOS[dp]) {
          var rol = (FICHA_SESION && LW_ROL.efectivo(FICHA_SESION)) || '';
          pestanasDe(dp, FICHA_SESION).forEach(function (t) {
            var n = T((t.rotulo && t.rotulo[rol]) || t.texto);
            out.push({ nombre: GRUPOS[dp].conEntrada ? T(GRUPOS[dp].texto) + ' · ' + n : n, href: ROOT + t.path + '/' });
          });
          return;
        }
        out.push({ nombre: nombre(a), href: a.href, alias: ALIAS[dp] ? T(ALIAS[dp]) : '' });
      });
      return out;
    }
    function nombre(a) { var s = a.querySelectorAll('span'); return normaliza((s[1] || a).textContent); }
    function sinTildes(t) { return lwNormaliza(t); }   // la pieza comun (contracts/assets/vocabulario.js, 15-oct)
    function cierra() { if (caja) { caja.remove(); caja = null; document.removeEventListener('click', fuera, true); } }
    function fuera(ev) { if (caja && !caja.contains(ev.target) && !lupa.contains(ev.target)) cierra(); }
    /* CLIENTES, CONTRATOS Y UNIDADES (Experiencia H6, 17-oct-2026: «menú, herramienta y buscar: 3 clics»). Revisión
       previa #429 de Seguridad y Backend:
       · Solo se PIDE el grupo cuya herramienta enseña el menú a esta sesión. Eso es comodidad, no la barrera: lo que
         limita de verdad es es_agente() y la RLS de cada lectura (son las mismas que usan sus pantallas).
       · Contratos por contratos_busca (busca en el servidor, sin tildes, 10 filas): nunca contratos_equipo() entero, que
         arma la fila completa de todos los contratos (el IO de Lawang cayó así el 1-oct).
       · Unidades por unidades_busca (17-oct, migración 20261017210000: busca en el servidor por código o nombre de HOY del
         proyecto, sin tildes, 10 filas, INVOKER con la RLS de unidades). La pantalla no lee la tabla (norma del owner del
         15-oct, gate escrituras_front). Sin la migración aplicada, PGRST202 esconde solo este grupo.
       · Clientes (solo id y nombre) se piden UNA vez por apertura y se filtran aquí con lwBuscaEn. Viven en memoria
         mientras el buscador está abierto: nada en localStorage ni sessionStorage.
       · Una instancia sin la función o sin permiso (PGRST202 / 42501, p. ej. el ERP fijado) esconde el grupo sin
         aviso; la línea «No se ha podido buscar en …» queda para la red o un fallo del servidor, sin su mensaje.
       · Texto por textContent y enlaces a rutas propias con encodeURIComponent; nunca innerHTML con un dato.
       · Cada enlace lleva el ID de la fila (contrato, cliente, proyecto), nunca su número ni su nombre. */
    var GRUPOS_DATOS = [
      { path: 'contratos', titulo: 'Contratos', porConsulta: true,
        pide: function (sb, q) { return sb.rpc('contratos_busca', { p_q: q.slice(0, 120) }); },
        casa: null,
        fila: function (c) { return [c.numero + (c.comprador_nombre ? ' · ' + c.comprador_nombre : ''), [c.proyecto_nombre, c.parcela_codigo].filter(Boolean).join(' · '), ROOT + 'contratos/?contrato=' + encodeURIComponent(c.id)]; },
        vale: function (c) { return c && c.id && c.numero; } },
      { path: 'compradores', titulo: 'Clientes',
        pide: function (sb) { return sb.rpc('compradores_lista').select('id,full_name'); },
        casa: function (c, q) { return lwBuscaEn([c.full_name], q); },
        fila: function (c) { return [c.full_name, '', ROOT + 'compradores/?id=' + encodeURIComponent(c.id)]; },
        vale: function (c) { return c && c.id && c.full_name; } },
      { path: 'proyectos', titulo: 'Unidades', porConsulta: true,
        pide: function (sb, q) { return sb.rpc('unidades_busca', { p_q: q.slice(0, 120) }); },
        casa: null,
        // por id, nunca por el nombre (máxima «todo apunta por ID»): Proyectos abre su cajón con ?proyecto=<id> desde el 17-oct
        fila: function (u) { return [u.codigo, u.proyecto || '', ROOT + 'proyectos/?proyecto=' + encodeURIComponent(u.proyecto_id)]; },
        vale: function (u) { return u && u.codigo && u.proyecto_id; } }
    ];
    var POR_GRUPO = 5;
    function tiene(dp) {
      var a = document.querySelector('aside nav a[data-path="' + dp + '"]');
      if (!a || a.style.display === 'none') return false;
      var g = a.parentElement; return !(g && g.style.display === 'none');
    }
    function resultado(txt, sub, href) {
      var o = document.createElement('a');
      o.href = href; o.textContent = txt;
      o.style.cssText = 'display:block;padding:9px 12px;border-radius:8px;color:#292524;text-decoration:none;font:500 14px/1.35 Jost,system-ui,sans-serif';
      if (sub) { var s = document.createElement('span'); s.textContent = sub; s.style.cssText = 'display:block;font:400 12px/1.35 Jost,system-ui,sans-serif;color:#78716c'; o.appendChild(s); }
      o.addEventListener('mouseenter', function () { o.style.background = '#F3F0E8'; });
      o.addEventListener('mouseleave', function () { o.style.background = ''; });
      return o;
    }
    var memo = {}, turno = 0, espera = null;
    function sinPermisoONoExiste(e) { return e && (e.code === 'PGRST202' || e.code === '42501'); }
    function lee(g, sb, q) {
      if (!g.porConsulta && memo[g.path]) return memo[g.path];
      // sin la función o sin permiso no se vuelve a pedir en cada tecla mientras dure esta apertura
      if (memo['no:' + g.path]) return memo['no:' + g.path];
      var p = Promise.resolve(g.pide(sb, q)).then(function (r) {
        if (r && r.error) {
          if (sinPermisoONoExiste(r.error)) memo['no:' + g.path] = Promise.resolve({ error: r.error });
          return { error: r.error };
        }
        return { filas: ((r && r.data) || []).filter(g.vale) };
      }, function (e) { return { error: e || {} }; });
      if (!g.porConsulta) memo[g.path] = p;
      return p;
    }
    function buscaDatos(texto, dest) {
      clearTimeout(espera);
      var mio = ++turno;
      var q = sinTildes(texto);
      var grupos = GRUPOS_DATOS.filter(function (g) { return tiene(g.path); });
      if (q.length < 2 || !grupos.length || !window.LW_AUTH || typeof window.LW_AUTH.then !== 'function') { dest.innerHTML = ''; return; }
      espera = setTimeout(function () {
        window.LW_AUTH.then(function (aut) {
          var sb = aut && aut.sb; if (!sb) return [];
          return Promise.all(grupos.map(function (g) { return lee(g, sb, texto).then(function (r) { return { g: g, r: r }; }); }));
        }).then(function (res) {
          if (mio !== turno || !caja) return;   // ya se tecleó otra cosa o se cerró
          dest.innerHTML = '';
          (res || []).forEach(function (x) {
            var g = x.g, r = x.r;
            if (r.error) {
              if (sinPermisoONoExiste(r.error)) return;
              var f = document.createElement('p'); f.textContent = T('No se ha podido buscar en %g.', { g: T(g.titulo) }).split('%g').join(T(g.titulo));
              f.style.cssText = 'margin:6px 8px;font:400 12px Jost,system-ui,sans-serif;color:#a8a29e'; dest.appendChild(f); return;
            }
            var hay = g.casa ? r.filas.filter(function (c) { return g.casa(c, q); }) : r.filas;
            if (!hay.length) return;
            var h = document.createElement('p'); h.textContent = T(g.titulo);
            h.style.cssText = 'margin:10px 12px 2px;font:600 11px Jost,system-ui,sans-serif;letter-spacing:.08em;text-transform:uppercase;color:#a8a29e';
            dest.appendChild(h);
            hay.slice(0, POR_GRUPO).forEach(function (c) { var v = g.fila(c); dest.appendChild(resultado(v[0], v[1], v[2])); });
          });
        });
      }, 250);
    }
    function abre() {
      if (caja) { cierra(); return; }
      memo = {};   // una carga por apertura: lo que se abra mañana trae lo de mañana
      caja = document.createElement('div');
      caja.style.cssText = 'position:fixed;top:60px;right:24px;z-index:var(--z-modal,400);width:340px;max-width:calc(100vw - 32px);' +
        'background:#fff;border:1px solid #E7E4DC;border-radius:12px;box-shadow:0 18px 40px -12px rgba(30,37,34,.22),0 2px 6px rgba(30,37,34,.06);padding:8px;font-family:Jost,system-ui,sans-serif';   // piel del desplegable del alta (26-sep-2026)
      var inp = document.createElement('input');
      var conDatos = GRUPOS_DATOS.some(function (g) { return tiene(g.path); });
      inp.type = 'search'; inp.placeholder = T(conDatos ? 'Buscar herramienta, cliente, contrato o unidad…' : 'Buscar herramienta…');
      inp.setAttribute('aria-label', T(conDatos ? 'Buscar herramienta, cliente, contrato o unidad' : 'Buscar herramienta'));
      inp.style.cssText = 'width:100%;box-sizing:border-box;padding:10px 14px;border:1px solid #E7E4DC;border-radius:8px;font:400 14px/1.43 Jost,system-ui,sans-serif;color:#1c1917;background:rgba(250,250,249,.5);outline:none';
      inp.addEventListener('focus', function () { inp.style.borderColor = '#104C4F'; inp.style.boxShadow = '0 0 0 2px #104C4F'; inp.style.background = '#fff'; });
      inp.addEventListener('blur', function () { inp.style.borderColor = '#E7E4DC'; inp.style.boxShadow = 'none'; inp.style.background = 'rgba(250,250,249,.5)'; });
      var lista = document.createElement('div');
      lista.style.cssText = 'display:grid;gap:2px;margin-top:8px;max-height:60vh;overflow-y:auto';
      caja.appendChild(inp); caja.appendChild(lista);
      var herr = document.createElement('div'), datos = document.createElement('div');
      herr.style.cssText = datos.style.cssText = 'display:grid;gap:2px';
      lista.appendChild(herr); lista.appendChild(datos);
      function pinta() {
        var q = sinTildes(inp.value.trim());
        herr.innerHTML = '';
        var hay = enlaces().filter(function (a) { return lwBuscaEn([a.nombre, a.alias], q); });
        if (!hay.length) {
          var p = document.createElement('p'); p.textContent = T('Ninguna herramienta con ese nombre.');
          p.style.cssText = 'margin:6px 8px;font:400 13px Jost,system-ui,sans-serif;color:#a8a29e;font-style:italic'; herr.appendChild(p);
        }
        hay.forEach(function (a) { herr.appendChild(resultado(a.nombre, '', a.href)); });
        buscaDatos(inp.value.trim(), datos);
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
      FICHA_SESION = (aut && aut.ficha) || null;
      document.querySelectorAll('aside').forEach(function (aside) {
        // «Panel de control» nace DESPUES del primer traduceSidebar (este
        // pase espera a LW_AUTH) — sin traducir el grupo nuevo se queda en
        // español aunque el resto de la sidebar ya este en ingles. Se
        // traduce SOLO `nuevoGrupo` (code-review, 21-sep): volver a barrer
        // los 14-17 enlaces ya traducidos en cada carga con sesion no
        // cambia nada que ya no estuviera en ingles, solo trabajo de mas.
        var nuevoGrupo = injertaPanelControl(aside, aut && aut.ficha);
        // Traducir ANTES de mudar a Finanzas lo que nació aquí: después ya no
        // está dentro de `nuevoGrupo` y se quedaría en español.
        if (nuevoGrupo && window.lwT) {
          var cabecera = nuevoGrupo.querySelector('span');
          if (cabecera) cabecera.textContent = T(normaliza(cabecera.textContent));
          traduceEnlaces(nuevoGrupo);
        }
        ordenaFinanzas(aside, true);
        ordenaComunicacion(aside);
        agrupaPestanas(aside, true);   // «Ajustes» con sus pestañas (12-oct-2026): General y Cuentas bancarias nacen en el Panel de control
        cableaPestanas(aside, aut && aut.ficha);
        // DESPUÉS del Panel de control y de la mudanza: poda y grupos vacíos
        podaMenu(aside, aut && aut.ficha);
      });
      /* El Asistente acoplado en la esquina (25-sep-2026, mascota.js): solo
         para quien puede abrir /asistente/ — la misma regla del menú, que vive
         aquí y no se copia allí. Sin ficha no sale: puedeVer() deja pasar a
         quien no tiene ficha (no poda), y la mascota llevaría a una página que
         guard.js rebota. Se sella con MASCOTA_V, como cortina.js. */
      if (aut && aut.ficha && puedeVer('asistente', aut.ficha) &&
          location.pathname.indexOf('/intranet/v4/') !== -1) {
        var sm = document.createElement('script');
        sm.src = ROOT + 'assets/mascota.js?v=' + MASCOTA_V;
        document.head.appendChild(sm);
      }
      /* El pop-up de novedades: una vez por persona y versión; decide dentro qué noticias
         le tocan según sus herramientas. Solo con ficha (sin ficha guard.js rebota). */
      if (aut && aut.ficha && location.pathname.indexOf('/intranet/v4/') !== -1) {
        var sn = document.createElement('script');
        sn.src = ROOT + 'assets/novedades.js?v=' + NOVEDADES_V;
        document.head.appendChild(sn);
      }
      /* La invitación a conectar el asistente de IA, en la cabecera (MCP de Lawang, 16-oct-2026). A quién le sale lo decide
         la base (ia_mis_conexiones) dentro de aviso-ia.js. En una instancia del ERP no nace: las ia_* solo existen en Lawang. */
      if (aut && aut.ficha && !window.AXW_NUCLEO_OPERACION) {
        var sa = document.createElement('script');
        sa.src = ROOT + 'assets/aviso-ia.js?v=' + AVISO_IA_V;
        document.head.appendChild(sa);
      }
    });
  }
})();
