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
   de la escritura sin tocar la base. Desde el 27-sep-2026 (LAW-336 bloque 3) la
   escritura es UNA llamada al servidor (`modelos_proyecto_fija`): el navegador no
   hace upsert ni delete sobre `modelos_villa`. */
function sbFalso(respuesta){
  const visto = { rpc:null, args:null, from:0 };
  return { visto,
    from(){ visto.from++; throw new Error('el navegador no escribe en modelos_villa'); },
    rpc(fn, args){ visto.rpc = fn; visto.args = args; return Promise.resolve({ data: respuesta || { altas:0, bajas:0, rechazadas:[] }, error:null }); },
  };
}

ok('🔴 declarar va por el servidor con la lista entera y el id del proyecto', async () => {
  const sb = sbFalso({ altas:2, bajas:0, rechazadas:[] });
  const r = await lwDeclaraModelosEnProyecto(sb, 'Bonian Village', ['m-dali', 'm-dune'],
    { catalogo:CATALOGO, villas:VILLAS, proyecto_id:'p-bonian' });
  assert.strictEqual(sb.visto.rpc, 'modelos_proyecto_fija');
  assert.deepStrictEqual(sb.visto.args, { p_proyecto_id:'p-bonian', p_modelos:['m-dali', 'm-dune'] });
  assert.strictEqual(sb.visto.from, 0, 'ni upsert ni delete desde el navegador');
  assert.strictEqual(r.altas, 2);
});

ok('declarar lo que ya estaba declarado no llama al servidor', async () => {
  const sb = sbFalso();
  const r = await lwDeclaraModelosEnProyecto(sb, 'Palm Field W5', ['m-dali', 'm-dream'],
    { catalogo:CATALOGO, villas:VILLAS, proyecto_id:'p-palm' });
  assert.strictEqual(r.altas, 0);
  assert.strictEqual(r.bajas, 0);
  assert.strictEqual(sb.visto.rpc, null, 'sin cambios no se escribe nada');
});

ok('🔴 un modelo que alguna parcela YA usa no se retira, y se dice por qué', async () => {
  const sb = sbFalso();
  const r = await lwDeclaraModelosEnProyecto(sb, 'Palm Field W5', ['m-dali'],
    { catalogo:CATALOGO, villas:VILLAS, proyecto_id:'p-palm', enUso:new Set(['Dream']) });
  assert.strictEqual(r.bajas, 0);
  assert.deepStrictEqual(r.rechazadas.map(x => x.modelo), ['Dream'],
    'se devuelve para poder decir POR QUE, no solo que no se pudo');
  assert.strictEqual(sb.visto.rpc, null, 'solo quitaba algo en uso: no hay nada que mandar');
});

ok('retirar uno que no usa nadie manda lo que debe QUEDAR y devuelve lo que dice el servidor', async () => {
  const sb = sbFalso({ altas:0, bajas:1, rechazadas:[] });
  const r = await lwDeclaraModelosEnProyecto(sb, 'Palm Field W5', ['m-dali'],
    { catalogo:CATALOGO, villas:VILLAS, proyecto_id:'p-palm', enUso:new Set() });
  assert.deepStrictEqual(sb.visto.args.p_modelos, ['m-dali']);
  assert.strictEqual(r.bajas, 1);
});

ok('sin id de proyecto no se escribe (el servidor trabaja por id, no por nombre)', async () => {
  const sb = sbFalso();
  const r = await lwDeclaraModelosEnProyecto(sb, 'Bonian Village', ['m-dali'], { catalogo:CATALOGO, villas:VILLAS });
  assert.strictEqual(r.ok, false);
  assert.strictEqual(sb.visto.rpc, null);
});

setTimeout(() => {
  console.log(fallos ? `\n${fallos} fallo(s)` : '\nOK modelos_catalogo.test.js — el catálogo se sostiene');
  process.exit(fallos ? 1 : 0);
}, 50);
