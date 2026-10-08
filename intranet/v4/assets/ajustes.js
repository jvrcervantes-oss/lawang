/* Ajustes con pestañas (Ajustes del ERP, subtarea S1, 30-sep-2026).
 * Encargo: encargos/20260930_erp_ajustes_pantalla.md. Migración: 20260930190000_ajustes_config_log.sql.
 *
 * Qué hace esta pieza (y solo esto):
 *  · las pestañas de /v4/ajustes/ (una URL por pestaña: #empresa, #correo…; atrás/adelante funcionan);
 *  · los formularios de «Empresa y marca» y «Correo», que leen por `ajustes_config_datos` y escriben por
 *    `ajustes_config_guardar` (una clave de la lista blanca por botón, para que un valor a medio teclear no llegue a la base);
 *  · el servidor de salida del correo y las cuatro direcciones (Remitente, Responder a, avisos de soporte y de sistema), que NO pasan por
 *    `ajustes_config_guardar`: se piden y se guardan con un código de confirmación por la edge `ajustes-correo` (F3.1, 8-oct-2026);
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
  function T(x, huecos) { return (typeof lwT === 'function') ? lwT(x, huecos) : x; }   // huecos: %nombre → valor (lo hace lwT)
  function fecha(x) { if (!x) return '—'; var d = new Date(x); return isNaN(d) ? String(x).slice(0, 16) : d.toLocaleString('es-ES'); }
  function aviso(t) { if (typeof toast === 'function') toast(t); }
  function lee(clave) {
    if (LEE_CORREO[clave]) return T(TEXTO_LEE_CORREO);
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
      ajustaCamposCorreo();
      pintaFormulario('correo', 'lw-aj-correo', ant, guardada);
      pintaServidorCorreo(guardada);
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
  /* ── Correo desde Ajustes (F3.1 + código de confirmación F3.1b; porte a Lawang 8-oct-2026) ─────────────────────────────────────────────
   * Qué añade a la pestaña Correo, y solo esto:
   *  1. «Servidor de salida» (host, puerto 465 fijo, usuario, contraseña write-only, nombre del remitente) y «Direcciones» (Remitente,
   *     Responder a, buzones de soporte y de sistema). El navegador NO guarda nada ni escribe en la base: llama a la edge `ajustes-correo`
   *     con la sesión. Todo cambio pasa por el mismo camino: «Pedir código» (la edge manda 6 cifras al correo de la SESIÓN) → se escriben →
   *     «Probar y guardar» (servidor) o «Guardar» (dirección). Cambiar host o usuario pide además la contraseña de la cuenta.
   *  2. Lee TODO por la acción `estado` de la edge: las 4 direcciones ya no salen por `ajustes_config_datos` (no son editables de `authenticated`).
   *  3. Una casilla más en el formulario de Correo (asunto_por_defecto), que escribe la RPC `ajustes_config_guardar` como las demás — solo si la
   *     base la declara editable (`datos.editables`).
   * Reglas: solo códigos traducidos (jamás el texto del servidor, ni lo tecleado devuelto como mensaje); todo dato a la pantalla por
   * textContent/atributos, nunca por innerHTML; enganche por data-accion / data-correo-*, nunca por un rótulo. El código está atado al cambio
   * EXACTO (la huella incluye la contraseña del buzón): por eso, con un código pedido, los datos se bloquean hasta guardar o cambiar de idea.
   * Los textos en inglés viven en contracts/assets/i18n.js (una frase, una entrada). Este bloque es el mismo código que el overlay del ERP maestro
   * (comercial/demo-erp/ajustes_correo.js), salvo el instalador, que Lawang no tiene. */
  var TEXTO_LEE_CORREO = 'Lo lee el envío de correos de este ERP en cada correo que manda.';
  var LEE_CORREO = { asunto_por_defecto: 1 };
  // Las cuatro direcciones de correo (email_from, email_reply_to, email_avisos_soporte, email_avisos_sistema) ya no son editables de `authenticated`:
  // se cambian con código desde la edge y el formulario base (CAMPOS.correo) no las ofrece.
  var EXTRA_CORREO = [
    { clave: 'asunto_por_defecto', etiqueta: 'Asunto por defecto', tipo: 'text', max: 200, opcional: true,
      ayuda: 'El asunto de los correos que no traen el suyo. Vacío = el de fábrica («Documento — marca»).' }
  ];
  var DIRECCIONES = [
    { clave: 'email_from', etiqueta: 'Remitente de los correos', max: 254,
      ayuda: 'La dirección desde la que salen todos los correos. Tiene que ser del mismo dominio que el buzón del servidor.' },
    { clave: 'email_reply_to', etiqueta: 'Responder a', max: 254, opcional: true,
      ayuda: 'Adónde llegan las respuestas de quien recibe un correo. Vacío = responde al remitente.' },
    { clave: 'email_avisos_soporte', etiqueta: 'Buzón de avisos de soporte', max: 254,
      ayuda: 'Recibe los avisos de soporte. Un solo correo, del dominio de la instalación, del remitente o del servidor de correo.' },
    { clave: 'email_avisos_sistema', etiqueta: 'Buzón de avisos del sistema', max: 254,
      ayuda: 'Recibe los avisos del sistema, entre ellos el de «han cambiado el servidor de correo». Un solo correo, del dominio de la instalación, del remitente o del servidor de correo.' }
  ];
  var CAMPOS_CORREO_BASE = null;
  // La casilla nueva sale SOLO si la base ya la declara editable (migración 20261010060000): sin ella guardar daría «clave no editable».
  function ajustaCamposCorreo() {
    if (!CAMPOS_CORREO_BASE) CAMPOS_CORREO_BASE = CAMPOS.correo.slice();
    var ed = datos && datos.editables;
    CAMPOS.correo = CAMPOS_CORREO_BASE.concat(EXTRA_CORREO.filter(function (c) { return Array.isArray(ed) && ed.indexOf(c.clave) >= 0; }));
  }

  // Códigos de la edge → texto (es). Lo que no está aquí NO se enseña tal cual: sale «Respuesta no reconocida».
  var CORREO_MSG = {
    host_no_valido: 'Pon un servidor válido: un nombre de internet como smtp.tuproveedor.com, sin IP ni nombres internos.',
    puerto_no_valido: 'El puerto tiene que ser 465.',
    usuario_no_valido: 'El usuario del buzón va de 1 a 254 caracteres y sin caracteres de control.',
    clave_no_valida: 'La contraseña del buzón va de 1 a 200 caracteres y sin saltos de línea.',
    nombre_no_valido: 'El nombre del remitente admite 60 caracteres, sin < ni >.',
    host_no_resuelve: 'Ese servidor no existe (no resuelve en internet).',
    host_privado: 'Ese servidor apunta a una red interna: solo se admite un servidor público.',
    host_no_comprobable: 'No se ha podido comprobar a dónde apunta ese servidor ahora mismo: no se ha enviado ni guardado nada. Inténtalo de nuevo en un rato.',
    sin_remitente: 'El usuario del buzón no es un correo y no hay remitente válido: pon uno de tu dominio en «Direcciones» más abajo.',
    sin_correo_usuario: 'Tu cuenta no tiene un correo válido al que mandar el código o la prueba.',
    sin_sesion: 'Tu sesión ha caducado: recarga la página o vuelve a entrar.',
    reautenticar: 'Confirma tu contraseña de la cuenta para cambiar de servidor o de usuario (o vuelve a entrar y repite).',
    clave_actual_incorrecta: 'Esa no es la contraseña de tu cuenta.',
    no_super_admin: 'Cambiar el correo exige ser super admin.',
    origen: 'Esta página no está autorizada a llamar al servicio de correo.',
    cuerpo_grande: 'La petición es demasiado grande.',
    json_no_valido: 'La petición no se ha entendido. Recarga la página e inténtalo de nuevo.',
    accion_no_valida: 'La petición no se ha entendido. Recarga la página e inténtalo de nuevo.',
    alcance_no_valido: 'La petición no se ha entendido. Recarga la página e inténtalo de nuevo.',
    metodo: 'La petición no se ha entendido. Recarga la página e inténtalo de nuevo.',
    prueba_caducada: 'La prueba ya no vale: repítela.',
    demasiados_intentos: 'Demasiados intentos o códigos pedidos seguidos: espera unos minutos antes de volver a intentarlo.',
    base_no_responde: 'La base no ha respondido: inténtalo de nuevo en un rato.',
    envios_pausados: 'Los envíos de correo están en pausa: no se prueba ni se guarda nada hasta reanudarlos (no es un fallo de la contraseña).',
    prueba_fallida: 'El servidor no ha aceptado la prueba: no se ha guardado y sigue el anterior.',
    codigo_no_valido: 'El código no vale: puede ser incorrecto, haber caducado, haberse usado ya o no corresponder a estos datos. Pide uno nuevo y no cambies nada de lo escrito.',
    codigo_no_enviado: 'No se ha podido mandar el código por correo. No se ha gastado ningún intento: inténtalo de nuevo en un rato.',
    codigo_no_disponible: 'La confirmación por código no está disponible ahora mismo en esta instalación, así que no se puede cambiar el correo desde aquí. Avisa al estudio.',
    sin_dominio_web: 'Esta instalación no tiene dominio configurado y sin él no se puede comprobar que el buzón es vuestro. Avisa al estudio.',
    clave_no_editable: 'Ese ajuste no se puede cambiar desde esta pantalla.',
    valor_no_valido: 'Ese valor no es válido: escribe una dirección de correo completa.',
    from_ajeno: 'El remitente tiene que ser una dirección del mismo dominio que el buzón del servidor de correo.',
    buzon_ajeno: 'Ese buzón tiene que ser del dominio de la instalación, del remitente o del servidor de correo.',
    sin_cambios: 'Ese valor ya es el actual.',
    codigo_caducado: 'El código ha caducado: pide uno nuevo.',
    codigo_mal_formado: 'Escribe las 6 cifras del código.',
    faltan_datos: 'Rellena el servidor, el usuario y la contraseña del buzón.',
    direccion_mal_formada: 'Escribe una dirección de correo completa, por ejemplo nombre@tudominio.com.',
    edge_no_disponible: 'El servicio de correo todavía no está disponible en esta instalación. Inténtalo más tarde.',
    sin_red: 'No se ha podido contactar con el servicio de correo (sin conexión, o todavía no está disponible).',
    respuesta_ilegible: 'La respuesta del servicio de correo no se entiende. Inténtalo de nuevo.'
  };
  // Tras estos fallos el código NO se ha gastado ni se ha invalidado: se puede repetir con los mismos datos. Con cualquier otro, se pide uno nuevo.
  var CODIGO_SIGUE = { reautenticar: 1, clave_actual_incorrecta: 1, prueba_fallida: 1, demasiados_intentos: 1, envios_pausados: 1, base_no_responde: 1,
    sin_red: 1, edge_no_disponible: 1, respuesta_ilegible: 1, prueba_caducada: 1, codigo_mal_formado: 1 };
  var CADUCA_POR_DEFECTO_S = 600;
  var srv = { fase: 'inicial', estado: null, remitente: null, avisos: null, pausados: false, pideCodigo: false, codigo: '', ocupado: '', editando: false, reauth: false, u: {} };

  function un(k) {
    if (!srv.u[k]) srv.u[k] = { fase: 'idle', correo: '', caduca: 0, minutos: 10, ok: '', codigo: '', extra: '' };
    return srv.u[k];
  }
  function nodo(tag, clase, txt, attrs) {
    var n = document.createElement(tag);
    if (clase) n.className = clase;
    if (txt != null) n.textContent = txt;
    if (attrs) Object.keys(attrs).forEach(function (k) { n.setAttribute(k, attrs[k]); });
    return n;
  }
  function mensajeCorreo(codigo) {
    return T(Object.prototype.hasOwnProperty.call(CORREO_MSG, codigo) ? CORREO_MSG[codigo] : 'Respuesta no reconocida del servicio de correo.');
  }
  // Una sola puerta a la edge. Devuelve SIEMPRE {status, codigo, d}: `codigo` solo si la edge mandó uno con forma de código; si no,
  // lo decide el estado HTTP (404/5xx sin código = la edge no está; sin respuesta = red o CORS). Nada del texto del servidor sale de aquí.
  function llamaCorreo(cuerpo) {
    return sb.auth.getSession().then(function (r) {
      var token = r && r.data && r.data.session && r.data.session.access_token;
      if (!token) return { status: 401, codigo: 'sin_sesion', d: null };
      var url;
      try { url = window.lwEdge('ajustes-correo'); } catch (e) { return { status: 0, codigo: 'edge_no_disponible', d: null }; }
      return fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token, 'apikey': window.LW_SB_KEY },
        body: JSON.stringify(cuerpo)
      }).then(function (resp) {
        return resp.text().then(function (t) {
          var d = null;
          try { d = JSON.parse(t); } catch (e) { d = null; }
          var cod = d && typeof d.codigo === 'string' && /^[a-z_]{3,40}$/.test(d.codigo) ? d.codigo : '';
          if (resp.ok && d && d.ok === true) return { status: resp.status, codigo: '', d: d };
          if (!cod) cod = (resp.status === 404 || resp.status >= 500) ? 'edge_no_disponible' : (d ? '' : 'respuesta_ilegible');
          return { status: resp.status, codigo: cod, d: d };
        });
      }, function () { return { status: 0, codigo: 'sin_red', d: null }; });
    }, function () { return { status: 401, codigo: 'sin_sesion', d: null }; });
  }
  // Solo códigos técnicos con forma de código (EAUTH, ETIMEDOUT, 535…): nunca un texto libre.
  function detalleTecnico(d) {
    var p = [];
    [d && d.detalle_code, d && d.smtp_code, d && d.smtp_response_code].forEach(function (x) {
      if ((typeof x === 'string' && /^[A-Za-z0-9_]{2,40}$/.test(x)) || (typeof x === 'number' && isFinite(x) && x >= 100 && x <= 999)) p.push(String(x));
    });
    return p.join(' ');
  }
  function localeCorreo() { return typeof window.lwLocale === 'function' ? window.lwLocale() : 'es-ES'; }
  function fechaCorreo(x) {
    var d = new Date(x);
    return isNaN(d) ? '' : d.toLocaleString(localeCorreo());
  }
  function horaCorreo(ms) {
    var d = new Date(ms);
    return isNaN(d) ? '' : d.toLocaleTimeString(localeCorreo(), { hour: '2-digit', minute: '2-digit' });
  }
  function textoSimple(x, max) { return typeof x === 'string' ? x.slice(0, max) : ''; }
  function aplicaRespuestaCorreo(d) {
    if (d && d.estado && typeof d.estado === 'object') srv.estado = d.estado;
    if (d && d.remitente && typeof d.remitente === 'object') srv.remitente = d.remitente;
    if (d && d.avisos && typeof d.avisos === 'object') srv.avisos = d.avisos;
    if (d && 'envios_pausados' in d) srv.pausados = !!d.envios_pausados;
    if (d && 'pide_codigo' in d) srv.pideCodigo = d.pide_codigo === true;
  }
  function valorDireccion(clave) {
    var r = srv.remitente || {}, a = srv.avisos || {};
    var v = clave === 'email_from' ? r.email_from : clave === 'email_reply_to' ? r.reply_to : clave === 'email_avisos_soporte' ? a.soporte : a.sistema;
    return typeof v === 'string' ? v : '';
  }

  function campoServidor(id, etiqueta, ayuda, input, opcional, extras) {
    var f = nodo('div', 'px-8 py-5 flex flex-col md:flex-row lw-aj-inicio justify-between gap-4 border-b border-outline-variant/30');
    var izq = nodo('div', 'flex flex-col gap-1 lw-aj-mitad');
    var lab = nodo('label', 'font-label-md text-label-md text-on-surface', T(etiqueta), { 'for': id });
    if (opcional) { var op = nodo('span', 'text-outline', ' (' + T('opcional') + ')'); lab.appendChild(op); }
    izq.appendChild(lab);
    if (ayuda) izq.appendChild(nodo('span', 'font-body-sm text-body-sm text-outline', T(ayuda)));
    var der = nodo('div', 'flex flex-col gap-2 lw-aj-mitad');
    input.id = id;
    input.className = 'w-full rounded-lg border border-control-border/50 bg-surface-container-lowest px-3 py-2.5 font-body-md text-body-md';
    der.appendChild(input);
    (extras || []).forEach(function (x) { if (x) der.appendChild(x); });
    f.appendChild(izq); f.appendChild(der);
    return { fila: f, der: der };
  }
  function inputServidor(tipo, campo, max, attrs) {
    var i = nodo('input', '', null, { type: tipo, maxlength: String(max), 'data-correo-campo': campo, autocomplete: 'off', spellcheck: 'false' });
    if (attrs) Object.keys(attrs).forEach(function (k) { i.setAttribute(k, attrs[k]); });
    return i;
  }
  function boton(txt, accion, extra) {
    var b = nodo('button', 'shrink-0 px-4 py-2 rounded-full bg-primary-container text-on-primary hover:bg-primary font-label-md text-label-md', T(txt),
      { type: 'button', 'data-real': '', 'data-accion': accion });
    if (extra) Object.keys(extra).forEach(function (k) { b.setAttribute(k, extra[k]); });
    return b;
  }
  function botonSecundario(txt, accion, extra) {
    var b = boton(txt, accion, extra);
    b.className = 'shrink-0 px-4 py-2 rounded-full border border-outline-variant text-on-surface hover:bg-surface-container font-label-md text-label-md';
    return b;
  }
  // Lo que el usuario ya tecleó sobrevive a un repintado. La contraseña del buzón solo mientras hay un código pedido para esos datos exactos
  // (el código está atado a ella); la de la cuenta, nunca.
  function tecleado() {
    var r = {}, cont = document.getElementById('lw-aj-correo-servidor');
    if (!cont) return r;
    cont.querySelectorAll('[data-correo-campo]').forEach(function (i) { var c = i.getAttribute('data-correo-campo'); if (c !== 'reauth') r[c] = i.value; });
    return r;
  }
  function bloqueServidor() {
    var cont = document.getElementById('lw-aj-correo-servidor');
    if (cont) return cont;
    var panel = document.getElementById('lw-aj-correo');
    if (!panel || !panel.parentNode) return null;
    cont = nodo('div', '', null, { id: 'lw-aj-correo-servidor', 'data-correo-servidor': '' });
    panel.parentNode.insertBefore(cont, panel);
    return cont;
  }
  function cabecera(titulo, ayuda) {
    var cab = nodo('div', 'px-8 pt-8 pb-4 flex flex-col gap-1 border-b border-outline-variant/40');
    cab.appendChild(nodo('h2', 'font-headline-sm text-headline-sm text-deep-lagoon tracking-tight', T(titulo)));
    cab.appendChild(nodo('p', 'font-body-sm text-body-sm text-outline', T(ayuda)));
    return cab;
  }
  function bloqueado(u) { return u.fase === 'pidiendo' || u.fase === 'esperando' || u.fase === 'guardando'; }
  function mensajeResultado(u, claveResultado) {
    var res = nodo('span', 'font-body-sm text-body-sm text-outline', null, { role: 'status', 'aria-live': 'polite', 'data-correo': claveResultado });
    if (u.ok) { res.className = 'font-body-sm text-body-sm text-on-surface'; res.textContent = u.ok; }
    else if (u.codigo) {
      res.className = 'font-body-sm text-body-sm text-error';
      res.setAttribute('role', 'alert');
      res.textContent = T(u.queFallo || 'No se guardó') + ': ' + mensajeCorreo(u.codigo) + (u.extra ? ' ' + u.extra : '');
    }
    return res;
  }
  // La mitad que se ve con un código pedido: a quién se mandó, cuándo caduca, la casilla de 6 cifras.
  function bloqueCodigo(u, campo) {
    var caja = nodo('div', 'flex flex-col gap-2', null, { 'data-correo': 'codigo-pedido' });
    caja.appendChild(nodo('span', 'font-body-sm text-body-sm text-on-surface',
      T('Te hemos enviado un código de 6 cifras a') + ' ' + u.correo + '. ' + T('Caduca en') + ' ' + u.minutos + ' ' + T('minutos') + ' (' + T('a las') + ' ' + horaCorreo(u.caduca) + '). ' + T('Sirve una sola vez.'),
      { 'data-correo': 'codigo-info' }));
    var cod = inputServidor('text', campo, 6, { inputmode: 'numeric', pattern: '[0-9]*', autocomplete: 'one-time-code', placeholder: '000000', 'aria-label': T('Código de confirmación') });
    cod.className = 'w-40 rounded-lg border border-control-border/50 bg-surface-container-lowest px-3 py-2.5 font-body-md text-body-md tracking-widest';
    caja.appendChild(cod);
    return { caja: caja, cod: cod };
  }

  function pintaServidorCorreo(guardada) {
    var cont = bloqueServidor();
    if (!cont || !datos) return;
    if (cont.firstChild && srv.fase === 'listo' && !srv.ocupado && guardada) return;   // se guardó OTRA casilla del formulario base: no se repinta esto
    var previo = tecleado();
    while (cont.firstChild) cont.removeChild(cont.firstChild);
    cont.appendChild(cabecera('Servidor de salida', 'El servidor SMTP desde el que salen todos los correos de este ERP. Se prueba con un envío real a tu correo y solo si llega se guarda; si falla, sigue el anterior.'));
    if (!datos.puede_escribir) {
      cont.appendChild(nodo('p', 'px-8 py-5 font-body-sm text-body-sm text-outline', T('Solo el super admin puede ver y cambiar el servidor de correo y las direcciones.')));
      cont.appendChild(nodo('div', 'border-b border-outline-variant/40'));
      return;
    }
    // Se pide el estado a la edge solo cuando se mira la pestaña
    if (srv.fase === 'inicial' && desdeHash() === 'correo') cargaEstadoCorreo(false);

    var estado = nodo('div', 'px-8 py-5 flex flex-col gap-2 border-b border-outline-variant/30', null, { role: 'status', 'aria-live': 'polite', 'data-correo': 'estado' });
    if (srv.fase === 'inicial' || srv.fase === 'cargando') {
      estado.appendChild(nodo('span', 'font-body-sm text-body-sm text-outline', T('Trayendo el estado del servidor…')));
    } else if (srv.fase === 'error') {
      estado.setAttribute('role', 'alert');
      estado.appendChild(nodo('span', 'font-body-md text-body-md text-error', T('No se ha podido leer el estado del servidor') + ': ' + mensajeCorreo(srv.codigo)));
      estado.appendChild(boton('Reintentar', 'correo-estado-reintentar', { 'class': 'self-start px-4 py-2 rounded-full bg-primary-container text-on-primary hover:bg-primary font-label-md text-label-md' }));
    } else {
      var e = srv.estado || {};
      if (e.configurado && typeof e.host === 'string') {
        var linea = T('Servidor actual') + ': ' + e.host + ' · ' + T('usuario') + ' ' + String(e.usuario || '') + ' · ' + T('puerto') + ' ' + String(e.puerto || 465);
        estado.appendChild(nodo('span', 'font-body-md text-body-md text-on-surface', linea, { 'data-correo': 'servidor-actual' }));
        var cuando = e.puesto_en ? fechaCorreo(e.puesto_en) : '';
        var porQuien = textoSimple(e.puesto_por, 120);
        var contra = porQuien ? T('Contraseña del buzón puesta el %cuando por %quien', { cuando: cuando || '—', quien: porQuien }) : T('Contraseña del buzón puesta el %cuando', { cuando: cuando || '—' });
        var filaContra = nodo('div', 'flex flex-col md:flex-row md:items-center gap-3');
        filaContra.appendChild(nodo('span', 'font-body-sm text-body-sm text-outline', '•••••••• · ' + contra, { 'data-correo': 'contrasena-puesta' }));
        if (!srv.editando && !srv.pausados) filaContra.appendChild(botonSecundario('Cambiar', 'correo-servidor-editar'));
        estado.appendChild(filaContra);
        if (e.hay_previo) estado.appendChild(nodo('span', 'font-body-sm text-body-sm text-outline', T('Hay un servidor anterior guardado como copia.')));
      } else {
        estado.appendChild(nodo('span', 'font-body-sm text-body-sm text-outline', T('Sin servidor guardado: los correos salen con la configuración de origen de la instalación.'), { 'data-correo': 'sin-servidor' }));
      }
      if (typeof e.intentos_recientes === 'number' && e.intentos_recientes > 0 && typeof e.intentos_max === 'number') {
        estado.appendChild(nodo('span', 'font-body-sm text-body-sm text-outline', T('Intentos recientes') + ': ' + e.intentos_recientes + ' ' + T('de') + ' ' + e.intentos_max));
      }
      var rem = srv.remitente || {};
      var efectivo = typeof rem.efectivo === 'string' ? rem.efectivo : '';
      if (rem.motivo === 'dominio_distinto' || rem.motivo === 'no_valido') {
        estado.appendChild(nodo('span', 'font-body-sm text-body-sm text-error',
          T('Los correos saldrán desde') + ' ' + efectivo + ' ' + T(rem.motivo === 'no_valido' ? 'porque el remitente de Ajustes no es una dirección válida.' : 'porque el remitente de Ajustes no es del dominio del buzón. Cambia el Remitente en «Direcciones» más abajo antes de probar.'),
          { 'data-correo': 'desajuste-dominio' }));
      } else if (rem.motivo === 'sin_remitente') {
        estado.appendChild(nodo('span', 'font-body-sm text-body-sm text-error', T('No hay remitente válido: el usuario del buzón no es un correo. Pon un remitente de tu dominio en «Direcciones» más abajo.'), { 'data-correo': 'desajuste-dominio' }));
      }
      if (srv.pausados) estado.appendChild(nodo('span', 'font-body-sm text-body-sm text-error', T('Los envíos de correo están en pausa (Mantenimiento): no se puede probar ni guardar hasta reanudarlos.'), { 'data-correo': 'pausa' }));
      if (!srv.pideCodigo) estado.appendChild(nodo('span', 'font-body-sm text-body-sm text-error', mensajeCorreo('codigo_no_disponible'), { 'data-correo': 'sin-codigo' }));
    }
    cont.appendChild(estado);
    if (srv.fase !== 'listo') { cont.appendChild(nodo('div', 'border-b border-outline-variant/40')); return; }

    pintaFormularioServidor(cont, previo);
    pintaDirecciones(cont, previo);
  }

  function pintaFormularioServidor(cont, previo) {
    var e2 = srv.estado || {};
    var u = un('servidor');
    var configurado = !!(e2.configurado && typeof e2.host === 'string');
    if (!configurado) srv.editando = true;
    if (!srv.editando) {   // plegado: el resultado del último guardado (o su fallo) se sigue viendo
      if (u.ok || u.codigo) { var pl = nodo('div', 'px-8 py-4 border-b border-outline-variant/30'); pl.appendChild(mensajeResultado(u, 'resultado')); cont.appendChild(pl); }
      return;
    }
    var lock = u.fase !== 'idle';
    var host = inputServidor('text', 'host', 253, { placeholder: 'smtp.tuproveedor.com', inputmode: 'url' });
    var port = inputServidor('text', 'port', 3, { value: '465', readonly: '', disabled: '', 'aria-readonly': 'true' });
    var user = inputServidor('text', 'user', 254, { inputmode: 'email' });
    // La contraseña del buzón: nunca prefijada ni del estado; new-password para que el navegador no la rellene con la de otra cuenta.
    // Con un código pedido se queda en la casilla (bloqueada) porque el código está atado a ella; al guardar, cancelar o cambiar de idea se vacía.
    var pass = inputServidor('password', 'pass', 200, { autocomplete: 'new-password' });
    var nombre = inputServidor('text', 'nombre', 60);
    host.value = previo.host != null ? previo.host : (typeof e2.host === 'string' ? e2.host : '');
    user.value = previo.user != null ? previo.user : (typeof e2.usuario === 'string' ? e2.usuario : '');
    nombre.value = previo.nombre != null ? previo.nombre : (typeof e2.nombre === 'string' ? e2.nombre : '');
    if (lock && previo.pass != null) pass.value = previo.pass;
    if (lock) [host, user, pass, nombre].forEach(function (i) { i.setAttribute('readonly', ''); });
    cont.appendChild(campoServidor('lw-aj-srv-host', 'Servidor', null, host).fila);
    cont.appendChild(campoServidor('lw-aj-srv-port', 'Puerto', 'Siempre 465 (conexión cifrada). No se puede cambiar.', port).fila);
    cont.appendChild(campoServidor('lw-aj-srv-user', 'Usuario del buzón', null, user).fila);
    cont.appendChild(campoServidor('lw-aj-srv-pass', 'Contraseña del buzón', 'Solo se escribe, nunca se enseña. Hay que escribirla otra vez cada vez que se cambie el servidor.', pass).fila);
    cont.appendChild(campoServidor('lw-aj-srv-nombre', 'Nombre del remitente', null, nombre, true).fila);
    // ¿cambia host o usuario? Entonces además de la contraseña del buzón y el código, la de la CUENTA (siempre, decisión del owner 8-oct)
    var cambia = !configurado || String(previo.host != null ? previo.host : '').trim() !== e2.host || String(previo.user != null ? previo.user : '').trim() !== e2.usuario;
    if (bloqueado(u) && (srv.reauth || cambia)) {
      var re = inputServidor('password', 'reauth', 200, { autocomplete: 'current-password' });
      var fila = campoServidor('lw-aj-srv-reauth', 'Tu contraseña de la cuenta', 'Para cambiar de servidor o de usuario confirma tu contraseña de acceso al ERP (o vuelve a entrar y repite).', re).fila;
      fila.setAttribute('data-correo', 'reauth');
      cont.appendChild(fila);
    }
    var pie = nodo('div', 'px-8 py-5 flex flex-col gap-3 border-b border-outline-variant/40');
    if (u.fase === 'esperando' || u.fase === 'guardando') {
      var bc = bloqueCodigo(u, 'codigo');
      if (previo.codigo != null) bc.cod.value = previo.codigo;
      pie.appendChild(bc.caja);
      pie.appendChild(nodo('span', 'font-body-sm text-body-sm text-outline', T('Los datos están bloqueados para que el código siga valiendo. Si quieres cambiar algo, pulsa «Cambiar los datos» y pide otro código.')));
    }
    var fila2 = nodo('div', 'flex flex-wrap items-center gap-3');
    if (u.fase === 'idle' || u.fase === 'pidiendo') {
      var bp = boton(u.fase === 'pidiendo' ? 'Pidiendo el código…' : 'Pedir código', 'correo-servidor-pedir');
      if (u.fase === 'pidiendo' || srv.pausados || !srv.pideCodigo) bp.disabled = true;
      fila2.appendChild(bp);
      if (configurado && u.fase === 'idle') fila2.appendChild(botonSecundario('Cancelar', 'correo-servidor-cancelar'));
    } else {
      var bg = boton(u.fase === 'guardando' ? 'Probando…' : 'Probar y guardar', 'correo-servidor-probar');
      if (u.fase === 'guardando' || srv.pausados) bg.disabled = true;
      fila2.appendChild(bg);
      if (u.fase === 'esperando') fila2.appendChild(botonSecundario('Cambiar los datos', 'correo-servidor-reabrir'));
    }
    pie.appendChild(fila2);
    pie.appendChild(mensajeResultado(u, 'resultado'));
    cont.appendChild(pie);
  }

  function pintaDirecciones(cont, previo) {
    cont.appendChild(cabecera('Direcciones de los correos', 'Quién envía los correos, adónde llegan las respuestas y quién recibe los avisos. Cambiar una dirección pide un código que te mandamos a tu correo.'));
    DIRECCIONES.forEach(function (d) {
      var u = un(d.clave);
      var actual = valorDireccion(d.clave);
      var campo = 'dir-' + d.clave;
      var inp = inputServidor('email', campo, d.max, { inputmode: 'email', 'data-ajuste-correo': d.clave });
      inp.value = previo[campo] != null && !u.reponer ? previo[campo] : actual;   // lo tecleado sobrevive a un repintado; tras guardar, vale lo que dice la edge
      u.reponer = false;
      if (bloqueado(u)) inp.setAttribute('readonly', '');
      var extras = [];
      extras.push(nodo('span', 'font-body-sm text-body-sm text-outline', T('Valor actual') + ': ' + (actual || T('sin valor')), { 'data-correo': 'actual-' + d.clave }));
      var cola = nodo('div', 'flex flex-col gap-2');
      var cod = null;
      if (u.fase === 'esperando' || u.fase === 'guardando') {
        var bc = bloqueCodigo(u, 'dir-codigo-' + d.clave);
        if (previo['dir-codigo-' + d.clave] != null) bc.cod.value = previo['dir-codigo-' + d.clave];
        cola.appendChild(bc.caja); cod = bc;
      }
      var filaB = nodo('div', 'flex flex-wrap items-center gap-3');
      var attrs = { 'data-correo-clave': d.clave };
      if (u.fase === 'idle' || u.fase === 'pidiendo') {
        var bp = boton(u.fase === 'pidiendo' ? 'Pidiendo el código…' : 'Pedir código', 'correo-ajuste-pedir', attrs);
        if (u.fase === 'pidiendo' || !srv.pideCodigo) bp.disabled = true;
        filaB.appendChild(bp);
      } else {
        var bg = boton(u.fase === 'guardando' ? 'Guardando…' : 'Guardar', 'correo-ajuste-guardar', attrs);
        if (u.fase === 'guardando') bg.disabled = true;
        filaB.appendChild(bg);
        if (u.fase === 'esperando') filaB.appendChild(botonSecundario('Cancelar', 'correo-ajuste-cancelar', attrs));
      }
      cola.appendChild(filaB);
      cola.appendChild(mensajeResultado(u, 'resultado-' + d.clave));
      extras.push(cola);
      var f = campoServidor('lw-aj-dir-' + d.clave, d.etiqueta, d.ayuda, inp, d.opcional, extras);
      f.fila.setAttribute('data-correo-fila', d.clave);
      cont.appendChild(f.fila);
    });
    cont.appendChild(nodo('div', 'border-b border-outline-variant/40'));
  }

  function cargaEstadoCorreo(silencioso) {
    if (srv.fase === 'cargando' || srv.cargandoSilencio) return;
    if (silencioso) srv.cargandoSilencio = true; else { srv.fase = 'cargando'; srv.codigo = ''; }
    llamaCorreo({ accion: 'estado' }).then(function (r) {
      srv.cargandoSilencio = false;
      if (r.codigo || !r.d) { if (!silencioso) { srv.fase = 'error'; srv.codigo = r.codigo || 'respuesta_ilegible'; } }   // un refresco que falla deja lo que ya se enseñaba
      else { aplicaRespuestaCorreo(r.d); srv.fase = 'listo'; srv.codigo = ''; }
      pintaServidorCorreo();
    });
  }

  /* ── El flujo de código: pedir → escribir las 6 cifras → guardar. Igual para el servidor y para cada dirección. ─────────────────────── */
  function leeCampo(campo) { var cont = document.getElementById('lw-aj-correo-servidor'); var i = cont && cont.querySelector('[data-correo-campo="' + campo + '"]'); return i ? i.value : ''; }
  function vacia(campo) { var cont = document.getElementById('lw-aj-correo-servidor'); var i = cont && cont.querySelector('[data-correo-campo="' + campo + '"]'); if (i) i.value = ''; }
  function sueltaCodigo(u) { u.fase = 'idle'; u.caduca = 0; u.correo = ''; }
  function aplicaCodigoPedido(u, d) {
    var s = d && typeof d.caduca_en === 'number' && d.caduca_en > 0 && d.caduca_en <= 3600 ? d.caduca_en : CADUCA_POR_DEFECTO_S;
    u.correo = textoSimple(d && d.correo_enmascarado, 120);
    u.caduca = Date.now() + s * 1000;
    u.minutos = Math.max(1, Math.round(s / 60));
    u.fase = 'esperando';
  }
  // Un fallo al pedir: nada queda pedido y no se deja ninguna contraseña en la pantalla.
  function falloAlPedir(u, r) {
    sueltaCodigo(u);
    u.codigo = r.codigo || 'respuesta_ilegible';
    u.queFallo = 'No se pidió el código';
    u.extra = '';
    if (u.codigo === 'envios_pausados') srv.pausados = true;
  }

  function pedirServidor() {
    var u = un('servidor');
    if (u.fase !== 'idle' || srv.ocupado) return;
    var host = leeCampo('host').trim(), user = leeCampo('user').trim(), pass = leeCampo('pass'), nom = leeCampo('nombre').trim();
    u.ok = ''; u.codigo = ''; u.extra = ''; u.queFallo = 'No se pidió el código';
    if (!host || !user || !pass) { u.codigo = 'faltan_datos'; pintaServidorCorreo(); return; }
    var cuerpo = { accion: 'pedir_codigo', alcance: 'servidor', host: host, port: 465, user: user, pass: pass };
    if (nom) cuerpo.nombre = nom;
    u.fase = 'pidiendo'; srv.ocupado = 'servidor';
    pintaServidorCorreo();
    llamaCorreo(cuerpo).then(function (r) {
      cuerpo.pass = '';
      srv.ocupado = '';
      if (r.codigo || !r.d || r.d.codigo !== 'codigo_enviado') { falloAlPedir(u, r); vacia('pass'); }
      else aplicaCodigoPedido(u, r.d);
      pintaServidorCorreo();
    });
  }

  function probarCorreo() {
    var u = un('servidor');
    if (u.fase !== 'esperando' || srv.ocupado) return;
    var codigo = leeCampo('codigo').trim();
    u.ok = ''; u.codigo = ''; u.extra = ''; u.queFallo = 'No se guardó';
    if (!/^[0-9]{6}$/.test(codigo)) { u.codigo = 'codigo_mal_formado'; pintaServidorCorreo(); return; }
    if (Date.now() > u.caduca) { sueltaCodigo(u); u.codigo = 'codigo_caducado'; vacia('pass'); vacia('reauth'); pintaServidorCorreo(); return; }
    var cuerpo = { accion: 'probar_y_guardar', host: leeCampo('host').trim(), port: 465, user: leeCampo('user').trim(), pass: leeCampo('pass'), codigo: codigo };
    var nom = leeCampo('nombre').trim();
    if (nom) cuerpo.nombre = nom;
    var re = leeCampo('reauth');
    if (re) cuerpo.contrasena_actual = re;
    vacia('reauth');   // la de la cuenta sale del DOM en cuanto se lee; la del buzón se queda (bloqueada) por si hay que repetir con el MISMO código
    u.fase = 'guardando'; srv.ocupado = 'servidor';
    pintaServidorCorreo();
    llamaCorreo(cuerpo).then(function (r) {
      cuerpo.pass = ''; cuerpo.contrasena_actual = '';
      srv.ocupado = '';
      if (r.codigo || !r.d) {
        u.codigo = r.codigo || 'respuesta_ilegible';
        u.extra = '';
        if (u.codigo === 'reautenticar' || u.codigo === 'clave_actual_incorrecta') srv.reauth = true;
        if (u.codigo === 'prueba_fallida') {
          var fase = r.d && r.d.fase;
          var det = detalleTecnico(r.d);
          u.extra = ((fase === 'verify' ? T('No se pudo iniciar sesión en el servidor: revisa servidor, usuario y contraseña.')
            : fase === 'envio' ? T('Se conectó, pero no se pudo enviar el correo de prueba.') : '') + (det ? ' ' + T('Código técnico') + ': ' + det : '')).trim();
        }
        if (u.codigo === 'envios_pausados') srv.pausados = true;
        if (CODIGO_SIGUE[u.codigo]) u.fase = 'esperando';   // el código sigue valiendo: se puede repetir sin tocar nada
        else { sueltaCodigo(u); vacia('pass'); }            // codigo_no_valido, sin sesión, no es super admin…: hay que empezar de nuevo
      } else {
        aplicaRespuestaCorreo(r.d);
        sueltaCodigo(u); vacia('pass'); srv.reauth = false; srv.editando = false;
        var aviso = r.d.aviso === 'enviado' ? ' ' + T('Se avisó del cambio por el servidor anterior.')
          : r.d.aviso === 'no_enviado' ? ' ' + T('No se pudo avisar por el servidor anterior (el cambio se hizo igualmente).')
          : r.d.aviso === 'sin_destinatario' ? ' ' + T('No había nadie más a quien avisar; queda anotado en el registro de cambios.') : '';
        u.ok = T('Guardado. Se envió un correo de prueba a') + ' ' + String(typeof r.d.prueba_enviada_a === 'string' ? r.d.prueba_enviada_a : '') + '.' + aviso;
        registroCargado = false;   // el registro de cambios tiene una fila nueva (correo_salida)
      }
      pintaServidorCorreo();
    });
  }

  function direccionOk(v) { return v.length <= 254 && /^[^\s@<>()\[\]\\,;:"]+@[^\s@<>()\[\]\\,;:"]+\.[A-Za-z]{2,}$/.test(v); }
  function fijaDireccion(clave, valor) {   // hasta que llegue el estado de la edge, la casilla enseña lo que acaba de confirmarse
    srv.remitente = srv.remitente || {}; srv.avisos = srv.avisos || {};
    if (clave === 'email_from') srv.remitente.email_from = valor; else if (clave === 'email_reply_to') srv.remitente.reply_to = valor;
    else if (clave === 'email_avisos_soporte') srv.avisos.soporte = valor; else if (clave === 'email_avisos_sistema') srv.avisos.sistema = valor;
  }
  function leeDireccion(clave) { return leeCampo('dir-' + clave).trim(); }

  function pedirAjuste(clave) {
    var u = un(clave);
    if (u.fase !== 'idle' || srv.ocupado) return;
    var valor = leeDireccion(clave);
    u.ok = ''; u.codigo = ''; u.extra = ''; u.queFallo = 'No se pidió el código';
    if (valor === valorDireccion(clave)) u.codigo = 'sin_cambios';
    else if (!(clave === 'email_reply_to' && valor === '') && !direccionOk(valor)) u.codigo = 'direccion_mal_formada';
    if (u.codigo) { pintaServidorCorreo(); return; }
    u.fase = 'pidiendo'; srv.ocupado = clave;
    pintaServidorCorreo();
    llamaCorreo({ accion: 'pedir_codigo', alcance: 'ajuste', clave: clave, valor: valor }).then(function (r) {
      srv.ocupado = '';
      if (r.codigo || !r.d || r.d.codigo !== 'codigo_enviado') falloAlPedir(u, r); else aplicaCodigoPedido(u, r.d);
      pintaServidorCorreo();
    });
  }

  function guardarAjuste(clave) {
    var u = un(clave);
    if (u.fase !== 'esperando' || srv.ocupado) return;
    var cont = document.getElementById('lw-aj-correo-servidor');
    var ci = cont && cont.querySelector('[data-correo-campo="dir-codigo-' + clave + '"]');
    var codigo = ci ? ci.value.trim() : '';
    u.ok = ''; u.codigo = ''; u.extra = ''; u.queFallo = 'No se guardó';
    if (!/^[0-9]{6}$/.test(codigo)) { u.codigo = 'codigo_mal_formado'; pintaServidorCorreo(); return; }
    if (Date.now() > u.caduca) { sueltaCodigo(u); u.codigo = 'codigo_caducado'; pintaServidorCorreo(); return; }
    u.fase = 'guardando'; srv.ocupado = clave;
    var valor = leeDireccion(clave);
    pintaServidorCorreo();
    llamaCorreo({ accion: 'guardar_ajuste', clave: clave, valor: valor, codigo: codigo }).then(function (r) {
      srv.ocupado = '';
      if (r.codigo || !r.d) {
        u.codigo = r.codigo || 'respuesta_ilegible';
        if (CODIGO_SIGUE[u.codigo]) u.fase = 'esperando'; else sueltaCodigo(u);
        if (u.codigo === 'envios_pausados') srv.pausados = true;
      } else {
        sueltaCodigo(u);
        var cambiado = r.d.cambiado === true;
        var aviso = cambiado && r.d.aviso === 'enviado' ? ' ' + T('Se avisó del cambio por el servidor anterior.')
          : cambiado && r.d.aviso === 'no_enviado' ? ' ' + T('No se pudo avisar por el servidor anterior (el cambio se hizo igualmente).')
          : cambiado && r.d.aviso === 'sin_destinatario' ? ' ' + T('No había nadie más a quien avisar; queda anotado en el registro de cambios.') : '';
        u.ok = cambiado ? T('Guardado.') + aviso : T('Sin cambios: ya valía eso.');
        u.reponer = true; fijaDireccion(clave, valor);
        registroCargado = false;
        cargaEstadoCorreo(true);   // el valor nuevo y el remitente efectivo salen de la edge, no de lo tecleado
      }
      pintaServidorCorreo();
    });
  }

  document.addEventListener('click', function (ev) {
    var b = ev.target.closest && ev.target.closest('[data-accion]');
    if (!b || !b.hasAttribute('data-real')) return;
    var a = b.getAttribute('data-accion');
    if (a.indexOf('correo-') !== 0) return;
    ev.stopPropagation();
    var clave = b.getAttribute('data-correo-clave') || '';
    if (a === 'correo-servidor-pedir') pedirServidor();
    else if (a === 'correo-servidor-probar') probarCorreo();
    else if (a === 'correo-servidor-editar') { srv.editando = true; un('servidor').ok = ''; pintaServidorCorreo(); }
    else if (a === 'correo-servidor-cancelar') { var us = un('servidor'); sueltaCodigo(us); us.codigo = ''; us.ok = ''; srv.editando = false; srv.reauth = false; vacia('pass'); pintaServidorCorreo(); }
    else if (a === 'correo-servidor-reabrir') { var ur = un('servidor'); sueltaCodigo(ur); ur.codigo = ''; ur.ok = ''; srv.reauth = false; vacia('pass'); vacia('codigo'); pintaServidorCorreo(); }
    else if (a === 'correo-ajuste-pedir' && clave) pedirAjuste(clave);
    else if (a === 'correo-ajuste-guardar' && clave) guardarAjuste(clave);
    else if (a === 'correo-ajuste-cancelar' && clave) { var ua = un(clave); sueltaCodigo(ua); ua.codigo = ''; ua.ok = ''; pintaServidorCorreo(); }
    else if (a === 'correo-estado-reintentar') { srv.fase = 'inicial'; pintaServidorCorreo(); }
  }, true);
  // Al abrir la pestaña Correo por primera vez (hash) se trae el estado; ya cargado, no se vuelve a pedir.
  window.addEventListener('hashchange', function () { if (datos && desdeHash() === 'correo' && srv.fase === 'inicial') pintaServidorCorreo(); });

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
