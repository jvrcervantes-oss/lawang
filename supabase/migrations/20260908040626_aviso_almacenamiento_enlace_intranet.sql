-- Fuente única: contracts/sql/aviso_almacenamiento.sql
-- 8-sep-2026. Único cambio: el cuerpo del aviso termina con el enlace a la
-- intranet. Desde hoy `send_email.php` ya no deduce el botón por el dominio del
-- destinatario (mandaba a la intranet a clientes con correo del dominio); el
-- botón de la intranet solo aparece si el propio mensaje trae el enlace. Sin
-- esta línea, este aviso INTERNO saldría con un botón al área de CLIENTES.
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
    '`contratos` (son la mayor parte del peso).' || chr(10) || chr(10) ||
    'Ver en la intranet: https://lawangproperties.com/intranet/';

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

revoke all on function public.revisar_almacenamiento() from public, anon, authenticated;;
