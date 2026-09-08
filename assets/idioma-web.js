/* ═══════════════════════════════════════════════════════════════════════════
   Idioma de la WEB PÚBLICA de Lawang — EN / ES / ID (bahasa).   8-sep-2026
   ═══════════════════════════════════════════════════════════════════════════

   POR QUÉ EXISTE. El selector de idioma llevaba meses en la home siendo una
   fachada: cambiaba `<html lang>`, guardaba la elección y no traducía una sola
   palabra — el propio código lo admitía («la traducción real del contenido aún
   no está cableada»). Y `thecollection.php` tenía un diccionario de 167 claves
   con el español YA escrito al 100%, pero arrancaba fijo en inglés y no leía la
   elección de la home: ese español estaba pagado y era inalcanzable.

   FUENTE ÚNICA de la elección de idioma en el sitio público. Namespaced a
   propósito: `lawang_lang` es la clave que la home ya usaba y la que
   `contracts/assets/idioma.js` documenta como «la del index.html público». NO
   se toca `lawang_idioma_ui` (intranet) ni `lw_portal_lang` (portal del
   comprador): son otros sistemas y compartir clave sería leer el valor de otro
   sin querer. El valor se valida SIEMPRE contra la lista conocida — nunca se
   confía en lo que haya en localStorage tal cual.

   SIN `defer` a propósito, y en <head>: tiene que resolver el idioma antes de
   que el navegador pinte, o el usuario ve un destello de inglés. Mismo motivo
   que `contracts/assets/idioma.js`.

   ───────────────────────────────────────────────────────────────────────────
   ⚠️ GLOSARIO QUE NO SE TRADUCE (revisión previa de Legal, 8-sep-2026)
   ───────────────────────────────────────────────────────────────────────────
   `freehold`, `leasehold`, `HGB`, `hak sewa`, `hak pakai`, `PT PMA` se dejan
   en el término de origen. NO es pereza: `freehold → hak milik` es la
   traducción literal correcta y jurídicamente letal — Hak Milik es solo para
   ciudadanos indonesios y el art. 26(2) UUPA declara NULO DE PLENO DERECHO
   cualquier acto que lo transfiera a un extranjero. Una ficha que en inglés
   dice «freehold» (= HGB corporativo vía PT PMA) y en bahasa dijera «hak
   milik» estaría ofreciendo por escrito, en el idioma del regulador, el patrón
   nominee que el estudio tiene como alerta permanente.
   Si hace falta glosar un término, lo redacta Legal — nunca un diccionario.
   ─────────────────────────────────────────────────────────────────────────── */
(function () {
  var IDIOMAS = ['en', 'es', 'id'];
  var CLAVE   = 'lawang_lang';
  var NOMBRE  = { en: 'English', es: 'Español', id: 'Bahasa' };

  function valida(v) { return IDIOMAS.indexOf(v) !== -1 ? v : null; }

  // ── Resolución: ?lang= manda sobre lo guardado ────────────────────────────
  // El parámetro existe para que un enlace sea COMPARTIBLE y para que un
  // anuncio pueda apuntar a la página en el idioma de su creatividad. Sin él,
  // la elección solo vive en el navegador de quien la hizo.
  var porUrl = null;
  try {
    var m = /[?&]lang=([a-zA-Z-]{2,5})/.exec(location.search);
    if (m) porUrl = valida(m[1].toLowerCase().slice(0, 2));
  } catch (e) {}

  var guardado = null;
  try { guardado = valida(localStorage.getItem(CLAVE)); } catch (e) {}

  var LANG = porUrl || guardado || 'en';
  if (porUrl && porUrl !== guardado) {
    try { localStorage.setItem(CLAVE, porUrl); } catch (e) {}
  }

  window.LW_LANG = LANG;

  // ── Se marca la raíz YA, antes de pintar ──────────────────────────────────
  // `data-lang` es el gancho de CSS para el cambio de tipografía en español
  // (ver más abajo) y para el velo antidestello. `lang` es lo que leen el
  // lector de pantalla y el corrector del navegador.
  var raiz = document.documentElement;
  raiz.setAttribute('lang', LANG);
  raiz.setAttribute('data-lang', LANG);

  // ── Velo antidestello ─────────────────────────────────────────────────────
  // El HTML servido está en inglés: sin esto, quien navega en ES/ID ve el
  // inglés un instante antes de que se aplique el diccionario. Se usa
  // `visibility` y no `display` para que NO haya salto de maquetación, y solo
  // en ES/ID: en inglés no se oculta nada y el primer pintado no paga nada.
  // Failsafe obligatorio: si el diccionario falla, se destapa igual a los
  // 1200 ms. Una página en blanco es peor que una página en inglés.
  if (LANG !== 'en') {
    var velo = document.createElement('style');
    velo.id = 'lw-velo-idioma';
    velo.textContent = 'html[data-lang]:not([data-i18n-listo]) body{visibility:hidden}';
    (document.head || raiz).appendChild(velo);
    // `if` obligatorio: sin él, el failsafe se dispara igualmente a los 1200 ms y
    // PISA la marca de «traducido» con «timeout», así que desde fuera ya no se
    // puede distinguir una traducción que funcionó de una que se rescató sola.
    // Es la señal con la que se verifica la página; tiene que decir la verdad.
    setTimeout(function () {
      if (!raiz.hasAttribute('data-i18n-listo')) raiz.setAttribute('data-i18n-listo', 'timeout');
    }, 1200);
  }

  // ── Cambio de tipografía en español ───────────────────────────────────────
  // MEDIDO con fontTools sobre los .otf del repo: `The Seasons` (la serif de
  // display) tiene 97 glifos, solo ASCII — le faltan á é í ó ú ñ Á É Í Ó Ú Ñ
  // ¿ ¡ ü Ü. Como va PRIMERA en la pila, el navegador hace fallback por glifo:
  // «Diseño» saldría con «Dise» en una tipografía y «ñ» en otra, dentro de la
  // misma palabra. `Neue Kabel` (sans, 497 glifos) está limpia y el bahasa no
  // se ve afectado (ortografía ASCII), así que esto es SOLO para español.
  // ⚠️ INTERINO, no la solución: The Seasons es una demo de fonnts.com que ya
  // corrompe `& - + 4` en cualquier idioma. La solución es comprar la licencia
  // — pendiente LAW-18, decisión de gasto del owner.
  // Se inyecta SIEMPRE, no solo si la pagina nace en español. Sus reglas ya van
  // gateadas por `html[data-lang="es"]`, asi que en EN e ID no pintan nada — y en
  // cambio, condicionarlo dejaba vivo el bug original en un camino entero:
  // `thecollection` cambia de idioma SIN recargar (se repinta sola), asi que quien
  // entraba en ingles y pulsaba Español obtenia texto español dibujado con The
  // Seasons, que no tiene acentos. Justo lo que motivo todo esto.
  {
    var tip = document.createElement('style');
    tip.id = 'lw-tipografia-es';
    // ⚠️ Las dos páginas declaran su serif en SITIOS distintos y eso decide la
    // especificidad que hace falta: `thecollection.php` la pone en `:root`
    // (l.196) pero `index.html` la pone en `#content-sections` (l.895), que es
    // un descendiente — una custom property redeclarada ahí GANA a la heredada
    // de `html`, así que un override solo en la raíz no llegaría y los acentos
    // seguirían rotos. Se cubren los dos casos a propósito.
    tip.textContent =
      'html[data-lang="es"]{--cse:"Cormorant Garamond",Georgia,serif;' +
      '--serif:"Cormorant Garamond",Georgia,serif}' +
      'html[data-lang="es"] #content-sections{--cse:"Cormorant Garamond",Georgia,serif}';
    (document.head || raiz).appendChild(tip);
  }

  // ── API ───────────────────────────────────────────────────────────────────
  window.lwSetLang = function (code) {
    var v = valida(code);
    if (!v || v === LANG) return;
    try { localStorage.setItem(CLAVE, v); } catch (e) {}
    // Una página que sepa repintarse sola lo dice; el resto recarga, que es la
    // única forma de garantizar que también cambia lo que pinta el servidor.
    if (typeof window.LW_AL_CAMBIAR_IDIOMA === 'function') {
      window.LW_LANG = v;
      raiz.setAttribute('lang', v);
      raiz.setAttribute('data-lang', v);
      window.LW_AL_CAMBIAR_IDIOMA(v);
    } else {
      location.reload();
    }
  };

  /* Traduce contra un diccionario `{clave:{en,es,id}}`. Fallback duro a EN:
     nunca se enseña la clave cruda en pantalla. */
  window.lwT = function (dict, clave) {
    var e = dict && dict[clave];
    if (!e) return clave;
    return (e[LANG] != null && e[LANG] !== '') ? e[LANG] : e.en;
  };

  /* Marca el nodo cuando cae al inglés estando la página en otro idioma.
     No es cosmética: WCAG 3.1.2 (Language of Parts) exige que un fragmento en
     otro idioma lo declare, y `accessibility.html` afirma perseguir el nivel
     AA. Lo pidió Legal en la revisión previa. */
  function marcaFallback(el, entrada) {
    if (LANG !== 'en' && (entrada[LANG] == null || entrada[LANG] === '')) {
      el.setAttribute('lang', 'en');
    } else if (el.getAttribute('lang') === 'en') {
      el.removeAttribute('lang');
    }
  }

  /* Aplica el diccionario a la página e inyecta el selector.
       data-i18n="clave"            → textContent
       data-i18n-html="clave"       → innerHTML (para copy con <b>, <br>…)
       data-i18n-attr="attr:clave"  → atributo (aria-label, placeholder, title…)
     `opts.host` es el selector CSS del contenedor donde va el desplegable. */
  window.lwLangInit = function (dict, opts) {
    opts = opts || {};
    window.LW_DICT = dict;

    function aplica() {
      var n, i, els;

      els = document.querySelectorAll('[data-i18n]');
      for (i = 0; i < els.length; i++) {
        n = els[i];
        var k = n.getAttribute('data-i18n');
        if (dict[k]) { n.textContent = window.lwT(dict, k); marcaFallback(n, dict[k]); }
      }

      els = document.querySelectorAll('[data-i18n-html]');
      for (i = 0; i < els.length; i++) {
        n = els[i];
        var kh = n.getAttribute('data-i18n-html');
        if (dict[kh]) { n.innerHTML = window.lwT(dict, kh); marcaFallback(n, dict[kh]); }
      }

      els = document.querySelectorAll('[data-i18n-attr]');
      for (i = 0; i < els.length; i++) {
        n = els[i];
        var pares = n.getAttribute('data-i18n-attr').split(';');
        for (var j = 0; j < pares.length; j++) {
          var p = pares[j].split(':');
          if (p.length === 2 && dict[p[1]]) n.setAttribute(p[0].trim(), window.lwT(dict, p[1].trim()));
        }
      }

      if (opts.host) montaSelector(opts.host);
      if (typeof opts.despues === 'function') opts.despues(LANG);

      raiz.setAttribute('data-i18n-listo', '1');
    }

    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', aplica);
    } else {
      aplica();
    }
  };

  /* Selector compartido. Se INYECTA, no se pega en cada página: la web pública
     ya arrastra el pendiente UNI-2 («9 menús en 9 páginas, cero reutilización»)
     y escribirlo a mano en cada landing lo subiría a 12. Quien lo use pasa el
     contenedor; el marcado y el comportamiento viven aquí y en un solo sitio. */
  /* Estilos del selector inyectado. Van AQUÍ y no en una hoja aparte para que
     usar esto sea UNA sola inclusión — si hubiera que acordarse de un segundo
     `<link>`, la landing número cuatro nacería sin él. Todo lo temable sale por
     variable con fallback, porque el cromo de las landings es oscuro y el de la
     home translúcido: la misma pieza tiene que servir a los dos.
     No se pinta hasta que alguien monta el selector. */
  function ponEstilos() {
    if (document.getElementById('lw-lang-css')) return;
    var s = document.createElement('style');
    s.id = 'lw-lang-css';
    s.textContent =
      '.lw-lang{position:relative;display:inline-flex;flex:none}' +
      '.lw-lang__btn{display:inline-flex;align-items:center;gap:6px;background:none;border:0;cursor:pointer;' +
        'font-family:var(--lw-lang-font,inherit);font-size:var(--lw-lang-size,11px);font-weight:500;' +
        'letter-spacing:.12em;text-transform:uppercase;color:var(--lw-lang-ink,currentColor);' +
        /* 24px es el mínimo táctil que ya exige la puerta de calidad del estudio
           (`target-size`); un selector de 15px sería un fallo conocido nuevo. */
        'min-height:24px;padding:4px 6px;line-height:1;border-radius:999px}' +
      '.lw-lang__btn:hover{opacity:.75}' +
      '.lw-lang__btn:focus-visible{outline:2px solid var(--lw-lang-ink,currentColor);outline-offset:2px}' +
      '.lw-lang__caret{font-size:.8em;opacity:.7}' +
      '.lw-lang__menu{position:absolute;top:calc(100% + 8px);right:0;z-index:120;margin:0;padding:6px;' +
        'list-style:none;min-width:150px;display:none;' +
        'background:var(--lw-lang-bg,#1a160f);border:1px solid var(--lw-lang-line,rgba(255,255,255,.18));' +
        'border-radius:10px;box-shadow:0 12px 34px rgba(0,0,0,.34)}' +
      '.lw-lang__menu.is-open{display:block}' +
      '.lw-lang__menu li{display:flex;align-items:center;min-height:36px;padding:8px 12px;cursor:pointer;' +
        'border-radius:7px;font-family:var(--lw-lang-font,inherit);font-size:13px;' +
        'color:var(--lw-lang-menu-ink,#f5f0e6);white-space:nowrap}' +
      '.lw-lang__menu li:hover{background:var(--lw-lang-hover,rgba(255,255,255,.1))}' +
      '.lw-lang__menu li.is-on{font-weight:700}' +
      /* Se imprime el documento, no el cromo: misma regla que el resto de la
         suite (`imprime_limpio.py`). */
      '@media print{.lw-lang{display:none}}';
    (document.head || raiz).appendChild(s);
  }

  function montaSelector(host) {
    var cont = typeof host === 'string' ? document.querySelector(host) : host;
    if (!cont || cont.querySelector('.lw-lang')) return;
    ponEstilos();

    var wrap = document.createElement('div');
    wrap.className = 'lw-lang';
    var btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'lw-lang__btn';
    btn.setAttribute('aria-haspopup', 'listbox');
    btn.setAttribute('aria-expanded', 'false');
    btn.setAttribute('aria-label', { en: 'Language', es: 'Idioma', id: 'Bahasa' }[LANG]);
    btn.innerHTML = '<span class="lw-lang__cur">' + NOMBRE[LANG] + '</span><span class="lw-lang__caret" aria-hidden="true">▾</span>';

    var ul = document.createElement('ul');
    ul.className = 'lw-lang__menu';
    ul.setAttribute('role', 'listbox');
    for (var i = 0; i < IDIOMAS.length; i++) {
      var c = IDIOMAS[i];
      var li = document.createElement('li');
      li.setAttribute('role', 'option');
      li.setAttribute('data-lang', c);
      li.setAttribute('lang', c);
      li.setAttribute('aria-selected', c === LANG ? 'true' : 'false');
      if (c === LANG) li.className = 'is-on';
      li.textContent = NOMBRE[c];
      ul.appendChild(li);
    }

    wrap.appendChild(btn);
    wrap.appendChild(ul);
    cont.appendChild(wrap);

    function cierra() { ul.classList.remove('is-open'); btn.setAttribute('aria-expanded', 'false'); }
    btn.addEventListener('click', function (e) {
      e.stopPropagation();
      var abierto = ul.classList.toggle('is-open');
      btn.setAttribute('aria-expanded', abierto ? 'true' : 'false');
    });
    ul.addEventListener('click', function (e) {
      var li = e.target.closest ? e.target.closest('li[data-lang]') : null;
      if (li) window.lwSetLang(li.getAttribute('data-lang'));
    });
    document.addEventListener('click', function (e) { if (!wrap.contains(e.target)) cierra(); });
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape') cierra(); });
  }

  window.lwMontaSelectorIdioma = montaSelector;
})();
