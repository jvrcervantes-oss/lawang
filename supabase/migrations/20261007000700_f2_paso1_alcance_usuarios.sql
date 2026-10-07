-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · PASO 1 del encargo «empresas» (7-oct-2026): ADITIVO Y DORMIDO. Nadie tiene todavia un rol de empresa, asi que hoy nadie ve ni puede nada distinto.
--   es_admin()/es_super_admin() NO se tocan (revision de Seguridad): el «nace cerrado» sale de dos ROLES NUEVOS, admin_empresa y super_admin_empresa,
--   que no coinciden con ninguna comparacion literal = 'admin' / = 'super_admin' ni con las dos funciones. Un usuario de empresa se comporta hoy como un agente
--   sin proyectos (es_agente() lo deja pasar, como a cualquier ficha activa). Lo que habra que ensenarle a reconocer: encargos/20261006_lawang_empresas_f2_inventario_rol.md.
--   Columnas nuevas en usuarios: ambito ('global'|'empresa'), empresas text[], es_propietario boolean (todas con default: los 34 usuarios quedan global/{}/false).
--   Candado: SOLO el propietario cambia ambito, empresas, es_propietario y los roles de empresa; nadie se los cambia a si mismo; no puede quedar la base sin propietario;
--   al propietario no le cambia el rol ni lo desactiva otro. Altas (INSERT) con esos valores: solo el propietario con sesion, o postgres (migraciones).
--   service_role/API sin sesion de usuario (session_user = authenticator) NO puede tocarlos: decision mas estricta que en F1 a proposito (aqui hay privilegios de por medio);
--   la edge admin-usuarios inserta con service_role y no manda ninguno de estos campos, asi que sigue igual; si algun dia crea usuarios de empresa, lo hara con el propietario.
--   usuario_guarda_permisos y usuario_supervisa_proyecto NO se convierten (paso 2): con el CHECK de coherencia ambito<->rol y este trigger no pueden dar un rol de empresa.
-- Visibilidad aceptada (decision escrita): la politica de usuarios deja leer todas las filas al equipo, asi que ambito/empresas/es_propietario son legibles por cualquier ficha activa.
-- destructivo-ok: solo anade columnas con default, constraints que cumplen las 34 filas actuales, funciones y triggers; no borra ni reescribe filas (salvo marcar al propietario).
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_paso1.sql (probada: devuelve rol_check y el trigger a su definicion anterior).

-- 1. Roles nuevos en el CHECK de rol + columnas nuevas (todo en la misma transaccion/migracion).
alter table public.usuarios drop constraint usuarios_rol_check;
alter table public.usuarios add constraint usuarios_rol_check
  check (rol = any (array['super_admin','admin','agente','sales_manager','project_manager','admin_empresa','super_admin_empresa']));

alter table public.usuarios
  add column ambito text not null default 'global' check (ambito in ('global','empresa')),
  add column empresas text[] not null default '{}',
  add column es_propietario boolean not null default false;
comment on column public.usuarios.ambito is 'global = como siempre; empresa = solo ve/gestiona las empresas de usuarios.empresas. Va con los roles admin_empresa/super_admin_empresa (CHECK). Solo el propietario lo cambia.';
comment on column public.usuarios.empresas is 'claves de public.empresas que el usuario controla (trigger: sin empresas fantasma). En un rol de empresa es su alcance; en un usuario global vacio = sin restriccion. Solo el propietario lo cambia.';
comment on column public.usuarios.es_propietario is 'Nivel super super admin del owner: unico que cambia ambito/empresas/es_propietario/roles de empresa. Va con rol super_admin global activo (CHECK).';

alter table public.usuarios add constraint usuarios_ambito_rol_check check (
  (ambito = 'global'  and rol not in ('admin_empresa','super_admin_empresa'))
  or (ambito = 'empresa' and rol in ('admin_empresa','super_admin_empresa')));
alter table public.usuarios add constraint usuarios_propietario_check check (
  not es_propietario or (rol = 'super_admin' and ambito = 'global' and activo));

-- 2. Marcar al propietario ANTES de cambiar el trigger de usuarios (si no, el candado nuevo no dejaria ni marcarlo). Exactamente uno, y es super_admin global.
do $$
declare v int;
begin
  update public.usuarios set es_propietario = true where lower(email) = 'jvr.cervantes@gmail.com' and rol = 'super_admin' and activo;
  get diagnostics v = row_count;
  if v <> 1 or (select count(*) from public.usuarios where es_propietario) <> 1 then
    raise exception 'Se esperaba exactamente 1 propietario (Javier Cervantes, super_admin); marcados: %', v;
  end if;
end $$;

-- 3. Comprobaciones nuevas. Todas STABLE SECURITY DEFINER, search_path vacio; nada para anon.
create or replace function public.es_propietario() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.usuarios u
                  where u.user_id = (select auth.uid()) and u.activo and u.es_propietario
                    and u.rol = 'super_admin' and u.ambito = 'global')
$$;

-- admin de esa empresa: cualquier admin/super GLOBAL de siempre (es_admin()), o un rol de empresa que la tenga. empresa nula: solo global.
create or replace function public.es_admin_de(p_empresa text) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.es_admin() or (p_empresa is not null and exists (
    select 1 from public.usuarios u
     where u.user_id = (select auth.uid()) and u.activo and u.ambito = 'empresa'
       and u.rol in ('admin_empresa','super_admin_empresa') and p_empresa = any (u.empresas)))
$$;

create or replace function public.es_super_admin_de(p_empresa text) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.es_super_admin() or (p_empresa is not null and exists (
    select 1 from public.usuarios u
     where u.user_id = (select auth.uid()) and u.activo and u.ambito = 'empresa'
       and u.rol = 'super_admin_empresa' and p_empresa = any (u.empresas)))
$$;

-- alcance sobre una empresa (NO da permiso por si solo: cada funcion lo combina con su propio rol). nula -> false. Sin ficha activa -> false.
--   global: admin/super siempre; el resto, si su lista de empresas esta vacia (hoy los 34) o la incluye. empresa: solo si la incluye.
create or replace function public.puede_empresa(p_empresa text) returns boolean
language sql stable security definer set search_path = '' as $$
  select p_empresa is not null and exists (
    select 1 from public.usuarios u
     where u.user_id = (select auth.uid()) and u.activo
       and ((u.ambito = 'global' and (u.rol in ('super_admin','admin') or cardinality(u.empresas) = 0 or p_empresa = any (u.empresas)))
         or (u.ambito = 'empresa' and p_empresa = any (u.empresas))))
$$;

-- lo que la pantalla necesitara para saber quien es quien llama (solo lo propio).
create or replace function public.mi_alcance() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('rol', u.rol, 'ambito', u.ambito, 'empresas', to_jsonb(u.empresas), 'es_propietario', u.es_propietario)
    from public.usuarios u where u.user_id = (select auth.uid()) and u.activo
$$;

revoke all on function public.es_propietario(), public.es_admin_de(text), public.es_super_admin_de(text), public.puede_empresa(text), public.mi_alcance() from public, anon;
grant execute on function public.es_propietario(), public.es_admin_de(text), public.es_super_admin_de(text), public.puede_empresa(text) to authenticated, lw_lector;
grant execute on function public.mi_alcance() to authenticated;

-- 4. Sin empresas fantasma (DEFINER: lee public.empresas sin depender de la politica de quien escribe).
create or replace function public.usuarios_empresas_validas() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from unnest(new.empresas) e(c) where c is null or not exists (select 1 from public.empresas x where x.clave = c)) then
    raise exception 'usuarios.empresas solo admite claves que existan en public.empresas' using errcode = '22023';
  end if;
  return new;
end $$;
revoke all on function public.usuarios_empresas_validas() from public, anon, authenticated;
create trigger usuarios_empresas_validas before insert or update of empresas on public.usuarios
  for each row execute function public.usuarios_empresas_validas();

-- 5. Candado de alta (INSERT) y de baja (DELETE del propietario).
create or replace function public.usuarios_candado_alta() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.es_propietario or new.ambito <> 'global' or cardinality(new.empresas) > 0 or new.rol in ('admin_empresa','super_admin_empresa') then
    if (select auth.uid()) is null then
      if session_user not in ('postgres','supabase_admin') then
        raise exception 'Alcance de empresa o propietario: solo el propietario (con sesion) lo da' using errcode = '42501';
      end if;
    elsif not public.es_propietario() then
      raise exception 'Solo el propietario da un alcance de empresa o el nivel propietario' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
revoke all on function public.usuarios_candado_alta() from public, anon, authenticated;
create trigger usuarios_candado_alta before insert on public.usuarios
  for each row execute function public.usuarios_candado_alta();

create or replace function public.usuarios_candado_baja() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if old.es_propietario and not exists (select 1 from public.usuarios o where o.es_propietario and o.activo and o.user_id <> old.user_id) then
    raise exception 'No puede quedar la base sin propietario' using errcode = '42501';
  end if;
  return old;
end $$;
revoke all on function public.usuarios_candado_baja() from public, anon, authenticated;
create trigger usuarios_candado_baja before delete on public.usuarios
  for each row execute function public.usuarios_candado_baja();

-- 6. Candado de cambios (UPDATE): mismo trigger de siempre, ampliado. Definicion anterior guardada en supabase/reversion_f2/REVERSION_f2_paso1.sql.
create or replace function public.usuarios_bloquea_cambio_rol_herramientas() returns trigger
language plpgsql set search_path = '' as $$
declare v_uid uuid := (select auth.uid());
begin
  -- lo de siempre
  if (new.rol is distinct from old.rol or new.herramientas is distinct from old.herramientas)
     and not public.es_super_admin() then
    raise exception 'Solo un super_admin puede cambiar el rol o las herramientas de un usuario'
      using errcode = '42501';
  end if;
  -- nuevo: alcance de empresa y propietario
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
  -- el propietario: no lo edita otro (rol/activo) y no puede quedar la base sin uno
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
$$;
