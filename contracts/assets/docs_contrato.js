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
     · en `orden`; desempate por subido_en y después por id (estable).
   El servidor guarda la casilla y el orden (supabase/migrations/
   20260927230000_modelo_documentos_en_contrato_dosier.sql); aquí solo se lee.

   Los TIPOS van aquí también: son los del CHECK de la tabla, y
   docs_contrato.test.js compara esta lista con la migración, la edge
   `ficheros` y las RPC. */
(function (g) {
  var TIPOS = [['plano', 'Plano'], ['calidades', 'Memoria de calidades'], ['ficha', 'Ficha'],
               ['render', 'Render'], ['dosier', 'Dosier'], ['otro', 'Otro']];

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
     los de «Todos los techos»). */
  function entran(docs, techo) {
    techo = techo || '';
    return ordena((docs || []).filter(function (d) {
      return d && d.en_contrato === true && (!d.techo_clave || d.techo_clave === techo);
    }));
  }
  g.lwDocsContrato = { TIPOS: TIPOS, etiqueta: etiqueta, ordena: ordena, entran: entran };
})(typeof window !== 'undefined' ? window : globalThis);
