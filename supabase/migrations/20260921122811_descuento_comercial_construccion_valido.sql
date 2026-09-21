-- Tope del descuento comercial de Construcción, en el SERVIDOR — 21-sep-2026,
-- revisión previa #33 (Legal + Administración + Seguridad).
-- Detalle completo en contracts/sql/descuento_comercial_construccion_valido.sql
-- ════════════════════════════════════════════════════════════════════════════
-- QUÉ CUBRE: tope 15% de descuento_comercial sobre techo+extras (cuando esa
-- forma es calculable en datos.techo/datos.extras), descuento nunca negativo,
-- y precio_total nunca en cero/negativo como cinturón final. NO valida el rol
-- de quien escribe (sigue siendo candado de pantalla, ver el .sql del repo).
-- ════════════════════════════════════════════════════════════════════════════

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
  end if;

  if coalesce(new.precio_total, 0) <= 0 then
    raise exception 'precio_total no puede quedar en cero o negativo en un Contrato de Construcción.';
  end if;

  return new;
end;
$$;

revoke execute on function public.descuento_comercial_construccion_valido() from public, anon, authenticated;

-- destructivo-ok: DROP defensivo de un trigger que hoy NO existe en producción
-- (comprobado con list_migrations/pg_trigger antes de escribir esto) — solo
-- por si esta migración se reaplica alguna vez; no borra nada que exista.
drop trigger if exists trg_descuento_comercial_construccion on public.contratos;
create trigger trg_descuento_comercial_construccion
  before insert or update on public.contratos
  for each row execute function public.descuento_comercial_construccion_valido();

comment on function public.descuento_comercial_construccion_valido() is
  'BEFORE INSERT OR UPDATE en contratos, solo tipo=construccion: bloquea un descuento_comercial negativo o por encima del 15% de techo+extras (cuando esa forma es calculable) y, siempre, un precio_total en cero o negativo. NO valida el rol de quien escribe — ese candado sigue siendo de pantalla. 21-sep-2026, revisión previa #33.';
;
