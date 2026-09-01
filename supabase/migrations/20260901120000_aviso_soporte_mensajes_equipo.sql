-- Aviso por email al equipo cuando un comprador crea un ticket de Soporte o
-- escribe en Mensajes/responde un ticket (1-sep-2026). Cierra la mitad que
-- faltaba de LAW-87: el área de clientes escribe en `tickets_comprador`,
-- `tickets_comprador_mensajes` y `mensajes_comprador` desde el 31-ago, pero
-- hasta hoy nadie del equipo se enteraba sin mirar la base a mano.
--
-- PASADO POR REVISIÓN PREVIA (Seguridad + Datos, mismo día) antes de
-- escribir esto. Hallazgos reales, plegados aquí:
--   1. (Seguridad + Datos) Un comprador puede repetir la acción a voluntad
--      (tickets, mensajes) y el email va a UNA sola bandeja sin respaldo
--      (jcervantes@lawangproperties.com, la misma que ya usa el aviso de
--      almacenamiento) — sin freno, es mail-bombing contra esa bandeja, y
--      Datos recuerda que ese mismo endpoint ya se bloqueó una vez por el
--      WAF de Hostinger (7-ago). `avisos_soporte_equipo` es el freno: como
--      mucho un correo cada 2 minutos POR COMPRADOR, no por evento.
--   2. (Seguridad) Inyección de cabeceras vía el "asunto" del ticket, que
--      escribe el comprador. VERIFICADO, no asumido: `send_email.php` y
--      `SmtpMailer.php` codifican el subject en base64 (`=?UTF-8?B?...?=`)
--      ANTES de montar la cabecera — un `\r\n` dentro del texto se convierte
--      en bytes base64 normales, no puede escapar a una cabecera nueva. No
--      hace falta tocar el endpoint.
--   3. (Datos, ALTA) El trigger vive en la MISMA transacción que el INSERT
--      real del comprador — si el aviso falla (red, payload raro), un
--      trigger sin aislar tumbaría el ticket/mensaje entero por un fallo
--      que no es suyo. Las tres funciones envuelven la llamada en
--      `EXCEPTION WHEN OTHERS THEN NULL` — el aviso puede fallar en
--      silencio, el ticket/mensaje del comprador NUNCA.
--   4. (Datos) `tickets_comprador_mensajes` solo trae `ticket_id`, no
--      `client_id` — el trigger de esa tabla hace el JOIN a
--      `tickets_comprador` para el enlace y el nombre del comprador.
--   5. (Datos) `search_path=''` y nombres cualificados (`public.x`,
--      `net.http_post`) en las tres funciones — mismo estándar que ya
--      exige el propio departamento de Datos para todo DDL nuevo.
--   6. (Seguridad) Mismo contexto de privilegio que `revisar_almacenamiento()`
--      (`security definer`, mismo `net.http_post` sin credencial, misma vía
--      3 ya documentada en `reference_lawang_send_email_tres_vias`) — no se
--      inventa un camino nuevo.
--
-- destructivo-ok: sin `drop table`. Los `drop function/trigger if exists`
-- son de objetos que esta misma migración vuelve a crear (idempotencia).

create table if not exists public.avisos_soporte_equipo (
  client_id  uuid primary key references public.clients(id) on delete cascade,
  enviado_en timestamptz not null default now()
);
comment on table public.avisos_soporte_equipo is
  'Cooldown del aviso por email al equipo (Soporte/Mensajes, LAW-87): un comprador no dispara más de un correo cada 2 minutos, sea cual sea el número de tickets/mensajes que mande en ese rato. Protege una sola bandeja (jcervantes@lawangproperties.com) de un chat o una ráfaga de tickets.';
alter table public.avisos_soporte_equipo enable row level security;
drop policy if exists "agentes leen cooldown de avisos" on public.avisos_soporte_equipo;
create policy "agentes leen cooldown de avisos" on public.avisos_soporte_equipo
  for select to authenticated using (public.es_agente());
-- Sin policy de escritura para nadie: solo la función de abajo, que corre
-- security definer con sus propios privilegios.

-- Manda el aviso si no se mandó ya uno para este comprador en los últimos 2
-- minutos; si lo manda, marca el cooldown. Nunca lanza: un fallo de red o
-- del propio net.http_post se traga aquí, no en cada trigger por separado.
create or replace function public._avisar_equipo_soporte(p_client_id uuid, p_asunto text, p_cuerpo text)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  if exists (
    select 1 from public.avisos_soporte_equipo
     where client_id = p_client_id and enviado_en > now() - interval '2 minutes'
  ) then
    return;   -- ya se avisó hace poco de este mismo comprador; el equipo ya lo sabe
  end if;

  perform net.http_post(
    url := 'https://lawangproperties.com/contracts/api/send_email.php',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := jsonb_build_object(
      'to', 'jcervantes@lawangproperties.com',
      'subject', p_asunto,
      'message', p_cuerpo, 'attach', false));

  insert into public.avisos_soporte_equipo (client_id, enviado_en)
    values (p_client_id, now())
  on conflict (client_id) do update set enviado_en = now();
exception when others then
  null;   -- el aviso puede fallar; el ticket/mensaje del comprador ya se guardó y no se toca
end $$;
revoke all on function public._avisar_equipo_soporte(uuid,text,text) from public, anon, authenticated;

-- ── Trigger 1: nuevo ticket ─────────────────────────────────────────────
create or replace function public._trg_aviso_ticket_nuevo()
returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_nombre text; v_cuerpo text;
begin
  select c.full_name into v_nombre from public.clients c where c.id = new.client_id;
  v_cuerpo :=
    'Nuevo ticket de soporte en el área de clientes.' || chr(10) || chr(10) ||
    'Comprador: ' || coalesce(v_nombre, 'sin nombre') || chr(10) ||
    'Categoría: ' || new.categoria || chr(10) ||
    'Asunto: ' || new.asunto || chr(10) || chr(10) ||
    'Responder desde: https://lawangproperties.com/intranet/compradores/?id=' || new.client_id::text;
  perform public._avisar_equipo_soporte(new.client_id, 'Lawang · nuevo ticket: ' || new.asunto, v_cuerpo);
  return new;
exception when others then
  return new;   -- el ticket ya está insertado; un fallo aquí no lo deshace
end $$;
drop trigger if exists trg_aviso_ticket_nuevo on public.tickets_comprador;
create trigger trg_aviso_ticket_nuevo
  after insert on public.tickets_comprador
  for each row execute function public._trg_aviso_ticket_nuevo();

-- ── Trigger 2: el comprador responde en un ticket ya abierto ────────────
-- Solo cuando de='cliente' -- si responde el equipo, el equipo ya lo sabe.
create or replace function public._trg_aviso_ticket_mensaje()
returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_client_id uuid; v_asunto text; v_nombre text; v_cuerpo text;
begin
  if new.de <> 'cliente' then return new; end if;
  select tc.client_id, tc.asunto into v_client_id, v_asunto
    from public.tickets_comprador tc where tc.id = new.ticket_id;
  if v_client_id is null then return new; end if;
  select c.full_name into v_nombre from public.clients c where c.id = v_client_id;
  v_cuerpo :=
    'El comprador respondió en un ticket de soporte.' || chr(10) || chr(10) ||
    'Comprador: ' || coalesce(v_nombre, 'sin nombre') || chr(10) ||
    'Ticket: ' || v_asunto || chr(10) || chr(10) ||
    'Mensaje: ' || new.texto || chr(10) || chr(10) ||
    'Responder desde: https://lawangproperties.com/intranet/compradores/?id=' || v_client_id::text;
  perform public._avisar_equipo_soporte(v_client_id, 'Lawang · respuesta en ticket: ' || v_asunto, v_cuerpo);
  return new;
exception when others then
  return new;
end $$;
drop trigger if exists trg_aviso_ticket_mensaje on public.tickets_comprador_mensajes;
create trigger trg_aviso_ticket_mensaje
  after insert on public.tickets_comprador_mensajes
  for each row execute function public._trg_aviso_ticket_mensaje();

-- ── Trigger 3: nuevo mensaje del comprador en el chat directo ───────────
create or replace function public._trg_aviso_mensaje_comprador()
returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_nombre text; v_cuerpo text;
begin
  if new.de <> 'cliente' then return new; end if;
  select c.full_name into v_nombre from public.clients c where c.id = new.client_id;
  v_cuerpo :=
    'Nuevo mensaje del comprador en el área de clientes.' || chr(10) || chr(10) ||
    'Comprador: ' || coalesce(v_nombre, 'sin nombre') || chr(10) || chr(10) ||
    'Mensaje: ' || new.texto || chr(10) || chr(10) ||
    'Responder desde: https://lawangproperties.com/intranet/compradores/?id=' || new.client_id::text;
  perform public._avisar_equipo_soporte(new.client_id, 'Lawang · mensaje de ' || coalesce(v_nombre, 'un comprador'), v_cuerpo);
  return new;
exception when others then
  return new;
end $$;
drop trigger if exists trg_aviso_mensaje_comprador on public.mensajes_comprador;
create trigger trg_aviso_mensaje_comprador
  after insert on public.mensajes_comprador
  for each row execute function public._trg_aviso_mensaje_comprador();

-- Comprobación (la del catálogo, no la de que alguien lo corriera):
--   select tgname from pg_trigger where tgname like 'trg_aviso_%';
--   select proname from pg_proc where proname like '_trg_aviso_%' or proname = '_avisar_equipo_soporte';
