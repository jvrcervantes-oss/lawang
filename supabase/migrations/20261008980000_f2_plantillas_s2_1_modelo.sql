-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Encargo «plantillas de contrato por empresa» · S2 · migracion 1/4 (7-oct-2026): EL MODELO. Tres tablas nuevas y sus candados; nada visible cambia (nadie las llama aun).
--   plantilla_contrato_versiones : una fila por (empresa, plantilla, version). estado borrador|activa|retirada; origen semilla|empresa; `activable` + `bloqueo_motivo`
--                                  (las semillas v1 NO son activables: llevan texto de Lawang fijo, R12/R13 del encargo).
--   plantilla_contrato_cuerpos   : el HTML en tabla hija (R9: nunca viaja en un listado). `hash` = sha256 del cuerpo en UTF-8, calculado en SERVIDOR y comprobado por trigger.
--   contrato_plantilla_version   : que version uso cada contrato. Tabla aparte: `contratos` no recibe columna ni trigger (R3). La FK a contratos solo crea disparadores internos de integridad.
--   Inmutabilidad por trigger: activa y retirada no se tocan (solo activa -> retirada, y solo cambia el estado); la semilla no cambia nunca; nada se borra ni se trunca.
--   Sin GRANT a anon/authenticated/service_role: solo RPC (migraciones 2-4). lw_lector recibe SELECT con policy (patron del bloque 6) para las RPC de lectura.
--   Los textos reales los carga S4; el validador de cuerpo (S3) lo pone otra migracion (rango 20261008990000+): hasta entonces guardar/activar fallan cerrado.
-- destructivo-ok: solo crea tablas, indices, funciones y triggers nuevos; no toca filas ni tablas existentes (la FK a plantillas_contrato/contratos no modifica nada)
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_plantillas_s2.sql

-- ---------------------------------------------------------------- hash en servidor
create or replace function public._plantilla_hash(p_cuerpo text) returns text
language sql immutable security definer set search_path = '' as $$
  select pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p_cuerpo, 'UTF8')), 'hex')
$$;
revoke all on function public._plantilla_hash(text) from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------- versiones
create table public.plantilla_contrato_versiones (
  id                  uuid        primary key default gen_random_uuid(),
  empresa             text        not null references public.empresas (clave),
  slug                text        not null references public.plantillas_contrato (slug),
  version             integer     not null check (version > 0),
  estado              text        not null default 'borrador' check (estado in ('borrador', 'activa', 'retirada')),
  origen              text        not null default 'empresa' check (origen in ('semilla', 'empresa')),
  idioma_set          text[]      not null default '{}' check (idioma_set <@ array['es', 'en', 'id']::text[]),
  hash                text        not null check (hash ~ '^[0-9a-f]{64}$'),
  bytes               integer     not null check (bytes > 0),
  activable           boolean     not null default false,
  bloqueo_motivo      text,
  hereda_de           uuid        references public.plantilla_contrato_versiones (id),
  autor               text        not null check (btrim(autor) <> ''),
  fecha               timestamptz not null default now(),
  motivo              text,
  activado_por        text,
  activado_en         timestamptz,
  confirmacion_nombre text,
  confirmacion_texto  text,
  retirada_por        text,
  retirada_en         timestamptz,
  unique (empresa, slug, version),
  constraint plantilla_activable_motivo check ((activable and bloqueo_motivo is null) or (not activable and nullif(btrim(bloqueo_motivo), '') is not null)),
  constraint plantilla_semilla_no_activable check (origen <> 'semilla' or not activable),
  constraint plantilla_activa_confirmada check (estado <> 'activa' or (activable and activado_por is not null and activado_en is not null
                                                   and nullif(btrim(confirmacion_nombre), '') is not null and nullif(btrim(confirmacion_texto), '') is not null)),
  constraint plantilla_retirada_firmada check (estado <> 'retirada' or (retirada_por is not null and retirada_en is not null))
);
comment on table public.plantilla_contrato_versiones is
  'Versiones del TEXTO de cada plantilla de contrato POR EMPRESA (owner 7-oct-2026, via A). Sin columna de cuerpo: vive en plantilla_contrato_cuerpos. activa y retirada son inmutables; las semillas v1 (origen semilla) son staging, no activables.';
comment on column public.plantilla_contrato_versiones.activable is 'false = no se puede activar (semilla del estudio con texto de otra sociedad, o hallazgo sin clasificar). bloqueo_motivo dice por que.';
create unique index plantilla_una_activa on public.plantilla_contrato_versiones (empresa, slug) where estado = 'activa';
create unique index plantilla_un_borrador on public.plantilla_contrato_versiones (empresa, slug) where estado = 'borrador' and origen = 'empresa';
create index plantilla_versiones_hereda on public.plantilla_contrato_versiones (hereda_de) where hereda_de is not null;

-- ---------------------------------------------------------------- cuerpos
create table public.plantilla_contrato_cuerpos (
  version_id  uuid primary key references public.plantilla_contrato_versiones (id),
  cuerpo_html text not null check (octet_length(cuerpo_html) between 1 and 1000000)
);
comment on table public.plantilla_contrato_cuerpos is 'HTML de cada version (hasta 300 KB hoy). Nunca en un listado ni select *: se lee por RPC, una version cada vez (R9, TOAST).';

-- ---------------------------------------------------------------- vinculo contrato -> version
create table public.contrato_plantilla_version (
  contrato_id uuid        primary key references public.contratos (id) on delete cascade,
  version_id  uuid        not null references public.plantilla_contrato_versiones (id),
  fijado_en   timestamptz not null default now(),
  fijado_por  text        not null check (btrim(fijado_por) <> '')
);
comment on table public.contrato_plantilla_version is 'Version de plantilla que usa cada contrato, fijada al GUARDAR. Inmutable si el contrato esta bloqueado o tiene alguna fila en contrato_firmas. Sin vinculo = texto del fichero.';
create index contrato_plantilla_version_ver on public.contrato_plantilla_version (version_id);

-- ---------------------------------------------------------------- triggers de versiones
create or replace function public._trg_plantilla_version_ins() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.estado <> 'borrador' or new.activado_por is not null or new.activado_en is not null or new.retirada_por is not null or new.retirada_en is not null
     or new.confirmacion_nombre is not null or new.confirmacion_texto is not null then
    raise exception 'Una version nace siempre como borrador; activar es un acto aparte (plantilla_contrato_activa)' using errcode = '55000';
  end if;
  return new;
end $$;
revoke all on function public._trg_plantilla_version_ins() from public, anon, authenticated, service_role;
create trigger trg_plantilla_version_ins before insert on public.plantilla_contrato_versiones
  for each row execute function public._trg_plantilla_version_ins();

create or replace function public._trg_plantilla_version_upd() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_body text;
begin
  if old.estado = 'retirada' then
    raise exception 'Una version retirada no se modifica (queda para siempre)' using errcode = '55000';
  end if;
  if old.origen = 'semilla' then
    raise exception 'Una semilla del estudio no se modifica ni se activa: se parte de ella para escribir una version nueva' using errcode = '55000';
  end if;
  if (old.id, old.empresa, old.slug, old.version, old.origen, old.hereda_de) is distinct from (new.id, new.empresa, new.slug, new.version, new.origen, new.hereda_de) then
    raise exception 'Identidad de la version inmutable (empresa, plantilla, version, origen)' using errcode = '55000';
  end if;
  if old.estado = 'activa' then
    -- unica transicion permitida: activa -> retirada, y solo cambian el estado y quien/cuando la retira
    if new.estado <> 'retirada' or (to_jsonb(new) - 'estado' - 'retirada_por' - 'retirada_en') is distinct from (to_jsonb(old) - 'estado' - 'retirada_por' - 'retirada_en') then
      raise exception 'Una version activa es inmutable: solo puede pasar a retirada' using errcode = '55000';
    end if;
    return new;
  end if;
  -- old.estado = 'borrador' (origen empresa)
  if new.estado = 'retirada' then
    if new.retirada_por is null or new.retirada_en is null then raise exception 'Falta quien retira' using errcode = '22023'; end if;
    return new;
  end if;
  if new.estado = 'activa' then
    if not old.activable then
      raise exception 'Version no activable: %', coalesce(old.bloqueo_motivo, 'sin motivo') using errcode = '55000';
    end if;
    select c.cuerpo_html into v_body from public.plantilla_contrato_cuerpos c where c.version_id = old.id;
    if v_body is null or public._plantilla_hash(v_body) is distinct from new.hash then
      raise exception 'El hash de la version no coincide con su cuerpo' using errcode = '55000';
    end if;
    return new;
  end if;
  return new;   -- sigue borrador: cambian cuerpo (hash, bytes), motivo, autor, fecha, idiomas
end $$;
revoke all on function public._trg_plantilla_version_upd() from public, anon, authenticated, service_role;
create trigger trg_plantilla_version_upd before update on public.plantilla_contrato_versiones
  for each row execute function public._trg_plantilla_version_upd();

create or replace function public._trg_plantilla_sin_borrado() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  raise exception 'Las versiones de plantilla y sus cuerpos no se borran ni se vacian' using errcode = '55000';
end $$;
revoke all on function public._trg_plantilla_sin_borrado() from public, anon, authenticated, service_role;
create trigger trg_plantilla_version_del before delete on public.plantilla_contrato_versiones for each row execute function public._trg_plantilla_sin_borrado();
create trigger trg_plantilla_version_trunc before truncate on public.plantilla_contrato_versiones for each statement execute function public._trg_plantilla_sin_borrado();
create trigger trg_plantilla_cuerpo_del before delete on public.plantilla_contrato_cuerpos for each row execute function public._trg_plantilla_sin_borrado();
create trigger trg_plantilla_cuerpo_trunc before truncate on public.plantilla_contrato_cuerpos for each statement execute function public._trg_plantilla_sin_borrado();

-- ---------------------------------------------------------------- triggers de cuerpos
create or replace function public._trg_plantilla_cuerpo_iu() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v public.plantilla_contrato_versiones%rowtype;
begin
  select * into v from public.plantilla_contrato_versiones x where x.id = new.version_id;
  if not found then raise exception 'La version del cuerpo no existe' using errcode = '23503'; end if;
  if tg_op = 'UPDATE' and new.version_id <> old.version_id then
    raise exception 'Un cuerpo no cambia de version' using errcode = '55000';
  end if;
  if v.estado <> 'borrador' or (tg_op = 'UPDATE' and v.origen = 'semilla') then
    raise exception 'El cuerpo de una version activa, retirada o semilla es inmutable' using errcode = '55000';
  end if;
  if public._plantilla_hash(new.cuerpo_html) is distinct from v.hash or octet_length(new.cuerpo_html) <> v.bytes then
    raise exception 'El hash/tamano de la version no corresponde a este cuerpo (se calcula en servidor)' using errcode = '55000';
  end if;
  return new;
end $$;
revoke all on function public._trg_plantilla_cuerpo_iu() from public, anon, authenticated, service_role;
create trigger trg_plantilla_cuerpo_iu before insert or update on public.plantilla_contrato_cuerpos
  for each row execute function public._trg_plantilla_cuerpo_iu();

-- ---------------------------------------------------------------- trigger del vinculo
create or replace function public._trg_contrato_plantilla_version() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_cid uuid := case when tg_op = 'DELETE' then old.contrato_id else new.contrato_id end;
        v_emp_c text; v_emp_v text;
begin
  if tg_op = 'UPDATE' and new.contrato_id <> old.contrato_id then
    raise exception 'El vinculo no cambia de contrato' using errcode = '55000';
  end if;
  -- contrato firmado o con alguna ronda de firma: el vinculo es historia (en un DELETE en cascada el contrato ya no existe y no entra aqui)
  if exists (select 1 from public.contratos c where c.id = v_cid and c.bloqueado)
     or exists (select 1 from public.contrato_firmas f where f.contrato_id = v_cid) then
    raise exception 'Contrato firmado o en firma: su version de plantilla ya no cambia' using errcode = '55000';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  select pr.empresa into v_emp_c from public.contratos c join public.proyectos pr on pr.id = c.proyecto_id where c.id = v_cid;
  select v.empresa into v_emp_v from public.plantilla_contrato_versiones v where v.id = new.version_id;
  if v_emp_c is null or v_emp_c is distinct from v_emp_v then
    raise exception 'La version es de otra empresa que el proyecto del contrato (o el contrato no tiene empresa)' using errcode = '22023';
  end if;
  return new;
end $$;
revoke all on function public._trg_contrato_plantilla_version() from public, anon, authenticated, service_role;
create trigger trg_contrato_plantilla_version before insert or update or delete on public.contrato_plantilla_version
  for each row execute function public._trg_contrato_plantilla_version();

-- ---------------------------------------------------------------- RLS y permisos: nada directo
alter table public.plantilla_contrato_versiones enable row level security;
alter table public.plantilla_contrato_cuerpos   enable row level security;
alter table public.contrato_plantilla_version   enable row level security;
revoke all on table public.plantilla_contrato_versiones, public.plantilla_contrato_cuerpos, public.contrato_plantilla_version from public, anon, authenticated, service_role;
grant select on table public.plantilla_contrato_versiones, public.plantilla_contrato_cuerpos, public.contrato_plantilla_version to lw_lector;

create policy "vinculo: quien ve el contrato" on public.contrato_plantilla_version for select to lw_lector
  using (public.es_agente() and public.puede_ver_contrato(contrato_id));
-- borrador = solo quien edita esa empresa; activa/retirada = agentes de su alcance; una semilla (borrador) la lee tambien quien ve un contrato vinculado a ella
create policy "versiones: lectura por empresa" on public.plantilla_contrato_versiones for select to lw_lector
  using (public.es_agente() and public.empresa_en_alcance(empresa)
         and (estado <> 'borrador' or public.es_admin_de(empresa)
              or exists (select 1 from public.contrato_plantilla_version l where l.version_id = plantilla_contrato_versiones.id)));
create policy "cuerpos: los de las versiones visibles" on public.plantilla_contrato_cuerpos for select to lw_lector
  using (exists (select 1 from public.plantilla_contrato_versiones v where v.id = plantilla_contrato_cuerpos.version_id));
