/* textos-contrato-nucleo.js — la parte PURA de la pantalla «Textos de contrato» (/intranet/v4/textos-contrato/), 8-oct-2026.
   Encargo «plantillas de contrato por empresa», S7 (encargos/20261007_lawang_plantillas_por_empresa.md). Sin DOM, sin red: corre igual en el navegador
   y en node (textos-contrato.test.js). La pantalla vive en textos-contrato.js.

   QUIÉN MANDA. El navegador NO valida nada: lo que decide si un texto se guarda o se activa es la base (validador S3, bloques fijos F2, bloqueo F1, quién
   puede activar). Todo lo de aquí es AYUDA para escribir: partir el texto en trozos editables, avisar antes de pulsar, enseñar la diferencia entre dos
   versiones y pintar una simulación. Si esta ayuda y la base discrepan, gana la base y la pantalla enseña su mensaje tal cual (con textContent).

   QUÉ SE EDITA. Solo TEXTO: cada «trozo» es un nodo de texto del documento (lo que hay entre dos etiquetas). La estructura, los estilos, las imágenes y los
   comentarios del motor no se tocan jamás: el documento nuevo se construye por REEMPLAZO LITERAL de esos trozos sobre el original, y lo que no se editó queda
   byte a byte igual (la prueba lo comprueba con las 20 plantillas). Los marcadores {{campo}} dentro de un trozo no se pueden quitar ni cambiar desde aquí. */
(function (raiz) {
  'use strict';

  var TC = {};

  /* ── texto ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────── */
  TC.esc = function (s) {
    return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  };
  /* Espacio en blanco como lo cuenta la base (_plantilla_ws): solo el ASCII. \s de JS incluye el espacio duro y la base no lo colapsa. */
  var WS = '[ \\t\\n\\r\\f\\v]';
  var WS_RE = new RegExp(WS + '+', 'g');
  TC.ws = function (s) { return String(s == null ? '' : s).replace(WS_RE, ' ').replace(new RegExp('^' + WS + '+|' + WS + '+$', 'g'), ''); };

  /* Entidades que la base admite en un texto (S3). Se muestran como el carácter y se devuelven a su forma al guardar. */
  var ENT = { nbsp: ' ', quot: '"', amp: '&', gt: '>', apos: "'", ldquo: '“', rdquo: '”', lsquo: '‘', rsquo: '’', ndash: '–',
              mdash: '—', hellip: '…', laquo: '«', raquo: '»', middot: '·', euro: '€' };
  var ENT_RE = /&(?:([a-z]+)|#x27|#39);/g;
  TC.decodifica = function (raw) {
    return String(raw).replace(ENT_RE, function (m, n) {
      if (n === undefined) return "'";                      // &#x27; y &#39;
      return Object.prototype.hasOwnProperty.call(ENT, n) ? ENT[n] : m;
    });
  };
  /* Inversa para lo que se escribe: solo lo imprescindible. `<` no se puede escribir (la base rechaza &lt; y cualquier forma de abrir una etiqueta). */
  TC.codifica = function (txt) {
    return String(txt).replace(/&/g, '&amp;').replace(/>/g, '&gt;').replace(/ /g, '&nbsp;');
  };

  var MARC_RE = /\{\{[a-z0-9_]+\}\}/g;
  TC.marcadores = function (txt) { return String(txt).match(MARC_RE) || []; };
  /* Caracteres que la base rechaza en crudo: controles, bidireccionales (Trojan Source), ancho cero, guion blando, BOM. */
  var INVISIBLES = /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f­​-‏‪-‮⁠⁦-⁩﻿]/;

  /* Avisos de lo que se acaba de escribir en un trozo (el servidor dice la última palabra). `original` = el texto del trozo antes de tocarlo. */
  /* Los marcadores que el trozo tenía y ya no tiene (con multiplicidad). La pantalla los nombra en llano; la base lo comprueba igualmente. */
  TC.faltanMarcadores = function (nuevo, original) {
    var antes = TC.marcadores(original), ahora = TC.marcadores(nuevo).slice(), faltan = [];
    antes.forEach(function (m) { var i = ahora.indexOf(m); if (i === -1) faltan.push(m.slice(2, -2)); else ahora.splice(i, 1); });
    return faltan;
  };
  /* `sinFaltan` = true: no incluir el aviso de marcadores perdidos (la pantalla lo redacta ella con las etiquetas en llano, usando faltanMarcadores). */
  TC.avisosTrozo = function (nuevo, original, sinFaltan) {
    var av = [];
    if (nuevo.indexOf('<') !== -1) av.push('No se puede escribir el signo «<»: la estructura del documento no se toca desde aquí.');
    if (INVISIBLES.test(nuevo)) av.push('Hay un carácter invisible o de control (ancho cero, dirección del texto…): no se admite.');
    var sinMarc = nuevo.replace(MARC_RE, '');
    if (/[{}]/.test(sinMarc)) av.push('Una llave suelta: los marcadores se escriben {{asi}}, en minúsculas, sin espacios.');
    var faltan = sinFaltan ? [] : TC.faltanMarcadores(nuevo, original).map(function (k) { return '{{' + k + '}}'; });
    if (faltan.length) av.push('Faltan marcadores que este trozo tenía: ' + faltan.join(' ') + '. Los marcadores no se quitan ni se cambian: los rellena el contrato.');
    return av;
  };

  /* ── el documento en trozos ───────────────────────────────────────────────────────────────────────────────────────────────────── */
  var VACIAS = { br: 1, img: 1, hr: 1, meta: 1, link: 1, input: 1, base: 1, col: 1, wbr: 1 };
  var BLOQUES = { p: 1, li: 1, td: 1, th: 1, h1: 1, h2: 1, h3: 1, h4: 1, div: 1, blockquote: 1, section: 1 };
  var OMITE = { style: 1, title: 1, script: 1, head: 1 };
  var TOKEN_RE = /<!--[\s\S]*?-->|<\/?[A-Za-z][^<>]*>|<![^<>]*>|<\?[^<>]*>|[^<]+|</g;

  /* Parte el documento en nodos de texto con su idioma (el data-lang más cercano), su bloque (el párrafo, celda o título que lo contiene) y su posición exacta.
     Devuelve { trozos: [...], bloques: n }. Un trozo: { i, ini, fin, raw, lead, core, trail, texto, lang, bloque, editable, bloqueado }. */
  TC.trocea = function (doc) {
    var trozos = [], pila = [], omite = 0, nBloque = 0, m, pos = 0;
    TOKEN_RE.lastIndex = 0;
    while ((m = TOKEN_RE.exec(doc)) !== null) {
      var t = m[0], ini = m.index, fin = ini + t.length;
      if (t.charAt(0) === '<') {
        if (t.slice(0, 4) === '<!--' || t.charAt(1) === '!' || t.charAt(1) === '?' || t === '<') continue;
        var cierre = t.charAt(1) === '/';
        var nm = /^<\/?([A-Za-z][A-Za-z0-9]*)/.exec(t)[1].toLowerCase();
        if (cierre) {
          for (var k = pila.length - 1; k >= 0; k--) {
            if (pila[k].n === nm) { pila.length = k; omite = pila.filter(function (e) { return OMITE[e.n]; }).length; break; }
          }
        } else if (!VACIAS[nm] && !/\/\s*>$/.test(t)) {
          var lg = /\sdata-lang="(es|en|id)"/.exec(t);
          var padre = pila.length ? pila[pila.length - 1] : null;
          var el = { n: nm, lang: lg ? lg[1] : (padre ? padre.lang : null), bloque: padre ? padre.bloque : 0 };
          if (BLOQUES[nm]) el.bloque = ++nBloque;
          if (OMITE[nm]) omite++;
          pila.push(el);
        }
        continue;
      }
      if (omite > 0 || !/[^ \t\n\r\f\v]/.test(t)) continue;
      var arriba = pila.length ? pila[pila.length - 1] : null;
      var lead = /^[ \t\n\r\f\v]*/.exec(t)[0], trail = /[ \t\n\r\f\v]*$/.exec(t)[0];
      var core = t.slice(lead.length, t.length - trail.length);
      var texto = TC.decodifica(core);
      trozos.push({ i: trozos.length, ini: ini, fin: fin, raw: t, lead: lead, core: core, trail: trail, texto: texto,
                    lang: arriba ? arriba.lang : null, bloque: arriba ? arriba.bloque : 0,
                    /* Un trozo que es solo un marcador o puntuación ({{fecha_firma}}, « · », «—») es parte del marcado: no se edita. */
                    editable: /[A-Za-z0-9À-ɏЀ-ӿ]/.test(texto.replace(MARC_RE, '')), bloqueado: false });
    }
    return { trozos: trozos, bloques: nBloque };
  };

  /* Los bloques que una empresa no cambia sola, localizados en el documento. `lista` = lo que dice la base (plantilla_contrato_edicion.bloques_fijos): textos
     normalizados con el prefijo E| (un elemento), S| (una sección entera desde su <h2>) o M| (una región marcada por Legal). Aquí solo se SITÚAN esos textos en
     el documento para pintarlos en solo lectura; que se respeten lo impone la base al guardar. Devuelve { spans: [[ini,fin],…], sinLocalizar: n }. */
  TC.situaBloquesFijos = function (doc, lista) {
    var set = {}, total = 0, spans = [], hallados = {};
    (lista || []).forEach(function (x) { if (!set[x]) total++; set[x] = true; });
    if (!total) return { spans: [], sinLocalizar: 0 };
    function toca(clave, a, b) { if (set[clave]) { spans.push([a, b, clave.charAt(0) === 'M' ? clave.split('|')[1] : clave.charAt(0)]); hallados[clave] = true; } }
    ['p', 'li', 'td', 'th', 'h1', 'h2', 'h3', 'h4'].forEach(function (tg) {
      var re = new RegExp('<' + tg + '(?: [^>]*)?>(?:(?!</' + tg + '>)[\\s\\S])*</' + tg + '>', 'g'), m;
      while ((m = re.exec(doc)) !== null) toca('E|' + TC.ws(m[0]), m.index, m.index + m[0].length);
    });
    var pos = [], i = -1;
    while ((i = doc.indexOf('<h2', i + 1)) !== -1) pos.push(i);
    pos.forEach(function (a, k) { var b = k + 1 < pos.length ? pos[k + 1] : doc.length; toca('S|' + TC.ws(doc.slice(a, b)), a, b); });
    var rm = /<!--bloque-fijo:([a-z0-9_]+)-->((?:(?!<!--\/bloque-fijo:)[\s\S])*)<!--\/bloque-fijo:\1-->/g, mm;
    while ((mm = rm.exec(doc)) !== null) toca('M|' + mm[1] + '|' + TC.ws(mm[2]), mm.index, mm.index + mm[0].length);
    return { spans: spans, sinLocalizar: total - Object.keys(hallados).length };
  };
  TC.marcaBloqueados = function (trozos, spans, todo) {
    var n = 0;
    trozos.forEach(function (t) {
      var dentro = spans.filter(function (s) { return t.ini >= s[0] && t.fin <= s[1]; });
      t.bloqueado = !!todo || dentro.length > 0;
      /* De qué clase es el candado: el nombre de la región marcada por Legal (M), o E (un elemento) / S (una sección entera). Sirve para decir el motivo. */
      t.fijo = dentro.length ? (dentro.filter(function (s) { return s[2].length > 1; })[0] || dentro[0])[2] : null;
      if (t.bloqueado && t.editable) n++;
    });
    return n;
  };

  /* El documento nuevo: el original con SOLO los trozos tocados sustituidos (conservando el blanco de alrededor). `cambios` = { i: textoNuevo }. */
  TC.construye = function (doc, trozos, cambios) {
    var out = '', cur = 0;
    trozos.forEach(function (t) {
      if (!Object.prototype.hasOwnProperty.call(cambios, t.i)) return;
      out += doc.slice(cur, t.ini) + t.lead + TC.codifica(cambios[t.i]) + t.trail;
      cur = t.fin;
    });
    return out + doc.slice(cur);
  };

  /* ── secciones: el índice del documento ───────────────────────────────────────────────────────────────────────────────────────── */
  /* Cada <h2> abre una cláusula; lo que hay antes del primero es el encabezado (sección 0). Marca `sec` en cada trozo (y `titulo` si es parte del propio título)
     y devuelve los títulos por sección e idioma. Es solo lectura del documento: construye() no sabe nada de esto. */
  TC.secciones = function (doc, trozos) {
    var h2 = [], re = /<h2(?:\s[^>]*)?>[\s\S]*?<\/h2>/gi, m;
    while ((m = re.exec(doc)) !== null) h2.push([m.index, m.index + m[0].length]);
    var titulos = [{}];
    h2.forEach(function () { titulos.push({}); });
    trozos.forEach(function (t) {
      var k = 0;
      for (var j = 0; j < h2.length; j++) { if (h2[j][0] <= t.ini) k = j + 1; else break; }
      t.sec = k; t.titulo = false;
      if (k > 0 && t.ini < h2[k - 1][1]) {
        var l = t.lang || 'general';
        titulos[k][l] = (titulos[k][l] ? titulos[k][l] + ' ' : '') + t.texto;
        t.titulo = true;
      }
    });
    return { n: h2.length + 1, titulos: titulos };
  };

  /* Un texto partido en trozos de texto y marcadores, para pintarlo sin tocar HTML: [{ m: false, v: 'texto' } | { m: true, k: 'fecha_firma' }]. */
  TC.segmentos = function (txt) {
    var out = [], last = 0, m, re = /\{\{([a-z0-9_]+)\}\}/g;
    txt = String(txt == null ? '' : txt);
    while ((m = re.exec(txt)) !== null) {
      if (m.index > last) out.push({ m: false, v: txt.slice(last, m.index) });
      out.push({ m: true, k: m[1] });
      last = m.index + m[0].length;
    }
    if (last < txt.length) out.push({ m: false, v: txt.slice(last) });
    return out;
  };

  /* Lo que se escribió en un trozo editable → el texto que se guarda. `piezas` = lo que el navegador tiene dentro del trozo, ya reducido a
     [{ t: 'txt', v } | { t: 'marca', k } | { t: 'otro', v }] (una pieza 'otro' es cualquier cosa que el navegador haya colado: solo cuenta su TEXTO, nunca su marcado).
     Reglas: espacio duro → espacio normal salvo que el original lo tuviera (el navegador los mete al teclear dos espacios seguidos); espacios colapsados como los
     cuenta la base (_plantilla_ws). Si queda igual que el original (salvo espacio en blanco), devuelve el original: no hay cambio fantasma. */
  TC.textoEscrito = function (piezas, original) {
    var s = (piezas || []).map(function (p) { return p.t === 'marca' ? '{{' + p.k + '}}' : String(p.v == null ? '' : p.v); }).join('');
    if (String(original).indexOf(' ') === -1) s = s.replace(/ /g, ' ');
    s = s.replace(/[\r\n]+/g, ' ');
    if (TC.ws(s) === TC.ws(original)) return original;
    return TC.ws(s);
  };

  /* ── etiquetas de los marcadores, en llano ───────────────────────────────────────────────────────────────────────────────────── */
  /* Casi todos salen de contracts/tokens.json (la pantalla lo lee, no se copia aquí: una lista a mano en dos sitios ES el bug). Estos son los que el motor
     deriva y tokens.json no lista: el test contra las 20 plantillas falla si aparece uno sin etiqueta. */
  TC.ETIQUETAS_EXTRA = {
    adq1_domicilio: 'Domicilio del comprador', adq1_registro_num: 'Número de registro del comprador', adq2_firmante_nombre: 'Nombre de quien firma por el comprador II',
    c2_adq1_domicilio: 'Domicilio del comprador I', c2_adq1_domicilio_id: 'Domicilio del comprador I (en indonesio)', c2_adq1_email: 'Email del comprador I',
    c2_adq1_pasaporte: 'Pasaporte del comprador I', c2_adq1_telefono: 'Teléfono del comprador I', c2_adq2_domicilio: 'Domicilio del comprador II',
    c2_adq2_domicilio_id: 'Domicilio del comprador II (en indonesio)', c2_adq2_email: 'Email del comprador II', c2_adq2_pasaporte: 'Pasaporte del comprador II',
    c2_adq2_telefono: 'Teléfono del comprador II', c2_rep_npwp: 'NPWP del representante', carta_cobrado_importe: 'Importe ya cobrado de la carta de reserva',
    carta_cobrado_numeros: 'Número de la carta de reserva cobrada', cc00014_ktp: 'KTP del titular de la cuenta', comp_domicilio: 'Domicilio de la sociedad compradora',
    comp_nib: 'NIB de la sociedad compradora', comp_npwp: 'NPWP de la sociedad compradora', comp_razon: 'Razón social de la sociedad compradora',
    cov_t: 'Título de la portada', cov_t_id: 'Título de la portada (en indonesio)', fecha_solicitud: 'Fecha de la solicitud', firma_adquiriente: 'Firma del comprador',
    jurisdiccion: 'Jurisdicción', precio_lista_construccion: 'Precio de lista de la construcción', precio_lista_suelo: 'Precio de lista del suelo',
    prom_cred_en: 'Cargo del representante de la promotora (en inglés)', prom_cred_es: 'Cargo del representante de la promotora', prom_cred_id: 'Cargo del representante de la promotora (en indonesio)',
    prom_domicilio: 'Domicilio de la promotora', prom_ktp: 'KTP del representante de la promotora', prom_marca: 'Marca registrada de la promotora', prom_nib: 'NIB de la promotora',
    prom_npwp: 'NPWP de la promotora', prom_razon: 'Razón social de la promotora', prom_rep: 'Representante de la promotora', prom_rep_npwp: 'NPWP del representante de la promotora',
    techo_nombre: 'Tipo de techo', unidad_construccion_codigo: 'Código de la unidad en construcción'
  };
  /* `campos` = { clave: etiqueta } ya sacada de tokens.json por la pantalla (TC.etiquetasDeTokens). Sin etiqueta se vuelve legible la clave: nunca se enseña «prom_razon». */
  TC.etiquetaMarcador = function (k, campos) {
    if (campos && campos[k]) return campos[k];
    if (TC.ETIQUETAS_EXTRA[k]) return TC.ETIQUETAS_EXTRA[k];
    var txt = String(k).split('_').filter(Boolean).join(' ');
    return txt.charAt(0).toUpperCase() + txt.slice(1);
  };
  /* tokens.json → { clave: etiqueta corta } en el idioma pedido (es por defecto). «Nombre (opcional — ...)» → «Nombre». */
  TC.etiquetasDeTokens = function (tokens, idioma) {
    var out = {};
    ((tokens && tokens.sections) || []).forEach(function (sec) {
      (sec.fields || []).forEach(function (f) {
        var l = f[1] && (f[1][idioma] || f[1].es); if (!l) return;
        var corto = String(l).replace(/\s*[(—–].*$/, '').replace(/\s*[:.]+$/, '').trim();
        if (corto) out[f[0]] = corto;
      });
    });
    return out;
  };

  /* ── lo que contesta la base, en llano ───────────────────────────────────────────────────────────────────────────────────────── */
  /* Clasifica un mensaje de la base por su PRINCIPIO (estable: el test lee las migraciones y falla si uno cambia). La pantalla pone la frase en llano
     y deja el mensaje tal cual debajo, como detalle. Devuelve { tipo, detalle }. */
  TC.PREFIJOS_BASE = [
    ['sesion', /^Sin sesion/i], ['solo_global', /^Este texto no lo cambia una empresa sola/], ['bloque_fijo', /^Tu texto cambia un bloque que una empresa no edita sola/],
    ['marcador_desconocido', /^marcador desconocido \{\{/], ['marcador_forma', /^marcador con forma no permitida/], ['llave', /^llave suelta o marcador mal cerrado/],
    ['esqueleto', /^el esqueleto cambia:/], ['motivo', /^Falta el motivo del cambio/], ['permiso', /^El texto de los contratos de una empresa lo escribe su administracion/],
    ['activar_super', /^Activar un texto de contrato lo hace el super administrador/], ['caracter', /^caracter (de control|bidireccional)/], ['grande', /^(El texto supera el tope|cuerpo demasiado grande)/],
    ['no_activable', /^Version no activable/]
  ];
  TC.clasificaError = function (msg) {
    var m = String(msg == null ? '' : msg).trim();
    for (var i = 0; i < TC.PREFIJOS_BASE.length; i++) if (TC.PREFIJOS_BASE[i][1].test(m)) return { tipo: TC.PREFIJOS_BASE[i][0], detalle: m };
    return { tipo: 'otro', detalle: m };
  };
  /* El marcador que nombra un error del validador («marcador desconocido {{x}}: …») → 'x', o null. */
  TC.marcadorDeError = function (msg) {
    var m = /\{\{([^{}]{1,40})\}\}/.exec(String(msg == null ? '' : msg)); return m ? m[1] : null;
  };

  /* ── qué cambió respecto a la versión de la que se parte (para «falta revisar» y «solo lo que he cambiado») ──────────────────────── */
  /* Compara trozo a trozo (misma posición) el documento de partida con el actual, con los cambios aún sin guardar aplicados. Si el número de trozos no
     coincide no se inventa nada: devuelve null y la pantalla lo dice. Devuelve { trozo: { i: true }, sec: { 'sec|lang': true } }. */
  TC.cambiosRespecto = function (trozosBase, trozos, cambios) {
    if (!trozosBase || trozosBase.length !== trozos.length) return null;
    var porTrozo = {}, porSec = {};
    trozos.forEach(function (t, i) {
      var ahora = Object.prototype.hasOwnProperty.call(cambios || {}, t.i) ? cambios[t.i] : t.texto;
      if (TC.ws(ahora) !== TC.ws(trozosBase[i].texto)) { porTrozo[t.i] = true; porSec[t.sec + '|' + (t.lang || 'general')] = true; }
    });
    return { trozo: porTrozo, sec: porSec };
  };
  /* Una cláusula está «por revisar» en un idioma si se ha cambiado en otro y en este no. */
  TC.porRevisar = function (cambiosSec, sec, lang, idiomas) {
    if (cambiosSec[sec + '|' + lang]) return false;
    return (idiomas || []).some(function (l) { return l !== lang && cambiosSec[sec + '|' + l]; });
  };

  /* ── comparar dos versiones ───────────────────────────────────────────────────────────────────────────────────────────────────── */
  /* El texto legible de un documento, un trozo por línea (con su idioma): lo que se compara y se enseña. */
  TC.lineas = function (doc) {
    return TC.trocea(doc).trozos.filter(function (t) { return t.editable || /[^\s]/.test(t.texto.replace(MARC_RE, '')); })
      .map(function (t) { return (t.lang ? '[' + t.lang + '] ' : '') + TC.ws(t.texto); });
  };
  /* Diferencias línea a línea (subsecuencia común más larga sobre lo que queda tras quitar el principio y el final iguales). Devuelve
     [{ t: '=' | '+' | '-', s }]. Con textos enormes y muy distintos cae a «todo cambió» en vez de colgar la pestaña. */
  TC.diff = function (a, b) {
    var i = 0, ea = a.length, eb = b.length;
    while (i < ea && i < eb && a[i] === b[i]) i++;
    while (ea > i && eb > i && a[ea - 1] === b[eb - 1]) { ea--; eb--; }
    var ma = ea - i, mb = eb - i, ops = [], k;
    for (k = 0; k < i; k++) ops.push({ t: '=', s: a[k] });
    if (ma * mb > 25000000) {
      for (k = i; k < ea; k++) ops.push({ t: '-', s: a[k] });
      for (k = i; k < eb; k++) ops.push({ t: '+', s: b[k] });
    } else {
      var w = mb + 1, tabla = new Uint32Array((ma + 1) * w), x, y;
      for (x = ma - 1; x >= 0; x--) for (y = mb - 1; y >= 0; y--) {
        tabla[x * w + y] = a[i + x] === b[i + y] ? tabla[(x + 1) * w + y + 1] + 1 : Math.max(tabla[(x + 1) * w + y], tabla[x * w + y + 1]);
      }
      x = 0; y = 0;
      while (x < ma && y < mb) {
        if (a[i + x] === b[i + y]) { ops.push({ t: '=', s: a[i + x] }); x++; y++; }
        else if (tabla[(x + 1) * w + y] >= tabla[x * w + y + 1]) { ops.push({ t: '-', s: a[i + x] }); x++; }
        else { ops.push({ t: '+', s: b[i + y] }); y++; }
      }
      for (; x < ma; x++) ops.push({ t: '-', s: a[i + x] });
      for (; y < mb; y++) ops.push({ t: '+', s: b[i + y] });
    }
    for (k = ea; k < a.length; k++) ops.push({ t: '=', s: a[k] });
    return ops;
  };

  /* ── simulación ───────────────────────────────────────────────────────────────────────────────────────────────────────────────── */
  /* Valores ficticios para pintar un documento sin ningún dato de un contrato real. Se elige por el nombre del marcador; si ninguno casa, se enseña el nombre. */
  var MUESTRA = [
    [/fecha|date/, '01/01/2030'], [/mail|correo/, 'nombre@correo.test'], [/tel|whats|phone/, '+00 000 000 000'],
    [/precio|importe|total|pago|saldo|deposito|monto|eur$|idr$|usd$|cuota|anticipo/, '100.000'],
    [/m2|superficie|area|metros/, '500'], [/npwp|nib|ktp|pasaporte|passport|dni|nif/, '0000000000'],
    [/nombre|razon|titular|representante|cargo|marca/, 'Nombre de muestra'], [/domicilio|direccion|address/, 'Dirección de muestra'],
    [/num|codigo|ref|parcela|unidad|villa/, '0001']
  ];
  TC.muestra = function (marcador) {
    for (var i = 0; i < MUESTRA.length; i++) if (MUESTRA[i][0].test(marcador)) return MUESTRA[i][1];
    return '[' + marcador + ']';
  };
  /* El documento con datos de muestra (todo escapado: son valores de esta tabla, nunca texto de nadie), sin comentarios, y mostrando un solo idioma. */
  TC.simula = function (doc) {
    return String(doc).replace(/<!--[\s\S]*?-->/g, '').replace(/\{\{([a-z0-9_]+)\}\}/g, function (m, k) { return TC.esc(TC.muestra(k)); });
  };

  /* La CSP del documento: la MISMA que antepone el generador (contracts/app.html → cspDocumento()); textos-contrato.test.js comprueba que no se separen. */
  TC.csp = function (origen, origenBase) {
    return "default-src 'none'; script-src 'none'; connect-src 'none'; frame-src 'none'; object-src 'none'; form-action 'none'; base-uri " + origen
      + "; style-src 'unsafe-inline' " + origen + " https://fonts.googleapis.com; font-src data: " + origen + " https://fonts.gstatic.com; img-src data: blob: " + origen + (origenBase ? ' ' + origenBase : '');
  };
  /* El documento de la vista previa: CSP como primer hijo de <head>, los dos CSS del contrato, y un solo idioma visible. Va a un iframe con sandbox="" (sin scripts). */
  TC.docPrevio = function (doc, idioma, origen, origenBase) {
    var meta = '<meta http-equiv="Content-Security-Policy" content="' + TC.esc(TC.csp(origen, origenBase)) + '">'
      + '<base href="' + TC.esc(origen) + '/contracts/">'
      + '<link rel="stylesheet" href="assets/brand.css"><link rel="stylesheet" href="assets/contract.css">'
      + '<style>' + (idioma ? '[data-lang]{display:none!important}[data-lang="' + idioma + '"]{display:revert!important}' : '') + 'body{margin:0;padding:12px;background:#fff}</style>';
    var html = TC.simula(doc);
    return /<head(\s[^>]*)?>/i.test(html) ? html.replace(/<head(\s[^>]*)?>/i, function (h) { return h + meta; }) : meta + html;
  };

  /* La frase que la persona confirma al activar y que la base guarda con la versión (plantilla_contrato_activa, v_texto). La comprueba el test contra el SQL. */
  TC.TEXTO_CONFIRMACION = 'Responde esta empresa. El estudio no ha revisado este texto. Consulte a un abogado o notario antes de usarlo: este aviso no sustituye a un abogado indonesio colegiado.';

  if (typeof module !== 'undefined' && module.exports) module.exports = TC;
  else raiz.LW_TEXTOS = TC;
})(typeof window !== 'undefined' ? window : this);
