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
// Desplegar con --no-verify-jwt (y `verify_jwt = false` en supabase/config.toml). Activación: ACTIVACION.md.

const env = (k: string) => (Deno.env.get(k) ?? '').trim();

// Ajustes mutables SOLO para las pruebas (nada los toca desde fuera de la edge).
export const AJUSTES = {
  ventanaMs: 60_000,
  topeCatalogo: 30,       // el bot pide el catálogo una vez por mensaje de venta, no más
  topeCrm: 90,
  maxCuerpo: 4096,        // bytes; una nota son ≤500 caracteres
  dbTimeoutMs: 8_000,
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
} as const;
type Clave = keyof typeof SQL;

class ErrorBase extends Error {
  codigo: 'db_conexion' | 'db_error';
  constructor(codigo: 'db_conexion' | 'db_error') { super(codigo); this.codigo = codigo; }
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
        conexion = postgres(url, { prepare: false, max: 1, connect_timeout: 8, idle_timeout: 20, onnotice: () => {} });
      }
      const consulta = conexion.unsafe(SQL[clave], args as never[]);
      const tope = new Promise((_, no) => setTimeout(() => no(new Error('timeout')), AJUSTES.dbTimeoutMs));
      return await Promise.race([consulta, tope]) as Record<string, unknown>[];
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
    const t = texto(o.texto, 1000);
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

export async function manejador(req: Request): Promise<Response> {
  const ruta = rutaDe(req);
  const esperado = secretoDe(ruta);
  const dado = (req.headers.get('x-bot-secret') ?? '').trim();
  // Fail-closed: sin secreto configurado, sin cabecera, método que no es POST, ruta desconocida o secreto malo → el mismo 401.
  if (!esperado || !dado || req.method !== 'POST' || !igual(dado, esperado)) return NO_AUTORIZADO();

  const espera = demasiado(ruta, ruta === 'catalogo' ? AJUSTES.topeCatalogo : AJUSTES.topeCrm);
  if (espera) return json({ error: 'demasiadas_peticiones' }, 429, { 'retry-after': String(espera) });

  try {
    return ruta === 'catalogo' ? await rutaCatalogo() : await rutaCrm(req);
  } catch (e) {
    // La base caída NO se parece a "vacío": 503 para que el bot use el último catálogo bueno o diga que no lo tiene.
    if (e instanceof ErrorBase) return json({ error: e.codigo }, e.codigo === 'db_conexion' ? 503 : 502);
    return json({ error: 'interno' }, 500);
  }
}

Deno.serve(manejador);
