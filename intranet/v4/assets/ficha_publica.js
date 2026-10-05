/* ficha_publica.js — la pantalla «Ficha pública» (solo admin) de /v4/proyectos/. The Collection v2, F3b, 5-oct-2026.
 *
 * Encargo: encargos/20261002_lawang_thecollection_v2.md (F3b). Backend: supabase/migrations/20261005120000_
 * thecollection_ficha_publica_editor.sql (`ficha_publica_lee` y `ficha_publica_guarda`). Revisión previa #205
 * (Datos + Seguridad + Desarrollo).
 *
 * POR QUÉ ES UN MÓDULO PROPIO y no más líneas en editores.js: solo la usa esta pantalla, y la lógica que importa
 * (qué se manda al servidor, qué falta para publicar, cómo se cuenta un error) son FUNCIONES PURAS que se prueban
 * en node (ficha_publica.test.js) sin navegador. Lo que toca el DOM va aparte y delgado.
 *
 * Reglas que cumple, con su porqué:
 *  - NO se cree NADA del front-end. El servidor valida forma, vínculos y qué falta para publicar; esto solo
 *    ADELANTA esos mensajes para no gastar un viaje. Nada de `sb.from('fichas_publicas')` (sin grant): todo por RPC.
 *  - `textos` y `ficha` se mandan como PARCHES con SOLO lo que cambió. El servidor mezcla por clave de primer
 *    nivel, así que mandar `ficha: {equipamiento: {pool: true}}` borraría `poolType` y `garageDesc`: la clave
 *    `equipamiento` se manda ENTERA (la original + lo editado) y `highlights`/`tech_specs` también. Lo que esta
 *    pantalla no edita (imagenes, downloads, diseno, payment_plan…) NO viaja nunca.
 *  - Al editar se manda SIEMPRE `p_version`, la cadena que devolvió `lee`, tal cual (con sus microsegundos: pasarla
 *    por Date la corta y cada guardado daría 40001). Solo el alta va sin ella.
 *  - Guardar y Publicar/Despublicar son DOS acciones distintas (como el Investor Deck). Publicar no va dentro de
 *    Guardar: un guardado de una ficha ya publicada ya es público al instante y no hay borrador.
 *  - Todo texto que viene de la base se pinta con esc()/textContent, nunca como marcado.
 *  - Español fijo en v1, como «Editar proyecto»: no se traducen decenas de etiquetas (apuntado en pendientes).
 */
(function () {
  'use strict';
  var W = typeof window !== 'undefined' ? window : {};

  /* Interruptor del alta (Crear ficha). Ver sondaSlug(): el servidor NO distingue «alta» de «edición» si se manda un
     slug que ya existe sin p_version — en ese caso edita la otra ficha en silencio. Mientras Datos no lo cierre en la
     base, el alta SONDEA antes (existeSlug) y se niega si el slug ya existe en cualquier proyecto. */
  var CONFIG = { ALTA: true };

  var LINEAS = [['signature', 'Signature'], ['villa', 'Villa'], ['land', 'Parcelas (land)']];
  var REGIONES = [['bali', 'Bali'], ['sumba', 'Sumba']];
  var MODOS_PRECIO = [['consultar', 'Consultar (sin precio)'], ['desde', 'Desde (la web lo calcula con las unidades)'], ['fijo', 'Fijo (importe propio, solo Signature)']];
  var TENURES = [['', '— sin indicar —'], ['freehold', 'Freehold (propiedad)'], ['leasehold', 'Leasehold (arrendamiento)']];
  var ESTADOS_OBRA = [['', '— sin indicar —'], ['offplan', 'En planos (off-plan)'], ['ready', 'Terminada (lista)']];
  /* clave, etiqueta, multilínea, tope de caracteres (espejo de _ficha_error: title/split_title 120, desc 3000, resto 200) */
  var TEXTOS = [
    ['title', 'Título', false, 120],
    ['sub', 'Subtítulo', false, 200],
    ['desc', 'Descripción', true, 3000],
    ['meta', 'Texto meta (buscadores)', false, 200],
    ['split_title', 'Título del bloque partido', false, 120],
    ['split_sub', 'Subtítulo del bloque partido', false, 200]
  ];
  var IDIOMAS = [['es', 'ES'], ['en', 'EN']];
  var EQ_TEXTO = [['poolType', 'Tipo de piscina'], ['garageDesc', 'Garaje (descripción)'], ['furnished', 'Amueblado'], ['style', 'Estilo']];

  /* ───────────────────────── funciones puras ───────────────────────── */

  function esc(v) {
    return String(v == null ? '' : v).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function texto(v) { return v == null ? '' : String(v).trim(); }
  function esObjeto(x) { return x && typeof x === 'object' && !Array.isArray(x); }
  function igual(a, b) { return JSON.stringify(a) === JSON.stringify(b); }
  function copia(x) { return x == null ? x : JSON.parse(JSON.stringify(x)); }

  /* La dirección de la ficha: minúsculas, números y guiones, de 3 a 60 (lo mismo que exige el servidor y el CHECK).
     Se quitan acentos y se cambia todo lo demás por un guion: «Pura Dalem II» → «pura-dalem-ii». */
  function normalizaSlug(s) {
    var t = String(s == null ? '' : s).toLowerCase();
    try { t = t.normalize('NFD').replace(/[̀-ͯ]/g, ''); } catch (e) { /* MUDO A PROPOSITO: sin normalize() (navegador viejo) se sigue sin quitar acentos y el regex de abajo descarta lo que quede */ }
    return t.replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 60).replace(/-+$/g, '');
  }
  function slugValido(s) { return /^[a-z0-9]+(-[a-z0-9]+)*$/.test(s) && s.length >= 3 && s.length <= 60; }

  /* Un importe tecleado («1.250.000», «1250000,50») lo lee lwParseImporte (dinero.js): una sola forma de leer dinero
     en toda la suite. Sin él (node sin dinero.js) solo se aceptan cifras y un punto o coma decimal. */
  function numeroImporte(s) {
    var t = texto(s);
    if (t === '') return null;
    if (typeof W.lwParseImporte === 'function') return W.lwParseImporte(t);
    if (!/^\d+([.,]\d+)?$/.test(t)) return null;
    return parseFloat(t.replace(',', '.'));
  }
  function enteroODefecto(s, def) { var t = texto(s); return /^-?\d+$/.test(t) ? parseInt(t, 10) : def; }

  /* Valores de formulario de una ficha: lo que se pinta en cada campo (todo como cadena o booleano) y la base contra la
     que se mide después qué ha cambiado. Una sola función para pintar y para comparar: así «sin tocar» siempre da {}. */
  function valoresDeFicha(f) {
    f = f || {};
    var tx = esObjeto(f.textos) ? f.textos : {}, fi = esObjeto(f.ficha) ? f.ficha : {}, eq = esObjeto(fi.equipamiento) ? fi.equipamiento : {};
    var v = {
      linea: f.linea || 'villa', region_key: f.region_key || 'bali', region: texto(f.region),
      orden: f.orden == null ? '0' : String(f.orden),
      en_coleccion: !!f.en_coleccion, destacada: !!f.destacada, destacada_home: !!f.destacada_home,
      precio_modo: f.precio_modo || 'consultar', precio_eur: f.precio_eur == null ? '' : String(f.precio_eur),
      tenure: f.tenure || '', lease_years: f.lease_years == null ? '' : String(f.lease_years), estado_obra: f.estado_obra || '',
      unidad_id: f.unidad_id || '', modelo_id: f.modelo_id || '',
      view: texto(fi.view),
      pool: eq.pool === true, garage: eq.garage === true,
      poolType: texto(eq.poolType), garageDesc: texto(eq.garageDesc), furnished: texto(eq.furnished), style: texto(eq.style),
      highlights: Array.isArray(fi.highlights) ? fi.highlights.map(function (x) { return texto(x); }) : [],
      tech_specs: Array.isArray(fi.tech_specs) ? fi.tech_specs.map(function (r) { return { l: texto(r && r.l), v: texto(r && r.v) }; }) : []
    };
    TEXTOS.forEach(function (t) { IDIOMAS.forEach(function (i) { v['t_' + t[0] + '_' + i[0]] = texto(esObjeto(tx[t[0]]) ? tx[t[0]][i[0]] : ''); }); });
    return v;
  }

  /* El PARCHE que se manda al servidor: solo lo que cambió respecto a `f` (la ficha tal y como la leyó `lee`).
     `v` son los valores del formulario (misma forma que valoresDeFicha). Devuelve {} si no hay nada que guardar.
     Nunca incluye `publicada_web` (publicar es otra acción) ni claves de `ficha`/`textos` que no se hayan tocado. */
  function construyeCambios(f, v) {
    var c = {}, base = valoresDeFicha(f), fi = esObjeto(f.ficha) ? f.ficha : {};
    ['linea', 'region_key', 'precio_modo'].forEach(function (k) { if (v[k] !== base[k]) c[k] = v[k]; });
    ['en_coleccion', 'destacada', 'destacada_home'].forEach(function (k) { if (!!v[k] !== base[k]) c[k] = !!v[k]; });
    var orden = enteroODefecto(v.orden, enteroODefecto(base.orden, 0));
    if (orden !== enteroODefecto(base.orden, 0)) c.orden = orden;
    // columnas que admiten vacío: «» → null (y solo si antes tenían algo)
    ['region', 'tenure', 'estado_obra', 'unidad_id', 'modelo_id'].forEach(function (k) {
      var nv = texto(v[k]);
      if (nv !== base[k]) c[k] = nv === '' ? null : nv;
    });
    var anios = texto(v.lease_years);
    if (anios !== base.lease_years) c.lease_years = anios === '' ? null : enteroODefecto(anios, null);
    // precio: con «desde»/«consultar» no viaja importe (el servidor lo pone a NULL y la web lo deriva de las unidades)
    if (v.precio_modo === 'fijo') {
      var importe = texto(v.precio_eur);
      if (v.precio_modo !== base.precio_modo || importe !== base.precio_eur) {
        c.precio_eur = importe === '' ? null : numeroImporte(importe);
      }
    }
    // textos: por clave Y por idioma. null borra el idioma (solo si antes había algo)
    var tx = {};
    TEXTOS.forEach(function (t) {
      IDIOMAS.forEach(function (i) {
        var k = 't_' + t[0] + '_' + i[0], nv = texto(v[k]);
        if (nv === base[k]) return;
        tx[t[0]] = tx[t[0]] || {};
        tx[t[0]][i[0]] = nv === '' ? null : nv;
      });
    });
    if (Object.keys(tx).length) c.textos = tx;
    // ficha: el merge del servidor es de primer nivel, así que cada clave tocada va ENTERA y las demás no van
    var fp = {};
    var hl = (v.highlights || []).map(texto).filter(Boolean);
    if (!igual(hl, base.highlights.filter(Boolean))) fp.highlights = hl.length ? hl : null;
    var ts = (v.tech_specs || []).map(function (r) { return { l: texto(r && r.l), v: texto(r && r.v) }; })
      .filter(function (r) { return r.l || r.v; });
    if (!igual(ts, base.tech_specs.filter(function (r) { return r.l || r.v; }))) fp.tech_specs = ts.length ? ts : null;
    var eq0 = esObjeto(fi.equipamiento) ? fi.equipamiento : {}, eq = copia(eq0), tocoEq = false;
    ['pool', 'garage'].forEach(function (k) {
      if (!!v[k] !== (eq0[k] === true)) { eq[k] = !!v[k]; tocoEq = true; }
    });
    EQ_TEXTO.forEach(function (p) {
      var nv = texto(v[p[0]]);
      if (nv !== base[p[0]]) { tocoEq = true; if (nv === '') delete eq[p[0]]; else eq[p[0]] = nv; }
    });
    // una subclave de equipamiento NO se borra con null (el validador la rechaza): se omite de la clave entera
    if (tocoEq) fp.equipamiento = Object.keys(eq).length ? eq : null;
    var vista = texto(v.view);
    if (vista !== base.view) fp.view = vista === '' ? null : vista;
    if (Object.keys(fp).length) c.ficha = fp;
    return c;
  }

  /* La llamada a `ficha_publica_guarda`. Una ficha que ya existe (f con `version`) lleva SIEMPRE p_version; solo el
     alta (f == null) va sin ella. Si una edición llega sin version se niega aquí: mandarla sin ella saltaría el
     control de «otra persona cambió esta ficha». */
  function payloadGuarda(f, slug, cambios) {
    if (f) {
      if (!f.version) throw new Error('La ficha no trae su versión: recarga la pantalla antes de guardar.');
      return { p_slug: f.slug, p_cambios: cambios, p_version: f.version };
    }
    return { p_slug: slug, p_cambios: cambios };
  }

  /* Problemas de forma que se dicen ANTES de viajar (espejo de _ficha_error y de las reglas de guarda; el servidor
     las vuelve a comprobar, esto solo ahorra el viaje y las dice en el campo). Devuelve una lista de frases. */
  function problemasForma(v, f) {
    var p = [], base = valoresDeFicha(f || {});
    var plano = function (s) { return /[<>]/.test(s); };
    TEXTOS.forEach(function (t) {
      IDIOMAS.forEach(function (i) {
        var s = texto(v['t_' + t[0] + '_' + i[0]]);
        if (s.length > t[3]) p.push(t[1] + ' (' + i[1] + '): pasa de ' + t[3] + ' caracteres (lleva ' + s.length + ').');
        if (plano(s)) p.push(t[1] + ' (' + i[1] + '): es texto plano, sin los signos < ni >.');
      });
    });
    var hl = (v.highlights || []).map(texto).filter(Boolean);
    if (hl.length > 20) p.push('Puntos destacados: como mucho 20.');
    hl.forEach(function (s) {
      if (s.length > 160) p.push('Un punto destacado pasa de 160 caracteres.');
      if (plano(s)) p.push('Los puntos destacados son texto plano, sin < ni >.');
    });
    var ts = (v.tech_specs || []).filter(function (r) { return texto(r && r.l) || texto(r && r.v); });
    if (ts.length > 20) p.push('Ficha técnica: como mucho 20 celdas.');
    ts.forEach(function (r) {
      var l = texto(r.l), x = texto(r.v);
      if (!l || !x) p.push('Cada celda de la ficha técnica necesita rótulo y valor.');
      if (l.length > 40) p.push('Un rótulo de la ficha técnica pasa de 40 caracteres.');
      if (x.length > 120) p.push('Un valor de la ficha técnica pasa de 120 caracteres.');
      if (plano(l) || plano(x)) p.push('La ficha técnica es texto plano, sin < ni >.');
    });
    EQ_TEXTO.forEach(function (q) {
      var s = texto(v[q[0]]);
      if (s.length > 80) p.push(q[1] + ': pasa de 80 caracteres.');
      if (plano(s)) p.push(q[1] + ': es texto plano, sin < ni >.');
    });
    if (texto(v.view).length > 60) p.push('Vista: pasa de 60 caracteres.');
    if (plano(texto(v.view)) || plano(texto(v.region))) p.push('Vista y región son texto plano, sin < ni >.');
    if (texto(v.region).length > 120) p.push('Región web: pasa de 120 caracteres.');
    if (texto(v.orden) !== '' && !/^-?\d+$/.test(texto(v.orden))) p.push('Orden: un número entero.');
    var anios = texto(v.lease_years);
    if (anios !== '' && (!/^\d+$/.test(anios) || +anios < 1 || +anios > 99)) p.push('Años de arrendamiento: un entero entre 1 y 99.');
    if (v.precio_modo === 'fijo') {
      if (v.linea !== 'signature') p.push('El precio fijo solo existe en la línea Signature.');
      var im = texto(v.precio_eur);
      if (im !== '') {
        var n = numeroImporte(im);
        if (n == null || !isFinite(n) || n < 0 || n >= 1e9) p.push('El importe no es válido (un número menor de 1.000 millones).');
      }
    }
    if (texto(v.unidad_id) && texto(v.unidad_id) !== base.unidad_id && v.linea !== 'signature') {
      p.push('Solo una ficha Signature se vincula a una unidad concreta.');
    }
    return p;
  }

  /* Lo que falta para PUBLICAR una ficha tal y como está GUARDADA (espejo de las reglas de guarda: proyecto, título en
     los dos idiomas, importe si es fijo). Lista de frases; vacía = se puede publicar. */
  function faltaParaPublicar(f) {
    var m = [], tx = esObjeto(f && f.textos) ? f.textos : {}, ti = esObjeto(tx.title) ? tx.title : {};
    if (!f || !f.proyecto_id) m.push('vincularla a un proyecto');
    if (!texto(ti.es)) m.push('el título en español');
    if (!texto(ti.en)) m.push('el título en inglés');
    if (f && f.precio_modo === 'fijo' && !(Number(f.precio_eur) > 0)) m.push('el importe del precio fijo (mayor que 0)');
    return m;
  }
  /* Lo que NO impide publicar pero conviene saber: se dice en la confirmación, no se esconde. */
  function avisosPublicacion(f) {
    var a = [], tx = esObjeto(f && f.textos) ? f.textos : {}, d = esObjeto(tx.desc) ? tx.desc : {};
    if (!texto(d.en)) a.push('La descripción en inglés está vacía.');
    if (!texto(d.es)) a.push('La descripción en español está vacía.');
    return a;
  }

  /* Un error de la RPC en una frase para la persona. 42501 y P0002 se explican; 22023/23514/40001 ya vienen en
     español desde el servidor (se muestran tal cual, sin el nombre de la regla de la base); lo demás pasa por
     lwErrorHumano, que ya sabe de red, sesión y errores de esquema. */
  function errorLegible(e, prefijo) {
    var c = String((e && e.code) || ''), m = String((e && e.message) || '');
    var pre = prefijo ? prefijo + ': ' : '';
    if (c === '42501') return pre + 'Solo administración puede editar la ficha pública.';
    if (c === 'P0002') return pre + 'Ese proyecto ya no existe: recarga la pantalla.';
    if (c === '40001') return pre + (m || 'Otra persona cambió esta ficha; recárgala.');
    if (c === '22023' || c === '23514') {
      var limpio = m.replace(/\s*\((?:regla|rule)[^)]*\)/i, '').replace(/\s+/g, ' ').trim();
      return pre + (limpio || 'Un dato no cumple las reglas de la ficha.');
    }
    if (typeof W.lwErrorHumano === 'function') return W.lwErrorHumano(e, prefijo || '');
    return pre + (m || 'Algo ha fallado');
  }

  /* El servidor no distingue alta de edición cuando se manda un slug que ya existe SIN p_version: edita esa ficha
     (puede ser de otro proyecto) en silencio. Sonda sin escritura: `guarda` con {} y una version imposible comprueba
     la versión ANTES de tocar nada → «ya no existe» (no hay ficha con ese slug) u «otra persona cambió» (existe). */
  var VERSION_IMPOSIBLE = '1970-01-01T00:00:00.000000Z';
  function interpretaSonda(e) {
    if (!e) return 'error';   // sin error es imposible (la versión no puede casar): mejor no crear nada
    var m = String(e.message || '');
    if (String(e.code) === '40001' && /ya no existe/i.test(m)) return 'libre';
    if (String(e.code) === '40001' && /cambi/i.test(m)) return 'existe';
    return 'error';
  }
  function existeSlug(sb, slug) {
    return sb.rpc('ficha_publica_guarda', { p_slug: slug, p_cambios: {}, p_version: VERSION_IMPOSIBLE }).then(function (r) {
      return interpretaSonda(r && r.error);
    });
  }

  /* Cómo se ve el precio de una ficha ya publicada, a partir de `publico` (el trozo de coleccion_publica()). No se
     recalcula nada: se muestra lo que la web sirve hoy. */
  function fmtEur(n) {
    if (typeof W.lwFormatoImporte === 'function') return W.lwFormatoImporte(n, 'EUR', { decimales: 0 });
    return String(Math.round(Number(n) || 0)).replace(/\B(?=(\d{3})+(?!\d))/g, '.') + ' EUR';
  }
  function precioPublico(pub) {
    if (!pub || pub.priceEUR == null) return 'Consultar (sin precio)';
    return (pub.priceMode === 'from' ? 'Desde ' : '') + fmtEur(pub.priceEUR);
  }
  function precioGuardado(f) {
    if (f.precio_modo === 'fijo') return f.precio_eur == null ? 'Fijo, sin importe todavía' : 'Fijo: ' + fmtEur(f.precio_eur);
    if (f.precio_modo === 'desde') return 'Desde (lo calcula la web con las unidades a la venta)';
    return 'Consultar (sin precio)';
  }
  function estadoObraTexto(s) {
    var k = String(s || '').replace(/^status\./, '');
    return k === 'ready' ? 'Terminada' : (k === 'offplan' ? 'En planos' : (k || '—'));
  }
  function tituloFicha(f) {
    var ti = esObjeto(f && f.textos && f.textos.title) ? f.textos.title : {};
    return texto(ti.es) || texto(ti.en) || (f && f.slug) || '—';
  }

  /* ───────────────────────── interfaz ───────────────────────── */

  var API = {
    CONFIG: CONFIG, normalizaSlug: normalizaSlug, slugValido: slugValido, valoresDeFicha: valoresDeFicha,
    construyeCambios: construyeCambios, payloadGuarda: payloadGuarda, problemasForma: problemasForma,
    faltaParaPublicar: faltaParaPublicar, avisosPublicacion: avisosPublicacion, errorLegible: errorLegible,
    interpretaSonda: interpretaSonda, existeSlug: existeSlug, precioPublico: precioPublico, precioGuardado: precioGuardado,
    VERSION_IMPOSIBLE: VERSION_IMPOSIBLE, abre: abre
  };
  W.lwFichaPublica = API;
  if (typeof module === 'object' && module && module.exports) module.exports = API;

  var INK = '#2E3437', MUTED = '#75786e', LINE = '#E4DCCB', BAND = '#f5f4ee';

  function aviso(m) { if (typeof toast === 'function') toast(m); }
  function avisoMal(m) { if (typeof toastMal === 'function') toastMal(m); else if (typeof alert === 'function') alert(m); }
  function nombreUnidad(estado, id) {
    var u = (estado.unidades || []).filter(function (x) { return x.id === id; })[0];
    return u ? u.codigo : null;
  }

  function abre(o) {
    o = o || {};
    var sb = o.sb, proy = o.proyecto;
    if (!o.esAdmin) return avisoMal('La ficha pública la edita administración.');
    if (!sb || !proy || !proy.id) return avisoMal('El proyecto aún no ha cargado.');
    if (typeof W.lwCajon !== 'function' || typeof W.lwVentana !== 'function' || typeof W.lwConfirmar !== 'function' || !W.lwCajonHtml) {
      return avisoMal('La pantalla aún no ha cargado: prueba otra vez en un segundo.');
    }
    var H = W.lwCajonHtml, estado = null, cajon = null, pendienteAbrir = null;

    cajon = W.lwCajon({
      titulo: 'Ficha pública', sub: proy.nombre, ancho: 'min(640px,96vw)',
      bajoTitulo: 'Lo que The Collection enseña de este proyecto, sin login.',
      cuerpo: '<p style="margin:0;color:' + MUTED + '">Cargando…</p>',
      acciones: [
        { texto: 'Crear ficha', tono: 'primario', onClick: function () { creaFicha(); } },
        { texto: 'Cerrar', cerrar: true }
      ]
    });

    function cuerpo() { return cajon && cajon.cuerpo; }
    function leer() {
      return sb.rpc('ficha_publica_lee', { p_proyecto_id: proy.id }).then(function (r) {
        if (r.error) throw r.error;
        if (!r.data || !Array.isArray(r.data.fichas)) throw new Error('La base no devolvió las fichas');
        estado = r.data;
        pinta();
      }).then(null, function (e) {
        // No poder leer NO es «no hay fichas»: se dice y se ofrece reintentar.
        estado = null; pendienteAbrir = null;
        var c = cuerpo(); if (!c) return;
        c.innerHTML = H.nota('No se han podido leer las fichas de este proyecto: ' + errorLegible(e) + ' Esto no significa que no existan.') +
          '<p style="margin:12px 0 0"><button type="button" class="las-btn2" data-fp="reintentar">Reintentar</button></p>';
      });
    }

    function filaFicha(f, i) {
      var pub = f.publico, publicada = !!f.publicada_web;
      var linea = (LINEAS.filter(function (l) { return l[0] === f.linea; })[0] || [f.linea, f.linea])[1];
      var etiqueta = H.tag(publicada ? 'Publicada' : 'Sin publicar', publicada ? 'ok' : 'neutro') + ' ' + H.tag(linea, 'neutro');
      var hoy;
      if (!publicada) {
        hoy = '<p style="margin:0;color:' + MUTED + '">No se sirve al público.</p>';
      } else if (!pub) {
        hoy = H.nota('Está marcada como publicada, pero la web no la sirve hoy (le falta el proyecto o datos). Revísala antes de darla por visible.');
      } else {
        var imgs = Array.isArray(pub.images) ? pub.images.length : 0;
        var ud = (pub.unitsTotal != null) ? ((pub.unitsAvailable == null ? '—' : pub.unitsAvailable) + ' de ' + pub.unitsTotal + ' disponibles') : null;
        hoy = '<p style="margin:0 0 6px;font-weight:600;color:' + INK + '">Lo que verá el público</p>' +
          H.dato('Precio', precioPublico(pub)) + H.dato('Estado de la obra', estadoObraTexto(pub.status)) +
          H.dato('Fotos', String(imgs)) + (ud ? H.dato('Unidades', ud) : '');
      }
      var base = '<div style="display:flex;flex-wrap:wrap;gap:6px;align-items:center;margin:0 0 8px">' + etiqueta + '</div>' +
        '<p style="margin:0 0 10px;color:' + MUTED + ';font-size:12.5px">Dirección <code>/property/' + esc(f.slug) + '</code> (fija: no se puede cambiar)</p>' +
        '<div style="background:' + BAND + ';border:1px solid ' + LINE + ';border-radius:12px;padding:12px 14px;margin:0 0 12px">' + hoy + '</div>' +
        '<div style="display:flex;flex-wrap:wrap;gap:8px;align-items:center">' +
        '<button type="button" class="las-btn1" data-fp="editar" data-i="' + i + '"><span>Editar</span></button>' +
        '<button type="button" class="las-btn2' + (publicada ? ' lwc-peligro' : '') + '" data-fp="publica" data-i="' + i + '">' + (publicada ? 'Despublicar' : 'Publicar') + '</button>' +
        (publicada ? H.enlace('/property/' + f.slug, 'Ver la página actual de la web', true) : '') + '</div>' +
        (publicada ? '<p style="margin:10px 0 0;color:' + MUTED + ';font-size:12px">La web de siempre aún lee su fuente antigua hasta el corte: lo que guardes aquí se ve ya en la versión nueva (<a class="lwc-link" href="/thecollection-v2" target="_blank" rel="noopener">/thecollection-v2</a>) y en la actual cuando se haga el cambio.</p>' : '');
      return H.seccion(tituloFicha(f), base, f.slug);
    }

    function pinta() {
      var c = cuerpo(); if (!c || !estado) return;
      var fichas = estado.fichas;
      c.innerHTML = fichas.length
        ? fichas.map(filaFicha).join('')
        : H.nota('Este proyecto aún no tiene ficha pública. «Crear ficha» la crea sin publicar: la completas y la publicas después.');
      if (pendienteAbrir) {
        var s = pendienteAbrir; pendienteAbrir = null;
        var i = fichas.map(function (f) { return f.slug; }).indexOf(s);
        if (i >= 0) editar(i);
      }
    }

    cajon.cuerpo.addEventListener('click', function (ev) {
      var b = ev.target.closest && ev.target.closest('[data-fp]');
      if (!b) return;
      var acc = b.getAttribute('data-fp'), i = parseInt(b.getAttribute('data-i'), 10);
      if (acc === 'reintentar') leer();
      else if (acc === 'editar') editar(i);
      else if (acc === 'publica') publicaODespublica(i);
    });

    /* ── publicar / despublicar: su propio clic, su propia confirmación ── */
    function publicaODespublica(i) {
      var f = estado && estado.fichas[i]; if (!f) return;
      var publicar = !f.publicada_web, t = esc(tituloFicha(f));
      if (publicar) {
        var falta = faltaParaPublicar(f);
        if (falta.length) return avisoMal('Para publicar «' + tituloFicha(f) + '» falta: ' + falta.join(', ') + '. Complétalo con «Editar» y vuelve a publicar.');
      }
      var avisos = publicar ? avisosPublicacion(f) : [];
      var cuerpoConf = publicar
        ? '<p>Vas a hacer PÚBLICA esta ficha, sin login: la verá cualquiera.</p>' +
          '<p><b>' + t + '</b><br>' + esc(precioGuardado(f)) + '<br>Dirección: <code>/property/' + esc(f.slug) + '</code></p>' +
          (avisos.length ? '<p>Ojo: ' + avisos.map(esc).join(' ') + '</p>' : '') +
          '<p>Para retirarla después, «Despublicar».</p>'
        : '<p><b>' + t + '</b> deja de verse en The Collection (<code>/property/' + esc(f.slug) + '</code>).</p><p>Los datos se conservan; se puede volver a publicar.</p>';
      W.lwConfirmar({
        titulo: publicar ? 'Publicar la ficha' : 'Despublicar la ficha', cuerpo: cuerpoConf,
        confirmar: publicar ? 'Publicar' : 'Despublicar', tono: 'peligro'
      }).then(function (ok) {
        if (!ok) return;
        var p;
        try { p = payloadGuarda(f, f.slug, { publicada_web: publicar }); } catch (e) { return avisoMal(e.message); }
        return sb.rpc('ficha_publica_guarda', p).then(function (r) {
          if (r.error) { avisoMal(errorLegible(r.error, 'No se pudo ' + (publicar ? 'publicar' : 'despublicar'))); return leer(); }
          aviso(publicar ? 'Ficha publicada' : 'Ficha despublicada');
          return leer();
        }, function (e) {
          // red caída o fallo del cliente: se dice y se relee, para no dejar en pantalla un estado que puede ser falso
          avisoMal(errorLegible(e, 'No se pudo ' + (publicar ? 'publicar' : 'despublicar') + ' (no sé si llegó a aplicarse)'));
          return leer();
        });
      });
    }

    /* ── crear ficha ── */
    function creaFicha() {
      if (!CONFIG.ALTA) return avisoMal('Crear fichas desde aquí está desactivado.');
      if (!estado) return avisoMal('Espera a que carguen las fichas del proyecto.');
      W.lwVentana('Nueva ficha pública', [
        { tipo: 'nota', label: 'La ficha nace SIN publicar. La dirección (slug) es la de /property/<slug> y no se puede cambiar después: cambiarla rompería los enlaces ya compartidos.' },
        { k: 'slug', label: 'Dirección (slug)', req: 1, valor: normalizaSlug(proy.slug || proy.nombre), ayuda: 'Minúsculas, números y guiones, de 3 a 60.' },
        { k: 'linea', label: 'Línea', tipo: 'select', opciones: LINEAS, valor: 'villa', medio: 1 },
        { k: 'region_key', label: 'Región', tipo: 'select', opciones: REGIONES, valor: 'bali', medio: 1 }
      ], 'Crear ficha', function (v) {
        var slug = normalizaSlug(v.slug);
        if (!slugValido(slug)) return { error: { message: 'La dirección solo admite minúsculas, números y guiones (de 3 a 60).' } };
        if (estado.fichas.some(function (f) { return f.slug === slug; })) return { error: { message: 'Este proyecto ya tiene una ficha con esa dirección.' } };
        return existeSlug(sb, slug).then(function (r) {
          if (r === 'existe') return { error: { message: 'Ya existe una ficha con esa dirección (puede ser de otro proyecto). Elige otra.' } };
          if (r !== 'libre') return { error: { message: 'No he podido comprobar si la dirección está libre. No se ha creado nada: vuelve a intentarlo.' } };
          return sb.rpc('ficha_publica_guarda', payloadGuarda(null, slug, { linea: v.linea, region_key: v.region_key, proyecto_id: proy.id }));
        }).then(function (r) {
          if (r && r.error) return { error: { message: errorLegible(r.error) } };
          pendienteAbrir = slug;
          return {};
        });
      }, { sub: proy.nombre, sinRecarga: true, ancho: '620px', alCerrar: function () { leer(); } });
    }

    /* ── editar ── */
    function editar(i) {
      var f = estado && estado.fichas[i]; if (!f) return;
      var v0 = valoresDeFicha(f), publicada = !!f.publicada_web;
      var usadas = {};
      estado.fichas.forEach(function (o) { if (o.id !== f.id && o.unidad_id) usadas[o.unidad_id] = true; });
      var opsUnidad = [['', '— ninguna —']].concat((estado.unidades || []).filter(function (u) { return !usadas[u.id] || u.id === f.unidad_id; })
        .map(function (u) { return [u.id, u.codigo]; }));
      if (f.unidad_id && !nombreUnidad(estado, f.unidad_id)) opsUnidad.push([f.unidad_id, 'Unidad ya no disponible']);
      var opsModelo = [['', 'Todos los modelos del proyecto']].concat((estado.modelos || []).map(function (m) { return [m.id, m.nombre]; }));
      var lista = { highlights: null, tech_specs: null };

      var campos = [];
      if (publicada) {
        campos.push({ tipo: 'nota', label: 'Esta ficha está PUBLICADA: lo que guardes pasa a la web nueva al instante, sin borrador (la web de siempre lo recogerá en el corte). Para retirarla usa «Despublicar» en la pantalla anterior.' });
      }
      campos.push(
        { k: 'linea', label: 'Línea', tipo: 'select', opciones: LINEAS, valor: v0.linea, medio: 1 },
        { k: 'region_key', label: 'Región', tipo: 'select', opciones: REGIONES, valor: v0.region_key, medio: 1 },
        { k: 'region', label: 'Región que se escribe en la web', valor: v0.region, medio: 1, ayuda: 'Ej. «Ubud, Bali». Texto plano.' },
        { k: 'orden', label: 'Orden en la lista', tipo: 'number', valor: v0.orden, medio: 1, paso: '1' },
        { k: 'en_coleccion', label: 'Sale en The Collection', tipo: 'check', valor: v0.en_coleccion },
        { k: 'destacada', label: 'Destacada', tipo: 'check', valor: v0.destacada },
        { k: 'destacada_home', label: 'Destacada en la portada', tipo: 'check', valor: v0.destacada_home },
        { k: 'precio_modo', label: 'Precio', tipo: 'select', opciones: MODOS_PRECIO, valor: v0.precio_modo, medio: 1,
          ayuda: 'Con «Desde» la web calcula el importe con las unidades a la venta; aquí no se escribe.' },
        { k: 'precio_eur', label: 'Importe fijo (EUR)', valor: v0.precio_eur, medio: 1, visibleSi: { k: 'precio_modo', valores: ['fijo'] } },
        { k: 'tenure', label: 'Tenencia', tipo: 'select', opciones: TENURES, valor: v0.tenure, medio: 1 },
        { k: 'lease_years', label: 'Años de arrendamiento (solo leasehold)', tipo: 'number', valor: v0.lease_years, medio: 1, paso: '1' },
        { k: 'estado_obra', label: 'Estado de la obra', tipo: 'select', opciones: ESTADOS_OBRA, valor: v0.estado_obra, medio: 1 }
      );
      if ((estado.unidades || []).length) {
        campos.push({ k: 'unidad_id', label: 'Unidad vinculada (solo Signature)', tipo: 'select', opciones: opsUnidad, valor: v0.unidad_id, medio: 1,
          ayuda: 'Una unidad solo puede estar en una ficha.' });
      }
      if ((estado.modelos || []).length || f.modelo_id) {
        campos.push({ k: 'modelo_id', label: 'Modelo de villa', tipo: 'select', opciones: opsModelo, valor: v0.modelo_id, medio: 1,
          ayuda: 'Sin modelo = la ficha habla de todos los modelos del proyecto.' });
      }
      TEXTOS.forEach(function (t) {
        IDIOMAS.forEach(function (i2) {
          campos.push({ k: 't_' + t[0] + '_' + i2[0], label: t[1] + ' (' + i2[1] + ')', tipo: t[2] ? 'textarea' : undefined,
            valor: v0['t_' + t[0] + '_' + i2[0]], medio: t[2] ? 0 : 1 });
        });
      });
      campos.push(
        { tipo: 'custom', render: function (d) { lista.highlights = montaLista(d, { titulo: 'Puntos destacados', ayuda: 'Hasta 20, de 160 caracteres. Texto plano.', cols: [{ ph: 'Punto destacado' }], filas: v0.highlights.map(function (x) { return [x]; }), max: 20, nuevo: 'Añadir punto' }); } },
        { tipo: 'custom', render: function (d) { lista.tech_specs = montaLista(d, { titulo: 'Ficha técnica', ayuda: 'Hasta 20 celdas: rótulo (40) y valor (120).', cols: [{ ph: 'Rótulo' }, { ph: 'Valor' }], filas: v0.tech_specs.map(function (r) { return [r.l, r.v]; }), max: 20, nuevo: 'Añadir celda' }); } },
        { k: 'pool', label: 'Piscina', tipo: 'check', valor: v0.pool },
        { k: 'poolType', label: 'Tipo de piscina', valor: v0.poolType, medio: 1 },
        { k: 'garage', label: 'Garaje', tipo: 'check', valor: v0.garage },
        { k: 'garageDesc', label: 'Garaje (descripción)', valor: v0.garageDesc, medio: 1 },
        { k: 'furnished', label: 'Amueblado', valor: v0.furnished, medio: 1 },
        { k: 'style', label: 'Estilo', valor: v0.style, medio: 1 },
        { k: 'view', label: 'Vista', valor: v0.view, medio: 1 }
      );

      W.lwVentana('Editar ficha — ' + tituloFicha(f), campos, 'Guardar cambios', function (vals) {
        var v = Object.assign({}, vals);
        v.highlights = lista.highlights ? lista.highlights().map(function (r) { return r[0]; }) : v0.highlights;
        v.tech_specs = lista.tech_specs ? lista.tech_specs().map(function (r) { return { l: r[0], v: r[1] }; }) : v0.tech_specs;
        ['unidad_id', 'modelo_id'].forEach(function (k) { if (!(k in vals)) v[k] = v0[k]; });   // campo no pintado = no tocado
        var problemas = problemasForma(v, f);
        if (problemas.length) return { error: { message: problemas.join(' ') } };
        var cambios = construyeCambios(f, v);
        if (!Object.keys(cambios).length) { aviso('No había cambios que guardar'); return {}; }
        var p;
        try { p = payloadGuarda(f, f.slug, cambios); } catch (e) { return { error: { message: e.message } }; }
        return sb.rpc('ficha_publica_guarda', p).then(function (r) {
          if (r.error) return { error: { message: errorLegible(r.error) } };
          return {};
        });
      }, { sub: proy.nombre, sinRecarga: true, ancho: '760px', alCerrar: function () { leer(); } });
    }

    leer();
    return cajon;
  }

  /* Lista editable con filas y «añadir/quitar» (precedente: tramos de pago en editores.js). Devuelve una función que
     lee las filas (descartando las vacías). Los botones son type=button y Enter no envía el formulario. */
  function montaLista(d, cfg) {
    var cab = document.createElement('div');
    cab.className = 'las-etq'; cab.textContent = cfg.titulo; d.appendChild(cab);
    if (cfg.ayuda) { var ay = document.createElement('p'); ay.className = 'las-ayuda'; ay.textContent = cfg.ayuda; d.appendChild(ay); }
    var caja = document.createElement('div'); caja.style.cssText = 'display:grid;gap:8px;margin:6px 0'; d.appendChild(caja);
    var cols = cfg.cols.length;
    function fila(vals) {
      var r = document.createElement('div');
      r.setAttribute('data-fp-fila', '1');
      r.style.cssText = 'display:grid;gap:8px;align-items:center;grid-template-columns:' + (cols === 1 ? 'minmax(0,1fr)' : 'minmax(0,1fr) minmax(0,1.6fr)') + ' auto';
      cfg.cols.forEach(function (c, i) {
        var inp = document.createElement('input');
        inp.type = 'text'; inp.className = 'las-in'; inp.placeholder = c.ph; inp.value = vals && vals[i] != null ? vals[i] : '';
        inp.setAttribute('aria-label', cfg.titulo + ': ' + c.ph);
        inp.addEventListener('keydown', function (ev) { if (ev.key === 'Enter') ev.preventDefault(); });
        r.appendChild(inp);
      });
      var q = document.createElement('button');
      q.type = 'button'; q.className = 'las-btn2 las-mini'; q.textContent = 'Quitar'; q.setAttribute('aria-label', 'Quitar ' + cfg.titulo.toLowerCase());
      q.addEventListener('click', function () { r.remove(); estadoBoton(); });
      r.appendChild(q);
      caja.appendChild(r);
    }
    var nuevo = document.createElement('button');
    nuevo.type = 'button'; nuevo.className = 'las-btn2 las-mini'; nuevo.textContent = cfg.nuevo; d.appendChild(nuevo);
    function estadoBoton() { nuevo.disabled = caja.children.length >= cfg.max; }
    nuevo.addEventListener('click', function () { fila(null); estadoBoton(); var ins = caja.lastChild && caja.lastChild.querySelector('input'); if (ins) ins.focus(); });
    (cfg.filas || []).forEach(fila); estadoBoton();
    return function () {
      return Array.prototype.map.call(caja.children, function (r) {
        return Array.prototype.map.call(r.querySelectorAll('input'), function (x) { return x.value; });
      }).filter(function (vs) { return vs.some(function (x) { return texto(x); }); });
    };
  }
})();
