-- destructivo-ok: solo construye (7 tablas nuevas, columnas nuevas en lead_notas y lead_accion, funciones nuevas, un create or replace de bot_lead_upsert con la misma firma). Las unicas apariciones de «truncate» son triggers BEFORE TRUNCATE que BLOQUEAN el vaciado de los logs y de bot_config; no se borra ni se vacia nada. Reversion: supabase/reversion_bot_sin_redis_s1/REVERSION.sql.
-- ============================================================================
-- LAWANG — BOT SIN REDIS: EL ESTADO DEL BOT VIVE EN POSTGRES — S1 (9-oct-2026)
-- ----------------------------------------------------------------------------
-- Encargo: encargos/20261009_lawang_bot_sin_redis.md, subtarea S1 (revision previa #239: Seguridad, Datos, Desarrollo).
-- ADITIVA: tablas, columnas, funciones y triggers NUEVOS + un create or replace de bot_lead_upsert (misma firma, solo gana la
-- referencia bot_chat.lead_id). No toca Redis ni el bot: hasta S4b nadie llama a nada de esto.
--
-- EL DATO TIENE UN DUEÑO (patrones_tecnicos.md):
--   · nombre del lead, notas, resumenes, citas, etapa       -> dueño: el ERP (leads, lead_notas, lead_accion). El bot las toca solo por bot_lead_*.
--   · bot_chat / bot_mensaje / bot_wamid / bot_escalacion   -> dueño: el bot. Estado OPERATIVO de la conversacion (pausa, baja, aviso, memoria).
--   · bot_chat.lead_id                                      -> REFERENCIA, no copia. Solo la fija bot_lead_upsert; si el telefono casa con mas de
--                                                              un lead queda NULA (no se adivina).
--   · bot_config                                            -> dueño: el ERP. El bot solo la LEE (dentro de bot_turno_estado). La escribira
--                                                              lawang-bot-proxy (S3) con el permiso bot_configurar.
--
-- LLAMADORES CON NOMBRE (seguridad_2026 §1.ter — lo nuevo nace cerrado). Todas las funciones: SECURITY DEFINER + search_path fijo,
-- REVOKE de PUBLIC/anon/authenticated/service_role, EXECUTE solo para bot_lawang (la edge `bot-api`, S2):
--   ruta /estado:       bot_mensaje_recibir · bot_turno_estado · bot_turno_cerrar · bot_eco_operadora · bot_pausar · bot_baja ·
--                       bot_entrega_fallida · bot_escalar · bot_escalacion_tomar (EXCEPCION 1) · bot_lead_resumen
--   ruta /recordatorio: bot_citas_recordar (EXCEPCION 2) · bot_cita_recordatorio_res
--   ruta /humano:       bot_pausar_humano · bot_envio_humano  (el usuario sale del JWT que reenvia el proxy; aqui llega como p_usuario)
--   sin EXECUTE para nadie (internas): _bot_tel · _bot_limpia · _bot_media · _bot_pausa_humana · _bot_conversaciones_autoriza y los triggers.
--   Las tablas no dan ningun privilegio a nadie: RLS activa, sin policies (el INFO `rls_enabled_no_policy` es lo buscado).
--
-- LO QUE ESTA MIGRACION NO HACE (otras subtareas, a proposito):
--   · purga (365 d / 24 m / bot_wamid / logs) y crm_bot_olvidar y su pg_cron       -> S7
--   · funcion que ESCRIBE bot_config (permiso, expectedUpdatedAt)                   -> S3 (aqui solo la tabla y su log automatico)
--   · funciones que LEEN conversaciones para la intranet                            -> S10 (aqui solo el permiso `bot_conversaciones_ver`
--                                                                                       y la tabla de lecturas, via _bot_conversaciones_autoriza)
--   · importar Redis                                                                -> S5
--
-- DESVIACIONES FRENTE A LA TABLA DE «Lista cerrada» DEL ENCARGO (las ve el CEO en el informe):
--   1. bot_lead_resumen recibe el TELEFONO (no un lead): el lead sale de bot_chat.lead_id, el bot no conoce ids de lead.
--   2. bot_turno_cerrar no recibe «ultimo mensaje»: lo deriva de bot_mensaje (no se cree lo que dice el cliente de la base). Si hay que
--      resumir, `resumir` trae {hasta_id, mensajes[<=60]} porque el bot necesita el texto para generar el resumen.
--   3. bot_turno_estado y bot_turno_cerrar ganan parametros opcionales: p_testing (consume el aviso de testing solo si el bot esta en
--      testing) y p_cambio_tema. bot_eco_operadora y bot_pausar: p_horas es OPCIONAL (null = lee bot_config.pausa_horas).
--   4. bot_mensaje_recibir puede devolver ademas `reproceso` (true = el wamid estaba reclamado sin procesar hace >10 min: se reprocesa
--      UNA vez) o `tope` (spam: mas de 120 mensajes del mismo telefono en una hora; se descarta en silencio, el bot NO debe responder 5xx).
--   5. bot_baja devuelve {baja:'nueva'|'ya_dada', pausado:true}; con el mismo wamid reintentado devuelve 'nueva' otra vez (idempotente).
--   6. «humano = 1 llamada» pasa a 2: antes de enviar, el bot comprueba la baja con bot_turno_estado (hoy /admin/api/send devuelve 409
--      si hay baja); bot_envio_humano solo REGISTRA lo ya enviado.
--   7. bot_citas_recordar excluye telefonos con baja. lead_accion gana recordatorio_intentos (tope de reclamos = 2: el original + uno).
--   8. Resumen: idempotencia y tope diario viven en lead_notas (columnas tipo y ref_hasta_id + indice unico parcial), no en bot_acciones_log.
--   9. «Las funciones del bot no devuelven datos de otro telefono» salvo las dos excepciones: lo vigila tools/check_seguridad.py (eje BOT-S1).
-- REVERSION: supabase/reversion_bot_sin_redis_s1/REVERSION.sql (incluye la definicion previa de bot_lead_upsert).
-- ============================================================================

-- ── 0. ayudantes internos ────────────────────────────────────────────────────
-- Telefono del bot = digitos con prefijo de pais y SIN '+' (como llega del webhook). Misma normalizacion que bot_lead_*.
create or replace function public._bot_tel(p text)
returns text language sql immutable set search_path = '' as $f$
  select ltrim(public._bot_e164(p), '+')
$f$;

-- Texto de fuera (chat con un tercero): sin caracteres de control (salvo salto de linea y tabulador), recortado y con tope.
create or replace function public._bot_limpia(p text, n int)
returns text language sql immutable set search_path = '' as $f$
  select left(btrim(regexp_replace(coalesce(p, ''), '[\x01-\x08\x0b\x0c\x0e-\x1f\x7f]', '', 'g')), n)
$f$;

-- Media del mensaje: SOLO {tipo, id}. Nunca base64 ni URL.
create or replace function public._bot_media(p jsonb)
returns jsonb language sql immutable set search_path = '' as $f$
  select case
           when p is null or jsonb_typeof(p) <> 'object' or nullif(btrim(coalesce(p->>'id', '')), '') is null then null
           else jsonb_build_object('tipo', left(btrim(coalesce(p->>'tipo', 'otro')), 20), 'id', left(btrim(p->>'id'), 200))
         end
$f$;

-- ── 1. lead_notas: tipo (resumen del bot) y su cursor ────────────────────────
alter table public.lead_notas
  add column if not exists tipo         text   not null default 'nota',
  add column if not exists ref_hasta_id bigint;
do $c$ begin
  if not exists (select 1 from pg_constraint where conname = 'lead_notas_tipo_check') then
    alter table public.lead_notas add constraint lead_notas_tipo_check check (tipo in ('nota', 'resumen_bot'));
  end if;
end $c$;
-- Idempotencia del resumen: (lead, hasta_id) una sola vez.
create unique index if not exists lead_notas_resumen_unico
  on public.lead_notas (lead_id, ref_hasta_id) where tipo = 'resumen_bot';

-- ── 2. lead_accion: recordatorio de cita ─────────────────────────────────────
alter table public.lead_accion
  add column if not exists recordatorio_en        timestamptz,
  add column if not exists recordatorio_res       text,
  add column if not exists recordatorio_intentos  smallint not null default 0;
do $c$ begin
  if not exists (select 1 from pg_constraint where conname = 'lead_accion_recordatorio_res_check') then
    alter table public.lead_accion add constraint lead_accion_recordatorio_res_check
      check (recordatorio_res is null or recordatorio_res in ('enviado', 'sin_ventana', 'fallo'));
  end if;
end $c$;
create index if not exists lead_accion_recordar
  on public.lead_accion (cuando_ts)
  where completada_en is null and estado = 'confirmada' and tipo in ('llamada', 'visita');

-- Si la cita cambia de hora, el recordatorio anterior ya no vale: vuelve a ser elegible.
create or replace function public._bot_recordatorio_reinicia()
returns trigger language plpgsql set search_path = '' as $f$
begin
  if new.cuando_ts is distinct from old.cuando_ts then
    new.recordatorio_en := null;
    new.recordatorio_res := null;
    new.recordatorio_intentos := 0;
  end if;
  return new;
end $f$;
do $c$ begin
  if not exists (select 1 from pg_trigger where tgname = 'trg_lead_accion_recordatorio_reinicia' and tgrelid = 'public.lead_accion'::regclass) then
    create trigger trg_lead_accion_recordatorio_reinicia
      before update of cuando_ts on public.lead_accion
      for each row execute function public._bot_recordatorio_reinicia();
  end if;
end $c$;

-- ── 3. bot_chat: una fila por telefono (estado operativo) ────────────────────
create table if not exists public.bot_chat (
  tel                 text primary key check (tel ~ '^[0-9]{6,20}$'),
  lead_id             uuid references public.leads (id) on delete set null,      -- referencia; solo la fija bot_lead_upsert
  nombre_perfil       text check (nombre_perfil is null or length(nombre_perfil) <= 80),
  intent              text check (intent is null or length(intent) <= 40),
  ultimo_mensaje      text check (ultimo_mensaje is null or length(ultimo_mensaje) <= 200),
  ultimo_por          text check (ultimo_por is null or ultimo_por in ('cliente', 'bot', 'humano')),
  creado_en           timestamptz not null default now(),
  actualizado_en      timestamptz not null default now(),
  actividad_en        timestamptz not null default now(),                         -- base de la purga por inactividad (S7)
  archivado           boolean not null default false,
  resumen_hasta_id    bigint,                                                     -- cursor: hasta que bot_mensaje.id esta resumido
  pausado             boolean not null default false,
  pausa_hasta         timestamptz,                                                -- null con pausado = pausa que no caduca
  pausa_por           text check (pausa_por is null or length(pausa_por) <= 120),
  esperando           boolean not null default false,
  ultimo_entrante_en  timestamptz,                                                -- ventana de 24 h de WhatsApp
  baja_en             timestamptz,                                                -- STOP: no caduca nunca
  baja_acuse_en       timestamptz,
  baja_wamid          text check (baja_wamid is null or length(baja_wamid) <= 120),
  seguimientos        integer not null default 0 check (seguimientos >= 0),
  aviso_nivel         smallint not null default 0 check (aviso_nivel between 0 and 2),   -- 0 nada · 1 interested · 2 booking
  aviso_testing_en    timestamptz,
  entrega_error       text check (entrega_error is null or length(entrega_error) <= 120),
  entrega_error_en    timestamptz,
  check (pausa_hasta is null or pausado)
);
create index if not exists bot_chat_actividad on public.bot_chat (actividad_en);
create index if not exists bot_chat_lead on public.bot_chat (lead_id) where lead_id is not null;

-- ── 4. bot_mensaje: la memoria (una fila por mensaje) ────────────────────────
create table if not exists public.bot_mensaje (
  id          bigint generated always as identity primary key,
  tel         text not null references public.bot_chat (tel) on delete cascade,
  rol         text not null check (rol in ('user', 'assistant')),
  por         text not null check (por in ('cliente', 'bot', 'humano')),
  por_usuario text check (por_usuario is null or length(por_usuario) <= 120),
  contenido   text not null check (length(contenido) <= 4096),
  media       jsonb check (media is null or (jsonb_typeof(media) = 'object' and (media - 'tipo' - 'id') = '{}'::jsonb and length(media::text) <= 300)),
  wamid       text check (wamid is null or length(wamid) <= 120),
  creado_en   timestamptz not null default now(),
  ts_origen   timestamptz,
  check ((rol = 'user') = (por = 'cliente'))
);
create index if not exists bot_mensaje_tel_id on public.bot_mensaje (tel, id);
create index if not exists bot_mensaje_creado on public.bot_mensaje (creado_en);
create unique index if not exists bot_mensaje_tel_wamid on public.bot_mensaje (tel, wamid) where wamid is not null;

-- ── 5. bot_wamid: autoridad unica de «ya procesado» ──────────────────────────
create table if not exists public.bot_wamid (
  wamid        text primary key check (length(wamid) between 1 and 120),
  tel          text not null check (tel ~ '^[0-9]{6,20}$'),
  visto_en     timestamptz not null default now(),
  procesado_en timestamptz,
  reprocesos   smallint not null default 0 check (reprocesos between 0 and 1)
);
create index if not exists bot_wamid_visto on public.bot_wamid (visto_en);

-- ── 6. bot_escalacion: sustituye esc_queue + escmap ──────────────────────────
create table if not exists public.bot_escalacion (
  id          bigint generated always as identity primary key,
  tel         text not null references public.bot_chat (tel) on delete cascade,
  nombre      text check (nombre is null or length(nombre) <= 80),
  pregunta    text not null check (length(pregunta) <= 500),
  aviso_wamid text check (aviso_wamid is null or length(aviso_wamid) <= 120),
  creada_en   timestamptz not null default now(),
  resuelta_en timestamptz
);
create unique index if not exists bot_escalacion_aviso on public.bot_escalacion (aviso_wamid) where aviso_wamid is not null;
create index if not exists bot_escalacion_abiertas on public.bot_escalacion (creada_en, id) where resuelta_en is null;
create index if not exists bot_escalacion_tel on public.bot_escalacion (tel);

-- ── 7. bot_config (fila unica) y su log ──────────────────────────────────────
create table if not exists public.bot_config (
  id              boolean primary key default true check (id),                    -- una sola fila posible
  extra           text    not null default '' check (length(extra) <= 2000),
  bienvenida      text    not null default '' check (length(bienvenida) <= 500),
  pausa_horas     integer not null default 0 check (pausa_horas between 0 and 720),   -- 0 = la pausa por humano no caduca
  resumen_cada_n  integer not null default 30 check (resumen_cada_n between 5 and 200),
  fallos_alarma   integer not null default 3 check (fallos_alarma between 1 and 20),
  version         integer not null default 1 check (version >= 1),
  actualizado_en  timestamptz not null default now(),
  actualizado_por text    not null default '' check (length(actualizado_por) <= 120)
);
insert into public.bot_config (id) values (true) on conflict (id) do nothing;

create table if not exists public.bot_config_log (
  id      bigint generated always as identity primary key,
  cuando  timestamptz not null default now(),
  usuario text not null check (length(usuario) <= 120),
  version integer not null,
  prev    jsonb not null,
  next    jsonb not null
);

-- ── 8. registro de lecturas de conversaciones (permiso bot_conversaciones_ver, S10) ──
create table if not exists public.bot_lecturas_log (
  id      bigint generated always as identity primary key,
  cuando  timestamptz not null default now(),
  usuario text not null check (length(usuario) <= 120),
  tel     text check (tel is null or tel ~ '^[0-9]{6,20}$'),
  accion  text not null check (accion in ('lista', 'hilo'))
);
create index if not exists bot_lecturas_log_cuando on public.bot_lecturas_log (cuando);

-- ── 9. cerrar todo: RLS sin policies, sin privilegios para nadie ─────────────
alter table public.bot_chat          enable row level security;
alter table public.bot_mensaje       enable row level security;
alter table public.bot_wamid         enable row level security;
alter table public.bot_escalacion    enable row level security;
alter table public.bot_config        enable row level security;
alter table public.bot_config_log    enable row level security;
alter table public.bot_lecturas_log  enable row level security;
revoke all on public.bot_chat, public.bot_mensaje, public.bot_wamid, public.bot_escalacion,
              public.bot_config, public.bot_config_log, public.bot_lecturas_log
  from public, anon, authenticated, service_role;
revoke all on sequence public.bot_mensaje_id_seq, public.bot_escalacion_id_seq, public.bot_config_log_id_seq, public.bot_lecturas_log_id_seq
  from public, anon, authenticated, service_role;

-- Logs de solo anadir. bot_config_log: nunca se borra. bot_lecturas_log: solo la purga de S7 (que fija bot.purga=on en su transaccion).
create or replace function public._bot_lecturas_solo_anade()
returns trigger language plpgsql set search_path = '' as $f$
begin
  if tg_op = 'DELETE' and coalesce(current_setting('bot.purga', true), '') = 'on' then
    return old;
  end if;
  raise exception 'bot_lecturas_log es de solo anadir (solo la purga de retencion borra)' using errcode = '42501';
end $f$;
do $c$ begin
  if not exists (select 1 from pg_trigger where tgname = 'trg_bot_lecturas_solo_anade' and tgrelid = 'public.bot_lecturas_log'::regclass) then
    create trigger trg_bot_lecturas_solo_anade before update or delete on public.bot_lecturas_log
      for each row execute function public._bot_lecturas_solo_anade();
    create trigger trg_bot_lecturas_no_truncate before truncate on public.bot_lecturas_log
      for each statement execute function public.bot_acciones_log_solo_anade();
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'trg_bot_config_log_solo_anade' and tgrelid = 'public.bot_config_log'::regclass) then
    create trigger trg_bot_config_log_solo_anade before update or delete on public.bot_config_log
      for each row execute function public.bot_acciones_log_solo_anade();
    create trigger trg_bot_config_log_no_truncate before truncate on public.bot_config_log
      for each statement execute function public.bot_acciones_log_solo_anade();
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'trg_bot_config_no_borrar' and tgrelid = 'public.bot_config'::regclass) then
    create trigger trg_bot_config_no_borrar before delete on public.bot_config
      for each row execute function public.bot_acciones_log_solo_anade();
    create trigger trg_bot_config_no_truncate before truncate on public.bot_config
      for each statement execute function public.bot_acciones_log_solo_anade();
  end if;
end $c$;

-- bot_config: cada cambio sube la version y deja su fila en bot_config_log EN LA MISMA TRANSACCION (lo garantiza la base, no la pantalla).
create or replace function public._bot_config_antes()
returns trigger language plpgsql set search_path = '' as $f$
begin
  new.id := true;
  new.version := old.version + 1;
  new.actualizado_en := now();
  return new;
end $f$;
create or replace function public._bot_config_log()
returns trigger language plpgsql security definer set search_path = '' as $f$
begin
  insert into public.bot_config_log (usuario, version, prev, next)
  values (left(coalesce(nullif(new.actualizado_por, ''), 'desconocido'), 120), new.version, to_jsonb(old), to_jsonb(new));
  return null;
end $f$;
do $c$ begin
  if not exists (select 1 from pg_trigger where tgname = 'trg_bot_config_antes' and tgrelid = 'public.bot_config'::regclass) then
    create trigger trg_bot_config_antes before update on public.bot_config for each row execute function public._bot_config_antes();
    create trigger trg_bot_config_log after update on public.bot_config for each row execute function public._bot_config_log();
  end if;
end $c$;

-- ── 10. la regla de pausa (UN solo escritor): equivale a botcfg.ttlPausaHumana ─
-- p_horas null = lo que diga bot_config.pausa_horas. 0 = no caduca. Una pausa manual que no caduca NO se vuelve caducable porque la
-- operadora escriba despues. Devuelve el instante en que caduca (null = no caduca / nada que hacer).
create or replace function public._bot_pausa_humana(p_tel text, p_horas int default null, p_por text default null)
returns timestamptz language plpgsql set search_path = '' as $f$
declare
  v_h int := least(greatest(coalesce(p_horas, (select c.pausa_horas from public.bot_config c)), 0), 720);
  v_c public.bot_chat%rowtype;
  v_hasta timestamptz;
begin
  select * into v_c from public.bot_chat where tel = p_tel for update;
  if not found then return null; end if;
  if v_h = 0 then
    update public.bot_chat set pausado = true, pausa_hasta = null, pausa_por = coalesce(left(p_por, 120), pausa_por), actualizado_en = now()
     where tel = p_tel;
    return null;
  end if;
  if v_c.pausado and v_c.pausa_hasta is null then return null; end if;
  v_hasta := now() + make_interval(hours => v_h);
  update public.bot_chat set pausado = true, pausa_hasta = v_hasta, pausa_por = coalesce(left(p_por, 120), pausa_por), actualizado_en = now()
   where tel = p_tel;
  return v_hasta;
end $f$;

-- ── 11. permiso bot_conversaciones_ver + registro de cada lectura (lo llamara S10) ─
-- Misma regla que «Lo que sabe el bot»: super_admin o la casilla, y SOLO con alcance global (el bot es uno y mezcla las dos empresas).
create or replace function public._bot_conversaciones_autoriza(p_tel text, p_accion text)
returns void language plpgsql security definer set search_path = '' as $f$
declare
  v_quien text := coalesce(nullif((select auth.email()), ''), '');
  v_tel text := case when p_tel is null then null else public._bot_tel(p_tel) end;
begin
  if p_accion not in ('lista', 'hilo') then
    raise exception 'Accion de lectura no valida' using errcode = 'PT400';
  end if;
  if p_tel is not null and v_tel is null then
    raise exception 'Telefono no valido' using errcode = 'PT400';
  end if;
  if v_quien = '' or not exists (
    select 1 from public.usuarios u
     where u.user_id = (select auth.uid()) and u.activo
       and u.ambito = 'global' and coalesce(cardinality(u.empresas), 0) = 0
       and (u.rol = 'super_admin' or 'bot_conversaciones_ver' = any (u.herramientas))
  ) then
    raise exception 'Sin permiso para leer las conversaciones del bot' using errcode = '42501';
  end if;
  insert into public.bot_lecturas_log (usuario, tel, accion) values (left(v_quien, 120), v_tel, p_accion);
end $f$;

-- ── 12. bot_lead_upsert: ahora tambien fija bot_chat.lead_id (misma firma) ───
-- Cambios sobre la version viva (20261010080200): tras resolver el lead, enlaza la conversacion; si el telefono casa con mas de
-- un lead, la deja NULA. Nada mas cambia.
create or replace function public.bot_lead_upsert(
  p_tel text, p_nombre text default null, p_origen text default 'bot-whatsapp-lawang', p_msg_id text default null)
returns text language plpgsql security definer set search_path = '' as $f$
declare
  v_e164   text := public._bot_e164(p_tel);
  v_msg    text := nullif(left(btrim(coalesce(p_msg_id, '')), 120), '');
  v_nombre text := nullif(left(btrim(regexp_replace(regexp_replace(coalesce(p_nombre, ''), '[[:cntrl:]]', ' ', 'g'), ' {2,}', ' ', 'g')), 80), '');
  v_origen text := case when p_origen in ('bot-whatsapp-lawang', 'bot-whatsapp-sumbahills') then p_origen else 'bot-whatsapp-lawang' end;
  v_prev   text;
  v_ids    uuid[];
  v_lead   uuid;
begin
  if v_e164 is null then return 'telefono_invalido'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bot:' || v_e164, 0));
  if v_msg is not null then
    select l.resultado into v_prev from public.bot_acciones_log l where l.accion = 'upsert' and l.msg_id = v_msg;
    if found then return v_prev; end if;
  end if;

  select coalesce(array_agg(l.id order by l.created_at), '{}') into v_ids
    from public.leads l where public._lw_tel_e164(l.whatsapp) = v_e164;

  if cardinality(v_ids) > 1 then
    perform public._bot_nota_ambiguo(v_ids, 'alta');
    perform public._bot_log('upsert', null, v_msg, 'ambiguo', 'n=' || cardinality(v_ids));
    update public.bot_chat set lead_id = null where tel = ltrim(v_e164, '+') and lead_id is not null;
    return 'ambiguo';
  end if;

  if cardinality(v_ids) = 1 then
    v_lead := v_ids[1];
    if (select count(*) from public.bot_acciones_log l
         where l.lead_id = v_lead and l.accion = 'upsert' and l.cuando > now() - interval '24 hours') >= 500 then
      return 'tope';
    end if;
    if v_nombre is not null then
      update public.leads set name = v_nombre where id = v_lead and name is null;
    end if;
    perform public._bot_log('upsert', v_lead, v_msg, 'existente');
    update public.bot_chat set lead_id = v_lead where tel = ltrim(v_e164, '+') and lead_id is distinct from v_lead;
    return 'existente';
  end if;

  if (select count(*) from public.bot_acciones_log l
       where l.accion = 'upsert' and l.resultado = 'creado' and l.cuando > now() - interval '1 hour') >= 60 then
    return 'tope';
  end if;
  insert into public.leads (whatsapp, name, source) values (v_e164, v_nombre, v_origen) returning id into v_lead;
  perform public._bot_log('upsert', v_lead, v_msg, 'creado');
  update public.bot_chat set lead_id = v_lead where tel = ltrim(v_e164, '+') and lead_id is distinct from v_lead;
  return 'creado';
end $f$;

-- ── 13. PASO 1 — bot_mensaje_recibir (antes del 200 a Meta) ──────────────────
create or replace function public.bot_mensaje_recibir(p_tel text, p_wamid text, p_nombre_perfil text, p_mensaje jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_e164   text := public._bot_e164(p_tel);
  v_tel    text := ltrim(public._bot_e164(p_tel), '+');
  v_w      text := nullif(left(btrim(coalesce(p_wamid, '')), 120), '');
  v_texto  text;
  v_media  jsonb;
  v_nombre text := nullif(public._bot_limpia(p_nombre_perfil, 80), '');
  v_ts     timestamptz;
  v_wr     public.bot_wamid%rowtype;
  v_n      int;
  v_corte  timestamptz;
begin
  if v_e164 is null then return jsonb_build_object('error', 'telefono_invalido'); end if;
  if v_w is null then return jsonb_build_object('error', 'wamid_invalido'); end if;
  if p_mensaje is null or jsonb_typeof(p_mensaje) <> 'object' then return jsonb_build_object('error', 'mensaje_invalido'); end if;
  v_texto := public._bot_limpia(p_mensaje->>'texto', 4096);            -- se recorta, no se rechaza: un 5xx haria que Meta reentregue sin fin
  v_media := public._bot_media(p_mensaje->'media');
  begin
    if (p_mensaje->>'ts') ~ '^[0-9]{9,13}$' then
      v_ts := to_timestamp(case when (p_mensaje->>'ts')::numeric > 100000000000 then (p_mensaje->>'ts')::numeric / 1000 else (p_mensaje->>'ts')::numeric end);
    end if;
  exception when others then v_ts := null;
  end;
  if v_ts is not null and abs(extract(epoch from (v_ts - now()))) > 604800 then v_ts := null; end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bot:' || v_e164, 0));

  -- reclamo atomico del wamid
  insert into public.bot_wamid (wamid, tel) values (v_w, v_tel) on conflict (wamid) do nothing;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    select * into v_wr from public.bot_wamid where wamid = v_w;
    if v_wr.tel <> v_tel or v_wr.procesado_en is not null then
      return jsonb_build_object('duplicado', true, 'procesado', true);
    end if;
    if v_wr.reprocesos = 0 and v_wr.visto_en < now() - interval '10 minutes' then
      update public.bot_wamid set reprocesos = 1, visto_en = now() where wamid = v_w;
      return jsonb_build_object('duplicado', false, 'procesado', false, 'reproceso', true);
    end if;
    return jsonb_build_object('duplicado', true, 'procesado', false);
  end if;

  -- tope de ritmo: mas de 120 mensajes entrantes del mismo telefono en una hora = se descarta (y se da por procesado)
  select m.creado_en into v_corte from public.bot_mensaje m where m.tel = v_tel and m.rol = 'user' order by m.id desc offset 119 limit 1;
  if v_corte is not null and v_corte > now() - interval '1 hour' then
    update public.bot_wamid set procesado_en = now() where wamid = v_w;
    return jsonb_build_object('duplicado', true, 'procesado', true, 'tope', true);
  end if;

  insert into public.bot_chat (tel, nombre_perfil, ultimo_mensaje, ultimo_por, ultimo_entrante_en, esperando)
  values (v_tel, v_nombre, nullif(left(v_texto, 200), ''), 'cliente', now(), true)
  on conflict (tel) do update
     set nombre_perfil = coalesce(excluded.nombre_perfil, public.bot_chat.nombre_perfil),
         ultimo_mensaje = excluded.ultimo_mensaje, ultimo_por = 'cliente',
         ultimo_entrante_en = now(), esperando = true, seguimientos = 0,
         actividad_en = now(), actualizado_en = now();

  insert into public.bot_mensaje (tel, rol, por, contenido, media, wamid, ts_origen)
  values (v_tel, 'user', 'cliente', v_texto, v_media, v_w, v_ts)
  on conflict (tel, wamid) where wamid is not null do nothing;

  return jsonb_build_object('duplicado', false, 'procesado', false);
end $f$;

-- ── 14. PASO 2 — bot_turno_estado (tras waitMyTurn) ──────────────────────────
create or replace function public.bot_turno_estado(p_tel text, p_testing boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_e164 text := public._bot_e164(p_tel);
  v_tel  text := ltrim(public._bot_e164(p_tel), '+');
  v_c    public.bot_chat%rowtype;
  v_avisar_testing boolean := false;
  v_hist jsonb;
  v_cfg  jsonb;
begin
  if v_e164 is null then return jsonb_build_object('error', 'telefono_invalido'); end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bot:' || v_e164, 0));
  select * into v_c from public.bot_chat where tel = v_tel;
  if not found then return jsonb_build_object('error', 'sin_chat'); end if;

  if coalesce(p_testing, false) and v_c.aviso_testing_en is null then
    update public.bot_chat set aviso_testing_en = now() where tel = v_tel and aviso_testing_en is null;
    v_avisar_testing := true;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('rol', m.rol, 'texto', m.contenido, 'por', m.por, 'media', m.media,
                                               'ts', (extract(epoch from m.creado_en) * 1000)::bigint) order by m.id), '[]'::jsonb)
    into v_hist
    from (select x.* from public.bot_mensaje x where x.tel = v_tel order by x.id desc limit 20) m;

  select jsonb_build_object('extra', c.extra, 'bienvenida', c.bienvenida, 'pausa_horas', c.pausa_horas,
                            'resumen_cada_n', c.resumen_cada_n, 'fallos_alarma', c.fallos_alarma,
                            'version', c.version, 'actualizado_en', c.actualizado_en)
    into v_cfg from public.bot_config c;

  return jsonb_build_object(
    'baja', v_c.baja_en is not null,
    'pausado', v_c.pausado and (v_c.pausa_hasta is null or v_c.pausa_hasta > now()),
    'esperando', v_c.esperando,
    'avisar_testing', v_avisar_testing,
    'primer_turno', not exists (select 1 from public.bot_mensaje m where m.tel = v_tel and m.rol = 'assistant'),
    'historial', v_hist,
    'config', v_cfg);
end $f$;

-- ── 15. PASO 3 — bot_turno_cerrar (fin de turno, una vez) ────────────────────
create or replace function public.bot_turno_cerrar(
  p_tel text, p_wamid text, p_salida jsonb default '[]'::jsonb, p_intent text default null, p_aviso text default null,
  p_esperando boolean default false, p_cambio_tema boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_e164  text := public._bot_e164(p_tel);
  v_tel   text := ltrim(public._bot_e164(p_tel), '+');
  v_w     text := nullif(left(btrim(coalesce(p_wamid, '')), 120), '');
  v_wr    public.bot_wamid%rowtype;
  v_c     public.bot_chat%rowtype;
  v_nivel smallint := case p_aviso when 'interested' then 1 when 'booking' then 2 else 0 end;
  v_avisar text;
  v_m     record;
  v_txt   text;
  v_media jsonb;
  v_ult_por text;
  v_ult_c text;
  v_cnt   int;
  v_max   bigint;
  v_n_cfg int;
  v_resumir jsonb;
begin
  if v_e164 is null then return jsonb_build_object('error', 'telefono_invalido'); end if;
  if v_w is null then return jsonb_build_object('error', 'wamid_invalido'); end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bot:' || v_e164, 0));

  select * into v_wr from public.bot_wamid where wamid = v_w and tel = v_tel;
  if not found then return jsonb_build_object('error', 'wamid_desconocido'); end if;
  if v_wr.procesado_en is not null then
    return jsonb_build_object('avisar', null, 'resumir', null, 'repetido', true);   -- reintento del cierre: no se duplica nada
  end if;
  select * into v_c from public.bot_chat where tel = v_tel for update;
  if not found then return jsonb_build_object('error', 'sin_chat'); end if;

  if p_salida is not null and jsonb_typeof(p_salida) = 'array' then
    for v_m in select e.value as v from jsonb_array_elements(p_salida) with ordinality as e(value, ord) where e.ord <= 10 order by e.ord loop
      if jsonb_typeof(v_m.v) = 'object' then
        v_txt := public._bot_limpia(v_m.v->>'texto', 4096);
        v_media := public._bot_media(v_m.v->'media');
        if v_txt <> '' or v_media is not null then
          insert into public.bot_mensaje (tel, rol, por, contenido, media, wamid)
          values (v_tel, 'assistant', 'bot', v_txt, v_media, nullif(left(btrim(coalesce(v_m.v->>'wamid', '')), 120), ''))
          on conflict (tel, wamid) where wamid is not null do nothing;
        end if;
      end if;
    end loop;
  end if;

  if v_nivel > v_c.aviso_nivel then v_avisar := p_aviso; end if;     -- un aviso por nivel, aunque el cierre se reintente

  select m.por, left(m.contenido, 200) into v_ult_por, v_ult_c from public.bot_mensaje m where m.tel = v_tel order by m.id desc limit 1;

  update public.bot_chat
     set intent = coalesce(nullif(public._bot_limpia(p_intent, 40), ''), intent),
         ultimo_mensaje = coalesce(nullif(v_ult_c, ''), ultimo_mensaje),
         ultimo_por = coalesce(v_ult_por, ultimo_por),
         aviso_nivel = greatest(aviso_nivel, v_nivel),
         esperando = coalesce(p_esperando, false),
         actividad_en = now(), actualizado_en = now()
   where tel = v_tel;

  -- ¿toca resumir? Solo con ficha (lead_id), pasado el umbral de mensajes (o cambio de tema con material suficiente) y bajo el tope diario.
  if v_c.lead_id is not null then
    select count(*), max(m.id) into v_cnt, v_max from public.bot_mensaje m where m.tel = v_tel and m.id > coalesce(v_c.resumen_hasta_id, 0);
    select c.resumen_cada_n into v_n_cfg from public.bot_config c;
    if (v_cnt >= v_n_cfg or (coalesce(p_cambio_tema, false) and v_cnt >= 4))
       and (select count(*) from public.lead_notas n where n.lead_id = v_c.lead_id and n.tipo = 'resumen_bot'
              and n.created_at > now() - interval '24 hours') < 6 then
      select jsonb_build_object('hasta_id', v_max,
                                'mensajes', coalesce(jsonb_agg(jsonb_build_object('rol', x.rol, 'por', x.por, 'texto', left(x.contenido, 1000)) order by x.id), '[]'::jsonb))
        into v_resumir
        from (select y.* from public.bot_mensaje y where y.tel = v_tel and y.id > coalesce(v_c.resumen_hasta_id, 0) order by y.id desc limit 60) x;
    end if;
  end if;

  update public.bot_wamid set procesado_en = now() where wamid = v_w and tel = v_tel;
  return jsonb_build_object('avisar', v_avisar, 'resumir', v_resumir, 'repetido', false);
end $f$;

-- ── 16. eco de la operadora (Coexistence): una sola llamada ──────────────────
create or replace function public.bot_eco_operadora(p_tel text, p_wamid text, p_texto text, p_horas int default null)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_e164 text := public._bot_e164(p_tel);
  v_tel  text := ltrim(public._bot_e164(p_tel), '+');
  v_w    text := nullif(left(btrim(coalesce(p_wamid, '')), 120), '');
  v_antes boolean;
  v_txt  text := public._bot_limpia(p_texto, 4096);
  v_n    int;
begin
  if v_e164 is null then return jsonb_build_object('error', 'telefono_invalido'); end if;
  if v_w is null then return jsonb_build_object('error', 'wamid_invalido'); end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bot:' || v_e164, 0));

  insert into public.bot_chat (tel) values (v_tel) on conflict (tel) do nothing;
  select (c.pausado and (c.pausa_hasta is null or c.pausa_hasta > now())) into v_antes from public.bot_chat c where c.tel = v_tel;
  -- 1º la pausa (lo que importa es que el bot se calle), aunque el wamid ya estuviera visto; cada mensaje de la persona renueva el plazo
  perform public._bot_pausa_humana(v_tel, p_horas, 'whatsapp_business_app');

  insert into public.bot_wamid (wamid, tel, procesado_en) values (v_w, v_tel, now()) on conflict (wamid) do nothing;
  get diagnostics v_n = row_count;
  if v_n = 0 then return jsonb_build_object('duplicado', true, 'estaba_pausado', v_antes); end if;

  insert into public.bot_mensaje (tel, rol, por, por_usuario, contenido, wamid)
  values (v_tel, 'assistant', 'humano', 'whatsapp_business_app', v_txt, v_w)
  on conflict (tel, wamid) where wamid is not null do nothing;
  update public.bot_chat
     set ultimo_mensaje = nullif(left(v_txt, 200), ''), ultimo_por = 'humano', esperando = false,
         actividad_en = now(), actualizado_en = now()
   where tel = v_tel;
  return jsonb_build_object('duplicado', false, 'estaba_pausado', v_antes);
end $f$;

-- ── 17. pausa desde el bot (traspaso [HUMANO]) ───────────────────────────────
create or replace function public.bot_pausar(p_tel text, p_modo text, p_horas int default null)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_e164 text := public._bot_e164(p_tel);
  v_tel  text := ltrim(public._bot_e164(p_tel), '+');
  v_hasta timestamptz;
  v_c    public.bot_chat%rowtype;
begin
  if v_e164 is null then return jsonb_build_object('error', 'telefono_invalido'); end if;
  if p_modo is null or p_modo not in ('humano', 'quitar') then return jsonb_build_object('error', 'modo_invalido'); end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bot:' || v_e164, 0));
  if not exists (select 1 from public.bot_chat where tel = v_tel) then return jsonb_build_object('error', 'sin_chat'); end if;
  if p_modo = 'humano' then
    v_hasta := public._bot_pausa_humana(v_tel, p_horas, 'bot');
  else
    update public.bot_chat set pausado = false, pausa_hasta = null, pausa_por = 'bot', actualizado_en = now() where tel = v_tel;
  end if;
  select * into v_c from public.bot_chat where tel = v_tel;
  return jsonb_build_object('pausado', v_c.pausado and (v_c.pausa_hasta is null or v_c.pausa_hasta > now()), 'hasta', v_c.pausa_hasta);
end $f$;

-- ── 18. baja (STOP): una sentencia, un acuse, pausa aplicada ─────────────────
create or replace function public.bot_baja(p_tel text, p_wamid text default null)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_e164 text := public._bot_e164(p_tel);
  v_tel  text := ltrim(public._bot_e164(p_tel), '+');
  v_w    text := nullif(left(btrim(coalesce(p_wamid, '')), 120), '');
  v_c    public.bot_chat%rowtype;
  v_res  text;
begin
  if v_e164 is null then return jsonb_build_object('error', 'telefono_invalido'); end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bot:' || v_e164, 0));
  insert into public.bot_chat (tel) values (v_tel) on conflict (tel) do nothing;        -- una baja se honra aunque la fila no existiera
  select * into v_c from public.bot_chat where tel = v_tel for update;
  if v_c.baja_en is null then
    update public.bot_chat
       set baja_en = now(), baja_acuse_en = now(), baja_wamid = v_w,
           pausado = true, pausa_hasta = null, pausa_por = 'baja', actualizado_en = now(), actividad_en = now()
     where tel = v_tel;
    v_res := 'nueva';
  elsif v_w is not null and v_c.baja_wamid = v_w then
    v_res := 'nueva';                                                                    -- reintento de la misma peticion: sigue debiendo su acuse
  else
    v_res := 'ya_dada';
  end if;
  return jsonb_build_object('baja', v_res, 'pausado', true);
end $f$;

-- ── 19. entrega fallida (estado de WhatsApp con error) ───────────────────────
create or replace function public.bot_entrega_fallida(p_tel text, p_codigo text, p_detalle text default null)
returns text language plpgsql security definer set search_path = '' as $f$
declare
  v_tel text := ltrim(public._bot_e164(p_tel), '+');
begin
  if v_tel is null then return 'telefono_invalido'; end if;
  update public.bot_chat
     set entrega_error = left(public._bot_limpia(p_codigo, 20) || ' ' || public._bot_limpia(p_detalle, 90), 120), entrega_error_en = now()
   where tel = v_tel;
  if not found then return 'sin_chat'; end if;
  return 'ok';
end $f$;

-- ── 20. escalaciones: sustituyen esc_queue + escmap ──────────────────────────
create or replace function public.bot_escalar(p_tel text, p_nombre text, p_pregunta text, p_aviso_wamid text default null)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_e164 text := public._bot_e164(p_tel);
  v_tel  text := ltrim(public._bot_e164(p_tel), '+');
  v_preg text := public._bot_limpia(p_pregunta, 500);
  v_id   bigint;
begin
  if v_e164 is null then return jsonb_build_object('error', 'telefono_invalido'); end if;
  if v_preg = '' then return jsonb_build_object('error', 'pregunta_vacia'); end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bot:' || v_e164, 0));
  if not exists (select 1 from public.bot_chat where tel = v_tel) then return jsonb_build_object('error', 'sin_chat'); end if;
  if (select count(*) from public.bot_escalacion e where e.tel = v_tel and e.resuelta_en is null) >= 20 then
    return jsonb_build_object('error', 'tope');
  end if;
  insert into public.bot_escalacion (tel, nombre, pregunta, aviso_wamid)
  values (v_tel, nullif(public._bot_limpia(p_nombre, 80), ''), v_preg, nullif(left(btrim(coalesce(p_aviso_wamid, '')), 120), ''))
  on conflict (aviso_wamid) where aviso_wamid is not null do nothing
  returning id into v_id;
  return jsonb_build_object('id', v_id);
end $f$;

-- EXCEPCION 1 a «el bot no lee otro telefono»: el dueño responde y hay que saber a QUIEN. Devuelve UNA escalacion, la marca resuelta.
-- Citando el aviso (p_ctx_wamid) → esa; si no, la mas antigua abierta de los ultimos 7 dias (la vida que tenia escmap).
create or replace function public.bot_escalacion_tomar(p_ctx_wamid text default null)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_ctx text := nullif(left(btrim(coalesce(p_ctx_wamid, '')), 120), '');
  v_r   record;
begin
  update public.bot_escalacion e
     set resuelta_en = now()
   where e.id = (select x.id from public.bot_escalacion x
                  where x.resuelta_en is null
                    and (coalesce(x.aviso_wamid = v_ctx, false) or x.creada_en > now() - interval '7 days')
                  order by coalesce(x.aviso_wamid = v_ctx, false) desc, x.creada_en, x.id
                  limit 1 for update skip locked)
  returning e.tel, e.nombre, e.pregunta into v_r;
  if not found then return '{}'::jsonb; end if;
  return jsonb_build_object('tel', v_r.tel, 'nombre', v_r.nombre, 'pregunta', v_r.pregunta);
end $f$;

-- ── 21. resumen de la conversacion → lead_notas (decision 5 del owner) ────────
create or replace function public.bot_lead_resumen(p_tel text, p_texto text, p_hasta_id bigint)
returns text language plpgsql security definer set search_path = '' as $f$
declare
  v_e164  text := public._bot_e164(p_tel);
  v_tel   text := ltrim(public._bot_e164(p_tel), '+');
  v_c     public.bot_chat%rowtype;
  v_texto text := public._bot_limpia(p_texto, 1200);
  v_n     int;
begin
  if v_e164 is null then return 'telefono_invalido'; end if;
  if v_texto = '' then return 'vacio'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bot:' || v_e164, 0));
  select * into v_c from public.bot_chat where tel = v_tel for update;
  if not found or v_c.lead_id is null then return 'sin_lead'; end if;
  if p_hasta_id is null or p_hasta_id <= 0
     or not exists (select 1 from public.bot_mensaje m where m.tel = v_tel and m.id = p_hasta_id) then
    return 'hasta_invalido';
  end if;
  if p_hasta_id <= coalesce(v_c.resumen_hasta_id, 0) then return 'ya_hecho'; end if;
  if (select count(*) from public.lead_notas n where n.lead_id = v_c.lead_id and n.tipo = 'resumen_bot'
        and n.created_at > now() - interval '24 hours') >= 6 then
    return 'tope';
  end if;
  insert into public.lead_notas (lead_id, texto, autor, tipo, ref_hasta_id)
  values (v_c.lead_id, v_texto, 'bot', 'resumen_bot', p_hasta_id)
  on conflict (lead_id, ref_hasta_id) where tipo = 'resumen_bot' do nothing;
  get diagnostics v_n = row_count;
  update public.bot_chat set resumen_hasta_id = p_hasta_id, actualizado_en = now() where tel = v_tel;
  return case when v_n = 1 then 'ok' else 'ya_hecho' end;
end $f$;

-- ── 22. recordatorio de cita 1 h antes ───────────────────────────────────────
-- EXCEPCION 2 a «el bot no lee otro telefono»: el reloj necesita saber a quien escribir. SIN parametro: la ventana (60 min) esta aqui.
-- En UNA sentencia reclama las citas confirmadas que vencen en la proxima hora: dos ticks simultaneos = una sola gana (SKIP LOCKED).
-- Reclamo con reintento: sin resultado pasados 10 min se reclama otra vez, UNA vez (recordatorio_intentos < 2). Los telefonos con baja no salen.
create or replace function public.bot_citas_recordar()
returns table (accion_id uuid, tel text, tipo text, cuando_ts timestamptz, ultimo_entrante_en timestamptz)
language sql security definer set search_path = '' as $f$
  with cand as (
    select a.id
      from public.lead_accion a
      join public.leads l on l.id = a.lead_id
     where a.estado = 'confirmada' and a.tipo in ('llamada', 'visita') and a.completada_en is null
       and a.cuando_ts > now() and a.cuando_ts <= now() + interval '60 minutes'
       and (a.recordatorio_en is null
            or (a.recordatorio_res is null and a.recordatorio_intentos < 2 and a.recordatorio_en < now() - interval '10 minutes'))
       and public._bot_tel(l.whatsapp) is not null
       and not exists (select 1 from public.bot_chat c where c.tel = public._bot_tel(l.whatsapp) and c.baja_en is not null)
     order by a.cuando_ts
     limit 20
     for update of a skip locked),
  tomadas as (
    update public.lead_accion a
       set recordatorio_en = now(), recordatorio_res = null, recordatorio_intentos = a.recordatorio_intentos + 1
      from cand
     where a.id = cand.id
    returning a.id, a.lead_id, a.tipo, a.cuando_ts)
  select t.id, public._bot_tel(l.whatsapp), t.tipo, t.cuando_ts, c.ultimo_entrante_en
    from tomadas t
    join public.leads l on l.id = t.lead_id
    left join public.bot_chat c on c.tel = public._bot_tel(l.whatsapp)
$f$;

create or replace function public.bot_cita_recordatorio_res(p_accion uuid, p_res text)
returns text language plpgsql security definer set search_path = '' as $f$
begin
  if p_res is null or p_res not in ('enviado', 'sin_ventana', 'fallo') then return 'resultado_invalido'; end if;
  update public.lead_accion
     set recordatorio_res = p_res
   where id = p_accion and tipo in ('llamada', 'visita') and recordatorio_en is not null and recordatorio_res is null;
  if not found then return 'no_aplica'; end if;
  return 'ok';
end $f$;

-- ── 23. ruta /humano: lo que hace una PERSONA desde la intranet ──────────────
-- El usuario llega como p_usuario, que la edge saca del JWT que reenvia el proxy (nunca del cuerpo). Aqui solo se exige que no este vacio.
create or replace function public.bot_pausar_humano(p_tel text, p_modo text, p_usuario text)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_e164 text := public._bot_e164(p_tel);
  v_tel  text := ltrim(public._bot_e164(p_tel), '+');
  v_u    text := nullif(public._bot_limpia(p_usuario, 120), '');
  v_c    public.bot_chat%rowtype;
begin
  if v_e164 is null then return jsonb_build_object('error', 'telefono_invalido'); end if;
  if v_u is null then return jsonb_build_object('error', 'sin_usuario'); end if;
  if p_modo is null or p_modo not in ('pausar', 'quitar') then return jsonb_build_object('error', 'modo_invalido'); end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bot:' || v_e164, 0));
  if not exists (select 1 from public.bot_chat where tel = v_tel) then return jsonb_build_object('error', 'sin_chat'); end if;
  update public.bot_chat
     set pausado = (p_modo = 'pausar'), pausa_hasta = null, pausa_por = v_u, actualizado_en = now()
   where tel = v_tel;
  select * into v_c from public.bot_chat where tel = v_tel;
  return jsonb_build_object('pausado', v_c.pausado, 'hasta', v_c.pausa_hasta);
end $f$;

-- Registra lo que la persona YA envio por WhatsApp (la baja se comprueba ANTES de enviar, con bot_turno_estado). Pausa al bot segun la config.
create or replace function public.bot_envio_humano(p_tel text, p_texto text, p_wamid text, p_media jsonb, p_usuario text)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_e164 text := public._bot_e164(p_tel);
  v_tel  text := ltrim(public._bot_e164(p_tel), '+');
  v_u    text := nullif(public._bot_limpia(p_usuario, 120), '');
  v_txt  text := public._bot_limpia(p_texto, 4096);
  v_media jsonb := public._bot_media(p_media);
begin
  if v_e164 is null then return jsonb_build_object('error', 'telefono_invalido'); end if;
  if v_u is null then return jsonb_build_object('error', 'sin_usuario'); end if;
  if v_txt = '' and v_media is null then return jsonb_build_object('error', 'mensaje_vacio'); end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bot:' || v_e164, 0));
  if not exists (select 1 from public.bot_chat where tel = v_tel) then return jsonb_build_object('error', 'sin_chat'); end if;
  insert into public.bot_mensaje (tel, rol, por, por_usuario, contenido, media, wamid)
  values (v_tel, 'assistant', 'humano', v_u, v_txt, v_media, nullif(left(btrim(coalesce(p_wamid, '')), 120), ''))
  on conflict (tel, wamid) where wamid is not null do nothing;
  perform public._bot_pausa_humana(v_tel, null, v_u);
  update public.bot_chat
     set ultimo_mensaje = nullif(left(v_txt, 200), ''), ultimo_por = 'humano', esperando = false,
         actividad_en = now(), actualizado_en = now()
   where tel = v_tel;
  return jsonb_build_object('ok', true);
end $f$;

-- ── 24. concesiones: solo bot_lawang, solo su lista ──────────────────────────
revoke all on function public._bot_tel(text)                                          from public, anon, authenticated, service_role;
revoke all on function public._bot_limpia(text, int)                                  from public, anon, authenticated, service_role;
revoke all on function public._bot_media(jsonb)                                       from public, anon, authenticated, service_role;
revoke all on function public._bot_pausa_humana(text, int, text)                      from public, anon, authenticated, service_role;
revoke all on function public._bot_conversaciones_autoriza(text, text)                from public, anon, authenticated, service_role;
revoke all on function public._bot_recordatorio_reinicia()                            from public, anon, authenticated, service_role;
revoke all on function public._bot_lecturas_solo_anade()                              from public, anon, authenticated, service_role;
revoke all on function public._bot_config_antes()                                     from public, anon, authenticated, service_role;
revoke all on function public._bot_config_log()                                       from public, anon, authenticated, service_role;
revoke all on function public.bot_mensaje_recibir(text, text, text, jsonb)            from public, anon, authenticated, service_role;
revoke all on function public.bot_turno_estado(text, boolean)                         from public, anon, authenticated, service_role;
revoke all on function public.bot_turno_cerrar(text, text, jsonb, text, text, boolean, boolean) from public, anon, authenticated, service_role;
revoke all on function public.bot_eco_operadora(text, text, text, int)                from public, anon, authenticated, service_role;
revoke all on function public.bot_pausar(text, text, int)                             from public, anon, authenticated, service_role;
revoke all on function public.bot_baja(text, text)                                    from public, anon, authenticated, service_role;
revoke all on function public.bot_entrega_fallida(text, text, text)                   from public, anon, authenticated, service_role;
revoke all on function public.bot_escalar(text, text, text, text)                     from public, anon, authenticated, service_role;
revoke all on function public.bot_escalacion_tomar(text)                              from public, anon, authenticated, service_role;
revoke all on function public.bot_lead_resumen(text, text, bigint)                    from public, anon, authenticated, service_role;
revoke all on function public.bot_citas_recordar()                                    from public, anon, authenticated, service_role;
revoke all on function public.bot_cita_recordatorio_res(uuid, text)                   from public, anon, authenticated, service_role;
revoke all on function public.bot_pausar_humano(text, text, text)                     from public, anon, authenticated, service_role;
revoke all on function public.bot_envio_humano(text, text, text, jsonb, text)         from public, anon, authenticated, service_role;
-- bot_lead_upsert: create or replace conserva sus concesiones; se reafirman por si acaso.
revoke all on function public.bot_lead_upsert(text, text, text, text)                 from public, anon, authenticated, service_role;

grant execute on function public.bot_lead_upsert(text, text, text, text)              to bot_lawang;
grant execute on function public.bot_mensaje_recibir(text, text, text, jsonb)         to bot_lawang;
grant execute on function public.bot_turno_estado(text, boolean)                      to bot_lawang;
grant execute on function public.bot_turno_cerrar(text, text, jsonb, text, text, boolean, boolean) to bot_lawang;
grant execute on function public.bot_eco_operadora(text, text, text, int)             to bot_lawang;
grant execute on function public.bot_pausar(text, text, int)                          to bot_lawang;
grant execute on function public.bot_baja(text, text)                                 to bot_lawang;
grant execute on function public.bot_entrega_fallida(text, text, text)                to bot_lawang;
grant execute on function public.bot_escalar(text, text, text, text)                  to bot_lawang;
grant execute on function public.bot_escalacion_tomar(text)                           to bot_lawang;
grant execute on function public.bot_lead_resumen(text, text, bigint)                 to bot_lawang;
grant execute on function public.bot_citas_recordar()                                 to bot_lawang;
grant execute on function public.bot_cita_recordatorio_res(uuid, text)                to bot_lawang;
grant execute on function public.bot_pausar_humano(text, text, text)                  to bot_lawang;
grant execute on function public.bot_envio_humano(text, text, text, jsonb, text)      to bot_lawang;
