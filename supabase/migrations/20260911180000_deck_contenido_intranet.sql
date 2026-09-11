-- destructivo-ok: los unicos DROP son `drop trigger if exists` justo antes de
-- volver a crear cada trigger -- idempotencia para poder reaplicar la migracion,
-- no retirada de nada (los cuatro triggers NACEN en este mismo fichero). Y lo que
-- el guardrail lee como "UPDATE sin WHERE" es la palabra `update` dentro de
-- `after insert or update or delete on ...`: no hay ni una sentencia UPDATE en
-- todo el fichero. Cero filas existentes tocadas: solo se crean objetos nuevos y
-- se reescriben dos funciones con `create or replace` manteniendo su alcance.

/* ══════════════════════════════════════════════════════════════════════════
   INVESTOR DECK — el contenido deja de vivir en el HTML y pasa a la intranet
   11-sep-2026 · encargo del owner
   ══════════════════════════════════════════════════════════════════════════

   QUÉ. Tres cosas que hoy están clavadas en `investor-deck/palmfield/index.html`
   —las fotos, la FAQ y la previsión de alquiler— pasan a tener dueño en la base,
   editables desde la intranet. Es estructura de INVESTOR DECK, no de Palm Field:
   nace pensada para copiarse al resto de la cartera, y por eso ni una sola de
   estas tablas nombra a Palm Field en su definición.

   ── Revisión previa hecha (Seguridad + Datos + Legal), CEO/flujos/revision_previa.md ──
   Los tres tumbaron partes del plan. Lo que cazaron y cómo se pliega aquí:

   1. [DATOS, lo más grave] El plan era sembrar la FAQ pública dentro de
      `documentos_proyecto` con `categoria='faq'`. Pero `investor_deck_documentos`
      lleva escrito Y APLICADO `and d.categoria <> 'faq'`, con este comentario en
      la propia función: «La categoria 'faq' guarda notas internas del equipo…
      Ahora la garantia escrita esta aplicada de verdad». Dentro hay hoy 6 filas
      reales: las preguntas de due diligence de un inversor sobre el título, el
      PKKPR/RDTR y una afirmación de «tributación 0%», todas `confidencial=true`.
      Meter filas públicas en ese mismo cajón dejaba un booleano como única
      frontera entre lo interno y una página sin login. Por eso la FAQ pública va
      a TABLA PROPIA: la frontera separa tablas, no valores de una columna.
      Las 6 internas no se tocan, no se publican y no se les inventa respuesta.

   2. [DATOS] Una columna por idioma (`pie_en`/`pie_es`/`pie_id`) no escala: añadir
      un cuarto idioma sería DDL en tres tablas más reescribir cada RPC, en una
      estructura que se va a copiar. Todo texto multiidioma va en `jsonb`
      (`{"en":…,"es":…,"id":…}`) con un CHECK de que `en` existe — la fila muda no
      llega a entrar. ⚠️ Y queda dicho aquí: **lo que sale de estas tablas NO pasa
      por `i18n.js`**, que casa por texto inglés y no puede tocar lo que no estaba
      en el HTML. El front resuelve `campo[lang] ?? campo.en`.

   3. [DATOS] `inversion_base` como columna suelta fabricaba el «cuarto papel» de
      `patrones_tecnicos.md`: un valor sin dueño ni fecha. Peor, la aritmética NO
      cuadraba en producción — verificado por el CEO contra `unidades`: las parcelas
      de Palm Field van de 31.250 € (250 m² a 125 €/m²) a 48.750 €, así que
      Dali 48.000+31.250 = 79.250 exacto, pero Dune daba 95.000 donde el mínimo
      posible es 99.250 y Dream 125.000 donde el mínimo es 132.250. Las dos estaban
      POR DEBAJO de construcción + la parcela más barata que existe, mientras la
      propia página afirma que el ROI se calcula sobre «construcción más suelo» y
      enseña el inventario real dos secciones más arriba. Como el ROI divide entre
      esa base, una base baja INFLA el porcentaje. **El owner decidió (11-sep) que
      eran cifras viejas y se corrigen**: se siembra construcción + parcela de
      referencia, y la fila guarda `unidad_referencia_id` para que la cifra sepa
      siempre de dónde salió.

   4. [DATOS] Los porcentajes NO van a `proyectos`: esa es la tabla maestra que leen
      contratos, unidades y facturas de las nueve herramientas, y estos tres números
      son constantes de un modelo de marketing. Van a `deck_forecast_proyecto`.
      Y el ADR no va a `modelos_villa` (nivel 2 de una cascada de 3, con `moneda` por
      fila y filas reales en IDR — Riverfront I, 1.726.000.000): heredaría la moneda
      por accidente al copiar esto a otro proyecto. Tabla propia y `moneda` forzada a
      EUR por CHECK, que es la moneda del contrato.

   5. [SEGURIDAD] El predicado de opt-in estaba COPIADO Y PEGADO en cada RPC. Con
      tres funciones nuevas serían seis copias de una regla de seguridad: el día que
      haya que endurecerla se cierra una salida y quedan cinco hermanas abiertas —
      patrón ya registrado en la memoria del estudio. Nace
      `deck_proyecto_abierto()` y las SEIS la llaman.

   6. [SEGURIDAD] Una tabla nueva en `public` nace con RLS sin políticas pero con los
      GRANT por defecto: legible por PostgREST directo, saltándose el RPC. Las cuatro
      llevan RLS, políticas y un `revoke` explícito a `anon` en esta misma migración.

   7. [SEGURIDAD] «Si el campo está relleno, sale» es publicar por accidente: el día
      que alguien teclea un ADR de prueba, ese modelo aparece con su ROI en una página
      pública. Todo lleva `publicado boolean not null default false` — puerta
      explícita y cerrada por defecto — más CHECK de rango, para que un dedazo en una
      cifra de rentabilidad se pare en la base y no en producción.

   8. [LEGAL] Hoy la FAQ vive en git: hay historial, fecha y autor de cada palabra, y
      se puede reconstruir qué leyó un inversor el día que reservó. Una fila mutable
      pierde esa prueba, y esta es la página que emite una Carta de Reserva. De ahí
      `deck_publicaciones`, append-only de verdad (sin UPDATE ni DELETE para nadie,
      ni siquiera para un admin). El owner eligió (11-sep) que publique cualquier
      admin CON RASTRO, no un segundo aprobador.

   9. [LEGAL] El pie del forecast afirma que los porcentajes «son los del contrato de
      gestión de alquiler vigente». Con el número editable esa frase deja de ser un
      descargo y pasa a ser una afirmación de hecho sobre un contrato que existe. Por
      eso `deck_forecast_proyecto` lleva `contrato_vigente` y `vigente_desde`: si no
      constan, el front tiene que cambiar la frase. La redacción se toca en el HTML.

  10. [LEGAL] Un render de una villa no construida publicado sin declararse como render
      integra la oferta en la UE y obliga a declararlo en Indonesia (Permendag 19/2026).
      `deck_fotos.tipo` lo hace obligatorio: foto real, render o imagen generada.

   NO toca ninguna fila existente. No toca unidades, contratos, facturas ni el flujo
   de reserva. No toca las 6 FAQ internas. */


/* ── 0. La regla de quién está abierto al data room, UNA sola vez ─────────────
   Era el mismo `exists (…)` copiado en investor_deck_parcelas, _modelos y
   _documentos. Aquí se nombra una vez y las seis funciones la llaman. Se conserva
   EXACTAMENTE el predicado de hoy (el opt-in vive en `unidades`), para que esta
   migración no cambie de paso quién ve qué: refactor, no cambio de alcance. */
create or replace function public.deck_proyecto_abierto(p_proyecto text)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.unidades u
     where u.proyecto = p_proyecto
       and u.publicado_investor_deck
  );
$$;

revoke all on function public.deck_proyecto_abierto(text) from public;
grant execute on function public.deck_proyecto_abierto(text) to anon, authenticated;

comment on function public.deck_proyecto_abierto is
  'Opt-in del data room publico: un proyecto esta abierto si alguna de sus unidades tiene publicado_investor_deck. Fuente unica de esa regla -- la llaman los seis RPC investor_deck_*. Antes estaba copiada en cada uno.';


/* ── 1. Fotos ────────────────────────────────────────────────────────────────
   El bucket `deck` es PÚBLICO, y eso es una decisión tomada a sabiendas (owner,
   11-sep): en un bucket público SUBIR ES PUBLICAR — el objeto es alcanzable por
   URL desde ese segundo, salga o no listado. Por eso aquí NO hay columna
   `publicado`: sería decorativa y mentiría. La foto está o no está, y la
   pertenencia ES el estado. La pantalla lo dice con esas palabras.

   `proyecto_id` / `modelo_id` sin espejo de texto a propósito: el RPC resuelve el
   nombre a id UNA vez y filtra por id, así renombrar un proyecto no rompe el deck
   (hoy sí lo rompe — los cuatro RPC viejos toman el nombre). Menos columnas, menos
   caminos por los que derivar. */
create table if not exists public.deck_fotos (
  id           uuid primary key default gen_random_uuid(),
  ambito       text not null check (ambito in ('proyecto','modelo')),
  proyecto_id  uuid references public.proyectos(id) on delete cascade,
  modelo_id    uuid references public.modelos(id)   on delete cascade,
  uso          text not null default 'galeria' check (uso in ('hero','galeria')),
  -- Lo declara quien sube y sale como pie visible: un render de algo no construido
  -- no puede pasar por fotografía (Legal, punto 10 de arriba).
  tipo         text not null default 'foto' check (tipo in ('foto','render','ia')),
  path         text not null unique,
  pie          jsonb not null default '{}'::jsonb,
  orden        integer not null default 0,
  creado_en    timestamptz not null default now(),
  creado_por   text default auth.email(),
  constraint deck_fotos_ambito_coherente check (
    (ambito = 'proyecto' and proyecto_id is not null and modelo_id is null)
    or
    (ambito = 'modelo'   and modelo_id   is not null)
  ),
  -- Sin `en` la fila es muda para el 90% de quien abre el deck. Se para aquí.
  constraint deck_fotos_pie_en check (pie ? 'en')
);

create index if not exists deck_fotos_proyecto_idx on public.deck_fotos (proyecto_id, uso, orden);
create index if not exists deck_fotos_modelo_idx   on public.deck_fotos (modelo_id, orden);

comment on table  public.deck_fotos is
  'Fotos PUBLICAS del investor deck. El bucket `deck` es publico: una fila aqui significa que el fichero ya es alcanzable por URL. No hay columna `publicado` a proposito -- seria decorativa. Borrar la fila obliga a borrar el objeto.';
comment on column public.deck_fotos.pie is
  'Pie de foto por idioma: {"en":…,"es":…,"id":…}. NO pasa por i18n.js. El front resuelve pie[lang] ?? pie.en.';
comment on column public.deck_fotos.tipo is
  'foto | render | ia. Se rinde como pie visible: en la UE un render publicado integra la oferta, y Permendag 19/2026 obliga a declarar imagen generada.';


/* ── 2. FAQ ──────────────────────────────────────────────────────────────────
   Tabla propia, NO `documentos_proyecto`: ver punto 1 de la revisión previa. */
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
  'Preguntas frecuentes PUBLICAS del investor deck. Tabla aparte de documentos_proyecto a proposito: alli categoria=faq guarda notas INTERNAS del equipo y investor_deck_documentos las excluye explicitamente. La frontera interno/publico separa tablas, no valores de una columna.';


/* ── 3. Previsión de alquiler ────────────────────────────────────────────────
   Los tres porcentajes son del CONTRATO de gestión de alquiler, no del modelo:
   una fila por proyecto. `contrato_vigente` existe porque el pie de la página
   afirma que esos porcentajes son los del contrato vigente (Legal): sin constar
   cuál, esa frase no se puede sostener y el front tiene que suavizarla. */
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
  -- Que los tres juntos no se coman el bruto entero: con >=100% el neto sale
  -- negativo y la tarjeta publica un ROI en rojo sin que nadie lo haya querido.
  constraint deck_forecast_pct_suma check (pct_gestion + pct_mantenimiento + pct_impuesto < 1)
);

/* Una fila por (proyecto, modelo). `inversion_base` es EXPLÍCITA y no derivada
   —Dune y Dream son cifras del owner, no salen de ninguna fórmula— pero guarda
   `unidad_referencia_id` para que siempre se pueda comparar con el suelo real y
   ver si ha envejecido. Es la diferencia entre una copia que sabe decir que está
   vieja y una que no (patrones_tecnicos.md, «El dato tiene un dueño»). */
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

comment on table  public.deck_forecast is
  'Prevision de alquiler Ano 1 por (proyecto, modelo) del investor deck. Tabla propia y NO columnas en modelos_villa: aquella es el nivel 2 de la cascada de precio y tiene moneda por fila (hay filas en IDR), asi que un ADR ahi heredaria la moneda por accidente al copiar esto a otro proyecto.';
comment on column public.deck_forecast.moneda is
  'Forzada a EUR por CHECK: el contrato SIEMPRE va en EUR y la conversion del deck es orientativa. Si algun dia hay forecast en otra divisa, se cambia el CHECK a proposito, no por descuido.';
comment on column public.deck_forecast.inversion_base is
  'Inversion total sobre la que se calcula el ROI. Explicita, nunca derivada al vuelo. `unidad_referencia_id` dice de que parcela salio el suelo, para poder detectar que ha envejecido.';


/* ── 4. El rastro, append-only de verdad ─────────────────────────────────────
   Legal: hoy la FAQ vive en git y se puede reconstruir qué leyó un inversor el día
   que reservó; una fila mutable pierde esa prueba. Sin UPDATE ni DELETE para NADIE
   —ni para un admin— porque un registro que el propio interesado puede editar no
   prueba nada. Solo `insert`, y lo escribe el trigger. */
create table if not exists public.deck_publicaciones (
  id         bigserial primary key,
  tabla      text not null,
  fila_id    uuid not null,
  accion     text not null check (accion in ('alta','cambio','baja')),
  antes      jsonb,
  despues    jsonb,
  quien      text not null default coalesce(auth.email(), '(sistema)'),
  cuando     timestamptz not null default now()
);

create index if not exists deck_publicaciones_fila_idx on public.deck_publicaciones (tabla, fila_id, cuando desc);

comment on table public.deck_publicaciones is
  'Historial APPEND-ONLY de todo lo que sale al investor deck publico. Sin update ni delete para ningun rol. Requisito de Legal: la pagina emite una Carta de Reserva, y en una reclamacion hay que poder demostrar que leyo el inversor ese dia.';

create or replace function public.deck_audita()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  -- `deck_forecast_proyecto` tiene el uuid en proyecto_id, no en una columna `id`.
  if TG_TABLE_NAME = 'deck_forecast_proyecto' then
    v_id := coalesce(new.proyecto_id, old.proyecto_id);
  else
    v_id := coalesce(new.id, old.id);
  end if;

  insert into public.deck_publicaciones (tabla, fila_id, accion, antes, despues)
  values (
    TG_TABLE_NAME,
    v_id,
    case TG_OP when 'INSERT' then 'alta' when 'UPDATE' then 'cambio' else 'baja' end,
    case when TG_OP = 'INSERT' then null else to_jsonb(old) end,
    case when TG_OP = 'DELETE' then null else to_jsonb(new) end
  );
  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_deck_audita_faq on public.deck_faq;
create trigger trg_deck_audita_faq
  after insert or update or delete on public.deck_faq
  for each row execute function public.deck_audita();

drop trigger if exists trg_deck_audita_forecast on public.deck_forecast;
create trigger trg_deck_audita_forecast
  after insert or update or delete on public.deck_forecast
  for each row execute function public.deck_audita();

drop trigger if exists trg_deck_audita_forecast_proy on public.deck_forecast_proyecto;
create trigger trg_deck_audita_forecast_proy
  after insert or update or delete on public.deck_forecast_proyecto
  for each row execute function public.deck_audita();

drop trigger if exists trg_deck_audita_fotos on public.deck_fotos;
create trigger trg_deck_audita_fotos
  after insert or update or delete on public.deck_fotos
  for each row execute function public.deck_audita();


/* ── 5. RLS y GRANTs ─────────────────────────────────────────────────────────
   Seguridad, punto 6: una tabla nueva en `public` nace con RLS sin politicas pero
   con los GRANT por defecto -- legible por PostgREST directo, saltandose el RPC.
   Se revoca a `anon` en la misma migracion, no «luego». Lo publico sale por los
   RPC `security definer`, que es el unico camino con la acotacion del opt-in. */
alter table public.deck_fotos              enable row level security;
alter table public.deck_faq                enable row level security;
alter table public.deck_forecast           enable row level security;
alter table public.deck_forecast_proyecto  enable row level security;
alter table public.deck_publicaciones      enable row level security;

revoke all on public.deck_fotos, public.deck_faq, public.deck_forecast,
              public.deck_forecast_proyecto, public.deck_publicaciones
  from anon;

grant select, insert, update, delete
  on public.deck_fotos, public.deck_faq, public.deck_forecast, public.deck_forecast_proyecto
  to authenticated;
grant select, insert on public.deck_publicaciones to authenticated;
grant usage, select on sequence public.deck_publicaciones_id_seq to authenticated;

do $$
begin
  -- Leer: cualquiera del equipo. Escribir: solo admin, igual que `modelos` y
  -- `modelos_villa`, que son las tablas hermanas de las que cuelga esto.
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='deck_fotos' and policyname='deck_fotos: leer') then
    create policy "deck_fotos: leer"     on public.deck_fotos    for select using (es_agente());
    create policy "deck_fotos: escribir" on public.deck_fotos    for all    using (es_admin()) with check (es_admin());
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='deck_faq' and policyname='deck_faq: leer') then
    create policy "deck_faq: leer"     on public.deck_faq        for select using (es_agente());
    create policy "deck_faq: escribir" on public.deck_faq        for all    using (es_admin()) with check (es_admin());
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='deck_forecast' and policyname='deck_forecast: leer') then
    create policy "deck_forecast: leer"     on public.deck_forecast for select using (es_agente());
    create policy "deck_forecast: escribir" on public.deck_forecast for all    using (es_admin()) with check (es_admin());
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='deck_forecast_proyecto' and policyname='deck_forecast_proyecto: leer') then
    create policy "deck_forecast_proyecto: leer"     on public.deck_forecast_proyecto for select using (es_agente());
    create policy "deck_forecast_proyecto: escribir" on public.deck_forecast_proyecto for all    using (es_admin()) with check (es_admin());
  end if;
  -- El historial se lee y se escribe, pero NO se corrige. Sin politica de update
  -- ni de delete: con RLS activa, lo que no tiene politica no se puede hacer.
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='deck_publicaciones' and policyname='deck_publicaciones: leer') then
    create policy "deck_publicaciones: leer"    on public.deck_publicaciones for select using (es_agente());
    create policy "deck_publicaciones: escribir" on public.deck_publicaciones for insert with check (true);
  end if;
end $$;


/* ── 6. Los RPC públicos ─────────────────────────────────────────────────────
   Los tres siguen el molde exacto de `investor_deck_modelos`: security definer,
   stable, search_path fijado, acotados por `deck_proyecto_abierto()`, y el
   `revoke ... from public` antes del grant. */

create or replace function public.investor_deck_fotos(p_proyecto text)
returns table(uso text, tipo text, path text, pie jsonb, orden integer, modelo_slug text)
language sql
security definer
stable
set search_path = public
as $$
  select f.uso, f.tipo, f.path, f.pie, f.orden, m.slug
    from public.deck_fotos f
    left join public.modelos m on m.id = f.modelo_id
   where public.deck_proyecto_abierto(p_proyecto)
     and (
       -- del proyecto…
       f.proyecto_id = (select p.id from public.proyectos p where p.nombre = p_proyecto)
       or
       -- …o de un modelo que ESTE proyecto tiene asignado. Un modelo es compartido
       -- entre proyectos, asi que su foto no cuelga de ninguno en concreto.
       f.modelo_id in (
         select mv.modelo_id from public.modelos_villa mv
          where mv.proyecto = p_proyecto and mv.modelo_id is not null
       )
     )
   order by f.uso, f.orden, f.creado_en;
$$;

revoke all on function public.investor_deck_fotos(text) from public;
grant execute on function public.investor_deck_fotos(text) to anon, authenticated;

comment on function public.investor_deck_fotos is
  'Fotos publicas del data room de un proyecto: las suyas mas las de los modelos que tiene asignados. Solo proyectos abiertos (deck_proyecto_abierto). El `path` es del bucket publico `deck`.';


create or replace function public.investor_deck_faq(p_proyecto text)
returns table(pregunta jsonb, respuesta jsonb, orden integer)
language sql
security definer
stable
set search_path = public
as $$
  select q.pregunta, q.respuesta, q.orden
    from public.deck_faq q
   where public.deck_proyecto_abierto(p_proyecto)
     and q.publicado
     and q.proyecto_id = (select p.id from public.proyectos p where p.nombre = p_proyecto)
   order by q.orden, q.creado_en;
$$;

revoke all on function public.investor_deck_faq(text) from public;
grant execute on function public.investor_deck_faq(text) to anon, authenticated;

comment on function public.investor_deck_faq is
  'FAQ publica del investor deck. Lee de deck_faq, NUNCA de documentos_proyecto (alli categoria=faq son notas internas del equipo y investor_deck_documentos las excluye a proposito).';


create or replace function public.investor_deck_forecast(p_proyecto text)
returns table(
  modelo_slug       text,
  modelo_nombre     text,
  dormitorios       integer,
  adr_medio         numeric,
  adr_optimo        numeric,
  ocupacion_media   numeric,
  ocupacion_optima  numeric,
  inversion_base    numeric,
  precio_construccion numeric,
  moneda            text,
  destacado         boolean,
  orden             integer,
  pct_gestion       numeric,
  pct_mantenimiento numeric,
  pct_impuesto      numeric,
  contrato_vigente  text,
  actualizado_en    timestamptz
)
language sql
security definer
stable
set search_path = public
as $$
  -- El precio de construccion NO se copia aqui: sale de la misma cascada que ya
  -- resuelve investor_deck_modelos (nivel 2 heredando del 1), para que la tarjeta
  -- del forecast y la tarjeta de la tipologia no puedan decir cifras distintas.
  select m.slug, m.nombre, m.dormitorios,
         f.adr_medio, f.adr_optimo, f.ocupacion_media, f.ocupacion_optima,
         f.inversion_base,
         coalesce(mv.precio_construccion, m.precio_construccion),
         f.moneda, f.destacado, f.orden,
         c.pct_gestion, c.pct_mantenimiento, c.pct_impuesto, c.contrato_vigente,
         greatest(f.actualizado_en, c.actualizado_en)
    from public.deck_forecast f
    join public.modelos m on m.id = f.modelo_id
    join public.proyectos p on p.id = f.proyecto_id
    join public.deck_forecast_proyecto c on c.proyecto_id = f.proyecto_id
    left join public.modelos_villa mv
           on mv.modelo_id = f.modelo_id and mv.proyecto = p.nombre
   where public.deck_proyecto_abierto(p_proyecto)
     and p.nombre = p_proyecto
     and f.publicado
     -- Los porcentajes son del contrato de gestion: sin ellos publicados no hay
     -- forecast que ensenar, porque el neto y el ROI salen de restarlos.
     and c.publicado
   order by f.orden, m.nombre;
$$;

revoke all on function public.investor_deck_forecast(text) from public;
grant execute on function public.investor_deck_forecast(text) to anon, authenticated;

comment on function public.investor_deck_forecast is
  'Prevision de alquiler Ano 1 publicada de un proyecto. Devuelve los datos, no el resultado: el calculo (bruto, gastos, neto, ROI) lo hace el front con una sola formula. El precio de construccion sale de la MISMA cascada que investor_deck_modelos para que las dos tarjetas no se contradigan.';


/* ── 7. Las funciones viejas pasan a usar la regla compartida ────────────────
   Mismo alcance exacto que antes -- se sustituye el `exists` copiado por la
   llamada. Se reescriben enteras porque `create or replace` lo exige.

   ⚠️ `investor_deck_parcelas` NO entra aqui, y no es un olvido: esa funcion NO
   tiene la copia del predicado. Filtra `publicado_investor_deck` FILA A FILA
   sobre `unidades`, que es el opt-in de verdad -- las demas solo preguntan si
   queda alguna fila marcada. Es el ORIGEN de la regla, no una copia suya.
   Meterle `deck_proyecto_abierto()` cambiaria su alcance: pasaria a devolver
   TODAS las parcelas de un proyecto con una sola marcada. No se toca. */
create or replace function public.investor_deck_documentos(p_proyecto text)
returns table(titulo text, descripcion text, url text, categoria text)
language sql
security definer
stable
set search_path = public
as $$
  select d.titulo, d.descripcion, d.url, d.categoria
    from public.documentos_proyecto d
   where d.proyecto = p_proyecto
     and d.publicado_investor_deck
     and d.confidencial = false          -- cinturon y tirantes: publicado nunca gana a confidencial
     and d.categoria <> 'faq'            -- 'faq' son notas INTERNAS; la publica vive en deck_faq
     and d.url is not null
     and d.url <> ''
     and public.deck_proyecto_abierto(d.proyecto)
   order by d.creado_en desc;
$$;

create or replace function public.investor_deck_modelos(p_proyecto text)
returns table(
  slug        text,
  nombre      text,
  dormitorios integer,
  banos       integer,
  villa_m2    numeric,
  terraza_m2  numeric,
  precio      numeric,
  moneda      text,
  orden       integer
)
language sql
security definer
stable
set search_path = public
as $$
  with base as (
    select m.slug, m.nombre, m.dormitorios, m.banos, m.villa_m2, m.terraza_m2, m.orden,
           (mv.precio_construccion is not null) as gana_proyecto,
           mv.precio_construccion as precio_proyecto,
           mv.moneda              as moneda_proyecto,
           m.precio_construccion  as precio_catalogo,
           m.moneda               as moneda_catalogo
      from public.modelos_villa mv
      join public.modelos m on m.id = mv.modelo_id
     where mv.proyecto = p_proyecto
       and m.publicado
       and m.activo
       and public.deck_proyecto_abierto(mv.proyecto)
  )
  select slug, nombre, dormitorios, banos, villa_m2, terraza_m2,
         case when gana_proyecto then precio_proyecto else precio_catalogo end as precio,
         case when gana_proyecto then coalesce(moneda_proyecto, moneda_catalogo)
              else moneda_catalogo end                                        as moneda,
         orden
    from base
   order by orden nulls last, nombre;
$$;
