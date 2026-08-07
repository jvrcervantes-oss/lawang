// firma-submit — el comprador firma en firmar.html y esta función cierra el
// ciclo 100% automático: coge el snapshot de confianza, le mete la firma real +
// una página de auditoría, lo manda al render service (Puppeteer en Railway),
// sube el PDF a `contratos-firmados` y marca el contrato bloqueado.
// Desplegar con verify_jwt=false. Secreto necesario: RENDER_SECRET.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const RENDER_URL = Deno.env.get('RENDER_URL') || 'https://contracts-pdf-service-production.up.railway.app';
const RENDER_SECRET = Deno.env.get('RENDER_SECRET') || '';
// El sitio sirve el envío de correo (api/send_email.php) y los ficheros
// compartidos con los que se pinta la factura. Env var para poder apuntar a un
// entorno de pruebas sin tocar el código.
const SITIO = (Deno.env.get('SITIO_URL') || 'https://lawangproperties.com').replace(/\/$/, '');
// Copia del contrato firmado para el estudio. Va aparte de los compradores
// porque no es "un destinatario más": es el acuse que se archiva.
const ESTUDIO_EMAIL = Deno.env.get('ESTUDIO_EMAIL') || 'jcervantes@lawangproperties.com';
// Por encima de esto el PDF se manda como enlace y no como adjunto. Gmail y la
// práctica totalidad de servidores rechazan por encima de ~25 MB, y un contrato
// de Lawang con anexos llega a 20 MB de sobra (los anexos van en base64 dentro
// del jsonb). Un correo rebotado por tamaño es un contrato que el cliente NO
// recibe y de lo que nadie se entera.
const MAX_ADJUNTO = 15 * 1024 * 1024;

// Origen restringido: con '*' cualquier web podia lanzar la firma desde su
// pagina. El token sigue siendo la credencial, pero esto cierra el paso a que
// un tercero monte una pantalla de firma que parezca nuestra.
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
    Vary: 'Origin', // sin esto una CDN cachea el header de un origen y se lo sirve a otro
  };
};

async function sha256hex(s: string | Uint8Array): Promise<string> {
  const b = await crypto.subtle.digest('SHA-256', typeof s === 'string' ? new TextEncoder().encode(s) : s);
  return [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, '0')).join('');
}
const esc = (s: string) =>
  String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]!));

// página final de auditoría (trilingüe ES/EN/ID), a sangre de página nueva
function auditPage(d: { nombre: string; email: string; fechaISO: string; ip: string; numero: string; ref: string }) {
  const fecha = d.fechaISO.replace('T', ' ').replace(/\.\d+Z$/, ' UTC');
  const rows = [
    ['Firmante / Signer', esc(d.nombre) || '—'],
    ['Email', esc(d.email) || '—'],
    ['Fecha y hora / Date & time', fecha],
    ['IP', esc(d.ip) || '—'],
    ['Documento / Document', esc(d.numero) || '—'],
    ['Referencia de firma / Signature ref', esc(d.ref)],
  ].map(([k, v]) => `<tr><td style="padding:3mm 12mm 3mm 0;color:#6b6c66;white-space:nowrap">${k}</td><td style="font-weight:600">${v}</td></tr>`).join('');
  return `<div style="page-break-before:always;padding:26mm 20mm;font-family:'Jost',system-ui,sans-serif;color:#2E3437">
    <div style="font-size:13pt;letter-spacing:.28em;text-transform:uppercase;color:#485B37;font-weight:600">Registro de firma electrónica</div>
    <div style="font-size:10pt;letter-spacing:.24em;text-transform:uppercase;color:#8F9B7A;margin-top:2mm">Electronic Signature Record</div>
    <div style="font-size:10pt;letter-spacing:.24em;text-transform:uppercase;color:#8F9B7A;margin-top:1mm">Catatan Tanda Tangan Elektronik</div>
    <table style="border-collapse:collapse;font-size:11pt;margin-top:12mm">${rows}</table>
    <p style="font-size:8.5pt;color:#6b6c66;margin-top:16mm;line-height:1.6;max-width:150mm">
      Este documento fue firmado electrónicamente y a distancia por la persona identificada arriba, que declaró haber leído y aceptado su contenido. El presente registro deja constancia de dicha aceptación, la fecha/hora y la dirección IP desde la que se realizó.<br><br>
      This document was signed electronically and remotely by the person identified above, who declared having read and accepted its content. This record evidences such acceptance, the date/time and the IP address from which it was made.<br><br>
      Dokumen ini ditandatangani secara elektronik dan jarak jauh oleh orang yang diidentifikasi di atas, yang menyatakan telah membaca dan menerima isinya. Catatan ini membuktikan penerimaan tersebut, beserta tanggal/waktu dan alamat IP dari mana tanda tangan dilakukan.
    </p>
  </div>`;
}

// ═══════════════════════════════════════════════════════════════════════════
//  CIERRE DE CICLO — lo que pasa DESPUÉS de que el contrato quede sellado
//  ---------------------------------------------------------------------------
//  Nada de esta sección puede tumbar una firma. Cuando se llega aquí el PDF ya
//  está en el bucket con su hash y el contrato ya está bloqueado: el documento
//  es válido aunque falle el correo o la factura. Por eso cada pieza va en su
//  try/catch y lo que falla vuelve como `avisos`, no como error.
// ═══════════════════════════════════════════════════════════════════════════

/* Envío de correo por el endpoint del sitio (PHP con SMTP autenticado). No se
   monta un segundo emisor aquí: el remitente, el SMTP y el formato MIME ya
   están resueltos y probados en `contracts/api/send_email.php`. */
async function enviarEmail(p: {
  to: string; subject: string; message: string; filename?: string; pdfB64?: string;
}) {
  const r = await fetch(SITIO + '/contracts/api/send_email.php', {
    method: 'POST',
    /* `X-Render-Secret` autentica esta función ante send_email.php desde el
       6-ago-2026: ese endpoint ya no admite peticiones sin credencial (antes le
       bastaba `Origin`, que un curl se salta). Se reusa el secreto del servicio
       de render a propósito — esta función no tiene sesión de usuario, y crear un
       secreto nuevo habría dejado el arreglo pendiente de que el owner lo pusiera
       en dos sitios. Es el mismo valor que `private/mail.php.pdf_service_secret`.
       ponytail: si se rota, se rota en los dos lados. */
    headers: { 'content-type': 'application/json', 'X-Render-Secret': RENDER_SECRET },
    body: JSON.stringify({
      to: p.to, subject: p.subject, message: p.message,
      ...(p.pdfB64 ? { filename: p.filename || 'documento.pdf', pdf_base64: p.pdfB64 } : { attach: false }),
    }),
  });
  const t = await r.text();
  if (!r.ok || !t.includes('"ok":true')) throw new Error('email a ' + p.to + ': ' + t.slice(0, 200));
}

const b64 = (u8: Uint8Array) => {
  // en trozos: `String.fromCharCode(...u8)` con un PDF de MB revienta la pila
  let s = '';
  for (let i = 0; i < u8.length; i += 0x8000) s += String.fromCharCode(...u8.subarray(i, i + 0x8000));
  return btoa(s);
};

/* Los ficheros que pintan la factura son los MISMOS que usa /facturas/: se
   bajan del sitio y se ejecutan aquí. Así la factura que sale sola y la que
   emite una persona son el mismo documento — si mañana cambia una fila en
   documento.js, cambia en las dos. La alternativa era una segunda plantilla
   aquí dentro, que es exactamente lo que se dejaría vieja.
   ponytail: se ejecutan con `new Function` porque son <script> clásicos (los
   comparte una página HTML plana). Si esto dejara de estar permitido, la
   factura se salta con aviso y la firma sigue intacta. */
let COMPARTIDOS: Record<string, any> | null = null;
async function compartidos() {
  if (COMPARTIDOS) return COMPARTIDOS;
  const rutas = ['/contracts/assets/entities.js', '/facturas/totales.js',
                 '/facturas/compradores.js', '/facturas/documento.js'];
  const fuentes = await Promise.all(rutas.map(async (p) => {
    const r = await fetch(SITIO + p + '?v=' + Date.now());
    if (!r.ok) throw new Error('no se pudo cargar ' + p + ' (' + r.status + ')');
    return await r.text();
  }));
  const caja: Record<string, any> = {};
  new Function('caja', fuentes.join('\n;\n') +
    '\n;Object.assign(caja,{SOCIEDADES,CUENTAS_BANCARIAS,calcTotales,fmtMoneda,parseImporte,' +
    'compradoresDeContrato,nombresFactura,documentosFactura,primerDato,documentoPagina,TIPOS_DOC});')(caja);

  /* Las cuentas de cobro ya NO vienen dentro de entities.js (6-ago-2026): ese
     fichero se baja por HTTP público —sin sesión, es la razón de que las cuentas
     salieran de él— así que aquí se leen de la base con service_role, que es lo
     que esta función ya tiene. Se rellena el MISMO objeto que publicó el
     `new Function` de arriba, no uno nuevo: documento.js lee la global
     CUENTAS_BANCARIAS por referencia.
     Si esto fallara, la factura del primer hito saldría sin datos bancarios; se
     corta aquí en vez de emitirla muda, porque una factura sin dónde pagar es
     una factura que hay que reemitir. */
  const { data: cuentas, error: errCuentas } = await sb.from('cuentas_bancarias')
    .select('clave,label,titular,banco,cuenta,codigo,direccion,extra').eq('activa', true);
  if (errCuentas) throw new Error('no se pudieron leer las cuentas de cobro: ' + errCuentas.message);
  for (const c of cuentas ?? []) {
    caja.CUENTAS_BANCARIAS[c.clave] = { label: c.label, titular: c.titular, banco: c.banco,
      cuenta: c.cuenta, codigo: c.codigo, direccion: c.direccion, extra: c.extra };
  }

  COMPARTIDOS = caja;
  return caja;
}

/* El contrato firmado, al estudio y a cada comprador con email. El estudio
   siempre; los compradores, los que tengan dirección — a quien no la dio no se
   le inventa una. */
async function repartirFirmado(o: {
  numero: string; pdf: Uint8Array; path: string; compradores: any[]; proyecto: string;
}) {
  const grande = o.pdf.length > MAX_ADJUNTO;
  let enlace = '';
  if (grande) {
    // 30 días: el comprador tiene que poder volver a descargarlo sin pedirlo.
    const { data, error } = await sb.storage.from('contratos-firmados')
      .createSignedUrl(o.path, 30 * 24 * 3600);
    if (error || !data) throw new Error('no se pudo firmar el enlace de descarga: ' + (error?.message ?? ''));
    enlace = data.signedUrl;
  }
  const adjunto = grande ? {} : { pdfB64: b64(o.pdf), filename: o.numero + '_firmado.pdf' };
  const cola = [
    '', '', 'Lawang Tropical Properties',
    'PT TEPI SUN GAI · PT SAN DAL WOODS',
  ].join('\n');
  const pie = grande
    ? '\n\nEl documento pesa más de lo que admite el correo, así que va por enlace:\n' + enlace +
      '\n(El enlace caduca en 30 días. Si lo necesitas después, escríbenos.)'
    : '\n\nEl documento firmado va adjunto a este correo.';

  const errores: string[] = [];
  const destinos = [
    { to: ESTUDIO_EMAIL, estudio: true },
    ...o.compradores.filter((c) => c.email).map((c) => ({ to: c.email, nombre: c.nombre, estudio: false })),
  ];
  for (const d of destinos) {
    const asunto = d.estudio
      ? 'Contrato firmado · ' + o.numero + (o.proyecto ? ' · ' + o.proyecto : '')
      : 'Tu contrato firmado · ' + o.numero;
    const cuerpo = d.estudio
      ? 'Se ha completado la firma del contrato ' + o.numero + '.' +
        (o.proyecto ? '\nProyecto: ' + o.proyecto : '') +
        '\nFirmantes: ' + o.compradores.map((c) => c.nombre).join(', ') +
        '\n\nCopia para archivo.' + pie
      : 'Hola' + ((d as any).nombre ? ' ' + String((d as any).nombre).split(' ')[0] : '') + ',' +
        '\n\nHemos recibido tu firma. Aquí tienes tu copia del contrato ' + o.numero +
        (o.proyecto ? ' (' + o.proyecto + ')' : '') + ', ya firmado.' +
        '\n\nGuárdalo: es el documento con el registro de firma electrónica que acredita la operación.' +
        pie + cola;
    try { await enviarEmail({ to: d.to, subject: asunto, message: cuerpo, ...adjunto }); }
    catch (e) { errores.push(String((e as Error).message)); }
  }
  if (errores.length) throw new Error(errores.join(' | '));
}

/* Factura del PRIMER hito del calendario de pagos. El número lo pone el trigger
   de la base de datos (serie INV), nunca esta función: si lo calculara aquí, dos
   firmas simultáneas emitirían el mismo número.
   Se cobra UN hito, el primero — no los cuatro. Si el contrato no tiene
   calendario, o el primer hito no da importe, no se emite nada y se avisa: una
   factura con importe inventado es dinero mal pedido. */
async function facturarPrimerHito(o: { contratoId: string; numero: string; ct: any })
    : Promise<{ emitida: boolean; mensaje: string }> {
  const C = await compartidos();
  const f = o.ct.fields || {};
  const hitos = Array.isArray(o.ct.hitos) ? o.ct.hitos : [];
  if (!hitos.length) return { emitida: false, mensaje: 'contrato sin calendario de pagos: no se emite factura' };

  const moneda = f.moneda || o.ct.moneda || 'EUR';
  const precio = C.parseImporte(f.precio_total) || Number(o.ct.precio_total) || 0;
  const h = hitos[0];
  const pct = C.parseImporte(h.pct);
  const monto = C.parseImporte(h.monto) || (pct && precio ? Math.round(precio * pct / 100 * 100) / 100 : 0);
  if (!monto) return { emitida: false,
    mensaje: 'el primer hito no fija importe ni porcentaje sobre un precio conocido: no se emite factura' };

  const compradores = C.compradoresDeContrato(f, o.ct.extras);
  const hoy = new Date().toISOString().slice(0, 10);
  const descripcion = [h.es || h.en || 'Primer pago', pct ? '(' + pct + '% del precio acordado)' : '']
    .filter(Boolean).join(' ') + (h.timing ? ' — ' + h.timing : '');
  const lineas = [{ descripcion, importe: String(monto) }];

  // Misma forma que produce collect() en /facturas/, para que la factura se abra
  // ahí tal cual y se pueda corregir o anular como cualquier otra.
  const campos: Record<string, string> = {
    tipo: 'factura',
    sociedad: f.sociedad_firmante && C.SOCIEDADES[f.sociedad_firmante] ? f.sociedad_firmante : 'tepi_sungai',
    cuenta: f.cuenta_bancaria && C.CUENTAS_BANCARIAS[f.cuenta_bancaria] ? f.cuenta_bancaria : '',
    fecha_emision: hoy, fecha_vencimiento: '', moneda,
    numero_visible: '', contrato_numero: o.numero,
    cliente_nombre: C.nombresFactura(compradores),
    cliente_documento: C.documentosFactura(compradores),
    cliente_domicilio: C.primerDato(compradores, 'domicilio'),
    cliente_email: C.primerDato(compradores, 'email'),
    proyecto_nombre: [f.proyecto_nombre, f.parcela_codigo || f.villa_nombre || f.tipologia_villa]
      .filter(Boolean).join(' — '),
    // El impuesto va vacío a propósito: qué tipo aplica en Indonesia (PPN y su
    // porcentaje vigente) no está confirmado, y un porcentaje inventado en una
    // factura es dinero mal calculado.
    imp_etiqueta: '', imp_pct: '',
    notas: 'Primer hito del contrato ' + o.numero + '. Emitida automáticamente al completarse la firma.',
  };
  const totales = C.calcTotales(lineas, moneda, { pct: '' });

  const { data: fila, error } = await sb.from('facturas').insert({
    tipo: 'factura', sociedad: campos.sociedad,
    cliente_nombre: campos.cliente_nombre || null,
    proyecto_nombre: campos.proyecto_nombre || null,
    contrato_numero: o.numero, contrato_id: o.contratoId,
    total: totales.total, moneda, fecha_emision: hoy,
    datos: { fields: { ...campos, lineas }, lineas, totales },
  }).select('id, numero').single();
  if (error || !fila) throw new Error('no se pudo crear la factura: ' + (error?.message ?? 'sin fila'));

  // El número ya emitido tiene que salir impreso en el papel que se manda.
  campos.numero_visible = fila.numero;
  const html = C.documentoPagina({ ...campos, lineas }, { numero: fila.numero, base: SITIO });

  const rr = await fetch(RENDER_URL.replace(/\/$/, '') + '/render-pdf', {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'X-Render-Secret': RENDER_SECRET },
    body: JSON.stringify({ html }),
  });
  if (!rr.ok) throw new Error('factura ' + fila.numero + ' creada, pero no se pudo generar su PDF: render ' + rr.status);
  const pdf = new Uint8Array(await rr.arrayBuffer());
  if (String.fromCharCode(...pdf.slice(0, 4)) !== '%PDF')
    throw new Error('factura ' + fila.numero + ' creada, pero el render no devolvió un PDF');

  const para = campos.cliente_email || ESTUDIO_EMAIL;
  const importe = C.fmtMoneda(totales.total, moneda);
  await enviarEmail({
    to: para,
    subject: 'Factura ' + fila.numero + ' · ' + o.numero,
    message: 'Hola' + (compradores[0] ? ' ' + compradores[0].nombre.split(' ')[0] : '') + ',' +
      '\n\nAdjuntamos la factura ' + fila.numero + ' correspondiente al primer pago del contrato ' +
      o.numero + '.' +
      '\n\nConcepto: ' + descripcion +
      '\nImporte: ' + importe +
      '\n\nLos datos para la transferencia están en la propia factura.' +
      '\n\n\nLawang Tropical Properties',
    filename: fila.numero + '.pdf', pdfB64: b64(pdf),
  });
  // Copia al estudio, para que la emisión no dependa de mirar el panel.
  if (para !== ESTUDIO_EMAIL) {
    await enviarEmail({
      to: ESTUDIO_EMAIL,
      subject: 'Factura ' + fila.numero + ' emitida y enviada · ' + o.numero,
      message: 'Factura ' + fila.numero + ' (' + importe + ') emitida automáticamente al firmarse ' +
        o.numero + ' y enviada a ' + para + '.\n\n' + descripcion,
      filename: fila.numero + '.pdf', pdfB64: b64(pdf),
    });
  }
  return { emitida: true, mensaje: 'factura ' + fila.numero + ' emitida y enviada a ' + para };
}

/* Proforma del TOTAL del proyecto. `contracts/app.html` ya la crea al guardar
   el contrato por primera vez (con número asignado, sin enviar); aquí se
   RELEE precio_total y los datos del comprador —pueden haber cambiado entre
   ese guardado y esta firma— y se manda. Si no existiera (contrato de antes
   de este cambio, o falló su creación) se crea aquí mismo, con el mismo
   criterio que facturarPrimerHito: sin precio_total válido no se emite nada.
   Conviven con la factura real del primer hito a propósito (decisión del
   dueño, 7-ago): la proforma es informativa, no exigible; el hito 1 sí vence
   en este momento y necesita su propio documento con fuerza de cobro. */
async function enviarProformaTotal(o: { contratoId: string; numero: string; ct: any })
    : Promise<{ emitida: boolean; mensaje: string }> {
  const C = await compartidos();
  const f = o.ct.fields || {};
  const moneda = f.moneda || o.ct.moneda || 'EUR';
  const precio = C.parseImporte(f.precio_total) || Number(o.ct.precio_total) || 0;
  if (!precio) return { emitida: false, mensaje: 'contrato sin precio_total: no se emite proforma' };

  const compradores = C.compradoresDeContrato(f, o.ct.extras);
  const hoy = new Date().toISOString().slice(0, 10);
  const lineas = [{ descripcion: 'Total del proyecto', importe: String(precio) }];
  const campos: Record<string, string> = {
    tipo: 'proforma',
    sociedad: f.sociedad_firmante && C.SOCIEDADES[f.sociedad_firmante] ? f.sociedad_firmante : 'tepi_sungai',
    cuenta: f.cuenta_bancaria && C.CUENTAS_BANCARIAS[f.cuenta_bancaria] ? f.cuenta_bancaria : '',
    fecha_emision: hoy, fecha_vencimiento: '', moneda,
    numero_visible: '', contrato_numero: o.numero,
    cliente_nombre: C.nombresFactura(compradores),
    cliente_documento: C.documentosFactura(compradores),
    cliente_domicilio: C.primerDato(compradores, 'domicilio'),
    cliente_email: C.primerDato(compradores, 'email'),
    proyecto_nombre: [f.proyecto_nombre, f.parcela_codigo || f.villa_nombre || f.tipologia_villa]
      .filter(Boolean).join(' — '),
    imp_etiqueta: '', imp_pct: '',
    notas: 'Total del proyecto contratado en ' + o.numero + '. Documento informativo, sin validez fiscal — ' +
      'el cobro de cada pago se factura aparte, a medida que vence.',
  };
  const totales = C.calcTotales(lineas, moneda, { pct: '' });

  // La proforma que ya se creó al guardar el contrato (o.contratoId es FK real).
  const { data: existente, error: errBusca } = await sb.from('facturas')
    .select('id, numero').eq('contrato_id', o.contratoId).eq('tipo', 'proforma').eq('anulada', false)
    .order('created_at', { ascending: true }).limit(1).maybeSingle();
  if (errBusca) throw new Error('no se pudo buscar la proforma: ' + errBusca.message);

  let fila: { id: string; numero: string };
  if (existente) {
    // resync: el precio o los datos del comprador pudieron cambiar desde la creación
    const upd = await sb.from('facturas').update({
      sociedad: campos.sociedad, cliente_nombre: campos.cliente_nombre || null,
      proyecto_nombre: campos.proyecto_nombre || null, contrato_numero: o.numero,
      total: totales.total, moneda, fecha_emision: hoy,
      datos: { fields: { ...campos, lineas }, lineas, totales },
    }).eq('id', existente.id).select('id, numero').single();
    if (upd.error || !upd.data) throw new Error('no se pudo actualizar la proforma: ' + (upd.error?.message ?? ''));
    fila = upd.data;
  } else {
    const ins = await sb.from('facturas').insert({
      tipo: 'proforma', sociedad: campos.sociedad,
      cliente_nombre: campos.cliente_nombre || null, proyecto_nombre: campos.proyecto_nombre || null,
      contrato_numero: o.numero, contrato_id: o.contratoId,
      total: totales.total, moneda, fecha_emision: hoy,
      datos: { fields: { ...campos, lineas }, lineas, totales },
    }).select('id, numero').single();
    if (ins.error || !ins.data) throw new Error('no se pudo crear la proforma: ' + (ins.error?.message ?? ''));
    fila = ins.data;
  }

  campos.numero_visible = fila.numero;
  const html = C.documentoPagina({ ...campos, lineas }, { numero: fila.numero, base: SITIO });

  const rr = await fetch(RENDER_URL.replace(/\/$/, '') + '/render-pdf', {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'X-Render-Secret': RENDER_SECRET },
    body: JSON.stringify({ html }),
  });
  if (!rr.ok) throw new Error('proforma ' + fila.numero + ' creada, pero no se pudo generar su PDF: render ' + rr.status);
  const pdf = new Uint8Array(await rr.arrayBuffer());
  if (String.fromCharCode(...pdf.slice(0, 4)) !== '%PDF')
    throw new Error('proforma ' + fila.numero + ' creada, pero el render no devolvió un PDF');

  const para = campos.cliente_email || ESTUDIO_EMAIL;
  const importe = C.fmtMoneda(totales.total, moneda);
  await enviarEmail({
    to: para,
    subject: 'Factura proforma ' + fila.numero + ' · ' + o.numero,
    message: 'Hola' + (compradores[0] ? ' ' + compradores[0].nombre.split(' ')[0] : '') + ',' +
      '\n\nAdjuntamos la factura proforma ' + fila.numero + ' con el importe total del proyecto contratado en ' +
      o.numero + '.' +
      '\n\nImporte total: ' + importe +
      '\n\nEs un documento informativo, sin validez fiscal: el cobro de cada pago se factura aparte, ' +
      'a medida que vence.' +
      '\n\n\nLawang Tropical Properties',
    filename: fila.numero + '.pdf', pdfB64: b64(pdf),
  });
  const marcar = await sb.from('facturas')
    .update({ enviada: true, fecha_envio: new Date().toISOString() }).eq('id', fila.id);
  if (marcar.error) {
    console.error('proforma', fila.numero, 'enviada pero SIN marcar enviada=true:', marcar.error.message);
  }
  // Copia al estudio, para que la emisión no dependa de mirar el panel.
  if (para !== ESTUDIO_EMAIL) {
    await enviarEmail({
      to: ESTUDIO_EMAIL,
      subject: 'Proforma ' + fila.numero + ' emitida y enviada · ' + o.numero,
      message: 'Proforma ' + fila.numero + ' (' + importe + ') emitida automáticamente al firmarse ' +
        o.numero + ' y enviada a ' + para + '.',
      filename: fila.numero + '.pdf', pdfB64: b64(pdf),
    });
  }
  return { emitida: true, mensaje: 'proforma ' + fila.numero + ' emitida y enviada a ' + para };
}

Deno.serve(async (req) => {
  const cors = corsFor(req);
  const json = (o: unknown, s = 200) =>
    new Response(JSON.stringify(o), { status: s, headers: { ...cors, 'content-type': 'application/json' } });
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'metodo' }, 405);
  if (!RENDER_SECRET) return json({ error: 'config' }, 500);

  let claimedId: string | null = null;
  try {
    const { token, signature, typedName } = await req.json().catch(() => ({}));
    if (!token || typeof token !== 'string') return json({ error: 'token' }, 400);
    if (typeof signature !== 'string' || !signature.startsWith('data:image/png;base64,') || signature.length < 200)
      return json({ error: 'firma' }, 400);
    if (signature.length > 3_000_000) return json({ error: 'firma_grande' }, 413);

    const hash = await sha256hex(token);
    // reclama el token de forma atómica: solo un submit puede pasar de 'pendiente'
    // a 'procesando'. Evita doble firma / doble render por doble click o reintento.
    const { data: claimed } = await sb
      .from('contrato_firmas')
      .update({ estado: 'procesando' })
      .eq('token_hash', hash)
      .eq('estado', 'pendiente')
      .select('id, contrato_id, expira_en, snapshot_path, firmante_nombre, firmante_email, firmante_rol, contratos(numero)')
      .maybeSingle();
    if (!claimed) return json({ error: 'no_disponible' }, 409); // no existe, ya usado, o en proceso
    claimedId = claimed.id;

    if (new Date(claimed.expira_en) < new Date()) {
      await sb.from('contrato_firmas').update({ estado: 'pendiente' }).eq('id', claimed.id);
      return json({ error: 'expirado' }, 410);
    }

    const ip = (req.headers.get('x-forwarded-for') || '').split(',')[0].trim();
    const ua = (req.headers.get('user-agent') || '').slice(0, 400);
    const numero = (claimed as any).contratos?.numero || '';

    const { data: file, error: dlErr } = await sb.storage.from('contratos-firmados').download(claimed.snapshot_path);
    if (dlErr || !file) throw new Error('snapshot no disponible');
    let html = await file.text();

    // ── Firma en cadena: cada rol tiene SU centinela ────────────────────
    // adquiriente_1 → %%FIRMA_ADQUIRIENTE%% (histórico) · adquiriente_N → %%FIRMA_ADQ_N%%
    const rol = String(claimed.firmante_rol || 'adquiriente_1');
    const sent = rol === 'adquiriente_1' ? '%%FIRMA_ADQUIRIENTE%%' : `%%FIRMA_ADQ_${rol.split('_')[1]}%%`;
    if (html.includes(sent)) {
      html = html.replaceAll(sent, signature); // firma real dentro del <img src>
      // la auditoría se APILA: una página por firmante, en orden de firma
      const audit = auditPage({
        nombre: typedName || claimed.firmante_nombre || '',
        email: claimed.firmante_email || '',
        fechaISO: new Date().toISOString(),
        ip,
        numero,
        ref: claimed.id,
      });
      html = html.includes('</body>') ? html.replace('</body>', audit + '</body>') : html + audit;
    } else if (!html.includes(claimed.id)) {
      // sin centinela Y sin rastro de esta firma en el snapshot = documento sin
      // hueco para este rol (snapshot de antes de la cadena) — mejor fallar en
      // voz alta que producir un "firmado" sin la firma. Se regenera desde la app.
      throw new Error('el documento no tiene hueco de firma para ' + rol + ' — regenera el enlace desde la app');
    }
    // (si el snapshot ya lleva la referencia de esta firma es un REINTENTO tras
    // un fallo a mitad: la firma ya está estampada, se sigue sin duplicarla)

    // ── ¿Es la última firma de la cadena? ───────────────────────────────
    // Firmantes esperados = Adquiriente I (si tiene nombre) + adicionales con
    // identidad, leídos del propio contrato. Columnas concretas, nunca datos
    // entero: el jsonb pesa MB por los anexos en base64.
    // Columnas concretas, JAMÁS `datos` entero: el jsonb pesa MB por los anexos
    // en base64. `datos->fields` sí es texto plano (las firmas no viven ahí) y
    // hace falta al completo para el correo y la factura del primer hito.
    const { data: ct, error: ctErr } = await sb.from('contratos')
      .select('adq1:datos->fields->>adq1_nombre, extras:datos->compradores, ' +
              'fields:datos->fields, hitos:datos->hitos, precio_total, moneda, proyecto_nombre')
      .eq('id', claimed.contrato_id).single();
    if (ctErr || !ct) throw new Error('no se pudo leer el contrato: ' + (ctErr?.message ?? 'sin fila'));
    const extras = Array.isArray((ct as any).extras) ? (ct as any).extras : [];
    const conDatos = (c: unknown) => ['nombre', 'nacionalidad', 'pasaporte', 'domicilio', 'telefono', 'email']
      .some((k) => String((c as Record<string, unknown>)?.[k] ?? '').trim() !== '');
    const total = Math.max(1, (String((ct as any).adq1 ?? '').trim() ? 1 : 0) + extras.filter(conDatos).length);
    const { count: yaFirmadas, error: cntErr } = await sb.from('contrato_firmas')
      .select('id', { count: 'exact', head: true })
      .eq('contrato_id', claimed.contrato_id).eq('estado', 'firmado');
    if (cntErr) throw new Error('no se pudo contar las firmas: ' + cntErr.message);
    const esUltima = (yaFirmadas ?? 0) + 1 >= total;

    if (!esUltima) {
      // ── Firma INTERMEDIA: no hay PDF ni bloqueo todavía ───────────────
      // 1) guardar el documento CON esta firma como snapshot vivo del contrato
      //    (path fijo por contrato_id) — es lo que recibirá el siguiente
      //    firmante. Si esto falla se lanza: un "ok" con el snapshot sin
      //    guardar significaría que el siguiente firma un documento al que le
      //    falta una firma, y nadie se enteraría (el fallo que FIRMA_EN_CADENA
      //    marca como el peor). El catch devuelve el token a pendiente y el
      //    reintento es limpio (el snapshot original sigue intacto).
      const snapPath = `pendientes/${claimed.contrato_id}.html`;
      const save = await sb.storage.from('contratos-firmados')
        .upload(snapPath, new Blob([html], { type: 'text/html' }), { contentType: 'text/html', upsert: true });
      if (save.error) throw new Error('no se pudo guardar el documento firmado: ' + save.error.message);
      // 2) marcar la firma (si falla, el catch devuelve el token a pendiente;
      //    el reintento detecta la firma ya estampada por la referencia y no
      //    la duplica — ver guard de arriba)
      const media = await sb.from('contrato_firmas').update({
        estado: 'firmado', firmado_en: new Date().toISOString(), firmante_ip: ip, firmante_user_agent: ua,
      }).eq('id', claimed.id);
      if (media.error) throw new Error('no se pudo registrar la firma: ' + media.error.message);
      // 3) anular pendientes sueltos (regeneraciones viejas) — informativo, la
      //    app ya anula al generar el siguiente enlace; solo se deja rastro
      const barrida = await sb.from('contrato_firmas').update({ estado: 'anulado' })
        .eq('contrato_id', claimed.contrato_id).eq('estado', 'pendiente');
      if (barrida.error) console.error('pendientes sin anular en', claimed.contrato_id, ':', barrida.error.message);
      return json({ ok: true, numero, faltan: total - ((yaFirmadas ?? 0) + 1) });
    }
    // ── ÚLTIMA firma: renderizar, sellar y bloquear (flujo original) ─────

    // render con Chromium real (mismo servicio que el email de contratos)
    const rr = await fetch(RENDER_URL.replace(/\/$/, '') + '/render-pdf', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'X-Render-Secret': RENDER_SECRET },
      body: JSON.stringify({ html }),
    });
    if (!rr.ok) throw new Error('render ' + rr.status + ' ' + (await rr.text()).slice(0, 200));
    const pdf = new Uint8Array(await rr.arrayBuffer());
    if (pdf.length < 5 || String.fromCharCode(...pdf.slice(0, 4)) !== '%PDF') throw new Error('render no devolvió PDF');

    // La ruta la decide la FIRMA, no el contrato. Antes era `<numero>.pdf`, que
    // rompía de dos formas distintas y en silencio (28-jul-2026):
    //   · dos adquirientes del mismo contrato -> el 2º machacaba el PDF del 1º
    //     y solo sobrevivía la última firma;
    //   · "Subir firmado" en app.html usaba ESA MISMA ruta, así que una subida
    //     manual pisaba el PDF firmado a distancia, y al revés.
    // `claimed.id` es además la "Referencia de firma" impresa en la página de
    // auditoría del propio PDF: el nombre del fichero es rastreable al registro.
    // `upsert:true` se mantiene a propósito: ahora la ruta es única por firma,
    // así que reescribir solo puede pisar el reintento de ESA misma firma.
    const path = `${numero || 'contrato'}_${claimed.id}.pdf`;
    // hash ANTES de subir: con el bucket en upsert, el registro es la única
    // prueba de integridad del documento (UU ITE 11/2008 la exige para que el
    // PDF valga como evidencia).
    const pdfHash = await sha256hex(pdf);
    const up = await sb.storage.from('contratos-firmados').upload(path, pdf, { contentType: 'application/pdf', upsert: true });
    if (up.error) throw up.error;

    // ── Cierre del ciclo ────────────────────────────────────────────────
    // TODO update se comprueba. `.update()` de supabase-js NO lanza: devuelve
    // `{ error }`. Sin mirarlo, un fallo aquí dejaba al comprador con un PDF
    // sellado como firmado mientras el registro decía otra cosa, y la función
    // respondía ok:true. Documento y registro contradiciéndose es el peor
    // escenario probatorio posible; peor que fallar de forma visible.
    // Si algo falla se lanza: el `catch` devuelve el token a 'pendiente' y el
    // comprador puede reintentar. El PDF se sube con upsert, así que el
    // reintento lo reescribe sin duplicar.

    // 1) marcar la firma ANTES de bloquear el contrato. Si fallara el bloqueo,
    //    queda una firma registrada sin contrato bloqueado — detectable y
    //    reparable. Al revés (contrato bloqueado sin firma registrada) es un
    //    contrato cerrado del que nadie sabe quién lo firmó.
    const marcada = await sb.from('contrato_firmas').update({
      estado: 'firmado', firmado_en: new Date().toISOString(), firmante_ip: ip, firmante_user_agent: ua,
    }).eq('id', claimed.id);
    if (marcada.error) throw new Error('no se pudo registrar la firma: ' + marcada.error.message);

    // 2) bloquear el contrato (mismo efecto que "Subir firmado" manual)
    const bloqueo = await sb.from('contratos')
      .update({ bloqueado: true, pdf_firmado_path: path, pdf_firmado_hash: pdfHash })
      .eq('id', claimed.contrato_id);
    if (bloqueo.error) throw new Error('no se pudo bloquear el contrato: ' + bloqueo.error.message);

    // 3) `pdf_path` es informativo (cada firma guarda SU pdf; el de `contratos`
    //    solo apunta al último) y va en su propio update: si la columna no
    //    existiera todavía, PostgREST rechazaría el lote ENTERO y tumbaría la
    //    transición de estado, que es la crítica.
    //    Aquí NO se lanza: la firma ya es válida sin este dato. Pero se deja
    //    rastro en los logs de la función, porque un fallo silencioso era
    //    justamente el problema: el comentario decía "es solo un dato que
    //    falta" y nadie se enteraba de que faltaba.
    const ruta = await sb.from('contrato_firmas').update({ pdf_path: path, pdf_hash: pdfHash }).eq('id', claimed.id);
    if (ruta.error) {
      console.error('firma', claimed.id, 'firmada pero SIN pdf_path/pdf_hash:', ruta.error.message,
                    '— el PDF está en', path, 'con sha256', pdfHash);
    }

    // 4) cadena completa → ningún enlace debe sobrevivir (regla: al completarse
    //    la última firma se anulan TODOS los pendientes del contrato)
    const barridaFinal = await sb.from('contrato_firmas').update({ estado: 'anulado' })
      .eq('contrato_id', claimed.contrato_id).eq('estado', 'pendiente');
    if (barridaFinal.error) console.error('pendientes sin anular al cerrar', claimed.contrato_id, ':', barridaFinal.error.message);

    // ── A PARTIR DE AQUÍ el contrato ya es válido y está sellado ───────────
    // Reparto del firmado y factura del primer hito. Van FUERA del camino
    // crítico y cada uno en su try: si el correo o la factura fallan, la firma
    // no se deshace ni se devuelve un error al comprador —que ya firmó y no
    // puede hacer nada al respecto—. Se avisa por logs y en la respuesta.
    const avisos: string[] = [];
    const compradores = [
      { nombre: String((ct as any).adq1 ?? '').trim(), email: String((ct as any).fields?.adq1_email ?? '').trim() },
      ...extras.filter(conDatos).map((c: any) => ({ nombre: String(c.nombre ?? '').trim(), email: String(c.email ?? '').trim() })),
    ].filter((c) => c.nombre);

    try {
      await repartirFirmado({ numero, pdf, path, compradores,
                              proyecto: String((ct as any).proyecto_nombre ?? (ct as any).fields?.proyecto_nombre ?? '') });
    } catch (e) {
      const m = 'contrato ' + numero + ' firmado pero NO repartido por email: ' + (e as Error).message;
      console.error(m); avisos.push(m);
    }

    try {
      const r = await facturarPrimerHito({ contratoId: claimed.contrato_id, numero, ct });
      console.log('firma', claimed.id, '·', r.mensaje);
      if (!r.emitida) avisos.push(r.mensaje);   // no emitir puede ser lo correcto, pero nunca en silencio
    } catch (e) {
      const m = 'contrato ' + numero + ' firmado pero SIN factura del primer hito: ' + (e as Error).message;
      console.error(m); avisos.push(m);
    }

    try {
      const r = await enviarProformaTotal({ contratoId: claimed.contrato_id, numero, ct });
      console.log('firma', claimed.id, '·', r.mensaje);
      if (!r.emitida) avisos.push(r.mensaje);
    } catch (e) {
      const m = 'contrato ' + numero + ' firmado pero SIN proforma del total: ' + (e as Error).message;
      console.error(m); avisos.push(m);
    }

    return json({ ok: true, numero, faltan: 0, ...(avisos.length ? { avisos } : {}) });
  } catch (e) {
    // deja el token reutilizable para que el comprador pueda reintentar
    if (claimedId) await sb.from('contrato_firmas').update({ estado: 'pendiente' }).eq('id', claimedId);
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
