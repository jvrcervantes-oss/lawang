-- destructivo-ok: solo crea objetos NUEVOS (tabla correos_cola vacía, funciones, un secreto de Vault y un job de cron que nace APAGADO). La función correos_cola_purga borra filas de la tabla nueva pero no se ejecuta aquí; ningún dato ni objeto existente se modifica ni se elimina.
-- (La migración se aplicó el 5-oct con la versión 20261005011702, la que registra Supabase; el nombre del fichero es esa versión.)
-- ============================================================================
-- AXW-202 C1 — COLA DE CORREOS (5-oct-2026)
-- ----------------------------------------------------------------------------
-- Encargo: encargos/20261002_estudio_cola_de_correos.md → «Plan revisado (5-oct-2026)», puntos 1-18
-- (revisión previa #204: Seguridad, Datos y Deploy). Molde: la cola de AXW-127
-- (20261001160000 + 20261005010948), SIN copiar su reclamo global (punto 6).
--
-- Qué es. Las funciones delicadas (firma-submit…) dejan de componer y mandar el correo dentro
-- de su petición: anotan «hay que mandar X sobre ESTE documento» (correo_encolar) y la edge
-- cola-correos-envio lo manda aparte, con el motor de envia-correo (plantillas).
--
-- EL DATO TIENE UN DUEÑO (patrones_tecnicos.md):
--   · Clave de plantilla  → dueño: correo_plantillas(clave). Aquí es FK, no copia.
--   · Documento           → dueño: contrato_firmas / contratos / facturas. La fila guarda SOLO su id
--                           (referencia, nunca copia): lo de hoy se lee al enviar.
--   · Destinatario        → dueño: el documento (contrato_firmas.firmante_email). NO se guarda en la
--                           cola: _correo_cola_destino lo resuelve al reclamar, con lista cerrada de
--                           claves. Una dirección copiada en la cola envejecería sin que nadie lo viera.
--   · Enlace de firma     → dueño: contrato_firmas.enlace_firma, que envia-correo lee al componer.
--                           Ni token ni URL ni texto renderizado en esta tabla (LAW-343).
--   · Registro del envío  → dueño: correos_enviados. El escritor es correo_cola_ok, en la MISMA
--                           transacción que marca la fila `ok` (envia-correo no lo escribe: punto 7).
--
-- Claves SOPORTADAS hoy: enlace_firma_cadena y aviso_anulacion (sin PDF, destinatario = firmante).
-- Las otras seis están declaradas en _correo_cola_regla con soportada=false y correo_encolar las
-- rechaza: las copias firmadas las lleva la cola de AXW-127 (C4 decide si se absorbe) y las
-- facturas necesitan PDF y destinatario resueltos por su dueño (C3). No hay filas muertas.
--
-- Ciclo de vida: pendiente → enviando (lease 4 min) → ok | error ; cancelado (el hecho dejó de ser
-- vigente: enlace revocado, firma ya firmada, contrato liberado). Entrega «al menos una vez»:
-- si el isolate muere con el correo ya aceptado y antes de cerrar, el reintento lo duplica.
-- Duplicado de enlace de firma = inocuo; de factura = no (por eso el índice único, punto 4).
--
-- INTERRUPTOR: el cron nace APAGADO (cron.job.active = false, se ve con
--   select jobname, active from cron.job where jobname = 'correos-cola-envio').
-- Encender (C2, con el OK del owner):  select cron.alter_job((select jobid from cron.job where jobname = 'correos-cola-envio'), active := true);
-- Reaplicar ESTA migración lo vuelve a apagar (a propósito: aquí nace apagado). El despertador por pg_net
-- (correo_encolar → _correos_cola_despierta) no depende del cron: lo que se encole se drena siempre.
-- Hoy NADIE llama a correo_encolar: es C2 (firma-submit) y C3.
--
-- LLAMADORES CON NOMBRE (seguridad_2026 §1.ter — lo nuevo nace cerrado):
--   correo_encolar            ← firma-submit (C2) y los llamantes que migre C3. service_role.
--   correo_cola_reclamar/ok/fallo, correos_cola_purga, cron_correos_cola_secret ← edge cola-correos-envio. service_role.
--   correo_cola_salud         ← tools/salud_lawang.py (invariante) y el briefing. service_role.
--   _correos_cola_despierta   ← correo_encolar y el cron «correos-cola-envio». Sin grants (owner).
--   _correo_cola_regla/_vigente/_destino ← reclamar / encolar (internas). Sin grants.
--   select sobre la tabla     ← service_role (diagnóstico). anon/authenticated: nada.
-- Repo público: ningún email ni uuid literal.
-- ============================================================================

-- ── reglas por clave (UN sitio; la edge y el test las cruzan) ────────────────
-- ancla: columna de correos_cola que identifica el documento. tope_horas: antigüedad máxima: pasada,
-- la fila pasa a `error` (un enlace de firma que sale tarde es un fallo que se ve, no un correo viejo).
-- prioridad: menor = antes (los enlaces de firma salen primero). via/asunto_registro: lo que se apunta en
-- correos_enviados (via es una de las del CHECK de esa tabla; el asunto es genérico a propósito: el texto
-- compuesto no se guarda y envia-correo no lo devuelve).
create or replace function public._correo_cola_regla(p_clave text)
returns table (ancla text, soportada boolean, tope_horas int, prioridad smallint, max_intentos int,
               via text, asunto_registro text, editables text[])
language sql immutable set search_path = '' as $$
  select r.ancla, r.soportada, r.tope_horas, r.prioridad, r.max_intentos, r.via, r.asunto_registro, r.editables
    from (values
      ('enlace_firma_cadena',     'firma_id',    true,   24, 1::smallint, 10, 'enlace_firma',   'Documento para firmar',        array[]::text[]),
      ('aviso_anulacion',         'firma_id',    true,   72, 5::smallint, 10, 'aviso_anulacion','Actualización del documento',  array[]::text[]),
      ('copia_firmada_comprador', 'contrato_id', false, 720, 5::smallint, 10, 'copia_firmada',  'Contrato firmado',             array['nombre']),
      ('copia_firmada_portal',    'contrato_id', false, 720, 5::smallint, 10, 'copia_firmada',  'Contrato firmado',             array['nombre']),
      ('copia_firmada_manual',    'contrato_id', false, 720, 5::smallint, 10, 'copia_firmada',  'Contrato firmado',             array['nombre']),
      ('factura_primer_hito',     'factura_id',  false, 720, 5::smallint, 10, 'factura',        'Factura',                      array['nombre']),
      ('proforma_total',          'factura_id',  false, 720, 5::smallint, 10, 'proforma',       'Factura proforma',             array['nombre']),
      ('factura_vencimiento',     'factura_id',  false, 720, 5::smallint, 10, 'factura_auto',   'Factura',                      array['nombre'])
    ) as r(clave, ancla, soportada, tope_horas, prioridad, max_intentos, via, asunto_registro, editables)
   where r.clave = p_clave
$$;

-- ── ¿el hecho que pidió este correo sigue vigente? (punto 3) ─────────────────
create or replace function public._correo_cola_vigente(p_clave text, p_firma uuid, p_contrato uuid, p_factura uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select case p_clave
    when 'enlace_firma_cadena' then exists (
      select 1 from public.contrato_firmas f join public.contratos c on c.id = f.contrato_id
       where f.id = p_firma and f.estado = 'pendiente' and f.anulado_en is null
         and f.enlace_firma is not null and f.expira_en > now() and c.liberado_en is null)
    when 'aviso_anulacion' then exists (
      select 1 from public.contrato_firmas f where f.id = p_firma and f.anulado_en is not null)
    else false
  end
$$;

-- ── destinatario: lo resuelve el dueño del dato, nunca la cola (punto 2) ─────
create or replace function public._correo_cola_destino(p_clave text, p_firma uuid, p_contrato uuid, p_factura uuid)
returns text language sql stable security definer set search_path = '' as $$
  select case when s.e ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' and char_length(s.e) <= 254 then s.e end
    from (select lower(btrim(f.firmante_email)) as e
            from public.contrato_firmas f
           where p_clave in ('enlace_firma_cadena', 'aviso_anulacion') and f.id = p_firma) s
$$;

-- ── la cola ──────────────────────────────────────────────────────────────────
create table public.correos_cola (
  id                uuid primary key default gen_random_uuid(),
  clave             text not null references public.correo_plantillas (clave),
  firma_id          uuid references public.contrato_firmas (id) on delete cascade,
  contrato_id       uuid references public.contratos (id) on delete cascade,
  factura_id        uuid references public.facturas (id) on delete cascade,
  vars              jsonb not null default '{}'::jsonb check (jsonb_typeof(vars) = 'object'),
  estado            text not null default 'pendiente'
                    check (estado in ('pendiente', 'enviando', 'ok', 'error', 'cancelado')),
  prioridad         smallint not null default 5,
  intentos          int not null default 0,
  proximo_intento_en timestamptz not null default now(),
  reclamado_hasta   timestamptz,
  error             text check (error is null or char_length(error) <= 300),
  encolado_en       timestamptz not null default now(),
  enviado_en        timestamptz,
  constraint correos_cola_un_ancla check (num_nonnulls(firma_id, contrato_id, factura_id) = 1)
);
comment on table public.correos_cola is
  'AXW-202 C1. Cola de correos con plantilla. Solo guarda clave + id del documento (sin destinatario, token, URL ni texto). La llena correo_encolar y la vacía la edge cola-correos-envio. Solo service_role.';

-- una sola fila viva por (clave, documento): factura-vencimiento corre por cron y reencolaría cada día
create unique index correos_cola_uno
  on public.correos_cola (clave, (coalesce(firma_id, contrato_id, factura_id)))
  where estado <> 'cancelado';
create index correos_cola_trabajo
  on public.correos_cola (prioridad, encolado_en) where estado in ('pendiente', 'enviando');

alter table public.correos_cola enable row level security;
revoke all on public.correos_cola from public, anon, authenticated;
grant select on public.correos_cola to service_role;

-- ── secreto propio de la edge (Vault, generado aquí dentro) ──────────────────
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'cron_correos_cola') then
    perform vault.create_secret(
      replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
      'cron_correos_cola',
      'Puerta de la edge cola-correos-envio (AXW-202). Solo la lee cron_correos_cola_secret().');
  end if;
end $$;

create or replace function public.cron_correos_cola_secret()
returns text language sql stable security definer set search_path = '' as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'cron_correos_cola';
$$;

-- ── despertador: pg_net hacia la edge, solo si hay trabajo ───────────────────
-- La URL sale de config_instancia.url_envio_correo (…/functions/v1/envia-correo → …/cola-correos-envio): sin
-- ref de proyecto escrito en el SQL, así que sirve igual en cualquier instancia. Si no hay trabajo, no llama.
create or replace function public._correos_cola_despierta()
returns void language plpgsql security definer set search_path = '' as $$
declare v_url text;
begin
  if not exists (select 1 from public.correos_cola q
                  where (q.estado = 'pendiente' and q.proximo_intento_en <= now())
                     or (q.estado = 'enviando' and q.reclamado_hasta <= now())) then
    return;
  end if;
  select regexp_replace(btrim(coalesce(g.valor #>> '{}', '')), '/envia-correo/?$', '/cola-correos-envio')
    into v_url from public.config_instancia g where g.clave = 'url_envio_correo';
  if v_url is null or v_url !~ '^https://[^[:space:]]+/cola-correos-envio$' then
    raise warning 'correos cola: url_envio_correo no apunta a envia-correo; la recoge el cron';
    return;
  end if;
  perform net.http_post(
    url     := v_url,
    headers := jsonb_build_object('Content-Type', 'application/json',
                                  'X-Cron-Secret', public.cron_correos_cola_secret()),
    body    := '{}'::jsonb,
    timeout_milliseconds := 60000);
exception when others then
  raise warning 'correos cola: no se pudo despertar la Edge (%): la recoge el cron', sqlerrm;
end $$;

-- ── encolar ──────────────────────────────────────────────────────────────────
-- Solo la clave y el id del documento (el de la columna que dice _correo_cola_regla). `vars`: solo las
-- variables editables de esa clave, texto corto sin URL, correo ni token (si no, error: no se ajusta).
-- Devuelve {id, estado, nuevo}. Si ya hay una fila viva para ese documento, no crea otra.
create or replace function public.correo_encolar(
  p_clave text, p_firma uuid default null, p_contrato uuid default null, p_factura uuid default null,
  p_vars jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  r      record;
  e      record;
  v      text;
  v_id   uuid;
  v_estado text;
begin
  select * into r from public._correo_cola_regla(p_clave);
  if not found then raise exception 'clave_desconocida' using errcode = '22023'; end if;
  if not r.soportada then raise exception 'clave_no_soportada_aun' using errcode = '22023'; end if;
  if num_nonnulls(p_firma, p_contrato, p_factura) <> 1
     or (r.ancla = 'firma_id'    and p_firma    is null)
     or (r.ancla = 'contrato_id' and p_contrato is null)
     or (r.ancla = 'factura_id'  and p_factura  is null) then
    raise exception 'ancla_invalida' using errcode = '22023';
  end if;
  if p_vars is null or jsonb_typeof(p_vars) <> 'object' then
    raise exception 'vars_invalidas' using errcode = '22023';
  end if;
  for e in select x.key as k, x.value as val from jsonb_each(p_vars) x loop
    v := e.val #>> '{}';
    if not (e.k = any (r.editables)) or jsonb_typeof(e.val) <> 'string'
       or char_length(v) > 120
       or v ~ '[@<>]|https?:|www[.]|[[:cntrl:]]|[A-Za-z0-9._-]{30,}' then
      raise exception 'vars_invalidas' using errcode = '22023';
    end if;
  end loop;

  insert into public.correos_cola (clave, firma_id, contrato_id, factura_id, vars, prioridad)
  values (p_clave, p_firma, p_contrato, p_factura, p_vars, r.prioridad)
  on conflict (clave, (coalesce(firma_id, contrato_id, factura_id))) where estado <> 'cancelado'
  do nothing
  returning id, estado into v_id, v_estado;

  if v_id is not null then
    perform public._correos_cola_despierta();
    return jsonb_build_object('id', v_id, 'estado', v_estado, 'nuevo', true);
  end if;

  select q.id, q.estado into v_id, v_estado
    from public.correos_cola q
   where q.clave = p_clave and q.estado <> 'cancelado'
     and coalesce(q.firma_id, q.contrato_id, q.factura_id) = coalesce(p_firma, p_contrato, p_factura);
  return jsonb_build_object('id', v_id, 'estado', v_estado, 'nuevo', false);
end $$;

-- ── reclamar: lease por fila, sin pasada global (punto 6) ────────────────────
-- Antes de coger nada cierra lo que ya no procede, sin gastar intentos:
--   · el hecho dejó de ser vigente        → cancelado
--   · pasó su tope de antigüedad          → error (visible: no se manda un enlace caducado)
--   · sin destinatario resoluble          → error
--   · lease vencido con los intentos agotados → error
-- Devuelve el destinatario resuelto por el dueño del dato y el contrato del documento.
create or replace function public.correo_cola_reclamar(p_max int default 5)
returns table (id uuid, clave text, firma_id uuid, contrato_id uuid, factura_id uuid,
               vars jsonb, para text, prioridad smallint, intentos int)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  update public.correos_cola q set estado = 'cancelado', error = 'hecho_no_vigente', reclamado_hasta = null
   where (q.estado = 'pendiente' or (q.estado = 'enviando' and q.reclamado_hasta <= now()))
     and not public._correo_cola_vigente(q.clave, q.firma_id, q.contrato_id, q.factura_id);

  update public.correos_cola q set estado = 'error', error = 'tope_antiguedad', reclamado_hasta = null
   where (q.estado = 'pendiente' or (q.estado = 'enviando' and q.reclamado_hasta <= now()))
     and q.encolado_en + make_interval(hours => (select r.tope_horas from public._correo_cola_regla(q.clave) r)) < now();

  update public.correos_cola q set estado = 'error', error = 'sin_destinatario', reclamado_hasta = null
   where (q.estado = 'pendiente' or (q.estado = 'enviando' and q.reclamado_hasta <= now()))
     and public._correo_cola_destino(q.clave, q.firma_id, q.contrato_id, q.factura_id) is null;

  update public.correos_cola q set estado = 'error', error = 'agotado', reclamado_hasta = null
   where q.estado = 'enviando' and q.reclamado_hasta <= now()
     and q.intentos >= (select r.max_intentos from public._correo_cola_regla(q.clave) r);

  return query
  with cand as (
    select x.id as cid
      from public.correos_cola x
     where (x.estado = 'pendiente' and x.proximo_intento_en <= now())
        or (x.estado = 'enviando' and x.reclamado_hasta <= now())
     order by x.prioridad, x.encolado_en
     limit least(greatest(coalesce(p_max, 5), 1), 10)
     for update of x skip locked)
  update public.correos_cola q
     set estado = 'enviando', reclamado_hasta = now() + interval '4 minutes', intentos = q.intentos + 1
    from cand
   where q.id = cand.cid
  returning q.id, q.clave, q.firma_id,
            coalesce(q.contrato_id, (select f.contrato_id from public.contrato_firmas f where f.id = q.firma_id)),
            q.factura_id, q.vars,
            public._correo_cola_destino(q.clave, q.firma_id, q.contrato_id, q.factura_id),
            q.prioridad, q.intentos;
end $$;

-- ── cerrar ok: el registro en correos_enviados va en la MISMA transacción ────
-- p_para: la dirección a la que salió (la que devolvió reclamar). p_version: la que contestó envia-correo
-- ('v3' o 'f:ab12cd34'); si no cuadra con el CHECK de correos_enviados se registra sin ella antes que perder el registro.
-- Devuelve false si la fila ya no estaba `enviando` (otro drenador la tomó tras vencer el lease): entonces no se registra.
create or replace function public.correo_cola_ok(p_id uuid, p_para text, p_version text)
returns boolean language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  r  record;
  g  record;
begin
  update public.correos_cola q
     set estado = 'ok', error = null, enviado_en = now(), reclamado_hasta = null
   where q.id = p_id and q.estado = 'enviando'
  returning q.clave, q.firma_id, q.contrato_id, q.factura_id into r;
  if not found then return false; end if;
  select * into g from public._correo_cola_regla(r.clave);

  insert into public.correos_enviados
         (contrato_id, factura_id, para, asunto, via, enviado_por, mensaje, plantilla, plantilla_version)
  values (coalesce(r.contrato_id, (select f.contrato_id from public.contrato_firmas f where f.id = r.firma_id)),
          r.factura_id, lower(btrim(p_para)), g.asunto_registro, g.via, null, null,
          case when p_version ~ '^(v[0-9]{1,6}|f:[0-9a-f]{8})$' then r.clave end,
          case when p_version ~ '^(v[0-9]{1,6}|f:[0-9a-f]{8})$' then p_version end);
  return true;
end $$;

-- ── cerrar con fallo ─────────────────────────────────────────────────────────
-- p_terminal: no se reintenta. p_devolver: no es culpa de este correo (pausa, bloqueo del proveedor, credencial): vuelve a la
-- cola SIN gastar el intento. Backoff 1,2,4,8,16 y luego 30 min (o p_espera_s, 0-3600). Sin direcciones en el error.
-- Devuelve el estado en que queda.
create or replace function public.correo_cola_fallo(
  p_id uuid, p_error text, p_terminal boolean default false, p_devolver boolean default false, p_espera_s int default null)
returns text language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare v text;
begin
  update public.correos_cola q
     set estado = case when p_terminal
                         or (not p_devolver and q.intentos >= (select r.max_intentos from public._correo_cola_regla(q.clave) r))
                       then 'error' else 'pendiente' end,
         intentos = case when p_devolver then greatest(q.intentos - 1, 0) else q.intentos end,
         proximo_intento_en = now() + make_interval(secs => case
             when p_espera_s is not null then least(greatest(p_espera_s, 0), 3600)
             else least(60 * power(2, greatest(q.intentos - 1, 0)), 1800) end),
         error = left(regexp_replace(coalesce(p_error, ''), '\S+@\S+', '<correo>', 'g'), 300),
         reclamado_hasta = null
   where q.id = p_id and q.estado = 'enviando'
  returning q.estado into v;
  return v;
end $$;

-- ── retención (punto 12): lo terminado hace más de 90 días ───────────────────
create or replace function public.correos_cola_purga()
returns int language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  delete from public.correos_cola q
   where q.estado in ('ok', 'cancelado', 'error')
     and coalesce(q.enviado_en, q.encolado_en) < now() - interval '90 days';
  get diagnostics n = row_count;
  return n;
end $$;

-- ── salud (punto 16): lo que se ve FUERA del SMTP ────────────────────────────
-- Cuenta lo que está mal; la lee tools/salud_lawang.py (devuelve filas solo si algo falla).
create or replace function public.correo_cola_salud(p_pendiente_min int default 10)
returns table (enviando_atascadas bigint, pendientes_antiguas bigint, en_error bigint, mas_antigua_min bigint)
language sql stable security definer set search_path = '' as $$
  select count(*) filter (where q.estado = 'enviando' and q.reclamado_hasta < now() - interval '11 minutes'),
         count(*) filter (where q.estado = 'pendiente' and q.proximo_intento_en < now() - make_interval(mins => greatest(p_pendiente_min, 1))),
         count(*) filter (where q.estado = 'error'),
         coalesce(max(extract(epoch from now() - q.encolado_en)::bigint / 60)
                  filter (where q.estado in ('pendiente', 'enviando')), 0)
    from public.correos_cola q
$$;

-- ── permisos: EXECUTE llega por PUBLIC y por los default privileges de Supabase si no se revoca ──
revoke execute on function public._correo_cola_regla(text)                          from public, anon, authenticated, service_role;
revoke execute on function public._correo_cola_vigente(text, uuid, uuid, uuid)       from public, anon, authenticated, service_role;
revoke execute on function public._correo_cola_destino(text, uuid, uuid, uuid)       from public, anon, authenticated, service_role;
revoke execute on function public._correos_cola_despierta()                          from public, anon, authenticated, service_role;
revoke execute on function public.cron_correos_cola_secret()                         from public, anon, authenticated;
revoke execute on function public.correo_encolar(text, uuid, uuid, uuid, jsonb)      from public, anon, authenticated;
revoke execute on function public.correo_cola_reclamar(int)                          from public, anon, authenticated;
revoke execute on function public.correo_cola_ok(uuid, text, text)                   from public, anon, authenticated;
revoke execute on function public.correo_cola_fallo(uuid, text, boolean, boolean, int) from public, anon, authenticated;
revoke execute on function public.correos_cola_purga()                               from public, anon, authenticated;
revoke execute on function public.correo_cola_salud(int)                             from public, anon, authenticated;
grant  execute on function public.cron_correos_cola_secret()                         to service_role;
grant  execute on function public.correo_encolar(text, uuid, uuid, uuid, jsonb)      to service_role;
grant  execute on function public.correo_cola_reclamar(int)                          to service_role;
grant  execute on function public.correo_cola_ok(uuid, text, text)                   to service_role;
grant  execute on function public.correo_cola_fallo(uuid, text, boolean, boolean, int) to service_role;
grant  execute on function public.correos_cola_purga()                               to service_role;
grant  execute on function public.correo_cola_salud(int)                             to service_role;

-- ── cron: cada minuto, NACE APAGADO ──────────────────────────────────────────
-- `cron.schedule` con nombre actualiza el job si ya existe (no duplica). La función solo llama a la edge si hay trabajo.
select cron.schedule('correos-cola-envio', '* * * * *', $cron$select public._correos_cola_despierta();$cron$);
select cron.alter_job((select j.jobid from cron.job j where j.jobname = 'correos-cola-envio'), active := false);
