/* node operaciones/etapas.test.js
   La escalera de etapas del EMBUDO de Operaciones.

   POR QUÉ EXISTE. Los `FILTROS` de esa herramienta son predicados que se
   SOLAPAN: una misma operación está a la vez «sin firmar», «con pendiente» y
   «falta ficha». Un tablero exige lo contrario — cada tarjeta en UNA columna, o
   la suma de las columnas no cuadra con el total de operaciones y el tablero deja
   de ser de fiar. `etapa()` resuelve eso por ORDEN, y este test comprueba las dos
   propiedades que lo sostienen:
     1. cada caso cae en la etapa que le toca;
     2. NINGÚN caso cae fuera de una etapa declarada.

   La segunda es la que importa de verdad: si un día alguien añade un estado de
   contrato y `etapa()` no lo contempla, esas operaciones desaparecerían del
   tablero sin error ninguno. Aquí falla antes.

   Se extraen las funciones REALES de `index.html` en vez de copiarlas: probar una
   copia no prueba nada — es la misma razón por la que `contracts/cuenta_marcador.test.js`
   saca `tablaCuentaHTML` de `app.html`.
   `parseImporte` y `redondear` vienen de `facturas/totales.js`, que es lo que
   carga la página. */
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const AQUI = path.join(__dirname);
const pagina = fs.readFileSync(path.join(AQUI, 'index.html'), 'utf8');

/* las mismas piezas que carga la herramienta, no reimplementadas */
const totales = fs.readFileSync(path.join(AQUI, '..', 'facturas', 'totales.js'), 'utf8');
const cajaTotales = {};
new Function('caja', totales + '\n;Object.assign(caja,{parseImporte,redondear});')(cajaTotales);

const entre = (ini, fin) => {
  const a = pagina.indexOf(ini);
  assert.ok(a > 0, 'no encuentro en index.html: ' + ini);
  const b = pagina.indexOf(fin, a);
  assert.ok(b > a, 'no encuentro el final tras: ' + ini);
  return pagina.slice(a, b);
};
const fuente = entre('function cuenta(op){', '/* ---------- filtros ----------')
             + entre('const ETAPAS = [', '/* ---------- vista');
const { ETAPAS, etapa } = new Function('parseImporte', 'redondear',
  fuente + '\n;return { ETAPAS, etapa };')(cajaTotales.parseImporte, cajaTotales.redondear);

/* `cobrado` (11-ago-2026, reforma del modelo de facturación): cuenta() ya no
   suma `op.facturas` — lee `op.cobrado`, precalculado en Supabase por
   contrato_cobrado() (solo recibís, nunca facturas/proformas: ver
   facturas/sql/contrato_cobrado.sql). Los casos que antes construían
   `facturas: [{total:...}]` pasan un `cobrado` numérico directo — es
   exactamente lo que cuenta() consume ahora, y "solo proforma"/"factura
   anulada" ya no son escenarios distintos a nivel de cuenta(): el filtrado
   pasó a Supabase, así que ambos son sencillamente `cobrado: 0`. */
const op = o => Object.assign({ firmas: [], cobrado: 0, hijos: [], moneda: 'EUR' }, o);

const CASOS = [
  ['sin firmar, sin enlace',              op({ bloqueado: false }), 'sin_firmar'],
  ['sin firmar, con enlace vivo',         op({ bloqueado: false, firmas: [{ estado: 'pendiente' }] }), 'firma_viva'],
  /* un enlace anulado NO es «firma enviada»: nadie está esperando al comprador */
  ['sin firmar, enlace anulado',          op({ bloqueado: false, firmas: [{ estado: 'anulado' }] }), 'sin_firmar'],
  /* firmado manda sobre el enlace: la app anula los pendientes al cerrar la
     cadena, pero si uno se queda sin barrer no puede devolver el contrato a
     «firma enviada» */
  ['firmado con enlace sin barrer',       op({ bloqueado: true, precio_total: '100', cobrado: 100,
                                              firmas: [{ estado: 'pendiente' }] }), 'cobro_ok'],
  ['firmado, falta cobrar',               op({ bloqueado: true, precio_total: '100', cobrado: 40 }), 'cobro_pend'],
  ['firmado, cobrado entero',             op({ bloqueado: true, precio_total: '100', cobrado: 100 }), 'cobro_ok'],
  /* 🔴 el caso que decide el criterio: firmado y sin precio fijado NO se declara
     cobrado. No se sabe cuánto falta, y de los dos errores posibles solo uno
     cuesta dinero. */
  ['firmado SIN precio fijado',           op({ bloqueado: true, precio_total: '' }), 'cobro_pend'],
  /* una proforma o una factura sin recibí no suman nada a `cobrado` — el
     filtrado ya pasó por contrato_cobrado(), esto solo comprueba que
     cobrado:0 con precio fijado cae en pendiente */
  ['firmado, solo proforma o factura sin recibí', op({ bloqueado: true, precio_total: '100', cobrado: 0 }), 'cobro_pend'],
];

const claves = ETAPAS.map(e => e[0]);
assert.deepStrictEqual(claves, ['sin_firmar', 'firma_viva', 'cobro_pend', 'cobro_ok'],
  'las etapas cambiaron: repasa las columnas del tablero y este test');

for (const [nombre, o, esperado] of CASOS) {
  const r = etapa(o);
  assert.strictEqual(r, esperado, `«${nombre}» cayó en ${r} y debía ir a ${esperado}`);
  assert.ok(claves.includes(r), `«${nombre}» cayó FUERA de toda columna (${r}): desaparecería del tablero`);
}

/* y la propiedad general, no solo los casos de la lista: cualquier combinación de
   los tres ejes que decide la etapa tiene que aterrizar en una columna conocida.
   Son 2×3×3 = 18 combinaciones; a mano se olvidan la mitad. */
let n = 0;
for (const bloqueado of [false, true])
  for (const firma of [[], [{ estado: 'pendiente' }], [{ estado: 'anulado' }]])
    for (const cobrado of [0, 40, 100]) {
      const r = etapa(op({ bloqueado, firmas: firma, cobrado, precio_total: '100' }));
      assert.ok(claves.includes(r), `combinación sin columna: ${JSON.stringify({ bloqueado, firma, cobrado })} -> ${r}`);
      n++;
    }

console.log(`etapas.test.js OK · ${CASOS.length} casos con nombre + ${n} combinaciones, todas dentro de una columna`);
