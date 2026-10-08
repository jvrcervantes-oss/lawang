-- destructivo-ok: no destruye datos de nadie. «delete» solo limpia intentos de prueba y códigos de confirmación de más de un día y, en la vuelta atrás explícita (correo_smtp_revierte, sin EXECUTE para nadie), la copia sin secretos `correo_salida`; ningún secreto de Vault se borra (se sobrescribe). Esta migración no hace drop de nada que exista hoy.
-- CORREO DESDE AJUSTES — porte a Lawang de F3.1 + F3.1b del ERP maestro (encargo encargos/20260930_erp_ajustes_pantalla.md → «S6/F3.1-Lawang», 8-oct-2026).
-- ESTADO: escrita y NO aplicada a ninguna base. Antes de aplicarla: copia restaurable de la base de Lawang (respaldo_instancia.py lawang), comparar con la base viva
-- las dos funciones que reemplaza (ajustes_config_guardar y _ajustes_claves_editables; el 8-oct su prosrc coincidía con 20260930190200: md5 6914c051…, ver
-- supabase/reversion_correo/REVERSION_correo_ajustes.sql), aplicar, `get_advisors`, y comprobar que `select public.correo_smtp_lee()` devuelve NULL (aún no hay servidor en Vault:
-- envia-correo sigue con los SMTP_* del entorno). Reversión: supabase/reversion_correo/REVERSION_correo_ajustes.sql (escrita, no ejecutada).
--
-- ES UNA MIGRACIÓN COMBINADA de las dos del maestro (erp/migraciones/20261007210000_f31_correo_smtp.sql y 20261008135000_f31b_correo_codigos.sql) en su forma FINAL: cada
-- función aparece una sola vez, con el cuerpo de su última versión en el maestro. Lo único que NO viene de ellas, con su porqué:
--   · `correo_smtp_instala` NO se porta: es del instalador de instancias nuevas (erp/nueva_instancia.py) y Lawang no se instala; sin llamador no se expone (§1.ter de seguridad_2026).
--   · No hay `drop function` de las firmas viejas del maestro (`_correo_smtp_activa(jsonb,text)`, `correo_smtp_promueve(uuid,text)`): en Lawang nunca existieron.
--   · Lawang es independiente del maestro (AXW-68): esta migración vive aquí y el maestro no la lee. erp/test_canon_ajustes.py compara cada función de aquí con su última
--     versión del maestro (mismo cuerpo, mismos permisos) para que no se separen sin avisar.
-- Cada función nueva nace CERRADA: sin EXECUTE para public, anon ni authenticated; solo service_role (las edges ajustes-correo y envia-correo) o nadie (internas, y la
-- vuelta atrás, que solo ejecuta el dueño de la base). Llamador con nombre de cada una: su `comment on function`.
--
-- QUÉ CAMBIA PARA LAWANG, en claro.
--   1. El servidor de salida del correo (SMTP del buzón de Lawang) puede vivir en Vault (secreto `smtp_activo`), escrito desde Ajustes › Correo por la edge `ajustes-correo`.
--      `envia-correo` lo lee con `correo_smtp_lee()`. Mientras no haya fila, NADA cambia: sigue con los secretos SMTP_* del entorno de la edge (que no se borran nunca: plan B).
--   2. `email_from`, `email_reply_to`, `email_avisos_soporte` y `email_avisos_sistema` SALEN de la lista blanca de `ajustes_config_guardar` (authenticated) y solo se cambian con un
--      código de 6 cifras de un solo uso enviado al correo de quien lo pide (`correo_ajuste_guarda`, service_role). Hoy `email_from` y `email_reply_to` no existen en
--      config_instancia de Lawang (medido 8-oct-2026) y `email_avisos_soporte`/`sistema` valen jcervantes@lawangproperties.com: un valor ya guardado no se invalida.
--   3. `asunto_por_defecto` (ya existe en config_instancia de Lawang) entra en la lista blanca: pasa de 7 a 6 claves editables por authenticated
--      (marca, logo_correo_url, email_avisos_reservas, email_avisos_crm, zona_horaria, asunto_por_defecto).
--   4. ⚠ EMPALME con el front: la pantalla actual de Ajustes (intranet/v4/assets/ajustes.js) escribe email_from / email_reply_to por `ajustes_config_guardar`; tras aplicar
--      esta migración esa llamada contesta «clave_no_editable» hasta que se publique el ajustes.js nuevo (commit aparte, F7). Orden: migración → edges → front.
--
-- EL DATO TIENE UN DUEÑO.
--   · Credenciales (host, puerto, usuario, contraseña, nombre): Vault, secreto `smtp_activo` (JSON). Dueño: `_correo_smtp_activa`, el único escritor. Se leen con `correo_smtp_lee()`.
--   · `smtp_candidato`: lo que se está probando; NO se usa para enviar; solo se promueve tras un envío real de prueba. `smtp_previo`: el activo de antes (volver atrás con SQL).
--   · `config_instancia.correo_salida` (host, usuario, puerto, nombre, desde cuándo y quién; SIN secretos): COPIA CONGELADA del activo para que la pantalla lea el estado sin descifrar
--     nada; se escribe en la misma transacción que el activo y nadie más. Si se contradijeran, manda Vault.
--   · email_from / email_reply_to / email_avisos_*: siguen en config_instancia; el dueño de su escritura pasa a `correo_ajuste_guarda` (con código). Dato leído por envia-correo.
--   · El código NO se guarda: se guarda su HMAC-SHA256 y el pepper vive FUERA de la base (secreto de la edge, CORREO_CODIGO_PEPPER): con la base filtrada hay 10^6 códigos y no se
--     pueden probar sin él. La «huella» (HMAC de acción + actor + todos los campos) ata el código al cambio exacto. Aquí son bytea opacos de 32 bytes.
--
-- DECISIONES (heredadas del maestro, con su porqué).
--   1. Nombres sin «smtp» en la clave de config: `_ajustes_es_sensible` redacta lo que case con /smtp|pass|…/ en ajustes_log; `correo_salida` deja host y usuario visibles en el registro.
--   2. Solo service_role ejecuta las funciones nuevas; cada una vuelve a comprobar que el actor es super admin ACTIVO (como correo_plantilla_guardar).
--   3. Límite de intentos en la base (5 por 10 min por instancia, pruebas SMTP) y contadores SEPARADOS para el código: emisión 3/hora por actor con 60 s de enfriamiento tras uno
--      anulado; fallos 5 por código. Uno solo dejaría a una sesión robada bloquear al dueño.
--   4. El servidor se valida también aquí (nombre DNS público, puerto 465): la edge ya lo hizo, pero no es la única puerta. La comprobación contra IP privadas por DNS solo la hace la edge.
--   5. Los secretos de Vault nunca se borran: se crean la primera vez y después se sobrescriben (vault.update_secret).
--   6. Un código inválido NO levanta excepción (el UPDATE del contador de fallos no se deshace): la función devuelve {codigo_no_valido:true} y la edge responde siempre el mismo error.
--   7. `email_avisos_reservas` y `email_avisos_crm` (siguen editables SIN código) cumplen la regla de buzón PROPIO (dominio_web o subdominio, dominio de email_from o del usuario SMTP
--      activo), solo si el valor cambia. Si no, una sesión robada redirigía esos avisos fuera sin código.
--   8. Vuelta atrás (`correo_smtp_revierte`): sobrescribe el activo con un valor vacío (no borra la fila de vault.secrets) y `correo_smtp_lee()` devuelve NULL → envia-correo vuelve a los SMTP_*.
--      Con la caché de envia-correo (30 s fresca; si Vault falla, el último valor bueno hasta 10 min) la vuelta tarda hasta 30 s en notarse.
--   9. Toda lectura de Vault va tras `to_regclass('vault.secrets')`: en una base sin Vault dicen «no hay servidor» en vez de romper.
--
-- Orden de despliegue (encargo, «Plan v2»): migración → edge envia-correo → edge ajustes-correo → front. Sin esta migración `ajustes-correo` contesta 502 `base_no_responde` en todo.
--
-- ══ A PARTIR DE AQUÍ, EL SQL DEL MAESTRO EN SU FORMA FINAL ══

-- ── 3. Intentos de prueba del servidor de salida (límite en la base, no en la memoria de una edge) ──────────────
create table if not exists public.correo_smtp_intentos (
  id     bigint generated always as identity primary key,
  cuando timestamptz not null default now(),
  actor  uuid not null
);
create index if not exists correo_smtp_intentos_cuando_idx on public.correo_smtp_intentos (cuando desc);
comment on table public.correo_smtp_intentos is
  'F3.1 (7-oct-2026): un renglón por cada prueba del servidor de salida del correo; sirve solo para el límite (5 en 10 min por instancia). Solo la toca correo_smtp_guarda_candidato (DEFINER); nadie más tiene permisos.';
alter table public.correo_smtp_intentos enable row level security;
revoke all on public.correo_smtp_intentos from public, anon, authenticated, service_role;

-- ── 4. Utilidades internas de Vault (sin EXECUTE para nadie: las llaman las funciones de abajo) ─────────────────
create or replace function public._correo_smtp_secreto(p_nombre text) returns jsonb
  language plpgsql security definer set search_path to ''
  as $$
declare v text;
begin
  select s.decrypted_secret into v from vault.decrypted_secrets s where s.name = p_nombre;
  if v is null or btrim(v) = '' then return null; end if;
  return v::jsonb;
end $$;
revoke all on function public._correo_smtp_secreto(text) from public, anon, authenticated, service_role;

-- Crea el secreto la primera vez y después lo SOBRESCRIBE: nunca se borra una fila de vault.secrets.
create or replace function public._correo_smtp_pon(p_nombre text, p_valor jsonb, p_desc text) returns void
  language plpgsql security definer set search_path to ''
  as $$
declare v_id uuid;
begin
  select s.id into v_id from vault.secrets s where s.name = p_nombre;
  if v_id is null then
    perform vault.create_secret(p_valor::text, p_nombre, p_desc);
  else
    perform vault.update_secret(v_id, p_valor::text, p_nombre, p_desc);
  end if;
end $$;
revoke all on function public._correo_smtp_pon(text, jsonb, text) from public, anon, authenticated, service_role;

-- el actor: super admin ACTIVO. Devuelve su correo (lo que va al registro) o lanza 42501.
create or replace function public._correo_smtp_actor(p_actor uuid) returns text
  language plpgsql security definer set search_path to ''
  as $$
declare v_email text;
begin
  select u.email into v_email from public.usuarios u where u.user_id = p_actor and u.activo and u.rol = 'super_admin';
  if not found then
    raise exception 'Cambiar el servidor de correo exige super admin.' using errcode = '42501';
  end if;
  return v_email;
end $$;
revoke all on function public._correo_smtp_actor(uuid) from public, anon, authenticated, service_role;

-- ── 5. Validar un servidor (compartida por la prueba desde Ajustes y por el instalador) ────────────────────────
-- Devuelve el servidor NORMALIZADO ({host, port, user, pass, nombre}) o lanza 22023 con un hint por campo. La edge repite estas reglas
-- (envia-correo/smtp.ts → validaServidor) para dar el error sin llegar aquí; si se cambia una, se cambia la otra (las dos tienen pruebas).
create or replace function public._correo_smtp_valida(p_host text, p_port integer, p_user text, p_pass text, p_nombre text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_host   text := lower(btrim(coalesce(p_host, '')));
  v_user   text := btrim(coalesce(p_user, ''));
  v_nombre text := btrim(coalesce(p_nombre, ''));
  v_tld    text;
begin
  -- servidor: un NOMBRE DNS público, nunca una IP ni un nombre interno (la edge además mira a qué IP resuelve)
  v_tld := substring(v_host from '\.([a-z0-9-]+)$');
  if char_length(v_host) not between 4 and 253
     or v_host !~ '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+([a-z]{2,24}|xn--[a-z0-9-]{2,20})$'
     or v_tld in ('localhost', 'local', 'internal', 'localdomain', 'lan', 'home', 'corp', 'intranet', 'private', 'arpa', 'invalid', 'test', 'example', 'onion') then
    raise exception 'El servidor tiene que ser un nombre público (como smtp.tuproveedor.com), no una IP ni un nombre interno.'
      using errcode = '22023', hint = 'host_no_valido';
  end if;
  if p_port is distinct from 465 then
    raise exception 'El puerto tiene que ser 465 (conexión cifrada): la plataforma bloquea el 25 y el 587.' using errcode = '22023', hint = 'puerto_no_valido';
  end if;
  if char_length(v_user) not between 1 and 254 or v_user ~ '[[:cntrl:]]' then
    raise exception 'El usuario del buzón va de 1 a 254 caracteres y sin caracteres de control.' using errcode = '22023', hint = 'usuario_no_valido';
  end if;
  if p_pass is null or char_length(p_pass) not between 1 and 200 or p_pass ~ '[[:cntrl:]]' then
    raise exception 'La contraseña del buzón va de 1 a 200 caracteres y sin saltos de línea.' using errcode = '22023', hint = 'clave_no_valida';
  end if;
  if char_length(v_nombre) > 60 or v_nombre ~ '[[:cntrl:]<>]' then
    raise exception 'El nombre del remitente admite 60 caracteres, sin < ni >.' using errcode = '22023', hint = 'nombre_no_valido';
  end if;
  return jsonb_build_object('host', v_host, 'port', 465, 'user', v_user, 'pass', p_pass, 'nombre', nullif(v_nombre, ''));
end $$;
revoke all on function public._correo_smtp_valida(text, integer, text, text, text) from public, anon, authenticated, service_role;

-- ── 7. Guardar el CANDIDATO (no envía nada ni cambia el activo) ──────────────────────────────────────────────────
create or replace function public.correo_smtp_guarda_candidato(
  p_actor uuid, p_host text, p_port integer, p_user text, p_pass text, p_nombre text default null)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_email  text;
  v_srv    jsonb;
  v_activo jsonb;
  v_token  text := gen_random_uuid()::text;
  v_n      integer;
begin
  if to_regclass('vault.secrets') is null then
    raise exception 'Esta instancia no tiene Vault: el servidor de correo no se puede guardar.' using errcode = '55000';
  end if;
  v_email := public._correo_smtp_actor(p_actor);
  perform pg_advisory_xact_lock(hashtext('correo_smtp'));

  -- el límite se mira ANTES de validar y el intento se anota DESPUÉS: solo cuenta lo que llega a probarse contra un servidor
  -- (un dato inválido se rechaza aquí, deshace la transacción y no toca ninguna red; lo que se quiere frenar es probar
  -- contraseñas contra el buzón del cliente)
  delete from public.correo_smtp_intentos where cuando < now() - interval '1 day';
  select count(*) into v_n from public.correo_smtp_intentos where cuando > now() - interval '10 minutes';
  if v_n >= 5 then
    raise exception 'Demasiados intentos seguidos con el servidor de correo (5 cada 10 minutos). Espera unos minutos.'
      using errcode = 'P0001', hint = 'demasiados_intentos';
  end if;
  v_srv := public._correo_smtp_valida(p_host, p_port, p_user, p_pass, p_nombre);

  insert into public.correo_smtp_intentos (actor) values (p_actor);
  select c.valor into v_activo from public.config_instancia c where c.clave = 'correo_salida';
  perform public._correo_smtp_pon('smtp_candidato', v_srv || jsonb_build_object('token', v_token, 'actor', p_actor, 'creado', now()),
    'F3.1: servidor de correo en prueba (7-oct-2026). No se usa para enviar hasta promoverlo.');
  return jsonb_build_object('token', v_token,
    'hay_activo', public._correo_smtp_existe('smtp_activo'),
    'cambia_servidor', public._correo_smtp_existe('smtp_activo')
                       and (v_activo is null or (v_activo ->> 'host') is distinct from (v_srv ->> 'host') or (v_activo ->> 'usuario') is distinct from (v_srv ->> 'user')));
end $$;
comment on function public.correo_smtp_guarda_candidato(uuid, text, integer, text, text, text) is
  'F3.1: guarda en Vault el servidor de correo CANDIDATO (smtp_candidato) tras validarlo y contar el intento (5 por 10 min). No toca el activo. Llamador ÚNICO: edge ajustes-correo (clave de servicio) con el uuid del super admin que ella verificó.';
revoke all on function public.correo_smtp_guarda_candidato(uuid, text, integer, text, text, text) from public, anon, authenticated;
grant execute on function public.correo_smtp_guarda_candidato(uuid, text, integer, text, text, text) to service_role;

-- ── 7b. Reautenticación con contraseña: cada intento cuenta en el MISMO límite (5 por 10 min) ─────────────────────
-- El intento se ANOTA ANTES de preguntarle a Auth (reserva atómica bajo el mismo candado): con una sesión robada y peticiones en paralelo,
-- anotar solo el fallo dejaría pasar todas las que llegan antes de que se escriba el primero. Si la contraseña era buena, la edge libera
-- la reserva (p_libera = el id devuelto): acertar no gasta intentos; fallar o no llegar a saber, sí.
create or replace function public.correo_smtp_reauth_intento(p_actor uuid, p_libera bigint default null)
returns bigint
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_n  integer;
  v_id bigint;
begin
  perform public._correo_smtp_actor(p_actor);
  perform pg_advisory_xact_lock(hashtext('correo_smtp'));
  if p_libera is not null then
    delete from public.correo_smtp_intentos where id = p_libera and actor = p_actor;
    return null;
  end if;
  delete from public.correo_smtp_intentos where cuando < now() - interval '1 day';
  select count(*) into v_n from public.correo_smtp_intentos where cuando > now() - interval '10 minutes';
  if v_n >= 5 then
    raise exception 'Demasiados intentos seguidos con el servidor de correo (5 cada 10 minutos). Espera unos minutos.'
      using errcode = 'P0001', hint = 'demasiados_intentos';
  end if;
  insert into public.correo_smtp_intentos (actor) values (p_actor) returning id into v_id;
  return v_id;
end $$;
comment on function public.correo_smtp_reauth_intento(uuid, bigint) is
  'F3.1: reserva un intento del límite (5 por 10 min, el mismo de correo_smtp_guarda_candidato) ANTES de comprobar la contraseña de la cuenta; con p_libera borra la reserva si la contraseña era buena. Llamador ÚNICO: edge ajustes-correo (clave de servicio).';
revoke all on function public.correo_smtp_reauth_intento(uuid, bigint) from public, anon, authenticated;
grant execute on function public.correo_smtp_reauth_intento(uuid, bigint) to service_role;

-- ── 11. El estado, SIN contraseña (lo que enseña la pantalla) ─────────────────────────────────────────────────────
create or replace function public.correo_smtp_estado()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_c jsonb;
  v_n integer;
begin
  select c.valor into v_c from public.config_instancia c where c.clave = 'correo_salida';
  select count(*) into v_n from public.correo_smtp_intentos where cuando > now() - interval '10 minutes';
  return jsonb_build_object(
    'configurado', public._correo_smtp_existe('smtp_activo'),
    'host', v_c ->> 'host', 'usuario', v_c ->> 'usuario', 'puerto', v_c -> 'puerto', 'nombre', v_c ->> 'nombre',
    'puesto_en', v_c ->> 'puesto_en', 'puesto_por', v_c ->> 'puesto_por',
    'hay_previo', public._correo_smtp_existe('smtp_previo'),
    'intentos_recientes', v_n, 'intentos_max', 5);
end $$;
comment on function public.correo_smtp_estado() is
  'F3.1: estado del servidor de correo SIN contraseña (host, usuario, desde cuándo, quién, intentos recientes). Llamador ÚNICO: edge ajustes-correo (clave de servicio).';
revoke all on function public.correo_smtp_estado() from public, anon, authenticated;
grant execute on function public.correo_smtp_estado() to service_role;

-- ── 1. La lista blanca de Ajustes para authenticated: salen las cuatro claves de correo ───────────────────────────────
create or replace function public._ajustes_claves_editables() returns text[]
  language sql immutable set search_path to ''
  as $$ select array['marca', 'logo_correo_url', 'email_avisos_reservas', 'email_avisos_crm', 'zona_horaria', 'asunto_por_defecto'] $$;

-- ── 2. Códigos de confirmación ────────────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.correo_codigos (
  id       bigint generated always as identity primary key,
  actor    uuid not null,
  alcance  text not null check (alcance in ('servidor', 'ajuste')),
  huella   bytea not null check (octet_length(huella) = 32),
  hash     bytea not null check (octet_length(hash) = 32),
  fallos   smallint not null default 0,
  estado   text not null default 'pendiente' check (estado in ('pendiente', 'usado', 'anulado', 'sustituido', 'caducado')),
  creado   timestamptz not null default now(),
  caduca   timestamptz not null default now() + interval '10 minutes',
  cambiado timestamptz
);
create index if not exists correo_codigos_actor_idx on public.correo_codigos (actor, creado desc);
comment on table public.correo_codigos is
  'F3.1b (8-oct-2026): códigos de confirmación para cambiar el correo. Guarda el HMAC del código (pepper fuera de la base), nunca el código. Un pendiente por actor. Solo la tocan las funciones correo_codigo_* y _correo_codigo_comprueba (DEFINER); nadie más tiene permisos, ni service_role.';
alter table public.correo_codigos enable row level security;
revoke all on public.correo_codigos from public, anon, authenticated, service_role;

-- ── 3. Utilidades internas (sin EXECUTE para nadie) ───────────────────────────────────────────────────────────────────────────
-- Comparación en tiempo constante de dos bytea (se recorren todos los bytes aunque el primero ya difiera).
create or replace function public._correo_ct_igual(a bytea, b bytea) returns boolean
  language plpgsql immutable set search_path to ''
  as $$
declare d integer := 0; i integer;
begin
  if a is null or b is null or octet_length(a) <> octet_length(b) then return false; end if;
  for i in 0 .. octet_length(a) - 1 loop
    d := d | (get_byte(a, i) # get_byte(b, i));
  end loop;
  return d = 0;
end $$;
revoke all on function public._correo_ct_igual(bytea, bytea) from public, anon, authenticated, service_role;

-- `quien` del registro de cambios = el actor. Devuelve las claims de antes para que `_correo_smtp_vuelve` las restituya.
create or replace function public._correo_smtp_como(p_email text) returns text
  language plpgsql set search_path to ''
  as $$
declare v_prev text := coalesce(current_setting('request.jwt.claims', true), '');
begin
  perform set_config('request.jwt.claims', jsonb_build_object('role', 'service_role', 'email', p_email)::text, true);
  return v_prev;
end $$;
revoke all on function public._correo_smtp_como(text) from public, anon, authenticated, service_role;

create or replace function public._correo_smtp_vuelve(p_prev text) returns void
  language plpgsql set search_path to ''
  as $$
begin
  perform set_config('request.jwt.claims', coalesce(p_prev, ''), true);
end $$;
revoke all on function public._correo_smtp_vuelve(text) from public, anon, authenticated, service_role;

-- ¿es un correo válido? (UNA regla para las dos RPC; la edge repite el mismo formato en MAIL_BASE y su prueba lo fija)
create or replace function public._correo_mail_valido(p_txt text) returns boolean
  language sql immutable set search_path to ''
  as $$ select p_txt is not null and char_length(p_txt) <= 254
              and p_txt ~ '^[A-Za-z0-9_%+-]+(\.[A-Za-z0-9_%+-]+)*@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}$'
              and strpos(p_txt, '@') <= 65 $$;
revoke all on function public._correo_mail_valido(text) from public, anon, authenticated, service_role;

-- El dominio del usuario del servidor SMTP ACTIVO (null si no hay servidor, no hay Vault o su usuario no es un correo).
create or replace function public._correo_dominio_usuario_smtp() returns text
  language plpgsql security definer set search_path to ''
  as $$
declare v_usr text;
begin
  if to_regclass('vault.secrets') is null then return null; end if;
  v_usr := public._correo_smtp_secreto('smtp_activo') ->> 'user';
  if v_usr is null or not public._correo_mail_valido(btrim(v_usr)) then return null; end if;
  return lower(regexp_replace(split_part(btrim(v_usr), '@', 2), '\.$', ''));
end $$;
revoke all on function public._correo_dominio_usuario_smtp() from public, anon, authenticated, service_role;

-- ¿Es PROPIO este buzón? '' = sí · 'sin_dominio_web' = no hay ningún dominio contra el que comprobarlo · 'buzon_ajeno' = es de otro dominio.
-- Propio = dominio_web (o un subdominio), dominio de email_from o dominio del usuario del servidor SMTP activo (owner, 7-oct-2026). Uno de otro dominio
-- quedaría guardado y mudo (envia-correo solo deja pasar por su vía de aviso a esos buzones) o sería una redirección de los avisos hacia fuera.
create or replace function public._correo_buzon_propio(p_txt text) returns text
  language plpgsql security definer set search_path to ''
  as $$
declare
  v_bz text := lower(regexp_replace(split_part(coalesce(p_txt, ''), '@', 2), '\.$', ''));
  v_dom text; v_dom_from text; v_dom_usr text;
begin
  select lower(regexp_replace(btrim(c.valor #>> '{}'), '\.$', '')) into v_dom
    from public.config_instancia c where c.clave = 'dominio_web' and jsonb_typeof(c.valor) = 'string';
  select lower(regexp_replace(split_part(btrim(c.valor #>> '{}'), '@', 2), '\.$', '')) into v_dom_from
    from public.config_instancia c where c.clave = 'email_from' and jsonb_typeof(c.valor) = 'string' and public._correo_mail_valido(btrim(c.valor #>> '{}'));
  v_dom_usr := public._correo_dominio_usuario_smtp();
  if coalesce(v_dom, '') = '' and coalesce(v_dom_from, '') = '' and coalesce(v_dom_usr, '') = '' then return 'sin_dominio_web'; end if;
  if (coalesce(v_dom, '') <> '' and (v_bz = v_dom or v_bz like '%.' || v_dom))
     or (coalesce(v_dom_from, '') <> '' and v_bz = v_dom_from)
     or (coalesce(v_dom_usr, '') <> '' and v_bz = v_dom_usr) then
    return '';
  end if;
  return 'buzon_ajeno';
end $$;
revoke all on function public._correo_buzon_propio(text) from public, anon, authenticated, service_role;

-- ── 3b. ajustes_config_guardar (Ajustes › lo que NO lleva código): igual que 20261007210000 sin las 4 claves de correo, y con la regla de buzón propio ──
-- para email_avisos_reservas y email_avisos_crm (solo si el valor CAMBIA: un valor ya guardado no se invalida).
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
  v_h     text;
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
  if p_clave in ('marca', 'logo_correo_url', 'email_avisos_reservas', 'email_avisos_crm', 'zona_horaria', 'asunto_por_defecto') then
    if jsonb_typeof(p_valor) <> 'string' then
      raise exception '«%» es un texto.', p_clave using errcode = '22023';
    end if;
    v_txt := btrim(p_valor #>> '{}');
    if v_txt ~ '[[:cntrl:]]' then
      raise exception '«%» no admite saltos de línea ni caracteres de control.', p_clave using errcode = '22023';
    end if;
    select c.valor into v_antes from public.config_instancia c where c.clave = p_clave;

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
    elsif p_clave in ('email_avisos_reservas', 'email_avisos_crm') then
      -- reservas: obligatorio (el maestro lo lee con config() como TEXTO, un solo correo, y lo usa de `creado_por` de la Carta de Reserva); crm: vacío = sin aviso.
      if not (p_clave = 'email_avisos_crm' and v_txt = '') and not public._correo_mail_valido(v_txt) then
        raise exception '«%» tiene que ser un correo válido%.', p_clave, case when p_clave = 'email_avisos_crm' then ' (o vacío)' else '' end using errcode = '22023';
      end if;
      -- buzón PROPIO (como soporte/sistema). Un valor que ya estaba guardado se acepta tal cual aunque hoy no cumpla: la regla es para lo que CAMBIA.
      if v_txt <> '' and not coalesce(jsonb_typeof(v_antes) = 'string' and btrim(v_antes #>> '{}') = v_txt, false) then
        v_h := public._correo_buzon_propio(v_txt);
        if v_h = 'sin_dominio_web' then
          raise exception 'Falta el dominio de la instancia (dominio_web), un email_from o un servidor de correo: sin ellos no se puede comprobar que el buzón es propio.' using errcode = '22023', hint = 'sin_dominio_web';
        elsif v_h <> '' then
          raise exception '«%» tiene que ser un buzón del dominio de la instancia, de email_from o del servidor de correo.', p_clave using errcode = '22023', hint = 'buzon_ajeno';
        end if;
      end if;
    elsif p_clave = 'asunto_por_defecto' then
      -- vacío = el de fábrica («Documento — marca»). Mismo tope que LIMITES.asunto de valida.ts (200 caracteres).
      if char_length(v_txt) > 200 then
        raise exception 'El asunto por defecto admite 200 caracteres como máximo.' using errcode = '22023';
      end if;
    elsif p_clave = 'zona_horaria' then
      if v_txt !~ '^([A-Za-z_]+(/[A-Za-z0-9_+-]+)+|UTC)$'
         or not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = v_txt) then
        raise exception 'La zona horaria no existe (formato Región/Ciudad, como Asia/Makassar).' using errcode = '22023';
      end if;
    end if;
    v_norm := to_jsonb(v_txt);
  else
    raise exception 'Ajuste sin validación: %', p_clave using errcode = '22023';
  end if;

  perform set_config('axw.ajustes_motivo', coalesce(btrim(p_motivo), ''), true);
  insert into public.config_instancia as c (clave, valor) values (p_clave, v_norm)
  on conflict (clave) do update set valor = excluded.valor, actualizado_en = now()
    where c.valor is distinct from excluded.valor;
  perform set_config('axw.ajustes_motivo', '', true);
  return jsonb_build_object('clave', p_clave, 'valor', v_norm, 'cambiado', v_antes is distinct from v_norm);
end $$;
revoke all on function public.ajustes_config_guardar(text, jsonb, text) from public, anon, service_role;
grant execute on function public.ajustes_config_guardar(text, jsonb, text) to authenticated;

-- ¿existe un servidor en ese secreto? (un valor vacío —la vuelta atrás— cuenta como que no)
create or replace function public._correo_smtp_existe(p_nombre text) returns boolean
  language plpgsql security definer set search_path to ''
  as $$
begin
  if to_regclass('vault.secrets') is null then return false; end if;
  return coalesce((public._correo_smtp_secreto(p_nombre) ->> 'host') is not null, false);
end $$;
revoke all on function public._correo_smtp_existe(text) from public, anon, authenticated, service_role;

-- La comprobación del código (UNA sola, la usan verifica, promueve y correo_ajuste_guarda). Devuelve true/false y NUNCA lanza por un
-- código malo: así el contador de fallos sobrevive. El llamador ya validó al actor y tomó el candado.
create or replace function public._correo_codigo_comprueba(p_actor uuid, p_alcance text, p_huella bytea, p_hash bytea, p_consumir boolean)
returns boolean
language plpgsql
security definer
set search_path to ''
as $$
declare
  c public.correo_codigos%rowtype;
begin
  select * into c from public.correo_codigos where actor = p_actor and estado = 'pendiente' order by id desc limit 1 for update;
  if not found then return false; end if;
  if c.caduca <= now() then
    update public.correo_codigos set estado = 'caducado', cambiado = now() where id = c.id;
    return false;
  end if;
  if c.alcance is distinct from p_alcance or not public._correo_ct_igual(c.huella, p_huella) or not public._correo_ct_igual(c.hash, p_hash) then
    update public.correo_codigos set fallos = fallos + 1,
           estado = case when fallos + 1 >= 5 then 'anulado' else estado end,
           cambiado = case when fallos + 1 >= 5 then now() else cambiado end
     where id = c.id;
    return false;
  end if;
  if p_consumir then
    update public.correo_codigos set estado = 'usado', cambiado = now() where id = c.id;
  end if;
  return true;
end $$;
revoke all on function public._correo_codigo_comprueba(uuid, text, bytea, bytea, boolean) from public, anon, authenticated, service_role;

-- ── 4. Emitir, verificar sin consumir, retirar una emisión que no llegó ───────────────────────────────────────────────────────
create or replace function public.correo_codigo_emite(p_actor uuid, p_alcance text, p_huella bytea, p_hash bytea)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_n   integer;
  v_id  bigint;
  v_cad timestamptz;
begin
  perform public._correo_smtp_actor(p_actor);
  if p_alcance is null or p_alcance not in ('servidor', 'ajuste') or p_huella is null or octet_length(p_huella) <> 32
     or p_hash is null or octet_length(p_hash) <> 32 then
    raise exception 'Código de confirmación mal formado.' using errcode = '22023', hint = 'codigo_mal_formado';
  end if;
  perform pg_advisory_xact_lock(hashtext('correo_codigo'), hashtext(p_actor::text));
  delete from public.correo_codigos where creado < now() - interval '1 day';
  if exists (select 1 from public.correo_codigos where actor = p_actor and estado = 'anulado' and cambiado > now() - interval '60 seconds') then
    raise exception 'Espera un minuto antes de pedir otro código.' using errcode = 'P0001', hint = 'codigo_enfriamiento';
  end if;
  select count(*) into v_n from public.correo_codigos where actor = p_actor and creado > now() - interval '1 hour';
  if v_n >= 3 then
    raise exception 'Demasiados códigos pedidos (3 por hora).' using errcode = 'P0001', hint = 'demasiados_codigos';
  end if;
  update public.correo_codigos set estado = 'sustituido', cambiado = now() where actor = p_actor and estado = 'pendiente';
  insert into public.correo_codigos (actor, alcance, huella, hash) values (p_actor, p_alcance, p_huella, p_hash) returning id, caduca into v_id, v_cad;
  return jsonb_build_object('id', v_id, 'caduca', v_cad);
end $$;
comment on function public.correo_codigo_emite(uuid, text, bytea, bytea) is
  'F3.1b: registra el HMAC de un código de confirmación (uno pendiente por actor; el anterior se sustituye), con límite de 3 por hora y 60 s de enfriamiento tras un código anulado. Llamador ÚNICO: edge ajustes-correo (acción pedir_codigo, clave de servicio).';
revoke all on function public.correo_codigo_emite(uuid, text, bytea, bytea) from public, anon, authenticated;
grant execute on function public.correo_codigo_emite(uuid, text, bytea, bytea) to service_role;

create or replace function public.correo_codigo_verifica(p_actor uuid, p_alcance text, p_huella bytea, p_hash bytea)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare v_ok boolean;
begin
  perform public._correo_smtp_actor(p_actor);
  perform pg_advisory_xact_lock(hashtext('correo_codigo'), hashtext(p_actor::text));
  v_ok := public._correo_codigo_comprueba(p_actor, p_alcance, p_huella, p_hash, false);
  return jsonb_build_object('valido', v_ok);
end $$;
comment on function public.correo_codigo_verifica(uuid, text, bytea, bytea) is
  'F3.1b: comprueba un código SIN consumirlo (un fallo cuenta; 5 fallos anulan el código). Llamador ÚNICO: edge ajustes-correo (acción probar_y_guardar, antes de la prueba SMTP, clave de servicio).';
revoke all on function public.correo_codigo_verifica(uuid, text, bytea, bytea) from public, anon, authenticated;
grant execute on function public.correo_codigo_verifica(uuid, text, bytea, bytea) to service_role;

-- Si el correo con el código no pudo salir por ningún servidor, la emisión no gasta cupo: se borra (solo si nadie la ha tocado).
create or replace function public.correo_codigo_retira(p_actor uuid, p_id bigint)
returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  perform public._correo_smtp_actor(p_actor);
  delete from public.correo_codigos where id = p_id and actor = p_actor and estado = 'pendiente' and fallos = 0;
end $$;
comment on function public.correo_codigo_retira(uuid, bigint) is
  'F3.1b: retira una emisión cuyo correo no pudo salir (no gasta cupo). Llamador ÚNICO: edge ajustes-correo (pedir_codigo con codigo_no_enviado, clave de servicio).';
revoke all on function public.correo_codigo_retira(uuid, bigint) from public, anon, authenticated;
grant execute on function public.correo_codigo_retira(uuid, bigint) to service_role;

-- ── 5. Servidor: leer solo si TIENE servidor; el activo previo solo si lo había; hacer activo con nota en el registro ─────────
create or replace function public.correo_smtp_lee()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare v jsonb;
begin
  if to_regclass('vault.secrets') is null then
    return null;
  end if;
  v := public._correo_smtp_secreto('smtp_activo');
  if v is null or (v ->> 'host') is null then return null; end if;   -- vacío (vuelta atrás) = «no hay servidor»
  return v;
end $$;
comment on function public.correo_smtp_lee() is
  'F3.1: el servidor de correo ACTIVO con su contraseña ({host, port, user, pass, nombre}) o NULL si no hay ninguno. Llamadores: edges envia-correo y ajustes-correo (clave de servicio). Nunca para el navegador.';
revoke all on function public.correo_smtp_lee() from public, anon, authenticated;
grant execute on function public.correo_smtp_lee() to service_role;

create or replace function public._correo_smtp_activa(p_srv jsonb, p_por text, p_nota text default null)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_act   jsonb := public._correo_smtp_secreto('smtp_activo');
  v_ahora text := to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
  v_nuevo jsonb;
  v_hay   boolean;
begin
  v_hay := v_act is not null and (v_act ->> 'host') is not null;
  if v_hay then
    perform public._correo_smtp_pon('smtp_previo', v_act, 'F3.1: servidor de correo anterior al último cambio (7-oct-2026). Solo para volver atrás con SQL.');
  end if;
  perform public._correo_smtp_pon('smtp_activo',
    jsonb_build_object('host', p_srv -> 'host', 'port', 465, 'user', p_srv -> 'user', 'pass', p_srv -> 'pass', 'nombre', p_srv -> 'nombre'),
    'F3.1: servidor de correo en uso (7-oct-2026). Lo lee correo_smtp_lee() para envia-correo.');
  v_nuevo := jsonb_build_object('host', p_srv -> 'host', 'usuario', p_srv -> 'user', 'puerto', 465, 'nombre', p_srv -> 'nombre',
                                'puesto_en', v_ahora, 'puesto_por', p_por);
  perform set_config('axw.ajustes_motivo',
    'Servidor de salida del correo (' || case when p_por = 'instalador' then 'instalador' else 'Ajustes › Correo' end || ')'
      || coalesce(' — ' || nullif(left(btrim(p_nota), 200), ''), ''), true);
  insert into public.config_instancia as c (clave, valor, descripcion)
  values ('correo_salida', v_nuevo, 'F3.1: copia SIN secretos del servidor de salida activo (la contraseña está en Vault: smtp_activo). La escribe _correo_smtp_activa.')
  on conflict (clave) do update set valor = excluded.valor, actualizado_en = now();
  perform set_config('axw.ajustes_motivo', '', true);
  return jsonb_build_object('host', v_nuevo ->> 'host', 'usuario', v_nuevo ->> 'usuario', 'puesto_en', v_ahora, 'hay_previo', v_hay);
end $$;
revoke all on function public._correo_smtp_activa(jsonb, text, text) from public, anon, authenticated, service_role;

-- ── 6. Promover: candidato → activo, SOLO con un código válido que se consume aquí ───────────────────────────────────────────
create or replace function public.correo_smtp_promueve(p_actor uuid, p_token text, p_huella bytea, p_hash bytea, p_nota text default null)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_email text;
  v_cand  jsonb;
  v_prev  text;
  v_res   jsonb;
begin
  v_email := public._correo_smtp_actor(p_actor);
  perform pg_advisory_xact_lock(hashtext('correo_smtp'));
  v_cand := public._correo_smtp_secreto('smtp_candidato');
  if v_cand is null or v_cand ->> 'host' is null or p_token is null or v_cand ->> 'token' is distinct from p_token then
    raise exception 'La prueba ya no vale (otra la ha sustituido o ya se usó). Vuelve a probar el servidor.' using errcode = '22023', hint = 'candidato_no_vigente';
  end if;
  if (v_cand ->> 'actor') is distinct from p_actor::text then
    raise exception 'Esa prueba la empezó otra persona.' using errcode = '42501', hint = 'candidato_de_otro';
  end if;
  if (v_cand ->> 'creado')::timestamptz < now() - interval '15 minutes' then
    raise exception 'La prueba caducó (15 minutos). Vuelve a probar el servidor.' using errcode = '22023', hint = 'candidato_no_vigente';
  end if;
  -- el código se comprueba y se CONSUME aquí, en la misma transacción que la promoción (si el candidato no vale, el código no se gasta)
  perform pg_advisory_xact_lock(hashtext('correo_codigo'), hashtext(p_actor::text));
  if not public._correo_codigo_comprueba(p_actor, 'servidor', p_huella, p_hash, true) then
    -- sin código válido el candidato no se queda: su contraseña no debe esperar en Vault a que alguien acierte el código (se sobrescribe, no se borra)
    perform public._correo_smtp_pon('smtp_candidato', jsonb_build_object('vacio', true), 'F3.1: sin prueba en curso.');
    return jsonb_build_object('codigo_no_valido', true);
  end if;
  -- el candidato se sobrescribe (no se borra): la contraseña deja de estar ahí
  perform public._correo_smtp_pon('smtp_candidato', jsonb_build_object('vacio', true), 'F3.1: sin prueba en curso.');
  v_prev := public._correo_smtp_como(v_email);
  v_res := public._correo_smtp_activa(v_cand, v_email, p_nota);
  perform public._correo_smtp_vuelve(v_prev);
  return v_res;
end $$;
comment on function public.correo_smtp_promueve(uuid, text, bytea, bytea, text) is
  'F3.1b: promueve el candidato (con su token) a servidor ACTIVO, consume el código de confirmación en la misma transacción, pasa el activo a previo y deja host/usuario en config_instancia.correo_salida (quien = el actor). Devuelve {codigo_no_valido:true} (y descarta el candidato) si el código no vale. Llamador ÚNICO: edge ajustes-correo, solo tras un envío de prueba correcto.';
revoke all on function public.correo_smtp_promueve(uuid, text, bytea, bytea, text) from public, anon, authenticated;
grant execute on function public.correo_smtp_promueve(uuid, text, bytea, bytea, text) to service_role;

-- Una prueba que falló: el candidato se descarta (la contraseña que no funcionó no se queda en Vault).
create or replace function public.correo_smtp_descarta(p_actor uuid, p_token text)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare v_cand jsonb;
begin
  perform public._correo_smtp_actor(p_actor);
  perform pg_advisory_xact_lock(hashtext('correo_smtp'));
  v_cand := public._correo_smtp_secreto('smtp_candidato');
  if v_cand is not null and v_cand ->> 'host' is not null and v_cand ->> 'token' is not distinct from p_token and (v_cand ->> 'actor') = p_actor::text then
    perform public._correo_smtp_pon('smtp_candidato', jsonb_build_object('vacio', true), 'F3.1: sin prueba en curso.');
  end if;
end $$;
comment on function public.correo_smtp_descarta(uuid, text) is
  'F3.1b: descarta el servidor candidato cuya prueba falló (sobrescribe, no borra). Llamador ÚNICO: edge ajustes-correo (prueba_fallida, clave de servicio).';
revoke all on function public.correo_smtp_descarta(uuid, text) from public, anon, authenticated;
grant execute on function public.correo_smtp_descarta(uuid, text) to service_role;

-- ── 7. Vuelta atrás: «ya no hay servidor en Vault» → envia-correo cae a los SMTP_* del entorno ─────────────────────────────────
-- SIN EXECUTE para nadie salvo el dueño de la base: el llamador es el SQL de servicio del estudio (contexto/seguridad_2026.md §7).
-- Una transacción: sobrescribe el activo y el candidato con un valor vacío, borra la copia sin secretos y deja el rastro en ajustes_log.
create or replace function public.correo_smtp_revierte(p_motivo text default null)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare v_hubo boolean;
begin
  if to_regclass('vault.secrets') is null then
    return jsonb_build_object('revertido', false, 'motivo', 'sin_vault');
  end if;
  perform pg_advisory_xact_lock(hashtext('correo_smtp'));
  v_hubo := public._correo_smtp_existe('smtp_activo');
  perform set_config('axw.ajustes_motivo', 'Vuelta atrás del servidor de correo: ' || left(coalesce(nullif(btrim(p_motivo), ''), 'sin motivo'), 300), true);
  if exists (select 1 from vault.secrets s where s.name = 'smtp_activo') then
    perform public._correo_smtp_pon('smtp_activo', jsonb_build_object('vacio', true), 'F3.1b: servidor de correo retirado (vuelta atrás); envia-correo usa los SMTP_* del entorno.');
  end if;
  if exists (select 1 from vault.secrets s where s.name = 'smtp_candidato') then
    perform public._correo_smtp_pon('smtp_candidato', jsonb_build_object('vacio', true), 'F3.1: sin prueba en curso.');
  end if;
  delete from public.config_instancia where clave = 'correo_salida';
  perform set_config('axw.ajustes_motivo', '', true);
  return jsonb_build_object('revertido', true, 'habia_servidor', v_hubo);
end $$;
comment on function public.correo_smtp_revierte(text) is
  'F3.1b: vuelta atrás del servidor de correo en una transacción (sobrescribe smtp_activo/candidato con un valor vacío, borra correo_salida, rastro en ajustes_log). Sin EXECUTE para nadie salvo el dueño de la base: lo lanza el SQL de servicio del estudio (runbook seguridad_2026 §7).';
revoke all on function public.correo_smtp_revierte(text) from public, anon, authenticated, service_role;

-- ── 8. Guardar uno de los cuatro ajustes de correo, con código ────────────────────────────────────────────────────────────────
-- Las mismas reglas de formato que tenía ajustes_config_guardar para estas cuatro claves (20261007210000), más: si hay servidor en Vault y su
-- usuario es un correo, email_from tiene que ser de ese dominio (la edge repite la regla con el usuario de los SMTP_* si no hay servidor en Vault).
create or replace function public.correo_ajuste_guarda(p_actor uuid, p_clave text, p_valor jsonb, p_huella bytea, p_hash bytea, p_motivo text default null)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_email text;
  v_txt   text;
  v_norm  jsonb;
  v_antes jsonb;
  v_dom_usr text;
  v_h     text;
  v_prev  text;
  v_mot   text;
begin
  v_email := public._correo_smtp_actor(p_actor);
  perform pg_advisory_xact_lock(hashtext('correo_smtp'));
  if p_clave is null or p_clave <> all (array['email_from', 'email_reply_to', 'email_avisos_sistema', 'email_avisos_soporte']) then
    raise exception 'El ajuste «%» no se cambia con código.', left(coalesce(p_clave, ''), 60) using errcode = '22023', hint = 'clave_no_editable';
  end if;
  if p_valor is null or jsonb_typeof(p_valor) <> 'string' then
    raise exception '«%» es un texto.', p_clave using errcode = '22023', hint = 'valor_no_valido';
  end if;
  if p_motivo is not null and char_length(p_motivo) > 300 then
    raise exception 'El motivo admite 300 caracteres como máximo.' using errcode = '22023', hint = 'motivo_no_valido';
  end if;
  v_txt := btrim(p_valor #>> '{}');
  if v_txt ~ '[[:cntrl:]]' then
    raise exception '«%» no admite saltos de línea ni caracteres de control.', p_clave using errcode = '22023', hint = 'valor_no_valido';
  end if;
  if p_clave = 'email_reply_to' then
    if v_txt <> '' and not public._correo_mail_valido(v_txt) then
      raise exception '«%» tiene que ser un correo válido (o vacío).', p_clave using errcode = '22023', hint = 'valor_no_valido';
    end if;
  else
    if not public._correo_mail_valido(v_txt) then
      raise exception '«%» tiene que ser un correo válido.', p_clave using errcode = '22023', hint = 'valor_no_valido';
    end if;
    if p_clave = 'email_from' then
      v_dom_usr := public._correo_dominio_usuario_smtp();   -- null si no hay servidor en Vault (o no hay Vault): entonces la edge ya comprobó contra SMTP_USER
      if coalesce(v_dom_usr, '') <> '' and lower(regexp_replace(split_part(v_txt, '@', 2), '\.$', '')) <> v_dom_usr then
        raise exception 'El remitente tiene que ser del dominio del buzón del servidor de correo.' using errcode = '22023', hint = 'from_ajeno';
      end if;
    else
      v_h := public._correo_buzon_propio(v_txt);
      if v_h = 'sin_dominio_web' then
        raise exception 'Falta el dominio de la instancia (dominio_web), un email_from o un servidor de correo: sin ellos no se puede comprobar que el buzón es propio.' using errcode = '22023', hint = 'sin_dominio_web';
      elsif v_h <> '' then
        raise exception '«%» tiene que ser un buzón del dominio de la instancia, de email_from o del servidor de correo.', p_clave using errcode = '22023', hint = 'buzon_ajeno';
      end if;
    end if;
  end if;
  v_norm := to_jsonb(v_txt);

  -- el código se comprueba y se CONSUME aquí (un valor inválido ya se rechazó arriba sin gastarlo)
  perform pg_advisory_xact_lock(hashtext('correo_codigo'), hashtext(p_actor::text));
  if not public._correo_codigo_comprueba(p_actor, 'ajuste', p_huella, p_hash, true) then
    return jsonb_build_object('codigo_no_valido', true);
  end if;

  select c.valor into v_antes from public.config_instancia c where c.clave = p_clave;
  v_mot := 'Confirmado con código' || coalesce(' — ' || nullif(btrim(p_motivo), ''), '');
  v_prev := public._correo_smtp_como(v_email);
  perform set_config('axw.ajustes_motivo', v_mot, true);
  insert into public.config_instancia as c (clave, valor) values (p_clave, v_norm)
  on conflict (clave) do update set valor = excluded.valor, actualizado_en = now()
    where c.valor is distinct from excluded.valor;
  perform set_config('axw.ajustes_motivo', '', true);
  perform public._correo_smtp_vuelve(v_prev);
  return jsonb_build_object('clave', p_clave, 'valor', v_norm, 'cambiado', v_antes is distinct from v_norm);
end $$;
comment on function public.correo_ajuste_guarda(uuid, text, jsonb, bytea, bytea, text) is
  'F3.1b: escribe email_from, email_reply_to, email_avisos_sistema o email_avisos_soporte tras validar el valor y consumir el código de confirmación, en una transacción (quien del registro = el actor). Devuelve {codigo_no_valido:true} si el código no vale. Llamador ÚNICO: edge ajustes-correo (acción guardar_ajuste, clave de servicio).';
revoke all on function public.correo_ajuste_guarda(uuid, text, jsonb, bytea, bytea, text) from public, anon, authenticated;
grant execute on function public.correo_ajuste_guarda(uuid, text, jsonb, bytea, bytea, text) to service_role;
