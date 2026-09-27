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
  const sb = {
    from: () => {
      const q = { select: () => q, eq: () => q, order: () => Promise.resolve(o.consultaFalla
        ? { data: null, error: { message: 'red caída' } } : { data: o.planos, error: null }) };
      return q;
    },
    storage: { from: () => ({ createSignedUrl: p => { pedidos.push(p); return Promise.resolve({ data: { signedUrl: 'https://x/' + p }, error: null }); } }) },
  };
  const ctx = {
    console, Promise, Object, Error, Uint8Array, TextEncoder, setTimeout,
    crypto: require('crypto').webcrypto,
    localStorage: { getItem: () => null, setItem() {} },
    document: { querySelector: s => (s === '[name="tipologia_construccion"]' ? { value: o.tipologia || 'Dali' } : null) },
    $: () => null,
    render() {}, toast: m => toasts.push(m), toastMal: m => males.push(m),
    fetch: () => Promise.resolve(o.fetchFalla ? { ok: false, status: 404 } : { ok: true, arrayBuffer: () => Promise.resolve(new Uint8Array([37, 80, 68, 70]).buffer) }),
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
  return { ctx, toasts, males, pedidos, lee: n => vm.runInContext(n, ctx) };
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

  console.log('documento_anexos.test.js OK');
})().catch(e => { console.error(e); process.exit(1); });
