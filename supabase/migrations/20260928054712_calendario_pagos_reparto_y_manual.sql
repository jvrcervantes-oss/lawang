-- destructivo-ok: reemplaza contrato_calendario_monta y contrato_calendario_aplica con la misma firma y añade una función.
-- Arreglos de 20260928052131 pedidos por el revisor de código (28-sep-2026) antes de publicar la pantalla:
-- 1) [ALTA] Un calendario `manual` (montado por un admin) guardado por un agente conservaba los importes viejos
--    aunque cambiara el precio total (techo, extras, descuento): el documento imprimía un total que no cuadraba con
--    sus pagos, y sincroniza_vencimientos los pasaba a las facturas automáticas. Antes de 052131 la pantalla
--    recalculaba y el servidor lo guardaba; era una regresión. Ahora TODO hito `calculado` se rehace en el servidor
--    desde el precio, en cualquier calendario, con la misma regla que recalcularMontosHitos() (hitos_fechas.js):
--    round(total × pct) / 100 por hito y el hito `resto` absorbe la diferencia. Una sola función para todos.
-- 2) [MEDIA] Un calendario `manual` solo lo cambia un admin, como ya decían el comentario y la pantalla: un agente
--    podía pisarlo eligiendo otro calendario.

create or replace function public.contrato_calendario_reparte(p_hitos jsonb, p_precio numeric) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare
  v_out   jsonb := coalesce(p_hitos, '[]'::jsonb);
  v_rep   numeric := 0;
  v_imp   numeric;
  v_resto int := -1;
  i int;
begin
  if jsonb_typeof(v_out) <> 'array' then return v_out; end if;
  for i in 0 .. jsonb_array_length(v_out) - 1 loop
    if not coalesce((v_out->i->>'calculado')::boolean, false) then continue; end if;
    if coalesce((v_out->i->>'resto')::boolean, false) then
      v_resto := i;
    elsif coalesce(p_precio, 0) > 0 then
      v_imp := coalesce(round(p_precio * public.lw_importe(v_out->i->>'pct')) / 100, 0);
      v_rep := v_rep + v_imp;
      v_out := jsonb_set(v_out, array[i::text, 'monto'],
                         to_jsonb(case when v_imp > 0 then public.lw_importe_texto(v_imp) else '' end));
    else
      v_out := jsonb_set(v_out, array[i::text, 'monto'], '""');   -- sin precio no hay nada que repartir
    end if;
  end loop;
  if v_resto >= 0 then
    v_out := jsonb_set(v_out, array[v_resto::text, 'monto'],
                       to_jsonb(case when coalesce(p_precio, 0) > 0
                                     then public.lw_importe_texto(greatest(0, p_precio - v_rep)) else '' end));
  end if;
  return v_out;
end $$;

create or replace function public.contrato_calendario_monta(p_cal text, p_precio numeric, p_hitos jsonb,
                                                            p_base date, p_admin boolean) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_pre  jsonb := public.contrato_calendario_preset(p_cal);
  v_out  jsonb;
  v_fecha date;
  v_max  int;
begin
  if v_pre is null then raise exception 'Calendario de pagos desconocido: %', p_cal using errcode = '22023'; end if;
  v_out := public.contrato_calendario_reparte(v_pre, p_precio);

  if p_cal = 'unico_firma' then
    v_fecha := public.contrato_calendario_fecha(p_hitos->0->>'fecha', 'El vencimiento del pago único');
    if v_fecha is null then
      raise exception 'Pon la fecha de vencimiento del pago único.' using errcode = '23514';
    end if;
    if v_fecha < p_base then
      raise exception 'El pago único no puede vencer antes de la fecha de firma (%).', to_char(p_base, 'DD/MM/YYYY') using errcode = '23514';
    end if;
    v_max := public.parametro_num('construccion.pago_unico_max_dias', 90)::int;
    if not p_admin and v_fecha > p_base + v_max then
      raise exception 'El pago único vence como muy tarde % días después de la firma (%). Más allá lo decide un admin.',
        v_max, to_char(p_base + v_max, 'DD/MM/YYYY') using errcode = '23514';
    end if;
    v_out := jsonb_set(v_out, '{0,fecha}', to_jsonb(to_char(v_fecha, 'YYYY-MM-DD')));
  elsif p_cal = 'unico_obra' then
    v_fecha := public.contrato_calendario_fecha(p_hitos->0->>'fecha_estimada', 'La fecha estimada del pago único');
    if v_fecha is not null then
      if v_fecha < p_base then
        raise exception 'La fecha estimada del pago no puede ser anterior a la firma (%).', to_char(p_base, 'DD/MM/YYYY') using errcode = '23514';
      end if;
      v_out := jsonb_set(v_out, '{0,fecha_estimada}', to_jsonb(to_char(v_fecha, 'YYYY-MM-DD')));
    end if;
  end if;
  return v_out;
end $$;

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
                  where cv.contrato_id = p_contrato_id and (cv.ajustado or cv.factura_id is not null)) then
    raise exception 'Este contrato ya tiene pagos con fecha movida o facturados: no se puede cambiar de calendario. Habla con administración.'
      using errcode = '23514';
  end if;

  if v_cal in ('estandar', 'unico_firma', 'unico_obra') then
    v_hitos := public.contrato_calendario_monta(v_cal, p_precio, v_hitos, coalesce(p_fecha_firma, current_date), v_admin);
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

revoke all on function public.contrato_calendario_reparte(jsonb, numeric) from public, anon, authenticated;
revoke all on function public.contrato_calendario_monta(text, numeric, jsonb, date, boolean) from public, anon, authenticated;
revoke all on function public.contrato_calendario_aplica(jsonb, jsonb, numeric, date, uuid) from public, anon, authenticated;
