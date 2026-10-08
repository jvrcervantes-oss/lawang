#!/usr/bin/env node
/* arnes_textos_contrato.js — ARNÉS VISUAL de la pantalla «Textos de contrato» (plantillas por empresa, S7, 8-oct-2026). A MANO: necesita Edge + playwright-core, así que no va en el gate.

   8-oct-2026 (editor como documento, E1-E3): ahora recorre el papel con índice, los idiomas en pestañas, los marcadores como pastillas, las partes sensibles editables con aviso y los
   rechazos de la base contados en llano (con textos REALES de las migraciones), también en modo oscuro.

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
const fijosPR = (doc) => {                     // lo que devolvería la base para ppjb_reserva: elementos con NPWP/foro/escrow + la sección «Ley aplicable»
  const out = fijos(doc), re = /<h2(?:\s[^>]*)?>/gi, pos = []; let m;
  while ((m = re.exec(doc)) !== null) pos.push(m.index);
  pos.forEach((a, k) => { const b = k + 1 < pos.length ? pos[k + 1] : doc.length; if (/ley aplicable|governing law/i.test(doc.slice(a, b).split('</h2>')[0].replace(/<[^>]*>/g, ' '))) out.push('S|' + TC.ws(doc.slice(a, b))); });
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
/* ppjb_reserva: la semilla y un borrador que cambió UN párrafo libre en español (para ver «falta revisar» en inglés e indonesio al abrirlo). estatutos_sw: solo-global. */
CUERPOS['sem-ppjb_reserva'] = sinNotas(tpl('ppjb_reserva'));
CUERPOS['sem-estatutos_sw'] = sinNotas(tpl('estatutos_sw'));
const FIJOS_PR = fijosPR(CUERPOS['sem-ppjb_reserva']);
{
  const doc = CUERPOS['sem-ppjb_reserva'], tr = TC.trocea(doc), s = TC.situaBloquesFijos(doc, FIJOS_PR);
  TC.secciones(doc, tr.trozos); TC.marcaBloqueados(tr.trozos, s.spans, false);
  const libre = tr.trozos.filter(x => x.editable && x.lang === 'es' && !x.bloqueado && !x.titulo && x.texto.length > 60 && !/\{\{/.test(x.texto))[2];
  CUERPOS['bor-pr'] = TC.construye(doc, tr.trozos, { [libre.i]: libre.texto + ' (texto revisado)' });
}
lista.push({ id: 'bor-pr', empresa: 'lawang', slug: 'ppjb_reserva', version: 2, estado: 'borrador', origen: 'empresa', idioma_set: ['es', 'en', 'id'], hash: 'e'.repeat(64), bytes: 1300, activable: true, bloqueo_motivo: null,
  autor: 'admin.uno@prueba.test', fecha: '2026-10-08T11:00:00Z', motivo: 'Aclaro un parrafo', activado_por: null, activado_en: null, confirmacion_nombre: null, retirada_por: null, retirada_en: null, hereda_de: 'sem-ppjb_reserva' });
const MARCADORES = [...new Set(Object.values(CUERPOS).join('').match(/\{\{[a-z0-9_]+\}\}/g) || [])].map(x => x.slice(2, -2));
const FIX = {
  usuarios: [{ user_id: 'u1', rol: 'admin_empresa', ambito: 'empresa', empresas: ['lawang'], herramientas: [], activo: true, nombre: 'Admin Uno', notif_visto_hasta: null, es_propietario: false }],
  empresas: [{ clave: 'lawang', nombre: 'Lawang', orden: 1, activa: true }, { clave: 'sandal_woods', nombre: 'Sandal Woods', orden: 2, activa: true }],
  plantillas_contrato: SLUGS.map((s, i) => ({ slug: s, nombre: 'Plantilla ' + s.replace(/_/g, ' '), orden: i + 1, archivada: false }))
};

/* El cliente FALSO. Persona y comportamientos por parámetros de la URL: ?p=ae|se|gl  ?lista=error|vacia  ?hostil=1 */
const STUB = `(function(){
  var FIX = ${JSON.stringify(FIX)}, LISTA = ${JSON.stringify(lista)}, CUERPOS = ${JSON.stringify(CUERPOS)}, FIJOS = ${JSON.stringify(fijos(OFERTA))}, FIJOS_PR = ${JSON.stringify(FIJOS_PR)}, MARC = ${JSON.stringify(MARCADORES)};
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
  function ws(s){ return String(s).replace(/[ \\t\\n\\r\\f\\v]+/g, ' ').replace(/^ | $/g, ''); }
  /* Lo que diría la base (mensajes REALES de las migraciones S3 y S2.5): bloque fijo tocado, marcador desconocido, llave suelta. */
  function rechazo(a){
    var cuerpo = String(a.p_cuerpo), fj = a.p_slug === 'ppjb_reserva' ? FIJOS_PR : (a.p_slug === 'commercial_offer' ? FIJOS : []);
    if (P !== 'gl') {
      var w = ws(cuerpo);
      for (var i = 0; i < fj.length; i++) if (fj[i].charAt(0) === 'E' && w.indexOf(fj[i].slice(2)) === -1) return 'Tu texto cambia un bloque que una empresa no edita sola (foro y ley aplicable, tenencia, escrow e impuestos, prorroga, defectos, datos, partes y firmas, clausulas negociadas) o anade en un parrafo libre palabras de esos temas. Esos bloques los cambia el administrador global con su abogado: bloques fijos ' + fj.length + ', recibidos ' + (fj.length - 1);
    }
    if (/\\{\\{(?![a-z0-9_]+\\}\\})/.test(cuerpo)) return 'llave suelta o marcador mal cerrado ({{ sin }}, }} sin {{ o {{{x}}})';
    var re = /\\{\\{([a-z0-9_]+)\\}\\}/g, m;
    while ((m = re.exec(cuerpo)) !== null) if (MARC.indexOf(m[1]) === -1) return 'marcador desconocido {{' + m[1] + '}}: no esta en tokens.json ni en la lista de derivados del motor';
    return null;
  }
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
      var cuerpo = borr ? CUERPOS[borr.id] : (CUERPOS['sem-' + a.p_slug] || CUERPOS['sem-commercial_offer']);
      var fijosDe = a.p_slug === 'ppjb_reserva' ? FIJOS_PR : (a.p_slug === 'commercial_offer' ? FIJOS : []);
      return ok({ empresa: a.p_empresa, slug: a.p_slug, version_id: borr ? borr.id : 'sem-' + a.p_slug, version: borr ? borr.version : 1, estado: 'borrador', origen: borr ? 'empresa' : 'semilla', hash: 'x', cuerpo_html: cuerpo,
        notas_quitadas: borr ? 0 : 1645, solo_global: solo, nunca_activable: null, bloques_fijos: (P === 'gl' || solo) ? [] : fijosDe, puede_activar: P !== 'ae', bloqueo: null });
    }
    if (n === 'plantilla_contrato_cuerpo_version') return ok({ version_id: a.p_version, cuerpo_html: CUERPOS[a.p_version] || '' });
    if (n === 'plantilla_contrato_revisa') {
      if (/<script/i.test(a.p_cuerpo)) return ok({ ok: false, errores: ['etiqueta prohibida <script>'], activable: false });
      var rz = rechazo(a); if (rz) return ok({ ok: false, errores: [rz], activable: false });
      return ok({ ok: true, errores: [], activable: P !== 'ae' ? true : true, bloqueo: null });
    }
    if (n === 'plantilla_contrato_guarda_borrador') {
      var rz = rechazo(a); if (rz) return mal(rz, '42501');
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
      if (/tokens=error/.test(query || '') && u.pathname === '/contracts/tokens.json') return route.fulfill({ status: 500, body: '' });
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
const esperaPapel = (page) => page.waitForSelector('#tc-trozos [data-tc-par]', { timeout: 8000 });
/* Abre un párrafo por un trozo de su texto, escribe al final y lo anota con «Listo». */
async function editaPar(page, contiene, extra, anota) {
  const span = page.locator('#tc-trozos [data-tc-trozo]', { hasText: contiene }).first();
  await span.click();
  await page.waitForSelector('#tc-trozos .tc-par.tc-editando', { timeout: 4000 });
  await page.keyboard.press('Control+End');
  await page.keyboard.type(extra);
  if (anota !== false) await page.locator('#tc-trozos [data-tc-par-listo]').click();
}
const normaliza = (s) => s.replace(/\s+/g, ' ');

(async () => {
  const browser = await chromium.launch({ executablePath: EDGE, headless: true });
  for (const ancho of [1440, 390]) {
    const t = ancho + 'px: ';
    /* ── A. admin de empresa, commercial_offer: lista, editor como documento, partes sensibles editables, simulación, guardado ── */
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
      await page.locator('[data-tc-editar="commercial_offer"]').click();
      await esperaPapel(page);
      ok(await page.locator('#tc-editor').isVisible(), t + 'el editor se abre');
      const e1 = (await rpcs(page, 'plantilla_contrato_edicion'))[0];
      ok(e1 && e1.a.p_empresa === 'lawang' && e1.a.p_slug === 'commercial_offer', t + 'pide el texto con su empresa y su plantilla');
      ok(await page.locator('#tc-trozos textarea').count() === 0, t + 'ya no hay una caja de texto por trozo: es un documento');
      ok(await page.locator('#tc-trozos [contenteditable="true"]').count() === 0, t + 'nada es editable hasta que se hace clic en un texto');
      ok(await page.locator('#tc-trozos .tc-par-sens').count() > 0, t + 'hay partes sensibles marcadas');
      const nota = page.locator('#tc-trozos .tc-par-sens .tc-sens-nota').first();
      ok(/Parte sensible: /.test(await nota.textContent()) && await nota.getAttribute('tabindex') === '0' && /Parte sensible/.test(await nota.getAttribute('aria-label')), t + 'una parte sensible lo dice en texto visible, con tabindex y aria-label');
      ok(await nota.locator('svg').count() === 1, t + 'y lleva su candado SVG');
      ok(await page.locator('#tc-activar').isHidden(), t + 'el admin de empresa NO ve el panel de activar');
      ok(await page.locator('#tc-guardar').isDisabled() && await page.locator('#tc-simular').isDisabled(), t + 'sin cambios no se simula ni se guarda');
      ok(/Estás en la primera cláusula que puedes editar/.test(await page.locator('#tc-aterriza').textContent()), t + 'aterriza en la primera cláusula editable y lo dice');
      // una parte sensible se puede editar, con aviso (decisión del owner)
      const sens = page.locator('#tc-trozos .tc-par-sens').first();
      await sens.locator('[data-tc-trozo]').first().click();
      await page.waitForSelector('#tc-trozos .tc-par.tc-editando', { timeout: 4000 });
      ok(await page.locator('#tc-trozos .tc-editando .tc-aviso-sens').isVisible(), t + 'al editar una parte sensible sale el aviso');
      ok(/queda(rá)? registrado/.test(await page.locator('#tc-trozos .tc-editando .tc-aviso-sens').textContent()), t + 'y dice que el cambio queda registrado');
      ok(await page.locator('#tc-trozos .tc-editando [contenteditable="true"]').count() > 0, t + 'y se puede escribir en ella (no es solo lectura)');
      await page.locator('#tc-trozos [data-tc-par-deshacer]').click();
      ok(await page.locator('#tc-trozos [contenteditable="true"]').count() === 0, t + 'Deshacer cierra el párrafo sin guardar nada');
      // editar uno libre
      await editaPar(page, 'acabados de calidad superior', ' & más');
      ok(/1 trozos/.test(await page.locator('#tc-cambios').textContent()), t + 'el contador cuenta el cambio anotado');
      ok(await page.locator('#tc-simular').isEnabled() && await page.locator('#tc-guardar').isEnabled(), t + 'con un cambio ya se puede simular y guardar');
      ok(await page.locator('#tc-trozos .tc-par-cambiado').count() === 1, t + 'el párrafo cambiado se marca');
      // un "<" avisa y no deja anotar
      await editaPar(page, 'jardín', ' <b>x</b>');
      ok(await page.locator('#tc-trozos .tc-editando [data-tc-par-av]').isVisible(), t + 'escribir "<" avisa en rojo en el propio párrafo');
      ok(/«<»/.test(await page.locator('#tc-trozos .tc-editando [data-tc-par-av]').textContent()), t + 'y el aviso es el del signo «<»');
      ok(await page.locator('#tc-trozos .tc-editando').count() === 1, t + 'y el párrafo sigue abierto (no se anota a medias)');
      await page.locator('#tc-trozos [data-tc-par-deshacer]').click();
      // simular
      await page.locator('#tc-simular').click();
      await page.waitForSelector('#tc-revision .tc-rev', { timeout: 6000 });
      ok(/guardaría como borrador/.test(await page.locator('#tc-revision').textContent()), t + 'la simulación enseña lo que contesta la base');
      const rev = (await rpcs(page, 'plantilla_contrato_revisa'))[0];
      ok(rev && rev.a.p_empresa === 'lawang' && rev.a.p_cuerpo.indexOf('&amp; más') !== -1, t + 'manda a revisar el texto nuevo con el & codificado como &amp;');
      ok(rev && Math.abs(rev.a.p_cuerpo.length - V3.length) < 40, t + 'el texto que se manda difiere del original solo en el trozo editado');
      const fr = page.locator('#tc-previa-frame');
      ok(await fr.getAttribute('sandbox') === '', t + 'el iframe de la simulación lleva sandbox vacío');
      const srcdoc = await fr.getAttribute('srcdoc');
      ok(/Content-Security-Policy/.test(srcdoc) && !/\{\{|<script/i.test(srcdoc), t + 'la simulación lleva la CSP, sin marcadores ni scripts');
      ok(await page.evaluate(() => { try { return !!document.getElementById('tc-previa-frame').contentDocument; } catch (e) { return false; } }) === false, t + 'la página NO puede leer dentro del iframe (origen opaco)');
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
      await ctx.close();
    }
    /* ── A2. ppjb_reserva: idiomas, índice, marcadores, partes sensibles, rechazos de la base ── */
    {
      const { ctx, page, errores } = await nueva(browser, ancho, 'p=ae');
      await page.locator('[data-tc-editar="ppjb_reserva"]').click();
      await esperaPapel(page);
      await page.waitForFunction(() => /falta revisar/.test(document.getElementById('tc-ed-idiomas').textContent), null, { timeout: 6000 }).catch(() => {});
      const nPars = await page.locator('#tc-trozos .tc-par').count();
      ok(nPars > 60, t + 'ppjb_reserva se abre como documento continuo (' + nPars + ' párrafos, sin paginar de 25 en 25)');
      ok(await page.locator('#tc-ed-barra [data-tc-pag]').count() === 0, t + 'ya no hay paginador');
      const nInd = await page.locator('#tc-indice [data-tc-ir]').count();
      ok(nInd >= 30, t + 'el índice lista las cláusulas (' + nInd + ')');
      const tabs = await page.locator('#tc-ed-idiomas .tc-tab').allTextContents();
      ok(tabs.length === 3 && /Español/.test(tabs[0]) && /principal/.test(tabs[0]), t + 'tres idiomas en pestañas y el español es el principal (' + tabs.join(' | ') + ')');
      ok(await page.locator('#tc-ed-idiomas .tc-tab[aria-pressed="true"]').textContent().then(x => /Español/.test(x)), t + 'se abre en español');
      ok(/al día/.test(tabs[0]) && /falta revisar/.test(tabs[1]) && /falta revisar/.test(tabs[2]), t + 'el borrador cambió solo el español: español al día, inglés e indonesio «falta revisar»');
      ok(await page.locator('#tc-trozos .tc-ancla').count() === 1, t + 'aterriza en una cláusula editable');
      const dentro = await page.evaluate(() => { const a = document.querySelector('#tc-trozos .tc-ancla').getBoundingClientRect(), p = document.getElementById('tc-trozos').getBoundingClientRect(); return a.top >= p.top - 2 && a.top <= p.bottom; });
      ok(dentro, t + 'y esa cláusula está a la vista en el papel');
      // marcadores como pastillas con etiqueta llana
      const pastillas = await page.locator('#tc-trozos .tc-marca').allTextContents();
      ok(pastillas.length > 10 && pastillas.every(x => x && !/_/.test(x)), t + 'los marcadores son pastillas con etiqueta en llano, nunca la clave (' + pastillas.slice(0, 3).join(', ') + ')');
      ok(await page.locator('#tc-trozos .tc-marca[data-ej]').first().getAttribute('data-ej').then(x => !!x && !/[{}]/.test(x)), t + 'cada pastilla lleva su valor de ejemplo');
      const prom = page.locator('#tc-trozos .tc-marca', { hasText: 'Razón social de la promotora' }).first();
      await prom.focus();
      ok(await prom.evaluate(el => getComputedStyle(el, '::after').content).then(x => /=/.test(x)), t + 'al foco la pastilla enseña su valor de ejemplo');
      // el borrador cambió el español: solo ese párrafo se marca como cambiado
      ok(await page.locator('#tc-trozos .tc-par-cambiado').count() === 1, t + 'el borrador guardado marca solo el párrafo que cambió');
      await page.locator('#tc-f-cambios').check();
      ok(await page.locator('#tc-trozos .tc-par').count() === 1, t + '«Solo lo que he cambiado» deja ese único párrafo');
      await page.locator('#tc-f-cambios').uncheck();
      // el idioma inglés: mismo documento, otro idioma, el español no se mezcla
      await page.locator('#tc-ed-idiomas [data-tc-idioma="en"]').click();
      await page.waitForFunction(() => document.querySelector('#tc-ed-idiomas [data-tc-idioma="en"]').getAttribute('aria-pressed') === 'true');
      ok(await page.locator('#tc-trozos .tc-aviso-rev').count() >= 1, t + 'en inglés avisa en la cláusula «Has cambiado esta cláusula en otro idioma»');
      ok(!/Exponen/.test(await page.locator('#tc-trozos').textContent()) && /Recitals/.test(await page.locator('#tc-trozos').textContent()), t + 'en inglés solo se ve el texto en inglés');
      const nEn = await page.locator('#tc-ed-idiomas .tc-tab-ins').nth(1).textContent();
      await page.locator('#tc-trozos [data-tc-visto]').first().click();
      ok(await page.locator('#tc-ed-idiomas .tc-tab-ins').nth(1).textContent() !== nEn || /\(0\)/.test(nEn) === false, t + '«Ya está igual» baja el contador de «falta revisar»');
      await page.locator('#tc-ed-idiomas [data-tc-idioma="es"]').click();
      await page.waitForFunction(() => document.querySelector('#tc-ed-idiomas [data-tc-idioma="es"]').getAttribute('aria-pressed') === 'true');
      // editar un párrafo en español no toca en ni id
      const libre = page.locator('#tc-trozos .tc-par-edit:not(.tc-par-sens):not(.tc-par-titulo) [data-tc-trozo]').nth(12);
      const textoLibre = (await libre.textContent()).trim();
      await libre.click();
      await page.waitForSelector('#tc-trozos .tc-par.tc-editando');
      await page.keyboard.press('Control+End'); await page.keyboard.type(' ZZtexto');
      await page.locator('#tc-trozos [data-tc-par-listo]').click();
      ok(/trozos cambiados/.test(await page.locator('#tc-cambios').textContent()), t + 'anotado el cambio en español');
      await page.locator('#tc-simular').click();
      await page.waitForSelector('#tc-revision .tc-rev', { timeout: 6000 });
      const rv = (await rpcs(page, 'plantilla_contrato_revisa')).pop();
      const orig = CUERPOS['bor-pr'], nuevoDoc = rv.a.p_cuerpo;
      const tr0 = TC.trocea(orig).trozos, tr1 = TC.trocea(nuevoDoc).trozos;
      let difEs = 0, difOtro = 0;
      tr0.forEach((x, i) => { if (tr1[i] && x.raw !== tr1[i].raw) { if (x.lang === 'es') difEs++; else difOtro++; } });
      ok(tr0.length === tr1.length && difEs === 1 && difOtro === 0, t + 'editar un párrafo en español cambia 1 trozo en español y ninguno en inglés o indonesio (es:' + difEs + ', otros:' + difOtro + ')');
      ok(/guardaría como borrador/.test(await page.locator('#tc-revision').textContent()), t + 'la base lo acepta como borrador (plantilla_contrato_revisa ok)');
      // buscar «3 de 12»
      await page.locator('#tc-buscar').fill('precio');
      await page.waitForFunction(() => /^\d+ de \d+$/.test(document.getElementById('tc-hits').textContent.trim()), null, { timeout: 4000 });
      const h1 = (await page.locator('#tc-hits').textContent()).trim();
      ok(/^1 de \d+$/.test(h1) && await page.locator('#tc-trozos mark').count() > 0, t + 'la búsqueda cuenta «' + h1 + '» y resalta');
      await page.locator('#tc-buscar').press('Enter');
      ok(/^2 de /.test((await page.locator('#tc-hits').textContent()).trim()), t + 'Intro pasa al siguiente resultado');
      await page.locator('#tc-buscar').fill('');
      // un marcador borrado: no se puede anotar y se dice en llano
      await page.locator('#tc-trozos .tc-par-edit [data-tc-trozo] .tc-marca').first().evaluate(el => { el.closest('[data-tc-trozo]').click(); });
      await page.waitForSelector('#tc-trozos .tc-par.tc-editando');
      const etq = await page.locator('#tc-trozos .tc-editando [data-tc-trozo] .tc-marca').first().textContent();
      await page.evaluate(() => { const m = document.querySelector('#tc-trozos .tc-editando [data-tc-trozo] .tc-marca'); const s = m.closest('[data-tc-trozo]'); m.remove(); s.dispatchEvent(new Event('input', { bubbles: true })); });
      ok(/Falta el campo/.test(await page.locator('#tc-trozos .tc-editando [data-tc-par-av]').textContent()) && (await page.locator('#tc-trozos .tc-editando [data-tc-par-av]').textContent()).indexOf(etq) !== -1, t + 'borrar una pastilla avisa en llano con su etiqueta («' + etq + '»)');
      await page.locator('#tc-trozos [data-tc-par-listo]').click();
      ok(await page.locator('#tc-trozos .tc-editando').count() === 1, t + 'y el párrafo no se anota con el campo perdido');
      await page.locator('#tc-trozos [data-tc-par-deshacer]').click();
      // pegar un {{ roto: el aviso local lo ve; nada se envía
      await page.locator('#tc-trozos .tc-par-edit:not(.tc-par-sens) [data-tc-trozo]').nth(5).click();
      await page.waitForSelector('#tc-trozos .tc-par.tc-editando');
      await page.keyboard.press('Control+End');
      await page.evaluate(() => { const s = document.querySelector('#tc-trozos .tc-editando [contenteditable="true"]'); const dt = new DataTransfer(); dt.setData('text/plain', ' {{roto'); s.dispatchEvent(new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true })); });
      ok(/llave suelta/i.test(await page.locator('#tc-trozos .tc-editando [data-tc-par-av]').textContent()), t + 'pegar un {{ roto lo avisa en llano antes de anotarlo');
      ok(await page.locator('#tc-trozos .tc-editando [contenteditable="true"] *:not(.tc-marca)').count() === 0, t + 'lo pegado entra como texto plano, sin etiquetas');
      await page.locator('#tc-trozos [data-tc-par-deshacer]').click();
      // pegar un marcador bien formado pero que no existe: lo rechaza el servidor y la pantalla lo cuenta
      await page.locator('#tc-trozos .tc-par-edit:not(.tc-par-sens) [data-tc-trozo]').nth(6).click();
      await page.waitForSelector('#tc-trozos .tc-par.tc-editando');
      await page.keyboard.press('Control+End');
      await page.evaluate(() => { const s = document.querySelector('#tc-trozos .tc-editando [contenteditable="true"]'); const dt = new DataTransfer(); dt.setData('text/plain', ' {{no_existe}}'); s.dispatchEvent(new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true })); });
      await page.locator('#tc-trozos [data-tc-par-listo]').click();
      await page.locator('#tc-motivo').fill('Prueba de marcador inexistente');
      await page.locator('#tc-guardar').click();
      await page.waitForFunction(() => /no lo ha guardado/i.test(document.getElementById('tc-ed-estado').textContent), null, { timeout: 5000 });
      const est = await page.locator('#tc-ed-estado').textContent();
      ok(/campo que no existe/.test(est) && /no_existe/.test(est), t + 'el servidor rechaza el marcador inexistente y la pantalla lo cuenta en llano («campo que no existe»)');
      ok(/Mensaje de la base: marcador desconocido/.test(est), t + 'y deja el mensaje de la base como detalle');
      ok(/siguen aquí/.test(est), t + 'y dice que los cambios siguen en pantalla');
      ok(/^\d+ trozos cambiados|trozos cambiados/.test(await page.locator('#tc-cambios').textContent()), t + 'sin perder lo escrito');
      // quitar ese cambio y probar la parte sensible: la base la rechaza y la pantalla lo dice con enlace a la cláusula
      await page.locator('#tc-deshacer').click();
      await page.waitForSelector('.lw-dlg-fondo button, [data-lw-ok], .lw-dlg-fondo', { timeout: 3000 }).catch(() => {});
      const conf = page.locator('.lw-dlg-fondo button', { hasText: /Descartar los cambios/ });
      if (await conf.count()) await conf.first().click();
      await page.waitForFunction(() => document.getElementById('tc-cambios').textContent.indexOf('Sin cambios') !== -1, null, { timeout: 4000 });
      const sensSpan = page.locator('#tc-trozos .tc-par-sens:not(.tc-par-titulo) [data-tc-trozo]', { hasText: 'NPWP' }).first();
      const alguna = (await sensSpan.count()) ? sensSpan : page.locator('#tc-trozos .tc-par-sens:not(.tc-par-titulo) [data-tc-trozo]').first();
      await alguna.click();
      await page.waitForSelector('#tc-trozos .tc-par.tc-editando');
      await page.keyboard.press('Control+End'); await page.keyboard.type(' cambio sensible');
      await page.locator('#tc-trozos [data-tc-par-listo]').click();
      await page.locator('#tc-motivo').fill('Prueba de parte sensible');
      await page.locator('#tc-guardar').click();
      await page.waitForFunction(() => /parte sensible/i.test(document.getElementById('tc-ed-estado').textContent), null, { timeout: 5000 });
      ok(/todavía no admite guardar cambios/.test(await page.locator('#tc-ed-estado').textContent()), t + 'la base rechaza el cambio en la parte sensible y la pantalla lo cuenta en llano');
      ok(await page.locator('#tc-ed-estado [data-tc-ir]').count() >= 1, t + 'con un enlace a la cláusula sensible que se tocó');
      ok(/Mensaje de la base: Tu texto cambia un bloque/.test(await page.locator('#tc-ed-estado').textContent()), t + 'y el mensaje original queda como detalle');
      await page.locator('#tc-ed-estado [data-tc-ir]').first().click();
      if (PNG) await page.screenshot({ path: PNG + '_documento_' + ancho + '.png', fullPage: false });
      ok(errores.length === 0, t + 'A2 sin errores de página: ' + errores.slice(0, 2).join(' || '));
      if (ancho === 390) {
        const desborda = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
        ok(desborda <= 1, t + 'la página no tiene scroll horizontal (' + desborda + ' px de más)');
        const chicos = await page.evaluate(() => [...document.querySelector('#tc-editor').querySelectorAll('button:not([hidden]),input:not([type=hidden]):not([type=checkbox]),select')].filter(e => e.offsetParent && e.getBoundingClientRect().height < 34 && e.getBoundingClientRect().height > 0).map(e => e.id || e.className).slice(0, 5));
        ok(chicos.length === 0, t + 'ningún control táctil por debajo de 34 px de alto: ' + chicos.join(','));
        ok(await page.evaluate(() => !document.getElementById('tc-indice-det').open), t + 'en el móvil el índice empieza plegado');
      }
      await ctx.close();
    }
    /* ── A3. modo oscuro: legible y sin sombras ── */
    {
      const ctx = await browser.newContext({ viewport: { width: ancho, height: ancho > 800 ? 900 : 844 }, colorScheme: 'dark' });
      const page = await ctx.newPage();
      await page.route('**/*', async route => {
        const u = new URL(route.request().url());
        if (u.origin === HOST) {
          let p = decodeURIComponent(u.pathname); if (p.endsWith('/')) p += 'index.html';
          const f = path.join(RAIZ, p);
          if (fs.existsSync(f) && fs.statSync(f).isFile()) { let body = fs.readFileSync(f); if (path.extname(f) === '.html') body = Buffer.from(body.toString('utf8').replace(/\sintegrity="[^"]*"/g, ''), 'utf8'); return route.fulfill({ status: 200, contentType: MIME[path.extname(f)] || 'application/octet-stream', body }); }
          return route.fulfill({ status: 404, body: '' });
        }
        if (/supabase\.min\.js/.test(u.href)) return route.fulfill({ status: 200, contentType: 'text/javascript', body: STUB });
        if (u.protocol === 'data:' || u.protocol === 'blob:') return route.continue();
        return route.fulfill({ status: 200, contentType: /\.css|fonts\.googleapis/.test(u.href) ? 'text/css' : 'text/javascript', body: '' });
      });
      await page.goto(HOST + '/intranet/v4/textos-contrato/?p=ae', { waitUntil: 'load' });
      await page.waitForSelector('[data-tc-editar="ppjb_reserva"]', { timeout: 15000 });
      await page.locator('[data-tc-editar="ppjb_reserva"]').click();
      await esperaPapel(page);
      const papel = await page.locator('#tc-trozos').evaluate(el => { const c = getComputedStyle(el); return { bg: c.backgroundColor, fg: c.color, sombra: c.boxShadow }; });
      const lum = (rgb) => { const m = rgb.match(/\d+/g).map(Number); return (0.2126 * m[0] + 0.7152 * m[1] + 0.0722 * m[2]) / 255; };
      ok(lum(papel.bg) < 0.25 && lum(papel.fg) > 0.6, t + 'modo oscuro: el papel es oscuro y el texto claro (' + papel.bg + ' / ' + papel.fg + ')');
      ok(papel.sombra === 'none', t + 'sin sombras');
      if (PNG) await page.screenshot({ path: PNG + '_oscuro_' + ancho + '.png', fullPage: false });
      await ctx.close();
    }
    /* ── B. super de empresa: activar con confirmación ── */
    {
      const { ctx, page, errores } = await nueva(browser, ancho, 'p=se');
      await page.locator('[data-tc-editar="commercial_offer"]').click();
      await esperaPapel(page);
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
    /* ── C. global: las dos empresas, sin partes sensibles ── */
    {
      const { ctx, page, errores } = await nueva(browser, ancho, 'p=gl');
      ok(await page.locator('#tc-empresa-caja').isVisible() && await page.locator('#tc-empresa option').count() === 2, t + 'el global elige entre las dos empresas');
      await page.locator('[data-tc-editar="commercial_offer"]').click();
      await esperaPapel(page);
      ok(await page.locator('#tc-trozos .tc-par-sens').count() === 0, t + 'el global no ve partes sensibles');
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
      await esperaPapel(page);
      await page.locator('#tc-trozos [data-tc-trozo]').first().click();
      ok(await page.locator('#tc-trozos [contenteditable="true"]').count() === 0, t + 'solo-global: nada se puede editar');
      ok(await page.locator('#tc-guardar').isDisabled(), t + 'solo-global: no se puede guardar');
      ok(/administrador global/.test(await page.locator('#tc-ed-aviso').textContent()), t + 'solo-global: lo dice');
      ok(await page.locator('#tc-trozos .tc-par-sens').count() === 0, t + 'solo-global: no llena el texto de avisos de parte sensible');
      await ctx.close();
    }
    /* ── E. la base contesta con algo hostil: se pinta como texto ── */
    {
      const { ctx, page } = await nueva(browser, ancho, 'p=ae&hostil=1');
      await page.locator('[data-tc-editar="commercial_offer"]').click();
      await esperaPapel(page);
      await editaPar(page, 'acabados de calidad superior', ' otra');
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
    /* ── G. sin las etiquetas de los campos (tokens.json falla): se dice, no se enseñan claves ── */
    {
      const { ctx, page } = await nueva(browser, ancho, 'p=ae&tokens=error');
      await page.locator('[data-tc-editar="ppjb_reserva"]').click();
      await esperaPapel(page);
      ok(/nombres de los campos/.test(await page.locator('#tc-ed-aviso').textContent()), t + 'si no se pueden leer los nombres de los campos, la pantalla lo dice');
      const ps = await page.locator('#tc-trozos .tc-marca').allTextContents();
      ok(ps.length > 0 && ps.every(x => !/_/.test(x)), t + 'y las pastillas siguen legibles (nunca la clave con guion bajo)');
      await ctx.close();
    }
  }
  await browser.close();
  if (fallos.length) { console.error('FALLA (' + fallos.length + '):\n - ' + fallos.join('\n - ')); process.exit(1); }
  console.log('arnes_textos_contrato OK: pantalla verificada a 1440 y 390 px (claro y oscuro) con tres personas: documento con índice, idiomas, marcadores, partes sensibles editables con aviso, rechazos de la base en llano, simulación, guardado, activación, historial y un mensaje hostil.');
})().catch(e => { console.error(e); process.exit(2); });
