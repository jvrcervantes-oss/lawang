// Guarda `contratosActivo()` de datos.js (desacople del núcleo comercial, corte A, 5-oct-2026): node guarda_contratos.test.js
// 1) la función se comporta: sin bandera (Lawang) true; con bandera y sin helper, true (falla abierto); con helper, lo que diga.
// 2) las guardas de la ficha de factura y del botón «Borrar operación» están puestas y el selector no cambió.
const fs = require('fs'), vm = require('vm'), assert = require('assert');
const src = fs.readFileSync(__dirname + '/datos.js', 'utf8');
const m = src.match(/function contratosActivo\(\) \{[\s\S]*?\n  \}/);
assert.ok(m, 'no encuentro contratosActivo en datos.js');
const corre = (win) => vm.runInNewContext('var window = W;' + m[0] + ';contratosActivo()', { W: win });
assert.strictEqual(corre({}), true, 'Lawang (sin bandera): siempre activo');
assert.strictEqual(corre({ axwModuloActivo: () => false }), true, 'sin bandera NO manda el helper: Lawang no cambia');
assert.strictEqual(corre({ AXW_NUCLEO_OPERACION: true }), true, 'maestro sin helper aún: falla abierto');
assert.strictEqual(corre({ AXW_NUCLEO_OPERACION: true, axwModuloActivo: (k) => k !== 'contratos' }), false, 'maestro con contratos apagado: false');
assert.strictEqual(corre({ AXW_NUCLEO_OPERACION: true, axwModuloActivo: (k) => k === 'contratos' }), true, 'maestro con contratos encendido: true');
assert.ok(/if \(contratosActivo\(\)\) acciones\.push\(\{ texto: 'Borrar operación'/.test(src), 'falta la guarda del botón Borrar operación');
assert.ok(/if \(a && c && contratosActivo\(\)\)/.test(src), 'falta la guarda del clic en la ficha de factura');
assert.ok(/c \? \(contratosActivo\(\) \? enlaceFichaContrato\(c\)/.test(src), 'falta la guarda del enlace en la ficha de factura');
assert.strictEqual((src.match(/data-lw-ficha-contrato/g) || []).length, 11, 'el selector data-lw-ficha-contrato no debe cambiar (11: 10 de siempre + la mención del comentario de contratosActivo)');
console.log('OK guarda_contratos.test.js');
