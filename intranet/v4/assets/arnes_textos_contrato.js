#!/usr/bin/env node
/* arnes_textos_contrato.js — ARNÉS VISUAL de la pantalla «Textos de contrato» (plantillas por empresa, S7, 8-oct-2026). A MANO: necesita Edge + playwright-core, así que no va en el gate.

   Qué hace: sirve la copia de Lawang desde disco bajo http://lawang.local, cambia el CDN de supabase-js por un cliente FALSO (sesión de una de las tres personas, `usuarios`, `empresas`,
   `plantillas_contrato` y las siete RPC de la pantalla con datos SINTÉTICOS salvo el cuerpo de las plantillas, que es el fichero público de contracts/templates) y recorre la pantalla a 1440 y a
   390 px. NO toca producción, NO llama a ninguna red, NO guarda nada. Lo que valida el SERVIDOR (qué se guarda, quién activa, qué bloques son fijos) se prueba por la RPC en
   supabase/pruebas/f2_plantillas_s7.sql; esto prueba que la pantalla pregunta bien, pinta lo que contesta la base (también cuando es hostil) y se puede usar en el móvil.

   Uso:  NODE_PATH=<carpeta con playwright-core> node arnes_textos_contrato.js --raiz <copia de Lawang> [--png <prefijo>]
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
const TC = require(path.join(RAIZ, 'intranet/v4/assets/textos-contrato-nucleo.js'));
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json', '.css': 'text/css', '.png': 'image/png', '.webp': 'image/webp', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.woff2': 'font/woff2', '.ttf': 'font/ttf' };

/* ── datos sintéticos ── */
const tpl = (f) => fs.readFileSync(path.join(RAIZ, 'contracts/templates', f + '.html'), 'utf8');
const sinNotas = (d) => d.replace(/<!--(?!if:|\/if:|opt:|\/opt:|seccion-|\/seccion-|extra-clauses|firmas-adquirientes|compradores-extra|datos-bancarios|hitos|extras-construccion|cuenta:|bloque-fijo:|\/bloque-fijo:)[\s\S]*?-->/g, '');
const SLUGS = fs.readdirSync(path.join(RAIZ, 'contracts/templates')).filter(f => f.endsWith('.html') && f[0] !== '_').map(f => f.replace(/\.html$/, ''));
const OFERTA = sinNotas(tpl('commercial_offer'));
const V2 = OFERTA.replace('acabados de alta calidad', 'acabados de calidad superior');
const V3 = V2.replace('piscina y paisajismo', 'piscina, jardín y paisajismo');
const fijos = (doc) => {                       // simula lo que devuelve la base: elementos que nombran el NPWP o el foro
  const out = [];
  for (const tg of ['p', 'li', 'td', 'th', 'h1', 'h2', 'h3', 'h4']) {
    const re = new RegExp('<' + tg + '(?: [^>]*)?>(?:(?!</' + tg + '>)[\\s\\S])*</' + tg + '>', 'g'); let m;
    while ((m = re.exec(doc)) !== null) if (/npwp|arbitra|escrow/i.test(m[0].replace(/<[^>]*>/g, ' '))) out.push('E|' + TC.ws(m[0]));
  }
  return out;
};
const lista = [];
SLUGS.forEach((s, i) => {
  lista.push({ id: 'sem-' + s, empresa: 'lawang', slug: s, version: 1, estado: 'borrador', origen: 'semilla', idioma_set: ['es', 'en', 'id'], hash: 'a'.repeat(63) + (i % 10), bytes: 1000, activable: false,
    bloqueo_motivo: 'Copia inicial del estudio: no se activa tal cual', autor: 'estudio', fecha: '2026-10-07T10:00:00Z', motivo: 'Copia inicial', activado_por: null, activado_en: null, confirmacion_nombre: null, retirada_por: null, retirada_en: null, hereda_de: null });
});
lista.push({ id: 'act-co', empresa: 'lawang', slug: 'commercial_offer', version: 2, estado: 'activa', origen: 'empresa', idioma_set: ['es'], hash: 'b'.repeat(64), bytes: 1200, activable: true, bloqueo_motivo: null,
  autor: 'admin.uno@prueba.test', fecha: '2026-10-08T08:00:00Z', motivo: 'Mejor redaccion del alcance', activado_por: 'super.uno@prueba.test', activado_en: '2026-10-08T09:00:00Z', confirmacion_nombre: 'Persona Uno de Prueba', retirada_por: null, retirada_en: null, hereda_de: 'sem-commercial_offer' });
lista.push({ id: 'bor-co', empresa: 'lawang', slug: 'commercial_offer', version: 3, estado: 'borrador', origen: 'empresa', idioma_set: ['es'], hash: 'c'.repeat(64), bytes: 1300, activable: true, bloqueo_motivo: null,
  autor: 'admin.uno@prueba.test', fecha: '2026-10-08T10:00:00Z', motivo: 'Anado el jardin', activado_por: null, activado_en: null, confirmacion_nombre: null, retirada_por: null, retirada_en: null, hereda_de: 'act-co' });
lista.push({ id: 'bor-ad', empresa: 'lawang', slug: 'adenda', version: 2, estado: 'borrador', origen: 'empresa', idioma_set: ['es'], hash: 'd'.repeat(64), bytes: 1300, activable: false, bloqueo_motivo: 'El texto nombra a otra sociedad (marca de otra)',
  autor: 'admin.uno@prueba.test', fecha: '2026-10-08T10:30:00Z', motivo: 'Prueba', activado_por: null, activado_en: null, confirmacion_nombre: null, retirada_por: null, retirada_en: null, hereda_de: 'sem-adenda' });
const CUERPOS = { 'sem-commercial_offer': OFERTA, 'act-co': V2, 'bor-co': V3, 'sem-adenda': sinNotas(tpl('adenda')), 'bor-ad': sinNotas(tpl('adenda')) };
const FIX = {
  usuarios: [{ user_id: 'u1', rol: 'admin_empresa', ambito: 'empresa', empresas: ['lawang'], herramientas: [], activo: true, nombre: 'Admin Uno', notif_visto_hasta: null, es_propietario: false }],
  empresas: [{ clave: 'lawang', nombre: 'Lawang', orden: 1, activa: true }, { clave: 'sandal_woods', nombre: 'Sandal Woods', orden: 2, activa: true }],
  plantillas_contrato: SLUGS.map((s, i) => ({ slug: s, nombre: 'Plantilla ' + s.replace(/_/g, ' '), orden: i + 1, archivada: false }))
};

/* El cliente FALSO. Persona y comportamientos por parámetros de la URL: ?p=ae|se|gl  ?lista=error|vacia  ?hostil=1 */
const STUB = `(function(){
  var FIX = ${JSON.stringify(FIX)}, LISTA = ${JSON.stringify(lista)}, CUERPOS = ${JSON.stringify(CUERPOS)}, FIJOS = ${JSON.stringify(fijos(OFERTA))};
  var q0 = new URLSearchParams(location.search), P = q0.get('p') || 'ae';
  if (P === 'se') { FIX.usuarios[0].rol = 'super_admin_empresa'; }
  if (P === 'gl') { FIX.usuarios[0].rol = 'super_admin'; FIX.usuarios[0].ambito = 'global'; FIX.usuarios[0].empresas = []; }
  window.__RPC = [];
  function q(tabla){
    var filas = (FIX[tabla] || []).slice(), unico = false;
    var b = new Proxy({}, { get: function(_, k){
      if (k === 'then') return function(ok, ko){ var d = unico ? (filas[0] || null) : filas; return Promise.resolve({ data: d, error: null, count: filas.length }).then(ok, ko); };
      if (k === 'eq') return function(c, v){ filas = filas.filter(function(f){ return f[c] === v; }); return b; };
      if (k === 'maybeSingle' || k === 'single') return function(){ unico = true; return b; };
      return function(){ return b; };
    }});
    return b;
  }
  function ok(d){ return Promise.resolve({ data: d, error: null }); }
  function mal(m, code){ return Promise.resolve({ data: null, error: { message: m, code: code || '42501' } }); }
  function rpc(n, a){
    window.__RPC.push({ n: n, a: a });
    if (n === 'plantilla_contrato_versiones_lista') {
      if (q0.get('lista') === 'error') return mal('permission denied para la lista');
      if (q0.get('lista') === 'vacia') return ok([]);
      return ok(LISTA.filter(function(v){ return v.empresa === a.p_empresa; }));
    }
    if (n === 'plantilla_contrato_edicion') {
      var solo = a.p_slug === 'estatutos_sw' && P !== 'gl' ? 'Estatutos de la comunidad: solo lo cambia el administrador global con su abogado' : null;
      var borr = LISTA.filter(function(v){ return v.slug === a.p_slug && v.estado === 'borrador' && v.origen === 'empresa'; })[0];
      var cuerpo = borr ? CUERPOS[borr.id] : CUERPOS['sem-commercial_offer'];
      return ok({ empresa: a.p_empresa, slug: a.p_slug, version_id: borr ? borr.id : 'sem-' + a.p_slug, version: borr ? borr.version : 1, estado: 'borrador', origen: borr ? 'empresa' : 'semilla', hash: 'x', cuerpo_html: cuerpo,
        notas_quitadas: borr ? 0 : 1645, solo_global: solo, nunca_activable: null, bloques_fijos: (P === 'gl' || solo) ? [] : FIJOS, puede_activar: P !== 'ae', bloqueo: null });
    }
    if (n === 'plantilla_contrato_cuerpo_version') return ok({ version_id: a.p_version, cuerpo_html: CUERPOS[a.p_version] || '' });
    if (n === 'plantilla_contrato_revisa') {
      if (/<script/i.test(a.p_cuerpo)) return ok({ ok: false, errores: ['etiqueta prohibida <script>'], activable: false });
      return ok({ ok: true, errores: [], activable: P !== 'ae' ? true : true, bloqueo: null });
    }
    if (n === 'plantilla_contrato_guarda_borrador') {
      if (q0.get('hostil')) return mal('El texto no pasa la validacion: <img src=x onerror="window.__PWNED=1"> | etiqueta prohibida', '22023');
      return ok('nuevo-borrador-id');
    }
    if (n === 'plantilla_contrato_activa') return ok({ version_id: a.p_version });
    if (n === 'plantilla_contrato_descarta_borrador') return ok(null);
    return q(n);
  }
  var sb = { from: q, rpc: rpc, supabaseUrl: 'https://sb.fake',
    storage: { from: function(){ return { getPublicUrl: function(p){ return { data: { publicUrl: 'https://sb.fake/' + p } }; } }; } },
    auth: { getSession: function(){ return Promise.resolve({ data: { session: { access_token: 'jwt-falso', user: { id: 'u1', email: 'admin.uno@prueba.test', app_metadata: {} } } } }); }, signOut: function(){ return Promise.resolve({}); }, onAuthStateChange: function(){ return { data: { subscription: { unsubscribe: function(){} } } }; } },
    channel: function(){ var c = { on: function(){ return c; }, subscribe: function(){ return c; } }; return c; }, removeChannel: function(){} };
  window.supabase = { createClient: function(){ return sb; } };
})();`;

const fallos = [];
const ok = (c, m) => { if (!c) fallos.push(m); return !!c; };
const espera = (page, ms) => page.waitForTimeout(ms);

async function nueva(browser, ancho, query) {
  const ctx = await browser.newContext({ viewport: { width: ancho, height: ancho > 800 ? 900 : 844 } });
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
  await page.goto(HOST + '/intranet/v4/textos-contrato/?' + (query || ''), { waitUntil: 'load' });
  await page.waitForFunction(() => document.querySelectorAll('#tc-lista tr').length > 0 && !/Trayendo/.test(document.getElementById('tc-lista').textContent), null, { timeout: 15000 }).catch(() => {});
  return { ctx, page, errores };
}
const rpcs = (page, n) => page.evaluate((n) => window.__RPC.filter(x => x.n === n), n);

(async () => {
  const browser = await chromium.launch({ executablePath: EDGE, headless: true });
  for (const ancho of [1440, 390]) {
    const t = ancho + 'px: ';
    /* ── A. admin de empresa: lista, editor, bloques con candado, simulación, guardado ── */
    {
      const { ctx, page, errores } = await nueva(browser, ancho, 'p=ae');
      ok(await page.locator('#tc-lista tr').count() === SLUGS.length, t + 'la lista tiene una fila por plantilla (' + SLUGS.length + ')');
      ok(await page.locator('#tc-empresa-caja').isHidden(), t + 'con una sola empresa no se ofrece el selector');
      ok(/no sustituye a un abogado indonesio colegiado/.test(await page.locator('.tc-aviso-fijo').textContent()), t + 'el aviso del abogado está visible');
      const filaCo = page.locator('#tc-lista tr', { has: page.locator('[data-tc-editar="commercial_offer"]') });
      ok(/v2/.test(await filaCo.textContent()) && /v3/.test(await filaCo.textContent()), t + 'commercial_offer enseña su versión activa v2 y su borrador v3');
      ok(/Persona Uno|super\.uno/.test(await filaCo.textContent()), t + 'la versión activa enseña quién la activó');
      const filaAd = page.locator('#tc-lista tr', { has: page.locator('[data-tc-editar="adenda"]') });
      ok(/otra sociedad/.test(await filaAd.textContent()), t + 'un borrador no activable dice por qué en la lista');
      if (PNG) await page.screenshot({ path: PNG + '_lista_' + ancho + '.png', fullPage: false });
      // abrir el editor
      await page.locator('[data-tc-editar="commercial_offer"]').click();
      await page.waitForSelector('#tc-trozos textarea', { timeout: 8000 });
      ok(await page.locator('#tc-editor').isVisible(), t + 'el editor se abre');
      const e1 = (await rpcs(page, 'plantilla_contrato_edicion'))[0];
      ok(e1 && e1.a.p_empresa === 'lawang' && e1.a.p_slug === 'commercial_offer', t + 'pide el texto con su empresa y su plantilla');
      const nRo = await page.locator('#tc-trozos textarea[readonly]').count(), nTotal = await page.locator('#tc-trozos textarea').count();
      ok(nRo > 0 && nRo < nTotal, t + 'hay trozos en solo lectura (' + nRo + ' de ' + nTotal + ' en esta página) y los demás se editan');
      ok(await page.locator('#tc-activar').isHidden(), t + 'el admin de empresa NO ve el panel de activar');
      ok(await page.locator('#tc-guardar').isDisabled() && await page.locator('#tc-simular').isDisabled(), t + 'sin cambios no se simula ni se guarda');
      // un trozo bloqueado no cambia aunque se intente
      const ro = page.locator('#tc-trozos textarea[readonly]').first();
      const antesRo = await ro.inputValue();
      await ro.evaluate(el => { el.value = 'intento'; el.dispatchEvent(new Event('input', { bubbles: true })); });
      ok(/0|Sin cambios/.test(await page.locator('#tc-cambios').textContent()) && !/1 trozo/.test(await page.locator('#tc-cambios').textContent()), t + 'un trozo con candado no cuenta como cambio');
      // editar uno libre
      const libre = page.locator('#tc-trozos textarea:not([readonly])', { hasText: 'acabados de calidad superior' }).first();
      await libre.fill('Construcción completa de la villa, incluyendo acabados de calidad superior & más, diseño de interiores, piscina y paisajismo.');
      ok(/1/.test(await page.locator('#tc-cambios').textContent()), t + 'el contador cuenta el cambio');
      ok(await page.locator('#tc-simular').isEnabled(), t + 'con un cambio ya se puede simular');
      ok(await page.locator('#tc-guardar').isEnabled(), t + 'y guardar');
      // un "<" avisa y bloquea guardar
      await libre.fill('texto con <b>etiqueta</b>');
      ok(/signo|«<»|&lt;|</.test(await page.locator('.tc-trozo-av').first().textContent().catch(() => '')) || await page.locator('.tc-trozo-av.tc-mal').count() > 0, t + 'escribir "<" avisa en rojo');
      ok(await page.locator('#tc-guardar').isDisabled(), t + 'con un aviso local no se puede guardar');
      await libre.fill('Construcción completa de la villa, incluyendo acabados de calidad superior & más, diseño de interiores, piscina y paisajismo.');
      // simular
      await page.locator('#tc-simular').click();
      await page.waitForSelector('#tc-revision .tc-rev', { timeout: 6000 });
      ok(/guardaría como borrador/.test(await page.locator('#tc-revision').textContent()), t + 'la simulación enseña lo que contesta la base');
      const rev = (await rpcs(page, 'plantilla_contrato_revisa'))[0];
      ok(rev && rev.a.p_empresa === 'lawang' && rev.a.p_cuerpo.indexOf('acabados de calidad superior &amp; más') !== -1, t + 'manda a revisar el texto nuevo con el & codificado como &amp;');
      const baseDoc = OFERTA;
      ok(rev && rev.a.p_cuerpo.length - baseDoc.length < 40 && rev.a.p_cuerpo.length > baseDoc.length - 40, t + 'el texto que se manda difiere del original solo en el trozo editado');
      const fr = page.locator('#tc-previa-frame');
      ok(await fr.getAttribute('sandbox') === '', t + 'el iframe de la simulación lleva sandbox vacío');
      const srcdoc = await fr.getAttribute('srcdoc');
      ok(/Content-Security-Policy/.test(srcdoc) && !/\{\{|<script/i.test(srcdoc), t + 'la simulación lleva la CSP, sin marcadores ni scripts');
      const accede = await page.evaluate(() => { try { return !!document.getElementById('tc-previa-frame').contentDocument; } catch (e) { return false; } });
      ok(accede === false, t + 'la página NO puede leer dentro del iframe (origen opaco)');
      // guardar
      await page.locator('#tc-guardar').click();
      ok(/motivo/i.test(await page.locator('#tc-ed-estado').textContent()), t + 'sin motivo no se guarda y lo dice');
      await page.locator('#tc-motivo').fill('Mejor redaccion del alcance');
      await page.locator('#tc-guardar').click();
      await page.waitForFunction(() => window.__RPC.some(x => x.n === 'plantilla_contrato_guarda_borrador'), null, { timeout: 5000 });
      const g = (await rpcs(page, 'plantilla_contrato_guarda_borrador'))[0];
      ok(g && g.a.p_empresa === 'lawang' && g.a.p_slug === 'commercial_offer' && g.a.p_motivo === 'Mejor redaccion del alcance' && Object.keys(g.a).sort().join() === 'p_cuerpo,p_empresa,p_motivo,p_slug', t + 'guarda por la RPC con empresa, plantilla, cuerpo y motivo (y nada más: ni versión, ni hash, ni importe)');
      if (PNG) await page.screenshot({ path: PNG + '_editor_' + ancho + '.png', fullPage: false });
      ok(errores.length === 0, t + 'sin errores de página: ' + errores.slice(0, 2).join(' || '));
      if (ancho === 390) {
        const desborda = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
        ok(desborda <= 1, t + 'la página no tiene scroll horizontal (' + desborda + ' px de más)');
        const chicos = await page.evaluate(() => [...document.querySelector('.lw-cabecera').parentElement.querySelectorAll('button:not([hidden]),input:not([type=hidden]):not([type=checkbox]),textarea,select')].filter(e => e.offsetParent && e.getBoundingClientRect().height < 34 && e.getBoundingClientRect().height > 0).map(e => e.id || e.className).slice(0, 5));
        ok(chicos.length === 0, t + 'ningún control táctil por debajo de 34 px de alto: ' + chicos.join(','));
      }
      await ctx.close();
    }
    /* ── B. super de empresa: activar con confirmación ── */
    {
      const { ctx, page, errores } = await nueva(browser, ancho, 'p=se');
      await page.locator('[data-tc-editar="commercial_offer"]').click();
      await page.waitForSelector('#tc-trozos textarea', { timeout: 8000 });
      ok(await page.locator('#tc-activar').isVisible() && await page.locator('#tc-act-form').isVisible(), t + 'el super ve el panel de activar sobre el borrador guardado');
      ok(await page.locator('#tc-act-texto').textContent() === TC.TEXTO_CONFIRMACION, t + 'la confirmación enseña la frase exacta que guarda la base');
      ok(/abogado indonesio colegiado/.test(await page.locator('#tc-act-texto').textContent()), t + 'y dice que no sustituye a un abogado indonesio colegiado');
      ok(await page.locator('#tc-act-boton').isDisabled(), t + 'activar nace deshabilitado');
      await page.locator('#tc-act-nombre').fill('Persona Dos de Prueba');
      ok(await page.locator('#tc-act-boton').isDisabled(), t + 'con el nombre solo no basta');
      await page.locator('#tc-act-ok').check();
      ok(await page.locator('#tc-act-boton').isEnabled(), t + 'nombre + casilla habilitan activar');
      await page.locator('#tc-act-boton').click();
      await page.waitForFunction(() => window.__RPC.some(x => x.n === 'plantilla_contrato_activa'), null, { timeout: 5000 });
      const a = (await rpcs(page, 'plantilla_contrato_activa'))[0];
      ok(a && a.a.p_version === 'bor-co' && a.a.p_nombre === 'Persona Dos de Prueba' && a.a.p_confirma === true && Object.keys(a.a).sort().join() === 'p_confirma,p_nombre,p_version', t + 'activa por la RPC con versión, nombre y confirmación (y nada más)');
      await page.waitForSelector('#tc-historial-caja:not([hidden])', { timeout: 6000 }).catch(() => {});
      // historial y diff
      await page.locator('#tc-historial-caja [data-tc-diff="act-co"]').click();
      await page.waitForSelector('#tc-diff .tc-d', { timeout: 6000 });
      const diff = await page.locator('#tc-diff').textContent();
      ok(/- .*alta calidad/.test(diff) && /\+ .*calidad superior/.test(diff), t + 'el diff v2 frente a v1 enseña lo quitado y lo añadido');
      ok(await page.locator('#tc-hist-cuerpo tr').count() === 3, t + 'el historial lista las tres versiones (semilla, activa, borrador)');
      ok(/Persona Uno de Prueba/.test(await page.locator('#tc-hist-cuerpo').textContent()) && /super\.uno/.test(await page.locator('#tc-hist-cuerpo').textContent()), t + 'el historial dice quién confirmó y quién activó');
      ok(/c{12}/.test(await page.locator('#tc-hist-cuerpo').textContent()), t + 'el historial enseña el hash');
      await page.locator('#tc-historial-caja [data-tc-diff="sem-commercial_offer"]').click();
      await page.waitForFunction(() => /primera versión/.test(document.getElementById('tc-diff').textContent), null, { timeout: 4000 });
      if (PNG) await page.screenshot({ path: PNG + '_activar_historial_' + ancho + '.png', fullPage: false });
      ok(errores.length === 0, t + 'B sin errores de página: ' + errores.slice(0, 2).join(' || '));
      await ctx.close();
    }
    /* ── C. global: las dos empresas, todo editable, solo-global ── */
    {
      const { ctx, page, errores } = await nueva(browser, ancho, 'p=gl');
      ok(await page.locator('#tc-empresa-caja').isVisible() && await page.locator('#tc-empresa option').count() === 2, t + 'el global elige entre las dos empresas');
      await page.locator('[data-tc-editar="commercial_offer"]').click();
      await page.waitForSelector('#tc-trozos textarea', { timeout: 8000 });
      ok(await page.locator('#tc-trozos textarea[readonly]').count() === 0, t + 'el global no ve bloques con candado');
      await page.selectOption('#tc-empresa', 'sandal_woods');
      await page.waitForFunction(() => window.__RPC.some(x => x.n === 'plantilla_contrato_versiones_lista' && x.a.p_empresa === 'sandal_woods'), null, { timeout: 5000 });
      ok(await page.locator('#tc-editor').isHidden(), t + 'al cambiar de empresa se cierra el editor (sin cambios que perder)');
      ok(errores.length === 0, t + 'C sin errores de página: ' + errores.slice(0, 2).join(' || '));
      await ctx.close();
    }
    /* ── D. un texto solo-global: todo en solo lectura para un admin de empresa ── */
    {
      const { ctx, page } = await nueva(browser, ancho, 'p=ae');
      await page.locator('[data-tc-editar="estatutos_sw"]').click();
      await page.waitForSelector('#tc-trozos textarea', { timeout: 8000 });
      ok(await page.locator('#tc-trozos textarea:not([readonly])').count() === 0, t + 'solo-global: ningún trozo editable');
      ok(await page.locator('#tc-guardar').isDisabled(), t + 'solo-global: no se puede guardar');
      ok(/administrador global/.test(await page.locator('#tc-ed-aviso').textContent()), t + 'solo-global: lo dice');
      await ctx.close();
    }
    /* ── E. la base contesta con algo hostil: se pinta como texto ── */
    {
      const { ctx, page } = await nueva(browser, ancho, 'p=ae&hostil=1');
      await page.locator('[data-tc-editar="commercial_offer"]').click();
      await page.waitForSelector('#tc-trozos textarea', { timeout: 8000 });
      await page.locator('#tc-trozos textarea:not([readonly])', { hasText: 'acabados de calidad superior' }).first().fill('Construcción con acabados de otra calidad, piscina y paisajismo.');
      await page.locator('#tc-motivo').fill('Prueba hostil');
      await page.locator('#tc-guardar').click();
      await page.waitForFunction(() => /no lo ha guardado/i.test(document.getElementById('tc-ed-estado').textContent), null, { timeout: 5000 });
      ok(await page.locator('#tc-ed-estado img').count() === 0, t + 'un mensaje hostil de la base no crea elementos (textContent)');
      ok(/onerror/.test(await page.locator('#tc-ed-estado').textContent()), t + 'y se ve tal cual, como texto');
      ok(await page.evaluate(() => window.__PWNED === undefined), t + 'no se ejecutó nada');
      await ctx.close();
    }
    /* ── F. «no he podido leer» y «no hay» se ven distinto ── */
    {
      const e = await nueva(browser, ancho, 'p=ae&lista=error');
      const txtE = await e.page.locator('#tc-lista').textContent();
      await e.ctx.close();
      const v = await nueva(browser, ancho, 'p=ae&lista=vacia');
      const txtV = await v.page.locator('#tc-lista').textContent();
      await v.ctx.close();
      ok(/No he podido leer las plantillas/.test(txtE) && /todavía no tiene textos/.test(txtV) && txtE !== txtV, t + 'un fallo de lectura y una lista vacía se leen distinto');
    }
  }
  await browser.close();
  if (fallos.length) { console.error('FALLA (' + fallos.length + '):\n - ' + fallos.join('\n - ')); process.exit(1); }
  console.log('arnes_textos_contrato OK: pantalla verificada a 1440 y 390 px con tres personas, bloques fijos, simulación, guardado, activación, historial y un mensaje hostil.');
})().catch(e => { console.error(e); process.exit(2); });
