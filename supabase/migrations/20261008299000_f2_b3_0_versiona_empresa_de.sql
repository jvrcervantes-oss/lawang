-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · BLOQUE 3 · migracion 0 (7-oct-2026): VERSIONA dos resolutores que existian en vivo sin migracion en el repo (consulta de Datos): empresa_de_contrato y empresa_de_factura.
--   Las usan las migraciones 301000 y 303000 de este bloque; sin esto una base reconstruida desde las migraciones abortaria. Copia literal de pg_get_functiondef de produccion (7-oct-2026): en vivo es un create or replace sin efecto.
-- destructivo-ok: create or replace de dos funciones con el mismo texto que ya tienen en produccion; sin tocar datos
-- REVERTIR: no procede (las funciones ya existian antes de este bloque)
create or replace function public.empresa_de_contrato(p_id uuid) returns text
 language sql stable security definer set search_path = '' as $$
  select pr.empresa from public.contratos c join public.proyectos pr on pr.id = c.proyecto_id
   where c.id = p_id and ((select auth.uid()) is null or public.es_agente()) $$;
create or replace function public.empresa_de_factura(p_id uuid) returns text
 language sql stable security definer set search_path = '' as $$
  select coalesce(pr.empresa, (select e.clave from public.empresas e where e.sociedad_clave = f.sociedad))
    from public.facturas f left join public.proyectos pr on pr.id = f.proyecto_id
   where f.id = p_id and ((select auth.uid()) is null or public.es_agente()) $$;
revoke all on function public.empresa_de_contrato(uuid), public.empresa_de_factura(uuid) from public, anon;
grant execute on function public.empresa_de_contrato(uuid), public.empresa_de_factura(uuid) to authenticated, lw_lector;
