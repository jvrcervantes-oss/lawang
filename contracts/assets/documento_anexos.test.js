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
// La regla de qué entra vive en docs_contrato.js (la comparte la ficha del modelo): se carga la REAL.
const REGLA = fs.readFileSync(path.join(__dirname, 'docs_contrato.js'), 'utf8');
const DALI = { id: 'dali-id', nombre: 'Dali' };
// Desde el 27-sep-2026 entra lo MARCADO (en_contrato), no lo de tipo plano: las fixtures llevan la casilla.
const PLANOS = [
  { id: 'd-bambu', path: 'dali-id/bambu.pdf', nombre: 'Dali - Bambu - Anexo Maestro.pdf', tipo: 'plano', techo_clave: 'bambu', subido_en: '2026-09-23', en_contrato: true, orden: 1 },
  { id: 'd-sirap', path: 'dali-id/sirap.pdf', nombre: 'Dali - Sirap - Anexo Maestro.pdf', tipo: 'plano', techo_clave: 'sirap', subido_en: '2026-09-23', en_contrato: true, orden: 2 },
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
      // cada documento, sus bytes (y así su huella): el sha de uno no puede valer por otro
      const p = String(u).replace('https://x/', '');
      const falla = o.fetchFalla === true || (Array.isArray(o.fetchFalla) && o.fetchFalla.includes(p));
      return Promise.resolve(falla ? { ok: false, status: 404 } : { ok: true, arrayBuffer: () => Promise.resolve(new Uint8Array(Buffer.from('%PDF ' + p)).buffer) });
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
  if (!o.sinRegla) vm.runInContext(REGLA, ctx);
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
  assert.ok(/^Apéndice A — Planos Arquitectónicos · Dali · Sirap Ulin$/.test(auto.title), auto.title);
  assert.strictEqual(auto.letra, 'A');
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
  assert.ok(m.toasts.some(t => /no tiene documentos marcados para el contrato \(con este techo\)/.test(t)));
  assert.match(m.lee('AUTO_AVISO.texto'), /^Este modelo no tiene documentos marcados para el contrato \(con este techo\): el contrato irá sin anexo\.$/);
  assert.strictEqual(m.lee('AUTO_AVISO.mal'), false);
  assert.strictEqual(m.lee('AUTO_CARGA'), '');

  // 3. Hay plano pero no se descarga: UN solo mensaje, en rojo, con el nombre y el motivo,
  //    y NUNCA «no tiene» (antes salían los dos y el segundo tapaba al primero).
  m = montar({ planos: PLANOS, techo: 'sirap', fetchFalla: true });
  await m.lee('syncAutoAnnex()');
  assert.strictEqual(m.males.length, 1, JSON.stringify(m.males));
  assert.match(m.males[0], /no se ha podido adjuntar: Apéndice A «Dali - Sirap - Anexo Maestro\.pdf» no se ha podido descargar: HTTP 404/);
  assert.ok(!m.toasts.some(t => /no tiene documentos marcados/.test(t)), 'con el documento en Modelos no se dice que no lo tiene');
  assert.strictEqual(m.lee('AUTO_AVISO.mal'), true);

  // 4. Se descarga pero no se convierte: rojo con motivo, y la ficha guardada del
  //    anexo (su `on` y su `sha`) sobrevive, sin páginas, para no perderla al guardar.
  const guardado = { id: 'axauto-d-sirap', auto: 'Dali', techo: 'sirap', sha: 'abc', on: false, pages: ['vieja'] };
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
    assert.match(m.males[0], /No se ha podido comprobar qué documentos de Dali van en el contrato/);
    assert.ok(!m.toasts.some(t => /no tiene documentos marcados/.test(t)), 'no haber podido mirar no es «no tiene»');
  }

  // 6. Modelo sin nada marcado (ni genérico): neutro.
  m = montar({ planos: [], techo: 'sirap' });
  await m.lee('syncAutoAnnex()');
  assert.strictEqual(m.males.length, 0);
  assert.ok(m.toasts.some(t => /no tiene documentos marcados/.test(t)));

  /* ═══ 27-sep-2026: VARIOS documentos, elegidos por la casilla ═══════════════════════════ */
  const JJ = x => JSON.parse(JSON.stringify(x));   // de otro contexto de vm
  const FICHA = { id: 'd-ficha', path: 'dali-id/ficha.pdf', nombre: 'DALI FICHA.pdf', tipo: 'ficha', techo_clave: null, subido_en: '2026-09-14', en_contrato: true, orden: 3 };
  // el dosier NUNCA entra (owner, 28-sep-2026), aunque la consulta lo devolviera marcado
  const DOSIER = { id: 'd-dosier', path: 'dali-id/dosier.pdf', nombre: 'DALI DOSIER.pdf', tipo: 'dosier', techo_clave: null, subido_en: '2026-09-14', en_contrato: true, orden: 0 };
  const CALIDADES = { id: 'd-cal', path: 'dali-id/cal.pdf', nombre: 'Memoria.pdf', tipo: 'calidades', techo_clave: null, subido_en: '2026-09-01', en_contrato: true, orden: 0 };
  const SIN_MARCAR = { id: 'd-no', path: 'dali-id/no.pdf', nombre: 'Plano sin marcar.pdf', tipo: 'plano', techo_clave: null, subido_en: '2026-09-02', en_contrato: false, orden: 0 };
  const ids = () => JSON.parse(JSON.stringify(m.ctx.ANNEXES.filter(a => a.auto).map(a => a.id)));

  // 14. Entran TODOS los marcados de su techo + los de «todos los techos», en `orden`; nunca uno sin marcar.
  m = montar({ planos: [...PLANOS, FICHA, CALIDADES, SIN_MARCAR, DOSIER], techo: 'sirap' });
  await m.lee('syncAutoAnnex()');
  assert.deepStrictEqual(ids(), ['axauto-d-sirap', 'axauto-d-cal', 'axauto-d-ficha'],
    'por LETRA (A plano, B calidades, D ficha) aunque calidades tenga orden 0; bambú, el no marcado y el dosier fuera');
  assert.deepStrictEqual(m.pedidos, ['dali-id/sirap.pdf', 'dali-id/cal.pdf', 'dali-id/ficha.pdf']);
  const titulos = JSON.parse(JSON.stringify(m.ctx.ANNEXES.filter(a => a.auto).map(a => a.title)));
  assert.deepStrictEqual(titulos, ['Apéndice A — Planos Arquitectónicos · Dali · Sirap Ulin', 'Apéndice B — Especificaciones Técnicas · Dali',
    'Apéndice D — Ficha de la vivienda (informativo) · Dali'], 'la letra la pone el tipo; el techo solo en el documento que ES de ese techo');
  assert.deepStrictEqual(JJ(m.ctx.ANNEXES.find(a => a.id === 'axauto-d-cal').nombres),
    { es: 'Especificaciones Técnicas · Dali', en: 'Technical Specifications · Dali', id: 'Spesifikasi Teknis · Dali' }, 'títulos trilingües');
  assert.ok(m.toasts.some(t => /Anexos de Dali adjuntados: 3 documentos \(6 pág\.\)/.test(t)), JSON.stringify(m.toasts));
  const shas = m.ctx.ANNEXES.filter(a => a.auto).map(a => a.sha);
  assert.strictEqual(new Set(shas).size, 3, 'cada documento con SU huella');

  // 14b. Dos de la misma letra: B1/B2 en el orden de Modelos; empate de orden → subido_en, después id.
  m = montar({ planos: [{ ...CALIDADES, orden: 1 }, { ...CALIDADES, id: 'd-cal2', path: 'dali-id/cal2.pdf', orden: 1, subido_en: '2026-08-01' }], techo: 'sirap' });
  await m.lee('syncAutoAnnex()');
  assert.deepStrictEqual(ids(), ['axauto-d-cal2', 'axauto-d-cal']);
  assert.deepStrictEqual(JJ(m.ctx.ANNEXES.filter(a => a.auto).map(a => a.letra)), ['B1', 'B2']);

  // 14c. Sin techo elegido: solo los de «todos los techos».
  m = montar({ planos: [...PLANOS, FICHA], techo: null });
  await m.lee('syncAutoAnnex()');
  assert.deepStrictEqual(ids(), ['axauto-d-ficha']);

  // 14d. La consulta filtra por en_contrato, pero aunque devolviera uno sin marcar, no entra (la regla va también aquí).
  m = montar({ planos: [SIN_MARCAR], techo: 'sirap' });
  await m.lee('syncAutoAnnex()');
  assert.deepStrictEqual(ids(), []);

  // 15. Uno de tres falla al bajarse: los otros entran, el que falla se dice en ROJO con su nombre,
  //     y el aviso rojo es lo que app.html usa para pedir confirmación al enviar a firma.
  m = montar({ planos: [...PLANOS, FICHA, CALIDADES], techo: 'sirap', fetchFalla: ['dali-id/ficha.pdf'],
               annexes: [{ id: 'axauto-d-ficha', auto: 'Dali', techo: 'sirap', sha: 'viejo', on: false, pages: [] }] });
  await m.lee('syncAutoAnnex()');
  assert.deepStrictEqual(ids(), ['axauto-d-sirap', 'axauto-d-cal', 'axauto-d-ficha']);
  const caido = m.ctx.ANNEXES.find(a => a.id === 'axauto-d-ficha');
  assert.ok(caido.pages.length === 0 && caido.on === false && caido.sha === 'viejo', 'la ficha del que falla sobrevive sin páginas: ' + JSON.stringify(caido));
  assert.strictEqual(m.lee('AUTO_AVISO.mal'), true);
  assert.match(m.lee('AUTO_AVISO.texto'), /Un documento marcado para el contrato no se ha podido adjuntar: Apéndice D «DALI FICHA\.pdf»/);
  assert.strictEqual(m.lee('AUTO_AVISO.faltan.length'), 1, 'lo que falta viaja aparte: es lo que se apunta en el historial al «Enviar igualmente»');

  // 16. COMPATIBILIDAD: un contrato de antes guarda UNA ficha `axauto` (el plano del techo). Se traduce a la del
  //     plano equivalente conservando `on=false` y su `sha`; el dosier nuevo entra encendido.
  m = montar({ planos: [...PLANOS, FICHA], techo: 'sirap',
               annexes: [{ id: 'axauto', auto: 'Dali', techo: 'sirap', sha: 'shaviejo', on: false, pages: [] }] });
  await m.lee('syncAutoAnnex()');
  const plano16 = m.ctx.ANNEXES.find(a => a.id === 'axauto-d-sirap');
  assert.strictEqual(plano16.on, false, 'apagado a propósito sigue apagado');
  assert.strictEqual(m.ctx.ANNEXES.find(a => a.id === 'axauto-d-ficha').on, true);
  assert.ok(!m.ctx.ANNEXES.some(a => a.id === 'axauto'), 'la ficha vieja no se queda duplicada');
  assert.ok(m.males.some(t => /Apéndice A — Planos Arquitectónicos · Dali · Sirap Ulin» ha cambiado desde que se guardó/.test(t)),
    'el sha viejo se compara con el del plano equivalente: ' + JSON.stringify(m.males));
  //     ficha vieja SIN techo guardado y modelo con plano genérico: la vieja es la del genérico.
  m = montar({ planos: [{ ...PLANOS[0], techo_clave: null, id: 'd-gen' }, FICHA], techo: 'sirap',
               annexes: [{ id: 'axauto', auto: 'Dali', on: false, pages: [] }] });
  await m.lee('syncAutoAnnex()');
  assert.strictEqual(m.ctx.ANNEXES.find(a => a.id === 'axauto-d-gen').on, false);
  //     y nunca se pega a un documento que no es plano (el dosier no era el anexo de antes)
  m = montar({ planos: [FICHA], techo: 'sirap', annexes: [{ id: 'axauto', auto: 'Dali', techo: 'sirap', on: false, pages: [] }] });
  await m.lee('syncAutoAnnex()');
  assert.strictEqual(m.ctx.ANNEXES.find(a => a.id === 'axauto-d-ficha').on, true);

  // 17. El documento demasiado grande para la memoria del navegador: rojo con su nombre, no se cuelga.
  m = montar({ planos: [FICHA], techo: 'sirap' });
  m.lee('pdfToImages = async () => { throw Object.assign(new Error("pasa del tope"), { tope: { paginas: 40, total: 60, bytes: 85e6 } }); }');
  await m.lee('syncAutoAnnex()');
  assert.match(m.lee('AUTO_AVISO.texto'), /«DALI FICHA\.pdf» es demasiado grande para convertirlo en este navegador \(a la página 40 de 60/);
  assert.strictEqual(m.lee('AUTO_CARGA'), '');

  // 18. Peso: los automáticos cuentan en la memoria y avisan si el PDF pasará de 15 MB (irá por enlace).
  m = montar({});
  m.lee(`ANNEXES = [{ id: 'axauto-x', auto: 'Dali', on: true, pages: ['x'.repeat(12e6)] }, { id: 'ax-m', title: 'M', on: true, pages: ['y'.repeat(10e6)] }]`);
  assert.strictEqual(m.lee('pesoAnexosEnMemoria()'), 22e6, 'los automáticos también ocupan memoria');
  assert.strictEqual(m.lee('pesoAnexosManuales()'), 10e6);
  assert.match(m.lee('avisoPesoAnexos()'), /al comprador le llegará por enlace, no adjunto/);
  m.lee(`ANNEXES[0].on = false`);
  assert.strictEqual(m.lee('avisoPesoAnexos()'), '', 'uno apagado no pesa en el documento');

  // 20. El dosier nunca entra, ni marcado ni solo; y el orden de Modelos no cambia la letra.
  m = montar({ planos: [DOSIER], techo: 'sirap' });
  await m.lee('syncAutoAnnex()');
  assert.deepStrictEqual(ids(), [], 'un dosier marcado no entra');
  assert.ok(m.toasts.some(t => /no tiene documentos marcados/.test(t)));
  m = montar({ planos: [{ ...PLANOS[1], orden: 9 }, { ...CALIDADES, orden: 0 }, { ...FICHA, orden: -1 }], techo: 'sirap' });
  await m.lee('syncAutoAnnex()');
  assert.deepStrictEqual(JJ(m.ctx.ANNEXES.filter(a => a.auto).map(a => a.letra)), ['A', 'B', 'D'], 'el orden solo ordena dentro de una letra');
  //     plano del techo + plano de «Todos los techos»: los dos son A → A1, A2 (en su orden de Modelos)
  m = montar({ planos: [PLANOS[1], { ...PLANOS[0], id: 'd-gen', techo_clave: null, orden: 0 }], techo: 'sirap' });
  await m.lee('syncAutoAnnex()');
  assert.deepStrictEqual(JJ(m.ctx.ANNEXES.filter(a => a.auto).map(a => [a.id, a.letra])), [['axauto-d-gen', 'A1'], ['axauto-d-sirap', 'A2']]);

  // 21. Portada del anexo en el documento: «Apéndice A» trilingüe con su título; los subidos a mano, «Anexo 1».
  m = montar({ planos: [PLANOS[1], CALIDADES], techo: 'sirap' });
  await m.lee('syncAutoAnnex()');
  m.lee(`ANNEXES.push({ id: 'ax-m1', title: 'Plano firmado por el cliente', on: true, pages: ['data:image/jpeg;base64,AAA'] })`);
  const html = m.lee('annexHTML()');
  assert.match(html, /<span data-lang="es">Apéndice A<\/span><span data-lang="en">Appendix A<\/span><span data-lang="id">Lampiran A<\/span>/);
  assert.match(html, /<span data-lang="es">Planos Arquitectónicos · Dali · Sirap Ulin<\/span><span data-lang="en">Architectural Drawings · Dali · Sirap Ulin<\/span><span data-lang="id">Gambar Arsitektur · Dali · Sirap Ulin<\/span>/);
  assert.match(html, /Apéndice B<\/span>[\s\S]*Especificaciones Técnicas · Dali/);
  assert.match(html, /<span data-lang="es">Anexo 1<\/span>[\s\S]*Plano firmado por el cliente/, 'el subido a mano sigue numerado, y es el 1 (no el 3)');
  assert.ok(html.indexOf('Apéndice A') < html.indexOf('Apéndice B'));
  //     el título editado a mano no cambia la letra
  m.lee(`ANNEXES.find(a => a.auto && a.letra === 'A').title = 'Otro título'`);
  assert.match(m.lee('annexHTML()'), /Apéndice A<\/span>/);

  // 19. Sin la regla cargada (docs_contrato.js) es «no he podido mirar», nunca «no tiene».
  m = montar({ planos: PLANOS, techo: 'sirap', sinRegla: true });
  await m.lee('syncAutoAnnex()');
  assert.strictEqual(m.lee('AUTO_AVISO.mal'), true);

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
  const avisosD = [], alCargar = [];
  const ctxD = { JSON, Array, localStorage: { getItem: k => almacen[k] ?? null, setItem: (k, v) => { almacen[k] = v; }, removeItem: k => { delete almacen[k]; } },
                 toastMal: t => avisosD.push(t) };
  ctxD.window = { addEventListener: (ev, f) => { if (ev === 'load') alCargar.push(f); } };
  vm.createContext(ctxD);
  vm.runInContext(cuerpo[0] + '\nvar r = loadAnnexes();', ctxD);
  alCargar.forEach(f => f());
  assert.strictEqual(avisosD.length, 1, 'los anexos manuales de un borrador no desaparecen callados');
  assert.match(avisosD[0], /un anexo subido a mano en un borrador sin guardar/);
  alCargar.length = 0; avisosD.length = 0;
  vm.runInContext('loadAnnexes();', ctxD);
  alCargar.forEach(f => f());
  assert.strictEqual(avisosD.length, 0, 'y el aviso sale UNA vez');
  assert.deepStrictEqual(JSON.parse(JSON.stringify(ctxD.r)), [{ id: 'axauto', auto: 'Dali', pages: [] }]);
  assert.ok(!/data:/.test(almacen.lawang_contract_annexes), 'en el navegador ya no quedan bytes: ' + almacen.lawang_contract_annexes);

  console.log('documento_anexos.test.js OK');
})().catch(e => { console.error(e); process.exit(1); });
