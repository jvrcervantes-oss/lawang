/* node cola_correos.test.js — la edge `cola-correos-envio` (AXW-202 C1) con el index.ts REAL, sin Deno y sin red (arnés de envia-correo),
   y las reglas de la migración 20261005011702 leídas de su fuente. Qué fija (plan revisado, puntos 1-18):
   puerta propia en tiempo constante que no lee body ni query; pausa = no reclama; cuerpo EXACTO que se manda a envia-correo
   (clave + ids, nunca texto, enlace ni token) con ENVIO_CORREO_SECRET; cierre ok con la versión; cada tipo de fallo (SMTP, 400,
   pausa, bloqueo 554, credencial, red); ninguna dirección en logs ni en lo que se guarda como error; y el mismo dato en todos
   los sitios donde vive (claves y ids de la edge = reglas SQL = PLANTILLAS de valida.ts). */
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const raiz = path.join(__dirname, '..', '..', '..');
const leer = (...p) => fs.readFileSync(path.join(raiz, ...p), 'utf8').replace(/\r\n/g, '\n');
const SIN_COMENTARIOS_SQL = (s) => s.replace(/^\s*--.*$/gm, '');

(async () => {
  const A = await import('../envia-correo/arnes.mjs');
  let n = 0;
  const igual = (a, b, m) => { assert.deepStrictEqual(a, b, m); n++; };
  const ok = (c, m) => { assert.ok(c, m); n++; };

  const ENVIO = 'envio-falso', COLA = 'cola-falsa';
  const F = '11111111-1111-4111-8111-111111111111', C = '22222222-2222-4222-8222-222222222222', Q = '33333333-3333-4333-8333-333333333333';
  const DIR = 'comprador.secreto@ejemplo.com';
  const fila = (o = {}) => ({ id: Q, clave: 'enlace_firma_cadena', firma_id: F, contrato_id: C, factura_id: null, vars: {}, para: DIR, prioridad: 1, intentos: 1, ...o });

  /** Prepara el arnés. `tandas`: lo que devuelve reclamar en cada llamada (después, []); `envia(cuerpo, init)`: respuesta de envia-correo. */
  function prepara({ tandas = [[fila()]], envia = () => ({ status: 200, cuerpo: { ok: true, plantilla: 'enlace_firma_cadena', version: 'f:ab12cd34' } }),
                     pausado = false, secreto = COLA, okRpc = true, env = {}, datos = [{ sociedad_clave: 'san_dal_woods' }] } = {}) {
    const est = { rpcs: [], envios: [], patches: [], reclamos: 0 };
    const extra = async (u, init = {}) => {
      const url = new URL(u);
      if (url.pathname.endsWith('/rest/v1/mantenimiento')) {
        if (init.method === 'PATCH') { est.patches.push(JSON.parse(init.body)); return new Response('', { status: 204 }); }
        return new Response(JSON.stringify([{ envios_pausados: pausado }]), { status: 200 });
      }
      const m = /\/rest\/v1\/rpc\/(\w+)$/.exec(url.pathname);
      if (m) {
        const args = init.body ? JSON.parse(init.body) : {};
        est.rpcs.push({ nombre: m[1], args });
        if (m[1] === 'cron_correos_cola_secret') return new Response(JSON.stringify(secreto), { status: 200 });
        if (m[1] === 'correo_cola_reclamar') { const t = tandas[est.reclamos++] ?? []; return new Response(JSON.stringify(t), { status: 200 }); }
        if (m[1] === 'correo_cola_ok') return okRpc === 'lanza' ? new Response('boom', { status: 500 }) : new Response(JSON.stringify(okRpc), { status: 200 });
        if (m[1] === 'correo_cola_fallo') return new Response(JSON.stringify('pendiente'), { status: 200 });
        if (m[1] === 'reclamo_pago_datos') return new Response(JSON.stringify(datos), { status: 200 });
        if (m[1] === 'correos_cola_purga') return new Response('0', { status: 200 });
        return new Response('null', { status: 200 });
      }
      if (url.pathname.endsWith('/functions/v1/envia-correo')) {
        const cuerpo = JSON.parse(init.body);
        est.envios.push({ cuerpo, cabeceras: init.headers });
        const r = envia(cuerpo, init);
        if (r === 'red') throw new TypeError('red caída (prueba)');
        return new Response(JSON.stringify(r.cuerpo), { status: r.status });
      }
      return null;
    };
    A.reinicia({ env: { ENVIO_CORREO_SECRET: ENVIO, ...env }, extra });
    return est;
  }
  async function pasa(cabeceras = { 'x-cron-secret': COLA }, metodo = 'POST') {
    const edge = await import(require('url').pathToFileURL(path.join(__dirname, 'index.ts')).href + '?t=' + (++n));
    edge.AJUSTES.esperaMs = 0;
    const r = await A.llama(edge.manejador, { metodo, cabeceras });
    return { ...r, edge };
  }
  const nombres = (est) => est.rpcs.map((r) => r.nombre);

  // ── 1. la puerta ─────────────────────────────────────────────────────────────────────────────────────────
  let est = prepara();
  let r = await pasa({}, 'GET'); igual(r.status, 405, 'solo POST');
  est = prepara(); r = await pasa({}); igual(r.status, 401, 'sin secreto: 401'); ok(!nombres(est).includes('correo_cola_reclamar'), 'sin secreto no se reclama nada');
  est = prepara(); r = await pasa({ 'x-cron-secret': 'otro' }); igual(r.status, 401); ok(!nombres(est).includes('correo_cola_reclamar'), 'secreto malo: no se reclama');
  est = prepara(); r = await pasa({ 'x-cron-secret': COLA + 'x' }); igual(r.status, 401, 'prefijo correcto no vale');
  est = prepara({ secreto: '' }); r = await pasa(); igual(r.status, 500, 'sin secreto en Vault: 500, no puerta abierta');
  est = prepara({ env: { ENVIO_CORREO_SECRET: '' } }); r = await pasa(); igual(r.status, 500, 'sin ENVIO_CORREO_SECRET: config');
  est = prepara({ env: { ENVIO_CORREO_SECRET: '', RENDER_SECRET: 'render-falso' } }); r = await pasa(); igual(r.status, 500, 'NO cae a RENDER_SECRET');

  // ── 2. pausa global ──────────────────────────────────────────────────────────────────────────────────────
  est = prepara({ pausado: true }); r = await pasa();
  igual(r.status, 200); ok(r.cuerpo.pausado === true, 'en pausa lo dice'); ok(!nombres(est).includes('correo_cola_reclamar'), 'en pausa no se reclama');

  // ── 3. camino feliz: enlace de firma ─────────────────────────────────────────────────────────────────────
  est = prepara(); r = await pasa();
  igual(r.status, 200); igual(r.cuerpo, { ok: true, enviadas: 1, fallidas: 0 });
  igual(est.envios.length, 1);
  igual(est.envios[0].cuerpo, { to: DIR, plantilla: 'enlace_firma_cadena', attach: false, contrato_id: C, firma_id: F }, 'solo clave + ids + destinatario del dueño');
  igual(est.envios[0].cabeceras['X-Render-Secret'], ENVIO, 'por la puerta de servicio con ENVIO_CORREO_SECRET');
  igual(est.envios[0].cabeceras['X-Llamante'], 'cola-correos-envio');
  const ok1 = est.rpcs.find((x) => x.nombre === 'correo_cola_ok');
  igual(ok1.args, { p_id: Q, p_para: DIR, p_version: 'f:ab12cd34' }, 'cierra ok con la versión que devolvió el motor');
  igual(nombres(est).filter((x) => x === 'correo_cola_reclamar').length, 2, 'reclama hasta vaciar');
  ok(nombres(est).at(-1) === 'correos_cola_purga', 'al vaciar, purga la retención');
  // nada de texto/enlace/token en lo que se manda
  ok(!/https?:|token|subject|message|html/i.test(JSON.stringify(est.envios[0].cuerpo)), 'el cuerpo no lleva texto, enlace ni token');

  // aviso_anulacion: solo contrato_id (el motor no admite firma_id con esa clave)
  est = prepara({ tandas: [[fila({ clave: 'aviso_anulacion', prioridad: 5 })]] }); r = await pasa();
  igual(est.envios[0].cuerpo, { to: DIR, plantilla: 'aviso_anulacion', attach: false, contrato_id: C }, 'aviso_anulacion: solo contrato_id');

  // reclamo_pago: el destinatario es el `para` de la base; al motor solo van el id de la fila, el contrato y la sociedad. Ni dirección en vars, ni nombre, ni nota.
  const RECL = { clave: 'reclamo_pago', firma_id: null, prioridad: 7, vars: { nombre: 'X', nota: 'no debe viajar', para: 'otro@x.com' } };
  est = prepara({ tandas: [[fila(RECL)]] }); r = await pasa();
  igual(est.envios[0].cuerpo, { to: DIR, plantilla: 'reclamo_pago', attach: false, contrato_id: C, vars: { reclamo: Q }, sociedad: 'san_dal_woods' }, 'reclamo_pago: to del dueño, vars solo {reclamo}, sociedad del contrato');
  ok(!JSON.stringify(est.envios[0].cuerpo.vars).includes('@') && !JSON.stringify(est.envios[0].cuerpo).includes('no debe viajar'), 'reclamo_pago: ninguna dirección ni nota en vars (las vars de la fila se ignoran)');
  igual(est.rpcs.find((x) => x.nombre === 'reclamo_pago_datos').args, { p_cola: Q }, 'los datos se piden a la base por el id de la fila');
  igual(est.rpcs.find((x) => x.nombre === 'correo_cola_ok').args, { p_id: Q, p_para: DIR, p_version: 'f:ab12cd34' }, 'reclamo_pago cierra ok como las demás');
  // sin sociedad en el contrato: terminal visible y NO se envía firmado como otra empresa
  for (const d of [[{ sociedad_clave: null }], [], null]) {
    est = prepara({ tandas: [[fila(RECL)]], datos: d, envia: () => ({ status: 400, cuerpo: { error: 'reclamo_sin_sociedad' } }) }); r = await pasa();
    ok(est.envios.length === 0, 'reclamo_pago sin sociedad: no llega al motor');
    const f2 = est.rpcs.find((x) => x.nombre === 'correo_cola_fallo'); ok(f2 && f2.args.p_terminal === true && f2.args.p_error === 'reclamo_sin_sociedad', 'reclamo_pago sin sociedad: fallo terminal visible');
  }

  // clave que la edge no sabe resolver → terminal visible, no se envía
  est = prepara({ tandas: [[fila({ clave: 'factura_vencimiento', contrato_id: null, firma_id: null, factura_id: C })]] }); r = await pasa();
  igual(est.envios.length, 0, 'clave no soportada: nada sale');
  igual(est.rpcs.find((x) => x.nombre === 'correo_cola_fallo').args.p_terminal, true);

  // sin destinatario → terminal
  est = prepara({ tandas: [[fila({ para: null })]] }); r = await pasa();
  igual(est.envios.length, 0); igual(est.rpcs.find((x) => x.nombre === 'correo_cola_fallo').args.p_error, 'sin_destinatario');

  // ── 4. fallos ────────────────────────────────────────────────────────────────────────────────────────────
  const fallo = (e) => e.rpcs.find((x) => x.nombre === 'correo_cola_fallo');
  est = prepara({ envia: () => ({ status: 500, cuerpo: { ok: false, error: 'No se pudo enviar por SMTP (450, 4.2.0)' } }) }); r = await pasa();
  igual(fallo(est).args.p_terminal, false, 'fallo de SMTP: reintenta con backoff'); ok(!fallo(est).args.p_devolver); igual(r.cuerpo.fallidas, 1);

  est = prepara({ envia: () => ({ status: 400, cuerpo: { ok: false, error: 'El enlace de firma ya no está vivo' } }) }); r = await pasa();
  igual(fallo(est).args.p_terminal, true, '400 del motor: el documento cambió, terminal y visible');

  est = prepara({ tandas: [[fila(), fila({ id: '44444444-4444-4444-8444-444444444444' })]],
                  envia: () => ({ status: 503, cuerpo: { ok: false, error: 'Los envíos de correo están en pausa (modo mantenimiento). No se ha enviado nada.' } }) }); r = await pasa();
  igual(est.envios.length, 1, 'en pausa a mitad: no sigue');
  const dev = est.rpcs.filter((x) => x.nombre === 'correo_cola_fallo');
  igual(dev.length, 2, 'las dos filas vuelven'); ok(dev.every((d) => d.args.p_devolver === true && d.args.p_espera_s === 300), 'sin gastar intento, espera 5 min');

  est = prepara({ tandas: [[fila(), fila({ id: '44444444-4444-4444-8444-444444444444' })]],
                  envia: () => ({ status: 500, cuerpo: { ok: false, error: 'No se pudo enviar por SMTP (554, 5.7.1): Outbound sending is disabled' } }) }); r = await pasa();
  ok(est.rpcs.filter((x) => x.nombre === 'correo_cola_fallo').every((d) => d.args.p_devolver === true), '554: vuelven sin gastar intento');
  igual(est.patches.length, 1, '554: pausa los envíos'); igual(est.patches[0].envios_pausados, true);
  igual(r.cuerpo.pausado, true);

  est = prepara({ envia: () => ({ status: 401, cuerpo: { ok: false, error: 'No autorizado' } }) }); r = await pasa();
  igual(r.status, 500, 'el motor rechaza la credencial: la pasada falla en voz alta');
  ok(fallo(est).args.p_devolver === true && fallo(est).args.p_espera_s === 600, 'la fila vuelve sin gastar intento');

  est = prepara({ envia: () => 'red' }); r = await pasa();
  ok(!fallo(est).args.p_terminal, 'red caída: reintento normal'); igual(r.cuerpo.fallidas, 1);

  // el correo salió pero el cierre falla: 3 intentos y queda dicho (el lease vence y se reenviará: al menos una vez)
  est = prepara({ okRpc: 'lanza' }); r = await pasa();
  igual(nombres(est).filter((x) => x === 'correo_cola_ok').length, 3, 'reintenta el cierre 3 veces');
  ok(r.logs.some((l) => l.includes('cola_correo_enviado_sin_cerrar')), 'lo deja en el log para medir duplicados');
  // el cierre devuelve false (otro drenador ya la tiene): no reintenta
  est = prepara({ okRpc: false }); r = await pasa();
  igual(nombres(est).filter((x) => x === 'correo_cola_ok').length, 1, 'false = ya no era nuestra: no reintenta');

  // ── 5. ninguna dirección en logs ni en lo que se guarda como error ──────────────────────────────────────
  for (const opts of [
    { envia: () => ({ status: 500, cuerpo: { ok: false, error: 'rebota ' + DIR + ' por completo' } }) },
    { envia: () => ({ status: 400, cuerpo: { ok: false, error: 'mal ' + DIR } }) },
    { envia: () => 'red' },
  ]) {
    const caso = prepara(opts);
    const rr = await pasa();
    ok(!rr.logs.join('\n').includes('@'), 'ni una dirección en el log: ' + rr.logs.join(' | ').slice(0, 120));
    ok(!rr.crudo.includes('@'), 'ni en la respuesta');
    const f2 = caso.rpcs.find((x) => x.nombre === 'correo_cola_fallo');
    ok(f2 && !String(f2.args.p_error).includes('@'), 'ni en el error que se guarda en la fila');
  }

  // ── 6. fuente: no lee body/query, secreto propio, sin direcciones en los logs ───────────────────────────
  const edge = leer('supabase', 'functions', 'cola-correos-envio', 'index.ts');
  const codigo = edge.replace(/^\s*\/\/.*$/gm, '');
  ok(!/req\.json\(|req\.text\(|req\.formData\(|req\.arrayBuffer\(|req\.url|searchParams|req\.body/.test(codigo), 'la edge no lee body ni query');
  ok(/rpc\('cron_correos_cola_secret'\)/.test(codigo) && !/cron_copias_firmadas|cron_avisos_manager|RENDER_SECRET/.test(codigo), 'secreto PROPIO; sin RENDER_SECRET');
  ok(/function igual\(/.test(codigo) && /\^ /.test(codigo), 'comparación en tiempo constante');
  ok(!/from\('correos_enviados'\)|correos_enviados/.test(codigo), 'la edge no escribe correos_enviados: lo hace correo_cola_ok');
  const logs = codigo.split('\n').filter((l) => /console\.(log|error|warn)/.test(l)).join('\n');
  ok(!/\.para\b|\.email\b|DIR/.test(logs), 'ninguna dirección en los logs');
  const toml = leer('supabase', 'config.toml');
  ok(toml.includes('[functions.cola-correos-envio]\nverify_jwt = false'), 'verify_jwt=false fijado en config.toml');
  ok(fs.statSync(path.join(__dirname, 'index.ts')).size > 3000, 'es un fichero real, no un puntero');

  // ── 7. el mismo dato en todos los sitios ─────────────────────────────────────────────────────────────────
  const mig = leer('supabase', 'migrations', '20261005011702_axw202_c1_cola_correos.sql');
  const valida = leer('supabase', 'functions', 'envia-correo', 'valida.ts');
  const IDS = (await import(require('url').pathToFileURL(path.join(__dirname, 'index.ts')).href + '?ids')).IDS_POR_CLAVE;
  // reglas SQL: 8 claves = las 8 de PLANTILLAS; soportadas = las que resuelve la edge
  const reglas = [...mig.matchAll(/^\s*\('([a-z_]+)',\s*'(firma_id|contrato_id|factura_id)',\s*(true|false),/gm)].map((m) => ({ clave: m[1], ancla: m[2], soportada: m[3] === 'true' }));
  const plantillasTodas = [...valida.matchAll(/^  ([a-z_]+):\s+\{ adjunto: (true|false),\s+ids: \[([^\]]*)\]/gm)].map((m) => ({ clave: m[1], adjunto: m[2] === 'true', ids: [...m[3].matchAll(/'(\w+)'/g)].map((x) => x[1]) }));
  // «Reclamar pago» (8-oct-2026) es la 9ª: su regla vive en la migración 20261010070000 (ancla propia, soportada=false A PROPÓSITO para que
  // correo_encolar la rechace) y la edge SÍ la resuelve; se comprueba aparte abajo. Las 8 de siempre siguen cruzadas como antes.
  const plantillas = plantillasTodas.filter((x) => x.clave !== 'reclamo_pago');
  igual(plantillasTodas.map((x) => x.clave).sort(), [...plantillas.map((x) => x.clave), 'reclamo_pago'].sort(), 'PLANTILLAS = las 8 + reclamo_pago');
  igual(reglas.map((x) => x.clave).sort(), plantillas.map((x) => x.clave).sort(), '_correo_cola_regla lista las mismas 8 claves que PLANTILLAS de valida.ts');
  igual(reglas.filter((x) => x.soportada).map((x) => x.clave).concat(['reclamo_pago']).sort(), Object.keys(IDS).sort(), 'las claves soportadas en SQL (+ reclamo_pago, aparte) son las que resuelve la edge');
  for (const r2 of reglas.filter((x) => x.soportada)) {
    const p = plantillas.find((x) => x.clave === r2.clave);
    igual(p.adjunto, false, r2.clave + ': sin adjunto (la edge manda attach:false)');
    igual([...IDS[r2.clave]].sort(), [...p.ids].sort(), r2.clave + ': ids de la edge = ids que pide el motor');
    ok(IDS[r2.clave].includes(r2.ancla === 'firma_id' ? 'firma_id' : r2.ancla) || r2.ancla === 'firma_id', r2.clave + ': ancla');
  }
  // reclamo_pago: regla SQL, ids del motor, ancla, vía y CHECKs, todo cruzado con la migración que lo introduce
  {
    const mr = leer('supabase', 'migrations', '20261010070000_reclamo_pago_parcela.sql');
    const fila = /\('reclamo_pago',\s*'(reclamo_id)',\s*(true|false),\s*(\d+),\s*(\d)::smallint,\s*(\d+),\s*'([a-z_]+)'/.exec(mr);
    ok(fila, 'regla SQL de reclamo_pago');
    igual(fila[2], 'false', 'reclamo_pago: soportada=false en SQL (correo_encolar la rechaza; solo reclamo_pago_encolar la crea)');
    const pr = plantillasTodas.find((x) => x.clave === 'reclamo_pago');
    igual(pr.adjunto, false, 'reclamo_pago: sin adjunto'); igual([...IDS.reclamo_pago].sort(), [...pr.ids].sort(), 'reclamo_pago: ids de la edge = ids que pide el motor');
    ok(/editables: \['reclamo'\]/.test(valida.match(/reclamo_pago:[^\n]*/)[0]), 'reclamo_pago: la única variable editable es el id del reclamo (nada de datos del correo)');
    ok(mr.includes("'" + fila[6] + "'") && mr.split("correos_enviados_via_check check")[1].includes("'reclamo_pago'"), 'la vía reclamo_pago está en el CHECK de correos_enviados');
    ok(mr.includes('reclamo_pago_datos'), 'la RPC que lee la edge existe en la migración');
  }
  // las vías de correos_enviados que usa la cola existen en su CHECK
  const viasCola = [...mig.matchAll(/^\s*\('[a-z_]+',\s*'[a-z_]+',\s*(?:true|false),\s*\d+,\s*\d::smallint,\s*\d+,\s*'([a-z_]+)'/gm)].map((m) => m[1]);
  ok(viasCola.length === 8, 'las 8 vías leídas');
  const checkVia = leer('supabase', 'migrations', '20261001160000_axw127_cola_copias_firmadas.sql').match(/via = any \(array\[([^\]]*)\]\)/)[1];
  for (const v of viasCola) ok(checkVia.includes("'" + v + "'"), 'via «' + v + '» está en el CHECK de correos_enviados');

  // ── 8. la migración: cerrada, sin red salvo el despertador, sin datos en un repo público ────────────────
  const sql = SIN_COMENTARIOS_SQL(mig);
  const funcs = [...sql.matchAll(/create or replace function public\.([a-z_]+)\(/g)].map((m) => m[1]);
  ok(funcs.length === 11, 'faltan funciones: ' + funcs.length);
  for (const f of funcs) {
    ok(new RegExp('revoke execute on function public\\.' + f + '\\([^)]*\\)\\s+from public, anon, authenticated').test(sql), f + ' sin revoke a public/anon/authenticated');
    const cab = sql.slice(sql.indexOf('function public.' + f + '('));
    ok(/set search_path = ''/.test(cab.slice(0, 900)), f + ' sin search_path vacío');
  }
  ok(!/grant\s+execute[^;]*to\s+(anon|authenticated|public)/i.test(sql), 'ningún grant a anon/authenticated');
  ok(!/grant\s+(?!execute|select)[a-z]+[^;]*to/i.test(sql.replace(/grant\s+execute[^;]*;/gi, '')), 'solo EXECUTE y el select de service_role');
  ok(/enable row level security/.test(sql) && /revoke all on public\.correos_cola from public, anon, authenticated/.test(sql), 'RLS y sin grants');
  ok(!/create policy/i.test(sql), 'sin policies: nada llega por la API de tablas');
  ok(/num_nonnulls\(firma_id, contrato_id, factura_id\) = 1/.test(sql), 'exactamente un ancla');
  ok(/references public\.correo_plantillas \(clave\)/.test(sql), 'clave = FK a correo_plantillas');
  ok(/create unique index correos_cola_uno[\s\S]*where estado <> 'cancelado'/.test(sql), 'índice único parcial (clave, ancla)');
  ok(!/\b(destinatario|email|para|token|url|asunto|mensaje|cuerpo)\b\s+(text|varchar)/i.test(sql.slice(sql.indexOf('create table public.correos_cola'), sql.indexOf('comment on table'))), 'la tabla no guarda destinatario, token, URL ni texto');
  ok(/for update of x skip locked/.test(sql) && /interval '4 minutes'/.test(sql), 'lease por fila con skip locked');
  ok(!/interval '15 minutes'/.test(sql.slice(sql.indexOf('create or replace function public.correo_cola_reclamar'), sql.indexOf('create or replace function public.correo_cola_ok'))), 'no copia el bloqueo global de 15 min de AXW-127');
  ok(/cron\.schedule\('correos-cola-envio'/.test(sql) && /cron\.alter_job\([\s\S]*active := false\)/.test(sql), 'cron con nombre y NACE APAGADO');
  ok(/vault\.create_secret/.test(sql) && /'cron_correos_cola'/.test(sql) && !/'cron_copias_firmadas'/.test(sql), 'secreto propio en Vault');
  ok(!/[A-Za-z0-9._-]+@[A-Za-z0-9-]+\.[a-z]{2,}/.test(sql), 'ningún email literal en un repo público');
  ok(!/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/.test(sql), 'ningún uuid literal');
  ok(!/vtulllundrfennhjddhc/.test(sql), 'sin el ref del proyecto escrito en el SQL (la URL sale de config_instancia)');
  ok(/insert into public\.correos_enviados/.test(sql) && sql.indexOf("set estado = 'ok'") < sql.indexOf('insert into public.correos_enviados') && /function public\.correo_cola_ok[\s\S]*?end \$\$/.test(sql), 'ok + registro en la misma función (misma transacción)');

  // migraciones 2 y 3 (arreglos de la revisión del propio C1): service_role solo lee; encolar reabre `error`; la purga conserva `error`
  const mig2 = SIN_COMENTARIOS_SQL(leer('supabase', 'migrations', '20261005012220_axw202_c1_cola_correos_service_role_solo_lectura.sql'));
  ok(/revoke insert, update, delete, truncate, references, trigger on public\.correos_cola from service_role/.test(mig2), 'service_role sin escritura directa en la tabla');
  const mig3 = SIN_COMENTARIOS_SQL(leer('supabase', 'migrations', '20261005012701_axw202_c1_cola_correos_reabre_error_y_purga.sql'));
  ok(/q\.estado = 'error'[\s\S]*?set estado = 'pendiente'|set estado = 'pendiente'[\s\S]*?q\.estado = 'error'/.test(mig3) && /'reabierto', true/.test(mig3), 'encolar sobre una fila en error la reabre');
  ok(/where q\.estado in \('ok', 'cancelado'\)/.test(mig3) && !/estado in \('ok', 'cancelado', 'error'\)/.test(mig3), 'la purga conserva las filas en error');
  for (const f of ['correo_encolar', 'correos_cola_purga', 'correo_cola_salud']) {
    ok(!new RegExp('function public\.' + f + '\([^)]*\)[\s\S]*?grant', 'i').test(mig3.slice(0, mig3.indexOf('$$;'))), f + ': create or replace conserva los permisos, sin grants nuevos');
  }
  ok(!/grant\s/i.test(mig3), 'la migración 3 no concede nada');

  console.log('OK cola_correos.test.js — ' + n + ' comprobaciones: puerta, pausa, cuerpo al motor, cierre, fallos, sin direcciones, y claves/ids/vías iguales en edge, SQL y valida.ts');
})().catch((e) => { console.error('FALLA cola_correos.test.js:', e && e.stack ? e.stack : e); process.exit(1); });
