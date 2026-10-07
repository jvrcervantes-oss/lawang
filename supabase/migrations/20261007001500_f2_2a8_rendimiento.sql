-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · paso 2A · migracion 8 (7-oct-2026): RENDIMIENTO. Medido nuevo vs original (reversion ensayada en transaccion) para un agente de la intranet:
--   facturas 255 ms (antes 3), contratos/vencimientos 50 ms (antes 2). Causa: el filtro de empresa se calculaba POR FILA (es_admin_de + empresa_de_proyecto + proyecto_en_alcance).
--   Arreglo: (1) mis_contratos_visibles lee la ficha una sola vez en vez de llamar a es_admin_de/_ve_empresa por contrato; (2) la policy de facturas usa dos valores que se
--   calculan UNA vez por consulta (initPlan): mis_proyectos_admin_empresa() = proyectos de las empresas que administro (vacio salvo rol de empresa) y alcance_restringido()
--   = ¿tengo empresas marcadas? Si no (los 34 de hoy) el filtro por fila ni se evalua. Misma regla que antes, solo mas barata.
-- destructivo-ok: create or replace de una funcion, dos funciones nuevas y alter policy; sin DDL que destruya datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_2a.sql (borra tambien las dos funciones nuevas)
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
  ), us as (
    select u.ambito, u.rol, u.empresas from public.usuarios u, yo where u.user_id = yo.uid and u.activo
  )
  select case
    when public.es_admin() then (select coalesce(array_agg(c.id), '{}'::uuid[]) from public.contratos c)
    when not public.es_agente() then '{}'::uuid[]
    else (select coalesce(array_agg(c.id), '{}'::uuid[])
            from public.contratos c
            left join public.proyectos pr on pr.id = c.proyecto_id
            left join us on true, yo, pm, eq
           where (us.ambito = 'empresa' and us.rol in ('admin_empresa','super_admin_empresa') and pr.empresa = any (us.empresas))
              or (not coalesce((us.ambito = 'global' and cardinality(us.empresas) > 0 and not coalesce(pr.empresa = any (us.empresas), false))
                               or (us.ambito = 'empresa' and not coalesce(pr.empresa = any (us.empresas), false)), false)
                  and (coalesce(c.creado_por = yo.email, false)
                       or c.proyecto_id = any (pm.ps)
                       or (cardinality(eq.ids) > 0 and public._venta_equipo(c.id) = any (eq.ids)))))
  end
$$;

create or replace function public.mis_proyectos_admin_empresa() returns uuid[]
language sql stable security definer set search_path = '' as $$
  select coalesce((select array_agg(p.id)
                     from public.usuarios u
                     join public.proyectos p on p.empresa = any (u.empresas)
                    where u.user_id = (select auth.uid()) and u.activo
                      and u.ambito = 'empresa' and u.rol in ('admin_empresa','super_admin_empresa')),
                  '{}'::uuid[])
$$;
revoke all on function public.mis_proyectos_admin_empresa() from public, anon;
grant execute on function public.mis_proyectos_admin_empresa() to authenticated, lw_lector;

create or replace function public.alcance_restringido() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.usuarios u
                  where u.user_id = (select auth.uid()) and u.activo
                    and (u.ambito = 'empresa' or cardinality(u.empresas) > 0))
$$;
revoke all on function public.alcance_restringido() from public, anon;
grant execute on function public.alcance_restringido() to authenticated, lw_lector;

alter policy "agentes leen sus facturas" on public.facturas
  using ((( SELECT es_agente() AS es_agente) AND (( SELECT es_admin() AS es_admin)
     OR (proyecto_id = ANY (( SELECT mis_proyectos_admin_empresa() AS mis_proyectos_admin_empresa)::uuid[]))
     OR ((COALESCE((creado_por = ( SELECT auth.email() AS email)), false)
         OR (proyecto_id = ANY (( SELECT mis_proyectos_supervisados() AS mis_proyectos_supervisados)::uuid[]))
         OR (contrato_id = ANY (( SELECT mis_contratos_visibles() AS mis_contratos_visibles)::uuid[])))
        AND ((NOT ( SELECT alcance_restringido() AS alcance_restringido)) OR proyecto_en_alcance(proyecto_id))))));
