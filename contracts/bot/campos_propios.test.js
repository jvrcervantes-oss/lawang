/* Test de los campos propios ({{cx_*}}) en el bot de apoyo. `node campos_propios.test.js`.
   1. Paridad byte a byte del bloque cxVisible con las DOS copias de la edge.
   2. Las dos copias de la edge usan cxVisible en los dos sitios que importan: filtraFields (lo que entra en `fields` del
      contexto) y esReservado (lo que se enmascara en el texto de la plantilla), y piden la lista publica al servidor.
   3. Comportamiento sobre plantillaTexto: un cx_ sensible, uno fuera de catalogo o con la lectura fallida NUNCA enseña su valor;
      uno publico si; los campos del sistema siguen con su regla de siempre. */
const fs = require('fs');
const path = require('path');
const { cxVisible } = require('./campos_propios.js');
const { plantillaTexto } = require('./plantilla_texto.js');

let fallos = 0;
function ok(cond, msg) { if (!cond) { fallos++; console.error('  FALLA  ' + msg); } }

const aqui = path.dirname(__filename);
function leer(f) { return fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n'); }
function bloque(txt) {
  const a = txt.indexOf('// >>> camposPropios');
  const b = txt.indexOf('// <<< camposPropios');
  if (a < 0 || b < 0 || b < a) return null;
  return txt.slice(a, b + '// <<< camposPropios'.length);
}
const bJs = bloque(leer(path.join(aqui, 'campos_propios.js')));
ok(bJs, 'campos_propios.js sin marcadores');
for (const f of [path.join(aqui, '..', 'edge', 'bot-agentes', 'index.ts'), path.join(aqui, '..', '..', 'supabase', 'functions', 'bot-agentes', 'index.ts')]) {
  const t = leer(f);
  ok(bloque(t) === bJs, f + ': cxVisible difiere de campos_propios.js');
  ok(/function filtraFields\([^)]*cxPublicos/.test(t) && /if \(!cxVisible\(k, cxPublicos\)\) continue;/.test(t), f + ': filtraFields no filtra los cx_ por la lista publica');
  ok(/const esReservado = \(k: string\) => !cxVisible\(k, cxPublicos\) \|\|/.test(t), f + ': esReservado no enmascara los cx_ que no son publicos');
  ok(/fields: filtraFields\(fields, cxPublicos\)/.test(t), f + ': el contexto no pasa la lista publica a filtraFields');
  ok(/rpc\('plantilla_campos_cx_publicos', \{ p_contrato: contrato\.id \}\)/.test(t), f + ': no pide la lista publica al servidor');
  ok(/let cxPublicos = new Set<string>\(\);/.test(t), f + ': sin lista publica por defecto (tiene que ser vacia = cerrado)');
}

// comportamiento
const CAMPO_EXCLUIDO = /pasaporte|nik|email|telefono|domicilio|direccion|edad|ocupacion|npwp|nib|registro|nacionalidad|firma_adquiriente|^firmante$|titular|client_id|cuenta|apoderado|propietario|rep_/i;
const reservadoCon = (pub) => (k) => !cxVisible(k, pub) || (!/^prom_/.test(k) && CAMPO_EXCLUIDO.test(k));
const html = '<p>Zona {{cx_zona}}. Nota {{cx_nota}}. Otro {{cx_fuera}}. Email {{adq1_email}}. Precio {{precio_total}}.</p>';
const campos = { cx_zona: 'norte', cx_nota: 'PASAPORTE X123', cx_fuera: 'secreto', adq1_email: 'a@b.c', precio_total: '66000' };
const pub = new Set(['cx_zona']);
const t = plantillaTexto(html, 'es', campos, reservadoCon(pub));
ok(t.includes('Zona norte'), 'el cx_ publico sale');
ok(!t.includes('X123') && t.includes('Nota (dato reservado)'), 'el cx_ sensible sale enmascarado, no su valor: ' + t);
ok(!t.includes('secreto') && t.includes('Otro (dato reservado)'), 'el cx_ fuera de catalogo tambien');
ok(t.includes('Email (dato reservado)'), 'el campo de sistema reservado sigue reservado');
ok(t.includes('Precio 66000'), 'el campo de sistema normal sigue saliendo');
const t2 = plantillaTexto(html, 'es', campos, reservadoCon(new Set()));
ok(!t2.includes('norte'), 'con la lista vacia (lectura fallida) ningun cx_ sale');
const t3 = plantillaTexto(html, 'es', campos, reservadoCon(undefined));
ok(!t3.includes('norte') && !t3.includes('X123'), 'sin lista (undefined) ningun cx_ sale');
ok(cxVisible('precio_total', undefined) === true, 'un campo de sistema es visible sin lista');
ok(cxVisible('cx_zona', pub) === true && cxVisible('cx_nota', pub) === false, 'cxVisible: solo los publicos');

if (fallos) { console.error(fallos + ' fallo(s)'); process.exit(1); }
console.log('campos_propios.test.js: OK');
