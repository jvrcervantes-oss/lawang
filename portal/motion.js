/* motion.js — el movimiento del portal de clientes (7-oct-2026, owner: «gran mejora, impleméntalo todo»).
 *
 * Es el mismo lenguaje que la entrada de pantalla de la intranet v4 (intranet/v4/assets/motion.js, elegido por el
 * owner el 26-sep: A «Sereno» por defecto, B «Plano» la primera vez que se abre Inicio en la sesión, D «Directo»
 * para el dinero) y la misma curva (--lw-ease). Lo que aquí se añade es propio de un panel de cliente: el indicador
 * del menú, abrir una carpeta de proyecto con la portada que crece, el pulso del paso actual, la campana y el cajón.
 *
 * QUÉ NO PUEDE PASAR (y cómo se evita):
 *  · Que algo se quede oculto o a medias. Nada usa `fill` salvo `backwards` mientras espera su turno: al acabar manda
 *    el CSS. Si este fichero no carga, el portal funciona igual, sin movimiento (el CSS no depende de él salvo la
 *    clase `lw-mov` que él mismo pone: sin la clase, el item activo del menú sigue con su fondo propio).
 *  · Que un importe quede mal. La cifra YA está escrita en el HTML; aquí solo se recorre desde 0 y siempre se
 *    restaura el valor exacto al terminar o si el nodo desaparece.
 *  · Que repinte lo que no cambió. `pantalla()` solo se llama cuando cambia la sección o la carpeta; un repintado por
 *    idioma o por recarga de datos no anima (lo decide index.html con la clave «sección|carpeta»).
 *  · Molestar a quien pidió menos movimiento: con `prefers-reduced-motion` o sin la API `animate`, no se hace nada.
 *  · Enganchar a un texto. Todo cuelga de clases e ids que no cambian (.proy-cab, .barra, .tl-paso, #nav…), nunca de
 *    un rótulo ni de una cabecera (norma del owner, 29-sep-2026).
 * Se prueba en node con motion.test.js (lo puro) y con el arnés de capturas (lo visual). */
(function (root) {
  'use strict';
  var EASE = 'cubic-bezier(.23,1,.32,1)';
  var CLAVE_VISTAS = 'lw-mov-vistas', CLAVE_CAMPANA = 'lw-mov-campana';

  /* ── lo puro: se prueba sin navegador ── */
  function perfil(seccion, vistas) {
    if (seccion === 'facturas') return 'D';                              // dinero: fundido corto y nada más
    if (seccion === 'inicio' && (vistas || []).indexOf('inicio') === -1) return 'B';   // la primera vez de la sesión
    return 'A';
  }
  function valorCuenta(fin, k) {                                          // k de 0 a 1, entra y se asienta
    if (!(k > 0)) return 0;
    if (k >= 1) return fin;
    return fin * (1 - Math.pow(1 - k, 3));
  }
  /* El FLIP solo vale si origen y destino tienen la MISMA forma (±5 %): con distinta proporción (la tarjeta horizontal
     del móvil frente a la cabecera 4:3) un escalado x/y distinto estiraría la imagen a mitad de vuelo. */
  function mismaForma(w1, h1, w2, h2) {
    if (!(w1 > 0 && h1 > 0 && w2 > 0 && h2 > 0)) return false;
    return Math.abs((w1 / h1) / (w2 / h2) - 1) <= 0.05;
  }
  function claveVista(seccion, carpeta) { return seccion + '|' + (seccion === 'documentos' ? (carpeta || '') : ''); }

  var PERF = {
    A: { dur: 420, paso: 45, ease: EASE, f: function () { return [{ opacity: 0, transform: 'translateY(10px)' }, { opacity: 1, transform: 'none' }]; } },
    B: { dur: 546, paso: 70, ease: 'cubic-bezier(.65,0,.35,1)', f: function () { return [{ clipPath: 'inset(-14px -14px 100% -14px)', transform: 'translateY(6px)' }, { clipPath: 'inset(-14px -14px -14px -14px)', transform: 'none' }]; } },
    D: { dur: 190, paso: 0, ease: 'cubic-bezier(0,0,.58,1)', f: function () { return [{ opacity: 0 }, { opacity: 1 }]; } }
  };

  var M = { formatoDinero: null, _portada: null, _menuY: null };

  /* ── lo que toca el navegador ── */
  function reducido() {
    try { return !!(root.matchMedia && root.matchMedia('(prefers-reduced-motion: reduce)').matches); } catch (e) { return false; }
  }
  function puede() {
    return !reducido() && typeof root.Element !== 'undefined' && typeof root.Element.prototype.animate === 'function';
  }
  function anima(el, frames, opc) { try { return el.animate(frames, opc); } catch (e) { return null; } }
  function sesion(clave, valor) {
    try { if (valor === undefined) return root.sessionStorage.getItem(clave); root.sessionStorage.setItem(clave, valor); } catch (e) {}
    return null;
  }
  function vistas() { try { return JSON.parse(sesion(CLAVE_VISTAS) || '[]'); } catch (e) { return []; } }

  /* El dinero que se recorre: el formateo es el del portal (idioma, divisa), no uno propio. */
  function cuenta(el, retraso) {
    var fin = Number(el.getAttribute('data-cuenta')), moneda = el.getAttribute('data-moneda') || '';
    var fmt = M.formatoDinero;
    if (!isFinite(fin) || typeof fmt !== 'function') return;
    var final = el.textContent, t0 = null, DUR = 800;
    function paso(t) {
      if (!el.isConnected) return;
      if (t0 === null) t0 = t;
      var k = Math.min(1, (t - t0) / DUR);
      el.textContent = k >= 1 ? final : fmt(valorCuenta(fin, k), moneda);
      if (k < 1) root.requestAnimationFrame(paso);
    }
    el.textContent = fmt(0, moneda);
    root.setTimeout(function () { if (el.isConnected) root.requestAnimationFrame(paso); else el.textContent = final; }, retraso);
    // si nadie lo repinta ni lo cuenta hasta el final, el valor exacto vuelve igualmente
    root.setTimeout(function () { if (el.isConnected) el.textContent = final; }, retraso + DUR + 200);
  }

  /* Entrada de una pantalla. `c` es #content: se animan SUS hijos directos, no el marcado de cada pantalla. */
  M.pantalla = function (c, seccion) {
    var v = vistas(), p = perfil(seccion, v);
    if (seccion === 'inicio' && v.indexOf('inicio') === -1) { v.push('inicio'); sesion(CLAVE_VISTAS, JSON.stringify(v)); }
    if (!puede() || !c) { M._portada = null; return; }
    var P = PERF[p];
    var cab = c.querySelector(':scope > .proy-cab'), grande = cab ? cab.querySelector('.proy-portada-grande') : null;
    var flip = null, r = M._portada; M._portada = null;
    if (grande && r && (Date.now() - r.t) < 2500 && r.w > 0 && r.h > 0) {
      var g = grande.getBoundingClientRect();
      if (mismaForma(r.w, r.h, g.width, g.height)) flip = { dx: r.x - g.left, dy: r.y - g.top, sx: r.w / g.width, sy: r.h / g.height, el: grande };
    }
    var piezas = [];
    Array.prototype.forEach.call(c.children, function (el) {
      if (flip && el === cab) { var info = cab.querySelector('.proy-cab-info'); if (info) piezas.push(info); }
      else piezas.push(el);
    });
    var base = flip ? 120 : 0;
    piezas.forEach(function (el, i) { anima(el, P.f(), { duration: P.dur, delay: base + i * P.paso, easing: P.ease, fill: 'backwards' }); });
    if (flip) {
      flip.el.style.transformOrigin = 'top left';
      anima(flip.el, [{ transform: 'translate(' + flip.dx + 'px,' + flip.dy + 'px) scale(' + flip.sx + ',' + flip.sy + ')' }, { transform: 'none' }], { duration: 520, easing: EASE });
    }
    if (p !== 'D') {
      Array.prototype.forEach.call(c.querySelectorAll('.barra > i'), function (el) {
        anima(el, [{ transform: 'scaleX(0)' }, { transform: 'scaleX(1)' }], { duration: 800, delay: 350, easing: EASE, fill: 'backwards' });
      });
    }
    // las cifras solo cuentan la PRIMERA vez que se abre Inicio en la sesión: después, el dato se ve de golpe
    if (p === 'B') {
      Array.prototype.forEach.call(c.querySelectorAll('[data-cuenta]'), function (el, i) { cuenta(el, 220 + i * 80); });
    }
    var act = c.querySelector('.tl-paso.actual'), pasos = c.querySelectorAll('.tl-paso');
    Array.prototype.forEach.call(pasos, function (el, i) {
      anima(el, [{ opacity: 0, transform: 'translateY(8px) scale(.96)' }, { opacity: 1, transform: 'none' }], { duration: 380, delay: 260 + i * 60, easing: EASE, fill: 'backwards' });
    });
    if (act) root.setTimeout(function () { if (act.isConnected) act.classList.add('pulso'); }, 260 + pasos.length * 60 + 150);
  };

  /* La portada de la tarjeta que se pulsa: la carpeta que se abre la hace crecer desde ahí. */
  M.recuerdaPortada = function (el) {
    try { var r = el.getBoundingClientRect(); M._portada = { x: r.left, y: r.top, w: r.width, h: r.height, t: Date.now() }; } catch (e) { M._portada = null; }
  };

  /* Menú: el indicador del item activo se desliza en vez de saltar. pintaNav() reconstruye #nav en cada repintado,
     así que el indicador se recrea y arranca desde donde estaba el anterior. Sin movimiento, no se crea y el item
     activo conserva su fondo (la clase `lw-mov` solo la pone este módulo). */
  M.menu = function (nav, anima_) {
    if (!nav) return;
    var activo = nav.querySelector('.navrow.on');
    if (!puede() || !activo) { root.document.documentElement.classList.remove('lw-mov'); M._menuY = null; return; }
    root.document.documentElement.classList.add('lw-mov');
    var ind = nav.querySelector('.nav-ind');
    if (!ind) { ind = root.document.createElement('span'); ind.className = 'nav-ind'; ind.setAttribute('aria-hidden', 'true'); nav.insertBefore(ind, nav.firstChild); }
    var y = activo.offsetTop, h = activo.offsetHeight;
    ind.style.height = h + 'px'; ind.style.transform = 'translateY(' + y + 'px)';
    if (anima_ && M._menuY !== null && M._menuY !== y) anima(ind, [{ transform: 'translateY(' + M._menuY + 'px)' }, { transform: 'translateY(' + y + 'px)' }], { duration: 340, easing: EASE });
    M._menuY = y;
  };

  /* Campana: suena UNA vez por sesión, y solo si hay novedades sin leer. Nunca al abrir el panel. */
  M.campana = function (boton, nuevas) {
    if (!puede() || !boton || !nuevas || sesion(CLAVE_CAMPANA)) return;
    sesion(CLAVE_CAMPANA, '1');
    var ico = boton.querySelector('.ico-campana'), n = boton.querySelector('.n');
    root.setTimeout(function () {
      if (ico && ico.isConnected) anima(ico, [{ transform: 'rotate(0)' }, { transform: 'rotate(14deg)', offset: .2 }, { transform: 'rotate(-12deg)', offset: .4 }, { transform: 'rotate(8deg)', offset: .6 }, { transform: 'rotate(-4deg)', offset: .8 }, { transform: 'rotate(0)' }], { duration: 760, easing: 'ease-in-out' });
      if (n && n.isConnected) anima(n, [{ boxShadow: '0 0 0 0 rgba(158,47,38,.55)' }, { boxShadow: '0 0 0 9px rgba(158,47,38,0)' }], { duration: 1100, easing: EASE });
    }, 900);
  };
  M.abrePanel = function (el) {
    if (!puede() || !el) return;
    el.style.transformOrigin = '100% 0';
    anima(el, [{ opacity: 0, transform: 'scale(.96) translateY(-6px)' }, { opacity: 1, transform: 'none' }], { duration: 180, easing: EASE });
  };

  /* Cajón lateral: entra por la derecha con el velo en fundido; sale algo más rápido. `fin` se llama al acabar. */
  M.cajon = function (dr, velo, abre, fin) {
    if (!puede() || !dr) { if (fin) fin(); return; }
    if (abre) {
      if (velo) anima(velo, [{ opacity: 0 }, { opacity: 1 }], { duration: 260, easing: 'ease-out' });
      anima(dr, [{ transform: 'translateX(100%)' }, { transform: 'none' }], { duration: 320, easing: EASE });
      if (fin) fin();
      return;
    }
    if (velo) anima(velo, [{ opacity: 1 }, { opacity: 0 }], { duration: 200, easing: 'ease-in' });
    var a = anima(dr, [{ transform: 'none' }, { transform: 'translateX(100%)' }], { duration: 220, easing: 'cubic-bezier(.4,0,1,1)' });
    if (a) a.onfinish = function () { if (fin) fin(); }; else if (fin) fin();
  };

  M.perfil = perfil; M.mismaForma = mismaForma; M.valorCuenta = valorCuenta; M.claveVista = claveVista; M.puede = puede;
  if (typeof module !== 'undefined' && module.exports) module.exports = M; else root.LW_MOV = M;
})(typeof window !== 'undefined' ? window : this);
