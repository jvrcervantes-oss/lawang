/* Ajustes con pestañas (Ajustes del ERP, subtarea S1, 30-sep-2026).
 * Encargo: encargos/20260930_erp_ajustes_pantalla.md. Migración: 20260930190000_ajustes_config_log.sql.
 *
 * Qué hace esta pieza (y solo esto):
 *  · las pestañas de /v4/ajustes/ (una URL por pestaña: #empresa, #correo…; atrás/adelante funcionan);
 *  · los formularios de «Empresa y marca» y «Correo», que leen por `ajustes_config_datos` y escriben por
 *    `ajustes_config_guardar` (una clave de la lista blanca por botón, para que un valor a medio teclear no llegue a la base);
 *  · el «Registro de cambios» (`ajustes_log_datos`, solo super admin).
 *
 * Lo que NO hace, a propósito: decidir quién puede escribir. Esa decisión es de la base (`es_super_admin()` dentro de la RPC,
 * 42501 si no). Esta pantalla solo no ofrece lo que la base va a rechazar, y enseña el error que la base devuelve.
 * Lo que ya existía (modo mantenimiento: mantenimiento.js; plazos de reservas: datos.js → REG.ajustes) sigue con sus ids
 * (#lw-mant-panel, #lw-mant-intranet, #lw-ajustes-lista) y ahora vive en su pestaña.
 * Se engancha por data-accion / data-lw-tab / data-ajuste, nunca por un rótulo.
 */
(function () {
  'use strict';

  var PESTANAS = ['empresa', 'correo', 'usuarios', 'mantenimiento', 'reservas', 'registro'];
  var ES_MAESTRO = !!window.AXW_NUCLEO_OPERACION;   // la bandera del ERP maestro; en Lawang no existe

  // Fuente única de lo que esta pantalla ofrece editar. La base tiene la lista blanca de verdad (_ajustes_claves_editables):
  // erp/test_canon_ajustes.py comprueba que ninguna clave de aquí se sale de ella.
  var CAMPOS = {
    empresa: [
      { clave: 'marca', etiqueta: 'Nombre del ERP', tipo: 'text', max: 60,
        ayuda: 'El nombre de la instalación: sale en el título del navegador, el menú lateral y las frases que nombran a la empresa. Vacío no se admite: si nunca se ha guardado, manda el nombre de origen.' },
      { clave: 'zona_horaria', etiqueta: 'Zona horaria', tipo: 'text', max: 64, ejemplo: 'Asia/Makassar',
        ayuda: 'Formato Región/Ciudad. Fija las horas de los avisos y resúmenes programados.' },
      { clave: 'logo_correo_url', etiqueta: 'Logo de los correos', tipo: 'url', max: 500, opcional: true, ejemplo: 'https://…',
        ayuda: 'Dirección https:// de una imagen. Vacío = sin logo.' }
    ],
    correo: [
      { clave: 'email_from', etiqueta: 'Remitente de los correos', tipo: 'email', max: 254,
        ayuda: 'El buzón desde el que salen los correos de la intranet.' },
      { clave: 'email_reply_to', etiqueta: 'Responder a', tipo: 'email', max: 254, opcional: true,
        ayuda: 'Dónde llegan las respuestas. Vacío = al remitente.' },
      { clave: 'email_avisos_reservas', etiqueta: 'Buzón de avisos de reservas', tipo: 'email', max: 254,
        ayuda: 'Recibe los avisos de reservas. Un solo correo.' },
      { clave: 'email_avisos_crm', etiqueta: 'Buzón de avisos del CRM', tipo: 'email', max: 254, opcional: true,
        ayuda: 'Recibe los avisos de leads nuevos. Un solo correo, o vacío.' }
    ]
  };
  // Qué lee hoy cada valor, sin inventar: una casilla que guarda pero no cambia nada se dice en la propia casilla.
  var LO_LEE_EL_MAESTRO = { marca: 1, zona_horaria: 1, email_avisos_reservas: 1, logo_correo_url: 1 };
  // Lawang (S2, 30-sep-2026): el nombre del ERP ya lo lee la pantalla (título del navegador y menú, por i18n.js → instancia_marca).
  // Idioma por defecto, moneda base y color de acento NO se ofrecen: hoy no los lee nada (cada documento lleva su moneda y el idioma
  // lo elige cada persona), y una casilla que guarda pero no cambia nada es una promesa falsa.
  var LO_LEE_LAWANG = { marca: 1 };
  var TEXTO_LEE_LAWANG = 'Ya lo leen el título del navegador, el menú lateral y las frases que nombran a la empresa. Los correos lo leerán en la fase siguiente.';
  var TEXTO_LEE = 'Ya lo leen funciones de la base de este ERP. La pantalla, el menú y los demás correos lo leerán en la fase siguiente.';
  var TEXTO_NO_LEE = 'Se guarda y queda en el registro, pero todavía no lo lee ninguna pantalla ni correo de esta instalación: llegará con la fase siguiente.';

  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function T(x) { return (typeof lwT === 'function') ? lwT(x) : x; }
  function fecha(x) { if (!x) return '—'; var d = new Date(x); return isNaN(d) ? String(x).slice(0, 16) : d.toLocaleString('es-ES'); }
  function aviso(t) { if (typeof toast === 'function') toast(t); }
  function lee(clave) {
    if (ES_MAESTRO) return LO_LEE_EL_MAESTRO[clave] ? T(TEXTO_LEE) : T(TEXTO_NO_LEE);
    return LO_LEE_LAWANG[clave] ? T(TEXTO_LEE_LAWANG) : T(TEXTO_NO_LEE);
  }

  var sb = null, datos = null, registroCargado = false;

  /* ── Pestañas ─────────────────────────────────────────────────────────────────────────────────────────────── */
  function desdeHash() {
    var h = String(location.hash || '').replace(/^#/, '');
    return PESTANAS.indexOf(h) >= 0 ? h : 'empresa';
  }
  function activa(nombre) {
    document.querySelectorAll('[data-lw-tab]').forEach(function (b) {
      var on = b.getAttribute('data-lw-tab') === nombre;
      b.setAttribute('aria-selected', on ? 'true' : 'false');
      b.setAttribute('tabindex', on ? '0' : '-1');
      b.classList.toggle('bg-primary-container', on);
      b.classList.toggle('text-on-primary', on);
      b.classList.toggle('text-on-surface-variant', !on);
      b.classList.toggle('hover:bg-surface-container', !on);
    });
    document.querySelectorAll('[data-lw-panel]').forEach(function (p) { p.hidden = p.getAttribute('data-lw-panel') !== nombre; });
    if (nombre === 'registro') cargaRegistro(false);
  }
  function cablePestanas() {
    var botones = Array.prototype.slice.call(document.querySelectorAll('[data-lw-tab]'));
    botones.forEach(function (b, i) {
      b.addEventListener('click', function (ev) {
        ev.stopPropagation();   // si no, maqueta.js la ve pasar y avisa «sin cablear»
        var n = b.getAttribute('data-lw-tab');
        if (location.hash !== '#' + n) location.hash = n; else activa(n);
      });
      b.addEventListener('keydown', function (ev) {
        var d = ev.key === 'ArrowRight' ? 1 : ev.key === 'ArrowLeft' ? -1 : 0;
        if (!d) return;
        ev.preventDefault();
        var s = botones[(i + d + botones.length) % botones.length];
        s.focus(); s.click();
      });
    });
    window.addEventListener('hashchange', function () { activa(desdeHash()); });
    activa(desdeHash());
  }

  /* ── Formularios ──────────────────────────────────────────────────────────────────────────────────────────── */
  function filaCampo(c, valor, actualizado, puede) {
    var id = 'lw-aj-' + c.clave;
    var v = valor == null ? '' : String(valor);
    return '<div class="px-8 py-5 flex flex-col md:flex-row lw-aj-inicio justify-between gap-4 border-b border-outline-variant/30" data-ajuste-fila="' + esc(c.clave) + '">' +
      '<div class="flex flex-col gap-1 lw-aj-mitad">' +
        '<label for="' + id + '" class="font-label-md text-label-md text-on-surface">' + esc(T(c.etiqueta)) + (c.opcional ? ' <span class="text-outline">(' + esc(T('opcional')) + ')</span>' : '') + '</label>' +
        '<span class="font-body-sm text-body-sm text-outline">' + esc(T(c.ayuda)) + '</span>' +
        '<span class="font-body-sm text-body-sm text-outline">' + esc(lee(c.clave)) + '</span>' +
        '<span class="font-body-sm text-body-sm text-outline">' + esc(T('Último cambio')) + ': ' + esc(actualizado ? fecha(actualizado) : T('nunca (valor de origen)')) + '</span>' +
      '</div>' +
      '<div class="flex flex-col gap-2 lw-aj-mitad">' +
        '<div class="flex flex-col md:flex-row gap-3 md:items-center">' +
          '<input id="' + id + '" type="' + c.tipo + '" maxlength="' + c.max + '" autocomplete="off" spellcheck="false" data-ajuste="' + esc(c.clave) + '"' +
            (c.ejemplo ? ' placeholder="' + esc(c.ejemplo) + '"' : '') + (puede ? '' : ' disabled') +
            ' class="w-full rounded-lg border border-control-border/50 bg-surface-container-lowest px-3 py-2.5 font-body-md text-body-md">' +
          (puede ? '<button type="button" data-real data-accion="ajuste-guardar" data-ajuste-clave="' + esc(c.clave) + '" class="shrink-0 px-4 py-2 rounded-full bg-primary-container text-on-primary hover:bg-primary font-label-md text-label-md">' + esc(T('Guardar')) + '</button>' : '') +
        '</div>' +
        '<span class="font-body-sm text-body-sm text-outline" role="status" aria-live="polite" data-ajuste-estado="' + esc(c.clave) + '"></span>' +
      '</div>' +
    '</div>';
  }

  // `ant` = lo que había antes de repintar: lo que el usuario ha tecleado y aún no ha guardado en OTRA casilla no se pierde
  // al guardar esta (revisión de código 30-sep). `guardada` = la que acaba de guardarse: esa muestra lo que dejó el servidor.
  function pintaFormulario(nombre, contenedorId, ant, guardada) {
    var cont = document.getElementById(contenedorId);
    if (!cont || !datos) return;
    var previo = {};
    cont.querySelectorAll('[data-ajuste]').forEach(function (i) { previo[i.getAttribute('data-ajuste')] = i.value; });
    var puede = !!datos.puede_escribir;
    cont.innerHTML = CAMPOS[nombre].map(function (c) {
      return filaCampo(c, (datos.valores || {})[c.clave], (datos.actualizado || {})[c.clave], puede);
    }).join('') +
      (puede
        ? '<div class="px-8 py-5 flex flex-col md:flex-row md:items-center gap-3">' +
            '<label for="lw-aj-motivo-' + nombre + '" class="font-label-md text-label-md text-on-surface">' + esc(T('Motivo del cambio')) + ' <span class="text-outline">(' + esc(T('opcional')) + ')</span></label>' +
            '<input id="lw-aj-motivo-' + nombre + '" type="text" maxlength="500" data-ajuste-motivo autocomplete="off" placeholder="' + esc(T('Queda en el registro de cambios')) + '"' +
              ' class="w-full md:w-80 rounded-lg border border-control-border/50 bg-surface-container-lowest px-3 py-2.5 font-body-md text-body-md">' +
          '</div>'
        : '<p class="px-8 py-5 font-body-sm text-body-sm text-outline">' + esc(T('Solo lectura: cambiar estos valores exige super admin.')) + '</p>');
    // el valor va por .value (nunca dentro del HTML): lo que llegue de la base no se interpreta como marcado
    CAMPOS[nombre].forEach(function (c) {
      var inp = cont.querySelector('[data-ajuste="' + c.clave + '"]');
      if (inp) inp.value = (datos.valores || {})[c.clave] == null ? '' : String((datos.valores || {})[c.clave]);
      var antes = ant && (ant.valores || {})[c.clave];
      if (inp && c.clave !== guardada && c.clave in previo && previo[c.clave] !== (antes == null ? '' : String(antes))) inp.value = previo[c.clave];
    });
  }

  function errorLectura(contenedorId, err) {
    var cont = document.getElementById(contenedorId);
    if (!cont) return;
    var sinPermiso = err && (err.code === '42501' || /42501/.test(String(err.message)));
    cont.innerHTML = '<div class="px-8 py-6 flex flex-col md:flex-row md:items-center justify-between gap-3" role="alert">' +
      '<span class="font-body-md text-body-md text-error">' +
        esc(sinPermiso ? T('Los ajustes son de administración: tu sesión no tiene acceso.') : T('No se han podido leer los ajustes') + ': ' + ((err && err.message) || T('sin respuesta'))) + '</span>' +
      (sinPermiso ? '' : '<button type="button" data-real data-accion="ajustes-reintentar" class="shrink-0 px-4 py-2 rounded-full bg-primary-container text-on-primary hover:bg-primary font-label-md text-label-md">' + esc(T('Reintentar')) + '</button>') +
      '</div>';
  }

  function carga(guardada) {
    return window.lwDatos('ajustes_config_datos').then(function (r) {
      if (r.error || !r.data) {
        console.error('[ajustes]', r.error);
        errorLectura('lw-aj-empresa', r.error); errorLectura('lw-aj-correo', r.error);
        datos = null;
        return;
      }
      var ant = datos;
      datos = r.data;
      pintaFormulario('empresa', 'lw-aj-empresa', ant, guardada);
      pintaFormulario('correo', 'lw-aj-correo', ant, guardada);
      var soloLee = document.getElementById('lw-ajustes-solo-lectura');
      if (soloLee) soloLee.hidden = !!datos.puede_escribir;
    });
  }

  function guarda(btn) {
    var clave = btn.getAttribute('data-ajuste-clave');
    var fila = btn.closest('[data-ajuste-fila]');
    var inp = fila && fila.querySelector('[data-ajuste]');
    var est = fila && fila.querySelector('[data-ajuste-estado]');
    var panel = btn.closest('[data-lw-panel]');
    var motivo = panel && panel.querySelector('[data-ajuste-motivo]');
    if (!inp) return;
    btn.disabled = true;
    if (est) { est.className = 'font-body-sm text-body-sm text-outline'; est.textContent = T('Guardando…'); }
    sb.rpc('ajustes_config_guardar', { p_clave: clave, p_valor: inp.value, p_motivo: (motivo && motivo.value.trim()) || null }).then(function (r) {
      btn.disabled = false;
      if (r.error) {
        var sin = r.error.code === '42501';
        var msg = sin ? T('Solo el super admin puede cambiar los ajustes.') : (r.error.message || T('sin detalle'));
        if (est) { est.className = 'font-body-sm text-body-sm text-error'; est.textContent = T('No se guardó') + ': ' + msg; }
        aviso(T('No se guardó') + ': ' + msg);
        return;
      }
      aviso(r.data && r.data.cambiado ? T('Guardado') + ': ' + clave : T('Sin cambios') + ': ' + clave);
      registroCargado = false;
      if (clave === 'marca' && typeof window.lwMarcaRefresca === 'function') window.lwMarcaRefresca(sb);   // el menú y el título cambian al momento
      carga(clave).then(function () {
        var e2 = document.querySelector('[data-ajuste-estado="' + clave + '"]');
        if (e2) { e2.className = 'font-body-sm text-body-sm text-on-surface'; e2.textContent = r.data && r.data.cambiado ? T('Guardado. Queda en el registro de cambios.') : T('Sin cambios: ya valía eso.'); }
      });
    });
  }

  /* ── Registro de cambios ──────────────────────────────────────────────────────────────────────────────────── */
  function valorTxt(v) {
    if (v == null) return '—';
    if (v === '') return '(' + T('vacío') + ')';
    return typeof v === 'string' ? v : JSON.stringify(v);
  }
  function cargaRegistro(forzar) {
    var cont = document.getElementById('lw-aj-registro');
    if (!cont || (registroCargado && !forzar)) return;
    if (datos && !datos.puede_escribir) {
      cont.innerHTML = '<p class="px-8 py-6 font-body-md text-body-md text-on-surface-variant">' + esc(T('El registro de cambios lo ve solo el super admin.')) + '</p>';
      return;
    }
    cont.innerHTML = '<p class="px-8 py-6 font-body-md text-body-md text-on-surface-variant">' + esc(T('Trayendo el registro…')) + '</p>';
    window.lwDatos('ajustes_log_datos', { p_limit: 200 }).then(function (r) {
      if (r.error || !r.data) {
        var sin = r.error && r.error.code === '42501';
        cont.innerHTML = '<div class="px-8 py-6 flex flex-col md:flex-row md:items-center justify-between gap-3" role="alert">' +
          '<span class="font-body-md text-body-md ' + (sin ? 'text-on-surface-variant' : 'text-error') + '">' +
            esc(sin ? T('El registro de cambios lo ve solo el super admin.') : T('No se ha podido leer el registro') + ': ' + ((r.error && r.error.message) || T('sin respuesta'))) + '</span>' +
          (sin ? '' : '<button type="button" data-real data-accion="ajustes-registro-reintentar" class="shrink-0 px-4 py-2 rounded-full bg-primary-container text-on-primary hover:bg-primary font-label-md text-label-md">' + esc(T('Reintentar')) + '</button>') +
          '</div>';
        return;
      }
      registroCargado = true;
      var filas = r.data.filas || [];
      if (!filas.length) {
        cont.innerHTML = '<p class="px-8 py-6 font-body-md text-body-md text-on-surface-variant">' + esc(T('Todavía no se ha cambiado ningún ajuste.')) + '</p>';
        return;
      }
      var th = function (t, extra) { return '<th class="px-5 py-3 font-label-md text-[11px] uppercase tracking-wider text-outline' + (extra || '') + '">' + esc(T(t)) + '</th>'; };
      cont.innerHTML = '<div class="overflow-x-auto"><table class="w-full text-left border-collapse"><thead><tr class="border-b border-outline-variant/60 bg-surface-container-low">' +
        th('Cuándo') + th('Quién') + th('Ajuste') + th('Antes') + th('Después') + th('Motivo') +
        '</tr></thead><tbody>' + filas.map(function (f) {
          return '<tr class="border-b border-outline-variant/30" data-ajuste-log="' + esc(f.id) + '">' +
            '<td class="px-5 py-3 font-body-sm text-body-sm text-outline">' + esc(fecha(f.cuando)) + '</td>' +
            '<td class="px-5 py-3 font-body-sm text-body-sm text-on-surface">' + esc(f.quien) + '</td>' +
            '<td class="px-5 py-3 font-body-sm text-body-sm text-on-surface"><code>' + esc(f.tabla + ' · ' + f.clave) + '</code></td>' +
            '<td class="px-5 py-3 font-body-sm text-body-sm text-on-surface-variant">' + esc(valorTxt(f.antes)) + '</td>' +
            '<td class="px-5 py-3 font-body-sm text-body-sm text-on-surface">' + esc(valorTxt(f.despues)) + '</td>' +
            '<td class="px-5 py-3 font-body-sm text-body-sm text-outline">' + esc(f.motivo || '—') + '</td></tr>';
        }).join('') + '</tbody></table></div>' +
        (r.data.hay_mas ? '<p class="px-8 py-4 border-t border-outline-variant/40 font-body-sm text-body-sm text-outline">' + esc(T('Se muestran los 200 últimos cambios.')) + '</p>' : '');
    });
  }

  /* ── Arranque ─────────────────────────────────────────────────────────────────────────────────────────────── */
  function arranca() {
    if (!document.querySelector('[data-lw-tab]')) return;   // otra página con este script: nada que hacer
    cablePestanas();
    document.addEventListener('click', function (ev) {
      var b = ev.target.closest && ev.target.closest('[data-accion]');
      if (!b || !b.hasAttribute('data-real')) return;
      var a = b.getAttribute('data-accion');
      if (a === 'ajuste-guardar') { ev.stopPropagation(); guarda(b); }
      else if (a === 'ajustes-reintentar') { ev.stopPropagation(); carga(); }
      else if (a === 'ajustes-registro-reintentar') { ev.stopPropagation(); cargaRegistro(true); }
      else if (a === 'ajustes-registro-actualizar') { ev.stopPropagation(); cargaRegistro(true); }
    }, true);
    if (!window.LW_AUTH) return;
    window.LW_AUTH.then(function (aut) {
      if (!aut || !aut.sb) return;
      sb = aut.sb;
      carga().then(function () { if (desdeHash() === 'registro') cargaRegistro(false); });
    });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', arranca); else arranca();
})();
