/* NOMBRE PARA ENSEÑAR — 17-oct-2026 (Experiencia, propuestas H3 y S2 de la intranet).
   `node contracts/nombre_visible.test.js`. Lo corre tools/test.py.
   Prueba lwNombreVisible (contracts/assets/vocabulario.js): un nombre entero en mayúsculas se
   enseña en tipo normal; uno con alguna minúscula, siglas de sociedad y lo vacío no se tocan. */
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ctx = { window: {} };
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(path.join(__dirname, 'assets', 'vocabulario.js'), 'utf8') +
  '\n;globalThis.__n = lwNombreVisible;', ctx);
const lwNombreVisible = ctx.__n;

const CASOS = [
  ['MARIA DE LA CRUZ', 'Maria de la Cruz'],
  ['JOSÉ ÁLVAREZ PEÑA', 'José Álvarez Peña'],
  ['ANA-MARÍA O\'BRIEN', 'Ana-María O\'Brien'],
  ['PT LAWANG ESTATE', 'PT Lawang Estate'],
  ['I KETUT SUDIARTA', 'I Ketut Sudiarta'],
  ['DE LA FUENTE GARCIA', 'De la Fuente Garcia'],      // la partícula del principio sí va en mayúscula
  ['Maria de la Cruz', 'Maria de la Cruz'],            // ya escrito a mano: no se toca
  ['McGREGOR', 'McGREGOR'],                            // con una minúscula: no se toca
  ['PT Lawang', 'PT Lawang'],
  ['123', '123'],
  ['', ''],
  [null, ''],
  [undefined, ''],
];

let fallos = 0;
CASOS.forEach(([entrada, esperado]) => {
  const r = lwNombreVisible(entrada);
  if (r !== esperado) { fallos++; console.error(`FALLA: lwNombreVisible(${JSON.stringify(entrada)}) = ${JSON.stringify(r)}, esperaba ${JSON.stringify(esperado)}`); }
});

if (fallos) { console.error(fallos + ' fallo(s)'); process.exit(1); }
console.log('OK nombre_visible.test.js — ' + CASOS.length + ' casos');
