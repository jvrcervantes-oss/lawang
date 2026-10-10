/* node ajustes_correo.test.js — la edge `ajustes-correo` (F3.1, 7-oct-2026) con el index.ts REAL, sin red ni Deno ni SMTP de verdad (arnés de envia-correo:
   Deno de mentira, nodemailer de mentira, fetch enrutado). Solo del maestro.
   Qué fija (revisión previa Seguridad + Datos, plan v2):
   · solo un super admin ACTIVO (leído de `usuarios` con la clave de servicio, no de los claims); el uuid y el correo de la prueba salen de la sesión;
   · la prueba se manda al usuario AUTENTICADO aunque el cuerpo nombre a otro;
   · el candidato se promueve SOLO si el envío de prueba pasó; si falla, no se promueve y el activo sigue;
   · la contraseña no aparece ni en la respuesta ni en el log; al cliente solo códigos (nunca el texto del servidor SMTP ni el host);
   · host público únicamente (IP literal, localhost, .internal y DNS a rango privado se rechazan ANTES de tocar la base o el SMTP), puerto 465;
   · cambiar host o usuario: aviso previo por el servidor VIEJO y reautenticación reciente (sesión < 5 min o la contraseña de la cuenta);
   · envíos en pausa: su propio código, sin guardar ni probar nada; CORS solo al origen de la intranet; tope de cuerpo.
   F3.1b (8-oct-2026, código de confirmación): cambiar servidor o uno de los 4 ajustes de correo exige un código de 6 cifras de un solo uso que llega al correo de
   la SESIÓN; la edge guarda solo su HMAC (pepper fuera de la base); atado al cambio exacto; sin pepper no hay modo «sin código»; un único error al navegador;
   avisos previos a los demás super admin y al buzón de sistema; si el correo del código no sale por ningún servidor, no gasta cupo. La base se simula con un
   almacén de códigos que compara huella y hash igual que lo hace correo_codigo_* (la prueba SQL real: erp/pruebas/f31b_correo_codigos.sql). */
const assert = require('assert');

(async () => {
  const A = await import('../envia-correo/arnes.mjs');
  let n = 0;
  const igual = (a, b, m) => { assert.deepStrictEqual(a, b, m); n++; };
  const ok = (c, m) => { assert.ok(c, m); n++; };
  const SECRETO = 'Cl4ve-Sup3r-Secreta!';
  const ORIGEN = 'https://erp.ejemplo.com';
  const EMAIL = 'ana.super@ejemplo.com';
  const BUENO = { accion: 'probar_y_guardar', host: 'smtp.proveedor.com', port: 465, user: 'buzon@ejemplo.com', pass: SECRETO, nombre: 'Acme', contrasena_actual: 'clave-de-la-cuenta' };
  const BEARER = { authorization: 'Bearer jwt-de-super', origin: ORIGEN };
  const todos = { logs: [], respuestas: [] };   // para la barrida final: la contraseña y los códigos no salen por ningún lado
  const PEPPER = 'pepper-de-prueba-0123456789abcdef-0123456789';
  const codigosVistos = [];                     // todos los códigos que salieron por correo: no pueden aparecer en logs ni respuestas

  /** Prepara el arnés. `rpc` = {nombre: (body) => ({status, cuerpo})} para pisar lo de fábrica. */
  let actual = null;   // el `est` de la última prepara()
  function prepara(o = {}) {
    const est = { rpcs: [], token: [], usuarios: [], otros: [], cod: { pend: null, n: 0, fallos: 0, usados: 0, emisiones: [] } };
    actual = est;
    const activo = o.activo === undefined ? null : o.activo;
    const hace = (ms) => new Date(Date.now() - ms).toISOString();
    const coincide = (huella, hash, alcance) => {
      const c = est.cod.pend;
      if (!c) return false;
      const ok = c.alcance === alcance && c.huella === huella && c.hash === hash;
      if (!ok) { c.fallos++; est.cod.fallos++; if (c.fallos >= 5) est.cod.pend = null; }
      return ok;
    };
    const por = {
      correo_smtp_estado: () => ({ status: 200, cuerpo: { configurado: !!activo, host: activo && activo.host, usuario: activo && activo.user, puerto: 465, nombre: null,
        puesto_en: activo ? '2026-10-07T10:00:00Z' : null, puesto_por: activo ? EMAIL : null, hay_previo: false, intentos_recientes: 0, intentos_max: 5 } }),
      correo_smtp_lee: () => ({ status: 200, cuerpo: activo }),
      correo_smtp_guarda_candidato: () => ({ status: 200, cuerpo: { token: '11111111-aaaa-bbbb-cccc-222222222222', hay_activo: !!activo, cambia_servidor: false } }),
      correo_smtp_reauth_intento: (b) => ({ status: 200, cuerpo: b.p_libera == null ? 777 : null }),
      correo_smtp_promueve: (b) => {
        if (!coincide(b.p_huella, b.p_hash, 'servidor')) return { status: 200, cuerpo: { codigo_no_valido: true } };
        est.cod.pend = null; est.cod.usados++;
        return { status: 200, cuerpo: { host: 'smtp.proveedor.com', usuario: 'buzon@ejemplo.com', puesto_en: '2026-10-07T11:00:00Z', hay_previo: !!activo } };
      },
      correo_smtp_descarta: () => ({ status: 200, cuerpo: null }),
      // el almacén de códigos: un pendiente por actor; los fallos suben y a los 5 el código se anula (como _correo_codigo_comprueba)
      correo_codigo_emite: (b) => {
        est.cod.n++; est.cod.pend = { id: est.cod.n, alcance: b.p_alcance, huella: b.p_huella, hash: b.p_hash, fallos: 0 }; est.cod.emisiones.push(b);
        return { status: 200, cuerpo: { id: est.cod.n, caduca: new Date(Date.now() + 600_000).toISOString() } };
      },
      correo_codigo_verifica: (b) => ({ status: 200, cuerpo: { valido: coincide(b.p_huella, b.p_hash, b.p_alcance) } }),
      correo_codigo_retira: (b) => { if (est.cod.pend && est.cod.pend.id === b.p_id) est.cod.pend = null; return { status: 200, cuerpo: null }; },
      correo_ajuste_guarda: (b) => {
        if (!coincide(b.p_huella, b.p_hash, 'ajuste')) return { status: 200, cuerpo: { codigo_no_valido: true } };
        est.cod.pend = null; est.cod.usados++;
        return { status: 200, cuerpo: { clave: b.p_clave, valor: b.p_valor, cambiado: true } };
      },
      ...(o.rpc || {}),
    };
    const extra = async (u, init = {}) => {
      const url = new URL(u);
      if (url.pathname === '/auth/v1/user') {
        if (o.sesion === false) return new Response('{}', { status: 401 });
        if (o.authError) return new Response('boom', { status: 500 });
        return new Response(JSON.stringify({ id: A.UID, email: o.email === undefined ? EMAIL : o.email, last_sign_in_at: o.ultimoAcceso || hace(60_000) }), { status: 200 });
      }
      if (url.pathname === '/rest/v1/usuarios') {
        est.usuarios.push({ search: url.search, cabeceras: init.headers });
        if (o.usuariosError) return new Response('boom', { status: 500 });
        if (/user_id=neq\./.test(url.search)) {   // «los demás super admin»
          if (o.otrosError) return new Response('boom', { status: 500 });
          est.otros.push(url.search);
          return new Response(JSON.stringify((o.otros || []).map((email) => ({ email }))), { status: 200 });
        }
        return new Response(JSON.stringify(o.super === false ? [] : [{ user_id: A.UID }]), { status: 200 });
      }
      if (url.pathname === '/auth/v1/token') {
        est.token.push(JSON.parse(init.body));
        return new Response('{}', { status: o.claveBuena === false ? 400 : 200 });
      }
      const m = /\/rest\/v1\/rpc\/(correo_(?:smtp|codigo|ajuste)_\w+)$/.exec(url.pathname);
      if (m) {
        const body = JSON.parse(init.body || '{}');
        est.rpcs.push({ nombre: m[1], body, cabeceras: init.headers });
        if (o.rpcLanza === m[1]) throw new TypeError('red caída (prueba)');
        const r = por[m[1]](body);
        return new Response(JSON.stringify(r.cuerpo), { status: r.status });
      }
      return null;
    };
    A.reinicia({ sesion: true, pausado: o.pausado || false, extra, env: o.sinPepper ? {} : { CORREO_CODIGO_PEPPER: PEPPER, ...(o.env || {}) }, config: [...A.CONFIG_BASE, ['email_from', o.emailFrom === undefined ? 'ventas@ejemplo.com' : o.emailFrom], ...(o.config || [])] });
    globalThis.Deno.resolveDns = o.dns === null ? undefined : (o.dns || (async () => ['203.0.113.250'.replace('203.0.113', '93.184.216')]));
    return est;
  }
  async function pide(cuerpo, cabeceras = BEARER, opciones = {}) {
    const m = await A.cargaEdge(__dirname);
    const r = await A.llama(m, { cabeceras, cuerpo, ...opciones });
    todos.logs.push(...r.logs); todos.respuestas.push(r.crudo);
    return r;
  }
  /** Llama al manejador sin pasar por `llama` (cuerpos que no son JSON) con el log recogido, no impreso. */
  async function directo(m, peticion) {
    const orig = console.log; console.log = (...a) => { todos.logs.push(a.join(' ')); };
    try { const x = await m(peticion); return x; } finally { console.log = orig; }
  }
  /** Las RPC de la última petición, SIN las de códigos (esas se miran aparte con `cods`). */
  const nombres = (est) => est.rpcs.map((x) => x.nombre).filter((n) => !n.startsWith('correo_codigo_'));
  const cods = (est) => est.rpcs.map((x) => x.nombre).filter((n) => n.startsWith('correo_codigo_'));
  /** El código que acaba de salir por correo a la sesión (el último correo con «Tu código de confirmación es: NNNNNN»). */
  function codigoDelCorreo() {
    const cs = A.estado.correo.correos;
    for (let i = cs.length - 1; i >= 0; i--) { const m = /Tu código de confirmación es: (\d{6})/.exec(cs[i].text || ''); if (m) { codigosVistos.push(m[1]); return { codigo: m[1], correo: cs[i] }; } }
    return null;
  }
  /** Pide el código para ESE cambio (como lo haría la pantalla), lo lee del correo y repite la petición con él. `antes()` se llama entre las dos (para armar
   *  un fallo SMTP que no debe afectar al correo del código). Si pedir el código falla, devuelve ese fallo. Deja `est.rpcs` y los correos de la petición real. */
  async function pideOk(cuerpo, cab = BEARER, antes = null) {
    const pedir = cuerpo.accion === 'guardar_ajuste'
      ? { accion: 'pedir_codigo', alcance: 'ajuste', clave: cuerpo.clave, valor: cuerpo.valor }
      : { accion: 'pedir_codigo', alcance: 'servidor', host: cuerpo.host, port: cuerpo.port, user: cuerpo.user, pass: cuerpo.pass, nombre: cuerpo.nombre };
    const p = await pide(pedir, cab);
    if (p.status !== 200) return p;
    const k = codigoDelCorreo();
    ok(k, 'el código salió por correo');
    A.estado.correo.correos.splice(0); A.estado.correo.transportes.splice(0);
    actual.rpcs.splice(0);
    if (antes) antes();
    return pide({ ...cuerpo, codigo: k.codigo }, cab);
  }
  const lineas = (r) => r.logs.map((l) => { try { return JSON.parse(l); } catch { return null; } }).filter((x) => x && x.fn === 'ajustes-correo');

  // ── 1. quién ────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  let est = prepara();
  let r = await pide(BUENO, { origin: ORIGEN });
  igual([r.status, r.cuerpo.codigo], [401, 'sin_sesion'], 'sin credencial');
  {   // B1: sin Authorization ni X-Suite-Token se contesta 401 ANTES de leer la configuración (no se gasta una consulta a la base por una petición anónima)
    const f0 = globalThis.fetch; let lecturas = 0;
    globalThis.fetch = (u, i) => { if (String(u).includes('/rest/v1/config_instancia')) lecturas++; return f0(u, i); };
    try {
      for (const cab of [{ origin: ORIGEN }, {}, { authorization: '  ', 'x-suite-token': '' }]) { r = await pide(BUENO, cab); igual([r.status, r.cuerpo.codigo], [401, 'sin_sesion'], 'anónimo'); }
      igual(lecturas, 0, 'una petición sin credencial no lee la configuración');
      r = await pide(BUENO, { 'x-suite-token': 'jwt-de-super', origin: ORIGEN }); igual(lecturas > 0 && r.status !== 401, true, 'con X-Suite-Token sí sigue su camino');
      lecturas = 0;
      const m0 = await A.cargaEdge(__dirname);
      const pre = await directo(m0, new Request('https://ref.supabase.co/x', { method: 'OPTIONS', headers: { origin: ORIGEN } }));
      igual([pre.status, lecturas > 0], [204, true], 'el preflight CORS (sin credenciales) sigue leyendo la configuración para dar sus cabeceras');
    } finally { globalThis.fetch = f0; }
  }
  est = prepara();
  r = await pide(BUENO, { authorization: 'Bearer anon-falsa', origin: ORIGEN }); igual(r.status, 401, 'la clave anon no es sesión');
  r = await pide(BUENO, { authorization: 'Bearer service-falsa', origin: ORIGEN }); igual(r.status, 401, 'la clave de servicio no abre esta puerta');
  igual(est.rpcs.length, 0, 'sin sesión no se toca la base');
  est = prepara({ sesion: false }); r = await pide(BUENO); igual([r.status, r.cuerpo.codigo], [401, 'sin_sesion'], 'sesión no válida'); igual(est.rpcs.length, 0);
  est = prepara({ super: false }); r = await pide(BUENO); igual([r.status, r.cuerpo.codigo], [403, 'no_super_admin'], 'un admin que no es super');
  igual(est.rpcs.length, 0, 'ni lee ni guarda nada');
  ok(/rol=eq\.super_admin/.test(est.usuarios[0].search) && /activo=is\.true/.test(est.usuarios[0].search), 'el rol y el estado activo se miran en `usuarios`');
  ok(String(est.usuarios[0].cabeceras.Authorization) === 'Bearer service-falsa', '… con la clave de servicio, no con el JWT del usuario');
  est = prepara({ usuariosError: true }); r = await pide(BUENO); igual([r.status, r.cuerpo.codigo], [502, 'base_no_responde'], 'si no se puede comprobar el rol, no se da por bueno');
  est = prepara({ authError: true }); r = await pide(BUENO); igual(r.status, 502);
  est = prepara(); r = await pide({ accion: 'estado' }, { 'x-suite-token': 'jwt-de-super', origin: ORIGEN }); igual(r.status, 200, 'X-Suite-Token también vale');

  // ── 2. CORS, método, cuerpo ─────────────────────────────────────────────────────────────────────────────────────────────────
  est = prepara();
  let m = await A.cargaEdge(__dirname);
  let rr = await directo(m, new Request('https://ref.supabase.co/functions/v1/ajustes-correo', { method: 'OPTIONS', headers: { origin: ORIGEN } }));
  igual([rr.status, rr.headers.get('access-control-allow-origin')], [204, ORIGEN], 'preflight: solo el origen de la intranet');
  rr = await directo(m, new Request('https://ref.supabase.co/x', { method: 'OPTIONS', headers: { origin: 'https://fraude.ru' } }));
  igual([rr.status, rr.headers.get('access-control-allow-origin')], [403, null], 'otro origen: 403 y sin CORS');
  r = await pide({ accion: 'estado' }, { authorization: 'Bearer j', origin: 'https://fraude.ru' }); igual([r.status, r.cuerpo.codigo], [403, 'origen']);
  r = await pide({ accion: 'estado' }, { authorization: 'Bearer j' }); igual(r.status, 200, 'sin Origin (llamante de servidor): sin CORS pero pasa por la sesión');
  rr = await directo(m, new Request('https://ref.supabase.co/x', { method: 'GET', headers: BEARER })); igual(rr.status, 405, 'solo POST');
  rr = await directo(m, new Request('https://ref.supabase.co/x', { method: 'POST', headers: { ...BEARER, 'content-length': String(40_000) }, body: '{}' })); igual(rr.status, 413, 'tope por cabecera');
  rr = await directo(m, new Request('https://ref.supabase.co/x', { method: 'POST', headers: BEARER, body: '{"accion":"estado","relleno":"' + 'x'.repeat(20_000) + '"}' })); igual(rr.status, 413, 'tope por cuerpo');
  rr = await directo(m, new Request('https://ref.supabase.co/x', { method: 'POST', headers: BEARER, body: '{no es json' })); igual(rr.status, 400, 'JSON inválido');
  rr = await directo(m, new Request('https://ref.supabase.co/x', { method: 'POST', headers: BEARER, body: '[1]' })); igual(rr.status, 400, 'un array no es un objeto');
  r = await pide({ accion: 'borrar_todo' }); igual([r.status, r.cuerpo.codigo], [400, 'accion_no_valida']);
  r = await pide({}); igual([r.status, r.cuerpo.codigo], [400, 'accion_no_valida']);

  // ── 3. estado: sin contraseña, con el desajuste de remitente ────────────────────────────────────────────────────────────────
  est = prepara({ activo: { host: 'smtp.viejo.com', user: 'buzon@ejemplo.com', pass: SECRETO, nombre: null }, emailFrom: 'ceo@banco.com', config: [['email_reply_to', 'hola@ejemplo.com']] });
  r = await pide({ accion: 'estado' });
  igual(r.status, 200); ok(r.cuerpo.ok === true && r.cuerpo.estado.configurado === true && r.cuerpo.estado.host === 'smtp.viejo.com', 'el estado');
  ok(!r.crudo.includes(SECRETO) && !('pass' in r.cuerpo.estado), 'el estado no lleva la contraseña');
  igual([r.cuerpo.remitente.motivo, r.cuerpo.remitente.efectivo, r.cuerpo.remitente.email_from], ['dominio_distinto', 'buzon@ejemplo.com', 'ceo@banco.com'], 'dice que el remitente de Ajustes no se usa y por qué');
  igual(r.cuerpo.envios_pausados, false);
  est = prepara({ pausado: true }); r = await pide({ accion: 'estado' }); igual(r.cuerpo.envios_pausados, true);
  est = prepara({ rpc: { correo_smtp_estado: () => ({ status: 500, cuerpo: { code: 'XX000' } }) } }); r = await pide({ accion: 'estado' }); igual([r.status, r.cuerpo.codigo], [502, 'base_no_responde'], 'un fallo al leer el estado se dice');

  // ── 4. el camino bueno: primer servidor (sin servidor en Vault: manda el de entorno hasta ahora) ──────────────────────────────
  est = prepara();
  r = await pideOk({ ...BUENO, to: 'otro@fraude.ru', email: 'otro@fraude.ru', destino: 'otro@fraude.ru', p_actor: '00000000-0000-0000-0000-000000000000' });
  igual(r.status, 200, JSON.stringify(r.cuerpo)); ok(r.cuerpo.ok && r.cuerpo.guardado, 'guardado');
  igual(nombres(est), ['correo_smtp_lee', 'correo_smtp_reauth_intento', 'correo_smtp_reauth_intento', 'correo_smtp_guarda_candidato', 'correo_smtp_promueve', 'correo_smtp_estado'], 'orden: lee → contraseña de la cuenta (reserva y liberación) → candidato → (prueba) → promueve');
  igual(cods(est), ['correo_codigo_verifica'], 'el código se comprueba SIN consumir antes de probar; se consume al promover');
  const gc = est.rpcs.find((x) => x.nombre === 'correo_smtp_guarda_candidato').body;
  igual([gc.p_actor, gc.p_host, gc.p_port, gc.p_user, gc.p_pass, gc.p_nombre], [A.UID, 'smtp.proveedor.com', 465, 'buzon@ejemplo.com', SECRETO, 'Acme'], 'el uuid es el de la sesión, no el del cuerpo');
  const pb = est.rpcs.find((x) => x.nombre === 'correo_smtp_promueve').body;
  igual([pb.p_actor, pb.p_token], [A.UID, '11111111-aaaa-bbbb-cccc-222222222222'], 'promueve con el token del candidato y el actor de la sesión');
  ok(/^\\x[0-9a-f]{64}$/.test(pb.p_huella) && /^\\x[0-9a-f]{64}$/.test(pb.p_hash), 'huella y hash viajan como bytea de 32 bytes'); igual(est.cod.usados, 1, 'el código se consumió una vez');
  const cx = A.estado.correo;
  igual(cx.correos.length, 2, 'la prueba y el aviso previo (primera carga = cambio de servidor)'); igual(cx.correos[0].to, EMAIL, 'la prueba va al usuario AUTENTICADO, no a la dirección del cuerpo');
  igual([cx.correos[0]._host, cx.correos[0]._user], ['smtp.proveedor.com', 'buzon@ejemplo.com'], 'con el servidor NUEVO');
  igual(cx.correos[0].from.address, 'ventas@ejemplo.com', 'sale con el remitente de Ajustes (dominio de la instancia)');
  igual(cx.transportes[0], { host: 'smtp.proveedor.com', port: 465, secure: true, user: 'buzon@ejemplo.com' }, '465 con TLS implícito');
  igual(cx.verificados.length, 1, 'verify() antes del envío');
  ok(!cx.correos[0].text.includes(SECRETO), 'el correo de prueba no lleva la contraseña');
  igual([cx.correos[1].to, cx.correos[1]._host], ['sistema@ejemplo.com', 'smtp.falso.test'], 'sin servidor en Vault, el aviso previo sale por el de entorno al buzón de sistema');
  igual([r.cuerpo.aviso, r.cuerpo.prueba_enviada_a], ['enviado', EMAIL]);
  ok(!r.crudo.includes(SECRETO), 'la respuesta no lleva la contraseña');
  ok(r.logs.every((l) => !l.includes(SECRETO) && !l.includes('smtp.proveedor.com') && !l.includes('buzon@ejemplo.com')), 'el log no lleva contraseña, host ni usuario');
  const l = lineas(r)[0]; igual([l.fn, l.accion, l.estado], ['ajustes-correo', 'probar_y_guardar', 200], 'la línea de log');

  // ── 5. la prueba falla → NO se promueve; el candidato se descarta; el cliente solo ve códigos ──────────────────────────────────
  for (const [fase, armar] of [['verify', (c) => { c.falloVerify = Object.assign(new Error('Invalid login: 535 5.7.8 Username and Password not accepted (cuenta secreta@ejemplo.com)'), { code: 'EAUTH', responseCode: 535, response: '535 5.7.8 Username and Password not accepted for secreta@ejemplo.com' }); }],
                               ['envio', (c) => { c.falloSmtp = Object.assign(new Error('554 5.7.1 rechazado'), { code: 'EENVELOPE', responseCode: 554, response: '554 5.7.1 Relay denied para cuenta-interna@ejemplo.com' }); }]]) {
    est = prepara();
    r = await pideOk(BUENO, BEARER, () => armar(A.estado.correo));   // se arma DESPUÉS del código: el correo del código no debe fallar
    igual([r.status, r.cuerpo.codigo, r.cuerpo.fase], [422, 'prueba_fallida', fase], 'la prueba falló en ' + fase);
    ok(!nombres(est).includes('correo_smtp_promueve'), 'NO se promueve (el activo anterior sigue)'); igual(est.cod.usados, 0, 'y el código NO se gasta: se puede repetir la prueba');
    ok(nombres(est).includes('correo_smtp_guarda_candidato'), 'el candidato sí se guardó (cuenta el intento)'); ok(nombres(est).includes('correo_smtp_descarta'), '… y se descarta al fallar');
    igual(est.rpcs.find((x) => x.nombre === 'correo_smtp_descarta').body, { p_actor: A.UID, p_token: '11111111-aaaa-bbbb-cccc-222222222222' });
    ok(r.cuerpo.smtp_code && Number.isInteger(r.cuerpo.smtp_response_code), 'códigos estructurados');
    ok(!r.crudo.includes('cuenta-interna') && !r.crudo.includes('secreta@') && !r.crudo.includes('Relay denied') && !r.crudo.includes(SECRETO) && !r.crudo.includes('smtp.proveedor.com'), 'ni el texto del servidor, ni el host, ni la contraseña');
    ok(r.logs.every((x) => !x.includes('cuenta-interna') && !x.includes('secreta@') && !x.includes('Relay denied') && !x.includes(SECRETO)), 'el log tampoco');
    igual(A.estado.correo.correos.length, 0, 'no salió ningún correo');
  }
  // un fallo de certificado: el código TLS (cerrado) llega, el texto no
  est = prepara(); r = await pideOk(BUENO, BEARER, () => { A.estado.correo.falloVerify = Object.assign(new Error('self-signed certificate in chain, host smtp.proveedor.com'), { code: 'ESOCKET', cause: { code: 'DEPTH_ZERO_SELF_SIGNED_CERT' } }); });
  igual([r.status, r.cuerpo.smtp_code, r.cuerpo.detalle_code], [422, 'ESOCKET', 'DEPTH_ZERO_SELF_SIGNED_CERT']); ok(!r.crudo.includes('self-signed'), 'sin el texto libre');

  // ── 6. validación del servidor ANTES de tocar la base o el SMTP (y antes de gastar un código) ──────────────────────────────────
  const malos = [[{ host: '127.0.0.1' }, 'host_no_valido'], [{ host: 'localhost' }, 'host_no_valido'], [{ host: 'smtp.internal' }, 'host_no_valido'], [{ host: '10.0.0.5' }, 'host_no_valido'],
    [{ host: '2130706433' }, 'host_no_valido'], [{ host: '[::1]' }, 'host_no_valido'], [{ host: 'smtp.proveedor.com:25' }, 'host_no_valido'], [{ host: undefined }, 'host_no_valido'],
    [{ port: 587 }, 'puerto_no_valido'], [{ port: 25 }, 'puerto_no_valido'], [{ port: '465' }, 'puerto_no_valido'], [{ user: '' }, 'usuario_no_valido'],
    [{ user: 'a@x.com\r\nBcc: v@y.com' }, 'usuario_no_valido'], [{ pass: '' }, 'clave_no_valida'], [{ pass: 'a\nb' }, 'clave_no_valida'], [{ nombre: '<b>x</b>' }, 'nombre_no_valido']];
  for (const accionMala of ['probar_y_guardar', 'pedir_codigo']) {
    for (const [parche, codigo] of malos) {
      est = prepara(); r = await pide({ ...BUENO, accion: accionMala, alcance: 'servidor', codigo: '123456', ...parche });
      igual([r.status, r.cuerpo.codigo], [400, codigo], accionMala + ' ' + JSON.stringify(parche));
      igual(est.rpcs.length, 0, 'no se toca la base: ' + JSON.stringify(parche)); igual(A.estado.correo.transportes.length, 0, 'no se abre ninguna conexión SMTP');
      ok(!r.crudo.includes(SECRETO), 'ni siquiera un error eco de la contraseña');
    }
  }
  est = prepara({ dns: async () => ['10.0.0.8'] }); r = await pide(BUENO);
  igual([r.status, r.cuerpo.codigo], [400, 'host_privado'], 'un nombre público que resuelve a una IP privada'); igual(est.rpcs.length, 0); igual(A.estado.correo.transportes.length, 0);
  est = prepara({ dns: async () => ['10.0.0.8'] }); r = await pide({ ...BUENO, accion: 'pedir_codigo', alcance: 'servidor' }); igual([r.status, r.cuerpo.codigo, est.rpcs.length], [400, 'host_privado', 0], 'y no se manda un código por un servidor que se va a rechazar');
  est = prepara({ dns: async (h, t) => (t === 'A' ? ['93.184.216.34'] : ['fe80::1']) }); r = await pide(BUENO); igual(r.cuerpo.codigo, 'host_privado', 'basta UNA dirección privada (AAAA)');
  est = prepara({ dns: async () => { const e = new Error('no existe'); e.name = 'NotFound'; throw e; } }); r = await pide(BUENO); igual([r.status, r.cuerpo.codigo], [400, 'host_no_resuelve']);
  // M2 (8-oct-2026): si el runtime no deja comprobar el DNS se FALLA CERRADO: ni se conecta ni se manda código
  est = prepara({ dns: async () => { throw new Error('operación no permitida en este runtime'); } }); r = await pide(BUENO);
  igual([r.status, r.cuerpo.codigo, est.rpcs.length, A.estado.correo.transportes.length], [503, 'host_no_comprobable', 0, 0], 'DNS que falla de forma rara: se rechaza sin conectar');
  est = prepara({ dns: null }); r = await pide(BUENO);
  igual([r.status, r.cuerpo.codigo, est.rpcs.length, A.estado.correo.transportes.length], [503, 'host_no_comprobable', 0, 0], 'sin Deno.resolveDns tampoco se acepta');
  est = prepara({ dns: null }); r = await pide({ ...BUENO, accion: 'pedir_codigo', alcance: 'servidor' });
  igual([r.status, r.cuerpo.codigo, est.rpcs.length, A.estado.correo.correos.length], [503, 'host_no_comprobable', 0, 0], 'y no se manda un código por un servidor que no se pudo comprobar');
  est = prepara({ dns: async (h, t) => (t === 'A' ? ['93.184.216.34'] : ['2606:2800:220:1:248:1893:25c8:1946']) }); r = await pideOk(BUENO); igual(r.status, 200, 'IPv4 e IPv6 públicas');
  est = prepara({ email: '' }); r = await pide(BUENO); igual([r.status, r.cuerpo.codigo], [400, 'sin_correo_usuario'], 'sin correo propio no hay a quién mandar la prueba');
  est = prepara({ email: '' }); r = await pide({ ...BUENO, accion: 'pedir_codigo', alcance: 'servidor' }); igual([r.status, r.cuerpo.codigo], [400, 'sin_correo_usuario'], 'ni el código');
  est = prepara(); r = await pideOk({ ...BUENO, user: 'login-suelto' }); igual([r.status, r.cuerpo.codigo], [200, undefined], 'un usuario que no es correo vale si hay remitente de Ajustes');
  est = prepara({ emailFrom: '' }); r = await pide({ ...BUENO, user: 'login-suelto' }); igual([r.status, r.cuerpo.codigo], [400, 'sin_remitente'], 'ni usuario-correo ni remitente: no se puede enviar');
  igual(est.rpcs.length, 0, 'y no se guardó nada');
  est = prepara({ emailFrom: 'ceo@banco.com' }); r = await pideOk(BUENO); igual(A.estado.correo.correos[0].from.address, 'buzon@ejemplo.com', 'el remitente ajeno no se usa: sale el buzón');

  // ── 7. pausa de envíos ─────────────────────────────────────────────────────────────────────────────────────────────────────────
  est = prepara({ pausado: true }); r = await pide(BUENO);
  igual([r.status, r.cuerpo.codigo], [503, 'envios_pausados'], 'su propio código: no se confunde con una credencial mala');
  igual(est.rpcs.length, 0, 'ni lee ni guarda'); igual(A.estado.correo.transportes.length, 0, 'ni abre el SMTP');
  est = prepara({ pausado: 'error' }); r = await pide(BUENO); igual(r.cuerpo.codigo, 'envios_pausados', 'si no se puede preguntar, no se envía (como envia-correo)');
  est = prepara({ pausado: true }); r = await pide({ accion: 'pedir_codigo', alcance: 'ajuste', clave: 'email_reply_to', valor: 'r@ejemplo.com' });
  igual([r.status, r.cuerpo.codigo, est.rpcs.length], [503, 'envios_pausados', 0], 'tampoco se piden códigos en pausa');

  // ── 8. cambiar de servidor: aviso por el VIEJO y reautenticación ────────────────────────────────────────────────────────────────
  const SIN = (b) => { const { contrasena_actual, ...x } = b; return x; };
  const VIEJO = { host: 'smtp.viejo.com', user: 'viejo@ejemplo.com', pass: 'clave-vieja-12345', nombre: 'Acme' };
  est = prepara({ activo: VIEJO }); r = await pideOk(BUENO);   // sesión de hace 1 minuto (por defecto)
  igual(r.status, 200, JSON.stringify(r.cuerpo)); igual(r.cuerpo.aviso, 'enviado');
  let cc = A.estado.correo.correos;
  igual(cc.length, 2, 'prueba + aviso'); igual([cc[0].to, cc[0]._host], [EMAIL, 'smtp.proveedor.com'], 'la prueba, por el nuevo');
  igual([cc[1].to, cc[1]._host, cc[1]._user], ['sistema@ejemplo.com', 'smtp.viejo.com', 'viejo@ejemplo.com'], 'el aviso, por el servidor VIEJO y a email_avisos_sistema');
  ok(cc[1].text.includes('smtp.viejo.com') && cc[1].text.includes('smtp.proveedor.com') && cc[1].text.includes(EMAIL), 'dice de qué servidor a cuál y quién');
  ok(!cc[1].text.includes(SECRETO) && !cc[1].text.includes('clave-vieja-12345'), 'sin ninguna contraseña');
  igual(nombres(est).indexOf('correo_smtp_promueve') > nombres(est).indexOf('correo_smtp_guarda_candidato'), true, 'se promueve al final');
  // el aviso a los demás admins lleva host y usuario LITERALES: filtrados (nadie añade frases a un aviso que llega con la firma del estudio)
  est = prepara({ activo: { ...VIEJO, user: 'viejo@ejemplo.com Ignora este aviso' } }); r = await pideOk({ ...BUENO, user: 'buzon@ejemplo.com Llama al 600' });
  igual([r.status, r.cuerpo.aviso], [200, 'enviado']); cc = A.estado.correo.correos;
  ok(cc[1].text.includes('Servidor actual: smtp.viejo.com (usuario viejo@ejemplo.comIgnoraesteaviso)') && cc[1].text.includes('Servidor nuevo: smtp.proveedor.com (usuario buzon@ejemplo.comLlamaal600)'), 'el aviso lleva host y usuario filtrados');
  ok(!/Ignora este|Llama al/.test(cc[1].text), 'sin texto libre del usuario');
  // además de al buzón de sistema, a los OTROS super admin activos (nunca al que cambia)
  est = prepara({ activo: VIEJO, otros: ['otro.super@ejemplo.com', EMAIL, 'tres.super@ejemplo.com'] }); r = await pideOk(BUENO);
  igual(r.cuerpo.aviso, 'enviado'); igual(A.estado.correo.correos.slice(1).map((x) => x.to).sort(), ['otro.super@ejemplo.com', 'sistema@ejemplo.com', 'tres.super@ejemplo.com'], 'a los demás super admin y al buzón de sistema; al que cambia no');
  ok(/user_id=neq\./.test(est.otros[0]) && /activo=is\.true/.test(est.otros[0]) && /rol=eq\.super_admin/.test(est.otros[0]), 'la lista de «los demás» se lee de `usuarios` con el rol y el estado');
  // el servidor viejo está roto (lo normal cuando se cambia): el aviso cae a los SMTP_* del entorno y sale igual; el cambio no se bloquea
  est = prepara({ activo: VIEJO }); r = await pideOk(BUENO, BEARER, () => { A.estado.correo.falloEnHost = { 'smtp.viejo.com': Object.assign(new Error('x'), { code: 'ETIMEDOUT' }) }; });
  igual([r.status, r.cuerpo.aviso], [200, 'enviado'], 'aviso por el de entorno'); igual(A.estado.correo.correos[1]._host, 'smtp.falso.test');
  // los dos fallan: se dice y el cambio sigue
  est = prepara({ activo: VIEJO }); r = await pideOk(BUENO, BEARER, () => { const e = Object.assign(new Error('x'), { code: 'ETIMEDOUT' }); A.estado.correo.falloEnHost = { 'smtp.viejo.com': e, 'smtp.falso.test': e }; });
  igual([r.status, r.cuerpo.aviso], [200, 'no_enviado'], 'el aviso no bloquea'); ok(nombres(est).includes('correo_smtp_promueve'));
  // un buzón de sistema de otro dominio no recibe avisos; sin nadie más, el cambio se permite y QUEDA ANOTADO en el registro (p_nota)
  est = prepara({ activo: VIEJO, config: [['email_avisos_sistema', 'sistema@otro-dominio.com']] }); r = await pideOk(BUENO);
  igual([r.status, r.cuerpo.aviso], [200, 'sin_destinatario'], 'un buzón de aviso de otro dominio no se usa y sin más super admin no hay a quién avisar');
  igual(est.rpcs.find((x) => x.nombre === 'correo_smtp_promueve').body.p_nota, 'sin otro destinatario de aviso', 'queda anotado'); igual(A.estado.correo.correos.length, 1, 'solo la prueba');
  est = prepara({ activo: VIEJO, config: [['email_avisos_sistema', 'sistema@otro-dominio.com']], otros: ['otro.super@ejemplo.com'] }); r = await pideOk(BUENO);
  igual(r.cuerpo.aviso, 'enviado', 'con otro super admin sí hay a quién avisar'); igual(est.rpcs.find((x) => x.nombre === 'correo_smtp_promueve').body.p_nota, null);
  // regla del owner (7-oct-2026): también vale el dominio de email_from o el del usuario del servidor VIEJO
  est = prepara({ activo: VIEJO, emailFrom: 'ventas@otro-dominio.com', config: [['email_avisos_sistema', 'sistema@otro-dominio.com']] }); r = await pideOk(BUENO);
  igual([r.status, r.cuerpo.aviso], [200, 'enviado'], 'buzón del dominio de email_from');
  est = prepara({ activo: { ...VIEJO, user: 'viejo@servidor-vault.com' }, config: [['email_avisos_sistema', 'sistema@servidor-vault.com']] }); r = await pideOk(BUENO);
  igual([r.status, r.cuerpo.aviso], [200, 'enviado'], 'buzón del dominio del usuario del servidor viejo');
  est = prepara({ activo: { ...VIEJO, user: 'viejo@servidor-vault.com' }, config: [['email_avisos_sistema', 'sistema@sub.servidor-vault.com']] }); r = await pideOk(BUENO);
  igual([r.status, r.cuerpo.aviso], [200, 'sin_destinatario'], 'del servidor/email_from solo vale el dominio exacto, no un subdominio');
  // solo la contraseña (mismo host y usuario): ni aviso ni contraseña de la cuenta (solo se exige al cambiar host o usuario)
  est = prepara({ activo: { ...VIEJO, host: 'smtp.proveedor.com', user: 'buzon@ejemplo.com' }, ultimoAcceso: new Date(Date.now() - 3 * 3600_000).toISOString() });
  r = await pideOk(SIN(BUENO)); igual([r.status, r.cuerpo.aviso], [200, 'no_aplica'], 'mismo servidor: solo cambia la contraseña'); igual(A.estado.correo.correos.length, 1);
  // primera carga (sin servidor en Vault) con sesión vieja: también es un cambio de servidor → pide la contraseña
  est = prepara({ ultimoAcceso: new Date(Date.now() - 3 * 3600_000).toISOString() }); r = await pideOk(SIN(BUENO));
  igual([r.status, r.cuerpo.codigo], [401, 'reautenticar'], 'primera carga sin la contraseña de la cuenta'); igual(nombres(est), ['correo_smtp_lee']);
  est = prepara({ ultimoAcceso: new Date(Date.now() - 3 * 3600_000).toISOString() }); r = await pideOk({ ...BUENO, contrasena_actual: 'mi-clave' });
  igual([r.status, r.cuerpo.aviso], [200, 'enviado'], 'con la contraseña pasa; sin servidor en Vault el aviso sale por el de entorno');
  const err = (code, hint, status = 400) => () => ({ status, cuerpo: { code, hint, message: 'detalle interno con ' + SECRETO } });
  // reautenticación
  const VIEJA = new Date(Date.now() - 10 * 60_000).toISOString();
  est = prepara({ activo: VIEJO, ultimoAcceso: VIEJA }); r = await pideOk(SIN(BUENO));
  igual([r.status, r.cuerpo.codigo], [401, 'reautenticar'], 'sesión de hace 10 min y cambio de host: pide la contraseña'); igual(nombres(est), ['correo_smtp_lee'], 'antes de guardar nada'); igual(A.estado.correo.transportes.length, 0);
  igual(est.cod.usados, 0, 'y el código no se gastó');
  est = prepara({ activo: VIEJO, ultimoAcceso: VIEJA }); r = await pideOk({ ...BUENO, contrasena_actual: 'mi-clave', email: 'otro@x.com' });
  igual(r.status, 200, JSON.stringify(r.cuerpo)); igual(est.token.length, 1); igual(est.token[0], { email: EMAIL, password: 'mi-clave' }, 'la contraseña se comprueba para el correo de la SESIÓN, no el del cuerpo');
  ok(!r.crudo.includes('mi-clave') && r.logs.every((x) => !x.includes('mi-clave')), 'la contraseña de la cuenta no sale');
  est = prepara({ activo: VIEJO, ultimoAcceso: VIEJA, claveBuena: false }); r = await pideOk({ ...BUENO, contrasena_actual: 'mala' });
  igual([r.status, r.cuerpo.codigo], [401, 'clave_actual_incorrecta']); igual(nombres(est), ['correo_smtp_lee', 'correo_smtp_reauth_intento'], 'con la clave mala no se guarda nada y la reserva NO se libera');
  // el intento se reserva ANTES de preguntar a Auth; con la contraseña buena se libera la reserva (id devuelto)
  est = prepara({ activo: VIEJO, ultimoAcceso: VIEJA }); r = await pideOk({ ...BUENO, contrasena_actual: 'mi-clave' });
  const reas = est.rpcs.filter((x) => x.nombre === 'correo_smtp_reauth_intento');
  igual(reas.map((x) => x.body), [{ p_actor: A.UID }, { p_actor: A.UID, p_libera: 777 }], 'reserva y liberación al acertar');
  ok(nombres(est).indexOf('correo_smtp_reauth_intento') < nombres(est).indexOf('correo_smtp_guarda_candidato'));
  // límite superado: ni se consulta /auth/v1/token (la sesión robada no puede probar contraseñas); el 429 queda en el log
  est = prepara({ activo: VIEJO, ultimoAcceso: VIEJA, rpc: { correo_smtp_reauth_intento: err('P0001', 'demasiados_intentos') } }); r = await pideOk({ ...BUENO, contrasena_actual: 'mala' });
  igual([r.status, r.cuerpo.codigo], [429, 'demasiados_intentos']); igual(est.token.length, 0, 'sin consultar a Auth'); igual(A.estado.correo.transportes.length, 0);
  ok(r.logs.some((x) => x.includes('429')), 'el 429 va al log');
  est = prepara({ activo: VIEJO, ultimoAcceso: VIEJA, rpc: { correo_smtp_reauth_intento: err('XX000', '', 500) } }); r = await pideOk({ ...BUENO, contrasena_actual: 'mi-clave' });
  igual([r.status, r.cuerpo.codigo], [502, 'base_no_responde']); igual(est.token.length, 0, 'si no se puede contar, no se prueba');
  est = prepara({ activo: VIEJO, ultimoAcceso: VIEJA, rpc: { correo_smtp_reauth_intento: err('42501', '') } }); r = await pideOk({ ...BUENO, contrasena_actual: 'x' }); igual([r.status, r.cuerpo.codigo, est.token.length], [403, 'no_super_admin', 0]);
  // decisión del owner 8-oct: una sesión RECIENTE ya no sustituye a la contraseña de la cuenta
  est = prepara({ activo: VIEJO }); r = await pideOk(SIN(BUENO)); igual([r.status, r.cuerpo.codigo], [401, 'reautenticar'], 'sesión de hace 1 min: pide igualmente la contraseña'); igual(est.cod.usados, 0);
  est = prepara({ activo: VIEJO, ultimoAcceso: 'no es una fecha' }); r = await pideOk(SIN(BUENO)); igual(r.cuerpo.codigo, 'reautenticar', 'sin fecha de acceso: se pide');
  est = prepara({ activo: { ...VIEJO, host: 'smtp.proveedor.com' }, ultimoAcceso: VIEJA }); r = await pideOk(SIN(BUENO)); igual(r.cuerpo.codigo, 'reautenticar', 'cambiar solo el usuario también cuenta como cambiar de servidor');
  est = prepara({ activo: VIEJO }); r = await pideOk({ ...BUENO, contrasena_actual: SECRETO }); ok(!r.crudo.includes(SECRETO));

  // ── 9. errores de la base: traducidos a códigos, sin filtrar ──────────────────────────────────────────────────────────────────
  est = prepara({ rpc: { correo_smtp_guarda_candidato: err('P0001', 'demasiados_intentos') } }); r = await pideOk(BUENO);
  igual([r.status, r.cuerpo.codigo], [429, 'demasiados_intentos']); igual(A.estado.correo.transportes.length, 0, 'frenado ANTES de probar contra el servidor');
  est = prepara({ rpc: { correo_smtp_guarda_candidato: err('22023', 'host_no_valido') } }); r = await pideOk(BUENO); igual([r.status, r.cuerpo.codigo], [400, 'host_no_valido'], 'la base también valida');
  est = prepara({ rpc: { correo_smtp_guarda_candidato: err('42501', '') } }); r = await pideOk(BUENO); igual([r.status, r.cuerpo.codigo], [403, 'no_super_admin']);
  est = prepara({ rpc: { correo_smtp_guarda_candidato: err('XX000', '', 500) } }); r = await pideOk(BUENO); igual([r.status, r.cuerpo.codigo], [502, 'base_no_responde']);
  est = prepara({ rpc: { correo_smtp_guarda_candidato: () => ({ status: 200, cuerpo: { token: 'no-es-un-uuid' } }) } }); r = await pideOk(BUENO); igual(r.status, 502, 'un token raro no se usa');
  est = prepara({ rpc: { correo_smtp_promueve: err('22023', 'candidato_no_vigente') } }); r = await pideOk(BUENO); igual([r.status, r.cuerpo.codigo], [409, 'prueba_caducada']);
  est = prepara({ rpc: { correo_smtp_promueve: err('XX000', '', 500) } }); r = await pideOk(BUENO); igual([r.status, r.cuerpo.codigo], [502, 'base_no_responde'], 'si no se puede guardar, no se dice que se guardó');
  est = prepara({ rpc: { correo_smtp_promueve: () => ({ status: 200, cuerpo: { codigo_no_valido: true } }) } }); r = await pideOk(BUENO);
  igual([r.status, r.cuerpo.codigo], [403, 'codigo_no_valido'], 'si al promover el código ya no vale (caducó durante la prueba), no se guarda y se dice igual que siempre');
  est = prepara({ rpc: { correo_smtp_lee: err('XX000', '', 500) } }); r = await pideOk(BUENO);
  igual([r.status, r.cuerpo.codigo], [502, 'base_no_responde'], 'un fallo al leer el servidor actual NO se toma por «no hay ninguno»'); igual(A.estado.correo.transportes.length, 0);
  est = prepara({ rpcLanza: 'correo_smtp_lee' }); r = await pideOk(BUENO); igual(r.status, 502, 'la red caída tampoco');
  for (const x of todos.respuestas) ok(!x.includes('detalle interno'), 'ningún mensaje interno de la base llega al navegador');

  // ── 10. pedir_codigo: el código llega a la SESIÓN, solo se guarda su HMAC, y nada del código sale por otro lado ─────────────────
  const crypto = require('crypto');
  const { accion: _a, ...SERVIDOR } = BUENO;   // los campos del servidor, sin la acción
  const pedirServidor = (extra = {}) => ({ accion: 'pedir_codigo', alcance: 'servidor', ...SERVIDOR, ...extra });
  est = prepara();
  r = await pide(pedirServidor({ to: 'otro@fraude.ru', email: 'otro@fraude.ru' }), { ...BEARER, 'cf-connecting-ip': '203.0.113.9', 'x-forwarded-for': '198.51.100.7, 10.0.0.1' });
  igual(r.status, 200, JSON.stringify(r.cuerpo));
  igual(r.cuerpo, { ok: true, codigo: 'codigo_enviado', caduca_en: 600, correo_enmascarado: 'a***@ejemplo.com' }, 'al navegador solo el aviso de que salió, la caducidad y el correo enmascarado');
  let kk = codigoDelCorreo(); ok(kk && /^\d{6}$/.test(kk.codigo), 'el código tiene 6 cifras');
  igual([kk.correo.to, kk.correo._host], [EMAIL, 'smtp.falso.test'], 'va al correo de la SESIÓN, no al del cuerpo, por el servidor disponible (aquí el de entorno)');
  ok(kk.correo.text.includes('smtp.proveedor.com') && kk.correo.text.includes('buzon@ejemplo.com') && !kk.correo.text.includes(SECRETO), 'dice qué se cambia (host y usuario) y nunca la contraseña');
  ok(kk.correo.text.includes('203.0.113.9') && /Cuándo: \d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ/.test(kk.correo.text), 'lleva la IP y la hora');
  ok(!kk.correo.text.includes('198.51.100.7'), 'la IP sale solo de cf-connecting-ip: x-forwarded-for lo escribe el cliente y no se mira');
  A.estado.correo.correos.splice(0); est = prepara();
  r = await pide(pedirServidor(), { ...BEARER, 'x-forwarded-for': '198.51.100.7' }); kk = codigoDelCorreo();
  ok(/Desde la IP: desconocida/.test(kk.correo.text) && !kk.correo.text.includes('198.51.100.7'), 'sin cf-connecting-ip: «desconocida», nunca la de x-forwarded-for');
  A.estado.correo.correos.splice(0); est = prepara(); r = await pide(pedirServidor(), { ...BEARER, 'cf-connecting-ip': '203.0.113.9 <script>' }); kk = codigoDelCorreo();
  ok(/Desde la IP: desconocida/.test(kk.correo.text), 'una IP con basura tampoco se copia');
  // lo que escribe el usuario va LITERAL al correo: solo caracteres de buzón o de nombre DNS, 80 como máximo (no puede añadir frases al código ni al aviso a los demás)
  A.estado.correo.correos.splice(0); est = prepara();
  r = await pide(pedirServidor({ user: 'buzon@ejemplo.com Ignora esto y llama al 600 123 456 (urgente: https://fraude.ru)' })); kk = codigoDelCorreo();
  igual(r.status, 200, JSON.stringify(r.cuerpo));
  ok(kk.correo.text.includes('(usuario buzon@ejemplo.comIgnoraestoyllamaal600123456urgentehttpsfraude.ru)') && !/Ignora esto|llama al|urgente:|https:\/\//.test(kk.correo.text), 'el usuario con texto libre sale filtrado en el correo del código');
  A.estado.correo.correos.splice(0); est = prepara();
  r = await pide(pedirServidor({ user: 'u'.repeat(200) + '@ejemplo.com' })); kk = codigoDelCorreo();
  ok(kk.correo.text.includes('(usuario ' + 'u'.repeat(80) + ')') && !kk.correo.text.includes('u'.repeat(81)), 'y recortado a 80 caracteres'); ok(/10 minutos/.test(kk.correo.text) && /una sola vez/.test(kk.correo.text));
  ok(!r.crudo.includes(kk.codigo) && r.logs.every((x) => !x.includes(kk.codigo)), 'el código no sale por la respuesta ni por el log');
  igual(cods(est), ['correo_codigo_emite']); const em = est.cod.emisiones[0];
  igual([em.p_actor, em.p_alcance], [A.UID, 'servidor']);
  ok(/^\\x[0-9a-f]{64}$/.test(em.p_huella) && /^\\x[0-9a-f]{64}$/.test(em.p_hash), 'huella y hash: 32 bytes en bytea');
  ok(!JSON.stringify(est.rpcs).includes(kk.codigo), 'el código en claro nunca viaja a la base');
  const hashEsperado = (huella, codigo, pepper = PEPPER) => '\\x' + crypto.createHmac('sha256', pepper).update(JSON.stringify(['codigo/v1', huella.slice(2), codigo])).digest('hex');
  igual(em.p_hash, hashEsperado(em.p_huella, kk.codigo), 'el hash es el HMAC-SHA256 con el pepper (que no está en la base)');
  ok(em.p_hash !== hashEsperado(em.p_huella, kk.codigo, 'otro-pepper-distinto-0123456789abcdef'), 'con otro pepper no sale el mismo hash: sin el pepper no se pueden probar los 10^6 códigos');
  ok(em.p_hash !== '\\x' + crypto.createHash('sha256').update(kk.codigo).digest('hex'), 'no es un hash sin pepper');
  // la huella cambia con cualquier campo del cambio; el mismo cambio, la misma huella
  const huellaDe = async (parche) => { A.estado.correo.correos.splice(0); const e2 = prepara(); await pide(pedirServidor(parche)); return e2.cod.emisiones[0] && e2.cod.emisiones[0].p_huella; };
  const base = await huellaDe({}); ok(base, 'huella base');
  for (const parche of [{ host: 'smtp.otro.com' }, { user: 'otro@ejemplo.com' }, { pass: 'otra-clave' }, { nombre: 'Otro' }]) {
    const h = await huellaDe(parche); ok(h && h !== base, 'otro valor, otra huella: ' + Object.keys(parche));
  }
  igual(await huellaDe({}), base, 'el mismo cambio, la misma huella (determinista)');
  // el servidor activo de Vault manda; si falla, el de entorno; si fallan los dos, codigo_no_enviado y la emisión no gasta cupo
  est = prepara({ activo: VIEJO }); r = await pide(pedirServidor());
  igual(r.status, 200); igual(A.estado.correo.correos[0]._host, 'smtp.viejo.com', 'el código sale por el servidor ACTIVO de Vault');
  est = prepara({ activo: VIEJO }); A.estado.correo.falloEnHost = { 'smtp.viejo.com': Object.assign(new Error('x'), { code: 'ETIMEDOUT' }) };
  r = await pide(pedirServidor());
  igual(r.status, 200); igual(A.estado.correo.correos[0]._host, 'smtp.falso.test', 'si Vault falla, por los SMTP_* del entorno');
  est = prepara({ activo: VIEJO }); { const e = Object.assign(new Error('x'), { code: 'ETIMEDOUT' }); A.estado.correo.falloEnHost = { 'smtp.viejo.com': e, 'smtp.falso.test': e }; }
  r = await pide(pedirServidor());
  igual([r.status, r.cuerpo.codigo], [502, 'codigo_no_enviado']); igual(cods(est), ['correo_codigo_emite', 'correo_codigo_retira'], 'la emisión se retira');
  igual(est.rpcs.find((x) => x.nombre === 'correo_codigo_retira').body, { p_actor: A.UID, p_id: 1 }); igual(est.cod.pend, null, 'y no queda un código pendiente que nadie recibió');
  est = prepara({ env: { SMTP_HOST: '' } }); r = await pide(pedirServidor());
  igual([r.status, r.cuerpo.codigo], [502, 'codigo_no_enviado'], 'sin ningún servidor con el que mandarlo'); igual(cods(est), [], 'ni se emite');
  // límites de emisión: 429 con su código único y al log
  for (const hint of ['demasiados_codigos', 'codigo_enfriamiento']) {
    est = prepara({ rpc: { correo_codigo_emite: () => ({ status: 400, cuerpo: { code: 'P0001', hint, message: 'detalle interno con ' + SECRETO } }) } });
    r = await pide(pedirServidor());
    igual([r.status, r.cuerpo.codigo], [429, 'demasiados_intentos'], hint); ok(r.logs.some((x) => x.includes('429')), 'el 429 va al log'); igual(A.estado.correo.correos.length, 0, 'y no sale ningún correo');
  }
  est = prepara({ rpc: { correo_codigo_emite: () => ({ status: 500, cuerpo: { code: 'XX000' } }) } }); r = await pide({ accion: 'pedir_codigo', alcance: 'ajuste', clave: 'email_reply_to', valor: 'r@ejemplo.com' }); igual([r.status, r.cuerpo.codigo], [502, 'base_no_responde']);
  est = prepara(); r = await pide(pedirServidor({ alcance: 'otra' })); igual([r.status, r.cuerpo.codigo], [400, 'alcance_no_valido']);
  est = prepara(); r = await pide({ accion: 'pedir_codigo', host: BUENO.host }); igual([r.status, r.cuerpo.codigo], [400, 'alcance_no_valido'], 'sin alcance no hay código');

  // ── 11. el código no vale sin más: ausente, malo, de otro cambio, gastado o anulado → el MISMO error ───────────────────────────
  est = prepara();
  r = await pide(pedirServidor());
  kk = codigoDelCorreo(); let bueno = kk.codigo; const malo = bueno === '000000' ? '111111' : '000000';
  A.estado.correo.correos.splice(0); est.rpcs.splice(0);
  const textos = new Set();
  for (const [que, cuerpo, fallos, llamaVerifica] of [
    ['sin código', { ...BUENO }, 0, false], ['código con letras', { ...BUENO, codigo: 'abc123' }, 0, false], ['código corto', { ...BUENO, codigo: '12345' }, 0, false],
    ['código que no es de texto', { ...BUENO, codigo: 123456 }, 0, false],
    ['código equivocado', { ...BUENO, codigo: malo }, 1, true], ['código bueno de OTRA contraseña', { ...BUENO, pass: 'otra-clave-distinta', codigo: bueno }, 2, true],
    ['código bueno de OTRO usuario', { ...BUENO, user: 'otro@ejemplo.com', codigo: bueno }, 3, true], ['código bueno de OTRO servidor', { ...BUENO, host: 'smtp.otro.com', codigo: bueno }, 4, true],
  ]) {
    est.rpcs.splice(0); r = await pide(cuerpo);
    igual([r.status, r.cuerpo.codigo], [403, 'codigo_no_valido'], que); textos.add(r.crudo);
    ok(!nombres(est).includes('correo_smtp_guarda_candidato') && !nombres(est).includes('correo_smtp_promueve'), que + ': no se guarda ni se prueba nada');
    igual(cods(est).length, llamaVerifica ? 1 : 0, que + (llamaVerifica ? ': se comprueba (y cuenta el fallo)' : ': ni se llama a la base')); igual(est.cod.fallos, fallos, que + ': contador de fallos');
    igual(A.estado.correo.correos.length, 0, que + ': no sale ningún correo');
  }
  igual(textos.size, 1, 'siempre el MISMO cuerpo de error: no se puede distinguir por qué falla');
  // (un código pedido de nuevo sustituye al anterior: los 4 fallos de arriba no se arrastran)
  r = await pide(pedirServidor()); bueno = codigoDelCorreo().codigo; A.estado.correo.correos.splice(0); est.rpcs.splice(0);
  // el código de OTRO alcance (el de servidor no sirve para un ajuste)
  r = await pide({ accion: 'guardar_ajuste', clave: 'email_reply_to', valor: 'r@ejemplo.com', codigo: bueno }); igual([r.status, r.cuerpo.codigo], [403, 'codigo_no_valido'], 'un código de servidor no sirve para un ajuste');
  // el bueno funciona UNA vez
  r = await pide({ ...BUENO, codigo: bueno }); igual(r.status, 200, JSON.stringify(r.cuerpo));
  r = await pide({ ...BUENO, codigo: bueno }); igual([r.status, r.cuerpo.codigo], [403, 'codigo_no_valido'], 'un solo uso');
  // 5 fallos lo anulan: el bueno ya no vale
  est = prepara(); r = await pide(pedirServidor());
  const buenoDos = codigoDelCorreo().codigo; const maloDos = buenoDos === '000000' ? '111111' : '000000';
  for (let i = 0; i < 5; i++) await pide({ ...BUENO, codigo: maloDos });
  igual(est.cod.pend, null, 'a los 5 fallos el código se anula'); r = await pide({ ...BUENO, codigo: buenoDos }); igual([r.status, r.cuerpo.codigo], [403, 'codigo_no_valido'], 'y el bueno ya no sirve');
  // la base no responde al comprobar: se dice, no se da por bueno
  est = prepara({ rpc: { correo_codigo_verifica: err('XX000', '', 500) } }); r = await pide({ ...BUENO, codigo: '123456' }); igual([r.status, r.cuerpo.codigo], [502, 'base_no_responde']);
  ok(!nombres(est).includes('correo_smtp_guarda_candidato'), 'ni se prueba el servidor');

  // ── 12. guardar_ajuste: las cuatro claves, solo con código, y el aviso previo ───────────────────────────────────────────────────
  const AJUSTES = [['email_from', 'soporte2@ejemplo.com'], ['email_reply_to', 'respuestas@ejemplo.com'], ['email_avisos_sistema', 'nuevo-sistema@ejemplo.com'], ['email_avisos_soporte', 'nuevo-soporte@ejemplo.com']];
  for (const [k, val] of AJUSTES) {
    est = prepara();
    r = await pideOk({ accion: 'guardar_ajuste', clave: k, valor: val });
    igual(r.status, 200, k + ' ' + JSON.stringify(r.cuerpo)); igual([r.cuerpo.guardado, r.cuerpo.cambiado, r.cuerpo.clave, r.cuerpo.aviso], [true, true, k, 'enviado'], k);
    igual(nombres(est), ['correo_smtp_lee', 'correo_ajuste_guarda'], k + ': lee el servidor de hoy y guarda por la RPC con código');
    igual(cods(est), ['correo_codigo_verifica'], k + ': se verifica antes del aviso; la RPC lo consume'); igual(est.cod.usados, 1, k + ': consumido una vez');
    const ag = est.rpcs.find((x) => x.nombre === 'correo_ajuste_guarda').body;
    igual([ag.p_actor, ag.p_clave, ag.p_valor, ag.p_motivo], [A.UID, k, val, null], k + ': el actor es el de la sesión');
    ok(/^\\x[0-9a-f]{64}$/.test(ag.p_huella) && /^\\x[0-9a-f]{64}$/.test(ag.p_hash));
    igual(A.estado.correo.correos.map((x) => x.to), ['sistema@ejemplo.com'], k + ': el aviso va al buzón de sistema de ANTES' + (k === 'email_avisos_sistema' ? ' (no al nuevo)' : ''));
    ok(A.estado.correo.correos[0].text.includes(k) && A.estado.correo.correos[0].text.includes(EMAIL), k + ': dice qué y quién');
  }
  // con otros super admin: también a ellos; sin nadie: se permite y queda anotado
  est = prepara({ otros: ['otro.super@ejemplo.com'] }); r = await pideOk({ accion: 'guardar_ajuste', clave: 'email_reply_to', valor: 'r2@ejemplo.com' });
  igual(A.estado.correo.correos.map((x) => x.to).sort(), ['otro.super@ejemplo.com', 'sistema@ejemplo.com']);
  est = prepara({ config: [['email_avisos_sistema', '']] }); r = await pideOk({ accion: 'guardar_ajuste', clave: 'email_reply_to', valor: 'r2@ejemplo.com' });
  igual([r.status, r.cuerpo.aviso], [200, 'sin_destinatario']); igual(est.rpcs.find((x) => x.nombre === 'correo_ajuste_guarda').body.p_motivo, 'sin otro destinatario de aviso', 'anotado en el registro'); igual(A.estado.correo.correos.length, 0);
  est = prepara({ otrosError: true }); r = await pideOk({ accion: 'guardar_ajuste', clave: 'email_reply_to', valor: 'r2@ejemplo.com' });
  igual([r.status, r.cuerpo.codigo], [502, 'base_no_responde'], 'si no se puede saber a quién avisar, no se cambia'); ok(!nombres(est).includes('correo_ajuste_guarda'));
  // valores: validados ANTES de pedir o gastar un código
  const invalidos = [
    [['email_from', 'ceo@banco.com'], 'from_ajeno'], [['email_from', 'no-es-correo'], 'valor_no_valido'], [['email_from', ''], 'valor_no_valido'], [['email_from', 'a@ejemplo.com\nBcc: v@y.com'], 'valor_no_valido'],
    [['email_reply_to', 'x'], 'valor_no_valido'], [['email_reply_to', 'a@x.com, b@x.com'], 'valor_no_valido'], [['email_avisos_sistema', 'x@ajeno.com'], 'buzon_ajeno'], [['email_avisos_soporte', 'x@ajeno.com'], 'buzon_ajeno'],
    [['email_avisos_soporte', ''], 'valor_no_valido'], [['email_reply_to', "o'brien@ejemplo.com"], 'valor_no_valido'], [['email_avisos_soporte', 'a!b@ejemplo.com'], 'valor_no_valido'],
    [['email_from', 'a/b@ejemplo.com'], 'valor_no_valido'], [['email_reply_to', 'a@ejemplo.c'], 'valor_no_valido'], [['email_reply_to', 'a'.repeat(65) + '@ejemplo.com'], 'valor_no_valido'],
    [['email_avisos_soporte', 'a{b}@ejemplo.com'], 'valor_no_valido'], [['marca', 'Otra marca'], 'clave_no_editable'], [['', 'x@ejemplo.com'], 'clave_no_editable'], [['zona_horaria', 'UTC'], 'clave_no_editable'],
  ];
  for (const accionMala of ['pedir_codigo', 'guardar_ajuste']) for (const [[k, val], codigo] of invalidos) {
    est = prepara(); r = await pide({ accion: accionMala, alcance: 'ajuste', clave: k, valor: val, codigo: '123456' });
    igual([r.status, r.cuerpo.codigo], [400, codigo], accionMala + ' ' + k + '=' + JSON.stringify(val)); igual(cods(est), [], 'no se pide ni se gasta un código'); igual(A.estado.correo.correos.length, 0);
  }
  est = prepara(); r = await pide({ accion: 'pedir_codigo', alcance: 'ajuste', clave: 'email_reply_to', valor: 7 }); igual([r.status, r.cuerpo.codigo], [400, 'valor_no_valido']);
  // lo que la base acepta, la edge también (mismo formato: `%`, `_`, `+` y puntos internos; local de 64)
  for (const buenoV of ['a.b+c_d%e@ejemplo.com', 'a'.repeat(64) + '@ejemplo.com', 'x@sub.ejemplo.com']) {
    est = prepara(); r = await pide({ accion: 'pedir_codigo', alcance: 'ajuste', clave: 'email_reply_to', valor: buenoV }); igual([r.status, r.cuerpo.codigo], [200, 'codigo_enviado'], buenoV.slice(0, 30));
  }
  // sin servidor en Vault y con SMTP_USER de OTRO dominio: un buzón de aviso de ese dominio NO es propio para la base (solo mira Vault) → la edge lo rechaza ANTES de gastar el código ni avisar a nadie
  for (const accionX of ['pedir_codigo', 'guardar_ajuste']) {
    est = prepara({ env: { SMTP_USER: 'envios@del-entorno.test' }, otros: ['otro.super@ejemplo.com'] });
    r = await pide({ accion: accionX, alcance: 'ajuste', clave: 'email_avisos_sistema', valor: 'avisos@del-entorno.test', codigo: '123456' });
    igual([r.status, r.cuerpo.codigo], [400, 'buzon_ajeno'], accionX + ': el usuario SMTP de entorno no hace propio un buzón de aviso'); igual(cods(est), [], 'ni se emite ni se verifica un código'); igual(A.estado.correo.correos.length, 0, 'ni se avisa a nadie');
  }
  est = prepara({ activo: { host: 'smtp.viejo.com', user: 'viejo@del-vault.test', pass: 'clave-vieja-12345', nombre: null } });
  r = await pide({ accion: 'pedir_codigo', alcance: 'ajuste', clave: 'email_avisos_soporte', valor: 'soporte@del-vault.test' }); igual([r.status, r.cuerpo.codigo], [200, 'codigo_enviado'], 'con el servidor de Vault sí');
  // vaciar «responder a» sí se puede
  est = prepara({ config: [['email_reply_to', 'hola@ejemplo.com']] }); r = await pideOk({ accion: 'guardar_ajuste', clave: 'email_reply_to', valor: '' });
  igual([r.status, r.cuerpo.cambiado], [200, true]); igual(est.rpcs.find((x) => x.nombre === 'correo_ajuste_guarda').body.p_valor, '');
  // mismo valor que el actual: no hay nada que confirmar
  est = prepara({ config: [['email_reply_to', 'hola@ejemplo.com']] }); r = await pide({ accion: 'pedir_codigo', alcance: 'ajuste', clave: 'email_reply_to', valor: 'hola@ejemplo.com' });
  igual([r.status, r.cuerpo.codigo, cods(est).length], [400, 'sin_cambios', 0]);
  est = prepara({ config: [['email_reply_to', 'hola@ejemplo.com']] }); r = await pide({ accion: 'guardar_ajuste', clave: 'email_reply_to', valor: 'hola@ejemplo.com', codigo: '123456' });
  igual([r.status, r.cuerpo.cambiado, r.cuerpo.aviso], [200, false, 'no_aplica']); igual(nombres(est).concat(cods(est)).filter((x) => x !== 'correo_smtp_lee'), [], 'no escribe ni gasta el código');
  // el código es del cambio EXACTO: pedido para un valor, no sirve para otro
  est = prepara(); r = await pide({ accion: 'pedir_codigo', alcance: 'ajuste', clave: 'email_reply_to', valor: 'a@ejemplo.com' }); kk = codigoDelCorreo(); A.estado.correo.correos.splice(0); est.rpcs.splice(0);
  r = await pide({ accion: 'guardar_ajuste', clave: 'email_reply_to', valor: 'b@ejemplo.com', codigo: kk.codigo }); igual([r.status, r.cuerpo.codigo], [403, 'codigo_no_valido'], 'otro valor');
  r = await pide({ accion: 'guardar_ajuste', clave: 'email_avisos_soporte', valor: 'a@ejemplo.com', codigo: kk.codigo }); igual([r.status, r.cuerpo.codigo], [403, 'codigo_no_valido'], 'otra clave');
  ok(!nombres(est).includes('correo_ajuste_guarda') && A.estado.correo.correos.length === 0, 'no se guarda ni se avisa');
  r = await pide({ accion: 'guardar_ajuste', clave: 'email_reply_to', valor: 'a@ejemplo.com' }); igual([r.status, r.cuerpo.codigo], [403, 'codigo_no_valido'], 'sin código');
  r = await pide({ accion: 'guardar_ajuste', clave: 'email_reply_to', valor: 'a@ejemplo.com', codigo: kk.codigo }); igual([r.status, r.cuerpo.guardado], [200, true], 'el bueno, con el valor exacto');
  r = await pide({ accion: 'guardar_ajuste', clave: 'email_reply_to', valor: 'a@ejemplo.com', codigo: kk.codigo }); igual([r.status, r.cuerpo.codigo], [403, 'codigo_no_valido'], 'y una sola vez');
  // carrera: la verificación pasó pero al consumir ya no vale → mismo error y no se guarda
  est = prepara({ rpc: { correo_ajuste_guarda: () => ({ status: 200, cuerpo: { codigo_no_valido: true } }) } }); r = await pideOk({ accion: 'guardar_ajuste', clave: 'email_reply_to', valor: 'a@ejemplo.com' });
  igual([r.status, r.cuerpo.codigo], [403, 'codigo_no_valido']);
  // errores de la RPC: validación de la base → código; lo demás → 502 sin filtrar
  est = prepara({ rpc: { correo_ajuste_guarda: err('22023', 'buzon_ajeno') } }); r = await pideOk({ accion: 'guardar_ajuste', clave: 'email_reply_to', valor: 'a@ejemplo.com' }); igual([r.status, r.cuerpo.codigo], [400, 'buzon_ajeno']);
  est = prepara({ rpc: { correo_ajuste_guarda: err('42501', '') } }); r = await pideOk({ accion: 'guardar_ajuste', clave: 'email_reply_to', valor: 'a@ejemplo.com' }); igual([r.status, r.cuerpo.codigo], [403, 'no_super_admin']);
  est = prepara({ rpc: { correo_ajuste_guarda: err('XX000', '', 500) } }); r = await pideOk({ accion: 'guardar_ajuste', clave: 'email_reply_to', valor: 'a@ejemplo.com' }); igual([r.status, r.cuerpo.codigo], [502, 'base_no_responde']);
  for (const x of todos.respuestas) ok(!x.includes('detalle interno'), 'ningún mensaje interno de la base llega al navegador');
  // un no super admin no llega a nada de esto
  est = prepara({ super: false }); r = await pide({ accion: 'pedir_codigo', alcance: 'ajuste', clave: 'email_reply_to', valor: 'a@ejemplo.com' }); igual([r.status, r.cuerpo.codigo, est.rpcs.length], [403, 'no_super_admin', 0]);
  est = prepara({ super: false }); r = await pide({ accion: 'guardar_ajuste', clave: 'email_reply_to', valor: 'a@ejemplo.com', codigo: '123456' }); igual([r.status, r.cuerpo.codigo, est.rpcs.length], [403, 'no_super_admin', 0]);

  // ── 13. sin pepper no hay modo «sin código»: 503 en las tres acciones, sin tocar la base ni mandar nada ───────────────────────────
  for (const [sinPepper, env] of [[true, undefined], [false, { CORREO_CODIGO_PEPPER: 'corto' }], [false, { CORREO_CODIGO_PEPPER: 'a'.repeat(64) }], [false, { CORREO_CODIGO_PEPPER: 'ab'.repeat(32) }],
                                  [false, { CORREO_CODIGO_PEPPER: '0123456'.repeat(6) }]]) {   // 6 caracteres distintos (<8): poca variedad
    for (const cuerpo of [BUENO, pedirServidor(), { accion: 'guardar_ajuste', clave: 'email_reply_to', valor: 'a@ejemplo.com', codigo: '123456' }]) {
      est = prepara({ sinPepper, env }); r = await pide(cuerpo);
      igual([r.status, r.cuerpo.codigo], [503, 'codigo_no_disponible'], cuerpo.accion + (sinPepper ? ' sin pepper' : ' con pepper ' + (env && env.CORREO_CODIGO_PEPPER.slice(0, 7)))); igual(est.rpcs.length, 0); igual(A.estado.correo.correos.length, 0); igual(A.estado.correo.transportes.length, 0);
    }
  }
  est = prepara({ sinPepper: true }); r = await pide({ accion: 'estado' }); igual([r.status, r.cuerpo.pide_codigo], [200, false], 'el estado dice si la confirmación está disponible');
  est = prepara({ env: { CORREO_CODIGO_PEPPER: 'a'.repeat(64) } }); r = await pide({ accion: 'estado' }); igual(r.cuerpo.pide_codigo, false, 'un pepper de un solo carácter repetido no cuenta');
  est = prepara({ env: { CORREO_CODIGO_PEPPER: crypto.randomBytes(32).toString('hex') } }); r = await pide({ accion: 'estado' }); igual(r.cuerpo.pide_codigo, true, 'un hex aleatorio de 32 bytes sí');
  est = prepara(); r = await pide({ accion: 'estado' }); igual(r.cuerpo.pide_codigo, true);

  // ── 13b. PostgREST contesta cuerpo VACÍO cuando la función devuelve NULL (correo_smtp_lee sin servidor en Vault): es un NULL, no un error ──────────
  est = prepara({ rpc: { correo_smtp_lee: () => ({ status: 200, cuerpo: undefined }) } });
  r = await pide(pedirServidor()); igual([r.status, r.cuerpo.codigo], [200, 'codigo_enviado'], 'pedir_codigo con lee() vacío → entorno');
  est = prepara({ rpc: { correo_smtp_lee: () => ({ status: 200, cuerpo: undefined }) } });
  r = await pideOk({ accion: 'guardar_ajuste', clave: 'email_reply_to', valor: 'r3@ejemplo.com' }); igual([r.status, r.cuerpo.guardado], [200, true], 'guardar_ajuste con lee() vacío');
  est = prepara({ rpc: { correo_smtp_lee: () => ({ status: 200, cuerpo: undefined }) } });
  r = await pideOk(BUENO); igual([r.status, r.cuerpo.guardado], [200, true], 'probar_y_guardar con lee() vacío (primera carga)');

  // ── 14. barrida: la contraseña y NINGÚN código aparecen en ningún log ni respuesta de toda la prueba ──────────────────────────────
  ok(todos.logs.length > 100 && todos.respuestas.length > 100, 'la barrida tiene materia');
  ok(todos.logs.every((x) => !x.includes(SECRETO)), 'ninguna línea de log lleva la contraseña');
  ok(todos.respuestas.every((x) => !x.includes(SECRETO)), 'ninguna respuesta lleva la contraseña');
  ok(codigosVistos.length > 20, 'se vieron muchos códigos');
  for (const k of new Set(codigosVistos)) {
    ok(todos.logs.every((x) => !x.includes(k)), 'ningún log lleva el código ' + k);
    ok(todos.respuestas.every((x) => !x.includes(k)), 'ninguna respuesta lleva el código ' + k);
  }

  console.log(`OK ajustes_correo.test.js — super admin activo solo · código de 6 cifras por correo a la sesión (HMAC con pepper, atado al cambio exacto, un solo uso, 5 fallos lo anulan, un único error) · sin pepper 503 · prueba al usuario autenticado · promueve solo tras el envío · sin contraseña ni texto del servidor · host público · aviso a los demás super admin por el servidor de hoy y reautenticación · pausa · CORS · ${n} comprobaciones`);
})().catch((e) => { console.error(e); process.exit(1); });
