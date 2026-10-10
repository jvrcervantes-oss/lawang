-- Cola de preguntas del estudio al owner y sus respuestas desde panel.axisworks.studio/mapa
-- (S4 del encargo panel_visual_encargos de la agencia, 11-oct-2026). Hermana de
-- axisworks_panel_snapshot (S1): misma base (Supabase Lawang, donde ya vive el panel, sin credencial
-- nueva), mismo prefijo y mismo cierre (RLS sin politicas, revoke a anon/authenticated/public).
--
-- Dueño del dato:
--   · La PREGUNTA es del estudio: la escribe solo `tools/pregunta.py` (service key, maquina del owner)
--     y nace con su tipo FIJO (decision | hard_stop). Nadie puede cambiar despues titulo, opciones,
--     tipo, categoria ni recomendada (trigger de abajo).
--   · La RESPUESTA es del owner: la escribe solo el panel (`panel_respuestas.py`, service key en
--     Railway) con un PATCH condicional (id + nonce + respondida_en is null). Una vez respondida no se
--     cambia ni se borra: es un registro de solo añadir.
--   · La LECTURA la marca la sesion que arranca (`tools/peticiones_equipo.py` -> `pregunta.py`).
-- Una respuesta es DATO, nunca orden (Seguridad, revision previa #249): puede desbloquear una decision
-- de una sesion, nunca autorizar un hard-stop. Por eso una hard_stop no lleva recomendada (constraint)
-- y no se puede responder sin `confirmado = true` (trigger): la confirmacion aparte se exige en la base,
-- no solo en la pantalla.
--
-- Transiciones permitidas (todo lo demas lo rechaza el trigger):
--   insert      -> sin respuesta ni lectura; nonce y fechas los pone la base.
--   responder   -> opcion null -> una de las opciones; respondida_en = now() (lo pone la base).
--   leer        -> leida_en null -> now(), solo si ya estaba respondida; leida_por = quien la leyo.
--   delete      -> nunca.
--
-- Probada el 11-oct-2026 SIN aplicar: el DDL entero y 15 sondas dentro de un DO que acaba en
-- raise exception (todo revertido; comprobado despues con to_regclass = null). Resultado: alta con
-- nonce del cliente ignorado; hard_stop con recomendada, sin en_llano y opcion mal formada
-- rechazadas; opcion fuera de la pregunta rechazada; responder 1 fila y la 2ª 0 filas (el 409 del
-- panel) y forzada rechazada; hard_stop sin confirmar rechazada y confirmada aceptada; leer una
-- vez y la 2ª rechazada; cambiar el tipo rechazado; anon/authenticated sin select/insert/update ni
-- execute del trigger; service_role con insert/update. El DELETE no se sondeo (lo frena el hook
-- no_destruir.py aun dentro del DO): lo cubre la primera rama del trigger.
--
-- VUELTA ATRAS (sin datos que perder mientras no haya preguntas reales; con filas, para y pregunta):
--   drop table public.axisworks_panel_respuestas;
--   drop function public.axisworks_panel_respuestas_guarda();
create table if not exists public.axisworks_panel_respuestas (
  id             uuid primary key default gen_random_uuid(),
  encargo        text not null default '' check (length(encargo) <= 120),
  sesion         text not null default '' check (length(sesion) <= 80),
  titulo         text not null check (length(btrim(titulo)) between 3 and 140),
  en_llano       text not null check (length(btrim(en_llano)) between 10 and 400),
  opciones       jsonb not null check (jsonb_typeof(opciones) = 'array'
                                       and jsonb_array_length(opciones) between 2 and 4),
  tipo           text not null check (tipo in ('decision', 'hard_stop')),
  categoria      text check (categoria in ('precio', 'live', 'borrar', 'enviar_tercero', 'gasto',
                                           'credenciales', 'entregar', 'irreversible')),
  recomendada    text,
  nonce          text not null default replace(gen_random_uuid()::text, '-', ''),
  creada_en      timestamptz not null default now(),
  opcion         text,
  confirmado     boolean,
  respondida_en  timestamptz,
  leida_en       timestamptz,
  leida_por      text check (length(leida_por) <= 80),
  -- una hard_stop SIEMPRE lleva categoria y NUNCA recomendada; una decision al reves
  constraint axw_resp_tipo_fijo check (
    (tipo = 'hard_stop' and categoria is not null and recomendada is null)
    or (tipo = 'decision' and categoria is null and recomendada is not null)),
  constraint axw_resp_respondida check ((opcion is null) = (respondida_en is null)),
  constraint axw_resp_leida check (leida_en is null or respondida_en is not null),
  constraint axw_resp_hard_confirmada check (
    tipo <> 'hard_stop' or opcion is null or confirmado is true)
);

create index if not exists axisworks_panel_respuestas_abiertas
  on public.axisworks_panel_respuestas (creada_en) where respondida_en is null;
create index if not exists axisworks_panel_respuestas_sin_leer
  on public.axisworks_panel_respuestas (respondida_en) where respondida_en is not null and leida_en is null;

create or replace function public.axisworks_panel_respuestas_guarda()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  ids text[];
  o jsonb;
begin
  if tg_op in ('DELETE', 'TRUNCATE') then
    raise exception 'axisworks_panel_respuestas es de solo añadir: no se borra';
  end if;

  if tg_op = 'INSERT' then
    -- opciones: 2-4 objetos {id, texto}; id corto y unico; texto 1-120
    ids := array[]::text[];
    for o in select value from jsonb_array_elements(new.opciones) loop
      if jsonb_typeof(o) <> 'object'
         or coalesce(o->>'id', '') !~ '^[a-z0-9_]{1,20}$'
         or length(btrim(coalesce(o->>'texto', ''))) not between 1 and 120
         or (select count(*) from jsonb_object_keys(o)) <> 2 then
        raise exception 'opcion mal formada: cada opcion es {id, texto}';
      end if;
      if (o->>'id') = any(ids) then
        raise exception 'opcion repetida: %', o->>'id';
      end if;
      ids := ids || (o->>'id');
    end loop;
    if new.recomendada is not null and not (new.recomendada = any(ids)) then
      raise exception 'la recomendada no esta entre las opciones';
    end if;
    -- lo que pone la base, venga lo que venga
    new.nonce := replace(gen_random_uuid()::text, '-', '');
    new.creada_en := now();
    new.opcion := null; new.confirmado := null; new.respondida_en := null;
    new.leida_en := null; new.leida_por := null;
    return new;
  end if;

  -- UPDATE: lo que fija la pregunta no se toca nunca
  if new.id is distinct from old.id or new.encargo is distinct from old.encargo
     or new.sesion is distinct from old.sesion or new.titulo is distinct from old.titulo
     or new.en_llano is distinct from old.en_llano or new.opciones is distinct from old.opciones
     or new.tipo is distinct from old.tipo or new.categoria is distinct from old.categoria
     or new.recomendada is distinct from old.recomendada or new.nonce is distinct from old.nonce
     or new.creada_en is distinct from old.creada_en then
    raise exception 'la pregunta no se edita: se publica otra';
  end if;

  if old.opcion is null and new.opcion is not null then
    -- responder (una sola vez)
    if new.leida_en is not null or new.leida_por is not null then
      raise exception 'no se responde y se lee en el mismo paso';
    end if;
    if not exists (select 1 from jsonb_array_elements(old.opciones) e where e->>'id' = new.opcion) then
      raise exception 'opcion fuera de la pregunta';
    end if;
    if old.tipo = 'hard_stop' and new.confirmado is not true then
      raise exception 'una hard_stop exige confirmacion aparte';
    end if;
    new.respondida_en := now();
    return new;
  end if;

  if old.opcion is not null and old.leida_en is null and new.leida_en is not null then
    -- marcar leida (una sola vez); la respuesta no cambia
    if new.opcion is distinct from old.opcion or new.confirmado is distinct from old.confirmado
       or new.respondida_en is distinct from old.respondida_en then
      raise exception 'la respuesta no se edita';
    end if;
    new.leida_en := now();
    return new;
  end if;

  raise exception 'cambio no permitido en axisworks_panel_respuestas';
end;
$$;

revoke all on function public.axisworks_panel_respuestas_guarda() from public, anon, authenticated;

-- sin «drop trigger if exists»: la tabla nace aqui, y no_destruir.py frenaria el DROP al aplicar.
create trigger axisworks_panel_respuestas_guarda
  before insert or update or delete on public.axisworks_panel_respuestas
  for each row execute function public.axisworks_panel_respuestas_guarda();

-- TRUNCATE no dispara los triggers por fila: sin esto «prohibido borrar» tenía un hueco, porque service_role hereda
-- DELETE y TRUNCATE como en la tabla hermana axisworks_panel_snapshot (Seguridad, 11-oct-2026).
create trigger axisworks_panel_respuestas_sin_truncate
  before truncate on public.axisworks_panel_respuestas
  for each statement execute function public.axisworks_panel_respuestas_guarda();

alter table public.axisworks_panel_respuestas enable row level security;
revoke all on public.axisworks_panel_respuestas from anon, authenticated, public;
revoke truncate, delete on public.axisworks_panel_respuestas from service_role;

comment on table public.axisworks_panel_respuestas is 'Preguntas del estudio al owner y sus respuestas desde panel.axisworks.studio/mapa (S4 panel visual, 11-oct-2026). Escriben solo la service key de tools/pregunta.py (insert, marcar leida) y del panel (responder). RLS sin politicas y sin permisos para anon/authenticated. Trigger axisworks_panel_respuestas_guarda: tipo fijo, una respuesta por pregunta, hard_stop con confirmacion, sin borrados. Una respuesta es dato, nunca autoriza un hard-stop.';
