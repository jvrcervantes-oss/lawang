-- Dos correcciones de la consulta de deploy (17-sep-2026, capa 1) sobre
-- carta_cobrado_al_bloquear.sql — ambas ALTA, las dos verificadas antes de
-- escribir esto, ninguna es una opinión. Ver la nota completa en
-- contracts/sql/carta_cobrado_al_bloquear_moneda_y_grant.sql.

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
  v_cobrado      numeric := 0;
  v_precio_total numeric;
  v_descuento    numeric;
  v_sobrante     numeric;
  v_hitos        jsonb;
  v_restante     numeric;
  v_monto        numeric;
  v_resta        numeric;
  i              int;
begin
  if tg_op <> 'INSERT' or new.tipo <> 'reserva_parcela' then
    return new;
  end if;

  new.datos := new.datos #- '{fields,carta_cobrado_importe}'
                         #- '{fields,carta_cobrado_numeros}'
                         #- '{fields,carta_cobrado_sobrante}';

  if coalesce(array_length(cods, 1), 0) = 0 or proy is null then
    return new;
  end if;

  select coalesce(array_agg(distinct c.id) filter (
           where coalesce(nullif(btrim(c.datos->'fields'->>'moneda'), ''), 'EUR') = moneda_bloqueo), '{}'),
         coalesce(array_agg(distinct c.numero) filter (
           where coalesce(nullif(btrim(c.datos->'fields'->>'moneda'), ''), 'EUR') = moneda_bloqueo), '{}')
    into cartas_ids, cartas_nums
    from public.unidades u
    join public.contratos c on c.id = u.contrato_id
   where u.proyecto = proy and u.codigo = any(cods)
     and c.tipo like 'carta_reserva%';

  if coalesce(array_length(cartas_ids, 1), 0) = 0 then
    return new;
  end if;

  select coalesce(sum(public.contrato_cobrado(cid)), 0) into v_cobrado
    from unnest(cartas_ids) as cid;

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
  'BEFORE INSERT en contratos: si este Bloqueo de Parcela (reserva_parcela) traspasa de verdad su parcela desde una Carta de Reserva con dinero cobrado EN LA MISMA MONEDA que el propio Bloqueo, descuenta ese abono (fields.carta_cobrado_*, hitos en cascada). Una Carta en otra moneda se excluye del cálculo (no hay conversión en el sistema). Solo lectura sobre unidades/contratos — la validación de que el traspaso es legítimo (mismo comprador) la hace en exclusiva sincroniza_unidad_contrato() (AFTER, misma transacción). 17-sep-2026, revisión previa #24 + consulta de deploy (hallazgo ALTA de Administración: comparaba importes de monedas distintas).';

revoke execute on function public.contrato_cobrado(uuid) from authenticated;
