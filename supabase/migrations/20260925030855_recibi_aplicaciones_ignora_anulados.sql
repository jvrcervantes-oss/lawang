-- El tope por factura sumaba tambien las aplicaciones de recibis ANULADOS:
-- anular REC00116 (44.400) dejaba INV00165 "llena" y el recibi nuevo no entraba
-- («la factura ya tiene 44400 aplicado de un total de 44400»), 25-sep-2026.
-- Mismo criterio que factura_aplicado(): un recibi anulado no cuenta.
-- El lado recibi no cambia: un recibi anulado ya no se edita (guardar_recibi).
create or replace function public.valida_recibi_aplicacion()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_factura_total numeric;
  v_factura_aplicado numeric;
  v_factura_moneda text;
  v_recibi_total numeric;
  v_recibi_aplicado numeric;
  v_recibi_moneda text;
begin
  select total, moneda into v_factura_total, v_factura_moneda from public.facturas where id = new.factura_id;
  select coalesce(sum(ra.importe_aplicado), 0) into v_factura_aplicado
    from public.recibi_aplicaciones ra
    join public.facturas r on r.id = ra.recibi_id
   where ra.factura_id = new.factura_id
     and not coalesce(r.anulada, false)
     and ra.id <> coalesce(new.id, '00000000-0000-0000-0000-000000000000'::uuid);
  if v_factura_aplicado + new.importe_aplicado > v_factura_total + 0.01 then
    raise exception 'la factura ya tiene % aplicado de un total de % — esta aplicación de % se pasa',
      v_factura_aplicado, v_factura_total, new.importe_aplicado using errcode = '23514';
  end if;

  select total, moneda into v_recibi_total, v_recibi_moneda from public.facturas where id = new.recibi_id;
  select coalesce(sum(importe_aplicado), 0) into v_recibi_aplicado
    from public.recibi_aplicaciones where recibi_id = new.recibi_id and id <> coalesce(new.id, '00000000-0000-0000-0000-000000000000'::uuid);
  if v_recibi_aplicado + new.importe_aplicado > v_recibi_total + 0.01 then
    raise exception 'el recibí es de % y ya lleva % aplicado — esta aplicación de % se pasa',
      v_recibi_total, v_recibi_aplicado, new.importe_aplicado using errcode = '23514';
  end if;

  if v_recibi_moneda is distinct from v_factura_moneda then
    raise exception 'el recibí es en % y la factura en % — no se pueden aplicar monedas distintas',
      v_recibi_moneda, v_factura_moneda using errcode = '23514';
  end if;

  return new;
end;
$function$;
