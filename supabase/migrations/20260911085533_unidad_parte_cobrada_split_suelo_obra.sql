-- Divide unidad_parte_cobrada() (que ya sumaba correctamente el Bloqueo/Carta
-- + los hijos de Construccion, prorateados cuando cubren varias parcelas) en
-- suelo/obra por separado, para la barra de recaudacion por parcela de
-- v4/proyectos. Mismas CTEs exactas de la funcion original -- no se reinventa
-- el reparto, solo se devuelve partido en vez de sumado. unidad_parte_cobrada
-- pasa a llamar a esta, asi nunca pueden divergir (norma de la suite: una
-- formula de dinero en un solo sitio).
create or replace function public.unidad_parte_cobrada_split(p_unidad uuid)
returns table(cobrado_suelo numeric, cobrado_obra numeric, obra_firmada boolean)
language sql stable security definer set search_path = ''
as $$
  with u as (
    select id, contrato_id, precio from public.unidades where id = p_unidad
  ),
  raiz as (
    select coalesce(c.contrato_padre_id, c.id) as id
      from public.contratos c join u on u.contrato_id = c.id
  ),
  hijos as (
    select h.id, h.unidad_id, h.bloqueado, coalesce(public.contrato_cobrado(h.id), 0) as cobrado
      from public.contratos h join raiz r on h.contrato_padre_id = r.id
  ),
  hermanas as (
    select x.id, x.precio
      from public.unidades x join u on x.contrato_id = u.contrato_id
  ),
  asignadas as (
    select distinct hj.unidad_id as id from hijos hj where hj.unidad_id is not null
  ),
  hermanas_sin_asignar as (
    select h.id, h.precio from hermanas h
     where not exists (select 1 from asignadas a where a.id = h.id)
  ),
  cobrado_raiz as (
    select coalesce(public.contrato_cobrado(r.id), 0) as total from raiz r
  ),
  cobrado_sin_asignar as (
    select coalesce(sum(hj.cobrado), 0) as total from hijos hj where hj.unidad_id is null
  ),
  cobrado_mio as (
    select coalesce(sum(hj.cobrado), 0) as total from hijos hj where hj.unidad_id = p_unidad
  ),
  tot_hermanas as (select count(*) n, sum(precio) suma from hermanas),
  tot_sin_asignar as (select count(*) n, sum(precio) suma from hermanas_sin_asignar),
  parte_raiz as (
    select case
      when (select suma from tot_hermanas) > 0
        then (select total from cobrado_raiz) * (select precio from u) / (select suma from tot_hermanas)
      when (select n from tot_hermanas) > 0
        then (select total from cobrado_raiz) / (select n from tot_hermanas)
      else 0
    end as v
  ),
  parte_sin_asignar as (
    select case
      when not exists (select 1 from hermanas_sin_asignar where id = p_unidad) then 0
      when (select suma from tot_sin_asignar) > 0
        then (select total from cobrado_sin_asignar) * (select precio from u) / (select suma from tot_sin_asignar)
      when (select n from tot_sin_asignar) > 0
        then (select total from cobrado_sin_asignar) / (select n from tot_sin_asignar)
      else 0
    end as v
  ),
  obra_firmada as (
    select exists (
      select 1 from hijos hj
       where hj.bloqueado = true
         and (hj.unidad_id = p_unidad
              or (hj.unidad_id is null and exists (select 1 from hermanas_sin_asignar where id = p_unidad)))
    ) as v
  )
  select
    coalesce((select v from parte_raiz), 0) as cobrado_suelo,
    coalesce((select v from parte_sin_asignar), 0) + coalesce((select total from cobrado_mio), 0) as cobrado_obra,
    coalesce((select v from obra_firmada), false) as obra_firmada;
$$;

-- unidad_parte_cobrada ahora es un envoltorio de la version partida: misma
-- salida de siempre (el total), pero calculada una sola vez.
create or replace function public.unidad_parte_cobrada(p_unidad uuid)
returns numeric
language sql stable security definer set search_path = ''
as $$
  select coalesce(cobrado_suelo, 0) + coalesce(cobrado_obra, 0)
    from public.unidad_parte_cobrada_split(p_unidad);
$$;

revoke all on function public.unidad_parte_cobrada_split(uuid) from public, anon;
grant execute on function public.unidad_parte_cobrada_split(uuid) to authenticated;
