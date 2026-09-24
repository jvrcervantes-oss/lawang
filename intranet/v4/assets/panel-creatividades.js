/* panel-creatividades.js — la portada /v4/creatividades/ (24-sep-2026).
 * Encargo: encargos/20260924_lawang_creatividades_v4.md (owner: D1=A, D2=A, D3=A).
 *
 * Tres cosas y nada más:
 *  1. Biblioteca de piezas y dossiers (tabla `creatividades`) con su estado.
 *  2. Acciones por estado: abrir, descargar, aprobar/publicar/archivar.
 *  3. Material por proyecto (qué proyectos y modelos no tienen fotos todavía).
 *
 * Quién ve qué lo decide la BASE, no esto (revisión previa #68):
 *  - `creatividades_ver` (comerciales) solo recibe filas aprobadas o publicadas;
 *  - los cambios de estado pasan SOLO por la RPC `creatividad_estado`, que exige
 *    admin + la casilla del tipo; aquí solo se esconde el botón que fallaría;
 *  - la descarga deja rastro (`creatividad_descarga`) y la URL firmada dura 2 min
 *    y se pide al pulsar, nunca al pintar la lista.
 * Todo texto que viene de la base se pinta con textContent / esc(). */
(function () {
  'use strict';
  if (!/\/v4\/creatividades\/?(index\.html)?$/.test(location.pathname)) return;

  var T = function (s) { return (typeof lwT === 'function') ? lwT(s) : s; };
  function esc(s) { var d = document.createElement('div'); d.textContent = s == null ? '' : String(s); return d.innerHTML.replace(/"/g, '&quot;'); }
  var $ = function (id) { return document.getElementById(id); };
  function fFecha(x) { if (!x) return '—'; var d = new Date(x); return isNaN(d) ? '—' : d.toLocaleDateString(typeof lwLocale === 'function' ? lwLocale() : 'es-ES', { day: '2-digit', month: 'short', year: 'numeric' }); }
  function aviso(texto, tono) {
    var caja = $('lw-cre-avisos'); if (!caja) return;
    var p = document.createElement('div'); p.setAttribute('role', 'status');
    p.className = 'rounded-xl border px-5 py-4 font-body-sm text-body-sm ' + (tono === 'mal' ? 'border-error/40 bg-error-container/40 text-on-surface' : 'border-burnt-earth/30 bg-surface-alt text-on-surface-variant');
    p.textContent = texto; caja.appendChild(p);
  }

  var FICHA = null, SB = null, PROY = {}, FILTRO = { tipo: '', estado: '', proyecto_id: '' };
  function tiene(h) { return !!FICHA && (FICHA.rol === 'super_admin' || (FICHA.herramientas || []).indexOf(h) >= 0); }
  function haceTipo(t) { return t === 'pieza' ? tiene('creatividades') : tiene('dossier'); }
  function esAdmin() { return !!FICHA && (FICHA.rol === 'admin' || FICHA.rol === 'super_admin'); }
  function soloVe() { return !tiene('creatividades') && !tiene('dossier'); }

  function editorDe(c) {
    return c.tipo === 'pieza' ? '/intranet/creatividades/redes/?id=' + encodeURIComponent(c.id)
                              : '/intranet/dossier/builder.html?id=' + encodeURIComponent(c.id);
  }
  function nombreFichero(c) {
    var base = String(c.titulo || 'lawang').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
      .replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '').slice(0, 60) || 'lawang';
    return 'lawang_' + base + '_' + (c.formato || '') + '.png';
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

  var ACCIONES = {
    borrador:  [['aprobada', 'Aprobar', true], ['archivada', 'Archivar', false]],
    aprobada:  [['publicada', 'Marcar publicada', true], ['archivada', 'Archivar', false]],
    publicada: [['archivada', 'Archivar', false]],
    archivada: []
  };
  async function cambia(c, destino, btn) {
    if (destino === 'archivada') {
      var ok = await lwConfirmar({ titulo: T('¿Archivar «') + esc(c.titulo) + '»?',
        cuerpo: '<p>' + esc(T('Deja de estar disponible para los comerciales. Las copias que ya se descargaron no se pueden retirar: si es por un motivo legal, avísales.')) + '</p>',
        confirmar: T('Archivar'), tono: 'peligro' });
      if (!ok) return;
    }
    if (destino === 'aprobada') {
      var ok2 = await lwConfirmar({ titulo: T('¿Aprobar «') + esc(c.titulo) + '»?',
        cuerpo: '<p>' + esc(T('Al aprobarla, los comerciales con acceso la pueden descargar y enviar. Ya no se podrá editar: un cambio será una copia nueva.')) + '</p>',
        confirmar: T('Aprobar') });
      if (!ok2) return;
    }
    btn.disabled = true;
    try {
      await lwCreatividades.cambiarEstado(c.id, destino);
      if (window.toast) toast(T('Hecho: ') + T(lwCreatividades.ESTADOS[destino]).toLowerCase());
      await pintaLista();
    } catch (e) {
      btn.disabled = false;
      if (window.toastMal) toastMal((e && e.message) || String(e)); else aviso((e && e.message) || String(e), 'mal');
    }
  }

  function tarjeta(c) {
    var card = document.createElement('article'); card.className = 'cre-card';
    var mini = document.createElement('div'); mini.className = 'cre-mini' + (c.tipo === 'dossier' ? ' dossier' : '');
    if (c.tipo === 'pieza' && c.path) {
      var img = document.createElement('img'); img.alt = ''; img.loading = 'lazy'; mini.appendChild(img);
      lwCreatividades.urlVer(c.path).then(function (u) { img.src = u; }).catch(function () { img.remove(); });
    } else {
      var ic = document.createElement('span'); ic.className = 'material-symbols-outlined text-[40px]';
      ic.textContent = c.tipo === 'dossier' ? 'menu_book' : 'image'; mini.appendChild(ic);
    }
    card.appendChild(mini);

    var cuerpo = document.createElement('div'); cuerpo.className = 'px-4 pt-3 pb-2 flex flex-col gap-1';
    var fila1 = document.createElement('div'); fila1.className = 'flex items-center gap-2 flex-wrap';
    var est = document.createElement('span'); est.className = 'cre-est ' + c.estado; est.textContent = T(lwCreatividades.ESTADOS[c.estado] || c.estado);
    fila1.appendChild(est);
    var tipo = document.createElement('span'); tipo.className = 'font-body-sm text-[12px] text-on-surface-variant';
    tipo.textContent = (c.tipo === 'pieza' ? T('Pieza') + (c.formato ? ' ' + c.formato.replace('x', ':') : '') : T('Dossier')) + (c.origen === 'repo' ? ' · ' + T('del repositorio') : '');
    fila1.appendChild(tipo);
    if (c.lleva_render) { var r = document.createElement('span'); r.className = 'cre-est archivada'; r.textContent = T('Con render'); fila1.appendChild(r); }
    cuerpo.appendChild(fila1);
    var h = document.createElement('h3'); h.className = 'font-label-md text-[15px] leading-snug text-on-surface'; h.textContent = c.titulo; cuerpo.appendChild(h);
    var sub = document.createElement('p'); sub.className = 'font-body-sm text-body-sm text-on-surface-variant';
    sub.textContent = (PROY[c.proyecto_id] || T('Sin proyecto')) + ' · ' + fFecha(c.aprobada_en || c.creado_en);
    cuerpo.appendChild(sub);
    card.appendChild(cuerpo);

    var acc = document.createElement('div'); acc.className = 'cre-acc';
    function boton(texto, fn, pri) {
      var b = document.createElement('button'); b.type = 'button'; b.setAttribute('data-real', ''); b.textContent = T(texto);
      if (pri) b.className = 'pri'; b.onclick = function () { fn(b); }; acc.appendChild(b); return b;
    }
    if (c.tipo === 'pieza' && c.path) boton('Descargar PNG', function (b) { descargar(c, b); }, c.estado !== 'borrador');
    // Abrir: quien hace el tipo, en su editor; un comercial abre el dossier aprobado para imprimirlo.
    if (haceTipo(c.tipo) || (c.tipo === 'dossier' && c.estado !== 'borrador')) {
      var a = document.createElement('a'); a.href = editorDe(c); a.setAttribute('data-real', '');
      a.textContent = haceTipo(c.tipo) ? T(c.estado === 'borrador' ? 'Editar' : 'Abrir') : T('Abrir para imprimir');
      acc.appendChild(a);
    }
    if (esAdmin() && haceTipo(c.tipo)) {
      (ACCIONES[c.estado] || []).forEach(function (x) { boton(x[1], function (b) { cambia(c, x[0], b); }, x[2]); });
    }
    card.appendChild(acc);
    return card;
  }

  async function pintaLista() {
    var caja = $('lw-cre-lista');
    try {
      var filas = await lwCreatividades.listar(FILTRO);
      caja.innerHTML = '';
      if (!filas.length) {
        var p = document.createElement('p'); p.className = 'col-span-full text-center font-body-md text-body-md text-on-surface-variant py-8';
        p.textContent = soloVe() ? T('Todavía no hay piezas aprobadas para descargar.')
          : (FILTRO.tipo || FILTRO.estado || FILTRO.proyecto_id ? T('Nada con estos filtros.') : T('La biblioteca está vacía. Crea la primera pieza o monta un dossier desde la base.'));
        caja.appendChild(p); return;
      }
      filas.forEach(function (c) { caja.appendChild(tarjeta(c)); });
    } catch (e) {
      caja.innerHTML = '';
      aviso(T('No se pudo leer la biblioteca: ') + ((e && e.message) || e), 'mal');
    }
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
    var pf = 0, pr = 0, mf = 0, mr = 0, porMod = {};
    fotos.forEach(function (f) {
      var real = f.tipo === 'foto';
      if (f.ambito === 'proyecto' && cuenta[f.proyecto_id]) { cuenta[f.proyecto_id][real ? 'foto' : 'render']++; }
      if (f.ambito === 'proyecto') { real ? pf++ : pr++; }
      if (f.ambito === 'modelo') { real ? mf++ : mr++; porMod[f.modelo_id] = (porMod[f.modelo_id] || 0) + 1; }
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
    function pon(k, t) { document.querySelectorAll('[data-cre="' + k + '"]').forEach(function (e) { e.textContent = t; }); }
    pon('k-proy', String(pf + pr)); pon('k-proy-d', pf + ' ' + T('fotos reales') + ' · ' + pr + ' ' + T('renders'));
    pon('k-mod', String(mf + mr)); pon('k-mod-d', (mods.length - sinR.length) + ' ' + T('de') + ' ' + mods.length + ' ' + T('modelos con imágenes'));
    pon('k-render', String(soloR)); pon('k-nada', String(nada));
    $('lw-cre-kpis').hidden = false; $('lw-cre-material').hidden = false;
  }

  function cablea() {
    document.querySelectorAll('[data-cre-tipo]').forEach(function (b) {
      b.addEventListener('click', function () {
        FILTRO.tipo = b.getAttribute('data-cre-tipo');
        document.querySelectorAll('[data-cre-tipo]').forEach(function (x) { x.setAttribute('aria-pressed', String(x === b)); });
        pintaLista();
      });
    });
    $('lw-cre-estado').addEventListener('change', function (e) { FILTRO.estado = e.target.value; pintaLista(); });
    $('lw-cre-proy').addEventListener('change', function (e) { FILTRO.proyecto_id = e.target.value; pintaLista(); });
  }

  function arranca() {
    if (!window.LW_AUTH || !window.lwCreatividades) { aviso(T('Falta la capa de Creatividades en esta página.'), 'mal'); return; }
    window.LW_AUTH.then(async function (a) {
      FICHA = a.ficha; SB = a.sb;
      $('lw-cre-pieza').hidden = !tiene('creatividades');
      $('lw-cre-dossier').hidden = !tiene('dossier');
      if (soloVe()) {
        // Un comercial ve solo lo aprobado: el filtro de estado sería confuso (la RLS ya filtra).
        var sel = $('lw-cre-estado'); if (sel) sel.hidden = true;
      }
      var r = await SB.from('proyectos').select('id, nombre').order('nombre');
      (r.data || []).forEach(function (p) {
        PROY[p.id] = p.nombre;
        var o = document.createElement('option'); o.value = p.id; o.textContent = p.nombre; $('lw-cre-proy').appendChild(o);
      });
      cablea();
      await pintaLista();
      if (!soloVe()) await pintaMaterial();
    });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', arranca); else arranca();
})();
