-- Reversion del BLOQUE 12 (Fase 2 empresas · comision de administracion solo super global; sociedades solo propietario), migraciones 20261008970000 y 970100 (7-oct-2026).
-- Devuelve las puertas a como las dejaron los bloques 4 (libro de administracion por empresa) y 2 (sociedades por empresa): el super de empresa vuelve a ver y operar el libro de
-- SU empresa y a editar la sociedad ligada a la suya. Parches con la misma comprobacion de marcas. Solo tiene sentido si el owner cambia de opinion.
-- destructivo-ok: recrea sociedad_super_de, pone de nuevo 5 policies y reescribe 10 funciones; no borra datos
begin;

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

-- ================================================================= migracion 2 (sociedades)
create or replace function public.sociedad_super_de(p_clave text) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.es_super_admin_de(public._empresa_sociedad(p_clave)) $$;
revoke all on function public.sociedad_super_de(text) from public, anon, authenticated, lw_lector;
grant execute on function public.sociedad_super_de(text) to authenticated, lw_lector;

alter policy "sociedades_log: leer solo super" on public.sociedades_log
  using (public.es_super_admin() or public.sociedad_super_de(clave));

create or replace function public.sociedades_ajustes_datos() returns jsonb
language plpgsql stable security definer set search_path = '' as $function$
declare
  v jsonb; v_all boolean := public.es_admin();
begin
  if public.uid_sesion() is null then
    raise exception 'sociedades_ajustes_datos: sin sesión' using errcode = '42501';
  end if;
  if not (v_all or public._rol_empresa()) then
    raise exception 'Las sociedades emisoras son de administración.' using errcode = '42501';
  end if;
  with d as (
    select f.clave, jsonb_build_object('total', sum(f.total)::int, 'abiertos', sum(f.abiertos)::int,
             'detalle', jsonb_object_agg(f.tabla, jsonb_build_object('total', f.total, 'abiertos', f.abiertos))) as j
      from public._sociedad_docs_filas(null) f group by f.clave)
  select coalesce(jsonb_agg(to_jsonb(s)
           || jsonb_build_object('documentos', coalesce(d.j, jsonb_build_object('total', 0, 'abiertos', 0, 'detalle', '{}'::jsonb)))
           || case when v_all then '{}'::jsonb
                   else jsonb_build_object('puede_escribir_esta', public.es_super_admin_de(public._empresa_sociedad(s.clave))) end
           order by s.orden, s.clave), '[]'::jsonb)
    into v
    from public.sociedades s left join d on d.clave = s.clave
   where v_all or (public._empresa_sociedad(s.clave) is not null and public.es_admin_de(public._empresa_sociedad(s.clave)));
  return jsonb_build_object('puede_escribir', public.es_super_admin() or public._super_empresa_alguna(), 'sociedades', v);
end $function$;

do $m$
declare d text; nuevo text; viejo text; n int;
begin
  d := pg_get_functiondef('public.sociedad_guarda(text,jsonb,boolean)'::regprocedure);
  viejo := E'  if not public.es_propietario() then\n'
        || E'    raise exception ''Las sociedades emisoras solo las edita el propietario'' using errcode = ''42501'';\n'
        || E'  end if;';
  nuevo := E'  perform public._super_o_empresa();\n'
        || E'  if not public.es_super_admin() then\n'
        || E'    -- super_admin_empresa: solo EDITA la sociedad ligada a su empresa; dar de alta una sociedad nueva es global (no tiene empresa a la que ligarse)\n'
        || E'    if p_nueva or public._empresa_sociedad(v_clave) is null or not public.es_super_admin_de(public._empresa_sociedad(v_clave)) then\n'
        || E'      raise exception ''Solo puedes editar la sociedad de tu empresa; las demas y las altas son del propietario o de un super admin global'' using errcode = ''42501'';\n'
        || E'    end if;\n'
        || E'  end if;';
  n := (length(d) - length(replace(d, viejo, ''))) / length(viejo);
  if n <> 1 then raise exception 'sociedad_guarda: se esperaba 1 coincidencia y hay %', n; end if;
  execute replace(d, viejo, nuevo);
end $m$;

-- ================================================================= migracion 1 (libro de administracion)
alter policy "comision_admin_fees: leer" on public.comision_admin_fees
  using (public.es_super_admin_de(public.empresa_de_sociedad(sociedad)));
alter policy "comision_admin_lineas: leer" on public.comision_admin_lineas
  using (public.es_super_admin_de(public.empresa_de_sociedad(sociedad)));
alter policy "comision_admin_tarifas: leer" on public.comision_admin_tarifas
  using (public.es_super_admin_de(empresa));
alter policy "comision_admin_cobros_super" on public.comision_admin_cobros
  using (public.es_super_admin_de(public.empresa_de_sociedad(sociedad)));

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
select pg_temp.parchea('public.comision_admin_descuadres()'::regprocedure, array[
  $o$if not public.es_super_admin() then$o$,
  $n$if not (select coalesce(bool_or(public.es_super_admin_de(e.clave)), false) from public.empresas e) then$n$, '1',
  $o$where f.tipo = 'recibi'$o$,
  $n$where f.tipo = 'recibi' and public.es_super_admin_de(public.empresa_de_sociedad(f.sociedad))$n$, '3',
  $o$where l.tipo_linea = 'devengo'$o$,
  $n$where l.tipo_linea = 'devengo' and public.es_super_admin_de(public.empresa_de_sociedad(l.sociedad))$n$, '3',
  $o$(select count(*) from public.comision_admin_lineas where revisar)$o$,
  $n$(select count(*) from public.comision_admin_lineas lr where lr.revisar and public.es_super_admin_de(public.empresa_de_sociedad(lr.sociedad)))$n$, '1']);
select pg_temp.parchea('public.comision_admin_prevision()'::regprocedure, array[
  $o$if not public.es_super_admin() then$o$,
  $n$if not (select coalesce(bool_or(public.es_super_admin_de(e.clave)), false) from public.empresas e) then$n$, '1',
  $o$where t.efectivo_desde <= current_date
   order by e.orden, t.efectivo_desde desc$o$,
  $n$where t.efectivo_desde <= current_date and public.es_super_admin_de(t.empresa)
   order by e.orden, t.efectivo_desde desc$n$, '1',
  $o$(c.bloqueado or public.contrato_firma_viva(c.id))$o$,
  $n$(c.bloqueado or public.contrato_firma_viva(c.id))
       and public.es_super_admin_de(public._empresa_de_contrato_int(c.id))$n$, '1']);

commit;
