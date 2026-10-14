// Lo cobrado por contrato con la regla «primero la parcela, luego la obra» (F2, 14-oct-2026): node cobrado_regla.test.js
// 1) cobradoConRegla() de datos.js usa contratos_cobrado_regla_equipo y marca los contratos que la regla movió;
// 2) sin esa RPC (el maestro del ERP aún no la tiene) cae a contratos_cobrado_equipo, nunca a 0, y lo dice;
// 3) si fallan las dos, null y fallo() — no una lista vacía, que se leería «nada cobrado»;
// 4) Vencimientos y Finanzas la usan (y Finanzas con la misma vuelta atrás).
const fs = require('fs'), assert = require('assert');
const src = fs.readFileSync(__dirname + '/datos.js', 'utf8');
const pf = fs.readFileSync(__dirname + '/panel-finanzas.js', 'utf8');

function saca(nombre) {
  const i = src.indexOf('  function ' + nombre + '(');
  assert.ok(i > -1, 'datos.js ya no define ' + nombre);
  const fin = src.indexOf('\n  }', i);
  return src.slice(i, src.indexOf('\n', fin + 1));
}
const fuente = saca('cobradoConRegla');
const fallos = [];
const hace = new Function('vig', 'fallo', 'console', fuente + '\nreturn cobradoConRegla;');
const consola = { warn: () => {} };
const fn = hace((p) => p, (d, e) => fallos.push(d), consola);
const sb = (respuestas) => ({ rpc: (n) => Promise.resolve(respuestas[n]) });

(async () => {
  // 1) con la regla
  let r = await fn(sb({ contratos_cobrado_regla_equipo: { data: [
    { contrato_id: 'rp', cobrado: 25000, cobrado_doc: 41620 },
    { contrato_id: 'cc', cobrado: 16620, cobrado_doc: 0 },
    { contrato_id: 'x', cobrado: 100, cobrado_doc: 100 } ] } }));
  assert.strictEqual(r.porRegla, true);
  assert.strictEqual(r.filas.length, 3);
  assert.deepStrictEqual(r.movidos, { rp: 41620, cc: 0 }, 'solo se marcan los que la regla movió, con su cifra por documento');

  // 2) sin la RPC nueva: lo de siempre, rotulado
  r = await fn(sb({ contratos_cobrado_regla_equipo: { error: { code: 'PGRST202', message: 'not found' } },
                    contratos_cobrado_equipo: { data: [{ contrato_id: 'rp', cobrado: 41620 }] } }));
  assert.strictEqual(r.porRegla, false);
  assert.deepStrictEqual(r.filas, [{ contrato_id: 'rp', cobrado: 41620 }]);
  assert.deepStrictEqual(r.movidos, {});

  // 3) las dos caídas
  r = await fn(sb({ contratos_cobrado_regla_equipo: { error: { message: 'x' } }, contratos_cobrado_equipo: { error: { message: 'y' } } }));
  assert.strictEqual(r, null);
  assert.deepStrictEqual(fallos, ['cobrado']);

  // 4) quién la usa
  assert.ok(/cobradoConRegla\(sb\),\s*\r?\n\s*q\(sb\.from\('contrato_vencimientos'\)/.test(src), 'Vencimientos pide lo cobrado con la regla');
  assert.ok(pf.indexOf("sb.rpc('contratos_cobrado_regla_equipo')") > -1 && pf.indexOf("sb.rpc('contratos_cobrado_equipo')") > pf.indexOf("sb.rpc('contratos_cobrado_regla_equipo')"),
    'Finanzas pide la regla y, si falla, cae a lo cobrado por documento');
  console.log('cobrado_regla.test.js: ok');
})().catch((e) => { console.error(e); process.exit(1); });
