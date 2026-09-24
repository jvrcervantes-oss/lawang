/* node contracts/frases_vetadas.test.js — la lista de Legal (24-sep-2026) caza lo que
   tiene que cazar y deja pasar el copy normal. Los casos «deben caer» salen de los
   dossiers REALES que se migran (revisión previa #68, Legal #1), no inventados. */
const assert = require('assert');
const F = require('./assets/frases_vetadas.js');

const caen = [
  ['Rental yield from day one', 'rentabilidad'],                      // Horizon_Resort.dossier.json
  ['Strong appreciation expected in Balian', 'rentabilidad'],
  ['Your own freehold villa', 'titularidad'],                         // Palm_Field / Inti / Soka
  ['Freehold land for investment', 'titularidad'],
  ['Villa en propiedad (freehold)', 'titularidad'],                   // plantillas/palm_field.json
  ['Escritura a tu nombre', 'titularidad'],
  ['Hak Milik certificate', 'titularidad'],
  ['No nominee needed', 'titularidad'],
  ['12% anual garantizado', 'rentabilidad'],
  ['8 % p.a. net', 'rentabilidad'],
  ['ROI in 6 years', 'rentabilidad'],
  ['Revalorización asegurada', 'rentabilidad'],
  ['Guaranteed buyback', 'garantia'],
  ['Inversión segura y sin riesgo', 'garantia'],
  ['Only 4 plots left', 'escasez'],
  ['¡Últimas 3 villas!', 'escasez'],
  ['Quedan 2 parcelas', 'escasez'],
  ['Prices will rise in January', 'escasez'],
  ['Renta<b>bilidad</b> del 9 %', 'rentabilidad'],                   // HTML no esconde la palabra
];
const pasan = [
  'Una casa así, *con su parcela*.',
  'Balian, a diez minutos del mar',
  'Freehold (HGB) via PT PMA · or Hak Sewa without a company',
  'Freehold HGB vía PT PMA',
  'Hak Sewa sin empresa',
  'Palm Field · W5',
  'Llave en mano. Nos encargamos de principio a fin.',
  'Return to nature',                                                 // «return» suelto no es rentabilidad
  'Desde 48.000 €',
];

const errores = [];
for (const [t, grupo] of caen) {
  const h = F.revisa(t);
  if (!h.some(x => x.grupo === grupo)) errores.push(`NO caza (${grupo}): «${t}» → ${JSON.stringify(h)}`);
}
for (const t of pasan) {
  const h = F.revisa(t);
  if (h.length) errores.push(`caza de más: «${t}» → ${h.map(x => x.frase).join(', ')}`);
}
// Las dos rutas, por construcción: mencionar la tenencia obliga a llevar la línea.
assert.ok(F.hablaDeTenencia('Hak Sewa for 25 years'), 'Hak Sewa es hablar de tenencia');
assert.ok(F.hablaDeTenencia(['otro', 'Freehold (HGB)']), 'Freehold es hablar de tenencia');
assert.ok(!F.hablaDeTenencia('Balian, a diez minutos del mar'), 'un titular normal no');
// Las etiquetas existen en los dos idiomas y la de precios lleva la fecha.
assert.ok(/no contractual/.test(F.etiqueta('render', 'es')) && /not contractual/.test(F.etiqueta('render', 'en')));
assert.ok(F.etiqueta('precios', 'es', '24-09-2026').includes('24-09-2026'));
assert.ok(F.etiqueta('dosRutas', 'en').includes('Hak Sewa') && F.etiqueta('dosRutas', 'en').includes('HGB'));

assert.deepStrictEqual(errores, [], '\n  ' + errores.join('\n  '));
console.log(`frases_vetadas.test.js OK (${caen.length} caen, ${pasan.length} pasan)`);
