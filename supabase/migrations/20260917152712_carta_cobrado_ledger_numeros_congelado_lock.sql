-- Tres correcciones de la consulta de deploy (17-sep-2026) sobre
-- carta_cobrado_ledger_multibloqueo.sql — ver
-- contracts/sql/carta_cobrado_ledger_multibloqueo.sql para la nota completa
-- (numeros mal atribuidos, ledger sin proteger en UPDATE, sin lock entre
-- inserts concurrentes) y los probes de cero huella usados para verificarlas.

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
  'BEFORE INSERT en contratos: si este Bloqueo de Parcela (reserva_parcela) traspasa de verdad su parcela desde una Carta de Reserva con dinero DISPONIBLE (cobrado real menos lo ya reclamado por otros Bloqueos de la misma Carta, fields.carta_cobrado_detalle) en la MISMA MONEDA que el propio Bloqueo, descuenta ese abono (fields.carta_cobrado_*, hitos en cascada). carta_cobrado_numeros solo cita Cartas que de verdad aportaron. El sobrante nunca se anota como reclamado. pg_advisory_xact_lock por Carta serializa Bloqueos concurrentes. Solo lectura sobre unidades/contratos — la validación de que el traspaso es legítimo (mismo comprador) la hace en exclusiva sincroniza_unidad_contrato() (AFTER, misma transacción). 17-sep-2026, revisión previa #24 + code-review + consulta de deploy (numeros mal atribuidos, ledger sin proteger en UPDATE, sin lock entre inserts concurrentes).';

create or replace function public.carta_cobrado_congelado_en_update()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  k text;
begin
  if tg_op <> 'UPDATE' or new.tipo <> 'reserva_parcela' then
    return new;
  end if;

  foreach k in array array['carta_cobrado_importe','carta_cobrado_numeros',
                            'carta_cobrado_sobrante','carta_cobrado_detalle']
  loop
    if (old.datos->'fields') ? k then
      new.datos := jsonb_set(new.datos, array['fields', k], old.datos->'fields'->k, true);
    else
      new.datos := new.datos #- array['fields', k];
    end if;
  end loop;

  return new;
end;
$$;

revoke execute on function public.carta_cobrado_congelado_en_update() from public, anon, authenticated;

drop trigger if exists trg_carta_cobrado_congelado_en_update on public.contratos;
create trigger trg_carta_cobrado_congelado_en_update
  before update on public.contratos
  for each row execute function public.carta_cobrado_congelado_en_update();

comment on function public.carta_cobrado_congelado_en_update() is
  'BEFORE UPDATE en contratos: si es un Bloqueo de Parcela (reserva_parcela), repone fields.carta_cobrado_importe/numeros/sobrante/detalle al valor que tenían ANTES del UPDATE, pase lo que pase en new — cierra el hueco por el que un re-guardado normal (UI) o un PATCH directo podía borrar o falsear el ledger que carta_cobrado_al_bloquear() escribe una sola vez en el INSERT. 17-sep-2026, consulta de deploy (hallazgo ALTA de Administración y de Seguridad, mismo problema desde dos ángulos distintos).';
