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
igual(rpcDe(aj), ['ia_ajustes_guarda', 'ia_ajustes_ver', 'ia_cliente_guarda'], 'ajustes-ia.js llama solo a las tres de Ajustes › IA (cortar va por LW_IA; sin permiso por persona desde el 17-oct)');
// 17-oct-2026 (owner: «quita lo de dar permiso porque se tienen que loguear»): ia_permiso_guarda se cierra a authenticated
const todos = leer('supabase', 'migrations', '20261017043002_mcp_todos.sql');
igual(/revoke execute on function public\.ia_permiso_guarda\(uuid, boolean\) from authenticated;/.test(todos), true, 'mcp_todos cierra ia_permiso_guarda a authenticated (ninguna pantalla la llama)');
igual(/ia_permiso_guarda/.test(aj + comun), false, 'ninguna pantalla nombra ia_permiso_guarda');
[...rpcDe(comun), ...rpcDe(aj)].forEach((f) => {
  if (!abiertas.has(f)) falla(f + ' no se abre a authenticated en las migraciones');
  if (!funcion(f)) falla(f + ' no está definida en las migraciones de P1/P4');
});
// los parámetros que manda cada llamada son los que declara la función (un nombre mal escrito da 404 de PostgREST, no un error legible)
const llamadas = [...(comun + aj).matchAll(/(?:\.rpc|\bguarda)\('([a-z_]+)', \{([^}]*)\}/g)];
igual(llamadas.map((m) => m[1]).sort(), ['ia_ajustes_guarda', 'ia_cliente_guarda', 'ia_conexion_revoca'],
  'se leen las tres llamadas con parámetros');
llamadas.forEach(([, f, args]) => {
  const declarados = (funcion(f) || { params: '' }).params.split(',').map((x) => x.trim().split(/\s+/)[0]).filter(Boolean).sort();
  const mandados = [...args.matchAll(/\b(p_[a-z_]+):/g)].map((m) => m[1]).sort();
  igual(mandados, declarados, 'la llamada a ' + f + ' manda los parámetros que declara la función');
});
igual(/lwDatos\(/.test(aj) || /lwDatos\(/.test(comun) || /_datos'/.test(aj + comun), false, 'ninguna pantalla del puente usa lwDatos ni una *_datos: son lecturas de ia_puente_rol, no de lw_lector (080000)');

/* ── 2. códigos de error → frase ── */
const ERR = clavesDe(bloque(aj, 'ERR')), ERR_CLIENTE = clavesDe(bloque(aj, 'ERR_CLIENTE')), ERR_CORTAR = clavesDe(bloque(comun, 'ERR_CORTAR'));
igual(ERR.slice().sort(), codigos('ia_ajustes_guarda'), 'Topes/interruptor: una frase por cada error de ia_ajustes_guarda');
igual(ERR_CLIENTE.slice().sort(), codigos('ia_cliente_guarda'), 'Asistentes: una frase por cada error de ia_cliente_guarda');
igual(ERR_CORTAR.slice().sort(), codigos('ia_conexion_revoca'), 'Cortar: una frase por cada error de ia_conexion_revoca');
igual(/falta_tope/.test(codigos('ia_ajustes_guarda').join()), true, 'la base sigue rechazando encender con tope 0 (falta_tope)');

/* ── 3. motivos de corte: los del CHECK, ni uno más ni uno menos ── */
// el ÚLTIMO que lo define manda: P1 lo crea en la columna y P6 (aviso de conexión, 16-oct) lo sustituye con 'sin_aviso'
let check = /revocada_motivo text check \(revocada_motivo in \(([^)]*)\)\)/.exec(p1);
for (const f of fs.readdirSync(path.join(RAIZ, 'supabase', 'migrations')).filter((x) => x.endsWith('.sql')).sort()) {
  const m = /add constraint ia_conexiones_revocada_motivo_check\s+check \(revocada_motivo in \(([^)]*)\)\)/.exec(leer('supabase', 'migrations', f));
  if (m) check = m;
}
const delCheck = check ? [...check[1].matchAll(/'([a-z_]+)'/g)].map((m) => m[1]).sort() : [];
igual(delCheck.length, 11, 'se lee el CHECK de revocada_motivo (los 10 de P1 + sin_aviso de P6)');
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
const bl = (d) => { const b = IA.bloques(d); return [b.conLista, b.vacio, b.claude && b.claude.map((k) => k.id), b.chatgpt && b.chatgpt.map((k) => k.id)]; };
igual(bl({ conexiones: [] }), [false, false, null, null], 'bloques sin lista de la base: los dos asistentes, sin identificador');
igual(bl(null), [false, false, null, null], 'bloques sin datos no revienta');
igual(bl({ clientes: [] }), [true, true, [], []], 'bloques con la lista vacía: ningún asistente activo');
igual(bl({ clientes: [{ id: 'c1', asistente: 'claude' }] }), [true, false, ['c1'], []], 'bloques solo con Claude: no enseña ChatGPT');
igual(bl({ clientes: [{ id: 'g1', asistente: 'chatgpt' }, null] }), [true, false, [], ['g1']], 'bloques solo con ChatGPT (y una fila nula ignorada)');
igual(bl({ clientes: [{ id: 'c1', asistente: 'claude' }, { id: 'g1', asistente: 'chatgpt' }, { id: 'c2', asistente: 'claude' }] }), [true, false, ['c1', 'c2'], ['g1']], 'bloques con los dos: cada identificador en su asistente');

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
igual((aj.match(/tono: 'peligro'/g) || []).length, 2, 'apagar la IA y apagar un asistente paran con diálogo de peligro');
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

/* ── 6b. la invitación de la cabecera (aviso-ia.js, 16-oct-2026, sesión mcp-aviso; revisión previa #403) ── */
const avisoJs = leer('intranet', 'v4', 'assets', 'aviso-ia.js');
const AV = require('./aviso-ia.js');
const VIVA = { id: 'v', viva: true, revocada_en: null }, CADUCADA = { id: 'k', viva: false, revocada_en: null }, CORTADA = { id: 'x', viva: false, revocada_en: 't' };
const base = (o) => Object.assign({ encendido: true, permiso: true, conexiones: [] }, o);
igual([
  AV.queAviso(base({}), true), AV.queAviso(base({}), false),
  AV.queAviso(base({ clientes: [{ id: 'c', asistente: 'claude' }] }), false), AV.queAviso(base({ clientes: [] }), true),
  AV.queAviso(base({ encendido: false }), true), AV.queAviso(base({ permiso: false }), true),
  AV.queAviso(base({ conexiones: [VIVA] }), true), AV.queAviso(base({ conexiones: [CADUCADA] }), true),
  AV.queAviso(base({ conexiones: [CORTADA] }), true), AV.queAviso(base({ conexiones: [CADUCADA, VIVA] }), true),
  AV.queAviso(base({ conexiones: null }), true), AV.queAviso(null, true)
], ['conecta', null, 'conecta', null, null, null, null, 'reconecta', 'conecta', null, null, null],
'aviso de la cabecera: sale con IA encendida + permiso + 0 vivas; sin la lista de asistentes, solo al super admin; con ella, si hay uno activo; caducada sola = «vuelve a conectar»');
const ahora = 1e12;
igual([AV.fresco({ t: ahora - 60000, aviso: 'conecta' }, ahora), AV.fresco({ t: ahora - AV.MINUTOS * 60000, aviso: null }, ahora),
  AV.fresco({ t: ahora + 5, aviso: null }, ahora), AV.fresco({ t: ahora, aviso: 'otro' }, ahora), AV.fresco(null, ahora)],
  [true, false, false, false, false], 'el recuerdo de la respuesta vale 3 min, nunca del futuro ni con un valor raro');
{
  const sin = avisoJs.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
  igual(rpcDe(avisoJs), ['ia_mis_conexiones'], 'aviso-ia.js solo lee ia_mis_conexiones');
  if (/\.from\(|innerHTML|insertAdjacentHTML|outerHTML/.test(sin)) falla('aviso-ia.js lee una tabla o pinta con HTML');
  if (/querySelector[^;]*(Conecta|Notificaciones|Buscar)/.test(sin)) falla('aviso-ia.js se engancha por un rótulo: va por data-lw="k-avisos"');
  igual(/querySelector\('header \[data-lw="k-avisos"\]'\)/.test(sin) && /'data-accion', 'aviso-ia-abrir'/.test(sin) && /'data-accion', 'aviso-ia-cerrar'/.test(sin), true, 'aviso-ia.js se engancha por la campana y lleva data-accion');
  igual(/raiz\.AXW_NUCLEO_OPERACION/.test(sin) && /\/intranet\/v4\/ia\//.test(sin), true, 'aviso-ia.js no nace en una instancia ni en /v4/ia/');
  igual(/#[0-9A-Fa-f]{3,8}\b/.test(sin), false, 'aviso-ia.js no lleva un hex suelto: color por token');
  igual(/@media \(max-width:639px\)\{\.lw-aviso-ia\{display:none\}\}/.test(sin), true,
    'aviso-ia.js no sale por debajo de 640 px (le quitaba una línea al nombre de la cabecera: medido el 16-oct)');
}
/* El banner de la portada (17-oct-2026, sesión mcp-ventana): misma regla (queAviso), su hueco por data-lw, data-accion en sus dos
   botones, los dos avisos con todos sus textos, y en la portada no sale la píldora de la cabecera. */
{
  const sin = avisoJs.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
  igual(/querySelector\('\[data-lw="banner-ia"\]'\)/.test(sin) && /'data-accion', 'banner-ia-abrir'/.test(sin) && /'data-accion', 'banner-ia-cerrar'/.test(sin), true,
    'el banner se engancha por data-lw="banner-ia" y lleva data-accion en sus dos botones');
  igual(/if \(hueco\) pintaBanner\(uid, aviso, hueco\); else pinta\(uid, aviso\);/.test(sin), true, 'con el hueco del banner no sale la píldora (y la regla es la misma queAviso)');
  igual(['conecta', 'reconecta'].every((k) => AV.BANNER[k] && ['antetitulo', 'titulo', 'texto', 'boton', 'nota'].every((c) => typeof AV.BANNER[k][c] === 'string' && AV.BANNER[k][c].length > 0)), true,
    'el banner tiene sus cinco textos para «conecta» y para «reconecta»');
  const home = leer('intranet', 'v4', 'home', 'index.html');
  igual((home.match(/<div data-lw="banner-ia" hidden><\/div>/g) || []).length, 1, 'la portada tiene UN hueco del banner, oculto hasta que la base diga que toca');
}
igual(/var AVISO_IA_V = '\d{8}[a-z]?';/.test(nav) && /aut && aut\.ficha && !window\.AXW_NUCLEO_OPERACION\) \{\s+var sa = document\.createElement\('script'\);\s+sa\.src = ROOT \+ 'assets\/aviso-ia\.js\?v=' \+ AVISO_IA_V;/.test(nav), true,
  'nav.js inyecta aviso-ia.js tras LW_AUTH, con su sello AVISO_IA_V y nunca en una instancia del ERP');

/* ── 7. inglés de cada frase de las dos pantallas y de la invitación ── */
const w = {}; new Function('window', leer('contracts', 'assets', 'i18n.js'))(w);
const EN = w.LW_EN;
const frases = new Set();
Object.values(AV.TEXTOS).forEach((t) => frases.add(t));
Object.values(AV.BANNER).forEach((b) => Object.values(b).forEach((t) => frases.add(t)));
AV.EJEMPLOS.forEach((t) => frases.add(t));
[comun, aj, avisoJs].forEach((js) => {
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
