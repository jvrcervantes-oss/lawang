// Páginas de anexo de contrato (LAW-78, 27-sep-2026): funciones puras de la clase `anexo_contrato` de la edge
// `ficheros`, aparte para poder probarlas con node sin Deno ni base (anexo.test.js).
// ⚠ Las importa la edge `ficheros`: si cambias este fichero, redespliega `ficheros`.

// La base (contrato_anexo_registra) vuelve a comprobar todo esto contra la FILA del contrato: esto es la primera
// barrera, no la única.
export const TOPE_PAGINA = 3 * 1024 * 1024;   // = file_size_limit del bucket contratos-anexos
const UUID = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
const RE_UUID = new RegExp('^' + UUID + '$');
const RE_ANEXO = /^ax[-0-9A-Za-z]{1,60}$/;

export const esUuid = (s) => RE_UUID.test(String(s ?? ''));
export const anexoIdOk = (s) => RE_ANEXO.test(String(s ?? ''));
// número de página 1..500 (el mismo CHECK que la tabla); 0 = no vale
export function nPagina(v) {
  const n = Number(v);
  return Number.isInteger(n) && n >= 1 && n <= 500 ? n : 0;
}

// La ruta la decide el servidor: `<contrato>/<uuid nuevo>/<n>.jpg`. Una carpeta por página, así una subida nunca
// pisa otra (el bucket no admite sobrescribir y la URL firmada va sin upsert).
export function rutaAnexo(contrato, n, uuid) {
  if (!esUuid(contrato) || !nPagina(n) || !esUuid(uuid)) return null;
  return `${contrato}/${uuid}/${nPagina(n)}.jpg`;
}
// ¿Esta ruta es una de las que genera rutaAnexo para ESE contrato y ESA página? Anclada: sin `..`, sin prefijos.
export function rutaAnexoOk(contrato, n, path) {
  if (!esUuid(contrato) || !nPagina(n)) return false;
  return new RegExp('^' + contrato + '/' + UUID + '/' + nPagina(n) + '\\.jpg$').test(String(path ?? ''));
}

export const esJpeg = (b) => !!b && b.length >= 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff;

// Ancho y alto de un JPEG leyendo su cabecera SOFn: los mide el servidor, no se cree los de la pantalla.
// null si no se encuentran (la columna los admite nulos: son informativos).
export function dimsJpeg(b) {
  if (!esJpeg(b)) return null;
  let i = 2;
  while (i + 9 < b.length) {
    if (b[i] !== 0xff) { i++; continue; }
    const m = b[i + 1];
    if (m === 0xff) { i++; continue; }                         // relleno
    if (m === 0xd8 || m === 0x01 || (m >= 0xd0 && m <= 0xd7)) { i += 2; continue; }  // sin longitud
    if (m === 0xd9 || m === 0xda) return null;                 // fin o datos de imagen sin SOF antes
    const len = (b[i + 2] << 8) | b[i + 3];
    // SOF0..SOF15 salvo DHT (C4), JPG (C8) y DAC (CC)
    if (m >= 0xc0 && m <= 0xcf && m !== 0xc4 && m !== 0xc8 && m !== 0xcc) {
      const alto = (b[i + 5] << 8) | b[i + 6];
      const ancho = (b[i + 7] << 8) | b[i + 8];
      return ancho > 0 && alto > 0 ? { ancho, alto } : null;
    }
    if (len < 2) return null;
    i += 2 + len;
  }
  return null;
}

export function hex(buf) {
  return [...new Uint8Array(buf)].map((x) => x.toString(16).padStart(2, '0')).join('');
}
