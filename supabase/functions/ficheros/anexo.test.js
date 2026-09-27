/* node anexo.test.js — las comprobaciones puras de la clase `anexo_contrato` de la edge `ficheros` (LAW-78).
   La ruta de una página la decide el servidor y la base la vuelve a mirar; aquí se fija la primera barrera:
   ruta anclada al contrato y a la página, sin `..`, y que lo subido sea un JPEG de verdad. */
const assert = require('assert');
const path = require('path');
const { pathToFileURL } = require('url');

(async () => {
  const m = await import(pathToFileURL(path.join(__dirname, 'anexo.mjs')).href);
  const C = '0f1e2d3c-4b5a-4968-8776-655443322110';
  const O = '11111111-2222-4333-8444-555555555555';
  const U = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';

  // rutas
  assert.strictEqual(m.rutaAnexo(C, 3, U), `${C}/${U}/3.jpg`);
  assert.strictEqual(m.rutaAnexo('no-uuid', 3, U), null);
  assert.strictEqual(m.rutaAnexo(C, 0, U), null);
  assert.ok(m.rutaAnexoOk(C, 3, `${C}/${U}/3.jpg`));
  assert.ok(!m.rutaAnexoOk(C, 4, `${C}/${U}/3.jpg`), 'la página de la ruta tiene que ser la pedida');
  assert.ok(!m.rutaAnexoOk(C, 3, `${O}/${U}/3.jpg`), 'ruta de otro contrato');
  assert.ok(!m.rutaAnexoOk(C, 3, `${C}/${U}/../${U}/3.jpg`), 'ruta con ..');
  assert.ok(!m.rutaAnexoOk(C, 3, `x/${C}/${U}/3.jpg`), 'prefijo delante');
  assert.ok(!m.rutaAnexoOk(C, 3, `${C}/${U}/3.jpg.png`), 'extensión doble');
  assert.ok(!m.rutaAnexoOk(C, 3, `${C}/${U}/3.JPG`), 'solo .jpg en minúsculas');
  assert.ok(!m.rutaAnexoOk(C + '.*', 3, `${C}/${U}/3.jpg`), 'un contrato con regex no cuela');

  // ids y páginas
  assert.ok(m.anexoIdOk('ax-' + U));
  assert.ok(m.anexoIdOk('ax12'));
  assert.ok(!m.anexoIdOk('ax/../x'));
  assert.ok(!m.anexoIdOk('otro'));
  assert.strictEqual(m.nPagina('7'), 7);
  assert.strictEqual(m.nPagina(501), 0);
  assert.strictEqual(m.nPagina(1.5), 0);

  // JPEG: magia y dimensiones de la cabecera SOF0
  const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x04, 0x4a, 0x46,
    0xff, 0xc0, 0x00, 0x11, 0x08, 0x04, 0x4c, 0x07, 0xd0, 0x03, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0xff, 0xd9]);
  assert.ok(m.esJpeg(jpeg));
  assert.deepStrictEqual(m.dimsJpeg(jpeg), { ancho: 2000, alto: 1100 });
  const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0]);
  assert.ok(!m.esJpeg(png));
  assert.strictEqual(m.dimsJpeg(png), null);
  assert.strictEqual(m.dimsJpeg(new Uint8Array([0xff, 0xd8, 0xff, 0xda, 0, 2, 0, 0, 0, 0, 0, 0])), null);
  assert.strictEqual(m.hex(new Uint8Array([0, 15, 255]).buffer), '000fff');
  console.log('anexo.test.js: OK');
})().catch((e) => { console.error(e); process.exit(1); });
