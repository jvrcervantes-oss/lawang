// AXW-124 (S5.0 F4, 30-sep-2026): fija la regla de la «red» de envío de firma-submit leyendo su fuente.
// Una excepción de fetch no distingue «no conectó» de «se cortó tras enviar»: reintentar por ahí duplicaría el correo
// de una firma. Solo un HTTP 401/404 (antes del SMTP) puede caer al PHP. Corre con: node contracts/edge/firma-submit/red_envio.test.js
'use strict';
const fs = require('fs'), path = require('path'), assert = require('assert');
const dir = __dirname;
const src = fs.readFileSync(path.join(dir, 'index.ts'), 'utf8').replace(/\r\n/g, '\n');
const espejo = fs.readFileSync(path.join(dir, '..', '..', '..', 'supabase', 'functions', 'firma-submit', 'index.ts'), 'utf8').replace(/\r\n/g, '\n');
assert.strictEqual(src, espejo, 'contracts/edge y supabase/functions de firma-submit han divergido');

// 1. los estados de la red son exactamente 401 y 404
const m = /const RED_ESTADOS = \[([^\]]*)\];/.exec(src);
assert.ok(m, 'no se encuentra RED_ESTADOS');
assert.deepStrictEqual(m[1].split(',').map((x) => x.trim()), ['401', '404'], 'la red solo admite 401 y 404');

// 2. la red mira r.status y no el cuerpo, y solo actúa cuando el destino era la edge
assert.ok(/if \(url === ENVIO_EDGE && RED_ESTADOS\.includes\(r\.status\)\)/.test(src), 'la red debe depender de status y de que el destino fuera la edge');
// 3. exactamente UN reintento por el PHP y ningún try/catch que reenvíe ante excepción
assert.strictEqual((src.match(/r = await postCorreo\(ENVIO_PHP/g) || []).length, 1, 'un solo reintento por el PHP');
const cuerpoEnviar = src.slice(src.indexOf('async function enviarEmail'), src.indexOf('const b64 = '));
assert.ok(!/catch\s*\(/.test(cuerpoEnviar.replace(/\.catch\(\(\) => ''\)/g, '')), 'enviarEmail no debe capturar excepciones de fetch para reenviar');
// 4. cada uso de la red deja huella medible
assert.ok(/console\.error\('red_envio_usada fn=firma-submit status='/.test(src), 'falta el log red_envio_usada');
// 5. el interruptor solo acepta la URL exacta de la edge (sin startsWith) y el secreto nuevo solo va a ella
assert.ok(/if \(u === ENVIO_EDGE\) return u;/.test(src) && !/startsWith\(/.test(cuerpoEnviar), 'comparación exacta de la URL');
assert.ok(/url === ENVIO_EDGE\s*\? await postCorreo\(url, Deno\.env\.get\('ENVIO_CORREO_SECRET'\)/.test(src), 'ENVIO_CORREO_SECRET solo hacia la edge');
assert.ok(/: await postCorreo\(ENVIO_PHP, RENDER_SECRET, cuerpo\)/.test(src), 'al PHP solo RENDER_SECRET');
// 6. el mayor adjunto cabe en la edge: MAX_ADJUNTO en base64 ≤ 34 MB (LIMITES.pdfBase64 de envia-correo)
const ma = /const MAX_ADJUNTO = (\d+) \* 1024 \* 1024;/.exec(src);
assert.ok(ma, 'no se encuentra MAX_ADJUNTO');
const valida = fs.readFileSync(path.join(dir, '..', '..', '..', 'supabase', 'functions', 'envia-correo', 'valida.ts'), 'utf8');
const lp = /pdfBase64:\s*(\d+)\s*\*\s*1024\s*\*\s*1024/.exec(valida);
assert.ok(lp, 'no se encuentra LIMITES.pdfBase64');
assert.ok(Number(ma[1]) * 1024 * 1024 * 4 / 3 <= Number(lp[1]) * 1024 * 1024, 'MAX_ADJUNTO en base64 supera el tope de la edge');
console.log('OK red_envio.test.js — red solo 401/404, un reintento, sin captura de excepciones, secreto solo a la edge, adjunto máximo cabe en la edge');
