// comunicados-envio — entrega por correo los comunicados que el owner encoló en
// /intranet/v4/comunicacion/ (tabla `comunicado_envios`, estado 'pendiente').
// Hermana de avisos-manager: el QUÉ y el A QUIÉN ya los decidió la base
// (`comunicado_encolar`, `comunicado_prueba` — supabase/migrations/
// 20260923004359_comunicados.sql); esta Edge solo entrega.
//
// Invocada por pg_cron cada 10 min (job `comunicados-envio`) y, para que no
// haya que esperar, por `_comunicados_despierta()` al encolar. Nunca por el
// navegador. verify_jwt=false: la puerta es X-Cron-Secret contra el MISMO
// secreto de Vault que avisos-manager (`cron_avisos_manager_secret()`).
//
// Revisión previa #47 (Seguridad + Datos):
//  · Reclama su tanda con `comunicado_envios_reclamar` (FOR UPDATE SKIP LOCKED):
//    el cron y el despertador pueden coincidir y NO cogen la misma fila.
//  · Fallo de SMTP → vuelve a 'pendiente' y reintenta en la próxima pasada;
//    al 3.er intento queda en 'error' y la pantalla ofrece reintentar.
//  · El error guardado se recorta a 300 caracteres y nunca lleva cabeceras ni
//    configuración.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const SITIO = (Deno.env.get('SITIO_URL') || 'https://lawangproperties.com').replace(/\/$/, '');
const RENDER_SECRET = Deno.env.get('RENDER_SECRET') || '';

// 25 por pasada: send_email.php abre una conexión SMTP por correo y Hostinger
// ya nos dio 502 por ráfagas. 25 cada 10 min cubre al equipo entero (~30) en
// dos pasadas como mucho, y el despertador adelanta la primera.
const TOPE = 25;
const MAX_INTENTOS = 3;
// Sin botón propio, el del equipo: la intranet. El valor por defecto de
// send_email.php es el portal de COMPRADORES, que aquí sería el sitio equivocado.
const CTA_DEFECTO = { url: SITIO + '/intranet/', texto: 'Abrir la intranet' };

type Comunicado = {
  id: string; asunto: string; encabezado: string | null; cuerpo: string;
  cta_url: string | null; cta_texto: string | null;
};

async function enviarEmail(to: string, c: Comunicado, prueba: boolean) {
  const r = await fetch(SITIO + '/contracts/api/send_email.php', {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'X-Render-Secret': RENDER_SECRET },
    body: JSON.stringify({
      to,
      subject: (prueba ? '[PRUEBA] ' : '') + c.asunto,
      encabezado: c.encabezado || '',
      message: c.cuerpo,
      cta_url: c.cta_url || CTA_DEFECTO.url,
      cta_texto: c.cta_texto || CTA_DEFECTO.texto,
      attach: false,
    }),
  });
  const t = await r.text();
  if (!r.ok || !t.includes('"ok":true')) throw new Error('HTTP ' + r.status + ': ' + t.slice(0, 200));
}

Deno.serve(async (req) => {
  const json = (o: unknown, s = 200) =>
    new Response(JSON.stringify(o), { status: s, headers: { 'content-type': 'application/json' } });
  if (req.method !== 'POST') return json({ error: 'metodo' }, 405);
  if (!RENDER_SECRET) return json({ error: 'config' }, 500);

  const { data: esperado, error: eSec } = await sb.rpc('cron_avisos_manager_secret');
  if (eSec || !esperado) return json({ error: 'sin_secreto_configurado' }, 500);
  if ((req.headers.get('x-cron-secret') || '') !== esperado) return json({ error: 'no_autorizado' }, 401);

  const { data: tanda, error: eRec } = await sb.rpc('comunicado_envios_reclamar', { p_tope: TOPE });
  if (eRec) return json({ error: eRec.message }, 500);
  if (!tanda || !tanda.length) return json({ ok: true, enviadas: 0, fallidas: 0 });

  const ids = [...new Set(tanda.map((t: { comunicado_id: string }) => t.comunicado_id))];
  const { data: coms, error: eCom } = await sb.from('comunicados')
    .select('id, asunto, encabezado, cuerpo, cta_url, cta_texto').in('id', ids);
  if (eCom) return json({ error: eCom.message }, 500);
  const porId = new Map((coms ?? []).map((c: Comunicado) => [c.id, c]));

  // es_prueba no viene en el reclamo: se lee aparte, una consulta para toda la tanda
  const { data: flags } = await sb.from('comunicado_envios')
    .select('id, es_prueba').in('id', tanda.map((t: { id: string }) => t.id));
  const esPrueba = new Map((flags ?? []).map((f: { id: string; es_prueba: boolean }) => [f.id, f.es_prueba]));

  let enviadas = 0, fallidas = 0;
  for (const e of tanda as { id: string; comunicado_id: string; email: string; intentos: number }[]) {
    const c = porId.get(e.comunicado_id);
    try {
      if (!c) throw new Error('el comunicado ya no existe');
      await enviarEmail(e.email, c, esPrueba.get(e.id) === true);
      await sb.from('comunicado_envios')
        .update({ estado: 'ok', error: null, enviado_en: new Date().toISOString() }).eq('id', e.id);
      enviadas++;
    } catch (err) {
      const msg = String((err as Error)?.message ?? err).slice(0, 300);
      await sb.from('comunicado_envios')
        .update({ estado: e.intentos >= MAX_INTENTOS || !c ? 'error' : 'pendiente', error: msg })
        .eq('id', e.id);
      fallidas++;
    }
  }
  return json({ ok: true, enviadas, fallidas });
});
