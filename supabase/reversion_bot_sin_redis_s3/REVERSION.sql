-- REVERSION de 20261010120000_bot_sin_redis_s3_config.sql (S3 del encargo «bot de Lawang sin Redis»).
-- NO es una migracion: no se aplica sola. Quita solo las 6 funciones de S3; bot_config y bot_config_log (S1) y sus datos NO se tocan.
-- Antes de ejecutarla, poner BOT_CONFIG_STORE=redis en los secretos de la edge lawang-bot-proxy (o volver a la version anterior de la edge):
-- sin las funciones, config_get/config_set con BOT_CONFIG_STORE=postgres darian error 500.
-- destructivo-ok: solo borra funciones que creo S3.
drop function if exists public.crm_bot_config_leer(uuid);
drop function if exists public.crm_bot_config_guardar(uuid, text, text, integer, bigint, text);
drop function if exists public.crm_bot_config_volver(uuid, bigint, text);
drop function if exists public._crm_bot_config_autoriza(uuid);
drop function if exists public._crm_bot_config_json();
drop function if exists public._crm_bot_config_limpia(text);
