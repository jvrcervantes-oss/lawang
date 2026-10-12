// Firma en cadena a medias (12-oct-2026): progresoFirma / etiquetaFirma de datos.js con los casos reales
// que lo motivaron. Se sacan las tres funciones del fuente (datos.js es un IIFE de navegador) y se evalúan solas.
// Ejecutar: node intranet/v4/assets/firma_parcial.test.js
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const src = fs.readFileSync(path.join(__dirname, 'datos.js'), 'utf8');
function saca(nombre) {
  const i = src.indexOf('  function ' + nombre + '(');
  assert.ok(i > -1, 'datos.js ya no define ' + nombre);
  // hasta la línea que cierra la función a dos espacios
  const j = src.indexOf('\n  }\n', i);
  const una = src.slice(i, src.indexOf('\n', i));
  return una.trim().endsWith('}') ? una : src.slice(i, j + 4);
}
const tx = (s, h) => { let v = String(s); for (const k in h) v = v.split('%' + k).join(h[k]); return v; };
const { progresoFirma, etiquetaFirma } = new Function('tx',
  saca('firmaCaducada') + '\n' + saca('progresoFirma') + '\n' + saca('etiquetaFirma') +
  '\nreturn { progresoFirma: progresoFirma, etiquetaFirma: etiquetaFirma };')(tx);

const futuro = new Date(Date.now() + 20 * 864e5).toISOString();
const pasado = new Date(Date.now() - 864e5).toISOString();
const pend = (n) => ({ estado: 'pendiente', expira_en: futuro, firmante_nombre: n });
const hecha = (n) => ({ estado: 'firmado', firmante_nombre: n });

// RP00264: dos compradores, nadie ha firmado, enlace vivo de Gema → «En firma · 0 de 2»
let pf = progresoFirma([pend('GEMA')], 2);
assert.deepStrictEqual([pf.firmadas, pf.total, pf.aMedias], [0, 2, false]);
assert.deepStrictEqual(etiquetaFirma(pf), ['En firma · 0 de 2', 'espera']);

// CR00108: Gema firmó, enlace vivo de Julián → «En firma · 1 de 2»
pf = progresoFirma([hecha('GEMA'), pend('JULIÁN')], 2);
assert.deepStrictEqual(etiquetaFirma(pf), ['En firma · 1 de 2', 'espera']);
assert.strictEqual(pf.hechas[0].firmante_nombre, 'GEMA');

// CR00020: 1 de 2 y sin enlace vivo (cadena rota) → «Firma a medias», en rojo
pf = progresoFirma([hecha('A')], 2);
assert.strictEqual(pf.aMedias, true);
assert.deepStrictEqual(etiquetaFirma(pf), ['Firma a medias · 1 de 2', 'mal']);

// el enlace del siguiente caducó: también es a medias (el comprador ya no puede firmar)
pf = progresoFirma([hecha('A'), { estado: 'pendiente', expira_en: pasado }], 2);
assert.deepStrictEqual(etiquetaFirma(pf), ['Firma a medias · 1 de 2', 'mal']);

// un solo comprador con enlace vivo: nada que añadir (sigue «En firma» de siempre)
assert.strictEqual(etiquetaFirma(progresoFirma([pend('X')], 1)), null);
// sin firmas: borrador, nada que añadir
assert.strictEqual(etiquetaFirma(progresoFirma([], 2)), null);
assert.strictEqual(etiquetaFirma(progresoFirma(undefined, undefined)), null);

// reabierto (RP00203): las firmas viejas pasan a «anulado» y no cuentan
pf = progresoFirma([{ estado: 'anulado' }, { estado: 'anulado' }, pend('X')], 2);
assert.deepStrictEqual(etiquetaFirma(pf), ['En firma · 0 de 2', 'espera']);

// sin filas de compradores (o menos de las que hay): el total nunca baja de lo que hay en firmas
pf = progresoFirma([hecha('A'), pend('B')], 0);
assert.deepStrictEqual(etiquetaFirma(pf), ['En firma · 1 de 2', 'espera']);

console.log('firma_parcial.test.js: OK');
