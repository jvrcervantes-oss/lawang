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
//   modelo_documento → bucket `modelos` (privado). Planos y marcar «va en el contrato» (en_contrato) solo admin;
//                      el resto, cualquiera del equipo. PDF o imagen. Tipos: plano, calidades, ficha, render, dosier, otro.
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
// LAW-78 (27-sep-2026; revisión previa con Datos y Seguridad):
//   anexo_contrato     → bucket `contratos-anexos` (privado, solo JPEG, 3 MB). Una página de un anexo subido a mano
//                        de un contrato. El contrato TIENE que estar guardado (la fila existe): el permiso lo decide
//                        `contrato_anexo_puede` con el JWT del usuario, con las reglas de contrato_guarda (no bloqueado,
//                        sin firma viva). Ruta `<contrato>/<uuid>/<n>.jpg`, la genera este servidor. `registra` lee la
//                        página ENTERA (≤3 MB): magia JPEG, tamaño, sha256 y ancho/alto los calcula el servidor, no la
//                        pantalla; si no es un JPEG se borra. Sin `borra`: lo que se queda sin usar lo recoge el barrido
//                        (contracts/tools/anexos_barrido.py). Funciones puras en anexo.mjs (anexo.test.js).
//
// Acciones (POST JSON, `accion` + `clase`):
//   subida_url {clase, ...ids, ext, tipo?}          → {path, token, content_type}   (creatividad: + creatividad_id)
//   registra   {clase, ...ids, path, nombre, tipo?} → {id}
//   borra      {clase, id}                          → {ok}
//   guarda     {clase:'creatividad', creatividad_id, tipo, datos, estado_path, path?, portada_path?, foto_ids?, modelo_ids?} → {fila}
//   AXW-66 (28-sep), solo clase deck_foto:
//   urls        {clase:'deck_foto', foto_ids[≤200]}     → {urls:{id:url|null}, caduca_seg}   (equipo; firmada si privada)
//   deck_activa {clase:'deck_foto', proyecto_id, activo} → {unidades, activo} | 409 cambio_en_curso | 500 deck_a_medias (admin)
//   sincroniza  {clase:'deck_foto'}                      → {movidas, fallidas, quedan, en_ambos}                 (admin)
//
// verify_jwt=false por el mismo motivo que ficheros-contrato (CORS del preflight); el JWT se valida a mano.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { TIPOS, bytesCuadran } from '../ficheros-kyc/firma.mjs';
import { TOPE_PAGINA, anexoIdOk, dimsJpeg, esJpeg, hex, nPagina, rutaAnexo, rutaAnexoOk } from './anexo.mjs';

const URL_SB = Deno.env.get('SUPABASE_URL')!;
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const ANON = Deno.env.get('SUPABASE_ANON_KEY')!;
const admin = createClient(URL_SB, SERVICE);
const TIPOS_: Record<string, string> = TIPOS;

// Orígenes del navegador (27-sep-2026, ERP maestro B7): en una instancia del ERP el instalador pone el secreto
// CORS_ORIGENES (erp/nueva_instancia.py → `https://<dominio_erp>`, lista separada por comas) y solo esos orígenes
// pasan; sin CORS_ORIGENES —Lawang no lo tiene— siguen sus tres dominios. Secreto propio y no SITIO_URL: en Lawang
// SITIO_URL es la base de los enlaces de firma-submit, y reutilizarlo cortaría las subidas desde www./sumbahills.
const origenDe = (u: string) => { try { const x = new URL(u); return x.protocol === 'https:' ? x.origin : ''; } catch { return ''; } };  // solo https: file:/data: darían «null»
const CORS_INSTANCIA = (Deno.env.get('CORS_ORIGENES') ?? '').split(',').map((u) => origenDe(u.trim())).filter(Boolean);
const ORIGENES = CORS_INSTANCIA.length ? CORS_INSTANCIA : [
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
      if (!['plano', 'calidades', 'ficha', 'render', 'dosier', 'otro'].includes(tipo)) return { error: 'tipo_de_documento_invalido', status: 400 };
      if (tipo === 'plano' && !(await esAdmin(u))) return { error: 'plano_solo_admin', status: 403 };
      // Marcarlo para el contrato al subir es de administración (27-sep-2026): se mira ANTES de subir, y la base
      // lo vuelve a mirar al registrar (modelo_documento_registra).
      if (body.en_contrato === true && !(await esAdmin(u))) return { error: 'en_contrato_solo_admin', status: 403 };
      // el dosier es comercial: nunca va en el contrato (owner, 28-sep-2026; la base también lo rechaza)
      if (body.en_contrato === true && tipo === 'dosier') return { error: 'dosier_no_va_en_el_contrato', status: 400 };
      const { data, error } = await u.from('modelos').select('id').eq('id', modelo).maybeSingle();
      if (error || !data) return { error: 'modelo_no_visible', status: 403 };
      return modelo + '/';
    },
    registra: (uid, body, path) => admin.rpc('modelo_documento_registra', {
      p_uid: uid, p_modelo: String(body.modelo_id ?? ''), p_path: path,
      p_nombre: String(body.nombre ?? '').slice(0, 300), p_tipo: String(body.tipo ?? 'otro'),
      p_techo_clave: body.techo_clave == null ? null : String(body.techo_clave),
      p_en_contrato: body.en_contrato === true,
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
  anexo_contrato: {
    bucket: 'contratos-anexos',
    exts: ['.jpg'],
    bytesOk: (_ext, b) => esJpeg(b),
    carpeta: async () => ({ error: 'accion_desconocida', status: 400 }), // tiene su propio camino (abajo)
    filaDe: async (path) => !!(await admin.from('contrato_anexo_paginas').select('id').eq('path', path).maybeSingle()).data,
  },
};

// ── anexo_contrato: permiso sobre ESE contrato, con el JWT del usuario ───────────────────────────────────────────
// La fila del contrato tiene que existir: un contrato nuevo se guarda antes de subirle anexos.
const PUEDE_ANEXO: Record<string, { error: string; status: number }> = {
  no_visible: { error: 'contrato_no_guardado', status: 404 },
  bloqueado: { error: 'contrato_bloqueado', status: 409 },
  sin_permiso: { error: 'sin_permiso_contrato', status: 403 },
};
async function permisoAnexo(u: Usuario, contrato: string): Promise<{ error: string; status: number } | null> {
  if (!esUuid(contrato)) return { error: 'contrato_invalido', status: 400 };
  const { data, error } = await u.rpc('contrato_anexo_puede', { p_contrato: contrato });
  if (error) return { error: 'error_interno', status: 500 };
  return data === 'ok' ? null : (PUEDE_ANEXO[String(data)] ?? PUEDE_ANEXO.sin_permiso);
}

async function subidaAnexo(u: Usuario, body: Record<string, unknown>) {
  const contrato = String(body.contrato_id ?? '');
  const p = await permisoAnexo(u, contrato);
  if (p) return p;
  const n = nPagina(body.n);
  if (!n) return { error: 'pagina_invalida', status: 400 } as const;
  const path = rutaAnexo(contrato, n, crypto.randomUUID());
  if (!path) return { error: 'ruta_invalida', status: 400 } as const;
  return { path };
}

// Registrar una página ya subida: el servidor la lee entera (≤3 MB) y decide él qué es, cuánto pesa y su huella.
async function registraAnexo(u: Usuario, uid: string, body: Record<string, unknown>) {
  const B = CLASES.anexo_contrato.bucket;
  const contrato = String(body.contrato_id ?? '');
  const p = await permisoAnexo(u, contrato);
  if (p) return p;
  const anexo = String(body.anexo_id ?? '');
  if (!anexoIdOk(anexo)) return { error: 'anexo_invalido', status: 400 } as const;
  const n = nPagina(body.n);
  if (!n) return { error: 'pagina_invalida', status: 400 } as const;
  const path = String(body.path ?? '');
  if (!rutaAnexoOk(contrato, n, path)) return { error: 'ruta_invalida', status: 400 } as const;
  const quita = async () => { if (!(await CLASES.anexo_contrato.filaDe(path))) await admin.storage.from(B).remove([path]); };
  const cab = await cabecera(B, path);
  if (!cab) return { error: 'el_fichero_no_ha_llegado', status: 409 } as const;
  if (!esJpeg(cab)) { await quita(); return { error: 'el_fichero_no_es_lo_que_dice_ser', status: 400 } as const; }
  const todo = await descargaEntera(B, path);
  if (!todo) return { error: 'el_fichero_no_ha_llegado', status: 409 } as const;
  if (todo.length > TOPE_PAGINA) { await quita(); return { error: 'pagina_demasiado_grande', status: 400 } as const; }
  if (!esJpeg(todo)) { await quita(); return { error: 'el_fichero_no_es_lo_que_dice_ser', status: 400 } as const; }
  const sha256 = hex(await crypto.subtle.digest('SHA-256', todo));
  const dims = dimsJpeg(todo);
  const { data, error } = await admin.rpc('contrato_anexo_registra', {
    p_uid: uid, p_contrato: contrato, p_anexo_id: anexo, p_n: n, p_path: path, p_sha256: sha256,
    p_bytes: todo.length, p_ancho: dims?.ancho ?? null, p_alto: dims?.alto ?? null,
  });
  if (error) { await quita(); return { rpcError: error }; }
  return { id: data, sha256, bytes: todo.length, ancho: dims?.ancho ?? null, alto: dims?.alto ?? null };
}

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

// ── Deck: fotos públicas solo de decks abiertos (AXW-66, 28-sep-2026; encargo 20260928_lawang_deck_fotos_privadas,
// revisión previa #139). Las fotos de proyectos sin deck abierto (y los ficheros sin fila) viven en `deck-privado`.
// Qué bucket DEBE tener cada objeto lo decide la base (deck_fotos_desajustes, lista cerrada de prefijos); aquí solo se
// mueve por Storage API conservando el nombre. Nunca se acepta del cliente una ruta ni un bucket: solo ids.
const DECK_PRIVADO = 'deck-privado';
const MAX_MUEVE = 300;          // por llamada: el resto lo recoge la siguiente (idempotente)
const FIRMA_SEG = 3600;         // URL firmada de 1 h: se pide al pintar y otra vez antes de imprimir; nunca se guarda
type RespDeck = { cuerpo: Record<string, unknown>; status?: number } | { rpcError: unknown };
type Desajuste = { name: string; bucket_real: string; bucket_debido: string; proyecto_id: string | null; motivo: string };

// ¿`deck` es público en ESTA instancia? En Lawang sí; en el ERP maestro nació privado (20260927230000). Si no lo es,
// también se firma: la acción `urls` sirve igual en las dos.
let deckPublico: boolean | null = null;
async function esDeckPublico(): Promise<boolean> {
  if (deckPublico === null) {
    const { data } = await admin.storage.getBucket('deck');
    deckPublico = data?.public === true;
  }
  return deckPublico;
}

// Mover conservando el nombre (rutas planas, revisión #139 DAT3). Por REST: el `move` con destinationBucket se probó
// así el 28-sep (S1: ida y vuelta de un objeto, mismo tamaño y sha256).
async function mueveObjeto(name: string, desde: string, hacia: string): Promise<boolean> {
  const r = await fetch(`${URL_SB}/storage/v1/object/move`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + SERVICE, apikey: SERVICE, 'content-type': 'application/json' },
    body: JSON.stringify({ bucketId: desde, sourceKey: name, destinationKey: name, destinationBucket: hacia }),
  });
  await r.body?.cancel();
  return r.ok;
}

// Pone en su bucket lo que la base dice que está mal puesto. `en_ambos` NO se toca (borrar una de las dos copias es
// decisión de una persona): se cuenta y se devuelve. Devuelve también lo que queda tras mover.
async function reconcilia(proyecto: string | null): Promise<{ movidas: number; fallidas: number; quedan: number; en_ambos: number } | { rpcError: unknown }> {
  const { data, error } = await admin.rpc('deck_fotos_desajustes', { p_proyecto_id: proyecto });
  if (error) return { rpcError: error };
  const filas = ((data ?? []) as Desajuste[]).filter((d) => d.motivo !== 'en_ambos').slice(0, MAX_MUEVE);
  let movidas = 0, fallidas = 0;
  for (let i = 0; i < filas.length; i += 8) {
    const lote = await Promise.all(filas.slice(i, i + 8).map((d) => mueveObjeto(d.name, d.bucket_real, d.bucket_debido)));
    lote.forEach((ok) => ok ? movidas++ : fallidas++);
  }
  const { data: d2, error: e2 } = await admin.rpc('deck_fotos_desajustes', { p_proyecto_id: proyecto });
  if (e2) return { rpcError: e2 };
  const resto = (d2 ?? []) as Desajuste[];
  return { movidas, fallidas, quedan: resto.filter((d) => d.motivo !== 'en_ambos').length, en_ambos: resto.filter((d) => d.motivo === 'en_ambos').length };
}

const ACCIONES_DECK: Record<string, (u: Usuario, uid: string, body: Record<string, unknown>) => Promise<RespDeck>> = {
  // URL de cada foto por id: pública si está en un `deck` público, firmada (1 h) si no. La ruta sale de deck_fotos y el
  // bucket de storage.objects (deck_fotos_ubicacion, que exige es_agente con el usuario del JWT).
  urls: async (_u, uid, body) => {
    const ids = [...new Set((Array.isArray(body.foto_ids) ? body.foto_ids : []).map(String))];
    if (!ids.length || ids.length > 200 || !ids.every(esUuid)) return { cuerpo: { ok: false, error: 'foto_ids_invalidos' }, status: 400 };
    const { data, error } = await admin.rpc('deck_fotos_ubicacion', { p_uid: uid, p_ids: ids });
    if (error) return { rpcError: error };
    const filas = (data ?? []) as { id: string; path: string; bucket: string | null }[];
    const urls: Record<string, string | null> = Object.fromEntries(ids.map((i) => [i, null]));
    const publico = await esDeckPublico();
    const aFirmar: Record<string, { id: string; path: string }[]> = {};
    for (const f of filas) {
      if (!f.bucket) continue;                                     // sin objeto: null (la pantalla lo dice)
      if (f.bucket === 'deck' && publico) urls[f.id] = admin.storage.from('deck').getPublicUrl(f.path).data.publicUrl;
      else (aFirmar[f.bucket] ??= []).push(f);
    }
    for (const [bucket, lista] of Object.entries(aFirmar)) {
      const { data: firmadas, error: eF } = await admin.storage.from(bucket).createSignedUrls(lista.map((f) => f.path), FIRMA_SEG);
      if (eF) return { cuerpo: { ok: false, error: 'no_se_pudieron_firmar' }, status: 500 };
      const porRuta = new Map<string, string>((firmadas ?? []).filter((x) => x.path && x.signedUrl).map((x) => [String(x.path), String(x.signedUrl)]));
      for (const f of lista) urls[f.id] = porRuta.get(f.path) ?? null;
    }
    return { cuerpo: { ok: true, urls, caduca_seg: FIRMA_SEG } };
  },

  // Abrir o cerrar el deck de un proyecto, UN solo camino y en orden (revisión #139 SEG2/SEG4):
  //   abrir  = marca → fotos a `deck` → flag;   cerrar = marca → flag → fotos a `deck-privado`;   quitar marca.
  // Si algo falla ANTES del flag, se quita la marca y se devuelven las fotos a donde estaban. Termina reconciliando el
  // proyecto: si queda algo mal puesto, es un error visible (deck_a_medias), nunca un «ok» silencioso.
  deck_activa: async (_u, uid, body) => {
    const proyecto = String(body.proyecto_id ?? '');
    if (!esUuid(proyecto) || typeof body.activo !== 'boolean') return { cuerpo: { ok: false, error: 'peticion_invalida' }, status: 400 };
    const abrir = body.activo;
    const { error: eM } = await admin.rpc('deck_transicion_empieza', { p_uid: uid, p_proyecto_id: proyecto, p_abrir: abrir });
    if (eM) return eM.code === '55P03' ? { cuerpo: { ok: false, error: 'cambio_en_curso', code: eM.code }, status: 409 } : { rpcError: eM };
    let unidades: number | null = null;
    let fase = abrir ? 'mover_a_publico' : 'flag';
    try {
      if (abrir) {
        const m = await reconcilia(proyecto);
        if ('rpcError' in m || m.quedan > 0) {
          await admin.rpc('deck_transicion_termina', { p_proyecto_id: proyecto });
          await reconcilia(proyecto);                                // vuelven a privado: el deck sigue cerrado
          return { cuerpo: { ok: false, error: 'fotos_sin_mover', fase, detalle: 'rpcError' in m ? null : m }, status: 500 };
        }
        fase = 'flag';
      }
      const { data: n, error: eF } = await admin.rpc('investor_deck_activa_como', { p_uid: uid, p_proyecto_id: proyecto, p_activo: abrir });
      if (eF) {
        await admin.rpc('deck_transicion_termina', { p_proyecto_id: proyecto });
        await reconcilia(proyecto);                                  // lo movido vuelve a donde manda el flag de verdad
        return { rpcError: eF };
      }
      unidades = Number(n);
      fase = 'final';
      await reconcilia(proyecto);                                    // cerrar: ahora sí salen de `deck`
    } finally {
      await admin.rpc('deck_transicion_termina', { p_proyecto_id: proyecto });
    }
    const fin = await reconcilia(proyecto);                          // ya sin marca: lo que manda es el flag
    if ('rpcError' in fin) return { cuerpo: { ok: false, error: 'deck_a_medias', unidades, fase }, status: 500 };
    if (fin.quedan > 0 || fin.en_ambos > 0) {
      return { cuerpo: { ok: false, error: 'deck_a_medias', unidades, quedan: fin.quedan, en_ambos: fin.en_ambos }, status: 500 };
    }
    return { cuerpo: { ok: true, unidades, activo: abrir } };
  },

  // Barrido: todo lo mal puesto, saltando los proyectos en plena transición. Solo administración.
  sincroniza: async (u) => {
    if (!(await esAdmin(u))) return { cuerpo: { ok: false, error: 'solo_admin' }, status: 403 };
    const r = await reconcilia(null);
    if ('rpcError' in r) return { rpcError: r.rpcError };
    return { cuerpo: { ok: r.fallidas === 0, ...r }, status: r.fallidas === 0 ? 200 : 500 };
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
// El fichero entero, igual de sin caché. Solo para lo que tiene tope pequeño (páginas de anexo, 3 MB).
async function descargaEntera(bucket: string, path: string): Promise<Uint8Array | null> {
  const r = await fetch(`${URL_SB}/storage/v1/object/authenticated/${bucket}/${path}?v=${crypto.randomUUID()}`, {
    headers: { Authorization: 'Bearer ' + SERVICE, apikey: SERVICE, 'cache-control': 'no-cache' },
  });
  if (!r.ok) return null;
  return new Uint8Array(await r.arrayBuffer());
}

Deno.serve(async (req) => {
  const cors = corsFor(req);
  const json = (o: unknown, s = 200) => {
    // Al registro solo va el código de error, nunca el cuerpo entero: una respuesta puede llevar rutas o tokens.
    if (s !== 200) {
      const r = (o ?? {}) as { error?: unknown; code?: unknown };
      console.error('ficheros ' + s + ': ' + String(r.error ?? '').slice(0, 120) + (r.code ? ' (' + String(r.code) + ')' : ''));
    }
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

    // ── deck (AXW-66): URLs por id, abrir/cerrar moviendo las fotos, barrido. Acciones NUEVAS de la clase deck_foto:
    //    no tocan subida_url/registra/borra de esa clase (cambian en S4, con el front). ──
    if (clase === CLASES.deck_foto && Object.hasOwn(ACCIONES_DECK, accion)) {
      const r = await ACCIONES_DECK[accion](usuario, quien.user.id, body);
      if ('rpcError' in r) return errRpc(r.rpcError as { message?: string; code?: string });
      return json(r.cuerpo, r.status ?? 200);
    }

    // ── anexo de contrato: su propio camino (ruta por página, sha y medidas del servidor) ──
    if (clase === CLASES.anexo_contrato) {
      if (accion === 'subida_url') {
        const s = await subidaAnexo(usuario, body);
        if ('error' in s) return json({ ok: false, error: s.error }, s.status);
        const { data, error } = await admin.storage.from(clase.bucket).createSignedUploadUrl(s.path);
        if (error || !data) return json({ ok: false, error: 'no_se_pudo_preparar_la_subida' }, 500);
        return json({ ok: true, path: s.path, token: data.token, content_type: 'image/jpeg', bucket: clase.bucket });
      }
      if (accion === 'registra') {
        const r = await registraAnexo(usuario, quien.user.id, body);
        if ('rpcError' in r) return errRpc(r.rpcError as { message?: string; code?: string });
        if ('error' in r) return json({ ok: false, error: r.error }, r.status);
        return json({ ok: true, id: r.id, sha256: r.sha256, bytes: r.bytes, ancho: r.ancho, alto: r.alto });
      }
      return json({ ok: false, error: 'accion_desconocida' }, 400);
    }

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
