// ficheros — los ficheros de la intranet los mueve el servidor, por CLASE (27-sep-2026, LAW-336 bloque 3; plan y
// revisión previa #126 en encargos/20260927_lawang_frontera_b3_modelos_deck.md).
//
// Nace genérica a propósito: en el bloque 4 entran documentación, obra, creatividades y gastos como clases nuevas
// de la tabla CLASES de abajo, sin otra edge por bucket. Mismo patrón que ficheros-kyc (bloque 2):
//   · la RUTA la decide esta función y la subida va por URL firmada, sin upsert;
//   · el PERMISO se comprueba ANTES de firmar la subida (y otra vez en la RPC de registro);
//   · al registrar se leen los primeros bytes del fichero subido: si no es lo que dice ser, se borra;
//   · registrar y borrar lo hacen RPC que solo ejecuta service_role (esta función), como el usuario de la sesión
//     (`_actua_como`): el permiso lo sigue decidiendo la base con es_admin/es_agente.
//
// Clases de hoy:
//   modelo_documento → bucket `modelos` (privado). Planos (Anexo Maestro del contrato de Construcción) solo admin;
//                      el resto, cualquiera del equipo. PDF o imagen.
//   deck_foto        → bucket `deck` (PÚBLICO: subir es publicar). Solo admin. Solo WebP (la pantalla recodifica
//                      para quitar el EXIF/GPS antes de subir). Al borrar: PRIMERO el objeto y después la fila — al
//                      revés, un fallo dejaría una imagen pública sin ninguna fila que diga que está ahí.
//
// Acciones (POST JSON, `accion` + `clase`):
//   subida_url {clase, ...ids, ext, tipo?}          → {path, token, content_type}
//   registra   {clase, ...ids, path, nombre, tipo?} → {id}
//   borra      {clase, id}                          → {ok}
//
// verify_jwt=false por el mismo motivo que ficheros-contrato (CORS del preflight); el JWT se valida a mano.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { TIPOS, bytesCuadran } from '../ficheros-kyc/firma.mjs';

const URL_SB = Deno.env.get('SUPABASE_URL')!;
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const ANON = Deno.env.get('SUPABASE_ANON_KEY')!;
const admin = createClient(URL_SB, SERVICE);
const TIPOS_: Record<string, string> = TIPOS;

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
const IMAGENES = ['.jpg', '.png', '.webp'];

type Usuario = ReturnType<typeof createClient>;
type Clase = {
  bucket: string;
  exts: string[];                           // lo que admite el bucket (intersección con TIPOS de firma.mjs)
  // ¿los bytes son lo que dice la extensión? (un PDF tiene que ser un PDF; una imagen, alguna imagen admitida)
  bytesOk: (ext: string, b: Uint8Array) => boolean;
  // ids del cuerpo → carpeta del servidor, comprobando el permiso ANTES de firmar la subida. null = sin permiso.
  carpeta: (u: Usuario, body: Record<string, unknown>) => Promise<string | { error: string; status: number }>;
  registra: (uid: string, body: Record<string, unknown>, path: string) => Promise<{ data: unknown; error: { message?: string; code?: string } | null }>;
  filaDe: (path: string) => Promise<boolean>;  // ¿alguien registró ya esta ruta? (entonces no se borra desde aquí)
  borraRpc: string;                            // (p_uid, p_id, p_solo_comprobar) → path
};

const esAdmin = async (u: Usuario) => (await u.rpc('es_admin')).data === true;

const CLASES: Record<string, Clase> = {
  modelo_documento: {
    bucket: 'modelos',
    exts: ['.pdf', '.jpg', '.jpeg', '.png', '.webp'],
    bytesOk: (ext, b) => ext === '.pdf' ? bytesCuadran('.pdf', b) : IMAGENES.some((e) => bytesCuadran(e, b)),
    carpeta: async (u, body) => {
      const modelo = String(body.modelo_id ?? '');
      if (!esUuid(modelo)) return { error: 'modelo_invalido', status: 400 };
      const tipo = String(body.tipo ?? 'otro');
      if (!['plano', 'calidades', 'ficha', 'render', 'otro'].includes(tipo)) return { error: 'tipo_de_documento_invalido', status: 400 };
      if (tipo === 'plano' && !(await esAdmin(u))) return { error: 'plano_solo_admin', status: 403 };
      const { data, error } = await u.from('modelos').select('id').eq('id', modelo).maybeSingle();
      if (error || !data) return { error: 'modelo_no_visible', status: 403 };
      return modelo + '/';
    },
    registra: (uid, body, path) => admin.rpc('modelo_documento_registra', {
      p_uid: uid, p_modelo: String(body.modelo_id ?? ''), p_path: path,
      p_nombre: String(body.nombre ?? '').slice(0, 300), p_tipo: String(body.tipo ?? 'otro'),
      p_techo_clave: body.techo_clave == null ? null : String(body.techo_clave),
    }),
    filaDe: async (path) => !!(await admin.from('modelo_documentos').select('id').eq('path', path).maybeSingle()).data,
    borraRpc: 'modelo_documento_borra',
  },
  deck_foto: {
    bucket: 'deck',
    exts: ['.webp'],
    bytesOk: (ext, b) => ext === '.webp' && bytesCuadran('.webp', b),
    carpeta: async (u, body) => {
      const ambito = String(body.ambito ?? '');
      const ref = String(body.ref_id ?? '');
      if (!['proyecto', 'modelo'].includes(ambito) || !esUuid(ref)) return { error: 'destino_invalido', status: 400 };
      if (!(await esAdmin(u))) return { error: 'solo_admin', status: 403 };
      const { data, error } = await u.from(ambito === 'modelo' ? 'modelos' : 'proyectos').select('id').eq('id', ref).maybeSingle();
      if (error || !data) return { error: 'destino_no_visible', status: 403 };
      return ambito + '/' + ref + '/';
    },
    registra: (uid, body, path) => admin.rpc('deck_foto_registra', {
      p_uid: uid, p_ambito: String(body.ambito ?? ''), p_ref: String(body.ref_id ?? ''), p_path: path,
      p_nombre: String(body.nombre ?? '').slice(0, 300),
    }),
    filaDe: async (path) => !!(await admin.from('deck_fotos').select('id').eq('path', path).maybeSingle()).data,
    borraRpc: 'deck_foto_borra',
  },
};

// Solo los primeros bytes, sin caché (la CDN de Storage puede servir una versión vieja ~60 s).
async function cabecera(bucket: string, path: string): Promise<Uint8Array | null> {
  const r = await fetch(`${URL_SB}/storage/v1/object/authenticated/${bucket}/${path}?v=${crypto.randomUUID()}`, {
    headers: { Authorization: 'Bearer ' + SERVICE, apikey: SERVICE, 'cache-control': 'no-cache', Range: 'bytes=0-15' },
  });
  if (!r.ok) return null;
  return new Uint8Array(await r.arrayBuffer()).subarray(0, 16);
}

Deno.serve(async (req) => {
  const cors = corsFor(req);
  const json = (o: unknown, s = 200) => {
    if (s !== 200) console.error('ficheros ' + s + ': ' + JSON.stringify(o));
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

    const body = (await req.json().catch(() => ({}))) as Record<string, unknown>;
    const accion = String(body.accion ?? '');
    const clase = CLASES[String(body.clase ?? '')];
    if (!clase) return json({ ok: false, error: 'clase_desconocida' }, 400);
    const errRpc = (e: { message?: string; code?: string } | null) =>
      json({ ok: false, error: e?.message ?? 'error', code: e?.code }, e?.code === '42501' ? 403 : 400);

    // ── borrar: permiso y ruta de la base → objeto → fila ────────────────
    if (accion === 'borra') {
      const id = String(body.id ?? '');
      if (!esUuid(id)) return json({ ok: false, error: 'id_invalido' }, 400);
      const { data: path, error: e1 } = await admin.rpc(clase.borraRpc, { p_uid: quien.user.id, p_id: id, p_solo_comprobar: true });
      if (e1) return errRpc(e1);
      if (typeof path === 'string' && path) {
        const { error: eRm } = await admin.storage.from(clase.bucket).remove([path]);
        if (eRm) return json({ ok: false, error: 'fichero_no_borrado' }, 500);
      }
      const { error: e2 } = await admin.rpc(clase.borraRpc, { p_uid: quien.user.id, p_id: id, p_solo_comprobar: false });
      if (e2) return json({ ok: false, error: 'fila_no_borrada', code: e2.code }, 500);
      return json({ ok: true });
    }

    // ── preparar la subida ───────────────────────────────────────────────
    if (accion === 'subida_url') {
      const ext = String(body.ext ?? '').toLowerCase();
      if (!clase.exts.includes(ext) || !TIPOS_[ext]) return json({ ok: false, error: 'tipo_de_fichero_no_admitido' }, 400);
      const carpeta = await clase.carpeta(usuario, body);
      if (typeof carpeta !== 'string') return json({ ok: false, error: carpeta.error }, carpeta.status);
      const path = `${carpeta}${crypto.randomUUID()}${ext}`;
      const { data, error } = await admin.storage.from(clase.bucket).createSignedUploadUrl(path);
      if (error || !data) return json({ ok: false, error: 'no_se_pudo_preparar_la_subida' }, 500);
      return json({ ok: true, path, token: data.token, content_type: TIPOS_[ext], bucket: clase.bucket });
    }

    // ── registrar lo subido ──────────────────────────────────────────────
    if (accion === 'registra') {
      const carpeta = await clase.carpeta(usuario, body);
      if (typeof carpeta !== 'string') return json({ ok: false, error: carpeta.error }, carpeta.status);
      const path = String(body.path ?? '');
      const m = new RegExp('^' + carpeta.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '[0-9a-f-]{36}(\\.[a-z]+)$').exec(path);
      if (!m || !clase.exts.includes(m[1])) return json({ ok: false, error: 'ruta_invalida' }, 400);
      const quita = async () => { if (!(await clase.filaDe(path))) await admin.storage.from(clase.bucket).remove([path]); };
      const cab = await cabecera(clase.bucket, path);
      if (!cab) return json({ ok: false, error: 'el_fichero_no_ha_llegado' }, 409);
      if (!clase.bytesOk(m[1], cab)) {
        await quita();
        return json({ ok: false, error: 'el_fichero_no_es_lo_que_dice_ser' }, 400);
      }
      const { data: id, error } = await clase.registra(quien.user.id, body, path);
      if (error) {
        // lo subido y no registrado no se queda suelto en el bucket (en `deck`, además, sería público)
        await quita();
        return errRpc(error);
      }
      return json({ ok: true, id });
    }

    return json({ ok: false, error: 'accion_desconocida' }, 400);
  } catch (e) {
    console.error('ficheros error interno: ' + String((e as Error)?.stack ?? e));
    return json({ ok: false, error: 'error_interno' }, 500);
  }
});
