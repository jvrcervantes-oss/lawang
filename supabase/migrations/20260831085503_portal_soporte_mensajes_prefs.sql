-- Soporte (tickets) + Mensajes (chat con la gestora) + preferencias del área
-- de clientes externa (31-ago-2026, diseño "Área de Clientes" instalado).
--
-- PASADO POR REVISIÓN PREVIA (Seguridad + Datos, mismo día) antes de escribir
-- esto. Cinco hallazgos reales, los cinco plegados aquí:
--   1. `client_id` NUNCA se asume 1:1 desde el email — una familia con un
--      correo lleva VARIAS filas en `portal_accesos` (portal_comprador.sql).
--      Toda policy y toda función usa `IN`/`EXISTS`, nunca una subconsulta
--      escalar `= (select ...)`.
--   2. El portal NUNCA escribe por INSERT directo + RLS. Es la primera vez
--      que este portal ESCRIBE (hasta hoy solo leía) — cada alta pasa por una
--      función `security definer` que fija `de`/`autor` ella misma, nunca lo
--      que mande el navegador. Impide que un comprador inserte una fila
--      fingiendo `de='equipo'`.
--   3. `leida`/visto lo marca el COMPRADOR sobre lo suyo (abrir la campana),
--      no el equipo — al revés de lo que decía el plan inicial. Aquí no hay
--      columna `leida` por fila: se ha seguido el patrón que YA usa
--      `usuarios.notif_visto_hasta` (notificaciones_intranet.sql) — un único
--      "visto hasta" por persona, más simple y ya probado.
--   4. NUNCA RLS de escritura directa del portal sobre `portal_accesos`: esa
--      tabla decide qué comprador ve qué ficha, y RLS no puede acotar QUÉ
--      COLUMNA toca un UPDATE — dar `UPDATE` para dos prefs habría dejado
--      reescribir `client_id` hacia la ficha de otro comprador. Las
--      preferencias viven en una tabla propia, nueva, sin relación de
--      escritura con `portal_accesos`.
--   5. Índices explícitos en cada FK nueva — ninguna tabla comparable del
--      estudio (`contrato_eventos`, `notificaciones`, `recibi_aplicaciones`)
--      se dejó sin ellos.
-- Nombres en español (`tickets_comprador`, no `client_tickets`): todo lo
-- construido desde que se abandonó el inglés inicial (`contrato_eventos`,
-- `obra_fotos`, `portal_accesos`...) sigue esa norma; `clients`/`clients.id`
-- es el único resto del esquema viejo y no se toca aquí.
--
-- destructivo-ok: los únicos `drop` son `drop policy/trigger if exists` de
-- objetos que esta misma migración vuelve a crear a continuación
-- (idempotencia). No se borra ninguna tabla, columna ni dato.

create table if not exists public.tickets_comprador (
  id         uuid primary key default gen_random_uuid(),
  client_id  uuid not null references public.clients(id) on delete cascade,
  asunto     text not null,
  categoria  text not null default 'Otro' check (categoria in ('Pagos','Documentación','Obra','Otro')),
  estado     text not null default 'abierto' check (estado in ('abierto','resuelto')),
  creado_en  timestamptz not null default now()
);
comment on table public.tickets_comprador is
  'Tickets de soporte abiertos desde el área de clientes (/portal/). El client_id lo valida portal_crear_ticket(), nunca se acepta a pelo desde el navegador.';
create index if not exists tickets_comprador_client_idx on public.tickets_comprador (client_id, creado_en desc);

create table if not exists public.tickets_comprador_mensajes (
  id         uuid primary key default gen_random_uuid(),
  ticket_id  uuid not null references public.tickets_comprador(id) on delete cascade,
  de         text not null check (de in ('cliente','equipo')),
  autor      text,
  texto      text not null,
  creado_en  timestamptz not null default now(),
  constraint tickets_comprador_mensajes_autor_check
    check ((de = 'cliente' and autor is null) or (de = 'equipo' and autor is not null))
);
comment on table public.tickets_comprador_mensajes is
  'Hilo de un ticket_comprador. `de` y `autor` los fija portal_enviar_ticket_mensaje(), nunca el propio INSERT del navegador.';
create index if not exists tickets_comprador_mensajes_ticket_idx on public.tickets_comprador_mensajes (ticket_id, creado_en desc);

create table if not exists public.mensajes_comprador (
  id         uuid primary key default gen_random_uuid(),
  client_id  uuid not null references public.clients(id) on delete cascade,
  de         text not null check (de in ('cliente','equipo')),
  autor      text,
  texto      text not null,
  creado_en  timestamptz not null default now(),
  constraint mensajes_comprador_autor_check
    check ((de = 'cliente' and autor is null) or (de = 'equipo' and autor is not null))
);
comment on table public.mensajes_comprador is
  'Chat de un comprador con el equipo, un solo hilo por client_id. `de`/`autor` los fija portal_enviar_mensaje(), nunca el INSERT del navegador.';
create index if not exists mensajes_comprador_client_idx on public.mensajes_comprador (client_id, creado_en desc);

create table if not exists public.preferencias_comprador (
  client_id          uuid primary key references public.clients(id) on delete cascade,
  pref_email         boolean not null default true,
  pref_sms           boolean not null default false,
  notif_visto_hasta  timestamptz,
  actualizado_en     timestamptz not null default now()
);
comment on table public.preferencias_comprador is
  'Preferencias de aviso y "visto hasta" de la campana del área de clientes. Se escribe solo vía portal_set_prefs()/portal_marcar_notificaciones_leidas(), nunca por UPDATE directo — mismo motivo que impide dar UPDATE sobre portal_accesos.';

alter table public.tickets_comprador enable row level security;
alter table public.tickets_comprador_mensajes enable row level security;
alter table public.mensajes_comprador enable row level security;
alter table public.preferencias_comprador enable row level security;

drop policy if exists "comprador ve sus tickets" on public.tickets_comprador;
create policy "comprador ve sus tickets" on public.tickets_comprador
  for select to authenticated
  using (public.es_portal() and client_id in (
    select pa.client_id from public.portal_accesos pa
     where pa.activo and pa.email = lower(coalesce(auth.email(), ''))
  ));
drop policy if exists "equipo ve y resuelve tickets" on public.tickets_comprador;
create policy "equipo ve y resuelve tickets" on public.tickets_comprador
  for select to authenticated using (public.es_agente());
drop policy if exists "equipo cambia el estado del ticket" on public.tickets_comprador;
create policy "equipo cambia el estado del ticket" on public.tickets_comprador
  for update to authenticated using (public.es_agente()) with check (public.es_agente());

drop policy if exists "comprador ve mensajes de sus tickets" on public.tickets_comprador_mensajes;
create policy "comprador ve mensajes de sus tickets" on public.tickets_comprador_mensajes
  for select to authenticated
  using (public.es_portal() and exists (
    select 1 from public.tickets_comprador tc
     where tc.id = ticket_id
       and tc.client_id in (
         select pa.client_id from public.portal_accesos pa
          where pa.activo and pa.email = lower(coalesce(auth.email(), ''))
       )
  ));
drop policy if exists "equipo ve mensajes de tickets" on public.tickets_comprador_mensajes;
create policy "equipo ve mensajes de tickets" on public.tickets_comprador_mensajes
  for select to authenticated using (public.es_agente());

drop policy if exists "comprador ve su hilo de mensajes" on public.mensajes_comprador;
create policy "comprador ve su hilo de mensajes" on public.mensajes_comprador
  for select to authenticated
  using (public.es_portal() and client_id in (
    select pa.client_id from public.portal_accesos pa
     where pa.activo and pa.email = lower(coalesce(auth.email(), ''))
  ));
drop policy if exists "equipo ve hilos de mensajes" on public.mensajes_comprador;
create policy "equipo ve hilos de mensajes" on public.mensajes_comprador
  for select to authenticated using (public.es_agente());

drop policy if exists "comprador ve sus preferencias" on public.preferencias_comprador;
create policy "comprador ve sus preferencias" on public.preferencias_comprador
  for select to authenticated
  using (public.es_portal() and client_id in (
    select pa.client_id from public.portal_accesos pa
     where pa.activo and pa.email = lower(coalesce(auth.email(), ''))
  ));
drop policy if exists "equipo ve preferencias" on public.preferencias_comprador;
create policy "equipo ve preferencias" on public.preferencias_comprador
  for select to authenticated using (public.es_agente());

create or replace function public.portal_crear_ticket(p_client_id uuid, p_asunto text, p_categoria text, p_mensaje text)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if not public.es_portal() then raise exception 'solo portal' using errcode = '42501'; end if;
  if not exists (select 1 from public.portal_accesos pa
                  where pa.activo and pa.email = lower(coalesce(auth.email(), '')) and pa.client_id = p_client_id) then
    raise exception 'esa ficha no es tuya' using errcode = '42501';
  end if;
  if btrim(coalesce(p_asunto,'')) = '' or btrim(coalesce(p_mensaje,'')) = '' then
    raise exception 'asunto y mensaje son obligatorios' using errcode = '22023';
  end if;
  insert into public.tickets_comprador (client_id, asunto, categoria)
    values (p_client_id, btrim(p_asunto), coalesce(nullif(btrim(p_categoria),''), 'Otro'))
    returning id into v_id;
  insert into public.tickets_comprador_mensajes (ticket_id, de, autor, texto)
    values (v_id, 'cliente', null, btrim(p_mensaje));
  return v_id;
end $$;
revoke execute on function public.portal_crear_ticket(uuid,text,text,text) from public, anon;
grant execute on function public.portal_crear_ticket(uuid,text,text,text) to authenticated;

create or replace function public.portal_enviar_ticket_mensaje(p_ticket_id uuid, p_texto text)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_de text; v_autor text;
begin
  if btrim(coalesce(p_texto,'')) = '' then raise exception 'mensaje vacío' using errcode = '22023'; end if;
  if public.es_agente() then
    v_de := 'equipo'; v_autor := auth.email();
  elsif public.es_portal() then
    if not exists (select 1 from public.tickets_comprador tc
                    join public.portal_accesos pa on pa.client_id = tc.client_id
                   where tc.id = p_ticket_id and pa.activo and pa.email = lower(coalesce(auth.email(), ''))) then
      raise exception 'ese ticket no es tuyo' using errcode = '42501';
    end if;
    v_de := 'cliente'; v_autor := null;
  else
    raise exception 'sin permiso' using errcode = '42501';
  end if;
  insert into public.tickets_comprador_mensajes (ticket_id, de, autor, texto)
    values (p_ticket_id, v_de, v_autor, btrim(p_texto))
    returning id into v_id;
  return v_id;
end $$;
revoke execute on function public.portal_enviar_ticket_mensaje(uuid,text) from public, anon;
grant execute on function public.portal_enviar_ticket_mensaje(uuid,text) to authenticated;

create or replace function public.portal_enviar_mensaje(p_client_id uuid, p_texto text)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_de text; v_autor text;
begin
  if btrim(coalesce(p_texto,'')) = '' then raise exception 'mensaje vacío' using errcode = '22023'; end if;
  if public.es_agente() then
    v_de := 'equipo'; v_autor := auth.email();
  elsif public.es_portal() then
    if not exists (select 1 from public.portal_accesos pa
                    where pa.activo and pa.email = lower(coalesce(auth.email(), '')) and pa.client_id = p_client_id) then
      raise exception 'esa ficha no es tuya' using errcode = '42501';
    end if;
    v_de := 'cliente'; v_autor := null;
  else
    raise exception 'sin permiso' using errcode = '42501';
  end if;
  insert into public.mensajes_comprador (client_id, de, autor, texto)
    values (p_client_id, v_de, v_autor, btrim(p_texto))
    returning id into v_id;
  return v_id;
end $$;
revoke execute on function public.portal_enviar_mensaje(uuid,text) from public, anon;
grant execute on function public.portal_enviar_mensaje(uuid,text) to authenticated;

create or replace function public.portal_marcar_notificaciones_leidas()
returns timestamptz
language plpgsql security definer set search_path = '' as $$
declare v_ahora timestamptz := now();
begin
  if not public.es_portal() then raise exception 'solo portal' using errcode = '42501'; end if;
  insert into public.preferencias_comprador (client_id, notif_visto_hasta)
    select pa.client_id, v_ahora from public.portal_accesos pa
     where pa.activo and pa.email = lower(coalesce(auth.email(), ''))
  on conflict (client_id) do update set notif_visto_hasta = v_ahora, actualizado_en = v_ahora;
  return v_ahora;
end $$;
revoke execute on function public.portal_marcar_notificaciones_leidas() from public, anon;
grant execute on function public.portal_marcar_notificaciones_leidas() to authenticated;

create or replace function public.portal_set_prefs(p_pref_email boolean, p_pref_sms boolean)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.es_portal() then raise exception 'solo portal' using errcode = '42501'; end if;
  insert into public.preferencias_comprador (client_id, pref_email, pref_sms)
    select pa.client_id, coalesce(p_pref_email, true), coalesce(p_pref_sms, false)
      from public.portal_accesos pa
     where pa.activo and pa.email = lower(coalesce(auth.email(), ''))
  on conflict (client_id) do update
    set pref_email = coalesce(p_pref_email, public.preferencias_comprador.pref_email),
        pref_sms   = coalesce(p_pref_sms, public.preferencias_comprador.pref_sms),
        actualizado_en = now();
end $$;
revoke execute on function public.portal_set_prefs(boolean,boolean) from public, anon;
grant execute on function public.portal_set_prefs(boolean,boolean) to authenticated;;
