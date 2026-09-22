// libera-reservas-vencidas — libera sola la parcela de una Carta de Reserva
// (CR/CA/CH/CP) cuando su plazo contractual vence sin que exista detrás un
// Bloqueo de Parcela (RP, tipo='reserva_parcela') que la sustituya. Avisa a
// los managers un día antes por el mismo canal que ya usa el resto de la
// suite (_avisar_managers → notificaciones.email_pendiente → avisos-manager,
// 18/19-sep-2026) — no se inventa un canal nuevo.
//
// 22-sep-2026 (owner, revisión previa #41 Legal+Datos+Seguridad): PRÓRROGA +
// GRACIA. El vencimiento ya NO se calcula aquí: lo dice la base en
// `reservas_vencimiento()` (base + última prórroga registrada con
// `prorroga_reserva()`), un solo viaje sin traerse `datos` de 500 contratos.
// Y el día que vence NO se libera: se avisa «vencida hoy, se libera el D+3 si
// nadie prorroga o libera» y se libera a partir de D+3. Motivo del owner: «el
// cliente tarda en pagar y el sistema libera la parcela porque el Bloqueo no
// ha llegado a ocurrir». El aviso de gracia se manda UNA vez (se deduplica
// contra `notificaciones`), no cada día de la gracia.
//
// Disparada por pg_cron a diario (04:00 UTC, job
// `libera-reservas-vencidas-diario`); nunca por el navegador. Desplegar con
// verify_jwt=false: la puerta es X-Cron-Secret, comparado contra
// `cron_libera_reservas_secret()` — mismo patrón que factura-vencimiento.
//
// La cuota de reserva NO es reembolsable y el recibí ya emitido no se toca:
// esto solo libera la PARCELA (unidades.estado/contrato_id) y marca el
// contrato como liberado (contratos.liberado_en/liberado_motivo) — la lógica
// de qué puede tocarse, la validación atómica y el blindaje contra escritura
// directa viven en la función SQL `public.libera_reserva()`
// (`libera_reservas_vencidas.sql`), no aquí. Esta Edge solo decide QUÉ
// candidatos procesar y CUÁNDO avisar.
//
// El catálogo de "Carta de Reserva" NUNCA se escribe a mano aquí ni en la
// base: `reservas_vencimiento()` lo saca de `contrato_tipo_etapa`
// (etapa='reserva', menos el propio 'reserva_parcela', que es el Bloqueo y
// nunca se libera por vencimiento).
//
// ⚠️ COPIA REAL, NO SYMLINK (patrón firma-submit/factura-vencimiento,
// LAW-238): en un checkout Windows con `core.symlinks=false` un symlink de
// git se materializa como un stub de texto y desplegar eso tumba la función.
// `supabase/functions/libera-reservas-vencidas/index.ts` y
// `contracts/edge/libera-reservas-vencidas/index.ts` deben ser IDÉNTICAS
// (`tools/empaqueta_edge.py --check` lo vigila desde el 22-sep-2026).
import { createClient } from 'jsr:@supabase/supabase-js@2';

const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

// Tope por ejecución (mismo patrón que factura-vencimiento/avisos-manager):
// si se acumulan vencidas, no se liberan 300 de golpe.
const TOPE_POR_EJECUCION = 20;
// Días de gracia tras el vencimiento antes de liberar (owner, 22-sep-2026).
const DIAS_GRACIA = 3;

function hoyISO(): string {
  return new Date().toISOString().slice(0, 10);
}
function masDias(iso: string, dias: number): string {
  const d = new Date(iso + 'T00:00:00Z');
  d.setUTCDate(d.getUTCDate() + dias);
  return d.toISOString().slice(0, 10);
}
function fechaLarga(iso: string): string {
  const [y, m, d] = iso.split('-');
  return `${d}/${m}/${y}`;
}

type Candidata = {
  unidad_id: string; codigo: string; proyecto: string;
  contrato_id: string; numero: string | null; tipo: string;
  proyecto_id: string | null; proyecto_nombre: string | null; comprador_nombre: string | null;
  vence_el: string | null; n_prorrogas: number;
};

Deno.serve(async (req) => {
  const json = (o: unknown, s = 200) =>
    new Response(JSON.stringify(o), { status: s, headers: { 'content-type': 'application/json' } });
  if (req.method !== 'POST') return json({ error: 'metodo' }, 405);

  // ── la puerta: el secreto de Vault, comparado con el que trae el cron ──────
  const { data: esperado, error: eSec } = await sb.rpc('cron_libera_reservas_secret');
  if (eSec || !esperado) return json({ error: 'sin_secreto_configurado' }, 500);
  if ((req.headers.get('x-cron-secret') || '') !== esperado) return json({ error: 'no_autorizado' }, 401);

  const body = await req.json().catch(() => ({}));
  const dry = body.dry === true;
  const hoy = hoyISO();
  const manana = masDias(hoy, 1);

  // ── candidatos + vencimiento, en un viaje: parcela reservada, contrato de
  // tipo Carta de Reserva, no liberado. Si el contrato hizo traspaso a un
  // Bloqueo, unidades.contrato_id ya apunta al RP y la función lo excluye sola.
  const { data: cands, error: eCand } = await sb.rpc('reservas_vencimiento');
  if (eCand) return json({ error: 'no_se_pudieron_leer_candidatos: ' + eCand.message }, 500);

  const emitidas: string[] = [];
  const avisadas: string[] = [];
  const saltadas: string[] = [];
  let procesadas = 0;

  for (const c of ((cands ?? []) as Candidata[])) {
    const etiqueta = (c.numero || c.contrato_id) + ' · ' + c.proyecto + ' ' + c.codigo;
    const vence = c.vence_el ? String(c.vence_el).slice(0, 10) : null;
    if (!vence) { saltadas.push(etiqueta + ': sin fecha_pago_reserva o sin validez, no se inventa'); continue; }
    const liberaEl = masDias(vence, DIAS_GRACIA);
    const enlace = '/intranet/operaciones/?contrato=' + c.contrato_id;
    const prorrogas = c.n_prorrogas > 0 ? ' · ' + c.n_prorrogas + ' prórroga(s)' : '';

    if (vence === manana) {
      // ── aviso 1 día antes — mismo canal que el resto de la suite ──────────
      if (dry) { avisadas.push('[DRY D-1] ' + etiqueta); continue; }
      const { error: eAv } = await sb.rpc('_avisar_managers', {
        p_proyecto_id: c.proyecto_id,
        p_tipo: 'reserva_por_vencer',
        p_titulo: 'Reserva ' + (c.numero || '') + ' vence mañana',
        p_detalle: (c.comprador_nombre || 'Comprador') + ' · ' + (c.proyecto_nombre || c.proyecto) + ' ' +
          c.codigo + prorrogas + ' · sin Bloqueo de Parcela detrás — vence mañana; tras ' + DIAS_GRACIA +
          ' días de gracia se libera sola si nadie prorroga o libera',
        p_enlace: enlace,
        p_contrato_id: c.contrato_id,
      });
      if (eAv) saltadas.push(etiqueta + ': aviso previo fallo - ' + eAv.message);
      else avisadas.push(etiqueta);
      continue;
    }

    if (vence > hoy) continue; // no vence todavía y no es mañana: nada que hacer hoy

    if (hoy < liberaEl) {
      // ── vencida, en gracia: un solo aviso, aunque el cron corra 3 veces ────
      // (y si un día no corrió, el siguiente lo manda igual — no depende de
      // que hoy sea exactamente el día del vencimiento).
      const { data: ya, error: eYa } = await sb.from('notificaciones')
        .select('id').eq('contrato_id', c.contrato_id).eq('tipo', 'reserva_vencida_gracia').limit(1);
      if (eYa) { saltadas.push(etiqueta + ': no se pudo comprobar el aviso de gracia - ' + eYa.message); continue; }
      if ((ya ?? []).length) continue;
      if (dry) { avisadas.push('[DRY GRACIA] ' + etiqueta + ' (venció ' + vence + ', se libera ' + liberaEl + ')'); continue; }
      const { error: eAv } = await sb.rpc('_avisar_managers', {
        p_proyecto_id: c.proyecto_id,
        p_tipo: 'reserva_vencida_gracia',
        p_titulo: 'Reserva ' + (c.numero || '') + ' vencida — se libera el ' + fechaLarga(liberaEl),
        p_detalle: (c.comprador_nombre || 'Comprador') + ' · ' + (c.proyecto_nombre || c.proyecto) + ' ' +
          c.codigo + prorrogas + ' · venció el ' + fechaLarga(vence) + ' sin Bloqueo de Parcela detrás. ' +
          'Si el comprador sigue en ello, prorroga la reserva desde su ficha; si no, se libera sola el ' +
          fechaLarga(liberaEl),
        p_enlace: enlace,
        p_contrato_id: c.contrato_id,
      });
      if (eAv) saltadas.push(etiqueta + ': aviso de gracia fallo - ' + eAv.message);
      else avisadas.push(etiqueta + ' (gracia hasta ' + liberaEl + ')');
      continue;
    }

    // ── gracia agotada: liberar ──────────────────────────────────────────────
    if (procesadas >= TOPE_POR_EJECUCION) {
      saltadas.push(etiqueta + ': tope de ' + TOPE_POR_EJECUCION + ' por ejecución alcanzado — el resto, mañana');
      continue;
    }
    procesadas++;
    if (dry) { emitidas.push('[DRY] ' + etiqueta + ' (venció ' + vence + ', gracia hasta ' + liberaEl + ')'); continue; }

    const { error: eLib } = await sb.rpc('libera_reserva', {
      p_unidad_id: c.unidad_id,
      p_contrato_id: c.contrato_id,
      p_motivo: 'vencida_reserva',
      p_nota: null,
    });
    if (eLib) saltadas.push(etiqueta + ': ' + eLib.message);
    else emitidas.push(etiqueta + ' (venció ' + vence + ', liberada tras ' + DIAS_GRACIA + ' días de gracia)');
  }

  console.log(
    'libera-reservas-vencidas', dry ? '[DRY]' : '',
    'liberadas:', emitidas.length, '· avisadas:', avisadas.length, '· saltadas:', saltadas.length,
  );
  return json({ ok: true, dry, hoy, emitidas, avisadas, saltadas });
});
