// send-contract-email — reemplaza la llamada directa navegador→send_email.php
// del botón "Enviar por email" de app.html cuando hay adjunto.
//
// Por qué existe (LAW-30, 6-ago-2026): el WAF de Hostinger (anomaly scoring
// acumulativo, tipo ModSecurity/OWASP CRS) bloquea con 403 cualquier request a
// send_email.php cuyo cuerpo lleve el HTML completo del contrato con la
// portada de diseño (gradientes, color-mix(), custom properties, url()) — no
// hay una causa única removible sin romper el PDF (investigación cerrada en
// memoria del estudio). Arreglarlo en hPanel es tarea del owner y no depende
// de esta sesión.
//
// El rodeo: la Edge `firma-submit` YA hace exactamente esto al cerrar una
// firma y nunca ha tropezado con el WAF — renderiza el PDF llamando a Railway
// directamente (server-to-server, fuera del dominio de Hostinger) y luego
// llama a send_email.php con `pdf_base64` (nunca `html`), así que lo único
// que cruza el WAF es PDF en base64 + texto, sin CSS. Esta función copia ese
// mismo patrón para el botón manual, que hasta ahora mandaba el HTML directo.
// Cero cambios en send_email.php.
//
// verify_jwt=false: con true el gateway de Supabase intercepta la request
// (incluido el preflight OPTIONS) antes de que corra el código de aquí abajo,
// así que las cabeceras CORS nunca se aplican — mismo motivo que
// admin-usuarios/portal-invitar. Se valida el JWT a mano.
//
// EL PAPEL DE UNA FACTURA LO PINTA ESTA EDGE DESDE LA FILA (15-oct-2026, revisión previa #350, Seguridad):
// con `factura_id`, el `html` y el `pdf_base64` que manda el navegador se IGNORAN (queda una línea de log sin
// contenido para saber cuándo quitarlos de la pantalla). El documento sale de `facturas` leída con la sesión del
// usuario, pintado con el MISMO documento.js de /facturas/ (compartidos.generated.ts, generado por
// tools/empaqueta_edge.py) y con el catálogo de la base. Antes, el agente que enviaba podía mandar al comprador
// cualquier papel —otra cuenta, otro importe— y el sistema lo registraba como «la factura enviada». Ver papelFactura().
// ⚠️ DESPLEGAR = DOS FICHEROS. El CLI empaqueta `index.ts` y `compartidos.generated.ts` (entrypoint en config.toml).
//    Verificación tras cada despliegue: `get_edge_function send-contract-email` tiene que devolver el sha256 de
//    `contracts/edge/send-contract-email/index.ts` Y el de `contracts/edge/send-contract-email/compartidos.generated.ts`.
//    Comparar solo el index.ts deja pasar un maquetador viejo.
// ⚠️ NO DESPLEGAR ANTES DE TENER APLICADA EN LA VIVA 20261015223236_recibi_total_suma_y_exento (aplicada el 16-oct-2026; orquestador agencia-c0 y
//    sesión lawang-cola-2, 15-oct-2026, revisor del papel del correo). Por qué: en un recibí el cuadre de esta edge solo
//    comprueba que el documento sea coherente consigo mismo, y hasta esa migración `guardar_recibi` guarda el total
//    que manda el navegador, así que líneas y total vienen los dos de él. Antes de desplegar, mide también en cada
//    instancia (Lawang, bbm, axisworks-demo), en solo lectura, cuántos documentos cortarían los 409 nuevos: campos
//    de `datos.fields` distintos de su columna en tipo/sociedad/moneda/fecha/contrato/proyecto/cliente; cuenta
//    'otros'; cuenta informada que no existe, sin verificar o de una empresa fuera del alcance de quien envía;
//    `datos.emisor.clave` distinto de la sociedad; `fields` que no es objeto o `lineas` que no es lista de objetos;
//    total nulo o distinto de factura_totales(lineas, moneda, imp_pct), recibís incluidos; `rectifica_numero` en los
//    campos; filas con `banco_de_servidor`; sociedades fuera de las regex de sociedad_guarda y del logo.
//    Y en la viva, solo lectura (Seguridad, consulta de deploy del 15-oct: la equivalencia con la policy se comprobó
//    contra el repo, y el historial de migraciones de Lawang está desincronizado): `pg_policies.qual` de «cuentas:
//    agentes» = es_agente() AND empresa_en_alcance(empresa); pg_get_functiondef de empresa_en_alcance y _ve_empresa
//    iguales a 20261007001600:13-23 y 20261007001400:11-18; has_function_privilege('authenticated',
//    'public.empresa_en_alcance(text)','execute') = true (si no, todo envío con cuenta de empresa da 500).
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { FUENTES, EXPORTA } from './compartidos.generated.ts';

const URL_SB = Deno.env.get('SUPABASE_URL')!;
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const ANON = Deno.env.get('SUPABASE_ANON_KEY')!;
const admin = createClient(URL_SB, SERVICE);

// Mismo secreto de proyecto que ya usa firma-submit — no se duplica.
const RENDER_URL = Deno.env.get('RENDER_URL') || 'https://contracts-pdf-service-production.up.railway.app';
const RENDER_SECRET = Deno.env.get('RENDER_SECRET') || '';
const SITIO = (Deno.env.get('SITIO_URL') || 'https://lawangproperties.com').replace(/\/$/, '');

// AXW-124 (S5.0 F4, 30-sep-2026): a dónde se manda el correo lo decide config_instancia.url_envio_correo (interruptor único:
// la edge envia-correo o, de vuelta atrás, el PHP). Solo se aceptan esas dos URL: una clave manipulada no puede sacar
// el secreto a otro host. Si la clave falta, no es texto o no es una de las dos, cae al PHP (comportamiento de siempre).
// La edge exige su secreto de entrada propio (ENVIO_CORREO_SECRET); el PHP solo conoce RENDER_SECRET.
// Tamaño: la edge envia-correo rechaza un PDF de más de 34 MB de base64 (no se puede subir: el runtime tiene 256 MB) y hay
// contratos firmados de hasta 33 MB reales. Qué pasa con ellos lo decide config_instancia.copias_firmadas_modo, el MISMO
// interruptor (y con la misma lectura) que firma-submit:
//  · «enlace» (hoy, medido 11-oct-2026), clave ausente o ilegible → siguen por el PHP (destinoEnvio), como en la v25.
//    Mientras el PHP no sea 410 es lo único que entrega esos PDF desde el botón manual.
//  · «cola» → 413 `pdf_demasiado_grande` con un texto que la pantalla enseña tal cual: no cabe en el buzón de casi nadie
//    (Gmail corta en 25 MB) y se entrega por el portal del comprador o, para el estudio, desde la intranet. Rechazo previo
//    al SMTP: nunca habría duplicado. Decisión del owner (1-oct-2026, AXW-127): el 413 se enciende con la cola, no antes.
const ENVIO_PHP = 'https://lawangproperties.com/contracts/api/send_email.php';
const ENVIO_EDGE = URL_SB + '/functions/v1/envia-correo';
const TOPE_PDF_EDGE = 34 * 1024 * 1024;
async function destinoEnvio(pdfLen: number): Promise<{ url: string; secreto: string }> {
  try {
    if (pdfLen <= TOPE_PDF_EDGE) {
      const { data } = await admin.from('config_instancia').select('valor').eq('clave', 'url_envio_correo').maybeSingle();
      const u = typeof data?.valor === 'string' ? data.valor.trim() : '';
      if (u === ENVIO_EDGE) return { url: u, secreto: Deno.env.get('ENVIO_CORREO_SECRET') || RENDER_SECRET };
    }
  } catch (_) { /* cae al PHP */ }
  return { url: ENVIO_PHP, secreto: RENDER_SECRET };
}
/** true solo con copias_firmadas_modo = «cola» (copia de modoCola() de firma-submit). Ante cualquier fallo, false = PHP. */
async function modoColaCopias(): Promise<boolean> {
  try {
    const { data } = await admin.from('config_instancia').select('valor').eq('clave', 'copias_firmadas_modo').maybeSingle();
    return data?.valor === 'cola';
  } catch (_) { return false; }
}

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

const b64 = (u8: Uint8Array) => {
  // en trozos: String.fromCharCode(...u8) con un PDF de MB revienta la pila
  let s = '';
  for (let i = 0; i < u8.length; i += 0x8000) s += String.fromCharCode(...u8.subarray(i, i + 0x8000));
  return btoa(s);
};

/* El correo del enlace de firma va SOLO al firmante de un enlace vivo de ese contrato y lleva ESE enlace (17-oct-2026,
   revisión previa de Seguridad de «Reenviar todas», punto 1). Antes, con via:'enlace_firma', valía cualquier dirección y
   cualquier texto con el buzón de Lawang, y en los correos de contrato no se guarda el texto: un «paga a esta otra cuenta»
   no dejaba rastro. El generador ya manda exactamente esto (app.html: FIRMA_ENVIO = {to: el email del envía_firma, link}),
   así que no cambia nada para quien lo usa bien. El texto sigue siendo editable (decisión de producto: el agente saluda a su
   manera). OJO, cierra SOLO esta vía: `via` lo pone el navegador, y un correo con otra vía (o sin ella, o con PDF) sigue
   pudiendo salir a cualquier dirección con texto libre, anclado a un contrato visible — así envía el generador el contrato
   a abogados y terceros. Cerrar eso es decisión de producto y está en contexto/pendientes.md (revisor, 17-oct).
   Devuelve '' si vale, o el motivo. */
async function motivoEnlaceFirmaNoVale(contratoId: string, to: string, message: string): Promise<string> {
  const { data, error } = await admin.from('contrato_firmas').select('firmante_email, enlace_firma')
    .eq('contrato_id', contratoId).eq('estado', 'pendiente').gt('expira_en', new Date().toISOString());
  if (error) return 'no_se_pudo_comprobar';
  const vivas = (data ?? []) as { firmante_email: string | null; enlace_firma: string | null }[];
  const suya = vivas.filter((f) => String(f.firmante_email ?? '').trim().toLowerCase() === to.trim().toLowerCase());
  if (!suya.length) return 'destinatario_no_es_el_firmante';
  if (!suya.some((f) => !!f.enlace_firma && message.includes(f.enlace_firma))) return 'mensaje_sin_el_enlace';
  return '';
}

/* AXW-202 C3 (5-oct-2026): el aviso de anulación de firma puede ir por la cola de correos. Solo cuando
   config_instancia.correo_cola_aviso_anulacion = «cola» (nace «directo»): la RPC correo_aviso_anulacion_encolar lee el
   interruptor UNA vez y, si está en cola, anota «hay que mandar el aviso de ESTA firma anulada» (la firma la elige la base,
   no el navegador; destinatario y motivo salen de contrato_firmas). El texto que compone el navegador se IGNORA en esa ruta:
   lo compone la edge de la cola con la plantilla `aviso_anulacion`. Devuelve null (= se manda directo, como siempre) con el
   interruptor apagado, sin anulación reciente que anclar, o ante cualquier fallo. Un correo nunca se pierde por esto. */
async function encolaAvisoAnulacion(contratoId: string, to: string): Promise<{ duplicado: boolean } | null> {
  try {
    const { data, error } = await admin.rpc('correo_aviso_anulacion_encolar', { p_contrato: contratoId, p_email: to });
    if (error) throw new Error(error.message);
    const d = data as { modo?: string; id?: string; nuevo?: boolean; reabierto?: boolean } | null;
    if (!d || d.modo !== 'cola' || typeof d.id !== 'string') return null;
    return { duplicado: d.nuevo === false && d.reabierto !== true };
  } catch (e) {
    console.error('cola_correos_aviso_anulacion_fallo', String((e as Error)?.message ?? e).slice(0, 200), '— se envía directo');
    return null;
  }
}

/* ══ EL PAPEL DE LA FACTURA, DESDE LA FILA (15-oct-2026, revisión previa #350) ═══════════════════════════════════════
   El dato tiene un dueño: el papel es una COPIA de la fila de `facturas` (columnas + datos.fields/lineas/emisor) y del
   catálogo (`sociedades`, `cuentas_bancarias`). Aquí no se guarda nada: se lee lo de hoy y se pinta.
   Reglas (cada una con su porqué):
   · Las columnas mandan sobre datos.fields en tipo, sociedad, moneda, fecha, contrato, proyecto y cliente: son lo que
     ve la base, el portal y los listados; el papel no puede decir otra cosa.
   · datos.lineas tiene que ser una lista de objetos: documento.js hace `d.lineas.map(l => l.descripcion…)` y con otra
     cosa revienta. Se corta con 409, nunca con excepción.
   · `banco_de_servidor` se BORRA siempre (condición 2c): en Lawang `guardar_recibi` no la quita al guardar, y con ella
     el papel imprimiría los banco_* escritos por el navegador como si los hubiera puesto el servidor. Sin la marca, la
     cuenta del catálogo se pinta desde `cuentas_bancarias`, y una cuenta verificada ya no cambia de datos
     (trigger _cuenta_bancaria_blinda, en Lawang y en el maestro), así que en el ERP sale lo mismo que su copia.
   · La cuenta del catálogo se acepta si `verificada_en is not null` (no se mira `activa`: una factura emitida con una
     cuenta que hoy está desactivada se sigue reimprimiendo con ella). Clave informada (≠ 'otros') que no existe o sin
     verificar → 409. 'otros' sigue imprimiendo los banco_* escritos a mano: deuda declarada aparte (#350).
   · La clave de la cuenta NO es de la factura: está en datos.fields, la escribe el navegador y ni factura_guarda ni
     guardar_recibi la atan a nada. Que la factura sea visible no dice nada de la cuenta. Por eso la cuenta se lee con
     service role (en el ERP la tabla se cierra a authenticated: AXW-299, erp/por_aplicar/cuentas_paso3_lectura_cerrada.sql)
     y se le pasa la MISMA regla de alcance que la policy «cuentas: agentes» de Lawang (20261007001600):
     `es_agente()` (ya exigido arriba) y `empresa_en_alcance(empresa)`, preguntada con la SESIÓN DEL USUARIO. Si la
     cuenta es de una empresa que quien envía no ve → 409 con el mismo código y la misma frase que «no existe»: otra
     frase le confirmaría que esa clave existe en otra empresa (las claves se adivinan). Solo hay alcance si la fila
     trae la columna `empresa` (Lawang); el maestro no la tiene y allí toda cuenta es del único negocio. Revisor, 15-oct.
     NO se exige además que la empresa de la cuenta sea la de la sociedad del documento: quien ve las dos empresas puede
     elegir hoy esa cuenta en su pantalla (pintarSelectCuentas de /facturas/ ofrece todas las visibles) y hay contratos
     que la pactan así (cc00014_timon lo firma PT TEPI SUN GAI y cobra también en sandalwoods_danamon_eur, de
     sandal_woods: 20260914022754). Exigirlo aquí cortaría el envío de facturas que la propia pantalla deja guardar.
   · `datos.emisor` (congelado por congela_emisor_factura) tiene que ser de la sociedad de la fila (condición 2b).
   · Rectificativa (2d): en Lawang `rectifica_numero` lo puede escribir el navegador (factura_guarda guarda datos.fields
     tal cual, salvo banco_de_servidor) y no hay columna que lo respalde → se borra. Solo si la fila trae
     `rectifica_id` (esquema del ERP maestro) se rellena desde la factura original y la columna rectificacion_motivo.
   · Cuadre: calcTotales del papel contra `facturas.total`, con la tolerancia de factura_guarda (1 unidad mínima de la
     moneda). Si no cuadra → 409 antes de render, SMTP, registro y marca: el papel que sale es el que se registra.
   Caja NUEVA por petición: el catálogo cambia y las globales SOCIEDADES/CUENTAS_BANCARIAS de una caja compartida
   las verían dos peticiones a la vez. Evaluar el paquete cuesta milisegundos; el botón lo pulsa una persona. */
const esObjeto = (v: any) => v !== null && typeof v === 'object' && !Array.isArray(v);
const COLS_SOCIEDAD = 'clave,label,razon,marca,domicilio,npwp,npwp_label,nib,rep,logo,logo_alto,emisor_debajo,folio,tinta';
const CAMPOS_RECTIFICA = ['rectifica_numero', 'rectifica_fecha', 'rectificacion_motivo', 'rectificacion_tipo'];
const NO_CUADRA = 'Este documento no cuadra con lo que hay guardado y no se envía. Ábrelo, revísalo, guárdalo de nuevo y vuelve a enviarlo.';

function cajaCompartidos(): any {
  const caja: any = {};
  new Function('caja', FUENTES.join('\n;\n') +
    '\n;Object.assign(caja,{' + EXPORTA.concat(['impuestoDelDocumento', 'DECIMALES']).join(',') + '});')(caja);
  return caja;
}

/** Lo que el papel necesita del catálogo, leído ANTES de pintar (todo lo asíncrono va aquí; el pintado es síncrono).
 *  null = la base no respondió (500, no se envía). Lectura con service role de UNA clave cada vez. La sociedad y la
 *  rectificada salen de COLUMNAS de la factura (visible por RLS para quien envía); la cuenta no: su clave la escribió el
 *  navegador, así que se comprueba aparte que quien envía puede verla (`cuentaAjena`, ver la cabecera de arriba). */
async function leeCatalogoPapel(fila: any, usuario: any): Promise<any> {
  const datos = esObjeto(fila?.datos) ? fila.datos : {};
  const fields = esObjeto(datos.fields) ? datos.fields : {};
  const clave = String(fields.cuenta ?? '').trim();
  const nada = Promise.resolve({ data: null, error: null });
  const [s, c, o]: any[] = await Promise.all([
    admin.from('sociedades').select(COLS_SOCIEDAD).eq('clave', String(fila?.sociedad ?? '')).maybeSingle(),
    // `*`: la columna `empresa` existe en Lawang y no en el maestro (pedirla por nombre rompería la lectura en el ERP).
    clave && clave !== 'otros' ? admin.from('cuentas_bancarias').select('*').eq('clave', clave).maybeSingle() : nada,
    fila?.rectifica_id ? admin.from('facturas').select('numero, fecha_emision').eq('id', fila.rectifica_id).maybeSingle() : nada,
  ]);
  const e = s.error || c.error || o.error;
  if (e) { console.error('papel: no se pudo leer el catálogo: ' + String(e.message ?? e).slice(0, 200)); return null; }
  // Alcance por empresa de la cuenta, con la sesión del usuario (la misma función que usa la policy). Error → null → 500:
  // nunca se da por visible una cuenta que no se ha podido comprobar.
  let cuentaAjena = false;
  if (esObjeto(c.data) && Object.prototype.hasOwnProperty.call(c.data, 'empresa') && c.data.empresa != null) {
    const { data: ve, error: eA } = await usuario.rpc('empresa_en_alcance', { p_empresa: String(c.data.empresa) });
    if (eA) { console.error('papel: no se pudo comprobar el alcance de la cuenta: ' + String(eA.message ?? eA).slice(0, 200)); return null; }
    cuentaAjena = ve !== true;
  }
  return { soc: s.data, cuenta: c.data, original: o.data, cuentaAjena };
}

/** El papel de la factura, SÍNCRONO y sin E/S. Devuelve { ok:true, html } o { ok:false, codigo, error } (→ 409). */
function papelFactura(C: any, fila: any, cat: any, base: string): any {
  const mal = (codigo: string, error: string) => ({ ok: false, codigo, error });
  const datos = esObjeto(fila?.datos) ? fila.datos : null;
  if (!datos || !esObjeto(datos.fields)) return mal('documento_incoherente', NO_CUADRA);
  if (!Array.isArray(datos.lineas) || !datos.lineas.every(esObjeto)) return mal('documento_incoherente', NO_CUADRA);
  if (!['factura', 'proforma', 'recibi'].includes(fila.tipo)) return mal('documento_incoherente', NO_CUADRA);

  const d: any = { ...datos.fields, lineas: datos.lineas };
  delete d.banco_de_servidor;
  for (const k of CAMPOS_RECTIFICA) delete d[k];
  if (fila.rectifica_id) {
    if (!cat?.original?.numero) return mal('documento_incoherente', NO_CUADRA);
    d.rectifica_numero = cat.original.numero;
    d.rectifica_fecha = cat.original.fecha_emision ?? '';
    d.rectificacion_motivo = fila.rectificacion_motivo ?? '';
  }
  for (const k of ['tipo', 'sociedad', 'moneda', 'fecha_emision', 'contrato_numero', 'proyecto_nombre', 'cliente_nombre']) {
    d[k] = fila[k] ?? '';
  }

  const emisor = datos.emisor ?? null;
  if (emisor !== null && (!esObjeto(emisor) || String(emisor.clave ?? '') !== String(fila.sociedad ?? ''))) {
    return mal('emisor_no_coincide', 'La empresa que figura en este documento no es la de su ficha: no se envía. Avisa al administrador.');
  }
  if (!esObjeto(cat?.soc)) return mal('sociedad_desconocida', 'La empresa emisora de este documento ya no está dada de alta: no se envía. Avisa al administrador.');
  const clave = String(d.cuenta ?? '').trim();
  const cta = cat?.cuenta;
  const ajena = clave !== '' && clave !== 'otros' && cat?.cuentaAjena !== false;   // sin comprobar = ajena (falla cerrado)
  if (ajena) {
    // Mismo código y frase que «no existe» (ver cabecera); el motivo real solo al log, sin la clave ni datos de la cuenta.
    console.error('papel: la factura ' + String(fila.id) + ' lleva una cuenta de una empresa fuera del alcance de quien envía');
  }
  if (clave && clave !== 'otros' && (ajena || !(esObjeto(cta) && cta.clave === clave && cta.verificada_en))) {
    return mal('cuenta_no_verificada', 'La cuenta de cobro de este documento no está dada de alta o no está verificada: no se envía. Elige una cuenta verificada, guarda y vuelve a enviar.');
  }

  // Igual que cargarSociedades / cargarCuentasBancarias de entities.js: el papel tiene que salir idéntico al de la pantalla.
  const r = cat.soc;
  C.SOCIEDADES[fila.sociedad] = {
    label: r.label, razon: r.razon, marca: r.marca || '', domicilio: r.domicilio, npwp: r.npwp, rep: r.rep,
    ...(r.npwp_label && r.npwp_label !== 'NPWP' ? { npwpLabel: r.npwp_label } : {}),
    ...(r.nib ? { nib: r.nib } : {}),
    logo: r.logo, logoAlto: r.logo_alto,
    ...(r.emisor_debajo ? { emisorDebajo: true } : {}),
    folio: r.folio, ...(r.tinta ? { tinta: r.tinta } : {}),
  };
  if (clave && clave !== 'otros') {
    C.CUENTAS_BANCARIAS[clave] = { label: cta.label, titular: cta.titular, banco: cta.banco, cuenta: cta.cuenta,
      codigo: cta.codigo, direccion: cta.direccion, extra: cta.extra };
  }

  try {
    const t = C.calcTotales(d.lineas, d.moneda, C.impuestoDelDocumento(d));
    const dec = Number(C.DECIMALES[d.moneda] ?? 2);
    const total = Number(fila.total);
    if (fila.total == null || !Number.isFinite(total) || !Number.isFinite(t.total)
        || Math.round(Math.abs(t.total - total) * Math.pow(10, dec)) > 1) {
      console.error('papel: la factura ' + String(fila.id) + ' no cuadra (líneas ' + t.total + ' / total ' + String(fila.total) + ')');
      return mal('documento_incoherente', NO_CUADRA);
    }
    return { ok: true, html: C.documentoPagina(d, { numero: fila.numero || '', emisor, base }) };
  } catch (e) {
    console.error('papel: no se pudo pintar la factura ' + String(fila.id) + ': ' + String((e as Error)?.message ?? e).slice(0, 200));
    return mal('documento_incoherente', NO_CUADRA);
  }
}

// ponytail: cooldown en memoria del propio isolate, no una tabla — el botón
// lo usa un puñado de personas del equipo con sesión válida, esto solo acota
// un doble-click o un bucle accidental. Se resetea en cada cold start; si
// algún día hace falta un límite real entre instancias, pasar a una tabla.
const ultimoEnvio = new Map<string, number>();
const COOLDOWN_MS = 4000;

Deno.serve(async (req) => {
  const cors = corsFor(req);
  const json = (o: unknown, s = 200) => {
    if (s !== 200) console.error('send-contract-email ' + s + ': ' + JSON.stringify(o));
    return new Response(JSON.stringify(o), { status: s, headers: { ...cors, 'content-type': 'application/json' } });
  };
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ ok: false, error: 'metodo' }, 405);

  try {
    const jwt = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '');
    if (!jwt) return json({ ok: false, error: 'sin_sesion' }, 401);
    const { data: quien, error: eUser } = await admin.auth.getUser(jwt);
    if (eUser || !quien?.user) return json({ ok: false, error: 'sesion_invalida' }, 401);

    // Cliente CON LA SESIÓN DEL USUARIO (26-sep-2026, revisión previa #106, Seguridad):
    // lo que decide si puede es la RLS, igual que si lo hiciera desde su pantalla.
    // `admin` (service role) queda solo para el registro de envíos.
    const usuario = createClient(URL_SB, ANON, {
      global: { headers: { Authorization: 'Bearer ' + jwt } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    // Solo el equipo: un comprador del portal también tiene sesión de Supabase, y sin
    // esto podía mandar cualquier HTML/PDF a cualquier dirección con el correo de Lawang.
    const { data: esAgente, error: eAg } = await usuario.rpc('es_agente');
    if (eAg || esAgente !== true) return json({ ok: false, error: 'solo_equipo' }, 403);

    const body = await req.json().catch(() => ({}));
    const to = String(body.to ?? '').trim();

    // Clave usuario+destinatario (26-sep-2026): el aviso de anulación y las copias del
    // firmado van a VARIOS firmantes seguidos, y con la clave solo por usuario el segundo
    // correo caía en 429. Sigue frenando el doble clic sobre el mismo destinatario.
    const ahora = Date.now();
    const claveCd = quien.user.id + '|' + to.toLowerCase();
    const previo = ultimoEnvio.get(claveCd) ?? 0;
    if (ahora - previo < COOLDOWN_MS) return json({ ok: false, error: 'espera_un_momento' }, 429);
    ultimoEnvio.set(claveCd, ahora);
    const subject = String(body.subject ?? '');
    const message = String(body.message ?? '');
    const filename = String(body.filename ?? 'contrato.pdf');
    const html = String(body.html ?? '');
    const pdfManual = String(body.pdf_base64 ?? '');
    // ancla para el registro de envíos (correos_enviados): el que llama dice de
    // qué contrato/factura sale el correo. Solo uuids válidos. Desde el 27-sep (LAW-343)
    // un envío SIN ancla se rechaza más abajo; un fallo al escribir el registro, en cambio,
    // nunca veta un correo que ya salió (se devuelve `registrado:false`).
    const esUuid = (s: string) => /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s);
    // Con factura, el contrato del registro sale de la FILA (más abajo), no de lo que diga el navegador.
    let contratoId = esUuid(String(body.contrato_id ?? '')) ? String(body.contrato_id) : null;
    const facturaId  = esUuid(String(body.factura_id ?? ''))  ? String(body.factura_id)  : null;
    // Correo de SOLO TEXTO (`attach:false`) y `via` (26-sep-2026, LAW-336 pieza 5, paso E):
    // el enlace de firma, el aviso de anulación y la copia del firmado sin PDF salían del
    // navegador directo a send_email.php y era el navegador quien escribía la fila de
    // `correos_enviados` — podía apuntar un envío que no salió. Ahora pasan por aquí y la
    // fila la escribe el servidor tras el envío real. Solo con contrato: un correo de
    // texto libre sin documento al que colgarse no tiene por qué salir por esta puerta.
    const VIAS = ['enlace_firma', 'aviso_anulacion', 'firma'];
    const via = VIAS.includes(String(body.via ?? '')) ? String(body.via) : null;
    const soloTexto = body.attach === false;
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(to)) return json({ ok: false, error: 'destinatario_invalido' }, 400);
    if (soloTexto && (!contratoId || !message.trim())) return json({ ok: false, error: 'texto_sin_contrato_o_mensaje' }, 400);
    // LAW-343 (27-sep-2026): nada sale por aquí sin un contrato o una factura que quien envía pueda ver,
    // y todo envío queda en correos_enviados. Antes, un PDF sin ancla (HTML libre renderizado en servidor,
    // a cualquier dirección, con el correo de Lawang) salía sin registro.
    if (!contratoId && !facturaId) return json({ ok: false, error: 'envio_sin_contrato_ni_factura' }, 400);
    // Una factura va SIEMPRE con su PDF: marcarla enviada fija número, emisor y la fecha que cuenta
    // para plazos de cobro — no puede hacerlo un correo que no la llevaba (Administración, capa 1, 26-sep).
    if (soloTexto && facturaId) return json({ ok: false, error: 'factura_requiere_pdf' }, 400);
    // Con factura el papel lo pinta esta edge desde la fila: no hace falta (ni se usa) html ni pdf del navegador.
    if (!soloTexto && !facturaId && !html && !pdfManual) return json({ ok: false, error: 'falta_html_o_pdf' }, 400);
    // La factura tiene que ser SUYA (visible por RLS) ANTES de enviar: más abajo se
    // apunta el envío y se marca `enviada` con ese id, y `enviada=true` congela número
    // y emisor y veta el borrado — no puede hacerlo quien no puede ver la factura.
    // Se lee la fila ENTERA con esa misma sesión: de ella sale el papel (papelFactura). `*` y no una lista porque el
    // esquema del ERP maestro añade `rectifica_id`/`rectificacion_motivo`, que en Lawang no existen.
    let filaFactura: any = null;
    if (facturaId) {
      const { data: fv, error: eF } = await usuario.from('facturas').select('*').eq('id', facturaId).maybeSingle();
      if (eF || !fv) return json({ ok: false, error: 'factura_no_visible' }, 403);
      // LAW-37 (11-oct-2026): un documento anulado no sale al cliente. Antes se renderizaba y se
      // enviaba, y solo fallaba después la marca (factura_marca_enviada rechaza anulados desde la
      // 20261010231114): el cliente recibía un papel anulado y la pantalla decía «no se pudo marcar».
      // Se corta aquí, antes del render, del SMTP y del registro. `error` es texto: la pantalla lo enseña tal cual.
      if (fv.anulada === true) {
        return json({ ok: false, codigo: 'documento_anulado',
          error: 'Este documento está anulado: no se envía al cliente. Si hace falta, emite otro.' }, 409);
      }
      filaFactura = fv;
    }
    if (filaFactura) {
      // El registro de envíos se cuelga del contrato de la FILA: un contrato_id del navegador no puede apuntar el envío
      // de esta factura en otro contrato. Al venir de la fila (visible por RLS) no se vuelve a comprobar abajo.
      contratoId = esUuid(String(filaFactura.contrato_id ?? '')) ? String(filaFactura.contrato_id) : null;
      // Sin contenido: solo para saber cuándo deja la pantalla de mandarlo y se puede quitar de ella (#350).
      if (html || pdfManual) console.log('send-contract-email: factura con ' + (html ? 'html' : 'pdf_base64') + ' del navegador, ignorado');
    }
    // Y el contrato igual: el registro de envíos se lee como «quién lo tiene» y lo
    // escribe el service role — sin esto, cualquiera del equipo dejaba un envío falso
    // en un contrato que no puede ver (code-review, 26-sep-2026).
    if (contratoId && !filaFactura) {
      const { data: cv, error: eC } = await usuario.from('contratos').select('id').eq('id', contratoId).maybeSingle();
      if (eC || !cv) return json({ ok: false, error: 'contrato_no_visible' }, 403);
    }

    // El enlace de firma, solo a su firmante y con su enlace (ver motivoEnlaceFirmaNoVale). Detrás de la RLS del contrato.
    if (via === 'enlace_firma' && contratoId) {
      const malo = await motivoEnlaceFirmaNoVale(contratoId, to, message);
      if (malo) ultimoEnvio.delete(claveCd);   // un rechazo no gasta la espera: se corrige y se reenvía al momento
      if (malo === 'no_se_pudo_comprobar') return json({ ok: false, codigo: malo, error: 'No se ha podido comprobar el enlace de firma: vuelve a intentarlo.' }, 500);
      if (malo === 'destinatario_no_es_el_firmante') return json({ ok: false, codigo: malo, error: 'Este correo no es el del firmante del enlace vivo de este contrato. Genera el enlace para esa persona y envíalo desde ahí.' }, 409);
      if (malo) return json({ ok: false, codigo: malo, error: 'El mensaje tiene que llevar el enlace de firma vigente: vuelve a generarlo o pega el enlace en el texto.' }, 409);
    }

    // AXW-202 C3: con el interruptor en «cola», el aviso de anulación lo manda la cola (ver encolaAvisoAnulacion).
    if (via === 'aviso_anulacion' && soloTexto && contratoId) {
      const enc = await encolaAvisoAnulacion(contratoId, to);
      if (enc) return json({ ok: true, encolado: true, duplicado: enc.duplicado });
    }

    // El papel de la factura, desde la fila, ANTES de render, copia, SMTP, registro y marca (#350).
    let htmlRender = html;
    if (filaFactura) {
      const cat = await leeCatalogoPapel(filaFactura, usuario);
      if (!cat) return json({ ok: false, error: 'no_se_pudo_generar_el_pdf' }, 500);
      const papel = papelFactura(cajaCompartidos(), filaFactura, cat, SITIO);
      if (!papel.ok) return json({ ok: false, codigo: papel.codigo, error: papel.error }, 409);
      htmlRender = papel.html;
    }

    let pdfB64 = '';
    if (soloTexto) {
      // nada que renderizar
    } else if (htmlRender || filaFactura) {
      if (!RENDER_SECRET) return json({ ok: false, error: 'render_no_configurado' }, 500);
      try {
        const rr = await fetch(RENDER_URL.replace(/\/$/, '') + '/render-pdf', {
          method: 'POST',
          headers: { 'content-type': 'application/json', 'X-Render-Secret': RENDER_SECRET },
          body: JSON.stringify({ html: htmlRender }),
        });
        if (!rr.ok) throw new Error('render http ' + rr.status);
        pdfB64 = b64(new Uint8Array(await rr.arrayBuffer()));
      } catch (e) {
        // El render falló: si hay un PDF adjuntado a mano de respaldo, se usa —solo en un contrato: el PDF de una
        // factura del navegador NO se acepta nunca (#350), así que ahí es 502 y no sale nada—;
        // si no, se corta aquí con un error explícito. Mandar el email sin
        // adjunto y sin avisar sería peor que el 403 — el usuario creería que
        // el contrato salió y no salió nada.
        if (pdfManual && !filaFactura) { pdfB64 = pdfManual; }
        else {
          console.error('render: ' + String((e as Error)?.message ?? e));
          return json({ ok: false, error: 'no_se_pudo_generar_el_pdf' }, 502);
        }
      }
    } else {
      pdfB64 = pdfManual;
    }

    // PRUEBA DE LO QUE SALIÓ, SOLO FACTURAS (LAW-343, 27-sep-2026, Seguridad + revisor de código): el PDF de
    // una factura lo manda el navegador, y un agente podía enviar al comprador una factura con otra cuenta que
    // el sistema registraba como «la enviada». Se guarda copia (bucket privado `correos-enviados`, solo
    // service role, nombre = sha256: la misma factura reenviada no se duplica), huella, tamaño y mensaje.
    // NUNCA en los correos de contrato: su mensaje lleva el enlace de firma con el token crudo o una URL
    // firmada del PDF, y `correos_enviados` la lee quien ve el contrato. Se prepara ANTES de enviar; si
    // falla, el envío sigue (se anota en el log) — la prueba no veta un correo.
    const prueba: Record<string, unknown> = {};
    const TOPE_COPIA = 25 * 1024 * 1024;
    if (facturaId && pdfB64 && pdfB64.length * 0.75 <= TOPE_COPIA) {
      try {
        const bytes = Uint8Array.from(atob(pdfB64), (c) => c.charCodeAt(0));
        const h = [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))].map((x) => x.toString(16).padStart(2, '0')).join('');
        const ruta = 'facturas/' + h + '.pdf';
        const { error: eCp } = await admin.storage.from('correos-enviados').upload(ruta, bytes, { contentType: 'application/pdf', upsert: false });
        // «ya existe» = la misma factura, byte a byte, ya se envió antes: la copia sirve igual
        if (eCp && !/exists|duplicate/i.test(eCp.message)) console.error('copia del PDF enviado: ' + eCp.message);
        else prueba.pdf_path = ruta;
        prueba.pdf_sha256 = h; prueba.pdf_bytes = bytes.length; prueba.mensaje = message.slice(0, 20000);
      } catch (e) { console.error('copia del PDF enviado: ' + String((e as Error)?.message ?? e)); }
    }

    // Solo se pregunta por el interruptor cuando el PDF pasa del tope: un envío normal no paga una consulta más.
    if (pdfB64.length > TOPE_PDF_EDGE && await modoColaCopias()) {
      return json({ ok: false, codigo: 'pdf_demasiado_grande',
        error: 'Este PDF pesa más de 25 MB y no se puede mandar por correo. Se entrega por el portal del comprador (o desde la intranet, si es para el estudio).' }, 413);
    }
    const dest = await destinoEnvio(pdfB64.length);
    const r = await fetch(dest.url, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'X-Render-Secret': dest.secreto, 'X-Llamante': 'send-contract-email' },
      body: JSON.stringify(soloTexto ? { to, subject, message, attach: false }
                                     : { to, subject, message, filename, pdf_base64: pdfB64 }),
    });
    const t = await r.text();
    // el detalle (puede llevar host o usuario SMTP) va al log del servidor, no al navegador
    if (!r.ok || !t.includes('"ok":true')) {
      console.error('send_email.php: ' + t.slice(0, 500));
      return json({ ok: false, error: 'no_se_pudo_enviar_el_correo' }, 502);
    }

    // Registro de envíos (correos_enviados): el correo YA salió — si el log
    // falla se anota en consola y se devuelve ok igualmente, porque devolver
    // error aquí haría que el usuario lo reenviara por duplicado.
    // `registrado:false` se devuelve (no error) para que la pantalla lo DIGA: esta tabla se
    // lee como «quién lo tiene», y una fila que falta acaba en un reenvío duplicado.
    let registrado: boolean | undefined;
    if (contratoId || facturaId) {
      const { error: eLog } = await admin.from('correos_enviados').insert({
        contrato_id: contratoId, factura_id: facturaId,
        para: to, asunto: subject,
        via: facturaId ? 'factura' : (via ?? 'manual'),
        enviado_por: quien.user.email ?? null,
        ...prueba,
      });
      registrado = !eLog;
      if (eLog) console.error('correos_enviados: ' + eLog.message);
    }
    // Marcar la factura como enviada AQUÍ, en el servidor y justo tras el envío
    // (26-sep-2026, «Operaciones atómicas»): antes lo hacía la pantalla en una segunda
    // llamada y, si fallaba, la factura seguía «sin enviar» y se reenviaba. Va con la
    // sesión del usuario: su RLS y los guardarraíles de facturas (que se apartan con
    // auth.uid() nulo) se aplican igual que antes. Si no se puede marcar, se DICE
    // (`marcada:false`) sin devolver error: el correo ya salió y reenviarlo sería peor.
    // La fecha es la del PRIMER envío (Administración, 26-sep-2026): es la que cuenta
    // para plazos y reclamaciones de cobro, y un reenvío no la mueve. Por eso el update
    // solo toca facturas aún sin enviar, y un reenvío (0 filas) que encuentra la factura
    // ya marcada cuenta como marcada.
    // Desde el 26-sep-2026 (frontera frontend/backend, LAW-336) la marca va por la RPC
    // `factura_marca_enviada`: `authenticated` deja de poder escribir en `facturas`
    // directamente, y un update con la sesión del usuario dejaría de marcar SIN que nadie
    // lo notara (rev. previa #119, Datos). La RPC aplica la misma regla de edición, no
    // mueve la fecha de un reenvío y devuelve true si la factura queda marcada.
    let marcada: boolean | undefined;
    if (facturaId) {
      const { data: m, error: eM } = await usuario.rpc('factura_marca_enviada', { p_id: facturaId });
      marcada = !eM && m === true;
      if (!marcada) console.error('factura ' + facturaId + ' enviada pero SIN marcar: ' + (eM?.message ?? 'la RPC devolvió ' + String(m)));
    }
    return json({ ok: true, marcada, registrado });
  } catch (e) {
    console.error('send-contract-email error interno: ' + String((e as Error)?.stack ?? e));
    return json({ ok: false, error: 'error_interno' }, 500);
  }
});
