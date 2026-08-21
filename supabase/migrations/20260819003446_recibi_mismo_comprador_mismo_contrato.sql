create or replace function public.contratos_mismo_comprador(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_a is not null and p_b is not null and (
    p_a = p_b or coalesce((
      select public.contrato_identificadores(a.datos)
          && public.contrato_identificadores(b.datos)
        from public.contratos a, public.contratos b
       where a.id = p_a and b.id = p_b
    ), false)
  );
$$;

create or replace function public.contratos_del_mismo_comprador(p_contrato_id uuid)
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select c.id
    from public.contratos c
   where c.id = p_contrato_id
      or public.contrato_identificadores(c.datos)
      && (select public.contrato_identificadores(datos)
            from public.contratos where id = p_contrato_id);
$$;

revoke all on function public.contratos_mismo_comprador(uuid, uuid) from public, anon;
grant execute on function public.contratos_mismo_comprador(uuid, uuid) to authenticated;
revoke all on function public.contratos_del_mismo_comprador(uuid) from public, anon;
grant execute on function public.contratos_del_mismo_comprador(uuid) to authenticated;;
