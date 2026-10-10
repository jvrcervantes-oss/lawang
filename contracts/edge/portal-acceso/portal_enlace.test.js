/* node contracts/edge/portal-acceso/portal_enlace.test.js — LAW-1 S2 (11-oct-2026): las edges `portal-acceso` y `portal-invitar` con el
   index.ts REAL, sin Deno, sin red y sin base (no hay deno en todas las máquinas; node >= 22.18 carga el .ts quitándole los tipos).
   `Deno` es un doble; supabase-js lo sustituye supabase_falso.mjs (gancho portal_hooks.mjs) y `fetch` y `console` son simulados: el único
   fetch que hacen estas edges es el envío del correo, así que «sin llamar a fetch» = «no salió ningún correo».
   El freno de la base se simula con la MISMA regla que portal_enlace_freno (60 s y 5/h por correo, 5/h por IP y 30/h global solo del
   formulario, devuelve 'pasa' o el motivo, p_libera devuelve el hueco); la prueba real contra la base:
   supabase/pruebas/law1_portal_enlace_freno.sql.
   Qué fija (criterio de S2 del encargo encargos/20261011_lawang_portal_enlace_por_correo.md, revisión previa #261):
   · el token (hashed_token), el action_link y la parte local del correo no aparecen en ninguna respuesta ni en ningún log;
   · un correo sin derecho, uno del equipo, el 6.º envío en una hora y el 6.º desde la misma IP dan LA MISMA respuesta que el éxito y no
     llaman a fetch ni a generateLink; la IP viaja a la base como HMAC (64 hex), nunca en claro; el tope global deja su línea propia;
   · el enlace lleva el token en el FRAGMENTO (#th=), no en la query;
   · destinatario, asunto, texto y botón los fija el servidor (lo que traiga la petición además de `email` se ignora); nunca preview ni sociedad;
   · vía de servicio X-Render-Secret: ENVIO_CORREO_SECRET hacia la edge envia-correo, RENDER_SECRET hacia el PHP, y nada a otra URL;
   · generateLink solo sobre una cuenta ya existente y con el mismo id; signInWithOtp (mailer de Supabase) no se usa nunca;
   · si envia-correo falla: portal-acceso {ok:true, reintentar:true}, portal-invitar el aviso acceso_creado_pero_email_no_enviado, y el hueco
     del freno se devuelve (el siguiente intento inmediato sí sale). */
const assert = require('assert');
const path = require('path');
const { register } = require('node:module');
const { pathToFileURL } = require('url');

register('./portal_hooks.mjs', pathToFileURL(__filename));

const URL_SB = 'https://ref.supabase.co';
const ENVIO_EDGE = URL_SB + '/functions/v1/envia-correo';
const ENVIO_PHP = 'https://lawangproperties.com/contracts/api/send_email.php';
const entorno = {};
const ENTORNO_BASE = { SUPABASE_URL: URL_SB, SUPABASE_SERVICE_ROLE_KEY: 'service-falsa', SUPABASE_ANON_KEY: 'anon-falsa',
  ENVIO_CORREO_SECRET: 'secreto-envio-falso', RENDER_SECRET: 'secreto-render-falso' };
globalThis.Deno = { env: { get: (k) => entorno[k] }, serve: () => ({}), test: () => {} };

// Valores reconocibles: se buscan en TODOS los logs y respuestas.
const LOCAL = 'compradorzeta7731';
const EMAIL = LOCAL + '@cliente-prueba.com';
const TOKEN = 'HASHTOKENSECRETO_0f9e8d7c6b5a4f3e2d1c0b9a';
const ACTION = 'https://ref.supabase.co/auth/v1/verify?token=ACTIONLINKSECRETO_77aa&type=magiclink';
const UID = 'aaaaaaaa-1111-2222-3333-444444444444';
const ADMIN_UID = 'bbbbbbbb-1111-2222-3333-444444444444';

(async () => {
  let n = 0;
  const igual = (a, b, m) => { assert.deepStrictEqual(a, b, m); n++; };
  const ok = (c, m) => { assert.ok(c, m); n++; };
  const todo = [];   // cada log y cada respuesta de todas las pruebas, para la barrida final
  const logs = [];
  for (const k of ['log', 'warn', 'error', 'info', 'debug']) console[k] = (...a) => { const l = a.map(String).join(' '); logs.push(l); todo.push(l); };
  const informe = (...a) => process.stdout.write(a.join(' ') + '\n');

  /* ── base, Auth y correo de mentira ── */
  let reloj = Date.parse('2026-10-11T03:00:00Z');
  const freno = { marcas: {}, global: [], ip: {} };   // estado persistente entre llamadas, como la tabla portal_enlaces_envios
  let est;
  function prepara(o = {}) {
    Object.keys(entorno).forEach((k) => delete entorno[k]);
    Object.assign(entorno, ENTORNO_BASE, o.env || {});
    est = {
      traza: [], envios: [],
      elegible: o.elegible !== undefined ? o.elegible : true,
      equipo: !!o.equipo,
      usuarioExiste: o.usuarioExiste !== undefined ? o.usuarioExiste : true,
      claim: o.claim !== undefined ? o.claim : true,
      urlEnvio: o.urlEnvio !== undefined ? o.urlEnvio : ENVIO_EDGE,
      correo: o.correo || (() => ({ status: 200, cuerpo: '{"ok":true}' })),
      linkUid: o.linkUid || UID,
      frenoError: !!o.frenoError,
      equipoUid: !!o.equipoUid,   // la cuenta de Auth es del equipo aunque `usuarios` tenga OTRO correo
    };
    globalThis.__sb = {
      traza: est.traza,
      rpc: (nombre, a) => {
        if (nombre === 'portal_autoservicio') return { data: { elegible: est.elegible, motivo: est.elegible ? null : 'sin_ficha' }, error: null };
        if (nombre === 'portal_puede_gestionar') return { data: true, error: null };
        if (nombre === 'portal_enlace_freno') {
          if (est.frenoError) return { data: null, error: { code: 'XX000', message: 'boom ' + a.p_email } };
          const e = a.p_email.trim().toLowerCase();
          const hora = reloj - 3600_000;
          const mio = (freno.marcas[e] || []).filter((t) => t > hora);
          const glob = freno.global.filter((t) => t > hora);
          const cuentaGlobal = a.p_origen === 'autoservicio';
          const ip = cuentaGlobal && a.p_ip_hash ? a.p_ip_hash : null;
          if (ip && !/^[0-9a-f]{64}$/.test(ip)) return { data: null, error: { code: '22023', message: 'ip_hash no válido' } };
          const deIp = ip ? (freno.ip[ip] || []).filter((t) => t > hora) : [];
          if (a.p_libera) {
            if (mio.length) { mio.pop(); if (cuentaGlobal) glob.pop(); if (ip) deIp.pop(); }
            freno.marcas[e] = mio; freno.global = glob; if (ip) freno.ip[ip] = deIp;
            return { data: 'liberado', error: null };
          }
          if (mio.length && mio[mio.length - 1] > reloj - 60_000) return { data: 'correo', error: null };
          if (mio.length >= 5) return { data: 'correo', error: null };
          if (ip && deIp.length >= 5) return { data: 'ip', error: null };
          if (cuentaGlobal && glob.length >= 30) return { data: 'global', error: null };
          freno.marcas[e] = [...mio, reloj];
          if (cuentaGlobal) freno.global = [...glob, reloj];
          if (ip) freno.ip[ip] = [...deIp, reloj];
          return { data: 'pasa', error: null };
        }
        throw new Error('rpc no prevista: ' + nombre);
      },
      consulta: (q) => {
        if (q.tabla === 'config_instancia') return { data: est.urlEnvio === null ? null : { valor: est.urlEnvio }, error: null };
        if (q.tabla === 'usuarios' && q.filtros.some((f) => f[1] === 'email')) return { data: est.equipo ? [{ user_id: 'x' }] : [], error: null };
        if (q.tabla === 'usuarios' && q.campos === 'user_id' && q.filtros.some((f) => f[1] === 'user_id')) return { data: est.equipoUid ? [{ user_id: UID }] : [], error: null };
        if (q.tabla === 'usuarios' && q.filtros.some((f) => f[1] === 'user_id')) return { data: { rol: 'super_admin', activo: true, herramientas: [] }, error: null };
        if (q.tabla === 'clients') return { data: (q.filtros.find((f) => f[0] === 'in') || [0, 0, []])[2].map((id) => ({ id })), error: null };
        if (q.tabla === 'portal_accesos' && q.op === 'select') return { data: [{ client_id: 'c1' }], error: null };
        if (q.tabla === 'portal_accesos') return { data: null, error: null };
        throw new Error('consulta no prevista: ' + q.tabla);
      },
      getUser: (jwt) => (jwt === 'jwt-admin' ? { data: { user: { id: ADMIN_UID, email: 'admin@lawangproperties.com' } }, error: null } : { data: null, error: { message: 'x' } }),
      listUsers: () => ({ data: { users: est.usuarioExiste ? [{ id: UID, email: EMAIL.toUpperCase(), app_metadata: est.claim ? { portal: true } : {} }] : [] }, error: null }),
      createUser: (a) => { est.usuarioExiste = true; return { data: { user: { id: UID, email: a.email, app_metadata: a.app_metadata } }, error: null }; },
      updateUserById: () => ({ data: {}, error: null }),
      generateLink: (a) => {
        if (!est.usuarioExiste) throw new Error('generateLink sin cuenta: habría creado una');
        return { data: { user: { id: est.linkUid, email: a.email }, properties: { hashed_token: TOKEN, action_link: ACTION, email_otp: '123456' } }, error: null };
      },
    };
    globalThis.fetch = async (url, init = {}) => {
      const u = String(url);
      est.envios.push({ url: u, cabeceras: init.headers || {}, cuerpo: JSON.parse(init.body || '{}') });
      if (u !== ENVIO_EDGE && u !== ENVIO_PHP) throw new Error('fetch a una URL no prevista: ' + u);
      const r = est.correo(u, init);
      return new Response(r.cuerpo, { status: r.status });
    };
  }
  const llama = async (M, cuerpo, cab = {}) => {
    const antes = logs.length;
    const r = await M.manejador(new Request('https://ref.supabase.co/functions/v1/x', {
      method: 'POST', headers: { 'content-type': 'application/json', ...cab }, body: JSON.stringify(cuerpo),
    }));
    const crudo = await r.text();
    todo.push(crudo);
    return { status: r.status, crudo, cuerpo: JSON.parse(crudo), logs: logs.slice(antes) };
  };
  const llamo = (que) => est.traza.filter((t) => t.que === que);
  const avanza = (seg) => { reloj += seg * 1000; };

  prepara();   // el entorno tiene que existir al importar: ENVIO_EDGE se calcula con SUPABASE_URL al cargar el módulo
  const ACCESO = await import(pathToFileURL(path.join(__dirname, 'index.ts')).href);
  const INVITAR = await import(pathToFileURL(path.join(__dirname, '..', 'portal-invitar', 'index.ts')).href);

  /* ════════ portal-acceso ════════ */
  // 1. éxito: envía por la edge con su secreto; destinatario/asunto/texto/botón fijados; la petición no cuela nada más
  prepara();
  const exito = await llama(ACCESO, { email: '  ' + EMAIL.toUpperCase() + ' ', to: 'otro@malo.com', subject: 'X', message: 'Y', cta_url: 'https://malo.com', preview: true, sociedad: 'sw' });
  igual(exito.status, 200, 'acceso: éxito 200');
  igual(exito.cuerpo, { ok: true }, 'acceso: éxito {ok:true} sin más');
  igual(est.envios.length, 1, 'acceso: un solo envío');
  const env = est.envios[0];
  igual(env.url, ENVIO_EDGE, 'acceso: va a la edge envia-correo (url_envio_correo)');
  igual(env.cabeceras['X-Render-Secret'], 'secreto-envio-falso', 'acceso: hacia la edge, ENVIO_CORREO_SECRET');
  igual(env.cabeceras['X-Llamante'], 'portal-acceso', 'acceso: se identifica en X-Llamante');
  igual(Object.keys(env.cuerpo).sort(), ['attach', 'cta_texto', 'cta_url', 'message', 'subject', 'to'], 'acceso: solo los campos fijados (sin preview ni sociedad)');
  igual(env.cuerpo.to, EMAIL, 'acceso: destinatario = el correo normalizado, nunca un `to` de la petición');
  igual(env.cuerpo.attach, false, 'acceso: attach:false');
  igual(env.cuerpo.cta_url, 'https://lawangproperties.com/portal/#th=' + TOKEN, 'acceso: enlace PORTAL_URL#th=<hashed_token> (fragmento, no query)');
  ok(!/malo|^X$|^Y$/.test(env.cuerpo.subject + env.cuerpo.message), 'acceso: asunto y texto del servidor');
  ok(!env.cuerpo.message.includes(TOKEN) && !env.cuerpo.message.includes('action'), 'acceso: el token solo va en el botón');
  const ordenA = est.traza.map((t) => t.que);
  ok(ordenA.indexOf('rpc:portal_enlace_freno') < ordenA.indexOf('admin.listUsers'), 'acceso: el freno va antes de tocar la cuenta');
  ok(ordenA.indexOf('admin.listUsers') < ordenA.indexOf('admin.generateLink'), 'acceso: generateLink después de resolver la cuenta');
  igual(llamo('admin.generateLink')[0].args, { type: 'magiclink', email: EMAIL }, 'acceso: generateLink magiclink con el correo normalizado');
  igual(llamo('auth.signInWithOtp').length, 0, 'acceso: nunca el mailer de Supabase');
  ok(exito.logs.some((l) => l.includes('enlace_enviado @cliente-prueba.com')), 'acceso: log con solo el dominio');

  // 2. las respuestas que no deben delatar nada son idénticas al éxito y no llaman a fetch ni a generateLink
  const mudas = {};
  prepara({ elegible: false });
  mudas.sin_derecho = await llama(ACCESO, { email: 'nadie-' + EMAIL });
  ok(!llamo('rpc:portal_enlace_freno').length, 'acceso: un correo sin derecho no gasta freno');
  igual([est.envios.length, llamo('admin.generateLink').length], [0, 0], 'acceso: sin derecho → ni fetch ni generateLink');
  prepara({ equipo: true });
  mudas.equipo = await llama(ACCESO, { email: EMAIL });
  igual([est.envios.length, llamo('admin.generateLink').length, llamo('rpc:portal_enlace_freno').length], [0, 0, 0], 'acceso: equipo → ni fetch, ni generateLink, ni freno');
  // 2b. cuenta del equipo con otro correo en `usuarios`: el filtro por correo no la ve, el de la cuenta sí (misma respuesta, hueco devuelto)
  avanza(61);   // el correo de la prueba 1 ya no está frenado: así lo que para es el filtro de equipo, no el freno
  prepara({ equipoUid: true });
  mudas.equipo_por_cuenta = await llama(ACCESO, { email: EMAIL });
  ok(llamo('rpc:portal_enlace_freno').some((t) => !t.args.p_libera), 'acceso: equipo por cuenta → el freno sí llegó a pasar (lo paró el filtro)');
  igual([est.envios.length, llamo('admin.generateLink').length, llamo('admin.updateUserById').length], [0, 0, 0], 'acceso: equipo por cuenta → ni claim, ni enlace, ni correo');
  igual(llamo('rpc:portal_enlace_freno').filter((t) => t.args.p_libera === true).length, 1, 'acceso: equipo por cuenta → devuelve el hueco');
  // 3. el 6.º envío en una hora (con más de 60 s entre cada uno) frena; el 2.º a menos de 60 s, también
  const otro = 'otrocomprador@cliente-prueba.com';
  prepara();
  const r1 = await llama(ACCESO, { email: otro });
  avanza(30);
  mudas.a_30s = await llama(ACCESO, { email: otro });
  igual(est.envios.length, 1, 'acceso: el 2.º a menos de 60 s no sale');
  for (let i = 2; i <= 5; i++) { avanza(61); await llama(ACCESO, { email: otro }); }
  igual(est.envios.length, 5, 'acceso: 5 envíos espaciados salen');
  avanza(61);
  const gen5 = llamo('admin.generateLink').length;
  const lu5 = llamo('admin.listUsers').length;
  mudas.sexto = await llama(ACCESO, { email: otro });
  igual([est.envios.length, llamo('admin.generateLink').length, llamo('admin.listUsers').length], [5, gen5, lu5], 'acceso: el 6.º en la hora → ni fetch, ni generateLink, ni cuenta');
  for (const [k, r] of Object.entries(mudas)) {
    igual([r.status, r.crudo], [exito.status, exito.crudo], 'acceso: «' + k + '» contesta exactamente lo mismo que el éxito');
  }
  igual([r1.status, r1.crudo], [200, exito.crudo], 'acceso: el primero de la serie sale normal');
  // 3b. pasada la hora vuelve a dejar
  avanza(3600);
  await llama(ACCESO, { email: otro });
  igual(est.envios.length, 6, 'acceso: pasada la hora, vuelve a salir');

  // 4. envia-correo falla → reintentar, y el hueco se devuelve: el siguiente intento inmediato sale
  const tercero = 'tercero@cliente-prueba.com';
  prepara({ correo: () => ({ status: 500, cuerpo: '{"ok":false,"error":"SMTP falló (554 5.7.1)"}' }) });
  const falla = await llama(ACCESO, { email: tercero });
  igual(falla.cuerpo, { ok: true, reintentar: true }, 'acceso: envío fallido → {ok:true, reintentar:true}');
  igual(llamo('rpc:portal_enlace_freno').filter((t) => t.args.p_libera === true).length, 1, 'acceso: devuelve el hueco del freno');
  ok(!falla.crudo.includes('554'), 'acceso: el texto del servidor de correo no llega al navegador');
  est.correo = () => ({ status: 200, cuerpo: '{"ok":true}' });
  const reint = await llama(ACCESO, { email: tercero });
  igual([reint.cuerpo, est.envios.length], [{ ok: true }, 2], 'acceso: reintento inmediato tras el fallo sí sale (no queda frenado)');
  // 200 sin "ok":true tampoco cuenta como enviado
  avanza(61);
  prepara({ correo: () => ({ status: 200, cuerpo: '{"ok":false}' }) });
  igual((await llama(ACCESO, { email: 'cuarto@cliente-prueba.com' })).cuerpo, { ok: true, reintentar: true }, 'acceso: 200 sin "ok":true = no enviado');

  // 5. generateLink devuelve OTRO usuario → no se manda nada
  avanza(61);
  prepara({ linkUid: 'cccccccc-0000-0000-0000-000000000000' });
  const otroU = await llama(ACCESO, { email: 'quinto@cliente-prueba.com' });
  igual([otroU.cuerpo, est.envios.length], [{ ok: true, reintentar: true }, 0], 'acceso: enlace de otro usuario → no se envía');
  // 6. cuenta nueva: se crea con el claim ANTES de generar el enlace
  avanza(61);
  prepara({ usuarioExiste: false });
  await llama(ACCESO, { email: 'sexto@cliente-prueba.com' });
  const ordenN = est.traza.map((t) => t.que);
  ok(ordenN.indexOf('admin.createUser') >= 0 && ordenN.indexOf('admin.createUser') < ordenN.indexOf('admin.generateLink'), 'acceso: la cuenta se crea antes del enlace');
  igual(llamo('admin.createUser')[0].args.app_metadata, { portal: true }, 'acceso: cuenta nueva con app_metadata.portal');
  // 7. el freno no contesta → 500 sin enlace ni correo
  prepara({ frenoError: true });
  const fe = await llama(ACCESO, { email: 'septimo@cliente-prueba.com' });
  igual([fe.status, fe.cuerpo, est.envios.length, llamo('admin.generateLink').length], [500, { error: 'no_disponible' }, 0, 0], 'acceso: freno caído → no_disponible, nada sale');
  ok(!fe.logs.join(' ').includes('septimo'), 'acceso: ni el error de la base deja la dirección en el log');
  // 8. url_envio_correo apunta al PHP → RENDER_SECRET; clave rara → PHP
  avanza(61);
  prepara({ urlEnvio: ENVIO_PHP });
  await llama(ACCESO, { email: 'octavo@cliente-prueba.com' });
  igual([est.envios[0].url, est.envios[0].cabeceras['X-Render-Secret']], [ENVIO_PHP, 'secreto-render-falso'], 'acceso: al PHP, RENDER_SECRET');
  avanza(61);
  prepara({ urlEnvio: 'https://malo.example/robar' });
  await llama(ACCESO, { email: 'noveno@cliente-prueba.com' });
  igual(est.envios[0].url, ENVIO_PHP, 'acceso: una url_envio_correo manipulada cae al PHP, nunca a otro host');
  // 9. sin ningún secreto → no hay fetch, reintentar
  avanza(61);
  prepara({ env: { ENVIO_CORREO_SECRET: '', RENDER_SECRET: '' } });
  const ss = await llama(ACCESO, { email: 'decimo@cliente-prueba.com' });
  igual([ss.cuerpo, est.envios.length], [{ ok: true, reintentar: true }, 0], 'acceso: sin secreto no se intenta enviar');
  // 10. tope global del formulario: con 30 en la hora, un correo nuevo frena (respuesta muda)
  avanza(3601);
  freno.global = Array.from({ length: 30 }, (_, i) => reloj - i * 1000);
  prepara();
  const glob = await llama(ACCESO, { email: 'nuevo-global@cliente-prueba.com' });
  igual([glob.crudo, est.envios.length], [exito.crudo, 0], 'acceso: tope global → misma respuesta y no sale');
  ok(glob.logs.includes('portal-acceso frenado_tope_global'), 'acceso: el tope global deja su línea propia (para avisar)');
  ok(glob.logs.some((l) => l.includes('frenado:global @cliente-prueba.com')), 'acceso: y el motivo con solo el dominio');
  // 11. método y correo inválido
  prepara();
  igual((await llama(ACCESO, { email: 'no-es-correo' })).crudo, exito.crudo, 'acceso: correo mal formado → misma respuesta');
  igual(llamo('rpc:portal_autoservicio').length, 0, 'acceso: correo mal formado ni pregunta a la base');

  // 12. por IP: 5 correos distintos con derecho desde la misma IP salen; el 6.º (otro correo) frena con la respuesta muda
  avanza(3601);
  freno.global = [];
  const IP = '203.0.113.77';
  const deIp = { 'cf-connecting-ip': IP };
  prepara();
  for (let i = 1; i <= 5; i++) { const r = await llama(ACCESO, { email: 'ip' + i + '@cliente-prueba.com' }, deIp); igual(r.crudo, exito.crudo, 'acceso: IP, envío ' + i + ' sale'); }
  igual(est.envios.length, 5, 'acceso: IP, 5 correos distintos desde la misma IP salen');
  const hIp = llamo('rpc:portal_enlace_freno')[0].args.p_ip_hash;
  ok(/^[0-9a-f]{64}$/.test(hIp), 'acceso: la IP va a la base como hash de 64 hex');
  ok(!JSON.stringify(est.traza).includes(IP), 'acceso: la IP en claro no llega a la base');
  const sextaIp = await llama(ACCESO, { email: 'ip6@cliente-prueba.com' }, deIp);
  igual([sextaIp.status, sextaIp.crudo, est.envios.length], [200, exito.crudo, 5], 'acceso: 6.º desde la misma IP → misma respuesta y no sale');
  ok(sextaIp.logs.some((l) => l.includes('frenado:ip @cliente-prueba.com')), 'acceso: IP, el log dice el motivo');
  ok(!sextaIp.logs.some((l) => l.includes('frenado_tope_global')), 'acceso: IP no se confunde con el tope global');
  // la última entrada de x-forwarded-for (la del proxy) es la misma IP: también frena; la primera (la que pone el cliente) no cuenta
  const xff = await llama(ACCESO, { email: 'ip7@cliente-prueba.com' }, { 'x-forwarded-for': '198.51.100.1, ' + IP });
  igual([xff.crudo, est.envios.length], [exito.crudo, 5], 'acceso: x-forwarded-for, cuenta la última entrada');
  const otraIp = await llama(ACCESO, { email: 'ip8@cliente-prueba.com' }, { 'x-forwarded-for': IP + ', 198.51.100.2' });
  igual([otraIp.crudo, est.envios.length], [exito.crudo, 6], 'acceso: otra IP (la del proxy es otra) sí sale');
  // envío fallido desde una IP: el hueco de la IP también se devuelve
  avanza(61);
  const IP2 = '203.0.113.88';
  prepara({ correo: () => ({ status: 500, cuerpo: '{"ok":false}' }) });
  await llama(ACCESO, { email: 'ip9@cliente-prueba.com' }, { 'cf-connecting-ip': IP2 });
  const lib = llamo('rpc:portal_enlace_freno').filter((t) => t.args.p_libera === true);
  igual(lib.length, 1, 'acceso: IP, envío fallido devuelve el hueco');
  ok(/^[0-9a-f]{64}$/.test(lib[0].args.p_ip_hash), 'acceso: el hueco devuelto lleva el hash de la IP');
  igual((freno.ip[lib[0].args.p_ip_hash] || ['x']).length, 0, 'acceso: la marca de esa IP se ha devuelto');
  // sin cabeceras de IP: no hay cubo común; cuentan correo y global, y queda «sin_ip» en el log
  avanza(61);
  prepara();
  const sinIp = await llama(ACCESO, { email: 'ip10@cliente-prueba.com' });
  igual([sinIp.crudo, est.envios.length, llamo('rpc:portal_enlace_freno')[0].args.p_ip_hash], [exito.crudo, 1, null], 'acceso: sin IP sale con p_ip_hash null');
  ok(sinIp.logs.some((l) => l.includes('sin_ip @cliente-prueba.com')), 'acceso: sin IP queda en el log');

  /* ════════ portal-invitar ════════ */
  freno.global = [];
  avanza(3601);
  const ADMIN = { authorization: 'Bearer jwt-admin' };
  // a. invitar a un comprador nuevo: crea la cuenta, vincula, freno 'invitar', envía con el texto fijado
  prepara({ usuarioExiste: false });
  const inv = await llama(INVITAR, { accion: 'invitar', email: EMAIL, client_ids: ['c1'], to: 'otro@malo.com', cta_url: 'https://malo.com' }, ADMIN);
  igual(inv.cuerpo, { ok: true }, 'invitar: éxito {ok:true}');
  igual(est.envios.length, 1, 'invitar: un envío');
  igual(Object.keys(est.envios[0].cuerpo).sort(), ['attach', 'cta_texto', 'cta_url', 'message', 'subject', 'to'], 'invitar: solo campos fijados');
  igual([est.envios[0].cuerpo.to, est.envios[0].cuerpo.cta_url], [EMAIL, 'https://lawangproperties.com/portal/#th=' + TOKEN], 'invitar: destinatario y enlace del servidor (fragmento)');
  igual([est.envios[0].url, est.envios[0].cabeceras['X-Render-Secret'], est.envios[0].cabeceras['X-Llamante']], [ENVIO_EDGE, 'secreto-envio-falso', 'portal-invitar'], 'invitar: vía de servicio hacia la edge');
  igual(llamo('rpc:portal_enlace_freno')[0].args, { p_email: EMAIL, p_origen: 'invitar' }, 'invitar: freno con origen invitar (no cuenta en el global)');
  const ordenI = est.traza.map((t) => t.que);
  ok(ordenI.indexOf('admin.createUser') < ordenI.indexOf('rpc:portal_enlace_freno') && ordenI.indexOf('rpc:portal_enlace_freno') < ordenI.indexOf('admin.generateLink'), 'invitar: cuenta → freno → enlace');
  igual(llamo('auth.signInWithOtp').length, 0, 'invitar: nunca el mailer de Supabase');
  // b. reenviar a menos de 60 s → aviso, sin enlace ni correo (el que tiene sigue valiendo)
  avanza(20);
  prepara();
  const rf = await llama(INVITAR, { accion: 'reenviar', email: EMAIL }, ADMIN);
  igual([rf.cuerpo, est.envios.length, llamo('admin.generateLink').length], [{ ok: true, aviso: 'acceso_creado_pero_email_no_enviado' }, 0, 0], 'invitar: frenado → aviso, sin enlace ni correo');
  // c. envío fallido → aviso constante y hueco devuelto
  avanza(61);
  prepara({ correo: () => ({ status: 500, cuerpo: '{"ok":false,"error":"SMTP falló"}' }) });
  const fi = await llama(INVITAR, { accion: 'reenviar', email: EMAIL }, ADMIN);
  igual(fi.cuerpo, { ok: true, aviso: 'acceso_creado_pero_email_no_enviado' }, 'invitar: envío fallido → aviso sin el texto del servidor');
  igual(llamo('rpc:portal_enlace_freno').filter((t) => t.args.p_libera === true).length, 1, 'invitar: devuelve el hueco');
  // d. correo del equipo → 400 de siempre, sin freno, enlace ni correo
  prepara({ equipo: true });
  const eq = await llama(INVITAR, { accion: 'invitar', email: EMAIL, client_ids: ['c1'] }, ADMIN);
  igual([eq.status, eq.cuerpo, est.envios.length, llamo('admin.generateLink').length, llamo('rpc:portal_enlace_freno').length],
    [400, { error: 'ese_email_es_del_equipo' }, 0, 0, 0], 'invitar: equipo → 400, nada sale');
  // d2. cuenta del equipo con otro correo en `usuarios` → 400, sin claim, sin vincular, sin enlace
  prepara({ equipoUid: true });
  const eqc = await llama(INVITAR, { accion: 'invitar', email: EMAIL, client_ids: ['c1'] }, ADMIN);
  igual([eqc.status, eqc.cuerpo, est.envios.length, llamo('admin.generateLink').length, llamo('admin.updateUserById').length, llamo('from:portal_accesos').length],
    [400, { error: 'ese_email_es_del_equipo' }, 0, 0, 0, 0], 'invitar: equipo por cuenta → 400, nada se toca');
  // d3. generateLink LANZA (red) tras pasar el freno → 500 y el hueco se devuelve igualmente
  avanza(61);
  prepara();
  globalThis.__sb.generateLink = () => { throw new TypeError('red caída (prueba)'); };
  const lz = await llama(INVITAR, { accion: 'reenviar', email: EMAIL }, ADMIN);
  igual([lz.status, est.envios.length, llamo('rpc:portal_enlace_freno').filter((t) => t.args.p_libera === true).length], [500, 0, 1], 'invitar: excepción tras el freno → devuelve el hueco');
  // e. sin sesión → 401 sin tocar nada
  prepara();
  const sin = await llama(INVITAR, { accion: 'invitar', email: EMAIL, client_ids: ['c1'] });
  igual([sin.status, est.envios.length, llamo('admin.generateLink').length], [401, 0, 0], 'invitar: sin sesión → 401');

  /* ════════ barrida: ni token, ni action_link, ni la parte local del correo, en ningún log ni respuesta ════════ */
  const junto = todo.join('\n');
  for (const [nombre, v] of [['hashed_token', TOKEN], ['action_link', 'ACTIONLINKSECRETO'], ['otp', '123456'], ['parte local', LOCAL], ['parte local 2', 'otrocomprador'], ['parte local 3', 'tercero'], ['IP en claro', '203.0.113.77'], ['IP en claro 2', '203.0.113.88']]) {
    ok(!junto.includes(v), 'barrida: «' + nombre + '» no aparece en logs ni respuestas');
  }
  ok(todo.length > 30, 'barrida: se han revisado ' + todo.length + ' líneas');

  informe('OK portal_enlace.test.js — ' + n + ' comprobaciones (portal-acceso y portal-invitar: freno, equipo, sin derecho, envío por la vía de servicio, sin token en logs ni respuestas)');
})().catch((e) => { process.stderr.write(String(e && e.stack || e) + '\n'); process.exit(1); });
