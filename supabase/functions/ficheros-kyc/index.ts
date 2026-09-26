// ficheros-kyc — los ficheros KYC de los compradores (pasaportes, NPWP, prueba de fondos…) los mueve el
// servidor (27-sep-2026, LAW-336 bloque 2; plan y revisión previa #125 en
// encargos/20260927_lawang_frontera_b2_compradores_kyc.md).
//
// Hasta hoy el navegador subía al bucket con la ruta que él elegía, registraba la fila en `documents` con
// la ruta que quisiera (así un agente podía apuntar su comprador al pasaporte de otro y leerlo) y borraba
// cualquier fichero del bucket. Ahora:
//   · la RUTA la decide esta función (`<client_id>/<uuid>.<ext>`) y la subida va por URL firmada, sin upsert;
//   · al registrar se leen los primeros bytes del fichero subido: si no es lo que dice ser, o no se puede
//     registrar, se borra; el registro solo lo hace esta función (la RPC no la llama el navegador);
//   · el permiso lo decide la base con la SESIÓN del usuario (RPC/RLS); el service role solo mueve bytes.
//
// Acciones (POST JSON, `accion`):
//   subida_url      {client_id, ext}                        → {path, token, content_type}
//   registra        {client_id, path, doc_type, caduca_el}  → {id}
//   retira          {document_id, motivo?}                  → {conservado, kyc_vuelve_a_revision}
//   borra_comprador {client_id}                             → resultado de borrar_comprador + ficheros quitados
//   limpia_comprador {client_id}                            → {borrados}  reintento, ficha ya borrada
//
// verify_jwt=false por el mismo motivo que ficheros-contrato (CORS del preflight); el JWT se valida a mano.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const URL_SB = Deno.env.get('SUPABASE_URL')!;
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const ANON = Deno.env.get('SUPABASE_ANON_KEY')!;
const admin = createClient(URL_SB, SERVICE);
const BUCKET = 'kyc';

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
// Tipos admitidos y comprobación de bytes: firma.mjs (función pura, con su test).
import { TIPOS, bytesCuadran } from './firma.mjs';
const TIPOS_: Record<string, string> = TIPOS;
// Solo los primeros bytes, sin caché (la CDN de Storage puede servir una versión vieja ~60 s).
async function cabecera(path: string): Promise<Uint8Array | null> {
  const r = await fetch(`${URL_SB}/storage/v1/object/authenticated/${BUCKET}/${path}?v=${crypto.randomUUID()}`, {
    headers: { Authorization: 'Bearer ' + SERVICE, apikey: SERVICE, 'cache-control': 'no-cache', Range: 'bytes=0-15' },
  });
  if (!r.ok) return null;
  return new Uint8Array(await r.arrayBuffer()).subarray(0, 16);
}

Deno.serve(async (req) => {
  const cors = corsFor(req);
  const json = (o: unknown, s = 200) => {
    if (s !== 200) console.error('ficheros-kyc ' + s + ': ' + JSON.stringify(o));
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
    const errRpc = (e: { message?: string; code?: string } | null) =>
      json({ ok: false, error: e?.message ?? 'error', code: e?.code }, e?.code === '42501' ? 403 : 400);

    // ── retirar un documento ─────────────────────────────────────────────
    if (accion === 'retira') {
      const docId = String(body.document_id ?? '');
      if (!esUuid(docId)) return json({ ok: false, error: 'documento_invalido' }, 400);
      const { data: r, error } = await usuario.rpc('documento_kyc_retira', {
        p_id: docId, p_motivo: body.motivo == null ? null : String(body.motivo),
      });
      if (error) return errRpc(error);
      const res = r as { conservado: boolean; borrar_fichero: boolean; path: string | null; kyc_vuelve_a_revision: boolean };
      let aviso: string | null = null;
      if (res.borrar_fichero && res.path) {
        const { error: eRm } = await admin.storage.from(BUCKET).remove([res.path]);
        if (eRm) aviso = 'fichero_no_borrado';
      }
      return json({ ok: true, conservado: res.conservado, kyc_vuelve_a_revision: res.kyc_vuelve_a_revision, aviso });
    }

    const clientId = String(body.client_id ?? '');
    if (!esUuid(clientId)) return json({ ok: false, error: 'comprador_invalido' }, 400);

    // ── borrar una ficha duplicada y sus ficheros ────────────────────────
    // La RPC (super admin dentro) devuelve las rutas: se borran servidor a servidor, nunca las que mande
    // la pantalla.
    if (accion === 'borra_comprador') {
      const { data: r, error } = await usuario.rpc('borrar_comprador', { p_client_id: clientId });
      if (error) return errRpc(error);
      const res = r as { rutas_kyc?: string[] } & Record<string, unknown>;
      const rutas = (res.rutas_kyc ?? []).filter((p) => typeof p === 'string');
      let fallidos = 0;
      if (rutas.length) {
        const { error: eRm } = await admin.storage.from(BUCKET).remove(rutas);
        if (eRm) fallidos = rutas.length;
      }
      return json({ ok: true, ...res, rutas_kyc: undefined, ficheros_quitados: rutas.length - fallidos, ficheros_pendientes: fallidos });
    }

    // ── reintento de limpieza (ficha ya borrada) ─────────────────────────
    if (accion === 'limpia_comprador') {
      const { data: sa } = await usuario.rpc('es_super_admin');
      if (sa !== true) return json({ ok: false, error: 'solo_super_admin' }, 403);
      const { data: rutas, error } = await admin.rpc('kyc_sueltos_de', { p_client: clientId });
      if (error) return json({ ok: false, error: 'no_se_pudo_comprobar' }, 500);
      const lista = ((rutas ?? []) as unknown[]).map(String).filter((p) => p.startsWith(clientId + '/'));
      if (lista.length) {
        const { error: eRm } = await admin.storage.from(BUCKET).remove(lista);
        if (eRm) return json({ ok: false, error: 'no_se_pudo_borrar' }, 500);
      }
      return json({ ok: true, borrados: lista.length });
    }

    // Para subir y registrar hay que VER al comprador (RLS de clients con la sesión del usuario).
    const { data: c, error: eC } = await usuario.from('clients').select('id').eq('id', clientId).maybeSingle();
    if (eC || !c) return json({ ok: false, error: 'comprador_no_visible' }, 403);

    // ── preparar la subida ───────────────────────────────────────────────
    if (accion === 'subida_url') {
      const ext = String(body.ext ?? '').toLowerCase();
      const tipo = TIPOS_[ext];
      if (!tipo) return json({ ok: false, error: 'tipo_de_fichero_no_admitido' }, 400);
      const path = `${clientId}/${crypto.randomUUID()}${ext}`;
      const { data, error } = await admin.storage.from(BUCKET).createSignedUploadUrl(path);
      if (error || !data) return json({ ok: false, error: 'no_se_pudo_preparar_la_subida' }, 500);
      return json({ ok: true, path, token: data.token, content_type: tipo });
    }

    // ── registrar lo subido ──────────────────────────────────────────────
    if (accion === 'registra') {
      const path = String(body.path ?? '');
      const m = new RegExp('^' + clientId + '/[0-9a-f-]{36}(\\.[a-z]+)$', 'i').exec(path);
      if (!m || !TIPOS_[m[1].toLowerCase()]) return json({ ok: false, error: 'ruta_invalida' }, 400);
      const cab = await cabecera(path);
      if (!cab) return json({ ok: false, error: 'el_fichero_no_ha_llegado' }, 409);
      if (!bytesCuadran(m[1].toLowerCase(), cab)) {
        // Solo se borra si nadie lo registró ya (una ruta registrada no se toca desde aquí).
        const { data: ya } = await admin.from('documents').select('id').eq('storage_path', path).maybeSingle();
        if (!ya) await admin.storage.from(BUCKET).remove([path]);
        return json({ ok: false, error: 'el_fichero_no_es_lo_que_dice_ser' }, 400);
      }
      const caduca = body.caduca_el ? String(body.caduca_el) : null;
      if (caduca && !/^\d{4}-\d{2}-\d{2}$/.test(caduca)) return json({ ok: false, error: 'fecha_de_caducidad_invalida' }, 400);
      // Con service role y el usuario de la sesión: la RPC ya no la puede llamar el navegador, así que
      // nadie registra un fichero sin pasar por la comprobación de bytes de aquí arriba. El permiso lo
      // sigue decidiendo la base, como ese usuario.
      const { data: id, error } = await admin.rpc('documento_kyc_registra', {
        p_uid: quien.user.id, p_client: clientId, p_path: path, p_tipo: String(body.doc_type ?? ''), p_caduca: caduca,
      });
      if (error) {
        // lo subido y no registrado no se queda suelto en el bucket
        const { data: ya } = await admin.from('documents').select('id').eq('storage_path', path).maybeSingle();
        if (!ya) await admin.storage.from(BUCKET).remove([path]);
        return errRpc(error);
      }
      return json({ ok: true, id });
    }

    return json({ ok: false, error: 'accion_desconocida' }, 400);
  } catch (e) {
    return json({ ok: false, error: String((e as Error)?.message ?? e) }, 500);
  }
});
