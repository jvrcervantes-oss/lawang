-- destructivo-ok: los "drop policy if exists" de abajo son el patron estandar
-- del repo para poder re-ejecutar la migracion sin fallar por nombre
-- duplicado -- los nombres de policy son NUEVOS (equipos_venta/equipo_miembros
-- se crean en este mismo fichero), hoy no existe ninguno, asi que el drop no
-- quita nada real. No hay ningun otro DROP/DELETE/UPDATE-sin-WHERE en este SQL.

create table if not exists public.equipos_venta (
  id             uuid primary key default gen_random_uuid(),
  nombre         text not null,
  manager_email  text not null,
  activo         boolean not null default true,
  created_at     timestamptz not null default now()
);

comment on table public.equipos_venta is
  'Equipos de venta (closers agrupados bajo un manager) para el reparto/atribución de comisiones. Quién ve qué detalle fino se resuelve en otra subtarea del mismo encargo; aquí la tabla es legible por cualquier authenticated y solo admin/super_admin la escribe.';
comment on column public.equipos_venta.manager_email is
  'Email del manager del equipo. Texto libre a propósito (igual que equipo_miembros.closer_email): sin FK a usuarios, para no bloquear el alta de un equipo cuyo manager aún no tiene ficha en la intranet.';

create table if not exists public.equipo_miembros (
  id            uuid primary key default gen_random_uuid(),
  equipo_id     uuid not null references public.equipos_venta(id) on delete cascade,
  closer_email  text not null,
  desde         date not null default current_date,
  hasta         date,
  added_by      text,
  created_at    timestamptz not null default now()
);

comment on table public.equipo_miembros is
  'Quién (closer_email) perteneció/pertenece a qué equipo y en qué ventana (desde/hasta). hasta NULL = sigue activo en el equipo hoy. Sin UNIQUE sobre (equipo_id, closer_email): qué pasa si el mismo closer aparece dos veces "activo" es una regla de negocio de otra subtarea, no de esta.';
comment on column public.equipo_miembros.id is
  'default gen_random_uuid() añadido por consistencia: todo uuid primary key de este esquema lo lleva (incluida equipos_venta, dos líneas más arriba). El encargo original no repitió el default para esta columna; se asume el mismo patrón que el resto del repo en vez de dejar una tabla sin forma de insertar sin generar el id a mano.';

create index if not exists equipo_miembros_equipo_idx  on public.equipo_miembros (equipo_id);
create index if not exists equipo_miembros_closer_idx  on public.equipo_miembros (closer_email);

alter table public.equipos_venta   enable row level security;
alter table public.equipo_miembros enable row level security;

revoke all on public.equipos_venta   from anon, authenticated;
revoke all on public.equipo_miembros from anon, authenticated;

grant select, insert, update, delete on public.equipos_venta   to authenticated;
grant select, insert, update, delete on public.equipo_miembros to authenticated;

drop policy if exists "equipos_venta: leer"     on public.equipos_venta;
drop policy if exists "equipos_venta: escribir" on public.equipos_venta;
create policy "equipos_venta: leer" on public.equipos_venta
  for select to authenticated using (true);
create policy "equipos_venta: escribir" on public.equipos_venta
  for all to authenticated using (public.es_admin()) with check (public.es_admin());

drop policy if exists "equipo_miembros: leer"     on public.equipo_miembros;
drop policy if exists "equipo_miembros: escribir" on public.equipo_miembros;
create policy "equipo_miembros: leer" on public.equipo_miembros
  for select to authenticated using (true);
create policy "equipo_miembros: escribir" on public.equipo_miembros
  for all to authenticated using (public.es_admin()) with check (public.es_admin());
;
