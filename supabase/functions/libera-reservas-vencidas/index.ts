// libera-reservas-vencidas — libera sola la parcela de una Carta de Reserva
// (CR/CA/CH/CP) cuando su plazo contractual vence sin que exista detrás un
// Bloqueo de Parcela (RP, tipo='reserva_parcela') que la sustituya. Avisa a
// los managers un día antes por el mismo canal que ya usa el resto de la
// suite (_avisar_managers → notificaciones.email_pendiente → avisos-manager,
// 18/19-sep-2026) — no se inventa un canal nuevo.
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
// El catálogo de "Carta de Reserva" NUNCA se escribe a mano aquí: sale de
// `contrato_tipo_etapa` (etapa='reserva', menos el propio 'reserva_parcela',
// que es el Bloqueo y nunca se libera por vencimiento).
//
// ⚠️ COPIA REAL, NO SYMLINK (patrón firma-submit/factura-vencimiento,
// LAW-238): en un checkout Windows con `core.symlinks=false` un symlink de
// git se materializa como un stub de texto y desplegar eso tumba la función.
// Esta copia y `contracts/edge/libera-reservas-vencidas/index.ts` deben
// mantenerse idénticas a mano — no hay caja compartida que empaquetar aquí
// (no usa compartidos.generated.ts), así que no entra en empaqueta_edge.py.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

// Tope por ejecución (mismo patrón que factura-vencimiento/avisos-manager):
// si se acumulan vencidas, no se liberan 300 de golpe.
const TOPE_POR_EJECUCION = 20;

function hoyISO(): string {
  return new Date().toISOString().slice(0, 10);
}
function masDias(iso: string, dias: number): string {
  const d = new Date(iso + 'T00:00:00Z');
  d.setUTCDate(d.getUTCDate() + dias);
  return d.toISOString().slice(0, 10);
}
function masMeses(iso: string, meses: number): string {
  const d = new Date(iso + 'T00:00:00Z');
  d.setUTCMonth(d.getUTCMonth() + meses);
  return d.toISOString().slice(0, 10);
}

async function tiposCartaReserva(): Promise<string[]> {
  const { data, error } = await sb.from('contrato_tipo_etapa')
    .select('tipo').eq('etapa', 'reserva').neq('tipo', 'reserva_parcela');
  if (error) throw new Error('catalogo de tipos: ' + error.message);
  return (data ?? []).map((r: { tipo: string }) => r.tipo);
}

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

  let tipos: string[];
  try {
    tipos = await tiposCartaReserva();
  } catch (e) {
    return json({ error: String((e as Error).message) }, 500);
  }
  if (tipos.length === 0) {
    return json({ ok: true, dry, hoy, emitidas: [], avisadas: [], saltadas: ['catalogo de tipos vacio'] });
  }

  // ── candidatos: parcela reservada, contrato de tipo Carta de Reserva, no
  // liberado ya. Si el contrato hizo traspaso a un Bloqueo de Parcela,
  // unidades.contrato_id ya apunta al RP (no a la Carta), así que el filtro
  // por tipo lo excluye solo — sin necesitar mirar el traspaso aquí.
  //
  // El hint `!unidades_contrato_id_fkey` es obligatorio desde que existe
  // unidades.contrato_liberado_id (esta misma migración): con dos FK de
  // unidades hacia contratos, PostgREST no puede elegir sola y el embed
  // falla con "more than one relationship was found" (verificado en vivo).
  // Y el `!inner` es igual de obligatorio: sin él, un filtro sobre el
  // embed (contratos.tipo/liberado_en) no excluye la fila de unidades — solo
  // deja el objeto `contratos` en null, y entonces `c.numero` revienta más
  // abajo con TypeError (verificado en vivo, segundo intento de esta misma
  // sesión).
  const { data: cands, error: eCand } = await sb.from('unidades')
    .select(
      'id, codigo, proyecto, estado, contrato_id, ' +
      'contratos!unidades_contrato_id_fkey!inner(id, numero, tipo, proyecto_id, proyecto_nombre, comprador_nombre, liberado_en, datos)',
    )
    .eq('estado', 'reservada')
    .not('contrato_id', 'is', null)
    .in('contratos.tipo', tipos)
    .is('contratos.liberado_en', null)
    .limit(500);
  if (eCand) return json({ error: 'no_se_pudieron_leer_candidatos: ' + eCand.message }, 500);

  const emitidas: string[] = [];
  const avisadas: string[] = [];
  const saltadas: string[] = [];
  let procesadas = 0;

  for (const u of (cands ?? [])) {
    // deno-lint-ignore no-explicit-any
    const c = (u as any).contratos;
    const etiqueta = (c.numero || c.id) + ' · ' + u.proyecto + ' ' + u.codigo;
    const fields = (c.datos && c.datos.fields) || {};
    const fecha = fields.fecha_pago_reserva ? String(fields.fecha_pago_reserva).slice(0, 10) : null;
    if (!fecha) { saltadas.push(etiqueta + ': sin fecha_pago_reserva, no se inventa'); continue; }

    const diasRaw = fields.validez_dias;
    const mesesRaw = fields.validez_meses;
    const dias = diasRaw != null && diasRaw !== '' ? Number(diasRaw) : null;
    const meses = mesesRaw != null && mesesRaw !== '' ? Number(mesesRaw) : null;

    let deadline: string | null = null;
    if (dias != null && !Number.isNaN(dias)) deadline = masDias(fecha, dias);
    else if (meses != null && !Number.isNaN(meses)) deadline = masMeses(fecha, meses); // NUNCA meses*30
    else { saltadas.push(etiqueta + ': sin validez_dias ni validez_meses, no se inventa'); continue; }

    if (deadline === manana) {
      // ── aviso 1 día antes — mismo canal que el resto de la suite ──────────
      if (dry) { avisadas.push('[DRY] ' + etiqueta); continue; }
      const { error: eAv } = await sb.rpc('_avisar_managers', {
        p_proyecto_id: c.proyecto_id,
        p_tipo: 'reserva_por_vencer',
        p_titulo: 'Reserva ' + (c.numero || '') + ' vence mañana',
        p_detalle: (c.comprador_nombre || 'Comprador') + ' · ' + (c.proyecto_nombre || u.proyecto) + ' ' +
          u.codigo + ' · sin Bloqueo de Parcela detrás — se libera sola mañana si nadie actúa',
        p_enlace: '/intranet/operaciones/?contrato=' + c.id,
        p_contrato_id: c.id,
      });
      if (eAv) saltadas.push(etiqueta + ': aviso previo fallo - ' + eAv.message);
      else avisadas.push(etiqueta);
      continue;
    }

    if (deadline > hoy) continue; // no vence todavía y no es mañana: nada que hacer hoy

    // ── vencida: liberar ─────────────────────────────────────────────────────
    if (procesadas >= TOPE_POR_EJECUCION) {
      saltadas.push(etiqueta + ': tope de ' + TOPE_POR_EJECUCION + ' por ejecución alcanzado — el resto, mañana');
      continue;
    }
    procesadas++;
    if (dry) { emitidas.push('[DRY] ' + etiqueta + ' (venció ' + deadline + ')'); continue; }

    const { error: eLib } = await sb.rpc('libera_reserva', {
      p_unidad_id: u.id,
      p_contrato_id: c.id,
      p_motivo: 'vencida_reserva',
      p_nota: null,
    });
    if (eLib) saltadas.push(etiqueta + ': ' + eLib.message);
    else emitidas.push(etiqueta + ' (venció ' + deadline + ')');
  }

  console.log(
    'libera-reservas-vencidas', dry ? '[DRY]' : '',
    'liberadas:', emitidas.length, '· avisadas:', avisadas.length, '· saltadas:', saltadas.length,
  );
  return json({ ok: true, dry, hoy, emitidas, avisadas, saltadas });
});
