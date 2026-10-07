-- REVERSION del paso 2A de la Fase 2 (empresas). Capturada ANTES de aplicar (7-oct-2026): definiciones tal cual estaban en produccion.
-- Orden: policies (para que no dependan de las funciones nuevas) -> funciones originales -> funciones nuevas.
-- Vale en cualquier momento: devuelve la visibilidad a la de antes del 2A (los roles de empresa vuelven a verse como agentes sin proyectos).

alter policy "solicitudes: cada uno lee las suyas, admin con casilla todas" on public.solicitudes_pago
  using ((((es_admin() AND puede('comisiones'::text)) OR ((creado_por = ( SELECT auth.uid() AS uid)) AND (origen IS DISTINCT FROM 'comision_automatica'::text)) OR (beneficiario_email = ( SELECT auth.email() AS email)))));

alter policy "agentes leen sus facturas" on public.facturas
  using ((( SELECT es_agente() AS es_agente) AND (( SELECT es_admin() AS es_admin) OR COALESCE((creado_por = ( SELECT auth.email() AS email)), false) OR (proyecto_id = ANY (( SELECT mis_proyectos_supervisados() AS mis_proyectos_supervisados)::uuid[])) OR (contrato_id = ANY (( SELECT mis_contratos_visibles() AS mis_contratos_visibles)::uuid[])))));

alter policy "agentes leen sus contratos" on public.contratos
  using ((( SELECT es_admin() AS es_admin) OR (( SELECT es_agente() AS es_agente) AND (COALESCE((creado_por = ( SELECT auth.email() AS email)), false) OR (id = ANY (( SELECT mis_contratos_visibles() AS mis_contratos_visibles)::uuid[]))))));

-- (migracion 8) las dos funciones nuevas de la policy de facturas: ya revertida arriba, se pueden borrar
drop function public.mis_proyectos_admin_empresa();
drop function public.alcance_restringido();

create or replace function public.cliente_visible(p_propietario text, p_client_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.es_admin()
      or coalesce(p_propietario = (select auth.email()), false)
      or ((public.es_gestor()
           or exists (select 1 from public.equipos_venta ev
                       where ev.activo and lower(ev.manager_email) = lower(coalesce((select auth.email()), ''))))
          and exists (
            select 1
              from public.contrato_compradores cc
              join public.contratos c on c.id = cc.contrato_id
             where cc.client_id = p_client_id
               and (public.es_manager_de(c.proyecto_id) or public._sm_ve_venta(c.id))));
$$;

create or replace function public.documento_visible(p_autor text, p_proyecto_id uuid, p_contrato_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  -- Por fila en facturas y recibís: autor y PM en línea (mismas reglas que es_suyo y
  -- es_manager_de) para no encadenar llamadas DEFINER; la venta, por la puerta.
  select public.es_admin()
      or coalesce(p_autor = (select auth.email()), false)
      or (p_proyecto_id is not null and exists (
            select 1 from public.usuarios u
             where u.user_id = (select auth.uid()) and u.activo
               and u.rol = 'project_manager'
               and p_proyecto_id = any (u.proyectos_supervisados)))
      or (p_contrato_id is not null and public.puede_ver_contrato(p_contrato_id))
$$;

create or replace function public.puede_ver_contrato(p_contrato uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select p_contrato is not null and (
    public.es_admin()
    or (public.es_agente() and exists (
          select 1 from public.contratos c
           where c.id = p_contrato
             and (coalesce(c.creado_por = (select auth.email()), false)
                  or exists (select 1 from public.usuarios u
                              where u.user_id = (select auth.uid()) and u.activo
                                and u.rol = 'project_manager'
                                and c.proyecto_id = any (u.proyectos_supervisados))
                  or (exists (select 1 from public.usuarios ua
                               where ua.user_id = (select auth.uid()) and ua.activo)
                      and exists (select 1 from public.equipos_venta ev
                                   where ev.activo
                                     and lower(ev.manager_email) = lower(coalesce((select auth.email()), ''))
                                     and ev.id = public._venta_equipo(c.id)))))))
$$;

create or replace function public.mis_contratos_visibles() returns uuid[]
language sql stable security definer set search_path = '' as $$
  with yo as (
    select (select auth.email()) email,
           (select auth.uid()) uid
  ), pm as (
    select coalesce((select u.proyectos_supervisados from public.usuarios u, yo
                      where u.user_id = yo.uid and u.activo and u.rol = 'project_manager'), '{}'::uuid[]) ps
  ), eq as (
    select coalesce(array_agg(ev.id), '{}'::uuid[]) ids
      from public.equipos_venta ev, yo
     where ev.activo
       and lower(ev.manager_email) = lower(coalesce(yo.email, ''))
       and exists (select 1 from public.usuarios ua where ua.user_id = yo.uid and ua.activo)
  )
  select case
    when public.es_admin() then (select coalesce(array_agg(c.id), '{}'::uuid[]) from public.contratos c)
    when not public.es_agente() then '{}'::uuid[]
    else (select coalesce(array_agg(c.id), '{}'::uuid[])
            from public.contratos c, yo, pm, eq
           where coalesce(c.creado_por = yo.email, false)
              or c.proyecto_id = any (pm.ps)
              or (cardinality(eq.ids) > 0 and public._venta_equipo(c.id) = any (eq.ids)))
  end
$$;

create or replace function public.mis_proyectos_supervisados() returns uuid[]
language sql stable security definer set search_path = '' as $$
  select coalesce((select u.proyectos_supervisados from public.usuarios u
                    where u.user_id = (select auth.uid()) and u.activo and u.rol = 'project_manager'),
                  '{}'::uuid[])
$$;

create or replace function public.puede_proyecto(p_nombre text) returns boolean
language sql stable security definer set search_path = '' as $$
  select case
    when public.es_admin() then true
    when not exists (select 1 from public.usuarios u where u.user_id = (select auth.uid()))
      then coalesce(((select auth.jwt()) -> 'app_metadata' ->> 'agente')::boolean, false)
    when coalesce(btrim(p_nombre), '') = '' then false
    when not exists (select 1 from public.proyectos p where p.nombre = btrim(p_nombre)) then false
    else exists (
      select 1
        from public.usuarios u
        join public.proyectos p
          on p.id = any (u.proyectos)
          or (u.rol = 'project_manager' and p.id = any (u.proyectos_supervisados))
       where u.user_id = (select auth.uid()) and u.activo
         and p.nombre = btrim(p_nombre))
  end
$$;

create or replace function public.proyecto_visible(p_proyecto_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select case
    when public.es_admin() then true
    when public.es_manager_de(p_proyecto_id) then true
    when p_proyecto_id is null then false
    else exists (
      select 1 from public.usuarios u
       where u.user_id = (select auth.uid()) and u.activo
         and p_proyecto_id = any (u.proyectos))
  end
$$;

drop function public.admin_de_contrato(uuid);
drop function public.proyecto_en_alcance(uuid);
drop function public._ve_empresa(text);
