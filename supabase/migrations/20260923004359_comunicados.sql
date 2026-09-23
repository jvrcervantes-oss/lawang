-- ============================================================================
-- COMUNICADOS AL EQUIPO — 23-sep-2026
-- ----------------------------------------------------------------------------
-- Encargo del owner: «prepara en v4 algo como "Comunicación" para poder
-- escribir yo ahí las plantillas y que lo mandes a los agentes de la
-- intranet». Pantalla: /intranet/v4/comunicacion/ (Panel de control, admin).
--
-- Revisión previa #47 (Seguridad + Datos), plegada entera:
--  · NO hay segundo sistema de envío: el navegador solo ENCOLA
--    (comunicado_encolar) y una Edge (comunicados-envio) entrega, igual que
--    avisos-manager vacía `notificaciones`. Cerrar el navegador a mitad no deja
--    un envío a medias sin saberlo, y un fallo de SMTP reintenta solo.
--  · Doble clic / dos admins a la vez: la reserva ES el INSERT … ON CONFLICT
--    del encolado; solo se envía lo que devuelve. La Edge reclama con
--    FOR UPDATE SKIP LOCKED, así que dos pasadas solapadas (cron + despertador)
--    no cogen la misma fila.
--  · Congelado AL ENCOLAR (enviado_en lo pone comunicado_encolar, no el primer
--    ok): desde ese momento asunto/encabezado/cuerpo/botón no cambian y el
--    registro dice lo que salió. Para cambiarlo se duplica.
--  · La lista blanca del botón vive también AQUÍ (CHECK), no solo en PHP: la
--    tabla la escribe el navegador y el correo sale con la marca de Lawang.
--  · El destinatario lo pone la base (usuarios activos por user_id), nunca un
--    email que mande el navegador. La prueba va al email de quien la pide.
--  · user_id ON DELETE SET NULL + email/nombre copiados: el registro sobrevive
--    a la baja de un usuario («valor + id», patrones_tecnicos).
--  · EXECUTE revocado a PUBLIC/anon en todas las funciones (Postgres lo concede
--    a PUBLIC por defecto al crear).
-- ============================================================================

create table public.comunicados (
  id              uuid primary key default gen_random_uuid(),
  asunto          text not null check (char_length(btrim(asunto)) between 1 and 200),
  encabezado      text check (encabezado is null or char_length(encabezado) <= 120),
  cuerpo          text not null check (char_length(btrim(cuerpo)) between 1 and 5000),
  cta_url         text,
  cta_texto       text check (cta_texto is null or char_length(btrim(cta_texto)) between 1 and 60),
  creado_por      uuid default auth.uid() references public.usuarios(user_id) on delete set null,
  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz not null default now(),
  enviado_en      timestamptz,
  constraint comunicados_cta_pareja check ((cta_url is null) = (cta_texto is null)),
  -- misma lista que cta_permitida() de contracts/api/send_email.php
  constraint comunicados_cta_lista_blanca check (
    cta_url is null
    or cta_url ~* '^https://([a-z0-9-]+\.)*lawangproperties\.com(/[^[:space:]"<>]*)?$'
    or cta_url ~* '^mailto:[^[:space:]"<>@]+@[^[:space:]"<>@]+$'
    or cta_url ~  '^https://wa\.me/[0-9]{6,20}$'
  )
);
comment on table public.comunicados is
  'Comunicados del owner al equipo de la intranet (/intranet/v4/comunicacion/). Se congelan al encolar el primer envío (enviado_en).';

create table public.comunicado_envios (
  id             uuid primary key default gen_random_uuid(),
  comunicado_id  uuid not null references public.comunicados(id) on delete cascade,
  user_id        uuid references public.usuarios(user_id) on delete set null,
  email          text not null,
  nombre         text,
  es_prueba      boolean not null default false,
  estado         text not null default 'pendiente'
                 check (estado in ('pendiente','enviando','ok','error')),
  intentos       int not null default 0,
  error          text check (error is null or char_length(error) <= 300),
  encolado_por   uuid references public.usuarios(user_id) on delete set null,
  encolado_en    timestamptz not null default now(),
  reclamado_en   timestamptz,
  enviado_en     timestamptz
);
-- una persona recibe un comunicado UNA vez (las pruebas no cuentan)
create unique index comunicado_envios_uno_por_persona
  on public.comunicado_envios (comunicado_id, user_id) where not es_prueba;
create index comunicado_envios_cola
  on public.comunicado_envios (encolado_en) where estado in ('pendiente','enviando');
create index comunicado_envios_por_comunicado on public.comunicado_envios (comunicado_id);

-- ── congelado + actualizado_en ──────────────────────────────────────────────
create or replace function public._comunicados_congela()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    if old.enviado_en is not null then
      raise exception 'Este comunicado ya se envió: queda en el registro y no se puede borrar.'
        using errcode = '42501';
    end if;
    return old;
  end if;
  if old.enviado_en is not null and (
       new.asunto     is distinct from old.asunto
    or new.encabezado is distinct from old.encabezado
    or new.cuerpo     is distinct from old.cuerpo
    or new.cta_url    is distinct from old.cta_url
    or new.cta_texto  is distinct from old.cta_texto) then
    raise exception 'Este comunicado ya se envió y no se puede cambiar: duplícalo para escribir otra versión.'
      using errcode = '42501';
  end if;
  new.actualizado_en := now();
  return new;
end $$;

create trigger trg_comunicados_congela
  before update or delete on public.comunicados
  for each row execute function public._comunicados_congela();

-- ── RLS + grants ────────────────────────────────────────────────────────────
alter table public.comunicados       enable row level security;
alter table public.comunicado_envios enable row level security;

create policy comunicados_admin_select on public.comunicados
  for select to authenticated using (public.es_admin());
create policy comunicados_admin_insert on public.comunicados
  for insert to authenticated with check (public.es_admin());
create policy comunicados_admin_update on public.comunicados
  for update to authenticated using (public.es_admin()) with check (public.es_admin());
create policy comunicados_admin_delete on public.comunicados
  for delete to authenticated using (public.es_admin());

-- el registro de envíos solo se LEE desde el navegador; lo escriben las RPC
create policy comunicado_envios_admin_select on public.comunicado_envios
  for select to authenticated using (public.es_admin());

revoke all on public.comunicados, public.comunicado_envios from public, anon, authenticated;
-- columnas: el navegador escribe el contenido, nunca enviado_en ni la autoría
grant select, delete on public.comunicados to authenticated;
grant insert (asunto, encabezado, cuerpo, cta_url, cta_texto) on public.comunicados to authenticated;
grant update (asunto, encabezado, cuerpo, cta_url, cta_texto) on public.comunicados to authenticated;
grant select on public.comunicado_envios to authenticated;
grant all on public.comunicados, public.comunicado_envios to service_role;

-- ── despertador: que la Edge entregue ya, sin esperar al cron ───────────────
-- pg_net es asíncrono (encola la petición y vuelve): no ata la transacción del
-- usuario a la red. Si falla, el cron de 10 min lo recoge igual.
create or replace function public._comunicados_despierta()
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform net.http_post(
    url     := 'https://vtulllundrfennhjddhc.supabase.co/functions/v1/comunicados-envio',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'X-Cron-Secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_avisos_manager')),
    body    := '{}'::jsonb,
    timeout_milliseconds := 60000);
exception when others then
  raise warning 'comunicados: no se pudo despertar la Edge (%): la recoge el cron', sqlerrm;
end $$;
revoke execute on function public._comunicados_despierta() from public, anon, authenticated;

-- ── encolar: la reserva ES este INSERT ──────────────────────────────────────
create or replace function public.comunicado_encolar(p_comunicado uuid, p_user_ids uuid[])
returns int language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  if not public.es_admin() then
    raise exception 'Enviar un comunicado exige ser admin.' using errcode = '42501';
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

  -- congela desde ya (Datos, revisión #47): lo que se encola es lo que sale
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
end $$;

-- ── prueba: solo al email de quien la pide ──────────────────────────────────
create or replace function public.comunicado_prueba(p_comunicado uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare v_email text; v_nombre text;
begin
  if not public.es_admin() then
    raise exception 'Enviar una prueba exige ser admin.' using errcode = '42501';
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
end $$;

-- ── la Edge reclama su tanda (solo service_role) ────────────────────────────
-- 'enviando' de más de 15 min = la pasada anterior murió a mitad: se recoge.
create or replace function public.comunicado_envios_reclamar(p_tope int default 25)
returns table (id uuid, comunicado_id uuid, email text, intentos int)
language plpgsql security definer set search_path = '' as $$
begin
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
end $$;

revoke execute on function public.comunicado_encolar(uuid, uuid[])     from public, anon;
revoke execute on function public.comunicado_prueba(uuid)              from public, anon;
revoke execute on function public.comunicado_envios_reclamar(int)      from public, anon, authenticated;
revoke execute on function public._comunicados_congela()               from public, anon, authenticated;
grant  execute on function public.comunicado_encolar(uuid, uuid[])     to authenticated;
grant  execute on function public.comunicado_prueba(uuid)              to authenticated;
grant  execute on function public.comunicado_envios_reclamar(int)      to service_role;

-- ── red de seguridad: el cron vacía la cola aunque el despertador falle ─────
select cron.schedule(
  'comunicados-envio',
  '*/10 * * * *',
  $cron$
  select net.http_post(
    url     := 'https://vtulllundrfennhjddhc.supabase.co/functions/v1/comunicados-envio',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'X-Cron-Secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_avisos_manager')),
    body    := '{}'::jsonb,
    timeout_milliseconds := 60000);
  $cron$
);
