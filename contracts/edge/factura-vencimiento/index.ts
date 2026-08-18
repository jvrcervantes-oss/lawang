// factura-vencimiento — la factura de cada hito, emitida sola a D-3 y enviada
// al comprador. La dispara pg_cron a diario (05:00 UTC); no la llama ningún
// navegador. Desplegar con verify_jwt=false: la puerta es X-Cron-Secret,
// generado dentro de la base (Vault) y leído aquí con la service key.
//
// ⚠️ LA HISTORIA QUE ESTA FUNCIÓN NO PUEDE REPETIR. El 11-ago se retiró la
// factura automática al firmar, por decisión del dueño y tras un balance real
// mal calculado: facturaba el hito BRUTO sin mirar lo ya cobrado. El encargo
// del 18-ago reabre la vía con otro disparador (la fecha), y esta versión
// lleva los guardarraíles que aquella no tenía — cada uno responde a un fallo
// concreto de entonces:
//   · el importe es lo PENDIENTE según la cascada (assets compartidos, la misma
//     función probada en node que usa el dashboard), nunca el hito bruto;
//   · idempotente: factura_id marca el vencimiento y no se factura dos veces —
//     ni aunque el cron dispare dos veces, ni aunque alguien llame a mano;
//   · no_facturar por vencimiento: lo negociado aparte no recibe robots;
//   · tope de 8 por ejecución: un error de datos jamás se convierte en una
//     remesa masiva a compradores reales;
//   · solo contratos FIRMADOS y fechas de hoy a hoy+3 — lo vencido del pasado
//     lo gestiona una persona, no un robot que llega tarde;
//   · copia al estudio de cada envío, y modo {"dry":true} que cuenta qué haría
//     sin escribir ni enviar nada (es como se verifica tras desplegar).
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { FUENTES, EXPORTA } from './compartidos.generated.ts';

const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const RENDER_URL = Deno.env.get('RENDER_URL') || 'https://contracts-pdf-service-production.up.railway.app';
const RENDER_SECRET = Deno.env.get('RENDER_SECRET') || '';
const SITIO = (Deno.env.get('SITIO_URL') || 'https://lawangproperties.com').replace(/\/$/, '');
const ESTUDIO_EMAIL = Deno.env.get('ESTUDIO_EMAIL') || 'jcervantes@lawangproperties.com';
const TOPE_POR_EJECUCION = 8;
const DIAS_ANTES = 3;

// El mismo cajón compartido que firma-submit: dinero, vocabulario, entities,
// totales, compradores, documento y la lógica de la cascada — generado por
// tools/empaqueta_edge.py desde los ficheros del repo, sin red por el medio.
let CAJA: Record<string, any> | null = null;
function caja(): Record<string, any> {
  if (CAJA) return CAJA;
  const c: Record<string, any> = {};
  new Function('caja', FUENTES.join('\n;\n') + '\n;Object.assign(caja,{' + EXPORTA.join(',') + '});')(c);
  CAJA = c;
  return c;
}

const b64 = (u8: Uint8Array) => {
  let s = '';
  for (let i = 0; i < u8.length; i += 0x8000) s += String.fromCharCode(...u8.subarray(i, i + 0x8000));
  return btoa(s);
};

async function enviarEmail(p: { to: string; subject: string; message: string; filename?: string; pdfB64?: string }) {
  const r = await fetch(SITIO + '/contracts/api/send_email.php', {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'X-Render-Secret': RENDER_SECRET },
    body: JSON.stringify({
      to: p.to, subject: p.subject, message: p.message,
      ...(p.pdfB64 ? { filename: p.filename || 'documento.pdf', pdf_base64: p.pdfB64 } : { attach: false }),
    }),
  });
  const t = await r.text();
  if (!r.ok || !t.includes('"ok":true')) throw new Error('email a ' + p.to + ': ' + t.slice(0, 180));
}

const hoyISO = () => new Date().toISOString().slice(0, 10);
const masDias = (iso: string, n: number) => {
  const d = new Date(iso + 'T00:00:00Z'); d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
};

Deno.serve(async (req) => {
  const json = (o: unknown, s = 200) =>
    new Response(JSON.stringify(o), { status: s, headers: { 'content-type': 'application/json' } });
  if (req.method !== 'POST') return json({ error: 'metodo' }, 405);
  if (!RENDER_SECRET) return json({ error: 'config' }, 500);

  // ── la puerta: el secreto de Vault, comparado con el que trae la petición ──
  const { data: esperado, error: eSec } = await sb.rpc('cron_facturas_secret');
  if (eSec || !esperado) return json({ error: 'sin_secreto_configurado' }, 500);
  if ((req.headers.get('x-cron-secret') || '') !== esperado) return json({ error: 'no_autorizado' }, 401);

  const body = await req.json().catch(() => ({}));
  const dry = body.dry === true;
  const C = caja();
  const hoy = hoyISO();

  // ── candidatos: firmados, con fecha en [hoy, hoy+3], sin factura, sin opt-out
  const { data: cands, error: eCand } = await sb.from('contrato_vencimientos')
    .select('id, contrato_id, orden, descripcion, pct, monto, fecha, ' +
            'contratos!inner(id, numero, tipo, precio_total, moneda, proyecto_nombre, bloqueado, contrato_padre_id)')
    .gte('fecha', hoy).lte('fecha', masDias(hoy, DIAS_ANTES))
    .is('factura_id', null).eq('no_facturar', false)
    .eq('contratos.bloqueado', true)
    .order('fecha').limit(40);
  if (eCand) return json({ error: 'no_se_pudieron_leer_vencimientos: ' + eCand.message }, 500);

  const emitidas: string[] = [], saltadas: string[] = [];

  for (const v of (cands ?? [])) {
    if (emitidas.length >= TOPE_POR_EJECUCION) {
      saltadas.push('tope de ' + TOPE_POR_EJECUCION + ' por ejecución alcanzado — el resto, mañana');
      break;
    }
    const ct = (v as any).contratos;
    const etiqueta = (ct.numero || 'sin nº') + ' hito ' + v.orden + ' (' + v.fecha + ')';
    try {
      // Una Carta de Reserva no recibe facturas de robot: su importe no es de
      // fiar por definición (regla del 14-ago). Ni ningún tipo sin calendario.
      if (C.lwEsPreliminar(ct.tipo)) { saltadas.push(etiqueta + ': tipo preliminar, no se factura solo'); continue; }

      // ── lo pendiente DE VERDAD: la cascada del contrato entero ──────────
      const [vencs, cobradoPropio, hijos] = await Promise.all([
        sb.from('contrato_vencimientos').select('id, orden, pct, monto, fecha').eq('contrato_id', v.contrato_id),
        sb.rpc('contrato_cobrado', { p_contrato_id: v.contrato_id }),
        sb.from('contratos').select('id, tipo').eq('contrato_padre_id', v.contrato_id),
      ]);
      if (vencs.error) throw new Error('vencimientos del contrato: ' + vencs.error.message);
      let cobrado = Number(cobradoPropio.data) || 0;
      for (const h of (hijos.data ?? [])) {
        if (!C.lwEsPreliminar(h.tipo)) continue;   // solo la señal de su Carta descuenta aquí
        const r = await sb.rpc('contrato_cobrado', { p_contrato_id: h.id });
        cobrado += Number(r.data) || 0;
      }
      const anotados = C.cascada(vencs.data ?? [], ct, cobrado, hoy);
      const yo = anotados.find((x: any) => x.id === v.id);
      if (!yo || yo.importe == null) { saltadas.push(etiqueta + ': importe no calculable (ni monto ni pct sobre precio) — lo revisa una persona'); continue; }
      if (!(yo.pendiente > 0)) { saltadas.push(etiqueta + ': ya cubierto por lo cobrado — no se pide dos veces'); continue; }

      if (dry) { emitidas.push('[DRY] ' + etiqueta + ' → ' + C.fmtMoneda(yo.pendiente, ct.moneda || 'EUR')); continue; }

      // ── la factura, con la misma forma que produce /facturas/ ───────────
      const { data: fila_ct, error: eCt } = await sb.from('contratos')
        .select('fields:datos->fields, extras:datos->compradores').eq('id', v.contrato_id).single();
      if (eCt || !fila_ct) throw new Error('no se pudo leer el contrato: ' + (eCt?.message ?? 'sin fila'));
      const f = (fila_ct as any).fields || {};
      const moneda = f.moneda || ct.moneda || 'EUR';
      const compradores = C.compradoresDeContrato(f, (fila_ct as any).extras);
      const descripcion = (v.descripcion || 'Hito ' + v.orden)
        + (yo.cubierto ? ' (parte ya entregada a cuenta: descontada)' : '')
        + ' — vence el ' + v.fecha;
      const lineas = [{ descripcion, importe: String(yo.pendiente) }];
      const campos: Record<string, string> = {
        tipo: 'factura',
        sociedad: f.sociedad_firmante && C.SOCIEDADES[f.sociedad_firmante] ? f.sociedad_firmante : 'tepi_sungai',
        cuenta: f.cuenta_bancaria && C.CUENTAS_BANCARIAS[f.cuenta_bancaria] ? f.cuenta_bancaria : '',
        fecha_emision: hoy, fecha_vencimiento: v.fecha, moneda,
        numero_visible: '', contrato_numero: ct.numero || '',
        cliente_nombre: C.nombresFactura(compradores),
        cliente_documento: C.documentosFactura(compradores),
        cliente_domicilio: C.primerDato(compradores, 'domicilio'),
        cliente_email: C.primerDato(compradores, 'email'),
        proyecto_nombre: [f.proyecto_nombre, f.parcela_codigo || f.villa_nombre || f.tipologia_villa].filter(Boolean).join(' — '),
        imp_etiqueta: '', imp_pct: '',   // el impuesto indonesio sigue sin confirmar: no se inventa
        notas: 'Vencimiento del ' + v.fecha + ' del contrato ' + (ct.numero || '') +
               '. Emitida automáticamente ' + DIAS_ANTES + ' días antes del vencimiento.',
      };
      const totales = C.calcTotales(lineas, moneda, { pct: '' });

      const ins = await sb.from('facturas').insert({
        tipo: 'factura', sociedad: campos.sociedad,
        cliente_nombre: campos.cliente_nombre || null, proyecto_nombre: campos.proyecto_nombre || null,
        contrato_numero: ct.numero || null, contrato_id: v.contrato_id,
        total: totales.total, moneda, fecha_emision: hoy,
        datos: { fields: { ...campos, lineas }, lineas, totales },
      }).select('id, numero').single();
      if (ins.error || !ins.data) throw new Error('no se pudo crear la factura: ' + (ins.error?.message ?? 'sin fila'));

      // El vencimiento queda marcado YA, con la factura recién creada: si el
      // PDF o el correo fallan luego, la factura EXISTE y el equipo la manda
      // desde /facturas/ — lo que no puede pasar es que mañana el cron emita
      // OTRA para el mismo hito porque el marcado llegara tarde.
      const marca = await sb.from('contrato_vencimientos').update({ factura_id: ins.data.id }).eq('id', v.id);
      if (marca.error) console.error('venc', v.id, 'facturado pero SIN marcar factura_id:', marca.error.message);

      campos.numero_visible = ins.data.numero;
      const html = C.documentoPagina({ ...campos, lineas }, { numero: ins.data.numero, base: SITIO });
      const rr = await fetch(RENDER_URL.replace(/\/$/, '') + '/render-pdf', {
        method: 'POST', headers: { 'content-type': 'application/json', 'X-Render-Secret': RENDER_SECRET },
        body: JSON.stringify({ html }),
      });
      if (!rr.ok) throw new Error('factura ' + ins.data.numero + ' creada, pero sin PDF: render ' + rr.status);
      const pdf = new Uint8Array(await rr.arrayBuffer());
      if (String.fromCharCode(...pdf.slice(0, 4)) !== '%PDF') throw new Error('factura ' + ins.data.numero + ' creada, pero el render no devolvió un PDF');

      const para = campos.cliente_email || ESTUDIO_EMAIL;
      const importe = C.fmtMoneda(totales.total, moneda);
      await enviarEmail({
        to: para,
        subject: 'Factura ' + ins.data.numero + ' · vencimiento del ' + v.fecha + ' · ' + (ct.numero || ''),
        message: 'Hola' + (compradores[0] ? ' ' + String(compradores[0].nombre).split(' ')[0] : '') + ',' +
          '\n\nEl próximo pago de tu contrato ' + (ct.numero || '') + ' vence el ' + v.fecha +
          '. Adjuntamos la factura ' + ins.data.numero + ' para que puedas realizarlo con tiempo.' +
          '\n\nConcepto: ' + descripcion +
          '\nImporte: ' + importe +
          '\n\nLos datos para la transferencia están en la propia factura. Si el pago ya está en camino, ignora este aviso.' +
          '\n\n\nLawang Tropical Properties',
        filename: ins.data.numero + '.pdf', pdfB64: b64(pdf),
      });
      const marcaEnv = await sb.from('facturas')
        .update({ enviada: true, fecha_envio: new Date().toISOString() }).eq('id', ins.data.id);
      if (marcaEnv.error) console.error('factura', ins.data.numero, 'enviada pero sin marcar enviada:', marcaEnv.error.message);
      if (para !== ESTUDIO_EMAIL) {
        await enviarEmail({
          to: ESTUDIO_EMAIL,
          subject: 'Factura ' + ins.data.numero + ' emitida sola (D-' + DIAS_ANTES + ') · ' + (ct.numero || ''),
          message: 'Factura ' + ins.data.numero + ' (' + importe + ') emitida automáticamente por el vencimiento del ' +
            v.fecha + ' de ' + (ct.numero || '') + ' y enviada a ' + para + '.\n\n' + descripcion,
          filename: ins.data.numero + '.pdf', pdfB64: b64(pdf),
        }).catch((e) => console.error('copia al estudio:', (e as Error).message));
      }
      emitidas.push(etiqueta + ' → ' + ins.data.numero + ' (' + importe + ') a ' + para);
    } catch (e) {
      saltadas.push(etiqueta + ': ERROR ' + String((e as Error).message).slice(0, 200));
      console.error('factura-vencimiento', etiqueta, e);
    }
  }

  console.log('factura-vencimiento', dry ? '[DRY]' : '', 'emitidas:', emitidas.length, '· saltadas:', saltadas.length);
  return json({ ok: true, dry, hoy, emitidas, saltadas });
});
