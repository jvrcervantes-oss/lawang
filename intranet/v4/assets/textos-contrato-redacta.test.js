/* textos-contrato-redacta.test.js — la PANTALLA de «Descríbelo en una frase (asistente)» (E10, 13-oct-2026). Se lanza con
   `node intranet/v4/assets/textos-contrato-redacta.test.js` desde la raíz de Lawang (lo recoge tools/test.py).
   La base la prueba supabase/pruebas/editor_ia_redacta.sql y la función supabase/functions/editor-ia/editor-ia.test.js; aquí lo que las une:
   · las RPC que llama la pantalla son exactamente las dos que la migración abre a authenticated para esto (estado y crear), ninguna tabla;
   · nada se pinta con HTML salvo el cuerpo escapado de los diálogos; enganche por data-tc-rd-*, nunca por rótulo;
   · la caja corta la frase en el mismo tope que la función; los textos de Legal (13-oct) están tal cual;
   · el aviso de responsabilidad se acepta con una casilla y la base lo recibe; p_confirma_sensibles solo va a true tras el diálogo;
   · todo lo que enseña tiene su inglés; index.html la carga después del editor, y la sección nace oculta. */
'use strict';
const fs = require('fs');
const path = require('path');
const RAIZ = path.join(__dirname, '..', '..', '..');
const errores = [];
const falla = (m) => errores.push(m);
const igual = (a, b, m) => { if (a !== b) falla(m + ' — esperado ' + JSON.stringify(b) + ', recibido ' + JSON.stringify(a)); };
const leer = (...r) => fs.readFileSync(path.join(RAIZ, ...r), 'utf8');

const js = leer('intranet', 'v4', 'assets', 'textos-contrato-redacta.js');
const tc = leer('intranet', 'v4', 'assets', 'textos-contrato.js');
const html = leer('intranet', 'v4', 'textos-contrato', 'index.html');
const mig = leer('supabase', 'migrations', '20261013235000_editor_ia_redacta.sql');
const motor = leer('supabase', 'functions', 'editor-ia', 'motor.js');

/* ── RPC y frontera ── */
const rpcs = [...new Set([...js.matchAll(/rpc\('([a-z_]+)'/g)].map((m) => m[1]))].sort();
igual(JSON.stringify(rpcs), JSON.stringify(['editor_ia_estado', 'plantilla_contrato_crea_desde_asistente']), 'la pantalla solo llama a editor_ia_estado y a la función de crear');
igual(/grant execute on function public\.plantilla_contrato_crea_desde_asistente\([^)]*\) to authenticated;/.test(mig), true, 'crear se abre a authenticated');
igual(/editor_ia_redaccion_reserva|editor_ia_redaccion_paso/.test(js), false, 'la pantalla no reserva ni marca pasos (eso es de la función editor-ia)');
if (/\.from\(/.test(js)) falla('textos-contrato-redacta.js lee o escribe una tabla');
if (/innerHTML|insertAdjacentHTML|outerHTML/.test(js)) falla('textos-contrato-redacta.js pinta con HTML: lo que se enseña viene del modelo');
const cuerpos = [...js.matchAll(/cuerpo:\s*([^,]+),/g)].map((m) => m[1].trim());
igual(cuerpos.length >= 1 && cuerpos.every((c) => /^'<p>' \+ TC\.esc\([a-z]+\) \+ '<\/p>'$/.test(c)), true, 'el cuerpo del diálogo va escapado');
if (/querySelector[^;]*(Redactar|Crear|Descartar|traducir)/.test(js)) falla('se engancha un botón por su rótulo: va por data-tc-rd-*');
const edges = [...new Set([...js.matchAll(/lwEdge\('([a-z0-9-]+)'\)/g)].map((m) => m[1]))];
igual(JSON.stringify(edges), JSON.stringify(['editor-ia']), 'la pantalla solo llama a la función editor-ia');
igual(/Authorization: 'Bearer ' \+ token/.test(js), true, 'la llamada va con la sesión de la persona');

/* ── topes y textos de Legal ── */
const tope = /REDACTA = \{ frase: (\d+)/.exec(motor);
igual(tope && new RegExp('ta\\.maxLength = ' + tope[1] + ';').test(js), true, 'la caja corta la frase en el mismo tope que la función');
igual(/inp\.maxLength = 75;/.test(js) && /between 3 and 75/.test(mig), true, 'el nombre: 75 letras en pantalla y en la base');
['Tu frase se envía a un proveedor externo de IA (Anthropic) para redactar el borrador. No escribas nombres, direcciones, números de pasaporte ni otros datos de clientes: describe el tipo de contrato y deja los importes como campo.',
 'Este texto lo ha redactado un asistente de IA y el estudio no lo ha revisado. Al activarlo, responde de él %e. La versión en indonesio es la que prevalece y es una traducción automática: antes de usarlo con un cliente, consulte a un abogado o notario que revise la versión en indonesio.']
  .forEach((x) => { if (js.indexOf(x) === -1) falla('falta el texto de Legal tal cual: «' + x.slice(0, 60) + '…»'); });
igual(/p_acepta_aviso: true/.test(js) && /bc\.disabled = !R\.acepta/.test(js), true, 'crear exige la casilla del aviso y la base lo recibe');
igual(/p_confirma_sensibles: confirmaSensibles === true/.test(js) && /if \(ok\) crea\(true\)/.test(js) && (js.match(/crea\(true\)/g) || []).length === 1, true,
  'p_confirma_sensibles solo va a true tras el diálogo de partes sensibles');

/* ── códigos de la función → frase (los de la base al crear, por hint) ── */
const hints = new Set([...mig.matchAll(/hint = '([a-z_]+)'/g)].map((m) => m[1]));
const bloque = /var FRASES_CREA = \{([\s\S]*?)\n  \};/.exec(js);
const claves = bloque ? [...bloque[1].matchAll(/^\s+([a-z_]+):/gm)].map((m) => m[1]) : [];
igual(claves.length > 0, true, 'hay FRASES_CREA');
claves.forEach((h) => { if (!hints.has(h)) falla('FRASES_CREA tiene «' + h + '», que la base no devuelve'); });
['aviso', 'origen', 'usada', 'caducada', 'traduccion', 'forma', 'huella'].forEach((h) => { if (!claves.includes(h)) falla('la base devuelve el hint «' + h + '» al crear y la pantalla no tiene frase'); });

/* ── inglés ── */
const dic = leer('contracts', 'assets', 'i18n.js');
const i0 = dic.indexOf('var EN = {'), i1 = dic.indexOf('\n  };', i0), cuerpoEN = dic.slice(i0, i1);
const en = new Set([...cuerpoEN.matchAll(/^\s*'((?:[^'\\]|\\.)*)'\s*:/gm)].map((m) => m[1].replace(/\\'/g, "'")));
const textos = new Set();
[...js.matchAll(/\bT\('((?:[^'\\]|\\.)*)'/g)].forEach((m) => textos.add(m[1].replace(/\\'/g, "'")));
['FRASES', 'CATEGORIAS', 'FRASES_CREA'].forEach((b) => {
  const m = new RegExp('var ' + b + ' = \\{([\\s\\S]*?)\\n  \\};').exec(js);
  [...(m ? m[1] : '').matchAll(/[a-z_]+: '((?:[^'\\]|\\.)*)'/g)].forEach((x) => textos.add(x[1].replace(/\\'/g, "'")));
});
const sec = /<section class="tc-seccion" id="tc-rd"[^>]*>[\s\S]*?<\/section>/.exec(html);
if (!sec) falla('index.html: falta la sección #tc-rd');
else {
  igual(/id="tc-rd"[^>]*\bhidden\b/.test(sec[0]), true, 'la sección nace oculta (la destapa la base al decir que el asistente existe)');
  [...sec[0].matchAll(/data-lwt>([^<]+)</g)].forEach((m) => textos.add(m[1].trim()));
}
const sin = [...textos].filter((x) => !en.has(x));
if (sin.length) falla('frases sin inglés: ' + sin.slice(0, 5).map((x) => '«' + x.slice(0, 50) + '»').join(', '));

/* ── puente y orden de carga ── */
const puente = /window\.LW_TC = \{([\s\S]*?)\};/.exec(tc);
[...new Set([...js.matchAll(/\bAPI\.([A-Za-z]+)/g)].map((m) => m[1]))].forEach((n) => { if (!puente || !new RegExp('\\b' + n + ':').test(puente[1])) falla('usa API.' + n + ' y window.LW_TC no lo da'); });
const orden = ['textos-contrato.js', 'textos-contrato-config.js', 'textos-contrato-redacta.js'].map((f) => html.indexOf('../assets/' + f + '?v='));
igual(orden.every((x, k) => x > 0 && (k === 0 || x > orden[k - 1])), true, 'index.html carga editor → config → redacta');
igual(/addEventListener\('lw-tc-ir'/.test(leer('intranet', 'v4', 'assets', 'textos-contrato-config.js')) && /'lw-tc-ir'/.test(js), true, 'tras crear, vuelve a la pestaña de textos por el evento que escucha config');

if (errores.length) { console.error('textos-contrato-redacta.test.js FALLA:\n - ' + errores.join('\n - ')); process.exit(1); }
console.log('textos-contrato-redacta.test.js OK (' + rpcs.length + ' RPC, ' + textos.size + ' frases con inglés)');
