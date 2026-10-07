-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · bloque 5 · migracion 4 (8-oct-2026): LAS DOS PUERTAS QUE USA LA EDGE `admin-usuarios` PARA UN ROL DE EMPRESA.
--   * `usuario_alta_empresa(...)`: da de alta la ficha de una persona que la edge acaba de crear en Auth. La ficha NACE ENTERA de una vez (ambito global, rol agente —o sales_manager /
--     project_manager si lo da un super de empresa—, empresas = las del llamador o un subconjunto, herramientas ⊆ las del llamador): nunca se inserta vacia para rellenarla despues
--     (una lista de empresas vacia es «global sin restriccion»: fallo abierto). Las empresas las fija el servidor, no el navegador.
--     Guardas contra abuso (se llama con la sesion de quien da el alta y recibe un user_id): la cuenta de Auth debe existir con ese correo, tener < 10 min, no haber iniciado sesion nunca, no llevar
--     el flag legacy app_metadata.agente, no tener ya ficha y no ser un correo de comprador del portal. Asi no sirve para «convertir» a un comprador ni a una cuenta ajena en agente.
--     El candado de alta de `usuarios` (migracion 3) repite la regla como ultimo cerrojo.
--   * `usuario_puede_poner_clave(uuid)`: ¿puede quien llama poner la contrasena de esa cuenta? Persona gestionable Y todas sus herramientas son suyas (poner la clave de una cuenta con herramientas que no
--     tienes es usarlas entrando con ella; regla LAW-343, la misma que para el admin global).
--   Ambas con EXECUTE solo para `authenticated` (no `anon`, no `lw_lector`); llamador con nombre: la edge admin-usuarios.
-- destructivo-ok: 2 funciones nuevas; sin tocar datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b5.sql
set local lock_timeout = '8s';

create or replace function public.usuario_alta_empresa(p_user_id uuid, p_email text, p_nombre text, p_rol text,
                                                       p_herramientas text[], p_tipos_contrato text[], p_empresas text[])
returns jsonb
language plpgsql security definer set search_path = '' as $function$
declare v_gest text[]; v_emp text[]; v_au auth.users%rowtype; v_yo public.usuarios%rowtype; v_email text := lower(btrim(coalesce(p_email, '')));
        v_herr text[] := coalesce(p_herramientas, '{}'); v_tipos text[] := coalesce(p_tipos_contrato, '{}');
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  v_gest := public._gestor_empresas();
  if v_gest is null then
    raise exception 'Solo un administrador de empresa con la herramienta Usuarios da de alta a su equipo' using errcode = '42501';
  end if;
  select * into v_yo from public.usuarios y where y.user_id = (select auth.uid());
  v_emp := coalesce((select array_agg(distinct e order by e) from unnest(case when cardinality(coalesce(p_empresas, '{}')) = 0 then v_gest else p_empresas end) e), '{}');
  if cardinality(v_emp) = 0 or not (v_emp <@ v_gest) then
    raise exception 'Solo puedes dar empresas que son tuyas' using errcode = '42501';
  end if;
  if p_rol is null or not (p_rol = any (case when v_yo.rol = 'super_admin_empresa' then array['agente','sales_manager','project_manager'] else array['agente'] end)) then
    raise exception 'Ese nivel no lo da un administrador de empresa' using errcode = '42501';
  end if;
  if not (v_herr <@ coalesce(v_yo.herramientas, '{}')) then
    raise exception 'No puedes dar herramientas que no tienes tú' using errcode = '42501';
  end if;
  if v_yo.rol <> 'super_admin_empresa' and not (v_tipos <@ coalesce(v_yo.tipos_contrato, '{}')) then
    raise exception 'No puedes dar tipos de contrato que no tienes tú' using errcode = '42501';
  end if;
  if v_email !~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' then raise exception 'Correo no válido' using errcode = '22023'; end if;
  select * into v_au from auth.users a where a.id = p_user_id;
  if not found or lower(coalesce(v_au.email, '')) <> v_email then
    raise exception 'La cuenta de acceso no existe o no es de ese correo' using errcode = '22023';
  end if;
  if v_au.created_at < now() - interval '10 minutes' or v_au.last_sign_in_at is not null then
    raise exception 'Solo se da de alta una cuenta recién creada' using errcode = '22023';
  end if;
  if coalesce(v_au.raw_app_meta_data, '{}'::jsonb) ? 'agente' then
    raise exception 'Esa cuenta lleva el marcador antiguo de agente: no se da de alta por aquí' using errcode = '22023';
  end if;
  if exists (select 1 from public.usuarios x where x.user_id = p_user_id or lower(x.email) = v_email) then
    raise exception 'Esa persona ya tiene ficha' using errcode = '22023';
  end if;
  if exists (select 1 from public.portal_accesos pa where lower(pa.email) = v_email) then
    raise exception 'Ese correo es de un comprador del portal' using errcode = '22023';
  end if;
  insert into public.usuarios (user_id, email, nombre, rol, herramientas, tipos_contrato, activo, creado_por, ambito, empresas)
  values (p_user_id, v_email, nullif(btrim(coalesce(p_nombre, '')), ''), p_rol, v_herr, v_tipos, true, v_yo.email, 'global', v_emp);
  insert into public.usuarios_cambios_alcance (quien, quien_email, a_quien, a_email, accion, antes, despues)
  values (v_yo.user_id, v_yo.email, p_user_id, v_email, 'alta', '{}'::jsonb,
          jsonb_build_object('rol', p_rol, 'ambito', 'global', 'empresas', to_jsonb(v_emp), 'herramientas', to_jsonb(v_herr)));
  return jsonb_build_object('user_id', p_user_id, 'email', v_email, 'rol', p_rol, 'empresas', to_jsonb(v_emp));
end $function$;

create or replace function public.usuario_puede_poner_clave(p_user_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public._usuario_gestionable(p_user_id)
     and coalesce((select t.herramientas from public.usuarios t where t.user_id = p_user_id), '{}'::text[])
         <@ coalesce(public._gestor_herramientas(), '{}'::text[])
$$;

revoke all on function public.usuario_alta_empresa(uuid, text, text, text, text[], text[], text[]), public.usuario_puede_poner_clave(uuid) from public, anon, authenticated;
grant execute on function public.usuario_alta_empresa(uuid, text, text, text, text[], text[], text[]) to authenticated;
grant execute on function public.usuario_puede_poner_clave(uuid) to authenticated;
