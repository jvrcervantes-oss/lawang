/**
 * consent.js — aviso de cookies + carga del Meta Pixel bajo consentimiento.
 *
 * Una sola copia para todas las páginas: index, thecollection y legal.
 *
 * PIXEL_ID activo desde el 29-jul-2026. Si se vacía, este fichero deja de hacer
 * nada —ni banner ni píxel— a propósito: pedir consentimiento para algo que no se
 * carga sería pedirlo en falso, y además molesta al visitante sin motivo.
 * La declaración del píxel en /legal tiene que seguir viva mientras esto tenga valor.
 */
(function () {
  'use strict';

  var PIXEL_ID = '1010261027348950';  // Meta dataset "Lawang" (portfolio PT TEPI SUN GAI)
  var KEY = 'lw-consent';          // 'granted' | 'denied'

  if (!PIXEL_ID) return;

  var stored = null;
  try { stored = localStorage.getItem(KEY); } catch (e) { /* modo privado: se pregunta cada visita */ }

  // ── Carga del píxel ────────────────────────────────────────────────────────
  var loaded = false;
  var queue = [];

  function loadPixel() {
    if (loaded) return;
    loaded = true;

    /* eslint-disable */
    !function(f,b,e,v,n,t,s){if(f.fbq)return;n=f.fbq=function(){n.callMethod?
    n.callMethod.apply(n,arguments):n.queue.push(arguments)};if(!f._fbq)f._fbq=n;
    n.push=n;n.loaded=!0;n.version='2.0';n.queue=[];t=b.createElement(e);t.async=!0;
    t.src=v;s=b.getElementsByTagName(e)[0];s.parentNode.insertBefore(t,s)}
    (window,document,'script','https://connect.facebook.net/en_US/fbevents.js');
    /* eslint-enable */

    window.fbq('init', PIXEL_ID);
    window.fbq('track', 'PageView');

    queue.forEach(function (ev) { window.fbq(ev[2] ? 'trackCustom' : 'track', ev[0], ev[1]); });
    queue = [];
  }

  /**
   * Envía un evento al píxel, o lo guarda hasta que haya consentimiento.
   * Si el visitante rechaza, el evento se descarta: nunca se envía nada sin permiso.
   *   window.lwTrack('Contact', {content_name: 'whatsapp-float'});
   *   window.lwTrack('AbrioCalendario', {...}, true);   // evento propio
   *
   * El tercer argumento manda `trackCustom` en vez de `track`. Un evento propio no se
   * puede llamar como uno estándar de Meta: si se emite `Schedule` cuando en realidad
   * alguien solo ha ABIERTO el calendario, el algoritmo aprende a buscar gente que abre
   * calendarios y los abandona. El nombre del evento es una promesa sobre lo que pasó.
   */
  window.lwTrack = function (name, params, custom) {
    var verbo = custom ? 'trackCustom' : 'track';
    if (loaded) { window.fbq(verbo, name, params); return; }
    if (localStorageGet() === 'granted') { loadPixel(); window.fbq(verbo, name, params); return; }
    if (localStorageGet() === 'denied') return;
    queue.push([name, params, custom]);
  };

  function localStorageGet() {
    try { return localStorage.getItem(KEY); } catch (e) { return stored; }
  }

  function decide(value) {
    stored = value;
    try { localStorage.setItem(KEY, value); } catch (e) { /* sin persistencia: vale para esta página */ }
    var bar = document.getElementById('lw-consent-bar');
    if (bar) bar.remove();
    if (value === 'granted') loadPixel(); else queue = [];
  }

  // ── Banner ─────────────────────────────────────────────────────────────────
  // ponytail: se muestra a todo el mundo, no solo a la UE. Detectar el país en
  // cliente no es fiable (VPN, CDN, IP móvil) y equivocarse hacia el lado de
  // preguntar de más es gratis; hacia el lado de no preguntar es una sanción.
  function showBar() {
    if (document.getElementById('lw-consent-bar')) return;

    var css = document.createElement('style');
    css.textContent =
      '#lw-consent-bar{position:fixed;left:50%;bottom:20px;transform:translateX(-50%);z-index:11000;' +
      'width:min(680px,calc(100vw - 32px));background:#F5F0E6;color:#2E3437;border-radius:14px;' +
      'box-shadow:0 24px 60px -18px rgba(0,0,0,.5);padding:18px 20px;display:flex;gap:16px;' +
      'align-items:center;flex-wrap:wrap;font-family:Jost,system-ui,sans-serif;font-size:14px;line-height:1.6}' +
      '#lw-consent-bar p{margin:0;flex:1 1 320px;color:rgba(46,52,55,.86)}' +
      '#lw-consent-bar a{color:#485B37}' +
      '#lw-consent-bar .lw-cbtns{display:flex;gap:10px;flex:0 0 auto}' +
      '#lw-consent-bar button{font-family:inherit;font-size:12px;font-weight:600;letter-spacing:.12em;' +
      'text-transform:uppercase;padding:10px 20px;border-radius:999px;cursor:pointer;transition:all .25s;border:1px solid}' +
      '#lw-consent-no{background:none;border-color:rgba(46,52,55,.28);color:rgba(46,52,55,.72)}' +
      '#lw-consent-no:hover{border-color:rgba(46,52,55,.6);color:#2E3437}' +
      '#lw-consent-yes{background:#485B37;border-color:#485B37;color:#F5F0E6}' +
      '#lw-consent-yes:hover{background:#3B4B2D;border-color:#3B4B2D}' +
      '@media(max-width:520px){#lw-consent-bar .lw-cbtns{flex:1 1 100%}#lw-consent-bar button{flex:1}}';
    document.head.appendChild(css);

    // Idioma del banner = idioma de la página. La pauta de Meta va a España y en una
    // landing en español un aviso en inglés baja la aceptación: sin aceptación no hay
    // píxel, y sin píxel no hay medición ni públicos. Es dinero, no cortesía.
    var es = (document.documentElement.lang || '').toLowerCase().indexOf('es') === 0;
    var t = es ? {
      p: 'Usamos cookies para medir el rendimiento de nuestra publicidad. No se carga nada hasta que aceptas. ',
      l: 'Política de Privacidad', no: 'Rechazar', si: 'Aceptar'
    } : {
      p: 'We use cookies to measure how our advertising performs. Nothing is loaded until you accept. ',
      l: 'Privacy &amp; Data Policy', no: 'Decline', si: 'Accept'
    };

    var bar = document.createElement('div');
    bar.id = 'lw-consent-bar';
    bar.setAttribute('role', 'dialog');
    bar.setAttribute('aria-label', 'Cookie preferences');
    bar.innerHTML =
      '<p>' + t.p + '<a href="/legal#privacy">' + t.l + '</a></p>' +
      '<div class="lw-cbtns">' +
      '<button type="button" id="lw-consent-no">' + t.no + '</button>' +
      '<button type="button" id="lw-consent-yes">' + t.si + '</button>' +
      '</div>';
    document.body.appendChild(bar);

    document.getElementById('lw-consent-yes').addEventListener('click', function () { decide('granted'); });
    document.getElementById('lw-consent-no').addEventListener('click', function () { decide('denied'); });
  }

  /** Reabre el aviso para cambiar de opinión (enlace "Cookie settings" del pie). */
  window.lwConsentReopen = function () {
    try { localStorage.removeItem(KEY); } catch (e) {}
    stored = null;
    showBar();
  };

  function start() {
    if (stored === 'granted') loadPixel();
    else if (stored !== 'denied') showBar();
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
})();
