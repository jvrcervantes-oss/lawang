-- Comision de administracion: solo super admin, retroactiva a todo, y con la
-- tarifa editable y las lineas anulables desde el panel
-- ============================================================================
-- Cuatro cambios pedidos por el owner:
--
-- [1] SOLO SUPER ADMIN. Antes el libro lo leia cualquier `es_admin()` (6 cuentas:
--     4 admin + 2 super_admin) y solo la tarifa exigia super. Ahora las dos
--     tablas, la reconciliacion y todas las acciones exigen `es_super_admin()`.
--     El menu tambien lo esconde, pero eso es la puerta: la de verdad es esta.
--
-- [2] RETROACTIVA A TODO. La tarifa pasa a regir desde antes del primer recibi
--     (2025-10-10), y se siembran las lineas de los 87 recibis vivos que ya
--     habia: base 1.976.160,41 EUR -> 9.880,80 EUR de comision que aparecen en
--     el libro de golpe.
--     `devengado_el` de esas lineas sembradas es la FECHA DEL RECIBI, no la de
--     hoy ni la de su alta en la base: 60 de ellos se cargaron en bloque el
--     28-jul-2026 como historico, asi que fecharlos por el alta amontonaria un
--     ano de dinero en un solo mes y la liquidacion mensual saldria absurda.
--     Para los recibis NUEVOS sigue mandando el dia del alta, que es lo que
--     impide retrasar la fecha de emision para escaparse del cobro.
--     Los 10 recibis anulados NO generan linea: ese dinero no entro.
--
-- [3] TARIFA EDITABLE. Contradice el diseno de ayer --una tarifa no se editaba,
--     se anadia otra con su fecha-- y se hace igual porque lo pide el owner,
--     pero sin perder nada: cada edicion guarda la fila anterior entera en
--     `comision_admin_tarifas_log`. Se puede seguir contestando "que % regia el
--     dia X" reconstruyendo desde el log, que es lo que el append-only protegia.
--     Editar NO recalcula lo ya devengado por defecto (cada linea lleva su pct
--     congelado); `comision_admin_edita_tarifa(..., p_recalcular => true)` lo
--     hace a peticion, y solo sobre lineas todavia `pendiente`.
--
-- [4] ANULAR UNA COMISION DESDE EL PANEL. `anulada` sigue FUERA del grant del
--     navegador a proposito: se anula por RPC, que ademas emite el abono si la
--     linea ya estaba facturada o cobrada. Un UPDATE suelto se saltaria eso y
--     dejaria dinero ya emitido sin su contrapartida.
--
-- destructivo-ok: hay un `drop policy` (patron del repo para repintar policies)
-- y un UPDATE con WHERE sobre la unica fila de tarifa, para moverla a su fecha
-- retroactiva. El INSERT de siembra solo crea lineas donde no hay ninguna.

-- ── 1. Solo super admin ─────────────────────────────────────────────────────
drop policy if exists "comision_admin_tarifas: leer"   on public.comision_admin_tarifas;
drop policy if exists "comision_admin_tarifas: alta"   on public.comision_admin_tarifas;
drop policy if exists "comision_admin_tarifas: editar" on public.comision_admin_tarifas;
drop policy if exists "comision_admin_lineas: leer"    on public.comision_admin_lineas;
drop policy if exists "comision_admin_lineas: estado"  on public.comision_admin_lineas;

create policy "comision_admin_tarifas: leer" on public.comision_admin_tarifas
  for select to authenticated using (public.es_super_admin());
-- Sin `efectivo_desde >= current_date`: el owner quiere la tarifa vigente desde
-- el principio de la intranet, asi que una fecha hacia atras es ahora legitima.
-- Lo que sostiene el historial ya no es esa restriccion, es el log de ediciones.
create policy "comision_admin_tarifas: alta" on public.comision_admin_tarifas
  for insert to authenticated
  with check (public.es_super_admin() and creado_por = (select auth.email()));
create policy "comision_admin_tarifas: editar" on public.comision_admin_tarifas
  for update to authenticated
  using (public.es_super_admin()) with check (public.es_super_admin());

create policy "comision_admin_lineas: leer" on public.comision_admin_lineas
  for select to authenticated using (public.es_super_admin());
create policy "comision_admin_lineas: estado" on public.comision_admin_lineas
  for update to authenticated
  using (public.es_super_admin()) with check (public.es_super_admin());

-- ── 2. El historial que sustituye al append-only ────────────────────────────
create table if not exists public.comision_admin_tarifas_log (
  id              uuid primary key default gen_random_uuid(),
  tarifa_id       uuid not null,
  pct_antes       numeric(7,4),
  desde_antes     date,
  nota_antes      text,
  pct_despues     numeric(7,4),
  desde_despues   date,
  nota_despues    text,
  accion          text not null check (accion in ('editada','borrada')),
  quien           text,
  cuando          timestamptz not null default now()
);

comment on table public.comision_admin_tarifas_log is
  'Que tenia una tarifa antes de cada edicion. Existe porque la tabla de tarifas dejo de ser append-only: sin esto, editar el % haria imposible contestar que porcentaje regia el dia que entro cada euro, que es justo lo que el append-only protegia.';

alter table public.comision_admin_tarifas_log enable row level security;
revoke all on public.comision_admin_tarifas_log from anon, authenticated;
grant select on public.comision_admin_tarifas_log to authenticated;
drop policy if exists "comision_admin_tarifas_log: leer" on public.comision_admin_tarifas_log;
create policy "comision_admin_tarifas_log: leer" on public.comision_admin_tarifas_log
  for select to authenticated using (public.es_super_admin());

create or replace function public._trg_comision_admin_tarifa_log()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  insert into public.comision_admin_tarifas_log (
    tarifa_id, pct_antes, desde_antes, nota_antes,
    pct_despues, desde_despues, nota_despues, accion, quien
  ) values (
    old.id, old.pct, old.efectivo_desde, old.nota,
    case when tg_op = 'UPDATE' then new.pct end,
    case when tg_op = 'UPDATE' then new.efectivo_desde end,
    case when tg_op = 'UPDATE' then new.nota end,
    case when tg_op = 'UPDATE' then 'editada' else 'borrada' end,
    coalesce((select auth.email()), 'sistema')
  );
  return case when tg_op = 'UPDATE' then new else old end;
end;
$function$;

revoke all on function public._trg_comision_admin_tarifa_log() from public, anon, authenticated;

drop trigger if exists trg_comision_admin_tarifa_log on public.comision_admin_tarifas;
create trigger trg_comision_admin_tarifa_log
  before update or delete on public.comision_admin_tarifas
  for each row execute function public._trg_comision_admin_tarifa_log();

-- ── 3. Editar una tarifa, con recalculo opcional ────────────────────────────
create or replace function public.comision_admin_edita_tarifa(
  p_tarifa_id uuid, p_pct numeric, p_efectivo_desde date,
  p_nota text default null, p_recalcular boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_antes record;
  v_tocadas integer := 0;
begin
  if not public.es_super_admin() then
    raise exception 'comision_admin_edita_tarifa: solo super_admin';
  end if;
  if p_pct is null or p_pct < 0 or p_pct > 100 then
    raise exception 'el porcentaje va entre 0 y 100 (recibido: %)', p_pct;
  end if;
  if p_efectivo_desde is null then
    raise exception 'la tarifa necesita una fecha desde la que rige';
  end if;

  select * into v_antes from public.comision_admin_tarifas where id = p_tarifa_id;
  if v_antes.id is null then
    raise exception 'esa tarifa no existe';
  end if;

  -- el trigger de log guarda sola la fila anterior
  update public.comision_admin_tarifas
     set pct = p_pct, efectivo_desde = p_efectivo_desde,
         nota = coalesce(p_nota, nota)
   where id = p_tarifa_id;

  /* Lo ya devengado NO se toca salvo que se pida: cada linea lleva su pct
     congelado, y cambiar el pasado en silencio es justo lo que el libro evita.
     Cuando se pide, solo alcanza a lo que sigue `pendiente`: una comision ya
     facturada o cobrada no se reescribe, se ajusta o se abona. */
  if p_recalcular then
    update public.comision_admin_lineas l
       set pct_aplicado = p_pct,
           importe = round(l.base_total * p_pct / 100,
                           case when upper(l.moneda) = 'IDR' then 0 else 2 end),
           revisar = true,
           nota = coalesce(l.nota || ' - ', '') || 'Recalculada al editar la tarifa: ' ||
                  v_antes.pct || '% -> ' || p_pct || '%.',
           actualizado_en = now()
     where l.tarifa_id = p_tarifa_id
       and l.tipo_linea = 'devengo'
       and l.estado = 'pendiente'
       and not l.anulada;
    get diagnostics v_tocadas = row_count;
  end if;

  return jsonb_build_object('ok', true, 'pct_antes', v_antes.pct, 'pct_ahora', p_pct,
                            'lineas_recalculadas', v_tocadas);
end;
$function$;

revoke all on function public.comision_admin_edita_tarifa(uuid, numeric, date, text, boolean) from public, anon, authenticated;
grant execute on function public.comision_admin_edita_tarifa(uuid, numeric, date, text, boolean) to authenticated;

-- ── 4. Anular una comision desde el panel ───────────────────────────────────
-- Por RPC y no por UPDATE: `anulada` sigue fuera del grant del navegador porque
-- anular tiene una consecuencia que un UPDATE suelto no haria — si la comision
-- ya estaba facturada o cobrada, hay que emitir el abono. Sin eso quedaria
-- dinero emitido sin contrapartida en el libro.
create or replace function public.comision_admin_anula_linea(p_linea_id uuid, p_motivo text default null)
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
  if v_linea.tipo_linea <> 'devengo' then
    raise exception 'solo se anula el devengo: sus ajustes y abonos van detras de el';
  end if;

  select coalesce(sum(l.importe), 0), coalesce(sum(l.base_total), 0)
    into v_neto_imp, v_neto_base
    from public.comision_admin_lineas l
   where (l.id = v_linea.id or l.linea_origen_id = v_linea.id)
     and l.tipo_linea in ('devengo', 'ajuste');

  if v_linea.estado not in ('pendiente', 'exenta') and (v_neto_imp <> 0 or v_neto_base <> 0) then
    insert into public.comision_admin_lineas (
      tipo_linea, linea_origen_id, recibi_id, recibi_numero, sociedad,
      contrato_id, proyecto_id, devengado_el, fecha_recibi,
      base_total, moneda, pct_aplicado, importe, tarifa_id, estado, revisar, nota, snapshot
    ) values (
      'abono', v_linea.id, v_linea.recibi_id, v_linea.recibi_numero, v_linea.sociedad,
      v_linea.contrato_id, v_linea.proyecto_id, current_date, v_linea.fecha_recibi,
      - v_neto_base, v_linea.moneda, v_linea.pct_aplicado, - v_neto_imp, v_linea.tarifa_id,
      'pendiente', true,
      'Abono: la comision se anulo a mano cuando ya estaba ' || v_linea.estado || '.' ||
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

revoke all on function public.comision_admin_anula_linea(uuid, text) from public, anon, authenticated;
grant execute on function public.comision_admin_anula_linea(uuid, text) to authenticated;

-- ── 5. La reconciliacion tambien pasa a super admin ─────────────────────────
create or replace function public.comision_admin_descuadres()
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_desde date;
  v_sin_linea integer;
  v_mal_calculadas integer;
  v_sin_base integer;
  v_base_no_cuadra integer;
  v_anulado_vivo integer;
  v_vivo_anulado integer;
begin
  if not public.es_super_admin() then
    raise exception 'comision_admin_descuadres: solo super_admin';
  end if;

  select min(efectivo_desde) into v_desde from public.comision_admin_tarifas;
  if v_desde is null then
    return jsonb_build_object('sin_tarifa', true);
  end if;

  /* Con la tarifa rigiendo desde el principio, «recibi vivo sin linea» pasa a
     medirse por la FECHA DEL RECIBI y no por su alta: los historicos se cargaron
     en bloque y por `created_at` ninguno contaria. */
  select count(*) into v_sin_linea
    from public.facturas f
   where f.tipo = 'recibi'
     and not coalesce(f.anulada, false)
     and coalesce(f.fecha_emision, f.created_at::date) >= v_desde
     and not exists (select 1 from public.comision_admin_lineas l
                      where l.recibi_id = f.id and l.tipo_linea = 'devengo');

  select count(*) into v_mal_calculadas
    from public.comision_admin_lineas l
   where l.tipo_linea = 'devengo'
     and l.importe is distinct from
         round(l.base_total * l.pct_aplicado / 100,
               case when upper(l.moneda) = 'IDR' then 0 else 2 end);

  select count(*) into v_sin_base
    from public.comision_admin_lineas l
   where l.tipo_linea = 'devengo' and l.base_total = 0 and not l.anulada;

  select count(*) into v_base_no_cuadra
    from public.comision_admin_lineas l
    join public.facturas f on f.id = l.recibi_id
   where l.tipo_linea = 'devengo'
     and not l.anulada
     and abs(coalesce(f.total, 0)
             - coalesce((f.datos -> 'totales' ->> 'impuesto')::numeric, 0)
             - l.base_total) > 0.01;

  select count(*) into v_anulado_vivo
    from public.facturas f
    join public.comision_admin_lineas l on l.recibi_id = f.id and l.tipo_linea = 'devengo'
   where f.tipo = 'recibi' and coalesce(f.anulada, false) and not l.anulada;

  select count(*) into v_vivo_anulado
    from public.facturas f
    join public.comision_admin_lineas l on l.recibi_id = f.id and l.tipo_linea = 'devengo'
   where f.tipo = 'recibi' and not coalesce(f.anulada, false) and l.anulada;

  return jsonb_build_object(
    'desde', v_desde,
    'recibis_sin_linea', v_sin_linea,
    'lineas_mal_calculadas', v_mal_calculadas,
    'devengos_con_base_cero', v_sin_base,
    'devengos_con_base_distinta_del_recibi', v_base_no_cuadra,
    'anulados_con_devengo_vivo', v_anulado_vivo,
    'vivos_con_devengo_anulado', v_vivo_anulado,
    'para_revisar', (select count(*) from public.comision_admin_lineas where revisar)
  );
end;
$function$;

revoke all on function public.comision_admin_descuadres() from public, anon, authenticated;
grant execute on function public.comision_admin_descuadres() to authenticated;

create or replace function public.comision_admin_repone_devengo(p_linea_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_linea  record;
  v_recibi record;
begin
  if not public.es_super_admin() then
    raise exception 'comision_admin_repone_devengo: solo super_admin';
  end if;

  select * into v_linea from public.comision_admin_lineas l
   where l.id = p_linea_id and l.tipo_linea = 'devengo';
  if v_linea.id is null then
    raise exception 'no existe ese devengo';
  end if;
  if not v_linea.anulada then
    return jsonb_build_object('ok', false, 'motivo', 'el devengo no esta anulado');
  end if;

  select * into v_recibi from public.facturas f where f.id = v_linea.recibi_id;
  if v_recibi.id is null or coalesce(v_recibi.anulada, false) then
    raise exception 'el recibi no existe o sigue anulado -- reponer el devengo dejaria el libro cobrando sobre dinero que no entro';
  end if;

  update public.comision_admin_lineas
     set anulada = false, revisar = true, actualizado_en = now(),
         nota = coalesce(nota || ' - ', '') || 'Devengo repuesto a mano por ' ||
                coalesce((select auth.email()), 'super_admin') || ' el ' || current_date || '.'
   where id = p_linea_id;

  return jsonb_build_object('ok', true, 'linea', p_linea_id, 'recibi', v_linea.recibi_numero);
end;
$function$;

revoke all on function public.comision_admin_repone_devengo(uuid) from public, anon, authenticated;
grant execute on function public.comision_admin_repone_devengo(uuid) to authenticated;

-- ── 6. La tarifa rige desde el principio ────────────────────────────────────
update public.comision_admin_tarifas
   set efectivo_desde = date '2025-01-01',
       nota = 'Tarifa de arranque: 0,5% por el uso de la intranet, sobre todo el dinero que entra. Rige desde el principio de la intranet.'
 where efectivo_desde = date '2026-09-17';

-- ── 7. Siembra: los recibis que ya estaban ──────────────────────────────────
-- `devengado_el` = fecha del recibi (ver cabecera: fecharlos por su alta
-- amontonaria un ano entero en el 28-jul-2026). Solo los VIVOS: un recibi
-- anulado es dinero que no entro. `on conflict` no hace falta -- el `not exists`
-- deja la siembra repetible sin duplicar.
insert into public.comision_admin_lineas (
  tipo_linea, recibi_id, recibi_numero, sociedad, contrato_id, proyecto_id,
  devengado_el, fecha_recibi, base_total, moneda, pct_aplicado, importe,
  tarifa_id, anulada, nota, snapshot
)
select
  'devengo', f.id, coalesce(f.numero, '(sin numero)'), f.sociedad, f.contrato_id, f.proyecto_id,
  coalesce(f.fecha_emision, f.created_at::date), f.fecha_emision,
  coalesce((f.datos -> 'totales' ->> 'subtotal')::numeric, f.total, 0),
  coalesce(f.moneda, 'EUR'), t.pct,
  round(coalesce((f.datos -> 'totales' ->> 'subtotal')::numeric, f.total, 0) * t.pct / 100,
        case when upper(coalesce(f.moneda, '')) = 'IDR' then 0 else 2 end),
  t.id, false,
  'Sembrada al pasar la tarifa a regir desde el principio de la intranet.',
  jsonb_build_object('numero', f.numero, 'sociedad', f.sociedad, 'total', f.total,
                     'subtotal', coalesce((f.datos -> 'totales' ->> 'subtotal')::numeric, f.total, 0),
                     'impuesto', (f.datos -> 'totales' ->> 'impuesto'),
                     'moneda', f.moneda, 'fecha_emision', f.fecha_emision,
                     'tarifa_pct', t.pct, 'siembra', true, 'calculado_en', now())
from public.facturas f
cross join lateral (
  select tt.id, tt.pct from public.comision_admin_tarifas tt
   where tt.efectivo_desde <= coalesce(f.fecha_emision, f.created_at::date)
   order by tt.efectivo_desde desc limit 1
) t
where f.tipo = 'recibi'
  and not coalesce(f.anulada, false)
  and not exists (select 1 from public.comision_admin_lineas l
                   where l.recibi_id = f.id and l.tipo_linea = 'devengo');
