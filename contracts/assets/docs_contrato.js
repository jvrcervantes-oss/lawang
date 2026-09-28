/* QUÉ DOCUMENTOS DEL MODELO ENTRAN EN EL CONTRATO DE OBRA — 27-sep-2026 (owner).
   ═══════════════════════════════════════════════════════════════════════════
   Fuente ÚNICA de la regla, en el navegador. La usan las dos pantallas que la
   necesitan y que no se pueden contradecir:
     · el generador de contratos (documento_anexos.js) — adjunta esto;
     · la ficha del modelo (intranet/v4/assets/ficha_modelo.js) — enseña, por
       techo, qué se va a adjuntar, ANTES de guardar.
   Si la regla vive dos veces, el resumen de la ficha dice una cosa y el
   contrato adjunta otra: justo lo que el owner no puede comprobar a ojo.

   La regla (decisión del owner, 27-sep-2026):
     · entra todo documento con `en_contrato = true` (la casilla «Se incluye
       automáticamente en el contrato», que solo cambia administración);
     · de techo X solo si el contrato tiene techo X; sin techo («Todos los
       techos», techo_clave NULL) entra siempre;
     · el DOSIER nunca (owner, 28-sep-2026): es comercial. La base ya no deja
       marcarlo; aquí se filtra también, por si llega uno.
   El servidor guarda la casilla y el orden (supabase/migrations/
   20260927230000_modelo_documentos_en_contrato_dosier.sql); aquí solo se lee.

   LETRAS DE APÉNDICE (owner y Legal, 28-sep-2026). El contrato de Construcción
   (contracts/templates/ppjb_construccion.html, Arts. 1, 2, 3, 8 y 15.1) tiene UN solo
   apéndice vinculante: el A – Planos Arquitectónicos. La prelación es Contrato →
   Apéndice A; cualquier otro adjunto (memorias de calidades, fichas, renders…) es
   INFORMATIVO con independencia de su rótulo, y el material comercial queda fuera.
   Por eso:
     · plano → Apéndice A (vinculante). Varios planos en un contrato: A1, A2… en el
       orden de Modelos.
     · el resto, en este orden de TIPO: calidades → ficha → render → otro, y dentro de
       cada tipo en el orden de Modelos, con letras CONSECUTIVAS desde la B, sin huecos
       (B, C, D…), todos marcados «(informativo)». La letra de uno informativo depende
       de cuántos van delante en ESE contrato; lo que no cambia es el orden por tipo.
     · el dosier, nunca.
   El orden de Modelos nunca cambia el tipo de un documento ni lo pasa por delante de
   otro tipo: solo ordena dentro del mismo tipo. El título editable, tampoco.

   Los TIPOS van aquí también: son los del CHECK de la tabla, y
   docs_contrato.test.js compara esta lista con la migración, la edge
   `ficheros` y las RPC. */
(function (g) {
  var TIPOS = [['plano', 'Plano'], ['calidades', 'Memoria de calidades'], ['ficha', 'Ficha'],
               ['render', 'Render'], ['dosier', 'Dosier'], ['otro', 'Otro']];

  // Orden de los tipos en el contrato. Solo el plano es vinculante (Apéndice A).
  var ORDEN_TIPOS = ['plano', 'calidades', 'ficha', 'render', 'otro'];
  var INFORMATIVO = { calidades: 1, ficha: 1, render: 1, otro: 1 };
  function grupo(tipo) { var i = ORDEN_TIPOS.indexOf(tipo); return i < 0 ? 99 : i; }
  /* Títulos trilingües (Legal, 28-sep-2026). El del plano, el de la plantilla tal cual.
     ID de calidades, ficha y render: PENDIENTE DE REVISIÓN DE TRADUCTOR (`revisar`). */
  var TITULO = {
    plano: { es: 'Planos Arquitectónicos', en: 'Architectural Drawings', id: 'Gambar Arsitektur' },
    calidades: { es: 'Memoria de calidades', en: 'Quality Specifications', id: 'Spesifikasi Mutu', revisar: 'id' },
    ficha: { es: 'Ficha de la vivienda', en: 'Home Fact Sheet', id: 'Lembar Data Rumah', revisar: 'id' },
    render: { es: 'Renders', en: 'Renderings', id: 'Gambar Render', revisar: 'id' }
  };
  var MARCA_INFORMATIVO = { es: ' (informativo)', en: ' (for information)', id: ' (informatif)' };
  var PALABRA = { es: 'Apéndice', en: 'Appendix', id: 'Lampiran' };

  function etiqueta(tipo) {
    for (var i = 0; i < TIPOS.length; i++) if (TIPOS[i][0] === tipo) return TIPOS[i][1];
    return tipo || '—';
  }
  function ordena(docs) {
    return (docs || []).slice().sort(function (a, b) {
      return ((a.orden || 0) - (b.orden || 0))
        || String(a.subido_en || '').localeCompare(String(b.subido_en || ''))
        || String(a.id || '').localeCompare(String(b.id || ''));
    });
  }
  /* Los que entran en un contrato con ese techo ('' = sin techo elegido: solo
     los de «Todos los techos»), en el orden de Modelos. */
  function entran(docs, techo) {
    techo = techo || '';
    return ordena((docs || []).filter(function (d) {
      return d && d.en_contrato === true && d.tipo !== 'dosier' && grupo(d.tipo) < 99
        && (!d.techo_clave || d.techo_clave === techo);
    }));
  }
  /* Título del documento en los tres idiomas. `otro`: el nombre del fichero. */
  function titulo(d) {
    var t = TITULO[d.tipo];
    var base = t ? { es: t.es, en: t.en, id: t.id }
      : (function (n) { return { es: n, en: n, id: n }; })(String(d.nombre || 'Documento').replace(/\.[^.]+$/, ''));
    if (INFORMATIVO[d.tipo]) { base.es += MARCA_INFORMATIVO.es; base.en += MARCA_INFORMATIVO.en; base.id += MARCA_INFORMATIVO.id; }
    return base;
  }
  /* Los apéndices de un contrato con ese techo, ya con su letra y su rótulo trilingüe:
     los planos, A (A1, A2… si hay varios); el resto, B, C, D… consecutivas, por tipo
     (calidades, ficha, render, otro) y, dentro de cada tipo, por el orden de Modelos. */
  function apendices(docs, techo) {
    var l = entran(docs, techo).map(function (d, i) { return { d: d, i: i, g: grupo(d.tipo) }; });
    l.sort(function (a, b) { return (a.g - b.g) || (a.i - b.i); });
    var planos = l.filter(function (x) { return x.d.tipo === 'plano'; }).length;
    var np = 0, siguiente = 'B'.charCodeAt(0);
    return l.map(function (x) {
      var letra;
      if (x.d.tipo === 'plano') letra = 'A' + (planos > 1 ? String(++np) : '');
      else letra = String.fromCharCode(siguiente++);
      return { doc: x.d, letra: letra, informativo: !!INFORMATIVO[x.d.tipo], titulo: titulo(x.d),
               rotulo: { es: PALABRA.es + ' ' + letra, en: PALABRA.en + ' ' + letra, id: PALABRA.id + ' ' + letra } };
    });
  }
  g.lwDocsContrato = { TIPOS: TIPOS, ORDEN_TIPOS: ORDEN_TIPOS, grupo: grupo, etiqueta: etiqueta, ordena: ordena, entran: entran,
                       titulo: titulo, apendices: apendices };
})(typeof window !== 'undefined' ? window : globalThis);
