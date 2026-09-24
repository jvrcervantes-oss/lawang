-- Cobrado por parcela: la Carta de Reserva hija de una RP cuenta como SUELO (24-sep-2026).
--
-- Síntoma (owner): «B8 Bonian debería salir cobrada entera, le faltan 1.000 €»
-- (REC00111). La cadena es RP00122 (raíz, suelo 64.565) ← CR00035 (Carta, hija,
-- sin unidad_id) + CC00078 (Construcción, hija, con unidad_id = B8). La función
-- trataba a TODA hija como obra: la hija sin unidad_id reparte su cobrado entre
-- las parcelas "sin asignar", y como B8 ya tiene su Construcción asignada, el
-- 1.000 € de la Carta no caía en ninguna parcela. Donde no había Construcción
-- (C4, C5, Mejan B2–B7, C5 S7) caía, pero como OBRA.
--
-- Una Carta (tipo con etapa 'reserva' en contrato_tipo_etapa, catálogo real —
-- nunca una lista a mano) es depósito de la parcela: se suma a lo cobrado de la
-- raíz y se reparte como suelo entre sus parcelas. El resto de hijas no cambia.

create or replace function public.unidad_parte_cobrada_split(p_unidad uuid)
 returns table(cobrado_suelo numeric, cobrado_obra numeric, obra_firmada boolean)
 language sql
 stable security definer
 set search_path to ''
as $function$
  with permiso as (
    select (u0.contrato_id is null
            or public.es_suyo(c0.creado_por)
            or public.es_manager_de(c0.proyecto_id)
            or public.es_admin()) as ok
      from public.unidades u0
      left join public.contratos c0 on c0.id = u0.contrato_id
     where u0.id = p_unidad
  ),
  u as (
    select id, contrato_id, precio from public.unidades where id = p_unidad
  ),
  raiz as (
    select coalesce(c.contrato_padre_id, c.id) as id
      from public.contratos c join u on u.contrato_id = c.id
  ),
  tipos_carta as (
    select tipo from public.contrato_tipo_etapa where etapa = 'reserva'
  ),
  cartas_hijas as (
    select coalesce(sum(coalesce(public.contrato_cobrado(h.id), 0)), 0) as total
      from public.contratos h join raiz r on h.contrato_padre_id = r.id
     where h.tipo in (select tipo from tipos_carta)
  ),
  hijos as (
    select h.id, h.unidad_id, h.bloqueado, coalesce(public.contrato_cobrado(h.id), 0) as cobrado
      from public.contratos h join raiz r on h.contrato_padre_id = r.id
     where h.tipo not in (select tipo from tipos_carta)
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
    select coalesce(public.contrato_cobrado(r.id), 0) + (select total from cartas_hijas) as total from raiz r
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
    case when coalesce((select ok from permiso), false)
      then coalesce((select v from parte_raiz), 0) end as cobrado_suelo,
    case when coalesce((select ok from permiso), false)
      then coalesce((select v from parte_sin_asignar), 0) + coalesce((select total from cobrado_mio), 0) end as cobrado_obra,
    case when coalesce((select ok from permiso), false)
      then coalesce((select v from obra_firmada), false) end as obra_firmada;
$function$;
