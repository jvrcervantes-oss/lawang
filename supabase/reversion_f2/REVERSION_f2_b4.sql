-- Reversion del BLOQUE 4 (Fase 2 empresas · comisiones, equipos de venta y condiciones), migraciones 20261008400100..400500 (8-oct-2026).
-- Devuelve funciones y policies a la version viva de antes del bloque (parches inversos, con la misma comprobacion de marcas) y retira las copias de sandal_woods.
-- VALE MIENTRAS NADIE TENGA ROL DE EMPRESA y mientras nada cuelgue de las copias (el propio script lo comprueba y se niega si una venta, un devengo o una linea del libro ya usa una copia).
-- No se ensayo sobre produccion: es la receta inversa de las migraciones; si hay que usarla, ensayarla antes en una transaccion con rollback.
-- destructivo-ok: borra las filas copiadas para sandal_woods (equipos, miembros, plantillas, condiciones, tramos, tarifa) y las columnas empresa creadas en el bloque
begin;

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

-- 0. comprobacion: nada puede colgar de las copias
do $c$
begin
  if exists (select 1 from public.contrato_closer k join public.equipos_venta e on e.id = k.equipo_id where e.empresa = 'sandal_woods')
     or exists (select 1 from public.comisiones_devengadas d join public.condiciones_comision c on c.id = d.condicion_id where c.empresa = 'sandal_woods')
     or exists (select 1 from public.contrato_roles_equipo r join public.equipos_venta e on e.id = r.equipo_id where e.empresa = 'sandal_woods')
     or exists (select 1 from public.comision_admin_lineas l join public.comision_admin_tarifas t on t.id = l.tarifa_id where t.empresa = 'sandal_woods') then
    raise exception 'Hay ventas, devengos o lineas del libro que ya usan una copia de sandal_woods: no se puede revertir sin decidir antes que hacer con ellas';
  end if;
end $c$;

-- ================================================================= migracion 5 (libro de administracion)
alter policy "comision_admin_fees: leer" on public.comision_admin_fees using (public.es_super_admin());
alter policy "comision_admin_lineas: leer" on public.comision_admin_lineas using (public.es_super_admin());
alter policy "comision_admin_tarifas: leer" on public.comision_admin_tarifas using (public.es_super_admin());
alter policy "comision_admin_cobros_super" on public.comision_admin_cobros using (public.es_super_admin());

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
select pg_temp.parchea('public.comision_admin_tarifa_crea(numeric,date,text)'::regprocedure, array[
  $n$with ins as (insert into public.comision_admin_tarifas (pct, efectivo_desde, nota, creado_por, empresa)$n$,
  $o$insert into public.comision_admin_tarifas (pct, efectivo_desde, nota, creado_por)$o$, '1',
  $n$select p_pct, p_efectivo_desde, nullif(btrim(coalesce(p_nota, '')), ''), (select auth.email()), e.clave
    from public.empresas e where e.activa order by e.orden$n$,
  $o$values (p_pct, p_efectivo_desde, nullif(btrim(coalesce(p_nota, '')), ''), (select auth.email()))$o$, '1',
  $n$returning id, empresa)
  select id into v_id from ins order by (empresa = 'lawang') desc limit 1;$n$,
  $o$returning id into v_id;$o$, '1']);
select pg_temp.parchea('public.comision_admin_edita_tarifa(uuid,numeric,date,text,boolean)'::regprocedure, array[
  $n$where l.tarifa_id = p_tarifa_id and public.empresa_de_sociedad(l.sociedad) = v_antes.empresa$n$,
  $o$where l.tarifa_id = p_tarifa_id$o$, '1']);
select pg_temp.parchea('public._comision_admin_alta_recibi()'::regprocedure, array[
  $n$where t.efectivo_desde <= current_date
     and t.empresa = coalesce(public.empresa_de_sociedad(new.sociedad), 'lawang')$n$,
  $o$where t.efectivo_desde <= current_date$o$, '1']);

create or replace function public.comision_admin_prevision()
 returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_pct numeric;
  v_out jsonb;
begin
  if not public.es_super_admin() then
    raise exception 'comision_admin_prevision: solo super_admin';
  end if;

  select t.pct into v_pct
    from public.comision_admin_tarifas t
   where t.efectivo_desde <= current_date
   order by t.efectivo_desde desc
   limit 1;

  with vivos as (
    select coalesce(c.moneda, 'EUR') as moneda,
           c.bloqueado as firmado,
           greatest(coalesce(c.precio_total, 0)
                    - public.contrato_cobrado(c.id)
                    - coalesce(public.lw_importe(c.datos->'fields'->>'carta_cobrado_importe'), 0), 0) as pendiente
      from public.contratos c
     where c.liberado_en is null
       and c.tipo not like 'carta_reserva%'
       and coalesce(c.precio_total, 0) > 0
       and (c.bloqueado or public.contrato_firma_viva(c.id))
  ), por_moneda as (
    select moneda,
           count(*) filter (where firmado)                          as n_firmados,
           coalesce(sum(pendiente) filter (where firmado), 0)       as pend_firmados,
           count(*) filter (where not firmado)                      as n_en_firma,
           coalesce(sum(pendiente) filter (where not firmado), 0)   as pend_en_firma
      from vivos group by moneda
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'moneda', moneda,
           'n_firmados', n_firmados, 'pendiente_firmados', pend_firmados,
           'n_en_firma', n_en_firma, 'pendiente_en_firma', pend_en_firma,
           'pendiente', pend_firmados + pend_en_firma,
           'comision', case when v_pct is null then null
                            else round((pend_firmados + pend_en_firma) * v_pct / 100, 2) end,
           'comision_firmados', case when v_pct is null then null
                            else round(pend_firmados * v_pct / 100, 2) end
         ) order by moneda), '[]'::jsonb)
    into v_out
    from por_moneda;

  return jsonb_build_object('pct', v_pct, 'monedas', v_out);
end;
$$;

-- ================================================================= migracion 4 (equipos, miembros, plantillas, condiciones)
alter policy "equipos_venta: leer" on public.equipos_venta
  using (es_admin() OR (lower(manager_email) = lower(COALESCE(( SELECT auth.email() AS email), ''::text))) OR (EXISTS ( SELECT 1
           FROM equipo_miembros em
          WHERE ((em.equipo_id = equipos_venta.id) AND (lower(em.closer_email) = lower(COALESCE(( SELECT auth.email() AS email), ''::text)))))));
alter policy "equipo_miembros: leer" on public.equipo_miembros
  using (es_admin() OR (lower(closer_email) = lower(COALESCE(( SELECT auth.email() AS email), ''::text))) OR es_manager_de_equipo(equipo_id));
alter policy "condiciones_comision: leer" on public.condiciones_comision
  using (es_admin() OR ((nivel = ANY (ARRAY['closer'::text, 'setter'::text, 'team_lead'::text])) AND (lower(COALESCE(closer_email, ''::text)) = lower(COALESCE(( SELECT auth.email() AS email), '-'::text))) AND ((equipo_id IS NULL) OR COALESCE(( SELECT ev.closers_ven_comision
           FROM equipos_venta ev
          WHERE (ev.id = condiciones_comision.equipo_id)), false))) OR ((nivel = 'manager'::text) AND (EXISTS ( SELECT 1
           FROM equipos_venta ev
          WHERE ((ev.id = condiciones_comision.equipo_id) AND (lower(ev.manager_email) = lower(COALESCE(( SELECT auth.email() AS email), '-'::text))))))));

-- las versiones de siempre de las tres funciones retiradas (a partir de las nuevas, con parche inverso)
create function public._condicion_es_mia(p_nivel text, p_equipo uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select (public.es_admin() and public.puede('comisiones_reparto'))
      or (p_nivel in ('closer', 'setter', 'team_lead') and p_equipo is not null and public.es_manager_de_equipo(p_equipo))
$$;
revoke all on function public._condicion_es_mia(text, uuid) from public, anon, authenticated, lw_lector;
select pg_temp.parchea('public._equipo_candidato_valido(text,text)'::regprocedure, array[
  $n$CREATE OR REPLACE FUNCTION public._equipo_candidato_valido(p_email text, p_empresa text)$n$,
  $o$CREATE OR REPLACE FUNCTION public._equipo_candidato_valido(p_email text)$o$, '1',
  $n$v_rol in ('sales_manager', 'admin', 'super_admin', 'project_manager', 'admin_empresa', 'super_admin_empresa')$n$,
  $o$v_rol in ('sales_manager', 'admin', 'super_admin', 'project_manager')$o$, '1',
  $n$where lower(ev.manager_email) = v_e and (p_empresa is null or ev.empresa = p_empresa))$n$,
  $o$where lower(ev.manager_email) = v_e)$o$, '1',
  $n$where lower(em.closer_email) = v_e and (em.hasta is null or em.hasta >= v_hoy) and (p_empresa is null or em.empresa = p_empresa))$n$,
  $o$where lower(em.closer_email) = v_e and (em.hasta is null or em.hasta >= v_hoy))$o$, '1',
  $n$if p_empresa is not null and exists (select 1 from public.usuarios u where lower(u.email) = v_e and u.activo
                                           and cardinality(coalesce(u.empresas, '{}')) > 0 and not (p_empresa = any (u.empresas))) then
    return 'Esa persona no vende en la empresa de este equipo';
  end if;
  return null;$n$,
  $o$return null;$o$, '1']);
select pg_temp.parchea('public._condicion_ventas_afectadas(uuid,uuid,text,text,date,date,text)'::regprocedure, array[
  $n$CREATE OR REPLACE FUNCTION public._condicion_ventas_afectadas(p_equipo uuid, p_proy uuid, p_nivel text, p_closer text, p_d1 date, p_d2 date, p_empresa text)$n$,
  $o$CREATE OR REPLACE FUNCTION public._condicion_ventas_afectadas(p_equipo uuid, p_proy uuid, p_nivel text, p_closer text, p_d1 date, p_d2 date)$o$, '1',
  $n$and (p_proy is null or c.proyecto_id = p_proy)
     and public._empresa_de_contrato_int(c.id) = p_empresa$n$,
  $o$and (p_proy is null or c.proyecto_id = p_proy)$o$, '1']);
revoke all on function public._condicion_ventas_afectadas(uuid, uuid, text, text, date, date) from public, anon, authenticated, lw_lector;

-- funciones de condiciones: de vuelta a las llamadas de dos argumentos (la interna pasa a ser la publica de siempre)
select pg_temp.parchea('public._condicion_comision_guarda_en(uuid,jsonb,jsonb,text,text)'::regprocedure, array[
  $n$CREATE OR REPLACE FUNCTION public._condicion_comision_guarda_en(p_id uuid, p_cond jsonb, p_tramos jsonb, p_motivo text, p_empresa text)$n$,
  $o$CREATE OR REPLACE FUNCTION public.condicion_comision_guarda(p_id uuid, p_cond jsonb, p_tramos jsonb, p_motivo text DEFAULT NULL::text)$o$, '1',
  $n$boolean;
  v_emp    text;$n$,
  $o$boolean := public.es_admin() and public.puede('comisiones_reparto');$o$, '1',
  $n$v_emp := coalesce(public.empresa_de_equipo(v_equipo), public._empresa_de_proyecto_int(v_proy), p_empresa);
    if v_emp is null then
      raise exception 'Falta la empresa de la condición (o el proyecto no tiene empresa)' using errcode = '22023';
    end if;
    v_admin := public.puede_reparto_de(v_emp);
    if not public._condicion_es_mia(v_nivel, v_equipo, v_emp) then$n$,
  $o$if not public._condicion_es_mia(v_nivel, v_equipo) then$o$, '1',
  $n$v_emp := v_old.empresa;
  v_admin := public.puede_reparto_de(v_emp);
  if not found or not public._condicion_es_mia(v_old.nivel, v_old.equipo_id, v_old.empresa) then$n$,
  $o$if not found or not public._condicion_es_mia(v_old.nivel, v_old.equipo_id) then$o$, '1',
  $n$if not public.es_super_admin_de(v_emp) and public._condicion_a_su_favor($n$,
  $o$if not public.es_super_admin() and public._condicion_a_su_favor($o$, '2',
  $n$where c.equipo_id is not distinct from v_equipo and c.proyecto_id is not distinct from v_proy and c.empresa = v_emp$n$,
  $o$where c.equipo_id is not distinct from v_equipo and c.proyecto_id is not distinct from v_proy$o$, '1',
  $n$importe_fijo, vigente_desde, created_by, sustituye_a, empresa)$n$,
  $o$importe_fijo, vigente_desde, created_by, sustituye_a)$o$, '1',
  $n$v_fijo, v_desde, (select auth.email()), v_sust, v_emp)$n$,
  $o$v_fijo, v_desde, (select auth.email()), v_sust)$o$, '1',
  $n$public._condicion_ventas_afectadas(v_equipo, v_proy, v_nivel, v_closer, v_desde, v_hoy, v_emp);$n$,
  $o$public._condicion_ventas_afectadas(v_equipo, v_proy, v_nivel, v_closer, v_desde, v_hoy);$o$, '1',
  $n$coalesce(v_old.vigente_hasta, v_hoy), v_old.empresa);$n$,
  $o$coalesce(v_old.vigente_hasta, v_hoy));$o$, '1',
  $n$v_old.nivel, v_old.closer_email, v_d1, v_d2, v_old.empresa);$n$,
  $o$v_old.nivel, v_old.closer_email, v_d1, v_d2);$o$, '1']);
drop function public._condicion_comision_guarda_en(uuid, jsonb, jsonb, text, text);
select pg_temp.parchea('public.condicion_comision_activa(uuid,boolean)'::regprocedure, array[
  $n$public._condicion_es_mia(v_old.nivel, v_old.equipo_id, v_old.empresa)$n$,
  $o$public._condicion_es_mia(v_old.nivel, v_old.equipo_id)$o$, '1',
  $n$if not public.es_super_admin_de(v_old.empresa) and public._condicion_a_su_favor($n$,
  $o$if not public.es_super_admin() and public._condicion_a_su_favor($o$, '1']);
select pg_temp.parchea('public.condicion_comision_borra(uuid)'::regprocedure, array[
  $n$public._condicion_es_mia(v_old.nivel, v_old.equipo_id, v_old.empresa)$n$,
  $o$public._condicion_es_mia(v_old.nivel, v_old.equipo_id)$o$, '1',
  $n$if not public.es_super_admin_de(v_old.empresa) and public._condicion_a_su_favor($n$,
  $o$if not public.es_super_admin() and public._condicion_a_su_favor($o$, '1']);
select pg_temp.parchea('public._trg_condicion_comision_manager()'::regprocedure, array[
  $n$or public.es_admin_de(case when tg_op = 'DELETE' then old.empresa else new.empresa end) then$n$,
  $o$or public.es_admin() then$o$, '1']);
drop function public._condicion_es_mia(text, uuid, text);

-- equipos, miembros, plantilla
select pg_temp.parchea('public.equipo_candidatos_sm(uuid)'::regprocedure, array[
  $n$public.es_admin_de(public.empresa_de_equipo(p_equipo)) or public.es_manager_de_equipo(p_equipo)$n$,
  $o$public.es_admin() or public.es_manager_de_equipo(p_equipo)$o$, '1',
  $n$public._equipo_candidato_valido(u.email, public.empresa_de_equipo(p_equipo)) is null$n$,
  $o$public._equipo_candidato_valido(u.email) is null$o$, '1']);
select pg_temp.parchea('public._equipo_miembro_guarda_con(uuid,uuid,text,date,date,integer)'::regprocedure, array[
  $n$if public.es_admin_de(public.empresa_de_equipo(p_equipo)) then$n$,
  $o$if public.es_admin() then$o$, '1',
  $n$and not public.es_super_admin_de(public.empresa_de_equipo(p_equipo)) then$n$,
  $o$and not public.es_super_admin() then$o$, '1',
  $n$public._equipo_candidato_valido(v_email, public.empresa_de_equipo(p_equipo)) is not null$n$,
  $o$public._equipo_candidato_valido(v_email) is not null$o$, '1']);
select pg_temp.parchea('public._equipo_miembro_mueve(uuid,uuid,text,date,date,boolean,integer,boolean,boolean)'::regprocedure, array[
  $n$if not found then raise exception 'Ese miembro no existe' using errcode = 'P0002'; end if;
    if not public.es_admin_de(public.empresa_de_equipo(v_old.equipo_id)) then
      raise exception 'Ese miembro es de un equipo de otra empresa' using errcode = '42501';
    end if;$n$,
  $o$if not found then raise exception 'Ese miembro no existe' using errcode = 'P0002'; end if;$o$, '1',
  $n$if exists (select 1 from public.usuarios u where lower(u.email) = v_email and u.activo and cardinality(coalesce(u.empresas, '{}')) > 0
                 and not ((select e.empresa from public.equipos_venta e where e.id = p_equipo) = any (u.empresas))) then
    raise exception 'Esa persona no vende en la empresa de este equipo' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtext(v_email));$n$,
  $o$perform pg_advisory_xact_lock(hashtext(v_email));$o$, '1',
  $n$and (p_id is null or em.id <> p_id)
     and em.empresa = (select e.empresa from public.equipos_venta e where e.id = p_equipo)$n$,
  $o$and (p_id is null or em.id <> p_id)$o$, '1']);
select pg_temp.parchea('public.equipo_miembro_anade(uuid,uuid)'::regprocedure, array[
  $n$if not public.es_admin_de(public.empresa_de_equipo(p_equipo)) and ($n$,
  $o$if not public.es_admin() and ($o$, '1',
  $n$if public.es_admin_de(public.empresa_de_equipo(p_equipo)) then$n$,
  $o$if public.es_admin() then$o$, '1']);
select pg_temp.parchea('public.equipo_miembro_baja(uuid,date)'::regprocedure, array[
  $n$v_admin boolean;$n$,
  $o$v_admin boolean := public.es_admin();$o$, '1',
  $n$if not found then raise exception 'Ese miembro no existe' using errcode = 'P0002'; end if;
  v_admin := public.es_admin_de(public.empresa_de_equipo(v_old.equipo_id));$n$,
  $o$if not found then raise exception 'Ese miembro no existe' using errcode = 'P0002'; end if;$o$, '1']);
select pg_temp.parchea('public.equipo_miembro_guarda(uuid,uuid,text,date,date)'::regprocedure, array[
  $n$if not public.es_admin_de(public.empresa_de_equipo(p_equipo)) then$n$,
  $o$if not public.es_admin() then$o$, '1']);
select pg_temp.parchea('public.equipo_miembro_guarda_confirmada(uuid,uuid,text,date,date,integer)'::regprocedure, array[
  $n$if not public.es_admin_de(public.empresa_de_equipo(p_equipo)) then$n$,
  $o$if not public.es_admin() then$o$, '1']);
select pg_temp.parchea('public.equipo_miembro_rol(uuid,text,text)'::regprocedure, array[
  $n$public.es_admin_de(public.empresa_de_equipo(v_old.equipo_id)) or public.es_manager_de_equipo(v_old.equipo_id)$n$,
  $o$public.es_admin() or public.es_manager_de_equipo(v_old.equipo_id)$o$, '1']);
select pg_temp.parchea('public.equipo_miembro_vista_previa(uuid,uuid,text,date,date)'::regprocedure, array[
  $n$if not public.es_admin_de(public.empresa_de_equipo(p_equipo)) then$n$,
  $o$if not public.es_admin() then$o$, '1']);
select pg_temp.parchea('public.equipo_venta_activa(uuid,boolean)'::regprocedure, array[
  $n$if not public.es_admin_de(public.empresa_de_equipo(p_id)) then$n$,
  $o$if not public.es_admin() then$o$, '1']);
select pg_temp.parchea('public.equipo_closers_ven_comision(uuid,boolean)'::regprocedure, array[
  $n$public.es_admin_de(v_old.empresa) or public.es_manager_de_equipo(p_equipo)$n$,
  $o$public.es_admin() or public.es_manager_de_equipo(p_equipo)$o$, '1']);
select pg_temp.parchea('public.equipo_venta_guarda(uuid,text,text)'::regprocedure, array[
  $n$v_nom text := nullif(btrim(coalesce(p_nombre, '')), '');
  v_emp text;$n$,
  $o$v_nom text := nullif(btrim(coalesce(p_nombre, '')), '');$o$, '1',
  $n$v_emp := coalesce(public.empresa_de_equipo(p_id),
                    (select u.empresas[1] from public.usuarios u where u.user_id = (select auth.uid()) and u.activo and cardinality(coalesce(u.empresas, '{}')) = 1),
                    'lawang');
  if not public.es_admin_de(v_emp) then raise exception 'Los equipos de venta los gestiona administración' using errcode = '42501'; end if;
  if v_man is not null and exists (select 1 from public.usuarios u where lower(u.email) = v_man and u.activo
                                    and cardinality(coalesce(u.empresas, '{}')) > 0 and not (v_emp = any (u.empresas))) then
    raise exception 'El manager no vende en la empresa de este equipo' using errcode = '22023';
  end if;$n$,
  $o$if not public.es_admin() then raise exception 'Los equipos de venta los gestiona administración' using errcode = '42501'; end if;$o$, '1',
  $n$and not public.es_super_admin_de(v_emp) then$n$,
  $o$and not public.es_super_admin() then$o$, '1',
  $n$insert into public.equipos_venta (nombre, manager_email, empresa) values (v_nom, v_man, v_emp) returning id into v_id;$n$,
  $o$insert into public.equipos_venta (nombre, manager_email) values (v_nom, v_man) returning id into v_id;$o$, '1']);
select pg_temp.parchea('public.plantilla_reparto_guarda(uuid,jsonb)'::regprocedure, array[
  $n$public.es_admin_de(public.empresa_de_equipo(p_equipo)) or public.es_manager_de_equipo(p_equipo)$n$,
  $o$public.es_admin() or public.es_manager_de_equipo(p_equipo)$o$, '1']);
select pg_temp.parchea('public.plantilla_reparto_lee(uuid)'::regprocedure, array[
  $n$public.es_admin_de(public.empresa_de_equipo(p_equipo)) or public.es_manager_de_equipo(p_equipo)$n$,
  $o$public.es_admin() or public.es_manager_de_equipo(p_equipo)$o$, '1']);
drop function public._equipo_candidato_valido(text, text);

-- ================================================================= migracion 3 (puertas de las comisiones devengadas y ventas por su cuenta)
select pg_temp.parchea('public.comision_visible(text,text,uuid,uuid)'::regprocedure, array[
  $n$public.puede_reparto_de(public._empresa_de_contrato_int(p_raiz))$n$,
  $o$(public.es_admin() and public.puede('comisiones_reparto'))$o$, '1']);
select pg_temp.parchea('public.comision_trazabilidad(uuid)'::regprocedure, array[
  $n$public.puede_reparto_de(public._empresa_de_contrato_int(d.contrato_raiz_id))$n$,
  $o$(public.es_admin() and public.puede('comisiones_reparto'))$o$, '1']);
select pg_temp.parchea('public._comision_devengo_admin_puede(uuid)'::regprocedure, array[
  $n$public.puede_reparto_de(public._empresa_de_contrato_int(d.contrato_raiz_id))$n$,
  $o$(public.es_admin() and public.puede('comisiones_reparto'))$o$, '1']);
select pg_temp.parchea('public.comision_marca_pagada(uuid)'::regprocedure, array[
  $n$public.puede_reparto_de(public._empresa_de_contrato_int(v.contrato_raiz_id))$n$,
  $o$(public.es_admin() and public.puede('comisiones_reparto'))$o$, '1']);
select pg_temp.parchea('public.comision_devengo_anular_lawang(uuid,text)'::regprocedure, array[
  $n$public.puede_reparto_de(public._empresa_de_contrato_int((select x.contrato_raiz_id from public.comisiones_devengadas x where x.id = p_id)))$n$,
  $o$(public.es_admin() and public.puede('comisiones_reparto'))$o$, '1']);
select pg_temp.parchea('public.comision_diferencia_resolver(uuid,text,text)'::regprocedure, array[
  $n$if not public.es_admin_de(public._empresa_de_contrato_int(d.contrato_raiz_id)) then$n$,
  $o$if not public.es_admin() then$o$, '1',
  $n$public.puede_reparto_de(public._empresa_de_contrato_int(d.contrato_raiz_id))$n$,
  $o$(public.es_admin() and public.puede('comisiones_reparto'))$o$, '1']);
select pg_temp.parchea('public.comision_rol_asignar(uuid,text,text)'::regprocedure, array[
  $n$public.puede_reparto_de(public._empresa_de_contrato_int(p_raiz))$n$,
  $o$(public.es_admin() and public.puede('comisiones_reparto'))$o$, '1',
  $n$and not public.es_super_admin_de(public._empresa_de_contrato_int(p_raiz)) then$n$,
  $o$and not public.es_super_admin() then$o$, '1']);
select pg_temp.parchea('public.comision_recalcular(uuid,text)'::regprocedure, array[
  $n$if not public.es_super_admin_de(public._empresa_de_contrato_int(p_raiz)) then$n$,
  $o$if not public.es_super_admin() then$o$, '1']);
select pg_temp.parchea('public._trg_contrato_padre_con_comisiones()'::regprocedure, array[
  $n$or public.es_super_admin_de(public._empresa_de_contrato_int(new.id)) then return new; end if;$n$,
  $o$or public.es_super_admin() then return new; end if;$o$, '1']);
select pg_temp.parchea('public.venta_modo_admin(uuid,text,text)'::regprocedure, array[
  $n$public.puede_reparto_de(public._empresa_de_contrato_int(p_raiz))$n$,
  $o$(public.es_admin() and public.puede('comisiones_reparto'))$o$, '1']);
select pg_temp.parchea('public.venta_objecion_resolver(uuid,text,text)'::regprocedure, array[
  $n$public.puede_reparto_de(public._empresa_de_contrato_int((select rv.contrato_raiz_id from public.reclamaciones_venta_propia rv where rv.id = p_id)))$n$,
  $o$(public.es_admin() and public.puede('comisiones_reparto'))$o$, '1']);
select pg_temp.parchea('public.venta_propia_resolver(uuid,boolean,text)'::regprocedure, array[
  $n$public.puede_reparto_de(public._empresa_de_contrato_int(r.contrato_raiz_id))$n$,
  $o$(public.es_admin() and public.puede('comisiones_reparto'))$o$, '1']);
select pg_temp.parchea('public.ventas_por_su_cuenta_cuota()'::regprocedure, array[
  $n$public.puede_reparto_de(public._empresa_de_contrato_int(k.contrato_id))$n$,
  $o$(public.es_admin() and public.puede('comisiones_reparto'))$o$, '1']);
select pg_temp.parchea('public.ventas_por_su_cuenta_equipo()'::regprocedure, array[
  $n$public.puede_reparto_de(public._empresa_de_contrato_int(k.contrato_id))$n$,
  $o$(public.es_admin() and public.puede('comisiones_reparto'))$o$, '1']);
select pg_temp.parchea('public.venta_objecion_crear(uuid,text)'::regprocedure, array[
  $n$(u.rol in ('admin', 'super_admin') or (u.rol in ('admin_empresa', 'super_admin_empresa') and public._empresa_de_contrato_int(p_raiz) = any (u.empresas)))$n$,
  $o$u.rol in ('admin', 'super_admin')$o$, '1']);

-- ================================================================= migraciones 2 y 2b (el calculo)
select pg_temp.parchea('public._equipo_de_venta(uuid)'::regprocedure, array[
  $n$join public.equipos_venta ev on ev.id = em.equipo_id and ev.activo and ev.empresa = public._empresa_de_contrato_int(p_raiz)$n$,
  $o$join public.equipos_venta ev on ev.id = em.equipo_id and ev.activo$o$, '1']);
select pg_temp.parchea('public._venta_equipo(uuid)'::regprocedure, array[
  $n$join public.equipos_venta ev on ev.id = em.equipo_id and ev.activo and ev.empresa = public._empresa_de_contrato_int(p_contrato)$n$,
  $o$join public.equipos_venta ev on ev.id = em.equipo_id and ev.activo$o$, '1']);
select pg_temp.parchea('public._venta_congela_equipo(uuid)'::regprocedure, array[
  $n$join public.equipos_venta ev on ev.id = em.equipo_id and ev.activo and ev.empresa = public._empresa_de_contrato_int(p_raiz)$n$,
  $o$join public.equipos_venta ev on ev.id = em.equipo_id and ev.activo$o$, '1']);
select pg_temp.parchea('public.comisiones_evaluar_contrato(uuid)'::regprocedure, array[
  $n$v_man_base             text;
  v_empresa              text;$n$,
  $o$v_man_base             text;$o$, '1',
  $n$v_precio_total := public._comisiones_precio_total(v_raiz_id);
  v_empresa := public._empresa_de_proyecto_int(v_proyecto_id);$n$,
  $o$v_precio_total := public._comisiones_precio_total(v_raiz_id);$o$, '1',
  $n$where lower(em.closer_email) = lower(v_closer_email)
     and ev.empresa = v_empresa$n$,
  $o$where lower(em.closer_email) = lower(v_closer_email)$o$, '1',
  $n$where c.equipo_id is null
         and c.empresa = v_empresa$n$,
  $o$where c.equipo_id is null$o$, '1']);
select pg_temp.parchea('public.comisiones_ventas_equipo()'::regprocedure, array[
  $n$join public.equipos_venta ev on ev.id = em.equipo_id and ev.activo and ev.empresa = coalesce(public._empresa_de_contrato_int(c.id), 'lawang')$n$,
  $o$join public.equipos_venta ev on ev.id = em.equipo_id and ev.activo$o$, '1',
  $n$(public.puede_reparto_de(public._empresa_de_contrato_int(v.id)) or lower(ev.manager_email) = yo.e or v.closer = yo.e$n$,
  $o$(yo.admin or lower(ev.manager_email) = yo.e or v.closer = yo.e$o$, '1']);
select pg_temp.parchea('public._condicion_solapa(uuid)'::regprocedure, array[
  $n$and b.nivel = a.nivel
     and b.empresa = a.empresa$n$,
  $o$and b.nivel = a.nivel$o$, '1']);

drop function public.mi_condicion_comision();
create function public.mi_condicion_comision()
 returns table(ambito text, equipo_nombre text, oculta boolean, proyecto_id uuid, nivel text, pct_comision numeric, base_calculo text, importe_fijo numeric, personal boolean, vigente_desde date)
 language plpgsql stable security definer set search_path = '' as $$
declare
  v_yo text := lower(coalesce(auth.email(), ''));
  v_hoy date := current_date;
  v_eq record;
  v_nivel text;
  v_p uuid;
  v_c public.condiciones_comision;
  v_vistas uuid[] := '{}';
begin
  if auth.uid() is null or v_yo = '' then
    raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501';
  end if;

  select em.equipo_id, em.rol, ev.nombre, ev.closers_ven_comision into v_eq
    from public.equipo_miembros em
    join public.equipos_venta ev on ev.id = em.equipo_id and ev.activo
   where lower(em.closer_email) = v_yo and em.desde <= v_hoy and (em.hasta is null or em.hasta >= v_hoy)
   order by em.created_at desc
   limit 1;

  if v_eq.equipo_id is not null then
    if not coalesce(v_eq.closers_ven_comision, true) then
      return query select 'equipo'::text, v_eq.nombre::text, true, null::uuid, null::text, null::numeric, null::text,
                          null::numeric, null::boolean, null::date;
      return;
    end if;
    v_nivel := case when v_eq.rol in ('closer', 'setter', 'team_lead') then v_eq.rol else 'closer' end;
    for v_p in
      select null::uuid
      union
      select distinct c.proyecto_id from public.condiciones_comision c
       where c.equipo_id = v_eq.equipo_id and c.nivel = v_nivel and c.proyecto_id is not null
         and (c.activo or c.vigente_hasta is not null)
         and c.vigente_desde <= v_hoy and (c.vigente_hasta is null or c.vigente_hasta >= v_hoy)
         and (c.closer_email is null or lower(c.closer_email) = v_yo)
    loop
      select * into v_c from public.condiciones_comision c
       where c.equipo_id = v_eq.equipo_id
         and (c.proyecto_id = v_p or c.proyecto_id is null)
         and c.nivel = v_nivel
         and (c.activo or c.vigente_hasta is not null)
         and c.vigente_desde <= v_hoy and (c.vigente_hasta is null or c.vigente_hasta >= v_hoy)
         and lower(c.closer_email) = v_yo
       order by (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
       limit 1;
      if not found then
        select * into v_c from public.condiciones_comision c
         where c.equipo_id = v_eq.equipo_id
           and (c.proyecto_id = v_p or c.proyecto_id is null)
           and c.nivel = v_nivel
           and (c.activo or c.vigente_hasta is not null)
           and c.vigente_desde <= v_hoy and (c.vigente_hasta is null or c.vigente_hasta >= v_hoy)
           and c.closer_email is null
         order by (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
         limit 1;
      end if;
      if found and not (v_c.id = any(v_vistas)) then
        v_vistas := v_vistas || v_c.id;
        return query select 'equipo'::text, v_eq.nombre::text, false, v_c.proyecto_id, v_c.nivel, v_c.pct_comision,
                            v_c.base_calculo, v_c.importe_fijo, v_c.closer_email is not null, v_c.vigente_desde;
      end if;
    end loop;
    return;
  end if;

  for v_p in
    select null::uuid
    union
    select distinct c.proyecto_id from public.condiciones_comision c
     where c.equipo_id is null and c.nivel = 'closer' and c.proyecto_id is not null
       and (c.activo or c.vigente_hasta is not null)
       and c.vigente_desde <= v_hoy and (c.vigente_hasta is null or c.vigente_hasta >= v_hoy)
       and (c.closer_email is null or lower(c.closer_email) = v_yo)
  loop
    select * into v_c from public.condiciones_comision c
     where c.equipo_id is null
       and c.nivel = 'closer'
       and (c.activo or c.vigente_hasta is not null)
       and c.vigente_desde <= v_hoy and (c.vigente_hasta is null or c.vigente_hasta >= v_hoy)
       and (c.proyecto_id = v_p or c.proyecto_id is null)
       and (c.closer_email is null or lower(c.closer_email) = v_yo)
     order by (c.closer_email is not null) desc, (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
     limit 1;
    if found and not (v_c.id = any(v_vistas)) then
      v_vistas := v_vistas || v_c.id;
      return query select 'estandar'::text, null::text, false, v_c.proyecto_id, 'estandar'::text, v_c.pct_comision,
                          v_c.base_calculo, v_c.importe_fijo, v_c.closer_email is not null, v_c.vigente_desde;
    end if;
  end loop;
end $$;
revoke all on function public.mi_condicion_comision() from public, anon;
grant execute on function public.mi_condicion_comision() to authenticated;
drop function public._condicion_ventas_afectadas(uuid, uuid, text, text, date, date, text);

-- ================================================================= migracion 1 (columnas, copias, indices)
alter table public.equipo_miembros disable trigger trg_equipo_miembros_congela, disable trigger trg_equipo_miembros_recongela;
delete from public.equipos_venta where empresa = 'sandal_woods';          -- arrastra miembros, plantilla, condiciones y tramos de las copias (ON DELETE CASCADE)
delete from public.condiciones_comision where empresa = 'sandal_woods';   -- las estandar copiadas (sin equipo)
delete from public.comision_admin_tarifas where empresa = 'sandal_woods';
alter table public.equipo_miembros enable trigger trg_equipo_miembros_congela, enable trigger trg_equipo_miembros_recongela;
set constraints all immediate;   -- los borrados dejan comprobaciones diferidas pendientes y sin esto no se pueden recrear los indices

drop trigger if exists trg_equipo_miembros_empresa on public.equipo_miembros;
drop trigger if exists trg_equipos_venta_empresa_fija on public.equipos_venta;
drop trigger if exists trg_condicion_empresa on public.condiciones_comision;
drop function if exists public._trg_equipo_miembro_empresa();
drop function if exists public._trg_equipo_empresa_fija();
drop function if exists public._trg_condicion_empresa();

drop index if exists public.equipo_miembros_un_equipo_activo;
create unique index equipo_miembros_un_equipo_activo on public.equipo_miembros (lower(closer_email)) where hasta is null;
drop index if exists public.condiciones_comision_estandar_unica;
create unique index condiciones_comision_estandar_unica on public.condiciones_comision
  (coalesce(proyecto_id, '00000000-0000-0000-0000-000000000000'::uuid), coalesce(lower(closer_email), ''::text))
  where equipo_id is null and activo and vigente_hasta is null;
alter table public.comision_admin_tarifas drop constraint if exists comision_admin_tarifas_empresa_desde_key;
alter table public.comision_admin_tarifas add constraint comision_admin_tarifas_efectivo_desde_key unique (efectivo_desde);

drop function if exists public.empresa_de_sociedad(text);
drop function if exists public.puede_reparto_de(text);
drop function if exists public.empresa_de_equipo(uuid);
drop function if exists public._empresa_de_contrato_int(uuid);
drop function if exists public._empresa_de_proyecto_int(uuid);

alter table public.equipos_venta drop column if exists empresa;
alter table public.equipo_miembros drop column if exists empresa;
alter table public.condiciones_comision drop column if exists empresa;
alter table public.comision_admin_tarifas drop column if exists empresa;

commit;
