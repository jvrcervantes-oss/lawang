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
assert(campo && campo[2] === 'select' && campo[3].length === 1 && campo[3][0][0] === 'si', 'tokens.json: clausulas_negociadas debe ser select con la única opción «si»');
n++;

// 5. Dónde se elige y dónde se ve (2-oct-2026, owner: «desde el listado o desde el asistente»).
const asi = fs.readFileSync(path.join(__dirname, 'assets', 'asistente-contrato.js'), 'utf8');
assert(/var SLUGS_REV03 = \['ppjb_parcela', 'ppjb_construccion'\];/.test(asi), 'asistente: el paso REV03 es solo de Parcela y Construcción');
assert(asi.includes("['super_admin', 'admin'].indexOf(MI_ROL) !== -1"), 'asistente: el paso REV03 es solo para admin/super_admin');
assert((asi.match(/if \(pideClausulas\(\)\) p\.push\(\['clausulas'/g) || []).length === 2, 'asistente: el paso REV03 tiene que estar en «venta nueva» y en «seguir una venta»');
assert(asi.includes("if (k === 'clausulas') return S.clausulas === 'estandar' || S.clausulas === 'rev03';"), 'asistente: el paso REV03 obliga a elegir');
// «Estándar» tiene que QUITAR el 'si' heredado: populateForm se salta los vacíos, así que se escribe a mano.
assert(asi.includes("cn.value = S.clausulas === 'rev03' ? 'si' : '';"), 'asistente: montaCondiciones no escribe el selector a mano');
const dv4 = fs.readFileSync(path.join(__dirname, '..', 'intranet', 'v4', 'assets', 'datos.js'), 'utf8');
assert(dv4.includes("select(CAMPOS_CONTRATO + ',rev03:datos_fields->>clausulas_negociadas')"), 'listado: no lee clausulas_negociadas');
assert(dv4.includes("(c.rev03 === 'si' ? ' <span title=\"Cláusulas negociadas (REV03)\">' + pill('REV03', 'curso')"), 'listado: no pinta la pastilla REV03');
n += 7;

console.log('clausulas_negociadas.test.js: ' + n + ' comprobaciones en verde');
