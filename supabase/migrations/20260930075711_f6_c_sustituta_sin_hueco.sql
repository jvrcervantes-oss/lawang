-- F6 · tercera parte (hallazgos de code-review, 30-sep-2026): una condición futura que SUSTITUYE a otra
-- (la creó cerrando la anterior en su vigente_desde − 1) no puede dejar un hueco sin condición:
--   · si se borra, la anterior se reabre (vuelve a estar en vigor, como antes de crear la sustituta);
--   · si se le cambia la fecha, la anterior se cierra el día antes de la nueva fecha.
-- Sin esto, las ventas de ese hueco no encontraban condición y no cobraban, sin ningún aviso.
-- Solo cuenta como «sustituida» la que se cerró por una condición nueva (log), no la que se cerró a mano.

create or replace function public._condicion_predecesora(p_equipo uuid, p_proy uuid, p_nivel text, p_closer text, p_desde date, p_excluye uuid)
 returns uuid
 language sql
 stable
 security definer
 set search_path to ''
as $function$
  select c.id from public.condiciones_comision c
   where c.id is distinct from p_excluye
     and c.equipo_id is not distinct from p_equipo and c.proyecto_id is not distinct from p_proy
     and c.nivel = p_nivel and lower(coalesce(c.closer_email, '')) = lower(coalesce(p_closer, ''))
     and not c.activo and c.vigente_hasta = p_desde - 1
     and (select l.motivo from public.condiciones_comision_log l where l.condicion_id = c.id order by l.en desc limit 1)
         = 'cerrada por una condición nueva'
   limit 1
$function$;
revoke all on function public._condicion_predecesora(uuid, uuid, text, text, date, uuid) from public, anon, authenticated;

-- al borrar una condición que aún no había empezado, la que ella había cerrado vuelve a estar en vigor
create or replace function public._trg_condicion_borrada_reabre()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_pred uuid;
begin
  if old.vigente_desde <= (now() at time zone 'Asia/Makassar')::date then return null; end if;
  v_pred := public._condicion_predecesora(old.equipo_id, old.proyecto_id, old.nivel, old.closer_email, old.vigente_desde, old.id);
  if v_pred is null then return null; end if;
  update public.condiciones_comision set activo = true, vigente_hasta = null where id = v_pred;
  insert into public.condiciones_comision_log (condicion_id, antes, despues, motivo)
  values (v_pred, jsonb_build_object('activo', false, 'vigente_hasta', old.vigente_desde - 1),
          jsonb_build_object('activo', true, 'vigente_hasta', null), 'reabierta: se borró la condición que la sustituía');
  return null;
end $function$;
revoke all on function public._trg_condicion_borrada_reabre() from public, anon, authenticated;
create trigger trg_condicion_borrada_reabre after delete on public.condiciones_comision
  for each row execute function public._trg_condicion_borrada_reabre();

-- condicion_comision_guarda: igual que en 20260930070138 más el bloque de la sustituta que cambia de fecha
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
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  begin
    v_pct   := (p_cond->>'pct_comision')::numeric;
    v_fijo  := case when v_base = 'importe_fijo' then (p_cond->>'importe_fijo')::numeric end;
    v_desde := coalesce(nullif(p_cond->>'vigente_desde', '')::date, v_hoy);
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

    -- una condición nueva CIERRA sola la anterior del mismo alcance (vigente_hasta = nueva.desde − 1),
    -- o se rechaza si no cabe; ANTES del insert, que el índice único solo mira las abiertas
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
    end loop;

    insert into public.condiciones_comision (equipo_id, proyecto_id, nivel, closer_email, pct_comision, base_calculo,
                                             importe_fijo, vigente_desde, created_by)
    values (v_equipo, v_proy, v_nivel, v_closer, v_pct, v_base, v_fijo, v_desde, (select auth.email()))
    returning id into v_id;
    if public._condicion_solapa(v_id) is not null then
      raise exception 'Se pisa con una condición ya cerrada del mismo alcance: empieza la nueva después de su fecha de cierre' using errcode = '23P01';
    end if;
    perform public._condicion_tramos_pone(v_id, p_tramos);
    insert into public.condiciones_comision_log (condicion_id, antes, despues, motivo)
    select v_id, null, to_jsonb(c), v_motivo from public.condiciones_comision c where c.id = v_id;
    return v_id;
  end if;

  select * into v_old from public.condiciones_comision c where c.id = p_id for update;
  if not found or not public._condicion_es_mia(v_old.nivel, v_old.equipo_id) then
    raise exception 'No encuentro esa condición entre las tuyas' using errcode = '42501';
  end if;
  if v_old.vigente_hasta is not null and v_desde > v_old.vigente_hasta then
    raise exception 'Esta condición está cerrada el %: su inicio no puede ser posterior a su cierre', to_char(v_old.vigente_hasta, 'DD-MM-YYYY') using errcode = '22023';
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

  -- sustituta futura que cambia de fecha: la condición que ella cerró se cierra el día antes de la nueva fecha
  if v_desde is distinct from v_old.vigente_desde and v_old.vigente_desde > v_hoy then
    v_pred := public._condicion_predecesora(v_old.equipo_id, v_old.proyecto_id, v_old.nivel, v_old.closer_email, v_old.vigente_desde, p_id);
    if v_pred is not null then
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
              'cerrada por una condición nueva');
    end if;
  end if;

  update public.condiciones_comision c
     set pct_comision = v_pct, base_calculo = v_base, importe_fijo = v_fijo, vigente_desde = v_desde,
         closer_email = case when c.nivel in ('closer', 'setter', 'team_lead') then v_closer else c.closer_email end
   where c.id = p_id;
  if public._condicion_solapa(p_id) is not null then
    raise exception 'Con esa fecha se pisa con otra condición del mismo alcance' using errcode = '23P01';
  end if;
  if v_n = 0 then
    perform public._condicion_tramos_pone(p_id, p_tramos);
  end if;
  insert into public.condiciones_comision_log (condicion_id, antes, despues, con_devengos, motivo)
  select p_id, to_jsonb(v_old),
         to_jsonb(c) || jsonb_build_object('ventas_con_devengos',
           (select count(distinct d.contrato_raiz_id) from public.comisiones_devengadas d where d.condicion_id = p_id)),
         v_n > 0, v_motivo
    from public.condiciones_comision c where c.id = p_id;
  return p_id;
end $function$;
revoke all on function public.condicion_comision_guarda(uuid, jsonb, jsonb, text) from public, anon;
grant execute on function public.condicion_comision_guarda(uuid, jsonb, jsonb, text) to authenticated;