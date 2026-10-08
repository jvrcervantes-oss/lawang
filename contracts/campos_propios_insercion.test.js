/* Insercion segura del valor de un campo propio en el documento. `node campos_propios_insercion.test.js`.
   Ejecuta el CODIGO REAL de contracts/app.html (la sustitucion final de {{campo}} de buildDoc y las funciones esc/campoFijo que usa),
   no una copia: si alguien cambia esa pasada a una que no escapa o que vuelve a expandir, este test falla.
   Garantias que fija: (1) el valor se escapa (& < > "), (2) una sola pasada con funcion de reemplazo: un {{otro}} dentro de un valor NO se expande,
   ni se interpretan los patrones $&, $1 de String.replace, (3) un valor nunca cierra el atributo data-campo ni abre una etiqueta.
   Defensa en profundidad: el servidor (_cx_valor) ya no deja entrar < > { } en el valor. */
const fs = require('fs');
const path = require('path');
const src = fs.readFileSync(path.join(__dirname, 'app.html'), 'utf8').replace(/\r\n/g, '\n');

let fallos = 0;
function ok(cond, msg) { if (!cond) { fallos++; console.error('  FALLA  ' + msg); } }

const mEsc = src.match(/^function esc\(v,k\)\{[^\n]*\}/m);
const mCampo = src.match(/^function campoFijo\(k, valueHtml\)\{[\s\S]*?\n\}/m);
const mCruda = src.match(/^const CAMPOS_IMAGEN_CRUDA = new Set\([^\n]*\);/m);
const mSust = src.match(/^ {2}html=html\.replace\(\/\\\{\\\{\(\[a-z0-9_\]\+\)\\\}\\\}\/g,\(m,k\)=>\{[\s\S]*?\n {2}\}\);/m);
ok(mEsc && mCampo && mCruda && mSust, 'no encuentro en app.html esc / campoFijo / CAMPOS_IMAGEN_CRUDA / la sustitucion final de {{campo}}');
if (!(mEsc && mCampo && mCruda && mSust)) { console.error('abortado'); process.exit(1); }

/* cxDe / LW_CX: la sustitucion final conoce el catalogo de campos propios (E8) para imprimir un Si/No en su idioma. Aqui, el LW_CX real y un catalogo de prueba. */
const LW_CX = require(path.join(__dirname, 'assets', 'cx_campos.js'));
const CAT = [{ clave: 'cx_nota', tipo: 'texto' }, { clave: 'cx_garaje', tipo: 'si_no' }];
const cxDe = (k) => CAT.find((c) => c.clave === k);
const fabrica = new Function('data', 'html', 'SIGN_MODE', 'REGIMEN_LABEL', 'nombreConResort', 'cxDe', 'LW_CX',
  mCruda[0] + '\n' + mEsc[0] + '\n' + mCampo[0] + '\nreturn function(){\n' + mSust[0] + '\nreturn html;\n};');
function rellena(html, data) { return fabrica(data, html, false, {}, () => '', cxDe, LW_CX)(); }

const doc = '<p>Ref: {{cx_nota}}.</p><p>Otro: {{adq1_nombre}}.</p>';
const hostiles = [
  ['<img src=x onerror=alert(1)>', '<img'],
  ['"><script>alert(1)</script>', '<script'],
  ['</span><b onmouseover=x>', '<b '],
  ['{{adq1_nombre}}', null],
  ['$& $1 $` $\'', null],
];
for (const [valor, etiqueta] of hostiles) {
  const out = rellena(doc, { cx_nota: valor, adq1_nombre: 'JUAN' });
  if (etiqueta) ok(!out.includes(etiqueta), 'el valor ' + JSON.stringify(valor) + ' no abre etiqueta: ' + out);
  ok(!/<(img|script|b)\b/.test(out.replace(/<p>|<\/p>|<span class="campo-fijo"[^>]*>|<\/span>/g, '')), 'sin etiquetas coladas con ' + JSON.stringify(valor));
  ok(out.includes('data-campo="cx_nota"'), 'el atributo data-campo sigue intacto con ' + JSON.stringify(valor));
  ok((out.match(/data-campo="/g) || []).length === 2, 'siguen siendo 2 campos, no se creo ni se perdio ninguno con ' + JSON.stringify(valor));
}
const o1 = rellena(doc, { cx_nota: '{{adq1_nombre}}', adq1_nombre: 'JUAN' });
ok(o1.includes('{{adq1_nombre}}') && (o1.match(/JUAN/g) || []).length === 1, 'un {{otro}} dentro de un valor NO se expande (una sola pasada): ' + o1);
const o2 = rellena(doc, { cx_nota: '$& y $1', adq1_nombre: 'X' });
ok(o2.includes('$&amp; y $1'), 'los patrones $& $1 de replace no se interpretan (el & se escapa): ' + o2);
const o3 = rellena(doc, { cx_nota: 'A & B "c"', adq1_nombre: 'X' });
ok(o3.includes('A &amp; B &quot;c&quot;'), 'se escapa & y comillas: ' + o3);

/* Un campo Si/No se guarda como «si» / «no» y se imprime «Sí» / «No»; un campo fuera del catalogo se imprime tal cual (y escapado). */
const o4 = rellena('<p>{{cx_garaje}}</p>', { cx_garaje: 'si' });
ok(/>Sí</.test(o4), 'cx_garaje=si se imprime «Sí» (en español): ' + o4);
const o5 = rellena('<p>{{cx_garaje}}</p>', { cx_garaje: 'no' });
ok(/>No</.test(o5), 'cx_garaje=no se imprime «No»: ' + o5);
const o6 = rellena('<p>{{cx_fuera}}</p>', { cx_fuera: '<b>x</b>' });
ok(o6.includes('&lt;b&gt;x&lt;/b&gt;') && !/<b>/.test(o6), 'un campo propio sin catalogo se imprime escapado: ' + o6);
ok(LW_CX.paraDocumento(CAT[1], 'si', 'en') === 'Yes' && LW_CX.paraDocumento(CAT[1], 'no', 'id') === 'Tidak' && LW_CX.paraDocumento(CAT[1], 'si', 'id') === 'Ya', 'Si/No se lee en el idioma del parrafo');
ok(LW_CX.paraDocumento(CAT[0], '<b>', 'es') === '<b>', 'un texto no se transforma aqui (el escape lo hace esc() al imprimir)');

/* Fallo (4) de la revision del 8-oct: el Si/No de un campo propio dentro de un bloque bilingue que NO es <p> ni <li> (los textos usan <span>, <ul>, <ol> con
   data-lang) salia siempre en español. Se ejecuta el bloque REAL de los idiomas en/id de buildDoc. */
const iL = src.indexOf('  html=enBloquesDeIdioma(html,');
const bloqueLang = iL >= 0 ? src.slice(iL, src.indexOf('\n  });', iL) + 6) : null;
const mHelper = src.match(/^function enBloquesDeIdioma\(h, fn\)\{[\s\S]*?\n\}/m);
ok(bloqueLang && mHelper, 'no encuentro en app.html el bloque de los parrafos en/id de buildDoc');
if (bloqueLang && mHelper) {
  const fabLang = new Function('data', 'html', 'cxDe', 'LW_CX', 'esc', 'campoFijo', 'trMotivoDescuento', 'trNacionalidad',
    mHelper[0] + '\nreturn function(){\n' + bloqueLang + '\nreturn html;\n};');
  const escReal = new Function(mCruda[0] + '\n' + mEsc[0] + '\nreturn esc;')();
  const campoReal = new Function('esc', mCampo[0] + '\nreturn campoFijo;')(escReal);
  const lang = (html, data) => fabLang(data, html, cxDe, LW_CX, escReal, campoReal, () => '', () => '')();
  for (const [html, t] of [['<p data-lang="en">Garage: {{cx_garaje}}</p>', 'p'], ['<li data-lang="en">Garage: {{cx_garaje}}</li>', 'li'],
      ['<span data-lang="en">Garage: {{cx_garaje}}</span>', 'span'], ['<ul data-lang="en"><li>Garage: {{cx_garaje}}</li></ul>', 'ul'], ['<ol data-lang="en"><li>Garage: {{cx_garaje}}</li></ol>', 'ol'],
      ['<span data-lang="en">A <span class="f">x</span> garage: {{cx_garaje}}</span>', 'span anidado']]) {
    const o = lang(html, { cx_garaje: 'si' });
    ok(/>Yes</.test(o) && !o.includes('{{cx_garaje}}'), 'Si/No en ingles dentro de <' + t + ' data-lang="en">: ' + o);
    const oi = lang(html.replace('"en"', '"id"'), { cx_garaje: 'no' });
    ok(/>Tidak</.test(oi), 'Si/No en indonesio dentro de <' + t + ' data-lang="id">: ' + oi);
  }
}

if (fallos) { console.error(fallos + ' fallo(s)'); process.exit(1); }
console.log('campos_propios_insercion.test.js: OK');
