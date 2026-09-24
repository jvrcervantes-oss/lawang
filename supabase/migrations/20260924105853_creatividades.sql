-- destructivo-ok: los DROP son de dos CHECK de deck_fotos que se recrean mas amplios; TRUNCATE solo aparece en un REVOKE que quita ese permiso (revision previa #68).
-- ═══════════════════════════════════════════════════════════════════════════
-- CREATIVIDADES — biblioteca de piezas de redes y dossiers (24-sep-2026)
-- Encargo: encargos/20260924_lawang_creatividades_v4.md (owner: D1=A, D2=A, D3=A)
-- Revisión previa #68 (Seguridad + Datos + Legal) — cada regla lleva su hallazgo.
--
-- Una fila = una pieza (PNG) o un dossier (JSON del constructor). Los FICHEROS
-- viven en el bucket privado `creatividades`, carpeta = id de la fila:
--   <id>/estado-<ts>.json   estado del editor, para reabrir
--   <id>/pieza-<ts>.png     el PNG final de una pieza
-- Sin DELETE en ningún sitio: lo que sobra se ARCHIVA.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── deck_fotos: tercer ámbito «general» (D3, Datos #3) ─────────────────────
-- Imágenes de marca que no son de un proyecto ni de un modelo (paisaje de Bali,
-- Indonesia…). Hasta hoy vivían en ficheros del repo; el CHECK no las admitía.
alter table public.deck_fotos drop constraint deck_fotos_ambito_check;
alter table public.deck_fotos add constraint deck_fotos_ambito_check
  check (ambito = any (array['proyecto','modelo','general']));
alter table public.deck_fotos drop constraint deck_fotos_ambito_coherente;
alter table public.deck_fotos add constraint deck_fotos_ambito_coherente check (
     (ambito = 'proyecto' and proyecto_id is not null and modelo_id is null)
  or (ambito = 'modelo'   and modelo_id is not null)
  or (ambito = 'general'  and proyecto_id is null and modelo_id is null));
-- Seguridad #2: `authenticated` tenía TRUNCATE (y REFERENCES/TRIGGER) en deck_fotos.
revoke truncate, references, trigger on public.deck_fotos from authenticated;

-- ── tablas ─────────────────────────────────────────────────────────────────
create table public.creatividades (
  id            uuid primary key default gen_random_uuid(),
  tipo          text not null check (tipo in ('pieza','dossier')),
  proyecto_id   uuid references public.proyectos(id) on delete restrict,  -- null = de la marca, sin proyecto
  titulo        text not null check (char_length(titulo) between 1 and 200),
  formato       text check (char_length(formato) <= 20),
  arquetipo     text check (arquetipo in ('anuncio','doc','portada','partida','plano')),
  estado        text not null default 'borrador'
                check (estado in ('borrador','aprobada','publicada','archivada')),
  path          text check (path ~ '^[0-9a-f-]{36}/pieza-[0-9]+\.png$'),        -- PNG final (solo piezas)
  estado_path   text check (estado_path ~ '^[0-9a-f-]{36}/estado-[0-9]+\.json$'), -- estado del editor
  lleva_render  boolean not null default false,   -- lo calcula la base (Datos #1), nunca el navegador
  precios_a     date,                              -- fecha de la lista de la que salen los «desde»
  origen        text check (origen in ('repo')),   -- 'repo' = dossier migrado del repositorio (D3)
  creado_por    uuid, creado_en timestamptz not null default now(),
  actualizado_por uuid, actualizado_en timestamptz,
  aprobada_por  uuid, aprobada_en timestamptz,
  publicada_en  timestamptz, archivada_en timestamptz,
  constraint creatividades_png_solo_pieza check (path is null or tipo = 'pieza'),
  constraint creatividades_carpeta_propia check (
        (path is null or split_part(path, '/', 1) = id::text)
    and (estado_path is null or split_part(estado_path, '/', 1) = id::text))
);
create index creatividades_proyecto_idx on public.creatividades (proyecto_id);
create index creatividades_estado_idx on public.creatividades (tipo, estado);

-- Datos #1: enlaces con clave ajena real. `on delete restrict`: una foto o un
-- modelo que usa una creatividad no desaparece dejando la pieza rota en silencio.
create table public.creatividad_fotos (
  creatividad_id uuid not null references public.creatividades(id) on delete cascade,
  foto_id        uuid not null references public.deck_fotos(id) on delete restrict,
  primary key (creatividad_id, foto_id)
);
create index creatividad_fotos_foto_idx on public.creatividad_fotos (foto_id);
create table public.creatividad_modelos (
  creatividad_id uuid not null references public.creatividades(id) on delete cascade,
  modelo_id      uuid not null references public.modelos(id) on delete restrict,
  primary key (creatividad_id, modelo_id)
);
create index creatividad_modelos_modelo_idx on public.creatividad_modelos (modelo_id);

-- Legal #5: quién descargó qué versión y cuándo. Solo inserción, por la RPC.
create table public.creatividad_descargas (
  id             bigint generated always as identity primary key,
  creatividad_id uuid not null references public.creatividades(id) on delete cascade,
  fichero        text not null,
  quien          uuid not null,
  en             timestamptz not null default now()
);
create index creatividad_descargas_idx on public.creatividad_descargas (creatividad_id);

-- Legal #3: bloques de texto legal VERSIONADOS (no escritos en el JS, que se
-- queda viejo en silencio — «Freehold (Hak Milik)» del 8-sep). Se lee la versión
-- más alta de cada (clave, idioma).
create table public.bloques_legales (
  clave     text not null check (clave ~ '^[a-z_]{3,40}$'),
  idioma    text not null check (idioma in ('es','en','id')),
  version   int  not null check (version > 0),
  texto     text not null check (char_length(texto) between 1 and 8000),
  estado    text not null default 'borrador_legal' check (estado in ('borrador_legal','validado')),
  creado_por uuid, creado_en timestamptz not null default now(),
  primary key (clave, idioma, version)
);

-- ── triggers ──────────────────────────────────────────────────────────────
-- Autoría y guardas. Seguridad #2: `estado`, `aprobada_*` y la autoría no tienen
-- GRANT de UPDATE (las mueve solo la RPC), y el CONTENIDO se congela en cuanto
-- la creatividad deja de ser borrador: una versión nueva es una fila nueva.
create or replace function public._creatividades_antes()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'UPDATE' then
    if old.estado <> 'borrador' and (
         new.path is distinct from old.path or new.estado_path is distinct from old.estado_path
      or new.titulo is distinct from old.titulo or new.proyecto_id is distinct from old.proyecto_id
      or new.formato is distinct from old.formato or new.arquetipo is distinct from old.arquetipo
      or new.precios_a is distinct from old.precios_a or new.tipo is distinct from old.tipo) then
      raise exception 'Solo se edita un borrador. Para cambiar esta creatividad, haz una copia.' using errcode = '23514';
    end if;
    new.tipo := old.tipo;
    new.origen := old.origen;
    new.creado_por := old.creado_por;
    new.creado_en  := old.creado_en;
    new.actualizado_por := (select auth.uid());
    new.actualizado_en  := now();
  else
    new.creado_por := coalesce((select auth.uid()), new.creado_por);
    new.creado_en  := now();
    new.actualizado_por := null; new.actualizado_en := null;
    new.aprobada_por := null; new.aprobada_en := null;
    new.publicada_en := null; new.archivada_en := null;
    new.lleva_render := false;
    if (select auth.uid()) is not null then new.estado := 'borrador'; new.origen := null; end if;
  end if;
  return new;
end $$;
revoke all on function public._creatividades_antes() from public, anon, authenticated;
create trigger creatividades_antes before insert or update on public.creatividades
  for each row execute function public._creatividades_antes();

-- Datos #1 + Legal #2: `lleva_render` sale de las fotos enlazadas. Cuenta como
-- render lo que no es foto real: 'render' y también 'ia'.
create or replace function public._creatividad_fotos_render()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_id uuid := coalesce(new.creatividad_id, old.creatividad_id);
begin
  if (select estado from public.creatividades where id = v_id) <> 'borrador'
     and (select auth.uid()) is not null then
    raise exception 'Solo se cambian las fotos de un borrador.' using errcode = '23514';
  end if;
  update public.creatividades c
     set lleva_render = exists (select 1 from public.creatividad_fotos cf
                                  join public.deck_fotos f on f.id = cf.foto_id
                                 where cf.creatividad_id = v_id and f.tipo <> 'foto')
   where c.id = v_id;
  return null;
end $$;
revoke all on function public._creatividad_fotos_render() from public, anon, authenticated;
create trigger creatividad_fotos_render after insert or delete on public.creatividad_fotos
  for each row execute function public._creatividad_fotos_render();

create or replace function public._creatividad_modelos_guarda()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_id uuid := coalesce(new.creatividad_id, old.creatividad_id);
begin
  if (select estado from public.creatividades where id = v_id) <> 'borrador'
     and (select auth.uid()) is not null then
    raise exception 'Solo se cambian los modelos de un borrador.' using errcode = '23514';
  end if;
  return null;
end $$;
revoke all on function public._creatividad_modelos_guarda() from public, anon, authenticated;
create trigger creatividad_modelos_guarda after insert or delete on public.creatividad_modelos
  for each row execute function public._creatividad_modelos_guarda();

create trigger trg_guarda_antes_de_borrar before delete on public.creatividades
  for each row execute function public.trg_guarda_antes_de_borrar();

-- ── quién puede qué ─────────────────────────────────────────────────────────
-- Casilla por tipo: 'creatividades' hace piezas, 'dossier' hace dossiers.
-- 'creatividades_ver' (comerciales, D2) solo VE lo aprobado o publicado y no
-- escribe en ningún sitio.
create or replace function public.creatividad_puede_hacer(p_tipo text)
returns boolean language sql stable security definer set search_path = '' as $$
  select case p_tipo when 'pieza' then public.puede('creatividades')
                     when 'dossier' then public.puede('dossier') else false end
$$;
create or replace function public.creatividad_puede_ver(p_tipo text, p_estado text)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.creatividad_puede_hacer(p_tipo)
      or (p_estado in ('aprobada','publicada') and public.puede('creatividades_ver'))
$$;
revoke all on function public.creatividad_puede_hacer(text), public.creatividad_puede_ver(text, text) from public, anon;
grant execute on function public.creatividad_puede_hacer(text), public.creatividad_puede_ver(text, text) to authenticated;

alter table public.creatividades        enable row level security;
alter table public.creatividad_fotos    enable row level security;
alter table public.creatividad_modelos  enable row level security;
alter table public.creatividad_descargas enable row level security;
alter table public.bloques_legales      enable row level security;

create policy "creatividades: leer" on public.creatividades for select to authenticated
  using ((select public.creatividad_puede_ver(tipo, estado)));
create policy "creatividades: crear" on public.creatividades for insert to authenticated
  with check ((select public.creatividad_puede_hacer(tipo)));
create policy "creatividades: editar borrador" on public.creatividades for update to authenticated
  using (estado = 'borrador' and (select public.creatividad_puede_hacer(tipo)))
  with check (estado = 'borrador' and (select public.creatividad_puede_hacer(tipo)));

create policy "creatividad_fotos: leer" on public.creatividad_fotos for select to authenticated
  using (exists (select 1 from public.creatividades c where c.id = creatividad_id));
create policy "creatividad_fotos: poner" on public.creatividad_fotos for insert to authenticated
  with check (exists (select 1 from public.creatividades c where c.id = creatividad_id
                       and c.estado = 'borrador' and public.creatividad_puede_hacer(c.tipo)));
create policy "creatividad_fotos: quitar" on public.creatividad_fotos for delete to authenticated
  using (exists (select 1 from public.creatividades c where c.id = creatividad_id
                  and c.estado = 'borrador' and public.creatividad_puede_hacer(c.tipo)));
create policy "creatividad_modelos: leer" on public.creatividad_modelos for select to authenticated
  using (exists (select 1 from public.creatividades c where c.id = creatividad_id));
create policy "creatividad_modelos: poner" on public.creatividad_modelos for insert to authenticated
  with check (exists (select 1 from public.creatividades c where c.id = creatividad_id
                       and c.estado = 'borrador' and public.creatividad_puede_hacer(c.tipo)));
create policy "creatividad_modelos: quitar" on public.creatividad_modelos for delete to authenticated
  using (exists (select 1 from public.creatividades c where c.id = creatividad_id
                  and c.estado = 'borrador' and public.creatividad_puede_hacer(c.tipo)));

create policy "creatividad_descargas: leer" on public.creatividad_descargas for select to authenticated
  using ((select public.es_admin()));

create policy "bloques_legales: leer" on public.bloques_legales for select to authenticated
  using ((select public.es_agente()));
create policy "bloques_legales: escribir" on public.bloques_legales for insert to authenticated
  with check ((select public.es_super_admin()));

-- GRANT explícitos: en Lawang los default privileges NO dan nada a authenticated.
revoke all on public.creatividades, public.creatividad_fotos, public.creatividad_modelos,
              public.creatividad_descargas, public.bloques_legales from anon, authenticated;
grant select on public.creatividades, public.creatividad_fotos, public.creatividad_modelos,
                public.creatividad_descargas, public.bloques_legales to authenticated;
grant insert (tipo, proyecto_id, titulo, formato, arquetipo, path, estado_path, precios_a)
  on public.creatividades to authenticated;
grant update (proyecto_id, titulo, formato, arquetipo, path, estado_path, precios_a)
  on public.creatividades to authenticated;
grant insert, delete on public.creatividad_fotos, public.creatividad_modelos to authenticated;
grant insert (clave, idioma, version, texto, estado) on public.bloques_legales to authenticated;

-- ── RPC ─────────────────────────────────────────────────────────────────────
-- Seguridad #2 / Datos #4: los cambios de estado, SOLO por aquí. Aprueba
-- cualquier admin con la casilla del tipo, también lo suyo (owner, 24-sep).
create or replace function public.creatividad_estado(p_id uuid, p_estado text)
returns public.creatividades language plpgsql security definer set search_path = '' as $$
declare c public.creatividades;
begin
  select * into c from public.creatividades where id = p_id for update;
  if not found then raise exception 'No existe esa creatividad.' using errcode = 'P0002'; end if;
  if not (public.es_admin() and public.creatividad_puede_hacer(c.tipo)) then
    raise exception 'Solo un admin con la casilla de % cambia el estado.',
      case c.tipo when 'pieza' then 'Creatividades' else 'Dossier' end using errcode = '42501';
  end if;
  if not ((c.estado = 'borrador'  and p_estado in ('aprobada','archivada'))
       or (c.estado = 'aprobada'  and p_estado in ('publicada','archivada'))
       or (c.estado = 'publicada' and p_estado = 'archivada')) then
    raise exception 'No se pasa de «%» a «%».', c.estado, p_estado using errcode = '23514';
  end if;
  if p_estado = 'aprobada' then
    if c.estado_path is null or (c.tipo = 'pieza' and c.path is null) then
      raise exception 'Guarda la creatividad antes de aprobarla: falta el fichero.' using errcode = '23514';
    end if;
  end if;
  update public.creatividades set
    estado = p_estado,
    aprobada_por = case when p_estado = 'aprobada' then (select auth.uid()) else aprobada_por end,
    aprobada_en  = case when p_estado = 'aprobada' then now() else aprobada_en end,
    publicada_en = case when p_estado = 'publicada' then now() else publicada_en end,
    archivada_en = case when p_estado = 'archivada' then now() else archivada_en end
  where id = p_id returning * into c;
  return c;
end $$;
revoke all on function public.creatividad_estado(uuid, text) from public, anon;
grant execute on function public.creatividad_estado(uuid, text) to authenticated;

-- Legal #5: la descarga deja rastro. Devuelve la ruta a firmar; la URL firmada
-- la pide el navegador con SU sesión (la policy de storage decide) y dura poco.
create or replace function public.creatividad_descarga(p_id uuid, p_fichero text)
returns text language plpgsql security definer set search_path = '' as $$
declare c public.creatividades;
begin
  select * into c from public.creatividades where id = p_id;
  if not found or not public.creatividad_puede_ver(c.tipo, c.estado) then
    raise exception 'No tienes acceso a esta creatividad.' using errcode = '42501';
  end if;
  if p_fichero is distinct from c.path and p_fichero is distinct from c.estado_path then
    raise exception 'Ese fichero no es de esta creatividad.' using errcode = '22023';
  end if;
  insert into public.creatividad_descargas (creatividad_id, fichero, quien) values (p_id, p_fichero, (select auth.uid()));
  return p_fichero;
end $$;
revoke all on function public.creatividad_descarga(uuid, text) from public, anon;
grant execute on function public.creatividad_descarga(uuid, text) to authenticated;

-- Datos #2: lo que un dossier lee de la base, en UNA llamada y con SU puerta.
-- Parcelas: SOLO disponibles y publicadas, sin precio (owner: solo «desde» por
-- modelo). «desde» = el techo más barato de `modelo_techos.precio_ahora`.
create or replace function public.dossier_datos(p_proyecto uuid, p_modelos uuid[])
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not (public.puede('dossier') or public.puede('creatividades')) then
    raise exception 'Sin permiso para montar dossiers.' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'proyecto', (select jsonb_build_object('id', p.id, 'nombre', p.nombre, 'slug', p.slug)
                   from public.proyectos p where p.id = p_proyecto),
    'parcelas', coalesce((select jsonb_agg(jsonb_build_object('codigo', u.codigo, 'superficie_m2', u.superficie_m2)
                                  order by coalesce(u.codigo_orden, u.codigo))
                            from public.unidades u
                           where u.proyecto_id = p_proyecto and u.estado = 'disponible'
                             and coalesce(u.publicado_investor_deck, false)), '[]'::jsonb),
    'modelos', coalesce((select jsonb_agg(jsonb_build_object(
                   'id', m.id, 'nombre', m.nombre, 'dormitorios', m.dormitorios, 'banos', m.banos,
                   'villa_m2', m.villa_m2, 'terraza_m2', m.terraza_m2, 'moneda', m.moneda,
                   'desde', (select min(t.precio_ahora) from public.modelo_techos t where t.modelo_id = m.id))
                   order by m.orden nulls last, m.nombre)
                  from public.modelos m where m.id = any(coalesce(p_modelos, '{}')) and m.activo), '[]'::jsonb),
    'fotos', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'ambito', f.ambito, 'modelo_id', f.modelo_id,
                   'tipo', f.tipo, 'uso', f.uso, 'path', f.path, 'pie', f.pie) order by f.ambito, f.orden)
                  from public.deck_fotos f
                 where (f.ambito = 'proyecto' and f.proyecto_id = p_proyecto)
                    or (f.ambito = 'modelo' and f.modelo_id = any(coalesce(p_modelos, '{}')))), '[]'::jsonb),
    'precios_a', to_char(current_date, 'YYYY-MM-DD')
  );
end $$;
revoke all on function public.dossier_datos(uuid, uuid[]) from public, anon;
grant execute on function public.dossier_datos(uuid, uuid[]) to authenticated;

-- ── STORAGE ─────────────────────────────────────────────────────────────────
-- Seguridad #4: privado, solo PNG y JSON, 15 MB. Sin UPDATE ni DELETE.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('creatividades', 'creatividades', false, 15728640, array['image/png','application/json']);

-- Seguridad #1: quien CREA lee los ficheros de su tipo; quien solo VE, únicamente
-- el fichero EXACTO (path o estado_path) de una fila aprobada o publicada.
-- Igualdad con la ruta, nunca con la carpeta: un fichero nuevo en la carpeta de
-- una pieza aprobada no hereda la aprobación.
create policy "creatividades: leer ficheros" on storage.objects for select to authenticated
  using (bucket_id = 'creatividades' and exists (
    select 1 from public.creatividades c
     where c.id::text = (storage.foldername(name))[1]
       and (public.creatividad_puede_hacer(c.tipo)
            or (public.puede('creatividades_ver') and c.estado in ('aprobada','publicada')
                and (c.path = name or c.estado_path = name)))));
create policy "creatividades: subir ficheros" on storage.objects for insert to authenticated
  with check (bucket_id = 'creatividades' and exists (
    select 1 from public.creatividades c
     where c.id::text = (storage.foldername(name))[1]
       and c.estado = 'borrador' and public.creatividad_puede_hacer(c.tipo)
       and ((storage.extension(name) = 'json' and name ~ '/estado-[0-9]+\.json$')
         or (storage.extension(name) = 'png' and c.tipo = 'pieza' and name ~ '/pieza-[0-9]+\.png$'))));

-- ── Texto de «Cómo se compra» (Legal #3; owner 24-sep: «usar ya el borrador») ──
-- Borrador de Legal, pendiente de validar con abogado indonesio: estado
-- 'borrador_legal'. Las dos rutas para TODOS los proyectos (owner, 24-sep).
insert into public.bloques_legales (clave, idioma, version, texto, estado) values
('como_se_compra', 'es', 1, 'Hay dos vías. 1) Con empresa — Freehold (HGB) vía PT PMA: la villa se adquiere a través de una sociedad indonesia de capital extranjero (PT PMA), con título HGB (Hak Guna Bangunan) de 30 años, prorrogable 20 y renovable 30 (PP 18/2021); la sociedad tiene obligaciones propias de capital y de información. 2) Sin empresa — Hak Sewa: arrendamiento a largo plazo a tu nombre, por el plazo y las prórrogas que fije el contrato. En ningún caso se adquiere Hak Milik, reservado por ley a ciudadanos indonesios, ni se usan estructuras nominee. La operación se formaliza con Carta de Reserva y PPJB, y se cierra ante notario/PPAT según la vía. Recomendamos asesoramiento legal independiente. Documento informativo; no constituye oferta vinculante: rigen las condiciones del contrato.', 'borrador_legal'),
('como_se_compra', 'en', 1, 'There are two routes. 1) With a company — Freehold (HGB) via PT PMA: the villa is acquired through an Indonesian foreign-owned company (PT PMA), holding an HGB (Hak Guna Bangunan) title for 30 years, extendable by 20 and renewable for 30 (PP 18/2021); the company has its own capital and reporting obligations. 2) Without a company — Hak Sewa: a long-term lease in your name, for the term and extensions set in the contract. In no case is Hak Milik acquired, as it is reserved by law for Indonesian citizens, and no nominee structures are used. The transaction is formalised with a Reservation Letter and a PPJB, and completed before a notary/PPAT depending on the route. We recommend independent legal advice. Information document; not a binding offer: the terms of the contract prevail.', 'borrador_legal');
