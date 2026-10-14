CREATE OR REPLACE FUNCTION public.condiciones_comision_datos()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_co jsonb; v_nco int; v_tr jsonb; v_ntr int;
begin
  if public.uid_sesion() is null then
    raise exception 'condiciones_comision_datos: sin sesión' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'equipo_id', c.equipo_id, 'proyecto_id', c.proyecto_id,
                                               'nivel', c.nivel, 'closer_email', c.closer_email,
                                               'pct_comision', c.pct_comision, 'base_calculo', c.base_calculo,
                                               'importe_fijo', c.importe_fijo, 'activo', c.activo,
                                               'vigente_desde', c.vigente_desde, 'vigente_hasta', c.vigente_hasta,
                                               'created_at', c.created_at, 'sustituye_a', c.sustituye_a,
                                               'empresa', c.empresa)
                            order by c.rn) filter (where c.rn <= 2000), '[]'::jsonb), count(*)::int
    into v_co, v_nco
    from (select x.id, x.equipo_id, x.proyecto_id, x.nivel, x.closer_email, x.pct_comision, x.base_calculo,
                 x.importe_fijo, x.activo, x.vigente_desde, x.vigente_hasta, x.created_at, x.sustituye_a, x.empresa,
                 row_number() over (order by x.created_at desc, x.id) as rn
            from public.condiciones_comision x order by x.created_at desc, x.id limit 2001) c;
  select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'condicion_id', t.condicion_id, 'orden', t.orden,
                                               'disparador_tipo', t.disparador_tipo, 'umbral', t.umbral,
                                               'pct_tramo', t.pct_tramo)
                            order by t.rn) filter (where t.rn <= 10000), '[]'::jsonb), count(*)::int
    into v_tr, v_ntr
    from (select x.id, x.condicion_id, x.orden, x.disparador_tipo, x.umbral, x.pct_tramo,
                 row_number() over (order by x.orden, x.id) as rn
            from public.condicion_tramos x order by x.orden, x.id limit 10001) t;
  return jsonb_build_object('condiciones', v_co, 'tramos', v_tr,
                            'recortado', (select coalesce(jsonb_agg(k), '[]'::jsonb) from (
                                            select 'condiciones' k where v_nco > 2000
                                            union all select 'tramos' where v_ntr > 10000) r));
end $function$
