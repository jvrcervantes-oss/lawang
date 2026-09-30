-- VOLCADO DE PRODUCCION (Supabase Lawang) del 2026-09-30: pg_get_functiondef(public._trg_equipo_miembros_recongela).
-- NO es una migracion: no se aplica. Referencia para construir sobre el cuerpo VIVO (encargo 20260930_lawang_equipos_venta_asistente, F1).
-- ---- fin cabecera ----
CREATE OR REPLACE FUNCTION public._trg_equipo_miembros_recongela()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record;
begin
  for r in select k.contrato_id from public.contrato_closer k
            where lower(k.closer_email) = lower(new.closer_email) and k.equipo_congelado_en is null loop
    perform public._venta_congela_equipo(r.contrato_id);
  end loop;
  return null;
end $function$
