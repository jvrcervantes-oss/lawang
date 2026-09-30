-- AJUSTES DEL ERP · AXW-123 (fase 1, 30-sep/1-oct-2026): las dos funciones SQL que mandan aviso por pg_net mandan ahora la
-- cabecera X-Aviso-Secret con un secreto de Vault (`envio_aviso`), para poder cerrar la puerta anonima de la edge
-- `envia-correo` (vía de aviso sin credencial) definiendo ENVIO_AVISO_SECRET en la edge. Mientras la edge no lo exija,
-- la cabecera se ignora; si la URL cae al PHP, tambien se ignora. Orden de activacion: 1) esta migracion, 2) el panel,
-- 3) `supabase secrets set ENVIO_AVISO_SECRET`. Decision del owner (30-sep): secreto en Vault, como el del cron avisos-manager.
-- `_aviso_cabecera()` devuelve {} si el secreto no existe (no rompe el aviso). Solo service_role/definer la usan.
-- Cuerpos identicos a los de 20260930230000 salvo la linea de `headers`.

create or replace function public._aviso_cabecera()
returns jsonb
language sql security definer set search_path = '' as $$
  select coalesce(
    (select jsonb_build_object('X-Aviso-Secret', decrypted_secret)
       from vault.decrypted_secrets where name = 'envio_aviso' and decrypted_secret is not null),
    '{}'::jsonb);
$$;
revoke all on function public._aviso_cabecera() from public, anon, authenticated;

create or replace function public._avisar_equipo_soporte(p_client_id uuid, p_asunto text, p_cuerpo text)
returns void
language plpgsql security definer set search_path = '' as $$
declare v_url text;
begin
  if exists (
    select 1 from public.avisos_soporte_equipo
     where client_id = p_client_id and enviado_en > now() - interval '2 minutes'
  ) then
    return;   -- ya se avisó hace poco de este mismo comprador; el equipo ya lo sabe
  end if;

  v_url := coalesce(
    (select nullif(btrim(c.valor #>> '{}'), '') from public.config_instancia c
      where c.clave = 'url_envio_correo' and jsonb_typeof(c.valor) = 'string'),
    'https://lawangproperties.com/contracts/api/send_email.php');

  perform net.http_post(
    url := v_url,
    headers := jsonb_build_object('Content-Type', 'application/json') || public._aviso_cabecera(),
    body := jsonb_build_object(
      'to', 'jcervantes@lawangproperties.com',
      'subject', p_asunto,
      'message', p_cuerpo, 'attach', false));

  insert into public.avisos_soporte_equipo (client_id, enviado_en)
    values (p_client_id, now())
  on conflict (client_id) do update set enviado_en = now();
exception when others then
  null;   -- el aviso puede fallar; el ticket/mensaje del comprador ya se guardó y no se toca
end $$;
revoke all on function public._avisar_equipo_soporte(uuid,text,text) from public, anon, authenticated;

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
  v_url text;
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

  v_url := coalesce(
    (select nullif(btrim(c.valor #>> '{}'), '') from public.config_instancia c
      where c.clave = 'url_envio_correo' and jsonb_typeof(c.valor) = 'string'),
    'https://lawangproperties.com/contracts/api/send_email.php');

  perform net.http_post(
    url := v_url,
    headers := jsonb_build_object('Content-Type', 'application/json') || public._aviso_cabecera(),
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
