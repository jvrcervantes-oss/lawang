-- VUELTA ATRÁS de supabase/migrations/20261014024234_cobro_primero_parcela.sql y de su 2.ª parte,
-- 20261014032925_cobro_primero_parcela_contrato.sql («primero la parcela, luego la obra»).
-- ENSAYADA EN PARTE el 14-oct-2026 en producción, dentro de un DO que acaba en raise: los permisos, el disparador
-- neutralizado, la vista y el parche inverso de comisiones. Después de eso un admin lee unidades_estado con el rol
-- authenticated (565 filas con su cobro), lw_lector la lee sin error y unidad_cobro_reparto queda cerrada (42501).
-- Antes de ese ensayo este fichero dejaba la vista con 42501 para todo el equipo: unidad_parte_cobrada_split se
-- quedaba sin permiso (revisor de código).
-- LO QUE NO SE ENSAYÓ: los tres cuerpos antiguos de abajo (unidad_parte_cobrada_interno, _split y
-- unidad_cumple_estado). Son el texto literal de pg_get_functiondef de esa mañana, pero el guardia del estudio no
-- deja pasarlos por el MCP porque leen `contratos` por join. Ejecutar este fichero de verdad pide, por lo mismo, la
-- marca del owner; y deshacer una regla de negocio en producción es decisión suya de todos modos.
-- Deja el reparto de lo cobrado como estaba el 14-oct-2026 por la mañana: el recibí cuenta como «suelo» si cuelga del
-- contrato raíz y como «obra» si cuelga de un hijo. Las cuatro funciones se reponen con el texto que devolvía
-- pg_get_functiondef ese día (copiado aquí: este fichero no depende de leer otro).
--
-- Qué NO deshace, y por qué:
--   * Las dos columnas nuevas de la vista (suelo_pactado, obra_pactada) se quedan, vacías: quitar columnas a una vista
--     obliga a borrarla y volver a darle permisos. La pantalla, sin ellas, usa el precio de catálogo.
--   * _unidad_cobro_cascada y unidad_cobro_reparto se quedan sin llamador y cerradas; el trigger
--     trg_zz_revalua_unidad_por_contrato se queda puesto pero sin efecto. Retirarlos es un drop aparte.
--   * Los estados de parcela y los devengos de comisión que la regla nueva haya movido NO vuelven solos: son datos.
--     Antes de ejecutar esto, listar qué cambió desde el 14-oct (unidades_estado_historial y comisiones_devengadas con
--     disparado_en >= '2026-10-14') y decidir con el owner qué se hace con cada uno.
begin;

create or replace function public.unidad_parte_cobrada_interno(p_unidad uuid)
 returns table(cobrado_suelo numeric, cobrado_obra numeric, obra_firmada boolean)
 language sql
 stable security definer
 set search_path to ''
as $function$
  with
  u as (select id, codigo, contrato_id, precio from public.unidades where id = p_unidad),
  raiz as (select coalesce(c.contrato_padre_id, c.id) as id from public.contratos c join u on u.contrato_id = c.id),
  hijos as (
    select h.id, h.unidad_id, h.bloqueado, h.tipo, h.parcela_codigo, coalesce(public.contrato_cobrado(h.id), 0) as cobrado
      from public.contratos h join raiz r on h.contrato_padre_id = r.id
  ),
  hermanas as (select x.id, x.codigo, x.precio from public.unidades x join u on x.contrato_id = u.contrato_id),
  hijos_obra as (select * from hijos where tipo is distinct from 'carta_reserva'),
  hijos_cr   as (select * from hijos where tipo = 'carta_reserva'),
  asignadas as (select distinct hj.unidad_id as id from hijos_obra hj where hj.unidad_id is not null),
  hermanas_sin_asignar as (select h.id, h.precio from hermanas h where not exists (select 1 from asignadas a where a.id = h.id)),
  cobrado_raiz as (select coalesce(public.contrato_cobrado(r.id), 0) as total from raiz r),
  cobrado_sin_asignar as (select coalesce(sum(hj.cobrado), 0) as total from hijos_obra hj where hj.unidad_id is null),
  cobrado_mio as (select coalesce(sum(hj.cobrado), 0) as total from hijos_obra hj where hj.unidad_id = p_unidad),
  cr_con_parcela as (
    select cr.cobrado, coalesce(cr.unidad_id, (select h.id from hermanas h where h.codigo = cr.parcela_codigo limit 1)) as unidad
      from hijos_cr cr
  ),
  cobrado_cr_mio as (select coalesce(sum(c.cobrado), 0) as total from cr_con_parcela c where c.unidad = p_unidad),
  cobrado_cr_suelto as (
    select coalesce(sum(c.cobrado), 0) as total from cr_con_parcela c
     where c.unidad is null or not exists (select 1 from hermanas h where h.id = c.unidad)
  ),
  tot_hermanas as (select count(*) n, sum(precio) suma from hermanas),
  tot_sin_asignar as (select count(*) n, sum(precio) suma from hermanas_sin_asignar),
  parte_raiz as (
    select case when (select suma from tot_hermanas) > 0 then (select total from cobrado_raiz) * (select precio from u) / (select suma from tot_hermanas)
      when (select n from tot_hermanas) > 0 then (select total from cobrado_raiz) / (select n from tot_hermanas) else 0 end as v
  ),
  parte_cr_suelta as (
    select case when (select suma from tot_hermanas) > 0 then (select total from cobrado_cr_suelto) * (select precio from u) / (select suma from tot_hermanas)
      when (select n from tot_hermanas) > 0 then (select total from cobrado_cr_suelto) / (select n from tot_hermanas) else 0 end as v
  ),
  parte_sin_asignar as (
    select case when not exists (select 1 from hermanas_sin_asignar where id = p_unidad) then 0
      when (select suma from tot_sin_asignar) > 0 then (select total from cobrado_sin_asignar) * (select precio from u) / (select suma from tot_sin_asignar)
      when (select n from tot_sin_asignar) > 0 then (select total from cobrado_sin_asignar) / (select n from tot_sin_asignar) else 0 end as v
  ),
  obra_firmada as (
    select exists (select 1 from hijos hj where exists (select 1 from public.contrato_tipo_etapa e where e.tipo = hj.tipo and e.es_obra) and hj.bloqueado = true
         and (hj.unidad_id = p_unidad or (hj.unidad_id is null and exists (select 1 from hermanas_sin_asignar where id = p_unidad)))) as v
  )
  select
    coalesce((select v from parte_raiz), 0) + coalesce((select total from cobrado_cr_mio), 0) + coalesce((select v from parte_cr_suelta), 0) as cobrado_suelo,
    coalesce((select v from parte_sin_asignar), 0) + coalesce((select total from cobrado_mio), 0) as cobrado_obra,
    coalesce((select v from obra_firmada), false) as obra_firmada;
$function$;

create or replace function public.unidad_parte_cobrada_split(p_unidad uuid)
 returns table(cobrado_suelo numeric, cobrado_obra numeric, obra_firmada boolean)
 language sql
 stable security definer
 set search_path to ''
as $function$
  with permiso as (
    select (u0.contrato_id is null
            or public.es_suyo(c0.creado_por)
            or public.puede_ver_contrato(c0.id)
            or public.es_admin_de(public.empresa_de_unidad(p_unidad))) as ok
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
    select h.id, h.unidad_id, h.bloqueado, h.tipo, coalesce(public.contrato_cobrado(h.id), 0) as cobrado
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
       where hj.bloqueado = true and exists (select 1 from public.contrato_tipo_etapa e where e.tipo = hj.tipo and e.es_obra)
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

create or replace function public.unidad_cumple_estado(p_unidad uuid, p_estado text, p_precio numeric, p_precio_suelo numeric)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  select case p_estado
    when 'cobrada' then coalesce(p_precio, 0) > 0
         and coalesce((select x.cobrado_suelo + x.cobrado_obra
                         from public.unidad_parte_cobrada_interno(p_unidad) x), 0) >= p_precio
    when 'vendida' then coalesce(p_precio_suelo, 0) > 0
         and coalesce((select x.cobrado_suelo
                         from public.unidad_parte_cobrada_interno(p_unidad) x), 0) >= p_precio_suelo
    else true
  end;
$function$;

-- PERMISOS. La migración quitó a unidad_parte_cobrada_split el permiso de authenticated y lw_lector, y
-- `create or replace` conserva la ACL: sin devolvérselo, la vista (security_invoker) da 42501 a todo el equipo.
grant execute on function public.unidad_parte_cobrada_split(uuid) to authenticated, lw_lector;
-- unidad_cobro_reparto se queda sin llamador: cerrada.
revoke execute on function public.unidad_cobro_reparto(uuid) from authenticated, lw_lector;

-- EL DISPARADOR de la 2.ª parte se neutraliza (su función pasa a no hacer nada): con el estado medido otra vez
-- contra el catálogo, quien revisa la parcela es trg_revalua_unidad_por_precio, como antes. Quitar el trigger del
-- todo es un borrado aparte.
create or replace function public.trg_revalua_unidad_por_contrato()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  return new;   -- neutralizado por vuelta.sql
end;
$function$;

-- La vista vuelve a leer unidad_parte_cobrada_split; las dos columnas nuevas se quedan, vacías.
create or replace view public.unidades_estado with (security_invoker = true) as
 SELECT u.id,
    u.codigo,
    u.proyecto,
    u.tipo,
    u.superficie_m2,
    COALESCE(u.precio, NULLIF(COALESCE(u.precio_suelo, 0::numeric) + COALESCE(u.precio_construccion, 0::numeric), 0::numeric)) AS precio,
    u.moneda,
    u.estado,
    u.contrato_id,
    u.notas,
    u.created_at,
    u.precio_suelo,
    u.precio_construccion,
    u.modelo,
    u.obra_fase,
    u.obra_fecha_entrega,
    u.obra_actualizado,
    c.numero AS contrato_numero,
    c.comprador_nombre,
    c.bloqueado AS contrato_firmado,
    cp.cobrado_suelo + cp.cobrado_obra AS facturado,
        CASE
            WHEN cp.cobrado_suelo IS NULL THEN NULL::numeric
            WHEN COALESCE(u.precio, NULLIF(COALESCE(u.precio_suelo, 0::numeric) + COALESCE(u.precio_construccion, 0::numeric), 0::numeric)) > 0::numeric THEN round((cp.cobrado_suelo + cp.cobrado_obra) / COALESCE(u.precio, NULLIF(COALESCE(u.precio_suelo, 0::numeric) + COALESCE(u.precio_construccion, 0::numeric), 0::numeric)) * 100::numeric, 1)
            ELSE NULL::numeric
        END AS pct_cobrado,
    u.fase_masterplan,
    u.zona_masterplan,
    u.precio AS precio_guardado,
    c.creado_por AS contrato_creado_por,
    cp.cobrado_suelo,
    cp.cobrado_obra,
    cp.obra_firmada,
    u.codigo_orden,
    c.id IS NOT NULL AND (EXISTS ( SELECT 1
           FROM public.contrato_tipo_etapa e
          WHERE e.tipo = c.tipo AND e.etapa = 'reserva'::text AND e.tipo <> 'reserva_parcela'::text)) AS contrato_es_carta,
    u.proyecto_id,
    NULL::numeric AS suelo_pactado,
    NULL::numeric AS obra_pactada
   FROM public.unidades u
     LEFT JOIN public.contratos c ON c.id = u.contrato_id
     LEFT JOIN LATERAL public.unidad_parte_cobrada_split(u.id) cp(cobrado_suelo, cobrado_obra, obra_firmada) ON true;

-- El motor de comisiones vuelve a leer unidad_parte_cobrada_interno y el precio de catálogo.
do $parche$
declare
  v_def text;
  m1 text := 'public._unidad_cobro_cascada(u.id) cp';
  r1 text := 'public.unidad_parte_cobrada_interno(u.id) cp';
  m2 text := 'coalesce(sum(case when cp.suelo_de_contrato then cp.suelo_precio else u.precio_suelo end), 0)';   -- la de la 2.ª parte
  r2 text := 'coalesce(sum(u.precio_suelo), 0)';
  m3 text := 'coalesce(sum(coalesce(cp.obra_precio, u.precio_construccion)), 0)';
  r3 text := 'coalesce(sum(u.precio_construccion), 0)';
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'comisiones_evaluar_contrato';
  if position(m1 in v_def) = 0 and position(m2 in v_def) = 0 and position(m3 in v_def) = 0 then
    return;   -- ya estaba como antes
  end if;
  if (length(v_def) - length(replace(v_def, m1, ''))) / length(m1) <> 1
     or (length(v_def) - length(replace(v_def, m2, ''))) / length(m2) <> 1
     or (length(v_def) - length(replace(v_def, m3, ''))) / length(m3) <> 1 then
    raise exception 'vuelta cobro_primero_parcela: comisiones_evaluar_contrato no tiene las tres marcas una vez cada una; revisar a mano';
  end if;
  execute replace(replace(replace(v_def, m1, r1), m2, r2), m3, r3);
end
$parche$;

commit;
