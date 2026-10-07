-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · paso 2A · migracion 3/6 (7-oct-2026): CONTRATOS y todo lo que cuelga de mis_contratos_visibles (vencimientos, firmas, anexos, correos, bot, eventos...).
--   mis_contratos_visibles: admin/super global = todos (igual). Rol de empresa = los contratos de proyectos de SUS empresas (contrato sin proyecto: no).
--   Agente/PM/equipo: lo de siempre Y la empresa del proyecto del contrato dentro de su alcance (lista vacia = sin restriccion = hoy; contrato sin proyecto: visible solo si la lista esta vacia).
--   puede_ver_contrato: misma regla (alimenta el storage de contratos-firmados). La policy de contratos pasa a depender solo de mis_contratos_visibles
--   (que ya incluia creado_por): asi el filtro de empresa no se salta por la rama «lo cree yo».
-- destructivo-ok: create or replace de dos funciones y alter policy (misma expresion salvo el filtro nuevo); sin DDL que destruya datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_2a.sql
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
            from public.contratos c
            left join public.proyectos pr on pr.id = c.proyecto_id, yo, pm, eq
           where public.es_admin_de(pr.empresa)
              or (public._ve_empresa(pr.empresa)
                  and (coalesce(c.creado_por = yo.email, false)
                       or c.proyecto_id = any (pm.ps)
                       or (cardinality(eq.ids) > 0 and public._venta_equipo(c.id) = any (eq.ids)))))
  end
$$;

create or replace function public.puede_ver_contrato(p_contrato uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select p_contrato is not null and (
    public.es_admin()
    or (public.es_agente() and exists (
          select 1 from public.contratos c
            left join public.proyectos pr on pr.id = c.proyecto_id
           where c.id = p_contrato
             and (public.es_admin_de(pr.empresa)
                  or (public._ve_empresa(pr.empresa)
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
                                              and ev.id = public._venta_equipo(c.id)))))))))
$$;

alter policy "agentes leen sus contratos" on public.contratos
  using ((( SELECT es_admin() AS es_admin) OR (( SELECT es_agente() AS es_agente) AND (id = ANY (( SELECT mis_contratos_visibles() AS mis_contratos_visibles)::uuid[])))));
