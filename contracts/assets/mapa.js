/* ============================================================================
   Ubicación de un proyecto en Google Maps — FUENTE ÚNICA (8-oct-2026).

   `proyectos.ubicacion_maps` guarda lo que se pegó en «Editar proyecto»: unas
   coordenadas «lat, lng» (27 de los 33 proyectos el 8-oct) o un enlace de Google
   Maps. De ahí salen dos cosas: `abrir` (siempre que haya algo válido) y `embed`
   (solo si se pueden sacar coordenadas o un nombre de sitio — el enlace corto
   maps.app.goo.gl no las trae y el navegador no puede seguirlo: ese se queda en
   el botón).

   Vivía dentro de intranet/v4/assets/datos.js (mapaProyecto, 24-sep) con una copia
   en el investor deck. El portal del comprador solo aceptaba enlaces https, así que
   con coordenadas no salía «Ver en el mapa» en casi ningún proyecto (owner, 8-oct:
   «coge la localización de Google Maps de cada proyecto de la intranet»). Escrita
   aquí una vez para que las tres pantallas digan lo mismo del mismo proyecto.

   Sin módulos a propósito: HTML plano con <script> clásico.
   ========================================================================== */
function lwMapaUbicacion(texto, zoom) {
  var t = (typeof texto === 'string' ? texto : '').trim();
  if (!t) return null;
  var z = '&z=' + (zoom || 15) + '&output=embed';
  var m = t.match(/^(-?\d{1,2}(?:\.\d+)?)\s*[,;]\s*(-?\d{1,3}(?:\.\d+)?)$/);
  if (m) {
    var q = m[1] + ',' + m[2];
    return { abrir: 'https://www.google.com/maps?q=' + q, embed: 'https://maps.google.com/maps?q=' + q + z };
  }
  // El host tiene que TERMINAR en google.<país> o goo.gl: «google.evil.com» no es Google (revisor, 8-oct-2026).
  if (!/^https:\/\/([a-z0-9-]+\.)*(google\.(com|[a-z]{2}|co\.[a-z]{2}|com\.[a-z]{2})|goo\.gl)([\/?#]|$)/i.test(t)) return null;
  var c = t.match(/!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)/) || t.match(/@(-?\d+\.\d+),(-?\d+\.\d+)/) ||
          t.match(/[?&](?:q|ll|query|center)=(-?\d+\.\d+)(?:,|%2C)\s*(-?\d+\.\d+)/i);
  if (c) return { abrir: t, embed: 'https://maps.google.com/maps?q=' + c[1] + ',' + c[2] + z };
  var pl = t.match(/\/maps\/place\/([^/@?]+)/);
  if (pl) {
    try { return { abrir: t, embed: 'https://maps.google.com/maps?q=' + encodeURIComponent(decodeURIComponent(pl[1].replace(/\+/g, ' '))) + z }; } catch (e) {}
  }
  return { abrir: t, embed: null };
}

if (typeof module !== 'undefined' && module.exports) module.exports = { lwMapaUbicacion };
