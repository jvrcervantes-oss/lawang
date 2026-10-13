/* textos-contrato-ia.test.js — pruebas de la parte de PANTALLA del asistente IA de «Textos de contrato» (E5/E5b, 13-oct-2026). Se lanza con
   `node intranet/v4/assets/textos-contrato-ia.test.js` desde la raíz de Lawang (lo recoge tools/test.py como el resto de los .test.js).
   La base la prueba supabase/pruebas/servicios_axisworks.sql y la función supabase/functions/editor-ia/editor-ia.test.js; aquí solo lo que une las tres:

   · LAS RPC QUE LLAMA LA PANTALLA son exactamente las editor_ia_* que la migración abre a `authenticated`, menos editor_ia_reserva (esa la
     llama la función con la sesión de la persona, nunca el navegador). editor_ia_cierra solo es de service_role y la pantalla no la nombra.
   · FRONTERA: ni una tabla (.from), ni innerHTML; lo único que va como HTML es el cuerpo del diálogo de confirmación, y escapado.
   · CADA CÓDIGO QUE DEVUELVE LA FUNCIÓN y que una persona puede provocar usando la pantalla tiene su frase en llano (sin frase cae en el
     genérico «No ha salido bien», que no dice qué hacer). Todas las frases tienen su inglés.
   · LOS ENGANCHES con textos-contrato.js existen en los dos lados (si alguien quita un avisa(), el asistente desaparece sin un error).
   · NACE APAGADO: la empresa nace con encendido = false.
   · SERVICIOS DE AXISWORKS (13-oct-2026, owner, AXW-104): la configuración (margen, topes, impago, extracto) ya no está en esta pantalla sino
     en Ajustes → «Servicios de AxisWorks» (ajustes-servicios.js), que solo llama a servicios_axisworks_datos/_guarda y solo se destapa
     para el super administrador global. Las RPC de precios en créditos (editor_ia_ajustes_*) quedan sin permiso y sin llamador. */
'use strict';
const fs = require('fs');
const path = require('path');

const RAIZ = path.join(__dirname, '..', '..', '..');
const errores = [];
const falla = (m) => errores.push(m);
const igual = (a, b, m) => { if (a !== b) falla(m + ' — esperado ' + JSON.stringify(String(b).slice(0, 120)) + ', recibido ' + JSON.stringify(String(a).slice(0, 120))); };
const leer = (...r) => fs.readFileSync(path.join(RAIZ, ...r), 'utf8');

const js = leer('intranet', 'v4', 'assets', 'textos-contrato-ia.js');
const tc = leer('intranet', 'v4', 'assets', 'textos-contrato.js');
const html = leer('intranet', 'v4', 'textos-contrato', 'index.html');
const mig0 = leer('supabase', 'migrations', '20261013020822_editor_ia_apagado.sql');
const mig1 = leer('supabase', 'migrations', '20261013060136_servicios_axisworks_editor_ia.sql');
const mig = mig0 + '\n' + mig1;
const srv = leer('intranet', 'v4', 'assets', 'ajustes-servicios.js');
const ajHtml = leer('intranet', 'v4', 'ajustes', 'index.html');
const ajJs = leer('intranet', 'v4', 'assets', 'ajustes.js');
const motor = leer('supabase', 'functions', 'editor-ia', 'motor.js');
const config = leer('supabase', 'config.toml');

/* ── RPC: la pantalla ↔ la migración ── */
const alAutenticado = new Set(), alServicio = new Set();
[...mig.matchAll(/grant execute on function public\.([a-z_]+)\([^)]*\)(?:, public\.([a-z_]+)\([^)]*\))? to ([a-z_]+);/g)].forEach((m) => [m[1], m[2]].filter(Boolean).forEach((f) => (m[3] === 'authenticated' ? alAutenticado : alServicio).add(f)));
// lo que la migración de servicios deja sin permiso (sin llamador desde el 13-oct): fuera de lo abierto
igual(/revoke all on function public\.editor_ia_ajustes_datos\(\), public\.editor_ia_ajustes_guarda\(text, jsonb, text\)\s+from public, anon, authenticated, service_role;/.test(mig1), true,
  'la migración de servicios quita el permiso a editor_ia_ajustes_datos/_guarda');
['editor_ia_ajustes_datos', 'editor_ia_ajustes_guarda'].forEach((f) => alAutenticado.delete(f));
const deAjustes = [...new Set([...srv.matchAll(/(?:rpc|lwDatos)\('([a-z_]+)'/g)].map((m) => m[1]))].sort();
igual(JSON.stringify(deAjustes), JSON.stringify(['servicios_axisworks_datos', 'servicios_axisworks_guarda']), 'Ajustes → Servicios llama solo a servicios_axisworks_datos y _guarda');
['servicios_axisworks_datos', 'servicios_axisworks_guarda'].forEach((f) => { if (!alAutenticado.delete(f)) falla(f + ' no se abre a authenticated'); });
const deLaPantalla = [...new Set([...js.matchAll(/rpc\('([a-z_]+)'/g)].map((m) => m[1]))].sort();
const esperadas = [...alAutenticado].filter((f) => f !== 'editor_ia_reserva').sort();
igual(JSON.stringify(deLaPantalla), JSON.stringify(esperadas), 'las RPC que llama la pantalla son EXACTAMENTE las que la migración abre a authenticated, salvo la reserva');
igual(deLaPantalla.length, 4, 'cuatro RPC en la pantalla del asistente');
igual(alAutenticado.has('editor_ia_reserva'), true, 'la reserva se abre a authenticated (la llama la función CON la sesión de la persona)');
igual(/sb\.rpc\('editor_ia_reserva'/.test(motor), true, 'la función reserva con el cliente de la persona (sb), no con el de servicio');
igual(JSON.stringify([...alServicio].sort()), JSON.stringify(['editor_ia_cierra', 'editor_ia_enviada']), 'solo editor_ia_cierra y editor_ia_enviada son de service_role');
igual(/editor_ia_cierra|editor_ia_enviada/.test(js), false, 'la pantalla no nombra editor_ia_cierra ni editor_ia_enviada');
igual(/rpc\('editor_ia_reserva'/.test(js), false, 'la pantalla no reserva por su cuenta');
if (/[^a-z_]grant [^;]* to (anon|public)\b/i.test(mig)) falla('la migración abre algo a anon o public');
if (/\.from\(|innerHTML|insertAdjacentHTML|outerHTML/.test(srv)) falla('ajustes-servicios.js lee una tabla o pinta con HTML: RPC y createElement / textContent');
igual(/encendido\s+boolean not null default false/.test(mig), true, 'cada empresa nace con el asistente apagado');

/* ── la función: un solo nombre, con verificación del JWT ── */
const edges = [...new Set([...js.matchAll(/lwEdge\('([a-z0-9-]+)'\)/g)].map((m) => m[1]))];
igual(JSON.stringify(edges), JSON.stringify(['editor-ia']), 'la pantalla solo llama a la función editor-ia');
igual(/\[functions\.editor-ia\]\s*\nverify_jwt = true/.test(config), true, 'config.toml: editor-ia con verify_jwt = true');
igual(/Authorization: 'Bearer ' \+ token/.test(js), true, 'la llamada va con la sesión de la persona');

/* ── frontera y pintado ── */
if (/\.from\(/.test(js)) falla('textos-contrato-ia.js lee o escribe una tabla: se pide a la base por RPC');
if (/innerHTML|insertAdjacentHTML|outerHTML/.test(js)) falla('textos-contrato-ia.js pinta con HTML: lo que se enseña viene de la base o del modelo; createElement / textContent');
const cuerpos = [...js.matchAll(/cuerpo:\s*([^,]+),/g)].map((m) => m[1].trim());
cuerpos.forEach((c) => { if (!/^'<p>' \+ TC\.esc\([a-z]+\) \+ '<\/p>'$/.test(c)) falla('el cuerpo de un diálogo no va escapado: ' + c); });
igual(cuerpos.length >= 1, true, 'el diálogo de gasto existe');
if (/querySelector[^;]*(Pedir|Usar|Traducir|Guardar)/.test(js)) falla('se engancha un botón por su rótulo: va por data-tc-ia-*');
const instruccion = /TOPES = \{[^}]*instruccion: (\d+)/.exec(motor);
igual(instruccion && new RegExp("inp\\.maxLength = " + instruccion[1] + ';').test(js), true, 'la caja de la instrucción corta en el mismo tope que la función');

/* ── códigos de la función → frase en llano ── */
const frasesBloque = /var FRASES = \{([\s\S]*?)\n  \};/.exec(js);
if (!frasesBloque) falla('no encuentro FRASES en textos-contrato-ia.js');
const frases = new Map([...(frasesBloque ? frasesBloque[1] : '').matchAll(/^\s+([a-z_]+): '((?:[^'\\]|\\.)*)'/gm)].map((m) => [m[1], m[2]]));
const codigos = new Set([...motor.matchAll(/error: (?:'([a-z_]+)'|h \}|res\.forma \? '([a-z_]+)' : '([a-z_]+)')/g)].flatMap((m) => [m[1], m[2], m[3]]).filter(Boolean));
['tope_minuto', 'tope_empresa', 'tope_global'].forEach((h) => { if (!new RegExp("h === '" + h + "'").test(motor)) falla('la función ya no devuelve ' + h); codigos.add(h); });
// los que no tienen frase propia a propósito: llamadas mal formadas (la pantalla no las manda) o fallos internos (el genérico es lo que toca)
const genericos = new Set(['metodo', 'accion', 'parametros', 'piezas', 'no_se_pudo_leer', 'no_se_pudo_reservar', 'no_se_pudo_cerrar', 'error_interno']);
// E10 (13-oct-2026): los motivos INTERNOS de los validadores (validaRedaccion / validaTraduccion / textoLimpio) nunca salen como «error»
// de la respuesta: van dentro de propuesta_no_valida como «motivo»
['no_es_texto', 'longitud', 'avisos', 'campo_nuevo', 'enlace', 'prohibido', 'forma', 'nombre', 'campos', 'clausulas'].forEach((c) => genericos.add(c));
// y las acciones redacta / redacta_traduce las pinta textos-contrato-redacta.js con su propio FRASES: entre las dos pantallas cubren
// todo lo que devuelve la función, y ninguna lleva una frase de más
const jsRd = leer('intranet', 'v4', 'assets', 'textos-contrato-redacta.js');
const bloqueRd = /var FRASES = \{([\s\S]*?)\n  \};/.exec(jsRd);
if (!bloqueRd) falla('no encuentro FRASES en textos-contrato-redacta.js');
const frasesRd = new Map([...(bloqueRd ? bloqueRd[1] : '').matchAll(/^\s+([a-z_]+): '((?:[^'\\]|\\.)*)'/gm)].map((m) => [m[1], m[2]]));
[...codigos].forEach((c) => { if (!frases.has(c) && !frasesRd.has(c) && !genericos.has(c)) falla('la función devuelve «' + c + '» y ninguna pantalla tiene frase para él'); });
[...frases.keys(), ...frasesRd.keys()].forEach((c) => { if (!codigos.has(c)) falla('FRASES tiene «' + c + '», que la función ya no devuelve'); });

/* ── inglés de todo lo que enseña ── */
const dic = leer('contracts', 'assets', 'i18n.js');
const i0 = dic.indexOf('var EN = {'), i1 = dic.indexOf('\n  };', i0), cuerpoEN = dic.slice(i0, i1);
const claves = new Set([...cuerpoEN.matchAll(/^\s*'((?:[^'\\]|\\.)*)'\s*:/gm)].map((m) => m[1].replace(/\\'/g, "'")));
const textos = new Set();
[...js.matchAll(/\bT\('((?:[^'\\]|\\.)*)'/g)].forEach((m) => textos.add(m[1].replace(/\\'/g, "'")));
[...frases.values()].forEach((x) => textos.add(x.replace(/\\'/g, "'")));
textos.add('No ha salido bien. No se ha cambiado nada.');
[...srv.matchAll(/\bT\('((?:[^'\\]|\\.)*)'/g)].forEach((m) => textos.add(m[1].replace(/\\'/g, "'")));
const pestSrv = /<button[^>]*data-lw-tab="servicios"[^>]*>([^<]+)</.exec(ajHtml), panelSrv = /<div id="lw-panel-servicios"[\s\S]*?<\/div><\/div>/.exec(ajHtml);
if (!pestSrv || !panelSrv) falla('ajustes/index.html: falta la pestaña «servicios» o su panel #lw-panel-servicios');
else { textos.add(pestSrv[1].trim()); [...panelSrv[0].matchAll(/data-lwt>([^<]+)</g)].forEach((m) => textos.add(m[1].trim())); }
const sinIngles = [...textos].filter((x) => !claves.has(x));
if (process.env.LISTA_EN) console.log(JSON.stringify(sinIngles, null, 1));
if (sinIngles.length) falla('frases del asistente sin inglés en contracts/assets/i18n.js: ' + sinIngles.slice(0, 6).map((x) => '«' + x.slice(0, 50) + '»').join(', ') + (sinIngles.length > 6 ? ' … (' + sinIngles.length + ')' : ''));
igual(textos.size > 60, true, 'se han recogido las frases de la pantalla (' + textos.size + ')');

/* ── enganches con textos-contrato.js ── */
['lw-tc-listo', 'lw-tc-empresa', 'lw-tc-par-abierto', 'lw-tc-pintado', 'lw-tc-guardado'].forEach((ev) => {
  igual(new RegExp("avisa\\('" + ev + "'").test(tc), true, 'textos-contrato.js avisa ' + ev);
  igual(new RegExp("addEventListener\\('" + ev + "'").test(js), true, 'textos-contrato-ia.js escucha ' + ev);
});
const puente = /window\.LW_TC = \{([\s\S]*?)\};/.exec(tc);
const usados = new Set([...js.matchAll(/\bAPI\.([A-Za-z]+)/g)].map((m) => m[1]));
[...usados].forEach((n) => { if (!puente || !new RegExp('\\b' + n + ':').test(puente[1])) falla('textos-contrato-ia.js usa API.' + n + ' y window.LW_TC no lo da'); });

/* ── index.html: el script va después del núcleo y del editor; la pestaña nace oculta y solo la abre el super administrador global ── */
const orden = ['textos-contrato-nucleo.js', 'textos-contrato.js', 'textos-contrato-ia.js'].map((f) => html.indexOf('../assets/' + f + '?v='));
igual(orden.every((x, k) => x > 0 && (k === 0 || x > orden[k - 1])), true, 'index.html carga núcleo → editor → asistente, en ese orden');
igual(/data-tc-ia-pestana|tc-panel-ia|tc-ia-ajustes/.test(html), false, 'la pestaña vieja «Asistente IA» ya no está en Textos de contrato (vive en Ajustes)');
igual(/<button[^>]*data-lw-tab="servicios"[^>]*\bhidden\b/.test(ajHtml), true, 'la pestaña «Servicios de AxisWorks» nace oculta');
igual(/<div id="lw-panel-servicios"[^>]*\bhidden\b/.test(ajHtml), true, 'su panel nace oculto');
igual(/LW_ROL\.esSuperGlobal\(aut\.ficha\)/.test(srv) && /window\.AXW_NUCLEO_OPERACION\) return;/.test(srv), true, 'solo la destapa el super administrador global, y nunca en una instancia del ERP (la base lo vuelve a comprobar)');
igual(/'servicios'/.test((/var PESTANAS = \[[^\]]*\]/.exec(ajJs) || [''])[0]), true, 'ajustes.js conoce la pestaña «servicios» (sin ella el # no la abre)');
igual(ajHtml.indexOf('../assets/ajustes.js?v=') > 0 && ajHtml.indexOf('../assets/ajustes-servicios.js?v=') > ajHtml.indexOf('../assets/ajustes.js?v='), true, 'Ajustes carga ajustes-servicios.js después de ajustes.js');

if (errores.length) { console.error('textos-contrato-ia.test.js FALLA:\n - ' + errores.join('\n - ')); process.exit(1); }
console.log('textos-contrato-ia.test.js OK (' + deLaPantalla.length + ' RPC, ' + codigos.size + ' códigos de la función, ' + textos.size + ' frases con inglés)');
