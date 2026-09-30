-- destructivo-ok: owner 30-sep-2026 («si, aplica»): voz-app muerta, tabla con 0 filas, lectores ya quitados y bot-agentes redesplegado; backup datos hecho 09:51
-- 30-sep-2026 · voz-app muerta (el owner la rehara con otro enfoque): se retira contrato_documentos (0 filas).
-- Sus lectores se quitaron ANTES: bot-agentes (supabase/functions y contracts/edge) redesplegado y verificado; el HTML de
-- asistente-correos solo tenia una etiqueta de texto, no la leia. Sin vistas, sin funciones, sin triggers, sin cron.
-- Inversa: contracts/sql/inversa_limpieza_superficie_20260930.sql
drop table public.contrato_documentos;
