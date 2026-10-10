// deck-sincroniza — barrido diario de las fotos del deck a su bucket debido (AXW-66 S5/S6, 10-oct-2026).
// Encargo: encargos/20260928_lawang_deck_fotos_privadas.md (repo de la agencia) → S5 y S6.
//
// Qué hace: pide a la base lo que está mal puesto (`deck_fotos_desajustes()`, dueña única del «bucket debido»: foto de
// proyecto con deck abierto → `deck`; cerrado, huérfano sin fila → `deck-privado`) y lo mueve por Storage conservando el
// nombre. Es lo único que barre el huérfano de una subida con URL firmada que nunca se registró: si el deck estaba
// abierto quedaría en `deck`, público, para siempre (Seguridad, 28-sep). Por eso corre a diario.
//
// Reglas:
//  · Llamador con nombre: SOLO el job de pg_cron `deck-sincroniza-diario` (migración 20261010210000). Sin JWT de
//    usuario: la puerta es X-Cron-Secret contra `cron_deck_sincroniza_secret()` (Vault, generado dentro de la base;
//    nadie lo ha visto), comparada en tiempo constante. NO lee body, query ni URL: solo barre.
//  · El mismo interruptor que `ficheros`: sin el secreto de entorno DECK_SINCRONIZA=on responde 409 y no mueve nada.
//  · `en_ambos` (mismo nombre en los dos buckets) NO se toca: decide una persona. Se cuenta y se devuelve.
//  · La respuesta solo lleva recuentos (queda en net._http_response): ni rutas ni nombres.
//  · Se salta los proyectos en transición: eso lo hace ya `deck_fotos_desajustes()` (marca de `deck_transiciones`).
//
// DUPLICADO A PROPÓSITO: `mueveObjeto` y `reconcilia` son copia de las de supabase/functions/ficheros/index.ts (acción
// `sincroniza` / `deck_activa`). Se copiaron en vez de tocar `ficheros` porque otra sesión la estaba desplegando el
// 10-oct; pasarlas a `_shared/` es criterio de S6 cuando `ficheros` esté quieta (y entonces la acción `sincroniza` de
// `ficheros`, que no tiene llamador, se retira). Diferencias a propósito: aquí `mueveObjeto` tiene tope de 20 s y un
// fallo de red cuenta como fallida (no revienta el barrido). Lo que importa de las dos lo fija deck_sincroniza.test.js
// (origen → destino, `en_ambos` intacto, parar sin progreso). Si cambias una, cambia la otra.
//
// Desplegar con --no-verify-jwt (y `verify_jwt = false` en supabase/config.toml).

const env = (k: string) => (Deno.env.get(k) ?? '').trim();
const URL_SB = env('SUPABASE_URL').replace(/\/$/, '');
const SERVICE = env('SUPABASE_SERVICE_ROLE_KEY');
const MAX_PASADAS = 40;

type Desajuste = { name: string; bucket_real: string; bucket_debido: string; proyecto_id: string | null; motivo: string };

const json = (o: unknown, s = 200) => {
  if (s !== 200) console.error('deck-sincroniza ' + s + ': ' + String((o as { error?: unknown })?.error ?? '').slice(0, 120));
  return new Response(JSON.stringify(o), { status: s, headers: { 'content-type': 'application/json' } });
};

// comparación en tiempo constante (copia de cola-correos-envio)
function igual(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a), y = new TextEncoder().encode(b);
  let d = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) d |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return d === 0;
}

const SERVICIO = () => ({ apikey: SERVICE, Authorization: 'Bearer ' + SERVICE });

/** RPC con la clave de servicio. El error solo lleva nombre y estado, nunca el cuerpo. */
async function rpc(nombre: string, args: Record<string, unknown> = {}): Promise<unknown> {
  const r = await fetch(URL_SB + '/rest/v1/rpc/' + nombre, {
    method: 'POST', headers: { ...SERVICIO(), 'Content-Type': 'application/json' },
    body: JSON.stringify(args), signal: AbortSignal.timeout(15_000),
  });
  const t = await r.text();
  if (!r.ok) throw new Error(nombre + ' HTTP ' + r.status);
  return t ? JSON.parse(t) : null;
}

// Mover conservando el nombre (rutas planas, revisión #139 DAT3). Copia de ficheros/index.ts.
async function mueveObjeto(name: string, desde: string, hacia: string): Promise<boolean> {
  try {
    const r = await fetch(`${URL_SB}/storage/v1/object/move`, {
      method: 'POST',
      headers: { ...SERVICIO(), 'content-type': 'application/json' },
      body: JSON.stringify({ bucketId: desde, sourceKey: name, destinationKey: name, destinationBucket: hacia }),
      signal: AbortSignal.timeout(20_000),
    });
    await r.body?.cancel();
    return r.ok;
  } catch { return false; }
}

// Por pasadas hasta que no quede nada o una pasada no mueva nada (lo que quede son fallos de Storage y se devuelven
// como `quedan`, nunca en silencio). Copia de `reconcilia(null)` de ficheros/index.ts.
async function reconcilia(): Promise<{ movidas: number; fallidas: number; quedan: number; en_ambos: number }> {
  let movidas = 0, fallidas = 0;
  for (let pasada = 0; ; pasada++) {
    const todas = ((await rpc('deck_fotos_desajustes', { p_proyecto_id: null })) ?? []) as Desajuste[];
    const filas = todas.filter((d) => d.motivo !== 'en_ambos');
    const en_ambos = todas.length - filas.length;
    if (!filas.length || pasada >= MAX_PASADAS) return { movidas, fallidas, quedan: filas.length, en_ambos };
    let estaPasada = 0;
    for (let i = 0; i < filas.length; i += 8) {
      const lote = await Promise.all(filas.slice(i, i + 8).map((d) => mueveObjeto(d.name, d.bucket_real, d.bucket_debido)));
      lote.forEach((ok) => ok ? (movidas++, estaPasada++) : fallidas++);
    }
    if (!estaPasada) return { movidas, fallidas, quedan: filas.length, en_ambos };   // sin progreso: no insistir
  }
}

export async function manejador(req: Request): Promise<Response> {
  if (req.method !== 'POST') return json({ ok: false, error: 'metodo' }, 405);
  await req.body?.cancel();                                         // no se lee: nada del llamador decide qué se mueve
  if (!URL_SB || !SERVICE) return json({ ok: false, error: 'sin_configuracion' }, 500);

  let esperado: unknown;
  try { esperado = await rpc('cron_deck_sincroniza_secret'); } catch { return json({ ok: false, error: 'sin_secreto_configurado' }, 500); }
  if (typeof esperado !== 'string' || esperado === '') return json({ ok: false, error: 'sin_secreto_configurado' }, 500);
  if (!igual(req.headers.get('x-cron-secret') || '', esperado)) return json({ ok: false, error: 'no_autorizado' }, 401);

  if (env('DECK_SINCRONIZA') !== 'on') return json({ ok: false, error: 'sincroniza_apagada' }, 409);

  try {
    // `fallidas` suma intentos fallidos de TODAS las pasadas: uno que falla en la 1.ª y entra en la 2.ª no es un error.
    // Lo que manda es `quedan` (lo que la base sigue viendo mal puesto al acabar). `en_ambos` no es fallo del barrido:
    // lo decide una persona y lo canta salud_lawang.py.
    const r = await reconcilia();
    if (r.quedan > 0) return json({ ok: false, error: 'quedan_sin_mover', ...r }, 500);
    return json({ ok: true, ...r });
  } catch (_e) {
    return json({ ok: false, error: 'desajustes_no_leidos' }, 500);
  }
}

Deno.serve(manejador);
