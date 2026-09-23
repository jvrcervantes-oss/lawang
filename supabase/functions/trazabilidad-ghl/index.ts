// trazabilidad-ghl — cruza los leads de Lawang con los contactos de las cuentas
// GoHighLevel PROPIAS de los sales managers (23-sep-2026, owner: «ver si un cliente
// entra por distintos funnels y que no nos apriete con descuentos jugando a doble
// banda»). Tablas y funciones: migración `trazabilidad_ghl`.
//
// SOLO LECTURA sobre GHL: aquí no hay ni un POST de escritura a su API (el único POST
// es /contacts/search, que es una búsqueda). Lo ideal es que además el token lleve solo
// el scope contacts.readonly — así lo garantiza GHL y no solo este código.
//
// Revisión previa #49 (Seguridad + Legal):
//  · teléfono y email NUNCA salen de esta función en claro: se guardan como HMAC-SHA256
//    con TRAZA_PEPPER, que vive SOLO en los secrets de esta Edge. En la base no está.
//  · de cada pasada solo se guardan las huellas que coinciden con otra fuente; el resto
//    se descarta en memoria (minimización).
//  · no se loguean cabeceras ni cuerpos de GHL (traen PII y el token).
//
// Dos puertas (verify_jwt=false, la puerta está aquí dentro):
//  · X-Cron-Secret (pg_cron, cada 6 h) → accion 'sincronizar' sobre las cuentas activas.
//  · JWT de un super_admin (la pestaña Trazabilidad del CRM):
//      'alta'        {manager_id, location_id, etiqueta, token}  valida el token contra GHL
//                    y da de alta la cuenta APAGADA. manager_id = usuario sales_manager
//                    de la intranet (desplegable, owner 23-sep). El token va a Vault como parámetro de
//                    RPC, nunca como literal en SQL.
//      'token'       {cuenta_id, token}                      cambia el token (rotación).
//      'probar'      {cuenta_id}                             pasada en seco de UNA cuenta,
//                    aunque esté apagada: devuelve solo cifras, no guarda nada.
//      'sincronizar'                                         la pasada real, a mano.
//
// ⚠️ COPIA REAL, NO SYMLINK: `supabase/functions/trazabilidad-ghl/index.ts` y
// `contracts/edge/trazabilidad-ghl/index.ts` deben ser idénticas.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const PEPPER = Deno.env.get('TRAZA_PEPPER') ?? '';

const GHL = 'https://services.leadconnectorhq.com';
const PAGINA = 100;
const TOPE_PAGINAS = 150;          // 15.000 contactos por cuenta: si se pasa, algo raro hay

const ORIGENES = ['https://lawangproperties.com', 'https://www.lawangproperties.com'];
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

// ── normalización: lo que decide si dos registros son la misma persona ────────────
// Teléfono: solo dígitos y los 9 últimos. Así +62 812… y 0812… (Indonesia) o +34 6… y
// 6… (España) dan lo mismo; con ~2.500 números, 10^9 combinaciones no chocan.
function normTel(t: unknown): string | null {
  const d = String(t ?? '').replace(/\D/g, '');
  return d.length >= 8 ? d.slice(-9) : null;
}
function normEmail(e: unknown): string | null {
  const s = String(e ?? '').trim().toLowerCase();
  return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(s) ? s : null;
}

let CLAVE: CryptoKey | null = null;
async function hmac(tipo: string, valor: string): Promise<string> {
  if (!CLAVE) {
    CLAVE = await crypto.subtle.importKey('raw', new TextEncoder().encode(PEPPER),
      { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  }
  const firma = await crypto.subtle.sign('HMAC', CLAVE, new TextEncoder().encode(tipo + ':' + valor));
  return Array.from(new Uint8Array(firma)).map(b => b.toString(16).padStart(2, '0')).join('');
}

type Fila = { huella: string; tipo: 'tel' | 'email'; origen: 'lawang' | 'comprador' | 'ghl';
              cuenta_id: string; ref_id: string; fuente: string | null; alta: string | null };

async function huellasDe(base: Omit<Fila, 'huella' | 'tipo'>, tel: unknown, email: unknown, emails: unknown[] = [], tels: unknown[] = []) {
  const out: Fila[] = [];
  const vistos = new Set<string>();
  for (const [tipo, v] of [
    ...[tel, ...tels].map(x => ['tel', normTel(x)] as const),
    ...[email, ...emails].map(x => ['email', normEmail(x)] as const),
  ]) {
    if (!v || vistos.has(tipo + v)) continue;
    vistos.add(tipo + v);
    out.push({ ...base, tipo, huella: await hmac(tipo, v) });
  }
  return out;
}

const dormir = (ms: number) => new Promise(r => setTimeout(r, ms));

// GHL permite ~100 peticiones / 10 s por location: una página cada 150 ms y, ante un
// 429, esperar lo que diga Retry-After (o 10 s) y reintentar hasta 3 veces.
async function ghlBuscar(token: string, cuerpo: unknown): Promise<any> {
  for (let intento = 0; intento < 4; intento++) {
    const r = await fetch(GHL + '/contacts/search', {
      method: 'POST',
      headers: { Authorization: 'Bearer ' + token, Version: '2021-07-28',
                 Accept: 'application/json', 'Content-Type': 'application/json',
                 'User-Agent': 'Mozilla/5.0 (Lawang trazabilidad)' },
      body: JSON.stringify(cuerpo),
    });
    if (r.status === 429) { await dormir((Number(r.headers.get('retry-after')) || 10) * 1000); continue; }
    const txt = await r.text();
    if (!r.ok) {
      // Solo el código y el mensaje de GHL: nunca la cabecera ni el cuerpo enviado.
      let msg = ''; try { msg = JSON.parse(txt).message ?? ''; } catch { /* */ }
      throw new Error(`GHL ${r.status}${msg ? ': ' + String(msg).slice(0, 120) : ''}`);
    }
    return JSON.parse(txt);
  }
  throw new Error('GHL 429 persistente');
}

type Cuenta = { id: string; nombre: string; location_id: string; etiqueta: string; token: string };

async function contactosDe(c: Cuenta): Promise<{ filas: Fila[]; total: number }> {
  const filas: Fila[] = [];
  let searchAfter: unknown = undefined, total = 0, paginas = 0;
  while (paginas++ < TOPE_PAGINAS) {
    const d = await ghlBuscar(c.token, {
      locationId: c.location_id, pageLimit: PAGINA,
      filters: [{ field: 'tags', operator: 'contains', value: c.etiqueta }],
      ...(searchAfter ? { searchAfter } : {}),
    });
    const lote: any[] = d.contacts ?? [];
    total = d.total ?? total;
    for (const k of lote) {
      const fuente = [k.source, k.attributionSource?.campaign ?? k.attributionSource?.utmCampaign ??
                      k.attributionSource?.sessionSource].filter(Boolean).join(' · ') || null;
      filas.push(...await huellasDe(
        { origen: 'ghl', cuenta_id: c.id, ref_id: String(k.id), fuente, alta: k.dateAdded ?? null },
        k.phone, k.email, k.additionalEmails ?? [], (k.additionalPhones ?? []).map((p: any) => p?.phone ?? p)));
    }
    if (lote.length < PAGINA) break;
    searchAfter = lote[lote.length - 1].searchAfter;
    if (!searchAfter) break;
    await dormir(150);
  }
  return { filas, total };
}

// Fuentes propias: los leads de Meta (`leads`) y los COMPRADORES (`clients`). En la
// primera prueba (23-sep) los leads dieron 0 coincidencias y los compradores 23: la
// doble banda se juega negociando, no en el lead frío.
async function tabla(nombre: string, cols: string, fila: (r: any) => Promise<Fila[]>): Promise<Fila[]> {
  const out: Fila[] = [];
  for (let desde = 0; ; desde += 1000) {
    const { data, error } = await sb.from(nombre).select(cols).range(desde, desde + 999);
    if (error) throw new Error(nombre + ': ' + error.message);
    for (const r of data ?? []) out.push(...await fila(r));
    if ((data ?? []).length < 1000) break;
  }
  return out;
}
async function fuentesLawang(): Promise<Fila[]> {
  const leads = await tabla('leads', 'id, created_at, email, whatsapp, source', l => huellasDe(
    { origen: 'lawang', cuenta_id: '', ref_id: l.id, fuente: l.source ?? null, alta: l.created_at },
    l.whatsapp, l.email));
  const compradores = await tabla('clients', 'id, created_at, email, phone', k => huellasDe(
    { origen: 'comprador', cuenta_id: '', ref_id: k.id, fuente: 'Comprador', alta: k.created_at },
    k.phone, k.email));
  return [...leads, ...compradores];
}

// Se queda con las filas cuya huella aparece en 2+ funnels (Lawang cuenta como uno).
function soloCoincidencias(filas: Fila[]): Fila[] {
  const funnels = new Map<string, Set<string>>();
  for (const f of filas) {
    const k = f.origen === 'ghl' ? f.cuenta_id : 'lawang';   // lead y comprador: mismo funnel
    (funnels.get(f.huella) ?? funnels.set(f.huella, new Set()).get(f.huella)!).add(k);
  }
  return filas.filter(f => funnels.get(f.huella)!.size >= 2);
}

function personas(filas: Fila[]): number {
  // Aproximación: huellas distintas. Una persona con tel y email coincidentes cuenta 2.
  return new Set(filas.map(f => f.huella)).size;
}

async function pasada(cuentas: Cuenta[], guardar: boolean) {
  const lawang = await fuentesLawang();
  const todas: Fila[] = [...lawang];
  const resultados: Record<string, unknown> = {};
  let fallo = false;
  for (const c of cuentas) {
    try {
      const { filas, total } = await contactosDe(c);
      todas.push(...filas);
      const conLawang = soloCoincidencias([...lawang, ...filas]).filter(f => f.origen === 'ghl');
      resultados[c.id] = { ok: true, contactos: total, huellas_con_lawang: personas(conLawang),
                           en: new Date().toISOString() };
    } catch (e) {
      fallo = true;
      resultados[c.id] = { ok: false, error: String((e as Error).message).slice(0, 200), en: new Date().toISOString() };
    }
  }
  const coinc = soloCoincidencias(todas);
  let guardadas: number | null = null;
  if (guardar) {
    // Si una cuenta falló, se anota el error y se conserva la pasada anterior entera.
    const { data, error } = await sb.rpc('traza_guardar', { p_filas: fallo ? null : coinc, p_resultados: resultados });
    if (error) throw new Error('guardar: ' + error.message);
    guardadas = data;
  }
  return { cuentas: cuentas.length, huellas_lawang: lawang.length, coincidencias: personas(coinc),
           guardadas, resultados, conservada_pasada_anterior: guardar && fallo };
}

async function cuentas(solo: string | null): Promise<Cuenta[]> {
  const { data, error } = await sb.rpc('traza_cuentas_para_sync', { p_solo: solo });
  if (error) throw new Error('cuentas: ' + error.message);
  return data ?? [];
}

Deno.serve(async (req) => {
  const cors = corsFor(req);
  const json = (o: unknown, s = 200) => {
    if (s !== 200) console.error('trazabilidad-ghl ' + s + ': ' + JSON.stringify(o).slice(0, 300));
    return new Response(JSON.stringify(o), { status: s, headers: { ...cors, 'content-type': 'application/json' } });
  };
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'metodo' }, 405);
  if (PEPPER.length < 32) return json({ error: 'sin_pepper_configurado' }, 500);

  const body = await req.json().catch(() => ({}));
  try {
    // ── puerta 1: el cron ──
    const secretoCron = req.headers.get('x-cron-secret');
    if (secretoCron) {
      const { data: esperado } = await sb.rpc('cron_trazabilidad_secret');
      if (!esperado || secretoCron !== esperado) return json({ error: 'no_autorizado' }, 401);
      const cs = await cuentas(null);
      if (!cs.length) return json({ ok: true, nada: 'sin cuentas activas' });
      return json(await pasada(cs, true));
    }

    // ── puerta 2: un super_admin con sesión ──
    const jwt = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '');
    const { data: quien } = await sb.auth.getUser(jwt);
    if (!quien?.user) return json({ error: 'sin_sesion' }, 401);
    const { data: ficha } = await sb.from('usuarios').select('rol, activo').eq('user_id', quien.user.id).maybeSingle();
    if (!ficha?.activo || ficha.rol !== 'super_admin') return json({ error: 'sin_permiso' }, 403);

    const accion = String(body.accion ?? '');
    if (accion === 'alta' || accion === 'token') {
      const token = String(body.token ?? '').trim();
      if (!/^pit-[0-9a-f-]{20,}$/i.test(token)) return json({ error: 'El token debe empezar por pit-' }, 400);
      let loc = String(body.location_id ?? '').trim(), etiqueta = String(body.etiqueta ?? '').trim();
      if (accion === 'token') {
        const { data: c } = await sb.from('traza_cuentas').select('location_id, etiqueta').eq('id', body.cuenta_id).maybeSingle();
        if (!c) return json({ error: 'cuenta no existe' }, 404);
        loc = c.location_id; etiqueta = c.etiqueta;
      }
      // Antes de guardarlo: que abra ESA location y cuántos contactos trae la etiqueta.
      let total = 0;
      try {
        const d = await ghlBuscar(token, { locationId: loc, pageLimit: 1,
          filters: [{ field: 'tags', operator: 'contains', value: etiqueta }] });
        total = d.total ?? 0;
      } catch (e) { return json({ error: 'GHL no acepta el token con esa cuenta — ' + (e as Error).message }, 400); }
      if (accion === 'alta') {
        const { data: id, error } = await sb.rpc('traza_cuenta_alta', {
          p_manager: body.manager_id, p_location_id: loc, p_etiqueta: etiqueta, p_token: token, p_creado_por: quien.user.id });
        if (error) return json({ error: error.message }, 400);
        return json({ ok: true, id, contactos_con_etiqueta: total });
      }
      const { error } = await sb.rpc('traza_cuenta_token_cambiar', { p_id: body.cuenta_id, p_token: token });
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true, contactos_con_etiqueta: total });
    }
    if (accion === 'probar') {
      const cs = body.cuenta_id ? await cuentas(String(body.cuenta_id)) : [];
      if (!cs.length) return json({ error: 'cuenta no existe' }, 404);
      return json(await pasada(cs, false));
    }
    if (accion === 'sincronizar') {
      const cs = await cuentas(null);
      if (!cs.length) return json({ ok: true, nada: 'Ninguna cuenta activa' });
      return json(await pasada(cs, true));
    }
    return json({ error: 'accion desconocida' }, 400);
  } catch (e) {
    return json({ error: String((e as Error).message).slice(0, 300) }, 500);
  }
});
