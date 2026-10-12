-- destructivo-ok: vuelta atrás de 20261012090544_aviso_firma_agente_por_correo.sql y 20261012094018_aviso_firma_autor_sin_hueco_managers.sql — devuelve el cuerpo anterior del trigger (solo campana, sin correo al autor), _avisar_managers con su condición en línea (la de 20260930065223, resultado idéntico) y el comentario de la columna, y retira la función interna _manager_recibe_aviso (sin datos, sin grants). No toca filas.
-- Los avisos ya apuntados con email_pendiente = true que no hayan salido se pueden dejar: salen en la siguiente pasada. Si no deben salir, apagarlos a mano es un UPDATE de filas reales: pide el OK del owner.

create or replace function public.trg_aviso_contrato_firmado()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  begin
    if coalesce(new.bloqueado,false) and not coalesce(old.bloqueado,false) then
      perform anotar_aviso('contrato_firmado',
        coalesce(new.numero,'Contrato') || ' firmado',
        coalesce(new.comprador_nombre,'sin comprador') || coalesce(' · ' || new.proyecto_nombre, ''),
        new.creado_por, new.id, '/intranet/operaciones/?contrato=' || new.id);
    end if;
  exception when others then
    raise warning 'aviso contrato_firmado (%) no se pudo anotar: %', new.id, sqlerrm;
  end;
  return new;
end $function$;

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
     and ((u.rol = 'project_manager' and p_proyecto_id = any(u.proyectos))
          or (u.rol = 'sales_manager' and p_contrato_id is null and p_proyecto_id = any(u.proyectos))
          or (u.rol = 'sales_manager' and p_contrato_id is not null
              and exists (select 1 from public.equipos_venta ev
                           where ev.activo and lower(ev.manager_email) = lower(u.email)
                             and ev.id = public._venta_equipo(p_contrato_id))));
end;
$function$;

drop function if exists public._manager_recibe_aviso(text, text, uuid[], uuid, uuid);

comment on column public.notificaciones.email_pendiente is
  'true = esta fila tiene que salir TAMBIEN por correo real, no solo campana. Lo pone el trigger que la crea; lo apaga la Edge avisos-manager al enviarla. Las filas normales (aviso a admins, a un agente) quedan en false.';
