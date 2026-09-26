// ficheros-contrato — los ficheros de contratos y cobros los mueve el servidor (26-sep-2026,
// LAW-336 pieza 5, pasos C y D; plan en encargos/20260926_lawang_frontera_f5_contratos.md).
//
// Norma del owner: «no te creas NADA del front-end». Hasta hoy el navegador subía al bucket
// con la ruta que él elegía, calculaba él el hash del PDF firmado a mano, generaba él el token
// de firma y borraba él los borradores al borrar una operación. Ahora:
//   · la RUTA la decide esta función y la subida va por URL firmada (sirve para cualquier
//     tamaño: el fichero no pasa por aquí, va directo al bucket);
//   · el HASH lo calcula esta función leyendo el fichero ya subido, nunca la pantalla;
//   · el TOKEN de firma lo genera la base (contrato_envia_firma) y aquí solo se pasa el hash
//     del documento que se va a firmar, que firma-submit comprueba antes de estampar;
//   · el permiso se decide con la SESIÓN del usuario (RPC/RLS), el service role solo mueve
//     bytes y hace el cierre que un agente no puede hacer por su cuenta.
//
// Acciones (POST JSON, `accion`):
//   justificante_url {ext}            → {path, token}  subida de un justificante de cobro
//   snapshot_url     {contrato_id}    → {path, token}  documento a firmar (solo si nadie firmó aún)
//   envia_firma      {contrato_id, nombre, email, rol, orden} → {link, anulados}
//   pdf_manual_url   {contrato_id}    → {path, token}  PDF firmado a mano
//   cierra_manual    {contrato_id}    → {path, hash, anulados}
//   limpia_borradores {}              → {borrados}     borradores de firma de contratos que ya no existen
//
// verify_jwt=false por el mismo motivo que send-contract-email (CORS del preflight); el JWT
// se valida a mano.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const URL_SB = Deno.env.get('SUPABASE_URL')!;
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const ANON = Deno.env.get('SUPABASE_ANON_KEY')!;
const admin = createClient(URL_SB, SERVICE);
const BUCKET_FIRMAS = 'contratos-firmados';

const ORIGENES = [
  'https://lawangproperties.com',
  'https://www.lawangproperties.com',
  'https://sumbahills.lawangproperties.com',
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

const esUuid = (s: string) => /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s);
async function sha256hex(s: string | Uint8Array): Promise<string> {
  const b = await crypto.subtle.digest('SHA-256', typeof s === 'string' ? new TextEncoder().encode(s) : s);
  return [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, '0')).join('');
}
// extensiones que admite un justificante (lo mismo que suben hoy: transferencias en PDF o foto)
const EXT_JUSTIF = ['.pdf', '.jpg', '.jpeg', '.png', '.webp', '.heic', '.heif'];
// Lee un objeto SIN caché: la CDN de Storage puede servir la versión anterior hasta ~60 s tras una
// reescritura, y un hash calculado sobre esa versión rompería el enlace (consulta C+D, Desarrollo).
async function leeFresco(bucket: string, path: string): Promise<Response> {
  return await fetch(`${URL_SB}/storage/v1/object/authenticated/${bucket}/${path}?v=${crypto.randomUUID()}`,
    { headers: { Authorization: 'Bearer ' + SERVICE, apikey: SERVICE, 'cache-control': 'no-cache' } });
}

Deno.serve(async (req) => {
  const cors = corsFor(req);
  const json = (o: unknown, s = 200) => {
    if (s !== 200) console.error('ficheros-contrato ' + s + ': ' + JSON.stringify(o));
    return new Response(JSON.stringify(o), { status: s, headers: { ...cors, 'content-type': 'application/json' } });
  };
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ ok: false, error: 'metodo' }, 405);

  try {
    const jwt = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '');
    if (!jwt) return json({ ok: false, error: 'sin_sesion' }, 401);
    const { data: quien, error: eUser } = await admin.auth.getUser(jwt);
    if (eUser || !quien?.user) return json({ ok: false, error: 'sesion_invalida' }, 401);
    const usuario = createClient(URL_SB, ANON, {
      global: { headers: { Authorization: 'Bearer ' + jwt } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    // Solo el equipo: un comprador del portal también tiene sesión de Supabase.
    const { data: esAgente, error: eAg } = await usuario.rpc('es_agente');
    if (eAg || esAgente !== true) return json({ ok: false, error: 'solo_equipo' }, 403);

    const body = await req.json().catch(() => ({}));
    const accion = String(body.accion ?? '');
    const contratoId = String(body.contrato_id ?? '');
    const errRpc = (e: { message?: string; code?: string } | null) =>
      json({ ok: false, error: e?.message ?? 'error' }, e?.code === '42501' ? 403 : 400);

    // ── justificante de cobro ────────────────────────────────────────────
    if (accion === 'justificante_url') {
      const ext = String(body.ext ?? '').toLowerCase();
      if (!EXT_JUSTIF.includes(ext)) return json({ ok: false, error: 'tipo_de_fichero_no_admitido' }, 400);
      const path = crypto.randomUUID() + ext;
      const { data, error } = await admin.storage.from('justificantes').createSignedUploadUrl(path);
      if (error || !data) return json({ ok: false, error: 'no_se_pudo_preparar_la_subida' }, 500);
      return json({ ok: true, path, token: data.token });
    }

    // ── borradores de firma huérfanos ────────────────────────────────────
    // Tras borrar una operación sus contratos ya no existen: se borran SOLO los
    // `pendientes/<id>.html` cuyo contrato no existe. No recibe rutas de la pantalla, así
    // que no puede borrar nada vivo. El PDF firmado no vive en `pendientes/`: nunca se toca.
    if (accion === 'limpia_borradores') {
      const ids: string[] = [];
      for (let off = 0; ; off += 1000) {
        const { data, error } = await admin.storage.from(BUCKET_FIRMAS).list('pendientes', { limit: 1000, offset: off });
        if (error) return json({ ok: false, error: 'no_se_pudo_listar' }, 500);
        (data ?? []).forEach((o) => { const m = /^([0-9a-f-]{36})\.html$/i.exec(o.name); if (m) ids.push(m[1]); });
        if (!data || data.length < 1000) break;
      }
      if (!ids.length) return json({ ok: true, borrados: 0 });
      const vivos = new Set<string>();
      for (let i = 0; i < ids.length; i += 200) {
        const { data, error } = await admin.from('contratos').select('id').in('id', ids.slice(i, i + 200));
        if (error) return json({ ok: false, error: 'no_se_pudo_comprobar' }, 500);
        (data ?? []).forEach((r) => vivos.add(r.id));
      }
      const huerfanos = ids.filter((id) => !vivos.has(id)).map((id) => `pendientes/${id}.html`);
      if (huerfanos.length) {
        const { error } = await admin.storage.from(BUCKET_FIRMAS).remove(huerfanos);
        if (error) return json({ ok: false, error: 'no_se_pudo_borrar' }, 500);
      }
      return json({ ok: true, borrados: huerfanos.length });
    }

    if (!esUuid(contratoId)) return json({ ok: false, error: 'contrato_invalido' }, 400);

    // ── documento a firmar: subida y envío ───────────────────────────────
    if (accion === 'snapshot_url' || accion === 'envia_firma') {
      // permiso + estado con la sesión del usuario (raise si no puede)
      const { data: est, error: eEst } = await usuario.rpc('contrato_firma_estado', { p_contrato: contratoId });
      if (eEst) return errRpc(eEst);
      const path = `pendientes/${contratoId}.html`;
      if (accion === 'snapshot_url') {
        // una vez que alguien firmó, el documento lo reescribe solo firma-submit (lleva sus firmas)
        if ((est as { firmados: number }).firmados > 0) return json({ ok: false, error: 'ya_hay_firmas' }, 409);
        const { data, error } = await admin.storage.from(BUCKET_FIRMAS).createSignedUploadUrl(path, { upsert: true });
        if (error || !data) return json({ ok: false, error: 'no_se_pudo_preparar_la_subida' }, 500);
        return json({ ok: true, path, token: data.token });
      }
      // envia_firma: el hash del documento lo calcula el servidor sobre lo que hay en el bucket
      const rDoc = await leeFresco(BUCKET_FIRMAS, path);
      if (!rDoc.ok) return json({ ok: false, error: 'falta_el_documento_a_firmar' }, 409);
      const hash = await sha256hex(await rDoc.text());
      const { data: r, error: eEnv } = await usuario.rpc('contrato_envia_firma', {
        p_contrato: contratoId,
        p_nombre: String(body.nombre ?? ''), p_email: String(body.email ?? ''),
        p_rol: String(body.rol ?? ''), p_orden: Number(body.orden ?? 1),
        p_snapshot_hash: hash,
      });
      if (eEnv) return errRpc(eEnv);
      return json({ ok: true, ...(r as Record<string, unknown>) });
    }

    // ── PDF firmado a mano ───────────────────────────────────────────────
    if (accion === 'pdf_manual_url' || accion === 'cierra_manual') {
      const { data: c, error: eC } = await usuario.from('contratos')
        .select('numero, bloqueado, pdf_firmado_path').eq('id', contratoId).maybeSingle();
      if (eC || !c) return json({ ok: false, error: 'contrato_no_visible' }, 403);
      if (c.bloqueado) return json({ ok: false, error: 'contrato_ya_cerrado' }, 409);
      // Lo firmado no se pisa nunca (Legal #120): si el contrato ya tuvo un PDF firmado
      // (lo desbloqueó un super admin), no se sube otro encima en la misma ruta.
      if (c.pdf_firmado_path) return json({ ok: false, error: 'ya_tiene_pdf_firmado' }, 409);
      const path = `${c.numero}_manual.pdf`;
      const { data: puede, error: eP } = await usuario.rpc('agente_escribe_fichero_contrato', { p_name: path });
      if (eP || puede !== true) return json({ ok: false, error: 'sin_permiso_sobre_este_contrato' }, 403);
      if (accion === 'pdf_manual_url') {
        // upsert: el contrato aún no está cerrado ni tuvo PDF firmado, así que lo que hubiera
        // en esa ruta es un intento anterior que no llegó a cerrar
        const { data, error } = await admin.storage.from(BUCKET_FIRMAS).createSignedUploadUrl(path, { upsert: true });
        if (error || !data) return json({ ok: false, error: 'no_se_pudo_preparar_la_subida' }, 500);
        return json({ ok: true, path, token: data.token });
      }
      const rPdf = await leeFresco(BUCKET_FIRMAS, path);
      if (!rPdf.ok) return json({ ok: false, error: 'falta_el_pdf' }, 409);
      const bytes = new Uint8Array(await rPdf.arrayBuffer());
      if (bytes.length < 5 || new TextDecoder().decode(bytes.subarray(0, 5)) !== '%PDF-')
        return json({ ok: false, error: 'no_es_un_pdf' }, 400);
      const hash = await sha256hex(bytes);
      const { data: anulados, error: eCi } = await admin.rpc('contrato_cierra_manual', {
        p_id: contratoId, p_path: path, p_hash: hash, p_actor: quien.user.email ?? null,
      });
      if (eCi) return errRpc(eCi);
      return json({ ok: true, path, hash, anulados });
    }

    return json({ ok: false, error: 'accion_desconocida' }, 400);
  } catch (e) {
    return json({ ok: false, error: String((e as Error)?.message ?? e) }, 500);
  }
});
