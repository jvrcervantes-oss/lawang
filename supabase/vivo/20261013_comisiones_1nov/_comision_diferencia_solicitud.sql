CREATE OR REPLACE FUNCTION public._comision_diferencia_solicitud(p_dif uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$

declare x public.comisiones_diferencias; d public.comisiones_devengadas; v_num text; v_por uuid; v_sp uuid;

begin

  select * into x from public.comisiones_diferencias where id = p_dif;

  select * into d from public.comisiones_devengadas where id = x.devengo_id;

  if x.importe is null or x.importe <= 0 or d.nivel not in ('manager', 'estandar', 'propia') or x.solicitud_id is not null then

    return x.solicitud_id;

  end if;

  select numero into v_num from public.contratos where id = d.contrato_raiz_id;

  v_por := coalesce(

    auth.uid(),

    (select u.user_id from public.usuarios u where lower(u.email) = lower(d.beneficiario_email) and u.activo limit 1),

    (select u.user_id from public.usuarios u where u.rol = 'super_admin' and u.activo order by u.email limit 1));

  insert into public.solicitudes_pago (contrato_id, concepto, importe, moneda, origen, beneficiario_email, creado_por)

  values (d.contrato_raiz_id,

          'Diferencia ' || x.numero || ' por cambio de contrato — comisión '

            || case d.nivel when 'manager' then 'manager' when 'propia' then 'venta propia' else 'estándar' end

            || ' de la venta ' || coalesce(v_num, '?') || ': base ' || coalesce(round(x.base_antes, 2)::text, '?')

            || ' → ' || coalesce(round(x.base_despues, 2)::text, '?') || ' ' || d.moneda

            || ' — importe BRUTO (retención al pagar)',

          x.importe, d.moneda, 'comision_automatica', d.beneficiario_email, v_por)

  returning id into v_sp;

  update public.comisiones_diferencias set solicitud_id = v_sp where id = x.id;

  return v_sp;

end $function$
