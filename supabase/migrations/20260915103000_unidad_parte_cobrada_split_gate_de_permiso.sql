-- LAW-186 mitad B, segunda pieza (15-sep-2026): el RPC directo saltaba la vista entera
--
-- QUE PASABA. El fix anterior (20260915100000) protegio `unidades_estado`, el camino
-- normal de la pantalla. Pero `unidad_parte_cobrada_split(p_unidad uuid)` es
-- SECURITY DEFINER **sin ningun chequeo de permiso dentro**, y `get_advisors` avisa de
-- que PostgREST la publica en `/rest/v1/rpc/unidad_parte_cobrada_split` para el rol
-- `authenticated`. Verificado con impersonacion real contra la base (no solo leyendo
-- el advisor): un agente sin relacion con el contrato de una parcela, llamando al RPC
-- DIRECTAMENTE (sin pasar por la vista), recibe el cobro real —
-- `{"cobrado_obra":33200,"obra_firmada":false,"cobrado_suelo":0}` para RP00040, un
-- contrato ajeno. El fix de la vista no protege este camino porque no lo toca.
--
-- NO se revoca EXECUTE a `authenticated`: la propia vista, con security_invoker=true,
-- necesita que `authenticated` pueda ejecutar la funcion para que la vista siga
-- funcionando desde la pantalla — revocarlo habria roto el camino que SI hay que
-- dejar pasar. El gate va DENTRO de la funcion, que es donde vive el privilegio real
-- (SECURITY DEFINER), no en el GRANT.
--
-- MISMO CRITERIO que ya usa la vista, en UN solo sitio (no dos copias que puedan
-- divergir): visible si la unidad no tiene contrato (nada que ocultar), o si quien
-- llama es el autor/manager del contrato de ESA unidad, o admin. Las CTE internas
-- (raiz, hijos, hermanas...) NO se tocan: siguen agregando la cadena completa para
-- quien SI tiene permiso, exactamente igual que antes -- solo se envuelve el SELECT
-- final en un `case` que devuelve NULL cuando no hay permiso, en vez de recalcular
-- nada distinto.
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
    case when coalesce((select ok from permiso), false)
      then coalesce((select v from parte_raiz), 0) end as cobrado_suelo,
    case when coalesce((select ok from permiso), false)
      then coalesce((select v from parte_sin_asignar), 0) + coalesce((select total from cobrado_mio), 0) end as cobrado_obra,
    case when coalesce((select ok from permiso), false)
      then coalesce((select v from obra_firmada), false) end as obra_firmada;
$function$;

-- Su envoltorio de conveniencia (devuelve la suma como un solo numero, sin desglose):
-- antes hacia `coalesce(cobrado_suelo,0) + coalesce(cobrado_obra,0)`, que habria
-- convertido el NULL de "sin permiso" en un 0 que parece "nada cobrado" -- la misma
-- ambiguedad que el prompt de Desarrollo prohibe (estado vacio = "no hay nada" vs
-- "no he podido mirar", tienen que verse distinto). Sin el coalesce, NULL + NULL
-- sigue siendo NULL y el "no visible" llega intacto a quien lo consuma.
create or replace function public.unidad_parte_cobrada(p_unidad uuid)
returns numeric
language sql
stable security definer
set search_path to ''
as $function$
  select cobrado_suelo + cobrado_obra
    from public.unidad_parte_cobrada_split(p_unidad);
$function$;
