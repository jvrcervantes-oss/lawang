/* Página de conexión del MCP de Lawang (F1-P4, 16-oct-2026; encargo agencia encargos/20261015_erp_mcp.md).

   FLUJO, en orden fijo (la base cuenta 120 s desde la contraseña: ia_conexion_autoriza mira el `amr` password del token):
     1. correo + contraseña con un cliente de Supabase PROPIO, sin guardar la sesión (memoria) y con storageKey propio: no
        pisa la sesión normal de la intranet de esta misma persona;
     2. si la cuenta tiene un segundo factor verificado, el código (aal2);
     3. ia_peticion_datos(p): qué asistente pide entrar y si esta persona puede conectarlo (no gasta la petición);
     4. consentimiento: qué podrá leer y cuánto dura;
     5. Permitir = formulario de PRIMER NIVEL (no fetch) a la edge mcp/conectar con `peticion` y `sesion`; la edge
        comprueba el Origin exacto, cierra esta sesión y responde 302 al asistente;
     6. si algo falla, la edge vuelve aquí con ?error=<código>&p=<petición>.

   SEGURIDAD. El token de esta sesión vive solo en la memoria del cliente de Supabase y en el campo oculto `sesion` desde el
   clic de Permitir hasta que se envía (se vacía en el acto). Nunca en la URL, en consola ni en almacenamiento. Lo que llega
   de la base o de la URL se pinta con textContent; un ?error= que no está en la lista cerrada da el mensaje genérico.
   Cancelar, «no puede» y el tiempo agotado cierran la sesión en el servidor (signOut local = revoca su refresco).

   IDIOMAS. Diccionario propio (es/en/id) y atributo data-k: la suite solo tiene es/en (idioma.js recorta a esos dos) y esta
   página no debe tocar ni ensuciar el diccionario común. Lee la elección de la suite (lawang_idioma_ui) pero no la escribe. */
(function () {
  'use strict';

  var RE_PETICION = /^[A-Za-z0-9_-]{43}$/;
  var PLAZO_MS = 105000;                 // de los 120 s de la base: margen para el viaje y el reloj del servidor
  var CODIGOS = ['contrasena_no_reciente', 'apagado', 'sin_permiso', 'usuario_inactivo', 'falta_segundo_factor',
                 'peticion_invalida', 'cliente', 'demasiadas_conexiones', 'invalid_request', 'server_error', 'error'];
  // Tras estos se puede volver a entrar desde aquí mismo; el resto no se arregla reintentando (apagado, sin permiso…).
  var REINTENTABLE = { contrasena_no_reciente: 1, falta_segundo_factor: 1, demasiadas_conexiones: 1,
                       invalid_request: 1, server_error: 1, error: 1 };

  var TXT = {
    es: {
      titulo_pagina: 'Conectar un asistente · %marca',
      idioma: 'Idioma',
      cargando: 'Cargando…',
      sin_peticion_titulo: 'Este enlace no sirve',
      sin_peticion_texto: 'Vuelve a pedir la conexión desde tu asistente (Claude o ChatGPT): te traerá aquí con un enlace nuevo.',
      en_marco: 'Por seguridad, esta página solo funciona abierta en su propia pestaña.',
      sin_cargar: 'La página no ha terminado de cargar. Recárgala; si sigue igual, revisa tu conexión.',
      entrar_titulo: 'Conectar un asistente',
      entrar_texto: 'Entra con tu usuario de %marca para confirmar que eres tú.',
      correo: 'Correo',
      contrasena: 'Contraseña',
      entrar: 'Entrar',
      entrando: 'Entrando…',
      faltan_datos: 'Escribe tu correo y tu contraseña.',
      login_credenciales: 'El correo o la contraseña no son correctos.',
      login_demasiados: 'Demasiados intentos seguidos. Espera unos minutos y vuelve a probar.',
      login_red: 'No hay conexión con %marca. Revisa tu conexión a internet e inténtalo otra vez.',
      login_otro: 'No se ha podido iniciar sesión. Inténtalo otra vez.',
      codigo_titulo: 'Código de verificación',
      codigo_texto: 'Escribe el código de 6 cifras de tu aplicación de verificación.',
      codigo: 'Código',
      verificar: 'Verificar',
      verificando: 'Verificando…',
      codigo_formato: 'El código son 6 cifras.',
      codigo_mal: 'El código no es correcto o ha caducado. Escribe el que se ve ahora en tu aplicación.',
      mfa_sin_totp: 'Tu cuenta tiene un segundo factor que esta página todavía no admite. Habla con un administrador.',
      comprobando: 'Comprobando la petición…',
      sin_mirar_titulo: 'No se ha podido comprobar la petición',
      sin_mirar_texto: 'No quiere decir que no puedas conectar: %marca no ha contestado. Revisa tu conexión e inténtalo otra vez.',
      reintentar: 'Intentar otra vez',
      consentir_titulo: '¿Permitir el acceso?',
      consentimiento: '%nombre podrá LEER, como tú, lo que ves en %marca de Dirección y Contabilidad durante %duracion. Puedes cortarlo cuando quieras en Apps conectadas.',
      consentimiento_sin_dias: '%nombre podrá LEER, como tú, lo que ves en %marca de Dirección y Contabilidad. Puedes cortarlo cuando quieras en Apps conectadas.',
      dias_1: '1 día',
      dias_n: '%n días',
      cuenta: 'Has entrado como %correo.',
      reloj: 'Confirma en los próximos %s segundos.',
      permitir: 'Permitir',
      cancelar: 'Cancelar',
      enviando: 'Conectando con %nombre…',
      cancelado_titulo: 'No se ha conectado nada',
      cancelado_texto: 'Has cancelado. Puedes cerrar esta pestaña y volver a tu asistente.',
      asistente: 'El asistente',
      error_contrasena_no_reciente: 'Ha pasado demasiado tiempo desde que escribiste la contraseña. Escríbela otra vez y confirma en menos de dos minutos.',
      error_apagado: 'La conexión de asistentes está apagada en %marca. Si la necesitas, pídele a un administrador que la encienda.',
      error_sin_permiso: 'Tu usuario no tiene permiso para conectar asistentes. Pídeselo a un administrador.',
      error_usuario_inactivo: 'Tu usuario está desactivado. Habla con un administrador.',
      error_falta_segundo_factor: 'Tu cuenta tiene verificación en dos pasos y falta el código. Vuelve a entrar y escribe el código cuando te lo pida.',
      error_peticion_invalida: 'Esta petición ya se usó o ha caducado. Vuelve a pedir la conexión desde tu asistente.',
      error_cliente: 'Este asistente no está autorizado en %marca. Pídele a un administrador que lo active.',
      error_demasiadas_conexiones: 'Ya tienes el máximo de asistentes conectados. Corta uno en Apps conectadas y vuelve a intentarlo.',
      error_invalid_request: 'La petición no se ha podido validar. Vuelve a entrar; si se repite, pide la conexión de nuevo desde tu asistente.',
      error_server_error: '%marca no ha podido terminar la conexión. Inténtalo otra vez en un momento.',
      error_error: 'No se ha podido conectar. Inténtalo otra vez.'
    },
    en: {
      titulo_pagina: 'Connect an assistant · %marca',
      idioma: 'Language',
      cargando: 'Loading…',
      sin_peticion_titulo: 'This link is not valid',
      sin_peticion_texto: 'Request the connection again from your assistant (Claude or ChatGPT): it will bring you back here with a new link.',
      en_marco: 'For security, this page only works when opened in its own tab.',
      sin_cargar: 'The page did not finish loading. Reload it; if nothing changes, check your connection.',
      entrar_titulo: 'Connect an assistant',
      entrar_texto: 'Sign in with your %marca account to confirm it is you.',
      correo: 'Email',
      contrasena: 'Password',
      entrar: 'Sign in',
      entrando: 'Signing in…',
      faltan_datos: 'Enter your email and your password.',
      login_credenciales: 'The email or password is incorrect.',
      login_demasiados: 'Too many attempts in a row. Wait a few minutes and try again.',
      login_red: 'Could not reach %marca. Check your internet connection and try again.',
      login_otro: 'Could not sign in. Please try again.',
      codigo_titulo: 'Verification code',
      codigo_texto: 'Enter the 6-digit code from your authenticator app.',
      codigo: 'Code',
      verificar: 'Verify',
      verificando: 'Verifying…',
      codigo_formato: 'The code is 6 digits.',
      codigo_mal: 'The code is incorrect or has expired. Enter the one your app shows now.',
      mfa_sin_totp: 'Your account has a second factor this page does not support yet. Talk to an administrator.',
      comprobando: 'Checking the request…',
      sin_mirar_titulo: 'The request could not be checked',
      sin_mirar_texto: 'This does not mean you cannot connect: %marca did not answer. Check your connection and try again.',
      reintentar: 'Try again',
      consentir_titulo: 'Allow access?',
      consentimiento: '%nombre will be able to READ, as you, what you see in %marca under Management and Accounting for %duracion. You can cut it off whenever you want in Connected apps.',
      consentimiento_sin_dias: '%nombre will be able to READ, as you, what you see in %marca under Management and Accounting. You can cut it off whenever you want in Connected apps.',
      dias_1: '1 day',
      dias_n: '%n days',
      cuenta: 'Signed in as %correo.',
      reloj: 'Confirm within the next %s seconds.',
      permitir: 'Allow',
      cancelar: 'Cancel',
      enviando: 'Connecting to %nombre…',
      cancelado_titulo: 'Nothing was connected',
      cancelado_texto: 'You cancelled. You can close this tab and go back to your assistant.',
      asistente: 'The assistant',
      error_contrasena_no_reciente: 'Too much time has passed since you entered your password. Enter it again and confirm within two minutes.',
      error_apagado: 'Assistant connections are turned off in %marca. If you need one, ask an administrator to turn them on.',
      error_sin_permiso: 'Your user is not allowed to connect assistants. Ask an administrator.',
      error_usuario_inactivo: 'Your user is deactivated. Talk to an administrator.',
      error_falta_segundo_factor: 'Your account uses two-step verification and the code is missing. Sign in again and enter the code when asked.',
      error_peticion_invalida: 'This request was already used or has expired. Request the connection again from your assistant.',
      error_cliente: 'This assistant is not authorised in %marca. Ask an administrator to enable it.',
      error_demasiadas_conexiones: 'You already have the maximum number of connected assistants. Cut one off in Connected apps and try again.',
      error_invalid_request: 'The request could not be validated. Sign in again; if it happens again, request the connection anew from your assistant.',
      error_server_error: '%marca could not complete the connection. Try again in a moment.',
      error_error: 'Could not connect. Please try again.'
    },
    id: {
      titulo_pagina: 'Hubungkan asisten · %marca',
      idioma: 'Bahasa',
      cargando: 'Memuat…',
      sin_peticion_titulo: 'Tautan ini tidak berlaku',
      sin_peticion_texto: 'Minta koneksi lagi dari asisten Anda (Claude atau ChatGPT): asisten akan membawa Anda kembali ke sini dengan tautan baru.',
      en_marco: 'Demi keamanan, halaman ini hanya berfungsi jika dibuka di tab tersendiri.',
      sin_cargar: 'Halaman belum selesai dimuat. Muat ulang; jika tetap sama, periksa koneksi Anda.',
      entrar_titulo: 'Hubungkan asisten',
      entrar_texto: 'Masuk dengan akun %marca Anda untuk memastikan bahwa ini memang Anda.',
      correo: 'Email',
      contrasena: 'Kata sandi',
      entrar: 'Masuk',
      entrando: 'Sedang masuk…',
      faltan_datos: 'Masukkan email dan kata sandi Anda.',
      login_credenciales: 'Email atau kata sandi salah.',
      login_demasiados: 'Terlalu banyak percobaan berturut-turut. Tunggu beberapa menit lalu coba lagi.',
      login_red: 'Tidak dapat terhubung ke %marca. Periksa koneksi internet Anda lalu coba lagi.',
      login_otro: 'Gagal masuk. Silakan coba lagi.',
      codigo_titulo: 'Kode verifikasi',
      codigo_texto: 'Masukkan kode 6 digit dari aplikasi autentikator Anda.',
      codigo: 'Kode',
      verificar: 'Verifikasi',
      verificando: 'Memverifikasi…',
      codigo_formato: 'Kode terdiri dari 6 digit.',
      codigo_mal: 'Kode salah atau sudah kedaluwarsa. Masukkan kode yang tampil sekarang di aplikasi Anda.',
      mfa_sin_totp: 'Akun Anda memiliki faktor kedua yang belum didukung halaman ini. Hubungi administrator.',
      comprobando: 'Memeriksa permintaan…',
      sin_mirar_titulo: 'Permintaan tidak dapat diperiksa',
      sin_mirar_texto: 'Ini bukan berarti Anda tidak bisa terhubung: %marca tidak merespons. Periksa koneksi Anda lalu coba lagi.',
      reintentar: 'Coba lagi',
      consentir_titulo: 'Izinkan akses?',
      consentimiento: '%nombre akan dapat MEMBACA, sebagai Anda, apa yang Anda lihat di %marca pada Direksi dan Akuntansi selama %duracion. Anda dapat memutusnya kapan saja di Aplikasi terhubung.',
      consentimiento_sin_dias: '%nombre akan dapat MEMBACA, sebagai Anda, apa yang Anda lihat di %marca pada Direksi dan Akuntansi. Anda dapat memutusnya kapan saja di Aplikasi terhubung.',
      dias_1: '1 hari',
      dias_n: '%n hari',
      cuenta: 'Masuk sebagai %correo.',
      reloj: 'Konfirmasi dalam %s detik ke depan.',
      permitir: 'Izinkan',
      cancelar: 'Batal',
      enviando: 'Menghubungkan ke %nombre…',
      cancelado_titulo: 'Tidak ada yang terhubung',
      cancelado_texto: 'Anda membatalkan. Anda dapat menutup tab ini dan kembali ke asisten Anda.',
      asistente: 'Asisten',
      error_contrasena_no_reciente: 'Sudah terlalu lama sejak Anda memasukkan kata sandi. Masukkan lagi dan konfirmasi dalam waktu dua menit.',
      error_apagado: 'Koneksi asisten dimatikan di %marca. Jika Anda membutuhkannya, minta administrator untuk menyalakannya.',
      error_sin_permiso: 'Pengguna Anda tidak memiliki izin untuk menghubungkan asisten. Mintalah kepada administrator.',
      error_usuario_inactivo: 'Pengguna Anda dinonaktifkan. Hubungi administrator.',
      error_falta_segundo_factor: 'Akun Anda menggunakan verifikasi dua langkah dan kodenya belum dimasukkan. Masuk lagi dan masukkan kode saat diminta.',
      error_peticion_invalida: 'Permintaan ini sudah digunakan atau sudah kedaluwarsa. Minta koneksi lagi dari asisten Anda.',
      error_cliente: 'Asisten ini tidak diizinkan di %marca. Minta administrator untuk mengaktifkannya.',
      error_demasiadas_conexiones: 'Anda sudah mencapai jumlah maksimum asisten yang terhubung. Putuskan salah satu di Aplikasi terhubung lalu coba lagi.',
      error_invalid_request: 'Permintaan tidak dapat divalidasi. Masuk lagi; jika terulang, minta koneksi baru dari asisten Anda.',
      error_server_error: '%marca tidak dapat menyelesaikan koneksi. Coba lagi sebentar lagi.',
      error_error: 'Tidak dapat terhubung. Silakan coba lagi.'
    }
  };

  var $ = function (sel) { return document.querySelector(sel); };
  var $$ = function (sel) { return Array.prototype.slice.call(document.querySelectorAll(sel)); };
  var INST = window.LW_INSTANCIA || null;
  var MARCA = (INST && INST.marca) || 'Lawang';

  var q = new URLSearchParams(location.search);
  var peticion = q.get('p') || '';
  var errorUrl = q.get('error');

  var estado = {
    idioma: idiomaInicial(),
    paso: 'arranque',
    aviso: null,          // clave del aviso de arriba (error de la edge o motivo de «no puede»)
    errEntrar: null,      // clave del error del paso 1
    errCodigo: null,      // clave del error del paso 2
    correo: '',           // con qué cuenta se ha entrado (solo para enseñarlo)
    nombre: '',           // nombre del asistente (de la base)
    dias: null,           // duración del permiso (de la base)
    t0: null,             // performance.now() al entrar con la contraseña
    factorId: null,
    ocupado: false,
    enviado: false,
    reintento: null,      // qué vuelve a probar «Intentar otra vez»
    reloj: 0
  };
  var sb = null;

  /* ── textos ───────────────────────────────────────────────────────────────────────────────────── */
  function idiomaInicial() {
    var guardado = null;
    try { guardado = localStorage.getItem('lawang_idioma_ui'); }
    catch (e) { /* MUDO A PROPOSITO: sin almacenamiento se decide por el idioma del navegador, que es la siguiente regla */ }
    if (guardado === 'en' || guardado === 'es') return guardado;
    var langs = (navigator.languages && navigator.languages.length) ? navigator.languages : [navigator.language || ''];
    for (var i = 0; i < langs.length; i++) {
      var l = String(langs[i] || '').toLowerCase();
      if (l.indexOf('id') === 0 || l.indexOf('in') === 0) return 'id';
      if (l.indexOf('en') === 0) return 'en';
      if (l.indexOf('es') === 0) return 'es';
    }
    return 'es';
  }
  function t(clave, vars) {
    var d = TXT[estado.idioma] || TXT.es;
    var s = d[clave] != null ? d[clave] : (TXT.es[clave] != null ? TXT.es[clave] : clave);
    var v = vars || {};
    return s.replace(/%(marca|nombre|correo|duracion|n|s)\b/g, function (m, k) {
      if (k === 'marca') return MARCA;
      return v[k] != null ? String(v[k]) : m;
    });
  }
  // Pinta una frase con trozos en negrita (el nombre del asistente) sin innerHTML: nodos de texto y <strong>.
  function pintaFrase(el, plantilla, vars, negritas) {
    while (el.firstChild) el.removeChild(el.firstChild);
    plantilla.split(/(%[a-z]+)/).forEach(function (trozo) {
      var m = /^%([a-z]+)$/.exec(trozo);
      if (m && Object.prototype.hasOwnProperty.call(vars, m[1])) {
        if (negritas.indexOf(m[1]) !== -1) {
          var b = document.createElement('strong');
          b.textContent = String(vars[m[1]]);
          el.appendChild(b);
        } else {
          el.appendChild(document.createTextNode(String(vars[m[1]])));
        }
      } else if (trozo) {
        el.appendChild(document.createTextNode(trozo.replace(/%marca\b/g, MARCA)));
      }
    });
  }
  function duracion() {
    var n = estado.dias;
    if (!(typeof n === 'number' && isFinite(n) && n > 0 && Math.floor(n) === n)) return null;
    return n === 1 ? t('dias_1') : t('dias_n', { n: n });
  }
  function nombreAsistente() { return estado.nombre || t('asistente'); }

  function aplicaTextos() {
    document.documentElement.lang = estado.idioma;
    document.title = t('titulo_pagina');
    $$('[data-k]').forEach(function (el) { el.textContent = t(el.getAttribute('data-k')); });
    $$('[data-k-aria]').forEach(function (el) { el.setAttribute('aria-label', t(el.getAttribute('data-k-aria'))); });
    $$('[data-ic-idioma]').forEach(function (b) {
      b.setAttribute('aria-pressed', b.getAttribute('data-ic-idioma') === estado.idioma ? 'true' : 'false');
    });
    var marca = $('[data-ic-marca]');
    if (marca) marca.textContent = (INST && INST.cabecera) || MARCA.toUpperCase();
    // lo dinámico: se vuelve a pintar desde el estado, nunca desde lo que ya hay en pantalla
    var av = $('[data-ic-aviso]');
    av.hidden = !estado.aviso;
    $('[data-ic-aviso-texto]').textContent = estado.aviso ? t(estado.aviso) : '';
    pintaError('entrar', estado.errEntrar);
    pintaError('codigo', estado.errCodigo);
    if (estado.ocupado) {
      var be = $('[data-accion="entrar"]'), bv = $('[data-accion="verificar"]');
      if (estado.paso === 'entrar') be.textContent = t('entrando');
      if (estado.paso === 'codigo') bv.textContent = t('verificando');
    }
    var vars = { nombre: nombreAsistente(), duracion: duracion() };
    pintaFrase($('[data-ic-consentimiento]'), t(vars.duracion ? 'consentimiento' : 'consentimiento_sin_dias'), vars, ['nombre']);
    $('[data-ic-cuenta]').textContent = estado.correo ? t('cuenta', { correo: estado.correo }) : '';
    $('[data-ic-enviando]').textContent = t('enviando', { nombre: nombreAsistente() });
    pintaReloj();
  }
  function pintaError(cual, clave) {
    var el = $('[data-ic-error="' + cual + '"]');
    el.hidden = !clave;
    el.textContent = clave ? t(clave) : '';
  }
  function ponAviso(clave) { estado.aviso = clave; aplicaTextos(); }

  /* ── pasos ────────────────────────────────────────────────────────────────────────────────────── */
  function muestra(paso) {
    estado.paso = paso;
    $$('[data-ic-paso]').forEach(function (el) { el.hidden = el.getAttribute('data-ic-paso') !== paso; });
    if (paso !== 'codigo' && paso !== 'consentir') paraReloj();
    aplicaTextos();
    // el foco al primer campo, o al título para que un lector de pantalla anuncie el cambio
    var caja = paso ? $('[data-ic-paso="' + paso + '"]') : null;
    var foco = caja && (caja.querySelector('input:not([type=hidden])') || caja.querySelector('h1'));
    if (!foco && estado.aviso) foco = $('[data-ic-aviso-texto]');
    if (foco) {
      if (foco.tagName !== 'INPUT') foco.setAttribute('tabindex', '-1');
      try { foco.focus({ preventScroll: false }); }
      catch (e) { /* MUDO A PROPOSITO: el foco es una ayuda; si el navegador no lo admite, la pantalla ya está pintada */ }
    }
  }
  function fin() { muestra(null); }        // solo queda el aviso de arriba: no hay nada que hacer desde aquí

  /* ── los 120 s ────────────────────────────────────────────────────────────────────────────────── */
  function restante() { return estado.t0 == null ? 0 : PLAZO_MS - (performance.now() - estado.t0); }
  function caducado() { return restante() <= 0; }
  function pintaReloj() {
    var s = Math.max(0, Math.ceil(restante() / 1000));
    var txt = (estado.reloj && estado.t0 != null) ? t('reloj', { s: s }) : '';
    $$('[data-ic-reloj]').forEach(function (el) { el.textContent = txt; });
  }
  function arrancaReloj() {
    paraReloj();
    estado.reloj = setInterval(function () {
      if (caducado()) { caduca(); return; }
      pintaReloj();
    }, 1000);
    pintaReloj();
  }
  function paraReloj() {
    if (estado.reloj) clearInterval(estado.reloj);
    estado.reloj = 0;
    pintaReloj();
  }
  function caduca() {
    paraReloj();
    cierraSesion();
    vuelveAEntrar('error_contrasena_no_reciente');
  }

  /* ── sesión propia ────────────────────────────────────────────────────────────────────────────── */
  function cliente() {
    return window.supabase.createClient(INST.sb_url, INST.sb_key, {   // publicable: el candado es la base
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false, storageKey: 'lw-ia-conectar' }
    });
  }
  function cierraSesion() {
    estado.t0 = null;
    estado.factorId = null;
    if (!sb) return Promise.resolve();
    // El mismo cliente sirve para el siguiente intento: signOut vacía su memoria y un inicio nuevo la pisa igualmente
    // (crear otro con la misma storageKey hace que supabase-js avise de «Multiple GoTrueClient instances»).
    return sb.auth.signOut({ scope: 'local' }).then(function () {}, function () {
      /* MUDO A PROPOSITO: si el cierre no llega, el token solo vivía en la memoria de esta página (ya descartada) y caduca
         solo en la hora de vida del access token; la persona no puede hacer nada distinto con un aviso */
    });
  }
  function vuelveAEntrar(clave) {
    estado.ocupado = false;
    estado.errEntrar = null;
    estado.errCodigo = null;
    estado.correo = '';
    estado.aviso = clave || null;
    $('#ic-clave').value = '';
    $('#ic-codigo').value = '';
    var be = $('[data-accion="entrar"]');
    be.disabled = false;
    muestra('entrar');
  }

  function claseErrorLogin(err) {
    var st = err && err.status, cod = (err && err.code) || '', msg = (err && err.message) || '';
    if (cod === 'invalid_credentials' || /invalid login credentials/i.test(msg)) return 'login_credenciales';
    if (st === 429 || cod === 'over_request_rate_limit') return 'login_demasiados';
    if (!st || (err && err.name === 'AuthRetryableFetchError') || st >= 500) return 'login_red';
    return 'login_otro';
  }

  function entrar(e) {
    e.preventDefault();
    if (estado.ocupado) return;
    var correo = $('#ic-correo').value.trim(), clave = $('#ic-clave').value;
    if (!correo || !clave) {
      estado.errEntrar = 'faltan_datos';
      aplicaTextos();
      (correo ? $('#ic-clave') : $('#ic-correo')).focus();
      return;
    }
    estado.ocupado = true;
    estado.errEntrar = null;
    estado.aviso = null;
    var boton = $('[data-accion="entrar"]');
    boton.disabled = true;
    aplicaTextos();
    var antes = performance.now();
    sb.auth.signInWithPassword({ email: correo, password: clave }).then(function (r) { return r; }, function (err) {
      return { error: err };
    }).then(function (r) {
      $('#ic-clave').value = '';
      if (r.error || !r.data || !r.data.session) {
        estado.ocupado = false;
        boton.disabled = false;
        estado.errEntrar = claseErrorLogin(r.error);
        aplicaTextos();
        $('#ic-clave').focus();
        return;
      }
      estado.t0 = antes;                 // desde ANTES de pedirlo: el reloj de la base arranca al autenticar
      estado.correo = (r.data.user && r.data.user.email) || correo;
      estado.ocupado = false;
      boton.disabled = false;
      segundoFactor();
    });
  }

  function segundoFactor() {
    if (caducado()) { caduca(); return; }
    sb.auth.mfa.getAuthenticatorAssuranceLevel().then(function (r) { return r; }, function (err) {
      return { error: err };
    }).then(function (r) {
      if (r.error || !r.data) { muestraSinMirar(segundoFactor); return; }
      if (r.data.nextLevel === 'aal2' && r.data.currentLevel !== 'aal2') {
        return sb.auth.mfa.listFactors().then(function (f) { return f; }, function (err) { return { error: err }; })
          .then(function (f) {
            if (f.error || !f.data) { muestraSinMirar(segundoFactor); return; }
            var totp = (f.data.totp || []).filter(function (x) { return x.status === 'verified'; })[0];
            if (!totp) {
              cierraSesion();
              estado.aviso = 'mfa_sin_totp';
              fin();
              return;
            }
            estado.factorId = totp.id;
            estado.errCodigo = null;
            muestra('codigo');
            arrancaReloj();
          });
      }
      comprueba();
    });
  }

  function verificar(e) {
    e.preventDefault();
    if (estado.ocupado) return;
    if (caducado()) { caduca(); return; }
    var codigo = $('#ic-codigo').value.replace(/\s+/g, '');
    if (!/^[0-9]{6}$/.test(codigo)) {
      estado.errCodigo = 'codigo_formato';
      aplicaTextos();
      $('#ic-codigo').focus();
      return;
    }
    estado.ocupado = true;
    estado.errCodigo = null;
    var boton = $('[data-accion="verificar"]');
    boton.disabled = true;
    aplicaTextos();
    sb.auth.mfa.challengeAndVerify({ factorId: estado.factorId, code: codigo }).then(function (r) { return r; }, function (err) {
      return { error: err };
    }).then(function (r) {
      estado.ocupado = false;
      boton.disabled = false;
      $('#ic-codigo').value = '';
      if (r.error) {
        var c = claseErrorLogin(r.error);
        estado.errCodigo = (c === 'login_demasiados' || c === 'login_red') ? c : 'codigo_mal';
        aplicaTextos();
        $('#ic-codigo').focus();
        return;
      }
      comprueba();
    });
  }

  function muestraSinMirar(reintento) {
    estado.reintento = reintento;
    muestra('sin-mirar');
  }

  function comprueba() {
    if (caducado()) { caduca(); return; }
    muestra('comprobando');
    sb.rpc('ia_peticion_datos', { p_peticion: peticion }).then(function (r) { return r; }, function (err) {
      return { error: err, status: 0 };
    }).then(function (r) {
      if (r.error) {
        // sin respuesta o el servidor caído = «no he podido mirar»; cualquier otro rechazo de la base es un error de verdad
        if (!r.status || r.status >= 500) { muestraSinMirar(comprueba); return; }
        cierraSesion();
        vuelveAEntrar('error_error');
        return;
      }
      var d = (r.data && typeof r.data === 'object') ? r.data : {};
      if (d.error) {
        cierraSesion();
        if (d.error === 'peticion_invalida') { estado.aviso = 'error_peticion_invalida'; fin(); }
        else vuelveAEntrar('error_error');
        return;
      }
      if (d.puede !== true) {
        var m = CODIGOS.indexOf(d.motivo) !== -1 ? d.motivo : 'error';
        cierraSesion();
        if (REINTENTABLE[m]) vuelveAEntrar('error_' + m);
        else { estado.aviso = 'error_' + m; fin(); }
        return;
      }
      if (caducado()) { caduca(); return; }
      estado.nombre = typeof d.nombre === 'string' ? d.nombre.trim().slice(0, 80) : '';
      estado.dias = typeof d.duracion_dias === 'number' ? d.duracion_dias : Number(d.duracion_dias);
      $('[data-accion="permitir"]').disabled = false;
      $('[data-accion="cancelar"]').disabled = false;
      muestra('consentir');
      arrancaReloj();
    });
  }

  function permitir() {
    if (estado.enviado) return;           // la petición vale UNA vez: un doble clic acabaría en peticion_invalida
    if (caducado()) { caduca(); return; }
    estado.enviado = true;
    $('[data-accion="permitir"]').disabled = true;
    $('[data-accion="cancelar"]').disabled = true;
    sb.auth.getSession().then(function (r) { return r; }, function (err) { return { error: err }; }).then(function (r) {
      var s = r && r.data && r.data.session;
      if (!s || !s.access_token || caducado()) {
        estado.enviado = false;
        if (caducado()) { caduca(); return; }
        cierraSesion();
        vuelveAEntrar('error_error');
        return;
      }
      var f = $('[data-ic-envio]');
      f.action = String(INST.sb_url).replace(/\/+$/, '') + '/functions/v1/mcp/conectar';
      f.elements.peticion.value = peticion;
      f.elements.sesion.value = s.access_token;
      paraReloj();
      muestra('enviando');
      f.submit();                          // el navegador ya ha copiado los campos: se vacían en el acto
      f.elements.sesion.value = '';
      f.elements.peticion.value = '';
    });
  }

  function cancelar() {
    if (estado.enviado) return;
    $('[data-accion="permitir"]').disabled = true;
    $('[data-accion="cancelar"]').disabled = true;
    paraReloj();
    cierraSesion();
    muestra('cancelado');
  }

  /* ── arranque ─────────────────────────────────────────────────────────────────────────────────── */
  function arranca() {
    $$('[data-ic-idioma]').forEach(function (b) {
      b.addEventListener('click', function () {
        estado.idioma = b.getAttribute('data-ic-idioma');
        aplicaTextos();
      });
    });
    aplicaTextos();

    // Dentro de un marco ajeno (clickjacking) no se pide nada. El servidor ya manda X-Frame-Options SAMEORIGIN.
    var enMarco = true;
    try { enMarco = window.top !== window.self; }
    catch (e) { /* MUDO A PROPOSITO: si no se puede leer top es que hay un marco de otro origen: se trata como marco */ }
    if (enMarco) { estado.aviso = 'en_marco'; fin(); return; }

    if (!RE_PETICION.test(peticion)) { muestra('sin-peticion'); return; }

    // La URL se queda solo con ?p=: recargar no repite un error viejo (y el código de error no se arrastra)
    try { history.replaceState(null, '', location.pathname + '?p=' + encodeURIComponent(peticion)); }
    catch (e) { /* MUDO A PROPOSITO: sin replaceState la URL conserva ?error= y recargar repite el aviso; no cambia nada más */ }

    if (!INST || !INST.sb_url || !INST.sb_key || !window.supabase || typeof window.supabase.createClient !== 'function') {
      estado.aviso = 'sin_cargar';
      fin();
      return;
    }
    sb = cliente();

    $('[data-ic-paso="entrar"]').addEventListener('submit', entrar);
    $('[data-ic-paso="codigo"]').addEventListener('submit', verificar);
    $('[data-accion="permitir"]').addEventListener('click', permitir);
    $('[data-accion="cancelar"]').addEventListener('click', cancelar);
    $('[data-accion="reintentar"]').addEventListener('click', function () {
      var f = estado.reintento || comprueba;
      estado.reintento = null;
      f();
    });

    if (errorUrl != null) {
      var c = CODIGOS.indexOf(errorUrl) !== -1 ? errorUrl : 'error';
      estado.aviso = 'error_' + c;
      if (!REINTENTABLE[c]) { fin(); return; }
    }
    muestra('entrar');
  }

  // Volver con «atrás» tras el 302 al asistente puede restaurar esta página de la caché con la sesión en memoria y los
  // campos ocultos: se recarga limpia (la petición ya está gastada; la base lo dirá).
  window.addEventListener('pageshow', function (e) {
    if (e.persisted) location.replace(location.pathname + (RE_PETICION.test(peticion) ? '?p=' + encodeURIComponent(peticion) : ''));
  });

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', arranca);
  else arranca();
})();
