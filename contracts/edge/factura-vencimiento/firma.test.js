/* node firma.test.js — factura-vencimiento ya no firma «Lawang Tropical Properties» a fuego (encargos/20261008_lawang_reclamo_pago_parcela.md).
   La firma sale de la sociedad del CONTRATO y esa misma clave viaja a envia-correo (que pone la marca del correo). Comprueba:
   1. el texto de los correos no contiene la cadena fija (solo puede salir de la sociedad);
   2. firmaDe(): para Lawang el texto sigue siendo «Lawang Tropical Properties»; para Sandal Woods, «Sandal Woods»; sin marca, la razón;
      sin nada, falla (y la firma se calcula ANTES de crear la factura);
   3. la clave de sociedad se manda a envia-correo en los dos correos, y solo si el destino es la edge (el PHP de respaldo no la entiende);
   4. las dos copias del fichero (contracts/edge y supabase/functions) son idénticas: la segunda es la que se despliega. */
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { stripTypeScriptTypes } = require('module');

const A = path.join(__dirname, 'index.ts');
const B = path.join(__dirname, '..', '..', '..', 'supabase', 'functions', 'factura-vencimiento', 'index.ts');
const src = fs.readFileSync(A, 'utf8').replace(/\r\n/g, '\n');
assert.strictEqual(fs.readFileSync(B, 'utf8').replace(/\r\n/g, '\n'), src, 'supabase/functions/factura-vencimiento/index.ts difiere de contracts/edge: son la misma edge');

// 1 · sin la cadena fija fuera de comentarios
const sinComentarios = src.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
assert.ok(!/Lawang Tropical Properties/i.test(sinComentarios), 'queda «Lawang Tropical Properties» escrito a fuego en el texto de los correos');

// 2 · firmaDe
const m = /function firmaDe\([\s\S]*?\n}\n/.exec(src);
assert.ok(m, 'no encuentro firmaDe');
const firmaDe = new Function(stripTypeScriptTypes(m[0]) + '\nreturn firmaDe;')();
const C = { SOCIEDADES: {
  tepi_sungai: { marca: 'LAWANG TROPICAL PROPERTIES', razon: 'PT TEPI SUN GAI' },
  san_dal_woods: { marca: 'Sandal Woods', razon: 'PT SAN DAL WOODS' },
  sin_marca: { marca: '', razon: 'PT SIN MARCA' }, vacia: { marca: '', razon: '' } } };
assert.strictEqual(firmaDe(C, 'tepi_sungai'), 'Lawang Tropical Properties', 'Lawang: el texto sigue siendo el de siempre');
assert.strictEqual(firmaDe(C, 'san_dal_woods'), 'Sandal Woods');
assert.strictEqual(firmaDe(C, 'sin_marca'), 'PT SIN MARCA');
assert.throws(() => firmaDe(C, 'vacia'), /no tiene marca ni razon/);
assert.throws(() => firmaDe(C, 'no_existe'), /no tiene marca ni razon/);
const iFirma = src.indexOf('const firma = firmaDe(C, campos.sociedad)'), iRpc = src.indexOf("sb.rpc('factura_vencimiento_emite'");
assert.ok(iFirma > 0 && iRpc > iFirma, 'la firma se calcula antes de crear la factura');
assert.ok(src.includes("'\\n\\n\\n' + firma,"), 'el correo al comprador termina con la firma de la sociedad');

// 3 · la sociedad viaja a envia-correo, y solo a la edge
assert.strictEqual((src.match(/\n\s+sociedad: campos\.sociedad,\n/g) || []).length, 2, 'los dos correos (comprador y copia al estudio) llevan la sociedad');
assert.ok(src.includes('...(p.sociedad && dest.url === ENVIO_EDGE ? { sociedad: p.sociedad } : {}),'), 'sociedad solo hacia la edge');
// 4 · si el destino no es la edge, una sociedad que NO es Lawang no sale con la marca de Lawang: se corta
assert.ok(src.includes("p.sociedad && p.sociedad !== 'tepi_sungai' && dest.url !== ENVIO_EDGE") && /throw new Error\('email a ' \+ p\.to \+ ': el destino de envio no entiende la sociedad/.test(src), 'sin la edge, una sociedad distinta de Lawang debe cortar el envio');
console.log('OK firma.test.js — sin firma fija; Lawang sigue firmando igual, Sandal Woods como Sandal Woods; la sociedad del contrato viaja a envia-correo solo por la edge; copias idénticas');
