-- destructivo-ok: el unico DROP es de un trigger que no existe todavia; es la forma
-- idempotente de crearlo (`drop if exists` + `create`). No borra datos ni toca filas.
create or replace function public.clients_pone_dueno() returns trigger
language plpgsql security definer set search_path to ''
as $$
begin
  new.propietario := coalesce(nullif(btrim(new.propietario), ''), (select auth.email()));
  return new;
end $$;

drop trigger if exists trg_clients_pone_dueno on public.clients;
create trigger trg_clients_pone_dueno
  before insert on public.clients
  for each row execute function public.clients_pone_dueno();

create or replace function public.cliente_visible(p_propietario text, p_client_id uuid)
returns boolean language sql stable security definer set search_path to ''
as $$
  select public.es_admin()
      or coalesce(p_propietario = (select auth.email()), false)
      or (public.es_gestor() and exists (
            select 1
              from public.contrato_compradores cc
              join public.contratos c on c.id = cc.contrato_id
             where cc.client_id = p_client_id
               and public.es_manager_de(c.proyecto_id)));
$$;;
