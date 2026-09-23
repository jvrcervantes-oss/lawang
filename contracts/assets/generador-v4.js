/* ═══════════════════════════════════════════════════════════════════════════
   generador-v4.js — la COMPOSICIÓN de la cara v4 del generador (23-sep-2026)
   ═══════════════════════════════════════════════════════════════════════════
   El generador es uno solo (contracts/app.html) con dos caras. Los colores y
   la tipografía van en suite-v4-generador.css. Este fichero solo RECOLOCA,
   siguiendo el boceto que aprobó el owner el 23-sep:
     · cabecera de una fila: ☰ · ← Contratos · tipo · idioma · estado · Guardar
     · barra de herramientas a la vista, sin menús: Documento · Firma · Cobro,
       con Registro y Limpiar fijos a la derecha
     · banda de estado, solo en firma o firmado, con lo que se puede hacer ahí
     · taller del documento (Editar texto, Diseño, Original) encima de la
       vista previa: es de admin y trabaja sobre el documento
   Qué se ve y qué se apaga NO se decide aquí: es pintaAcciones() en app.html,
   igual para las dos caras. Aquí los botones solo cambian de sitio. Mover un
   nodo conserva su id y sus listeners, así que el motor no se entera.

   Inerte sin `html.v4` (assets/piel.js). Corre una vez, con `defer`.
   ═══════════════════════════════════════════════════════════════════════════ */
(function () {
  'use strict';
  var html = document.documentElement;
  if (!html.classList.contains('v4')) return;
  var T = window.lwT || function (s) { return s; };
  var $ = function (id) { return document.getElementById(id); };

  /* Icono de cada botón (Material Symbols, la familia de la v4). El glifo que
     la clásica lleva escrito DENTRO del texto (✎ 🎨 🔒 ✉…) se quita del
     rótulo, y el motor puede volver a escribirlo (p. ej. «🔒 Subir firmado»
     tras subir): un observador lo vuelve a quitar. */
  var ICONOS = {
    btnContracts: 'arrow_back', btnSave: 'save', btnPdf: 'picture_as_pdf', btnEmail: 'mail',
    btnDerivar: 'content_copy', btnEnviarFirma: 'draw', btnLockUpload: 'upload_file',
    btnFacturar: 'receipt_long', btnRegistro: 'history', btnReset: 'mop',
    btnEdit: 'edit', btnDesign: 'palette', btnEditReset: 'restart_alt',
    btnEditarFirmado: 'edit_note', btnDownloadSigned: 'download', btnDesbloquear: 'lock_open',
    btnClose: 'close'
  };
  var GLIFO = /^[^\p{L}\p{N}(«"]+|[^\p{L}\p{N})»".]+$/gu;
  function limpia(b) {
    b.childNodes.forEach(function (n) {
      if (n.nodeType === 3) { var t = n.nodeValue.replace(GLIFO, ''); if (t !== n.nodeValue) n.nodeValue = t; }
    });
  }
  function iconiza(id) {
    var b = $(id); if (!b) return;
    b.classList.add('lw4-tb');
    b.setAttribute('data-ico', ICONOS[id]);
    limpia(b);
    new MutationObserver(function () { limpia(b); }).observe(b, { childList: true, characterData: true, subtree: true });
  }

  function grupo(nombre, ids, clase) {
    var g = document.createElement('div');
    g.className = 'pv-grupo lw4-grupo' + (clase ? ' ' + clase : '');
    g.setAttribute('role', 'group');
    if (nombre) {
      g.setAttribute('aria-label', T(nombre));
      var s = document.createElement('span'); s.className = 'g lw4-glab'; s.textContent = T(nombre);
      g.appendChild(s);
    }
    ids.forEach(function (id) { var b = $(id); if (b) g.appendChild(b); });
    return g;
  }

  function monta() {
    var top = document.querySelector('.lw-topbar');
    var bar = document.querySelector('.pv-bar');
    var pane = $('pane');
    if (!top || !bar || !pane || top.dataset.lw4) return;
    top.dataset.lw4 = '1';

    /* ── cabecera ─────────────────────────────────────────────────────────── */
    var hamb = top.querySelector('[data-lw4-menu]');
    var volver = $('btnContracts');
    if (volver) {
      volver.classList.add('lw4-volver');
      // «← Listado» lleva al listado de la v4 (app.html, listener de btnContracts)
      if (hamb) hamb.insertAdjacentElement('afterend', volver); else top.insertBefore(volver, top.firstChild);
    }
    var estado = document.createElement('span');
    estado.className = 'lw4-estado'; estado.id = 'lw4Estado';
    estado.setAttribute('role', 'status');
    var toggle = $('langToggle');
    (toggle || top.lastChild).insertAdjacentElement('afterend', estado);
    var der = document.createElement('div'); der.className = 'lw4-cab-der';
    ['btnDownloadSigned', 'btnSave', 'btnNuevoC'].forEach(function (id) { var b = $(id); if (b) der.appendChild(b); });
    top.appendChild(der);

    /* ── barra de herramientas: sale del panel de la vista previa y ocupa el
          ancho entero, justo debajo de la cabecera ──────────────────────── */
    var cierre = $('btnClose');                       // se queda con el panel: cierra la vista a pantalla completa
    var viejos = [].slice.call(bar.querySelectorAll('.pv-grupo'));
    bar.appendChild(grupo('Documento', ['btnPdf', 'btnEmail', 'btnDerivar']));
    bar.appendChild(grupo('Firma', ['btnEnviarFirma', 'btnLockUpload']));
    bar.appendChild(grupo('Cobro', ['btnFacturar']));
    bar.appendChild(grupo('', ['btnRegistro', 'btnReset'], 'lw4-especiales'));
    bar.classList.add('lw4-barra');
    top.insertAdjacentElement('afterend', bar);

    /* ── banda de estado: solo se ve en firma o firmado (CSS, por
          html[data-lw-estado], que pone pintaAcciones) ─────────────────── */
    var banda = document.createElement('div');
    banda.className = 'lw4-banda'; banda.id = 'lw4Banda';
    var txt = document.createElement('div'); txt.className = 'lw4-banda-txt';
    ['lockBadge', 'firmaBadge'].forEach(function (id) { var b = $(id); if (b) txt.appendChild(b); });
    var acc = document.createElement('div'); acc.className = 'lw4-banda-acc';
    ['btnEditarFirmado', 'btnDesbloquear'].forEach(function (id) { var b = $(id); if (b) acc.appendChild(b); });
    banda.appendChild(txt); banda.appendChild(acc);
    bar.insertAdjacentElement('afterend', banda);

    /* ── taller del documento, encima de la vista previa ─────────────────── */
    var cab = document.createElement('div'); cab.className = 'lw4-pane-cab';
    var taller = grupo('Taller del documento', ['btnEdit', 'btnDesign', 'btnEditReset'], 'lw4-taller');
    cab.appendChild(taller);
    if (cierre) cab.appendChild(cierre);
    pane.insertBefore(cab, pane.firstChild);

    // los grupos viejos se quedaron vacíos (sus botones ya están en su sitio nuevo)
    viejos.forEach(function (g) { if (!g.querySelector('button, a')) g.remove(); });
    var titulo = $('pvTitle'); if (titulo) titulo.hidden = true;

    Object.keys(ICONOS).forEach(iconiza);
    // los avisos de la banda llevan el mismo glifo delante (🔒, ✍︎): fuera también
    ['lockBadge', 'firmaBadge'].forEach(function (id) {
      var b = $(id); if (!b) return;
      limpia(b);
      new MutationObserver(function () { limpia(b); }).observe(b, { childList: true, characterData: true, subtree: true });
    });
    pintaEstado();
    new MutationObserver(pintaEstado).observe(html, { attributes: true, attributeFilter: ['data-lw-estado'] });
    // el taller es de admin: si el motor oculta sus botones por rol, se va entero
    var edit = $('btnEdit');
    var ajustaTaller = function () { taller.hidden = !edit || edit.style.display === 'none'; };
    if (edit) new MutationObserver(ajustaTaller).observe(edit, { attributes: true, attributeFilter: ['style'] });
    ajustaTaller();
  }

  var ESTADOS = { nuevo: 'Sin guardar', borrador: 'Borrador', firma: 'En firma', firmado: 'Firmado' };
  function pintaEstado() {
    var e = $('lw4Estado'); if (!e) return;
    var k = html.getAttribute('data-lw-estado') || 'nuevo';
    e.textContent = T(ESTADOS[k] || ESTADOS.nuevo);
    e.setAttribute('data-estado', k);
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', monta); else monta();
})();
