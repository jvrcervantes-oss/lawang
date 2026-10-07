/* Cláusulas negociadas REV03 (2-oct-2026, owner) — ppjb_parcela + ppjb_construccion.
   ----------------------------------------------------------------------------
   Un comprador de Carmen recibió por escrito seis cambios. El owner decidió que
   son SOLO para él: un selector `clausulas_negociadas` ('' / 'si') que solo
   ven y cambian admin/super_admin (trigger clausulas_negociadas_rol en la base).

   Lo que este test sostiene, con el motor REAL de app.html (la regex se saca
   del fichero, no se copia) y con el del bot (bot/plantilla_texto.js):
     1. Sin el selector, NINGUNA frase REV03 se imprime — el resto de
        compradores firma lo de siempre — y la garantía cuenta «desde la
        Terminación» como antes.
     2. Con 'si', las seis frases salen en ES, EN e ID.
     3. Ningún bloque REV03 está anidado dentro de otro <!--if-->: el motor
        evalúa en UNA pasada y uno anidado se imprimiría siempre (así salía el
        «o DNI» en todos los contratos de persona hasta que este test lo cazó).
        El DNI va con `rev03_dni` (persona Y REV03) y el HGB con `rev03_hgb`
        (leasehold Y REV03): las estampa la base y collect() las calcula igual.
   node clausulas_negociadas.test.js */
const fs = require('fs');
const path = require('path');
const assert = require('assert');
const { plantillaTexto } = require('./bot/plantilla_texto.js');

const app = fs.readFileSync(path.join(__dirname, 'app.html'), 'utf8');
const linea = app.split('\n').find(l => l.trim().startsWith('html=html.replace(/<!--if:'));
assert(linea, 'no encuentro el motor de <!--if--> en app.html');
const motor = new Function('html', 'data', linea.trim() + '\nreturn html;');

const tpl = f => fs.readFileSync(path.join(__dirname, 'templates', f), 'utf8');
const PARCELA = tpl('ppjb_parcela.html');
const CONSTRUCCION = tpl('ppjb_construccion.html');

const FRASES = {
  'ppjb_parcela.html': [
    'con pasaporte o DNI nº', 'holder of passport or national ID card (DNI) no.', 'pemegang paspor atau Kartu Identitas (DNI) no.',
    'podrá titular el terreno bajo el régimen de Hak Guna Bangunan (HGB)',
    'the land may be held under the Hak Guna Bangunan (HGB) regime',
    'tanah dapat dimiliki dengan status Hak Guna Bangunan (HGB)',
    'La ejecución inicial de las zonas comunes, viales e instalaciones está incluida en el precio',
    'The initial construction of the common areas, roads and facilities is included in the price',
    'Pembangunan awal area bersama, jalan, dan fasilitas termasuk dalam harga',
  ],
  'ppjb_construccion.html': [
    'Pasaporte/DNI/Nº de identificación fiscal', 'Passport/National ID (DNI)/Tax ID no.', 'Paspor/Kartu Identitas (DNI)/Nomor Identifikasi Pajak',
    'El CONSTRUCTOR deberá notificar por escrito al ADQUIRIENTE la necesidad de prórroga',
    'The BUILDER shall notify the BUYER in writing of the need for an extension',
    'KONTRAKTOR wajib memberitahukan secara tertulis kepada PEMBELI mengenai kebutuhan perpanjangan',
    '12 (doce) meses desde la fecha de firma del acta de entrega al ADQUIRIENTE',
    '5 años desde la misma fecha', '5 years from the same date', '5 tahun sejak tanggal yang sama',
    '12 (twelve) months from the date of signature of the handover certificate',
    '12 (dua belas) bulan sejak tanggal penandatanganan berita acara serah terima',
  ],
};
const ESTANDAR = {
  'ppjb_parcela.html': ['con pasaporte nº', 'holder of passport no.', 'pemegang paspor no.'],
  'ppjb_construccion.html': ['12 (doce) meses desde la Terminación', '5 años desde la Terminación',
    '12 (twelve) months from Completion', '5 years from Completion',
    '12 (dua belas) bulan sejak Penyelesaian', '5 tahun sejak Penyelesaian', 'con Pasaporte/Nº de identificación fiscal'],
};
const DNI = [' o DNI', 'or national ID card (DNI)', 'atau Kartu Identitas (DNI)', 'DNI/', 'National ID (DNI)/'];
// Igual que collect() en app.html: rev03_dni = persona Y REV03.
const conRev03 = d => ({ ...d, clausulas_negociadas: 'si', rev03_dni: d.adq1_tipo === 'persona' ? 'si' : '',
  rev03_hgb: d.regimen_tenencia === 'leasehold' ? 'si' : '' });
// El párrafo HGB-vía-PT PMA solo con leasehold: con hgb repetiría su párrafo y con hak_milik contradiría el de SHM.
const HGB = ['podrá titular el terreno bajo el régimen de Hak Guna Bangunan (HGB)',
  'the land may be held under the Hak Guna Bangunan (HGB) regime', 'tanah dapat dimiliki dengan status Hak Guna Bangunan (HGB)'];
assert(app.includes("data.rev03_dni = (data.clausulas_negociadas === 'si' && data.adq1_tipo === 'persona') ? 'si' : '';")
  && app.includes("data.rev03_hgb = (data.clausulas_negociadas === 'si' && data.regimen_tenencia === 'leasehold') ? 'si' : '';"),
  'app.html: collect() ya no deriva rev03_dni/rev03_hgb como espera este test (y como los estampa la base)');
const limpia = h => h.replace(/<!--[\s\S]*?-->/g, '').replace(/<[^>]+>/g, '').replace(/\s+/g, ' ');

let n = 0;
for (const [f, html] of [['ppjb_parcela.html', PARCELA], ['ppjb_construccion.html', CONSTRUCCION]]) {
  for (const regimen of ['leasehold', 'hgb', 'hak_milik']) {
    const base = { adq1_tipo: 'persona', regimen_tenencia: regimen };
    const sin = limpia(motor(html, { ...base }));
    const vacio = limpia(motor(html, { ...base, clausulas_negociadas: '', rev03_dni: '' }));
    const con = limpia(motor(html, conRev03(base)));
    // Sociedad con REV03: el «o DNI» del párrafo de persona no puede colarse suelto.
    const empresa = limpia(motor(html, conRev03({ adq1_tipo: 'empresa', regimen_tenencia: regimen })));
    for (const fr of DNI) { assert(!empresa.includes(fr), f + ' (empresa+REV03): sale suelto «' + fr + '»'); n++; }
    assert.strictEqual(limpia(motor(html, { adq1_tipo: 'empresa', regimen_tenencia: regimen })).includes('BUYER I'), true);
    assert.strictEqual(sin, vacio, f + ': sin el campo y con el campo vacío deben imprimir lo mismo');
    for (const fr of FRASES[f]) {
      assert(!sin.includes(fr), f + ' (' + regimen + '): sin REV03 se imprime «' + fr + '»');
      if (HGB.includes(fr) && regimen !== 'leasehold')
        assert(!con.includes(fr), f + ' (' + regimen + '): con REV03 sale el HGB-vía-PT PMA fuera de leasehold');
      else assert(con.includes(fr), f + ' (' + regimen + '): con REV03 falta «' + fr + '»');
      n += 2;
    }
    for (const fr of ESTANDAR[f]) {
      assert(sin.includes(fr), f + ' (' + regimen + '): el texto estándar perdió «' + fr + '»');
      assert(!con.includes(fr), f + ' (' + regimen + '): con REV03 sigue el estándar «' + fr + '»');
      n += 2;
    }
  }
  // El motor del bot (edge bot-agentes) tiene que dar lo mismo.
  for (const lang of ['es', 'en', 'id']) {
    const sinBot = plantillaTexto(html, lang, { adq1_tipo: 'persona', regimen_tenencia: 'leasehold' });
    const conBot = plantillaTexto(html, lang, conRev03({ adq1_tipo: 'persona', regimen_tenencia: 'leasehold' }));
    const deEsteIdioma = FRASES[f].filter(fr => conBot.replace(/\s+/g, ' ').includes(fr));
    assert(deEsteIdioma.length >= 3, f + ' bot ' + lang + ': con REV03 salen solo ' + deEsteIdioma.length + ' frases');
    for (const fr of FRASES[f]) { assert(!sinBot.replace(/\s+/g, ' ').includes(fr), f + ' bot ' + lang + ': sin REV03 sale «' + fr + '»'); n++; }
  }
}

// 3. Ningún bloque clausulas_negociadas dentro de otro <!--if-->.
for (const [f, html] of [['ppjb_parcela.html', PARCELA], ['ppjb_construccion.html', CONSTRUCCION]]) {
  const re = /<!--if:([a-z0-9_]+)=[a-z0-9_]*-->([\s\S]*?)<!--\/if:\1-->/g;
  let m;
  while ((m = re.exec(html))) {
    for (const k of ['clausulas_negociadas', 'rev03_dni', 'rev03_hgb']) if (m[1] !== k) assert(!m[2].includes('<!--if:' + k + '='),
      f + ': un bloque ' + k + ' está anidado dentro de <!--if:' + m[1] + '--> y saldría siempre');
    n++;
  }
}

// 4. El campo existe en tokens.json y solo con la opción 'si' (vacío = estándar).
const tokens = JSON.parse(fs.readFileSync(path.join(__dirname, 'tokens.json'), 'utf8'));
const campo = tokens.sections.flatMap(s => s.fields).find(x => x[0] === 'clausulas_negociadas');
assert(campo && campo[2] === 'select' && campo[3].length === 2 && campo[3][0][0] === 'si' && campo[3][1][0] === 'rev04'
  && ['poder_titular', 'poder_apoderado', 'finca_shm_nib'].every(k => tokens.sections.flatMap(x => x.fields).some(x => x[0] === k && x[2] === 'text')), 'tokens.json: clausulas_negociadas debe ser select con las opciones «si» (REV03) y «rev04»');
n++;
// 4b. Es OPCIONAL: el candado «Faltan por rellenar» no puede exigirlo (5-oct-2026: a un agente le salía).
assert(/const CAMPOS_OPCIONALES = new Set\(\[[^\]]*'clausulas_negociadas'/.test(app), 'app.html: clausulas_negociadas tiene que estar en CAMPOS_OPCIONALES (vacío = estándar, no «falta»)');
n++;

// 5. Dónde se elige y dónde se ve (2-oct-2026, owner: «desde el listado o desde el asistente»).
const asi = fs.readFileSync(path.join(__dirname, 'assets', 'asistente-contrato.js'), 'utf8');
assert(/var SLUGS_REV03 = \['ppjb_parcela', 'ppjb_construccion'\];/.test(asi), 'asistente: el paso REV03 es solo de Parcela y Construcción');
assert(asi.includes("['super_admin', 'admin'].indexOf(MI_ROL) !== -1"), 'asistente: el paso REV03 es solo para admin/super_admin');
assert((asi.match(/if \(pideClausulas\(\)\) p\.push\(\['clausulas'/g) || []).length === 2, 'asistente: el paso REV03 tiene que estar en «venta nueva» y en «seguir una venta»');
assert(asi.includes("if (k === 'clausulas') return S.clausulas === 'estandar' || S.clausulas === 'rev03' || S.clausulas === 'rev04';"), 'asistente: el paso REV03 obliga a elegir');
// «Estándar» tiene que QUITAR el 'si' heredado: populateForm se salta los vacíos, así que se escribe a mano.
assert(asi.includes("cn.value = S.clausulas === 'rev04' ? 'rev04' : S.clausulas === 'rev03' ? 'si' : '';"), 'asistente: montaCondiciones no escribe el selector a mano');
const dv4 = fs.readFileSync(path.join(__dirname, '..', 'intranet', 'v4', 'assets', 'datos.js'), 'utf8');
assert(dv4.includes("select(CAMPOS_CONTRATO + ',rev03:datos_fields->>clausulas_negociadas')"), 'listado: no lee clausulas_negociadas');
assert(dv4.includes("(c.rev03 === 'si' ? ' <span title=\"Cláusulas negociadas (REV03)\">' + pill('REV03', 'curso')"), 'listado: no pinta la pastilla REV03');
n += 7;

// 6. Comportamiento (revisor, 2-oct): se EJECUTAN las funciones reales del asistente sobre un
//    selector simulado. «Estándar» quita el 'si' heredado, REV03 lo pone, y una venta REV03
//    llega preseleccionada (quitarla tiene que ser una elección visible, no un clic a ciegas).
{
  const trozo = (desde, hasta) => { const i = asi.indexOf(desde); const j = asi.indexOf(hasta, i); assert(i >= 0 && j > i, 'asistente: no encuentro ' + desde); return asi.slice(i, j); };
  const funciones = trozo('  var SLUGS_REV03', '  /* ── los pasos');
  const bloque = trozo('    /* REV03: se escribe a mano', '  async function montaNueva');
  const cuerpo = bloque.slice(0, bloque.lastIndexOf('}'));   // sin la llave que cierra montaCondiciones
  const corre = (estado, valorInicial, rol) => {
    const sel = { value: valorInicial, eventos: 0, dispatchEvent() { this.eventos++; } };
    const avisos = [];
    const f = new Function('S', 'MI_ROL', 'document', 'T', 'avisaMal', 'Event',
      funciones + String.fromCharCode(10) + cuerpo + String.fromCharCode(10) + 'return { clausulasDeSalida: clausulasDeSalida };');
    const r = f(estado, rol, { querySelector: q => (q === '[name="clausulas_negociadas"]' ? sel : null) }, x => x, m => avisos.push(m), function () {});
    return { sel, avisos, r };
  };
  const base = { slug: 'ppjb_construccion', camino: 'existente', venta: { rev03: true } };
  assert.strictEqual(corre({ ...base, clausulas: 'estandar' }, 'si', 'admin').sel.value, '', 'Estándar no quita el «si» heredado');
  assert.strictEqual(corre({ ...base, clausulas: 'rev03' }, '', 'super_admin').sel.value, 'si', 'REV03 no pone el «si»');
  assert.strictEqual(corre({ ...base, clausulas: 'rev03' }, '', 'agente').sel.value, '', 'un agente no puede poner REV03 desde el asistente');
  assert.strictEqual(corre({ ...base, slug: 'ppjb_reserva', clausulas: 'rev03' }, '', 'admin').sel.value, '', 'REV03 fuera de Parcela/Construcción');
  assert.strictEqual(corre({ ...base, clausulas: '' }, 'si', 'admin').r.clausulasDeSalida(), 'rev03', 'una venta REV03 no llega preseleccionada');
  assert.strictEqual(corre({ ...base, camino: 'nueva', venta: null, clausulas: '' }, '', 'admin').r.clausulasDeSalida(), '', 'venta nueva: no debe preseleccionar');
  n += 6;
  // REV04 (7-oct-2026): su valor es 'rev04' (no 'si'), y una venta REV04 llega preseleccionada.
  assert.strictEqual(corre({ ...base, venta: { rev04: true }, clausulas: 'rev04' }, '', 'admin').sel.value, 'rev04', 'REV04 no pone «rev04»');
  assert.strictEqual(corre({ ...base, venta: { rev04: true }, clausulas: 'estandar' }, 'rev04', 'admin').sel.value, '', 'Estándar no quita el «rev04» heredado');
  assert.strictEqual(corre({ ...base, venta: { rev04: true }, clausulas: 'rev03' }, 'rev04', 'admin').sel.value, 'si', 'REV03 no sustituye a REV04');
  assert.strictEqual(corre({ ...base, clausulas: 'rev04' }, '', 'agente').sel.value, '', 'un agente no puede poner REV04 desde el asistente');
  assert.strictEqual(corre({ ...base, venta: { rev04: true }, clausulas: '' }, 'rev04', 'admin').r.clausulasDeSalida(), 'rev04', 'una venta REV04 no llega preseleccionada');
  n += 5;
}

// 7. REV04 (7-oct-2026, owner: revisión legal «Horizon Francisco», opción solo admin como REV03).
//    Valor 'rev04' del MISMO selector. (a) con 'rev04' salen las frases nuevas en ES/EN/ID y desaparece lo
//    que sustituyen (impuestos, arbitraje SIAC, permisos); (b) con '' y con 'si' (REV03) el texto estándar
//    sale IGUAL que antes y no se cuela ni una frase REV04; y REV04 no arrastra frases REV03.
// La finca y la titular van como campos ({{finca_shm_nib}}, {{poder_titular}}): el repo es PÚBLICO y no puede llevar el nombre de un tercero ni su NIB (Legal, 7-oct-2026).
const FINCA = 'SHM/NIB {{finca_shm_nib}}';
for (const t of [PARCELA, CONSTRUCCION]) assert(!/SHM\/NIB \d|(Dña\.|Mrs\.|Ny\.) [A-ZÑ]{4,} [A-ZÑ]{4,}/.test(t), 'una plantilla lleva datos personales de la titular o su NIB fijos');
const TABANAN = ['Juzgado de Distrito de Tabanan (Pengadilan Negeri Tabanan)', 'Tabanan District Court (Pengadilan Negeri Tabanan)', 'yurisdiksi eksklusif Pengadilan Negeri Tabanan'];
const REV04 = {
  'ppjb_parcela.html': [
    'Surat Kuasa (poder de venta) de fecha 16 de septiembre de 2025', 'by virtue of the Surat Kuasa (power of sale) dated 16 September 2025',
    'berdasarkan Surat Kuasa tertanggal 16 September 2025', 'a favor de D. {{poder_apoderado}}', 'in favour of Mr. {{poder_apoderado}}', 'kepada Tn. {{poder_apoderado}}',
    'correspondiente a la finca con certificado ' + FINCA, 'corresponding to the land under certificate ' + FINCA, 'sesuai dengan tanah bersertifikat ' + FINCA,
    'procedente de la finca con certificado ' + FINCA, 'originating from the land under certificate ' + FINCA, 'berasal dari tanah bersertifikat ' + FINCA,
    'El PROMOTOR asumirá el PPh correspondiente al arrendamiento', 'The DEVELOPER shall bear the PPh corresponding to the lease', 'PENGEMBANG menanggung PPh atas sewa',
    ...TABANAN,
  ],
  'ppjb_construccion.html': [
    'incluido el PBG y el SLF (Sertifikat Laik Fungsi) a la finalización de las obras', 'including the PBG and the SLF (Sertifikat Laik Fungsi) upon completion of the works', 'termasuk PBG dan SLF (Sertifikat Laik Fungsi) pada saat selesainya pekerjaan',
    'salvo en caso de dolo o negligencia grave del CONSTRUCTOR', 'except in case of wilful misconduct or gross negligence of the BUILDER', 'kecuali dalam hal kesengajaan atau kelalaian berat KONTRAKTOR',
    'se obtendrán conforme a lo previsto en el Artículo 2', 'shall be obtained as provided in Article 2', 'diperoleh sesuai dengan ketentuan Pasal 2',
    ...TABANAN,
  ],
};
// Lo que REV04 SUSTITUYE: con REV04 no sale; con '' y con 'si' sí, UNA vez.
const SUSTITUIDO = {
  'ppjb_parcela.html': ['De los impuestos de la transmisión', 'Regarding transfer taxes', 'Mengenai pajak transaksi', 'Singapore International Arbitration Centre (SIAC)'],
  'ppjb_construccion.html': ['es responsabilidad exclusiva y a cargo del CONSTRUCTOR', 'is the sole responsibility of, and at the cost of, the BUILDER',
    'merupakan tanggung jawab tunggal dan atas biaya KONTRAKTOR', 'Singapore International Arbitration Centre (SIAC)'],
};
const cuenta = (h, fr) => h.split(fr).length - 1;
for (const [f, html] of [['ppjb_parcela.html', PARCELA], ['ppjb_construccion.html', CONSTRUCCION]]) {
  for (const regimen of ['leasehold', 'hgb', 'hak_milik']) {
    const base = { adq1_tipo: 'persona', regimen_tenencia: regimen };
    const sin = limpia(motor(html, { ...base }));
    const r03 = limpia(motor(html, conRev03(base)));
    const r04 = limpia(motor(html, { ...base, clausulas_negociadas: 'rev04' }));
    for (const fr of REV04[f]) {
      assert(r04.includes(fr), f + ' (' + regimen + '): con REV04 falta «' + fr + '»');
      assert(!sin.includes(fr), f + ' (' + regimen + '): sin REV04 se imprime «' + fr + '»');
      assert(!r03.includes(fr), f + ' (' + regimen + '): con REV03 se cuela la frase REV04 «' + fr + '»');
      n += 3;
    }
    for (const fr of SUSTITUIDO[f]) {
      assert(cuenta(sin, fr) >= 1, f + ' (' + regimen + '): el texto estándar perdió «' + fr + '»');
      assert.strictEqual(cuenta(r03, fr), cuenta(sin, fr), f + ' (' + regimen + '): REV03 cambia o duplica el estándar «' + fr + '»');
      assert(!r04.includes(fr), f + ' (' + regimen + '): con REV04 sigue lo sustituido «' + fr + '»');
      n += 3;
    }
    for (const fr of [...FRASES[f], ...DNI]) { assert(!r04.includes(fr), f + ' (' + regimen + '): con REV04 sale una frase REV03 «' + fr + '»'); n++; }
    for (const fr of ESTANDAR[f]) { assert(r04.includes(fr), f + ' (' + regimen + '): con REV04 se perdió el estándar «' + fr + '»'); n++; }
  }
  // El motor del bot (edge bot-agentes) da lo mismo.
  for (const lang of ['es', 'en', 'id']) {
    const d = { adq1_tipo: 'persona', regimen_tenencia: 'leasehold' };
    const plano = h => h.replace(/\s+/g, ' ');
    const sinBot = plano(plantillaTexto(html, lang, d));
    const r04Bot = plano(plantillaTexto(html, lang, { ...d, clausulas_negociadas: 'rev04' }));
    const r03Bot = plano(plantillaTexto(html, lang, conRev03(d)));
    const deLang = REV04[f].filter(fr => r04Bot.includes(fr));
    assert(deLang.length >= 3, f + ' bot ' + lang + ': con REV04 salen solo ' + deLang.length + ' frases');
    for (const fr of REV04[f]) { assert(!sinBot.includes(fr) && !r03Bot.includes(fr), f + ' bot ' + lang + ': sin REV04 sale «' + fr + '»'); n++; }
    for (const fr of SUSTITUIDO[f]) { if (sinBot.includes(fr)) assert(!r04Bot.includes(fr) && r03Bot.includes(fr), f + ' bot ' + lang + ': lo sustituido no cuadra «' + fr + '»'); n++; }
  }
}

console.log('clausulas_negociadas.test.js: ' + n + ' comprobaciones en verde');
