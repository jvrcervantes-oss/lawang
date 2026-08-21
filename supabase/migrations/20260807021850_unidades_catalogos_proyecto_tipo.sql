-- destructivo-ok: DROP CONSTRAINT sustituye un CHECK de 4 valores por un FK
-- equivalente (unidades_tipo_fkey -> tipos_vivienda), mismo patron que
-- obra_fase; verificado por Infraestructura como metadata-only, sin tocar
-- ninguna fila de datos (revision previa de esta sesion). Las clausulas
-- "for update using" son de RLS policies, no UPDATE de filas.
create table public.proyectos (
  id uuid primary key default gen_random_uuid(),
  nombre text not null unique,
  activo boolean not null default true,
  creado_en timestamptz not null default now(),
  creado_por text default auth.email()
);

create table public.tipos_vivienda (
  clave text primary key,
  etiqueta text not null,
  activo boolean not null default true
);

insert into public.proyectos (nombre) values
  ('Bonian Village by Balian Hills'),
  ('Palm Field by Balian Hills'),
  ('Horizon by Balian Hills'),
  ('Horizon S2 by Balian Hills'),
  ('Mejan by Balian Hills'),
  ('Tamarind Rise by Balian Hills'),
  ('Sumba Hills by SandalWoods')
on conflict (nombre) do nothing;

insert into public.tipos_vivienda (clave, etiqueta) values
  ('parcela', 'Parcela'),
  ('villa', 'Villa'),
  ('apartamento', 'Apartamento'),
  ('local', 'Local')
on conflict (clave) do nothing;

alter table public.unidades alter column proyecto set not null;

alter table public.unidades drop constraint unidades_tipo_check;
alter table public.unidades add constraint unidades_tipo_fkey
  foreign key (tipo) references public.tipos_vivienda(clave);

alter table public.proyectos enable row level security;
alter table public.tipos_vivienda enable row level security;

create policy "agentes leen proyectos" on public.proyectos
  for select using (es_agente());
create policy "agentes dan de alta proyectos" on public.proyectos
  for insert with check (es_agente() and puede('unidades'));
create policy "admin desactiva proyectos" on public.proyectos
  for update using (es_admin()) with check (es_admin());

create policy "agentes leen tipos_vivienda" on public.tipos_vivienda
  for select using (es_agente());
create policy "agentes dan de alta tipos_vivienda" on public.tipos_vivienda
  for insert with check (es_agente() and puede('unidades'));
create policy "admin desactiva tipos_vivienda" on public.tipos_vivienda
  for update using (es_admin()) with check (es_admin());
;
