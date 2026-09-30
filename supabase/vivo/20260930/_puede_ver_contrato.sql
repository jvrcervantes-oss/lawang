-- VOLCADO DE PRODUCCION (Supabase Lawang) del 2026-09-30: pg_get_functiondef(public._puede_ver_contrato).
-- NO es una migracion: no se aplica. Referencia para construir sobre el cuerpo VIVO (encargo 20260930_lawang_equipos_venta_asistente, F1).
-- ---- fin cabecera ----
CREATE OR REPLACE FUNCTION public._puede_ver_contrato(p_contrato uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select public.es_super_admin() or (public.es_agente() and exists (
    select 1 from public.contratos c
    where c.id = p_contrato
      and (public.es_suyo(c.creado_por) or public.es_manager_de(c.proyecto_id))))
$function$
