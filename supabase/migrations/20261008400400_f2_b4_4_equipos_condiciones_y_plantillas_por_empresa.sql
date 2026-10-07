-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · bloque 4 · migracion 4 (8-oct-2026): EQUIPOS DE VENTA, MIEMBROS, PLANTILLAS Y CONDICIONES DE COMISION GESTIONADOS POR LA EMPRESA DE CADA UNO.
--   * La empresa de un equipo, de un miembro, de una plantilla y de una condicion sale SIEMPRE del servidor (el equipo la guarda; la condicion la de su equipo o
--     proyecto). admin_empresa gestiona los de su empresa (incluido borrar/cerrar); super_admin_empresa lo mismo; admin/super globales, todo, como antes.
--   * Quien tiene `empresas` marcadas en Usuarios solo puede ser MIEMBRO o MANAGER de un equipo de una de ellas (regla 4 del encargo); «ya esta en un equipo» se mide
--     por empresa (una persona puede estar en un equipo de lawang y en el gemelo de sandal_woods).
--   * condicion_comision_guarda: lo que ya hacia pasa a `_condicion_comision_guarda_en(..., p_empresa)`; la publica sigue con la MISMA firma y deduce la empresa de
--     equipo/proyecto; una condicion estandar (sin equipo ni proyecto) y sin empresa pedida se crea para TODAS las empresas que el llamador gobierna
--     (como hoy, que una estandar valia para todo). Cerrar el periodo anterior y comprobar solapes se hace DENTRO de la empresa.
--   * equipo_venta_guarda: el equipo nuevo nace en la unica empresa del llamador si solo tiene una; si no (global o varias), en lawang hasta que la pantalla ofrezca elegir.
--   * Se retiran las versiones viejas `_condicion_es_mia(2 args)`, `_condicion_ventas_afectadas(6 args)` y `_equipo_candidato_valido(1 arg)`: nadie las llama ya (comprobado en el propio script).
--   * Policies de lectura de equipos_venta, equipo_miembros y condiciones_comision: es_admin() -> es_admin_de(empresa de la fila). Las de condicion_tramos y
--     plantilla_reparto cuelgan de la condicion/equipo y no cambian.
-- destructivo-ok: create or replace de ~20 funciones por parche con marca (cada marca debe salir las veces esperadas o aborta), 4 funciones nuevas, drop de 3 funciones sin llamadores (comprobado), alter policy; sin DDL que destruya datos
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

-- ---------------------------------------------------------------- 1. puertas nuevas (reemplazan a las de 2 y 6 argumentos)
create function public._condicion_es_mia(p_nivel text, p_equipo uuid, p_empresa text) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.puede_reparto_de(p_empresa)
      or (p_nivel in ('closer', 'setter', 'team_lead') and p_equipo is not null and public.es_manager_de_equipo(p_equipo))
$$;
revoke all on function public._condicion_es_mia(text, uuid, text) from public, anon, authenticated, lw_lector;

select pg_temp.parchea('public._equipo_candidato_valido(text)'::regprocedure, array[
  $o$CREATE OR REPLACE FUNCTION public._equipo_candidato_valido(p_email text)$o$,
  $n$CREATE OR REPLACE FUNCTION public._equipo_candidato_valido(p_email text, p_empresa text)$n$, '1',
  $o$v_rol in ('sales_manager', 'admin', 'super_admin', 'project_manager')$o$,
  $n$v_rol in ('sales_manager', 'admin', 'super_admin', 'project_manager', 'admin_empresa', 'super_admin_empresa')$n$, '1',
  $o$where lower(ev.manager_email) = v_e)$o$,
  $n$where lower(ev.manager_email) = v_e and (p_empresa is null or ev.empresa = p_empresa))$n$, '1',
  $o$where lower(em.closer_email) = v_e and (em.hasta is null or em.hasta >= v_hoy))$o$,
  $n$where lower(em.closer_email) = v_e and (em.hasta is null or em.hasta >= v_hoy) and (p_empresa is null or em.empresa = p_empresa))$n$, '1',
  $o$return null;$o$,
  $n$if p_empresa is not null and exists (select 1 from public.usuarios u where lower(u.email) = v_e and u.activo
                                           and cardinality(coalesce(u.empresas, '{}')) > 0 and not (p_empresa = any (u.empresas))) then
    return 'Esa persona no vende en la empresa de este equipo';
  end if;
  return null;$n$, '1']);
revoke all on function public._equipo_candidato_valido(text, text) from public, anon, authenticated, lw_lector;

-- ---------------------------------------------------------------- 2. miembros
select pg_temp.parchea('public.equipo_candidatos_sm(uuid)'::regprocedure, array[
  $o$public.es_admin() or public.es_manager_de_equipo(p_equipo)$o$,
  $n$public.es_admin_de(public.empresa_de_equipo(p_equipo)) or public.es_manager_de_equipo(p_equipo)$n$, '1',
  $o$public._equipo_candidato_valido(u.email) is null$o$,
  $n$public._equipo_candidato_valido(u.email, public.empresa_de_equipo(p_equipo)) is null$n$, '1']);
select pg_temp.parchea('public._equipo_miembro_guarda_con(uuid,uuid,text,date,date,integer)'::regprocedure, array[
  $o$if public.es_admin() then$o$,
  $n$if public.es_admin_de(public.empresa_de_equipo(p_equipo)) then$n$, '1',
  $o$and not public.es_super_admin() then$o$,
  $n$and not public.es_super_admin_de(public.empresa_de_equipo(p_equipo)) then$n$, '1',
  $o$public._equipo_candidato_valido(v_email) is not null$o$,
  $n$public._equipo_candidato_valido(v_email, public.empresa_de_equipo(p_equipo)) is not null$n$, '1']);
select pg_temp.parchea('public._equipo_miembro_mueve(uuid,uuid,text,date,date,boolean,integer,boolean,boolean)'::regprocedure, array[
  $o$if not found then raise exception 'Ese miembro no existe' using errcode = 'P0002'; end if;$o$,
  $n$if not found then raise exception 'Ese miembro no existe' using errcode = 'P0002'; end if;
    -- mover o editar una fila ya existente exige gobernar tambien la empresa DE ORIGEN (no se roba un miembro a la otra empresa)
    if not public.es_admin_de(public.empresa_de_equipo(v_old.equipo_id)) then
      raise exception 'Ese miembro es de un equipo de otra empresa' using errcode = '42501';
    end if;$n$, '1',
  $o$perform pg_advisory_xact_lock(hashtext(v_email));$o$,
  $n$if exists (select 1 from public.usuarios u where lower(u.email) = v_email and u.activo and cardinality(coalesce(u.empresas, '{}')) > 0
                 and not ((select e.empresa from public.equipos_venta e where e.id = p_equipo) = any (u.empresas))) then
    raise exception 'Esa persona no vende en la empresa de este equipo' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtext(v_email));$n$, '1',
  $o$and (p_id is null or em.id <> p_id)$o$,
  $n$and (p_id is null or em.id <> p_id)
     and em.empresa = (select e.empresa from public.equipos_venta e where e.id = p_equipo)$n$, '1']);
select pg_temp.parchea('public.equipo_miembro_anade(uuid,uuid)'::regprocedure, array[
  $o$if not public.es_admin() and ($o$,
  $n$if not public.es_admin_de(public.empresa_de_equipo(p_equipo)) and ($n$, '1',
  $o$if public.es_admin() then$o$,
  $n$if public.es_admin_de(public.empresa_de_equipo(p_equipo)) then$n$, '1']);
select pg_temp.parchea('public.equipo_miembro_baja(uuid,date)'::regprocedure, array[
  $o$v_admin boolean := public.es_admin();$o$,
  $n$v_admin boolean;$n$, '1',
  $o$if not found then raise exception 'Ese miembro no existe' using errcode = 'P0002'; end if;$o$,
  $n$if not found then raise exception 'Ese miembro no existe' using errcode = 'P0002'; end if;
  v_admin := public.es_admin_de(public.empresa_de_equipo(v_old.equipo_id));$n$, '1']);
select pg_temp.parchea('public.equipo_miembro_guarda(uuid,uuid,text,date,date)'::regprocedure, array[
  $o$if not public.es_admin() then$o$,
  $n$if not public.es_admin_de(public.empresa_de_equipo(p_equipo)) then$n$, '1']);
select pg_temp.parchea('public.equipo_miembro_guarda_confirmada(uuid,uuid,text,date,date,integer)'::regprocedure, array[
  $o$if not public.es_admin() then$o$,
  $n$if not public.es_admin_de(public.empresa_de_equipo(p_equipo)) then$n$, '1']);
select pg_temp.parchea('public.equipo_miembro_rol(uuid,text,text)'::regprocedure, array[
  $o$public.es_admin() or public.es_manager_de_equipo(v_old.equipo_id)$o$,
  $n$public.es_admin_de(public.empresa_de_equipo(v_old.equipo_id)) or public.es_manager_de_equipo(v_old.equipo_id)$n$, '1']);
select pg_temp.parchea('public.equipo_miembro_vista_previa(uuid,uuid,text,date,date)'::regprocedure, array[
  $o$if not public.es_admin() then$o$,
  $n$if not public.es_admin_de(public.empresa_de_equipo(p_equipo)) then$n$, '1']);

-- ---------------------------------------------------------------- 3. equipos y plantilla
select pg_temp.parchea('public.equipo_venta_activa(uuid,boolean)'::regprocedure, array[
  $o$if not public.es_admin() then$o$,
  $n$if not public.es_admin_de(public.empresa_de_equipo(p_id)) then$n$, '1']);
select pg_temp.parchea('public.equipo_closers_ven_comision(uuid,boolean)'::regprocedure, array[
  $o$public.es_admin() or public.es_manager_de_equipo(p_equipo)$o$,
  $n$public.es_admin_de(v_old.empresa) or public.es_manager_de_equipo(p_equipo)$n$, '1']);
select pg_temp.parchea('public.equipo_venta_guarda(uuid,text,text)'::regprocedure, array[
  $o$v_nom text := nullif(btrim(coalesce(p_nombre, '')), '');$o$,
  $n$v_nom text := nullif(btrim(coalesce(p_nombre, '')), '');
  v_emp text;$n$, '1',
  $o$if not public.es_admin() then raise exception 'Los equipos de venta los gestiona administración' using errcode = '42501'; end if;$o$,
  $n$-- la empresa del equipo: la suya si se edita; si es nuevo, la UNICA del llamador si solo tiene una; si no, lawang (la pantalla aun no deja elegir)
  v_emp := coalesce(public.empresa_de_equipo(p_id),
                    (select u.empresas[1] from public.usuarios u where u.user_id = (select auth.uid()) and u.activo and cardinality(coalesce(u.empresas, '{}')) = 1),
                    'lawang');
  if not public.es_admin_de(v_emp) then raise exception 'Los equipos de venta los gestiona administración' using errcode = '42501'; end if;
  if v_man is not null and exists (select 1 from public.usuarios u where lower(u.email) = v_man and u.activo
                                    and cardinality(coalesce(u.empresas, '{}')) > 0 and not (v_emp = any (u.empresas))) then
    raise exception 'El manager no vende en la empresa de este equipo' using errcode = '22023';
  end if;$n$, '1',
  $o$and not public.es_super_admin() then$o$,
  $n$and not public.es_super_admin_de(v_emp) then$n$, '1',
  $o$insert into public.equipos_venta (nombre, manager_email) values (v_nom, v_man) returning id into v_id;$o$,
  $n$insert into public.equipos_venta (nombre, manager_email, empresa) values (v_nom, v_man, v_emp) returning id into v_id;$n$, '1']);
select pg_temp.parchea('public.plantilla_reparto_guarda(uuid,jsonb)'::regprocedure, array[
  $o$public.es_admin() or public.es_manager_de_equipo(p_equipo)$o$,
  $n$public.es_admin_de(public.empresa_de_equipo(p_equipo)) or public.es_manager_de_equipo(p_equipo)$n$, '1']);
select pg_temp.parchea('public.plantilla_reparto_lee(uuid)'::regprocedure, array[
  $o$public.es_admin() or public.es_manager_de_equipo(p_equipo)$o$,
  $n$public.es_admin_de(public.empresa_de_equipo(p_equipo)) or public.es_manager_de_equipo(p_equipo)$n$, '1']);

-- ---------------------------------------------------------------- 4. condiciones
-- 4a. la funcion que guarda, con empresa explicita (interna) ...
select pg_temp.parchea('public.condicion_comision_guarda(uuid,jsonb,jsonb,text)'::regprocedure, array[
  $o$CREATE OR REPLACE FUNCTION public.condicion_comision_guarda(p_id uuid, p_cond jsonb, p_tramos jsonb, p_motivo text DEFAULT NULL::text)$o$,
  $n$CREATE OR REPLACE FUNCTION public._condicion_comision_guarda_en(p_id uuid, p_cond jsonb, p_tramos jsonb, p_motivo text, p_empresa text)$n$, '1',
  $o$boolean := public.es_admin() and public.puede('comisiones_reparto');$o$,
  $n$boolean;
  v_emp    text;$n$, '1',
  $o$if not public._condicion_es_mia(v_nivel, v_equipo) then$o$,
  $n$v_emp := coalesce(public.empresa_de_equipo(v_equipo), public._empresa_de_proyecto_int(v_proy), p_empresa);
    if v_emp is null then
      raise exception 'Falta la empresa de la condición (o el proyecto no tiene empresa)' using errcode = '22023';
    end if;
    v_admin := public.puede_reparto_de(v_emp);
    if not public._condicion_es_mia(v_nivel, v_equipo, v_emp) then$n$, '1',
  $o$if not found or not public._condicion_es_mia(v_old.nivel, v_old.equipo_id) then$o$,
  $n$v_emp := v_old.empresa;
  v_admin := public.puede_reparto_de(v_emp);
  if not found or not public._condicion_es_mia(v_old.nivel, v_old.equipo_id, v_old.empresa) then$n$, '1',
  $o$if not public.es_super_admin() and public._condicion_a_su_favor($o$,
  $n$if not public.es_super_admin_de(v_emp) and public._condicion_a_su_favor($n$, '2',
  $o$where c.equipo_id is not distinct from v_equipo and c.proyecto_id is not distinct from v_proy$o$,
  $n$where c.equipo_id is not distinct from v_equipo and c.proyecto_id is not distinct from v_proy and c.empresa = v_emp$n$, '1',
  $o$importe_fijo, vigente_desde, created_by, sustituye_a)$o$,
  $n$importe_fijo, vigente_desde, created_by, sustituye_a, empresa)$n$, '1',
  $o$v_fijo, v_desde, (select auth.email()), v_sust)$o$,
  $n$v_fijo, v_desde, (select auth.email()), v_sust, v_emp)$n$, '1',
  $o$public._condicion_ventas_afectadas(v_equipo, v_proy, v_nivel, v_closer, v_desde, v_hoy);$o$,
  $n$public._condicion_ventas_afectadas(v_equipo, v_proy, v_nivel, v_closer, v_desde, v_hoy, v_emp);$n$, '1',
  $o$coalesce(v_old.vigente_hasta, v_hoy));$o$,
  $n$coalesce(v_old.vigente_hasta, v_hoy), v_old.empresa);$n$, '1',
  $o$v_old.nivel, v_old.closer_email, v_d1, v_d2);$o$,
  $n$v_old.nivel, v_old.closer_email, v_d1, v_d2, v_old.empresa);$n$, '1']);
revoke all on function public._condicion_comision_guarda_en(uuid, jsonb, jsonb, text, text) from public, anon, authenticated, lw_lector;

-- 4b. ... y la publica, con la MISMA firma de siempre
create or replace function public.condicion_comision_guarda(p_id uuid, p_cond jsonb, p_tramos jsonb, p_motivo text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_equipo uuid := nullif(p_cond->>'equipo_id', '')::uuid;
  v_proy   uuid := nullif(p_cond->>'proyecto_id', '')::uuid;
  v_pedida text := nullif(btrim(coalesce(p_cond->>'empresa', '')), '');
  v_id uuid; v_primero uuid; e record;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  -- editar: la empresa es la de la condicion (la deduce la interna de la fila)
  if p_id is not null then
    return public._condicion_comision_guarda_en(p_id, p_cond, p_tramos, p_motivo, null);
  end if;
  -- con equipo, con proyecto o con empresa pedida: una sola condicion (la empresa sale de ellos o se valida la pedida)
  if v_equipo is not null or v_proy is not null or v_pedida is not null then
    return public._condicion_comision_guarda_en(null, p_cond, p_tramos, p_motivo, v_pedida);
  end if;
  -- estandar sin proyecto ni empresa: vale para TODAS las empresas que el llamador gobierna (como hoy, que valia para todo)
  for e in select em.clave from public.empresas em where em.activa order by em.orden loop
    if public.es_admin_de(e.clave) then
      v_id := public._condicion_comision_guarda_en(null, p_cond, p_tramos, p_motivo, e.clave);
      v_primero := coalesce(v_primero, v_id);
    end if;
  end loop;
  if v_primero is null then
    raise exception 'Solo puedes crear condiciones para los closers, setters o team leads de tu equipo' using errcode = '42501';
  end if;
  return v_primero;
end $$;

-- 4c. cerrar y borrar
select pg_temp.parchea('public.condicion_comision_activa(uuid,boolean)'::regprocedure, array[
  $o$public._condicion_es_mia(v_old.nivel, v_old.equipo_id)$o$,
  $n$public._condicion_es_mia(v_old.nivel, v_old.equipo_id, v_old.empresa)$n$, '1',
  $o$if not public.es_super_admin() and public._condicion_a_su_favor($o$,
  $n$if not public.es_super_admin_de(v_old.empresa) and public._condicion_a_su_favor($n$, '1']);
select pg_temp.parchea('public.condicion_comision_borra(uuid)'::regprocedure, array[
  $o$public._condicion_es_mia(v_old.nivel, v_old.equipo_id)$o$,
  $n$public._condicion_es_mia(v_old.nivel, v_old.equipo_id, v_old.empresa)$n$, '1',
  $o$if not public.es_super_admin() and public._condicion_a_su_favor($o$,
  $n$if not public.es_super_admin_de(v_old.empresa) and public._condicion_a_su_favor($n$, '1']);
select pg_temp.parchea('public._trg_condicion_comision_manager()'::regprocedure, array[
  $o$or public.es_admin() then$o$,
  $n$or public.es_admin_de(case when tg_op = 'DELETE' then old.empresa else new.empresa end) then$n$, '1']);

-- ---------------------------------------------------------------- 5. retirar las versiones viejas (solo si nadie las llama)
do $retira$
declare r record; n int := 0;
begin
  for r in select p.proname, p.oid from pg_proc p
            where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
              and p.oid not in ('public._condicion_es_mia(text,uuid)'::regprocedure, 'public._condicion_ventas_afectadas(uuid,uuid,text,text,date,date)'::regprocedure,
                                'public._equipo_candidato_valido(text)'::regprocedure)
              and (pg_get_functiondef(p.oid) ~ '_condicion_es_mia\([^,()]+,[^,()]+\)'
                or pg_get_functiondef(p.oid) ~ '_equipo_candidato_valido\([^,()]+\)'
                or pg_get_functiondef(p.oid) ~ '_condicion_ventas_afectadas\(([^,()]+,){5}[^,()]+\)')
  loop
    raise exception 'La funcion % aun llama a una version vieja (de 2/1/6 argumentos): no se retira', r.proname;
  end loop;
  drop function public._condicion_es_mia(text, uuid);
  drop function public._condicion_ventas_afectadas(uuid, uuid, text, text, date, date);
  drop function public._equipo_candidato_valido(text);
end $retira$;

-- ---------------------------------------------------------------- 6. policies de lectura
alter policy "equipos_venta: leer" on public.equipos_venta
  using (public.es_admin_de(empresa)
         or lower(manager_email) = lower(coalesce((select auth.email()), ''))
         or exists (select 1 from public.equipo_miembros em
                     where em.equipo_id = equipos_venta.id and lower(em.closer_email) = lower(coalesce((select auth.email()), ''))));
alter policy "equipo_miembros: leer" on public.equipo_miembros
  using (public.es_admin_de(empresa)
         or lower(closer_email) = lower(coalesce((select auth.email()), ''))
         or public.es_manager_de_equipo(equipo_id));
alter policy "condiciones_comision: leer" on public.condiciones_comision
  using (public.es_admin_de(empresa)
         or (nivel = any (array['closer', 'setter', 'team_lead'])
             and lower(coalesce(closer_email, '')) = lower(coalesce((select auth.email()), '-'))
             and (equipo_id is null or coalesce((select ev.closers_ven_comision from public.equipos_venta ev where ev.id = condiciones_comision.equipo_id), false)))
         or (nivel = 'manager'
             and exists (select 1 from public.equipos_venta ev
                          where ev.id = condiciones_comision.equipo_id and lower(ev.manager_email) = lower(coalesce((select auth.email()), '-')))));
