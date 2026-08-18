-- ════════════════════════════════════════════════════════════════════════════
-- FACTURACIÓN AUTOMÁTICA A D-3 — la parte de base de datos — 18-ago-2026
-- ════════════════════════════════════════════════════════════════════════════
-- Encargo del cliente: «que el sistema genere las facturas tres días antes del
-- vencimiento y las mande al cliente para que proceda con el pago».
--
-- ⚠️ CONTEXTO QUE NO SE PUEDE IGNORAR. El 11-ago se RETIRÓ la factura automática
-- al firmar, por decisión del dueño y tras descabalar un balance real: «una
-- factura automática con fuerza de cobro sin que un agente la revise es dinero
-- mal pedido». Este encargo (18-ago) reabre la vía con otro disparador — la
-- fecha de vencimiento — y por eso esta versión lleva lo que aquella no tenía:
--   · el importe sale de la CASCADA (lo pendiente de verdad, descontado lo ya
--     cobrado — incluida la señal de la Carta), no del hito bruto;
--   · idempotente: `factura_id` marca el vencimiento facturado y no se repite;
--   · `no_facturar` por vencimiento, para los pagos que se negocian aparte;
--   · tope por ejecución y copia al estudio de cada envío;
--   · solo contratos FIRMADOS, solo fechas de hoy a hoy+3 (lo vencido del
--     pasado es territorio humano, no de un robot).
-- La lógica corre en la edge `factura-vencimiento`; aquí va lo que es de la
-- base: columnas de control, el secreto del cron y el programador.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. Columnas de control en contrato_vencimientos ─────────────────────────
-- `factura_id`: qué factura salió de este vencimiento. La escribe SOLO la edge
-- (service_role): el equipo no tiene grant sobre ella — poder marcarla a mano
-- sería poder fingir que algo se facturó.
-- `no_facturar`: el opt-out por vencimiento. Este SÍ es del equipo.
alter table public.contrato_vencimientos
  add column if not exists factura_id uuid references public.facturas(id) on delete set null,
  add column if not exists no_facturar boolean not null default false;

grant update (no_facturar) on public.contrato_vencimientos to authenticated;

-- ── 2. El secreto que autentica al cron ante la edge ────────────────────────
-- Se genera DENTRO de la base (gen_random_bytes) y vive en Vault: no pasa por
-- ningún repo, ninguna sesión ni ningún portapapeles. Lo leen dos actores:
--   · el cron, directamente de vault.decrypted_secrets (corre como postgres);
--   · la edge, vía la función de abajo con su service key.
-- Idempotente: si ya existe, no se regenera (regenerarlo rompería un cron ya
-- programado hasta la siguiente lectura).
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'cron_facturas') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'cron_facturas');
  end if;
end $$;

-- La ventanilla para la edge: SECURITY DEFINER porque vault no está expuesto a
-- PostgREST, y con EXECUTE SOLO para service_role — para cualquier otro rol
-- esta función no existe. Es un secreto: la lista de avisos del linter la va a
-- señalar, y la respuesta es este comentario.
create or replace function public.cron_facturas_secret()
returns text
language sql
security definer
set search_path to ''
as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'cron_facturas';
$$;
revoke execute on function public.cron_facturas_secret() from public, anon, authenticated;
grant execute on function public.cron_facturas_secret() to service_role;

-- ── 3. El programador ───────────────────────────────────────────────────────
-- Diario a las 05:00 UTC (07:00 en Madrid, 13:00 en Bali): las facturas salen
-- por la mañana europea, que es donde está el equipo que respondería dudas.
-- `cron.schedule` con nombre es un upsert: correr este fichero dos veces no
-- duplica el trabajo.
-- Mientras la edge no esté desplegada (LAW-75) cada disparo deja un 404 en
-- net._http_response y NADA más: el sistema entero es inerte hasta ese deploy,
-- y se enciende solo con él — sin un segundo paso que alguien pueda olvidar.
select cron.schedule(
  'facturas-vencimiento-d3',
  '0 5 * * *',
  $$
  select net.http_post(
    url     := 'https://vtulllundrfennhjddhc.supabase.co/functions/v1/factura-vencimiento',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'X-Cron-Secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_facturas')
    ),
    body    := '{"dry": false}'::jsonb,
    timeout_milliseconds := 120000
  );
  $$
);

-- ── Comprobación (la del catálogo) ──────────────────────────────────────────
--   select jobname, schedule, active from cron.job where jobname = 'facturas-vencimiento-d3';
--   select name from vault.secrets where name = 'cron_facturas';
--   select column_name from information_schema.columns
--    where table_name='contrato_vencimientos' and column_name in ('factura_id','no_facturar');
-- Y tras el primer disparo real: select status, (response).status_code
--   from net._http_response order by created desc limit 3;
