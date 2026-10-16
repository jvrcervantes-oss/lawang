// node intranet/v4/assets/ajustes_registro.harness.cjs   (desde la raíz del repo de Lawang; necesita Edge)
// Arnés de Ajustes › Registro de cambios, Usuarios y Mantenimiento (ajustes-ux, 17-oct-2026): la página REAL (/intranet/v4/ajustes/)
// servida en local con un Supabase FALSO (window.LW_SB, que guard.js usa si existe; datos inventados). Mide, en es y en, a 1440 y 390:
//  · Registro: cada ajuste sale por su nombre en pantalla (de Ajustes o de Reservas), con la clave interna solo en el title; una clave que
//    nadie conoce sale tal cual; en 390 cada cambio es una ficha (sin cabecera de tabla, cada dato con su rótulo, sin scroll horizontal);
//    en 1440 la tabla de siempre, con cabecera y sin rótulos repetidos.
//  · Usuarios: la pestaña «Próximamente» tiene una salida a la herramienta Usuarios (data-accion="ajustes-ir-usuarios", ../usuarios/).
//  · Mantenimiento: las dos casillas de motivo tienen nombre accesible (aria-label), no solo placeholder.
// La interfaz se maneja por data-* e id, nunca por rótulo. Sale 1 si falla.
const fs = require('fs'), path = require('path'), http = require('http');
const { chromium } = require(process.env.PLAYWRIGHT_CORE || 'C:/Users/jvrce/AppData/Roaming/npm/node_modules/@playwright/mcp/node_modules/playwright-core');
const RAIZ = path.resolve(__dirname, '..', '..', '..');
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.png': 'image/png', '.webp': 'image/webp', '.json': 'application/json' };
const srv = http.createServer((q, r) => {
  let p = decodeURIComponent(q.url.split('?')[0]); if (p.endsWith('/')) p += 'index.html';
  const f = path.join(RAIZ, p);
  if (!fs.existsSync(f)) { r.writeHead(404); r.end(); return; }
  r.writeHead(200, { 'content-type': MIME[path.extname(f)] || 'application/octet-stream' }); fs.createReadStream(f).pipe(r);
});
const LOG = [
  { id: 3, tabla: 'otra_tabla', clave: 'clave_rara', antes: 1, despues: 2, motivo: null, quien: 'persona@ejemplo.test', cuando: '2026-10-02T03:00:00Z' },
  { id: 2, tabla: 'ajustes_config', clave: 'marca', antes: 'Lawang Estate', despues: 'Lawang', motivo: 'Nombre corto', quien: 'persona@ejemplo.test', cuando: '2026-10-01T03:00:00Z' },
  { id: 1, tabla: 'parametros', clave: 'reservas.dias_gracia', antes: 2, despues: 3, motivo: null, quien: 'persona@ejemplo.test', cuando: '2026-09-28T03:00:00Z' }
];
const FALSO = `(function () {
  var FICHA = { rol: 'super_admin', herramientas: [], activo: true, nombre: 'Persona de prueba', notif_visto_hasta: null, ambito: 'global', empresas: null, es_propietario: true };
  var TABLAS = { usuarios: [FICHA], empresas: [], parametros: [] };
  var RPC = {
    ajustes_config_datos: { puede_escribir: true, valores: { marca: 'Lawang', zona_horaria: 'Asia/Makassar', logo_correo_url: '' }, actualizado: {}, editables: ['marca', 'zona_horaria', 'logo_correo_url'] },
    ajustes_log_datos: { hay_mas: false, filas: ${JSON.stringify(LOG)} },
    mantenimiento_datos: { envios_pausados: false, motivo: null, cambiado_en: null, intranet_cerrada: false, intranet_motivo: null, intranet_cambiado_en: null },
    reservas_vencimiento: []
  };
  function cadena(tabla) {
    var filas = (TABLAS[tabla] || []).slice(), uno = false;
    var p = new Proxy({}, { get: function (_, k) {
      if (k === 'then') return function (ok, ko) { return Promise.resolve({ data: uno ? (filas[0] || null) : filas, error: null }).then(ok, ko); };
      if (k === 'maybeSingle' || k === 'single') return function () { uno = true; return p; };
      return function () { return p; };
    } });
    return p;
  }
  window.LW_SB = {
    auth: {
      getSession: function () { return Promise.resolve({ data: { session: { access_token: 'x', user: { id: 'u-prueba', email: 'persona@ejemplo.test', app_metadata: {} } } } }); },
      getUser: function () { return Promise.resolve({ data: { user: { id: 'u-prueba', email: 'persona@ejemplo.test' } } }); },
      onAuthStateChange: function () { return { data: { subscription: { unsubscribe: function () {} } } }; },
      signOut: function () { return Promise.resolve({}); }
    },
    from: cadena,
    rpc: function (n) {
      if (RPC[n] !== undefined) return Promise.resolve({ data: JSON.parse(JSON.stringify(RPC[n])), error: null });
      return Promise.resolve({ data: null, error: { message: '(arnés) sin dato para ' + n } });
    },
    storage: { from: function () { return { getPublicUrl: function () { return { data: { publicUrl: '' } }; }, createSignedUrl: function () { return Promise.resolve({ data: null, error: null }); } }; } },
    channel: function () { var c = { on: function () { return c; }, subscribe: function () { return c; } }; return c; },
    removeChannel: function () {},
    functions: { invoke: function () { return Promise.resolve({ data: null, error: { message: '(arnés)' } }); } }
  };
  window.supabase = { createClient: function () { return window.LW_SB; } };
})();
`;
// Lo que se espera ver en la columna del ajuste, por idioma. El nombre de Reservas es el de RES_TEXTOS (datos.js), el de marca el de CAMPOS (ajustes.js).
const NOMBRES = { es: { marca: 'Nombre del ERP', 'reservas.dias_gracia': 'Días de gracia tras vencer' }, en: { marca: 'ERP name', 'reservas.dias_gracia': 'Grace days after expiry' } };
const fallos = [];
const ok = (txt, cond) => { console.log((cond ? 'ok     ' : 'FALLA  ') + txt); if (!cond) fallos.push(txt); };

srv.listen(0, async () => {
  const port = srv.address().port;
  const exe = process.env.CHROMIUM_EXE || 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
  const b = await chromium.launch({ executablePath: exe });
  try {
    for (const idioma of ['es', 'en']) for (const w of [1440, 390]) {
      const pre = idioma + ' ' + w + ': ';
      const ctx = await b.newContext({ viewport: { width: w, height: w > 800 ? 900 : 844 } });
      await ctx.addInitScript({ content: `try{localStorage.setItem('lawang_idioma_ui','${idioma}')}catch(e){};\n` + FALSO });
      await ctx.route(/cdn\.jsdelivr\.net\/npm\/@supabase/, rt => rt.fulfill({ status: 200, contentType: 'text/javascript', body: 'window.supabase={createClient:function(){return window.LW_SB}};' }));
      const p = await ctx.newPage(); const errs = [];
      p.on('pageerror', e => errs.push(String(e.message).slice(0, 160)));
      await p.goto(`http://127.0.0.1:${port}/intranet/v4/ajustes/#registro`, { waitUntil: 'load' });
      await p.waitForSelector('[data-ajuste-log="1"]', { timeout: 15000 });
      const m = await p.evaluate(() => {
        const fila = id => document.querySelector('[data-ajuste-log="' + id + '"]');
        const celda = id => fila(id).children[2];
        const vis = e => !!e && e.offsetParent !== null;
        const thead = document.querySelector('[data-ajuste-log]').closest('table').querySelector('thead');
        const td = fila(2).children[0];
        const panel = fila(2).closest('[data-lw-panel]') || document.body;
        return {
          marca: celda(2).textContent.trim(), marcaTitle: (celda(2).querySelector('[title]') || {}).title || '',
          dias: celda(1).textContent.trim(), rara: celda(3).textContent.trim(),
          clavesVisibles: [...document.querySelectorAll('[data-ajuste-log]')].map(f => f.innerText).join(' ').match(/reservas\.dias_gracia|ajustes_config · marca/g) || [],
          theadVisible: vis(thead), filaDisplay: getComputedStyle(fila(2)).display,
          rotulo: getComputedStyle(td, '::before').content, rotuloEsperado: td.getAttribute('data-l'),
          scrollX: document.documentElement.scrollWidth > document.documentElement.clientWidth || panel.scrollWidth > panel.clientWidth + 1,
          irUsuarios: (() => { const a = document.querySelectorAll('#lw-panel-usuarios [data-accion="ajustes-ir-usuarios"]'); return { n: a.length, href: a[0] ? a[0].getAttribute('href') : null, txt: a[0] ? a[0].textContent.trim() : '' }; })(),
          aria: ['lw-mant-motivo', 'lw-int-motivo'].map(id => { const i = document.getElementById(id); return i ? (i.getAttribute('aria-label') || '') : null; })
        };
      });
      ok(pre + 'sin errores de página', errs.length === 0);
      ok(pre + 'marca sale por su nombre («' + m.marca + '»)', m.marca === NOMBRES[idioma].marca);
      ok(pre + 'la clave interna de marca queda solo en el title', m.marcaTitle === 'ajustes_config · marca');
      ok(pre + 'reservas.dias_gracia sale por su nombre («' + m.dias + '»)', m.dias === NOMBRES[idioma]['reservas.dias_gracia']);
      ok(pre + 'una clave que nadie conoce sale tal cual', m.rara === 'otra_tabla · clave_rara');
      ok(pre + 'ninguna clave interna conocida a la vista', m.clavesVisibles.length === 0);
      if (w === 390) {
        ok(pre + 'sin cabecera de tabla', !m.theadVisible);
        ok(pre + 'cada cambio es una ficha (fila en bloque)', m.filaDisplay === 'block');
        ok(pre + 'cada dato lleva su rótulo («' + m.rotuloEsperado + '»)', m.rotulo === '"' + m.rotuloEsperado + '"');
      } else {
        ok(pre + 'tabla con cabecera', m.theadVisible && m.filaDisplay === 'table-row');
        ok(pre + 'sin rótulo repetido en cada celda', m.rotulo === 'none' || m.rotulo === 'normal');
      }
      ok(pre + 'sin scroll horizontal', !m.scrollX);
      ok(pre + 'Usuarios: una sola salida a ../usuarios/ con texto', m.irUsuarios.n === 1 && m.irUsuarios.href === '../usuarios/' && !!m.irUsuarios.txt);
      ok(pre + 'Mantenimiento: los dos motivos con aria-label', m.aria.every(a => !!a));
      await ctx.close();
    }
  } finally { await b.close(); srv.close(); }
  console.log(fallos.length ? fallos.length + ' FALLA' : 'todo en verde');
  process.exit(fallos.length ? 1 : 0);
});
