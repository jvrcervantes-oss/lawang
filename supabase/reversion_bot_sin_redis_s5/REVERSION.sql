-- REVERSION de 20261010135000_bot_sin_redis_s5_importar.sql (S5 del encargo «bot de Lawang sin Redis»).
-- NO es una migracion. Tambien es lo que S9 ejecuta para RETIRAR el importador una vez hecha la migracion.
-- Lo importado (filas de bot_chat/bot_mensaje...) no se toca: solo se quitan las funciones y se restaura _bot_config_log a la version de S1.
drop function if exists public.bot_importar_chat(jsonb);
drop function if exists public.bot_importar_cuadre(text);
drop function if exists public.bot_importar_config(jsonb);
drop function if exists public._bot_importar_ms(bigint);
create or replace function public._bot_config_log()
returns trigger language plpgsql security definer set search_path = '' as $f$
begin
  insert into public.bot_config_log (usuario, version, prev, next)
  values (left(coalesce(nullif(new.actualizado_por, ''), 'desconocido'), 120), new.version, to_jsonb(old), to_jsonb(new));
  return null;
end $f$;
