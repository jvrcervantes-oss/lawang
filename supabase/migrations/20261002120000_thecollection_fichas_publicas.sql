-- destructivo-ok: solo crea (tabla, log, funciones, triggers) e inserta 4 proyectos + 4 unidades que no existen (insert condicionado a «no existe», nada se borra ni se sobrescribe).
-- THE COLLECTION v2 · F2 — fichas_publicas (la web pública bebe de la intranet). 2-oct-2026.
-- Encargo: encargos/20261002_lawang_thecollection_v2.md (F2) y _F1.md (esquema §2, alta de proyectos §4.2/Q4). Plan revisado por Datos+Seguridad+Desarrollo (#188).
-- Sin pareja en erp/migraciones/: Lawang es independiente del maestro (28-sep) y fichas_publicas no la usa ninguna pantalla común.
--
-- El dato tiene un dueño: aquí viven SOLO los datos editoriales y de publicación que la intranet no tenía (línea, región web,
-- textos EN/ES, highlights, tenure, visibilidad web…). Lo que ya tiene dueño (m², dormitorios de un modelo, estado y superficie de
-- una parcela, galería de deck_fotos, entrega del proyecto) NO se copia: se leerá por JOIN desde proyecto_id/modelo_id/unidad_id.
-- dormitorios/banos/construido_m2/parcela_m2 son el respaldo SOLO para fichas sin modelo/unidad (las 4 casas signature sueltas).
--
-- Decisiones, con su porqué:
--   1. Tabla cerrada: RLS activo, SIN policy y SIN grant a anon/authenticated (patrón LAW-51/LAW-50 y copias_firmadas_envios). Nada del
--      navegador la toca directo. Se escribe por `ficha_publica_guarda` (solo admin/super_admin, comprobado en servidor) y se leerá
--      por `coleccion_publica()` (F5b, migración aparte; NO se crea aquí) con campos escritos a mano.
--   2. FK opcionales con ON DELETE SET NULL (decisión del encargo): borrar un proyecto/modelo/unidad no se lleva la ficha por delante.
--      Coste conocido: la ficha pierde su vínculo en silencio → F5b debe tratar «publicada_web y sin proyecto/modelo/unidad donde el
--      ficha.linea lo exige» como ficha incompleta (no publicarla), y salud_lawang puede vigilarlo.
--   3. `slug` es la URL pública (/property/<slug>): UNIQUE, con forma fija, y la RPC NO lo cambia (como trg_proyecto_slug).
--   4. Nace cerrada: `publicada_web` default false. No se publica un precio fijo sin importe ni una ficha sin título EN (CHECK en la base,
--      no solo en la pantalla). Precio fijo solo en la línea signature (decisión del owner 2-oct): CHECK.
--   5. Registro de cambios solo-añadir (fichas_publicas_log), alimentado por trigger: cualquier escritura (RPC, service_role, SQL) deja
--      rastro. Mismo patrón que ajustes_log. `precio_eur` y `publicada_web` son lo que el cliente ve: quién los cambió importa.
--   6. La RPC acepta una LISTA BLANCA de claves (las columnas editables). Cualquier otra se rechaza (22023). Los textos largos y el jsonb
--      tienen tope de tamaño. Nada se calcula en el navegador: el servidor valida todo.
--   7. RPC SECURITY DEFINER con search_path='' y comprobación `es_admin()` (admin + super_admin) dentro. Sin permiso a PUBLIC ni anon.
--
-- Llamadores con nombre (reducir la exposición): ficha_publica_guarda → pestaña «Ficha pública» de intranet/v4/proyectos (F3).
-- fichas_publicas → solo la lee coleccion_publica() (F5b) y la escribe ficha_publica_guarda; la migración de las 44 fichas (F4) corre con
-- service_role.
-- ROLLBACK: drop function ficha_publica_guarda(text, jsonb); drop table fichas_publicas_log, fichas_publicas (nada más depende de ellas);
-- los 4 proyectos y sus unidades se retiran con delete por slug/proyecto SOLO si siguen sin contratos (parar y preguntar al owner).

-- ── 0. Guarda: los 4 nombres/slug no pueden existir ya con otra identidad (la lectura del 2-oct: ninguno existe) ─────────────────
do $guarda$
begin
  if exists (select 1 from public.proyectos p
              where (p.nombre in ('Tirta Hikari', 'Cube', 'River', 'Aqua') and p.slug not in ('tirta-hikari', 'cube', 'river', 'aqua'))
                 or (p.slug in ('tirta-hikari', 'cube', 'river', 'aqua') and p.nombre not in ('Tirta Hikari', 'Cube', 'River', 'Aqua'))) then
    raise exception 'Ya existe un proyecto con ese nombre o slug pero con otra identidad: revisar a mano antes de dar de alta las 4 casas signature';
  end if;
end $guarda$;

-- ── 1. La tabla ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.fichas_publicas (
  id              uuid primary key default gen_random_uuid(),
  slug            text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and char_length(slug) between 3 and 60),
  linea           text not null check (linea in ('signature', 'villa', 'land')),
  region_key      text not null check (region_key in ('bali', 'sumba')),
  region          text check (char_length(region) <= 120),
  publicada_web   boolean not null default false,
  en_coleccion    boolean not null default false,
  destacada       boolean not null default false,
  destacada_home  boolean not null default false,
  orden           integer not null default 0,
  proyecto_id     uuid references public.proyectos(id) on delete set null,
  modelo_id       uuid references public.modelos(id)   on delete set null,
  unidad_id       uuid references public.unidades(id)  on delete set null,
  precio_modo     text not null default 'consultar' check (precio_modo in ('fijo', 'desde', 'consultar')),
  precio_eur      numeric check (precio_eur is null or (precio_eur >= 0 and precio_eur < 1000000000)),
  tenure          text check (tenure in ('freehold', 'leasehold')),
  lease_years     integer check (lease_years is null or lease_years between 1 and 99),
  estado_obra     text check (estado_obra in ('offplan', 'ready')),
  -- respaldo SOLO para fichas sin modelo_id / unidad_id (el dueño es modelos / unidades)
  dormitorios     integer check (dormitorios is null or dormitorios between 0 and 30),
  banos           integer check (banos is null or banos between 0 and 30),
  construido_m2   numeric check (construido_m2 is null or (construido_m2 > 0 and construido_m2 < 100000)),
  parcela_m2      numeric check (parcela_m2 is null or (parcela_m2 > 0 and parcela_m2 < 10000000)),
  textos          jsonb not null default '{}'::jsonb check (jsonb_typeof(textos) = 'object'),
  ficha           jsonb not null default '{}'::jsonb check (jsonb_typeof(ficha) = 'object'),
  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz not null default now(),
  actualizado_por text,
  -- una ficha publicada tiene título EN y, si anuncia precio, importe (la base lo exige, no solo la pantalla)
  constraint ficha_publicada_completa check (
    not publicada_web or (
      (precio_modo = 'consultar' or precio_eur is not null)
      and nullif(btrim(textos #>> '{title,en}'), '') is not null)),
  constraint ficha_precio_fijo_signature check (precio_modo <> 'fijo' or linea = 'signature')
);
create index if not exists fichas_publicas_proyecto_idx on public.fichas_publicas (proyecto_id);
create index if not exists fichas_publicas_modelo_idx   on public.fichas_publicas (modelo_id);
create index if not exists fichas_publicas_unidad_idx   on public.fichas_publicas (unidad_id);

comment on table public.fichas_publicas is
  'The Collection v2 (2-oct-2026). DUEÑO: administración (admin/super_admin) por ficha_publica_guarda; datos editoriales y de publicación de la web pública que la intranet no tenía. Lo que ya tiene dueño (m², estado de parcela, galería, entrega) se lee por JOIN y no se copia. LLAMADORES: escribe solo ficha_publica_guarda (pestaña Ficha pública, intranet/v4/proyectos) y la migración F4 (service_role); lee solo coleccion_publica() (F5b) y el PHP coleccion/lib.php. Cerrada a anon/authenticated: sin policy ni grant.';

alter table public.fichas_publicas enable row level security;
revoke all on public.fichas_publicas from public, anon, authenticated;
grant all on public.fichas_publicas to service_role;

-- ── 2. Registro de cambios (solo se añade) ─────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.fichas_publicas_log (
  id        bigint generated always as identity primary key,
  ficha_id  uuid,
  slug      text not null,
  operacion text not null check (operacion in ('INSERT', 'UPDATE', 'DELETE')),
  antes     jsonb,
  despues   jsonb,
  quien     text not null,
  cuando    timestamptz not null default now()
);
create index if not exists fichas_publicas_log_ficha_idx on public.fichas_publicas_log (ficha_id, cuando desc);
comment on table public.fichas_publicas_log is
  'Quién cambió qué en fichas_publicas, antes y después (2-oct-2026). Solo se añade (trigger). Lo escribe el trigger de fichas_publicas; sin lector en el navegador.';
alter table public.fichas_publicas_log enable row level security;
revoke all on public.fichas_publicas_log from public, anon, authenticated;
revoke all on public.fichas_publicas_log from service_role;
grant select on public.fichas_publicas_log to service_role;

create or replace function public._trg_fichas_publicas_log_inmutable() returns trigger
  language plpgsql set search_path to ''
  as $$
begin
  raise exception 'fichas_publicas_log es un registro: no se modifica ni se borra.' using errcode = '42501';
end $$;
revoke all on function public._trg_fichas_publicas_log_inmutable() from public, anon, authenticated;
create or replace trigger fichas_publicas_log_inmutable before update or delete on public.fichas_publicas_log
  for each row execute function public._trg_fichas_publicas_log_inmutable();
create or replace trigger fichas_publicas_log_sin_truncate before truncate on public.fichas_publicas_log
  for each statement execute function public._trg_fichas_publicas_log_inmutable();

-- BEFORE: una escritura que no cambia nada es un no-op (ni toca actualizado_en ni deja rastro: F4 se puede re-ejecutar)
create or replace function public._trg_fichas_publicas_sello() returns trigger
  language plpgsql set search_path to ''
  as $$
begin
  if tg_op = 'UPDATE'
     and (to_jsonb(new) - 'actualizado_en' - 'actualizado_por') is not distinct from (to_jsonb(old) - 'actualizado_en' - 'actualizado_por') then
    return old;
  end if;
  new.actualizado_en := now();
  new.actualizado_por := coalesce(public._quien_actua(), 'sistema:' || current_user);
  return new;
end $$;
revoke all on function public._trg_fichas_publicas_sello() from public, anon, authenticated;
create or replace trigger fichas_publicas_sello before insert or update on public.fichas_publicas
  for each row execute function public._trg_fichas_publicas_sello();

create or replace function public._trg_fichas_publicas_log() returns trigger
  language plpgsql security definer set search_path to ''
  as $$
begin
  insert into public.fichas_publicas_log (ficha_id, slug, operacion, antes, despues, quien)
  values (coalesce(new.id, old.id), coalesce(new.slug, old.slug), tg_op,
          case when tg_op = 'INSERT' then null else to_jsonb(old) end,
          case when tg_op = 'DELETE' then null else to_jsonb(new) end,
          coalesce(public._quien_actua(), 'sistema:' || current_user));
  return null;
end $$;
revoke all on function public._trg_fichas_publicas_log() from public, anon, authenticated;
create or replace trigger fichas_publicas_log_ins_del after insert or delete on public.fichas_publicas
  for each row execute function public._trg_fichas_publicas_log();
create or replace trigger fichas_publicas_log_upd after update on public.fichas_publicas
  for each row when (old.* is distinct from new.*) execute function public._trg_fichas_publicas_log();

-- ── 3. RPC de escritura (solo admin / super_admin, comprobado aquí) ─────────────────────────────────────────────────────────────
-- p_slug identifica la ficha (alta si no existe: exige linea y region_key). p_cambios: solo las claves a cambiar, de la lista blanca.
create or replace function public.ficha_publica_guarda(p_slug text, p_cambios jsonb)
  returns uuid
  language plpgsql security definer set search_path to ''
  as $$
declare
  v_ok  text[] := array['linea', 'region_key', 'region', 'publicada_web', 'en_coleccion', 'destacada', 'destacada_home', 'orden',
                        'proyecto_id', 'modelo_id', 'unidad_id', 'precio_modo', 'precio_eur', 'tenure', 'lease_years', 'estado_obra',
                        'dormitorios', 'banos', 'construido_m2', 'parcela_m2', 'textos', 'ficha'];
  v_old public.fichas_publicas%rowtype;
  v_new public.fichas_publicas%rowtype;
  k text;
  v_slug text := lower(btrim(coalesce(p_slug, '')));
begin
  if not public.es_admin() then
    raise exception 'La ficha pública la edita administración' using errcode = '42501';
  end if;
  if v_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' or char_length(v_slug) not between 3 and 60 then
    raise exception 'La dirección solo admite minúsculas, números y guiones (de 3 a 60)' using errcode = '22023';
  end if;
  if jsonb_typeof(p_cambios) is distinct from 'object' then
    raise exception 'Datos de la ficha no válidos' using errcode = '22023';
  end if;
  if char_length(p_cambios::text) > 200000 then
    raise exception 'La ficha es demasiado grande' using errcode = '22023';
  end if;
  for k in select jsonb_object_keys(p_cambios) loop
    if not (k = any (v_ok)) then
      raise exception 'Ese dato de la ficha no se edita desde aquí: %', k using errcode = '22023';
    end if;
  end loop;

  select * into v_old from public.fichas_publicas f where f.slug = v_slug for update;
  if not found then
    if not (p_cambios ? 'linea' and p_cambios ? 'region_key') then
      raise exception 'Una ficha nueva necesita línea y región (bali o sumba)' using errcode = '22023';
    end if;
    insert into public.fichas_publicas (slug, linea, region_key)
    values (v_slug, p_cambios->>'linea', p_cambios->>'region_key')
    returning * into v_old;
  end if;

  -- las claves ausentes conservan su valor; las presentes lo sustituyen (jsonb entero, no mezcla)
  v_new := jsonb_populate_record(v_old, p_cambios);

  update public.fichas_publicas f set
    linea = v_new.linea, region_key = v_new.region_key, region = nullif(btrim(v_new.region), ''),
    publicada_web = v_new.publicada_web, en_coleccion = v_new.en_coleccion, destacada = v_new.destacada,
    destacada_home = v_new.destacada_home, orden = v_new.orden,
    proyecto_id = v_new.proyecto_id, modelo_id = v_new.modelo_id, unidad_id = v_new.unidad_id,
    precio_modo = v_new.precio_modo, precio_eur = v_new.precio_eur, tenure = v_new.tenure, lease_years = v_new.lease_years,
    estado_obra = v_new.estado_obra, dormitorios = v_new.dormitorios, banos = v_new.banos,
    construido_m2 = v_new.construido_m2, parcela_m2 = v_new.parcela_m2,
    textos = coalesce(v_new.textos, '{}'::jsonb), ficha = coalesce(v_new.ficha, '{}'::jsonb)
  where f.id = v_old.id;
  return v_old.id;
end $$;
comment on function public.ficha_publica_guarda(text, jsonb) is
  'Alta/edición de una ficha pública (The Collection v2). Solo admin/super_admin (comprobado dentro). Lista blanca de claves; el slug no se cambia. Llamador: pestaña Ficha pública de intranet/v4/proyectos (F3).';
revoke all on function public.ficha_publica_guarda(text, jsonb) from public, anon;
grant execute on function public.ficha_publica_guarda(text, jsonb) to authenticated, service_role;

-- ── 4. Alta idempotente de los 4 proyectos que faltan (1 unidad por casa) ───────────────────────────────────────────────────────
-- Convención medida el 2-oct en Tangkuban Village / Pura Dalem: resort 'Signature project', estado 'en_venta', unidades tipo 'villa'
-- con código 'Villa N', moneda EUR. El precio NO se pone aquí: es de la ficha (precio fijo, F4, lo fija el owner); la unidad nace
-- 'disponible' sin precio. `proyecto_id` lo resuelve el trigger unidades_resuelve_proyecto por nombre.
insert into public.proyectos (nombre, slug, resort, estado)
select v.nombre, v.slug, 'Signature project', 'en_venta'
  from (values ('Tirta Hikari', 'tirta-hikari'), ('Cube', 'cube'), ('River', 'river'), ('Aqua', 'aqua')) as v(nombre, slug)
 where not exists (select 1 from public.proyectos p where p.slug = v.slug or p.nombre = v.nombre);

insert into public.unidades (codigo, proyecto, tipo, estado, moneda)
select 'Villa 1', p.nombre, 'villa', 'disponible', 'EUR'
  from public.proyectos p
 where p.slug in ('tirta-hikari', 'cube', 'river', 'aqua')
   and not exists (select 1 from public.unidades u where u.proyecto = p.nombre and u.codigo = 'Villa 1')
   and not exists (select 1 from public.unidades u where u.proyecto_id = p.id);
