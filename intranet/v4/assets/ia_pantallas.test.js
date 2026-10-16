/* node intranet/v4/assets/ia_pantallas.test.js — «Apps conectadas» (/v4/ia/, ia-conexiones.js) y Ajustes › IA (ajustes-ia.js) contra
   las funciones de la base que llaman (MCP de Lawang F1-P4, 16-oct-2026). La base la prueba supabase/pruebas/mcp_f1_p4_ajustes.sql;
   aquí, lo que une la pantalla con ella y lo que la pantalla decide sola:
   · cada RPC que llaman existe, se abre a authenticated y recibe los parámetros con el NOMBRE que declara la función;
   · cada código de error que devuelven esas funciones tiene su frase en llano (y ninguna frase sobra);
   · cada motivo de corte del CHECK de ia_conexiones tiene su frase;
   · la lógica de estados (activa / en pausa / caducada / cortada), los avisos y el texto de los errores;
   · ni tablas ni HTML con datos: RPC y createElement/textContent; diálogos con el cuerpo escapado; botones con data-real;
   · puertas: /v4/ia/ abre a cualquier ficha; la pestaña IA nace oculta y solo la destapa el super admin global, nunca en una instancia;
   · inglés de cada frase (el marcado lo recorre ficha_parcela.test.js con el resto de plantillas de la v4). */
'use strict';
const fs = require('fs');
const path = require('path');
const assert = require('assert');

const RAIZ = path.join(__dirname, '..', '..', '..');
const leer = (...r) => fs.readFileSync(path.join(RAIZ, ...r), 'utf8').replace(/\r\n/g, '\n');
const errores = [];
const falla = (m) => errores.push(m);
const igual = (a, b, m) => { if (JSON.stringify(a) !== JSON.stringify(b)) falla(m + ' — esperado ' + JSON.stringify(b) + ', recibido ' + JSON.stringify(a)); };

const comun = leer('intranet', 'v4', 'assets', 'ia-conexiones.js');
const aj = leer('intranet', 'v4', 'assets', 'ajustes-ia.js');
const p1 = leer('supabase', 'migrations', '20261016073011_mcp_f1_p1_base.sql');
const p4 = leer('supabase', 'migrations', '20261016073530_mcp_f1_p4_ajustes.sql');
const nombres = leer('supabase', 'migrations', '20261016080111_mcp_f1_p4_nombres.sql');
// la base de hoy: P1 + P4 con los renombres de 080000 aplicados (ALTER ... RENAME conserva cuerpo y grants)
let mig = p1 + '\n' + p4;
const renombres = [...nombres.matchAll(/^alter function public\.([a-z_]+)\([^)]*\) rename to ([a-z_]+);/gm)];
igual(renombres.map((m) => m[1] + '>' + m[2]), ['ia_ajustes_datos>ia_ajustes_ver', 'ia_peticion_datos>ia_peticion_ver'], 'se leen los dos renombres de 080000');
renombres.forEach(([, de, a]) => { mig = mig.replace(new RegExp('public\\.' + de + '\\(', 'g'), 'public.' + a + '('); });

/* ── el cuerpo de una función de la migración (la ÚLTIMA definición, por si se redefine) ── */
function funcion(nombre) {
  const re = new RegExp('create or replace function public\\.' + nombre + '\\(([^)]*)\\)[\\s\\S]*?\\$\\$([\\s\\S]*?)\\$\\$;', 'g');
  let m, ult = null;
  while ((m = re.exec(mig))) ult = { params: m[1], cuerpo: m[2] };
  return ult;
}
function bloque(js, nombre) {   // `var NOMBRE = { … }` con las llaves emparejadas (salta las cadenas)
  const i = js.indexOf('var ' + nombre + ' = {');
  if (i < 0) return null;
  let k = js.indexOf('{', i), d = 0, q = null;
  for (; k < js.length; k++) {
    const c = js[k];
    if (q) { if (c === '\\') k++; else if (c === q) q = null; continue; }
    if (c === "'" || c === '"') q = c; else if (c === '{') d++; else if (c === '}' && --d === 0) break;
  }
  return js.slice(i, k + 1);
}
const clavesDe = (b) => [...(b || '').matchAll(/^\s*([a-z_]+):/gm)].map((m) => m[1]);
const codigos = (f) => [...new Set([...(funcion(f) || { cuerpo: '' }).cuerpo.matchAll(/jsonb_build_object\('error', '([a-z_]+)'/g)].map((m) => m[1]))].sort();

/* ── 1. RPC: la pantalla ↔ la migración ── */
const abiertas = new Set([...mig.matchAll(/grant execute on function public\.([a-z_]+)\([^)]*\) to authenticated;/g)].map((m) => m[1]));
// las escrituras de Ajustes › IA pasan por guarda('ia_…', {…}), el camino común de ajustes-ia.js (16-oct)
const rpcDe = (js) => [...new Set([...js.matchAll(/(?:rpc|lwDatos|\bguarda)\('([a-z_]+)'/g)].map((m) => m[1]))].sort();
igual(rpcDe(comun), ['ia_conexion_revoca', 'ia_mis_conexiones'], 'ia-conexiones.js llama solo a ia_mis_conexiones e ia_conexion_revoca');
igual(rpcDe(aj), ['ia_ajustes_guarda', 'ia_ajustes_ver', 'ia_cliente_guarda', 'ia_permiso_guarda'], 'ajustes-ia.js llama solo a las cuatro de Ajustes › IA (cortar va por LW_IA)');
[...rpcDe(comun), ...rpcDe(aj)].forEach((f) => {
  if (!abiertas.has(f)) falla(f + ' no se abre a authenticated en las migraciones');
  if (!funcion(f)) falla(f + ' no está definida en las migraciones de P1/P4');
});
// los parámetros que manda cada llamada son los que declara la función (un nombre mal escrito da 404 de PostgREST, no un error legible)
const llamadas = [...(comun + aj).matchAll(/(?:\.rpc|\bguarda)\('([a-z_]+)', \{([^}]*)\}/g)];
igual(llamadas.map((m) => m[1]).sort(), ['ia_ajustes_guarda', 'ia_cliente_guarda', 'ia_conexion_revoca', 'ia_permiso_guarda'], 'se leen las cuatro llamadas con parámetros');
llamadas.forEach(([, f, args]) => {
  const declarados = (funcion(f) || { params: '' }).params.split(',').map((x) => x.trim().split(/\s+/)[0]).filter(Boolean).sort();
  const mandados = [...args.matchAll(/\b(p_[a-z_]+):/g)].map((m) => m[1]).sort();
  igual(mandados, declarados, 'la llamada a ' + f + ' manda los parámetros que declara la función');
});
igual(/lwDatos\(/.test(aj) || /lwDatos\(/.test(comun) || /_datos'/.test(aj + comun), false, 'ninguna pantalla del puente usa lwDatos ni una *_datos: son lecturas de ia_puente_rol, no de lw_lector (080000)');

/* ── 2. códigos de error → frase ── */
const ERR = clavesDe(bloque(aj, 'ERR')), ERR_CLIENTE = clavesDe(bloque(aj, 'ERR_CLIENTE')), ERR_PERMISO = clavesDe(bloque(aj, 'ERR_PERMISO')), ERR_CORTAR = clavesDe(bloque(comun, 'ERR_CORTAR'));
igual(ERR.slice().sort(), codigos('ia_ajustes_guarda'), 'Topes/interruptor: una frase por cada error de ia_ajustes_guarda');
igual(ERR_CLIENTE.slice().sort(), codigos('ia_cliente_guarda'), 'Asistentes: una frase por cada error de ia_cliente_guarda');
igual(ERR_PERMISO.slice().sort(), codigos('ia_permiso_guarda'), 'Quién puede conectar: una frase por cada error de ia_permiso_guarda');
igual(ERR_CORTAR.slice().sort(), codigos('ia_conexion_revoca'), 'Cortar: una frase por cada error de ia_conexion_revoca');
igual(/falta_tope/.test(codigos('ia_ajustes_guarda').join()), true, 'la base sigue rechazando encender con tope 0 (falta_tope)');

/* ── 3. motivos de corte: los del CHECK, ni uno más ni uno menos ── */
const check = /revocada_motivo text check \(revocada_motivo in \(([^)]*)\)\)/.exec(p1);
const delCheck = check ? [...check[1].matchAll(/'([a-z_]+)'/g)].map((m) => m[1]).sort() : [];
igual(delCheck.length, 10, 'se lee el CHECK de revocada_motivo');
igual(clavesDe(bloque(comun, 'MOTIVOS')).sort(), delCheck, 'MOTIVOS tiene una frase por cada motivo del CHECK');

/* ── 4. lógica (sin navegador) ── */
const IA = require('./ia-conexiones.js');
const viva = { id: 'a', viva: true, revocada_en: null };
igual(IA.estado(viva, true), 'activa', 'viva con la IA encendida = activa');
igual(IA.estado(viva, false), 'pausada', 'viva con la IA apagada = en pausa (la base no la revoca, niega cada consulta)');
igual(IA.estado({ id: 'b', viva: false, revocada_en: null }, true), 'caducada', 'no viva y sin corte = caducada');
igual(IA.estado({ id: 'c', viva: false, revocada_en: '2026-10-16T01:00:00Z', revocada_motivo: 'persona' }, true), 'cortada', 'con revocada_en = cortada');
const sep = IA.separa([viva, { id: 'b', viva: false }, { id: 'c', viva: false, revocada_en: 'x' }], false);
igual([sep.vivas.map((c) => c.id), sep.pasadas.map((c) => c.id)], [['a'], ['b', 'c']], 'separa: las vivas (también en pausa) a un lado, cortadas y caducadas al otro');
igual(IA.separa(null, true), { vivas: [], pasadas: [] }, 'separa sin lista no revienta');
igual([IA.aviso({ encendido: false, permiso: true }), IA.aviso({ encendido: true, permiso: false }), IA.aviso({ encendido: true, permiso: true }), IA.aviso(null)],
  ['apagado', 'sin_permiso', null, 'apagado'], 'aviso: apagado manda sobre sin permiso; sin datos, apagado');
igual(IA.textoError({ data: { ok: true }, error: null }), null, 'sin error, null');
igual(/permiso/.test(IA.textoError({ data: null, error: { code: '42501', message: 'x' } })), true, '42501 se dice como permiso');
igual(/no ha llegado/i.test(IA.textoError({ data: null, error: { message: 'Failed to fetch' } })), true, 'un fallo de red se dice como «no ha llegado» (no he podido mirar)');
igual(IA.textoError({ data: { error: 'no_existe' } }, { no_existe: 'Esa conexión ya no existe. Recarga la página.' }), 'Esa conexión ya no existe. Recarga la página.', 'un código de negocio sale con su frase');
igual(/raro/.test(IA.textoError({ data: { error: 'raro' } }, {})), true, 'un código sin frase sale con el código, nunca en silencio');
igual(IA.motivoTexto('persona'), 'la cortaste tú', 'motivo en llano');
igual(IA.motivoTexto('otro'), 'cortada', 'motivo desconocido: «cortada» a secas');
igual(IA.asistenteTexto('chatgpt'), 'ChatGPT', 'nombre del asistente');
igual(IA.urlConector(), '', 'sin guard.js (lwEdge) no se inventa la dirección del conector');

/* ── 5. frontera y pintado ── */
[['ia-conexiones.js', comun], ['ajustes-ia.js', aj]].forEach(([n, js]) => {
  const sinComent = js.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
  if (/\.from\(/.test(sinComent)) falla(n + ' lee o escribe una tabla: se pide a la base por RPC');
  if (/innerHTML|insertAdjacentHTML|outerHTML/.test(sinComent)) falla(n + ' pinta con HTML: createElement / textContent');
  if (/\bconfirm\(/.test(sinComent)) falla(n + ' usa confirm(): la suite para con lwConfirmar');
  [...sinComent.matchAll(/cuerpo:\s*([\s\S]*?)\s*,\n\s*confirmar:/g)].forEach((m) => {
    if (!/^'<p>' \+ (IA\.)?esc\(/.test(m[1].trim())) falla(n + ': el cuerpo de un diálogo no va escapado: ' + m[1].trim().slice(0, 60));
  });
  if (/el\('button'/.test(sinComent.replace(/function boton\([\s\S]*?\n  \}/, ''))) falla(n + ': un botón creado fuera de boton() (sin data-real, maqueta.js lo intercepta)');
  if (/querySelector[^;]*(Cortar|Guardar|Encender|Apagar|permiso)/.test(sinComent)) falla(n + ': se engancha por un rótulo: va por data-accion / data-ia-*');
  if (/\btoast\(/.test(sinComent.replace(/raiz\.toast\(m\)|typeof raiz\.toast/g, ''))) falla(n + ': un aviso con toast() suelto: los errores van por toastMal (LW_IA.mal)');
});
igual(/b\.setAttribute\('data-real', ''\)/.test(comun), true, 'boton() pone data-real');
igual((aj.match(/tono: 'peligro'/g) || []).length, 3, 'apagar la IA, apagar un asistente y quitar un permiso paran con diálogo de peligro');
igual(/tono: 'peligro'/.test(comun), true, 'cortar una conexión para con diálogo de peligro');

/* ── 6. puertas y cableado ── */
const iaHtml = leer('intranet', 'v4', 'ia', 'index.html');
const ajHtml = leer('intranet', 'v4', 'ajustes', 'index.html');
const ajJs = leer('intranet', 'v4', 'assets', 'ajustes.js');
const guard = (iaHtml.match(/<script[^>]+guard\.js[^>]*>/) || [''])[0];
igual(!!guard && !/data-(herramienta|rol|ambito)=/.test(guard), true, '/v4/ia/ es de cualquier ficha: guard.js sin data-herramienta, data-rol ni data-ambito');
igual(/<script src="\.\.\/assets\/ia-conexiones\.js\?v=[0-9a-fx]+" defer><\/script>/.test(iaHtml) && /id="lw-ia-apps"/.test(iaHtml), true, '/v4/ia/ carga ia-conexiones.js y tiene #lw-ia-apps');
igual(/<link href="\.\.\/assets\/tw\.css\?v=[0-9a-fx]+" rel="stylesheet"><\/head>/.test(iaHtml), true, '/v4/ia/ enlaza su Tailwind compilado al final del <head>');
igual(JSON.parse(leer('tailwind', 'tailwind.json')).salidas.some((s) => s.css === 'intranet/v4/assets/tw.css' && s.paginas.indexOf('intranet/v4/ia/index.html') !== -1), true, 'tailwind.json compila /v4/ia/ en tw.css');
igual(/var PROPIAS = \{[^}]*\bia: 1/.test(leer('intranet', 'v4', 'assets', 'datos.js')), true, 'datos.js tapa /v4/ia/ hasta que llega su dato (PROPIAS)');
const nav = leer('intranet', 'v4', 'assets', 'nav.js');
igual(/function injertaCuenta\(aside\) \{\n\s+if \(window\.AXW_NUCLEO_OPERACION/.test(nav) && /forEach\(injertaCuenta\)/.test(nav), true, 'nav.js pone «Apps conectadas» en el pie de la barra, y nunca en una instancia del ERP');
igual(/'ia'/.test((/var PESTANAS = \[[^\]]*\]/.exec(ajJs) || [''])[0]), true, 'ajustes.js conoce la pestaña «ia» (sin ella el # no la abre)');
igual(/<button[^>]*data-lw-tab="ia"[^>]*\bhidden\b/.test(ajHtml) && /<div id="lw-panel-ia"[^>]*\bhidden\b/.test(ajHtml), true, 'la pestaña IA y su panel nacen ocultos');
igual(/LW_ROL\.esSuperGlobal\(aut\.ficha\)/.test(aj) && /window\.AXW_NUCLEO_OPERACION\) return;/.test(aj), true, 'solo la destapa el super admin global (es_super_admin() = rol super_admin), nunca en una instancia');
const pos = (f) => ajHtml.indexOf('../assets/' + f + '?v=');
igual(pos('ajustes.js') > 0 && pos('ia-conexiones.js') > pos('ajustes.js') && pos('ajustes-ia.js') > pos('ia-conexiones.js'), true, 'Ajustes carga ajustes.js → ia-conexiones.js → ajustes-ia.js');
igual(/VUELTA = \{\s*claude: 'https:\/\/claude\.ai\/api\/mcp\/auth_callback',\s*chatgpt: 'https:\/\/chatgpt\.com\/connector_platform_oauth_redirect'/.test(aj), true, 'las direcciones de vuelta propuestas son las de cada asistente');
// …y la base las acepta (la propuesta no puede nacer rechazada): se casa contra la expresión de privado.ia_redirect_valida
const rv = /when 'claude'\s+then p_uri ~ '([^']+)'\s+when 'chatgpt' then p_uri ~ '([^']+)'/.exec(p4);
igual(!!rv && new RegExp(rv[1]).test('https://claude.ai/api/mcp/auth_callback') && new RegExp(rv[2]).test('https://chatgpt.com/connector_platform_oauth_redirect'), true, 'las direcciones propuestas pasan la validación de la base');

/* ── 7. inglés de cada frase de las dos pantallas ── */
const w = {}; new Function('window', leer('contracts', 'assets', 'i18n.js'))(w);
const EN = w.LW_EN;
const frases = new Set();
[comun, aj].forEach((js) => {
  for (const m of js.matchAll(/\bT\('((?:[^'\\]|\\.)*)'/g)) frases.add(m[1].replace(/\\'/g, "'"));
  ['MOTIVOS', 'ERR', 'ERR_CLIENTE', 'ERR_CORTAR', 'ERR_PERMISO'].forEach((n) => {
    const b = bloque(js, n);
    if (b) for (const m of b.replace(/\bT\('((?:[^'\\]|\\.)*)'/g, '').matchAll(/'((?:[^'\\]|\\.)*)'/g)) if (/\s/.test(m[1])) frases.add(m[1].replace(/\\'/g, "'"));
  });
});
frases.add('Apps conectadas');   // el rótulo del pie de la barra (nav.js lo pasa por T al traducir la barra)
const sinIngles = [...frases].filter((k) => !Object.prototype.hasOwnProperty.call(EN, k));
igual(frases.size > 120, true, 'se han recogido las frases de las dos pantallas (' + frases.size + ')');
if (sinIngles.length) falla('frases sin inglés en contracts/assets/i18n.js: ' + sinIngles.slice(0, 6).map((x) => '«' + x.slice(0, 50) + '»').join(', ') + (sinIngles.length > 6 ? ' … (' + sinIngles.length + ')' : ''));
// los huecos %x de cada frase siguen en su traducción (un hueco perdido imprime el dato en ningún sitio)
[...frases].filter((k) => EN[k]).forEach((k) => {
  const h = (s) => (s.match(/%[a-z]/g) || []).sort().join();
  if (h(k) !== h(EN[k])) falla('la traducción de «' + k.slice(0, 40) + '» pierde o cambia sus huecos');
});

if (errores.length) { console.error('ia_pantallas.test.js FALLA:\n - ' + errores.join('\n - ')); process.exit(1); }
assert.ok(true);
console.log('ia_pantallas.test.js OK (' + (rpcDe(comun).length + rpcDe(aj).length) + ' RPC, ' + llamadas.length + ' llamadas casadas, ' + delCheck.length + ' motivos, ' + frases.size + ' frases con inglés)');
