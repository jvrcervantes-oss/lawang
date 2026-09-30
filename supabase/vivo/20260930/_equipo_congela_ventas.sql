-- VOLCADO DE PRODUCCION (Supabase Lawang) del 2026-09-30: pg_get_functiondef(public._equipo_congela_ventas).
-- NO es una migracion: no se aplica. Referencia para construir sobre el cuerpo VIVO (encargo 20260930_lawang_equipos_venta_asistente, F1).
-- ---- fin cabecera ----
CREATE OR REPLACE FUNCTION public._equipo_congela_ventas(p_equipo uuid, p_email text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; n int := 0;
begin
  for r in
    select k.contrato_id from public.contrato_closer k
     where k.equipo_congelado_en is null
       and ((p_email is not null and lower(k.closer_email) = lower(p_email))
            or (p_equipo is not null and exists (select 1 from public.equipo_miembros em
                                                   where em.equipo_id = p_equipo
                                                     and lower(em.closer_email) = lower(k.closer_email))))
  loop
    perform public._venta_congela_equipo(r.contrato_id);
    n := n + 1;
  end loop;
  return n;
end $function$
