// AXW-127 (11-oct-2026): el 413 `pdf_demasiado_grande` de send-contract-email SOLO se enciende con
// config_instancia.copias_firmadas_modo = «cola» (decisión del owner, 1-oct: se despliega con la activación de la cola).
// Con «enlace» (lo de hoy), la clave ausente o ilegible, un PDF de más de 34 MB de base64 sigue al PHP, como la v25 desplegada.
// Fija la regla EJECUTANDO el interruptor, el corte y destinoEnvio contra una base falsa, y mirando el orden en la fuente.
// Corre con: node contracts/edge/send-contract-email/tope_cola.test.js
'use strict';
const fs = require('fs'), path = require('path'), assert = require('assert');
const src = fs.readFileSync(path.join(__dirname, 'index.ts'), 'utf8').replace(/\r\n/g, '\n');
let n = 0;
const ok = (c, m) => { assert.ok(c, m); n++; };

function extrae(firma) {
  const i = src.indexOf(firma);
  assert.ok(i >= 0, 'no se encuentra ' + firma);
  return src.slice(i, src.indexOf('\n}\n', i) + 2)
    .replace(/\(pdfLen: number\): Promise<\{ url: string; secreto: string \}>/, '(pdfLen)')
    .replace(/\(\): Promise<boolean>/, '()');
}
// base falsa: config_instancia con las claves que se le den; `rompe` = la consulta lanza
const base = (claves, rompe = false) => {
  const pedidas = [];
  return { pedidas, admin: { from(t) { const q = { t }; return {
    select() { return this; }, eq(k, v) { q[k] = v; return this; },
    async maybeSingle() { pedidas.push(q.clave); if (rompe) throw new Error('caida');
      return { data: q.clave in claves ? { valor: claves[q.clave] } : null, error: null }; } }; } } };
};
const URL_SB = 'https://x.supabase.co';
const ENVIO_EDGE = URL_SB + '/functions/v1/envia-correo';
const ENVIO_PHP = 'https://lawangproperties.com/contracts/api/send_email.php';
const TOPE_PDF_EDGE = 34 * 1024 * 1024;
const fabrica = (admin) => new Function('admin', 'Deno', 'ENVIO_PHP', 'ENVIO_EDGE', 'TOPE_PDF_EDGE', 'RENDER_SECRET',
  extrae('async function modoColaCopias') + '\n' + extrae('async function destinoEnvio') + '\nreturn { modoColaCopias, destinoEnvio };')(
  admin, { env: { get: () => 'sec-edge' } }, ENVIO_PHP, ENVIO_EDGE, TOPE_PDF_EDGE, 'sec-php');

// el corte, tal cual está en la fuente, como cuerpo ejecutable
const ini = src.indexOf('    if (pdfB64.length > TOPE_PDF_EDGE');
ok(ini > 0, 'no se encuentra el corte del 413');
const corte = src.slice(ini, src.indexOf('\n    }\n', ini) + 6);
const correCorte = (modoColaCopias, pdfLen) => new Function('pdfB64', 'TOPE_PDF_EDGE', 'modoColaCopias', 'json',
  'return (async () => {\n' + corte + '\n  return "sigue";\n})();')({ length: pdfLen }, TOPE_PDF_EDGE, modoColaCopias, (o, s) => ({ o, s }));

(async () => {
  const GRANDE = TOPE_PDF_EDGE + 1, NORMAL = 1000;
  // ── 1. el interruptor ─────────────────────────────────────────────────────────────────────────────────────────
  for (const [claves, rompe, esperado, que] of [
    [{ copias_firmadas_modo: 'cola' }, false, true, '«cola»'], [{ copias_firmadas_modo: 'enlace' }, false, false, '«enlace»'],
    [{}, false, false, 'clave ausente'], [{ copias_firmadas_modo: 'cola' }, true, false, 'consulta caída'],
    [{ copias_firmadas_modo: { modo: 'cola' } }, false, false, 'valor que no es el texto «cola»']]) {
    const b = base(claves, rompe);
    ok((await fabrica(b.admin).modoColaCopias()) === esperado, 'interruptor con ' + que + ' → ' + esperado);
    ok(b.pedidas[0] === 'copias_firmadas_modo', 'lee copias_firmadas_modo (' + que + ')');
  }
  // ── 2. el corte, en los dos modos ─────────────────────────────────────────────────────────────────────────────
  for (const modo of ['cola', 'enlace']) {
    const b = base({ copias_firmadas_modo: modo, url_envio_correo: ENVIO_EDGE });
    const f = fabrica(b.admin);
    const r = await correCorte(f.modoColaCopias, GRANDE);
    if (modo === 'cola') {
      ok(r && r.s === 413 && r.o.codigo === 'pdf_demasiado_grande' && r.o.ok === false, 'cola + PDF grande: 413 pdf_demasiado_grande');
      ok(/portal/.test(r.o.error) && !/_/.test(r.o.error), 'el 413 trae una frase para la pantalla, no un código');
    } else {
      ok(r === 'sigue', 'enlace + PDF grande: NO hay 413, sigue al envío (como la v25)');
      const d = await f.destinoEnvio(GRANDE);
      ok(d.url === ENVIO_PHP && d.secreto === 'sec-php', 'enlace + PDF grande: va al PHP con su secreto, aunque url_envio_correo apunte a la edge');
    }
    const b2 = base({ copias_firmadas_modo: modo });
    ok((await correCorte(fabrica(b2.admin).modoColaCopias, NORMAL)) === 'sigue', modo + ' + PDF normal: sigue');
    ok(b2.pedidas.length === 0, modo + ' + PDF normal: ni siquiera se consulta el interruptor');
  }
  { const b = base({ copias_firmadas_modo: 'cola' }, true);
    ok((await correCorte(fabrica(b.admin).modoColaCopias, GRANDE)) === 'sigue', 'interruptor ilegible + PDF grande: sigue al PHP (nunca un 413 por no poder leer)'); }
  { const d = await fabrica(base({ url_envio_correo: ENVIO_EDGE }).admin).destinoEnvio(NORMAL);
    ok(d.url === ENVIO_EDGE && d.secreto === 'sec-edge', 'PDF normal con url_envio_correo = edge: va a la edge (sin cambio)'); }
  // ── 3. el orden en la fuente ──────────────────────────────────────────────────────────────────────────────────
  const i413 = src.indexOf("codigo: 'pdf_demasiado_grande'");
  ok((src.match(/codigo: 'pdf_demasiado_grande'/g) || []).length === 1, 'un solo 413');
  ok(/if \(pdfB64\.length > TOPE_PDF_EDGE && await modoColaCopias\(\)\) \{/.test(src), 'el 413 exige PDF grande Y modo cola');
  ok(i413 < src.indexOf('const dest = await destinoEnvio(') && i413 < src.indexOf('await fetch(dest.url'), 'el 413 va antes del destino y del envío');
  ok(i413 < src.indexOf("admin.from('correos_enviados').insert("), 'el 413 va antes del registro de envíos');
  console.log('OK tope_cola.test.js — ' + n + ' comprobaciones: 413 solo con copias_firmadas_modo=«cola»; con «enlace»/ausente/ilegible el PDF grande sigue al PHP como la v25');
})().catch((e) => { console.error(e); process.exit(1); });
