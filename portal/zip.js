/* zip.js — empaquetar varios ficheros en un .zip dentro del navegador (7-oct-2026).
   Para «Descargar todo» de /portal/ → Documentos. Sin librería de terceros a propósito:
   el portal es la cara del cliente y no carga más código ajeno del imprescindible
   (ya carga supabase-js con SRI). Formato «store» (sin comprimir): los PDF y las
   imágenes ya vienen comprimidos y comprimirlos otra vez solo gasta CPU.
   La firma de fichero la fija el navegador del comprador, pero aquí no hay nada de
   confianza que proteger: solo se empaquetan ficheros que el servidor ya le sirvió
   con URL firmada.
   API: lwZip([{ name:'a.pdf', data: Uint8Array }]) → Uint8Array del .zip.
   Se prueba en node con zip.test.js (lo abre Python `zipfile`). */
(function (root) {
  var TABLA = null;
  function crc32(buf) {
    if (!TABLA) {
      TABLA = new Uint32Array(256);
      for (var n = 0; n < 256; n++) {
        var c = n;
        for (var k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
        TABLA[n] = c >>> 0;
      }
    }
    var crc = 0xFFFFFFFF;
    for (var i = 0; i < buf.length; i++) crc = TABLA[(crc ^ buf[i]) & 0xFF] ^ (crc >>> 8);
    return (crc ^ 0xFFFFFFFF) >>> 0;
  }
  function u16(v, n) { v.push(n & 0xFF, (n >>> 8) & 0xFF); }
  function u32(v, n) { v.push(n & 0xFF, (n >>> 8) & 0xFF, (n >>> 16) & 0xFF, (n >>> 24) & 0xFF); }
  function utf8(s) {
    if (typeof TextEncoder !== 'undefined') return new TextEncoder().encode(s);
    return Uint8Array.from(Buffer.from(s, 'utf8'));
  }
  function fechaDos(d) {
    var hora = (d.getHours() << 11) | (d.getMinutes() << 5) | (d.getSeconds() >> 1);
    var dia = ((d.getFullYear() - 1980) << 9) | ((d.getMonth() + 1) << 5) | d.getDate();
    return { hora: hora & 0xFFFF, dia: dia & 0xFFFF };
  }
  function lwZip(ficheros, ahora) {
    var f = fechaDos(ahora || new Date());
    var partes = [], central = [], desplaza = 0;
    ficheros.forEach(function (x) {
      var nombre = utf8(x.name), datos = x.data, crc = crc32(datos), cab = [];
      u32(cab, 0x04034B50); u16(cab, 20); u16(cab, 0x0800); u16(cab, 0);   // bit 11 = nombre UTF-8
      u16(cab, f.hora); u16(cab, f.dia); u32(cab, crc); u32(cab, datos.length); u32(cab, datos.length);
      u16(cab, nombre.length); u16(cab, 0);
      partes.push(Uint8Array.from(cab), nombre, datos);
      var c = [];
      u32(c, 0x02014B50); u16(c, 20); u16(c, 20); u16(c, 0x0800); u16(c, 0);
      u16(c, f.hora); u16(c, f.dia); u32(c, crc); u32(c, datos.length); u32(c, datos.length);
      u16(c, nombre.length); u16(c, 0); u16(c, 0); u16(c, 0); u16(c, 0); u32(c, 0); u32(c, desplaza);
      central.push(Uint8Array.from(c), nombre);
      desplaza += cab.length + nombre.length + datos.length;
    });
    var tamCentral = central.reduce(function (s, p) { return s + p.length; }, 0);
    var fin = [];
    u32(fin, 0x06054B50); u16(fin, 0); u16(fin, 0); u16(fin, ficheros.length); u16(fin, ficheros.length);
    u32(fin, tamCentral); u32(fin, desplaza); u16(fin, 0);
    var todo = partes.concat(central, [Uint8Array.from(fin)]);
    var total = todo.reduce(function (s, p) { return s + p.length; }, 0);
    var out = new Uint8Array(total), pos = 0;
    todo.forEach(function (p) { out.set(p, pos); pos += p.length; });
    return out;
  }
  if (typeof module !== 'undefined' && module.exports) module.exports = { lwZip: lwZip, crc32: crc32 };
  else root.lwZip = lwZip;
})(typeof window !== 'undefined' ? window : this);
