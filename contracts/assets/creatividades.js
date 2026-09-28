/* ═══════════════════════════════════════════════════════════════════════════
   CREATIVIDADES · la biblioteca, vista desde el navegador — 24-sep-2026
   ═══════════════════════════════════════════════════════════════════════════
   Encargo: encargos/20260924_lawang_creatividades_v4.md. Una sola capa para las
   tres pantallas que la usan (generador de redes, constructor de dossiers y la
   portada v4): nace compartida en `contracts/assets/` (Regla 0 de la suite), no
   dentro de una herramienta con idea de moverla luego.

   Lo que decide la BASE, no esto (revisión previa #68):
   · quién ve qué: RLS de `creatividades` y del bucket (un comercial con
     `creatividades_ver` solo ve el fichero EXACTO de lo aprobado);
   · los cambios de estado: SOLO la RPC `creatividad_estado`;
   · `lleva_render`: lo calcula un trigger con las fotos enlazadas.
   Esta capa solo pide cosas; si la base dice que no, el error sube tal cual.

   Ficheros: el bucket no admite UPDATE ni DELETE, así que cada guardado es un
   fichero NUEVO (`<id>/estado-<ts>.json`, `<id>/pieza-<ts>.png`) y la fila
   apunta al último. Un borrador guardado diez veces deja nueve JSON pequeños
   huérfanos: es el precio de que nadie pueda sobrescribir lo ya aprobado.

   Seguridad #3: un estado guardado por OTRA persona es entrada no fiable. Todo
   HTML que venga de ahí pasa por `limpia()` (DOMPurify con lista blanca mínima)
   antes de pintarse. Sin DOMPurify cargado, `limpia()` escapa todo: falla
   cerrado, nunca abierto.
   ═══════════════════════════════════════════════════════════════════════════ */
(function () {
  'use strict';
  var BUCKET = 'creatividades';
  var HTML_PERMITIDO = { ALLOWED_TAGS: ['b', 'i', 'em', 'strong', 'br', 'span'], ALLOWED_ATTR: ['class'] };

  function sb() {
    if (!window.LW_AUTH) return Promise.reject(new Error('Sin sesión: falta guard.js en esta página.'));
    return window.LW_AUTH.then(function (a) { return a.sb; });
  }
  function falla(r) { if (r && r.error) throw r.error; return r ? r.data : null; }

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function limpia(html) {
    if (window.DOMPurify && window.DOMPurify.sanitize) return window.DOMPurify.sanitize(String(html == null ? '' : html), HTML_PERMITIDO);
    return esc(html);
  }
  /* Recorre un estado reabierto y limpia TODAS sus cadenas: el constructor de
     dossiers pinta muchos campos con innerHTML, y cuál lo hace depende del tipo
     de página. Más seguro limpiarlo todo que acordarse de cada campo. Las rutas
     de imagen no llevan HTML, así que DOMPurify las devuelve tal cual. */
  function limpiaEstado(v) {
    if (typeof v === 'string') return limpia(v);
    if (Array.isArray(v)) return v.map(limpiaEstado);
    if (v && typeof v === 'object') {
      var o = {};
      Object.keys(v).forEach(function (k) { o[k] = limpiaEstado(v[k]); });
      return o;
    }
    return v;
  }

  /* Guarda (crea o actualiza un BORRADOR). `o`:
     { id?, tipo:'pieza'|'dossier', titulo, proyecto_id?, formato?, arquetipo?, precios_a?,
       estado: <objeto del editor>, png?: Blob, portada?: Blob, fotoIds?: [uuid], modeloIds?: [uuid] }
     Devuelve la fila guardada. */
  /* Frontera frontend/backend, bloque 4 (27-sep-2026, LAW-336; revisión previa #127 de Marketing): el navegador ya
     no escribe en la base ni elige la ruta de los ficheros. Cada fichero se sube por URL firmada que da la edge
     `ficheros` (clase `creatividad`: el servidor compone `<id>/{estado|pieza|portada}-<n>.<ext>`, la convención
     que exigen los CHECK), y al final UNA llamada `guarda` valida lo subido (el estado es un JSON: la edge lo lee
     entero) y guarda metadatos, ficheros, fotos y modelos en una sola transacción. Antes eran 5-8 escrituras
     sueltas: un fallo a mitad dejaba la fila nueva con los enlaces viejos. Misma firma y mismo resultado (la fila
     guardada, con `lleva_render` recalculado): la usan redes, el constructor de dossiers y «Enviar a aprobar». */
  function subeCreatividad(c, id, tipo, rol, blob) {
    return window.lwFichero(c, 'creatividad', 'subida_url', { creatividad_id: id || null, tipo: tipo, rol: rol }).then(function (u) {
      var f = new File([blob], rol + (rol === 'estado' ? '.json' : '.png'), { type: u.content_type });
      return c.storage.from(u.bucket).uploadToSignedUrl(u.path, u.token, f, { contentType: u.content_type }).then(function (up) {
        if (up.error) throw new Error('No se pudo subir el fichero: ' + (up.error.message || up.error));
        return u;
      });
    });
  }
  async function guardar(o) {
    if (typeof window.lwFichero !== 'function') throw new Error('Falta guard.js actualizado: recarga la página');
    var c = await sb();
    var datos = {
      titulo: String(o.titulo || '').trim().slice(0, 200) || 'Sin título',
      proyecto_id: o.proyecto_id || null,
      formato: o.formato || null,
      arquetipo: o.arquetipo || null,
      precios_a: o.precios_a || null
    };
    // El estado primero: en una creatividad nueva, su subida es la que recibe el id del servidor.
    var est = await subeCreatividad(c, o.id, o.tipo, 'estado',
      new Blob([JSON.stringify(o.estado || {})], { type: 'application/json' }));
    var id = est.creatividad_id;
    var cuerpo = { creatividad_id: id, tipo: o.tipo, datos: datos, estado_path: est.path };
    if (o.png) cuerpo.path = (await subeCreatividad(c, id, o.tipo, 'pieza', o.png)).path;
    // Miniatura de la portada de un dossier (rediseño A, 24-sep): la biblioteca la
    // enseña en vez de una caja gris. Una pieza no la necesita: su PNG ya es la imagen.
    if (o.portada) cuerpo.portada_path = (await subeCreatividad(c, id, o.tipo, 'portada', o.portada)).path;
    // Enlaces: se reponen enteros (null = no se tocan). La base rechaza tocarlos si ya no es borrador.
    if (o.fotoIds) cuerpo.foto_ids = uniq(o.fotoIds);
    if (o.modeloIds) cuerpo.modelo_ids = uniq(o.modeloIds);
    var r = await window.lwFichero(c, 'creatividad', 'guarda', cuerpo);
    return r.fila;
  }
  function uniq(a) { return (a || []).filter(function (x, i, t) { return x && t.indexOf(x) === i; }); }

  /* Abre una creatividad: su fila y su estado de editor, YA limpio. */
  async function abrir(id) {
    var c = await sb();
    var fila = falla(await c.from('creatividades').select('*').eq('id', id).single());
    if (!fila.estado_path) return { fila: fila, estado: null };
    var blob = falla(await c.storage.from(BUCKET).download(fila.estado_path));
    var txt = await blob.text();
    var estado;
    try { estado = JSON.parse(txt); } catch (e) { throw new Error('El estado guardado no es un JSON válido.'); }
    if (!estado || typeof estado !== 'object' || Array.isArray(estado)) throw new Error('El estado guardado no tiene la forma esperada.');
    return { fila: fila, estado: limpiaEstado(estado) };
  }

  async function listar(filtro) {
    var c = await sb();
    var q = c.from('creatividades')
      .select('id, tipo, titulo, proyecto_id, formato, arquetipo, estado, path, estado_path, portada_path, lleva_render, precios_a, origen, creado_por, creado_en, actualizado_en, enviada_por, enviada_en, aprobada_en, publicada_en, archivada_en')
      .order('creado_en', { ascending: false }).limit(500);
    if (filtro && filtro.tipo) q = q.eq('tipo', filtro.tipo);
    if (filtro && filtro.estado) q = q.eq('estado', filtro.estado);
    if (filtro && filtro.proyecto_id) q = q.eq('proyecto_id', filtro.proyecto_id);
    return falla(await q) || [];
  }

  async function cambiarEstado(id, estado) {
    var c = await sb();
    return falla(await c.rpc('creatividad_estado', { p_id: id, p_estado: estado }));
  }

  /* URL firmada CORTA y pedida al pulsar (Seguridad #5): la autorización se evalúa
     al firmar, así que no se guarda ni se reparte. Antes deja rastro de la descarga
     (Legal #5) por la RPC, que también comprueba que el fichero es de esa fila. */
  async function urlDescarga(id, fichero, nombre) {
    var c = await sb();
    falla(await c.rpc('creatividad_descarga', { p_id: id, p_fichero: fichero }));
    var r = falla(await c.storage.from(BUCKET).createSignedUrl(fichero, 120, nombre ? { download: nombre } : undefined));
    return r.signedUrl;
  }
  // Para pintar una miniatura dentro de la página: sin rastro de descarga (no sale del navegador).
  async function urlVer(fichero) {
    var c = await sb();
    var r = falla(await c.storage.from(BUCKET).createSignedUrl(fichero, 300));
    return r.signedUrl;
  }

  /* Fotos de la intranet (`deck_fotos`). La foto viaja por ID y nunca se acepta
     una URL libre de un estado guardado (Seguridad #4). Desde AXW-66 (28-sep-2026)
     las de proyectos sin deck abierto viven en el bucket PRIVADO `deck-privado`:
     la URL la da el servidor por id (`lwFotoUrls`, guard.js; firmada 1 h si es
     privada) y NO se guarda en ningún estado. Dos pasos separados a propósito:
     leer las filas (`filasFotos`, pasará a lwDatos en L4) y resolver sus URL.
     Si el servidor no da las URL, RECHAZA (`.clave = 'urls_fallan'`): la pantalla
     no puede confundirlo con «este proyecto no tiene fotos». */
  async function filasFotos(c, filtro) {
    var q = c.from('deck_fotos').select('id, ambito, proyecto_id, modelo_id, tipo, uso, path, pie, orden')
      .order('orden', { ascending: true }).limit(1000);
    if (filtro && filtro.proyecto_id) q = q.eq('proyecto_id', filtro.proyecto_id);
    if (filtro && filtro.modelo_id) q = q.eq('modelo_id', filtro.modelo_id);
    if (filtro && filtro.ambito) q = q.eq('ambito', filtro.ambito);
    return falla(await q) || [];
  }
  function urlsDe(c, filas) {
    if (typeof window.lwFotoUrls !== 'function') return Promise.reject(Object.assign(new Error('Falta guard.js actualizado: recarga la página'), { clave: 'urls_fallan' }));
    return window.lwFotoUrls(c, filas).then(function (r) { return r.urls; });
  }
  async function fotos(filtro) {
    var c = await sb();
    var filas = await filasFotos(c, filtro);
    var urls = await urlsDe(c, filas);
    return filas.map(function (f) {
      f.url = urls[f.id] || null;               // null: la fila existe pero su fichero no
      f.esRender = f.tipo !== 'foto';            // 'render' e 'ia' (Datos #1)
      f.rotulo = (f.pie && (f.pie.es || f.pie.en)) || '';
      return f;
    });
  }
  async function urlFoto(fotoId) {
    var c = await sb();
    var urls = await urlsDe(c, [String(fotoId)]);
    return urls[fotoId] || null;
  }

  async function bloqueLegal(clave, idioma) {
    var c = await sb();
    var r = falla(await c.from('bloques_legales').select('texto, version, estado')
      .eq('clave', clave).eq('idioma', idioma === 'es' ? 'es' : 'en')
      .order('version', { ascending: false }).limit(1));
    return (r && r[0]) || null;
  }

  /* `pendiente` = «para aprobar» (rediseño A, 24-sep): quien hace la pieza la envía
     y un admin la aprueba o la devuelve. Congelada como cualquier estado que no es
     borrador: lo que se aprueba es lo que se envió. */
  var ESTADOS = { borrador: 'Borrador', pendiente: 'Para aprobar', aprobada: 'Aprobada', publicada: 'Publicada', archivada: 'Archivada' };

  window.lwCreatividades = {
    guardar: guardar, abrir: abrir, listar: listar, cambiarEstado: cambiarEstado,
    urlDescarga: urlDescarga, urlVer: urlVer, fotos: fotos, urlFoto: urlFoto,
    bloqueLegal: bloqueLegal, limpia: limpia, limpiaEstado: limpiaEstado, ESTADOS: ESTADOS
  };
})();
