-- Descuento comercial del Bloqueo de Parcela, en el SERVIDOR — 25-sep-2026.
-- Owner: "en el contrato de bloqueo de parcela añade la opción de descuento
-- comercial y motivo, opcional, como hacemos en construcción".
-- ════════════════════════════════════════════════════════════════════════════
-- GEMELO de descuento_comercial_construccion_valido (21/22-sep-2026, revisión
-- previa #33), con el suelo de inventario en el papel de techo+extras. Función
-- y trigger PROPIOS en vez de ampliar la de Construcción: la base se calcula
-- distinto (allí sale de datos.techo/extras; aquí la congela la intranet en
-- datos.fields.precio_lista_suelo) y mezclarlas haría que un cambio en una
-- regla rompa la otra.
--
-- QUÉ BLOQUEA (solo tipo = reserva_parcela):
--   · descuento_comercial negativo — siempre.
--   · Con descuento > 0, y solo en INSERT o si cambia precio_total, el
--     descuento, el motivo o la lista (lección del 21-sep: un cinturón
--     incondicional rompe ediciones que no tienen nada que ver):
--       - falta precio_lista_suelo (sin lista no hay de qué restar);
--       - descuento > 15% de la lista;
--       - falta el motivo;
--       - precio_total ≠ lista − descuento (±0,01). En el Bloqueo precio_total
--         sigue siendo editable a mano; con descuento, si no cuadra, el
--         contrato imprimiría "lista 100, descuento 10, total 95".
-- NO valida el ROL de quien escribe (super_admin/admin): ese candado sigue
-- siendo de pantalla, igual que en Construcción.
create or replace function public.descuento_comercial_suelo_valido()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_descuento numeric;
  v_lista     numeric;
  v_motivo    text;
  v_cambia    boolean;
begin
  if new.tipo <> 'reserva_parcela' then
    return new;
  end if;
  v_descuento := coalesce(public.lw_importe(new.datos->'fields'->>'descuento_comercial'), 0);
  if v_descuento < 0 then
    raise exception 'El descuento comercial no puede ser negativo.';
  end if;
  if v_descuento = 0 then
    return new;
  end if;
  v_cambia := tg_op = 'INSERT'
    or new.precio_total is distinct from old.precio_total
    or (new.datos->'fields'->>'descuento_comercial') is distinct from (old.datos->'fields'->>'descuento_comercial')
    or (new.datos->'fields'->>'descuento_comercial_motivo') is distinct from (old.datos->'fields'->>'descuento_comercial_motivo')
    or (new.datos->'fields'->>'precio_lista_suelo') is distinct from (old.datos->'fields'->>'precio_lista_suelo');
  if not v_cambia then
    return new;
  end if;
  v_lista := public.lw_importe(new.datos->'fields'->>'precio_lista_suelo');
  if v_lista is null or v_lista <= 0 then
    raise exception 'Un descuento comercial en el Bloqueo de Parcela necesita el precio de lista del suelo (precio_lista_suelo).';
  end if;
  if v_descuento > round(v_lista * 0.15, 2) then
    raise exception 'El descuento comercial (%) supera el 15%% del precio del suelo (%).', v_descuento, v_lista;
  end if;
  v_motivo := nullif(btrim(coalesce(new.datos->'fields'->>'descuento_comercial_motivo', '')), '');
  if v_motivo is null then
    raise exception 'Un descuento comercial necesita su motivo.';
  end if;
  if new.precio_total is null or abs(new.precio_total - (v_lista - v_descuento)) > 0.01 then
    raise exception 'precio_total (%) no cuadra con el precio del suelo menos el descuento comercial (% − % = %).',
      new.precio_total, v_lista, v_descuento, v_lista - v_descuento;
  end if;
  return new;
end;
$$;

-- destructivo-ok: DROP defensivo de un trigger que hoy NO existe (nuevo en
-- esta migración) — solo por si se reaplica; no borra nada que exista.
drop trigger if exists trg_descuento_comercial_suelo on public.contratos;
create trigger trg_descuento_comercial_suelo
  before insert or update on public.contratos
  for each row execute function public.descuento_comercial_suelo_valido();

comment on function public.descuento_comercial_suelo_valido() is
  'BEFORE INSERT OR UPDATE en contratos, solo tipo=reserva_parcela: bloquea un descuento_comercial negativo y, con descuento>0 (en INSERT o si cambia precio/descuento/motivo/lista), exige precio_lista_suelo, tope 15%, motivo y precio_total = lista − descuento. NO valida el rol — candado de pantalla. 25-sep-2026.';
