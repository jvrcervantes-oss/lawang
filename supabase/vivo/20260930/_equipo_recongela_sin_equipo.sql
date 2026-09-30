-- VOLCADO DE PRODUCCION (Supabase Lawang) del 2026-09-30: pg_get_functiondef(public._equipo_recongela_sin_equipo).
-- NO es una migracion: no se aplica. Referencia para construir sobre el cuerpo VIVO (encargo 20260930_lawang_equipos_venta_asistente, F1).
-- Extra (no pedido en el encargo): la llama el trigger BEFORE trg_equipo_miembros_congela; decide si un alta con `desde` pasado re-atribuye ventas.
-- ---- fin cabecera ----
CREATE OR REPLACE FUNCTION public._equipo_recongela_sin_equipo(p_email text, p_desde date, p_hasta date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; n int := 0;
begin
  for r in
    select k.contrato_id from public.contrato_closer k
     where lower(k.closer_email) = lower(p_email)
       and k.equipo_congelado_en is not null and k.equipo_id is null
       and coalesce(k.fecha_venta, current_date) >= p_desde
       and (p_hasta is null or coalesce(k.fecha_venta, current_date) <= p_hasta)
       and not exists (select 1 from public.comisiones_devengadas d where d.contrato_raiz_id = k.contrato_id)
  loop
    update public.contrato_closer k set equipo_id = null, manager_email = null, equipo_congelado_en = null
     where k.contrato_id = r.contrato_id;
    n := n + 1;
  end loop;
  return n;
end $function$
