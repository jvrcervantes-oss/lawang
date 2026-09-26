/* ═══════════════════════════════════════════════════════════════════════════
   motion-generador.js — ENSAYO del movimiento de la cara v4 del generador
   (26-sep-2026). Solo lo carga contracts/appv2.html; app.html no se entera.
   ═══════════════════════════════════════════════════════════════════════════
   El owner quiere verlo en vivo antes de decidir (boceto:
   https://claude.ai/artifact/RvXVUEvhMto3vaNMyyYKqd). Por eso esto NO toca el
   motor: escucha lo que el motor ya escribe y anima encima.
     · html[data-lw-estado]  — pintaAcciones(): nuevo|borrador|firma|firmado
     · .lw4-tb[disabled]     — pintaAcciones(): encendido/apagado
     · #pvFrame srcdoc       — render(): la vista previa se reconstruye entera
     · .stage style.display  — init(): el editor se destapa
   Lenguaje: perfil A · Sereno de intranet/v4/assets/motion.js (curva
   cubic-bezier(.23,1,.32,1), sube 10 px, 45 ms entre hermanos).
   Las animaciones no dejan estado (sin fill, salvo `backwards` en espera): al
   acabar manda el CSS de siempre. Sin WAAPI, sin v4 o con menos movimiento
   pedido, no hace nada.                                                      */
(function () {
  'use strict';
  var html = document.documentElement;
  if (!html.classList.contains('v4')) return;
  if (!Element.prototype.animate) return;
  if (window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  var R = window.LW_MOTION_GEN = { entrada: false, gestos: [] };
  var EASE = 'cubic-bezier(.23,1,.32,1)';
  var $ = function (s) { return document.querySelector(s); };
  var $$ = function (s) { return Array.prototype.slice.call(document.querySelectorAll(s)); };
  function anima(el, frames, dur, delay) {
    try { return el.animate(frames, { duration: dur, delay: delay || 0, easing: EASE, fill: delay ? 'backwards' : 'none' }); }
    catch (e) { return null; }
  }
  function apunta(g) { R.gestos.push(g + ' @' + Math.round(performance.now())); if (R.gestos.length > 40) R.gestos.shift(); }
  function visible(el) {
    if (!el || el.offsetParent === null) return false;
    var r = el.getBoundingClientRect();
    return r.height > 0 && r.top < (window.innerHeight || 800) && r.bottom > 0;
  }
  var listo = false;          // hasta la entrada, los cambios de estado son la carga, no un gesto

  /* ── 1. Entrada: el editor se destapa (A · Sereno) ───────────────────── */
  function entrada() {
    if (R.entrada) return;
    R.entrada = true;
    var piezas = [];
    var barra = $('.lw4-barra'); if (visible(barra)) piezas.push(barra);
    $$('.pane-form form > *').forEach(function (el) { if (visible(el) && piezas.length < 9) piezas.push(el); });
    ['.lw4-pane-cab', '.pv-scroll'].forEach(function (s) { var el = $(s); if (visible(el)) piezas.push(el); });
    piezas.forEach(function (el, i) {
      anima(el, [{ opacity: 0, transform: 'translateY(10px)' }, { opacity: 1, transform: 'none' }], 420, 60 + Math.min(i, 8) * 45);
    });
    apunta('entrada ' + piezas.length);
    setTimeout(function () { listo = true; }, 700);
  }
  function vigilaStage() {
    var st = $('.stage');
    if (!st) return;
    if (st.style.display !== 'none') { requestAnimationFrame(entrada); return; }
    var mo = new MutationObserver(function () {
      if (st.style.display === 'none') return;
      mo.disconnect();
      requestAnimationFrame(entrada);   // el mismo frame en que se destapa: sin destello
    });
    mo.observe(st, { attributes: true, attributeFilter: ['style'] });
    setTimeout(function () { mo.disconnect(); listo = true; }, 15000);
  }

  /* ── 2. El dato llega al documento ───────────────────────────────────── */
  var ultimo = null;
  function vigilaPreview() {
    var form = $('#form'), fr = $('#pvFrame');
    if (!form || !fr) return;
    form.addEventListener('input', function (e) {
      var n = e.target && e.target.name;
      if (n) ultimo = { k: n, t: Date.now() };
    });
    fr.addEventListener('load', function () {
      if (!ultimo || Date.now() - ultimo.t > 2500) return;
      var k = ultimo.k; ultimo = null;
      var d = fr.contentDocument; if (!d) return;
      var els = d.querySelectorAll('[data-campo="' + (window.CSS && CSS.escape ? CSS.escape(k) : k) + '"]');
      Array.prototype.forEach.call(els, function (el) {
        try {
          el.animate([{ backgroundColor: 'rgba(16,76,79,.16)' }, { backgroundColor: 'rgba(16,76,79,0)' }],
            { duration: 900, easing: EASE });
        } catch (e) {}
      });
      if (els.length) apunta('dato ' + k);
    });
  }

  /* ── 3. Herramientas que se encienden: cascada de 45 ms en orden de lectura ─ */
  var cola = [], colaT = null;
  function encendido(b) {
    cola.push(b);
    clearTimeout(colaT);
    colaT = setTimeout(function () {
      var orden = $$('.lw4-tb').filter(function (x) { return cola.indexOf(x) !== -1 && visible(x); });
      cola = [];
      orden.forEach(function (x, i) {
        setTimeout(function () {
          x.classList.remove('lw4m-on'); void x.offsetWidth; x.classList.add('lw4m-on');
          setTimeout(function () { x.classList.remove('lw4m-on'); }, 950);
        }, i * 45);
      });
      if (orden.length) apunta('encienden ' + orden.length);
    }, 30);
  }
  function vigilaBotones() {
    $$('.lw4-tb, #btnSave').forEach(function (b) {
      var antes = b.disabled || b.getAttribute('aria-disabled') === 'true';
      new MutationObserver(function () {
        var ahora = b.disabled || b.getAttribute('aria-disabled') === 'true';
        if (antes && !ahora && listo) encendido(b);
        antes = ahora;
      }).observe(b, { attributes: true, attributeFilter: ['disabled', 'aria-disabled'] });
    });
  }

  /* ── 4. Cambio de estado: chip, banda, candados y la principal ───────── */
  var estado = html.getAttribute('data-lw-estado');
  function cambiaEstado() {
    var nuevo = html.getAttribute('data-lw-estado');
    if (nuevo === estado) return;
    var viejo = estado; estado = nuevo;
    if (!listo) return;
    apunta('estado ' + viejo + '→' + nuevo);

    var chip = $('#lw4Estado');
    if (chip) anima(chip, [{ opacity: 0, transform: 'translateY(10px)' }, { opacity: 1, transform: 'none' }], 420);

    var banda = $('#lw4Banda');
    var abre = (nuevo === 'firma' || nuevo === 'firmado') && !(viejo === 'firma' || viejo === 'firmado');
    if (banda && abre) {
      var h = banda.offsetHeight;
      if (h) {
        banda.style.overflow = 'hidden';
        var a = anima(banda, [{ height: '0px', paddingTop: '0px', paddingBottom: '0px', opacity: .4 }, { height: h + 'px', opacity: 1 }], 420);
        var fin = function () { banda.style.overflow = ''; };
        if (a) a.onfinish = a.oncancel = fin; else fin();
      }
    }
    if (nuevo === 'firma' || nuevo === 'firmado') {
      // cada campo a la vista se asienta en cascada al pasar a solo lectura
      var campos = $$('.pane-form .field input, .pane-form .field select, .pane-form .field textarea').filter(visible).slice(0, 14);
      campos.forEach(function (c, i) {
        anima(c, [{ boxShadow: '0 0 0 3px ' + (nuevo === 'firma' ? 'rgba(138,90,18,.22)' : 'rgba(16,76,79,.2)') }, { boxShadow: '0 0 0 0 rgba(0,0,0,0)' }], 520, 120 + i * 45);
      });
    }
    if (nuevo === 'firmado') {
      var sig = $('#btnDownloadSigned');
      if (visible(sig)) anima(sig, [{ opacity: 0, transform: 'translateY(10px)' }, { opacity: 1, transform: 'none' }], 420, 80);
    }
    if (viejo === 'nuevo' && nuevo === 'borrador') {
      var save = $('#btnSave');
      if (visible(save)) anima(save, [{ boxShadow: '0 0 0 0 rgba(16,76,79,.35)' }, { boxShadow: '0 0 0 8px rgba(16,76,79,0)' }], 600);
    }
  }

  function monta() {
    vigilaStage();
    vigilaPreview();
    // generador-v4.js recoloca los botones con `defer`, antes que este: ya existen
    vigilaBotones();
    new MutationObserver(cambiaEstado).observe(html, { attributes: true, attributeFilter: ['data-lw-estado'] });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', monta); else monta();
})();
