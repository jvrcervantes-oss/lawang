// Logos de las sociedades emisoras (Ajustes del ERP, S3, 30-sep-2026): funciones puras de la clase `sociedad_logo` de la edge
// `ficheros`, aparte para poder probarlas con node sin Deno ni base (logo.test.js).
// ⚠ Las importa la edge `ficheros`: si cambias este fichero, redespliega `ficheros`.
//
// El logo acaba en un <img src> de cada contrato y factura (y en el PDF que renderiza Chromium desde fuera), así que aquí se
// decide qué es un logo: PNG, JPEG o WebP por sus PRIMEROS BYTES —nunca por la extensión ni por el tipo que diga el navegador—,
// con tope de peso y de dimensiones. Un SVG (que lleva script), un GIF, un HTML con extensión .png o un fichero truncado no pasan.
// La base (`sociedad_guarda`) vuelve a comprobar que la URL guardada es del bucket para ESA clave: esto es la primera barrera.
import { dimsJpeg, esJpeg, hex } from './anexo.mjs';

export const TOPE_LOGO = 512 * 1024;        // = file_size_limit del bucket `sociedades`
export const LADO_MIN = 16;                 // px por lado: por debajo no es un logo, es un pixel de rastreo
export const LADO_MAX = 2000;               // px por lado: un logo de 4000 px pesa memoria en cada PDF
export { hex };

const RE_CLAVE = /^[a-z][a-z0-9_]{2,39}$/;  // la misma regla que sociedad_guarda
export const claveOk = (s) => RE_CLAVE.test(String(s ?? ''));

const asc = (b, i, n) => String.fromCharCode(...b.subarray(i, i + n));
const be32 = (b, i) => ((b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3]) >>> 0;
const le16 = (b, i) => b[i] | (b[i + 1] << 8);
const le24 = (b, i) => b[i] | (b[i + 1] << 8) | (b[i + 2] << 16);

// PNG: firma de 8 bytes y, justo detrás, el chunk IHDR (longitud 13) con ancho y alto.
export function dimsPng(b) {
  if (!b || b.length < 24) return null;
  const firma = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (!firma.every((x, i) => b[i] === x)) return null;
  if (be32(b, 8) !== 13 || asc(b, 12, 4) !== 'IHDR') return null;
  const ancho = be32(b, 16), alto = be32(b, 20);
  return ancho > 0 && alto > 0 ? { ancho, alto } : null;
}

// WebP: RIFF....WEBP y uno de los tres contenedores (VP8 con pérdida, VP8L sin pérdida, VP8X extendido).
export function dimsWebp(b) {
  if (!b || b.length < 30) return null;
  if (asc(b, 0, 4) !== 'RIFF' || asc(b, 8, 4) !== 'WEBP') return null;
  const chunk = asc(b, 12, 4);
  if (chunk === 'VP8 ') {
    if (!(b[23] === 0x9d && b[24] === 0x01 && b[25] === 0x2a)) return null;   // start code del frame
    const ancho = le16(b, 26) & 0x3fff, alto = le16(b, 28) & 0x3fff;
    return ancho > 0 && alto > 0 ? { ancho, alto } : null;
  }
  if (chunk === 'VP8L') {
    if (b[20] !== 0x2f) return null;                                          // firma del bitstream sin pérdida
    const bits = (b[21] | (b[22] << 8) | (b[23] << 16) | (b[24] << 24)) >>> 0;
    return { ancho: (bits & 0x3fff) + 1, alto: ((bits >>> 14) & 0x3fff) + 1 };
  }
  if (chunk === 'VP8X') return { ancho: le24(b, 24) + 1, alto: le24(b, 27) + 1 };
  return null;
}

// ¿Es un logo admitible? → {ext, mime, ancho, alto} o {error}. Los códigos de error los enseña la pantalla tal cual.
export function juzgaLogo(b) {
  if (!b || !b.length) return { error: 'logo_vacio' };
  if (b.length > TOPE_LOGO) return { error: 'logo_demasiado_grande' };
  let kind = null, d = null;
  if (b.length >= 8 && b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) { kind = { ext: 'png', mime: 'image/png' }; d = dimsPng(b); }
  else if (esJpeg(b)) { kind = { ext: 'jpg', mime: 'image/jpeg' }; d = dimsJpeg(b); }
  else if (b.length >= 12 && asc(b, 0, 4) === 'RIFF' && asc(b, 8, 4) === 'WEBP') { kind = { ext: 'webp', mime: 'image/webp' }; d = dimsWebp(b); }
  if (!kind) return { error: 'logo_tipo_no_admitido' };     // SVG, GIF, HTML, PDF… o un fichero que no es lo que dice
  if (!d) return { error: 'logo_ilegible' };                 // firma correcta pero cabecera rota o truncada
  if (d.ancho < LADO_MIN || d.alto < LADO_MIN) return { error: 'logo_demasiado_pequeno' };
  if (d.ancho > LADO_MAX || d.alto > LADO_MAX) return { error: 'logo_dimensiones_excesivas' };
  return { ...kind, ancho: d.ancho, alto: d.alto };
}

// Ruta dentro del bucket `sociedades`: la decide el servidor por el contenido (sha256), así el mismo logo no se duplica y
// una subida nunca pisa otra (el nombre cambia con el contenido). Devuelve null si la clave o el hash no cumplen.
export function rutaLogo(clave, sha256, ext) {
  if (!claveOk(clave) || !/^[0-9a-f]{64}$/.test(String(sha256 ?? '')) || !['png', 'jpg', 'webp'].includes(ext)) return null;
  return `${clave}/${sha256}.${ext}`;
}

// base64 → bytes, sin reventar la memoria con una cadena enorme: el tope se mira ANTES de decodificar.
export function decodificaB64(s) {
  const t = String(s ?? '').replace(/^data:[^,]*,/, '');
  if (!t || t.length > Math.ceil((TOPE_LOGO * 4) / 3) + 8) return null;
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(t) || t.length % 4 !== 0) return null;
  try {
    const bin = atob(t);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  } catch (_e) { return null; }
}
