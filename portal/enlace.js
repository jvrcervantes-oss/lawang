/* enlace.js — entrada al portal con el enlace que manda NUESTRO correo (LAW-1 S3, 11-oct-2026).
   Encargo: encargos/20261011_lawang_portal_enlace_por_correo.md de la agencia.

   Desde LAW-1 las edges `portal-acceso` y `portal-invitar` ya no dejan que el correo gratuito de
   Supabase mande el enlace (~4/h: de 44 compradores con acceso había entrado 1). Generan el enlace
   con `generateLink` y lo mandan por el buzón de Lawang como `/portal/?th=<hashed_token>`. Esta
   página canjea ese `th` con `verifyOtp`. Los enlaces viejos (redirección de GoTrue con
   `#access_token=`) no pasan por aquí: los recoge supabase-js al arrancar, como siempre.

   Cómo, y por qué:
     1. `quitaTh` lo PRIMERO y de forma síncrona: el token sale de la barra y del historial antes
        de que corra nada más del portal, para que no quede en el historial, en una captura ni en
        un «copiar enlace». Se queda solo en memoria. (El `<meta name="referrer"
        content="no-referrer">` de la página cubre la cabecera Referer.)
     2. El canje lo dispara un BOTÓN, no la carga de la página. Los filtros de correo de empresa
        (Microsoft Defender Safe Links y parecidos) abren los enlaces del correo para revisarlos;
        si la página canjeara sola, el filtro gastaría el enlace (es de un solo uso) y el
        comprador vería «caducado» al pulsarlo. Es la salida que da la documentación de Supabase
        (docs/guides/auth/auth-email-templates, «email prefetching»: una página propia con un
        botón que dispara la confirmación). Si falla por red, el token sigue en memoria y el
        mismo botón reintenta.
     3. El botón solo se ofrece después de `getSession()`: el cliente ya ha terminado de arrancar.
        Si no, un arranque que encuentre caducada la sesión guardada en `lw-portal-auth` y la
        borre (`_recoverAndRefresh` → `_removeSession`) podría terminar DESPUÉS del canje y
        borrar la sesión recién creada.
     4. `verifyOtp({ token_hash, type: 'email' })`. Tipo 'email' y no 'magiclink': en GoTrue
        (supabase/auth, internal/api/verify.go → verifyTokenHash) 'magiclink' busca solo el
        token de recuperación y 'email' busca el de confirmación Y el de recuperación.
        `generateLink({type:'magiclink'})` sobre una cuenta que existe rellena el de
        recuperación (internal/api/mail.go → adminGenerateLink), así que hoy valen los dos;
        'email' sigue valiendo si GoTrue convierte el enlace en uno de alta, y es el que usa la
        guía oficial para canjear un token_hash (docs/guides/auth/auth-email-passwordless).
        Lo admite auth-js 2.110.9 (`EmailOtpType`), la versión que carga la página.
     5. `verifyOtp` avisa SIGNED_IN a los oyentes y el oyente del portal llamaría a `cargar()`,
        que luego llama también quien canjea: dos cargas. `callado` envuelve al oyente para que
        calle mientras `entrada.ocupado` (arranque y canje); `canjeaCallado` lo enciende y lo
        apaga alrededor del canje.

   Estados del canje (lo que ve el comprador sale de aquí):
     'demo'       → con `?demo` NO se canjea nada (el cliente es falso); el `th` se quita igual.
     'ok'         → sesión creada (va en `ses`).
     'caducado'   → el servidor dijo que no (4xx: caducado, ya usado, inválido), contestó sin
                    sesión (el token ya está gastado), o el `th` no tiene forma de token:
                    «el enlace ha caducado o ya se usó: pide otro», sin más pistas.
     'red'        → no se ha podido preguntar (sin red, 5xx, 429 por exceso de peticiones): NO se
                    dice «pide otro», porque pedir otro invalida el que tiene y quizá sigue
                    valiendo; el botón reintenta. «No he podido mirar» se ve distinto de
                    «caducado».

   Se prueba en node con enlace.test.js. */
(function (root) {
  'use strict';

  var TIPO = 'email';
  // El hashed_token de GoTrue es hex (sha224, 56 caracteres). Margen amplio por si cambia, pero
  // nada que no tenga forma de token llega al servidor.
  var FORMATO = /^[A-Za-z0-9_-]{16,256}$/;

  /* Quita `th` de la dirección (barra e historial) y lo devuelve; null si no venía.
     El resto de la dirección (otros parámetros como `demo`, el # de sección) se conserva. */
  function quitaTh(loc, hist) {
    var u;
    try { u = new URL(loc.href); }
    catch (e) { return null; /* MUDO A PROPOSITO: sin URL legible no hay `th` que canjear; el arranque sigue como siempre */ }
    if (!u.searchParams.has('th')) return null;
    var th = u.searchParams.get('th') || '';
    u.searchParams.delete('th');
    try { hist.replaceState(hist.state, '', u.pathname + u.search + u.hash); }
    catch (e) { /* MUDO A PROPOSITO: si el navegador no deja reescribir la barra se sigue igual; al canjearlo, un token usado en la barra ya no abre nada */ }
    return th;
  }

  function formatoOk(th) { return typeof th === 'string' && FORMATO.test(th); }

  /* Error de auth-js → 'caducado' (el servidor dijo que no) o 'red' (no se pudo preguntar). */
  function clasifica(error) {
    if (!error) return 'red';
    var st = typeof error.status === 'number' ? error.status : 0;
    if (error.name === 'AuthRetryableFetchError' || st === 0 || st === 429 || st >= 500) return 'red';
    if (st >= 400) return 'caducado';
    return 'red';
  }

  /* Canjea el `th`. Nunca rechaza: resuelve { estado, ses }. */
  function canjea(sb, th, demo) {
    if (demo) return Promise.resolve({ estado: 'demo', ses: null });
    if (!formatoOk(th)) return Promise.resolve({ estado: 'caducado', ses: null });
    return Promise.resolve()
      .then(function () { return sb.auth.verifyOtp({ token_hash: th, type: TIPO }); })
      .then(function (r) {
        if (r && r.error) return { estado: clasifica(r.error), ses: null };
        var ses = (r && r.data && r.data.session) || null;
        return { estado: ses ? 'ok' : 'caducado', ses: ses };
      }, function (e) { return { estado: clasifica(e), ses: null }; });
  }

  /* Canje con el oyente de onAuthStateChange callado mientras dura. */
  function canjeaCallado(sb, th, entrada) {
    entrada.ocupado = true;
    return canjea(sb, th, false).then(function (r) { entrada.ocupado = false; return r; });
  }

  /* Envuelve el oyente de onAuthStateChange: calla mientras `entrada.ocupado`. */
  function callado(entrada, fn) {
    return function (ev, ses) { if (!entrada.ocupado) fn(ev, ses); };
  }

  var AVISO = { caducado: 'enlace_caducado', red: 'enlace_red' };

  var api = { TIPO: TIPO, AVISO: AVISO, quitaTh: quitaTh, formatoOk: formatoOk, clasifica: clasifica, canjea: canjea, canjeaCallado: canjeaCallado, callado: callado };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.LW_ENLACE = api;
})(typeof window !== 'undefined' ? window : this);
