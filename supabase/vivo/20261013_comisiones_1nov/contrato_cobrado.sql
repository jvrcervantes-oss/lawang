CREATE OR REPLACE FUNCTION public.contrato_cobrado(p_contrato_id uuid)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_existe boolean;
begin
  select true into v_existe from public.contratos c where c.id = p_contrato_id;
  if not coalesce(v_existe, false) then return 0; end if;
  if (select auth.role()) <> 'service_role'
     and not (public.es_agente() or public.es_portal()) then
    return 0;
  end if;
  return coalesce((
      select sum(ra.importe_aplicado)
        from public.recibi_aplicaciones ra
        join public.facturas r on r.id = ra.recibi_id
        join public.facturas f on f.id = ra.factura_id
       where f.contrato_id = p_contrato_id
         and not coalesce(r.anulada, false)
         and not coalesce(f.anulada, false)
    ), 0)
    + coalesce((
      select sum(
        r.total - coalesce((
          select sum(ra.importe_aplicado)
            from public.recibi_aplicaciones ra
            join public.facturas f2 on f2.id = ra.factura_id
           where ra.recibi_id = r.id
             and f2.contrato_id is not null
             and not coalesce(f2.anulada, false)
        ), 0))
        from public.facturas r
       where r.tipo = 'recibi'
         and r.contrato_id = p_contrato_id
         and not coalesce(r.anulada, false)
    ), 0);
end;
$function$
