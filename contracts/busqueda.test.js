/* BUSQUEDA SIN TILDES — 15-oct-2026, owner: "que no haga falta poner la tilde en los
   buscadores de Lawang y en todo lo que hagamos".
   `node contracts/busqueda.test.js`. Lo corre tools/test.py (y con el el gate de push).

   Prueba tres hechos, no solo una funcion:
     1. lwNormaliza / lwBusca / lwBuscaEn / lwCoincidencias (contracts/assets/vocabulario.js)
        cumplen la tabla de casos contracts/busqueda_casos.json (casos de Idiomas).
     2. La prueba del SERVIDOR (supabase/pruebas/busqueda_sin_tildes.sql, la funcion
        public.normaliza_busqueda) lleva EXACTAMENTE la misma tabla: las dos capas aplican
        el mismo algoritmo y, si un caso existe en una y no en la otra, divergen sin aviso.
     3. Toda pagina que carga un script que llama a la pieza comun carga tambien
        vocabulario.js. Sin el, el buscador muere con "lwBusca is not defined": peor que
        el buscador con tildes de antes. */
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assert = require('assert');

const RAIZ = path.join(__dirname, '..');
const leer = (...p) => fs.readFileSync(path.join(RAIZ, ...p), 'utf8');

const ctx = { window: {} };
vm.createContext(ctx);
vm.runInContext(leer('contracts', 'assets', 'vocabulario.js') +
  '\n;globalThis.__b = { lwNormaliza, lwBusca, lwBuscaEn, lwCoincidencias };', ctx);
const { lwNormaliza, lwBusca, lwBuscaEn, lwCoincidencias } = ctx.__b;
const CASOS = JSON.parse(leer('contracts', 'busqueda_casos.json'));

let fallos = 0;
const ok = (cond, msg) => { if (!cond) { fallos++; console.error('FALLA: ' + msg); } };

// 1 · la tabla
CASOS.normaliza.forEach(([entrada, esperado]) => {
  const r = lwNormaliza(entrada);
  ok(r === esperado, `lwNormaliza(${JSON.stringify(entrada)}) = ${JSON.stringify(r)}, esperaba ${JSON.stringify(esperado)}`);
});
CASOS.busca.forEach(([texto, q, casa]) => {
  ok(lwBusca(texto, q) === casa, `lwBusca(${JSON.stringify(texto)}, ${JSON.stringify(q)}) deberia dar ${casa}`);
  ok(lwBuscaEn(['otro campo', texto], q) === casa || (!lwNormaliza(q) && lwBuscaEn(['otro campo', texto], q)),
     `lwBuscaEn([..., ${JSON.stringify(texto)}], ${JSON.stringify(q)}) deberia dar ${casa}`);
});
ok(lwBuscaEn([], 'x') === false && lwBuscaEn(null, '') === true, 'lwBuscaEn con lista vacia');
ok(lwNormaliza(lwNormaliza('Jean—Luc  Müller')) === lwNormaliza('Jean—Luc  Müller'), 'normalizar dos veces da lo mismo');

// lwCoincidencias: posiciones en el texto ORIGINAL (para el <mark>)
const trozos = (t, q) => JSON.parse(JSON.stringify(lwCoincidencias(t, q).map(([a, b]) => t.slice(a, b))));   // el array nace en otro contexto (vm): se copia a este
assert.deepStrictEqual(trozos('José María y JOSE', 'jose'), ['José', 'JOSE']);
assert.deepStrictEqual(trozos("Señor O’Brien", 'obrien'), ['O’Brien']);
assert.deepStrictEqual(trozos('Jean  -  Luc', 'jean luc'), ['Jean  -  Luc']);
assert.deepStrictEqual(trozos('José Luis', 'jose'), ['José']);
assert.deepStrictEqual(trozos('Strauß', 'strauss'), ['Strauß']);
assert.deepStrictEqual(trozos('Strauß', 'ss'), ['ß']);
assert.deepStrictEqual(trozos('Ubud', ''), []);
assert.deepStrictEqual(trozos('Ubud', 'xyz'), []);

// 2 · la prueba del servidor lleva la misma tabla
const SQL = leer('supabase', 'pruebas', 'busqueda_sin_tildes.sql');
const lit = s => s == null ? 'null' : "'" + String(s).replace(/'/g, "''") + "'";
CASOS.normaliza.forEach(([entrada, esperado]) => {
  const fila = `(${lit(entrada)}, ${lit(esperado)})`;
  ok(SQL.includes(fila), `busqueda_sin_tildes.sql no lleva el caso de normaliza ${fila}`);
});
CASOS.busca.forEach(([texto, q, casa]) => {
  const fila = `(${lit(texto)}, ${lit(q)}, ${casa})`;
  ok(SQL.includes(fila), `busqueda_sin_tildes.sql no lleva el caso de busca ${fila}`);
});

// 3 · quien usa la pieza comun carga vocabulario.js
const USA = /\blw(?:Normaliza|Busca|BuscaEn|Coincidencias|PliegaTexto)\s*\(/;
const SALTA = new Set(['node_modules', '.git', 'Backups', 'vendor', 'dist']);
function htmls(dir, out) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (SALTA.has(e.name)) continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) htmls(p, out); else if (e.name.endsWith('.html')) out.push(p);
  }
  return out;
}
const cache = {};
function scriptLocal(pagina, src) {
  const limpio = src.split('?')[0];
  if (/^(https?:)?\/\//.test(limpio)) return null;
  const p = limpio.startsWith('/') ? path.join(RAIZ, limpio) : path.join(path.dirname(pagina), limpio);
  if (!(p in cache)) cache[p] = fs.existsSync(p) ? fs.readFileSync(p, 'utf8') : null;
  return cache[p];
}
let paginasQueBuscan = 0;
for (const pag of htmls(RAIZ, [])) {
  const html = fs.readFileSync(pag, 'utf8');
  const srcs = [...html.matchAll(/<script[^>]*\bsrc="([^"]+)"/g)].map(m => m[1]);
  const VOC = path.join(RAIZ, 'contracts', 'assets', 'vocabulario.js');
  const cargaVoc = srcs.some(s => {
    const limpio = s.split('?')[0];
    if (/^(https?:)?\/\//.test(limpio)) return false;
    return path.resolve(limpio.startsWith('/') ? path.join(RAIZ, limpio) : path.join(path.dirname(pag), limpio)) === path.resolve(VOC);
  });
  const inline = html.replace(/<script[^>]*\bsrc="[^"]*"[^>]*>\s*<\/script>/g, '');
  const usa = USA.test(inline.replace(/vocabulario\.js[^\n]*/g, '')) ||
    srcs.some(s => !/vocabulario\.js/.test(s) && USA.test(scriptLocal(pag, s) || ''));
  if (usa) {
    paginasQueBuscan++;
    ok(cargaVoc, `${path.relative(RAIZ, pag)} usa la busqueda comun y no carga /contracts/assets/vocabulario.js`);
  }
}
ok(paginasQueBuscan >= 30, `solo ${paginasQueBuscan} paginas usan la busqueda comun: el detector se ha roto`);

if (fallos) { console.error(`busqueda.test.js: ${fallos} fallo(s)`); process.exit(1); }
console.log(`busqueda.test.js: OK (${CASOS.normaliza.length} normaliza, ${CASOS.busca.length} busca, ${paginasQueBuscan} paginas con buscador cargan vocabulario.js)`);
