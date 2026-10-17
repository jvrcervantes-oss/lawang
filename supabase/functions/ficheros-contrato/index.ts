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
//   snapshot_url     {contrato_id}    → {path, token}  documento a firmar (solo si nadie firmó aún), a la ruta de
//                    ESPERA `pendientes/<id>.subida.<nonce>.html`; envia_firma {…, subida} lo pasa a la fija `pendientes/<id>.html` solo
//                    si la RPC crea el enlace (LAW-411, 28-sep-2026). La pantalla usa el `path` que se le da.
//   envia_firma      {contrato_id, nombre, email, rol, orden, sin_anexo?} → {link, anulados}
//                    sin_anexo = {motivo: 'ninguno'|'sin_apendice_a'|'fallo', faltan: [texto]}: el agente confirmó «Enviar
//                    igualmente» sin un documento del modelo (28-sep-2026, owner). Va a contrato_envia_firma, que lo
//                    valida y apunta la constancia en contrato_eventos en la MISMA transacción que el envío (LAW-406):
//                    o salen el enlace y su constancia, o no sale nada. Desde LAW-410 la RPC deduce ella la falta en
//                    un contrato de obra; lo que manda la pantalla solo suma.
//   pdf_manual_url   {contrato_id}    → {path, token}  PDF firmado a mano
//   cierra_manual    {contrato_id}    → {path, hash, anulados}
//   limpia_borradores {}              → {borrados}     borradores de firma de contratos que ya no existen
//   reenvia_caducada {contrato_id, ver?} → {puede:false, motivo} | {puede:true, para, …} (ver) | {enlace, correo, motivo?}
//                    enlace caducado → enlace nuevo para el MISMO firmante y el MISMO documento + correo por la cola
//                    (17-oct-2026, «Reenviar todas» de Hoy toca; la regla en reenvio.ts)
//
// verify_jwt=false por el mismo motivo que send-contract-email (CORS del preflight); el JWT
// se valida a mano.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { constanciaHeredada, decideReenvio, documentoCasa, superaTope, TOPE_REENVIOS, VENTANA_TOPE_MIN, type FilaFirma } from './reenvio.ts';

const URL_SB = Deno.env.get('SUPABASE_URL')!;
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const ANON = Deno.env.get('SUPABASE_ANON_KEY')!;
const admin = createClient(URL_SB, SERVICE);
const BUCKET_FIRMAS = 'contratos-firmados';

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
    // en minúsculas: la ruta de Storage y el patrón de la ruta de espera se comparan tal cual (revisor 28-sep)
    const contratoId = String(body.contrato_id ?? '').toLowerCase();
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
    // `pendientes/<id>.html` (y `<id>.subida.<nonce>.html`) cuyo contrato no existe. No recibe rutas de la pantalla, así
    // que no puede borrar nada vivo. El PDF firmado no vive en `pendientes/`: nunca se toca.
    if (accion === 'limpia_borradores') {
      const nombres: [string, string][] = [];   // [id del contrato, nombre del fichero]
      for (let off = 0; ; off += 1000) {
        const { data, error } = await admin.storage.from(BUCKET_FIRMAS).list('pendientes', { limit: 1000, offset: off });
        if (error) return json({ ok: false, error: 'no_se_pudo_listar' }, 500);
        // también los documentos en espera `<id>.subida.<nonce>.html` (LAW-411) de un contrato que ya no existe
        (data ?? []).forEach((o) => { const m = /^([0-9a-f-]{36})(\.subida\.[0-9a-f]{32})?\.html$/i.exec(o.name); if (m) nombres.push([m[1], o.name]); });
        if (!data || data.length < 1000) break;
      }
      if (!nombres.length) return json({ ok: true, borrados: 0 });
      const ids = [...new Set(nombres.map(([id]) => id))];
      const vivos = new Set<string>();
      for (let i = 0; i < ids.length; i += 200) {
        const { data, error } = await admin.from('contratos').select('id').in('id', ids.slice(i, i + 200));
        if (error) return json({ ok: false, error: 'no_se_pudo_comprobar' }, 500);
        (data ?? []).forEach((r) => vivos.add(r.id));
      }
      const huerfanos = nombres.filter(([id]) => !vivos.has(id)).map(([, n]) => `pendientes/${n}`);
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
      // LAW-411 (28-sep-2026): el documento nuevo se sube a una ruta de ESPERA y solo pasa a la ruta fija
      // (la que leen firma-submit, el trigger _firma_solo_servidor y las policies de Storage) DESPUÉS de que
      // contrato_envia_firma haya creado el enlace. Antes se subía directo a la fija: si la RPC fallaba (validación,
      // permiso, red) el enlace anterior seguía vivo con un hash que ya no casaba y firma-submit lo rechazaba.
      // La ruta de espera lleva un NONCE por subida (code-review 28-sep): con una sola ruta por contrato, dos agentes
      // enviando a la vez podían firmar cada uno el documento del otro.
      const prefijoEspera = `${contratoId}.subida.`;
      const reEspera = new RegExp('^pendientes/' + contratoId + '\\.subida\\.[0-9a-f]{32}\\.html$');
      const firmados = (est as { firmados: number }).firmados;
      if (accion === 'snapshot_url') {
        // una vez que alguien firmó, el documento lo reescribe solo firma-submit (lleva sus firmas)
        if (firmados > 0) return json({ ok: false, error: 'ya_hay_firmas' }, 409);
        const espera = `pendientes/${prefijoEspera}${crypto.randomUUID().replace(/-/g, '')}.html`;
        const { data, error } = await admin.storage.from(BUCKET_FIRMAS).createSignedUploadUrl(espera);
        if (error || !data) return json({ ok: false, error: 'no_se_pudo_preparar_la_subida' }, 500);
        return json({ ok: true, path: espera, token: data.token });
      }
      // envia_firma: el hash del documento lo calcula el servidor sobre lo que hay en el bucket.
      //   · `subida` (la ruta que devolvió snapshot_url) → se firma ESE documento y se promueve tras el ok. Tiene que
      //     ser una ruta de espera de ESTE contrato y existir: si no, se para (nunca se cae al fijo a ciegas).
      //   · Con firmas ya estampadas, nunca: el fijo las lleva y lo reescribe solo firma-submit.
      //   · Sin `subida` (pestaña abierta con la pantalla de antes): si hay UNA sola ruta de espera de este contrato,
      //     esa; si hay varias, se pide recargar; si no hay ninguna, el fijo, como antes.
      let espera = '';
      if (firmados === 0) {
        if (body.subida != null) {
          espera = String(body.subida).toLowerCase();
          if (!reEspera.test(espera)) return json({ ok: false, error: 'subida_invalida' }, 400);
        } else {
          const { data: lista, error: eL } = await admin.storage.from(BUCKET_FIRMAS)
            .list('pendientes', { limit: 20, search: prefijoEspera });
          if (eL) return json({ ok: false, error: 'no_se_pudo_leer_el_documento' }, 500);
          const mias = (lista ?? []).map((o) => 'pendientes/' + o.name).filter((n) => reEspera.test(n));
          if (mias.length > 1) return json({ ok: false, error: 'recarga_la_pagina_y_vuelve_a_generar' }, 409);
          if (mias.length === 1) espera = mias[0];
        }
      } else if (body.subida != null) {
        return json({ ok: false, error: 'ya_hay_firmas' }, 409);
      }
      // «No está» (Storage responde 400/404) no es lo mismo que «Storage no ha contestado» (5xx): lo segundo no
      // puede leerse como que falta el documento (revisor 28-sep).
      const rDoc = await leeFresco(BUCKET_FIRMAS, espera || path);
      if (!rDoc.ok) {
        return rDoc.status === 400 || rDoc.status === 404
          ? json({ ok: false, error: 'falta_el_documento_a_firmar' }, 409)
          : json({ ok: false, error: 'No se ha podido leer el documento a firmar (almacenamiento ' + rDoc.status + '): vuelve a intentarlo' }, 502);
      }
      const promover = !!espera;
      const html = await rDoc.text();
      const hash = await sha256hex(html);
      // «Enviar igualmente» sin un anexo del modelo (LAW-406, 28-sep-2026): la constancia la valida y la apunta
      // contrato_envia_firma en la MISMA transacción que el envío, con el actor de la sesión. Antes eran dos
      // llamadas y un fallo de la segunda dejaba el envío hecho sin constancia. `p_sin_anexo` solo viaja si lo
      // hay. ORDEN: esta edge va DESPUÉS de la migración 20260928120000 (con p_sin_anexo, la firma vieja de 6
      // argumentos no casa y el envío falla); los envíos sin constancia sí resolverían cualquiera de las dos.
      const { data: r, error: eEnv } = await usuario.rpc('contrato_envia_firma', {
        p_contrato: contratoId,
        p_nombre: String(body.nombre ?? ''), p_email: String(body.email ?? ''),
        p_rol: String(body.rol ?? ''), p_orden: Number(body.orden ?? 1),
        p_snapshot_hash: hash,
        ...(body.sin_anexo != null ? { p_sin_anexo: body.sin_anexo } : {}),
      });
      // Si la RPC falla, la ruta fija no se ha tocado: el enlace anterior sigue casando con su documento. El
      // documento en espera se borra (el siguiente intento sube otro con su propio nonce).
      if (eEnv) {
        if (promover) {
          const { error: eRm } = await admin.storage.from(BUCKET_FIRMAS).remove([espera]);
          // MUDO A PROPOSITO: el error que importa es el de la RPC, que se devuelve; un documento en espera que no
          // se pudo borrar no se vuelve a firmar (nonce propio) y lo barre limpia_borradores con su contrato.
          if (eRm) console.error('ficheros-contrato: no se pudo borrar ' + espera + ': ' + eRm.message);
        }
        return errRpc(eEnv);
      }
      if (promover) {
        // Los MISMOS bytes que se han hasheado, a la ruta fija. Si esto falla, el enlace nuevo ya existe con el hash
        // del documento nuevo y el fijo sigue siendo el viejo: firma-submit lo rechaza (no se firma nada distinto de
        // lo enviado) y el error llega a la pantalla ahora, no al comprador. Generar otra vez lo arregla (anula este).
        const REGENERA = 'El enlace se ha creado pero no ha quedado bien unido a su documento: vuelve a pulsar «Generar enlace de firma» (anula este).';
        // Dos envíos del mismo contrato a la vez (revisor 28-sep): el otro puede crear su enlace DESPUÉS del nuestro
        // (y el nuestro queda anulado) y promover su documento antes o después que nosotros. Se mira el enlace vivo
        // ANTES de escribir —si ya no es el nuestro, no se pisa el documento del otro— y DESPUÉS —si entretanto ha
        // cambiado, se dice ahora, no cuando el comprador intente firmar—. Queda una ventana de milisegundos entre
        // la segunda mirada del otro y nuestra escritura; firma-submit sigue rechazando un hash que no casa.
        const enlaceVivoEsElNuestro = async (): Promise<string> => {
          const { data: viva, error: eViva } = await admin.from('contrato_firmas').select('snapshot_hash')
            .eq('contrato_id', contratoId).eq('estado', 'pendiente').maybeSingle();
          if (eViva) return 'no_se_pudo_comprobar';
          return viva && viva.snapshot_hash === hash ? '' : 'otro_envio_a_la_vez';
        };
        const antes = await enlaceVivoEsElNuestro();
        if (antes) return json({ ok: false, error: REGENERA, motivo: antes }, antes === 'otro_envio_a_la_vez' ? 409 : 500);
        const { error: eUp } = await admin.storage.from(BUCKET_FIRMAS)
          .upload(path, new Blob([html], { type: 'text/html' }), { contentType: 'text/html', upsert: true });
        if (eUp) return json({ ok: false, error: REGENERA, motivo: 'promocion_fallida' }, 500);
        const despues = await enlaceVivoEsElNuestro();
        if (despues) return json({ ok: false, error: REGENERA, motivo: despues }, despues === 'otro_envio_a_la_vez' ? 409 : 500);
        const { error: eRm } = await admin.storage.from(BUCKET_FIRMAS).remove([espera]);
        // MUDO A PROPOSITO: un documento en espera que no se pudo borrar no se vuelve a firmar (cada subida lleva su
        // nonce y la pantalla manda el suyo) y lo barre limpia_borradores si el contrato desaparece; el envío ya está
        // bien hecho.
        if (eRm) console.error('ficheros-contrato: no se pudo borrar ' + espera + ': ' + eRm.message);
      }
      return json({ ok: true, ...(r as Record<string, unknown>) });
    }

    // ── reenviar un enlace de firma CADUCADO (17-oct-2026, mejora 5b: «Reenviar todas» en Hoy toca) ──────────
    // Un contrato por llamada: la pantalla los recorre de uno en uno y pinta el resultado de cada fila (una petición larga
    // con todos dejaría el estado sin decir si se corta a la mitad). `ver:true` solo dice qué se haría, con la MISMA regla
    // que el envío (reenvio.ts). Del cuerpo solo se usa `contrato_id`: el firmante sale de la fila caducada, el documento es
    // el fijo con su hash recalculado aquí y el correo lo compone la cola (plantilla enlace_firma_cadena: destinatario = el
    // firmante de la fila, texto del servidor), nunca send-contract-email con el texto del navegador.
    if (accion === 'reenvia_caducada') {
      if (!esUuid(contratoId)) return json({ ok: false, error: 'contrato_invalido' }, 400);
      // permiso con la sesión de la persona: el mismo que «Generar enlace de firma» (raise si no puede o está bloqueado)
      const { error: eEst } = await usuario.rpc('contrato_firma_estado', { p_contrato: contratoId });
      if (eEst) return errRpc(eEst);
      const [rc, rf, rq] = await Promise.all([
        admin.from('contratos').select('numero, bloqueado, liberado_en').eq('id', contratoId).maybeSingle(),
        admin.from('contrato_firmas').select('id, estado, expira_en, firmante_nombre, firmante_email, firmante_rol, orden, snapshot_hash, creado_en')
          .eq('contrato_id', contratoId),
        admin.from('config_instancia').select('valor').eq('clave', 'correo_cola_firma_submit').maybeSingle(),
      ]);
      if (rc.error || rf.error || rq.error) return json({ ok: false, error: 'no_se_pudo_leer_el_contrato' }, 500);
      const numero = (rc.data?.numero as string | undefined) ?? null;
      // La cola es la única salida del correo de este reenvío. Con el interruptor de la cola apagado (AXW-202: encendido el
      // 5-oct con el OK del owner) no se crea el enlace: quedaría un enlace nuevo sin correo. Al generador, uno a uno.
      if (rq.data?.valor !== 'cola') return json({ ok: true, puede: false, motivo: 'cola_apagada', numero });
      const dec = decideReenvio(rc.data, (rf.data ?? []) as FilaFirma[], Date.now());
      if (!dec.ok) return json({ ok: true, puede: false, motivo: dec.motivo, numero });
      const f = dec.fila;
      // Si el enlace caducado salió sin un anexo (LAW-406/410), se dice en la vista previa: en el generador eso pide
      // «Enviar igualmente» y aquí no hay ese paso. Y la constancia viaja al enlace nuevo (revisor, 17-oct): la base solo
      // deduce sola un modelo apagado o sin plano; lo que declaró la PANTALLA (un PDF que no se pudo incrustar, motivo
      // 'fallo') no lo ve, y sin esto la firma nueva —la que se firma— saldría con el mismo documento y sin constancia.
      // Es un dato que lee el servidor de su evento, no del navegador; contrato_envia_firma lo valida y solo suma.
      const { data: ev, error: eEv } = await admin.from('contrato_eventos').select('detalle')
        .eq('contrato_id', contratoId).eq('evento', 'envio_sin_anexo_confirmado').eq('detalle->>firma_id', f.id).limit(1);
      if (eEv) return json({ ok: false, error: 'no_se_pudo_leer_el_contrato' }, 500);
      const det = (ev?.[0]?.detalle ?? null) as { motivo?: string; motivo_pantalla?: string; faltan?: unknown; declarado_por?: string } | null;
      const sinAnexo = det?.motivo ?? null;
      const constancia = constanciaHeredada(det);
      // Constancias de ANTES de LAW-406 (27-28 sep): las escribía la función suelta que retiró LAW-406, SIN firma_id, así que la búsqueda
      // de arriba no las ve (revisor, 17-oct; esos enlaces caducan el 27-28 oct). Una sin firma_id que puede ser la suya frena el
      // reenvío en bloque —saldría el enlace nuevo sin constancia— y el contrato va al generador, que pide «Enviar igualmente».
      // SIN cota de fecha: del 28-sep 00:42 al 08:42 la edge apuntaba la constancia ANTES de crear el enlace (dos llamadas
      // sueltas, milisegundos antes que él), y en una cadena de firmantes el enlace del 2.º nace después de firmar el 1.º, así
      // que ninguna fecha de corte las cubre todas (revisor 2.ª vuelta y buscador B, 17-oct). Son un conjunto cerrado (la
      // función que las escribía se retiró el 28-sep; contrato_envia_firma siempre pone firma_id) y cerrar de más solo manda
      // ese contrato al generador.
      if (!det) {
        const { data: evViejo, error: eV } = await admin.from('contrato_eventos').select('id')
          .eq('contrato_id', contratoId).eq('evento', 'envio_sin_anexo_confirmado').is('detalle->>firma_id', null).limit(1);
        if (eV) return json({ ok: false, error: 'no_se_pudo_leer_el_contrato' }, 500);
        if (evViejo?.length) return json({ ok: true, puede: false, motivo: 'constancia_sin_enlace', numero });
      }
      const base = { numero, para: f.firmante_email, nombre: f.firmante_nombre, enviado_en: f.creado_en ?? null, caduco_en: f.expira_en, sin_anexo: sinAnexo, tope: TOPE_REENVIOS };
      // La vista previa NO descarga el documento (revisor, 17-oct: con anexos pesa hasta 20 MB y se piden hasta 20 seguidos):
      // la huella se comprueba en el envío, y si no casa la fila lo dice entonces (documento_cambiado / falta_el_documento).
      if (body.ver === true) return json({ ok: true, puede: true, ...base });

      // Tope de TODO el equipo (no por persona: dos admins a la vez doblarían la ráfaga), contado en la base y no en la
      // memoria de esta edge: ver reenvio.ts.
      const desde = new Date(Date.now() - VENTANA_TOPE_MIN * 60_000).toISOString();
      const { count, error: eT } = await admin.from('contrato_firmas').select('id', { count: 'exact', head: true })
        .eq('anulado_motivo', 'nuevo_enlace').gte('anulado_en', desde);
      if (eT) return json({ ok: false, error: 'no_se_pudo_comprobar_el_tope' }, 500);
      if (superaTope(count ?? 0)) return json({ ok: false, error: 'demasiados_reenvios', tope: TOPE_REENVIOS, minutos: VENTANA_TOPE_MIN }, 429);

      // Siempre el FIJO, nunca una ruta de espera (una generación a medias que nadie envió): y tiene que ser el que se mandó.
      const rDoc = await leeFresco(BUCKET_FIRMAS, `pendientes/${contratoId}.html`);
      if (!rDoc.ok) {
        return rDoc.status === 400 || rDoc.status === 404
          ? json({ ok: true, puede: false, motivo: 'falta_el_documento', numero })
          : json({ ok: false, error: 'No se ha podido leer el documento a firmar (almacenamiento ' + rDoc.status + '): vuelve a intentarlo' }, 502);
      }
      const hash = await sha256hex(await rDoc.text());
      if (!documentoCasa(hash, f)) return json({ ok: true, puede: false, motivo: 'documento_cambiado', numero });

      // contrato_envia_firma anula TODAS las pendientes del contrato: justo antes se vuelve a mirar que la única sigue siendo
      // la caducada que se comprobó (revisor, 17-oct). Si entretanto alguien generó un enlace vivo desde el generador, no se
      // le anula. Entre esta lectura y la RPC quedan milisegundos, y se aceptan (Backend, 17-oct): dos reenvíos a la vez los
      // para el índice único contrato_firmas_un_pendiente_por_rol (la segunda RPC da 23505 y se deshace), y un enlace del
      // generador creado justo en ese hueco queda anulado y su envío falla a la vista por el candado de destino de
      // send-contract-email. Si algún día se quiere cerrar del todo: una RPC NUEVA (contrato_reenvia_caducada con el id
      // esperado), nunca un parámetro con valor por defecto en contrato_envia_firma (dos versiones y PostgREST no elige).
      const { data: rf2, error: eF2 } = await admin.from('contrato_firmas')
        .select('id, estado, expira_en, firmante_nombre, firmante_email, firmante_rol, orden, snapshot_hash, creado_en').eq('contrato_id', contratoId);
      if (eF2) return json({ ok: false, error: 'no_se_pudo_leer_el_contrato' }, 500);
      const dec2 = decideReenvio(rc.data, (rf2 ?? []) as FilaFirma[], Date.now());
      if (!dec2.ok || dec2.fila.id !== f.id) return json({ ok: true, puede: false, motivo: dec2.ok ? 'otro_envio_a_la_vez' : dec2.motivo, numero });

      const { data: r, error: eEnv } = await usuario.rpc('contrato_envia_firma', {
        p_contrato: contratoId, p_nombre: f.firmante_nombre ?? '', p_email: f.firmante_email ?? '',
        p_rol: f.firmante_rol ?? '', p_orden: f.orden ?? 1, p_snapshot_hash: hash,
        ...(constancia ? { p_sin_anexo: constancia } : {}),
      });
      if (eEnv) return errRpc(eEnv);
      // contrato_envia_firma no devuelve el id de la firma nueva: es la pendiente con ESTA huella. Si ya no lo es, otro envío
      // del mismo contrato se ha cruzado (milisegundos): el enlace vivo es el suyo y el correo lo manda quien lo creó.
      const { data: nueva, error: eN } = await admin.from('contrato_firmas').select('id, snapshot_hash')
        .eq('contrato_id', contratoId).eq('estado', 'pendiente').maybeSingle();
      if (eN || !nueva || nueva.snapshot_hash !== hash) {
        return json({ ok: true, enlace: true, correo: false, motivo: eN ? 'no_se_pudo_comprobar' : 'otro_envio_a_la_vez', ...base });
      }
      const { data: enc, error: eQ } = await admin.rpc('correo_encolar', { p_clave: 'enlace_firma_cadena', p_firma: nueva.id });
      if (eQ || !enc || typeof (enc as { id?: unknown }).id !== 'string') {
        // Sin caer al envío directo con un texto del navegador: se dice y el generador lo deja reenviar.
        console.error('ficheros-contrato reenvia_caducada: enlace creado, correo no encolado', numero, String(eQ?.message ?? 'sin id').slice(0, 200));
        return json({ ok: true, enlace: true, correo: false, motivo: 'correo_no_encolado', ...base });
      }
      return json({ ok: true, enlace: true, correo: true, anulados: (r as { anulados?: number })?.anulados ?? null, ...base });
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
