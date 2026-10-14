CREATE OR REPLACE FUNCTION public._comision_devengo_reponer(p_id uuid, p_importe numeric, p_snap jsonb, p_motivo text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- Devuelve true si la fila repuesta ya estaba pagada (no toca crear solicitud) y false si vuelve a pendiente sin pagar.
declare
  d      public.comisiones_devengadas;
  v_sp   public.solicitudes_pago;
  v_vig  numeric;
  v_obj  numeric;
  v_dif  uuid;
  v_yo   text := nullif(lower(coalesce(auth.email(), '')), '');
begin
  select * into d from public.comisiones_devengadas where id = p_id for update;
  if d.id is null or d.estado <> 'anulada' or not d.anulado_por_modo then
    raise exception 'Solo se repone una comisión anulada por un cambio de modo de la venta' using errcode = '22023';
  end if;
  if d.solicitud_id is not null then
    select * into v_sp from public.solicitudes_pago sp where sp.id = d.solicitud_id;
  end if;
  -- su solicitud la rechazó un administrador: no renace (arreglo del revisor, 30-sep-2026)
  if v_sp.estado = 'rechazada' then
    raise exception 'La solicitud de pago de esta comisión se rechazó: no se repone, queda anulada' using errcode = '22023';
  end if;

  if d.pagado_en is null and v_sp.estado is distinct from 'pagada' then
    -- no se había pagado: vuelve a devengar con el importe de hoy; la solicitud vieja queda anulada con su rastro
    insert into public.comisiones_ajustes_log (tabla, fila_id, accion, importe_antes, importe_despues, estado_antes, estado_despues, motivo, copia)
    values ('comisiones_devengadas', d.id, 'reponer', coalesce(d.importe_ajustado, d.importe), p_importe, 'anulada', 'pendiente',
            p_motivo || ' — no se había pagado: vuelve a devengar',
            jsonb_build_object('solicitud_anterior', d.solicitud_id, 'anulado_motivo', d.anulado_motivo, 'anulado_en', d.anulado_en));
    update public.comisiones_devengadas
       set estado = 'pendiente', importe = p_importe,
           importe_ajustado = null, ajuste_motivo = null, ajustado_por = null, ajustado_en = null,
           anulado_motivo = null, anulado_por = null, anulado_en = null, anulado_por_modo = false,
           solicitud_id = null, disparado_en = now(),
           disparado_por_snapshot = coalesce(p_snap, '{}'::jsonb)
             || jsonb_build_object('repuesta_en', now(), 'importe_anterior', d.importe, 'solicitud_anterior', d.solicitud_id)
     where id = d.id;
    return false;
  end if;

  -- ya pagada: lo pagado no se reescribe ni se vuelve a pagar
  perform set_config('app.via_recalculo_comision', 'on', true);
  -- lo que valía justo antes del cambio de modo (lo guardó su diferencia negativa en importe_vigente)
  select x.importe_vigente into v_obj
    from public.comisiones_diferencias x
   where x.devengo_id = d.id and x.importe < 0 and x.origen->>'op' = 'cambio_modo'
   order by x.created_at desc limit 1;
  update public.comisiones_diferencias
     set estado = 'anulada', resuelto_por = 'sistema', resuelto_en = now(),
         resolucion_motivo = p_motivo || ': se repone la comisión ya pagada, no se descuenta'
   where devengo_id = d.id and estado = 'pendiente' and importe < 0 and origen->>'op' = 'cambio_modo';
  v_vig := coalesce(v_sp.importe, coalesce(d.importe_ajustado, d.importe))
         + coalesce((select sum(x.importe) from public.comisiones_diferencias x
                      where x.devengo_id = d.id and x.estado in ('pendiente', 'pagada', 'compensada')), 0);
  v_obj := coalesce(v_obj, v_vig);
  if round(v_obj - v_vig, 2) >= 0.01 then
    raise exception 'Esta comisión ya se pagó y se descontó: la regulariza administración a mano' using errcode = '22023';
    -- la diferencia negativa ya se había descontado de otro pago: se devuelve al mismo perceptor
    insert into public.comisiones_diferencias (devengo_id, importe, importe_vigente, importe_nuevo, base_antes, base_despues,
                                               motivo, estado, origen, provocado_por)
    values (d.id, round(v_obj - v_vig, 2), v_vig, v_obj,
            nullif(d.disparado_por_snapshot->>'base_valor', '')::numeric, nullif(d.disparado_por_snapshot->>'base_valor', '')::numeric,
            p_motivo || ' — ya estaba pagada y se había descontado: se devuelve lo descontado', 'pendiente',
            jsonb_build_object('tabla', 'contrato_closer', 'op', 'vuelta_modo', 'contrato_id', d.contrato_raiz_id, 'en', now(), 'quien', v_yo),
            v_yo)
    returning id into v_dif;
    insert into public.comisiones_ajustes_log (tabla, fila_id, accion, importe_antes, importe_despues, estado_antes, estado_despues, motivo, copia)
    values ('comisiones_diferencias', v_dif, 'diferencia', v_vig, v_obj, null, 'pendiente', p_motivo, jsonb_build_object('devengo_id', d.id));
    perform public._comision_diferencia_solicitud(v_dif);
  end if;
  insert into public.comisiones_ajustes_log (tabla, fila_id, accion, importe_antes, importe_despues, estado_antes, estado_despues, motivo, copia)
  values ('comisiones_devengadas', d.id, 'reponer', coalesce(d.importe_ajustado, d.importe), coalesce(d.importe_ajustado, d.importe),
          'anulada', case when d.pagado_en is not null then 'pagada' else 'pendiente' end,
          p_motivo || ' — ya estaba pagada: se repone sin volver a pagarla',
          jsonb_build_object('anulado_motivo', d.anulado_motivo, 'anulado_en', d.anulado_en, 'diferencia_devuelta', v_dif));
  update public.comisiones_devengadas
     set estado = case when d.pagado_en is not null then 'pagada' else 'pendiente' end,
         anulado_motivo = null, anulado_por = null, anulado_en = null, anulado_por_modo = false
   where id = d.id;
  perform set_config('app.via_recalculo_comision', 'off', true);
  return true;
end $function$
