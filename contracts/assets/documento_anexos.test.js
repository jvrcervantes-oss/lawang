/* node documento_anexos.test.js — el Anexo Maestro automático (27-sep-2026).
   Ejecuta el documento_anexos.js REAL en un sandbox, con Supabase, fetch y pdf.js
   falsos, y recorre las salidas de syncAutoAnnex().

   POR QUÉ EXISTE: el 26-sep (c1db7ddc) se borró `sha256hex` de app.html al pasar la
   firma al servidor, y este fichero la seguía llamando. Cada anexo automático moría
   en un ReferenceError que el catch convertía en «Dali no tiene Anexo Maestro», con
   el plano subido y legible. `node --check` no lo ve (la sintaxis era válida) y el
   navegador tampoco lo gritaba: el catch se lo tragaba. El caso 1 es el que habría
   parado aquel commit; los demás fijan que cada salida diga lo que de verdad pasó. */
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const CODIGO = fs.readFileSync(path.join(__dirname, 'documento_anexos.js'), 'utf8');
const DALI = { id: 'dali-id', nombre: 'Dali' };
const PLANOS = [
  { path: 'dali-id/bambu.pdf', nombre: 'Dali - Bambu - Anexo Maestro.pdf', tipo: 'plano', techo_clave: 'bambu', subido_en: '2026-09-23' },
  { path: 'dali-id/sirap.pdf', nombre: 'Dali - Sirap - Anexo Maestro.pdf', tipo: 'plano', techo_clave: 'sirap', subido_en: '2026-09-23' },
];

function montar(o) {
  const toasts = [], males = [];
  const pedidos = [];
  const subidos = [];
  const sb = {
    // Cada tabla con su respuesta: el mock de `modelo_documentos` no puede contestar por
    // `contrato_anexo_paginas` (LAW-78), o las pruebas nuevas pasarían por el motivo equivocado.
    from: (tabla) => {
      const resp = tabla === 'contrato_anexo_paginas'
        ? (o.filasFalla ? { data: null, error: { message: 'red caída' } } : { data: o.filas || [], error: null })
        : (o.consultaFalla ? { data: null, error: { message: 'red caída' } } : { data: o.planos, error: null });
      const q = { select: () => q, eq: () => q, order: () => q, then: (f, r) => Promise.resolve(resp).then(f, r) };
      return q;
    },
    storage: { from: () => ({
      createSignedUrl: p => { pedidos.push(p); return Promise.resolve({ data: { signedUrl: 'https://x/' + p }, error: null }); },
      createSignedUrls: ps => Promise.resolve({ data: ps.map(p => ({ path: p, signedUrl: 'https://anx/' + p })), error: null }),
      uploadToSignedUrl: (p, t, blob) => { subidos.push(p); return Promise.resolve({ error: null }); },
    }) },
  };
  const ctx = {
    console, Promise, Object, Error, Uint8Array, TextEncoder, setTimeout,
    crypto: require('crypto').webcrypto,
    localStorage: { getItem: () => null, setItem() {} },
    document: { querySelector: s => (s === '[name="tipologia_construccion"]' ? { value: o.tipologia || 'Dali' } : null) },
    $: () => null,
    render() {}, toast: m => toasts.push(m), toastMal: m => males.push(m),
    fetch: (u) => {
      if (String(u).startsWith('https://anx/')) {
        const b = (o.bytesDe || {})[String(u).slice(12)];
        return Promise.resolve(b ? { ok: true, arrayBuffer: () => Promise.resolve(b.buffer) } : { ok: false, status: 404 });
      }
      return Promise.resolve(o.fetchFalla ? { ok: false, status: 404 } : { ok: true, arrayBuffer: () => Promise.resolve(new Uint8Array([37, 80, 68, 70]).buffer) });
    },
    atob: (x) => Buffer.from(x, 'base64').toString('binary'), btoa: (x) => Buffer.from(x, 'binary').toString('base64'),
    Blob: class { constructor(p, o2) { this.p = p; this.type = o2 && o2.type; } },
    lwFichero: o.lwFichero,
    SAVED_CONTRACT: o.contrato ? { id: o.contrato } : null,
    SIGN_MODE: false,
    sb,
    CATALOGO_MODELOS: o.sinCatalogo ? null : { catalogo: [DALI] },
    fichaDelModelo: n => (n === 'Dali' ? DALI : null),
    TECHO_ELEGIDO: o.techo ? { clave: o.techo, nombre: o.techo === 'sirap' ? 'Sirap Ulin' : 'Bamboo' } : null,
    TECHO_CARGANDO: false,
    ANNEXES: o.annexes || [],
  };
  ctx.window = ctx;
  vm.createContext(ctx);
  vm.runInContext(CODIGO, ctx);
  // pdf.js necesita canvas: la conversión se sustituye; la huella (sha256hex) NO, es la que se vigila.
  vm.runInContext(o.convierteFalla
    ? 'pdfToImages = async () => { throw new Error("canvas sin memoria"); }'
    : 'pdfToImages = async () => ["data:image/jpeg;base64,AAA", "data:image/jpeg;base64,BBB"]', ctx);
  return { ctx, toasts, males, pedidos, subidos, lee: n => vm.runInContext(n, ctx) };
}

(async () => {
  // 1. Dali + Sirap, con plano: se adjunta el de SU techo, con huella.
  let m = montar({ planos: PLANOS, techo: 'sirap' });
  assert.strictEqual(m.lee('typeof sha256hex'), 'function', 'documento_anexos.js tiene que definir sha256hex: es su único llamador');
  await m.lee('syncAutoAnnex()');
  let auto = m.ctx.ANNEXES.find(a => a.auto);
  assert.ok(auto, 'con el plano en Modelos el anexo automático se adjunta: ' + JSON.stringify({ t: m.toasts, mal: m.males }));
  assert.strictEqual(auto.pages.length, 2);
  assert.strictEqual(auto.techo, 'sirap');
  assert.match(auto.sha, /^[0-9a-f]{64}$/, 'la huella del PDF se calcula');
  assert.deepStrictEqual(m.pedidos, ['dali-id/sirap.pdf'], 'se pide el plano del techo elegido, no el de otro');
  assert.ok(/Planos y Especificaciones · Dali · Sirap Ulin/.test(auto.title));
  assert.strictEqual(m.males.length, 0);
  assert.ok(m.toasts.some(t => /adjuntado \(2 pág\.\)/.test(t)));
  assert.strictEqual(m.lee('AUTO_CARGA'), '', '«Preparando…» no se queda colgado');

  // 1b. Lo mismo con Bambú.
  m = montar({ planos: PLANOS, techo: 'bambu' });
  await m.lee('syncAutoAnnex()');
  assert.deepStrictEqual(m.pedidos, ['dali-id/bambu.pdf']);
  assert.ok(m.ctx.ANNEXES.some(a => a.auto && a.techo === 'bambu' && a.pages.length === 2));

  // 2. Sin plano de ese techo: aviso NEUTRO, sin rojo, y queda pintado en el panel.
  m = montar({ planos: [PLANOS[0]], techo: 'sirap' });
  await m.lee('syncAutoAnnex()');
  assert.ok(!m.ctx.ANNEXES.some(a => a.auto), 'un plano de OTRO techo nunca se usa');
  assert.strictEqual(m.males.length, 0, 'no tener plano no es un fallo: ' + m.males);
  assert.ok(m.toasts.some(t => /no tiene Anexo Maestro con el techo elegido/.test(t)));
  assert.strictEqual(m.lee('AUTO_AVISO.mal'), false);
  assert.strictEqual(m.lee('AUTO_CARGA'), '');

  // 3. Hay plano pero no se descarga: UN solo mensaje, en rojo, con el nombre y el motivo,
  //    y NUNCA «no tiene» (antes salían los dos y el segundo tapaba al primero).
  m = montar({ planos: PLANOS, techo: 'sirap', fetchFalla: true });
  await m.lee('syncAutoAnnex()');
  assert.strictEqual(m.males.length, 1, JSON.stringify(m.males));
  assert.match(m.males[0], /Dali - Sirap - Anexo Maestro\.pdf.*está en Modelos.*HTTP 404/);
  assert.ok(!m.toasts.some(t => /no tiene Anexo Maestro/.test(t)), 'con plano en Modelos no se dice que no lo tiene');
  assert.strictEqual(m.lee('AUTO_AVISO.mal'), true);

  // 4. Se descarga pero no se convierte: rojo con motivo, y la ficha guardada del
  //    anexo (su `on` y su `sha`) sobrevive, sin páginas, para no perderla al guardar.
  const guardado = { id: 'axauto', auto: 'Dali', techo: 'sirap', sha: 'abc', on: false, pages: ['vieja'] };
  m = montar({ planos: PLANOS, techo: 'sirap', convierteFalla: true, annexes: [guardado] });
  await m.lee('syncAutoAnnex()');
  assert.strictEqual(m.males.length, 1);
  assert.match(m.males[0], /no se ha podido convertir a páginas: canvas sin memoria/);
  auto = m.ctx.ANNEXES.find(a => a.auto);
  assert.ok(auto && auto.sha === 'abc' && auto.on === false && auto.pages.length === 0,
    'la ficha guardada se conserva sin páginas (no se imprime, no se pierde): ' + JSON.stringify(auto));
  assert.strictEqual(m.lee('AUTO_CARGA'), '');

  // 5. No se ha podido ni mirar (catálogo o consulta): rojo, «no se ha podido comprobar».
  for (const caso of [{ sinCatalogo: true }, { consultaFalla: true }]) {
    m = montar(Object.assign({ planos: PLANOS, techo: 'sirap' }, caso));
    await m.lee('syncAutoAnnex()');
    assert.strictEqual(m.males.length, 1, JSON.stringify(caso));
    assert.match(m.males[0], /No se ha podido comprobar si Dali tiene Anexo Maestro/);
    assert.ok(!m.toasts.some(t => /no tiene Anexo Maestro/.test(t)), 'no haber podido mirar no es «no tiene»');
  }

  // 6. Modelo sin plano ninguno (ni genérico): neutro.
  m = montar({ planos: [], techo: 'sirap' });
  await m.lee('syncAutoAnnex()');
  assert.strictEqual(m.males.length, 0);
  assert.ok(m.toasts.some(t => /no tiene Anexo Maestro/.test(t)));

  /* ═══ LAW-78 (27-sep-2026): anexos subidos a mano en Storage ═══════════════════════════
     Lo que no puede pasar: guardar o firmar con una página que falta o que no es la que se
     subió; perder un anexo viejo porque su paso al archivo falló a medias; bytes o URLs en
     el borrador local; un id de anexo reutilizado. */
  const C1 = '0f1e2d3c-4b5a-4968-8776-655443322110';
  const C2 = '11111111-2222-4333-8444-555555555555';
  const jpg = n => new Uint8Array([0xff, 0xd8, 0xff, 0xe0, n, n, n, 0xff, 0xd9]);
  const dataUrl = b => 'data:image/jpeg;base64,' + Buffer.from(b).toString('base64');
  const sha = b => require('crypto').createHash('sha256').update(Buffer.from(b)).digest('hex');
  const fila = (anexo, n, b) => ({ anexo_id: anexo, n, path: C1 + '/u' + anexo + n + '/' + n + '.jpg', sha256: sha(b), bytes: b.length });

  // 7. problemasAnexos: nombra anexo y página; «cargando» y «falta» son cosas distintas.
  m = montar({});
  const J = x => JSON.parse(JSON.stringify(x));   // de otro contexto de vm: deepStrictEqual mira el prototipo
  const P = (lista, op) => { m.ctx._l = lista; m.ctx._o = op; return J(m.lee('problemasAnexos(_l, _o)')); };
  const ok = { id: 'ax-a', title: 'Planos', on: true, pages: ['d1', 'd2'], almacen: [{ n: 1 }, { n: 2 }], contrato: C1, estado: 'ok', faltan: [] };
  assert.deepStrictEqual(P([ok]), [], 'un anexo del archivo entero no bloquea');
  assert.deepStrictEqual(P([{ id: 'ax1', title: 'Viejo', on: true, pages: ['d'] }]), [], 'un anexo viejo con sus páginas no bloquea');
  assert.match(P([{ ...ok, pages: ['d1', null], faltan: [2] }])[0], /página 2 del anexo «Planos».*huella/);
  assert.match(P([{ ...ok, almacen: [{ n: 1 }, { n: 3 }], pages: ['d1', 'd3'] }])[0], /falta la página 2 del anexo «Planos»/);
  assert.match(P([{ ...ok, estado: 'cargando', pages: [] }])[0], /aún se está cargando/);
  assert.match(P([{ ...ok, estado: 'error', error: 'red caída' }])[0], /no se ha podido comprobar el anexo «Planos» \(red caída\)/);
  assert.match(P([{ id: 'ax-b', title: 'Suelto', on: true }])[0], /«Suelto» no tiene páginas/);
  assert.deepStrictEqual(P([{ ...ok, on: false, pages: [null, null], faltan: [1, 2] }], { soloIncluidos: true }), [],
    'para firmar solo cuentan los incluidos');
  assert.strictEqual(P([{ ...ok, on: false, pages: [null, null], faltan: [1, 2] }]).length, 2, 'para guardar, todos');

  // 8. fichaDatos: a `datos` solo la ficha, y solo si las filas son de ESTE contrato.
  m.ctx._a = ok;
  assert.deepStrictEqual(JSON.parse(JSON.stringify(m.lee(`fichaDatos(_a, '${C1}')`))), { id: 'ax-a', title: 'Planos', on: true });
  assert.deepStrictEqual(J(m.lee(`fichaDatos(_a, '${C2}')`).pages), ['d1', 'd2'], 'filas de otro contrato: viaja con páginas');
  m.ctx._a = { id: 'axauto', auto: 'Dali', pages: ['x'], estado: 'ok', almacen: [] };
  const fa = m.lee('fichaDatos(_a)');
  assert.deepStrictEqual([fa.pages.length, 'estado' in fa, 'almacen' in fa], [0, false, false], 'el automático, sin páginas ni estado de memoria');

  // 9. Migración perezosa: el que sube, id nuevo y sin páginas en datos; el que falla, intacto.
  const viejoA = { id: 'ax1', title: 'A', on: true, pages: ['a1', 'a2'] };
  const viejoB = { id: 'ax2', title: 'B', on: false, pages: ['b1'] };
  m.ctx._l = [{ id: 'axauto', auto: 'Dali', pages: ['p'] }, viejoA, viejoB];
  assert.deepStrictEqual(J(m.lee(`anexosAMigrar(_l, '${C1}').map(a => a.id)`)), ['ax1', 'ax2']);
  m.ctx._h = { ax1: { id: 'ax-nuevo', filas: [{ n: 1 }, { n: 2 }] } };
  const tras = m.lee(`aplicaMigracion(_l, _h, '${C1}')`);
  assert.strictEqual(tras[1].id, 'ax-nuevo');
  assert.deepStrictEqual(J(Object.keys(m.lee(`fichaDatos(aplicaMigracion(_l, _h, '${C1}')[1], '${C1}')`)).sort()), ['id', 'on', 'title']);
  assert.strictEqual(tras[2], viejoB, 'si su subida falló, el anexo viejo se queda EXACTAMENTE como estaba');
  assert.deepStrictEqual(J(m.lee(`fichaDatos(_l[2], '${C1}')`).pages), ['b1'], 'y sigue guardándose con sus páginas');
  assert.match(m.lee('idAnexoNuevo()'), /^ax-[0-9a-f-]{36}$/);
  assert.notStrictEqual(m.lee('idAnexoNuevo()'), m.lee('idAnexoNuevo()'), 'un id de anexo no se reutiliza');

  // 10. subePaginasAnexo: el sha lo dice el servidor; si no cuadra con lo que se subió, se para con la página.
  const p1 = jpg(1), p2 = jpg(2);
  const llamadas = [];
  const edge = (shaMalo) => (sbx, clase, accion, d) => {
    llamadas.push([clase, accion, d.n]);
    if (accion === 'subida_url') return Promise.resolve({ ok: true, path: C1 + '/u/' + d.n + '.jpg', token: 't', bucket: 'contratos-anexos' });
    const b = d.n === 1 ? p1 : p2;
    return Promise.resolve({ ok: true, id: 'f' + d.n, sha256: shaMalo && d.n === 2 ? 'f'.repeat(64) : sha(b), bytes: b.length });
  };
  m = montar({ lwFichero: edge(false) });
  m.ctx._p = [dataUrl(p1), dataUrl(p2)];
  const filas = await m.lee(`subePaginasAnexo('${C1}', 'ax-n', _p)`);
  assert.deepStrictEqual(J(filas.map(f => [f.n, f.sha256])), [[1, sha(p1)], [2, sha(p2)]]);
  assert.ok(llamadas.every(l => l[0] === 'anexo_contrato'));
  m = montar({ lwFichero: edge(true) });
  m.ctx._p = [dataUrl(p1), dataUrl(p2)];
  await assert.rejects(m.lee(`subePaginasAnexo('${C1}', 'ax-n', _p)`), e => e.pagina === 2 && /no es la página que se subió/.test(e.message));

  // 11. cargaAnexosAlmacen: baja, compara la huella, y la página que no cuadra queda marcada.
  const f1 = fila('ax-a', 1, p1), f2 = fila('ax-a', 2, p2);
  m = montar({ contrato: C1, filas: [f1, f2], bytesDe: { [f1.path]: p1, [f2.path]: jpg(9) } });
  m.lee(`ANNEXES = normalizaAnexos([{ id: 'ax-a', title: 'Planos', on: true }])`);
  assert.strictEqual(m.lee('ANNEXES[0].estado'), 'cargando');
  await m.lee(`cargaAnexosAlmacen('${C1}')`);
  const cargado = m.ctx.ANNEXES[0];
  assert.strictEqual(cargado.pages[0], dataUrl(p1), 'la página buena se embebe tal cual');
  assert.strictEqual(cargado.pages[1], null);
  assert.deepStrictEqual([cargado.estado, [...cargado.faltan]], ['falta', [2]]);
  assert.match(m.lee('problemasAnexos(ANNEXES)')[0], /página 2 del anexo «Planos»/);
  //     vista previa: hueco marcado; documento que se firma: se para.
  assert.match(m.lee('annexHTML()'), /Falta la página 2 de este anexo/);
  m.ctx.SIGN_MODE = true;
  assert.throws(() => m.lee('annexHTML()'), /página 2 del anexo «Planos»/);
  m.ctx.SIGN_MODE = false;
  //     la consulta caída NO es «sin páginas»: estado de error, con su motivo
  m = montar({ contrato: C1, filasFalla: true });
  m.lee(`ANNEXES = normalizaAnexos([{ id: 'ax-a', title: 'Planos', on: true }])`);
  await m.lee(`cargaAnexosAlmacen('${C1}')`);
  assert.strictEqual(m.lee('ANNEXES[0].estado'), 'error');
  //     carrera: si mientras carga se abre otro contrato, lo bajado se tira
  m = montar({ contrato: C1, filas: [f1], bytesDe: { [f1.path]: p1 } });
  m.lee(`ANNEXES = normalizaAnexos([{ id: 'ax-a', title: 'Planos', on: true }])`);
  const pend = m.lee(`cargaAnexosAlmacen('${C1}')`);
  m.ctx.SAVED_CONTRACT = { id: C2 };
  await pend;
  assert.strictEqual(m.lee('ANNEXES[0].estado'), 'cargando', 'lo del contrato anterior no aterriza en el nuevo');

  // 12. Borrador local: solo fichas de automáticos, nunca bytes ni URLs.
  const guardadoLocal = [];
  m = montar({});
  m.ctx.localStorage = { getItem: () => null, setItem: (k, v) => guardadoLocal.push(v), removeItem() {} };
  m.lee(`ANNEXES = [{ id: 'axauto', auto: 'Dali', pages: ['data:image/jpeg;base64,AAA'], on: true }, { id: 'ax-m', title: 'M', on: true, pages: ['data:x'], almacen: [], contrato: '${C1}' }]; saveAnnexes()`);
  assert.deepStrictEqual(JSON.parse(guardadoLocal.pop()), [{ id: 'axauto', auto: 'Dali', pages: [], on: true }]);

  // 13. loadAnnexes (documento_diseno.js): la clave vieja con páginas se reescribe UNA vez sin ellas.
  const DISENO = fs.readFileSync(path.join(__dirname, 'documento_diseno.js'), 'utf8');
  const cuerpo = DISENO.match(/function loadAnnexes\(\)\{[\s\S]*?\n\}/);
  assert.ok(cuerpo, 'loadAnnexes sigue en documento_diseno.js');
  const almacen = { lawang_contract_annexes: JSON.stringify([{ id: 'axauto', auto: 'Dali', pages: ['data:AAA'] }, { id: 'ax1', title: 'viejo', pages: ['data:BBB'] }]) };
  const ctxD = { JSON, Array, localStorage: { getItem: k => almacen[k] ?? null, setItem: (k, v) => { almacen[k] = v; }, removeItem: k => { delete almacen[k]; } } };
  vm.createContext(ctxD);
  vm.runInContext(cuerpo[0] + '\nvar r = loadAnnexes();', ctxD);
  assert.deepStrictEqual(JSON.parse(JSON.stringify(ctxD.r)), [{ id: 'axauto', auto: 'Dali', pages: [] }]);
  assert.ok(!/data:/.test(almacen.lawang_contract_annexes), 'en el navegador ya no quedan bytes: ' + almacen.lawang_contract_annexes);

  console.log('documento_anexos.test.js OK');
})().catch(e => { console.error(e); process.exit(1); });
