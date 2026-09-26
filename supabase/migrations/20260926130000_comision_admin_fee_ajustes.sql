-- Fee fijo: dos ajustes de la consulta de deploy (Administración), 26-sep-2026.
--
-- 1. Un fee puesto a 0 ya NO anula la línea pendiente del mes: la deja a 0.
--    Anular es definitivo (la línea anulada no renace, a propósito), así que un
--    0 tecleado por error se comía ese mes sin avisar. A 0 sigue viva y, si se
--    corrige el fee, se pone al día como cualquier pendiente.
-- 2. El abono de una línea de fee se fecha en BALI, no en UTC: entre las 00:00
--    y las 08:00 de Bali del día 1 caía en el mes anterior. Los abonos de
--    devengo siguen con current_date, igual que sus devengos (el disparador de
--    facturas), para no desalinear las dos mitades de una misma serie.

create or replace function public.comision_admin_devenga_fees()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_hoy     date := (now() at time zone 'Asia/Makassar')::date;
  v_desde   date;
  v_mes     date;
  v_fin     date;
  f         record;
  l         record;
  n_nuevas  integer := 0;
  n_puestas integer := 0;
  n_revisar integer := 0;
begin
  if not public.es_super_admin() then
    raise exception 'comision_admin_devenga_fees: solo super_admin';
  end if;

  select date_trunc('month', min(efectivo_desde))::date into v_desde
    from public.comision_admin_fees where efectivo_desde <= v_hoy;
  if v_desde is null then
    return jsonb_build_object('ok', true, 'nuevas', 0, 'puestas_al_dia', 0, 'a_revisar', 0);
  end if;

  for v_mes in
    select g::date from generate_series(v_desde, date_trunc('month', v_hoy)::date, interval '1 month') g
  loop
    v_fin := (v_mes + interval '1 month' - interval '1 day')::date;

    for f in
      select distinct on (x.sociedad) x.*
        from public.comision_admin_fees x
       where x.efectivo_desde <= v_fin
       order by x.sociedad, x.efectivo_desde desc, x.created_at desc, x.id desc
    loop
      select * into l from public.comision_admin_lineas
       where tipo_linea = 'fee' and sociedad = f.sociedad and devengado_el = v_mes;

      if l.id is null then
        if f.importe > 0 then
          insert into public.comision_admin_lineas (
            tipo_linea, recibi_numero, sociedad, devengado_el, base_total, moneda,
            pct_aplicado, importe, fee_id, estado, nota, snapshot
          ) values (
            'fee', 'FEE ' || to_char(v_mes, 'YYYY-MM'), f.sociedad, v_mes, 0, f.moneda,
            0, f.importe, f.id, 'pendiente',
            'Fee fijo de ' || to_char(v_mes, 'MM/YYYY') || '.',
            jsonb_build_object('fee_id', f.id, 'importe', f.importe, 'moneda', f.moneda,
                               'efectivo_desde', f.efectivo_desde, 'devengado_en', now())
          )
          on conflict (sociedad, devengado_el) where tipo_linea = 'fee' do nothing;
          if found then n_nuevas := n_nuevas + 1; end if;
        end if;
      elsif l.anulada then
        null;  -- ese mes se decidió no cobrarlo
      elsif l.fee_id is distinct from f.id then
        if l.estado = 'pendiente' then
          update public.comision_admin_lineas
             set importe = f.importe, moneda = f.moneda, fee_id = f.id, actualizado_en = now(),
                 nota = coalesce(nota || ' - ', '') || 'Fee puesto al día el ' ||
                        to_char(v_hoy, 'DD/MM/YYYY') || ' (antes ' || l.importe || ' ' || l.moneda || ').',
                 snapshot = coalesce(snapshot, '{}'::jsonb) || jsonb_build_object(
                   'fee_id', f.id, 'importe', f.importe, 'moneda', f.moneda,
                   'efectivo_desde', f.efectivo_desde, 'antes', l.importe, 'puesto_al_dia_en', now())
           where id = l.id;
          n_puestas := n_puestas + 1;
        elsif not l.revisar and l.estado in ('facturada', 'cobrada') then
          update public.comision_admin_lineas
             set revisar = true, actualizado_en = now(),
                 nota = coalesce(nota || ' - ', '') || 'El fee cambió después de ' || l.estado ||
                        ' (ahora ' || f.importe || ' ' || f.moneda || '): revisar.'
           where id = l.id;
          n_revisar := n_revisar + 1;
        end if;
      end if;
    end loop;
  end loop;

  return jsonb_build_object('ok', true, 'nuevas', n_nuevas, 'puestas_al_dia', n_puestas, 'a_revisar', n_revisar);
end;
$$;

create or replace function public.comision_admin_anula_linea(p_linea_id uuid, p_motivo text default null::text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_linea     record;
  v_neto_imp  numeric;
  v_neto_base numeric;
  v_abono_id  uuid;
begin
  if not public.es_super_admin() then
    raise exception 'comision_admin_anula_linea: solo super_admin';
  end if;

  select * into v_linea from public.comision_admin_lineas where id = p_linea_id;
  if v_linea.id is null then
    raise exception 'esa linea no existe';
  end if;
  if v_linea.anulada then
    return jsonb_build_object('ok', false, 'motivo', 'esa linea ya estaba anulada');
  end if;
  if v_linea.tipo_linea not in ('devengo', 'fee') then
    raise exception 'solo se anula el devengo o el fee: sus ajustes y abonos van detras';
  end if;

  select coalesce(sum(l.importe), 0), coalesce(sum(l.base_total), 0)
    into v_neto_imp, v_neto_base
    from public.comision_admin_lineas l
   where (l.id = v_linea.id or l.linea_origen_id = v_linea.id)
     and l.tipo_linea in ('devengo', 'ajuste', 'fee');

  if v_linea.estado not in ('pendiente', 'exenta') and (v_neto_imp <> 0 or v_neto_base <> 0) then
    insert into public.comision_admin_lineas (
      tipo_linea, linea_origen_id, recibi_id, recibi_numero, sociedad,
      contrato_id, proyecto_id, devengado_el, fecha_recibi,
      base_total, moneda, pct_aplicado, importe, tarifa_id, fee_id, estado, revisar, nota, snapshot
    ) values (
      'abono', v_linea.id, v_linea.recibi_id, v_linea.recibi_numero, v_linea.sociedad,
      v_linea.contrato_id, v_linea.proyecto_id,
      case when v_linea.tipo_linea = 'fee' then (now() at time zone 'Asia/Makassar')::date else current_date end,
      v_linea.fecha_recibi,
      - v_neto_base, v_linea.moneda, v_linea.pct_aplicado, - v_neto_imp, v_linea.tarifa_id, v_linea.fee_id,
      'pendiente', true,
      'Abono: la ' || case when v_linea.tipo_linea = 'fee' then 'linea de fee' else 'comision' end ||
        ' se anulo a mano cuando ya estaba ' || v_linea.estado || '.' ||
        case when p_motivo is not null then ' Motivo: ' || p_motivo else '' end,
      jsonb_build_object('motivo', 'anulada_a_mano', 'devengo_id', v_linea.id,
                         'estado_al_anular', v_linea.estado, 'quien', (select auth.email()),
                         'neto_revertido', v_neto_imp, 'en', now())
    ) returning id into v_abono_id;
  end if;

  update public.comision_admin_lineas
     set anulada = true, actualizado_en = now(),
         nota = coalesce(nota || ' - ', '') || 'Anulada a mano por ' ||
                coalesce((select auth.email()), 'super_admin') || ' el ' || current_date ||
                case when p_motivo is not null then ': ' || p_motivo else '.' end
   where (id = v_linea.id or linea_origen_id = v_linea.id)
     and tipo_linea <> 'abono';

  return jsonb_build_object('ok', true, 'abono', v_abono_id, 'importe_revertido', v_neto_imp);
end;
$function$;
