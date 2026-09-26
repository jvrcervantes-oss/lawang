/* motion.js — la ENTRADA de cada pantalla de la v4 (26-sep-2026, owner).
 *
 * El owner eligió la mezcla A+B+D sobre un ensayo con las entradas del menú
 * (artifact «Lawang v4 · Movimiento»):
 *   A · Sereno  — por defecto: los bloques suben 10 px y aparecen en cascada.
 *   B · Plano   — la PRIMERA entrada de la sesión en Home, Proyectos y Modelos:
 *                 los bloques se destapan con una máscara. Después, A.
 *   D · Directo — lo que es dinero y configuración: un fundido corto y nada más.
 * El CRM (/intranet/leads/) queda fuera: es una vertical con diseño propio.
 *
 * CÓMO ENGANCHA. La v4 nace oculta por CSS hasta `body.lw-listo` (datos.js, al
 * volver las consultas). nav.js marca `html.lw-mov` en cuanto corre —antes de
 * que vuelva ninguna consulta— y con esa marca shell.css retiene `main` un poco
 * más tras `lw-listo`, hasta que este fichero toma el control y la retira. Así
 * la entrada sale SIEMPRE, llegue este fichero antes o después que los datos
 * (revisión previa de Desarrollo y Diseño, 26-sep).
 *
 * QUÉ NO PUEDE PASAR, y cómo se evita:
 * · Que algo se quede oculto. Si este fichero no llega, shell.css suelta `main`
 *   a los 600 ms de `lw-listo` (lw-mov-rescate). Las animaciones no dejan estado
 *   (sin `fill`, salvo `backwards` mientras esperan turno): al acabar manda el CSS.
 * · Que algo ya visible parpadee. Sin la marca `lw-mov` (la página ya estaba
 *   destapada cuando corrió nav.js) no se anima; tampoco tras el rescate de 12 s.
 * · Que una cifra quede mal: ver `cuenta()`.
 * · Que el velo de carga se coma la entrada: se retira sin fundido al empezarla
 *   (clase `lw-mov-entra`, la regla vive en shell.css junto al velo).
 * · Molestar a quien pidió menos movimiento: nav.js ni siquiera marca.
 *
 * Solo toca hijos de `main`. Nunca `body` ni sus hijos directos: ahí viven la
 * cortina, el velo y los avisos.
 *
 * nav.js lo carga como a cortina.js, con MOTION_V = los 8 primeros del sha1 de
 * este fichero; nav.test.js falla si no casan. */
(function () {
  'use strict';
  if (window.LW_MOTION) return;
  var R = window.LW_MOTION = { perfil: null, estado: 'esperando', piezas: 0, filas: 0, cifras: 0 };
  var html = document.documentElement;
  function suelta() { html.classList.remove('lw-mov'); }
  if (!Element.prototype.animate) { R.estado = 'sin-waapi'; suelta(); return; }
  /* Sin marca: la pantalla ya estaba destapada cuando corrió nav.js. Son las que
     no esperan a datos.js y pintan con su propio script (Finanzas, Gastos,
     Bancos, Comunicados, Asistente): se va al modo tardío, más abajo. */
  var tarde = !html.classList.contains('lw-mov');

  var seg = location.pathname.replace(/\/(index\.html)?$/, '').split('/').pop();
  var PRIMERA_B = { home: 1, proyectos: 1, modelos: 1 };
  var DIRECTO = { finanzas: 1, vencimientos: 1, facturas: 1, recibos: 1, comisiones: 1, reparto: 1, condiciones: 1,
    'equipos-venta': 1, gastos: 1, bancos: 1, cuentas: 1, sociedades: 1, ajustes: 1, 'comision-admin': 1 };
  var CLAVE = 'lw-mov-vistas';
  function vistas() { try { return JSON.parse(sessionStorage.getItem(CLAVE) || '[]'); } catch (e) { return []; } }
  var perfil = DIRECTO[seg] ? 'D' : (PRIMERA_B[seg] && vistas().indexOf(seg) === -1 ? 'B' : 'A');
  R.perfil = perfil;

  function css(v, f) { try { return getComputedStyle(html).getPropertyValue(v).trim() || f; } catch (e) { return f; } }
  var EASE = css('--lw-ease', 'cubic-bezier(.23,1,.32,1)');
  var SUBE = function () { return [{ opacity: 0, transform: 'translateY(10px)' }, { opacity: 1, transform: 'none' }]; };
  var P = {
    A: { ease: EASE, dur: 420, paso: 45, f: SUBE },
    /* Margen negativo en la máscara: con inset 0 se cortaba la sombra de las tarjetas. */
    B: { ease: 'cubic-bezier(.65,0,.35,1)', dur: 546, paso: 70,
      f: function () { return [{ clipPath: 'inset(-14px -14px 100% -14px)', transform: 'translateY(6px)' }, { clipPath: 'inset(-14px -14px -14px -14px)', transform: 'none' }]; } },
    D: { ease: 'cubic-bezier(0,0,.58,1)', dur: 190, paso: 0, f: function () { return [{ opacity: 0 }, { opacity: 1 }]; } }
  }[perfil];

  function anima(el, frames, dur, delay, ease) {
    try { return el.animate(frames, { duration: dur, delay: delay || 0, easing: ease || P.ease, fill: delay ? 'backwards' : 'none' }); }
    catch (e) { return null; }
  }
  var VH = window.innerHeight || 800;
  function caja(el) { return el.getBoundingClientRect(); }
  function cuenta_pieza(el) {                          // ¿merece la pena animarlo?
    if (el.hidden || el.offsetHeight === 0) return false;
    var r = caja(el);
    if (r.width === 0 || r.top >= VH || r.bottom <= 0) return false;
    var p = getComputedStyle(el).position;
    if (p === 'fixed' || p === 'sticky') return false;
    /* Un transform en un antepasado recoloca a un `fixed` de dentro (la vista
       previa de /comunicacion/): ese bloque no se mueve. */
    if (el.querySelector('.fixed, [style*="position:fixed"], [style*="position: fixed"]')) return false;
    return true;
  }
  /* Las piezas: los hijos de la columna de la cabecera. Una rejilla, o un bloque
     de más del 60 % de la pantalla, se baja a sus hijos (dos niveles como mucho):
     si no, Home entraba como UN bloque de 1500 px y Proyectos como una sola rejilla.
     Nunca se animan a la vez un contenedor y sus hijos. */
  function recoge(el, nivel, out) {
    Array.prototype.forEach.call(el.children, function (h) {
      if (!cuenta_pieza(h)) return;
      var rejilla = getComputedStyle(h).display === 'grid' && h.children.length >= 2;
      var alto = caja(h).height > VH * 0.6;
      if (nivel < 2 && (rejilla || alto) && h.children.length && h.tagName !== 'TABLE' && !h.classList.contains('lw-cabecera')) {
        var antes = out.length;
        recoge(h, nivel + 1, out);
        if (out.length > antes) return;
      }
      out.push(h);
    });
    return out;
  }

  /* Una cifra de KPI tal como la escribe la suite: miles con punto y decimales con
     coma SIEMPRE (dinero.js formatea en de-DE en los dos idiomas), con lo que lleve
     delante o detrás («412.800,00 EUR», «38», «61%»). Si no casa exacto, no se cuenta:
     una cifra mal leída es peor que una que no se mueve. */
  var NUM = /^(\D*?)(\d{1,3}(?:\.\d{3})+|\d+)(,\d+)?(\D*)$/;
  function cuenta(el, delay) {
    var orig = el.textContent, m = NUM.exec(orig.trim());
    if (!m) return false;
    var fin = parseInt(m[2].replace(/\./g, ''), 10);
    if (!(fin > 0)) return false;
    var dec = m[3] ? m[3].length - 1 : 0, mil = m[2].indexOf('.') !== -1;
    var fmt = function (v) {
      var t = mil ? Math.round(v).toLocaleString('de-DE') : String(Math.round(v));
      return m[1] + t + (dec ? ',' + new Array(dec + 1).join('0') : '') + m[4];
    };
    var tab = el.style.fontVariantNumeric;
    el.style.fontVariantNumeric = 'tabular-nums';       // que el ancho no baile mientras cuenta
    var dur = 900, t0 = performance.now() + delay, escrito = fmt(0);
    el.textContent = escrito;
    function tick(now) {
      /* Otra escritura (una consulta que llega tarde) manda: se retira SIN reponer
         nada, que taparía el dato nuevo. Solo se repone si sigue lo nuestro. */
      if (el.textContent !== escrito) { el.style.fontVariantNumeric = tab; return; }
      var p = Math.min(1, Math.max(0, (now - t0) / dur));
      if (p >= 1) { el.textContent = orig; el.style.fontVariantNumeric = tab; return; }   // el texto EXACTO de antes
      escrito = fmt(fin * (1 - Math.pow(1 - p, 5)));
      el.textContent = escrito;
      requestAnimationFrame(tick);
    }
    requestAnimationFrame(tick);
    return true;
  }

  function entra() {
    var main = document.querySelector('main');
    if (!main) { R.estado = 'sin-main'; return; }
    if (html.classList.contains('lw-tapada')) { R.estado = 'tapada'; return; }   // cortina de privacidad
    var cab = main.querySelector('.lw-cabecera');
    var col = cab ? cab.parentElement : main;
    html.classList.add('lw-mov-entra');                 // fuera el velo, sin fundido: si no, se come la entrada

    if (perfil === 'D') { anima(col, P.f(), P.dur); R.piezas = 1; R.estado = 'hecho'; return; }

    var piezas = recoge(col, 0, []);
    // Filas de rejilla (parcelas, tarjetas): el orden de lectura, fila a fila.
    var fila = {}, filas = 0;
    piezas.forEach(function (el, i) {
      var r = caja(el), k = Math.round(r.top / 8);
      if (!(k in fila)) fila[k] = filas++;
      var f = P.f(), dur = P.dur;
      if (perfil === 'B' && r.height > VH) { f = SUBE(); dur = 420; }   // un destape de 1500 px sale de golpe, no plano
      var delay = perfil === 'B' ? 60 + fila[k] * P.paso + Math.min(r.left / 40, 12) * 6 : 60 + Math.min(i, 8) * P.paso;
      anima(el, f, dur, delay, perfil === 'B' && dur === 420 ? EASE : null);
    });
    R.piezas = piezas.length;

    /* Filas de tabla a la vista: solo opacidad. Un translate en filas de una tabla
       border-collapse deja las líneas quietas mientras el texto se mueve. */
    var trs = Array.prototype.filter.call(main.querySelectorAll('tbody tr'), function (tr) {
      var r = caja(tr); return r.height > 0 && r.top < VH && r.bottom > 0;
    }).slice(0, 9);
    trs.forEach(function (tr, i) { anima(tr, [{ opacity: 0 }, { opacity: 1 }], 320, 300 + i * 40, EASE); });
    R.filas = trs.length;

    // Solo la cifra principal de cada KPI: el pie, el subtítulo y la tendencia no cuentan.
    Array.prototype.forEach.call(main.querySelectorAll('[data-lw^="k-"]'), function (el) {
      var k = el.getAttribute('data-lw');
      if (/-(pie|sub|tend)$/.test(k)) return;
      var r = caja(el);
      if (r.height === 0 || r.top >= VH) return;
      if (cuenta(el, 180 + R.cifras * 70)) R.cifras++;
    });
    if (perfil === 'B') {
      try { var v = vistas(); v.push(seg); sessionStorage.setItem(CLAVE, JSON.stringify(v)); } catch (e) {}
    }
    R.estado = 'hecho';
  }

  /* MODO TARDÍO. Lo ya pintado no se toca. Se espera al primer lote de
     contenido que el script de la pantalla meta en `main` y se anima ESE lote:
     un MutationObserver corre antes del siguiente pintado, así que lo nuevo nace
     ya animándose, sin destello. Un lote de menos de 60 px (un «Cargando…») no
     cuenta. Un solo disparo, y a los 6 s se deja de esperar. */
  function tardio() {
    var main = document.querySelector('main');
    if (!main) { R.estado = 'sin-main'; return; }
    R.modo = 'tardio';
    var mo = new MutationObserver(function (muts) {
      var nuevos = [];
      muts.forEach(function (m) { Array.prototype.forEach.call(m.addedNodes, function (n) { if (n.nodeType === 1 && n.isConnected) nuevos.push(n); }); });
      nuevos = nuevos.filter(function (n) { return !nuevos.some(function (o) { return o !== n && o.contains(n); }); });
      var piezas = [];
      nuevos.forEach(function (n) {
        if (!cuenta_pieza(n)) return;
        var grande = caja(n).height > VH * 0.6 || (getComputedStyle(n).display === 'grid' && n.children.length >= 2);
        var dentro = grande ? recoge(n, 1, []) : [];
        if (dentro.length) piezas.push.apply(piezas, dentro); else piezas.push(n);
      });
      var alto = piezas.reduce(function (t, el) { return t + caja(el).height; }, 0);
      if (alto < 60) return;
      mo.disconnect();
      try {
        piezas.slice(0, 12).forEach(function (el, i) { anima(el, P.f(), P.dur, perfil === 'D' ? 0 : 40 + Math.min(i, 8) * P.paso); });
        R.piezas = Math.min(piezas.length, 12); R.estado = 'hecho';
      } catch (e) { R.estado = 'fallo: ' + e.message; }
    });
    mo.observe(main, { childList: true, subtree: true });
    setTimeout(function () { mo.disconnect(); if (R.estado === 'esperando') R.estado = 'sin-lote'; }, 6000);
  }

  function listo() { return document.body && document.body.classList.contains('lw-listo'); }
  function ahora() {
    /* A los 12 s el CSS destapa `main` solo (lw-rescate): lo de dentro ya se
       estaba viendo, no se toca. */
    if (performance.now() > 11500) { R.estado = 'tras-rescate'; suelta(); return; }
    try { entra(); } catch (e) { R.estado = 'fallo: ' + e.message; }
    suelta();                                           // en el mismo frame que las animaciones: sin destello
  }
  function arranca() {
    if (tarde) return tardio();
    if (listo()) return ahora();
    var mo = new MutationObserver(function () {
      if (!listo()) return;
      mo.disconnect();                                  // un solo disparo: maqueta.js también cambia clases de body
      ahora();
    });
    mo.observe(document.body, { attributes: true, attributeFilter: ['class'] });
  }
  if (document.body) arranca(); else document.addEventListener('DOMContentLoaded', arranca);
})();
