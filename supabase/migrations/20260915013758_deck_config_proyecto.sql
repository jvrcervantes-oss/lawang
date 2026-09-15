-- destructivo-ok: el unico DROP es `drop trigger if exists` justo antes de
-- recrearlo -- idempotencia para poder reaplicar la migracion, no retirada de
-- nada (el trigger NACE en este mismo fichero, mismo patron que las 4 tablas
-- deck_* de 20260911180000_deck_contenido_intranet.sql). Ninguna fila
-- existente se toca: solo se crea una tabla nueva y sus policies/trigger.
--
-- Investor Deck multi-proyecto (15-sep-2026) -- pieza 2/4.
-- Config por proyecto que hoy vive clavada a mano en el HTML de Palm Field
-- (titulo, meta description, modelo destacado) y que hace falta para poder
-- generalizar la plantilla a cualquier proyecto. Mismo molde EXACTO que
-- `deck_forecast_proyecto` (20260911180000_deck_contenido_intranet.sql):
-- proyecto_id como PK, RLS activa, revoke a anon, policy leer=es_agente(),
-- escribir=es_admin(), trigger deck_audita() ya existente (append-only en
-- deck_publicaciones).
--
-- Decision de Diseno en la revision previa, aplicada aqui: nunca placeholders.
-- `titulo`/`meta_desc` son NOT NULL (con CHECK ? 'en') porque una pagina
-- publica sin titulo no es aceptable; `kpis` es NULLABLE a proposito -- si un
-- proyecto no tiene sus KPIs reales cargados, esa fila de la cabecera
-- simplemente no se pinta (nunca los 4 KPIs de Palm Field reciclados).
-- `masterplan_activo` nace en `false`: el plano interactivo es trabajo manual
-- por proyecto (coordenadas medidas a mano sobre la imagen de CADA masterplan,
-- ver ZONAS en investor-deck/palmfield/index.html) y no se puede derivar solo.

create table if not exists public.deck_config_proyecto (
  proyecto_id         uuid primary key references public.proyectos(id) on delete cascade,
  titulo               jsonb not null check (titulo ? 'en'),
  meta_desc            jsonb not null check (meta_desc ? 'en'),
  tipo_venta           text not null default 'parcela' check (tipo_venta in ('parcela','villa','desarrollo')),
  modelo_destacado_id  uuid references public.modelos(id),
  masterplan_activo    boolean not null default false,
  masterplan_imagen    text,
  kpis                 jsonb,
  actualizado_en       timestamptz not null default now(),
  actualizado_por      text default auth.email()
);

comment on table public.deck_config_proyecto is
  'Config del Investor Deck genérico por proyecto (título, meta, modelo destacado, KPIs, plano). Nace vacía por proyecto: sin fila aquí, ese proyecto no tiene deck que activar (la intranet debe bloquear el botón "Activar" hasta que exista).';
comment on column public.deck_config_proyecto.titulo is 'jsonb {"en":...,"es":...,"id":...}. NO pasa por i18n.js -- el front resuelve titulo[lang] ?? titulo.en, mismo patrón que deck_faq/deck_fotos.';
comment on column public.deck_config_proyecto.kpis is 'Array opcional [{"label":{"en":...},"valor":{"en":...}}, ...]. NULL o vacío = esa fila de la cabecera no se pinta. Nunca se rellena con los KPIs de Palm Field ni con cifras inventadas -- son hechos verificables de CADA proyecto.';
comment on column public.deck_config_proyecto.masterplan_activo is 'false por defecto: el plano interactivo (imagen + coordenadas medidas a mano) es trabajo manual por proyecto, no derivable de una plantilla. Con esto en false el deck genérico muestra igualmente la lista de parcelas en vivo (investor_deck_parcelas, que no depende de coordenadas), solo oculta la imagen+hotspots.';

alter table public.deck_config_proyecto enable row level security;
revoke all on public.deck_config_proyecto from anon;
grant select, insert, update, delete on public.deck_config_proyecto to authenticated;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='deck_config_proyecto' and policyname='deck_config_proyecto: leer') then
    create policy "deck_config_proyecto: leer"     on public.deck_config_proyecto for select using (es_agente());
    create policy "deck_config_proyecto: escribir" on public.deck_config_proyecto for all    using (es_admin()) with check (es_admin());
  end if;
end $$;

drop trigger if exists trg_deck_audita_config_proyecto on public.deck_config_proyecto;
create trigger trg_deck_audita_config_proyecto
  after insert or update or delete on public.deck_config_proyecto
  for each row execute function public.deck_audita();
