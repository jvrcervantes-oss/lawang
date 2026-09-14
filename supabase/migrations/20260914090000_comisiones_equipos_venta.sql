-- COMISIONES: EQUIPOS DE VENTA — 14-sep-2026.
-- Subtarea de un encargo mayor (reparto de comisiones por equipo). Esta pieza
-- SOLO crea las dos tablas base -- equipos y quien pertenece a cada uno -- con
-- su RLS. La visibilidad fina (qué ve un closer normal frente a un manager o
-- admin) queda para otra subtarea del mismo encargo: aquí basta con que la
-- lista de equipos y de miembros la pueda LEER cualquiera con sesión en la
-- intranet, y que solo admin/super_admin pueda darlos de alta, editarlos o
-- borrarlos.
--
-- FUNCIÓN DE ROL: se usa public.es_admin() y no una OR con es_super_admin().
-- Verificado en 20260729090612_usuarios_funciones_permisos.sql: es_admin() ya
-- comprueba `rol in ('super_admin','admin')`, así que ya cubre a los dos.
--
-- GRANTS: el proyecto tiene el GRANT por defecto de Supabase a `authenticated`
-- (ALL, TRUNCATE incluido) sin revocar en el esquema base. Aquí se revoca
-- explícitamente para las dos tablas nuevas y se concede solo lo que hace
-- falta: nada para `anon` (sin policies == sin acceso, igual que el resto de
-- la intranet), y select+insert+update+delete para `authenticated` -- el GRANT
-- deja pasar la operación a nivel de tabla, la policy decide luego QUIÉN de
-- authenticated puede de verdad ejecutarla. Sin este revoke, cualquier cuenta
-- con sesión podría truncar la tabla aunque ninguna policy se lo permitiera
-- por RLS -- TRUNCATE no lo filtra RLS, lo filtra el GRANT.
--
-- destructivo-ok: no hay DROP ni DELETE ni UPDATE sin WHERE en este fichero.
-- Los "revoke all" son retirada de privilegio sobre tablas que se crean dos
-- líneas más arriba en esta misma migración (hoy no tienen ninguna fila ni
-- ningún grant que perder); los "drop policy if exists" son el patrón
-- estándar del repo para poder re-ejecutar la migración sin fallar por
-- nombre duplicado -- los nombres son nuevos, no existe ninguno todavía.

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

-- anon: sin policies = sin acceso (mismo patrón que el resto de tablas de la intranet).

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
