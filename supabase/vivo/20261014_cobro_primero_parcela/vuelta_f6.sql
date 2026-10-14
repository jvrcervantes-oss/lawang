-- Vuelta atrás de f6_retira_parte_cobrada.sql: las dos funciones tal como estaban en Supabase Lawang el 14-oct-2026
-- (pg_get_functiondef, leídas justo antes de borrar), con los permisos que tenían (solo service_role).

CREATE OR REPLACE FUNCTION public.unidad_parte_cobrada_split(p_unidad uuid)
 RETURNS TABLE(cobrado_suelo numeric, cobrado_obra numeric, obra_firmada boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select x.cobrado_suelo, x.cobrado_obra, x.obra_firmada from public.unidad_cobro_reparto(p_unidad) x;
$function$;

CREATE OR REPLACE FUNCTION public.unidad_parte_cobrada(p_unidad uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select cobrado_suelo + cobrado_obra
    from public.unidad_parte_cobrada_split(p_unidad);
$function$;

revoke all on function public.unidad_parte_cobrada_split(uuid) from public, anon, authenticated;
revoke all on function public.unidad_parte_cobrada(uuid) from public, anon, authenticated;
grant execute on function public.unidad_parte_cobrada_split(uuid) to service_role;
grant execute on function public.unidad_parte_cobrada(uuid) to service_role;
