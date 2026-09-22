-- destructivo-ok: el escaner textual ve DROP CONSTRAINT / DROP TRIGGER / DELETE y
-- los para, pero ninguno borra datos aqui. El DROP CONSTRAINT sustituye el CHECK
-- fijo por la FK equivalente en la misma sentencia (mismo conjunto de valores
-- validos hoy, verificado con `select estado, count(*) from lead_estado group by
-- estado` antes de escribir esto: solo nuevo/contactado/visita/perdido en uso, los
-- cuatro dentro de la nueva tabla). El DROP TRIGGER IF EXISTS es el idiom habitual
-- para (re)crear un trigger sobre una tabla que la propia migracion acaba de crear
-- (no existia nada que perder). Los DELETE viven DENTRO de `crm_estado_borrar`,
-- una funcion que solo se ejecuta cuando un super_admin la llama a proposito, ya
-- migro los leads de esa columna antes de borrarla y esta descrita entera en la
-- revision previa con Datos y Seguridad (ver `tools/revision_previa.py`).
--
-- Kanban de leads configurable — 15-sep-2026, encargo del owner: poder editar los
-- títulos de las columnas y añadir/quitar columnas intermedias. Revisión previa con
-- Datos, Seguridad y Diseño sobre el plan antes de escribir esto (ver historial de
-- `tools/revision_previa.py`); los cinco puntos de Datos y los cinco de Seguridad
-- están recogidos aquí uno a uno, comentados donde se resuelven.
--
-- ── Qué NO cambia ─────────────────────────────────────────────────────────────────
-- 'nuevo', 'reserva' y 'contrato' son PROTEGIDAS: no se pueden borrar ni cambiar de
-- clave (el título sí). Motivo, cada una distinta:
--   · 'nuevo'    — es el DEFAULT de `lead_estado.estado` y el COALESCE de
--                  `crm_lead_mover` para un lead sin fila de estado todavía. Borrarla
--                  rompería el alta de cualquier lead nuevo.
--   · 'reserva'  — de ella depende `lead_sugerencia` (contratos con etapa 'reserva')
--                  y el KPI "Reserva o contrato" de `leads.js`.
--   · 'contrato' — mismo motivo que 'reserva'.
-- 'contactado', 'visita' y 'perdido' NO llevan nada colgado por su clave literal en
-- ningún otro sitio del repo (verificado con grep antes de escribir esto) — se dejan
-- editables/borrables como el resto de columnas intermedias.
--
-- ── Decisión explícita sobre `contrato_tipo_etapa` (hallazgo 2 de Datos) ───────────
-- Su CHECK (`etapa in ('reserva','contrato','ninguna')`) se queda TAL CUAL, sin FK a
-- `lead_estados`. No es un descuido: `contrato_tipo_etapa` dice qué TIPOS DE CONTRATO
-- cuentan como cierre de venta — un concepto propio del negocio, no "qué columnas
-- tiene el tablero hoy" — que solo COINCIDE en vocabulario con las dos claves
-- protegidas. Como 'reserva' y 'contrato' nunca pueden borrarse ni renombrar su clave
-- (trigger de abajo), esa coincidencia nunca puede divergir. Referenciar la tabla
-- aquí acoplaría dos conceptos distintos sin necesidad.

-- ── 1. La tabla ──────────────────────────────────────────────────────────────────
create table if not exists public.lead_estados (
  clave           text primary key check (clave ~ '^[a-z][a-z0-9_]{1,29}$'),
  titulo          text not null check (char_length(btrim(titulo)) between 1 and 24),
  descripcion     text not null default '',
  -- Paleta cerrada, no un color picker libre: nueve tonos ya distinguibles entre sí y
  -- coherentes con el resto de la suite (hallazgo 4 de Diseño). Se comprueba aquí Y en
  -- la función de escritura — un solo punto de control ya falló antes en este repo
  -- (ver GRANT-antes-que-policy, security_invoker de unidades_estado).
  color           text not null check (color in (
                    '#64748B','#1D4ED8','#0F766E','#D97706','#064E3B','#94A3B8',
                    '#7C3AED','#0891B2','#B45309')),
  orden           int  not null,
  protegida       boolean not null default false,
  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz,
  actualizado_por uuid
);
create unique index if not exists lead_estados_orden_idx on public.lead_estados(orden);

comment on table public.lead_estados is
  'Columnas del kanban de leads. Editable desde el panel (solo super_admin). '
  'protegida=true en nuevo/reserva/contrato: no se pueden borrar ni cambiar de clave.';

insert into public.lead_estados (clave, titulo, descripcion, color, orden, protegida) values
  ('nuevo',      'Nuevo',      'Acaba de entrar, nadie lo ha tocado',  '#64748B', 10, true),
  ('contactado', 'Contactado', 'Se le ha escrito o llamado',           '#1D4ED8', 20, false),
  ('visita',     'Visita',     'Ha visto el terreno o la villa',       '#0F766E', 30, false),
  ('reserva',    'Reserva',    'Carta de reserva firmada',             '#D97706', 40, true),
  ('contrato',   'Contrato',   'Contrato de compraventa firmado',      '#064E3B', 50, true),
  ('perdido',    'Perdido',    'No sigue adelante',                    '#94A3B8', 60, false)
on conflict (clave) do nothing;

-- ── 2. El candado (hallazgo 2 de Seguridad) ─────────────────────────────────────
-- No basta con el `if not es_super_admin()` dentro de las funciones de escritura: un
-- bug en esa función, o un script futuro que escriba con service_role, se llevaría
-- 'reserva'/'contrato' por delante sin este trigger. Aquí se blinda AL NIVEL DE LA
-- FILA, sin excepción ni para super_admin — el título y el color siguen editables
-- porque esto solo mira `clave` (UPDATE) y el DELETE entero.
create or replace function public.lead_estado_protegido_guard()
returns trigger language plpgsql security invoker set search_path to '' as $$
begin
  if tg_op = 'DELETE' then
    if old.protegida then
      raise exception 'La columna "%" está protegida y no se puede borrar.', old.clave
        using errcode = 'PT403';
    end if;
    return old;
  end if;
  -- tg_op = 'UPDATE'
  if old.protegida and new.clave is distinct from old.clave then
    raise exception 'La columna "%" está protegida: no se puede cambiar su clave.', old.clave
      using errcode = 'PT403';
  end if;
  if old.protegida and new.protegida is not true then
    raise exception 'La columna "%" está protegida y no se puede desproteger.', old.clave
      using errcode = 'PT403';
  end if;
  new.actualizado_en := now();
  new.actualizado_por := auth.uid();
  return new;
end $$;

drop trigger if exists trg_lead_estado_protegido on public.lead_estados;
create trigger trg_lead_estado_protegido
  before update or delete on public.lead_estados
  for each row execute function public.lead_estado_protegido_guard();

-- ── 3. El CHECK fijo de `lead_estado.estado` pasa a ser una FK ──────────────────
-- `on delete restrict`: defensa de base además del guard de la función de borrado
-- (hallazgo 3 de Datos) — si algún día algo intenta borrar una clave con leads
-- dentro sin pasar por `crm_estado_borrar`, Postgres lo para igual.
alter table public.lead_estado drop constraint if exists lead_estado_estado_check;
alter table public.lead_estado
  add constraint lead_estado_estado_fkey foreign key (estado)
  references public.lead_estados (clave) on update cascade on delete restrict;

-- ── 4. RLS: lectura scoped, NUNCA "authenticated = true" ────────────────────────
-- El plan original decía "igual que plantilla_cuentas", y plantilla_cuentas es
-- precisamente el diseño que Legal señaló ayer como abierto de más (LAW-221:
-- `for select to authenticated using (true)`, sin mirar `puede()`). No se clona
-- ese defecto en una tabla nueva: se lee con el mismo permiso que el resto del CRM.
alter table public.lead_estados enable row level security;

create policy "crm lee las columnas del tablero" on public.lead_estados
  for select to authenticated using (public.puede('leads'));

-- Sin policies de INSERT/UPDATE/DELETE a propósito: toda escritura de estructura
-- pasa por las funciones SECURITY DEFINER de abajo (hallazgo 1 de Seguridad — no
-- se abre con `for all using (es_super_admin())` directo sobre la tabla, que es el
-- patrón de plantilla_cuentas y no deja rastro ni permite el borrado atómico).

-- ── 5. `crm_lead_mover`: valida en FRESCO contra la tabla, no contra una lista ──
-- (hallazgo 4 de Seguridad). Se añade además un cerrojo de aviso POR CLAVE, para
-- que mover un lead a una columna y borrar esa misma columna no puedan pisarse
-- (hallazgo 3 de Seguridad): mismo mecanismo que el cerrojo por lead que ya tenía,
-- en un espacio de claves de asesoramiento distinto (segundo argumento = 1) para
-- no chocar con el existente (segundo argumento = 0).
create or replace function public.crm_lead_mover(
  p_lead uuid, p_estado text, p_desde timestamptz
)
returns table (lead_id uuid, estado text, estado_desde timestamptz, responsable text)
language plpgsql volatile security definer set search_path to ''
as $$
declare
  v_quien  text := coalesce((select auth.email()), '');
  v_actual text;
  v_desde  timestamptz;
  v_alta   timestamptz;
  v_ahora  timestamptz := now();
begin
  if not public.puede('leads') then
    raise exception 'Sin permiso sobre los leads' using errcode = 'PT403';
  end if;
  if v_quien = '' then
    raise exception 'Sesion sin identidad' using errcode = 'PT403';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_estado, 1));

  if not exists (select 1 from public.lead_estados where clave = p_estado) then
    raise exception 'Estado desconocido: %', p_estado using errcode = 'PT400';
  end if;

  select l.created_at into v_alta from public.leads l where l.id = p_lead;
  if v_alta is null then
    raise exception 'Ese lead no existe' using errcode = 'PT404';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_lead::text, 0));

  -- La fila de estado puede faltar: el 'nuevo' del tablero es un COALESCE, no un dato
  -- guardado. Cuando falta, la referencia de concurrencia es la fecha de alta.
  select e.estado, e.estado_desde into v_actual, v_desde
    from public.lead_estado e where e.lead_id = p_lead;
  v_actual := coalesce(v_actual, 'nuevo');
  v_desde  := coalesce(v_desde, v_alta);

  if p_desde is null or v_desde is distinct from p_desde then
    raise exception 'La tarjeta la ha movido otra persona' using errcode = 'PT409';
  end if;

  if v_actual = p_estado then
    return query select p_lead, v_actual, v_desde,
                        (select e.responsable from public.lead_estado e where e.lead_id = p_lead);
    return;
  end if;

  update public.lead_estado e
     set estado = p_estado, responsable = v_quien,
         estado_desde = v_ahora, actualizado = v_ahora
   where e.lead_id = p_lead;
  if not found then
    insert into public.lead_estado (lead_id, estado, responsable, estado_desde, actualizado)
         values (p_lead, p_estado, v_quien, v_ahora, v_ahora);
  end if;

  insert into public.lead_estado_log (lead_id, de, a, autor)
       values (p_lead, v_actual, p_estado, v_quien);

  return query
    select e.lead_id, e.estado, e.estado_desde, e.responsable
      from public.lead_estado e where e.lead_id = p_lead;
end;
$$;

-- ── 6. Crear una columna intermedia ─────────────────────────────────────────────
-- Renumera SIEMPRE antes de insertar (huecos de 10 entre cada una) para que nunca
-- falte sitio decimal, por muchas columnas que se hayan insertado ya entre las
-- mismas dos vecinas.
create or replace function public.crm_estado_crear(
  p_clave text, p_titulo text, p_descripcion text, p_color text, p_tras text
)
returns public.lead_estados
language plpgsql volatile security definer set search_path to '' as $$
declare
  v_orden int;
  v_row   public.lead_estados;
begin
  if not public.es_super_admin() then
    raise exception 'Solo un super admin edita la estructura del tablero.' using errcode = 'PT403';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(hashtext('lead_estados_estructura'));

  with ranked as (
    select clave, row_number() over (order by orden) as rn from public.lead_estados
  )
  update public.lead_estados le set orden = ranked.rn * 10
    from ranked where ranked.clave = le.clave;

  select orden into v_orden from public.lead_estados where clave = p_tras;
  if v_orden is null then
    raise exception 'No existe la columna de referencia "%".', p_tras using errcode = 'PT400';
  end if;

  insert into public.lead_estados (clave, titulo, descripcion, color, orden, protegida)
       values (p_clave, btrim(p_titulo), coalesce(p_descripcion, ''), p_color, v_orden + 5, false)
    returning * into v_row;
  return v_row;
end $$;

-- ── 7. Editar título/descripción/color — vale también para las protegidas ──────
-- El trigger de arriba solo mira `clave` y `protegida`: renombrar el título de
-- 'reserva' o 'contrato' pasa sin problema, cambiar su clave no.
create or replace function public.crm_estado_editar(
  p_clave text, p_titulo text, p_descripcion text, p_color text
)
returns public.lead_estados
language plpgsql volatile security definer set search_path to '' as $$
declare v_row public.lead_estados;
begin
  if not public.es_super_admin() then
    raise exception 'Solo un super admin edita la estructura del tablero.' using errcode = 'PT403';
  end if;
  update public.lead_estados
     set titulo = btrim(p_titulo), descripcion = coalesce(p_descripcion, ''), color = p_color
   where clave = p_clave
  returning * into v_row;
  if v_row is null then
    raise exception 'La columna "%" no existe.', p_clave using errcode = 'PT400';
  end if;
  return v_row;
end $$;

-- ── 8. Borrar una columna intermedia — atómico, con migración de leads ─────────
-- Mismo cerrojo de aviso que la creación (namespace 'lead_estados_estructura'):
-- dos admins no pueden crear/borrar estructura a la vez, y el cerrojo por clave de
-- `crm_lead_mover` (punto 5) impide que un lead entre en la columna justo mientras
-- se está borrando.
create or replace function public.crm_estado_borrar(p_clave text, p_destino text default null)
returns void
language plpgsql volatile security definer set search_path to '' as $$
declare
  v_protegida boolean;
  v_n         int;
  v_quien     text := coalesce((select auth.email()), 'sistema');
begin
  if not public.es_super_admin() then
    raise exception 'Solo un super admin edita la estructura del tablero.' using errcode = 'PT403';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(hashtext('lead_estados_estructura'));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_clave, 1));

  select protegida into v_protegida from public.lead_estados where clave = p_clave;
  if v_protegida is null then
    raise exception 'La columna "%" no existe.', p_clave using errcode = 'PT400';
  end if;
  if v_protegida then
    raise exception 'La columna "%" está protegida y no se puede borrar.', p_clave using errcode = 'PT403';
  end if;

  select count(*) into v_n from public.lead_estado where estado = p_clave;

  if v_n > 0 then
    if p_destino is null then
      raise exception 'Hay % lead(s) en esta columna: indica a qué columna se migran.', v_n
        using errcode = 'PT409';
    end if;
    if p_destino = p_clave then
      raise exception 'La columna destino no puede ser la misma que se borra.' using errcode = 'PT400';
    end if;
    if not exists (select 1 from public.lead_estados where clave = p_destino) then
      raise exception 'La columna destino "%" no existe.', p_destino using errcode = 'PT400';
    end if;

    insert into public.lead_estado_log (lead_id, de, a, autor)
      select lead_id, p_clave, p_destino, v_quien || ' (al borrar la columna)'
        from public.lead_estado where estado = p_clave;

    update public.lead_estado
       set estado = p_destino, estado_desde = now(), actualizado = now()
     where estado = p_clave;
  end if;

  delete from public.lead_estados where clave = p_clave;
end $$;

revoke execute on function public.crm_estado_crear(text, text, text, text, text) from public, anon;
revoke execute on function public.crm_estado_editar(text, text, text, text) from public, anon;
revoke execute on function public.crm_estado_borrar(text, text) from public, anon;
grant execute on function public.crm_estado_crear(text, text, text, text, text) to authenticated;
grant execute on function public.crm_estado_editar(text, text, text, text) to authenticated;
grant execute on function public.crm_estado_borrar(text, text) to authenticated;;
