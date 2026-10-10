// lawang-bot-proxy — puente entre la intranet y el bot de WhatsApp de Lawang.
// 10-sep-2026. Revisión previa: Bots + Seguridad + Legal (plan en
// CEO/revisiones/estado.json y hallazgos en contexto/pendientes.md).
//
// POR QUÉ EXISTE. El bot (`lawang-bot`, Railway) protege sus `/admin/api/*` con
// una clave (`X-Admin-Key`), y esa clave NUNCA puede llegar al navegador — un
// `fetch` desde la intranet con la clave en el cliente la deja en cualquier
// devtools. Aquí la clave vive como secreto de la función (`LAWANG_BOT_ADMIN_KEY`)
// y nunca sale de este servidor.
//
// WHITELIST EXPLÍCITA, NO PASSTHROUGH. El bot tiene más endpoints admin de los
// que esta pestaña necesita (envío de plantillas, newsletters, medios…) — un
// proxy que reenviara cualquier `path` que le pidan convertiría un password de
// panel interno en un password de API abierta a lo que sea. Solo las acciones
// de abajo, cada una con su propio chequeo de permiso.
//
// PERMISOS DISTINTOS (no uno): 'leads' para mirar conversaciones/pausar el
// bot (ya lo tiene cualquiera que vea el CRM de leads); 'bot_escribir'
// (11-sep-2026) para enviar mensajes al lead, que es lo único que produce algo
// que ve un cliente real — de ahí que no venga de regalo con 'leads'; y
// 'bot_configurar' para la configuración. La agenda de citas ('closers') dejó
// este proxy el 9-oct-2026: ahora vive en Postgres (ver más abajo).
//
// CONFIGURACIÓN DEL BOT (S3 del encargo «bot sin Redis», 9-oct-2026). Dos almacenes, un interruptor:
//   BOT_CONFIG_STORE = 'redis' (por defecto, o sin definir) -> config_get/set/revert se reenvían al bot, que la guarda en Redis (como siempre).
//   BOT_CONFIG_STORE = 'postgres'                          -> se leen y escriben en bot_config por las RPC crm_bot_config_* (la base comprueba el
//                                                            permiso otra vez y compara la versión bajo FOR UPDATE). El bot solo la LEE.
// POR QUÉ UN INTERRUPTOR: el bot vivo sigue leyendo su configuración de Redis hasta que S4b lo cambie. Si esto escribiera ya en Postgres, la
// pantalla diría «Guardado» y el bot seguiría obedeciendo a Redis. Se pasa a 'postgres' en el corte (S8), DESPUÉS de importar la config de
// Redis (S5) y con el bot leyendo bot_turno_estado. Vuelta atrás: poner 'redis'.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const URL_SB = Deno.env.get('SUPABASE_URL')!;
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const admin = createClient(URL_SB, SERVICE);

const BOT_BASE = 'https://lawang-bot-production.up.railway.app';
const BOT_KEY = Deno.env.get('LAWANG_BOT_ADMIN_KEY') ?? '';

const ORIGENES = [
  'https://lawangproperties.com',
  'https://www.lawangproperties.com',
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

// El bot responde JSON siempre (o texto plano en algún caso raro) — se
// reenvía tal cual, sin reinterpretarlo, para no inventar una forma nueva de
// error que el frontend tenga que aprender aparte de la del bot real.
// `jwt` (solo en enviar, enviar_plantilla y pausar): la sesión de la PERSONA, para que el bot compruebe él mismo su permiso (acción `verificar` de la edge
// bot-api; encargo «bot sin Redis», apartado c). Va en `X-User-Jwt`, sin «Bearer »; el bot actual lo ignora. NUNCA se registra en ningún log.
// Seguridad (10-oct-2026, «reducir la exposición»): un JWT de sesión es un bearer completo; no viaja al bot mientras el bot no lo use. Interruptor del secreto de la edge
// BOT_ENVIA_JWT=on, que se enciende en el mismo paso que BOT_HUMANO_VERIFICA=sombra|on del bot (y solo tras comprobar que el bot no lo registra).
const enviaJwtAlBot = () => (Deno.env.get('BOT_ENVIA_JWT') ?? '').trim().toLowerCase() === 'on';
async function llamaBot(path: string, init: RequestInit = {}, jwt?: string) {
  if (!BOT_KEY) {
    return { status: 503, body: { error: 'lawang-bot-proxy no configurado (falta LAWANG_BOT_ADMIN_KEY)' } };
  }
  const r = await fetch(BOT_BASE + path, {
    ...init,
    headers: { ...(init.headers ?? {}), 'X-Admin-Key': BOT_KEY, 'Content-Type': 'application/json', ...(jwt && enviaJwtAlBot() ? { 'X-User-Jwt': jwt } : {}) },
  });
  const texto = await r.text();
  let body: unknown;
  try { body = JSON.parse(texto); } catch { body = { error: texto || 'respuesta vacía del bot' }; }
  return { status: r.status, body };
}

// ── /humano de la edge bot-api (S4b, 9-oct-2026) ──────────────────────────────────────────────────────────────
// Con BOT_STORE=postgres el bot ya no guarda nada como persona: ni la pausa ni el registro de un envío. Lo hace ESTE proxy, que es el único
// que tiene a la vez el secreto de /humano (BOT_API_SECRET_HUMANO, solo en la edge, nunca en Railway) y el JWT de la persona (la edge lo verifica
// contra Auth y de ahí sale el usuario; un `usuario` en el cuerpo es 400). Interruptor BOT_HUMANO_STORE=postgres: se enciende en el corte S8 JUNTO con
// BOT_STORE=postgres del bot. Fuera de sincronía, la pausa de la pantalla daría 410 (bot nuevo) o no quedaría en la base (proxy nuevo).
const humanoEnPostgres = () => (Deno.env.get('BOT_HUMANO_STORE') ?? '').trim().toLowerCase() === 'postgres';
async function llamaHumano(jwt: string, cuerpo: Record<string, unknown>): Promise<{ status: number; body: Record<string, unknown> }> {
  const secreto = (Deno.env.get('BOT_API_SECRET_HUMANO') ?? '').trim();
  if (!secreto) return { status: 503, body: { error: 'humano_sin_configurar' } };
  try {
    const r = await fetch(`${URL_SB}/functions/v1/bot-api/humano`, {
      method: 'POST',
      headers: { 'X-Bot-Secret': secreto, Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(cuerpo),
      signal: AbortSignal.timeout(12000),
    });
    const b = await r.json().catch(() => ({}));
    return { status: r.status, body: (b && typeof b === 'object' ? b : {}) as Record<string, unknown> };
  } catch { return { status: 502, body: { error: 'bot_api_sin_respuesta' } }; }
}
/** Traduce la respuesta NO buena de /humano a códigos cerrados PROPIOS: nunca se reenvía el `error` de bot-api (podría traer texto de la edge o de Postgres), y un
 *  401 o 429 de bot-api no sube con su código — un secreto mal puesto (401) no debe leerse en la pantalla como «sesión caducada» (la sesión ya la comprobó este proxy). */
function falloHumano(h: { status: number; body: Record<string, unknown> }): { status: number; body: { error: string } } {
  if (h.status === 200) {
    const e = h.body.error;
    if (e === 'sin_chat') return { status: 404, body: { error: 'sin_chat' } };
    if (e === 'sin_usuario') return { status: 400, body: { error: 'usuario_no_valido' } };
    return { status: 400, body: { error: 'valor_no_valido' } };   // telefono_invalido, modo_invalido… o un código que no conocemos
  }
  if (h.status === 429) return { status: 429, body: { error: 'demasiadas' } };
  if (h.body.error === 'humano_sin_configurar') return { status: 503, body: { error: 'humano_sin_configurar' } };   // el propio proxy sin secreto
  return { status: 502, body: { error: 'bot_api_no_disponible' } };   // 401 (secreto mal puesto), 5xx, sin respuesta, 400 de forma del cuerpo…
}
/** Tras un envío correcto del bot: lo anota en la conversación como mensaje de una persona (con el wamid de Meta). El envío ya salió: si esto falla se avisa, no se deshace. */
async function registraEnvio(jwt: string, phone: string, bot: { status: number; body: unknown }) {
  const b = (bot.body ?? {}) as Record<string, unknown>;
  const reg = (b.registrar ?? null) as { texto?: unknown; wamid?: unknown } | null;
  if (bot.status !== 200 || b.ok !== true || !reg || typeof reg.texto !== 'string') return bot;
  const wamid = typeof reg.wamid === 'string' && reg.wamid ? reg.wamid : `h-${phone}-${Date.now()}`;
  const h = await llamaHumano(jwt, { accion: 'enviar', tel: phone, texto: reg.texto, wamid });
  const { registrar: _r, ...resto } = b;   // eslint-disable-line @typescript-eslint/no-unused-vars
  return { status: 200, body: { ...resto, registrado: h.status === 200 && h.body.ok === true } };
}

// ── Validación de la configuración (portada de botcfg.js `validaConfig`: la MISMA regla, ahora en el servidor que escribe) ──────────
// Si cambia una, cambia la otra mientras el bot siga escribiendo en Redis: lawang_bot_proxy.test.js pasa los casos de test-botcfg.js por esta.
const MAX_EXTRA = 2000;
const MAX_BIENVENIDA = 500;
const MAX_PAUSA_HORAS = 720;
const CLAVES_CFG = ['extra', 'bienvenida', 'pausaHoras'];
const RE_TELEFONO_CAND = /(?:\+|00)?\d(?:[ -]?\d){8,}/g;
const RE_CORREO = /[^\s@]+@[^\s@]+\.[^\s@]+/;
export function pareceTelefono(t: string): boolean {
  for (const m of String(t).matchAll(RE_TELEFONO_CAND)) {
    const c = m[0];
    if (/^\d{4}-\d{2}-\d{2}$/.test(c)) continue;          // fecha ISO
    if (/^[1-9]\d{0,2}(?: \d{3})+$/.test(c)) continue;    // miles con espacio
    return true;
  }
  return false;
}
export function neutraliza(t: string): string {
  return String(t).replace(/<<</g, '‹‹‹').replace(/>>>/g, '›››').replace(/\r\n/g, '\n').trim();
}
export function validaConfig(input: unknown): { ok: true; value: { extra: string; bienvenida: string; pausaHoras: number } } | { ok: false; error: string } {
  if (!input || typeof input !== 'object' || Array.isArray(input)) return { ok: false, error: 'cuerpo no válido' };
  const c = input as Record<string, unknown>;
  for (const k of Object.keys(c)) if (!CLAVES_CFG.includes(k)) return { ok: false, error: `clave desconocida: ${k}` };
  const extra = c.extra === undefined ? '' : c.extra;
  const bienvenida = c.bienvenida === undefined ? '' : c.bienvenida;
  const pausaHoras = c.pausaHoras === undefined ? 0 : c.pausaHoras;
  if (typeof extra !== 'string') return { ok: false, error: 'extra debe ser texto' };
  if (typeof bienvenida !== 'string') return { ok: false, error: 'bienvenida debe ser texto' };
  if (extra.length > MAX_EXTRA) return { ok: false, error: `extra pasa de ${MAX_EXTRA} caracteres` };
  if (bienvenida.length > MAX_BIENVENIDA) return { ok: false, error: `bienvenida pasa de ${MAX_BIENVENIDA} caracteres` };
  if (typeof pausaHoras !== 'number' || !Number.isInteger(pausaHoras) || pausaHoras < 0 || pausaHoras > MAX_PAUSA_HORAS)
    return { ok: false, error: `pausaHoras debe ser un entero entre 0 y ${MAX_PAUSA_HORAS}` };
  for (const [campo, t] of [['extra', extra], ['bienvenida', bienvenida]] as const) {
    if (RE_CORREO.test(t)) return { ok: false, error: `${campo}: no pongas correos (lo ve el bot en todas las conversaciones)` };
    if (pareceTelefono(t)) return { ok: false, error: `${campo}: no pongas teléfonos (lo ve el bot en todas las conversaciones)` };
  }
  return { ok: true, value: { extra: neutraliza(extra), bienvenida: neutraliza(bienvenida), pausaHoras } };
}

// Traduce el fallo de una RPC crm_bot_config_* a una respuesta SIN texto de Postgres (el detalle va solo al log de la edge).
function falloRpc(e: { code?: string; message?: string } | null | undefined, que: string): { status: number; body: Record<string, unknown> } {
  if (e?.code === '42501') return { status: 403, body: { error: 'sin_permiso: bot_configurar' } };
  if (e?.code === 'PT400') return { status: 400, body: { error: 'valor_no_valido' } };
  console.error(`lawang-bot-proxy: ${que} fallo (${e?.code ?? '?'}): ${e?.message ?? ''}`);
  return { status: 500, body: { error: 'no_se_pudo_' + que } };
}

// ── La regla de permisos del bot, UNA sola vez (10-oct-2026, acción `verificar` del bot) ─────────────────────────────────────────
// La misma regla vive también en SQL: public.bot_humano_verificar (la edge bot-api la usa cuando el bot pide comprobar a una persona). Hasta que este proxy
// llame también a esa función son DOS sitios: bot_api.test.js y lawang_bot_proxy.test.js pasa los MISMOS casos por esta y por la SQL. Si cambia una, cambia la otra.
export type FichaBot = { rol?: string | null; activo?: boolean | null; herramientas?: string[] | null; ambito?: string | null; empresas?: string[] | null };
/** Alcance acotado a una empresa (rol de empresa o personas con empresas marcadas): el bot es uno y mezcla las dos, no se usa desde ahí. */
export const acotadoAEmpresa = (f: FichaBot) => f.ambito === 'empresa' || (f.empresas ?? []).length > 0;
/** ¿Tiene esta casilla? super_admin las tiene todas. */
export const tieneCasilla = (f: FichaBot, casilla: string) => f.rol === 'super_admin' || (f.herramientas ?? []).includes(casilla);
/** La regla completa: ficha activa, sin alcance acotado y con la casilla. */
export const reglaBot = (f: FichaBot | null | undefined, casilla: string) => !!f && !!f.activo && !acotadoAEmpresa(f) && tieneCasilla(f, casilla);

export const manejador = async (req: Request) => {
  const cors = corsFor(req);
  const json = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { ...cors, 'content-type': 'application/json' } });
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'metodo' }, 405);

  try {
    // ── quién llama ──────────────────────────────────────────────────────
    const jwt = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '');
    if (!jwt) return json({ error: 'sin_sesion' }, 401);
    const { data: quien, error: eUser } = await admin.auth.getUser(jwt);
    if (eUser || !quien?.user) return json({ error: 'sesion_invalida' }, 401);

    const { data: ficha, error: eFicha } = await admin
      .from('usuarios').select('rol, activo, herramientas, email, ambito, empresas').eq('user_id', quien.user.id).maybeSingle();
    if (eFicha) return json({ error: 'no_se_pudo_comprobar_permiso' }, 500);
    if (!ficha || !ficha.activo) return json({ error: 'no_autorizado' }, 403);
    // 8-oct-2026 (Fase 2, «Lawang con dos empresas»): el bot de WhatsApp es UNO y mezcla las conversaciones y las citas de
    // las dos empresas, y su API no sabe de empresas. Quien tiene el alcance acotado (un rol de empresa, o una persona con
    // empresas marcadas) NO pasa por aquí: dejarlo pasar le enseñaría las conversaciones de la otra empresa con solo tener
    // la casilla «leads». Nace cerrado hasta que el bot filtre por empresa (LAW-E13, departamento Bots). Hoy nadie está acotado.
    if (acotadoAEmpresa(ficha))
      return json({ error: 'sin_permiso: el bot de WhatsApp atiende a las dos empresas; esta pantalla no está disponible con el alcance acotado a una empresa' }, 403);
    const puedeLeads = reglaBot(ficha, 'leads');
    // Permiso propio para escribir al lead. Se reparte desde /intranet/usuarios/ como
    // una casilla mas; mientras nadie la marque, solo los super_admin pueden escribir.
    const puedeEscribir = reglaBot(ficha, 'bot_escribir');
    // Configurar el bot (instrucciones extra, saludo, horas de pausa) cambia lo que el bot dice a clientes
    // reales, así que es un permiso APARTE, y también para LEER la configuración (puede traer datos comerciales).
    // Llamador: la pestaña «Configurar bot» de intranet/leads. Hasta que se reparta como casilla, solo super_admin.
    const puedeConfigurar = reglaBot(ficha, 'bot_configurar');

    const body = await req.json().catch(() => ({}));
    const accion = String(body.accion ?? '');

    // ── Setter IA: requiere 'leads' ──────────────────────────────────────
    if (accion === 'conversaciones') {
      if (!puedeLeads) return json({ error: 'sin_permiso: leads' }, 403);
      const r = await llamaBot('/admin/api/leads');
      return json(r.body, r.status);
    }
    if (accion === 'conversacion') {
      if (!puedeLeads) return json({ error: 'sin_permiso: leads' }, 403);
      const phone = String(body.phone ?? '').replace(/[^0-9]/g, '');
      if (!phone) return json({ error: 'phone_requerido' }, 400);
      const r = await llamaBot('/admin/api/conv/' + encodeURIComponent(phone));
      return json(r.body, r.status);
    }
    if (accion === 'pausar') {
      if (!puedeLeads) return json({ error: 'sin_permiso: leads' }, 403);
      const phone = String(body.phone ?? '').replace(/[^0-9]/g, '');
      if (!phone) return json({ error: 'phone_requerido' }, 400);
      if (humanoEnPostgres()) {
        const h = await llamaHumano(jwt, { accion: 'pausar', tel: phone, modo: body.paused ? 'pausar' : 'quitar' });
        if (h.status === 200 && h.body.ok === true) return json({ ok: true, paused: !!h.body.pausado });
        const f = falloHumano(h);
        return json(f.body, f.status);
      }
      const r = await llamaBot('/admin/api/pause', {
        method: 'POST', body: JSON.stringify({ phone, paused: !!body.paused }),
      }, jwt);
      return json(r.body, r.status);
    }

    /* ── ESCRIBIR AL LEAD: requiere 'bot_escribir' ───────────────────────
       Permiso PROPIO, no 'leads'. Leer conversaciones y hablar por WhatsApp en nombre
       de PT TEPI SUN GAI no son el mismo nivel de acceso, y quien tenga el CRM abierto
       no debería poder emitir mensajes a clientes por el hecho de tenerlo abierto.

       ⚠️ Esto revierte a medias la nota de la cabecera ("el bot tiene más endpoints
       admin de los que esta pestaña necesita — envío de plantillas…"). Se revierte con
       condiciones, no con un passthrough: dos acciones nombradas, permiso aparte, y el
       bot exige además que el teléfono sea un lead ya conocido. Nunca se acepta un
       `path` libre.

       LA AUTORÍA LA PONE ESTE SERVIDOR, NUNCA EL NAVEGADOR. Mismo patrón que
       `closerFinal` más abajo: si `byUser` viajara en el cuerpo, el registro de quién
       habló en nombre de la empresa sería falsificable justo por quien más motivos
       tendría para falsificarlo. */
    if (accion === 'enviar') {
      if (!puedeEscribir) return json({ error: 'sin_permiso: bot_escribir' }, 403);
      const phone = String(body.phone ?? '').replace(/[^0-9]/g, '');
      const text = String(body.text ?? '').trim();
      if (!phone || !text) return json({ error: 'phone_y_text_requeridos' }, 400);
      if (text.length > 4000) return json({ error: 'texto_demasiado_largo' }, 400);
      let r = await llamaBot('/admin/api/send', {
        method: 'POST', body: JSON.stringify({ phone, text, byUser: ficha.email }),
      }, jwt);
      if (humanoEnPostgres()) r = await registraEnvio(jwt, phone, r);
      return json(r.body, r.status);
    }
    // ── Configurar el bot: requiere 'bot_configurar' (lectura incluida) ──────────────────────────
    // La autoría (`byUser`) la pone ESTE servidor desde la sesión, nunca el navegador. Se copian solo las tres
    // claves conocidas: el bot las valida otra vez y rechaza cualquier otra.
    const enPostgres = (Deno.env.get('BOT_CONFIG_STORE') ?? '').trim().toLowerCase() === 'postgres';
    if (accion === 'config_get') {
      if (!puedeConfigurar) return json({ error: 'sin_permiso: bot_configurar' }, 403);
      if (enPostgres) {
        const { data, error } = await admin.rpc('crm_bot_config_leer', { p_user: quien.user.id });
        if (error) { const f = falloRpc(error, 'leer'); return json(f.body, f.status); }
        return json(data);
      }
      const r = await llamaBot('/admin/api/config');
      return json(r.body, r.status);
    }
    if (accion === 'config_set') {
      if (!puedeConfigurar) return json({ error: 'sin_permiso: bot_configurar' }, 403);
      if (enPostgres) {
        const claves = Object.keys((body.config ?? {}) as Record<string, unknown>);
        // Faltando una clave se guardaría vacía (se borraría en silencio): se exigen las tres, como con el bot.
        if (CLAVES_CFG.some((k) => !claves.includes(k))) return json({ error: 'config_incompleta' }, 400);
        const v = validaConfig(body.config);
        if (!v.ok) return json({ error: v.error }, 400);
        if (typeof body.expectedUpdatedAt !== 'number' || !Number.isFinite(body.expectedUpdatedAt))
          return json({ error: 'expectedUpdatedAt requerido (la versión que estabas viendo)' }, 400);
        const { data, error } = await admin.rpc('crm_bot_config_guardar', {
          p_user: quien.user.id, p_extra: v.value.extra, p_bienvenida: v.value.bienvenida, p_pausa_horas: v.value.pausaHoras,
          p_esperada: Math.trunc(body.expectedUpdatedAt), p_por: ficha.email ?? '',
        });
        if (error) { const f = falloRpc(error, 'guardar'); return json(f.body, f.status); }
        if (data?.conflicto) return json({ error: 'otra persona ha cambiado la configuración mientras la editabas', config: data.config }, 409);
        return json(data);
      }
      const c = (body.config ?? {}) as Record<string, unknown>;
      const claves = Object.keys(c);
      if (claves.some((k) => !['extra', 'bienvenida', 'pausaHoras'].includes(k))) return json({ error: 'clave_desconocida' }, 400);
      // Faltando una clave el bot la guardaría vacía (la borraría en silencio): se exigen las tres.
      if (['extra', 'bienvenida', 'pausaHoras'].some((k) => !claves.includes(k))) return json({ error: 'config_incompleta' }, 400);
      const config = {
        extra: typeof c.extra === 'string' ? c.extra : '',
        bienvenida: typeof c.bienvenida === 'string' ? c.bienvenida : '',
        pausaHoras: typeof c.pausaHoras === 'number' ? c.pausaHoras : 0,
      };
      if (config.extra.length > 2000 || config.bienvenida.length > 500) return json({ error: 'texto_demasiado_largo' }, 400);
      const expectedUpdatedAt = typeof body.expectedUpdatedAt === 'number' ? body.expectedUpdatedAt : undefined;
      const r = await llamaBot('/admin/api/config', {
        method: 'POST', body: JSON.stringify({ config, byUser: ficha.email, expectedUpdatedAt }),
      });
      return json(r.body, r.status);
    }
    if (accion === 'config_revert') {
      if (!puedeConfigurar) return json({ error: 'sin_permiso: bot_configurar' }, 403);
      if (enPostgres) {
        if (typeof body.expectedUpdatedAt !== 'number' || !Number.isFinite(body.expectedUpdatedAt))
          return json({ error: 'expectedUpdatedAt requerido (la versión que estabas viendo)' }, 400);
        const { data, error } = await admin.rpc('crm_bot_config_volver', {
          p_user: quien.user.id, p_esperada: Math.trunc(body.expectedUpdatedAt), p_por: ficha.email ?? '',
        });
        if (error) { const f = falloRpc(error, 'volver'); return json(f.body, f.status); }
        if (data?.conflicto) return json({ error: 'otra persona ha cambiado la configuración mientras la mirabas' }, 409);
        if (data?.sin_anterior) return json({ error: 'no hay un cambio anterior al que volver' }, 404);
        return json(data);
      }
      const expectedUpdatedAt = typeof body.expectedUpdatedAt === 'number' ? body.expectedUpdatedAt : undefined;
      const r = await llamaBot('/admin/api/config/revert', {
        method: 'POST', body: JSON.stringify({ byUser: ficha.email, expectedUpdatedAt }),
      });
      return json(r.body, r.status);
    }
    if (accion === 'plantillas') {
      if (!puedeEscribir) return json({ error: 'sin_permiso: bot_escribir' }, 403);
      const r = await llamaBot('/admin/api/templates');
      return json(r.body, r.status);
    }
    if (accion === 'enviar_plantilla') {
      if (!puedeEscribir) return json({ error: 'sin_permiso: bot_escribir' }, 403);
      const phone = String(body.phone ?? '').replace(/[^0-9]/g, '');
      const template = String(body.template ?? '').trim();
      if (!phone || !template) return json({ error: 'phone_y_template_requeridos' }, 400);
      // Tope de parámetros y de longitud: una plantilla con diez variables gigantes es
      // una forma de meter un mensaje arbitrario dentro de algo que Meta ya aprobó.
      const params = Array.isArray(body.params)
        ? body.params.slice(0, 10).map((p: unknown) => String(p ?? '').slice(0, 300))
        : [];
      const lang = /^[a-z]{2}(_[A-Z]{2})?$/.test(String(body.lang ?? '')) ? String(body.lang) : 'es';
      let r = await llamaBot('/admin/api/send-template', {
        method: 'POST', body: JSON.stringify({ phone, template, lang, params, byUser: ficha.email }),
      }, jwt);
      if (humanoEnPostgres()) r = await registraEnvio(jwt, phone, r);
      return json(r.body, r.status);
    }

    // ── Agenda de cierre: YA NO PASA POR AQUÍ (9-oct-2026, S5 del encargo del bot) ──
    // Las citas viven en Postgres y la pestaña Agenda habla con crm_citas_agenda / crm_cita_guardar / crm_cita_cancelar
    // (permiso `closers` comprobado en la base). citas_listar / citas_guardar / citas_borrar se retiraron: sin llamador
    // no se deja la puerta (seguridad_2026 §1.ter).

    // Cualquier otra acción se deniega — nunca un passthrough de `path` libre.
    return json({ error: 'accion_desconocida' }, 400);
  } catch (e) {
    console.error('lawang-bot-proxy: error no previsto: ' + String((e as Error)?.message ?? e));
    return json({ error: 'error_interno' }, 500);
  }
};
Deno.serve(manejador);
