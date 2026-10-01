-- AJUSTES DEL ERP · S5.0 (subtarea 2): sembrar config_instancia con lo que la edge `envia-correo` exige y repuntar
-- las dos funciones SQL que mandan correo por pg_net. 30-sep-2026. Encargo: encargos/20260930_erp_ajustes_pantalla.md.
--
-- Comportamiento NEUTRO: hoy nadie lee estas claves salvo las funciones de abajo, que caen al mismo literal del PHP.
--   1. Siembra (`on conflict do nothing`: no pisa nada). `valor` es un jsonb de TEXTO (la edge hace `typeof valor === 'string'`).
--      NO se siembran `marca` (alimenta el título del ERP en Ajustes) ni `logo_correo_url` (no cambiarían nada).
--      Ninguna de estas claves entra en `_ajustes_claves_editables()`: `url_envio_correo` es el interruptor de vuelta atrás
--      y no puede quedar al alcance de un admin desde la pantalla. Lo exige la prueba prueba_config_envio.sql.
--   2. `_avisar_equipo_soporte` y `revisar_almacenamiento`: la URL, antes literal, se lee de
--      config_instancia.url_envio_correo y, si falta, está vacía o no es texto, cae al literal del PHP (no depende del orden
--      de migraciones). Lo demás del cuerpo es idéntico al vigente en producción (verificado con pg_get_functiondef).
-- Tras aplicar: proacl solo postgres+service_role, search_path vacío, get_advisors(security).

insert into public.config_instancia (clave, valor, descripcion) values
  ('dominio_web',          to_jsonb('lawangproperties.com'::text),
     'Dominio de la web/intranet: pie y buzones admin@/sales@ de los correos. No editable desde Ajustes.'),
  ('url_intranet',         to_jsonb('https://lawangproperties.com'::text),
     'Origen de la intranet: único origen CORS de envia-correo. No editable desde Ajustes.'),
  ('url_envio_correo',     to_jsonb('https://lawangproperties.com/contracts/api/send_email.php'::text),
     'A dónde mandan correo las funciones SQL (y, más adelante, las edges y el panel). Hoy el PHP; interruptor de vuelta atrás. No editable desde Ajustes.'),
  ('email_avisos_soporte', to_jsonb('jcervantes@lawangproperties.com'::text),
     'Buzón de los avisos de soporte (antes escrito a fuego en _avisar_equipo_soporte). No editable desde Ajustes.'),
  ('email_avisos_sistema', to_jsonb('jcervantes@lawangproperties.com'::text),
     'Buzón de los avisos del sistema (antes escrito a fuego en revisar_almacenamiento). No editable desde Ajustes.'),
  ('asunto_por_defecto',   to_jsonb('Contrato — Lawang Tropical Properties'::text),
     'Asunto cuando un envío no trae uno (lo que ponía el PHP). No editable desde Ajustes.')
on conflict (clave) do nothing;

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
    headers := '{"Content-Type":"application/json"}'::jsonb,
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
