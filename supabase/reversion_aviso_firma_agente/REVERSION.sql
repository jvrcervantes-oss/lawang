-- destructivo-ok: vuelta atrás de 20261012090544_aviso_firma_agente_por_correo.sql — devuelve el cuerpo anterior del trigger (solo campana, sin correo al agente) y el comentario de la columna. No toca filas.
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

comment on column public.notificaciones.email_pendiente is
  'true = esta fila tiene que salir TAMBIEN por correo real, no solo campana. Lo pone el trigger que la crea; lo apaga la Edge avisos-manager al enviarla. Las filas normales (aviso a admins, a un agente) quedan en false.';
