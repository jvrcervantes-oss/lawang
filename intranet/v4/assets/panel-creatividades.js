/* panel-creatividades.js — la portada /v4/creatividades/.
 * Encargo: encargos/20260924_lawang_creatividades_v4.md (owner: D1=A, D2=A, D3=A).
 * Rediseño A «mesa de trabajo» (24-sep-2026, owner: «elige tú»):
 *  1. Arriba, lo que ESPERA APROBACIÓN (estado `pendiente`): un admin lo ve y lo
 *     aprueba o lo devuelve sin buscarlo entre todo lo demás. Quien lo envió puede
 *     retirarlo mientras nadie lo haya mirado.
 *  2. La biblioteca en rejilla densa con la imagen de verdad: el PNG de la pieza o
 *     la portada del dossier (`portada_path`), filtrada por estado con su número.
 *     «Todo» no incluye el archivo: 20 dossiers viejos taparían lo que se usa.
 *  3. El material por proyecto, plegado abajo: es consulta, no tarea.
 *
 * Quién ve qué lo decide la BASE, no esto (revisión previa #68):
 *  - `creatividades_ver` (comerciales) solo recibe filas aprobadas o publicadas;
 *  - los cambios de estado pasan SOLO por la RPC `creatividad_estado` (enviar y
 *    retirar: quien tenga la casilla; lo demás: admin + casilla). Aquí solo se
 *    esconde el botón que fallaría;
 *  - la descarga deja rastro (`creatividad_descarga`) y la URL firmada dura 2 min
 *    y se pide al pulsar, nunca al pintar la lista.
 * Todo texto que viene de la base se pinta con textContent / esc(). */
(function () {
  'use strict';
  if (!/\/v4\/creatividades\/?(index\.html)?$/.test(location.pathname)) return;

  var T = function (s) { return (typeof lwT === 'function') ? lwT(s) : s; };
  function esc(s) { var d = document.createElement('div'); d.textContent = s == null ? '' : String(s); return d.innerHTML.replace(/"/g, '&quot;'); }
  var $ = function (id) { return document.getElementById(id); };
  function loc() { return typeof lwLocale === 'function' ? lwLocale() : 'es-ES'; }
  function fFecha(x) { if (!x) return '—'; var d = new Date(x); return isNaN(d) ? '—' : d.toLocaleDateString(loc(), { day: 'numeric', month: 'short', year: 'numeric' }); }
  // «hace 2 h» / «2 hours ago»: el navegador sabe decirlo en cada idioma.
  function hace(x) {
    var d = new Date(x); if (isNaN(d)) return '';
    var min = Math.round((Date.now() - d) / 60000);
    if (min >= 60 * 24 || typeof Intl.RelativeTimeFormat !== 'function') return fFecha(x);
    var rt = new Intl.RelativeTimeFormat(loc(), { numeric: 'auto' });
    return min < 60 ? rt.format(-Math.max(1, min), 'minute') : rt.format(-Math.round(min / 60), 'hour');
  }
  function aviso(texto, tono) {
    var caja = $('lw-cre-avisos'); if (!caja) return;
    var p = document.createElement('div'); p.setAttribute('role', 'status');
    p.className = 'rounded-xl border px-5 py-4 font-body-sm text-body-sm ' + (tono === 'mal' ? 'border-error/40 bg-error-container/40 text-on-surface' : 'border-burnt-earth/30 bg-surface-alt text-on-surface-variant');
    p.textContent = texto; caja.appendChild(p);
  }
  function mal(e) { var m = (e && e.message) || String(e); if (window.toastMal) toastMal(m); else aviso(m, 'mal'); }

  var FICHA = null, SB = null, PROY = {}, TODAS = [];
  var FILTRO = { estado: 'todo', tipo: '', proyecto_id: '' };
  function tiene(h) { return !!FICHA && (FICHA.rol === 'super_admin' || (FICHA.herramientas || []).indexOf(h) >= 0); }
  function haceTipo(t) { return t === 'pieza' ? tiene('creatividades') : tiene('dossier'); }
  function esAdmin() { return !!FICHA && (FICHA.rol === 'admin' || FICHA.rol === 'super_admin'); }
  function soloVe() { return !tiene('creatividades') && !tiene('dossier'); }
  function mia(c) { return !!FICHA && !!c.enviada_por && c.enviada_por === FICHA.user_id; }

  function editorDe(c) {
    return c.tipo === 'pieza' ? '/intranet/creatividades/redes/?id=' + encodeURIComponent(c.id)
                              : '/intranet/dossier/builder.html?id=' + encodeURIComponent(c.id);
  }
  function nombreFichero(c) {
    var base = String(c.titulo || 'lawang').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
      .replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '').slice(0, 60) || 'lawang';
    return 'lawang_' + base + '_' + (c.formato || '') + '.png';
  }
  function tipoTxt(c) {
    if (c.tipo === 'dossier') return T('Dossier') + (c.origen === 'repo' ? ' · ' + T('del repositorio') : '');
    var f = { '4x5': 'Feed', '9x16': 'Story' }[c.formato] || '';
    return T('Pieza') + (f ? ' ' + f : '') + (c.lleva_render ? ' · render' : '');
  }

  /* La imagen de la tarjeta: el PNG de la pieza o la portada del dossier. Sin ninguna
     de las dos (los presupuestos de obra del repositorio son solo texto), una portada
     tipográfica con el título: nunca una caja gris con un icono. */
  function miniatura(c, conEstado) {
    var th = document.createElement('div');
    var ruta = c.tipo === 'pieza' ? c.path : c.portada_path;
    if (ruta) {
      th.className = 'cre-th';
      var img = document.createElement('img'); img.alt = ''; img.loading = 'lazy'; th.appendChild(img);
      lwCreatividades.urlVer(ruta).then(function (u) { img.src = u; }).catch(function () { img.remove(); });
    } else {
      th.className = 'cre-th tipo';
      var sm = document.createElement('small'); sm.textContent = c.tipo === 'dossier' ? T('Dossier') : T('Pieza');
      var st = document.createElement('strong'); st.textContent = c.titulo;
      th.appendChild(sm); th.appendChild(st);
    }
    if (conEstado && c.estado !== 'publicada') {
      var est = document.createElement('span'); est.className = 'cre-est ' + c.estado;
      est.textContent = T(lwCreatividades.ESTADOS[c.estado] || c.estado); th.appendChild(est);
    }
    return th;
  }

  async function descargar(c, btn) {
    btn.disabled = true;
    try {
      var url = await lwCreatividades.urlDescarga(c.id, c.path, nombreFichero(c));
      var a = document.createElement('a'); a.href = url; a.rel = 'noopener'; document.body.appendChild(a); a.click(); a.remove();
    } catch (e) {
      if (window.toastMal) toastMal(T('No se pudo descargar: ') + ((e && e.message) || e)); else aviso(T('No se pudo descargar.'), 'mal');
    } finally { btn.disabled = false; }
  }

  var CONFIRMA = {
    aprobada: ['¿Aprobar «', 'Al aprobarla, los comerciales con acceso la pueden descargar y enviar. Ya no se podrá editar: un cambio será una copia nueva.', 'Aprobar', ''],
    archivada: ['¿Archivar «', 'Deja de estar disponible para los comerciales. Las copias que ya se descargaron no se pueden retirar: si es por un motivo legal, avísales.', 'Archivar', 'peligro'],
    borrador: ['¿Devolver «', 'Vuelve a borrador para que se corrija y se envíe otra vez. Los comerciales no la ven.', 'Devolver', '']
  };
  async function cambia(c, destino, btn) {
    var k = CONFIRMA[destino];
    if (k) {
      var ok = await lwConfirmar({ titulo: T(k[0]) + esc(c.titulo) + '»?', cuerpo: '<p>' + esc(T(k[1])) + '</p>', confirmar: T(k[2]), tono: k[3] || undefined });
      if (!ok) return;
    }
    btn.disabled = true;
    try {
      await lwCreatividades.cambiarEstado(c.id, destino);
      if (window.toast) toast(T('Hecho: ') + T(lwCreatividades.ESTADOS[destino]).toLowerCase());
      await recarga();
    } catch (e) { btn.disabled = false; mal(e); }
  }

  function boton(caja, texto, fn, pri) {
    var b = document.createElement('button'); b.type = 'button'; b.setAttribute('data-real', ''); b.textContent = T(texto);
    if (pri) b.className = 'pri'; b.onclick = function () { fn(b); }; caja.appendChild(b); return b;
  }
  function enlace(caja, texto, href) {
    var a = document.createElement('a'); a.href = href; a.setAttribute('data-real', ''); a.textContent = T(texto); caja.appendChild(a); return a;
  }

  /* Acciones de la tarjeta, según estado y quién mira. `pendiente` se gestiona en la
     cola de arriba; aquí solo se abre. */
  function acciones(c, caja) {
    if (c.tipo === 'pieza' && c.path && c.estado !== 'borrador') boton(caja, 'Descargar', function (b) { descargar(c, b); }, c.estado === 'aprobada' || c.estado === 'publicada');
    if (haceTipo(c.tipo)) enlace(caja, c.estado === 'borrador' ? 'Editar' : 'Abrir', editorDe(c));
    else if (c.tipo === 'dossier') enlace(caja, 'Abrir para imprimir', editorDe(c));
    if (!haceTipo(c.tipo)) return;
    if (c.estado === 'borrador' && (c.path || c.tipo === 'dossier') && c.estado_path) boton(caja, 'Enviar a aprobar', function (b) { cambia(c, 'pendiente', b); });
    if (!esAdmin()) return;
    if (c.estado === 'aprobada') boton(caja, 'Marcar publicada', function (b) { cambia(c, 'publicada', b); });
    if (c.estado === 'aprobada' || c.estado === 'publicada' || c.estado === 'borrador') boton(caja, 'Archivar', function (b) { cambia(c, 'archivada', b); });
  }

  function tarjeta(c) {
    var card = document.createElement('article'); card.className = 'cre-card';
    card.appendChild(miniatura(c, true));
    var h = document.createElement('h3'); h.textContent = c.titulo; card.appendChild(h);
    var meta = document.createElement('p'); meta.className = 'cre-meta';
    meta.textContent = (PROY[c.proyecto_id] || T('Sin proyecto')) + ' · ' + tipoTxt(c) + ' · ' + fFecha(c.publicada_en || c.aprobada_en || c.actualizado_en || c.creado_en);
    card.appendChild(meta);
    var acc = document.createElement('div'); acc.className = 'cre-acc'; acciones(c, acc);
    if (acc.childNodes.length) card.appendChild(acc);
    return card;
  }

  // ── Cola de aprobación ────────────────────────────────────────────────────
  function pintaCola() {
    var cola = $('lw-cre-cola');
    var pend = TODAS.filter(function (c) { return c.estado === 'pendiente' && haceTipo(c.tipo); });
    if (!pend.length || soloVe()) { cola.hidden = true; return; }
    cola.hidden = false;
    $('lw-cre-cola-t').textContent = (esAdmin() ? T('Esperan tu aprobación') : T('Enviadas a aprobar')) + ' · ' + pend.length;
    $('lw-cre-cola-d').textContent = esAdmin()
      ? T('Las reglas de Legal ya pasaron al guardar: falta tu visto bueno.')
      : T('Un admin las revisa. Mientras tanto no se pueden editar.');
    var l = $('lw-cre-cola-lista'); l.innerHTML = '';
    pend.forEach(function (c) {
      var f = document.createElement('div'); f.className = 'cre-cola-fila';
      f.appendChild(miniatura(c, false));
      var tx = document.createElement('div'); tx.className = 'cre-cola-txt';
      var b = document.createElement('b'); b.textContent = c.titulo; tx.appendChild(b);
      var s = document.createElement('span'); s.textContent = (PROY[c.proyecto_id] || T('Sin proyecto')) + ' · ' + tipoTxt(c) + ' · ' + hace(c.enviada_en || c.actualizado_en || c.creado_en);
      tx.appendChild(s); f.appendChild(tx);
      var acc = document.createElement('div'); acc.className = 'cre-cola-acc';
      enlace(acc, 'Ver', editorDe(c));
      if (esAdmin()) {
        boton(acc, 'Devolver', function (bt) { cambia(c, 'borrador', bt); });
        boton(acc, 'Aprobar', function (bt) { cambia(c, 'aprobada', bt); }, true);
      } else if (mia(c)) {
        boton(acc, 'Retirar', function (bt) { cambia(c, 'borrador', bt); });
      }
      f.appendChild(acc); l.appendChild(f);
    });
  }

  // ── Biblioteca ─────────────────────────────────────────────────────────────
  var SEGMENTOS = [['todo', 'Todo'], ['publicada', 'Publicadas'], ['aprobada', 'Aprobadas'], ['pendiente', 'Para aprobar'], ['borrador', 'Borradores'], ['archivada', 'Archivo']];
  function pasaFiltro(c, estado) {
    if (FILTRO.tipo && c.tipo !== FILTRO.tipo) return false;
    if (FILTRO.proyecto_id && c.proyecto_id !== FILTRO.proyecto_id) return false;
    if (estado === 'todo') return c.estado !== 'archivada';
    return c.estado === estado;
  }
  function pintaSegmentos() {
    var caja = $('lw-cre-estados'); caja.innerHTML = '';
    SEGMENTOS.forEach(function (sg) {
      var n = TODAS.filter(function (c) { return pasaFiltro(c, sg[0]); }).length;
      if (!n && sg[0] !== 'todo' && sg[0] !== FILTRO.estado) return;   // un estado sin nada no ocupa sitio
      var b = document.createElement('button'); b.type = 'button'; b.setAttribute('data-real', '');
      b.setAttribute('aria-pressed', String(FILTRO.estado === sg[0]));
      b.textContent = T(sg[1]);
      var num = document.createElement('span'); num.textContent = String(n); b.appendChild(num);
      b.onclick = function () { FILTRO.estado = sg[0]; pintaSegmentos(); pintaLista(); };
      caja.appendChild(b);
    });
  }
  function pintaLista() {
    var caja = $('lw-cre-lista'); caja.innerHTML = '';
    var filas = TODAS.filter(function (c) { return pasaFiltro(c, FILTRO.estado); });
    if (!filas.length) {
      var p = document.createElement('p'); p.className = 'col-span-full text-center font-body-md text-body-md text-on-surface-variant py-8';
      p.textContent = soloVe() ? T('Todavía no hay piezas aprobadas para descargar.')
        : (TODAS.length ? T('Nada con estos filtros.') : T('La biblioteca está vacía. Crea la primera pieza o monta un dossier desde la base.'));
      caja.appendChild(p); return;
    }
    filas.forEach(function (c) { caja.appendChild(tarjeta(c)); });
  }
  async function recarga() {
    try {
      TODAS = await lwCreatividades.listar({});
    } catch (e) {
      $('lw-cre-lista').innerHTML = '';
      aviso(T('No se pudo leer la biblioteca: ') + ((e && e.message) || e), 'mal');
      return;
    }
    pintaCola(); pintaSegmentos(); pintaLista();
  }

  // Material por proyecto: se siembra de `proyectos` (un proyecto sin fotos también sale: es lo que falta).
  async function pintaMaterial() {
    var r = await Promise.all([
      SB.from('deck_fotos').select('ambito, proyecto_id, modelo_id, tipo').limit(5000),
      SB.from('modelos').select('id, nombre, publicado').eq('activo', true)
    ]);
    if (r[0].error || r[1].error) { aviso(T('No se pudo leer el material de los proyectos.'), 'mal'); return; }
    var fotos = r[0].data || [], mods = r[1].data || [];
    var cuenta = {};
    Object.keys(PROY).forEach(function (id) { cuenta[id] = { foto: 0, render: 0 }; });
    var porMod = {};
    fotos.forEach(function (f) {
      var real = f.tipo === 'foto';
      if (f.ambito === 'proyecto' && cuenta[f.proyecto_id]) { cuenta[f.proyecto_id][real ? 'foto' : 'render']++; }
      if (f.ambito === 'modelo') { porMod[f.modelo_id] = (porMod[f.modelo_id] || 0) + 1; }
    });
    var soloR = 0, nada = 0;
    var ids = Object.keys(cuenta).sort(function (a, b) {
      var ca = cuenta[a], cb = cuenta[b];
      var pa = ca.foto ? 2 : ca.render ? 1 : 0, pb = cb.foto ? 2 : cb.render ? 1 : 0;
      return pa - pb || String(PROY[a]).localeCompare(String(PROY[b]));
    });
    var tb = $('lw-cre-mat'); tb.innerHTML = '';
    ids.forEach(function (id) {
      var c = cuenta[id], estado, clase;
      if (c.foto) { estado = T('Listo'); clase = 'text-territorial-green'; }
      else if (c.render) { estado = T('Solo render'); clase = 'text-burnt-earth'; soloR++; }
      else { estado = T('Sin material'); clase = 'text-error'; nada++; }
      var tr = document.createElement('tr'); tr.className = 'border-t border-outline-variant/30';
      tr.innerHTML = '<td class="px-5 py-3 font-body-md text-body-md">' + esc(PROY[id]) + '</td>'
        + '<td class="px-5 py-3 text-right tabular-nums">' + c.foto + '</td>'
        + '<td class="px-5 py-3 text-right tabular-nums">' + c.render + '</td>'
        + '<td class="px-5 py-3 font-label-md text-[13px] ' + clase + '">' + esc(estado) + '</td>';
      tb.appendChild(tr);
    });
    var sinR = mods.filter(function (m) { return !porMod[m.id]; }).map(function (m) { return m.nombre; });
    $('lw-cre-modelos').textContent = sinR.length
      ? T('Modelos sin ninguna imagen (no pueden salir en un dossier): ') + sinR.join(' · ')
      : T('Todos los modelos activos tienen imágenes.');
    // El resumen del plegable dice lo que falta, que es lo único accionable.
    var partes = [];
    if (nada) partes.push(nada + ' ' + T('sin material'));
    if (soloR) partes.push(soloR + ' ' + T('solo con render'));
    if (sinR.length) partes.push(sinR.length + ' ' + T('modelos sin imágenes'));
    $('lw-cre-mat-r').textContent = partes.length ? '· ' + partes.join(' · ') : '· ' + T('todo con material');
    $('lw-cre-material').hidden = false;
  }

  function cablea() {
    $('lw-cre-tipo').addEventListener('change', function (e) { FILTRO.tipo = e.target.value; pintaSegmentos(); pintaLista(); });
    $('lw-cre-proy').addEventListener('change', function (e) { FILTRO.proyecto_id = e.target.value; pintaSegmentos(); pintaLista(); });
  }

  function arranca() {
    if (!window.LW_AUTH || !window.lwCreatividades) { aviso(T('Falta la capa de Creatividades en esta página.'), 'mal'); return; }
    window.LW_AUTH.then(async function (a) {
      FICHA = a.ficha; SB = a.sb;
      if (FICHA && !FICHA.user_id && a.session && a.session.user) FICHA.user_id = a.session.user.id;
      $('lw-cre-pieza').hidden = !tiene('creatividades');
      $('lw-cre-dossier').hidden = !tiene('dossier');
      var r = await SB.from('proyectos').select('id, nombre').order('nombre');
      (r.data || []).forEach(function (p) {
        PROY[p.id] = p.nombre;
        var o = document.createElement('option'); o.value = p.id; o.textContent = p.nombre; $('lw-cre-proy').appendChild(o);
      });
      cablea();
      await recarga();
      if (!soloVe()) await pintaMaterial();
    }).catch(mal);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', arranca); else arranca();
})();
