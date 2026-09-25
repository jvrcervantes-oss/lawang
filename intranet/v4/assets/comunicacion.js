/* comunicacion.js — /intranet/v4/comunicacion/ (23-sep-2026, encargo del owner:
 * «algo como "Comunicación" para poder escribir yo ahí las plantillas y que lo
 * mandes a los agentes de la intranet»).
 *
 * Fichero propio y no REG['comunicacion'] de datos.js: es la única pantalla
 * que lo usa, y datos.js ya pasa de 7.000 líneas. Vive en v4/assets/ (no en
 * la carpeta de la pantalla) para que sella_assets.py le ponga su ?v=.
 *
 * Lo que esta pantalla NO decide (revisión previa #47, Seguridad + Datos):
 *  · A quién llega: el navegador manda user_ids; el email lo pone la base
 *    (`comunicado_encolar` lee `usuarios` activos). Nunca un email tecleado.
 *  · Cuándo sale: el navegador solo ENCOLA. Entrega la Edge `comunicados-envio`
 *    (despertada al encolar, y el cron de 10 min como red). Cerrar la pestaña
 *    no deja nada a medias.
 *  · Si se puede cambiar: al encolar se congela en la base. Aquí solo se
 *    deshabilitan los campos para no ofrecer lo que la base va a rechazar.
 *  · La vista previa la pinta send_email.php (preview:true) con la plantilla
 *    de verdad; no hay una copia de la plantilla en JS que pueda divergir. */
(function () {
  'use strict';

  /* El dominio de la instancia es el de esta página (ERP F3, 25-sep-2026): el botón por defecto, la validación y la
     ayuda lo toman de aquí, no de un literal. En Lawang es lawangproperties.com y se ve igual que antes; el
     servidor aplica la misma regla con config_instancia.dominio_web (cta_dominio_permitido). */
  var DOMINIO = location.hostname.replace(/^www\./, '');
  var DOMINIO_RX = DOMINIO.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  var CTA_DEFECTO = { url: location.origin + '/intranet/', texto: 'Abrir la intranet' };
  function pintaAyudaCta() {
    var el = document.querySelector('[data-lw-cta-ayuda]');
    if (el) el.textContent = window.lwT ? window.lwT('El botón solo puede llevar a %dominio, a un email o a WhatsApp. Si lo dejas vacío, lleva a la intranet.', { dominio: DOMINIO })
                                          : 'El botón solo puede llevar a %dominio, a un email o a WhatsApp. Si lo dejas vacío, lleva a la intranet.'.replace('%dominio', DOMINIO);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', pintaAyudaCta); else pintaAyudaCta();
  var ROLES = [
    { k: 'agente', t: 'Agentes' },
    { k: 'sales_manager', t: 'Sales managers' },
    { k: 'project_manager', t: 'Project managers' },
    { k: 'admin', t: 'Admins' },
    { k: 'super_admin', t: 'Super admins' }
  ];
  var ROL_DEFECTO = { agente: true, sales_manager: true };
  var ESTADO_TXT = { pendiente: 'En cola', enviando: 'Enviando', ok: 'Enviado', error: 'Falló' };

  function $(id) { return document.getElementById(id); }
  function esc(s) { var d = document.createElement('div'); d.textContent = s == null ? '' : String(s); return d.innerHTML.replace(/"/g, '&quot;'); }
  function fecha(x) { if (!x) return '—'; var d = new Date(x); return isNaN(d) ? '—' : d.toLocaleString('es-ES', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }); }
  function mal(err, pref) {
    console.error('[comunicacion]', pref, err);
    var t = (window.lwErrorHumano ? window.lwErrorHumano(err, pref) : (pref + ': ' + ((err && err.message) || err)));
    (typeof toastMal === 'function' ? toastMal : alert)(t);
  }
  function bien(t) { if (typeof toast === 'function') toast(t); }

  var sb = null;
  var actual = null;           // fila de `comunicados` abierta, o null = nuevo
  var sucio = false;           // hay cambios sin guardar en el formulario
  var usuarios = [];
  var envios = [];             // del comunicado abierto
  var marcados = {};           // user_id -> true
  var sondeo = null;

  var campos = ['lw-com-asunto', 'lw-com-encabezado', 'lw-com-cuerpo', 'lw-com-cta-texto', 'lw-com-cta-url'];

  function leeForm() {
    var v = function (id) { return $(id).value.trim(); };
    return {
      asunto: v('lw-com-asunto'),
      encabezado: v('lw-com-encabezado') || null,
      cuerpo: $('lw-com-cuerpo').value.replace(/\s+$/, ''),
      cta_texto: v('lw-com-cta-texto') || null,
      cta_url: v('lw-com-cta-url') || null
    };
  }
  /* Revisión del asunto (24-sep-2026). Hostinger bloqueó el correo de admin@ por
     «Content Spam» y mandó su guía: asunto nunca vacío ni todo en mayúsculas,
     sin «Re:», sin palabras-reclamo, sin exceso de símbolos, sin acortadores.
     Lo que el filtro castiga seguro BLOQUEA (valida); lo dudoso solo AVISA y se
     enseña al guardar y en la confirmación de envío. El asunto que sale lleva
     además el nombre de cada destinatario delante (Edge comunicados-envio). */
  var PALABRAS_SPAM = ['gratis', 'free', 'sin coste', 'sin costo', 'no cost', 'tanpa biaya', 'urgente', 'urgent',
    'ganador', 'winner', 'pemenang', 'hadiah', 'regalo', 'gift', 'dinero', 'money', 'uang', 'precio más bajo',
    'lowest price', 'harga terendah', 'prueba', 'test', 'tes', 'check', 'periksa', 'read me', 'léeme',
    'open this letter', 'abre esta carta', 'oferta', 'offer'];
  var ACORTADORES = /\b(bit\.ly|tinyurl\.com|t\.co|goo\.gl|ow\.ly|is\.gd|buff\.ly|cutt\.ly|rebrand\.ly|s\.id)\//i;
  function erroresAsunto(a) {
    if (!a) return 'Falta el asunto.';
    if (/^\s*(re|fw|fwd|rv)\s*:/i.test(a)) return 'El asunto no puede empezar por «Re:» ni «Fwd:»: los filtros de spam lo castigan.';
    var letras = a.replace(/[^\p{L}]/gu, '');
    if (letras.length >= 4 && letras === letras.toUpperCase()) return 'El asunto no puede ir todo en mayúsculas: los filtros de spam lo castigan.';
    // Hostinger, 24-sep: «no utilice una sola palabra ("HOLA", "PRUEBA") como asunto»
    if ((a.match(/[\p{L}\p{N}]+/gu) || []).length < 2) return 'El asunto no puede ser una sola palabra («Hola», «Novedades»): los filtros de spam lo castigan.';
    return null;
  }
  function avisosAsunto(f) {
    var avisos = [], bajo = ' ' + f.asunto.toLowerCase().replace(/[^\p{L}\p{N}\s]/gu, ' ').replace(/\s+/g, ' ') + ' ';
    var vistas = PALABRAS_SPAM.filter(function (p) { return bajo.indexOf(' ' + p + ' ') >= 0; });
    if (vistas.length) avisos.push('El asunto lleva palabras que los filtros de spam vigilan: «' + vistas.join('», «') + '».');
    var simbolos = (f.asunto.match(/[\[\]{}<>%^!?$€*#|~_=+]/g) || []).length;
    if (/[!?¡¿.]{2,}/.test(f.asunto.replace(/\.{3}|…/g, ''))) avisos.push('Nada de puntuación repetida en el asunto («!!», «??»).');
    else if (simbolos >= 2) avisos.push('El asunto lleva muchos símbolos (corchetes, %, !, >…). Mejor solo palabras.');
    var mayus = (f.asunto.match(/\b\p{Lu}{4,}\b/gu) || []);
    if (mayus.length) avisos.push('Mejor sin palabras enteras en mayúsculas en el asunto: «' + mayus.join('», «') + '».');
    if (ACORTADORES.test(f.cuerpo + ' ' + (f.cta_url || ''))) avisos.push('Hay un enlace acortado (bit.ly y similares): pon la dirección completa.');
    return avisos;
  }

  function valida(f) {
    var ea = erroresAsunto(f.asunto);
    if (ea) return ea;
    if (!f.cuerpo.trim()) return 'Falta el texto.';
    if (!!f.cta_url !== !!f.cta_texto) return 'El botón necesita texto y enlace, o ninguno de los dos.';
    if (f.cta_url && !new RegExp('^(https://([a-z0-9-]+\\.)*' + DOMINIO_RX + '(/\\S*)?|mailto:\\S+@\\S+|https://wa\\.me/\\d{6,20})$', 'i').test(f.cta_url))
      return 'El enlace del botón solo puede ir a ' + DOMINIO + ', a un email (mailto:) o a WhatsApp (https://wa.me/…).';
    return null;
  }

  function pintaForm() {
    var c = actual || {};
    $('lw-com-asunto').value = c.asunto || '';
    $('lw-com-encabezado').value = c.encabezado || '';
    $('lw-com-cuerpo').value = c.cuerpo || '';
    $('lw-com-cta-texto').value = c.id ? (c.cta_texto || '') : CTA_DEFECTO.texto;
    $('lw-com-cta-url').value = c.id ? (c.cta_url || '') : CTA_DEFECTO.url;
    var congelado = !!(c.enviado_en);
    campos.forEach(function (id) { $(id).disabled = congelado; });
    $('lw-com-guardar').hidden = congelado;
    $('lw-com-borrar').hidden = !c.id || congelado;
    $('lw-com-duplicar').hidden = !c.id;
    $('lw-com-titulo').textContent = c.id ? (c.asunto || 'Comunicado') : 'Nuevo comunicado';
    $('lw-com-estado').textContent = !c.id ? 'Borrador sin guardar.'
      : congelado ? 'Enviado por primera vez el ' + fecha(c.enviado_en) + '. Ya no se puede cambiar: para otra versión, «Duplicar».'
      : 'Borrador · guardado ' + fecha(c.actualizado_en) + '.';
    $('lw-com-previa-caja').hidden = true;
    sucio = false;
    cuenta();
  }
  function cuenta() { $('lw-com-cuenta').textContent = '(' + $('lw-com-cuerpo').value.length + ' / 5000)'; }

  // ── lista de comunicados ──────────────────────────────────────────────────
  function cargaLista() {
    return Promise.all([
      sb.from('comunicados').select('id,asunto,encabezado,cuerpo,cta_url,cta_texto,creado_en,actualizado_en,enviado_en')
        .order('actualizado_en', { ascending: false }).limit(100),
      sb.from('comunicado_envios').select('comunicado_id,estado').eq('es_prueba', false)
    ]).then(function (r) {
      var ul = $('lw-com-lista');
      if (r[0].error) { ul.innerHTML = '<li class="px-6 py-6 font-body-sm text-body-sm text-error">No se pudieron traer los comunicados.</li>'; mal(r[0].error, 'Comunicados'); return []; }
      var n = {};
      (r[1].data || []).forEach(function (e) {
        var x = n[e.comunicado_id] = n[e.comunicado_id] || { ok: 0, total: 0 };
        x.total++; if (e.estado === 'ok') x.ok++;
      });
      var filas = r[0].data || [];
      ul.innerHTML = filas.length ? filas.map(function (c) {
        var x = n[c.id];
        var chip = c.enviado_en
          ? '<span class="inline-flex px-2 py-0.5 rounded-full text-[11px] font-label-md uppercase tracking-wider bg-primary-fixed text-on-primary-fixed">Enviado ' + (x ? x.ok + '/' + x.total : '') + '</span>'
          : '<span class="inline-flex px-2 py-0.5 rounded-full text-[11px] font-label-md uppercase tracking-wider bg-surface-container-high text-on-surface-variant">Borrador</span>';
        var activo = actual && actual.id === c.id;
        return '<li><button type="button" data-com="' + esc(c.id) + '" class="w-full text-left px-6 py-4 border-b border-outline-variant/30 hover:bg-surface-container-low' + (activo ? ' bg-surface-container' : '') + '">' +
          '<div class="font-label-md text-label-md text-on-surface">' + esc(c.asunto) + '</div>' +
          '<div class="mt-1 flex items-center gap-2 font-body-sm text-body-sm text-outline">' + chip + '<span>' + esc(fecha(c.enviado_en || c.actualizado_en)) + '</span></div></button></li>';
      }).join('') : '<li class="px-6 py-6 font-body-sm text-body-sm text-outline">Aún no hay comunicados. Escribe el primero a la izquierda.</li>';
      return filas;
    });
  }

  // ── destinatarios ─────────────────────────────────────────────────────────
  function estadoDe(uid) {
    for (var i = 0; i < envios.length; i++) if (!envios[i].es_prueba && envios[i].user_id === uid) return envios[i].estado;
    return null;
  }
  function yaCubierto(uid) { var e = estadoDe(uid); return e === 'ok' || e === 'pendiente' || e === 'enviando'; }

  function pintaRoles() {
    $('lw-com-roles').innerHTML = ROLES.map(function (r) {
      var del = usuarios.filter(function (u) { return u.rol === r.k; });
      if (!del.length) return '';
      var todos = del.every(function (u) { return marcados[u.user_id] || yaCubierto(u.user_id); });
      return '<button type="button" data-rol="' + r.k + '" aria-pressed="' + todos + '" class="px-3 py-1.5 rounded-full font-label-md text-[12px] border ' +
        (todos ? 'bg-deep-lagoon text-on-primary border-deep-lagoon' : 'border-outline-variant text-on-surface-variant hover:bg-surface-container-high') + '">' +
        esc(r.t) + ' · ' + del.length + '</button>';
    }).join('');
  }
  function pintaPersonas() {
    $('lw-com-personas').innerHTML = usuarios.map(function (u) {
      var e = estadoDe(u.user_id), cubierto = yaCubierto(u.user_id);
      var nota = e ? '<span class="ml-auto text-[11px] font-label-md ' + (e === 'error' ? 'text-error' : 'text-outline') + '">' + esc(ESTADO_TXT[e]) + '</span>' : '';
      var id = 'lw-com-u-' + u.user_id;
      return '<label for="' + id + '" class="flex items-center gap-3 py-1.5 border-b border-outline-variant/20 cursor-pointer' + (cubierto ? ' opacity-60' : '') + '">' +
        '<input type="checkbox" id="' + id + '" data-uid="' + esc(u.user_id) + '"' + (cubierto || marcados[u.user_id] ? ' checked' : '') + (cubierto ? ' disabled' : '') + '>' +
        '<span class="min-w-0"><span class="block font-body-md text-body-md text-on-surface truncate">' + esc(u.nombre || u.email) + '</span>' +
        '<span class="block font-body-sm text-[12px] text-outline truncate">' + esc(u.email) + ' · ' + esc(u.rol) + '</span></span>' + nota + '</label>';
    }).join('');
    pintaRoles();
    pintaBotonEnviar();
  }
  function aEnviar() { return usuarios.filter(function (u) { return marcados[u.user_id] && !yaCubierto(u.user_id); }); }
  function pintaBotonEnviar() {
    var n = aEnviar().length, b = $('lw-com-enviar');
    b.disabled = n === 0;
    b.textContent = n ? 'Enviar a ' + n + (n === 1 ? ' persona' : ' personas') : 'Enviar';
    var fallidos = envios.filter(function (e) { return !e.es_prueba && e.estado === 'error'; }).length;
    $('lw-com-enviar-nota').textContent = fallidos ? fallidos + ' envío(s) fallaron: siguen marcados; «Enviar» los reintenta.' : '';
  }
  function marcaPorDefecto() {
    marcados = {};
    usuarios.forEach(function (u) {
      // un fallo vuelve a salir marcado: reintentarlo es lo que se quiere casi siempre
      if (ROL_DEFECTO[u.rol] || estadoDe(u.user_id) === 'error') marcados[u.user_id] = true;
    });
  }

  // ── registro ──────────────────────────────────────────────────────────────
  function cargaEnvios() {
    if (!actual || !actual.id) { envios = []; pintaRegistro(); return Promise.resolve(); }
    var id = actual.id;
    return sb.from('comunicado_envios').select('id,user_id,email,nombre,es_prueba,estado,intentos,error,encolado_en,enviado_en')
      .eq('comunicado_id', id).order('encolado_en', { ascending: false }).then(function (r) {
        if (!actual || actual.id !== id) return;
        if (r.error) { mal(r.error, 'Registro de envíos'); return; }
        envios = r.data || [];
        pintaRegistro();
      });
  }
  function pintaRegistro() {
    var tb = $('lw-com-registro');
    if (!envios.length) { tb.innerHTML = '<tr><td colspan="3" class="px-4 py-6 text-center font-body-sm text-body-sm text-outline">Todavía no se ha enviado.</td></tr>'; }
    else tb.innerHTML = envios.map(function (e) {
      /* Un fallo que aún se va a reintentar también se enseña (23-sep-2026: Hostinger
         cortó el SMTP a mitad de envío y la pantalla solo decía «En cola», sin motivo). */
      var fallo = e.estado !== 'ok' && e.error;
      var color = e.estado === 'ok' ? 'text-on-surface' : (e.estado === 'error' || fallo) ? 'text-error' : 'text-outline';
      var txt = e.estado === 'pendiente' && fallo ? 'Falló · se reintenta (' + (e.intentos || 1) + ' de 3)' : (ESTADO_TXT[e.estado] || e.estado);
      return '<tr class="border-b border-outline-variant/30">' +
        '<td class="px-4 py-2.5"><div class="font-body-md text-body-md text-on-surface">' + esc(e.nombre || e.email) + (e.es_prueba ? ' <span class="text-[11px] font-label-md uppercase tracking-wider text-outline">prueba</span>' : '') + '</div>' +
          '<div class="font-body-sm text-[12px] text-outline">' + esc(e.email) + '</div></td>' +
        '<td class="px-4 py-2.5 font-label-md text-label-md ' + color + '">' + esc(txt) +
          (fallo ? '<div class="font-body-sm text-[12px] text-outline font-normal" title="' + esc(e.error) + '">' + esc(e.error.slice(0, 90)) + '</div>' : '') + '</td>' +
        '<td class="px-4 py-2.5 font-body-sm text-body-sm text-outline">' + esc(fecha(e.enviado_en || e.encolado_en)) + '</td></tr>';
    }).join('');
    if (usuarios.length) pintaPersonas();
    /* Mientras quede algo en camino, se refresca solo: rápido el primer minuto
       (el despertador entrega en segundos) y luego cada 20 s hasta 15 min,
       porque un reintento lo recoge el cron de 10 min. Pasado eso, se dice. */
    var enCamino = envios.some(function (e) { return e.estado === 'pendiente' || e.estado === 'enviando'; });
    if (enCamino && !sondeo) {
      var vueltas = 0, inicio = Date.now();
      sondeo = setInterval(function () {
        vueltas++;
        if (Date.now() - inicio > 15 * 60000) {
          clearInterval(sondeo); sondeo = null;
          $('lw-com-enviar-nota').textContent = 'El registro ha dejado de actualizarse solo: recarga la página para ver el estado.';
          return;
        }
        if (vueltas > 15 && vueltas % 5) return;   // tras el 1.er minuto, una de cada cinco (20 s)
        cargaEnvios().then(function () {
          if (!envios.some(function (e) { return e.estado === 'pendiente' || e.estado === 'enviando'; })) {
            clearInterval(sondeo); sondeo = null; cargaLista();
          }
        });
      }, 4000);
    }
  }

  // ── abrir / nuevo ─────────────────────────────────────────────────────────
  function abre(c) {
    if (sondeo) { clearInterval(sondeo); sondeo = null; }
    actual = c; envios = [];
    pintaForm();
    return cargaEnvios().then(function () { marcaPorDefecto(); pintaPersonas(); cargaLista(); });
  }
  function puedeSoltar() {
    if (!sucio) return Promise.resolve(true);
    return window.lwConfirmar({ titulo: 'Hay cambios sin guardar', cuerpo: 'Si sigues, se pierden.', confirmar: 'Descartar cambios' });
  }

  // ── guardar ───────────────────────────────────────────────────────────────
  function guarda() {
    var f = leeForm(), e = valida(f);
    if (e) { toastMal(e); return Promise.resolve(null); }
    var b = $('lw-com-guardar'); b.disabled = true;
    var p = actual && actual.id
      ? sb.from('comunicados').update(f).eq('id', actual.id).select().single()
      : sb.from('comunicados').insert(f).select().single();
    return p.then(function (r) {
      b.disabled = false;
      if (r.error) { mal(r.error, 'No se guardó'); return null; }
      actual = r.data; pintaForm(); cargaLista();
      var av = avisosAsunto(f);
      if (av.length) toastMal('Guardado, pero revisa: ' + av.join(' ')); else bien('Comunicado guardado.');
      return actual;
    }, function (err) { b.disabled = false; mal(err, 'No se guardó'); return null; });
  }
  // prueba y envío trabajan SIEMPRE sobre lo guardado: la base lee de la tabla
  function guardadoPrimero() {
    if (actual && actual.id && !sucio) return Promise.resolve(actual);
    if (actual && actual.enviado_en) return Promise.resolve(actual);
    return guarda();
  }

  // ── vista previa ──────────────────────────────────────────────────────────
  function previa() {
    var f = leeForm(), e = valida(f);
    if (e) { toastMal(e); return; }
    var b = $('lw-com-previa'); b.disabled = true;
    sb.auth.getSession().then(function (s) {
      var t = s && s.data && s.data.session && s.data.session.access_token;
      return fetch('/contracts/api/send_email.php', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Suite-Token': t || '' },
        body: JSON.stringify({
          preview: true, subject: f.asunto, message: f.cuerpo, encabezado: f.encabezado || '', etiqueta: 'Comunicado al equipo',
          cta_url: f.cta_url || CTA_DEFECTO.url, cta_texto: f.cta_texto || CTA_DEFECTO.texto
        })
      });
    }).then(function (r) { return r.json(); }).then(function (j) {
      b.disabled = false;
      if (!j || !j.ok || !j.html) { mal({ message: (j && j.error) || 'sin respuesta' }, 'No se pudo generar la vista previa'); return; }
      $('lw-com-previa-marco').srcdoc = j.html;
      $('lw-com-previa-caja').hidden = false;
      $('lw-com-previa-cerrar').focus();
    }).catch(function (err) { b.disabled = false; mal(err, 'No se pudo generar la vista previa'); });
  }

  // ── prueba ────────────────────────────────────────────────────────────────
  function prueba() {
    var b = $('lw-com-prueba'); b.disabled = true;
    guardadoPrimero().then(function (c) {
      if (!c) { b.disabled = false; return; }
      return sb.rpc('comunicado_prueba', { p_comunicado: c.id }).then(function (r) {
        b.disabled = false;
        if (r.error) { mal(r.error, 'No se mandó la prueba'); return; }
        bien('Prueba en camino a ' + r.data + '. Llega con «Borrador:» y tu nombre delante del asunto.');
        cargaEnvios();
      });
    }).catch(function (err) { b.disabled = false; mal(err, 'No se mandó la prueba'); });
  }

  // ── enviar ────────────────────────────────────────────────────────────────
  function envia() {
    var lista = aEnviar();
    if (!lista.length) return;
    var f = leeForm(), e = valida(f);
    if (e) { toastMal(e); return; }
    var nombres = lista.slice(0, 8).map(function (u) { return esc(u.nombre || u.email); }).join(', ') + (lista.length > 8 ? ' y ' + (lista.length - 8) + ' más' : '');
    window.lwConfirmar({
      titulo: 'Enviar a ' + lista.length + (lista.length === 1 ? ' persona' : ' personas'),
      cuerpo: '<p><b>' + esc(f.asunto) + '</b></p>' +
        '<p>Cada persona lo recibe con su nombre delante (por ejemplo «' + esc(((lista[0].nombre || '').split(/\s+/)[0] || 'Nombre') + ', …') + '»), para que el asunto no salga repetido.</p>' +
        avisosAsunto(f).map(function (a) { return '<p><b>Ojo:</b> ' + esc(a) + '</p>'; }).join('') +
        '<p>' + nombres + '.</p>' +
        '<p>Sale por email ahora mismo. Desde este momento el comunicado ya no se puede cambiar.</p>',
      confirmar: 'Enviar'
    }).then(function (si) {
      if (!si) return;
      var b = $('lw-com-enviar'); b.disabled = true;
      guardadoPrimero().then(function (c) {
        if (!c) { pintaBotonEnviar(); return; }
        return sb.rpc('comunicado_encolar', { p_comunicado: c.id, p_user_ids: lista.map(function (u) { return u.user_id; }) }).then(function (r) {
          if (r.error) { mal(r.error, 'No se envió'); pintaBotonEnviar(); return; }
          bien(r.data ? r.data + ' email(s) en camino. El registro de abajo se actualiza solo.' : 'Nada que enviar: esas personas ya lo tenían.');
          return sb.from('comunicados').select('*').eq('id', c.id).single().then(function (rr) {
            if (!rr.error) actual = rr.data;
            pintaForm(); cargaLista();
            return cargaEnvios();
          });
        });
      }).catch(function (err) { mal(err, 'No se envió'); pintaBotonEnviar(); });
    });
  }

  // ── duplicar / borrar ─────────────────────────────────────────────────────
  function duplica() {
    if (!actual || !actual.id) return;
    // con cambios sin guardar se copia lo que hay EN PANTALLA, no lo guardado:
    // si no, la copia salía sin lo último escrito y abre() lo tiraba sin avisar
    var c = sucio ? leeForm() : actual, e = sucio ? valida(c) : null;
    if (e) { toastMal(e); return; }
    sb.from('comunicados').insert({
      asunto: c.asunto, encabezado: c.encabezado, cuerpo: c.cuerpo, cta_url: c.cta_url, cta_texto: c.cta_texto
    }).select().single().then(function (r) {
      if (r.error) { mal(r.error, 'No se duplicó'); return; }
      bien('Copia creada como borrador: cámbiala y envíala cuando quieras.');
      abre(r.data);
    });
  }
  function borra() {
    if (!actual || !actual.id || actual.enviado_en) return;
    window.lwConfirmar({ titulo: 'Borrar este borrador', cuerpo: esc(actual.asunto), confirmar: 'Borrar', tono: 'peligro' }).then(function (si) {
      if (!si) return;
      sb.from('comunicados').delete().eq('id', actual.id).then(function (r) {
        if (r.error) { mal(r.error, 'No se borró'); return; }
        bien('Borrador borrado.');
        abre(null);
      });
    });
  }

  // ── arranque ──────────────────────────────────────────────────────────────
  function soloAdmin() {
    var main = document.querySelector('main');
    if (main) main.innerHTML = '<div style="max-width:32rem;margin:6rem auto 0;background:#fff;border-radius:12px;padding:2rem;text-align:center">' +
      '<h1 style="margin:0 0 8px;font-size:22px;color:#104C4F">Solo administración</h1>' +
      '<p style="margin:0;font-size:14px;color:#44483f">Esta pantalla es de administración (roles admin / super_admin).</p></div>';
  }

  function cablea() {
    $('lw-com-form').addEventListener('submit', function (ev) { ev.preventDefault(); guarda(); });
    campos.forEach(function (id) { $(id).addEventListener('input', function () { sucio = true; if (id === 'lw-com-cuerpo') cuenta(); }); });
    $('lw-com-previa').addEventListener('click', previa);
    // popup de la vista previa: se cierra con la X, con Esc o pinchando fuera
    function cierraPrevia() { $('lw-com-previa-caja').hidden = true; }
    $('lw-com-previa-cerrar').addEventListener('click', cierraPrevia);
    $('lw-com-previa-caja').addEventListener('click', function (ev) { if (ev.target.hasAttribute('data-cierra-previa')) cierraPrevia(); });
    document.addEventListener('keydown', function (ev) { if (ev.key === 'Escape' && !$('lw-com-previa-caja').hidden) cierraPrevia(); });
    $('lw-com-prueba').addEventListener('click', prueba);
    $('lw-com-enviar').addEventListener('click', envia);
    $('lw-com-duplicar').addEventListener('click', duplica);
    $('lw-com-borrar').addEventListener('click', borra);
    $('lw-com-nuevo').addEventListener('click', function () { puedeSoltar().then(function (ok) { if (ok) abre(null); }); });
    $('lw-com-lista').addEventListener('click', function (ev) {
      var b = ev.target.closest && ev.target.closest('[data-com]');
      if (!b) return;
      var id = b.getAttribute('data-com');
      puedeSoltar().then(function (ok) {
        if (!ok) return;
        sb.from('comunicados').select('*').eq('id', id).single().then(function (r) {
          if (r.error) { mal(r.error, 'No se abrió'); return; }
          abre(r.data);
        });
      });
    });
    $('lw-com-personas').addEventListener('change', function (ev) {
      var uid = ev.target.getAttribute && ev.target.getAttribute('data-uid');
      if (!uid) return;
      if (ev.target.checked) marcados[uid] = true; else delete marcados[uid];
      pintaRoles(); pintaBotonEnviar();
    });
    $('lw-com-roles').addEventListener('click', function (ev) {
      var b = ev.target.closest && ev.target.closest('[data-rol]');
      if (!b) return;
      var rol = b.getAttribute('data-rol'), poner = b.getAttribute('aria-pressed') !== 'true';
      usuarios.forEach(function (u) {
        if (u.rol !== rol || yaCubierto(u.user_id)) return;
        if (poner) marcados[u.user_id] = true; else delete marcados[u.user_id];
      });
      pintaPersonas();
    });
    window.addEventListener('beforeunload', function (ev) { if (sucio) { ev.preventDefault(); ev.returnValue = ''; } });
  }

  function arranca() {
    if (!window.LW_AUTH) { console.error('[comunicacion] sin guard'); return; }
    window.LW_AUTH.then(function (aut) {
      var rol = aut && aut.ficha && aut.ficha.rol;
      if (rol !== 'admin' && rol !== 'super_admin') { soloAdmin(); return; }
      sb = aut.sb;
      cablea();
      sb.from('usuarios').select('user_id,nombre,email,rol').eq('activo', true).order('nombre').then(function (r) {
        if (r.error) { mal(r.error, 'Usuarios'); return; }
        usuarios = (r.data || []).filter(function (u) { return u.email; });
        // ?id=<uuid> abre ese comunicado (enlace directo desde el registro)
        var id = new URLSearchParams(location.search).get('id');
        if (!id) return abre(null);
        return sb.from('comunicados').select('*').eq('id', id).single().then(function (rr) { abre(rr.error ? null : rr.data); });
      });
    });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', arranca); else arranca();
})();
