/* ═══════════════════════════════════════════════════════════════════════════
   EL PRECIO DE LA VENTA SOLO SUMA LA OBRA VIGENTE — 15-oct-2026
   `node precio_cadena_vigente.test.js`. Lo corre `tools/test.py`, y con él el gate.
   ═══════════════════════════════════════════════════════════════════════════
   POR QUÉ EXISTE. El precio de una venta sumaba también los contratos de obra
   ya sustituidos: RP00101 tenía la obra CC00062 en borrador y la CC00102
   firmada (las dos de 44.000) y el precio salía 113.000 en vez de 69.000. Lo
   arregla en el servidor la migración 20261015101833_precio_cadena_vigente
   (public._venta_obras_vigentes, una sola regla). La lista de Operaciones, el
   Saldo y la ficha suman en el navegador con `cuentaGrupo`
   (assets/operaciones-cuentas.js), que es su gemela y tiene que decir lo mismo.

   Esto afirma, ejecutando el código real de cuentaGrupo:
     1. RP00101: Bloqueo 25.000 + obra borrador sustituida + obra firmada = 69.000.
     2. Por parcela: en una parcela la firmada gana a un borrador más nuevo; en
        otra, dos borradores → el más reciente; el grupo sin unidad cuenta
        aparte; una obra liberada no suma.
     3. Una pieza que no trae unidad_id cuenta como antes (no se agrupa a ciegas).
     4. Las tres consultas que alimentan cuentaGrupo piden unidad_id.
   ═══════════════════════════════════════════════════════════════════════════ */
const fs = require('fs');
const path = require('path');
const vm = require('vm');

let fallos = 0;
function ok(nombre, cond) {
  console.log((cond ? '  ok   ' : '  MAL  ') + nombre);
  if (!cond) fallos++;
}
function trozo(src, ini, fin, donde) {
  const i = src.indexOf(ini);
  if (i < 0) throw new Error('no encuentro «' + ini + '» en ' + donde);
  const j = src.indexOf(fin, i);
  if (j < 0) throw new Error('no encuentro el final de «' + ini + '» en ' + donde);
  return src.slice(i, j);
}

const opsSrc = fs.readFileSync(path.join(__dirname, 'assets', 'operaciones-cuentas.js'), 'utf8');
const cg = trozo(opsSrc, 'function cuentaGrupo(op){', '\n}\n', 'operaciones-cuentas') + '\n}';
const ctx = { PIEZAS_ACOMPANAN: ['poa', 'hak_sewa_notario', 'adenda'], lwEsPreliminar: t => /^carta_reserva/.test(t || ''),
  parseImporte: v => (v == null ? null : Number(v)), redondear: v => Math.round(v * 100) / 100, Set };
vm.createContext(ctx);
vm.runInContext(cg + '\nthis.cuentaGrupo = cuentaGrupo;', ctx);

// 1. RP00101
{
  const raiz = { id: 'r1', tipo: 'reserva_parcela', precio_total: 25000, bloqueado: true, cobrado: 0, moneda: 'EUR', unidad_id: null,
                 created_at: '2026-08-26T10:00:00Z' };
  raiz.hijos = [
    { id: 'cb', tipo: 'construccion', precio_total: 44000, bloqueado: false, cobrado: 0, moneda: 'EUR', unidad_id: 'sh36', created_at: '2026-08-26T11:00:00Z' },
    { id: 'cf', tipo: 'construccion', precio_total: 44000, bloqueado: true,  cobrado: 0, moneda: 'EUR', unidad_id: 'sh36', created_at: '2026-09-16T10:00:00Z' },
  ];
  const r = ctx.cuentaGrupo(raiz);
  ok('RP00101: el borrador sustituido no suma; precio = 25.000 + 44.000 = 69.000 (antes 113.000)', r.precio === 69000);
  // y lo mismo pidiéndolo desde un hijo (la operación se abre desde la obra)
  raiz.hijos.forEach(h => { h.padre = raiz; });
  ok('RP00101 desde el borrador: la misma cadena, 69.000', ctx.cuentaGrupo(raiz.hijos[0]).precio === 69000);
}

// 2. por parcela, sin parcela y liberada
{
  const raiz = { id: 'r2', tipo: 'reserva_parcela', precio_total: 10000, bloqueado: true, cobrado: 0, moneda: 'EUR', unidad_id: null, created_at: '2026-09-01' };
  const h = (id, precio, firmado, unidad, fecha, extra) => Object.assign(
    { id, tipo: 'construccion', precio_total: precio, bloqueado: firmado, cobrado: 0, moneda: 'EUR', unidad_id: unidad, created_at: fecha }, extra || {});
  raiz.hijos = [
    h('o2a', 20000, true,  'u2', '2026-09-02'), h('o2b', 30000, false, 'u2', '2026-09-05'),
    h('o3a', 15000, false, 'u3', '2026-09-02'), h('o3b', 16000, false, 'u3', '2026-09-06'),
    h('o4',   5000, false, null, '2026-09-03'), h('o5',   7000, false, null, '2026-09-07', { liberado_en: '2026-09-08' }),
    h('o6',      9, false, null, '2026-09-08', { moneda: 'IDR' }),
  ];
  ok('dos parcelas y un sin parcela: 10.000 + 20.000 (firmada) + 16.000 (borrador más nuevo) + 5.000 = 51.000 (la regla de la migración, prueba V4 en rama)',
     ctx.cuentaGrupo(raiz).precio === 51000);
}

// 3. sin unidad_id en la pieza (consulta que no lo pide): cuenta como antes
{
  const raiz = { tipo: 'reserva_parcela', precio_total: 1000, cobrado: 0, moneda: 'EUR' };
  raiz.hijos = [{ tipo: 'construccion', precio_total: 500, bloqueado: false, cobrado: 0, moneda: 'EUR' },
                { tipo: 'construccion', precio_total: 700, bloqueado: true,  cobrado: 0, moneda: 'EUR' }];
  ok('sin unidad_id no se agrupa: suman las dos, como antes (1.000 + 500 + 700)', ctx.cuentaGrupo(raiz).precio === 2200);
}

// 4. las consultas que alimentan cuentaGrupo piden unidad_id
{
  const datos = fs.readFileSync(path.join(__dirname, '..', 'intranet', 'v4', 'assets', 'datos.js'), 'utf8');
  ok('lwOperacionesCargar pide unidad_id a contratos_equipo',
     /rpc\('contratos_equipo'\)\.select\('id,numero,tipo,[^']*\bunidad_id\b[^']*'/.test(trozo(opsSrc, 'async function lwOperacionesCargar', '\n}\n', 'operaciones-cuentas')));
  ok('la ficha (CAMPOS_CONTRATO) pide unidad_id', /var CAMPOS_CONTRATO = '[^']*\bunidad_id\b[^']*'/.test(datos));
  ok('la familia de la ficha pide unidad_id', /select\('[^']*\bunidad_id\b[^']*'\)\.or\(familia\)/.test(datos));
}

if (fallos) { console.log('\n' + fallos + ' MAL'); process.exit(1); }
console.log('\nprecio_cadena_vigente: todo ok');
