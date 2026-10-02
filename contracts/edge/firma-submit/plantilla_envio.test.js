// S5.3 (2-oct-2026): comportamiento REAL de enviarEmail() de firma-submit con la clave piloto `enlace_firma_cadena`, con fetch y
// base simulados (se extrae la función de la fuente .ts y se ejecuta). Fija: envío por plantilla (sin subject/message ni vars),
// caída UNA vez al camino libre solo ante 400/502 de la edge, nunca tras timeout/excepción ni 2xx, convivencia con la red 401/404,
// y que correos_enviados guarda plantilla+versión y jamás el texto (lleva el token del enlace, LAW-343).
// Corre con: node contracts/edge/firma-submit/plantilla_envio.test.js
'use strict';
const fs = require('fs'), path = require('path'), assert = require('assert');
const { stripTypeScriptTypes } = require('module');
const src = fs.readFileSync(path.join(__dirname, 'index.ts'), 'utf8').replace(/\r\n/g, '\n');

const EDGE = 'https://ref.supabase.co/functions/v1/envia-correo';
const PHP = 'https://lawangproperties.com/contracts/api/send_email.php';
const TOKEN = 'TOKENSECRETO123';
const MSG = 'Hola Ana, aquí tienes el enlace para firmar: https://lawangproperties.com/contracts/firmar.html?t=' + TOKEN;
const PLANT = { clave: 'enlace_firma_cadena', contrato_id: 'c-1', firma_id: 'f-1' };

function carga(fuente) {
  const ini = fuente.indexOf('const ENVIO_PHP'), fin = fuente.indexOf('const b64 = ');
  assert.ok(ini > 0 && fin > ini, 'no se encuentra el bloque de envío');
  const js = stripTypeScriptTypes(fuente.slice(ini, fin));
  return new Function('sb', 'Deno', 'fetch', 'RENDER_SECRET', 'console', js + '\nreturn enviarEmail;');
}
// respuestas: cola de {status, body} o 'timeout' (fetch lanza)
function escenario(fuente, urlConfig, respuestas) {
  const llamadas = [], logs = [], inserts = [];
  const sb = { from: (t) => ({
    select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: { valor: urlConfig } }) }) }),
    insert: async (fila) => { inserts.push({ t, fila }); return { error: null }; },
  }) };
  const Deno = { env: { get: (k) => (k === 'SUPABASE_URL' ? 'https://ref.supabase.co' : k === 'ENVIO_CORREO_SECRET' ? 'secreto-edge' : null) } };
  const cola = respuestas.slice();
  const fetchFalso = async (url, init) => {
    llamadas.push({ url, body: JSON.parse(init.body), h: init.headers });
    const r = cola.shift();
    if (!r) throw new Error('petición inesperada a ' + url);
    if (r === 'timeout') throw new Error('The operation was aborted due to timeout');
    return { status: r.status, ok: r.status >= 200 && r.status < 300, text: async () => r.body };
  };
  const consola = { error: (...a) => logs.push(a.join(' ')) };
  const enviarEmail = carga(fuente)(sb, Deno, fetchFalso, 'secreto-render', consola);
  return { enviarEmail, llamadas, logs, inserts };
}
const base = { to: 'ana@x.com', subject: 'Documento para firmar · LW-1', message: MSG, log: { contrato_id: 'c-1', via: 'enlace_firma' }, plantilla: PLANT };
const ok = (extra) => ({ status: 200, body: JSON.stringify({ ok: true, ...extra }) });

(async () => {
  // 1. envío por plantilla OK: una sola petición, sin subject/message/vars; registro con plantilla+versión y SIN texto
  let e = escenario(src, EDGE, [ok({ plantilla: 'enlace_firma_cadena', version: 'f:ab12cd34' })]);
  await e.enviarEmail(base);
  assert.strictEqual(e.llamadas.length, 1);
  assert.deepStrictEqual(e.llamadas[0].body, { to: 'ana@x.com', plantilla: 'enlace_firma_cadena', contrato_id: 'c-1', firma_id: 'f-1', attach: false });
  assert.strictEqual(e.llamadas[0].h['X-Render-Secret'], 'secreto-edge');
  assert.strictEqual(e.inserts.length, 1);
  const fila = e.inserts[0].fila;
  assert.strictEqual(fila.plantilla, 'enlace_firma_cadena'); assert.strictEqual(fila.plantilla_version, 'f:ab12cd34');
  assert.strictEqual(fila.contrato_id, 'c-1'); assert.strictEqual(fila.via, 'enlace_firma');
  assert.ok(!('mensaje' in fila), 'el registro no debe llevar mensaje');
  assert.ok(!JSON.stringify(fila).includes(TOKEN), 'ningún campo del registro lleva el token');
  assert.ok(!e.logs.some((l) => l.includes('plantilla_caida')));

  // 2. caída 400 y 502: UNA vez al camino libre (a la edge, con subject/message), log plantilla_caida, registro SIN plantilla
  for (const st of [400, 502]) {
    e = escenario(src, EDGE, [{ status: st, body: '{"error":"x"}' }, ok()]);
    await e.enviarEmail(base);
    assert.strictEqual(e.llamadas.length, 2, st + ': dos peticiones');
    assert.ok('plantilla' in e.llamadas[0].body && !('subject' in e.llamadas[0].body));
    assert.strictEqual(e.llamadas[1].url, EDGE);
    assert.strictEqual(e.llamadas[1].body.subject, base.subject); assert.strictEqual(e.llamadas[1].body.message, MSG);
    assert.ok(!('plantilla' in e.llamadas[1].body));
    assert.ok(e.logs.includes('plantilla_caida fn=firma-submit plantilla=enlace_firma_cadena status=' + st), st + ': log plantilla_caida');
    assert.ok(!('plantilla' in e.inserts[0].fila) && !('plantilla_version' in e.inserts[0].fila), 'tras caer no se registra plantilla');
  }

  // 3. la caída es UNA sola vez: si el camino libre también da 400/502 se lanza, sin tercera petición
  e = escenario(src, EDGE, [{ status: 400, body: 'a' }, { status: 502, body: 'b' }]);
  await assert.rejects(() => e.enviarEmail(base), /email a ana@x.com/);
  assert.strictEqual(e.llamadas.length, 2);

  // 4. timeout/excepción en la petición con plantilla: NO se reintenta (podría haber salido el correo)
  e = escenario(src, EDGE, ['timeout', ok()]);
  await assert.rejects(() => e.enviarEmail(base), /timeout/);
  assert.strictEqual(e.llamadas.length, 1, 'tras timeout no hay segunda petición');
  assert.strictEqual(e.inserts.length, 0);

  // 5. 429, 500 y 503 no caen al camino libre (no se sabe si salió)
  for (const st of [429, 500, 503]) {
    e = escenario(src, EDGE, [{ status: st, body: 'x' }, ok()]);
    await assert.rejects(() => e.enviarEmail(base));
    assert.strictEqual(e.llamadas.length, 1, st + ' no cae');
  }

  // 6. red 401/404: la petición con plantilla cae al PHP con el camino LIBRE (el PHP no conoce plantillas), una vez, con red_envio_usada
  for (const st of [401, 404]) {
    e = escenario(src, EDGE, [{ status: st, body: 'x' }, ok()]);
    await e.enviarEmail(base);
    assert.strictEqual(e.llamadas.length, 2);
    assert.strictEqual(e.llamadas[1].url, PHP); assert.strictEqual(e.llamadas[1].h['X-Render-Secret'], 'secreto-render');
    assert.strictEqual(e.llamadas[1].body.message, MSG); assert.ok(!('plantilla' in e.llamadas[1].body));
    assert.ok(e.logs.includes('red_envio_usada fn=firma-submit status=' + st));
    assert.ok(!e.logs.some((l) => l.includes('plantilla_caida')));
    assert.ok(!('plantilla' in e.inserts[0].fila));
  }

  // 7. 400 con plantilla y luego 401 en el camino libre: la red sigue funcionando (3 peticiones: edge, edge, PHP)
  e = escenario(src, EDGE, [{ status: 400, body: 'a' }, { status: 401, body: 'b' }, ok()]);
  await e.enviarEmail(base);
  assert.deepStrictEqual(e.llamadas.map((l) => l.url), [EDGE, EDGE, PHP]);

  // 8. interruptor en el PHP (vuelta atrás): no se manda `plantilla` al PHP, camino libre y registro sin plantilla
  e = escenario(src, PHP, [ok()]);
  await e.enviarEmail(base);
  assert.strictEqual(e.llamadas.length, 1); assert.strictEqual(e.llamadas[0].url, PHP);
  assert.ok(!('plantilla' in e.llamadas[0].body)); assert.strictEqual(e.llamadas[0].body.message, MSG);
  assert.ok(!('plantilla' in e.inserts[0].fila));

  // 9. sin `plantilla` (los demás llamantes) el comportamiento es el de siempre
  const { plantilla, ...sinPlantilla } = base;
  e = escenario(src, EDGE, [ok()]);
  await e.enviarEmail(sinPlantilla);
  assert.strictEqual(e.llamadas[0].body.message, MSG); assert.ok(!('plantilla' in e.inserts[0].fila));

  // 10. el llamante pide la plantilla con los ids que la edge exige y el insert devuelve el id de la firma
  assert.ok(/\.select\('id'\)\.single\(\);\s*\n\s*if \(insSig\.error\)/.test(src), 'el insert de contrato_firmas debe devolver su id');
  assert.ok(/plantilla: \{ clave: 'enlace_firma_cadena', contrato_id: claimed\.contrato_id, firma_id: insSig\.data\.id \}/.test(src), 'el llamante pasa clave + contrato_id + firma_id');

  // 11. LA GUARDA IMPORTA: sin ella (una captura que reenvía ante excepción) el caso 4 se pone en ROJO
  const viva = "let r = url === ENVIO_EDGE\n    ? await postCorreo(url, Deno.env.get('ENVIO_CORREO_SECRET') || RENDER_SECRET, cuerpoPlantilla ?? cuerpo)";
  const sec = "Deno.env.get('ENVIO_CORREO_SECRET') || RENDER_SECRET";
  const mutada = src.replace(viva, "let r: any; try { r = await postCorreo(url, " + sec + ", cuerpoPlantilla ?? cuerpo); } catch (_) { r = await postCorreo(url, " + sec + ", cuerpo); }\n  const _x = url === ENVIO_EDGE\n    ? 0");
  assert.notStrictEqual(mutada, src, 'la mutación no se aplicó: el caso del timeout no está vigilando nada');
  e = escenario(mutada, EDGE, ['timeout', ok()]);
  await e.enviarEmail(base).catch(() => {});
  assert.strictEqual(e.llamadas.length, 2, 'con la guarda quitada el timeout SÍ reintenta (el caso 4 se pondría en rojo)');

  console.log('OK plantilla_envio.test.js — plantilla OK, caída 400/502 una vez, timeout/429/500/503 no reintentan, red 401/404 intacta, registro plantilla+versión sin texto, mutación detectada');
})().catch((err) => { console.error(err); process.exit(1); });
