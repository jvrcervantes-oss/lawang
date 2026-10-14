// Lo cobrado por contrato con la regla «primero la parcela, luego la obra» (F2, 14-oct-2026): node cobrado_regla.test.js
// 1) cobradoConRegla() de datos.js usa contratos_cobrado_regla_equipo y guarda lo de cada contrato por documento;
// 2) si la base no tiene esa función (instancias del ERP: el maestro no tiene la regla) cae a contratos_cobrado_equipo
//    callada (porRegla null); si la función falla de verdad, cae igual pero lo dice (porRegla false); nunca 0;
// 3) si fallan las dos, null y fallo() — no una lista vacía, que se leería «nada cobrado»;
// 4) movidosPorRegla() marca solo lo que cambia frente a lo que la pantalla enseñaba antes (lo suyo + sus Cartas);
// 5) Finanzas: la misma distinción en todas(); 6) quién la usa y qué rotula.
const fs = require('fs'), assert = require('assert');
const src = fs.readFileSync(__dirname + '/datos.js', 'utf8');
const pf = fs.readFileSync(__dirname + '/panel-finanzas.js', 'utf8');

function saca(texto, nombre) {
  const i = texto.indexOf('  function ' + nombre + '(');
  assert.ok(i > -1, 'ya no se define ' + nombre);
  const fin = texto.indexOf('\n  }', i);
  return texto.slice(i, texto.indexOf('\n', fin + 1));
}
// faltaRpc es de una línea: el trozo llega hasta el final de cobradoConRegla, que va justo detrás.
const fuente = saca(src, 'faltaRpc');
assert.ok(fuente.indexOf('function cobradoConRegla(') > -1, 'faltaRpc y cobradoConRegla van juntas');
const fallos = [], avisos = [];
const hace = new Function('vig', 'fallo', 'console', fuente + '\nreturn cobradoConRegla;');
const fn = hace((p) => p, (d) => fallos.push(d), { warn: (...a) => avisos.push(a) });
const sb = (respuestas) => ({ rpc: (n) => Promise.resolve(respuestas[n]) });

const movidosPorRegla = new Function('esPreliminar', saca(src, 'movidosPorRegla') + '\nreturn movidosPorRegla;')(
  (c) => /^carta_reserva/.test(c.tipo));

(async () => {
  // 1) con la regla
  let r = await fn(sb({ contratos_cobrado_regla_equipo: { data: [
    { contrato_id: 'rp', cobrado: 25000, cobrado_doc: 41620 },
    { contrato_id: 'cc', cobrado: 16620, cobrado_doc: 0 },
    { contrato_id: 'x', cobrado: 100, cobrado_doc: 100 } ] } }));
  assert.strictEqual(r.porRegla, true);
  assert.strictEqual(r.filas.length, 3);
  assert.deepStrictEqual(r.doc, { rp: 41620, cc: 0, x: 100 });

  // 4) movidos: SH-1 (Bloqueo y Construcción) cambian; un Bloqueo con Carta cobrada que la regla deja igual, no
  const cs = [{ id: 'rp', tipo: 'reserva_parcela' }, { id: 'cc', tipo: 'construccion', contrato_padre_id: 'rp' },
              { id: 'x', tipo: 'reserva_parcela' }];
  assert.deepStrictEqual(movidosPorRegla(r, cs), { rp: 41620, cc: 0 });
  const conCarta = { porRegla: true, doc: { b: 5000, cr: 2000 },
    filas: [{ contrato_id: 'b', cobrado: 7000 }, { contrato_id: 'cr', cobrado: 0 }] };
  const csCarta = [{ id: 'b', tipo: 'reserva_parcela' }, { id: 'cr', tipo: 'carta_reserva', contrato_padre_id: 'b' }];
  assert.deepStrictEqual(movidosPorRegla(conCarta, csCarta), { cr: 2000 },
    'el Bloqueo enseñaba ya 5.000 + 2.000 de su Carta: no se marca; la Carta sí cambia (su dinero pasa al Bloqueo)');
  // venta que la regla no reparte (o que el usuario no ve entera): la base devuelve lo de documento → nada marcado
  // (revisor, 2.ª vuelta: con la comparación anterior salía {b: 5000})
  const sinRepartir = { porRegla: true, doc: { b: 5000, cr: 2000 },
    filas: [{ contrato_id: 'b', cobrado: 5000 }, { contrato_id: 'cr', cobrado: 2000 }] };
  assert.deepStrictEqual(movidosPorRegla(sinRepartir, csCarta), {});
  assert.deepStrictEqual(movidosPorRegla({ porRegla: null, doc: {}, filas: [] }, cs), {});
  assert.deepStrictEqual(movidosPorRegla(null, cs), {});

  // 2a) la base no tiene la función: lo de siempre, sin aviso ni rótulo
  r = await fn(sb({ contratos_cobrado_regla_equipo: { error: { code: 'PGRST202', message: 'not found' } },
                    contratos_cobrado_equipo: { data: [{ contrato_id: 'rp', cobrado: 41620 }] } }));
  assert.strictEqual(r.porRegla, null);
  assert.deepStrictEqual(r.filas, [{ contrato_id: 'rp', cobrado: 41620 }]);
  assert.strictEqual(avisos.length, 0, 'sin la función es lo normal: no se avisa');

  // 2b) la función falla de verdad: lo de siempre, avisado y rotulado
  r = await fn(sb({ contratos_cobrado_regla_equipo: { error: { code: '57014', message: 'timeout' } },
                    contratos_cobrado_equipo: { data: [{ contrato_id: 'rp', cobrado: 41620 }] } }));
  assert.strictEqual(r.porRegla, false);
  assert.strictEqual(avisos.length, 1);

  // 3) las dos caídas
  r = await fn(sb({ contratos_cobrado_regla_equipo: { error: { message: 'x' } }, contratos_cobrado_equipo: { error: { message: 'y' } } }));
  assert.strictEqual(r, null);
  assert.deepStrictEqual(fallos, ['cobrado']);

  // 5) Finanzas: todas() marca «falta» solo si se le dice que puede faltar y el error es ese
  const errores = [];
  const todas = new Function('PAGINA', 'console', saca(pf, 'todas') + '\nreturn todas;')(1000, { error: (...a) => errores.push(a) });
  const pide = (error) => () => ({ order: () => ({ range: () => Promise.resolve({ error }) }) });
  let e = await todas(pide({ code: 'PGRST202' }), 'regla', 'contrato_id', true).catch((x) => x);
  assert.strictEqual(e.falta, true); assert.strictEqual(errores.length, 0);
  e = await todas(pide({ code: 'PGRST202' }), 'otra', 'id').catch((x) => x);
  assert.strictEqual(e.falta, false); assert.strictEqual(errores.length, 1, 'sin puedeFaltar, una función que falta es un fallo');
  e = await todas(pide({ code: '57014' }), 'regla', 'contrato_id', true).catch((x) => x);
  assert.strictEqual(e.falta, false); assert.strictEqual(errores.length, 2);
  assert.ok(/'cobrado por contrato con la regla', 'contrato_id', true\)/.test(pf), 'Finanzas pide la regla diciendo que puede faltar');
  assert.ok(/porRegla: e && e\.falta \? null : false/.test(pf), 'Finanzas distingue «no la tiene» de «falló»');

  // 6) quién la usa y qué rotula: solo un fallo de verdad lleva el aviso
  assert.ok(/cobradoConRegla\(sb\),\s*\r?\n\s*q\(sb\.from\('contrato_vencimientos'\)/.test(src), 'Vencimientos pide lo cobrado con la regla');
  assert.ok(/MOVIDOS = movidosPorRegla\(cb, cs\);/.test(src), 'Vencimientos marca con movidosPorRegla');
  assert.ok(/REGLA === false \? ' · ' \+ ts\('cobrado por contrato, sin la regla de la parcela'\)/.test(src), 'Vencimientos rotula solo el fallo');
  assert.ok(/d\.cobrado\.porRegla === false \? ' · ' \+ T\('cobrado por contrato, sin la regla de la parcela'\)/.test(pf), 'Finanzas rotula solo el fallo');
  console.log('cobrado_regla.test.js: ok');
})().catch((e) => { console.error(e); process.exit(1); });
