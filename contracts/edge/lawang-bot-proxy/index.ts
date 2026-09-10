// lawang-bot-proxy — puente entre la intranet y el bot de WhatsApp de Lawang.
// 10-sep-2026. Revisión previa: Bots + Seguridad + Legal (plan en
// CEO/revisiones/estado.json y hallazgos en contexto/pendientes.md).
//
// POR QUÉ EXISTE. El bot (`lawang-bot`, Railway) protege sus `/admin/api/*` con
// una clave (`X-Admin-Key`), y esa clave NUNCA puede llegar al navegador — un
// `fetch` desde la intranet con la clave en el cliente la deja en cualquier
// devtools. Aquí la clave vive como secreto de la función (`LAWANG_BOT_ADMIN_KEY`)
// y nunca sale de este servidor.
//
// WHITELIST EXPLÍCITA, NO PASSTHROUGH. El bot tiene más endpoints admin de los
// que esta pestaña necesita (envío de plantillas, newsletters, medios…) — un
// proxy que reenviara cualquier `path` que le pidan convertiría un password de
// panel interno en un password de API abierta a lo que sea. Solo las acciones
// de abajo, cada una con su propio chequeo de permiso.
//
// DOS PERMISOS DISTINTOS (no uno): 'leads' para mirar conversaciones/pausar el
// bot (ya lo tiene cualquiera que vea el CRM de leads); 'closers' para tocar la
// agenda de citas — quien agenda una llamada de venta y más adelante verá su
// grabación de Fathom es una decisión de acceso aparte (misma separación que ya
// existe entre 'leads' y 'operaciones').
import { createClient } from 'jsr:@supabase/supabase-js@2';

const URL_SB = Deno.env.get('SUPABASE_URL')!;
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const admin = createClient(URL_SB, SERVICE);

const BOT_BASE = 'https://lawang-bot-production.up.railway.app';
const BOT_KEY = Deno.env.get('LAWANG_BOT_ADMIN_KEY') ?? '';

const ORIGENES = [
  'https://lawangproperties.com',
  'https://www.lawangproperties.com',
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

// El bot responde JSON siempre (o texto plano en algún caso raro) — se
// reenvía tal cual, sin reinterpretarlo, para no inventar una forma nueva de
// error que el frontend tenga que aprender aparte de la del bot real.
async function llamaBot(path: string, init: RequestInit = {}) {
  if (!BOT_KEY) {
    return { status: 503, body: { error: 'lawang-bot-proxy no configurado (falta LAWANG_BOT_ADMIN_KEY)' } };
  }
  const r = await fetch(BOT_BASE + path, {
    ...init,
    headers: { ...(init.headers ?? {}), 'X-Admin-Key': BOT_KEY, 'Content-Type': 'application/json' },
  });
  const texto = await r.text();
  let body: unknown;
  try { body = JSON.parse(texto); } catch { body = { error: texto || 'respuesta vacía del bot' }; }
  return { status: r.status, body };
}

Deno.serve(async (req) => {
  const cors = corsFor(req);
  const json = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { ...cors, 'content-type': 'application/json' } });
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'metodo' }, 405);

  try {
    // ── quién llama ──────────────────────────────────────────────────────
    const jwt = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '');
    if (!jwt) return json({ error: 'sin_sesion' }, 401);
    const { data: quien, error: eUser } = await admin.auth.getUser(jwt);
    if (eUser || !quien?.user) return json({ error: 'sesion_invalida' }, 401);

    const { data: ficha, error: eFicha } = await admin
      .from('usuarios').select('rol, activo, herramientas, email').eq('user_id', quien.user.id).maybeSingle();
    if (eFicha) return json({ error: 'no_se_pudo_comprobar_permiso' }, 500);
    if (!ficha || !ficha.activo) return json({ error: 'no_autorizado' }, 403);
    const esSuper = ficha.rol === 'super_admin';
    const puedeLeads = esSuper || (ficha.herramientas ?? []).includes('leads');
    const puedeClosers = esSuper || (ficha.herramientas ?? []).includes('closers');

    const body = await req.json().catch(() => ({}));
    const accion = String(body.accion ?? '');

    // ── Setter IA: requiere 'leads' ──────────────────────────────────────
    if (accion === 'conversaciones') {
      if (!puedeLeads) return json({ error: 'sin_permiso: leads' }, 403);
      const r = await llamaBot('/admin/api/leads');
      return json(r.body, r.status);
    }
    if (accion === 'conversacion') {
      if (!puedeLeads) return json({ error: 'sin_permiso: leads' }, 403);
      const phone = String(body.phone ?? '').replace(/[^0-9]/g, '');
      if (!phone) return json({ error: 'phone_requerido' }, 400);
      const r = await llamaBot('/admin/api/conv/' + encodeURIComponent(phone));
      return json(r.body, r.status);
    }
    if (accion === 'pausar') {
      if (!puedeLeads) return json({ error: 'sin_permiso: leads' }, 403);
      const phone = String(body.phone ?? '').replace(/[^0-9]/g, '');
      if (!phone) return json({ error: 'phone_requerido' }, 400);
      const r = await llamaBot('/admin/api/pause', {
        method: 'POST', body: JSON.stringify({ phone, paused: !!body.paused }),
      });
      return json(r.body, r.status);
    }

    // ── Agenda de cierre: requiere 'closers' ─────────────────────────────
    if (accion === 'citas_listar') {
      if (!puedeClosers) return json({ error: 'sin_permiso: closers' }, 403);
      const r = await llamaBot('/admin/api/appts');
      return json(r.body, r.status);
    }
    if (accion === 'citas_guardar') {
      if (!puedeClosers) return json({ error: 'sin_permiso: closers' }, 403);
      const { id, phone, name, title, when, closer, notes } = body;
      if (!when) return json({ error: 'when_requerido' }, 400);
      // el closer que se guarda es el de la sesión salvo que un admin agende a
      // nombre de otro — evita que cualquiera con 'closers' agende citas
      // atribuidas a un compañero
      const closerFinal = esSuper || ficha.rol === 'admin' ? (closer || ficha.email) : ficha.email;
      const r = await llamaBot('/admin/api/appts', {
        method: 'POST',
        body: JSON.stringify({ id, phone, name, title, when, closer: closerFinal, notes }),
      });
      return json(r.body, r.status);
    }
    if (accion === 'citas_borrar') {
      if (!puedeClosers) return json({ error: 'sin_permiso: closers' }, 403);
      const id = String(body.id ?? '');
      if (!id) return json({ error: 'id_requerido' }, 400);
      const r = await llamaBot('/admin/api/appts/' + encodeURIComponent(id), { method: 'DELETE' });
      return json(r.body, r.status);
    }

    // Cualquier otra acción se deniega — nunca un passthrough de `path` libre.
    return json({ error: 'accion_desconocida' }, 400);
  } catch (e) {
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
