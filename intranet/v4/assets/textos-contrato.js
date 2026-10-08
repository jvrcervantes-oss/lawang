/* textos-contrato.js — la pantalla «Textos de contrato» (/intranet/v4/textos-contrato/), 8-oct-2026.
   Encargo «plantillas de contrato por empresa», S7 (encargos/20261007_lawang_plantillas_por_empresa.md). La parte pura (trocear el documento, bloques fijos, construir el
   texto nuevo, comparar, simular) vive en textos-contrato-nucleo.js; aquí solo hay pantalla y llamadas.

   FRONTERA FRONT/BACK. Esta pantalla NO valida nada y NO escribe en ninguna tabla: pregunta y pide, siempre por RPC (las siete que la migración
   20261009010000 abre a `authenticated` y a nadie más):
     plantilla_contrato_versiones_lista   la lista y el historial (sin cuerpo)          plantilla_contrato_edicion   el texto a editar, sin notas, con sus bloques fijos y permisos
     plantilla_contrato_cuerpo_version    el texto de una versión (historial y diff)    plantilla_contrato_revisa    ensayo sin guardar: lo que diría guardar y si sería activable
     plantilla_contrato_guarda_borrador   guardar (motivo obligatorio)                  plantilla_contrato_activa    activar (solo el super administrador de esa empresa)
     plantilla_contrato_descarta_borrador descartar un borrador (pasa a «retirada»: nada se borra)
   Y, desde el 8-oct-2026 (E7/E8), con el parámetro `p_variante` (la revisión que se edita; por defecto 'estandar') en edicion y guarda_borrador, y
     plantilla_contrato_cambios_sensibles  el registro de quién cambió qué parte sensible (historial)   (guarda_borrador gana p_confirma_sensibles; revisa gana p_variante y devuelve las partes sensibles)
     plantilla_campo_propio_lista         el catálogo de campos propios de la empresa (nombre en llano de las pastillas {{cx_…}} y menú «Insertar campo»)
   Las pestañas Revisiones y Campos (altas, archivos, borrados) viven en textos-contrato-config.js, que usa el puente window.LW_TC de abajo.
   Si la pantalla enseña un botón que la base no deja pulsar, la base contesta y se enseña SU mensaje (con textContent: repite un trozo del texto recibido).
   Mostrar u ocultar «Activar» según el rol es solo reflejo: lo que manda es es_super_admin_de(empresa) en plantilla_contrato_activa.

   ENGANCHE POR IDENTIFICADOR. Todo se encuentra por data-tc-* o por id, nunca por un rótulo (norma del 29-sep-2026: cambiar un texto no rompe nada). */
(function () {
  'use strict';

  var TC = window.LW_TEXTOS;
  if (!TC) { console.error('[textos-contrato] falta textos-contrato-nucleo.js'); return; }
  var T = function (s, h) { return window.lwT ? window.lwT(s, h) : s; };
  var esc = TC.esc;
  var $ = function (id) { return document.getElementById(id); };
  var IDIOMAS = [['es', 'Español'], ['en', 'English'], ['id', 'Bahasa']];

  /* El estado de la pantalla, en un solo sitio. */
  var E = {
    sb: null, ficha: null, empresas: [], empresa: null, nombres: {}, nombresOk: true,
    lista: [], porSlug: {}, slug: null, orden: {},
    ed: null,                // lo que devolvió plantilla_contrato_edicion
    doc: '', trozos: [], secs: null, pars: [], editables: 0, bloqueados: 0, sinLocalizar: 0, soloLectura: false,
    cambios: {},             // { i: textoNuevo } — solo lo que la persona ha tocado y anotado con «Listo»
    edicion: null, edicionSucia: false,   // el párrafo abierto (clave sec|bloque) y si se ha escrito algo sin anotar
    baseTrozos: null, camb: null, baseAviso: false, vistos: {},   // la versión de la que se parte, qué cambió respecto a ella, y lo que la persona dio por revisado
    lang: 'es', langs: [], ancla: null, filtro: '', hits: [], hi: 0, rechazo: false,
    campos: null, camposOk: true, etiqP: null,   // etiquetas de los marcadores (contracts/tokens.json)
    variante: 'estandar',    // la revisión que se edita (E7): 'estandar' = la de siempre
    cx: null, cxOk: true, cxEj: {}, cxEt: {}, rangoCx: null,   // catálogo de campos propios de la empresa (E8): lo que devolvió plantilla_campo_propio_lista, y el último cursor dentro del párrafo abierto
    cuerpos: {}              // caché de cuerpos por version_id (el hash es el etag)
  };

  /* ── pequeños ayudantes ───────────────────────────────────────────────────────────────────────────────────────────────────────── */
  function fFecha(x) { try { return new Date(x).toLocaleDateString(window.LW_IDIOMA === 'en' ? 'en-GB' : 'es-ES', { day: '2-digit', month: 'short', year: 'numeric' }); } catch (_) { return String(x || ''); } }
  function fFechaHora(x) { try { return new Date(x).toLocaleString(window.LW_IDIOMA === 'en' ? 'en-GB' : 'es-ES', { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' }); } catch (_) { return String(x || ''); } }
  function msg(e) { return (e && e.message) ? e.message : String(e || ''); }
  function pill(texto, tono) { return '<span class="tc-pill tc-' + (tono || 'neutro') + '">' + esc(texto) + '</span>'; }
  function nombreDe(slug) { return E.nombres[slug] || slug; }
  function hayCambios() { return Object.keys(E.cambios).length > 0 || E.edicionSucia; }
  /* «No he podido leer» y «no hay» se ven distinto, siempre (norma de la suite: un vacío no puede significar las dos cosas). */
  function nota(id, texto, tono) {
    var n = $(id); if (!n) return;
    n.hidden = !texto; n.textContent = texto || '';
    n.className = 'tc-nota' + (tono ? ' tc-nota-' + tono : '');
  }
  function rpc(nombre, args) {
    return Promise.resolve(E.sb.rpc(nombre, args || {})).then(function (r) { return r || { error: { message: T('La base no ha contestado') } }; },
      function (e) { return { error: { message: msg(e) || T('La base no ha contestado') } }; });
  }
  function preguntaPerder() {
    if (!hayCambios() || typeof window.lwConfirmar !== 'function') return Promise.resolve(true);
    return window.lwConfirmar({ titulo: T('Hay cambios sin guardar'), cuerpo: '<p>' + esc(T('Si sigues, se pierde lo que has escrito en este texto y no se ha guardado como borrador.')) + '</p>',
      confirmar: T('Descartar los cambios'), tono: 'peligro' });
  }

  /* ── arranque ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────── */
  function arranca(aut) {
    E.sb = aut.sb; E.ficha = aut.ficha || null;
    var esSuper = window.LW_ROL ? window.LW_ROL.esSuperAdmin(E.ficha) : false;
    var esGlobal = window.LW_ROL ? window.LW_ROL.esGlobal(E.ficha) : false;
    $('tc-rol').textContent = esSuper
      ? T('Puedes cambiar el texto, guardar borradores y activarlos en tu empresa.')
      : T('Puedes cambiar el texto y guardar borradores de tu empresa. Activar un texto lo hace el super administrador de la empresa.');
    if (esGlobal) $('tc-rol').textContent += ' ' + T('Ves las dos empresas.');
    cableaEventos();
    var cat = window.LW_ROL ? window.LW_ROL.misEmpresas(E.ficha) : Promise.resolve([]);
    cat.then(function (emps) {
      E.empresas = emps || [];
      if (!E.empresas.length) { nota('tc-estado', T('No he podido saber de qué empresa eres: recarga la pantalla o pide a administración que te asigne una.'), 'mal'); $('tc-lista').innerHTML = ''; return; }
      var sel = $('tc-empresa');
      sel.innerHTML = E.empresas.map(function (e) { return '<option value="' + esc(e.clave) + '">' + esc(e.nombre) + '</option>'; }).join('');
      $('tc-empresa-caja').hidden = E.empresas.length < 2;
      E.empresa = E.empresas[0].clave;
      Promise.resolve(E.sb.from('plantillas_contrato').select('slug,nombre,orden,archivada').order('orden')).then(function (r) {
        if (r && !r.error && r.data) r.data.forEach(function (p, i) { E.nombres[p.slug] = p.nombre; E.orden[p.slug] = i; });
        else E.nombresOk = false;
      }, function () { E.nombresOk = false; }).then(cargaLista).then(function () { avisa('lw-tc-listo'); });
    });
  }
  function avisa(nombre, detalle) { document.dispatchEvent(new CustomEvent(nombre, { detail: detalle || {} })); }

  function cableaEventos() {
    $('tc-empresa').addEventListener('change', function () {
      var nueva = this.value, sel = this;
      preguntaPerder().then(function (ok) {
        if (!ok) { sel.value = E.empresa; return; }
        E.empresa = nueva; cierraEditor(); cargaLista().then(function () { avisa('lw-tc-empresa'); });
      });
    });
    $('tc-lista').addEventListener('click', function (ev) {
      var b = ev.target.closest('[data-tc-editar],[data-tc-historial],[data-tc-descartar],[data-tc-ver-revs]'); if (!b) return;
      ev.stopPropagation();
      if (b.hasAttribute('data-tc-editar')) abreEditor(b.getAttribute('data-tc-editar'), 'estandar');
      else if (b.hasAttribute('data-tc-historial')) abreHistorial(b.getAttribute('data-tc-historial'), 'estandar');
      else if (b.hasAttribute('data-tc-ver-revs')) avisa('lw-tc-ir', { tab: 'revisiones', slug: b.getAttribute('data-tc-ver-revs') });
      else descarta(b.getAttribute('data-tc-descartar'));
    });
    $('tc-hist-cuerpo').addEventListener('click', function (ev) {
      var b = ev.target.closest('[data-tc-diff]'); if (!b) return;
      ev.stopPropagation(); verDiff(b.getAttribute('data-tc-diff'));
    });
    var ed = $('tc-editor');
    ed.addEventListener('click', function (ev) {
      var b = ev.target.closest('[data-tc-idioma],[data-tc-ir],[data-tc-hit],[data-tc-visto],[data-tc-par-listo],[data-tc-par-deshacer],#tc-simular,#tc-guardar,#tc-deshacer,#tc-cerrar,[data-tc-previa-idioma],[data-tc-cx-menu],[data-tc-cx],[data-tc-ir-tab]');
      if (b) {
        ev.stopPropagation();
        if (b.hasAttribute('data-tc-cx-menu')) { alternaMenuCx(); return; }
        if (b.hasAttribute('data-tc-cx')) { insertaCampo(b.getAttribute('data-tc-cx')); return; }
        if (b.hasAttribute('data-tc-ir-tab')) { avisa('lw-tc-ir', { tab: b.getAttribute('data-tc-ir-tab') }); return; }
        if (b.hasAttribute('data-tc-idioma')) { if (commitEdicion()) { E.lang = b.getAttribute('data-tc-idioma'); E.hi = 0; pintaDocumento(true); } }
        else if (b.hasAttribute('data-tc-ir')) { if (commitEdicion()) irA($('tc-trozos').querySelector('[data-tc-sec="' + b.getAttribute('data-tc-ir') + '"]')); }
        else if (b.hasAttribute('data-tc-hit')) irAHit(Number(b.getAttribute('data-tc-hit')));
        else if (b.hasAttribute('data-tc-visto')) { E.vistos[b.getAttribute('data-tc-visto') + '|' + E.lang] = true; pintaDocumento(false); }
        else if (b.hasAttribute('data-tc-par-listo')) commitEdicion();
        else if (b.hasAttribute('data-tc-par-deshacer')) deshacerPar();
        else if (b.hasAttribute('data-tc-previa-idioma')) pintaPrevia(b.getAttribute('data-tc-previa-idioma'));
        else if (b.id === 'tc-simular') simula();
        else if (b.id === 'tc-guardar') guarda();
        else if (b.id === 'tc-deshacer') deshaz();
        else if (b.id === 'tc-cerrar') preguntaPerder().then(function (ok) { if (ok) cierraEditor(); });
        return;
      }
      var par = ev.target.closest('[data-tc-par]');
      if (par && $('tc-trozos').contains(par)) abrePar(par.getAttribute('data-tc-par'), ev);
    });
    ed.addEventListener('keydown', function (ev) {
      var menu = ev.key === 'Escape' ? ed.querySelector('.tc-menu-cx:not([hidden])') : null;
      if (menu) { ev.preventDefault(); cierraMenuCx(); }
      else if (ev.key === 'Escape' && E.edicion) { ev.preventDefault(); deshacerPar(); }
      else if (ev.key === 'Enter' && (ev.ctrlKey || ev.metaKey) && E.edicion) { ev.preventDefault(); commitEdicion(); }
      else if (ev.key === 'Enter' && ev.target.matches && ev.target.matches('.tc-par-edit') && !E.edicion) { ev.preventDefault(); abrePar(ev.target.getAttribute('data-tc-par'), null); }
      else if (ev.key === 'Enter' && ev.target.id === 'tc-buscar') { ev.preventDefault(); irAHit(ev.shiftKey ? -1 : 1); }
    });
    var papel = $('tc-trozos'), pendiente = false;
    papel.addEventListener('input', alEscribir);
    papel.addEventListener('beforeinput', alAntesDeEscribir);
    papel.addEventListener('paste', alPegar);
    papel.addEventListener('drop', function (ev) { if (E.edicion) ev.preventDefault(); });
    papel.addEventListener('scroll', function () { if (pendiente) return; pendiente = true; window.requestAnimationFrame(function () { pendiente = false; marcaIndiceActivo(); }); });
    $('tc-buscar').addEventListener('input', function () {
      if (!commitEdicion()) return;
      E.filtro = this.value.trim().toLowerCase(); E.hi = 0; pintaDocumento(false); if (E.hits.length) { E.hi = -1; irAHit(1); }
    });
    $('tc-f-cambios').addEventListener('change', function () { if (commitEdicion()) pintaDocumento(false); else this.checked = !this.checked; });
    $('tc-f-sin-sens').addEventListener('change', function () { if (commitEdicion()) pintaDocumento(false); else this.checked = !this.checked; });
    try { $('tc-indice-det').open = window.matchMedia('(min-width: 1000px)').matches; } catch (_) { /* MUDO A PROPOSITO: sin matchMedia el índice queda plegado; se abre con un clic */ }
    $('tc-act-nombre').addEventListener('input', actualizaActivar);
    $('tc-act-ok').addEventListener('change', actualizaActivar);
    $('tc-act-boton').addEventListener('click', function (ev) { ev.stopPropagation(); activa(); });
    window.addEventListener('beforeunload', function (ev) { if (hayCambios()) { ev.preventDefault(); ev.returnValue = ''; } });
    /* El último cursor dentro del párrafo abierto: pulsar «Insertar campo» mueve el foco al botón y sin esto no se sabría dónde poner la pastilla. */
    document.addEventListener('selectionchange', function () {
      if (!E.edicion) return;
      var sel = window.getSelection(); if (!sel || !sel.rangeCount) return;
      var r = sel.getRangeAt(0), n = r.startContainer.nodeType === 1 ? r.startContainer : r.startContainer.parentElement;
      var s = n && n.closest ? n.closest('[data-tc-trozo][contenteditable="true"]') : null;
      if (s && $('tc-trozos').contains(s)) E.rangoCx = r.cloneRange();
    });
  }

  /* ── la lista ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────── */
  function cargaLista() {
    var cuerpo = $('tc-lista');
    cuerpo.innerHTML = '<tr><td colspan="5" class="tc-vacio">' + esc(T('Trayendo las plantillas…')) + '</td></tr>';
    nota('tc-estado', '');
    return rpc('plantilla_contrato_versiones_lista', { p_empresa: E.empresa, p_slug: null }).then(function (r) {
      if (r.error) {
        cuerpo.innerHTML = '<tr><td colspan="5" class="tc-vacio tc-mal"></td></tr>';
        cuerpo.querySelector('td').textContent = T('No he podido leer las plantillas: ') + msg(r.error);
        E.lista = []; E.porSlug = {};
        return;
      }
      E.lista = r.data || []; E.porSlug = {};
      E.lista.forEach(function (v) { (E.porSlug[v.slug] = E.porSlug[v.slug] || []).push(v); });
      var slugs = Object.keys(E.porSlug).sort(function (a, b) {
        var oa = a in E.orden ? E.orden[a] : 999, ob = b in E.orden ? E.orden[b] : 999;
        return oa - ob || (a < b ? -1 : 1);
      });
      if (!E.nombresOk) nota('tc-estado', T('No he podido leer los nombres de las plantillas: se enseña su clave.'), 'aviso');
      if (!slugs.length) { cuerpo.innerHTML = '<tr><td colspan="5" class="tc-vacio">' + esc(T('Tu empresa todavía no tiene textos de contrato en la base.')) + '</td></tr>'; return; }
      cuerpo.innerHTML = slugs.map(filaLista).join('');
    });
  }

  function filaLista(slug) {
    var todas = E.porSlug[slug];
    var vs = todas.filter(function (v) { return (v.variante || 'estandar') === 'estandar'; });   // esta tabla es la revisión estándar; las demás viven en la pestaña Revisiones
    var otras = {}; todas.forEach(function (v) { if ((v.variante || 'estandar') !== 'estandar') otras[v.variante] = 1; });
    var nOtras = Object.keys(otras).length;
    var activa = vs.filter(function (v) { return v.estado === 'activa'; })[0];
    var borrador = vs.filter(function (v) { return v.estado === 'borrador' && v.origen === 'empresa'; })[0];
    var semilla = vs.filter(function (v) { return v.origen === 'semilla'; })[0];
    var colAct = activa
      ? '<div class="tc-fuerte">v' + esc(activa.version) + '</div><div class="tc-peq">' + esc(fFecha(activa.activado_en)) + (activa.activado_por ? ' · ' + esc(activa.activado_por) : '') + '</div>'
      : pill(T('Ninguna activa'), 'neutro') + '<div class="tc-peq">' + esc(T('Los contratos usan la copia inicial del estudio')) + '</div>';
    var colBor = borrador
      ? '<div class="tc-fuerte">v' + esc(borrador.version) + '</div><div class="tc-peq">' + esc(fFechaHora(borrador.fecha)) + ' · ' + esc(borrador.autor) + '</div>'
        + (borrador.activable ? '' : '<div class="tc-peq tc-aviso-txt" data-tc-bloqueo="1">' + esc(borrador.bloqueo_motivo || '') + '</div>')
      : '<span class="tc-peq">—</span>';
    var chips = [];
    if (!activa && semilla) chips.push(pill(T('Semilla del estudio v') + semilla.version, 'neutro'));
    if (borrador && borrador.activable) chips.push(pill(T('Borrador listo para activar'), 'ok'));
    if (nOtras) chips.push('<button type="button" class="tc-chip" data-real="1" data-tc-ver-revs="' + esc(slug) + '">' + esc(nOtras === 1 ? T('1 revisión más') : T('%n revisiones más', { n: nOtras })) + '</button>');
    var acc = '<button type="button" class="tc-btn" data-real="1" data-tc-editar="' + esc(slug) + '">' + esc(borrador ? T('Seguir editando') : T('Editar')) + '</button>'
      + '<button type="button" class="tc-btn tc-btn-suave" data-real="1" data-tc-historial="' + esc(slug) + '">' + esc(T('Historial')) + '</button>'
      + (borrador ? '<button type="button" class="tc-btn tc-btn-suave tc-peligro" data-real="1" data-tc-descartar="' + esc(borrador.id) + '">' + esc(T('Descartar borrador')) + '</button>' : '');
    return '<tr' + (slug === E.slug ? ' class="tc-fila-sel"' : '') + '><td><div class="tc-fuerte">' + esc(nombreDe(slug)) + '</div><div class="tc-peq">' + esc(slug) + '</div></td>'
      + '<td>' + colAct + '</td><td>' + colBor + '</td><td>' + (chips.join(' ') || '<span class="tc-peq">—</span>') + '</td><td class="tc-acc">' + acc + '</td></tr>';
  }

  function descarta(id) {
    var v = E.lista.filter(function (x) { return x.id === id; })[0]; if (!v) return;
    window.lwConfirmar({ titulo: T('¿Descartar este borrador?'), cuerpo: '<p>' + esc(T('El borrador pasa a «retirada» y deja de ofrecerse. No se borra: queda en el historial con quién lo descartó y cuándo.')) + '</p>',
      confirmar: T('Descartar borrador'), tono: 'peligro' }).then(function (ok) {
      if (!ok) return;
      rpc('plantilla_contrato_descarta_borrador', { p_version: id }).then(function (r) {
        if (r.error) { toastMal(T('No se pudo descartar: ') + msg(r.error)); return; }
        toast(T('Borrador descartado.'));
        if (E.slug === v.slug && E.variante === (v.variante || 'estandar')) { E.cambios = {}; cierraEditor(); }
        cargaLista();
      });
    });
  }

  /* ── el editor: el contrato como un documento ───────────────────────────────────────────────────────────────────────────────────── */
  /* Se pinta con DOM propio (createElement + textContent; el HTML de la plantilla NO entra nunca en la página): cada trozo editable es un <span> y cada marcador, una
     pastilla que no se puede partir. Lo que se GUARDA sigue saliendo de TC.construye (reemplazo literal sobre el original), así que la fidelidad de las 20
     plantillas no depende de este pintado. La simulación fiel sigue en el iframe sandbox de abajo. */
  var SVG = 'http://www.w3.org/2000/svg';
  function el(tag, cls, txt) { var n = document.createElement(tag); if (cls) n.className = cls; if (txt != null) n.textContent = txt; return n; }
  function nodoTexto(s) { return document.createTextNode(s); }
  function boton(txt, attrs, cls) {                 // data-real: sin él, maqueta.js se come el clic y enseña «disponible en la fase de cableado»
    var b = el('button', 'tc-btn ' + (cls || 'tc-btn-suave'), txt); b.type = 'button'; b.setAttribute('data-real', '1');
    Object.keys(attrs || {}).forEach(function (k) { b.setAttribute(k, attrs[k]); });
    return b;
  }
  function candado() {
    var s = document.createElementNS(SVG, 'svg'); s.setAttribute('width', '14'); s.setAttribute('height', '14'); s.setAttribute('viewBox', '0 0 16 16'); s.setAttribute('aria-hidden', 'true'); s.setAttribute('focusable', 'false');
    var r = document.createElementNS(SVG, 'rect'), p = document.createElementNS(SVG, 'path');
    [['x', '3'], ['y', '7'], ['width', '10'], ['height', '7'], ['fill', 'none'], ['stroke', 'currentColor'], ['stroke-width', '1.4']].forEach(function (a) { r.setAttribute(a[0], a[1]); });
    [['d', 'M5 7V5a3 3 0 0 1 6 0v2'], ['fill', 'none'], ['stroke', 'currentColor'], ['stroke-width', '1.4']].forEach(function (a) { p.setAttribute(a[0], a[1]); });
    s.appendChild(r); s.appendChild(p); return s;
  }
  function etiqueta(k) { return (E.cxEt && E.cxEt[k]) || TC.etiquetaMarcador(k, E.campos); }
  function nombreIdioma(l) { return l === 'general' ? T('General') : (IDIOMAS.filter(function (x) { return x[0] === l; })[0] || [l, l])[1]; }
  function idiomasReales() { return (E.langs || []).filter(function (l) { return l !== 'general'; }); }
  function tituloSec(sec) {
    var t = (E.secs && E.secs.titulos[sec]) || {}, l = E.lang;
    return TC.ws(t[l] || t.es || t.en || t.id || t.general || '') || (sec === 0 ? T('Encabezado') : T('Cláusula %n', { n: sec }));
  }
  function valorDe(t) { return Object.prototype.hasOwnProperty.call(E.cambios, t.i) ? E.cambios[t.i] : TC.ws(t.texto); }

  function cargaEtiquetas() {
    if (E.etiqP) return E.etiqP;
    var URL_TOKENS = '/contracts/tokens.json';
    E.etiqP = Promise.resolve(window.fetch ? window.fetch(URL_TOKENS) : null).then(function (r) {
      if (!r || !r.ok) throw new Error('tokens');
      return r.json();
    }).then(function (j) { E.campos = TC.etiquetasDeTokens(j, window.LW_IDIOMA === 'en' ? 'en' : 'es'); E.camposOk = true; },
      function () { E.campos = null; E.camposOk = false; });   // no es un fallo mudo: abreEditor lo enseña en el aviso («se enseñan abreviados»)
    return E.etiqP;
  }

  function abreEditor(slug, variante) {
    var vr = variante || 'estandar';
    return preguntaPerder().then(function (ok) {
      if (!ok) return;
      E.cambios = {}; E.edicion = null; E.edicionSucia = false; E.vistos = {}; E.baseAviso = false; E.baseTrozos = null; E.camb = null;
      E.slug = slug; E.variante = vr; E.rangoCx = null;
      var cab = $('tc-editor'); cab.hidden = false;
      $('tc-ed-titulo').textContent = nombreDe(slug);
      $('tc-trozos').textContent = ''; $('tc-trozos').appendChild(el('p', 'tc-vacio', T('Trayendo el texto…')));
      $('tc-ed-barra').hidden = true; $('tc-previa-caja').hidden = true; $('tc-activar').hidden = true; nota('tc-ed-aviso', ''); nota('tc-ed-estado', '');
      $('tc-indice').textContent = ''; $('tc-aterriza').textContent = '';
      cab.scrollIntoView({ behavior: 'smooth', block: 'start' });
      Promise.all([rpc('plantilla_contrato_edicion', { p_empresa: E.empresa, p_slug: slug, p_variante: vr }), cargaEtiquetas().then(cargaCatalogoCx)]).then(function (res) {
        var r = res[0];
        if (E.slug !== slug || E.variante !== vr) return;              // se abrió otra mientras tanto
        if (r.error || !r.data) {
          $('tc-trozos').textContent = ''; $('tc-trozos').appendChild(el('p', 'tc-vacio tc-mal', T('No he podido leer el texto: ') + msg(r.error)));
          return;
        }
        var d = r.data; E.ed = d; E.doc = d.cuerpo_html || '';
        if (d.variante && d.variante !== 'estandar') $('tc-ed-titulo').textContent = nombreDe(slug) + ' · ' + (d.variante_nombre || d.variante);
        var tr = TC.trocea(E.doc); E.trozos = tr.trozos;
        E.secs = TC.secciones(E.doc, E.trozos);
        E.editables = E.trozos.filter(function (t) { return t.editable; }).length;
        E.soloLectura = !!d.solo_global;
        var s = TC.situaBloquesFijos(E.doc, d.bloques_fijos || [], d.bloques_fijos_motivos);
        E.sinLocalizar = s.sinLocalizar;
        E.bloqueados = TC.marcaBloqueados(E.trozos, s.spans, E.soloLectura);
        var langs = {}; E.trozos.forEach(function (t) { if (t.editable) langs[t.lang || 'general'] = 1; });
        E.lang = langs.es ? 'es' : (langs.en ? 'en' : (langs.id ? 'id' : 'general'));
        E.langs = Object.keys(langs).sort(function (a, b) { var o = { es: 0, en: 1, id: 2, general: 3 }; return o[a] - o[b]; });
        E.filtro = ''; $('tc-buscar').value = ''; $('tc-motivo').value = ''; $('tc-f-cambios').checked = false; $('tc-f-sin-sens').checked = false; E.hi = 0;
        E.baseTrozos = E.trozos;                                       // hasta saber de qué versión viene, la base es este mismo texto
        pintaCabecera(); pintaDocumento(true); preparaActivar();
        $('tc-ed-barra').hidden = false;
        cargaListaSuave();                                             // la lista marca la fila abierta
        cargaBase(slug);
      });
    });
  }
  /* El catálogo de campos propios de la empresa (E8): con él las pastillas {{cx_…}} llevan su nombre en llano y se pueden insertar. Si la base no contesta, el editor
     sigue y lo dice (un vacío «no hay campos» y un «no he podido leer» se ven distinto). */
  function cargaCatalogoCx() {
    return rpc('plantilla_campo_propio_lista', { p_empresa: E.empresa, p_con_uso: false }).then(function (r) {
      E.cxEj = {}; E.cxEt = {};
      if (r.error || !Array.isArray(r.data)) { E.cx = null; E.cxOk = false; return; }
      E.cx = r.data; E.cxOk = true;
      var idioma = window.LW_IDIOMA === 'en' ? 'en' : 'es';
      r.data.forEach(function (c) { E.cxEj[c.clave] = window.LW_CX.ejemplo(c); E.cxEt[c.clave] = window.LW_CX.etiqueta(c, idioma); });
    });
  }
  /* El texto de la versión de la que viene este borrador: con él se sabe qué idioma se tocó (y cuál «falta revisar») aunque se haya guardado y reabierto. */
  function cargaBase(slug) {
    var d = E.ed, v = (E.lista || []).filter(function (x) { return x.id === d.version_id; })[0];
    if (!v || !v.hereda_de || d.origen !== 'empresa') return;
    cuerpoDe(v.hereda_de).then(function (c) {
      if (E.slug !== slug) return;
      var t = TC.trocea(c).trozos;
      if (t.length !== E.trozos.length) { E.baseAviso = true; pintaCabecera(); return; }
      E.baseTrozos = t; if (!E.edicion) pintaDocumento(false);
    }, function () { if (E.slug === slug) { E.baseAviso = true; pintaCabecera(); } });
  }
  function cargaListaSuave() { /* repinta la marca de fila sin volver a pedir nada */
    var slugs = Object.keys(E.porSlug); if (!slugs.length) return;
    var filas = $('tc-lista').querySelectorAll('tr'); [].forEach.call(filas, function (f) { f.classList.remove('tc-fila-sel'); });
    var b = E.variante === 'estandar' ? $('tc-lista').querySelector('[data-tc-editar="' + ((window.CSS && CSS.escape) ? CSS.escape(E.slug) : E.slug) + '"]') : null; if (b) b.closest('tr').classList.add('tc-fila-sel');
  }

  function cierraEditor() {
    E.cambios = {}; E.edicion = null; E.edicionSucia = false; E.slug = null; E.ed = null; E.trozos = []; E.doc = ''; E.pars = []; E.camb = null;
    $('tc-editor').hidden = true; $('tc-previa-caja').hidden = true; $('tc-activar').hidden = true;
    cargaListaSuave();
  }

  function origenTxt(d) {
    if (d.estado === 'activa') return T('la versión activa');
    if (d.origen === 'semilla') return T('la copia inicial del estudio («semilla»)');
    return T('tu borrador');
  }
  function pintaCabecera() {
    var d = E.ed;
    $('tc-ed-sub').textContent = T('Empiezas desde ') + origenTxt(d) + ' (v' + d.version + ') · ' + (E.empresas.filter(function (x) { return x.clave === d.empresa; })[0] || { nombre: d.empresa }).nombre;
    var avisos = [];
    if (d.solo_global) avisos.push(T('Este texto solo lo cambia el administrador global con su abogado: ') + d.solo_global + T('. Puedes leerlo y simularlo, no editarlo.'));
    else if (E.bloqueados) avisos.push(T('Las partes con candado (foro y ley aplicable, tenencia, escrow e impuestos, prórroga, defectos, datos, partes y firmas, cláusulas negociadas) son sensibles. Puedes escribir en ellas: al guardar tendrás que confirmar el aviso y queda registrado quién, cuándo y el texto de antes y después.'));
    if (E.sinLocalizar > 0) avisos.push(T('No he podido marcar en pantalla %n bloques con candado; la base los protege igualmente al guardar.', { n: E.sinLocalizar }));
    if (d.nunca_activable) avisos.push(T('Esta plantilla no se puede activar nunca para esta empresa: ') + d.nunca_activable);
    if (d.bloqueo && !d.nunca_activable) avisos.push(T('Tal como está, este texto no se podría activar: ') + d.bloqueo);
    if (d.notas_quitadas > 0) avisos.push(T('Se han quitado %n bytes de notas internas del autor del estudio: no se imprimen en el contrato y no se pueden guardar en una versión de empresa.', { n: d.notas_quitadas }));
    if (E.camposOk === false) avisos.push(T('No he podido leer los nombres de los campos: se enseñan abreviados.'));
    if (E.cxOk === false) avisos.push(T('No he podido leer los campos propios de la empresa: sus marcadores se enseñan con la clave y no se pueden insertar.'));
    if (E.baseAviso) avisos.push(T('No he podido comparar con la versión de la que parte este borrador: «falta revisar» solo cuenta lo que cambies ahora.'));
    var n = $('tc-ed-aviso'); n.hidden = !avisos.length; n.textContent = '';
    avisos.forEach(function (a) { n.appendChild(el('p', null, a)); });   // textContent: parte de esto viene de la base
    pintaPestanas();
    var solo = !!d.solo_global;
    $('tc-guardar').disabled = solo; $('tc-motivo').disabled = solo;
    $('tc-guardar').title = solo ? T('Este texto solo lo cambia el administrador global') : '';
  }

  /* ── los párrafos del idioma que se ve ──────────────────────────────────────────────────────────────────────────────────────── */
  /* Un párrafo = los trozos de un mismo bloque (párrafo, celda o título) en el idioma visible. Su clave es sec|bloque. */
  function construyePars() {
    var lang = E.lang === 'general' ? null : E.lang, orden = [], por = {};
    E.trozos.forEach(function (t) {
      if ((t.lang || null) !== lang) return;
      var k = t.sec + '|' + t.bloque, p = por[k];
      if (!p) { p = por[k] = { key: k, sec: t.sec, bloque: t.bloque, trozos: [], titulo: false, sens: false, editable: false }; orden.push(p); }
      p.trozos.push(t);
      if (t.titulo) p.titulo = true;
      if (t.editable) { p.editable = true; if (t.bloqueado) p.sens = true; }
    });
    orden.forEach(function (p) {
      p.editable = p.editable && !E.soloLectura;
      if (E.soloLectura) p.sens = false;                                  // todo el texto es de solo lectura: marcarlo párrafo a párrafo sería ruido
      p.vis = p.trozos.map(function (t) { return TC.segmentos(valorDe(t)).map(function (sg) { return sg.m ? etiqueta(sg.k) : sg.v; }).join(''); }).join(' ');
      p.cambiado = p.trozos.some(function (t) { return E.camb ? !!E.camb.trozo[t.i] : Object.prototype.hasOwnProperty.call(E.cambios, t.i); });
    });
    return orden;
  }
  function parPorKey(k) { return (E.pars || []).filter(function (p) { return p.key === k; })[0]; }
  function nodoPar(k) { return $('tc-trozos').querySelector('[data-tc-par="' + k + '"]'); }
  function pasaFiltros(p) {
    if ($('tc-f-sin-sens').checked && p.sens) return false;
    if ($('tc-f-cambios').checked && !p.cambiado) return false;
    return true;
  }
  function motivoSensible(p) {
    var t0 = p.trozos.filter(function (t) { return t.bloqueado && t.editable; })[0], k = t0 && t0.fijo;
    if (t0 && t0.motivo) return t0.motivo;                                  // el motivo que da la base (plantilla_bloque_regla)
    if (k && k.length > 1) return T('región marcada por Legal «%cl»', { cl: k.replace(/_/g, ' ') });
    if (k === 'S' && p.sec > 0) return T('la cláusula «%cl» no la cambia una empresa sola', { cl: tituloSec(p.sec) });
    return T('foro y ley aplicable, tenencia, impuestos, prórroga, defectos, datos, partes y firmas');
  }

  function pastilla(k, q) {
    var lab = etiqueta(k), ej = TC.muestra(k, E.cxEj), s = el('span', 'tc-marca', lab);
    s.setAttribute('data-tc-marca', k); s.setAttribute('contenteditable', 'false'); s.tabIndex = 0; s.setAttribute('data-ej', ej);
    s.setAttribute('aria-label', lab + '. ' + T('Campo que se rellena solo al emitir el contrato. Ejemplo: ') + ej);
    if (q && lab.toLowerCase().indexOf(q) !== -1) s.classList.add('tc-marca-hit');
    return s;
  }
  function resalta(nodo, v, q) {
    if (!q) { nodo.appendChild(nodoTexto(v)); return; }
    var low = v.toLowerCase(), i = 0, j;
    while ((j = low.indexOf(q, i)) !== -1) {
      if (j > i) nodo.appendChild(nodoTexto(v.slice(i, j)));
      nodo.appendChild(el('mark', null, v.slice(j, j + q.length))); i = j + q.length;
    }
    if (i < v.length) nodo.appendChild(nodoTexto(v.slice(i)));
  }
  function rellena(nodo, txt, q) {
    TC.segmentos(txt).forEach(function (sg) { if (sg.m) nodo.appendChild(pastilla(sg.k, q)); else resalta(nodo, sg.v, q); });
  }

  /* Dos textos pegados sin blanco entre ellos en el original («Contrato Privado» | «de Reserva»: la separación la ponía el estilo) se leen con un espacio, salvo que uno de los dos
     empiece o acabe en puntuación. Solo es pintado: lo que se guarda no cambia. */
  function separaTrozos(a, b) { return /[\p{L}\p{N}}»”)]$/u.test(a.core) && /^[\p{L}\p{N}{«“(]/u.test(b.core); }
  function pintaPar(p, q) {
    var d = el('div', 'tc-par' + (p.titulo ? ' tc-par-titulo' : '') + (p.sens ? ' tc-par-sens' : '') + (p.cambiado ? ' tc-par-cambiado' : '') + (p.editable ? ' tc-par-edit' : '') + (E.ancla === p.key ? ' tc-ancla' : ''));
    d.setAttribute('data-tc-par', p.key);
    if (p.editable) { d.tabIndex = 0; d.title = T('Clic para editar solo este texto'); }
    p.trozos.forEach(function (t, k) {
      if (k > 0 && (p.trozos[k - 1].trail || t.lead || separaTrozos(p.trozos[k - 1], t))) d.appendChild(nodoTexto(' '));
      var s = el('span', 'tc-tr' + (t.editable ? '' : ' tc-tr-fijo'));
      if (t.editable) s.setAttribute('data-tc-trozo', String(t.i));
      rellena(s, valorDe(t), q);
      d.appendChild(s);
    });
    if (p.sens) {
      var n = el('div', 'tc-sens-nota'); n.setAttribute('role', 'note'); n.tabIndex = 0;
      var m = motivoSensible(p);
      n.setAttribute('aria-label', T('Parte sensible: %m. Se puede editar, con aviso.', { m: m }));
      n.appendChild(candado()); n.appendChild(el('span', null, T('Parte sensible: ') + m));
      d.appendChild(n);
    }
    return d;
  }

  function pintaDocumento(aterriza) {
    recalcula();
    E.pars = construyePars();
    var papel = $('tc-trozos'), y = papel.scrollTop, q = E.filtro || '';
    papel.textContent = '';
    var vis = E.pars.filter(pasaFiltros), langs = idiomasReales(), sec = -1, caja = null;
    if (!E.pars.length) papel.appendChild(el('p', 'tc-vacio', T('No hay texto editable en este idioma.')));
    else if (!vis.length) papel.appendChild(el('p', 'tc-vacio', $('tc-f-cambios').checked ? T('Todavía no has cambiado nada en este idioma. Quita el filtro para ver todo el texto.') : T('Ninguna cláusula coincide con los filtros. Quita un filtro para ver más texto.')));
    vis.forEach(function (p) {
      if (p.sec !== sec) {
        sec = p.sec; caja = el('div', 'tc-sec'); caja.setAttribute('data-tc-sec', String(sec)); papel.appendChild(caja);
        if (revisar(sec)) {
          var av = el('div', 'tc-aviso-rev'); av.setAttribute('role', 'status');
          av.appendChild(el('span', null, T('Has cambiado esta cláusula en otro idioma. Revisa que diga lo mismo.')));
          av.appendChild(boton(T('Ya está igual'), { 'data-tc-visto': String(sec) }));
          caja.appendChild(av);
        }
      }
      caja.appendChild(pintaPar(p, q));
    });
    buscaHits();
    papel.scrollTop = y;
    pintaIndice(vis); pintaPestanas(); pintaContador(); resumen();
    if (aterriza) aterrizaPrimera(vis);
  }
  function recalcula() { E.camb = TC.cambiosRespecto(E.baseTrozos, E.trozos, E.cambios); }
  function revisar(sec) {
    if (!E.camb || E.lang === 'general' || E.vistos[sec + '|' + E.lang]) return false;
    return TC.porRevisar(E.camb.sec, sec, E.lang, idiomasReales());
  }
  function cuentaRevisar(lang) {
    if (!E.camb || lang === 'general') return 0;
    var n = 0;
    for (var s = 0; s < (E.secs ? E.secs.n : 0); s++) if (!E.vistos[s + '|' + lang] && TC.porRevisar(E.camb.sec, s, lang, idiomasReales())) n++;
    return n;
  }

  function pintaPestanas() {
    var caja = $('tc-ed-idiomas'); caja.textContent = '';
    (E.langs || []).forEach(function (l) {
      var n = cuentaRevisar(l), b = el('button', 'tc-tab' + (n ? ' tc-tab-rev' : ''));
      b.type = 'button'; b.setAttribute('data-real', '1'); b.setAttribute('data-tc-idioma', l); b.setAttribute('aria-pressed', l === E.lang ? 'true' : 'false');
      b.appendChild(el('span', 'tc-tab-nom', nombreIdioma(l) + (l === 'es' && idiomasReales().length > 1 ? ' · ' + T('principal') : '')));
      if (l !== 'general') b.appendChild(el('span', 'tc-tab-ins', n ? T('cambiado, falta revisar (%n)', { n: n }) : T('al día')));
      caja.appendChild(b);
    });
  }
  function pintaIndice(vis) {
    var caja = $('tc-indice'), secs = [], vistos = {};
    caja.textContent = '';
    (vis || []).forEach(function (p) { if (!vistos[p.sec]) { vistos[p.sec] = { sec: p.sec, libre: false, sens: false, cambiado: false }; secs.push(vistos[p.sec]); } var s = vistos[p.sec]; if (p.editable && !p.titulo && !p.sens) s.libre = true; if (p.sens) s.sens = true; if (p.cambiado) s.cambiado = true; });
    secs.forEach(function (s) {
      var b = el('button', 'tc-ind'); b.type = 'button'; b.setAttribute('data-real', '1'); b.setAttribute('data-tc-ir', String(s.sec));
      b.appendChild(el('span', 'tc-ind-nom', tituloSec(s.sec)));
      var marcas = el('span', 'tc-ind-marcas');
      if (revisar(s.sec)) marcas.appendChild(el('span', 'tc-ind-rev', T('revisar')));
      else if (s.cambiado) marcas.appendChild(el('span', 'tc-ind-cambio', T('editado')));
      if (s.sens && !s.libre) { var c = el('span', 'tc-ind-fijo'); c.appendChild(candado()); c.title = T('Parte sensible'); marcas.appendChild(c); }
      b.appendChild(marcas); caja.appendChild(b);
    });
    $('tc-indice-sum').textContent = T('Índice (%n cláusulas)', { n: secs.length });
    marcaIndiceActivo();
  }
  function marcaIndiceActivo() {
    var papel = $('tc-trozos'), activa = null;
    [].forEach.call(papel.querySelectorAll('.tc-sec'), function (c) { if (c.offsetTop <= papel.scrollTop + 24) activa = c.getAttribute('data-tc-sec'); });
    [].forEach.call($('tc-indice').querySelectorAll('[data-tc-ir]'), function (b) { b.classList.toggle('on', b.getAttribute('data-tc-ir') === activa); });
  }
  function irA(nodo) {
    var papel = $('tc-trozos'); if (!nodo) return;
    papel.scrollTop = Math.max(0, nodo.offsetTop - 12);
    marcaIndiceActivo();
  }
  function aterrizaPrimera(vis) {
    var primera = (vis || []).filter(function (p) { return p.editable && !p.titulo && !p.sens; })[0];
    E.ancla = null;
    var aviso = $('tc-aterriza'); aviso.textContent = '';
    if (!primera) { if (E.soloLectura) aviso.textContent = T('Este texto es de solo lectura para tu usuario.'); return; }
    var n = nodoPar(primera.key);
    E.ancla = primera.key;
    if (n) { irA(n.closest('.tc-sec') || n); n.classList.add('tc-ancla'); }
    aviso.textContent = T('Estás en la primera cláusula que puedes editar: ') + tituloSec(primera.sec) + '. ' + T('Haz clic en un texto para editarlo.');
  }

  /* ── buscar: «3 de 12» ───────────────────────────────────────────────────────────────────────────────────────────────────────── */
  function buscaHits() {
    var q = E.filtro; E.hits = [];
    if (q) E.pars.filter(pasaFiltros).forEach(function (p) { if (p.vis.toLowerCase().indexOf(q) !== -1) E.hits.push(p.key); });
    if (E.hi >= E.hits.length) E.hi = 0;
  }
  function pintaContador() {
    var c = $('tc-hits'); c.textContent = E.filtro ? (E.hits.length ? T('%a de %b', { a: E.hi + 1, b: E.hits.length }) : T('0 resultados')) : '';
    $('tc-hit-ant').disabled = $('tc-hit-sig').disabled = E.hits.length < 2;
  }
  function irAHit(delta) {
    if (!E.hits.length) return;
    E.hi = (E.hi + delta + E.hits.length) % E.hits.length;
    [].forEach.call($('tc-trozos').querySelectorAll('.tc-hit-actual'), function (x) { x.classList.remove('tc-hit-actual'); });
    var n = nodoPar(E.hits[E.hi]); if (n) { n.classList.add('tc-hit-actual'); irA(n); }
    pintaContador();
  }

  /* ── editar un párrafo ──────────────────────────────────────────────────────────────────────────────────────────────────────── */
  function piezasDe(nodo) {
    var out = [];
    (function ir(n) {
      [].forEach.call(n.childNodes, function (c) {
        if (c.nodeType === 3) out.push({ t: 'txt', v: c.nodeValue });
        else if (c.nodeType === 1) {
          var k = c.getAttribute('data-tc-marca');
          if (k !== null && /^[a-z0-9_]{1,60}$/.test(k)) out.push({ t: 'marca', k: k });
          else if (c.nodeName === 'BR') out.push({ t: 'otro', v: ' ' });
          else ir(c);                                                     // cualquier otra cosa que el navegador cuele: solo cuenta su texto
        }
      });
    })(nodo);
    return out;
  }
  function avisosDe(t, txt) {
    var av = TC.avisosTrozo(txt, t.texto, true).map(function (a) { return T(a); });
    TC.faltanMarcadores(txt, t.texto).forEach(function (k) { av.push(T('Falta el campo «%c». Los campos los rellena el contrato: vuelve a ponerlo o pulsa Deshacer.', { c: etiqueta(k) })); });
    return av;
  }
  function leeEdicion(p, d) {                                             // { nuevos: { i: texto }, avisos: [] } de lo que hay escrito ahora
    var nuevos = {}, avisos = [];
    p.trozos.forEach(function (t) {
      if (!t.editable) return;
      var s = d.querySelector('[data-tc-trozo="' + t.i + '"]'); if (!s) return;
      var txt = TC.textoEscrito(piezasDe(s), t.texto);
      nuevos[t.i] = txt;
      avisosDe(t, txt).forEach(function (a) { if (avisos.indexOf(a) === -1) avisos.push(a); });
    });
    return { nuevos: nuevos, avisos: avisos };
  }
  function muestraAvisoPar(d, avisos) {
    var n = d.querySelector('[data-tc-par-av]'); if (!n) return;
    n.textContent = avisos.join(' '); n.hidden = !avisos.length;
  }
  function ponCaret(span, ev) {
    try {
      var r = null;
      if (ev && document.caretRangeFromPoint) r = document.caretRangeFromPoint(ev.clientX, ev.clientY);
      else if (ev && document.caretPositionFromPoint) { var cp = document.caretPositionFromPoint(ev.clientX, ev.clientY); if (cp) { r = document.createRange(); r.setStart(cp.offsetNode, cp.offset); } }
      if (r && span.contains(r.startContainer)) {
        var host = r.startContainer.nodeType === 1 ? r.startContainer : r.startContainer.parentElement, pill = host && host.closest ? host.closest('[data-tc-marca]') : null;
        if (pill) r.setStartAfter(pill);                                  // un clic sobre una pastilla deja el cursor DETRÁS de ella: dentro no se puede escribir
        r.setEnd(r.startContainer, r.startOffset); var sel = window.getSelection(); sel.removeAllRanges(); sel.addRange(r); return;   // inicio = fin: cursor sin selección
      }
      span.focus();
    } catch (_) { /* MUDO A PROPOSITO: sin la posición exacta del clic el cursor queda al principio del texto; escribir funciona igual */ }
  }
  function abrePar(key, ev) {
    var p = parPorKey(key); if (!p || !p.editable || E.edicion === key) return;
    var clicI = ev && ev.target && ev.target.closest ? ev.target.closest('[data-tc-trozo]') : null; clicI = clicI ? clicI.getAttribute('data-tc-trozo') : null;
    if (!commitEdicion()) return;
    p = parPorKey(key); var d = nodoPar(key); if (!p || !d) return;
    E.edicion = key; E.edicionSucia = false;
    E.ancla = null; d.classList.add('tc-editando'); d.classList.remove('tc-ancla'); d.removeAttribute('title');
    $('tc-aterriza').textContent = '';
    var primero = null;
    p.trozos.forEach(function (t) {
      if (!t.editable) return;
      var s = d.querySelector('[data-tc-trozo="' + t.i + '"]'); if (!s) return;
      s.textContent = ''; rellena(s, valorDe(t), '');                        // sin resaltado de búsqueda mientras se escribe
      s.setAttribute('contenteditable', 'true'); s.setAttribute('spellcheck', 'true'); s.setAttribute('role', 'textbox'); s.setAttribute('aria-label', T('Texto del contrato'));
      if (!primero) primero = s;
    });
    var barra = el('div', 'tc-par-acc');
    if (p.sens) {
      var w = el('div', 'tc-aviso-sens'); w.setAttribute('role', 'status');
      w.appendChild(el('span', null, T('Esta parte es sensible (%m). Puedes cambiarla: la decisión es tuya. Consulta a tu abogado si tienes dudas. El cambio quedará registrado con tu nombre y la fecha.', { m: motivoSensible(p) })));
      w.appendChild(el('span', 'tc-peq', T('Al guardar tendrás que confirmar el aviso. Queda registrado quién, cuándo y el texto de antes y después.')));
      barra.appendChild(w);
    }
    var av = el('div', 'tc-trozo-av tc-mal'); av.setAttribute('data-tc-par-av', '1'); av.setAttribute('role', 'alert'); av.hidden = true; barra.appendChild(av);
    var fila = el('div', 'tc-barra-fila');
    fila.appendChild(boton(T('Listo'), { 'data-tc-par-listo': '1' }, 'tc-btn'));
    fila.appendChild(boton(T('Deshacer'), { 'data-tc-par-deshacer': '1' }));
    if (E.cxOk) fila.appendChild(boton(T('Insertar campo'), { 'data-tc-cx-menu': '1', 'aria-haspopup': 'true', 'aria-expanded': 'false' }));
    barra.appendChild(fila);
    if (E.cxOk) barra.appendChild(menuCx());
    d.appendChild(barra);
    var foco = clicI !== null ? d.querySelector('[data-tc-trozo="' + clicI + '"]') : null;
    if (foco) { foco.focus(); ponCaret(foco, ev); } else if (primero) primero.focus();
  }
  /* ── insertar un campo propio de la empresa (E8) ──────────────────────────────────────────────────────────────────────────────── */
  /* El menú ofrece los campos del catálogo NO archivados (un archivado ya no admite valores nuevos: la base rechazaría el texto). Cada uno entra como una pastilla igual que las demás. */
  function menuCx() {
    var m = el('div', 'tc-menu-cx'); m.hidden = true; m.setAttribute('role', 'menu'); m.setAttribute('aria-label', T('Campos propios de la empresa'));
    var vivos = (E.cx || []).filter(function (c) { return !c.archivado; });
    if (!vivos.length) {
      m.appendChild(el('p', 'tc-peq', T('Esta empresa todavía no tiene campos propios. Créalos en la pestaña «Campos».')));
      m.appendChild(boton(T('Ir a Campos'), { 'data-tc-ir-tab': 'campos' }));
      return m;
    }
    vivos.forEach(function (c) {
      var b = boton('', { 'data-tc-cx': c.clave, role: 'menuitem' }, 'tc-btn-suave tc-cx-item');
      b.appendChild(el('span', 'tc-cx-nom', window.LW_CX.etiqueta(c, window.LW_IDIOMA === 'en' ? 'en' : 'es')));
      b.appendChild(el('code', 'tc-cx-clave', '{{' + c.clave + '}}'));
      m.appendChild(b);
    });
    return m;
  }
  function cierraMenuCx() {
    [].forEach.call($('tc-editor').querySelectorAll('.tc-menu-cx'), function (m) { m.hidden = true; });
    [].forEach.call($('tc-editor').querySelectorAll('[data-tc-cx-menu]'), function (b) { b.setAttribute('aria-expanded', 'false'); });
  }
  function alternaMenuCx() {
    var barra = $('tc-editor').querySelector('.tc-par-acc'); if (!barra) return;
    var m = barra.querySelector('.tc-menu-cx'), b = barra.querySelector('[data-tc-cx-menu]'); if (!m) return;
    var abrir = m.hidden; cierraMenuCx();
    if (abrir) { m.hidden = false; if (b) b.setAttribute('aria-expanded', 'true'); var primero = m.querySelector('button'); if (primero) primero.focus(); }
  }
  function insertaCampo(k) {
    if (!E.edicion || !/^cx_[a-z0-9_]{1,40}$/.test(k)) return;
    var d = nodoPar(E.edicion); if (!d) return;
    var r = E.rangoCx, span = null;
    if (r) {
      var host = r.startContainer.nodeType === 1 ? r.startContainer : r.startContainer.parentElement;
      span = host && host.closest ? host.closest('[data-tc-trozo][contenteditable="true"]') : null;
      if (span && !d.contains(span)) span = null;
    }
    if (!span) { span = d.querySelector('[data-tc-trozo][contenteditable="true"]'); r = null; }
    if (!span) return;
    span.focus();
    var sel = window.getSelection(), rg = document.createRange();
    if (r && span.contains(r.startContainer) && span.contains(r.endContainer)) { rg.setStart(r.startContainer, r.startOffset); rg.setEnd(r.endContainer, r.endOffset); }
    else { rg.selectNodeContents(span); rg.collapse(false); }
    var h = rg.startContainer.nodeType === 1 ? rg.startContainer : rg.startContainer.parentElement, pl = h && h.closest ? h.closest('[data-tc-marca]') : null;
    if (pl) { rg.setStartAfter(pl); rg.collapse(true); }                  // un cursor dentro de una pastilla se pone detrás: dentro no se escribe
    rg.deleteContents();
    var pastillaNueva = pastilla(k, ''), blanco = nodoTexto('\u00a0');          // espacio duro detrás: el texto vuelve a tener dónde seguir; la base lo cuenta como espacio
    rg.insertNode(blanco); rg.insertNode(pastillaNueva);
    rg.setStartAfter(blanco); rg.collapse(true);
    sel.removeAllRanges(); sel.addRange(rg);
    E.rangoCx = rg.cloneRange();
    cierraMenuCx();
    alEscribir({ target: span });
  }

  /* Anota lo escrito en el párrafo abierto. false = hay un aviso y el párrafo sigue abierto (no se guarda nada a medias). */
  function commitEdicion() {
    if (!E.edicion) return true;
    var key = E.edicion, p = parPorKey(key), d = nodoPar(key);
    if (!p || !d) { E.edicion = null; E.edicionSucia = false; return true; }
    var r = leeEdicion(p, d);
    if (r.avisos.length) { muestraAvisoPar(d, r.avisos); return false; }
    Object.keys(r.nuevos).forEach(function (i) { if (r.nuevos[i] === E.trozos[i].texto) delete E.cambios[i]; else E.cambios[i] = r.nuevos[i]; });
    E.edicion = null; E.edicionSucia = false;
    pintaDocumento(false);
    var n = nodoPar(key); if (n) n.focus({ preventScroll: true });
    return true;
  }
  function deshacerPar() {
    if (!E.edicion) return;
    var key = E.edicion; E.edicion = null; E.edicionSucia = false;
    pintaDocumento(false);
    var n = nodoPar(key); if (n) n.focus({ preventScroll: true });
  }
  function alEscribir(ev) {
    if (!E.edicion) return;
    var d = nodoPar(E.edicion), p = parPorKey(E.edicion); if (!d || !p || !d.contains(ev.target)) return;
    E.edicionSucia = true;
    muestraAvisoPar(d, leeEdicion(p, d).avisos);
    resumen();
  }
  function alPegar(ev) {
    var s = ev.target.closest && ev.target.closest('[data-tc-trozo][contenteditable="true"]'); if (!s) return;
    ev.preventDefault();
    var cb = ev.clipboardData || window.clipboardData, txt = cb ? String(cb.getData('text/plain') || cb.getData('Text') || '') : '';
    txt = txt.replace(/[\r\n]+/g, ' ');
    if (!txt) return;
    var ok = false; try { ok = document.execCommand('insertText', false, txt); } catch (_) { ok = false; }
    if (!ok) {
      var sel = window.getSelection(); if (!sel.rangeCount) return;
      var r = sel.getRangeAt(0); if (!s.contains(r.commonAncestorContainer)) return;
      r.deleteContents(); var n = nodoTexto(txt); r.insertNode(n); r.setStartAfter(n); r.setEndAfter(n); sel.removeAllRanges(); sel.addRange(r);
    }
    alEscribir(ev);
  }
  function alAntesDeEscribir(ev) {                                          // un párrafo es una línea: ni Intro, ni formato, ni arrastrar
    var t = ev.inputType || '';
    if (/^(insertParagraph|insertLineBreak|insertFromDrop|insertFromYank|insertOrderedList|insertUnorderedList|insertHorizontalRule|insertFromPaste)$/.test(t) || /^format/.test(t)) ev.preventDefault();
  }

  function hayAvisosLocales() {
    return Object.keys(E.cambios).some(function (k) { return TC.avisosTrozo(E.cambios[k], E.trozos[k].texto).length > 0; });
  }
  function resumen() {
    var n = Object.keys(E.cambios).length, algo = n > 0 || E.edicionSucia;
    $('tc-cambios').textContent = n ? T('%n trozos cambiados sin guardar', { n: n }) : (E.edicionSucia ? T('Estás escribiendo: pulsa Listo para anotar el cambio') : T('Sin cambios todavía'));
    $('tc-deshacer').disabled = !algo;
    var mal = hayAvisosLocales();
    $('tc-simular').disabled = !algo;
    $('tc-guardar').disabled = !algo || mal || !!(E.ed && E.ed.solo_global);
    if (mal) nota('tc-ed-estado', T('Corrige los avisos en rojo antes de guardar.'), 'mal'); else if (!E.rechazo) nota('tc-ed-estado', '');
  }
  function deshaz() {
    preguntaPerder().then(function (ok) { if (ok) { E.cambios = {}; E.edicion = null; E.edicionSucia = false; E.rechazo = false; pintaDocumento(false); $('tc-previa-caja').hidden = true; nota('tc-ed-estado', ''); } });
  }

  /* ── lo que contesta la base, en llano ────────────────────────────────────────────────────────────────────────────────────────── */
  var FRASES = {
    sesion: 'Tu sesión ha caducado. Vuelve a entrar; lo que has escrito sigue en pantalla.',
    solo_global: 'Este texto no lo puede cambiar una empresa sola: lo cambia el administrador global con su abogado.',
    sensibles_confirma: 'Has cambiado una parte sensible y falta confirmar el aviso. Pulsa Guardar otra vez y confírmalo.',
    marcador_forma: 'Un campo está mal escrito. Los campos se escriben entre dobles llaves, en minúsculas y sin espacios.',
    llave: 'Hay una llave suelta o un campo sin cerrar. Cada campo se escribe {{asi}}.',
    esqueleto: 'El texto cambia la estructura del documento y no solo las palabras. Deshaz lo último que has cambiado.',
    motivo: 'Falta el motivo del cambio: escríbelo abajo (mínimo tres letras).',
    permiso: 'Tu usuario no puede guardar textos de contrato: lo hace la administración de la empresa.',
    activar_super: 'Activar un texto lo hace el super administrador de la empresa.',
    caracter: 'Hay un carácter invisible o de control que no se admite. Borra esa parte y vuelve a escribirla.',
    grande: 'El texto es demasiado grande para guardarlo.',
    no_activable: 'La base dice que este texto no se podría activar tal cual.'
  };
  /* Pinta, dentro de `caja`, la frase en llano de un mensaje de la base y debajo el mensaje tal cual (textContent: repite un trozo del texto recibido). */
  function pintaRechazo(caja, mensaje, clase) {
    var c = TC.clasificaError(mensaje), p = el('p', clase || 'tc-rev tc-rev-mal'), frase;
    if (c.tipo === 'marcador_desconocido') frase = T('Has escrito un campo que no existe («%c»). Quítalo: solo valen los campos que ya salen en el texto.', { c: TC.marcadorDeError(mensaje) || '' });
    else if (FRASES[c.tipo]) frase = T(FRASES[c.tipo]);
    else frase = T('La base no ha aceptado el texto.');
    p.appendChild(el('span', null, frase));
    if (c.tipo === 'sensibles_confirma') {
      var vistas = {}, lista = el('span', 'tc-rev-enlaces');
      Object.keys(E.cambios).forEach(function (i) {
        var t = E.trozos[i]; if (!t || !t.bloqueado || vistas[t.sec]) return;
        vistas[t.sec] = true;
        lista.appendChild(boton('«' + tituloSec(t.sec) + '»', { 'data-tc-ir': String(t.sec) }));
      });
      if (lista.firstChild) { p.appendChild(el('span', 'tc-peq', ' ' + T('Cambiaste partes sensibles en:') + ' ')); p.appendChild(lista); }
    }
    p.appendChild(el('span', 'tc-peq tc-detalle', T('Mensaje de la base: ') + c.detalle));
    caja.appendChild(p);
  }

  /* ── simular: la base dice qué haría; aquí solo se pinta ───────────────────────────────────────────────────────────────────── */
  /* El HTML de un bloque que devuelve la base, como texto corrido (se pinta siempre con textContent). */
  function soloTexto(h) { return TC.ws(TC.decodifica(String(h == null ? '' : h).replace(/<[^>]*>/g, ' '))).slice(0, 400); }
  function cuerpoNuevo() { return TC.construye(E.doc, E.trozos, E.cambios); }
  function simula() {
    if (!commitEdicion() || !hayCambios()) return;
    var nuevo = cuerpoNuevo();
    E.previo = nuevo;
    $('tc-previa-caja').hidden = false;
    $('tc-revision').textContent = ''; $('tc-revision').appendChild(el('p', 'tc-vacio', T('Preguntando a la base qué haría con este texto…')));
    pintaPrevia(E.langPrevia || (E.lang === 'general' ? null : E.lang) || 'es');
    rpc('plantilla_contrato_revisa', { p_empresa: E.empresa, p_slug: E.slug, p_cuerpo: nuevo, p_variante: E.variante }).then(function (r) {
      var caja = $('tc-revision'); caja.textContent = '';
      function linea(tono, txt) { caja.appendChild(el('p', 'tc-rev tc-rev-' + tono, txt)); }
      if (r.error) { pintaRechazo(caja, msg(r.error)); return; }
      var d = r.data || {};
      if (!d.ok) {
        linea('mal', T('La base NO guardaría este texto:'));
        (d.errores || []).forEach(function (e) { pintaRechazo(caja, e); });
        return;
      }
      linea('ok', T('La base lo guardaría como borrador.'));
      if (d.sensibles && d.bloques_tocados && d.bloques_tocados.length) {
        linea('aviso', T('Este texto cambia partes sensibles. Al guardar tendrás que confirmar el aviso y quedará registrado:'));
        d.bloques_tocados.forEach(function (b) {
          var w = el('div', 'tc-rev tc-rev-aviso');
          w.appendChild(el('span', 'tc-fuerte', b.motivo || T('Parte sensible')));
          w.appendChild(el('span', 'tc-peq tc-detalle', T('Antes: ') + soloTexto(b.antes)));
          w.appendChild(el('span', 'tc-peq tc-detalle', T('Después: ') + soloTexto(b.despues)));
          caja.appendChild(w);
        });
      }
      if (d.activable) linea('ok', T('Y se podría activar.'));
      else linea('aviso', T('Pero no se podría activar tal cual: ') + (d.bloqueo || T('sin motivo')));
    });
  }
  function pintaPrevia(idioma) {
    E.langPrevia = idioma;
    var fr = $('tc-previa-frame');
    var base = ''; try { base = new URL(E.sb.supabaseUrl).origin; } catch (_) { /* MUDO A PROPOSITO: sin la URL de la base la vista previa sale sin las fotos del bucket; el documento se ve igual */ }
    fr.srcdoc = TC.docPrevio(E.previo || E.doc, idioma, location.origin, base, E.cxEj);
    [].forEach.call(document.querySelectorAll('[data-tc-previa-idioma]'), function (b) { b.setAttribute('aria-pressed', b.getAttribute('data-tc-previa-idioma') === idioma ? 'true' : 'false'); });
  }

  /* ── guardar ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────── */
  function guarda() {
    if (!commitEdicion()) { nota('tc-ed-estado', T('Corrige el aviso en rojo del texto que estás editando antes de guardar.'), 'mal'); return; }
    var motivo = $('tc-motivo').value.trim();
    if (!hayCambios()) return;
    if (hayAvisosLocales()) { nota('tc-ed-estado', T('Corrige los avisos en rojo antes de guardar.'), 'mal'); return; }
    if (motivo.length < 3) { nota('tc-ed-estado', T('Escribe el motivo del cambio (mínimo tres letras): queda en el historial.'), 'mal'); $('tc-motivo').focus(); return; }
    var sens = tocaSensibles();
    if (sens.length) { confirmaSensibles(sens).then(function (ok) { if (ok) envia(true); }); return; }
    envia(false);
    function envia(confirma) {
    var b = $('tc-guardar'); b.disabled = true; E.rechazo = false; nota('tc-ed-estado', T('Guardando…'));
    rpc('plantilla_contrato_guarda_borrador', { p_empresa: E.empresa, p_slug: E.slug, p_cuerpo: cuerpoNuevo(), p_motivo: motivo, p_variante: E.variante, p_confirma_sensibles: confirma }).then(function (r) {
      if (r.error) {
        var caja = $('tc-ed-estado'); caja.hidden = false; caja.className = 'tc-nota tc-nota-mal'; caja.textContent = '';
        caja.appendChild(el('p', null, T('La base no lo ha guardado. Tus cambios siguen aquí, no se ha perdido nada.')));
        pintaRechazo(caja, msg(r.error), 'tc-rev');
        E.rechazo = true; b.disabled = false; return;
      }
      toast(T('Borrador guardado.'));
      E.cambios = {}; E.previo = null; var slug = E.slug;
      cargaLista().then(function () { E.ed = null; reabre(slug); });
    });
    }
  }
  /* Las partes sensibles que tocan los cambios anotados (la base lo vuelve a calcular y pide la confirmación igualmente: esto es solo el aviso a tiempo). */
  function tocaSensibles() {
    var vistos = {}, out = [];
    Object.keys(E.cambios).forEach(function (i) {
      var t = E.trozos[i]; if (!t || !t.bloqueado) return;
      var k = t.sec + '|' + (t.motivo || ''); if (vistos[k]) return; vistos[k] = true;
      out.push({ sec: t.sec, motivo: t.motivo || T('parte sensible') });
    });
    return out;
  }
  function confirmaSensibles(lista) {
    if (typeof window.lwConfirmar !== 'function') return Promise.resolve(true);
    var cuerpo = '<p>' + esc(T('Estás cambiando partes sensibles del contrato. La decisión es tuya: consulta a tu abogado si tienes dudas. El cambio queda registrado con tu nombre, la fecha y el texto de antes y después.')) + '</p><ul>'
      + lista.map(function (x) { return '<li>' + esc(tituloSec(x.sec) + ' — ' + x.motivo) + '</li>'; }).join('') + '</ul>';
    return window.lwConfirmar({ titulo: T('Vas a cambiar partes sensibles'), cuerpo: cuerpo, confirmar: T('Entiendo el aviso y guardo'), tono: 'peligro' });
  }
  function reabre(slug) { /* vuelve a pedir el texto: ahora la base parte de TU borrador */
    var guardado = E.slug; E.slug = null;
    abreEditor(slug || guardado, E.variante);
  }

  /* ── activar ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────── */
  function preparaActivar() {
    var caja = $('tc-activar'), d = E.ed; caja.hidden = true;
    var puede = !!d.puede_activar && d.estado === 'borrador' && d.origen === 'empresa';
    if (!puede) {
      if (d.puede_activar && d.origen === 'semilla') nota('tc-act-nota', T('La copia inicial del estudio no se activa: cambia lo que haga falta, guarda tu borrador y actívalo.'), 'aviso');
      else nota('tc-act-nota', '');
      caja.hidden = !(d.puede_activar && d.origen === 'semilla'); $('tc-act-form').hidden = true; return;
    }
    $('tc-act-form').hidden = false; caja.hidden = false;
    var v = (E.porSlug[E.slug] || []).filter(function (x) { return x.id === d.version_id; })[0];
    $('tc-act-texto').textContent = TC.TEXTO_CONFIRMACION;
    $('tc-act-fecha').textContent = fFecha(new Date());
    $('tc-act-nombre').value = ''; $('tc-act-ok').checked = false;
    if (v && !v.activable) { nota('tc-act-nota', T('Este borrador no se puede activar: ') + (v.bloqueo_motivo || ''), 'mal'); $('tc-act-form').hidden = true; return; }
    nota('tc-act-nota', '');
    actualizaActivar();
  }
  function actualizaActivar() {
    $('tc-act-boton').disabled = !($('tc-act-ok').checked && $('tc-act-nombre').value.trim().length >= 3) || hayCambios();
  }
  function activa() {
    var d = E.ed, nombre = $('tc-act-nombre').value.trim();
    if (!d || hayCambios()) return;
    $('tc-act-boton').disabled = true; nota('tc-act-nota', T('Activando…'));
    rpc('plantilla_contrato_activa', { p_version: d.version_id, p_nombre: nombre, p_confirma: $('tc-act-ok').checked }).then(function (r) {
      if (r.error) { nota('tc-act-nota', T('La base no la ha activado: ') + msg(r.error), 'mal'); actualizaActivar(); return; }
      toast(T('Versión activada.'));
      var slug = E.slug; cargaLista().then(function () { reabre(slug); abreHistorial(slug, E.variante); });
    });
  }

  /* ── historial y diferencias ──────────────────────────────────────────────────────────────────────────────────────────────── */
  /* El historial de UNA revisión (los números de versión corren por plantilla, no por revisión: se filtra por revisión o se compararía con otra). */
  function abreHistorial(slug, variante) {
    var vr = variante || 'estandar';
    E.histSlug = slug; E.histVar = vr;
    var vs = (E.porSlug[slug] || []).filter(function (v) { return (v.variante || 'estandar') === vr; }), caja = $('tc-historial-caja');
    var rev = vs.filter(function (v) { return v.variante_nombre; })[0];
    caja.hidden = false; $('tc-hist-titulo').textContent = nombreDe(slug) + (vr !== 'estandar' ? ' · ' + (rev ? rev.variante_nombre : vr) : ''); $('tc-diff').hidden = true;
    $('tc-hist-cuerpo').innerHTML = vs.map(function (v) {
      var estado = v.estado === 'activa' ? pill(T('Activa'), 'ok') : (v.estado === 'retirada' ? pill(T('Retirada'), 'neutro') : pill(v.origen === 'semilla' ? T('Semilla del estudio') : T('Borrador'), 'aviso'));
      var conf = v.estado === 'activa' || v.activado_por
        ? '<div class="tc-peq">' + esc(T('Activada por')) + ' ' + esc(v.activado_por || '—') + ' · ' + esc(fFechaHora(v.activado_en)) + '</div>'
          + (v.confirmacion_nombre ? '<div class="tc-peq">' + esc(T('Confirmó')) + ': ' + esc(v.confirmacion_nombre) + '</div>' : '') : '';
      var ret = v.retirada_por ? '<div class="tc-peq">' + esc(T('Retirada por')) + ' ' + esc(v.retirada_por) + ' · ' + esc(fFechaHora(v.retirada_en)) + '</div>' : '';
      return '<tr><td class="tc-fuerte">v' + esc(v.version) + '</td><td>' + estado + '</td>'
        + '<td><div>' + esc(v.autor) + '</div><div class="tc-peq">' + esc(fFechaHora(v.fecha)) + '</div></td>'
        + '<td>' + esc(v.motivo || '—') + conf + ret + '</td>'
        + '<td><code class="tc-hash" title="SHA-256 ' + esc(v.hash) + '">' + esc(String(v.hash || '').slice(0, 12)) + '</code></td>'
        + '<td class="tc-acc"><button type="button" class="tc-btn tc-btn-suave" data-real="1" data-tc-diff="' + esc(v.id) + '">' + esc(T('Ver cambios')) + '</button></td></tr>';
    }).join('');
    cargaCambiosSensibles(slug, vr);
    caja.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }
  /* Quién cambió qué parte sensible, con el texto literal de antes y después (plantilla_contrato_cambios_sensibles; solo la administración de la empresa). */
  function cargaCambiosSensibles(slug, vr) {
    var l = $('tc-sens-lista'); l.textContent = ''; l.appendChild(el('p', 'tc-vacio', T('Trayendo el registro…')));
    return rpc('plantilla_contrato_cambios_sensibles', { p_empresa: E.empresa, p_slug: slug, p_limite: 50 }).then(function (r) {
      if (E.histSlug !== slug || E.histVar !== vr) return;
      l.textContent = '';
      if (r.error || !r.data || !Array.isArray(r.data.cambios)) { l.appendChild(el('p', 'tc-vacio tc-mal', T('No he podido leer el registro de cambios en partes sensibles: ') + msg(r.error || T('la base no ha devuelto la lista')))); return; }
      var filas = r.data.cambios.filter(function (c) { return (c.variante || 'estandar') === vr; });
      if (!filas.length) { l.appendChild(el('p', 'tc-vacio', T('Nadie ha cambiado partes sensibles de este contrato.'))); return; }
      filas.forEach(function (c) {
        var f = el('div', 'tc-fila'), info = el('div', 'tc-fila-info');
        info.appendChild(el('div', 'tc-fuerte', (c.motivo || T('Parte sensible')) + ' · v' + c.version));
        info.appendChild(el('div', 'tc-peq', fFechaHora(c.fecha) + ' · ' + c.autor + ' · ' + (c.aviso_confirmado ? T('aviso confirmado') : T('sin confirmar'))));
        if (c.motivo_cambio) info.appendChild(el('div', 'tc-peq', T('Motivo del cambio: ') + c.motivo_cambio));
        var det = el('details', 'tc-det'); det.appendChild(el('summary', 'tc-peq', T('Ver el texto de antes y después')));
        det.appendChild(el('div', 'tc-peq', T('Antes')));
        det.appendChild(el('pre', 'tc-json', soloTexto(c.antes)));
        det.appendChild(el('div', 'tc-peq', T('Después')));
        det.appendChild(el('pre', 'tc-json', soloTexto(c.despues)));
        info.appendChild(det); f.appendChild(info); l.appendChild(f);
      });
    });
  }

  function cuerpoDe(id) {
    var c = E.cuerpos[id];
    if (c) return Promise.resolve(c);
    return rpc('plantilla_contrato_cuerpo_version', { p_version: id }).then(function (r) {
      if (r.error || !r.data || typeof r.data.cuerpo_html !== 'string') throw new Error(r.error ? msg(r.error) : T('la base no ha devuelto el texto'));
      E.cuerpos[id] = r.data.cuerpo_html; return r.data.cuerpo_html;
    });
  }
  function verDiff(id) {
    var todas = E.porSlug[E.histSlug] || [], v = todas.filter(function (x) { return x.id === id; })[0]; if (!v) return;
    /* La anterior DE SU REVISIÓN: la de número inmediatamente menor dentro de la misma revisión; la primera de una revisión creada como copia se compara con el texto del que salió. */
    var vr = v.variante || 'estandar';
    var ant = todas.filter(function (x) { return (x.variante || 'estandar') === vr && x.version < v.version; }).sort(function (a, b) { return b.version - a.version; })[0]
      || (v.hereda_de ? todas.filter(function (x) { return x.id === v.hereda_de; })[0] : null);
    var caja = $('tc-diff'); caja.hidden = false;
    caja.innerHTML = '<p class="tc-vacio"></p>'; caja.firstChild.textContent = T('Comparando…');
    if (!ant) { caja.firstChild.textContent = T('Es la primera versión: no hay otra con la que comparar.'); return; }
    Promise.all([cuerpoDe(ant.id), cuerpoDe(v.id)]).then(function (cc) {
      var ops = TC.diff(TC.lineas(cc[0]), TC.lineas(cc[1]));
      var cambios = ops.filter(function (o) { return o.t !== '='; });
      caja.innerHTML = '';
      var h = document.createElement('p'); h.className = 'tc-fuerte';
      h.textContent = T('v%a frente a v%b: %n líneas cambiadas', { a: v.version, b: ant.version, n: cambios.length });
      caja.appendChild(h);
      if (!cambios.length) {
        var igual = document.createElement('p'); igual.className = 'tc-vacio';
        igual.textContent = ant.hash === v.hash ? T('Los dos textos son idénticos (mismo SHA-256).') : T('El texto visible es el mismo: solo cambian notas internas o marcado.');
        caja.appendChild(igual); return;
      }
      /* Solo las líneas que cambian, con una de contexto a cada lado. */
      var mostrar = {}; ops.forEach(function (o, k) { if (o.t !== '=') { mostrar[k] = 1; if (k > 0) mostrar[k - 1] = 1; if (k + 1 < ops.length) mostrar[k + 1] = 1; } });
      var pre = document.createElement('div'); pre.className = 'tc-difflista';
      var saltado = false, cuantas = 0;
      ops.forEach(function (o, k) {
        if (!mostrar[k]) { saltado = true; return; }
        if (saltado) { var s = document.createElement('div'); s.className = 'tc-dsalto'; s.textContent = '…'; pre.appendChild(s); saltado = false; }
        if (++cuantas > 600) return;
        var l = document.createElement('div'); l.className = 'tc-d tc-d' + (o.t === '+' ? 'mas' : (o.t === '-' ? 'menos' : 'igual'));
        l.textContent = (o.t === '=' ? '  ' : o.t + ' ') + o.s; pre.appendChild(l);
      });
      caja.appendChild(pre);
      if (cuantas > 600) { var m = document.createElement('p'); m.className = 'tc-peq'; m.textContent = T('Se enseñan las primeras 600 líneas.'); caja.appendChild(m); }
    }).catch(function (e) {
      caja.innerHTML = '<p class="tc-vacio tc-mal"></p>'; caja.firstChild.textContent = T('No he podido leer una de las dos versiones: ') + msg(e);
    });
  }

  /* El puente con textos-contrato-config.js (las pestañas Revisiones y Campos): lo que necesita de esta pantalla, sin tocar su estado a mano. */
  window.LW_TC = { E: E, rpc: rpc, cargaLista: cargaLista, abreEditor: abreEditor, abreHistorial: abreHistorial, preguntaPerder: preguntaPerder, nombreDe: nombreDe,
                   el: el, boton: boton, pill: pill, fFecha: fFecha, fFechaHora: fFechaHora, msg: msg };

  /* ── puesta en marcha ─────────────────────────────────────────────────────────────────────────────────────────────────────────── */
  function inicia() {
    if (!window.LW_AUTH) { console.error('[textos-contrato] sin guard: no se cablea nada'); return; }
    window.LW_AUTH.then(arranca);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', inicia); else inicia();
})();
