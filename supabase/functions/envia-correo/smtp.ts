// envia-correo · el servidor de salida (SMTP) — lógica PURA (sin red, sin Deno): la usan `envia-correo` (qué remitente sale) y
// `ajustes-correo` (validar el servidor que escribe el super admin). Sin red para poder probarla con node y con deno (smtp_test.ts).
// F3.1 de Ajustes (7-oct-2026, encargos/20261006_estudio_erp_plan_unico.md). SOLO del maestro: el canon con Lawang es index.ts + valida.ts
// (README → «Este fichero es CANON»); este fichero no existe en Lawang a propósito, así que `valida.ts` no cambia.
import { esEmail, tieneControl, esDominioPropio, normalizaDominio } from './valida.ts';

/** Supabase Edge bloquea la salida a 25 y 587 (docs «Edge Functions → Limits», comprobado 25-sep-2026): solo sirve 465 con TLS implícito. */
export const PUERTO_SMTP = 465;
export const LIMITES_SMTP = { host: 253, usuario: 254, clave: 200, nombre: 60 };

/** Terminaciones que nunca son un servidor público de correo (RFC 6761 / 6762 y las que usan las redes internas). La misma lista que
 *  correo_smtp_guarda_candidato en SQL: si se cambia una, se cambia la otra (smtp_test.ts y f31_correo_smtp.sql lo prueban). */
const TLD_NO_PUBLICOS = new Set(['localhost', 'local', 'internal', 'localdomain', 'lan', 'home', 'corp', 'intranet', 'private', 'arpa', 'invalid', 'test', 'example', 'onion']);

/** Un NOMBRE DNS público en minúsculas, o '' si no vale: sin IP (ni con puntos, ni decimal, ni hexadecimal, ni IPv6), sin puerto, sin
 *  rutas, sin nombre de una sola etiqueta ni interno. La terminación es solo de letras (o xn--): un «127.1» o un «2130706433» no pasan. */
export function normalizaHost(h: unknown): string {
  if (typeof h !== 'string') return '';
  const s = h.trim().toLowerCase();
  if (s.length < 4 || s.length > LIMITES_SMTP.host) return '';
  if (!/^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+([a-z]{2,24}|xn--[a-z0-9-]{2,20})$/.test(s)) return '';
  const tld = s.slice(s.lastIndexOf('.') + 1);
  return TLD_NO_PUBLICOS.has(tld) ? '' : s;
}

export type ServidorValido = { host: string; port: number; user: string; pass: string; nombre: string };
export type ServidorMalo = { error: string; codigo: 'host_no_valido' | 'puerto_no_valido' | 'usuario_no_valido' | 'clave_no_valida' | 'nombre_no_valido' };
export function esServidorMalo(x: unknown): x is ServidorMalo { return !!x && typeof x === 'object' && 'codigo' in x; }

/** Valida lo que el super admin escribe en «Servidor de salida». Los códigos son los `hint` de correo_smtp_guarda_candidato. */
export function validaServidor(i: { host?: unknown; port?: unknown; user?: unknown; pass?: unknown; nombre?: unknown }): ServidorValido | ServidorMalo {
  const host = normalizaHost(i.host);
  if (!host) return { error: 'El servidor tiene que ser un nombre público (como smtp.tuproveedor.com), no una IP ni un nombre interno.', codigo: 'host_no_valido' };
  if (i.port !== PUERTO_SMTP) return { error: 'El puerto tiene que ser 465 (conexión cifrada): la plataforma bloquea el 25 y el 587.', codigo: 'puerto_no_valido' };
  const user = typeof i.user === 'string' ? i.user.trim() : '';
  if (user === '' || [...user].length > LIMITES_SMTP.usuario || tieneControl(user)) return { error: 'El usuario del buzón va de 1 a 254 caracteres y sin caracteres de control.', codigo: 'usuario_no_valido' };
  const pass = typeof i.pass === 'string' ? i.pass : '';
  if (pass === '' || [...pass].length > LIMITES_SMTP.clave || tieneControl(pass)) return { error: 'La contraseña del buzón va de 1 a 200 caracteres y sin saltos de línea.', codigo: 'clave_no_valida' };
  const nombre = i.nombre === undefined || i.nombre === null ? '' : typeof i.nombre === 'string' ? i.nombre.trim() : null;
  if (nombre === null || [...nombre].length > LIMITES_SMTP.nombre || tieneControl(nombre) || /[<>]/.test(nombre)) return { error: 'El nombre del remitente admite 60 caracteres, sin < ni >.', codigo: 'nombre_no_valido' };
  return { host, port: PUERTO_SMTP, user, pass, nombre };
}

// ── ¿A qué IP resuelve el servidor? Una dirección pública y nada más ──────────────────────────────────────────────────────
function v4Partes(s: string): number[] | null {
  const m = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(s);
  if (!m) return null;
  const p = m.slice(1).map(Number);
  return p.every((x) => x <= 255) ? p : null;
}
function v4Publica(p: number[]): boolean {
  const [a, b, c] = p;
  if (a === 0 || a === 10 || a === 127 || a >= 224) return false;                   // «esta red», privada, bucle, multidifusión y reservadas
  if (a === 100 && b >= 64 && b <= 127) return false;                               // 100.64/10 (CGNAT)
  if (a === 169 && b === 254) return false;                                         // enlace local (incluye los metadatos de la nube)
  if (a === 172 && b >= 16 && b <= 31) return false;
  if (a === 192 && b === 168) return false;
  if (a === 192 && b === 0 && c === 0) return false;                                // 192.0.0/24
  if ((a === 192 && b === 0 && c === 2) || (a === 198 && b === 51 && c === 100) || (a === 203 && b === 0 && c === 113)) return false;   // documentación
  if (a === 198 && (b === 18 || b === 19)) return false;                            // pruebas de red 198.18/15
  return true;
}
function v6Grupos(s: string): number[] | null {
  let t = s.toLowerCase().replace(/%.*$/, '');
  const i4 = t.lastIndexOf('.');
  if (i4 !== -1) {                                                                  // sufijo IPv4 (::ffff:1.2.3.4)
    const p = v4Partes(t.slice(t.lastIndexOf(':') + 1));
    if (!p) return null;
    t = t.slice(0, t.lastIndexOf(':') + 1) + ((p[0] << 8) | p[1]).toString(16) + ':' + ((p[2] << 8) | p[3]).toString(16);
  }
  const dos = t.split('::');
  if (dos.length > 2) return null;
  const trozo = (x: string) => (x === '' ? [] : x.split(':'));
  const izq = trozo(dos[0]), der = dos.length === 2 ? trozo(dos[1]) : [];
  if (dos.length === 1 && izq.length !== 8) return null;
  const relleno = dos.length === 2 ? 8 - izq.length - der.length : 0;
  if (relleno < 0 || (dos.length === 2 && relleno < 1)) return null;
  const g = [...izq, ...Array(relleno).fill('0'), ...der];
  if (g.length !== 8 || !g.every((x) => /^[0-9a-f]{1,4}$/.test(x))) return null;
  return g.map((x) => parseInt(x, 16));
}
/** ¿Es una IP pública a la que se puede conectar? IPv4 o IPv6; todo lo que no se entienda cuenta como NO pública (se cierra). */
export function esIpPublica(ip: unknown): boolean {
  if (typeof ip !== 'string') return false;
  const p4 = v4Partes(ip);
  if (p4) return v4Publica(p4);
  if (!ip.includes(':')) return false;
  const g = v6Grupos(ip);
  if (!g) return false;
  const [a, b, c, d, e, f, x, y] = g;
  if (g.every((n) => n === 0)) return false;                                        // ::
  if (a === 0 && b === 0 && c === 0 && d === 0 && e === 0 && f === 0 && x === 0 && y === 1) return false;   // ::1
  const incrustada = [x >> 8, x & 255, y >> 8, y & 255];
  if (a === 0 && b === 0 && c === 0 && d === 0 && e === 0 && (f === 0xffff || f === 0)) return v4Publica(incrustada);   // ::ffff:a.b.c.d y ::a.b.c.d
  if (a === 0x64 && b === 0xff9b) return v4Publica(incrustada);                     // NAT64: manda la IPv4 que lleva dentro
  if (a === 0x2002) return v4Publica([b >> 8, b & 255, c >> 8, c & 255]);           // 6to4
  if ((a & 0xfe00) === 0xfc00) return false;                                        // fc00::/7 (única local)
  if ((a & 0xffc0) === 0xfe80 || (a & 0xffc0) === 0xfec0) return false;            // enlace local y sitio local
  if ((a & 0xff00) === 0xff00) return false;                                        // multidifusión
  if (a === 0x2001 && b === 0x0db8) return false;                                   // documentación
  return (a & 0xe000) === 0x2000;                                                   // solo el espacio unicast global 2000::/3
}

// ── ¿Con qué remitente sale el correo? ────────────────────────────────────────────────────────────────────────────────────
export type Remitente = { from: string; motivo: '' | 'sin_remitente' | 'dominio_distinto' | 'no_valido' };
function dominioDe(d: string): string { return d.slice(d.lastIndexOf('@') + 1).toLowerCase(); }

/** El remitente efectivo (F3.1, A4). `emailFrom` es la clave de Ajustes (puede estar vacía o mal); `buzon` es la dirección del buzón con el que
 *  se envía (el usuario del SMTP si es un correo; si no, el SMTP_FROM de entorno); `dominioWeb` es el dominio de la instancia.
 *  Se usa `emailFrom` SOLO si es un correo válido, sin caracteres de control, y su dominio es el del buzón, el del usuario SMTP o el propio de la
 *  instancia (o un subdominio suyo): un remitente de un dominio ajeno saldría rechazado o como suplantación. Si no, sale el buzón y
 *  `motivo` dice por qué (código, nunca la dirección: va al log). `from === ''` = ni uno ni otro valen: no se puede enviar. */
export function remitenteEfectivo(o: { emailFrom: unknown; buzon: unknown; usuario?: unknown; dominioWeb: unknown }): Remitente {
  const buzon = typeof o.buzon === 'string' && esEmail(o.buzon.trim()) ? o.buzon.trim() : '';
  const usuario = typeof o.usuario === 'string' && esEmail(o.usuario.trim()) ? o.usuario.trim() : '';
  const dom = normalizaDominio(o.dominioWeb);
  const crudo = typeof o.emailFrom === 'string' ? o.emailFrom.trim() : '';
  const noTexto = o.emailFrom !== undefined && o.emailFrom !== null && typeof o.emailFrom !== 'string';
  if (crudo === '' && !noTexto) return { from: buzon, motivo: buzon ? '' : 'sin_remitente' };
  if (noTexto || !esEmail(crudo) || tieneControl(crudo)) return { from: buzon, motivo: buzon ? 'no_valido' : 'sin_remitente' };
  const d = dominioDe(crudo);
  const ok = (buzon !== '' && dominioDe(buzon) === d) || (usuario !== '' && dominioDe(usuario) === d) || (dom !== '' && esDominioPropio(crudo, dom));
  return ok ? { from: crudo, motivo: '' } : { from: buzon, motivo: buzon ? 'dominio_distinto' : 'sin_remitente' };
}

/** «Responder a»: el correo válido de Ajustes o nada (un valor roto no debe parar un envío ni inyectar cabeceras). */
export function replyToEfectivo(v: unknown): string {
  const s = typeof v === 'string' ? v.trim() : '';
  return s !== '' && esEmail(s) && !tieneControl(s) ? s : '';
}

/** Proveedores de correo GRATUITO. Si el dominio del `email_from` o del usuario del servidor SMTP es uno de estos, NO cuenta como «propio» (revisión de Seguridad,
 *  8-oct-2026): los avisos de reservas/CRM llevan datos personales de clientes y redirigirlos a un Gmail cualquiera, sin código de por medio, sería una fuga. El
 *  dominio de la empresa (`dominio_web`) siempre cuenta: es suyo aunque fuese uno de estos. LA MISMA lista vive en SQL (`_correo_buzon_propio`, array v_gratis):
 *  si cambia una, cambia la otra (la prueba SQL F12 y la de node fijan los dos lados). */
export const CORREO_GRATUITO: readonly string[] = ['gmail.com', 'googlemail.com', 'outlook.com', 'hotmail.com', 'live.com', 'msn.com', 'yahoo.com', 'ymail.com',
  'icloud.com', 'me.com', 'proton.me', 'protonmail.com', 'aol.com', 'gmx.com', 'gmx.net', 'mail.com', 'zoho.com'];

/** ¿Vale `buzon` como buzón de aviso interno? (decisión del owner, 7-oct-2026) Un correo válido cuyo dominio sea el de la instancia
 *  (dominio_web o un subdominio), el del `email_from` de Ajustes o el del usuario del servidor SMTP (`usuarioSmtp`; '' si no se conoce).
 *  De email_from y del servidor vale el dominio COMPLETO exacto, salvo que sea de correo gratuito (CORREO_GRATUITO); `x@dominio.com.fraude.ru` no pasa. */
export function buzonAvisoValido(buzon: string, o: { dominio: string; emailFrom?: string; usuarioSmtp?: string }): boolean {
  const b = String(buzon ?? '').trim();
  if (!esEmail(b) || tieneControl(b)) return false;
  const d = dominioDe(b).replace(/\.$/, '');
  if (esDominioPropio(b, o.dominio)) return true;
  if (CORREO_GRATUITO.includes(d)) return false;
  return [o.emailFrom, o.usuarioSmtp].some((x) => {
    const t = String(x ?? '').trim();
    return esEmail(t) && !tieneControl(t) && dominioDe(t).replace(/\.$/, '') === d;
  });
}
