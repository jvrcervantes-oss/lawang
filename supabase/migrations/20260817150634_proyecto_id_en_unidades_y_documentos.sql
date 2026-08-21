-- ═══════════════════════════════════════════════════════════════════════════
--  El proyecto deja de ser un TEXTO suelto — 17-ago-2026
--  ---------------------------------------------------------------------------
--  `unidades.proyecto` y `documentos_proyecto.proyecto` guardaban el NOMBRE del
--  proyecto en texto, sin ninguna clave que los uniera a `proyectos`. O sea que
--  renombrar un proyecto dejaba sus unidades y sus documentos huerfanos EN
--  SILENCIO: nada fallaba, simplemente dejaban de encontrarse.
--
--  Es la ficha LAW-36, abierta el 11-ago, y ya habia enseñado la oreja: hay 3
--  documentos colgando de «Lawang (general)», un nombre que no existe en
--  `proyectos`. Ahi es deliberado —es una carpeta general, no un proyecto— y por
--  eso `proyecto_id` admite NULL: NULL significa exactamente eso, «no cuelga de
--  ningun proyecto».
--
--  POR QUE NO SE BORRA LA COLUMNA DE TEXTO. La leen muchos sitios (Proyectos,
--  Obra, Documentacion, el portal, Operaciones y el propio generador de
--  contratos). Quitarla de golpe seria cambiar decenas de consultas a la vez, que
--  es justo como se rompen las cosas. En vez de eso, la base la MANTIENE:
--    · al escribir una unidad o un documento, el id se resuelve solo desde el
--      nombre, asi que el codigo que ya existe no se entera de nada;
--    · al RENOMBRAR un proyecto, el nombre se propaga a todas sus filas.
--  El texto pasa a ser un reflejo del vinculo, no la fuente.
-- ═══════════════════════════════════════════════════════════════════════════

alter table public.unidades
  add column if not exists proyecto_id uuid references public.proyectos(id) on delete set null;
alter table public.documentos_proyecto
  add column if not exists proyecto_id uuid references public.proyectos(id) on delete set null;

create index if not exists unidades_proyecto_id_idx   on public.unidades(proyecto_id);
create index if not exists documentos_proyecto_id_idx on public.documentos_proyecto(proyecto_id);

comment on column public.unidades.proyecto_id is
  'Proyecto al que pertenece. La columna `proyecto` (texto) es un reflejo que la base mantiene sola.';
comment on column public.documentos_proyecto.proyecto_id is
  'Proyecto al que pertenece, NULL si es documentacion general que no cuelga de ninguno.';

-- ── Relleno inicial, por nombre ────────────────────────────────────────────
update public.unidades u set proyecto_id = p.id
  from public.proyectos p where p.nombre = u.proyecto and u.proyecto_id is null;
update public.documentos_proyecto d set proyecto_id = p.id
  from public.proyectos p where p.nombre = d.proyecto and d.proyecto_id is null;

-- ── Al escribir: el id se resuelve solo desde el nombre ────────────────────
create or replace function public.resuelve_proyecto_id()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Solo se toca si hace falta: fila nueva, nombre cambiado, o id vacio. Asi el
  -- renombrado (que escribe el texto desde el otro trigger) no se pisa a si mismo.
  if new.proyecto is distinct from coalesce(old.proyecto, null) or new.proyecto_id is null then
    select p.id into new.proyecto_id from public.proyectos p where p.nombre = new.proyecto;
  end if;
  return new;
end $$;

drop trigger if exists unidades_resuelve_proyecto on public.unidades;
create trigger unidades_resuelve_proyecto
  before insert or update of proyecto, proyecto_id on public.unidades
  for each row execute function public.resuelve_proyecto_id();

drop trigger if exists documentos_resuelve_proyecto on public.documentos_proyecto;
create trigger documentos_resuelve_proyecto
  before insert or update of proyecto, proyecto_id on public.documentos_proyecto
  for each row execute function public.resuelve_proyecto_id();

-- ── Al renombrar un proyecto: el nombre baja a todas sus filas ─────────────
create or replace function public.propaga_nombre_proyecto()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.nombre is distinct from old.nombre then
    update public.unidades            set proyecto = new.nombre where proyecto_id = new.id;
    update public.documentos_proyecto set proyecto = new.nombre where proyecto_id = new.id;
  end if;
  return new;
end $$;

drop trigger if exists proyectos_propaga_nombre on public.proyectos;
create trigger proyectos_propaga_nombre
  after update of nombre on public.proyectos
  for each row execute function public.propaga_nombre_proyecto();;
