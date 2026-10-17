/* Los avisos se piden por su nombre global, nunca por window. `node contracts/assets/toast_global.test.js`.
   ============================================================================
   `toast` y `toastMal` son `const` de primer nivel de suite-comun.js: viven en el ámbito global de los scripts, pero un
   `const` NO crea propiedad en window. Quien preguntaba `window.toast` recibía undefined y el aviso no salía, sin un error:
   el 17-oct-2026 eran 7 ficheros (Ajustes › IA y apps conectadas, textos de contrato con IA, redactar contrato, fotos del
   deck, creatividades, el error de guardar de los editores y un aviso de datos.js). Se llaman como el resto de la suite:
   `if (typeof toast === 'function') toast(m)`. Esta prueba lo mantiene: ningún .js de la suite toca window.toast. */
const fs = require('fs'), path = require('path');
const RAIZ = path.resolve(__dirname, '..', '..');
const CARPETAS = ['contracts', 'intranet', 'portal'];
const FUERA = /node_modules|Backups|\.test\.js$|\.harness\.cjs$/;   // los arneses ponen window.toast a propósito para espiarlo

let fallos = 0, leidos = 0;
function recorre(dir) {
  let hijos;
  try { hijos = fs.readdirSync(dir, { withFileTypes: true }); } catch (e) { return; }
  for (const h of hijos) {
    const p = path.join(dir, h.name);
    if (FUERA.test(p)) continue;
    if (h.isDirectory()) recorre(p);
    else if (/\.js$/.test(h.name)) {
      leidos++;
      fs.readFileSync(p, 'utf8').split(/\r?\n/).forEach((l, i) => {
        if (/\bwindow\.toast(Mal)?\b/.test(l)) {
          fallos++;
          console.log(`  FALLA  ${path.relative(RAIZ, p)}:${i + 1} pide el aviso por window (no existe ahí): ${l.trim().slice(0, 120)}`);
        }
      });
    }
  }
}
CARPETAS.forEach((c) => recorre(path.join(RAIZ, c)));

// la premisa: si suite-comun.js los pasara a window, esta regla sobraría (y habría que retirarla, no esquivarla)
const comun = fs.readFileSync(path.join(RAIZ, 'contracts', 'assets', 'suite-comun.js'), 'utf8');
if (!/^const toast = /m.test(comun) || !/^const toastMal = /m.test(comun)) {
  fallos++; console.log('  FALLA  suite-comun.js ya no declara toast/toastMal como const de primer nivel: revisa esta prueba');
}
if (leidos < 100) { fallos++; console.log(`  FALLA  solo ${leidos} ficheros .js leídos: la ruta de la suite ha cambiado`); }

if (fallos) { console.log(`\n${fallos} fallo(s)`); process.exit(1); }
console.log(`OK toast_global.test.js — ${leidos} ficheros, ninguno pide el aviso por window`);
