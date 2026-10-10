// bot-api — la puerta del bot de WhatsApp de Lawang a su catálogo y a su CRM (S4 del encargo
// encargos/20261008_lawang_bot_catalogo_crm.md, 9-oct-2026). Revisión previa #234 (Seguridad, Datos, Desarrollo).
//
// UNA edge, DOS rutas (reducir la exposición, seguridad_2026.md §1.ter):
//   POST …/bot-api/catalogo   {}                                  → bot_catalogo_leer()      (secreto BOT_API_SECRET_CATALOGO)
//   POST …/bot-api/crm        {accion, tel, msg_id, …}            → bot_lead_upsert / _nota / _cita (secreto BOT_API_SECRET_CRM)
// Cada ruta tiene SU secreto (cabecera X-Bot-Secret): el del catálogo no abre el CRM y al revés.
//
// QUIÉN LLAMA: el servicio `lawang-bot` (Railway), servidor a servidor. Por eso no hay CORS (un navegador no es llamador),
// ni JWT del gateway (`verify_jwt = false` en config.toml: la puerta es el secreto) y solo se acepta POST.
//
// SIN SECRETOS CONFIGURADOS RESPONDE 401 A TODO. Es el estado en que se despliega: un secreto vacío NUNCA autentica
// (`igual('', '')` daría true y dejaría pasar una petición sin cabecera). La comprobación va ANTES de leer el cuerpo
// y de abrir la conexión a la base. Ruta desconocida, método distinto de POST y secreto malo dan el MISMO 401: nada
// que enseñar a quien no tiene secreto.
//
// CÓMO LLEGA A LA BASE. Conexión directa como el rol `bot_lawang` (usuario `bot_lawang.<ref>` del pooler), con la URL en el
// secreto de la edge BOT_DB_URL — NO con service_role: S3 le revocó el EXECUTE a service_role, y un SET ROLE desde la URL del
// superusuario sería un rol autoimpuesto. Se exige que el usuario de la URL sea `bot_lawang`: una URL mal puesta (la de
// postgres) NO se usa. El rol solo ejecuta las 4 funciones de S3; no toca ninguna tabla. Cada función es SECURITY DEFINER,
// comprueba el permiso en código, normaliza el teléfono, bloquea por teléfono (advisory lock) y es idempotente por id de mensaje.
// Las sentencias de abajo son LA lista cerrada: no hay SQL construido, solo parámetros.
//
// EL TELÉFONO. `tel` es la ÚNICA entrada con forma de teléfono y lo manda el bot desde el webhook de Meta (nunca una etiqueta
// del modelo). Ninguna acción lee, lista ni devuelve otro teléfono ni un lead: la respuesta es una palabra fija (`resultado`).
// El cuerpo se valida con esquema cerrado (claves desconocidas = 400): no existe forma de pedir "el lead de otro teléfono".
//
// RESULTADOS. 'tope', 'ambiguo', 'sin_lead'… son respuestas normales (200 + `resultado`), no errores: el bot los trata sin
// romper la conversación. Un texto que la base devuelva y no esté en la lista de abajo, o cualquier fallo de la base, es un
// 502/503 genérico sin detalle.
//
// LÍMITE DE RITMO. En memoria del isolate (ventana fija por ruta): frena un bucle de un bot desbocado, NO es la barrera
// contra un atacante (cada isolate cuenta aparte). La barrera real son los topes por lead y por hora de las funciones de S3.
//
// SIN consola: ni teléfonos, ni textos, ni la URL de la base pasan por los logs de Edge (los lee todo el dashboard 7 días).
// Los fallos se resumen en un código (`db_conexion`, `db_error`) sin mensaje.
//
// ── S2 del encargo encargos/20261009_lawang_bot_sin_redis.md (9-oct-2026): TRES RUTAS NUEVAS ─────────────────────────────────
//   /estado        (secreto BOT_API_SECRET_ESTADO)        el turno del bot: recibir, estado, cerrar, eco, pausa, baja, escalar, resumen
//   /recordatorio  (secreto BOT_API_SECRET_RECORDATORIO)  el reloj de las citas: reclamar las de la proxima hora y anotar el resultado
//   /humano        (secreto BOT_API_SECRET_HUMANO)        lo que hace una PERSONA desde la intranet (pausar, registrar un envio)
// Cada secreto abre SOLO su ruta. Cada accion es una fila de LISTA_CERRADA: claves permitidas, validacion, UNA sentencia SQL, forma
// fija de la salida y codigos de negocio permitidos; lo que la base devuelva fuera de esa forma es un 502 sin detalle.
//   · Contrato de respuesta: 200 {ok:true, accion, ...} | 200 {ok:false, accion, error:'<codigo de negocio>'} (sin_chat, tope…) |
//     4xx (peticion mal formada) | 429 (ritmo; el bot lo trata como `tope`, NUNCA como 5xx a Meta) | 5xx (la base o Auth, sin detalle).
//   · Contenido que viene de Meta (texto, nombre de perfil) se RECORTA, no se rechaza: un 400 ahi acabaria en un 5xx del bot a Meta y
//     Meta reentrega durante 7 dias. La FORMA que construye el bot (claves, media {tipo,id}, <=10 salidas) es esquema cerrado.
//   · /humano: el usuario NO viaja en el cuerpo (un `usuario` en el cuerpo es 400). Sale del JWT de la persona, que el proxy reenvia
//     en `Authorization: Bearer <jwt>`; la edge lo VERIFICA contra Auth (GET /auth/v1/user) y pasa a la base el id (uuid) verificado (el email solo si Auth no lo diera).
//     Un JWT valido NO implica permiso: el permiso 'leads'/'bot_escribir' lo comprueba el proxy antes de llamar.
//   · Las dos unicas respuestas con un telefono que no es el de la peticion: escalacion_tomar (el dueño responde y hay que saber a QUIEN)
//     y citas_recordar (el reloj necesita saber a quien escribir). Ambas declaradas en el plan (excepciones 1 y 2).
//
// ── S5-puente (LAW-507, 9-oct-2026): /importar — TEMPORAL ────────────────────────────────────────────────────
//   /importar      (secreto BOT_API_SECRET_IMPORTAR)      la importacion UNICA de lo que hay en Redis a Postgres (fase B de S5)
// Acciones: chat (un telefono: estado + <=100 mensajes + <=20 escalaciones abiertas), config (una vez), cuadre (lectura de un telefono: conteos y md5).
// Esquema cerrado A FONDO (la edge reconstruye el objeto y solo pasa a la base lo que reconoce). Su secreto no abre ninguna otra ruta ni al
// reves. Se RETIRA en S9 junto con el secreto y las funciones bot_importar_* (ver ACTIVACION.txt).
//
// Desplegar con --no-verify-jwt (y `verify_jwt = false` en supabase/config.toml). Activación: ACTIVACION.txt.

const env = (k: string) => (Deno.env.get(k) ?? '').trim();

// Ajustes mutables SOLO para las pruebas (nada los toca desde fuera de la edge).
export const AJUSTES = {
  ventanaMs: 60_000,
  topeCatalogo: 30,       // el bot pide el catálogo una vez por mensaje de venta, no más
  topeCrm: 90,
  maxCuerpo: 4096,        // bytes; una nota son ≤500 caracteres
  dbTimeoutMs: 8_000,     // menor que el timeout por llamada del bot (S4b): la edge contesta antes de que el bot se rinda
  authTimeoutMs: 5_000,
  topeEstado: 600,        // por minuto e isolate: 3-4 llamadas por mensaje, varios chats a la vez
  topeRecordatorio: 30,   // el reloj corre cada 5 min
  topeHumano: 120,
  topeVerificar: 60,      // `verificar` (estado): una llamada por envio humano; por minuto e isolate
  topeTelEstado: 60,      // por minuto y telefono (~20 mensajes/min). Pasado esto: 429, que el bot trata como `tope`
  topeTelHumano: 20,
  maxCuerpoEstado: 262_144,   // 10 salidas de 4096 caracteres en UTF-8 son ~160 KB
  maxCuerpoRecordatorio: 1024,
  maxCuerpoHumano: 32_768,
  topeImportar: 600,      // un telefono por llamada: la importacion son unos cientos de llamadas seguidas
  maxCuerpoImportar: 2_097_152,   // 100 mensajes de 4096 caracteres (hasta 4 bytes en UTF-8 + escapes) caben en ~1,7 MB
  maxTelefonos: 5_000,    // tamaño del mapa de ritmo por telefono
};

// Las 8 columnas que puede ver el bot (espejo de `bot_catalogo_leer()`). Lo que la función devolviera de más NO sale de aquí.
const CLAVES_CATALOGO = ['proyecto', 'tipo', 'codigo', 'superficie_m2', 'precio', 'moneda', 'modelo', 'disponible'] as const;

// Lo que cada función puede contestar (de las migraciones 20261010080000/80100/80200). Cualquier otro texto = error del servidor.
const RESULTADOS: Record<string, readonly string[]> = {
  lead_upsert: ['creado', 'existente', 'ambiguo', 'tope', 'telefono_invalido'],
  lead_nota: ['ok', 'vacio', 'sin_lead', 'ambiguo', 'tope', 'telefono_invalido'],
  lead_cita: ['propuesta', 'reprogramada', 'ya_hay_cita', 'sin_lead', 'ambiguo', 'tope', 'telefono_invalido',
    'tipo_invalido', 'fecha_invalida', 'pasada', 'lejana', 'fuera_horario'],
};
export const ACCIONES = Object.keys(RESULTADOS);

// Esquema cerrado por acción: claves permitidas (todas las demás → 400).
const CLAVES_ACCION: Record<string, readonly string[]> = {
  lead_upsert: ['accion', 'tel', 'msg_id', 'nombre', 'origen'],
  lead_nota: ['accion', 'tel', 'msg_id', 'texto'],
  lead_cita: ['accion', 'tel', 'msg_id', 'cuando', 'tipo'],
};
const ORIGENES = ['bot-whatsapp-lawang', 'bot-whatsapp-sumbahills'];
const RE_TEL = /^\+?[0-9]{8,15}$/;
const RE_MSG = /^[A-Za-z0-9._:=@+\/-]{1,120}$/;   // wamid.HBgM… (base64 urlsafe y puntos)

const json = (o: unknown, s = 200, extra: Record<string, string> = {}) =>
  new Response(JSON.stringify(o), { status: s, headers: { 'content-type': 'application/json', 'cache-control': 'no-store', ...extra } });
const NO_AUTORIZADO = () => json({ error: 'no_autorizado' }, 401);

// comparación en tiempo constante
function igual(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a), y = new TextEncoder().encode(b);
  let d = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) d |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return d === 0;
}

/** El secreto esperado de la ruta ('' si no hay ruta válida o no está configurado). */
function secretoDe(ruta: string): string {
  if (ruta === 'catalogo') return env('BOT_API_SECRET_CATALOGO');
  if (ruta === 'crm') return env('BOT_API_SECRET_CRM');
  if (ruta === 'estado') return env('BOT_API_SECRET_ESTADO');
  if (ruta === 'recordatorio') return env('BOT_API_SECRET_RECORDATORIO');
  if (ruta === 'humano') return env('BOT_API_SECRET_HUMANO');
  if (ruta === 'importar') return env('BOT_API_SECRET_IMPORTAR');
  return '';
}

/** La ruta es el último segmento: …/functions/v1/bot-api/<ruta>. */
function rutaDe(req: Request): string {
  const seg = new URL(req.url).pathname.split('/').filter(Boolean);
  const i = seg.lastIndexOf('bot-api');
  return i >= 0 && seg.length === i + 2 ? seg[i + 1] : '';
}

// ── límite de ritmo (por isolate) ───────────────────────────────────────────────────────────
const ventana: Record<string, { desde: number; n: number }> = {};
function demasiado(ruta: string, tope: number): number {
  const ahora = Date.now();
  const v = ventana[ruta];
  if (!v || ahora - v.desde >= AJUSTES.ventanaMs) { ventana[ruta] = { desde: ahora, n: 1 }; return 0; }
  v.n += 1;
  return v.n > tope ? Math.max(1, Math.ceil((v.desde + AJUSTES.ventanaMs - ahora) / 1000)) : 0;
}
export function reiniciaRitmo() { for (const k of Object.keys(ventana)) delete ventana[k]; }

// ── la base ─────────────────────────────────────────────────────────────────────────────────
// Lista cerrada de sentencias. Los parámetros van con casts: el pooler en modo transacción no admite sentencias preparadas.
// JSONB: NUNCA `$N::jsonb` a pelo. postgres.js serializa un parámetro tipado jsonb con JSON.stringify, y la edge ya manda el JSON
// hecho texto: llegaba un jsonb ESCALAR de tipo string (doble codificado) y las funciones contestaban 'forma' (LAW-507, 9-oct-2026).
// Se recibe como texto y se convierte en SQL: `$N::text::jsonb`. Lo fija bot_api.test.js con un doble que serializa como postgres.js.
const SQL = {
  catalogo: 'select proyecto, tipo, codigo, superficie_m2, precio, moneda, modelo, disponible from public.bot_catalogo_leer()',
  lead_upsert: 'select public.bot_lead_upsert($1::text, $2::text, $3::text, $4::text) as r',
  lead_nota: 'select public.bot_lead_nota($1::text, $2::text, $3::text) as r',
  lead_cita: 'select public.bot_lead_cita($1::text, $2::text, $3::text, $4::text) as r',
  // ── S2 ──
  mensaje_recibir: 'select public.bot_mensaje_recibir($1::text, $2::text, $3::text, $4::text::jsonb) as r',
  turno_estado: 'select public.bot_turno_estado($1::text, $2::boolean) as r',
  turno_cerrar: 'select public.bot_turno_cerrar($1::text, $2::text, $3::text::jsonb, $4::text, $5::text, $6::boolean, $7::boolean) as r',
  eco_operadora: 'select public.bot_eco_operadora($1::text, $2::text, $3::text, $4::int) as r',
  pausar: 'select public.bot_pausar($1::text, $2::text, $3::int) as r',
  baja: 'select public.bot_baja($1::text, $2::text) as r',
  entrega_fallida: 'select public.bot_entrega_fallida($1::text, $2::text, $3::text) as r',
  escalar: 'select public.bot_escalar($1::text, $2::text, $3::text, $4::text) as r',
  escalacion_tomar: 'select public.bot_escalacion_tomar($1::text) as r',
  lead_resumen: 'select public.bot_lead_resumen($1::text, $2::text, $3::bigint) as r',
  citas_recordar: 'select accion_id, tel, tipo, cuando_ts, ultimo_entrante_en, nombre from public.bot_citas_recordar()',
  cita_recordatorio_res: 'select public.bot_cita_recordatorio_res($1::uuid, $2::text) as r',
  pausar_humano: 'select public.bot_pausar_humano($1::text, $2::text, $3::text) as r',
  envio_humano: 'select public.bot_envio_humano($1::text, $2::text, $3::text, $4::text::jsonb, $5::text) as r',
  // ── verificar (11-oct-2026): ¿esta persona (JWT verificado) tiene la casilla? $1 = el usuario de Auth, $2 = el permiso ──
  verificar_humano: 'select public.bot_humano_verificar($1::text, $2::text) as r',
  // ── S12: consentimiento de seguimiento y reenganche ──
  consentimiento_preguntar: 'select public.bot_consentimiento_preguntar($1::text, $2::text, $3::text, $4::text, $5::boolean) as r',
  consentimiento_enviada: 'select public.bot_consentimiento_enviada($1::text, $2::text, $3::boolean) as r',
  consentimiento_responder: 'select public.bot_consentimiento_responder($1::text, $2::text, $3::text, $4::text) as r',
  seguimiento_candidatos: 'select tel, plantilla, idioma, nombre from public.bot_seguimiento_candidatos()',
  seguimiento_reservar: 'select public.bot_seguimiento_reservar($1::text, $2::text) as r',
  seguimiento_registrar: 'select public.bot_seguimiento_registrar($1::text, $2::text, $3::text, $4::text, $5::text) as r',
  // ── S5-puente (temporal) ──
  importar_chat: 'select public.bot_importar_chat($1::text::jsonb) as r',
  importar_config: 'select public.bot_importar_config($1::text::jsonb) as r',
  importar_cuadre: 'select public.bot_importar_cuadre($1::text) as r',
} as const;
type Clave = keyof typeof SQL;
export { SQL };

class ErrorBase extends Error {
  codigo: 'db_conexion' | 'db_error' | 'auth_conexion';
  constructor(codigo: 'db_conexion' | 'db_error' | 'auth_conexion') { super(codigo); this.codigo = codigo; }
}

// La puerta a la base. Las pruebas la sustituyen por un doble (DB.ejecuta); en producción abre UNA conexión por isolate.
// deno-lint-ignore no-explicit-any
let conexion: any = null;
export const DB = {
  async ejecuta(clave: Clave, args: (string | null)[]): Promise<Record<string, unknown>[]> {
    const url = env('BOT_DB_URL');
    let usuario = '';
    try { usuario = decodeURIComponent(new URL(url).username); } catch { /* url vacía o rota: se trata abajo */ }
    // Defensa en profundidad: la edge solo se conecta como el rol del bot. Una URL del superusuario no se usa.
    if (!/^bot_lawang(\.[a-z0-9]+)?$/.test(usuario)) throw new ErrorBase('db_conexion');
    try {
      if (!conexion) {
        const postgres = (await import('npm:postgres@3.4.5')).default;
        conexion = postgres(url, { ssl: 'require', prepare: false, max: 1, connect_timeout: 8, idle_timeout: 20, onnotice: () => {} });
      }
      const consulta = conexion.unsafe(SQL[clave], args as never[]);
      let reloj: ReturnType<typeof setTimeout> | undefined;
      const tope = new Promise((_, no) => { reloj = setTimeout(() => no(new Error('timeout')), AJUSTES.dbTimeoutMs); });
      try { return await Promise.race([consulta, tope]) as Record<string, unknown>[]; } finally { clearTimeout(reloj); }
    } catch {
      // MUDO A PROPOSITO: el mensaje del driver puede llevar la URL (con la clave) o un teléfono; se resume en un código y la
      // respuesta ya dice que falló la base. Se tira la conexión para que la siguiente petición abra una limpia.
      try { await conexion?.end({ timeout: 1 }); } catch { /* ya estaba rota */ }
      conexion = null;
      throw new ErrorBase('db_error');
    }
  },
};

// ── rutas ───────────────────────────────────────────────────────────────────────────────────
async function rutaCatalogo(): Promise<Response> {
  const filas = await DB.ejecuta('catalogo', []);
  const unidades = filas.map((f) => {
    const o: Record<string, unknown> = {};
    for (const k of CLAVES_CATALOGO) o[k] = f[k] ?? null;
    if (o.precio !== null) o.precio = Number(o.precio);
    if (o.superficie_m2 !== null) o.superficie_m2 = Number(o.superficie_m2);
    return o;
  });
  // Vacío y caído se ven distinto: aquí 200 con lista vacía ("no hay unidades publicadas"); la base caída es un 503 (ver manejador).
  return json({ ok: true, generado: new Date().toISOString(), unidades });
}

const texto = (v: unknown, max: number): string | null | undefined =>
  v === undefined || v === null ? null : (typeof v === 'string' && v.length <= max ? v : undefined);

async function rutaCrm(req: Request): Promise<Response> {
  const len = Number(req.headers.get('content-length') ?? '0');
  if (len > AJUSTES.maxCuerpo) return json({ error: 'cuerpo_grande' }, 413);
  const crudo = await req.text();
  if (new TextEncoder().encode(crudo).length > AJUSTES.maxCuerpo) return json({ error: 'cuerpo_grande' }, 413);
  let b: unknown;
  try { b = JSON.parse(crudo); } catch { return json({ error: 'cuerpo' }, 400); }
  if (!b || typeof b !== 'object' || Array.isArray(b)) return json({ error: 'cuerpo' }, 400);
  const o = b as Record<string, unknown>;

  const accion = o.accion;
  if (typeof accion !== 'string' || !Object.prototype.hasOwnProperty.call(CLAVES_ACCION, accion)) return json({ error: 'accion' }, 400);
  if (Object.keys(o).some((k) => !CLAVES_ACCION[accion].includes(k))) return json({ error: 'campo_no_permitido' }, 400);

  // El teléfono lo manda el bot desde el webhook: una sola cadena, solo dígitos (y + inicial).
  if (typeof o.tel !== 'string' || !RE_TEL.test(o.tel)) return json({ error: 'tel' }, 400);
  // Sin id de mensaje no hay idempotencia: una reentrega de Meta duplicaría el lead o la nota. Se exige siempre.
  if (typeof o.msg_id !== 'string' || !RE_MSG.test(o.msg_id)) return json({ error: 'msg_id' }, 400);

  let clave: Clave, args: (string | null)[];
  if (accion === 'lead_upsert') {
    const nombre = texto(o.nombre, 200);
    if (nombre === undefined) return json({ error: 'nombre' }, 400);
    const origen = o.origen === undefined ? 'bot-whatsapp-lawang' : o.origen;
    if (typeof origen !== 'string' || !ORIGENES.includes(origen)) return json({ error: 'origen' }, 400);
    clave = 'lead_upsert'; args = [o.tel, nombre, origen, o.msg_id];
  } else if (accion === 'lead_nota') {
    const t = texto(o.texto, 1000);   // la base recorta a 500; aqui solo se frena lo desmesurado
    if (typeof t !== 'string' || !t.trim()) return json({ error: 'texto' }, 400);
    clave = 'lead_nota'; args = [o.tel, t, o.msg_id];
  } else {
    if (o.tipo !== 'llamada' && o.tipo !== 'visita') return json({ error: 'tipo' }, 400);
    if (typeof o.cuando !== 'string' || o.cuando.length > 40) return json({ error: 'cuando' }, 400);
    clave = 'lead_cita'; args = [o.tel, o.cuando, o.tipo, o.msg_id];
  }

  const filas = await DB.ejecuta(clave, args);
  const r = filas.length === 1 ? filas[0].r : undefined;
  if (typeof r !== 'string' || !RESULTADOS[accion].includes(r)) throw new ErrorBase('db_error');
  return json({ ok: true, accion, resultado: r });
}

// ═══ S2 — rutas /estado, /recordatorio y /humano ═════════════════════════════════════════════════════════════
// Quien verifica a la persona de /humano. Las pruebas lo sustituyen; en produccion pregunta a Auth (el gateway no verifica el JWT:
// verify_jwt=false). Devuelve el email (o el id) VERIFICADO, null si el token no vale, y lanza ErrorBase('auth_conexion') si Auth no
// responde: sin usuario no se sigue nunca.
export const AUTH = {
  async usuario(jwt: string): Promise<string | null> {
    const base = env('SUPABASE_URL').replace(/\/+$/, ''), apikey = env('SUPABASE_ANON_KEY');
    if (!base || !apikey) throw new ErrorBase('auth_conexion');
    let r: Response;
    try {
      r = await fetch(base + '/auth/v1/user', { headers: { authorization: 'Bearer ' + jwt, apikey }, signal: AbortSignal.timeout(AJUSTES.authTimeoutMs) });
    } catch { throw new ErrorBase('auth_conexion'); }
    if (r.status === 401 || r.status === 403) return null;
    if (!r.ok) throw new ErrorBase('auth_conexion');
    let u: Record<string, unknown>;
    try { u = await r.json(); } catch { throw new ErrorBase('auth_conexion'); }
    if (!u || u.is_anonymous === true) return null;
    // El id (sub) es estable y no suplantable; el email es mutable y reasignable. Solo si Auth no da id se usa el email.
    const quien = typeof u.id === 'string' && u.id ? u.id : (typeof u.email === 'string' ? u.email.trim() : '');
    return quien && quien.length <= 120 ? quien : null;
  },
};

const RE_UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const RE_TIPO_MEDIA = /^[a-z_]{1,20}$/;
const RE_ID_MEDIA = /^[A-Za-z0-9._:=@+\/-]{1,200}$/;

type Corte = { error: string };                       // 400 con este codigo
type Args = (string | null)[];
const esObj = (v: unknown): v is Record<string, unknown> => !!v && typeof v === 'object' && !Array.isArray(v);
const cerrado = (o: Record<string, unknown>, claves: readonly string[]) => Object.keys(o).every((k) => claves.includes(k));
/** Contenido de fuera (Meta, el modelo): si no es texto es 400; si es largo se RECORTA (nunca un 400 por longitud). */
// Tras cortar se normaliza: un par sustituto partido o un NUL harian que Postgres rechace el jsonb/text (502 -> Meta reentrega 7 dias).
const recorta = (v: unknown, max: number): string | undefined =>
  (typeof v === 'string' ? (v.length > max ? v.slice(0, max) : v).replace(/\u0000/g, '').toWellFormed() : undefined);
const horasOk = (v: unknown): number | null | undefined => (v === undefined || v === null ? null : (Number.isInteger(v) && (v as number) >= 0 && (v as number) <= 720 ? (v as number) : undefined));

type Media = { tipo: string; id: string };
/** media = {tipo,id} y nada mas (ni blobs ni URLs). undefined = forma invalida; null = sin media. */
function media(v: unknown): Media | null | undefined {
  if (v === undefined || v === null) return null;
  if (!esObj(v) || !cerrado(v, ['tipo', 'id'])) return undefined;
  if (typeof v.id !== 'string' || !RE_ID_MEDIA.test(v.id)) return undefined;
  const tipo = v.tipo === undefined ? 'otro' : v.tipo;
  if (typeof tipo !== 'string' || !RE_TIPO_MEDIA.test(tipo)) return undefined;
  return { tipo, id: v.id };
}

// Lectores estrictos de lo que devuelve la base: lo que no tenga la forma exacta es un 502 (nunca se reenvia tal cual).
const mal = (): never => { throw new ErrorBase('db_error'); };
const B = (v: unknown): boolean => (typeof v === 'boolean' ? v : mal());
const N = (v: unknown): number => (typeof v === 'number' && Number.isFinite(v) ? v : (typeof v === 'string' && v.trim() !== '' && Number.isFinite(Number(v)) ? Number(v) : mal()));
const T = (v: unknown): string => (typeof v === 'string' ? v : mal());
const TN = (v: unknown): string | null => (v === null || v === undefined ? null : T(v));
const iso = (v: unknown): string => (v instanceof Date ? v.toISOString() : T(v));
const isoN = (v: unknown): string | null => (v === null || v === undefined ? null : iso(v));
const O = (v: unknown): Record<string, unknown> => (esObj(v) ? v : mal());
const AVISOS = ['interested', 'booking'];
const ESTADOS_CONSENT = ['sin_preguntar', 'preguntado', 'si', 'no', 'revocado', 'usado', 'caducado'];
const VERSION_CONSENT = 'CONSENT-SEGUIMIENTO-2026-10-09-v1';

type Def = {
  claves: readonly string[];
  tel: boolean;                                        // exige `tel` (el de la peticion)
  valida: (o: Record<string, unknown>) => { args: Args } | Corte;
  sql: Clave;
  tipo: 'json' | 'texto' | 'filas';
  errores?: readonly string[];                         // json: codigos de negocio que la base puede devolver como {error}
  resultados?: readonly string[];                      // texto: palabras que la base puede devolver
  forma?: (r: Record<string, unknown>) => Record<string, unknown>;            // json: salida fija
  formaFilas?: (f: Record<string, unknown>[]) => Record<string, unknown>;     // filas: salida fija
  persona?: 'primero' | 'ultimo';                      // exige el JWT de una persona (cabecera Authorization); su usuario VERIFICADO va como primer o último argumento SQL
};
const ERR_TEL = ['telefono_invalido', 'wamid_invalido', 'sin_chat'];

const mensajeDe = (v: unknown): { texto: string; media: Media | null; ts: number | string | null } | Corte => {
  if (!esObj(v) || !cerrado(v, ['rol', 'texto', 'media', 'ts'])) return { error: 'mensaje' };
  if (v.rol !== undefined && v.rol !== 'user') return { error: 'mensaje' };      // la base fija el rol; solo se acepta el entrante
  const texto = v.texto === undefined || v.texto === null ? '' : recorta(v.texto, 4096);
  if (texto === undefined) return { error: 'texto' };
  const m = media(v.media);
  if (m === undefined) return { error: 'media' };
  let ts: number | string | null = null;
  if (v.ts !== undefined && v.ts !== null) {
    if ((typeof v.ts === 'number' && Number.isInteger(v.ts) && v.ts >= 0 && v.ts < 1e14) || (typeof v.ts === 'string' && /^[0-9]{9,13}$/.test(v.ts))) ts = v.ts;
    else return { error: 'ts' };
  }
  return { texto, media: m, ts };
};

// ── /importar: validacion a fondo. undefined = forma invalida (400). Los textos se RECORTAN (como en las otras rutas); los tipos NO se corrigen. ──
const MS_MAX = 1e15;   // la base solo acepta 1-15 digitos
/** instante en ms: entero 0..1e15 o null/ausente */
const msOk = (v: unknown): number | null | undefined => (v === undefined || v === null ? null : (Number.isSafeInteger(v) && (v as number) >= 0 && (v as number) < MS_MAX ? (v as number) : undefined));
const boolOk = (v: unknown): boolean | undefined => (v === undefined || v === null ? false : (typeof v === 'boolean' ? v : undefined));
const enteroOk = (v: unknown, max: number): number | undefined => (v === undefined || v === null ? 0 : (Number.isSafeInteger(v) && (v as number) >= 0 && (v as number) <= max ? (v as number) : undefined));
const textoN = (v: unknown, max: number): string | null | undefined => (v === undefined || v === null ? null : recorta(v, max));
const CLAVES_CHAT = ['nombre_perfil', 'intent', 'ultimo_mensaje', 'ultimo_por', 'creado_ms', 'actualizado_ms', 'archivado', 'ultimo_entrante_ms', 'esperando', 'pausado',
  'pausa_hasta_ms', 'baja_ms', 'baja_acuse', 'seguimientos', 'aviso_nivel', 'aviso_testing'];

function chatDe(v: unknown): Record<string, unknown> | undefined {
  if (!esObj(v) || !cerrado(v, CLAVES_CHAT)) return undefined;
  const o: Record<string, unknown> = {};
  for (const [k, max] of [['nombre_perfil', 200], ['intent', 40], ['ultimo_mensaje', 500], ['ultimo_por', 20]] as const) {
    const t = textoN(v[k], max); if (t === undefined) return undefined; o[k] = t;
  }
  for (const k of ['creado_ms', 'actualizado_ms', 'ultimo_entrante_ms', 'pausa_hasta_ms', 'baja_ms']) {
    const m = msOk(v[k]); if (m === undefined) return undefined; o[k] = m;   // pausa_hasta_ms null con pausado = SIN caducidad: se conserva el null
  }
  for (const k of ['archivado', 'esperando', 'pausado', 'baja_acuse', 'aviso_testing']) {
    const b = boolOk(v[k]); if (b === undefined) return undefined; o[k] = b;
  }
  const seg = enteroOk(v.seguimientos, 1_000_000), av = enteroOk(v.aviso_nivel, 2);
  if (seg === undefined || av === undefined) return undefined;
  o.seguimientos = seg; o.aviso_nivel = av;
  return o;
}
function mensajeImportado(v: unknown): Record<string, unknown> | undefined {
  if (!esObj(v) || !cerrado(v, ['rol', 'por', 'por_usuario', 'contenido', 'media', 'wamid', 'ts_ms'])) return undefined;
  const rol = textoN(v.rol, 20), por = textoN(v.por, 20), pu = textoN(v.por_usuario, 120), cont = v.contenido === undefined || v.contenido === null ? '' : recorta(v.contenido, 4096);
  const md = media(v.media), ts = msOk(v.ts_ms);
  if (rol === undefined || por === undefined || pu === undefined || cont === undefined || md === undefined || ts === undefined) return undefined;
  if (v.wamid !== undefined && v.wamid !== null && (typeof v.wamid !== 'string' || !RE_MSG.test(v.wamid))) return undefined;
  return { rol, por, por_usuario: pu, contenido: cont, media: md, wamid: (v.wamid as string | undefined) ?? null, ts_ms: ts };
}
function escalacionImportada(v: unknown): Record<string, unknown> | undefined {
  if (!esObj(v) || !cerrado(v, ['nombre', 'pregunta', 'aviso_wamid', 'creada_ms'])) return undefined;
  const nombre = textoN(v.nombre, 200), pregunta = v.pregunta === undefined || v.pregunta === null ? '' : recorta(v.pregunta, 2000), ms = msOk(v.creada_ms);
  if (nombre === undefined || pregunta === undefined || ms === undefined) return undefined;
  if (v.aviso_wamid !== undefined && v.aviso_wamid !== null && (typeof v.aviso_wamid !== 'string' || !RE_MSG.test(v.aviso_wamid))) return undefined;
  return { nombre, pregunta, aviso_wamid: (v.aviso_wamid as string | undefined) ?? null, creada_ms: ms };
}
function ajustesDe(v: unknown, conAutor: boolean): Record<string, unknown> | undefined {
  if (!esObj(v) || !cerrado(v, conAutor ? ['extra', 'bienvenida', 'pausa_horas', 'updated_by'] : ['extra', 'bienvenida', 'pausa_horas'])) return undefined;
  const extra = v.extra === undefined || v.extra === null ? '' : recorta(v.extra, 2000), bien = v.bienvenida === undefined || v.bienvenida === null ? '' : recorta(v.bienvenida, 500);
  const by = conAutor ? textoN(v.updated_by, 120) : null;
  if (extra === undefined || bien === undefined || by === undefined || !Number.isInteger(v.pausa_horas) || (v.pausa_horas as number) < 0 || (v.pausa_horas as number) > 720) return undefined;
  const o: Record<string, unknown> = { extra, bienvenida: bien, pausa_horas: v.pausa_horas };
  if (conAutor) o.updated_by = by;
  return o;
}
/** array de <=max elementos validados con `f`; ausente = [] ; undefined = forma invalida */
function listaDe(v: unknown, max: number, f: (x: unknown) => Record<string, unknown> | undefined): Record<string, unknown>[] | undefined {
  if (v === undefined || v === null) return [];
  if (!Array.isArray(v) || v.length > max) return undefined;
  const out: Record<string, unknown>[] = [];
  for (const x of v) { const y = f(x); if (!y) return undefined; out.push(y); }
  return out;
}

export const LISTA_CERRADA: Record<string, Record<string, Def>> = {
  estado: {
    mensaje_recibir: {
      claves: ['accion', 'tel', 'wamid', 'nombre_perfil', 'mensaje'], tel: true, sql: 'mensaje_recibir', tipo: 'json',
      errores: ['telefono_invalido', 'wamid_invalido', 'mensaje_invalido'],
      valida: (o) => {
        if (typeof o.wamid !== 'string' || !RE_MSG.test(o.wamid)) return { error: 'wamid' };
        const nombre = o.nombre_perfil === undefined || o.nombre_perfil === null ? null : recorta(o.nombre_perfil, 200);
        if (nombre === undefined) return { error: 'nombre_perfil' };
        const m = mensajeDe(o.mensaje);
        if ('error' in m) return m;
        return { args: [o.tel as string, o.wamid, nombre, JSON.stringify({ texto: m.texto, media: m.media, ts: m.ts })] };
      },
      forma: (r) => ({ duplicado: B(r.duplicado), procesado: B(r.procesado), reproceso: r.reproceso === true, tope: r.tope === true }),
    },
    turno_estado: {
      claves: ['accion', 'tel', 'testing'], tel: true, sql: 'turno_estado', tipo: 'json', errores: ['telefono_invalido', 'sin_chat'],
      valida: (o) => (o.testing !== undefined && typeof o.testing !== 'boolean' ? { error: 'testing' } : { args: [o.tel as string, o.testing === true ? 'true' : 'false'] }),
      forma: (r) => {
        const c = O(r.config);
        const hist = Array.isArray(r.historial) ? r.historial : mal();
        return {
          baja: B(r.baja), pausado: B(r.pausado), esperando: B(r.esperando), avisar_testing: B(r.avisar_testing), primer_turno: B(r.primer_turno),
          historial: hist.slice(-20).map((h) => {
            const x = O(h), m = x.media === null || x.media === undefined ? null : O(x.media);
            return { rol: T(x.rol), texto: T(x.texto), por: TN(x.por), media: m ? { tipo: T(m.tipo), id: T(m.id) } : null, ts: N(x.ts) };
          }),
          config: { extra: TN(c.extra), bienvenida: TN(c.bienvenida), pausa_horas: N(c.pausa_horas), resumen_cada_n: N(c.resumen_cada_n),
            fallos_alarma: N(c.fallos_alarma), version: N(c.version), actualizado_en: isoN(c.actualizado_en) },
          // S12: opcional a proposito (una base anterior a la migracion no lo devuelve); el bot trata su ausencia como «no preguntar».
          ...(r.consentimiento === undefined || r.consentimiento === null ? {} : (() => {
            const k = O(r.consentimiento), e = T(k.estado);
            if (!ESTADOS_CONSENT.includes(e)) mal();
            return { consentimiento: { estado: e, repreguntado: B(k.repreguntado), puede_preguntar: B(k.puede_preguntar) } };
          })()),
        };
      },
    },
    turno_cerrar: {
      claves: ['accion', 'tel', 'wamid', 'salida', 'intent', 'aviso', 'esperando', 'cambio_tema'], tel: true, sql: 'turno_cerrar', tipo: 'json',
      errores: [...ERR_TEL, 'wamid_desconocido'],
      valida: (o) => {
        if (typeof o.wamid !== 'string' || !RE_MSG.test(o.wamid)) return { error: 'wamid' };
        const salida: { texto: string; media: Media | null; wamid: string | null }[] = [];
        if (o.salida !== undefined && o.salida !== null) {
          if (!Array.isArray(o.salida) || o.salida.length > 10) return { error: 'salida' };
          for (const m of o.salida) {
            if (!esObj(m) || !cerrado(m, ['texto', 'media', 'wamid'])) return { error: 'salida' };
            const texto = m.texto === undefined || m.texto === null ? '' : recorta(m.texto, 4096);
            const md = media(m.media);
            if (texto === undefined || md === undefined) return { error: 'salida' };
            if (m.wamid !== undefined && m.wamid !== null && (typeof m.wamid !== 'string' || !RE_MSG.test(m.wamid))) return { error: 'salida' };
            salida.push({ texto, media: md, wamid: (m.wamid as string | undefined) ?? null });
          }
        }
        const intent = o.intent === undefined || o.intent === null ? null : recorta(o.intent, 40);
        if (intent === undefined) return { error: 'intent' };
        if (o.aviso !== undefined && o.aviso !== null && !AVISOS.includes(o.aviso as string)) return { error: 'aviso' };
        for (const k of ['esperando', 'cambio_tema']) if (o[k] !== undefined && typeof o[k] !== 'boolean') return { error: k };
        return { args: [o.tel as string, o.wamid, JSON.stringify(salida), intent, (o.aviso as string | undefined) ?? null, String(o.esperando === true), String(o.cambio_tema === true)] };
      },
      forma: (r) => {
        const av = r.avisar === null || r.avisar === undefined ? null : T(r.avisar);
        if (av !== null && !AVISOS.includes(av)) mal();
        let res: { hasta_id: number; mensajes: { rol: string; por: string; texto: string }[] } | null = null;
        if (r.resumir !== null && r.resumir !== undefined) {
          const x = O(r.resumir), ms = Array.isArray(x.mensajes) ? x.mensajes : mal();
          res = { hasta_id: N(x.hasta_id), mensajes: ms.slice(0, 60).map((m) => { const y = O(m); return { rol: T(y.rol), por: T(y.por), texto: T(y.texto) }; }) };
        }
        return { avisar: av, resumir: res, repetido: B(r.repetido) };
      },
    },
    eco_operadora: {
      claves: ['accion', 'tel', 'wamid', 'texto', 'horas'], tel: true, sql: 'eco_operadora', tipo: 'json', errores: ['telefono_invalido', 'wamid_invalido'],
      valida: (o) => {
        if (typeof o.wamid !== 'string' || !RE_MSG.test(o.wamid)) return { error: 'wamid' };
        const texto = o.texto === undefined || o.texto === null ? '' : recorta(o.texto, 4096);
        const h = horasOk(o.horas);
        if (texto === undefined) return { error: 'texto' };
        if (h === undefined) return { error: 'horas' };
        return { args: [o.tel as string, o.wamid, texto, h === null ? null : String(h)] };
      },
      forma: (r) => ({ duplicado: B(r.duplicado), estaba_pausado: r.estaba_pausado === null || r.estaba_pausado === undefined ? null : B(r.estaba_pausado) }),
    },
    pausar: {
      claves: ['accion', 'tel', 'modo', 'horas'], tel: true, sql: 'pausar', tipo: 'json', errores: ['telefono_invalido', 'modo_invalido', 'sin_chat'],
      valida: (o) => {
        if (o.modo !== 'humano' && o.modo !== 'quitar') return { error: 'modo' };
        const h = horasOk(o.horas);
        if (h === undefined) return { error: 'horas' };
        return { args: [o.tel as string, o.modo, h === null ? null : String(h)] };
      },
      forma: (r) => ({ pausado: B(r.pausado), hasta: isoN(r.hasta) }),
    },
    baja: {
      claves: ['accion', 'tel', 'wamid'], tel: true, sql: 'baja', tipo: 'json', errores: ['telefono_invalido'],
      valida: (o) => (typeof o.wamid !== 'string' || !RE_MSG.test(o.wamid) ? { error: 'wamid' } : { args: [o.tel as string, o.wamid] }),
      forma: (r) => {
        const b = T(r.baja);
        if (b !== 'nueva' && b !== 'ya_dada') mal();
        return { baja: b, pausado: B(r.pausado) };
      },
    },
    entrega_fallida: {
      claves: ['accion', 'tel', 'codigo', 'detalle'], tel: true, sql: 'entrega_fallida', tipo: 'texto', resultados: ['ok', 'sin_chat', 'telefono_invalido'],
      valida: (o) => {
        const codigo = recorta(o.codigo, 20), detalle = o.detalle === undefined || o.detalle === null ? null : recorta(o.detalle, 200);
        if (codigo === undefined || !codigo.trim()) return { error: 'codigo' };
        if (detalle === undefined) return { error: 'detalle' };
        return { args: [o.tel as string, codigo, detalle] };
      },
    },
    escalar: {
      claves: ['accion', 'tel', 'nombre', 'pregunta', 'aviso_wamid'], tel: true, sql: 'escalar', tipo: 'json',
      errores: ['telefono_invalido', 'pregunta_vacia', 'sin_chat', 'tope'],
      valida: (o) => {
        const nombre = o.nombre === undefined || o.nombre === null ? null : recorta(o.nombre, 200);
        const pregunta = recorta(o.pregunta, 2000);
        if (nombre === undefined) return { error: 'nombre' };
        if (pregunta === undefined) return { error: 'pregunta' };
        if (o.aviso_wamid !== undefined && o.aviso_wamid !== null && (typeof o.aviso_wamid !== 'string' || !RE_MSG.test(o.aviso_wamid))) return { error: 'aviso_wamid' };
        return { args: [o.tel as string, nombre, pregunta, (o.aviso_wamid as string | undefined) ?? null] };
      },
      forma: (r) => ({ id: r.id === null || r.id === undefined ? null : N(r.id) }),
    },
    // EXCEPCION 1: sin `tel` de entrada; devuelve el telefono de la escalacion que toma. Solo la llama el webhook cuando el remitente
    // firmado es el dueño (comprobacion del bot, S4b).
    escalacion_tomar: {
      claves: ['accion', 'wamid'], tel: false, sql: 'escalacion_tomar', tipo: 'json', errores: [],
      valida: (o) => (o.wamid !== undefined && o.wamid !== null && (typeof o.wamid !== 'string' || !RE_MSG.test(o.wamid)) ? { error: 'wamid' } : { args: [(o.wamid as string | undefined) ?? null] }),
      forma: (r) => (Object.keys(r).length === 0 ? { encontrada: false } : { encontrada: true, tel: T(r.tel), nombre: TN(r.nombre), pregunta: T(r.pregunta) }),
    },
    // S12 — el estado del consentimiento lo decide la base; aqui NO existe ninguna clave `estado` que el bot (o el modelo) pueda mandar.
    consentimiento_preguntar: {
      claves: ['accion', 'tel', 'version', 'idioma', 'texto', 'repregunta'], tel: true, sql: 'consentimiento_preguntar', tipo: 'json',
      errores: ['telefono_invalido', 'version_desconocida', 'no_procede', 'sin_chat'],
      valida: (o) => {
        if (o.version !== VERSION_CONSENT) return { error: 'version' };
        if (o.idioma !== 'en' && o.idioma !== 'es') return { error: 'idioma' };
        const texto = recorta(o.texto, 1500);
        if (texto === undefined || !texto.trim()) return { error: 'texto' };
        if (o.repregunta !== undefined && typeof o.repregunta !== 'boolean') return { error: 'repregunta' };
        return { args: [o.tel as string, o.version, o.idioma, texto, String(o.repregunta === true)] };
      },
      forma: (r) => ({ ok: r.ok === true ? true : mal() }),
    },
    consentimiento_enviada: {
      claves: ['accion', 'tel', 'wamid', 'repregunta'], tel: true, sql: 'consentimiento_enviada', tipo: 'json',
      errores: ['telefono_invalido', 'wamid_invalido', 'no_procede', 'sin_chat'],
      valida: (o) => {
        if (typeof o.wamid !== 'string' || !RE_MSG.test(o.wamid)) return { error: 'wamid' };
        if (o.repregunta !== undefined && typeof o.repregunta !== 'boolean') return { error: 'repregunta' };
        return { args: [o.tel as string, o.wamid, String(o.repregunta === true)] };
      },
      forma: (r) => ({ ok: r.ok === true ? true : mal() }),
    },
    consentimiento_responder: {
      claves: ['accion', 'tel', 'wamid', 'texto', 'cita'], tel: true, sql: 'consentimiento_responder', tipo: 'json',
      errores: ['telefono_invalido', 'wamid_invalido', 'sin_chat'],
      valida: (o) => {
        if (typeof o.wamid !== 'string' || !RE_MSG.test(o.wamid)) return { error: 'wamid' };
        const texto = o.texto === undefined || o.texto === null ? '' : recorta(o.texto, 4096);
        if (texto === undefined) return { error: 'texto' };
        if (o.cita !== undefined && o.cita !== null && (typeof o.cita !== 'string' || !RE_MSG.test(o.cita))) return { error: 'cita' };
        return { args: [o.tel as string, o.wamid, texto, (o.cita as string | undefined) ?? null] };
      },
      forma: (r) => {
        const res = T(r.resultado), est = T(r.estado);
        if (!['si', 'no', 'repreguntar', 'no_cuenta', 'sin_efecto'].includes(res) || !ESTADOS_CONSENT.includes(est)) mal();
        return { resultado: res, estado: est };
      },
    },
    lead_resumen: {
      claves: ['accion', 'tel', 'texto', 'hasta_id'], tel: true, sql: 'lead_resumen', tipo: 'texto',
      resultados: ['ok', 'ya_hecho', 'tope', 'vacio', 'sin_lead', 'hasta_invalido', 'telefono_invalido'],
      valida: (o) => {
        const texto = recorta(o.texto, 2000);
        if (texto === undefined || !texto.trim()) return { error: 'texto' };
        if (!Number.isSafeInteger(o.hasta_id) || (o.hasta_id as number) <= 0) return { error: 'hasta_id' };
        return { args: [o.tel as string, texto, String(o.hasta_id)] };
      },
    },
    // verificar (11-oct-2026): el bot pregunta si la PERSONA que le pide enviar/pausar tiene la casilla. Es la única acción de /estado con JWT: el usuario sale del JWT
    // verificado contra Auth (nunca del cuerpo: un `usuario` es 400) y el permiso es una lista de UNO. Devuelve si puede y su email, nunca la lista de herramientas.
    verificar: {
      claves: ['accion', 'permiso'], tel: false, persona: 'primero', sql: 'verificar_humano', tipo: 'json', errores: ['permiso_invalido'],
      valida: (o) => (o.permiso === 'bot_escribir' ? { args: [o.permiso] } : { error: 'permiso' }),
      forma: (r) => {
        const email = r.email === null || r.email === undefined ? null : T(r.email);
        const permitido = B(r.permitido);
        if (email !== null && email.length > 320) mal();
        return { permitido, email: permitido ? email : null };
      },
    },
  },
  recordatorio: {
    // EXCEPCION 2: sin parametros (la ventana de 60 min esta fijada en SQL) y devuelve telefonos de OTROS clientes: es el reloj.
    citas_recordar: {
      claves: ['accion'], tel: false, sql: 'citas_recordar', tipo: 'filas', valida: () => ({ args: [] }),
      formaFilas: (filas) => ({
        citas: filas.slice(0, 20).map((f) => {
          const id = T(f.accion_id), tel = T(f.tel), tipo = T(f.tipo);
          if (!RE_UUID.test(id) || !RE_TEL.test(tel) || (tipo !== 'llamada' && tipo !== 'visita')) mal();
          return { accion_id: id, tel, tipo, cuando_ts: iso(f.cuando_ts), ultimo_entrante_en: isoN(f.ultimo_entrante_en), nombre: f.nombre === null || f.nombre === undefined ? null : T(f.nombre).replace(/[ -]/g, ' ').trim().slice(0, 80) || null };
        }),
      }),
    },
    // EXCEPCION 3 (S12): sin parametros, <=20 filas, solo telefonos con consentimiento `si` vigente y un envio de reenganche debido.
    seguimiento_candidatos: {
      claves: ['accion'], tel: false, sql: 'seguimiento_candidatos', tipo: 'filas', valida: () => ({ args: [] }),
      formaFilas: (filas) => ({
        candidatos: filas.slice(0, 20).map((f) => {
          const tel = T(f.tel), pl = T(f.plantilla), idioma = T(f.idioma);
          if (!RE_TEL.test(tel) || (pl !== '48h' && pl !== '7d') || (idioma !== 'en' && idioma !== 'es')) mal();
          return { tel, plantilla: pl, idioma, nombre: f.nombre === null || f.nombre === undefined ? null : T(f.nombre).replace(/[\u0000-\u001f\u007f]/g, ' ').trim().slice(0, 80) || null };
        }),
      }),
    },
    seguimiento_reservar: {
      claves: ['accion', 'tel', 'plantilla'], tel: true, sql: 'seguimiento_reservar', tipo: 'json',
      errores: ['telefono_invalido', 'plantilla_invalida', 'no_procede', 'sin_chat'],
      valida: (o) => (o.plantilla !== '48h' && o.plantilla !== '7d' ? { error: 'plantilla' } : { args: [o.tel as string, o.plantilla] }),
      forma: (r) => ({ idioma: r.idioma === 'es' ? 'es' : 'en', nombre: r.nombre === null || r.nombre === undefined ? null : T(r.nombre).replace(/[\u0000-\u001f\u007f]/g, ' ').trim().slice(0, 80) || null }),
    },
    seguimiento_registrar: {
      claves: ['accion', 'tel', 'plantilla', 'wamid', 'resultado', 'texto'], tel: true, sql: 'seguimiento_registrar', tipo: 'texto',
      resultados: ['ok', 'no_aplica', 'telefono_invalido', 'plantilla_invalida', 'resultado_invalido'],
      valida: (o) => {
        if (o.plantilla !== '48h' && o.plantilla !== '7d') return { error: 'plantilla' };
        if (o.resultado !== 'enviado' && o.resultado !== 'fallo') return { error: 'resultado' };
        if (o.wamid !== undefined && o.wamid !== null && (typeof o.wamid !== 'string' || !RE_MSG.test(o.wamid))) return { error: 'wamid' };
        if (o.resultado === 'enviado' && (typeof o.wamid !== 'string' || !RE_MSG.test(o.wamid))) return { error: 'wamid' };
        const texto = o.texto === undefined || o.texto === null ? null : recorta(o.texto, 200);
        if (texto === undefined) return { error: 'texto' };
        return { args: [o.tel as string, o.plantilla, (o.wamid as string | undefined) ?? null, o.resultado, texto] };
      },
    },
    cita_recordatorio_res: {
      claves: ['accion', 'accion_id', 'resultado'], tel: false, sql: 'cita_recordatorio_res', tipo: 'texto', resultados: ['ok', 'no_aplica', 'resultado_invalido'],
      valida: (o) => {
        if (typeof o.accion_id !== 'string' || !RE_UUID.test(o.accion_id)) return { error: 'accion_id' };
        if (o.resultado !== 'enviado' && o.resultado !== 'sin_ventana' && o.resultado !== 'fallo') return { error: 'resultado' };
        return { args: [o.accion_id, o.resultado] };
      },
    },
  },
  importar: {
    chat: {
      claves: ['accion', 'tel', 'chat', 'mensajes', 'escalaciones'], tel: true, sql: 'importar_chat', tipo: 'json', errores: ['telefono_invalido', 'forma'],
      valida: (o) => {
        const chat = chatDe(o.chat);
        if (!chat) return { error: 'chat' };
        const mensajes = listaDe(o.mensajes, 100, mensajeImportado);
        if (!mensajes) return { error: 'mensajes' };
        const escalaciones = listaDe(o.escalaciones, 20, escalacionImportada);
        if (!escalaciones) return { error: 'escalaciones' };
        return { args: [JSON.stringify({ tel: o.tel, chat, mensajes, escalaciones })] };
      },
      forma: (r) => {
        const m = O(r.mensajes), e = O(r.escalaciones), ch = T(r.chat), ld = T(r.lead);
        if (!['creado', 'actualizado'].includes(ch) || !['enlazado', 'ambiguo', 'sin_lead'].includes(ld)) mal();
        return { chat: ch, lead: ld, mensajes: { recibidos: N(m.recibidos), insertados: N(m.insertados), omitidos_posteriores: B(m.omitidos_posteriores) },
          escalaciones: { recibidas: N(e.recibidas), insertadas: N(e.insertadas) } };
      },
    },
    config: {
      claves: ['accion', 'config', 'log'], tel: false, sql: 'importar_config', tipo: 'json', errores: ['forma', 'pausa_horas'],
      valida: (o) => {
        const config = ajustesDe(o.config, true);
        if (!config) return { error: 'config' };
        const log = listaDe(o.log, 50, (x) => {
          if (!esObj(x) || !cerrado(x, ['ts_ms', 'by', 'prev', 'next'])) return undefined;
          const ts = msOk(x.ts_ms), by = textoN(x.by, 120), prev = ajustesDe(x.prev, false), next = ajustesDe(x.next, false);
          return ts === undefined || by === undefined || !prev || !next ? undefined : { ts_ms: ts, by, prev, next };
        });
        if (!log) return { error: 'log' };
        return { args: [JSON.stringify({ config, log })] };
      },
      forma: (r) => {
        const res = T(r.resultado);
        if (res !== 'importada' && res !== 'ya_configurada') mal();
        return { resultado: res, log_importado: r.log_importado === undefined ? 0 : N(r.log_importado) };
      },
    },
    cuadre: {
      claves: ['accion', 'tel'], tel: true, sql: 'importar_cuadre', tipo: 'json', errores: [],
      valida: (o) => ({ args: [o.tel as string] }),
      forma: (r) => {
        if (!B(r.existe)) return { existe: false };
        const h = T(r.hash_mensajes);
        if (!/^[0-9a-f]{32}$/.test(h)) mal();
        return { existe: true, n_mensajes: N(r.n_mensajes), hash_mensajes: h, ultimo_entrante_ms: r.ultimo_entrante_ms === null || r.ultimo_entrante_ms === undefined ? null : N(r.ultimo_entrante_ms),
          pausado: B(r.pausado), pausa_hasta_ms: r.pausa_hasta_ms === null || r.pausa_hasta_ms === undefined ? null : N(r.pausa_hasta_ms), baja: B(r.baja),
          aviso_nivel: N(r.aviso_nivel), escalaciones_abiertas: N(r.escalaciones_abiertas) };
      },
    },
  },
  humano: {
    // El usuario (ultimo argumento SQL de cada una) lo añade el manejador desde el JWT VERIFICADO; el cuerpo no puede traerlo.
    pausar: {
      claves: ['accion', 'tel', 'modo'], tel: true, persona: 'ultimo', sql: 'pausar_humano', tipo: 'json', errores: ['telefono_invalido', 'sin_usuario', 'modo_invalido', 'sin_chat'],
      valida: (o) => (o.modo !== 'pausar' && o.modo !== 'quitar' ? { error: 'modo' } : { args: [o.tel as string, o.modo] }),
      forma: (r) => ({ pausado: B(r.pausado), hasta: isoN(r.hasta) }),
    },
    enviar: {
      claves: ['accion', 'tel', 'texto', 'wamid', 'media'], tel: true, persona: 'ultimo', sql: 'envio_humano', tipo: 'json', errores: ['telefono_invalido', 'sin_usuario', 'mensaje_vacio', 'sin_chat'],
      valida: (o) => {
        if (typeof o.wamid !== 'string' || !RE_MSG.test(o.wamid)) return { error: 'wamid' };
        const texto = o.texto === undefined || o.texto === null ? '' : recorta(o.texto, 4096);
        const m = media(o.media);
        if (texto === undefined) return { error: 'texto' };
        if (m === undefined) return { error: 'media' };
        if (!texto.trim() && !m) return { error: 'mensaje' };
        return { args: [o.tel as string, texto, o.wamid, m ? JSON.stringify(m) : null] };
      },
      forma: (r) => ({ ok: r.ok === true ? true : mal() }),
    },
  },
};
export const ACCIONES_RUTA: Record<string, string[]> = Object.fromEntries(Object.entries(LISTA_CERRADA).map(([r, a]) => [r, Object.keys(a)]));
const TOPES_RUTA: Record<string, () => number> = {
  estado: () => AJUSTES.topeEstado, recordatorio: () => AJUSTES.topeRecordatorio, humano: () => AJUSTES.topeHumano, importar: () => AJUSTES.topeImportar,
};
const TOPES_TEL: Record<string, () => number> = { estado: () => AJUSTES.topeTelEstado, humano: () => AJUSTES.topeTelHumano };
const MAX_CUERPO: Record<string, () => number> = {
  estado: () => AJUSTES.maxCuerpoEstado, recordatorio: () => AJUSTES.maxCuerpoRecordatorio, humano: () => AJUSTES.maxCuerpoHumano,
  importar: () => AJUSTES.maxCuerpoImportar,
};

// ritmo por telefono (por isolate, mapa acotado: se barren las ventanas caducadas y, si sigue lleno, la mas antigua)
const ventanaTel = new Map<string, { desde: number; n: number }>();
function demasiadoTel(ruta: string, tel: string, tope: number): number {
  const ahora = Date.now(), k = ruta + ':' + tel, v = ventanaTel.get(k);
  if (!v || ahora - v.desde >= AJUSTES.ventanaMs) {
    if (!v && ventanaTel.size >= AJUSTES.maxTelefonos) {
      for (const [kk, vv] of ventanaTel) if (ahora - vv.desde >= AJUSTES.ventanaMs) ventanaTel.delete(kk);
      if (ventanaTel.size >= AJUSTES.maxTelefonos) { const primero = ventanaTel.keys().next().value; if (primero !== undefined) ventanaTel.delete(primero); }
    }
    ventanaTel.set(k, { desde: ahora, n: 1 });
    return 0;
  }
  v.n += 1;
  return v.n > tope ? Math.max(1, Math.ceil((v.desde + AJUSTES.ventanaMs - ahora) / 1000)) : 0;
}
export function reiniciaRitmoTel() { ventanaTel.clear(); }
export const tamanoRitmoTel = () => ventanaTel.size;

async function rutaLista(req: Request, ruta: string): Promise<Response> {
  const defs = LISTA_CERRADA[ruta];
  const max = MAX_CUERPO[ruta]();
  const len = Number(req.headers.get('content-length') ?? '0');
  if (len > max) return json({ error: 'cuerpo_grande' }, 413);
  const crudo = await req.text();
  if (new TextEncoder().encode(crudo).length > max) return json({ error: 'cuerpo_grande' }, 413);
  let b: unknown;
  try { b = JSON.parse(crudo); } catch { return json({ error: 'cuerpo' }, 400); }
  if (!esObj(b)) return json({ error: 'cuerpo' }, 400);

  const accion = b.accion;
  if (typeof accion !== 'string' || !Object.prototype.hasOwnProperty.call(defs, accion)) return json({ error: 'accion' }, 400);
  const def = defs[accion];
  if (!cerrado(b, def.claves)) return json({ error: 'campo_no_permitido' }, 400);
  if (def.tel && (typeof b.tel !== 'string' || !RE_TEL.test(b.tel))) return json({ error: 'tel' }, 400);
  const v = def.valida(b);
  if ('error' in v) return json({ error: v.error }, 400);

  if (def.tel && TOPES_TEL[ruta]) {
    const espera = demasiadoTel(ruta, (b.tel as string).replace(/^\+/, ''), TOPES_TEL[ruta]());
    if (espera) return json({ error: 'demasiadas_peticiones' }, 429, { 'retry-after': String(espera) });
  }

  const args = v.args;
  if (def.persona) {
    // La persona que actua sale del JWT verificado, nunca del cuerpo ni del bot. Va la ULTIMA (humano) o la PRIMERA (verificar) en los argumentos SQL.
    const jwt = (req.headers.get('authorization') ?? '').replace(/^Bearer(\s+|$)/i, '').trim();
    if (!jwt || jwt.length > 4096) return NO_AUTORIZADO();
    if (def.persona === 'primero') {
      // `verificar` lleva su propio tope (una llamada por envio humano): pasado, 429 y NUNCA llega a Auth.
      const espera = demasiado('estado:verificar', AJUSTES.topeVerificar);
      if (espera) return json({ error: 'demasiadas_peticiones' }, 429, { 'retry-after': String(espera) });
    }
    const quien = await AUTH.usuario(jwt);
    if (!quien) return NO_AUTORIZADO();
    if (def.persona === 'primero') args.unshift(quien); else args.push(quien);
  }

  const filas = await DB.ejecuta(def.sql, args);
  if (def.tipo === 'filas') return json({ ok: true, accion, ...def.formaFilas!(filas) });
  let r: unknown = filas.length === 1 ? filas[0].r : undefined;
  if (def.tipo === 'texto') {
    if (typeof r !== 'string' || !def.resultados!.includes(r)) throw new ErrorBase('db_error');
    return json({ ok: true, accion, resultado: r });
  }
  if (typeof r === 'string') { try { r = JSON.parse(r); } catch { /* no es json: abajo falla */ } }
  if (!esObj(r)) throw new ErrorBase('db_error');
  if (r.error !== undefined) {
    if (typeof r.error !== 'string' || !def.errores!.includes(r.error)) throw new ErrorBase('db_error');
    return json({ ok: false, accion, error: r.error });
  }
  return json({ ok: true, accion, ...def.forma!(r) });
}

export async function manejador(req: Request): Promise<Response> {
  const ruta = rutaDe(req);
  const esperado = secretoDe(ruta);
  const dado = (req.headers.get('x-bot-secret') ?? '').trim();
  // Fail-closed: sin secreto configurado, sin cabecera, método que no es POST, ruta desconocida o secreto malo → el mismo 401.
  if (!esperado || !dado || req.method !== 'POST' || !igual(dado, esperado)) return NO_AUTORIZADO();

  const tope = ruta === 'catalogo' ? AJUSTES.topeCatalogo : ruta === 'crm' ? AJUSTES.topeCrm : TOPES_RUTA[ruta]();
  const espera = demasiado(ruta, tope);
  if (espera) return json({ error: 'demasiadas_peticiones' }, 429, { 'retry-after': String(espera) });

  try {
    if (ruta === 'catalogo') return await rutaCatalogo();
    if (ruta === 'crm') return await rutaCrm(req);
    return await rutaLista(req, ruta);
  } catch (e) {
    // La base caída NO se parece a "vacío": 503 para que el bot use el último catálogo bueno o diga que no lo tiene.
    if (e instanceof ErrorBase) return json({ error: e.codigo }, e.codigo === 'db_error' ? 502 : 503);
    return json({ error: 'interno' }, 500);
  }
}

Deno.serve(manejador);
