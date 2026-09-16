-- 'vendida' hoy se dispara con CUALQUIER cobro (suelo+obra combinados) via
-- unidad_parte_cobrada() -> unidad_parte_cobrada_split(), que lleva un gate de
-- permiso (es_suyo/es_manager_de/es_admin) pensado para lectura desde la UI.
-- El trigger de la escalera necesita ver el cobro real SIEMPRE, sin importar
-- quien registro el recibi -- por eso esta version interna, sin el gate,
-- nunca expuesta a anon/authenticated.
CREATE FUNCTION public.unidad_parte_cobrada_interno(p_unidad uuid)
 RETURNS TABLE(cobrado_suelo numeric, cobrado_obra numeric, obra_firmada boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with
  u as (
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
$function$;

REVOKE EXECUTE ON FUNCTION public.unidad_parte_cobrada_interno(uuid) FROM PUBLIC;

COMMENT ON FUNCTION public.unidad_parte_cobrada_interno(uuid) IS
  'Uso interno de avanza_unidad_por_cobro() unicamente. Mismo calculo que unidad_parte_cobrada_split() pero SIN el gate de permiso -- nunca conceder EXECUTE a anon/authenticated, expondria el cobro real de cualquier unidad a cualquier sesion.';

-- La regla de negocio (confirmada por el owner, 16-sep-2026): 'vendida' exige
-- el SUELO cobrado al 100%, no cualquier cobro combinado con obra. Antes de
-- este fix, un pago solo de construccion marcaba 'vendida' con el suelo a
-- 0% (caso real: Bonian Village A4, 33.200 EUR de obra cobrados, 0 EUR de
-- suelo). Efecto FORWARD-ONLY: esta funcion solo corre cuando llega un
-- movimiento de caja nuevo, asi que los casos ya mal marcados NO cambian
-- solos -- retrocederlos es una decision de datos de produccion aparte,
-- pendiente confirmacion del owner (algunos ya tienen proformas emitidas
-- apoyadas en el estado 'vendida'), no responsabilidad de este fix. Y como
-- este CASE no tiene ninguna rama que retroceda de 'vendida'/'cobrada' hacia
-- atras, esos casos existentes se quedan en 'vendida' para siempre aunque
-- vuelva a haber movimiento de caja -- necesitan un UPDATE manual aparte.
CREATE OR REPLACE FUNCTION public.avanza_unidad_por_cobro(p_contrato_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_raiz_id uuid;
  v_mon     text;
  v_nmon    int;
  v_mezcla  boolean;
begin
  if p_contrato_id is null then return; end if;

  select coalesce(contrato_padre_id, id) into v_raiz_id
    from public.contratos where id = p_contrato_id;
  if v_raiz_id is null then return; end if;

  select min(u.moneda), count(distinct u.moneda)
    into v_mon, v_nmon
    from public.unidades u where u.contrato_id = v_raiz_id;
  if coalesce(v_nmon, 0) > 1 then return; end if;

  select exists (
    select 1 from public.facturas f
     where f.tipo = 'recibi' and not coalesce(f.anulada, false)
       and (f.contrato_id = v_raiz_id
            or f.contrato_id in (select hijo.id from public.contratos hijo where hijo.contrato_padre_id = v_raiz_id))
       and f.moneda is distinct from v_mon
    union all
    select 1 from public.recibi_aplicaciones ra
      join public.facturas r   on r.id = ra.recibi_id
      join public.facturas fac on fac.id = ra.factura_id
     where not coalesce(r.anulada, false) and not coalesce(fac.anulada, false)
       and (fac.contrato_id = v_raiz_id
            or fac.contrato_id in (select hijo.id from public.contratos hijo where hijo.contrato_padre_id = v_raiz_id))
       and r.moneda is distinct from v_mon
  ) into v_mezcla;
  if v_mezcla then return; end if;

  update public.unidades u
     set estado = case
           when u.estado = 'no_disponible' then u.estado
           when u.estado = 'bloqueada' and not exists (
                  select 1 from public.contratos c2
                   where c2.id = u.contrato_id
                     and c2.tipo = 'reserva_parcela' and coalesce(c2.bloqueado, false)
                ) then u.estado
           when u.estado not in ('bloqueada', 'vendida', 'cobrada') then u.estado
           when coalesce(u.precio, 0) > 0
                and (select cobrado_suelo + cobrado_obra from public.unidad_parte_cobrada_interno(u.id)) >= u.precio
                then 'cobrada'
           when coalesce(u.precio_suelo, 0) > 0
                and (select cobrado_suelo from public.unidad_parte_cobrada_interno(u.id)) >= u.precio_suelo
                then 'vendida'
           else u.estado
         end
   where u.contrato_id = v_raiz_id;
end;
$function$;
