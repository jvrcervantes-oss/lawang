/* Datos que se escriben UNA vez y el contrato imprime en tres idiomas.
   REV03 (7-oct-2026): el comprador revisó el borrador y vio «España» y «(promoción)»
   dentro de la columna indonesia. El contrato guarda un solo valor por campo
   (`adq1_nacionalidad`, `descuento_comercial_motivo`) y la plantilla lo pegaba igual
   en los tres párrafos; los hitos ya llevan es/en/id propios, estos no.

   Aquí vive la traducción. Fuera de app.html para poder probarla (traduce_campos.test.js)
   y para que el editor, la vista previa y el PDF lean la MISMA tabla.

   - NACIONALIDAD: tabla acotada a lo que existe de verdad en contratos y fichas
     (medido 7-oct-2026: 25 valores distintos, en español y alguno en inglés:
     «Spanish», «Netherlands»). Se busca sin mayúsculas ni tildes. Un valor que no está
     en la tabla devuelve null: el documento imprime lo que hay (no se inventa un país)
     y quien llama decide si avisa.
   - MOTIVO DEL DESCUENTO: lista cerrada. El valor GUARDADO es el texto en español
     (los triggers de descuento exigen que no esté vacío y no cambian). Los motivos
     antiguos escritos a mano que no son de la lista devuelven null y el documento
     imprime el descuento sin el paréntesis del motivo en inglés e indonesio. */
(function (raiz) {
  const sinTildes = s => String(s == null ? '' : s).normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/\s+/g, ' ').trim();

  const PAISES = [
    [['espana', 'espanola', 'espanol', 'spanish', 'spain'],            { en: 'Spain',         id: 'Spanyol' }],
    [['indonesia', 'indonesian'],                                      { en: 'Indonesia',     id: 'Indonesia' }],
    [['argentina', 'argentine'],                                       { en: 'Argentina',     id: 'Argentina' }],
    [['italia', 'italiana', 'italiano', 'italian'],                    { en: 'Italy',         id: 'Italia' }],
    [['francia', 'francesa', 'frances', 'french'],                     { en: 'France',        id: 'Prancis' }],
    [['turquia', 'turca', 'turco', 'turkish'],                         { en: 'Turkey',        id: 'Turki' }],
    [['cuba', 'cubana', 'cubano', 'cuban'],                            { en: 'Cuba',          id: 'Kuba' }],
    [['colombia', 'colombiana', 'colombiano', 'colombian'],            { en: 'Colombia',      id: 'Kolombia' }],
    [['estados unidos', 'eeuu', 'ee.uu.', 'usa', 'american'],          { en: 'United States', id: 'Amerika Serikat' }],
    [['suiza', 'suizo', 'suiza', 'swiss'],                             { en: 'Switzerland',   id: 'Swiss' }],
    [['china', 'chino', 'china', 'chinese'],                           { en: 'China',         id: 'Tiongkok' }],
    [['portugal', 'portuguesa', 'portugues', 'portuguese'],            { en: 'Portugal',      id: 'Portugal' }],
    [['paises bajos', 'holanda', 'neerlandesa', 'neerlandes', 'netherlands', 'dutch'], { en: 'Netherlands', id: 'Belanda' }],
    [['moldavia', 'moldava', 'moldova'],                               { en: 'Moldova',       id: 'Moldova' }],
    [['rusia', 'rusa', 'ruso', 'russia', 'russian'],                   { en: 'Russia',        id: 'Rusia' }],
  ];
  const PAIS_POR_CLAVE = {};
  PAISES.forEach(([claves, t]) => claves.forEach(k => { PAIS_POR_CLAVE[k] = t; }));

  // [texto guardado (es), en, id, variantes antiguas que se reconocen]
  const MOTIVOS_DESCUENTO = [
    { es: 'Promoción',               en: 'Promotion',               id: 'Promosi',                                alias: ['promocion'] },
    { es: 'Oferta',                  en: 'Special offer',           id: 'Penawaran khusus',                       alias: ['oferta'] },
    { es: 'Precio anterior pactado', en: 'Previously agreed price', id: 'Harga sebelumnya yang telah disepakati', alias: ['precio anterior pactado', 'precio anterior', 'precio antiguo', 'precio antiguo pactado', 'precio pactado'] },
    { es: 'Descuento comercial',     en: 'Commercial discount',     id: 'Diskon komersial',                       alias: ['descuento comercial'] },
  ];
  const MOTIVO_POR_CLAVE = {};
  MOTIVOS_DESCUENTO.forEach(m => [m.es].concat(m.alias).forEach(k => { MOTIVO_POR_CLAVE[sinTildes(k)] = m; }));

  // Devuelve la traducción en 'en' | 'id', o null si el valor no está en la tabla.
  function trNacionalidad(valor, lang) {
    const t = PAIS_POR_CLAVE[sinTildes(valor)];
    return t && t[lang] ? t[lang] : null;
  }
  function trMotivoDescuento(valor, lang) {
    const m = MOTIVO_POR_CLAVE[sinTildes(valor)];
    return m && m[lang] ? m[lang] : null;
  }
  // Los textos que se ofrecen en el selector (valor guardado = español).
  const motivosDescuentoOpciones = () => MOTIVOS_DESCUENTO.map(m => m.es);

  const api = { trNacionalidad, trMotivoDescuento, motivosDescuentoOpciones, MOTIVOS_DESCUENTO };
  if (typeof module !== 'undefined') module.exports = api;
  else Object.assign(raiz, api);
})(typeof window !== 'undefined' ? window : globalThis);
