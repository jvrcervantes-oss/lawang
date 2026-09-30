-- VOLCADO DE PRODUCCION (Supabase Lawang) del 2026-09-30: pg_get_functiondef(public._trg_equipos_venta_congela).
-- NO es una migracion: no se aplica. Referencia para construir sobre el cuerpo VIVO (encargo 20260930_lawang_equipos_venta_asistente, F1).
-- Extra (no pedido en el encargo). Trigger: CREATE TRIGGER trg_equipos_venta_congela BEFORE UPDATE ON public.equipos_venta FOR EACH ROW EXECUTE FUNCTION _trg_equipos_venta_congela()
-- ---- fin cabecera ----
CREATE OR REPLACE FUNCTION public._trg_equipos_venta_congela()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if lower(coalesce(old.manager_email, '')) is distinct from lower(coalesce(new.manager_email, ''))
     or old.activo is distinct from new.activo then
    perform public._equipo_congela_ventas(old.id, null);
  end if;
  return new;
end $function$
