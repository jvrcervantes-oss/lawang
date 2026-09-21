-- carta_cobrado_al_bloquear() causaba "canceling statement due to statement timeout"
-- en produccion (20+ veces el 21-sep-2026, incluida al menos un alta de contrato real
-- bloqueada). Medido antes de tocar: sumar lo ya aplicado de UNA carta tardaba 2.710 ms
-- y tocaba 12.722 buffers -- escaneaba los 116 contratos reserva_parcela y descomprimia
-- su `datos` JSONB entero por cada uno (problema TOAST ya diagnosticado el 24-ago,
-- LAW-78: nombrar cualquier rama de `datos` fuerza descomprimir la fila completa). El
-- trigger repetia esto UNA VEZ POR CADA carta implicada -- con 2+ cartas, sobra de
-- cualquier limite de tiempo razonable.
--
-- Verificado antes de escribir el backfill: 0 de 116 contratos reserva_parcela tienen
-- hoy `carta_cobrado_detalle`/`carta_cobrado_importe`/`carta_cobrado_sobrante` poblados
-- -- nadie ha completado nunca este flujo en produccion. NO hace falta backfill: la
-- tabla nace vacia y coincide exactamente con la realidad. Si algun dia esto deja de
-- ser cierto habria que revisar este comentario antes de reusar el patron.
--
-- ARREGLO: tabla lateral indexada por carta_id. El JSONB `carta_cobrado_detalle` sigue
-- siendo el histórico congelado que ya se enseña en el contrato (no se toca su lectura
-- de cara al usuario); solo cambia DE DONDE se lee la suma "cuanto se ha aplicado ya".
-- El dato tiene un dueño: esta tabla es la fuente de la suma, el JSONB es la copia
-- congelada para mostrar, escrita en el mismo momento desde el mismo v_detalle.

create table if not exists public.carta_cobrado_aplicado (
  id          uuid primary key default gen_random_uuid(),
  contrato_id uuid not null references public.contratos(id) on delete cascade,
  carta_id    uuid not null references public.contratos(id) on delete cascade,
  importe     numeric not null,
  creado_en   timestamptz not null default now(),
  unique (contrato_id, carta_id)
);
create index if not exists carta_cobrado_aplicado_por_carta
  on public.carta_cobrado_aplicado (carta_id);

alter table public.carta_cobrado_aplicado enable row level security;
revoke all on public.carta_cobrado_aplicado from anon, authenticated;
-- Ni SELECT directo: nadie necesita leer esta tabla desde el navegador, solo la usa
-- el trigger de abajo (SECURITY DEFINER). Mismo patron que contrato_closer/_log.

create or replace function public.carta_cobrado_al_bloquear()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  cods text[] := (
    select coalesce(array_agg(distinct btrim(x)) filter (where btrim(x) <> ''), '{}')
      from unnest(string_to_array(coalesce(new.datos->'fields'->>'parcela_codigo',''), ',')) x);
  proy text := coalesce(nullif(btrim(new.datos->'fields'->>'proyecto_nombre'), ''), new.proyecto_nombre);
  moneda_bloqueo text := coalesce(nullif(btrim(new.datos->'fields'->>'moneda'), ''), 'EUR');
  cartas_ids        uuid[];
  cartas_nums        text[];
  v_disponibles      numeric[] := '{}';
  v_nums_aportantes  text[] := '{}';
  v_cobrado          numeric := 0;
  v_precio_total     numeric;
  v_descuento        numeric;
  v_sobrante         numeric;
  v_hitos            jsonb;
  v_restante         numeric;
  v_monto            numeric;
  v_resta            numeric;
  v_detalle          jsonb := '[]'::jsonb;
  v_disp             numeric;
  v_ya               numeric;
  v_claim            numeric;
  i                  int;
begin
  if tg_op <> 'INSERT' or new.tipo <> 'reserva_parcela' then
    return new;
  end if;

  new.datos := new.datos #- '{fields,carta_cobrado_importe}'
                         #- '{fields,carta_cobrado_numeros}'
                         #- '{fields,carta_cobrado_sobrante}'
                         #- '{fields,carta_cobrado_detalle}';

  if coalesce(array_length(cods, 1), 0) = 0 or proy is null then
    return new;
  end if;

  select array_agg(x.id order by x.numero), array_agg(x.numero order by x.numero)
    into cartas_ids, cartas_nums
    from (
      select distinct c.id, c.numero
        from public.unidades u
        join public.contratos c on c.id = u.contrato_id
       where u.proyecto = proy and u.codigo = any(cods)
         and c.tipo like 'carta_reserva%'
         and coalesce(nullif(btrim(c.datos->'fields'->>'moneda'), ''), 'EUR') = moneda_bloqueo
    ) x;

  if coalesce(array_length(cartas_ids, 1), 0) = 0 then
    return new;
  end if;

  for i in 1 .. array_length(cartas_ids, 1) loop
    perform pg_advisory_xact_lock(hashtext(cartas_ids[i]::text));
    -- ANTES: sum(...) from contratos c2, jsonb_array_elements(c2.datos->...) -- escaneaba
    -- y descomprimia el `datos` de los 116 contratos reserva_parcela por cada carta
    -- (2.710 ms/12.722 buffers medido para UNA carta). AHORA: tabla lateral indexada.
    v_ya := coalesce((
      select sum(importe) from public.carta_cobrado_aplicado
       where carta_id = cartas_ids[i] and contrato_id <> new.id
    ), 0);
    v_disp := greatest(coalesce(public.contrato_cobrado(cartas_ids[i]), 0) - v_ya, 0);
    v_disponibles := v_disponibles || v_disp;
    v_cobrado := v_cobrado + v_disp;
  end loop;

  if v_cobrado <= 0 then
    return new;
  end if;

  v_precio_total := greatest(coalesce(public.lw_importe(new.datos->'fields'->>'precio_total'), 0), 0);
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

    new.datos := jsonb_set(new.datos, '{fields,carta_cobrado_importe}',
                            to_jsonb(public.lw_importe_texto(v_descuento)), true);
    new.datos := jsonb_set(new.datos, '{fields,carta_cobrado_numeros}',
                            to_jsonb(array_to_string(v_nums_aportantes, ', ')), true);
    new.datos := jsonb_set(new.datos, '{fields,carta_cobrado_detalle}', v_detalle, true);

    -- Espejo indexado de lo que se acaba de reclamar, para que la PROXIMA alta no
    -- tenga que volver a escanear el `datos` de nadie -- misma fuente (v_detalle) que
    -- se acaba de congelar en el jsonb, sin recalcular ni duplicar la logica de reparto.
    insert into public.carta_cobrado_aplicado (contrato_id, carta_id, importe)
    select new.id, (elem->>'carta_id')::uuid, public.lw_importe(elem->>'importe')
      from jsonb_array_elements(v_detalle) elem
    on conflict (contrato_id, carta_id) do nothing;
  end if;

  if v_sobrante > 0 then
    new.datos := jsonb_set(new.datos, '{fields,carta_cobrado_sobrante}',
                            to_jsonb(public.lw_importe_texto(v_sobrante)), true);
  end if;

  if v_descuento > 0 then
    v_restante := v_descuento;
    v_hitos := new.datos->'hitos';
    if jsonb_typeof(v_hitos) = 'array' then
      for i in 0 .. jsonb_array_length(v_hitos) - 1 loop
        exit when v_restante <= 0;
        v_monto := coalesce(public.lw_importe(v_hitos->i->>'monto'), 0);
        if v_monto > 0 then
          v_resta := least(v_monto, v_restante);
          v_hitos := jsonb_set(v_hitos, array[i::text, 'monto'],
                                to_jsonb(public.lw_importe_texto(v_monto - v_resta)), true);
          v_restante := v_restante - v_resta;
        end if;
      end loop;
      new.datos := jsonb_set(new.datos, '{hitos}', v_hitos, true);
    end if;
  end if;

  return new;
end;
$function$;;
