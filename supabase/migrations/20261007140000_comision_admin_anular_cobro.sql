-- Comisión de administración: poder ANULAR un cobro y guardas del cobro por bolsa (7-oct-2026).
-- Revisor de código: con la bolsa, comision_admin_cobros.importe suma saldo a favor para siempre; un importe mal
-- tecleado (o un cobro de 0 líneas) inflaría para siempre la bolsa siguiente y solo se arreglaría con SQL a mano.
--   · comision_admin_anular_cobro(id, motivo): suelta las líneas del cobro (vuelven al estado que tenían, que
--     sale del log), deja el cobro marcado anulado (no se borra: queda quién, cuándo y por qué) y el saldo
--     lo deja de contar.
--   · registrar_cobro: el saldo ignora cobros anulados y redondea cada línea; y rechaza un cobro idéntico
--     (misma sociedad, moneda, importe, fecha y referencia) registrado hace menos de 10 minutos: un doble clic
--     con 0 líneas no tenía ninguna lista de ids que lo parase.
--   · Una línea cobrada que luego se anula CONSERVA su cobro_id a propósito: el dinero ya se aplicó a ella y
--     su abono (negativo, pendiente) queda en el libro; contarla como saldo libre dejaría el dinero aplicado dos veces.
alter table public.comision_admin_cobros
  add column if not exists anulado boolean not null default false,
  add column if not exists anulado_motivo text,
  add column if not exists anulado_en timestamptz,
  add column if not exists anulado_por text;

create or replace function public.comision_admin_anular_cobro(p_cobro_id uuid, p_motivo text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  c public.comision_admin_cobros%rowtype;
  r record;
  v_prev text;
  v_n integer := 0;
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  if not public.es_super_admin() then raise exception 'Solo un super admin' using errcode = '42501'; end if;
  if v_motivo is null or length(v_motivo) < 5 then
    raise exception 'Anular un cobro necesita un motivo (queda registrado)' using errcode = '22023';
  end if;
  select * into c from public.comision_admin_cobros where id = p_cobro_id for update;
  if not found then raise exception 'Ese cobro no existe' using errcode = 'P0002'; end if;
  if c.anulado then
    return jsonb_build_object('ok', false, 'motivo', 'Ese cobro ya estaba anulado.');
  end if;
  for r in select l.id, l.estado from public.comision_admin_lineas l where l.cobro_id = p_cobro_id for update loop
    select lg.estado_antes into v_prev from public.comision_admin_lineas_log lg
     where lg.linea_id = r.id and lg.estado_despues = 'cobrada' and lg.motivo like '%[lote ' || c.lote || ']%'
     order by lg.en desc limit 1;
    v_prev := coalesce(v_prev, 'pendiente');
    insert into public.comision_admin_lineas_log (linea_id, estado_antes, estado_despues, motivo)
    values (r.id, r.estado, v_prev, 'Cobro anulado [lote ' || c.lote || ']: ' || v_motivo);
    update public.comision_admin_lineas set estado = v_prev, cobro_id = null, actualizado_en = now() where id = r.id;
    v_n := v_n + 1;
  end loop;
  update public.comision_admin_cobros
     set anulado = true, anulado_motivo = v_motivo, anulado_en = now(), anulado_por = auth.email()
   where id = p_cobro_id;
  return jsonb_build_object('ok', true, 'lineas_sueltas', v_n, 'importe', c.importe, 'moneda', c.moneda);
end $$;
revoke all on function public.comision_admin_anular_cobro(uuid, text) from public, anon;
grant execute on function public.comision_admin_anular_cobro(uuid, text) to authenticated;

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
  v_previo   numeric;
  v_bolsa    numeric;
  v_acum     numeric := 0;
  v_lineas   jsonb := '[]'::jsonb;
  v_parado   boolean := false;
  v_sig      jsonb;
  v_ids      uuid[] := '{}';
  v_id       uuid;
  v_lote     text := substr(gen_random_uuid()::text, 1, 8);
  v_sinfact  integer := 0;
  v_sinfact_imp numeric := 0;
  v_revisar  integer := 0;
  v_pend_tot numeric := 0;
  v_hoy      date := (now() at time zone 'Asia/Makassar')::date;
  v_ref      text := nullif(btrim(coalesce(p_referencia, '')), '');
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

  if coalesce(p_confirmar, false) then
    perform 1 from public.comision_admin_lineas l
     where l.sociedad = p_sociedad and upper(l.moneda) = upper(p_moneda)
       and not l.anulada and l.estado in ('pendiente', 'facturada')
     order by l.id for update;
    perform 1 from public.comision_admin_cobros c
     where c.sociedad = p_sociedad and upper(c.moneda) = upper(p_moneda) for update;
    if exists (select 1 from public.comision_admin_cobros c
                where c.sociedad = p_sociedad and upper(c.moneda) = upper(p_moneda) and not c.anulado
                  and c.importe = v_obj and c.fecha_cobro = p_fecha
                  and c.referencia is not distinct from v_ref
                  and c.en > now() - interval '10 minutes') then
      return jsonb_build_object('ok', false,
        'motivo', 'Ya hay un cobro idéntico (misma sociedad, importe, fecha y referencia) registrado hace menos de 10 minutos: parece un doble clic. Míralo en «Cobros registrados».');
    end if;
  end if;

  v_previo := coalesce((select sum(c.importe) from public.comision_admin_cobros c
                         where c.sociedad = p_sociedad and upper(c.moneda) = upper(p_moneda) and not c.anulado), 0)
            - coalesce((select sum(round(l.importe, v_dec)) from public.comision_admin_lineas l
                         where l.cobro_id in (select c.id from public.comision_admin_cobros c
                                               where c.sociedad = p_sociedad and upper(c.moneda) = upper(p_moneda)
                                                 and not c.anulado)), 0);
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
    values (p_sociedad, upper(p_moneda), v_obj, p_fecha, v_ref,
            nullif(btrim(coalesce(p_nota, '')), ''), v_lote, cardinality(v_ids))
    returning id into v_cobro;
    foreach v_id in array v_ids loop
      insert into public.comision_admin_lineas_log (linea_id, estado_antes, estado_despues, motivo)
      select l.id, l.estado, 'cobrada',
             'Cobro por bolsa [lote ' || v_lote || '] del ' || p_fecha || ': ' || v_obj || ' ' || upper(p_moneda) ||
             coalesce('. Ref. ' || v_ref, '') ||
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
