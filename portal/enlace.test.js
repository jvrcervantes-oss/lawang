// enlace.test.js — canje del enlace del portal (?th=) con un supabase falso (LAW-1 S3, 11-oct-2026).
// Comprueba lo que no se ve en pantalla y es caro si falla:
//   · el `th` desaparece de la dirección ANTES de llamar a verifyOtp, y el resto de la dirección se conserva;
//   · verifyOtp va con { token_hash, type: 'email' };
//   · con ?demo no se llama a verifyOtp (y el `th` se quita igual);
//   · caducado (4xx, o respuesta sin sesión) → «pide otro»; red / 5xx / 429 → «no he podido comprobarlo», nunca «pide otro»;
//   · un `th` sin forma de token no llega al servidor;
//   · tras un canje correcto, cargar() corre UNA vez aunque verifyOtp avise SIGNED_IN a los oyentes,
//     y pasado el canje el oyente vuelve a funcionar.
// La página (portal/index.html) usa estas mismas piezas: quitaTh al empezar, canjeaCallado al pulsar «Entrar»,
// callado alrededor de su oyente. El recorrido en navegador real está en la bitácora del encargo (S3).
'use strict';
const E = require('./enlace.js');

let fallos = 0, pruebas = 0;
function ok(c, m) { pruebas++; if (!c) { fallos++; console.error('FALLO:', m); } }
function igual(a, b, m) { ok(JSON.stringify(a) === JSON.stringify(b), m + ' → ' + JSON.stringify(a) + ' ≠ ' + JSON.stringify(b)); }

const TH = 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4'; // 56 hex, como el hashed_token de GoTrue

// Navegador falso: location + history que se reescriben juntos.
function navegador(href) {
  const loc = { href };
  const hist = {
    state: null, llamadas: [],
    replaceState(st, _t, url) { this.llamadas.push(url); loc.href = new URL(url, loc.href).href; },
  };
  return { loc, hist };
}

// Supabase falso. `resp` decide qué contesta verifyOtp; registra la URL en el momento del canje.
function supabaseFalso(nav, resp) {
  const est = { llamadas: 0, urlEnCanje: null, args: null, oyentes: [] };
  const SES = { access_token: 'x', user: { app_metadata: { portal: true } } };
  const sb = {
    auth: {
      onAuthStateChange(fn) { est.oyentes.push(fn); return { data: { subscription: { unsubscribe() {} } } }; },
      verifyOtp(args) {
        est.llamadas++; est.urlEnCanje = nav.loc.href; est.args = args;
        if (resp === 'lanza') return Promise.reject(Object.assign(new Error('Failed to fetch'), { name: 'AuthRetryableFetchError', status: 0 }));
        if (resp === 'ok') {
          est.oyentes.forEach((fn) => fn('SIGNED_IN', SES));   // como auth-js: avisa antes de devolver
          return Promise.resolve({ data: { user: SES.user, session: SES }, error: null });
        }
        if (resp === 'sin_sesion') return Promise.resolve({ data: { user: null, session: null }, error: null });
        return Promise.resolve({ data: { user: null, session: null }, error: resp });
      },
    },
  };
  return { sb, est };
}

(async () => {
  // 1. quitaTh: devuelve el token, lo quita de la barra y conserva el resto (otros parámetros y el # de sección).
  {
    const nav = navegador('https://lawangproperties.com/portal/?lang=en&th=' + TH + '#/facturas');
    const th = E.quitaTh(nav.loc, nav.hist);
    igual(th, TH, 'quitaTh devuelve el token');
    igual(nav.loc.href, 'https://lawangproperties.com/portal/?lang=en#/facturas', 'quitaTh deja la dirección sin th y con el resto');
    ok(!/th=/.test(nav.hist.llamadas.join(' ')), 'replaceState nunca recibe el token');
    const nav2 = navegador('https://lawangproperties.com/portal/#/inicio');
    igual(E.quitaTh(nav2.loc, nav2.hist), null, 'sin th → null');
    igual(nav2.hist.llamadas.length, 0, 'sin th no toca el historial');
  }

  // 2. canje correcto, como lo hace la página: th fuera ANTES de verifyOtp, tipo 'email', cargar() una sola vez.
  {
    const nav = navegador('https://lawangproperties.com/portal/?th=' + TH);
    const { sb, est } = supabaseFalso(nav, 'ok');
    const th = E.quitaTh(nav.loc, nav.hist);              // al empezar el script
    const entrada = { ocupado: true };                    // calla mientras el arranque decide
    let cargas = 0; const vAppOculta = () => true;        // en la página, cargar() deja vApp oculta hasta terminar
    sb.auth.onAuthStateChange(E.callado(entrada, (ev, ses) => {
      if (ev === 'SIGNED_IN' && ses && (ses.user.app_metadata || {}).portal && vAppOculta()) cargas++;
    }));
    entrada.ocupado = false;                              // getSession resuelto → se ofrece el botón
    const r = await E.canjeaCallado(sb, th, entrada);     // pulsa «Entrar»
    if (r.estado === 'ok') cargas++;                      // trasSesion → cargar()
    ok(est.urlEnCanje && !/th=/.test(est.urlEnCanje), 'ok: el th ya no estaba en la dirección cuando se llamó a verifyOtp');
    igual(est.args, { token_hash: TH, type: 'email' }, 'ok: verifyOtp con token_hash y type email');
    igual([r.estado, !!r.ses], ['ok', true], 'ok: estado y sesión');
    igual(cargas, 1, 'ok: cargar() corre exactamente una vez');
    igual(entrada.ocupado, false, 'ok: el oyente se suelta al terminar');
    est.oyentes.forEach((fn) => fn('SIGNED_IN', { user: { app_metadata: { portal: true } } }));   // p. ej. entrar luego con contraseña
    igual(cargas, 2, 'ok: pasado el canje el oyente vuelve a funcionar');
  }

  // 3. caducado / ya usado (403 otp_expired, el que da el GoTrue real) y respuesta sin sesión → «pide otro».
  for (const [nombre, resp] of [
    ['403 otp_expired', { name: 'AuthApiError', status: 403, code: 'otp_expired', message: 'Email link is invalid or has expired' }],
    ['400', { name: 'AuthApiError', status: 400, message: 'x' }],
    ['200 sin sesión', 'sin_sesion'],
  ]) {
    const nav = navegador('https://lawangproperties.com/portal/?th=' + TH);
    const { sb, est } = supabaseFalso(nav, resp);
    const entrada = { ocupado: false };
    const r = await E.canjeaCallado(sb, E.quitaTh(nav.loc, nav.hist), entrada);
    igual([r.estado, r.ses, E.AVISO[r.estado]], ['caducado', null, 'enlace_caducado'], nombre + ' → caducado, pide otro');
    ok(!/th=/.test(est.urlEnCanje), nombre + ': th fuera antes del canje');
    igual(entrada.ocupado, false, nombre + ': el oyente se suelta');
  }

  // 4. errores que NO son «caducado»: sin red (lanza), 500, 502 reintentable, 429 → «no he podido comprobarlo».
  for (const [nombre, resp] of [
    ['sin red', 'lanza'],
    ['500', { name: 'AuthApiError', status: 500, message: 'x' }],
    ['502 reintentable', { name: 'AuthRetryableFetchError', status: 502, message: 'x' }],
    ['429', { name: 'AuthApiError', status: 429, code: 'over_request_rate_limit', message: 'x' }],
  ]) {
    const nav = navegador('https://lawangproperties.com/portal/?th=' + TH);
    const { sb } = supabaseFalso(nav, resp);
    const entrada = { ocupado: false };
    const r = await E.canjeaCallado(sb, E.quitaTh(nav.loc, nav.hist), entrada);
    igual([r.estado, E.AVISO[r.estado]], ['red', 'enlace_red'], 'error ' + nombre + ' → no he podido comprobarlo');
    igual(entrada.ocupado, false, 'error ' + nombre + ': el oyente se suelta');
  }

  // 5. ?demo: el th se quita y verifyOtp no se llama.
  {
    const nav = navegador('https://lawangproperties.com/portal/?demo=1&th=' + TH);
    const { sb, est } = supabaseFalso(nav, 'ok');
    const r = await E.canjea(sb, E.quitaTh(nav.loc, nav.hist), true);
    igual(nav.loc.href, 'https://lawangproperties.com/portal/?demo=1', 'demo: th fuera, demo se queda');
    igual(est.llamadas, 0, 'demo: no se llama a verifyOtp');
    igual(r.estado, 'demo', 'demo: estado demo');
  }

  // 6. th sin forma de token: no llega al servidor, se trata como caducado y también sale de la dirección.
  for (const malo of ['', 'corto', '<script>alert(1)</script>xxxxxxxxxxxx', 'x'.repeat(300)]) {
    const nav = navegador('https://lawangproperties.com/portal/?th=' + encodeURIComponent(malo));
    const { sb, est } = supabaseFalso(nav, 'ok');
    const th = E.quitaTh(nav.loc, nav.hist);
    ok(!E.formatoOk(th), 'th malo (' + malo.slice(0, 12) + '): formatoOk lo rechaza');
    const r = await E.canjea(sb, th, false);
    igual([est.llamadas, r.estado], [0, 'caducado'], 'th malo (' + malo.slice(0, 12) + '): no llega al servidor y es caducado');
    ok(!/th=/.test(nav.loc.href), 'th malo: también se quita de la dirección');
  }
  ok(E.formatoOk(TH), 'un hashed_token real (56 hex) tiene forma de token');

  if (fallos) { console.error(fallos + ' de ' + pruebas + ' comprobaciones fallan'); process.exit(1); }
  console.log('enlace.test.js: ' + pruebas + ' comprobaciones OK');
})().catch((e) => { console.error('FALLO inesperado:', e); process.exit(1); });
