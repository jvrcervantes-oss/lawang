-- VOLCADO DE PRODUCCION (Supabase Lawang) del 2026-09-30: pg_get_functiondef(public.contratos_cobrado_equipo).
-- NO es una migracion: no se aplica. Referencia para construir sobre el cuerpo VIVO (encargo 20260930_lawang_equipos_venta_asistente, F1).
-- ---- fin cabecera ----
CREATE OR REPLACE FUNCTION public.contratos_cobrado_equipo()
 RETURNS TABLE(contrato_id uuid, cobrado numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select c.id, public.contrato_cobrado(c.id)
    from public.contratos c
   where public.es_agente() and public.contrato_visible(c.creado_por, c.proyecto_id)
$function$
