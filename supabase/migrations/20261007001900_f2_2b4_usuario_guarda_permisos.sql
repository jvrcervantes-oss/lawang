-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · paso 2B · migracion 4 (7-oct-2026): usuario_guarda_permisos reconoce los roles de empresa.
--   (1) Un admin global NO super no gestiona a un admin_empresa ni a un super_admin_empresa (antes la lista protegida solo tenia admin/super_admin y podia cambiarles proyectos/activo).
--   (2) Si la persona tiene empresas marcadas, sus proyectos tienen que ser de esas empresas (un proyecto sin empresa, como Karana, no entra): un agente de Lawang no puede quedar con proyectos de Sandal Woods.
--   Resto identico a la version viva (F7-alcance, LAW-343). El rol y el alcance de empresa siguen blindados por el trigger de usuarios (solo el propietario).
-- destructivo-ok: create or replace de una funcion; sin borrar datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_2b.sql
create or replace function public.usuario_guarda_permisos(p_user_id uuid, p_cambios jsonb)
 returns void language plpgsql security definer set search_path = '' as $$
declare v_old public.usuarios%rowtype; v_yo boolean; v_rol text;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if not (public.es_admin() and public.puede('usuarios')) then
    raise exception 'Solo un administrador con la herramienta Usuarios gestiona permisos' using errcode = '42501';
  end if;
  select * into v_old from public.usuarios u where u.user_id = p_user_id for update;
  if not found or (v_old.rol = 'super_admin' and not public.es_super_admin()) then
    raise exception 'No encuentro ese usuario entre los que puedes gestionar' using errcode = '42501';
  end if;
  v_yo := p_user_id = (select auth.uid());
  -- F7-alcance
  if not v_yo and not public.es_super_admin() then
    if v_old.rol in ('admin','super_admin','admin_empresa','super_admin_empresa') then
      raise exception 'Un admin no gestiona a otro admin: lo hace un super admin' using errcode = '42501';
    end if;
    if p_cambios ? 'proyectos' and not (
         array(select (jsonb_array_elements_text(p_cambios->'proyectos'))::uuid except select unnest(coalesce(v_old.proyectos, '{}')))
         <@ coalesce((select y.proyectos from public.usuarios y where y.user_id = (select auth.uid())), '{}')) then
      raise exception 'No puedes dar proyectos que no tienes tú' using errcode = '42501';
    end if;
    if p_cambios ? 'tipos_contrato' and not (
         array(select jsonb_array_elements_text(p_cambios->'tipos_contrato') except select unnest(coalesce(v_old.tipos_contrato, '{}')))
         <@ coalesce((select y.tipos_contrato from public.usuarios y where y.user_id = (select auth.uid())), '{}')) then
      raise exception 'No puedes dar tipos de contrato que no tienes tú' using errcode = '42501';
    end if;
  end if;
  -- 2B: proyectos dentro de las empresas de la persona (si tiene alguna marcada)
  if p_cambios ? 'proyectos' and cardinality(coalesce(v_old.empresas, '{}')) > 0
     and exists (select 1 from jsonb_array_elements_text(p_cambios->'proyectos') x(id)
                   left join public.proyectos p on p.id = x.id::uuid
                  where p.empresa is null or not (p.empresa = any (v_old.empresas))) then
    raise exception 'Esa persona tiene empresas marcadas: sus proyectos tienen que ser de esas empresas' using errcode = '42501';
  end if;
  if v_yo and not public.es_super_admin()
     and (p_cambios - 'nombre') <> '{}'::jsonb then
    raise exception 'Sobre tu propia ficha solo puedes cambiar el nombre' using errcode = '42501';
  end if;
  if v_yo and (p_cambios ? 'activo' or p_cambios ? 'rol') then
    raise exception 'Nadie se desactiva ni se cambia el rol a sí mismo' using errcode = '42501';
  end if;
  -- LAW-343 reactivar: un admin no-super solo reactiva cuentas cuyas herramientas tiene él
  if p_cambios ? 'activo' and (p_cambios->>'activo')::boolean and not v_old.activo and not public.es_super_admin()
     and not (coalesce(v_old.herramientas, '{}') <@ coalesce((select y.herramientas from public.usuarios y
                                                              where y.user_id = (select auth.uid())), '{}')) then
    raise exception 'Esa cuenta tiene herramientas que tú no tienes: la reactiva un super admin' using errcode = '42501';
  end if;
  v_rol := case when p_cambios ? 'rol' then p_cambios->>'rol' else v_old.rol end;
  if v_rol = 'super_admin' and not public.es_super_admin() then
    raise exception 'Solo un super admin da el rol super_admin' using errcode = '42501';
  end if;
  update public.usuarios u
     set nombre         = case when p_cambios ? 'nombre' then nullif(btrim(coalesce(p_cambios->>'nombre', '')), '') else u.nombre end,
         herramientas   = case when p_cambios ? 'herramientas'
                               then coalesce(array(select jsonb_array_elements_text(p_cambios->'herramientas')), '{}') else u.herramientas end,
         tipos_contrato = case when p_cambios ? 'tipos_contrato'
                               then coalesce(array(select jsonb_array_elements_text(p_cambios->'tipos_contrato')), '{}') else u.tipos_contrato end,
         proyectos      = case when p_cambios ? 'proyectos'
                               then coalesce(array(select (jsonb_array_elements_text(p_cambios->'proyectos'))::uuid), '{}') else u.proyectos end,
         activo         = case when p_cambios ? 'activo' then (p_cambios->>'activo')::boolean else u.activo end,
         rol            = v_rol
   where u.user_id = p_user_id;
end $$;
