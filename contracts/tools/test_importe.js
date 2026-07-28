/* Importes tecleados a número — `node tools/test_importe.js` desde contracts/.

   Nace de un fallo real (28-jul-2026): alguien escribió el precio como "44.000"
   y el contrato quedó guardado con precio_total = 44. Causa: los campos de
   dinero eran <input type="number">, donde el punto ES el separador decimal, y
   además `contractPayload()` reparseaba a mano con
   `Number(String(v).replace(/[^\d.-]/g,''))`, que quita la coma pero deja el
   punto. Dos parsers en el mismo fichero y el malo era el que escribía en la BD.

   Saca parseImporte() y fmtImporte() del propio app.html — no los duplica: si
   alguien toca el fichero, esto prueba la versión que se despliega. */
const fs = require('fs'), assert = require('assert');

const src = fs.readFileSync(__dirname + '/../app.html', 'utf8');
const grab = name => {
  const i = src.indexOf('function ' + name + '(');
  assert.ok(i > 0, 'no encuentro ' + name + ' en app.html');
  let depth = 0;
  for (let k = src.indexOf('{', i); k < src.length; k++) {
    if (src[k] === '{') depth++;
    else if (src[k] === '}' && --depth === 0) return src.slice(i, k + 1);
  }
  throw new Error('no se cierra ' + name);
};
eval(grab('parseImporte'));
eval(grab('fmtImporte'));

// [tecleado, valor esperado, cómo debe quedar en pantalla al salir del campo]
const CASOS = [
  ['44.000',    44000,   '44.000'],      // el que rompió el contrato
  ['44,000',    44000,   '44.000'],
  ['44000',     44000,   '44.000'],
  ['44.000,50', 44000.5, '44.000,50'],
  ['44,000.50', 44000.5, '44.000,50'],
  ['1.000.000', 1000000, '1.000.000'],
  ['250000',    250000,  '250.000'],
  ['44,5',      44.5,    '44,50'],
  ['44.5',      44.5,    '44,50'],
  ['€ 44.000',  44000,   '44.000'],      // símbolo pegado
  ['',          null,    null],
  ['   ',       null,    null],
  ['abc',       null,    null],
];

let fallos = 0;
for (const [txt, valor, pantalla] of CASOS) {
  const n = parseImporte(txt);
  const okValor = n === valor || (n != null && valor != null && Math.abs(n - valor) < 1e-9);
  const okPant  = n == null ? pantalla === null : fmtImporte(n) === pantalla;
  if (!okValor || !okPant) {
    fallos++;
    console.error(`MAL  ${JSON.stringify(txt)} -> ${n} (esperado ${valor})` +
                  (n == null ? '' : ` / muestra "${fmtImporte(n)}" (esperado "${pantalla}")`));
  }
}

// El parser roto que vivía en contractPayload. Se comprueba que SIGUE fallando:
// si algún día devolviera lo correcto, este test estaría dando un verde vacío.
const parserViejo = s => Number(String(s).replace(/[^\d.-]/g, '')) || null;
assert.strictEqual(parserViejo('44.000'), 44, 'el fallo original ya no se reproduce: revisar este test');
assert.strictEqual(parseImporte('44.000'), 44000, 'parseImporte volvió a romperse con el separador de miles');

if (fallos) { console.error(`\n${fallos} caso(s) mal`); process.exit(1); }
console.log(`ok — ${CASOS.length} casos, y el fallo original sigue reproduciéndose con el parser viejo`);
