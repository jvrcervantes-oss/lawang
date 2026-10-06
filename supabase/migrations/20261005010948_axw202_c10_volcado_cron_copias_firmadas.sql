-- AXW-202 C1.0 (5-oct-2026): volcar al repo lo que AXW-127 aplicó por MCP y no quedó versionado.
--
-- Producción ya tiene esto desde el 1-oct; esta migración NO cambia el comportamiento, solo hace
-- que el repo diga lo que hay (el molde que copiará la cola de correos, AXW-202 C1):
--   · `_copias_firmadas_despierta()` real (la migración 20261001160000 deja un stub `null`).
--   · el cron `copias-firmadas-envio` (jobid 17, cada 10 min) — no estaba en ninguna migración.
-- Leído de `pg_get_functiondef` y `cron.job` el 5-oct-2026. El secreto (`cron_copias_firmadas`)
-- ya lo crea 20261001160000 en Vault; aquí no hay valores secretos.
-- Idempotente: reaplicarla deja producción igual.

create or replace function public._copias_firmadas_despierta()
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform net.http_post(
    url     := 'https://vtulllundrfennhjddhc.supabase.co/functions/v1/copias-firmadas-envio',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'X-Cron-Secret', public.cron_copias_firmadas_secret()),
    body    := '{}'::jsonb,
    timeout_milliseconds := 60000);
exception when others then
  raise warning 'copias firmadas: no se pudo despertar la Edge (%): la recoge el cron', sqlerrm;
end $$;

revoke execute on function public._copias_firmadas_despierta() from public, anon, authenticated;
grant  execute on function public._copias_firmadas_despierta() to service_role;

-- `cron.schedule` con nombre actualiza el job si ya existe (no duplica).
select cron.schedule(
  'copias-firmadas-envio',
  '*/10 * * * *',
  $cron$
  select net.http_post(
    url     := 'https://vtulllundrfennhjddhc.supabase.co/functions/v1/copias-firmadas-envio',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'X-Cron-Secret', public.cron_copias_firmadas_secret()),
    body    := '{}'::jsonb,
    timeout_milliseconds := 60000);
  $cron$);
