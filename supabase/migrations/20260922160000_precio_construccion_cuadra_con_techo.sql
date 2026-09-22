-- 22-sep-2026 — el precio de Construcción con techo elegido se comprueba en SERVIDOR.
-- Detalle y porqué en contracts/sql/descuento_comercial_construccion_valido.sql.
--
-- QUÉ AÑADE: cuando datos.techo trae precio, precio_total debe ser exactamente
-- techo + Σextras − descuento_comercial (±0,01). Hasta hoy ese candado era solo de
-- pantalla y falló: CC00105/CC00106/CC00107 se guardaron con un precio tecleado a
-- mano (el atributo que enganchaba el readonly no se emitía en contratos nuevos).
-- Solo se comprueba en INSERT o cuando cambia alguno de los cuatro datos que
-- entran en la cuenta — nunca en un UPDATE ajeno (misma lección que el fix del
-- 21-sep: un cinturón incondicional rompía ediciones que no tenían que ver).
create or replace function public.descuento_comercial_construccion_valido()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_descuento numeric;
  v_techo     numeric;
  v_base      numeric;
  v_esperado  numeric;
  v_cambia    boolean;
begin
  if new.tipo <> 'construccion' then
    return new;
  end if;
  v_descuento := coalesce(public.lw_importe(new.datos->'fields'->>'descuento_comercial'), 0);
  if v_descuento < 0 then
    raise exception 'El descuento comercial no puede ser negativo.';
  end if;
  v_techo := nullif(new.datos->'techo'->>'precio', '')::numeric;
  if v_techo is not null then
    select v_techo + coalesce(sum(nullif(x->>'precio','')::numeric), 0)
      into v_base
      from jsonb_array_elements(coalesce(new.datos->'extras', '[]'::jsonb)) x;
  end if;
  if v_descuento > 0 then
    if v_base > 0 and v_descuento > round(v_base * 0.15, 2) then
      raise exception 'El descuento comercial (%) supera el 15%% del precio de techo+extras (%).',
        v_descuento, v_base;
    end if;
    -- Cinturón: SOLO cuando hay descuento de por medio (fix 21-sep — hay
    -- contratos reales con precio_total NULL y sin descuento, CC00040/76/86).
    if coalesce(new.precio_total, 0) <= 0 then
      raise exception 'precio_total no puede quedar en cero o negativo al aplicar un descuento comercial.';
    end if;
  end if;
  -- 22-sep-2026: con techo elegido, el precio es la fórmula, no lo que llegue.
  if v_base is not null and v_base > 0 then
    v_cambia := tg_op = 'INSERT'
      or new.precio_total is distinct from old.precio_total
      or new.datos->'techo' is distinct from old.datos->'techo'
      or new.datos->'extras' is distinct from old.datos->'extras'
      or (new.datos->'fields'->>'descuento_comercial') is distinct from (old.datos->'fields'->>'descuento_comercial');
    if v_cambia then
      v_esperado := v_base - v_descuento;
      if new.precio_total is null or abs(new.precio_total - v_esperado) > 0.01 then
        raise exception 'precio_total (%) no cuadra con techo + extras − descuento comercial (% = % + extras − %): el precio de Construcción con techo elegido lo calcula la intranet, no se teclea.',
          new.precio_total, v_esperado, v_techo, v_descuento;
      end if;
    end if;
  end if;
  return new;
end;
$$;

comment on function public.descuento_comercial_construccion_valido() is
  'BEFORE INSERT OR UPDATE en contratos, solo tipo=construccion: bloquea un descuento_comercial negativo o por encima del 15% de techo+extras, un precio_total en cero o negativo cuando hay descuento y, desde el 22-sep-2026, un precio_total que no sea techo+extras−descuento cuando datos.techo trae precio (solo en INSERT o si cambia alguno de esos datos). NO valida el rol de quien escribe — ese candado sigue siendo de pantalla. 21/22-sep-2026.';
