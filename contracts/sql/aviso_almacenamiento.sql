-- ============================================================================
-- Vigilancia del almacenamiento — 31-jul-2026
-- ----------------------------------------------------------------------------
-- Medido el 31-jul: 162 MB de 1 GB (15%), pero el ritmo real es 14,25 MB/día y
-- eso son ~60 DÍAS DE MARGEN. Un porcentaje bajo no tranquiliza si el ritmo se
-- lo come en dos meses, y por eso el aviso mira el margen, no solo el %.
--
-- Corre en la propia base de datos (pg_cron) y avisa por el mismo endpoint de
-- correo que usa el resto de la suite (pg_net → api/send_email.php). Sin
-- servicio externo que mantener ni credencial nueva.
--
-- Se separa `_uso_almacenamiento()` (el cálculo, sin permisos) de
-- `uso_almacenamiento()` (lo que llama el panel, con `es_agente()`): el cron
-- corre como postgres y no tiene JWT, así que compartir la función con el guard
-- dentro lo dejaría fallando en silencio todas las noches.
-- ============================================================================

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- ---- una fila por aviso enviado -------------------------------------------
-- Sirve para dos cosas: no repetir el mismo aviso cada noche, y poder responder
-- "¿nos avisó?" con una fila en vez de con un recuerdo.
create table if not exists public.avisos_almacenamiento (
  id        bigserial primary key,
  enviado_en timestamptz not null default now(),
  motivo    text not null,
  uso       jsonb not null
);
alter table public.avisos_almacenamiento enable row level security;
drop policy if exists "agentes leen avisos" on public.avisos_almacenamiento;
create policy "agentes leen avisos" on public.avisos_almacenamiento
  for select to authenticated using (public.es_agente());

-- ---- la revisión nocturna --------------------------------------------------
create or replace function public.revisar_almacenamiento()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  u jsonb;
  motivo text := null;
  margen int;
  pct numeric;
  cuerpo text;
begin
  u := public._uso_almacenamiento();
  margen := (u->>'dias_de_margen')::int;
  pct    := (u->'ficheros'->>'pct')::numeric;

  -- Dos disparadores, y hace falta cualquiera de los dos: el % avisa del techo
  -- absoluto y el margen avisa de la velocidad. Con solo el %, un ritmo que
  -- multiplique por diez pasaría de 60% a lleno entre dos revisiones.
  if pct >= 75 then
    motivo := 'el almacenamiento va por el ' || pct || '% del límite';
  elsif margen is not null and margen <= 30 then
    motivo := 'al ritmo actual quedan ' || margen || ' días de almacenamiento';
  end if;

  if motivo is null then return 'ok'; end if;

  -- Un aviso a la semana como mucho: uno cada noche se convierte en ruido y se
  -- deja de leer, que es lo mismo que no avisar.
  if exists (select 1 from public.avisos_almacenamiento
              where enviado_en > now() - interval '7 days') then
    return 'ya avisado esta semana';
  end if;

  cuerpo :=
    'Aviso automático de la intranet de Lawang.' || chr(10) || chr(10) ||
    'Motivo: ' || motivo || '.' || chr(10) || chr(10) ||
    'Ficheros: ' || round((u->'ficheros'->>'bytes')::numeric/1048576.0) || ' MB de ' ||
                    round((u->'ficheros'->>'limite')::numeric/1048576.0) || ' MB (' ||
                    (u->'ficheros'->>'pct') || '%)' || chr(10) ||
    'Base de datos: ' || round((u->'base'->>'bytes')::numeric/1048576.0) || ' MB de ' ||
                    round((u->'base'->>'limite')::numeric/1048576.0) || ' MB (' ||
                    (u->'base'->>'pct') || '%)' || chr(10) ||
    'Ritmo: ' || (u->>'ritmo_mb_dia') || ' MB/día · margen estimado: ' ||
                 coalesce(u->>'dias_de_margen','?') || ' días' || chr(10) || chr(10) ||
    'Cuando se llena, Supabase NO borra nada: RECHAZA las subidas. En esta suite '
    'eso significa que una firma se completa y su PDF no se puede guardar.' || chr(10) || chr(10) ||
    'Detalle por bucket: ' || (u->>'buckets') || chr(10) || chr(10) ||
    'Qué hacer: subir de plan, o sacar del jsonb los anexos en base64 de '
    '`contratos` (son la mayor parte del peso).';

  perform net.http_post(
    url := 'https://lawangproperties.com/contracts/api/send_email.php',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := jsonb_build_object(
      'to', 'jcervantes@lawangproperties.com',
      'subject', 'Lawang · almacenamiento: ' || motivo,
      'message', cuerpo,
      'attach', false)
  );

  insert into public.avisos_almacenamiento (motivo, uso) values (motivo, u);
  return 'avisado: ' || motivo;
end;
$$;

revoke all on function public.revisar_almacenamiento() from public, anon, authenticated;

-- ---- cada noche a las 02:00 UTC (10:00 en Bali) ----------------------------
select cron.unschedule('revisar-almacenamiento')
 where exists (select 1 from cron.job where jobname = 'revisar-almacenamiento');
select cron.schedule('revisar-almacenamiento', '0 2 * * *',
                     $$select public.revisar_almacenamiento()$$);
