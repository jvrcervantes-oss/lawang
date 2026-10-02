// plantillas-guardar — guarda el texto de una plantilla de correo (S5.1 de Ajustes, 2-oct-2026).
// Encargo encargos/20260930_erp_ajustes_pantalla.md → «Plan de S5», revisión previa #191 (Seguridad + Datos).
//
// POR QUÉ ES UNA EDGE Y NO UNA RPC LLAMADA DESDE LA PANTALLA: `correo_plantillas` no tiene ningún permiso para public/anon/authenticated
// y la RPC `correo_plantilla_guardar` solo la ejecuta service_role. El navegador no escribe en la base: pide a esta edge, que comprueba
// QUIÉN es y qué manda, y es ella (con la clave de servicio) la que llama a la RPC. La RPC no se fía de la edge: vuelve a comprobar que
// el actor es un super admin activo y repite la validación del texto.
//
// POST JSON {clave, asunto, cuerpo, cuerpo_alt, activa, motivo?}
//   · «restaurar fábrica» = asunto, cuerpo y cuerpo_alt a null con activa:false.
//   · 200 {ok:true, version, activa, cambiado} · 400 {ok:false, error, errores?} · 401 sin sesión · 403 no es super admin / origen
//     · 405 · 413 · 502 la base no contestó.
// Autorización: Authorization: Bearer <JWT del usuario> (o X-Suite-Token). Vivo en Auth Y fila activa de `usuarios` con rol super_admin.
// El uuid que va a la RPC es el del JWT verificado: nunca uno que venga en el cuerpo.
// CORS solo al origen de la intranet (config_instancia.url_intranet), como envia-correo.
//
// Log: una línea JSON por petición con estado y clave. Nunca el texto de la plantilla ni el motivo.
import { catalogoDe, esClavePlantilla, validaTextoPlantilla, saneaLlamante, type Catalogo } from '../envia-correo/valida.ts';

const env = (k: string) => (Deno.env.get(k) ?? '').trim();
const SUPA_URL = env('SUPABASE_URL').replace(/\/$/, '');
const SUPA_ANON = env('SUPABASE_ANON_KEY');
const SUPA_SERVICE = env('SUPABASE_SERVICE_ROLE_KEY');
const TOPE_CUERPO = 64 * 1024;
const servicio = () => ({ apikey: SUPA_SERVICE, Authorization: 'Bearer ' + SUPA_SERVICE });

async function origenIntranet(): Promise<string> {
  if (!SUPA_URL || !SUPA_SERVICE) return '';
  try {
    const r = await fetch(SUPA_URL + '/rest/v1/config_instancia?select=clave,valor&clave=eq.url_intranet', { headers: servicio(), signal: AbortSignal.timeout(6000) });
    if (!r.ok) return '';
    const f = await r.json() as { clave?: string; valor?: unknown }[];
    const o = new URL(String(f.find((x) => x.clave === 'url_intranet')?.valor ?? '')).origin;
    return o.startsWith('https://') ? o : '';
  } catch { return ''; }
}

/** uuid del usuario si el JWT es de una sesión viva de un super admin ACTIVO; 'no_sesion' | 'no_super' | 'error' si no. */
async function superAdmin(jwt: string): Promise<{ uid: string } | 'no_sesion' | 'no_super' | 'error'> {
  if (!SUPA_URL || !SUPA_ANON || !SUPA_SERVICE) return 'error';
  try {
    const r = await fetch(SUPA_URL + '/auth/v1/user', { headers: { apikey: SUPA_ANON, Authorization: 'Bearer ' + jwt }, signal: AbortSignal.timeout(10_000) });
    if (r.status === 401 || r.status === 403) return 'no_sesion';
    if (r.status !== 200) return 'error';
    const uid = String((await r.json() as { id?: string })?.id ?? '');
    if (!/^[0-9a-f-]{36}$/i.test(uid)) return 'no_sesion';
    const q = await fetch(SUPA_URL + '/rest/v1/usuarios?select=user_id&activo=is.true&rol=eq.super_admin&user_id=eq.' + encodeURIComponent(uid),
      { headers: servicio(), signal: AbortSignal.timeout(10_000) });
    if (q.status !== 200) return 'error';
    const filas = await q.json();
    return Array.isArray(filas) && filas.length === 1 && filas[0]?.user_id === uid ? { uid } : 'no_super';
  } catch { return 'error'; }
}

export async function manejador(req: Request): Promise<Response> {
  const origen = req.headers.get('origin');
  const permitido = await origenIntranet();
  const origenOk = origen && permitido && origen === permitido ? origen : null;
  const cab = new Headers({ 'Content-Type': 'application/json; charset=utf-8' });
  if (origenOk) {
    cab.set('Access-Control-Allow-Origin', origenOk);
    cab.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
    cab.set('Access-Control-Allow-Headers', 'content-type, x-suite-token, authorization, apikey, x-client-info');
    cab.set('Access-Control-Max-Age', '600');
    cab.set('Vary', 'Origin');
  }
  const llamante = saneaLlamante(req.headers.get('x-llamante'));
  let clave = '';
  const resp = (cuerpo: Record<string, unknown>, status = 200) => {
    console.log(JSON.stringify({ fn: 'plantillas-guardar', estado: status, ...(clave ? { clave } : {}), ...(llamante ? { llamante } : {}) }));
    return new Response(JSON.stringify(cuerpo), { status, headers: cab });
  };

  if (origen && !origenOk) return resp({ ok: false, error: 'Origen no permitido' }, 403);
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cab });
  if (req.method !== 'POST') return resp({ ok: false, error: 'Método no permitido' }, 405);

  let jwt = (req.headers.get('x-suite-token') ?? '').trim();
  if (!jwt) { const m = /^Bearer\s+(.+)$/i.exec((req.headers.get('authorization') ?? '').trim()); if (m) jwt = m[1].trim(); }
  if (!jwt || jwt === SUPA_ANON || jwt === SUPA_SERVICE) return resp({ ok: false, error: 'Hace falta la sesión de un super admin' }, 401);
  const quien = await superAdmin(jwt);
  if (quien === 'no_sesion') return resp({ ok: false, error: 'Sesión no válida' }, 401);
  if (quien === 'no_super') return resp({ ok: false, error: 'Cambiar las plantillas de correo exige super admin' }, 403);
  if (quien === 'error') return resp({ ok: false, error: 'No se pudo comprobar la sesión' }, 502);

  if (Number(req.headers.get('content-length') ?? '0') > TOPE_CUERPO) return resp({ ok: false, error: 'La petición es demasiado grande' }, 413);
  let crudo: string;
  try { crudo = await req.text(); } catch { return resp({ ok: false, error: 'JSON inválido' }, 400); }
  if (crudo.length > TOPE_CUERPO) return resp({ ok: false, error: 'La petición es demasiado grande' }, 413);
  let c: Record<string, unknown>;
  try { const j = JSON.parse(crudo); if (!j || typeof j !== 'object' || Array.isArray(j)) throw new Error('forma'); c = j; } catch { return resp({ ok: false, error: 'JSON inválido' }, 400); }

  if (!esClavePlantilla(c.clave)) return resp({ ok: false, error: 'Plantilla no reconocida' }, 400);
  clave = c.clave as string;
  const texto = (v: unknown): string | null | undefined =>
    v === null || v === undefined ? null : typeof v === 'string' ? v.replace(/\r\n?/g, '\n') : undefined;
  const asunto = texto(c.asunto), cuerpo = texto(c.cuerpo), alt = texto(c.cuerpo_alt);
  if (asunto === undefined || cuerpo === undefined || alt === undefined) return resp({ ok: false, error: 'Los textos tienen que ser texto' }, 400);
  if (typeof c.activa !== 'boolean') return resp({ ok: false, error: 'Falta indicar si la plantilla está activa' }, 400);
  const motivo = c.motivo === undefined || c.motivo === null ? null : typeof c.motivo === 'string' ? c.motivo : undefined;
  if (motivo === undefined || (motivo !== null && [...motivo].length > 500)) return resp({ ok: false, error: 'El motivo admite 500 caracteres como máximo' }, 400);

  // Catálogo sellado de ESA clave (única fuente: la columna `variables`) y validación del texto, todos los errores de una vez
  let cat: Catalogo | null;
  try {
    const r = await fetch(SUPA_URL + '/rest/v1/correo_plantillas?select=variables&clave=eq.' + encodeURIComponent(clave), { headers: servicio(), signal: AbortSignal.timeout(8000) });
    if (!r.ok) { await r.text().catch(() => ''); return resp({ ok: false, error: 'No se pudo leer la plantilla' }, 502); }
    const f = await r.json();
    cat = Array.isArray(f) && f.length === 1 ? catalogoDe(f[0]?.variables) : null;
  } catch { return resp({ ok: false, error: 'No se pudo leer la plantilla' }, 502); }
  if (!cat) return resp({ ok: false, error: 'La plantilla no existe o su catálogo no es legible' }, 502);
  if (asunto !== null || cuerpo !== null) {
    const errores = [
      ...validaTextoPlantilla(asunto, 'asunto', cat), ...validaTextoPlantilla(cuerpo, 'cuerpo', cat),
      ...(cat.variantes === 2 ? validaTextoPlantilla(alt, 'cuerpo_alt', cat) : alt !== null ? ['Esta plantilla solo tiene un cuerpo'] : []),
    ];
    if (errores.length) return resp({ ok: false, error: errores[0], errores }, 400);
  }

  try {
    const r = await fetch(SUPA_URL + '/rest/v1/rpc/correo_plantilla_guardar', {
      method: 'POST', headers: { ...servicio(), 'Content-Type': 'application/json' }, signal: AbortSignal.timeout(15_000),
      body: JSON.stringify({ p_actor: quien.uid, p_clave: clave, p_asunto: asunto, p_cuerpo: cuerpo, p_cuerpo_alt: alt, p_activa: c.activa, p_motivo: motivo }),
    });
    const t = await r.text();
    if (r.status === 200) {
      const d = JSON.parse(t) as { version?: number; activa?: boolean; cambiado?: boolean };
      return resp({ ok: true, version: d.version, activa: d.activa, cambiado: d.cambiado });
    }
    let e: { code?: string; message?: string } = {};
    try { e = JSON.parse(t); } catch { /* sin JSON */ }
    if (e.code === '42501') return resp({ ok: false, error: 'Cambiar las plantillas de correo exige super admin' }, 403);
    if (e.code === '22023') return resp({ ok: false, error: String(e.message ?? 'Texto no válido').slice(0, 300) }, 400);
    console.error('plantillas-guardar: RPC HTTP ' + r.status + ' ' + String(e.code ?? ''));
    return resp({ ok: false, error: 'No se pudo guardar' }, 502);
  } catch (e) {
    console.error('plantillas-guardar: ' + String((e as Error)?.name ?? e));
    return resp({ ok: false, error: 'No se pudo guardar' }, 502);
  }
}

Deno.serve(manejador);
