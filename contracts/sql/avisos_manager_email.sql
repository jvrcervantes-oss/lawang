-- destructivo-ok: DROP TRIGGER/CREATE OR REPLACE FUNCTION son sustituciones
-- (mismo nombre, misma forma, se amplía una que ya existía), no retiradas de
-- capacidad. Cero DELETE de filas, cero RLS desactivada, cero TRUNCATE.
-- ════════════════════════════════════════════════════════════════════════════
-- AVISO POR CORREO A sales_manager/project_manager EN CAMBIO DE ESTADO — 10-sep-2026
-- ════════════════════════════════════════════════════════════════════════════
-- Parte 2 del encargo de roles (modelo de acceso en
-- permisos_agente_solo_lo_suyo_y_managers.sql). Esta es la mitad de "avisos":
-- contrato bloqueado (firmado), solicitud de pago resuelta, unidad que avanza
-- de estado — para los managers asignados al proyecto de cada fila.
--
-- MISMO PATRÓN que facturacion_automatica.sql (18-ago-2026): pg_cron + secreto
-- de Vault + `net.http_post` a una Edge, NUNCA un trigger llamando a red
-- directamente. Un trigger que bloqueara la transacción del usuario con I/O de
-- red convertiría un fallo de SMTP (ya conocido: 502 de Hostinger) en un
-- contrato que no se guarda. El trigger solo dEJA la fila en `notificaciones`
-- con `email_pendiente=true`; la Edge `avisos-manager` la recoge y la envía.
--
-- MINIMIZACIÓN (Legal, revisión previa 10-sep, CEO/flujos/revision_previa.md):
-- el correo lleva nombre + proyecto + estado + enlace. NUNCA pasaporte,
-- nacionalidad ni domicilio — ese dato sigue detrás de la RLS, tras el enlace,
-- no viaja por email.

-- ── 1. Cómo se sabe qué avisos faltan por salir como correo ─────────────────
alter table public.notificaciones
  add column if not exists email_pendiente boolean not null default false,
  add column if not exists email_enviado_en timestamptz;

comment on column public.notificaciones.email_pendiente is
  'true = esta fila tiene que salir TAMBIÉN por correo real, no solo campana. Lo pone el trigger que la crea; lo apaga la Edge avisos-manager al enviarla. Las filas normales (aviso a admins, a un agente) quedan en false: solo se manda correo para lo que un trigger marcó explícitamente.';

create index if not exists notificaciones_email_pendiente_idx
  on public.notificaciones (creado_en) where email_pendiente;

-- ── 2. Un solo sitio que decide «a qué managers avisar» ─────────────────────
-- Lo reutilizan los tres triggers de abajo — repetir el select en cada uno es
-- la lista-a-mano-en-tres-sitios que este estudio ya sabe que ES el bug.
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
  -- sin proyecto, nadie es "su" manager — fail-closed, igual que la RLS de
  -- lectura (es_manager_de): no se adivina a quién avisar.
  if p_proyecto_id is null then return; end if;
  insert into public.notificaciones (tipo, titulo, detalle, destinatario, contrato_id, enlace, email_pendiente)
  select p_tipo, p_titulo, p_detalle, u.email, p_contrato_id, p_enlace, true
    from public.usuarios u
   where u.activo and u.rol in ('sales_manager','project_manager')
     and p_proyecto_id = any(u.proyectos);
end;
$$;
revoke execute on function public._avisar_managers(uuid, text, text, text, text, uuid) from public, anon, authenticated;

-- ── 3. Contrato que se bloquea (firma) ───────────────────────────────────────
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
  return new;   -- el contrato ya se guardó; un fallo del aviso no lo deshace
end;
$$;

drop trigger if exists trg_contrato_bloqueado_aviso_manager on public.contratos;
create trigger trg_contrato_bloqueado_aviso_manager
  after update on public.contratos
  for each row
  when (old.bloqueado is distinct from new.bloqueado and new.bloqueado)
  execute function public._trg_contrato_bloqueado_aviso_manager();

-- ── 4. Solicitud de pago que cambia de estado — se AMPLÍA el trigger que ya
--       existía (9-sep, contracts/sql/solicitudes_pago.sql), no se duplica.
--       La rama de aviso al creador queda BYTE A BYTE igual; solo se añade al
--       final la de manager. ─────────────────────────────────────────────────
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
    -- 10-sep: además, si la solicitud referencia un contrato con proyecto,
    -- avisa por correo a los managers de ese proyecto (no solo al creador).
    -- Sin contrato_id (referencia opcional) no hay proyecto que derivar: se
    -- queda solo con el aviso al creador de arriba, fail-closed.
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
  return new;   -- la solicitud ya se guardó; un fallo del aviso no la deshace
end;
$$;

-- ── 5. Unidad que avanza de estado (obra) ────────────────────────────────────
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

-- ── 6. El secreto que autentica el cron ante la Edge (mismo patrón que
--       cron_facturas_secret, secreto PROPIO — un secreto por cron, nunca
--       compartido entre dos) ────────────────────────────────────────────────
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

-- ── 7. El programador — cada 10 minutos, envía lo pendiente ─────────────────
-- `cron.schedule` con nombre es upsert: correr este fichero dos veces no
-- duplica el job. Mientras la Edge no esté desplegada, cada disparo deja un
-- 404 en net._http_response y nada más — igual que facturacion_automatica.
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

-- ── Comprobación (la del catálogo) ──────────────────────────────────────────
--   select column_name from information_schema.columns where table_name='notificaciones'
--    and column_name in ('email_pendiente','email_enviado_en');   -- 2 filas
--   select tgname from pg_trigger where tgrelid in
--    ('public.contratos'::regclass,'public.unidades'::regclass) and not tgisinternal;
--   select jobname, schedule, active from cron.job where jobname = 'avisos-manager-email';
--   select name from vault.secrets where name = 'cron_avisos_manager';
-- Y de comportamiento: bloque DO que asigna un manager de prueba a un proyecto
-- (UPDATE reversible con rollback vía excepción, patrón ya usado en esta
-- sesión), fuerza `bloqueado=false→true` en un contrato de ese proyecto y
-- comprueba que aparece una fila en `notificaciones` con `email_pendiente=true`
-- para ese manager.
