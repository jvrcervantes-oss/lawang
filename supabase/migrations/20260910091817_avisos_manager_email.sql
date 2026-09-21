-- destructivo-ok: DROP TRIGGER/CREATE OR REPLACE FUNCTION son sustituciones
-- (mismo nombre, misma forma, se amplia una que ya existia), no retiradas de
-- capacidad. Cero DELETE de filas, cero RLS desactivada, cero TRUNCATE.

alter table public.notificaciones
  add column if not exists email_pendiente boolean not null default false,
  add column if not exists email_enviado_en timestamptz;

comment on column public.notificaciones.email_pendiente is
  'true = esta fila tiene que salir TAMBIEN por correo real, no solo campana. Lo pone el trigger que la crea; lo apaga la Edge avisos-manager al enviarla. Las filas normales (aviso a admins, a un agente) quedan en false.';

create index if not exists notificaciones_email_pendiente_idx
  on public.notificaciones (creado_en) where email_pendiente;

create or replace function public._avisar_managers(
  p_proyecto_id uuid, p_tipo text, p_titulo text, p_detalle text,
  p_enlace text, p_contrato_id uuid default null
)
returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  if p_proyecto_id is null then return; end if;
  insert into public.notificaciones (tipo, titulo, detalle, destinatario, contrato_id, enlace, email_pendiente)
  select p_tipo, p_titulo, p_detalle, u.email, p_contrato_id, p_enlace, true
    from public.usuarios u
   where u.activo and u.rol in ('sales_manager','project_manager')
     and p_proyecto_id = any(u.proyectos);
end;
$$;
revoke execute on function public._avisar_managers(uuid, text, text, text, text, uuid) from public, anon, authenticated;

create or replace function public._trg_contrato_bloqueado_aviso_manager()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  perform public._avisar_managers(
    new.proyecto_id, 'contrato_bloqueado',
    'Contrato ' || coalesce(new.numero, '') || ' firmado',
    coalesce(new.comprador_nombre, 'Comprador') || ' · ' || coalesce(new.proyecto_nombre, 'proyecto') || ' · pasa a bloqueado',
    '/intranet/operaciones/?contrato=' || new.id::text, new.id);
  return new;
exception when others then
  return new;
end;
$$;

drop trigger if exists trg_contrato_bloqueado_aviso_manager on public.contratos;
create trigger trg_contrato_bloqueado_aviso_manager
  after update on public.contratos
  for each row
  when (old.bloqueado is distinct from new.bloqueado and new.bloqueado)
  execute function public._trg_contrato_bloqueado_aviso_manager();

create or replace function public._trg_solicitud_pago_aviso()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare v_email text; v_nombre text; v_proyecto_id uuid; v_proyecto_nombre text;
begin
  if tg_op = 'INSERT' then
    select u.nombre into v_nombre from public.usuarios u where u.user_id = new.creado_por;
    insert into public.notificaciones (tipo, titulo, detalle, destinatario, contrato_id, enlace)
    values ('solicitud_pago',
            'Solicitud de pago SP-' || new.numero,
            coalesce(v_nombre, 'Un comercial') || ' pide un pago: ' || new.concepto,
            null, new.contrato_id,
            '/intranet/solicitudes/?id=' || new.id::text);
  elsif tg_op = 'UPDATE' and new.estado is distinct from old.estado and new.estado <> 'pendiente' then
    select u.email into v_email from public.usuarios u where u.user_id = new.creado_por;
    if v_email is not null and new.estado <> 'anulada' then
      insert into public.notificaciones (tipo, titulo, detalle, destinatario, contrato_id, enlace)
      values ('solicitud_pago',
              'Tu solicitud SP-' || new.numero || ' — ' ||
                case new.estado when 'aprobada' then 'aprobada'
                                when 'rechazada' then 'rechazada'
                                when 'pagada' then 'pagada' end,
              case when new.estado = 'rechazada' then new.motivo_rechazo
                   when new.estado = 'pagada' then coalesce(new.pago_referencia, new.concepto)
                   else new.concepto end,
              v_email, new.contrato_id,
              '/intranet/solicitudes/?id=' || new.id::text);
    end if;
    if new.estado <> 'anulada' and new.contrato_id is not null then
      select c.proyecto_id, c.proyecto_nombre into v_proyecto_id, v_proyecto_nombre
        from public.contratos c where c.id = new.contrato_id;
      select coalesce(u.nombre, u.email) into v_nombre
        from public.usuarios u where u.user_id = new.creado_por;
      perform public._avisar_managers(
        v_proyecto_id, 'solicitud_pago',
        'Solicitud SP-' || new.numero || ' — ' || new.estado,
        coalesce(v_nombre, 'Un comercial') || ' · ' || coalesce(v_proyecto_nombre, 'proyecto') || ' · ' || new.estado,
        '/intranet/solicitudes/?id=' || new.id::text, new.contrato_id);
    end if;
  end if;
  return new;
exception when others then
  return new;
end;
$$;

create or replace function public._trg_unidad_estado_aviso_manager()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare v_proyecto_nombre text;
begin
  select p.nombre into v_proyecto_nombre from public.proyectos p where p.id = new.proyecto_id;
  perform public._avisar_managers(
    new.proyecto_id, 'unidad_estado',
    'Unidad ' || coalesce(new.codigo, '') || ' — ' || coalesce(new.estado, ''),
    coalesce(v_proyecto_nombre, 'proyecto') || ' · pasa a ' || coalesce(new.estado, ''),
    '/intranet/obra/', null);
  return new;
exception when others then
  return new;
end;
$$;

drop trigger if exists trg_unidad_estado_aviso_manager on public.unidades;
create trigger trg_unidad_estado_aviso_manager
  after update on public.unidades
  for each row
  when (old.estado is distinct from new.estado)
  execute function public._trg_unidad_estado_aviso_manager();

do $$
begin
  if not exists (select 1 from vault.secrets where name = 'cron_avisos_manager') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'cron_avisos_manager');
  end if;
end $$;

create or replace function public.cron_avisos_manager_secret()
returns text
language sql
security definer
set search_path to ''
as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'cron_avisos_manager';
$$;
revoke execute on function public.cron_avisos_manager_secret() from public, anon, authenticated;
grant execute on function public.cron_avisos_manager_secret() to service_role;

select cron.schedule(
  'avisos-manager-email',
  '*/10 * * * *',
  $$
  select net.http_post(
    url     := 'https://vtulllundrfennhjddhc.supabase.co/functions/v1/avisos-manager',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'X-Cron-Secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_avisos_manager')
    ),
    body    := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
  $$
);
;
