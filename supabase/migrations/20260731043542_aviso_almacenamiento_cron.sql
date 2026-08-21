create extension if not exists pg_cron;
create extension if not exists pg_net;

create table if not exists public.avisos_almacenamiento (
  id         bigserial primary key,
  enviado_en timestamptz not null default now(),
  motivo     text not null,
  uso        jsonb not null
);
alter table public.avisos_almacenamiento enable row level security;
drop policy if exists "agentes leen avisos" on public.avisos_almacenamiento;
create policy "agentes leen avisos" on public.avisos_almacenamiento
  for select to authenticated using (public.es_agente());

create or replace function public.revisar_almacenamiento()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  u jsonb; motivo text := null; margen int; pct numeric; cuerpo text;
begin
  u := public._uso_almacenamiento();
  margen := (u->>'dias_de_margen')::int;
  pct    := (u->'ficheros'->>'pct')::numeric;

  if pct >= 75 then
    motivo := 'el almacenamiento va por el ' || pct || '% del limite';
  elsif margen is not null and margen <= 30 then
    motivo := 'al ritmo actual quedan ' || margen || ' dias de almacenamiento';
  end if;

  if motivo is null then return 'ok'; end if;

  if exists (select 1 from public.avisos_almacenamiento
              where enviado_en > now() - interval '7 days') then
    return 'ya avisado esta semana';
  end if;

  cuerpo :=
    'Aviso automatico de la intranet de Lawang.' || chr(10) || chr(10) ||
    'Motivo: ' || motivo || '.' || chr(10) || chr(10) ||
    'Ficheros: ' || round((u->'ficheros'->>'bytes')::numeric/1048576.0) || ' MB de ' ||
                    round((u->'ficheros'->>'limite')::numeric/1048576.0) || ' MB (' ||
                    (u->'ficheros'->>'pct') || '%)' || chr(10) ||
    'Base de datos: ' || round((u->'base'->>'bytes')::numeric/1048576.0) || ' MB de ' ||
                    round((u->'base'->>'limite')::numeric/1048576.0) || ' MB (' ||
                    (u->'base'->>'pct') || '%)' || chr(10) ||
    'Ritmo: ' || (u->>'ritmo_mb_dia') || ' MB/dia - margen estimado: ' ||
                 coalesce(u->>'dias_de_margen','?') || ' dias' || chr(10) || chr(10) ||
    'Cuando se llena, Supabase NO borra nada: RECHAZA las subidas. En esta suite eso '
    'significa que una firma se completa y su PDF no se puede guardar.' || chr(10) || chr(10) ||
    'Detalle por bucket: ' || (u->>'buckets') || chr(10) || chr(10) ||
    'Que hacer: subir de plan, o sacar del jsonb los anexos en base64 de contratos '
    '(son la mayor parte del peso).';

  perform net.http_post(
    url := 'https://lawangproperties.com/contracts/api/send_email.php',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := jsonb_build_object(
      'to', 'jcervantes@lawangproperties.com',
      'subject', 'Lawang - almacenamiento: ' || motivo,
      'message', cuerpo, 'attach', false));

  insert into public.avisos_almacenamiento (motivo, uso) values (motivo, u);
  return 'avisado: ' || motivo;
end;
$$;
revoke all on function public.revisar_almacenamiento() from public, anon, authenticated;;
