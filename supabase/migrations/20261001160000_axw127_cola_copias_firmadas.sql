-- destructivo-ok: solo sustituye dos CHECK de correos_enviados (el de `via` gana el valor copia_firmada; los datos no cambian y se revalidan contra todas las filas) y define la purga de 90 días de la tabla NUEVA copias_firmadas_envios (una función que aún no se ejecuta); no borra ni modifica nada existente.
-- ============================================================================
-- AXW-127 — COLA DE COPIAS FIRMADAS — 1-oct-2026
-- ----------------------------------------------------------------------------
-- Problema: firma-submit repartía el contrato firmado DENTRO de la petición de
-- firma. Con un PDF grande eso (a) tumbó el reparto el 17-ago («solo el primero
-- y yo lo recibimos») y (b) se arregló mandando un ENLACE FIRMADO de 30 días a
-- todos, que es una URL con credencial en el cuerpo de un correo.
--
-- Decisión del owner (1-oct): quien puede entrar al portal recibe un correo de
-- texto con el enlace al portal; el resto recibe el PDF adjunto en un correo
-- individual desde una COLA, fuera de la petición de firma.
--
-- Plan: encargos/20260930_erp_ajustes_pantalla.md → «Plan de AXW-127» y
-- «Revisión previa #186» (Seguridad, Datos, Deploy). Lo que esta migración
-- recoge de la revisión:
--  · El navegador no toca nada de esto: todo son RPC de service_role. La tabla
--    tiene RLS activo y ningún grant a anon/authenticated.
--  · `copia_firmada_encolar` recibe SOLO el contrato: los destinos, el PDF, su
--    sha y su tamaño los calcula la base (contratos.pdf_firmado_*, el objeto del
--    bucket). La edge no pasa emails ni rutas.
--  · `portal_elegible` copia la regla literal de portal_ve_pdf (fila activa de
--    portal_accesos unida por contrato_compradores a ESE contrato), no la de
--    portal_autoservicio (que escribe y acepta al cliente de cualquier
--    contrato). Ante la duda: adjunto, nunca enlace.
--  · Ciclo de vida: pendiente → enviando → ok | error; cancelado (contrato
--    liberado/desbloqueado) y obsoleto (el sha ya no es el del contrato) son
--    terminales y no gastan intentos.
--  · Una sola pasada viva a la vez; una fila si el PDF pesa más de 10 MB.
--  · Entrega «al menos una vez»: si el isolate muere con el correo ya aceptado
--    y antes de cerrar, el reintento lo duplica. Máximo 3 intentos. Queda dicho.
--  · Secreto PROPIO de la edge en Vault (cron_copias_firmadas), generado aquí
--    dentro: no pasa por disco ni por consola.
--  · Sin net.http_post en esta migración: el despertador y el cron van en una
--    migración aparte, DESPUÉS de desplegar la edge (con el OK del owner).
--  · Repo público: ningún email ni uuid literal.
-- ============================================================================

-- ── interruptor: el código nuevo de firma-submit sale APAGADO ───────────────
insert into public.config_instancia (clave, valor, descripcion)
values ('copias_firmadas_modo', '"enlace"'::jsonb,
        'AXW-127. «enlace» = reparto antiguo (enlace firmado de 30 días en los PDF grandes); «cola» = portal para quien puede entrar y cola de adjuntos para el resto. Apagar = volver a «enlace», sin redespliegue.')
on conflict (clave) do nothing;

-- ── correos_enviados: referencia al PDF firmado y la vía nueva ──────────────
-- `pdf_path` ya existía con otro significado (copia en el bucket
-- `correos-enviados`). `pdf_bucket` dice de qué bucket es la ruta; nulo = el
-- bucket de siempre. Quien lee esta tabla ya puede leer el PDF por la policy de
-- storage de su rol (agente_ve_contrato_pdf / es_admin): no se añade lectura.
alter table public.correos_enviados add column if not exists pdf_bucket text;
alter table public.correos_enviados drop constraint if exists correos_enviados_pdf_bucket_check;
alter table public.correos_enviados add constraint correos_enviados_pdf_bucket_check
  check (pdf_bucket is null or pdf_bucket in ('correos-enviados', 'contratos-firmados'));

alter table public.correos_enviados drop constraint if exists correos_enviados_via_check;
alter table public.correos_enviados add constraint correos_enviados_via_check
  check (via = any (array['manual','enlace_firma','firma','proforma','factura','factura_auto','aviso_anulacion','copia_firmada']));

-- ── la cola ─────────────────────────────────────────────────────────────────
create table public.copias_firmadas_envios (
  id           uuid primary key default gen_random_uuid(),
  contrato_id  uuid not null references public.contratos(id) on delete cascade,
  email        text not null check (email = lower(btrim(email))),
  nombre       text check (nombre is null or char_length(nombre) <= 120),
  pdf_sha256   text not null,
  pdf_bytes    integer not null,
  estado       text not null default 'pendiente'
               check (estado in ('pendiente','enviando','ok','error','cancelado','obsoleto')),
  intentos     int not null default 0,
  error        text check (error is null or char_length(error) <= 300),
  encolado_en  timestamptz not null default now(),
  reclamado_en timestamptz,
  enviado_en   timestamptz
);
comment on table public.copias_firmadas_envios is
  'AXW-127. Cola de copias del contrato firmado que van como adjunto. La llena copia_firmada_encolar (firma-submit) y la vacía la edge copias-firmadas-envio. Solo service_role.';
-- un reintento de firma-submit (re-sube el PDF con upsert) no duplica
create unique index copias_firmadas_envios_uno
  on public.copias_firmadas_envios (contrato_id, email, pdf_sha256);
create index copias_firmadas_envios_cola
  on public.copias_firmadas_envios (encolado_en) where estado in ('pendiente','enviando');

alter table public.copias_firmadas_envios enable row level security;
revoke all on public.copias_firmadas_envios from public, anon, authenticated;
grant all on public.copias_firmadas_envios to service_role;

-- ── despertador: en esta migración no hace nada (ver cabecera) ──────────────
create or replace function public._copias_firmadas_despierta()
returns void language plpgsql security definer set search_path = '' as $$
begin
  null;
end $$;
revoke execute on function public._copias_firmadas_despierta() from public, anon, authenticated;

-- ── ¿puede este email ver ESTE contrato en el portal? ───────────────────────
-- Misma condición que portal_ve_pdf salvo la parte de sesión (es_portal() y
-- auth.email(), que dependen del JWT del comprador). Además excluye al equipo y
-- a quien tenga un acceso revocado, que es lo que rechaza el portal al entrar.
create or replace function public.portal_elegible(p_email text, p_contrato uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
           select 1
             from public.contratos c
             join public.contrato_compradores cc on cc.contrato_id = c.id
             join public.portal_accesos pa on pa.client_id = cc.client_id
            where c.id = p_contrato
              and c.pdf_firmado_path is not null
              and pa.activo
              and pa.email = lower(btrim(coalesce(p_email, ''))))
     and not exists (
           select 1 from public.usuarios u
            where lower(btrim(u.email)) = lower(btrim(coalesce(p_email, ''))))
     and not exists (
           select 1 from public.portal_accesos pa
            where pa.email = lower(btrim(coalesce(p_email, ''))) and not pa.activo)
$$;

-- ── a quién se le manda el firmado (la lógica de destinosFirmado, en la base) ─
-- Espejo de repartirFirmado/destinosFirmado en firma-submit: el estudio primero
-- y siempre; el comprador 1 y los demás compradores con NOMBRE (el reparto
-- descarta los que no lo tienen); los firmantes con estado 'firmado'; dirección
-- válida; sin duplicados por lower(btrim()). Si cambia allí, cambia aquí: un
-- test cruza las dos sobre los contratos firmados.
-- El email del estudio sale de config_instancia (email_estudio_copias, y si no
-- existe email_avisos_sistema): nunca literal en un repo público.
create or replace function public.copias_firmadas_destinos(p_contrato uuid)
returns table (email text, nombre text, estudio boolean, equipo boolean, elegible boolean)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  v_fields jsonb;
  v_comp   jsonb;
  v_estudio text;
begin
  select c.datos->'fields', c.datos->'compradores' into v_fields, v_comp
    from public.contratos c where c.id = p_contrato;
  if not found then return; end if;

  select btrim(coalesce(g.valor #>> '{}', '')) into v_estudio
    from public.config_instancia g where g.clave = 'email_estudio_copias';
  if v_estudio is null or v_estudio = '' then
    select btrim(coalesce(g.valor #>> '{}', '')) into v_estudio
      from public.config_instancia g where g.clave = 'email_avisos_sistema';
  end if;

  return query
  with cand as (
    select 0 as g, 0::bigint as o, coalesce(v_estudio, '') as em, null::text as nom, true as est
    union all
    select 1, 0::bigint, btrim(coalesce(v_fields->>'adq1_email', '')),
           btrim(coalesce(v_fields->>'adq1_nombre', '')), false
     where btrim(coalesce(v_fields->>'adq1_nombre', '')) <> ''
    union all
    select 1, e.ord, btrim(coalesce(e.v->>'email', '')), btrim(coalesce(e.v->>'nombre', '')), false
      from jsonb_array_elements(case when jsonb_typeof(v_comp) = 'array' then v_comp else '[]'::jsonb end)
           with ordinality as e(v, ord)
     where btrim(coalesce(e.v->>'nombre', '')) <> ''
    union all
    select 2, row_number() over (order by f.firmado_en nulls last, f.creado_en),
           btrim(coalesce(f.firmante_email, '')), btrim(coalesce(f.firmante_nombre, '')), false
      from public.contrato_firmas f
     where f.contrato_id = p_contrato and f.estado = 'firmado'
  ), valido as (
    select * from cand
     where cand.em ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
  ), uno as (
    select distinct on (lower(valido.em)) valido.*
      from valido order by lower(valido.em), valido.g, valido.o
  )
  select uno.em, nullif(uno.nom, ''), uno.est,
         exists (select 1 from public.usuarios u where lower(btrim(u.email)) = lower(uno.em)),
         (not uno.est) and public.portal_elegible(uno.em, p_contrato)
    from uno order by uno.g, uno.o;
end $$;

-- ── encolar: lo llama firma-submit con SOLO el contrato ─────────────────────
-- Devuelve qué hacer con cada destino:
--   portal    → correo de texto con el enlace al portal (lo manda firma-submit)
--   cola      → adjunto por la cola (esta función ya lo encoló)
--   intranet  → estudio/equipo con un PDF demasiado grande para adjuntar:
--               correo de texto con enlace a la intranet (lo manda firma-submit)
--   error     → comprador fuera del portal con PDF demasiado grande: queda una
--               fila 'error' visible; resolver a mano
-- Umbral de adjunto: 18 000 000 bytes. Gmail rechaza más de 25 MB INCLUIDO el
-- base64 (×1,37): 18e6 × 1,37 = 24,7e6, por debajo con MB y con MiB.
create or replace function public.copia_firmada_encolar(p_contrato uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  c       record;
  d       record;
  v_bytes bigint;
  v_modo  text;
  v_estado text;
  v_out   jsonb := '[]'::jsonb;
  v_encolo boolean := false;
  v_max   constant bigint := 18000000;
begin
  select ct.id, ct.numero, ct.bloqueado, ct.liberado_en,
         ct.pdf_firmado_path as ruta, ct.pdf_firmado_hash as sha
    into c from public.contratos ct where ct.id = p_contrato;
  if not found then
    raise exception 'contrato_inexistente' using errcode = 'P0002';
  end if;
  if not c.bloqueado or c.liberado_en is not null or c.ruta is null or c.sha is null then
    raise exception 'contrato_sin_pdf_firmado' using errcode = '22023';
  end if;
  select (o.metadata->>'size')::bigint into v_bytes
    from storage.objects o where o.bucket_id = 'contratos-firmados' and o.name = c.ruta;
  if v_bytes is null then
    raise exception 'pdf_no_encontrado' using errcode = 'P0002';
  end if;

  for d in select * from public.copias_firmadas_destinos(p_contrato) loop
    if d.elegible then v_modo := 'portal';
    elsif v_bytes <= v_max then v_modo := 'cola';
    elsif d.estudio or d.equipo then v_modo := 'intranet';
    else v_modo := 'error';
    end if;

    v_estado := null;
    if v_modo in ('cola', 'error') then
      insert into public.copias_firmadas_envios
             (contrato_id, email, nombre, pdf_sha256, pdf_bytes, estado, error)
      values (p_contrato, lower(btrim(d.email)), left(d.nombre, 120), c.sha, v_bytes::int,
              case when v_modo = 'cola' then 'pendiente' else 'error' end,
              case when v_modo = 'error' then 'pdf_demasiado_grande_para_adjuntar' else null end)
      on conflict (contrato_id, email, pdf_sha256) do update
         set estado = 'pendiente', intentos = 0, error = null, reclamado_en = null, encolado_en = now()
       where public.copias_firmadas_envios.estado = 'error' and excluded.estado = 'pendiente'
      returning estado into v_estado;
      if v_estado is null then
        select e.estado into v_estado from public.copias_firmadas_envios e
         where e.contrato_id = p_contrato and e.email = lower(btrim(d.email)) and e.pdf_sha256 = c.sha;
      end if;
      if v_modo = 'cola' and v_estado = 'pendiente' then v_encolo := true; end if;
    end if;

    v_out := v_out || jsonb_build_object(
      'email', d.email, 'nombre', d.nombre, 'estudio', d.estudio, 'equipo', d.equipo,
      'modo', v_modo, 'estado', v_estado);
  end loop;

  if v_encolo then perform public._copias_firmadas_despierta(); end if;
  return jsonb_build_object('numero', c.numero, 'bytes', v_bytes, 'max_adjunto', v_max, 'destinos', v_out);
end $$;

-- ── reclamar: la edge coge su tanda (solo service_role) ─────────────────────
-- Todo lo que devuelve sale de contratos y del objeto del bucket, no de lo que
-- se guardó al encolar: si el contrato cambió, la fila se cierra sin enviar.
create or replace function public.copia_firmada_reclamar(p_tope int default 3)
returns table (id uuid, contrato_id uuid, numero text, proyecto text, email text, nombre text,
               pdf_path text, pdf_sha256 text, pdf_bytes bigint, intentos int)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  v_primero uuid;
  v_grande  boolean;
begin
  -- una sola pasada viva a la vez
  if exists (select 1 from public.copias_firmadas_envios e
              where e.estado = 'enviando' and e.reclamado_en > now() - interval '15 minutes') then
    return;
  end if;

  -- terminales que no gastan intentos ni avisan
  update public.copias_firmadas_envios e set estado = 'cancelado', reclamado_en = null
    from public.contratos ct
   where ct.id = e.contrato_id
     and (e.estado = 'pendiente' or e.estado = 'enviando')
     and (ct.liberado_en is not null or not ct.bloqueado);
  update public.copias_firmadas_envios e set estado = 'obsoleto', reclamado_en = null
    from public.contratos ct
   where ct.id = e.contrato_id
     and (e.estado = 'pendiente' or e.estado = 'enviando')
     and ct.pdf_firmado_hash is distinct from e.pdf_sha256;
  -- 404 del bucket = terminal
  update public.copias_firmadas_envios e set estado = 'error', error = 'pdf_no_encontrado', reclamado_en = null
    from public.contratos ct
   where ct.id = e.contrato_id
     and (e.estado = 'pendiente' or e.estado = 'enviando')
     and not exists (select 1 from storage.objects o
                      where o.bucket_id = 'contratos-firmados' and o.name = ct.pdf_firmado_path);
  -- la pasada murió tres veces con la fila cogida
  update public.copias_firmadas_envios e set estado = 'error', error = 'agotado', reclamado_en = null
   where e.estado = 'enviando' and e.reclamado_en <= now() - interval '15 minutes' and e.intentos >= 3;

  select e.id, (o.metadata->>'size')::bigint > 10000000 into v_primero, v_grande
    from public.copias_firmadas_envios e
    join public.contratos ct on ct.id = e.contrato_id
    join storage.objects o on o.bucket_id = 'contratos-firmados' and o.name = ct.pdf_firmado_path
   where e.estado = 'pendiente'
      or (e.estado = 'enviando' and e.reclamado_en <= now() - interval '15 minutes')
   order by e.encolado_en
   limit 1
   for update of e skip locked;
  if v_primero is null then return; end if;

  return query
  with cand as (
    select e.id as cid
      from public.copias_firmadas_envios e
      join public.contratos ct on ct.id = e.contrato_id
      join storage.objects o on o.bucket_id = 'contratos-firmados' and o.name = ct.pdf_firmado_path
     where e.id = v_primero
        or (not v_grande
            and (e.estado = 'pendiente'
                 or (e.estado = 'enviando' and e.reclamado_en <= now() - interval '15 minutes'))
            and (o.metadata->>'size')::bigint <= 10000000)
     order by (e.id = v_primero) desc, e.encolado_en
     limit case when v_grande then 1 else least(greatest(coalesce(p_tope, 3), 1), 3) end
     for update of e skip locked)
  update public.copias_firmadas_envios e
     set estado = 'enviando', reclamado_en = now(), intentos = e.intentos + 1
    from cand, public.contratos ct, storage.objects o
   where e.id = cand.cid and ct.id = e.contrato_id
     and o.bucket_id = 'contratos-firmados' and o.name = ct.pdf_firmado_path
  returning e.id, e.contrato_id, ct.numero, ct.proyecto_nombre, e.email, e.nombre,
            ct.pdf_firmado_path, ct.pdf_firmado_hash, (o.metadata->>'size')::bigint, e.intentos;
end $$;

-- ── cerrar: ok (con el registro en correos_enviados, en la MISMA transacción) ─
-- Se llama con el envío ya aceptado. `mensaje` es la plantilla fija del correo
-- (sin token, sin URL firmada, sin importes ni nombres de otros compradores).
create or replace function public.copia_firmada_ok(p_id uuid, p_asunto text, p_mensaje text)
returns boolean language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare r record;
begin
  update public.copias_firmadas_envios e
     set estado = 'ok', error = null, enviado_en = now(), reclamado_en = null
   where e.id = p_id and e.estado = 'enviando'
  returning e.contrato_id, e.email, e.pdf_sha256, e.pdf_bytes into r;
  if not found then return false; end if;

  insert into public.correos_enviados
         (contrato_id, para, asunto, via, enviado_por, mensaje, pdf_path, pdf_bucket, pdf_sha256, pdf_bytes)
  select r.contrato_id, r.email, left(coalesce(p_asunto, ''), 200), 'copia_firmada',
         null, left(coalesce(p_mensaje, ''), 2000),
         ct.pdf_firmado_path, 'contratos-firmados', r.pdf_sha256, r.pdf_bytes
    from public.contratos ct where ct.id = r.contrato_id;
  return true;
end $$;

-- ── cerrar: fallo ───────────────────────────────────────────────────────────
-- p_terminal: no se reintenta. p_devolver: no es culpa de este destinatario
-- (bloqueo del proveedor): vuelve a la cola SIN gastar el intento.
-- El error se recorta a 300 y pierde cualquier dirección de correo.
-- Devuelve el estado en que queda (la edge avisa al admin si es 'error').
create or replace function public.copia_firmada_fallo(
  p_id uuid, p_error text, p_terminal boolean default false, p_devolver boolean default false)
returns text language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare v text;
begin
  update public.copias_firmadas_envios e
     set estado = case when p_terminal or (not p_devolver and e.intentos >= 3) then 'error' else 'pendiente' end,
         intentos = case when p_devolver then greatest(e.intentos - 1, 0) else e.intentos end,
         error = left(regexp_replace(coalesce(p_error, ''), '\S+@\S+', '<correo>', 'g'), 300),
         reclamado_en = null
   where e.id = p_id and e.estado = 'enviando'
  returning e.estado into v;
  return v;
end $$;

-- ── retención: las filas terminadas guardan email y nombre de un comprador ──
create or replace function public.copias_firmadas_purga()
returns int language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  delete from public.copias_firmadas_envios e
   where e.estado in ('ok', 'cancelado', 'obsoleto')
     and coalesce(e.enviado_en, e.encolado_en) < now() - interval '90 days';
  get diagnostics n = row_count;
  return n;
end $$;

-- ── secreto propio de la edge (generado aquí, en la base) ───────────────────
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'cron_copias_firmadas') then
    perform vault.create_secret(
      replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
      'cron_copias_firmadas',
      'Puerta de la edge copias-firmadas-envio (AXW-127). Solo la lee cron_copias_firmadas_secret().');
  end if;
end $$;

create or replace function public.cron_copias_firmadas_secret()
returns text language sql stable security definer set search_path = '' as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'cron_copias_firmadas';
$$;

-- ── permisos: EXECUTE llega por PUBLIC si no se revoca (seguridad_2026 §1.ter) ─
revoke execute on function public.portal_elegible(text, uuid)               from public, anon, authenticated;
revoke execute on function public.copias_firmadas_destinos(uuid)            from public, anon, authenticated;
revoke execute on function public.copia_firmada_encolar(uuid)               from public, anon, authenticated;
revoke execute on function public.copia_firmada_reclamar(int)               from public, anon, authenticated;
revoke execute on function public.copia_firmada_ok(uuid, text, text)        from public, anon, authenticated;
revoke execute on function public.copia_firmada_fallo(uuid, text, boolean, boolean) from public, anon, authenticated;
revoke execute on function public.copias_firmadas_purga()                   from public, anon, authenticated;
revoke execute on function public.cron_copias_firmadas_secret()             from public, anon, authenticated;
grant  execute on function public.portal_elegible(text, uuid)               to service_role;
grant  execute on function public.copias_firmadas_destinos(uuid)            to service_role;
grant  execute on function public.copia_firmada_encolar(uuid)               to service_role;
grant  execute on function public.copia_firmada_reclamar(int)               to service_role;
grant  execute on function public.copia_firmada_ok(uuid, text, text)        to service_role;
grant  execute on function public.copia_firmada_fallo(uuid, text, boolean, boolean) to service_role;
grant  execute on function public.copias_firmadas_purga()                   to service_role;
grant  execute on function public.cron_copias_firmadas_secret()             to service_role;
