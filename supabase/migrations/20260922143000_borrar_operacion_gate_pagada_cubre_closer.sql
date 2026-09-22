-- Hallazgo ALTA de Administración en la consulta de deploy del gate anterior
-- (20260922141500_borrar_operacion_gate_pagada_no_cerrada): ese gate solo
-- miraba `solicitudes_pago.estado = 'pagada'` vía el JOIN por `solicitud_id`.
-- Pero `comisiones_devengadas_solicitud_solo_manager` EXIGE `solicitud_id is
-- null` para nivel='closer' -- el cobro de un closer se resuelve
-- DIRECTAMENTE en `comisiones_devengadas.estado='pagada'` (columna con GRANT
-- explícito update(estado,pagado_por,pagado_en), usada desde
-- intranet/v4/assets/editores.js·datos.js), sin pasar nunca por
-- solicitudes_pago. Con el gate anterior, una comisión de CLOSER ya pagada no
-- disparaba el JOIN (solicitud_id es null) y se borraba en silencio junto con
-- el contrato -- exactamente el dinero ya movido que este gate existe para
-- proteger.
--
-- Verificado antes de escribir esto: comisiones_devengadas_estado_check
-- admite 'pendiente'/'pagada'/'en_disputa' en la propia tabla, independiente
-- de si hay solicitud_id.
--
-- Fix: el gate mira AMBAS fuentes de "ya pagada" -- el estado propio del
-- devengo (cubre closer) y el de su solicitud si la tiene (cubre manager).
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
  d_pagada_id uuid;
  solicitudes_a_purgar uuid[];
begin
  if not public.es_agente() then
    raise exception 'no autorizado';
  end if;

  select array_agg(c.id) into ids
    from public.contratos c
   where c.id = p_contrato_id or c.contrato_padre_id = p_contrato_id;
  if ids is null then
    raise exception 'esa operacion no existe';
  end if;

  if not public.es_super_admin() then
    select c.numero into bloqueado_ajeno
      from public.contratos c
     where c.id = any(ids)
       and (coalesce(c.bloqueado,false) = true
            or c.creado_por is null
            or c.creado_por <> (select auth.email()))
     limit 1;
    if bloqueado_ajeno is not null then
      raise exception 'El contrato % esta firmado o es de otra persona: esta operacion solo la puede borrar un super admin', bloqueado_ajeno;
    end if;
  end if;

  -- Gate: una comisión ya pagada no se purga sola -- ni la de closer (estado
  -- propio del devengo) ni la de manager (estado de su solicitud_pago).
  select d.id into d_pagada_id
    from public.comisiones_devengadas d
    left join public.solicitudes_pago sp on sp.id = d.solicitud_id
   where d.contrato_raiz_id = any(ids)
     and (d.estado = 'pagada' or sp.estado = 'pagada')
   limit 1;
  if d_pagada_id is not null then
    raise exception 'Esta operacion ya tiene una comision pagada (devengo %): no se puede borrar automaticamente, resuelvelo a mano', d_pagada_id;
  end if;

  update public.contrato_firmas set estado = 'anulado'
   where contrato_id = any(ids) and estado in ('pendiente','procesando');
  get diagnostics n_firmas = row_count;

  update public.facturas set anulada = true
   where contrato_id = any(ids) and coalesce(anulada,false) = false;
  get diagnostics n_fact = row_count;

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
grant execute on function public.borrar_operacion(uuid) to authenticated;;
