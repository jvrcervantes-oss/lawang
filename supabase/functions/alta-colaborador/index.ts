// alta-colaborador — la puerta pública de la guía /formacion/ (24-sep-2026).
//
// Tres acciones, todas SIN sesión:
//   · codigo    → manda un código de 6 dígitos al email (demuestra que el buzón es suyo)
//   · solicitud → COMERCIAL (5 %): con el código, deja una solicitud de alta. NO crea
//                 usuario: la activa el owner con un clic (admin-usuarios, accion
//                 'activar_solicitud'). Motivo (revisión previa #61, Seguridad+Legal+Datos):
//                 cualquier fila activa de `usuarios` pasa es_agente() y puede LEER el
//                 directorio de compradores; ese acceso no se da sin una persona detrás.
//   · referir   → REFERIDO (1 %): sin cuenta, registra a un contacto suyo. Queda a su
//                 nombre en `referidos_contactos` (referido_email = atribución).
//
// Reglas que no se tocan:
//   · Respuesta IDÉNTICA exista o no el email (no sirve para averiguar quién es cliente
//     o equipo). La diferencia solo se le cuenta al owner por email.
//   · Límites en BASE, no en memoria del isolate: por IP (hash) y global por hora.
//   · Nada del body llega a un insert sin pasar por la lista blanca y su longitud máxima.
//   · Nada de datos personales en console.* salvo el email (mismo criterio que el resto).
import { createClient } from 'jsr:@supabase/supabase-js@2';

const URL_SB = Deno.env.get('SUPABASE_URL')!;
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const admin = createClient(URL_SB, SERVICE);
const RENDER_SECRET = Deno.env.get('RENDER_SECRET') || '';
const SITIO = (Deno.env.get('SITIO_URL') || 'https://lawangproperties.com').replace(/\/$/, '');
const OWNER = Deno.env.get('ESTUDIO_EMAIL') || 'jcervantes@lawangproperties.com';

const ORIGENES = ['https://lawangproperties.com', 'https://www.lawangproperties.com'];
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

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const MAX_CODIGOS_IP_HORA = 5;
const MAX_CODIGOS_GLOBAL_HORA = 60;
const MAX_REFERIDOS_DIA = 15;
const MAX_CODIGOS_EMAIL_HORA = 3;

async function sha256(s: string) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, '0')).join('');
}
// Texto libre del formulario: recortado, sin controles, con tope de longitud.
function txt(v: unknown, max: number) {
  return String(v ?? '').replace(/[\u0000-\u001f\u007f]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, max);
}
function hace(min: number) { return new Date(Date.now() - min * 60_000).toISOString(); }

// Idioma de los correos AL COLABORADOR (25-sep-2026): la guía existe en /formacion/ (es),
// /formacion/en/ y /formacion/fr/, y cada copia manda el suyo. Lista blanca; cualquier otra
// cosa es 'es'. Los correos al owner siguen en español. El 'es' conserva la línea en inglés
// que ya llevaba.
type Idioma = 'es' | 'en' | 'fr';
const idiomaDe = (v: unknown): Idioma => (v === 'en' || v === 'fr' ? v : 'es');
const guiaUrl = (l: Idioma) => SITIO + '/formacion/' + (l === 'es' ? '' : l + '/');
const MSG = {
  es: {
    volver: 'Volver a la guía',
    codigoAsunto: 'Tu código de verificación — Lawang',
    codigo: (c: string) => 'Tu código de verificación es ' + c + '. Caduca en 10 minutos.\n\n' +
      'Your verification code is ' + c + '. It expires in 10 minutes.\n\n' +
      'Si no lo has pedido tú, ignora este correo. / If you did not request it, ignore this email.',
    solicitudAsunto: 'Hemos recibido tu solicitud — Lawang',
    solicitud: (n: string) => 'Hola ' + n + ',\n\nHemos recibido tu solicitud para trabajar como comercial con Lawang. ' +
      'La revisamos y, cuando la activemos, te llegará un correo para crear tu contraseña y entrar en la intranet.\n\n' +
      'We have received your request to work with Lawang as a sales associate. Once it is approved you will get an email to set your password.',
    referidoAsunto: 'Contacto registrado — Lawang',
    referido: (n: string, c: string) => 'Hola ' + n + ',\n\nHemos registrado a ' + c + ' a tu nombre. ' +
      'Nuestro equipo se pondrá en contacto con él. Si compra, te escribiremos para tu comisión de referido.\n\n' +
      'We have registered ' + c + ' under your name. Our team will get in touch with them.',
  },
  en: {
    volver: 'Back to the guide',
    codigoAsunto: 'Your verification code — Lawang',
    codigo: (c: string) => 'Your verification code is ' + c + '. It expires in 10 minutes.\n\n' +
      'If you did not request it, ignore this email.',
    solicitudAsunto: 'We have received your request — Lawang',
    solicitud: (n: string) => 'Hi ' + n + ',\n\nWe have received your request to work with Lawang as a sales associate. ' +
      'We will review it and, once it is approved, you will get an email to set your password and log in to the intranet.',
    referidoAsunto: 'Contact registered — Lawang',
    referido: (n: string, c: string) => 'Hi ' + n + ',\n\nWe have registered ' + c + ' under your name. ' +
      'Our team will get in touch with them. If they buy, we will write to you about your referral commission.',
  },
  fr: {
    volver: 'Retour au guide',
    codigoAsunto: 'Votre code de vérification — Lawang',
    codigo: (c: string) => 'Votre code de vérification est ' + c + '. Il expire dans 10 minutes.\n\n' +
      "Si vous ne l'avez pas demandé, ignorez cet e-mail.",
    solicitudAsunto: 'Nous avons bien reçu votre demande — Lawang',
    solicitud: (n: string) => 'Bonjour ' + n + ',\n\nNous avons bien reçu votre demande pour travailler comme commercial avec Lawang. ' +
      "Nous allons l'examiner et, dès qu'elle sera validée, vous recevrez un e-mail pour créer votre mot de passe et accéder à l'intranet.",
    referidoAsunto: 'Contact enregistré — Lawang',
    referido: (n: string, c: string) => 'Bonjour ' + n + ',\n\nNous avons enregistré ' + c + ' à votre nom. ' +
      "Notre équipe va prendre contact avec cette personne. Si elle achète, nous vous écrirons au sujet de votre commission d'apporteur.",
  },
} as const;

async function enviar(to: string, subject: string, message: string, ctaUrl: string, ctaTexto: string) {
  if (!RENDER_SECRET) { console.error('alta-colaborador: RENDER_SECRET no configurado, no se envía a <' + to + '>'); return false; }
  try {
    const ac = new AbortController();
    const t = setTimeout(() => ac.abort(), 8000);
    try {
      const r = await fetch(SITIO + '/contracts/api/send_email.php', {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'X-Render-Secret': RENDER_SECRET },
        body: JSON.stringify({ to, subject, message, contacto: 'sales', attach: false, cta_url: ctaUrl, cta_texto: ctaTexto }),   // sin attach:false, send_email.php exige PDF y da 400
        signal: ac.signal,
      });
      if (!r.ok) console.error('alta-colaborador send_email http ' + r.status + ' <' + to + '>');
      return r.ok;
    } finally { clearTimeout(t); }
  } catch (e) {
    console.error('alta-colaborador send_email excepcion <' + to + '>: ' + String((e as Error)?.message ?? e));
    return false;
  }
}

// Comprueba el código en la BASE, de forma atómica (RPC colaborador_verifica): compara
// y suma el intento en una sola sentencia con FOR UPDATE, así que N peticiones en
// paralelo no se saltan el tope de 5. Vale cualquiera de los 3 últimos códigos vigentes.
async function verifica(email: string, codigo: string): Promise<boolean> {
  if (!/^\d{6}$/.test(codigo)) return false;
  const { data, error } = await admin.rpc('colaborador_verifica', { p_email: email, p_hash: await sha256(codigo) });
  if (error) { console.error('alta-colaborador verifica <' + email + '>: ' + error.message); return false; }
  return data === true;
}

Deno.serve(async (req) => {
  const cors = corsFor(req);
  const json = (o: unknown, s = 200) =>
    new Response(JSON.stringify(o), { status: s, headers: { ...cors, 'content-type': 'application/json' } });
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ ok: false, error: 'metodo' }, 405);

  let email = '';
  try {
    const body = await req.json().catch(() => ({}));
    const accion = String(body.accion ?? '');
    const idioma = idiomaDe(body.idioma);
    const m = MSG[idioma];
    email = String(body.email ?? '').trim().toLowerCase().slice(0, 160);
    // honeypot: un campo que una persona no ve; si viene relleno, se contesta
    // «ok» sin hacer nada (no le decimos al bot que lo hemos cazado)
    if (String(body.web ?? '').trim()) return json({ ok: true });
    if (!EMAIL_RE.test(email)) return json({ ok: false, error: 'email' }, 400);

    // cf-connecting-ip la pone el proxy y el cliente no la puede falsear; si falta, la
    // ÚLTIMA entrada de x-forwarded-for (la añade el proxy), nunca la primera.
    const xff = (req.headers.get('x-forwarded-for') ?? '').split(',').map((x) => x.trim()).filter(Boolean);
    const ip = (req.headers.get('cf-connecting-ip') ?? '').trim() || xff[xff.length - 1] || 'sin-ip';
    const ipHash = await sha256('lawang-alta:' + ip);

    // ── 1. código ─────────────────────────────────────────────────────────
    if (accion === 'codigo') {
      const [{ count: porIp }, { count: global }, { data: ultimo }, { count: porEmail }] = await Promise.all([
        admin.from('colaboradores_verificaciones').select('id', { count: 'exact', head: true })
          .eq('ip_hash', ipHash).gte('creado_at', hace(60)),
        admin.from('colaboradores_verificaciones').select('id', { count: 'exact', head: true })
          .gte('creado_at', hace(60)),
        admin.from('colaboradores_verificaciones').select('creado_at').eq('email', email)
          .order('creado_at', { ascending: false }).limit(1).maybeSingle(),
        admin.from('colaboradores_verificaciones').select('id', { count: 'exact', head: true })
          .eq('email', email).gte('creado_at', hace(60)),
      ]);
      // Todos los frenos contestan lo mismo que el éxito: no delatan nada.
      if ((porIp ?? 0) >= MAX_CODIGOS_IP_HORA) return json({ ok: true });
      if ((porEmail ?? 0) >= MAX_CODIGOS_EMAIL_HORA) return json({ ok: true });
      if ((global ?? 0) >= MAX_CODIGOS_GLOBAL_HORA) {
        console.error('alta-colaborador: tope global de códigos por hora alcanzado');
        return json({ ok: true });
      }
      if (ultimo && Date.now() - new Date(ultimo.creado_at).getTime() < 60_000) return json({ ok: true });

      const codigo = String(100000 + (crypto.getRandomValues(new Uint32Array(1))[0] % 900000));
      const { error } = await admin.from('colaboradores_verificaciones').insert({
        email, codigo_hash: await sha256(codigo), ip_hash: ipHash,
        expira_at: new Date(Date.now() + 10 * 60_000).toISOString(),
      });
      if (error) { console.error('alta-colaborador insert codigo <' + email + '>: ' + error.message); return json({ ok: false, error: 'no_disponible' }, 500); }
      await enviar(email, m.codigoAsunto, m.codigo(codigo), guiaUrl(idioma), m.volver);
      return json({ ok: true });
    }

    // ── 2 y 3 necesitan el código ─────────────────────────────────────────
    if (accion !== 'solicitud' && accion !== 'referir') return json({ ok: false, error: 'accion' }, 400);
    if (body.privacidad !== true) return json({ ok: false, error: 'privacidad' }, 400);
    const nombre = txt(body.nombre, 120);
    const telefono = txt(body.telefono, 40);
    if (nombre.length < 2) return json({ ok: false, error: 'nombre' }, 400);
    // Referido: todo lo que se puede rechazar se comprueba ANTES de gastar el código;
    // si no, un error de formulario obligaba a pedir otro (y gastaba cupo).
    const clienteNombre = txt(body.cliente_nombre, 120);
    const clienteEmail = String(body.cliente_email ?? '').trim().toLowerCase().slice(0, 160);
    const clienteTel = txt(body.cliente_telefono, 40);
    const clientePais = txt(body.cliente_pais, 60);
    const interes = txt(body.interes, 600);
    if (accion === 'referir') {
      if (clienteNombre.length < 2) return json({ ok: false, error: 'cliente_nombre' }, 400);
      if (clienteEmail && !EMAIL_RE.test(clienteEmail)) return json({ ok: false, error: 'cliente_email' }, 400);
      if (!clienteEmail && clienteTel.length < 6) return json({ ok: false, error: 'cliente_contacto' }, 400);
      if (body.consentimiento !== true) return json({ ok: false, error: 'consentimiento' }, 400);
      const { count: hoy } = await admin.from('referidos_contactos').select('id', { count: 'exact', head: true })
        .eq('referido_email', email).gte('creado_at', hace(24 * 60));
      if ((hoy ?? 0) >= MAX_REFERIDOS_DIA) return json({ ok: false, error: 'limite' }, 429);
    }
    if (!await verifica(email, String(body.codigo ?? '').trim())) return json({ ok: false, error: 'codigo' }, 400);

    // ── 2. solicitud de alta de comercial ─────────────────────────────────
    if (accion === 'solicitud') {
      const pais = txt(body.pais, 60);
      const mensaje = txt(body.mensaje, 600);
      const { data: yaUsuario } = await admin.from('usuarios').select('user_id').eq('email', email).maybeSingle();
      let nota = '';
      if (yaUsuario) {
        nota = 'OJO: este email YA es usuario de la intranet. No se ha creado solicitud.';
      } else {
        const { error } = await admin.from('solicitudes_colaborador').insert({ email, nombre, telefono, pais, mensaje });
        if (error && !/duplicate|unique/i.test(error.message)) {
          console.error('alta-colaborador insert solicitud <' + email + '>: ' + error.message);
          return json({ ok: false, error: 'no_disponible' }, 500);
        }
        if (error) nota = 'Ya tenía una solicitud pendiente; no se ha duplicado.';
      }
      await enviar(OWNER, 'Nueva solicitud de comercial — ' + nombre,
        'Ha llegado una solicitud de alta como COMERCIAL (5 %) desde la guía de formación.\n\n' +
        'Nombre: ' + nombre + '\nEmail (verificado): ' + email + '\nTeléfono: ' + (telefono || '—') +
        '\nPaís: ' + (pais || '—') + '\nIdioma de la guía: ' + idioma + '\nMensaje: ' + (mensaje || '—') + '\n\n' +
        (nota ? nota + '\n\n' : '') +
        'Actívala o descártala en la intranet → Usuarios → Solicitudes de alta.', SITIO + '/intranet/v4/usuarios/', 'Revisar en la intranet');
      if (!yaUsuario) await enviar(email, m.solicitudAsunto, m.solicitud(nombre.split(' ')[0]), guiaUrl(idioma), m.volver);
      return json({ ok: true });
    }

    // ── 3. referido: registra un contacto suyo (validado arriba) ──────────
    const { error } = await admin.from('referidos_contactos').insert({
      referido_email: email, referido_nombre: nombre, referido_telefono: telefono,
      cliente_nombre: clienteNombre, cliente_email: clienteEmail || null, cliente_telefono: clienteTel || null,
      cliente_pais: clientePais || null, interes: interes || null, consentimiento: true,
    });
    if (error) { console.error('alta-colaborador insert referido <' + email + '>: ' + error.message); return json({ ok: false, error: 'no_disponible' }, 500); }
    await enviar(OWNER, 'Nuevo contacto de un referido — ' + clienteNombre,
      'Un referido (1 %) ha registrado un contacto desde la guía de formación.\n\n' +
      'REFERIDO\nNombre: ' + nombre + '\nEmail (verificado): ' + email + '\nTeléfono: ' + (telefono || '—') + '\n\n' +
      'CLIENTE\nNombre: ' + clienteNombre + '\nEmail: ' + (clienteEmail || '—') + '\nTeléfono: ' + (clienteTel || '—') +
      '\nPaís: ' + (clientePais || '—') + '\nQué busca: ' + (interes || '—') + '\n\n' +
      'El referido declara que el cliente ha aceptado que Lawang le contacte.\n' +
      'Lo tienes en la intranet → Usuarios → Contactos de referidos.', SITIO + '/intranet/v4/usuarios/', 'Revisar en la intranet');
    await enviar(email, m.referidoAsunto, m.referido(nombre.split(' ')[0], clienteNombre), guiaUrl(idioma), m.volver);
    return json({ ok: true });
  } catch (e) {
    console.error('alta-colaborador excepcion <' + email + '>: ' + String((e as Error)?.message ?? e));
    return json({ ok: false, error: 'no_disponible' }, 500);
  }
});
