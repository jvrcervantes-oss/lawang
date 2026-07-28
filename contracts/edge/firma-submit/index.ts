// firma-submit — el comprador firma en firmar.html y esta función cierra el
// ciclo 100% automático: coge el snapshot de confianza, le mete la firma real +
// una página de auditoría, lo manda al render service (Puppeteer en Railway),
// sube el PDF a `contratos-firmados` y marca el contrato bloqueado.
// Desplegar con verify_jwt=false. Secreto necesario: RENDER_SECRET.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const RENDER_URL = Deno.env.get('RENDER_URL') || 'https://contracts-pdf-service-production.up.railway.app';
const RENDER_SECRET = Deno.env.get('RENDER_SECRET') || '';

// Origen restringido: con '*' cualquier web podia lanzar la firma desde su
// pagina. El token sigue siendo la credencial, pero esto cierra el paso a que
// un tercero monte una pantalla de firma que parezca nuestra.
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
    Vary: 'Origin', // sin esto una CDN cachea el header de un origen y se lo sirve a otro
  };
};

async function sha256hex(s: string): Promise<string> {
  const b = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, '0')).join('');
}
const esc = (s: string) =>
  String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]!));

// página final de auditoría (bilingüe), a sangre de página nueva
function auditPage(d: { nombre: string; email: string; fechaISO: string; ip: string; numero: string; ref: string }) {
  const fecha = d.fechaISO.replace('T', ' ').replace(/\.\d+Z$/, ' UTC');
  const rows = [
    ['Firmante / Signer', esc(d.nombre) || '—'],
    ['Email', esc(d.email) || '—'],
    ['Fecha y hora / Date & time', fecha],
    ['IP', esc(d.ip) || '—'],
    ['Documento / Document', esc(d.numero) || '—'],
    ['Referencia de firma / Signature ref', esc(d.ref)],
  ].map(([k, v]) => `<tr><td style="padding:3mm 12mm 3mm 0;color:#6b6c66;white-space:nowrap">${k}</td><td style="font-weight:600">${v}</td></tr>`).join('');
  return `<div style="page-break-before:always;padding:26mm 20mm;font-family:'Jost',system-ui,sans-serif;color:#2E3437">
    <div style="font-size:13pt;letter-spacing:.28em;text-transform:uppercase;color:#485B37;font-weight:600">Registro de firma electrónica</div>
    <div style="font-size:10pt;letter-spacing:.24em;text-transform:uppercase;color:#8F9B7A;margin-top:2mm">Electronic Signature Record</div>
    <table style="border-collapse:collapse;font-size:11pt;margin-top:12mm">${rows}</table>
    <p style="font-size:8.5pt;color:#6b6c66;margin-top:16mm;line-height:1.6;max-width:150mm">
      Este documento fue firmado electrónicamente y a distancia por la persona identificada arriba, que declaró haber leído y aceptado su contenido. El presente registro deja constancia de dicha aceptación, la fecha/hora y la dirección IP desde la que se realizó.<br><br>
      This document was signed electronically and remotely by the person identified above, who declared having read and accepted its content. This record evidences such acceptance, the date/time and the IP address from which it was made.
    </p>
  </div>`;
}

Deno.serve(async (req) => {
  const cors = corsFor(req);
  const json = (o: unknown, s = 200) =>
    new Response(JSON.stringify(o), { status: s, headers: { ...cors, 'content-type': 'application/json' } });
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'metodo' }, 405);
  if (!RENDER_SECRET) return json({ error: 'config' }, 500);

  let claimedId: string | null = null;
  try {
    const { token, signature, typedName } = await req.json().catch(() => ({}));
    if (!token || typeof token !== 'string') return json({ error: 'token' }, 400);
    if (typeof signature !== 'string' || !signature.startsWith('data:image/png;base64,') || signature.length < 200)
      return json({ error: 'firma' }, 400);
    if (signature.length > 3_000_000) return json({ error: 'firma_grande' }, 413);

    const hash = await sha256hex(token);
    // reclama el token de forma atómica: solo un submit puede pasar de 'pendiente'
    // a 'procesando'. Evita doble firma / doble render por doble click o reintento.
    const { data: claimed } = await sb
      .from('contrato_firmas')
      .update({ estado: 'procesando' })
      .eq('token_hash', hash)
      .eq('estado', 'pendiente')
      .select('id, contrato_id, expira_en, snapshot_path, firmante_nombre, firmante_email, contratos(numero)')
      .maybeSingle();
    if (!claimed) return json({ error: 'no_disponible' }, 409); // no existe, ya usado, o en proceso
    claimedId = claimed.id;

    if (new Date(claimed.expira_en) < new Date()) {
      await sb.from('contrato_firmas').update({ estado: 'pendiente' }).eq('id', claimed.id);
      return json({ error: 'expirado' }, 410);
    }

    const ip = (req.headers.get('x-forwarded-for') || '').split(',')[0].trim();
    const ua = (req.headers.get('user-agent') || '').slice(0, 400);
    const numero = (claimed as any).contratos?.numero || '';

    const { data: file, error: dlErr } = await sb.storage.from('contratos-firmados').download(claimed.snapshot_path);
    if (dlErr || !file) throw new Error('snapshot no disponible');
    let html = await file.text();
    html = html.replaceAll('%%FIRMA_ADQUIRIENTE%%', signature); // firma real dentro del <img src>
    const audit = auditPage({
      nombre: typedName || claimed.firmante_nombre || '',
      email: claimed.firmante_email || '',
      fechaISO: new Date().toISOString(),
      ip,
      numero,
      ref: claimed.id,
    });
    html = html.includes('</body>') ? html.replace('</body>', audit + '</body>') : html + audit;

    // render con Chromium real (mismo servicio que el email de contratos)
    const rr = await fetch(RENDER_URL.replace(/\/$/, '') + '/render-pdf', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'X-Render-Secret': RENDER_SECRET },
      body: JSON.stringify({ html }),
    });
    if (!rr.ok) throw new Error('render ' + rr.status + ' ' + (await rr.text()).slice(0, 200));
    const pdf = new Uint8Array(await rr.arrayBuffer());
    if (pdf.length < 5 || String.fromCharCode(...pdf.slice(0, 4)) !== '%PDF') throw new Error('render no devolvió PDF');

    // La ruta la decide la FIRMA, no el contrato. Antes era `<numero>.pdf`, que
    // rompía de dos formas distintas y en silencio (28-jul-2026):
    //   · dos adquirientes del mismo contrato -> el 2º machacaba el PDF del 1º
    //     y solo sobrevivía la última firma;
    //   · "Subir firmado" en app.html usaba ESA MISMA ruta, así que una subida
    //     manual pisaba el PDF firmado a distancia, y al revés.
    // `claimed.id` es además la "Referencia de firma" impresa en la página de
    // auditoría del propio PDF: el nombre del fichero es rastreable al registro.
    // `upsert:true` se mantiene a propósito: ahora la ruta es única por firma,
    // así que reescribir solo puede pisar el reintento de ESA misma firma.
    const path = `${numero || 'contrato'}_${claimed.id}.pdf`;
    const up = await sb.storage.from('contratos-firmados').upload(path, pdf, { contentType: 'application/pdf', upsert: true });
    if (up.error) throw up.error;

    // bloquea el contrato (mismo efecto que "Subir firmado" manual) y cierra la firma
    await sb.from('contratos').update({ bloqueado: true, pdf_firmado_path: path }).eq('id', claimed.contrato_id);
    await sb.from('contrato_firmas').update({
      estado: 'firmado', firmado_en: new Date().toISOString(), firmante_ip: ip, firmante_user_agent: ua,
      pdf_path: path,  // cada firma guarda SU pdf; `contratos.pdf_firmado_path` solo apunta al último
    }).eq('id', claimed.id);

    return json({ ok: true, numero });
  } catch (e) {
    // deja el token reutilizable para que el comprador pueda reintentar
    if (claimedId) await sb.from('contrato_firmas').update({ estado: 'pendiente' }).eq('id', claimedId);
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
