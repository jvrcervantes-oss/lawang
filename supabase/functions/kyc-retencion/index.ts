// kyc-retencion — barrido diario del bucket `kyc` y retención de las copias KYC (LAW-557/558, 13-oct-2026).
// Decisión del owner LAW-558 (13-oct): las copias (ficheros) de los documentos KYC de quien no firma una reserva ni un
// contrato se borran solas a los 12 meses de su última documentación. La ficha se queda entera.
//
// Qué hace, en este orden (la BASE decide qué se borra; esta función solo mueve bytes):
//   1. kyc_barrido(dry): pendientes de alta de más de 36 h y ficheros sin fila y sin pendiente viva (también en la
//      carpeta de un cliente: así se reintenta solo el fichero que la base ya soltó y Storage no borró).
//   2. kyc_retencion(dry): clientes candidatos (12 meses, sin reserva/factura/contrato/portal; 20 por pasada, los más
//      antiguos; con más de 100 no borra nada y avisa).
//   4. kyc_retencion_registra: una fila por pasada en kyc_retencion_pasadas; si fue mal, correo (1 por semana).
//      Sin `kyc_meses_retencion` en config_instancia no hace nada. Los meses NO se leen del cuerpo.
//   3. Borra en Storage las rutas que la base devuelve. En la retención, solo las que empiezan por `<client_id>/` de un
//      cliente aplicado (defensa en profundidad: la base ya las filtra).
//
// Reglas:
//  · Llamador con nombre: SOLO el job pg_cron `kyc-retencion-diario`. Sin JWT de usuario: la puerta es X-Cron-Secret
//    contra `cron_kyc_retencion_secret()` (Vault, generado en la base; nadie lo ha visto), en tiempo constante.
//  · Solo POST, sin CORS (nadie la llama desde un navegador).
//  · `dry` por defecto: solo `{"dry": false}` borra. Cualquier otra clave del cuerpo se ignora.
//  · Respuesta y logs: solo recuentos e ids (queda en net._http_response), nunca rutas ni nombres.
//
// Desplegar con --no-verify-jwt (y `verify_jwt = false` en supabase/config.toml).

const env = (k: string) => (Deno.env.get(k) ?? '').trim();
const URL_SB = env('SUPABASE_URL').replace(/\/$/, '');
const SERVICE = env('SUPABASE_SERVICE_ROLE_KEY');
const BUCKET = 'kyc';

const json = (o: unknown, s = 200) => {
  if (s !== 200) console.error('kyc-retencion ' + s + ': ' + String((o as { error?: unknown })?.error ?? '').slice(0, 120));
  return new Response(JSON.stringify(o), { status: s, headers: { 'content-type': 'application/json' } });
};

// comparación en tiempo constante (copia de deck-sincroniza / cola-correos-envio)
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
    body: JSON.stringify(args), signal: AbortSignal.timeout(30_000),
  });
  const t = await r.text();
  if (!r.ok) throw new Error(nombre + ' HTTP ' + r.status);
  return t ? JSON.parse(t) : null;
}

/** Borra en Storage por lotes de 100. Devuelve cuántos fallaron (nunca revienta el barrido). */
async function borra(rutas: string[]): Promise<number> {
  let fallidos = 0;
  for (let i = 0; i < rutas.length; i += 100) {
    const lote = rutas.slice(i, i + 100);
    try {
      const r = await fetch(`${URL_SB}/storage/v1/object/${BUCKET}`, {
        method: 'DELETE', headers: { ...SERVICIO(), 'content-type': 'application/json' },
        body: JSON.stringify({ prefixes: lote }), signal: AbortSignal.timeout(30_000),
      });
      await r.body?.cancel();
      if (!r.ok) fallidos += lote.length;
    } catch { fallidos += lote.length; }
  }
  return fallidos;
}

const textos = (x: unknown) => (Array.isArray(x) ? x : []).filter((p): p is string => typeof p === 'string' && p.length > 0);

export async function manejador(req: Request): Promise<Response> {
  if (req.method !== 'POST') return json({ ok: false, error: 'metodo' }, 405);
  if (!URL_SB || !SERVICE) return json({ ok: false, error: 'sin_configuracion' }, 500);

  let esperado: unknown;
  try { esperado = await rpc('cron_kyc_retencion_secret'); } catch { return json({ ok: false, error: 'sin_secreto_configurado' }, 500); }
  if (typeof esperado !== 'string' || esperado === '') return json({ ok: false, error: 'sin_secreto_configurado' }, 500);
  if (!igual(req.headers.get('x-cron-secret') || '', esperado)) {
    await req.body?.cancel();
    return json({ ok: false, error: 'no_autorizado' }, 401);
  }

  // Solo se mira `dry`, y solo `false` (booleano) borra. Lo demás del cuerpo (p_meses incluido) no llega a la base.
  const cuerpo = await req.json().catch(() => ({})) as Record<string, unknown>;
  const dry = cuerpo?.dry !== false;

  try {
    const b = (await rpc('kyc_barrido', { p_dry: dry })) as { pendientes_caducadas?: number; rutas?: unknown };
    const rutasB = textos(b?.rutas);
    const fallB = dry ? 0 : await borra(rutasB);

    const r = (await rpc('kyc_retencion', { p_dry: dry })) as {
      activa?: boolean; meses?: number; aviso?: string; candidatos?: number; quedan?: number; aplicados?: number; clientes?: unknown; rutas?: unknown;
    };
    const clientes = textos(r?.clientes);
    // defensa en profundidad: solo ficheros dentro de la carpeta de un cliente aplicado
    const rutasR = dry ? [] : textos(r?.rutas).filter((p) => clientes.some((c) => p.startsWith(c + '/')));
    const fallR = dry ? 0 : await borra(rutasR);

    const salida = {
      ok: fallB === 0 && fallR === 0 && !r?.aviso,
      dry,
      barrido: { pendientes_caducadas: b?.pendientes_caducadas ?? 0, ficheros: rutasB.length, fallidos: fallB },
      retencion: {
        activa: r?.activa === true, meses: r?.meses ?? null, aviso: r?.aviso ?? null,
        candidatos: r?.candidatos ?? 0, quedan: r?.quedan ?? 0, aplicados: r?.aplicados ?? 0, clientes,
        ficheros: dry ? 0 : rutasR.length, fallidos: fallR,
      },
    };
    console.log('kyc-retencion ' + JSON.stringify({ dry, pend: salida.barrido.pendientes_caducadas, fB: rutasB.length,
      cand: salida.retencion.candidatos, apl: salida.retencion.aplicados, fR: rutasR.length, aviso: salida.retencion.aviso }));
    await registra(salida);
    return json(salida, salida.ok ? 200 : 500);
  } catch (_e) {
    await registra({ ok: false, dry, error: 'pasada_fallida' });
    return json({ ok: false, error: 'pasada_fallida' }, 500);
  }
}

/** Deja la pasada en kyc_retencion_pasadas (y la base avisa por correo si fue mal). Nunca tumba la respuesta. */
async function registra(resumen: Record<string, unknown>): Promise<void> {
  try { await rpc('kyc_retencion_registra', { p_resumen: resumen }); } catch { console.error('kyc-retencion: no se pudo registrar la pasada'); }
}

Deno.serve(manejador);
