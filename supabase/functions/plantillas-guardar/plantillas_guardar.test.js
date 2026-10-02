/* node plantillas_guardar.test.js — la edge `plantillas-guardar` (S5.1), con el index.ts REAL, sin red. Idéntico en Lawang y en el maestro.
   Qué fija (revisión previa #191, Seguridad): solo el super admin ACTIVO guarda; el uuid que va a la RPC es el del JWT verificado (nunca uno
   del cuerpo); se valida el texto (mismas reglas que valida.ts y que la RPC SQL) ANTES de llamar a la RPC; los errores de la RPC se
   traducen sin filtrar nada interno; CORS solo al origen de la intranet; el log no lleva ni el texto ni el motivo. */
const assert = require('assert');
const path = require('path');

(async () => {
  const A = await import('../envia-correo/arnes.mjs');
  const P = await import('../envia-correo/plantillas_arnes.mjs');
  const CAT = P.catalogosSellados();
  let n = 0;
  const igual = (a, b, m) => { assert.deepStrictEqual(a, b, m); n++; };
  const ok = (c, m) => { assert.ok(c, m); n++; };
  const K = 'copia_firmada_comprador';
  const BUENO = { clave: K, asunto: 'Tu contrato firmado · {{numero}}', cuerpo: '{{saludo}}, aquí tienes {{contrato_proyecto}}.\nUn saludo.', cuerpo_alt: null, activa: true, motivo: 'prueba' };

  /** Prepara el arnés: `super` = el usuario es super admin activo; `rpc(body)` contesta la RPC; `catalogo` = lo que devuelve correo_plantillas. */
  function prepara({ superAdmin = true, sesion = true, rpc = null, catalogo = true, usuariosFalla = false } = {}) {
    const est = { rpcs: [], usuarios: [] };
    const extra = async (u, init = {}) => {
      const url = new URL(u);
      if (url.pathname.endsWith('/rest/v1/usuarios')) {
        est.usuarios.push(url.search);
        if (usuariosFalla) return new Response('boom', { status: 500 });
        return new Response(JSON.stringify(superAdmin && url.searchParams.get('rol') === 'eq.super_admin' ? [{ user_id: A.UID }] : []), { status: 200 });
      }
      if (url.pathname.endsWith('/rest/v1/correo_plantillas')) {
        if (!catalogo) return new Response('boom', { status: 500 });
        const clave = (url.searchParams.get('clave') || '').replace(/^eq\./, '');
        return new Response(JSON.stringify(CAT[clave] ? [{ variables: CAT[clave] }] : []), { status: 200 });
      }
      if (url.pathname.endsWith('/rest/v1/rpc/correo_plantilla_guardar')) {
        const body = JSON.parse(init.body);
        est.rpcs.push({ body, cabeceras: init.headers });
        if (rpc === 'lanza') throw new TypeError('red caída (prueba)');
        const r = rpc ? rpc(body) : { status: 200, cuerpo: { clave: body.p_clave, version: 1, activa: body.p_activa, cambiado: true } };
        return new Response(JSON.stringify(r.cuerpo), { status: r.status });
      }
      return null;
    };
    A.reinicia({ sesion, extra });
    return est;
  }
  const BEARER = { authorization: 'Bearer jwt-de-super' };
  async function llamaEdge(cuerpo, cabeceras = BEARER) {
    const m = await A.cargaEdge(__dirname);
    return A.llama(m, { cabeceras, cuerpo });
  }

  // ── autorización ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
  let est = prepara();
  igual((await llamaEdge(BUENO, {})).status, 401, 'sin credencial');
  igual((await llamaEdge(BUENO, { authorization: 'Bearer anon-falsa' })).status, 401, 'la clave anon no es una sesión');
  igual((await llamaEdge(BUENO, { authorization: 'Bearer service-falsa' })).status, 401, 'la clave de servicio no abre esta puerta');
  igual(est.rpcs.length, 0);
  est = prepara({ sesion: false });
  igual((await llamaEdge(BUENO)).status, 401, 'sesión no válida'); igual(est.rpcs.length, 0);
  est = prepara({ superAdmin: false });
  const r403 = await llamaEdge(BUENO);
  igual(r403.status, 403, 'admin, agente o comprador de portal con sesión pero sin ser super admin'); igual(est.rpcs.length, 0, 'la RPC ni se llama');
  est = prepara({ usuariosFalla: true });
  igual((await llamaEdge(BUENO)).status, 502, 'si no se puede comprobar el rol, no se guarda'); igual(est.rpcs.length, 0);

  // ── guardar ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  est = prepara();
  let r = await llamaEdge({ ...BUENO, p_actor: '99999999-9999-4999-8999-999999999999', actor: 'otro' });
  igual(r.status, 200, r.crudo); igual(r.cuerpo, { ok: true, version: 1, activa: true, cambiado: true });
  igual(est.rpcs.length, 1); const b = est.rpcs[0].body;
  igual(b.p_actor, A.UID, 'el uuid de la RPC es el del JWT verificado, nunca uno del cuerpo');
  igual([b.p_clave, b.p_asunto, b.p_cuerpo, b.p_cuerpo_alt, b.p_activa, b.p_motivo], [K, BUENO.asunto, BUENO.cuerpo, null, true, 'prueba']);
  ok(/service-falsa/.test(est.rpcs[0].cabeceras.Authorization), 'la RPC se llama con la clave de servicio');
  igual(est.usuarios.length, 1, 'se comprobó la fila de usuarios'); ok(/rol=eq\.super_admin/.test(est.usuarios[0]) && /activo=is\.true/.test(est.usuarios[0]), 'rol super_admin y activo');
  // CRLF de un textarea se normaliza antes de validar y de guardar
  est = prepara(); r = await llamaEdge({ ...BUENO, cuerpo: '{{saludo}}, {{contrato_proyecto}}\r\nlínea 2' });
  igual(r.status, 200, r.crudo); igual(est.rpcs[0].body.p_cuerpo, '{{saludo}}, {{contrato_proyecto}}\nlínea 2');
  // restaurar fábrica
  est = prepara(); r = await llamaEdge({ clave: K, asunto: null, cuerpo: null, cuerpo_alt: null, activa: false });
  igual(r.status, 200, r.crudo); igual([est.rpcs[0].body.p_asunto, est.rpcs[0].body.p_cuerpo, est.rpcs[0].body.p_activa, est.rpcs[0].body.p_motivo], [null, null, false, null]);
  // dos cuerpos
  est = prepara(); r = await llamaEdge({ clave: 'aviso_anulacion', asunto: 'Cambio {{numero}}', cuerpo: '{{saludo}} {{numero}}', cuerpo_alt: '{{saludo}} {{numero}}\n{{bloque_motivo}}', activa: true });
  igual(r.status, 200, r.crudo);

  // ── validación: no llega a la RPC ────────────────────────────────────────────────────────────────────────────────────────────
  const rechazado = async (cuerpo, trozo) => { est = prepara(); const x = await llamaEdge(cuerpo); igual(x.status, 400, JSON.stringify(cuerpo).slice(0, 100) + ' → ' + x.crudo); ok(String(x.cuerpo.error).includes(trozo), x.crudo); igual(est.rpcs.length, 0, 'la RPC no se llama'); return x; };
  await rechazado({ ...BUENO, clave: 'otra' }, 'no reconocida');
  await rechazado({ ...BUENO, clave: '__proto__' }, 'no reconocida');
  await rechazado({ ...BUENO, activa: 'si' }, 'activa');
  await rechazado({ ...BUENO, asunto: 5 }, 'texto');
  await rechazado({ ...BUENO, motivo: 'm'.repeat(501) }, 'motivo');
  await rechazado({ ...BUENO, cuerpo_alt: 'sobra' }, 'solo tiene un cuerpo');
  await rechazado({ clave: 'aviso_anulacion', asunto: 'Cambio {{numero}}', cuerpo: '{{saludo}} {{numero}}', cuerpo_alt: null, activa: true }, 'cuerpo_alt');
  const INVALIDOS = [['<b>hola</b>', 'texto plano'], ['mira https://malo.example', 'enlaces'], ['escribe a x@malo.example', 'enlaces'], ['{{saludo}} {{importe}} {{contrato_proyecto}}', 'no existe'],
    ['{{saludo}} {contrato_proyecto}} {{contrato_proyecto}}', 'llaves'], ['{{saludo}} \u0007 {{contrato_proyecto}}', 'control'], ['x'.repeat(5001), 'caracteres'], ['javascript:alert {{contrato_proyecto}}', 'enlaces'], ['   ', 'vacío'], ['{{saludo}} hola', 'tiene que llevar']];
  for (const [t, trozo] of INVALIDOS) await rechazado({ ...BUENO, cuerpo: t }, trozo);
  await rechazado({ ...BUENO, asunto: 'Tu contrato firmado' }, 'tiene que llevar');
  await rechazado({ ...BUENO, asunto: 'Tu\ncontrato {{numero}}' }, 'control');
  const varios = await rechazado({ ...BUENO, asunto: 'sin variable', cuerpo: '<b>x</b>' }, '«');
  ok(varios.cuerpo.errores.length >= 3, 'devuelve todos los errores a la vez: ' + varios.crudo);

  // ── errores de la RPC y de la base ───────────────────────────────────────────────────────────────────────────────────────────
  est = prepara({ rpc: () => ({ status: 403, cuerpo: { code: '42501', message: 'permission denied for function x', details: 'secreto interno' } }) });
  r = await llamaEdge(BUENO); igual(r.status, 403); ok(!r.crudo.includes('secreto interno') && !r.crudo.includes('permission denied'), 'no filtra el error interno');
  est = prepara({ rpc: () => ({ status: 400, cuerpo: { code: '22023', message: 'La plantilla no admite eso.' } }) });
  r = await llamaEdge(BUENO); igual(r.status, 400); ok(r.cuerpo.error === 'La plantilla no admite eso.', r.crudo);
  est = prepara({ rpc: () => ({ status: 500, cuerpo: { code: 'XX000', message: 'relation "x" at host 10.0.0.1' } }) });
  r = await llamaEdge(BUENO); igual(r.status, 502); ok(!r.crudo.includes('10.0.0.1') && r.cuerpo.error === 'No se pudo guardar', 'un error raro no se enseña');
  est = prepara({ rpc: 'lanza' }); igual((await llamaEdge(BUENO)).status, 502, 'red caída → 502');
  est = prepara({ catalogo: false }); r = await llamaEdge(BUENO); igual(r.status, 502, 'sin catálogo no se valida ni se guarda'); igual(est.rpcs.length, 0);
  // el log: estado y clave, nunca el texto ni el motivo
  est = prepara(); r = await llamaEdge({ ...BUENO, motivo: 'MOTIVO-SECRETO', asunto: 'ASUNTO-SECRETO {{numero}}' });
  ok(!r.logs.join('\n').includes('SECRETO'), 'el log no lleva el texto ni el motivo'); ok(r.logs.some((l) => l.includes('"fn":"plantillas-guardar"') && l.includes('"clave":"' + K + '"')), 'pero sí la clave');

  // ── forma de la petición, método y CORS ──────────────────────────────────────────────────────────────────────────────────────
  est = prepara();
  const m = await A.cargaEdge(__dirname);
  const consolaLog = console.log; console.log = () => {};   // estas llamadas directas escriben la línea de log de la edge: se silencian aquí
  const pide = (o = {}) => new Request('https://ref.supabase.co/functions/v1/plantillas-guardar', { method: 'POST', headers: { ...BEARER, ...(o.cab || {}) }, body: o.cuerpo === undefined ? JSON.stringify(BUENO) : o.cuerpo });
  igual((await m(pide({ cuerpo: '{no es json' }))).status, 400, 'JSON inválido'); igual((await m(pide({ cuerpo: '[1,2]' }))).status, 400, 'un array no es un objeto');
  igual((await m(pide({ cuerpo: JSON.stringify({ ...BUENO, cuerpo: 'x'.repeat(70 * 1024) }) }))).status, 413, 'cuerpo demasiado grande');
  igual((await m(new Request('https://ref.supabase.co/x', { method: 'GET', headers: BEARER }))).status, 405, 'solo POST');
  const conOrigen = await m(pide({ cab: { origin: 'https://erp.ejemplo.com' } }));
  igual(conOrigen.status, 200); igual(conOrigen.headers.get('access-control-allow-origin'), 'https://erp.ejemplo.com', 'CORS solo al origen de la intranet');
  const ajeno = await m(pide({ cab: { origin: 'https://malo.example' } }));
  igual(ajeno.status, 403); ok(!ajeno.headers.get('access-control-allow-origin'), 'un origen ajeno no recibe CORS');
  const pre = await m(new Request('https://ref.supabase.co/x', { method: 'OPTIONS', headers: { origin: 'https://erp.ejemplo.com' } }));
  igual(pre.status, 204); igual(pre.headers.get('access-control-allow-origin'), 'https://erp.ejemplo.com', 'el preflight llega sin credencial');
  igual(est.rpcs.length, 1, 'solo la petición válida con origen guardó');

  console.log = consolaLog;
  console.log(`OK plantillas_guardar.test.js — super admin activo sí, el resto no · uuid del JWT · ${INVALIDOS.length + 11} textos/formas inválidos sin llegar a la RPC · errores traducidos sin filtrar · CORS · log sin texto · ${n} comprobaciones`);
})().catch((e) => { console.error(e); process.exit(1); });
