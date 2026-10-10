-- Reconstruida el 10-oct-2026 desde supabase_migrations.schema_migrations.statements (nombre exacto; version real del catalogo 20261001145838, el prefijo sigue al fichero padre para que el orden de replay sea el de aplicacion; ya APLICADA en produccion, no se vuelve a aplicar). El padre 20261001160000_axw127_cola_copias_firmadas.sql solo deja el esqueleto de _copias_firmadas_despierta; la funcion y el cron vigentes estan en 20261005010948_axw202_c10_volcado_cron_copias_firmadas.sql
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
  $cron$
);
