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
// tuerce y se acumulan avisos, esto no manda 3.000 correos de golpe — manda
// 50 cada 10 minutos hasta ponerse al día.
const TOPE = 50;

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

  const enviadas: string[] = [];
  const fallidas: string[] = [];
  for (const n of pendientes ?? []) {
    // sin destinatario no hay a quién mandarlo (no debería pasar: _avisar_managers
    // siempre pone un email) — se apaga para no reintentarlo para siempre
    if (!n.destinatario) {
      await sb.from('notificaciones').update({ email_pendiente: false }).eq('id', n.id);
      continue;
    }
    try {
      const enlace = n.enlace ? SITIO + n.enlace : SITIO + '/intranet/';
      await enviarEmail({
        to: n.destinatario,
        subject: n.titulo || 'Aviso de la intranet Lawang',
        message: (n.detalle || '') + '\n\nVer en la intranet: ' + enlace,
      });
      await sb.from('notificaciones')
        .update({ email_pendiente: false, email_enviado_en: new Date().toISOString() })
        .eq('id', n.id);
      enviadas.push(n.id);
    } catch (e) {
      // se deja email_pendiente=true a propósito: el próximo disparo (10 min) reintenta
      fallidas.push(n.id + ': ' + String((e as Error)?.message ?? e));
    }
  }
  return json({ ok: true, enviadas: enviadas.length, fallidas: fallidas.length, detalle_fallidas: fallidas });
});
