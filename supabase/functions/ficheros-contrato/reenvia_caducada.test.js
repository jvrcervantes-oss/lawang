/* node reenvia_caducada.test.js — la acción `reenvia_caducada` de ficheros-contrato (mejora 5b, 17-oct-2026) con el index.ts REAL
   (node ≥ 22.18 le quita los tipos; el import jsr: lo cambia arnes_hooks.mjs por un doble), sin red ni base.
   Qué fija (revisión previa Backend + Seguridad del 17-oct), cada criterio como llamada permitida, denegada y repetida:
     · sin sesión 401, sin ser del equipo 403, sin permiso sobre el contrato 403 y nada se toca;
     · el firmante y el destinatario salen de la FILA caducada: lo que mande el cuerpo (email, to, message) se ignora;
     · el correo va por la cola (correo_encolar con la firma nueva); si encolar falla se dice y no se cae a otro envío;
     · la 2.ª llamada con el mismo contrato no crea otro enlace ni otro correo;
     · documento cambiado, cola apagada, liberado: no se crea nada;
     · el tope por persona corta antes de la RPC. */
const assert = require('assert');
const path = require('path');
const { pathToFileURL } = require('url');
require('node:module').register(pathToFileURL(path.join(__dirname, 'arnes_hooks.mjs')).href);

const CID = '0b0b0b0b-1111-2222-3333-444444444444';
const UID = '11111111-2222-3333-4444-555555555555';
const DOC = '<html>contrato fijo</html>';
const crypto = require('crypto');
const HASH = crypto.createHash('sha256').update(DOC).digest('hex');

let E;   // estado de la base de mentira
function reinicia(o = {}) {
  E = Object.assign({
    sesion: true, agente: true, permiso: true, cola: 'cola', doc: DOC, liberado: null, encolarFalla: false, anuladosPorMi: 0,
    firmas: [{ id: 'f-cad', contrato_id: CID, estado: 'pendiente', expira_en: '2026-10-01T00:00:00Z', firmante_nombre: 'Ana Compradora',
      firmante_email: 'ana@ejemplo.com', firmante_rol: 'adquiriente_1', orden: 1, snapshot_hash: HASH, creado_en: '2026-09-01T00:00:00Z' }],
    eventos: [], llamadas: [],
  }, o);
}

function consulta(tabla) {
  const filtros = []; let cuenta = false;
  const filas = () => {
    let base;
    if (tabla === 'contratos') base = [{ id: CID, numero: 'RP00041', bloqueado: false, liberado_en: E.liberado }];
    else if (tabla === 'contrato_firmas') base = E.firmas;
    else if (tabla === 'config_instancia') base = E.cola == null ? [] : [{ clave: 'correo_cola_firma_submit', valor: E.cola }];
    else if (tabla === 'contrato_eventos') base = E.eventos;
    else throw new Error('tabla no prevista ' + tabla);
    return base.filter((r) => filtros.every(([op, k, v]) => {
      const val = k.includes('->>') ? (r[k.split('->>')[0]] || {})[k.split('->>')[1]] : r[k];
      return op === 'eq' ? val === v : String(val) >= String(v);
    }));
  };
  const q = {
    select(_c, o) { if (o && o.count) cuenta = true; return q; },
    eq(k, v) { filtros.push(['eq', k, v]); return q; },
    gte(k, v) { filtros.push(['gte', k, v]); return q; },
    limit() { return q; },
    maybeSingle() { const f = filas(); return Promise.resolve(f.length > 1 ? { data: null, error: { message: 'varias' } } : { data: f[0] ?? null, error: null }); },
    then(res, rej) {
      if (cuenta) return Promise.resolve({ count: tabla === 'contrato_firmas' ? E.anuladosPorMi + filas().length : 0, error: null }).then(res, rej);
      return Promise.resolve({ data: filas(), error: null }).then(res, rej);
    },
  };
  return q;
}

globalThis.__sbFalso = (clave, opciones) => {
  const deUsuario = !!(opciones && opciones.global);
  return {
    auth: { getUser: async () => (E.sesion ? { data: { user: { id: UID, email: 'agente@ejemplo.com' } }, error: null } : { data: null, error: { message: 'no' } }) },
    from: (t) => consulta(t),
    rpc: async (fn, args) => {
      E.llamadas.push([deUsuario ? 'usuario' : 'admin', fn, args]);
      if (fn === 'es_agente') return { data: E.agente, error: null };
      if (fn === 'contrato_firma_estado') return E.permiso ? { data: { firmados: 0 }, error: null } : { data: null, error: { message: 'No tienes permiso', code: '42501' } };
      if (fn === 'contrato_envia_firma') {
        assert.ok(deUsuario, 'contrato_envia_firma va con la sesión de la persona, no con el service role');
        let anul = 0;
        for (const f of E.firmas) if (f.estado === 'pendiente') { f.estado = 'anulado'; f.anulado_por = 'agente@ejemplo.com'; f.anulado_motivo = 'nuevo_enlace'; f.anulado_en = new Date().toISOString(); anul++; }
        E.firmas.push({ id: 'f-nueva-' + E.firmas.length, contrato_id: CID, estado: 'pendiente', expira_en: new Date(Date.now() + 30 * 864e5).toISOString(),
          firmante_nombre: args.p_nombre, firmante_email: args.p_email, firmante_rol: args.p_rol, orden: args.p_orden, snapshot_hash: args.p_snapshot_hash });
        return { data: { link: 'https://x/firmar?t=1', anulados: anul }, error: null };
      }
      if (fn === 'correo_encolar') return E.encolarFalla ? { data: null, error: { message: 'boom' } } : { data: { id: 'cola-1' }, error: null };
      throw new Error('rpc no prevista ' + fn);
    },
    storage: { from: () => { throw new Error('reenvia_caducada no debe tocar storage salvo leer el fijo'); } },
  };
};
globalThis.fetch = async (u) => {
  const url = String(u);
  E.llamadas.push(['fetch', url]);
  if (url.includes('/storage/v1/object/authenticated/contratos-firmados/pendientes/' + CID + '.html') && E.alLeerDoc) E.alLeerDoc();
  if (url.includes('/storage/v1/object/authenticated/contratos-firmados/pendientes/' + CID + '.html')) return E.doc == null ? new Response('no', { status: 404 }) : new Response(E.doc, { status: 200 });
  throw new Error('fetch no previsto ' + url);
};
let manejador;
globalThis.Deno = { env: { get: (k) => ({ SUPABASE_URL: 'https://ref.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'service', SUPABASE_ANON_KEY: 'anon' })[k] }, serve: (h) => { manejador = h; } };

async function llama(cuerpo, { jwt = 'jwt-bueno' } = {}) {
  const orig = console.error; console.error = () => {};
  try {
    const r = await manejador(new Request('https://ref.supabase.co/functions/v1/ficheros-contrato', { method: 'POST',
      headers: Object.assign({ 'content-type': 'application/json', origin: 'https://lawangproperties.com' }, jwt ? { authorization: 'Bearer ' + jwt } : {}), body: JSON.stringify(cuerpo) }));
    return { status: r.status, cuerpo: await r.json() };
  } finally { console.error = orig; }
}
const hizo = (fn) => E.llamadas.filter((l) => l[1] === fn);

(async () => {
  await import(pathToFileURL(path.join(__dirname, 'index.ts')).href);
  assert.ok(manejador, 'index.ts registra su manejador con Deno.serve');
  let n = 0; const ok = (c, m) => { assert.ok(c, m); n++; }; const igual = (a, b, m) => { assert.deepStrictEqual(a, b, m); n++; };
  const PIDE = { accion: 'reenvia_caducada', contrato_id: CID };

  // ── denegadas ──
  reinicia(); let r = await llama(PIDE, { jwt: '' }); igual(r.status, 401, 'sin sesión');
  reinicia({ agente: false }); r = await llama(PIDE); igual(r.status, 403, 'no es del equipo');
  reinicia({ permiso: false }); r = await llama(PIDE);
  igual(r.status, 403, 'sin permiso sobre el contrato'); igual(hizo('contrato_envia_firma').length, 0, 'sin permiso no se crea enlace');
  reinicia(); r = await llama({ accion: 'reenvia_caducada', contrato_id: 'no-uuid' }); igual(r.status, 400, 'contrato_id que no es uuid');

  // ── vista previa ──
  reinicia(); r = await llama(Object.assign({ ver: true }, PIDE));
  igual([r.status, r.cuerpo.puede, r.cuerpo.para, r.cuerpo.numero], [200, true, 'ana@ejemplo.com', 'RP00041'], 'ver: dice a quién iría');
  igual(hizo('contrato_envia_firma').length + hizo('correo_encolar').length, 0, 'ver no crea ni encola nada');
  igual(E.llamadas.filter((l) => l[0] === 'fetch').length, 0, 'ver no descarga el documento (hasta 20 MB con anexos)');

  // ── permitida: el cuerpo no manda ──
  reinicia(); r = await llama(Object.assign({ email: 'malo@ataque.com', to: 'malo@ataque.com', message: 'paga aquí', nombre: 'X', rol: 'adquiriente_9', orden: 7 }, PIDE));
  igual([r.status, r.cuerpo.enlace, r.cuerpo.correo], [200, true, true], 'enlace creado y correo encolado');
  const env = hizo('contrato_envia_firma')[0][2];
  igual([env.p_email, env.p_nombre, env.p_rol, env.p_orden, env.p_snapshot_hash], ['ana@ejemplo.com', 'Ana Compradora', 'adquiriente_1', 1, HASH], 'firmante y documento de la fila, no del cuerpo');
  igual(hizo('correo_encolar')[0][2], { p_clave: 'enlace_firma_cadena', p_firma: E.firmas[1].id }, 'se encola la firma NUEVA por la plantilla del servidor');
  ok(!E.llamadas.some((l) => l[0] === 'fetch' && /send-contract-email|envia-correo/.test(l[1])), 'ningún envío directo');

  // ── repetida: la 2.ª no crea nada ──
  r = await llama(PIDE);
  igual([r.cuerpo.puede, r.cuerpo.motivo], [false, 'enlace_vivo'], 'la 2.ª llamada ve el enlace vivo');
  igual([hizo('contrato_envia_firma').length, hizo('correo_encolar').length], [1, 1], 'un solo enlace y un solo correo');

  // ── no se crea nada ──
  reinicia({ doc: '<html>otro</html>' }); r = await llama(PIDE); igual(r.cuerpo.motivo, 'documento_cambiado', 'el fijo ya no es el enviado');
  reinicia({ doc: null }); r = await llama(PIDE); igual(r.cuerpo.motivo, 'falta_el_documento', 'sin documento fijo');
  reinicia({ cola: 'directo' }); r = await llama(PIDE); igual(r.cuerpo.motivo, 'cola_apagada', 'cola apagada');
  reinicia({ cola: null }); r = await llama(PIDE); igual(r.cuerpo.motivo, 'cola_apagada', 'sin interruptor');
  reinicia({ liberado: '2026-10-02T00:00:00Z' }); r = await llama(PIDE); igual(r.cuerpo.motivo, 'liberado', 'reserva liberada');
  igual(hizo('contrato_envia_firma').length, 0, 'en ninguno de estos se ha creado enlace');

  // ── carrera: alguien genera un enlace vivo mientras esta llamada lee el documento → no se le anula ──
  reinicia({ alLeerDoc: () => { E.firmas.push({ id: 'f-viva', contrato_id: CID, estado: 'pendiente', expira_en: new Date(Date.now() + 864e5).toISOString(),
    firmante_nombre: 'Ana Compradora', firmante_email: 'ana@ejemplo.com', firmante_rol: 'adquiriente_1', orden: 1, snapshot_hash: HASH }); E.alLeerDoc = null; } });
  r = await llama(PIDE);
  igual([r.cuerpo.puede, hizo('contrato_envia_firma').length], [false, 0], 'se vuelve a mirar justo antes de la RPC y no se crea nada');
  igual(E.firmas.find((f) => f.id === 'f-viva').estado, 'pendiente', 'el enlace vivo del otro sigue vivo');

  // ── tope ──
  reinicia({ anuladosPorMi: 20 }); r = await llama(PIDE);
  igual([r.status, r.cuerpo.error], [429, 'demasiados_reenvios'], 'en el tope se para'); igual(hizo('contrato_envia_firma').length, 0, 'antes de la RPC');
  reinicia({ anuladosPorMi: 19 }); r = await llama(PIDE); igual(r.cuerpo.correo, true, 'justo por debajo del tope pasa');

  // ── encolar falla ──
  reinicia({ encolarFalla: true }); r = await llama(PIDE);
  igual([r.cuerpo.enlace, r.cuerpo.correo, r.cuerpo.motivo], [true, false, 'correo_no_encolado'], 'se dice: enlace creado, correo no');

  // ── la constancia sin anexo del enlace caducado sale en la vista previa ──
  reinicia({ eventos: [{ contrato_id: CID, evento: 'envio_sin_anexo_confirmado', detalle: { firma_id: 'f-cad', motivo: 'sin_apendice_a' } }] });
  r = await llama(Object.assign({ ver: true }, PIDE)); igual(r.cuerpo.sin_anexo, 'sin_apendice_a', 'ver avisa de que salió sin Apéndice A');

  console.log('reenvia_caducada.test.js: ' + n + ' comprobaciones en verde');
})().catch((e) => { console.error(e); process.exit(1); });
