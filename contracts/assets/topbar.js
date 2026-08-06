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
    casa.className = 'lw-home'; casa.href = '/intranet/'; casa.textContent = '← Intranet';
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
    if (h < 1)  return 'hace ' + Math.max(1, Math.round(ms / 60000)) + ' min';
    if (h < 24) return 'hace ' + Math.round(h) + ' h';
    if (h < 48) return 'ayer';
    return d.toLocaleDateString('es-ES', { day: '2-digit', month: 'short' });
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
    var ROLES = { super_admin: 'Super administrador', admin: 'Administrador', agente: 'Agente' };

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
    boton.title = 'Tu cuenta y tus avisos';
    boton.innerHTML =
      '<span class="lw-usuario-ini" aria-hidden="true">' + esc(nombre.charAt(0).toUpperCase()) + '</span>' +
      '<span class="lw-usuario-nom">' + esc(nombre) + '</span>' +
      '<span class="lw-campana-n" hidden></span>';
    barra.insertBefore(boton, barra.firstChild);

    var velo = document.createElement('div');
    velo.className = 'lw-velo';
    var panel = document.createElement('aside');
    panel.className = 'lw-panel';
    panel.setAttribute('aria-label', 'Tu cuenta');
    panel.innerHTML =
      '<div class="lw-panel-cab">' +
        '<span class="lw-usuario-ini grande" aria-hidden="true">' + esc(nombre.charAt(0).toUpperCase()) + '</span>' +
        '<div class="lw-panel-quien"><b>' + esc(nombre) + '</b><span>' + esc(email) + '</span>' +
          (ficha.rol ? '<span class="lw-usuario-rol">' + esc(ROLES[ficha.rol] || ficha.rol) + '</span>' : '') +
        '</div>' +
        '<button type="button" class="lw-panel-x" aria-label="Cerrar">✕</button>' +
      '</div>' +
      '<div class="lw-panel-cuerpo">' +
        '<div class="lw-usuario-seccion">Notificaciones</div>' +
        '<div class="lw-campana-lista"><p class="lw-campana-vacio">Cargando…</p></div>' +
      '</div>' +
      '<div class="lw-panel-pie"><button type="button" class="lw-btn lw-usuario-salir">Cerrar sesión</button></div>';
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
        : '<p class="lw-campana-vacio">Nada nuevo por aquí.</p>';
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
          if (f.anulada || f.tipo === 'proforma' || !f.venc) return;
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
