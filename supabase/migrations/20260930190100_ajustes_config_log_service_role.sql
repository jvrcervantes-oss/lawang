-- AJUSTES DEL ERP · S1 (cierre): service_role no llama a ninguna auxiliar. 30-sep-2026.
-- Las auxiliares de 20260930190000 solo las usan el trigger y la RPC de escritura (DEFINER, dueño postgres, ejecutan con sus
-- propios privilegios): nadie necesita EXECUTE de service_role, y «lo nuevo nace cerrado» (contexto/seguridad_2026.md §1.ter).
-- Pareja: erp/migraciones/20260930190100_ajustes_config_log_service_role.sql (maestro). Solo revoca.
revoke all on function public._ajustes_claves_editables() from service_role;
revoke all on function public._ajustes_es_sensible(text) from service_role;
revoke all on function public._trg_ajustes_log() from service_role;
revoke all on function public._trg_ajustes_log_inmutable() from service_role;
