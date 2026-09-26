/* node firma.test.js — la comprobación de bytes de los ficheros KYC (27-sep-2026, LAW-336 bloque 2).
   Un fichero que no es lo que dice su extensión no se registra y se borra del bucket. */
const assert = require('assert');
const path = require('path');
const { pathToFileURL } = require('url');

const b = (...xs) => {
  const out = new Uint8Array(16);
  let i = 0;
  xs.forEach((x) => {
    if (typeof x === 'string') for (const ch of x) out[i++] = ch.charCodeAt(0);
    else out[i++] = x;
  });
  return out;
};

import(pathToFileURL(path.join(__dirname, 'firma.mjs')).href).then(({ TIPOS, bytesCuadran }) => {
  const pdf = b('%PDF-1.7');
  const jpg = b(0xff, 0xd8, 0xff, 0xe0);
  const png = b(0x89, 'PNG', 0x0d, 0x0a, 0x1a, 0x0a);
  const webp = b('RIFF', 0, 0, 0, 0, 'WEBP');
  const heic = b(0, 0, 0, 0x18, 'ftypheic');
  const html = b('<html><script>');

  assert.ok(bytesCuadran('.pdf', pdf));
  assert.ok(bytesCuadran('.jpg', jpg) && bytesCuadran('.jpeg', jpg));
  assert.ok(bytesCuadran('.png', png));
  assert.ok(bytesCuadran('.webp', webp));
  assert.ok(bytesCuadran('.heic', heic) && bytesCuadran('.heif', heic));

  // lo que no es lo que dice ser
  assert.ok(!bytesCuadran('.pdf', html), 'un HTML con extensión .pdf no pasa');
  assert.ok(!bytesCuadran('.jpg', pdf), 'un PDF con extensión .jpg no pasa');
  assert.ok(!bytesCuadran('.png', jpg));
  assert.ok(!bytesCuadran('.webp', b('RIFF', 0, 0, 0, 0, 'WAVE')), 'un RIFF que no es WEBP no pasa');
  assert.ok(!bytesCuadran('.exe', pdf), 'extensión fuera de la lista no pasa');
  assert.ok(!bytesCuadran('.pdf', new Uint8Array(3)), 'un fichero de 3 bytes no pasa');
  assert.ok(!bytesCuadran('.pdf', null));

  // cada extensión admitida tiene su tipo, y el bucket admite exactamente esos tipos
  assert.deepStrictEqual(Object.keys(TIPOS).sort(), ['.heic', '.heif', '.jpeg', '.jpg', '.pdf', '.png', '.webp']);
  assert.deepStrictEqual([...new Set(Object.values(TIPOS))].sort(),
    ['application/pdf', 'image/heic', 'image/heif', 'image/jpeg', 'image/png', 'image/webp']);
  console.log('firma.test.js: ok');
}).catch((e) => { console.error(e); process.exit(1); });
