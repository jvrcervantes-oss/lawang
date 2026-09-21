-- destructivo-ok: los unicos DROP son `drop trigger if exists` justo antes de
-- volver a crear cada trigger -- idempotencia para poder reaplicar, no retirada
-- de nada (los cuatro triggers NACEN aqui). Lo que el guardrail lee como "UPDATE
-- sin WHERE" es la palabra `update` dentro de `after insert or update or delete`:
-- no hay ni una sentencia UPDATE en todo el fichero. Cero filas existentes tocadas.
/* INVESTOR DECK — el contenido deja de vivir en el HTML y pasa a la intranet.
   11-sep-2026. Copia con los porques completos, y por que cada decision es la que es:
   supabase/migrations/20260911180000_deck_contenido_intranet.sql
   Revision previa hecha (Seguridad+Datos+Legal), CEO/flujos/revision_previa.md. */

create or replace function public.deck_proyecto_abierto(p_proyecto text)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from public.unidades u
     where u.proyecto = p_proyecto and u.publicado_investor_deck
  );
$$;
revoke all on function public.deck_proyecto_abierto(text) from public;
grant execute on function public.deck_proyecto_abierto(text) to anon, authenticated;
comment on function public.deck_proyecto_abierto is
  'Opt-in del data room publico: un proyecto esta abierto si alguna de sus unidades tiene publicado_investor_deck. Fuente unica de esa regla -- la llaman los RPC investor_deck_*. Antes estaba copiada en cada uno.';

create table if not exists public.deck_fotos (
  id           uuid primary key default gen_random_uuid(),
  ambito       text not null check (ambito in ('proyecto','modelo')),
  proyecto_id  uuid references public.proyectos(id) on delete cascade,
  modelo_id    uuid references public.modelos(id)   on delete cascade,
  uso          text not null default 'galeria' check (uso in ('hero','galeria')),
  tipo         text not null default 'foto' check (tipo in ('foto','render','ia')),
  path         text not null unique,
  pie          jsonb not null default '{}'::jsonb,
  orden        integer not null default 0,
  creado_en    timestamptz not null default now(),
  creado_por   text default auth.email(),
  constraint deck_fotos_ambito_coherente check (
    (ambito = 'proyecto' and proyecto_id is not null and modelo_id is null)
    or (ambito = 'modelo' and modelo_id is not null)
  ),
  constraint deck_fotos_pie_en check (pie ? 'en')
);
create index if not exists deck_fotos_proyecto_idx on public.deck_fotos (proyecto_id, uso, orden);
create index if not exists deck_fotos_modelo_idx   on public.deck_fotos (modelo_id, orden);
comment on table public.deck_fotos is
  'Fotos PUBLICAS del investor deck. El bucket `deck` es publico: una fila aqui significa que el fichero ya es alcanzable por URL. No hay columna `publicado` a proposito -- seria decorativa.';
comment on column public.deck_fotos.pie is
  'Pie por idioma {"en":..,"es":..,"id":..}. NO pasa por i18n.js. El front resuelve pie[lang] ?? pie.en.';
comment on column public.deck_fotos.tipo is
  'foto | render | ia. Se rinde como pie visible: en la UE un render publicado integra la oferta, y Permendag 19/2026 obliga a declarar imagen generada.';

create table if not exists public.deck_faq (
  id             uuid primary key default gen_random_uuid(),
  proyecto_id    uuid not null references public.proyectos(id) on delete cascade,
  pregunta       jsonb not null,
  respuesta      jsonb not null,
  orden          integer not null default 0,
  publicado      boolean not null default false,
  creado_en      timestamptz not null default now(),
  creado_por     text default auth.email(),
  actualizado_en timestamptz not null default now(),
  constraint deck_faq_pregunta_en  check (pregunta  ? 'en'),
  constraint deck_faq_respuesta_en check (respuesta ? 'en')
);
create index if not exists deck_faq_proyecto_idx on public.deck_faq (proyecto_id, orden);
comment on table public.deck_faq is
  'FAQ PUBLICA del investor deck. Tabla aparte de documentos_proyecto a proposito: alli categoria=faq guarda notas INTERNAS del equipo y investor_deck_documentos las excluye. La frontera interno/publico separa tablas, no valores de una columna.';

create table if not exists public.deck_forecast_proyecto (
  proyecto_id       uuid primary key references public.proyectos(id) on delete cascade,
  pct_gestion       numeric not null check (pct_gestion       >= 0 and pct_gestion       <= 1),
  pct_mantenimiento numeric not null check (pct_mantenimiento >= 0 and pct_mantenimiento <= 1),
  pct_impuesto      numeric not null check (pct_impuesto      >= 0 and pct_impuesto      <= 1),
  contrato_vigente  text,
  vigente_desde     date,
  publicado         boolean not null default false,
  actualizado_en    timestamptz not null default now(),
  actualizado_por   text default auth.email(),
  constraint deck_forecast_pct_suma check (pct_gestion + pct_mantenimiento + pct_impuesto < 1)
);
comment on table public.deck_forecast_proyecto is
  'Porcentajes del contrato de gestion de alquiler, por proyecto. NO van a `proyectos`: esa es la tabla maestra que leen contratos, unidades y facturas de las nueve herramientas. `contrato_vigente` existe porque el pie del deck afirma que estos % son los del contrato vigente (Legal): sin constar cual, esa frase no se sostiene.';

create table if not exists public.deck_forecast (
  id                   uuid primary key default gen_random_uuid(),
  proyecto_id          uuid not null references public.proyectos(id) on delete cascade,
  modelo_id            uuid not null references public.modelos(id)   on delete cascade,
  adr_medio            numeric not null check (adr_medio  > 0),
  adr_optimo           numeric not null check (adr_optimo > 0),
  ocupacion_media      numeric not null check (ocupacion_media  > 0 and ocupacion_media  <= 1),
  ocupacion_optima     numeric not null check (ocupacion_optima > 0 and ocupacion_optima <= 1),
  inversion_base       numeric not null check (inversion_base > 0),
  unidad_referencia_id uuid references public.unidades(id) on delete set null,
  moneda               text not null default 'EUR' check (moneda = 'EUR'),
  destacado            boolean not null default false,
  publicado            boolean not null default false,
  orden                integer not null default 0,
  actualizado_en       timestamptz not null default now(),
  actualizado_por      text default auth.email(),
  constraint deck_forecast_unico unique (proyecto_id, modelo_id)
);
create index if not exists deck_forecast_proyecto_idx on public.deck_forecast (proyecto_id, orden);
comment on table public.deck_forecast is
  'Prevision de alquiler Ano 1 por (proyecto, modelo). Tabla propia y NO columnas en modelos_villa: aquella es el nivel 2 de la cascada de precio y tiene moneda por fila (hay filas en IDR), asi que un ADR ahi heredaria la moneda por accidente al copiar esto a otro proyecto.';
comment on column public.deck_forecast.inversion_base is
  'Inversion total sobre la que se calcula el ROI. Explicita, nunca derivada al vuelo. `unidad_referencia_id` dice de que parcela salio el suelo, para poder detectar que ha envejecido.';

create table if not exists public.deck_publicaciones (
  id      bigserial primary key,
  tabla   text not null,
  fila_id uuid not null,
  accion  text not null check (accion in ('alta','cambio','baja')),
  antes   jsonb,
  despues jsonb,
  quien   text not null default coalesce(auth.email(), '(sistema)'),
  cuando  timestamptz not null default now()
);
create index if not exists deck_publicaciones_fila_idx on public.deck_publicaciones (tabla, fila_id, cuando desc);
comment on table public.deck_publicaciones is
  'Historial APPEND-ONLY de todo lo que sale al investor deck publico. Sin update ni delete para ningun rol. Requisito de Legal: la pagina emite una Carta de Reserva y hay que poder demostrar que leyo el inversor ese dia.';

create or replace function public.deck_audita()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if TG_TABLE_NAME = 'deck_forecast_proyecto' then
    v_id := coalesce(new.proyecto_id, old.proyecto_id);
  else
    v_id := coalesce(new.id, old.id);
  end if;
  insert into public.deck_publicaciones (tabla, fila_id, accion, antes, despues)
  values (TG_TABLE_NAME, v_id,
    case TG_OP when 'INSERT' then 'alta' when 'UPDATE' then 'cambio' else 'baja' end,
    case when TG_OP = 'INSERT' then null else to_jsonb(old) end,
    case when TG_OP = 'DELETE' then null else to_jsonb(new) end);
  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_deck_audita_faq on public.deck_faq;
create trigger trg_deck_audita_faq after insert or update or delete on public.deck_faq
  for each row execute function public.deck_audita();
drop trigger if exists trg_deck_audita_forecast on public.deck_forecast;
create trigger trg_deck_audita_forecast after insert or update or delete on public.deck_forecast
  for each row execute function public.deck_audita();
drop trigger if exists trg_deck_audita_forecast_proy on public.deck_forecast_proyecto;
create trigger trg_deck_audita_forecast_proy after insert or update or delete on public.deck_forecast_proyecto
  for each row execute function public.deck_audita();
drop trigger if exists trg_deck_audita_fotos on public.deck_fotos;
create trigger trg_deck_audita_fotos after insert or update or delete on public.deck_fotos
  for each row execute function public.deck_audita();

alter table public.deck_fotos              enable row level security;
alter table public.deck_faq                enable row level security;
alter table public.deck_forecast           enable row level security;
alter table public.deck_forecast_proyecto  enable row level security;
alter table public.deck_publicaciones      enable row level security;

revoke all on public.deck_fotos, public.deck_faq, public.deck_forecast,
              public.deck_forecast_proyecto, public.deck_publicaciones from anon;

grant select, insert, update, delete
  on public.deck_fotos, public.deck_faq, public.deck_forecast, public.deck_forecast_proyecto
  to authenticated;
grant select, insert on public.deck_publicaciones to authenticated;
grant usage, select on sequence public.deck_publicaciones_id_seq to authenticated;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='deck_fotos' and policyname='deck_fotos: leer') then
    create policy "deck_fotos: leer"     on public.deck_fotos for select using (es_agente());
    create policy "deck_fotos: escribir" on public.deck_fotos for all    using (es_admin()) with check (es_admin());
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='deck_faq' and policyname='deck_faq: leer') then
    create policy "deck_faq: leer"     on public.deck_faq for select using (es_agente());
    create policy "deck_faq: escribir" on public.deck_faq for all    using (es_admin()) with check (es_admin());
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='deck_forecast' and policyname='deck_forecast: leer') then
    create policy "deck_forecast: leer"     on public.deck_forecast for select using (es_agente());
    create policy "deck_forecast: escribir" on public.deck_forecast for all    using (es_admin()) with check (es_admin());
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='deck_forecast_proyecto' and policyname='deck_forecast_proyecto: leer') then
    create policy "deck_forecast_proyecto: leer"     on public.deck_forecast_proyecto for select using (es_agente());
    create policy "deck_forecast_proyecto: escribir" on public.deck_forecast_proyecto for all    using (es_admin()) with check (es_admin());
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='deck_publicaciones' and policyname='deck_publicaciones: leer') then
    create policy "deck_publicaciones: leer"      on public.deck_publicaciones for select using (es_agente());
    create policy "deck_publicaciones: escribir"  on public.deck_publicaciones for insert with check (true);
  end if;
end $$;;
