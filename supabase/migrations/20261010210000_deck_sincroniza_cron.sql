-- AXW-66 S5/S6 (10-oct-2026): barrido DIARIO de las fotos del deck a su bucket debido.
-- Encargo: encargos/20260928_lawang_deck_fotos_privadas.md (repo de la agencia) → S6 «sincroniza diaria».
--
-- POR QUÉ: una subida con URL firmada que nunca se registra deja el fichero en su bucket sin fila. Si el deck estaba
-- abierto, ese huérfano queda en `deck`, PÚBLICO, y nada más lo barre. Seguridad (28-sep) exige que el barrido se
-- programe el MISMO día que se enciende DECK_SINCRONIZA. La acción `sincroniza` de la edge `ficheros` pide la sesión
-- de un admin y nadie la llama; el cron no tiene sesión → edge propia `deck-sincroniza` con puerta X-Cron-Secret,
-- el mismo patrón que cola-correos-envio (AXW-202) y libera-reservas-vencidas.
--
-- DUEÑO DE CADA DATO: dónde DEBE estar cada foto lo dice `deck_fotos_desajustes()` (derivado de `unidades` y
-- `deck_fotos`); dónde ESTÁ, `storage.objects.bucket_id`. Aquí no se guarda ninguna copia de ninguno de los dos.
-- El secreto vive solo en Vault (generado aquí dentro, nadie lo ha visto); lo leen el job y `cron_deck_sincroniza_secret()`.
--
-- Solo crea objetos nuevos (un secreto de Vault, una función solo service_role y un job de cron). No toca datos.
--
-- VUELTA ATRÁS:
--   select cron.unschedule('deck-sincroniza-diario');
--   drop function public.cron_deck_sincroniza_secret();
--   delete from vault.secrets where name = 'cron_deck_sincroniza';
--   (y `supabase functions delete deck-sincroniza`; para apagarlo sin quitar nada: secreto DECK_SINCRONIZA distinto de «on»)

do $$
begin
  if not exists (select 1 from vault.secrets where name = 'cron_deck_sincroniza') then
    perform vault.create_secret(
      replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
      'cron_deck_sincroniza',
      'Puerta de la edge deck-sincroniza (AXW-66 S6). Solo la leen cron_deck_sincroniza_secret() y el job deck-sincroniza-diario.');
  end if;
end $$;

create or replace function public.cron_deck_sincroniza_secret()
returns text language sql stable security definer set search_path = '' as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'cron_deck_sincroniza';
$$;
revoke all     on function public.cron_deck_sincroniza_secret() from public, anon, authenticated;
grant  execute on function public.cron_deck_sincroniza_secret() to service_role;

-- 03:37 UTC (11:37 en Bali): fuera de la hora del respaldo (22:30 UTC) y de los otros jobs de las 03:17/03:23/04:00.
-- `cron.schedule` con nombre actualiza el job si ya existe (no duplica).
select cron.schedule('deck-sincroniza-diario', '37 3 * * *', $cron$
  select net.http_post(
    url     := 'https://vtulllundrfennhjddhc.supabase.co/functions/v1/deck-sincroniza',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'X-Cron-Secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_deck_sincroniza')),
    body    := '{}'::jsonb,
    timeout_milliseconds := 120000);
$cron$);
