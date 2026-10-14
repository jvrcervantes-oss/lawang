/* node cobro_primero_parcela.test.js — «primero la parcela, luego la obra» en la pantalla de Proyectos
   (owner, 14-oct-2026; migraciones 20261014024234 y 20261014032925).

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
// Una venta tal como la monta datos.js: lo cobrado por familia, lo de contratos sin familia (`otros`: una Carta de
// Reserva) y si la venta tiene ya Bloqueo o Construcción (`conFamilia`).
const cad = (parcela, obra, otros) => ({ parcela, obra, otros: otros || 0, conFamilia: true });
// Solo parcela y obra; `absorbido` se prueba aparte.
const reparto = (fam, uu) => { const r = repartoPorRegla(fam, uu); return { parcela: r.parcela, obra: r.obra }; };

// --- precioParte: el de contrato manda; el de catálogo es el respaldo ---
assert.strictEqual(precioParte({ suelo_pactado: 15000, precio_suelo: 18750 }, 'suelo'), 15000, 'suelo: manda el precio de contrato');
assert.strictEqual(precioParte({ suelo_pactado: '25000.00', precio_suelo: 25000 }, 'suelo'), 25000, 'la base manda texto: se devuelve número');
assert.strictEqual(precioParte({ precio_suelo: 18750 }, 'suelo'), 18750, 'sin columna nueva (maestro del ERP): catálogo');
assert.strictEqual(precioParte({ suelo_pactado: null, precio_suelo: 18750 }, 'suelo'), 18750, 'pactado nulo (sin contrato o sin permiso): catálogo');
assert.strictEqual(precioParte({ obra_pactada: 44000, precio_construccion: 40250 }, 'obra'), 44000, 'obra: manda el precio de contrato');
assert.strictEqual(precioParte({ precio_construccion: 40250 }, 'obra'), 40250, 'obra sin pactado: catálogo');
assert.strictEqual(precioParte({}, 'suelo'), null, 'sin ningún precio: null, no 0');
assert.strictEqual(precioParte({ suelo_pactado: 0, precio_suelo: 18750 }, 'suelo'), 0, 'un 0 de la base es un dato, no un hueco');

// --- repartoPorRegla ---
// SH-1 (medido el 14-oct): 41.620 cobrados contra el Bloqueo (25.000) y la Construcción a 0.
ctx.RAIZ_C = { rp21: 'rp21', cc10: 'rp21' };
igual(reparto({ cadenas: { rp21: cad(41620, 0) } }, [{ contrato_id: 'rp21', cobrado_suelo: '25000.00' }]),
  { parcela: 25000, obra: 16620 }, 'SH-1: lo que pasa del precio de la parcela es obra');

// SH-2: todo cobrado contra la Construcción y el Bloqueo a 0 → primero la parcela.
ctx.RAIZ_C = { rp: 'rp', cc: 'rp' };
igual(reparto({ cadenas: { rp: cad(0, 44955) } }, [{ contrato_id: 'rp', cobrado_suelo: 25000 }]),
  { parcela: 25000, obra: 19955 }, 'SH-2: un recibí colgado de la Construcción paga antes la parcela');

// Varias ventas: se suma venta a venta y el total del proyecto no cambia.
ctx.RAIZ_C = { a: 'a', a2: 'a', b: 'b', c: 'c' };
const fam = { cadenas: { a: cad(5000, 20000), b: cad(30000, 0), c: cad(1000, 500) } };
const r = reparto(fam, [
  { contrato_id: 'a', cobrado_suelo: 25000 },
  { contrato_id: 'b', cobrado_suelo: 30000 },
]);
igual(r, { parcela: 56000, obra: 500 }, 'tres ventas: dos con la regla y una sin parcela a la vista, que se queda por tipo');
assert.strictEqual(r.parcela + r.obra, 56500, 'el total cobrado del proyecto es el mismo');

// Una venta con dos parcelas: su suelo es la suma de las dos.
ctx.RAIZ_C = { v: 'v' };
igual(reparto({ cadenas: { v: cad(10000, 50000) } },
  [{ contrato_id: 'v', cobrado_suelo: 20000 }, { contrato_id: 'v', cobrado_suelo: 15000 }]),
  { parcela: 35000, obra: 25000 }, 'dos parcelas en la misma venta: se suman');

// La parcela cuelga de un hijo: se casa por la raíz.
ctx.RAIZ_C = { hijo: 'raiz', raiz: 'raiz' };
igual(reparto({ cadenas: { raiz: cad(0, 9000) } }, [{ contrato_id: 'hijo', cobrado_suelo: 9000 }]),
  { parcela: 9000, obra: 0 }, 'se casa por la raíz de la venta');

// Cobro no visible (la base da null a quien no puede verlo): NO se inventa un 0; la venta se queda por tipo.
ctx.RAIZ_C = { x: 'x' };
igual(reparto({ cadenas: { x: cad(100, 900) } }, [{ contrato_id: 'x', cobrado_suelo: null }]),
  { parcela: 100, obra: 900 }, 'cobrado_suelo null = «no he podido mirar», no «0 cobrado»');

// La base nunca puede dar más suelo que lo cobrado en la venta; si lo diera, la obra no sale negativa.
igual(reparto({ cadenas: { x: cad(100, 900) } }, [{ contrato_id: 'x', cobrado_suelo: 5000 }]),
  { parcela: 1000, obra: 0 }, 'suelo acotado al total de la venta');

// Parcelas sin contrato o de una venta que no está en la familia: no cuentan ni rompen.
igual(reparto({ cadenas: { x: cad(100, 900) } },
  [{ contrato_id: null, cobrado_suelo: 0 }, { contrato_id: 'otra', cobrado_suelo: 7000 }]),
  { parcela: 100, obra: 900 }, 'parcelas ajenas a la familia no cuentan');

// La Carta de Reserva de una venta que ya tiene Bloqueo: la base la cuenta en la bolsa y las barras también.
// 5.000 de señal en la Carta + 20.000 contra la Construcción, parcela de 25.000 → todo parcela. Lo absorbido se
// descuenta del aviso de «sin atribuir» para no contarlo dos veces.
ctx.RAIZ_C = { v: 'v' };
igual(repartoPorRegla({ cadenas: { v: cad(0, 20000, 5000) } }, [{ contrato_id: 'v', cobrado_suelo: 25000 }]),
  { parcela: 25000, obra: 0, absorbido: 5000 }, 'la señal de la Carta cuenta para la parcela de su venta');
// Una venta SOLO con Carta (sin Bloqueo ni Construcción) no entra en las barras: sigue en «sin atribuir».
igual(repartoPorRegla({ cadenas: { v: { parcela: 0, obra: 0, otros: 3000, conFamilia: false } } }, [{ contrato_id: 'v', cobrado_suelo: 3000 }]),
  { parcela: 0, obra: 0, absorbido: 0 }, 'venta solo con Carta: fuera de las barras');

// Sin datos no rompe.
igual(repartoPorRegla(null, null), { parcela: 0, obra: 0, absorbido: 0 }, 'sin familia');
igual(repartoPorRegla({ cadenas: {} }, []), { parcela: 0, obra: 0, absorbido: 0 }, 'familia vacía');

// --- el cableado en datos.js ---
assert.ok(/from\('unidades_estado'\)\s*\.select\('\*'\)/.test(src),
  'el cajón tiene que pedir unidades_estado con select(*): las columnas suelo_pactado / obra_pactada no existen en todas las bases que comparten esta pantalla');
assert.ok(src.includes("precioParte(u, 'suelo')") && src.includes("precioParte(u, 'obra')"), 'tarjeta y ficha pintan el precio con precioParte');
assert.ok(src.includes('repartoPorRegla(fam, uu)'), 'las barras del proyecto usan repartoPorRegla');
assert.ok(src.includes('var dpTotal = (dpSuelo != null && dpObra != null) ? dpSuelo + dpObra : u.precio;'),
  'el Total de la ficha es la suma de las dos partes que enseña');
assert.ok(src.includes('(fam.sinAtribuir || 0) - reparto.absorbido'), 'el aviso de «sin atribuir» descuenta lo que la regla ya repartió');
assert.ok(src.includes('cad.conFamilia = true') && src.includes('cadO.otros += cobradoC'), 'las ventas se montan con conFamilia y otros');
assert.ok(!/Math\.min\([^)]*precio_suelo/.test(src), 'datos.js no recalcula la cascada contra precio_suelo: la regla vive en la base');

console.log('cobro_primero_parcela.test.js OK');
