/* textos-contrato-config.js — las pestañas REVISIONES y CAMPOS de la pantalla «Textos de contrato» (/intranet/v4/textos-contrato/), 8-oct-2026.
   Encargo «editor de textos de contrato» (encargos/20261008_lawang_editor_textos_contrato.md), E7 (revisiones múltiples) y E8 (campos propios por empresa). El prototipo aprobado
   por el owner es el artifact «Configurador de contratos»; la pestaña «Contrato nuevo» (E9) NO está aquí todavía: su RPC la crea Datos, y el hueco de la pestaña queda oculto.

   FRONTERA FRONT/BACK. Esta pantalla NO valida nada y NO escribe en ninguna tabla: pregunta y pide, siempre por RPC. Las que usa, todas de las migraciones
   20261010000000 (E7) y 20261010010000 (E8), abiertas solo a `authenticated` con la empresa y el rol comprobados DENTRO:
     plantilla_contrato_revisiones_lista    las revisiones de un contrato (estado, contratos que la usan, párrafos distintos de su origen)
     plantilla_contrato_revision_crea       copia una revisión con nombre y motivo     plantilla_contrato_revision_archiva / _restaura / _borra
     plantilla_campo_propio_lista           el catálogo (con su uso)                   plantilla_campo_propio_guarda / _archiva / _borra
     plantilla_campo_propio_valida          lo que respondería la base a unos valores (la vista previa «esto se guarda» sale de AQUÍ: no hay un segundo lector de números en el navegador)
   Mostrar u ocultar un botón es solo reflejo: quién puede archivar, restaurar (solo el super administrador), borrar o tocar un campo lo decide la base, y si dice que no se enseña SU mensaje
   en llano (con textContent: repite un trozo de lo recibido) y debajo el mensaje tal cual.

   La pestaña CONTRATO NUEVO (E9) es un asistente de cuatro pasos (nombre, punto de partida, campos, revisar) que termina en UNA llamada:
     plantilla_contrato_nuevo_crea          crea el contrato propio de la empresa con su esqueleto y un primer borrador editable (la base valida, pone el identificador y limita a 30)
   El contrato nace oculto del generador de contratos (migración 20261010030000): se escribe y se activa aquí, y el estudio abre su uso en el generador.

   Lo de la pantalla de textos (editor, historial, lista) lo abre el puente window.LW_TC que deja textos-contrato.js. ENGANCHE POR IDENTIFICADOR: data-rv-* / data-cx-* / ids, nunca un rótulo. */
(function () {
  'use strict';

  var TC = window.LW_TEXTOS, CX = window.LW_CX, API = window.LW_TC;
  if (!TC || !CX || !API) { console.error('[textos-contrato-config] falta textos-contrato-nucleo.js, cx_campos.js o textos-contrato.js'); return; }
  var T = function (s, h) { return window.lwT ? window.lwT(s, h) : String(s).replace(/%(\w+)/g, function (m, k) { return h && k in h ? h[k] : m; }); };
  var $ = function (id) { return document.getElementById(id); };
  var el = API.el, boton = API.boton, pill = API.pill;
  var PESTANAS = ['textos', 'revisiones', 'campos', 'nuevo'];

  var S = {
    tab: 'textos', listo: false,
    slug: null, revs: [], revsOk: true, seqR: 0, origen: null,
    cx: null, cxOk: true, seqC: 0, editando: null, val: {}, seqV: 0, timerV: 0,
    nv: { paso: 1, nombre: '', partir: 'blanco', origen: '', campos: {}, creando: false }
  };
  var E = API.E;

  /* ── lo que contesta la base, en llano ─────────────────────────────────────────────────────────────────────────────────────────── */
  var FRASES_REV = {
    sesion: 'Tu sesión ha caducado. Vuelve a entrar; lo que has escrito sigue en pantalla.',
    permiso: 'Tu usuario no puede hacer esto: lo hace la administración de la empresa.',
    rev_restaurar_super: 'Volver a poner un texto en uso lo hace el super administrador de la empresa. Pídeselo a él.',
    rev_borrar_activa: 'Esta revisión está activa: archívala antes de borrarla.',
    rev_nombre: 'Pon un nombre a la revisión, de 3 a 80 letras.',
    rev_motivo: 'Falta el motivo de la revisión (mínimo tres letras).',
    rev_tope: 'Una empresa puede tener como mucho 20 revisiones de un contrato: archiva o borra alguna.',
    rev_origen: 'El texto del que parte la revisión ya no es de esta empresa y contrato. Recarga la pantalla.',
    rev_estandar: 'La revisión estándar no se archiva ni se borra: se sustituye activando otra versión.',
    rev_no_archivada: 'Esa revisión no está archivada.',
    rev_sin_activa: 'Esa revisión no tiene una versión activa que archivar.',
    rev_ya_activa: 'Esa revisión ya tiene otra versión activa.',
    rev_no_existe: 'Esa revisión ya no existe. Recarga la pantalla.',
    rev_clave: 'No se ha podido dar un nombre interno a la revisión: prueba con otro nombre.',
    no_activable: 'La base dice que esta revisión no se podría volver a poner en uso tal cual.'
  };
  var FRASES_CX = {
    sesion: 'Tu sesión ha caducado. Vuelve a entrar; lo que has escrito sigue en pantalla.',
    admin: 'Los campos propios de la empresa los escribe su administración.',
    clave: 'La clave del campo no es válida. Cambia el nombre del campo.',
    tipo_invalido: 'Ese tipo de campo no existe.',
    lista: 'Una lista necesita entre 1 y 50 opciones de hasta 80 letras, sin los signos < > { }.',
    solo_lista: 'Solo una lista lleva opciones.',
    choque: 'Esa clave coincide con un campo del sistema. Cambia el nombre del campo.',
    tope: 'Una empresa puede tener hasta 200 campos propios.',
    no_existe: 'Ese campo ya no existe. Recarga la pantalla.',
    etiqueta: 'El nombre del campo no vale: hasta 80 letras y sin los signos < > { }.'
  };
  var FRASES_NV = {
    sesion: 'Tu sesión ha caducado. Vuelve a entrar; lo que has escrito sigue en pantalla.',
    permiso: 'Tu usuario no puede hacer esto: lo hace la administración de la empresa.',
    nv_nombre: 'Pon un nombre de 3 a 80 letras, sin los signos < > { } & ni comillas dobles.',
    nv_partida: 'Elige si partes de una copia o de un contrato en blanco.',
    nv_campos_forma: 'La lista de campos no es válida (como mucho 40).',
    nv_campos_catalogo: 'Alguno de los campos ya no está en el catálogo de tu empresa o está archivado. Vuelve al paso de campos.',
    nv_tope: 'Una empresa puede tener como mucho 30 contratos propios.',
    nv_duplicado: 'Ya hay un contrato con ese nombre: elige otro.',
    nv_falta_origen: 'Elige el contrato del que partir.',
    nv_origen: 'Ese contrato de origen ya no existe. Recarga la pantalla.',
    nv_no_copia: 'Ese contrato no se puede copiar: solo lo cambia el administrador global.',
    nv_sin_texto: 'Ese contrato no tiene texto para tu empresa.',
    nv_partida_invalida: 'El texto de partida no pasa la validación de la base.',
    rev_origen: 'El texto del que parte ya no es de esta empresa y contrato. Recarga la pantalla.'
  };
  /* Pinta, dentro de `caja`, la frase en llano de un mensaje de la base y debajo el mensaje tal cual (textContent). `tipoCx` = el error viene de un campo propio. */
  function pintaRechazo(caja, mensaje, tipoCx) {
    var m = String(mensaje == null ? '' : mensaje), c, frase;
    caja.hidden = false; caja.className = 'tc-nota tc-nota-mal'; caja.textContent = '';
    var esCx = tipoCx === true, esNv = tipoCx === 'nuevo';
    c = esCx ? CX.clasificaError(m) : TC.clasificaError(m);
    var uso = CX.usoDeError(m), n = /^No se puede borrar: (\d+) contrato/.exec(m);
    if (esNv && FRASES_NV[c.tipo]) frase = T(FRASES_NV[c.tipo]);
    else if (esCx && c.tipo === 'tipo_en_uso') frase = uso ? T('El tipo de este campo ya no se puede cambiar: lo usan %v textos y %c contratos. Archívalo y crea otro campo.', { v: uso.versiones, c: uso.contratos }) : T('El tipo de este campo ya no se puede cambiar. Archívalo y crea otro campo.');
    else if (esCx && c.tipo === 'opciones_en_uso') frase = T('En un campo en uso solo se pueden añadir opciones, no quitarlas ni cambiarlas.');
    else if (esCx && c.tipo === 'borrar_en_uso') frase = uso ? T('No se puede borrar: lo usan %v textos y %c contratos. Archívalo para que no se ofrezca más; los contratos que ya lo tienen lo conservan.', { v: uso.versiones, c: uso.contratos }) : T('No se puede borrar: ya lo usa algún texto o contrato. Archívalo para que no se ofrezca más.');
    else if (!esCx && !esNv && c.tipo === 'rev_borrar_en_uso') frase = T('No se puede borrar: la usan %n contratos. Archívala para que no se ofrezca en contratos nuevos; los que ya la usan la siguen leyendo.', { n: n ? n[1] : '?' });
    else if ((esCx ? FRASES_CX : FRASES_REV)[c.tipo]) frase = T((esCx ? FRASES_CX : FRASES_REV)[c.tipo]);
    else frase = T('La base no ha aceptado la operación.');
    caja.appendChild(el('p', null, frase));
    caja.appendChild(el('p', 'tc-peq tc-detalle', T('Mensaje de la base: ') + c.detalle));
  }
  function nota(id, texto, tono, accion) {
    var n = $(id); if (!n) return;
    n.hidden = !texto; n.textContent = texto || ''; n.className = 'tc-nota' + (tono ? ' tc-nota-' + tono : '');
    if (texto && accion) n.appendChild(accion);
  }

  /* ── las pestañas ──────────────────────────────────────────────────────────────────────────────────────────────────────────────── */
  function pestanaDeHash() { var h = String(location.hash || '').replace(/^#/, ''); return PESTANAS.indexOf(h) !== -1 ? h : 'textos'; }
  function mostrar(tab) {
    if (PESTANAS.indexOf(tab) === -1) tab = 'textos';
    S.tab = tab;
    [].forEach.call(document.querySelectorAll('[data-tc-panel]'), function (p) { p.hidden = p.getAttribute('data-tc-panel') !== tab; });
    [].forEach.call(document.querySelectorAll('[data-tc-pestana]'), function (b) { b.setAttribute('aria-selected', b.getAttribute('data-tc-pestana') === tab ? 'true' : 'false'); });
    if (!S.listo) return;
    if (tab === 'revisiones') iniciaRevisiones();
    else if (tab === 'campos') cargaCampos();
    else if (tab === 'nuevo') iniciaNuevo();
  }
  function iraPestana(tab) {
    if (location.hash === '#' + tab) mostrar(tab); else location.hash = tab;   // el cambio de hash dispara hashchange y ahí se muestra (el botón «atrás» del navegador funciona)
  }

  /* ── REVISIONES ────────────────────────────────────────────────────────────────────────────────────────────────────────────────── */
  function slugsOrdenados() {
    return Object.keys(E.porSlug).sort(function (a, b) {
      var oa = a in E.orden ? E.orden[a] : 999, ob = b in E.orden ? E.orden[b] : 999;
      return oa - ob || (a < b ? -1 : 1);
    });
  }
  function iniciaRevisiones() {
    var sel = $('tc-rev-slug'), slugs = slugsOrdenados();
    if (S.slug && slugs.indexOf(S.slug) === -1) S.slug = null;
    if (!S.slug) S.slug = slugs[0] || null;
    sel.textContent = '';
    slugs.forEach(function (s) { var o = el('option', null, API.nombreDe(s)); o.value = s; if (s === S.slug) o.selected = true; sel.appendChild(o); });
    if (!slugs.length) { pintaVacioRev(T('Tu empresa todavía no tiene textos de contrato en la base.')); return; }
    cargaRevisiones();
  }
  function pintaVacioRev(txt, mal) {
    var l = $('tc-rev-lista'); l.textContent = ''; l.appendChild(el('p', 'tc-vacio' + (mal ? ' tc-mal' : ''), txt));
    $('tc-rev-activas').textContent = '';
  }
  function cargaRevisiones() {
    var seq = ++S.seqR, slug = S.slug;
    pintaVacioRev(T('Trayendo las revisiones…'));
    return API.rpc('plantilla_contrato_revisiones_lista', { p_empresa: E.empresa, p_slug: slug }).then(function (r) {
      if (seq !== S.seqR) return;
      if (r.error) { S.revs = []; S.revsOk = false; pintaVacioRev(T('No he podido leer las revisiones: ') + API.msg(r.error), true); return; }
      S.revs = r.data || []; S.revsOk = true;
      pintaRevisiones();
    });
  }
  function nombreDeVersion(id) {
    var v = (E.porSlug[S.slug] || []).filter(function (x) { return x.id === id; })[0];
    if (!v) return T('su origen');
    return v.variante_nombre || ((v.variante || 'estandar') === 'estandar' ? T('Estándar') : v.variante);
  }
  /* La versión de la que se copia una revisión: su activa; si no, la archivada, el borrador o la última (la base lo valida igualmente). */
  function versionOrigen(variante) {
    var vs = (E.porSlug[S.slug] || []).filter(function (v) { return (v.variante || 'estandar') === variante; });
    var orden = ['activa', 'archivada', 'borrador', 'retirada'];
    for (var i = 0; i < orden.length; i++) {
      var c = vs.filter(function (v) { return v.estado === orden[i]; }).sort(function (a, b) { return b.version - a.version; })[0];
      if (c) return c;
    }
    return vs.sort(function (a, b) { return b.version - a.version; })[0] || null;
  }
  function textoEstado(r) {
    return { activa: pill(T('activa'), 'ok'), archivada: pill(T('archivada'), 'neutro'), borrador: pill(T('borrador, sin activar'), 'aviso'),
             semilla: pill(T('copia inicial del estudio'), 'neutro'), retirada: pill(T('retirada'), 'neutro') }[r.estado] || pill(r.estado, 'neutro');
  }
  function pintaRevisiones() {
    var l = $('tc-rev-lista'); l.textContent = '';
    var esSuper = window.LW_ROL ? window.LW_ROL.esSuperAdmin(E.ficha) : false;
    if (!S.revs.length) l.appendChild(el('p', 'tc-vacio', T('Este contrato todavía no tiene textos en la base.')));
    S.revs.forEach(function (r) {
      var fila = el('div', 'tc-fila'); fila.setAttribute('data-rv-fila', r.variante);
      var info = el('div', 'tc-fila-info');
      var cab = el('div', 'tc-fuerte', r.nombre + ' '); cab.insertAdjacentHTML('beforeend', textoEstado(r)); info.appendChild(cab);
      var det = el('div', 'tc-peq');
      if (r.variante === 'estandar') det.appendChild(el('span', null, T('Texto base')));
      else if (r.parrafos_distintos == null) det.appendChild(el('span', null, T('Sin comparar con su origen')));
      else {
        var n = Number(r.parrafos_distintos), o = nombreDeVersion(r.origen_version);
        det.appendChild(el('span', 'tc-aviso-txt', n === 1 ? T('1 párrafo distinto de «%o»', { o: o }) : T('%n párrafos distintos de «%o»', { n: n, o: o })));
      }
      var c = Number(r.contratos || 0);
      det.appendChild(el('span', null, ' · ' + (c === 0 ? T('no la usa ningún contrato') : (c === 1 ? T('usada en 1 contrato') : T('usada en %n contratos', { n: c })))));
      info.appendChild(det);
      if (r.estado === 'archivada' && !esSuper) info.appendChild(el('div', 'tc-peq', T('Restaurarla lo hace el super administrador de la empresa.')));
      fila.appendChild(info);
      var acc = el('div', 'tc-acc');
      acc.appendChild(boton(T('Editar'), { 'data-rv-editar': r.variante }, 'tc-btn'));
      acc.appendChild(boton(T('Historial'), { 'data-rv-historial': r.variante }));
      acc.appendChild(boton(T('Crear revisión desde esta'), { 'data-rv-dup': r.variante }));
      if (r.variante !== 'estandar') {
        if (r.estado === 'activa') acc.appendChild(boton(T('Archivar'), { 'data-rv-arch': r.variante }));
        if (r.estado === 'archivada') acc.appendChild(boton(T('Restaurar'), { 'data-rv-rest': r.variante }));
        acc.appendChild(boton(T('Borrar'), { 'data-rv-del': r.variante }, 'tc-btn-suave tc-peligro'));
      }
      fila.appendChild(acc); l.appendChild(fila);
    });
    var act = $('tc-rev-activas'); act.textContent = '';
    var activas = S.revs.filter(function (r) { return r.estado === 'activa'; });
    if (!activas.length) act.appendChild(el('li', null, T('Ninguna revisión activa todavía: los contratos nuevos usan la copia inicial del estudio.')));
    activas.forEach(function (r) { act.appendChild(el('li', null, r.nombre)); });
  }
  function revDe(variante) { return S.revs.filter(function (r) { return r.variante === variante; })[0]; }
  function refrescaRevs() { return API.cargaLista().then(cargaRevisiones); }

  function abreCrear(variante) {
    var r = revDe(variante), v = versionOrigen(variante); if (!r || !v) return;
    S.origen = { id: v.id, variante: variante, nombre: r.nombre };
    $('tc-rev-crear').hidden = false; nota('tc-rev-crear-estado', '');
    $('tc-rev-origen').textContent = T('Se copia el texto de «%o». Después editas solo lo que cambia.', { o: r.nombre });
    $('tc-rev-nombre').value = ''; $('tc-rev-motivo').value = '';
    $('tc-rev-nombre').focus();
  }
  function creaRevision() {
    var nombre = $('tc-rev-nombre').value.trim(), motivo = $('tc-rev-motivo').value.trim();
    if (!S.origen) return;
    if (nombre.length < 3) { nota('tc-rev-crear-estado', T('Pon un nombre a la revisión, de 3 a 80 letras.'), 'mal'); $('tc-rev-nombre').focus(); return; }
    if (motivo.length < 3) { nota('tc-rev-crear-estado', T('Escribe por qué se crea (mínimo tres letras): queda en el historial.'), 'mal'); $('tc-rev-motivo').focus(); return; }
    var ok = $('tc-rev-crear-ok'); ok.disabled = true; nota('tc-rev-crear-estado', T('Creando…'));
    API.rpc('plantilla_contrato_revision_crea', { p_empresa: E.empresa, p_slug: S.slug, p_origen: S.origen.id, p_nombre: nombre, p_motivo: motivo, p_variante: null }).then(function (r) {
      ok.disabled = false;
      if (r.error) { pintaRechazo($('tc-rev-crear-estado'), API.msg(r.error), false); return; }
      var nuevaId = r.data, desde = S.origen.nombre;
      S.origen = null; $('tc-rev-crear').hidden = true;
      refrescaRevs().then(function () {
        var v = (E.lista || []).filter(function (x) { return x.id === nuevaId; })[0];
        var abrir = v ? boton(T('Abrir para editar'), { 'data-rv-editar': v.variante }, 'tc-btn') : null;
        nota('tc-rev-estado', T('Creada «%n» a partir de «%o». Es una copia en borrador: ábrela, cambia solo lo que difiere y actívala para que se ofrezca al crear contratos.', { n: nombre, o: desde }), 'ok', abrir);
      });
    });
  }

  /* El cuerpo de lwConfirmar es HTML: el texto de la persona (el nombre de una revisión) NO entra nunca sin escapar. */
  function confirmaTexto(titulo, cuerpoTexto, botonTxt) {
    if (typeof window.lwConfirmar !== 'function') return Promise.resolve(true);
    return window.lwConfirmar({ titulo: titulo, cuerpo: '<p>' + TC.esc(cuerpoTexto) + '</p>', confirmar: botonTxt, tono: 'peligro' });
  }
  function accionRev(rpcNombre, variante, exito) {
    API.rpc(rpcNombre, { p_empresa: E.empresa, p_slug: S.slug, p_variante: variante }).then(function (r) {
      if (r.error) { var n = $('tc-rev-estado'); pintaRechazo(n, API.msg(r.error), false); return; }
      refrescaRevs().then(function () { nota('tc-rev-estado', exito, 'ok'); });
    });
  }
  function archiva(variante) {
    var r = revDe(variante); if (!r) return;
    confirmaTexto(T('¿Archivar esta revisión?'), T('«%o» deja de ofrecerse al crear contratos nuevos. Los contratos que ya la usan no cambian. Se puede restaurar.', { o: r.nombre }), T('Archivar'))
      .then(function (ok) { if (ok) accionRev('plantilla_contrato_revision_archiva', variante, T('Archivada. Ya no sale al crear contratos; los que la usan no cambian.')); });
  }
  function restaura(variante) { accionRev('plantilla_contrato_revision_restaura', variante, T('Restaurada. Vuelve a ofrecerse al crear contratos.')); }
  function borra(variante) {
    var r = revDe(variante); if (!r) return;
    confirmaTexto(T('¿Borrar esta revisión?'), T('«%o» se borra de la lista. Solo se puede si ningún contrato la usa; su historial queda guardado.', { o: r.nombre }), T('Borrar'))
      .then(function (ok) { if (ok) accionRev('plantilla_contrato_revision_borra', variante, T('Borrada «%o».', { o: r.nombre })); });
  }

  /* ── CAMPOS ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────── */
  function tipoRotulo(t) { var x = CX.TIPOS.filter(function (y) { return y[0] === t; })[0]; return x ? T(x[1]) : t; }
  function cargaCampos() {
    var seq = ++S.seqC;
    var l = $('tc-cx-lista'); l.textContent = ''; l.appendChild(el('p', 'tc-vacio', T('Trayendo los campos…'))); nota('tc-cx-aviso', '');
    return API.rpc('plantilla_campo_propio_lista', { p_empresa: E.empresa, p_con_uso: true }).then(function (r) {
      if (seq !== S.seqC) return;
      if (r.error || !Array.isArray(r.data)) {
        S.cx = null; S.cxOk = false;
        l.textContent = ''; l.appendChild(el('p', 'tc-vacio tc-mal', T('No he podido leer los campos: ') + API.msg(r.error || T('la base no ha devuelto la lista'))));
        pintaPrevia(); return;
      }
      S.cx = r.data; S.cxOk = true;
      pintaCampos(); pintaPrevia();
    });
  }
  function vivos() { return (S.cx || []).filter(function (c) { return !c.archivado; }); }
  function campoDe(k) { return (S.cx || []).filter(function (c) { return c.clave === k; })[0]; }
  function idiomaUI() { return window.LW_IDIOMA === 'en' ? 'en' : 'es'; }

  function pintaCampos() {
    var l = $('tc-cx-lista'); l.textContent = '';
    if (!S.cx.length) { l.appendChild(el('p', 'tc-vacio', T('Esta empresa todavía no tiene campos propios. Añade el primero abajo.'))); return; }
    S.cx.forEach(function (c) {
      var fila = el('div', 'tc-fila' + (c.archivado ? ' tc-fila-arch' : '')); fila.setAttribute('data-cx-fila', c.clave);
      var info = el('div', 'tc-fila-info');
      var cab = el('div', 'tc-fuerte', CX.etiqueta(c, idiomaUI()) + (c.obligatorio ? ' *' : '') + ' ');
      cab.insertAdjacentHTML('beforeend', c.archivado ? pill(T('archivado'), 'neutro') : '');
      info.appendChild(cab);
      var det = el('div', 'tc-peq'); det.appendChild(el('code', 'tc-cx-clave', '{{' + c.clave + '}}'));
      det.appendChild(el('span', null, ' · ' + tipoRotulo(c.tipo) + (c.opciones && c.opciones.length ? ' (' + c.opciones.join(', ') + ')' : '') + (c.obligatorio ? ' · ' + T('obligatorio') : '')));
      info.appendChild(det);
      var det2 = el('div', 'tc-peq');
      det2.appendChild(el('span', null, c.sensible ? T('Sensible: oculto al asistente y al bot') : T('Visible para el asistente y el bot')));
      if (c.uso) det2.appendChild(el('span', null, ' · ' + T('lo usan %v textos y %c contratos', { v: c.uso.versiones, c: c.uso.contratos })));
      info.appendChild(det2);
      fila.appendChild(info);
      var acc = el('div', 'tc-acc');
      acc.appendChild(boton(T('Editar'), { 'data-cx-editar': c.clave }, 'tc-btn'));
      acc.appendChild(boton(c.archivado ? T('Restaurar') : T('Archivar'), c.archivado ? { 'data-cx-rest': c.clave } : { 'data-cx-arch': c.clave }));
      acc.appendChild(boton(T('Borrar'), { 'data-cx-del': c.clave }, 'tc-btn-suave tc-peligro'));
      fila.appendChild(acc); l.appendChild(fila);
    });
  }

  /* El formulario de añadir / editar. */
  function llenaTipos() {
    var sel = $('tc-cx-tipo'); sel.textContent = '';
    CX.TIPOS.forEach(function (t) { var o = el('option', null, T(t[1])); o.value = t[0]; sel.appendChild(o); });
  }
  function claveFormulario() { return S.editando || CX.claveDeNombre($('tc-cx-es').value); }
  function refrescaFormulario() {
    $('tc-cx-op-caja').hidden = $('tc-cx-tipo').value !== 'lista';
    var v = $('tc-cx-clave-vista'); v.textContent = '';
    var k = claveFormulario();
    if (S.editando) { v.appendChild(document.createTextNode(T('Clave en los textos: '))); v.appendChild(el('code', 'tc-cx-clave', '{{' + k + '}}')); v.appendChild(document.createTextNode(' ' + T('(no se puede cambiar)'))); }
    else if (k) { v.appendChild(document.createTextNode(T('Clave en los textos: '))); v.appendChild(el('code', 'tc-cx-clave', '{{' + k + '}}')); v.appendChild(document.createTextNode(' ' + T('(sale del nombre y no se puede cambiar después)'))); }
    else v.textContent = T('La clave del campo sale del nombre y no se puede cambiar después.');
  }
  function limpiaFormulario() {
    S.editando = null;
    ['tc-cx-es', 'tc-cx-en', 'tc-cx-id', 'tc-cx-op'].forEach(function (id) { $(id).value = ''; });
    $('tc-cx-tipo').value = 'texto'; $('tc-cx-tipo').disabled = false; $('tc-cx-tipo').removeAttribute('title');
    $('tc-cx-obl').checked = false; $('tc-cx-sens').checked = true;
    $('tc-cx-guardar').textContent = T('Añadir campo'); $('tc-cx-cancelar').hidden = true;
    $('tc-cx-form-titulo').textContent = T('Añadir un campo');
    nota('tc-cx-estado', ''); refrescaFormulario();
  }
  function editaCampo(k) {
    var c = campoDe(k); if (!c) return;
    S.editando = k;
    $('tc-cx-es').value = (c.etiqueta && c.etiqueta.es) || ''; $('tc-cx-en').value = (c.etiqueta && c.etiqueta.en) || ''; $('tc-cx-id').value = (c.etiqueta && c.etiqueta.id) || '';
    $('tc-cx-tipo').value = c.tipo; $('tc-cx-op').value = (c.opciones || []).join(', ');
    var enUso = c.uso && (c.uso.versiones + c.uso.contratos) > 0;
    $('tc-cx-tipo').disabled = !!enUso;
    if (enUso) $('tc-cx-tipo').title = T('El tipo no se cambia en un campo que ya usan textos o contratos. Archívalo y crea otro.');
    $('tc-cx-obl').checked = !!c.obligatorio; $('tc-cx-sens').checked = !!c.sensible;
    $('tc-cx-guardar').textContent = T('Guardar cambios'); $('tc-cx-cancelar').hidden = false;
    $('tc-cx-form-titulo').textContent = T('Editar el campo');
    nota('tc-cx-estado', ''); refrescaFormulario();
    $('tc-cx-es').scrollIntoView({ behavior: 'smooth', block: 'center' }); $('tc-cx-es').focus();
  }
  function guardaCampo() {
    var nombre = $('tc-cx-es').value.trim(), tipo = $('tc-cx-tipo').value, k = claveFormulario(), caja = $('tc-cx-estado');
    function mal(txt, foco) { nota('tc-cx-estado', txt, 'mal'); if (foco) $(foco).focus(); }
    if (nombre.length < 3) return mal(T('Escribe cómo se llama el campo (mínimo 3 letras).'), 'tc-cx-es');
    if (!k) return mal(T('El nombre necesita al menos una letra o una cifra.'), 'tc-cx-es');
    /* La RPC de guardar es un alta-o-cambio: sin esta comprobación un nombre que da la clave de otro campo (también archivado) lo SOBRESCRIBIRÍA en silencio. */
    if (!S.editando && campoDe(k)) return mal(campoDe(k).archivado ? T('Ya existe un campo con ese nombre (%k) y está archivado: restáuralo en la lista.', { k: k }) : T('Ya existe un campo con ese nombre (%k). Elige otro nombre.', { k: k }), 'tc-cx-es');
    var opciones = null;
    if (tipo === 'lista') {
      var o = CX.opcionesDeTexto($('tc-cx-op').value);
      if (o.errores.length) return mal(T(o.errores[0]), 'tc-cx-op');
      opciones = o.opciones;
    }
    var b = $('tc-cx-guardar'); b.disabled = true; nota('tc-cx-estado', T('Guardando…'));
    API.rpc('plantilla_campo_propio_guarda', { p_empresa: E.empresa, p_clave: k, p_etiqueta_es: nombre, p_etiqueta_en: $('tc-cx-en').value.trim() || null, p_etiqueta_id: $('tc-cx-id').value.trim() || null,
      p_tipo: tipo, p_opciones: opciones, p_obligatorio: $('tc-cx-obl').checked, p_sensible: $('tc-cx-sens').checked }).then(function (r) {
      b.disabled = false;
      if (r.error) { pintaRechazo(caja, API.msg(r.error), true); return; }
      var nuevo = !S.editando;
      limpiaFormulario();
      cargaCampos().then(function () {
        nota('tc-cx-aviso', nuevo ? T('Campo «%n» añadido. Ya puedes insertarlo como pastilla en cualquier texto y aparece en el formulario del contrato.', { n: nombre }) : T('Campo «%n» guardado.', { n: nombre }), 'ok');
      });
    });
  }
  function accionCampo(rpcNombre, args, exito) {
    API.rpc(rpcNombre, Object.assign({ p_empresa: E.empresa }, args)).then(function (r) {
      if (r.error) { pintaRechazo($('tc-cx-aviso'), API.msg(r.error), true); return; }
      if (S.editando && S.editando === args.p_clave && rpcNombre === 'plantilla_campo_propio_borra') limpiaFormulario();
      cargaCampos().then(function () { nota('tc-cx-aviso', exito, 'ok'); });
    });
  }
  function archivaCampo(k, archivar) {
    var c = campoDe(k); if (!c) return;
    if (!archivar) { accionCampo('plantilla_campo_propio_archiva', { p_clave: k, p_archivado: false }, T('Campo «%n» restaurado.', { n: CX.etiqueta(c, idiomaUI()) })); return; }
    confirmaTexto(T('¿Archivar este campo?'), T('«%n» deja de ofrecerse en los textos nuevos y en los contratos nuevos. Los contratos que ya tienen su valor lo conservan.', { n: CX.etiqueta(c, idiomaUI()) }), T('Archivar'))
      .then(function (ok) { if (ok) accionCampo('plantilla_campo_propio_archiva', { p_clave: k, p_archivado: true }, T('Campo «%n» archivado.', { n: CX.etiqueta(c, idiomaUI()) })); });
  }
  function borraCampo(k) {
    var c = campoDe(k); if (!c) return;
    confirmaTexto(T('¿Borrar este campo?'), T('«%n» se borra del catálogo. Solo se puede si ningún texto ni contrato lo usa.', { n: CX.etiqueta(c, idiomaUI()) }), T('Borrar'))
      .then(function (ok) { if (ok) accionCampo('plantilla_campo_propio_borra', { p_clave: k }, T('Campo «%n» borrado.', { n: CX.etiqueta(c, idiomaUI()) })); });
  }

  /* ── vista previa: «así lo verá quien crea el contrato» + el JSON que la base guardaría ───────────────────────────────────────── */
  function pintaPrevia() {
    var caja = $('tc-cx-previa'); caja.textContent = '';
    if (!S.cxOk) { caja.appendChild(el('p', 'tc-vacio tc-mal', T('No he podido leer los campos: no hay vista previa.'))); pintaJson(null, null, T('No hay datos que enseñar.')); return; }
    var lista = vivos();
    if (!lista.length) { caja.appendChild(el('p', 'tc-vacio', T('Todavía no hay campos: añade el primero.'))); pintaJson({}, null); return; }
    lista.forEach(function (c) {
      var f = CX.tipoForm(c, { si: T('Sí'), no: T('No') }), caja2 = el('div', 'tc-campo'), id = 'tc-pv-' + c.clave;
      var lab = el('label', null, CX.etiqueta(c, idiomaUI())); lab.setAttribute('for', id);
      if (c.obligatorio) lab.appendChild(el('span', 'tc-req', ' *'));
      caja2.appendChild(lab);
      var ent;
      if (f[2] === 'select') {
        ent = el('select'); ent.appendChild(el('option', null, ''));
        f[3].forEach(function (o) { var par = Array.isArray(o) ? o : [o, o], op = el('option', null, par[1]); op.value = par[0]; ent.appendChild(op); });
      } else {
        ent = el('input'); ent.type = f[2] === 'date' ? 'date' : 'text';
        if (f[2] === 'money') ent.setAttribute('inputmode', 'decimal');
      }
      ent.id = id; ent.setAttribute('data-cx-val', c.clave); ent.autocomplete = 'off';
      if (S.val[c.clave] != null) ent.value = S.val[c.clave];
      caja2.appendChild(ent);
      var er = el('div', 'tc-peq tc-mal'); er.setAttribute('data-cx-err', c.clave); er.hidden = true; caja2.appendChild(er);
      caja.appendChild(caja2);
    });
    comprueba();
  }
  function valoresEscritos() {
    var out = {};
    vivos().forEach(function (c) { var v = S.val[c.clave]; if (v != null && String(v).trim() !== '') out[c.clave] = String(v); });
    return out;
  }
  function pintaJson(fields, errores, aviso) {
    var pre = $('tc-cx-json');
    pre.textContent = fields == null ? '' : JSON.stringify({ datos: { fields: fields } }, null, 2);
    [].forEach.call($('tc-cx-previa').querySelectorAll('[data-cx-err]'), function (n) {
      var k = n.getAttribute('data-cx-err'), e = errores && errores[k];
      n.hidden = !e; n.textContent = '';
      if (e) { var cl = CX.clasificaValor(e); n.textContent = cl ? T(CX.FRASES_VALOR[cl]) : T('La base no acepta este valor: ') + e; }
    });
    $('tc-cx-json-nota').textContent = aviso || '';
  }
  /* Lo que se guardaría lo dice la base (plantilla_campo_propio_valida): ni un número ni una fecha se interpretan aquí. */
  function comprueba() {
    var vals = valoresEscritos(), seq = ++S.seqV;
    if (!Object.keys(vals).length) { pintaJson({}, null, T('Escribe un valor para ver cómo lo guardará la base.')); return; }
    API.rpc('plantilla_campo_propio_valida', { p_empresa: E.empresa, p_valores: vals }).then(function (r) {
      if (seq !== S.seqV) return;
      if (r.error || !r.data) { pintaJson(vals, null, T('No he podido comprobarlo con la base: se enseña lo escrito, sin comprobar.')); return; }
      var d = r.data, malos = Object.keys(d.errores || {}).length;
      pintaJson(d.valores || {}, d.errores || {}, malos ? T('La base no aceptaría algún valor: míralo en rojo.') : T('Comprobado por la base: este es el valor exacto que se guarda.'));
    });
  }

  /* ── CONTRATO NUEVO (E9): asistente de cuatro pasos ───────────────────────────────────────────────────────────────────────────── */
  var PASOS_NV = ['Nombre', 'Punto de partida', 'Campos', 'Revisar'];
  function nvVacio() { return { paso: 1, nombre: '', partir: 'blanco', origen: '', campos: {}, creando: false }; }
  function iniciaNuevo() {
    if (S.cx === null && S.cxOk) cargaCampos().then(pintaNuevo); else pintaNuevo();
  }
  function nvCampo(rotulo, ctrl, id) {
    var c = el('div', 'tc-campo'), l = el('label', null, rotulo); if (id) l.setAttribute('for', id);
    c.appendChild(l); c.appendChild(ctrl); return c;
  }
  function pintaNuevo() {
    var n = S.nv, ol = $('tc-nv-pasos'), caja = $('tc-nv-paso');
    ol.textContent = '';
    PASOS_NV.forEach(function (x, i) { var li = el('li', 'tc-paso' + (n.paso === i + 1 ? ' on' : ''), (i + 1) + '. ' + T(x)); if (n.paso === i + 1) li.setAttribute('aria-current', 'step'); ol.appendChild(li); });
    caja.textContent = '';
    if (n.paso === 1) {
      var inp = el('input'); inp.type = 'text'; inp.id = 'tc-nv-nombre'; inp.maxLength = 80; inp.autocomplete = 'off'; inp.value = n.nombre; inp.setAttribute('data-nv', 'nombre');
      caja.appendChild(nvCampo(T('Cómo se llama el contrato'), inp, 'tc-nv-nombre'));
      caja.appendChild(el('p', 'tc-peq', T('Entre 3 y 80 letras. El identificador interno lo pone la base.')));
    } else if (n.paso === 2) {
      [['blanco', T('En blanco, con las cláusulas que tú escribas')], ['copia', T('Copiar un contrato existente y cambiar lo distinto')]].forEach(function (o) {
        var lab = el('label', 'tc-check'), r = el('input'); r.type = 'radio'; r.name = 'tc-nv-partir'; r.value = o[0]; r.checked = n.partir === o[0]; r.setAttribute('data-nv', 'partir');
        lab.appendChild(r); lab.appendChild(el('span', null, o[1])); caja.appendChild(lab);
      });
      if (n.partir === 'copia') {
        var sel = el('select'); sel.id = 'tc-nv-origen'; sel.setAttribute('data-nv', 'origen');
        var o0 = el('option', null, ''); o0.value = ''; sel.appendChild(o0);
        slugsOrdenados().forEach(function (sl) { var o = el('option', null, API.nombreDe(sl)); o.value = sl; if (sl === n.origen) o.selected = true; sel.appendChild(o); });
        caja.appendChild(nvCampo(T('Contrato del que partir'), sel, 'tc-nv-origen'));
      }
    } else if (n.paso === 3) {
      if (n.partir === 'copia') caja.appendChild(el('p', 'tc-peq', T('Al copiar un contrato, sus campos ya vienen en su texto. Puedes añadir más después, con «Insertar campo» en el editor.')));
      else if (!S.cxOk) caja.appendChild(el('p', 'tc-vacio tc-mal', T('No he podido leer los campos: no se pueden elegir. Vuelve a probar o sigue sin campos.')));
      else {
        caja.appendChild(el('p', 'tc-peq', T('Campos que pedirá este contrato:')));
        var vivosCx = vivos();
        if (!vivosCx.length) caja.appendChild(el('p', 'tc-vacio', T('Esta empresa todavía no tiene campos propios. Créalos en la pestaña «Campos» y vuelve aquí.')));
        vivosCx.forEach(function (c) {
          var lab = el('label', 'tc-check'), ch = el('input'); ch.type = 'checkbox'; ch.checked = !!n.campos[c.clave]; ch.setAttribute('data-nv-campo', c.clave);
          lab.appendChild(ch); lab.appendChild(el('span', null, CX.etiqueta(c, idiomaUI()))); caja.appendChild(lab);
        });
        caja.appendChild(el('p', 'tc-peq', T('Si falta uno, se añade en la pestaña Campos y vuelve aquí.')));
      }
    } else {
      var res = el('div', 'tc-nota');
      var linea = function (k, v) { var p = el('p', null); p.appendChild(el('span', 'tc-peq', k + ': ')); p.appendChild(el('span', 'tc-fuerte', v)); res.appendChild(p); };
      linea(T('Nombre'), n.nombre.trim());
      linea(T('Punto de partida'), n.partir === 'copia' ? T('copia de «%o»', { o: API.nombreDe(n.origen) }) : T('en blanco'));
      var sel2 = n.partir === 'blanco' ? vivos().filter(function (c) { return n.campos[c.clave]; }).map(function (c) { return CX.etiqueta(c, idiomaUI()); }) : [];
      linea(T('Campos'), n.partir === 'copia' ? T('los del contrato copiado') : (sel2.join(', ') || T('ninguno')));
      linea(T('Idioma principal'), T('español; inglés e indonesio se completan después'));
      caja.appendChild(res);
    }
    $('tc-nv-atras').disabled = n.paso === 1 || n.creando;
    $('tc-nv-sig').hidden = n.paso === 4; $('tc-nv-crear').hidden = n.paso !== 4; $('tc-nv-crear').disabled = n.creando;
  }
  function nvSiguiente() {
    var n = S.nv;
    if (n.paso === 1 && n.nombre.trim().length < 3) { nota('tc-nv-estado', T('Escribe cómo se llama el contrato (mínimo 3 letras).'), 'mal'); return; }
    if (n.paso === 2 && n.partir === 'copia' && !n.origen) { nota('tc-nv-estado', T('Elige el contrato del que partir.'), 'mal'); return; }
    nota('tc-nv-estado', ''); n.paso++; pintaNuevo();
  }
  function creaNuevo() {
    var n = S.nv; if (n.creando) return;
    n.creando = true; pintaNuevo(); nota('tc-nv-estado', T('Creando el contrato…'));
    var campos = n.partir === 'blanco' ? vivos().filter(function (c) { return n.campos[c.clave]; }).map(function (c) { return c.clave; }) : [];
    API.rpc('plantilla_contrato_nuevo_crea', { p_empresa: E.empresa, p_nombre: n.nombre.trim(), p_punto_partida: n.partir, p_slug_origen: n.partir === 'copia' ? n.origen : null, p_version_origen: null, p_campos: campos }).then(function (r) {
      n.creando = false;
      if (r.error || !r.data) { pintaNuevo(); pintaRechazo($('tc-nv-estado'), API.msg(r.error || T('la base no ha devuelto el contrato')), 'nuevo'); return; }
      var d = r.data;
      E.nombres[d.slug] = d.nombre || n.nombre.trim();
      S.nv = nvVacio(); nota('tc-nv-estado', '');
      API.cargaLista().then(function () {
        toast(T('Contrato «%n» creado. Ahora escribe su texto.', { n: E.nombres[d.slug] }));
        iraPestana('textos'); API.abreEditor(d.slug, 'estandar');
      });
    });
  }

  /* ── cableado ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────── */
  function cablea() {
    $('tc-pestanas').addEventListener('click', function (ev) {
      var b = ev.target.closest('[data-tc-pestana]'); if (!b) return;
      ev.stopPropagation(); iraPestana(b.getAttribute('data-tc-pestana'));
    });
    window.addEventListener('hashchange', function () { mostrar(pestanaDeHash()); });
    window.addEventListener('popstate', function () { mostrar(pestanaDeHash()); });
    document.addEventListener('lw-tc-ir', function (ev) {
      var d = ev.detail || {};
      if (d.slug) S.slug = d.slug;
      iraPestana(d.tab || 'textos');
    });
    document.addEventListener('lw-tc-empresa', function () {
      S.slug = null; S.revs = []; S.origen = null; S.cx = null; S.val = {}; S.nv = nvVacio(); $('tc-rev-crear').hidden = true; limpiaFormulario();
      nota('tc-rev-estado', ''); nota('tc-cx-aviso', '');
      mostrar(S.tab);
    });
    $('tc-rev-slug').addEventListener('change', function () { S.slug = this.value; S.origen = null; $('tc-rev-crear').hidden = true; nota('tc-rev-estado', ''); cargaRevisiones(); });
    $('tc-panel-revisiones').addEventListener('click', function (ev) {
      var b = ev.target.closest('[data-rv-editar],[data-rv-historial],[data-rv-dup],[data-rv-arch],[data-rv-rest],[data-rv-del],#tc-rev-crear-ok,#tc-rev-crear-no'); if (!b) return;
      ev.stopPropagation();
      if (b.id === 'tc-rev-crear-ok') return creaRevision();
      if (b.id === 'tc-rev-crear-no') { S.origen = null; $('tc-rev-crear').hidden = true; return; }
      if (b.hasAttribute('data-rv-editar')) { iraPestana('textos'); API.abreEditor(S.slug, b.getAttribute('data-rv-editar')); }
      else if (b.hasAttribute('data-rv-historial')) { iraPestana('textos'); API.abreHistorial(S.slug, b.getAttribute('data-rv-historial')); }
      else if (b.hasAttribute('data-rv-dup')) abreCrear(b.getAttribute('data-rv-dup'));
      else if (b.hasAttribute('data-rv-arch')) archiva(b.getAttribute('data-rv-arch'));
      else if (b.hasAttribute('data-rv-rest')) restaura(b.getAttribute('data-rv-rest'));
      else if (b.hasAttribute('data-rv-del')) borra(b.getAttribute('data-rv-del'));
    });
    $('tc-nv-sig').addEventListener('click', function (ev) { ev.stopPropagation(); nvSiguiente(); });
    $('tc-nv-atras').addEventListener('click', function (ev) { ev.stopPropagation(); if (S.nv.paso > 1) { S.nv.paso--; nota('tc-nv-estado', ''); pintaNuevo(); } });
    $('tc-nv-crear').addEventListener('click', function (ev) { ev.stopPropagation(); creaNuevo(); });
    $('tc-nv-paso').addEventListener('input', function (ev) { if (ev.target.getAttribute('data-nv') === 'nombre') S.nv.nombre = ev.target.value; });
    $('tc-nv-paso').addEventListener('change', function (ev) {
      var t = ev.target, k = t.getAttribute('data-nv');
      if (k === 'partir') { S.nv.partir = t.value; pintaNuevo(); }
      else if (k === 'origen') S.nv.origen = t.value;
      else if (t.getAttribute('data-nv-campo')) S.nv.campos[t.getAttribute('data-nv-campo')] = t.checked;
    });
    llenaTipos();
    $('tc-cx-tipo').addEventListener('change', refrescaFormulario);
    $('tc-cx-es').addEventListener('input', refrescaFormulario);
    $('tc-cx-guardar').addEventListener('click', function (ev) { ev.stopPropagation(); guardaCampo(); });
    $('tc-cx-cancelar').addEventListener('click', function (ev) { ev.stopPropagation(); limpiaFormulario(); });
    $('tc-cx-lista').addEventListener('click', function (ev) {
      var b = ev.target.closest('[data-cx-editar],[data-cx-arch],[data-cx-rest],[data-cx-del]'); if (!b) return;
      ev.stopPropagation();
      if (b.hasAttribute('data-cx-editar')) editaCampo(b.getAttribute('data-cx-editar'));
      else if (b.hasAttribute('data-cx-arch')) archivaCampo(b.getAttribute('data-cx-arch'), true);
      else if (b.hasAttribute('data-cx-rest')) archivaCampo(b.getAttribute('data-cx-rest'), false);
      else borraCampo(b.getAttribute('data-cx-del'));
    });
    function alEscribirValor(ev) {
      var k = ev.target && ev.target.getAttribute ? ev.target.getAttribute('data-cx-val') : null; if (!k) return;
      S.val[k] = ev.target.value;
      window.clearTimeout(S.timerV); S.timerV = window.setTimeout(comprueba, 400);
    }
    $('tc-cx-previa').addEventListener('input', alEscribirValor);
    $('tc-cx-previa').addEventListener('change', alEscribirValor);
    limpiaFormulario();
  }

  function inicia() {
    if (!$('tc-pestanas')) return;
    cablea();
    S.tab = pestanaDeHash();
    mostrar(S.tab);                                   // pinta el panel (sin cargar nada hasta que la pantalla de textos esté lista)
    document.addEventListener('lw-tc-listo', function () { S.listo = true; mostrar(S.tab); });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', inicia); else inicia();
})();
