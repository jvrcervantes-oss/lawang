// avisos-manager — envía por correo real los avisos que un trigger marcó
// `email_pendiente=true` en `notificaciones` (contrato bloqueado, solicitud de
// pago resuelta, unidad que avanza de estado) a los sales_manager/project_manager
// del proyecto de cada fila. El QUÉ y el A QUIÉN ya los decidió la base
// (`_avisar_managers`, `avisos_manager_email.sql`); esta Edge solo entrega.
//
// Invocada por pg_cron cada 10 min (job `avisos-manager-email`), nunca por el
// navegador. Desplegar con verify_jwt=false: la puerta es X-Cron-Secret,
// comparado contra `cron_avisos_manager_secret()` — mismo patrón que
// factura-vencimiento/facturacion_automatica.sql (18-ago-2026).
//
// MINIMIZACIÓN (Legal, revisión previa 10-sep): el correo lleva exactamente lo
// que el trigger puso en `titulo`/`detalle` — nombre + proyecto + estado — y
// un enlace a la intranet, NUNCA pasaporte, nacionalidad ni domicilio. Ese
// dato sigue detrás de la RLS, no viaja por email.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const SITIO = (Deno.env.get('SITIO_URL') || 'https://lawangproperties.com').replace(/\/$/, '');
const RENDER_SECRET = Deno.env.get('RENDER_SECRET') || '';

// Tope por ejecución (misma cautela que facturacion_automatica): si algo se
// tuerce y se acumulan avisos, esto no manda 3.000 correos de golpe.
//
// 24-sep-2026: de 50 seguidos a 6 por pasada con 20 s entre correo y correo,
// como comunicados-envio. Hostinger bloqueó el SMTP de admin@ por «Content
// Spam» y cada cambio de estado de una unidad salía como 5 correos IDÉNTICOS
// a la vez (uno por manager): ráfaga + asunto repetido, justo lo que castiga.
const TOPE = 6;
const ESPERA_MS = 20_000;
// Respuesta de bloqueo del proveedor (554 5.7.1 «Outbound sending is
// disabled»): se para la tanda y se ponen los envíos en pausa para todos.
const BLOQUEO_SMTP = /\b554\b|5\.7\.1|Outbound sending is disabled/i;
// send_email.php en modo mantenimiento: no tiene sentido seguir con la tanda.
const EN_PAUSA = /en pausa \(modo mantenimiento\)/i;

// «Ketut, unidad A5 — vendida»: el nombre del manager delante para que el
// mismo aviso a cinco personas no salga con el mismo asunto. La primera letra
// solo baja a minúscula si es una palabra normal («Unidad» → «unidad»).
function asuntoPara(titulo: string, nombre: string | null): string {
  const pila = (nombre || '').trim().split(/\s+/)[0] || '';
  let a = titulo.trim();
  if (!pila) return a;
  if (/^\p{Lu}\p{Ll}/u.test(a)) a = a.charAt(0).toLocaleLowerCase('es') + a.slice(1);
  return pila + ', ' + a;
}

async function enviarEmail(p: { to: string; subject: string; message: string }) {
  const r = await fetch(SITIO + '/contracts/api/send_email.php', {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'X-Render-Secret': RENDER_SECRET },
    body: JSON.stringify({ to: p.to, subject: p.subject, message: p.message, attach: false }),
  });
  const t = await r.text();
  if (!r.ok || !t.includes('"ok":true')) throw new Error('email a ' + p.to + ': ' + t.slice(0, 180));
}

Deno.serve(async (req) => {
  const json = (o: unknown, s = 200) =>
    new Response(JSON.stringify(o), { status: s, headers: { 'content-type': 'application/json' } });
  if (req.method !== 'POST') return json({ error: 'metodo' }, 405);
  if (!RENDER_SECRET) return json({ error: 'config' }, 500);

  // ── la puerta: el secreto de Vault, comparado con el que trae el cron ──────
  const { data: esperado, error: eSec } = await sb.rpc('cron_avisos_manager_secret');
  if (eSec || !esperado) return json({ error: 'sin_secreto_configurado' }, 500);
  if ((req.headers.get('x-cron-secret') || '') !== esperado) return json({ error: 'no_autorizado' }, 401);

  const { data: pendientes, error: eSel } = await sb.from('notificaciones')
    .select('id, titulo, detalle, destinatario, enlace')
    .eq('email_pendiente', true)
    .order('creado_en', { ascending: true })
    .limit(TOPE);
  if (eSel) return json({ error: eSel.message }, 500);

  // nombre de pila de cada destinatario, una consulta para toda la tanda
  const correos = [...new Set((pendientes ?? []).map((n) => n.destinatario).filter(Boolean))];
  const { data: gente } = correos.length
    ? await sb.from('usuarios').select('email, nombre').in('email', correos)
    : { data: [] };
  const nombreDe = new Map((gente ?? []).map((u: { email: string; nombre: string | null }) => [(u.email || '').toLowerCase(), u.nombre]));

  const enviadas: string[] = [];
  const fallidas: string[] = [];
  let intentados = 0;
  for (const n of pendientes ?? []) {
    // sin destinatario no hay a quién mandarlo (no debería pasar: _avisar_managers
    // siempre pone un email) — se apaga para no reintentarlo para siempre
    if (!n.destinatario) {
      await sb.from('notificaciones').update({ email_pendiente: false }).eq('id', n.id);
      continue;
    }
    if (intentados++ > 0) await new Promise((r) => setTimeout(r, ESPERA_MS));
    try {
      const enlace = n.enlace ? SITIO + n.enlace : SITIO + '/intranet/';
      await enviarEmail({
        to: n.destinatario,
        subject: asuntoPara(n.titulo || 'Aviso de la intranet Lawang', nombreDe.get(String(n.destinatario).toLowerCase()) ?? null),
        message: (n.detalle || '') + '\n\nVer en la intranet: ' + enlace,
      });
      await sb.from('notificaciones')
        .update({ email_pendiente: false, email_enviado_en: new Date().toISOString() })
        .eq('id', n.id);
      enviadas.push(n.id);
    } catch (e) {
      // se deja email_pendiente=true a propósito: el próximo disparo (10 min) reintenta
      const msg = String((e as Error)?.message ?? e);
      fallidas.push(n.id + ': ' + msg);
      if (BLOQUEO_SMTP.test(msg)) {
        await sb.from('mantenimiento').update({
          envios_pausados: true,
          motivo: 'Pausa automática: el proveedor de correo ha bloqueado el envío (' + msg.slice(0, 120) + ').',
          cambiado_por: null, cambiado_en: new Date().toISOString(),
        }).eq('id', 1);
        return json({ ok: false, enviadas: enviadas.length, fallidas: fallidas.length, pausado: true });
      }
      if (EN_PAUSA.test(msg)) break;
    }
  }
  return json({ ok: true, enviadas: enviadas.length, fallidas: fallidas.length, detalle_fallidas: fallidas });
});
