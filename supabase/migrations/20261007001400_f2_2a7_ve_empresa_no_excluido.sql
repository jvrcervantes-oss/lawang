-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · paso 2A · migracion 7 (7-oct-2026): CORRECCION de la semantica de _ve_empresa, cazada por la foto de visibilidad (md5 de funciones distinto en 1 usuario:
--   martaruiz, ficha INACTIVA, veia por documento_visible 3 facturas que ella misma creo; con la _ve_empresa de la migracion 1 dejaba de verlas).
--   Antes: «la ficha activa deja ver esa empresa» (sin ficha activa = no). Ahora: «ninguna ficha ACTIVA la EXCLUYE» (sin ficha o inactiva = no excluye).
--   Sigue siendo solo un FILTRO que resta: cada funcion conserva su propio permiso (es_agente, lista de proyectos, rol...), asi que una ficha inactiva o inexistente
--   no gana nada, solo deja de perder lo que ya tenia. Excluida = ambito global con lista de empresas no vacia que no la incluye, o ambito empresa que no la incluye
--   (empresa nula con lista no vacia = excluida: nace cerrado).
--   puede_ver_contrato: el mismo criterio dentro de su version rapida.
-- destructivo-ok: create or replace de dos funciones; sin DDL que destruya datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_2a.sql
create or replace function public._ve_empresa(p_empresa text) returns boolean
language sql stable security definer set search_path = '' as $$
  select not exists (
    select 1 from public.usuarios u
     where u.user_id = (select auth.uid()) and u.activo
       and ((u.ambito = 'global' and cardinality(u.empresas) > 0 and not coalesce(p_empresa = any (u.empresas), false))
         or (u.ambito = 'empresa' and not coalesce(p_empresa = any (u.empresas), false))))
$$;

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
                  or (not coalesce((u.ambito = 'global' and cardinality(u.empresas) > 0 and not coalesce(pr.empresa = any (u.empresas), false))
                                   or (u.ambito = 'empresa' and not coalesce(pr.empresa = any (u.empresas), false)), false)
                      and (coalesce(c.creado_por = (select auth.email()), false)
                           or (u.rol = 'project_manager' and c.proyecto_id = any (u.proyectos_supervisados))
                           or (u.user_id is not null
                               and exists (select 1 from public.equipos_venta ev
                                            where ev.activo
                                              and lower(ev.manager_email) = lower(coalesce((select auth.email()), ''))
                                              and ev.id = public._venta_equipo(c.id))))))))
  )
$$;
