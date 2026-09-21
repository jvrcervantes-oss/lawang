-- FIX urgente, misma sesión (21-sep-2026): el cinturón final de
-- descuento_comercial_construccion_valido() comprobaba precio_total<=0 SIN
-- condicionarlo a que hubiera descuento (`v_descuento > 0`), así que corría
-- en CUALQUIER UPDATE de un contrato tipo=construccion, tenga o no
-- descuento_comercial. Verificado contra producción ANTES de este fix:
-- CC00040/CC00076/CC00086 ya existen con precio_total NULL y descuento 0 —
-- la próxima edición de cualquiera de esos tres (arreglar un email, enlazar
-- un comprador, tocar un hito) habría reventado con "precio_total no puede
-- quedar en cero o negativo", un freno que no existía ayer y que no tiene
-- nada que ver con el descuento comercial. Detectado por autorrevisión
-- (code-review) antes de dar la tarea por cerrada, no en producción.
--
-- FIX: el cinturón final pasa a vivir DENTRO de `if v_descuento > 0`, igual
-- que el tope del 15% — solo se exige un precio_total sano cuando de verdad
-- hay un descuento comercial que podría haberlo dejado en cero o negativo.
-- Un contrato sin descuento (el 100% de los de antes de hoy) se comporta
-- exactamente igual que antes de esta migración.

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
begin
  if new.tipo <> 'construccion' then
    return new;
  end if;

  v_descuento := coalesce(public.lw_importe(new.datos->'fields'->>'descuento_comercial'), 0);

  if v_descuento < 0 then
    raise exception 'El descuento comercial no puede ser negativo.';
  end if;

  if v_descuento > 0 then
    v_techo := nullif(new.datos->'techo'->>'precio', '')::numeric;
    if v_techo is not null then
      select v_techo + coalesce(sum(nullif(x->>'precio','')::numeric), 0)
        into v_base
        from jsonb_array_elements(coalesce(new.datos->'extras', '[]'::jsonb)) x;

      if v_base > 0 and v_descuento > round(v_base * 0.15, 2) then
        raise exception 'El descuento comercial (%) supera el 15%% del precio de techo+extras (%).',
          v_descuento, v_base;
      end if;
    end if;

    -- Cinturón final: SOLO cuando hay descuento de por medio (fix de esta
    -- migración). Antes de este fix corría siempre, y hay contratos reales
    -- (CC00040, CC00076, CC00086) con precio_total NULL sin ningún
    -- descuento — no son un dato corrupto de este cambio, son contratos que
    -- todavía no tienen precio puesto por otro motivo, y editarlos por
    -- cualquier otra razón no puede empezar a fallar por esto.
    if coalesce(new.precio_total, 0) <= 0 then
      raise exception 'precio_total no puede quedar en cero o negativo al aplicar un descuento comercial.';
    end if;
  end if;

  return new;
end;
$$;

comment on function public.descuento_comercial_construccion_valido() is
  'BEFORE INSERT OR UPDATE en contratos, solo tipo=construccion: bloquea un descuento_comercial negativo o por encima del 15% de techo+extras (cuando esa forma es calculable), y --SOLO cuando hay descuento (v_descuento>0)-- que precio_total no quede en cero o negativo. NO valida el rol de quien escribe — ese candado sigue siendo de pantalla. 21-sep-2026, revisión previa #33; corregido el mismo día (autorrevisión) para no bloquear ediciones de contratos sin descuento y con precio_total ya en null/0.';
;
