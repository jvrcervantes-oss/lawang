/* Solicitudes de alta y contactos de referidos (24-sep-2026).
 *
 * Llegan desde la guía /formacion/ por la edge pública `alta-colaborador`:
 *   · COMERCIAL (5 %) → `solicitudes_colaborador`. Nadie entra a la intranet sin
 *     el clic «Activar» de aquí (revisión previa #61): la cuenta la crea la edge
 *     admin-usuarios, accion 'activar_solicitud', y el comercial recibe un correo
 *     para crear su contraseña.
 *   · REFERIDO (1 %) → `referidos_contactos`, sin cuenta. Aquí solo se marca si
 *     ya está en el CRM o se descarta; `referido_email` es la atribución.
 *
 * Fichero propio de la página (no datos.js/editores.js): lo pinta todo con
 * textContent — nada de lo que escribió un desconocido en un formulario público
 * llega a innerHTML.
 */
(function () {
  'use strict';
  var EDGE = 'https://vtulllundrfennhjddhc.supabase.co/functions/v1/admin-usuarios';
  var KEY = 'sb_publishable_B_ot_6lNVRLiWiEMtApYOQ_3Ho3xNUg';
  var HERR_COMERCIAL = [['leads', 'CRM'], ['contratos', 'Generador de contratos'], ['compradores', 'Compradores'],
                        ['reservas', 'Reservas'], ['comisiones_reparto', 'Mis comisiones']];
  var TIPOS = [['carta_reserva', 'Carta de Reserva'], ['reserva_parcela', 'Bloqueo de Parcela'],
               ['construccion', 'Construcción'], ['carta_reserva_hak_sewa', 'Carta de Reserva (Hak Sewa)'],
               ['carta_reserva_pma', 'Carta de Reserva Condicionada (PT PMA)']];
  var TIPOS_DEF = ['carta_reserva', 'reserva_parcela', 'construccion'];

  function el(tag, cls, txt) { var e = document.createElement(tag); if (cls) e.className = cls; if (txt != null) e.textContent = txt; return e; }
  function fecha(s) { try { return new Date(s).toLocaleString('es-ES', { dateStyle: 'medium', timeStyle: 'short' }); } catch (e) { return s; } }
  function espera(cb, n) {
    n = n || 0;
    if (window.LW_SB && document.querySelector('main')) return cb(window.LW_SB);
    if (n > 100) return;
    setTimeout(function () { espera(cb, n + 1); }, 150);
  }
  function llama(sb, cuerpo) {
    return sb.auth.getSession().then(function (r) {
      var t = r && r.data && r.data.session && r.data.session.access_token;
      if (!t) throw new Error('sesión no encontrada');
      return fetch(EDGE, { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + t, apikey: KEY },
                           body: JSON.stringify(cuerpo) }).then(function (x) { return x.json(); });
    });
  }
  var TXT_ERR = {
    elige_tipos_de_contrato: 'Marca al menos un tipo de contrato.', elige_proyectos: 'Marca al menos un proyecto.',
    ya_es_usuario: 'Ese email ya es usuario de la intranet.',
    email_ya_existe_en_auth: 'Ese email ya tiene una cuenta (por ejemplo, de comprador en el portal). No se convierte en agente: dale de alta a mano con otro email.',
  };

  espera(function (sb) {
    var cont = document.querySelector('main > div') || document.querySelector('main');
    var sec = el('section', 'bg-surface-container-lowest rounded-xl p-6 shadow-sm');
    sec.id = 'lwSolicitudes';
    cont.appendChild(sec);
    var sec2 = el('section', 'bg-surface-container-lowest rounded-xl p-6 shadow-sm');
    sec2.id = 'lwReferidos';
    cont.appendChild(sec2);
    var proyectos = [];
    var errProy = '';
    sb.from('proyectos').select('id,nombre').eq('activo', true).order('nombre').then(function (r) {
      proyectos = r.data || []; errProy = r.error ? r.error.message : ''; pintaSolicitudes(); });
    pintaReferidos();

    function cabecera(host, titulo, sub) {
      host.innerHTML = '';
      host.appendChild(el('h2', 'font-headline-sm text-headline-sm text-volcanic-ash font-bold', titulo));
      host.appendChild(el('p', 'font-body-sm text-body-sm text-on-surface-variant mt-1 mb-4', sub));
    }

    function pintaSolicitudes() {
      sb.from('solicitudes_colaborador').select('*').order('creado_at', { ascending: false }).limit(60).then(function (r) {
        cabecera(sec, 'Solicitudes de alta de comerciales',
          'Llegan desde la guía de formación con el email verificado. Nadie entra en la intranet hasta que pulsas «Activar»: entonces se crea su usuario y le llega un correo para crear su contraseña.');
        if (r.error) { sec.appendChild(el('p', 'text-error', 'No se han podido cargar: ' + r.error.message)); return; }
        var filas = r.data || [];
        var pend = filas.filter(function (s) { return s.estado === 'pendiente'; });
        if (!pend.length) sec.appendChild(el('p', 'font-body-md text-on-surface-variant', 'No hay solicitudes pendientes.'));
        pend.forEach(function (s) { sec.appendChild(tarjeta(s)); });
        var resto = filas.filter(function (s) { return s.estado !== 'pendiente'; });
        if (resto.length) {
          var det = el('details', 'mt-4');
          det.appendChild(el('summary', 'cursor-pointer font-label-md text-label-md text-on-surface-variant', 'Ya revisadas (' + resto.length + ')'));
          resto.forEach(function (s) {
            var d = el('div', 'flex flex-wrap items-center gap-3 py-2 border-b border-outline/10 font-body-sm text-body-sm');
            d.appendChild(el('span', 'font-semibold', s.nombre));
            d.appendChild(el('span', 'text-on-surface-variant', s.email));
            d.appendChild(el('span', 'px-2 py-0.5 rounded-full ' + (s.estado === 'activada' ? 'bg-primary-container text-on-primary' : 'bg-surface-container-high'), s.estado));
            d.appendChild(el('span', 'text-outline', (s.revisado_por || '') + ' · ' + fecha(s.revisado_en)));
            if (s.estado === 'activada') {
              var re = el('button', 'ml-auto px-3 py-1 rounded-full border border-outline/40 hover:bg-surface-container-high', 'Reenviar enlace de contraseña');
              re.type = 'button';
              re.addEventListener('click', function () {
                re.disabled = true;
                llama(sb, { accion: 'reenviar_enlace', solicitud_id: s.id }).then(function (x) {
                  re.textContent = x && x.ok ? 'Enlace reenviado' : 'No se pudo reenviar'; });
              });
              d.appendChild(re);
            }
            det.appendChild(d);
          });
          sec.appendChild(det);
        }
      });
    }

    function tarjeta(s) {
      var c = el('div', 'border border-outline/20 rounded-xl p-4 mb-3 bg-surface');
      var top = el('div', 'flex flex-wrap items-baseline gap-3');
      top.appendChild(el('span', 'font-label-md text-label-md text-on-surface', s.nombre));
      top.appendChild(el('span', 'font-body-sm text-body-sm text-on-surface-variant', s.email + (s.telefono ? ' · ' + s.telefono : '') + (s.pais ? ' · ' + s.pais : '')));
      top.appendChild(el('span', 'ml-auto font-body-sm text-body-sm text-outline', fecha(s.creado_at)));
      c.appendChild(top);
      if (s.mensaje) c.appendChild(el('p', 'font-body-sm text-body-sm text-on-surface-variant mt-2', '«' + s.mensaje + '»'));

      var form = el('div', 'mt-3 grid gap-3 md:grid-cols-3');
      function grupo(titulo, items, nombre, marcados, fijo) {
        var g = el('div', '');
        g.appendChild(el('div', 'font-body-sm text-body-sm font-semibold mb-1', titulo));
        items.forEach(function (it) {
          var l = el('label', 'flex items-center gap-2 font-body-sm text-body-sm');
          var i = document.createElement('input'); i.type = 'checkbox'; i.name = nombre; i.value = it[0];
          i.checked = marcados.indexOf(it[0]) >= 0; if (fijo) i.disabled = false;
          l.appendChild(i); l.appendChild(el('span', '', it[1])); g.appendChild(l);
        });
        return g;
      }
      if (errProy || !proyectos.length) form.appendChild(el('div', 'text-error font-body-sm text-body-sm',
        'No se han podido cargar los proyectos' + (errProy ? ' (' + errProy + ')' : '') + '. Recarga la página antes de activar.'));
      else form.appendChild(grupo('Proyectos que puede vender', proyectos.map(function (p) { return [p.id, p.nombre]; }), 'p_' + s.id, []));
      form.appendChild(grupo('Tipos de contrato', TIPOS, 't_' + s.id, TIPOS_DEF));
      form.appendChild(grupo('Herramientas', HERR_COMERCIAL, 'h_' + s.id, HERR_COMERCIAL.map(function (h) { return h[0]; })));
      c.appendChild(form);

      var acc = el('div', 'flex flex-wrap items-center gap-2 mt-3');
      var act = el('button', 'px-4 py-2 rounded-full bg-deep-lagoon text-on-primary font-label-md text-label-md', 'Activar');
      var des = el('button', 'px-4 py-2 rounded-full border border-outline/40 font-label-md text-label-md', 'Descartar');
      act.type = des.type = 'button';
      var aviso = el('span', 'font-body-sm text-body-sm');
      acc.appendChild(act); acc.appendChild(des); acc.appendChild(aviso);
      c.appendChild(acc);
      function marcados(n) { return Array.prototype.map.call(c.querySelectorAll('input[name="' + n + '"]:checked'), function (i) { return i.value; }); }

      act.addEventListener('click', function () {
        if (!window.confirm('¿Activar a ' + s.nombre + ' (' + s.email + ')? Tendrá acceso a la intranet como comercial.')) return;
        if (act.dataset.enCurso) return; act.dataset.enCurso = '1';
        act.disabled = des.disabled = true; aviso.textContent = 'Activando…'; aviso.className = 'font-body-sm text-body-sm text-on-surface-variant';
        llama(sb, { accion: 'activar_solicitud', solicitud_id: s.id, proyectos: marcados('p_' + s.id),
                    tipos_contrato: marcados('t_' + s.id), herramientas: marcados('h_' + s.id) }).then(function (x) {
          if (x && x.ok) {
            aviso.textContent = x.email_enviado ? 'Activado. Le ha llegado el correo para crear su contraseña.' : 'Activado, pero el correo no salió: usa «Reenviar enlace».';
            aviso.className = 'font-body-sm text-body-sm text-primary';
            setTimeout(pintaSolicitudes, 1800);
          } else {
            act.disabled = des.disabled = false; delete act.dataset.enCurso;
            aviso.textContent = TXT_ERR[x && x.error] || ('No se pudo activar: ' + (x && x.error || 'error'));
            aviso.className = 'font-body-sm text-body-sm text-error';
          }
        }).catch(function (e) { act.disabled = des.disabled = false; aviso.textContent = String(e.message || e); });
      });
      des.addEventListener('click', function () {
        if (!window.confirm('¿Descartar la solicitud de ' + s.nombre + '?')) return;
        act.disabled = des.disabled = true;
        llama(sb, { accion: 'descartar_solicitud', solicitud_id: s.id }).then(function (x) {
          if (x && x.ok) return pintaSolicitudes();
          act.disabled = des.disabled = false; aviso.textContent = 'No se pudo descartar: ' + (x && x.error || 'error'); aviso.className = 'font-body-sm text-body-sm text-error';
        }).catch(function (e) { act.disabled = des.disabled = false; aviso.textContent = String(e.message || e); });
      });
      return c;
    }

    function pintaReferidos() {
      sb.from('referidos_contactos').select('*').order('creado_at', { ascending: false }).limit(100).then(function (r) {
        cabecera(sec2, 'Contactos de referidos',
          'Clientes que te pasan los referidos (1 %) desde la guía, sin cuenta en la intranet. El referido queda anotado como quien lo trajo: dalo de alta en el CRM y márcalo aquí.');
        if (r.error) { sec2.appendChild(el('p', 'text-error', 'No se han podido cargar: ' + r.error.message)); return; }
        var filas = r.data || [];
        if (!filas.length) { sec2.appendChild(el('p', 'font-body-md text-on-surface-variant', 'Todavía no hay contactos de referidos.')); return; }
        filas.forEach(function (x) {
          var c = el('div', 'border border-outline/20 rounded-xl p-4 mb-3 bg-surface grid gap-2 md:grid-cols-[1fr_1fr_auto] items-start');
          var cli = el('div', '');
          cli.appendChild(el('div', 'font-label-md text-label-md', x.cliente_nombre));
          cli.appendChild(el('div', 'font-body-sm text-body-sm text-on-surface-variant',
            [x.cliente_email, x.cliente_telefono, x.cliente_pais].filter(Boolean).join(' · ')));
          if (x.interes) cli.appendChild(el('div', 'font-body-sm text-body-sm mt-1', '«' + x.interes + '»'));
          var ref = el('div', 'font-body-sm text-body-sm');
          ref.appendChild(el('div', 'text-outline', 'Referido por'));
          ref.appendChild(el('div', 'font-semibold', x.referido_nombre));
          ref.appendChild(el('div', 'text-on-surface-variant', x.referido_email + (x.referido_telefono ? ' · ' + x.referido_telefono : '')));
          ref.appendChild(el('div', 'text-outline mt-1', fecha(x.creado_at)));
          var sel = document.createElement('select');
          sel.className = 'border border-outline/40 rounded-lg px-2 py-1 font-body-sm text-body-sm bg-surface-container-lowest';
          [['nuevo', 'Nuevo'], ['en_crm', 'Ya en el CRM'], ['descartado', 'Descartado']].forEach(function (o) {
            var op = document.createElement('option'); op.value = o[0]; op.textContent = o[1]; if (x.estado === o[0]) op.selected = true; sel.appendChild(op);
          });
          var previo = x.estado;
          var nota = el('span', 'font-body-sm text-body-sm text-error');
          sel.addEventListener('change', function () {
            sel.disabled = true; nota.textContent = '';
            llama(sb, { accion: 'estado_referido', id: x.id, estado: sel.value }).then(function (res) {
              sel.disabled = false;
              if (res && res.ok) { previo = sel.value; return; }
              sel.value = previo; nota.textContent = 'No se guardó: ' + (res && res.error || 'error');
            }).catch(function (e) { sel.disabled = false; sel.value = previo; nota.textContent = String(e.message || e); });
          });
          var col = el('div', 'flex flex-col gap-1'); col.appendChild(sel); col.appendChild(nota);
          c.appendChild(cli); c.appendChild(ref); c.appendChild(col);
          sec2.appendChild(c);
        });
      });
    }
  });
})();
