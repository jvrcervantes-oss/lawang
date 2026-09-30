-- destructivo-ok: el único DELETE es el del trigger nuevo, que borra el alcance de un techo en un proyecto cuando esa casa deja de venderse allí (filas de la tabla puente de hoy, sin datos de cliente).
-- Techos (3ª vuelta, 30-sep-2026) — consultas de deploy Administración + Datos sobre el diff.
-- 1. Ancla 2026 = techo ACTIVO más barato (antes la base del modelo), igual que 2027: con dos anclas de distinta
--    naturaleza el «desde» de un proyecto con precio propio podía moverse el 1-ene (Administración). Con el
--    invariante de hoy (base = el más barato) la cifra no cambia. Las dos anclas son sobre TODOS los techos activos
--    del modelo, no solo los ofrecidos en el proyecto (Administración: si no, el 1-ene se regalaría la diferencia).
-- 2. Todo techo activo lleva precio 2027 (el 1-ene-2027 se cobra ese): va al invariante diferido.
-- 3. Al quitar una casa de un proyecto, su alcance en ese proyecto se borra: si no, al volver a añadirla los techos
--    limitados reaparecerían allí sin que nadie lo decidiera (Datos).

create or replace function public._modelo_techos_opciones(p_modelo_id uuid, p_proyecto_id uuid)
returns table(techo_id uuid, clave text, nombre text, precio numeric, moneda text, tramo text)
language sql
stable
security definer
set search_path = ''
as $$
  with base as (
    select m.moneda as m_moneda,
           mv.precio_construccion as propio,
           coalesce(mv.precio_construccion, m.precio_construccion) as efectivo,
           case when mv.precio_construccion is not null then coalesce(mv.moneda, m.moneda) else m.moneda end as moneda
      from public.modelos m
      left join public.modelos_villa mv
        on mv.modelo_id = m.id and mv.proyecto_id = p_proyecto_id and mv.precio_construccion is not null
     where m.id = p_modelo_id
  ), tramo as (select public.catalogo_tramo_activo() as t),
  minimos as (
    select min(th.precio_ahora) as a26, min(th.precio_2027) as a27
      from public.modelo_techos th where th.modelo_id = p_modelo_id and th.activo
  ), vivos as (
    select th.* from public.modelo_techos th
     where th.modelo_id = p_modelo_id and th.activo
       and (th.alcance = 'todos'
            or exists (select 1 from public.modelo_techo_proyectos tp
                        where tp.techo_id = th.id and tp.proyecto_id = p_proyecto_id))
  )
  (
    select v.id, v.clave, v.nombre,
           case when tramo.t = '2026' then v.precio_ahora + coalesce(base.propio - minimos.a26, 0)
                else v.precio_2027 + coalesce(base.propio - minimos.a27, 0) end,
           base.m_moneda, tramo.t
      from vivos v, base, tramo, minimos
     where case when tramo.t = '2026' then v.precio_ahora else v.precio_2027 end is not null
     order by v.orden nulls last, v.nombre
  )
  union all
  (
    select p_modelo_id, 'ulin'::text, 'Ulin'::text, base.efectivo, base.moneda, tramo.t
      from base, tramo
     where base.efectivo is not null
       and not exists (select 1 from public.modelo_techos th where th.modelo_id = p_modelo_id)
  )
$$;

create or replace function public._techos_invariantes_modelo(p_modelo uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_base numeric; v_nombre text; v_mal text;
begin
  if p_modelo is null then return; end if;
  if not exists (select 1 from public.modelo_techos t where t.modelo_id = p_modelo) then return; end if;
  select m.precio_construccion, m.nombre into v_base, v_nombre from public.modelos m where m.id = p_modelo;
  if not found then return; end if;
  if exists (select 1 from public.modelo_techos t where t.modelo_id = p_modelo and t.activo) then
    if v_base is null then
      raise exception '«%» tiene techos y se ha quedado sin precio base: pon la base (el precio de su techo más barato).', v_nombre using errcode = '23514';
    end if;
    select string_agg(t.nombre || ' (' || t.precio_ahora || ')', ', ') into v_mal
      from public.modelo_techos t where t.modelo_id = p_modelo and t.activo and t.precio_ahora < v_base;
    if v_mal is not null then
      raise exception 'En «%» hay techos por debajo del precio base (%): %. Si quieres un techo más barato, baja antes la base; si subes la base, mueve también los techos.',
        v_nombre, v_base, v_mal using errcode = '23514';
    end if;
    select string_agg(t.nombre, ', ') into v_mal
      from public.modelo_techos t where t.modelo_id = p_modelo and t.activo and t.precio_2027 is null;
    if v_mal is not null then
      raise exception 'En «%» hay techos que se ofrecen sin precio 2027: %. Desde el 1-ene-2027 se cobra ese precio: ponlo o retira el techo.',
        v_nombre, v_mal using errcode = '23514';
    end if;
  end if;
  select string_agg(p.nombre, ', ' order by p.nombre) into v_mal
    from public.modelos_villa mv join public.proyectos p on p.id = mv.proyecto_id
   where mv.modelo_id = p_modelo
     and not exists (select 1 from public.modelo_techos t
                      where t.modelo_id = p_modelo and t.activo
                        and (t.alcance = 'todos'
                             or exists (select 1 from public.modelo_techo_proyectos tp
                                         where tp.techo_id = t.id and tp.proyecto_id = mv.proyecto_id)));
  if v_mal is not null then
    raise exception 'Con este cambio «%» se quedaría sin ningún techo en: %. Un contrato de Construcción necesita techo: deja al menos uno para ese proyecto.',
      v_nombre, v_mal using errcode = '23514';
  end if;
end $$;

create or replace function public._techos_alcance_sin_casa()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.modelo_techo_proyectos tp
   using public.modelo_techos t
   where t.id = tp.techo_id and t.modelo_id = old.modelo_id and tp.proyecto_id = old.proyecto_id;
  return old;
end $$;
revoke all on function public._techos_alcance_sin_casa() from public, anon, authenticated;
drop trigger if exists techos_alcance_sin_casa on public.modelos_villa;
create trigger techos_alcance_sin_casa after delete on public.modelos_villa
  for each row execute function public._techos_alcance_sin_casa();
