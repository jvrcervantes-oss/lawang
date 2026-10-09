-- REVERSION de 20261010120000_bot_sin_redis_s7_purga.sql (S7 del encargo «bot de Lawang sin Redis»).
-- NO es una migracion: no se aplica sola. Solo si el owner pide deshacer S7. Quita el job de purga, el olvido y la retirada de resumenes.
-- Las trazas (bot_purga_log, bot_olvidos_log, lead_notas_retiradas) se borran con su tabla: si ya hay olvidos registrados, EXPORTAR ANTES
-- (bot_olvidos_log es la unica forma de reaplicar un olvido tras restaurar un backup). Orden: job -> funciones -> triggers -> tablas.

select cron.unschedule('bot_purga') where exists (select 1 from cron.job where jobname = 'bot_purga');

drop function if exists public.lead_nota_retirar(bigint, text);
drop function if exists public.bot_olvidos_reaplicar();
drop function if exists public.crm_bot_olvidar(text, text, boolean);
drop function if exists public._bot_olvidar_tel(text, boolean);
drop function if exists public._bot_tel_hash(text);
drop function if exists public.bot_purga();

-- bot_acciones_log vuelve a ser de solo anadir sin excepcion (la funcion compartida original)
drop trigger if exists trg_bot_acciones_log_solo_anade on public.bot_acciones_log;
create trigger trg_bot_acciones_log_solo_anade before update or delete on public.bot_acciones_log
  for each row execute function public.bot_acciones_log_solo_anade();

drop table if exists public.lead_notas_retiradas;
drop table if exists public.bot_olvidos_log;
drop table if exists public.bot_purga_log;      -- los triggers caen con la tabla (bot_purga_log lo bloquea el trigger de truncate: no es truncate, es drop)
drop function if exists public._bot_log_solo_anade_purga();
