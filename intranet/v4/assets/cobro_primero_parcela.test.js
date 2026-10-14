/* node cobro_primero_parcela.test.js — «primero la parcela, luego la obra» en la pantalla de Proyectos
   (owner, 14-oct-2026; migración 20261014024234_cobro_primero_parcela.sql).

   La regla vive en la base (_unidad_cobro_cascada). La pantalla NO la recalcula: toma el `cobrado_suelo`
   que la base ya dio a cada parcela y, venta a venta, deja el resto de lo cobrado como obra. Este test
   fija las dos piezas de datos.js que hacen eso, sacadas del fichero real (no una copia):
     precioParte(u, parte)      precio de CONTRATO si la base lo da; si no, el de catálogo
     repartoPorRegla(fam, uu)   barras Parcela / Construcción del proyecto
   Falla también si datos.js deja de pedir las columnas nuevas o vuelve a repartir por su cuenta. */
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const src = fs.readFileSync(path.join(__dirname, 'datos.js'), 'utf8');

function extrae(nombre) {
  const ini = src.indexOf('function ' + nombre + '(');
  assert.ok(ini > 0, 'datos.js ya no tiene ' + nombre + '()');
  assert.strictEqual(src.indexOf('function ' + nombre + '(', ini + 1), -1, nombre + '() está dos veces en datos.js');
  let nivel = 0, i = src.indexOf('{', ini);
  for (; i < src.length; i++) {
    if (src[i] === '{') nivel++;
    else if (src[i] === '}' && --nivel === 0) break;
  }
  return src.slice(ini, i + 1);
}

const ctx = { RAIZ_C: {} };
vm.createContext(ctx);
vm.runInContext(extrae('precioParte') + '\n' + extrae('repartoPorRegla') + '\n;this.precioParte = precioParte; this.repartoPorRegla = repartoPorRegla;', ctx);
const { precioParte, repartoPorRegla } = ctx;
const igual = (a, b, m) => assert.deepStrictEqual(JSON.parse(JSON.stringify(a)), b, m);

// --- precioParte: el de contrato manda; el de catálogo es el respaldo ---
assert.strictEqual(precioParte({ suelo_pactado: 15000, precio_suelo: 18750 }, 'suelo'), 15000, 'suelo: manda el precio de contrato');
assert.strictEqual(precioParte({ suelo_pactado: '25000.00', precio_suelo: 25000 }, 'suelo'), 25000, 'la base manda texto: se devuelve número');
assert.strictEqual(precioParte({ precio_suelo: 18750 }, 'suelo'), 18750, 'sin columna nueva (maestro del ERP): catálogo');
assert.strictEqual(precioParte({ suelo_pactado: null, precio_suelo: 18750 }, 'suelo'), 18750, 'pactado nulo (sin permiso): catálogo');
assert.strictEqual(precioParte({ obra_pactada: 44000, precio_construccion: 40250 }, 'obra'), 44000, 'obra: manda el precio de contrato');
assert.strictEqual(precioParte({ precio_construccion: 40250 }, 'obra'), 40250, 'obra sin pactado: catálogo');
assert.strictEqual(precioParte({}, 'suelo'), null, 'sin ningún precio: null, no 0');
assert.strictEqual(precioParte({ suelo_pactado: 0, precio_suelo: 18750 }, 'suelo'), 0, 'un 0 de la base es un dato, no un hueco');

// --- repartoPorRegla ---
// SH-1 (medido el 14-oct): 41.620 cobrados contra el Bloqueo (25.000) y la Construcción a 0.
ctx.RAIZ_C = { rp21: 'rp21', cc10: 'rp21' };
igual(repartoPorRegla({ cadenas: { rp21: { parcela: 41620, obra: 0 } } }, [{ contrato_id: 'rp21', cobrado_suelo: '25000.00' }]),
  { parcela: 25000, obra: 16620 }, 'SH-1: lo que pasa del precio de la parcela es obra');

// SH-2: todo cobrado contra la Construcción y el Bloqueo a 0 → primero la parcela.
ctx.RAIZ_C = { rp: 'rp', cc: 'rp' };
igual(repartoPorRegla({ cadenas: { rp: { parcela: 0, obra: 44955 } } }, [{ contrato_id: 'rp', cobrado_suelo: 25000 }]),
  { parcela: 25000, obra: 19955 }, 'SH-2: un recibí colgado de la Construcción paga antes la parcela');

// Varias ventas: se suma venta a venta y el total del proyecto no cambia.
ctx.RAIZ_C = { a: 'a', a2: 'a', b: 'b', c: 'c' };
const fam = { cadenas: { a: { parcela: 5000, obra: 20000 }, b: { parcela: 30000, obra: 0 }, c: { parcela: 1000, obra: 500 } } };
const r = repartoPorRegla(fam, [
  { contrato_id: 'a', cobrado_suelo: 25000 },
  { contrato_id: 'b', cobrado_suelo: 30000 },
]);
igual(r, { parcela: 56000, obra: 500 }, 'tres ventas: dos con la regla y una sin parcela a la vista, que se queda por tipo');
assert.strictEqual(r.parcela + r.obra, 56500, 'el total cobrado del proyecto es el mismo');

// Una venta con dos parcelas: su suelo es la suma de las dos.
ctx.RAIZ_C = { v: 'v' };
igual(repartoPorRegla({ cadenas: { v: { parcela: 10000, obra: 50000 } } },
  [{ contrato_id: 'v', cobrado_suelo: 20000 }, { contrato_id: 'v', cobrado_suelo: 15000 }]),
  { parcela: 35000, obra: 25000 }, 'dos parcelas en la misma venta: se suman');

// La parcela cuelga de un hijo: se casa por la raíz.
ctx.RAIZ_C = { hijo: 'raiz', raiz: 'raiz' };
igual(repartoPorRegla({ cadenas: { raiz: { parcela: 0, obra: 9000 } } }, [{ contrato_id: 'hijo', cobrado_suelo: 9000 }]),
  { parcela: 9000, obra: 0 }, 'se casa por la raíz de la venta');

// Cobro no visible (la base da null a quien no puede verlo): NO se inventa un 0; la venta se queda por tipo.
ctx.RAIZ_C = { x: 'x' };
igual(repartoPorRegla({ cadenas: { x: { parcela: 100, obra: 900 } } }, [{ contrato_id: 'x', cobrado_suelo: null }]),
  { parcela: 100, obra: 900 }, 'cobrado_suelo null = «no he podido mirar», no «0 cobrado»');

// La base nunca puede dar más suelo que lo cobrado en la venta; si lo diera, la obra no sale negativa.
igual(repartoPorRegla({ cadenas: { x: { parcela: 100, obra: 900 } } }, [{ contrato_id: 'x', cobrado_suelo: 5000 }]),
  { parcela: 1000, obra: 0 }, 'suelo acotado al total de la venta');

// Parcelas sin contrato o de una venta que no está en la familia: no cuentan ni rompen.
igual(repartoPorRegla({ cadenas: { x: { parcela: 100, obra: 900 } } },
  [{ contrato_id: null, cobrado_suelo: 0 }, { contrato_id: 'otra', cobrado_suelo: 7000 }]),
  { parcela: 100, obra: 900 }, 'parcelas ajenas a la familia no cuentan');

// Sin datos no rompe.
igual(repartoPorRegla(null, null), { parcela: 0, obra: 0 }, 'sin familia');
igual(repartoPorRegla({ cadenas: {} }, []), { parcela: 0, obra: 0 }, 'familia vacía');

// --- el cableado en datos.js ---
assert.ok(/from\('unidades_estado'\)\s*\.select\('\*'\)/.test(src),
  'el cajón tiene que pedir unidades_estado con select(*): las columnas suelo_pactado / obra_pactada no existen en todas las bases que comparten esta pantalla');
assert.ok(src.includes("precioParte(u, 'suelo')") && src.includes("precioParte(u, 'obra')"), 'tarjeta y ficha pintan el precio con precioParte');
assert.ok(src.includes('repartoPorRegla(fam, uu)'), 'las barras del proyecto usan repartoPorRegla');
assert.ok(!/Math\.min\([^)]*precio_suelo/.test(src), 'datos.js no recalcula la cascada contra precio_suelo: la regla vive en la base');

console.log('cobro_primero_parcela.test.js OK');
