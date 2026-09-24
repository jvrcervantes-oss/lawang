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

  function sello() { return Date.now(); }

  /* Guarda (crea o actualiza un BORRADOR). `o`:
     { id?, tipo:'pieza'|'dossier', titulo, proyecto_id?, formato?, arquetipo?, precios_a?,
       estado: <objeto del editor>, png?: Blob, portada?: Blob, fotoIds?: [uuid], modeloIds?: [uuid] }
     Devuelve la fila guardada. */
  async function guardar(o) {
    var c = await sb();
    var base = {
      titulo: String(o.titulo || '').trim().slice(0, 200) || 'Sin título',
      proyecto_id: o.proyecto_id || null,
      formato: o.formato || null,
      arquetipo: o.arquetipo || null,
      precios_a: o.precios_a || null
    };
    var id = o.id;
    if (!id) {
      var nueva = falla(await c.from('creatividades').insert(Object.assign({ tipo: o.tipo }, base)).select('id').single());
      id = nueva.id;
    }
    var ts = sello(), cambios = Object.assign({}, base);
    cambios.estado_path = id + '/estado-' + ts + '.json';
    falla(await c.storage.from(BUCKET).upload(cambios.estado_path,
      new Blob([JSON.stringify(o.estado || {})], { type: 'application/json' }),
      { contentType: 'application/json', upsert: false }));
    if (o.png) {
      cambios.path = id + '/pieza-' + ts + '.png';
      falla(await c.storage.from(BUCKET).upload(cambios.path, o.png, { contentType: 'image/png', upsert: false }));
    }
    // Miniatura de la portada de un dossier (rediseño A, 24-sep): la biblioteca la
    // enseña en vez de una caja gris. Una pieza no la necesita: su PNG ya es la imagen.
    if (o.portada) {
      cambios.portada_path = id + '/portada-' + ts + '.png';
      falla(await c.storage.from(BUCKET).upload(cambios.portada_path, o.portada, { contentType: 'image/png', upsert: false }));
    }
    var fila = falla(await c.from('creatividades').update(cambios).eq('id', id).select('*').single());
    // Enlaces: se reponen enteros. La base rechaza tocarlos si ya no es borrador.
    if (o.fotoIds) {
      falla(await c.from('creatividad_fotos').delete().eq('creatividad_id', id));
      var fotos = uniq(o.fotoIds).map(function (f) { return { creatividad_id: id, foto_id: f }; });
      if (fotos.length) falla(await c.from('creatividad_fotos').insert(fotos));
    }
    if (o.modeloIds) {
      falla(await c.from('creatividad_modelos').delete().eq('creatividad_id', id));
      var mods = uniq(o.modeloIds).map(function (m) { return { creatividad_id: id, modelo_id: m }; });
      if (mods.length) falla(await c.from('creatividad_modelos').insert(mods));
    }
    // `lleva_render` lo ha recalculado el trigger: se relee la fila.
    return falla(await c.from('creatividades').select('*').eq('id', id).single());
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

  /* Fotos de la intranet (`deck_fotos`, bucket público `deck`). La foto viaja
     por ID; la URL se compone aquí y nunca se acepta una URL libre de un estado
     guardado (Seguridad #4). */
  async function fotos(filtro) {
    var c = await sb();
    var q = c.from('deck_fotos').select('id, ambito, proyecto_id, modelo_id, tipo, uso, path, pie, orden')
      .order('orden', { ascending: true }).limit(1000);
    if (filtro && filtro.proyecto_id) q = q.eq('proyecto_id', filtro.proyecto_id);
    if (filtro && filtro.modelo_id) q = q.eq('modelo_id', filtro.modelo_id);
    if (filtro && filtro.ambito) q = q.eq('ambito', filtro.ambito);
    var filas = falla(await q) || [];
    return filas.map(function (f) {
      f.url = c.storage.from('deck').getPublicUrl(f.path).data.publicUrl;
      f.esRender = f.tipo !== 'foto';            // 'render' e 'ia' (Datos #1)
      f.rotulo = (f.pie && (f.pie.es || f.pie.en)) || '';
      return f;
    });
  }
  async function urlFoto(fotoId) {
    var c = await sb();
    var f = falla(await c.from('deck_fotos').select('path').eq('id', fotoId).maybeSingle());
    return f ? c.storage.from('deck').getPublicUrl(f.path).data.publicUrl : null;
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
