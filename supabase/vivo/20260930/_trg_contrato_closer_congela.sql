-- VOLCADO DE PRODUCCION (Supabase Lawang) del 2026-09-30: pg_get_functiondef(public._trg_contrato_closer_congela).
-- NO es una migracion: no se aplica. Referencia para construir sobre el cuerpo VIVO (encargo 20260930_lawang_equipos_venta_asistente, F1).
-- Extra (no pedido en el encargo). Triggers: trg_contrato_closer_congela_alta AFTER INSERT ON public.contrato_closer;
--   trg_contrato_closer_congela_cambio AFTER UPDATE OF closer_email ON public.contrato_closer WHEN (lower(old.closer_email) IS DISTINCT FROM lower(new.closer_email)).
-- ---- fin cabecera ----
CREATE OR REPLACE FUNCTION public._trg_contrato_closer_congela()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_eq_antes uuid; v_eq_nuevo uuid;
begin
  if tg_op = 'UPDATE' then
    select k.equipo_id into v_eq_antes from public.contrato_closer k where k.contrato_id = new.contrato_id;
    update public.contrato_closer k set equipo_id = null, manager_email = null, equipo_congelado_en = null
     where k.contrato_id = new.contrato_id;
  end if;
  perform public._venta_congela_equipo(new.contrato_id);
  if tg_op = 'UPDATE' then
    select k.equipo_id into v_eq_nuevo from public.contrato_closer k where k.contrato_id = new.contrato_id;
    if v_eq_antes is distinct from v_eq_nuevo then
      delete from public.contrato_roles_equipo re
       where re.contrato_raiz_id = new.contrato_id
         and re.equipo_id is distinct from v_eq_nuevo
         and not exists (select 1 from public.comisiones_devengadas d
                          where d.contrato_raiz_id = re.contrato_raiz_id and d.nivel = re.rol
                            and lower(d.beneficiario_email) = lower(re.email) and d.estado <> 'anulada');
    end if;
  end if;
  return null;
end $function$
