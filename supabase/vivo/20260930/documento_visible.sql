-- VOLCADO DE PRODUCCION (Supabase Lawang) del 2026-09-30: pg_get_functiondef(public.documento_visible).
-- NO es una migracion: no se aplica. Referencia para construir sobre el cuerpo VIVO (encargo 20260930_lawang_equipos_venta_asistente, F1).
-- ---- fin cabecera ----
CREATE OR REPLACE FUNCTION public.documento_visible(p_autor text, p_proyecto_id uuid, p_contrato_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select public.es_suyo(p_autor)
      or public.es_manager_de(p_proyecto_id)
      or (p_contrato_id is not null and exists (
            select 1 from public.contratos c
             where c.id = p_contrato_id
               and public.contrato_visible(c.creado_por, c.proyecto_id)))
$function$
