-- Hallazgo Seguridad (11-ago, revisión del deploy de la reforma de
-- facturación): el tope "no apliques más de lo pendiente" vivía SOLO en el
-- JS de facturas/index.html — saltable por un INSERT directo a la API REST.
-- Es la misma clase de fallo que esta reforma vino a cerrar (dinero fantasma
-- contado de más), solo que movido de "factura cuenta como cobro" a "recibí
-- cuenta de más". Dos topes, los dos importan:
--   · una factura no puede recibir aplicaciones por encima de su total
--     (evita repartir el mismo recibí dos veces sobre la misma factura, o
--     cobrar de más de lo que esa factura pide);
--   · un recibí no puede aplicar más dinero del que él mismo representa
--     (evita inflar el "cobrado" con dinero que nunca entró).
-- destructivo-ok: no hay UPDATE de datos aquí — "before insert or update on"
-- es la sintaxis de CREATE TRIGGER, el guardrail lo confunde con un UPDATE DML.
create or replace function public.valida_recibi_aplicacion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_factura_total numeric;
  v_factura_aplicado numeric;
  v_recibi_total numeric;
  v_recibi_aplicado numeric;
begin
  select total into v_factura_total from public.facturas where id = new.factura_id;
  select coalesce(sum(importe_aplicado), 0) into v_factura_aplicado
    from public.recibi_aplicaciones where factura_id = new.factura_id and id <> coalesce(new.id, '00000000-0000-0000-0000-000000000000'::uuid);
  if v_factura_aplicado + new.importe_aplicado > v_factura_total + 0.01 then
    raise exception 'la factura ya tiene % aplicado de un total de % — esta aplicación de % se pasa',
      v_factura_aplicado, v_factura_total, new.importe_aplicado using errcode = '23514';
  end if;

  select total into v_recibi_total from public.facturas where id = new.recibi_id;
  select coalesce(sum(importe_aplicado), 0) into v_recibi_aplicado
    from public.recibi_aplicaciones where recibi_id = new.recibi_id and id <> coalesce(new.id, '00000000-0000-0000-0000-000000000000'::uuid);
  if v_recibi_aplicado + new.importe_aplicado > v_recibi_total + 0.01 then
    raise exception 'el recibí es de % y ya lleva % aplicado — esta aplicación de % se pasa',
      v_recibi_total, v_recibi_aplicado, new.importe_aplicado using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger recibi_aplicaciones_valida
  before insert or update on public.recibi_aplicaciones
  for each row execute function public.valida_recibi_aplicacion();
;
