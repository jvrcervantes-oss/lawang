-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · paso 2A · migracion 2b (7-oct-2026): proyecto_visible MAS RAPIDA. La de la migracion 2 anidaba es_admin_de/_ve_empresa/es_manager_de y duplicaba el coste por fila
--   (unidades de un agente: 0,18 s -> 0,38 s para 464 filas, medido). Misma regla con la ficha leida UNA vez; es_manager_de(p) para no-admin == project_manager con p en sus supervisados.
-- destructivo-ok: create or replace de una funcion; sin DDL que destruya datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_2a.sql
create or replace function public.proyecto_visible(p_proyecto_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select case
    when public.es_admin() then true
    when p_proyecto_id is null then false
    else exists (
      select 1
        from public.usuarios u
        left join public.proyectos pr on pr.id = p_proyecto_id
       where u.user_id = (select auth.uid()) and u.activo
         and ((u.ambito = 'empresa' and u.rol in ('admin_empresa','super_admin_empresa') and pr.empresa = any (u.empresas))
              or (((u.ambito = 'global' and (cardinality(u.empresas) = 0 or pr.empresa = any (u.empresas)))
                   or (u.ambito = 'empresa' and pr.empresa = any (u.empresas)))
                  and (p_proyecto_id = any (u.proyectos)
                       or (u.rol = 'project_manager' and p_proyecto_id = any (u.proyectos_supervisados))))))
  end
$$;
