/* node contracts/modelos_catalogo.test.js
   Las reglas del catálogo de modelos: la herencia de precio (que ya se enseñó mal
   una vez), el respaldo cuando un proyecto no tiene ninguno declarado, y la forma
   exacta de lo que se escribe en `modelos_villa`. */
const assert = require('assert');
const path = require('path');
const { lwModelosDeProyecto, lwDeclaraModelosEnProyecto } =
  require(path.join(__dirname, 'assets', 'modelos_catalogo.js'));

const CATALOGO = [
  { id:'m-dali',  nombre:'Dali',  precio_construccion:39000,  moneda:'EUR', villa_m2:60 },
  { id:'m-dream', nombre:'Dream', precio_construccion:109000, moneda:'EUR', villa_m2:120 },
  { id:'m-dune',  nombre:'Dune',  precio_construccion:69000,  moneda:'EUR', villa_m2:80 },
  { id:'m-loft',  nombre:'Loftbung', precio_construccion:950000000, moneda:'IDR', villa_m2:90 },
];
const VILLAS = [
  { id:'v1', proyecto:'Palm Field W5', proyecto_id:'p-palm', modelo:'Dali',  modelo_id:'m-dali',  precio_construccion:null,  moneda:'EUR' },
  { id:'v2', proyecto:'Palm Field W5', proyecto_id:'p-palm', modelo:'Dream', modelo_id:'m-dream', precio_construccion:95000, moneda:'EUR' },
  { id:'v3', proyecto:'Riverfront I',  proyecto_id:'p-river', modelo:'Loftbung', modelo_id:'m-loft', precio_construccion:null, moneda:'IDR' },
];

let fallos = 0;
const ok = (t, f) => { try { f(); console.log('  ok   ' + t); }
                       catch (e) { fallos++; console.log('  FALLA ' + t + '\n         ' + e.message); } };

ok('un proyecto declarado ofrece SOLO lo suyo', () => {
  const r = lwModelosDeProyecto('Palm Field W5', VILLAS, CATALOGO);
  assert.strictEqual(r.declarados, true);
  assert.deepStrictEqual(r.lista.map(x => x.modelo), ['Dali', 'Dream'],
    'Dune y Loftbung no se construyen en Palm Field, no pueden ofrecerse');
});

ok('🔴 precio a NULL = HEREDA del catálogo, no «sin precio»', () => {
  const dali = lwModelosDeProyecto('Palm Field W5', VILLAS, CATALOGO).lista.find(x => x.modelo === 'Dali');
  assert.strictEqual(dali.precio_construccion, 39000, 'el dia que Palm Field paso a heredar, la pantalla los enseño SIN precio');
  assert.strictEqual(dali.heredado, true);
});

ok('un precio propio del proyecto manda sobre el del catálogo', () => {
  const dream = lwModelosDeProyecto('Palm Field W5', VILLAS, CATALOGO).lista.find(x => x.modelo === 'Dream');
  assert.strictEqual(dream.precio_construccion, 95000);
  assert.strictEqual(dream.heredado, false);
});

ok('🔴 la moneda viaja con el precio y del MISMO nivel que lo dio', () => {
  const loft = lwModelosDeProyecto('Riverfront I', VILLAS, CATALOGO).lista[0];
  assert.strictEqual(loft.precio_construccion, 950000000);
  assert.strictEqual(loft.moneda, 'IDR', 'heredar la cifra en IDR con la moneda EUR son tres ordenes de magnitud de error');
});

ok('🔴 sin ninguno declarado se ofrece el catálogo entero, avisando', () => {
  const r = lwModelosDeProyecto('Bonian Village', VILLAS, CATALOGO);
  assert.strictEqual(r.declarados, false, 'la pantalla necesita saberlo para decirlo');
  assert.strictEqual(r.lista.length, CATALOGO.length,
    'filtrar a secas dejaria el desplegable vacio: 16 de 29 proyectos no tienen ninguno declarado');
});

/* Doble de `sb` que se queda con lo que se le manda, para mirar la FORMA exacta
   de la escritura sin tocar la base. */
function sbFalso(){
  const visto = { upsert:null, onConflict:null, borrados:null };
  return { visto, from(){ return {
    upsert(filas, opts){ visto.upsert = filas; visto.onConflict = opts && opts.onConflict; return Promise.resolve({ error:null }); },
    delete(){ return { in(_c, ids){ visto.borrados = ids; return Promise.resolve({ error:null }); } }; },
  }; } };
}

ok('🔴 el lote del upsert lleva TODAS las filas con las mismas claves', async () => {
  const sb = sbFalso();
  await lwDeclaraModelosEnProyecto(sb, 'Bonian Village', ['m-dali', 'm-dune'],
    { catalogo:CATALOGO, villas:VILLAS, proyecto_id:'p-bonian' });
  const firmas = new Set(sb.visto.upsert.map(f => Object.keys(f).sort().join('|')));
  assert.strictEqual(firmas.size, 1,
    'un upsert en lote manda UNA sentencia con la union de las claves: dos formas = NULL implicito');
  assert.strictEqual(sb.visto.onConflict, 'proyecto,modelo', 'la unicidad de la tabla es sobre el TEXTO');
  assert.deepStrictEqual(sb.visto.upsert.map(f => f.modelo), ['Dali', 'Dune']);
  assert.strictEqual(sb.visto.upsert[0].precio_construccion, null, 'declarar no fija precio: hereda del catalogo');
});

ok('declarar lo que ya estaba declarado no duplica ni reescribe', async () => {
  const sb = sbFalso();
  const r = await lwDeclaraModelosEnProyecto(sb, 'Palm Field W5', ['m-dali', 'm-dream'],
    { catalogo:CATALOGO, villas:VILLAS, proyecto_id:'p-palm' });
  assert.strictEqual(r.altas, 0);
  assert.strictEqual(r.bajas, 0);
  assert.strictEqual(sb.visto.upsert, null, 'sin cambios no se escribe nada');
});

ok('🔴 no se retira un modelo que alguna parcela YA usa', async () => {
  const sb = sbFalso();
  const r = await lwDeclaraModelosEnProyecto(sb, 'Palm Field W5', ['m-dali'],
    { catalogo:CATALOGO, villas:VILLAS, proyecto_id:'p-palm', enUso:new Set(['Dream']) });
  assert.strictEqual(r.bajas, 0);
  assert.deepStrictEqual(r.rechazadas.map(x => x.modelo), ['Dream'],
    'se devuelve para poder decir POR QUE, no solo que no se pudo');
  assert.strictEqual(sb.visto.borrados, null);
});

ok('un modelo que no usa nadie sí se retira', async () => {
  const sb = sbFalso();
  const r = await lwDeclaraModelosEnProyecto(sb, 'Palm Field W5', ['m-dali'],
    { catalogo:CATALOGO, villas:VILLAS, proyecto_id:'p-palm', enUso:new Set() });
  assert.strictEqual(r.bajas, 1);
  assert.deepStrictEqual(sb.visto.borrados, ['v2']);
});

setTimeout(() => {
  console.log(fallos ? `\n${fallos} fallo(s)` : '\nOK modelos_catalogo.test.js — el catálogo se sostiene');
  process.exit(fallos ? 1 : 0);
}, 50);
