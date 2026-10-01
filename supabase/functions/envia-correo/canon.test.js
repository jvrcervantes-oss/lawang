/* node canon.test.js — index.ts y valida.ts son el CANON de la edge envia-correo: idénticos byte a byte en Lawang y en el
   maestro (proyectos/Lawang/supabase/functions/envia-correo ↔ erp/funciones/envia-correo). `.canon_hash` guarda su SHA-256
   (con los finales de línea normalizados a LF: Windows con autocrlf los cambia en disco). Este test solo mira ESTE repo;
   el que compara los dos es erp/test_canon_envia_correo.py, en la agencia.
   Tras un cambio deliberado del canon:  node canon.test.js --escribe   (y el mismo cambio, cp, en el otro repo). */
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const FICHEROS = ['index.ts', 'valida.ts'];
const hash = (f) => crypto.createHash('sha256').update(fs.readFileSync(path.join(__dirname, f), 'utf8').replace(/\r\n/g, '\n'), 'utf8').digest('hex');
const ruta = path.join(__dirname, '.canon_hash');
if (process.argv.includes('--escribe')) {
  fs.writeFileSync(ruta, FICHEROS.map((f) => hash(f) + '  ' + f).join('\n') + '\n');
  console.log('escrito .canon_hash'); process.exit(0);
}
const esperado = Object.fromEntries(fs.readFileSync(ruta, 'utf8').split(/\r?\n/).filter(Boolean).map((l) => { const [h, f] = l.split(/\s+/); return [f, h]; }));
const fallos = FICHEROS.filter((f) => esperado[f] !== hash(f));
if (Object.keys(esperado).sort().join() !== [...FICHEROS].sort().join()) fallos.push('.canon_hash no lista exactamente ' + FICHEROS.join(', '));
if (fallos.length) {
  console.error('FALLA canon.test.js: ' + fallos.join(', ') + ' no coincide con .canon_hash. El canon de envia-correo se cambia a la vez en Lawang y en el maestro; '
    + 'si el cambio es deliberado: node canon.test.js --escribe (y la misma copia en el otro repo).');
  process.exit(1);
}
console.log('OK canon.test.js — index.ts y valida.ts coinciden con .canon_hash');
