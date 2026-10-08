-- destructivo-ok: reversión explícita de 20261010060000_correo_ajustes_servidor_y_codigo (8-oct-2026). Hace drop de las funciones y las dos tablas que creó esa migración (correo_codigos y correo_smtp_intentos solo guardan códigos de confirmación y contadores de intentos, nada de negocio) y borra la clave correo_salida; vuelve a dejar ajustes_config_guardar y _ajustes_claves_editables como estaban (7 claves, cuerpo de 20260930190200).
-- REVERSIÓN del correo desde Ajustes en Lawang (porte de F3.1 + F3.1b). ESCRITA, NO EJECUTADA. Se ejecuta con execute_sql o psql (lleva su propio begin/commit); NO por apply_migration.
--
-- Tres niveles, de menos a más:
--   PARTE 1 — «volver al correo de siempre» SIN deshacer la migración: `select public.correo_smtp_revierte('motivo')`. Vacía el servidor de Vault (se sobrescribe, no se borra),
--             borra config_instancia.correo_salida y deja el rastro en ajustes_log; `correo_smtp_lee()` pasa a NULL y envia-correo usa los secretos SMTP_* del entorno (plan B
--             permanente, nunca se borran). Tarda hasta 30 s en notarse (caché de envia-correo; con Vault caído, hasta 10 min con el último valor bueno).
--             Es lo único que hace falta si el problema es «el servidor que se guardó no funciona».
--   PARTE 2 — deshacer la migración entera (abajo). Antes: retirar el front nuevo y las edges `ajustes-correo` (y dejar `envia-correo` como estaba si se despliega la versión vieja),
--             porque tras esta parte sus llamadas a las RPC fallan. Orden: PARTE 1 primero (para que el correo no dependa de Vault), luego PARTE 2.
--   PARTE 3 — (opcional, a mano, no está en el script) quitar de Vault los secretos smtp_activo / smtp_previo / smtp_candidato si se quiere que la contraseña deje de estar en la base:
--             `delete from vault.secrets where name in ('smtp_activo','smtp_previo','smtp_candidato');` Solo el dueño de la base; irreversible (la contraseña vuelve a estar solo en los SMTP_*).
--
-- Al volver a 7 claves, ajustes_config_guardar vuelve a aceptar email_from y email_reply_to desde authenticated: es el comportamiento anterior, que NO envía nada
-- (envia-correo vieja solo lee los SMTP_* del entorno). Las claves email_from / email_reply_to / email_avisos_* que se hayan guardado con código se quedan en config_instancia.
--
-- Comprobación tras la PARTE 2 (solo lectura):
--   select proname from pg_proc where pronamespace = 'public'::regnamespace and (proname like 'correo\_smtp\_%' or proname like 'correo\_codigo\_%' or proname like 'correo\_ajuste\_%');   -- 0 filas
--   select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'ajustes_config_guardar';   -- 6914c051151790b47920b9abe57a2786 (el de antes de la migración)

-- ===================== PARTE 1: el correo vuelve a los SMTP_* del entorno =====================
-- select public.correo_smtp_revierte('<motivo>');   -- lo ejecuta el dueño de la base (sin EXECUTE para nadie más)

-- ===================== PARTE 2: deshacer la migración =====================
begin;
-- 2.1 Fuera las funciones nuevas (cada una con su firma)
drop function if exists public._correo_smtp_secreto(text);
drop function if exists public._correo_smtp_pon(text, jsonb, text);
drop function if exists public._correo_smtp_actor(uuid);
drop function if exists public._correo_smtp_valida(text, integer, text, text, text);
drop function if exists public.correo_smtp_guarda_candidato(uuid, text, integer, text, text, text);
drop function if exists public.correo_smtp_reauth_intento(uuid, bigint);
drop function if exists public.correo_smtp_estado();
drop function if exists public._correo_ct_igual(bytea, bytea);
drop function if exists public._correo_smtp_como(text);
drop function if exists public._correo_smtp_vuelve(text);
drop function if exists public._correo_mail_valido(text);
drop function if exists public._correo_dominio_usuario_smtp();
drop function if exists public._correo_buzon_propio(text);
drop function if exists public._correo_smtp_existe(text);
drop function if exists public._correo_codigo_comprueba(uuid, text, bytea, bytea, boolean);
drop function if exists public.correo_codigo_emite(uuid, text, bytea, bytea);
drop function if exists public.correo_codigo_verifica(uuid, text, bytea, bytea);
drop function if exists public.correo_codigo_retira(uuid, bigint);
drop function if exists public.correo_smtp_lee();
drop function if exists public._correo_smtp_activa(jsonb, text, text);
drop function if exists public.correo_smtp_promueve(uuid, text, bytea, bytea, text);
drop function if exists public.correo_smtp_descarta(uuid, text);
drop function if exists public.correo_smtp_revierte(text);
drop function if exists public.correo_ajuste_guarda(uuid, text, jsonb, bytea, bytea, text);

-- 2.2 Fuera las tablas nuevas y la copia sin secretos
drop table if exists public.correo_codigos;
drop table if exists public.correo_smtp_intentos;
delete from public.config_instancia where clave = 'correo_salida';

-- 2.3 La lista blanca y ajustes_config_guardar, como estaban (20260930190200; prosrc de la función viva el 8-oct-2026: md5 6914c051151790b47920b9abe57a2786)
create or replace function public._ajustes_claves_editables() returns text[]
  language sql immutable set search_path to ''
  as $$ select array['marca', 'logo_correo_url', 'email_from', 'email_reply_to', 'email_avisos_reservas', 'email_avisos_crm', 'zona_horaria'] $$;

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
revoke all on function public.ajustes_config_guardar(text, jsonb, text) from public, anon, service_role;
grant execute on function public.ajustes_config_guardar(text, jsonb, text) to authenticated;

commit;
