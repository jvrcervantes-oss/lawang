-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · paso 2A · migracion 3b (7-oct-2026): puede_ver_contrato MAS RAPIDA. La version de la migracion 3 llamaba a es_admin_de() y _ve_empresa() por contrato y tardaba
--   ~1,8 ms por llamada (se llama por fila en documento_visible, recibis y el storage): se medio con la foto de visibilidad, que dejo de caber en el tiempo del MCP.
--   Misma regla, pero con la ficha del usuario leida UNA vez (left join) y sin llamadas anidadas.
-- destructivo-ok: create or replace de una funcion; sin DDL que destruya datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_2a.sql
create or replace function public.puede_ver_contrato(p_contrato uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select p_contrato is not null and (
    public.es_admin()
    or (public.es_agente() and exists (
          select 1
            from public.contratos c
            left join public.proyectos pr on pr.id = c.proyecto_id
            left join public.usuarios u on u.user_id = (select auth.uid()) and u.activo
           where c.id = p_contrato
             and ((u.ambito = 'empresa' and u.rol in ('admin_empresa','super_admin_empresa') and pr.empresa = any (u.empresas))
                  or (coalesce((u.ambito = 'global' and (cardinality(u.empresas) = 0 or pr.empresa = any (u.empresas)))
                               or (u.ambito = 'empresa' and pr.empresa = any (u.empresas)), false)
                      and (coalesce(c.creado_por = (select auth.email()), false)
                           or (u.rol = 'project_manager' and c.proyecto_id = any (u.proyectos_supervisados))
                           or (u.user_id is not null
                               and exists (select 1 from public.equipos_venta ev
                                            where ev.activo
                                              and lower(ev.manager_email) = lower(coalesce((select auth.email()), ''))
                                              and ev.id = public._venta_equipo(c.id))))))))
  )
$$;
