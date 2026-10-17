// 17-oct-2026 (revisión previa de Seguridad de «Reenviar todas», punto 1): con via:'enlace_firma' el correo solo sale al firmante
// de un enlace VIVO de ese contrato y con ESE enlace en el texto. Fija la regla EJECUTANDO motivoEnlaceFirmaNoVale contra una base
// falsa y el cableado leyendo la fuente. Corre con: node contracts/edge/send-contract-email/enlace_firma_destino.test.js
'use strict';
const fs = require('fs'), path = require('path'), assert = require('assert');
const raiz = path.join(__dirname, '..', '..', '..');
const leer = (...p) => fs.readFileSync(path.join(raiz, ...p), 'utf8').replace(/\r\n/g, '\n');
const src = leer('contracts', 'edge', 'send-contract-email', 'index.ts');
let n = 0;
const ok = (c, m) => { assert.ok(c, m); n++; };

function extrae(nombre) {
  const i = src.indexOf('async function ' + nombre);
  assert.ok(i >= 0, 'no se encuentra ' + nombre);
  const f = src.indexOf('\n}\n', i);
  return src.slice(i, f + 2)
    .replace(/\(contratoId: string, to: string, message: string\): Promise<string>/, '(contratoId, to, message)')
    .replace(/ as \{ firmante_email: string \| null; enlace_firma: string \| null \}\[\]/, '')
    .replace(/\(f\)/g, '(f)');
}
// base falsa: guarda los filtros y devuelve las filas que pase la prueba
function base(filas, error = null) {
  const q = { filtros: [] };
  const cadena = { select() { return cadena; }, eq(k, v) { q.filtros.push(['eq', k, v]); return cadena; },
    gt(k, v) { q.filtros.push(['gt', k, v]); return Promise.resolve({ data: filas, error }); } };
  return { q, admin: { from(t) { q.tabla = t; return cadena; } } };
}
const fabrica = (admin) => new Function('admin', extrae('motivoEnlaceFirmaNoVale') + '\nreturn motivoEnlaceFirmaNoVale;')(admin);
const LINK = 'https://lawangproperties.com/contracts/firmar.html?t=abc123';
const MSG = 'Hola Ana, aquí tienes el enlace para firmar: ' + LINK + '\n\nLawang';

(async () => {
  { const b = base([{ firmante_email: 'Ana@Cliente.test', enlace_firma: LINK }]);
    ok((await fabrica(b.admin)('c-1', ' ana@cliente.test ', MSG)) === '', 'el firmante del enlace vivo, con su enlace: vale (sin distinguir mayúsculas)');
    ok(b.q.tabla === 'contrato_firmas', 'lee contrato_firmas');
    ok(JSON.stringify(b.q.filtros.slice(0, 2)) === JSON.stringify([['eq', 'contrato_id', 'c-1'], ['eq', 'estado', 'pendiente']]), 'del contrato y pendiente');
    ok(b.q.filtros[2][0] === 'gt' && b.q.filtros[2][1] === 'expira_en', 'y no caducado'); }
  ok((await fabrica(base([{ firmante_email: 'ana@cliente.test', enlace_firma: LINK }]).admin)('c-1', 'otro@ataque.test', MSG)) === 'destinatario_no_es_el_firmante', 'a otra dirección: no');
  ok((await fabrica(base([]).admin)('c-1', 'ana@cliente.test', MSG)) === 'destinatario_no_es_el_firmante', 'sin enlace vivo: no');
  ok((await fabrica(base([{ firmante_email: 'ana@cliente.test', enlace_firma: LINK }]).admin)('c-1', 'ana@cliente.test', 'Paga aquí: IBAN ES00')) === 'mensaje_sin_el_enlace', 'sin el enlace en el texto: no');
  ok((await fabrica(base([{ firmante_email: 'ana@cliente.test', enlace_firma: null }]).admin)('c-1', 'ana@cliente.test', MSG)) === 'mensaje_sin_el_enlace', 'fila sin enlace guardado: no');
  ok((await fabrica(base([{ firmante_email: 'ana@cliente.test', enlace_firma: LINK + 'x' }, { firmante_email: 'luis@cliente.test', enlace_firma: LINK }]).admin)('c-1', 'ana@cliente.test', MSG)) === 'mensaje_sin_el_enlace',
    'el enlace de OTRO firmante no vale para Ana');
  ok((await fabrica(base(null, { message: 'boom' }).admin)('c-1', 'ana@cliente.test', MSG)) === 'no_se_pudo_comprobar', 'error al leer: no se envía');

  // cableado
  const cab = "if (via === 'enlace_firma' && contratoId) {";
  const i = src.indexOf(cab);
  ok(i > 0, 'el bloque existe');
  ok(i > src.indexOf("const { data: cv, error: eC } = await usuario.from('contratos')"), 'DESPUÉS de comprobar que el contrato es visible para quien envía');
  ok(i < src.indexOf("let pdfB64 = '';") && i < src.indexOf('encolaAvisoAnulacion(contratoId, to)'), 'y antes de enviar nada');
  const bloque = src.slice(i, src.indexOf('\n    }\n', i));
  ok(/const malo = await motivoEnlaceFirmaNoVale\(contratoId, to, message\);/.test(bloque), 'con el to y el texto que llegan');
  ok((bloque.match(/return json\(\{ ok: false, codigo: malo/g) || []).length === 3, 'cualquier motivo corta con ok:false');
  // el generador manda lo que esta regla pide
  const app = leer('contracts', 'app.html');
  ok(app.includes("FIRMA_ENVIO = { to:email, link:link };") && /ficheros\('envia_firma', Object\.assign\(\{ contrato_id: SAVED_CONTRACT\.id,\s*\n\s*nombre, email,/.test(app),
    'app.html: el destinatario es el email con el que se creó el enlace');
  ok(app.includes("if(FIRMA_ENVIO && msg.indexOf(FIRMA_ENVIO.link) === -1){ toastMal(lwT('El mensaje ya no incluye el enlace de firma')); return null; }"), 'y ya exige el enlace en el texto');
  console.log('OK enlace_firma_destino.test.js — ' + n + ' comprobaciones');
})().catch((e) => { console.error(e); process.exit(1); });
