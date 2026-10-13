-- LAW-558 (13-oct-2026): programa el barrido y la retención KYC diarios (edge kyc-retencion, en modo real).
-- Se aplica DESPUÉS de desplegar la edge kyc-retencion y de 20261013235338 (que crea cron_kyc_retencion_secret()):
-- sin la edge, el job llamaría a un 404 cada noche.
-- Mismo patrón que copias-firmadas-envio (job 17): el secreto lo pone la función, no el texto del job.
-- 03:47 UTC (11:47 en Bali): fuera del respaldo (22:30 UTC) y de los jobs de las 03:17/03:23/03:37/04:00 y del :41 horario.
-- `cron.schedule` con nombre actualiza el job si ya existe (no duplica). Solo construye: no toca datos.
--
-- VUELTA ATRÁS: select cron.unschedule('kyc-retencion-diario');

select cron.schedule('kyc-retencion-diario', '47 3 * * *', $cron$
  select net.http_post(
    url     := 'https://vtulllundrfennhjddhc.supabase.co/functions/v1/kyc-retencion',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'X-Cron-Secret', public.cron_kyc_retencion_secret()),
    body    := '{"dry": false}'::jsonb,
    timeout_milliseconds := 120000);
$cron$);
