// portal-invitar — da acceso al portal del comprador, envía el enlace de
// entrada y (7-ago) permite ponerle una contraseña como alternativa al enlace.
//
// Existe porque crear el usuario de Auth, marcarle `app_metadata.portal` y
// tocar su contraseña exige `service_role`, que no puede vivir en el
// navegador. El vínculo email→fichas (portal_accesos) también se escribe aquí
// para que invitar sea UNA acción atómica, no tres pasos que alguien deja a
// medias.
//
// ⚠️ La autorización se decide SIEMPRE con el JWT de quien llama (admin de la
// suite), nunca con un campo del body. verify_jwt=false: se valida dentro para
// devolver errores legibles.
//
// LAW-1 (11-oct-2026, encargos/20261011_lawang_portal_enlace_por_correo.md de la
// agencia, revisión previa #261 Backend + Seguridad): el enlace ya NO lo manda el
// correo gratuito de Supabase (~4/h). Se genera con
// `auth.admin.generateLink({type:'magiclink'})` sobre la cuenta ya resuelta y se
// manda por `envia-correo` (buzón de Lawang) con la vía de servicio
// `X-Render-Secret`; destinatario, asunto, texto y botón fijados aquí. El enlace
// es `PORTAL_URL?th=<hashed_token>` y no viaja en la respuesta ni en los logs.
// Antes de generarlo pasa por el freno `portal_enlace_freno` (60 s y 5/h por
// correo; los de un admin no cuentan en el tope global del formulario anónimo).
// Si frena o el envío falla, el acceso queda dado y la respuesta lleva el aviso
// `acceso_creado_pero_email_no_enviado` (la pantalla dice «reenvía en un rato»).
import { createClient } from 'jsr:@supabase/supabase-js@2';

const URL_SB = Deno.env.get('SUPABASE_URL')!;
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const ANON = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
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

const ASUNTO = 'Your access to the Lawang client portal · Tu acceso al portal de Lawang';
const TEXTO =
  'Hello,\n\n'
  + 'You now have access to your Lawang client portal, where you can follow your contract, payments and documents. '
  + 'Use the button below to sign in. The link works only once and expires soon; if it has expired, request a new one '
  + 'from the portal page with this same email address.\n\n'
  + '—\n\n'
  + 'Hola:\n\n'
  + 'Ya tienes acceso a tu portal de cliente de Lawang, donde puedes seguir tu contrato, tus pagos y tus documentos. '
  + 'Usa el botón para entrar. El enlace sirve una sola vez y caduca pronto; si ha caducado, pide otro desde la página '
  + 'del portal con este mismo correo.';
const CTA_TEXTO = 'Sign in · Entrar al portal';
const AVISO_NO_ENVIADO = 'acceso_creado_pero_email_no_enviado';

/** Solo el dominio: la dirección completa no va a los logs (LAW-1). */
const dominio = (email: string) => { const i = email.lastIndexOf('@'); return i > 0 ? email.slice(i + 1) : '?'; };

/** Manda el enlace por envia-correo (o el PHP), con destinatario y textos fijados aquí. true solo si respondió ok. */
async function enviaEnlace(email: string, enlace: string): Promise<boolean> {
  const url = await urlEnvio();
  // La edge exige su secreto de entrada propio (ENVIO_CORREO_SECRET); el PHP solo conoce RENDER_SECRET.
  const secreto = url === ENVIO_EDGE ? (Deno.env.get('ENVIO_CORREO_SECRET') || Deno.env.get('RENDER_SECRET') || '') : (Deno.env.get('RENDER_SECRET') || '');
  if (!secreto) { console.error('portal-invitar envio sin_secreto @' + dominio(email)); return false; }
  const ac = new AbortController();
  const t = setTimeout(() => ac.abort(), 8000);
  try {
    const r = await fetch(url, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'X-Render-Secret': secreto, 'X-Llamante': 'portal-invitar' },
      // attach:false: sin él el destino exige PDF. cta_url + cta_texto: van juntos o el destino da 400.
      body: JSON.stringify({ to: email, subject: ASUNTO, message: TEXTO, attach: false, cta_url: enlace, cta_texto: CTA_TEXTO }),
      signal: ac.signal,
    });
    const cuerpo = await r.text().catch(() => '');
    const ok = r.ok && cuerpo.includes('"ok":true');
    if (!ok) console.error('portal-invitar envio http_' + r.status + ' @' + dominio(email));
    return ok;
  } catch (e) {
    console.error('portal-invitar envio excepcion @' + dominio(email) + ': ' + String((e as Error)?.name ?? 'error').slice(0, 40));
    return false;
  } finally {
    clearTimeout(t);
  }
}

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

export async function manejador(req: Request): Promise<Response> {
  const cors = corsFor(req);
  // Un rechazo que solo viaja al navegador no existe: el 5-ago hubo cuatro 400
  // seguidos y en los logs solo constaba el código, así que no se pudo saber
  // POR QUÉ. Ahora cada salida distinta de 200 deja su motivo en el log.
  const json = (o: unknown, s = 200) => {
    // LAW-1: sin direcciones de correo en el log (un mensaje de Auth o de la base podría citar una).
    if (s !== 200) console.error('portal-invitar ' + s + ': ' + JSON.stringify(o).replace(/[^\s@"<>]+@[^\s@"<>]+/g, '[correo]'));
    return new Response(JSON.stringify(o), { status: s, headers: { ...cors, 'content-type': 'application/json' } });
  };
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'metodo' }, 405);

  try {
    // ── quién llama: un admin ACTIVO de la suite ─────────────────────────
    const jwt = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '');
    if (!jwt) return json({ error: 'sin_sesion' }, 401);
    const { data: quien, error: eUser } = await admin.auth.getUser(jwt);
    if (eUser || !quien?.user) return json({ error: 'sesion_invalida' }, 401);
    const { data: ficha, error: eFicha } = await admin
      .from('usuarios').select('rol, activo, herramientas').eq('user_id', quien.user.id).maybeSingle();
    if (eFicha) return json({ error: 'no_se_pudo_comprobar_permiso' }, 500);
    // 7-oct-2026 (empresas): entran tambien los roles de empresa; que fichas puede tocar cada uno
    // lo decide la base (portal_puede_gestionar), no esta lista.
    if (!ficha || !ficha.activo || !['super_admin', 'admin', 'admin_empresa', 'super_admin_empresa'].includes(ficha.rol))
      return json({ error: 'no_autorizado' }, 403);
    // 26-sep-2026 (revisión de las edges con service_role): ser admin no basta. El portal
    // se da desde «Compradores», y desde el 18-ago los admin van limitados por sus
    // herramientas; esta función se salta la RLS, así que sin esto era la puerta de
    // servicio para dar acceso a fichas que el admin no tiene ni en su pantalla.
    if (ficha.rol !== 'super_admin' && !(ficha.herramientas ?? []).includes('compradores'))
      return json({ error: 'no_autorizado: te falta la herramienta «compradores»' }, 403);
    // Cliente CON LA SESIÓN de quien llama: lo que puede ver lo decide la RLS de `clients`,
    // igual que en su pantalla (mismo patrón que send-contract-email, rev. previa #106).
    const usuario = createClient(URL_SB, ANON, {
      global: { headers: { Authorization: 'Bearer ' + jwt } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    // true si quien llama ve TODAS esas fichas; nunca se vincula ni se toca lo que no ve
    // 7-oct-2026 (empresas): ademas de verlas, un rol de empresa solo gestiona fichas con contratos y TODOS
    // en sus empresas (un comprador con contratos en las dos empresas daria a su cuenta de portal
    // los de la otra). Lo decide la base con el JWT de quien llama; un administrador global pasa siempre.
    const veTodas = async (ids: string[]) => {
      const unicos = [...new Set(ids)];
      if (!unicos.length) return true;
      const { data, error } = await usuario.from('clients').select('id').in('id', unicos);
      if (error || (data ?? []).length !== unicos.length) return false;
      const { data: puede, error: eRpc } = await usuario.rpc('portal_puede_gestionar', { p_ids: unicos });
      return !eRpc && puede === true;
    };
    // Las fichas a las que YA da acceso ese email; null si no se han podido leer.
    const fichasDe = async (em: string) => {
      const { data, error } = await admin.from('portal_accesos').select('client_id').eq('email', em);
      return error ? null : (data ?? []).map((a: { client_id: string }) => a.client_id);
    };

    const body = await req.json().catch(() => ({}));
    const accion = String(body.accion ?? '');
    const email = String(body.email ?? '').trim().toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json({ error: 'email_invalido' }, 400);

    // El email podría ser de alguien del EQUIPO: esa cuenta no se convierte en
    // portal (mezclaría los dos mundos en un mismo usuario de Auth).
    // LAW-1: con limit(1) y mirando el error. Antes era maybeSingle() sin mirar el error: un fallo de la base (o dos
    // filas con el mismo correo) daba null y dejaba pasar a alguien del equipo; ahora el enlace abre la cuenta de Auth entera.
    const { data: esEquipo, error: eEquipo } = await admin.from('usuarios').select('user_id').eq('email', email).limit(1);
    if (eEquipo) return json({ error: 'no_se_pudo_comprobar_permiso' }, 500);
    if ((esEquipo ?? []).length) return json({ error: 'ese_email_es_del_equipo' }, 400);

    // ── revocar: apaga los accesos; la cuenta queda pero no ve nada ──────
    if (accion === 'revocar') {
      const fichas = await fichasDe(email);
      if (fichas === null) return json({ error: 'no_se_pudo_comprobar_permiso' }, 500);
      if (!(await veTodas(fichas))) return json({ error: 'ficha_no_visible' }, 403);
      const { error } = await admin.from('portal_accesos').update({ activo: false }).eq('email', email);
      if (error) return json({ error: error.message }, 500);
      return json({ ok: true });
    }

    // ── contraseña: alternativa al enlace mágico, no lo sustituye ────────
    // Mismo patrón que admin-usuarios (cuentas de equipo): el admin la escribe
    // y se la pasa a la persona por su cuenta; aquí nunca queda en claro.
    if (accion === 'password') {
      const password = String(body.password ?? '');
      if (password.length < 10) return json({ error: 'password_corta' }, 400);
      const { data: lista, error: eLista } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
      if (eLista) return json({ error: eLista.message }, 500);
      const user = (lista?.users ?? []).find((u) => (u.email ?? '').toLowerCase() === email) ?? null;
      if (!user || !(user.app_metadata as Record<string, unknown> | null)?.portal)
        return json({ error: 'no_es_cuenta_de_portal' }, 400);
      // Poner contraseña es quedarse con la cuenta: solo sobre un comprador que YA tiene
      // fichas y todas las ves. Sin fichas no hay dueño todavía: ponerle clave a una cuenta
      // vacía y esperar a que otro la invite era apoderarse de ella (consulta de deploy de
      // Seguridad, 26-sep-2026). Si no se pueden leer sus fichas, no.
      const fichas = await fichasDe(email);
      if (fichas === null) return json({ error: 'no_se_pudo_comprobar_permiso' }, 500);
      if (!fichas.length) return json({ error: 'sin_fichas' }, 403);
      if (!(await veTodas(fichas))) return json({ error: 'ficha_no_visible' }, 403);
      const { error } = await admin.auth.admin.updateUserById(user.id, { password });
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true });
    }

    // ── invitar / reenviar ───────────────────────────────────────────────
    if (accion !== 'invitar' && accion !== 'reenviar') return json({ error: 'accion_desconocida' }, 400);
    // Reenviar es para quien ya está invitado: sin fichas no crea ninguna cuenta de portal.
    if (accion === 'reenviar') {
      const fichas = await fichasDe(email);
      if (fichas === null) return json({ error: 'no_se_pudo_comprobar_permiso' }, 500);
      if (!fichas.length) return json({ error: 'sin_fichas' }, 403);
      if (!(await veTodas(fichas))) return json({ error: 'ficha_no_visible' }, 403);
    }

    // 7-oct-2026 (revision de codigo): las fichas de una invitacion se comprueban ANTES de crear o
    // marcar la cuenta de Auth; un 403 ya no deja una cuenta de portal a medias.
    const idsInvitar: string[] = accion === 'invitar' && Array.isArray(body.client_ids) ? body.client_ids.map(String) : [];
    if (accion === 'invitar') {
      if (!idsInvitar.length) return json({ error: 'sin_fichas' }, 400);
      if (!(await veTodas(idsInvitar))) return json({ error: 'ficha_no_visible' }, 403);
    }

    // ¿existe ya el usuario de Auth?
    // ponytail: listUsers pagina de 1000 — sobra con los volúmenes de la
    // promotora; si algún día hay miles de compradores, cambiar a una búsqueda.
    const { data: lista, error: eLista } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
    if (eLista) return json({ error: eLista.message }, 500);
    let user = (lista?.users ?? []).find((u) => (u.email ?? '').toLowerCase() === email) ?? null;

    if (!user) {
      const { data: creado, error: eCrear } = await admin.auth.admin.createUser({
        email, email_confirm: true,
        app_metadata: { portal: true },
      });
      if (eCrear || !creado?.user) return json({ error: eCrear?.message ?? 'no_se_pudo_crear' }, 400);
      user = creado.user;
    } else if (!(user.app_metadata as Record<string, unknown> | null)?.portal) {
      const { error: eMeta } = await admin.auth.admin.updateUserById(user.id, {
        app_metadata: { ...(user.app_metadata ?? {}), portal: true },
      });
      if (eMeta) return json({ error: eMeta.message }, 500);
    }

    // ── vincular fichas (solo en invitar) ────────────────────────────────
    if (accion === 'invitar') {
      const filas = idsInvitar.map((client_id) => ({
        email, client_id, activo: true, creado_por: quien.user.email ?? null,
      }));
      const { error: eAcc } = await admin.from('portal_accesos')
        .upsert(filas, { onConflict: 'email,client_id' });
      if (eAcc) return json({ error: eAcc.message }, 500);
    }

    // ── enviar el enlace de entrada (LAW-1) ──────────────────────────────
    // Freno antes de generar el enlace: cada enlace invalida el anterior, así que
    // dos «Reenviar» seguidos dejarían sin valor el que ya tiene el comprador.
    // Si frena o la base no contesta, el acceso queda dado y se avisa.
    const { data: pasa, error: eFreno } = await admin.rpc('portal_enlace_freno', { p_email: email, p_origen: 'invitar' });
    if (eFreno || pasa !== true) {
      console.log('portal-invitar ' + (eFreno ? 'freno_fallo' : 'frenado') + ' @' + dominio(email));
      return json({ ok: true, aviso: AVISO_NO_ENVIADO });
    }
    const libera = async () => {
      const { error } = await admin.rpc('portal_enlace_freno', { p_email: email, p_origen: 'invitar', p_libera: true });
      if (error) console.error('portal-invitar freno_libera_fallo @' + dominio(email));
    };
    // La cuenta ya existe (arriba): se comprueba que el enlace es de ESE usuario.
    // Ni `data` ni `action_link` se registran nunca.
    const { data: link, error: eLink } = await admin.auth.admin.generateLink({ type: 'magiclink', email });
    const th = link?.properties?.hashed_token;
    if (eLink || !th || link?.user?.id !== user.id) {
      console.error('portal-invitar generateLink_fallo @' + dominio(email) + ': ' + String(eLink?.code ?? eLink?.status ?? (th ? 'otro_usuario' : 'sin_token')).slice(0, 40));
      await libera();
      return json({ ok: true, aviso: AVISO_NO_ENVIADO });
    }
    if (!(await enviaEnlace(email, PORTAL_URL + '?th=' + encodeURIComponent(th)))) {
      await libera();
      return json({ ok: true, aviso: AVISO_NO_ENVIADO });
    }
    console.log('portal-invitar enlace_enviado @' + dominio(email));
    return json({ ok: true });
  } catch (e) {
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
}

Deno.serve(manejador);
