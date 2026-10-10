-- LAW-513 (10-oct-2026, decision del owner): la casilla `bot_conversaciones_ver` pasa a ser SUFICIENTE para leer las conversaciones del bot.
-- Antes la regla exigia ademas «sin empresas marcadas», asi que dar la casilla a Andrea (super_admin con empresas [lawang, sandal_woods])
-- no le abria nada. El bot atiende a las dos empresas a la vez: quien reciba la casilla ve los chats de TODAS (el panel de Usuarios lo avisa).
-- Revision previa n.o 253 (Seguridad + Frontend). Cambios:
--  1. _bot_conversaciones_autoriza: usuario activo AND ambito 'global' AND (casilla OR (super_admin sin empresas)). Ambito 'empresa' con casilla: NO
--     (ese ambito existe para quedar acotado). Super_admin con empresas y SIN casilla: NO (si no, la casilla no significaria nada).
--     Cada lectura sigue apuntandose en bot_lecturas_log. NUEVO tope: 300 lecturas por usuario y hora (PT429), para que una sesion robada
--     no vuelque todo el historial ni llene el registro.
--  2. Quien concede la casilla: cualquier super_admin (decision del owner), nunca un gestor no-super (42501, tambien en el alta).
--  3. bot_casilla_log (solo anade, nunca se purga): quien concedio o retiro la casilla, a quien y cuando. Hasta hoy no quedaba rastro.
-- El dato tiene un dueno: la casilla vive en usuarios.herramientas (dueno: la ficha del usuario); el log guarda el correo como copia
-- congelada Y el user_id, para saber a quien fue aunque cambie el correo.
-- Vuelta atras: supabase/reversion_casilla_bot_conv/REVERSION.sql.
-- destructivo-ok: el unico drop es «drop trigger if exists» de un trigger que esta misma migracion crea (idempotencia); la palabra truncate
-- solo aparece en el trigger que PROHIBE truncar el registro. No se borra ningun dato.

-- ── 1. registro de concesiones ──
create table if not exists public.bot_casilla_log (
  id           bigint generated always as identity primary key,
  cuando       timestamptz not null default now(),
  quien        text not null check (length(quien) <= 120),   -- correo de la sesion; 'servicio' si lo hizo una edge con service_role
  a_quien_id   uuid not null,
  a_quien      text not null check (length(a_quien) <= 120),
  accion       text not null check (accion in ('alta', 'baja'))
);
alter table public.bot_casilla_log enable row level security;
revoke all on public.bot_casilla_log from public, anon, authenticated, service_role;
revoke all on sequence public.bot_casilla_log_id_seq from public, anon, authenticated, service_role;
do $c$ begin
  if not exists (select 1 from pg_trigger where tgname = 'trg_bot_casilla_log_solo_anade' and tgrelid = 'public.bot_casilla_log'::regclass) then
    create trigger trg_bot_casilla_log_solo_anade before update or delete on public.bot_casilla_log
      for each row execute function public.bot_acciones_log_solo_anade();
    create trigger trg_bot_casilla_log_no_truncate before truncate on public.bot_casilla_log
      for each statement execute function public.bot_acciones_log_solo_anade();
  end if;
end $c$;

create or replace function public.usuarios_bot_casilla_log()
returns trigger language plpgsql security definer set search_path = '' as $f$
declare
  v_tenia boolean := tg_op = 'UPDATE' and 'bot_conversaciones_ver' = any (coalesce(old.herramientas, '{}'));
  v_tiene boolean := 'bot_conversaciones_ver' = any (coalesce(new.herramientas, '{}'));
begin
  if v_tenia is distinct from v_tiene then
    insert into public.bot_casilla_log (quien, a_quien_id, a_quien, accion)
    values (left(coalesce(nullif((select auth.email()), ''), 'servicio'), 120), new.user_id, left(coalesce(new.email, ''), 120),
            case when v_tiene then 'alta' else 'baja' end);
  end if;
  return null;
end $f$;
revoke all on function public.usuarios_bot_casilla_log() from public, anon, authenticated, service_role;
drop trigger if exists usuarios_bot_casilla_log on public.usuarios;
create trigger usuarios_bot_casilla_log after insert or update of herramientas on public.usuarios
  for each row execute function public.usuarios_bot_casilla_log();

-- ── 2. solo un super_admin concede o retira la casilla (cambio de ficha) ──
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
    -- LAW-513: dar o quitar la lectura de los chats del bot es de un super_admin, aunque el gestor la tenga y pudiera «darla» como cualquier otra.
    if ('bot_conversaciones_ver' = any (coalesce(new.herramientas, '{}'))) is distinct from ('bot_conversaciones_ver' = any (coalesce(old.herramientas, '{}'))) then
      raise exception 'Solo un super_admin concede o retira la casilla de conversaciones del bot' using errcode = '42501';
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

-- ── 2b. y tampoco en el ALTA de una ficha (la policy de insert solo pide es_admin) ──
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
  -- LAW-513: una ficha nueva no nace con la casilla de los chats del bot si quien la crea (con sesion) no es super_admin.
  if (select auth.uid()) is not null and 'bot_conversaciones_ver' = any (coalesce(new.herramientas, '{}')) and not public.es_super_admin() then
    raise exception 'Solo un super_admin concede la casilla de conversaciones del bot' using errcode = '42501';
  end if;
  return new;
end $f$;

-- ── 3. la regla de lectura ──
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
  -- La casilla basta (aunque haya empresas marcadas: el bot mezcla las dos y el panel lo avisa). Un super_admin SIN casilla solo lee si no
  -- tiene empresas marcadas, como hasta hoy. El ambito 'empresa' nunca lee, ni con la casilla.
  if v_quien = '' or not exists (
    select 1 from public.usuarios u
     where u.user_id = (select auth.uid()) and u.activo
       and u.ambito = 'global'
       and ('bot_conversaciones_ver' = any (coalesce(u.herramientas, '{}'))
            or (u.rol = 'super_admin' and coalesce(cardinality(u.empresas), 0) = 0))
  ) then
    raise exception 'Sin permiso para leer las conversaciones del bot' using errcode = '42501';
  end if;
  if (select count(*) from public.bot_lecturas_log where usuario = left(v_quien, 120) and cuando > now() - interval '1 hour') >= 300 then
    raise exception 'Demasiadas lecturas de conversaciones en la ultima hora' using errcode = 'PT429';
  end if;
  insert into public.bot_lecturas_log (usuario, tel, accion) values (left(v_quien, 120), v_tel, p_accion);
end $f$;
