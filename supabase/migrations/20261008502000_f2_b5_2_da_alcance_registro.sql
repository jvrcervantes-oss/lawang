-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · bloque 5 · migracion 2 (8-oct-2026): `usuario_da_alcance` (solo el propietario) con las tres mejoras que dejaron Seguridad y Datos en el paso 3A.
--   * No da nivel a una cuenta DESACTIVADA (quedaria un rol de empresa durmiendo que alguien reactiva sin saber que lo es).
--   * Cada cambio deja una fila en `usuarios_cambios_alcance` (quien, a quien, antes y despues de nivel, ambito, empresas, proyectos y supervisados).
--   * Cuenta tambien los proyectos SUPERVISADOS que quita al acotar por empresa (antes solo contaba `proyectos`) y los devuelve como `supervisados_quitados`.
--   Todo lo demas es literal el texto vivo anterior (misma puerta, mismos mensajes, mismo reparto).
-- destructivo-ok: create or replace de una funcion
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b5.sql
set local lock_timeout = '8s';

create or replace function public.usuario_da_alcance(p_user_id uuid, p_rol text, p_empresas text[])
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_old public.usuarios%rowtype; v_amb text; v_emp text[]; v_quita int := 0; v_quita_s int := 0; v_p uuid[]; v_ps uuid[]; v_yo public.usuarios%rowtype;
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
  if not v_old.activo then
    raise exception 'Esa cuenta está desactivada: reactívala primero y luego dale el nivel' using errcode = '22023';
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
  if cardinality(v_emp) > 0 then
    select coalesce(array_agg(x.id), '{}') into v_p
      from unnest(coalesce(v_old.proyectos, '{}')) x(id)
      join public.proyectos p on p.id = x.id and p.empresa = any (v_emp);
    select coalesce(array_agg(x.id), '{}') into v_ps
      from unnest(coalesce(v_old.proyectos_supervisados, '{}')) x(id)
      join public.proyectos p on p.id = x.id and p.empresa = any (v_emp);
    v_quita := cardinality(coalesce(v_old.proyectos, '{}')) - cardinality(v_p);
    v_quita_s := cardinality(coalesce(v_old.proyectos_supervisados, '{}')) - cardinality(v_ps);
  else
    v_p := coalesce(v_old.proyectos, '{}'); v_ps := coalesce(v_old.proyectos_supervisados, '{}');
  end if;
  update public.usuarios u
     set rol = p_rol, ambito = v_amb, empresas = v_emp, proyectos = v_p, proyectos_supervisados = v_ps
   where u.user_id = p_user_id;
  select * into v_yo from public.usuarios y where y.user_id = (select auth.uid());
  insert into public.usuarios_cambios_alcance (quien, quien_email, a_quien, a_email, accion, antes, despues)
  values (v_yo.user_id, v_yo.email, p_user_id, v_old.email, 'nivel',
          jsonb_build_object('rol', v_old.rol, 'ambito', v_old.ambito, 'empresas', to_jsonb(v_old.empresas),
                             'proyectos', to_jsonb(v_old.proyectos), 'proyectos_supervisados', to_jsonb(v_old.proyectos_supervisados)),
          jsonb_build_object('rol', p_rol, 'ambito', v_amb, 'empresas', to_jsonb(v_emp),
                             'proyectos', to_jsonb(v_p), 'proyectos_supervisados', to_jsonb(v_ps)));
  return jsonb_build_object('rol', p_rol, 'ambito', v_amb, 'empresas', to_jsonb(v_emp),
                            'proyectos_quitados', v_quita, 'supervisados_quitados', v_quita_s);
end $function$;
