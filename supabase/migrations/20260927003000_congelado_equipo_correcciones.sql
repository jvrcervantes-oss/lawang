-- destructivo-ok: reemplaza el trigger del congelado (drop/create del trigger nuevo de 001500) y borra, DENTRO de una función, roles de setter/team lead del equipo ANTERIOR que ya no pueden cobrar nunca (sin devengos); esta migración no borra ninguna fila al aplicarse.
-- Correcciones del congelado del equipo de una venta (consulta de deploy de Administración, 26/27-sep-2026,
-- LAW-336 pieza 7). Ninguna duplicaba comisiones (índice único + on conflict), pero podían perder o
-- reasignar alguna:
-- 1) ALTA: volver a guardar el MISMO closer (crm_contrato_closer_set hace el UPDATE aunque no cambie) borraba
--    el congelado y lo rehacía con el manager de hoy → el trigger solo actúa si el closer CAMBIA de verdad.
-- 2) Una venta congelada SIN equipo (su closer aún no estaba en ninguno) se quedaba en estándar para siempre
--    aunque luego se diera de alta al closer con fecha que cubre la venta → si esa venta no ha devengado nada,
--    se vuelve a congelar con el equipo que le toca.
-- 3) Al cambiar el closer a otro equipo, setter/team lead del equipo anterior quedaban colgados (el motor
--    filtra por equipo y no cobrarían nunca, sin aviso) → se quitan si no han devengado nada.
-- 4) Un admin podía saltarse el congelado escribiendo directo en equipos_venta/equipo_miembros → el
--    congelado pasa a triggers de esas tablas: vale por cualquier camino (las RPC lo seguían haciendo; ahora
--    es doble, sin efecto: una venta ya congelada no se vuelve a congelar).

-- 1) + 3) trigger de contrato_closer: alta, o cambio REAL de closer
create or replace function public._trg_contrato_closer_congela() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_eq_antes uuid; v_eq_nuevo uuid;
begin
  if tg_op = 'UPDATE' then
    select k.equipo_id into v_eq_antes from public.contrato_closer k where k.contrato_id = new.contrato_id;
    update public.contrato_closer k set equipo_id = null, manager_email = null, equipo_congelado_en = null
     where k.contrato_id = new.contrato_id;
  end if;
  perform public._venta_congela_equipo(new.contrato_id);
  if tg_op = 'UPDATE' then
    select k.equipo_id into v_eq_nuevo from public.contrato_closer k where k.contrato_id = new.contrato_id;
    if v_eq_antes is distinct from v_eq_nuevo then
      delete from public.contrato_roles_equipo re
       where re.contrato_raiz_id = new.contrato_id
         and re.equipo_id is distinct from v_eq_nuevo
         and not exists (select 1 from public.comisiones_devengadas d
                          where d.contrato_raiz_id = re.contrato_raiz_id and d.nivel = re.rol
                            and lower(d.beneficiario_email) = lower(re.email) and d.estado <> 'anulada');
    end if;
  end if;
  return null;
end $$;
revoke all on function public._trg_contrato_closer_congela() from public, anon, authenticated;
drop trigger if exists trg_contrato_closer_congela on public.contrato_closer;
drop trigger if exists trg_contrato_closer_congela_alta on public.contrato_closer;
drop trigger if exists trg_contrato_closer_congela_cambio on public.contrato_closer;
create trigger trg_contrato_closer_congela_alta after insert on public.contrato_closer
  for each row execute function public._trg_contrato_closer_congela();
create trigger trg_contrato_closer_congela_cambio after update of closer_email on public.contrato_closer
  for each row when (lower(coalesce(old.closer_email, '')) is distinct from lower(coalesce(new.closer_email, '')))
  execute function public._trg_contrato_closer_congela();

-- 2) ventas congeladas SIN equipo de un closer al que se da de alta con fechas que las cubren: se vuelven a
--    congelar si no han devengado nada (con devengos, lo cobrado manda y no se reasigna).
create or replace function public._equipo_recongela_sin_equipo(p_email text, p_desde date, p_hasta date) returns integer
language plpgsql security definer set search_path = '' as $$
declare r record; n int := 0;
begin
  for r in
    select k.contrato_id from public.contrato_closer k
     where lower(k.closer_email) = lower(p_email)
       and k.equipo_congelado_en is not null and k.equipo_id is null
       and coalesce(k.fecha_venta, current_date) >= p_desde
       and (p_hasta is null or coalesce(k.fecha_venta, current_date) <= p_hasta)
       and not exists (select 1 from public.comisiones_devengadas d where d.contrato_raiz_id = k.contrato_id)
  loop
    update public.contrato_closer k set equipo_id = null, manager_email = null, equipo_congelado_en = null
     where k.contrato_id = r.contrato_id;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public._equipo_recongela_sin_equipo(text, date, date) from public, anon, authenticated;

-- 4) el congelado, en las propias tablas (antes del cambio; después, para el alta de un miembro)
create or replace function public._trg_equipos_venta_congela() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if lower(coalesce(old.manager_email, '')) is distinct from lower(coalesce(new.manager_email, ''))
     or old.activo is distinct from new.activo then
    perform public._equipo_congela_ventas(old.id, null);
  end if;
  return new;
end $$;
revoke all on function public._trg_equipos_venta_congela() from public, anon, authenticated;
drop trigger if exists trg_equipos_venta_congela on public.equipos_venta;
create trigger trg_equipos_venta_congela before update on public.equipos_venta
  for each row execute function public._trg_equipos_venta_congela();

create or replace function public._trg_equipo_miembros_congela() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    perform public._equipo_congela_ventas(old.equipo_id, old.closer_email);
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    perform public._equipo_congela_ventas(new.equipo_id, new.closer_email);
    -- las congeladas sin equipo que este alta cubre, y sin devengos, se descongelan; el trigger AFTER de
    -- abajo las vuelve a congelar cuando la fila del miembro ya existe
    perform public._equipo_recongela_sin_equipo(new.closer_email, new.desde, new.hasta);
    return new;
  end if;
  return old;
end $$;
revoke all on function public._trg_equipo_miembros_congela() from public, anon, authenticated;
drop trigger if exists trg_equipo_miembros_congela on public.equipo_miembros;
create trigger trg_equipo_miembros_congela before insert or update or delete on public.equipo_miembros
  for each row execute function public._trg_equipo_miembros_congela();

-- tras el alta/edición del miembro: congela las ventas de ese closer que se quedaron sin congelar
create or replace function public._trg_equipo_miembros_recongela() returns trigger
language plpgsql security definer set search_path = '' as $$
declare r record;
begin
  for r in select k.contrato_id from public.contrato_closer k
            where lower(k.closer_email) = lower(new.closer_email) and k.equipo_congelado_en is null loop
    perform public._venta_congela_equipo(r.contrato_id);
  end loop;
  return null;
end $$;
revoke all on function public._trg_equipo_miembros_recongela() from public, anon, authenticated;
drop trigger if exists trg_equipo_miembros_recongela on public.equipo_miembros;
create trigger trg_equipo_miembros_recongela after insert or update on public.equipo_miembros
  for each row execute function public._trg_equipo_miembros_recongela();
