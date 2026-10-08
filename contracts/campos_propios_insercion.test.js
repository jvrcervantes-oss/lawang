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

const fabrica = new Function('data', 'html', 'SIGN_MODE', 'REGIMEN_LABEL', 'nombreConResort',
  mCruda[0] + '\n' + mEsc[0] + '\n' + mCampo[0] + '\nreturn function(){\n' + mSust[0] + '\nreturn html;\n};');
function rellena(html, data) { return fabrica(data, html, false, {}, () => '')(); }

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

if (fallos) { console.error(fallos + ' fallo(s)'); process.exit(1); }
console.log('campos_propios_insercion.test.js: OK');
