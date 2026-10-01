-- VOLCADO DE PRODUCCION (Supabase Lawang) del 2026-09-30: pg_get_functiondef(public.proyecto_visible).
-- NO es una migracion: no se aplica. Referencia para construir sobre el cuerpo VIVO (encargo 20260930_lawang_equipos_venta_asistente, F1).
-- ---- fin cabecera ----
CREATE OR REPLACE FUNCTION public.proyecto_visible(p_proyecto_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case
    when public.es_admin() then true
    when public.es_manager_de(p_proyecto_id) then true
    when p_proyecto_id is null then false
    else exists (
      select 1 from public.usuarios u
       where u.user_id = (select auth.uid()) and u.activo
         and p_proyecto_id = any (u.proyectos))
  end
$function$
