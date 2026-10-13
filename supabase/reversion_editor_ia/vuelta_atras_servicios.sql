-- destructivo-ok: VUELTA ATRÁS de 20261013210000_servicios_axisworks_editor_ia.sql («Servicios de AxisWorks», coste + margen).
-- Solo a mano, con OK del owner y su válvula (tools/no_destruir.py), y con copia previa:
--   python erp/respaldo_instancia.py lawang --previa "antes de revertir servicios de AxisWorks"
--
-- PASO 1 — PARAR EL GASTO (no borra nada; basta casi siempre). Lo mismo se hace desde Ajustes → Servicios de AxisWorks.
--   update public.editor_ia_empresa set encendido = false, actualizado_por = 'estudio (vuelta atrás)', actualizado_en = now()
--    where empresa = 'lawang';
--
-- PASO 2 — QUITAR LA PIEZA ENTERA. Con filas en editor_ia_uso: PARA y pregunta, que es el extracto de lo que se factura (exportarlo antes).
-- Las funciones de la migración anterior (créditos) no se restauran: el modelo de créditos lo sustituyó el owner el 13-oct. Lo coherente es
-- retirar el asistente entero: este fichero y después vuelta_atras.sql (que quita todo lo editor_ia_*). Antes: retirar la edge
-- (supabase functions delete editor-ia) y la pestaña de Ajustes (ajustes-servicios.js) y textos-contrato-ia.js de la pantalla.
begin;
drop function if exists public.editor_ia_rechazada(uuid, integer);            -- 20261013220000
drop function if exists public._editor_ia_falta_clave(text);                -- 20261013220000
drop function if exists public.servicios_axisworks_guarda(text, jsonb, text);
drop function if exists public.servicios_axisworks_datos();
drop function if exists public._servicios_tope_empresa(text);
drop function if exists public._servicios_gasto_mes(text, date);
drop function if exists public._editor_ia_peso(public.editor_ia_uso);
drop function if exists public._editor_ia_coste_max(text);
drop table if exists public.servicios_axisworks_log;
drop function if exists public._trg_servicios_log_solo_anade();
drop table if exists public.servicios_axisworks_empresa;
drop table if exists public.servicios_axisworks_ajustes;
-- _editor_ia_falta, editor_ia_estado, editor_ia_reserva y editor_ia_cierra leen las tablas de arriba: quedan rotas a propósito hasta
-- vuelta_atras.sql (el asistente sin margen ni tope no debe poder llamar a nadie).
commit;
