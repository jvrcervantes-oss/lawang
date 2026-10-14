/* node cobrado_venta.test.js — factura-vencimiento descuenta lo cobrado de la VENTA con la regla «primero la parcela,
   luego la obra» (owner, 14-oct-2026; F5 del encargo de la agencia 20261014_lawang_cobro_primero_parcela).
   Ejecuta cobradoDe() de index.ts (extraída y sin tipos, como firmaDe en firma.test.js) contra una base simulada:
   1. con la función en la base: su cifra, `regla: true`, y no se toca contrato_cobrado (también con data null → 0);
   2. sin la función (PGRST202: bbm, demo): lo de siempre = lo suyo + sus Cartas, nunca otros hijos; `regla: false`;
   3. cualquier otro error, también en el respaldo, LANZA: nunca devuelve 0 (con 0 se facturaría el hito bruto, el
      fallo del 11-ago), y el bucle lo manda a «para revisar».
   4. el bucle usa cobradoDe y cuenta en `cobrado_sin_regla` los hitos que fueron por el respaldo. */
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { stripTypeScriptTypes } = require('module');

const src = fs.readFileSync(path.join(__dirname, 'index.ts'), 'utf8').replace(/\r\n/g, '\n');
const m = /async function cobradoDe\([\s\S]*?\n}\n/.exec(src);
assert.ok(m, 'no encuentro cobradoDe');
const cobradoDe = new Function(stripTypeScriptTypes(m[0]) + '\nreturn cobradoDe;')();
const C = { lwEsPreliminar: (t) => String(t || '').startsWith('carta_reserva') };

/* base simulada: rpcs = { nombre: (args) => ({ data, error }) }, hijos = filas de contratos hijos (o { error }) */
function base(rpcs, hijos) {
  const llamadas = [];
  return {
    llamadas,
    rpc: async (nombre, args) => { llamadas.push(nombre); return rpcs[nombre](args); },
    from: (tabla) => ({ select: () => ({ eq: async () => {
      assert.strictEqual(tabla, 'contratos'); llamadas.push('hijos');
      return hijos && hijos.error ? { data: null, error: hijos.error } : { data: hijos || [], error: null };
    } }) }),
  };
}
const NO_EXISTE = { code: 'PGRST202', message: 'Could not find the function public._contrato_cobrado_venta' };
const COBRADO = { 'yo': 5000, 'carta': 1000, 'obra-hija': 9000 };
const porDocumento = (a) => ({ data: COBRADO[a.p_contrato_id] ?? 0, error: null });

(async () => {
  // 1 · con la regla
  let sb = base({ _contrato_cobrado_venta: (a) => ({ data: a.p_contrato === 'yo' ? 26500 : null, error: null }) });
  assert.deepStrictEqual(await cobradoDe(sb, C, 'yo'), { cobrado: 26500, regla: true });
  assert.deepStrictEqual(sb.llamadas, ['_contrato_cobrado_venta'], 'con la función en la base no se calcula por documento');
  assert.deepStrictEqual(await cobradoDe(sb, C, 'otro'), { cobrado: 0, regla: true }, 'data null = 0 cobrado, con la regla');

  // 2 · sin la función: lo suyo + sus Cartas (la obra hija no suma)
  sb = base({ _contrato_cobrado_venta: () => ({ data: null, error: NO_EXISTE }), contrato_cobrado: porDocumento },
            [{ id: 'carta', tipo: 'carta_reserva' }, { id: 'obra-hija', tipo: 'construccion' }]);
  assert.deepStrictEqual(await cobradoDe(sb, C, 'yo'), { cobrado: 6000, regla: false });

  // 3 · cualquier otro error lanza, también dentro del respaldo
  const caida = { code: '57014', message: 'canceling statement due to statement timeout' };
  sb = base({ _contrato_cobrado_venta: () => ({ data: null, error: caida }), contrato_cobrado: porDocumento });
  await assert.rejects(cobradoDe(sb, C, 'yo'), /lo cobrado de la venta: canceling/);
  assert.ok(!sb.llamadas.includes('contrato_cobrado'), 'un error que no es PGRST202 no cae al respaldo');
  sb = base({ _contrato_cobrado_venta: () => ({ data: null, error: NO_EXISTE }), contrato_cobrado: () => ({ data: null, error: caida }) }, []);
  await assert.rejects(cobradoDe(sb, C, 'yo'), /lo cobrado del contrato: /);
  sb = base({ _contrato_cobrado_venta: () => ({ data: null, error: NO_EXISTE }), contrato_cobrado: porDocumento }, { error: caida });
  await assert.rejects(cobradoDe(sb, C, 'yo'), /los hijos del contrato: /);
  sb = base({ _contrato_cobrado_venta: () => ({ data: null, error: NO_EXISTE }),
              contrato_cobrado: (a) => a.p_contrato_id === 'carta' ? { data: null, error: caida } : porDocumento(a) },
            [{ id: 'carta', tipo: 'carta_reserva' }]);
  await assert.rejects(cobradoDe(sb, C, 'yo'), /lo cobrado de la Carta carta: /);

  // 4 · el bucle
  const ini = src.indexOf('// ── lo pendiente DE VERDAD'), fin = src.indexOf('const anotados = C.cascada(');
  assert.ok(ini > 0 && fin > ini, 'no encuentro el bloque de lo cobrado del bucle');
  const bloque = src.slice(ini, fin);
  assert.ok(bloque.includes('cobradoDe(sb, C, v.contrato_id)') && bloque.includes('if (!cob.regla) sinRegla++;'), 'el bucle no usa cobradoDe o no cuenta el respaldo');
  assert.ok(!bloque.includes("rpc('contrato_cobrado'"), 'el bucle vuelve a calcular por documento por su cuenta');
  assert.ok(src.includes('cobrado_sin_regla: sinRegla'), 'la respuesta no dice cuántos hitos fueron sin la regla');

  console.log('OK cobrado_venta.test.js — con la regla, respaldo solo en PGRST202 (lo suyo + Cartas), ningún error se convierte en 0, el bucle lo cuenta');
})().catch((e) => { console.error(e); process.exit(1); });
