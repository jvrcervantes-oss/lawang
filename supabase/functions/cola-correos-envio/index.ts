// cola-correos-envio — drena la cola `correos_cola` (AXW-202 C1, 5-oct-2026).
// Encargo: encargos/20261002_estudio_cola_de_correos.md → «Plan revisado (5-oct-2026)», puntos 1-18.
//
// Qué hace: reclama filas (lease por fila, `correo_cola_reclamar`), manda cada una por el motor de
// `envia-correo` (plantilla + ids; el motor lee de la base los datos, el enlace y el texto) y cierra con
// `correo_cola_ok` / `correo_cola_fallo`. Las funciones delicadas (firma-submit…) solo ENCOLAN
// (`correo_encolar`): no conocen SMTP, plantillas ni texto.
//
// Reglas (las fija cola_correos.test.js):
//  · Puerta propia: X-Cron-Secret contra `cron_correos_cola_secret()` (Vault; no el de AXW-127 ni RENDER_SECRET),
//    comparación en tiempo constante. NO lee body, query ni URL: solo drena lo que hay.
//  · Todo lo que se manda sale de la base: el destinatario lo resuelve `correo_cola_reclamar` desde el dueño del dato
//    (contrato_firmas.firmante_email), el enlace de firma lo lee envia-correo en el momento del envío. Esta edge no
//    guarda ni registra direcciones, tokens ni textos: sin direcciones en logs, errores ni cierres de fallo.
//  · El hecho sigue vigente (enlace vivo, contrato no liberado, tope de antigüedad) lo comprueba la RPC al reclamar;
//    envia-correo lo vuelve a comprobar al componer (un 400 suyo cierra la fila como error terminal).
//  · Un escritor de `correos_enviados`: `correo_cola_ok`, en la MISMA transacción que marca `ok` (envia-correo no lo escribe).
//  · Entrega «al menos una vez»: si el isolate muere con el correo ya aceptado y antes de cerrar, el lease vence y se
//    reenvía. Duplicado de un enlace de firma = inocuo (el enlace es el mismo). Se avisa en el log (`cola_correo_enviado_sin_cerrar`).
//  · Pausa global (`mantenimiento.envios_pausados`): no se reclama nada y la cola espera; no es silenciosa porque
//    `correo_cola_salud` (tools/salud_lawang.py) cuenta lo pendiente antiguo.
//  · Bloqueo del proveedor (554 / 5.7.1 / «Outbound sending is disabled»): la fila vuelve a la cola SIN gastar intento y se
//    pausan los envíos, igual que las otras colas del estudio (BLOQUEO_SMTP de comunicados-envio).
//
// Desplegar con --no-verify-jwt (y `verify_jwt = false` en supabase/config.toml). Código REAL aquí, no un puntero.

const env = (k: string) => (Deno.env.get(k) ?? '').trim();
const SUPA_URL = () => env('SUPABASE_URL').replace(/\/$/, '');
const SUPA_SERVICE = () => env('SUPABASE_SERVICE_ROLE_KEY');
const SECRETO_ENVIO = () => env('ENVIO_CORREO_SECRET');

// Ajustes mutables SOLO para las pruebas (no hay forma de tocarlos desde fuera de la edge).
export const AJUSTES = {
  esperaMs: 5_000,          // entre correos que no son de prioridad 1 (el filtro de spam de Hostinger ya bloqueó una ráfaga; no medido)
  presupuestoMs: 100_000,   // tiempo de una pasada: muy por debajo del tope de petición y del lease de 4 min
  lote: 5,
  rondasMax: 10,
};
const BLOQUEO_SMTP = /\b554\b|5\.7\.1|Outbound sending is disabled/i;
const EN_PAUSA = /en pausa \(modo mantenimiento\)/i;

// Los ids que el motor pide a cada clave (espejo de PLANTILLAS en envia-correo/valida.ts; la prueba los cruza).
export const IDS_POR_CLAVE: Record<string, string[]> = {
  enlace_firma_cadena: ['contrato_id', 'firma_id'],
  aviso_anulacion: ['contrato_id'],
  reclamo_pago: ['contrato_id'],   // + vars.reclamo (id de la fila) y `sociedad`: ver enviar()
};

type Fila = {
  id: string; clave: string; firma_id: string | null; contrato_id: string | null; factura_id: string | null;
  vars: Record<string, string> | null; para: string | null; prioridad: number; intentos: number;
};

const json = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { 'content-type': 'application/json' } });

// comparación en tiempo constante (no corta en el primer byte distinto)
function igual(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a), y = new TextEncoder().encode(b);
  let d = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) d |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return d === 0;
}

const SERVICIO = () => ({ apikey: SUPA_SERVICE(), Authorization: 'Bearer ' + SUPA_SERVICE() });

/** RPC de PostgREST con la clave de servicio. El error NO lleva el cuerpo de la respuesta (podría llevar datos): solo nombre y estado. */
async function rpc(nombre: string, args: Record<string, unknown> = {}): Promise<unknown> {
  const r = await fetch(SUPA_URL() + '/rest/v1/rpc/' + nombre, {
    method: 'POST', headers: { ...SERVICIO(), 'Content-Type': 'application/json' },
    body: JSON.stringify(args), signal: AbortSignal.timeout(15_000),
  });
  const t = await r.text();
  if (!r.ok) throw new Error(nombre + ' HTTP ' + r.status);
  return t ? JSON.parse(t) : null;
}

const espera = (ms: number) => ms > 0 ? new Promise((r) => setTimeout(r, ms)) : Promise.resolve();
const limpio = (m: string) => m.replace(/\S+@\S+/g, '<correo>').slice(0, 300);

async function enviosPausados(): Promise<boolean> {
  try {
    const r = await fetch(SUPA_URL() + '/rest/v1/mantenimiento?select=envios_pausados&id=eq.1',
      { headers: SERVICIO(), signal: AbortSignal.timeout(8_000) });
    if (!r.ok) { await r.text().catch(() => ''); return true; }       // sin poder preguntar, NO se manda (como envia-correo)
    const f = await r.json();
    return !Array.isArray(f) || f[0]?.envios_pausados !== false;
  } catch { return true; }
}

/** Pide el envío al motor de envia-correo. Devuelve el estado HTTP, el texto de error (sin cuerpo si fue bien) y la versión de la plantilla. */
async function enviar(f: Fila): Promise<{ status: number; ok: boolean; version: string; error: string }> {
  const ids = IDS_POR_CLAVE[f.clave];
  const cuerpo: Record<string, unknown> = { to: f.para, plantilla: f.clave, attach: false };
  for (const k of ids) cuerpo[k] = k === 'contrato_id' ? f.contrato_id : k === 'firma_id' ? f.firma_id : f.factura_id;
  if (f.clave === 'reclamo_pago') {
    // «Reclamar pago»: el destinatario ya viene de la base (`para`, resuelto por correo_cola_reclamar desde el libro) y el resto lo lee
    // envia-correo con el id de la fila. Aquí solo viajan el id y la clave de la sociedad del CONTRATO (marca/firma del correo): nunca una
    // dirección, un nombre ni la nota, y `f.vars` de esta clave se ignora. Sin sociedad no se envía: no se firma como otra empresa.
    const d = (await rpc('reclamo_pago_datos', { p_cola: f.id })) as { sociedad_clave?: unknown }[] | null;
    const soc = Array.isArray(d) && d.length === 1 ? d[0].sociedad_clave : null;
    if (typeof soc !== 'string' || soc === '') return { status: 400, ok: false, version: '', error: 'reclamo_sin_sociedad' };
    cuerpo.vars = { reclamo: f.id };
    cuerpo.sociedad = soc;
  } else if (f.vars && Object.keys(f.vars).length) cuerpo.vars = f.vars;
  const r = await fetch(SUPA_URL() + '/functions/v1/envia-correo', {
    method: 'POST',
    // Un timeout es AMBIGUO (el SMTP pudo aceptarlo): cuenta como fallo del intento y puede acabar en duplicado.
    signal: AbortSignal.timeout(60_000),
    headers: { 'content-type': 'application/json', 'X-Render-Secret': SECRETO_ENVIO(), 'X-Llamante': 'cola-correos-envio' },
    body: JSON.stringify(cuerpo),
  });
  const t = await r.text();
  let o: { ok?: unknown; error?: unknown; version?: unknown } = {};
  try { o = JSON.parse(t); } catch { /* respuesta sin JSON */ }
  const ok = r.status === 200 && o.ok === true;
  return { status: r.status, ok, version: typeof o.version === 'string' ? o.version : '',
           error: ok ? '' : limpio(typeof o.error === 'string' ? o.error : 'HTTP ' + r.status) };
}

async function pasada(): Promise<Response> {
  const inicio = Date.now();
  if (await enviosPausados()) return json({ ok: true, pausado: true, enviadas: 0, fallidas: 0 });

  let enviadas = 0, fallidas = 0, enviadoAlguno = false;
  for (let ronda = 0; ronda < AJUSTES.rondasMax; ronda++) {
    if (Date.now() - inicio > AJUSTES.presupuestoMs) break;
    let filas: Fila[];
    try { filas = ((await rpc('correo_cola_reclamar', { p_max: AJUSTES.lote })) ?? []) as Fila[]; }
    catch (e) { console.error('cola_correo_reclamar_fallo', String((e as Error)?.message ?? e).slice(0, 80)); return json({ error: 'reclamar' }, 500); }
    if (!filas.length) {
      try { await rpc('correos_cola_purga'); } catch (e) { console.error('cola_correo_purga_fallo', String((e as Error)?.message ?? e).slice(0, 80)); }
      return json({ ok: true, enviadas, fallidas });
    }

    for (let i = 0; i < filas.length; i++) {
      const f = filas[i];
      const devuelve = async (desde: number, motivo: string, esperaS: number) => {
        for (const x of filas.slice(desde)) await rpc('correo_cola_fallo', { p_id: x.id, p_error: motivo, p_devolver: true, p_espera_s: esperaS }).catch(() => null /* MUDO A PROPOSITO: si no se puede devolver la fila, su lease de 4 min vence y la recoge la pasada siguiente; no hay nada que reintentar aquí */);
      };
      // sin tiempo para otro: el resto vuelve a la cola sin gastar intento
      if (Date.now() - inicio > AJUSTES.presupuestoMs) { await devuelve(i, 'sin_tiempo_en_la_pasada', 0); return json({ ok: true, enviadas, fallidas, cortada: true }); }
      if (!IDS_POR_CLAVE[f.clave] || !f.para) {
        await rpc('correo_cola_fallo', { p_id: f.id, p_error: !f.para ? 'sin_destinatario' : 'clave_sin_resolver_en_la_edge', p_terminal: true }).catch(() => null /* MUDO A PROPOSITO: si no cierra, el lease vence y la RPC de reclamar la vuelve a ver; aquí queda en el log (línea siguiente) */);
        console.error('cola_correo_terminal clave', f.clave, 'fila', f.id);
        fallidas++; continue;
      }
      if (enviadoAlguno && f.prioridad > 1) await espera(AJUSTES.esperaMs);
      try {
        const e = await enviar(f);
        enviadoAlguno = true;
        if (e.ok) {
          // El correo YA salió: se reintenta el CIERRE (3 veces). Si no cierra, el lease vence y se reenvía (ver «al menos una vez»).
          let cerrado = false;
          for (let k = 0; k < 3 && !cerrado; k++) {
            try {
              const ok = await rpc('correo_cola_ok', { p_id: f.id, p_para: f.para, p_version: e.version });
              if (ok === true) cerrado = true; else break;      // false: la fila ya no estaba `enviando`; reintentar no cambia nada
            } catch { /* MUDO A PROPOSITO: se reintenta el cierre (3 veces) y, si ninguno cierra, queda `cola_correo_enviado_sin_cerrar` en el log y el lease vence */ await espera(AJUSTES.esperaMs > 0 ? 1_500 : 0); }
          }
          if (!cerrado) console.error('cola_correo_enviado_sin_cerrar clave', f.clave, 'fila', f.id);
          console.log(JSON.stringify({ fn: 'cola-correos-envio', clave: f.clave, fila: f.id, estado: 'ok', version: e.version }));
          enviadas++; continue;
        }
        if (BLOQUEO_SMTP.test(e.error)) {
          // No es culpa de este correo: esta fila y las que quedaban vuelven a la cola y los envíos se pausan para todos.
          await devuelve(i, e.error, 600);
          await fetch(SUPA_URL() + '/rest/v1/mantenimiento?id=eq.1', {
            method: 'PATCH', headers: { ...SERVICIO(), 'Content-Type': 'application/json' },
            body: JSON.stringify({ envios_pausados: true, motivo: 'Pausa automática: el proveedor de correo ha bloqueado el envío (' + e.error.slice(0, 120) + ').',
              cambiado_por: null, cambiado_en: new Date().toISOString() }),
            signal: AbortSignal.timeout(8_000),
          }).then((r) => r.text()).catch(() => null);
          return json({ ok: false, enviadas, fallidas: fallidas + 1, pausado: true });
        }
        if (e.status === 503 || EN_PAUSA.test(e.error)) { await devuelve(i, 'envios_en_pausa', 300); return json({ ok: true, enviadas, fallidas, pausado: true }); }
        if (e.status === 401 || e.status === 403) {
          console.error('cola_correo_envia_correo_rechaza_la_puerta HTTP', e.status);
          await devuelve(i, 'envia_correo_rechaza_la_credencial', 600);
          return json({ ok: false, enviadas, fallidas, error: 'credencial' }, 500);
        }
        // 400 = el motor no acepta el documento (el hecho cambió entre reclamar y componer): terminal, visible. El resto reintenta con backoff.
        const terminal = e.status === 400;
        await rpc('correo_cola_fallo', { p_id: f.id, p_error: e.error, p_terminal: terminal });
        console.error('cola_correo_fallo clave', f.clave, 'fila', f.id, 'HTTP', e.status, 'intento', f.intentos);
        fallidas++;
      } catch (err) {
        const msg = limpio(String((err as Error)?.name ?? 'error') + ': ' + String((err as Error)?.message ?? err));
        await rpc('correo_cola_fallo', { p_id: f.id, p_error: msg }).catch(() => null /* MUDO A PROPOSITO: si no se anota el fallo, el lease vence y se reintenta; el error ya va al log justo debajo */);
        console.error('cola_correo_fallo clave', f.clave, 'fila', f.id, 'intento', f.intentos);
        fallidas++;
      }
    }
  }
  return json({ ok: true, enviadas, fallidas, cortada: true });
}

export async function manejador(req: Request): Promise<Response> {
  if (req.method !== 'POST') return json({ error: 'metodo' }, 405);
  if (!SUPA_URL() || !SUPA_SERVICE() || !SECRETO_ENVIO()) return json({ error: 'config' }, 500);

  let esperado: unknown = null;
  try { esperado = await rpc('cron_correos_cola_secret'); } catch { return json({ error: 'sin_secreto_configurado' }, 500); }
  if (typeof esperado !== 'string' || esperado === '') return json({ error: 'sin_secreto_configurado' }, 500);
  if (!igual(req.headers.get('x-cron-secret') || '', esperado)) return json({ error: 'no_autorizado' }, 401);

  return await pasada();
}

Deno.serve(manejador);
