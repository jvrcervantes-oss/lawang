-- Comisión de administración: el cobro es una BOLSA (7-oct-2026, owner).
-- «Es un pago general de 1.940 €: que la interfaz me calcule lo que se me devenga y yo voy quitando del
--  total. No línea a línea, porque hay líneas ridículas de 5 €.»
--
-- Antes (20261007120000) el cobro tenía que sumar EXACTO un tramo de líneas; con 1.940 € no cuadraba nunca.
-- Ahora: bolsa = saldo que ya quedaba de cobros anteriores + el importe que entra. Se saldan líneas enteras,
-- de la más antigua en adelante, mientras quepan en la bolsa; en la primera que no cabe se PARA (no se
-- salta a las pequeñas de después: el orden es el del libro). Lo que sobra no se pierde: queda como saldo a
-- favor de esa sociedad y moneda, y entra en la bolsa del siguiente cobro.
--
-- El saldo no es un campo que alguien pueda tocar: se CALCULA = suma de lo cobrado en los cobros
--   menos el importe de las líneas que esos cobros han saldado (cobro_id). Si una línea sale de «cobrada»
--   (comision_admin_linea_estado le quita el cobro_id), el saldo vuelve a subir solo.
-- Sigue el paso de vista previa / confirmación con los mismos ids, la fecha real del cobro y el log por línea.
create or replace function public.comision_admin_registrar_cobro(
  p_sociedad text, p_moneda text, p_importe numeric, p_fecha date default null,
  p_referencia text default null, p_incluir_fee boolean default false,
  p_confirmar boolean default false, p_nota text default null, p_ids uuid[] default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  r          record;
  v_dec      integer;
  v_obj      numeric;
  v_previo   numeric;        -- saldo que ya quedaba de cobros anteriores
  v_bolsa    numeric;
  v_acum     numeric := 0;
  v_lineas   jsonb := '[]'::jsonb;
  v_parado   boolean := false;
  v_sig      jsonb;          -- la primera línea que ya no cabe
  v_ids      uuid[] := '{}';
  v_id       uuid;
  v_lote     text := substr(gen_random_uuid()::text, 1, 8);
  v_sinfact  integer := 0;
  v_sinfact_imp numeric := 0;
  v_revisar  integer := 0;
  v_pend_tot numeric := 0;
  v_hoy      date := (now() at time zone 'Asia/Makassar')::date;
  v_cobro    uuid;
begin
  if not public.es_super_admin() then raise exception 'Solo un super admin' using errcode = '42501'; end if;
  if coalesce(btrim(p_sociedad), '') = '' or coalesce(btrim(p_moneda), '') = '' then
    raise exception 'Falta la sociedad o la moneda' using errcode = '22023';
  end if;
  if p_importe is null or p_importe <= 0 then
    raise exception 'El importe cobrado tiene que ser mayor que 0' using errcode = '22023';
  end if;
  if p_fecha is null then
    raise exception 'Falta la fecha en que entró el cobro' using errcode = '22023';
  end if;
  if p_fecha > v_hoy then
    raise exception 'La fecha de cobro no puede ser futura (hoy es %)', v_hoy using errcode = '22023';
  end if;
  v_dec := case when upper(p_moneda) = 'IDR' then 0 else 2 end;
  v_obj := round(p_importe, v_dec);

  /* Al confirmar se bloquean las filas (la vista previa no frena a nadie); el barrido se recalcula entero. */
  if coalesce(p_confirmar, false) then
    perform 1 from public.comision_admin_lineas l
     where l.sociedad = p_sociedad and upper(l.moneda) = upper(p_moneda)
       and not l.anulada and l.estado in ('pendiente', 'facturada')
     order by l.id for update;
    perform 1 from public.comision_admin_cobros c
     where c.sociedad = p_sociedad and upper(c.moneda) = upper(p_moneda) for update;
  end if;

  v_previo := coalesce((select sum(c.importe) from public.comision_admin_cobros c
                         where c.sociedad = p_sociedad and upper(c.moneda) = upper(p_moneda)), 0)
            - coalesce((select sum(l.importe) from public.comision_admin_lineas l
                         where l.cobro_id in (select c.id from public.comision_admin_cobros c
                                               where c.sociedad = p_sociedad and upper(c.moneda) = upper(p_moneda))), 0);
  v_previo := round(greatest(v_previo, 0), v_dec);
  v_bolsa  := v_obj + v_previo;

  for r in
    select l.id, l.tipo_linea, l.recibi_numero, l.devengado_el, l.importe, l.estado, l.fee_id, l.revisar
      from public.comision_admin_lineas l
     where l.sociedad = p_sociedad and upper(l.moneda) = upper(p_moneda)
       and not l.anulada and l.estado in ('pendiente', 'facturada')
       and (coalesce(p_incluir_fee, false) or l.fee_id is null)
       and not (l.tipo_linea = 'abono' and exists (
             select 1 from public.comision_admin_lineas o
              where o.id = l.linea_origen_id and o.anulada and o.estado in ('pendiente', 'exenta', 'facturada')))
     order by l.devengado_el, l.creado_en, l.id
  loop
    v_pend_tot := v_pend_tot + round(r.importe, v_dec);
    if not v_parado then
      if round(v_acum + r.importe, v_dec) <= v_bolsa then
        v_acum := round(v_acum + r.importe, v_dec);
        v_lineas := v_lineas || jsonb_build_object(
          'id', r.id, 'tipo', r.tipo_linea, 'recibi', r.recibi_numero, 'fecha', r.devengado_el,
          'importe', r.importe, 'estado', r.estado, 'fee', r.fee_id is not null, 'revisar', r.revisar);
        v_ids := v_ids || r.id;
        if r.estado = 'pendiente' then v_sinfact := v_sinfact + 1; v_sinfact_imp := v_sinfact_imp + r.importe; end if;
        if r.revisar then v_revisar := v_revisar + 1; end if;
      else
        v_parado := true;
        v_sig := jsonb_build_object('recibi', r.recibi_numero, 'fecha', r.devengado_el, 'importe', r.importe);
      end if;
    end if;
  end loop;

  if coalesce(p_confirmar, false) then
    if p_ids is null or coalesce((select array_agg(x order by x) from unnest(p_ids) x), '{}')
                        is distinct from coalesce((select array_agg(x order by x) from unnest(v_ids) x), '{}') then
      return jsonb_build_object('ok', false,
        'motivo', 'Las líneas han cambiado desde que las viste. No se ha marcado nada: vuelve a pulsar «Ver qué salda».');
    end if;
    insert into public.comision_admin_cobros (sociedad, moneda, importe, fecha_cobro, referencia, nota, lote, n_lineas)
    values (p_sociedad, upper(p_moneda), v_obj, p_fecha, nullif(btrim(coalesce(p_referencia, '')), ''),
            nullif(btrim(coalesce(p_nota, '')), ''), v_lote, cardinality(v_ids))
    returning id into v_cobro;
    foreach v_id in array v_ids loop
      insert into public.comision_admin_lineas_log (linea_id, estado_antes, estado_despues, motivo)
      select l.id, l.estado, 'cobrada',
             'Cobro por bolsa [lote ' || v_lote || '] del ' || p_fecha || ': ' || v_obj || ' ' || upper(p_moneda) ||
             coalesce('. Ref. ' || nullif(btrim(coalesce(p_referencia, '')), ''), '') ||
             coalesce('. ' || nullif(btrim(coalesce(p_nota, '')), ''), '')
        from public.comision_admin_lineas l where l.id = v_id;
      update public.comision_admin_lineas
         set estado = 'cobrada', cobro_id = v_cobro, actualizado_en = now()
       where id = v_id;
    end loop;
  end if;

  return jsonb_build_object('ok', true, 'aplicado', coalesce(p_confirmar, false), 'cobro_id', v_cobro,
    'lote', v_lote, 'importe', v_obj, 'saldo_previo', v_previo, 'bolsa', v_bolsa,
    'aplicado_importe', v_acum, 'resto', round(v_bolsa - v_acum, v_dec),
    'pendiente_total', round(v_pend_tot, v_dec), 'siguiente', v_sig,
    'moneda', upper(p_moneda), 'fecha', p_fecha,
    'n', jsonb_array_length(v_lineas), 'sin_facturar', v_sinfact, 'sin_facturar_importe', v_sinfact_imp,
    'revisar', v_revisar, 'ids', to_jsonb(v_ids), 'lineas', v_lineas);
end $$;
