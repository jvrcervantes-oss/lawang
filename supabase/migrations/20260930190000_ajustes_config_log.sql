-- destructivo-ok: no destruye nada. «truncate/update/delete» aparecen solo en un REVOKE y en el trigger que IMPIDE tocar ajustes_log.
-- AJUSTES DEL ERP · S1: config_instancia editable con lista blanca + registro de cambios (ajustes_log). 30-sep-2026.
-- Encargo: encargos/20260930_erp_ajustes_pantalla.md (S1). Revisión previa 30-sep (Seguridad, Datos, Legal). Owner: «el ERP se suelta
-- algún día y no tenemos que estar detrás»: el nombre del ERP, el remitente de los correos y los buzones de aviso dejan de estar
-- en el código y pasan a una pantalla que solo cambia el super admin.
-- Pareja: erp/migraciones/20260930190000_ajustes_config_log.sql (maestro, dueño erp_lector). Los CUERPOS (tablas, funciones, triggers) son IDÉNTICOS en las dos; solo cambia el último bloque,
-- que nombra al rol lector de cada base (Lawang: lw_lector · maestro: erp_lector). tools de comparación: erp/test_canon_ajustes.py.
--
-- Qué hay antes (verificado en Lawang el 30-sep con list_tables): `config_instancia` NO existía; en el maestro existe con esta misma
-- forma y solo service_role la toca. Aquí se crea con `if not exists` (en el maestro no hace nada).
--
-- El dato tiene un dueño: cada valor de `config_instancia` es de la instancia (una fila por clave); nadie más lo copia. El texto de
-- `ajustes_log.antes/despues` SÍ es copia congelada a propósito: es el rastro de lo que valía en ese instante.
--
-- Decisiones, con su porqué:
--   1. Lista blanca CERRADA (`_ajustes_claves_editables`). Nunca un «set clave/valor» genérico: `config_instancia` también guarda
--      `modulos_activos`, la url de Supabase, los topes del CRM… que no son cosa de esta pantalla. Una clave fuera de la lista se
--      rechaza en servidor (22023), no en la pantalla.
--   2. Solo escribe el super admin, y lo comprueba la RPC (42501), no el navegador. Leen los admins (solo lectura).
--   3. La tabla queda cerrada al navegador (sin grants para authenticated). El navegador lee por `*_datos` con dueño lector, que
--      hereda la RLS; escribe por `ajustes_config_guardar`. Cada pieza tiene un llamador con nombre (intranet/v4/ajustes/).
--   4. `ajustes_log` es solo-añadir: un trigger impide UPDATE, DELETE y TRUNCATE incluso al super admin (42501). Lo alimenta un
--      trigger sobre `config_instancia`, así que cualquier escritura (RPC, service_role, SQL) deja rastro. Valores de claves
--      sensibles (smtp, contraseñas, tokens…) se guardan redactados: el log dice QUE cambió, no el secreto.
--      Límite honesto: quien tenga `session_replication_role = replica` (postgres) se salta los triggers; eso es el propietario
--      de la base, no una sesión de la aplicación.
--   5. `quien` sale del correo del JWT (`_quien_actua`, el mismo que `parametro_set`); sin sesión, `sistema:<rol>`.
--   6. `sociedades_log` no se toca: tiene su propia historia y su propio llamador.
--   7. Formato compatible con lo que YA existe en el maestro (verificado en su línea base y en la edge envia-correo): `marca`,
--      `zona_horaria`, `logo_correo_url` y los buzones `email_avisos_*` son TEXTO y los leen `config()` y la edge tal cual; por eso
--      cada buzón guarda UN correo (no una lista) y los obligatorios no aceptan vacío. `email_from`, `email_reply_to` y
--      `email_avisos_crm` son claves nuevas que hoy no lee nadie (el remitente sale de SMTP_FROM): la pantalla lo dice.
--   8. `parametros` (Reservas) ya tenía su RPC de super admin; el mismo trigger la registra en ajustes_log (tabla='parametros').

-- ── 1. config_instancia (forma del maestro) ──────────────────────────────────────────────────────────────────────
create table if not exists public.config_instancia (
  clave          text primary key,
  valor          jsonb not null,
  descripcion    text,
  actualizado_en timestamptz not null default now(),
  constraint config_instancia_modulos_activos_lista check (clave <> 'modulos_activos' or jsonb_typeof(valor) = 'array')
);
alter table public.config_instancia enable row level security;
revoke all on public.config_instancia from public, anon, authenticated;
grant all on public.config_instancia to service_role;

-- ── 2. La lista blanca ───────────────────────────────────────────────────────────────────────────────────────────
create or replace function public._ajustes_claves_editables() returns text[]
  language sql immutable set search_path to ''
  as $$ select array['marca', 'logo_correo_url', 'email_from', 'email_reply_to', 'email_avisos_reservas', 'email_avisos_crm', 'zona_horaria'] $$;
revoke all on function public._ajustes_claves_editables() from public, anon, authenticated;
grant execute on function public._ajustes_claves_editables() to service_role;

create or replace function public._ajustes_es_sensible(p_clave text) returns boolean
  language sql immutable set search_path to ''
  as $$ select coalesce(p_clave ~* '(smtp|pass|secret|token|api_?key|privad|credencial|_key$)', false) $$;
revoke all on function public._ajustes_es_sensible(text) from public, anon, authenticated;
grant execute on function public._ajustes_es_sensible(text) to service_role;

-- ── 3. El registro de cambios (solo se añade) ────────────────────────────────────────────────────────────────────
create table if not exists public.ajustes_log (
  id      bigint generated always as identity primary key,
  tabla   text not null,
  clave   text not null,
  antes   jsonb,
  despues jsonb,
  motivo  text check (char_length(motivo) <= 500),
  quien   text not null,
  cuando  timestamptz not null default now()
);
create index if not exists ajustes_log_cuando_idx on public.ajustes_log (cuando desc, id desc);
comment on table public.ajustes_log is
  'Registro de cambios de Ajustes (30-sep-2026): quién, cuándo, antes y después. Solo se añade (trigger). Lo escribe el trigger de config_instancia; lo lee solo el super admin por ajustes_log_datos().';
alter table public.ajustes_log enable row level security;
revoke all on public.ajustes_log from public, anon, authenticated;
-- service_role solo lee (backups): el trigger de inmutabilidad no es la única cerradura
revoke all on public.ajustes_log from service_role;
grant select on public.ajustes_log to service_role;

create or replace function public._trg_ajustes_log_inmutable() returns trigger
  language plpgsql set search_path to ''
  as $$
begin
  raise exception 'ajustes_log es un registro: no se modifica ni se borra.' using errcode = '42501', hint = 'ajustes_log_inmutable';
end $$;
revoke all on function public._trg_ajustes_log_inmutable() from public, anon, authenticated;
create or replace trigger ajustes_log_inmutable before update or delete on public.ajustes_log
  for each row execute function public._trg_ajustes_log_inmutable();
create or replace trigger ajustes_log_sin_truncate before truncate on public.ajustes_log
  for each statement execute function public._trg_ajustes_log_inmutable();

create or replace function public._trg_ajustes_log() returns trigger
  language plpgsql security definer set search_path to ''
  as $$
declare
  v_clave text;
  v_sens  boolean;
  v_antes jsonb;
  v_desp  jsonb;
begin
  -- en un DELETE `new` no está asignado: se lee según la operación, no con coalesce(new.x, old.x)
  v_clave := case when tg_op = 'DELETE' then old.clave else new.clave end;
  if tg_op = 'UPDATE' and new.valor is not distinct from old.valor then return null; end if;
  v_sens  := public._ajustes_es_sensible(v_clave);
  v_antes := case when tg_op = 'INSERT' then null when v_sens then to_jsonb('[redactado]'::text) else old.valor end;
  v_desp  := case when tg_op = 'DELETE' then null when v_sens then to_jsonb('[redactado]'::text) else new.valor end;
  insert into public.ajustes_log (tabla, clave, antes, despues, motivo, quien)
  values (tg_table_name, v_clave, v_antes, v_desp,
          nullif(left(coalesce(current_setting('axw.ajustes_motivo', true), ''), 500), ''),
          coalesce(public._quien_actua(),
                   'sistema:' || coalesce(nullif((nullif(current_setting('request.jwt.claims', true), '')::jsonb) ->> 'role', ''), 'sql')));
  return null;
end $$;
revoke all on function public._trg_ajustes_log() from public, anon, authenticated;
create or replace trigger config_instancia_log after insert or update or delete on public.config_instancia
  for each row execute function public._trg_ajustes_log();
-- `parametros` (plazos y topes de las Cartas de Reserva) ya existía con su propia RPC de super admin (parametro_set): su
-- pestaña de Ajustes tiene que dejar el mismo rastro. Misma forma (clave, valor) en Lawang y en el maestro.
create or replace trigger parametros_log after insert or update or delete on public.parametros
  for each row execute function public._trg_ajustes_log();

-- ── 4. Escribir: una clave de la lista, validada, solo super admin ───────────────────────────────────────────────
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
  v_mail  constant text := '^[A-Za-z0-9._%+-]{1,64}@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}$';
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
      if char_length(v_txt) > 254 or v_txt !~ v_mail then
        raise exception '«%» tiene que ser un correo válido.', p_clave using errcode = '22023';
      end if;
    elsif p_clave in ('email_reply_to', 'email_avisos_crm') then
      if v_txt <> '' and (char_length(v_txt) > 254 or v_txt !~ v_mail) then
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

-- ── 5. Leer (dueño lector: heredan la RLS) ───────────────────────────────────────────────────────────────────────
create or replace function public.ajustes_config_datos() returns jsonb
language plpgsql stable security definer set search_path to ''
as $$
begin
  if public.uid_sesion() is null then
    raise exception 'ajustes_config_datos: sin sesión' using errcode = '42501';
  end if;
  if not public.es_admin() then
    raise exception 'Los ajustes son de administración.' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'editables', to_jsonb(public._ajustes_claves_editables()),
    'puede_escribir', public.es_super_admin(),
    'valores', coalesce((select jsonb_object_agg(c.clave, c.valor) from public.config_instancia c
                          where c.clave = any (public._ajustes_claves_editables())), '{}'::jsonb),
    'actualizado', coalesce((select jsonb_object_agg(c.clave, c.actualizado_en) from public.config_instancia c
                              where c.clave = any (public._ajustes_claves_editables())), '{}'::jsonb));
end $$;

create or replace function public.ajustes_log_datos(p_limit integer default 100) returns jsonb
language plpgsql stable security definer set search_path to ''
as $$
declare
  v_lim  int := least(greatest(coalesce(p_limit, 100), 1), 500);
  v_filas jsonb;
  v_mas  boolean;
begin
  if public.uid_sesion() is null then
    raise exception 'ajustes_log_datos: sin sesión' using errcode = '42501';
  end if;
  if not public.es_super_admin() then
    raise exception 'El registro de cambios lo ve solo el super admin.' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'tabla', x.tabla, 'clave', x.clave, 'antes', x.antes,
                                               'despues', x.despues, 'motivo', x.motivo, 'quien', x.quien, 'cuando', x.cuando)
                            order by x.id desc) filter (where x.rn <= v_lim), '[]'::jsonb),
         coalesce(bool_or(x.rn > v_lim), false)
    into v_filas, v_mas
    from (select l.*, row_number() over (order by l.id desc) as rn
            from public.ajustes_log l order by l.id desc limit v_lim + 1) x;
  return jsonb_build_object('filas', v_filas, 'hay_mas', v_mas);
end $$;

-- ── 6. Lector: dueño de las lecturas, con su grant y su policy (único bloque que difiere entre Lawang y el maestro) ──
grant create on schema public to lw_lector;
alter function public.ajustes_config_datos() owner to lw_lector;
alter function public.ajustes_log_datos(integer) owner to lw_lector;
revoke create on schema public from lw_lector;
revoke all on function public.ajustes_config_datos() from public, anon, service_role;
revoke all on function public.ajustes_log_datos(integer) from public, anon, service_role;
grant execute on function public.ajustes_config_datos() to authenticated;
grant execute on function public.ajustes_log_datos(integer) to authenticated;

grant select on public.config_instancia to lw_lector;
grant select on public.ajustes_log to lw_lector;
grant execute on function public._ajustes_claves_editables() to lw_lector;
do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'config_instancia'
                  and policyname = 'config_instancia: ajustes al lector') then
    create policy "config_instancia: ajustes al lector" on public.config_instancia for select to lw_lector
      using (public.es_admin() and clave = any (public._ajustes_claves_editables()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'ajustes_log'
                  and policyname = 'ajustes_log: leer solo super') then
    create policy "ajustes_log: leer solo super" on public.ajustes_log for select to lw_lector
      using (public.es_super_admin());
  end if;
end $$;
