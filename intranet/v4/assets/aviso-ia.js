/* aviso-ia.js — la invitación de la cabecera a conectar el asistente de IA (MCP de Lawang, 16-oct-2026).
 * Owner, 16-oct: «un aviso bonito para invitar a la gente a conectarse… que esté en la topbar». Encargo: encargos/20261015_erp_mcp.md
 * (agencia), sesión mcp-aviso; revisión previa #403 (Experiencia). Lleva a /intranet/v4/ia/ («Apps conectadas»): pasos y conexiones.
 *
 * A QUIÉN LE SALE lo decide la base, no el navegador: ia_mis_conexiones() (20261016073530, ya en la viva) dice si la IA está
 * encendida, si ESTA persona tiene permiso vigente y qué conexiones tiene. Sale con las tres a la vez: encendida, con permiso y sin
 * ninguna conexión viva. A quien no puede conectarse no se le invita (sería un botón roto); a quien ya está conectado, tampoco.
 * Y además tiene que poder TERMINAR (#403, «bloquea»): para conectar hace falta el identificador del asistente (ia_clientes.id).
 *  · si la base dice qué asistentes están activos (`clientes`, la propuesta supabase/propuestas/20261016230000_ia_mis_conexiones_clientes.sql),
 *    sale solo con uno activo o más;
 *  · mientras no lo diga, sale solo al super admin, que es quien ve los identificadores en Ajustes › IA.
 * Si la lectura falla, no sale: es una invitación, no un aviso de algo que va mal (callarse aquí no esconde ningún fallo).
 * Dos textos: «Conecta tu asistente de IA» y, si ya tuvo una conexión que caducó sola (7 días), «Vuelve a conectar tu asistente».
 *
 * Lo inyecta nav.js tras LW_AUTH, como novedades.js, y se sella a mano con AVISO_IA_V (sella_assets no ve un script inyectado).
 * En una instancia del ERP no nace (las ia_* solo existen en Lawang). En /v4/ia/ no sale: ya está allí.
 *
 * Dos recuerdos, los dos COMODIDAD y no dato de verdad (como el «visto» de novedades.js; sin almacenamiento, sale y ya):
 *  · la respuesta de la base, 3 min en sessionStorage, para no preguntar en cada carga. Entrar en /v4/ia/ la borra.
 *  · la × («no volver a mostrar»), en localStorage por persona (su id) y navegador, con el texto que cerró: cerrar «Conecta» no
 *    calla «Vuelve a conectar». Decisión por defecto (16-oct, mcp-aviso): guardarlo en la base pedía una tabla nueva para un aviso
 *    que además desaparece solo en todos los dispositivos en cuanto la persona se conecta. Cómo revertir: una columna/RPC por
 *    usuario y leerla aquí en vez de localStorage.
 * Se engancha por data-lw="k-avisos" (la campana) y data-accion, nunca por un rótulo. Todo con createElement/textContent.
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
  if (typeof module !== 'undefined' && module.exports) module.exports = { queAviso: queAviso, fresco: fresco, MINUTOS: MINUTOS, TEXTOS: TEXTOS };
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
    var cerrado = lee('localStorage', 'lw-aviso-ia:cerrado:' + uid);
    var muestra = function (aviso) { if (aviso && aviso !== cerrado) pinta(uid, aviso); };
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
