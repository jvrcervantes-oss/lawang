-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · cierre · bloque 1 · migracion 1 (8-oct-2026): proyectos y parcelas por empresa.
--   Un admin_empresa / super_admin_empresa hace, EN SUS EMPRESAS, lo que un admin / super_admin global (owner 7-oct: «administrador en una empresa significa poder borrar»).
--   La empresa se deduce SIEMPRE en el servidor desde el objeto (proyecto, unidad); si el objeto no tiene empresa solo pasa un admin/super global (nace cerrado).
--   es_admin()/es_super_admin() NO se tocan. Cada puerta pasa a es_admin_de(<empresa del objeto>) / es_super_admin_de(<empresa del objeto>).
--   Funciones: es_manager_de, _puede_editar_proyectos, proyecto_alta (nace en una empresa de quien la crea), proyecto_cambiar_estado, proyecto_fijar_plazo, proyecto_guarda,
--   renombrar_proyecto, unidad_guarda, unidad_socio_asigna, unidad_parte_cobrada_split, socios_parcelas, borrar_proyecto, borrar_unidad, trg_valida_unidad_id_contrato,
--   trg_proyecto_empresa (deja crear con empresa a un rol de empresa de ESA empresa).
--   proyecto_empresa_guarda NO se toca: cambiar la empresa de un proyecto existente sigue siendo solo de un super global (propietario incluido).
--   Metodo: parche sobre pg_get_functiondef con el numero de apariciones esperado (raise si no cuadra), como pide reference_parchear_funcion_viva_con_marca.
-- destructivo-ok: create or replace de funciones; drop de proyecto_alta(text) solo para sustituirla por proyecto_alta(text,text) con el mismo comportamiento para el resto de roles; sin borrar datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b1.sql

create or replace function pg_temp.parchea(p_f regprocedure, p_old text, p_new text, p_n int default 1) returns void language plpgsql as $f$
declare v text; v_c int;
begin
  v := pg_get_functiondef(p_f);
  v_c := (length(v) - length(replace(v, p_old, ''))) / length(p_old);
  if v_c <> p_n then
    raise exception 'parche f2_b1: «%» aparece % veces en %, esperaba %', p_old, v_c, p_f, p_n;
  end if;
  execute replace(v, p_old, p_new);
end $f$;

-- 1. es_manager_de: el admin de empresa gestiona los proyectos de SUS empresas (el project_manager sigue igual)
create or replace function public.es_manager_de(p_proyecto_id uuid)
 returns boolean language sql stable security definer set search_path = '' as $$
  select case
    when public.es_admin() then true
    when p_proyecto_id is null then false
    else exists (
      select 1 from public.usuarios u
       where u.user_id = (select auth.uid()) and u.activo
         and u.rol = 'project_manager'
         and p_proyecto_id = any (u.proyectos_supervisados))
      or exists (
      select 1 from public.usuarios u join public.proyectos pr on pr.id = p_proyecto_id
       where u.user_id = (select auth.uid()) and u.activo and u.ambito = 'empresa'
         and u.rol in ('admin_empresa', 'super_admin_empresa') and pr.empresa = any (u.empresas))
  end
$$;

-- 2. _puede_editar_proyectos: puerta general (sin objeto); cada llamador ya comprueba el proyecto concreto con es_manager_de
select pg_temp.parchea('public._puede_editar_proyectos()'::regprocedure,
  $q$u.rol = 'project_manager')$q$,
  $q$u.rol in ('project_manager', 'admin_empresa', 'super_admin_empresa'))$q$);

-- 3. proyecto_alta: nace en una empresa de quien lo crea
drop function public.proyecto_alta(text);
create function public.proyecto_alta(p_nombre text, p_empresa text default null)
 returns uuid language plpgsql security definer set search_path = '' as $$
declare v uuid; v_nom text := btrim(coalesce(p_nombre, '')); v_emp text; v_mias text[];
begin
  select u.empresas into v_mias from public.usuarios u
   where u.user_id = (select auth.uid()) and u.activo and u.ambito = 'empresa' and u.rol in ('admin_empresa', 'super_admin_empresa');
  if not public.es_admin() and v_mias is null then
    raise exception 'Dar de alta un proyecto es cosa de un administrador. Pídeselo a dirección.' using errcode = '42501';
  end if;
  if not public.es_admin() then
    -- admin / super de empresa: el proyecto nace en UNA DE SUS empresas; lo que mande el navegador solo se acepta si es una de las suyas
    if p_empresa is not null then
      if not (p_empresa = any (v_mias)) then
        raise exception 'Solo puedes dar de alta proyectos de tus empresas' using errcode = '42501';
      end if;
      v_emp := p_empresa;
    elsif cardinality(v_mias) = 1 then
      v_emp := v_mias[1];
    else
      raise exception 'Tu cuenta gestiona varias empresas: indica en cuál se da de alta el proyecto' using errcode = '22023';
    end if;
  elsif p_empresa is not null then
    -- global: la empresa al crear solo la fija un super (igual que proyecto_empresa_guarda)
    if not public.es_super_admin() then
      raise exception 'La empresa de un proyecto la fija solo un super administrador' using errcode = '42501';
    end if;
    v_emp := p_empresa;
  end if;
  if v_emp is not null and not exists (select 1 from public.empresas e where e.clave = v_emp and e.activa) then
    raise exception 'Esa empresa no existe o esta desactivada' using errcode = '22023';
  end if;
  if v_nom = '' or length(v_nom) > 120 then raise exception 'El nombre no puede quedar vacío' using errcode = '22023'; end if;
  if v_nom ~ '^[=+\-@]' then raise exception 'El nombre no puede empezar por = + - @' using errcode = '22023'; end if;
  if exists (select 1 from public.proyectos p where lower(p.nombre) = lower(v_nom)) then
    raise exception 'Ya existe un proyecto con ese nombre.' using errcode = '23505';
  end if;
  insert into public.proyectos (nombre, creado_por, empresa) values (v_nom, (select auth.email()), v_emp) returning id into v;
  return v;
end $$;
revoke all on function public.proyecto_alta(text, text) from public, anon;
grant execute on function public.proyecto_alta(text, text) to authenticated, service_role;

-- 4. el trigger de la empresa deja INSERTAR con empresa a un rol de empresa de ESA empresa (cambiarla despues sigue siendo solo de un super global)
select pg_temp.parchea('public.trg_proyecto_empresa()'::regprocedure,
  $q$if (select auth.uid()) is null then return new; end if;$q$,
  $q$if (select auth.uid()) is null then return new; end if;
  if tg_op = 'INSERT' and not public.es_admin() and public.es_admin_de(new.empresa) then return new; end if;$q$);

-- 5. proyectos: estado, plazos, ficha, renombrar
select pg_temp.parchea('public.proyecto_cambiar_estado(uuid,text,boolean,text)'::regprocedure,
  $q$if not public.es_admin() then$q$, $q$if not public.es_admin_de(public.empresa_de_proyecto(p_proyecto_id)) then$q$);
select pg_temp.parchea('public.proyecto_fijar_plazo(uuid,integer,integer)'::regprocedure,
  $q$if not public.es_admin() then$q$, $q$if not public.es_admin_de(public.empresa_de_proyecto(p_proyecto_id)) then$q$);
select pg_temp.parchea('public.proyecto_guarda(uuid,jsonb)'::regprocedure,
  $q$if not public.es_admin() then$q$, $q$if not public.es_admin_de(public.empresa_de_proyecto(p_id)) then$q$);
select pg_temp.parchea('public.renombrar_proyecto(text,text)'::regprocedure,
  $q$if not public.es_admin() then$q$,
  $q$if not public.es_admin_de((select pr.empresa from public.proyectos pr where pr.nombre = p_antiguo)) then$q$);
select pg_temp.parchea('public.renombrar_proyecto(text,text)'::regprocedure,
  $q$raise exception 'Solo un administrador puede renombrar un proyecto';$q$,
  $q$raise exception 'Solo un administrador puede renombrar un proyecto' using errcode = '42501';$q$);

-- 6. parcelas
select pg_temp.parchea('public.unidad_guarda(uuid,jsonb,text)'::regprocedure,
  $q$v_admin boolean := public.es_admin();$q$,
  $q$v_admin boolean := public.es_admin_de(public.empresa_de_unidad(p_id));$q$);
select pg_temp.parchea('public.unidad_socio_asigna(uuid,uuid,text)'::regprocedure,
  $q$if not public.es_admin() then$q$, $q$if not public.es_admin_de(public.empresa_de_unidad(p_unidad)) then$q$);
select pg_temp.parchea('public.unidad_parte_cobrada_split(uuid)'::regprocedure,
  $q$or public.es_admin()) as ok$q$, $q$or public.es_admin_de(public.empresa_de_unidad(p_unidad))) as ok$q$);
-- socios: catalogo COMPARTIDO sin empresa (los 11 son de san_dal_woods pero estan asignados tambien en Palm Field, de Lawang). Nace cerrado en lo que no se puede atribuir:
--   quien tiene alcance restringido (rol de empresa o lista de empresas) solo ve y asigna socios YA asignados en parcelas de SUS empresas; el primero de cada empresa lo asigna un admin global.
--   Sin alcance restringido (los 34 de hoy) todo igual que antes.
create or replace function public.socios_parcelas(p_proyecto_id uuid)
 returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if not public.es_admin_de(public.empresa_de_proyecto(p_proyecto_id)) then raise exception 'Solo un administrador ve los socios' using errcode = '42501'; end if;
  return jsonb_build_object(
    'socios', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'numero', s.numero, 'nombre', s.nombre,
                                                            'tipo', s.tipo, 'sociedad', s.sociedad, 'activo', s.activo)
                                         order by s.nombre)
                          from public.socios s
                         where (s.activo
                            or exists (select 1 from public.unidad_socio us join public.unidades u on u.id = us.unidad_id
                                        where us.socio_id = s.id and u.proyecto_id = p_proyecto_id))
                           and (not public.alcance_restringido()
                            or exists (select 1 from public.unidad_socio u2s join public.unidades un2 on un2.id = u2s.unidad_id
                                         join public.proyectos pr2 on pr2.id = un2.proyecto_id
                                        where u2s.socio_id = s.id and public.puede_empresa(pr2.empresa)))), '[]'::jsonb),
    'asignaciones', coalesce((select jsonb_agg(jsonb_build_object('unidad_id', us.unidad_id, 'socio_id', us.socio_id,
                                                                  'nota', us.nota))
                                from public.unidad_socio us
                                join public.unidades u on u.id = us.unidad_id
                               where u.proyecto_id = p_proyecto_id), '[]'::jsonb));
end $$;
select pg_temp.parchea('public.unidad_socio_asigna(uuid,uuid,text)'::regprocedure,
  $q$if length(v_nota) > 500 then raise exception 'La nota no puede pasar de 500 caracteres' using errcode = '22023'; end if;$q$,
  $q$if length(v_nota) > 500 then raise exception 'La nota no puede pasar de 500 caracteres' using errcode = '22023'; end if;
  if p_socio is not null and public.alcance_restringido() and not exists (
       select 1 from public.unidad_socio us join public.unidades un on un.id = us.unidad_id join public.proyectos pr on pr.id = un.proyecto_id
        where us.socio_id = p_socio and public.puede_empresa(pr.empresa)) then
    raise exception 'Ese socio no esta asignado todavia en tus empresas: la primera asignacion la hace un administrador global' using errcode = '42501';
  end if;$q$);
select pg_temp.parchea('public.trg_valida_unidad_id_contrato()'::regprocedure,
  $q$and not public.es_admin() then$q$, $q$and not public.es_admin_de(public.empresa_de_contrato(new.id)) then$q$);

-- 7. borrar (lo que borra un super global lo borra un super de empresa, en su empresa)
select pg_temp.parchea('public.borrar_proyecto(text)'::regprocedure,
  $q$if not public.es_super_admin() then$q$,
  $q$if not public.es_super_admin_de((select pr.empresa from public.proyectos pr where pr.nombre = p_nombre)) then$q$);
select pg_temp.parchea('public.borrar_unidad(uuid)'::regprocedure,
  $q$if not public.es_super_admin() then$q$, $q$if not public.es_super_admin_de(public.empresa_de_unidad(p_id)) then$q$);

-- 8. lectura: proyecto_vinculos_datos (aviso previo al borrado) NO se toca: su duena es lw_lector (sin bypass de RLS), asi que ya cuenta solo lo que la policy
--    de la persona deja ver (medido 8-oct: un admin_empresa de otra empresa recibe ceros). Misma razon para el resto de funciones de lectura de este dominio duenas de lw_lector.
