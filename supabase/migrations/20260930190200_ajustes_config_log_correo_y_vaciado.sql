-- destructivo-ok: no destruye nada. «truncate» aparece solo en un REVOKE (se le quita a service_role el permiso de vaciar la tabla).
-- AJUSTES DEL ERP · S1 (revisión de código, 30-sep-2026): dos hallazgos menores de /code-review sobre 20260930190000.
--   1. El patrón de correo dejaba pasar `.a@x.com`, `a.@x.com` y `a..b@x.com` (SMTP los rechazaría después): la parte local
--      son grupos de caracteres separados por UN punto. Su longitud (64) se mira aparte.
--   2. `TRUNCATE public.config_instancia` (service_role tiene ALL desde antes) borraba toda la configuración sin dejar fila en
--      ajustes_log, contra lo que dice la cabecera («cualquier escritura deja rastro»). Se le quita ese permiso a service_role;
--      vaciarla queda para el propietario de la base, no para una sesión de la aplicación.
-- Pareja: erp/migraciones/20260930190200_ajustes_config_log_correo_y_vaciado.sql (maestro). Los cuerpos son idénticos; esta migración no nombra al rol lector.
create or replace function public.ajustes_config_guardar(p_clave text, p_valor jsonb, p_motivo text default null)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_txt   text;
  v_norm  jsonb;
  v_antes jsonb;
  v_mail  constant text := '^[A-Za-z0-9_%+-]+(\.[A-Za-z0-9_%+-]+)*@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}$';
begin
  if not public.es_super_admin() then
    raise exception 'Cambiar los ajustes exige super admin.' using errcode = '42501';
  end if;
  if p_clave is null or p_clave <> all (public._ajustes_claves_editables()) then
    raise exception 'El ajuste «%» no se edita desde Ajustes.', left(coalesce(p_clave, ''), 60)
      using errcode = '22023', hint = 'clave_no_editable';
  end if;
  if p_valor is null or p_valor = 'null'::jsonb then
    raise exception 'Falta el valor de «%».', p_clave using errcode = '22023';
  end if;
  if p_motivo is not null and char_length(p_motivo) > 500 then
    raise exception 'El motivo admite 500 caracteres como máximo.' using errcode = '22023';
  end if;

  if p_clave in ('marca', 'logo_correo_url', 'email_from', 'email_reply_to', 'email_avisos_reservas', 'email_avisos_crm', 'zona_horaria') then
    if jsonb_typeof(p_valor) <> 'string' then
      raise exception '«%» es un texto.', p_clave using errcode = '22023';
    end if;
    v_txt := btrim(p_valor #>> '{}');
    if v_txt ~ '[[:cntrl:]]' then
      raise exception '«%» no admite saltos de línea ni caracteres de control.', p_clave using errcode = '22023';
    end if;
    if p_clave = 'marca' then
      if char_length(v_txt) not between 1 and 60 or v_txt ~ '[<>]' then
        raise exception 'El nombre del ERP va de 1 a 60 caracteres y sin < ni >.' using errcode = '22023';
      end if;
    elsif p_clave = 'logo_correo_url' then
      -- vacío = sin logo. Si hay, https y nada raro: acaba dentro de un <img src> de cada correo.
      if v_txt <> '' and (char_length(v_txt) > 500
          or v_txt !~ '^https://[A-Za-z0-9.-]+(:[0-9]{2,5})?(/[A-Za-z0-9._~%/+@:-]*)?(\?[A-Za-z0-9._~%/+=&@:-]*)?$') then
        raise exception 'El logo del correo es una dirección https:// sin espacios ni comillas (o vacía).' using errcode = '22023';
      end if;
    elsif p_clave in ('email_from', 'email_avisos_reservas') then
      -- obligatorios: el maestro los lee con config() como TEXTO (un solo correo) para el remitente y como `creado_por`
      -- de la Carta de Reserva del Investor Deck; una lista o un vacío romperían esos llamadores.
      if char_length(v_txt) > 254 or v_txt !~ v_mail or strpos(v_txt, '@') > 65 then
        raise exception '«%» tiene que ser un correo válido.', p_clave using errcode = '22023';
      end if;
    elsif p_clave in ('email_reply_to', 'email_avisos_crm') then
      if v_txt <> '' and (char_length(v_txt) > 254 or v_txt !~ v_mail or strpos(v_txt, '@') > 65) then
        raise exception '«%» tiene que ser un correo válido (o vacío).', p_clave using errcode = '22023';
      end if;
    else -- zona_horaria
      if v_txt !~ '^([A-Za-z_]+(/[A-Za-z0-9_+-]+)+|UTC)$'
         or not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = v_txt) then
        raise exception 'La zona horaria no existe (formato Región/Ciudad, como Asia/Makassar).' using errcode = '22023';
      end if;
    end if;
    v_norm := to_jsonb(v_txt);
  else
    raise exception 'Ajuste sin validación: %', p_clave using errcode = '22023';
  end if;

  select c.valor into v_antes from public.config_instancia c where c.clave = p_clave;
  perform set_config('axw.ajustes_motivo', coalesce(btrim(p_motivo), ''), true);
  insert into public.config_instancia as c (clave, valor) values (p_clave, v_norm)
  on conflict (clave) do update set valor = excluded.valor, actualizado_en = now()
    where c.valor is distinct from excluded.valor;
  perform set_config('axw.ajustes_motivo', '', true);
  return jsonb_build_object('clave', p_clave, 'valor', v_norm, 'cambiado', v_antes is distinct from v_norm);
end $$;

revoke truncate on public.config_instancia from service_role;
