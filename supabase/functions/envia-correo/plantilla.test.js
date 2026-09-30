/* node plantilla.test.js — la piel de Lawang de la edge envia-correo, lo que no necesita php ni Deno:
   1. cada recurso que el correo pide a lawangproperties.com EXISTE en este repo (si se borra una fuente o el grano, el
      correo sale sin ella y no da error: el correo ya enviado apunta a esas URL);
   2. el `contacto` que pide quien llama llega al pie por el index.ts real (vista previa y envío). */
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const RAIZ = path.join(__dirname, '..', '..', '..');

(async () => {
  const { plantillaHtml } = await import('./plantilla.ts');
  const html = plantillaHtml('Hola', '', null, '', { marca: 'L', dominio: 'lawangproperties.com', remitente: 'a@b.co' });
  const urls = [...new Set(html.match(/https:\/\/lawangproperties\.com\/assets\/[^'")\s]+/g))];
  assert.ok(urls.length >= 5, 'esperaba las 3 fuentes, el grano, el moanito y el logo: ' + urls.length);
  for (const u of urls) {
    const f = path.join(RAIZ, u.replace('https://lawangproperties.com/', ''));
    assert.ok(fs.existsSync(f), 'el correo pide ' + u + ' y no está en el repo: ' + f);
  }

  const A = await import('./arnes.mjs');
  const { reinicia, cargaEdge, llama, estado } = A;
  const H = (o) => ({ 'content-type': 'application/json', ...o });
  reinicia({ sesion: true });
  let m = await cargaEdge(__dirname);
  const pv = (extra) => llama(m, { cabeceras: H({ 'x-suite-token': 'jwt' }), cuerpo: { message: 'Hola', preview: true, ...extra } });
  let r = await pv({});
  assert.strictEqual(r.status, 200);
  assert.ok(r.cuerpo.html.includes('admin@ejemplo.com') && !r.cuerpo.html.includes('sales@'), 'vista previa: admin@ por defecto, del dominio_web');
  r = await pv({ contacto: 'sales' });
  assert.ok(r.cuerpo.html.includes('sales@ejemplo.com'), 'vista previa: contacto sales llega a la plantilla');
  r = await pv({ contacto: 'otro@evil.com' });
  assert.ok(r.cuerpo.html.includes('admin@ejemplo.com') && !r.cuerpo.html.includes('evil'), 'cualquier otro contacto se ignora: nunca una dirección libre');
  // envío real (sin adjunto) por la vía de sesión: HTML y texto plano llevan sales@
  await llama(m, { cabeceras: H({ 'x-suite-token': 'jwt' }), cuerpo: { to: 'ana@cliente.es', message: 'Hola', attach: false, contacto: 'sales' } });
  const c = estado.correo.correos[0];
  assert.ok(c && c.html.includes('sales@ejemplo.com') && c.text.includes('sales@ejemplo.com'), 'envío: sales@ en HTML y en texto');
  assert.ok(c.html.startsWith('<!DOCTYPE html>'), 'el correo sale como documento completo');
  console.log(`OK plantilla.test.js — ${urls.length} recursos del correo existen en el repo; contacto llega al pie (previa y envío)`);
})().catch((e) => { console.error(e); process.exit(1); });
