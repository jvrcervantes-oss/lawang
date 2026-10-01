-- La señal pagada en la Carta de Reserva (hija del RP por contrato_padre_id) es SUELO de su parcela.
--
-- Hasta hoy `unidad_parte_cobrada_interno` trataba toda hija del RP como obra: sin parcela asignada
-- (`unidad_id` null, que es lo normal en una CR) su cobro iba a `cobrado_sin_asignar`, y ese
-- reparto solo lo recibe una parcela SIN Contrato de Construcción asignado. Bonian B8 (1-oct-2026):
-- RP00122 con 63.565 € de suelo + 1.000 € de señal en CR00035 = 64.565 € = precio_suelo, y la
-- parcela seguía «bloqueada» porque la señal no llegaba a ningún sitio (la CC00078 ya la tenía
-- asignada). El total cobrado (suelo+obra) NO cambia: solo se mueve de obra/perdido a suelo.
--
-- A qué parcela va la CR: `unidad_id` si lo trae; si no, su `parcela_codigo`; si no encaja con
-- ninguna hermana del RP, se reparte entre las hermanas por precio (igual que el cobro del RP).
create or replace function public.unidad_parte_cobrada_interno(p_unidad uuid)
 returns table(cobrado_suelo numeric, cobrado_obra numeric, obra_firmada boolean)
 language sql
 stable security definer
 set search_path to ''
as $function$
  with
  u as (
    select id, codigo, contrato_id, precio from public.unidades where id = p_unidad
  ),
  raiz as (
    select coalesce(c.contrato_padre_id, c.id) as id
      from public.contratos c join u on u.contrato_id = c.id
  ),
  hijos as (
    select h.id, h.unidad_id, h.bloqueado, h.tipo, h.parcela_codigo,
           coalesce(public.contrato_cobrado(h.id), 0) as cobrado
      from public.contratos h join raiz r on h.contrato_padre_id = r.id
  ),
  hermanas as (
    select x.id, x.codigo, x.precio
      from public.unidades x join u on x.contrato_id = u.contrato_id
  ),
  -- Las CR no son obra: su cobro es suelo y se reparte aparte.
  hijos_obra as (select * from hijos where tipo is distinct from 'carta_reserva'),
  hijos_cr   as (select * from hijos where tipo = 'carta_reserva'),
  asignadas as (
    select distinct hj.unidad_id as id from hijos_obra hj where hj.unidad_id is not null
  ),
  hermanas_sin_asignar as (
    select h.id, h.precio from hermanas h
     where not exists (select 1 from asignadas a where a.id = h.id)
  ),
  cobrado_raiz as (
    select coalesce(public.contrato_cobrado(r.id), 0) as total from raiz r
  ),
  cobrado_sin_asignar as (
    select coalesce(sum(hj.cobrado), 0) as total from hijos_obra hj where hj.unidad_id is null
  ),
  cobrado_mio as (
    select coalesce(sum(hj.cobrado), 0) as total from hijos_obra hj where hj.unidad_id = p_unidad
  ),
  -- CR con parcela propia (unidad_id o parcela_codigo que casa con una hermana) o sin ella.
  cr_con_parcela as (
    select cr.cobrado,
           coalesce(cr.unidad_id,
                    (select h.id from hermanas h where h.codigo = cr.parcela_codigo limit 1)) as unidad
      from hijos_cr cr
  ),
  cobrado_cr_mio as (
    select coalesce(sum(c.cobrado), 0) as total from cr_con_parcela c where c.unidad = p_unidad
  ),
  cobrado_cr_suelto as (
    select coalesce(sum(c.cobrado), 0) as total from cr_con_parcela c
     where c.unidad is null or not exists (select 1 from hermanas h where h.id = c.unidad)
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
  parte_cr_suelta as (
    select case
      when (select suma from tot_hermanas) > 0
        then (select total from cobrado_cr_suelto) * (select precio from u) / (select suma from tot_hermanas)
      when (select n from tot_hermanas) > 0
        then (select total from cobrado_cr_suelto) / (select n from tot_hermanas)
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
      select 1 from hijos_obra hj
       where hj.bloqueado = true
         and (hj.unidad_id = p_unidad
              or (hj.unidad_id is null and exists (select 1 from hermanas_sin_asignar where id = p_unidad)))
    ) as v
  )
  select
    coalesce((select v from parte_raiz), 0)
      + coalesce((select total from cobrado_cr_mio), 0)
      + coalesce((select v from parte_cr_suelta), 0) as cobrado_suelo,
    coalesce((select v from parte_sin_asignar), 0) + coalesce((select total from cobrado_mio), 0) as cobrado_obra,
    coalesce((select v from obra_firmada), false) as obra_firmada;
$function$;
