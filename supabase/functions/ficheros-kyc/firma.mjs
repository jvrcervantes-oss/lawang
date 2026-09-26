// ¿Un fichero KYC es lo que dice su extensión? Función pura, aparte de la edge para poder probarla sin
// Deno ni base: firma.test.js (27-sep-2026, LAW-336 bloque 2, revisor de código).

// Extensión → content-type. El navegador suele mandar un HEIC sin tipo y el bucket solo admite estos:
// la pantalla sube con el que devuelve la edge, no con el que trae el fichero.
export const TIPOS = {
  '.pdf': 'application/pdf', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png',
  '.webp': 'image/webp', '.heic': 'image/heic', '.heif': 'image/heif',
};

const MARCAS_HEIF = ['heic', 'heix', 'hevc', 'hevx', 'heim', 'heis', 'mif1', 'msf1'];

// Los primeros bytes (bastan 12) casan con la firma de su formato.
export function bytesCuadran(ext, b) {
  if (!b || b.length < 12) return false;
  const asc = (i, n) => String.fromCharCode(...b.subarray(i, i + n));
  switch (ext) {
    case '.pdf': return asc(0, 5) === '%PDF-';
    case '.jpg': case '.jpeg': return b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff;
    case '.png': return b[0] === 0x89 && asc(1, 3) === 'PNG';
    case '.webp': return asc(0, 4) === 'RIFF' && asc(8, 4) === 'WEBP';
    // ISO-BMFF: `ftyp` y la MARCA de imagen (sin ella pasaría un MP4/MOV, que es el mismo contenedor)
    case '.heic': case '.heif': return asc(4, 4) === 'ftyp' && MARCAS_HEIF.includes(asc(8, 4));
    default: return false;
  }
}

// ¿Se admite? Lo que dice la extensión, o —si es una imagen— cualquier imagen admitida: una captura PNG
// guardada como .jpg (WhatsApp, capturas) es un fichero legítimo con la extensión mal puesta. Un PDF tiene
// que ser un PDF (consulta de deploy, Desarrollo, 27-sep-2026).
export function esAdmisible(ext, b) {
  if (bytesCuadran(ext, b)) return true;
  if (ext === '.pdf' || !TIPOS[ext]) return false;
  return ['.jpg', '.png', '.webp', '.heic'].some((e) => bytesCuadran(e, b));
}
