-- F6 · séptima parte (30-sep-2026, pedido por Administración): HOY CUENTA COMO PASADO a efectos de dinero.
--
-- «Desde hoy no cuenta las ventas de hoy» (COMMENT de 091729) no fue decisión del owner, fue una suposición. Una venta
-- hecha hoy ya está hecha: una condición nueva, o un cambio de cifras, con inicio hoy la cambia igual que una con
-- inicio ayer. Por eso, igual en alta y en edición:
-- 1. condicion_comision_guarda: el recuento de ventas afectadas se hace con inicio <= hoy (Bali), no < hoy.
--    · recuento > 0: administración confirma con ese número (hint lw-confirmar-ventas:N, como hasta ahora);
--      el Sales Manager recibe rechazo 42501 «empieza mañana o pide a administración», SIN hint (el navegador no
--      le ofrece un botón de confirmar que volvería a fallar) y aunque mande confirmar_ventas (lo manda el navegador).
--    · recuento 0: pasa sin confirmación, también para el SM.
--    · Se mantiene el bloqueo incondicional del SM sobre cifras de una condición en vigor desde ANTES de hoy.
--    · Mover el inicio a hoy (o de hoy a mañana) con ventas de hoy: mismo trato (admin confirma, SM rechazo).
-- 2. Mismo ancla de la fecha de venta que el motor (comisiones_evaluar_contrato), que evalúa en la RAÍZ:
--    coalesce(k.fecha_venta, (raíz.created_at at time zone 'Asia/Makassar')::date).
--    · _condicion_ventas_afectadas contaba también las filas de contrato_closer de contratos HIJOS (27 hoy, todas con
--      su raíz también presente): con la fecha de creación de la hija y sin devengo posible (los devengos van a la
--      raíz), así que salían siempre como «sin devengar». Ahora solo cuenta filas de raíz, como el motor.
--    · _trg_contrato_closer_fecha_venta fijaba fecha_venta con created_at::date en la zona de la sesión (UTC): una
--      venta creada entre las 00:00 y las 08:00 de Bali quedaba con el día anterior. Desde aquí, día de Bali.
--      La fila ya grabada con el día UTC (1 hoy) NO se corrige aquí: es dato de dinero y el trigger congela
--      fecha_venta en UPDATE; va a administración.
--    · _condicion_ultima_venta_devengada ya usaba el ancla de la raíz en Bali: no cambia.

create or replace function public._condicion_ventas_afectadas(p_equipo uuid, p_proy uuid, p_nivel text, p_closer text, p_d1 date, p_d2 date)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select count(*)::int
    from public.contrato_closer k
    join public.contratos c on c.id = k.contrato_id
   where p_d1 is not null and p_d2 is not null
     -- solo la raíz: el motor evalúa y devenga en la raíz (contrato_padre_id nulo) y su fecha es la de la raíz
     and c.contrato_padre_id is null
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
     and (
       -- sin ningún devengo de ese nivel
       not exists (select 1 from public.comisiones_devengadas d
                    where d.contrato_raiz_id = k.contrato_id and d.estado <> 'anulada'
                      and d.nivel = any (case when p_equipo is null then array['estandar', 'propia'] else array[p_nivel] end))
       -- o a medio devengar: algún tramo de la condición con la que empezó aún sin devengo
       or exists (select 1 from public.comisiones_devengadas d
                   where d.contrato_raiz_id = k.contrato_id and d.estado <> 'anulada'
                     and d.nivel = any (case when p_equipo is null then array['estandar', 'propia'] else array[p_nivel] end)
                     and exists (select 1 from public.condicion_tramos t
                                  where t.condicion_id = d.condicion_id
                                    and not exists (select 1 from public.comisiones_devengadas d2
                                                     where d2.contrato_raiz_id = k.contrato_id and d2.tramo_id = t.id
                                                       and d2.nivel = d.nivel and d2.estado <> 'anulada')))
     )
$function$;

create or replace function public._trg_contrato_closer_fecha_venta()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'UPDATE' then
    new.fecha_venta := old.fecha_venta;
    return new;
  end if;
  -- día de Bali, el mismo que usan el motor y las guardas (antes: created_at::date en UTC)
  select case when c.created_at >= '2026-09-24' then (c.created_at at time zone 'Asia/Makassar')::date end
    into new.fecha_venta
    from public.contratos c where c.id = new.contrato_id;
  return new;
end $function$;

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
  v_cifras boolean;
  v_closer_nuevo text;
  v_alcance boolean;
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

    -- 3b: con inicio hoy o en el pasado (hoy cuenta como pasado), cuántas ventas ya hechas (sin devengar o a medio
    -- devengar) pueden pasar a esta condición. El SM no las mueve (ni confirmando); administración confirma el número.
    if v_desde <= v_hoy then
      v_ventas := public._condicion_ventas_afectadas(v_equipo, v_proy, v_nivel, v_closer, v_desde, v_hoy);
      if v_ventas > 0 and not v_admin then
        raise exception 'Con inicio hoy, % venta(s) ya hechas hoy y sin comisión completa pasarían a esta condición: empieza mañana o pide a administración',
          v_ventas using errcode = '42501';
      end if;
      if v_ventas > 0 and v_conf is distinct from v_ventas then
        raise exception 'Con inicio el %, hasta % venta(s) ya hechas y sin comisión completa pueden pasar a esta condición: confírmalo con ese número',
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
    select v_id, null, to_jsonb(c) || jsonb_build_object('ventas_max', v_ventas), v_motivo
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

  select count(*) into v_n from public.comisiones_devengadas d where d.condicion_id = p_id;
  v_cerrada := public._condicion_cerrada(p_id);

  -- ALCANCE (a quién se aplica: «todo el equipo» o una persona) = identidad de la condición, como equipo,
  -- proyecto y nivel, que ya no se editan. Cambiarlo en una condición empezada o cerrada cambia qué ventas
  -- ya hechas cobran con ella sin recuento, y en una sustituta deja al resto del alcance sin condición.
  -- Solo se cambia en una condición FUTURA (hoy Bali < inicio viejo y nuevo), sin devengos, que no sustituye
  -- a otra ni la sustituye ninguna y sin cierre. Por eso los recuentos de abajo pueden usar v_old.closer_email.
  v_closer_nuevo := case when v_old.nivel in ('closer', 'setter', 'team_lead') then v_closer else v_old.closer_email end;
  v_alcance := lower(coalesce(v_closer_nuevo, '')) is distinct from lower(coalesce(v_old.closer_email, ''));
  if v_alcance and not (v_old.vigente_desde > v_hoy and v_desde > v_hoy and v_n = 0
                        and v_old.sustituye_a is null and v_old.vigente_hasta is null
                        and not exists (select 1 from public.condiciones_comision s where s.sustituye_a = p_id)) then
    raise exception 'Para cambiar a quién se aplica, crea una condición nueva desde hoy' using errcode = '22023';
  end if;

  -- ¿cambian las cifras? (%, base, importe fijo o tramos; los tramos solo cuentan donde de verdad se guardan:
  -- sin devengos y sin cerrar, o cerrada, que es donde 3a los prohíbe)
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
  v_cifras := v_pct is distinct from v_old.pct_comision or v_base is distinct from v_old.base_calculo
              or v_fijo is distinct from v_old.importe_fijo
              or ((v_cerrada or v_n = 0) and v_tr_new is distinct from v_tr_act);

  -- 3a: las cifras de una condición cerrada no se tocan (tampoco sus tramos): se crea una nueva
  if v_cerrada and v_cifras then
    raise exception 'Esta condición está cerrada desde el %: sus cifras no se cambian. Crea una nueva desde la fecha que toque.',
      to_char(v_old.vigente_hasta, 'DD-MM-YYYY') using errcode = '22023';
  end if;

  -- 1: las cifras de una condición en vigor desde antes de hoy ya pesan sobre ventas hechas: el SM no las cambia
  if v_cifras and v_old.vigente_desde < v_hoy and not v_admin then
    raise exception 'Esta condición está en vigor desde el %: sus cifras no se cambian, crea una condición nueva desde hoy',
      to_char(v_old.vigente_desde, 'DD-MM-YYYY') using errcode = '42501';
  end if;

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
    if v_alcance and v_closer_nuevo is not null and not public._closer_del_equipo(v_old.equipo_id, v_closer_nuevo) then
      raise exception 'Esa persona no está hoy en tu equipo' using errcode = '42501';
    end if;
  end if;

  -- 1: cifras nuevas en una condición en vigor desde hoy o antes (hoy cuenta como pasado) → recuento de ventas
  -- afectadas desde el inicio más temprano (viejo o nuevo) hasta su cierre o hoy. Cubre también un cambio de fecha a
  -- la vez. Aquí solo llega el SM con inicio HOY (antes de hoy ya lo paró el bloqueo de arriba): con ventas, rechazo.
  if v_cifras and v_old.vigente_desde <= v_hoy then
    v_ventas := public._condicion_ventas_afectadas(v_old.equipo_id, v_old.proyecto_id, v_old.nivel, v_old.closer_email,
                  least(v_desde, v_old.vigente_desde), coalesce(v_old.vigente_hasta, v_hoy));
    if v_ventas > 0 and not v_admin then
      raise exception 'Esta condición empezó hoy y % venta(s) de hoy sin comisión completa cobran con ella: sus cifras no se cambian, empieza una nueva mañana o pide a administración',
        v_ventas using errcode = '42501';
    end if;
    if v_ventas > 0 and v_conf is distinct from v_ventas then
      raise exception 'Cambiar las cifras de esta condición (en vigor desde el %) afecta hasta a % venta(s) ya hechas sin comisión completa: confírmalo con ese número',
        to_char(v_old.vigente_desde, 'DD-MM-YYYY'), v_ventas
        using errcode = '22023', hint = 'lw-confirmar-ventas:' || v_ventas;
    end if;
  end if;

  if v_desde is distinct from v_old.vigente_desde then
    -- 3b: la frontera se mueve entre la fecha vieja y la nueva; las ventas ya hechas de ese tramo cambian de condición
    v_d1 := least(v_desde, v_old.vigente_desde);
    v_d2 := greatest(v_desde, v_old.vigente_desde) - 1;
    if v_d1 <= v_hoy and not (v_cifras and v_old.vigente_desde <= v_hoy) then
      v_ventas := public._condicion_ventas_afectadas(v_old.equipo_id, v_old.proyecto_id, v_old.nivel, v_old.closer_email, v_d1, v_d2);
      if v_ventas > 0 and not v_admin then
        raise exception 'Mover el inicio al % cambia de condición % venta(s) ya hechas y sin comisión completa: pídeselo a administración',
          to_char(v_desde, 'DD-MM-YYYY'), v_ventas using errcode = '42501';
      end if;
      if v_ventas > 0 and v_conf is distinct from v_ventas then
        raise exception 'Mover el inicio al % cambia de condición hasta % venta(s) ya hechas y sin comisión completa: confírmalo con ese número',
          to_char(v_desde, 'DD-MM-YYYY'), v_ventas
          using errcode = '22023', hint = 'lw-confirmar-ventas:' || v_ventas;
      end if;
    end if;

    -- sustituta sin devengos que cambia de fecha (futura o ya empezada): la que ella cerró se cierra el día
    -- antes de la fecha nueva, para que no quede ni hueco ni solape
    v_pred := v_old.sustituye_a;
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
         closer_email = case when v_alcance then v_closer_nuevo else c.closer_email end
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
           'ventas_max', v_ventas),
         v_n > 0, v_motivo
    from public.condiciones_comision c where c.id = p_id;
  return p_id;
end $function$;
revoke all on function public.condicion_comision_guarda(uuid, jsonb, jsonb, text) from public, anon;
grant execute on function public.condicion_comision_guarda(uuid, jsonb, jsonb, text) to authenticated;

comment on function public.condicion_comision_guarda(uuid, jsonb, jsonb, text) is
  'Alta y edición de condiciones de comisión (único camino de escritura). Reglas de dinero: el alcance (equipo, proyecto, nivel y a quién se aplica: todo el equipo o una persona) es identidad y no se edita, salvo a quién se aplica en una condición futura sin devengos que no sustituye ni es sustituida; las cifras de una cerrada no se tocan; el SM no cambia cifras de una en vigor desde antes de hoy. Hoy cuenta como pasado (Administración, 30-sep-2026): una condición nueva, un cambio de cifras o un cambio de inicio con inicio hoy o antes cuenta las ventas ya hechas (también las de hoy, día de Bali) sin comisión completa; si hay alguna, administración confirma el recuento y el SM recibe rechazo; con 0, pasa sin confirmar.';
