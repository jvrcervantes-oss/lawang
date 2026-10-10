-- Vuelta atras de 20261010200000_bot_conversaciones_casilla_suficiente (LAW-513). Restaura las tres funciones a su forma anterior.
-- NO borra bot_casilla_log (es un registro; si de verdad se quiere quitar: exportarlo y luego drop table public.bot_casilla_log).
-- destructivo-ok: solo create or replace de funciones y drop del trigger de registro.
drop trigger if exists usuarios_bot_casilla_log on public.usuarios;
drop function if exists public.usuarios_bot_casilla_log();

create or replace function public._bot_conversaciones_autoriza(p_tel text, p_accion text)
returns void language plpgsql security definer set search_path = '' as $f$
declare
  v_quien text := coalesce(nullif((select auth.email()), ''), '');
  v_tel text := case when p_tel is null then null else public._bot_tel(p_tel) end;
begin
  if p_accion not in ('lista', 'hilo') then
    raise exception 'Accion de lectura no valida' using errcode = 'PT400';
  end if;
  if p_tel is not null and v_tel is null then
    raise exception 'Telefono no valido' using errcode = 'PT400';
  end if;
  if v_quien = '' or not exists (
    select 1 from public.usuarios u
     where u.user_id = (select auth.uid()) and u.activo
       and u.ambito = 'global' and coalesce(cardinality(u.empresas), 0) = 0
       and (u.rol = 'super_admin' or 'bot_conversaciones_ver' = any (u.herramientas))
  ) then
    raise exception 'Sin permiso para leer las conversaciones del bot' using errcode = '42501';
  end if;
  insert into public.bot_lecturas_log (usuario, tel, accion) values (left(v_quien, 120), v_tel, p_accion);
end $f$;

create or replace function public.usuarios_candado_alta()
returns trigger language plpgsql security definer set search_path = '' as $f$
begin
  if new.es_propietario or new.ambito <> 'global' or cardinality(new.empresas) > 0 or new.rol in ('admin_empresa','super_admin_empresa') then
    if (select auth.uid()) is null then
      if session_user not in ('postgres','supabase_admin') then
        raise exception 'Alcance de empresa o propietario: solo el propietario (con sesion) lo da' using errcode = '42501';
      end if;
    elsif not public.es_propietario() then
      if not public._alta_empresa_permitida(new.rol, new.ambito, new.empresas, new.herramientas, new.proyectos, new.es_propietario) then
        raise exception 'Solo el propietario da un alcance de empresa o el nivel propietario' using errcode = '42501';
      end if;
    end if;
  end if;
  return new;
end $f$;

create or replace function public.usuarios_bloquea_cambio_rol_herramientas()
returns trigger language plpgsql set search_path = '' as $f$
declare v_uid uuid := (select auth.uid());
begin
  if (new.rol is distinct from old.rol or new.herramientas is distinct from old.herramientas)
     and not public.es_super_admin() then
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
$f$;
