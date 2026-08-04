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
(function () {
  if (!window.LW_AUTH) return;                       // login y páginas sin sesión

  var VENC_DIAS = 15;                                // se avisa desde 15 días antes
  var LIMITE = 40;

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

  window.LW_AUTH.then(function (ctx) {
    var sb = ctx.sb, ficha = ctx.ficha || {};
    var barra = document.querySelector('.lw-topbar');
    if (!barra) return;
    var esAdmin = ficha.rol === 'admin' || ficha.rol === 'super_admin';
    var email = (ctx.session && ctx.session.user && ctx.session.user.email) || '';
    var vistoHasta = ficha.notif_visto_hasta ? new Date(ficha.notif_visto_hasta) : null;

    // se cuelga antes de "quién soy" si está, y si no al final de la barra
    var caja = document.createElement('details');
    caja.className = 'lw-menu lw-campana';
    caja.innerHTML =
      '<summary class="lw-campana-btn" title="Notificaciones" aria-label="Notificaciones">' +
        '<span aria-hidden="true">🔔</span><span class="lw-campana-n" hidden></span></summary>' +
      '<div class="lw-menu-list lw-campana-lista"><p class="lw-campana-vacio">Cargando…</p></div>';
    var ancla = barra.querySelector('.lw-who') || barra.querySelector('.lw-spacer');
    if (ancla && ancla.classList.contains('lw-who')) barra.insertBefore(caja, ancla);
    else barra.appendChild(caja);

    var contador = caja.querySelector('.lw-campana-n');
    var lista = caja.querySelector('.lw-campana-lista');

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

    // abrir el panel = darlos por vistos. Se apaga el contador en el momento y
    // se guarda la marca en el servidor: la suite se usa desde el móvil Y desde
    // el escritorio, y en el navegador la marca no viajaría de uno a otro.
    caja.addEventListener('toggle', function () {
      if (!caja.open || contador.hidden) return;
      contador.hidden = true;
      vistoHasta = new Date();
      sb.rpc('marcar_notificaciones_leidas');
    });

    cargar();
  }).catch(function () { /* sin sesión no hay campana; guard.js ya redirige */ });
})();
