-- destructivo-ok: solo se sustituyen dos CHECK de traza_coincidencias, tabla creada hoy y vacía (ni una fila), para admitir el origen comprador.
-- Trazabilidad GHL — segunda fuente propia: COMPRADORES (`clients`), 23-sep-2026.
-- Al probar con la primera cuenta (2.235 contactos de la etiqueta «inversor realtyfy")
-- salieron 0 coincidencias con los 132 leads de Meta y 23 con los 197 compradores: la
-- doble banda que se quiere ver pasa en la negociación, no en el lead frío. Lead de Meta y
-- comprador son el MISMO funnel (Lawang) para contar funnels: que un lead acabe comprando
-- no es jugar a dos bandas.

alter table public.traza_coincidencias drop constraint if exists traza_coincidencias_origen_check;
alter table public.traza_coincidencias drop constraint if exists traza_origen_cuenta;
alter table public.traza_coincidencias add constraint traza_coincidencias_origen_check
  check (origen in ('lawang','comprador','ghl'));
alter table public.traza_coincidencias add constraint traza_origen_cuenta
  check ((origen = 'ghl') = (cuenta_id is not null));

create or replace function public.traza_coincidencias_listar()
returns table(huella text, tipos text[], n_funnels integer, primera_alta timestamptz, apariciones jsonb)
language plpgsql stable security definer set search_path to '' as $$
begin
  if not public.es_super_admin() then raise exception 'sin permiso'; end if;
  return query
  with ap as (
    select distinct on (t.huella, t.origen, t.cuenta_id, t.ref_id)
           t.huella, t.tipo, t.origen, t.cuenta_id, t.ref_id, t.fuente, t.alta,
           case t.origen when 'lawang' then 'Lawang · lead' when 'comprador' then 'Lawang · comprador'
                else c.nombre end as funnel,
           coalesce(l.name, k.full_name) as nombre, l.project as proyecto
      from public.traza_coincidencias t
      left join public.traza_cuentas c on c.id = t.cuenta_id
      left join public.leads   l on t.origen = 'lawang'    and l.id::text = t.ref_id
      left join public.clients k on t.origen = 'comprador' and k.id::text = t.ref_id
     order by t.huella, t.origen, t.cuenta_id, t.ref_id, t.alta
  )
  select ap.huella,
         array_agg(distinct ap.tipo),
         count(distinct coalesce(ap.cuenta_id::text, 'lawang'))::int,
         min(ap.alta),
         jsonb_agg(jsonb_build_object(
           'funnel', ap.funnel, 'origen', ap.origen, 'ref_id', ap.ref_id,
           'fuente', ap.fuente, 'alta', ap.alta,
           'nombre', ap.nombre, 'proyecto', ap.proyecto) order by ap.alta nulls last)
    from ap
   group by ap.huella
  having count(distinct coalesce(ap.cuenta_id::text, 'lawang')) >= 2
   order by min(ap.alta) desc nulls last;
end $$;
revoke execute on function public.traza_coincidencias_listar() from public, anon;
grant execute on function public.traza_coincidencias_listar() to authenticated;
