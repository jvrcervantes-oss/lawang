/* node plantilla-html.test.js — lo que pinta y compara las plantillas de contrato del ERP (28-sep-2026, 6b).
   Lo que se prueba es la SEGUNDA barrera (la primera es la base): que nada fuera de la lista blanca llegue
   interpretado a la vista previa, que los {{campos}} salgan con su etiqueta ESCAPADA y que el diff diga qué
   cláusula cambió aunque el cuerpo venga en una sola línea. */
const assert = require('assert');
const H = require('./plantilla-html.js');
let n = 0;
const es = (dio, esperado, porque) => { n++; assert.strictEqual(dio, esperado, porque + '\n    dio: ' + dio); };
const no = (dio, trozo, porque) => { n++; assert.ok(String(dio).indexOf(trozo) === -1, porque + '\n    dio: ' + dio); };

// ── saneado ─────────────────────────────────────────────────────────────────────────────────────────
es(H.lwPlantillaSanea('<p class="c1">Hola <strong>X</strong></p>'), '<p class="c1">Hola <strong>X</strong></p>', 'lo admitido pasa igual');
es(H.lwPlantillaSanea('<script>alert(1)</script>'), '&lt;script&gt;alert(1)&lt;/script&gt;', 'script se ve como texto, nunca se ejecuta');
es(H.lwPlantillaSanea('<p onclick="x()">a</p>'), '<p>a</p>', 'on* no se copia');
es(H.lwPlantillaSanea('<p style="background:url(javascript:x)">a</p>'), '<p>a</p>', 'style no se copia');
es(H.lwPlantillaSanea('<img src=x onerror=alert(1)>'), '&lt;img src=x onerror=alert(1)&gt;', 'img no admitida: texto');
es(H.lwPlantillaSanea('<a href="javascript:x">a</a>'), '&lt;a href=&quot;javascript:x&quot;&gt;a&lt;/a&gt;', 'enlace no admitido: texto');
es(H.lwPlantillaSanea('<!-- c --><p>a</p>'), '&lt;!-- c --&gt;<p>a</p>', 'comentario como texto');
es(H.lwPlantillaSanea('1 < 2 y 3 > 2'), '1 &lt; 2 y 3 &gt; 2', '< y > sueltos como entidad');
es(H.lwPlantillaSanea('<td colspan="2" rowspan=3 class=\'x\'>a</td>'), '<td class="x" colspan="2" rowspan="3">a</td>', 'colspan/rowspan y class entre comillas simples');
es(H.lwPlantillaSanea('<td colspan="200">a</td>'), '<td>a</td>', 'colspan de 3 cifras no se copia');
es(H.lwPlantillaSanea('<p class="a&quot;onmouseover=x">a</p>'), '<p>a</p>', 'class con caracteres fuera de la lista no se copia');
es(H.lwPlantillaSanea('<br/><BR>'), '<br><br>', 'br vacía, en minúsculas');
es(H.lwPlantillaSanea('</br>'), '', 'cierre de vacía se omite');
es(H.lwPlantillaSanea('<svg><script>x</script></svg>'), '&lt;svg&gt;&lt;script&gt;x&lt;/script&gt;&lt;/svg&gt;', 'svg: texto');
es(H.lwPlantillaSanea('<p <script>>'), '&lt;p &lt;script&gt;&gt;', 'etiqueta rota con otra dentro: texto');
es(H.lwPlantillaSanea(null), '', 'null → vacío');

// ── campos ──────────────────────────────────────────────────────────────────────────────────────────
assert.deepStrictEqual(H.lwPlantillaCamposUsados('{{a}} {{ b_1 }} {{a}} {{Mal}} {{9x}}'), ['a', 'b_1'], 'claves válidas, sin repetir, en orden'); n++;
es(H.lwPlantillaEtiquetaDe('nombre_del_comprador'), 'Nombre del comprador', 'etiqueta por defecto');

// ── vista previa ────────────────────────────────────────────────────────────────────────────────────
const vp = H.lwPlantillaVistaPrevia('<p>Comprador: {{nombre}} {{otro}}</p><script>x</script>',
  [{ clave: 'nombre', etiqueta: '<img src=x onerror=alert(1)>' }]);
n++; assert.ok(vp.indexOf("default-src 'none'") !== -1, 'la vista previa lleva CSP default-src none');
no(vp, '<img', 'la etiqueta del campo va escapada');
n++; assert.ok(vp.indexOf('&lt;img src=x onerror=alert(1)&gt;') !== -1, 'la etiqueta se ve como texto');
n++; assert.ok(/lw-sin[^>]*>\{\{otro\}\} · sin declarar/.test(vp), 'campo sin declarar marcado');
no(vp, '<script>', 'nada de script en la vista previa');

// ── diff ────────────────────────────────────────────────────────────────────────────────────────────
const d0 = H.lwPlantillaDiff('<p>a</p><p>b</p>', '<p>a</p><p>b</p>');
es(d0.iguales, true, 'mismo cuerpo: iguales');
const d1 = H.lwPlantillaDiff('<p>a</p><p>b</p><p>c</p>', '<p>a</p><p>B</p><p>c</p>');
es(d1.iguales, false, 'cambio de una cláusula');
es(d1.lineas.map(l => l.op + l.t).join('|'), ' <p>a</p>|-<p>b</p>|+<p>B</p>| <p>c</p>', 'una línea sola, aunque el cuerpo venga en una');
const d2 = H.lwPlantillaDiff('', '<p>x</p>');
es(d2.lineas.map(l => l.op + l.t).join('|'), '+<p>x</p>', 'desde vacío: todo añadido');
const grande = Array.from({ length: 50 }, (_, i) => '<p>' + i + '</p>').join('');
const d3 = H.lwPlantillaDiff(grande, grande.replace('<p>0</p>', '<p>cero</p>').replace('<p>49</p>', '<p>fin</p>'), 10);
es(d3.aproximado, true, 'por encima del tope no calcula el LCS y lo dice');
es(d3.lineas.filter(l => l.op === '-').length, 50, 'aproximado: el medio sale entero como quitado');
const d4 = H.lwPlantillaDiff('<p>a</p><p>x</p><p>c</p>', '<p>a</p><p>c</p><p>d</p>');
es(d4.lineas.map(l => l.op + l.t).join('|'), ' <p>a</p>|-<p>x</p>| <p>c</p>|+<p>d</p>', 'quita y añade en sitios distintos');

console.log('plantilla-html.test.js OK (' + n + ' comprobaciones)');
