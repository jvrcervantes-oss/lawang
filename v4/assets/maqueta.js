/* maqueta.js — capa de interactividad de la MAQUETA v4 (3-sep-2026).
 *
 * Las pantallas de Stitch son estáticas: la mayoría de botones no hace nada.
 * Esta capa, compartida por las 16 pantallas de equipo, hace que TODO responda:
 *  - CTAs de navegación van a su herramienta (Nuevo contrato → generador…)
 *  - Acciones de crear/editar abren un formulario en modal y "guardan" con aviso
 *  - Descargas/exports enseñan el aviso de maqueta
 *  - Chips de filtro y pestañas conmutan su estado activo
 *  - El botón de plegar la sidebar pliega de verdad, y en <1024px la sidebar
 *    pasa a cajón off-canvas con hamburguesa (responsive)
 * Nada escribe datos: es una maqueta. Un botón con onclick propio de Stitch
 * conserva su comportamiento (no se pisa). */
(function () {
  'use strict';
  var self = document.currentScript || document.querySelector('script[src*="maqueta.js"]');
  var ROOT = self ? self.src.replace(/assets\/maqueta\.js.*$/, '') : '../';

  /* ---------- utilidades ---------- */
  // El texto de un botón de Stitch lleva pegada la ligadura del icono ("addNuevo documento"):
  // el texto real se calcula clonando el nodo SIN los spans de Material Symbols.
  function texto(el) {
    var c = el.cloneNode(true);
    var ic = c.querySelectorAll('[class*="material-symbols"]');
    for (var i = ic.length - 1; i >= 0; i--) ic[i].parentNode.removeChild(ic[i]);
    return (c.textContent || '').replace(/\s+/g, ' ').trim();
  }
  function iconos(el) {
    var ic = el.querySelectorAll('[class*="material-symbols"]'); var out = [];
    for (var i = 0; i < ic.length; i++) out.push((ic[i].textContent || '').trim());
    return out.join(' ');
  }
  function sinIcono(t) { return t; }

  var toastT;
  function toast(msg, ok) {
    var d = document.getElementById('lw-toast');
    if (!d) {
      d = document.createElement('div'); d.id = 'lw-toast'; d.setAttribute('role', 'status');
      document.body.appendChild(d);
    }
    d.textContent = msg; d.className = ok ? 'ok' : ''; d.style.display = 'block';
    clearTimeout(toastT); toastT = setTimeout(function () { d.style.display = 'none'; }, 3200);
  }

  function cerrarModal() { var m = document.getElementById('lw-modal'); if (m) m.remove(); }

  function modal(titulo, cuerpoHTML, accion, alGuardar) {
    cerrarModal();
    var w = document.createElement('div'); w.id = 'lw-modal';
    w.innerHTML =
      '<div class="lw-modal-fondo"></div>' +
      '<div class="lw-modal-caja" role="dialog" aria-modal="true">' +
        '<p class="lw-modal-titulo">' + titulo + '</p>' +
        '<div class="lw-modal-cuerpo">' + cuerpoHTML + '</div>' +
        '<div class="lw-modal-pie">' +
          '<button type="button" class="lw-btn-sec" data-mq="cerrar">Cancelar</button>' +
          '<button type="button" class="lw-btn-pri" data-mq="guardar">' + (accion || 'Guardar') + '</button>' +
        '</div>' +
        '<p class="lw-modal-nota">Maqueta — no se guarda ningún dato real.</p>' +
      '</div>';
    document.body.appendChild(w);
    w.querySelector('.lw-modal-fondo').addEventListener('click', cerrarModal);
    w.querySelector('[data-mq="cerrar"]').addEventListener('click', cerrarModal);
    w.querySelector('[data-mq="guardar"]').addEventListener('click', function () {
      cerrarModal(); (alGuardar || function () { toast('✓ Guardado (maqueta) — sin datos reales', true); })();
    });
    var inp = w.querySelector('input, select, textarea'); if (inp) inp.focus();
  }

  function campo(label, tipo, ph) {
    return '<label class="lw-campo"><span>' + label + '</span>' +
      (tipo === 'select'
        ? '<select><option>Horizon S1</option><option>Sumba Hills</option><option>Bonian Village</option><option>Palm Field</option><option>Aura Village</option></select>'
        : tipo === 'area' ? '<textarea rows="2" placeholder="' + (ph || '') + '"></textarea>'
        : '<input type="' + tipo + '" placeholder="' + (ph || '') + '">') + '</label>';
  }
  var FORM_BASICO = campo('Referencia', 'text', 'p. ej. REF-2026-001') + campo('Proyecto', 'select') + campo('Notas', 'area', 'Opcional');
  var FORM_DINERO = campo('Referencia', 'text', 'p. ej. INV-2026-120') + campo('Proyecto', 'select') + campo('Importe (€)', 'text', '25.000') + campo('Fecha', 'date');
  var FORM_PERSONA = campo('Nombre completo', 'text', 'Nombre y apellidos') + campo('Email', 'email', 'nombre@ejemplo.com') + campo('Proyecto', 'select');

  /* ---------- tabla de rutas para CTAs de navegación ---------- */
  var aqui = location.pathname;
  function en(carpeta) { return aqui.indexOf('/' + carpeta + '/') !== -1; }
  var NAVEGAN = [
    [/nuevo contrato/i, 'generador-contratos'],
    [/emitir factura|nueva factura/i, 'facturas'],
    [/calendario de tesorer/i, 'vencimientos'],
    [/registro de firmas/i, 'contratos'],
    [/registro de auditor/i, 'operaciones']
  ];

  /* Con datos reales (cableado 4-sep-2026), crear/editar NO abre el modal de
     maqueta: abre el formulario de la herramienta VIVA — Regla 0 bis de la
     suite, y encargo literal del owner («usa los mismos formularios que
     tenemos en la versión estándar»). Rutas absolutas: las herramientas viven
     en el dominio real, no dentro de v4/. */
  var FORM_REAL = [
    [/nuevo contrato|nueva operaci/i, '/contracts/app.html'],
    [/nueva factura|nuevo documento|emitir factura/i, '/intranet/facturas/?tipo=factura'],
    [/emitir recib/i, '/intranet/facturas/?tipo=recibi'],
    [/alta de comprador/i, '/intranet/compradores/?nuevo=1'],
    [/nueva unidad|nuevo proyecto|importar csv/i, '/intranet/proyectos/'],
    [/registrar hito/i, '/intranet/vencimientos/'],
    [/registrar avance|firmar peritaje/i, '/intranet/obra/'],
    [/nuevo ticket/i, '/intranet/soporte/'],
    [/invitar miembro|editar permisos/i, '/intranet/usuarios/'],
    [/nueva creatividad|dossier$/i, '/intranet/creatividades/'],
    [/subir nuevo expediente/i, '/intranet/documentacion/'],
    [/añadir adquirente|editar texto|copiar datos/i, '/contracts/app.html']
  ];
  function conDatosReales() { return document.body.getAttribute('data-datos') === 'reales'; }

  /* ---------- clasificación de la acción de un botón ---------- */
  function maneja(btn) {
    var t = texto(btn); var ico = iconos(btn); var tl = t.toLowerCase();
    if (!t) t = btn.getAttribute('title') || btn.getAttribute('aria-label') || '';

    // 1) plegar sidebar (en móvil, el mismo botón cierra el cajón)
    if (/left_panel_close|left_panel_open/.test(ico)) {
      if (window.innerWidth < 1024) document.body.classList.remove('v4-nav-abierta');
      else document.body.classList.toggle('v4-nav-plegada');
      return true;
    }
    // 2) con datos reales: crear/editar abre el formulario de la herramienta VIVA
    if (conDatosReales()) {
      for (var k = 0; k < FORM_REAL.length; k++) {
        if (FORM_REAL[k][0].test(tl)) { location.href = FORM_REAL[k][1]; return true; }
      }
    }
    // 2b) navegación interna de la maqueta
    for (var i = 0; i < NAVEGAN.length; i++) {
      if (NAVEGAN[i][0].test(tl) && !en(NAVEGAN[i][1])) { location.href = ROOT + NAVEGAN[i][1] + '/'; return true; }
    }
    // 3) descargas / exports / envíos
    if (/descarg|export|\.zip|pdf$|enviar por email|^email$|csv/i.test(tl) || /picture_as_pdf|download|^send$/.test(ico)) {
      toast('Generando… (maqueta: no se emite ningún fichero ni correo real)'); return true;
    }
    // 4) crear / registrar / editar → modal con formulario
    if (/^(\+ )?(nuev[oa]|alta|emitir|registrar|invitar|subir|añadir|importar|crear)/i.test(tl)) {
      var f = /factur|recib|hito|importe|proforma/i.test(tl) ? FORM_DINERO
            : /comprador|miembro|usuario|invitar/i.test(tl) ? FORM_PERSONA : FORM_BASICO;
      modal(t, f, 'Guardar'); return true;
    }
    if (/^(editar|reasignar|actualizar|traer los conceptos|corregir)/i.test(tl)) { modal(t, FORM_BASICO, 'Aplicar'); return true; }
    if (/^(firmar|verificar|conciliar|ejecutar|reactivar|aprobar|validar)/i.test(tl)) {
      modal(t, '<p class="lw-modal-p">Esta acción quedará registrada en la auditoría de la herramienta.</p>', 'Confirmar'); return true;
    }
    if (/^(eliminar|borrar|anular)/i.test(tl) || (/(^| )delete( |$)/.test(ico) && !t)) {
      modal(t || 'Eliminar', '<p class="lw-modal-p">¿Seguro? En la app real esto pide confirmación y deja rastro.</p>', 'Eliminar'); return true;
    }
    if (/contactar|plantillas de respuesta|revisión de marca|filtros?( avanzados)?$|^filtrar|^filtro/i.test(tl) || (/(^| )tune( |$)/.test(ico) && !t)) {
      toast('«' + (t || 'Filtros') + '» — disponible en la fase de cableado'); return true;
    }
    if (/(^| )search( |$)/.test(ico) && !t) { toast('Búsqueda global — disponible en la fase de cableado'); return true; }
    if (/more_vert|open_in_new|visibility|chevron_right|arrow_forward|^edit$/.test(ico) && !t) {
      toast('Vista de detalle — disponible en la fase de cableado'); return true;
    }
    return false;
  }

  /* ---------- chips de filtro / pestañas: conmutar activo ---------- */
  function conmutaChip(btn) {
    var padre = btn.parentElement; if (!padre) return false;
    var hermanos = Array.prototype.filter.call(padre.children, function (x) { return x.tagName === 'BUTTON'; });
    if (hermanos.length < 2 || hermanos.indexOf(btn) === -1) return false;
    var clases = {}; hermanos.forEach(function (h) { clases[h.className] = (clases[h.className] || 0) + 1; });
    var comun = null, distinto = null;
    hermanos.forEach(function (h) { if (clases[h.className] === 1 && hermanos.length > 2) distinto = h; else comun = h.className; });
    if (!distinto || distinto === btn || comun === null) return false;
    var activo = distinto.className; distinto.className = comun; btn.className = activo;
    return true;
  }

  /* ---------- delegación global ---------- */
  document.addEventListener('click', function (ev) {
    var btn = ev.target.closest && ev.target.closest('button');
    if (btn) {
      if (btn.closest('#lw-modal')) return;             // el modal gestiona los suyos
      if (btn.hasAttribute('onclick')) return;          // comportamiento propio de Stitch
      if (btn.hasAttribute('data-real')) return;        // cableado por datos.js: no se toca
      // Sobre datos reales un chip que "se enciende" sin filtrar MIENTE: solo
      // conmutan los chips en pantallas aún de maqueta, o los que datos.js
      // haya cableado de verdad (data-real, rama de arriba).
      if (!conDatosReales() && conmutaChip(btn)) return;
      if (maneja(btn)) { ev.preventDefault(); return; }
      toast('«' + (sinIcono(texto(btn)) || 'Acción') + '» — disponible en la fase de cableado');
      return;
    }
    var a = ev.target.closest && ev.target.closest('a[href="#"]');
    if (a && !a.closest('aside') && !a.closest('#lw-maqueta')) {
      var t = sinIcono(texto(a));
      if (t) toast('«' + t + '» — disponible en la fase de cableado');
    }
  });
  document.addEventListener('keydown', function (ev) { if (ev.key === 'Escape') cerrarModal(); });

  /* ---------- responsive: etiquetar cáscara + hamburguesa ---------- */
  function prepara() {
    var asides = document.querySelectorAll('aside');
    for (var i = 0; i < asides.length; i++) {
      if (asides[i].textContent.indexOf('Cerrar Sesi') !== -1) { asides[i].classList.add('lw-aside'); break; }
    }
    var hdrs = document.querySelectorAll('header');
    for (var j = 0; j < hdrs.length; j++) {
      if (/search|notifications/.test(hdrs[j].innerHTML)) {
        hdrs[j].classList.add('lw-topbar');
        var izq = hdrs[j].firstElementChild;
        if (izq && !izq.querySelector('.lw-burger')) {
          var b = document.createElement('button');
          b.type = 'button'; b.className = 'lw-burger'; b.setAttribute('aria-label', 'Menú');
          b.innerHTML = '<span class="material-symbols-outlined">menu</span>';
          b.addEventListener('click', function (ev) { ev.stopPropagation(); document.body.classList.toggle('v4-nav-abierta'); });
          izq.insertBefore(b, izq.firstChild);
        }
        break;
      }
    }
    var velo = document.createElement('div'); velo.className = 'lw-velo';
    velo.addEventListener('click', function () { document.body.classList.remove('v4-nav-abierta'); });
    document.body.appendChild(velo);
    // navegar desde el cajón móvil lo cierra
    document.addEventListener('click', function (ev) {
      if (ev.target.closest && ev.target.closest('.lw-aside a')) document.body.classList.remove('v4-nav-abierta');
    });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', prepara); else prepara();
})();
