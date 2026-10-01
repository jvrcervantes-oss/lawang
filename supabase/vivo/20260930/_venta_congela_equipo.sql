-- VOLCADO DE PRODUCCION (Supabase Lawang) del 2026-09-30: pg_get_functiondef(public._venta_congela_equipo).
-- NO es una migracion: no se aplica. Referencia para construir sobre el cuerpo VIVO (encargo 20260930_lawang_equipos_venta_asistente, F1).
-- ---- fin cabecera ----
CREATE OR REPLACE FUNCTION public._venta_congela_equipo(p_raiz uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_eq uuid; v_man text;
begin
  if not exists (select 1 from public.contrato_closer k where k.contrato_id = p_raiz and k.equipo_congelado_en is null) then
    return;
  end if;
  select em.equipo_id, ev.manager_email into v_eq, v_man
    from public.contrato_closer k
    join public.equipo_miembros em on lower(em.closer_email) = lower(k.closer_email)
    join public.equipos_venta ev on ev.id = em.equipo_id and ev.activo
   where k.contrato_id = p_raiz
     and em.desde <= coalesce(k.fecha_venta, current_date)
     and (em.hasta is null or em.hasta >= coalesce(k.fecha_venta, current_date))
   order by em.created_at desc
   limit 1;
  update public.contrato_closer k
     set equipo_id = v_eq, manager_email = v_man, equipo_congelado_en = now()
   where k.contrato_id = p_raiz and k.equipo_congelado_en is null;
end $function$
