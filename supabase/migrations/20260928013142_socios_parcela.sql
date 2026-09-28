-- Socio de cada parcela (28-sep-2026, owner): Lawang pide ver en la intranet qué partner es dueño de cada parcela de
-- Sumba Hills. Revisión previa #140 (Datos + Seguridad) plegada abajo.
-- erp-ok: dato interno propio de Lawang (reparto entre los socios de PT SAN DAL WOODS), sin pantalla en el maestro
-- destructivo-ok: el único DELETE vive DENTRO de unidad_socio_asigna (quitar el socio de una parcela, queda en el log); esta migración no borra filas
--
-- Qué es y qué NO es:
--  · «Socio» = el partner de la sociedad a quien corresponde la parcela en el reparto interno. NO es el propietario
--    legal del suelo (ese va en el Hak Sewa, hsn_propietario_*): por eso no se llama «propietario».
--  · El socio cuelga de la SOCIEDAD (`sociedades.clave`), no del proyecto (Datos #140-5): un mismo partner con parcelas
--    en otro proyecto es la misma entidad y el mismo número SOC.
--  · Una parcela tiene como mucho UN socio (PK en unidad_id). Sin fila = «sin socio asignado», nunca un socio inventado.
--  · Desde la carga del 28-sep manda la intranet; la hoja del cliente queda como origen histórico, no como fuente.
--
-- Solo lo ve y lo cambia un admin (decisión del owner, 28-sep):
--  · Tablas APARTE de `unidades` a propósito: `unidades` y `unidades_estado` las leen los agentes; una columna ahí
--    dejaría agrupar las parcelas por dueño.
--  · RLS activada y SIN policies; ningún grant a anon/authenticated. service_role conserva el suyo: el respaldo diario
--    (respaldo_supabase.py) descubre las tablas por PostgREST con esa clave y es la única copia de estos datos (#140-D4).
--  · Las dos RPC son SECURITY DEFINER con dueño `postgres`, NUNCA `lw_lector` (Seguridad #140-2: LAW-338 va dando
--    lecturas a lw_lector; si heredara estas, una RPC de agentes podría leer el reparto). Por eso tampoco se llaman
--    `*_datos`. Primera línea: sin sesión o no admin → 42501. Lo vigila un invariante de tools/salud_lawang.py.
--  · Secuencia y funciones de trigger revocadas explícitamente: en Lawang nacen abiertas por los default privileges
--    (Seguridad #140-1).
--  · El autor sale de la sesión (auth.email()), nunca de un parámetro.
--  · El log NO cuelga en cascada de `unidades`: copia código de parcela y nombre del socio en el momento, para que
--    borrar o recrear una unidad no borre su historia (Seguridad #140-4).
-- Los datos (nombres y reparto) NO van en este fichero ni en ningún otro del repo (repos públicos): se cargan por SQL.
-- Solo añade: ningún drop, ningún dato existente se reescribe.

create sequence public.socios_numero_seq as bigint start with 1;
revoke all on sequence public.socios_numero_seq from public, anon, authenticated;

create table public.socios (
  id          uuid primary key default gen_random_uuid(),
  numero      text not null unique,
  sociedad    text not null references public.sociedades(clave),
  nombre      text not null check (btrim(nombre) <> '' and length(nombre) <= 120),
  tipo        text not null default 'socio' check (tipo in ('socio', 'arquitecto')),
  activo      boolean not null default true,
  notas       text check (length(notas) <= 1000),
  creado_en   timestamptz not null default now(),
  creado_por  text
);
create unique index socios_sociedad_nombre_key on public.socios (sociedad, lower(btrim(nombre)));

create function public.socios_numero() returns trigger
  language plpgsql security definer set search_path to ''
  as $$
begin
  if tg_op = 'INSERT' then
    new.numero := 'SOC-' || lpad(nextval('public.socios_numero_seq')::text, 5, '0');
  else
    new.numero := old.numero;
  end if;
  return new;
end $$;
revoke all on function public.socios_numero() from public, anon, authenticated;
create trigger trg_socios_numero before insert or update of numero on public.socios
  for each row execute function public.socios_numero();

create table public.unidad_socio (
  unidad_id     uuid primary key references public.unidades(id) on delete cascade,
  socio_id      uuid not null references public.socios(id),
  nota          text check (length(nota) <= 500),
  asignado_en   timestamptz not null default now(),
  asignado_por  text
);
create index unidad_socio_socio_idx on public.unidad_socio (socio_id);

create table public.unidad_socio_log (
  id             bigint generated always as identity primary key,
  unidad_id      uuid not null,
  unidad_codigo  text,
  socio_antes    uuid,
  socio_antes_nombre   text,
  socio_despues  uuid,
  socio_despues_nombre text,
  nota           text,
  por            text,
  en             timestamptz not null default now()
);
create index unidad_socio_log_unidad_idx on public.unidad_socio_log (unidad_id, en desc);

alter table public.socios enable row level security;
alter table public.unidad_socio enable row level security;
alter table public.unidad_socio_log enable row level security;
revoke all on public.socios, public.unidad_socio, public.unidad_socio_log from public, anon, authenticated;

-- Lectura para la pantalla de parcelas: los socios activos y las asignaciones de las parcelas de UN proyecto.
create function public.socios_parcelas(p_proyecto_id uuid)
  returns jsonb
  language plpgsql stable security definer set search_path to ''
  as $$
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if not public.es_admin() then raise exception 'Solo un administrador ve los socios' using errcode = '42501'; end if;
  return jsonb_build_object(
    'socios', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'numero', s.numero, 'nombre', s.nombre,
                                                            'tipo', s.tipo, 'sociedad', s.sociedad)
                                         order by s.nombre)
                          from public.socios s where s.activo), '[]'::jsonb),
    'asignaciones', coalesce((select jsonb_agg(jsonb_build_object('unidad_id', us.unidad_id, 'socio_id', us.socio_id,
                                                                  'nota', us.nota))
                                from public.unidad_socio us
                                join public.unidades u on u.id = us.unidad_id
                               where u.proyecto_id = p_proyecto_id), '[]'::jsonb));
end $$;
alter function public.socios_parcelas(uuid) owner to postgres;
revoke all on function public.socios_parcelas(uuid) from public, anon;
grant execute on function public.socios_parcelas(uuid) to authenticated;

-- Asignar, cambiar o quitar (p_socio null) el socio de una parcela. Todo cambio queda en el log.
create function public.unidad_socio_asigna(p_unidad uuid, p_socio uuid, p_nota text default null)
  returns void
  language plpgsql volatile security definer set search_path to ''
  as $$
declare
  v_cod text; v_antes public.unidad_socio%rowtype; v_nom_antes text; v_nom_despues text;
  v_nota text := nullif(btrim(coalesce(p_nota, '')), '');
  v_por text := (select auth.email());
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if not public.es_admin() then raise exception 'Solo un administrador asigna socios' using errcode = '42501'; end if;
  if length(v_nota) > 500 then raise exception 'La nota no puede pasar de 500 caracteres' using errcode = '22023'; end if;

  select u.codigo into v_cod from public.unidades u where u.id = p_unidad for update;
  if not found then raise exception 'No encuentro esa parcela' using errcode = '22023'; end if;
  if p_socio is not null then
    select s.nombre into v_nom_despues from public.socios s where s.id = p_socio and s.activo;
    if not found then raise exception 'Ese socio no existe o está dado de baja' using errcode = '22023'; end if;
  end if;

  select * into v_antes from public.unidad_socio us where us.unidad_id = p_unidad;
  if found then select s.nombre into v_nom_antes from public.socios s where s.id = v_antes.socio_id; end if;
  if v_antes.socio_id is not distinct from p_socio and v_antes.nota is not distinct from v_nota then return; end if;

  if p_socio is null then
    delete from public.unidad_socio where unidad_id = p_unidad;
  else
    insert into public.unidad_socio (unidad_id, socio_id, nota, asignado_por)
    values (p_unidad, p_socio, v_nota, v_por)
    on conflict (unidad_id) do update
      set socio_id = excluded.socio_id, nota = excluded.nota, asignado_en = now(), asignado_por = excluded.asignado_por;
  end if;

  insert into public.unidad_socio_log (unidad_id, unidad_codigo, socio_antes, socio_antes_nombre,
                                       socio_despues, socio_despues_nombre, nota, por)
  values (p_unidad, v_cod, v_antes.socio_id, v_nom_antes, p_socio, v_nom_despues, v_nota, v_por);
end $$;
alter function public.unidad_socio_asigna(uuid, uuid, text) owner to postgres;
revoke all on function public.unidad_socio_asigna(uuid, uuid, text) from public, anon;
grant execute on function public.unidad_socio_asigna(uuid, uuid, text) to authenticated;
