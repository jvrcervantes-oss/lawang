// ajustes-correo — el servidor de salida del correo (SMTP del buzón del cliente) desde Ajustes › Correo. F3.1 del plan único, 7-oct-2026.
// Encargo encargos/20261006_estudio_erp_plan_unico.md → F3 · inventario erp/inventario_descableado.md S1, A4, A5. Plan v2 revisado por
// Seguridad y Datos.
//
// POR QUÉ ES UNA EDGE: el navegador no escribe en la base ni guarda secretos. La pantalla manda lo que escribe el super admin; esta edge
// comprueba QUIÉN es, valida el servidor, lo PRUEBA con un envío real y solo entonces lo promueve a activo (RPC `correo_smtp_*`, que solo
// ejecuta service_role y vuelven a comprobar al actor). La contraseña viaja una vez en el cuerpo, se guarda en Vault y nunca vuelve: ni en la
// respuesta ni en el log. `envia-correo` la lee de Vault (`correo_smtp_lee`).
//
// POST JSON {accion:'estado'}                                   → 200 {ok:true, estado:{…sin contraseña…}, remitente, avisos:{soporte, sistema}, envios_pausados, pide_codigo}
//      JSON {accion:'pedir_codigo', alcance:'servidor', host, port:465, user, pass, nombre?}  ← o ←  {accion:'pedir_codigo', alcance:'ajuste', clave, valor}
//        200 {ok:true, codigo:'codigo_enviado', caduca_en:600, correo_enmascarado}      (el código de 6 cifras sale por correo a la SESIÓN, nunca al navegador)
//        400 validación · 503 host_no_comprobable (el DNS no se pudo comprobar) · 400 sin_cambios · 429 demasiados_intentos · 502 codigo_no_enviado · 503 codigo_no_disponible|envios_pausados
//      JSON {accion:'guardar_ajuste', clave, valor, codigo}  (clave: email_from · email_reply_to · email_avisos_sistema · email_avisos_soporte)
//        200 {ok:true, guardado:true, cambiado, aviso:'enviado'|'no_enviado'|'sin_destinatario', clave}  ·  403 {codigo:'codigo_no_valido'}
//      JSON {accion:'probar_y_guardar', host, port:465, user, pass, nombre?, codigo, contrasena_actual?}
//        200 {ok:true, guardado:true, aviso:'enviado'|'no_enviado'|'sin_destinatario', prueba_enviada_a, estado}
//        400 {ok:false, codigo} validación (host_no_valido · puerto_no_valido · usuario_no_valido · clave_no_valida · nombre_no_valido ·
//            host_no_resuelve · host_privado · sin_remitente · sin_correo_usuario · accion_no_valida · json_no_valido)
//        401 {ok:false, codigo:'sin_sesion'|'reautenticar'|'clave_actual_incorrecta'} · 403 {codigo:'no_super_admin'|'origen'|'codigo_no_valido'} · 405 · 413
//        422 {ok:false, codigo:'prueba_fallida', fase:'verify'|'envio', smtp_code, smtp_response_code, detalle_code}  (el activo anterior sigue)
//        429 {codigo:'demasiados_intentos'} · 503 {codigo:'envios_pausados'|'codigo_no_disponible'} · 502 {codigo:'base_no_responde'}
// Al navegador solo CÓDIGOS: nunca el texto libre del servidor SMTP, ni el host que escribió, ni la contraseña. Log: {fn, accion, estado, codigo}.
//
// Autorización: Bearer <JWT> (o X-Suite-Token). Sesión viva en Auth (/auth/v1/user) Y fila ACTIVA de `public.usuarios` con rol super_admin leída
// con la clave de servicio —nunca de los claims del JWT, que no dicen si lo dieron de baja—. El uuid que va a las RPC y el correo al que se manda
// la prueba salen de esa sesión verificada, jamás del cuerpo.
// Cambiar de host o de usuario (no solo la contraseña) pide SIEMPRE la contraseña de la cuenta (además del código), y avisa
// antes por el servidor VIEJO al buzón `email_avisos_sistema`: si alguien se hace con una sesión de super admin, el dueño se entera.
// CÓDIGO DE CONFIRMACIÓN (F3.1b, 8-oct-2026; decisión del owner, diseño en encargos/20260930_erp_ajustes_pantalla.md): cambiar el servidor o uno de los
// cuatro ajustes de correo exige un código de 6 cifras de un solo uso, enviado al correo de la sesión verificada. Lo genera ESTA edge
// (crypto.getRandomValues) y en la base solo se guarda su HMAC-SHA256 con el pepper CORREO_CODIGO_PEPPER, que vive aquí y no en la base; la «huella» (HMAC de
// acción + actor + todos los campos del cambio) lo ata al cambio exacto. Sale por el servidor ACTIVO (Vault), si falla por los SMTP_* del entorno, y si ambos
// fallan es `codigo_no_enviado` y la emisión no gasta cupo. Nunca hay un modo «sin código»: sin pepper, 503. Antes de aplicar el cambio se avisa a los demás
// super admin y al buzón de sistema anterior (por el servidor de hoy); con un solo admin y sin buzón se permite y queda anotado en el registro de cambios.
// Límite conocido (decidido por el owner): quien tenga la sesión Y el buzón puede cambiarlo; sin botón de cancelar ni retardo (seguridad_2026 §7).
// CORS: solo el origen de la intranet (config_instancia.url_intranet) — marca: cors-lista, no cors-publico. Otro Origin → 403.
//
// Límite de intentos (5 en 10 min por instancia): vive en la base (correo_smtp_guarda_candidato), no en la memoria de esta edge.
// DNS: se resuelve el nombre y se rechaza si cae en un rango privado/reservado. Límite honesto: después, nodemailer vuelve a resolver (una
// respuesta DNS que cambie entre las dos no se detecta) y envia-correo conecta por nombre; la barrera de verdad es que solo el super admin llega
// aquí, que el puerto es 465 con TLS verificado y que la plataforma no tiene red interna a la que apuntar.

// @deno-types="npm:@types/nodemailer@6.4.17"
import nodemailer from 'npm:nodemailer@6.9.16';
import { esEmail, tieneControl, saneaLlamante, describeFalloSmtp, normalizaDominio, TEXTO_PAUSA } from '../envia-correo/valida.ts';
import { validaServidor, esServidorMalo, type ServidorValido, esIpPublica, remitenteEfectivo, buzonAvisoValido, PUERTO_SMTP } from '../envia-correo/smtp.ts';

const env = (k: string) => (Deno.env.get(k) ?? '').trim();
const SUPA_URL = env('SUPABASE_URL').replace(/\/$/, '');
const SUPA_ANON = env('SUPABASE_ANON_KEY');
const SUPA_SERVICE = env('SUPABASE_SERVICE_ROLE_KEY');
const PEPPER = env('CORREO_CODIGO_PEPPER');   // aleatorio (≥ 32 bytes en hex); fuera de la base (secreto de esta edge)
/** Un pepper de «aaaa…» o de 4 caracteres que se repiten no protege nada: se exige longitud Y variedad (un hex aleatorio de 64 caracteres trae ~16 distintos). */
const PEPPER_OK = PEPPER.length >= 32 && new Set(PEPPER).size >= 8;
const TOPE_CUERPO = 16 * 1024;
const servicio = () => ({ apikey: SUPA_SERVICE, Authorization: 'Bearer ' + SUPA_SERVICE });

type Cfg = Record<string, string>;
/** Las claves de config_instancia que esta edge necesita (todas texto, ninguna secreta). */
async function leeConfig(): Promise<Cfg | null> {
  if (!SUPA_URL || !SUPA_SERVICE) return null;
  try {
    const r = await fetch(SUPA_URL + '/rest/v1/config_instancia?select=clave,valor&clave=in.(url_intranet,dominio_web,marca,email_from,email_reply_to,email_avisos_sistema,email_avisos_soporte)',
      { headers: servicio(), signal: AbortSignal.timeout(6000) });
    if (!r.ok) { await r.text().catch(() => ''); return null; }
    const filas = await r.json() as { clave: string; valor: unknown }[];
    const c: Cfg = {};
    for (const f of filas) if (typeof f?.valor === 'string') c[f.clave] = f.valor.trim();
    return c;
  } catch { return null; }
}

type Quien = { uid: string; email: string; ultimoAcceso: number };
/** El usuario de la sesión si es un super admin ACTIVO; si no, el motivo. */
async function superAdmin(jwt: string): Promise<Quien | 'no_sesion' | 'no_super' | 'error'> {
  if (!SUPA_URL || !SUPA_ANON || !SUPA_SERVICE) return 'error';
  try {
    const r = await fetch(SUPA_URL + '/auth/v1/user', { headers: { apikey: SUPA_ANON, Authorization: 'Bearer ' + jwt }, signal: AbortSignal.timeout(10_000) });
    if (r.status === 401 || r.status === 403) return 'no_sesion';
    if (r.status !== 200) return 'error';
    const u = await r.json() as { id?: string; email?: string; last_sign_in_at?: string };
    const uid = String(u?.id ?? '');
    if (!/^[0-9a-f-]{36}$/i.test(uid)) return 'no_sesion';
    const q = await fetch(SUPA_URL + '/rest/v1/usuarios?select=user_id&activo=is.true&rol=eq.super_admin&user_id=eq.' + encodeURIComponent(uid),
      { headers: servicio(), signal: AbortSignal.timeout(10_000) });
    if (q.status !== 200) { await q.text().catch(() => ''); return 'error'; }
    const filas = await q.json();
    if (!(Array.isArray(filas) && filas.length === 1 && filas[0]?.user_id === uid)) return 'no_super';
    const t = Date.parse(String(u?.last_sign_in_at ?? ''));
    return { uid, email: String(u?.email ?? '').trim(), ultimoAcceso: Number.isFinite(t) ? t : 0 };
  } catch { return 'error'; }
}

// Las RPC que llama esta edge, con la ruta ESCRITA ENTERA: así el inventario (erp/modulos.py, que busca `rest/v1/rpc/<nombre>`) ve a su llamador
// con nombre, que es lo que la regla «reducir la exposición» exige a cada función expuesta.
const RPC = {
  estado: '/rest/v1/rpc/correo_smtp_estado', lee: '/rest/v1/rpc/correo_smtp_lee',
  guarda: '/rest/v1/rpc/correo_smtp_guarda_candidato', reauth: '/rest/v1/rpc/correo_smtp_reauth_intento', promueve: '/rest/v1/rpc/correo_smtp_promueve', pausa: '/rest/v1/rpc/envios_pausados',
  descarta: '/rest/v1/rpc/correo_smtp_descarta',
  emite: '/rest/v1/rpc/correo_codigo_emite', verifica: '/rest/v1/rpc/correo_codigo_verifica', retira: '/rest/v1/rpc/correo_codigo_retira',
  ajuste: '/rest/v1/rpc/correo_ajuste_guarda',
} as const;
type Rpc = { ok: true; json: unknown } | { ok: false; code: string; hint: string; status: number };
async function rpc(ruta: typeof RPC[keyof typeof RPC], cuerpo: Record<string, unknown>): Promise<Rpc> {
  try {
    const r = await fetch(SUPA_URL + ruta, {
      method: 'POST', headers: { ...servicio(), 'Content-Type': 'application/json' }, body: JSON.stringify(cuerpo), signal: AbortSignal.timeout(15_000),
    });
    const t = await r.text();
    if (r.status === 200 || r.status === 204) {
      // PostgREST contesta cuerpo VACÍO cuando la función devuelve NULL (p. ej. correo_smtp_lee sin servidor en Vault): es un NULL, no un error
      if (t.trim() === '') return { ok: true, json: null };
      try { return { ok: true, json: JSON.parse(t) }; } catch { return { ok: false, code: 'json', hint: '', status: 200 }; }
    }
    let e: { code?: string; hint?: string } = {};
    try { e = JSON.parse(t); } catch { /* sin JSON: queda el estado HTTP */ }
    return { ok: false, code: String(e.code ?? ''), hint: String(e.hint ?? ''), status: r.status };
  } catch { return { ok: false, code: 'red', hint: '', status: 0 }; }
}

/** ¿Están en pausa los envíos? Si no se puede saber, SÍ (como envia-correo: ante la duda no se manda nada). */
async function enviosPausados(): Promise<boolean> {
  const r = await rpc(RPC.pausa, {});
  return !(r.ok && r.json === false);
}

// ── DNS ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
/** 'ok' · 'no_resuelve' · 'privado' · 'no_disponible' (el runtime no deja resolver: no se puede comprobar). Quien llama FALLA CERRADO con 'no_disponible'
 *  (host_no_comprobable, 8-oct-2026): sin saber a qué IP apunta el nombre no se conecta ni se manda código. Medido en axisworks-demo: Deno.resolveDns SÍ
 *  funciona en el runtime de Supabase Edge, así que el caso normal no se rompe.
 *  Límite conocido (NO se resuelve aquí a propósito): nodemailer vuelve a resolver el nombre al conectar, así que un DNS que cambie entre la comprobación y la
 *  conexión (rebinding) no se detecta. Queda acotado por el puerto 465 fijo + TLS con certificado verificado (una IP interna no presentará un certificado válido
 *  para ese nombre) + solo super admin + código de confirmación. Conectar por la IP ya resuelta exigiría fijar `servername` para el TLS: no se hace. */
async function compruebaDns(host: string): Promise<'ok' | 'no_resuelve' | 'privado' | 'no_disponible'> {
  const d = Deno as unknown as { resolveDns?: (h: string, t: string) => Promise<string[]> };
  if (typeof d.resolveDns !== 'function') return 'no_disponible';
  const ips: string[] = [];
  let noEncontrado = 0, raro = 0;
  for (const tipo of ['A', 'AAAA']) {
    try { ips.push(...await d.resolveDns(host, tipo)); } catch (e) {
      const n = String((e as { name?: string })?.name ?? '');
      if (n === 'NotFound' || /NotFound|ENODATA|ENOTFOUND/i.test(String((e as Error)?.message ?? ''))) noEncontrado++; else raro++;
    }
  }
  if (ips.length === 0) return raro > 0 ? 'no_disponible' : noEncontrado > 0 ? 'no_resuelve' : 'no_disponible';
  return ips.every((ip) => esIpPublica(ip)) ? 'ok' : 'privado';
}

// ── SMTP (prueba) ────────────────────────────────────────────────────────────────────────────────────────────────────────────
type Servidor = { host: string; port: number; user: string; pass: string };
const transporte = (s: Servidor) => nodemailer.createTransport({
  host: s.host, port: s.port, secure: true, auth: { user: s.user, pass: s.pass },   // TLS implícito en 465 y certificado verificado (no se toca rejectUnauthorized)
  connectionTimeout: 15_000, greetingTimeout: 15_000, socketTimeout: 30_000,
  disableFileAccess: true, disableUrlAccess: true,
});
function codigoTls(e: unknown): string {
  const c = (e as { cause?: { code?: unknown } })?.cause?.code;
  return typeof c === 'string' && /^[A-Z0-9_]{3,40}$/.test(c) ? c : '';
}

// ── código de confirmación: cripto ─────────────────────────────────────────────────────────────────────────────────────────────
/** El MISMO formato de correo que valida la base (correo_ajuste_guarda: `v_mail`, ≤ 254 y el @ en la posición ≤ 65): si la edge aceptase algo que la base rechaza, el código ya
 *  estaría gastado (o el aviso a los demás admins enviado) cuando la base dijera que no. Si se cambia uno, se cambia el otro (el test fija los dos casos). */
const MAIL_BASE = /^[A-Za-z0-9_%+-]+(\.[A-Za-z0-9_%+-]+)*@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}$/;
const mailComoLaBase = (s: string) => s.length <= 254 && MAIL_BASE.test(s) && s.indexOf('@') < 65;
const CLAVES_CODIGO = ['email_from', 'email_reply_to', 'email_avisos_sistema', 'email_avisos_soporte'] as const;
const CADUCA_S = 600;
const hex = (b: ArrayBuffer | Uint8Array) => [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, '0')).join('');
async function hmacHex(datos: string): Promise<string> {
  const k = await crypto.subtle.importKey('raw', new TextEncoder().encode(PEPPER), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return hex(await crypto.subtle.sign('HMAC', k, new TextEncoder().encode(datos)));
}
/** La huella ata el código al cambio EXACTO (acción + actor + todos los campos, en forma canónica: un array JSON no es ambiguo). */
const huellaDe = (alcance: string, uid: string, campos: string[]) => hmacHex(JSON.stringify(['huella/v1', alcance, uid, ...campos]));
const hashDe = (huella: string, codigo: string) => hmacHex(JSON.stringify(['codigo/v1', huella, codigo]));
const bytea = (h: string) => '\\x' + h;
/** 6 cifras uniformes (rechazo del sesgo del módulo) con el generador criptográfico. */
function generaCodigo(): string {
  const tope = Math.floor(0x1_0000_0000 / 1_000_000) * 1_000_000;
  const a = new Uint32Array(1);
  do { crypto.getRandomValues(a); } while (a[0] >= tope);
  return String(a[0] % 1_000_000).padStart(6, '0');
}
function enmascara(email: string): string {
  const i = email.lastIndexOf('@');
  return i < 1 ? '***' : email[0] + '***' + email.slice(i);
}
/** La IP que dice la red delante de la función; solo informativa, para el texto del correo (saneada: nunca va a un sitio que decida algo).
 *  Solo `cf-connecting-ip` (la pone el borde de Supabase; `x-forwarded-for` lo puede escribir el cliente y aquí ni se mira). */
function ipDe(req: Request): string {
  const v = (req.headers.get('cf-connecting-ip') ?? '').trim();
  return /^[0-9a-fA-F:.]{3,45}$/.test(v) ? v : 'desconocida';
}

// ── envío de los correos propios de esta edge (código y avisos) ────────────────────────────────────────────────────────────────
type Envio = { host: string; user: string; pass: string; nombre: string; from: string; origen: 'vault' | 'entorno' };
type Activo = { host?: string; user?: string; pass?: string; nombre?: string | null } | null;
/** Servidores por los que se intenta, en orden: el ACTIVO de Vault y, si falla o no hay, los SMTP_* del entorno (plan B permanente, owner 8-oct). */
function servidoresDeEnvio(cfg: Cfg, dominio: string, vault: Activo): Envio[] {
  const out: Envio[] = [];
  if (vault && vault.host && vault.user && vault.pass) {
    const from = remitenteEfectivo({ emailFrom: cfg.email_from, buzon: vault.user, usuario: vault.user, dominioWeb: dominio }).from;
    if (from !== '') out.push({ host: vault.host, user: vault.user, pass: vault.pass, nombre: vault.nombre ?? '', from, origen: 'vault' });
  }
  const host = env('SMTP_HOST'), user = env('SMTP_USER'), pass = env('SMTP_PASS');
  if (host && user && pass && Number(env('SMTP_PORT') || '465') === PUERTO_SMTP) {
    const from = remitenteEfectivo({ emailFrom: cfg.email_from, buzon: env('SMTP_FROM'), usuario: user, dominioWeb: dominio }).from;
    if (from !== '') out.push({ host, user, pass, nombre: env('SMTP_FROM_NAME'), from, origen: 'entorno' });
  }
  return out;
}
/** Lo que escribe el usuario (host, usuario SMTP) y va LITERAL al texto de un correo: solo caracteres de un buzón o de un nombre DNS, recortado. Un usuario
 *  con saltos de línea o texto largo no puede añadir frases al correo del código ni al aviso a los demás admins. */
const lit = (s: unknown) => String(s ?? '').replace(/[^A-Za-z0-9@._+-]/g, '').slice(0, 80);
/** Manda un correo de texto a UNA dirección probando cada servidor en orden. Al log solo el origen y el código de fallo, nunca el texto. */
async function enviaTexto(srvs: Envio[], cfg: Cfg, to: string, subject: string, text: string): Promise<boolean> {
  if (!esEmail(to) || tieneControl(to)) return false;
  for (const s of srvs) {
    const t = transporte({ host: s.host, port: PUERTO_SMTP, user: s.user, pass: s.pass });
    try {
      await t.sendMail({ from: { name: s.nombre || cfg.marca || 'Aviso', address: s.from }, to, subject, text, disableFileAccess: true, disableUrlAccess: true });
      return true;
    } catch (e) {
      console.error('ajustes-correo: envío fallido por ' + s.origen + ' (' + describeFalloSmtp(e).log + ')');
    } finally { t.close(); }
  }
  return false;
}
/** Avisa del cambio que se va a hacer ANTES de hacerlo: a los demás super admin activos y al buzón de sistema de hoy. `null` = no se pudo saber a quién (se frena). */
async function avisaCambio(quien: Quien, cfg: Cfg, dominio: string, usuarioSmtp: string, srvs: Envio[], que: string): Promise<'enviado' | 'no_enviado' | 'sin_destinatario' | null> {
  let otros: string[] = [];
  try {
    const q = await fetch(SUPA_URL + '/rest/v1/usuarios?select=email&activo=is.true&rol=eq.super_admin&user_id=neq.' + encodeURIComponent(quien.uid),
      { headers: servicio(), signal: AbortSignal.timeout(10_000) });
    if (q.status !== 200) { await q.text().catch(() => ''); return null; }
    const filas = await q.json() as { email?: unknown }[];
    if (!Array.isArray(filas)) return null;
    otros = filas.map((f) => String(f?.email ?? '').trim()).filter((e) => esEmail(e) && !tieneControl(e));
  } catch { return null; }
  const destinos = new Set(otros.map((e) => e.toLowerCase()));
  const sis = (cfg.email_avisos_sistema ?? '').trim().toLowerCase();
  // el buzón de sistema solo cuenta si es PROPIO (dominio de la instancia, de email_from o del servidor): un valor antiguo de otro dominio no recibe avisos
  if (buzonAvisoValido(sis, { dominio, emailFrom: cfg.email_from, usuarioSmtp })) destinos.add(sis);
  destinos.delete(quien.email.toLowerCase());   // el aviso es para los demás: a quien cambia ya le llega el código
  if (destinos.size === 0) return 'sin_destinatario';
  // en paralelo: con varios destinatarios y un servidor caído, uno tras otro superaría el plazo de la edge
  const asunto = 'Aviso: se va a cambiar la configuración del correo' + (cfg.marca && !tieneControl(cfg.marca) ? ' de ' + cfg.marca : '');
  const texto = 'Un super admin (' + quien.email + ') está cambiando la configuración del correo.\n\n' + que + '\n\nSi no has sido tú ni nadie de tu equipo, entra en Ajustes › Correo y revisa los accesos de los super admin.\n';
  const res = await Promise.all([...destinos].map((d) => enviaTexto(srvs, cfg, d, asunto, texto)));
  const todos = res.every(Boolean);
  return todos ? 'enviado' : 'no_enviado';
}

// ── manejador ────────────────────────────────────────────────────────────────────────────────────────────────────────────────
export async function manejador(req: Request): Promise<Response> {
  // Sin credencial no se gasta ni la lectura de la configuración: 401 directo (salvo el preflight CORS, que nunca lleva credenciales y sí necesita la configuración).
  // Sin cabeceras CORS a propósito: el front siempre manda sesión; quien no la manda no es el front.
  if (req.method !== 'OPTIONS' && !(req.headers.get('x-suite-token') ?? '').trim() && !(req.headers.get('authorization') ?? '').trim()) {
    console.log(JSON.stringify({ fn: 'ajustes-correo', estado: 401, codigo: 'sin_sesion' }));
    return new Response(JSON.stringify({ ok: false, codigo: 'sin_sesion', error: 'Hace falta la sesión de un super admin' }),
      { status: 401, headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' } });
  }
  const cfg = await leeConfig();
  const origen = req.headers.get('origin');
  let permitido = '';
  try { permitido = new URL(cfg?.url_intranet ?? '').origin; } catch { /* sin url_intranet válida: sin CORS */ }
  if (!permitido.startsWith('https://')) permitido = '';
  const origenOk = origen && permitido && origen === permitido ? origen : null;
  const cab = new Headers({ 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
  if (origenOk) {
    cab.set('Access-Control-Allow-Origin', origenOk);
    cab.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
    cab.set('Access-Control-Allow-Headers', 'content-type, x-suite-token, authorization, apikey, x-client-info');
    cab.set('Access-Control-Max-Age', '600');
    cab.set('Vary', 'Origin');
  }
  const llamante = saneaLlamante(req.headers.get('x-llamante'));
  let accion = '';
  const resp = (cuerpo: Record<string, unknown>, status = 200) => {
    console.log(JSON.stringify({ fn: 'ajustes-correo', ...(accion ? { accion } : {}), estado: status, ...(typeof cuerpo.codigo === 'string' ? { codigo: cuerpo.codigo } : {}), ...(llamante ? { llamante } : {}) }));
    return new Response(JSON.stringify(cuerpo), { status, headers: cab });
  };
  const no = (codigo: string, error: string, status: number, extra: Record<string, unknown> = {}) => resp({ ok: false, codigo, error, ...extra }, status);

  if (origen && !origenOk) return no('origen', 'Origen no permitido', 403);
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cab });
  if (req.method !== 'POST') return no('metodo', 'Método no permitido', 405);
  if (!cfg) return no('base_no_responde', 'No se pudo leer la configuración de la instancia', 502);

  // 1. QUIÉN
  let jwt = (req.headers.get('x-suite-token') ?? '').trim();
  if (!jwt) { const m = /^Bearer\s+(.+)$/i.exec((req.headers.get('authorization') ?? '').trim()); if (m) jwt = m[1].trim(); }
  if (!jwt || jwt === SUPA_ANON || jwt === SUPA_SERVICE) return no('sin_sesion', 'Hace falta la sesión de un super admin', 401);
  const quien = await superAdmin(jwt);
  if (quien === 'no_sesion') return no('sin_sesion', 'Sesión no válida', 401);
  if (quien === 'no_super') return no('no_super_admin', 'Cambiar el servidor de correo exige super admin', 403);
  if (quien === 'error') return no('base_no_responde', 'No se pudo comprobar la sesión', 502);

  // 2. QUÉ (tope de cuerpo ANTES de parsear)
  if (Number(req.headers.get('content-length') ?? '0') > TOPE_CUERPO) return no('cuerpo_grande', 'La petición es demasiado grande', 413);
  let crudo: string;
  try { crudo = await req.text(); } catch { return no('json_no_valido', 'JSON inválido', 400); }
  if (crudo.length > TOPE_CUERPO) return no('cuerpo_grande', 'La petición es demasiado grande', 413);
  let c: Record<string, unknown>;
  try { const j = JSON.parse(crudo); if (!j || typeof j !== 'object' || Array.isArray(j)) throw new Error('forma'); c = j; } catch { return no('json_no_valido', 'JSON inválido', 400); }
  accion = typeof c.accion === 'string' ? c.accion.slice(0, 30) : '';

  const dominio = normalizaDominio(cfg.dominio_web);
  const estadoPantalla = async () => {
    const e = await rpc(RPC.estado, {});
    if (!e.ok) return null;
    const est = e.json as Record<string, unknown>;
    const usuario = typeof est.usuario === 'string' ? est.usuario : '';
    const rem = remitenteEfectivo({ emailFrom: cfg.email_from, buzon: usuario, usuario, dominioWeb: dominio });
    return { estado: est, remitente: { email_from: cfg.email_from ?? '', efectivo: rem.from, motivo: rem.motivo, reply_to: cfg.email_reply_to ?? '' },
      avisos: { soporte: cfg.email_avisos_soporte ?? '', sistema: cfg.email_avisos_sistema ?? '' } };
  };

  // ── acción: estado ───────────────────────────────────────────────────────────────────────────────────────────────────────
  if (accion === 'estado') {
    const e = await estadoPantalla();
    if (!e) return no('base_no_responde', 'No se pudo leer el estado del correo', 502);
    return resp({ ok: true, ...e, envios_pausados: await enviosPausados(), pide_codigo: PEPPER_OK });
  }
  if (accion !== 'probar_y_guardar' && accion !== 'pedir_codigo' && accion !== 'guardar_ajuste') return no('accion_no_valida', 'Acción no reconocida', 400);

  // ── lo que comparten las tres acciones con código: el cambio concreto, validado, y su huella ─────────────────────────────────
  if (!PEPPER_OK) {
    console.error('ajustes-correo: CORREO_CODIGO_PEPPER sin definir, corto (< 32) o de poca variedad (< 8 caracteres distintos): no se puede pedir ni comprobar un código');
    return no('codigo_no_disponible', 'La confirmación por código no está disponible en esta instancia', 503);
  }
  const alcance: string = accion === 'probar_y_guardar' ? 'servidor' : accion === 'guardar_ajuste' ? 'ajuste' : (c.alcance === 'servidor' || c.alcance === 'ajuste' ? c.alcance : '');
  if (alcance === '') return no('alcance_no_valido', 'Falta qué se quiere cambiar', 400);
  const codigoPuesto = typeof c.codigo === 'string' && /^[0-9]{6}$/.test(c.codigo.trim()) ? c.codigo.trim() : '';

  let v: ServidorValido | null = null;                       // alcance servidor
  let clave = '', valor = '';                                // alcance ajuste
  let campos: string[] = [];
  if (alcance === 'servidor') {
    const val = validaServidor({ host: c.host, port: c.port, user: c.user, pass: c.pass, nombre: c.nombre });
    if (esServidorMalo(val)) return no(val.codigo, val.error, 400);
    v = val;
    campos = [v.host, String(v.port), v.user, v.pass, v.nombre];
  } else {
    clave = typeof c.clave === 'string' ? c.clave : '';
    if (!(CLAVES_CODIGO as readonly string[]).includes(clave)) return no('clave_no_editable', 'Ese ajuste no se cambia desde aquí', 400);
    valor = typeof c.valor === 'string' ? c.valor.trim() : '';
    if (typeof c.valor !== 'string' || tieneControl(valor) || [...valor].length > 254) return no('valor_no_valido', 'El valor no es válido', 400);
    if (!(clave === 'email_reply_to' && valor === '') && !(esEmail(valor) && mailComoLaBase(valor))) return no('valor_no_valido', 'Tiene que ser un correo válido', 400);
    campos = [clave, valor];
  }
  if (!esEmail(quien.email) || tieneControl(quien.email)) return no('sin_correo_usuario', 'Tu cuenta no tiene un correo válido al que mandar el código', 400);
  let remitenteNuevo = '';
  if (v) {
    const dns = await compruebaDns(v.host);
    if (dns === 'no_disponible') {
      console.error('ajustes-correo: dns_no_disponible (el nombre no se pudo comprobar contra rangos privados): se rechaza, no se manda código ni se conecta');
      return no('host_no_comprobable', 'No se ha podido comprobar a dónde apunta ese servidor ahora mismo: inténtalo de nuevo en un rato', 503);
    }
    if (dns === 'no_resuelve') return no('host_no_resuelve', 'Ese servidor no existe (no resuelve en internet)', 400);
    if (dns === 'privado') return no('host_privado', 'Ese servidor apunta a una red interna: solo se admite un servidor público', 400);
    remitenteNuevo = remitenteEfectivo({ emailFrom: cfg.email_from, buzon: v.user, usuario: v.user, dominioWeb: dominio }).from;
    if (remitenteNuevo === '') return no('sin_remitente', 'El usuario del buzón no es un correo: pon un remitente de tu dominio en Ajustes › Correo', 400);
  }
  // pausa: no se manda nada ni se prueba (y se dice claro, que no es una credencial mala)
  if (await enviosPausados()) return no('envios_pausados', TEXTO_PAUSA, 503);

  // El servidor que manda hoy (Vault; si no hay, los SMTP_*): su usuario decide qué remitente y qué buzones de aviso son «propios». Un fallo al leerlo NO se disimula.
  const hoy = await rpc(RPC.lee, {});
  if (!hoy.ok) { console.error('ajustes-correo: correo_smtp_lee HTTP ' + hoy.status + ' ' + hoy.code); return no('base_no_responde', 'No se pudo leer el servidor de correo actual', 502); }
  const activo = hoy.json as Activo;
  if (alcance === 'ajuste') {
    const usuarioSmtp = activo?.user ?? env('SMTP_USER');
    if (clave === 'email_from' && remitenteEfectivo({ emailFrom: valor, buzon: usuarioSmtp, usuario: usuarioSmtp, dominioWeb: '' }).from !== valor)
      return no('from_ajeno', 'El remitente tiene que ser del dominio del buzón del servidor de correo', 400);
    // OJO: para los buzones de aviso solo cuenta el usuario del servidor de VAULT (como `_correo_buzon_propio` en la base): con el de entorno la edge diría que sí y la base que no,
    // y para entonces el código estaría gastado y los demás admins avisados. Para email_from sí vale el de entorno (la edge es más estricta que la base, no al revés).
    if ((clave === 'email_avisos_sistema' || clave === 'email_avisos_soporte') && !buzonAvisoValido(valor, { dominio, emailFrom: cfg.email_from, usuarioSmtp: activo?.user ?? '' }))
      return no('buzon_ajeno', 'Tiene que ser un buzón del dominio de la instancia, del remitente o del servidor de correo', 400);
    if (valor === (cfg[clave] ?? '')) {
      if (accion === 'pedir_codigo') return no('sin_cambios', 'Ese valor ya es el actual', 400);
      return resp({ ok: true, guardado: true, cambiado: false, aviso: 'no_aplica', clave });
    }
  }
  const huella = await huellaDe(alcance, quien.uid, campos);

  // ── acción: pedir_codigo ─────────────────────────────────────────────────────────────────────────────────────────────────
  if (accion === 'pedir_codigo') {
    const srvs = servidoresDeEnvio(cfg, dominio, activo);
    if (srvs.length === 0) return no('codigo_no_enviado', 'No hay ningún servidor de correo con el que mandar el código', 502);
    const codigo = generaCodigo();
    const em = await rpc(RPC.emite, { p_actor: quien.uid, p_alcance: alcance, p_huella: bytea(huella), p_hash: bytea(await hashDe(huella, codigo)) });
    if (!em.ok) {
      if (em.hint === 'demasiados_codigos' || em.hint === 'codigo_enfriamiento') { console.error('ajustes-correo: 429 ' + em.hint); return no('demasiados_intentos', 'Demasiados códigos pedidos: espera un poco', 429); }
      if (em.code === '42501') return no('no_super_admin', 'Cambiar el servidor de correo exige super admin', 403);
      console.error('ajustes-correo: codigo_emite HTTP ' + em.status + ' ' + em.code);
      return no('base_no_responde', 'No se pudo preparar el código', 502);
    }
    const idEmision = Number((em.json as { id?: unknown })?.id);
    const que = v ? 'Servidor de salida del correo: ' + lit(v.host) + ' (usuario ' + lit(v.user) + ')' : 'Ajuste «' + clave + '»: nuevo valor ' + (valor === '' ? '(vacío)' : valor);
    const texto = 'Tu código de confirmación es: ' + codigo + '\n\nCaduca en 10 minutos y sirve una sola vez.\n\nQué se va a cambiar: ' + que
      + '\nCuándo: ' + new Date().toISOString().slice(0, 19) + 'Z\nDesde la IP: ' + ipDe(req)
      + '\n\nSi no has pedido este cambio, no uses el código y avisa: alguien podría tener tu sesión.\n';
    const salio = await enviaTexto(srvs, cfg, quien.email, 'Código de confirmación del correo' + (cfg.marca && !tieneControl(cfg.marca) ? ' · ' + cfg.marca : ''), texto);
    if (!salio) {
      if (Number.isSafeInteger(idEmision)) await rpc(RPC.retira, { p_actor: quien.uid, p_id: idEmision });   // un código que no llegó no gasta cupo
      return no('codigo_no_enviado', 'No se pudo enviar el código por correo', 502);
    }
    return resp({ ok: true, codigo: 'codigo_enviado', caduca_en: CADUCA_S, correo_enmascarado: enmascara(quien.email) });
  }

  // ── desde aquí, el código es obligatorio: sin él (o con uno malo), siempre el mismo error ───────────────────────────────────
  const codigoNoValido = () => no('codigo_no_valido', 'El código no es válido', 403);
  if (codigoPuesto === '') return codigoNoValido();
  const hashPuesto = bytea(await hashDe(huella, codigoPuesto));
  const verifica = async (): Promise<'ok' | 'no' | 'error'> => {
    const r = await rpc(RPC.verifica, { p_actor: quien.uid, p_alcance: alcance, p_huella: bytea(huella), p_hash: hashPuesto });
    if (!r.ok) { console.error('ajustes-correo: codigo_verifica HTTP ' + r.status + ' ' + r.code); return r.code === '42501' ? 'no' : 'error'; }
    return (r.json as { valido?: unknown })?.valido === true ? 'ok' : 'no';
  };

  // ── acción: guardar_ajuste ───────────────────────────────────────────────────────────────────────────────────────────────
  if (accion === 'guardar_ajuste') {
    const ver = await verifica();
    if (ver === 'error') return no('base_no_responde', 'No se pudo comprobar el código', 502);
    if (ver === 'no') return codigoNoValido();
    const aviso = await avisaCambio(quien, cfg, dominio, activo?.user ?? env('SMTP_USER'), servidoresDeEnvio(cfg, dominio, activo), 'Se va a cambiar el ajuste «' + clave + '» (valor nuevo: ' + (valor === '' ? 'vacío' : valor) + ').');
    if (aviso === null) return no('base_no_responde', 'No se pudo comprobar a quién avisar', 502);
    const g = await rpc(RPC.ajuste, { p_actor: quien.uid, p_clave: clave, p_valor: valor, p_huella: bytea(huella), p_hash: hashPuesto,
      p_motivo: aviso === 'sin_destinatario' ? 'sin otro destinatario de aviso' : null });
    if (!g.ok) {
      if (g.code === '42501') return no('no_super_admin', 'Cambiar el servidor de correo exige super admin', 403);
      if (g.code === '22023' && /^[a-z_]{5,30}$/.test(g.hint)) return no(g.hint, 'El valor no es válido', 400);
      console.error('ajustes-correo: ajuste_guarda HTTP ' + g.status + ' ' + g.code);
      return no('base_no_responde', 'No se pudo guardar el cambio', 502);
    }
    const j = g.json as { codigo_no_valido?: unknown; cambiado?: unknown };
    if (j?.codigo_no_valido === true) return codigoNoValido();
    return resp({ ok: true, guardado: true, cambiado: j?.cambiado === true, aviso, clave });
  }

  // ── acción: probar_y_guardar ────────────────────────────────────────────────────────────────────────────────────────────
  if (!v) return no('accion_no_valida', 'Acción no reconocida', 400);
  // 3. el servidor, el DNS, el remitente y la pausa ya se comprobaron arriba (antes de tocar la base). 4. el código: se comprueba SIN consumirlo (una prueba que falla no lo quema); se consume al promover
  const ver = await verifica();
  if (ver === 'error') return no('base_no_responde', 'No se pudo comprobar el código', 502);
  if (ver === 'no') return codigoNoValido();

  // 5. ¿cambia de servidor? Sin servidor en Vault (instancia que aún manda por los SMTP_* de entorno) también es un CAMBIO: la primera carga pide sesión
  // reciente o la contraseña (revisión 7-oct). El aviso previo sale por el servidor de hoy: el de Vault, o el de entorno si aún no hay ninguno.
  const cambia = !activo || !activo.host || activo.host !== v.host || activo.user !== v.user;

  // 6. reautenticación reciente si cambia el host o el usuario
  // Decisión del owner (8-oct-2026): cambiar host o usuario exige SIEMPRE la contraseña de la cuenta (y además el código); una sesión reciente no la sustituye.
  if (cambia) {
    const claveCuenta = typeof c.contrasena_actual === 'string' ? c.contrasena_actual : '';
    if (claveCuenta === '') return no('reautenticar', 'Para cambiar de servidor confirma tu contraseña (o vuelve a entrar y repite)', 401);
    // El intento se reserva en la base ANTES de preguntarle a Auth (mismo límite de 5 por 10 min que el de probar): con una sesión robada no se
    // pueden probar contraseñas sin que cuente. Superado el límite, ni siquiera se consulta /auth/v1/token.
    const reserva = await rpc(RPC.reauth, { p_actor: quien.uid });
    if (!reserva.ok) {
      if (reserva.hint === 'demasiados_intentos') { console.error('ajustes-correo: 429 reauth'); return no('demasiados_intentos', 'Demasiados intentos seguidos: espera unos minutos', 429); }
      if (reserva.code === '42501') return no('no_super_admin', 'Cambiar el servidor de correo exige super admin', 403);
      console.error('ajustes-correo: reauth_intento HTTP ' + reserva.status + ' ' + reserva.code);
      return no('base_no_responde', 'No se pudo comprobar la contraseña', 502);
    }
    const idReserva = Number(reserva.json);
    let okClave = false;
    try {
      const r = await fetch(SUPA_URL + '/auth/v1/token?grant_type=password', {
        method: 'POST', headers: { apikey: SUPA_ANON, 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: quien.email, password: claveCuenta }), signal: AbortSignal.timeout(10_000),
      });
      okClave = r.status === 200;
      await r.text().catch(() => '');
    } catch { return no('base_no_responde', 'No se pudo comprobar la contraseña', 502); }
    // contraseña buena: se devuelve la reserva (acertar no gasta intentos). Si no se pudiera liberar, el intento queda contado: es el lado seguro.
    if (okClave && Number.isSafeInteger(idReserva)) await rpc(RPC.reauth, { p_actor: quien.uid, p_libera: idReserva });
    if (!okClave) return no('clave_actual_incorrecta', 'Esa contraseña no es la de tu cuenta', 401);
  }

  // 7. el CANDIDATO a Vault (cuenta el intento). Aún no se usa para enviar nada.
  const g = await rpc(RPC.guarda, { p_actor: quien.uid, p_host: v.host, p_port: v.port, p_user: v.user, p_pass: v.pass, p_nombre: v.nombre === '' ? null : v.nombre });
  if (!g.ok) {
    if (g.hint === 'demasiados_intentos') { console.error('ajustes-correo: 429 candidato'); return no('demasiados_intentos', 'Demasiados intentos seguidos: espera unos minutos', 429); }
    if (g.code === '42501') return no('no_super_admin', 'Cambiar el servidor de correo exige super admin', 403);
    if (g.code === '22023' && /^[a-z_]{5,30}$/.test(g.hint)) return no(g.hint, 'Datos del servidor no válidos', 400);
    console.error('ajustes-correo: guarda_candidato HTTP ' + g.status + ' ' + g.code);
    return no('base_no_responde', 'No se pudo guardar la prueba', 502);
  }
  const token = String((g.json as { token?: unknown })?.token ?? '');
  if (!/^[0-9a-f-]{36}$/i.test(token)) return no('base_no_responde', 'No se pudo guardar la prueba', 502);

  // 8. LA PRUEBA: conexión + usuario y contraseña (verify) y un correo real AL USUARIO que lo está probando (nunca a una dirección del cuerpo)
  const t = transporte(v);
  let fase: 'verify' | 'envio' = 'verify';
  try {
    await t.verify();
    fase = 'envio';
    await t.sendMail({
      from: { name: v.nombre || cfg.marca || 'Prueba', address: remitenteNuevo },
      ...(esEmail(cfg.email_reply_to ?? '') ? { replyTo: cfg.email_reply_to } : {}),
      to: quien.email,
      subject: 'Prueba del servidor de correo' + (cfg.marca && !tieneControl(cfg.marca) ? ' · ' + cfg.marca : ''),
      text: 'Si lees esto, el servidor de salida del correo funciona. Se acaba de comprobar desde Ajustes › Correo y se guardará al terminar la prueba.\n',
      disableFileAccess: true, disableUrlAccess: true,
    });
  } catch (e) {
    const f = describeFalloSmtp(e);
    console.error('ajustes-correo: prueba falló en ' + fase + ' (' + f.log + (codigoTls(e) ? ', ' + codigoTls(e) : '') + ')');
    await rpc(RPC.descarta, { p_actor: quien.uid, p_token: token });   // el candidato fallido no se queda en Vault
    return no('prueba_fallida', 'El servidor no ha aceptado la prueba: no se ha guardado y sigue el anterior', 422,
      { fase, smtp_code: f.smtp_code, smtp_response_code: f.smtp_response_code, detalle_code: codigoTls(e) });
  } finally { t.close(); }

  // 9. aviso previo por el servidor de HOY (el viejo) si cambia de servidor: que los demás se enteren antes de que el cambio quede hecho
  let aviso: 'enviado' | 'no_enviado' | 'sin_destinatario' | 'no_aplica' = 'no_aplica';
  if (cambia) {
    const a = await avisaCambio(quien, cfg, dominio, activo?.user ?? env('SMTP_USER'), servidoresDeEnvio(cfg, dominio, activo),
      (activo?.host ? 'Servidor actual: ' + lit(activo.host) + ' (usuario ' + lit(activo.user) + ')\n' : '') + 'Servidor nuevo: ' + lit(v.host) + ' (usuario ' + lit(v.user) + ')');
    if (a === null) return no('base_no_responde', 'No se pudo comprobar a quién avisar', 502);
    aviso = a;
  }

  // 10. SOLO si la prueba pasó: el candidato pasa a activo (el activo de antes queda como previo) y el código se consume en la misma transacción
  const p = await rpc(RPC.promueve, { p_actor: quien.uid, p_token: token, p_huella: bytea(huella), p_hash: hashPuesto,
    p_nota: aviso === 'sin_destinatario' ? 'sin otro destinatario de aviso' : null });
  if (!p.ok) {
    if (p.hint === 'candidato_no_vigente') return no('prueba_caducada', 'La prueba ya no vale: repítela', 409);
    if (p.code === '42501') return no('no_super_admin', 'Cambiar el servidor de correo exige super admin', 403);
    console.error('ajustes-correo: promueve HTTP ' + p.status + ' ' + p.code);
    return no('base_no_responde', 'La prueba pasó pero no se pudo guardar: repítela', 502);
  }
  if ((p.json as { codigo_no_valido?: unknown })?.codigo_no_valido === true) return codigoNoValido();
  const e = await estadoPantalla();
  return resp({ ok: true, guardado: true, aviso, prueba_enviada_a: quien.email, ...(e ?? {}) });
}

Deno.serve(manejador);
