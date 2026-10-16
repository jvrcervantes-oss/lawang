// node intranet/v4/assets/ajustes_servicios.harness.cjs [salida.json] [rol=super_admin]      (desde la raíz del repo de Lawang; necesita Edge)
// Arnés de Ajustes › «Servicios de AxisWorks» (ajustes-ux, 16-oct-2026): la página REAL (/intranet/v4/ajustes/) servida en local con un
// Supabase FALSO (window.LW_SB, que guard.js usa si existe; datos inventados). Recorre la pestaña como el super admin y mide lo que se MANDA
// a la base: cada campo cambiado de uno en uno, el tope propio de una empresa, encender el asistente y suspender sin motivo previo (hasta el
// 16-oct se confirmaba y luego se rechazaba), y que lo escrito sin guardar en otro bloque sobrevive a guardar uno. Con rol=admin: la pestaña
// tiene que quedar oculta. La interfaz se maneja por data-* (data-srv-in, data-accion, data-srv-empresa), nunca por rótulo. Sale 1 si falla.
const fs = require('fs'), path = require('path'), http = require('http');
const { chromium } = require(process.env.PLAYWRIGHT_CORE || 'C:/Users/jvrce/AppData/Roaming/npm/node_modules/@playwright/mcp/node_modules/playwright-core');
const RAIZ = path.resolve(__dirname, '..', '..', '..');
const [SALIDA, ROL = 'super_admin'] = process.argv.slice(2);
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.png': 'image/png', '.webp': 'image/webp', '.json': 'application/json' };
const srv = http.createServer((q, r) => {
  let p = decodeURIComponent(q.url.split('?')[0]); if (p.endsWith('/')) p += 'index.html';
  const f = path.join(RAIZ, p);
  if (!fs.existsSync(f)) { r.writeHead(404); r.end(); return; }
  r.writeHead(200, { 'content-type': MIME[path.extname(f)] || 'application/octet-stream' }); fs.createReadStream(f).pipe(r);
});
const FALSO = `/* Supabase FALSO para capturas de Ajustes (datos inventados). guard.js usa window.LW_SB si existe. */
(function () {
  var ROL = window.__ROL || 'super_admin';
  var FICHA = { rol: ROL, herramientas: [], activo: true, nombre: 'Persona de prueba', notif_visto_hasta: null, ambito: 'global', empresas: null, es_propietario: ROL === 'super_admin' };
  var EMPRESAS = [{ clave: 'emp_a', nombre: 'Empresa Uno', orden: 1, activa: true }, { clave: 'emp_b', nombre: 'Empresa Dos', orden: 2, activa: true }, { clave: 'emp_c', nombre: 'Empresa Tres', orden: 3, activa: true }];
  var TABLAS = { usuarios: [FICHA], empresas: EMPRESAS };
  var hoy = new Date(); var per = hoy.getFullYear() + '-' + String(hoy.getMonth() + 1).padStart(2, '0') + '-01';
  window.__GUARDADOS = [];
  var RPC = window.__RPC = {
    servicios_axisworks_datos: {
      periodo: per, zona: 'Asia/Makassar',
      instancia: { margen_pct: 30, tope_usd_defecto: 20, tope_instancia_usd: 100, aviso_pct: 80, gasto_usd: 12.4, actualizado_por: 'persona@ejemplo.test', actualizado_en: '2026-10-14T09:12:00Z' },
      tarifas: { modelo: 'claude-opus-5-5', tarifa_entrada_usd_mtok: 4, tarifa_salida_usd_mtok: 20, tarifa_deepl_usd_mcar: null },
      empresas: [
        { clave: 'emp_a', nombre: 'Empresa Uno', editor_ia: true, suspendido: false, tope_usd: null, tope_efectivo_usd: 20, gasto_usd: 8.1, falta: null },
        { clave: 'emp_b', nombre: 'Empresa Dos', editor_ia: false, suspendido: false, tope_usd: 5, tope_efectivo_usd: 5, gasto_usd: 0, falta: null },
        { clave: 'emp_c', nombre: 'Empresa Tres', editor_ia: true, suspendido: true, tope_usd: null, tope_efectivo_usd: 20, gasto_usd: 4.3, falta: null }],
      extracto: [
        { periodo: per, empresa: 'emp_a', hechas: 14, fallidas: 1, en_vuelo: 0, coste_proveedor_usd: 8.1, coste_no_repercutido_usd: 0.4, coste_facturable_usd: 7.7, margen_usd: 2.31, total_sin_impuestos_usd: 10.01, margenes_pct: [30], coste_incompleto: false },
        { periodo: per, empresa: 'emp_c', hechas: 6, fallidas: 0, en_vuelo: 0, coste_proveedor_usd: 4.3, coste_no_repercutido_usd: 0, coste_facturable_usd: 4.3, margen_usd: 1.29, total_sin_impuestos_usd: 5.59, margenes_pct: [30], coste_incompleto: true }],
      registro: [{ ambito: 'instancia', antes: {}, despues: {}, motivo: 'Subo el tope de la intranet', autor: 'persona@ejemplo.test', fecha: '2026-10-14T09:12:00Z' },
                 { ambito: 'emp_c', antes: {}, despues: {}, motivo: 'Factura de septiembre sin pagar', autor: 'persona@ejemplo.test', fecha: '2026-10-10T03:40:00Z' }]
    }
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
    rpc: function (n, a) {
      if (/_guarda$|_guardar$/.test(n)) { window.__GUARDADOS.push([n, JSON.parse(JSON.stringify(a || {}))]); return Promise.resolve({ data: { ok: true }, error: null }); }
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
const res = { pasos: [], fallos: [] };
srv.listen(0, async () => {
  const port = srv.address().port;
  const b = await chromium.launch({ channel: 'msedge' });
  const ctx = await b.newContext({ viewport: { width: 1440, height: 900 } });
  await ctx.addInitScript({ content: `window.__ROL='${ROL}';\n` + FALSO });
  const pg = await ctx.newPage(); const errs = [];
  pg.on('pageerror', e => errs.push(String(e.message).slice(0, 200)));
  await pg.goto(`http://127.0.0.1:${port}/intranet/v4/ajustes/#servicios`, { waitUntil: 'load' });
  await pg.waitForTimeout(1800);
  await pg.evaluate(() => { ['lw-novedades', 'lw-masc'].forEach(i => { const n = document.getElementById(i); if (n) n.remove(); }); });
  const visible = await pg.evaluate(() => { const p = document.querySelector('[data-lw-panel="servicios"]'); const t = document.querySelector('[data-lw-tab="servicios"]'); return { panel: !!p && !p.hidden, pestana: !!t && !t.hidden }; });
  res.visible = visible;
  if (ROL !== 'super_admin') {
    res.errs = errs; if (visible.pestana || visible.panel) res.fallos.push('la pestaña se ve con el rol ' + ROL);
    if (SALIDA) fs.writeFileSync(SALIDA, JSON.stringify(res, null, 1)); console.log(JSON.stringify(res));
    await b.close(); srv.close(); process.exitCode = res.fallos.length ? 1 : 0; return;
  }
  const n0 = () => pg.evaluate(() => window.__GUARDADOS.length);
  const ultimo = () => pg.evaluate(() => window.__GUARDADOS[window.__GUARDADOS.length - 1] || null);
  // abre lo plegado (si lo hay) para poder escribir
  const abrePlegados = () => pg.evaluate(() => document.querySelectorAll('#lw-srv details').forEach(d => { d.open = true; }));
  // escribe un valor en un data-srv-in (de la instancia o de una empresa), el motivo de SU bloque y pulsa SU guardar
  async function cambia(clave, valor, empresa) {
    await abrePlegados();
    const sel = empresa ? `[data-srv-empresa-fila="${empresa}"] [data-srv-in="${clave}"]` : `[data-srv-in="${clave}"]:not([data-srv-empresa-fila] *)`;
    const inp = pg.locator(sel).first();
    await inp.fill(String(valor)); await inp.dispatchEvent('input'); await inp.dispatchEvent('change');
    const antes = await n0();
    // el bloque del campo: el ancestro más cercano que tenga un botón servicios-guardar
    const ok = await pg.evaluate(([sel]) => {
      let n = document.querySelector(sel);
      while (n && !n.querySelector('[data-accion="servicios-guardar"]')) n = n.parentElement;
      if (!n) return 'sin bloque';
      const m = n.querySelector('[data-srv-motivo]'); if (!m) return 'sin motivo';
      m.value = 'Prueba de arnés'; m.dispatchEvent(new Event('input', { bubbles: true }));
      n.querySelector('[data-accion="servicios-guardar"]').click(); return 'ok';
    }, [sel]);
    await pg.waitForTimeout(300);
    const g = (await n0()) > antes ? await ultimo() : null;
    res.pasos.push({ paso: 'cambia ' + (empresa || 'instancia') + '.' + clave, ok, enviado: g });
  }
  for (const [k, v] of [['margen_pct', 35], ['aviso_pct', 75], ['tope_usd_defecto', 25], ['tope_instancia_usd', 150], ['tarifa_entrada_usd_mtok', 4.5], ['tarifa_salida_usd_mtok', 22]]) await cambia(k, v);
  await cambia('tope_usd', 7, 'emp_b');
  // interruptor con motivo: encender el asistente de Empresa Dos; suspender Empresa Uno SIN haber escrito antes nada (la trampa)
  async function interruptor(accion, empresa, previo) {
    const antes = await n0();
    // «previo»: el motivo ya escrito en la caja de esa empresa, como se hacía hasta hoy (si la caja está a la vista)
    if (previo) await pg.evaluate((e) => { const m = document.querySelector('[data-srv-empresa-fila="' + e + '"] [data-srv-motivo]'); if (m && m.offsetParent) { m.value = 'Prueba de arnés'; m.dispatchEvent(new Event('input', { bubbles: true })); } }, empresa);
    await pg.locator(`[data-accion="${accion}"][data-srv-empresa="${empresa}"]`).first().click();
    await pg.waitForTimeout(250);
    // si la interfaz pide el motivo DENTRO del paso (después del arreglo), se escribe ahí
    const pide = await pg.evaluate(() => { const m = document.querySelector('[data-srv-paso] [data-srv-motivo-paso]'); if (!m) return false; m.value = 'Prueba de arnés'; m.dispatchEvent(new Event('input', { bubbles: true })); return true; });
    // confirmar: el botón del paso (después) o el de lwConfirmar (antes)
    await pg.evaluate(() => { const b = document.querySelector('[data-srv-paso] [data-accion="servicios-confirmar"]') || document.querySelector('.lw-dlg-fondo.abierto .btn.primary'); if (b) b.click(); });
    await pg.waitForTimeout(400);
    const toast = await pg.evaluate(() => { const t = document.querySelector('#lw-toast, .lw-toast, [data-lw-toast]'); return t ? t.textContent.trim() : null; });
    const g = (await n0()) > antes ? await ultimo() : null;
    res.pasos.push({ paso: accion + ' ' + empresa, pideMotivoEnElPaso: pide, enviado: g, toast });
  }
  await interruptor('servicios-editor_ia', 'emp_b', true);
  await interruptor('servicios-suspendido', 'emp_a');
  // lo escrito y sin guardar en OTRO bloque sobrevive a guardar uno: tope propio de Empresa Tres a medias, se guarda el margen
  await pg.locator('[data-srv-empresa-fila="emp_c"] [data-srv-in="tope_usd"]').fill('9');
  await cambia('margen_pct', 33);
  await pg.waitForTimeout(300);
  const queda = await pg.evaluate(() => { const i = document.querySelector('[data-srv-empresa-fila="emp_c"] [data-srv-in="tope_usd"]'); return i ? i.value : null; });
  res.conserva = queda;
  if (queda !== '9') res.fallos.push('SE PIERDE LO ESCRITO: el tope a medias de Empresa Tres quedó en «' + queda + '» al guardar el margen');
  // la trampa: suspender sin motivo previo tiene que acabar en un envío con motivo, no en confirmar y luego rechazar
  const s = res.pasos[res.pasos.length - 1];
  if (!s.enviado) res.fallos.push('TRAMPA: suspender por impago sin motivo previo se confirma y no se guarda');
  res.pasos.filter(p => p.paso.startsWith('cambia') && !p.enviado).forEach(p => res.fallos.push('no se guardó: ' + p.paso + ' (' + p.ok + ')'));
  res.errs = errs;
  if (SALIDA) fs.writeFileSync(SALIDA, JSON.stringify(res, null, 1));
  console.log(JSON.stringify(res, null, 1));
  console.log(res.fallos.length ? 'FALLA ' + res.fallos.length : 'ok: ' + res.pasos.length + ' pasos, nada se pierde');
  await b.close(); srv.close();
  process.exitCode = res.fallos.length ? 1 : 0;
});
