/* node contracts/orden_dinero.test.js
   El ORDEN de dos etiquetas <script>, que no lo comprueba ningún otro check.

   POR QUÉ EXISTE (26-ago-2026, después de tirar producción con esto).
   `facturas/totales.js` usa `dinero.js`. Mientras totales.js llevaba dentro su
   propia copia del parser y del formato, cargarlos en el orden equivocado no se
   notaba: caía al respaldo y devolvía cifras *parecidas*. El 26-ago se quitaron
   esas copias —eran la razón de que el test de totales probara código que
   producción no ejecutaba— y el orden pasó a importar de verdad. Facturas,
   Compradores y Proyectos lo tenían mal desde siempre, y las tres se quedaron en
   blanco: `Cannot access '_LW' before initialization`.

   `totales.js` ya no depende del orden (resuelve `dinero.js` en la primera
   llamada, no al parsear). Este test existe igualmente por dos motivos:
     1. El orden declarado es el contrato, y un contrato que nadie comprueba se
        rompe: la próxima página que se escriba copiará el bloque de la de al
        lado, y si esa lo tiene mal lo hereda.
     2. `sintaxis_js.py` valida que el JS *se puede ejecutar*, no que las
        dependencias estén en pie. Este es el piso que faltaba.

   Se comprueban las etiquetas del HTML, que es lo que el navegador lee — no lo
   que digan los comentarios. */
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const RAIZ = path.join(__dirname, '..');
const FUERA = new Set(['Backups', 'node_modules', 'templates', '_archive', 'dist']);

/* Solo las paginas QUE ESTAN EN GIT (28-ago-2026). Esta prueba corre en el gate de
   push, y ahi lo unico que puede romperse para alguien mas es lo que se sube: una
   pagina sin trackear —o tapada por el `.gitignore`, como los `_qa_*`— no viaja, no
   se despliega y no la abre nadie. Cinco ficheros de diagnostico de una sesion en
   marcha tenian esto en rojo, y arreglarlos habria sido editar el trabajo en vivo de
   otro para que pasara un push ajeno.

   Se pregunta por lo que ESTA en el indice, no por lo que no esta: `ls-files --others
   --exclude-standard` no lista lo que tapa el `.gitignore`, asi que preguntando al
   reves un `_qa_index.html` ignorado se colaba igual. Lo saltado se dice al final, no
   se calla. */
function enGit(raiz) {
  try {
    const { execFileSync } = require('child_process');
    const out = execFileSync('git', ['-C', raiz, 'ls-files', '--', '*.html'],
                             { encoding: 'utf8' });
    return new Set(out.split(String.fromCharCode(10))
                      .map(f => f.trim()).filter(Boolean)
                      .map(f => path.resolve(raiz, f).toLowerCase()));
  } catch (_) {
    return null;   // sin git (o sin repo) se comprueba todo: mejor de mas que de menos
  }
}
const EN_GIT = enGit(RAIZ);
let SALTADAS = 0;

function paginas(dir, salida = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (FUERA.has(e.name)) continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) paginas(p, salida);
    else if (e.name.endsWith('.html')) {
      if (EN_GIT && !EN_GIT.has(path.resolve(p).toLowerCase())) { SALTADAS++; continue; }
      salida.push(p);
    }
  }
  return salida;
}

/* Solo las etiquetas <script src>, en el orden en que aparecen. Un `src` dentro
   de un comentario HTML no es una carga — el mismo matiz que ya costó una
   pasada en `sintaxis_js.py`. */
const SIN_COMENTARIOS = html => html.replace(/<!--[\s\S]*?-->/g, '');
const SCRIPTS = html => [...SIN_COMENTARIOS(html).matchAll(/<script[^>]+src="([^"]+)"/g)].map(m => m[1]);

const DEPENDE = [
  // [el que necesita, lo que necesita, por qué]
  ['totales.js', 'dinero.js',
   'totales.js llama a lwParseImporte/lwFormatoImporte de dinero.js'],
  ['documento.js', 'totales.js',
   'documento.js arma el papel con calcTotales/fmtMoneda de totales.js'],
];

let fallos = 0;
let revisadas = 0;
for (const p of paginas(RAIZ)) {
  const srcs = SCRIPTS(fs.readFileSync(p, 'utf8'));
  for (const [quien, necesita, porque] of DEPENDE) {
    const i = srcs.findIndex(s => s.includes(quien));
    const j = srcs.findIndex(s => s.includes(necesita));
    if (i === -1) continue;                       // esta página no lo usa
    revisadas++;
    const rel = path.relative(RAIZ, p);
    if (j === -1) {
      fallos++;
      console.log(`  FALLA ${rel}\n         carga ${quien} y NO carga ${necesita} — ${porque}`);
    } else if (j > i) {
      fallos++;
      console.log(`  FALLA ${rel}\n         carga ${quien} ANTES que ${necesita} — ${porque}`);
    }
  }
}

if (SALTADAS) console.log(`
  (${SALTADAS} pagina(s) fuera de git no se cuentan: no se suben)`);
console.log(fallos
  ? `\n${fallos} fallo(s) de orden de carga`
  : `\nOK orden_dinero.test.js — ${revisadas} dependencia(s) de carga, todas en pie`);
process.exit(fallos ? 1 : 0);
