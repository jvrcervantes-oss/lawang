-- destructivo-ok: reemplaza contrato_calendario_aplica con la misma firma; no toca datos.
-- Tercera pasada del revisor de código (28-sep-2026), [MEDIA]: el atajo que deja pasar una fecha de pago único ya
-- guardada (para que la de un admin más allá del tope no bloquee al agente) no miraba si la fecha de FIRMA había
-- cambiado. Guardar el pago a firma+90 y adelantar luego la firma dejaba el pago más allá del tope sin admin. Ahora
-- el atajo exige también la misma fecha de firma.

create or replace function public.contrato_calendario_aplica(p_datos jsonb, p_old_datos jsonb, p_precio numeric,
                                                             p_fecha_firma date, p_contrato_id uuid) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_admin   boolean := public.es_admin();
  v_old_cal text;
  v_cal     text := nullif(btrim(coalesce(p_datos->>'calendario', '')), '');
  v_hitos   jsonb := case when jsonb_typeof(p_datos->'hitos') = 'array' then p_datos->'hitos' else '[]'::jsonb end;
  v_old_h   jsonb;
  v_suma    numeric;
  i int;
begin
  if p_old_datos is not null then
    v_old_h := case when jsonb_typeof(p_old_datos->'hitos') = 'array' then p_old_datos->'hitos' else '[]'::jsonb end;
    v_old_cal := coalesce(nullif(p_old_datos->>'calendario', ''), public.contrato_calendario_deduce(v_old_h));
  end if;
  -- Una pestaña abierta antes de este cambio no manda `calendario`: se sigue con el que ya tenía, o, en un alta,
  -- con el que dicen sus hitos. Deducido del payload SOLO aquí, y lo que salga se valida igual abajo.
  if v_cal is null then v_cal := coalesce(v_old_cal, public.contrato_calendario_deduce(v_hitos)); end if;
  if v_cal not in ('estandar', 'unico_firma', 'unico_obra', 'manual', 'libre') then
    raise exception 'Calendario de pagos desconocido: %', v_cal using errcode = '22023';
  end if;

  if v_cal = 'libre' and v_old_cal is distinct from 'libre' and not v_admin then
    raise exception 'Elige el calendario de pagos: por hitos, pago único a la firma o pago único al inicio de obra.'
      using errcode = '23514';
  end if;
  if v_cal = 'manual' and v_old_cal is distinct from 'manual' and not v_admin then
    raise exception 'Un calendario de pagos a medida solo lo monta un admin.' using errcode = '42501';
  end if;
  if v_old_cal = 'manual' and v_cal <> 'manual' and not v_admin then
    raise exception 'Este calendario de pagos lo montó un admin: cambiar la forma de pago es cosa suya.' using errcode = '42501';
  end if;

  if p_old_datos is not null and v_cal is distinct from v_old_cal
     and exists (select 1 from public.contrato_vencimientos cv
                  where cv.contrato_id = p_contrato_id and (cv.ajustado or cv.factura_id is not null or coalesce(cv.no_facturar, false))) then
    -- `no_facturar` también (Datos, 28-sep): sincroniza_vencimientos conserva la marca por `orden`, así que el pago
    -- nuevo que cae en ese número la heredaría y el robot no lo facturaría nunca
    raise exception 'Este contrato ya tiene pagos con fecha movida, facturados o marcados «no facturar»: no se puede cambiar de calendario. Habla con administración.'
      using errcode = '23514';
  end if;

  if v_cal in ('estandar', 'unico_firma', 'unico_obra') then
    -- La fecha de un pago único que ya estaba guardada (quizá la puso un admin más allá del tope) no bloquea al agente
    -- que guarda el contrato por otra cosa: el tope solo se mira cuando la fecha cambia.
    v_hitos := public.contrato_calendario_monta(v_cal, p_precio, v_hitos, coalesce(p_fecha_firma, current_date),
                 -- coalesce: en un alta no hay calendario ni hitos viejos y la comparación da NULL, que
                 -- dentro de monta se leería como «no mires el tope»
                 v_admin or coalesce(v_cal = v_old_cal and coalesce(v_hitos->0->>'fecha', '') <> ''
                                     and v_hitos->0->>'fecha' = v_old_h->0->>'fecha'
                                     -- …y la firma tampoco se movió: adelantarla deja el pago más allá del tope
                                     -- (revisor de código, tercera pasada)
                                     and coalesce(p_datos->'fields'->>'fecha_firma', '')
                                         = coalesce(p_old_datos->'fields'->>'fecha_firma', ''), false));
  elsif v_cal = 'manual' and not v_admin then
    -- conserva la tabla guardada; solo deja mover la fecha de cada hito, como hasta hoy. Los importes se rehacen
    -- abajo con el precio de ahora.
    if jsonb_array_length(v_hitos) <> jsonb_array_length(v_old_h) then
      raise exception 'Este calendario de pagos lo montó un admin: añadir o quitar hitos es cosa suya.' using errcode = '42501';
    end if;
    for i in 0 .. jsonb_array_length(v_old_h) - 1 loop
      v_old_h := jsonb_set(v_old_h, array[i::text, 'fecha'],
                           to_jsonb(coalesce(to_char(public.contrato_calendario_fecha(v_hitos->i->>'fecha', 'El vencimiento del hito ' || (i + 1)), 'YYYY-MM-DD'), '')));
    end loop;
    v_hitos := public.contrato_calendario_reparte(v_old_h, p_precio);
  else
    -- libre (cualquiera, solo en un contrato que ya lo era) o manual de admin: la tabla es de quien la escribe,
    -- pero un agente no se fabrica marcas de fábrica, y ninguna tabla sale con importes negativos ni % que no cuadren
    if not v_admin and exists (select 1 from jsonb_array_elements(v_hitos) h where coalesce((h->>'fijo')::boolean, false)) then
      raise exception 'Este contrato no tiene calendario de fábrica: elige uno en vez de marcar hitos a mano.' using errcode = '42501';
    end if;
    select sum(public.lw_importe(h->>'pct')) into v_suma
      from jsonb_array_elements(v_hitos) h where coalesce(public.lw_importe(h->>'pct'), 0) > 0;
    if v_suma is not null and abs(v_suma - 100) > 0.01 then
      raise exception 'Los hitos suman % %%, no 100 %%.', v_suma using errcode = '23514';
    end if;
    for i in 0 .. jsonb_array_length(v_hitos) - 1 loop
      perform public.contrato_calendario_fecha(v_hitos->i->>'fecha', 'El vencimiento del hito ' || (i + 1));
    end loop;
    -- los hitos `calculado` salen del precio (los escritos a mano, no: son importes cerrados a propósito)
    v_hitos := public.contrato_calendario_reparte(v_hitos, p_precio);
    if exists (select 1 from jsonb_array_elements(v_hitos) h where public.lw_importe(h->>'monto') < 0) then
      raise exception 'Hay un hito con importe negativo.' using errcode = '23514';
    end if;
  end if;

  return jsonb_set(
           p_datos || jsonb_build_object('calendario', v_cal, 'hitos', v_hitos),
           '{fields}',
           (coalesce(p_datos->'fields', '{}'::jsonb) - 'clausula_pago')
             || case when v_cal in ('unico_firma', 'unico_obra') then jsonb_build_object('clausula_pago', v_cal) else '{}'::jsonb end);
end $$;

revoke all on function public.contrato_calendario_aplica(jsonb, jsonb, numeric, date, uuid) from public, anon, authenticated;
