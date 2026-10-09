-- REVERSION de 20261010141000_bot_sin_redis_s5_importar_ajustes.sql. NO es una migracion.
-- Quita el envoltorio y devuelve su nombre al nucleo (la funcion de 20261010135000). bot_importar_config vuelve a la version de esa migracion
-- reaplicando su bloque (los dos arreglos eran de forma; no hay datos que deshacer).
drop function if exists public.bot_importar_chat(jsonb);
alter function public._bot_importar_chat_nucleo(jsonb) rename to bot_importar_chat;
revoke all on function public.bot_importar_chat(jsonb) from public, anon, authenticated, service_role;
grant execute on function public.bot_importar_chat(jsonb) to bot_lawang;
