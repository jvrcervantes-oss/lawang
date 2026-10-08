// envia-correo — envío de correo de una instancia del AxisWorks ERP por el SMTP del BUZÓN DEL
// PROPIO CLIENTE (decisión del owner, 25-sep-2026, encargos/20260925_estudio_erp_instalador.md).
//
// Implementa el CONTRATO de proyectos/Lawang/contracts/api/send_email.php (mismo cuerpo, mismas
// cabeceras, mismas respuestas). OJO — apuntar config_instancia.url_envio_correo aquí SOLO conecta
// a los llamantes de la BASE (pg_net). Las Edge (firma-submit, factura-vencimiento,
// send-contract-email, avisos-manager, comunicados-envio, alta-colaborador, admin-usuarios) y el
// navegador (contracts/app.html, v4/comunicacion.js) llevan la ruta '/contracts/api/send_email.php'
// escrita a fuego: hay que repuntarlos (ver README → «Llamantes»), o en una instancia sin PHP fallan.
//
// Contrato (idéntico salvo lo marcado ⚠):
//   POST JSON {to, subject?, message?, attach?=true, pdf_base64?, html?, filename?, encabezado?,
//              etiqueta?, contacto?, cta_url?, cta_texto?, preview?}
//   200 {ok:true} · preview → 200 {ok:true, html}
//   400 validación · 401 sin credencial · 403 origen · 405 método · 500 SMTP/config
//   502 PDF no generado · 503 envíos en pausa (mantenimiento, fail-closed)
//   Autorización, en este orden (como el PHP):
//     1. X-Render-Secret == ENVIO_CORREO_SECRET (o RENDER_SECRET si aquélla no existe)
//                                                  → vía «servicio» (Edge sin sesión)
//     2. X-Suite-Token o Authorization: Bearer    → vía «sesion»: usuario vivo en Auth Y fila activa
//        en public.usuarios (un comprador del portal con sesión NO puede enviar)
//     3. aviso interno: solo correo de TEXTO (attach:false) a uno de los buzones de aviso de la
//        instancia (config email_avisos_soporte|sistema|reservas). Con ENVIO_AVISO_SECRET definido
//        hace falta la cabecera X-Aviso-Secret (vía «aviso»); sin esa variable sigue la antigua
//        puerta anónima (vía «aviso-interno», lo usa pg_net), con freno. ⚠ Más estrecha que el PHP
//        (todo @dominio): motivo en el manejador. Se le quitan encabezado, etiqueta y cta_*.
//   ⚠ Tope de adjunto: 34 MB de base64 (el PHP, 140 MB). Motivo en valida.ts → LIMITES.
//   contacto:'sales' se pasa a la plantilla en Marca.contacto; cada plantilla decide qué hace con él.
//   Cabecera opcional X-Llamante: se anota (saneada, 40 car.) en la línea de log; no cambia el contrato.
//
// Secretos: SMTP_HOST, SMTP_PORT (465), SMTP_USER, SMTP_PASS, SMTP_FROM, SMTP_FROM_NAME?,
// ENVIO_CORREO_SECRET?, ENVIO_AVISO_SECRET?, RENDER_SECRET (salida hacia el servicio de PDFs; y de
// entrada solo mientras no exista ENVIO_CORREO_SECRET), PDF_SERVICE_URL?. SUPABASE_URL /
// SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY los inyecta el runtime. Detalle en README.md.
//
// Log: una línea JSON por petición con vía, estado, DOMINIO del destinatario y, si llegó, el llamante.
// Nunca el asunto, el cuerpo, la dirección completa ni el texto libre del servidor SMTP (del fallo de
// SMTP solo se anotan el código de nodemailer, el numérico y el estado mejorado).

// @deno-types="npm:@types/nodemailer@6.4.17"
import nodemailer from 'npm:nodemailer@6.9.16';
import { Buffer } from 'node:buffer';
import {
  LIMITES, type Peticion, type Fallo, esFallo, leePeticion, validaTextos, validaEnvio, deduceCta,
  esDominioPropio, normalizaDominio, decodificaBase64, esPdf, esEmail, ctaPermitida, tieneControl,
  TEXTO_PAUSA, saneaLlamante, viaServicio, viaAviso, describeFalloSmtp,
  VIAS_PLANTILLA, validaPlantillaPeticion, limpiaValor, catalogoDe, validaTextoPlantilla, componeCorreo, CTA_PORTAL_TEXTO,
  type TextoPlantilla,
} from './valida.ts';
import { plantillaHtml, plantillaTexto, type Marca, type SociedadMarca } from './plantilla.ts';
import { resuelve, textoFabrica } from './plantillas_fabrica.ts';

const env = (k: string) => (Deno.env.get(k) ?? '').trim();
const SUPA_URL = env('SUPABASE_URL').replace(/\/$/, '');
const SUPA_ANON = env('SUPABASE_ANON_KEY');
const SUPA_SERVICE = env('SUPABASE_SERVICE_ROLE_KEY');

// ── configuración de la instancia (dueño: config_instancia; aquí solo se lee) ─────────────────
type Config = { marca: string; dominio: string; urlIntranet: string; origen: string; logoUrl?: string; asuntoDefecto: string; avisos: string[] };
let cache: { t: number; c: Config } | null = null;

async function config(): Promise<Config | null> {
  if (cache && Date.now() - cache.t < 60_000) return cache.c;
  if (!SUPA_URL || !SUPA_SERVICE) return null;
  try {
    const r = await fetch(SUPA_URL + '/rest/v1/config_instancia?select=clave,valor&clave=in.(marca,dominio_web,url_intranet,logo_correo_url,asunto_por_defecto,email_avisos_soporte,email_avisos_sistema,email_avisos_reservas)', {
      headers: { apikey: SUPA_SERVICE, Authorization: 'Bearer ' + SUPA_SERVICE },
      signal: AbortSignal.timeout(6000),
    });
    if (!r.ok) return null;
    const filas = await r.json() as { clave: string; valor: unknown }[];
    const v = (k: string) => { const f = filas.find((x) => x.clave === k); return typeof f?.valor === 'string' ? f.valor.trim() : ''; };
    const dominio = normalizaDominio(v('dominio_web'));
    let origen = '';
    try { origen = new URL(v('url_intranet')).origin; } catch { /* sin url_intranet válida: sin CORS */ }
    if (!dominio || !origen.startsWith('https://')) return null;
    const logo = v('logo_correo_url');
    const asunto = v('asunto_por_defecto');   // con saltos de línea o demasiado largo se ignora: manda el de fábrica
    const c: Config = { marca: v('marca') || dominio, dominio, urlIntranet: v('url_intranet'), origen,
      logoUrl: /^https:\/\//.test(logo) ? logo : undefined,
      asuntoDefecto: asunto !== '' && !tieneControl(asunto) && [...asunto].length <= LIMITES.asunto ? asunto : '',
      // Buzones de aviso: los ÚNICOS destinos de la vía 3 (ver manejador). Solo los del propio dominio.
      avisos: ['email_avisos_soporte', 'email_avisos_sistema', 'email_avisos_reservas'].map(v).map((x) => x.toLowerCase())
        .filter((x) => esEmail(x) && esDominioPropio(x, dominio)) };
    cache = { t: Date.now(), c };
    return c;
  } catch { return null; }
}

// ── respuesta ────────────────────────────────────────────────────────────────────────────────
// CORS: HAY llamantes de navegador (contracts/app.html → enlace de firma; v4/comunicacion.js →
// vista previa y envío; ambos con X-Suite-Token). Por eso se contesta CORS, pero SOLO al origen de
// la intranet de la instancia (config url_intranet), nunca `*` — marca: cors-lista, no cors-publico.
// Un Origin distinto → 403, que es la criba same-origin del PHP.
function cabeceras(origen: string | null): Headers {
  const h = new Headers({ 'Content-Type': 'application/json; charset=utf-8' });
  if (origen) {
    h.set('Access-Control-Allow-Origin', origen);
    h.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
    h.set('Access-Control-Allow-Headers', 'content-type, x-suite-token, authorization, apikey, x-client-info');
    h.set('Access-Control-Max-Age', '600');
    h.set('Vary', 'Origin');
  }
  return h;
}

function log(via: string, estado: number, to = '', llamante = '', plantilla?: { plantilla: string; version: string }) {
  const i = to.lastIndexOf('@');
  console.log(JSON.stringify({
    fn: 'envia-correo', via: via || 'ninguna', estado, dominio_destino: i > 0 ? to.slice(i + 1).toLowerCase() : '',
    ...(llamante ? { llamante } : {}), ...(plantilla ?? {}),
  }));
}

// ── autorización ─────────────────────────────────────────────────────────────────────────────
/** Vía 1: sesión viva en Auth y fila ACTIVA en public.usuarios leída con el JWT de quien llama
 *  (la RLS deja a cada uno leer su ficha). Mismo criterio que es_del_equipo() del PHP. */
async function esDelEquipo(jwt: string): Promise<boolean> {
  if (!SUPA_URL || !SUPA_ANON) return false;
  try {
    const cab = { apikey: SUPA_ANON, Authorization: 'Bearer ' + jwt };
    const r = await fetch(SUPA_URL + '/auth/v1/user', { headers: cab, signal: AbortSignal.timeout(10_000) });
    if (r.status !== 200) return false;
    const u = await r.json() as { id?: string };
    const uid = String(u?.id ?? '');
    if (!/^[0-9a-f-]{36}$/i.test(uid)) return false;
    const q = await fetch(SUPA_URL + '/rest/v1/usuarios?select=user_id&activo=is.true&user_id=eq.' + encodeURIComponent(uid),
      { headers: cab, signal: AbortSignal.timeout(10_000) });
    if (q.status !== 200) return false;
    const filas = await q.json();
    return Array.isArray(filas) && filas.length === 1 && filas[0]?.user_id === uid;
  } catch { return false; }
}

/** Modo mantenimiento: si no se puede preguntar, NO se envía (decisión del owner, 23-sep).
 *  Pregunta con la clave de servicio, que solo vive aquí (27-sep-2026): desde B-1 del encargo del canon
 *  (`erp/migraciones/20260927230000`) `anon` ya no ejecuta `envios_pausados`, y con la clave anon la respuesta
 *  era 401 → «en pausa» → ningún correo salía (consulta de deploy de Seguridad). No se le devuelve el permiso a anon. */
async function enviosPausados(): Promise<boolean> {
  if (!SUPA_URL || !SUPA_SERVICE) return true;
  try {
    const r = await fetch(SUPA_URL + '/rest/v1/rpc/envios_pausados', {
      method: 'POST', body: '{}',
      headers: { apikey: SUPA_SERVICE, Authorization: 'Bearer ' + SUPA_SERVICE, 'Content-Type': 'application/json' },
      signal: AbortSignal.timeout(6000),
    });
    if (r.status !== 200) return true;
    return (await r.text()).trim() !== 'false';
  } catch { return true; }
}

// ── PDF ──────────────────────────────────────────────────────────────────────────────────────
async function renderPdf(html: string): Promise<Uint8Array | null> {
  const url = env('PDF_SERVICE_URL'), secreto = env('RENDER_SECRET');
  if (!url || !secreto) return null;
  try {
    const r = await fetch(url.replace(/\/$/, '') + '/render-pdf', {
      method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Render-Secret': secreto },
      body: JSON.stringify({ html }), signal: AbortSignal.timeout(40_000),
    });
    const b = new Uint8Array(await r.arrayBuffer());
    if (r.status !== 200 || !esPdf(b)) { console.error('envia-correo: render-pdf HTTP ' + r.status); return null; }
    return b;
  } catch (e) { console.error('envia-correo: render-pdf ' + (e as Error).name); return null; }
}

// ── SMTP ─────────────────────────────────────────────────────────────────────────────────────
/** Supabase Edge BLOQUEA la salida a los puertos 25 y 587 (docs «Edge Functions limits»,
 *  comprobado 25-sep-2026): solo sirve 465 con TLS implícito. Se valida aquí para dar un error
 *  claro en vez de un timeout. */
type Smtp = { host: string; port: number; user: string; pass: string; from: string; fromName: string };
function smtpConfig(): Smtp | { error: string } {
  const host = env('SMTP_HOST'), port = Number(env('SMTP_PORT') || '465');
  const user = env('SMTP_USER'), pass = env('SMTP_PASS'), from = env('SMTP_FROM');
  if (!host || !user || !pass || !esEmail(from)) return { error: 'SMTP de la instancia sin configurar' };
  if (port !== 465) return { error: 'SMTP_PORT debe ser 465 (Supabase Edge bloquea 25 y 587)' };
  return { host, port, user, pass, from, fromName: env('SMTP_FROM_NAME') };
}

async function enviaSmtp(p: Peticion, marca: Marca, html: string, texto: string, pdf: Uint8Array | null, fromName: string,
  s: { host: string; port: number; user: string; pass: string; from: string }) {
  const t = nodemailer.createTransport({
    host: s.host, port: s.port, secure: true, auth: { user: s.user, pass: s.pass },
    connectionTimeout: 15_000, greetingTimeout: 15_000, socketTimeout: 60_000,
  });
  try {
    await t.sendMail({
      from: { name: fromName || marca.marca, address: s.from },
      to: p.to,                       // una sola dirección ya validada (esEmail)
      subject: p.subject,             // sin caracteres de control (validaTextos); nodemailer lo codifica RFC 2047
      text: texto, html,
      textEncoding: 'base64',         // líneas de 76: el corte de línea >998 rompió DKIM en Lawang (ver PHP)
      attachments: pdf ? [{ filename: p.filename, content: Buffer.from(pdf), contentType: 'application/pdf' }] : [],
      disableFileAccess: true, disableUrlAccess: true,
    });
  } finally { t.close(); }
}

// Freno de la vía 3: como mucho AVISOS_MAX en AVISOS_VENTANA_MS por isolate. Los avisos legítimos
// son pocos al día (soporte con su propio antirrebote de 2 min, almacenamiento nocturno).
const AVISOS_MAX = 20, AVISOS_VENTANA_MS = 10 * 60_000;
let avisosRecientes: number[] = [];
function frenoAvisoInterno(): boolean {
  const ahora = Date.now();
  avisosRecientes = avisosRecientes.filter((t) => ahora - t < AVISOS_VENTANA_MS);
  if (avisosRecientes.length >= AVISOS_MAX) return false;
  avisosRecientes.push(ahora);
  return true;
}

// ── plantillas de correo (S5.2, encargos/20260930_erp_ajustes_pantalla.md → «Plan de S5») ─────────────────────────────────────
// La petición trae `plantilla` + ids (+ `vars` de texto). Los datos los lee esta edge de la base (plantillas_fabrica.ts → resuelve);
// el texto es el de la fila ACTIVA y válida de `correo_plantillas`, y si no (inactiva, inválida, tabla ausente o ilegible) el de
// fábrica, que es el que componían los llamantes. Nunca un 500 por la plantilla. La respuesta lleva {plantilla, version}: el
// llamante (único escritor de correos_enviados) guarda ESO y nunca el texto renderizado, que puede llevar un enlace con token.
const SERVICIO = () => ({ apikey: SUPA_SERVICE, Authorization: 'Bearer ' + SUPA_SERVICE });
type Fila = { activa: unknown; asunto: unknown; cuerpo: unknown; cuerpo_alt: unknown; variables: unknown; version: unknown };

async function filaPlantilla(clave: string): Promise<Fila | null> {
  if (!SUPA_URL || !SUPA_SERVICE) return null;
  try {
    const r = await fetch(SUPA_URL + '/rest/v1/correo_plantillas?select=activa,asunto,cuerpo,cuerpo_alt,variables,version&clave=eq.' + encodeURIComponent(clave),
      { headers: SERVICIO(), signal: AbortSignal.timeout(6000) });
    if (!r.ok) { await r.text().catch(() => ''); console.error('envia-correo: correo_plantillas HTTP ' + r.status + ' (texto de fábrica)'); return null; }
    const filas = await r.json();
    return Array.isArray(filas) && filas.length === 1 ? filas[0] as Fila : null;
  } catch { return null; }
}

/** Lectura de datos para `resuelve`: GET a PostgREST con la clave de servicio. Si no es 200 lanza (la edge responde 502). */
async function leeDato(ruta: string): Promise<unknown> {
  const r = await fetch(SUPA_URL + '/rest/v1/' + ruta, { headers: SERVICIO(), signal: AbortSignal.timeout(8000) });
  if (r.status !== 200) { await r.text().catch(() => ''); throw new Error('HTTP ' + r.status); }
  return await r.json();
}

/** Identifica la versión del texto de FÁBRICA que salió (8 hex de su SHA-256): si cambia el texto de fábrica, cambia la versión. */
async function huellaFabrica(t: TextoPlantilla): Promise<string> {
  const b = new TextEncoder().encode([t.asunto, t.cuerpo, t.cuerpo_alt ?? ''].join('\u0000'));
  const h = [...new Uint8Array(await crypto.subtle.digest('SHA-256', b))].map((x) => x.toString(16).padStart(2, '0')).join('');
  return 'f:' + h.slice(0, 8);
}

type Compuesta = { subject: string; message: string; cta: { url: string; texto: string }; plantilla: string; version: string };

async function componePlantilla(p: Peticion, cfg: Config, portal: string): Promise<Compuesta | Fallo> {
  const vars: Record<string, string> = {};
  for (const [k, v] of Object.entries(p.vars ?? {})) vars[k] = limpiaValor(v) ?? '';
  let res: Awaited<ReturnType<typeof resuelve>>;
  try {
    res = await resuelve(p.plantilla, { contrato_id: p.contratoId, factura_id: p.facturaId, firma_id: p.firmaId }, p.to, vars, leeDato,
      { marca: cfg.marca, portal, dominio: cfg.dominio });
  } catch (e) {
    console.error('envia-correo: no se pudieron leer los datos de ' + p.plantilla + ' (' + String((e as Error)?.message ?? e).slice(0, 40) + ')');
    return { error: 'No se pudieron leer los datos del correo', status: 502 };
  }
  if (esFallo(res)) return res;

  let c: { subject: string; message: string } | null = null, version = '';
  const fila = await filaPlantilla(p.plantilla);
  if (fila && fila.activa === true) {
    const cat = catalogoDe(fila.variables);
    const t: TextoPlantilla = { asunto: fila.asunto as string, cuerpo: fila.cuerpo as string, cuerpo_alt: (fila.cuerpo_alt ?? null) as string | null };
    const errs = !cat ? ['catálogo ilegible']
      : [...validaTextoPlantilla(t.asunto, 'asunto', cat), ...validaTextoPlantilla(t.cuerpo, 'cuerpo', cat),
         ...(cat.variantes === 2 ? validaTextoPlantilla(t.cuerpo_alt, 'cuerpo_alt', cat) : [])];
    c = errs.length === 0 && typeof fila.version === 'number' ? componeCorreo(t, res.variante, res.vars) : null;
    if (c) version = 'v' + fila.version;
    else console.error('envia-correo: plantilla ' + p.plantilla + ' activa pero no válida (' + (errs[0] ?? 'no compone').slice(0, 80) + '): texto de fábrica');
  }
  if (!c) {
    const f = textoFabrica(p.plantilla);
    c = f ? componeCorreo(f, res.variante, res.vars) : null;
    if (!f || !c) return { error: 'La plantilla de fábrica no compone un correo válido', status: 500 };
    version = await huellaFabrica(f);
  }
  const cta = res.cta ?? { url: portal, texto: CTA_PORTAL_TEXTO };
  if (!ctaPermitida(cta.url, cfg.dominio)) return { error: 'El botón de la plantilla no está permitido', status: 500 };
  return { ...c, cta, plantilla: p.plantilla, version };
}

// ── marca por sociedad (reclamo de pago / facturas automáticas, encargos/20261008_lawang_reclamo_pago_parcela.md) ──────────────
// `sociedad` es la CLAVE de una fila activa de `public.sociedades` (lista cerrada: se lee de la base con la clave de servicio, jamás
// texto libre). Solo la vía de servicio puede pedirla: un navegador con sesión no elige con qué razón social sale un correo. Sin
// `sociedad`, el correo es el de siempre. Una clave pedida que no se puede resolver NO cae a la marca de Lawang: falla (400/502),
// porque un correo de Sandal Woods firmado como Lawang es justo el error que esto viene a quitar.
const CLAVE_SOCIEDAD = /^[a-z][a-z0-9_]{2,39}$/;

/** Logo de la sociedad como URL https ABSOLUTA de dominio propio (el de la instancia, un subdominio, o el storage de ESTE proyecto de
 *  Supabase); una ruta «/…» se resuelve contra el dominio de la instancia. Cualquier otra cosa → null (el nombre en texto, nunca un
 *  <img> hacia un tercero: sería un pixel de rastreo en el correo del comprador). */
export function logoDeSociedad(logo: unknown, dominio: string, supaUrl: string): string | null {
  if (typeof logo !== 'string') return null;
  const l = logo.trim();
  if (l === '' || tieneControl(l) || l.length > 500) return null;
  let u: URL;
  try { u = new URL(l.startsWith('/') && !l.startsWith('//') ? 'https://' + dominio + l : l); } catch { return null; }
  if (u.protocol !== 'https:' || u.username || u.password || u.port) return null;
  const h = u.hostname.toLowerCase();
  let supaHost = '';
  try { supaHost = new URL(supaUrl).hostname.toLowerCase(); } catch { /* sin URL de Supabase: solo el dominio propio */ }
  return h === dominio || h.endsWith('.' + dominio) || (supaHost !== '' && h === supaHost) ? u.href : null;
}

async function leeSociedad(clave: string, dominio: string): Promise<SociedadMarca | Fallo> {
  if (!CLAVE_SOCIEDAD.test(clave)) return { error: 'sociedad no válida', status: 400 };
  let filas: unknown;
  try {
    filas = await leeDato('sociedades?select=razon,marca,logo,tinta,folio&activa=is.true&clave=eq.' + encodeURIComponent(clave));
  } catch (e) {
    console.error('envia-correo: no se pudo leer la sociedad (' + String((e as Error)?.message ?? e).slice(0, 40) + ')');
    return { error: 'No se pudo leer la sociedad del correo', status: 502 };
  }
  const f = Array.isArray(filas) && filas.length === 1 ? filas[0] as { razon?: unknown; marca?: unknown; logo?: unknown; tinta?: unknown; folio?: unknown } : null;
  const razon = typeof f?.razon === 'string' ? f.razon.trim() : '';
  if (!f || razon === '' || tieneControl(razon)) return { error: 'sociedad desconocida o inactiva', status: 400 };
  const marcaTxt = typeof f.marca === 'string' ? f.marca.trim() : '';
  return { razon, marca: marcaTxt !== '' && !tieneControl(marcaTxt) ? marcaTxt : razon, logoUrl: logoDeSociedad(f.logo, dominio, SUPA_URL),
           // los colores se validan (#rrggbb) en paletaDe; aquí solo se pasa lo que tenga la forma de objeto / texto
           tinta: f.tinta && typeof f.tinta === 'object' && !Array.isArray(f.tinta) ? f.tinta as { deep?: unknown; primary?: unknown } : null,
           folio: typeof f.folio === 'string' ? f.folio : null };
}

// ── manejador ────────────────────────────────────────────────────────────────────────────────
export async function manejador(req: Request): Promise<Response> {
  const cfg = await config();
  const origen = req.headers.get('origin');
  const origenOk = origen && cfg && origen === cfg.origen ? origen : null;
  const resp = (cuerpo: unknown, status = 200) => new Response(JSON.stringify(cuerpo), { status, headers: cabeceras(origenOk) });
  const llamante = saneaLlamante(req.headers.get('x-llamante'));
  const fail = (f: Fallo, via = '', to = '') => { log(via, f.status, to, llamante); return resp({ ok: false, error: f.error, ...(f.extra ?? {}) }, f.status); };

  if (origen && !origenOk) return fail({ error: 'Origen no permitido', status: 403 });
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cabeceras(origenOk) });
  if (req.method !== 'POST') return fail({ error: 'Método no permitido', status: 405 });
  if (!cfg) return fail({ error: 'Configuración de la instancia no disponible (dominio_web / url_intranet)', status: 500 });

  // vías 1 y 2: por cabeceras
  let via = '';
  const secreto = (req.headers.get('x-render-secret') ?? '').trim();
  const secretoAviso = (req.headers.get('x-aviso-secret') ?? '').trim();
  let bearer = (req.headers.get('x-suite-token') ?? '').trim();
  if (!bearer) { const m = /^Bearer\s+(.+)$/i.exec((req.headers.get('authorization') ?? '').trim()); if (m) bearer = m[1].trim(); }
  via = viaServicio(secreto, env('ENVIO_CORREO_SECRET'), env('RENDER_SECRET'));
  if (!via && bearer && bearer !== SUPA_ANON && bearer !== SUPA_SERVICE && await esDelEquipo(bearer)) via = 'sesion';

  // cuerpo, con tope ANTES de parsear
  const largo = Number(req.headers.get('content-length') ?? '0');
  if (largo > LIMITES.cuerpo) return fail({ error: 'La petición es demasiado grande', status: 413 }, via);
  let crudo: string;
  try { crudo = await req.text(); } catch { return fail({ error: 'JSON inválido', status: 400 }, via); }
  if (crudo.length > LIMITES.cuerpo) return fail({ error: 'La petición es demasiado grande', status: 413 }, via);
  let entrada: unknown;
  try { entrada = JSON.parse(crudo || '[]'); } catch { return fail({ error: 'JSON inválido', status: 400 }, via); }
  const leida = leePeticion(entrada);
  if (esFallo(leida)) return fail(leida, via);
  const p = leida;
  // `sociedad`: fuera de lo que lee leePeticion (canon); se mira en el JSON crudo. Solo vía de servicio; por cualquier otra, 400.
  const sociedadPedida = entrada && typeof entrada === 'object' && !Array.isArray(entrada) ? (entrada as Record<string, unknown>).sociedad : undefined;
  let sociedad: SociedadMarca | null = null;
  if (sociedadPedida !== undefined && sociedadPedida !== null && sociedadPedida !== '') {
    if (via !== 'servicio' && via !== 'servicio-render') return fail({ error: 'sociedad solo se admite con el secreto del servicio', status: 400 }, via, p.to);
    const r = typeof sociedadPedida === 'string' ? await leeSociedad(sociedadPedida.trim(), cfg.dominio) : { error: 'sociedad no válida', status: 400 } as Fallo;
    if (esFallo(r)) return fail(r, via, p.to);
    sociedad = r;
  }
  if (p.subject === '') p.subject = cfg.asuntoDefecto || ('Documento — ' + cfg.marca);

  const marca: Marca = { marca: cfg.marca, dominio: cfg.dominio, remitente: env('SMTP_FROM') || ('no-reply@' + cfg.dominio), logoUrl: cfg.logoUrl, contacto: p.contacto, sociedad };
  const portal = new URL('/portal/', cfg.urlIntranet).href;

  // plantilla: solo con credencial de servicio o sesión (la vía de aviso interno no admite plantillas). Compone el texto y deja
  // subject/message/botón en `p` para que sigan las mismas validaciones y el mismo envío que el camino libre, que se conserva.
  let comp = null as Compuesta | null;   // se asigna dentro de aplicaPlantilla: la aserción evita que TS lo estreche a `null`
  const aplicaPlantilla = async (): Promise<Fallo | null> => {
    if (!VIAS_PLANTILLA.includes(via)) return { error: 'No autorizado: una plantilla exige sesión de la suite o el secreto del servicio.', status: 401 };
    const e = validaPlantillaPeticion(p); if (e) return e;
    // «Reclamar pago» la pide solo la cola (secreto del servicio) y siempre con la sociedad del contrato: ni una sesión del equipo puede
    // reenviarlo a mano ni sale firmado con la marca de Lawang por descuido.
    if (p.plantilla === 'reclamo_pago' && ((via !== 'servicio' && via !== 'servicio-render') || !sociedad)) {
      return { error: 'reclamo_pago exige el secreto del servicio y la sociedad', status: 400 };
    }
    const r = await componePlantilla(p, cfg, portal);
    if (esFallo(r)) return r;
    comp = r;
    p.subject = r.subject; p.message = r.message; p.encabezado = ''; p.etiqueta = ''; p.ctaUrl = r.cta.url; p.ctaTexto = r.cta.texto;
    return null;
  };

  // vista previa: solo con sesión de la suite; no toca SMTP
  if (p.preview) {
    if (via !== 'sesion') return fail({ error: 'La vista previa exige sesión de la suite', status: 401 }, via);
    if (p.plantilla !== '') { const e = await aplicaPlantilla(); if (e) return fail(e, via); }
    const t = validaTextos(p); if (t) return fail(t, via);
    if (p.message === '') return fail({ error: 'El mensaje está vacío o es demasiado largo', status: 400 }, via);
    // Como el PHP: una URL fuera de lista es error; media pareja no pinta botón (no es error).
    if (p.ctaUrl !== '' && !ctaPermitida(p.ctaUrl, cfg.dominio)) {
      return fail({ error: 'cta_url no permitida: solo https hacia ' + cfg.dominio + ' (o sus subdominios), mailto: y https://wa.me/', status: 400 }, via);
    }
    const cta = p.ctaUrl !== '' && p.ctaTexto !== '' ? { url: p.ctaUrl, texto: p.ctaTexto } : null;
    log(via, 200, '', llamante, comp ? { plantilla: comp.plantilla, version: comp.version } : undefined);
    return resp({ ok: true, html: plantillaHtml(p.message, p.encabezado, cta, p.etiqueta, marca), ...(comp ? { plantilla: comp.plantilla, version: comp.version } : {}) });
  }

  if (await enviosPausados()) return fail({ error: TEXTO_PAUSA, status: 503 }, via);
  if (p.plantilla !== '') { const e = await aplicaPlantilla(); if (e) return fail(e, via, p.to); }

  const v = validaEnvio(p); if (v) return fail(v, via, p.to);

  // vía 3: aviso interno — solo texto, solo a los buzones de aviso, sin título ni botón propios
  const destinoInterno = esDominioPropio(p.to, cfg.dominio);
  /* Vía 3, MÁS ESTRECHA que el PHP (code-review 25-sep-2026): aquí se envía por el buzón SMTP del
     cliente, con cuota diaria. Abierta a todo @dominio, cualquiera en internet podía agotar esa cuota
     en bucle y dejar sin correo los contratos y las facturas (y arriesgar la suspensión del buzón).
     Así que: solo a los buzones de aviso de config_instancia —que son los únicos a los que escribe la
     base con pg_net (_avisar_equipo_soporte, revisar_almacenamiento)— y con un freno por isolate.
     El freno no es global (cada isolate cuenta el suyo): uno duradero necesita una tabla, pendiente. */
  const va = via ? null : viaAviso({ secretoEnv: env('ENVIO_AVISO_SECRET'), cabecera: secretoAviso, attach: p.attach, to: p.to, avisos: cfg.avisos });
  if (va) {
    if (!frenoAvisoInterno()) return fail({ error: 'Demasiados avisos internos seguidos; se reintenta más tarde', status: 429 }, va, p.to);
    via = va;
    p.encabezado = ''; p.etiqueta = ''; p.ctaUrl = ''; p.ctaTexto = '';
  }
  if (!via) {
    return fail({ error: 'No autorizado: hace falta una sesión de la suite (X-Suite-Token) o el secreto del servicio. '
      + 'Solo los avisos internos de texto a los buzones de aviso de la instancia van sin credencial.', status: 401 }, via, p.to);
  }

  const cta = comp ? { url: p.ctaUrl, texto: p.ctaTexto } : deduceCta(p, cfg.dominio, portal, destinoInterno, cfg.urlIntranet);
  if (esFallo(cta)) return fail(cta, via, p.to);

  let pdf: Uint8Array | null = null;
  if (p.attach) {
    if (p.html !== '') pdf = await renderPdf(p.html);
    if (!pdf && p.pdfBase64 !== '') { const b = decodificaBase64(p.pdfBase64); if (esPdf(b)) pdf = b; }
    if (!pdf) return fail({ error: 'No se pudo generar ni adjuntar el PDF (servicio de render no disponible y no se adjuntó uno manualmente)', status: 502 }, via, p.to);
  }

  const s = smtpConfig();
  if ('error' in s) return fail({ error: s.error, status: 500 }, via, p.to);
  try {
    await enviaSmtp(p, marca, plantillaHtml(p.message, p.encabezado, cta, p.etiqueta, marca),
      plantillaTexto(p.message, p.encabezado, cta, marca), pdf, s.fromName, s);
  } catch (e) {
    // La línea libre del servidor SMTP puede llevar la cuenta o el banner: al log solo códigos. Al llamante,
    // el texto con 554 / 5.7.1 (que buscan los crons para parar la tanda) y los mismos códigos en campos.
    const f = describeFalloSmtp(e);
    console.error('envia-correo: SMTP falló (' + f.log + ')');
    return fail({ error: f.texto, status: 500, extra: { smtp_code: f.smtp_code, smtp_response_code: f.smtp_response_code } }, via, p.to);
  }
  log(via, 200, p.to, llamante, comp ? { plantilla: comp.plantilla, version: comp.version } : undefined);
  return resp({ ok: true, ...(comp ? { plantilla: comp.plantilla, version: comp.version } : {}) });
}

Deno.serve(manejador);
