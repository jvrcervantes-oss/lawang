/* aviso-ia.js — la invitación de la cabecera a conectar el asistente de IA (MCP de Lawang, 16-oct-2026).
 * Owner, 16-oct: «un aviso bonito para invitar a la gente a conectarse… que esté en la topbar». Encargo: encargos/20261015_erp_mcp.md
 * (agencia), sesión mcp-aviso; revisión previa #403 (Experiencia). Lleva a /intranet/v4/ia/ («Apps conectadas»): pasos y conexiones.
 *
 * A QUIÉN LE SALE lo decide la base, no el navegador: ia_mis_conexiones() (20261016073530, ya en la viva) dice si la IA está
 * encendida, si ESTA persona puede conectar (`permiso`: desde el 17-oct-2026, 20261017043002_mcp_todos, es «usuario activo y sin
 * bloqueo»; ya no hay permiso por persona) y qué conexiones tiene. Sale con las tres a la vez: encendida, puede conectar y sin
 * ninguna conexión viva. A quien no puede conectarse no se le invita (sería un botón roto); a quien ya está conectado, tampoco.
 * Y además tiene que poder TERMINAR (#403, «bloquea»): para conectar hace falta el identificador del asistente (ia_clientes.id).
 *  · si la base dice qué asistentes están activos (`clientes`, la migración supabase/migrations/20261017015203_ia_mis_conexiones_clientes.sql),
 *    sale solo con uno activo o más;
 *  · mientras no lo diga, sale solo al super admin, que es quien ve los identificadores en Ajustes › IA.
 * Si la lectura falla, no sale: es una invitación, no un aviso de algo que va mal (callarse aquí no esconde ningún fallo).
 * Dos textos: «Conecta tu asistente de IA» y, si ya tuvo una conexión que caducó sola (7 días), «Vuelve a conectar tu asistente».
 *
 * Lo inyecta nav.js tras LW_AUTH, como novedades.js, y se sella a mano con AVISO_IA_V (sella_assets no ve un script inyectado).
 * En una instancia del ERP no nace (las ia_* solo existen en Lawang). En /v4/ia/ no sale: ya está allí.
 * Sale en TODA cabecera de la suite con campana (v4, contratos, leads, obra…), no solo en /intranet/v4/ como novedades.js: el
 * asistente lee lo de Dirección y Contabilidad, que también se trabaja en contratos. Decisión por defecto (16-oct, mcp-aviso; el
 * revisor la preguntó). Cómo revertir: en arranca(), salir si location.pathname no contiene '/intranet/v4/'.
 *
 * Dos recuerdos, los dos COMODIDAD y no dato de verdad (como el «visto» de novedades.js; sin almacenamiento, sale y ya):
 *  · la respuesta de la base, 3 min en sessionStorage, para no preguntar en cada carga. Entrar en /v4/ia/ la borra.
 *  · la × («no volver a mostrar»), en localStorage por persona (su id) y navegador, con el texto que cerró: cerrar «Conecta» no
 *    calla «Vuelve a conectar». Decisión por defecto (16-oct, mcp-aviso): guardarlo en la base pedía una tabla nueva para un aviso
 *    que además desaparece solo en todos los dispositivos en cuanto la persona se conecta. Cómo revertir: una columna/RPC por
 *    usuario y leerla aquí en vez de localStorage.
 * Se engancha por data-lw="k-avisos" (la campana) y data-accion, nunca por un rótulo. Todo con createElement/textContent.
 *
 * EL BANNER DE LA PORTADA (17-oct-2026, sesión mcp-ventana). Owner, 17-oct: «en la home haz un banner llamativo para el mcp».
 * Misma regla de a quién le sale (queAviso) y mismo recuerdo de 3 min: no hay una segunda copia de la regla. Sale donde la
 * página tenga el hueco data-lw="banner-ia" (hoy solo /intranet/v4/home/); en esa página NO sale la píldora de la cabecera
 * (serían dos invitaciones a lo mismo). Sí sale en el móvil: en la portada hay sitio, a diferencia de la cabecera.
 * Su × tiene su propio recuerdo (lw-banner-ia:cerrado:<uid>), porque quien cerró la píldora el 16-oct no ha visto el banner;
 * cerrar el banner cierra también la píldora. Decisión por defecto (17-oct, mcp-ventana). Cómo revertir: que el banner lea
 * y escriba la clave de la píldora.
 */
(function (raiz) {
  'use strict';

  /* ── lógica pura (ia_pantallas.test.js la usa sin navegador) ─────────────────────────────────────────────────────────────
     null = no sale · 'conecta' · 'reconecta'. `esSuper` solo pesa mientras la base no diga qué asistentes están activos. */
  function queAviso(d, esSuper) {
    if (!d || d.encendido !== true || d.permiso !== true || !Array.isArray(d.conexiones)) return null;
    if (Array.isArray(d.clientes) ? d.clientes.length === 0 : esSuper !== true) return null;
    var vivas = d.conexiones.some(function (c) { return c && c.viva === true && !c.revocada_en; });
    if (vivas) return null;
    var caducada = d.conexiones.some(function (c) { return c && c.viva === false && !c.revocada_en; });
    return caducada ? 'reconecta' : 'conecta';
  }
  var MINUTOS = 3;
  function fresco(g, ahora) {
    return !!g && typeof g.t === 'number' && ahora - g.t >= 0 && ahora - g.t < MINUTOS * 60000 &&
      (g.aviso === null || g.aviso === 'conecta' || g.aviso === 'reconecta');
  }
  var TEXTOS = { conecta: 'Conecta tu asistente de IA', reconecta: 'Vuelve a conectar tu asistente de IA' };
  /* Los textos del banner, por aviso. Los ejemplos son preguntas, no datos: cada persona verá la respuesta según sus permisos. */
  var BANNER = {
    conecta: {
      antetitulo: 'Nuevo en la intranet',
      titulo: 'Pregúntale a tu IA por Lawang',
      texto: 'Conecta Claude con tu usuario y pregúntale en lenguaje normal lo que ves en la intranet. Solo ve lo que tú ves, no ve pasaportes ni documentos de los compradores y cada consulta queda registrada.',
      boton: 'Conectar mi asistente',
      nota: 'Son 2 minutos, desde el ordenador.'
    },
    reconecta: {
      antetitulo: 'Tu asistente de IA',
      titulo: 'Tu asistente se ha desconectado',
      texto: 'Por seguridad, cada conexión dura unos días y luego caduca sola. Vuelve a conectarlo para seguir preguntándole por Lawang.',
      boton: 'Volver a conectar',
      nota: 'Entras otra vez con tu usuario y tu contraseña.'
    }
  };
  var EJEMPLOS = ['¿Qué facturas siguen sin cobrar?', '¿Cuánto hemos cobrado este mes por proyecto?', '¿Qué parcelas quedan libres?'];
  if (typeof module !== 'undefined' && module.exports) module.exports = { queAviso: queAviso, fresco: fresco, MINUTOS: MINUTOS, TEXTOS: TEXTOS, BANNER: BANNER, EJEMPLOS: EJEMPLOS };
  if (typeof document === 'undefined') return;
  if (raiz.__lwAvisoIa) return;
  raiz.__lwAvisoIa = true;

  function T(s) { return typeof raiz.lwT === 'function' ? raiz.lwT(s) : s; }
  function lee(alm, k) { try { return raiz[alm].getItem(k); } catch (e) { return null; } }
  function guarda(alm, k, v) { try { raiz[alm].setItem(k, v); } catch (e) { /* MUDO A PROPÓSITO: sin almacenamiento solo se pierde el recuerdo */ } }
  function borra(alm, k) { try { raiz[alm].removeItem(k); } catch (e) { /* MUDO A PROPÓSITO: igual que guarda() */ } }
  function el(tag, cls, txt) { var e = document.createElement(tag); if (cls) e.className = cls; if (txt != null) e.textContent = txt; return e; }

  /* Estilo propio y por token (las salidas de Tailwind de cada pantalla no llevan estas clases): el alto de los botones redondos
     de la cabecera (36 px), filete de 1 px, sin sombra; la × conserva una diana de 44 px aunque se dibuje de 28.
     Por debajo de 640 px NO sale. Decisión por defecto (16-oct, mcp-aviso), medida a 390 y 360 px: la cabecera del móvil va
     llena y cualquier forma de la invitación (píldora «IA», solo icono, círculo de 36 px, a la derecha o junto a la hamburguesa)
     le quita una línea al nombre de la persona; desde 640 px no le quita nada. Conectar se hace en claude.ai desde el ordenador
     (pegar dirección e identificador), y /v4/ia/ sigue en el menú. Cómo revertir: quitar la regla @media de abajo. */
  var CSS =
    '.lw-aviso-ia{display:inline-flex;align-items:center;height:36px;border:1px solid rgb(var(--tema-outline-variant, 196 200 186));' +
    'border-radius:999px;background:rgb(var(--tema-surface-container-lowest, 255 255 255));color:rgb(var(--tema-deep-lagoon, 16 76 79));' +
    'font:500 13px/1 Jost,system-ui,sans-serif;white-space:nowrap;flex-shrink:0}' +
    '.lw-aviso-ia a{display:inline-flex;align-items:center;gap:8px;height:100%;padding:0 4px 0 12px;color:inherit;text-decoration:none;border-radius:999px 0 0 999px}' +
    '.lw-aviso-ia a:hover{background:rgb(var(--tema-surface-alt, 241 235 221))}' +
    '.lw-aviso-ia .material-symbols-outlined{font-size:18px}' +
    '.lw-aviso-ia button{position:relative;display:inline-flex;align-items:center;justify-content:center;width:28px;height:28px;margin:0 4px 0 2px;' +
    'border:0;border-radius:999px;background:transparent;color:rgb(var(--tema-on-surface-variant, 68 72 63));cursor:pointer}' +
    '.lw-aviso-ia button::after{content:"";position:absolute;inset:-8px}' +
    '.lw-aviso-ia button:hover{background:rgb(var(--tema-surface-alt, 241 235 221))}' +
    '.lw-aviso-ia button .material-symbols-outlined{font-size:16px}' +
    '.lw-aviso-ia a:focus-visible,.lw-aviso-ia button:focus-visible{outline:2px solid rgb(var(--tema-deep-lagoon, 16 76 79));outline-offset:2px}' +
    '@media (max-width:639px){.lw-aviso-ia{display:none}}';

  /* El banner: fondo deep-lagoon y texto on-primary (contraste 9,6:1), botón claro de 44 px, × con diana de 44 px. Por token,
     con el valor de Lawang de reserva por si una pantalla no carga tw.css. De una columna por debajo de 768 px. */
  var C = function (t, r) { return 'rgb(var(--tema-' + t + ', ' + r + '))'; };
  var CSS_BANNER =
    '.lw-banner-ia{position:relative;display:grid;grid-template-columns:minmax(0,1fr) minmax(0,22rem);gap:28px;align-items:center;' +
    'padding:28px 72px 28px 32px;border-radius:16px;overflow:hidden;background:' + C('deep-lagoon', '16 76 79') + ';color:' + C('on-primary', '255 255 255') + '}' +
    '.lw-banner-ia::before{content:"";position:absolute;right:-90px;top:-110px;width:320px;height:320px;border-radius:50%;' +
    'background:' + C('secondary-fixed-dim', '154 208 211') + ';opacity:.14;pointer-events:none}' +
    '.lw-banner-ia>*{position:relative}' +
    '.lw-banner-ia .lw-bia-ante{display:inline-flex;align-items:center;gap:6px;margin:0 0 10px;padding:4px 10px;border-radius:999px;' +
    'background:rgb(255 255 255 / .14);font:600 11px/1.2 "Neue Kabel",system-ui,sans-serif;letter-spacing:.14em;text-transform:uppercase}' +
    '.lw-banner-ia .lw-bia-ante .material-symbols-outlined{font-size:16px}' +
    '.lw-banner-ia h2{margin:0;font:600 clamp(24px,2.4vw,32px)/1.15 "Neue Kabel",system-ui,sans-serif;letter-spacing:-.01em}' +
    '.lw-banner-ia .lw-bia-texto{margin:10px 0 0;max-width:40rem;font:400 15px/1.55 "Neue Kabel",system-ui,sans-serif;opacity:.92}' +
    '.lw-banner-ia .lw-bia-acciones{display:flex;flex-wrap:wrap;align-items:center;gap:12px 18px;margin-top:20px}' +
    '.lw-banner-ia .lw-bia-boton{display:inline-flex;align-items:center;gap:8px;min-height:44px;padding:0 22px;border-radius:999px;' +
    'background:' + C('surface-container-lowest', '255 255 255') + ';color:' + C('deep-lagoon', '16 76 79') + ';font:600 14px/1 "Neue Kabel",system-ui,sans-serif;text-decoration:none}' +
    '.lw-banner-ia .lw-bia-boton:hover{background:' + C('secondary-fixed', '182 236 239') + '}' +
    '.lw-banner-ia .lw-bia-boton .material-symbols-outlined{font-size:18px}' +
    '.lw-banner-ia .lw-bia-nota{font:400 13px/1.4 "Neue Kabel",system-ui,sans-serif;opacity:.8}' +
    '.lw-banner-ia .lw-bia-ejemplos{display:flex;flex-direction:column;gap:10px;margin:0;padding:0;list-style:none}' +
    '.lw-banner-ia .lw-bia-ejemplos li{display:flex;align-items:flex-start;gap:8px;padding:12px 14px;border-radius:14px 14px 14px 4px;' +
    'background:rgb(255 255 255 / .1);border:1px solid rgb(255 255 255 / .18);font:400 14px/1.4 "Neue Kabel",system-ui,sans-serif}' +
    '.lw-banner-ia .lw-bia-ejemplos .material-symbols-outlined{font-size:18px;opacity:.75}' +
    '.lw-banner-ia .lw-bia-cerrar{position:absolute;top:14px;right:14px;display:inline-flex;align-items:center;justify-content:center;' +
    'width:44px;height:44px;border:0;border-radius:999px;background:transparent;color:inherit;cursor:pointer;opacity:.85}' +
    '.lw-banner-ia .lw-bia-cerrar:hover{background:rgb(255 255 255 / .14);opacity:1}' +
    '.lw-banner-ia a:focus-visible,.lw-banner-ia button:focus-visible{outline:2px solid ' + C('on-primary', '255 255 255') + ';outline-offset:3px}' +
    '@media (max-width:767px){.lw-banner-ia{grid-template-columns:minmax(0,1fr);gap:20px;padding:24px 20px}' +
    '.lw-banner-ia .lw-bia-cabeza{padding-right:40px}.lw-banner-ia .lw-bia-cerrar{top:8px;right:8px}' +
    '.lw-banner-ia .lw-bia-ejemplos li:nth-child(3){display:none}}';

  function pintaBanner(uid, aviso, hueco) {
    if (hueco.querySelector('.lw-banner-ia')) return;
    if (!document.getElementById('lw-banner-ia-css')) { var st = el('style'); st.id = 'lw-banner-ia-css'; st.textContent = CSS_BANNER; document.head.appendChild(st); }
    var t = BANNER[aviso];
    var caja = el('section', 'lw-banner-ia');
    caja.setAttribute('data-lw-aviso-ia', aviso);
    caja.setAttribute('aria-labelledby', 'lw-bia-titulo');

    var izq = el('div', 'lw-bia-cabeza');
    var ante = el('p', 'lw-bia-ante');
    var ai = el('span', 'material-symbols-outlined', 'auto_awesome'); ai.setAttribute('aria-hidden', 'true');
    ante.appendChild(ai); ante.appendChild(el('span', null, T(t.antetitulo)));
    var h = el('h2', null, T(t.titulo)); h.id = 'lw-bia-titulo';
    izq.appendChild(ante); izq.appendChild(h); izq.appendChild(el('p', 'lw-bia-texto', T(t.texto)));
    var acc = el('div', 'lw-bia-acciones');
    var a = el('a', 'lw-bia-boton');
    a.href = '/intranet/v4/ia/';
    a.setAttribute('data-accion', 'banner-ia-abrir');
    a.setAttribute('data-real', '');
    a.appendChild(el('span', null, T(t.boton)));
    var fl = el('span', 'material-symbols-outlined', 'arrow_forward'); fl.setAttribute('aria-hidden', 'true'); a.appendChild(fl);
    acc.appendChild(a); acc.appendChild(el('span', 'lw-bia-nota', T(t.nota)));
    izq.appendChild(acc);
    caja.appendChild(izq);

    var ej = el('ul', 'lw-bia-ejemplos');
    ej.setAttribute('aria-label', T('Ejemplos de preguntas'));
    EJEMPLOS.forEach(function (q) {
      var li = el('li');
      var qi = el('span', 'material-symbols-outlined', 'chat_bubble'); qi.setAttribute('aria-hidden', 'true');
      li.appendChild(qi); li.appendChild(el('span', null, T(q)));
      ej.appendChild(li);
    });
    caja.appendChild(ej);

    var x = el('button', 'lw-bia-cerrar'); x.type = 'button';
    x.setAttribute('data-accion', 'banner-ia-cerrar');
    x.setAttribute('data-real', '');
    x.setAttribute('aria-label', T('No volver a mostrar este aviso'));
    x.title = T('No volver a mostrar este aviso');
    var xi = el('span', 'material-symbols-outlined', 'close'); xi.setAttribute('aria-hidden', 'true');
    x.appendChild(xi);
    x.addEventListener('click', function () {
      guarda('localStorage', 'lw-banner-ia:cerrado:' + uid, aviso);
      guarda('localStorage', 'lw-aviso-ia:cerrado:' + uid, aviso);
      hueco.hidden = true;
      caja.remove();
      var foco = document.querySelector('[data-lw="buscador"]'); if (foco) foco.focus();   // el foco no se pierde con el banner
    });
    caja.appendChild(x);
    hueco.appendChild(caja);
    hueco.hidden = false;
  }

  function pinta(uid, aviso) {
    var campana = document.querySelector('header [data-lw="k-avisos"]');
    var boton = campana && campana.closest('button');
    var grupo = boton && boton.parentElement;
    if (!grupo || grupo.querySelector('[data-lw="aviso-ia"]')) return;
    if (!document.getElementById('lw-aviso-ia-css')) { var st = el('style'); st.id = 'lw-aviso-ia-css'; st.textContent = CSS; document.head.appendChild(st); }

    var largo = T(TEXTOS[aviso]);
    var caja = el('div', 'lw-aviso-ia');
    caja.setAttribute('data-lw', 'aviso-ia');
    caja.setAttribute('data-lw-aviso-ia', aviso);
    var a = el('a');
    a.href = '/intranet/v4/ia/';
    a.setAttribute('data-accion', 'aviso-ia-abrir');
    a.setAttribute('data-real', '');
    a.setAttribute('aria-label', largo);
    a.title = T('Claude o ChatGPT consultan la intranet con tu usuario y ven solo lo que tú ves. Te explicamos cómo en Apps conectadas.');
    var ic = el('span', 'material-symbols-outlined', 'auto_awesome'); ic.setAttribute('aria-hidden', 'true');
    var tx = el('span', null, largo); tx.setAttribute('data-lw-aviso-ia-texto', ''); tx.setAttribute('aria-hidden', 'true');
    a.appendChild(ic); a.appendChild(tx);
    var x = el('button'); x.type = 'button';
    x.setAttribute('data-accion', 'aviso-ia-cerrar');
    x.setAttribute('data-real', '');
    x.setAttribute('aria-label', T('No volver a mostrar este aviso'));
    x.title = T('No volver a mostrar este aviso');
    var xi = el('span', 'material-symbols-outlined', 'close'); xi.setAttribute('aria-hidden', 'true');
    x.appendChild(xi);
    x.addEventListener('click', function () {
      guarda('localStorage', 'lw-aviso-ia:cerrado:' + uid, aviso);
      caja.remove();
      if (boton) boton.focus();   // el foco no se pierde con el aviso
    });
    caja.appendChild(a); caja.appendChild(x);
    grupo.insertBefore(caja, grupo.firstChild);
  }

  function arranca(aut) {
    if (raiz.AXW_NUCLEO_OPERACION || !aut || !aut.sb || !aut.ficha) return;
    var uid = aut.session && aut.session.user && aut.session.user.id;
    if (!uid) return;
    var kResp = 'lw-aviso-ia:resp:' + uid;
    if (location.pathname.indexOf('/intranet/v4/ia/') !== -1) { borra('sessionStorage', kResp); return; }
    var hueco = document.querySelector('[data-lw="banner-ia"]');
    var cerrado = lee('localStorage', (hueco ? 'lw-banner-ia' : 'lw-aviso-ia') + ':cerrado:' + uid);
    var muestra = function (aviso) {
      if (!aviso || aviso === cerrado) return;
      if (hueco) pintaBanner(uid, aviso, hueco); else pinta(uid, aviso);
    };
    var g = null;
    try { g = JSON.parse(lee('sessionStorage', kResp) || 'null'); } catch (e) { g = null; }   // un recuerdo roto = preguntar otra vez
    if (fresco(g, Date.now())) { muestra(g.aviso); return; }
    var esSuper = raiz.LW_ROL && typeof raiz.LW_ROL.esSuperGlobal === 'function' ? raiz.LW_ROL.esSuperGlobal(aut.ficha) : aut.ficha.rol === 'super_admin';
    aut.sb.rpc('ia_mis_conexiones').then(function (r) {
      if (!r || r.error) return;   // no he podido mirar → no se invita (y se vuelve a preguntar en la próxima carga)
      var aviso = queAviso(r.data, esSuper);
      guarda('sessionStorage', kResp, JSON.stringify({ t: Date.now(), aviso: aviso }));
      muestra(aviso);
    }, function () { /* MUDO A PROPÓSITO: sin red no se invita; la próxima carga vuelve a preguntar */ });
  }

  if (raiz.LW_AUTH && typeof raiz.LW_AUTH.then === 'function') raiz.LW_AUTH.then(arranca);
})(typeof window !== 'undefined' ? window : globalThis);
