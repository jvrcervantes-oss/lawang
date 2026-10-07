-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · bloque 5 · migracion 3 (8-oct-2026): GESTION DE PERSONAS POR EMPRESA (usuario_guarda_permisos, usuario_supervisa_proyecto y los triggers de `usuarios`).
--   Un admin_empresa (con la casilla «usuarios») o un super_admin_empresa gestiona SOLO a las personas que `_usuario_gestionable` le deja (agentes / sales_manager / project_manager,
--   ambito global, con empresas marcadas y todas dentro de las suyas; nunca globales sin empresas, ni otros roles de empresa, ni el propietario, ni el mismo).
--   * usuario_guarda_permisos: herramientas (solo las que tiene el), tipos de contrato (un super de empresa cualquiera; un admin de empresa solo los suyos), proyectos (solo de las
--     empresas de la persona, que son de las suyas: «tenerlo» = «es de mis empresas», no «esta en mi lista», porque un admin_empresa ve todos los de su empresa y su lista puede estar vacia),
--     activar/desactivar (reactivar exige que las herramientas de la cuenta sean suyas, la regla de siempre) y nombre. NUNCA el nivel: eso solo lo da el propietario (usuario_da_alcance).
--   * usuario_supervisa_proyecto: igual, y el proyecto debe ser de las empresas de la persona. QUITAR una supervision tambien exige persona gestionable (antes no miraba al destino).
--   * Triggers de `usuarios`: el que exige super_admin para cambiar rol/herramientas deja pasar a un rol de empresa SOLO para herramientas de una persona gestionable y que el da (sin tocar el rol);
--     el candado de alta deja nacer una ficha con empresas a un rol de empresa SOLO si la regla de alta (`_alta_empresa_permitida`) lo permite.
--   Para el administrador global y el agente la conducta no cambia: el texto es el anterior salvo las ramas nuevas (se comprueba A/B contra el original en la prueba).
-- destructivo-ok: create or replace de 4 funciones + 1 funcion nueva sin EXECUTE
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b5.sql
set local lock_timeout = '8s';

create or replace function public._gestor_puede_dar(p_user_id uuid, p_antes text[], p_despues text[]) returns boolean
language sql stable security definer set search_path = '' as $$
  select public._usuario_gestionable(p_user_id)
     and array(select unnest(coalesce(p_despues, '{}'::text[])) except select unnest(coalesce(p_antes, '{}'::text[])))
         <@ coalesce(public._gestor_herramientas(), '{}'::text[])
$$;
revoke all on function public._gestor_puede_dar(uuid, text[], text[]) from public, anon, authenticated;

-- ---------------------------------------------------------------- usuario_guarda_permisos
create or replace function public.usuario_guarda_permisos(p_user_id uuid, p_cambios jsonb)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_old public.usuarios%rowtype; v_yo boolean; v_rol text; v_emp boolean := false; v_mias text[]; v_sup boolean;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if not (public.es_admin() and public.puede('usuarios')) then
    if public._gestor_empresas() is null then
      raise exception 'Solo un administrador con la herramienta Usuarios gestiona permisos' using errcode = '42501';
    end if;
    v_emp := true;   -- admin_empresa con la casilla «usuarios», o super_admin_empresa
  end if;
  select * into v_old from public.usuarios u where u.user_id = p_user_id for update;
  if not found or (v_old.rol = 'super_admin' and not public.es_super_admin()) then
    raise exception 'No encuentro ese usuario entre los que puedes gestionar' using errcode = '42501';
  end if;
  v_yo := p_user_id = (select auth.uid());
  if v_emp then
    if not v_yo and not public._usuario_gestionable(p_user_id) then
      raise exception 'No encuentro ese usuario entre los que puedes gestionar' using errcode = '42501';
    end if;
    if p_cambios ? 'rol' and (p_cambios->>'rol') is distinct from v_old.rol then
      raise exception 'El nivel de una persona lo cambia el propietario, no un administrador de empresa' using errcode = '42501';
    end if;
    if not v_yo then
      v_mias := coalesce(public._gestor_herramientas(), '{}');
      v_sup := coalesce((select y.rol = 'super_admin_empresa' from public.usuarios y where y.user_id = (select auth.uid())), false);
      if p_cambios ? 'herramientas' and not (
           array(select jsonb_array_elements_text(p_cambios->'herramientas') except select unnest(coalesce(v_old.herramientas, '{}')))
           <@ v_mias) then
        raise exception 'No puedes dar herramientas que no tienes tú' using errcode = '42501';
      end if;
      if p_cambios ? 'tipos_contrato' and not v_sup and not (
           array(select jsonb_array_elements_text(p_cambios->'tipos_contrato') except select unnest(coalesce(v_old.tipos_contrato, '{}')))
           <@ coalesce((select y.tipos_contrato from public.usuarios y where y.user_id = (select auth.uid())), '{}')) then
        raise exception 'No puedes dar tipos de contrato que no tienes tú' using errcode = '42501';
      end if;
    end if;
  elsif not v_yo and not public.es_super_admin() then
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
  if p_cambios ? 'proyectos' and cardinality(coalesce(v_old.empresas, '{}')) > 0
     and exists (select 1 from jsonb_array_elements_text(p_cambios->'proyectos') x(id)
                   left join public.proyectos p on p.id = x.id::uuid
                  where p.empresa is null or not (p.empresa = any (v_old.empresas))) then
    raise exception 'Esa persona tiene empresas marcadas: sus proyectos tienen que ser de esas empresas' using errcode = '42501';
  end if;
  if v_emp and p_cambios ? 'proyectos' and cardinality(coalesce(v_old.empresas, '{}')) = 0 then
    raise exception 'Esa persona no tiene empresas marcadas' using errcode = '42501';
  end if;
  if v_yo and not public.es_super_admin()
     and (p_cambios - 'nombre') <> '{}'::jsonb then
    raise exception 'Sobre tu propia ficha solo puedes cambiar el nombre' using errcode = '42501';
  end if;
  if v_yo and (p_cambios ? 'activo' or p_cambios ? 'rol') then
    raise exception 'Nadie se desactiva ni se cambia el rol a sí mismo' using errcode = '42501';
  end if;
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
end $function$;

-- ---------------------------------------------------------------- usuario_supervisa_proyecto
create or replace function public.usuario_supervisa_proyecto(p_user_id uuid, p_proyecto_id uuid, p_asignar boolean)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_rol text; v_dest text[]; v_emp boolean := false; v_p_emp text;
begin
  if not (public.es_admin() and public.puede('usuarios')) then
    if public._gestor_empresas() is null then
      raise exception 'no autorizado' using errcode = '42501';
    end if;
    v_emp := true;
  end if;
  select rol, empresas into v_rol, v_dest from public.usuarios where user_id = p_user_id;
  if v_rol is null then
    raise exception 'usuario no encontrado' using errcode = '22023';
  end if;
  if v_emp and not public._usuario_gestionable(p_user_id) then
    raise exception 'no autorizado' using errcode = '42501';
  end if;
  if v_rol = 'super_admin' and not public.es_super_admin() then
    raise exception 'no autorizado' using errcode = '42501';
  end if;

  -- F7-alcance
  if p_asignar and not v_emp and not public.es_super_admin()
     and not exists (select 1 from public.usuarios y where y.user_id = (select auth.uid()) and p_proyecto_id = any (y.proyectos)) then
    raise exception 'Solo puedes asignar proyectos que son tuyos' using errcode = '42501';
  end if;
  -- Fase 2 b5: la empresa del proyecto sale de la base y debe ser una de las de la persona (que son de las del llamador)
  if p_asignar and v_emp then
    select p.empresa into v_p_emp from public.proyectos p where p.id = p_proyecto_id;
    if v_p_emp is null or not (v_p_emp = any (coalesce(v_dest, '{}'))) then
      raise exception 'Solo puedes asignar proyectos de las empresas de esa persona' using errcode = '42501';
    end if;
  end if;
  if p_asignar and v_rol <> 'project_manager' then
    raise exception 'Solo un project_manager supervisa proyectos: el sales_manager ve las ventas de su equipo' using errcode = '22023';
  end if;

  if p_asignar then
    update public.usuarios
       set proyectos_supervisados = (
         select array(select distinct unnest(coalesce(proyectos_supervisados, '{}'::uuid[]) || array[p_proyecto_id]))
       )
     where user_id = p_user_id;
  else
    update public.usuarios
       set proyectos_supervisados = array_remove(coalesce(proyectos_supervisados, '{}'::uuid[]), p_proyecto_id)
     where user_id = p_user_id;
  end if;
end;
$function$;

-- ---------------------------------------------------------------- triggers de `usuarios`
create or replace function public.usuarios_bloquea_cambio_rol_herramientas()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
declare v_uid uuid := (select auth.uid());
begin
  if (new.rol is distinct from old.rol or new.herramientas is distinct from old.herramientas)
     and not public.es_super_admin() then
    -- Fase 2 b5: un rol de empresa puede cambiar SOLO las herramientas de una persona que gestiona y que el mismo tiene; nunca el rol
    if v_uid is null or new.rol is distinct from old.rol or not public._gestor_puede_dar(old.user_id, old.herramientas, new.herramientas) then
      raise exception 'Solo un super_admin puede cambiar el rol o las herramientas de un usuario'
        using errcode = '42501';
    end if;
  end if;
  if new.ambito is distinct from old.ambito or new.empresas is distinct from old.empresas
     or new.es_propietario is distinct from old.es_propietario
     or (new.rol is distinct from old.rol
         and (new.rol in ('admin_empresa','super_admin_empresa') or old.rol in ('admin_empresa','super_admin_empresa'))) then
    if v_uid is null then
      if session_user not in ('postgres','supabase_admin') then
        raise exception 'Alcance de empresa o propietario: solo el propietario (con sesion) lo cambia' using errcode = '42501';
      end if;
    else
      if not public.es_propietario() then
        raise exception 'Solo el propietario cambia el ambito, las empresas, el nivel propietario o los roles de empresa' using errcode = '42501';
      end if;
      if v_uid = old.user_id then
        raise exception 'Nadie se cambia esos campos a si mismo' using errcode = '42501';
      end if;
    end if;
  end if;
  if old.es_propietario then
    if v_uid is not null and v_uid <> old.user_id and (new.rol is distinct from old.rol or new.activo is distinct from old.activo) then
      raise exception 'Al propietario no le cambia el rol ni lo desactiva otro' using errcode = '42501';
    end if;
    if (not new.es_propietario or not new.activo or new.rol <> 'super_admin')
       and not exists (select 1 from public.usuarios o where o.es_propietario and o.activo and o.user_id <> old.user_id) then
      raise exception 'No puede quedar la base sin propietario' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$function$;

create or replace function public.usuarios_candado_alta()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if new.es_propietario or new.ambito <> 'global' or cardinality(new.empresas) > 0 or new.rol in ('admin_empresa','super_admin_empresa') then
    if (select auth.uid()) is null then
      if session_user not in ('postgres','supabase_admin') then
        raise exception 'Alcance de empresa o propietario: solo el propietario (con sesion) lo da' using errcode = '42501';
      end if;
    elsif not public.es_propietario() then
      -- Fase 2 b5: un rol de empresa da de alta a una persona de SUS empresas, y nada mas (misma regla que la funcion de alta)
      if not public._alta_empresa_permitida(new.rol, new.ambito, new.empresas, new.herramientas, new.proyectos, new.es_propietario) then
        raise exception 'Solo el propietario da un alcance de empresa o el nivel propietario' using errcode = '42501';
      end if;
    end if;
  end if;
  return new;
end $function$;
