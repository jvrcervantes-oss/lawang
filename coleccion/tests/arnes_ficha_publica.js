#!/usr/bin/env node
/* Arnés de NAVEGADOR de la pantalla «Ficha pública» (The Collection v2, F3b, 5-oct-2026).
   Molde: tools/arnes_deck_fotos.js de la agencia (Edge + playwright-core, sin sesión real). Va FUERA del gate
   (necesita Edge y playwright-core) y fuera de los *.test.js (no lo recoge tools/test.py).

   Qué mide, con el código servido de verdad desde disco bajo http://lawang.local:
     · la página REAL de /intranet/v4/proyectos/ con guard.js sustituido por un stub (cliente Supabase falso);
     · un servidor de mentira para `ficha_publica_lee` / `ficha_publica_guarda` que aplica la MISMA semántica que la
       migración 20261005120000 (mezcla por clave de primer nivel, null borra, p_version contra la fila → 40001):
       así se mide el efecto real de un parche sobre una ficha con `imagenes`, `downloads` y `diseno`, no solo su forma;
     · casos: botón en el pie (visible para admin, escondido para otro rol, 390 px y escritorio), cajón con dos fichas
       de un mismo proyecto y «lo que verá el público», editar UN campo (payload mínimo + p_version + lo no editado
       intacto en el servidor + segunda edición con la versión nueva), choque de versión (40001 en español),
       publicar con su propia confirmación (y que guardar nunca publica), alta (sondea antes; slug existente en otro
       proyecto se niega sin escribir), y un dato hostil de la base pintado como TEXTO.
   Datos SINTÉTICOS.

   Uso:  NODE_PATH=<carpeta con playwright-core> node coleccion/tests/arnes_ficha_publica.js [--raiz <copia de Lawang>] [--capturas <dir>]
   Sale con 1 si falla alguna aserción. Receta general: memoria reference_arnes_visual_intranet_v4_sin_sesion. */
const { chromium } = require('playwright-core');
const fs = require('fs');
const path = require('path');
const arg = (k, d) => { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : d; };
const RAIZ = path.resolve(arg('--raiz', path.join(__dirname, '..', '..')));
const OUT = arg('--capturas', null);
const EDGE = process.env.ARNES_EDGE || 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const SB = 'https://sb.fake';

const PID = '00000000-0000-4000-8000-0000000000a1';
const PROYECTO = { id: PID, nombre: 'PRB Riverfront', slug: 'prb-riverfront', resort: 'PRB', activo: true, estado: 'activo', parcela_master: null };
const IMAGENES = ['/assets/img/a.webp', '/assets/img/b.webp'];
const DOWNLOADS = [{ name: 'Brochure', url: '/dl/brochure.pdf', ext: 'pdf', size: '2 MB' }];
const DISENO = { logo: '/assets/l.svg', landColor: '#aabbcc', tabs: [{ title: { en: 'Tab', es: 'Pestaña' } }] };
const V1 = '2026-10-05T10:00:00.111111Z', V2 = '2026-10-05T10:00:00.222222Z';
const HOSTIL = '<img src=x onerror="window.__pwn=1">Villa Hostil';

const FICHAS = [
  { id: 'f-big', slug: 'prb-riverfront-big', linea: 'signature', region_key: 'bali', region: 'Ubud, Bali', publicada_web: false, en_coleccion: true,
    destacada: false, destacada_home: false, orden: 1, proyecto_id: PID, modelo_id: null, unidad_id: null,
    precio_modo: 'fijo', precio_eur: 450000, tenure: 'freehold', lease_years: null, estado_obra: 'offplan',
    textos: { title: { es: HOSTIL, en: 'Villa Big' }, desc: { es: 'Desc ES', en: 'Desc EN' } },
    ficha: { highlights: ['Piscina'], tech_specs: [{ l: 'Dormitorios', v: '4' }], equipamiento: { pool: true, poolType: 'infinity', garageDesc: 'dos coches' },
      view: 'arrozales', imagenes: IMAGENES.slice(), downloads: JSON.parse(JSON.stringify(DOWNLOADS)), diseno: JSON.parse(JSON.stringify(DISENO)) },
    version: V1, publico: null },
  { id: 'f-small', slug: 'prb-riverfront-small', linea: 'villa', region_key: 'bali', region: 'Ubud, Bali', publicada_web: true, en_coleccion: true,
    destacada: false, destacada_home: false, orden: 2, proyecto_id: PID, modelo_id: null, unidad_id: null,
    precio_modo: 'desde', precio_eur: null, tenure: 'leasehold', lease_years: 25, estado_obra: 'ready',
    textos: { title: { es: 'Villa Small', en: 'Villa Small' }, sub: { es: 'Sub es', en: 'Sub en' }, desc: { es: 'D es', en: 'D en' } },
    ficha: { highlights: ['Jardín', 'Vistas'], tech_specs: [{ l: 'Dormitorios', v: '2' }], equipamiento: { pool: false, poolType: 'plunge', furnished: 'sí', style: 'tropical' },
      view: 'río', imagenes: IMAGENES.slice(), downloads: JSON.parse(JSON.stringify(DOWNLOADS)), diseno: JSON.parse(JSON.stringify(DISENO)),
      payment_plan: [{ pct: 30, label: 'Reserva' }], masterplan_pins: [{ code: 'A1', x: 1, y: 2 }] },
    version: V1, publico: { id: 'prb-riverfront-small', priceEUR: 63875, priceMode: 'from', status: 'status.ready', images: ['a', 'b', 'c'], unitsAvailable: 6, unitsTotal: 10 } }
];
const FIX = { proyectos: [PROYECTO] };

// stub de guard.js + servidor de mentira (vive en la página: estado en window.__SRV)
const STUB = `(function(){
  var URL_SB = ${JSON.stringify(SB)};
  var FIX = ${JSON.stringify(FIX)};
  var SRV = window.__SRV = { fichas: ${JSON.stringify(FICHAS)}, calls: [], otros: { 'otro-proyecto': true }, conflicto: false };
  function q(tabla){
    var filas = (FIX[tabla] || []).slice(), unico = false;
    var b = new Proxy({}, { get: function(_, k){
      if (k === 'then') return function(ok, ko){ return Promise.resolve({ data: unico ? (filas[0] || null) : filas, error: null, count: filas.length }).then(ok, ko); };
      if (k === 'eq') return function(c, v){ filas = filas.filter(function(f){ return f[c] === v; }); return b; };
      if (k === 'maybeSingle' || k === 'single') return function(){ unico = true; return b; };
      return function(){ return b; };
    }});
    return b;
  }
  function err(code, message){ return { data: null, error: { code: code, message: message } }; }
  function mezcla(old, parche){   // mezcla de primer nivel; null borra (idéntica a la de la migración)
    var r = JSON.parse(JSON.stringify(old || {}));
    Object.keys(parche || {}).forEach(function(k){ if (parche[k] === null) delete r[k]; else r[k] = parche[k]; });
    return r;
  }
  function guarda(a){
    SRV.calls.push({ n: 'guarda', a: JSON.parse(JSON.stringify(a)) });
    var f = SRV.fichas.filter(function(x){ return x.slug === a.p_slug; })[0];
    if (!f) {
      if (a.p_version != null) return err('40001', 'Esa ficha ya no existe; recarga la pantalla');
      var nueva = { id: 'f-' + a.p_slug, slug: a.p_slug, linea: a.p_cambios.linea, region_key: a.p_cambios.region_key, region: null, publicada_web: false,
        en_coleccion: false, destacada: false, destacada_home: false, orden: 0, proyecto_id: a.p_cambios.proyecto_id, modelo_id: null, unidad_id: null,
        precio_modo: 'consultar', precio_eur: null, tenure: null, lease_years: null, estado_obra: null, textos: {}, ficha: {}, version: ${JSON.stringify(V2)}, publico: null };
      SRV.fichas.push(nueva);
      return { data: { id: nueva.id, slug: nueva.slug, version: nueva.version }, error: null };
    }
    if (a.p_version != null && f.version !== a.p_version) return err('40001', 'Otra persona cambió esta ficha; recárgala');
    if (SRV.conflicto) { SRV.conflicto = false; f.version = 'CAMBIADA-' + Date.now(); return err('40001', 'Otra persona cambió esta ficha; recárgala'); }
    var c = a.p_cambios;
    Object.keys(c).forEach(function(k){
      if (k === 'textos') {
        Object.keys(c.textos).forEach(function(t){
          var o = Object.assign({}, f.textos[t] || {});
          Object.keys(c.textos[t]).forEach(function(l){ if (c.textos[t][l] === null) delete o[l]; else o[l] = c.textos[t][l]; });
          if (Object.keys(o).length) f.textos[t] = o; else delete f.textos[t];
        });
      } else if (k === 'ficha') f.ficha = mezcla(f.ficha, c.ficha);
      else f[k] = c[k];
    });
    if (f.precio_modo !== 'fijo') f.precio_eur = null;
    f.version = ${JSON.stringify(V2)}.replace('222222', String(SRV.calls.length).padStart(6, '0'));
    if (f.publicada_web && !f.publico) f.publico = { id: f.slug, priceEUR: f.precio_eur, priceMode: 'fixed', status: f.estado_obra ? 'status.' + f.estado_obra : null, images: f.ficha.imagenes || [] };
    return { data: { id: f.id, slug: f.slug, version: f.version }, error: null };
  }
  function rpc(nombre, a){
    if (nombre === 'ficha_publica_lee') {
      SRV.calls.push({ n: 'lee', a: a });
      if (SRV.leeFalla) return Promise.resolve(err('XX000', 'Failed to fetch'));
      return Promise.resolve({ data: { proyecto: { id: a.p_proyecto_id, slug: 'prb-riverfront', nombre: 'PRB Riverfront' },
        fichas: JSON.parse(JSON.stringify(SRV.fichas.filter(function(f){ return f.proyecto_id === a.p_proyecto_id; }))),
        unidades: [{ id: 'u-1', codigo: 'A1' }, { id: 'u-2', codigo: 'A2' }], modelos: [{ id: 'm-1', nombre: 'Dune' }] }, error: null });
    }
    if (nombre === 'ficha_publica_guarda') {
      if (a.p_cambios && Object.keys(a.p_cambios).length === 0 && a.p_version === '1970-01-01T00:00:00.000000Z') {   // sonda de existencia
        SRV.calls.push({ n: 'sonda', a: a });
        var existe = SRV.fichas.some(function(x){ return x.slug === a.p_slug; }) || SRV.otros[a.p_slug];
        return Promise.resolve(existe ? err('40001', 'Otra persona cambió esta ficha; recárgala') : err('40001', 'Esa ficha ya no existe; recarga la pantalla'));
      }
      return Promise.resolve(guarda(a));
    }
    return q('__vacio_' + nombre);   // cualquier otra RPC de la pantalla: vacía y encadenable
  }
  var sb = { from: q, rpc: rpc,
    storage: { from: function(bk){ return { getPublicUrl: function(p){ return { data: { publicUrl: URL_SB + '/storage/v1/object/public/' + bk + '/' + p } }; } }; } },
    auth: { getSession: function(){ return Promise.resolve({ data: { session: { access_token: 'jwt-falso' } } }); } },
    channel: function(){ return { on: function(){ return this; }, subscribe: function(){ return this; } }; } };
  window.LW_SB = sb; window.LW_SB_URL = URL_SB;
  var rol = window.__ARNES_ROL || 'super_admin';
  window.LW_AUTH = Promise.resolve({ sb: sb, session: {}, ficha: { rol: rol, herramientas: ['proyectos'], activo: true, email: 'arnes@example.com' } });
  window.lwDatos = function(){ return Promise.resolve({ data: null, error: null }); };
})();`;

const MIME = { '.html': 'text/html', '.js': 'application/javascript', '.css': 'text/css', '.json': 'application/json', '.webp': 'image/webp', '.png': 'image/png', '.svg': 'image/svg+xml' };
async function rutas(ctx) {
  await ctx.route('**/*', async (route) => {
    const u = new URL(route.request().url());
    if (u.origin === SB) {
      const CORS = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': 'POST, GET, OPTIONS' };
      if (route.request().method() === 'OPTIONS') return route.fulfill({ status: 200, headers: CORS, body: 'ok' });
      return route.fulfill({ status: 404, headers: CORS, body: '' });
    }
    if (u.hostname === 'lawang.local') {
      if (u.pathname === '/contracts/assets/guard.js') return route.fulfill({ contentType: 'application/javascript', body: STUB });
      let f = path.join(RAIZ, decodeURIComponent(u.pathname));
      if (fs.existsSync(f) && fs.statSync(f).isDirectory()) f = path.join(f, 'index.html');
      if (fs.existsSync(f) && fs.statSync(f).isFile()) return route.fulfill({ contentType: MIME[path.extname(f)] || 'application/octet-stream', body: fs.readFileSync(f) });
      return route.fulfill({ status: 404, body: '' });
    }
    return route.fulfill({ status: 200, body: '' });   // supabase-js CDN, fuentes, iconos: fuera
  });
}

(async () => {
  const browser = await chromium.launch({ executablePath: EDGE, headless: true });
  const res = {}, errores = [];
  const nueva = async (w, h, rol) => {
    const ctx = await browser.newContext({ viewport: { width: w, height: h } });
    await rutas(ctx);
    const page = await ctx.newPage();
    if (rol) await page.addInitScript((r) => { window.__ARNES_ROL = r; }, rol);
    page.on('pageerror', (e) => { errores.push(String(e.message).slice(0, 200)); if (process.argv.includes('-d')) console.error('[pageerror]', e.message); });
    if (process.argv.includes('-d')) page.on('console', (m) => { if (m.type() === 'error' || m.type() === 'warning') console.error('[consola]', m.text().slice(0, 300)); });
    return { ctx, page };
  };
  const URL_PAG = 'http://lawang.local/intranet/v4/proyectos/?proyecto=' + encodeURIComponent(PROYECTO.nombre);
  const llamadas = (page, n) => page.evaluate((x) => window.__SRV.calls.filter((c) => c.n === x).map((c) => c.a), n);
  const abrePagina = async (page) => {
    await page.goto(URL_PAG);
    await page.waitForSelector('[data-accion="ficha-publica"]', { timeout: 10000 });
    await page.waitForTimeout(800);
  };
  const soloUna = (xs) => (xs.length === 1 ? xs[0] : null);

  // ── 1. Admin, escritorio: botón, cajón con dos fichas, texto hostil ──
  {
    const { ctx, page } = await nueva(1440, 900);
    await abrePagina(page);
    res.boton_admin = await page.evaluate(() => {
      const b = document.querySelector('[data-accion="ficha-publica"]'), r = b.getBoundingClientRect(), cs = getComputedStyle(b);
      const hermanos = [...b.parentElement.querySelectorAll('button')].map((x) => x.getBoundingClientRect());
      return { visible: r.width > 0 && r.height > 0 && cs.display !== 'none', texto: b.textContent.trim(), nBotones: hermanos.length, enNativo: b.getAttribute('data-e-nativo') };
    });
    if (OUT) await page.screenshot({ path: path.join(OUT, 'ficha_boton_escritorio.png') });
    await page.click('[data-accion="ficha-publica"]');
    await page.waitForSelector('#lw-cajon [data-fp="editar"]', { timeout: 6000 });
    res.cajon = await page.evaluate(() => {
      const c = document.getElementById('lw-cajon'), t = c.textContent;
      return { secciones: c.querySelectorAll('[data-fp="editar"]').length, dice_verà: /Lo que verá el público/.test(t), precio_desde: /Desde .*63\.875|Desde 63875|Desde .*€/.test(t) || /Desde/.test(t),
        unidades: /6 de 10 disponibles/.test(t), fotos3: /Fotos\s*3/.test(t.replace(/\s+/g, ' ')), no_servida: /No se sirve al público/.test(t),
        publicada_tag: /Publicada/.test(t), pwn: window.__pwn === 1, img_hostil: !!c.querySelector('img[src="x"]'), texto_hostil_visible: /<img src=x/.test(t),
        publica_big: c.querySelector('[data-fp="publica"][data-i="0"]').textContent.trim(), despublica_small: c.querySelector('[data-fp="publica"][data-i="1"]').textContent.trim(),
        enlace_property: !!c.querySelector('a[href="/property/prb-riverfront-small"]') };
    });
    if (OUT) await page.screenshot({ path: path.join(OUT, 'ficha_cajon_escritorio.png') });
    await ctx.close();
  }

  // ── 2. Editar UN campo, guardar: payload mínimo, p_version, nada borrado; segunda edición con la versión nueva ──
  {
    const { ctx, page } = await nueva(1440, 900);
    await abrePagina(page);
    await page.click('[data-accion="ficha-publica"]');
    await page.waitForSelector('#lw-cajon [data-fp="editar"]');
    await page.click('#lw-cajon [data-fp="editar"][data-i="1"]');   // la publicada (-small)
    await page.waitForSelector('#lw-editor [data-k="view"]');
    res.editor_campos = await page.evaluate(() => {
      const w = document.getElementById('lw-editor');
      return { view: w.querySelector('[data-k="view"]').value, aviso_publicada: /PUBLICADA/.test(w.textContent), modelo_todos: /Todos los modelos del proyecto/.test(w.textContent),
        fotos_o_downloads_en_form: /imagenes|downloads|diseno/i.test(w.textContent), highlights: w.querySelectorAll('[data-fp-fila]').length,
        precio_visible: !w.querySelector('[data-k="precio_eur"]').closest('.las-campo').classList.contains('las-oculto') };
    });
    await page.waitForTimeout(700);
    if (OUT) await page.screenshot({ path: path.join(OUT, 'ficha_editor_escritorio.png'), fullPage: false });
    await page.fill('#lw-editor [data-k="view"]', 'cascada');
    await page.click('#lw-editor [data-e="guardar"]');
    await page.waitForFunction(() => window.__SRV.calls.some((c) => c.n === 'guarda'), null, { timeout: 6000 }).catch(async (e) => { console.error('DEBUG editor:', await page.evaluate(() => { const w = document.getElementById('lw-editor'); return w ? [w.querySelector('[data-e="error"]').textContent, [...w.querySelectorAll('.las-mal .las-msg')].map((x) => x.textContent).join('|'), w.querySelector('[data-e="faltan"]') && w.querySelector('[data-e="faltan"]').textContent] : 'sin editor'; })); throw e; });
    await page.waitForFunction(() => !document.getElementById('lw-editor'), null, { timeout: 6000 }).catch(async (e) => { console.error('DEBUG cierre:', await page.evaluate(() => { const w = document.getElementById('lw-editor'); return w ? [w.querySelector('[data-e="error"]').textContent, w.querySelector('[data-e="guardar"]').className, w.querySelector('[data-e="form"]').style.transform] : 'sin editor'; })); throw e; });
    await page.waitForTimeout(500);
    const g1 = (await llamadas(page, 'guarda'))[0];
    res.edicion1 = { llamada: g1, servidor: await page.evaluate(() => { const f = window.__SRV.fichas.find((x) => x.slug === 'prb-riverfront-small'); return { view: f.ficha.view, imagenes: f.ficha.imagenes, downloads: f.ficha.downloads, diseno: f.ficha.diseno, payment_plan: f.ficha.payment_plan, equipamiento: f.ficha.equipamiento, highlights: f.ficha.highlights, textos: f.textos, version: f.version }; }) };
    // segunda edición: otro campo (título EN), debe llevar la versión NUEVA y no reenviar `view`
    await page.click('#lw-cajon [data-fp="editar"][data-i="1"]');
    await page.waitForSelector('#lw-editor [data-k="t_title_en"]');
    await page.fill('#lw-editor [data-k="t_title_en"]', 'Villa Small Deluxe');
    await page.click('#lw-editor [data-e="guardar"]');
    await page.waitForFunction(() => window.__SRV.calls.filter((c) => c.n === 'guarda').length >= 2, null, { timeout: 6000 });
    await page.waitForTimeout(700);
    res.edicion2 = { llamada: (await llamadas(page, 'guarda'))[1], versionTrasPrimera: res.edicion1.servidor.version };
    // sin cambios: no se llama a la base
    await page.waitForFunction(() => !document.getElementById('lw-editor'), null, { timeout: 6000 });
    await page.click('#lw-cajon [data-fp="editar"][data-i="1"]');
    await page.waitForSelector('#lw-editor [data-e="guardar"]');
    await page.click('#lw-editor [data-e="guardar"]');
    await page.waitForFunction(() => !document.getElementById('lw-editor'), null, { timeout: 6000 });
    res.sin_cambios_llamadas = (await llamadas(page, 'guarda')).length;
    if (OUT) await page.screenshot({ path: path.join(OUT, 'ficha_tras_guardar.png') });
    res.toast_global = await page.evaluate(() => [typeof toast, typeof toastMal]);
    // listas con filas: quitar un punto, añadir otro y una celda técnica → cada lista viaja ENTERA y nada más
    await page.click('#lw-cajon [data-fp="editar"][data-i="1"]');
    await page.waitForSelector('#lw-editor [data-fp-fila]');
    await page.evaluate(() => { const w = document.getElementById('lw-editor'); w.querySelector('[data-fp-fila] button').click(); });   // quita «Jardín»
    await page.evaluate(() => { [...document.querySelectorAll('#lw-editor button')].find((b) => /Añadir punto/.test(b.textContent)).click(); });
    await page.keyboard.type('Piscina privada');
    await page.evaluate(() => { [...document.querySelectorAll('#lw-editor button')].find((b) => /Añadir celda/.test(b.textContent)).click(); });
    await page.keyboard.type('Baños');
    await page.keyboard.press('Tab'); await page.keyboard.type('2');
    await page.keyboard.press('Enter');   // Enter dentro de una fila NO debe enviar el formulario
    await page.waitForTimeout(400);
    res.enter_no_envia = (await llamadas(page, 'guarda')).length === 2;
    await page.click('#lw-editor [data-e="guardar"]');
    await page.waitForFunction(() => window.__SRV.calls.filter((c) => c.n === 'guarda').length >= 3, null, { timeout: 6000 });
    res.edicion3 = (await llamadas(page, 'guarda'))[2];
    await ctx.close();
  }

  // ── 3. Choque de versión: el mensaje sale en español dentro del editor y nada se pisa ──
  {
    const { ctx, page } = await nueva(1440, 900);
    await abrePagina(page);
    await page.click('[data-accion="ficha-publica"]');
    await page.waitForSelector('#lw-cajon [data-fp="editar"]');
    await page.click('#lw-cajon [data-fp="editar"][data-i="1"]');
    await page.waitForSelector('#lw-editor [data-k="view"]');
    await page.evaluate(() => { window.__SRV.conflicto = true; });
    await page.fill('#lw-editor [data-k="view"]', 'otra');
    await page.click('#lw-editor [data-e="guardar"]');
    await page.waitForSelector('#lw-editor [data-e="error"]:not([style*="none"])', { timeout: 6000 });
    res.choque = await page.evaluate(() => ({ error: document.querySelector('#lw-editor [data-e="error"]').textContent, sigue_abierto: !!document.getElementById('lw-editor'),
      view_servidor: window.__SRV.fichas.find((x) => x.slug === 'prb-riverfront-small').ficha.view }));
    if (OUT) await page.screenshot({ path: path.join(OUT, 'ficha_choque.png') });
    await ctx.close();
  }

  // ── 4. Publicar: su propio clic, su confirmación con título/precio/slug; guardar nunca publica ──
  {
    const { ctx, page } = await nueva(1440, 900);
    await abrePagina(page);
    await page.click('[data-accion="ficha-publica"]');
    await page.waitForSelector('#lw-cajon [data-fp="publica"]');
    await page.click('#lw-cajon [data-fp="publica"][data-i="0"]');   // -big
    await page.waitForSelector('.lw-dlg-fondo.abierto');
    res.confirmacion = await page.evaluate(() => {
      const d = document.querySelector('.lw-dlg-fondo.abierto'), t = d.textContent;
      return { titulo: d.querySelector('h2').textContent, muestra_slug: /prb-riverfront-big/.test(t), muestra_precio: /450/.test(t), muestra_titulo: /Villa Big|Villa Hostil/.test(t),
        tono_peligro: !!d.querySelector('.btn.peligro'), pwn: window.__pwn === 1, llamadas_antes: window.__SRV.calls.filter((c) => c.n === 'guarda').length };
    });
    if (OUT) await page.screenshot({ path: path.join(OUT, 'ficha_confirma_publicar.png') });
    await page.click('.lw-dlg-fondo.abierto .btn:last-child');   // Cancelar
    await page.waitForTimeout(300);
    res.tras_cancelar = (await llamadas(page, 'guarda')).length;
    await page.click('#lw-cajon [data-fp="publica"][data-i="0"]');
    await page.waitForSelector('.lw-dlg-fondo.abierto');
    await page.click('.lw-dlg-fondo.abierto .btn.peligro');
    await page.waitForFunction(() => window.__SRV.calls.some((c) => c.n === 'guarda'), null, { timeout: 6000 });
    await page.waitForTimeout(500);
    res.publicar = { llamada: soloUna(await llamadas(page, 'guarda')), tag_publicada: await page.evaluate(() => document.querySelectorAll('#lw-cajon .lwc-tag').length && /Publicada/.test(document.getElementById('lw-cajon').textContent)) };
    // despublicar la otra: confirmación distinta
    await page.click('#lw-cajon [data-fp="publica"][data-i="1"]');
    await page.waitForSelector('.lw-dlg-fondo.abierto');
    res.despublicar_titulo = await page.evaluate(() => document.querySelector('.lw-dlg-fondo.abierto h2').textContent);
    await page.click('.lw-dlg-fondo.abierto .btn:last-child');
    await ctx.close();
  }

  // ── 5. Crear ficha: sonda antes de escribir; slug de otro proyecto se niega ──
  {
    const { ctx, page } = await nueva(1440, 900);
    await abrePagina(page);
    await page.click('[data-accion="ficha-publica"]');
    await page.waitForSelector('#lw-cajon [data-fp="editar"]');
    await page.click('#lw-cajon .las-pie button:first-child');   // Crear ficha
    await page.waitForSelector('#lw-editor [data-k="slug"]');
    res.alta_slug_propuesto = await page.evaluate(() => document.querySelector('#lw-editor [data-k="slug"]').value);
    // (a) slug que ya existe en OTRO proyecto
    await page.fill('#lw-editor [data-k="slug"]', 'otro-proyecto');
    await page.click('#lw-editor [data-e="guardar"]');
    await page.waitForSelector('#lw-editor [data-e="error"]:not([style*="none"])', { timeout: 6000 });
    res.alta_otro = { error: await page.evaluate(() => document.querySelector('#lw-editor [data-e="error"]').textContent),
      escrituras: (await llamadas(page, 'guarda')).length, sondas: (await llamadas(page, 'sonda')).length };
    // (b) slug que ya existe en ESTE proyecto: se niega sin ni siquiera sondear
    await page.fill('#lw-editor [data-k="slug"]', 'prb-riverfront-small');
    await page.click('#lw-editor [data-e="guardar"]');
    await page.waitForTimeout(400);
    res.alta_propio = { sondas: (await llamadas(page, 'sonda')).length, error: await page.evaluate(() => document.querySelector('#lw-editor [data-e="error"]').textContent) };
    // (c) slug libre → alta SIN p_version, con proyecto_id, y se abre el editor de la nueva
    await page.fill('#lw-editor [data-k="slug"]', 'PRB Riverfront Nueva');
    await page.click('#lw-editor [data-e="guardar"]');
    await page.waitForFunction(() => window.__SRV.calls.some((c) => c.n === 'guarda'), null, { timeout: 6000 });
    await page.waitForSelector('#lw-editor [data-k="t_title_es"]', { timeout: 8000 });
    res.alta = { llamada: soloUna(await llamadas(page, 'guarda')), editor_de: await page.evaluate(() => document.querySelector('#lw-editor h1').textContent) };
    await ctx.close();
  }

  // ── 6. Leer falla: se dice, no es «sin fichas» ──
  {
    const { ctx, page } = await nueva(1440, 900);
    await page.addInitScript(() => { window.__leeFalla = true; });
    await abrePagina(page);
    await page.evaluate(() => { window.__SRV.leeFalla = true; });
    await page.click('[data-accion="ficha-publica"]');
    await page.waitForSelector('#lw-cajon [data-fp="reintentar"]', { timeout: 6000 });
    res.lee_falla = await page.evaluate(() => { const t = document.getElementById('lw-cajon').textContent; return { dice_no_leido: /No se han podido leer/.test(t), dice_sin_fichas: /aún no tiene ficha pública/.test(t) }; });
    await ctx.close();
  }

  // ── 7. Otro rol: el botón no se ve (medido, no solo `hidden`) ──
  {
    const { ctx, page } = await nueva(1440, 900, 'sales_manager');
    await page.goto(URL_PAG);
    await page.waitForSelector('[data-accion="ficha-publica"]', { state: 'attached', timeout: 10000 });
    await page.waitForTimeout(1200);
    res.boton_no_admin = await page.evaluate(() => {
      const b = document.querySelector('[data-accion="ficha-publica"]'), r = b.getBoundingClientRect();
      return { display: getComputedStyle(b).display, ancho: r.width, alto: r.height, hidden: b.hidden };
    });
    await ctx.close();
  }

  // ── 8. Móvil 390 px: el pie con 6 botones no se sale ni se corta ──
  {
    const { ctx, page } = await nueva(390, 844);
    await abrePagina(page);
    res.movil = await page.evaluate(() => {
      const b = document.querySelector('[data-accion="ficha-publica"]'), cont = b.parentElement, rc = cont.getBoundingClientRect();
      const botones = [...cont.querySelectorAll('button')].filter((x) => x.getBoundingClientRect().width > 0 && getComputedStyle(x).display !== 'none');
      const r = b.getBoundingClientRect();
      return { viewport: innerWidth, scrollX_extra: document.documentElement.scrollWidth - innerWidth, boton: { x: Math.round(r.x), w: Math.round(r.width), h: Math.round(r.height), derecha: Math.round(r.right) },
        todos_dentro: botones.every((x) => { const q = x.getBoundingClientRect(); return q.left >= 0 && q.right <= innerWidth + 0.5; }), n: botones.length,
        sin_texto_cortado: botones.every((x) => x.scrollWidth <= x.clientWidth + 1), alto_boton_ok: r.height >= 30,
        columnas: new Set(botones.map((x) => Math.round(x.getBoundingClientRect().left))).size };
    });
    await page.evaluate(() => document.querySelector('[data-accion="ficha-publica"]').scrollIntoView({ block: 'center' }));
    if (OUT) await page.screenshot({ path: path.join(OUT, 'ficha_boton_390.png') });
    await page.click('[data-accion="ficha-publica"]');
    await page.waitForSelector('#lw-cajon [data-fp="editar"]');
    await page.waitForTimeout(700);   // que termine de deslizar
    res.movil_cajon = await page.evaluate(() => { const p = document.querySelector('#lw-cajon [data-c="panel"]').getBoundingClientRect(); return { ancho: Math.round(p.width), izq: Math.round(p.left), der: Math.round(p.right), cabe: p.right <= innerWidth + 1 && p.left >= -1, scroll_x: document.documentElement.scrollWidth - innerWidth }; });
    if (OUT) await page.screenshot({ path: path.join(OUT, 'ficha_cajon_390.png') });
    // referencia: el cajón de siempre (Investor Deck: min(560px,96vw)) mide igual → si el borde se come 4 px, no es de esta pantalla
    res.movil_cajon_referencia = await page.evaluate(() => new Promise((ok) => {
      window.lwCajon({ titulo: 'ref', ancho: 'min(560px,96vw)', cuerpo: 'x' });
      setTimeout(() => { const r = document.querySelector('#lw-cajon [data-c="panel"]').getBoundingClientRect(); window.lwCierraCajon(); ok({ izq: Math.round(r.left), der: Math.round(r.right) }); }, 700);
    }));
    await page.waitForTimeout(500);
    await page.click('[data-accion="ficha-publica"]');
    await page.waitForSelector('#lw-cajon [data-fp="editar"]');
    await page.click('#lw-cajon [data-fp="editar"][data-i="1"]');
    await page.waitForSelector('#lw-editor [data-k="view"]');
    await page.waitForTimeout(500);
    res.movil_editor = await page.evaluate(() => { const p = document.querySelector('#lw-editor [data-e="form"]').getBoundingClientRect(); return { ancho: Math.round(p.width), cabe: p.right <= innerWidth + 1 && p.left >= -1 }; });
    if (OUT) await page.screenshot({ path: path.join(OUT, 'ficha_editor_390.png') });
    await ctx.close();
  }

  await browser.close();
  res.errores_de_pagina = [...new Set(errores)];
  const e1 = res.edicion1.llamada, e2 = res.edicion2.llamada, s = res.edicion1.servidor;
  const c = [
    ['botón «Ficha pública» visible para admin y enganchado por data-accion', res.boton_admin.visible && res.boton_admin.enNativo === '1' && /Ficha pública/.test(res.boton_admin.texto) && res.boton_admin.nBotones >= 6],
    ['cajón: dos fichas del mismo proyecto, cada una con su estado y su publicación', res.cajon.secciones === 2 && res.cajon.publica_big === 'Publicar' && res.cajon.despublica_small === 'Despublicar' && res.cajon.publicada_tag],
    ['«lo que verá el público» sale de `publico` (precio desde, 6 de 10, 3 fotos) y la oculta dice que no se sirve', res.cajon.dice_verà && res.cajon.precio_desde && res.cajon.unidades && res.cajon.fotos3 && res.cajon.no_servida],
    ['enlace a /property/<slug> con el slug del servidor', res.cajon.enlace_property],
    ['un título hostil de la base se pinta como TEXTO (sin ejecutar, sin <img> real)', !res.cajon.pwn && !res.cajon.img_hostil && res.cajon.texto_hostil_visible],
    ['editor: avisa que la ficha está publicada, «todos los modelos», sin campos de fotos/descargas/diseño', res.editor_campos.aviso_publicada && res.editor_campos.modelo_todos && !res.editor_campos.fotos_o_downloads_en_form],
    ['editar UN campo: parche = solo {ficha:{view}} con p_version = la de lee', e1 && JSON.stringify(e1.p_cambios) === JSON.stringify({ ficha: { view: 'cascada' } }) && e1.p_version === V1 && e1.p_slug === 'prb-riverfront-small'],
    ['…y en el servidor NO se borró nada de lo no editado (imagenes, downloads, diseno, payment_plan, equipamiento, highlights, textos)',
      s.view === 'cascada' && JSON.stringify(s.imagenes) === JSON.stringify(IMAGENES) && JSON.stringify(s.downloads) === JSON.stringify(DOWNLOADS) && JSON.stringify(s.diseno) === JSON.stringify(DISENO)
      && s.payment_plan && s.payment_plan.length === 1 && s.equipamiento.poolType === 'plunge' && s.highlights.length === 2 && s.textos.title.en === 'Villa Small' && s.textos.sub.es === 'Sub es'],
    ['segunda edición: título EN, con la versión NUEVA (no la vieja) y sin reenviar `view`', e2 && JSON.stringify(e2.p_cambios) === JSON.stringify({ textos: { title: { en: 'Villa Small Deluxe' } } }) && e2.p_version === res.edicion2.versionTrasPrimera && e2.p_version !== V1],
    ['guardar sin cambios no llama a la base; toast/toastMal existen en la página', res.sin_cambios_llamadas === 2 && res.toast_global.join() === 'function,function'],
    ['listas: quitar/añadir filas manda highlights y tech_specs ENTEROS (y solo eso); Enter en una fila no envía el formulario', res.enter_no_envia && res.edicion3 && JSON.stringify(res.edicion3.p_cambios) === JSON.stringify({ ficha: { highlights: ['Vistas', 'Piscina privada'], tech_specs: [{ l: 'Dormitorios', v: '2' }, { l: 'Baños', v: '2' }] } })],
    ['choque de versión: mensaje en español, el editor sigue abierto y no se pisa el dato', /Otra persona cambió esta ficha/.test(res.choque.error) && res.choque.sigue_abierto && res.choque.view_servidor !== 'otra'],
    ['publicar: la confirmación muestra título, precio y slug en tono de peligro, y cancelar no llama', res.confirmacion.titulo === 'Publicar la ficha' && res.confirmacion.muestra_slug && res.confirmacion.muestra_precio && res.confirmacion.muestra_titulo && res.confirmacion.tono_peligro && !res.confirmacion.pwn && res.confirmacion.llamadas_antes === 0 && res.tras_cancelar === 0],
    ['confirmar publica con {publicada_web:true} + p_version, y nada más', res.publicar.llamada && JSON.stringify(res.publicar.llamada.p_cambios) === JSON.stringify({ publicada_web: true }) && res.publicar.llamada.p_version === V1],
    ['despublicar tiene su propia confirmación', res.despublicar_titulo === 'Despublicar la ficha'],
    ['alta: slug propuesto desde el del proyecto', res.alta_slug_propuesto === 'prb-riverfront'],
    ['alta con slug de OTRO proyecto: se niega tras sondear, sin escribir', /Ya existe una ficha con esa dirección/.test(res.alta_otro.error) && res.alta_otro.escrituras === 0 && res.alta_otro.sondas === 1],
    ['alta con slug de ESTE proyecto: se niega sin sondear', /ya tiene una ficha con esa dirección/.test(res.alta_propio.error) && res.alta_propio.sondas === 1],
    ['alta libre: sin p_version, con proyecto_id y línea/región, normalizando el slug; abre el editor de la nueva', res.alta.llamada && !('p_version' in res.alta.llamada) && res.alta.llamada.p_slug === 'prb-riverfront-nueva' && res.alta.llamada.p_cambios.proyecto_id === PID && /Editar ficha/.test(res.alta.editor_de)],
    ['si `lee` falla se dice «no se han podido leer», nunca «sin ficha»', res.lee_falla.dice_no_leido && !res.lee_falla.dice_sin_fichas],
    ['otro rol: el botón no ocupa sitio (display none, 0×0)', res.boton_no_admin.display === 'none' && res.boton_no_admin.ancho === 0 && res.boton_no_admin.alto === 0],
    ['390 px: los 6 botones del pie dentro de la pantalla, sin texto cortado ni scroll horizontal', res.movil.todos_dentro && res.movil.sin_texto_cortado && res.movil.scrollX_extra <= 0 && res.movil.n >= 6 && res.movil.alto_boton_ok],
    ['390 px: cajón y editor caben en pantalla (el cajón con la misma geometría que el de siempre)', res.movil_cajon.izq === res.movil_cajon_referencia.izq && res.movil_cajon.der === res.movil_cajon_referencia.der && res.movil_cajon.scroll_x <= 0 && res.movil_editor.cabe],
    ['sin errores de página', res.errores_de_pagina.length === 0]
  ];
  let mal = 0;
  c.forEach(([n, ok]) => { if (!ok) mal++; console.log((ok ? 'ok     ' : 'FALLA  ') + n); });
  if (mal || process.argv.includes('-v')) console.log(JSON.stringify(res, null, 1));
  console.log(mal ? `\n${mal} de ${c.length} FALLAN` : `\n${c.length}/${c.length} ok`);
  process.exit(mal ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
