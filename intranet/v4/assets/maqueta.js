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

  /* El toast local se retira (14-sep-2026): las llamadas de abajo resuelven al
     `toast` compartido de `contracts/assets/suite-comun.js`, que es el que ya
     limpia el temporizador y se anuncia con aria-live. Aqui no hace falta
     adaptador —al reves que en editores.js— porque ninguna llamada de este
     fichero usaba el segundo argumento para nada... salvo una, y esa se corrige
     abajo: en la firma compartida el segundo argumento es la DURACION en ms, asi
     que el `true` que marcaba «exito» habria dado un aviso de cero milisegundos.
     El verde de «guardado» se pierde a proposito: la suite tiene un solo aviso
     neutro y `toastMal` para los fallos, y estrenar un tercero aqui seria volver
     a empezar. */

  /* ═══ LA VENTANA YA NO SE PINTA AQUI (14-sep-2026, encargo del owner) ═══
     Este fichero tenia su propio modal: la MISMA ventana que la de editores.js
     —fondo, cabecera, campos, pie— pero con radio 10 en vez de 14, botones
     rectos en vez de pastilla y sin saber ensenar un error. Dos ventanas para el
     mismo trabajo, ya separandose. Se queda la de editores.js, que valida y sabe
     fallar, y aqui solo queda COMO SE RELLENA.

     `campos` es la declaracion que espera aquella ventana, no HTML: `{k, label,
     tipo, ayuda, opciones}`. Lo que antes era una cadena con `<label>` dentro
     ahora se dice en datos, que es lo que permitia unificarlas.

     `sinRecarga` es lo unico que hubo que anadir a la pieza compartida: aquella
     recarga la pagina al guardar —correcto para un editor que acaba de escribir
     en la base— y estos formularios no guardan nada, asi que recargarian por
     haber pulsado un boton que no hace nada.

     Y `sub` dice en la propia ventana que no se guarda. Antes era una nota al
     pie; ahora va bajo el titulo, que es donde se lee antes de teclear. */
  var PROYECTOS = ['Horizon S1', 'Sumba Hills', 'Bonian Village', 'Palm Field', 'Aura Village'];

  function ventana(titulo, campos, accion, alGuardar) {
    /* Si la ventana compartida no esta en esta pantalla, no se inventa otra: se
       dice en un aviso. Una segunda implementacion «por si acaso» es justo la
       duplicacion que este cambio viene a quitar. */
    if (typeof window.lwVentana !== 'function') {
      toast('«' + titulo + '» — disponible en la fase de cableado');
      return;
    }
    window.lwVentana(titulo, campos, accion || 'Guardar', function () {
      (alGuardar || function () { toast('✓ Guardado (maqueta) — sin datos reales'); })();
    }, { sinRecarga: true, sub: 'Maqueta — no se guarda ningún dato real.' });
  }

  var FORM_BASICO = [
    { k: 'ref', label: 'Referencia', ayuda: 'p. ej. REF-2026-001' },
    { k: 'proyecto', label: 'Proyecto', tipo: 'select', opciones: PROYECTOS },
    { k: 'notas', label: 'Notas', tipo: 'textarea' }
  ];
  var FORM_DINERO = [
    { k: 'ref', label: 'Referencia', ayuda: 'p. ej. INV-2026-120' },
    { k: 'proyecto', label: 'Proyecto', tipo: 'select', opciones: PROYECTOS },
    { k: 'importe', label: 'Importe (EUR)', ayuda: 'p. ej. 25.000' },
    { k: 'fecha', label: 'Fecha', tipo: 'date' }
  ];
  var FORM_PERSONA = [
    { k: 'nombre', label: 'Nombre completo' },
    { k: 'email', label: 'Email', tipo: 'email' },
    { k: 'proyecto', label: 'Proyecto', tipo: 'select', opciones: PROYECTOS }
  ];
  /* Los dos que no eran formulario sino una frase: `nota` es el tipo que la
     ventana compartida ya trae para eso. */
  var NOTA_AUDITORIA = [{ tipo: 'nota', label: 'Esta accion quedara registrada en la auditoria de la herramienta.' }];
  var NOTA_BORRADO = [{ tipo: 'nota', label: 'En la app real esto pide confirmacion y deja rastro.' }];

  /* ---------- tabla de rutas para CTAs de navegación ---------- */
  var aqui = location.pathname;
  function en(carpeta) { return aqui.indexOf('/' + carpeta + '/') !== -1; }
  var NAVEGAN = [
    [/nuevo contrato/i, 'generador-contratos'],
    [/emitir factura|nueva factura/i, 'facturas'],
    [/calendario de tesorer/i, 'vencimientos'],
    [/registro de firmas/i, 'contratos']
    /* «Registro de auditoría» tenía aquí un resto de Stitch que la llevaba a
       Operaciones (que no habla de auditoría en absoluto). Desde el 21-sep
       el botón vive solo en usuarios/ y hace scroll a su propio panel «Auditoría
       Reciente» — cableado real en datos.js, data-real evita que llegue aquí. */
  ];

  /* Con datos reales (cableado 4-sep-2026), crear/editar NO abre el modal de
     maqueta: abre el formulario de la herramienta VIVA — Regla 0 bis de la
     suite, y encargo literal del owner («usa los mismos formularios que
     tenemos en la versión estándar»). Rutas absolutas: las herramientas viven
     en el dominio real, no dentro de v4/. */
  var FORM_REAL = [
    /* 19-sep-2026: sin `?nuevo=1` / `?nueva=1` las tres herramientas abren el
       LISTADO (app.html: `par.has('nuevo')`; facturas: `par.has('nueva')`) y el
       agente tenía que volver a pulsar «Nueva». Ahora aterrizan en el formulario. */
    [/nuevo contrato|nueva operaci/i, '/contracts/app.html?nuevo=1'],
    /* «Nuevo documento» (/v4/facturas/) y «+ Emitir recibí de cobro»
       (/v4/recibos/) YA NO redirigen a /intranet/facturas/ (21-sep-2026):
       editores.js los cablea con `ata()` — se ata en directo al botón con
       `stopPropagation`, así que este array ni se consulta para ellos. Se
       retiran las dos entradas del todo (no se dejan "por si acaso"): una
       redirección viva que sobreviviera a un fallo de `ata()` sería
       exactamente el escape silencioso a la herramienta vieja que este
       build vino a cerrar. */
    /* PODA (23-sep-2026, tras S16-S18): las otras once entradas que vivían
       aquí ya no tenían a quién redirigir — o su botón ya es nativo y
       editores.js lo ata con `stopPropagation` (Alta de comprador, Nueva
       unidad, Nuevo proyecto, Importar CSV, Registrar hito, Registrar avance,
       Nueva solicitud, Invitar/Editar permisos), o el botón ya no existe en
       ninguna pantalla (Nuevo ticket, Firmar peritaje, Nueva creatividad,
       Subir nuevo expediente, Añadir adquirente, Editar texto, Copiar datos).
       Mismo criterio que facturas/recibos arriba: una redirección que
       sobreviviera a un fallo del editor nativo sería la salida silenciosa a
       la herramienta vieja. Queda solo el generador de contratos, que SIGUE
       en la herramienta de siempre por decisión (encargo 19-sep). */
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
      ventana(t, f, 'Guardar'); return true;
    }
    if (/^(editar|reasignar|actualizar|traer los conceptos|corregir)/i.test(tl)) { ventana(t, FORM_BASICO, 'Aplicar'); return true; }
    if (/^(firmar|verificar|conciliar|ejecutar|reactivar|aprobar|validar)/i.test(tl)) {
      ventana(t, NOTA_AUDITORIA, 'Confirmar'); return true;
    }
    if (/^(eliminar|borrar|anular)/i.test(tl) || (/(^| )delete( |$)/.test(ico) && !t)) {
      ventana(t || 'Eliminar', NOTA_BORRADO, 'Eliminar'); return true;
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
      if (btn.closest('#lw-editor')) return;            // la ventana gestiona los suyos
      // y el diálogo de la suite (dialogo.js: lwConfirmar/lwElegir) también —
      // desde S17 todas las confirmaciones de la v4 van por él (23-sep-2026)
      if (btn.closest('.lw-dlg-fondo')) return;
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
  /* `cerrarModal` se fue con la ventana propia de este fichero (14-sep) y esta
     linea siguio llamandola: un ReferenceError en consola a cada Escape. El
     cajon de ficha y el editor gestionan su propia tecla. */
  document.addEventListener('keydown', function (ev) { if (ev.key === 'Escape' && typeof cerrarModal === 'function') cerrarModal(); });

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
