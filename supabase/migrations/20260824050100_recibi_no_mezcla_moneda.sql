-- destructivo-ok: `create or replace function` + `drop trigger if exists`
-- idempotente sobre el trigger que este mismo fichero recrea; no borra datos.
-- ════════════════════════════════════════════════════════════════════════════
-- UN RECIBÍ PODÍA APLICARSE A UNA FACTURA EN OTRA MONEDA — 24-ago-2026
-- ════════════════════════════════════════════════════════════════════════════
-- Hallazgo de Desarrollo (auditoría de hoy): `valida_recibi_aplicacion()`
-- compara `importe_aplicado` contra `total` de forma puramente numérica, sin
-- mirar `moneda` en ningún lado. `cargarFacturasAbiertas()` (facturas/index.html)
-- tampoco pide `moneda` en su `select`, así que el desplegable de "facturas
-- pendientes" formatea el importe de CADA factura con la moneda que esté
-- elegida en el recibí — nunca la real de esa factura.
--
-- Hoy no hay ningún comprador con contratos en monedas distintas (comprobado
-- contra producción), así que no ha pasado todavía — pero la suite lo permite
-- por diseño (EUR e IDR conviven, `vencimientos/logica.js` ya tiene la regla
-- "Monedas NUNCA mezcladas en una suma" precisamente por esto) y nada lo
-- impedía. Si pasara: un recibí de 50.000,00 € podría aplicarse a una factura
-- de 50.000.000 IDR, y ni la pantalla ni la base lo habrían frenado.
--
-- LA CURA: el mismo guardarraíl de servidor que ya existe para los TOPES,
-- ampliado con la comprobación de moneda. El frontend se arregla aparte (pide
-- `moneda` y filtra el desplegable a la del recibí) — este trigger es el que
-- de verdad lo impide, aunque alguien salte el frontend.

create or replace function public.valida_recibi_aplicacion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_factura_total numeric;
  v_factura_aplicado numeric;
  v_factura_moneda text;
  v_recibi_total numeric;
  v_recibi_aplicado numeric;
  v_recibi_moneda text;
begin
  select total, moneda into v_factura_total, v_factura_moneda from public.facturas where id = new.factura_id;
  select coalesce(sum(importe_aplicado), 0) into v_factura_aplicado
    from public.recibi_aplicaciones where factura_id = new.factura_id and id <> coalesce(new.id, '00000000-0000-0000-0000-000000000000'::uuid);
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
$$;

drop trigger if exists recibi_aplicaciones_valida on public.recibi_aplicaciones;
create trigger recibi_aplicaciones_valida
  before insert or update on public.recibi_aplicaciones
  for each row execute function public.valida_recibi_aplicacion();
