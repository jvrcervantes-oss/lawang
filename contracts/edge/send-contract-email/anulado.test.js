// LAW-37 (11-oct-2026): send-contract-email no genera ni envía el PDF de un documento ANULADO. Antes lo renderizaba,
// lo mandaba por SMTP y solo fallaba después la marca (factura_marca_enviada rechaza anulados desde la 20261010231114).
// Fija la regla EJECUTANDO el bloque de la factura contra una base falsa y comprobando en la fuente que el corte va antes
// del render, del envío y del registro. Corre con: node contracts/edge/send-contract-email/anulado.test.js
'use strict';
const fs = require('fs'), path = require('path'), assert = require('assert');
const src = fs.readFileSync(path.join(__dirname, 'index.ts'), 'utf8').replace(/\r\n/g, '\n');
let n = 0;
const ok = (c, m) => { assert.ok(c, m); n++; };

// ── 1. el bloque de la factura, ejecutado ──────────────────────────────────────────────────────────────────────────
const ini = src.indexOf("    if (facturaId) {\n      const { data: fv, error: eF } = await usuario.from('facturas')");
ok(ini > 0, 'no se encuentra el bloque que comprueba la factura antes de enviar');
const fin = src.indexOf('\n    }\n', ini);
const bloque = src.slice(ini, fin + 6);
const corre = new Function('usuario', 'json', 'facturaId',
  'return (async () => {\n' + bloque + '\n  return "sigue";\n})();');
const base = (fila, error = null) => {
  const pedido = {};
  return { pedido, usuario: { from(t) { pedido.tabla = t; return {
    select(c) { pedido.cols = c; return this; }, eq(k, v) { pedido.eq = [k, v]; return this; },
    async maybeSingle() { return { data: fila, error }; } }; } } };
};
const json = (o, s = 200) => ({ o, s });
(async () => {
  { const b = base({ id: 'f1', anulada: true });
    const r = await corre(b.usuario, json, 'f1');
    ok(r && r.s === 409 && r.o.ok === false && r.o.codigo === 'documento_anulado', 'anulada: 409 documento_anulado');
    ok(/anulado/.test(r.o.error) && !/_/.test(r.o.error), 'el error es una frase para la pantalla, no un código');
    ok(/\banulada\b/.test(b.pedido.cols) && b.pedido.tabla === 'facturas', 'lee `anulada` en la MISMA consulta (con la sesión del usuario)'); }
  ok((await corre(base({ id: 'f1', anulada: false }).usuario, json, 'f1')) === 'sigue', 'no anulada: sigue al envío');
  ok((await corre(base({ id: 'f1', anulada: null }).usuario, json, 'f1')) === 'sigue', 'anulada nula (histórico): sigue, como antes');
  { const r = await corre(base(null).usuario, json, 'f1'); ok(r.s === 403 && r.o.error === 'factura_no_visible', 'no visible: el 403 de siempre, sin decir si está anulada'); }
  { const r = await corre(base(null, { message: 'x' }).usuario, json, 'f1'); ok(r.s === 403, 'error de la consulta: 403, no se envía'); }
  ok((await corre(base({ id: 'f1', anulada: true }).usuario, json, null)) === 'sigue', 'sin factura (correo de contrato): no aplica');

  // ── 2. el orden dentro del manejador ─────────────────────────────────────────────────────────────────────────────
  const corte = src.indexOf("codigo: 'documento_anulado'");
  ok(corte > src.indexOf("error: 'solo_equipo' }, 403)"), 'el corte va después del gate de equipo');
  for (const [frag, que] of [["let pdfB64 = '';", 'del render'], ["'/render-pdf'", 'de la llamada a Railway'],
                             ["admin.storage.from('correos-enviados')", 'de la copia de prueba'],
                             ['const dest = await destinoEnvio(', 'del envío SMTP'], ["admin.from('correos_enviados').insert(", 'del registro de envíos'],
                             ["usuario.rpc('factura_marca_enviada'", 'de la marca']]) {
    const i = src.indexOf(frag);
    ok(i > 0 && corte < i, 'el corte va antes ' + que);
  }
  ok((src.match(/codigo: 'documento_anulado'/g) || []).length === 1, 'un solo corte');
  console.log('OK anulado.test.js — ' + n + ' comprobaciones: anulada corta con 409 y frase, no anulada/nula/no visible como antes, y el corte va antes de render, copia, SMTP, registro y marca');
})().catch((e) => { console.error(e); process.exit(1); });
