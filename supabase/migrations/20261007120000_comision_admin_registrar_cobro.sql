-- Comisión de administración: «Registrar cobro» por importe (7-oct-2026, owner).
-- «PT Tepi Sungai me liquida 1.940 €: ¿línea a línea o por importe?» → por importe.
--
-- Una sociedad paga un importe; el panel salda las líneas más antiguas hasta
-- cubrirlo. Las líneas son ATÓMICAS: si ningún tramo de líneas seguidas suma
-- exactamente el importe, NO marca nada y devuelve los totales vecinos.
-- Dos pasos con la misma función: p_confirmar=false enseña, true aplica — y al
-- aplicar exige los MISMOS ids que se enseñaron (si el libro cambió entre medias,
-- se rechaza y hay que volver a mirar).
--
-- Revisión previa 7-oct (Datos + Administración):
--   · el cobro tiene cabecera propia (comision_admin_cobros) con la FECHA REAL de
--     cobro que se teclea, la referencia bancaria y el lote; cada línea saldada
--     guarda su cobro_id. now() del log no sirve: un cobro registrado tarde saldría
--     con otra fecha, y esa fecha es la que cuenta para fiscalidad y conversión.
--   · el abono de un devengo anulado que estaba pendiente, exento o facturado no
--     entra (su devengo tampoco: cuentan los dos o ninguno).
--   · se avisa de cuántas líneas se cobran SIN haberse facturado y de las que
--     están marcadas «revisar».
create table if not exists public.comision_admin_cobros (
  id uuid primary key default gen_random_uuid(),
  sociedad text not null,
  moneda text not null,
  importe numeric not null check (importe > 0),
  fecha_cobro date not null,
  referencia text,
  nota text,
  lote text not null,
  n_lineas integer not null,
  por text default auth.email(),
  en timestamptz not null default now()
);
alter table public.comision_admin_cobros enable row level security;
create policy comision_admin_cobros_super on public.comision_admin_cobros
  for select to authenticated using (public.es_super_admin());
revoke all on public.comision_admin_cobros from anon, authenticated;
grant select on public.comision_admin_cobros to authenticated;

alter table public.comision_admin_lineas
  add column if not exists cobro_id uuid references public.comision_admin_cobros(id);

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
  v_acum     numeric := 0;
  v_cerca    numeric;        -- el mayor acumulado que no pasa del objetivo
  v_pasa     numeric;        -- el menor acumulado que se pasa
  v_total    numeric := 0;
  v_lineas   jsonb := '[]'::jsonb;
  v_ok       boolean := false;
  v_motivo   text;
  v_ids      uuid[] := '{}';
  v_id       uuid;
  v_lote     text := substr(gen_random_uuid()::text, 1, 8);
  v_sinfact  integer := 0;
  v_sinfact_imp numeric := 0;
  v_revisar  integer := 0;
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

  /* Solo al confirmar se bloquean las filas (la vista previa no frena a nadie); al
     confirmar el barrido se recalcula entero, así que un cambio entre medias no se cuela. */
  if coalesce(p_confirmar, false) then
    perform 1 from public.comision_admin_lineas l
     where l.sociedad = p_sociedad and upper(l.moneda) = upper(p_moneda)
       and not l.anulada and l.estado in ('pendiente', 'facturada')
     order by l.id for update;
  end if;

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
    v_total := v_total + round(r.importe, v_dec);
    if not v_ok then
      v_acum := round(v_acum + r.importe, v_dec);
      v_lineas := v_lineas || jsonb_build_object(
        'id', r.id, 'tipo', r.tipo_linea, 'recibi', r.recibi_numero, 'fecha', r.devengado_el,
        'importe', r.importe, 'estado', r.estado, 'fee', r.fee_id is not null, 'revisar', r.revisar);
      v_ids := v_ids || r.id;
      if r.estado = 'pendiente' then v_sinfact := v_sinfact + 1; v_sinfact_imp := v_sinfact_imp + r.importe; end if;
      if r.revisar then v_revisar := v_revisar + 1; end if;
      if v_acum = v_obj then
        v_ok := true;
      elsif v_acum < v_obj then
        v_cerca := greatest(coalesce(v_cerca, v_acum), v_acum);
      else
        v_pasa := least(coalesce(v_pasa, v_acum), v_acum);
      end if;
    end if;
  end loop;

  if not v_ok then
    v_motivo := case
      when v_total < v_obj then
        'Esa sociedad solo tiene ' || round(v_total, v_dec) || ' ' || upper(p_moneda) ||
        ' pendientes: menos que el importe cobrado (' || v_obj || ').'
      else
        'Ningún tramo de líneas seguidas, de la más antigua en adelante, suma exactamente ' || v_obj || ' ' || upper(p_moneda) ||
        '. Lo más cerca por debajo es ' || coalesce(v_cerca::text, '—') || ' y por encima ' || coalesce(v_pasa::text, '—') ||
        '. Si el cobro incluye algo más (el fee fijo, una línea suelta), ajusta el importe o márcalas desde «Estado».'
      end;
    return jsonb_build_object('ok', false, 'motivo', v_motivo,
      'pendiente_total', round(v_total, v_dec), 'se_queda_corto', v_cerca, 'se_pasa', v_pasa);
  end if;

  if coalesce(p_confirmar, false) then
    if p_ids is null or (select array_agg(x order by x) from unnest(p_ids) x)
                        is distinct from (select array_agg(x order by x) from unnest(v_ids) x) then
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
             'Cobro por importe [lote ' || v_lote || '] del ' || p_fecha || ': ' || v_obj || ' ' || upper(p_moneda) ||
             coalesce('. Ref. ' || nullif(btrim(coalesce(p_referencia, '')), ''), '') ||
             coalesce('. ' || nullif(btrim(coalesce(p_nota, '')), ''), '')
        from public.comision_admin_lineas l where l.id = v_id;
      update public.comision_admin_lineas
         set estado = 'cobrada', cobro_id = v_cobro, actualizado_en = now()
       where id = v_id;
    end loop;
  end if;

  return jsonb_build_object('ok', true, 'aplicado', coalesce(p_confirmar, false), 'cobro_id', v_cobro,
    'lote', v_lote, 'importe', v_obj, 'moneda', upper(p_moneda), 'fecha', p_fecha,
    'n', jsonb_array_length(v_lineas), 'sin_facturar', v_sinfact, 'sin_facturar_importe', v_sinfact_imp,
    'revisar', v_revisar, 'ids', to_jsonb(v_ids), 'lineas', v_lineas);
end $$;
revoke all on function public.comision_admin_registrar_cobro(text, text, numeric, date, text, boolean, boolean, text, uuid[]) from public, anon;
grant execute on function public.comision_admin_registrar_cobro(text, text, numeric, date, text, boolean, boolean, text, uuid[]) to authenticated;
