/* ═══════════════════════════════════════════════════════════════════════════
   FRASES VETADAS · lo que el material publicitario de Lawang no puede decir
   24-sep-2026 · revisión previa #68 (Legal), encargo Creatividades v4
   ═══════════════════════════════════════════════════════════════════════════
   DUEÑO: el departamento LEGAL. Cualquier cambio de esta lista pasa por Legal
   (departamentos/legal/prompt.md). No es una lista de estilo: cada grupo es un
   riesgo de publicidad engañosa (UU 8/1999 de Protección al Consumidor; Ley
   3/1991 de Competencia Desleal si va a compradores españoles) o de titularidad
   imposible para un extranjero en Indonesia.

   La usan el generador de redes y el constructor de dossiers, y BLOQUEA guardar
   y descargar: un aviso que se puede ignorar es un aviso que se ignora.
   Los bloques FIJOS de Legal (`bloques_legales`, p. ej. «Cómo se compra», que
   nombra Hak Milik para decir que NO se adquiere) no pasan por aquí.

   Regla de las dos rutas (owner, 24-sep-2026, para TODOS los proyectos): no se
   comprueba con una expresión regular —una pieza 4:5 no cabe las dos rutas en
   el titular—, se cumple POR CONSTRUCCIÓN: si el texto menciona la tenencia, la
   pieza lleva pegada la línea `LW_DOS_RUTAS` (lwFrases.hablaDeTenencia).

   Carga: script clásico, sin dependencias. Expone `window.lwFrases`. En Node
   (contracts/frases_vetadas.test.js) se exporta con module.exports.
   ═══════════════════════════════════════════════════════════════════════════ */
(function (raiz) {
  'use strict';

  /* Texto → forma comparable: minúsculas, sin acentos, sin etiquetas ni
     entidades, espacios colapsados. «Rentabilidad», «RENTABILIDAD» y
     «renta<b>bilidad</b>» tienen que caer igual. */
  function normaliza(t) {
    return String(t == null ? '' : t)
      .replace(/<br\s*\/?>/gi, ' ')
      .replace(/<[^>]*>/g, '')
      .replace(/&nbsp;/gi, ' ').replace(/&amp;/gi, '&').replace(/&#39;|&apos;/gi, "'")
      .replace(/&quot;/gi, '"').replace(/&lt;/gi, '<').replace(/&gt;/gi, '>')
      .toLowerCase()
      .normalize('NFD').replace(/[̀-ͯ]/g, '')
      .replace(/[*_]/g, '')            // la sintaxis *beige* del titular no parte palabras
      .replace(/\s+/g, ' ').trim();
  }

  // grupo · expresión (sobre el texto normalizado) · qué se le dice a quien escribe
  var REGLAS = [
    // ── Titularidad ──
    ['titularidad', /\bhak milik\b/, 'Hak Milik solo lo pueden tener ciudadanos indonesios: no se ofrece.'],
    ['titularidad', /\bfreehold\b(?!\s*\(?\s*hgb)/, '«Freehold» solo como «Freehold (HGB)», y siempre con la otra ruta (Hak Sewa).'],
    ['titularidad', /\bnominee\b/, 'No se usan estructuras nominee.'],
    ['titularidad', /\b(full|absolute) ownership\b|\bown the land\b|\b(land|title|certificate) in your name\b|\b100\s?% ownership\b/, 'Promete una propiedad que un extranjero no puede tener.'],
    ['titularidad', /\bpropiedad plena\b|\ben propiedad\b|\b(escritura )?a tu nombre\b|\bsertifikat atas nama\b/, 'Promete una propiedad que un extranjero no puede tener.'],
    // ── Rentabilidad ──
    ['rentabilidad', /\broi\b|\byields?\b|\brental income\b|\bpassive income\b|\breturns?\s+on\b|\breturns\b|\bappreciation\b|\bcapital growth\b|\bpayback\b|\bpays for itself\b/, 'No se prometen rentabilidades ni revalorización.'],
    ['rentabilidad', /\brentabilidad\b|\brendimiento\b|\bretorno\b|\bingresos pasivos\b|\bingresos por alquiler\b|\brevalorizacion\b|\bplusvalia\b|\bse paga sola\b|\bduplica/, 'No se prometen rentabilidades ni revalorización.'],
    ['rentabilidad', /\d+\s?%\s*(p\.?\s?a\.?|per year|yearly|annual|anual|al ano)/, 'Un porcentaje anual se lee como rentabilidad prometida.'],
    // ── Garantías ──
    ['garantia', /\bguarantee[ds]?\b|\brisk[- ]free\b|\bsafe investment\b|\bfully legal\b|\b100\s?% legal\b|\bbuy-?back\b/, 'No se garantiza nada que dependa del mercado o de un tercero.'],
    ['garantia', /\bgarantizad[oa]s?\b|\bgarantia de\b|\bsin riesgo\b|\binversion segura\b|\btotalmente legal\b|\brecompra\b/, 'No se garantiza nada que dependa del mercado o de un tercero.'],
    // ── Escasez y urgencia ──
    ['escasez', /\bonly \d+( \w+)? (left|remaining|available)\b|\blast \d+\b|\bselling fast\b|\bsold out soon\b|\blimited time\b|\bact now\b|\bprices? (will )?(rise|go up)\b/, 'Escasez o urgencia que no sale de un dato: no.'],
    ['escasez', /\bultim[oa]s \d+\b|\bquedan \d+\b|\bse agotan\b|\btiempo limitado\b|\boferta termina\b|\bel precio sube\b/, 'Escasez o urgencia que no sale de un dato: no.']
  ];

  // Hablar de tenencia obliga a llevar las dos rutas (por construcción, ver cabecera).
  var TENENCIA = /\b(freehold|hgb|hak sewa|leasehold|arrendamiento|ownership|propiedad|hak pakai|pt pma|titularidad|tenencia)\b/;

  /* Revisa uno o varios textos. Devuelve [{grupo, frase, motivo}] — vacío si pasa.
     `frase` es el trozo que casó, para enseñárselo a quien escribe. */
  function revisa(textos) {
    var hallazgos = [];
    [].concat(textos || []).forEach(function (t) {
      var n = normaliza(t);
      if (!n) return;
      REGLAS.forEach(function (r) {
        var m = n.match(r[1]);
        if (m && !hallazgos.some(function (h) { return h.frase === m[0] && h.grupo === r[0]; })) {
          hallazgos.push({ grupo: r[0], frase: m[0], motivo: r[2] });
        }
      });
    });
    return hallazgos;
  }

  function hablaDeTenencia(textos) {
    return [].concat(textos || []).some(function (t) { return TENENCIA.test(normaliza(t)); });
  }

  // Etiquetas que van GRABADAS en la pieza o el PDF, nunca solo en el texto del post (Legal #2).
  var ETIQUETAS = {
    render: { es: 'Render · imagen ilustrativa, no contractual', en: 'Render · illustrative image, not contractual' },
    plano:  { es: 'Plano orientativo, no a escala · superficies y linderos según contrato',
              en: 'Indicative plan, not to scale · areas and boundaries as per contract' },
    dosRutas: { es: 'Freehold (HGB) vía PT PMA · o Hak Sewa sin empresa',
                en: 'Freehold (HGB) via PT PMA · or Hak Sewa without a company' },
    // {fecha} = la fecha de la lista de la que sale el precio. Obligatorio con precio (Legal #4).
    precios: { es: 'Precios de lista a {fecha}, orientativos y sujetos a disponibilidad. El precio vinculante, su importe en IDR y los impuestos aplicables se fijan en el contrato. Este documento no es una oferta vinculante.',
               en: 'List prices as of {fecha}, indicative and subject to availability. The binding price, its IDR amount and applicable taxes are set in the contract. This document is not a binding offer.' }
  };
  function etiqueta(clave, idioma, fecha) {
    var e = ETIQUETAS[clave];
    if (!e) return '';
    var t = e[idioma === 'es' ? 'es' : 'en'];
    return fecha ? t.replace('{fecha}', fecha) : t;
  }

  var api = { normaliza: normaliza, revisa: revisa, hablaDeTenencia: hablaDeTenencia, etiqueta: etiqueta, REGLAS: REGLAS };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else raiz.lwFrases = api;
})(typeof window !== 'undefined' ? window : this);
