/* REV03 (7-oct-2026) — lo que el comprador vio en el borrador y no debe volver:
     1. Un comentario de plantilla que se cierra antes de tiempo (su texto se imprime).
     2. «España» / «(promoción)» dentro de la columna indonesia.
     3. El Adquiriente II sin «DNI» cuando el I sí lo lleva.
   Usa el código REAL de app.html (se extrae, no se copia).   node traduce_campos.test.js */
const fs = require('fs');
const path = require('path');
const assert = require('assert');
const T = require('./assets/traduce_campos.js');

const app = fs.readFileSync(path.join(__dirname, 'app.html'), 'utf8');
const dir = path.join(__dirname, 'templates');

// ── 1. Ningún comentario de plantilla contiene otro `<!--`: su `-->` lo cerraría y el resto se imprime.
for (const f of fs.readdirSync(dir).filter(x => x.endsWith('.html'))) {
  const s = fs.readFileSync(path.join(dir, f), 'utf8');
  const re = /<!--(?!\/?(?:if:|opt:|seccion-|hitos|extras-|compradores-|firmas-|extra-clauses))([\s\S]*?)-->/g;
  let m;
  while ((m = re.exec(s))) {
    assert(!/<!--/.test(m[1]), `${f} l.${s.slice(0, m.index).split('\n').length}: un comentario contiene «<!--» (se cierra antes de tiempo)`);
  }
}

// ── 2. Tabla de traducciones
assert.strictEqual(T.trNacionalidad('España', 'id'), 'Spanyol');
assert.strictEqual(T.trNacionalidad('ESPAÑOLA', 'en'), 'Spain');
assert.strictEqual(T.trNacionalidad('Spanish', 'id'), 'Spanyol');
assert.strictEqual(T.trNacionalidad('Países Bajos', 'id'), 'Belanda');
assert.strictEqual(T.trNacionalidad('Netherlands', 'en'), 'Netherlands');
assert.strictEqual(T.trNacionalidad('TEST', 'id'), null, 'un valor desconocido no se inventa');
assert.strictEqual(T.trMotivoDescuento('promoción', 'id'), 'Promosi');
assert.strictEqual(T.trMotivoDescuento('Precio antiguo', 'en'), 'Previously agreed price');
assert.strictEqual(T.trMotivoDescuento('dto comercial, inicio pago septiembre 2027', 'id'), null);

// ── 3. Adquiriente II con el código real de app.html
const a = app.indexOf('const COMPRADOR_FRASE = {');
const b = app.indexOf('/* lwT:fin */', a);
const c = app.indexOf('function compradorFields(', b);
const d = app.indexOf('function compradorTieneDatos', c);
assert(a > 0 && b > a && c > b && d > c, 'no encuentro COMPRADOR_FRASE/compradorFields en app.html');
const esc = s => String(s);
const { COMPRADOR_FRASE, compradorFields } = new Function('esc', 'trNacionalidad',
  app.slice(a, b) + app.slice(c, d) + '\nreturn { COMPRADOR_FRASE, compradorFields };')(esc, T.trNacionalidad);
const comp = { nombre: 'Ana Pérez', nacionalidad: 'España', pasaporte: 'X1', telefono: '1', email: 'a@b.c' };
const frases = (slug, rev03) => ['es', 'en', 'id'].map(l => COMPRADOR_FRASE[slug][l]('II', compradorFields(comp, rev03)));
const DNI = { ppjb_parcela: [' o DNI nº', 'passport or national ID card (DNI) no.', 'paspor atau Kartu Identitas (DNI) no.'],
              ppjb_construccion: ['Pasaporte/DNI/Nº de identificación fiscal', 'Passport/National ID (DNI)/Tax ID no.', 'Paspor/Kartu Identitas (DNI)/Nomor Identifikasi Pajak'] };
for (const slug of Object.keys(DNI)) {
  const con = frases(slug, true), sin = frases(slug, false);
  DNI[slug].forEach((x, i) => { assert(con[i].includes(x), `${slug} ${i}: con REV03 falta «${x}»`); assert(!sin[i].includes('DNI'), `${slug} ${i}: sin REV03 no debe haber DNI`); });
}
// Sin REV03 el texto de siempre, byte a byte
assert(frases('ppjb_construccion', false)[0].includes('con Pasaporte/Nº de identificación fiscal <span'));
assert(frases('ppjb_parcela', false)[0].includes('con pasaporte nº <span'));
// Nacionalidad por idioma en TODAS las frases
for (const slug of Object.keys(COMPRADOR_FRASE)) {
  const [es, en, id] = ['es', 'en', 'id'].map(l => COMPRADOR_FRASE[slug][l]('II', compradorFields(comp, false)));
  assert(es.includes('España'), `${slug} es`);
  assert(en.includes('Spain') && !en.includes('España'), `${slug} en: ${en}`);
  assert(id.includes('Spanyol') && !id.includes('España'), `${slug} id: ${id}`);
}

// ── 4. Pase por idioma de buildDoc (párrafos en/id del Adquiriente I y del descuento)
const i0 = app.indexOf('  html=html.replace(/<(p|li)');
const i1 = app.indexOf('\n  });', i0) + 6;
assert(i0 > 0 && i1 > i0, 'no encuentro el pase por idioma en app.html');
const pase = new Function('html', 'data', 'trNacionalidad', 'trMotivoDescuento', 'campoFijo', 'esc',
  app.slice(i0, i1) + '\nreturn html;');
const campoFijo = (k, v) => v, esc2 = s => s;
const doc = '<p data-lang="es">de {{adq1_nacionalidad}}, ({{descuento_comercial_motivo}}),</p>'
  + '<p data-lang="en">of {{adq1_nacionalidad}}, discount {{descuento_comercial}} ({{descuento_comercial_motivo}}),</p>'
  + '<p data-lang="id">dari {{adq1_nacionalidad}}, diskon {{descuento_comercial}} ({{descuento_comercial_motivo}}),</p>';
let out = pase(doc, { adq1_nacionalidad: 'España', descuento_comercial_motivo: 'Promoción' }, T.trNacionalidad, T.trMotivoDescuento, campoFijo, esc2);
assert(out.includes('<p data-lang="es">de {{adq1_nacionalidad}}, ({{descuento_comercial_motivo}}),</p>'), 'el español no se toca');
assert(out.includes('of Spain') && out.includes('(Promotion)'), out);
assert(out.includes('dari Spanyol') && out.includes('(Promosi)'), out);
out = pase(doc, { adq1_nacionalidad: 'TEST', descuento_comercial_motivo: 'dto especial' }, T.trNacionalidad, T.trMotivoDescuento, campoFijo, esc2);
assert(out.includes('of {{adq1_nacionalidad}}'), 'sin traducción la nacionalidad se imprime tal cual');
assert(out.includes('{{descuento_comercial}},</p>') && !/\(\{\{descuento_comercial_motivo\}\}\)[^<]*<\/p><p data-lang="id"/.test(out.split('<p data-lang="id">')[0].split('<p data-lang="en">')[1] || ''), 'sin traducción el motivo se omite en en/id');

// ── 5. Las plantillas REALES (el patrón de ppjb_parcela es distinto al de ppjb_construccion)
for (const f of ['ppjb_parcela.html', 'ppjb_construccion.html']) {
  const real = fs.readFileSync(path.join(dir, f), 'utf8').replace(/<!--[\s\S]*?-->/g, '');
  const parrafos = real.match(/<p data-lang="(?:es|en|id)"[^>]*>[\s\S]*?<\/p>/g).filter(x => x.includes('{{descuento_comercial_motivo}}'));
  assert(parrafos.length === 3, `${f}: esperaba 3 párrafos con el motivo (es/en/id), hay ${parrafos.length}`);
  const hecho = pase(parrafos.join(''), { descuento_comercial_motivo: 'Promoción', adq1_nacionalidad: 'España' }, T.trNacionalidad, T.trMotivoDescuento, campoFijo, esc2);
  const [pEs, pEn, pId] = hecho.match(/<p data-lang[\s\S]*?<\/p>/g);
  assert(pEs.includes('{{descuento_comercial_motivo}}'), `${f} es sin tocar`);
  assert(pEn.includes('Promotion') && !pEn.includes('{{descuento_comercial_motivo}}') && !pEn.includes('Promoción'), `${f} en: ${pEn}`);
  assert(pId.includes('Promosi') && !pId.includes('{{descuento_comercial_motivo}}') && !pId.includes('Promoción'), `${f} id: ${pId}`);
  const sin = pase(parrafos.join(''), { descuento_comercial_motivo: 'dto especial' }, T.trNacionalidad, T.trMotivoDescuento, campoFijo, esc2).match(/<p data-lang[\s\S]*?<\/p>/g);
  for (const q of [sin[1], sin[2]]) assert(!q.includes('{{descuento_comercial_motivo}}') && !/reason:|alasan:/.test(q), `${f}: sin traducción no debe quedar el motivo ni su rótulo: ${q}`);
}

console.log('traduce_campos.test.js OK');
