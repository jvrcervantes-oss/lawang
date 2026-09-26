-- Fee fijo: varios a la vez — 26-sep-2026, owner: «quiero meter el mío y el de
-- mi mujer, tengo varios conceptos de fee fijo vigentes».
--
-- El modelo de la mañana admitía UN fee vigente por sociedad: el segundo alta
-- («SALARIO ANDREA», 1.200) pisó al primero («SALARIO JAVI», 1.000) y septiembre
-- quedó con una sola línea de 1.200. Ahora cada fee es una SERIE:
--   · `serie_id`: lo que dura en el tiempo. Cambiar el importe de un fee = fila
--     nueva con el MISMO serie_id; un fee distinto = serie nueva.
--   · `concepto` (obligatorio) y `beneficiario` (opcional): qué es y para quién.
--     Son de la serie, no de cada fila: el disparador los copia de la serie al
--     dar de alta un cambio, así que no pueden divergir aunque la pantalla mande
--     otra cosa (patrón «el dato tiene un dueño»). La sociedad, igual.
--   · La línea mensual del libro es una por SERIE y mes (antes: por sociedad y mes).
--
-- Migración de lo que ya había: cada fila existente pasa a ser su propia serie
-- con concepto = su nota («SALARIO JAVI», «SALARIO ANDREA»). La línea de
-- septiembre ya creada era del segundo alta (fee_id), así que se queda en esa
-- serie; la del primero la crea el panel al abrirse.
--
-- destructivo-ok: `drop index` del único viejo (sociedad, mes), sustituido por
-- (serie, mes); `drop trigger if exists` antes de crearlo. No se borra ningún dato.

alter table public.comision_admin_fees
  add column if not exists serie_id uuid,
  add column if not exists concepto text,
  add column if not exists beneficiario text;

update public.comision_admin_fees set serie_id = id where serie_id is null;
update public.comision_admin_fees
   set concepto = coalesce(nullif(trim(nota), ''), 'Fee fijo')
 where concepto is null;

alter table public.comision_admin_fees
  alter column serie_id set default gen_random_uuid(),
  alter column serie_id set not null,
  alter column concepto set not null;

alter table public.comision_admin_fees drop constraint if exists comision_admin_fees_concepto_check;
alter table public.comision_admin_fees
  add constraint comision_admin_fees_concepto_check check (length(trim(concepto)) > 0);

create index if not exists comision_admin_fees_serie_idx
  on public.comision_admin_fees (serie_id, efectivo_desde desc, created_at desc);

-- Una serie conserva su sociedad, concepto y beneficiario
create or replace function public._trg_comision_admin_fee_serie()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v record;
begin
  select x.sociedad, x.concepto, x.beneficiario into v
    from public.comision_admin_fees x
   where x.serie_id = new.serie_id
   order by x.created_at
   limit 1;
  if found then
    new.sociedad := v.sociedad;
    new.concepto := v.concepto;
    new.beneficiario := v.beneficiario;
  end if;
  new.concepto := trim(new.concepto);
  new.beneficiario := nullif(trim(coalesce(new.beneficiario, '')), '');
  return new;
end;
$$;
revoke all on function public._trg_comision_admin_fee_serie() from public, anon, authenticated;

drop trigger if exists trg_comision_admin_fee_serie on public.comision_admin_fees;
create trigger trg_comision_admin_fee_serie
  before insert on public.comision_admin_fees
  for each row execute function public._trg_comision_admin_fee_serie();

comment on table public.comision_admin_fees is
  'Fee fijo mensual de administración (solo super_admin). Append-only y por SERIE: cambiar un fee = fila nueva con el mismo serie_id (sociedad, concepto y beneficiario los hereda de la serie); quitarlo = importe 0. El fee de un mes es el vigente el último día de ese mes (created_at desc, id desc desempata). La deuda de cada mes vive en comision_admin_lineas (tipo_linea=fee, una por serie y mes). 26-sep-2026, owner.';

-- ── El libro: una línea por serie y mes ─────────────────────────────────────
alter table public.comision_admin_lineas add column if not exists fee_serie uuid;

update public.comision_admin_lineas l
   set fee_serie = f.serie_id
  from public.comision_admin_fees f
 where l.fee_id = f.id and l.fee_serie is null;

drop index if exists public.comision_admin_lineas_fee_mes_uq;
create unique index if not exists comision_admin_lineas_fee_serie_mes_uq
  on public.comision_admin_lineas (fee_serie, devengado_el)
  where tipo_linea = 'fee';

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
      select distinct on (x.serie_id) x.*
        from public.comision_admin_fees x
       where x.efectivo_desde <= v_fin
       order by x.serie_id, x.efectivo_desde desc, x.created_at desc, x.id desc
    loop
      select * into l from public.comision_admin_lineas
       where tipo_linea = 'fee' and fee_serie = f.serie_id and devengado_el = v_mes;

      if l.id is null then
        if f.importe > 0 then
          insert into public.comision_admin_lineas (
            tipo_linea, recibi_numero, sociedad, devengado_el, base_total, moneda,
            pct_aplicado, importe, fee_id, fee_serie, estado, nota, snapshot
          ) values (
            'fee', 'FEE ' || to_char(v_mes, 'YYYY-MM'), f.sociedad, v_mes, 0, f.moneda,
            0, f.importe, f.id, f.serie_id, 'pendiente',
            'Fee fijo de ' || to_char(v_mes, 'MM/YYYY') || ': ' || f.concepto ||
              coalesce(' (' || f.beneficiario || ')', '') || '.',
            jsonb_build_object('fee_id', f.id, 'serie_id', f.serie_id, 'concepto', f.concepto,
                               'beneficiario', f.beneficiario, 'importe', f.importe, 'moneda', f.moneda,
                               'efectivo_desde', f.efectivo_desde, 'devengado_en', now())
          )
          on conflict (fee_serie, devengado_el) where tipo_linea = 'fee' do nothing;
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

-- La línea de septiembre que ya existía: su nota decía «antes 1000», que era el
-- fee de la OTRA persona. Se aclara (solo la nota; el importe es correcto).
update public.comision_admin_lineas
   set nota = nota || ' - 26/09/2026: los fees pasan a ser series; esta línea es de «' ||
              (select f.concepto from public.comision_admin_fees f where f.id = comision_admin_lineas.fee_id) ||
              '» y el «antes» de arriba era otro fee.',
       actualizado_en = now()
 where tipo_linea = 'fee' and fee_id is not null and nota like '%Fee puesto al día%';
