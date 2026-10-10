// portal-acceso — entrada de autoservicio al portal del comprador (8-sep-2026).
//
// Hermana de `portal-invitar`, no una acción suya, porque el modelo de
// autorización es el contrario: `portal-invitar` decide con el JWT de un admin
// de la suite; ésta se llama SIN sesión (quien entra al portal todavía no tiene
// cuenta). Colgar una acción sin autenticar de la función que autoriza por JWT
// es la clase de mezcla que acaba abriendo la que no tocaba.
//
// Qué hace: pregunta a `portal_autoservicio()` si a ese correo le corresponde
// el portal (ficha de comprador con contrato, no del equipo, no revocado). Si
// sí, se asegura de que exista la cuenta de Auth con `app_metadata.portal` y le
// manda el enlace de entrada. La REGLA vive en SQL, aquí solo lo que exige
// service_role.
//
// LAW-1 (11-oct-2026, encargos/20261011_lawang_portal_enlace_por_correo.md de la
// agencia, revisión previa #261 Backend + Seguridad): el enlace ya NO lo manda el
// correo gratuito de Supabase (~4/h: de 44 compradores con acceso solo había
// entrado 1). Ahora:
//   · el enlace se genera con `auth.admin.generateLink({type:'magiclink'})` y se
//     manda por `envia-correo` (el buzón de Lawang de Ajustes) por la vía de
//     servicio `X-Render-Secret`, como alta-colaborador. Ese secreto permite
//     mandar cualquier correo a cualquiera, así que destinatario, asunto, texto y
//     botón se fijan AQUÍ: de la petición solo se toma `email`, y solo se manda al
//     correo que ya pasó la regla. Nunca `preview`, nunca `sociedad`;
//   · el enlace es `PORTAL_URL#th=<hashed_token>` y la página lo canjea con
//     verifyOtp. En el FRAGMENTO (#) y no en `?th=` (Seguridad, consulta del
//     revisor): el fragmento no viaja al servidor, así que no queda en los logs de
//     acceso de Hostinger, del CDN ni de un proxy. El token no viaja en la
//     respuesta ni en ningún log;
//   · freno propio (`portal_enlace_freno`, migración 20261010194801) ANTES de tocar
//     la cuenta y de generar el enlace: `generateLink` se salta el límite de GoTrue
//     y cada enlace invalida el anterior, así que repetir el formulario dejaría al
//     comprador sin poder entrar. Frenado = la misma respuesta que un correo sin
//     derecho. Si el envío falla, el hueco se devuelve. Además de 60 s y 5/h por
//     correo y el techo global de 30/h, como mucho 5 enlaces por hora desde la
//     misma IP: una sola máquina no puede invalidar el enlace de 30 compradores ni
//     agotar el global. La IP viaja a la base como HMAC (nunca en claro) y su fila
//     se purga 1 h después de su última petición. El frenazo por tope global se
//     registra con su propia línea (`frenado_tope_global`) para poder avisar;
//   · un correo con fila en `usuarios` (equipo, activa o no) no recibe enlace: el
//     enlace abre la cuenta de Auth ENTERA, no solo el portal;
//   · logs: solo el dominio del correo y códigos (nunca la dirección ni el token).
//
// ⚠️ Respuesta uniforme a propósito: un correo que no da acceso recibe
// exactamente lo mismo que uno que sí. Si contestara distinto, este formulario
// sería un buscador público de «¿quién ha comprado en Lawang?».
//
// La única excepción es `reintentar:true` cuando el envío falla de verdad, y es
// deliberada: sí, distingue a un elegible de uno que no lo es. Se acepta porque
// el fallo contrario ya ocurrió y es peor — el 8-sep había 18 invitaciones a
// compradores reales con CERO entradas, y la sospecha es que varias nunca
// salieron (SMTP por defecto de Supabase, ~4 correos/hora) mientras la pantalla
// decía «enviado». Decirle a alguien que revise un buzón donde no hay nada es la
// avería que estamos arreglando; no se puede reintroducir aquí.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const URL_SB = Deno.env.get('SUPABASE_URL')!;
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const admin = createClient(URL_SB, SERVICE);

const PORTAL_URL = 'https://lawangproperties.com/portal/';

// A dónde va el correo lo decide config_instancia.url_envio_correo (interruptor único, AXW-124), y solo valen estas dos
// URL exactas: una clave manipulada no puede sacar el secreto ni el enlace a otro host. Mismo patrón que alta-colaborador.
const ENVIO_PHP = 'https://lawangproperties.com/contracts/api/send_email.php';
const ENVIO_EDGE = URL_SB + '/functions/v1/envia-correo';
async function urlEnvio(): Promise<string> {
  try {
    const { data } = await admin.from('config_instancia').select('valor').eq('clave', 'url_envio_correo').maybeSingle();
    const u = typeof data?.valor === 'string' ? data.valor.trim() : '';
    if (u === ENVIO_EDGE || u === ENVIO_PHP) return u;
  } catch (_) { /* cae al PHP */ }
  return ENVIO_PHP;
}

const ASUNTO = 'Your Lawang client portal link · Tu enlace al portal de Lawang';
const TEXTO =
  'Hello,\n\n'
  + 'Use the button below to sign in to your Lawang client portal. The link works only once and expires soon; '
  + 'if it has expired, request a new one from the portal page.\n\n'
  + 'If you did not ask for this email, you can ignore it: nobody can sign in without opening this message.\n\n'
  + '—\n\n'
  + 'Hola:\n\n'
  + 'Usa el botón para entrar a tu portal de cliente de Lawang. El enlace sirve una sola vez y caduca pronto; '
  + 'si ha caducado, pide otro desde la página del portal.\n\n'
  + 'Si no has pedido este correo, puedes ignorarlo: nadie puede entrar sin abrir este mensaje.';
const CTA_TEXTO = 'Sign in · Entrar al portal';

const ORIGENES = [
  'https://lawangproperties.com',
  'https://www.lawangproperties.com',
  'https://sumbahills.lawangproperties.com',
];
const corsFor = (req: Request) => {
  const o = req.headers.get('origin') ?? '';
  const ok = ORIGENES.includes(o) || /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(o);
  return {
    'Access-Control-Allow-Origin': ok ? o : ORIGENES[0],
    'Access-Control-Allow-Headers': 'content-type, authorization, apikey',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    Vary: 'Origin',
  };
};

/** Solo el dominio: la dirección completa no va a los logs (LAW-1). */
const dominio = (email: string) => { const i = email.lastIndexOf('@'); return i > 0 ? email.slice(i + 1) : '?'; };
/** Texto de error para el log sin direcciones de correo ni cadenas largas (un token, una URL con token). */
const limpia = (s: unknown) => String(s ?? '').replace(/[^\s@<>]+@[^\s@<>]+/g, '[correo]').replace(/[A-Za-z0-9_\-]{24,}/g, '[…]').slice(0, 120);

/** IP de quien llama, como alta-colaborador: cf-connecting-ip la pone el proxy y el cliente no la puede falsear; si falta,
 *  la ÚLTIMA entrada de x-forwarded-for (la añade el proxy), nunca la primera. '' si no hay ninguna. */
function ipDe(req: Request): string {
  const xff = (req.headers.get('x-forwarded-for') ?? '').split(',').map((x) => x.trim()).filter(Boolean);
  return ((req.headers.get('cf-connecting-ip') ?? '').trim() || xff[xff.length - 1] || '').slice(0, 64);
}
/** HMAC-SHA256 de la IP, en hex (64). Clave = la service_role de la edge, con etiqueta propia: un sha256 sin clave de una
 *  IPv4 se deshace probando las ~4.300 millones de IPs. Si la clave rota, solo se reinician los contadores. null sin IP. */
async function hashIp(ip: string): Promise<string | null> {
  if (!ip) return null;
  const enc = new TextEncoder();
  const k = await crypto.subtle.importKey('raw', enc.encode(SERVICE), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const firma = new Uint8Array(await crypto.subtle.sign('HMAC', k, enc.encode('lawang-portal-acceso-ip:' + ip)));
  return Array.from(firma, (b) => b.toString(16).padStart(2, '0')).join('');
}

/** Manda el enlace por envia-correo (o el PHP), con destinatario y textos fijados aquí. true solo si respondió ok. */
async function enviaEnlace(email: string, enlace: string): Promise<boolean> {
  const url = await urlEnvio();
  // La edge exige su secreto de entrada propio (ENVIO_CORREO_SECRET); el PHP solo conoce RENDER_SECRET.
  const secreto = url === ENVIO_EDGE ? (Deno.env.get('ENVIO_CORREO_SECRET') || Deno.env.get('RENDER_SECRET') || '') : (Deno.env.get('RENDER_SECRET') || '');
  if (!secreto) { console.error('portal-acceso envio sin_secreto @' + dominio(email)); return false; }
  const ac = new AbortController();
  const t = setTimeout(() => ac.abort(), 8000);
  try {
    const r = await fetch(url, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'X-Render-Secret': secreto, 'X-Llamante': 'portal-acceso' },
      // attach:false: sin él el destino exige PDF. cta_url + cta_texto: van juntos o el destino da 400.
      body: JSON.stringify({ to: email, subject: ASUNTO, message: TEXTO, attach: false, cta_url: enlace, cta_texto: CTA_TEXTO }),
      signal: ac.signal,
    });
    const cuerpo = await r.text().catch(() => '');
    const ok = r.ok && cuerpo.includes('"ok":true');
    if (!ok) console.error('portal-acceso envio http_' + r.status + ' @' + dominio(email));
    return ok;
  } catch (e) {
    console.error('portal-acceso envio excepcion @' + dominio(email) + ': ' + limpia((e as Error)?.name ?? e));
    return false;
  } finally {
    clearTimeout(t);
  }
}

export async function manejador(req: Request): Promise<Response> {
  const cors = corsFor(req);
  const json = (o: unknown, s = 200) =>
    new Response(JSON.stringify(o), { status: s, headers: { ...cors, 'content-type': 'application/json' } });

  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'metodo' }, 405);

  let email = '';
  let ipHash: string | null = null;
  let reservado = false;   // true = el freno ya anotó este envío (si no sale, se devuelve el hueco)
  const libera = async () => {
    if (!reservado) return;
    reservado = false;
    const { error } = await admin.rpc('portal_enlace_freno', { p_email: email, p_origen: 'autoservicio', p_ip_hash: ipHash, p_libera: true });
    if (error) console.error('portal-acceso freno_libera_fallo @' + dominio(email) + ': ' + limpia(error.code ?? error.message));
  };
  try {
    const body = await req.json().catch(() => ({}));
    email = String(body.email ?? '').trim().toLowerCase().slice(0, 320);

    // El motivo real solo viaja al log: es lo único que permite auditar por qué
    // alguien no entró, sin decírselo a quien pregunta desde fuera.
    const anota = (m: string) => console.log('portal-acceso ' + m + ' @' + dominio(email));

    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      console.log('portal-acceso email_invalido');
      return json({ ok: true });
    }

    const { data: veredicto, error: eRpc } = await admin.rpc('portal_autoservicio', { p_email: email });
    if (eRpc) {
      console.error('portal-acceso rpc_fallo @' + dominio(email) + ': ' + limpia(eRpc.code ?? eRpc.message));
      return json({ error: 'no_disponible' }, 500);
    }
    const v = (veredicto ?? {}) as { elegible?: boolean; motivo?: string; creadas?: number };
    if (!v.elegible) {
      anota('sin_derecho:' + limpia(v.motivo ?? '?'));
      return json({ ok: true });
    }
    if (v.creadas) anota('acceso_creado_por_regla:' + Number(v.creadas));

    // ── equipo: el enlace abre la cuenta de Auth entera, no solo el portal ──
    // Cualquier fila de `usuarios` (activa o no), igual que portal-invitar.
    const { data: equipo, error: eEquipo } = await admin.from('usuarios').select('user_id').eq('email', email).limit(1);
    if (eEquipo) {
      console.error('portal-acceso equipo_fallo @' + dominio(email) + ': ' + limpia(eEquipo.code ?? eEquipo.message));
      return json({ error: 'no_disponible' }, 500);
    }
    if ((equipo ?? []).length) {
      anota('es_del_equipo');
      return json({ ok: true });
    }

    // ── freno: antes de tocar la cuenta y de generar el enlace ──────────
    // Por correo (60 s, 5/h), por IP (5/h) y techo global (30/h), todo en la misma llamada y con el mismo candado.
    // Sin IP legible (no debería pasar detrás del proxy de Supabase) no se inventa un cubo común: cuenta el correo y el
    // global, y queda en el log.
    ipHash = await hashIp(ipDe(req));
    if (!ipHash) anota('sin_ip');
    const { data: motivo, error: eFreno } = await admin.rpc('portal_enlace_freno', { p_email: email, p_origen: 'autoservicio', p_ip_hash: ipHash });
    if (eFreno) {
      console.error('portal-acceso freno_fallo @' + dominio(email) + ': ' + limpia(eFreno.code ?? eFreno.message));
      return json({ error: 'no_disponible' }, 500);
    }
    if (motivo !== 'pasa') {
      const m = ['correo', 'ip', 'global', 'invalido'].includes(String(motivo)) ? String(motivo) : 'desconocido';
      anota('frenado:' + m);
      // Línea fija para avisar: 30 enlaces en una hora desde el formulario = alguien martillea o el techo se queda corto.
      if (m === 'global') console.warn('portal-acceso frenado_tope_global');
      return json({ ok: true });
    }
    reservado = true;

    // ── la cuenta de Auth ────────────────────────────────────────────────
    // Mismo paginado de 1000 que portal-invitar: sobra con los volúmenes de la
    // promotora, y si algún día no sobra hay que cambiarlo en los DOS sitios.
    const { data: lista, error: eLista } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
    if (eLista) {
      console.error('portal-acceso listUsers @' + dominio(email) + ': ' + limpia(eLista.message));
      await libera();
      return json({ error: 'no_disponible' }, 500);
    }
    let user = (lista?.users ?? []).find((u) => (u.email ?? '').toLowerCase() === email) ?? null;

    // Equipo también por la CUENTA, no solo por el correo: una cuenta del equipo cuyo correo de `usuarios` no coincide con el
    // de Auth (medido el 11-oct-2026: 1 caso real) pasaba el filtro por correo y habría recibido el claim y un enlace a su
    // cuenta entera. Antes de tocar el claim y de generar nada.
    if (user) {
      const { data: delEquipo, error: eUid } = await admin.from('usuarios').select('user_id').eq('user_id', user.id).limit(1);
      if (eUid) {
        console.error('portal-acceso equipo_uid_fallo @' + dominio(email) + ': ' + limpia(eUid.code ?? eUid.message));
        await libera();
        return json({ error: 'no_disponible' }, 500);
      }
      if ((delEquipo ?? []).length) {
        anota('es_del_equipo');
        await libera();
        return json({ ok: true });
      }
    }

    if (!user) {
      const { data: creado, error: eCrear } = await admin.auth.admin.createUser({
        email, email_confirm: true,
        app_metadata: { portal: true },
      });
      if (eCrear || !creado?.user) {
        console.error('portal-acceso createUser @' + dominio(email) + ': ' + limpia(eCrear?.message ?? 'sin usuario'));
        await libera();
        return json({ error: 'no_disponible' }, 500);
      }
      user = creado.user;
      anota('cuenta_creada');
    } else if (!(user.app_metadata as Record<string, unknown> | null)?.portal) {
      // Existe la cuenta pero sin el claim: sin él, `es_portal()` es false y el
      // portal se abriría vacío. Solo llega aquí quien ya pasó el filtro de la
      // regla, así que ponérselo no amplía a nadie.
      const { error: eMeta } = await admin.auth.admin.updateUserById(user.id, {
        app_metadata: { ...(user.app_metadata ?? {}), portal: true },
      });
      if (eMeta) {
        console.error('portal-acceso claim @' + dominio(email) + ': ' + limpia(eMeta.message));
        await libera();
        return json({ error: 'no_disponible' }, 500);
      }
      anota('claim_puesto');
    }

    // ── el enlace ────────────────────────────────────────────────────────
    // La cuenta ya existe (arriba): `generateLink` se llama solo sobre ella y se
    // comprueba que devuelve ESE usuario; si no, no se manda nada. Ni `data` ni
    // `action_link` se registran nunca.
    const { data: link, error: eLink } = await admin.auth.admin.generateLink({ type: 'magiclink', email });
    const th = link?.properties?.hashed_token;
    if (eLink || !th || link?.user?.id !== user.id) {
      console.error('portal-acceso generateLink_fallo @' + dominio(email) + ': ' + limpia(eLink?.code ?? eLink?.status ?? (th ? 'otro_usuario' : 'sin_token')));
      await libera();
      return json({ ok: true, reintentar: true });
    }
    const enviado = await enviaEnlace(email, PORTAL_URL + '#th=' + encodeURIComponent(th));
    if (!enviado) {
      await libera();
      return json({ ok: true, reintentar: true });
    }
    anota('enlace_enviado');
    return json({ ok: true });
  } catch (e) {
    console.error('portal-acceso excepcion @' + dominio(email) + ': ' + limpia((e as Error)?.message ?? e));
    await libera().catch(() => {});
    return json({ error: 'no_disponible' }, 500);
  }
}

Deno.serve(manejador);
