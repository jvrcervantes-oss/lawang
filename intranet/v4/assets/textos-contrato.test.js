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
  /* E8 (8-oct-2026): la pantalla lee además el catálogo de campos propios (nombre en llano de las pastillas {{cx_…}} y menú «Insertar campo»): una RPC más, abierta por su propia migración. */
  const migE8 = leer('supabase', 'migrations', '20261010010000_f2_editor_e8_campos_propios.sql');
  const abiertasE8 = new Set(); const grantE8 = /grant execute on function([\s\S]*?) to authenticated;/g; let g8;
  while ((g8 = grantE8.exec(migE8)) !== null) [...g8[1].matchAll(/public\.([a-z_]+)\(/g)].forEach((m) => abiertasE8.add(m[1]));
  igual(abiertasE8.has('plantilla_campo_propio_lista'), true, 'la migración E8 abre plantilla_campo_propio_lista a authenticated');
  const migPS = leer('supabase', 'migrations', '20261010020000_f2_editor_partes_sensibles.sql');
  igual(/grant execute on function public\.plantilla_contrato_cambios_sensibles\(text, text, int\) to authenticated/.test(migPS), true, 'la migración de partes sensibles abre plantilla_contrato_cambios_sensibles a authenticated');
  igual(JSON.stringify(rpcs), JSON.stringify([...abiertas, 'plantilla_campo_propio_lista', 'plantilla_contrato_cambios_sensibles'].sort()), 'las RPC que llama la pantalla son EXACTAMENTE las que las migraciones abren a authenticated');
  igual(rpcs.length, 9, 'nueve RPC en la pantalla de textos');
  igual(/p_confirma_sensibles: confirma/.test(js) && /p_variante: E\.variante \}\)/.test(js), true, 'guardar manda la confirmación del aviso y el ensayo manda la revisión');
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

/* ── EL EDITOR COMO DOCUMENTO (encargo editor de textos, E1-E3, 8-oct-2026) ──
   Lo que se afirma, y por qué:
   · LOS IDIOMAS NO SE TOCAN ENTRE SÍ. Con las 20 plantillas: reescribir todo el texto español deja el inglés y el indonesio byte a byte igual.
   · NINGÚN MARCADOR SE PIERDE EN SILENCIO: lo que se escribe pasa por textoEscrito y faltanMarcadores; el servidor lo vuelve a comprobar.
   · LAS ETIQUETAS EN LLANO existen para todo marcador de las 20 plantillas (tokens.json + lista de derivados): nunca se enseña «prom_razon».
   · LOS MENSAJES DE LA BASE que la pantalla traduce siguen existiendo en las migraciones: si alguien reescribe uno, esto falla antes de que la pantalla enseñe «otro».
   · TODA FRASE de la pantalla está en el diccionario inglés (una frase sin traducir se ve en el idioma equivocado). */
{
  const tokens = JSON.parse(leer('contracts', 'tokens.json'));
  const campos = TC.etiquetasDeTokens(tokens, 'es');
  const marcadoresTodos = new Set();
  ficheros.forEach((f) => {
    const doc = sinNotas(fs.readFileSync(path.join(dir, f), 'utf8'));
    (doc.match(/\{\{[a-z0-9_]+\}\}/g) || []).forEach((m) => marcadoresTodos.add(m.slice(2, -2)));
    const t = TC.trocea(doc);
    const s = TC.secciones(doc, t.trozos);
    const h2 = (doc.match(/<h2(?:\s[^>]*)?>/gi) || []).length;
    igual(s.n, h2 + 1, f + ': una sección por <h2> más el encabezado');
    let ant = 0, ok = true;
    t.trozos.forEach((x) => { if (x.sec < ant) ok = false; ant = x.sec; if (x.sec < 0 || x.sec > h2) ok = false; });
    igual(ok, true, f + ': la sección de cada trozo crece con el documento y cae dentro del rango');
    // los idiomas no se tocan entre sí: se reescribe todo el español y el resto queda igual
    const es = t.trozos.filter((x) => x.editable && x.lang === 'es');
    if (es.length) {
      const cambios = {}; es.forEach((x) => { cambios[x.i] = x.texto + ' (revisado)'; });
      const nuevo = TC.construye(doc, t.trozos, cambios), t2 = TC.trocea(nuevo);
      igual(t2.trozos.length, t.trozos.length, f + ': reescribir el español no cambia el número de trozos');
      let tocaOtro = 0, cambiaEs = 0;
      t2.trozos.forEach((x, i) => { const o = t.trozos[i]; if (o.lang !== 'es' && x.raw !== o.raw) tocaOtro++; if (o.lang === 'es' && cambios[o.i] !== undefined && x.texto === cambios[o.i]) cambiaEs++; });
      igual(tocaOtro, 0, f + ': reescribir el español deja el inglés y el indonesio byte a byte igual');
      igual(cambiaEs, es.length, f + ': y el español queda como se escribió');
      // «falta revisar»: se cambió es, así que en e id falta revisar y en es no
      const cmp = TC.cambiosRespecto(t.trozos, t2.trozos.map((x, i) => Object.assign({}, x, { sec: t.trozos[i].sec })), {});
      const secs = Object.keys(cmp.sec).map((k) => k.split('|')[1]);
      igual(secs.every((l) => l === 'es'), true, f + ': el cambio solo consta en español');
      const hayEn = t.trozos.some((x) => x.lang === 'en'), sec0 = Object.keys(cmp.sec)[0].split('|')[0];
      if (hayEn) igual(TC.porRevisar(cmp.sec, Number(sec0), 'en', ['es', 'en', 'id']), true, f + ': el inglés queda «falta revisar» en la cláusula que cambió el español');
      igual(TC.porRevisar(cmp.sec, Number(sec0), 'es', ['es', 'en', 'id']), false, f + ': y el español, que es donde se escribió, no');
    }
  });
  marcadoresTodos.forEach((k) => {
    const l = TC.etiquetaMarcador(k, campos);
    if (!l || /_/.test(l)) falla('el marcador {{' + k + '}} no tiene etiqueta en llano (sale «' + l + '»): añádelo a TC.ETIQUETAS_EXTRA');
    if (!campos[k] && !TC.ETIQUETAS_EXTRA[k]) falla('el marcador {{' + k + '}} solo tiene la etiqueta inventada de la clave: ni tokens.json ni ETIQUETAS_EXTRA lo conocen');
    if (campos[k] && TC.ETIQUETAS_EXTRA[k]) falla('el marcador {{' + k + '}} está en tokens.json y también en ETIQUETAS_EXTRA: una etiqueta, un sitio');
  });
  igual(TC.etiquetaMarcador('inventado_x_y', null), 'Inventado x y', 'un marcador desconocido se vuelve legible, no se enseña la clave');
  igual(TC.etiquetasDeTokens({ sections: [{ fields: [['a', { es: 'Nombre (opcional — sustituye al comprador)', en: 'Name' }, 'text'], ['b', { es: 'N.º de contrato:' }, 'text']] }] }, 'es').a, 'Nombre', 'la etiqueta corta quita lo que va entre paréntesis y tras la raya');
  igual(TC.etiquetasDeTokens({ sections: [{ fields: [['a', { es: 'Nombre', en: 'Name' }]] }] }, 'en').a, 'Name', 'la etiqueta sale en el idioma pedido');

  // segmentos y texto escrito
  igual(JSON.stringify(TC.segmentos('a {{x_1}} b {{y}}')), JSON.stringify([{ m: false, v: 'a ' }, { m: true, k: 'x_1' }, { m: false, v: ' b ' }, { m: true, k: 'y' }]), 'segmentos: texto y marcadores en orden');
  igual(TC.segmentos('').length, 0, 'segmentos: vacío');
  igual(TC.segmentos('{{{x}}}').map((s) => s.m ? '[' + s.k + ']' : s.v).join(''), '{[x]}', 'segmentos: una llave de más no se come el marcador');
  igual(TC.textoEscrito([{ t: 'txt', v: 'Hola ' }, { t: 'marca', k: 'fecha_firma' }, { t: 'txt', v: ' fin' }], 'Hola {{fecha_firma}} fin'), 'Hola {{fecha_firma}} fin', 'textoEscrito: sin cambios devuelve el original');
  igual(TC.textoEscrito([{ t: 'txt', v: 'Hola  ' }, { t: 'marca', k: 'a' }, { t: 'txt', v: '\n fin ' }], 'Hola {{a}} fin'), 'Hola {{a}} fin', 'textoEscrito: solo cambia el blanco → no hay cambio fantasma');
  igual(TC.textoEscrito([{ t: 'txt', v: 'Hola mundo' }], 'Hola'), 'Hola mundo', 'textoEscrito: texto nuevo');
  igual(TC.textoEscrito([{ t: 'txt', v: 'a b' }], 'a b'), 'a b', 'textoEscrito: el espacio duro que mete el navegador se vuelve espacio normal');
  igual(TC.textoEscrito([{ t: 'txt', v: 'a b c' }], 'a b'), 'a b c', 'textoEscrito: el espacio duro que ya tenía el original se conserva');
  igual(TC.textoEscrito([{ t: 'otro', v: '<b>x</b>' }], 'x'), '<b>x</b>', 'textoEscrito: lo que cuela el navegador cuenta como texto (la base lo rechaza por el «<»)');
  igual(TC.avisosTrozo('<b>x</b>', 'x').length, 1, 'y el aviso local lo ve antes de enviarlo');
  igual(TC.faltanMarcadores('hola', 'hola {{a}} y {{b}}').join(), 'a,b', 'faltanMarcadores: los nombra');
  igual(TC.faltanMarcadores('hola {{a}}', 'hola {{a}} y {{b}}').join(), 'b', 'faltanMarcadores: solo los que faltan');
  igual(TC.avisosTrozo('hola', 'hola {{a}}', true).length, 0, 'avisosTrozo con sinFaltan no repite el aviso (la pantalla redacta el suyo)');
  igual(TC.avisosTrozo('hola', 'hola {{a}}').length, 1, 'avisosTrozo sin sinFaltan sigue avisando (compatibilidad)');
  // un {{ roto pegado: el aviso local lo ve; uno bien formado pero inexistente lo decide el servidor
  igual(TC.avisosTrozo('hola {{roto', 'hola').length, 1, 'un {{ pegado a medias se avisa antes de enviar');
  igual(TC.avisosTrozo('hola {{no_existe}}', 'hola').length, 0, 'un marcador bien formado pero inexistente lo decide la base (lista cerrada)');

  // cambiosRespecto
  igual(TC.cambiosRespecto([{ texto: 'a' }], [{ i: 0, texto: 'a', sec: 0, lang: 'es' }, { i: 1, texto: 'b', sec: 0, lang: 'es' }], {}), null, 'cambiosRespecto: si no coinciden los trozos no inventa nada');
  const cr = TC.cambiosRespecto([{ texto: 'a' }, { texto: 'b' }], [{ i: 0, texto: 'a', sec: 1, lang: 'es' }, { i: 1, texto: 'b', sec: 1, lang: 'en' }], { 1: 'b2' });
  igual(JSON.stringify(cr), JSON.stringify({ trozo: { 1: true }, sec: { '1|en': true } }), 'cambiosRespecto: lo pendiente cuenta y lo no tocado no');
  igual(TC.cambiosRespecto([{ texto: 'a  b' }], [{ i: 0, texto: 'a b', sec: 0, lang: null }], {}).sec['0|general'], undefined, 'cambiosRespecto: solo el espacio en blanco no es un cambio');

  // los bloques fijos dicen de qué clase son (para el motivo)
  {
    const doc = '<h2><span data-lang="es">Ley aplicable</span></h2><p data-lang="es">Texto de ley</p><!--bloque-fijo:escrow--><p data-lang="es">Escrow fijo</p><!--/bloque-fijo:escrow--><p data-lang="es">Texto de PT SIAC</p><p data-lang="es">Libre</p>';
    const lista = ['E|<p data-lang="es">Texto de PT SIAC</p>', 'M|escrow|<p data-lang="es">Escrow fijo</p>'];
    const s = TC.situaBloquesFijos(doc, lista), t = TC.trocea(doc);
    TC.marcaBloqueados(t.trozos, s.spans, false);
    const por = {}; t.trozos.forEach((x) => { por[x.texto] = x.fijo; });
    igual(por['Escrow fijo'], 'escrow', 'una región de Legal dice su nombre');
    igual(por['Texto de PT SIAC'], 'E', 'un elemento fijo dice que es un elemento');
    igual(por['Libre'], null, 'un párrafo libre no tiene candado');
    const s2 = TC.situaBloquesFijos(doc, ['S|' + TC.ws(doc)]); const t2 = TC.trocea(doc); TC.marcaBloqueados(t2.trozos, s2.spans, false);
    igual(t2.trozos.every((x) => x.fijo === 'S'), true, 'una sección entera dice que es una sección');
  }

  // los mensajes de la base que la pantalla traduce siguen existiendo en las migraciones
  {
    const dirM = path.join(RAIZ, 'supabase', 'migrations');
    const sql = fs.readdirSync(dirM).map((f) => fs.readFileSync(path.join(dirM, f), 'utf8')).join('\n');
    const literal = {
      sesion: 'Sin sesion: vuelve a entrar', solo_global: 'Este texto no lo cambia una empresa sola', sensibles_confirma: 'Has cambiado partes sensibles del contrato',
      marcador_desconocido: 'marcador desconocido {{', marcador_forma: 'marcador con forma no permitida', llave: 'llave suelta o marcador mal cerrado', esqueleto: 'el esqueleto cambia:',
      motivo: 'Falta el motivo del cambio', permiso: 'El texto de los contratos de una empresa lo escribe su administracion', activar_super: 'Activar un texto de contrato lo hace el super administrador',
      caracter: 'caracter bidireccional o invisible', grande: 'El texto supera el tope', no_activable: 'Version no activable',
      /* Revisiones (E7): los mensajes de plantilla_contrato_revision_* */
      rev_restaurar_super: 'Volver a poner un texto en uso lo hace el super administrador', rev_borrar_en_uso: 'No se puede borrar: % contrato(s) usan esta revision',
      rev_borrar_activa: 'Esta revision esta activa', rev_nombre: 'Pon un nombre a la revision', rev_motivo: 'Falta el motivo de la revision', rev_tope: 'Tope de 20 revisiones',
      rev_origen: 'Ese texto de origen no es de esta empresa', rev_estandar: 'La revision estandar no se archiva', rev_no_archivada: 'Esa revision no esta archivada',
      rev_sin_activa: 'Esa revision no tiene una version activa', rev_ya_activa: 'Esa revision ya tiene otra version activa', rev_no_existe: 'Esa revision no existe',
      rev_clave: 'Clave de revision no valida',
      /* Contrato nuevo (E9): los mensajes de plantilla_contrato_nuevo_crea */
      nv_nombre: 'Pon un nombre de 3 a 80 letras', nv_partida: 'Elige si partes de una copia', nv_campos_forma: 'La lista de campos no es valida', nv_campos_catalogo: 'Alguno de los campos no esta en el catalogo',
      nv_tope: 'Una empresa puede tener como mucho 30 contratos propios', nv_duplicado: 'Ya hay un contrato con ese nombre', nv_falta_origen: 'Falta el contrato del que partir',
      nv_origen: 'Ese contrato de origen no existe', nv_no_copia: 'Ese contrato no se copia', nv_sin_texto: 'Ese contrato no tiene texto para tu empresa', nv_partida_invalida: 'El texto de partida no pasa la validacion'
    };
    igual(JSON.stringify(Object.keys(literal).sort()), JSON.stringify(TC.PREFIJOS_BASE.map((x) => x[0]).sort()), 'cada clase de error que la pantalla reconoce tiene su mensaje comprobado contra las migraciones');
    Object.keys(literal).forEach((k) => {
      if (sql.indexOf(literal[k]) === -1) falla('el mensaje de la base «' + literal[k] + '» ya no está en las migraciones: la pantalla dejaría de reconocer el error «' + k + '»');
      igual(TC.clasificaError(literal[k].replace('%', '3')).tipo, k, 'clasificaError reconoce «' + literal[k] + '»');
    });
    igual(TC.clasificaError('algo raro del servidor').tipo, 'otro', 'un mensaje desconocido cae en «otro» y se enseña tal cual');
    igual(TC.clasificaError('marcador desconocido {{zzz}}: no esta en tokens.json').tipo, 'marcador_desconocido', 'el marcador desconocido se reconoce con su cola');
    igual(TC.marcadorDeError('marcador desconocido {{zzz}}: no esta en tokens.json'), 'zzz', 'y se saca el marcador del mensaje');
    igual(TC.marcadorDeError('sin marcador'), null, 'sin marcador, null');
  }

  // toda frase de la pantalla está en el diccionario inglés
  {
    const dic = leer('contracts', 'assets', 'i18n.js');
    const i0 = dic.indexOf('var EN = {'), i1 = dic.indexOf('\n  };', i0), cuerpo = dic.slice(i0, i1);
    const claves = new Set([...cuerpo.matchAll(/^\s*'((?:[^'\\]|\\.)*)'\s*:/gm)].map((m) => m[1].replace(/\\'/g, "'").replace(/\\\\/g, '\\')));
    const js = leer('intranet', 'v4', 'assets', 'textos-contrato.js'), html = leer('intranet', 'v4', 'textos-contrato', 'index.html');
    const sinTraducir = new Set();
    const mira = (s) => { s = s.replace(/\\'/g, "'"); if (/[A-Za-zÁ-ú]{3}/.test(s) && !claves.has(s) && !claves.has(s.trim())) sinTraducir.add(s); };
    [...js.matchAll(/\bT\('((?:[^'\\]|\\.)*)'/g)].forEach((m) => mira(m[1]));
    // las pestañas Revisiones y Campos (textos-contrato-config.js): sus T('…'), sus tablas de frases en llano y lo que traducen de LW_CX
    const cfg = leer('intranet', 'v4', 'assets', 'textos-contrato-config.js'), CXH = require(path.join(RAIZ, 'contracts', 'assets', 'cx_campos.js'));
    [...cfg.matchAll(/\bT\('((?:[^'\\]|\\.)*)'/g)].forEach((m) => mira(m[1]));
    [...cfg.matchAll(/^\s{4}[a-z_]+: '((?:[^'\\]|\\.)*)'[,]?\s*$/gm)].forEach((m) => mira(m[1]));
    Object.values(CXH.FRASES_VALOR).forEach(mira); CXH.TIPOS.forEach((t) => mira(t[1]));
    ['Escribe al menos una opción.', 'Una lista admite como mucho 50 opciones.', 'Cada opción puede tener hasta 80 letras.', 'Las opciones no admiten los signos < > { }.'].forEach(mira);
    CXH.opcionesDeTexto('').errores.forEach(mira);
    [...js.matchAll(/^\s{4}[a-z_]+: '((?:[^'\\]|\\.)*)'[,]?\s*$/gm)].forEach((m) => { if (/^(Tu sesión|Este texto no|Has cambiado una|Un campo|Hay una|El texto cambia|Falta el motivo|Tu usuario|Activar un|Hay un carácter|El texto es|La base dice)/.test(m[1])) mira(m[1]); });
    [...html.matchAll(/<([a-z0-9]+)[^>]*\bdata-lwt\b[^>]*>([^<]+)</g)].forEach((m) => mira(m[2].trim()));
    if (sinTraducir.size) falla('frases de la pantalla sin traducción al inglés en contracts/assets/i18n.js: ' + [...sinTraducir].slice(0, 6).map((x) => '«' + x.slice(0, 50) + '»').join(', ') + (sinTraducir.size > 6 ? ' … (' + sinTraducir.size + ')' : ''));
  }

  // la pantalla: ids nuevos, el papel se pinta con DOM propio y las partes sensibles ya no son de solo lectura
  {
    const js = leer('intranet', 'v4', 'assets', 'textos-contrato.js'), html = leer('intranet', 'v4', 'textos-contrato', 'index.html');
    ['tc-f-cambios', 'tc-f-sin-sens', 'tc-hits', 'tc-hit-ant', 'tc-hit-sig', 'tc-aterriza', 'tc-indice', 'tc-indice-sum', 'tc-indice-det', 'tc-trozos', 'tc-buscar', 'tc-ed-estado'].forEach((id) => {
      if (html.indexOf('id="' + id + '"') === -1) falla('falta #' + id + ' en la página');
    });
    if (/<textarea/.test(js)) falla('el editor vuelve a pintar <textarea>: el documento se edita en el papel');
    if (/innerHTML\s*=\s*[^;]*(t\.texto|valorDe|E\.cambios|E\.doc|cuerpo_html)/.test(js)) falla('el texto del contrato llega a innerHTML: se pinta siempre con createElement / textContent');
    if (/readonly/.test(js)) falla('hay un campo readonly en la pantalla: las partes sensibles se pueden editar con aviso (decisión del owner, 8-oct-2026)');
    if (/if \(!t \|\| t\.bloqueado\) return;/.test(js)) falla('un trozo con candado vuelve a ser intocable: contradice la decisión del owner (editable con aviso)');
    if (/data-tc-pag/.test(js + html)) falla('queda el paginador de 25: el documento es continuo con índice');
    // todo botón que crea el script lleva data-real (si no, maqueta.js se lo come)
    if (!/b\.setAttribute\('data-real', '1'\)/.test(js)) falla('los botones creados por el script deben llevar data-real');
  }
}

/* ── LAS PESTAÑAS REVISIONES Y CAMPOS (textos-contrato-config.js, E7/E8, 8-oct-2026) ──
   · Solo llama RPC que las migraciones E7/E8 abren a `authenticated`, y ninguna tabla (la base manda; el navegador pide).
   · Todo id que pide existe en la página; todo botón lleva data-real (si no, maqueta.js se lo come) y se engancha por data-*, no por su rótulo.
   · «Contrato nuevo» (E9) NO existe todavía: su pestaña está oculta y el script no llama a ninguna RPC de ella.
   · Lo que viene de la base se pinta con textContent. */
{
  const cfg = leer('intranet', 'v4', 'assets', 'textos-contrato-config.js'), html = leer('intranet', 'v4', 'textos-contrato', 'index.html'), core = leer('intranet', 'v4', 'assets', 'textos-contrato.js');
  const migE7 = leer('supabase', 'migrations', '20261010000000_f2_editor_e7_variantes.sql'), migE8 = leer('supabase', 'migrations', '20261010010000_f2_editor_e8_campos_propios.sql');
  const abiertas = new Set(); const gr = /grant execute on function([\s\S]*?) to authenticated;/g; let g;
  const migE9 = leer('supabase', 'migrations', '20261010030000_f2_editor_e9_contrato_nuevo.sql');
  [migE7, migE8, migE9].forEach((m) => { gr.lastIndex = 0; while ((g = gr.exec(m)) !== null) [...g[1].matchAll(/public\.([a-z_]+)\(/g)].forEach((x) => abiertas.add(x[1])); });
  const rpcs = [...new Set([...cfg.matchAll(/'(plantilla_[a-z_]+)'/g)].map((m) => m[1]))].sort();   // llamadas directas y las que pasan por accionRev / accionCampo
  rpcs.forEach((r) => { if (!abiertas.has(r)) falla('textos-contrato-config.js llama a ' + r + ', que ninguna migración E7/E8 abre a authenticated'); });
  igual(JSON.stringify(rpcs), JSON.stringify(['plantilla_campo_propio_archiva', 'plantilla_campo_propio_borra', 'plantilla_campo_propio_guarda', 'plantilla_campo_propio_lista', 'plantilla_campo_propio_valida',
    'plantilla_contrato_nuevo_crea', 'plantilla_contrato_revision_archiva', 'plantilla_contrato_revision_borra', 'plantilla_contrato_revision_crea', 'plantilla_contrato_revision_restaura', 'plantilla_contrato_revisiones_lista']), 'las once RPC de las pestañas Revisiones, Campos y Contrato nuevo');
  // los argumentos con los nombres de las funciones de la migración (PostgREST rechaza un parámetro que no existe)
  const firma = (sql, f) => { const m = new RegExp('create function public\\.' + f + '\\(([^)]*)\\)').exec(sql); return m ? [...m[1].matchAll(/(?:^|,)\s*(p_[a-z_]+)\s/g)].map((x) => x[1]) : null; };
  const llamada = (f) => { const m = new RegExp("rpc\\('" + f + "', \\{([^}]*)\\}").exec(cfg); return m ? [...m[1].matchAll(/(p_[a-z_]+)\s*:/g)].map((x) => x[1]) : null; };
  [[migE7, 'plantilla_contrato_revision_crea'], [migE7, 'plantilla_contrato_revision_archiva'], [migE7, 'plantilla_contrato_revision_restaura'], [migE7, 'plantilla_contrato_revision_borra'],
   [migE7, 'plantilla_contrato_revisiones_lista']].forEach((x) => {
    const a = firma(x[0], x[1]), b = llamada(x[1]);
    if (!a) falla('no encuentro la firma de ' + x[1] + ' en la migración E7');
    else if (b) a.forEach((n) => { if (b.indexOf(n) === -1 && !/default/.test((new RegExp(n + '\\s+\\w+\\s+default').exec(x[0]) || [''])[0])) falla(x[1] + ': la pantalla no manda ' + n); });
  });
  // accionRev manda p_variante (archiva/restaura/borra): se comprueba el uso, no la llamada literal
  igual(/p_empresa: E\.empresa, p_slug: S\.slug, p_variante: variante/.test(cfg), true, 'archivar, restaurar y borrar mandan empresa, contrato y revisión');
  igual(/p_clave: k, p_etiqueta_es: nombre/.test(cfg), true, 'guardar un campo manda clave y nombre');
  // frontera
  if (/\.(insert|update|upsert|delete)\s*\(/.test(cfg)) falla('textos-contrato-config.js escribe en una tabla: solo RPC');
  if (/\.from\(/.test(cfg)) falla('textos-contrato-config.js lee una tabla: solo RPC (los datos ya los trae textos-contrato.js)');
  if (/localStorage|sessionStorage|\beval\(|document\.write|new Function|outerHTML/.test(cfg)) falla('textos-contrato-config.js usa almacenamiento del navegador / eval / outerHTML');
  // el prototipo calcaba un JSON {datos:{…}}; el dato real vive en datos.fields (lo que lee el trigger de contratos)
  igual(/datos: \{ fields: fields \}/.test(cfg), true, 'la vista previa enseña datos.fields, que es donde guarda el contrato');
  // no hay un segundo lector de números en el navegador: la vista previa del JSON sale de la base
  if (/parseFloat|parseInt|Number\(\s*String\(|lwParseImporte|parseImporte/.test(cfg)) falla('textos-contrato-config.js interpreta números: lo único que lee un importe es el servidor');
  // ids y enganches
  const ids = [...new Set([...cfg.matchAll(/\$\('([a-z0-9-]+)'\)/g)].map((m) => m[1]))];
  ids.forEach((id) => { if (html.indexOf('id="' + id + '"') === -1) falla('textos-contrato-config.js pide #' + id + ' y la página no lo tiene'); });
  [...core.matchAll(/\$\('([a-z0-9-]+)'\)/g)].forEach((m) => { if (html.indexOf('id="' + m[1] + '"') === -1) falla('textos-contrato.js pide #' + m[1] + ' y la página no lo tiene'); });
  if (/textContent\s*===|innerText\s*===|\.textContent\.(trim\(\)\.)?(indexOf|includes|match)/.test(cfg)) falla('textos-contrato-config.js engancha por el texto de algo');
  [...cfg.matchAll(/data-(rv|cx)-[a-z]+/g)].forEach((m) => { if (!/data-(rv|cx)-/.test(m[0])) falla('enganche raro ' + m[0]); });
  // todo botón del script sale de boton() (lleva data-real); ningún createElement('button') suelto
  if (/el\('button'/.test(cfg) || /createElement\('button'\)/.test(cfg)) falla('hay un <button> creado sin boton(): le faltaría data-real');
  if (/innerHTML\s*\+?=/.test(cfg)) falla('textos-contrato-config.js usa innerHTML: se pinta con createElement / textContent');
  cfg.split('\n').forEach((l) => { if (/insertAdjacentHTML/.test(l) && !/(textoEstado|pill)\(/.test(l)) falla('insertAdjacentHTML con algo que no es una pastilla propia: ' + l.trim().slice(0, 90)); });
  // los textos que escribe la persona entran escapados en el cuerpo del diálogo
  igual(/cuerpo: '<p>' \+ TC\.esc\(cuerpoTexto\) \+ '<\/p>'/.test(cfg), true, 'el cuerpo de lwConfirmar escapa el texto de la persona');
  // «Contrato nuevo» (E9): asistente de cuatro pasos y UNA sola llamada de escritura, con los argumentos de la migración
  igual(/data-tc-pestana="nuevo"/.test(html) && !/data-tc-pestana="nuevo"[^>]*\shidden/.test(html), true, 'la pestaña «Contrato nuevo» está visible');
  igual(/PESTANAS = \['textos', 'revisiones', 'campos', 'nuevo'\]/.test(cfg), true, 'el script conoce las cuatro pestañas');
  igual((cfg.match(/plantilla_contrato_nuevo_crea/g) || []).length >= 1 && /p_punto_partida: n\.partir/.test(cfg) && /p_slug_origen:/.test(cfg) && /p_version_origen: null/.test(cfg) && /p_campos: campos/.test(cfg), true, 'crear manda nombre, punto de partida, origen, versión y campos');
  const firmaNv = /create function public\.plantilla_contrato_nuevo_crea\(([^)]*)\)/.exec(migE9);
  igual(firmaNv && [...firmaNv[1].matchAll(/(p_[a-z_]+)\s/g)].map((x) => x[1]).join(), 'p_empresa,p_nombre,p_punto_partida,p_slug_origen,p_version_origen,p_campos', 'los argumentos de plantilla_contrato_nuevo_crea son los que manda la pantalla');
  igual(/Esqueleto de partida/.test(migE9) && /nace ARCHIVADA/.test(migE9), true, 'el contrato nuevo nace oculto del generador (la pantalla lo dice)');
  // pestañas en la URL: hash + atrás del navegador
  igual(/addEventListener\('hashchange'/.test(cfg) && /addEventListener\('popstate'/.test(cfg), true, 'las pestañas viven en el hash y responden al botón atrás');
  // el editor sabe de revisiones: las dos RPC que escriben/leen el texto llevan p_variante
  igual(/rpc\('plantilla_contrato_edicion', \{ p_empresa: E\.empresa, p_slug: slug, p_variante: vr \}\)/.test(core), true, 'abrir el editor manda la revisión');
  igual(/p_motivo: motivo, p_variante: E\.variante/.test(core), true, 'guardar el borrador manda la revisión');
  // la lista principal es la revisión estándar: las demás van a su pestaña
  igual(/\(v\.variante \|\| 'estandar'\) === 'estandar'/.test(core), true, 'la lista de plantillas enseña solo la revisión estándar');
  // la pastilla de un campo propio es una pastilla más (misma función) y entra en el texto como {{clave}}
  igual(/pastilla\(k, ''\)/.test(core) && /data-tc-cx/.test(core), true, 'insertar un campo propio pone una pastilla normal');
  // el historial no compara una revisión con el texto de otra
  igual(/\(x\.variante \|\| 'estandar'\) === vr && x\.version < v\.version/.test(core), true, 'el historial compara dentro de la misma revisión');
}

if (errores.length) { console.error('textos-contrato.test.js FALLA:\n - ' + errores.join('\n - ')); process.exit(1); }
console.log('textos-contrato.test.js OK (' + ficheros.length + ' plantillas, ' + nTrozos + ' trozos)');
