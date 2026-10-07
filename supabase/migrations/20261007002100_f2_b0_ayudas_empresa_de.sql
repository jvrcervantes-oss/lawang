-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · etapa B · base comun (7-oct-2026): empresa_de_unidad(uuid) = «¿de que empresa es esta unidad?». Aplicada en produccion el 7-oct con el nombre f2_b0_ayudas_empresa_de
--   junto con empresa_de_contrato / empresa_de_factura / empresa_de_solicitud_pago, que los bloques 2 y 3 ya versionaron (20261008200500, 20261008299000). Esta es la unica que faltaba en el repo y la usa el bloque 1.
-- Solo devuelve la clave de la empresa, nunca datos; exige ser del equipo (es_agente()) o ser el servidor. STABLE, DEFINER, search_path vacio. EXECUTE: authenticated y lw_lector; nada a anon.
-- destructivo-ok: una funcion; no borra datos
-- REVERTIR: drop function public.empresa_de_unidad(uuid); (solo si ninguna funcion del bloque 1 la usa ya)
create or replace function public.empresa_de_unidad(p_id uuid) returns text language sql stable security definer set search_path = '' as $$
  select pr.empresa from public.unidades u join public.proyectos pr on pr.id = u.proyecto_id
   where u.id = p_id and ((select auth.uid()) is null or public.es_agente()) $$;
revoke all on function public.empresa_de_unidad(uuid) from public, anon;
grant execute on function public.empresa_de_unidad(uuid) to authenticated, lw_lector;
