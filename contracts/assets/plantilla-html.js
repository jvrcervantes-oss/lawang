/* Plantillas de contrato del ERP: pintar, comparar y detectar campos (28-sep-2026, subtarea 6b de
   encargos/20260926_estudio_erp_clientes_contratos_productos.md). Funciones PURAS, sin DOM: las usa la
   pantalla /intranet/v4/plantillas/ y las va a usar el generador de contratos al pintar una plantilla de la
   base (subtarea 6c) — por eso nacen aquí y no dentro de la pantalla (Regla 0 de contexto/suite_lawang.md).

   QUIÉN MANDA. La barrera es la base: el trigger de plantilla_contrato_versiones RECHAZA (no limpia) cualquier
   cuerpo con una etiqueta o un atributo fuera de su lista blanca (plantilla_html_problemas, migración
   erp/migraciones/20260928190000). Esto es la SEGUNDA barrera, al pintar: lo que salga de aquí solo lleva
   etiquetas que este fichero construye él mismo, con los atributos que él mismo copia. La lista de etiquetas
   repite la de la base A PROPÓSITO: si divergen, lo peor que pasa es que una etiqueta que la base admite se
   vea como texto en la vista previa — nunca al revés, porque la base es la que decide qué se guarda.
   Y la vista previa va además en un iframe `sandbox=""` con CSP `default-src 'none'`: tres capas.

   Por qué un tokenizador y no DOMParser: tiene que correr igual en node (test) y en el navegador, y hace
   exactamente lo que hace la base (misma expresión de etiqueta), así que lo que la base aprueba se pinta
   igual que se validó. */

var LW_PLANTILLA_ETIQUETAS = ['p', 'br', 'h1', 'h2', 'h3', 'h4', 'strong', 'b', 'em', 'i', 'u', 'ul', 'ol', 'li',
  'table', 'thead', 'tbody', 'tfoot', 'tr', 'th', 'td', 'div', 'span', 'section', 'hr', 'sup', 'sub', 'blockquote'];
var LW_PLANTILLA_VACIAS = ['br', 'hr'];
/* Los tipos de campo que la base admite (plantilla_campos_problemas), con su nombre para la persona. */
var LW_PLANTILLA_TIPOS_CAMPO = [['texto', 'Texto corto'], ['texto_largo', 'Texto largo'], ['numero', 'Número'],
  ['importe', 'Importe'], ['fecha', 'Fecha'], ['email', 'Email']];

function lwPlantillaEscapa(s) {
  return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

/* Texto entre etiquetas: `<` y `>` sueltos van como entidad. El `&` se deja: una entidad (&amp;, &nbsp;) es texto
   y no abre nada. */
function lwPlantillaTexto_(s) { return s.replace(/</g, '&lt;').replace(/>/g, '&gt;'); }

/* HTML → HTML con solo la lista blanca. Una etiqueta no admitida se ENSEÑA como texto (la persona ve qué tiene
   que quitar), nunca se interpreta. Atributos: `class` con letras, cifras, espacio, `_` y `-`; `colspan` y
   `rowspan` de 1-2 cifras. Todo lo demás (on*, style, href, src…) no se copia. */
function lwPlantillaSanea(html) {
  var s = String(html == null ? '' : html);
  var re = /<\s*(\/?)\s*([A-Za-z][A-Za-z0-9]*)([^<>]*)>/g;
  var out = '', ultimo = 0, m;
  while ((m = re.exec(s))) {
    out += lwPlantillaTexto_(s.slice(ultimo, m.index));
    ultimo = re.lastIndex;
    var cierre = !!m[1], tag = m[2].toLowerCase(), attrs = m[3] || '';
    if (LW_PLANTILLA_ETIQUETAS.indexOf(tag) === -1) { out += lwPlantillaEscapa(m[0]); continue; }
    if (cierre) { if (LW_PLANTILLA_VACIAS.indexOf(tag) === -1) out += '</' + tag + '>'; continue; }
    var a = '';
    var mc = /(?:^|\s)class\s*=\s*(?:"([A-Za-z0-9_ -]*)"|'([A-Za-z0-9_ -]*)')/.exec(attrs);
    if (mc) a += ' class="' + (mc[1] != null ? mc[1] : mc[2]) + '"';
    var rs = /(?:^|\s)(colspan|rowspan)\s*=\s*(?:"([0-9]{1,2})"|'([0-9]{1,2})'|([0-9]{1,2})(?![0-9]))/gi, mr, vistos = {};
    while ((mr = rs.exec(attrs))) {
      var k = mr[1].toLowerCase();
      if (vistos[k]) continue;
      vistos[k] = 1;
      a += ' ' + k + '="' + (mr[2] || mr[3] || mr[4]) + '"';
    }
    out += '<' + tag + a + '>';
  }
  return out + lwPlantillaTexto_(s.slice(ultimo));
}

/* Las claves {{así}} del cuerpo, sin repetir y en el orden en que salen. Misma forma que exige la base. */
function lwPlantillaCamposUsados(html) {
  var re = /\{\{\s*([a-z][a-z0-9_]{0,47})\s*\}\}/g, m, out = [];
  var s = String(html == null ? '' : html);
  while ((m = re.exec(s))) if (out.indexOf(m[1]) === -1) out.push(m[1]);
  return out;
}

/* Etiqueta por defecto de un campo detectado: «nombre_comprador» → «Nombre comprador». La persona la cambia. */
function lwPlantillaEtiquetaDe(clave) {
  var t = String(clave || '').replace(/_+/g, ' ').trim();
  return t ? t.charAt(0).toUpperCase() + t.slice(1) : '';
}

/* Documento entero para el `srcdoc` de la vista previa. Cada {{campo}} se pinta como una marca con su
   ETIQUETA escapada (lo que ve quien rellena el contrato); uno sin declarar se marca en rojo, igual que lo va a
   rechazar la base. `campos`: [{clave, etiqueta}]. */
function lwPlantillaVistaPrevia(html, campos) {
  var etq = {};
  (campos || []).forEach(function (c) { if (c && c.clave) etq[c.clave] = c.etiqueta || c.clave; });
  var cuerpo = lwPlantillaSanea(html).replace(/\{\{\s*([a-z][a-z0-9_]{0,47})\s*\}\}/g, function (_, k) {
    return Object.prototype.hasOwnProperty.call(etq, k)
      ? '<span class="lw-campo" title="{{' + k + '}}">' + lwPlantillaEscapa(etq[k]) + '</span>'
      : '<span class="lw-campo lw-sin" title="Campo sin declarar">{{' + k + '}} · sin declarar</span>';
  });
  return '<!DOCTYPE html><html lang="es"><head><meta charset="utf-8">' +
    '<meta http-equiv="Content-Security-Policy" content="default-src \'none\'; style-src \'unsafe-inline\'">' +
    '<style>body{margin:0;padding:28px 32px;font:15px/1.6 Georgia,\'Times New Roman\',serif;color:#1c1b17;background:#fff}' +
    'h1,h2,h3,h4{font-family:inherit;line-height:1.25}table{border-collapse:collapse;width:100%}' +
    'th,td{border:1px solid #d6d2c8;padding:6px 8px;vertical-align:top}' +
    '.lw-campo{display:inline-block;padding:0 6px;border-radius:4px;background:#e6efe9;color:#104C4F;' +
    'font:600 12px/1.6 system-ui,sans-serif;border:1px dashed #104C4F}' +
    '.lw-campo.lw-sin{background:#ffdad6;color:#93000a;border-color:#93000a}</style></head><body>' +
    cuerpo + '</body></html>';
}

/* Líneas para comparar. Un cuerpo de HTML suele venir en UNA línea: se corta tras cada cierre de bloque para que
   el diff diga «cambió esta cláusula» y no «cambió todo». */
function lwPlantillaLineas_(s) {
  return String(s == null ? '' : s).replace(/\r\n?/g, '\n')
    .replace(/(<\/(?:p|h[1-4]|li|tr|table|thead|tbody|tfoot|ul|ol|div|section|blockquote)\s*>|<br\s*\/?>|<hr\s*\/?>)/gi, '$1\n')
    .split('\n').map(function (l) { return l.replace(/\s+$/, ''); }).filter(function (l) { return l.trim() !== ''; });
}

/* Diff por líneas (LCS) entre `antes` (la versión activa) y `ahora` (el borrador). Devuelve
   {iguales, lineas:[{op:' '|'-'|'+', t}], aproximado}. Lo común del principio y del final se recorta antes (lo
   normal es cambiar una cláusula); si lo que queda en medio es enorme, no se calcula el LCS y se dice
   (`aproximado`: todo lo del medio sale como quitado y añadido). */
function lwPlantillaDiff(antes, ahora, tope) {
  var a = lwPlantillaLineas_(antes), b = lwPlantillaLineas_(ahora);
  var ini = 0;
  while (ini < a.length && ini < b.length && a[ini] === b[ini]) ini++;
  var fa = a.length, fb = b.length;
  while (fa > ini && fb > ini && a[fa - 1] === b[fb - 1]) { fa--; fb--; }
  var out = [], i, j;
  for (i = 0; i < ini; i++) out.push({ op: ' ', t: a[i] });
  var ma = a.slice(ini, fa), mb = b.slice(ini, fb), n = ma.length, m = mb.length, aproximado = false;
  if (n * m > (tope || 4000000)) {
    aproximado = true;
    ma.forEach(function (t) { out.push({ op: '-', t: t }); });
    mb.forEach(function (t) { out.push({ op: '+', t: t }); });
  } else if (n || m) {
    var L = [];
    for (i = 0; i <= n; i++) L.push(new Uint32Array(m + 1));
    for (i = n - 1; i >= 0; i--) for (j = m - 1; j >= 0; j--)
      L[i][j] = ma[i] === mb[j] ? L[i + 1][j + 1] + 1 : Math.max(L[i + 1][j], L[i][j + 1]);
    i = 0; j = 0;
    while (i < n && j < m) {
      if (ma[i] === mb[j]) { out.push({ op: ' ', t: ma[i] }); i++; j++; }
      else if (L[i + 1][j] >= L[i][j + 1]) out.push({ op: '-', t: ma[i++] });
      else out.push({ op: '+', t: mb[j++] });
    }
    while (i < n) out.push({ op: '-', t: ma[i++] });
    while (j < m) out.push({ op: '+', t: mb[j++] });
  }
  for (i = fa; i < a.length; i++) out.push({ op: ' ', t: a[i] });
  return { iguales: !out.some(function (l) { return l.op !== ' '; }), lineas: out, aproximado: aproximado };
}

if (typeof module !== 'undefined' && module.exports)
  module.exports = { LW_PLANTILLA_ETIQUETAS, LW_PLANTILLA_TIPOS_CAMPO, lwPlantillaEscapa, lwPlantillaSanea,
                     lwPlantillaCamposUsados, lwPlantillaEtiquetaDe, lwPlantillaVistaPrevia, lwPlantillaDiff };
