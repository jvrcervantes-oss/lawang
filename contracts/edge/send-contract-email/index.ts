// send-contract-email — reemplaza la llamada directa navegador→send_email.php
// del botón "Enviar por email" de app.html cuando hay adjunto.
//
// Por qué existe (LAW-30, 6-ago-2026): el WAF de Hostinger (anomaly scoring
// acumulativo, tipo ModSecurity/OWASP CRS) bloquea con 403 cualquier request a
// send_email.php cuyo cuerpo lleve el HTML completo del contrato con la
// portada de diseño (gradientes, color-mix(), custom properties, url()) — no
// hay una causa única removible sin romper el PDF (investigación cerrada en
// memoria del estudio). Arreglarlo en hPanel es tarea del owner y no depende
// de esta sesión.
//
// El rodeo: la Edge `firma-submit` YA hace exactamente esto al cerrar una
// firma y nunca ha tropezado con el WAF — renderiza el PDF llamando a Railway
// directamente (server-to-server, fuera del dominio de Hostinger) y luego
// llama a send_email.php con `pdf_base64` (nunca `html`), así que lo único
// que cruza el WAF es PDF en base64 + texto, sin CSS. Esta función copia ese
// mismo patrón para el botón manual, que hasta ahora mandaba el HTML directo.
// Cero cambios en send_email.php.
//
// verify_jwt=false: con true el gateway de Supabase intercepta la request
// (incluido el preflight OPTIONS) antes de que corra el código de aquí abajo,
// así que las cabeceras CORS nunca se aplican — mismo motivo que
// admin-usuarios/portal-invitar. Se valida el JWT a mano.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const URL_SB = Deno.env.get('SUPABASE_URL')!;
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const admin = createClient(URL_SB, SERVICE);

// Mismo secreto de proyecto que ya usa firma-submit — no se duplica.
const RENDER_URL = Deno.env.get('RENDER_URL') || 'https://contracts-pdf-service-production.up.railway.app';
const RENDER_SECRET = Deno.env.get('RENDER_SECRET') || '';
const SITIO = (Deno.env.get('SITIO_URL') || 'https://lawangproperties.com').replace(/\/$/, '');

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

const b64 = (u8: Uint8Array) => {
  // en trozos: String.fromCharCode(...u8) con un PDF de MB revienta la pila
  let s = '';
  for (let i = 0; i < u8.length; i += 0x8000) s += String.fromCharCode(...u8.subarray(i, i + 0x8000));
  return btoa(s);
};

// ponytail: cooldown en memoria del propio isolate, no una tabla — el botón
// lo usa un puñado de personas del equipo con sesión válida, esto solo acota
// un doble-click o un bucle accidental. Se resetea en cada cold start; si
// algún día hace falta un límite real entre instancias, pasar a una tabla.
const ultimoEnvio = new Map<string, number>();
const COOLDOWN_MS = 4000;

Deno.serve(async (req) => {
  const cors = corsFor(req);
  const json = (o: unknown, s = 200) => {
    if (s !== 200) console.error('send-contract-email ' + s + ': ' + JSON.stringify(o));
    return new Response(JSON.stringify(o), { status: s, headers: { ...cors, 'content-type': 'application/json' } });
  };
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ ok: false, error: 'metodo' }, 405);

  try {
    const jwt = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '');
    if (!jwt) return json({ ok: false, error: 'sin_sesion' }, 401);
    const { data: quien, error: eUser } = await admin.auth.getUser(jwt);
    if (eUser || !quien?.user) return json({ ok: false, error: 'sesion_invalida' }, 401);

    const ahora = Date.now();
    const previo = ultimoEnvio.get(quien.user.id) ?? 0;
    if (ahora - previo < COOLDOWN_MS) return json({ ok: false, error: 'espera_un_momento' }, 429);
    ultimoEnvio.set(quien.user.id, ahora);

    const body = await req.json().catch(() => ({}));
    const to = String(body.to ?? '').trim();
    const subject = String(body.subject ?? '');
    const message = String(body.message ?? '');
    const filename = String(body.filename ?? 'contrato.pdf');
    const html = String(body.html ?? '');
    const pdfManual = String(body.pdf_base64 ?? '');
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(to)) return json({ ok: false, error: 'destinatario_invalido' }, 400);
    if (!html && !pdfManual) return json({ ok: false, error: 'falta_html_o_pdf' }, 400);

    let pdfB64 = '';
    if (html) {
      if (!RENDER_SECRET) return json({ ok: false, error: 'render_no_configurado' }, 500);
      try {
        const rr = await fetch(RENDER_URL.replace(/\/$/, '') + '/render-pdf', {
          method: 'POST',
          headers: { 'content-type': 'application/json', 'X-Render-Secret': RENDER_SECRET },
          body: JSON.stringify({ html }),
        });
        if (!rr.ok) throw new Error('render http ' + rr.status);
        pdfB64 = b64(new Uint8Array(await rr.arrayBuffer()));
      } catch (e) {
        // El render falló: si hay un PDF adjuntado a mano de respaldo, se usa;
        // si no, se corta aquí con un error explícito. Mandar el email sin
        // adjunto y sin avisar sería peor que el 403 — el usuario creería que
        // el contrato salió y no salió nada.
        if (pdfManual) { pdfB64 = pdfManual; }
        else return json({ ok: false, error: 'no_se_pudo_generar_el_pdf: ' + String((e as Error)?.message ?? e) }, 502);
      }
    } else {
      pdfB64 = pdfManual;
    }

    const r = await fetch(SITIO + '/contracts/api/send_email.php', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'X-Render-Secret': RENDER_SECRET },
      body: JSON.stringify({ to, subject, message, filename, pdf_base64: pdfB64 }),
    });
    const t = await r.text();
    if (!r.ok || !t.includes('"ok":true')) return json({ ok: false, error: 'send_email: ' + t.slice(0, 300) }, 502);
    return json({ ok: true });
  } catch (e) {
    return json({ ok: false, error: String((e as Error)?.message ?? e) }, 500);
  }
});
