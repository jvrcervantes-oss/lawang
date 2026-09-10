// investor-deck-codigo — manda un código de 6 dígitos de un solo uso al email
// del inversor antes de dejarle reservar (hallazgo Legal #2 de la revisión
// previa, 10-sep-2026). Hermana de portal-acceso en el modelo de autorización:
// se llama SIN sesión, y por eso valida todo a mano en vez de confiar en RLS.
//
// Respuesta SIEMPRE {ok:true} salvo error de formato/servidor — no revela si el
// email tiene ya una reserva o no (mismo criterio que portal-acceso).
//
// ⚠️ PENDIENTE DE DESPLIEGUE: el `deploy_edge_function` del MCP lo bloqueó el
// clasificador de permisos de Auto Mode (acción irreversible sobre producción,
// exige aprobación humana explícita) — ver informe de la sesión del 10-sep-2026.
// El código está listo y verificado contra el patrón de portal-acceso/
// send-contract-email; falta el `supabase functions deploy investor-deck-codigo`
// (o el mismo MCP, con aprobación interactiva) para que exista en producción.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const URL_SB = Deno.env.get('SUPABASE_URL')!;
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const admin = createClient(URL_SB, SERVICE);

const RENDER_SECRET = Deno.env.get('RENDER_SECRET') || '';
const SITIO = (Deno.env.get('SITIO_URL') || 'https://lawangproperties.com').replace(/\/$/, '');

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

async function sha256(s: string) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, '0')).join('');
}

// cooldown en memoria del isolate — igual de "mejor esfuerzo" que el de
// send-contract-email; el freno de verdad es la fila en investor_deck_verificaciones
// (máximo un código activo sin caducar por email).
const ultimoEnvio = new Map<string, number>();
const COOLDOWN_MS = 30_000;

Deno.serve(async (req) => {
  const cors = corsFor(req);
  const json = (o: unknown, s = 200) =>
    new Response(JSON.stringify(o), { status: s, headers: { ...cors, 'content-type': 'application/json' } });
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ ok: false, error: 'metodo' }, 405);

  let email = '';
  try {
    const body = await req.json().catch(() => ({}));
    email = String(body.email ?? '').trim().toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json({ ok: true });

    const ahora = Date.now();
    const previo = ultimoEnvio.get(email) ?? 0;
    if (ahora - previo < COOLDOWN_MS) return json({ ok: true }); // no delata rate-limit
    ultimoEnvio.set(email, ahora);

    // como mucho un código activo por email: los anteriores no caducados se
    // invalidan (evita que alguien acumule códigos válidos a la vez).
    await admin.from('investor_deck_verificaciones').update({ usado: true }).eq('email', email).eq('usado', false);

    const codigo = String(Math.floor(100000 + Math.random() * 900000));
    const codigoHash = await sha256(codigo);
    const expira = new Date(Date.now() + 10 * 60 * 1000).toISOString();

    const { error: eIns } = await admin
      .from('investor_deck_verificaciones')
      .insert({ email, codigo_hash: codigoHash, expira_at: expira });
    if (eIns) {
      console.error('investor-deck-codigo insert <' + email + '>: ' + eIns.message);
      return json({ ok: false, error: 'no_disponible' }, 500);
    }

    if (RENDER_SECRET) {
      try {
        const r = await fetch(SITIO + '/contracts/api/send_email.php', {
          method: 'POST',
          headers: { 'content-type': 'application/json', 'X-Render-Secret': RENDER_SECRET },
          body: JSON.stringify({
            to: email,
            subject: 'Tu código de verificación — Lawang Investor Deck',
            message:
              'Tu código de verificación es ' + codigo + '. Caduca en 10 minutos.\n\n' +
              'Your verification code is ' + codigo + '. It expires in 10 minutes.\n\n' +
              'Si no has solicitado esto, ignora este correo. / If you did not request this, ignore this email.',
          }),
        });
        if (!r.ok) console.error('investor-deck-codigo send_email http ' + r.status + ' <' + email + '>');
      } catch (e) {
        console.error('investor-deck-codigo send_email excepcion <' + email + '>: ' + String((e as Error)?.message ?? e));
      }
    } else {
      console.error('investor-deck-codigo RENDER_SECRET no configurado — código generado pero NO enviado <' + email + '>');
    }

    return json({ ok: true });
  } catch (e) {
    console.error('investor-deck-codigo excepcion <' + email + '>: ' + String((e as Error)?.message ?? e));
    return json({ ok: false, error: 'no_disponible' }, 500);
  }
});
