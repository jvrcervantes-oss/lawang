-- VOLCADO DE PRODUCCION (Supabase Lawang) del 2026-09-30: pg_get_functiondef(public._trg_equipo_miembros_congela).
-- NO es una migracion: no se aplica. Referencia para construir sobre el cuerpo VIVO (encargo 20260930_lawang_equipos_venta_asistente, F1).
-- Extra (no pedido en el encargo). Trigger: CREATE TRIGGER trg_equipo_miembros_congela BEFORE INSERT OR DELETE OR UPDATE ON public.equipo_miembros FOR EACH ROW EXECUTE FUNCTION _trg_equipo_miembros_congela()
-- ---- fin cabecera ----
CREATE OR REPLACE FUNCTION public._trg_equipo_miembros_congela()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    perform public._equipo_congela_ventas(old.equipo_id, old.closer_email);
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    perform public._equipo_congela_ventas(new.equipo_id, new.closer_email);
    perform public._equipo_recongela_sin_equipo(new.closer_email, new.desde, new.hasta);
    return new;
  end if;
  return old;
end $function$
