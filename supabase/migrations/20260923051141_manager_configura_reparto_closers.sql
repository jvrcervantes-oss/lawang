-- destructivo-ok: ningún dato se borra — DROP CONSTRAINT quita la regla «equipo exige proyecto» (se permite «todos los proyectos»), los DROP POLICY/TRIGGER IF EXISTS hacen la migración repetible.
-- El Sales Manager configura el reparto de sus closers (23-sep-2026, owner):
--   «Nosotros damos de alta el equipo de un Sales Manager y le asignamos comisión, y él
--    se encarga de configurar en cada proyecto lo que quiera a sus closers.»
--   «Las condiciones que Gus da a sus closers son para todos los proyectos.»
-- Revisión previa #53 (Seguridad, ÁMBAR, correcciones aplicadas):
--   · el manager solo escribe condiciones nivel 'closer' de un equipo ACTIVO que dirige;
--     la de manager y la estándar siguen siendo de administración;
--   · un override solo puede nombrar a un closer vigente de ese equipo (el motor, además,
--     solo mira condiciones del equipo actual del closer);
--   · con devengos, el manager no toca la condición salvo desactivarla (versionar =
--     desactivar y crear otra), ni sus tramos;
--   · vigente_desde del manager nunca en el pasado (no se reescribe lo ya evaluado);
--   · created_by lo pone la base.
--   · un devengo de closer de equipo nunca crea solicitud de pago de Lawang: ya lo
--     garantiza el CHECK comisiones_devengadas_solicitud_solo_lawang.
-- equipo_miembros sigue siendo solo de administración: estar en un equipo decide si
-- Lawang paga la estándar al closer o el % al manager — es dinero de Lawang.

-- 1. «Todos los proyectos» también para equipos
alter table public.condiciones_comision drop constraint if exists condiciones_comision_equipo_con_proyecto;
create unique index if not exists condiciones_comision_equipo_unica
  on public.condiciones_comision (equipo_id, nivel,
    coalesce(proyecto_id, '00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(lower(closer_email), ''))
  where equipo_id is not null and activo;

-- 2. motor: proyecto concreto manda sobre «todos»; override manda sobre el equipo
do $$
declare d text; n text;
begin
  d := pg_get_functiondef('public.comisiones_evaluar_contrato'::regproc);
  n := d;
  -- closer, override individual
  n := replace(n,
$a$       where c.equipo_id = v_equipo_id
         and c.proyecto_id = v_proyecto_id
         and c.nivel = 'closer'
         and c.activo
         and c.vigente_desde <= v_raiz_creada
         and lower(c.closer_email) = lower(v_closer_email)
       limit 1;$a$,
$b$       where c.equipo_id = v_equipo_id
         and (c.proyecto_id = v_proyecto_id or c.proyecto_id is null)
         and c.nivel = 'closer'
         and c.activo
         and c.vigente_desde <= v_raiz_creada
         and lower(c.closer_email) = lower(v_closer_email)
       order by (c.proyecto_id is not null) desc
       limit 1;$b$);
  -- closer, todo el equipo
  n := replace(n,
$a$         where c.equipo_id = v_equipo_id
           and c.proyecto_id = v_proyecto_id
           and c.nivel = 'closer'
           and c.activo
           and c.vigente_desde <= v_raiz_creada
           and c.closer_email is null
         limit 1;$a$,
$b$         where c.equipo_id = v_equipo_id
           and (c.proyecto_id = v_proyecto_id or c.proyecto_id is null)
           and c.nivel = 'closer'
           and c.activo
           and c.vigente_desde <= v_raiz_creada
           and c.closer_email is null
         order by (c.proyecto_id is not null) desc
         limit 1;$b$);
  -- manager
  n := replace(n,
$a$       where c.equipo_id = v_equipo_id
         and c.proyecto_id = v_proyecto_id
         and c.nivel = 'manager'
         and c.activo
         and c.vigente_desde <= v_raiz_creada
         and c.closer_email is null
       limit 1;$a$,
$b$       where c.equipo_id = v_equipo_id
         and (c.proyecto_id = v_proyecto_id or c.proyecto_id is null)
         and c.nivel = 'manager'
         and c.activo
         and c.vigente_desde <= v_raiz_creada
         and c.closer_email is null
       order by (c.proyecto_id is not null) desc
       limit 1;$b$);
  if (length(d) - length(replace(d, 'and c.proyecto_id = v_proyecto_id', ''))) / length('and c.proyecto_id = v_proyecto_id') <> 3 then
    raise exception 'el motor no tiene las 3 búsquedas de equipo esperadas: revisar a mano';
  end if;
  if position('and c.proyecto_id = v_proyecto_id' in n) > 0 then
    raise exception 'quedó alguna búsqueda de equipo sin «todos los proyectos»';
  end if;
  execute n;
end $$;

-- 3. ¿dirijo este equipo? (activo)
create or replace function public.es_manager_de_equipo(p_equipo uuid)
returns boolean language sql stable security definer set search_path to '' as $$
  select exists (select 1 from public.equipos_venta ev
                  where ev.id = p_equipo and ev.activo
                    and lower(ev.manager_email) = lower(coalesce(auth.email(), '')));
$$;
revoke all on function public.es_manager_de_equipo(uuid) from public, anon;
grant execute on function public.es_manager_de_equipo(uuid) to authenticated;

-- 4. policies del manager (se suman a las de admin)
drop policy if exists "condiciones: el manager lee las de su equipo" on public.condiciones_comision;
create policy "condiciones: el manager lee las de su equipo" on public.condiciones_comision
  for select to authenticated using (equipo_id is not null and public.es_manager_de_equipo(equipo_id));

drop policy if exists "condiciones: el manager configura a sus closers" on public.condiciones_comision;
create policy "condiciones: el manager configura a sus closers" on public.condiciones_comision
  for all to authenticated
  using (nivel = 'closer' and equipo_id is not null and public.es_manager_de_equipo(equipo_id))
  with check (nivel = 'closer' and equipo_id is not null and public.es_manager_de_equipo(equipo_id)
    and (closer_email is null or exists (
      select 1 from public.equipo_miembros em
       where em.equipo_id = condiciones_comision.equipo_id
         and lower(em.closer_email) = lower(condiciones_comision.closer_email)
         and em.desde <= current_date and (em.hasta is null or em.hasta >= current_date))));

drop policy if exists "tramos: el manager lee los de su equipo" on public.condicion_tramos;
create policy "tramos: el manager lee los de su equipo" on public.condicion_tramos
  for select to authenticated using (exists (
    select 1 from public.condiciones_comision c
     where c.id = condicion_tramos.condicion_id and c.equipo_id is not null
       and public.es_manager_de_equipo(c.equipo_id)));

drop policy if exists "tramos: el manager configura los de sus closers" on public.condicion_tramos;
create policy "tramos: el manager configura los de sus closers" on public.condicion_tramos
  for all to authenticated
  using (exists (
    select 1 from public.condiciones_comision c
     where c.id = condicion_tramos.condicion_id and c.nivel = 'closer' and c.equipo_id is not null
       and public.es_manager_de_equipo(c.equipo_id)
       and not exists (select 1 from public.comisiones_devengadas d where d.condicion_id = c.id)))
  with check (exists (
    select 1 from public.condiciones_comision c
     where c.id = condicion_tramos.condicion_id and c.nivel = 'closer' and c.equipo_id is not null
       and public.es_manager_de_equipo(c.equipo_id)
       and not exists (select 1 from public.comisiones_devengadas d where d.condicion_id = c.id)));

-- 5. candados del manager que una policy no expresa bien (fechas, historia)
create or replace function public._trg_condicion_comision_manager()
returns trigger language plpgsql security invoker set search_path to '' as $$
begin
  if tg_op in ('INSERT', 'UPDATE') then
    new.created_by := case when tg_op = 'INSERT' then coalesce(auth.email(), new.created_by) else old.created_by end;
  end if;
  -- administración y las funciones del estudio: sin candado extra
  if current_user not in ('authenticated', 'anon') or public.es_admin() then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  if tg_op = 'INSERT' then
    if new.vigente_desde < current_date then
      raise exception 'una condición nueva vale desde hoy en adelante: no se puede fechar en el pasado' using errcode = '22023';
    end if;
    return new;
  end if;
  if exists (select 1 from public.comisiones_devengadas d where d.condicion_id = old.id) then
    if tg_op = 'DELETE' then
      raise exception 'esta condición ya ha generado comisiones: desactívala en vez de borrarla' using errcode = '22023';
    end if;
    if (to_jsonb(new) - 'activo') is distinct from (to_jsonb(old) - 'activo') then
      raise exception 'esta condición ya ha generado comisiones: solo se puede desactivar; para otras cifras crea una nueva' using errcode = '22023';
    end if;
    return new;
  end if;
  if tg_op = 'UPDATE' and new.vigente_desde is distinct from old.vigente_desde and new.vigente_desde < current_date then
    raise exception 'la fecha de vigencia no puede quedar en el pasado' using errcode = '22023';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;
drop trigger if exists trg_condicion_comision_manager on public.condiciones_comision;
create trigger trg_condicion_comision_manager before insert or update or delete on public.condiciones_comision
  for each row execute function public._trg_condicion_comision_manager();
