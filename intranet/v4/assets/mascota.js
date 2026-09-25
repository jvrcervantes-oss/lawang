/* mascota.js — el Asistente, presente en toda la intranet v4 (25-sep-2026).
 *
 * Owner: «que el asistente empiece a ganar vida y protagonismo en toda la
 * intranet. Que sea la mascota que te persigue por si necesitas mandarle
 * alguna tarea, porque va a ir creciendo — la plataforma terminará siendo
 * agéntica». Encargo: encargos/20260925_lawang_asistente_mascota.md (revisión
 * previa #90, Diseño + Desarrollo).
 *
 * QUÉ HACE
 *  · La PRIMERA vez que una persona entra (por usuario, no por navegador: en
 *    un puesto compartido el segundo agente también tiene que conocerlo), la
 *    campana suena, el Asistente sale de ella, baja pegado al borde derecho
 *    —nunca cruzando la tabla del centro— y se presenta en tres pasos: quién
 *    es, qué hace HOY (las peticiones de /asistente/) y que irá aprendiendo.
 *  · Después se queda acoplado en la esquina inferior derecha en todas las
 *    herramientas. Al tocarlo: «¿Qué necesitas?» y lo escrito viaja a
 *    /asistente/?q=…, donde SOLO rellena el campo — nunca envía: un enlace con
 *    ?q= reenviado por WhatsApp no puede pedir nada en nombre de nadie.
 *
 * QUIÉN LO VE. Lo carga nav.js en su pase de LW_AUTH, y solo si
 * `puedeVer('asistente', ficha)` — la misma regla del menú. Sin eso, la
 * mascota mandaría a una página que guard.js rebota. Aquí no se repite la
 * regla: una lista copiada en dos sitios ES el bug.
 *
 * FORMA (revisión de Diseño): personaje plano, del mismo verde que la píldora
 * activa del menú (#314322 sobre #fbf9f4), sin loop continuo — un parpadeo
 * cada 9-14 s y nada más, porque está a la vista mientras alguien firma o
 * cuadra un banco. El brote de la cabeza es a propósito: «va creciendo».
 * El bocadillo copia la piel de dialogo.js (filete #104C4F, borde #E4DCCB).
 *
 * CAPA: `--z-mascota` en la escalera de shell.css. Con un cajón, editor,
 * diálogo o el menú móvil abiertos se esconde con `visibility:hidden` (no
 * solo tapada: así tampoco se llega a ella con el tabulador).
 *
 * AVISAR DE UN FALLO (ampliación del 25-sep, owner: «¿puede detectar si ha
 * habido un fallo y que mande el feedback, o un botón para mandarlo y que me
 * llegue a Telegram?»). nav.js apunta en `window.__lwFallos` los errores de
 * código y los avisos rojos que ve la persona. La mascota se marca con un punto
 * rojo y, ante un error de CÓDIGO, ofrece una vez por página «¿Aviso al
 * estudio?». Nunca envía sola: cada error a Telegram lo inundaría y llegaría sin
 * contexto. El aviso es una petición libre de `solicitudes_cambio` —la misma vía
 * que /asistente/—, que panel-web lleva a Telegram con «Hecho / Rechazar / Al
 * estudio». Revisión previa #93 (Seguridad): solo el mensaje, NUNCA el stack; se
 * limpian en cliente las mismas marcas de PII que tapa panel-web (email, 9+
 * cifras, enlaces) y lo citado entre comillas en los avisos, que es donde van
 * los nombres. El tope de 5 al día es de cortesía, no de seguridad.
 *
 * Se sella a mano con MASCOTA_V en nav.js, como cortina.js: sella_assets solo
 * recorre las etiquetas de los HTML y este fichero no tiene ninguna.
 */
(function () {
  'use strict';
  if (window.__lwMascota) return;
  window.__lwMascota = true;
  if (location.pathname.indexOf('/intranet/v4/') === -1) return;

  var self = document.currentScript || document.querySelector('script[src*="mascota.js"]');
  var ROOT = self ? self.src.replace(/assets\/mascota\.js.*$/, '') : '../';
  var EN_ASISTENTE = /\/intranet\/v4\/asistente\/?(index\.html)?$/.test(location.pathname);
  var Q_MAX = 500;

  function T(s, h) { return window.lwT ? window.lwT(s, h) : (h ? s.replace(/%(\w+)/g, function (m, k) { return h[k] != null ? h[k] : m; }) : s); }
  var QUIETO = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  function lee(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }
  function guarda(k, v) { try { localStorage.setItem(k, v); } catch (e) { /* MUDO A PROPÓSITO: sin almacenamiento solo se pierde el recuerdo */ } }
  function hoy() { var d = new Date(); return d.getFullYear() + '-' + ('0' + (d.getMonth() + 1)).slice(-2) + '-' + ('0' + d.getDate()).slice(-2); }

  /* ── En /asistente/: el ?q= rellena el campo y nada más ─────────────────── */
  function rellenaDesdeUrl() {
    var q;
    try { q = new URLSearchParams(location.search).get('q'); } catch (e) { return; }
    if (!q) return;
    var campo = document.getElementById('sc-texto');
    if (!campo) return;
    campo.value = String(q).slice(0, Q_MAX);   // .value, nunca HTML; tope de longitud
    try { history.replaceState(null, '', location.pathname + location.hash); } catch (e) { /* MUDO A PROPÓSITO: solo limpia la barra */ }
    campo.focus();
    campo.setSelectionRange(campo.value.length, campo.value.length);
  }

  /* ── El personaje ─────────────────────────────────────────────────────── */
  var SVG =
    '<svg viewBox="0 0 48 48" width="48" height="48" aria-hidden="true" focusable="false">' +
      '<ellipse class="lwm-suelo" cx="24" cy="45" rx="12" ry="2.2" fill="#1b1c19" opacity=".12"/>' +
      '<g class="lwm-cuerpo">' +
        '<g class="lwm-brote">' +
          '<path d="M24 16.5V9.5" stroke="#485b37" stroke-width="2.4" stroke-linecap="round" fill="none"/>' +
          '<path d="M24 11.5c-1.2-3.6-4.4-5.2-7.6-4.6.6 3.3 3.6 5.4 7.6 4.6z" fill="#b8cea1"/>' +
          '<path d="M24 10.2c.9-3.5 3.9-5.4 7.3-5 -.4 3.4-3.3 5.6-7.3 5z" fill="#d3eabb"/>' +
        '</g>' +
        '<rect x="7" y="15" width="34" height="28" rx="13" fill="#314322"/>' +
        '<rect x="11" y="19.5" width="26" height="17" rx="8.5" fill="#485b37"/>' +
        '<g class="lwm-ojos">' +
          '<rect x="17.2" y="23.4" width="4.2" height="8" rx="2.1" fill="#fbf9f4"/>' +
          '<rect x="26.6" y="23.4" width="4.2" height="8" rx="2.1" fill="#fbf9f4"/>' +
        '</g>' +
      '</g>' +
    '</svg>';

  var CSS =
    '#lw-masc{position:fixed;right:24px;bottom:22px;z-index:var(--z-mascota,150);font-family:"Neue Kabel",system-ui,sans-serif;pointer-events:none}' +
    '#lw-masc *{box-sizing:border-box}' +
    '#lw-masc .lwm-yo{pointer-events:auto;display:block;width:52px;height:52px;padding:2px;border:0;border-radius:999px;background:transparent;cursor:pointer;transform-origin:50% 100%;-webkit-tap-highlight-color:transparent}' +
    '#lw-masc .lwm-yo:focus-visible{outline:2px solid #104C4F;outline-offset:2px}' +
    '#lw-masc svg{display:block;width:48px;height:48px;overflow:visible}' +
    '#lw-masc .lwm-ojos{transform-origin:24px 27.4px;transition:transform .18s ease}' +
    '#lw-masc .lwm-ojos.parpadea{animation:lwmParpadeo .16s ease-in-out}' +
    '#lw-masc .lwm-ojos.mira{transform:translate(-1.6px,-1.2px)}' +
    '#lw-masc .lwm-brote{transform-origin:24px 16.5px;transition:transform .3s cubic-bezier(.3,1.6,.5,1)}' +
    '#lw-masc .lwm-yo:hover .lwm-brote,#lw-masc .lwm-brote.saluda{transform:rotate(-9deg)}' +
    '#lw-masc .lwm-cuerpo{transform-origin:24px 43px;transition:transform .25s cubic-bezier(.3,1.4,.5,1)}' +
    '#lw-masc .lwm-yo:hover .lwm-cuerpo{transform:translateY(-2px)}' +
    '@keyframes lwmParpadeo{50%{transform:scaleY(.12)}}' +
    '@keyframes lwmBrote{0%,100%{transform:rotate(0)}30%{transform:rotate(-14deg)}60%{transform:rotate(10deg)}80%{transform:rotate(-4deg)}}' +
    '#lw-masc .lwm-brote.baila{animation:lwmBrote .9s ease-in-out}' +
    /* bocadillo: la piel de dialogo.js */
    '#lw-masc .lwm-bur{pointer-events:auto;position:absolute;right:0;bottom:64px;width:min(340px,calc(100vw - 32px));background:#fff;border:1px solid #E4DCCB;border-radius:12px;box-shadow:0 18px 50px -20px rgba(27,28,25,.35);color:#44483f;transform-origin:calc(100% - 26px) 100%}' +
    '#lw-masc .lwm-bur[hidden]{display:none}' +
    '#lw-masc .lwm-bur::after{content:"";position:absolute;right:20px;bottom:-7px;width:12px;height:12px;background:#fff;border-right:1px solid #E4DCCB;border-bottom:1px solid #E4DCCB;transform:rotate(45deg)}' +
    '#lw-masc .lwm-cab{display:flex;gap:12px;padding:18px 44px 0 20px}' +
    '#lw-masc .lwm-marca{flex:0 0 3px;align-self:stretch;border-radius:2px;background:#104C4F;margin:2px 0}' +
    '#lw-masc .lwm-tit{margin:0;font-size:15.5px;line-height:1.3;font-weight:600;color:#2E3437}' +
    '#lw-masc .lwm-txt{margin:6px 0 0;font-size:14px;line-height:1.5}' +
    '#lw-masc .lwm-cerrar{position:absolute;top:10px;right:10px;width:30px;height:30px;border:0;border-radius:999px;background:transparent;color:#75786e;cursor:pointer;display:flex;align-items:center;justify-content:center}' +
    '#lw-masc .lwm-cerrar:hover{background:#efeee8;color:#1b1c19}' +
    '#lw-masc .lwm-pie{display:flex;align-items:center;gap:8px;flex-wrap:wrap;padding:16px 20px 18px 35px}' +
    '#lw-masc .lwm-puntos{display:flex;gap:5px;margin-right:auto}' +
    '#lw-masc .lwm-puntos i{width:6px;height:6px;border-radius:999px;background:#E4DCCB}' +
    '#lw-masc .lwm-puntos i.on{background:#104C4F}' +
    '#lw-masc .lwm-btn{font:inherit;font-size:13px;font-weight:600;line-height:1;padding:10px 14px;border-radius:999px;cursor:pointer;border:1px solid #E4DCCB;background:#fff;color:#2E3437}' +
    '#lw-masc .lwm-btn:hover{background:#f5f4ee}' +
    '#lw-masc .lwm-btn.pri{border-color:#104C4F;background:#104C4F;color:#fff}' +
    '#lw-masc .lwm-btn.pri:hover{background:#0c3c3e}' +
    '#lw-masc .lwm-btn:focus-visible,#lw-masc .lwm-link:focus-visible,#lw-masc .lwm-cerrar:focus-visible{outline:2px solid #104C4F;outline-offset:2px}' +
    '#lw-masc .lwm-link{font:inherit;font-size:12.5px;border:0;background:none;padding:4px 0;color:#316669;cursor:pointer;text-decoration:underline;text-underline-offset:3px}' +
    '#lw-masc .lwm-campo{display:block;width:calc(100% - 55px);margin:12px 20px 0 35px;min-height:78px;resize:vertical;border:1px solid #c5c8bc;border-radius:8px;padding:10px 12px;font:inherit;font-size:14px;line-height:1.45;color:#1b1c19;background:#fbf9f4}' +
    '#lw-masc .lwm-campo:focus{outline:none;border-color:#104C4F;background:#fff}' +
    '#lw-masc .lwm-yo{position:relative}' +
    '#lw-masc .lwm-bur > .lwm-cab:last-child{padding-bottom:20px}' +
    '#lw-masc .lwm-punto{position:absolute;top:5px;right:5px;width:12px;height:12px;border-radius:999px;background:#9E2F26;border:2px solid #fbf9f4;pointer-events:none}' +
    '#lw-masc .lwm-err{margin:8px 20px 0 35px;font-size:13px;color:#9E2F26}' +
    '#lw-masc .lwm-err[hidden]{display:none}' +
    '#lw-masc .lwm-extra{display:flex;gap:14px;flex-wrap:wrap;padding:0 20px 16px 35px;margin-top:-6px}' +
    /* se esconde con cualquier cajón/diálogo/menú móvil (mismos selectores que el bloqueo de scroll de shell.css) */
    'html:has(#lw-cajon) #lw-masc,html:has(#lw-editor) #lw-masc,html:has(#cajon-detalle:not(.translate-x-full)) #lw-masc,' +
    'html:has(#lw-com-previa-caja:not([hidden])) #lw-masc,html:has(.lw-dlg-fondo.abierto) #lw-masc,html:has(body.v4-nav-abierta) #lw-masc{visibility:hidden}' +
    '@media (max-width:767px){#lw-masc{right:14px;bottom:14px}#lw-masc .lwm-bur{right:-2px}}' +
    '@media print{#lw-masc{display:none}}';

  function el(tag, cls, txt) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (txt != null) e.textContent = txt;
    return e;
  }

  function monta(aut) {
    var ficha = (aut && aut.ficha) || {};
    var email = (aut && aut.session && aut.session.user && aut.session.user.email) || '';
    if (!email) return;   // sin usuario no hay a quién recordar: no sale
    var K_VISTO = 'lw-mascota:presentada:' + email;
    var K_OCULTA = 'lw-mascota:oculta:' + email;
    var nombre = String(ficha.nombre || '').trim().split(/\s+/)[0] || '';

    if (lee(K_OCULTA) === hoy()) return;

    var st = document.createElement('style');
    st.id = 'lw-masc-css';
    st.textContent = CSS;
    document.head.appendChild(st);

    var raiz = el('div');
    raiz.id = 'lw-masc';
    var bur = el('div', 'lwm-bur');
    bur.hidden = true;
    bur.setAttribute('role', 'dialog');
    bur.setAttribute('aria-live', 'polite');
    var yo = el('button', 'lwm-yo');
    yo.type = 'button';
    yo.setAttribute('aria-label', T('Abrir el Asistente'));
    yo.setAttribute('aria-expanded', 'false');
    yo.title = T('Asistente');
    yo.innerHTML = SVG;   // marcado fijo de este fichero, sin datos
    raiz.appendChild(bur);
    raiz.appendChild(yo);
    document.body.appendChild(raiz);

    var ojos = yo.querySelector('.lwm-ojos');
    var brote = yo.querySelector('.lwm-brote');

    /* parpadeo suelto, nada más: sin loop de respiración (revisión de Diseño) */
    function parpadea() {
      ojos.classList.remove('parpadea');
      void ojos.getBoundingClientRect();
      ojos.classList.add('parpadea');
    }
    if (!QUIETO) (function cadaTanto() {
      setTimeout(function () { if (!document.hidden) parpadea(); cadaTanto(); }, 9000 + Math.random() * 5000);
    })();
    function baila() {
      if (QUIETO) return;
      brote.classList.remove('baila');
      void brote.getBoundingClientRect();
      brote.classList.add('baila');
    }

    /* ── bocadillo ── */
    var alCerrar = null;
    function cierra() {
      if (bur.hidden) return;
      bur.hidden = true;
      ojos.classList.remove('mira');
      yo.setAttribute('aria-expanded', 'false');
      var f = alCerrar; alCerrar = null;
      if (f) f();
    }
    function abre(contenido, foco) {
      bur.textContent = '';
      var x = el('button', 'lwm-cerrar');
      x.type = 'button';
      x.setAttribute('aria-label', T('Cerrar'));
      x.innerHTML = '<span class="material-symbols-outlined" style="font-size:18px" aria-hidden="true">close</span>';
      x.addEventListener('click', function () { cierra(); yo.focus(); });
      bur.appendChild(x);
      contenido.forEach(function (n) { bur.appendChild(n); });
      bur.hidden = false;
      yo.setAttribute('aria-expanded', 'true');
      ojos.classList.add('mira');
      if (!QUIETO && bur.animate) bur.animate([{ opacity: 0, transform: 'translateY(6px) scale(.96)' }, { opacity: 1, transform: 'none' }], { duration: 200, easing: 'cubic-bezier(.2,.9,.3,1)' });
      if (foco) setTimeout(function () { foco.focus(); }, 30);
    }
    function cabecera(titulo, texto) {
      var cab = el('div', 'lwm-cab');
      cab.appendChild(el('span', 'lwm-marca'));
      var col = el('div');
      var h = el('p', 'lwm-tit', titulo);
      h.id = 'lwm-tit';
      bur.setAttribute('aria-labelledby', 'lwm-tit');
      col.appendChild(h);
      if (texto) col.appendChild(el('p', 'lwm-txt', texto));
      cab.appendChild(col);
      return cab;
    }
    function boton(texto, pri, fn) {
      var b = el('button', 'lwm-btn' + (pri ? ' pri' : ''), texto);
      b.type = 'button';
      b.addEventListener('click', fn);
      return b;
    }
    function irAlAsistente(q) {
      location.href = ROOT + 'asistente/' + (q ? '?q=' + encodeURIComponent(String(q).slice(0, Q_MAX)) : '');
    }

    /* La presentación: quién es · qué hace HOY · qué viene. El paso 2 dice
       SOLO lo que hace /asistente/ hoy (peticiones). El asistente de
       respuestas a compradores sigue fuera del menú por decisión del owner. */
    var PASOS = [
      { t: nombre ? T('Hola, %nombre. Soy el Asistente.', { nombre: nombre }) : T('Hola. Soy el Asistente.'),
        x: T('Desde hoy te acompaño por toda la intranet, aquí abajo en la esquina. Cuando necesites algo, tócame.') },
      { t: T('Lo que ya sé hacer'),
        x: T('Pídeme lo que la intranet no te deja hacer: cambiar un dato de un comprador, anular o borrar una factura o un recibí, borrar una operación. Dirección lo aprueba y se hace solo.') },
      { t: T('Y lo que viene'),
        x: T('Voy a ir aprendiendo a hacer más cosas por ti. Si me pides algo que aún no sé hacer, también le llega a dirección.') }
    ];
    function presenta(i, primera) {
      var p = PASOS[i];
      var pie = el('div', 'lwm-pie');
      var puntos = el('span', 'lwm-puntos');
      puntos.setAttribute('aria-label', T('Paso %n de %t', { n: i + 1, t: PASOS.length }));
      PASOS.forEach(function (_, j) { puntos.appendChild(el('i', j === i ? 'on' : '')); });
      pie.appendChild(puntos);
      var principal;
      if (i < PASOS.length - 1) {
        principal = boton(T('Siguiente'), true, function () { baila(); presenta(i + 1, primera); });
        pie.appendChild(principal);
      } else {
        pie.appendChild(boton(T('Entendido'), false, function () { cierra(); }));
        principal = boton(T('Pedirle algo'), true, function () { cierra(); if (EN_ASISTENTE) { var c = document.getElementById('sc-texto'); if (c) c.focus(); } else irAlAsistente(''); });
        pie.appendChild(principal);
      }
      /* la primera vez sale solo: no le quita el foco a lo que la persona esté haciendo */
      abre([cabecera(p.t, p.x), pie], primera && i === 0 ? null : principal);
      if (primera && i === 0) guarda(K_VISTO, hoy());
    }

    /* Tocarle, ya acoplado: «¿Qué necesitas?» */
    function pideAlgo() {
      var campo = el('textarea', 'lwm-campo');
      campo.maxLength = Q_MAX;
      campo.rows = 3;
      campo.placeholder = T('Por ejemplo: «Anula la factura INV00160, el importe está mal».');
      campo.setAttribute('aria-label', T('¿Qué necesitas?'));
      var enviar = function () { irAlAsistente(campo.value.trim()); };
      campo.addEventListener('keydown', function (ev) {
        if (ev.key === 'Enter' && (ev.ctrlKey || ev.metaKey)) { ev.preventDefault(); enviar(); }
      });
      var pie = el('div', 'lwm-pie');
      pie.appendChild(el('span', 'lwm-puntos'));
      pie.appendChild(boton(T('Seguir en el Asistente'), true, enviar));
      var extra = el('div', 'lwm-extra');
      var queSabes = el('button', 'lwm-link', T('¿Qué sabes hacer?'));
      queSabes.type = 'button';
      queSabes.addEventListener('click', function () { presenta(1, false); });
      var esconde = el('button', 'lwm-link', T('Esconder hasta mañana'));
      esconde.type = 'button';
      esconde.addEventListener('click', function () {
        guarda(K_OCULTA, hoy());
        cierra();
        if (!QUIETO && raiz.animate) raiz.animate([{ opacity: 1 }, { opacity: 0, transform: 'translateY(16px)' }], { duration: 220, fill: 'forwards' }).onfinish = function () { raiz.remove(); };
        else raiz.remove();
      });
      var fallo = el('button', 'lwm-link', T('Avisar de un fallo'));
      fallo.type = 'button';
      fallo.addEventListener('click', function () { avisaFallo(false); });
      extra.appendChild(queSabes);
      extra.appendChild(fallo);
      extra.appendChild(esconde);
      abre([cabecera(T('¿Qué necesitas?'), T('Dime de qué se trata —el comprador, la factura o el contrato— y por qué. Lo revisas en el Asistente antes de enviarlo.')), campo, pie, extra], campo);
    }

    /* ── Avisar de un fallo ─────────────────────────────────────────── */
    var K_FALLOS = 'lw-mascota:fallos:' + email;
    var MAX_FALLOS_DIA = 5;
    var punto = null, ofrecido = false, vistoHasta = 0, apagaPunto = null;
    function pendientes() { return (window.__lwFallos || []).filter(function (f) { return f.t > vistoHasta; }); }
    function usados() { var v = (lee(K_FALLOS) || '').split('|'); return v[0] === hoy() ? (+v[1] || 0) : 0; }
    function marca(on) {
      if (on && !punto) {
        punto = el('span', 'lwm-punto');
        yo.appendChild(punto);
        yo.setAttribute('aria-label', T('Abrir el Asistente: ha notado un fallo'));
      } else if (!on && punto) {
        punto.remove(); punto = null;
        yo.setAttribute('aria-label', T('Abrir el Asistente'));
      }
    }
    /* La misma red que panel-web (VIGILA_LEADS_PII y SC_URL): si algo de esto
       llegara, Telegram taparía el aviso entero y quitaría «Al estudio». */
    function limpia(x) {
      return String(x || '')
        .replace(/(https?:\/\/|www\.|t\.me\/)\S*/gi, '[enlace]')
        .replace(/[\w.+-]+@[\w-]+\.[\w.]{2,}/g, '[email]')
        .replace(/(^|[^\d])\+?\d[\d ()./-]{7,}\d(?!\d)/g, '$1[número]')
        /* DNI/NIE/pasaporte: 6+ cifras pegadas a letras («12345678Z», «X1234567L»,
           «AB1234567»). La red de panel-web exige acabar en cifra y se los dejaría
           pasar (consulta de deploy, Legal, 25-sep). */
        .replace(/\b[A-Za-z]{0,3}\d{6,}[A-Za-z]?\b/g, '[documento]');
    }
    function sinCitas(x) {
      return String(x || '').replace(/«[^»]*»/g, '«…»').replace(/“[^”]*”/g, '“…”').replace(/"[^"]*"/g, '"…"');
    }
    function hace(t) {
      var sg = Math.max(0, Math.round((Date.now() - t) / 1000));
      return sg < 90 ? 'hace ' + sg + ' s' : 'hace ' + Math.round(sg / 60) + ' min';
    }
    function navegador() {
      var ua = navigator.userAgent || '', m;
      var n = (m = ua.match(/Edg\/(\d+)/)) ? 'Edge ' + m[1] : (m = ua.match(/Firefox\/(\d+)/)) ? 'Firefox ' + m[1]
        : (m = ua.match(/Chrome\/(\d+)/)) ? 'Chrome ' + m[1] : (m = ua.match(/Version\/(\d+).*Safari/)) ? 'Safari ' + m[1] : 'otro';
      var so = /Windows/.test(ua) ? 'Windows' : /Android/.test(ua) ? 'Android' : /iPhone|iPad/.test(ua) ? 'iOS'
        : /Mac OS/.test(ua) ? 'Mac' : /Linux/.test(ua) ? 'Linux' : '?';
      return n + ' · ' + so + ' · ventana ' + window.innerWidth + ' px · ' + (window.LW_IDIOMA === 'en' ? 'EN' : 'ES');
    }
    /* Lo lee dirección en Telegram: siempre en español, sea cual sea el idioma de la interfaz. */
    function componer(comentario, lista) {
      var herr = String(document.title || '').split(/\s[—·|-]\s/)[0] || 'Intranet';
      var L = ['🐞 FALLO EN LA INTRANET (aviso desde el Asistente)',
        'Herramienta: ' + limpia(herr) + ' (' + location.pathname + ')',
        'Qué hacía: ' + (comentario ? limpia(comentario).slice(0, 800) : '(no lo ha dicho)')];
      if (lista.length) {
        L.push('Lo que notó la intranet:');
        lista.slice(-3).forEach(function (f) {
          var msg = sinCitas(f.msg);   // también en errores de código: un throw puede citar un nombre (Legal, 25-sep)
          L.push('· ' + (f.tipo === 'aviso' ? 'Aviso en pantalla: ' : 'Error de código: ') + limpia(msg).slice(0, 200) + ' (' + hace(f.t) + ')');
        });
      } else {
        L.push('La intranet no registró ningún error: lo ha notado la persona.');
      }
      L.push('Navegador: ' + navegador());
      return L.join('\n').slice(0, 2000);
    }
    function avisaFallo(auto) {
      var lista = pendientes();
      if (usados() >= MAX_FALLOS_DIA) {
        var pie0 = el('div', 'lwm-pie');
        pie0.appendChild(el('span', 'lwm-puntos'));
        pie0.appendChild(boton(T('Ir al Asistente'), true, function () { irAlAsistente(''); }));
        abre([cabecera(T('Hoy ya me has avisado de varios fallos'), T('Por hoy no mando más avisos. Si es urgente, pídelo en el Asistente.')), pie0], null);
        return;
      }
      var campo = el('textarea', 'lwm-campo');
      campo.maxLength = 800;
      campo.rows = 3;
      campo.placeholder = lista.length ? T('¿Qué estabas haciendo? (opcional)') : T('¿Qué ha pasado? Por ejemplo: «al guardar la factura no hace nada».');
      campo.setAttribute('aria-label', lista.length ? T('¿Qué estabas haciendo? (opcional)') : T('¿Qué ha pasado?'));
      var err = el('p', 'lwm-err');
      err.hidden = true;
      err.setAttribute('role', 'alert');
      var pie = el('div', 'lwm-pie');
      pie.appendChild(el('span', 'lwm-puntos'));
      if (auto) pie.appendChild(boton(T('No hace falta'), false, function () { vistoHasta = Date.now(); marca(false); cierra(); }));
      var enviar = boton(T('Avisar al estudio'), true, function () {
        var c = campo.value.trim();
        if (!lista.length && !c) { err.textContent = T('Cuéntame qué ha pasado para poder avisar.'); err.hidden = false; campo.focus(); return; }
        enviar.disabled = true;
        enviar.textContent = T('Enviando…');
        err.hidden = true;
        aut.sb.from('solicitudes_cambio').insert({ accion: 'manual', texto: componer(c, lista) }).select('numero').then(function (r) {
          if (!r || r.error) throw (r && r.error) || new Error('sin respuesta');
          var n = r.data && r.data[0] && r.data[0].numero;
          guarda(K_FALLOS, hoy() + '|' + (usados() + 1));
          vistoHasta = Date.now();
          marca(false);
          abre([cabecera(T('Aviso enviado'), n ? T('Gracias. Queda avisado como SC-%n.', { n: n }) : T('Gracias. Queda avisado.'))], null);
        }).catch(function (e) {
          console.warn('[mascota] aviso de fallo:', e);
          enviar.disabled = false;
          enviar.textContent = T('Avisar al estudio');
          err.textContent = T('No se pudo enviar el aviso. Prueba otra vez en un momento.');
          err.hidden = false;
        });
      });
      pie.appendChild(enviar);
      abre([cabecera(lista.length ? T('Algo ha fallado') : T('Avisar de un fallo'),
        lista.length ? T('Si no ha hecho lo que esperabas, avísame y se lo paso al estudio con los detalles técnicos.')
                     : T('Cuéntame qué ha pasado y se lo paso al estudio.')), campo, err, pie], auto ? null : campo);
    }
    /* Un error de CÓDIGO abre el bocadillo una vez por página; un aviso rojo solo
       marca el punto (muchos son validaciones: «escribe qué necesitas») y el punto
       se apaga solo a los 90 s si no hubo nada peor. */
    function alFallo(f, alArrancar) {
      marca(true);
      clearTimeout(apagaPunto);
      if (!pendientes().some(function (x) { return x.tipo === 'codigo'; })) {
        apagaPunto = setTimeout(function () { if (bur.hidden) { vistoHasta = Date.now(); marca(false); } }, 90000);
      }
      if (f.tipo === 'codigo' && !ofrecido && !alArrancar) {
        ofrecido = true;
        setTimeout(function () { if (bur.hidden && !hayVentana() && raiz.style.visibility !== 'hidden') avisaFallo(true); }, 1200);
      } else {
        baila();
      }
    }
    document.addEventListener('lw:fallo', function (ev) { alFallo(ev.detail || {}, false); });
    // lo apuntado antes de que llegara la mascota: punto, sin bocadillo (la persona ya siguió)
    if (pendientes().length) alFallo(pendientes()[pendientes().length - 1], true);

    yo.addEventListener('click', function (ev) {
      ev.stopPropagation();
      if (!bur.hidden) { cierra(); return; }
      if (punto) { avisaFallo(false); return; }
      if (EN_ASISTENTE) { presenta(1, false); return; }
      pideAlgo();
    });
    bur.addEventListener('click', function (ev) { ev.stopPropagation(); });
    document.addEventListener('click', function () { cierra(); });
    document.addEventListener('keydown', function (ev) {
      if (ev.key === 'Escape' && !bur.hidden) { cierra(); yo.focus(); }
    });

    if (lee(K_VISTO)) return;   // ya se conocen: acoplado y quieto

    /* ── La primera vez: sale de la campana ───────────────────────────── */
    raiz.style.visibility = 'hidden';
    function hayVentana() {
      return !!document.querySelector('#lw-cajon,#lw-editor,.lw-dlg-fondo.abierto,body.v4-nav-abierta,#lw-cargando');   // el velo se retira del DOM al cargar (datos.js)
    }
    var intentos = 0;
    function cuandoToque() {
      if (document.hidden || hayVentana()) {
        if (++intentos > 40) { raiz.style.visibility = ''; return; }   // tras ~1 min, se acopla sin función
        setTimeout(cuandoToque, 1500);
        return;
      }
      sale();
    }
    function sale() {
      var badge = document.querySelector('[data-lw="k-avisos"]');
      var campana = badge ? badge.closest('button') : null;
      var r = campana ? campana.getBoundingClientRect() : null;
      var yr = yo.getBoundingClientRect();
      raiz.style.visibility = '';
      if (QUIETO || !yo.animate || !r || !r.width) {
        if (yo.animate && !QUIETO) yo.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 250 });
        setTimeout(function () { presenta(0, true); }, QUIETO ? 0 : 260);
        return;
      }
      var dx = (r.left + r.width / 2) - (yr.left + yr.width / 2);
      var dy = (r.top + r.height / 2) - (yr.top + yr.height / 2);
      /* 1 · la campana suena */
      campana.animate([
        { transform: 'rotate(0)' }, { transform: 'rotate(-16deg)' }, { transform: 'rotate(13deg)' },
        { transform: 'rotate(-9deg)' }, { transform: 'rotate(5deg)' }, { transform: 'rotate(0)' }
      ], { duration: 650, easing: 'ease-in-out' });
      /* 2 · asoma por debajo de la campana, 3 · baja pegado al borde derecho y aterriza */
      var t = function (x, y, sx, sy) { return 'translate(' + x + 'px,' + y + 'px) scale(' + sx + ',' + (sy == null ? sx : sy) + ')'; };
      var vuelo = yo.animate([
        { transform: t(dx, dy, .15), opacity: 0, offset: 0 },
        { transform: t(dx, dy + 34, .9), opacity: 1, offset: .2, easing: 'cubic-bezier(.3,.7,.4,1)' },
        { transform: t(dx * .15, dy + 60, 1), opacity: 1, offset: .38, easing: 'cubic-bezier(.55,0,.9,.45)' },
        { transform: t(0, 0, .96, 1.05), opacity: 1, offset: .82 },
        { transform: t(0, 0, 1.14, .84), opacity: 1, offset: .88 },
        { transform: t(0, -4, .96, 1.05), opacity: 1, offset: .95 },
        { transform: t(0, 0, 1), opacity: 1, offset: 1 }
      ], { duration: 1500, delay: 380, fill: 'backwards' });
      vuelo.onfinish = function () {
        baila();
        setTimeout(parpadea, 250);
        setTimeout(function () { presenta(0, true); }, 520);
      };
    }
    setTimeout(cuandoToque, 1500);
  }

  function arranca() {
    if (EN_ASISTENTE) rellenaDesdeUrl();
    if (!window.LW_AUTH || typeof window.LW_AUTH.then !== 'function') return;
    window.LW_AUTH.then(function (aut) { monta(aut); })
      .catch(function (e) { /* MUDO A PROPÓSITO: sin sesión resuelta la mascota simplemente no sale; se deja rastro en consola */ console.warn('[mascota]', e); });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', arranca);
  else arranca();
})();
