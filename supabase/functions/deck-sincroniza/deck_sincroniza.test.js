/* node deck_sincroniza.test.js — la edge `deck-sincroniza` (AXW-66 S6) con el index.ts REAL, sin Deno y sin red
   (Node >= 22.18 quita los tipos del .ts), y las reglas de su migración y de config.toml leídas de su fuente.
   Qué fija (revisor de código + Seguridad, 10-oct-2026):
   · puerta: sin cabecera / cabecera mala → 401 y NO se pregunta qué está mal puesto; GET → 405; el body no se lee;
   · secreto bueno con DECK_SINCRONIZA apagado → 409 y 0 movimientos;
   · reconcilia: mueve cada foto de bucket_real a bucket_debido (en ese orden, conservando el nombre), deja `en_ambos`
     sin tocar, para cuando una pasada no avanza (no insiste en bucle) y un fallo que entra en la 2.ª pasada no es un 500;
   · la respuesta solo lleva recuentos (ni un nombre de fichero);
   · migración: secreto generado en Vault, función solo service_role, job que lee Vault por subconsulta (nunca el valor
     escrito), y verify_jwt = false en config.toml. */
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const raiz = path.join(__dirname, '..', '..', '..');
const leer = (...p) => fs.readFileSync(path.join(raiz, ...p), 'utf8').replace(/\r\n/g, '\n');

const SECRETO = 'secreto-del-cron-de-prueba';
const est = { env: {}, rpcs: [], movs: [], desajustes: [], falla: new Set(), fallaUnaVez: new Set(), cuerpoLeido: false };

globalThis.Deno = { env: { get: (k) => est.env[k] }, serve: () => ({}) };
globalThis.fetch = async (url, init = {}) => {
  const u = new URL(String(url));
  const m = /\/rest\/v1\/rpc\/(\w+)$/.exec(u.pathname);
  if (m) {
    est.rpcs.push(m[1]);
    if (m[1] === 'cron_deck_sincroniza_secret') return new Response(JSON.stringify(SECRETO), { status: 200 });
    if (m[1] === 'deck_fotos_desajustes') return new Response(JSON.stringify(est.desajustes), { status: 200 });
    return new Response('{}', { status: 404 });
  }
  if (u.pathname === '/storage/v1/object/move') {
    const b = JSON.parse(init.body);
    est.movs.push(b);
    if (est.falla.has(b.sourceKey)) return new Response('no', { status: 500 });
    if (est.fallaUnaVez.has(b.sourceKey)) { est.fallaUnaVez.delete(b.sourceKey); return new Response('no', { status: 500 }); }
    // movido: la base deja de verlo mal puesto
    est.desajustes = est.desajustes.filter((d) => d.name !== b.sourceKey);
    return new Response('{}', { status: 200 });
  }
  throw new Error('fetch inesperado: ' + u);
};

function reinicia({ sincroniza = 'on', desajustes = [] } = {}) {
  Object.assign(est, {
    env: { SUPABASE_URL: 'https://ref.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'service-falsa', DECK_SINCRONIZA: sincroniza },
    rpcs: [], movs: [], desajustes: desajustes.map((d) => ({ ...d })), falla: new Set(), fallaUnaVez: new Set(), cuerpoLeido: false,
  });
}
const des = (name, motivo = 'bucket', real = 'deck', debido = 'deck-privado') =>
  ({ name, bucket_real: real, bucket_debido: debido, proyecto_id: null, motivo });

function peticion({ metodo = 'POST', secreto = SECRETO, cuerpo = '{"name":"proyecto/x.webp","bucket":"deck"}' } = {}) {
  const h = new Headers({ 'content-type': 'application/json' });
  if (secreto !== null) h.set('x-cron-secret', secreto);
  return new Request('https://ref.supabase.co/functions/v1/deck-sincroniza', { method: metodo, headers: h, body: metodo === 'GET' ? undefined : cuerpo });
}

(async () => {
  reinicia();
  const { manejador } = await import('./index.ts');
  let n = 0;
  const igual = (a, b, msg) => { assert.deepStrictEqual(a, b, msg); n++; };
  const ok = (c, msg) => { assert.ok(c, msg); n++; };
  const llama = async (o) => { const r = await manejador(peticion(o)); return { status: r.status, cuerpo: await r.json() }; };

  // ── puerta ──
  reinicia({ desajustes: [des('proyecto/a.webp')] });
  let r = await llama({ secreto: null });
  igual(r.status, 401, 'sin cabecera → 401');
  ok(!est.rpcs.includes('deck_fotos_desajustes') && est.movs.length === 0, 'sin cabecera no mira ni mueve nada');

  reinicia({ desajustes: [des('proyecto/a.webp')] });
  r = await llama({ secreto: SECRETO + 'x' });
  igual(r.status, 401, 'cabecera mala → 401');
  ok(!est.rpcs.includes('deck_fotos_desajustes') && est.movs.length === 0, 'cabecera mala no mira ni mueve nada');

  reinicia();
  r = await llama({ metodo: 'GET', secreto: SECRETO });
  igual(r.status, 405, 'GET → 405');

  // ── interruptor ──
  reinicia({ sincroniza: '', desajustes: [des('proyecto/a.webp')] });
  r = await llama({});
  igual([r.status, r.cuerpo.error], [409, 'sincroniza_apagada'], 'apagado → 409');
  ok(est.movs.length === 0 && !est.rpcs.includes('deck_fotos_desajustes'), 'apagado: ni mira ni mueve');

  // ── barrido ──
  reinicia({ desajustes: [des('proyecto/a.webp'), des('modelo/b.webp', 'huerfano'), des('proyecto/c.webp', 'bucket', 'deck-privado', 'deck'),
                          des('proyecto/d.webp', 'en_ambos', 'deck', 'deck-privado')] });
  r = await llama({ cuerpo: '{"name":"proyecto/d.webp"}' });           // lo que diga el body no decide nada
  igual(r.status, 200, 'barrido normal → 200');
  igual(r.cuerpo, { ok: true, movidas: 3, fallidas: 0, quedan: 0, en_ambos: 1 }, 'recuentos del barrido');
  igual(est.movs.map((m) => [m.sourceKey, m.bucketId, m.destinationBucket, m.destinationKey]).sort(),
        [['modelo/b.webp', 'deck', 'deck-privado', 'modelo/b.webp'], ['proyecto/a.webp', 'deck', 'deck-privado', 'proyecto/a.webp'],
         ['proyecto/c.webp', 'deck-privado', 'deck', 'proyecto/c.webp']], 'origen → destino conservando el nombre; en_ambos intacto');
  ok(!JSON.stringify(r.cuerpo).includes('.webp'), 'la respuesta no lleva nombres de fichero');

  // un fallo que entra en la 2.ª pasada no es error
  reinicia({ desajustes: [des('proyecto/a.webp'), des('proyecto/e.webp')] });
  est.fallaUnaVez.add('proyecto/e.webp');
  r = await llama({});
  igual([r.status, r.cuerpo.quedan, r.cuerpo.movidas, r.cuerpo.fallidas], [200, 0, 2, 1], 'fallo pasajero: 200 al acabar bien');

  // sin progreso: para y lo dice
  reinicia({ desajustes: [des('proyecto/f.webp')] });
  est.falla.add('proyecto/f.webp');
  r = await llama({});
  igual([r.status, r.cuerpo.error, r.cuerpo.quedan], [500, 'quedan_sin_mover', 1], 'sin progreso → 500 con lo que queda');
  igual(est.movs.length, 1, 'sin progreso no insiste');

  // ── migración y config ──
  const mig = leer('supabase', 'migrations', '20261010210000_deck_sincroniza_cron.sql');
  const sinComent = mig.replace(/^\s*--.*$/gm, '');
  ok(/vault\.create_secret\(\s*replace\(gen_random_uuid/.test(sinComent), 'el secreto se genera dentro de la base');
  ok(/revoke all\s+on function public\.cron_deck_sincroniza_secret\(\) from public, anon, authenticated/.test(sinComent), 'función cerrada a anon/authenticated');
  ok(/grant\s+execute on function public\.cron_deck_sincroniza_secret\(\) to service_role/.test(sinComent), 'solo service_role');
  ok(/cron\.schedule\('deck-sincroniza-diario'/.test(sinComent), 'el job tiene el nombre que cita la edge');
  ok(/'X-Cron-Secret', \(select decrypted_secret from vault\.decrypted_secrets where name = 'cron_deck_sincroniza'\)/.test(sinComent),
     'el job lee el secreto de Vault por subconsulta');
  ok(/\[functions\.deck-sincroniza\]\nverify_jwt = false/.test(leer('supabase', 'config.toml')), 'verify_jwt = false en config.toml');
  const idx = leer('supabase', 'functions', 'deck-sincroniza', 'index.ts');
  ok(!/req\.json\(|req\.text\(|new URL\(req\.url/.test(idx), 'la edge no lee body ni URL');

  console.log('deck_sincroniza.test.js: ' + n + ' comprobaciones OK');
  process.exit(0);   // los AbortSignal.timeout de la edge dejarían el proceso vivo 20 s más
})().catch((e) => { console.error(e); process.exit(1); });
