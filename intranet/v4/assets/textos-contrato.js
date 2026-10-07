/* textos-contrato.js — la pantalla «Textos de contrato» (/intranet/v4/textos-contrato/), 8-oct-2026.
   Encargo «plantillas de contrato por empresa», S7 (encargos/20261007_lawang_plantillas_por_empresa.md). La parte pura (trocear el documento, bloques fijos, construir el
   texto nuevo, comparar, simular) vive en textos-contrato-nucleo.js; aquí solo hay pantalla y llamadas.

   FRONTERA FRONT/BACK. Esta pantalla NO valida nada y NO escribe en ninguna tabla: pregunta y pide, siempre por RPC (las siete que la migración
   20261009010000 abre a `authenticated` y a nadie más):
     plantilla_contrato_versiones_lista   la lista y el historial (sin cuerpo)          plantilla_contrato_edicion   el texto a editar, sin notas, con sus bloques fijos y permisos
     plantilla_contrato_cuerpo_version    el texto de una versión (historial y diff)    plantilla_contrato_revisa    ensayo sin guardar: lo que diría guardar y si sería activable
     plantilla_contrato_guarda_borrador   guardar (motivo obligatorio)                  plantilla_contrato_activa    activar (solo el super administrador de esa empresa)
     plantilla_contrato_descarta_borrador descartar un borrador (pasa a «retirada»: nada se borra)
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
  var PAGINA = 25;                                 // bloques de texto por página del editor
  var IDIOMAS = [['es', 'Español'], ['en', 'English'], ['id', 'Bahasa']];

  /* El estado de la pantalla, en un solo sitio. */
  var E = {
    sb: null, ficha: null, empresas: [], empresa: null, nombres: {}, nombresOk: true,
    lista: [], porSlug: {}, slug: null, orden: {},
    ed: null,                // lo que devolvió plantilla_contrato_edicion
    doc: '', trozos: [], editables: 0, bloqueados: 0, sinLocalizar: 0,
    cambios: {},             // { i: textoNuevo } — solo lo que la persona ha tocado
    lang: 'es', filtro: '', pagina: 0,
    cuerpos: {}              // caché de cuerpos por version_id (el hash es el etag)
  };

  /* ── pequeños ayudantes ───────────────────────────────────────────────────────────────────────────────────────────────────────── */
  function fFecha(x) { try { return new Date(x).toLocaleDateString(window.LW_IDIOMA === 'en' ? 'en-GB' : 'es-ES', { day: '2-digit', month: 'short', year: 'numeric' }); } catch (_) { return String(x || ''); } }
  function fFechaHora(x) { try { return new Date(x).toLocaleString(window.LW_IDIOMA === 'en' ? 'en-GB' : 'es-ES', { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' }); } catch (_) { return String(x || ''); } }
  function msg(e) { return (e && e.message) ? e.message : String(e || ''); }
  function pill(texto, tono) { return '<span class="tc-pill tc-' + (tono || 'neutro') + '">' + esc(texto) + '</span>'; }
  function nombreDe(slug) { return E.nombres[slug] || slug; }
  function hayCambios() { return Object.keys(E.cambios).length > 0; }
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
      }, function () { E.nombresOk = false; }).then(cargaLista);
    });
  }

  function cableaEventos() {
    $('tc-empresa').addEventListener('change', function () {
      var nueva = this.value, sel = this;
      preguntaPerder().then(function (ok) {
        if (!ok) { sel.value = E.empresa; return; }
        E.empresa = nueva; cierraEditor(); cargaLista();
      });
    });
    $('tc-lista').addEventListener('click', function (ev) {
      var b = ev.target.closest('[data-tc-editar],[data-tc-historial],[data-tc-descartar]'); if (!b) return;
      ev.stopPropagation();
      if (b.hasAttribute('data-tc-editar')) abreEditor(b.getAttribute('data-tc-editar'));
      else if (b.hasAttribute('data-tc-historial')) abreHistorial(b.getAttribute('data-tc-historial'));
      else descarta(b.getAttribute('data-tc-descartar'));
    });
    $('tc-hist-cuerpo').addEventListener('click', function (ev) {
      var b = ev.target.closest('[data-tc-diff]'); if (!b) return;
      ev.stopPropagation(); verDiff(b.getAttribute('data-tc-diff'));
    });
    $('tc-editor').addEventListener('click', function (ev) {
      var b = ev.target.closest('[data-tc-idioma],[data-tc-pag],#tc-simular,#tc-guardar,#tc-deshacer,#tc-cerrar,[data-tc-previa-idioma]'); if (!b) return;
      ev.stopPropagation();
      if (b.hasAttribute('data-tc-idioma')) { E.lang = b.getAttribute('data-tc-idioma'); E.pagina = 0; pintaTrozos(); }
      else if (b.hasAttribute('data-tc-pag')) { E.pagina += Number(b.getAttribute('data-tc-pag')); pintaTrozos(); }
      else if (b.hasAttribute('data-tc-previa-idioma')) pintaPrevia(b.getAttribute('data-tc-previa-idioma'));
      else if (b.id === 'tc-simular') simula();
      else if (b.id === 'tc-guardar') guarda();
      else if (b.id === 'tc-deshacer') deshaz();
      else if (b.id === 'tc-cerrar') preguntaPerder().then(function (ok) { if (ok) cierraEditor(); });
    });
    $('tc-trozos').addEventListener('input', function (ev) {
      var ta = ev.target.closest('[data-tc-trozo]'); if (ta) tocaTrozo(ta);
    });
    $('tc-buscar').addEventListener('input', function () { E.filtro = this.value.trim().toLowerCase(); E.pagina = 0; pintaTrozos(); });
    $('tc-act-nombre').addEventListener('input', actualizaActivar);
    $('tc-act-ok').addEventListener('change', actualizaActivar);
    $('tc-act-boton').addEventListener('click', function (ev) { ev.stopPropagation(); activa(); });
    window.addEventListener('beforeunload', function (ev) { if (hayCambios()) { ev.preventDefault(); ev.returnValue = ''; } });
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
    var vs = E.porSlug[slug];
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
        if (E.slug === v.slug) { E.cambios = {}; cierraEditor(); }
        cargaLista();
      });
    });
  }

  /* ── el editor ────────────────────────────────────────────────────────────────────────────────────────────────────────────────── */
  function abreEditor(slug) {
    preguntaPerder().then(function (ok) {
      if (!ok) return;
      E.cambios = {};
      E.slug = slug;
      var cab = $('tc-editor'); cab.hidden = false;
      $('tc-ed-titulo').textContent = nombreDe(slug);
      $('tc-trozos').innerHTML = '<p class="tc-vacio">' + esc(T('Trayendo el texto…')) + '</p>';
      $('tc-ed-barra').hidden = true; $('tc-previa-caja').hidden = true; $('tc-activar').hidden = true; nota('tc-ed-aviso', '');
      cab.scrollIntoView({ behavior: 'smooth', block: 'start' });
      rpc('plantilla_contrato_edicion', { p_empresa: E.empresa, p_slug: slug }).then(function (r) {
        if (r.error || !r.data) {
          $('tc-trozos').innerHTML = '<p class="tc-vacio tc-mal"></p>';
          $('tc-trozos').firstChild.textContent = T('No he podido leer el texto: ') + msg(r.error);
          return;
        }
        var d = r.data; E.ed = d; E.doc = d.cuerpo_html || '';
        var tr = TC.trocea(E.doc); E.trozos = tr.trozos;
        E.editables = E.trozos.filter(function (t) { return t.editable; }).length;
        var todoBloqueado = !!d.solo_global;
        var s = TC.situaBloquesFijos(E.doc, d.bloques_fijos || []);
        E.sinLocalizar = s.sinLocalizar;
        E.bloqueados = TC.marcaBloqueados(E.trozos, s.spans, todoBloqueado);
        var langs = {}; E.trozos.forEach(function (t) { if (t.editable) langs[t.lang || 'general'] = 1; });
        E.lang = langs.es ? 'es' : (langs.en ? 'en' : (langs.id ? 'id' : 'general'));
        E.langs = Object.keys(langs); E.filtro = ''; E.pagina = 0; $('tc-buscar').value = ''; $('tc-motivo').value = '';
        pintaCabecera(); pintaTrozos(); preparaActivar();
        $('tc-ed-barra').hidden = false;
        nota('tc-ed-estado', '');
        cargaListaSuave();                       // la lista marca la fila abierta
      });
    });
  }
  function cargaListaSuave() { /* repinta la marca de fila sin volver a pedir nada */
    var slugs = Object.keys(E.porSlug); if (!slugs.length) return;
    var filas = $('tc-lista').querySelectorAll('tr'); [].forEach.call(filas, function (f) { f.classList.remove('tc-fila-sel'); });
    var b = $('tc-lista').querySelector('[data-tc-editar="' + E.slug + '"]'); if (b) b.closest('tr').classList.add('tc-fila-sel');
  }

  function cierraEditor() {
    E.cambios = {}; E.slug = null; E.ed = null; E.trozos = []; E.doc = '';
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
    else if (E.bloqueados) avisos.push(T('Los bloques con candado (foro y ley aplicable, tenencia, escrow e impuestos, prórroga, defectos, datos, partes y firmas, cláusulas negociadas) los cambia el administrador global con su abogado. Aquí salen en solo lectura.'));
    if (E.sinLocalizar > 0) avisos.push(T('No he podido marcar en pantalla %n bloques con candado; la base los protege igualmente al guardar.', { n: E.sinLocalizar }));
    if (d.nunca_activable) avisos.push(T('Esta plantilla no se puede activar nunca para esta empresa: ') + d.nunca_activable);
    if (d.bloqueo && !d.nunca_activable) avisos.push(T('Tal como está, este texto no se podría activar: ') + d.bloqueo);
    if (d.notas_quitadas > 0) avisos.push(T('Se han quitado %n bytes de notas internas del autor del estudio: no se imprimen en el contrato y no se pueden guardar en una versión de empresa.', { n: d.notas_quitadas }));
    var n = $('tc-ed-aviso'); n.hidden = !avisos.length; n.innerHTML = avisos.map(function (a) { return '<p></p>'; }).join('');
    [].forEach.call(n.querySelectorAll('p'), function (p, i) { p.textContent = avisos[i]; });   // textContent: parte de esto viene de la base
    $('tc-ed-idiomas').innerHTML = (E.langs || []).sort().map(function (l) {
      var nombre = l === 'general' ? T('General') : (IDIOMAS.filter(function (x) { return x[0] === l; })[0] || [l, l])[1];
      return '<button type="button" class="tc-tab" data-real="1" data-tc-idioma="' + esc(l) + '" aria-pressed="' + (l === E.lang ? 'true' : 'false') + '">' + esc(nombre) + '</button>';
    }).join('');
    var solo = !!d.solo_global;
    $('tc-guardar').disabled = solo; $('tc-motivo').disabled = solo;
    $('tc-guardar').title = solo ? T('Este texto solo lo cambia el administrador global') : '';
  }

  /* Los trozos de la página actual, agrupados por bloque (un párrafo, una celda, un título). */
  function visibles() {
    var lang = E.lang === 'general' ? null : E.lang;
    return E.trozos.filter(function (t) {
      if (!t.editable) return false;
      if ((t.lang || null) !== lang) return false;
      if (E.filtro && (E.cambios[t.i] !== undefined ? E.cambios[t.i] : t.texto).toLowerCase().indexOf(E.filtro) === -1) return false;
      return true;
    });
  }
  function altoFila(txt) { return Math.max(1, Math.min(14, Math.ceil(txt.length / 80) + (txt.match(/\n/g) || []).length)); }
  function pintaTrozos() {
    var todos = visibles(), grupos = [], ult = null;
    todos.forEach(function (t) { if (!ult || ult.id !== t.bloque) { ult = { id: t.bloque, trozos: [] }; grupos.push(ult); } ult.trozos.push(t); });
    var paginas = Math.max(1, Math.ceil(grupos.length / PAGINA));
    E.pagina = Math.min(Math.max(0, E.pagina), paginas - 1);
    var pag = grupos.slice(E.pagina * PAGINA, (E.pagina + 1) * PAGINA);
    var caja = $('tc-trozos');
    if (!pag.length) {
      caja.innerHTML = '<p class="tc-vacio"></p>';
      caja.firstChild.textContent = E.filtro ? T('Ningún trozo contiene esa búsqueda en este idioma.') : T('No hay texto editable en este idioma.');
    } else {
      caja.innerHTML = pag.map(function (g) {
        return '<div class="tc-bloque">' + g.trozos.map(function (t) {
          var v = E.cambios[t.i] !== undefined ? E.cambios[t.i] : t.texto;
          var cand = t.bloqueado;
          return '<div class="tc-trozo' + (cand ? ' tc-cand' : '') + (E.cambios[t.i] !== undefined ? ' tc-tocado' : '') + '" data-tc-fila="' + t.i + '">'
            + (cand ? '<span class="tc-lock" title="' + esc(T('Bloque fijo: lo cambia el administrador global con su abogado')) + '">🔒</span>' : '')
            + '<textarea data-tc-trozo="' + t.i + '" rows="' + altoFila(v) + '" spellcheck="true"' + (cand ? ' readonly aria-readonly="true"' : '')
            + ' aria-label="' + esc(T('Texto del contrato')) + '">' + esc(v) + '</textarea><div class="tc-trozo-av" data-tc-av="' + t.i + '"></div></div>';
        }).join('') + '</div>';
      }).join('');
    }
    $('tc-pag-txt').textContent = T('Página %a de %b', { a: E.pagina + 1, b: paginas }) + ' · ' + T('%n trozos', { n: todos.length });
    document.querySelector('[data-tc-pag="-1"]').disabled = E.pagina <= 0;
    document.querySelector('[data-tc-pag="1"]').disabled = E.pagina >= paginas - 1;
    [].forEach.call($('tc-ed-idiomas').querySelectorAll('[data-tc-idioma]'), function (b) { b.setAttribute('aria-pressed', b.getAttribute('data-tc-idioma') === E.lang ? 'true' : 'false'); });
    [].forEach.call(caja.querySelectorAll('[data-tc-trozo]'), function (ta) { avisaTrozo(Number(ta.getAttribute('data-tc-trozo')), ta.value); });
    resumen();
  }

  function trozoPorI(i) { return E.trozos[i]; }
  function avisaTrozo(i, valor) {
    var t = trozoPorI(i), av = TC.avisosTrozo(valor, t.texto), nodo = document.querySelector('[data-tc-av="' + i + '"]');
    if (nodo) { nodo.textContent = av.length ? T(av[0]) : ''; nodo.className = 'tc-trozo-av' + (av.length ? ' tc-mal' : ''); }
    return av.length === 0;
  }
  function tocaTrozo(ta) {
    var i = Number(ta.getAttribute('data-tc-trozo')), t = trozoPorI(i);
    if (!t || t.bloqueado) return;
    if (ta.value === t.texto) delete E.cambios[i]; else E.cambios[i] = ta.value;
    ta.rows = altoFila(ta.value);
    avisaTrozo(i, ta.value);
    ta.closest('.tc-trozo').classList.toggle('tc-tocado', E.cambios[i] !== undefined);
    resumen();
  }
  function hayAvisosLocales() {
    return Object.keys(E.cambios).some(function (k) { return TC.avisosTrozo(E.cambios[k], E.trozos[k].texto).length > 0; });
  }
  function resumen() {
    var n = Object.keys(E.cambios).length;
    $('tc-cambios').textContent = n ? T('%n trozos cambiados sin guardar', { n: n }) : T('Sin cambios todavía');
    $('tc-deshacer').disabled = !n;
    var mal = hayAvisosLocales();
    $('tc-simular').disabled = !n;
    $('tc-guardar').disabled = !n || mal || !!(E.ed && E.ed.solo_global);
    if (mal) nota('tc-ed-estado', T('Corrige los avisos en rojo antes de simular o guardar.'), 'mal'); else nota('tc-ed-estado', '');
  }
  function deshaz() {
    preguntaPerder().then(function (ok) { if (ok) { E.cambios = {}; pintaTrozos(); $('tc-previa-caja').hidden = true; } });
  }

  /* ── simular: la base dice qué haría; aquí solo se pinta ───────────────────────────────────────────────────────────────────── */
  function cuerpoNuevo() { return TC.construye(E.doc, E.trozos, E.cambios); }
  function simula() {
    if (!hayCambios() || hayAvisosLocales()) return;
    var nuevo = cuerpoNuevo();
    E.previo = nuevo;
    $('tc-previa-caja').hidden = false;
    $('tc-revision').innerHTML = '<p class="tc-vacio">' + esc(T('Preguntando a la base qué haría con este texto…')) + '</p>';
    pintaPrevia(E.langPrevia || (E.lang === 'general' ? null : E.lang) || 'es');
    rpc('plantilla_contrato_revisa', { p_empresa: E.empresa, p_slug: E.slug, p_cuerpo: nuevo }).then(function (r) {
      var caja = $('tc-revision'); caja.innerHTML = '';
      function linea(tono, txt) { var p = document.createElement('p'); p.className = 'tc-rev tc-rev-' + tono; p.textContent = txt; caja.appendChild(p); }
      if (r.error) { linea('mal', T('La base no ha podido revisar el texto: ') + msg(r.error)); return; }
      var d = r.data || {};
      if (!d.ok) {
        linea('mal', T('La base NO guardaría este texto:'));
        (d.errores || []).forEach(function (e) { linea('mal', '· ' + e); });
        return;
      }
      linea('ok', T('La base lo guardaría como borrador.'));
      if (d.activable) linea('ok', T('Y se podría activar.'));
      else linea('aviso', T('Pero no se podría activar tal cual: ') + (d.bloqueo || T('sin motivo')));
    });
  }
  function pintaPrevia(idioma) {
    E.langPrevia = idioma;
    var fr = $('tc-previa-frame');
    var base = ''; try { base = new URL(E.sb.supabaseUrl).origin; } catch (_) { /* MUDO A PROPOSITO: sin la URL de la base la vista previa sale sin las fotos del bucket; el documento se ve igual */ }
    fr.srcdoc = TC.docPrevio(E.previo || E.doc, idioma, location.origin, base);
    [].forEach.call(document.querySelectorAll('[data-tc-previa-idioma]'), function (b) { b.setAttribute('aria-pressed', b.getAttribute('data-tc-previa-idioma') === idioma ? 'true' : 'false'); });
  }

  /* ── guardar ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────── */
  function guarda() {
    var motivo = $('tc-motivo').value.trim();
    if (!hayCambios()) return;
    if (hayAvisosLocales()) { nota('tc-ed-estado', T('Corrige los avisos en rojo antes de guardar.'), 'mal'); return; }
    if (motivo.length < 3) { nota('tc-ed-estado', T('Escribe el motivo del cambio (mínimo tres letras): queda en el historial.'), 'mal'); $('tc-motivo').focus(); return; }
    var b = $('tc-guardar'); b.disabled = true; nota('tc-ed-estado', T('Guardando…'));
    rpc('plantilla_contrato_guarda_borrador', { p_empresa: E.empresa, p_slug: E.slug, p_cuerpo: cuerpoNuevo(), p_motivo: motivo }).then(function (r) {
      if (r.error) {
        nota('tc-ed-estado', T('La base no lo ha guardado: ') + msg(r.error), 'mal');   // textContent: el mensaje repite un trozo del texto
        b.disabled = false; return;
      }
      toast(T('Borrador guardado.'));
      E.cambios = {}; E.previo = null; var slug = E.slug;
      cargaLista().then(function () { E.ed = null; reabre(slug); });
    });
  }
  function reabre(slug) { /* vuelve a pedir el texto: ahora la base parte de TU borrador */
    var guardado = E.slug; E.slug = null;
    abreEditor(slug || guardado);
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
      var slug = E.slug; cargaLista().then(function () { reabre(slug); abreHistorial(slug); });
    });
  }

  /* ── historial y diferencias ──────────────────────────────────────────────────────────────────────────────────────────────── */
  function abreHistorial(slug) {
    E.histSlug = slug;
    var vs = E.porSlug[slug] || [], caja = $('tc-historial-caja');
    caja.hidden = false; $('tc-hist-titulo').textContent = nombreDe(slug); $('tc-diff').hidden = true;
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
    caja.scrollIntoView({ behavior: 'smooth', block: 'start' });
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
    var vs = E.porSlug[E.histSlug] || [], v = vs.filter(function (x) { return x.id === id; })[0]; if (!v) return;
    /* La anterior: la de número inmediatamente menor (de cualquier estado: el historial no tiene huecos). */
    var ant = vs.filter(function (x) { return x.version === v.version - 1; })[0];
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

  /* ── puesta en marcha ─────────────────────────────────────────────────────────────────────────────────────────────────────────── */
  function inicia() {
    if (!window.LW_AUTH) { console.error('[textos-contrato] sin guard: no se cablea nada'); return; }
    window.LW_AUTH.then(arranca);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', inicia); else inicia();
})();
