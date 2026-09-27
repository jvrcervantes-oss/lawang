-- LAW-78 (27-sep-2026): los anexos SUBIDOS A MANO de un contrato salen de `contratos.datos.annexes` (JPEG en
-- base64 dentro del jsonb) a un bucket privado, una fila por página. Revisión previa con Datos y Seguridad; su
-- diseño combinado es el que se aplica aquí.
--
-- POR QUÉ. El 27-sep un guardado con 6,5 MB de anexos cortó dos veces por el statement_timeout de 8 s de
-- `authenticated`, y cada lectura de `datos` descomprime el jsonb entero (7,3 MB el mayor, HS00003): los
-- anexos son lo que más pesa de la tabla. En Storage cada página pesa lo suyo y solo se baja al abrir.
--
-- EL DATO TIENE UN DUEÑO (contexto/patrones_tecnicos.md):
--   · Las PÁGINAS (bytes) las tiene el bucket `contratos-anexos`; su lista, huella y tamaño, esta tabla. Es la
--     única fuente del recuento: `datos.annexes` guarda del anexo manual solo {id, title, on} (la ficha).
--   · El contenido de un `anexo_id` es INMUTABLE: cada subida (y cada paso de un anexo viejo a Storage) estrena
--     un id nuevo. Por eso `unique (contrato_id, anexo_id, n)` y ninguna escritura de update: cambiar un anexo es
--     subir otro. Título y «Incluir» viven en la ficha y cambian sin tocar las páginas.
--   · El DOCUMENTO FIRMADO no depende de esto: el snapshot de firma sigue EMBEBIENDO las imágenes (autocontenido).
--     Esta tabla es la fuente del borrador editable, no del firmado.
--   · Contratos viejos con `pages` en base64: se siguen leyendo; al volver a guardarlos la pantalla sube y registra
--     primero TODAS sus páginas y solo después guarda sin `pages` (migración perezosa). Los bloqueados o con firma
--     viva no se tocan (contracts/tools/anexos_a_storage.py, preparado y sin ejecutar).
--
-- SEGURIDAD:
--   · Bucket PRIVADO nuevo (no se reutiliza `contratos-firmados`, que tiene otras reglas), solo image/jpeg y 3 MB por
--     página (la mayor medida en datos, un plano a 2.000 px, ~0,5 MB).
--   · Lectura: tabla y objetos, con `es_agente()` DELANTE — `contrato_visible()` no lo incluye y un comprador del
--     portal también tiene sesión. El objeto se lee solo si es la ruta EXACTA de una fila de un contrato visible
--     (comparación de texto, sin cast ::uuid sobre carpetas).
--   · Escritura: NINGUNA policy para authenticated (ni en la tabla ni en storage.objects). Sube la Edge `ficheros`
--     (clase `anexo_contrato`) por URL firmada sin upsert, con la ruta que decide ella, y registra con la RPC de
--     abajo, que solo ejecuta service_role actuando como el usuario de la sesión (`_actua_como`).
--   · Borrado: por barrido (contracts/tools/anexos_barrido.py), no en caliente. `on delete cascade` quita las filas con
--     el contrato; los objetos que se quedan sin fila los recoge el barrido.

-- ── bucket ───────────────────────────────────────────────────────────────────────────────────────────────────────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('contratos-anexos', 'contratos-anexos', false, 3145728, array['image/jpeg'])
on conflict (id) do nothing;

-- ── tabla ────────────────────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.contrato_anexo_paginas (
  id          uuid primary key default gen_random_uuid(),
  contrato_id uuid not null references public.contratos (id) on delete cascade,
  -- el id del anexo en datos.annexes[].id. Los nuevos son `ax-<uuid>`; los que pasan desde `pages` también estrenan uno.
  anexo_id    text not null check (anexo_id ~ '^ax[-0-9A-Za-z]{1,60}$'),
  n           int  not null check (n between 1 and 500),
  path        text not null unique,
  sha256      text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  bytes       int  not null check (bytes between 1 and 3145728),
  ancho       int  check (ancho is null or ancho between 1 and 20000),
  alto        int  check (alto is null or alto between 1 and 20000),
  creado_por  text,
  created_at  timestamptz not null default now(),
  unique (contrato_id, anexo_id, n)
);
comment on table public.contrato_anexo_paginas is
  'LAW-78: páginas (JPEG) de los anexos subidos a mano de un contrato, en el bucket contratos-anexos. Fuente única del recuento; datos.annexes guarda solo la ficha {id,title,on}. Solo escribe la Edge ficheros (contrato_anexo_registra).';

alter table public.contrato_anexo_paginas enable row level security;
revoke all on table public.contrato_anexo_paginas from public, anon, authenticated;
grant select on table public.contrato_anexo_paginas to authenticated;
grant all on table public.contrato_anexo_paginas to service_role;

drop policy if exists "anexos: el equipo lee las paginas de sus contratos" on public.contrato_anexo_paginas;
create policy "anexos: el equipo lee las paginas de sus contratos" on public.contrato_anexo_paginas
  for select to authenticated
  using (public.es_agente() and exists (
    select 1 from public.contratos c
     where c.id = contrato_anexo_paginas.contrato_id and public.contrato_visible(c.creado_por, c.proyecto_id)));

-- ── storage: una sola policy, de lectura ─────────────────────────────────────────────────────────────────────────
drop policy if exists "contratos-anexos: el equipo lee las paginas de sus contratos" on storage.objects;
create policy "contratos-anexos: el equipo lee las paginas de sus contratos" on storage.objects
  for select to authenticated
  using (bucket_id = 'contratos-anexos' and public.es_agente() and exists (
    select 1 from public.contrato_anexo_paginas p
      join public.contratos c on c.id = p.contrato_id
     where p.path = storage.objects.name and public.contrato_visible(c.creado_por, c.proyecto_id)));

-- ── ¿puede esta sesión añadir páginas de anexo a ESE contrato? ────────────────────────────────────────────────────
-- Las MISMAS reglas que contrato_guarda al editar (USING de la policy de UPDATE): agente con la herramienta
-- «contratos», el contrato existe y lo ve, sin bloquear y sin firma viva, es suyo o de un proyecto que supervisa, y
-- el proyecto es de los suyos. Aquí NADIE pasa con el contrato bloqueado o en firma, tampoco el super admin: un anexo
-- nuevo en un documento que ya no se puede guardar no sirve para nada.
-- Nunca `select *` de contratos: detoastaría `datos` entero (7 MB en el mayor). Solo las columnas que decide la regla.
-- Devuelve un código, no un booleano, para que la pantalla diga QUÉ pasa: 'ok' | 'sin_permiso' | 'no_visible' | 'bloqueado'.
-- 'no_visible' junta «no existe» y «no es tuyo» a propósito: no se revela si un id ajeno existe.
create or replace function public._contrato_anexo_check(p_contrato uuid) returns text
language plpgsql stable security definer set search_path = '' as $$
declare
  v_autor text; v_proy uuid; v_proy_nombre text; v_bloq boolean; v_fields jsonb;
begin
  if (select auth.uid()) is null then return 'sin_permiso'; end if;
  if not (public.es_agente() and public.puede('contratos')) then return 'sin_permiso'; end if;
  select c.creado_por, c.proyecto_id, c.proyecto_nombre, coalesce(c.bloqueado, false), c.datos_fields
    into v_autor, v_proy, v_proy_nombre, v_bloq, v_fields
    from public.contratos c where c.id = p_contrato;
  if not found then return 'no_visible'; end if;
  if not (public.es_super_admin() or public.contrato_visible(v_autor, v_proy)) then return 'no_visible'; end if;
  if v_bloq or public.contrato_firma_viva(p_contrato) then return 'bloqueado'; end if;
  if not (public.es_super_admin()
          or ((public.es_suyo(v_autor) or public.es_manager_de(v_proy))
              and public.puede_proyecto_de(jsonb_build_object('fields', v_fields), v_proy_nombre, v_proy))) then
    return 'sin_permiso';
  end if;
  return 'ok';
end $$;
revoke all on function public._contrato_anexo_check(uuid) from public, anon, authenticated;
grant execute on function public._contrato_anexo_check(uuid) to service_role;

-- La Edge pregunta con el JWT del usuario ANTES de firmar la subida.
create or replace function public.contrato_anexo_puede(p_contrato uuid) returns text
language sql stable security definer set search_path = '' as $$
  select public._contrato_anexo_check(p_contrato)
$$;
revoke all on function public.contrato_anexo_puede(uuid) from public, anon;
grant execute on function public.contrato_anexo_puede(uuid) to authenticated;

-- ── registrar una página ya subida (solo la Edge, como el usuario de la sesión) ──────────────────────────────────
-- La ruta tiene que ser `<id del contrato de la fila>/<uuid>/<n>.jpg`: el id se compara con el de la FILA leída,
-- no con uno que venga en el cuerpo, y el `n` de la ruta con el de la página. El objeto tiene que existir en ESTE
-- bucket y medir lo que dice la Edge (que lo ha descargado, comprobado que es JPEG y calculado su sha256).
create or replace function public.contrato_anexo_registra(p_uid uuid, p_contrato uuid, p_anexo_id text, p_n int,
                                                           p_path text, p_sha256 text, p_bytes int,
                                                           p_ancho int, p_alto int) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid; v_cid uuid; v_check text; v_size bigint;
begin
  perform public._actua_como(p_uid);
  v_check := public._contrato_anexo_check(p_contrato);
  if v_check = 'no_visible' then
    raise exception 'No encuentro ese contrato: guárdalo primero (o no es de los tuyos)' using errcode = '42501';
  elsif v_check = 'bloqueado' then
    raise exception 'Contrato enviado a firma o bloqueado: no admite anexos nuevos' using errcode = '23514';
  elsif v_check <> 'ok' then
    raise exception 'No tienes permiso para añadir anexos a este contrato' using errcode = '42501';
  end if;
  select c.id into v_cid from public.contratos c where c.id = p_contrato;
  if p_anexo_id is null or p_anexo_id !~ '^ax[-0-9A-Za-z]{1,60}$' then
    raise exception 'Anexo no válido: recarga la página' using errcode = '22023';
  end if;
  if p_n is null or p_n < 1 or p_n > 500 then raise exception 'Página no válida' using errcode = '22023'; end if;
  -- dos pasos: SQL no garantiza el orden de un `or`, y el cast a int de una ruta mala reventaría con otro mensaje
  if p_path is null
     or p_path !~ ('^' || v_cid::text || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9]{1,3}\.jpg$') then
    raise exception 'Ruta de la página no válida' using errcode = '22023';
  end if;
  if split_part(p_path, '/', 1) <> v_cid::text or split_part(split_part(p_path, '/', 3), '.', 1)::int <> p_n then
    raise exception 'Ruta de la página no válida' using errcode = '22023';
  end if;
  if p_sha256 is null or p_sha256 !~ '^[0-9a-f]{64}$' then raise exception 'Huella de la página no válida' using errcode = '22023'; end if;
  if p_bytes is null or p_bytes < 1 or p_bytes > 3145728 then raise exception 'Tamaño de la página no válido' using errcode = '22023'; end if;
  select (o.metadata->>'size')::bigint into v_size
    from storage.objects o where o.bucket_id = 'contratos-anexos' and o.name = p_path;
  if not found then raise exception 'La página no ha llegado al archivo: vuelve a subirla' using errcode = '22023'; end if;
  if v_size is not null and v_size <> p_bytes then
    raise exception 'La página del archivo no es la que se ha comprobado: vuelve a subirla' using errcode = '22023';
  end if;
  begin
    insert into public.contrato_anexo_paginas (contrato_id, anexo_id, n, path, sha256, bytes, ancho, alto, creado_por)
    values (v_cid, p_anexo_id, p_n, p_path, p_sha256, p_bytes,
            case when p_ancho between 1 and 20000 then p_ancho end,
            case when p_alto between 1 and 20000 then p_alto end,
            (select auth.email()))
    returning id into v_id;
  exception when unique_violation then
    raise exception 'Esa página ya está registrada' using errcode = '23505';
  end;
  return v_id;
end $$;
revoke all on function public.contrato_anexo_registra(uuid, uuid, text, int, text, text, int, int, int) from public, anon, authenticated;
grant execute on function public.contrato_anexo_registra(uuid, uuid, text, int, text, text, int, int, int) to service_role;
