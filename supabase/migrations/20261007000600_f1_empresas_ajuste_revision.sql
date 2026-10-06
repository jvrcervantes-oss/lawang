-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Ajuste tras revision de codigo (7-oct-2026): empresa_de_proyecto no debe dejar a cualquier authenticated (p. ej. un comprador del portal) leer la empresa por uuid.
-- Llamador previsto con nombre: F2b (puede_proyecto*/proyecto_visible/unidad_visible/cliente_visible). Sin sesion de usuario (service_role) sigue respondiendo.
-- destructivo-ok: solo reemplaza el cuerpo de una funcion creada hoy.
-- REVERTIR: recrear empresa_de_proyecto sin la condicion de es_agente (ver 20261007000500_f1_empresas.sql).
create or replace function public.empresa_de_proyecto(p_id uuid) returns text
language sql stable security definer set search_path = '' as $$
  select p.empresa from public.proyectos p
   where p.id = p_id and ((select auth.uid()) is null or public.es_agente())
$$;
