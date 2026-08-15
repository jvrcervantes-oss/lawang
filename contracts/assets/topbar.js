/* Comportamiento de los desplegables <details> de la suite (barra superior y
   barra de vista previa) — 28-jul-2026.

   <details> se abre solo, pero no se cierra ni al elegir una acción ni al
   pinchar fuera: sin esto se queda abierto tapando lo que hay debajo. Vive aquí
   y no copiado en cada app por lo mismo que topbar.css.

   Reglas:
   · solo un menú abierto a la vez,
   · elegir una acción (button/a de la lista) cierra,
   · un control que se usa varias veces seguidas (zoom) lleva data-keep y NO cierra,
   · clic fuera o Escape cierra todos.
   Un <select> o <label> dentro del menú tampoco cierra: hay que poder desplegarlo. */
/* Diccionario de la barra compartida — mismo mecanismo que documentacion/
   index.html (piloto, 12-ago-2026, ver assets/idioma.js). A nivel de
   fichero, no dentro de una IIFE: varias de las de abajo lo usan y cada una
   corre en su propio scope aislado. */
var TB_T = {
  cuentaTitle: { es:'Tu cuenta y tus avisos', en:'Your account and notifications' },
  cerrarSesion: { es:'Cerrar sesión', en:'Log out' },
  notificaciones: { es:'Notificaciones', en:'Notifications' },
  nadaNuevo: { es:'Nada nuevo por aquí.', en:'Nothing new here.' },
  cargando: { es:'Cargando…', en:'Loading…' },
  rolSuperAdmin: { es:'Super administrador', en:'Super admin' },
  rolAdmin: { es:'Administrador', en:'Admin' },
  rolAgente: { es:'Agente', en:'Agent' },
  hace: { es:'hace ', en:'' },          // ES antepone ("hace 3 min"), EN pospone ("3 min ago")
  minAgo: { es:' min', en:' min ago' },
  hAgo: { es:' h', en:' h ago' },
  ayer: { es:'ayer', en:'yesterday' },
  volverIntranet: { es:'← Intranet', en:'← Home' },
};
function tb(k) { return (TB_T[k] && TB_T[k][window.LW_IDIOMA]) || (TB_T[k] && TB_T[k].es) || k; }

(function () {
  var SEL = 'details.lw-menu, details.pv-menu';
  var LISTA = '.lw-menu-list, .pv-menu-list';

  function cerrarTodos(salvo) {
    document.querySelectorAll(SEL).forEach(function (d) { if (d !== salvo) d.open = false; });
  }

  document.addEventListener('click', function (e) {
    var menu = e.target.closest ? e.target.closest(SEL) : null;
    if (!menu) { cerrarTodos(null); return; }
    cerrarTodos(menu);
    var accion = e.target.closest(LISTA) && e.target.closest('button, a');
    if (accion && !accion.hasAttribute('data-keep')) menu.open = false;
  });

  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') cerrarTodos(null);
  });
})();

/* ============================================================================
   CAMPANA DE NOTIFICACIONES — 4-ago-2026
   ----------------------------------------------------------------------------
   Vive aquí y no en cada herramienta por lo mismo que el resto de este fichero:
   las siete comparten `.lw-topbar`, así que la campana se inyecta sola en todas
   y no hay siete copias que se vayan separando. Ninguna página se toca.

   DOS ORÍGENES, a propósito (ver contracts/sql/notificaciones.sql):
   · HECHOS — tabla `notificaciones`, escrita por disparadores. «CR00007 quedó
     firmado» pasó una vez y no cambia.
   · VENCIMIENTOS — se calculan AQUÍ, al leer. «Vence en 3 días» sería mentira
     dentro de una semana; guardarlo obligaría a un proceso que lo repasara cada
     día, que es justo lo que no queríamos tener encendido.

   El reparto lo hace la RLS en el caso de los hechos. Los vencimientos salen de
   `facturas` y `contrato_firmas`, que un agente PUEDE leer enteras, así que ahí
   el filtro por `creado_por` va explícito: sin él, un agente vería los cobros
   pendientes de toda la promotora.
   ============================================================================ */
/* CABECERA DE LA BARRA — 4-ago-2026
   «← Intranet», el logo y el rótulo estaban escritos a mano en las ocho
   herramientas: ocho copias de tres líneas idénticas salvo la ruta del logo, que
   en unas era relativa y en otras absoluta (y en el maquetador de dossiers venía
   con un `onerror` para taparlo cuando no cargaba). Ahora las pone esta función
   y cada página solo declara CÓMO SE LLAMA, con `data-titulo`.

   Se inserta al principio de la barra y no toca nada más: los controles propios
   de cada herramienta se quedan donde estaban y en el orden que estaban. */
(function () {
  var barra = document.querySelector('.lw-topbar');
  if (barra && !barra.querySelector('.lw-home')) {
    var cab = document.createDocumentFragment();
    var casa = document.createElement('a');
    casa.className = 'lw-home'; casa.href = '/intranet/'; casa.textContent = tb('volverIntranet');
    var logo = document.createElement('img');
    logo.className = 'lw-brand'; logo.alt = 'Lawang';
    logo.src = '/contracts/assets/brand/lawang-logo-v3-dark.png';
    logo.onerror = function () { this.remove(); };   // que falte el logo no parte la barra
    var rotulo = document.createElement('h1');
    rotulo.className = 'lw-title';
    rotulo.textContent = barra.dataset.titulo || (document.title.split('·').pop() || '').trim();
    cab.appendChild(casa); cab.appendChild(logo); cab.appendChild(rotulo);
    barra.insertBefore(cab, barra.firstChild);
  }
})();

/* SELECTOR DE IDIOMA DE INTERFAZ — 12-ago-2026
   `idioma.js` (cargado antes que este script, sin defer) ya resolvió
   `window.LW_IDIOMA` para cuando el <script> propio de la herramienta
   arrancó. Esto solo pinta el botón para CAMBIARLO — la lectura inicial no
   vive aquí (ver idioma.js y por qué está aparte de guard.js).
   Recarga la página al cambiar en vez de traducir en caliente: la
   traducción en vivo de una herramienta entera (tablas ya pintadas, cajones
   abiertos, formularios a medio rellenar) es mucho más frágil que perder el
   scroll y volver a cargar — mismo criterio que ya usa el toggle EUR/USD/AUD
   de portfolio.html. */
(function () {
  // Mismo fallback que la campana, más abajo: `.lw-topbar` en las ocho
  // herramientas, `[data-lw-usuario]` en el hub de la intranet, que tiene
  // cabecera propia.
  var barra = document.querySelector('.lw-topbar') || document.querySelector('[data-lw-usuario]');
  if (!barra || !window.lwSetIdioma) return;
  var boton = document.createElement('button');
  boton.type = 'button';
  boton.className = 'lw-btn lw-idioma';
  var otro = window.LW_IDIOMA === 'en' ? 'es' : 'en';
  boton.textContent = otro.toUpperCase();
  boton.title = otro === 'en' ? 'Switch interface to English' : 'Cambiar la interfaz a español';
  boton.addEventListener('click', function () {
    window.lwSetIdioma(otro);
    location.reload();
  });
  barra.appendChild(boton);
})();

(function () {
  var VENC_DIAS = 15;                                // se avisa desde 15 días antes
  var LIMITE = 40;

  /* 🔴 La primera versión pedía `window.LW_AUTH` y se iba en silencio si no
     estaba. Resultado: la campana no salía en Contratos ni en Facturas, que son
     las dos herramientas que MÁS se usan. No es que fallara — es que esas dos
     no pasan por `guard.js`: se montan su propio cliente y su propio
     `getSession()`. Tres puertas distintas para entrar a la misma suite.
     Mientras esas tres puertas no sean una (ver el panel de usuario), esto
     acepta cualquiera de ellas: `LW_AUTH` si guard.js ya resolvió, y si no el
     cliente que la herramienta publique en `LW_SB`. */
  function contexto() {
    if (window.LW_AUTH) return window.LW_AUTH;
    if (!window.LW_SB) return Promise.reject('sin cliente');
    var sb = window.LW_SB;
    return sb.auth.getSession().then(function (r) {
      var s = r && r.data && r.data.session;
      if (!s) return Promise.reject('sin sesión');
      return sb.from('usuarios').select('rol, notif_visto_hasta')
        .eq('user_id', s.user.id).maybeSingle()
        .then(function (f) { return { sb: sb, session: s, ficha: (f && f.data) || null }; });
    });
  }

  /* Y esperar al DOM: `contexto()` puede resolver mientras el navegador sigue
     leyendo el cuerpo de la página —Contratos son 3.000 líneas—, y entonces
     `.lw-topbar` todavía no existe y la campana no se llega a colgar de nada. */
  function cuandoHayaDOM(fn) {
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', fn);
    else fn();
  }

  function fecha(f) {
    if (!f) return '';
    var d = new Date(String(f).length === 10 ? f + 'T00:00:00' : f);
    var ms = Date.now() - d.getTime(), h = ms / 3600000;
    if (h < 1)  return tb('hace') + Math.max(1, Math.round(ms / 60000)) + tb('minAgo');
    if (h < 24) return tb('hace') + Math.round(h) + tb('hAgo');
    if (h < 48) return tb('ayer');
    return d.toLocaleDateString(window.LW_IDIOMA === 'en' ? 'en-GB' : 'es-ES', { day: '2-digit', month: 'short' });
  }
  function esc(v) {
    return String(v == null ? '' : v).replace(/[&<>"]/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c];
    });
  }
  var dias = function (f) { return f ? Math.round((new Date(f) - new Date()) / 86400000) : null; };

  contexto().then(function (ctx) { cuandoHayaDOM(function () { montar(ctx); }); })
            .catch(function () { /* sin sesión no hay campana; guard.js ya redirige */ });

  function montar(ctx) {
    var sb = ctx.sb, ficha = ctx.ficha || {};
    // `.lw-topbar` en las ocho herramientas; `[data-lw-usuario]` para el hub de
    // la intranet, que tiene cabecera propia y no la barra compartida
    var barra = document.querySelector('.lw-topbar') || document.querySelector('[data-lw-usuario]');
    if (!barra) return;
    var esAdmin = ficha.rol === 'admin' || ficha.rol === 'super_admin';
    var email = (ctx.session && ctx.session.user && ctx.session.user.email) || '';
    var vistoHasta = ficha.notif_visto_hasta ? new Date(ficha.notif_visto_hasta) : null;

    // se cuelga antes de "quién soy" si está, y si no al final de la barra
    /* PANEL DE USUARIO — quién eres, qué te ha pasado y salir, en un solo sitio
       y en las nueve pantallas. Antes cada herramienta pintaba su propio «👤
       nombre» y su propio botón Salir: nueve copias de lo mismo (once `signOut`
       contados) que había que tocar una a una para cambiar cualquier detalle.

       No se edita ninguna página: el panel se INYECTA y esconde el `.lw-who` y
       el botón de salir que la página ya trae. Se esconden y no se borran a
       propósito — el código de cada herramienta les sigue escribiendo dentro
       (`$('#who').textContent = ...`) y quitarlos del DOM lo rompería.

       Lo que NO lleva: un selector de herramientas. El catálogo vive en
       `/intranet/` con sus permisos, y una segunda lista aquí se quedaría vieja
       en cuanto se añadiera una herramienta. Para eso ya está «← Intranet». */
    var nombre = ficha.nombre || (email.split('@')[0] || 'Cuenta');
    var ROLES = { super_admin: tb('rolSuperAdmin'), admin: tb('rolAdmin'), agente: tb('rolAgente') };

    /* CAJÓN IZQUIERDO, no un desplegable. Se abre y se cierra EXACTAMENTE igual
       que el cajón de la derecha de la suite (`.sui-cajon`): mismo velo que
       atenúa sin tapar, misma duración (260ms), misma curva, mismo cierre con
       Escape o pulsando fuera, y en móvil sube desde abajo en vez de entrar de
       lado. Los valores están copiados en topbar.css y no heredados de
       suite.css porque suite.css solo lo cargan cuatro de las nueve pantallas.

       El disparador va el PRIMERO de la barra, a la izquierda, que es de donde
       sale el panel: un botón a la derecha que abre algo por la izquierda
       obliga a buscar con la vista lo que acaba de aparecer. */
    var boton = document.createElement('button');
    boton.type = 'button';
    boton.className = 'lw-usuario-btn';
    boton.setAttribute('aria-expanded', 'false');
    boton.title = tb('cuentaTitle');
    boton.innerHTML =
      '<span class="lw-usuario-ini" aria-hidden="true">' + esc(nombre.charAt(0).toUpperCase()) + '</span>' +
      '<span class="lw-usuario-nom">' + esc(nombre) + '</span>' +
      '<span class="lw-campana-n" hidden></span>';
    barra.insertBefore(boton, barra.firstChild);

    var velo = document.createElement('div');
    velo.className = 'lw-velo';
    var panel = document.createElement('aside');
    panel.className = 'lw-panel';
    panel.setAttribute('aria-label', tb('cuentaTitle'));
    panel.innerHTML =
      '<div class="lw-panel-cab">' +
        '<span class="lw-usuario-ini grande" aria-hidden="true">' + esc(nombre.charAt(0).toUpperCase()) + '</span>' +
        '<div class="lw-panel-quien"><b>' + esc(nombre) + '</b><span>' + esc(email) + '</span>' +
          (ficha.rol ? '<span class="lw-usuario-rol">' + esc(ROLES[ficha.rol] || ficha.rol) + '</span>' : '') +
        '</div>' +
        '<button type="button" class="lw-panel-x" aria-label="✕">✕</button>' +
      '</div>' +
      '<div class="lw-panel-cuerpo">' +
        '<div class="lw-usuario-seccion">' + tb('notificaciones') + '</div>' +
        '<div class="lw-campana-lista"><p class="lw-campana-vacio">' + tb('cargando') + '</p></div>' +
      '</div>' +
      '<div class="lw-panel-pie"><button type="button" class="lw-btn lw-usuario-salir">' + tb('cerrarSesion') + '</button></div>';
    document.body.appendChild(velo);
    document.body.appendChild(panel);

    // la página conserva su marcado, pero deja de enseñarlo: si no, el nombre y
    // el botón de salir salen dos veces
    var ancla = barra.querySelector('.lw-who');
    if (ancla) ancla.hidden = true;
    var salirViejo = barra.querySelector('#btnLogout, #out, #btnSalir');
    if (salirViejo) salirViejo.hidden = true;
    panel.querySelector('.lw-usuario-salir').addEventListener('click', function () {
      if (salirViejo) { salirViejo.click(); return; }   // cada herramienta sabe a dónde volver
      sb.auth.signOut().then(function () { location.replace('/entrar/'); });
    });

    var contador = boton.querySelector('.lw-campana-n');
    var abierto = false;
    function abrir(si) {
      abierto = si;
      panel.classList.toggle('on', si);
      velo.classList.toggle('on', si);
      boton.setAttribute('aria-expanded', si ? 'true' : 'false');
      if (si) marcarVistos();
    }
    // abrir el panel = dar los avisos por vistos. Se apaga el contador en el
    // momento y se guarda la marca en el servidor: la suite se usa desde el
    // móvil Y desde el escritorio, y en el navegador no viajaría de uno a otro.
    function marcarVistos() {
      if (contador.hidden) return;
      contador.hidden = true;
      vistoHasta = new Date();
      sb.rpc('marcar_notificaciones_leidas');
    }
    boton.addEventListener('click', function () { abrir(!abierto); });
    velo.addEventListener('click', function () { abrir(false); });
    panel.querySelector('.lw-panel-x').addEventListener('click', function () { abrir(false); });
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape' && abierto) abrir(false); });
    var lista = panel.querySelector('.lw-campana-lista');

    function pintar(avisos, sinLeer) {
      contador.textContent = sinLeer > 99 ? '99+' : sinLeer;
      contador.hidden = !sinLeer;
      lista.innerHTML = avisos.length
        ? avisos.map(function (a) {
            return '<a class="lw-aviso' + (a.nuevo ? ' nuevo' : '') + '" href="' + esc(a.enlace || '#') + '">' +
                   '<span class="lw-aviso-t">' + esc(a.titulo) + '</span>' +
                   (a.detalle ? '<span class="lw-aviso-d">' + esc(a.detalle) + '</span>' : '') +
                   '<span class="lw-aviso-c">' + esc(fecha(a.cuando)) + '</span></a>';
          }).join('')
        : '<p class="lw-campana-vacio">' + tb('nadaNuevo') + '</p>';
    }

    function cargar() {
      var q = sb.from('notificaciones')
        .select('tipo,titulo,detalle,enlace,creado_en')
        .order('creado_en', { ascending: false }).limit(LIMITE);

      // Vencimientos: facturas con fecha puesta y sin anular. `venc` vive dentro
      // del jsonb, igual que en Operaciones — no hay columna propia.
      var qf = sb.from('facturas')
        .select('numero,total,moneda,contrato_id,creado_por,anulada,tipo,venc:datos->fields->>fecha_vencimiento')
        .limit(200);
      var qs = sb.from('contrato_firmas')
        .select('firmante_nombre,estado,expira_en,contrato_id,contratos(numero,creado_por)')
        .eq('estado', 'pendiente').limit(100);

      Promise.all([q, qf, qs]).then(function (r) {
        var avisos = (r[0].data || []).map(function (n) {
          return { titulo: n.titulo, detalle: n.detalle, enlace: n.enlace, cuando: n.creado_en,
                   nuevo: !vistoHasta || new Date(n.creado_en) > vistoHasta };
        });

        (r[1].data || []).forEach(function (f) {
          if (f.anulada || f.tipo === 'proforma' || f.tipo === 'recibi' || !f.venc) return;
          if (!esAdmin && f.creado_por !== email) return;   // la RLS aquí no filtra: deja leer todas
          var d = dias(f.venc);
          if (d === null || d > VENC_DIAS) return;
          avisos.push({
            titulo: 'Factura ' + (f.numero || 'sin nº') + (d < 0 ? ' vencida hace ' + (-d) + ' d'
                    : d === 0 ? ' vence hoy' : ' vence en ' + d + ' d'),
            detalle: (f.total || '') + ' ' + (f.moneda || '') + ' sin cobrar',
            enlace: f.contrato_id ? '/operaciones/?contrato=' + f.contrato_id : '/facturas/',
            cuando: f.venc, nuevo: d <= 5,
          });
        });

        (r[2].data || []).forEach(function (s) {
          var c = s.contratos || {};
          if (!esAdmin && c.creado_por !== email) return;
          var d = dias(s.expira_en);
          if (d === null || d > VENC_DIAS) return;
          avisos.push({
            titulo: 'Enlace de firma de ' + (c.numero || 'un contrato') +
                    (d < 0 ? ' caducado' : d === 0 ? ' caduca hoy' : ' caduca en ' + d + ' d'),
            detalle: s.firmante_nombre || '',
            enlace: '/operaciones/?contrato=' + s.contrato_id,
            cuando: s.expira_en, nuevo: d <= 5,
          });
        });

        avisos.sort(function (a, b) { return new Date(b.cuando) - new Date(a.cuando); });
        pintar(avisos.slice(0, LIMITE), avisos.filter(function (a) { return a.nuevo; }).length);
      });
    }

    cargar();
  }
})();

/* ============================================================================
   MENÚ LATERAL — V2, 15-ago-2026 (petición del owner)
   ----------------------------------------------------------------------------
   Antes, saltar de Facturas a Compradores eran DOS pasos y una carga entera del
   hub por el medio. Ahora es un clic desde cualquier herramienta.

   POR QUÉ RIEL Y NO BARRA FIJA. Estas pantallas son tablas densas y el cajón de
   detalle ya ocupa el 70% del ancho; una columna permanente compite justo donde
   el espacio escasea. Y por los números: un agente tiene 2,6 herramientas de
   media, así que una columna abierta para tres entradas no sale a cuenta.
   Así que: PLEGADO por defecto dentro de las herramientas (riel de iconos, 56px,
   se ve dónde estás) y ABIERTO en el hub, que es donde uno elige a dónde va.

   NO DUPLICA EL CATÁLOGO. Lee `LW_HERRAMIENTAS` de assets/herramientas.js, la
   misma lista que pinta el hub. Esa era la objeción por escrito que este fichero
   tenía para no llevar selector -- «una segunda lista aquí se quedaría vieja» --
   y era correcta: se resuelve mudando la lista, no ignorándola.

   Si `herramientas.js` no está cargado, no se pinta nada y la barra queda como
   estaba. Una herramienta que no lo incluya no se rompe.
============================================================================ */
(function () {
  if (typeof LW_HERRAMIENTAS === 'undefined') return;
  var LLAVE = 'lw_rail_abierto';
  var enHub = /^\/intranet\/?$/.test(location.pathname);

  function pintar(ficha) {
    if (document.getElementById('lwRail')) return;
    var permitidas = LW_HERRAMIENTAS.filter(function (t) { return lwPermitida(t, ficha); });
    // Con una sola herramienta no hay a dónde saltar: la barra sobra.
    if (permitidas.length < 2) return;

    var guardado = null;
    try { guardado = localStorage.getItem(LLAVE); } catch (e) {}
    // El hub abre por defecto; dentro de una herramienta, plegado. Lo que el
    // usuario haya elegido a mano manda sobre las dos cosas.
    var abierto = guardado === null ? enHub : guardado === '1';

    var rail = document.createElement('nav');
    rail.id = 'lwRail';
    rail.className = 'lw-rail' + (abierto ? ' abierto' : '');
    rail.setAttribute('aria-label', 'Herramientas');

    var btn = document.createElement('button');
    btn.type = 'button'; btn.className = 'lw-rail-tog';
    btn.setAttribute('aria-expanded', String(abierto));
    btn.innerHTML = '<i class="ph ph-list"></i><span>Herramientas</span>';
    btn.title = 'Plegar o desplegar el menú';
    rail.appendChild(btn);

    var aqui = location.pathname.replace(/\/$/, '');
    permitidas.forEach(function (t) {
      var a = document.createElement('a');
      a.className = 'lw-rail-i';
      a.href = t.href;
      // `title` SIEMPRE, no solo plegado: plegado es la única etiqueta que hay, y
      // abierto sigue sirviendo a quien navega con teclado.
      a.title = t.nombre;
      var suyo = t.href.replace(/\/$/, '');
      if (aqui === suyo || (suyo && aqui.indexOf(suyo) === 0)) a.classList.add('aqui');
      a.innerHTML = '<i class="ph ' + (t.icon || 'ph-circle') + '"></i><span>' + t.nombre + '</span>';
      rail.appendChild(a);
    });

    document.body.appendChild(rail);
    document.body.classList.add('con-rail');
    if (abierto) document.body.classList.add('rail-abierto');

    btn.addEventListener('click', function () {
      var ab = rail.classList.toggle('abierto');
      document.body.classList.toggle('rail-abierto', ab);
      btn.setAttribute('aria-expanded', String(ab));
      try { localStorage.setItem(LLAVE, ab ? '1' : '0'); } catch (e) {}
    });
  }

  // Se cuelga de la misma promesa que el resto de la barra: sin ficha no se
  // sabe qué herramientas puede ver esta persona, y enseñarle puertas que le
  // van a rebotar es peor que no enseñar ninguna.
  if (window.LW_AUTH) window.LW_AUTH.then(function (ctx) { pintar((ctx && ctx.ficha) || null); }).catch(function () {});
})();
