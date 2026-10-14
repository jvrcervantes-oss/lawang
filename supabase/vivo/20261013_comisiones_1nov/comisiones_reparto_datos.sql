CREATE OR REPLACE FUNCTION public.comisiones_reparto_datos()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_de jsonb; v_nde int; v_di jsonb; v_ndi int;
begin
  if public.uid_sesion() is null then
    raise exception 'comisiones_reparto_datos: sin sesión' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'contrato_raiz_id', d.contrato_raiz_id,
                                               'beneficiario_email', d.beneficiario_email, 'nivel', d.nivel,
                                               'importe', d.importe, 'importe_ajustado', d.importe_ajustado,
                                               'ajuste_motivo', d.ajuste_motivo, 'anulado_motivo', d.anulado_motivo,
                                               'moneda', d.moneda, 'estado', d.estado, 'disparado_en', d.disparado_en,
                                               'pagado_por', d.pagado_por, 'pagado_en', d.pagado_en,
                                               'disparado_por_snapshot', d.disparado_por_snapshot)
                            order by d.rn) filter (where d.rn <= 20000), '[]'::jsonb), count(*)::int
    into v_de, v_nde
    from (select x.id, x.contrato_raiz_id, x.beneficiario_email, x.nivel, x.importe, x.importe_ajustado, x.ajuste_motivo,
                 x.anulado_motivo, x.moneda, x.estado, x.disparado_en, x.pagado_por, x.pagado_en,
                 x.disparado_por_snapshot,
                 row_number() over (order by x.disparado_en desc, x.id) as rn
            from public.comisiones_devengadas x
           where x.nivel in ('closer', 'setter', 'team_lead')
           order by x.disparado_en desc, x.id limit 20001) d;
  -- el devengo de cada diferencia se lee con la RLS de comisiones_devengadas (como el embebido de PostgREST):
  -- si el lector no lo ve, sale null.
  select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'numero', f.numero, 'devengo_id', f.devengo_id,
                                               'importe', f.importe, 'estado', f.estado, 'motivo', f.motivo,
                                               'created_at', f.created_at,
                                               'devengo', case when f.d_id is not null then
                                                 jsonb_build_object('nivel', f.d_nivel,
                                                                    'beneficiario_email', f.d_benef,
                                                                    'contrato_raiz_id', f.d_raiz,
                                                                    'moneda', f.d_moneda) end)
                            order by f.rn) filter (where f.rn <= 5000), '[]'::jsonb), count(*)::int
    into v_di, v_ndi
    from (select x.id, x.numero, x.devengo_id, x.importe, x.estado, x.motivo, x.created_at,
                 d.id as d_id, d.nivel as d_nivel, d.beneficiario_email as d_benef, d.contrato_raiz_id as d_raiz,
                 d.moneda as d_moneda,
                 row_number() over (order by x.created_at desc, x.id) as rn
            from public.comisiones_diferencias x
            left join public.comisiones_devengadas d on d.id = x.devengo_id
           order by x.created_at desc, x.id limit 5001) f;
  return jsonb_build_object('devengadas', v_de, 'diferencias', v_di,
                            'recortado', (select coalesce(jsonb_agg(k), '[]'::jsonb) from (
                                            select 'devengadas' k where v_nde > 20000
                                            union all select 'diferencias' where v_ndi > 5000) r));
end $function$
