/* Comprobación de la equivalencia en IDR — `node tools/test_idr.js` desde contracts/.
   Saca parseImporte() e idrEquiv() del propio app.html (no los duplica: si el
   fichero cambia, esto prueba la versión que se despliega) y comprueba los
   casos que importan: separadores de miles/decimales, importe vacío, moneda
   IDR y falta de tipo de cambio. */
const fs = require('fs'), assert = require('assert');

const src = fs.readFileSync(__dirname + '/../app.html', 'utf8');
const grab = name => {
  const i = src.indexOf('function ' + name + '(');
  assert.ok(i > 0, 'no encuentro ' + name + ' en app.html');
  let depth = 0, j = src.indexOf('{', i);
  for (let k = j; k < src.length; k++) {
    if (src[k] === '{') depth++;
    else if (src[k] === '}' && --depth === 0) return src.slice(i, k + 1);
  }
  throw new Error('no se cierra ' + name);
};
eval(grab('parseImporte'));
eval(grab('idrEquiv'));

// --- el parser lee el importe como lo escribe un agente ---
assert.strictEqual(parseImporte('79.000'), 79000);        // miles a la española
assert.strictEqual(parseImporte('1.343.000'), 1343000);
assert.strictEqual(parseImporte('1,500'), 1500);          // miles a la inglesa
assert.strictEqual(parseImporte('79.000,50'), 79000.5);   // decimal español
assert.strictEqual(parseImporte('79,000.50'), 79000.5);   // decimal inglés
assert.strictEqual(parseImporte('1,5'), 1.5);
assert.strictEqual(parseImporte('79000'), 79000);
assert.strictEqual(parseImporte(''), null);
assert.strictEqual(parseImporte('a plazos'), null);

// --- la equivalencia se imprime pegada al importe, y solo cuando procede ---
const doc = '<p><span class="f f-lg">79.000</span> EUR</p><td class="amt"><span class="mny">20.000</span> EUR</td>';
const out = idrEquiv(doc, { moneda: 'EUR', tipo_cambio_idr: '17000' });
assert.ok(out.includes('79.000</span> EUR <span class="idr-eq">(≈ 1.343.000.000 IDR)</span>'), out);
assert.ok(out.includes('20.000</span> EUR <span class="idr-eq">(≈ 340.000.000 IDR)</span>'), out);
assert.strictEqual(idrEquiv(doc, { moneda: 'EUR' }), doc);                        // sin tipo de cambio, nada
assert.strictEqual(idrEquiv(doc, { moneda: 'IDR', tipo_cambio_idr: '1' }), doc);  // ya está en rupias
assert.ok(!idrEquiv('<span class="f"></span> EUR', { moneda: 'EUR', tipo_cambio_idr: '17000' }).includes('idr-eq'));

console.log('test_idr: ok');
