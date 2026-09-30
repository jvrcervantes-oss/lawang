/* node logo.test.js — la primera barrera de la clase `sociedad_logo` de la edge `ficheros` (Ajustes del ERP, S3, 30-sep-2026).
   Un logo entra si SUS BYTES son un PNG, JPEG o WebP legible, de peso y tamaño razonables; nada se decide por la extensión ni por
   el tipo que declare el navegador. Y la ruta del bucket la compone el servidor con la clave y el sha256 del contenido. */
const assert = require('assert');
const path = require('path');
const { pathToFileURL } = require('url');

(async () => {
  const m = await import(pathToFileURL(path.join(__dirname, 'logo.mjs')).href);
  const enc = (s) => Uint8Array.from(Buffer.from(s, 'latin1'));

  // ── PNG mínimo válido (firma + IHDR) de w×h ────────────────────────────────────────────────────────────────
  function png(w, h, extra = 0) {
    const b = new Uint8Array(33 + extra);
    b.set([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52], 0);
    new DataView(b.buffer).setUint32(16, w); new DataView(b.buffer).setUint32(20, h);
    return b;
  }
  assert.deepStrictEqual(m.juzgaLogo(png(200, 100)), { ext: 'png', mime: 'image/png', ancho: 200, alto: 100 });
  assert.strictEqual(m.juzgaLogo(png(15, 100)).error, 'logo_demasiado_pequeno');
  assert.strictEqual(m.juzgaLogo(png(100, 15)).error, 'logo_demasiado_pequeno');
  assert.strictEqual(m.juzgaLogo(png(2001, 100)).error, 'logo_dimensiones_excesivas');
  assert.strictEqual(m.juzgaLogo(png(100, 4000)).error, 'logo_dimensiones_excesivas');
  assert.strictEqual(m.juzgaLogo(png(2000, 2000)).ancho, 2000, 'el borde exacto entra');
  assert.strictEqual(m.juzgaLogo(png(16, 16)).ancho, 16, 'el mínimo exacto entra');
  // firma de PNG sin IHDR detrás = cabecera rota
  const roto = png(100, 100); roto[12] = 0x58;
  assert.strictEqual(m.juzgaLogo(roto).error, 'logo_ilegible');
  const corto = png(100, 100).subarray(0, 20);
  assert.strictEqual(m.juzgaLogo(corto).error, 'logo_ilegible', 'PNG truncado');

  // ── JPEG con SOF0 ────────────────────────────────────────────────────────────────────────────────────────────
  const jpg = (w, h) => new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x04, 0x4a, 0x46,
    0xff, 0xc0, 0x00, 0x11, 0x08, h >> 8, h & 255, w >> 8, w & 255, 0x03, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xd9]);
  assert.deepStrictEqual(m.juzgaLogo(jpg(300, 120)), { ext: 'jpg', mime: 'image/jpeg', ancho: 300, alto: 120 });
  assert.strictEqual(m.juzgaLogo(jpg(5, 5)).error, 'logo_demasiado_pequeno');
  assert.strictEqual(m.juzgaLogo(new Uint8Array([0xff, 0xd8, 0xff, 0xda, 0, 2, 0, 0, 0, 0, 0, 0])).error, 'logo_ilegible');

  // ── WebP: los tres contenedores ─────────────────────────────────────────────────────────────────────────────
  function webpBase(chunk) {
    const b = new Uint8Array(40);
    b.set(enc('RIFF'), 0); b.set(enc('WEBP'), 8); b.set(enc(chunk), 12);
    return b;
  }
  const w8 = webpBase('VP8 '); w8.set([0x9d, 0x01, 0x2a], 23); w8[26] = 200; w8[27] = 0; w8[28] = 100; w8[29] = 0;
  assert.deepStrictEqual(m.juzgaLogo(w8), { ext: 'webp', mime: 'image/webp', ancho: 200, alto: 100 });
  const wl = webpBase('VP8L'); wl[20] = 0x2f; const bits = (199) | (99 << 14); wl[21] = bits & 255; wl[22] = (bits >> 8) & 255; wl[23] = (bits >> 16) & 255; wl[24] = (bits >>> 24) & 255;
  assert.deepStrictEqual(m.juzgaLogo(wl), { ext: 'webp', mime: 'image/webp', ancho: 200, alto: 100 });
  const wx = webpBase('VP8X'); wx[24] = 199; wx[27] = 99;
  assert.deepStrictEqual(m.juzgaLogo(wx), { ext: 'webp', mime: 'image/webp', ancho: 200, alto: 100 });
  const w8malo = webpBase('VP8 '); // sin start code
  assert.strictEqual(m.juzgaLogo(w8malo).error, 'logo_ilegible');
  const wraro = webpBase('XXXX');
  assert.strictEqual(m.juzgaLogo(wraro).error, 'logo_ilegible');

  // ── Lo que NO es un logo: se rechaza aunque venga con extensión o tipo de imagen ────────────────────────────
  for (const [que, bytes] of [
    ['SVG con script', enc('<svg xmlns="http://www.w3.org/2000/svg" onload="alert(1)"><script>alert(1)</script></svg>')],
    ['SVG con cabecera XML', enc('<?xml version="1.0"?><svg/>')],
    ['HTML con extensión .png', enc('<!doctype html><script>alert(1)</script>')],
    ['GIF', enc('GIF89a\x10\x00\x10\x00\x00\x00\x00;')],
    ['PDF', enc('%PDF-1.7\n%âãÏÓ')],
    ['ejecutable', enc('MZ\x90\x00\x03\x00\x00\x00')],
    ['ZIP', Uint8Array.from([0x50, 0x4b, 0x03, 0x04, 0, 0, 0, 0])],
    ['texto', enc('esto no es una imagen')],
    ['PNG con firma falsa (falta un byte)', Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0b, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, 0, 0, 0, 100, 0, 0, 0, 100, 0, 0, 0, 0, 0, 0, 0, 0, 0])],
  ]) {
    const r = m.juzgaLogo(bytes);
    assert.ok(r.error === 'logo_tipo_no_admitido' || r.error === 'logo_ilegible', que + ' → ' + JSON.stringify(r));
    assert.ok(!r.ext, que + ' no puede tener extensión');
  }
  assert.strictEqual(m.juzgaLogo(new Uint8Array(0)).error, 'logo_vacio');
  assert.strictEqual(m.juzgaLogo(null).error, 'logo_vacio');
  // peso: el tope exacto entra, un byte más no
  assert.strictEqual(m.juzgaLogo(png(100, 100, m.TOPE_LOGO - 33)).ext, 'png');
  assert.strictEqual(m.juzgaLogo(png(100, 100, m.TOPE_LOGO - 32)).error, 'logo_demasiado_grande');

  // ── Claves y rutas ───────────────────────────────────────────────────────────────────────────────────────────
  const H = 'ab'.repeat(32);
  assert.strictEqual(m.rutaLogo('tepi_sungai', H, 'png'), `tepi_sungai/${H}.png`);
  assert.strictEqual(m.rutaLogo('Mala Clave', H, 'png'), null);
  assert.strictEqual(m.rutaLogo('../x', H, 'png'), null, 'sin ..');
  assert.strictEqual(m.rutaLogo('a/b', H, 'png'), null, 'sin barras en la clave');
  assert.strictEqual(m.rutaLogo('ab', H, 'png'), null, 'clave corta');
  assert.strictEqual(m.rutaLogo('tepi_sungai', 'abc', 'png'), null, 'hash corto');
  assert.strictEqual(m.rutaLogo('tepi_sungai', H.toUpperCase(), 'png'), null, 'hash en minúsculas');
  assert.strictEqual(m.rutaLogo('tepi_sungai', H, 'svg'), null, 'jamás svg');
  assert.strictEqual(m.rutaLogo('tepi_sungai', H, 'gif'), null);
  assert.ok(m.claveOk('mi_empresa_sa') && !m.claveOk('MiEmpresa') && !m.claveOk('1abc') && !m.claveOk(''));
  assert.strictEqual(m.hex(new Uint8Array([1, 171, 255]).buffer), '01abff');

  // ── base64 ───────────────────────────────────────────────────────────────────────────────────────────────────
  const b64 = Buffer.from(png(50, 50)).toString('base64');
  assert.deepStrictEqual(Array.from(m.decodificaB64(b64)), Array.from(png(50, 50)));
  assert.deepStrictEqual(Array.from(m.decodificaB64('data:image/png;base64,' + b64)), Array.from(png(50, 50)), 'admite el prefijo data:');
  assert.strictEqual(m.decodificaB64(''), null);
  assert.strictEqual(m.decodificaB64('no es base64!'), null);
  assert.strictEqual(m.decodificaB64('abc'), null, 'longitud no múltiplo de 4');
  assert.strictEqual(m.decodificaB64('A'.repeat(Math.ceil(m.TOPE_LOGO * 4 / 3) + 100)), null, 'cadena enorme: se rechaza antes de decodificar');

  console.log('logo.test.js: OK');
})().catch((e) => { console.error(e); process.exit(1); });
