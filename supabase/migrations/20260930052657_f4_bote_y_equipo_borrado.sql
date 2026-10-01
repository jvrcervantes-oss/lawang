-- F4 «comisión oculta» (30-sep-2026), últimos ajustes pedidos por Seguridad y Datos en la consulta de deploy.
-- Escrita sobre los cuerpos VIVOS (pg_get_functiondef / pg_policies del 30-sep). El motor no se toca.
--
-- 1 · _solicitud_puede_tocar: el creador toca su solicitud pendiente, SALVO si es automática. El disparador del
--     recálculo corre en la sesión de quien edita, así que una solicitud del bote del SM puede quedar con
--     creado_por = el closer; la policy de lectura ya lo excluía (origen is distinct from 'comision_automatica'),
--     pero anular/editar seguía abierto por esta función. Ahora las dos dicen lo mismo.
-- 2 · comision_visible (4 args) y la policy «condiciones_comision: leer»: en los niveles de equipo, si la fila del
--     equipo no existe, la comisión NO se ve (coalesce(..., false)). contrato_closer.equipo_id no tiene FK: un equipo
--     borrado dejaba el subselect en null y el coalesce(..., true) la hacía visible. Sin equipo (null) se sigue viendo
--     la propia, como antes. closers_ven_comision es NOT NULL: el coalesce solo actúa cuando falta la fila.
--     (En condiciones_comision equipo_id sí tiene FK con cascade: allí es coherencia, no un agujero abierto.)
-- 3 · mi_condicion_comision: sin cambio de lógica, solo su comentario (decisión del owner).

create or replace function public._solicitud_puede_tocar(s public.solicitudes_pago)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  -- = policy «solicitudes: admin resuelve, el creador toca la suya pendiente» (USING); la automática no es «suya»
  select (public.es_admin() and public.puede('comisiones'))
      or (s.creado_por = (select auth.uid()) and s.estado = 'pendiente'
          and s.origen is distinct from 'comision_automatica')
$function$;

comment on function public._solicitud_puede_tocar(public.solicitudes_pago) is
  'F4 (30-sep-2026): ¿quien consulta puede anular/editar esta solicitud? Admin con casilla, o su creador si sigue pendiente y NO es automatica (origen comision_automatica: el recalculo la crea en la sesion del closer, pero es del bote de su SM).';

create or replace function public.comision_visible(p_nivel text, p_beneficiario text, p_condicion uuid, p_raiz uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  with yo as (select lower(coalesce(auth.email(), '')) as e),
  eq as (
    select (select c.equipo_id from public.condiciones_comision c where c.id = p_condicion) as de_condicion,
           (select k.equipo_id from public.contrato_closer k where k.contrato_id = p_raiz) as congelado
  )
  select yo.e <> '' and (
       (public.es_admin() and public.puede('comisiones_reparto'))
    or (p_nivel in ('closer', 'setter', 'team_lead') and (
          public.es_manager_de_equipo(eq.de_condicion)
          or public.es_manager_de_equipo(eq.congelado)
          or (lower(coalesce(p_beneficiario, '')) = yo.e
              and (coalesce(eq.congelado, eq.de_condicion) is null
                   or coalesce((select ev.closers_ven_comision from public.equipos_venta ev
                                 where ev.id = coalesce(eq.congelado, eq.de_condicion)), false)))))
    or (p_nivel not in ('closer', 'setter', 'team_lead') and lower(coalesce(p_beneficiario, '')) = yo.e)
  )
  from yo, eq
$function$;

alter policy "condiciones_comision: leer" on public.condiciones_comision
  to authenticated, lw_lector
  using (
    public.es_admin()
    or (nivel = any (array['closer', 'setter', 'team_lead'])
        and lower(coalesce(closer_email, '')) = lower(coalesce((select auth.email()), '-'))
        and (equipo_id is null
             or coalesce((select ev.closers_ven_comision from public.equipos_venta ev
                           where ev.id = condiciones_comision.equipo_id), false)))
    or (nivel = 'manager'
        and exists (select 1 from public.equipos_venta ev
                     where ev.id = condiciones_comision.equipo_id
                       and lower(ev.manager_email) = lower(coalesce((select auth.email()), '-'))))
  );

comment on function public.mi_condicion_comision() is
  'LAW-461 (30-sep-2026): la condicion de comision que el motor aplicaria hoy a quien consulta; sin cifras si su SM oculta la comision. Con interruptor encendido ensena la condicion generica del equipo si el closer no tiene personal: es su comision (decision owner 30-sep). Llamador: datos.js «Tu condicion».';
