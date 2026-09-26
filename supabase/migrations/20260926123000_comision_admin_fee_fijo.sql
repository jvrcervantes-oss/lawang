-- Fee fijo mensual de administración — 26-sep-2026, owner: «también cobro un fee
-- fijo además de la comisión, ¿lo añado aquí para saber cuánto deben pagarme
-- este mes?». Revisión previa #108 (Administración + Datos) antes de escribirlo.
--
-- DOS PIEZAS, y por qué dos:
--   · `comision_admin_fees` es la CONDICIÓN: cuánto, en qué moneda, a qué
--     sociedad y desde cuándo. Append-only: cambiar el fee = fila nueva con su
--     fecha; dejar de cobrarlo = fila con importe 0. Así siempre se puede decir
--     qué fee regía cada mes sin tabla de log.
--   · La DEUDA de cada mes es una línea `tipo_linea='fee'` en el libro de
--     siempre (`comision_admin_lineas`), con su estado pendiente / facturada /
--     cobrada / exenta. Sin estado, el fee reaparecería cada mes como «a cobrar»
--     aunque ya se hubiera cobrado, y los meses sin cobrar no se acumularían
--     (Administración). Al ir en el libro entra solo en «Pendiente de facturar»,
--     en la tabla por sociedad y en los filtros, sin pantalla nueva.
--
-- DECISIONES QUE NO SON OBVIAS:
--   · `sociedad` NOT NULL: cada PT es un deudor distinto y ninguna factura sale a
--     nombre de «las dos». Si se cobra a dos, son dos filas.
--   · El fee de un mes es el que rige el ÚLTIMO día de ese mes, entero y sin
--     prorratear. Un fee dado de alta el 26 con «rige desde el 26» cuenta ya
--     para ese mes, que es lo que pidió el owner («este mes»).
--   · «Hoy» es la fecha de BALI (Asia/Makassar), no la UTC del servidor: entre
--     las 00:00 y las 08:00 de Bali la UTC sigue en el día anterior, y el día 1
--     el fee del mes nuevo no aparecería (Datos).
--   · Desempate si dos filas rigen desde el mismo día: gana la más reciente
--     (`created_at desc, id desc`). El panel usa el mismo orden.
--   · La línea de un mes se crea UNA vez por (sociedad, mes), anulada incluida:
--     anular la línea de un mes = «ese mes no se cobra», y no puede renacer sola.
--   · Si el fee cambia y la línea del mes sigue `pendiente`, se pone al día
--     (todavía no se ha facturado: no hay nada emitido que contradecir). Si ya
--     está facturada o cobrada NO se toca: se marca `revisar`.
--   · Importes BRUTOS: base imponible, sin PPN ni retención (PPh 23/26), que
--     dependen de LAW-231 (a quién se le cobra), todavía abierto.
--   · `base_total = 0` y `pct_aplicado = 0` en la línea de fee: no entró dinero,
--     así que «Dinero entrado» de la tabla por sociedad no se infla.
--     `comision_admin_descuadres()` filtra por `tipo_linea='devengo'`, así que
--     las líneas de fee no le generan falsos avisos.
--
-- destructivo-ok: `drop policy if exists` sobre la tabla nueva (patrón del repo
-- para repintar policies) y `drop constraint` del check de tipo_linea para
-- volver a crearlo AMPLIADO con 'fee'. No se borra ni cambia ningún dato.

-- ── 1. La condición ─────────────────────────────────────────────────────────
create table if not exists public.comision_admin_fees (
  id              uuid primary key default gen_random_uuid(),
  sociedad        text not null references public.sociedades(clave),
  importe         numeric(14,2) not null check (importe >= 0),
  moneda          text not null default 'EUR' check (moneda ~ '^[A-Z]{3}$'),
  efectivo_desde  date not null,
  nota            text,
  creado_por      text not null default auth.email(),
  created_at      timestamptz not null default now()
);

comment on table public.comision_admin_fees is
  'Fee fijo mensual de administración (solo super_admin). Append-only: cambiar = fila nueva con fecha; quitar = importe 0. El fee de un mes es el vigente el último día de ese mes (created_at desc, id desc desempata). La deuda de cada mes vive en comision_admin_lineas (tipo_linea=fee). 26-sep-2026, owner.';

create index if not exists comision_admin_fees_vigente_idx
  on public.comision_admin_fees (sociedad, efectivo_desde desc, created_at desc);

alter table public.comision_admin_fees enable row level security;
revoke all on public.comision_admin_fees from public, anon, authenticated;
grant select, insert on public.comision_admin_fees to authenticated;

drop policy if exists "comision_admin_fees: leer" on public.comision_admin_fees;
drop policy if exists "comision_admin_fees: alta" on public.comision_admin_fees;
create policy "comision_admin_fees: leer" on public.comision_admin_fees
  for select to authenticated using (public.es_super_admin());
create policy "comision_admin_fees: alta" on public.comision_admin_fees
  for insert to authenticated
  with check (public.es_super_admin() and creado_por = (select auth.email()));

-- ── 2. El libro admite la línea de fee ──────────────────────────────────────
alter table public.comision_admin_lineas
  add column if not exists fee_id uuid references public.comision_admin_fees(id);

alter table public.comision_admin_lineas drop constraint if exists comision_admin_lineas_tipo_linea_check;
alter table public.comision_admin_lineas add constraint comision_admin_lineas_tipo_linea_check
  check (tipo_linea = any (array['devengo', 'ajuste', 'abono', 'fee']));

-- Una línea de fee por sociedad y mes, ANULADAS INCLUIDAS (ver cabecera).
create unique index if not exists comision_admin_lineas_fee_mes_uq
  on public.comision_admin_lineas (sociedad, devengado_el)
  where tipo_linea = 'fee';

-- ── 3. Devengar los fees hasta el mes en curso ──────────────────────────────
-- Idempotente: la llama el panel al abrirse. Recorre desde el primer mes con
-- fee hasta el mes en curso de Bali; nunca crea meses futuros.
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
             set importe = f.importe, moneda = f.moneda, fee_id = f.id,
                 anulada = (f.importe = 0), actualizado_en = now(),
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

revoke all on function public.comision_admin_devenga_fees() from public, anon, authenticated;
grant execute on function public.comision_admin_devenga_fees() to authenticated;

comment on function public.comision_admin_devenga_fees() is
  'Crea (idempotente) la línea tipo fee de cada sociedad y mes hasta el mes en curso de Bali; pone al día las pendientes si el fee cambió y marca revisar las ya facturadas/cobradas. Solo super_admin. 26-sep-2026.';

-- ── 4. Anular también una línea de fee ──────────────────────────────────────
-- Mismo cuerpo que la versión del 17-sep con dos cambios: admite `fee` además de
-- `devengo`, y suma la propia línea de fee en el neto a revertir (si ya estaba
-- facturada, el abono sale igual que con un devengo).
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
      v_linea.contrato_id, v_linea.proyecto_id, current_date, v_linea.fecha_recibi,
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
