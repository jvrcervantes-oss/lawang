#!/usr/bin/env node
/* arnes_reclamo_pago.js — ARNÉS de «Reclamar pago» en la ficha de parcela (/intranet/v4/proyectos/, 8-oct-2026).
   A MANO: necesita Edge + playwright-core, así que no va en el gate.

   Qué hace: sirve la copia de Lawang desde disco bajo http://lawang.local, cambia el CDN de supabase-js por un cliente FALSO
   (admin de empresa, un proyecto, tres parcelas y las tres RPC de la pantalla con datos SINTÉTICOS) y recorre la ficha de
   parcela. NO toca producción, NO llama a ninguna red, NO envía nada: `reclamo_pago_encolar` y `reclamo_pago_prueba` son
   mocks que solo APUNTAN la llamada. Lo que valida el SERVIDOR (permiso, pertenencia, sociedad, tope, nota) se prueba por
   las RPC en supabase/pruebas/reclamo_pago.sql; esto prueba que la pantalla pregunta bien, manda solo lo que debe, pinta lo
   que contesta la base (también los errores) y cabe en un panel estrecho de altura baja.

   Casos (?c=): base · nadie (nadie seleccionable) · perm (sin permiso) · fallo (error de la base) · vacio (parcela sin contrato).
   Otros: ?enc=hostil (el mock rechaza toda nota con nota_invalida) · ?prueba=falta (la RPC de prueba no existe aún).
   Idiomas: es y en (la suite no tiene interfaz en indonesio: idioma.js solo conoce es/en).

   Uso:  NODE_PATH=<carpeta con playwright-core> node arnes_reclamo_pago.js --raiz <copia de Lawang> [--png <prefijo>]
   Sale con 1 si algo falla. */
const { chromium } = require('playwright-core');
const fs = require('fs');
const path = require('path');
const arg = (k, d) => { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : d; };
if (!arg('--raiz')) { console.error('falta --raiz <copia de Lawang>'); process.exit(2); }
const RAIZ = path.resolve(arg('--raiz'));
const PNG = arg('--png', null);
const EDGE = process.env.ARNES_EDGE || 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const HOST = 'http://lawang.local';
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json', '.css': 'text/css', '.png': 'image/png', '.webp': 'image/webp', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.woff2': 'font/woff2' };

const FIX = {
  usuarios: [{ user_id: 'u1', rol: 'admin_empresa', ambito: 'empresa', empresas: ['lawang'], herramientas: ['unidades'], activo: true, nombre: 'Admin Uno', notif_visto_hasta: null, es_propietario: false, email: 'admin.uno@prueba.test' }],
  empresas: [{ clave: 'lawang', nombre: 'Lawang', orden: 1, activa: true }],
  proyectos: [{ id: 'p1', nombre: 'Sumba Hills', slug: 'sumba-hills', resort: 'Sumba', empresa: 'lawang', ubicacion_maps: null, parcela_master: 'M1', parcela_master_m2: 10000, fecha_entrega_estimada_proyecto: null, fecha_entrega_estimada_fijada_en: null, estado: 'comercializacion', pct_minimo_inicio: 30, activo: true }],
  unidades: [],
  unidades_estado: [
    { id: 'u-a', codigo: 'SH-1', proyecto: 'Sumba Hills', proyecto_id: 'p1', tipo: 'parcela', modelo: 'Parcela', estado: 'vendida', precio: 100000, precio_suelo: 100000, precio_construccion: null, superficie_m2: 500, moneda: 'EUR', codigo_orden: 1, contrato_id: 'c1', contrato_numero: 'PPJB-1', comprador_nombre: 'Ana Sol' },
    { id: 'u-b', codigo: 'SH-2', proyecto: 'Sumba Hills', proyecto_id: 'p1', tipo: 'parcela', modelo: 'Parcela', estado: 'vendida', precio: 100000, precio_suelo: 100000, precio_construccion: null, superficie_m2: 500, moneda: 'EUR', codigo_orden: 2, contrato_id: 'c2', contrato_numero: 'PPJB-2', comprador_nombre: 'Zoe' },
    { id: 'u-c', codigo: 'SH-3', proyecto: 'Sumba Hills', proyecto_id: 'p1', tipo: 'parcela', modelo: 'Parcela', estado: 'disponible', precio: 100000, precio_suelo: 100000, precio_construccion: null, superficie_m2: 500, moneda: 'EUR', codigo_orden: 3, contrato_id: null, contrato_numero: null, comprador_nombre: null }
  ]
};

/* El cliente FALSO. Todo por parámetros de la URL. */
const STUB = `(function(){
  var FIX = ${JSON.stringify(FIX)};
  var q0 = new URLSearchParams(location.search), C = q0.get('c') || 'base';
  window.__RPC = [];
  window.__ESCRITURAS = [];
  function q(tabla){
    var filas = (FIX[tabla] || []).slice(), unico = false;
    var b = new Proxy({}, { get: function(_, k){
      if (k === 'then') return function(ok, ko){ var d = unico ? (filas[0] || null) : filas; return Promise.resolve({ data: d, error: null, count: filas.length }).then(ok, ko); };
      if (k === 'eq') return function(c, v){ filas = filas.filter(function(f){ return f[c] === v; }); return b; };
      if (k === 'maybeSingle' || k === 'single') return function(){ unico = true; return b; };
      if (k === 'insert' || k === 'update' || k === 'delete' || k === 'upsert') return function(){ window.__ESCRITURAS.push({ tabla: tabla, op: k }); return b; };
      return function(){ return b; };
    }});
    return b;
  }
  function ok(d, ms){ return new Promise(function(r){ setTimeout(function(){ r({ data: d, error: null }); }, ms || 0); }); }
  function mal(m, hint, code){ return Promise.resolve({ data: null, error: { message: m, hint: hint || null, code: code || '22023' } }); }
  var DEST = [
    { contrato_id: 'c1', client_id: 'k-ana', nombre: 'Ana Sol <b>X</b>', email_oculto: 'a***@correo.test', idioma: 'es', seleccionable: true, motivo: null, empresa: 'Lawang', sociedad: 'PT Lawang Tropical Properties', parcela: 'SH-1', proyecto: 'Sumba Hills', ultimo_reclamo_en: '2026-10-01T09:30:00Z', ultimo_estado: 'enviado', ultimo_enviado_en: '2026-10-01T09:31:00Z' },
    { contrato_id: 'c3', client_id: 'k-ben', nombre: 'Ben Ocean', email_oculto: 'b***@mail.test', idioma: 'en', seleccionable: true, motivo: null, empresa: 'Lawang', sociedad: 'PT Lawang Tropical Properties', parcela: 'SH-1', proyecto: 'Sumba Hills', ultimo_reclamo_en: null, ultimo_estado: null, ultimo_enviado_en: null },
    { contrato_id: 'c4', client_id: 'k-carla', nombre: 'Carla Mar', email_oculto: 'c***@mail.test', idioma: null, seleccionable: true, motivo: null, empresa: 'Lawang', sociedad: 'PT Lawang Tropical Properties', parcela: 'SH-1', proyecto: 'Sumba Hills', ultimo_reclamo_en: null, ultimo_estado: null, ultimo_enviado_en: null },
    { contrato_id: 'c5', client_id: 'k-dani', nombre: 'Dani Sin Correo', email_oculto: null, idioma: 'es', seleccionable: false, motivo: 'sin_email', empresa: 'Lawang', sociedad: 'PT Lawang Tropical Properties', parcela: 'SH-1', proyecto: 'Sumba Hills', ultimo_reclamo_en: null, ultimo_estado: null, ultimo_enviado_en: null },
    { contrato_id: 'c6', client_id: null, nombre: null, email_oculto: null, idioma: null, seleccionable: false, motivo: 'sin_ficha', empresa: 'Lawang', sociedad: 'PT Lawang Tropical Properties', parcela: 'SH-1', proyecto: 'Sumba Hills', ultimo_reclamo_en: null, ultimo_estado: null, ultimo_enviado_en: null }
  ];
  var HIST = [
    { reclamo_id: 'r1', creado_en: '2026-10-01T09:30:00Z', creado_por: 'admin.uno@prueba.test', client_id: 'k-ana', nombre: 'Ana Sol <b>X</b>', estado: 'enviado', enviado_en: '2026-10-01T09:31:00Z', error: null, nota: 'Quedan 2.000 EUR <i>hoy</i>' },
    { reclamo_id: 'r2', creado_en: '2026-09-20T09:30:00Z', creado_por: 'otra@prueba.test', client_id: 'k-ben', nombre: 'Ben Ocean', estado: 'error', enviado_en: null, error: 'buzon lleno', nota: null }
  ];
  function rpc(n, a){
    window.__RPC.push({ n: n, a: JSON.parse(JSON.stringify(a || {})) });
    if (n === 'reclamo_pago_destinatarios') {
      if (C === 'perm') return mal('No tienes permiso sobre esta parcela.', 'sin_permiso', '42501');
      if (C === 'fallo') return mal('boom de la base', null, 'XX000');
      if (C === 'vacio' || a.p_unidad === 'u-b') return ok([], a.p_unidad === 'u-b' ? 0 : 0);
      if (a.p_unidad === 'u-a' && q0.get('lento') === '1') return ok(DEST, 900);
      if (C === 'nadie') return ok(DEST.filter(function(d){ return !d.seleccionable; }));
      if (C === 'una') return ok(DEST.slice(0, 1).concat(DEST.slice(3)));
      return ok(DEST);
    }
    if (n === 'reclamo_pago_historial') {
      if (C === 'perm') return mal('No tienes permiso sobre esta parcela.', 'sin_permiso', '42501');
      if (C === 'histfallo') return mal('historial roto', null, 'XX000');
      if (C === 'vacio' || C === 'una' || a.p_unidad === 'u-b') return ok([]);
      return ok(HIST);
    }
    if (n === 'reclamo_pago_encolar') {
      var hostil = q0.get('enc') === 'hostil';
      if (hostil) return mal('mensaje en castellano que NO se debe mostrar', 'nota_invalida');
      if (q0.get('enc') === 'doble') return mal('x', 'doble_clic');
      if (q0.get('enc') === 'roto') return mal('db caida', null, 'XX000');
      return ok({ n: a.p_clients.length, reclamos: [] });
    }
    if (n === 'reclamo_pago_prueba') {
      if (q0.get('prueba') === 'falta') return mal('Could not find the function public.reclamo_pago_prueba', null, 'PGRST202');
      return ok('admin.uno@prueba.test');
    }
    return q(n);
  }
  var sb = { from: q, rpc: rpc, supabaseUrl: 'https://sb.fake',
    storage: { from: function(){ return { getPublicUrl: function(p){ return { data: { publicUrl: 'https://sb.fake/' + p } }; } }; } },
    auth: { getSession: function(){ return Promise.resolve({ data: { session: { access_token: 'jwt-falso', user: { id: 'u1', email: 'admin.uno@prueba.test', app_metadata: {} } } } }); }, signOut: function(){ return Promise.resolve({}); }, onAuthStateChange: function(){ return { data: { subscription: { unsubscribe: function(){} } } }; } },
    channel: function(){ var c = { on: function(){ return c; }, subscribe: function(){ return c; } }; return c; }, removeChannel: function(){} };
  window.supabase = { createClient: function(){ return sb; } };
})();`;

const fallos = [];
const ok = (c, m) => { if (!c) { fallos.push(m); console.log('FALLO  ' + m); } else console.log('ok     ' + m); return !!c; };

async function nueva(browser, ancho, alto, query, idioma) {
  const ctx = await browser.newContext({ viewport: { width: ancho, height: alto } });
  await ctx.addInitScript((i) => { try { localStorage.setItem('lawang_idioma_ui', i); } catch (e) { /* sin almacenamiento */ } }, idioma);
  const page = await ctx.newPage();
  const errores = [];
  page.on('pageerror', e => errores.push(String(e)));
  page.on('console', m => { if (m.type() === 'error' && !/Failed to load resource|net::ERR/.test(m.text())) errores.push(m.text().slice(0, 200)); });
  await page.route('**/*', async route => {
    const u = new URL(route.request().url());
    if (u.origin === HOST) {
      let p = decodeURIComponent(u.pathname); if (p.endsWith('/')) p += 'index.html';
      const f = path.join(RAIZ, p);
      if (fs.existsSync(f) && fs.statSync(f).isFile()) {
        let body = fs.readFileSync(f);
        if (path.extname(f) === '.html') body = Buffer.from(body.toString('utf8').replace(/\sintegrity="[^"]*"/g, ''), 'utf8');
        return route.fulfill({ status: 200, contentType: MIME[path.extname(f)] || 'application/octet-stream', body });
      }
      return route.fulfill({ status: 404, body: '' });
    }
    if (/supabase\.min\.js/.test(u.href)) return route.fulfill({ status: 200, contentType: 'text/javascript', body: STUB });
    if (u.protocol === 'data:' || u.protocol === 'blob:') return route.continue();
    return route.fulfill({ status: 200, contentType: /\.css|fonts\.googleapis/.test(u.href) ? 'text/css' : 'text/javascript', body: '' });
  });
  await page.goto(HOST + '/intranet/v4/proyectos/?' + (query || ''), { waitUntil: 'load' });
  return { ctx, page, errores };
}
const rpcs = (page, n) => page.evaluate((n) => window.__RPC.filter(x => x.n === n), n);
const T = (es, en, idioma) => idioma === 'en' ? en : es;

/* abre el proyecto y luego la parcela con ese código */
async function abreParcela(page, codigo) {
  if (!(await page.locator('#cajon-detalle:not(.translate-x-full)').count())) {
    await page.locator('[data-abrir-cajon]').first().click({ timeout: 15000 }).catch(async () => { await page.locator('[data-lw="nombre"]').first().click(); });
    await page.waitForFunction(() => window.LW_V4 && window.LW_V4.unidades && Object.keys(window.LW_V4.unidades).length > 0, null, { timeout: 15000 });
  }
  await page.evaluate((c) => {
    const u = Object.values(window.LW_V4.unidades).filter(x => x.codigo === c)[0];
    window.LW_V4.abrirDetalleUnidad(u.id);
  }, codigo);
}
const bloqueVisible = (page) => page.locator('[data-lw="rp-bloque"]').evaluate(el => !el.classList.contains('hidden') && el.offsetParent !== null).catch(() => false);
const botonVisible = (page) => page.locator('[data-accion="reclamar-pago"]').evaluate(el => !el.hidden && el.offsetParent !== null).catch(() => false);
const esperaPanel = (page) => page.waitForTimeout(500);

(async () => {
  const browser = await chromium.launch({ executablePath: EDGE, headless: true });

  if (process.env.ARNES_DEBUG) {            // para ver qué pinta la página con el cliente falso
    const { ctx, page, errores } = await nueva(browser, 1440, 900, 'c=base', 'es');
    await page.waitForTimeout(4000);
    console.log('ERRORES', errores);
    console.log(await page.evaluate(() => ({ n: document.querySelectorAll('[data-lw="nombre"]').length, texto: document.body.innerText.slice(0, 600) })));
    if (PNG) await page.screenshot({ path: PNG + '_debug.png' });
    await ctx.close(); await browser.close(); return;
  }

  for (const idioma of ['es', 'en']) {
    for (const [ancho, alto] of [[1440, 900], [1280, 560]]) {
      const t = idioma + ' ' + ancho + 'x' + alto + ': ';
      /* ── A. caso base: botón, historial, diálogo ── */
      {
        const { ctx, page, errores } = await nueva(browser, ancho, alto, 'c=base', idioma);
        await abreParcela(page, 'SH-1'); await esperaPanel(page);
        ok(await botonVisible(page), t + 'hay seleccionables: el botón «Reclamar pago» se ve');
        ok((await page.locator('[data-accion="reclamar-pago"]').textContent()).trim() === T('Reclamar pago', 'Request payment', idioma), t + 'el botón dice «' + T('Reclamar pago', 'Request payment', idioma) + '»');
        const dest = (await rpcs(page, 'reclamo_pago_destinatarios'));
        ok(dest.length === 1 && dest[0].a.p_unidad === 'u-a' && Object.keys(dest[0].a).join() === 'p_unidad', t + 'destinatarios: solo manda la parcela');
        const hist = await page.locator('[data-lw="rp-hist-fila"]').allTextContents();
        ok(hist.length === 2 && /Enviado|Sent/.test(hist[0]) && /Con error|Failed/.test(hist[1]), t + 'historial: dos filas con su estado');
        ok(!/<b>|<i>/.test(await page.locator('[data-lw="rp-historial"]').innerHTML().then(h => h.replace(/&lt;/g, '')).catch(() => '')) || true, t + 'historial escapa (ver abajo)');
        ok((await page.locator('[data-lw="rp-historial"] b, [data-lw="rp-historial"] i').count()) === 0, t + 'el nombre y la nota del historial con etiquetas salen como texto, no como HTML');
        if (PNG) await page.screenshot({ path: PNG + '_panel_' + t.replace(/[ :]+/g, '_') + '.png' });
        // panel de altura baja: el botón se alcanza haciendo scroll en el panel
        const alcance = await page.locator('[data-accion="reclamar-pago"]').evaluate(el => { el.scrollIntoView({ block: 'center' }); const r = el.getBoundingClientRect(); return r.top >= 0 && r.bottom <= innerHeight; });
        ok(alcance, t + 'el botón se alcanza con scroll del panel');

        await page.locator('[data-accion="reclamar-pago"]').click();
        await page.waitForSelector('#lw-editor [data-lw="rp-destinatarios"]', { timeout: 8000 });
        await page.waitForTimeout(500);
        ok((await rpcs(page, 'reclamo_pago_destinatarios')).length === 2, t + 'al abrir el diálogo se vuelve a leer la lista (no se fía de la del panel)');
        const cajas = await page.locator('#lw-editor [data-rp-cliente]').count();
        ok(cajas === 3, t + 'tres casillas: solo los seleccionables (' + cajas + ')');
        const noSel = await page.locator('#lw-editor [data-lw="rp-dest-no"]').allTextContents();
        ok(noSel.length === 2 && noSel.some(x => /Dani/.test(x) && /(correo válido|valid email)/.test(x)) && noSel.some(x => /(ficha de cliente|client record)/.test(x)), t + 'los no seleccionables salen sin casilla y con su motivo');
        ok((await page.locator('#lw-editor [data-lw="rp-idioma"]').count()) === 2, t + 'aviso de idioma para en y para sin idioma, no para es');
        ok(/(español|Spanish)/.test(await page.locator('#lw-editor [data-lw="rp-idioma"]').first().textContent()), t + 'el aviso dice que recibirá el correo en español');
        ok((await page.locator('#lw-editor [data-lw="rp-ultimo"]').count()) === 1, t + 'último recordatorio solo como dato (una persona)');
        ok(await page.locator('#lw-editor [data-rp-cliente]:checked').count() === 0, t + 'nadie marcado de salida: se marca a mano');
        const cuerpoDlg = await page.locator('#lw-editor').textContent();
        ok(/(no una notificación formal de mora|not a formal notice of default)/.test(cuerpoDlg), t + 'aviso «no es una notificación formal de mora»');
        ok(/(No escribas datos de pago, cuentas ni enlaces|Do not write payment details, accounts or links)/.test(cuerpoDlg), t + 'aviso «no escribas datos de pago, cuentas ni enlaces»');
        ok(await page.locator('#lw-editor [data-rp="nota"]').getAttribute('maxlength') === '300', t + 'nota con tope de 300');
        ok(/PT Lawang Tropical Properties/.test(cuerpoDlg), t + 'dice en nombre de qué sociedad se envía');
        ok((await page.locator('#lw-editor b').count()) === 0, t + 'el nombre con etiquetas del diálogo sale como texto');
        if (PNG) await page.screenshot({ path: PNG + '_dialogo_' + t.replace(/[ :]+/g, '_') + '.png' });

        // sin marcar a nadie
        await page.locator('#lw-editor [data-e="guardar"]').click();
        await page.waitForTimeout(300);
        ok(/(Marca al menos una persona|Tick at least one person)/.test(await page.locator('#lw-editor [data-e="error"]').textContent()) && !/No se pudo guardar/.test(await page.locator('#lw-editor [data-e="error"]').textContent()), t + 'sin marcar a nadie: lo dice, sin «No se pudo guardar», y no llama al servidor');
        ok((await rpcs(page, 'reclamo_pago_encolar')).length === 0, t + 'sin marcar: ninguna llamada de envío');

        // nota con enlace: la corta la pantalla antes de viajar
        await page.locator('#lw-editor [data-rp-cliente="k-ana"]').check();
        await page.locator('#lw-editor [data-rp="nota"]').fill('mira http://pago.example/x');
        ok(await page.locator('#lw-editor [data-rp="nota-error"]').isVisible(), t + 'nota con enlace: aviso en rojo al escribir');
        await page.locator('#lw-editor [data-e="guardar"]').click();
        await page.waitForTimeout(300);
        ok((await rpcs(page, 'reclamo_pago_encolar')).length === 0 && !(await page.locator('.lw-dlg-fondo').count()), t + 'nota con enlace: no se pide confirmación ni se llama a la base');
        await page.locator('#lw-editor [data-accion="reclamo-prueba"]').click();
        await page.waitForTimeout(200);
        ok((await rpcs(page, 'reclamo_pago_prueba')).length === 0, t + 'nota con enlace: tampoco se manda la prueba');
        await page.locator('#lw-editor [data-rp="nota"]').fill('con arroba a@b');
        ok(await page.locator('#lw-editor [data-rp="nota-error"]').isVisible(), t + 'nota con @ rechazada');
        await page.locator('#lw-editor [data-rp="nota"]').fill('Quedan 2.000 EUR pendientes');
        ok(!(await page.locator('#lw-editor [data-rp="nota-error"]').isVisible()), t + 'una nota normal quita el aviso');
        ok(/27 (de|of) 300/.test(await page.locator('#lw-editor [data-rp="cuenta"]').textContent()), t + 'contador de la nota');

        // prueba
        await page.locator('#lw-editor [data-accion="reclamo-prueba"]').click();
        await page.waitForSelector('#lw-editor [data-rp="prueba-msg"]:not([hidden])', { timeout: 4000 });
        const pr = await rpcs(page, 'reclamo_pago_prueba');
        ok(pr.length === 1 && pr[0].a.p_unidad === 'u-a' && pr[0].a.p_nota === 'Quedan 2.000 EUR pendientes' && Object.keys(pr[0].a).sort().join() === 'p_nota,p_unidad', t + 'la prueba manda solo parcela y nota (el destino lo pone la base: quien pulsa)');
        ok(/admin\.uno@prueba\.test/.test(await page.locator('#lw-editor [data-rp="prueba-msg"]').textContent()), t + 'la prueba dice a qué correo va');

        // envío: confirmación con destinatarios, cancelar no envía
        await page.locator('#lw-editor [data-rp-cliente="k-ben"]').check();
        await page.locator('#lw-editor [data-e="guardar"]').click();
        await page.waitForSelector('.lw-dlg-fondo', { timeout: 4000 });
        const conf = await page.locator('.lw-dlg-fondo').first().textContent();
        ok(/Ana Sol/.test(conf) && /Ben Ocean/.test(conf) && !/Carla/.test(conf) && /(2 personas|2 people)/.test(conf), t + 'la confirmación nombra a los marcados y solo a ellos');
        ok(/Quedan 2\.000 EUR pendientes/.test(conf) && /(no se puede retirar|cannot be withdrawn)/.test(conf), t + 'la confirmación enseña la nota y avisa de que no se retira');
        if (PNG) await page.screenshot({ path: PNG + '_confirma_' + t.replace(/[ :]+/g, '_') + '.png' });
        await page.locator('.lw-dlg-fondo button').filter({ hasText: /Cancelar|Cancel/ }).first().click();
        await page.waitForTimeout(400);
        ok((await rpcs(page, 'reclamo_pago_encolar')).length === 0, t + 'cancelar la confirmación no envía nada');
        ok(!(await page.locator('#lw-editor [data-e="error"]').isVisible()), t + 'cancelar no deja un error en rojo');
        // ahora sí (el mock NO envía nada a nadie)
        await page.locator('#lw-editor [data-e="guardar"]').click();
        await page.waitForSelector('.lw-dlg-fondo', { timeout: 4000 });
        await page.locator('.lw-dlg-fondo button').filter({ hasText: /^(Enviar a 2 personas|Send to 2 people)$/ }).click();
        await page.waitForFunction(() => window.__RPC.some(x => x.n === 'reclamo_pago_encolar'), null, { timeout: 4000 });
        const en = (await rpcs(page, 'reclamo_pago_encolar'))[0];
        ok(en && en.a.p_unidad === 'u-a' && JSON.stringify(en.a.p_clients) === JSON.stringify(['k-ana', 'k-ben']) && en.a.p_nota === 'Quedan 2.000 EUR pendientes' && Object.keys(en.a).sort().join() === 'p_clients,p_nota,p_unidad', t + 'el envío manda solo unidad, ids de cliente y nota');
        await page.waitForTimeout(900);
        ok(!(await page.locator('#lw-editor').count()), t + 'tras enviar el diálogo se cierra');
        ok((await rpcs(page, 'reclamo_pago_historial')).length === 2, t + 'tras enviar se recarga el historial');
        ok(await page.evaluate(() => window.__ESCRITURAS.length) === 0, t + 'ninguna escritura directa a tablas desde el navegador');
        ok(errores.length === 0, t + 'sin errores de consola' + (errores.length ? ': ' + errores.join(' | ') : ''));
        await ctx.close();
      }
    }
  }

  const idi = 'es';
  /* ── B. nadie seleccionable ── */
  {
    const { ctx, page, errores } = await nueva(browser, 1440, 900, 'c=nadie', idi);
    await abreParcela(page, 'SH-1'); await esperaPanel(page);
    ok(await bloqueVisible(page) && !(await botonVisible(page)), 'nadie seleccionable: sin botón, pero el panel explica por qué');
    ok(/nadie de esta parcela puede recibir/.test(await page.locator('[data-lw="rp-nadie"]').textContent()), 'nadie seleccionable: mensaje propio');
    ok(/Dani/.test(await page.locator('[data-lw="rp-estado"]').textContent()), 'nadie seleccionable: lista a quién y por qué');
    ok(errores.length === 0, 'nadie: sin errores de consola');
    await ctx.close();
  }
  /* ── C. sin permiso (agente): nada de nada ── */
  {
    const { ctx, page, errores } = await nueva(browser, 1440, 900, 'c=perm', idi);
    await abreParcela(page, 'SH-1'); await esperaPanel(page);
    ok(!(await bloqueVisible(page)) && !(await botonVisible(page)), 'sin permiso: ni botón ni bloque');
    ok(errores.length === 0, 'sin permiso: sin errores de consola');
    await ctx.close();
  }
  /* ── D. fallo de la base ≠ nadie ── */
  {
    const { ctx, page } = await nueva(browser, 1440, 900, 'c=fallo', idi);
    await abreParcela(page, 'SH-1'); await esperaPanel(page);
    ok(await bloqueVisible(page) && /No se pudo comprobar/.test(await page.locator('[data-lw="rp-error"]').textContent()), 'error de la base: se dice «no se pudo comprobar», distinto de «nadie»');
    ok(!(await botonVisible(page)), 'error de la base: sin botón');
    await ctx.close();
  }
  /* ── E. parcela sin contrato ── */
  {
    const { ctx, page } = await nueva(browser, 1440, 900, 'c=vacio', idi);
    await abreParcela(page, 'SH-3'); await esperaPanel(page);
    ok(!(await bloqueVisible(page)), 'parcela sin contrato: nada que enseñar');
    await ctx.close();
  }
  /* ── F. historial roto no esconde el botón y se ve distinto de «vacío» ── */
  {
    const { ctx, page } = await nueva(browser, 1440, 900, 'c=histfallo', idi);
    await abreParcela(page, 'SH-1'); await esperaPanel(page);
    ok(await botonVisible(page) && /No se pudo cargar el historial/.test(await page.locator('[data-lw="rp-hist-error"]').textContent()), 'historial roto: botón sí, y el fallo se dice (no se confunde con «sin envíos»)');
    await ctx.close();
  }
  /* ── G. respuesta vieja: abrir SH-1 (lenta) y luego SH-2 enseguida ── */
  {
    const { ctx, page } = await nueva(browser, 1440, 900, 'c=base&lento=1', idi);
    await abreParcela(page, 'SH-1');
    await page.evaluate(() => { const u = Object.values(window.LW_V4.unidades).filter(x => x.codigo === 'SH-2')[0]; window.LW_V4.abrirDetalleUnidad(u.id); });
    await page.waitForTimeout(1500);
    ok(!(await bloqueVisible(page)) && !(await botonVisible(page)), 'respuesta vieja: lo de SH-1 no se pinta en SH-2');
    await ctx.close();
  }
  /* ── H. rechazos de la base mostrados en llano ── */
  for (const [enc, rx, nombre] of [['hostil', /hasta 300 caracteres de texto, sin enlaces/, 'nota_invalida'], ['doble', /hace unos segundos/, 'doble_clic'], ['roto', /No se pudo enviar: db caida/, 'error genérico']]) {
    const { ctx, page, errores } = await nueva(browser, 1440, 900, 'c=base&enc=' + enc, idi);
    await abreParcela(page, 'SH-1'); await esperaPanel(page);
    await page.locator('[data-accion="reclamar-pago"]').click();
    await page.waitForSelector('#lw-editor [data-rp-cliente]');
    await page.locator('#lw-editor [data-rp-cliente="k-ana"]').check();
    await page.locator('#lw-editor [data-rp="nota"]').fill('una nota normal');
    await page.locator('#lw-editor [data-e="guardar"]').click();
    await page.waitForSelector('.lw-dlg-fondo');
    await page.locator('.lw-dlg-fondo button').filter({ hasText: /^Enviar a 1 persona$/ }).click();
    await page.waitForFunction(() => /\S/.test((document.querySelector('#lw-editor [data-e="error"]') || {}).textContent || ''), null, { timeout: 4000 });
    const msg = await page.locator('#lw-editor [data-e="error"]').textContent();
    ok(rx.test(msg) && !/NO se debe mostrar/.test(msg) && !/^No se pudo guardar/.test(msg), 'rechazo ' + nombre + ': se muestra en llano por el hint — «' + msg.slice(0, 80) + '»');
    ok(await page.locator('#lw-editor').count() === 1, 'rechazo ' + nombre + ': el diálogo sigue abierto con lo escrito');
    ok(await page.locator('#lw-editor [data-rp="nota"]').inputValue() === 'una nota normal', 'rechazo ' + nombre + ': no se pierde la nota');
    if (PNG && enc === 'hostil') await page.screenshot({ path: PNG + '_rechazo_nota.png' });
    ok(errores.length === 0, 'rechazo ' + nombre + ': sin errores de consola');
    await ctx.close();
  }
  /* ── I. la RPC de prueba aún no existe ── */
  {
    const { ctx, page } = await nueva(browser, 1440, 900, 'c=base&prueba=falta', idi);
    await abreParcela(page, 'SH-1'); await esperaPanel(page);
    await page.locator('[data-accion="reclamar-pago"]').click();
    await page.waitForSelector('#lw-editor [data-accion="reclamo-prueba"]');
    await page.locator('#lw-editor [data-accion="reclamo-prueba"]').click();
    await page.waitForSelector('#lw-editor [data-rp="prueba-msg"]:not([hidden])');
    ok(/todavía no está disponible en el servidor/.test(await page.locator('#lw-editor [data-rp="prueba-msg"]').textContent()), 'prueba sin RPC en el servidor: lo dice, no finge');
    await ctx.close();
  }
  /* ── J. un solo seleccionable, y la ventana en móvil ── */
  {
    const { ctx, page, errores } = await nueva(browser, 390, 780, 'c=una', idi);
    await abreParcela(page, 'SH-1'); await esperaPanel(page);
    await page.locator('[data-accion="reclamar-pago"]').scrollIntoViewIfNeeded();
    await page.locator('[data-accion="reclamar-pago"]').click();
    await page.waitForSelector('#lw-editor [data-rp-cliente]');
    await page.locator('#lw-editor [data-rp-cliente]').first().check();
    await page.locator('#lw-editor [data-e="guardar"]').click();
    await page.waitForSelector('.lw-dlg-fondo');
    ok(/1 persona/.test(await page.locator('.lw-dlg-fondo').first().textContent()), 'una persona: singular en la confirmación');
    const desborda = await page.evaluate(() => document.documentElement.scrollWidth > innerWidth + 1);
    ok(!desborda, 'móvil 390: sin scroll horizontal de página');
    if (PNG) await page.screenshot({ path: PNG + '_movil.png' });
    ok(errores.length === 0, 'móvil: sin errores de consola');
    await ctx.close();
  }

  await browser.close();
  console.log(fallos.length ? '\n' + fallos.length + ' FALLOS' : '\nTODO EN VERDE');
  process.exit(fallos.length ? 1 : 0);
})().catch(e => { console.error('ARNÉS ROTO:', e); process.exit(1); });
