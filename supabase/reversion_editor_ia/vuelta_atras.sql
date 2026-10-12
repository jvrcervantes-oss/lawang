-- destructivo-ok: VUELTA ATRÁS de 20261013000000_editor_ia_apagado.sql (asistente IA del editor de textos). Solo se lanza a mano y con OK del owner.
-- Mientras el asistente siga apagado no hay datos que perder (sin usos ni marcas). Con filas en editor_ia_uso: PARA y pregunta, que es el
-- extracto de lo que se factura. Antes: retirar la edge (supabase functions delete editor-ia) y quitar textos-contrato-ia.js de la pantalla.
begin;
drop function if exists public.editor_ia_ajustes_guarda(text, jsonb, text);
drop function if exists public.editor_ia_ajustes_datos();
drop function if exists public.editor_ia_marca_revisada(text, text, text, text, text[]);
drop function if exists public.editor_ia_marcas(text, text, text);
drop function if exists public.editor_ia_aceptada(uuid, uuid);
drop function if exists public.editor_ia_cierra(uuid, boolean, text, integer, integer, integer, text, jsonb);
drop function if exists public.editor_ia_reserva(text, text, text, text, uuid, integer);
drop function if exists public.editor_ia_estado(text);
drop function if exists public._editor_ia_caduca(text);
drop function if exists public._editor_ia_falta(text);
drop function if exists public._editor_ia_periodo();
drop table if exists public.editor_ia_traduccion_marca;
drop table if exists public.editor_ia_uso;
drop table if exists public.editor_ia_saldo;
drop table if exists public.editor_ia_ajustes_log;
drop function if exists public._trg_editor_ia_log_solo_anade();
drop table if exists public.editor_ia_empresa;
drop table if exists public.editor_ia_ajustes;
commit;
