/* CATÁLOGO DE MODELOS DE VIVIENDA — 7-sep-2026.
   Detalle, porqués y la cascada de precio explicada: el fichero canónico
   supabase/migrations/20260907190000_catalogo_de_modelos.sql

   -- destructivo-ok: NADA de esta migración borra datos. Los tres patrones que
   marca el freno son de forma, y son estos tres, ninguno más:
     1. `drop policy if exists` sobre políticas que se crean dos líneas más
        abajo — patrón estándar de "create or replace" para políticas, que
        Postgres no soporta directamente. Todas son NOMBRES NUEVOS: hoy no
        existe ninguna, así que el drop no quita nada. Se dejan para que la
        migración se pueda volver a correr entera sin fallar por duplicado.
     2. `drop trigger if exists` — lo mismo, y también nombres nuevos
        (trg_espejo_modelo, trg_modelo_renombrado).
     3. "UPDATE sin WHERE": es `create trigger ... AFTER UPDATE OF nombre`, la
        cláusula DDL que declara CUÁNDO dispara el trigger. No es una sentencia
        UPDATE sobre filas. Los dos UPDATE reales que hay (dentro de
        trg_modelo_renombrado) van acotados por `where modelo_id = new.id`.
   Todo lo demás es CREATE TABLE / ADD COLUMN / CREATE POLICY / CREATE FUNCTION.
   No se toca ni una fila de `unidades`: el enganche va en la migración
   siguiente, a propósito y por separado. */

create table if not exists public.modelos (
  id                  uuid primary key default gen_random_uuid(),
  slug                text not null unique,
  nombre              text not null,
  dormitorios         integer,
  banos               integer,
  villa_m2            numeric,
  terraza_m2          numeric,
  descripcion         text,
  precio_construccion numeric,
  moneda              text not null default 'EUR',
  publicado           boolean not null default false,
  activo              boolean not null default true,
  renders_pendientes  boolean not null default false,
  orden               integer,
  notas               text,
  creado_en           timestamptz not null default now(),
  actualizado_en      timestamptz not null default now()
);

comment on table public.modelos is
  'Catálogo de tipos de vivienda. FUENTE: el modelo se da de alta y se corrige aquí y solo aquí. unidades.modelo_id y modelos_villa.modelo_id lo referencian; modelo/modelos.php de la web lo lee por el RPC catalogo_publico().';
comment on column public.modelos.precio_construccion is
  'Nivel 1 de la cascada de precio. Un NULL en modelos_villa.precio_construccion hereda de aquí; un valor allí lo pisa para ese proyecto; y lo escrito en unidades.precio_construccion manda sobre los dos.';
comment on column public.modelos.notas is
  'Interno del equipo. Excluida a propósito del RPC publico (catalogo_publico): la web no la ve.';

create index if not exists modelos_publicado_idx on public.modelos (publicado, orden);

alter table public.modelos enable row level security;
drop policy if exists "modelos: leer"    on public.modelos;
drop policy if exists "modelos: escribir" on public.modelos;
create policy "modelos: leer" on public.modelos
  for select to authenticated using (public.es_agente());
create policy "modelos: escribir" on public.modelos
  for all to authenticated using (public.es_admin()) with check (public.es_admin());

create table if not exists public.modelo_techos (
  id            uuid primary key default gen_random_uuid(),
  modelo_id     uuid not null references public.modelos(id) on delete cascade,
  clave         text not null,
  nombre        text not null,
  descripcion   text,
  precio_ahora  numeric,
  precio_2027   numeric,
  orden         integer,
  unique (modelo_id, clave)
);

comment on table public.modelo_techos is
  'Variantes de techo de un modelo. precio_ahora/precio_2027 son precios COMPLETOS del modelo con ese techo, no un recargo. El corte lo resuelve el reloj del SERVIDOR, nunca un flag manual ni la fecha del visitante.';

alter table public.modelo_techos enable row level security;
drop policy if exists "techos: leer"    on public.modelo_techos;
drop policy if exists "techos: escribir" on public.modelo_techos;
create policy "techos: leer" on public.modelo_techos
  for select to authenticated using (public.es_agente());
create policy "techos: escribir" on public.modelo_techos
  for all to authenticated using (public.es_admin()) with check (public.es_admin());

create table if not exists public.extras (
  id          uuid primary key default gen_random_uuid(),
  clave       text not null unique,
  nombre      text not null,
  descripcion text,
  orden       integer,
  activo      boolean not null default true
);

create table if not exists public.modelo_extras (
  id         uuid primary key default gen_random_uuid(),
  modelo_id  uuid not null references public.modelos(id) on delete cascade,
  extra_id   uuid not null references public.extras(id)  on delete cascade,
  precio     numeric,
  moneda     text not null default 'EUR',
  disponible boolean not null default true,
  unique (modelo_id, extra_id)
);

comment on table public.extras is
  'Catálogo de opcionales. Nombre y descripción viven aquí UNA vez porque son iguales para todos los modelos; el precio nunca, que va en modelo_extras.';

alter table public.extras        enable row level security;
alter table public.modelo_extras enable row level security;
drop policy if exists "extras: leer"     on public.extras;
drop policy if exists "extras: escribir" on public.extras;
drop policy if exists "modelo_extras: leer"     on public.modelo_extras;
drop policy if exists "modelo_extras: escribir" on public.modelo_extras;
create policy "extras: leer" on public.extras
  for select to authenticated using (public.es_agente());
create policy "extras: escribir" on public.extras
  for all to authenticated using (public.es_admin()) with check (public.es_admin());
create policy "modelo_extras: leer" on public.modelo_extras
  for select to authenticated using (public.es_agente());
create policy "modelo_extras: escribir" on public.modelo_extras
  for all to authenticated using (public.es_admin()) with check (public.es_admin());

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('modelos', 'modelos', false, 52428800,
        array['application/pdf','image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

create table if not exists public.modelo_documentos (
  id            uuid primary key default gen_random_uuid(),
  modelo_id     uuid not null references public.modelos(id) on delete cascade,
  nombre        text not null,
  path          text not null unique,
  tipo          text not null default 'otro',
  visible_portal boolean not null default false,
  tamano_bytes  bigint,
  subido_por    uuid,
  subido_en     timestamptz not null default now(),
  constraint modelo_documentos_tipo_ck
    check (tipo in ('plano','calidades','ficha','render','otro'))
);

comment on column public.modelo_documentos.path is
  'Ruta dentro del bucket modelos. Es un uuid: el nombre real del fichero vive en `nombre`, nunca en la ruta.';

create index if not exists modelo_documentos_modelo_idx on public.modelo_documentos (modelo_id);

alter table public.modelo_documentos enable row level security;
drop policy if exists "modelo_docs: leer"    on public.modelo_documentos;
drop policy if exists "modelo_docs: escribir" on public.modelo_documentos;
create policy "modelo_docs: leer" on public.modelo_documentos
  for select to authenticated using (public.es_agente());
create policy "modelo_docs: escribir" on public.modelo_documentos
  for all to authenticated using (public.es_agente()) with check (public.es_agente());

drop policy if exists "modelos bucket: leer"   on storage.objects;
drop policy if exists "modelos bucket: subir"  on storage.objects;
drop policy if exists "modelos bucket: borrar" on storage.objects;
create policy "modelos bucket: leer" on storage.objects
  for select to authenticated using (bucket_id = 'modelos' and public.es_agente());
create policy "modelos bucket: subir" on storage.objects
  for insert to authenticated with check (bucket_id = 'modelos' and public.es_agente());
create policy "modelos bucket: borrar" on storage.objects
  for delete to authenticated using (bucket_id = 'modelos' and public.es_admin());

alter table public.modelos_villa add column if not exists modelo_id   uuid references public.modelos(id) on delete cascade;
alter table public.modelos_villa add column if not exists proyecto_id uuid references public.proyectos(id) on delete cascade;
create index if not exists modelos_villa_modelo_idx   on public.modelos_villa (modelo_id);
create index if not exists modelos_villa_proyecto_idx on public.modelos_villa (proyecto_id);

comment on table public.modelos_villa is
  'Nivel 2 de la cascada de precio: lo que cuesta construir un modelo EN un proyecto concreto. precio_construccion NULL significa «hereda del catálogo», no «sin dato». Las columnas de texto proyecto y modelo son ESPEJOS de los enlaces.';
comment on column public.modelos_villa.precio_construccion is
  'NULL = hereda modelos.precio_construccion. Solo se rellena cuando este proyecto tiene un precio propio pactado, distinto del de catálogo.';

create or replace function public.modelo_norm(txt text)
returns text
language sql
immutable
set search_path = ''
as $$
  select nullif(btrim(lower(translate(coalesce(txt,''),
                                      'áéíóúàèìòùäëïöüâêîôûÁÉÍÓÚÀÈÌÒÙÄËÏÖÜÂÊÎÔÛ',
                                      'aeiouaeiouaeiouaeiouAEIOUAEIOUAEIOUAEIOU'))), '')
$$;

create or replace function public.trg_espejo_modelo()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_nombre text;
begin
  if new.modelo_id is null and public.modelo_norm(new.modelo) is not null then
    select m.id into new.modelo_id
      from public.modelos m
     where public.modelo_norm(m.nombre) = public.modelo_norm(new.modelo)
     limit 1;
  end if;

  if new.modelo_id is not null then
    select m.nombre into v_nombre from public.modelos m where m.id = new.modelo_id;
    if v_nombre is not null then new.modelo := v_nombre; end if;
  end if;
  return new;
end $$;

revoke all on function public.trg_espejo_modelo() from public, anon, authenticated;
revoke all on function public.modelo_norm(text)   from public, anon;

alter table public.unidades add column if not exists modelo_id uuid references public.modelos(id);
create index if not exists unidades_modelo_idx on public.unidades (modelo_id);

comment on column public.unidades.modelo_id is
  'Referencia al catálogo. modelo (texto) es su ESPEJO: se reescribe desde aquí en cada guardado. Si es null, la unidad nombra un modelo que no está en el catálogo — huérfano VISIBLE en la vista modelos_sin_catalogar, no silencioso.';

drop trigger if exists trg_espejo_modelo on public.unidades;
create trigger trg_espejo_modelo
before insert or update of modelo_id, modelo on public.unidades
for each row execute function public.trg_espejo_modelo();

drop trigger if exists trg_espejo_modelo on public.modelos_villa;
create trigger trg_espejo_modelo
before insert or update of modelo_id, modelo on public.modelos_villa
for each row execute function public.trg_espejo_modelo();

create or replace function public.trg_modelo_renombrado()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.nombre is not distinct from old.nombre then return new; end if;
  update public.unidades      set modelo = new.nombre where modelo_id = new.id;
  update public.modelos_villa set modelo = new.nombre where modelo_id = new.id;
  return new;
end $$;

revoke all on function public.trg_modelo_renombrado() from public, anon, authenticated;

drop trigger if exists trg_modelo_renombrado on public.modelos;
create trigger trg_modelo_renombrado after update of nombre on public.modelos
for each row execute function public.trg_modelo_renombrado();

create or replace function public.modelo_precio_construccion(p_modelo_id uuid, p_proyecto_id uuid default null)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select mv.precio_construccion from public.modelos_villa mv
      where mv.modelo_id = p_modelo_id and mv.proyecto_id = p_proyecto_id
        and mv.precio_construccion is not null),
    (select m.precio_construccion from public.modelos m where m.id = p_modelo_id)
  )
$$;

revoke all on function public.modelo_precio_construccion(uuid, uuid) from public, anon;
grant execute on function public.modelo_precio_construccion(uuid, uuid) to authenticated;

create or replace view public.modelos_sin_catalogar as
select u.proyecto,
       u.modelo                       as nombra_a,
       count(*)                       as unidades,
       count(u.contrato_id)           as con_contrato,
       min(u.precio_construccion)     as precio_min,
       max(u.precio_construccion)     as precio_max
  from public.unidades u
 where public.modelo_norm(u.modelo) is not null
   and u.modelo_id is null
 group by 1, 2;

alter view public.modelos_sin_catalogar set (security_invoker = true);
grant select on public.modelos_sin_catalogar to authenticated;

comment on view public.modelos_sin_catalogar is
  'Unidades que nombran un modelo sin enlace al catálogo. Al cerrar esta migración las únicas ahí dentro son, a propósito, las 81 de Sumba Hills bajo «Dream»: dos bloques con precio distinto (109.000 y 95.000) que el owner decidió el 7-sep revisar con el cliente antes de unificar.';

create or replace function public.catalogo_publico()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(x.slug, x.ficha), '{}'::jsonb)
    from (
      select m.slug,
             jsonb_strip_nulls(jsonb_build_object(
               'nombre',             m.nombre,
               'dormitorios',        m.dormitorios,
               'banos',              m.banos,
               'villa_m2',           m.villa_m2,
               'terraza_m2',         m.terraza_m2,
               'sub',                m.descripcion,
               'moneda',             m.moneda,
               'desde',              m.precio_construccion,
               'renders_pendientes', nullif(m.renders_pendientes, false),
               'techos', (select jsonb_object_agg(t.clave, jsonb_build_object(
                                   'nombre', t.nombre, 'desc', t.descripcion,
                                   'now',    t.precio_ahora, 'y2027', t.precio_2027))
                            from public.modelo_techos t where t.modelo_id = m.id),
               'extras', (select jsonb_object_agg(e.clave, me.precio)
                            from public.modelo_extras me
                            join public.extras e on e.id = me.extra_id
                           where me.modelo_id = m.id and me.disponible and e.activo)
             )) as ficha
        from public.modelos m
       where m.publicado and m.activo
    ) x
$$;

revoke all on function public.catalogo_publico() from public;
grant execute on function public.catalogo_publico() to anon, authenticated;

comment on function public.catalogo_publico() is
  'Lo único del catálogo que ve un anónimo: modelos publicados, con specs, techos y extras. Nunca notas, ni precios por proyecto (modelos_villa), ni nada de unidades. Declarada en departamentos/seguridad/rls_publico.txt.';;
