-- Modo mantenimiento de la INTRANET (owner, 23-sep-2026: «quiero que la
-- intranet pueda entrar en modo mantenimiento»). Hermano del de envíos
-- (20260923180000_mantenimiento_envios.sql), en la misma fila.
--
-- Con la intranet cerrada solo entran admin y super_admin (trabajan y la
-- reabren). El resto del equipo ve la pantalla de mantenimiento que pinta
-- `contracts/assets/cierre.js`, llamada desde guard.js y desde el hub.
-- ⚠️ Es una PUERTA DE INTERFAZ, no un candado de datos: la RLS no cambia.
-- Decisión escrita tras revisión previa Seguridad+Datos (23-sep).
--
-- Revisión previa:
--  · cada interruptor escribe SOLO sus columnas, con UPDATE y no upsert: un
--    INSERT…ON CONFLICT que creara la fila pondría envios_pausados a false y
--    cerrar la intranet reabriría el correo (hoy en pausa por el SMTP).
--  · el estado lo lee `intranet_estado()` y no la tabla: la policy de la
--    tabla deja leer la fila a cualquier authenticated, compradores del
--    portal incluidos, y el motivo lo escribe un admin pensando en el equipo.

alter table public.mantenimiento
  add column if not exists intranet_cerrada      boolean not null default false,
  add column if not exists intranet_motivo       text,
  add column if not exists intranet_cambiado_por uuid,
  add column if not exists intranet_cambiado_en  timestamptz;

-- Estado para la puerta: solo a quien tiene ficha ACTIVA de equipo. A cualquier
-- otro (comprador del portal) le devuelve null — no le hace falta saber nada.
create or replace function public.intranet_estado()
returns jsonb language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object('cerrada', m.intranet_cerrada, 'motivo', m.intranet_motivo)
    from public.mantenimiento m
   where m.id = 1
     and exists (select 1 from public.usuarios u
                  where u.user_id = (select auth.uid()) and u.activo)
$$;
revoke all on function public.intranet_estado() from public, anon;
grant execute on function public.intranet_estado() to authenticated;

create or replace function public.mantenimiento_intranet(p_cerrar boolean, p_motivo text default null)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not public.es_admin() then
    raise exception 'Cerrar o reabrir la intranet exige ser admin.' using errcode = '42501';
  end if;
  if p_cerrar is null then
    raise exception 'Falta indicar si se cierra o se reabre.' using errcode = '22023';
  end if;
  -- el motivo es lo único que verá el equipo bloqueado: sin él no se cierra
  if p_cerrar and nullif(btrim(p_motivo), '') is null then
    raise exception 'Escribe el motivo: es lo que verá el equipo.' using errcode = '22023';
  end if;
  update public.mantenimiento
     set intranet_cerrada      = p_cerrar,
         intranet_motivo       = case when p_cerrar then btrim(p_motivo) else null end,
         intranet_cambiado_por = (select auth.uid()),
         intranet_cambiado_en  = now()
   where id = 1;
  if not found then
    raise exception 'Falta la fila de mantenimiento (id = 1).' using errcode = 'P0002';
  end if;
end $$;
revoke all on function public.mantenimiento_intranet(boolean, text) from public, anon;
grant execute on function public.mantenimiento_intranet(boolean, text) to authenticated;
