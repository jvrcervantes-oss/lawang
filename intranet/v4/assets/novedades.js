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

  var NOV_ID = '20261013';
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

  /* ── Las noticias. La ve quien tiene la herramienta `herr` del menú o uno de los
     `roles` de la lista (el super global, todas). `lista` = puntos bajo el texto.
     Las dos del 30-sep (asistente de contrato y avisos del Asistente) se retiraron
     el 13-oct al subir NOV_ID: ya las había visto todo el equipo. ── */
  var NOTICIAS = [
    {
      /* Regla del owner (13-oct-2026), texto aprobado por él ese día. Solo ventas
         con fecha de venta desde el 1-nov; las anteriores siguen con la de hoy. */
      id: 'comisiones-1nov', roles: ['agente', 'sales_manager'],
      titulo: function () { return T('Comisiones desde el 1 de noviembre'); },
      texto: function () { return T('Desde el 1 de noviembre de 2026, la comisión de cada venta se paga en dos momentos:'); },
      lista: function () {
        return [
          T('Parcela: el 10\u00a0% de su valor, cuando el cliente ha pagado el 50\u00a0% de la parcela.'),
          T('Construcción: el 10\u00a0% de su valor, cuando el cliente ha pagado el 25\u00a0% de la construcción.')
        ];
      },
      nota: function () { return T('Tu parte dentro del equipo no cambia. Las ventas anteriores al 1 de noviembre siguen con la regla de hoy.'); },
      cta: function () { return null; },
      arte: arteComision
    },
    {
      /* En producción desde el 13-oct-2026 (alta de cliente en editores.js: «Foto del pasaporte»).
         Aviso pedido por el owner el 14-oct. La ve quien puede dar de alta clientes. */
      id: 'pasaporte-alta', roles: ['agente', 'sales_manager'], herr: 'compradores',
      titulo: function () { return T('Foto del pasaporte, obligatoria'); },
      texto: function () { return T('Para dar de alta un cliente nuevo hay que adjuntar la foto de su pasaporte.'); },
      lista: function () {
        return [
          T('Vale una foto o un escaneo (JPG, PNG, WEBP, HEIC o PDF, hasta 20 MB). Si es un DNI o una tarjeta, sube las dos caras.'),
          T('Si el cliente es una empresa, se pide su documento de identificación: NPWP, escritura o certificado del registro.'),
          T('La foto queda guardada en la Documentación KYC de su ficha.')
        ];
      },
      nota: function () { return T('Las fichas que ya existían no cambian. Junto al campo tienes el aviso de privacidad para enseñárselo al cliente.'); },
      cta: function () { return null; },
      arte: artePasaporte
    }
  ];

  /* Ilustraciones: marcado fijo de este fichero, con textos por T(); ningún dato. */
  function artePasaporte() {
    var m = el('div', 'lwn-com');
    var f = el('div', 'lwn-com-f');
    var cab = el('div', 'lwn-com-cab');
    cab.appendChild(el('span', '', T('Foto del pasaporte')));
    cab.appendChild(el('i', 'lwn-pas-ob', T('Obligatoria')));
    f.appendChild(cab);
    var caja = el('div', 'lwn-pas-caja');
    caja.innerHTML = '<span class="material-symbols-outlined" aria-hidden="true">badge</span>';   // marcado fijo, sin datos
    caja.appendChild(el('span', '', T('Adjunta la foto del pasaporte.')));
    f.appendChild(caja);
    m.appendChild(f);
    return m;
  }
  function arteComision() {
    var m = el('div', 'lwn-com');
    [[T('Parcela'), 50], [T('Construcción'), 25]].forEach(function (p) {
      var f = el('div', 'lwn-com-f');
      var cab = el('div', 'lwn-com-cab');
      cab.appendChild(el('span', '', p[0]));
      cab.appendChild(el('b', '', '10\u00a0%'));
      f.appendChild(cab);
      var barra = el('div', 'lwn-com-barra');
      var lleno = el('i');
      lleno.style.width = p[1] + '%';
      barra.appendChild(lleno);
      f.appendChild(barra);
      f.appendChild(el('div', 'lwn-com-pie', T('al cobrar el %p', { p: p[1] + '\u00a0%' })));
      m.appendChild(f);
    });
    return m;
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
    '#lw-novedades .lwn-lista{margin:10px 0 0;padding:0 0 0 18px;font-size:15px;line-height:1.55}' +
    '#lw-novedades .lwn-lista li+li{margin-top:6px}' +
    /* ilustración: las dos partes de la comisión, cada una con su barra de cobro */
    '#lw-novedades .lwn-arte:has(.lwn-com){height:auto}' +
    '#lw-novedades .lwn-com{width:100%;max-width:380px;display:grid;gap:10px}' +
    '#lw-novedades .lwn-com-f{background:#FBF9F4;border-radius:14px;padding:12px 16px;display:grid;gap:8px}' +
    '#lw-novedades .lwn-com-cab{display:flex;justify-content:space-between;align-items:baseline;gap:8px;font-size:15px;color:#2E3437}' +
    '#lw-novedades .lwn-com-cab b{font-weight:400;font-size:24px;line-height:1;color:#104C4F;font-variant-numeric:tabular-nums}' +
    '#lw-novedades .lwn-com-barra{height:6px;border-radius:3px;background:#E4DCCB;overflow:hidden}' +
    '#lw-novedades .lwn-com-barra i{display:block;height:100%;background:#104C4F}' +
    '#lw-novedades .lwn-com-pie{font-size:12px;color:#75786e;font-variant-numeric:tabular-nums}' +
    /* ilustración: el campo del pasaporte en el alta de cliente */
    '#lw-novedades .lwn-pas-ob{font-style:normal;font-size:11px;letter-spacing:.14em;text-transform:uppercase;color:#9E2F26}' +
    '#lw-novedades .lwn-pas-caja{display:flex;align-items:center;gap:10px;border:1px dashed #104C4F;border-radius:10px;padding:16px 14px;font-size:14px;color:#2E3437}' +
    '#lw-novedades .lwn-pas-caja .material-symbols-outlined{font-size:26px;color:#104C4F}' +
    '@media (max-width:480px){#lw-novedades .lwn-arte{height:190px}#lw-novedades .lwn-not,#lw-novedades .lwn-nav{padding-left:18px;padding-right:18px}#lw-novedades .lwn-cab{padding-left:18px}}' +
    '@media (prefers-reduced-motion:no-preference){#lw-novedades .lwn-not.on{animation:lwnEntra .28s ease-out}@keyframes lwnEntra{from{opacity:0;transform:translateX(14px)}to{opacity:1;transform:none}}}' +
    '@media print{#lw-novedades{display:none}}';

  function monta(aut) {
    var ficha = (aut && aut.ficha) || {};
    var email = (aut && aut.session && aut.session.user && aut.session.user.email) || '';
    if (!email || !aut.ficha) return;            // sin usuario o sin ficha no hay a quién recordar ni qué herramientas tiene
    var K = Q + email;
    var herr = ficha.herramientas || [];
    var lista = NOTICIAS.filter(function (n) {
      return LW_ROL.esSuperGlobal(ficha) || (n.herr && herr.indexOf(n.herr) !== -1) || (n.roles || []).indexOf(ficha.rol) !== -1;
    });
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
        if (n.lista) {
          var ul = el('ul', 'lwn-lista');
          n.lista().forEach(function (s) { ul.appendChild(el('li', '', s)); });
          p.appendChild(ul);
        }
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
