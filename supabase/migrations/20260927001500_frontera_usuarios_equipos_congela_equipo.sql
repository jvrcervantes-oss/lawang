-- destructivo-ok: el unico DROP es `drop trigger if exists` del trigger nuevo trg_contrato_closer_congela (idempotencia); no borra ni cambia ninguna fila al aplicarse.
-- Frontera frontend/backend — pieza 7: USUARIOS y EQUIPOS DE VENTA por el servidor, y el equipo de una venta
-- CONGELADO (26/27-sep-2026, LAW-336). SOLO AÑADE funciones, columnas y una tabla de registro; cambia
-- `_equipo_de_venta` y `comisiones_evaluar_contrato` para que lean lo congelado cuando lo hay (si no, idéntico).
-- Plan y revisión previa #122 (Seguridad): encargos/20260926_lawang_frontera_f7_usuarios_equipos.md
--
-- DECISIÓN DEL OWNER (26-sep): «congelar en la venta». Hasta hoy el equipo y el manager de una venta se
-- buscaban cada vez que se calculaba la comisión, con los datos del equipo de ESE momento: cambiar el
-- manager, desactivar un equipo o mover las fechas de un miembro reasignaba en silencio comisiones
-- pendientes de ventas ya hechas. Ahora cada venta guarda en `contrato_closer` el equipo y el manager que
-- tenía, y el motor usa eso.
-- Cuándo se congela, sin ningún volcado masivo:
--   · una venta NUEVA, al asignarle el closer (trigger en contrato_closer);
--   · una venta que ya existía, justo ANTES de cualquier cambio en su equipo (manager, activo, miembros),
--     con el equipo que tiene hoy — así nada de lo que ya se cobraría cambia.
-- Si se cambia el closer de una venta, se vuelve a congelar con el equipo del closer nuevo.
-- El email del manager se guarda TAL CUAL (el motor compara beneficiario_email con mayúsculas).

-- ── congelado ─────────────────────────────────────────────────────────────────
alter table public.contrato_closer
  add column if not exists equipo_id uuid,
  add column if not exists manager_email text,
  add column if not exists equipo_congelado_en timestamptz;

-- Mismo criterio que usaba el motor; con la venta congelada, lo congelado.
create or replace function public._equipo_de_venta(p_raiz uuid)
returns table(equipo_id uuid, manager_email text, closer_email text, fecha date)
language sql stable security definer set search_path = '' as $$
  select x.equipo_id, x.manager_email, x.closer_email, x.fecha from (
    select k.equipo_id, lower(k.manager_email) as manager_email, lower(k.closer_email) as closer_email,
           coalesce(k.fecha_venta, current_date) as fecha, 0 as prio
      from public.contrato_closer k
     where k.contrato_id = p_raiz and k.equipo_congelado_en is not null and k.equipo_id is not null
    union all
    (select em.equipo_id, lower(ev.manager_email), lower(k.closer_email), coalesce(k.fecha_venta, current_date), 1
       from public.contrato_closer k
       join public.equipo_miembros em on lower(em.closer_email) = lower(k.closer_email)
       join public.equipos_venta ev on ev.id = em.equipo_id and ev.activo
      where k.contrato_id = p_raiz and k.equipo_congelado_en is null
        and em.desde <= coalesce(k.fecha_venta, current_date)
        and (em.hasta is null or em.hasta >= coalesce(k.fecha_venta, current_date))
      order by em.created_at desc
      limit 1)
  ) x order by x.prio limit 1
$$;

-- Congela una venta con el equipo que le toca AHORA (si ya estaba congelada, no hace nada).
create or replace function public._venta_congela_equipo(p_raiz uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_eq uuid; v_man text;
begin
  if not exists (select 1 from public.contrato_closer k where k.contrato_id = p_raiz and k.equipo_congelado_en is null) then
    return;
  end if;
  select em.equipo_id, ev.manager_email into v_eq, v_man   -- manager tal cual, sin lower (ver cabecera)
    from public.contrato_closer k
    join public.equipo_miembros em on lower(em.closer_email) = lower(k.closer_email)
    join public.equipos_venta ev on ev.id = em.equipo_id and ev.activo
   where k.contrato_id = p_raiz
     and em.desde <= coalesce(k.fecha_venta, current_date)
     and (em.hasta is null or em.hasta >= coalesce(k.fecha_venta, current_date))
   order by em.created_at desc
   limit 1;
  update public.contrato_closer k
     set equipo_id = v_eq, manager_email = v_man, equipo_congelado_en = now()
   where k.contrato_id = p_raiz and k.equipo_congelado_en is null;
end $$;
revoke all on function public._venta_congela_equipo(uuid) from public, anon, authenticated;

-- Antes de tocar un equipo o un miembro: congela las ventas que hoy dependen de él. Devuelve cuántas.
create or replace function public._equipo_congela_ventas(p_equipo uuid, p_email text) returns integer
language plpgsql security definer set search_path = '' as $$
declare r record; n int := 0;
begin
  for r in
    select k.contrato_id from public.contrato_closer k
     where k.equipo_congelado_en is null
       and ((p_email is not null and lower(k.closer_email) = lower(p_email))
            or (p_equipo is not null and exists (select 1 from public.equipo_miembros em
                                                   where em.equipo_id = p_equipo
                                                     and lower(em.closer_email) = lower(k.closer_email))))
  loop
    perform public._venta_congela_equipo(r.contrato_id);
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public._equipo_congela_ventas(uuid, text) from public, anon, authenticated;

-- venta nueva o closer cambiado: congela con el equipo del closer de ESA venta
create or replace function public._trg_contrato_closer_congela() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'UPDATE' then
    update public.contrato_closer k set equipo_id = null, manager_email = null, equipo_congelado_en = null
     where k.contrato_id = new.contrato_id;
  end if;
  perform public._venta_congela_equipo(new.contrato_id);
  return null;
end $$;
revoke all on function public._trg_contrato_closer_congela() from public, anon, authenticated;
drop trigger if exists trg_contrato_closer_congela on public.contrato_closer;
create trigger trg_contrato_closer_congela after insert or update of closer_email on public.contrato_closer
  for each row execute function public._trg_contrato_closer_congela();

-- El motor lee lo congelado. Cambio QUIRÚRGICO sobre la función viva (no se reescribe a mano: son 300
-- líneas de dinero): con la venta congelada, equipo y manager salen de contrato_closer; sin congelar,
-- exactamente el mismo código de antes.
do $$
declare d text := pg_get_functiondef('public.comisiones_evaluar_contrato'::regproc); d0 text;
begin
  d0 := d;
  d := replace(d, 'v_creados              integer := 0;',
               'v_creados              integer := 0;' || chr(10) ||
               '  v_eq_cong              uuid;' || chr(10) ||
               '  v_man_cong             text;' || chr(10) ||
               '  v_congelado            boolean := false;');
  if d = d0 then raise exception 'evaluar: no encuentro la declaración de v_creados'; end if;
  d0 := d;
  d := regexp_replace(d,
    'select em\.equipo_id into v_equipo_id(.*?)order by em\.created_at desc\s+limit 1;',
    'select k.equipo_id, k.manager_email, (k.equipo_congelado_en is not null)' || chr(10) ||
    '    into v_eq_cong, v_man_cong, v_congelado' || chr(10) ||
    '    from public.contrato_closer k where k.contrato_id = v_raiz_id;' || chr(10) ||
    '  if coalesce(v_congelado, false) then' || chr(10) ||
    '    v_equipo_id := v_eq_cong;   -- equipo congelado en la venta (owner, 26-sep-2026)' || chr(10) ||
    '  else' || chr(10) ||
    '  select em.equipo_id into v_equipo_id\1order by em.created_at desc' || chr(10) ||
    '   limit 1;' || chr(10) ||
    '  end if;');
  if d = d0 then raise exception 'evaluar: no encuentro la búsqueda del equipo'; end if;
  d0 := d;
  d := regexp_replace(d,
    'select ev\.manager_email into v_manager_email\s+from public\.equipos_venta ev\s+where ev\.id = v_equipo_id;',
    'if coalesce(v_congelado, false) then' || chr(10) ||
    '      v_manager_email := v_man_cong;   -- manager congelado en la venta' || chr(10) ||
    '    else' || chr(10) ||
    '      select ev.manager_email into v_manager_email from public.equipos_venta ev where ev.id = v_equipo_id;' || chr(10) ||
    '    end if;');
  if d = d0 then raise exception 'evaluar: no encuentro la búsqueda del manager'; end if;
  execute d;
end $$;

-- ── registro ──────────────────────────────────────────────────────────────────
create table if not exists public.equipos_log (
  id uuid primary key default gen_random_uuid(),
  tabla text not null,
  fila_id uuid,
  antes jsonb, despues jsonb,
  ventas_congeladas int not null default 0,
  por text default auth.email(),
  en timestamptz not null default now()
);
alter table public.equipos_log enable row level security;
revoke all on public.equipos_log from anon, authenticated;
grant select on public.equipos_log to authenticated;
create policy "log de equipos: lo ve un admin" on public.equipos_log for select to authenticated using (public.es_admin());

create or replace function public._usuario_activo(p_email text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.usuarios u where lower(u.email) = lower(p_email) and u.activo)
$$;
revoke all on function public._usuario_activo(text) from public, anon, authenticated;

-- ── equipos de venta ──────────────────────────────────────────────────────────
create or replace function public.equipo_venta_guarda(p_id uuid, p_nombre text, p_manager_email text)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_old public.equipos_venta%rowtype; v_id uuid; v_n int := 0;
  v_man text := nullif(lower(btrim(coalesce(p_manager_email, ''))), '');
  v_nom text := nullif(btrim(coalesce(p_nombre, '')), '');
begin
  if not public.es_admin() then raise exception 'Los equipos de venta los gestiona administración' using errcode = '42501'; end if;
  if v_nom is null then raise exception 'Falta el nombre del equipo' using errcode = '22023'; end if;
  if v_man is null or not public._usuario_activo(v_man) then
    raise exception 'El manager tiene que ser un usuario activo de la intranet' using errcode = '22023';
  end if;
  if v_man = lower(coalesce((select auth.email()), '')) and not public.es_super_admin() then
    raise exception 'Nadie se pone a sí mismo de manager de un equipo' using errcode = '42501';
  end if;
  if p_id is null then
    insert into public.equipos_venta (nombre, manager_email) values (v_nom, v_man) returning id into v_id;
    insert into public.equipos_log (tabla, fila_id, antes, despues)
    select 'equipos_venta', v_id, null, to_jsonb(e) from public.equipos_venta e where e.id = v_id;
    return v_id;
  end if;
  select * into v_old from public.equipos_venta e where e.id = p_id for update;
  if not found then raise exception 'Ese equipo no existe' using errcode = 'P0002'; end if;
  if lower(v_old.manager_email) is distinct from v_man then
    v_n := public._equipo_congela_ventas(p_id, null);   -- las ventas de hoy se quedan con su manager
  end if;
  update public.equipos_venta set nombre = v_nom, manager_email = v_man where id = p_id;
  insert into public.equipos_log (tabla, fila_id, antes, despues, ventas_congeladas)
  select 'equipos_venta', p_id, to_jsonb(v_old), to_jsonb(e), v_n from public.equipos_venta e where e.id = p_id;
  return p_id;
end $$;
revoke all on function public.equipo_venta_guarda(uuid, text, text) from public, anon;
grant execute on function public.equipo_venta_guarda(uuid, text, text) to authenticated;

create or replace function public.equipo_venta_activa(p_id uuid, p_activo boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare v_old public.equipos_venta%rowtype; v_n int;
begin
  if not public.es_admin() then raise exception 'Los equipos de venta los gestiona administración' using errcode = '42501'; end if;
  select * into v_old from public.equipos_venta e where e.id = p_id for update;
  if not found then raise exception 'Ese equipo no existe' using errcode = 'P0002'; end if;
  v_n := public._equipo_congela_ventas(p_id, null);   -- desactivar no deja sin equipo a sus ventas
  update public.equipos_venta set activo = coalesce(p_activo, false) where id = p_id;
  insert into public.equipos_log (tabla, fila_id, antes, despues, ventas_congeladas)
  values ('equipos_venta', p_id, jsonb_build_object('activo', v_old.activo), jsonb_build_object('activo', coalesce(p_activo, false)), v_n);
end $$;
revoke all on function public.equipo_venta_activa(uuid, boolean) from public, anon;
grant execute on function public.equipo_venta_activa(uuid, boolean) to authenticated;

-- alta (p_id null) o edición de un miembro
create or replace function public.equipo_miembro_guarda(p_id uuid, p_equipo uuid, p_email text, p_desde date, p_hasta date)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_old public.equipo_miembros%rowtype; v_id uuid; v_n int := 0;
  v_email text := nullif(lower(btrim(coalesce(p_email, ''))), '');
begin
  if not public.es_admin() then raise exception 'Los equipos de venta los gestiona administración' using errcode = '42501'; end if;
  if v_email is null or not public._usuario_activo(v_email) then
    raise exception 'El miembro tiene que ser un usuario activo de la intranet' using errcode = '22023';
  end if;
  if v_email = lower(coalesce((select auth.email()), '')) and not public.es_super_admin() then
    raise exception 'Nadie se añade a sí mismo a un equipo' using errcode = '42501';
  end if;
  if p_desde is null then raise exception 'Falta la fecha «Desde»' using errcode = '22023'; end if;
  if p_hasta is not null and p_hasta < p_desde then raise exception '«Hasta» no puede ser anterior a «Desde».' using errcode = '22023'; end if;
  if not exists (select 1 from public.equipos_venta e where e.id = p_equipo) then
    raise exception 'Ese equipo no existe' using errcode = 'P0002';
  end if;
  -- una persona no está en dos equipos distintos a la vez (el motor elegiría uno al azar por fecha de alta)
  if exists (select 1 from public.equipo_miembros em
              where lower(em.closer_email) = v_email and em.equipo_id <> p_equipo
                and (p_id is null or em.id <> p_id)
                and em.desde <= coalesce(p_hasta, 'infinity'::date)
                and p_desde <= coalesce(em.hasta, 'infinity'::date)) then
    raise exception 'Esa persona ya está en otro equipo en esas fechas: dale de baja allí primero' using errcode = '23P01';
  end if;
  if p_id is null then
    v_n := public._equipo_congela_ventas(p_equipo, v_email);
    insert into public.equipo_miembros (equipo_id, closer_email, desde, hasta, added_by)
    values (p_equipo, v_email, p_desde, p_hasta, (select auth.email())) returning id into v_id;
    insert into public.equipos_log (tabla, fila_id, antes, despues, ventas_congeladas)
    select 'equipo_miembros', v_id, null, to_jsonb(m), v_n from public.equipo_miembros m where m.id = v_id;
    return v_id;
  end if;
  select * into v_old from public.equipo_miembros m where m.id = p_id for update;
  if not found then raise exception 'Ese miembro no existe' using errcode = 'P0002'; end if;
  v_n := public._equipo_congela_ventas(v_old.equipo_id, v_old.closer_email)
       + public._equipo_congela_ventas(p_equipo, v_email);
  update public.equipo_miembros
     set equipo_id = p_equipo, closer_email = v_email, desde = p_desde, hasta = p_hasta
   where id = p_id;
  insert into public.equipos_log (tabla, fila_id, antes, despues, ventas_congeladas)
  select 'equipo_miembros', p_id, to_jsonb(v_old), to_jsonb(m), v_n from public.equipo_miembros m where m.id = p_id;
  return p_id;
end $$;
revoke all on function public.equipo_miembro_guarda(uuid, uuid, text, date, date) from public, anon;
grant execute on function public.equipo_miembro_guarda(uuid, uuid, text, date, date) to authenticated;

create or replace function public.equipo_miembro_baja(p_id uuid, p_hasta date) returns void
language plpgsql security definer set search_path = '' as $$
declare v_old public.equipo_miembros%rowtype; v_n int;
begin
  if not public.es_admin() then raise exception 'Los equipos de venta los gestiona administración' using errcode = '42501'; end if;
  select * into v_old from public.equipo_miembros m where m.id = p_id for update;
  if not found then raise exception 'Ese miembro no existe' using errcode = 'P0002'; end if;
  if p_hasta is null or p_hasta < v_old.desde then raise exception 'La fecha de baja no puede ser anterior a su alta' using errcode = '22023'; end if;
  v_n := public._equipo_congela_ventas(v_old.equipo_id, v_old.closer_email);
  update public.equipo_miembros set hasta = p_hasta where id = p_id;
  insert into public.equipos_log (tabla, fila_id, antes, despues, ventas_congeladas)
  values ('equipo_miembros', p_id, jsonb_build_object('hasta', v_old.hasta), jsonb_build_object('hasta', p_hasta), v_n);
end $$;
revoke all on function public.equipo_miembro_baja(uuid, date) from public, anon;
grant execute on function public.equipo_miembro_baja(uuid, date) to authenticated;

-- ── permisos de una persona ───────────────────────────────────────────────────
-- Lista blanca: nombre, herramientas, tipos_contrato, proyectos, activo, rol — cada una solo si viene la clave.
-- Nunca: email, user_id, proyectos_supervisados (tiene su función), notif_visto_hasta.
create or replace function public.usuario_guarda_permisos(p_user_id uuid, p_cambios jsonb) returns void
language plpgsql security definer set search_path = '' as $$
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
  -- sobre la propia ficha solo se cambia el nombre (salvo super admin): nadie se amplía proyectos o contratos
  if v_yo and not public.es_super_admin()
     and (p_cambios - 'nombre') <> '{}'::jsonb then
    raise exception 'Sobre tu propia ficha solo puedes cambiar el nombre' using errcode = '42501';
  end if;
  if v_yo and (p_cambios ? 'activo' or p_cambios ? 'rol') then
    raise exception 'Nadie se desactiva ni se cambia el rol a sí mismo' using errcode = '42501';
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
  -- el trigger usuarios_bloquea_cambio_rol_herramientas sigue exigiendo super admin para rol/herramientas
end $$;
revoke all on function public.usuario_guarda_permisos(uuid, jsonb) from public, anon;
grant execute on function public.usuario_guarda_permisos(uuid, jsonb) to authenticated;
