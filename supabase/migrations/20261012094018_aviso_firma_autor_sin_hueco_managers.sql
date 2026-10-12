-- destructivo-ok: solo `create function` nueva (interna, sin grants) y `create or replace` de _avisar_managers (mismo resultado, la condición pasa a la función nueva) y de trg_aviso_contrato_firmado. No borra ni cambia filas, no toca RLS.
-- ============================================================================
-- Aviso por correo al AUTOR del contrato cuando su cliente firma — sin hueco
-- para los managers (12-oct-2026; corrige 20261012090544 tras el revisor)
-- ----------------------------------------------------------------------------
-- 20261012090544 mandaba el correo solo al rol 'agente' y daba por hecho que
-- un sales_manager / project_manager «ya recibe» el correo contrato_bloqueado.
-- Falso en parte: _avisar_managers solo avisa al sales_manager si la venta es
-- de SU equipo activo y al project_manager si el proyecto está en SU lista.
-- Medido en producción (90 días): de 22 firmas creadas por sales_manager, 9 no
-- tenían su correo de manager; de 8 de project_manager, 4. Esas personas
-- vendieron y no se habrían enterado por correo.
--
-- REGLA NUEVA — recibe el correo el autor del contrato (creado_por) si:
--   · es un usuario ACTIVO (avisos-manager no mira `activo`: el filtro va aquí),
--   · no es admin / super_admin (reciben la copia del estudio y lo ven todo;
--     decisión por defecto del CEO, reversible quitando la exclusión), y
--   · NO es uno de los managers que _avisar_managers avisa por ESTE contrato
--     (si lo fuera recibiría dos correos por la misma firma).
--
-- UNA SOLA FUENTE para «¿este manager recibe el aviso de este contrato?»:
-- _manager_recibe_aviso(). La usan _avisar_managers (que la tenía en su WHERE)
-- y este trigger. Así no hay dos copias de la regla que puedan divergir, y no
-- se depende del orden de disparo entre los dos triggers de contratos.
--
-- Quién es «el agente»: el AUTOR (creado_por), no el closer de
-- contrato_closer. Es el mismo criterio que ya usaba la campana; decisión por
-- defecto, anotada para el owner.
--
-- VUELTA ATRÁS: supabase/reversion_aviso_firma_agente/REVERSION.sql
-- ============================================================================

create or replace function public._manager_recibe_aviso(
  p_rol text, p_email text, p_proyectos uuid[], p_proyecto_id uuid, p_contrato_id uuid
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select p_proyecto_id is not null
     and ((p_rol = 'project_manager' and p_proyecto_id = any(p_proyectos))
          or (p_rol = 'sales_manager' and p_contrato_id is null and p_proyecto_id = any(p_proyectos))
          or (p_rol = 'sales_manager' and p_contrato_id is not null
              and exists (select 1 from public.equipos_venta ev
                           where ev.activo and lower(ev.manager_email) = lower(p_email)
                             and ev.id = public._venta_equipo(p_contrato_id))));
$$;
revoke execute on function public._manager_recibe_aviso(text, text, uuid[], uuid, uuid) from public, anon, authenticated;

create or replace function public._avisar_managers(p_proyecto_id uuid, p_tipo text, p_titulo text, p_detalle text, p_enlace text, p_contrato_id uuid default null::uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if p_proyecto_id is null then return; end if;
  insert into public.notificaciones (tipo, titulo, detalle, destinatario, contrato_id, enlace, email_pendiente)
  select p_tipo, p_titulo, p_detalle, u.email, p_contrato_id, p_enlace, true
    from public.usuarios u
   where u.activo
     and public._manager_recibe_aviso(u.rol, u.email, u.proyectos, p_proyecto_id, p_contrato_id);
end;
$function$;

create or replace function public.trg_aviso_contrato_firmado()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_dest text := nullif(btrim(coalesce(new.creado_por, '')), '');
begin
  begin
    if coalesce(new.bloqueado,false) and not coalesce(old.bloqueado,false) then
      insert into notificaciones (tipo, titulo, detalle, destinatario, contrato_id, enlace, email_pendiente)
      values ('contrato_firmado',
        coalesce(new.numero,'Contrato') || ' firmado',
        coalesce(new.comprador_nombre,'sin comprador') || coalesce(' · ' || new.proyecto_nombre, ''),
        v_dest, new.id, '/intranet/operaciones/?contrato=' || new.id,
        v_dest is not null and exists (
          select 1 from usuarios u
           where u.activo
             and lower(btrim(u.email)) = lower(v_dest)
             and u.rol not in ('admin', 'super_admin')
             and not public._manager_recibe_aviso(u.rol, u.email, u.proyectos, new.proyecto_id, new.id)));
    end if;
  exception when others then
    raise warning 'aviso contrato_firmado (%) no se pudo anotar: %', new.id, sqlerrm;
  end;
  return new;
end $function$;

comment on column public.notificaciones.email_pendiente is
  'true = esta fila tiene que salir TAMBIEN por correo real, no solo campana. La pone el trigger que la crea (_avisar_managers para managers; trg_aviso_contrato_firmado para el autor activo del contrato que no es admin ni ya recibe el aviso de manager, desde el 12-oct-2026); la apaga la Edge avisos-manager al enviarla. El resto de filas quedan en false.';
