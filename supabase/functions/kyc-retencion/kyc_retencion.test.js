/* node kyc_retencion.test.js — la edge `kyc-retencion` (LAW-557/558, 13-oct-2026) con el index.ts REAL, sin Deno y sin
   red (Node >= 22.18 quita los tipos del .ts), y las reglas de su migración y de config.toml leídas de su fuente.
   Qué fija (revisor de código, 13-oct-2026: «kyc-retencion no tiene prueba ejecutable»):
   · puerta: GET → 405; sin cabecera / secreto malo → 401 y NO se llama a ninguna RPC que borre ni se lee el cuerpo;
   · en seco por defecto: sin cuerpo, o con cualquier cosa que no sea `"dry": false`, ninguna llamada a Storage y las
     RPC reciben p_dry=true; lo demás del cuerpo (p_meses incluido) no llega a la base;
   · en real: borra las rutas del barrido y, de la retención, SOLO las que caen en la carpeta de un cliente aplicado;
   · cada pasada se registra (kyc_retencion_registra) con solo recuentos, también cuando falla, y un fallo es un 500;
   · migración: funciones solo service_role, la de candidatos y _cliente_crea sin execute para nadie, secreto en Vault
     generado dentro, tabla de pasadas cerrada; verify_jwt = false en config.toml. */
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const raiz = path.join(__dirname, '..', '..', '..');
const leer = (...p) => fs.readFileSync(path.join(raiz, ...p), 'utf8').replace(/\r\n/g, '\n');

const SECRETO = 'secreto-del-cron-de-prueba';
const A = '11111111-1111-4111-8111-111111111111', B = '22222222-2222-4222-8222-222222222222';
const est = { env: {}, rpcs: [], args: {}, borrados: [], fallaStorage: false, barrido: {}, retencion: {}, registros: [] };

globalThis.Deno = { env: { get: (k) => est.env[k] }, serve: () => ({}) };
globalThis.fetch = async (url, init = {}) => {
  const u = new URL(String(url));
  const m = /\/rest\/v1\/rpc\/(\w+)$/.exec(u.pathname);
  if (m) {
    const args = init.body ? JSON.parse(init.body) : {};
    est.rpcs.push(m[1]); est.args[m[1]] = args;
    if (m[1] === 'cron_kyc_retencion_secret') return new Response(JSON.stringify(SECRETO), { status: 200 });
    if (m[1] === 'kyc_barrido') return new Response(JSON.stringify(est.barrido), { status: 200 });
    if (m[1] === 'kyc_retencion') return new Response(JSON.stringify(est.retencion), { status: 200 });
    if (m[1] === 'kyc_retencion_registra') { est.registros.push(args.p_resumen); return new Response('', { status: 200 }); }
    return new Response('{}', { status: 404 });
  }
  if (u.pathname === '/storage/v1/object/kyc' && init.method === 'DELETE') {
    const b = JSON.parse(init.body);
    if (est.fallaStorage) return new Response('no', { status: 500 });
    est.borrados.push(...b.prefixes);
    return new Response('[]', { status: 200 });
  }
  throw new Error('fetch inesperado: ' + u);
};

function reinicia({ barrido = { pendientes_caducadas: 0, rutas: [] }, retencion = { activa: true, meses: 12, candidatos: 0, aplicados: 0, clientes: [], rutas: [] } } = {}) {
  Object.assign(est, {
    env: { SUPABASE_URL: 'https://ref.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'service-falsa' },
    rpcs: [], args: {}, borrados: [], fallaStorage: false, barrido, retencion, registros: [],
  });
}
function peticion({ metodo = 'POST', secreto = SECRETO, cuerpo } = {}) {
  const h = new Headers({ 'content-type': 'application/json' });
  if (secreto !== null) h.set('x-cron-secret', secreto);
  return new Request('https://ref.supabase.co/functions/v1/kyc-retencion', { method: metodo, headers: h, body: metodo === 'GET' ? undefined : cuerpo });
}
let n = 0; const ok = (c, msg) => { assert.ok(c, msg); n++; };

(async () => {
  reinicia();
  const { manejador } = await import('./index.ts');

  // ── puerta ───────────────────────────────────────────────────────────────────────────────────────────────────────
  let r = await manejador(peticion({ metodo: 'GET' }));
  ok(r.status === 405, 'GET → 405');
  for (const s of [null, '', 'otro-secreto', SECRETO + 'x']) {
    reinicia();
    r = await manejador(peticion({ secreto: s, cuerpo: '{"dry":false}' }));
    ok(r.status === 401, 'secreto ' + JSON.stringify(s) + ' → 401');
    ok(!est.rpcs.some((x) => x !== 'cron_kyc_retencion_secret'), 'sin secreto bueno no se llama a nada más');
  }

  // ── en seco por defecto ──────────────────────────────────────────────────────────────────────────────────────────
  for (const cuerpo of [undefined, '{}', '{"dry":"false"}', '{"dry":0}', '{"dry":true,"p_meses":0}', 'no-es-json']) {
    reinicia({ barrido: { pendientes_caducadas: 1, rutas: [A + '/x.pdf'] },
               retencion: { activa: true, meses: 12, candidatos: 1, aplicados: 0, clientes: [A], rutas: [A + '/y.pdf'] } });
    r = await manejador(peticion({ cuerpo }));
    const d = await r.json();
    ok(r.status === 200 && d.dry === true, 'cuerpo ' + JSON.stringify(cuerpo) + ' → en seco');
    ok(est.borrados.length === 0, 'en seco no se borra nada en Storage');
    ok(est.args.kyc_barrido.p_dry === true && est.args.kyc_retencion.p_dry === true, 'las RPC reciben p_dry=true');
    ok(Object.keys(est.args.kyc_retencion).join() === 'p_dry', 'a la base solo llega p_dry (nunca p_meses)');
  }

  // ── en real ──────────────────────────────────────────────────────────────────────────────────────────────────────
  reinicia({ barrido: { pendientes_caducadas: 2, rutas: [B + '/suelto.jpg'] },
             retencion: { activa: true, meses: 12, candidatos: 3, quedan: 2, aplicados: 1, clientes: [A],
                          rutas: [A + '/p1.jpg', A + '/p2.pdf', B + '/ajeno.jpg', 'otra/cosa.png'] } });
  r = await manejador(peticion({ cuerpo: '{"dry":false}' }));
  let d = await r.json();
  ok(r.status === 200 && d.ok === true && d.dry === false, 'dry:false → pasada real correcta');
  ok(est.borrados.includes(B + '/suelto.jpg'), 'borra el fichero suelto del barrido');
  ok(est.borrados.includes(A + '/p1.jpg') && est.borrados.includes(A + '/p2.pdf'), 'borra las copias del cliente aplicado');
  ok(!est.borrados.includes(B + '/ajeno.jpg') && !est.borrados.includes('otra/cosa.png'), 'nunca fuera de la carpeta de un cliente aplicado');
  ok(d.retencion.quedan === 2, 'dice cuántos quedan para las noches siguientes');
  const txt = JSON.stringify(d);
  ok(!/p1\.jpg|suelto\.jpg|ajeno/.test(txt), 'la respuesta no lleva rutas, solo recuentos e ids');
  ok(est.registros.length === 1 && est.registros[0].ok === true, 'la pasada queda registrada');

  // ── fallos: se registran y son 500 ───────────────────────────────────────────────────────────────────────────────
  reinicia({ retencion: { activa: true, meses: 12, candidatos: 1, aplicados: 1, clientes: [A], rutas: [A + '/p1.jpg'] } });
  est.fallaStorage = true;
  r = await manejador(peticion({ cuerpo: '{"dry":false}' }));
  d = await r.json();
  ok(r.status === 500 && d.ok === false && d.retencion.fallidos === 1, 'Storage que falla → 500 con el recuento de fallidos');
  ok(est.registros.length === 1 && est.registros[0].ok === false, 'la pasada fallida se registra (la base avisa)');

  reinicia({ retencion: { activa: true, meses: 12, aviso: 'mas_de_100_candidatos', candidatos: 101, aplicados: 0, rutas: [] } });
  r = await manejador(peticion({ cuerpo: '{"dry":false}' }));
  ok(r.status === 500 && est.borrados.length === 0, 'el freno de anomalía no borra nada y es un 500');
  ok(est.registros[0].ok === false, 'el freno de anomalía queda registrado como fallo (avisa)');

  reinicia(); est.barrido = null;
  globalThis.fetch = ((orig) => async (url, init) => {
    if (/kyc_barrido$/.test(new URL(String(url)).pathname)) return new Response('boom', { status: 500 });
    return orig(url, init);
  })(globalThis.fetch);
  r = await manejador(peticion({ cuerpo: '{"dry":false}' }));
  ok(r.status === 500 && est.registros.length === 1 && est.registros[0].error === 'pasada_fallida', 'una RPC que revienta → 500 y se registra');

  // ── migración y config ───────────────────────────────────────────────────────────────────────────────────────────
  const mig = leer('supabase', 'migrations', '20261013230000_law557_558_alta_con_documento_y_retencion_kyc.sql');
  for (const f of ['kyc_barrido(boolean)', 'kyc_retencion(boolean)', 'kyc_retencion_registra(jsonb)', 'cron_kyc_retencion_secret()']) {
    ok(mig.includes('revoke all on function public.' + f + ' from public, anon, authenticated;') &&
       mig.includes('grant execute on function public.' + f + ' to service_role;'), f + ': solo service_role');
  }
  ok(mig.includes('revoke all on function public._kyc_retencion_candidato(uuid, timestamptz) from public, anon, authenticated, service_role;'),
     '_kyc_retencion_candidato: sin execute para nadie');
  ok(/vault\.create_secret\(\s*replace\(gen_random_uuid\(\)/.test(mig), 'el secreto se genera dentro de la base');
  ok(mig.includes('revoke all on table public.kyc_retencion_pasadas from public, anon, authenticated;') &&
     mig.includes('alter table public.kyc_retencion_pasadas enable row level security;'), 'tabla de pasadas cerrada');
  ok(/exit when cardinality\(v_cand\) > 100;/.test(mig) && /v_cand := coalesce\(v_cand\[1:20\], '\{\}'\);/.test(mig), 'retención: 20 por noche y freno a los 100');
  ok(/doc_type = 'signed_contract' or d\.contrato_id is not null or d\.reservation_id is not null/.test(mig), 'retención: nunca un cliente con contrato firmado o documento vinculado');
  ok(/if v_cfg is null or jsonb_typeof\(v_cfg\) <> 'number' then\s+return jsonb_build_object\('activa', false\);/.test(mig), 'retención: sin la clave no hace nada');
  const cfg = leer('supabase', 'config.toml');
  ok(/\[functions\.kyc-retencion\]\nverify_jwt = false/.test(cfg), 'config.toml: verify_jwt = false');

  console.log('kyc_retencion.test.js OK (' + n + ' comprobaciones)');
})().catch((e) => { console.error(e); process.exit(1); });
