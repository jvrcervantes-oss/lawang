// envia-correo · validación PURA (sin imports, sin red): es lo que cubre valida_test.ts.
// Réplica de las comprobaciones de proyectos/Lawang/contracts/api/send_email.php, con las
// literales de Lawang (dominio, portal) pasadas como parámetro: en el ERP vienen de
// config_instancia de cada instancia.

export const LIMITES = {
  asunto: 200,
  mensaje: 5000,
  encabezado: 120,
  etiqueta: 40,
  ctaTexto: 60,
  nombreFichero: 150,
  // ÚNICA desviación consciente del contrato PHP (140 MB de base64): el runtime de Edge tiene
  // 256 MB de memoria y los servidores de correo rechazan por encima de ~25 MB reales, que es lo
  // que el propio comentario del PHP reconoce. 34 MB de base64 ≈ 25 MB de PDF.
  pdfBase64: 34 * 1024 * 1024,
  html: 25 * 1024 * 1024,
  // tope del cuerpo HTTP entero, antes de parsear el JSON
  cuerpo: 36 * 1024 * 1024,
};

/** Caracteres de control (incluye CR y LF): en un asunto o un nombre de fichero son la vía de
 *  inyección de cabeceras. Se RECHAZAN, no se limpian: todos los llamantes son de casa, así que
 *  un 400 aquí es un bug nuestro que hay que ver. */
export function tieneControl(s: string): boolean {
  return /[\u0000-\u001F\u007F]/.test(s);
}

/** Un solo destinatario, con la forma que acepta FILTER_VALIDATE_EMAIL de PHP en la práctica.
 *  Sin comas, espacios, `<>` ni saltos: nunca una lista ni un "Nombre <dir>". */
export function esEmail(s: string): boolean {
  if (typeof s !== 'string' || s.length > 254 || tieneControl(s)) return false;
  const m = /^([A-Za-z0-9!#$%&'*+/=?^_`{|}~.-]+)@([A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+)$/.exec(s);
  if (!m) return false;
  const [, local, dominio] = m;
  if (local.length > 64 || local.startsWith('.') || local.endsWith('.') || local.includes('..')) return false;
  const etiquetas = dominio.split('.');
  if (etiquetas.some((e) => e.length === 0 || e.length > 63 || e.startsWith('-') || e.endsWith('-'))) return false;
  return /^[A-Za-z]{2,}$/.test(etiquetas[etiquetas.length - 1]);
}

/** Dominio normalizado: minúsculas, sin punto final. '' si no vale como dominio. */
export function normalizaDominio(d: unknown): string {
  const s = String(d ?? '').trim().toLowerCase().replace(/\.$/, '');
  return /^[a-z0-9-]+(\.[a-z0-9-]+)+$/.test(s) ? s : '';
}

function hostEsPropio(host: string, dominio: string): boolean {
  const h = host.toLowerCase();
  return dominio !== '' && (h === dominio || h.endsWith('.' + dominio));
}

/** ¿El destinatario es de NUESTRO dominio (o un subdominio)? Comparación de host completo:
 *  `x@dominio.com.fraude.ru` no pasa. */
export function esDominioPropio(to: string, dominio: string): boolean {
  const i = to.lastIndexOf('@');
  return i > 0 && hostEsPropio(to.slice(i + 1), normalizaDominio(dominio));
}

/** Lista blanca del botón: https hacia el dominio de la instancia (o subdominios), mailto: con
 *  una dirección válida, o https://wa.me/<número>. Con parseo real de URL, nunca `includes`. */
export function ctaPermitida(u: string, dominio: string): boolean {
  if (typeof u !== 'string' || tieneControl(u)) return false;
  if (/^mailto:/i.test(u)) return esEmail(u.slice(7));
  if (/^https:\/\/wa\.me\//i.test(u)) return /^https:\/\/wa\.me\/\d{6,20}$/.test(u);
  let p: URL;
  try { p = new URL(u); } catch { return false; }
  if (p.protocol !== 'https:' || !p.hostname || p.username || p.password) return false;
  return hostEsPropio(p.hostname, normalizaDominio(dominio));
}

/** Nombre del adjunto: misma regla Unicode que el PHP (\p{L}\p{N}+_-.), más tope de largo. */
export function limpiaNombreFichero(s: unknown): string {
  let n = String(s ?? 'contrato.pdf').replace(/[^\p{L}\p{N}+_\-.]/gu, '_').slice(0, LIMITES.nombreFichero);
  if (n === '' || /^\.+$/.test(n)) n = 'documento.pdf';
  return n;
}

/** base64 estricto (admite saltos de línea, que se quitan) → bytes, o null. */
export function decodificaBase64(s: string): Uint8Array | null {
  const limpio = s.replace(/\s+/g, '');
  if (limpio === '' || limpio.length % 4 !== 0 || !/^[A-Za-z0-9+/]*={0,2}$/.test(limpio)) return null;
  try {
    const bin = atob(limpio);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  } catch { return null; }
}

export function esPdf(b: Uint8Array | null): boolean {
  return !!b && b.length >= 4 && b[0] === 0x25 && b[1] === 0x50 && b[2] === 0x44 && b[3] === 0x46; // %PDF
}

/** Comparación de secretos en tiempo constante (hash_equals del PHP). */
export function igualSeguro(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a), y = new TextEncoder().encode(b);
  let d = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) d |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return d === 0 && x.length > 0;
}

export type Peticion = {
  to: string; subject: string; message: string; filename: string;
  pdfBase64: string; html: string; attach: boolean;
  encabezado: string; etiqueta: string; contacto: 'sales' | null;
  ctaUrl: string; ctaTexto: string; preview: boolean;
};

/** `extra` viaja en la respuesta JSON junto a `error` (hoy: los campos estructurados del fallo de SMTP). */
export type Fallo = { error: string; status: number; extra?: Record<string, unknown> };

/** Lee el cuerpo con los mismos valores por defecto que el PHP. No decide autorización. */
export function leePeticion(entrada: unknown): Peticion | Fallo {
  if (!entrada || typeof entrada !== 'object' || Array.isArray(entrada)) return { error: 'JSON inválido', status: 400 };
  const i = entrada as Record<string, unknown>;
  const txt = (v: unknown, def = '') => (v === undefined || v === null ? def : String(v));
  return {
    to: txt(i.to).trim(),
    subject: txt(i.subject).trim(),   // vacío → index.ts pone «Documento — <marca>» (el PHP ponía la de Lawang)
    message: txt(i.message).trim(),
    filename: limpiaNombreFichero(i.filename ?? 'contrato.pdf'),
    pdfBase64: txt(i.pdf_base64),
    html: txt(i.html),
    attach: i.attach !== false,
    encabezado: txt(i.encabezado).trim(),
    etiqueta: txt(i.etiqueta).trim(),
    contacto: i.contacto === 'sales' ? 'sales' : null,
    ctaUrl: txt(i.cta_url).trim(),
    ctaTexto: txt(i.cta_texto).trim(),
    preview: i.preview === true,
  };
}

const largo = (s: string) => [...s].length;   // mb_strlen: cuenta caracteres, no bytes ni unidades UTF-16

/** Campos comunes a vista previa y envío (textos que acaban en cabecera o en la tarjeta). */
export function validaTextos(p: Peticion): Fallo | null {
  if (largo(p.encabezado) > LIMITES.encabezado || tieneControl(p.encabezado)) return { error: 'Encabezado demasiado largo o no válido', status: 400 };
  if (largo(p.etiqueta) > LIMITES.etiqueta || tieneControl(p.etiqueta)) return { error: 'Etiqueta demasiado larga o no válida', status: 400 };
  if (largo(p.subject) > LIMITES.asunto) return { error: 'Asunto demasiado largo', status: 400 };
  if (tieneControl(p.subject)) return { error: 'El asunto no puede llevar saltos de línea ni caracteres de control', status: 400 };
  if (largo(p.message) > LIMITES.mensaje) return { error: 'Mensaje demasiado largo', status: 400 };
  if (largo(p.ctaTexto) > LIMITES.ctaTexto || tieneControl(p.ctaTexto)) return { error: 'cta_texto demasiado largo', status: 400 };
  return null;
}

/** Validación de un envío real (tras la pausa, antes de la vía 3), en el orden del PHP. */
export function validaEnvio(p: Peticion): Fallo | null {
  if (!esEmail(p.to)) return { error: 'Destinatario no válido', status: 400 };
  const t = validaTextos(p); if (t) return t;
  if (!p.attach && p.message === '') return { error: 'Un correo sin adjunto necesita mensaje', status: 400 };
  if (p.attach && p.pdfBase64 === '' && p.html === '') return { error: 'Falta el PDF o el HTML a renderizar', status: 400 };
  if (p.pdfBase64.length > LIMITES.pdfBase64) return { error: 'El PDF es demasiado grande', status: 400 };
  if (p.html.length > LIMITES.html) return { error: 'El HTML es demasiado grande', status: 400 };
  return null;
}

/** Botón del correo, mismo orden que el PHP: impuesto por quien llama (contra lista blanca) →
 *  enlace de firma en el mensaje → enlace a la intranet si va a alguien de casa → portal. */
export function deduceCta(p: Peticion, dominio: string, urlPortal: string, destinoInterno: boolean, urlIntranet = ''):
  { url: string; texto: string } | Fallo {
  const d = normalizaDominio(dominio);
  if (p.ctaUrl !== '') {
    if (!ctaPermitida(p.ctaUrl, d)) return { error: 'cta_url no permitida: solo https hacia ' + d + ' (o sus subdominios), mailto: y https://wa.me/', status: 400 };
    if (p.ctaTexto === '') return { error: 'cta_url sin cta_texto: media pareja no pinta medio botón', status: 400 };
    return { url: p.ctaUrl, texto: p.ctaTexto };
  }
  const firma = /https:\/\/[A-Za-z0-9.-]+\/contracts\/firmar[.]html[?]t=[A-Za-z0-9._-]+/.exec(p.message);
  if (firma && ctaPermitida(firma[0], d)) return { url: firma[0], texto: 'Firmar el documento' };
  const intra = /https:\/\/[A-Za-z0-9.-]+\/intranet\/[A-Za-z0-9._/?=-]*/.exec(p.message);
  if (destinoInterno && intra && ctaPermitida(intra[0], d)) return { url: intra[0], texto: 'Abrir en la intranet' };
  // URLs limpias (AXW-103/AXW-140): el ERP de la instancia cuelga de la raíz de su `url_intranet`, sin /intranet/. Un
  // enlace del mensaje a ESE origen (y no a /portal/, que es del cliente) es también «Abrir en la intranet».
  const nueva = destinoInterno ? enlaceDeLaInstancia(p.message, urlIntranet) : '';
  if (nueva !== '' && ctaPermitida(nueva, d)) return { url: nueva, texto: 'Abrir en la intranet' };
  return { url: urlPortal, texto: 'Entrar · Sign in' };
}

/** Primer enlace del mensaje cuyo ORIGEN es exactamente el de `url_intranet` y que no cae en /portal/ ni en
 *  /contracts/ (assets y firma: otras vías). '' si no hay `url_intranet` válida o ningún enlace así. */
function enlaceDeLaInstancia(mensaje: string, urlIntranet: string): string {
  let origen: string;
  try {
    const b = new URL(urlIntranet);
    // Solo una instancia con el ERP en la RAÍZ (url_intranet = https://host/). Con /intranet/ en la ruta (Lawang) la rama
    // no existe: cualquier enlace a su web pública pasaría a ser el botón de la intranet.
    if (b.pathname !== '/') return '';
    origen = b.origin;
  } catch { return ''; }
  if (!origen.startsWith('https://')) return '';
  for (const m of mensaje.matchAll(/https:\/\/[A-Za-z0-9.-]+(?::\d+)?\/[A-Za-z0-9._\/?=&%#-]*/g)) {
    let u: URL;
    try { u = new URL(m[0]); } catch { continue; }
    if (u.origin === origen && !/^\/(portal|contracts)(\/|$)/.test(u.pathname)) return m[0];
  }
  return '';
}

export function esFallo(x: unknown): x is Fallo {
  return !!x && typeof x === 'object' && 'error' in x && 'status' in x;
}

// ── decisiones de la edge que no necesitan red (para poder probarlas con node y con deno) ─────────

/** El texto EXACTO del 503 de pausa. Dos crons de Lawang (avisos-manager, comunicados-envio) lo detectan con
 *  /en pausa \(modo mantenimiento\)/i: cambiarlo sin cambiarlos a ellos los deja sin freno y sin dar error. */
export const TEXTO_PAUSA = 'Los envíos de correo están en pausa (modo mantenimiento). No se ha enviado nada.';

/** Cabecera X-Llamante saneada: solo para atribuir la línea del log (nunca decide nada). Máx. 40. */
export function saneaLlamante(v: unknown): string {
  return String(v ?? '').trim().replace(/[^A-Za-z0-9._:@\/-]/g, '_').slice(0, 40);
}

export type ViaServicio = 'servicio' | 'servicio-render' | '';
/** Vía «servicio» (cabecera X-Render-Secret; el nombre de la cabecera no cambia). Si existe ENVIO_CORREO_SECRET
 *  es el ÚNICO que vale; si no existe, cae a RENDER_SECRET (el maestro sigue como estaba) y se anota como
 *  'servicio-render' para que el log muestre que aún no se ha separado la autoridad de envío de la de render. */
export function viaServicio(cabecera: string, envioSecret: string, renderSecret: string): ViaServicio {
  if (cabecera === '') return '';
  if (envioSecret !== '') return igualSeguro(cabecera, envioSecret) ? 'servicio' : '';
  return renderSecret !== '' && igualSeguro(cabecera, renderSecret) ? 'servicio-render' : '';
}

export type ViaAviso = 'aviso' | 'aviso-interno' | null;
/** Vía de aviso interno: solo texto sin adjunto y solo a los buzones de aviso de la instancia. Con
 *  ENVIO_AVISO_SECRET definido hace falta X-Aviso-Secret ('aviso') y la puerta anónima queda CERRADA; sin él
 *  se conserva la antigua vía 3 anónima ('aviso-interno'). */
export function viaAviso(o: { secretoEnv: string; cabecera: string; attach: boolean; to: string; avisos: string[] }): ViaAviso {
  if (o.attach || !o.avisos.includes(o.to.toLowerCase())) return null;
  if (o.secretoEnv !== '') return igualSeguro(o.cabecera, o.secretoEnv) ? 'aviso' : null;
  return 'aviso-interno';
}

export type FalloSmtp = { texto: string; smtp_code: string; smtp_response_code: number | null; log: string };
/** Fallo de nodemailer → texto para el llamante + campos estructurados + fragmento para el log.
 *  El texto lleva SOLO piezas cerradas: el código de nodemailer, el numérico (554) y el estado mejorado
 *  (5.7.1), extraídos por regex, más la frase «Outbound sending is disabled» si (y solo si) el servidor la dijo.
 *  Los llamantes (avisos-manager, comunicados-envio) buscan 554 / 5.7.1 / esa frase en este texto para parar la
 *  tanda. La línea libre del servidor (`response`) puede llevar la cuenta o el banner: nunca se copia, y el log
 *  recibe solo `log` (código + números). */
export function describeFalloSmtp(e: unknown): FalloSmtp {
  const o = (e && typeof e === 'object' ? e : {}) as { code?: unknown; responseCode?: unknown; response?: unknown };
  const resp = typeof o.response === 'string' ? o.response : '';
  const code = typeof o.code === 'string' && /^[A-Za-z0-9_]{1,30}$/.test(o.code) ? o.code : 'desconocido';
  let num: number | null = null;
  const rc = typeof o.responseCode === 'number' ? o.responseCode : /^\d{3}$/.test(String(o.responseCode ?? '')) ? Number(o.responseCode) : NaN;
  if (Number.isInteger(rc) && rc >= 200 && rc <= 599) num = rc;
  else { const m = /^(\d{3})[ -]/.exec(resp); if (m && Number(m[1]) >= 200 && Number(m[1]) <= 599) num = Number(m[1]); }
  const est = /^\d{3}[ -]([245]\.\d{1,3}\.\d{1,3})(?![\d.])/m.exec(resp)?.[1] ?? '';   // solo el estado que sigue al código de respuesta, no cualquier número con puntos
  const piezas = [num === null ? '' : String(num), est, code === 'desconocido' && (num !== null || est !== '') ? '' : code].filter((x) => x !== '');
  const frase = /Outbound sending is disabled/i.test(resp) ? 'Outbound sending is disabled' : '';
  const dentro = piezas.length ? piezas.join(', ') : 'desconocido';
  return {
    texto: 'No se pudo enviar por SMTP (' + dentro + ')' + (frase ? ': ' + frase : ''),
    smtp_code: code, smtp_response_code: num, log: dentro,
  };
}
