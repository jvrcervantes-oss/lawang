-- Abono de la Carta: contar también la Carta TRASPASADA al Bloqueo (23-sep-2026).
--
-- Caso real: CR00061 (5.000 € cobrados) se colgó de RP00181 DESPUÉS de crear el
-- Bloqueo (evento 'traspaso', la intranet pone contrato_padre_id en la Carta).
-- carta_cobrado_calcula() solo buscaba (a) la Carta que ocupa hoy la parcela y
-- (b) la Carta liberada del mismo comprador. Tras el traspaso la parcela la ocupa
-- el propio Bloqueo y la Carta no está liberada, así que ni el INSERT ni
-- carta_cobrado_recalcula() la encontraban: el Bloqueo cobraba el 100 %.
--
-- Fix: tercera rama — Cartas cuyo contrato_padre_id es este Bloqueo. En un
-- INSERT el Bloqueo aún no tiene hijos, así que no cambia nada al crear; solo
-- actúa en el recálculo. Partida de la definición VIVA (pg_get_functiondef),
-- no de un .sql anterior.
create or replace function public.carta_cobrado_calcula(p_id uuid, p_datos jsonb, p_proyecto_nombre text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  datos jsonb := p_datos;
  cods text[] := (
    select coalesce(array_agg(distinct btrim(x)) filter (where btrim(x) <> ''), '{}')
      from unnest(string_to_array(coalesce(p_datos->'fields'->>'parcela_codigo',''), ',')) x);
  proy text := coalesce(nullif(btrim(p_datos->'fields'->>'proyecto_nombre'), ''), p_proyecto_nombre);
  moneda_bloqueo text := coalesce(nullif(btrim(p_datos->'fields'->>'moneda'), ''), 'EUR');
  ids_yo text[] := public.contrato_identificadores(p_datos);
  cartas_ids        uuid[];
  cartas_nums        text[];
  v_disponibles      numeric[] := '{}';
  v_nums_aportantes  text[] := '{}';
  v_cobrado          numeric := 0;
  v_precio_total     numeric;
  v_descuento        numeric;
  v_sobrante         numeric;
  v_restante         numeric;
  v_detalle          jsonb := '[]'::jsonb;
  v_disp             numeric;
  v_ya               numeric;
  v_claim            numeric;
  i                  int;
begin
  datos := datos #- '{fields,carta_cobrado_importe}'
                 #- '{fields,carta_cobrado_numeros}'
                 #- '{fields,carta_cobrado_sobrante}'
                 #- '{fields,carta_cobrado_detalle}';
  datos := public.carta_cobrado_aplica_hitos(datos, 'insert');

  if proy is null then
    return datos;
  end if;

  select array_agg(x.id order by x.misma desc, x.numero), array_agg(x.numero order by x.misma desc, x.numero)
    into cartas_ids, cartas_nums
    from (select y.id, y.numero, bool_or(y.misma) as misma from (
      -- la Carta que ocupa hoy la parcela (traspaso Carta -> Bloqueo, 17-sep)
      select distinct c.id, c.numero, true as misma
        from public.unidades u
        join public.contratos c on c.id = u.contrato_id
       where u.proyecto = proy and u.codigo = any(cods)
         and c.tipo like 'carta_reserva%'
         and coalesce(nullif(btrim(c.datos->'fields'->>'moneda'), ''), 'EUR') = moneda_bloqueo
      union
      -- la Carta ya colgada de este Bloqueo (traspaso posterior al alta, 23-sep)
      select c.id, c.numero, true
        from public.contratos c
       where c.contrato_padre_id = p_id
         and c.tipo like 'carta_reserva%'
         and coalesce(nullif(btrim(c.datos->'fields'->>'moneda'), ''), 'EUR') = moneda_bloqueo
      union
      -- la Carta LIBERADA del mismo comprador (22-sep): retenida e imputable
      select c.id, c.numero, false
        from public.contratos c
       where c.tipo like 'carta_reserva%'
         and c.liberado_en is not null
         and coalesce(nullif(btrim(c.datos->'fields'->>'moneda'), ''), 'EUR') = moneda_bloqueo
         and coalesce(array_length(ids_yo, 1), 0) > 0
         and public.contrato_identificadores(c.datos) && ids_yo
    ) y group by y.id, y.numero) x;

  if coalesce(array_length(cartas_ids, 1), 0) = 0 then
    return datos;
  end if;

  for i in 1 .. array_length(cartas_ids, 1) loop
    perform pg_advisory_xact_lock(hashtext(cartas_ids[i]::text));
    v_ya := coalesce((
      select sum(importe) from public.carta_cobrado_aplicado
       where carta_id = cartas_ids[i] and contrato_id <> p_id
    ), 0);
    v_disp := greatest(coalesce(public.contrato_cobrado(cartas_ids[i]), 0) - v_ya, 0);
    v_disponibles := v_disponibles || v_disp;
    v_cobrado := v_cobrado + v_disp;
  end loop;

  if v_cobrado <= 0 then
    return datos;
  end if;

  v_precio_total := greatest(coalesce(public.lw_importe(datos->'fields'->>'precio_total'), 0), 0);
  v_descuento := least(v_cobrado, v_precio_total);
  v_sobrante  := greatest(v_cobrado - v_precio_total, 0);

  if v_descuento > 0 then
    v_restante := v_descuento;
    for i in 1 .. array_length(cartas_ids, 1) loop
      exit when v_restante <= 0;
      v_disp := v_disponibles[i];
      if v_disp > 0 then
        v_claim := least(v_disp, v_restante);
        v_detalle := v_detalle || jsonb_build_object(
          'carta_id', cartas_ids[i],
          'numero', cartas_nums[i],
          'importe', public.lw_importe_texto(v_claim));
        v_nums_aportantes := v_nums_aportantes || cartas_nums[i];
        v_restante := v_restante - v_claim;
      end if;
    end loop;

    datos := jsonb_set(datos, '{fields,carta_cobrado_importe}', to_jsonb(public.lw_importe_texto(v_descuento)), true);
    datos := jsonb_set(datos, '{fields,carta_cobrado_numeros}', to_jsonb(array_to_string(v_nums_aportantes, ', ')), true);
    datos := jsonb_set(datos, '{fields,carta_cobrado_detalle}', v_detalle, true);

    insert into public.carta_cobrado_aplicado (contrato_id, carta_id, importe)
    select p_id, (elem->>'carta_id')::uuid, public.lw_importe(elem->>'importe')
      from jsonb_array_elements(v_detalle) elem
    on conflict (contrato_id, carta_id) do nothing;
  end if;

  if v_sobrante > 0 then
    datos := jsonb_set(datos, '{fields,carta_cobrado_sobrante}', to_jsonb(public.lw_importe_texto(v_sobrante)), true);
  end if;

  datos := public.carta_cobrado_aplica_hitos(datos, 'insert');
  return datos;
end;
$function$;
