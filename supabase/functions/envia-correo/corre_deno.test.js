/* node corre_deno.test.js — corre los `*_test.ts` de esta carpeta (escritos para `deno test`) con node, para que el
   gate los ejecute aunque la máquina no tenga Deno. Idéntico en Lawang y en el maestro. */
const assert = require('assert');
const fs = require('fs');
const path = require('path');
(async () => {
  const { correDenoTest } = await import('./arnes.mjs');
  const ficheros = fs.readdirSync(__dirname).filter((f) => /_test\.ts$/.test(f)).sort();
  assert.ok(ficheros.includes('valida_test.ts'), 'falta valida_test.ts');
  let total = 0;
  for (const f of ficheros) { const n = await correDenoTest(path.join(__dirname, f)); assert.ok(n > 0, f + ': 0 pruebas'); total += n; }
  console.log(`OK corre_deno.test.js — ${total} pruebas de ${ficheros.join(', ')}`);
})().catch((e) => { console.error(e); process.exit(1); });
