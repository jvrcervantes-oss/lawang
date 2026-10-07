/* textos-contrato.test.js — pruebas de la pantalla «Textos de contrato» (plantillas por empresa, S7, 8-oct-2026). Se lanza con `node intranet/v4/assets/textos-contrato.test.js`
   desde la raíz de Lawang (lo recoge tools/test.py como el resto de los .test.js).

   Qué afirma, y por qué cada cosa:
   · LA FIDELIDAD DE LA EDICIÓN. La pantalla edita nodos de texto de las 20 plantillas reales y construye el documento nuevo por reemplazo literal. Con las 20: sin tocar nada el
     resultado es el original byte a byte; tocando trozos, lo que cambia es SOLO esos trozos (las etiquetas, los comentarios del motor, los estilos y los marcadores de fuera quedan igual).
   · LOS DATOS QUE VIVEN EN DOS SITIOS no se separan: la CSP de la simulación es la del generador (app.html), la frase que confirma quien activa es la que guarda la base (SQL), y las
     RPC que llama la pantalla son exactamente las que la migración abre a `authenticated`.
   · FRONTERA: la pantalla no escribe en ninguna tabla (solo RPC) y su iframe no lleva ningún permiso. */
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const RAIZ = path.join(__dirname, '..', '..', '..');
const TC = require('./textos-contrato-nucleo.js');
const errores = [];
const falla = (m) => errores.push(m);
const igual = (a, b, m) => { if (a !== b) falla(m + ' — esperado ' + JSON.stringify(String(b).slice(0, 80)) + ', recibido ' + JSON.stringify(String(a).slice(0, 80))); };
const leer = (...r) => fs.readFileSync(path.join(RAIZ, ...r), 'utf8');

/* ── las notas de autor se quitan EXACTAMENTE como lo hace la base (se lee la expresión de la migración, no se copia) ── */
const migS7 = leer('supabase', 'migrations', '20261009010000_f2_plantillas_s7_1_pantalla.sql');
const reSql = /regexp_replace\(p_cuerpo,\s*'(<!--\(\?!.*?\)\.\*\?-->)'/s.exec(migS7);
if (!reSql) falla('no encuentro la expresión de _plantilla_sin_notas en la migración S7');
const sinNotas = (doc) => doc.replace(new RegExp(reSql[1].replace('.*?-->', '[\\s\\S]*?-->'), 'g'), '');

/* ── las 20 plantillas reales ── */
const dir = path.join(RAIZ, 'contracts', 'templates');
const ficheros = fs.readdirSync(dir).filter((f) => f.endsWith('.html') && f !== '_portada.html');
igual(ficheros.length, 20, 'plantillas en contracts/templates');
/* 8-oct-2026 (decisión del owner): lo que se sirve SIN login no lleva notas de autor. El original con notas vive en el repo privado de la
   agencia (contexto/legal/plantillas_lawang/) y `tools/plantillas_publica.py` escribe aquí la copia limpia: una nota nueva en un fichero
   publicado (alguien edita aquí a mano) rompe este test antes de llegar a producción. Vale también para _portada.html. */
const publicados = fs.readdirSync(dir).filter((f) => f.endsWith('.html'));
publicados.forEach((f) => {
  const doc = fs.readFileSync(path.join(dir, f), 'utf8');
  igual(sinNotas(doc), doc, f + ': el fichero publicado no lleva notas de autor (solo comentarios del motor)');
});
const cambiado = JSON.parse(leer('contracts', 'templates', 'texto_cambiado.json'));
ficheros.forEach((f) => {
  const d = cambiado[f.replace(/\.html$/, '')];
  if (typeof d !== 'string' || isNaN(Date.parse(d))) falla(f + ': sin fecha válida en texto_cambiado.json (la lee el bot para «la plantilla cambió tras la firma»)');
});
igual(Object.keys(cambiado).length, ficheros.length, 'texto_cambiado.json: una fecha por plantilla, ni una más');
const etiquetas = (d) => d.match(/<\/?[A-Za-z][^<>]*>|<!--[\s\S]*?-->/g) || [];
let nTrozos = 0;
ficheros.forEach((f) => {
  const doc = sinNotas(fs.readFileSync(path.join(dir, f), 'utf8'));
  const t = TC.trocea(doc);
  nTrozos += t.trozos.length;
  igual(TC.construye(doc, t.trozos, {}), doc, f + ': sin cambios, el documento es el original byte a byte');
  const ed = t.trozos.filter((x) => x.editable);
  if (ed.length < 20) falla(f + ': demasiado pocos trozos editables (' + ed.length + ')');
  // los marcadores de cada trozo se conservan en la lectura
  const marcadoresDoc = (doc.match(/\{\{[a-z0-9_]+\}\}/g) || []).length;
  const marcadoresTrozos = t.trozos.reduce((n, x) => n + TC.marcadores(x.core).length, 0);
  const enEtiquetas = etiquetas(doc).reduce((n, x) => n + (x.match(/\{\{[a-z0-9_]+\}\}/g) || []).length, 0);
  igual(marcadoresTrozos + enEtiquetas, marcadoresDoc, f + ': todo marcador está en un trozo o dentro de una etiqueta');
  // se tocan tres trozos (primero, uno del medio, último) con caracteres que se codifican
  const toca = [ed[0], ed[Math.floor(ed.length / 2)], ed[ed.length - 1]];
  const cambios = {};
  toca.forEach((x, k) => { cambios[x.i] = x.texto + ' & más > ' + k + ' fin'; });
  const nuevo = TC.construye(doc, t.trozos, cambios);
  igual(JSON.stringify(etiquetas(nuevo)), JSON.stringify(etiquetas(doc)), f + ': las etiquetas y los comentarios del motor no se mueven al editar texto');
  const t2 = TC.trocea(nuevo);
  igual(t2.trozos.length, t.trozos.length, f + ': el número de trozos no cambia al editar');
  toca.forEach((x, k) => igual(t2.trozos[x.i].texto, cambios[x.i], f + ': el trozo editado se lee tal como se escribió'));
  // todo lo que no es un trozo editado queda idéntico: se tapan los editados en las dos versiones y se comparan
  const tapa = (d, tr, ids) => { let o = '', cur = 0; tr.forEach((x) => { if (ids.indexOf(x.i) !== -1) { o += d.slice(cur, x.ini) + '§'; cur = x.fin; } }); return o + d.slice(cur); };
  const ids = toca.map((x) => x.i);
  igual(tapa(nuevo, t2.trozos, ids), tapa(doc, t.trozos, ids), f + ': fuera de los trozos editados no cambia ni un byte');
  // y deshacer devuelve el original
  igual(TC.construye(doc, t.trozos, {}), doc, f + ': deshacer devuelve el original');
});

/* ── entidades: lo que se muestra vuelve a su forma ── */
igual(TC.decodifica('a&nbsp;b &amp; c &rsquo; d &#x27;e&#39; &mdash; &hellip;'), 'a b & c ’ d \'e\' — …', 'decodifica entidades de la lista');
igual(TC.decodifica('&desconocida; &lt;'), '&desconocida; &lt;', 'una entidad fuera de la lista no se toca');
igual(TC.codifica('a & b > c d'), 'a &amp; b &gt; c&nbsp;d', 'codifica lo imprescindible');
ficheros.forEach((f) => {
  const doc = sinNotas(fs.readFileSync(path.join(dir, f), 'utf8'));
  TC.trocea(doc).trozos.forEach((x) => { if (TC.decodifica(TC.codifica(x.texto)) !== x.texto) falla(f + ': el trozo ' + x.i + ' no vuelve a su forma al codificarlo'); });
});

/* ── avisos al escribir (la base decide; esto avisa antes) ── */
igual(TC.avisosTrozo('hola', 'hola').length, 0, 'sin cambios no hay avisos');
igual(TC.avisosTrozo('a <b> c', 'a c').length, 1, 'el signo < se avisa');
igual(TC.avisosTrozo('en {{fecha_firma}}', 'en {{fecha_firma}}').length, 0, 'conservar un marcador no avisa');
igual(TC.avisosTrozo('en la fecha', 'en {{fecha_firma}}').length, 1, 'quitar un marcador se avisa');
igual(TC.avisosTrozo('en {{fecha_firma}} y {{prom_cargo}}', 'en {{fecha_firma}}').length, 0, 'añadir un marcador de la lista no avisa (la lista cerrada la impone la base)');
igual(TC.avisosTrozo('en { suelta', 'en').length, 1, 'una llave suelta se avisa');
igual(TC.avisosTrozo('a​b', 'ab').length, 1, 'un carácter de ancho cero se avisa');
igual(TC.avisosTrozo('a‮b', 'ab').length, 1, 'un carácter de dirección (Trojan Source) se avisa');

/* ── bloques fijos: la base dice cuáles, la pantalla los sitúa ── */
{
  const doc = '<h2><span data-lang="es">Las Partes</span></h2><p data-lang="es">Libre uno</p><h2><span data-lang="es">Ley aplicable</span></h2><p data-lang="es">Texto de ley</p>'
    + '<!--bloque-fijo:escrow--><p data-lang="es">Escrow fijo</p><!--/bloque-fijo:escrow--><p data-lang="es">Texto de PT SIAC</p>';
  const lista = ['S|' + TC.ws(doc.slice(doc.indexOf('<h2', 5))), 'E|<p data-lang="es">Texto de PT SIAC</p>', 'M|escrow|<p data-lang="es">Escrow fijo</p>'];
  // la sección «Ley aplicable» (desde su <h2> hasta el siguiente o el final) incluye a las dos de después
  const s = TC.situaBloquesFijos(doc, lista);
  igual(s.sinLocalizar, 0, 'bloques fijos: todos localizados');
  const t = TC.trocea(doc);
  const n = TC.marcaBloqueados(t.trozos, s.spans, false);
  const por = {}; t.trozos.forEach((x) => { por[x.texto] = x.bloqueado; });
  igual(por['Libre uno'], false, 'un párrafo libre no queda bloqueado');
  igual(por['Texto de ley'], true, 'lo que está dentro de una sección fija queda bloqueado');
  igual(por['Escrow fijo'], true, 'una región marcada por Legal queda bloqueada');
  igual(por['Texto de PT SIAC'], true, 'un elemento fijo queda bloqueado');
  igual(TC.situaBloquesFijos(doc, ['E|<p>no existe</p>']).sinLocalizar, 1, 'un bloque fijo que no se encuentra se cuenta (la pantalla lo dice)');
  igual(TC.marcaBloqueados(t.trozos, [], true) >= 4, true, 'solo-global: todo el texto queda en solo lectura');
  igual(n >= 3, true, 'cuenta los trozos editables bloqueados');
}

/* ── comparar ── */
{
  const ops = TC.diff(['a', 'b', 'c', 'd'], ['a', 'x', 'c', 'd', 'e']);
  igual(ops.filter((o) => o.t === '-').map((o) => o.s).join(), 'b', 'diff: lo quitado');
  igual(ops.filter((o) => o.t === '+').map((o) => o.s).join(), 'x,e', 'diff: lo añadido');
  igual(ops.filter((o) => o.t === '=').map((o) => o.s).join(), 'a,c,d', 'diff: lo que sigue igual');
  igual(TC.diff([], []).length, 0, 'diff vacío');
  const enorme = Array.from({ length: 6000 }, (_, i) => 'x' + i), otro = Array.from({ length: 6000 }, (_, i) => 'y' + i);
  igual(TC.diff(enorme, otro).length, 12000, 'diff enorme y distinto: cae a «todo cambió» sin colgarse');
  const doc = '<p data-lang="es">Hola {{nombre_x}}</p><p data-lang="en">Hi</p>';
  igual(TC.lineas(doc).join('|'), '[es] Hola {{nombre_x}}|[en] Hi', 'líneas legibles con su idioma');
}

/* ── simulación ── */
{
  const s = TC.simula('<p>Fecha {{fecha_firma}} <!-- nota --> total {{precio_total}} y {{zzz_qq}} y <b>{{prom_razon}}</b></p>');
  igual(/\{\{|<!--/.test(s), false, 'la simulación no deja marcadores ni comentarios');
  igual(s.indexOf('[zzz_qq]') !== -1, true, 'un marcador sin valor de muestra enseña su nombre');
  igual(TC.simula('{{x_y}}').indexOf('<'), -1, 'los valores de muestra salen escapados');
  const d = TC.docPrevio('<html><head><title>x</title></head><body><p data-lang="es">a</p></body></html>', 'es', 'https://sitio.test', 'https://base.test');
  igual(d.indexOf('<head><meta http-equiv="Content-Security-Policy"'), 0 + d.indexOf('<head>'), 'la CSP es lo primero del <head>');
  igual(/<script/i.test(d), false, 'la vista previa no lleva scripts');
}

/* ── la CSP de la simulación es la del generador ── */
{
  const app = leer('contracts', 'app.html');
  const m = /function cspDocumento\(\)\{[\s\S]*?\n\}/.exec(app);
  if (!m) falla('no encuentro cspDocumento() en contracts/app.html');
  else {
    const ctx = { location: { origin: 'https://sitio.test' }, SUPABASE_URL: 'https://base.test/rest', URL };
    vm.createContext(ctx);
    vm.runInContext(m[0] + '\nthis.__csp = cspDocumento();', ctx);
    igual(TC.csp('https://sitio.test', 'https://base.test'), ctx.__csp, 'la CSP de la vista previa == la de buildDoc() (app.html)');
  }
}

/* ── la frase de confirmación es la que guarda la base ── */
{
  const dirM = path.join(RAIZ, 'supabase', 'migrations');
  const frases = fs.readdirSync(dirM).sort().map((f) => ({ f, s: fs.readFileSync(path.join(dirM, f), 'utf8') }))
    .map((x) => ({ f: x.f, m: /v_texto constant text := '([^']*)';/.exec(x.s) })).filter((x) => x.m);
  if (!frases.length) falla('no encuentro v_texto en las migraciones');
  else igual(TC.TEXTO_CONFIRMACION, frases[frases.length - 1].m[1], 'la confirmación de la pantalla == la que guarda plantilla_contrato_activa (' + frases[frases.length - 1].f + ')');
}

/* ── la pantalla: RPC, frontera, enganches ── */
{
  const js = leer('intranet', 'v4', 'assets', 'textos-contrato.js'), html = leer('intranet', 'v4', 'textos-contrato', 'index.html');
  const rpcs = [...new Set([...js.matchAll(/rpc\('([a-z_]+)'/g)].map((m) => m[1]))].sort();
  const grant = /grant execute on function([\s\S]*?) to authenticated;/g;
  const abiertas = new Set(); let g;
  while ((g = grant.exec(migS7)) !== null) [...g[1].matchAll(/public\.([a-z_]+)\(/g)].forEach((m) => abiertas.add(m[1]));
  igual(JSON.stringify(rpcs), JSON.stringify([...abiertas].sort()), 'las RPC que llama la pantalla son EXACTAMENTE las que la migración abre a authenticated');
  igual(rpcs.length, 7, 'siete RPC');
  if (/\.(insert|update|upsert|delete)\s*\(/.test(js)) falla('textos-contrato.js escribe en una tabla: la pantalla escribe solo por RPC');
  const froms = [...js.matchAll(/\.from\('([a-z_]+)'\)/g)].map((m) => m[1]);
  igual(JSON.stringify([...new Set(froms)]), JSON.stringify(['plantillas_contrato']), 'la única tabla que lee es el catálogo de nombres de plantilla');
  if (/\beval\(|document\.write|new Function|outerHTML/.test(js)) falla('textos-contrato.js usa eval / document.write / new Function / outerHTML');
  if (/localStorage|sessionStorage/.test(js)) falla('textos-contrato.js guarda estado en el navegador: la fuente de verdad es la base');
  // cada id que pide el script existe en la página
  const ids = [...new Set([...js.matchAll(/\$\('([a-z0-9-]+)'\)/g)].map((m) => m[1]))];
  ids.forEach((id) => { if (html.indexOf('id="' + id + '"') === -1) falla('el script pide #' + id + ' y la página no lo tiene'); });
  // el iframe de la simulación no lleva ningún permiso
  const fr = /<iframe[^>]*id="tc-previa-frame"[^>]*>/.exec(html);
  if (!fr) falla('falta #tc-previa-frame');
  else {
    if (!/\ssandbox=""/.test(fr[0])) falla('#tc-previa-frame debe llevar sandbox="" (sin allow-scripts ni allow-same-origin)');
    if (/allow-/.test(fr[0])) falla('#tc-previa-frame lleva un permiso allow-*');
  }
  if (!/data-rol="admin"/.test(html)) falla('la puerta debe ser data-rol="admin"');
  if (/data-herramienta=/.test(html)) falla('la pantalla no debe pedir una casilla nueva (data-herramienta)');
  // los botones se enganchan por data-tc-* / id, nunca por su rótulo
  if (/textContent\s*===|innerText\s*===|\.textContent\.(trim\(\)\.)?(indexOf|includes|match)/.test(js)) falla('textos-contrato.js engancha por el texto de algo');
  // los errores de la base se pintan como texto, nunca como HTML
  js.split('\n').forEach((linea) => {
    if (/innerHTML\s*\+?=[^;]*msg\(/.test(linea) && !/esc\([^)]*msg\(/.test(linea)) falla('un mensaje de la base va a innerHTML sin escapar: ' + linea.trim().slice(0, 100));
  });
}

if (errores.length) { console.error('textos-contrato.test.js FALLA:\n - ' + errores.join('\n - ')); process.exit(1); }
console.log('textos-contrato.test.js OK (' + ficheros.length + ' plantillas, ' + nTrozos + ' trozos)');
