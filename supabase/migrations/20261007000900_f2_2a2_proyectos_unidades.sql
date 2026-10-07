-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · paso 2A · migracion 2/6 (7-oct-2026): PROYECTOS y UNIDADES (unidad_visible = proyecto_visible, sin tocarla).
--   proyecto_visible: admin/super global = todo (igual). admin_empresa / super_admin_empresa = los proyectos de SUS empresas (proyecto sin empresa: no).
--   Agente/PM: lo de siempre (su lista / supervisados) Y ademas la empresa del proyecto dentro de su alcance (lista vacia = sin restriccion = hoy).
--   puede_proyecto(nombre): misma regla (documentos, modelos, fotos de obra...). puede_proyecto_id ya delega en proyecto_visible. El atajo del JWT con
--   app_metadata.agente y SIN ficha no se toca (medido 7-oct: 0 cuentas asi de 32 con la marca).
--   mis_proyectos_supervisados: filtra por empresa (lista vacia: igual que hoy).
-- destructivo-ok: create or replace de tres funciones; sin DDL que destruya datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_2a.sql
create or replace function public.proyecto_visible(p_proyecto_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select case
    when public.es_admin() then true
    when p_proyecto_id is null then false
    else (
      select case
        when public.es_admin_de(e.emp) then true
        else public._ve_empresa(e.emp)
             and (public.es_manager_de(p_proyecto_id)
                  or exists (select 1 from public.usuarios u
                              where u.user_id = (select auth.uid()) and u.activo
                                and p_proyecto_id = any (u.proyectos)))
      end
      from (select (select p.empresa from public.proyectos p where p.id = p_proyecto_id) as emp) e)
  end
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
        join public.proyectos p on p.nombre = btrim(p_nombre)
       where u.user_id = (select auth.uid()) and u.activo
         and ((u.ambito = 'empresa' and u.rol in ('admin_empresa','super_admin_empresa') and p.empresa = any (u.empresas))
           or ((p.id = any (u.proyectos) or (u.rol = 'project_manager' and p.id = any (u.proyectos_supervisados)))
               and ((u.ambito = 'global' and (cardinality(u.empresas) = 0 or p.empresa = any (u.empresas)))
                 or (u.ambito = 'empresa' and p.empresa = any (u.empresas))))))
  end
$$;

create or replace function public.mis_proyectos_supervisados() returns uuid[]
language sql stable security definer set search_path = '' as $$
  select coalesce((select array(select pid from unnest(u.proyectos_supervisados) pid
                                 where public._ve_empresa((select p.empresa from public.proyectos p where p.id = pid)))
                     from public.usuarios u
                    where u.user_id = (select auth.uid()) and u.activo and u.rol = 'project_manager'),
                  '{}'::uuid[])
$$;
