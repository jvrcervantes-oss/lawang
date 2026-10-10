-- destructivo-ok: solo construye (3 columnas nuevas en proyectos, 4 en lead_accion, tabla nueva bot_acciones_log, rol nuevo, funciones nuevas). Los "drop" son: el indice lead_accion_una_viva, que se RECREA con la misma clave y un filtro mas (tipo='tarea'); lead_accion esta VACIA (0 filas, medido 9-oct-2026), asi que no hay datos que se pierdan. Y 3 funciones existentes (crm_leads, crm_lead_accion_poner, crm_lead_accion_completar) se REEMPLAZAN con create or replace (misma firma). Reversion: supabase/reversion_bot_s3/REVERSION.sql.
-- ============================================================================
-- LAWANG — BOT CON CATALOGO EN VIVO Y GESTION DEL CRM — BASE DE DATOS (9-oct-2026)
-- ----------------------------------------------------------------------------
-- Encargo: encargos/20261008_lawang_bot_catalogo_crm.md, subtarea S3 (revision previa #234:
-- decisiones de Seguridad y Datos). La edge `bot-api` (S4) y el bot (S6) son otras subtareas.
--
-- EL DATO TIENE UN DUEÑO (patrones_tecnicos.md) — que se guarda aqui y que NO:
--   · precio, superficie, tipo, modelo, estado de la unidad -> dueño: unidades. El catalogo NO lo copia: la funcion lo lee al llamarla.
--   · «el bot puede hablar de este proyecto»              -> dueño: proyectos.bot_publico (una sola escritura, cerrada por defecto,
--                                                           independiente de publicado_investor_deck: Palm Field es confidencial, LAW-200).
--   · telefono del lead                                    -> dueño: leads.whatsapp. NO se copia: el bot manda el del webhook en cada llamada
--                                                           y se normaliza con _lw_tel_e164(). El log NO guarda telefono ni hash (un telefono
--                                                           hasheado se saca por fuerza bruta); guarda lead_id y id de mensaje.
--   · citas y llamadas                                     -> dueño: lead_accion (la misma tabla que ya lee el CRM de la intranet).
--   · notas del bot                                        -> dueño: lead_notas (autor 'bot').
--
-- LLAMADORES CON NOMBRE (seguridad_2026 §1.ter — lo nuevo nace cerrado):
--   bot_catalogo_leer / bot_lead_upsert / bot_lead_nota / bot_lead_cita  <- edge `bot-api` (S4), con el rol de BD `bot_lawang`. Nadie mas:
--                                                           sin EXECUTE para anon, authenticated ni PUBLIC.
--   _bot_e164 / _bot_log / _bot_nota_ambiguo                <- solo las cuatro de arriba. Sin EXECUTE para nadie.
--   bot_acciones_log (tabla)                                <- solo las cuatro de arriba. RLS activa, sin policies, sin grants. Append-only (trigger).
--   proyectos_bot_publico_sello (trigger)                   <- proyectos. Sin EXECUTE.
--   Quien enciende la casilla bot_publico: pantalla de la ficha del proyecto (S7). Hasta entonces solo `postgres` (nadie mas puede
--   escribir en proyectos: authenticated solo tiene SELECT).
--
-- DESVIACIONES / DECISIONES DE ESTA SUBTAREA (el CEO las ve en el informe):
--   1. El rol bot_lawang nace NOLOGIN. Darle clave y LOGIN es el paso de activacion (S4/Deploy, con el OK del owner):
--      `python tools/railway_secreto.py genera lawang bot_lawang <VAR> <carpeta>` (patron de ACTIVACION_ROLES_AGENTE.md).
--   2. lead_accion admite UNA tarea viva por lead (como hasta hoy) Y UNA cita viva por lead (llamada o visita). Sin esto la cita del bot
--      pisaba la «proxima accion» de la persona del equipo (crm_lead_accion_poner actualizaba «la viva») o al reves.
--      Por eso se retocan 3 funciones del CRM: poner (solo toca la tarea), completar (marca estado='hecha') y crm_leads
--      (un join a lead_accion con dos filas vivas DUPLICABA cada lead en la lista).
--   3. crm_origen_empresa gana 2 origenes del bot (bot-whatsapp-lawang -> lawang, bot-whatsapp-sumbahills -> sandal_woods): sin fila,
--      empresa_de_lead() devuelve null y el lead del bot seria INVISIBLE para el equipo.
--   4. Horario comercial de las citas: lunes a sabado, 09:00-17:30 hora de Bali (Asia/Makassar). Constante de esta funcion: es un
--      supuesto de Datos, no una decision del owner (el bot RESPONDE siempre; esto solo limita a que hora puede PROPONER una cita).
--   5. «disponible» en el catalogo: estado='disponible' Y sin contrato (unidades.contrato_id null). Solo salen disponibles.
--   6. NO se crea el indice unico por e164 ni se fusiona ningun lead: S2 espera la decision del owner (hay grupos duplicados).
--      Mientras tanto, >1 lead con el mismo e164 -> 'ambiguo', nada se aplica y se deja una nota FIJA en cada ficha.
-- ============================================================================

-- ── 1. la casilla «el bot puede hablar de este proyecto» ─────────────────────
alter table public.proyectos
  add column if not exists bot_publico     boolean not null default false,
  add column if not exists bot_publico_por text,
  add column if not exists bot_publico_en  timestamptz;

comment on column public.proyectos.bot_publico is
  'El bot de WhatsApp puede dar precios y disponibilidad de este proyecto. Cerrada por defecto; independiente de publicado_investor_deck. Dueño unico del dato (S3, 9-oct-2026).';

create or replace function public.proyectos_bot_publico_sello()
returns trigger language plpgsql security definer set search_path = '' as $f$
begin
  if (tg_op = 'INSERT' and new.bot_publico)
     or (tg_op = 'UPDATE' and new.bot_publico is distinct from old.bot_publico) then
    new.bot_publico_por := coalesce(nullif((select auth.email()), ''), current_user);
    new.bot_publico_en  := now();
  end if;
  return new;
end $f$;

drop trigger if exists trg_proyectos_bot_publico_sello on public.proyectos;
create trigger trg_proyectos_bot_publico_sello
  before insert or update of bot_publico on public.proyectos
  for each row execute function public.proyectos_bot_publico_sello();

-- ── 2. lead_accion: tipo, hora exacta, estado y origen ───────────────────────
alter table public.lead_accion
  add column if not exists tipo      text        not null default 'tarea',
  add column if not exists cuando_ts timestamptz,
  add column if not exists estado    text        not null default 'confirmada',
  add column if not exists origen    text        not null default 'humano';

do $c$ begin
  if not exists (select 1 from pg_constraint where conname = 'lead_accion_tipo_check') then
    alter table public.lead_accion add constraint lead_accion_tipo_check check (tipo in ('tarea', 'llamada', 'visita'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'lead_accion_estado_check') then
    alter table public.lead_accion add constraint lead_accion_estado_check
      check (estado in ('propuesta', 'confirmada', 'hecha', 'cancelada'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'lead_accion_origen_check') then
    alter table public.lead_accion add constraint lead_accion_origen_check check (origen in ('humano', 'bot', 'importado'));
  end if;
end $c$;

-- Una tarea viva por lead (como hasta hoy) y UNA cita viva por lead, por separado.
drop index if exists public.lead_accion_una_viva;
create unique index if not exists lead_accion_una_viva
  on public.lead_accion (lead_id) where completada_en is null and tipo = 'tarea';
create unique index if not exists lead_accion_cita_viva
  on public.lead_accion (lead_id) where completada_en is null and tipo in ('llamada', 'visita');

-- ── 3. el log del bot: append-only, sin telefono, sin texto del cliente ───────
create table if not exists public.bot_acciones_log (
  id        bigint generated always as identity primary key,
  cuando    timestamptz not null default now(),
  accion    text not null check (accion in ('upsert', 'nota', 'cita', 'catalogo')),
  lead_id   uuid,                                   -- sin FK a proposito: el log sobrevive al lead
  msg_id    text check (msg_id is null or length(msg_id) <= 120),
  resultado text not null check (length(resultado) <= 40),
  detalle   text check (detalle is null or length(detalle) <= 120)
);
create unique index if not exists bot_acciones_log_idem
  on public.bot_acciones_log (accion, msg_id) where msg_id is not null;
create index if not exists bot_acciones_log_lead_dia
  on public.bot_acciones_log (lead_id, accion, cuando desc) where lead_id is not null;
create index if not exists bot_acciones_log_cuando on public.bot_acciones_log (cuando desc);

alter table public.bot_acciones_log enable row level security;       -- sin policies: nadie lo lee por la API
revoke all on public.bot_acciones_log from public, anon, authenticated, service_role;
revoke all on sequence public.bot_acciones_log_id_seq from public, anon, authenticated, service_role;

create or replace function public.bot_acciones_log_solo_anade()
returns trigger language plpgsql set search_path = '' as $f$
begin
  raise exception 'bot_acciones_log es de solo anadir (no se modifica ni se borra)' using errcode = '42501';
end $f$;

drop trigger if exists trg_bot_acciones_log_solo_anade on public.bot_acciones_log;
create trigger trg_bot_acciones_log_solo_anade
  before update or delete on public.bot_acciones_log
  for each row execute function public.bot_acciones_log_solo_anade();
drop trigger if exists trg_bot_acciones_log_no_truncate on public.bot_acciones_log;
create trigger trg_bot_acciones_log_no_truncate
  before truncate on public.bot_acciones_log
  for each statement execute function public.bot_acciones_log_solo_anade();

-- ── 4. origenes del bot en el mapa origen -> empresa ─────────────────────────
insert into public.crm_origen_empresa (clave, empresa, nota) values
  ('bot-whatsapp-lawang',     'lawang',       'Lead creado por el bot de WhatsApp (S3, 9-oct-2026)'),
  ('bot-whatsapp-sumbahills', 'sandal_woods', 'Lead creado por el bot de WhatsApp sobre Sumba Hills (S3, 9-oct-2026)')
on conflict (clave) do nothing;

-- ── 5. ayudantes internos (nadie los ejecuta salvo las funciones del bot) ─────
-- El telefono del webhook llega como digitos con prefijo de pais y sin '+': se le pone el '+' para que
-- _lw_tel_e164 no lo trate como «local» (un '0' inicial se leeria como Indonesia).
create or replace function public._bot_e164(p text)
returns text language sql immutable set search_path = '' as $f$
  select public._lw_tel_e164(case when btrim(coalesce(p, '')) ~ '^[0-9]+$' then '+' || btrim(p) else p end)
$f$;

create or replace function public._bot_log(p_accion text, p_lead uuid, p_msg text, p_res text, p_det text default null)
returns void language sql set search_path = '' as $f$
  insert into public.bot_acciones_log (accion, lead_id, msg_id, resultado, detalle)
  values (p_accion, p_lead, p_msg, left(p_res, 40), left(p_det, 120))
  on conflict (accion, msg_id) where msg_id is not null do nothing
$f$;

-- Texto FIJO (nada del cliente) en cada ficha que comparte telefono: asi el equipo ve que el bot no actuo y por que.
create or replace function public._bot_nota_ambiguo(p_ids uuid[], p_accion text)
returns void language plpgsql set search_path = '' as $f$
declare v_texto text := 'Bot: este telefono figura en ' || cardinality(p_ids) || ' fichas de lead; no se aplico la accion ('
                        || left(p_accion, 20) || '). Revisar duplicados.';
begin
  insert into public.lead_notas (lead_id, texto, autor)
  select i, v_texto, 'bot' from unnest(p_ids) i
   where not exists (select 1 from public.lead_notas n
                      where n.lead_id = i and n.autor = 'bot' and n.texto = v_texto and n.created_at > now() - interval '24 hours');
end $f$;

-- ── 6. EL CATALOGO — columnas fijas, nunca una fila entera ────────────────────
create or replace function public.bot_catalogo_leer()
returns table (proyecto text, tipo text, codigo text, superficie_m2 numeric, precio numeric, moneda text, modelo text, disponible boolean)
language sql stable security definer set search_path = '' as $f$
  select p.nombre, u.tipo, u.codigo, u.superficie_m2, u.precio, u.moneda, u.modelo, true
    from public.unidades u
    join public.proyectos p on p.id = u.proyecto_id
   where p.bot_publico and p.activo
     and u.estado = 'disponible' and u.contrato_id is null
   order by p.nombre, u.tipo, u.codigo_orden nulls last, u.codigo
$f$;

-- ── 7. LAS TRES ACCIONES DE CRM ──────────────────────────────────────────────
create or replace function public.bot_lead_upsert(
  p_tel text, p_nombre text default null, p_origen text default 'bot-whatsapp-lawang', p_msg_id text default null)
returns text language plpgsql security definer set search_path = '' as $f$
declare
  v_e164   text := public._bot_e164(p_tel);
  v_msg    text := nullif(left(btrim(coalesce(p_msg_id, '')), 120), '');
  v_nombre text := nullif(left(btrim(regexp_replace(coalesce(p_nombre, ''), '[[:cntrl:]]', ' ', 'g')), 80), '');
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
    return 'ambiguo';
  end if;

  if cardinality(v_ids) = 1 then
    v_lead := v_ids[1];
    if (select count(*) from public.bot_acciones_log l
         where l.lead_id = v_lead and l.accion = 'upsert' and l.cuando > now() - interval '24 hours') >= 40 then
      return 'tope';
    end if;
    if v_nombre is not null then
      update public.leads set name = v_nombre where id = v_lead and name is null;   -- solo rellena un hueco, nunca pisa
    end if;
    perform public._bot_log('upsert', v_lead, v_msg, 'existente');
    return 'existente';
  end if;

  if (select count(*) from public.bot_acciones_log l
       where l.accion = 'upsert' and l.resultado = 'creado' and l.cuando > now() - interval '1 hour') >= 60 then
    return 'tope';
  end if;
  insert into public.leads (whatsapp, name, source) values (v_e164, v_nombre, v_origen) returning id into v_lead;
  perform public._bot_log('upsert', v_lead, v_msg, 'creado');
  return 'creado';
end $f$;

create or replace function public.bot_lead_nota(p_tel text, p_texto text, p_msg_id text default null)
returns text language plpgsql security definer set search_path = '' as $f$
declare
  v_e164  text := public._bot_e164(p_tel);
  v_msg   text := nullif(left(btrim(coalesce(p_msg_id, '')), 120), '');
  v_texto text := left(btrim(regexp_replace(coalesce(p_texto, ''), '[[:cntrl:]]', ' ', 'g')), 500);
  v_prev  text;
  v_ids   uuid[];
  v_lead  uuid;
begin
  if v_e164 is null then return 'telefono_invalido'; end if;
  if v_texto = '' then return 'vacio'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bot:' || v_e164, 0));
  if v_msg is not null then
    select l.resultado into v_prev from public.bot_acciones_log l where l.accion = 'nota' and l.msg_id = v_msg;
    if found then return v_prev; end if;
  end if;

  select coalesce(array_agg(l.id order by l.created_at), '{}') into v_ids
    from public.leads l where public._lw_tel_e164(l.whatsapp) = v_e164;
  if cardinality(v_ids) = 0 then return 'sin_lead'; end if;
  if cardinality(v_ids) > 1 then
    perform public._bot_nota_ambiguo(v_ids, 'nota');
    perform public._bot_log('nota', null, v_msg, 'ambiguo', 'n=' || cardinality(v_ids));
    return 'ambiguo';
  end if;

  v_lead := v_ids[1];
  if (select count(*) from public.bot_acciones_log l
       where l.lead_id = v_lead and l.accion = 'nota' and l.resultado = 'ok' and l.cuando > now() - interval '24 hours') >= 30 then
    return 'tope';
  end if;
  insert into public.lead_notas (lead_id, texto, autor) values (v_lead, v_texto, 'bot');
  perform public._bot_log('nota', v_lead, v_msg, 'ok');
  return 'ok';
end $f$;

create or replace function public.bot_lead_cita(p_tel text, p_cuando text, p_tipo text, p_msg_id text default null)
returns text language plpgsql security definer set search_path = '' as $f$
declare
  v_e164 text := public._bot_e164(p_tel);
  v_msg  text := nullif(left(btrim(coalesce(p_msg_id, '')), 120), '');
  v_s    text := btrim(coalesce(p_cuando, ''));
  v_ts   timestamptz;
  v_loc  timestamp;
  v_min  int;
  v_prev text;
  v_ids  uuid[];
  v_lead uuid;
  v_viva public.lead_accion%rowtype;
  v_resp text;
  v_que  text;
begin
  if v_e164 is null then return 'telefono_invalido'; end if;
  if p_tipo is null or p_tipo not in ('llamada', 'visita') then return 'tipo_invalido'; end if;
  -- ISO 8601 con o sin zona; sin zona se lee como hora de Bali (Asia/Makassar).
  if v_s !~ '^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(:\d{2}(\.\d{1,6})?)?(Z|[+-]\d{2}(:?\d{2})?)?$' then return 'fecha_invalida'; end if;
  begin
    if v_s ~ '(Z|[+-]\d{2}(:?\d{2})?)$' then v_ts := v_s::timestamptz;
    else v_ts := v_s::timestamp at time zone 'Asia/Makassar'; end if;
  exception when others then
    return 'fecha_invalida';
  end;
  if v_ts <= now() then return 'pasada'; end if;
  if v_ts > now() + interval '60 days' then return 'lejana'; end if;
  v_loc := v_ts at time zone 'Asia/Makassar';
  v_min := extract(hour from v_loc)::int * 60 + extract(minute from v_loc)::int;
  if extract(isodow from v_loc) not between 1 and 6 or v_min < 540 or v_min > 1050 then return 'fuera_horario'; end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bot:' || v_e164, 0));
  if v_msg is not null then
    select l.resultado into v_prev from public.bot_acciones_log l where l.accion = 'cita' and l.msg_id = v_msg;
    if found then return v_prev; end if;
  end if;

  select coalesce(array_agg(l.id order by l.created_at), '{}') into v_ids
    from public.leads l where public._lw_tel_e164(l.whatsapp) = v_e164;
  if cardinality(v_ids) = 0 then return 'sin_lead'; end if;
  if cardinality(v_ids) > 1 then
    perform public._bot_nota_ambiguo(v_ids, 'cita');
    perform public._bot_log('cita', null, v_msg, 'ambiguo', 'n=' || cardinality(v_ids));
    return 'ambiguo';
  end if;

  v_lead := v_ids[1];
  if (select count(*) from public.bot_acciones_log l
       where l.lead_id = v_lead and l.accion = 'cita' and l.resultado in ('propuesta', 'reprogramada')
         and l.cuando > now() - interval '24 hours') >= 5 then
    return 'tope';
  end if;

  v_que := case p_tipo when 'visita' then 'Visita' else 'Llamada' end
           || ' propuesta por el bot, pendiente de confirmar: ' || to_char(v_loc, 'DD-MM-YYYY HH24:MI') || ' (hora de Bali)';

  select * into v_viva from public.lead_accion a
   where a.lead_id = v_lead and a.completada_en is null and a.tipo in ('llamada', 'visita');
  if found then
    -- Solo se reprograma lo que el propio bot propuso y nadie ha confirmado; una cita del equipo no se toca.
    if v_viva.estado = 'propuesta' and v_viva.origen = 'bot' then
      update public.lead_accion
         set tipo = p_tipo, que = v_que, cuando = v_loc::date, cuando_ts = v_ts
       where id = v_viva.id;
      perform public._bot_log('cita', v_lead, v_msg, 'reprogramada');
      return 'reprogramada';
    end if;
    perform public._bot_log('cita', v_lead, v_msg, 'ya_hay_cita');
    return 'ya_hay_cita';
  end if;

  select e.responsable into v_resp from public.lead_estado e where e.lead_id = v_lead;
  insert into public.lead_accion (lead_id, que, cuando, responsable, creada_por, tipo, cuando_ts, estado, origen)
  values (v_lead, v_que, v_loc::date, coalesce(v_resp, 'bot'), 'bot', p_tipo, v_ts, 'propuesta', 'bot');
  perform public._bot_log('cita', v_lead, v_msg, 'propuesta');
  return 'propuesta';
end $f$;

-- ── 8. el rol del bot y quien puede ejecutar que ─────────────────────────────
do $r$ begin
  if not exists (select 1 from pg_roles where rolname = 'bot_lawang') then
    create role bot_lawang nologin noinherit connection limit 3;
  end if;
end $r$;
grant usage on schema public to bot_lawang;

revoke all on function public.bot_catalogo_leer()                              from public, anon, authenticated;
revoke all on function public.bot_lead_upsert(text, text, text, text)          from public, anon, authenticated;
revoke all on function public.bot_lead_nota(text, text, text)                  from public, anon, authenticated;
revoke all on function public.bot_lead_cita(text, text, text, text)            from public, anon, authenticated;
revoke all on function public._bot_e164(text)                                  from public, anon, authenticated;
revoke all on function public._bot_log(text, uuid, text, text, text)           from public, anon, authenticated;
revoke all on function public._bot_nota_ambiguo(uuid[], text)                  from public, anon, authenticated;
revoke all on function public.proyectos_bot_publico_sello()                    from public, anon, authenticated;
revoke all on function public.bot_acciones_log_solo_anade()                    from public, anon, authenticated;

grant execute on function public.bot_catalogo_leer()                           to bot_lawang;
grant execute on function public.bot_lead_upsert(text, text, text, text)       to bot_lawang;
grant execute on function public.bot_lead_nota(text, text, text)               to bot_lawang;
grant execute on function public.bot_lead_cita(text, text, text, text)         to bot_lawang;

-- ── 9. las tres funciones del CRM que asumian UNA accion viva por lead ────────
-- (cambia solo lo marcado «S3»; el resto es el cuerpo vigente leido de la base el 9-oct-2026)
create or replace function public.crm_lead_accion_poner(p_lead uuid, p_que text, p_cuando date, p_responsable text default null)
returns table (id uuid, lead_id uuid, que text, cuando date, responsable text)
language plpgsql security definer set search_path = '' as $f$
declare
  v_quien text := coalesce((select auth.email()), '');
  v_que   text := btrim(coalesce(p_que, ''));
  v_resp  text := nullif(btrim(coalesce(p_responsable, '')), '');
  v_id    uuid;
begin
  if not public.puede('leads') then
    raise exception 'Sin permiso sobre los leads' using errcode = 'PT403';
  end if;
  if not public.lead_a_mi_alcance(p_lead) then
    raise exception 'Ese lead no es de ninguna de tus campanas' using errcode = 'PT403';
  end if;
  if v_quien = '' then
    raise exception 'Sesion sin identidad' using errcode = 'PT403';
  end if;
  if v_que = '' then
    raise exception 'La accion esta vacia' using errcode = 'PT400';
  end if;
  if length(v_que) > 280 then
    raise exception 'La accion es demasiado larga' using errcode = 'PT400';
  end if;
  if p_cuando is null then
    raise exception 'Falta la fecha de la accion' using errcode = 'PT400';
  end if;
  if not exists (select 1 from public.leads l where l.id = p_lead) then
    raise exception 'Ese lead no existe' using errcode = 'PT404';
  end if;

  if v_resp is not null then
    if not exists (
      select 1 from public.usuarios u
       where lower(u.email) = lower(v_resp) and u.activo
         and ('leads' = any(u.herramientas) or u.rol = 'super_admin')
         and public.usuario_en_empresa(u.email, public.empresa_de_lead(p_lead))
    ) then
      raise exception 'Esa persona no esta activa o no tiene acceso al CRM de leads'
        using errcode = 'PT400';
    end if;
  else
    select e.responsable into v_resp from public.lead_estado e where e.lead_id = p_lead;
    v_resp := coalesce(v_resp, v_quien);
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_lead::text, 1));

  update public.lead_accion a
     set que = v_que, cuando = p_cuando, responsable = v_resp
   where a.lead_id = p_lead and a.completada_en is null
     and a.tipo = 'tarea'                                   -- S3: la cita del bot no es «la proxima accion»
   returning a.id into v_id;

  if v_id is null then
    insert into public.lead_accion (lead_id, que, cuando, responsable, creada_por)
         values (p_lead, v_que, p_cuando, v_resp, v_quien)
      returning lead_accion.id into v_id;
  end if;

  return query
    select a.id, a.lead_id, a.que, a.cuando, a.responsable
      from public.lead_accion a where a.id = v_id;
end;
$f$;

create or replace function public.crm_lead_accion_completar(p_accion uuid)
returns table (id uuid, lead_id uuid, completada_en timestamptz)
language plpgsql security definer set search_path = '' as $f$
declare
  v_quien text := coalesce((select auth.email()), '');
  v_lead  uuid;
begin
  if not public.puede('leads') then
    raise exception 'Sin permiso sobre los leads' using errcode = 'PT403';
  end if;
  if v_quien = '' then
    raise exception 'Sesion sin identidad' using errcode = 'PT403';
  end if;
  select a.lead_id into v_lead from public.lead_accion a where a.id = p_accion;
  if v_lead is not null and not public.lead_a_mi_alcance(v_lead) then
    raise exception 'Esa tarea es de un lead que no es de tus campanas' using errcode = 'PT403';
  end if;

  return query
    update public.lead_accion a
       set completada_en = now(), completada_por = v_quien,
           estado = 'hecha'                                 -- S3
     where a.id = p_accion and a.completada_en is null
    returning a.id, a.lead_id, a.completada_en;
end;
$f$;

create or replace function public.crm_leads()
returns table (id uuid, created_at timestamptz, source text, name text, campaign_id text, respuestas jsonb, tiene_email boolean,
               tiene_whatsapp boolean, estado text, estado_desde timestamptz, responsable text, notas bigint, sugerencia text,
               sugerencia_contrato text, accion_id uuid, accion_que text, accion_cuando date, accion_responsable text,
               contrato_id uuid, contrato_numero text, dueno text, dueno_nombre text, dueno_activo boolean)
language sql stable security definer set search_path = '' as $f$
  select l.id, l.created_at, l.source, l.name, l.campaign_id,
         coalesce((select jsonb_object_agg(k, v)
                     from jsonb_each(coalesce(l.respuestas, '{}'::jsonb)) as r(k, v)
                    where k in ('budget_range','buy_timeline','budget','purpose')),
                  '{}'::jsonb),
         nullif(btrim(coalesce(l.email, '')), '') is not null,
         nullif(btrim(coalesce(l.whatsapp, '')), '') is not null,
         coalesce(e.estado, 'nuevo'),
         coalesce(e.estado_desde, l.created_at),
         e.responsable,
         (select count(*) from public.lead_notas n where n.lead_id = l.id),
         s.etapa, s.contrato_numero,
         a.id, a.que, a.cuando, a.responsable,
         v.contrato_id, v.numero,
         e.responsable, u.nombre,
         case when e.responsable is null then null else coalesce(u.activo, false) end
    from public.leads l
    left join public.lead_estado e on e.lead_id = l.id
    left join public.lead_sugerencia s on s.lead_id = l.id
    -- S3: con tarea viva Y cita viva habria DOS filas por lead. Sale la mas proxima (la lista sigue siendo una fila por lead).
    left join lateral (
      select x.id, x.que, x.cuando, x.responsable
        from public.lead_accion x
       where x.lead_id = l.id and x.completada_en is null
       order by x.cuando asc, x.creada_en asc limit 1
    ) a on true
    left join public.usuarios u on lower(u.email) = lower(e.responsable)
    left join lateral (
      select k.contrato_id, c.numero
        from public.lead_contrato k
        join public.contratos c on c.id = k.contrato_id
       where k.lead_id = l.id order by k.cuando desc limit 1
    ) v on true
   where public.puede('leads')
     -- El alcance se aplica AQUI y no en el navegador: filtrar en el cliente es ensenar
     -- menos, no entregar menos, y los 108 seguirian viajando al navegador de quien solo
     -- debe ver 49.
     and public.lead_a_mi_alcance(l.id);
$f$;
