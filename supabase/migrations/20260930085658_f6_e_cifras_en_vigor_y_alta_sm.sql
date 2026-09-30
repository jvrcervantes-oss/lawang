-- F6 · quinta parte (consultas de deploy de Administración y Seguridad, 30-sep-2026)
--
-- 1. [Admin, dinero] Cambiar las CIFRAS (%, base, importe fijo o tramos) de una condición que ya está en vigor
--    desde antes de hoy (hora de Bali) cambia lo que cobran ventas ya hechas:
--      · el Sales Manager no puede: se le dice que cree una condición nueva desde hoy;
--      · administración sí, pero confirmando el recuento de ventas afectadas (mismo hint lw-confirmar-ventas:N
--        que al mover la fecha). Si a la vez mueve la fecha, un solo recuento cubre las dos cosas.
-- 2. [Admin] El recuento es un TOPE («hasta N ventas»), no un número exacto: una condición más específica
--    (por closer o por proyecto) puede quedarse alguna. Los mensajes lo dicen así y el log guarda `ventas_max`
--    (antes `ventas_confirmadas`).
--    Y el recuento incluye ahora las ventas A MEDIO DEVENGAR. Comprobado en el cuerpo vivo de
--    comisiones_evaluar_contrato: la condición NO queda fijada al primer devengo. En cada evaluación se vuelve a
--    elegir por la fecha de la venta; si ya hubo un devengo con OTRA condición, la venta hace `continue`
--    («la primera condición que devenga manda») y sus tramos pendientes no se pagan con ninguna; si es la
--    MISMA condición, los tramos pendientes se calculan con sus cifras de ese momento. En los dos casos, una
--    venta con tramos cobrados y tramos pendientes se ve afectada por el cambio.
-- 3. [Seg] equipo_miembro_guarda (por email) pasa a ser solo de administración; el Sales Manager entra
--    únicamente por equipo_miembro_anade (por id). En el camino del SM, cualquier motivo que hable de un tercero
--    (no existe, inactivo, su rol, ya está en otro equipo, dirige un equipo) sale como un único mensaje
--    genérico: «Esa persona no se puede añadir a tu equipo».
-- 4. [Seg] Carrera: _equipo_miembro_mueve toma pg_advisory_xact_lock(hashtext(lower(email))) antes de mirar
--    solapes, para que dos altas simultáneas de la misma persona no la dejen en dos equipos
--    (no hay btree_gist para una restricción de exclusión).
-- 5. _closer_del_equipo mira la fecha de Bali, no current_date (UTC).
-- 6. Se borra public.equipo_candidatos (revocada en 082130, sin llamador; OK del owner 30-sep).

-- 2 · recuento compartido: sin devengar O a medio devengar
create or replace function public._condicion_ventas_afectadas(p_equipo uuid, p_proy uuid, p_nivel text, p_closer text, p_d1 date, p_d2 date)
 returns integer
 language sql
 stable security definer
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
revoke all on function public._condicion_ventas_afectadas(uuid, uuid, text, text, date, date) from public, anon, authenticated;

-- 1 y 2 · condicion_comision_guarda
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
    if v_closer is not null and not public._closer_del_equipo(v_old.equipo_id, v_closer) then
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
           'ventas_max', v_ventas),
         v_n > 0, v_motivo
    from public.condiciones_comision c where c.id = p_id;
  return p_id;
end $function$;
revoke all on function public.condicion_comision_guarda(uuid, jsonb, jsonb, text) from public, anon;
grant execute on function public.condicion_comision_guarda(uuid, jsonb, jsonb, text) to authenticated;

-- 3 · por email, solo administración
create or replace function public.equipo_miembro_guarda(p_id uuid, p_equipo uuid, p_email text, p_desde date, p_hasta date)
 returns uuid
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if not public.es_admin() then
    raise exception 'El alta por email es de administración: el sales manager añade desde su lista de candidatos' using errcode = '42501';
  end if;
  return public._equipo_miembro_guarda_con(p_id, p_equipo, p_email, p_desde, p_hasta, null);
end $function$;
revoke all on function public.equipo_miembro_guarda(uuid, uuid, text, date, date) from public, anon;
grant execute on function public.equipo_miembro_guarda(uuid, uuid, text, date, date) to authenticated;

-- 3 · por id: admin con el mensaje de siempre; cualquier otro, genérico (no sirve para sondear ids)
create or replace function public.equipo_miembro_anade(p_equipo uuid, p_usuario uuid)
 returns uuid
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_email text;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if not public.es_admin() and (p_equipo is null or not public.es_manager_de_equipo(p_equipo)) then
    raise exception 'Solo el sales manager de este equipo o administración dan de alta miembros' using errcode = '42501';
  end if;
  select lower(u.email) into v_email from public.usuarios u where u.user_id = p_usuario and u.activo;
  if v_email is null then
    if public.es_admin() then
      raise exception 'El miembro tiene que ser un usuario activo de la intranet' using errcode = '22023';
    end if;
    raise exception 'Esa persona no se puede añadir a tu equipo' using errcode = '42501';
  end if;
  return public._equipo_miembro_guarda_con(null, p_equipo, v_email, (now() at time zone 'Asia/Makassar')::date, null, null);
end $function$;
revoke all on function public.equipo_miembro_anade(uuid, uuid) from public, anon;
grant execute on function public.equipo_miembro_anade(uuid, uuid) to authenticated;

-- 3 · camino del SM con mensaje genérico para todo lo que hable de un tercero
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
  exception when others then
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

-- 4 · candado por persona antes de mirar solapes
create or replace function public._equipo_miembro_mueve(p_id uuid, p_equipo uuid, p_email text, p_desde date, p_hasta date, p_simular boolean, p_confirmar integer, p_confirma_siempre boolean, p_sin_recongela boolean)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_email text := nullif(lower(btrim(coalesce(p_email, ''))), '');
  v_old public.equipo_miembros%rowtype;
  v_id uuid; v_choca uuid; v_n int := 0; v_cong int := 0;
  v_antes jsonb; v_lista jsonb := '[]'::jsonb;
  v_dev0 bigint; v_sp0 bigint; v_dev1 bigint; v_sp1 bigint;
  v_res jsonb;
begin
  if v_email is null or not public._usuario_activo(v_email) then
    raise exception 'El miembro tiene que ser un usuario activo de la intranet' using errcode = '22023';
  end if;
  if p_desde is null then raise exception 'Falta la fecha «Desde»' using errcode = '22023'; end if;
  if p_hasta is not null and p_hasta < p_desde then raise exception '«Hasta» no puede ser anterior a «Desde».' using errcode = '22023'; end if;
  if not exists (select 1 from public.equipos_venta e where e.id = p_equipo) then
    raise exception 'Ese equipo no existe' using errcode = 'P0002';
  end if;
  -- dos altas a la vez de la misma persona: la segunda espera aquí y luego ve la fila de la primera
  perform pg_advisory_xact_lock(hashtext(v_email));
  if p_id is not null then
    select * into v_old from public.equipo_miembros m where m.id = p_id;
    if not found then raise exception 'Ese miembro no existe' using errcode = 'P0002'; end if;
    if lower(v_old.closer_email) <> v_email then
      perform pg_advisory_xact_lock(hashtext(lower(v_old.closer_email)));
    end if;
  end if;
  -- solape de rangos con CUALQUIER otra fila de la persona, también del mismo equipo; una fila con «hasta» futura cuenta
  select em.equipo_id into v_choca from public.equipo_miembros em
   where lower(em.closer_email) = v_email
     and (p_id is null or em.id <> p_id)
     and em.desde <= coalesce(p_hasta, 'infinity'::date)
     and p_desde <= coalesce(em.hasta, 'infinity'::date)
   order by (em.equipo_id = p_equipo) desc
   limit 1;
  if found then
    if v_choca = p_equipo then
      raise exception 'Esa persona ya está en este equipo en esas fechas: edita su fila en vez de añadir otra' using errcode = '23P01';
    end if;
    raise exception 'Esa persona ya está en otro equipo en esas fechas: dale de baja allí primero' using errcode = '23P01';
  end if;

  begin
    -- congelar ANTES de la foto: una venta sin congelar que se congela con el equipo de hoy no «se mueve»
    v_cong := public._equipo_congela_ventas(p_equipo, v_email);
    if p_id is not null then
      v_cong := v_cong + public._equipo_congela_ventas(v_old.equipo_id, v_old.closer_email);
    end if;
    select coalesce(jsonb_object_agg(k.contrato_id::text, jsonb_build_array(k.equipo_id, k.manager_email)), '{}'::jsonb)
      into v_antes from public.contrato_closer k;
    select count(*) into v_dev0 from public.comisiones_devengadas;
    select count(*) into v_sp0 from public.solicitudes_pago;

    perform set_config('lw.sin_recongela', case when p_sin_recongela then '1' else '' end, true);
    if p_id is null then
      insert into public.equipo_miembros (equipo_id, closer_email, desde, hasta, added_by)
      values (p_equipo, v_email, p_desde, p_hasta, (select auth.email())) returning id into v_id;
    else
      update public.equipo_miembros
         set equipo_id = p_equipo, closer_email = v_email, desde = p_desde, hasta = p_hasta
       where id = p_id;
      v_id := p_id;
    end if;
    perform set_config('lw.sin_recongela', '', true);

    select coalesce(jsonb_agg(jsonb_build_object(
             'contrato_id', k.contrato_id, 'numero', c.numero, 'comprador', c.comprador_nombre,
             'proyecto', p.nombre, 'closer', k.closer_email,
             'fecha', coalesce(k.fecha_venta, (c.created_at at time zone 'Asia/Makassar')::date),
             'equipo_antes', ea.nombre, 'equipo_despues', ed.nombre,
             'devengos', (select count(*) from public.comisiones_devengadas d where d.contrato_raiz_id = k.contrato_id))
             order by coalesce(k.fecha_venta, (c.created_at at time zone 'Asia/Makassar')::date), c.numero), '[]'::jsonb)
      into v_lista
      from public.contrato_closer k
      join public.contratos c on c.id = k.contrato_id
      left join public.proyectos p on p.id = c.proyecto_id
      left join public.equipos_venta ea on ea.id = nullif(v_antes -> k.contrato_id::text ->> 0, '')::uuid
      left join public.equipos_venta ed on ed.id = k.equipo_id
     where (v_antes -> k.contrato_id::text) is null
        or (v_antes -> k.contrato_id::text ->> 0) is distinct from k.equipo_id::text
        or (v_antes -> k.contrato_id::text ->> 1) is distinct from k.manager_email;
    v_n := jsonb_array_length(v_lista);
    select count(*) into v_dev1 from public.comisiones_devengadas;
    select count(*) into v_sp1 from public.solicitudes_pago;

    v_res := jsonb_build_object('id', v_id, 'ventas', v_lista, 'n', v_n,
                                'devengos_nuevos', v_dev1 - v_dev0, 'solicitudes_nuevas', v_sp1 - v_sp0);

    if p_simular then
      raise exception 'simulacion' using errcode = 'LWS01';
    end if;
    if (p_confirma_siempre or v_n > 0) and p_confirmar is distinct from v_n then
      raise exception 'Esta alta mueve % venta(s) de equipo y confirmaste %: vuelve a abrir la vista previa y confirma lo que ves ahora', v_n, coalesce(p_confirmar::text, 'ninguna')
        using errcode = '22023';
    end if;
    insert into public.equipos_log (tabla, fila_id, antes, despues, ventas_congeladas)
    select 'equipo_miembros', v_id, case when p_id is null then null else to_jsonb(v_old) end,
           to_jsonb(m) || jsonb_build_object('ventas_movidas', v_n), v_cong
      from public.equipo_miembros m where m.id = v_id;
  exception when sqlstate 'LWS01' then
    null;   -- la vista previa: todo lo de arriba se deshace, v_res queda con lo que habría pasado
  end;
  return v_res;
end $function$;
revoke all on function public._equipo_miembro_mueve(uuid, uuid, text, date, date, boolean, integer, boolean, boolean) from public, anon, authenticated;

-- 5 · fecha de Bali
create or replace function public._closer_del_equipo(p_equipo uuid, p_email text)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  select exists (select 1 from public.equipo_miembros em
                  where em.equipo_id = p_equipo and lower(em.closer_email) = lower(p_email)
                    and em.desde <= (now() at time zone 'Asia/Makassar')::date
                    and (em.hasta is null or em.hasta >= (now() at time zone 'Asia/Makassar')::date))
$function$;
revoke all on function public._closer_del_equipo(uuid, text) from public, anon, authenticated;

-- 6 · función vieja sin llamador
-- destructivo-ok: owner 30-sep «Sí, bórrala» — función revocada sin llamador
drop function if exists public.equipo_candidatos(uuid);
