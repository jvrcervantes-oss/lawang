create or replace function public.contratos_del_mismo_comprador(p_contrato_id uuid)
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select p_contrato_id
  union
  select cc2.contrato_id
    from public.contrato_compradores cc1
    join public.contrato_compradores cc2 on cc2.client_id = cc1.client_id
   where cc1.contrato_id = p_contrato_id;
$$;

revoke all on function public.contratos_del_mismo_comprador(uuid) from public, anon;
grant execute on function public.contratos_del_mismo_comprador(uuid) to authenticated;
;
