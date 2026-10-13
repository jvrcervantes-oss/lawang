/* ═══════════════════════════════════════════════════════════════════════════
   Pie de página compartido de la web pública de Lawang — 23-sep-2026
   ═══════════════════════════════════════════════════════════════════════════

   POR QUÉ UN JS Y NO UN INCLUDE. El pedido del owner fue "un pie que sirva ya para
   /modelo y para /investor-deck", comprimido y con el contacto bien destacado. Esas
   dos páginas no comparten nada más: /modelo es PHP con un Tailwind congelado
   (dali-tesla-tw.min.css) y solo en inglés; el deck v2 es HTML estático con su
   propio build (v2.min.css) y traduce EN/ES/ID en el navegador. Un include PHP no
   entra en el deck, y copiar el marcado a las dos es la segunda copia que diverge
   el día que cambie un teléfono. Por eso: una sola fuente, con su propio CSS
   (clases .lwpie-*, no depende de ningún build) y sus tres idiomas dentro.

   USO. En la página:
     <footer data-lw-pie data-wa="https://wa.me/...?text=..." [data-cookies]>
       <span data-pie-nota>Aviso propio de esta página (opcional)</span>
     </footer>
     <script src="/assets/lawang-pie.js?v=..."></script>   ← justo después, SIN defer
   · data-wa      enlace de WhatsApp con el mensaje prellenado de esa página.
   · data-cookies pinta "Cookie preferences" con id="lw-cookies" (solo donde se carga
                  consent.js: un enlace que no abre nada es peor que no tenerlo).
   · [data-pie-nota] se conserva y va a la barra de abajo (el deck lleva ahí el aviso
                  legal de que no es una oferta de valores; /modelo no lleva nada).
   Sin defer a propósito: la página engancha luego sus propios manejadores sobre lo
   que pinta este fichero (#lw-cookies, [data-wa-enlace]).

   DATOS. Fuente única de teléfonos, email y oficina de la web pública: vivían en
   $OFICINA/$TELEFONOS/$EMAIL/$WA_SHOW de modelo/index.php y se retiraron de allí al
   pasar a este fichero. Si cambia un teléfono, cambia AQUÍ.
   ═══════════════════════════════════════════════════════════════════════════ */
(function () {
  'use strict';

  var DATOS = {
    wa: { num: '6281138319862', show: '+62 811-3831-9862' },
    tels: [
      { show: '+62 811-3830-5240', tel: '+6281138305240' },
      { show: '+62 811-3830-5237', tel: '+6281138305237' }
    ],
    email: 'sales@lawangproperties.com',
    oficina: 'Jl. Gn. Tangkuban Perahu No.145, 2nd Floor, Padangsambian Klod, Denpasar, Bali 80117',
    mapa: 'https://www.google.com/maps/search/?api=1&query=' +
      encodeURIComponent('Jl. Gn. Tangkuban Perahu No.145, Padangsambian Klod, Denpasar, Bali 80117')
  };

  /* Textos. La línea de marca es un SUBCONJUNTO literal de la que ya publicaba el pie
     de /modelo ("Registered Developer & Property Advisory"): no se añade ninguna
     afirmación nueva. Lo de "EPC a precio fijo" e "IVA incluido" se queda fuera porque
     es de villas y este pie también sale en un deck de parcelas en Hak Sewa. */
  var T = {
    en: { marca: 'Registered developer & property advisory in Bali.',
          horario: 'We reply during Bali hours (WITA).',
          lineas: 'Direct lines', oficina: 'Bali office',
          legal: 'Legal & privacy', cookies: 'Cookie preferences',
          copy: '© 2026 Lawang Tropical Properties. All rights reserved.' },
    es: { marca: 'Promotora registrada y asesoría inmobiliaria en Bali.',
          horario: 'Respondemos en horario de Bali (WITA).',
          lineas: 'Líneas directas', oficina: 'Oficina en Bali',
          legal: 'Aviso legal y privacidad', cookies: 'Preferencias de cookies',
          copy: '© 2026 Lawang Tropical Properties. Todos los derechos reservados.' },
    id: { marca: 'Pengembang terdaftar & konsultan properti di Bali.',
          horario: 'Kami membalas pada jam kerja Bali (WITA).',
          lineas: 'Saluran langsung', oficina: 'Kantor Bali',
          legal: 'Legal & privasi', cookies: 'Preferensi cookie',
          copy: '© 2026 Lawang Tropical Properties. Hak cipta dilindungi.' },
    // fr: solo lo usa /partners/fr/ (25-sep-2026). Sin aviso legal en francés: cae al inglés.
    fr: { marca: 'Promoteur enregistré et conseil immobilier à Bali.',
          horario: 'Nous répondons aux heures de Bali (WITA).',
          lineas: 'Lignes directes', oficina: 'Bureau à Bali',
          legal: 'Mentions légales et confidentialité', cookies: 'Préférences cookies',
          copy: '© 2026 Lawang Tropical Properties. Tous droits réservés.' }
  };
  // Aviso legal por idioma: /legal-es existe; en bahasa NO se hereda el español
  // (LAW-247), cae al inglés.
  var LEGAL_URL = { en: '/legal', es: '/legal-es', id: '/legal', fr: '/legal' };

  var CSS =
    '.lwpie{background:#F1EBDD;border-top:1px solid #e4e2dd;color:#44483f;font-size:13px;line-height:1.5;padding:28px 24px 96px}' +
    '.lwpie a{color:inherit;text-decoration:none}.lwpie a:hover{color:#314322}' +
    '.lwpie__in{max-width:1400px;margin:0 auto}' +
    '.lwpie__top{display:grid;grid-template-columns:1fr;gap:20px;align-items:center}' +
    '.lwpie__marca img{height:28px;width:auto;display:block}' +
    '.lwpie__marca p{margin:8px 0 0;max-width:30rem}' +
    '.lwpie__lbl{display:block;font-size:10px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:#314322;margin-bottom:4px}' +
    '.lwpie__cont{display:flex;flex-wrap:wrap;gap:12px 28px;align-items:center}' +
    '.lwpie__wa{display:inline-flex;align-items:center;gap:10px;background:#25D366;color:#0b3d25!important;font-weight:700;font-size:15px;padding:12px 20px;border-radius:999px;box-shadow:0 4px 14px rgba(37,211,102,.28);transition:filter .15s,transform .15s;white-space:nowrap}' +
    '.lwpie__wa:hover{filter:brightness(.95);transform:translateY(-1px)}' +
    '.lwpie__wa svg{width:20px;height:20px;flex:none}' +
    '.lwpie__wa small{display:block;font-weight:500;font-size:11px;opacity:.8;line-height:1.2}' +
    // 180px y sin overflow-wrap:anywhere: a 390px el email se partia en "...properties.c / om"
    // (revision responsive 23-sep). Si no caben dos columnas, cada lista va a su fila.
    '.lwpie__lista{flex:1 1 180px;min-width:0}.lwpie__lista a{display:block;font-weight:600;color:#104C4F;padding:4px 0}' +
    '.lwpie__wa{flex:1 1 100%;justify-content:center}' +
    '.lwpie__bar{margin-top:20px;padding-top:14px;border-top:1px solid rgba(68,72,63,.15);display:flex;flex-wrap:wrap;gap:6px 18px;align-items:center;justify-content:space-between;font-size:11.5px;color:rgba(68,72,63,.85)}' +
    '.lwpie__bar nav{display:flex;flex-wrap:wrap;gap:6px 16px}.lwpie__bar nav a{display:inline-block;padding:10px 0}' +
    '.lwpie__nota{flex-basis:100%;order:3;font-size:11px;line-height:1.5}' +
    '@media(min-width:900px){.lwpie{padding:28px 48px 28px}' +
      '.lwpie__top{grid-template-columns:minmax(0,1fr) auto}' +
      '.lwpie__cont{justify-content:flex-end}.lwpie__lista{flex:0 1 auto}.lwpie__wa{flex:0 0 auto}}';

  var SVG_WA = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M17.47 14.38c-.3-.15-1.76-.87-2.03-.97-.27-.1-.47-.15-.67.15-.2.3-.77.97-.94 1.17-.17.2-.35.22-.65.07-.3-.15-1.26-.46-2.4-1.48-.89-.79-1.49-1.77-1.66-2.07-.17-.3-.02-.46.13-.61.13-.13.3-.35.45-.52.15-.17.2-.3.3-.5.1-.2.05-.37-.02-.52-.07-.15-.67-1.62-.92-2.22-.24-.58-.49-.5-.67-.51l-.57-.01c-.2 0-.52.07-.8.37-.27.3-1.04 1.02-1.04 2.48 0 1.46 1.07 2.88 1.22 3.08.15.2 2.1 3.2 5.08 4.49.71.31 1.26.49 1.69.63.71.22 1.36.19 1.87.12.57-.09 1.76-.72 2.01-1.41.25-.7.25-1.29.17-1.41-.07-.12-.27-.2-.57-.35zM12.04 21.5a9.5 9.5 0 0 1-4.84-1.33l-.35-.2-3.6.94.96-3.51-.23-.36a9.49 9.49 0 0 1-1.45-5.05c0-5.24 4.27-9.5 9.52-9.5a9.46 9.46 0 0 1 9.51 9.51c0 5.24-4.27 9.5-9.51 9.5zM20.52 3.49A11.78 11.78 0 0 0 12.04 0C5.46 0 .1 5.36.1 11.94c0 2.1.55 4.16 1.6 5.98L0 24l6.25-1.64a11.92 11.92 0 0 0 5.79 1.47c6.58 0 11.94-5.36 11.94-11.94a11.86 11.86 0 0 0-3.47-8.4z"/></svg>';

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function soloHttp(u) {
    try { var p = new URL(String(u), location.href); return /^https?:$/.test(p.protocol) ? p.href : ''; }
    catch (e) { return ''; }
  }

  function idioma() {
    var h = document.documentElement;
    var l = (h.getAttribute('data-lang') || h.getAttribute('lang') || 'en').slice(0, 2).toLowerCase();
    return T[l] ? l : 'en';
  }

  function pinta(pie) {
    var lang = idioma(), t = T[lang];
    var wa = soloHttp(pie.getAttribute('data-wa')) || ('https://wa.me/' + DATOS.wa.num);
    var nota = pie.querySelector('[data-pie-nota]');
    var logo = pie.getAttribute('data-logo') || '/assets/img/lawang-logo-v3-dark.webp';

    var tels = DATOS.tels.map(function (x) {
      return '<a href="tel:' + esc(x.tel) + '">' + esc(x.show) + '</a>';
    }).join('');

    pie.classList.add('lwpie');
    pie.innerHTML =
      '<div class="lwpie__in">' +
        '<div class="lwpie__top" data-no-i18n>' +
          '<div class="lwpie__marca">' +
            '<img src="' + esc(logo) + '" alt="Lawang Tropical Properties" loading="lazy">' +
            '<p>' + esc(t.marca) + '</p>' +
          '</div>' +
          '<div class="lwpie__cont">' +
            '<a class="lwpie__wa" href="' + esc(wa) + '" target="_blank" rel="noopener" data-wa-enlace>' + SVG_WA +
              '<span>' + esc(DATOS.wa.show) + '<small>' + esc(t.horario) + '</small></span></a>' +
            '<div class="lwpie__lista"><span class="lwpie__lbl">' + esc(t.lineas) + '</span>' + tels +
              '<a href="mailto:' + esc(DATOS.email) + '">' + esc(DATOS.email) + '</a></div>' +
            '<div class="lwpie__lista"><span class="lwpie__lbl">' + esc(t.oficina) + '</span>' +
              '<a href="' + esc(DATOS.mapa) + '" target="_blank" rel="noopener" style="font-weight:500;color:inherit;max-width:16rem">' + esc(DATOS.oficina) + '</a></div>' +
          '</div>' +
        '</div>' +
        '<div class="lwpie__bar">' +
          '<span data-no-i18n>' + esc(t.copy) + '</span>' +
          '<nav data-no-i18n><a href="' + LEGAL_URL[lang] + '">' + esc(t.legal) + '</a>' +
            (pie.hasAttribute('data-cookies') ? '<a href="#" id="lw-cookies">' + esc(t.cookies) + '</a>' : '') +
          '</nav>' +
        '</div>' +
      '</div>';

    // Lo que pinta este fichero va con data-no-i18n (se traduce solo). La nota propia
    // de la pagina NO: la traduce la pagina (el walker del deck, por ejemplo). Se mueve
    // tal cual, nodo incluido: no se re-escribe ni se re-escapa.
    if (nota) {
      nota.className = 'lwpie__nota';
      nota.removeAttribute('hidden');
      pie.querySelector('.lwpie__bar').appendChild(nota);
    }
  }

  /* ═══════════════════════════════════════════════════════════════════════════
     VARIANTE «home» — el pie de la home, para las páginas del menú   13-oct-2026
     ═══════════════════════════════════════════════════════════════════════════
     Pedido del owner: The Land / The Villas (/thecollection y sus fichas), The Soul y
     The Portfolio llevan EL MISMO pie que la home. Antes había tres: el de la home
     escrito a mano en index.html, una copia en portfolio-app.js que ya se había
     desviado (el 13-oct se corrigieron los enlaces de Company en la home y la copia
     siguió con los viejos) y el pie de contacto de arriba en /thesoul y /portfolio.
     Ahora la home también lo pinta desde aquí: una sola fuente.

     USO.
       <footer data-lw-pie="home" [data-cookies]>            ← páginas estáticas
         <span data-pie-nota>Aviso propio (opcional)</span>
       </footer>
       <script src="/assets/lawang-pie.js?v=..."></script>   ← justo después, SIN defer
       · data-sin-fondo  sin fondo ni tótem: en la home los pone section.lw-contact.
       · data-cookies    pinta «Cookie Settings» (solo donde se carga consent.js).
       · [data-pie-nota] se conserva tal cual (nodo incluido) bajo la barra de abajo.
     En plantillas que se repintan (portfolio-app.js): window.lwPieHome({cookies:true})
     devuelve el <footer> como cadena.

     CSS con prefijo propio (.lwh) y su propia tipografía: /thesoul llama 'NK' a la
     Neue Kabel en .woff2 y /thecollection tiene reglas sueltas .lw-ft-*; con los mismos
     .otf que la home el pie mide igual en las cuatro (interlineado 1.6, el que el pie hereda en la home de su sección). */
  var TH = {
    tag:   { en: 'Strategic asset investment, structuring and development in Indonesia. Bali · Sumba.',
             es: 'Inversión, estructuración y desarrollo de activos estratégicos en Indonesia. Bali · Sumba.',
             id: 'Investasi, penataan struktur, dan pengembangan aset strategis di Indonesia. Bali · Sumba.' },
    hPort: { en: 'Portfolio', es: 'Portafolio', id: 'Portofolio' },
    hComp: { en: 'Company',   es: 'Compañía',   id: 'Perusahaan' },
    hDiv:  { en: 'Divisions', es: 'Divisiones', id: 'Divisi' },
    signature:  { en: 'Signature', es: 'Signature', id: 'Signature' },
    land:       { en: 'Land',      es: 'Terrenos',  id: 'Tanah' },
    villas:     { en: 'Villas',    es: 'Villas',    id: 'Villa' },
    resorts:    { en: 'Resorts',   es: 'Resorts',   id: 'Resort' },
    soul:       { en: 'The Soul',       es: 'La Esencia',    id: 'Jiwa' },
    whatwedo:   { en: 'What We Do',     es: 'Qué hacemos',   id: 'Apa yang Kami Lakukan' },
    expedition: { en: 'The Expedition', es: 'La Expedición', id: 'Ekspedisi' },
    choose:     { en: 'Choose your Legacy', es: 'Elige tu legado', id: 'Pilih Warisan Anda' },
    terms:      { en: 'Terms & Conditions', es: 'Términos y Condiciones', id: 'Syarat & Ketentuan' },
    privacy:    { en: 'Privacy Policy',  es: 'Política de Privacidad', id: 'Kebijakan Privasi' },
    cookies:    { en: 'Cookie Settings', es: 'Preferencias de cookies', id: 'Pengaturan Cookie' },
    access:     { en: 'Accessibility',   es: 'Accesibilidad',  id: 'Aksesibilitas' }
  };
  function th(k, lang) { var e = TH[k]; return e[lang] || e.en; }

  var F = '/assets/fonts/NeueKabel-';
  var CSS_HOME =
    "@font-face{font-family:'LWH Kabel';src:url('" + F + "Book.otf') format('opentype');font-weight:400;font-display:swap}" +
    "@font-face{font-family:'LWH Kabel';src:url('" + F + "Regular.otf') format('opentype');font-weight:450;font-display:swap}" +
    "@font-face{font-family:'LWH Kabel';src:url('" + F + "Medium.otf') format('opentype');font-weight:500;font-display:swap}" +
    "@font-face{font-family:'LWH Kabel';src:url('" + F + "Bold.otf') format('opentype');font-weight:700;font-display:swap}" +
    '.lwh{--lwh-fs:clamp(12px, 11.65px + 0.09vw, 13px);--lwh-pd:clamp(22px,5vw,72px);display:block;position:relative;z-index:1;' +
      "overflow:hidden;background:#0A0C09;color:#F5F0E6;font-family:'LWH Kabel','Neue Kabel','Jost',system-ui,sans-serif;" +
      'font-weight:400;font-size:16px;line-height:1.6;text-align:left;padding-bottom:1.8rem}' +
    '.lwh.lwh--sinfondo{background:transparent;overflow:visible}' +
    '.lwh *{box-sizing:border-box}:where(.lwh) h5,:where(.lwh) p{margin:0}' +
    '.lwh__totem{position:absolute;right:-1%;bottom:0;height:clamp(420px,84vh,760px);width:auto;opacity:.07;pointer-events:none;z-index:0}' +
    '.lwh__in{position:relative;z-index:1;max-width:1280px;margin:0 auto;padding:clamp(2.6rem,5vh,3.6rem) var(--lwh-pd) 2rem}' +
    '.lwh__grid{display:grid;grid-template-columns:1.5fr 1fr 1fr 1fr;gap:2.4rem}' +
    '.lwh__logo{height:34px;width:auto;display:block}' +
    '.lwh__sub{font-size:var(--lwh-fs);letter-spacing:.3em;text-transform:uppercase;color:#BEB3A5;margin-top:10px}' +
    '.lwh__tag{font-size:var(--lwh-fs);opacity:.5;line-height:1.7;max-width:34ch;margin-top:14px}' +
    '.lwh__col h5{font-size:var(--lwh-fs);font-weight:600;letter-spacing:.2em;text-transform:uppercase;color:#8F9B7A;margin-bottom:14px}' +
    '.lwh__col a{display:block;font-size:var(--lwh-fs);color:rgba(245,240,230,.72);margin-bottom:10px;transition:color .2s;text-decoration:none}' +
    '.lwh__col a:hover{color:#fff}' +
    '.lwh__bottom{display:flex;justify-content:space-between;align-items:center;gap:1rem;flex-wrap:wrap;position:relative;z-index:1;' +
      'max-width:1280px;margin:2.2rem auto 0;padding:1.5rem var(--lwh-pd) 0;border-top:1px solid rgba(245,240,230,.1)}' +
    '.lwh__copy{font-size:var(--lwh-fs);color:rgba(245,240,230,.4);letter-spacing:.04em}' +
    '.lwh__contact{display:flex;gap:1.6rem;flex-wrap:wrap;align-items:center}' +
    '.lwh__cti{display:inline-flex;align-items:center;gap:10px;font-size:calc(var(--lwh-fs) * 1.3);color:rgba(245,240,230,.82);' +
      'text-decoration:none;letter-spacing:.04em;transition:color .2s}' +
    '.lwh__cti:hover{color:#fff}.lwh__cti svg{width:19.5px;height:19.5px;flex:none;opacity:.9}' +
    '.lwh__legal{display:flex;gap:1.4rem;flex-wrap:wrap}' +
    '.lwh__tc{font-size:var(--lwh-fs);font-weight:600;letter-spacing:.14em;text-transform:uppercase;color:rgba(245,240,230,.72);' +
      'text-decoration:none;cursor:pointer;padding:9px 18px;border:1px solid rgba(245,240,230,.22);border-radius:999px;transition:all .25s}' +
    '.lwh__tc:hover{color:#0A0C09;background:#F5F0E6;border-color:#F5F0E6}' +
    '.lwh__nota{display:block;position:relative;z-index:1;max-width:1280px;margin:1.2rem auto 0;padding:0 var(--lwh-pd);' +
      'font-size:var(--lwh-fs);line-height:1.6;color:rgba(245,240,230,.4)}' +
    '@media(max-width:980px){.lwh__grid{grid-template-columns:1fr 1fr}}' +
    '@media(max-width:560px){.lwh__grid{grid-template-columns:1fr 1fr;gap:1.6rem 1.2rem}.lwh__grid>div:first-child{grid-column:1/-1}' +
      '.lwh__in{padding-top:1.6rem;padding-bottom:1rem}.lwh__tag{margin-top:8px}.lwh__col h5{margin-bottom:8px}.lwh__col a{margin-bottom:6px}' +
      '.lwh__bottom{margin-top:1.2rem;padding-top:1rem;gap:.7rem}.lwh{padding-bottom:1rem}}';

  var SVG_TEL = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true"><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.8 19.8 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.8 19.8 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.13.96.36 1.9.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.9.34 1.85.57 2.81.7A2 2 0 0 1 22 16.92z"/></svg>';
  var SVG_MAIL = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true"><rect x="2" y="4" width="20" height="16" rx="2"/><path d="m2 6 10 7L22 6"/></svg>';

  function cssHome() {
    if (document.getElementById('lwh-css')) return;
    var s = document.createElement('style');
    s.id = 'lwh-css';
    s.textContent = CSS_HOME;
    (document.head || document.documentElement).appendChild(s);
  }

  // «Cookie Settings» sin onclick en línea: un solo manejador delegado, que sirve también
  // al pie que portfolio-app.js repinta.
  var cookiesEnganchado = false;
  function enganchaCookies() {
    if (cookiesEnganchado) return;
    cookiesEnganchado = true;
    document.addEventListener('click', function (e) {
      var a = e.target && e.target.closest ? e.target.closest('[data-lwh-cookies]') : null;
      if (!a) return;
      e.preventDefault();
      if (typeof window.lwConsentReopen === 'function') window.lwConsentReopen();
    });
  }

  function interiorHome(o) {
    var lang = idioma();
    var legal = lang === 'es' ? '/legal-es' : '/legal';   // el aviso en español es el completo (LAW-247)
    // En la home «Choose your Legacy» es su propia sección: ancla local; fuera, a la home.
    var enHome = /^\/(index\.html)?$/.test(location.pathname);
    function a(href, k) { return '<a href="' + esc(href) + '">' + esc(th(k, lang)) + '</a>'; }
    function n(href, txt) { return '<a href="' + esc(href) + '">' + esc(txt) + '</a>'; }
    return (o.sinFondo ? '' : '<img class="lwh__totem" src="/assets/img/tiki-totem.webp" alt="" aria-hidden="true" loading="lazy" draggable="false">') +
      '<div class="lwh__in"><div class="lwh__grid">' +
        '<div><img class="lwh__logo" loading="lazy" src="/assets/img/lawang-logo-v3.webp" alt="Lawang Tropical Properties">' +
          '<div class="lwh__sub">Tropical Properties</div>' +
          '<p class="lwh__tag">' + esc(th('tag', lang)) + '</p></div>' +
        '<div class="lwh__col"><h5>' + esc(th('hPort', lang)) + '</h5>' +
          a('/thecollection#signature', 'signature') + a('/thecollection#land', 'land') +
          a('/thecollection#villas', 'villas') + a('/thecollection#resorts', 'resorts') + '</div>' +
        '<div class="lwh__col"><h5>' + esc(th('hComp', lang)) + '</h5>' +
          a('/thesoul', 'soul') + a('/thesoul#who', 'whatwedo') + a('/#expedition', 'expedition') +
          a(enHome ? '#portfolio' : '/#portfolio', 'choose') + '</div>' +
        '<div class="lwh__col"><h5>' + esc(th('hDiv', lang)) + '</h5>' +
          n('/thecollection', 'Tepi Sungai') + n('/thecollection', 'Balian Hills') +
          n('/thecollection#signature', 'Riverfront II®') + '</div>' +
      '</div></div>' +
      '<div class="lwh__bottom">' +
        '<span class="lwh__copy">© 2026 Lawang Tropical Properties · Indonesia</span>' +
        '<div class="lwh__contact">' +
          '<a class="lwh__cti" href="tel:+' + esc(DATOS.wa.num) + '">' + SVG_TEL + esc(DATOS.wa.show) + '</a>' +
          '<a class="lwh__cti" href="mailto:' + esc(DATOS.email) + '">' + SVG_MAIL + esc(DATOS.email) + '</a>' +
        '</div>' +
        '<div class="lwh__legal">' +
          '<a class="lwh__tc" href="' + legal + '#terms">' + esc(th('terms', lang)) + '</a>' +
          '<a class="lwh__tc" href="' + legal + '#privacy">' + esc(th('privacy', lang)) + '</a>' +
          (o.cookies ? '<a class="lwh__tc" href="#" data-lwh-cookies>' + esc(th('cookies', lang)) + '</a>' : '') +
          '<a class="lwh__tc" href="/accessibility">' + esc(th('access', lang)) + '</a>' +
        '</div>' +
      '</div>';
  }

  // Para plantillas que se repintan enteras (portfolio-app.js): devuelve el <footer>.
  window.lwPieHome = function (o) {
    o = o || {};
    cssHome();
    if (o.cookies) enganchaCookies();
    return '<footer class="lwh' + (o.sinFondo ? ' lwh--sinfondo' : '') + '" data-lw-pie="home" data-no-i18n>' +
      interiorHome(o) + '</footer>';
  };

  function montaHome(pie) {
    var o = { cookies: pie.hasAttribute('data-cookies'), sinFondo: pie.hasAttribute('data-sin-fondo') };
    var nota = pie.querySelector('[data-pie-nota]');
    cssHome();
    if (o.cookies) enganchaCookies();
    pie.classList.add('lwh');
    if (o.sinFondo) pie.classList.add('lwh--sinfondo');
    pie.innerHTML = interiorHome(o);
    // La nota es de la página (la traduce ella): se mueve el nodo, no se reescribe.
    if (nota) { nota.classList.add('lwh__nota'); nota.removeAttribute('hidden'); pie.appendChild(nota); }
  }

  var pies = document.querySelectorAll('[data-lw-pie]');
  for (var i = 0; i < pies.length; i++) {
    if (pies[i].getAttribute('data-lw-pie') === 'home') { montaHome(pies[i]); continue; }
    if (!document.getElementById('lwpie-css')) {
      var st = document.createElement('style');
      st.id = 'lwpie-css';
      st.textContent = CSS;
      document.head.appendChild(st);
    }
    pinta(pies[i]);
  }
})();
