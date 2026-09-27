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

   LETRA DE APÉNDICE POR TIPO (owner, 28-sep-2026, tras la consulta de Legal): el
   Art. 3 de la plantilla de Construcción (contracts/templates/ppjb_construccion.html)
   nombra «Apéndice A – Planos Arquitectónicos», «B – Especificaciones Técnicas»,
   «C – Brochure». Un contrato que remite al Apéndice B tiene que llevar en la B
   las especificaciones, no lo que haya quedado segundo en una lista. Por eso la
   letra la pone el TIPO, nunca el orden de Modelos (que solo ordena dentro de una
   misma letra) ni el título: plano → A, calidades → B; ficha, render y otro van
   como INFORMATIVOS, de la D en adelante (ficha D, render E, otro F; la C, brochure,
   queda para cuando exista ese tipo). Dos documentos con la misma letra en un
   contrato salen A1, A2…

   Los TIPOS van aquí también: son los del CHECK de la tabla, y
   docs_contrato.test.js compara esta lista con la migración, la edge
   `ficheros` y las RPC. */
(function (g) {
  var TIPOS = [['plano', 'Plano'], ['calidades', 'Memoria de calidades'], ['ficha', 'Ficha'],
               ['render', 'Render'], ['dosier', 'Dosier'], ['otro', 'Otro']];

  var LETRA = { plano: 'A', calidades: 'B', ficha: 'D', render: 'E', otro: 'F' };
  var INFORMATIVO = { ficha: 1, render: 1, otro: 1 };
  /* Títulos trilingües del apéndice (Legal, 28-sep-2026). A y B, los de la plantilla
     tal cual. ID de ficha y render: PENDIENTE DE REVISIÓN DE TRADUCTOR (marcadas
     con `revisar`); las de A y B son las mismas palabras que ya firma la plantilla. */
  var TITULO = {
    plano: { es: 'Planos Arquitectónicos', en: 'Architectural Drawings', id: 'Gambar Arsitektur' },
    calidades: { es: 'Especificaciones Técnicas', en: 'Technical Specifications', id: 'Spesifikasi Teknis' },
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
      return d && d.en_contrato === true && d.tipo !== 'dosier' && LETRA[d.tipo]
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
  /* Los apéndices de un contrato con ese techo: ordenados por LETRA y, dentro, por el
     orden de Modelos. Cada uno con su letra final (A, o A1/A2 si comparten) y su
     rótulo trilingüe. */
  function apendices(docs, techo) {
    var l = entran(docs, techo).map(function (d, i) { return { d: d, i: i, base: LETRA[d.tipo] }; });
    l.sort(function (a, b) { return a.base < b.base ? -1 : a.base > b.base ? 1 : a.i - b.i; });
    var cuenta = {}; l.forEach(function (x) { cuenta[x.base] = (cuenta[x.base] || 0) + 1; });
    var visto = {};
    return l.map(function (x) {
      visto[x.base] = (visto[x.base] || 0) + 1;
      var letra = x.base + (cuenta[x.base] > 1 ? String(visto[x.base]) : '');
      return { doc: x.d, letra: letra, informativo: !!INFORMATIVO[x.d.tipo], titulo: titulo(x.d),
               rotulo: { es: PALABRA.es + ' ' + letra, en: PALABRA.en + ' ' + letra, id: PALABRA.id + ' ' + letra } };
    });
  }
  g.lwDocsContrato = { TIPOS: TIPOS, LETRA: LETRA, etiqueta: etiqueta, ordena: ordena, entran: entran,
                       titulo: titulo, apendices: apendices };
})(typeof window !== 'undefined' ? window : globalThis);
