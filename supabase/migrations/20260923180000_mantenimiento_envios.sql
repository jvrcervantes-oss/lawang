-- Modo mantenimiento de ENVÍOS (owner, 23-sep-2026, urgente).
-- Hostinger bloqueó el SMTP de admin@ a mitad de un comunicado (554 5.7.1
-- «Outbound sending is disabled») y el owner pidió poder cortar TODO envío de
-- correo de la intranet de golpe, sin que nadie pueda saltárselo.
--
-- Una sola fila (id = 1). Dónde se aplica:
--  · send_email.php — la puerta por la que sale TODO correo de la intranet
--    (navegador, firma-submit, avisos-manager, factura-vencimiento,
--    admin-usuarios, send-contract-email, investor-deck-codigo). Pregunta a
--    envios_pausados() antes de abrir el SMTP; si no puede preguntar, NO envía.
--  · comunicado_envios_reclamar — en pausa no reclama nada: la cola se queda
--    congelada en 'pendiente' sin gastar intentos, y sale sola al reanudar.
--  · comunicado_encolar / comunicado_prueba — se niegan con un mensaje claro.
-- Pausar y reanudar: mantenimiento_envios(bool, text), solo admin.

create table if not exists public.mantenimiento (
  id           smallint primary key default 1 check (id = 1),
  envios_pausados boolean not null default false,
  motivo       text,
  cambiado_por uuid,
  cambiado_en  timestamptz not null default now()
);
alter table public.mantenimiento enable row level security;
revoke all on public.mantenimiento from anon, authenticated;
grant select on public.mantenimiento to authenticated;
create policy mantenimiento_leer on public.mantenimiento for select to authenticated using (true);

-- Nace EN PAUSA: se creó con el SMTP bloqueado.
insert into public.mantenimiento (id, envios_pausados, motivo, cambiado_en)
values (1, true, 'Hostinger ha bloqueado el envío de correo de admin@ (23-sep). En pausa hasta que lo reactiven.', now())
on conflict (id) do nothing;

-- Lectura para send_email.php. Devuelve SOLO un booleano. Se concede a anon
-- porque la vía 2 de send_email.php (Edges con X-Render-Secret) no trae sesión:
-- es la excepción consciente a «anon sin grants» y no expone ningún dato.
create or replace function public.envios_pausados()
returns boolean language sql stable security definer set search_path = ''
as $$ select coalesce((select envios_pausados from public.mantenimiento where id = 1), false) $$;
revoke all on function public.envios_pausados() from public;
grant execute on function public.envios_pausados() to anon, authenticated;

create or replace function public.mantenimiento_envios(p_pausar boolean, p_motivo text default null)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not public.es_admin() then
    raise exception 'Pausar o reanudar los envíos exige ser admin.' using errcode = '42501';
  end if;
  if p_pausar is null then
    raise exception 'Falta indicar si se pausa o se reanuda.' using errcode = '22023';
  end if;
  insert into public.mantenimiento (id, envios_pausados, motivo, cambiado_por, cambiado_en)
  values (1, p_pausar, nullif(btrim(p_motivo), ''), (select auth.uid()), now())
  on conflict (id) do update set envios_pausados = excluded.envios_pausados, motivo = excluded.motivo,
                                 cambiado_por = excluded.cambiado_por, cambiado_en = excluded.cambiado_en;
  -- al reanudar, lo que quedó en cola sale ya, sin esperar al cron
  if not p_pausar then perform public._comunicados_despierta(); end if;
end $$;
revoke all on function public.mantenimiento_envios(boolean, text) from public, anon;
grant execute on function public.mantenimiento_envios(boolean, text) to authenticated;

-- La cola: en pausa no reclama nada (no gasta intentos).
create or replace function public.comunicado_envios_reclamar(p_tope integer default 25)
 returns table(id uuid, comunicado_id uuid, email text, intentos integer)
 language plpgsql security definer set search_path to ''
as $function$
begin
  if public.envios_pausados() then return; end if;   -- modo mantenimiento (23-sep)
  return query
  with cand as (
    select e.id from public.comunicado_envios e
     where e.estado = 'pendiente'
        or (e.estado = 'enviando' and e.reclamado_en < now() - interval '15 minutes')
     order by e.encolado_en
     limit least(greatest(coalesce(p_tope, 25), 1), 50)
     for update skip locked)
  update public.comunicado_envios e
     set estado = 'enviando', reclamado_en = now(), intentos = e.intentos + 1
    from cand where e.id = cand.id
  returning e.id, e.comunicado_id, e.email, e.intentos;
end $function$;

create or replace function public.comunicado_encolar(p_comunicado uuid, p_user_ids uuid[])
 returns integer language plpgsql security definer set search_path to ''
as $function$
declare n int;
begin
  if not public.es_admin() then
    raise exception 'Enviar un comunicado exige ser admin.' using errcode = '42501';
  end if;
  if public.envios_pausados() then
    raise exception 'Los envíos de correo están en pausa (modo mantenimiento). Reanúdalos en Ajustes para enviar.' using errcode = '55000';
  end if;
  if p_user_ids is null or cardinality(p_user_ids) = 0 then
    raise exception 'Elige al menos un destinatario.' using errcode = '22023';
  end if;
  if cardinality(p_user_ids) > 200 then
    raise exception 'Demasiados destinatarios de una vez (máximo 200).' using errcode = '22023';
  end if;
  perform 1 from public.comunicados where id = p_comunicado for update;
  if not found then
    raise exception 'Ese comunicado no existe.' using errcode = 'P0002';
  end if;

  update public.comunicados set enviado_en = coalesce(enviado_en, now()) where id = p_comunicado;

  with reservados as (
    insert into public.comunicado_envios (comunicado_id, user_id, email, nombre, encolado_por)
    select p_comunicado, u.user_id, u.email, u.nombre, (select auth.uid())
      from public.usuarios u
     where u.user_id = any (p_user_ids) and u.activo and u.email is not null
    on conflict (comunicado_id, user_id) where not es_prueba
    do update set estado = 'pendiente', intentos = 0, error = null, reclamado_en = null,
                  email = excluded.email, nombre = excluded.nombre,
                  encolado_por = excluded.encolado_por, encolado_en = now()
      where public.comunicado_envios.estado = 'error'
    returning 1)
  select count(*) into n from reservados;

  if n > 0 then perform public._comunicados_despierta(); end if;
  return n;
end $function$;

create or replace function public.comunicado_prueba(p_comunicado uuid)
 returns text language plpgsql security definer set search_path to ''
as $function$
declare v_email text; v_nombre text;
begin
  if not public.es_admin() then
    raise exception 'Enviar una prueba exige ser admin.' using errcode = '42501';
  end if;
  if public.envios_pausados() then
    raise exception 'Los envíos de correo están en pausa (modo mantenimiento). Reanúdalos en Ajustes para enviar.' using errcode = '55000';
  end if;
  perform 1 from public.comunicados where id = p_comunicado;
  if not found then
    raise exception 'Guarda el comunicado antes de probarlo.' using errcode = 'P0002';
  end if;
  select u.email, u.nombre into v_email, v_nombre
    from public.usuarios u where u.user_id = (select auth.uid()) and u.activo;
  if v_email is null then
    raise exception 'Tu usuario no tiene email en la intranet.' using errcode = 'P0002';
  end if;
  if exists (select 1 from public.comunicado_envios
              where comunicado_id = p_comunicado and es_prueba and user_id = (select auth.uid())
                and estado in ('pendiente','enviando')) then
    raise exception 'Ya hay una prueba en camino: espera a que llegue.' using errcode = '22023';
  end if;
  insert into public.comunicado_envios (comunicado_id, user_id, email, nombre, es_prueba, encolado_por)
  values (p_comunicado, (select auth.uid()), v_email, v_nombre, true, (select auth.uid()));
  perform public._comunicados_despierta();
  return v_email;
end $function$;
