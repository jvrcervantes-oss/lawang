-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · bloque 4 · migracion 5 (8-oct-2026): LIBRO DE ADMINISTRACION (comision_admin_*) POR EMPRESA.
--   Es el libro de lo que Lawang paga por el uso de la intranet (0,5 % de lo que entra) y de sus costes fijos (fees). Cada linea, fee y cobro lleva `sociedad`; su empresa es
--   la de esa sociedad (empresas.sociedad_clave): tepi_sungai -> lawang, san_dal_woods -> sandal_woods. La tarifa lleva `empresa` (migracion 1).
--   * Lectura (policies): el super de una empresa ve solo lo de sus sociedades; el super global, todo, como siempre. Un admin_empresa (que no es super) no lo ve.
--   * Operar el libro (anular/reponer una linea, cambiar su estado, registrar y anular cobros, devengar fees, definir fees): es_super_admin() -> es_super_admin_de(empresa de la
--     sociedad de la linea/cobro/fee). Las 5 lineas de tepi_sungai que cuelgan de proyectos de sandal_woods siguen siendo de tepi_sungai, es decir de lawang: lo emitido no se reetiqueta.
--   * LA TARIFA (el porcentaje) y su historial se SIGUEN creando y editando solo por un super GLOBAL: es lo que el estudio cobra, no un dato de la empresa. Crear una tarifa
--     nueva crea una por empresa activa (una sola tarifa «para todas», como hoy); editar una cambia solo la de su fila, y recalcular solo toca lineas de esa empresa.
--   * El trigger que devenga el 0,5 % en cada recibi elige la tarifa DE LA EMPRESA de la sociedad del recibi (sociedad sin empresa conocida: la de lawang, como hasta ahora).
--   * comision_admin_descuadres y comision_admin_prevision cuentan solo lo de las empresas que el llamador gobierna (el super global, todo: resultado identico al de antes).
--   Lo ya devengado no se recalcula ni se reasigna: las lineas de sandal_woods anteriores siguen apuntando a la fila de tarifa original (tarifa_id), y no se tocan.
-- destructivo-ok: create or replace de 13 funciones por parche con marca (cada marca debe salir las veces esperadas o aborta) y 1 reescrita, alter policy x4; sin DDL que destruya datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b4.sql

create or replace function pg_temp.parchea(p_sig regprocedure, p_pares text[]) returns void language plpgsql as $f$
declare d text; i int := 1; v_old text; v_new text; v_n int; v_esp int;
begin
  d := pg_get_functiondef(p_sig);
  while i <= array_length(p_pares, 1) loop
    v_old := p_pares[i]; v_new := p_pares[i + 1]; v_esp := p_pares[i + 2]::int;
    v_n := (length(d) - length(replace(d, v_old, ''))) / length(v_old);
    if v_n <> v_esp then
      raise exception 'parchea %: la marca «%» sale % veces y se esperaban %', p_sig, left(v_old, 90), v_n, v_esp;
    end if;
    d := replace(d, v_old, v_new);
    i := i + 3;
  end loop;
  execute d;
end $f$;

-- ---------------------------------------------------------------- lectura
alter policy "comision_admin_fees: leer" on public.comision_admin_fees
  using (public.es_super_admin_de(public.empresa_de_sociedad(sociedad)));
alter policy "comision_admin_lineas: leer" on public.comision_admin_lineas
  using (public.es_super_admin_de(public.empresa_de_sociedad(sociedad)));
alter policy "comision_admin_tarifas: leer" on public.comision_admin_tarifas
  using (public.es_super_admin_de(empresa));
alter policy "comision_admin_cobros_super" on public.comision_admin_cobros
  using (public.es_super_admin_de(public.empresa_de_sociedad(sociedad)));

-- ---------------------------------------------------------------- operar el libro (por la sociedad del objeto)
select pg_temp.parchea('public.comision_admin_anula_linea(uuid,text)'::regprocedure, array[
  $o$if not public.es_super_admin() then$o$,
  $n$if not public.es_super_admin_de(public.empresa_de_sociedad((select l.sociedad from public.comision_admin_lineas l where l.id = p_linea_id))) then$n$, '1']);
select pg_temp.parchea('public.comision_admin_repone_devengo(uuid)'::regprocedure, array[
  $o$if not public.es_super_admin() then$o$,
  $n$if not public.es_super_admin_de(public.empresa_de_sociedad((select l.sociedad from public.comision_admin_lineas l where l.id = p_linea_id))) then$n$, '1']);
select pg_temp.parchea('public.comision_admin_linea_estado(uuid,text,text,boolean,boolean,text)'::regprocedure, array[
  $o$if not public.es_super_admin() then$o$,
  $n$if not public.es_super_admin_de(public.empresa_de_sociedad((select l.sociedad from public.comision_admin_lineas l where l.id = p_id))) then$n$, '1']);
select pg_temp.parchea('public.comision_admin_anular_cobro(uuid,text)'::regprocedure, array[
  $o$if not public.es_super_admin() then$o$,
  $n$if not public.es_super_admin_de(public.empresa_de_sociedad((select cx.sociedad from public.comision_admin_cobros cx where cx.id = p_cobro_id))) then$n$, '1']);
select pg_temp.parchea('public.comision_admin_registrar_cobro(text,text,numeric,date,text,boolean,boolean,text,uuid[])'::regprocedure, array[
  $o$if not public.es_super_admin() then$o$,
  $n$if not public.es_super_admin_de(public.empresa_de_sociedad(p_sociedad)) then$n$, '1']);
select pg_temp.parchea('public.comision_admin_fee_guarda(uuid,jsonb)'::regprocedure, array[
  $o$if not public.es_super_admin() then$o$,
  $n$if not public.es_super_admin_de(public.empresa_de_sociedad(coalesce(
         (select f.sociedad from public.comision_admin_fees f where f.serie_id = p_serie order by f.created_at limit 1),
         nullif(btrim(coalesce(p_datos->>'sociedad', '')), '')))) then$n$, '1']);
select pg_temp.parchea('public.comision_admin_devenga_fees()'::regprocedure, array[
  $o$if not public.es_super_admin() then$o$,
  $n$if not (select coalesce(bool_or(public.es_super_admin_de(e.clave)), false) from public.empresas e) then$n$, '1',
  $o$from public.comision_admin_fees where efectivo_desde <= v_hoy;$o$,
  $n$from public.comision_admin_fees where efectivo_desde <= v_hoy and public.es_super_admin_de(public.empresa_de_sociedad(sociedad));$n$, '1',
  $o$where x.efectivo_desde <= v_fin$o$,
  $n$where x.efectivo_desde <= v_fin and public.es_super_admin_de(public.empresa_de_sociedad(x.sociedad))$n$, '1']);

-- ---------------------------------------------------------------- informes: solo lo de las empresas que se gobiernan
select pg_temp.parchea('public.comision_admin_descuadres()'::regprocedure, array[
  $o$if not public.es_super_admin() then$o$,
  $n$if not (select coalesce(bool_or(public.es_super_admin_de(e.clave)), false) from public.empresas e) then$n$, '1',
  $o$where f.tipo = 'recibi'$o$,
  $n$where f.tipo = 'recibi' and public.es_super_admin_de(public.empresa_de_sociedad(f.sociedad))$n$, '3',
  $o$where l.tipo_linea = 'devengo'$o$,
  $n$where l.tipo_linea = 'devengo' and public.es_super_admin_de(public.empresa_de_sociedad(l.sociedad))$n$, '3',
  $o$(select count(*) from public.comision_admin_lineas where revisar)$o$,
  $n$(select count(*) from public.comision_admin_lineas lr where lr.revisar and public.es_super_admin_de(public.empresa_de_sociedad(lr.sociedad)))$n$, '1']);

create or replace function public.comision_admin_prevision()
 returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_pct numeric;
  v_out jsonb;
begin
  if not (select coalesce(bool_or(public.es_super_admin_de(e.clave)), false) from public.empresas e) then
    raise exception 'comision_admin_prevision: solo super_admin';
  end if;

  -- el % que se muestra: el de la primera empresa que el llamador gobierna (lawang para un global, como siempre)
  select t.pct into v_pct
    from public.comision_admin_tarifas t join public.empresas e on e.clave = t.empresa
   where t.efectivo_desde <= current_date and public.es_super_admin_de(t.empresa)
   order by e.orden, t.efectivo_desde desc
   limit 1;

  with vivos as (
    select coalesce(c.moneda, 'EUR') as moneda,
           c.bloqueado as firmado,
           coalesce(public._empresa_de_contrato_int(c.id), 'lawang') as emp,
           greatest(coalesce(c.precio_total, 0)
                    - public.contrato_cobrado(c.id)
                    - coalesce(public.lw_importe(c.datos->'fields'->>'carta_cobrado_importe'), 0), 0) as pendiente
      from public.contratos c
     where c.liberado_en is null
       and c.tipo not like 'carta_reserva%'
       and coalesce(c.precio_total, 0) > 0
       and (c.bloqueado or public.contrato_firma_viva(c.id))
       and public.es_super_admin_de(public._empresa_de_contrato_int(c.id))
  ), con_pct as (
    -- cada venta con la tarifa vigente de SU empresa (la del libro de esa empresa)
    select v.*, (select t.pct from public.comision_admin_tarifas t
                  where t.empresa = v.emp and t.efectivo_desde <= current_date
                  order by t.efectivo_desde desc limit 1) as pct
      from vivos v
  ), por_moneda as (
    select moneda,
           count(*) filter (where firmado)                          as n_firmados,
           coalesce(sum(pendiente) filter (where firmado), 0)       as pend_firmados,
           count(*) filter (where not firmado)                      as n_en_firma,
           coalesce(sum(pendiente) filter (where not firmado), 0)   as pend_en_firma,
           bool_or(pct is null)                                     as falta_tarifa,
           coalesce(sum(pendiente * pct / 100), 0)                  as com_total,
           coalesce(sum(pendiente * pct / 100) filter (where firmado), 0) as com_firmados
      from con_pct group by moneda
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'moneda', moneda,
           'n_firmados', n_firmados, 'pendiente_firmados', pend_firmados,
           'n_en_firma', n_en_firma, 'pendiente_en_firma', pend_en_firma,
           'pendiente', pend_firmados + pend_en_firma,
           'comision', case when falta_tarifa then null else round(com_total, 2) end,
           'comision_firmados', case when falta_tarifa then null else round(com_firmados, 2) end
         ) order by moneda), '[]'::jsonb)
    into v_out
    from por_moneda;

  return jsonb_build_object('pct', v_pct, 'monedas', v_out);
end;
$$;

-- ---------------------------------------------------------------- tarifas: siguen siendo solo del super GLOBAL; ahora con empresa
select pg_temp.parchea('public.comision_admin_tarifa_crea(numeric,date,text)'::regprocedure, array[
  $o$insert into public.comision_admin_tarifas (pct, efectivo_desde, nota, creado_por)$o$,
  $n$with ins as (insert into public.comision_admin_tarifas (pct, efectivo_desde, nota, creado_por, empresa)$n$, '1',
  $o$values (p_pct, p_efectivo_desde, nullif(btrim(coalesce(p_nota, '')), ''), (select auth.email()))$o$,
  $n$select p_pct, p_efectivo_desde, nullif(btrim(coalesce(p_nota, '')), ''), (select auth.email()), e.clave
    from public.empresas e where e.activa order by e.orden$n$, '1',
  $o$returning id into v_id;$o$,
  $n$returning id, empresa)
  select id into v_id from ins order by (empresa = 'lawang') desc limit 1;$n$, '1']);
select pg_temp.parchea('public.comision_admin_edita_tarifa(uuid,numeric,date,text,boolean)'::regprocedure, array[
  $o$where l.tarifa_id = p_tarifa_id$o$,
  $n$where l.tarifa_id = p_tarifa_id and public.empresa_de_sociedad(l.sociedad) = v_antes.empresa$n$, '1']);

-- ---------------------------------------------------------------- el devengo automatico del 0,5 % elige la tarifa de la empresa del recibi
select pg_temp.parchea('public._comision_admin_alta_recibi()'::regprocedure, array[
  $o$where t.efectivo_desde <= current_date$o$,
  $n$where t.efectivo_desde <= current_date
     and t.empresa = coalesce(public.empresa_de_sociedad(new.sociedad), 'lawang')$n$, '1']);
