-- Corrección de fondo tras `/code-review high` (17-sep-2026): doble cómputo
-- cuando UNA Carta con varias parcelas se traspasa a VARIOS Bloqueos por
-- separado (no todas a un único Bloqueo multi-parcela).
-- ════════════════════════════════════════════════════════════════════════════
-- EL FALLO. `contrato_cobrado(carta_id)` devuelve el TOTAL cobrado en la
-- Carta, sin memoria de si ese dinero ya se aplicó a un Bloqueo anterior. El
-- trigger AFTER (`sincroniza_unidad_contrato`) solo fija `contrato_padre_id`
-- en la Carta la PRIMERA vez (`where c.contrato_padre_id is null`), así que
-- una Carta con 3 parcelas (p.ej. CR00025: B9/B15/B16) puede traspasar cada
-- una a un Bloqueo distinto en fechas distintas, y CADA Bloqueo vería el
-- 100% de lo cobrado en la Carta y lo descontaría entero — el mismo abono
-- aplicado dos o tres veces, en documentos firmables independientes.
--
-- Esto es real en este dominio (Cartas multi-parcela existen en producción,
-- CP00002/CR00025) y NO estaba cubierto por ninguna de las reglas ya
-- cerradas del owner (que hablaban de "varias Cartas hacia UN Bloqueo", no
-- de "una Carta hacia varios Bloqueos" secuenciales).
--
-- ARREGLO (sin tabla nueva — no es un cambio de arquitectura, es que el
-- propio Bloqueo anota lo que reclamó, igual que ya anota `carta_cobrado_*`):
-- cada Bloqueo que reclama dinero de una Carta dhora escribe también
-- `fields.carta_cobrado_detalle`, un array `[{carta_id, numero, importe}]`
-- con CUÁNTO reclamó de CADA Carta de origen. El siguiente Bloqueo que mire
-- la MISMA Carta resta lo que YA reclamaron sus hermanos (escaneando ese
-- campo en cualquier otro `reserva_parcela`) antes de calcular su propio
-- descuento — el "disponible" de cada Carta, no su total bruto.
-- El "sobrante" (lo que no cupo en el precio_total de ESTE Bloqueo) NUNCA se
-- anota como reclamado: sigue disponible de verdad para un Bloqueo futuro,
-- que es justo lo que "sobrante" quiere decir.
-- Si el Bloqueo que reclamó se borra, su claim desaparece con él (vive
-- dentro de su propia fila) — no hay ledger huérfano que limpiar aparte.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.carta_cobrado_al_bloquear()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  cods text[] := (
    select coalesce(array_agg(distinct btrim(x)) filter (where btrim(x) <> ''), '{}')
      from unnest(string_to_array(coalesce(new.datos->'fields'->>'parcela_codigo',''), ',')) x);
  proy text := coalesce(nullif(btrim(new.datos->'fields'->>'proyecto_nombre'), ''), new.proyecto_nombre);
  moneda_bloqueo text := coalesce(nullif(btrim(new.datos->'fields'->>'moneda'), ''), 'EUR');
  cartas_ids     uuid[];
  cartas_nums    text[];
  v_disponibles  numeric[] := '{}';
  v_cobrado      numeric := 0;
  v_precio_total numeric;
  v_descuento    numeric;
  v_sobrante     numeric;
  v_hitos        jsonb;
  v_restante     numeric;
  v_monto        numeric;
  v_resta        numeric;
  v_detalle      jsonb := '[]'::jsonb;
  v_disp         numeric;
  v_ya           numeric;
  v_claim        numeric;
  i              int;
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

  -- mismo criterio de moneda que ya se corrigió; ahora en orden por numero
  -- para que cartas_ids/cartas_nums queden alineados de forma determinista
  -- (los necesito emparejados para el reparto en cascada de más abajo).
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

  -- disponible por Carta = cobrado real − lo que otros Bloqueos ya reclamaron
  -- de ESA misma Carta (su propio carta_cobrado_detalle, nunca el sobrante).
  for i in 1 .. array_length(cartas_ids, 1) loop
    v_ya := coalesce((
      select sum(public.lw_importe(d->>'importe'))
        from public.contratos c2,
             jsonb_array_elements(coalesce(c2.datos->'fields'->'carta_cobrado_detalle', '[]'::jsonb)) d
       where c2.tipo = 'reserva_parcela'
         and c2.id <> new.id
         and (d->>'carta_id')::uuid = cartas_ids[i]
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
    new.datos := jsonb_set(new.datos, '{fields,carta_cobrado_importe}',
                            to_jsonb(public.lw_importe_texto(v_descuento)), true);
    new.datos := jsonb_set(new.datos, '{fields,carta_cobrado_numeros}',
                            to_jsonb(array_to_string(cartas_nums, ', ')), true);

    -- reparto del descuento EN CASCADA sobre lo disponible de cada Carta, en
    -- el mismo orden — este array es lo que el siguiente Bloqueo va a leer.
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
        v_restante := v_restante - v_claim;
      end if;
    end loop;
    new.datos := jsonb_set(new.datos, '{fields,carta_cobrado_detalle}', v_detalle, true);
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
$$;

revoke execute on function public.carta_cobrado_al_bloquear() from public, anon, authenticated;

comment on function public.carta_cobrado_al_bloquear() is
  'BEFORE INSERT en contratos: si este Bloqueo de Parcela (reserva_parcela) traspasa de verdad su parcela desde una Carta de Reserva con dinero DISPONIBLE (cobrado real menos lo ya reclamado por otros Bloqueos de la misma Carta, fields.carta_cobrado_detalle) en la MISMA MONEDA que el propio Bloqueo, descuenta ese abono (fields.carta_cobrado_*, hitos en cascada). El sobrante nunca se anota como reclamado. Solo lectura sobre unidades/contratos — la validación de que el traspaso es legítimo (mismo comprador) la hace en exclusiva sincroniza_unidad_contrato() (AFTER, misma transacción). 17-sep-2026, revisión previa #24 + code-review (doble cómputo en Carta multi-parcela repartida en varios Bloqueos secuenciales).';

-- ── comprobación tras aplicar: probe de cero huella con DOS Bloqueos ────────
-- secuenciales sobre la MISMA Carta multi-parcela (CR00025: B9/B15/B16,
-- proyecto "Palm Field", cobrado real ~5000 EUR comprobado antes de escribir
-- esto). El segundo Bloqueo debe ver "disponible" en 0 y no escribir ninguna
-- clave carta_cobrado_*.
--
-- do $$
-- declare d1 jsonb; d2 jsonb;
-- begin
--   insert into public.contratos (numero, tipo, proyecto_nombre, datos)
--     values ('PROBE-A', 'reserva_parcela', 'Palm Field',
--       jsonb_build_object('fields', jsonb_build_object(
--         'parcela_codigo','B9','proyecto_nombre','Palm Field',
--         'precio_total','2000','moneda','EUR'), 'hitos','[]'::jsonb))
--     returning datos into d1;
--   insert into public.contratos (numero, tipo, proyecto_nombre, datos)
--     values ('PROBE-B', 'reserva_parcela', 'Palm Field',
--       jsonb_build_object('fields', jsonb_build_object(
--         'parcela_codigo','B15','proyecto_nombre','Palm Field',
--         'precio_total','2000','moneda','EUR'), 'hitos','[]'::jsonb))
--     returning datos into d2;
--   raise exception 'PROBE A=% -- B=%', d1->'fields', d2->'fields';
-- end $$;
