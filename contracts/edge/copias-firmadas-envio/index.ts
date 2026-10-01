// copias-firmadas-envio — entrega por correo, como adjunto, la copia del contrato
// firmado a quien NO puede verla en el portal (AXW-127). La cola es la tabla
// `copias_firmadas_envios`; la llena `copia_firmada_encolar` (firma-submit, con
// SOLO el contrato) y esta edge la vacía. Hermana de comunicados-envio, con las
// diferencias que pidió la revisión previa #186 (Seguridad, Datos y Deploy):
//
//  · Puerta propia: X-Cron-Secret contra `cron_copias_firmadas_secret()` (Vault,
//    secreto distinto del de avisos-manager: esta edge manda contratos firmados,
//    una fuga del secreto compartido ampliaría el daño). Comparación en tiempo
//    constante. NO lee body ni query: solo vacía la cola.
//  · Todo lo que se envía sale de la base: la ruta del PDF, su sha y su tamaño
//    los devuelve `copia_firmada_reclamar` derivados de `contratos` y del objeto
//    del bucket, no de lo que se guardó al encolar.
//  · Una pasada viva a la vez y una fila por pasada si el PDF pesa >10 MB (el
//    runtime tiene 256 MB y el adjunto es PDF + base64 + cuerpo del fetch).
//  · Antes de enviar se comprueba el tamaño (>18 MB → error terminal visible) y
//    el sha del PDF descargado. Un sha distinto no se envía nunca.
//  · Entrega «al menos una vez»: si el isolate muere con el correo ya aceptado y
//    antes de cerrar, el reintento lo duplica. Máximo 3 intentos y aviso al admin.
//    ACEPTADO: un duplicado raro de un contrato firmado es preferible a perder una copia; decidido por el estudio en la
//    revisión previa #186 (punto 8, Datos). Se mide en el ciclo de 10 firmas reales (log `copia_firmada_enviada_sin_cerrar`).
//    El control de duplicados es solo el estado de la propia cola (la tabla
//    `correos_enviados` la puede escribir un agente: no es una fuente de verdad).
//  · 20 s entre correos (el filtro de spam de Hostinger ya bloqueó una ráfaga) y
//    el freno de bloqueo 554 igual que comunicados-envio.
//  · Registro en `correos_enviados` dentro de la misma transacción que el `ok`
//    (`copia_firmada_ok`): mensaje = plantilla fija sin token ni URL.
//  · Sin dirección de correo en logs, errores ni avisos al admin.
//
// Desplegar con --no-verify-jwt (y `verify_jwt = false` en supabase/config.toml).
// Vive solo en contracts/edge (como comunicados-envio): aterriza.py --edge la
// rechaza, entra por el lote de despliegue del owner.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const ENVIO_EDGE = Deno.env.get('SUPABASE_URL')! + '/functions/v1/envia-correo';
const SECRETO_ENVIO = Deno.env.get('ENVIO_CORREO_SECRET') || Deno.env.get('RENDER_SECRET') || '';

// Mismo umbral que copia_firmada_encolar (18 000 000 bytes): Gmail rechaza más de
// 25 MB incluido el base64 (x1,37). Aquí es una segunda barrera, no la primera.
const MAX_ADJUNTO = 18_000_000;
const ESPERA_MS = 20_000;
// Presupuesto de tiempo de la pasada, muy por debajo del tope de petición de
// Supabase (no medido: se fija prudente) y del arrendamiento de 15 min de la cola.
const PRESUPUESTO_MS = 100_000;
const BLOQUEO_SMTP = /\b554\b|5\.7\.1|Outbound sending is disabled/i;

type Fila = {
  id: string; contrato_id: string; numero: string; proyecto: string | null; email: string;
  nombre: string | null; pdf_path: string; pdf_sha256: string; pdf_bytes: number; intentos: number;
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

async function sha256hex(u8: Uint8Array): Promise<string> {
  const b = await crypto.subtle.digest('SHA-256', u8);
  return [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, '0')).join('');
}

const b64 = (u8: Uint8Array) => {
  // en trozos: `String.fromCharCode(...u8)` con un PDF de MB revienta la pila
  let s = '';
  for (let i = 0; i < u8.length; i += 0x8000) s += String.fromCharCode(...u8.subarray(i, i + 0x8000));
  return btoa(s);
};

// Plantilla FIJA: sin token, sin URL firmada, sin importes ni nombres de otros
// compradores. Lo que se guarda en correos_enviados.mensaje es exactamente esto
// (lo fija copias_firmadas.test.js).
export function plantilla(f: { numero: string; proyecto: string | null; nombre: string | null }) {
  const asunto = 'Contrato firmado · ' + f.numero;
  const proy = f.proyecto ? ' (' + f.proyecto + ')' : '';
  const mensaje = f.nombre
    ? 'Hola ' + f.nombre.split(' ')[0] + ',\n\nHemos recibido la firma. Aquí tienes tu copia del contrato ' + f.numero + proy +
      ', ya firmado, adjunta a este correo.\n\nGuárdalo: es el documento con el registro de firma electrónica que acredita la operación.\n\nLawang Tropical Properties'
    : 'Se ha completado la firma del contrato ' + f.numero + proy + '.\n\nCopia para archivo, adjunta a este correo.\n\nLawang Tropical Properties';
  return { asunto, mensaje };
}

async function enviar(f: Fila, pdf: Uint8Array, asunto: string, mensaje: string) {
  const r = await fetch(ENVIO_EDGE, {
    method: 'POST',
    // Un timeout es AMBIGUO (el SMTP pudo aceptarlo): cuenta como fallo del intento y puede acabar en duplicado.
    signal: AbortSignal.timeout(60_000),
    headers: { 'content-type': 'application/json', 'X-Render-Secret': SECRETO_ENVIO, 'X-Llamante': 'copias-firmadas-envio' },
    body: JSON.stringify({ to: f.email, subject: asunto, message: mensaje, filename: f.numero + '_firmado.pdf', pdf_base64: b64(pdf) }),
  });
  const t = await r.text();
  if (!r.ok || !t.includes('"ok":true')) throw new Error('HTTP ' + r.status + ': ' + t.slice(0, 200));
}

// Aviso al admin cuando una copia queda en 'error': nunca silencio. Solo el número
// del contrato y el motivo, sin direcciones.
async function avisaAdmin(numero: string, motivo: string): Promise<boolean> {
  try {
    const { data } = await sb.from('config_instancia').select('valor').eq('clave', 'email_avisos_sistema').maybeSingle();
    const to = typeof data?.valor === 'string' ? data.valor.trim() : '';
    if (!to) return false;
    const r = await fetch(ENVIO_EDGE, {
      method: 'POST',
      signal: AbortSignal.timeout(60_000),
      headers: { 'content-type': 'application/json', 'X-Render-Secret': SECRETO_ENVIO, 'X-Llamante': 'copias-firmadas-envio' },
      body: JSON.stringify({
        to, subject: 'Copia firmada sin entregar · ' + numero, attach: false,
        message: 'Una copia del contrato firmado ' + numero + ' no se ha podido entregar (' + motivo.slice(0, 120) +
          '). Revisa la tabla copias_firmadas_envios (estado «error»): hay que resolverla a mano.',
      }),
    });
    return r.ok;
  } catch (e) { console.error('copia_firmada_aviso_admin_fallo', String((e as Error)?.message ?? e).slice(0, 120)); return false; }
}

// El motivo que se guarda/avisa: sin direcciones y recortado. La RPC lo vuelve a limpiar.
const limpio = (m: string) => m.replace(/\S+@\S+/g, '<correo>').slice(0, 300);

// Al final de CADA pasada: toda fila que haya acabado en 'error' (agotado, PDF no encontrado, comprador fuera del
// portal con un PDF demasiado grande, tres fallos…) se avisa al admin una vez y se marca. Nunca silencio.
async function avisaPendientes() {
  try {
    const { data } = await sb.rpc('copias_firmadas_sin_avisar');
    const hechas: string[] = [];
    for (const r of (data ?? []) as { id: string; numero: string; error: string | null }[]) {
      if (await avisaAdmin(r.numero, r.error ?? 'error')) hechas.push(r.id);
    }
    if (hechas.length) await sb.rpc('copias_firmadas_marca_avisadas', { p_ids: hechas });
  } catch (e) { console.error('copia_firmada_avisos_fallo', String((e as Error)?.message ?? e).slice(0, 120)); }
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'metodo' }, 405);
  if (!SECRETO_ENVIO) return json({ error: 'config' }, 500);

  const { data: esperado, error: eSec } = await sb.rpc('cron_copias_firmadas_secret');
  if (eSec || !esperado) return json({ error: 'sin_secreto_configurado' }, 500);
  if (!igual(req.headers.get('x-cron-secret') || '', String(esperado))) return json({ error: 'no_autorizado' }, 401);

  const r = await pasada();
  await avisaPendientes();
  return r;
});

async function pasada(): Promise<Response> {
  const inicio = Date.now();
  const { data: mant } = await sb.from('mantenimiento').select('envios_pausados').eq('id', 1).maybeSingle();
  if (mant?.envios_pausados) return json({ ok: true, pausado: true, enviadas: 0, fallidas: 0 });

  const { data: tanda, error: eRec } = await sb.rpc('copia_firmada_reclamar', { p_tope: 3 });
  if (eRec) { console.error('copia_firmada_reclamar', eRec.message); return json({ error: 'reclamar' }, 500); }
  const filas = (tanda ?? []) as Fila[];
  if (!filas.length) {
    await sb.rpc('copias_firmadas_purga');
    return json({ ok: true, enviadas: 0, fallidas: 0 });
  }

  let enviadas = 0, fallidas = 0;
  for (let i = 0; i < filas.length; i++) {
    const f = filas[i];
    // sin tiempo para otro: el resto vuelve a la cola sin gastar intento
    if (i > 0 && Date.now() - inicio + ESPERA_MS > PRESUPUESTO_MS) {
      for (const r of filas.slice(i)) await sb.rpc('copia_firmada_fallo', { p_id: r.id, p_error: 'sin_tiempo_en_la_pasada', p_devolver: true });
      break;
    }
    if (i > 0) await new Promise((r) => setTimeout(r, ESPERA_MS));
    try {
      if (f.pdf_bytes > MAX_ADJUNTO) {
        await sb.rpc('copia_firmada_fallo', { p_id: f.id, p_error: 'pdf_demasiado_grande_para_adjuntar', p_terminal: true });
        console.error('copia_firmada_error contrato', f.numero, 'pdf_demasiado_grande_para_adjuntar');
        fallidas++; continue;
      }
      const dl = await sb.storage.from('contratos-firmados').download(f.pdf_path);
      if (dl.error || !dl.data) {
        const terminal = /not.?found|404|does not exist/i.test(String(dl.error?.message ?? ''));
        throw Object.assign(new Error('descarga: ' + (dl.error?.message ?? 'vacía')), { terminal });
      }
      let pdf: Uint8Array | null = new Uint8Array(await dl.data.arrayBuffer());
      if (pdf.length > MAX_ADJUNTO) throw Object.assign(new Error('pdf_demasiado_grande_para_adjuntar'), { terminal: true });
      if ((await sha256hex(pdf)) !== f.pdf_sha256) throw Object.assign(new Error('sha_distinto'), { terminal: true });

      const { asunto, mensaje } = plantilla(f);
      await enviar(f, pdf, asunto, mensaje);
      pdf = null;
      // El correo YA salió: se reintenta el CIERRE (3 veces). Si no cierra, la fila queda en 'enviando' y a los 15 min la
      // pasada siguiente la reenvía: duplicado posible, ver «al menos una vez» arriba. Queda en el log para medirlo.
      let cerrado = false;
      for (let k = 0; k < 3 && !cerrado; k++) {
        const ok = await sb.rpc('copia_firmada_ok', { p_id: f.id, p_asunto: asunto, p_mensaje: mensaje });
        if (!ok.error && ok.data === true) cerrado = true;
        else if (!ok.error) break;                       // false: la fila ya no estaba 'enviando', reintentar no cambia nada
        else await new Promise((r) => setTimeout(r, 1500));
      }
      if (!cerrado) console.error('copia_firmada_enviada_sin_cerrar contrato', f.numero, 'fila', f.id);
      enviadas++;
    } catch (err) {
      const msg = limpio(String((err as Error)?.message ?? err));
      const terminal = (err as { terminal?: boolean })?.terminal === true;
      if (BLOQUEO_SMTP.test(msg)) {
        // No es culpa de este destinatario: esta fila y las que quedaban vuelven a
        // la cola sin gastar el intento y los envíos se pausan para todos.
        for (const r of filas.slice(i)) await sb.rpc('copia_firmada_fallo', { p_id: r.id, p_error: msg, p_devolver: true });
        await sb.from('mantenimiento').update({
          envios_pausados: true,
          motivo: 'Pausa automática: el proveedor de correo ha bloqueado el envío (' + msg.slice(0, 120) + ').',
          cambiado_por: null, cambiado_en: new Date().toISOString(),
        }).eq('id', 1);
        return json({ ok: false, enviadas, fallidas: fallidas + 1, pausado: true });
      }
      await sb.rpc('copia_firmada_fallo', { p_id: f.id, p_error: msg, p_terminal: terminal });
      console.error('copia_firmada_fallo contrato', f.numero, 'intento', f.intentos, msg.slice(0, 100));
      fallidas++;
    }
  }
  return json({ ok: true, enviadas, fallidas });
}
