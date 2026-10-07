-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · paso 3A (7-oct-2026): usuario_da_alcance — la unica puerta para dar o quitar a una persona su NIVEL y sus EMPRESAS desde la pantalla de Usuarios.
--   Solo el propietario (es_propietario(), con sesion). Cambia rol + ambito + empresas EN UN SOLO UPDATE (los CHECK de coherencia ambito<->rol no admiten hacerlo en dos pasos).
--   Niveles: 'admin_empresa' y 'super_admin_empresa' (ambito empresa, 1+ empresas) · 'agente','sales_manager','project_manager' (ambito global; empresas opcionales = acotar a esas empresas;
--   vacio = sin restriccion como hoy) · 'admin' (global, sin empresas). 'super_admin' NO se da por aqui. Nadie se cambia a si mismo; el propietario no se toca.
--   Al acotar a empresas, los proyectos de la persona que no sean de esas empresas se QUITAN (devuelve cuantos). Sin esto el alcance dejaria proyectos fuera de su empresa.
--   Los triggers de usuarios (usuarios_bloquea_cambio_rol_herramientas) siguen siendo la segunda cerradura.
-- destructivo-ok: una funcion nueva; no borra datos
-- REVERTIR: drop function public.usuario_da_alcance(uuid, text, text[]);
create or replace function public.usuario_da_alcance(p_user_id uuid, p_rol text, p_empresas text[])
 returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_old public.usuarios%rowtype; v_amb text; v_emp text[]; v_quita int := 0; v_p uuid[]; v_ps uuid[];
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if not public.es_propietario() then
    raise exception 'Solo el propietario da el nivel y las empresas de una persona' using errcode = '42501';
  end if;
  if p_user_id = (select auth.uid()) then raise exception 'Nadie se cambia el nivel a sí mismo' using errcode = '42501'; end if;
  select * into v_old from public.usuarios u where u.user_id = p_user_id for update;
  if not found then raise exception 'No encuentro a esa persona' using errcode = '42501'; end if;
  if v_old.es_propietario or v_old.rol = 'super_admin' then
    raise exception 'El propietario y los super admin globales no se tocan por aquí' using errcode = '42501';
  end if;
  if p_rol not in ('admin_empresa','super_admin_empresa','agente','sales_manager','project_manager','admin') then
    raise exception 'Nivel no válido' using errcode = '22023';
  end if;
  v_emp := coalesce((select array_agg(distinct e) from unnest(coalesce(p_empresas, '{}')) e), '{}');
  if exists (select 1 from unnest(v_emp) e where not exists (select 1 from public.empresas x where x.clave = e and x.activa)) then
    raise exception 'Alguna empresa no existe o no está activa' using errcode = '22023';
  end if;
  if p_rol in ('admin_empresa','super_admin_empresa') then
    v_amb := 'empresa';
    if cardinality(v_emp) = 0 then raise exception 'Un rol de empresa necesita al menos una empresa' using errcode = '22023'; end if;
  else
    v_amb := 'global';
    if p_rol = 'admin' and cardinality(v_emp) > 0 then
      raise exception 'Un administrador global no se acota a empresas: dale un rol de empresa' using errcode = '22023';
    end if;
  end if;
  -- proyectos fuera de las empresas elegidas: se quitan (y se cuenta)
  if cardinality(v_emp) > 0 then
    select coalesce(array_agg(x.id), '{}') into v_p
      from unnest(coalesce(v_old.proyectos, '{}')) x(id)
      join public.proyectos p on p.id = x.id and p.empresa = any (v_emp);
    select coalesce(array_agg(x.id), '{}') into v_ps
      from unnest(coalesce(v_old.proyectos_supervisados, '{}')) x(id)
      join public.proyectos p on p.id = x.id and p.empresa = any (v_emp);
    v_quita := cardinality(coalesce(v_old.proyectos, '{}')) - cardinality(v_p);
  else
    v_p := coalesce(v_old.proyectos, '{}'); v_ps := coalesce(v_old.proyectos_supervisados, '{}');
  end if;
  update public.usuarios u
     set rol = p_rol, ambito = v_amb, empresas = v_emp, proyectos = v_p, proyectos_supervisados = v_ps
   where u.user_id = p_user_id;
  return jsonb_build_object('rol', p_rol, 'ambito', v_amb, 'empresas', to_jsonb(v_emp), 'proyectos_quitados', v_quita);
end $$;
revoke all on function public.usuario_da_alcance(uuid, text, text[]) from public, anon;
grant execute on function public.usuario_da_alcance(uuid, text, text[]) to authenticated;  -- lo llama la pantalla de Usuarios (RPC); ninguna policy, asi que sin lw_lector
