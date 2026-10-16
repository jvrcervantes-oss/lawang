-- MCP de Lawang · F1-P1 · base del puente (16-oct-2026, sesión mcp-lawang).
-- Encargo: encargos/20261015_erp_mcp.md (agencia), «Construcción F1» y filas «Lawang F1-P*». Diseño: puente B' v2, «el token
-- se resuelve en la base, sin ninguna sesión guardada» (owner, 16-oct ~10:40: «mejor hacernos el mcp interno y no usar el de
-- supabase»). Revisiones previas #393, #394 y #395 (Seguridad + Backend), incorporadas.
--
-- QUÉ CONSTRUYE (solo construye: no toca Auth, ni edges, ni nada existente; NO abre nada a anon — eso va aparte en
-- supabase/propuestas/20261016140000_mcp_f1_abre_conexion.sql, parada del owner: fuera de migrations/ hasta su OK):
--   1. Rol `ia_puente_rol` NOLOGIN NOINHERIT NOBYPASSRLS. Es dueño de las tablas ia_* y de las funciones del puente, y de nada
--      más: es la ÚNICA pieza que actúa como una persona (fija sus claims y llama a una mcp_* de lista cerrada). Sin escritura
--      fuera de ia_*. Llamador con nombre: la edge `mcp` (vía public.ia_puente) y la página de conexión de la intranet.
--   2. Tablas ia_ajustes, ia_clientes, ia_permisos, ia_uso, ia_llamadas, ia_peticiones, ia_conexiones, ia_tokens. RLS activa,
--      sin policies y sin grants a anon/authenticated: solo las tocan funciones DEFINER de ia_puente_rol (su dueño).
--   3. Ayudantes de postgres, estrechos y con EXECUTE solo a ia_puente_rol: privado.ia_auth_usuario (lee auth.users y factores
--      MFA; NO escribe en auth) y privado.ia_aleatorio (32 bytes de pgcrypto).
--   4. privado.mcp_puerta / privado.mcp_cierra: encendido, cliente activo, permiso, usuario activo, sin ban, contraseña sin
--      cambiar desde que se conectó, 7 días, tope diario con contador atómico, y registro en ia_llamadas. Una denegación
--      DEVUELVE el resultado y confirma la transacción (no lanza: el registro se perdería). Sin EXECUTE para nadie: las llaman
--      las puertas privado.mcp_<x> de P2, con dueño postgres, que las alcanza por pertenencia a ia_puente_rol.
--   5. public.ia_puente(accion, datos): la entrada de la edge. pide · deniega (la persona dice «no»: access_denied) · canjea (PKCE S256 dentro de la base) · refresca (rotación,
--      reuso = revoca) · revoca · comprueba · llama (fija claims del usuario y despacha). Los tokens llegan EN CLARO y se
--      convierten en hash aquí (un hash de un volcado no sirve para llamar). Rechaza GET y cualquier `Prefer: tx=`.
--   6. public.ia_conexion_autoriza(peticion) y public.ia_conexion_revoca(conexion): RPC de authenticated (la primera la llama la
--      edge con la sesión RECIÉN creada por la página de conexión, y su EXECUTE lo da la propuesta 140000 con el OK del owner;
--      la segunda, «apps conectadas» y Ajustes, ya aquí).
--   7. privado.ia_despacha: STUB que P2 (20261016120000_mcp_f1_p2_herramientas.sql) sustituye por la lista CASE literal.
--   8. privado.ia_purga() y su cron diario: borra peticiones y tokens caducados. ia_llamadas NO se purga aquí: su retención la
--      fijan Legal y el owner (fila en el encargo).
--
-- DUEÑO DEL DATO («El dato tiene un dueño», contexto/patrones_tecnicos.md):
--   ia_ajustes, ia_clientes, ia_permisos: el super admin, desde Ajustes › IA (P4). El resto lo escribe solo el puente.
--   ia_conexiones.usuario_id / ia_permisos.usuario_id → public.usuarios(user_id) por id. ia_clientes.id es el client_id
--   público del asistente. La huella de contraseña es una COPIA congelada al conectar (sha256 del hash de Auth + ban): si cambia,
--   la conexión se revoca en la siguiente llamada (#395, punto 7).
--
-- VUELTA ATRÁS: supabase/reversion_mcp/vuelta_atras_p1.sql (destructiva: drop de lo creado aquí; con filas en ia_llamadas
-- PARA y pregunta). Apagar sin borrar: `update public.ia_ajustes set encendido = false` (lo hace el super admin en Ajustes).

set lock_timeout = '5s';

-- ── 1. Rol ────────────────────────────────────────────────────────────────────────────────────────────────────────────────
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'ia_puente_rol') then
    create role ia_puente_rol nologin noinherit nobypassrls;
  end if;
end $$;
alter role ia_puente_rol nologin noinherit nobypassrls nocreatedb nocreaterole noreplication;
grant ia_puente_rol to postgres with inherit true, set true;
grant usage on schema public to ia_puente_rol;
grant usage on schema privado to ia_puente_rol;   -- lw_lector NO: el invariante «lw_lector es un lector» de salud_lawang (patas d/e)
-- CREATE solo mientras se cambian dueños (ALTER OWNER exige CREATE del nuevo dueño en el esquema); se revoca al final.
grant create on schema public to ia_puente_rol;
grant create on schema privado to ia_puente_rol;

-- ── 2. Tablas ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
create table public.ia_ajustes (
  id              boolean primary key default true check (id),
  encendido       boolean not null default false,
  -- 0 = nadie llama hasta que el super admin fije el tope (el estudio no inventa la cifra: plan F0 §4)
  tope_dia        integer not null default 0 check (tope_dia between 0 and 5000),
  -- owner, 15-oct ~21:50: «una conexión dura 7 días»
  duracion_dias   integer not null default 7 check (duracion_dias between 1 and 30),
  max_conexiones  integer not null default 2 check (max_conexiones between 1 and 10),
  -- la dirección del recurso MCP (RFC 8707): la de la edge de este proyecto
  recurso         text not null default 'https://vtulllundrfennhjddhc.supabase.co/functions/v1/mcp'
                  check (recurso ~ '^https://[a-z0-9.-]+/[A-Za-z0-9/_-]*$'),
  actualizado_por uuid references public.usuarios(user_id) on delete set null,
  actualizado_en  timestamptz not null default now()
);
insert into public.ia_ajustes default values on conflict do nothing;

create table public.ia_clientes (
  id            uuid primary key default gen_random_uuid(),
  asistente     text not null check (asistente in ('claude', 'chatgpt')),
  nombre        text not null check (length(nombre) between 1 and 60),
  redirect_uris text[] not null check (cardinality(redirect_uris) between 1 and 3),
  activo        boolean not null default false,
  creado_por    uuid references public.usuarios(user_id) on delete set null,
  creado_en     timestamptz not null default now()
);

create table public.ia_permisos (
  usuario_id    uuid primary key references public.usuarios(user_id) on delete cascade,
  concedido_por uuid references public.usuarios(user_id) on delete set null,
  concedido_en  timestamptz not null default now()
);

create table public.ia_uso (
  usuario_id uuid not null references public.usuarios(user_id) on delete cascade,
  dia        date not null,
  n          integer not null default 0,
  primary key (usuario_id, dia)
);

create table public.ia_peticiones (
  id_hash        bytea primary key,
  cliente_id     uuid not null references public.ia_clientes(id) on delete cascade,
  redirect_uri   text not null,
  code_challenge text not null check (code_challenge ~ '^[A-Za-z0-9_-]{43}$'),
  recurso        text not null,
  estado         text check (length(estado) <= 500),
  creado_en      timestamptz not null default now(),
  caduca_en      timestamptz not null default now() + interval '5 minutes',
  usada_en       timestamptz
);
create index ia_peticiones_caduca on public.ia_peticiones (caduca_en);
create index ia_peticiones_cliente on public.ia_peticiones (cliente_id);

create table public.ia_conexiones (
  id              uuid primary key default gen_random_uuid(),
  usuario_id      uuid not null references public.usuarios(user_id) on delete cascade,
  cliente_id      uuid not null references public.ia_clientes(id) on delete cascade,
  recurso         text not null,
  huella          text not null,
  aal             text not null check (aal in ('aal1', 'aal2')),
  creada_en       timestamptz not null default now(),
  expira_en       timestamptz not null,
  revocada_en     timestamptz,
  revocada_motivo text check (revocada_motivo in ('persona', 'admin', 'asistente', 'reuso_codigo', 'reuso_refresco',
                                                  'contrasena', 'permiso', 'apagado', 'usuario_inactivo', 'cliente'))
);
-- índices sin filtro: también los usa la cascada al borrar a la persona o al cliente (Base de datos, 16-oct)
create index ia_conexiones_usuario on public.ia_conexiones (usuario_id);
create index ia_conexiones_cliente on public.ia_conexiones (cliente_id);

create table public.ia_tokens (
  hash           bytea primary key,
  conexion_id    uuid not null references public.ia_conexiones(id) on delete cascade,
  tipo           text not null check (tipo in ('codigo', 'acceso', 'refresco')),
  code_challenge text check (code_challenge is null or code_challenge ~ '^[A-Za-z0-9_-]{43}$'),
  redirect_uri   text,
  creado_en      timestamptz not null default now(),
  caduca_en      timestamptz not null,
  usado_en       timestamptz,
  sustituido_por bytea
);
create index ia_tokens_conexion on public.ia_tokens (conexion_id);
create index ia_tokens_caduca on public.ia_tokens (caduca_en);

create table public.ia_llamadas (
  id          bigint generated always as identity primary key,
  conexion_id uuid references public.ia_conexiones(id) on delete set null,
  usuario_id  uuid,   -- sin-fk-ok: registro de auditoría; quién consultó sobrevive al borrado de la persona (Base de datos, 16-oct)
  herramienta text not null check (length(herramienta) <= 60),
  argumentos  jsonb not null default '{}'::jsonb check (pg_column_size(argumentos) <= 2048),
  resultado   text not null check (resultado in ('ok', 'sin_conexion', 'caducada', 'revocada', 'apagado', 'cliente',
                                                 'permiso', 'usuario_inactivo', 'contrasena', 'tope', 'sin_permiso',
                                                 'argumento_invalido', 'error')),
  filas       integer,
  ms          integer,
  creado_en   timestamptz not null default now()
);
create index ia_llamadas_usuario on public.ia_llamadas (usuario_id, creado_en desc);
create index ia_llamadas_creado on public.ia_llamadas (creado_en);
create index ia_llamadas_conexion on public.ia_llamadas (conexion_id, creado_en);   -- «Apps conectadas» (ia_mis_conexiones) y la cascada

-- Cerradas a todos: el GRANT por defecto de Supabase da ALL a anon/authenticated en cada tabla nueva (lección 14-sep).
do $$
declare t text;
begin
  foreach t in array array['ia_ajustes', 'ia_clientes', 'ia_permisos', 'ia_uso', 'ia_peticiones', 'ia_conexiones',
                           'ia_tokens', 'ia_llamadas'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on table public.%I from public, anon, authenticated, service_role', t);
    execute format('alter table public.%I owner to ia_puente_rol', t);
  end loop;
end $$;
revoke all on sequence public.ia_llamadas_id_seq from public, anon, authenticated, service_role;

-- ── 3. Ayudantes de postgres (estrechos; EXECUTE solo a ia_puente_rol) ─────────────────────────────────────────────────────
create or replace function privado.ia_aleatorio()
returns bytea
language sql
volatile
security definer
set search_path = ''
as $$ select extensions.gen_random_bytes(32) $$;
alter function privado.ia_aleatorio() owner to postgres;
revoke all on function privado.ia_aleatorio() from public, anon, authenticated, service_role;
grant execute on function privado.ia_aleatorio() to ia_puente_rol;

-- Lo que el puente necesita de Auth, sin darle grants en `auth`. Solo lee.
create or replace function privado.ia_auth_usuario(p_uid uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
           'email', u.email,
           'app_metadata', coalesce(u.raw_app_meta_data, '{}'::jsonb),
           'baneado', coalesce(u.banned_until > now(), false),
           'huella', encode(sha256(convert_to(coalesce(u.encrypted_password, '') || '|' || coalesce(u.banned_until::text, ''), 'UTF8')), 'hex'),
           'factores', (select count(*) from auth.mfa_factors f where f.user_id = u.id and f.status = 'verified'),
           'activo', coalesce((select x.activo from public.usuarios x where x.user_id = u.id), false))
    from auth.users u
   where u.id = p_uid
$$;
alter function privado.ia_auth_usuario(uuid) owner to postgres;
revoke all on function privado.ia_auth_usuario(uuid) from public, anon, authenticated, service_role;
grant execute on function privado.ia_auth_usuario(uuid) to ia_puente_rol;

grant execute on function public.uid_sesion() to ia_puente_rol;
grant execute on function public.es_super_admin() to ia_puente_rol;

-- ── 4. Utilidades del puente (dueño ia_puente_rol) ──────────────────────────────────────────────────────────────────────────
create or replace function privado.ia_b64url(p bytea)
returns text
language sql
immutable
set search_path = ''
as $$ select rtrim(translate(encode(p, 'base64'), E'+/\n', '-_'), '=') $$;

create or replace function privado.ia_hash(p text)
returns bytea
language sql
immutable
set search_path = ''
as $$ select sha256(convert_to(coalesce(p, ''), 'UTF8')) $$;

-- Un token nuevo de 256 bits: lo devuelve en claro UNA vez; la base guarda solo su hash.
create or replace function privado.ia_token_nuevo(p_conexion uuid, p_tipo text, p_caduca timestamptz,
                                                  p_challenge text default null, p_redirect text default null)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare v text := privado.ia_b64url(privado.ia_aleatorio());
begin
  insert into public.ia_tokens (hash, conexion_id, tipo, caduca_en, code_challenge, redirect_uri)
  values (privado.ia_hash(v), p_conexion, p_tipo, p_caduca, p_challenge, p_redirect);
  return v;
end $$;

create or replace function privado.ia_revoca(p_conexion uuid, p_motivo text)
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  update public.ia_conexiones set revocada_en = now(), revocada_motivo = p_motivo
   where id = p_conexion and revocada_en is null;
  update public.ia_tokens set caduca_en = least(caduca_en, now()) where conexion_id = p_conexion;
$$;

-- ¿Por qué NO vale hoy esta conexión? null = vale. Lo usan la puerta, refresca, canjea y comprueba: una sola regla.
-- Revoca de paso lo que es definitivo (contraseña cambiada, permiso quitado, usuario inactivo, cliente apagado).
create or replace function privado.ia_conexion_motivo(p_conexion uuid)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare c public.ia_conexiones; a public.ia_ajustes; u jsonb;
begin
  select * into c from public.ia_conexiones where id = p_conexion;
  if c.id is null then return 'sin_conexion'; end if;
  if c.revocada_en is not null then return 'revocada'; end if;
  if c.expira_en <= now() then return 'caducada'; end if;
  select * into a from public.ia_ajustes where id;
  if not coalesce(a.encendido, false) then return 'apagado'; end if;
  if not exists (select 1 from public.ia_clientes k where k.id = c.cliente_id and k.activo) then
    perform privado.ia_revoca(c.id, 'cliente'); return 'cliente';
  end if;
  if not exists (select 1 from public.ia_permisos p where p.usuario_id = c.usuario_id) then
    perform privado.ia_revoca(c.id, 'permiso'); return 'permiso';
  end if;
  u := privado.ia_auth_usuario(c.usuario_id);
  if u is null or not coalesce((u ->> 'activo')::boolean, false) or coalesce((u ->> 'baneado')::boolean, true) then
    perform privado.ia_revoca(c.id, 'usuario_inactivo'); return 'usuario_inactivo';
  end if;
  if (u ->> 'huella') is distinct from c.huella then
    perform privado.ia_revoca(c.id, 'contrasena'); return 'contrasena';
  end if;
  return null;
end $$;

-- ── 5. La puerta común (la llaman las mcp_*) ───────────────────────────────────────────────────────────────────────────────
create or replace function privado.mcp_puerta(p_herramienta text, p_argumentos jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_txt text := nullif(current_setting('axw.ia_conexion', true), '');
  v_con uuid; v_uid uuid := public.uid_sesion(); v_res text; v_n integer; v_id bigint; v_tope integer;
begin
  if v_txt ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then v_con := v_txt::uuid; end if;
  if v_con is null or v_uid is null
     or not exists (select 1 from public.ia_conexiones c where c.id = v_con and c.usuario_id = v_uid) then
    v_res := 'sin_conexion';
  else
    v_res := coalesce(privado.ia_conexion_motivo(v_con), 'ok');
  end if;
  if v_res = 'ok' then
    select tope_dia into v_tope from public.ia_ajustes where id;
    insert into public.ia_uso (usuario_id, dia, n) values (v_uid, (now() at time zone 'Asia/Makassar')::date, 1)
    on conflict (usuario_id, dia) do update set n = public.ia_uso.n + 1
    returning n into v_n;
    if v_n > coalesce(v_tope, 0) then v_res := 'tope'; end if;
  end if;
  insert into public.ia_llamadas (conexion_id, usuario_id, herramienta, argumentos, resultado)
  values (case when v_res = 'sin_conexion' then null else v_con end,
          -- con conexión, v_uid es su usuario_id (el de la conexión); sin ella, el uid de los claims no se apunta (ia_puente_rol no lee usuarios)
          case when v_res = 'sin_conexion' then null else v_uid end,
          left(coalesce(p_herramienta, ''), 60),
          case when pg_column_size(coalesce(p_argumentos, '{}'::jsonb)) <= 2048 then coalesce(p_argumentos, '{}'::jsonb)
               else jsonb_build_object('recortado', true) end,
          v_res)
  returning id into v_id;
  return jsonb_build_object('ok', v_res = 'ok', 'resultado', v_res, 'llamada', v_id);
end $$;

create or replace function privado.mcp_cierra(p_llamada bigint, p_filas integer, p_resultado text default 'ok')
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  update public.ia_llamadas
     set filas = greatest(coalesce(p_filas, 0), 0),
         ms = (extract(epoch from clock_timestamp() - creado_en) * 1000)::integer,
         resultado = case when p_resultado in ('sin_permiso', 'argumento_invalido') then p_resultado else resultado end
   where id = p_llamada and filas is null
     and conexion_id::text = nullif(current_setting('axw.ia_conexion', true), '')
$$;

-- STUB: P2 lo sustituye por la lista CASE literal de herramientas (nunca format()/EXECUTE sobre el nombre).
create or replace function privado.ia_despacha(p_herramienta text, p_args jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  return jsonb_build_object('error', 'herramienta_desconocida');
end $$;

-- ── 6. La entrada de la edge ──────────────────────────────────────────────────────────────────────────────────────────────
-- Errores con nombre de OAuth (invalid_request, invalid_grant, invalid_client…) para que la edge los traduzca tal cual.
-- Lo que revoca por reuso DEVUELVE (no lanza): si lanzara, la revocación se desharía.
create or replace function public.ia_puente(p_accion text, p_datos jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  d jsonb := coalesce(p_datos, '{}'::jsonb);
  h jsonb; a public.ia_ajustes; t public.ia_tokens; hijo public.ia_tokens; c public.ia_conexiones; p public.ia_peticiones;
  v text; v_motivo text; v_acc text; v_ref text; u jsonb; v_res jsonb; v_cli uuid; v_vivas integer;
begin
  -- Solo POST (un GET de PostgREST corre en transacción de solo lectura: el registro no se escribiría) y sin `Prefer: tx=`
  -- (si el hosting dejara deshacer la transacción, la llamada saldría sin registro ni tope: #394/#395).
  if coalesce(current_setting('request.method', true), '') <> 'POST' then
    raise exception 'ia_puente: solo POST' using errcode = '42501';
  end if;
  h := coalesce(nullif(current_setting('request.headers', true), ''), '{}')::jsonb;
  if coalesce(h ->> 'prefer', '') ~* 'tx\s*=' then
    raise exception 'ia_puente: Prefer tx no admitido' using errcode = '42501';
  end if;
  if pg_column_size(d) > 4096 or jsonb_typeof(d) <> 'object' then
    return jsonb_build_object('error', 'invalid_request');
  end if;
  select * into a from public.ia_ajustes where id;

  if p_accion = 'pide' then
    -- Escritura sin token: se valida TODO antes del INSERT y hay tope global de peticiones vivas (#395, punto 5).
    if not coalesce(a.encendido, false) then return jsonb_build_object('error', 'temporarily_unavailable'); end if;
    if coalesce(d ->> 'cliente_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      return jsonb_build_object('error', 'invalid_client');
    end if;
    v_cli := (d ->> 'cliente_id')::uuid;
    if not exists (select 1 from public.ia_clientes k where k.id = v_cli and k.activo) then
      return jsonb_build_object('error', 'invalid_client');
    end if;
    if not exists (select 1 from public.ia_clientes k where k.id = v_cli and (d ->> 'redirect_uri') = any (k.redirect_uris)) then
      return jsonb_build_object('error', 'invalid_redirect_uri');
    end if;
    if coalesce(d ->> 'code_challenge_method', '') <> 'S256' or coalesce(d ->> 'code_challenge', '') !~ '^[A-Za-z0-9_-]{43}$' then
      return jsonb_build_object('error', 'invalid_request', 'detalle', 'PKCE S256');
    end if;
    if (d ->> 'recurso') is distinct from a.recurso then return jsonb_build_object('error', 'invalid_target'); end if;
    -- tope por cliente (100) y global (400): quien llene las de un asistente no bloquea al otro (revisor, 16-oct). Llenarlas
    -- sigue siendo posible con el client_id público; caducan en 5 min y la purga diaria las borra.
    select count(*) into v_vivas from public.ia_peticiones where caduca_en > now() and usada_en is null and cliente_id = v_cli;
    if v_vivas >= 100 then return jsonb_build_object('error', 'temporarily_unavailable'); end if;
    select count(*) into v_vivas from public.ia_peticiones where caduca_en > now() and usada_en is null;
    if v_vivas >= 400 then return jsonb_build_object('error', 'temporarily_unavailable'); end if;
    v := privado.ia_b64url(privado.ia_aleatorio());
    insert into public.ia_peticiones (id_hash, cliente_id, redirect_uri, code_challenge, recurso, estado)
    values (privado.ia_hash(v), v_cli, d ->> 'redirect_uri', d ->> 'code_challenge', a.recurso, left(d ->> 'estado', 500));
    return jsonb_build_object('peticion', v);

  elsif p_accion = 'deniega' then
    -- La persona dice «no» (o no puede) en la página de conexión: el asistente recibe error=access_denied (RFC 6749 §4.1.2.1)
    -- en vez de esperar a que caduque. Gasta la petición; la dirección de vuelta es la que se validó en `pide`.
    select * into p from public.ia_peticiones where id_hash = privado.ia_hash(d ->> 'peticion') for update;
    if p.id_hash is null or p.usada_en is not null or p.caduca_en <= now() then
      return jsonb_build_object('error', 'peticion_invalida');
    end if;
    update public.ia_peticiones set usada_en = now() where id_hash = p.id_hash;
    return jsonb_build_object('redirect_uri', p.redirect_uri, 'state', p.estado);

  elsif p_accion = 'canjea' then
    select * into t from public.ia_tokens where hash = privado.ia_hash(d ->> 'codigo') and tipo = 'codigo';
    if t.hash is null then return jsonb_build_object('error', 'invalid_grant'); end if;
    if t.usado_en is not null then
      perform privado.ia_revoca(t.conexion_id, 'reuso_codigo');            -- un código repetido revoca lo que salió de él
      return jsonb_build_object('error', 'invalid_grant');
    end if;
    if t.caduca_en <= now() then return jsonb_build_object('error', 'invalid_grant'); end if;
    select * into c from public.ia_conexiones where id = t.conexion_id;
    if (d ->> 'cliente_id') is distinct from c.cliente_id::text or (d ->> 'redirect_uri') is distinct from t.redirect_uri
       or (d ->> 'recurso') is distinct from c.recurso then
      return jsonb_build_object('error', 'invalid_grant');
    end if;
    if coalesce(d ->> 'code_verifier', '') !~ '^[A-Za-z0-9._~-]{43,128}$'
       or privado.ia_b64url(sha256(convert_to(d ->> 'code_verifier', 'UTF8'))) is distinct from t.code_challenge then
      return jsonb_build_object('error', 'invalid_grant');
    end if;
    update public.ia_tokens set usado_en = now() where hash = t.hash and usado_en is null;
    if not found then return jsonb_build_object('error', 'invalid_grant'); end if;   -- dos canjes a la vez: gana uno
    v_motivo := privado.ia_conexion_motivo(c.id);
    if v_motivo is not null then return jsonb_build_object('error', 'invalid_grant'); end if;
    v_acc := privado.ia_token_nuevo(c.id, 'acceso', least(now() + interval '1 hour', c.expira_en));
    v_ref := privado.ia_token_nuevo(c.id, 'refresco', c.expira_en);
    return jsonb_build_object('access_token', v_acc, 'refresh_token', v_ref, 'token_type', 'Bearer',
                              'expires_in', greatest(1, extract(epoch from least(interval '1 hour', c.expira_en - now()))::integer));

  elsif p_accion = 'refresca' then
    select * into t from public.ia_tokens where hash = privado.ia_hash(d ->> 'refresh_token') and tipo = 'refresco'
       for update;
    if t.hash is null then return jsonb_build_object('error', 'invalid_grant'); end if;
    select * into c from public.ia_conexiones where id = t.conexion_id;
    if (d ->> 'cliente_id') is distinct from c.cliente_id::text then return jsonb_build_object('error', 'invalid_grant'); end if;
    if t.usado_en is not null then
      -- Reintento del asistente tras un timeout (≤10 s): solo vale si el hijo existe y sigue SIN usar; se mata y se da par
      -- nuevo (nunca se guarda un token en claro: #395). Un hijo ya usado, o un token sin hijo (uno matado por un reintento),
      -- es reúso: se revoca la conexión entera. Así nunca hay dos cadenas vivas (Seguridad, 16-oct).
      select * into hijo from public.ia_tokens where hash = t.sustituido_por for update;
      if t.usado_en > now() - interval '10 seconds' and hijo.hash is not null and hijo.usado_en is null then
        update public.ia_tokens set caduca_en = least(caduca_en, now()), usado_en = now() where hash = hijo.hash;
      else
        perform privado.ia_revoca(c.id, 'reuso_refresco');
        return jsonb_build_object('error', 'invalid_grant');
      end if;
    elsif t.caduca_en <= now() then
      return jsonb_build_object('error', 'invalid_grant');
    end if;
    v_motivo := privado.ia_conexion_motivo(c.id);
    if v_motivo is not null then return jsonb_build_object('error', 'invalid_grant'); end if;
    v_acc := privado.ia_token_nuevo(c.id, 'acceso', least(now() + interval '1 hour', c.expira_en));
    v_ref := privado.ia_token_nuevo(c.id, 'refresco', c.expira_en);
    update public.ia_tokens set usado_en = coalesce(usado_en, now()), sustituido_por = privado.ia_hash(v_ref) where hash = t.hash;
    return jsonb_build_object('access_token', v_acc, 'refresh_token', v_ref, 'token_type', 'Bearer',
                              'expires_in', greatest(1, extract(epoch from least(interval '1 hour', c.expira_en - now()))::integer));

  elsif p_accion = 'revoca' then
    select * into t from public.ia_tokens where hash = privado.ia_hash(d ->> 'token') and tipo in ('acceso', 'refresco');
    if t.hash is not null then perform privado.ia_revoca(t.conexion_id, 'asistente'); end if;
    return jsonb_build_object('ok', true);                                   -- RFC 7009: siempre 200

  elsif p_accion in ('comprueba', 'llama') then
    select * into t from public.ia_tokens where hash = privado.ia_hash(d ->> 'access_token') and tipo = 'acceso';
    if t.hash is null or t.caduca_en <= now() then return jsonb_build_object('error', 'invalid_token'); end if;
    select * into c from public.ia_conexiones where id = t.conexion_id;
    if (d ->> 'recurso') is distinct from c.recurso then return jsonb_build_object('error', 'invalid_token'); end if;
    v_motivo := privado.ia_conexion_motivo(c.id);
    if v_motivo is not null then return jsonb_build_object('error', 'invalid_token', 'motivo', v_motivo); end if;
    if p_accion = 'comprueba' then return jsonb_build_object('ok', true); end if;
    -- La persona, tal como la ve Lawang: claims nuevos Y formato antiguo (auth.uid() lee PRIMERO request.jwt.claim.sub; #395).
    u := privado.ia_auth_usuario(c.usuario_id);
    perform set_config('request.jwt.claims',
                       jsonb_build_object('sub', c.usuario_id, 'email', u ->> 'email', 'role', 'authenticated',
                                          'app_metadata', u -> 'app_metadata', 'aal', c.aal)::text, true);
    perform set_config('request.jwt.claim.sub', c.usuario_id::text, true);
    perform set_config('request.jwt.claim.email', coalesce(u ->> 'email', ''), true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('axw.ia_conexion', c.id::text, true);
    begin
      v_res := privado.ia_despacha(d ->> 'herramienta', coalesce(d -> 'argumentos', '{}'::jsonb));
    exception when others or query_canceled then
      -- La herramienta lanzó (o el tiempo de la API la cortó): su fila de ia_llamadas y el contador del tope se deshicieron con
      -- ella. Se apuntan aquí: si no, forzar errores daría llamadas sin rastro y fuera del tope (revisor, 16-oct).
      insert into public.ia_llamadas (conexion_id, usuario_id, herramienta, argumentos, resultado)
      -- argumentos '{}': aquí aún no están tipados (texto libre del asistente); solo las puertas de P2 guardan los suyos, ya
      -- tipados (Base de datos, 16-oct: «argumentos (solo ids)» del encargo)
      values (c.id, c.usuario_id, left(coalesce(d ->> 'herramienta', ''), 60), '{}'::jsonb, 'error');
      insert into public.ia_uso (usuario_id, dia, n) values (c.usuario_id, (now() at time zone 'Asia/Makassar')::date, 1)
      on conflict (usuario_id, dia) do update set n = public.ia_uso.n + 1;
      v_res := jsonb_build_object('error', 'server_error');
    end;
    perform set_config('axw.ia_conexion', '', true);
    return v_res;
  end if;
  return jsonb_build_object('error', 'invalid_request');
end $$;

-- ── 7. RPC de la persona (authenticated) ──────────────────────────────────────────────────────────────────────────────────
-- La llama la edge `mcp` con la sesión RECIÉN creada en la página de conexión (contraseña puesta otra vez); la edge hace el 302
-- y el JavaScript de la intranet no ve el código. El PKCE NO protege aquí: quien llama a `pide` elige el verificador, así que
-- un tercero con la sesión de la persona podría pedir y autorizar su propia conexión. La barrera real es la contraseña puesta
-- hace ≤120 s (y el segundo factor si lo tiene). Ojo: la conexión sobrevive a cerrar sesión, a «cerrar todas las sesiones» y
-- a cambios de MFA (la huella solo cubre contraseña y baneo); por eso el aviso por correo de cada conexión nueva es condición
-- para abrir el puente (Seguridad, 16-oct; pendientes).
create or replace function public.ia_conexion_autoriza(p_peticion text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  cl jsonb := coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb;
  v_uid uuid := public.uid_sesion(); a public.ia_ajustes; p public.ia_peticiones; u jsonb; v_ts numeric;
  v_con uuid; v_cod text; v_vivas integer;
begin
  if v_uid is null then raise exception 'Sin sesión' using errcode = '42501'; end if;
  if nullif(current_setting('axw.ia_conexion', true), '') is not null then
    raise exception 'No disponible' using errcode = '42501';
  end if;
  -- Frescura por el método `password` del amr (no por iat: un refresh lo renueva sin contraseña; #395).
  select max((x ->> 'timestamp')::numeric) into v_ts
    from jsonb_array_elements(case when jsonb_typeof(cl -> 'amr') = 'array' then cl -> 'amr' else '[]'::jsonb end) x
   where x ->> 'method' = 'password';
  if v_ts is null or v_ts < extract(epoch from now()) - 120 then
    return jsonb_build_object('error', 'contrasena_no_reciente');
  end if;
  select * into a from public.ia_ajustes where id;
  if not coalesce(a.encendido, false) then return jsonb_build_object('error', 'apagado'); end if;
  if not exists (select 1 from public.ia_permisos x where x.usuario_id = v_uid) then
    return jsonb_build_object('error', 'sin_permiso');
  end if;
  u := privado.ia_auth_usuario(v_uid);
  if u is null or not coalesce((u ->> 'activo')::boolean, false) or coalesce((u ->> 'baneado')::boolean, true) then
    return jsonb_build_object('error', 'usuario_inactivo');
  end if;
  if coalesce((u ->> 'factores')::integer, 0) > 0 and coalesce(cl ->> 'aal', '') <> 'aal2' then
    return jsonb_build_object('error', 'falta_segundo_factor');
  end if;
  select * into p from public.ia_peticiones where id_hash = privado.ia_hash(p_peticion) for update;
  if p.id_hash is null or p.usada_en is not null or p.caduca_en <= now() then
    return jsonb_build_object('error', 'peticion_invalida');
  end if;
  if not exists (select 1 from public.ia_clientes k where k.id = p.cliente_id and k.activo) then
    return jsonb_build_object('error', 'cliente');
  end if;
  select count(*) into v_vivas from public.ia_conexiones x
   where x.usuario_id = v_uid and x.revocada_en is null and x.expira_en > now();
  if v_vivas >= a.max_conexiones then return jsonb_build_object('error', 'demasiadas_conexiones'); end if;
  update public.ia_peticiones set usada_en = now() where id_hash = p.id_hash;
  insert into public.ia_conexiones (usuario_id, cliente_id, recurso, huella, aal, expira_en)
  values (v_uid, p.cliente_id, p.recurso, u ->> 'huella', case when cl ->> 'aal' = 'aal2' then 'aal2' else 'aal1' end,
          now() + make_interval(days => a.duracion_dias))
  returning id into v_con;
  v_cod := privado.ia_token_nuevo(v_con, 'codigo', now() + interval '60 seconds', p.code_challenge, p.redirect_uri);
  return jsonb_build_object('redirect_uri', p.redirect_uri, 'code', v_cod, 'state', p.estado);
end $$;

-- «Apps conectadas» (la persona, lo suyo) y Ajustes (el super admin, cualquiera).
create or replace function public.ia_conexion_revoca(p_conexion uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare v_uid uuid := public.uid_sesion(); v_dueno uuid;
begin
  if v_uid is null then raise exception 'Sin sesión' using errcode = '42501'; end if;
  select usuario_id into v_dueno from public.ia_conexiones where id = p_conexion;
  if v_dueno is null then return jsonb_build_object('error', 'no_existe'); end if;
  if v_dueno = v_uid then
    perform privado.ia_revoca(p_conexion, 'persona');
  elsif public.es_super_admin() then
    perform privado.ia_revoca(p_conexion, 'admin');
  else
    raise exception 'No puedes revocar esta conexión' using errcode = '42501';
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- ── 8. Purga diaria de lo operativo (no de ia_llamadas) ────────────────────────────────────────────────────────────────────
create or replace function privado.ia_purga()
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  delete from public.ia_peticiones where caduca_en < now() - interval '1 day';
  delete from public.ia_tokens where caduca_en < now() - interval '1 day';
$$;

-- ── 9. Dueños y permisos (default-deny: cada EXECUTE con su llamador) ──────────────────────────────────────────────────────
do $$
declare f text;
begin
  foreach f in array array['privado.ia_b64url(bytea)', 'privado.ia_hash(text)',
                           'privado.ia_token_nuevo(uuid,text,timestamptz,text,text)', 'privado.ia_revoca(uuid,text)',
                           'privado.ia_conexion_motivo(uuid)', 'privado.mcp_puerta(text,jsonb)',
                           'privado.mcp_cierra(bigint,integer,text)', 'privado.ia_despacha(text,jsonb)',
                           'public.ia_puente(text,jsonb)', 'public.ia_conexion_autoriza(text)',
                           'public.ia_conexion_revoca(uuid)', 'privado.ia_purga()'] loop
    execute format('alter function %s owner to ia_puente_rol', f);
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f);
  end loop;
end $$;
-- la puerta y el cierre: sin grants; las puertas privado.mcp_<x> de P2 (dueño postgres) los alcanzan por pertenencia a ia_puente_rol
-- «apps conectadas»: revocar lo suyo (llamador: intranet/v4/assets/ia-conexiones.js)
grant execute on function public.ia_conexion_revoca(uuid) to authenticated;
-- public.ia_puente (anon) y public.ia_conexion_autoriza (authenticated): SIN grant aquí. Su único llamador es la edge `mcp` y la
-- página ia/conectar/, que salen juntas con el OK del owner: los abre supabase/propuestas/20261016140000_mcp_f1_abre_conexion.sql
-- (Seguridad, 16-oct: nada expuesto sin llamador vivo).

revoke create on schema public from ia_puente_rol;
revoke create on schema privado from ia_puente_rol;

-- Purga diaria (03:17 UTC). pg_cron corre como postgres: ejecuta la función de por sí. En una rama de ensayo sin pg_cron no se
-- programa (la viva sí lo tiene: 13 trabajos, medido el 16-oct).
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('ia-purga-diaria', '17 3 * * *', 'select privado.ia_purga()');
  end if;
end $$;
