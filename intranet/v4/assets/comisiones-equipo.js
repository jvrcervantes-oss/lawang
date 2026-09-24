/* «Ventas del equipo» — pestaña Reparto (intranet/v4/reparto/), 24-sep-2026 (owner).
 *
 *  · El manager (o admin) dice quién hizo de SETTER y de TEAM LEAD en cada venta de su
 *    equipo: cobran de su bolsillo, igual que el closer (acuerdo privado; Lawang no retiene).
 *  · El closer reclama una venta como PROPIA (cliente suyo, no un lead del equipo). Si su
 *    manager la aprueba, cobra la fee entera del manager, la paga Lawang, y el equipo cobra 0.
 *
 *  Todo lo decide la base (RPC SECURITY DEFINER: comision_rol_asignar, venta_propia_reclamar,
 *  venta_propia_retirar, venta_propia_resolver; lectura por comisiones_ventas_equipo). Aquí
 *  solo se pinta y se ofrece lo que la base aceptaría. Ningún dato real en el marcado: este
 *  repo es público; todo entra en tiempo de ejecución detrás de guard.js.
 */
(function () {
  if (!/\/v4\/reparto\//.test(location.pathname)) return;
  if (!window.LW_AUTH) return;

  var ROL = { setter: 'Setter', team_lead: 'Team Lead' };
  var EST = { pendiente: 'Pendiente de tu manager', aprobada: 'Aprobada', rechazada: 'Rechazada', retirada: 'Retirada' };
  var TONO = { pendiente: ['#FFF1D6', '#7A5200'], aprobada: ['#D3EABB', '#0F2003'], rechazada: ['#FFDAD6', '#93000A'], retirada: ['#E4E2DD', '#44483F'] };

  function esc(v) {
    return String(v == null ? '' : v).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function fecha(x) { return x ? new Date(x).toLocaleDateString('es-ES', { day: 'numeric', month: 'short', year: 'numeric' }) : '—'; }
  function pill(txt, tono) {
    var t = tono || ['#E4E2DD', '#44483F'];
    return '<span style="display:inline-block;padding:2px 10px;border-radius:999px;background:' + t[0] + ';color:' + t[1] +
      ';font:600 11px \'Neue Kabel\',sans-serif;white-space:nowrap">' + esc(txt) + '</span>';
  }
  // nunca alert(): un diálogo nativo congela la extensión de Chrome (dialogo.js)
  function aviso(msg) {
    if (window.lwConfirmar) window.lwConfirmar({ titulo: 'Ventas del equipo', cuerpo: esc(msg), confirmar: 'Entendido', cancelar: false });
    else console.warn('[ventas del equipo]', msg);
  }
  function mensajeError(e) { return (e && (e.message || e.details)) || 'no se ha podido guardar'; }

  window.LW_AUTH.then(function (aut) {
    var sb = aut.sb;
    var yo = ((aut.session && aut.session.user && aut.session.user.email) || '').toLowerCase();
    var rol = (aut.ficha && aut.ficha.rol) || '';
    var esAdmin = rol === 'admin' || rol === 'super_admin';

    Promise.all([
      sb.rpc('comisiones_ventas_equipo'),
      sb.from('equipo_miembros').select('equipo_id,closer_email,desde,hasta'),
      sb.from('usuarios').select('nombre,email')
    ]).then(function (r) {
      if (r[0].error) { console.error('[ventas del equipo]', r[0].error); return; }
      var ventas = r[0].data || [];
      if (!ventas.length) return;   // sin ventas de equipo que ver: el bloque no aparece
      var miembros = (r[1] && r[1].data) || [];
      var nombre = {};
      ((r[2] && r[2].data) || []).forEach(function (u) { if (u.email) nombre[u.email.toLowerCase()] = u.nombre || u.email; });
      function quien(e) { return e ? (nombre[e.toLowerCase()] || e) : '—'; }
      pinta(ventas, miembros, quien);
    });

    function pinta(ventas, miembros, quien) {
      var gestiono = ventas.some(function (v) { return v.soy_manager; }) || esAdmin;
      var pendientes = ventas.filter(function (v) { return v.reclamacion_estado === 'pendiente'; });
      var sec = document.createElement('section');
      sec.id = 'lw-ventas-equipo';
      sec.className = 'bg-surface-container-lowest rounded-xl p-5 shadow-sm flex flex-col gap-3';
      sec.style.marginBottom = '24px';
      var intro = gestiono
        ? 'Quién hizo de Setter y de Team Lead en cada venta (lo pagas tú, como al closer: acuerdo privado, Lawang no retiene nada) y las reclamaciones de venta propia de tu equipo.'
        : 'Tus ventas de equipo. Si el cliente es tuyo —no un lead del equipo— puedes reclamar la venta como propia: si tu manager la aprueba, cobras su comisión entera y la paga Lawang.';
      sec.innerHTML =
        '<div style="display:flex;flex-wrap:wrap;align-items:baseline;justify-content:space-between;gap:8px">' +
          '<h2 class="font-headline-sm text-headline-sm text-on-surface" style="margin:0">Ventas del equipo</h2>' +
          (pendientes.length && gestiono ? pill(pendientes.length + (pendientes.length === 1 ? ' reclamación por resolver' : ' reclamaciones por resolver'), TONO.pendiente) : '') +
        '</div>' +
        '<p class="font-body-md text-body-md text-on-surface-variant" style="margin:0">' + esc(intro) + '</p>' +
        '<div style="overflow-x:auto"><table class="w-full text-left" style="border-collapse:collapse;min-width:640px"><thead><tr>' +
          ['Venta', 'Closer', 'Setter', 'Team Lead', 'Venta propia'].map(function (h) {
            return '<th class="px-4 py-2 font-label-md text-[11px] uppercase tracking-wider text-on-surface-variant">' + h + '</th>';
          }).join('') +
        '</tr></thead><tbody data-lw-ve></tbody></table></div>';
      var tb = sec.querySelector('[data-lw-ve]');
      // primero lo que espera una decisión
      ventas.slice().sort(function (a, b) {
        return (b.reclamacion_estado === 'pendiente') - (a.reclamacion_estado === 'pendiente');
      }).forEach(function (v) {
        var tr = document.createElement('tr');
        tr.className = 'border-b border-outline-variant/30';
        tr.style.cursor = 'pointer';
        tr.innerHTML =
          '<td class="px-4 py-3 font-label-md text-label-md text-on-surface whitespace-nowrap">' + esc(v.numero || '—') +
            '<div class="font-body-sm text-body-sm text-outline">' + esc([v.proyecto_nombre, v.equipo_nombre].filter(Boolean).join(' · ')) + '</div></td>' +
          '<td class="px-4 py-3 font-body-md text-body-md text-on-surface-variant">' + esc(quien(v.closer_email)) + '</td>' +
          '<td class="px-4 py-3 font-body-md text-body-md text-on-surface-variant">' + esc(v.setter_email ? quien(v.setter_email) : '—') + '</td>' +
          '<td class="px-4 py-3 font-body-md text-body-md text-on-surface-variant">' + esc(v.team_lead_email ? quien(v.team_lead_email) : '—') + '</td>' +
          '<td class="px-4 py-3">' + (v.reclamacion_estado ? pill(EST[v.reclamacion_estado] || v.reclamacion_estado, TONO[v.reclamacion_estado]) : '<span class="font-body-sm text-body-sm text-outline">—</span>') + '</td>';
        tr.addEventListener('click', function () { abre(v, miembros, quien); });
        tb.appendChild(tr);
      });

      var tabla = document.getElementById('lw-filas-equipo');
      var ancla = tabla && (tabla.closest('[data-lw-panel]') || tabla.closest('section'));
      if (ancla && ancla.parentNode) ancla.parentNode.insertBefore(sec, ancla);
      else (document.querySelector('main') || document.body).appendChild(sec);
    }

    function abre(v, miembros, quien) {
      if (!window.lwCajon || !window.lwCajonHtml) { aviso('La ficha aún no ha cargado — prueba de nuevo en un segundo.'); return; }
      var H = window.lwCajonHtml;
      var soyCloser = v.closer_email === yo;
      var gestiono = (v.soy_manager || esAdmin) && !soyCloser;
      var viva = v.reclamacion_estado === 'pendiente' || v.reclamacion_estado === 'aprobada';
      var propiaAprobada = v.reclamacion_estado === 'aprobada';
      var fechaEq = v.fecha_venta || new Date().toISOString().slice(0, 10);
      var delEquipo = miembros.filter(function (m) {
        return m.equipo_id === v.equipo_id && m.desde <= fechaEq && (!m.hasta || m.hasta >= fechaEq);
      }).map(function (m) { return (m.closer_email || '').toLowerCase(); })
        .filter(function (e, i, a) { return e && a.indexOf(e) === i && e !== yo && e !== v.closer_email; });

      var cuerpo = H.seccion('La venta',
        H.dato('Venta', [v.numero, v.proyecto_nombre].filter(Boolean).join(' · ')) +
        H.dato('Equipo', v.equipo_nombre) +
        H.dato('Manager', quien(v.manager_email)) +
        H.dato('Closer', quien(v.closer_email)) +
        H.dato('Fecha de la venta', v.fecha_venta ? fecha(v.fecha_venta) : fecha(v.creada) + ' (equipo: el de hoy)'));

      if (v.reclamacion_estado) {
        cuerpo += H.seccion('Venta propia',
          H.dato('Estado', pill(EST[v.reclamacion_estado] || v.reclamacion_estado, TONO[v.reclamacion_estado]), { html: 1 }) +
          H.dato('Pedida por', quien(v.reclamacion_solicitante)) +
          H.dato('Por qué es suya', v.reclamacion_motivo) +
          H.dato('Respuesta', v.reclamacion_resolucion) +
          H.dato('Fecha', fecha(v.reclamacion_en)));
      }

      var acciones = [];
      if (gestiono && !propiaAprobada) {
        var opts = function (actual) {
          var lista = delEquipo.slice();
          if (actual && lista.indexOf(actual) === -1) lista.unshift(actual);
          return '<option value="">— nadie —</option>' + lista.map(function (e) {
            return '<option value="' + esc(e) + '"' + (e === actual ? ' selected' : '') + '>' + esc(quien(e)) + '</option>';
          }).join('');
        };
        var sel = 'width:100%;padding:9px 10px;border:1px solid #8A8474;border-radius:8px;background:#fff;font:500 14px \'Neue Kabel\',sans-serif';
        cuerpo += H.seccion('Roles de la venta',
          '<label style="display:grid;gap:4px;font:600 12px \'Neue Kabel\',sans-serif">Setter<select data-ve-rol="setter" style="' + sel + '">' + opts(v.setter_email) + '</select></label>' +
          '<label style="display:grid;gap:4px;font:600 12px \'Neue Kabel\',sans-serif">Team Lead<select data-ve-rol="team_lead" style="' + sel + '">' + opts(v.team_lead_email) + '</select></label>' +
          H.nota('Cobran según la condición de su rol en Condiciones, en cuanto la venta cumpla el tramo. Lo pagas tú, igual que al closer: Lawang no lo gestiona ni retiene nada.'));
        acciones.push({ texto: 'Guardar roles', tono: 'primario', onClick: function (ev, w) {
          var cambios = [];
          w.querySelectorAll('[data-ve-rol]').forEach(function (s) {
            var r2 = s.getAttribute('data-ve-rol');
            var antes = (r2 === 'setter' ? v.setter_email : v.team_lead_email) || '';
            if (s.value !== antes) cambios.push([r2, s.value || null]);
          });
          if (!cambios.length) { aviso('No has cambiado nada.'); return; }
          cambios.reduce(function (p, c) {
            return p.then(function () {
              return sb.rpc('comision_rol_asignar', { p_raiz: v.raiz_id, p_rol: c[0], p_email: c[1] }).then(function (r) {
                if (r.error) throw r.error;
              });
            });
          }, Promise.resolve()).then(function () { location.reload(); }, function (e) { aviso(mensajeError(e)); });
        } });
      }

      var motivoCaja = function (etq) {
        return '<label style="display:grid;gap:4px;font:600 12px \'Neue Kabel\',sans-serif">' + esc(etq) +
          '<textarea data-ve-motivo rows="3" style="width:100%;padding:9px 10px;border:1px solid #8A8474;border-radius:8px;font:500 14px \'Neue Kabel\',sans-serif"></textarea></label>';
      };
      var leeMotivo = function (w) { var t = w.querySelector('[data-ve-motivo]'); return t ? t.value.trim() : ''; };

      if (gestiono && v.reclamacion_estado === 'pendiente') {
        cuerpo += H.seccion('Resolver la reclamación',
          H.nota('Si la apruebas, ' + quien(v.closer_email) + ' cobra la comisión entera de manager de esta venta, la paga Lawang, y tú y el resto del equipo (closer, setter, team lead) no cobráis nada de ella. Lo ya generado y pendiente se anula con su motivo.') +
          motivoCaja('Motivo (obligatorio para rechazar)'));
        acciones.push({ texto: 'Aprobar venta propia', tono: 'primario', onClick: function (ev, w) {
          var m = leeMotivo(w);
          var sigue = window.lwConfirmar
            ? window.lwConfirmar({ titulo: '¿Aprobar la venta propia?', confirmar: 'Aprobar',
                cuerpo: esc(quien(v.closer_email) + ' cobrará la comisión entera de manager de ' + (v.numero || 'esta venta') + ' y el equipo no cobrará nada de ella. No se deshace desde aquí.') })
            : Promise.resolve(true);
          sigue.then(function (ok) {
            if (!ok) return;
            sb.rpc('venta_propia_resolver', { p_id: v.reclamacion_id, p_aprobar: true, p_motivo: m || null })
              .then(function (r) { if (r.error) aviso(mensajeError(r.error)); else location.reload(); });
          });
        } });
        acciones.push({ texto: 'Rechazar', tono: 'peligro', onClick: function (ev, w) {
          var m = leeMotivo(w);
          if (!m) { aviso('Para rechazar escribe el motivo: se le enseña tal cual.'); return; }
          sb.rpc('venta_propia_resolver', { p_id: v.reclamacion_id, p_aprobar: false, p_motivo: m })
            .then(function (r) { if (r.error) aviso(mensajeError(r.error)); else location.reload(); });
        } });
      }

      if (soyCloser && !v.soy_manager && !viva) {
        cuerpo += H.seccion('Reclamar como venta propia',
          H.nota('Úsalo solo si el cliente es tuyo (tu agenda, tus conocidos), no un lead del equipo. Si ' + quien(v.manager_email) + ' lo aprueba, cobras su comisión entera de esta venta, la paga Lawang y tu equipo no cobra nada de ella.') +
          motivoCaja('De dónde viene el cliente'));
        acciones.push({ texto: 'Reclamar venta propia', tono: 'primario', onClick: function (ev, w) {
          var m = leeMotivo(w);
          if (!m) { aviso('Explica de dónde viene el cliente: es lo que verá tu manager.'); return; }
          sb.rpc('venta_propia_reclamar', { p_raiz: v.raiz_id, p_motivo: m })
            .then(function (r) { if (r.error) aviso(mensajeError(r.error)); else location.reload(); });
        } });
      }
      if (soyCloser && v.reclamacion_estado === 'pendiente' && v.reclamacion_solicitante === yo) {
        acciones.push({ texto: 'Retirar la reclamación', tono: 'peligro', onClick: function () {
          sb.rpc('venta_propia_retirar', { p_id: v.reclamacion_id })
            .then(function (r) { if (r.error) aviso(mensajeError(r.error)); else location.reload(); });
        } });
      }
      acciones.push({ texto: 'Cerrar', cerrar: true });

      window.lwCajon({
        sub: 'Venta de equipo',
        titulo: v.numero || 'Venta',
        bajoTitulo: propiaAprobada ? 'Venta propia aprobada: la cobra ' + quien(v.reclamacion_solicitante) + ' entera.' : '',
        cuerpo: cuerpo, acciones: acciones
      });
    }
  });
})();
