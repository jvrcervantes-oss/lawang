-- F6 · sexta parte (hueco ALTA de dinero, revisor de código, 30-sep-2026)
--
-- 1. [ALTA] condicion_comision_guarda guardaba closer_email («Override individual») sin tratarlo como cambio: un SM,
--    o administración sin confirmar nada, podía pasar una condición empezada o cerrada de «todo el equipo» a una
--    persona o al revés. Eso cambia qué ventas ya hechas cobran con ella, sin recuento, y si era una sustituta dejaba
--    al resto del alcance sin condición (hueco). Criterio: el alcance es identidad de la condición, igual que
--    equipo/proyecto/nivel. Solo se cambia en una condición futura, sin devengos, que no sustituye ni es sustituida;
--    en cualquier otro caso, 22023 «Para cambiar a quién se aplica, crea una condición nueva desde hoy».
--    El chequeo «esa persona está hoy en tu equipo» del SM solo mira cuando la persona cambia.
-- 2. _equipo_miembro_guarda_con: el camino del SM solo convierte en mensaje genérico 23P01 y 22023 (motivos de un
--    tercero) y 23505 (el índice único equipo_miembros_un_equipo_activo, que en una carrera diría lo mismo); cualquier otro error se relanza tal cual en vez de esconderse.
-- 3. _condicion_predecesora ignoraba cinco de sus seis parámetros (desde 082130 solo lee sustituye_a) y su único
--    llamador era condicion_comision_guarda, que ya tiene la fila: se lee v_old.sustituye_a. La función queda sin
--    llamador y marcada obsoleta; el DROP espera el OK del owner (no_destruir.py lo para).
-- 4. Queda escrita en el COMMENT la decisión «desde hoy»: una condición que empieza HOY no cuenta en el recuento
--    las ventas de hoy (solo un inicio anterior a hoy pide confirmar).

-- 1 y 3 · condicion_comision_guarda
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

    -- 3b: con inicio en el pasado, cuántas ventas ya hechas (sin devengar o a medio devengar) pueden pasar a esta condición
    if v_desde < v_hoy then
      v_ventas := public._condicion_ventas_afectadas(v_equipo, v_proy, v_nivel, v_closer, v_desde, v_hoy);
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

  -- 1 (admin): cifras nuevas en una condición en vigor desde antes de hoy → recuento de ventas afectadas desde
  -- el inicio más temprano (viejo o nuevo) hasta su cierre o hoy. Cubre también un cambio de fecha a la vez.
  if v_cifras and v_old.vigente_desde < v_hoy then
    v_ventas := public._condicion_ventas_afectadas(v_old.equipo_id, v_old.proyecto_id, v_old.nivel, v_old.closer_email,
                  least(v_desde, v_old.vigente_desde), coalesce(v_old.vigente_hasta, v_hoy));
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
    if v_d1 <= v_hoy and not (v_cifras and v_old.vigente_desde < v_hoy) then
      v_ventas := public._condicion_ventas_afectadas(v_old.equipo_id, v_old.proyecto_id, v_old.nivel, v_old.closer_email, v_d1, v_d2);
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

-- 2 · camino del SM: solo los motivos de un tercero salen como mensaje genérico
create or replace function public._equipo_miembro_guarda_con(p_id uuid, p_equipo uuid, p_email text, p_desde date, p_hasta date, p_confirmar integer)
 returns uuid
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_email text := nullif(lower(btrim(coalesce(p_email, ''))), '');
  v_hoy date := (now() at time zone 'Asia/Makassar')::date;
  v_res jsonb; v_eq text; v_yo text := lower(coalesce((select auth.email()), ''));
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  select e.nombre into v_eq from public.equipos_venta e where e.id = p_equipo;

  if public.es_admin() then
    if v_email = v_yo and not public.es_super_admin() then
      raise exception 'Nadie se añade a sí mismo a un equipo' using errcode = '42501';
    end if;
    -- fecha pasada o edición (traslado, cambio de fechas): SIEMPRE con el recuento de la vista previa
    v_res := public._equipo_miembro_mueve(p_id, p_equipo, v_email, p_desde, p_hasta, false, p_confirmar,
                                          (p_id is not null or p_desde < v_hoy), false);
    if p_id is not null or p_desde < v_hoy or (v_res->>'n')::int > 0 then
      perform public._equipo_aviso_admin(
        'Equipo ' || coalesce(v_eq, '?') || ': ' || case when p_id is null then 'alta' else 'cambio' end || ' de ' || v_email || ' desde ' || to_char(p_desde, 'DD-MM-YYYY'),
        'Hecho por ' || v_yo || '. Ventas que cambian de equipo: ' || (v_res->>'n') || '.');
    end if;
    return (v_res->>'id')::uuid;
  end if;

  -- Sales Manager de ESE equipo: solo altas nuevas, con fecha de hoy (la que mande el navegador no cuenta)
  if p_equipo is null or not public.es_manager_de_equipo(p_equipo) then
    raise exception 'Solo el sales manager de este equipo o administración dan de alta miembros' using errcode = '42501';
  end if;
  if p_id is not null then
    raise exception 'Cambiar fechas o mover a alguien de equipo lo hace administración' using errcode = '42501';
  end if;
  -- lo que diga el motivo concreto (inactivo, su rol, ya en otro equipo, dirige uno) es de un tercero: no sale
  if public._equipo_candidato_valido(v_email) is not null then
    raise exception 'Esa persona no se puede añadir a tu equipo' using errcode = '42501';
  end if;
  begin
    v_res := public._equipo_miembro_mueve(null, p_equipo, v_email, v_hoy, null, false, null, false, true);
  exception when sqlstate '23P01' or sqlstate '22023' or sqlstate '23505' then   -- solape, dato o el índice «un equipo activo»: hablan de un tercero; lo demás se relanza
    raise exception 'Esa persona no se puede añadir a tu equipo' using errcode = '42501';
  end;
  if (v_res->>'n')::int <> 0 then   -- no debería pasar nunca: el alta del SM no recoge ventas
    raise exception 'Esa persona no se puede añadir a tu equipo' using errcode = '42501';
  end if;
  perform public._equipo_aviso_admin(
    'Equipo ' || coalesce(v_eq, '?') || ': alta de ' || v_email,
    'La hizo el sales manager ' || v_yo || ' con fecha ' || to_char(v_hoy, 'DD-MM-YYYY') || '.');
  return (v_res->>'id')::uuid;
end $function$;
revoke all on function public._equipo_miembro_guarda_con(uuid, uuid, text, date, date, integer) from public, anon, authenticated;

comment on function public.condicion_comision_guarda(uuid, jsonb, jsonb, text) is
  'Alta y edición de condiciones de comisión (único camino de escritura). Reglas de dinero: el alcance (equipo, proyecto, nivel y a quién se aplica: todo el equipo o una persona) es identidad y no se edita, salvo a quién se aplica en una condición futura sin devengos que no sustituye ni es sustituida; las cifras de una cerrada no se tocan; el SM no cambia cifras de una en vigor desde antes de hoy; administración sí, confirmando el recuento (tope) de ventas afectadas. Decisión «desde hoy»: un inicio HOY no pide confirmar y no cuenta las ventas ya hechas hoy; solo un inicio anterior a hoy dispara el recuento.';

-- Sin llamador desde aquí. No se borra en esta migración: un DROP lo para no_destruir.py y pide el OK del owner
-- (se le ha reportado al CEO). Mientras, sigue revocada a todos los roles y el COMMENT dice que no se use.
comment on function public._condicion_predecesora(uuid, uuid, text, text, date, uuid) is
  'OBSOLETA (30-sep-2026, f6_f): sin llamador; ignora todo salvo p_excluye y devuelve su sustituye_a. Se lee condiciones_comision.sustituye_a directamente. Pendiente de borrar con OK del owner.';
