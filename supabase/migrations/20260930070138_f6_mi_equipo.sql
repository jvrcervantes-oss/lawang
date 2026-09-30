-- F6 · «Mi equipo» del Sales Manager (encargo 20260930_lawang_equipos_venta_asistente, D4/D5/D6 + Seguridad #162)
--
-- Quién manda sobre cada dato (patrones_tecnicos → «El dato tiene un dueño»):
--   · equipo_miembros (quién está, desde cuándo, rol y nombre de rol): dueño = el SM de ese equipo
--     para altas DE HOY, bajas DE HOY y el rol; administración para todo lo demás (fechas pasadas,
--     traslados entre equipos). contrato_closer.equipo_id es una COPIA CONGELADA del día de la venta:
--     ninguna función de aquí la reescribe salvo el alta retroactiva de admin, y esa exige confirmar
--     el recuento exacto que enseñó la vista previa.
--   · plantilla_reparto: dueño = el SM (herramienta suya). NUNCA genera solicitudes de pago de Lawang
--     (decisión fiscal D3: el SM es el único perceptor). Aquí solo se LEE (SM de ese equipo y admin);
--     guardarla queda para una migración aparte (pasa por no_destruir.py: reemplaza filas).
--   · equipos_venta.closers_ven_comision: dueño = el SM de ese equipo (o admin). Lo lee comision_visible.
--   · condiciones_comision: desactivar = CERRAR (activo=false + vigente_hasta a la vez); una nueva cierra
--     sola la anterior del mismo alcance en nueva.vigente_desde − 1.
--
-- «Hoy» es hoy en Bali (Asia/Makassar), el mismo ancla que el congelado de ventas.

-- ───────────────────────────── 1. trigger de miembros ─────────────────────────────
-- Antes: saltaba en CUALQUIER update (cambiar el rol re-atribuía ventas) y siempre descongelaba las
-- ventas «sin equipo» del rango nuevo (un alta de HOY por el SM se llevaba las ventas de esta mañana).
create or replace function public._trg_equipo_miembros_congela()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if tg_op = 'UPDATE'
     and new.equipo_id = old.equipo_id
     and lower(new.closer_email) = lower(old.closer_email)
     and new.desde = old.desde
     and new.hasta is not distinct from old.hasta then
    return new;   -- rol / rol_nombre: no mueve ninguna venta
  end if;
  if tg_op in ('UPDATE', 'DELETE') then
    perform public._equipo_congela_ventas(old.equipo_id, old.closer_email);
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    perform public._equipo_congela_ventas(new.equipo_id, new.closer_email);
    -- el alta del SM y cualquier baja NO recogen ventas «sin equipo» (F6, D6): lo decide la RPC
    if coalesce(current_setting('lw.sin_recongela', true), '') <> '1' then
      perform public._equipo_recongela_sin_equipo(new.closer_email, new.desde, new.hasta);
    end if;
    return new;
  end if;
  return old;
end $function$;

-- ───────────────────────────── 2. núcleo único de escritura de miembros ─────────────────────────────
-- Un solo camino para la vista previa y para el alta confirmada: hace la escritura de verdad, compara
-- contrato_closer antes/después y, si es simulación, deshace con una excepción propia (las variables
-- sobreviven al rollback del bloque). Así la lista que ve admin y la que se aplica son la misma por
-- construcción. Interno: sin grant a authenticated.
create or replace function public._equipo_miembro_mueve(
  p_id uuid, p_equipo uuid, p_email text, p_desde date, p_hasta date,
  p_simular boolean, p_confirmar integer, p_confirma_siempre boolean, p_sin_recongela boolean)
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
  if p_id is not null then
    select * into v_old from public.equipo_miembros m where m.id = p_id;
    if not found then raise exception 'Ese miembro no existe' using errcode = 'P0002'; end if;
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

-- aviso a administración (campana): destinatario NULL = lo ven los admins (policy de notificaciones)
create or replace function public._equipo_aviso_admin(p_titulo text, p_detalle text)
 returns void
 language sql
 security definer
 set search_path to ''
as $function$
  insert into public.notificaciones (tipo, titulo, detalle, destinatario, enlace)
  values ('equipo_venta', left(p_titulo, 200), left(p_detalle, 500), null, '/intranet/v4/equipos-venta/');
$function$;
revoke all on function public._equipo_aviso_admin(text, text) from public, anon, authenticated;

-- ¿puede esta persona entrar en un equipo por mano del SM? (D6 + Seguridad #162). NULL = sí; si no, el motivo.
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
  if v_rol in ('sales_manager', 'admin', 'super_admin') then
    return 'A un sales manager o a administración no se le mete en un equipo desde aquí: lo hace administración';
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

-- ───────────────────────────── 3. RPCs de miembros ─────────────────────────────
-- núcleo con permisos; dos puertas públicas: la de siempre (sin confirmación) y la confirmada de admin
create or replace function public._equipo_miembro_guarda_con(
  p_id uuid, p_equipo uuid, p_email text, p_desde date, p_hasta date, p_confirmar integer)
 returns uuid
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_email text := nullif(lower(btrim(coalesce(p_email, ''))), '');
  v_hoy date := (now() at time zone 'Asia/Makassar')::date;
  v_res jsonb; v_mal text; v_eq text; v_yo text := lower(coalesce((select auth.email()), ''));
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
  v_mal := public._equipo_candidato_valido(v_email);
  if v_mal is not null then raise exception '%', v_mal using errcode = '42501'; end if;
  v_res := public._equipo_miembro_mueve(null, p_equipo, v_email, v_hoy, null, false, null, false, true);
  if (v_res->>'n')::int <> 0 then   -- no debería pasar nunca: el alta del SM no recoge ventas
    raise exception 'Este alta movería ventas ya hechas: la tiene que hacer administración' using errcode = '42501';
  end if;
  perform public._equipo_aviso_admin(
    'Equipo ' || coalesce(v_eq, '?') || ': alta de ' || v_email,
    'La hizo el sales manager ' || v_yo || ' con fecha ' || to_char(v_hoy, 'DD-MM-YYYY') || '.');
  return (v_res->>'id')::uuid;
end $function$;
revoke all on function public._equipo_miembro_guarda_con(uuid, uuid, text, date, date, integer) from public, anon, authenticated;

-- la de siempre (editores.js): SM con fecha de hoy, y admin cuando no mueve ninguna venta
create or replace function public.equipo_miembro_guarda(p_id uuid, p_equipo uuid, p_email text, p_desde date, p_hasta date)
 returns uuid
 language sql
 security definer
 set search_path to ''
as $function$
  select public._equipo_miembro_guarda_con(p_id, p_equipo, p_email, p_desde, p_hasta, null)
$function$;
revoke all on function public.equipo_miembro_guarda(uuid, uuid, text, date, date) from public, anon;
grant execute on function public.equipo_miembro_guarda(uuid, uuid, text, date, date) to authenticated;

-- la de admin tras la vista previa: fecha pasada o cambio de una fila, con el recuento que vio
create or replace function public.equipo_miembro_guarda_confirmada(p_id uuid, p_equipo uuid, p_email text, p_desde date, p_hasta date, p_confirmar integer)
 returns uuid
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if not public.es_admin() then
    raise exception 'Las altas con fecha pasada y los cambios de fila son de administración' using errcode = '42501';
  end if;
  if p_confirmar is null then raise exception 'Falta confirmar el recuento de la vista previa' using errcode = '22023'; end if;
  return public._equipo_miembro_guarda_con(p_id, p_equipo, p_email, p_desde, p_hasta, p_confirmar);
end $function$;
revoke all on function public.equipo_miembro_guarda_confirmada(uuid, uuid, text, date, date, integer) from public, anon;
grant execute on function public.equipo_miembro_guarda_confirmada(uuid, uuid, text, date, date, integer) to authenticated;

create or replace function public.equipo_miembro_vista_previa(
  p_id uuid, p_equipo uuid, p_email text, p_desde date, p_hasta date)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if not public.es_admin() then
    raise exception 'La vista previa de altas con fecha pasada es de administración' using errcode = '42501';
  end if;
  return public._equipo_miembro_mueve(p_id, p_equipo, p_email, p_desde, p_hasta, true, null, false, false) - 'id';
end $function$;
revoke all on function public.equipo_miembro_vista_previa(uuid, uuid, text, date, date) from public, anon;
grant execute on function public.equipo_miembro_vista_previa(uuid, uuid, text, date, date) to authenticated;

create or replace function public.equipo_miembro_baja(p_id uuid, p_hasta date)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_old public.equipo_miembros%rowtype; v_n int; v_hasta date; v_eq text;
  v_hoy date := (now() at time zone 'Asia/Makassar')::date; v_yo text := lower(coalesce((select auth.email()), ''));
  v_admin boolean := public.es_admin();
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  select * into v_old from public.equipo_miembros m where m.id = p_id for update;
  if not found then raise exception 'Ese miembro no existe' using errcode = 'P0002'; end if;
  if not v_admin then
    if not public.es_manager_de_equipo(v_old.equipo_id) then
      raise exception 'Solo el sales manager de este equipo o administración dan de baja miembros' using errcode = '42501';
    end if;
    if lower(v_old.closer_email) = v_yo then
      raise exception 'Tu propia fila en el equipo la cambia administración' using errcode = '42501';
    end if;
  end if;
  v_hasta := case when v_admin then p_hasta else v_hoy end;   -- el SM siempre con fecha de hoy
  if v_old.hasta is not null and v_old.hasta <= v_hoy then
    raise exception 'Esa persona ya está de baja desde el %', to_char(v_old.hasta, 'DD-MM-YYYY') using errcode = '22023';
  end if;
  if v_hasta is null or v_hasta < v_old.desde then raise exception 'La fecha de baja no puede ser anterior a su alta' using errcode = '22023'; end if;
  v_n := public._equipo_congela_ventas(v_old.equipo_id, v_old.closer_email);
  perform set_config('lw.sin_recongela', '1', true);   -- acortar un rango nunca recoge ventas
  update public.equipo_miembros set hasta = v_hasta where id = p_id;
  perform set_config('lw.sin_recongela', '', true);
  insert into public.equipos_log (tabla, fila_id, antes, despues, ventas_congeladas)
  values ('equipo_miembros', p_id, jsonb_build_object('hasta', v_old.hasta), jsonb_build_object('hasta', v_hasta), v_n);
  select e.nombre into v_eq from public.equipos_venta e where e.id = v_old.equipo_id;
  perform public._equipo_aviso_admin(
    'Equipo ' || coalesce(v_eq, '?') || ': baja de ' || v_old.closer_email,
    'Hecha por ' || v_yo || ' con fecha ' || to_char(v_hasta, 'DD-MM-YYYY') || '.');
end $function$;
revoke all on function public.equipo_miembro_baja(uuid, date) from public, anon;
grant execute on function public.equipo_miembro_baja(uuid, date) to authenticated;

create or replace function public.equipo_miembro_rol(p_id uuid, p_rol text, p_rol_nombre text)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_old public.equipo_miembros%rowtype; v_nom text := nullif(btrim(coalesce(p_rol_nombre, '')), '');
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  select * into v_old from public.equipo_miembros m where m.id = p_id for update;
  if not found then raise exception 'Ese miembro no existe' using errcode = 'P0002'; end if;
  if not (public.es_admin() or public.es_manager_de_equipo(v_old.equipo_id)) then
    raise exception 'El rol lo pone el sales manager de su equipo o administración' using errcode = '42501';
  end if;
  if p_rol is null or p_rol not in ('closer', 'setter', 'otro') then
    raise exception 'El tipo de rol es Closer, Setter u Otro' using errcode = '22023';
  end if;
  if v_nom is not null and length(v_nom) > 60 then raise exception 'El nombre del rol cabe en 60 letras' using errcode = '22023'; end if;
  update public.equipo_miembros set rol = p_rol, rol_nombre = v_nom where id = p_id;
  insert into public.equipos_log (tabla, fila_id, antes, despues)
  values ('equipo_miembros', p_id, jsonb_build_object('rol', v_old.rol, 'rol_nombre', v_old.rol_nombre),
          jsonb_build_object('rol', p_rol, 'rol_nombre', v_nom));
end $function$;
revoke all on function public.equipo_miembro_rol(uuid, text, text) from public, anon;
grant execute on function public.equipo_miembro_rol(uuid, text, text) to authenticated;

-- el buscador de «Añadir miembro» del SM: solo gente que de verdad puede entrar (el SM no lee
-- equipo_miembros de otros equipos, así que la lista la tiene que dar el servidor)
create or replace function public.equipo_candidatos(p_equipo uuid)
 returns table(email text, nombre text)
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if not (public.es_admin() or public.es_manager_de_equipo(p_equipo)) then
    raise exception 'Solo el sales manager de este equipo o administración' using errcode = '42501';
  end if;
  return query
    select lower(u.email), coalesce(u.nombre, u.email)
      from public.usuarios u
     where u.activo and public._equipo_candidato_valido(u.email) is null
     order by coalesce(u.nombre, u.email);
end $function$;
revoke all on function public.equipo_candidatos(uuid) from public, anon;
grant execute on function public.equipo_candidatos(uuid) to authenticated;

-- ───────────────────────────── 4. plantilla de reparto: lectura (SM de ese equipo y admin) ─────────────────────────────
create or replace function public.plantilla_reparto_lee(p_equipo uuid)
 returns table(rol_tipo text, rol_nombre text, pct numeric)
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if not (public.es_admin() or public.es_manager_de_equipo(p_equipo)) then
    raise exception 'La plantilla de reparto solo la ven su sales manager y administración' using errcode = '42501';
  end if;
  return query select p.rol_tipo, p.rol_nombre, p.pct from public.plantilla_reparto p
                where p.equipo_id = p_equipo order by p.pct desc, p.rol_nombre;
end $function$;
revoke all on function public.plantilla_reparto_lee(uuid) from public, anon;
grant execute on function public.plantilla_reparto_lee(uuid) to authenticated;

-- ───────────────────────────── 5. interruptor «mis closers ven su comisión» ─────────────────────────────
create or replace function public.equipo_closers_ven_comision(p_equipo uuid, p_valor boolean)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_old public.equipos_venta%rowtype;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if p_valor is null then raise exception 'Falta el valor del interruptor' using errcode = '22023'; end if;
  select * into v_old from public.equipos_venta e where e.id = p_equipo for update;
  if not found then raise exception 'Ese equipo no existe' using errcode = 'P0002'; end if;
  if not (public.es_admin() or public.es_manager_de_equipo(p_equipo)) then
    raise exception 'Lo cambia el sales manager de este equipo o administración' using errcode = '42501';
  end if;
  if v_old.closers_ven_comision = p_valor then return; end if;
  update public.equipos_venta set closers_ven_comision = p_valor where id = p_equipo;
  insert into public.equipos_log (tabla, fila_id, antes, despues)
  values ('equipos_venta', p_equipo, jsonb_build_object('closers_ven_comision', v_old.closers_ven_comision),
          jsonb_build_object('closers_ven_comision', p_valor));
  perform public._equipo_aviso_admin(
    'Equipo ' || v_old.nombre || ': sus closers ' || case when p_valor then 'ya ven' else 'dejan de ver' end || ' su comisión',
    'Lo cambió ' || lower(coalesce((select auth.email()), '')) || '.');
end $function$;
revoke all on function public.equipo_closers_ven_comision(uuid, boolean) from public, anon;
grant execute on function public.equipo_closers_ven_comision(uuid, boolean) to authenticated;

-- ───────────────────────────── 6. condiciones: desactivar = cerrar (reglas de Administración, F6) ─────────────────────────────
-- fecha de la venta más reciente que YA devengó con esta condición (mismo ancla que el congelado)
create or replace function public._condicion_ultima_venta_devengada(p_cond uuid)
 returns date
 language sql
 stable
 security definer
 set search_path to ''
as $function$
  select max(coalesce(k.fecha_venta, (rz.created_at at time zone 'Asia/Makassar')::date))
    from public.comisiones_devengadas d
    join public.contratos rz on rz.id = d.contrato_raiz_id
    left join public.contrato_closer k on k.contrato_id = d.contrato_raiz_id
   where d.condicion_id = p_cond and d.estado <> 'anulada'
$function$;
revoke all on function public._condicion_ultima_venta_devengada(uuid) from public, anon, authenticated;

-- otra condición EN VIGOR del mismo alcance cuyo rango de fechas se pisa con esta (el motor cogería una al azar)
create or replace function public._condicion_solapa(p_cond uuid)
 returns uuid
 language sql
 stable
 security definer
 set search_path to ''
as $function$
  select b.id from public.condiciones_comision a
    join public.condiciones_comision b
      on b.id <> a.id
     and b.equipo_id is not distinct from a.equipo_id
     and b.proyecto_id is not distinct from a.proyecto_id
     and b.nivel = a.nivel
     and lower(coalesce(b.closer_email, '')) = lower(coalesce(a.closer_email, ''))
     and (b.activo or b.vigente_hasta is not null)
     and b.vigente_desde <= coalesce(a.vigente_hasta, 'infinity'::date)
     and a.vigente_desde <= coalesce(b.vigente_hasta, 'infinity'::date)
   where a.id = p_cond and (a.activo or a.vigente_hasta is not null)
   limit 1
$function$;
revoke all on function public._condicion_solapa(uuid) from public, anon, authenticated;

create or replace function public.condicion_comision_activa(p_id uuid, p_activo boolean)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_old public.condiciones_comision%rowtype; v_hoy date := (now() at time zone 'Asia/Makassar')::date;
  v_hasta date; v_ult date;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if p_activo is null then raise exception 'Falta el valor' using errcode = '22023'; end if;
  select * into v_old from public.condiciones_comision c where c.id = p_id for update;
  if not found or not public._condicion_es_mia(v_old.nivel, v_old.equipo_id) then
    raise exception 'No encuentro esa condición entre las tuyas' using errcode = '42501';
  end if;

  if not p_activo then
    -- DESACTIVAR = CERRAR: activo=false y vigente_hasta a la vez. Sin fecha de fin el motor la dejaría
    -- de aplicar también HACIA ATRÁS, y con el recálculo encendido movería dinero ya devengado.
    if not v_old.activo then
      raise exception 'Esta condición ya está cerrada%', coalesce(' desde el ' || to_char(v_old.vigente_hasta, 'DD-MM-YYYY'), '') using errcode = '22023';
    end if;
    if v_old.vigente_desde > v_hoy then
      raise exception 'Esta condición empieza el %: todavía no se ha aplicado a ninguna venta. Cámbiale la fecha en «Editar» en vez de cerrarla.',
        to_char(v_old.vigente_desde, 'DD-MM-YYYY') using errcode = '22023';
    end if;
    v_hasta := least(coalesce(v_old.vigente_hasta, v_hoy), v_hoy);
    v_ult := public._condicion_ultima_venta_devengada(p_id);
    if v_ult is not null and v_ult > v_hasta then
      raise exception 'Una venta del % ya ha cobrado comisión con esta condición: no se puede cerrar antes de esa fecha',
        to_char(v_ult, 'DD-MM-YYYY') using errcode = '22023';
    end if;
    update public.condiciones_comision set activo = false, vigente_hasta = v_hasta where id = p_id;
    insert into public.condiciones_comision_log (condicion_id, antes, despues, motivo)
    values (p_id, jsonb_build_object('activo', v_old.activo, 'vigente_hasta', v_old.vigente_hasta),
            jsonb_build_object('activo', false, 'vigente_hasta', v_hasta), 'cerrada');
    return;
  end if;

  -- REACTIVAR: una condición cerrada no se reabre (volvería a aplicarse a las ventas entre su cierre y hoy)
  if v_old.activo then return; end if;
  if v_old.vigente_hasta is not null then
    raise exception 'Una condición cerrada no se reabre: crea una nueva desde hoy' using errcode = '22023';
  end if;
  if v_old.vigente_desde < v_hoy then
    raise exception 'Reactivarla la aplicaría a ventas pasadas: crea una nueva desde hoy' using errcode = '22023';
  end if;
  update public.condiciones_comision set activo = true where id = p_id;
  if public._condicion_solapa(p_id) is not null then
    raise exception 'Ya hay otra condición en vigor para ese mismo alcance en esas fechas' using errcode = '23P01';
  end if;
  insert into public.condiciones_comision_log (condicion_id, antes, despues, motivo)
  values (p_id, jsonb_build_object('activo', false), jsonb_build_object('activo', true), null);
end $function$;
revoke all on function public.condicion_comision_activa(uuid, boolean) from public, anon;
grant execute on function public.condicion_comision_activa(uuid, boolean) to authenticated;

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