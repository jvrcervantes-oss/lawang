/* motion.js — el movimiento del portal de clientes (7-oct-2026, owner: «gran mejora, impleméntalo todo»).
 *
 * Es el mismo lenguaje que la entrada de pantalla de la intranet v4 (intranet/v4/assets/motion.js, elegido por el
 * owner el 26-sep: A «Sereno» por defecto, B «Plano» la primera vez que se abre Inicio en la sesión, D «Directo»
 * para el dinero) y la misma curva (--lw-ease). Lo que aquí se añade es propio de un panel de cliente: el indicador
 * del menú, abrir una carpeta de proyecto con la portada que crece, el pulso del paso actual, la campana y el cajón.
 *
 * QUÉ NO PUEDE PASAR (y cómo se evita):
 *  · Que algo se quede oculto o a medias. Las entradas solo usan `fill: backwards` mientras esperan su turno: al acabar
 *    manda el CSS. Lo único con `forwards` son las copias que se desvanecen al filtrar, y se borran solas al terminar. Si este fichero no carga, el portal funciona igual, sin movimiento (el CSS no depende de él salvo la
 *    clase `lw-mov` que él mismo pone: sin la clase, el item activo del menú sigue con su fondo propio).
 *  · Que un importe quede mal. La cifra YA está escrita en el HTML; aquí solo se recorre desde 0 y siempre se
 *    restaura el valor exacto al terminar o si el nodo desaparece.
 *  · Que repinte lo que no cambió. `pantalla()` solo se llama cuando cambia la sección o la carpeta; un repintado por
 *    idioma o por recarga de datos no anima (lo decide index.html con la clave «sección|carpeta»).
 *  · Molestar a quien pidió menos movimiento: con `prefers-reduced-motion` o sin la API `animate`, no se hace nada.
 *  · Enganchar a un texto. Todo cuelga de clases e ids que no cambian (.barra, .tl-paso, #nav…), nunca de
 *    un rótulo ni de una cabecera (norma del owner, 29-sep-2026).
 * Se prueba en node con motion.test.js (lo puro) y con el arnés de capturas (lo visual). */
(function (root) {
  'use strict';
  var EASE = 'cubic-bezier(.23,1,.32,1)', EASE_IO = 'cubic-bezier(.77,0,.175,1)';
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
  function claveVista(seccion, carpeta) { return seccion + '|' + (seccion === 'documentos' ? (carpeta || '') : ''); }
  /* La ventana de `dest` que ocupa `orig` (rectángulos de getBoundingClientRect), como clip-path: así la portada de la
     carpeta nace en el sitio y del tamaño de la foto de la tarjeta pulsada y crece hasta ocuparlo todo. Nunca negativo:
     si la tarjeta queda fuera de la portada, el recorte se queda en el borde. */
  function recorte(orig, dest, radio) {
    var n = function (v) { return Math.max(0, Math.round(v)); };
    return 'inset(' + n(orig.top - dest.top) + 'px ' + n(dest.right - orig.right) + 'px ' + n(dest.bottom - orig.bottom) + 'px ' + n(orig.left - dest.left) + 'px round ' + (radio || 0) + 'px)';
  }

  var PERF = {
    A: { dur: 420, paso: 45, ease: EASE, f: function () { return [{ opacity: 0, transform: 'translateY(10px)' }, { opacity: 1, transform: 'none' }]; } },
    B: { dur: 546, paso: 70, ease: 'cubic-bezier(.65,0,.35,1)', f: function () { return [{ clipPath: 'inset(-14px -14px 100% -14px)', transform: 'translateY(6px)' }, { clipPath: 'inset(-14px -14px -14px -14px)', transform: 'none' }]; } },
    D: { dur: 190, paso: 0, ease: 'cubic-bezier(0,0,.58,1)', f: function () { return [{ opacity: 0 }, { opacity: 1 }]; } }
  };

  var M = { formatoDinero: null, _menuY: null, _sel: {}, _portada: null };

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
    if (!puede() || !c) return;
    var P = PERF[p];
    /* Desde una tarjeta de proyecto de Inicio: la portada de la carpeta crece desde la foto pulsada (el
       resto entra después y por piezas). Solo si el clic fue hace un momento: atrás/adelante o recargar no lo hacen. */
    var r = M._portada; M._portada = null;
    var heroe = seccion === 'documentos' ? c.querySelector(':scope > .dc-heroe') : null, crece = false;
    if (heroe && r && (Date.now() - r.t) < 2500 && r.w > 0 && r.h > 0) {
      var d = heroe.getBoundingClientRect();
      if (d.width > 0) {
        crece = true;
        anima(heroe, [{ clipPath: recorte(r, d, 12) }, { clipPath: 'inset(0px 0px 0px 0px round 20px)' }], { duration: 440, easing: EASE_IO });
        Array.prototype.forEach.call(heroe.querySelectorAll('.dc-heroe-tx, .dc-heroe-acc'), function (el, i) {
          anima(el, [{ opacity: 0, transform: 'translateY(8px)' }, { opacity: 1, transform: 'none' }], { duration: 320, delay: 300 + i * 60, easing: EASE, fill: 'backwards' });
        });
      }
    }
    var i = 0;
    Array.prototype.forEach.call(c.children, function (el) {
      if (crece && el === heroe) return;
      anima(el, P.f(), { duration: P.dur, delay: (crece ? 260 : 0) + (i++) * P.paso, easing: P.ease, fill: 'backwards' });
    });
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
    /* `fin` se ejecuta UNA vez y siempre: si el aviso de fin de la animación no llegara (pestaña en segundo plano,
       animación cancelada), un temporizador de seguridad lo dispara igualmente; un cajón y un velo que no se ocultan
       taparían el portal entero. */
    var hecho = false;
    function acaba() { if (hecho) return; hecho = true; if (fin) fin(); }
    if (a) a.onfinish = acaba;
    root.setTimeout(acaba, a ? 450 : 0);
  };

  /* La foto de la tarjeta que se pulsa en Inicio: la carpeta que se abre la hace crecer desde ahí. */
  M.recuerdaPortada = function (el) {
    try { var r = el.getBoundingClientRect(); M._portada = { top: r.top, right: r.right, bottom: r.bottom, left: r.left, w: r.width, h: r.height, t: Date.now() }; } catch (e) { M._portada = null; }
  };

  /* Selectores (.ini-filtro de proyecto o villa, .lang-sel del idioma): el fondo del elegido se desliza hasta el nuevo
     en vez de saltar, como el indicador del menú. Cada repintado rehace los botones, así que se recuerda dónde estaba
     por grupo (zona + los data- de sus botones, nunca un rótulo). La pista SOLO existe mientras se desliza: viaja
     desde la posición vieja a la nueva y se borra sola; en reposo el botón elegido tiene su propio fondo, así que un
     cambio de tamaño, de orientación o una fuente que llega tarde nunca dejan su texto blanco sin fondo (revisor). */
  function claveSel(g, zona) {
    var b = g.querySelector('button'), a = [];
    if (b) Array.prototype.forEach.call(b.attributes, function (x) { if (/^data-/.test(x.name)) a.push(x.name); });
    return (zona || '') + '|' + (g.id || '') + '|' + a.sort().join(',');
  }
  function quitaPista(g) {
    var p = g.querySelector(':scope > .lw-pista');
    if (p) p.parentNode.removeChild(p);
    g.classList.remove('con-pista');
  }
  M.selectores = function (raiz, zona) {
    if (!raiz) return;
    Array.prototype.forEach.call(raiz.querySelectorAll('.ini-filtro, .lang-sel'), function (g) {
      var on = g.querySelector('button[aria-pressed="true"]');
      if (!on || !on.offsetWidth) { quitaPista(g); return; }
      var k = claveSel(g, zona), x = on.offsetLeft, w = on.offsetWidth, antes = M._sel[k];
      M._sel[k] = { x: x, w: w };
      if (!puede() || !antes || (antes.x === x && antes.w === w)) { quitaPista(g); return; }
      var pista = g.querySelector(':scope > .lw-pista');
      if (!pista) { pista = root.document.createElement('span'); pista.className = 'lw-pista'; pista.setAttribute('aria-hidden', 'true'); g.insertBefore(pista, g.firstChild); }
      g.classList.add('con-pista');
      pista.style.top = on.offsetTop + 'px'; pista.style.height = on.offsetHeight + 'px';
      pista.style.width = w + 'px'; pista.style.transform = 'translateX(' + x + 'px)';
      anima(pista, [{ transform: 'translateX(' + antes.x + 'px)', width: antes.w + 'px' }, { transform: 'translateX(' + x + 'px)', width: w + 'px' }], { duration: 280, easing: EASE });
      root.clearTimeout(g._lwPista);
      g._lwPista = root.setTimeout(function () { quitaPista(g); }, 300);   // al llegar, el botón recupera su fondo
    });
  };

  /* Filtrar sin saltos: pinta() rehace la lista de `caja`; lo que se queda (mismo valor de `attr`) se recoloca desde
     donde estaba, lo que sale se desvanece rápido (una copia quieta encima, que se borra sola) y lo que entra aparece
     en cascada corta. Con muchas piezas, o sin movimiento, solo se pinta. */
  M.reordena = function (caja, pinta, attr) {
    if (!puede() || !caja || caja.querySelectorAll('[' + attr + ']').length > 60) { pinta(); return; }
    var antes = {}, base = caja.getBoundingClientRect();
    Array.prototype.forEach.call(caja.querySelectorAll('[' + attr + ']'), function (el) { antes[el.getAttribute(attr)] = { r: el.getBoundingClientRect(), el: el }; });
    pinta();
    if (caja.querySelectorAll('[' + attr + ']').length > 60) return;   // lo que entra también cuenta para el tope
    var quedan = {}, n = 0;
    Array.prototype.forEach.call(caja.querySelectorAll('[' + attr + ']'), function (el) {
      var k = el.getAttribute(attr), a = antes[k];
      if (a) {
        quedan[k] = true;
        var r = el.getBoundingClientRect(), dx = a.r.left - r.left, dy = a.r.top - r.top;
        if (dx || dy) anima(el, [{ transform: 'translate(' + dx + 'px,' + dy + 'px)' }, { transform: 'none' }], { duration: 300, easing: EASE_IO });
      } else {
        anima(el, [{ opacity: 0, transform: 'translateY(8px) scale(.98)' }, { opacity: 1, transform: 'none' }], { duration: 260, delay: 90 + Math.min(n++, 8) * 30, easing: EASE, fill: 'backwards' });
      }
    });
    Object.keys(antes).forEach(function (k) {
      if (quedan[k]) return;
      var a = antes[k], f = a.el.cloneNode(true);
      f.removeAttribute(attr); f.removeAttribute('id'); f.removeAttribute('href'); f.setAttribute('aria-hidden', 'true'); f.setAttribute('tabindex', '-1');
      f.style.cssText += ';position:absolute;margin:0;pointer-events:none;left:' + (a.r.left - base.left) + 'px;top:' + (a.r.top - base.top) + 'px;width:' + a.r.width + 'px;height:' + a.r.height + 'px';
      caja.appendChild(f);
      anima(f, [{ opacity: 1, transform: 'none' }, { opacity: 0, transform: 'scale(.96)' }], { duration: 140, easing: 'ease-out', fill: 'forwards' });
      root.setTimeout(function () { if (f.parentNode) f.parentNode.removeChild(f); }, 160);
    });
  };

  /* Avisos: el de abajo sube y se asienta; el de error (centro) crece un poco. Se van más rápido de lo que llegan.
     Devuelve false si no hay movimiento, para que el portal siga con su fundido de siempre. */
  M.aviso = function (el, entra, mal) {
    if (!puede() || !el) return false;
    el.classList.add('lw-aviso');   // sin la transición CSS de opacidad, que ganaría a esta animación
    var base = mal ? 'translate(-50%,-50%)' : 'translateX(-50%)';
    if (entra) anima(el, [{ opacity: 0, transform: base + (mal ? ' scale(.94)' : ' translateY(18px)') }, { opacity: 1, transform: base }], { duration: mal ? 220 : 260, easing: EASE });
    else anima(el, [{ opacity: 1, transform: base }, { opacity: 0, transform: base + (mal ? ' scale(.97)' : ' translateY(8px)') }], { duration: 150, easing: 'ease-in' });
    return true;
  };

  M.perfil = perfil; M.valorCuenta = valorCuenta; M.claveVista = claveVista; M.recorte = recorte; M.puede = puede;
  if (typeof module !== 'undefined' && module.exports) module.exports = M; else root.LW_MOV = M;
})(typeof window !== 'undefined' ? window : this);
