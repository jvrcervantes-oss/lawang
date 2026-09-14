-- COMISIONES: CONDICIONES Y TRAMOS — 14-sep-2026.
-- Subtarea del mismo encargo que creó equipos_venta/equipo_miembros
-- (20260914090000_comisiones_equipos_venta.sql). Esta pieza define QUÉ % cobra
-- cada nivel (manager/closer) en cada proyecto, con qué base de cálculo, y en
-- qué tramos se libera ese % según el disparador (cobro parcial de suelo/obra/
-- total, o hito binario de obra/contrato firmado).
--
-- FUNCIÓN DE ROL: public.es_admin() — mismo criterio que equipos_venta (ya
-- cubre super_admin, verificado en 20260729090612_usuarios_funciones_permisos.sql).
--
-- LECTURA — regla de negocio de esta subtarea:
--   · nivel='closer': el propio closer ve su override (closer_email =
--     auth.email()) y la condición por defecto (closer_email is null) de
--     cualquier equipo del que sea miembro VIGENTE hoy (equipo_miembros.desde
--     <= hoy <= hasta, o hasta null).
--   · nivel='manager': la ve el manager_email de ese equipo (columna de
--     equipos_venta, no requiere ficha en equipo_miembros) y cualquier admin.
--   · admin/super_admin: todo, siempre.
--
-- GRANTS: mismo patrón que equipos_venta — revoke del ALL por defecto de
-- Supabase a authenticated, grant explícito de lo que hace falta. anon sin
-- policies = sin acceso.
--
-- destructivo-ok: no hay DROP ni DELETE ni UPDATE sin WHERE en este fichero.
-- Los "revoke all" retiran privilegio sobre tablas creadas dos líneas más
-- arriba en esta misma migración (sin filas ni grants que perder); los
-- "drop policy/trigger if exists" son el patrón estándar del repo para poder
-- re-ejecutar la migración sin fallar por nombre duplicado.

create table if not exists public.condiciones_comision (
  id             uuid primary key default gen_random_uuid(),
  equipo_id      uuid not null references public.equipos_venta(id) on delete cascade,
  proyecto_id    uuid not null references public.proyectos(id),
  nivel          text not null check (nivel in ('manager', 'closer')),
  closer_email   text,
  pct_comision   numeric not null check (pct_comision > 0),
  base_calculo   text not null check (base_calculo in ('precio_total', 'precio_suelo', 'precio_construccion', 'importe_fijo')),
  importe_fijo   numeric,
  activo         boolean not null default true,
  created_by     text,
  created_at     timestamptz not null default now(),
  constraint condiciones_comision_importe_fijo_coherente check (
    (base_calculo = 'importe_fijo' and importe_fijo is not null and importe_fijo > 0)
    or
    (base_calculo <> 'importe_fijo' and importe_fijo is null)
  )
);

comment on table public.condiciones_comision is
  'Qué % de comisión cobra un nivel (manager/closer) en un proyecto, y sobre qué base. closer_email NULL = condición por defecto del equipo en ese proyecto/nivel; closer_email con valor = override individual para ese closer, que manda sobre el default cuando ambos existen (el desempate lo resuelve quien LEA esta tabla, no una constraint: no hay UNIQUE que impida que default y override convivan, es justo el diseño).';
comment on column public.condiciones_comision.closer_email is
  'NULL = condición por defecto del equipo+proyecto+nivel. Con valor = override de ESE closer. Texto libre (igual que equipo_miembros.closer_email): sin FK a usuarios.';
comment on column public.condiciones_comision.importe_fijo is
  'Solo se rellena cuando base_calculo = importe_fijo (constraint condiciones_comision_importe_fijo_coherente); en cualquier otra base queda NULL.';

create table if not exists public.condicion_tramos (
  id               uuid primary key default gen_random_uuid(),
  condicion_id     uuid not null references public.condiciones_comision(id) on delete cascade,
  orden            int not null,
  disparador_tipo  text not null check (disparador_tipo in ('pct_cobrado_suelo', 'pct_cobrado_obra', 'pct_cobrado_total', 'obra_firmada', 'contrato_firmado')),
  umbral           numeric,
  pct_tramo        numeric not null check (pct_tramo > 0 and pct_tramo <= 100),
  created_at       timestamptz not null default now(),
  constraint condicion_tramos_umbral_coherente check (
    (disparador_tipo in ('obra_firmada', 'contrato_firmado') and umbral is null)
    or
    (disparador_tipo in ('pct_cobrado_suelo', 'pct_cobrado_obra', 'pct_cobrado_total') and umbral is not null and umbral >= 0 and umbral <= 100)
  )
);

comment on table public.condicion_tramos is
  'En qué tramos se libera el % de una condiciones_comision. disparador_tipo binario (obra_firmada/contrato_firmado) no lleva umbral; los pct_cobrado_* llevan umbral 0-100 (constraint condicion_tramos_umbral_coherente). La suma de pct_tramo de los tramos de una misma condición debe ser exactamente 100 — lo fuerza el trigger condicion_tramos_suma_100, diferido a fin de transacción para permitir construir los tramos de una condición en varios INSERT dentro de la misma transacción.';

create index if not exists condiciones_comision_equipo_idx      on public.condiciones_comision (equipo_id);
create index if not exists condiciones_comision_proyecto_idx    on public.condiciones_comision (proyecto_id);
create index if not exists condiciones_comision_closer_idx      on public.condiciones_comision (closer_email);
create index if not exists condicion_tramos_condicion_idx       on public.condicion_tramos (condicion_id);

-- TRIGGER: la suma de pct_tramo de una condición debe ser exactamente 100.
-- CONSTRAINT TRIGGER deferrable/deferred (no un AFTER ROW normal): un AFTER
-- ROW inmediato reventaría en el primer INSERT de un alta multi-tramo (la
-- suma parcial nunca es 100 hasta el último), y bloquearía además el propio
-- DELETE en cascada de una condición completa (sus tramos desaparecen uno a
-- uno, la suma pasa por 0 antes de llegar a "ya no queda nada que comprobar").
-- Diferir a fin de transacción dejar completar el alta/baja de todos los
-- tramos de una condición antes de exigir el 100%.
create or replace function public.valida_suma_tramos_comision()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_condicion_id uuid := coalesce(new.condicion_id, old.condicion_id);
  v_suma numeric;
begin
  -- La condición padre ya no existe (se borró ella misma, arrastrando estos
  -- tramos por el ON DELETE CASCADE): nada que validar, no queda condición
  -- viva con un % a medias.
  if not exists (select 1 from public.condiciones_comision c where c.id = v_condicion_id) then
    return coalesce(new, old);
  end if;

  select coalesce(sum(pct_tramo), 0) into v_suma
    from public.condicion_tramos
   where condicion_id = v_condicion_id;

  if abs(v_suma - 100) > 0.01 then
    raise exception 'los tramos de la condición % suman % (deben sumar exactamente 100)',
      v_condicion_id, v_suma using errcode = '23514';
  end if;

  return coalesce(new, old);
end;
$$;

drop trigger if exists condicion_tramos_suma_100 on public.condicion_tramos;
create constraint trigger condicion_tramos_suma_100
  after insert or update or delete on public.condicion_tramos
  deferrable initially deferred
  for each row execute function public.valida_suma_tramos_comision();

alter table public.condiciones_comision enable row level security;
alter table public.condicion_tramos     enable row level security;

revoke all on public.condiciones_comision from anon, authenticated;
revoke all on public.condicion_tramos     from anon, authenticated;

grant select, insert, update, delete on public.condiciones_comision to authenticated;
grant select, insert, update, delete on public.condicion_tramos     to authenticated;

-- anon: sin policies = sin acceso (mismo patrón que el resto de la intranet).

drop policy if exists "condiciones_comision: leer"     on public.condiciones_comision;
drop policy if exists "condiciones_comision: escribir" on public.condiciones_comision;

create policy "condiciones_comision: leer" on public.condiciones_comision
  for select to authenticated using (
    public.es_admin()
    or (
      nivel = 'closer'
      and (
        closer_email = (select auth.email())
        or (
          closer_email is null
          and exists (
            select 1 from public.equipo_miembros em
             where em.equipo_id = condiciones_comision.equipo_id
               and em.closer_email = (select auth.email())
               and em.desde <= current_date
               and (em.hasta is null or em.hasta >= current_date)
          )
        )
      )
    )
    or (
      nivel = 'manager'
      and exists (
        select 1 from public.equipos_venta ev
         where ev.id = condiciones_comision.equipo_id
           and ev.manager_email = (select auth.email())
      )
    )
  );

create policy "condiciones_comision: escribir" on public.condiciones_comision
  for all to authenticated using (public.es_admin()) with check (public.es_admin());

drop policy if exists "condicion_tramos: leer"     on public.condicion_tramos;
drop policy if exists "condicion_tramos: escribir" on public.condicion_tramos;

create policy "condicion_tramos: leer" on public.condicion_tramos
  for select to authenticated using (
    exists (
      select 1 from public.condiciones_comision c
       where c.id = condicion_tramos.condicion_id
         and (
           public.es_admin()
           or (
             c.nivel = 'closer'
             and (
               c.closer_email = (select auth.email())
               or (
                 c.closer_email is null
                 and exists (
                   select 1 from public.equipo_miembros em
                    where em.equipo_id = c.equipo_id
                      and em.closer_email = (select auth.email())
                      and em.desde <= current_date
                      and (em.hasta is null or em.hasta >= current_date)
                 )
               )
             )
           )
           or (
             c.nivel = 'manager'
             and exists (
               select 1 from public.equipos_venta ev
                where ev.id = c.equipo_id
                  and ev.manager_email = (select auth.email())
             )
           )
         )
    )
  );

create policy "condicion_tramos: escribir" on public.condicion_tramos
  for all to authenticated using (public.es_admin()) with check (public.es_admin());
;
