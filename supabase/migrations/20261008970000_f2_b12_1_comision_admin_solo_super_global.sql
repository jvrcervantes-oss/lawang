-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · bloque 12 · migracion 1 (7-oct-2026): COMISION DE ADMINISTRACION SOLO PARA EL SUPER ADMIN GLOBAL.
--   Orden del owner (7-oct-2026): «Comision de administracion: deberia ser como ajustes, solo acceso yo, no un super admin de empresa tenga acceso.»
--   El bloque 4 (migracion 8-oct 400500) abrio el libro `comision_admin_*` al super_admin_empresa con es_super_admin_de(empresa de la sociedad). Se revierte SOLO esa
--   parte: las 4 policies de lectura y la puerta de las 9 funciones de la pantalla vuelven a exigir es_super_admin() (el global: propietario, Andrea y Pepito).
--   NO se toca: el devengo automatico (`_comision_admin_alta_recibi` y los demas triggers), la tarifa por empresa (columna, `comision_admin_tarifa_crea`,
--   `comision_admin_edita_tarifa` ya eran solo del global) ni el calculo; `comision_admin_prevision` conserva su pct por empresa del contrato (solo cambia la puerta).
--   `puede_reparto_de` NO es de esta pantalla (es el reparto de comisiones de los agentes): no se toca.
-- destructivo-ok: create or replace de 9 funciones por parche con marca (cada marca debe salir las veces esperadas o aborta) y alter policy x4; sin DDL que destruya datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b12.sql

create or replace function pg_temp.parchea(p_sig regprocedure, p_pares text[]) returns void language plpgsql as $f$
declare d text; i int := 1; v_old text; v_new text; v_n int; v_esp int;
begin
  d := replace(pg_get_functiondef(p_sig), E'\r\n', E'\n');   -- fines de linea normalizados: las marcas de varias lineas casan sea cual sea el origen
  while i <= array_length(p_pares, 1) loop
    v_old := replace(p_pares[i], E'\r\n', E'\n'); v_new := replace(p_pares[i + 1], E'\r\n', E'\n'); v_esp := p_pares[i + 2]::int;
    v_n := (length(d) - length(replace(d, v_old, ''))) / length(v_old);
    if v_n <> v_esp then
      raise exception 'parchea %: la marca «%» sale % veces y se esperaban %', p_sig, left(v_old, 90), v_n, v_esp;
    end if;
    d := replace(d, v_old, v_new);
    i := i + 3;
  end loop;
  execute d;
end $f$;

-- ---------------------------------------------------------------- lectura: solo el super global
alter policy "comision_admin_fees: leer" on public.comision_admin_fees using (public.es_super_admin());
alter policy "comision_admin_lineas: leer" on public.comision_admin_lineas using (public.es_super_admin());
alter policy "comision_admin_tarifas: leer" on public.comision_admin_tarifas using (public.es_super_admin());
alter policy "comision_admin_cobros_super" on public.comision_admin_cobros using (public.es_super_admin());

-- ---------------------------------------------------------------- operar el libro: solo el super global
select pg_temp.parchea('public.comision_admin_anula_linea(uuid,text)'::regprocedure, array[
  $n$if not public.es_super_admin_de(public.empresa_de_sociedad((select l.sociedad from public.comision_admin_lineas l where l.id = p_linea_id))) then$n$,
  $o$if not public.es_super_admin() then$o$, '1']);
select pg_temp.parchea('public.comision_admin_repone_devengo(uuid)'::regprocedure, array[
  $n$if not public.es_super_admin_de(public.empresa_de_sociedad((select l.sociedad from public.comision_admin_lineas l where l.id = p_linea_id))) then$n$,
  $o$if not public.es_super_admin() then$o$, '1']);
select pg_temp.parchea('public.comision_admin_linea_estado(uuid,text,text,boolean,boolean,text)'::regprocedure, array[
  $n$if not public.es_super_admin_de(public.empresa_de_sociedad((select l.sociedad from public.comision_admin_lineas l where l.id = p_id))) then$n$,
  $o$if not public.es_super_admin() then$o$, '1']);
select pg_temp.parchea('public.comision_admin_anular_cobro(uuid,text)'::regprocedure, array[
  $n$if not public.es_super_admin_de(public.empresa_de_sociedad((select cx.sociedad from public.comision_admin_cobros cx where cx.id = p_cobro_id))) then$n$,
  $o$if not public.es_super_admin() then$o$, '1']);
select pg_temp.parchea('public.comision_admin_registrar_cobro(text,text,numeric,date,text,boolean,boolean,text,uuid[])'::regprocedure, array[
  $n$if not public.es_super_admin_de(public.empresa_de_sociedad(p_sociedad)) then$n$,
  $o$if not public.es_super_admin() then$o$, '1']);
select pg_temp.parchea('public.comision_admin_fee_guarda(uuid,jsonb)'::regprocedure, array[
  $n$if not public.es_super_admin_de(public.empresa_de_sociedad(coalesce(
         (select f.sociedad from public.comision_admin_fees f where f.serie_id = p_serie order by f.created_at limit 1),
         nullif(btrim(coalesce(p_datos->>'sociedad', '')), '')))) then$n$,
  $o$if not public.es_super_admin() then$o$, '1']);
select pg_temp.parchea('public.comision_admin_devenga_fees()'::regprocedure, array[
  $n$if not (select coalesce(bool_or(public.es_super_admin_de(e.clave)), false) from public.empresas e) then$n$,
  $o$if not public.es_super_admin() then$o$, '1',
  $n$from public.comision_admin_fees where efectivo_desde <= v_hoy and public.es_super_admin_de(public.empresa_de_sociedad(sociedad));$n$,
  $o$from public.comision_admin_fees where efectivo_desde <= v_hoy;$o$, '1',
  $n$where x.efectivo_desde <= v_fin and public.es_super_admin_de(public.empresa_de_sociedad(x.sociedad))$n$,
  $o$where x.efectivo_desde <= v_fin$o$, '1']);
select pg_temp.parchea('public.comision_admin_descuadres()'::regprocedure, array[
  $n$if not (select coalesce(bool_or(public.es_super_admin_de(e.clave)), false) from public.empresas e) then$n$,
  $o$if not public.es_super_admin() then$o$, '1',
  $n$where f.tipo = 'recibi' and public.es_super_admin_de(public.empresa_de_sociedad(f.sociedad))$n$,
  $o$where f.tipo = 'recibi'$o$, '3',
  $n$where l.tipo_linea = 'devengo' and public.es_super_admin_de(public.empresa_de_sociedad(l.sociedad))$n$,
  $o$where l.tipo_linea = 'devengo'$o$, '3',
  $n$(select count(*) from public.comision_admin_lineas lr where lr.revisar and public.es_super_admin_de(public.empresa_de_sociedad(lr.sociedad)))$n$,
  $o$(select count(*) from public.comision_admin_lineas where revisar)$o$, '1']);

-- la prevision conserva su tarifa por empresa de cada contrato; solo cambia la puerta (y los dos filtros que dependian de ella)
select pg_temp.parchea('public.comision_admin_prevision()'::regprocedure, array[
  $o$if not (select coalesce(bool_or(public.es_super_admin_de(e.clave)), false) from public.empresas e) then$o$,
  $n$if not public.es_super_admin() then$n$, '1',
  $o$where t.efectivo_desde <= current_date and public.es_super_admin_de(t.empresa)$o$,
  $n$where t.efectivo_desde <= current_date$n$, '1',
  E'
       and public.es_super_admin_de(public._empresa_de_contrato_int(c.id))',
  '', '1']);
