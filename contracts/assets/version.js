/* ¿Esta pestaña ejecuta el código de hoy? — LAW-386, 27-sep-2026 (aprobado por el owner).

   POR QUÉ EXISTE. Una pestaña abierta desde antes de un despliegue sigue ejecutando el código de
   entonces. El 26-sep una comercial tenía el generador abierto desde antes del «guardar por el
   servidor»: su pestaña hizo el PATCH directo a `contratos` que ya estaba revocado, la base dijo 403
   y la pantalla le contestó «No tienes permiso para guardar este contrato». Mentira: le faltaba
   recargar. Una pantalla vieja tiene que SABERLO y decirlo, no fallar con un mensaje que engaña.

   CÓMO. `tools/sella_assets.py` escribe en cada página de la suite una huella
   `<meta name="lw-version" content="H">`: el hash de la propia página, que lleva dentro los `?v=`
   de todo lo que carga, así que cambia justo cuando cambia su código (inline o assets). Aquí se
   pide la página otra vez al servidor, sin caché, y se compara su huella con la del DOM.
     · Cuándo: al volver a la pestaña (máx. 1 vez cada 5 min) y cuando una petición a Supabase
       vuelve 401/403/404 — guard.js emite el evento `lw:version-vieja` (sospecha, no certeza).
     · Si no cuadra: SEGUNDA lectura a los 30 s (el `git pull` del servidor tarda unos segundos: no se
       pide recargar a mitad de un despliegue) y solo entonces la banda con «Recargar».
     · NUNCA recarga sola: se perdería lo que la persona tenga a medias. Si ya recargó para ir a
       esa huella y sigue sin cuadrar (caché de algún sitio), no insiste.
     · Sin huella, 404, sin red o respuesta rara: silencio para la persona, pero `console.info` —
       una comprobación que no ha podido mirar lo dice, no se hace pasar por «todo bien».

   LÍMITES (escritos en contexto/suite_lawang.md). Solo protege pestañas abiertas DESPUÉS de que
   este fichero se publicara: la pestaña del 26-sep no lo tenía. Y el orden importa: primero se
   publica el front (cambia la huella), después se revoca en la base.

   Carga sin `defer`, detrás de instancia.js, en todas las páginas de la suite (portal y firma
   del comprador incluidos: el texto es neutro, sin «intranet»). En la página que pierde trabajo
   al recargar (el generador), la etiqueta lleva `data-pierde-al-recargar` y la banda lo avisa.
   `decide()` es pura y la prueba contracts/assets/version.test.js. */
(function (raiz) {
  'use strict';

  var HUELLA_RE = /<meta name="lw-version" content="([0-9a-f]+)">/;

  function extrae(html) {
    var m = HUELLA_RE.exec(String(html || ''));
    return m ? m[1] : null;
  }

  /* Estado: { pendiente: H leída una vez y sin confirmar, recargue: H a la que ya se recargó,
     mostrada: banda puesta }. Evento: { local, remota } de una lectura (null = no se pudo).
     Devuelve { accion, estado } con accion ∈ nada | desconocido | confirmar | mostrar | callar. */
  function decide(estado, ev) {
    var s = { pendiente: estado.pendiente || null, recargue: estado.recargue || null, mostrada: !!estado.mostrada };
    if (s.mostrada) return { accion: 'nada', estado: s };
    if (!ev.local || !ev.remota) { s.pendiente = null; return { accion: 'desconocido', estado: s }; }
    if (ev.local === ev.remota) { s.pendiente = null; return { accion: 'nada', estado: s }; }
    if (s.recargue === ev.remota) { s.pendiente = null; return { accion: 'callar', estado: s }; }
    if (s.pendiente === ev.remota) { s.pendiente = null; s.mostrada = true; return { accion: 'mostrar', estado: s }; }
    s.pendiente = ev.remota;
    return { accion: 'confirmar', estado: s };
  }

  var TEXTOS = {
    es: { msg: 'Hay una versión nueva de esta página. Recárgala para seguir (Ctrl/Cmd+Shift+R).',
          pierde: 'Antes, guarda o copia lo que tengas a medias: al recargar se pierde lo que no esté guardado.',
          boton: 'Recargar' },
    en: { msg: 'There is a new version of this page. Reload it to continue (Ctrl/Cmd+Shift+R).',
          pierde: 'First save or copy anything unfinished: reloading loses whatever is not saved.',
          boton: 'Reload' }
  };

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = { decide: decide, extrae: extrae, TEXTOS: TEXTOS };
  }
  if (!raiz || !raiz.document || raiz.lwVersion) return;

  var doc = raiz.document;
  var CADA_MS = 5 * 60 * 1000, SEGUNDA_MS = 30 * 1000, TRAS_ERROR_MS = 60 * 1000;
  var CLAVE = 'lw_version_recargue';
  var yo = doc.currentScript;
  var pierde = !!(yo && yo.hasAttribute('data-pierde-al-recargar'));
  var bilingue = !!(yo && yo.hasAttribute('data-bilingue'));
  var metaLocal = doc.querySelector('meta[name="lw-version"]');
  var local = metaLocal ? metaLocal.getAttribute('content') : null;
  var estado = { pendiente: null, recargue: null, mostrada: false };
  var ultima = Date.now(), ultimaError = 0, enCurso = null, segunda = null;

  function info(m) { try { console.info('[version] ' + m); } catch (e) { /* MUDO A PROPOSITO: sin consola no hay a quién decirlo */ } }

  try {
    var r = JSON.parse(raiz.sessionStorage.getItem(CLAVE) || 'null');
    if (r && r.ruta === raiz.location.pathname) {
      if (r.h === local) raiz.sessionStorage.removeItem(CLAVE);   // la recarga trajo lo nuevo
      else estado.recargue = r.h;
    }
  } catch (e) { /* MUDO A PROPOSITO: sin sessionStorage solo se pierde el «no insistir»; la banda sigue funcionando */ }

  if (!local) info('esta página no lleva huella lw-version: no puedo saber si su código es el de hoy');

  function lee() {
    var url = raiz.location.pathname + '?lwv=' + Date.now();
    return raiz.fetch(url, { cache: 'no-store', credentials: 'same-origin' }).then(function (res) {
      if (!res.ok) { info('no he podido comprobar la versión (HTTP ' + res.status + ')'); return null; }
      return res.text().then(function (t) {
        var h = extrae(t);
        if (!h) info('la página del servidor no trae huella lw-version: no puedo comparar');
        return h;
      });
    }).then(null, function (e) {
      info('no he podido comprobar la versión (sin red: ' + (e && e.message || e) + ')');
      return null;
    });
  }

  function idioma() {
    var l = raiz.LW_IDIOMA || (doc.documentElement.getAttribute('lang') || 'es').slice(0, 2);
    return TEXTOS[l] ? l : 'es';
  }

  function banda(remota) {
    if (doc.getElementById('lw-version-banda')) return;
    var idiomas = bilingue ? ['es', 'en'] : [idioma()];
    var b = doc.createElement('div');
    b.id = 'lw-version-banda';
    b.setAttribute('role', 'alert');
    b.style.cssText = 'position:fixed;left:0;right:0;bottom:0;z-index:2147483646;display:flex;flex-wrap:wrap;' +
      'align-items:center;justify-content:center;gap:12px;padding:12px 16px;background:#104C4F;color:#F5F0E6;' +
      'font:500 14px/1.4 system-ui,-apple-system,Segoe UI,sans-serif;box-shadow:0 -2px 12px rgba(0,0,0,.18)';
    var txt = doc.createElement('div');
    txt.style.cssText = 'max-width:720px';
    idiomas.forEach(function (l, i) {
      var p = doc.createElement('div');
      p.textContent = TEXTOS[l].msg + (pierde ? ' ' + TEXTOS[l].pierde : '');
      if (i) p.style.opacity = '.85';
      txt.appendChild(p);
    });
    var btn = doc.createElement('button');
    btn.type = 'button';
    btn.textContent = idiomas.map(function (l) { return TEXTOS[l].boton; }).join(' / ');
    btn.style.cssText = 'flex:none;cursor:pointer;border:0;border-radius:999px;padding:8px 18px;background:#F5F0E6;' +
      'color:#104C4F;font:600 14px/1 system-ui,-apple-system,Segoe UI,sans-serif';
    btn.addEventListener('click', function () {
      try { raiz.sessionStorage.setItem(CLAVE, JSON.stringify({ ruta: raiz.location.pathname, h: remota })); }
      catch (e) { /* MUDO A PROPOSITO: sin sessionStorage se recarga igual; solo no se recordará */ }
      raiz.location.reload();
    });
    b.appendChild(txt);
    b.appendChild(btn);
    (doc.body || doc.documentElement).appendChild(b);
  }

  function aplica(remota) {
    var d = decide(estado, { local: local, remota: remota });
    estado = d.estado;
    if (d.accion === 'confirmar') {
      clearTimeout(segunda);
      segunda = setTimeout(function () { revisa(true); }, SEGUNDA_MS);
    } else if (d.accion === 'mostrar') {
      banda(remota);
    } else if (d.accion === 'callar') {
      info('ya se recargó para ir a ' + remota + ' y la página sigue siendo ' + local + ': no insisto (¿caché intermedia?)');
    }
    return d.accion;
  }

  function revisa(forzada) {
    if (!local || estado.mostrada) return Promise.resolve('nada');
    if (enCurso) return enCurso;
    if (!forzada && Date.now() - ultima < CADA_MS) return Promise.resolve('nada');
    ultima = Date.now();
    enCurso = lee().then(aplica).then(function (a) { enCurso = null; return a; },
      function (e) { enCurso = null; info('fallo al comprobar: ' + (e && e.message || e)); return 'desconocido'; });
    return enCurso;
  }

  /* Una sola lectura, para quien necesita decidir un mensaje YA (el catch de guardado del
     generador): 'vieja' | 'igual' | 'desconocido'. No espera la segunda lectura —para el TEXTO
     de un error basta una—, pero sí la pide para la banda. Con tope de tiempo: un mensaje de
     error no puede quedarse esperando a la red. */
  function comprueba(msTope) {
    if (!local) return Promise.resolve('desconocido');
    var tope = new Promise(function (ok) { setTimeout(function () { ok(undefined); }, msTope || 5000); });
    return Promise.race([lee(), tope]).then(function (remota) {
      if (remota === undefined) { info('la comprobación de versión no contestó a tiempo'); return 'desconocido'; }
      if (!remota) return 'desconocido';
      if (remota === local) return 'igual';
      // Ya se recargó para ir a esta huella y la página sigue siendo la vieja (caché intermedia):
      // decir «recárgala» otra vez no lo arregla y taparía la causa real. Mensaje de siempre.
      if (estado.recargue === remota) { info('ya se recargó para ir a ' + remota + ': no culpo a la versión'); return 'desconocido'; }
      if (!estado.mostrada && estado.recargue !== remota) {
        estado.pendiente = remota;   // la primera lectura ya está hecha: a los 30 s se confirma
        clearTimeout(segunda);
        segunda = setTimeout(function () { revisa(true); }, SEGUNDA_MS);
      }
      return 'vieja';
    });
  }

  doc.addEventListener('visibilitychange', function () { if (doc.visibilityState === 'visible') revisa(false); });
  raiz.addEventListener('focus', function () { revisa(false); });
  raiz.addEventListener('lw:version-vieja', function () {
    if (Date.now() - ultimaError < TRAS_ERROR_MS) return;
    ultimaError = Date.now();
    revisa(true);
  });

  try {
    Object.defineProperty(raiz, 'lwVersion', { value: Object.freeze({ comprueba: comprueba, revisa: revisa }),
      writable: false, configurable: false, enumerable: true });
  } catch (e) { /* MUDO A PROPOSITO: cargado dos veces; la primera ya lo publicó */ }
})(typeof window !== 'undefined' ? window : null);
