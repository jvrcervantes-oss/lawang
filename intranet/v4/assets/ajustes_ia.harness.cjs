// node intranet/v4/assets/ajustes_ia.harness.cjs   (desde la raíz del repo de Lawang; necesita Edge)
// Arnés de Ajustes › IA en pantalla (ajustes-ux, 17-oct-2026): la página REAL (/intranet/v4/ajustes/#ia) servida en local con un
// Supabase FALSO (window.LW_SB, que guard.js usa si existe; datos inventados). Lo que la base decide lo prueba ia_pantallas.test.js y
// supabase/pruebas/mcp_f1_p4_ajustes.sql; aquí, lo que se VE y lo que se MANDA, en es y en, a 1440 y 390:
//  · ningún bloque lleva encima la etiqueta «IA» (ya lo dice la pestaña) y ninguno pasa de 3 campos;
//  · «Guardar los topes» no se ve en reposo, sale al cambiar un tope y se va si vuelve a su valor; al guardar se manda
//    ia_ajustes_guarda {p_datos} SOLO con el tope cambiado (lo de siempre);
//  · el interruptor sigue igual: «Encender la IA» a la vista y, con el tope a 0, no manda nada y lleva el foco al tope;
//  · la ficha de un asistente no repite su nombre («Claude Claude»);
//  · sin scroll horizontal;
//  · el equipo (17-oct-2026, sin permiso por persona: puede conectar todo el equipo activo): solo para mirar, sin ningún botón de
//    permiso, con las consultas de hoy y las conexiones vivas de cada persona;
//  · si la base rechaza un guardado, el aviso de error SE VE (toastMal es global, no de window).
// La interfaz se maneja por data-* (data-ia-*, data-accion), nunca por rótulo. Sale 1 si falla.
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
const VER = {
  ajustes: { encendido: false, tope_dia: 0, duracion_dias: 7, max_conexiones: 2, actualizado_en: '2026-10-16T09:00:00Z', actualizado_por: 'u-prueba' },
  clientes: [{ id: 'k1', asistente: 'claude', nombre: 'Claude', redirect_uris: ['https://claude.ai/api/mcp/auth_callback'], activo: true }],
  usuarios: [{ user_id: 'u-prueba', nombre: 'Persona de prueba', rol: 'super_admin', permiso: true, uso_hoy: 3 },
             { user_id: 'u-2', nombre: 'Ana Gestora', rol: 'admin', permiso: false, uso_hoy: 0 },
             { user_id: 'u-3', nombre: 'Baja Reciente', rol: 'agente', permiso: false, uso_hoy: 0 }],
  conexiones: [{ id: 'c1', usuario_id: 'u-2', cliente_id: 'k1', creada_en: '2026-10-15T02:00:00Z', expira_en: '2026-10-22T02:00:00Z', aal: 'aal1' }]
};
const FALSO = `(function () {
  var FICHA = { rol: 'super_admin', herramientas: [], activo: true, nombre: 'Persona de prueba', notif_visto_hasta: null, ambito: 'global', empresas: null, es_propietario: true };
  var TABLAS = { usuarios: [FICHA], empresas: [], parametros: [] };
  var RPC = {
    ia_ajustes_ver: ${JSON.stringify(VER)},
    ajustes_config_datos: { puede_escribir: true, valores: { marca: 'Lawang' }, actualizado: {}, editables: ['marca'] },
    ajustes_log_datos: { hay_mas: false, filas: [] },
    mantenimiento_datos: { envios_pausados: false, motivo: null, cambiado_en: null, intranet_cerrada: false, intranet_motivo: null, intranet_cambiado_en: null },
    reservas_vencimiento: []
  };
  window.__LLAMADAS = [];
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
    rpc: function (n, a) {
      // solo las escrituras: ia_mis_conexiones (aviso de la barra) e ia_ajustes_ver son lecturas
      if (/^ia_.*(_guarda|_revoca)$/.test(n)) {
        window.__LLAMADAS.push([n, JSON.parse(JSON.stringify(a || {}))]);
        // 99 días la rechaza la base (fuera de rango): el aviso de error tiene que verse
        if (n === 'ia_ajustes_guarda' && a && a.p_datos && a.p_datos.duracion_dias === 99) return Promise.resolve({ data: { error: 'fuera_de_rango' }, error: null });
        return Promise.resolve({ data: { ok: true }, error: null });
      }
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
const fallos = [];
const ok = (txt, cond) => { console.log((cond ? 'ok     ' : 'FALLA  ') + txt); if (!cond) fallos.push(txt); };
const PIE = '[data-accion="ia-guardar-topes"]';

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
      await p.goto(`http://127.0.0.1:${port}/intranet/v4/ajustes/#ia`, { waitUntil: 'load' });
      await p.waitForSelector('[data-ia-bloque="topes"]', { timeout: 15000 });
      const vis = (sel) => p.$eval(sel, e => e.offsetParent !== null);
      const m = await p.evaluate(() => {
        const secs = [...document.querySelectorAll('#lw-ia-aj > section')];
        return {
          n: secs.length,
          etiquetas: secs.map(s => s.querySelector('span.uppercase')).filter(Boolean).map(s => s.textContent.trim()),
          maxCampos: Math.max(...secs.map(s => [...s.querySelectorAll('input,select,textarea')].filter(e => e.offsetParent !== null).length)),
          cabCliente: document.querySelector('[data-ia-cliente="k1"] > div').innerText.replace(/\s+/g, ' ').trim(),
          scrollX: document.documentElement.scrollWidth > document.documentElement.clientWidth
        };
      });
      ok(pre + 'sin errores de página', errs.length === 0);
      ok(pre + 'los 5 bloques, ninguno con la etiqueta «IA» encima', m.n === 5 && m.etiquetas.length === 0);
      ok(pre + 'ningún bloque pasa de 3 campos', m.maxCampos <= 3);
      ok(pre + 'la ficha del asistente no repite su nombre («' + m.cabCliente + '»)', !/Claude\s+Claude/.test(m.cabCliente));
      ok(pre + 'sin scroll horizontal', !m.scrollX);
      ok(pre + '«Guardar los topes» no se ve en reposo', !(await vis(PIE)));
      ok(pre + '«Encender la IA» a la vista', await vis('[data-accion="ia-encender"]'));
      if (w === 1440) {
        await p.click('[data-accion="ia-encender"]');
        ok(pre + 'encender con tope 0: no manda nada y el foco va al tope', (await p.evaluate(() => window.__LLAMADAS.length)) === 0 &&
          (await p.evaluate(() => document.activeElement && document.activeElement.getAttribute('data-ia-tope'))) === 'tope_dia');
        await p.fill('[data-ia-tope="tope_dia"]', '50');
        ok(pre + 'al cambiar un tope sale «Guardar los topes»', await vis(PIE));
        await p.fill('[data-ia-tope="tope_dia"]', '0');
        ok(pre + 'si vuelve a su valor, se va', !(await vis(PIE)));
        await p.fill('[data-ia-tope="duracion_dias"]', '14');
        await p.click(PIE);
        await p.waitForFunction(() => window.__LLAMADAS.length > 0, null, { timeout: 5000 });
        const ll = await p.evaluate(() => window.__LLAMADAS);
        ok(pre + 'se manda ia_ajustes_guarda {p_datos} solo con lo cambiado (' + JSON.stringify(ll) + ')',
          ll.length === 1 && ll[0][0] === 'ia_ajustes_guarda' && JSON.stringify(ll[0][1]) === JSON.stringify({ p_datos: { duracion_dias: 14 } }));
        // un guardado que la base rechaza: el aviso es position:fixed (offsetParent siempre null): «se ve» = encendido (clase show)
        await p.waitForSelector(PIE, { state: 'hidden', timeout: 5000 }).catch(() => null);
        await p.fill('[data-ia-tope="duracion_dias"]', '99');
        await p.click(PIE);
        const seVe = () => { const t = document.getElementById('toastMal'); if (!t) return null;
          const cs = getComputedStyle(t); return t.classList.contains('show') && cs.display !== 'none' && cs.visibility !== 'hidden' ? t.textContent.trim() : null; };
        await p.waitForFunction(seVe, null, { timeout: 5000 }).catch(() => null);
        const avisoMal = await p.evaluate(seVe);
        ok(pre + 'guardado rechazado por la base: el aviso de error SE VE (' + avisoMal + ')', !!avisoMal);
      }
      // el equipo: solo para mirar (17-oct, sin permiso por persona)
      const eq = await p.evaluate(() => {
        const b = document.querySelector('[data-ia-bloque="equipo"]');
        const filas = b ? [...b.querySelectorAll('[data-ia-usuario-fila]')] : [];
        return { hay: !!b, filas: filas.length, botones: document.querySelectorAll('[data-accion^="ia-permiso"]').length,
                 viejo: !!document.querySelector('[data-ia-bloque="permisos"]'),
                 u2: (filas.find(f => f.getAttribute('data-ia-usuario-fila') === 'u-2') || {}).innerText || '' };
      });
      ok(pre + 'equipo: las 3 personas, sin ningún botón de permiso ni el bloque viejo (' + JSON.stringify(eq) + ')',
        eq.hay && eq.filas === 3 && eq.botones === 0 && !eq.viejo);
      ok(pre + 'equipo: la persona con una conexión viva lo dice (' + eq.u2.replace(/\s+/g, ' ') + ')', /\b1\b/.test(eq.u2) && eq.u2.length > 0);
      await ctx.close();
    }
  } finally { await b.close(); srv.close(); }
  console.log(fallos.length ? fallos.length + ' FALLA' : 'todo en verde');
  process.exit(fallos.length ? 1 : 0);
});
