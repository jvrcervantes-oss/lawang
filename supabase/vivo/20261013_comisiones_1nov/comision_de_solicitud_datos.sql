CREATE OR REPLACE FUNCTION public.comision_de_solicitud_datos(p_solicitud uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lista jsonb; v_n int;
begin
  if public.uid_sesion() is null then
    raise exception 'comision_de_solicitud_datos: sin sesión' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('estado', x.estado, 'pagado_en', x.pagado_en, 'importe', x.importe,
                                               'importe_ajustado', x.importe_ajustado, 'moneda', x.moneda)), '[]'::jsonb),
         count(*)::int
    into v_lista, v_n
    from (select d.estado, d.pagado_en, d.importe, d.importe_ajustado, d.moneda
            from public.comisiones_devengadas d
           where d.solicitud_id = p_solicitud and d.nivel in ('manager', 'estandar', 'propia')
           limit 2) x;
  return jsonb_build_object('comision', case when v_n = 1 then v_lista -> 0 end);
end $function$
