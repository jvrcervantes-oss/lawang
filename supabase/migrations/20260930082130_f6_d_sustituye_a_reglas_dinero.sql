-- F6 · cuarta parte (arreglos pedidos por el revisor, 30-sep-2026)
--
-- 1. La sustitución de condiciones deja de deducirse del log. Antes, _condicion_predecesora buscaba
--    «cerrada por una condición nueva» en el ÚLTIMO log de la anterior: editar la anterior (log con motivo
--    nulo) rompía la pista, y el ajuste solo se hacía si la sustituta era futura. Ahora hay una columna
--    explícita, condiciones_comision.sustituye_a, que rellena el servidor al crear la condición que cierra otra.
--    Relleno: la estándar 10 % (desde 30-sep) sustituye a la 2,5 % (cerrada el 29-sep). Esa pareja la
--    detección vieja NO la habría reconocido nunca: la 2,5 % sigue con activo=true y su último log es el
--    motivo del owner, no «cerrada por una condición nueva».
-- 2. Borrar una sustituta reabre la anterior con la fecha de fin y el «activo» que tenía la borrada
--    (con A→B→C, borrar B deja A cerrada el día antes de C y C pasa a sustituir a A).
-- 3. Reglas de dinero (Administración):
--    (a) las cifras (%, base, importe fijo, tramos) de una condición CERRADA no se editan: se crea una nueva.
--        Cerrada = tiene fecha de fin y, o esa fecha ya pasó, o nadie la sustituye (cierre a mano).
--        La que tiene una sustituta futura sigue vigente hasta el día antes.
--    (b) una fecha de inicio en el pasado (alta, o mover una sustituta) cambia de condición a ventas ya
--        hechas sin comisión devengada: el servidor las cuenta y exige confirmar ese número exacto
--        (p_cond.confirmar_ventas), como las altas retroactivas de miembros. Sigue sin poder cerrarse la
--        anterior antes de la venta más reciente que ya devengó con ella.
-- 6. El candidato a un equipo no puede ser project_manager; el buscador del SM ya no recibe emails enteros.

-- ───────────────────────────── 1. columna explícita ─────────────────────────────
alter table public.condiciones_comision add column if not exists sustituye_a uuid;
alter table public.condiciones_comision add constraint condiciones_comision_sustituye_a_fkey
  foreign key (sustituye_a) references public.condiciones_comision(id) deferrable initially deferred;
-- una condición la sustituye como mucho otra (NULL se repite sin problema)
alter table public.condiciones_comision add constraint condiciones_comision_sustituye_a_unica
  unique (sustituye_a) deferrable initially deferred;
alter table public.condiciones_comision add constraint condiciones_comision_sustituye_a_no_si_misma
  check (sustituye_a is distinct from id);
comment on column public.condiciones_comision.sustituye_a is
  'La condición del mismo alcance que ésta cerró al crearse (vigente_hasta = esta.vigente_desde - 1). La rellena condicion_comision_guarda; nunca el navegador.';

-- relleno: misma pareja que dejaría hoy el servidor (mismo alcance, la anterior acaba justo el día antes)
update public.condiciones_comision c
   set sustituye_a = p.id
  from public.condiciones_comision p
 where c.sustituye_a is null
   and p.id <> c.id
   and p.equipo_id is not distinct from c.equipo_id
   and p.proyecto_id is not distinct from c.proyecto_id
   and p.nivel = c.nivel
   and lower(coalesce(p.closer_email, '')) = lower(coalesce(c.closer_email, ''))
   and p.vigente_hasta = c.vigente_desde - 1;

-- compatibilidad de firma: ahora lee la columna (los demás parámetros ya no deciden nada)
create or replace function public._condicion_predecesora(p_equipo uuid, p_proy uuid, p_nivel text, p_closer text, p_desde date, p_excluye uuid)
 returns uuid
 language sql
 stable
 security definer
 set search_path to ''
as $function$
  select s.sustituye_a from public.condiciones_comision s where s.id = p_excluye
$function$;
revoke all on function public._condicion_predecesora(uuid, uuid, text, text, date, uuid) from public, anon, authenticated;

-- ¿cerrada? (regla 3a) — la misma definición que pinta /condiciones/
create or replace function public._condicion_cerrada(p_cond uuid)
 returns boolean
 language sql
 stable
 security definer
 set search_path to ''
as $function$
  select c.vigente_hasta is not null
     and (c.vigente_hasta < (now() at time zone 'Asia/Makassar')::date
          or not exists (select 1 from public.condiciones_comision s where s.sustituye_a = c.id))
    from public.condiciones_comision c where c.id = p_cond
$function$;
revoke all on function public._condicion_cerrada(uuid) from public, anon, authenticated;

-- ventas YA HECHAS (fecha de venta entre p_d1 y min(p_d2, hoy)) del alcance de una condición que aún no
-- han devengado en ese nivel: son las que cambiarían de condición si su frontera se mueve a esas fechas.
-- Mismo ancla de fecha y mismo equipo congelado que el motor (comisiones_evaluar_contrato).
create or replace function public._condicion_ventas_afectadas(p_equipo uuid, p_proy uuid, p_nivel text, p_closer text, p_d1 date, p_d2 date)
 returns integer
 language sql
 stable
 security definer
 set search_path to ''
as $function$
  select count(*)::int
    from public.contrato_closer k
    join public.contratos c on c.id = k.contrato_id
   where p_d1 is not null and p_d2 is not null
     and coalesce(k.fecha_venta, (c.created_at at time zone 'Asia/Makassar')::date)
         between p_d1 and least(p_d2, (now() at time zone 'Asia/Makassar')::date)
     and (p_proy is null or c.proyecto_id = p_proy)
     and case when p_equipo is null then (k.equipo_id is null or k.modo = 'propia')
              else k.equipo_id = p_equipo and k.modo is distinct from 'propia' end
     and (p_closer is null
          or case when p_equipo is null or p_nivel = 'closer' then lower(k.closer_email) = lower(p_closer)
                  else exists (select 1 from public.contrato_roles_equipo re
                                where re.contrato_raiz_id = k.contrato_id and re.rol = p_nivel
                                  and lower(re.email) = lower(p_closer)) end)
     and not exists (select 1 from public.comisiones_devengadas d
                      where d.contrato_raiz_id = k.contrato_id and d.estado <> 'anulada'
                        and d.nivel = any (case when p_equipo is null then array['estandar', 'propia'] else array[p_nivel] end))
$function$;
revoke all on function public._condicion_ventas_afectadas(uuid, uuid, text, text, date, date) from public, anon, authenticated;

-- ───────────────────────────── 2. borrar una sustituta ─────────────────────────────
-- (sin condición de fecha: condicion_comision_borra ya solo deja borrar la que no ha empezado)
create or replace function public._trg_condicion_borrada_reabre()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  -- quien sustituía a la borrada pasa a sustituir a la que la borrada sustituía (A→B→C, borrar B = A→C)
  update public.condiciones_comision set sustituye_a = old.sustituye_a where sustituye_a = old.id;
  if old.sustituye_a is null then return null; end if;
  -- la anterior recupera el final y el estado que tenía la borrada: con C detrás, sigue cerrada el día antes de C
  update public.condiciones_comision
     set activo = old.activo, vigente_hasta = old.vigente_hasta
   where id = old.sustituye_a;
  if found then
    insert into public.condiciones_comision_log (condicion_id, antes, despues, motivo)
    values (old.sustituye_a, jsonb_build_object('vigente_hasta', old.vigente_desde - 1),
            jsonb_build_object('activo', old.activo, 'vigente_hasta', old.vigente_hasta),
            'reabierta: se borró la condición que la sustituía');
  end if;
  return null;
end $function$;
revoke all on function public._trg_condicion_borrada_reabre() from public, anon, authenticated;

-- ───────────────────────────── 3. guardar una condición ─────────────────────────────
create or replace function public.condicion_comision_guarda(p_id uuid, p_cond jsonb, p_tramos jsonb, p_motivo text DEFAULT NULL::text)
 returns uuid
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_old    public.condiciones_comision%rowtype;
  v_prev   public.condiciones_comision%rowtype;
  v_id     uuid;
  v_nivel  text;
  v_equipo uuid;
  v_proy   uuid;
  v_closer text := nullif(lower(btrim(coalesce(p_cond->>'closer_email', ''))), '');
  v_pct    numeric;
  v_base   text := p_cond->>'base_calculo';
  v_fijo   numeric;
  v_desde  date;
  v_admin  boolean := public.es_admin();
  v_n      int := 0;
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_hoy    date := (now() at time zone 'Asia/Makassar')::date;
  v_ult    date;
  v_pred   uuid;
  v_sust   uuid;
  v_conf   int;
  v_ventas int;
  v_d1     date;
  v_d2     date;
  v_cerrada boolean;
  v_tr_act jsonb;
  v_tr_new jsonb;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  begin
    v_pct   := (p_cond->>'pct_comision')::numeric;
    v_fijo  := case when v_base = 'importe_fijo' then (p_cond->>'importe_fijo')::numeric end;
    v_desde := coalesce(nullif(p_cond->>'vigente_desde', '')::date, v_hoy);
    v_conf  := nullif(p_cond->>'confirmar_ventas', '')::int;
  exception when others then
    raise exception 'Revisa las cifras: el %%, el importe fijo o la fecha no son válidos' using errcode = '22023';
  end;
  if v_pct is null or v_pct < 0 or v_pct > 100 then raise exception 'El %% de comisión va entre 0 y 100' using errcode = '22023'; end if;

  if p_id is null then
    v_equipo := nullif(p_cond->>'equipo_id', '')::uuid;
    v_proy   := nullif(p_cond->>'proyecto_id', '')::uuid;
    v_nivel  := case when v_equipo is null then 'closer' else coalesce(p_cond->>'nivel', 'closer') end;
    if not public._condicion_es_mia(v_nivel, v_equipo) then
      raise exception 'Solo puedes crear condiciones para los closers, setters o team leads de tu equipo' using errcode = '42501';
    end if;
    if not v_admin then
      if v_desde < v_hoy then raise exception 'La fecha no puede ser anterior a hoy.' using errcode = '22023'; end if;
      if v_closer is not null and not public._closer_del_equipo(v_equipo, v_closer) then
        raise exception 'Esa persona no está hoy en tu equipo' using errcode = '42501';
      end if;
    end if;
    if v_nivel not in ('closer', 'setter', 'team_lead') then v_closer := null; end if;

    -- 3b: con inicio en el pasado, cuántas ventas ya hechas sin devengar pasan a esta condición
    if v_desde < v_hoy then
      v_ventas := public._condicion_ventas_afectadas(v_equipo, v_proy, v_nivel, v_closer, v_desde, v_hoy);
      if v_ventas > 0 and v_conf is distinct from v_ventas then
        raise exception 'Con inicio el %, % venta(s) ya hechas y sin comisión devengada pasan a esta condición: confírmalo con ese número',
          to_char(v_desde, 'DD-MM-YYYY'), v_ventas
          using errcode = '22023', hint = 'lw-confirmar-ventas:' || v_ventas;
      end if;
    end if;

    -- una condición nueva CIERRA sola la anterior del mismo alcance (vigente_hasta = nueva.desde − 1) y
    -- queda apuntándola en sustituye_a; ANTES del insert, que el índice único solo mira las abiertas
    for v_prev in
      select * from public.condiciones_comision c
       where c.equipo_id is not distinct from v_equipo and c.proyecto_id is not distinct from v_proy
         and c.nivel = v_nivel and lower(coalesce(c.closer_email, '')) = coalesce(v_closer, '')
         and c.activo and c.vigente_hasta is null
       for update
    loop
      if v_desde - 1 < v_prev.vigente_desde then
        raise exception 'Ya hay una condición para ese mismo alcance desde el %: la nueva tiene que empezar después (o edita la que hay)',
          to_char(v_prev.vigente_desde, 'DD-MM-YYYY') using errcode = '23P01';
      end if;
      v_ult := public._condicion_ultima_venta_devengada(v_prev.id);
      if v_ult is not null and v_ult > v_desde - 1 then
        raise exception 'La condición que sustituyes ya ha cobrado comisión en una venta del %: la nueva tiene que empezar después de esa fecha',
          to_char(v_ult, 'DD-MM-YYYY') using errcode = '22023';
      end if;
      update public.condiciones_comision set activo = false, vigente_hasta = v_desde - 1 where id = v_prev.id;
      insert into public.condiciones_comision_log (condicion_id, antes, despues, motivo)
      values (v_prev.id, jsonb_build_object('activo', true, 'vigente_hasta', null),
              jsonb_build_object('activo', false, 'vigente_hasta', v_desde - 1), 'cerrada por una condición nueva');
      v_sust := v_prev.id;
    end loop;

    insert into public.condiciones_comision (equipo_id, proyecto_id, nivel, closer_email, pct_comision, base_calculo,
                                             importe_fijo, vigente_desde, created_by, sustituye_a)
    values (v_equipo, v_proy, v_nivel, v_closer, v_pct, v_base, v_fijo, v_desde, (select auth.email()), v_sust)
    returning id into v_id;
    if public._condicion_solapa(v_id) is not null then
      raise exception 'Se pisa con una condición ya cerrada del mismo alcance: empieza la nueva después de su fecha de cierre' using errcode = '23P01';
    end if;
    perform public._condicion_tramos_pone(v_id, p_tramos);
    insert into public.condiciones_comision_log (condicion_id, antes, despues, motivo)
    select v_id, null, to_jsonb(c) || jsonb_build_object('ventas_confirmadas', v_ventas), v_motivo
      from public.condiciones_comision c where c.id = v_id;
    return v_id;
  end if;

  select * into v_old from public.condiciones_comision c where c.id = p_id for update;
  if not found or not public._condicion_es_mia(v_old.nivel, v_old.equipo_id) then
    raise exception 'No encuentro esa condición entre las tuyas' using errcode = '42501';
  end if;
  if v_old.vigente_hasta is not null and v_desde > v_old.vigente_hasta then
    raise exception 'Esta condición está cerrada el %: su inicio no puede ser posterior a su cierre', to_char(v_old.vigente_hasta, 'DD-MM-YYYY') using errcode = '22023';
  end if;

  -- 3a: las cifras de una condición cerrada no se tocan (tampoco sus tramos): se crea una nueva
  v_cerrada := public._condicion_cerrada(p_id);
  if v_cerrada then
    select coalesce(jsonb_agg(jsonb_build_array(t.disparador_tipo, t.umbral, t.pct_tramo) order by t.orden), '[]'::jsonb)
      into v_tr_act from public.condicion_tramos t where t.condicion_id = p_id;
    if p_tramos is null or jsonb_typeof(p_tramos) <> 'array' then
      v_tr_new := v_tr_act;
    else
      begin
        select coalesce(jsonb_agg(jsonb_build_array(x->>'disparador_tipo',
                 case when (x->>'disparador_tipo') like 'pct_cobrado_%' then (x->>'umbral')::numeric end,
                 (x->>'pct_tramo')::numeric) order by o), '[]'::jsonb)
          into v_tr_new from jsonb_array_elements(p_tramos) with ordinality y(x, o);
      exception when others then
        raise exception 'Revisa los tramos: alguna cifra no es válida' using errcode = '22023';
      end;
    end if;
    if v_pct is distinct from v_old.pct_comision or v_base is distinct from v_old.base_calculo
       or v_fijo is distinct from v_old.importe_fijo or v_tr_new is distinct from v_tr_act then
      raise exception 'Esta condición está cerrada desde el %: sus cifras no se cambian. Crea una nueva desde la fecha que toque.',
        to_char(v_old.vigente_hasta, 'DD-MM-YYYY') using errcode = '22023';
    end if;
  end if;

  select count(*) into v_n from public.comisiones_devengadas d where d.condicion_id = p_id;
  if v_n > 0 then
    if not v_admin then
      raise exception 'Esta condición ya ha generado comisiones: no se cambian sus cifras. Ciérrala y crea una nueva.' using errcode = '22023';
    end if;
    if v_motivo is null or length(v_motivo) < 10 then
      raise exception 'Esta condición ya ha generado comisiones: escribe por qué cambias sus cifras (queda registrado)' using errcode = '22023';
    end if;
    if v_desde > v_old.vigente_desde then
      raise exception 'Esta condición ya ha generado comisiones: su fecha de vigencia no se puede adelantar (dejaría sin cobrar los tramos pendientes de ventas ya empezadas)' using errcode = '22023';
    end if;
    if v_base is distinct from v_old.base_calculo then
      raise exception 'Esta condición ya ha generado comisiones: su base de cálculo no se cambia. Ciérrala y crea una nueva.' using errcode = '22023';
    end if;
  end if;
  if not v_admin then
    if v_desde is distinct from v_old.vigente_desde and v_desde < v_hoy then
      raise exception 'la fecha de vigencia no puede quedar en el pasado' using errcode = '22023';
    end if;
    if v_closer is not null and not public._closer_del_equipo(v_old.equipo_id, v_closer) then
      raise exception 'Esa persona no está hoy en tu equipo' using errcode = '42501';
    end if;
  end if;

  if v_desde is distinct from v_old.vigente_desde then
    -- 3b: la frontera se mueve entre la fecha vieja y la nueva; las ventas ya hechas de ese tramo cambian de condición
    v_d1 := least(v_desde, v_old.vigente_desde);
    v_d2 := greatest(v_desde, v_old.vigente_desde) - 1;
    if v_d1 <= v_hoy then
      v_ventas := public._condicion_ventas_afectadas(v_old.equipo_id, v_old.proyecto_id, v_old.nivel, v_old.closer_email, v_d1, v_d2);
      if v_ventas > 0 and v_conf is distinct from v_ventas then
        raise exception 'Mover el inicio al % cambia de condición % venta(s) ya hechas y sin comisión devengada: confírmalo con ese número',
          to_char(v_desde, 'DD-MM-YYYY'), v_ventas
          using errcode = '22023', hint = 'lw-confirmar-ventas:' || v_ventas;
      end if;
    end if;

    -- sustituta sin devengos que cambia de fecha (futura o ya empezada): la que ella cerró se cierra el día
    -- antes de la fecha nueva, para que no quede ni hueco ni solape
    v_pred := public._condicion_predecesora(v_old.equipo_id, v_old.proyecto_id, v_old.nivel, v_old.closer_email, v_old.vigente_desde, p_id);
    if v_pred is not null and v_n = 0 then
      select * into v_prev from public.condiciones_comision c where c.id = v_pred for update;
      if v_desde - 1 < v_prev.vigente_desde then
        raise exception 'Esta condición sustituye a otra que vale desde el %: tiene que empezar después',
          to_char(v_prev.vigente_desde, 'DD-MM-YYYY') using errcode = '23P01';
      end if;
      v_ult := public._condicion_ultima_venta_devengada(v_pred);
      if v_ult is not null and v_ult > v_desde - 1 then
        raise exception 'La condición a la que sustituye ya ha cobrado comisión en una venta del %: esta tiene que empezar después',
          to_char(v_ult, 'DD-MM-YYYY') using errcode = '22023';
      end if;
      update public.condiciones_comision set vigente_hasta = v_desde - 1 where id = v_pred;
      insert into public.condiciones_comision_log (condicion_id, antes, despues, motivo)
      values (v_pred, jsonb_build_object('vigente_hasta', v_prev.vigente_hasta), jsonb_build_object('vigente_hasta', v_desde - 1),
              'ajustada: su sustituta cambió de fecha');
    end if;
  end if;

  update public.condiciones_comision c
     set pct_comision = v_pct, base_calculo = v_base, importe_fijo = v_fijo, vigente_desde = v_desde,
         closer_email = case when c.nivel in ('closer', 'setter', 'team_lead') then v_closer else c.closer_email end
   where c.id = p_id;
  if public._condicion_solapa(p_id) is not null then
    raise exception 'Con esa fecha se pisa con otra condición del mismo alcance' using errcode = '23P01';
  end if;
  if v_n = 0 and not v_cerrada then
    perform public._condicion_tramos_pone(p_id, p_tramos);
  end if;
  insert into public.condiciones_comision_log (condicion_id, antes, despues, con_devengos, motivo)
  select p_id, to_jsonb(v_old),
         to_jsonb(c) || jsonb_build_object('ventas_con_devengos',
           (select count(distinct d.contrato_raiz_id) from public.comisiones_devengadas d where d.condicion_id = p_id),
           'ventas_confirmadas', v_ventas),
         v_n > 0, v_motivo
    from public.condiciones_comision c where c.id = p_id;
  return p_id;
end $function$;
revoke all on function public.condicion_comision_guarda(uuid, jsonb, jsonb, text) from public, anon;
grant execute on function public.condicion_comision_guarda(uuid, jsonb, jsonb, text) to authenticated;

-- ───────────────────────────── 6. candidatos de un equipo ─────────────────────────────
create or replace function public._equipo_candidato_valido(p_email text)
 returns text
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
declare v_e text := lower(btrim(coalesce(p_email, ''))); v_rol text; v_hoy date := (now() at time zone 'Asia/Makassar')::date;
begin
  select u.rol into v_rol from public.usuarios u where lower(u.email) = v_e and u.activo;
  if not found then return 'El miembro tiene que ser un usuario activo de la intranet'; end if;
  if v_e = lower(coalesce((select auth.email()), '')) then return 'Nadie se añade a sí mismo a un equipo'; end if;
  if v_rol in ('sales_manager', 'admin', 'super_admin', 'project_manager') then
    return 'A un sales manager, un project manager o a administración no se le mete en un equipo desde aquí: lo hace administración';
  end if;
  if exists (select 1 from public.equipos_venta ev where lower(ev.manager_email) = v_e) then
    return 'Esa persona dirige un equipo: no puede entrar en otro';
  end if;
  if exists (select 1 from public.equipo_miembros em where lower(em.closer_email) = v_e and (em.hasta is null or em.hasta >= v_hoy)) then
    return 'Esa persona ya está en un equipo: los traslados entre equipos los hace administración';
  end if;
  return null;
end $function$;
revoke all on function public._equipo_candidato_valido(text) from public, anon, authenticated;

-- el buscador del SM: solo lo necesario para elegir (nombre y email enmascarado) y el id con el que se
-- pide el alta; nunca gente con equipo (la filtra _equipo_candidato_valido)
create or replace function public.equipo_candidatos_sm(p_equipo uuid)
 returns table(usuario uuid, nombre text, email text)
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if p_equipo is null or not (public.es_admin() or public.es_manager_de_equipo(p_equipo)) then
    raise exception 'Solo el sales manager de este equipo o administración' using errcode = '42501';
  end if;
  return query
    select u.user_id,
           coalesce(nullif(btrim(u.nombre), ''), m.mascara),
           m.mascara
      from public.usuarios u
      cross join lateral (select left(split_part(lower(u.email), '@', 1), 1) || '***@' || split_part(lower(u.email), '@', 2) as mascara) m
     where u.activo and u.user_id is not null and public._equipo_candidato_valido(u.email) is null
     order by 2;
end $function$;
revoke all on function public.equipo_candidatos_sm(uuid) from public, anon;
grant execute on function public.equipo_candidatos_sm(uuid) to authenticated;

-- el alta del SM por id: el email lo pone el servidor (el navegador ya no lo conoce entero)
create or replace function public.equipo_miembro_anade(p_equipo uuid, p_usuario uuid)
 returns uuid
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_email text;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  select lower(u.email) into v_email from public.usuarios u where u.user_id = p_usuario and u.activo;
  if v_email is null then raise exception 'El miembro tiene que ser un usuario activo de la intranet' using errcode = '22023'; end if;
  return public._equipo_miembro_guarda_con(null, p_equipo, v_email, (now() at time zone 'Asia/Makassar')::date, null, null);
end $function$;
revoke all on function public.equipo_miembro_anade(uuid, uuid) from public, anon;
grant execute on function public.equipo_miembro_anade(uuid, uuid) to authenticated;

-- el buscador viejo devolvía emails enteros: sin llamador desde hoy, se cierra (quitarlo del todo queda
-- pendiente del OK del owner, que no_destruir.py para cualquier DDL que lo elimine)
revoke all on function public.equipo_candidatos(uuid) from public, anon, authenticated;
