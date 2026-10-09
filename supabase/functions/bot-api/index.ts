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
//     en `Authorization: Bearer <jwt>`; la edge lo VERIFICA contra Auth (GET /auth/v1/user) y pasa a la base el email (o el id) verificado.
//     Un JWT valido NO implica permiso: el permiso 'leads'/'bot_escribir' lo comprueba el proxy antes de llamar.
//   · Las dos unicas respuestas con un telefono que no es el de la peticion: escalacion_tomar (el dueño responde y hay que saber a QUIEN)
//     y citas_recordar (el reloj necesita saber a quien escribir). Ambas declaradas en el plan (excepciones 1 y 2).
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
  topeTelEstado: 60,      // por minuto y telefono (~20 mensajes/min). Pasado esto: 429, que el bot trata como `tope`
  topeTelHumano: 20,
  maxCuerpoEstado: 262_144,   // 10 salidas de 4096 caracteres en UTF-8 son ~160 KB
  maxCuerpoRecordatorio: 1024,
  maxCuerpoHumano: 32_768,
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
const SQL = {
  catalogo: 'select proyecto, tipo, codigo, superficie_m2, precio, moneda, modelo, disponible from public.bot_catalogo_leer()',
  lead_upsert: 'select public.bot_lead_upsert($1::text, $2::text, $3::text, $4::text) as r',
  lead_nota: 'select public.bot_lead_nota($1::text, $2::text, $3::text) as r',
  lead_cita: 'select public.bot_lead_cita($1::text, $2::text, $3::text, $4::text) as r',
  // ── S2 ──
  mensaje_recibir: 'select public.bot_mensaje_recibir($1::text, $2::text, $3::text, $4::jsonb) as r',
  turno_estado: 'select public.bot_turno_estado($1::text, $2::boolean) as r',
  turno_cerrar: 'select public.bot_turno_cerrar($1::text, $2::text, $3::jsonb, $4::text, $5::text, $6::boolean, $7::boolean) as r',
  eco_operadora: 'select public.bot_eco_operadora($1::text, $2::text, $3::text, $4::int) as r',
  pausar: 'select public.bot_pausar($1::text, $2::text, $3::int) as r',
  baja: 'select public.bot_baja($1::text, $2::text) as r',
  entrega_fallida: 'select public.bot_entrega_fallida($1::text, $2::text, $3::text) as r',
  escalar: 'select public.bot_escalar($1::text, $2::text, $3::text, $4::text) as r',
  escalacion_tomar: 'select public.bot_escalacion_tomar($1::text) as r',
  lead_resumen: 'select public.bot_lead_resumen($1::text, $2::text, $3::bigint) as r',
  citas_recordar: 'select accion_id, tel, tipo, cuando_ts, ultimo_entrante_en from public.bot_citas_recordar()',
  cita_recordatorio_res: 'select public.bot_cita_recordatorio_res($1::uuid, $2::text) as r',
  pausar_humano: 'select public.bot_pausar_humano($1::text, $2::text, $3::text) as r',
  envio_humano: 'select public.bot_envio_humano($1::text, $2::text, $3::text, $4::jsonb, $5::text) as r',
} as const;
type Clave = keyof typeof SQL;

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
    const quien = typeof u.email === 'string' && u.email.trim() ? u.email.trim() : (typeof u.id === 'string' ? u.id : '');
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
const recorta = (v: unknown, max: number): string | undefined => (typeof v === 'string' ? (v.length > max ? v.slice(0, max) : v) : undefined);
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
  },
  recordatorio: {
    // EXCEPCION 2: sin parametros (la ventana de 60 min esta fijada en SQL) y devuelve telefonos de OTROS clientes: es el reloj.
    citas_recordar: {
      claves: ['accion'], tel: false, sql: 'citas_recordar', tipo: 'filas', valida: () => ({ args: [] }),
      formaFilas: (filas) => ({
        citas: filas.slice(0, 20).map((f) => {
          const id = T(f.accion_id), tel = T(f.tel), tipo = T(f.tipo);
          if (!RE_UUID.test(id) || !RE_TEL.test(tel) || (tipo !== 'llamada' && tipo !== 'visita')) mal();
          return { accion_id: id, tel, tipo, cuando_ts: iso(f.cuando_ts), ultimo_entrante_en: isoN(f.ultimo_entrante_en) };
        }),
      }),
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
  humano: {
    // El usuario (ultimo argumento SQL de cada una) lo añade el manejador desde el JWT VERIFICADO; el cuerpo no puede traerlo.
    pausar: {
      claves: ['accion', 'tel', 'modo'], tel: true, sql: 'pausar_humano', tipo: 'json', errores: ['telefono_invalido', 'sin_usuario', 'modo_invalido', 'sin_chat'],
      valida: (o) => (o.modo !== 'pausar' && o.modo !== 'quitar' ? { error: 'modo' } : { args: [o.tel as string, o.modo] }),
      forma: (r) => ({ pausado: B(r.pausado), hasta: isoN(r.hasta) }),
    },
    enviar: {
      claves: ['accion', 'tel', 'texto', 'wamid', 'media'], tel: true, sql: 'envio_humano', tipo: 'json', errores: ['telefono_invalido', 'sin_usuario', 'mensaje_vacio', 'sin_chat'],
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
  estado: () => AJUSTES.topeEstado, recordatorio: () => AJUSTES.topeRecordatorio, humano: () => AJUSTES.topeHumano,
};
const TOPES_TEL: Record<string, () => number> = { estado: () => AJUSTES.topeTelEstado, humano: () => AJUSTES.topeTelHumano };
const MAX_CUERPO: Record<string, () => number> = {
  estado: () => AJUSTES.maxCuerpoEstado, recordatorio: () => AJUSTES.maxCuerpoRecordatorio, humano: () => AJUSTES.maxCuerpoHumano,
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
  if (ruta === 'humano') {
    // La persona que actua sale del JWT verificado, nunca del cuerpo ni del bot. Va la ULTIMA en los argumentos SQL.
    const jwt = (req.headers.get('authorization') ?? '').replace(/^Bearer(\s+|$)/i, '').trim();
    if (!jwt || jwt.length > 4096) return NO_AUTORIZADO();
    const quien = await AUTH.usuario(jwt);
    if (!quien) return NO_AUTORIZADO();
    args.push(quien);
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
