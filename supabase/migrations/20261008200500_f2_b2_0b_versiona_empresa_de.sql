-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · bloque 2 · migracion 0b (8-oct-2026): VERSIONA tres funciones que ya viven en produccion y que este bloque llama (las crearon el 2B/2A y no estaban en ninguna migracion):
--   empresa_de_contrato, empresa_de_solicitud_pago, empresa_de_factura. Texto identico al vivo (pg_get_functiondef) y mismos permisos. Sin cambio de comportamiento; el bloque 3 las versiona
--   igual en 20261008299000: al fusionar no choca porque el texto es el mismo. Asi una base reconstruida desde migraciones no aborta en la migracion 1.
-- destructivo-ok: create or replace con el mismo cuerpo; sin borrar datos
-- REVERTIR: no hace falta (identico al vivo)
create or replace function public.empresa_de_contrato(p_id uuid) returns text
language sql stable security definer set search_path = '' as $$
  select pr.empresa from public.contratos c join public.proyectos pr on pr.id = c.proyecto_id
   where c.id = p_id and ((select auth.uid()) is null or public.es_agente()) $$;

create or replace function public.empresa_de_solicitud_pago(p_id uuid) returns text
language sql stable security definer set search_path = '' as $$
  select public.empresa_de_contrato(s.contrato_id)
    from public.solicitudes_pago s
   where s.id = p_id and ((select auth.uid()) is null or public.es_agente()) $$;

create or replace function public.empresa_de_factura(p_id uuid) returns text
language sql stable security definer set search_path = '' as $$
  select coalesce(pr.empresa, (select e.clave from public.empresas e where e.sociedad_clave = f.sociedad))
    from public.facturas f left join public.proyectos pr on pr.id = f.proyecto_id
   where f.id = p_id and ((select auth.uid()) is null or public.es_agente()) $$;

revoke all on function public.empresa_de_contrato(uuid), public.empresa_de_solicitud_pago(uuid), public.empresa_de_factura(uuid) from public, anon;
grant execute on function public.empresa_de_contrato(uuid), public.empresa_de_solicitud_pago(uuid), public.empresa_de_factura(uuid) to authenticated, lw_lector;
