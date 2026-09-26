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
const ANON = Deno.env.get('SUPABASE_ANON_KEY')!;
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

    // Cliente CON LA SESIÓN DEL USUARIO (26-sep-2026, revisión previa #106, Seguridad):
    // lo que decide si puede es la RLS, igual que si lo hiciera desde su pantalla.
    // `admin` (service role) queda solo para el registro de envíos.
    const usuario = createClient(URL_SB, ANON, {
      global: { headers: { Authorization: 'Bearer ' + jwt } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    // Solo el equipo: un comprador del portal también tiene sesión de Supabase, y sin
    // esto podía mandar cualquier HTML/PDF a cualquier dirección con el correo de Lawang.
    const { data: esAgente, error: eAg } = await usuario.rpc('es_agente');
    if (eAg || esAgente !== true) return json({ ok: false, error: 'solo_equipo' }, 403);

    const body = await req.json().catch(() => ({}));
    const to = String(body.to ?? '').trim();

    // Clave usuario+destinatario (26-sep-2026): el aviso de anulación y las copias del
    // firmado van a VARIOS firmantes seguidos, y con la clave solo por usuario el segundo
    // correo caía en 429. Sigue frenando el doble clic sobre el mismo destinatario.
    const ahora = Date.now();
    const claveCd = quien.user.id + '|' + to.toLowerCase();
    const previo = ultimoEnvio.get(claveCd) ?? 0;
    if (ahora - previo < COOLDOWN_MS) return json({ ok: false, error: 'espera_un_momento' }, 429);
    ultimoEnvio.set(claveCd, ahora);
    const subject = String(body.subject ?? '');
    const message = String(body.message ?? '');
    const filename = String(body.filename ?? 'contrato.pdf');
    const html = String(body.html ?? '');
    const pdfManual = String(body.pdf_base64 ?? '');
    // ancla para el registro de envíos (correos_enviados): el que llama dice de
    // qué contrato/factura sale el correo. Solo uuids válidos — cualquier otra
    // cosa se ignora y el envío sigue: el log nunca puede vetar un correo.
    const esUuid = (s: string) => /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s);
    const contratoId = esUuid(String(body.contrato_id ?? '')) ? String(body.contrato_id) : null;
    const facturaId  = esUuid(String(body.factura_id ?? ''))  ? String(body.factura_id)  : null;
    // Correo de SOLO TEXTO (`attach:false`) y `via` (26-sep-2026, LAW-336 pieza 5, paso E):
    // el enlace de firma, el aviso de anulación y la copia del firmado sin PDF salían del
    // navegador directo a send_email.php y era el navegador quien escribía la fila de
    // `correos_enviados` — podía apuntar un envío que no salió. Ahora pasan por aquí y la
    // fila la escribe el servidor tras el envío real. Solo con contrato: un correo de
    // texto libre sin documento al que colgarse no tiene por qué salir por esta puerta.
    const VIAS = ['enlace_firma', 'aviso_anulacion', 'firma'];
    const via = VIAS.includes(String(body.via ?? '')) ? String(body.via) : null;
    const soloTexto = body.attach === false;
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(to)) return json({ ok: false, error: 'destinatario_invalido' }, 400);
    if (soloTexto && (!contratoId || !message.trim())) return json({ ok: false, error: 'texto_sin_contrato_o_mensaje' }, 400);
    // Una factura va SIEMPRE con su PDF: marcarla enviada fija número, emisor y la fecha que cuenta
    // para plazos de cobro — no puede hacerlo un correo que no la llevaba (Administración, capa 1, 26-sep).
    if (soloTexto && facturaId) return json({ ok: false, error: 'factura_requiere_pdf' }, 400);
    if (!soloTexto && !html && !pdfManual) return json({ ok: false, error: 'falta_html_o_pdf' }, 400);
    // La factura tiene que ser SUYA (visible por RLS) ANTES de enviar: más abajo se
    // apunta el envío y se marca `enviada` con ese id, y `enviada=true` congela número
    // y emisor y veta el borrado — no puede hacerlo quien no puede ver la factura.
    if (facturaId) {
      const { data: fv, error: eF } = await usuario.from('facturas').select('id').eq('id', facturaId).maybeSingle();
      if (eF || !fv) return json({ ok: false, error: 'factura_no_visible' }, 403);
    }
    // Y el contrato igual: el registro de envíos se lee como «quién lo tiene» y lo
    // escribe el service role — sin esto, cualquiera del equipo dejaba un envío falso
    // en un contrato que no puede ver (code-review, 26-sep-2026).
    if (contratoId) {
      const { data: cv, error: eC } = await usuario.from('contratos').select('id').eq('id', contratoId).maybeSingle();
      if (eC || !cv) return json({ ok: false, error: 'contrato_no_visible' }, 403);
    }

    let pdfB64 = '';
    if (soloTexto) {
      // nada que renderizar
    } else if (html) {
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
      body: JSON.stringify(soloTexto ? { to, subject, message, attach: false }
                                     : { to, subject, message, filename, pdf_base64: pdfB64 }),
    });
    const t = await r.text();
    if (!r.ok || !t.includes('"ok":true')) return json({ ok: false, error: 'send_email: ' + t.slice(0, 300) }, 502);

    // Registro de envíos (correos_enviados): el correo YA salió — si el log
    // falla se anota en consola y se devuelve ok igualmente, porque devolver
    // error aquí haría que el usuario lo reenviara por duplicado.
    // `registrado:false` se devuelve (no error) para que la pantalla lo DIGA: esta tabla se
    // lee como «quién lo tiene», y una fila que falta acaba en un reenvío duplicado.
    let registrado: boolean | undefined;
    if (contratoId || facturaId) {
      const { error: eLog } = await admin.from('correos_enviados').insert({
        contrato_id: contratoId, factura_id: facturaId,
        para: to, asunto: subject,
        via: facturaId ? 'factura' : (via ?? 'manual'),
        enviado_por: quien.user.email ?? null,
      });
      registrado = !eLog;
      if (eLog) console.error('correos_enviados: ' + eLog.message);
    }
    // Marcar la factura como enviada AQUÍ, en el servidor y justo tras el envío
    // (26-sep-2026, «Operaciones atómicas»): antes lo hacía la pantalla en una segunda
    // llamada y, si fallaba, la factura seguía «sin enviar» y se reenviaba. Va con la
    // sesión del usuario: su RLS y los guardarraíles de facturas (que se apartan con
    // auth.uid() nulo) se aplican igual que antes. Si no se puede marcar, se DICE
    // (`marcada:false`) sin devolver error: el correo ya salió y reenviarlo sería peor.
    // La fecha es la del PRIMER envío (Administración, 26-sep-2026): es la que cuenta
    // para plazos y reclamaciones de cobro, y un reenvío no la mueve. Por eso el update
    // solo toca facturas aún sin enviar, y un reenvío (0 filas) que encuentra la factura
    // ya marcada cuenta como marcada.
    // Desde el 26-sep-2026 (frontera frontend/backend, LAW-336) la marca va por la RPC
    // `factura_marca_enviada`: `authenticated` deja de poder escribir en `facturas`
    // directamente, y un update con la sesión del usuario dejaría de marcar SIN que nadie
    // lo notara (rev. previa #119, Datos). La RPC aplica la misma regla de edición, no
    // mueve la fecha de un reenvío y devuelve true si la factura queda marcada.
    let marcada: boolean | undefined;
    if (facturaId) {
      const { data: m, error: eM } = await usuario.rpc('factura_marca_enviada', { p_id: facturaId });
      marcada = !eM && m === true;
      if (!marcada) console.error('factura ' + facturaId + ' enviada pero SIN marcar: ' + (eM?.message ?? 'la RPC devolvió ' + String(m)));
    }
    return json({ ok: true, marcada, registrado });
  } catch (e) {
    return json({ ok: false, error: String((e as Error)?.message ?? e) }, 500);
  }
});
