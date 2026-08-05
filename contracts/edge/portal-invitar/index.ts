// portal-invitar — da acceso al portal del comprador y envía el enlace de entrada.
//
// Existe porque crear el usuario de Auth y marcarle `app_metadata.portal` exige
// `service_role`, que no puede vivir en el navegador. El vínculo email→fichas
// (portal_accesos) también se escribe aquí para que invitar sea UNA acción
// atómica, no tres pasos que alguien deja a medias.
//
// ⚠️ La autorización se decide SIEMPRE con el JWT de quien llama (admin de la
// suite), nunca con un campo del body. verify_jwt=false: se valida dentro para
// devolver errores legibles.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const URL_SB = Deno.env.get('SUPABASE_URL')!;
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const ANON = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const admin = createClient(URL_SB, SERVICE);

const PORTAL_URL = 'https://lawangproperties.com/portal/';

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

Deno.serve(async (req) => {
  const cors = corsFor(req);
  // Un rechazo que solo viaja al navegador no existe: el 5-ago hubo cuatro 400
  // seguidos y en los logs solo constaba el código, así que no se pudo saber
  // POR QUÉ. Ahora cada salida distinta de 200 deja su motivo en el log.
  const json = (o: unknown, s = 200) => {
    if (s !== 200) console.error('portal-invitar ' + s + ': ' + JSON.stringify(o));
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
      .from('usuarios').select('rol, activo').eq('user_id', quien.user.id).maybeSingle();
    if (eFicha) return json({ error: 'no_se_pudo_comprobar_permiso' }, 500);
    if (!ficha || !ficha.activo || !['super_admin', 'admin'].includes(ficha.rol))
      return json({ error: 'no_autorizado' }, 403);

    const body = await req.json().catch(() => ({}));
    const accion = String(body.accion ?? '');
    const email = String(body.email ?? '').trim().toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json({ error: 'email_invalido' }, 400);

    // El email podría ser de alguien del EQUIPO: esa cuenta no se convierte en
    // portal (mezclaría los dos mundos en un mismo usuario de Auth).
    const { data: esEquipo } = await admin.from('usuarios').select('user_id').eq('email', email).maybeSingle();
    if (esEquipo) return json({ error: 'ese_email_es_del_equipo' }, 400);

    // ── revocar: apaga los accesos; la cuenta queda pero no ve nada ──────
    if (accion === 'revocar') {
      const { error } = await admin.from('portal_accesos').update({ activo: false }).eq('email', email);
      if (error) return json({ error: error.message }, 500);
      return json({ ok: true });
    }

    // ── invitar / reenviar ───────────────────────────────────────────────
    if (accion !== 'invitar' && accion !== 'reenviar') return json({ error: 'accion_desconocida' }, 400);

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
      const ids: string[] = Array.isArray(body.client_ids) ? body.client_ids.map(String) : [];
      if (!ids.length) return json({ error: 'sin_fichas' }, 400);
      const filas = ids.map((client_id) => ({
        email, client_id, activo: true, creado_por: quien.user.email ?? null,
      }));
      const { error: eAcc } = await admin.from('portal_accesos')
        .upsert(filas, { onConflict: 'email,client_id' });
      if (eAcc) return json({ error: eAcc.message }, 500);
    }

    // ── enviar el enlace de entrada ──────────────────────────────────────
    // El correo lo manda el flujo estándar de magic link (mismo remitente y
    // plantilla que usará el comprador cada vez que entre). Con el SMTP por
    // defecto de Supabase hay un límite bajo de correos/hora: para invitar en
    // tandas hace falta el SMTP propio (pendiente del owner).
    const pub = createClient(URL_SB, ANON);
    const { error: eOtp } = await pub.auth.signInWithOtp({
      email,
      options: { shouldCreateUser: false, emailRedirectTo: PORTAL_URL },
    });
    if (eOtp) return json({ ok: true, aviso: 'acceso_creado_pero_email_no_enviado: ' + eOtp.message });
    return json({ ok: true });
  } catch (e) {
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
