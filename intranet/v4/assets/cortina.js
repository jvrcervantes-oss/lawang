/* cortina.js — CORTINA DE PRIVACIDAD para pantallas sensibles de la v4.
 *
 * 23-sep-2026, owner: «quiero más privacidad en "Comisión de administración"
 * por si lo abro con alguien cerca: que pida una contraseña y cuando pasen 15
 * segundos sin uso la pantalla vuelva a pedir la contraseña».
 *
 * Qué ES: una cortina para miradas por encima del hombro. Tapa la pantalla
 * entera (menú, contenido y cualquier cajón abierto) hasta que se escribe la
 * contraseña de la propia cuenta, y vuelve a taparla tras N segundos sin tocar
 * nada o al cambiar de pestaña.
 * Qué NO es: control de acceso. Quién puede abrir la pantalla lo deciden
 * guard.js (data-rol) y la RLS de la base; los datos ya están cargados en la
 * página detrás de la cortina.
 *
 * La contraseña es la de entrar a la intranet: no hay una clave nueva guardada
 * en ningún sitio. Se comprueba con un cliente de Supabase APARTE, sin guardar
 * sesión (persistSession:false), y se cierra al momento: la sesión con la que
 * se está trabajando no se toca ni se renueva.
 *
 * La carga nav.js solo en las pantallas de su lista CORTINA, que también fija
 * los segundos (data-segundos en este <script>). */
(function () {
  'use strict';
  var yo = document.currentScript;
  var SEGUNDOS = Math.max(5, parseInt((yo && yo.getAttribute('data-segundos')) || '15', 10) || 15);
  var MAX_FALLOS = 5, ESPERA_FALLOS = 30;   // tras 5 fallos seguidos, 30 s sin poder probar

  var css = document.createElement('style');
  css.textContent =
    '#lw-cortina{position:fixed;inset:0;z-index:2147483000;background:#0F2E30;display:flex;align-items:center;justify-content:center;padding:16px;font-family:"Neue Kabel",system-ui,sans-serif}' +
    '#lw-cortina[hidden]{display:none}' +
    '#lw-cortina form{width:100%;max-width:360px;background:#F5F0E6;border-radius:18px;padding:28px 26px;display:flex;flex-direction:column;gap:14px;box-shadow:0 20px 60px rgba(0,0,0,.35)}' +
    '#lw-cortina .ic{width:44px;height:44px;border-radius:999px;background:#104C4F;color:#F5F0E6;display:flex;align-items:center;justify-content:center;font-family:"Material Symbols Outlined";font-size:22px}' +
    '#lw-cortina h2{margin:0;font-size:20px;font-weight:700;color:#104C4F}' +
    '#lw-cortina p{margin:0;font-size:13px;line-height:1.45;color:#44483f}' +
    '#lw-cortina input{width:100%;padding:12px 14px;border-radius:12px;border:1px solid #BEB3A5;background:#fff;font:500 15px system-ui,sans-serif;color:#1b1c19}' +
    '#lw-cortina input:focus{outline:3px solid #E8741C;outline-offset:1px}' +
    '#lw-cortina button{padding:12px 16px;border-radius:999px;border:0;background:#104C4F;color:#fff;font:700 14px system-ui,sans-serif;cursor:pointer}' +
    '#lw-cortina button[disabled]{opacity:.55;cursor:default}' +
    '#lw-cortina .err{color:#93000A;font-weight:600;min-height:18px}' +
    '#lw-cortina-chip{position:fixed;right:16px;bottom:calc(16px + env(safe-area-inset-bottom,0px));z-index:2147482999;display:flex;align-items:center;gap:8px;padding:8px 8px 8px 14px;border-radius:999px;background:#104C4F;color:#F5F0E6;font:600 12px system-ui,sans-serif;box-shadow:0 6px 20px rgba(0,0,0,.2)}' +
    '#lw-cortina-chip[hidden]{display:none}' +
    '#lw-cortina-chip b{font-variant-numeric:tabular-nums;min-width:2ch;text-align:right}' +
    '#lw-cortina-chip button{border:0;border-radius:999px;padding:6px 10px;background:#F5F0E6;color:#104C4F;font:700 11px system-ui,sans-serif;cursor:pointer}';
  document.head.appendChild(css);

  // La cortina se pone YA, antes de que se pinte ningún dato.
  var capa = document.createElement('div');
  capa.id = 'lw-cortina';
  capa.innerHTML =
    '<form autocomplete="off" novalidate>' +
      '<span class="ic" aria-hidden="true">lock</span>' +
      '<h2>Pantalla protegida</h2>' +
      '<p>Escribe la contraseña con la que entras a la intranet. Se vuelve a bloquear sola tras ' + SEGUNDOS + ' segundos sin usarla.</p>' +
      '<input id="lw-cortina-clave" type="password" autocomplete="current-password" placeholder="Contraseña" aria-label="Contraseña">' +
      '<p class="err" role="alert" id="lw-cortina-err"></p>' +
      '<button type="submit" id="lw-cortina-ok">Desbloquear</button>' +
    '</form>';
  var chip = document.createElement('div');
  chip.id = 'lw-cortina-chip';
  chip.hidden = true;
  chip.innerHTML = '<span>Se bloquea en</span><b id="lw-cortina-seg">' + SEGUNDOS + '</b><span>s</span><button type="button" id="lw-cortina-ya">Bloquear ya</button>';
  function monta() {
    document.body.appendChild(capa); document.body.appendChild(chip);
    var pre = document.getElementById('lw-cortina-pre');   // el fondo que puso nav.js
    if (pre) pre.remove();
  }
  if (document.body) monta(); else document.addEventListener('DOMContentLoaded', monta);

  var form = capa.querySelector('form');
  var input = capa.querySelector('#lw-cortina-clave');
  var err = capa.querySelector('#lw-cortina-err');
  var ok = capa.querySelector('#lw-cortina-ok');
  var seg = chip.querySelector('#lw-cortina-seg');
  var abierta = false, ultimo = 0, reloj = null, fallos = 0, bloqueadoHasta = 0;
  var sb = null, email = '';

  function cierra() {
    abierta = false;
    capa.hidden = false; chip.hidden = true;
    input.value = ''; err.textContent = '';
    if (reloj) { clearInterval(reloj); reloj = null; }
    setTimeout(function () { try { input.focus(); } catch (e) {} }, 30);
  }
  function abre() {
    abierta = true; fallos = 0;
    capa.hidden = true; chip.hidden = false;
    input.value = '';
    ultimo = Date.now();
    tic();
    if (!reloj) reloj = setInterval(tic, 250);
  }
  function tic() {
    var quedan = Math.ceil(SEGUNDOS - (Date.now() - ultimo) / 1000);
    if (quedan <= 0) { cierra(); return; }
    seg.textContent = String(quedan);
  }
  function actividad() { if (abierta) ultimo = Date.now(); }
  ['mousemove', 'mousedown', 'keydown', 'wheel', 'touchstart', 'scroll', 'input'].forEach(function (ev) {
    window.addEventListener(ev, actividad, { capture: true, passive: true });
  });
  // al cambiar de pestaña o minimizar, se bloquea en el acto
  document.addEventListener('visibilitychange', function () { if (document.hidden && abierta) cierra(); });
  chip.querySelector('#lw-cortina-ya').addEventListener('click', function (ev) { ev.stopPropagation(); cierra(); });

  function comprueba(clave) {
    if (!sb || !email) return Promise.resolve({ ok: false, msg: 'Aún no se ha cargado tu sesión: espera un segundo y vuelve a probar.' });
    var url = sb.supabaseUrl, key = sb.supabaseKey;
    if (!url || !key || !window.supabase || !window.supabase.createClient) {
      return Promise.resolve({ ok: false, msg: 'No se ha podido comprobar la contraseña. Recarga la página.' });
    }
    // cliente desechable: no guarda sesión ni pisa la tuya
    var tmp = window.supabase.createClient(url, key, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false, storageKey: 'lw-cortina-' + Date.now() }
    });
    return tmp.auth.signInWithPassword({ email: email, password: clave }).then(function (r) {
      if (r.error || !r.data || !r.data.user) return { ok: false, msg: 'Contraseña incorrecta.' };
      if ((r.data.user.email || '').toLowerCase() !== email.toLowerCase()) return { ok: false, msg: 'Contraseña incorrecta.' };
      try { tmp.auth.signOut({ scope: 'local' }); } catch (e) {}
      return { ok: true };
    }, function () { return { ok: false, msg: 'Sin conexión: no se ha podido comprobar la contraseña.' }; });
  }

  form.addEventListener('submit', function (ev) {
    ev.preventDefault();
    var ahora = Date.now();
    if (ahora < bloqueadoHasta) {
      err.textContent = 'Demasiados intentos. Espera ' + Math.ceil((bloqueadoHasta - ahora) / 1000) + ' s.';
      return;
    }
    var clave = input.value;
    if (!clave) { err.textContent = 'Escribe tu contraseña.'; return; }
    ok.disabled = true; ok.textContent = 'Comprobando…'; err.textContent = '';
    comprueba(clave).then(function (r) {
      ok.disabled = false; ok.textContent = 'Desbloquear';
      if (r.ok) { abre(); return; }
      fallos += 1;
      input.value = '';
      if (fallos >= MAX_FALLOS) { bloqueadoHasta = Date.now() + ESPERA_FALLOS * 1000; fallos = 0; err.textContent = 'Demasiados intentos. Espera ' + ESPERA_FALLOS + ' s.'; }
      else err.textContent = r.msg;
      try { input.focus(); } catch (e) {}
    });
  });

  if (window.LW_AUTH && window.LW_AUTH.then) {
    window.LW_AUTH.then(function (aut) {
      sb = aut && aut.sb;
      email = (aut && aut.session && aut.session.user && aut.session.user.email) || '';
    });
  }
  setTimeout(function () { try { input.focus(); } catch (e) {} }, 60);
})();
