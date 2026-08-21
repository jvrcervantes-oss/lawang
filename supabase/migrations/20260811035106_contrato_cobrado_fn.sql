create or replace function public.contrato_cobrado(p_contrato_id uuid)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select
    coalesce((
      select sum(ra.importe_aplicado)
        from public.recibi_aplicaciones ra
        join public.facturas r on r.id = ra.recibi_id
        join public.facturas f on f.id = ra.factura_id
       where f.contrato_id = p_contrato_id
         and not coalesce(r.anulada, false)
         and not coalesce(f.anulada, false)
    ), 0)
    +
    coalesce((
      select sum(r.total)
        from public.facturas r
       where r.tipo = 'recibi' and r.contrato_id = p_contrato_id
         and not coalesce(r.anulada, false)
         and not exists (select 1 from public.recibi_aplicaciones ra where ra.recibi_id = r.id)
    ), 0)
$$;

revoke all on function public.contrato_cobrado(uuid) from public, anon;
grant execute on function public.contrato_cobrado(uuid) to authenticated;
;
