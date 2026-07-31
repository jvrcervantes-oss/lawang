/* node contracts/assets/huella.test.js
   Falla si la identidad de los párrafos deja de ser estable — que es lo que
   hacía que editar el texto a mano rompiera contratos ya guardados. */
const assert = require('assert');
const { huellaTexto, normaliza, huellaBloque } = require('./huella.js');

/* --- lo mínimo: mismo texto, misma clave --- */
assert.strictEqual(huellaTexto('Cláusula 8'), huellaTexto('Cláusula 8'));
assert.notStrictEqual(huellaTexto('Cláusula 8'), huellaTexto('Cláusula 9'));

/* --- reindentar la plantilla NO cambia la identidad --- */
assert.strictEqual(normaliza('  Las partes\n   acuerdan  '), 'Las partes acuerdan');
assert.strictEqual(
  huellaBloque('Las partes acuerdan', {}),
  huellaBloque('  Las partes\n   acuerdan  ', {}),
  'reenvolver el HTML de la plantilla no debe tirar las ediciones guardadas');

/* --- EL FALLO QUE ORIGINÓ ESTO ---
   Con la clave vieja (el ordinal) insertar un párrafo al principio de la
   plantilla corría todas las claves siguientes, y la edición del párrafo C
   acababa aplicada sobre el D. Con la huella, C sigue siendo C. */
const antes   = ['Reunidos', 'Exponen', 'Cláusula 1', 'Cláusula 2'];
const despues = ['Portada nueva', 'Reunidos', 'Exponen', 'Cláusula 1', 'Cláusula 2'];
const claves = lista => { const v = {}; return lista.map(t => huellaBloque(t, v)); };
const kA = claves(antes), kB = claves(despues);

assert.strictEqual(kA[2], kB[3], 'la Cláusula 1 debe conservar su clave tras insertar un párrafo antes');
assert.strictEqual(kA[3], kB[4], 'la Cláusula 2 también');
assert.ok(!kA.includes(kB[0]), 'el párrafo nuevo estrena clave, no hereda la de nadie');

/* Y lo que de verdad importa: una edición guardada sobre "Cláusula 1" no puede
   caer sobre otro párrafo cuando la plantilla cambia. */
const guardado = { [kA[2]]: 'Cláusula 1 — texto reescrito a mano' };
const destino = kB.filter(k => guardado[k] != null);
assert.deepStrictEqual(destino, [kA[2]], 'la edición cae en un único párrafo');
assert.strictEqual(kB.indexOf(destino[0]), 3, 'y es el párrafo que dice "Cláusula 1"');

/* --- párrafos repetidos: claves distintas, y estables al insertar en medio --- */
const rep = claves(['Firma', 'Firma', 'Firma']);
assert.strictEqual(new Set(rep).size, 3, 'tres párrafos iguales dan tres claves distintas');
const repConIntruso = claves(['Firma', 'Firma', 'Sello', 'Firma']);
assert.strictEqual(rep[0], repConIntruso[0]);
assert.strictEqual(rep[1], repConIntruso[1]);
assert.strictEqual(rep[2], repConIntruso[3], 'la 3ª "Firma" sigue siendo la 3ª aunque se cuele un párrafo distinto');

/* --- huecos de datos: el texto del marcador forma parte de la identidad --- */
assert.notStrictEqual(
  huellaBloque('El precio es {{precio_total}}', {}),
  huellaBloque('El precio es {{precio_reserva}}', {}));

/* --- entradas vacías no revientan --- */
assert.strictEqual(typeof huellaBloque('', {}), 'string');
assert.strictEqual(typeof huellaBloque(null, {}), 'string');

console.log('huella.test.js OK');
