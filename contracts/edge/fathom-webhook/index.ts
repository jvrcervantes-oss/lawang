// fathom-webhook — receptor de Fathom.ai, SIN CONECTAR todavía (10-sep-2026).
// Revisión previa: Bots + Seguridad + Legal.
//
// EL OWNER NO TIENE CUENTA DE FATHOM.AI. Esta función existe para que la tabla
// `fathom_call_insights` tenga por dónde llenarse el día que exista, pero HOY
// no hay secreto real configurado — y por diseño responde 503 a todo mientras
// eso sea así (mismo patrón que `adminAuth` del bot cuando falta ADMIN_PASSWORD:
// cerrado por defecto, nunca abierto "por ahora" — hallazgo Seguridad #3).
//
// ⚠️ FORMA DEL PAYLOAD SIN CONFIRMAR. No hay cuenta real ni documentación de
// Fathom delante: el parseo de abajo es la mejor suposición (campos que Fathom
// anuncia en su propio marketing) y HAY QUE REVISARLO contra el payload real
// del primer webhook de verdad antes de fiarse de un solo insert. El secreto
// también es una suposición (`X-Fathom-Webhook-Secret` comparado contra
// `FATHOM_WEBHOOK_SECRET`) — Fathom puede firmar de otra forma (HMAC de un
// cuerpo, por ejemplo) y esto tendría que adaptarse el día que se lea su
// documentación real de webhooks al dar de alta la cuenta.
//
// NO IDENTIFICAMOS AL LEAD POR SUPOSICIÓN: se busca por email o whatsapp EXACTO
// contra `leads`. Si no hay una coincidencia clara, no se inserta nada con un
// lead_id inventado — se descarta y se deja constancia en la respuesta, nunca
// en la tabla.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const URL_SB = Deno.env.get('SUPABASE_URL')!;
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const admin = createClient(URL_SB, SERVICE);

const SECRETO = Deno.env.get('FATHOM_WEBHOOK_SECRET') ?? '';

Deno.serve(async (req) => {
  const json = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'content-type': 'application/json' } });
  if (req.method !== 'POST') return json({ error: 'metodo' }, 405);

  // Cerrado por defecto: sin secreto configurado, nadie pasa — ni siquiera para
  // "probar si funciona". Ver cabecera del fichero.
  if (!SECRETO) return json({ error: 'fathom-webhook no configurado todavía (falta FATHOM_WEBHOOK_SECRET)' }, 503);

  const recibido = req.headers.get('x-fathom-webhook-secret') ?? '';
  if (recibido !== SECRETO) return json({ error: 'firma_invalida' }, 401);

  const payload = await req.json().catch(() => null);
  if (!payload) return json({ error: 'payload_invalido' }, 400);

  const {
    meeting_id, recording_id, recording_url, summary,
    objections, action_items, participant_email, participant_phone,
  } = payload as Record<string, unknown>;

  const email = typeof participant_email === 'string' ? participant_email.trim().toLowerCase() : '';
  const phone = typeof participant_phone === 'string' ? participant_phone.replace(/[^0-9]/g, '') : '';
  if (!email && !phone) {
    return json({ ok: false, motivo: 'sin_email_ni_telefono_de_participante_no_se_puede_identificar_el_lead' }, 200);
  }

  let query = admin.from('leads').select('id, email, whatsapp');
  const { data: candidatos } = email
    ? await query.ilike('email', email)
    : await query.ilike('whatsapp', '%' + phone);
  const lead = (candidatos ?? [])[0];
  if (!lead) {
    return json({ ok: false, motivo: 'ningun_lead_coincide_no_se_inserta_con_lead_id_inventado' }, 200);
  }

  const { data: cierre } = await admin
    .from('lead_closer').select('closer_email').eq('lead_id', lead.id).maybeSingle();

  const { error } = await admin.from('fathom_call_insights').insert({
    lead_id: lead.id,
    closer_email: cierre?.closer_email ?? null,
    resumen: typeof summary === 'string' ? summary : null,
    objeciones: objections ?? [],
    proximos_pasos: action_items ?? [],
    recording_url: typeof recording_url === 'string' ? recording_url : null,
    fathom_recording_id: typeof recording_id === 'string' ? recording_id : (typeof meeting_id === 'string' ? meeting_id : null),
  });
  if (error) return json({ error: error.message }, 500);
  return json({ ok: true, lead_id: lead.id });
});
