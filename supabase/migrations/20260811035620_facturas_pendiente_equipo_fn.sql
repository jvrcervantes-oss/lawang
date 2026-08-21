-- Cuánto le queda pendiente a cada factura viva (para el picker de "qué
-- factura salda este recibí" en /facturas/). Team-wide, mismo criterio que
-- contratos_equipo()/facturas_equipo(): recibi_aplicaciones solo deja ver
-- SUS propias filas a cada agente, y aquí hace falta ver las de todos.
create or replace function public.facturas_pendiente_equipo()
returns table(factura_id uuid, pendiente numeric)
language sql
stable
security definer
set search_path = ''
as $$
  select f.id,
    f.total - coalesce((
      select sum(ra.importe_aplicado)
        from public.recibi_aplicaciones ra
        join public.facturas r on r.id = ra.recibi_id
       where ra.factura_id = f.id and not coalesce(r.anulada, false)
    ), 0)
    from public.facturas f
   where f.tipo = 'factura' and not coalesce(f.anulada, false) and public.es_agente();
$$;

revoke all on function public.facturas_pendiente_equipo() from public, anon;
grant execute on function public.facturas_pendiente_equipo() to authenticated;
;
