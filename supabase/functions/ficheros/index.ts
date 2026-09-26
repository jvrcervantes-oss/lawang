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
// Bloque 4 (27-sep-2026, LAW-336; revisión previa #127 en encargos/20260927_lawang_frontera_b4_b5_resto.md):
//   documento_proyecto → bucket `documentacion` (privado). Agente con la herramienta «documentacion» y el proyecto
//                        entre los suyos. PDF, imagen, Office, CSV, CAD (dwg/dxf) o ZIP; ruta
//                        `proyectos/<proyecto_id>/<uuid>.<ext>` (la que ya usaban las pantallas). Borrar: super admin.
//   obra_foto          → bucket `obra` (privado). Herramienta «obra» y la parcela en un proyecto suyo. Imagen.
//   gasto_justificante → bucket `gastos` (privado). Admin + herramienta «gastos», gasto no anulado. PDF o imagen.
//                        Sin borrado (no lo había).
//   creatividad        → bucket `creatividades` (privado). NO usa uuid: los CHECK de la tabla exigen
//                        `<id>/{estado|pieza|portada}-<n>.<ext>`; el servidor la compone por `rol`. El `estado` es un
//                        JSON (puede llevar imágenes data: dentro; el mayor medido el 27-sep pesa 8,7 MB, el bucket
//                        admite 15): se DESCARGA entero y se valida con JSON.parse + objeto, no con bytes mágicos.
//                        No hay `registra` por fichero: la acción `guarda` valida lo subido y guarda metadatos,
//                        ficheros, fotos y modelos en UNA transacción (creatividad_guarda).
//
// Acciones (POST JSON, `accion` + `clase`):
//   subida_url {clase, ...ids, ext, tipo?}          → {path, token, content_type}   (creatividad: + creatividad_id)
//   registra   {clase, ...ids, path, nombre, tipo?} → {id}
//   borra      {clase, id}                          → {ok}
//   guarda     {clase:'creatividad', creatividad_id, tipo, datos, estado_path, path?, portada_path?, foto_ids?, modelo_ids?} → {fila}
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
  exts: string[];                           // lo que admite el bucket (intersección con TIPOS de firma.mjs o `tipos`)
  tipos?: Record<string, string>;           // content-type por extensión, si la clase admite más que firma.mjs
  // ¿los bytes son lo que dice la extensión? (un PDF tiene que ser un PDF; una imagen, alguna imagen admitida)
  bytesOk: (ext: string, b: Uint8Array) => boolean;
  // ids del cuerpo → carpeta del servidor, comprobando el permiso ANTES de firmar la subida. null = sin permiso.
  carpeta: (u: Usuario, body: Record<string, unknown>) => Promise<string | { error: string; status: number }>;
  registra?: (uid: string, body: Record<string, unknown>, path: string) => Promise<{ data: unknown; error: { message?: string; code?: string } | null }>;
  filaDe: (path: string) => Promise<boolean>;  // ¿alguien registró ya esta ruta? (entonces no se borra desde aquí)
  borraRpc?: string;                           // (p_uid, p_id, p_solo_comprobar) → path. Sin él, la clase no borra.
};

const esAdmin = async (u: Usuario) => (await u.rpc('es_admin')).data === true;
const rpcSi = async (u: Usuario, fn: string, args: Record<string, unknown>) => (await u.rpc(fn, args)).data === true;
const IMAGEN_OK = (_ext: string, b: Uint8Array) => IMAGENES.some((e) => bytesCuadran(e, b));

// Documentación: además de PDF e imagen, Office, CSV, CAD y ZIP (la lista que ya ofrecía la v4). El tipo lo pone
// el servidor; ninguno es algo que un navegador ejecute (html, svg, js).
const TIPOS_DOC: Record<string, string> = {
  '.pdf': 'application/pdf', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png', '.webp': 'image/webp',
  '.doc': 'application/msword', '.xls': 'application/vnd.ms-excel', '.ppt': 'application/vnd.ms-powerpoint',
  '.docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  '.xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  '.pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  '.csv': 'text/csv', '.dwg': 'image/vnd.dwg', '.dxf': 'image/vnd.dxf', '.zip': 'application/zip',
};
const asc = (b: Uint8Array, i: number, n: number) => String.fromCharCode(...b.subarray(i, i + n));
const esTexto = (b: Uint8Array) => !b.some((x) => x === 0) && asc(b, 0, 1) !== '<';
function bytesDoc(ext: string, b: Uint8Array): boolean {
  if (!b || b.length < 4) return false;
  switch (ext) {
    case '.pdf': return bytesCuadran('.pdf', b);
    case '.jpg': case '.jpeg': case '.png': case '.webp': return IMAGEN_OK(ext, b);
    // Office moderno y ZIP: contenedor ZIP (PK\x03\x04); Office 97-2003: OLE (D0 CF 11 E0)
    case '.docx': case '.xlsx': case '.pptx': case '.zip': return b[0] === 0x50 && b[1] === 0x4b && b[2] === 0x03 && b[3] === 0x04;
    case '.doc': case '.xls': case '.ppt': return b[0] === 0xd0 && b[1] === 0xcf && b[2] === 0x11 && b[3] === 0xe0;
    case '.dwg': return asc(b, 0, 4) === 'AC10';
    // texto sin bytes nulos que no empiece por «<» (que no sea un HTML con otra extensión)
    case '.csv': return esTexto(b);
    case '.dxf': return esTexto(b) || asc(b, 0, 16).startsWith('AutoCAD Binary');
    default: return false;
  }
}

// Creatividad: la ruta la compone el servidor por `rol` (convención de los CHECK de la tabla).
const ROLES_CREATIVIDAD: Record<string, { ext: string; tipo: string | null }> = {
  estado: { ext: '.json', tipo: null },      // cualquier tipo
  pieza: { ext: '.png', tipo: 'pieza' },     // la imagen de una pieza
  portada: { ext: '.png', tipo: 'dossier' }, // la miniatura de la portada de un dossier
};
const RE_CREATIVIDAD = /^([0-9a-f-]{36})\/(estado|pieza|portada)-([0-9]+)\.(json|png)$/;

// ¿Puede esta sesión escribir en ESA creatividad (o crear una del tipo pedido)? Mismas reglas que las policies de
// hoy: la herramienta del tipo y solo un borrador. La existencia se mira con service role (una fila que la sesión
// no ve no puede parecer «nueva»). Devuelve el tipo efectivo o el error.
async function permisoCreatividad(u: Usuario, id: string, tipoPedido: string): Promise<{ tipo: string } | { error: string; status: number }> {
  if (!esUuid(id)) return { error: 'creatividad_invalida', status: 400 };
  const { data: fila, error } = await admin.from('creatividades').select('tipo, estado').eq('id', id).maybeSingle();
  if (error) return { error: 'error_interno', status: 500 };
  const tipo = fila ? String(fila.tipo) : tipoPedido;
  if (!['pieza', 'dossier'].includes(tipo)) return { error: 'tipo_de_creatividad_invalido', status: 400 };
  if (!(await rpcSi(u, 'creatividad_puede_hacer', { p_tipo: tipo }))) {
    return { error: tipo === 'dossier' ? 'sin_permiso_dossier' : 'sin_permiso_creatividades', status: 403 };
  }
  if (fila && fila.estado !== 'borrador') return { error: 'creatividad_no_borrador', status: 409 };
  return { tipo };
}

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
  documento_proyecto: {
    bucket: 'documentacion',
    exts: Object.keys(TIPOS_DOC),
    tipos: TIPOS_DOC,
    bytesOk: bytesDoc,
    carpeta: async (u, body) => {
      const proyecto = String(body.proyecto_id ?? '');
      if (!esUuid(proyecto)) return { error: 'proyecto_invalido', status: 400 };
      if (!(await rpcSi(u, 'documento_proyecto_puede', { p_proyecto_id: proyecto }))) return { error: 'proyecto_no_permitido', status: 403 };
      return 'proyectos/' + proyecto + '/';
    },
    registra: (uid, body, path) => admin.rpc('documento_proyecto_registra', {
      p_uid: uid, p_proyecto: String(body.proyecto_id ?? ''), p_path: path,
      p_datos: (body.datos && typeof body.datos === 'object' && !Array.isArray(body.datos)) ? body.datos : {},
    }),
    filaDe: async (path) => !!(await admin.from('documentos_proyecto').select('id').eq('path', path).maybeSingle()).data,
    borraRpc: 'documento_proyecto_borra',
  },
  obra_foto: {
    bucket: 'obra',
    exts: ['.jpg', '.jpeg', '.png', '.webp'],
    bytesOk: IMAGEN_OK,
    carpeta: async (u, body) => {
      const unidad = String(body.unidad_id ?? '');
      if (!esUuid(unidad)) return { error: 'unidad_invalida', status: 400 };
      if (!(await rpcSi(u, 'obra_puede', { p_unidad: unidad }))) return { error: 'obra_no_permitida', status: 403 };
      return unidad + '/';
    },
    registra: (uid, body, path) => admin.rpc('obra_foto_registra', {
      p_uid: uid, p_unidad: String(body.unidad_id ?? ''), p_path: path,
      p_titulo: body.titulo == null ? null : String(body.titulo).slice(0, 300),
    }),
    filaDe: async (path) => !!(await admin.from('obra_fotos').select('id').eq('path', path).maybeSingle()).data,
    borraRpc: 'obra_foto_borra',
  },
  gasto_justificante: {
    bucket: 'gastos',
    exts: ['.pdf', '.jpg', '.jpeg', '.png', '.webp'],
    bytesOk: (ext, b) => ext === '.pdf' ? bytesCuadran('.pdf', b) : IMAGEN_OK(ext, b),
    carpeta: async (u, body) => {
      const gasto = String(body.gasto_id ?? '');
      if (!esUuid(gasto)) return { error: 'gasto_invalido', status: 400 };
      // la lectura de `gastos` ya exige admin + herramienta gastos (RLS): si no la ve, no es suya
      const { data, error } = await u.from('gastos').select('id, estado').eq('id', gasto).maybeSingle();
      if (error || !data) return { error: 'gasto_no_visible', status: 403 };
      if (data.estado === 'anulado') return { error: 'gasto_anulado', status: 409 };
      return gasto + '/';
    },
    registra: (uid, body, path) => admin.rpc('gasto_justificante_registra', {
      p_uid: uid, p_gasto: String(body.gasto_id ?? ''), p_path: path, p_nombre: String(body.nombre ?? '').slice(0, 300),
    }),
    filaDe: async (path) => !!(await admin.from('gastos').select('id').contains('justificantes', [{ path }]).maybeSingle()).data,
  },
  creatividad: {
    bucket: 'creatividades',
    exts: ['.json', '.png'],
    tipos: { '.json': 'application/json', '.png': 'image/png' },
    bytesOk: (ext, b) => ext === '.png' && bytesCuadran('.png', b),   // el .json se valida entero en `guarda`
    carpeta: async () => ({ error: 'accion_desconocida', status: 400 }), // tiene su propio camino (abajo)
    filaDe: async (path) => !!(await admin.from('creatividades').select('id')
      .or(`path.eq."${path}",estado_path.eq."${path}",portada_path.eq."${path}"`).limit(1).maybeSingle()).data,
  },
};

// ── creatividad: preparar una subida (la ruta la compone el servidor por `rol`) ─────────────────────────────────
async function subidaCreatividad(u: Usuario, body: Record<string, unknown>) {
  const rol = String(body.rol ?? '');
  const def = ROLES_CREATIVIDAD[rol];
  if (!def) return { error: 'rol_invalido', status: 400 } as const;
  // sin id = creatividad nueva: el id lo pone el servidor (y la fila solo nace en `guarda`, con su estado subido)
  const id = body.creatividad_id ? String(body.creatividad_id) : crypto.randomUUID();
  const p = await permisoCreatividad(u, id, String(body.tipo ?? ''));
  if ('error' in p) return p;
  if (def.tipo && def.tipo !== p.tipo) return { error: 'rol_invalido', status: 400 } as const;
  // `<n>` con milisegundos + un aleatorio: dos subidas del mismo rol no chocan (el bucket no admite sobrescribir)
  const path = `${id}/${rol}-${Date.now()}${Math.floor(Math.random() * 1000).toString().padStart(3, '0')}${def.ext}`;
  return { id, path, content_type: def.ext === '.json' ? 'application/json' : 'image/png' };
}

// ── creatividad: validar lo subido y guardar TODO en una transacción ────────────────────────────────────────────
async function guardaCreatividad(u: Usuario, uid: string, body: Record<string, unknown>) {
  const id = String(body.creatividad_id ?? '');
  const p = await permisoCreatividad(u, id, String(body.tipo ?? ''));
  if ('error' in p) return p;
  const rutas: Record<string, string | null> = {
    estado: body.estado_path ? String(body.estado_path) : null,
    pieza: body.path ? String(body.path) : null,
    portada: body.portada_path ? String(body.portada_path) : null,
  };
  if (!rutas.estado) return { error: 'falta_el_estado', status: 400 } as const;
  const nuevas = Object.values(rutas).filter((x): x is string => !!x);
  for (const [rol, ruta] of Object.entries(rutas)) {
    if (!ruta) continue;
    const m = RE_CREATIVIDAD.exec(ruta);
    if (!m || m[1] !== id || m[2] !== rol) return { error: 'ruta_invalida', status: 400 } as const;
  }
  // lo subido y no guardado no se queda suelto; nunca se quita algo que una fila ya usa
  const quita = async () => {
    const sueltas: string[] = [];
    for (const r of nuevas) if (!(await CLASES.creatividad.filaDe(r))) sueltas.push(r);
    if (sueltas.length) await admin.storage.from('creatividades').remove(sueltas);
  };
  // el estado: JSON entero, objeto (no array); las PNG: bytes de PNG
  const { data: blob, error: eDl } = await admin.storage.from('creatividades').download(rutas.estado!);
  if (eDl || !blob) return { error: 'el_fichero_no_ha_llegado', status: 409 } as const;
  let objeto: unknown = null;
  try { objeto = JSON.parse(await blob.text()); } catch { objeto = null; }
  if (!objeto || typeof objeto !== 'object' || Array.isArray(objeto)) { await quita(); return { error: 'estado_no_valido', status: 400 } as const; }
  for (const r of [rutas.pieza, rutas.portada]) {
    if (!r) continue;
    const cab = await cabecera('creatividades', r);
    if (!cab) return { error: 'el_fichero_no_ha_llegado', status: 409 } as const;
    if (!bytesCuadran('.png', cab)) { await quita(); return { error: 'el_fichero_no_es_lo_que_dice_ser', status: 400 } as const; }
  }
  const ids = (v: unknown) => Array.isArray(v) ? v.map(String).filter(esUuid) : null;
  const datos = (body.datos && typeof body.datos === 'object' && !Array.isArray(body.datos)) ? body.datos : {};
  const { data, error } = await admin.rpc('creatividad_guarda', {
    p_uid: uid, p_id: id, p_tipo: p.tipo, p_datos: datos, p_estado_path: rutas.estado,
    p_path: rutas.pieza, p_portada_path: rutas.portada, p_fotos: ids(body.foto_ids), p_modelos: ids(body.modelo_ids),
  });
  if (error) { await quita(); return { rpcError: error }; }
  return { fila: data };
}

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
      if (!clase.borraRpc) return json({ ok: false, error: 'accion_desconocida' }, 400);
      const id = String(body.id ?? '');
      if (!esUuid(id)) return json({ ok: false, error: 'id_invalido' }, 400);
      const { data: path, error: e1 } = await admin.rpc(clase.borraRpc!, { p_uid: quien.user.id, p_id: id, p_solo_comprobar: true });
      if (e1) return errRpc(e1);
      if (typeof path === 'string' && path) {
        const { error: eRm } = await admin.storage.from(clase.bucket).remove([path]);
        if (eRm) return json({ ok: false, error: 'fichero_no_borrado' }, 500);
      }
      const { error: e2 } = await admin.rpc(clase.borraRpc!, { p_uid: quien.user.id, p_id: id, p_solo_comprobar: false });
      if (e2) return json({ ok: false, error: 'fila_no_borrada', code: e2.code }, 500);
      return json({ ok: true });
    }

    // ── preparar la subida ───────────────────────────────────────────────
    if (accion === 'subida_url') {
      if (clase === CLASES.creatividad) {
        const s = await subidaCreatividad(usuario, body);
        if ('error' in s) return json({ ok: false, error: s.error }, s.status);
        const { data, error } = await admin.storage.from(clase.bucket).createSignedUploadUrl(s.path);
        if (error || !data) return json({ ok: false, error: 'no_se_pudo_preparar_la_subida' }, 500);
        return json({ ok: true, creatividad_id: s.id, path: s.path, token: data.token, content_type: s.content_type, bucket: clase.bucket });
      }
      const ext = String(body.ext ?? '').toLowerCase();
      const tipoDe = (x: string) => (clase.tipos ?? TIPOS_)[x];
      if (!clase.exts.includes(ext) || !tipoDe(ext)) return json({ ok: false, error: 'tipo_de_fichero_no_admitido' }, 400);
      const carpeta = await clase.carpeta(usuario, body);
      if (typeof carpeta !== 'string') return json({ ok: false, error: carpeta.error }, carpeta.status);
      const path = `${carpeta}${crypto.randomUUID()}${ext}`;
      const { data, error } = await admin.storage.from(clase.bucket).createSignedUploadUrl(path);
      if (error || !data) return json({ ok: false, error: 'no_se_pudo_preparar_la_subida' }, 500);
      return json({ ok: true, path, token: data.token, content_type: tipoDe(ext), bucket: clase.bucket });
    }

    // ── registrar lo subido ──────────────────────────────────────────────
    if (accion === 'registra') {
      if (!clase.registra) return json({ ok: false, error: 'accion_desconocida' }, 400);
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
      const { data: id, error } = await clase.registra!(quien.user.id, body, path);
      if (error) {
        // lo subido y no registrado no se queda suelto en el bucket (en `deck`, además, sería público)
        await quita();
        return errRpc(error);
      }
      return json({ ok: true, id });
    }

    // ── creatividad: validar lo subido y guardar en UNA transacción ──────
    if (accion === 'guarda' && clase === CLASES.creatividad) {
      const r = await guardaCreatividad(usuario, quien.user.id, body);
      if ('rpcError' in r) return errRpc(r.rpcError as { message?: string; code?: string });
      if ('error' in r) return json({ ok: false, error: r.error }, r.status);
      return json({ ok: true, fila: r.fila });
    }

    return json({ ok: false, error: 'accion_desconocida' }, 400);
  } catch (e) {
    console.error('ficheros error interno: ' + String((e as Error)?.stack ?? e));
    return json({ ok: false, error: 'error_interno' }, 500);
  }
});
