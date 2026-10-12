-- destructivo-ok: solo `create or replace` de la función del trigger (mismo nombre, misma forma, misma campana) y un `comment on column`. No borra filas, no cambia filas existentes (sin relleno: los avisos viejos se quedan en false y no salen), no toca RLS.
-- ============================================================================
-- Aviso por correo al AGENTE cuando su cliente firma (12-oct-2026, owner)
-- ----------------------------------------------------------------------------
-- PETICIÓN DEL OWNER: «hay que mandárselo al agente también, el contrato no,
-- una notificación como que han firmado». Hasta hoy el agente que creó el
-- contrato solo lo veía en la campana de la intranet; por correo salía a los
-- managers (contrato_bloqueado), al estudio y a los compradores.
--
-- CÓMO: no hay pieza nueva. La campana del agente ya la apunta este trigger
-- (tipo contrato_firmado, destinatario = creado_por). Se le pone
-- email_pendiente = true y la edge avisos-manager (cron cada 10 min) la manda
-- como texto: asunto «Nombre, CRxxxxx firmado», comprador · proyecto y el
-- enlace a Operaciones. Sin PDF (MINIMIZACIÓN de la edge: nunca PII de KYC).
--
-- A QUIÉN: solo a un usuario ACTIVO con rol 'agente'.
--   · sales_manager / project_manager ya reciben el correo contrato_bloqueado
--     de _avisar_managers: con ellos serían dos correos por firma.
--   · admin / super_admin ya reciben la copia del estudio, y el owner pidió
--     «al agente». Decisión por defecto, reversible: añadir el rol a la lista.
--   · avisos-manager NO mira `activo` antes de enviar: el filtro va aquí.
--   Se filtra por rol y no copiando la lógica de _avisar_managers para no
--   tener dos sitios que decidan «quién es manager de este contrato» ni
--   depender del orden de disparo entre triggers (suite_lawang.md).
--
-- anotar_aviso NO se toca: la comparten los demás avisos y añadirle un
-- parámetro crearía una sobrecarga ambigua que los dejaría mudos.
--
-- VUELTA ATRÁS: supabase/reversion_aviso_firma_agente/REVERSION.sql (cuerpo
-- anterior tal cual, con perform anotar_aviso).
-- ============================================================================

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
           where u.activo and u.rol = 'agente'
             and lower(btrim(u.email)) = lower(v_dest)));
    end if;
  exception when others then
    raise warning 'aviso contrato_firmado (%) no se pudo anotar: %', new.id, sqlerrm;
  end;
  return new;
end $function$;

comment on column public.notificaciones.email_pendiente is
  'true = esta fila tiene que salir TAMBIEN por correo real, no solo campana. La pone el trigger que la crea (_avisar_managers para managers; trg_aviso_contrato_firmado para el agente activo con rol agente desde el 12-oct-2026); la apaga la Edge avisos-manager al enviarla. El resto de filas (admins, otros avisos) quedan en false.';
