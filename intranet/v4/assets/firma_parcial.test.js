// Firma en cadena a medias (12-oct-2026): progresoFirma / etiquetaFirma de datos.js con los casos reales
// que lo motivaron. Se sacan las tres funciones del fuente (datos.js es un IIFE de navegador) y se evalúan solas.
// Ejecutar: node intranet/v4/assets/firma_parcial.test.js
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const src = fs.readFileSync(path.join(__dirname, 'datos.js'), 'utf8');
// una función de datos.js a dos espacios: de una línea, o hasta su `  }` de cierre
function saca(nombre) {
  const i = src.indexOf('  function ' + nombre + '(');
  assert.ok(i > -1, 'datos.js ya no define ' + nombre);
  const una = src.slice(i, src.indexOf('\n', i));
  return una.trim().endsWith('}') ? una : src.slice(i, src.indexOf('\n  }\n', i) + 4);
}
const tx = (s, h) => { let v = String(s); for (const k in h) v = v.split('%' + k).join(h[k]); return v; };
const { progresoFirma, etiquetaFirma } = new Function('tx',
  saca('firmaCaducada') + '\n' + saca('progresoFirma') + '\n' + saca('etiquetaFirma') +
  '\nreturn { progresoFirma: progresoFirma, etiquetaFirma: etiquetaFirma };')(tx);
const etq = (c, firmas, filas) => etiquetaFirma(progresoFirma(c, firmas, filas));

const futuro = new Date(Date.now() + 20 * 864e5).toISOString();
const pasado = new Date(Date.now() - 864e5).toISOString();
const pend = (n) => ({ estado: 'pendiente', expira_en: futuro, firmante_nombre: n });
const hecha = (n) => ({ estado: 'firmado', firmante_nombre: n });
const dos = { comprador_nombre: 'GEMA · JULIÁN', bloqueado: false, pdf_firmado_path: null };
const uno = { comprador_nombre: 'ANA', bloqueado: false, pdf_firmado_path: null };

// RP00264: dos compradores, nadie ha firmado, enlace vivo de Gema → «En firma · 0 de 2»
let pf = progresoFirma(dos, [pend('GEMA')], 2);
assert.deepStrictEqual([pf.firmadas, pf.total, pf.aMedias], [0, 2, false]);
assert.deepStrictEqual(etiquetaFirma(pf), ['En firma · 0 de 2', 'espera']);

// CR00108: Gema firmó, enlace vivo de Julián → «En firma · 1 de 2»
pf = progresoFirma(dos, [hecha('GEMA'), pend('JULIÁN')], 2);
assert.deepStrictEqual(etiquetaFirma(pf), ['En firma · 1 de 2', 'espera']);
assert.strictEqual(pf.hechas[0].firmante_nombre, 'GEMA');

// CR00020: 1 de 2 y sin enlace vivo (cadena rota) → «Firma a medias», en rojo
assert.deepStrictEqual(etq(dos, [hecha('A')], 2), ['Firma a medias · 1 de 2', 'mal']);
// ... también sin filas de contrato_compradores (comprador sin ficha, o quien mira no la ve): el total sale de los nombres
assert.deepStrictEqual(etq(dos, [hecha('A')], 0), ['Firma a medias · 1 de 2', 'mal']);
assert.deepStrictEqual(etq(dos, [hecha('A')], undefined), ['Firma a medias · 1 de 2', 'mal']);

// el enlace del siguiente caducó: también es a medias (el comprador ya no puede firmar)
assert.deepStrictEqual(etq(dos, [hecha('A'), { estado: 'pendiente', expira_en: pasado }], 2), ['Firma a medias · 1 de 2', 'mal']);

// todos firmaron pero sin bloquear: NO es «a medias» (no falta nadie)
assert.strictEqual(progresoFirma(dos, [hecha('A'), hecha('B')], 2).aMedias, false);
assert.strictEqual(progresoFirma(uno, [hecha('A')], 1).aMedias, false);

// «Desbloquear» (contrato_desbloquea): bloqueado=false, pdf_firmado_path y firmas en «firmado» → manda «reabierto», no se toca
const reab = { comprador_nombre: 'GEMA · JULIÁN', bloqueado: false, pdf_firmado_path: 'firmados/x.pdf' };
assert.strictEqual(etq(reab, [hecha('A'), hecha('B')], 2), null);
assert.strictEqual(etq(reab, [hecha('A')], 2), null);
assert.strictEqual(progresoFirma(reab, [hecha('A')], 2).aMedias, false);

// «Editar (anula la firma)» (RP00203): firmas viejas en «anulado», no cuentan; manda la etiqueta de siempre
assert.strictEqual(etq(reab, [{ estado: 'anulado' }, { estado: 'anulado' }, pend('X')], 2), null);
assert.strictEqual(progresoFirma(reab, [{ estado: 'anulado' }, pend('X')], 2).firmadas, 0);

// un solo comprador con enlace vivo: nada que añadir (sigue «En firma» de siempre)
assert.strictEqual(etq(uno, [pend('X')], 1), null);
// sin firmas: borrador, nada que añadir; y sin contrato ni datos no revienta
assert.strictEqual(etq(dos, [], 2), null);
assert.strictEqual(etq(null, undefined, undefined), null);

// el total nunca baja de lo que hay en firmas, aunque filas y nombres se queden cortos
assert.deepStrictEqual(etq(uno, [hecha('A'), pend('B')], 0), ['En firma · 1 de 2', 'espera']);
// y manda la cuenta mayor de las tres
assert.strictEqual(progresoFirma({ comprador_nombre: 'A · B · C' }, [hecha('A')], 2).total, 3);
assert.strictEqual(progresoFirma({ comprador_nombre: 'A' }, [hecha('A')], 3).total, 3);

console.log('firma_parcial.test.js: OK');
