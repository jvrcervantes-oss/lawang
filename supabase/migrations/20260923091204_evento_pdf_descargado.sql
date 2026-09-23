-- Aplicada por MCP el 23-sep-2026 (version 20260923091204). Fuente con los porqués:
-- contracts/sql/evento_pdf_descargado.sql (este fichero es su copia).
-- ═══════════════════════════════════════════════════════════════════════════
-- «SUBIR FIRMADO» SOLO DESPUÉS DE QUE EL PDF HAYA SALIDO — 23-sep-2026, owner
-- ═══════════════════════════════════════════════════════════════════════════
-- Owner, al revisar las herramientas del generador en la v4: «Subir firmado no
-- debería aparecer hasta que no hayan como mínimo descargado el pdf». No se
-- puede subir firmado un documento que nunca salió del sistema.
--
-- Hasta hoy nadie apuntaba una descarga: el PDF se imprime en el navegador
-- (printPreview) y la base no se enteraba. Así que «¿salió ya?» no tenía
-- respuesta al reabrir un contrato. El owner eligió apuntarlo en el registro
-- del contrato, junto a los demás eventos (y no recordarlo solo en la pestaña).
--
-- Tres piezas:
--   1. 'pdf_descargado' entra en la lista cerrada del CHECK.
--   2. contrato_pdf_descargado(id): lo apunta la app al descargar.
--   3. contrato_pdf_salio(id): la ÚNICA definición de «el PDF ya salió», que lee
--      la app para encender «Subir firmado». Vale cualquiera de las tres:
--        · alguien lo descargó (evento de arriba);
--        · se mandó por email desde el generador (correos_enviados);
--        · el contrato es anterior a esta regla: de esos no hay historial de
--          descargas, y exigirlo los dejaría sin poder cerrarse nunca.
--      Vive aquí y no en el JS para que la decisión tenga un solo dueño.
--
-- Acceso: las dos funciones son security definer (la tabla de eventos no tiene
-- policy de INSERT: la escriben triggers), así que comprueban a mano el mismo
-- criterio que la policy de SELECT de contrato_eventos: super admin, o agente
-- dueño del contrato o manager de su proyecto.
-- ═══════════════════════════════════════════════════════════════════════════

-- 1 · El CHECK. Se recrea con los 21 valores vivos (consultados en
-- pg_constraint el 23-sep) + 'pdf_descargado'. La declaración que vigila
-- eventos.test.js es sql/super_admin_poderes.sql y se actualiza con esto.
-- destructivo-ok: se recrea el CHECK ampliándolo; no se borra ningún dato
alter table public.contrato_eventos drop constraint if exists contrato_eventos_evento_check;
alter table public.contrato_eventos add constraint contrato_eventos_evento_check
  check (evento = any (array[
    'creado','editado','tipo_cambiado','enviado_a_firma','firma_abierta','firma_recogida',
    'firma_anulada','firmado_del_todo','desbloqueado','traspaso',
    'editado_estando_firmado','desbloqueado_estando_firmado','factura_sin_bloquear','cobro_a_factura_huerfana',
    'cobro_a_otro_comprador','comprador_sin_ficha','factura_borrada','contrato_borrado',
    'reserva_liberada','reserva_prorrogada','reserva_liberacion_deshecha','pdf_descargado'
  ]));

-- quién puede hablar de este contrato: el criterio de la policy de SELECT
create or replace function public._puede_ver_contrato(p_contrato uuid)
returns boolean language sql stable security definer
set search_path to ''
as $$
  select public.es_super_admin() or (public.es_agente() and exists (
    select 1 from public.contratos c
    where c.id = p_contrato
      and (public.es_suyo(c.creado_por) or public.es_manager_de(c.proyecto_id))))
$$;
revoke execute on function public._puede_ver_contrato(uuid) from public, anon, authenticated;

-- 2 · Apuntar la descarga
create or replace function public.contrato_pdf_descargado(p_contrato uuid)
returns void language plpgsql security definer
set search_path to ''
as $$
begin
  if not public._puede_ver_contrato(p_contrato) then
    raise exception 'No tienes acceso a ese contrato' using errcode = '42501';
  end if;
  -- una por persona y día: el registro dice QUE salió, no cuenta clics
  if exists (select 1 from public.contrato_eventos e
             where e.contrato_id = p_contrato and e.evento = 'pdf_descargado'
               and e.quien is not distinct from public._quien_actua()
               and e.creado_en > now() - interval '1 day') then
    return;
  end if;
  insert into public.contrato_eventos (contrato_id, evento, quien)
  values (p_contrato, 'pdf_descargado', public._quien_actua());
end $$;
revoke execute on function public.contrato_pdf_descargado(uuid) from public, anon;
grant execute on function public.contrato_pdf_descargado(uuid) to authenticated;

-- 3 · ¿Salió ya el PDF?
create or replace function public.contrato_pdf_salio(p_contrato uuid)
returns boolean language sql stable security definer
set search_path to ''
as $$
  select public._puede_ver_contrato(p_contrato) and (
       exists (select 1 from public.contrato_eventos e
               where e.contrato_id = p_contrato and e.evento = 'pdf_descargado')
    or exists (select 1 from public.correos_enviados m where m.contrato_id = p_contrato)
    -- anterior a la regla: la regla entró en vigor el 24-sep-2026 (hora de Bali)
    or exists (select 1 from public.contratos c
               where c.id = p_contrato and c.created_at < timestamptz '2026-09-24 00:00:00+08'))
$$;
revoke execute on function public.contrato_pdf_salio(uuid) from public, anon;
grant execute on function public.contrato_pdf_salio(uuid) to authenticated;
