-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · etapa B · base comun (7-oct-2026): «¿de que empresa es esto?» para contrato, unidad, factura y solicitud de pago. Las usan las puertas de admin por empresa (es_admin_de(empresa)).
-- Solo devuelven la clave de la empresa, nunca datos; exigen ser del equipo (es_agente()) o ser el servidor. STABLE, DEFINER, search_path vacio. EXECUTE: authenticated y lw_lector; nada a anon.
-- (Aplicada en produccion el 7-oct con el nombre f2_b0_ayudas_empresa_de.)
-- destructivo-ok: cuatro funciones nuevas; no borra datos
-- REVERTIR: drop function public.empresa_de_contrato(uuid), public.empresa_de_unidad(uuid), public.empresa_de_factura(uuid), public.empresa_de_solicitud_pago(uuid); (solo si ninguna funcion de los bloques 1-4 las usa ya)
create or replace function public.empresa_de_contrato(p_id uuid) returns text language sql stable security definer set search_path = '' as $$
  select pr.empresa from public.contratos c join public.proyectos pr on pr.id = c.proyecto_id
   where c.id = p_id and ((select auth.uid()) is null or public.es_agente()) $$;
create or replace function public.empresa_de_unidad(p_id uuid) returns text language sql stable security definer set search_path = '' as $$
  select pr.empresa from public.unidades u join public.proyectos pr on pr.id = u.proyecto_id
   where u.id = p_id and ((select auth.uid()) is null or public.es_agente()) $$;
create or replace function public.empresa_de_factura(p_id uuid) returns text language sql stable security definer set search_path = '' as $$
  select coalesce(pr.empresa, (select e.clave from public.empresas e where e.sociedad_clave = f.sociedad))
    from public.facturas f left join public.proyectos pr on pr.id = f.proyecto_id
   where f.id = p_id and ((select auth.uid()) is null or public.es_agente()) $$;
create or replace function public.empresa_de_solicitud_pago(p_id uuid) returns text language sql stable security definer set search_path = '' as $$
  select public.empresa_de_contrato(s.contrato_id)
    from public.solicitudes_pago s
   where s.id = p_id and ((select auth.uid()) is null or public.es_agente()) $$;
revoke all on function public.empresa_de_contrato(uuid), public.empresa_de_unidad(uuid), public.empresa_de_factura(uuid), public.empresa_de_solicitud_pago(uuid) from public, anon;
grant execute on function public.empresa_de_contrato(uuid), public.empresa_de_unidad(uuid), public.empresa_de_factura(uuid), public.empresa_de_solicitud_pago(uuid) to authenticated, lw_lector;
