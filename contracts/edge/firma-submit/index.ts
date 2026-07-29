// firma-submit — el comprador firma en firmar.html y esta función cierra el
// ciclo 100% automático: coge el snapshot de confianza, le mete la firma real +
// una página de auditoría, lo manda al render service (Puppeteer en Railway),
// sube el PDF a `contratos-firmados` y marca el contrato bloqueado.
// Desplegar con verify_jwt=false. Secreto necesario: RENDER_SECRET.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const RENDER_URL = Deno.env.get('RENDER_URL') || 'https://contracts-pdf-service-production.up.railway.app';
const RENDER_SECRET = Deno.env.get('RENDER_SECRET') || '';

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
    const { data: ct, error: ctErr } = await sb.from('contratos')
      .select('adq1:datos->fields->>adq1_nombre, extras:datos->compradores')
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

    return json({ ok: true, numero, faltan: 0 });
  } catch (e) {
    // deja el token reutilizable para que el comprador pueda reintentar
    if (claimedId) await sb.from('contrato_firmas').update({ estado: 'pendiente' }).eq('id', claimedId);
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
