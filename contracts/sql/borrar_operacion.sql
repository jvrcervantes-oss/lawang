-- ============================================================================
-- Borrar una operación entera — 31-jul-2026 (última reescritura: 22-sep-2026)
-- ----------------------------------------------------------------------------
-- Una "operación" no es un contrato: es el contrato padre, los que cuelgan de
-- él (reserva → bloqueo → obra), sus enlaces de firma y sus facturas. Borrar
-- solo el padre dejaba los hijos huérfanos, los enlaces de firma VIVOS —o sea,
-- alguien con el enlace podía seguir firmando un contrato que ya no existe— y
-- las facturas apuntando al vacío.
--
-- Qué hace con cada cosa, y por qué:
--   · enlaces de firma pendientes  → ANULADOS. Un token vivo de un contrato
--     borrado es un documento que se puede firmar sin que nadie lo vea venir.
--   · facturas emitidas            → ANULADAS, no borradas. Borrarlas deja un
--     hueco en la serie fiscal que un contable no puede explicar; anularlas deja
--     el rastro, que es justo lo que hace falta.
--   · comisión ya devengada        → PURGADA (comisiones_devengadas + su
--     solicitud_pago), salvo que esa solicitud ya esté 'pagada' — en ese caso
--     la función para en seco sin borrar nada. Decisión explícita del owner
--     (22-sep-2026), ver
--     supabase/migrations/20260922134500_borrar_operacion_purga_comision_devengada.sql
--     para el porqué completo (hallazgo de Administración tras el fix de
--     facturas_contrato_obligatorio, que hizo alcanzable por primera vez este
--     camino: antes el CHECK de facturas fallaba antes de llegar aquí), y
--     supabase/migrations/20260922141500_borrar_operacion_gate_pagada_no_cerrada.sql
--     para la corrección del nombre del estado (el esquema real usa 'pagada'
--     + pago_referencia/pagado_en, no 'cerrada'/factura_id como en la
--     migración original de solicitudes_pago), y
--     supabase/migrations/20260922143000_borrar_operacion_gate_pagada_cubre_closer.sql
--     porque una comisión de CLOSER pagada no lleva solicitud_id
--     (comisiones_devengadas_solicitud_solo_manager lo exige NULL para
--     closer) — el gate mira también el estado propio del devengo, no solo
--     el de su solicitud. Ampliado en
--     supabase/migrations/20260922150000_borrar_operacion_gate_aprobada_y_disputa.sql:
--     el gate también bloquea una solicitud 'aprobada' (ya visada para pago,
--     aunque no ejecutado) y un devengo 'en_disputa' (reclamación abierta) —
--     decisión del owner tras hallazgos MEDIA de Legal/Administración. Lo que
--     SÍ se purga (comisiones_devengadas + solicitudes_pago) deja rastro en
--     `public.borrados` desde
--     supabase/migrations/20260922150500_purga_comisiones_deja_rastro_en_borrados.sql
--     (reutiliza el trigger genérico de auditoría LAW-71, ya colgado de
--     contratos/facturas — mismo patrón, dos tablas más).
--   · contratos                    → BORRADOS (el padre y sus hijos, con
--     rastro en `public.borrados` desde LAW-71). El ON DELETE SET NULL de
--     facturas_contrato_id_fkey deja huérfanas (pero con contrato_numero
--     congelado, ver trg_facturas_congela_contrato_numero) las facturas ya
--     anuladas del paso anterior — y desde
--     supabase/migrations/20260922140000_factura_anulada_permite_contrato_id_a_null.sql
--     eso ya no choca con la inmutabilidad de una factura anulada. Esa
--     excepción quedó acotada en
--     supabase/migrations/20260922151000_factura_anulada_contrato_null_solo_si_borrado.sql
--     a que el contrato realmente ya no exista — un super_admin YA NO puede
--     desvincular a mano una factura anulada de un contrato que sigue vivo
--     (hallazgo MEDIA de Seguridad: antes esa vía quedaba abierta y sin rastro).
--   · unidades                     → vuelven a `disponible` solas, por el
--     trigger `libera_unidad_sin_contrato`.
--
-- Va en una función y no en la aplicación porque son pasos que tienen que
-- pasar TODOS o NINGUNO: a mitad de camino queda una operación con las facturas
-- anuladas y los contratos todavía vivos, que es peor que no haber empezado.
--
-- Verificado en vivo end-to-end (22-sep-2026, transacciones de prueba con
-- ROLLBACK, auth.uid() real simulado): factura reciente anulada sobrevive al
-- borrado del contrato con contrato_numero intacto; comisión pendiente se
-- purga junto al contrato y deja rastro en `borrados`; comisión pagada (closer
-- o manager), en disputa, o con solicitud aprobada bloquea la operación entera
-- sin dejar nada a medias; un UPDATE manual de contrato_id=NULL sobre una
-- factura anulada con contrato vivo también queda bloqueado.
-- ============================================================================

create or replace function public.borrar_operacion(p_contrato_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  ids        uuid[];
  n_cont     int;
  n_firmas   int;
  n_fact     int;
  n_devengos int;
  n_solic    int;
  bloqueado_ajeno text;
  d_blindado_id uuid;
  solicitudes_a_purgar uuid[];
begin
  if not public.es_agente() then
    raise exception 'no autorizado';
  end if;

  -- El padre y sus hijos. Un solo nivel a propósito: hoy la cadena es
  -- reserva → obra y no hay nietos; si algún día los hubiera, es mejor que esto
  -- se quede corto y haya que repetirlo que no que arrastre de más.
  select array_agg(c.id) into ids
    from public.contratos c
   where c.id = p_contrato_id or c.contrato_padre_id = p_contrato_id;
  if ids is null then
    raise exception 'esa operación no existe';
  end if;

  -- El permiso se comprueba contrato a contrato con la MISMA regla que la policy
  -- de borrado: super admin siempre, o el autor si no está bloqueado. Si uno
  -- solo de la cadena no se puede borrar, no se borra nada — media operación
  -- borrada es un destrozo peor.
  if not public.es_super_admin() then
    select c.numero into bloqueado_ajeno
      from public.contratos c
     where c.id = any(ids)
       and (coalesce(c.bloqueado,false) = true
            or c.creado_por is null
            or c.creado_por <> (select auth.email()))
     limit 1;
    if bloqueado_ajeno is not null then
      raise exception 'El contrato % está firmado o es de otra persona: esta operación solo la puede borrar un super admin', bloqueado_ajeno;
    end if;
  end if;

  -- Gate: comisión pagada, en disputa, o con solicitud ya aprobada -- ninguna
  -- se purga sola. Solo 'pendiente' pasa de largo.
  select d.id into d_blindado_id
    from public.comisiones_devengadas d
    left join public.solicitudes_pago sp on sp.id = d.solicitud_id
   where d.contrato_raiz_id = any(ids)
     and (d.estado in ('pagada', 'en_disputa') or sp.estado in ('pagada', 'aprobada'))
   limit 1;
  if d_blindado_id is not null then
    raise exception 'Esta operación tiene una comisión pagada, en disputa o ya aprobada para pago (devengo %): no se puede borrar automáticamente, resuélvelo a mano', d_blindado_id;
  end if;

  update public.contrato_firmas set estado = 'anulado'
   where contrato_id = any(ids) and estado in ('pendiente','procesando');
  get diagnostics n_firmas = row_count;

  update public.facturas set anulada = true
   where contrato_id = any(ids) and coalesce(anulada,false) = false;
  get diagnostics n_fact = row_count;

  -- Orden importa: comisiones_devengadas.solicitud_id referencia
  -- solicitudes_pago(id) sin ON DELETE — hay que borrar el devengo primero.
  select array_agg(distinct d.solicitud_id) into solicitudes_a_purgar
    from public.comisiones_devengadas d
   where d.contrato_raiz_id = any(ids) and d.solicitud_id is not null;

  delete from public.comisiones_devengadas where contrato_raiz_id = any(ids);
  get diagnostics n_devengos = row_count;

  if solicitudes_a_purgar is not null then
    delete from public.solicitudes_pago where id = any(solicitudes_a_purgar);
    get diagnostics n_solic = row_count;
  else
    n_solic := 0;
  end if;

  delete from public.contratos where id = any(ids);
  get diagnostics n_cont = row_count;

  return jsonb_build_object(
    'contratos_borrados',   n_cont,
    'firmas_anuladas',      n_firmas,
    'facturas_anuladas',    n_fact,
    'comisiones_purgadas',  n_devengos,
    'solicitudes_purgadas', n_solic);
end $$;

revoke all on function public.borrar_operacion(uuid) from public, anon;
grant execute on function public.borrar_operacion(uuid) to authenticated;
