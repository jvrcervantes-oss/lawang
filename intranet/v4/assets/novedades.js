/* novedades.js — el pop-up de NOVEDADES al entrar en la intranet v4 (30-sep-2026).
 *
 * Una noticia por pantalla, con puntos y «Siguiente». Sale UNA vez por persona y
 * por versión (`NOV_ID`): al cerrarlo, de la forma que sea, se apunta como visto.
 * Para anunciar algo nuevo se añade una entrada a NOTICIAS y se sube NOV_ID (aquí)
 * y NOVEDADES_V (nav.js): quien lo cerró vuelve a verlo UNA vez.
 *
 * Lo inyecta nav.js tras LW_AUTH, junto a mascota.js, y se sella a mano con
 * NOVEDADES_V (sella_assets no lo ve, como cortina.js y mascota.js). Solo se
 * enseña la noticia cuya herramienta tiene la persona: no se anuncia lo que su
 * menú no le deja abrir. Sin ventana encima ni pantalla cargando: espera.
 * Solo lee la ficha (rol y herramientas); no toca la base. El único dato que
 * guarda es el «visto» en localStorage, que aquí es una comodidad, no un dato
 * de verdad: sin almacenamiento el pop-up sale en cada carga, y ya.
 */
(function () {
  'use strict';
  if (window.__lwNovedades) return;
  window.__lwNovedades = true;
  if (location.pathname.indexOf('/intranet/v4/') === -1) return;

  var NOV_ID = '20260930';
  var Q = 'lw-novedades:visto:';

  function T(s, h) { return window.lwT ? window.lwT(s, h) : (h ? s.replace(/%(\w+)/g, function (m, k) { return h[k] != null ? h[k] : m; }) : s); }
  function lee(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }
  function guarda(k, v) { try { localStorage.setItem(k, v); } catch (e) { /* MUDO A PROPÓSITO: sin almacenamiento solo se pierde el recuerdo de «visto» */ } }
  function el(tag, cls, txt) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (txt != null) e.textContent = txt;
    return e;
  }
  var QUIETO = !!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches);

  /* ── Las noticias. `herr` = herramienta del menú que hace falta para verla ── */
  var NOTICIAS = [
    {
      id: 'asistente-contrato', herr: 'contratos',
      titulo: function () { return T('Nuevo contrato, paso a paso'); },
      texto: function () { return T('El asistente te va preguntando lo justo: si la venta es de tu equipo o por tu cuenta, el tipo de contrato, el cliente y las condiciones. Antes de guardar, revisas el resumen. El formulario de siempre sigue ahí.'); },
      nota: function () { return T('Está en pruebas: si algo no va bien, cuéntaselo al Asistente de la esquina.'); },
      cta: function () { return { texto: T('Probarlo ahora'), href: '/contracts/app.html?nuevo=1&asistente=1' }; },
      arte: arteContrato
    },
    {
      id: 'asistente-avisa', herr: 'asistente',
      titulo: function () { return T('El Asistente te avisa de lo grave'); },
      texto: function () { return T('Si una reserva tuya está a punto de vencer y la parcela se va a liberar, el Asistente te lo dice al entrar. El punto rojo se queda en su esquina mientras siga pendiente.'); },
      nota: function () { return ''; },
      cta: function () { return null; },
      arte: arteAviso,
      grave: true
    }
  ];

  /* Ilustraciones: marcado fijo de este fichero, con textos por T(); ningún dato. */
  function arteContrato() {
    var m = el('div', 'lwn-mini');
    var barra = el('div', 'lwn-barra');
    for (var i = 0; i < 5; i++) barra.appendChild(el('i', i === 0 ? 'h' : ''));
    m.appendChild(barra);
    m.appendChild(el('div', 'lwn-q', T('¿Venta de equipo o por tu cuenta?')));
    var op = el('div', 'lwn-op');
    op.appendChild(el('span', 'on', T('Venta de equipo')));
    op.appendChild(el('span', '', T('Por mi cuenta')));
    m.appendChild(op);
    var ft = el('div', 'lwn-ft');
    ft.appendChild(el('span', '', T('Paso %n de %t', { n: 1, t: 5 })));
    ft.appendChild(el('u', '', T('Formulario clásico')));
    m.appendChild(ft);
    return m;
  }
  function arteAviso() {
    var e = el('div', 'lwn-esc');
    var av = el('div', 'lwn-aviso');
    av.appendChild(el('b', '', T('Urgente')));
    av.appendChild(document.createTextNode(T('Una reserva vence en 2 días. Pide la prórroga o cierra el Bloqueo.')));
    e.appendChild(av);
    var mas = el('div', 'lwn-mas', 'A');
    e.appendChild(mas);
    return e;
  }

  var CSS =
    '#lw-novedades{position:fixed;inset:0;z-index:var(--z-modal,400);display:flex;align-items:center;justify-content:center;padding:16px;background:rgba(27,28,25,.5);font-family:"Neue Kabel",system-ui,sans-serif;color:#44483f}' +
    '#lw-novedades *{box-sizing:border-box}' +
    '#lw-novedades .lwn-pop{width:min(520px,100%);max-height:100%;overflow:auto;background:#FBF9F4;border:1px solid #E4DCCB;border-radius:20px;display:flex;flex-direction:column}' +
    '#lw-novedades .lwn-cab{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:16px 18px 0 24px}' +
    '#lw-novedades .lwn-cuenta{font-size:12px;letter-spacing:.14em;text-transform:uppercase;color:#75786e;font-variant-numeric:tabular-nums}' +
    '#lw-novedades .lwn-x{width:34px;height:34px;border:0;border-radius:999px;background:transparent;color:#75786e;cursor:pointer;display:flex;align-items:center;justify-content:center}' +
    '#lw-novedades .lwn-x:hover{background:#efeee8;color:#1b1c19}' +
    '#lw-novedades .lwn-not{display:none;padding:12px 24px 0}' +
    '#lw-novedades .lwn-not.on{display:block}' +
    '#lw-novedades .lwn-arte{height:220px;border-radius:16px;background:#DCEAE7;display:grid;place-items:center;padding:18px;overflow:hidden}' +
    '#lw-novedades .lwn-arte.grave{background:#F8E3E0}' +
    '#lw-novedades .lwn-tit{margin:20px 0 6px;font-size:clamp(26px,6vw,34px);line-height:1.1;font-weight:400;color:#2E3437;text-wrap:balance}' +
    '#lw-novedades .lwn-txt{margin:0;font-size:15px;line-height:1.55}' +
    '#lw-novedades .lwn-nota{margin:10px 0 0;font-size:13px;line-height:1.45;color:#75786e}' +
    '#lw-novedades .lwn-nav{display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap;padding:18px 24px 22px}' +
    '#lw-novedades .lwn-puntos{display:flex;gap:7px}' +
    '#lw-novedades .lwn-puntos button{width:9px;height:9px;padding:0;border:0;border-radius:999px;background:#E4DCCB;cursor:pointer}' +
    '#lw-novedades .lwn-puntos button[aria-current="true"]{width:24px;background:#104C4F}' +
    '#lw-novedades .lwn-acc{display:flex;gap:8px;align-items:center;flex-wrap:wrap}' +
    '#lw-novedades .lwn-btn{font:inherit;font-size:14px;font-weight:600;line-height:1;padding:11px 18px;border-radius:999px;cursor:pointer;border:1px solid #E4DCCB;background:#fff;color:#2E3437;text-decoration:none;display:inline-block}' +
    '#lw-novedades .lwn-btn:hover{background:#f5f4ee}' +
    '#lw-novedades .lwn-btn.pri{border-color:#104C4F;background:#104C4F;color:#fff}' +
    '#lw-novedades .lwn-btn.pri:hover{background:#0c3c3e}' +
    '#lw-novedades .lwn-btn.t{border-color:transparent;background:transparent;color:#75786e}' +
    '#lw-novedades button:focus-visible,#lw-novedades a:focus-visible{outline:2px solid #104C4F;outline-offset:2px}' +
    '#lw-novedades [hidden]{display:none!important}' +
    /* ilustración 1: mini pantalla del asistente */
    '#lw-novedades .lwn-mini{width:100%;max-width:380px;background:#FBF9F4;border-radius:14px;padding:14px 16px;display:grid;gap:10px}' +
    '#lw-novedades .lwn-barra{display:grid;grid-template-columns:repeat(5,1fr);gap:5px}' +
    '#lw-novedades .lwn-barra i{height:4px;border-radius:2px;background:#E4DCCB}' +
    '#lw-novedades .lwn-barra i.h{background:#104C4F}' +
    '#lw-novedades .lwn-q{font-size:17px;font-weight:600;line-height:1.2;color:#2E3437}' +
    '#lw-novedades .lwn-op{display:grid;grid-template-columns:1fr 1fr;gap:8px}' +
    '#lw-novedades .lwn-op span{border:1px solid #E4DCCB;border-radius:10px;padding:10px 12px;font-size:14px}' +
    '#lw-novedades .lwn-op span.on{border-color:#104C4F;background:#104C4F;color:#fff}' +
    '#lw-novedades .lwn-ft{display:flex;justify-content:space-between;align-items:center;gap:8px;font-size:12px;color:#75786e}' +
    '#lw-novedades .lwn-ft u{text-decoration:none;border-bottom:1px solid #75786e}' +
    /* ilustración 2: el aviso y la mascota con su punto */
    '#lw-novedades .lwn-esc{position:relative;width:100%;max-width:380px;height:100%}' +
    '#lw-novedades .lwn-aviso{position:absolute;left:0;right:60px;top:26px;background:#FBF9F4;border:1px solid #9E2F26;border-radius:16px 16px 4px 16px;padding:12px 14px;font-size:14px;line-height:1.4;color:#2E3437}' +
    '#lw-novedades .lwn-aviso b{display:block;color:#9E2F26;font-weight:600;font-size:11px;letter-spacing:.14em;text-transform:uppercase;margin-bottom:3px}' +
    '#lw-novedades .lwn-mas{position:absolute;right:4px;bottom:8px;width:52px;height:52px;border-radius:999px;background:#104C4F;color:#FBF9F4;display:grid;place-items:center;font-size:22px;font-weight:600}' +
    '#lw-novedades .lwn-mas::after{content:"";position:absolute;top:1px;right:1px;width:14px;height:14px;border-radius:999px;background:#9E2F26;border:2px solid #F8E3E0}' +
    '@media (max-width:480px){#lw-novedades .lwn-arte{height:190px}#lw-novedades .lwn-not,#lw-novedades .lwn-nav{padding-left:18px;padding-right:18px}#lw-novedades .lwn-cab{padding-left:18px}}' +
    '@media (prefers-reduced-motion:no-preference){#lw-novedades .lwn-not.on{animation:lwnEntra .28s ease-out}@keyframes lwnEntra{from{opacity:0;transform:translateX(14px)}to{opacity:1;transform:none}}}' +
    '@media print{#lw-novedades{display:none}}';

  function monta(aut) {
    var ficha = (aut && aut.ficha) || {};
    var email = (aut && aut.session && aut.session.user && aut.session.user.email) || '';
    if (!email || !aut.ficha) return;            // sin usuario o sin ficha no hay a quién recordar ni qué herramientas tiene
    var K = Q + email;
    var herr = ficha.herramientas || [];
    var lista = NOTICIAS.filter(function (n) { return LW_ROL.esSuperGlobal(ficha) || herr.indexOf(n.herr) !== -1; });
    if (!lista.length) return;
    var yaVisto = lee(K) === NOV_ID;

    function hayVentana() {
      return !!document.querySelector('#lw-cajon,#lw-editor,.lw-dlg-fondo.abierto,body.v4-nav-abierta,#lw-cargando');
    }
    var intentos = 0;
    function cuandoToque() {
      if (document.hidden || hayVentana()) {
        if (++intentos > 40) return;             // tras ~1 min sin hueco no se insiste: sale en la próxima entrada
        setTimeout(cuandoToque, 1500);
        return;
      }
      abre();
    }

    function abre() {
      if (document.getElementById('lw-novedades')) return;   // ya está abierto
      var st = document.createElement('style');
      st.id = 'lw-novedades-css';
      st.textContent = CSS;
      document.head.appendChild(st);

      var previo = document.activeElement;
      var velo = el('div');
      velo.id = 'lw-novedades';
      var pop = el('div', 'lwn-pop');
      pop.setAttribute('role', 'dialog');
      pop.setAttribute('aria-modal', 'true');
      pop.setAttribute('aria-labelledby', 'lwn-t0');

      var cab = el('div', 'lwn-cab');
      var cuenta = el('span', 'lwn-cuenta');
      var x = el('button', 'lwn-x');
      x.type = 'button';
      x.setAttribute('data-accion', 'novedades-cerrar');
      x.setAttribute('aria-label', T('Cerrar'));
      x.innerHTML = '<span class="material-symbols-outlined" style="font-size:20px" aria-hidden="true">close</span>';   // marcado fijo, sin datos
      cab.appendChild(cuenta);
      cab.appendChild(x);
      pop.appendChild(cab);

      var paneles = lista.map(function (n, i) {
        var p = el('article', 'lwn-not');
        var arte = el('div', 'lwn-arte' + (n.grave ? ' grave' : ''));
        arte.setAttribute('aria-hidden', 'true');
        arte.appendChild(n.arte());
        p.appendChild(arte);
        var h = el('h2', 'lwn-tit', n.titulo());
        h.id = 'lwn-t' + i;
        p.appendChild(h);
        p.appendChild(el('p', 'lwn-txt', n.texto()));
        var nota = n.nota();
        if (nota) p.appendChild(el('p', 'lwn-nota', nota));
        pop.appendChild(p);
        return p;
      });

      var nav = el('div', 'lwn-nav');
      var puntos = el('div', 'lwn-puntos');
      var acc = el('div', 'lwn-acc');
      var ant = el('button', 'lwn-btn t', T('Anterior'));
      ant.type = 'button';
      ant.setAttribute('data-accion', 'novedades-anterior');
      var cta = el('a', 'lwn-btn');
      var sig = el('button', 'lwn-btn pri');
      sig.type = 'button';
      sig.setAttribute('data-accion', 'novedades-siguiente');
      acc.appendChild(ant);
      acc.appendChild(cta);
      acc.appendChild(sig);
      nav.appendChild(puntos);
      nav.appendChild(acc);
      pop.appendChild(nav);
      velo.appendChild(pop);
      document.body.appendChild(velo);

      var cur = 0;
      function ir(i) {
        cur = i;
        paneles.forEach(function (p, j) { p.classList.toggle('on', j === i); });
        puntos.textContent = '';
        lista.forEach(function (_, j) {
          var b = el('button');
          b.type = 'button';
          b.setAttribute('data-accion', 'novedades-ir');
          b.setAttribute('aria-label', T('Noticia %n de %t', { n: j + 1, t: lista.length }));
          if (j === i) b.setAttribute('aria-current', 'true');
          b.addEventListener('click', function () { ir(j); });
          puntos.appendChild(b);
        });
        cuenta.textContent = T('Novedades') + ' · ' + T('%n de %t', { n: i + 1, t: lista.length });
        pop.setAttribute('aria-labelledby', 'lwn-t' + i);
        ant.hidden = i === 0;
        var c = lista[i].cta();
        cta.hidden = !c;
        if (c) { cta.textContent = c.texto; cta.href = c.href; cta.setAttribute('data-accion', 'novedades-cta'); }
        sig.textContent = i === lista.length - 1 ? T('Entendido') : T('Siguiente');
      }
      var cerrando = false;
      function cierra() {
        if (cerrando) return;
        cerrando = true;
        guarda(K, NOV_ID);
        document.removeEventListener('keydown', teclas, true);
        function fin() {
          velo.remove();
          st.remove();
          if (previo && previo.focus) { try { previo.focus(); } catch (e) { /* MUDO A PROPÓSITO: el foco previo pudo desaparecer del DOM */ } }
        }
        var v = haciaCampana();
        if (!v || !pop.animate) { fin(); return; }
        velo.style.pointerEvents = 'none';
        velo.animate([{ background: 'rgba(27,28,25,.5)' }, { background: 'rgba(27,28,25,0)' }], { duration: 380, fill: 'forwards' });
        var a = pop.animate([{ transform: 'none', opacity: 1 }, { transform: v, opacity: 0 }], { duration: 380, easing: 'cubic-bezier(.5,0,.75,.3)', fill: 'forwards' });
        a.onfinish = function () { sacude(); fin(); };
      }
      /* La campana es de donde sale y adonde vuelve: traslación + escala hacia su centro.
         Sin campana en pantalla (o con «reducir movimiento») no se anima: aparece y se va. */
      function campana() { var b = document.querySelector('[data-lw="k-avisos"]'); return b ? b.closest('button') : null; }
      function haciaCampana() {
        if (QUIETO) return null;
        var c = campana();
        if (!c) return null;
        var r = c.getBoundingClientRect(), p = pop.getBoundingClientRect();
        if (!r.width || !p.width) return null;
        var dx = (r.left + r.width / 2) - (p.left + p.width / 2), dy = (r.top + r.height / 2) - (p.top + p.height / 2);
        return 'translate(' + Math.round(dx) + 'px,' + Math.round(dy) + 'px) scale(.06)';
      }
      function sacude() {
        var c = campana();
        if (c && c.animate && !QUIETO) c.animate([{ transform: 'rotate(0)' }, { transform: 'rotate(-16deg)' }, { transform: 'rotate(13deg)' }, { transform: 'rotate(-8deg)' }, { transform: 'rotate(0)' }], { duration: 550, easing: 'ease-in-out' });
      }
      function teclas(ev) {
        if (ev.key === 'Escape') { ev.stopPropagation(); cierra(); }
        else if (ev.key === 'ArrowRight' && cur < lista.length - 1) ir(cur + 1);
        else if (ev.key === 'ArrowLeft' && cur > 0) ir(cur - 1);
        else if (ev.key === 'Tab') {                               // el foco no se escapa a la página de detrás
          var f = [].slice.call(pop.querySelectorAll('button,a[href]')).filter(function (n) { return !n.hidden && n.offsetParent !== null; });
          if (!f.length) return;
          var a = f[0], z = f[f.length - 1];
          if (ev.shiftKey && document.activeElement === a) { ev.preventDefault(); z.focus(); }
          else if (!ev.shiftKey && document.activeElement === z) { ev.preventDefault(); a.focus(); }
        }
      }
      x.addEventListener('click', cierra);
      ant.addEventListener('click', function () { ir(cur - 1); });
      sig.addEventListener('click', function () { if (cur === lista.length - 1) cierra(); else ir(cur + 1); });
      cta.addEventListener('click', function () { guarda(K, NOV_ID); });   // se va a probarlo: ya lo ha visto
      velo.addEventListener('click', function (ev) { if (ev.target === velo) cierra(); });
      document.addEventListener('keydown', teclas, true);
      ir(0);
      sig.focus();
      var d = haciaCampana();
      if (d && pop.animate) {                       // sale de la campana
        sacude();
        velo.animate([{ background: 'rgba(27,28,25,0)' }, { background: 'rgba(27,28,25,.5)' }], { duration: 420 });
        pop.animate([{ transform: d, opacity: 0 }, { transform: 'none', opacity: 1 }], { duration: 520, delay: 120, easing: 'cubic-bezier(.2,.9,.3,1)', fill: 'backwards' });
      }
    }
    /* Volver a verlo cuando se quiera: la fila «Novedades» del panel de la campana lo llama. */
    window.lwNovedades = { abre: abre };
    if (!yaVisto) setTimeout(cuandoToque, 1200);
  }

  function arranca() {
    if (!window.LW_AUTH || typeof window.LW_AUTH.then !== 'function') return;
    window.LW_AUTH.then(function (aut) { monta(aut); })
      .catch(function (e) { /* MUDO A PROPÓSITO: sin sesión resuelta no hay pop-up; se deja rastro en consola */ console.warn('[novedades]', e); });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', arranca);
  else arranca();
})();
