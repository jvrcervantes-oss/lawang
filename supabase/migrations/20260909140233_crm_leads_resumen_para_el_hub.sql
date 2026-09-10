-- Cifra de la tarjeta del hub. Existe para no traerse los 103 leads enteros solo para
-- contar: el hub pinta once tarjetas y las pide todas a la vez.
-- Cuenta "sin contactar" y no "leads totales" a proposito: el total no le pide nada a
-- nadie, y lo que hay que mirar cada mañana es a cuanta gente se ha dejado sin contestar.
create or replace function public.crm_leads_resumen()
returns table (total bigint, nuevos bigint, parados bigint)
language sql stable security definer set search_path to ''
as $$
  select count(*),
         count(*) filter (where coalesce(e.estado, 'nuevo') = 'nuevo'),
         count(*) filter (where coalesce(e.estado, 'nuevo') = 'nuevo'
                            and coalesce(e.estado_desde, l.created_at) < now() - interval '14 days')
    from public.leads l
    left join public.lead_estado e on e.lead_id = l.id
   where public.puede('leads');
$$;

revoke execute on function public.crm_leads_resumen() from public, anon;
grant execute on function public.crm_leads_resumen() to authenticated;;
