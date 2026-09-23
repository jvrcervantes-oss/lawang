-- destructivo-ok: los DELETE viven dentro de funciones y solo tocan las dos tablas nuevas de esta migración (vacías al crearse) y el secreto Vault de una cuenta al darla de baja — minimización pedida por Legal.
-- Trazabilidad GHL — 23-sep-2026 (owner: «centralizar para ver si un cliente entra por
-- distintos funnels y que no nos apriete con descuentos jugando a doble banda»).
--
-- Cruza los leads de Lawang con los contactos de las cuentas GoHighLevel PROPIAS de los
-- sales managers (cada uno con sus campañas). Solo lectura sobre GHL, nunca escribe allí.
--
-- Revisión previa #49 (Seguridad + Legal), lo que la forma de esto:
--  · Solo super_admin ve y gestiona. Los closers son justo de quien se protege: con la
--    vista, un sales manager vería en qué otras cuentas aparecen sus clientes.
--  · Nada de teléfono/email en claro: HMAC-SHA256 con un pepper que vive en los secrets de
--    la Edge `trazabilidad-ghl`, NUNCA en esta base (un teléfono son ~10^9 valores: con el
--    pepper al lado de los hashes se revierten todos en minutos).
--  · Minimización (Legal): solo se guardan huellas que COINCIDEN con otra fuente; el resto
--    se descarta en memoria en cada pasada. Borrar una cuenta borra su token y sus filas.
--  · Una cuenta no puede activarse sin fecha de adenda firmada (Legal: base = interés
--    legítimo de Lawang como responsable; el sales manager actúa por cuenta de Lawang).
--    El CHECK lo hace mecánico, no una promesa.
--  · Una coincidencia es una SEÑAL para que la mire una persona, nunca un «no» automático
--    a un descuento (art. 22 RGPD / UU PDP). La UI lo dice así.
--  · El token (pit-…) va a Vault vía la Edge, como parámetro de RPC — nunca como literal
--    en un SQL, que acabaría en logs / pg_stat_statements.

create table if not exists public.traza_cuentas (
  id               uuid primary key default gen_random_uuid(),
  nombre           text not null,                 -- «Sales manager X» — visible solo a super_admin
  location_id      text not null unique,
  etiqueta         text not null,                 -- solo se leen contactos con esta tag (Legal: producto Lawang)
  secreto_id       uuid,                          -- vault.secrets.id del token
  activo           boolean not null default false,
  adenda_firmada_en date,
  creado_en        timestamptz not null default now(),
  creado_por       uuid,
  ultima_sync      timestamptz,
  ultimo_resultado jsonb,
  constraint traza_activo_exige_adenda check (not activo or adenda_firmada_en is not null)
);

create table if not exists public.traza_coincidencias (
  id              bigserial primary key,
  huella          text not null,                  -- HMAC hex, agrupa las filas de una misma persona
  tipo            text not null check (tipo in ('tel','email')),
  origen          text not null check (origen in ('lawang','ghl')),
  cuenta_id       uuid references public.traza_cuentas(id) on delete cascade,
  ref_id          text not null,                  -- leads.id o id de contacto GHL
  fuente          text,                           -- source / atribución
  alta            timestamptz,                    -- cuándo entró por ESE funnel
  sincronizado_en timestamptz not null default now(),
  constraint traza_origen_cuenta check ((origen = 'ghl') = (cuenta_id is not null))
);
create index if not exists traza_coinc_huella on public.traza_coincidencias(huella);

alter table public.traza_cuentas enable row level security;
alter table public.traza_coincidencias enable row level security;
-- Sin policies y sin grants: todo pasa por las funciones de abajo.
revoke all on public.traza_cuentas, public.traza_coincidencias from public, anon, authenticated;
revoke all on sequence public.traza_coincidencias_id_seq from public, anon, authenticated;

-- ── secreto del cron (mismo patrón que libera-reservas-vencidas) ──────────────
do $$ begin
  if not exists (select 1 from vault.secrets where name = 'cron_trazabilidad') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'cron_trazabilidad');
  end if;
end $$;

create or replace function public.cron_trazabilidad_secret()
returns text language sql security definer set search_path to '' as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'cron_trazabilidad';
$$;
revoke execute on function public.cron_trazabilidad_secret() from public, anon, authenticated;
grant execute on function public.cron_trazabilidad_secret() to service_role;

-- ── solo service_role (la Edge) ───────────────────────────────────────────────
create or replace function public.traza_cuenta_alta(
  p_nombre text, p_location_id text, p_etiqueta text, p_token text, p_creado_por uuid)
returns uuid language plpgsql security definer set search_path to '' as $$
declare v_id uuid := gen_random_uuid(); v_sec uuid;
begin
  if coalesce(trim(p_nombre),'') = '' or coalesce(trim(p_location_id),'') = ''
     or coalesce(trim(p_etiqueta),'') = '' or coalesce(p_token,'') !~ '^pit-' then
    raise exception 'datos incompletos';
  end if;
  v_sec := vault.create_secret(p_token, 'ghl_traza_' || v_id::text, 'Token GHL (solo lectura) de trazabilidad');
  insert into public.traza_cuentas(id, nombre, location_id, etiqueta, secreto_id, creado_por)
  values (v_id, trim(p_nombre), trim(p_location_id), trim(p_etiqueta), v_sec, p_creado_por);
  return v_id;
end $$;

create or replace function public.traza_cuenta_token_cambiar(p_id uuid, p_token text)
returns void language plpgsql security definer set search_path to '' as $$
declare v_sec uuid;
begin
  if coalesce(p_token,'') !~ '^pit-' then raise exception 'token no válido'; end if;
  select secreto_id into v_sec from public.traza_cuentas where id = p_id;
  if not found then raise exception 'cuenta no existe'; end if;
  perform vault.update_secret(v_sec, p_token);
end $$;

create or replace function public.traza_cuentas_para_sync(p_solo uuid default null)
returns table(id uuid, nombre text, location_id text, etiqueta text, token text)
language sql security definer set search_path to '' as $$
  select c.id, c.nombre, c.location_id, c.etiqueta, s.decrypted_secret
    from public.traza_cuentas c
    join vault.decrypted_secrets s on s.id = c.secreto_id
   where (p_solo is null and c.activo) or c.id = p_solo;
$$;

-- Sustituye TODAS las coincidencias de una pasada completa, en una transacción.
create or replace function public.traza_guardar(p_filas jsonb, p_resultados jsonb)
returns integer language plpgsql security definer set search_path to '' as $$
declare n integer := null;
begin
  -- p_filas null = la pasada falló en alguna cuenta: se anota el resultado y se CONSERVA
  -- lo de la pasada anterior (vaciar por un 429 haría desaparecer coincidencias reales).
  if p_filas is not null then
  delete from public.traza_coincidencias where true;
  insert into public.traza_coincidencias(huella, tipo, origen, cuenta_id, ref_id, fuente, alta)
  select f->>'huella', f->>'tipo', f->>'origen', nullif(f->>'cuenta_id','')::uuid,
         f->>'ref_id', f->>'fuente', nullif(f->>'alta','')::timestamptz
    from jsonb_array_elements(p_filas) f;
  get diagnostics n = row_count;
  end if;
  update public.traza_cuentas c set ultima_sync = now(), ultimo_resultado = r.value
    from jsonb_each(coalesce(p_resultados,'{}'::jsonb)) r
   where c.id::text = r.key;
  return n;
end $$;

revoke execute on function public.traza_cuenta_alta(text,text,text,text,uuid),
                           public.traza_cuenta_token_cambiar(uuid,text),
                           public.traza_cuentas_para_sync(uuid),
                           public.traza_guardar(jsonb,jsonb)
  from public, anon, authenticated;
grant execute on function public.traza_cuenta_alta(text,text,text,text,uuid),
                          public.traza_cuenta_token_cambiar(uuid,text),
                          public.traza_cuentas_para_sync(uuid),
                          public.traza_guardar(jsonb,jsonb)
  to service_role;

-- ── super_admin desde el navegador ────────────────────────────────────────────
create or replace function public.traza_cuentas_listar()
returns table(id uuid, nombre text, location_id text, etiqueta text, activo boolean,
              adenda_firmada_en date, ultima_sync timestamptz, ultimo_resultado jsonb)
language plpgsql stable security definer set search_path to '' as $$
begin
  if not public.es_super_admin() then raise exception 'sin permiso'; end if;
  return query select c.id, c.nombre, c.location_id, c.etiqueta, c.activo,
                      c.adenda_firmada_en, c.ultima_sync, c.ultimo_resultado
                 from public.traza_cuentas c order by c.creado_en;
end $$;

create or replace function public.traza_cuenta_estado(p_id uuid, p_activo boolean, p_adenda date)
returns void language plpgsql security definer set search_path to '' as $$
begin
  if not public.es_super_admin() then raise exception 'sin permiso'; end if;
  if p_activo and p_adenda is null then
    raise exception 'Sin fecha de adenda firmada no se puede activar la cuenta';
  end if;
  update public.traza_cuentas set activo = p_activo, adenda_firmada_en = p_adenda where id = p_id;
  if not found then raise exception 'cuenta no existe'; end if;
  -- Al desactivar, sus coincidencias dejan de tener base: fuera.
  if not p_activo then delete from public.traza_coincidencias where cuenta_id = p_id; end if;
end $$;

create or replace function public.traza_cuenta_borrar(p_id uuid)
returns void language plpgsql security definer set search_path to '' as $$
declare v_sec uuid;
begin
  if not public.es_super_admin() then raise exception 'sin permiso'; end if;
  select secreto_id into v_sec from public.traza_cuentas where id = p_id;
  if not found then raise exception 'cuenta no existe'; end if;
  delete from public.traza_cuentas where id = p_id;          -- cascada a coincidencias
  delete from vault.secrets where id = v_sec;
end $$;

-- Una fila por persona (huella) que aparece en 2+ funnels distintos.
create or replace function public.traza_coincidencias_listar()
returns table(huella text, tipos text[], n_funnels integer, primera_alta timestamptz, apariciones jsonb)
language plpgsql stable security definer set search_path to '' as $$
begin
  if not public.es_super_admin() then raise exception 'sin permiso'; end if;
  return query
  with ap as (
    select distinct on (t.huella, t.origen, t.cuenta_id, t.ref_id)
           t.huella, t.tipo, t.origen, t.cuenta_id, t.ref_id, t.fuente, t.alta,
           coalesce(c.nombre, 'Lawang') as funnel,
           l.name as lead_nombre, l.project as lead_proyecto
      from public.traza_coincidencias t
      left join public.traza_cuentas c on c.id = t.cuenta_id
      left join public.leads l on t.origen = 'lawang' and l.id::text = t.ref_id
     order by t.huella, t.origen, t.cuenta_id, t.ref_id, t.alta
  )
  select ap.huella,
         array_agg(distinct ap.tipo),
         count(distinct coalesce(ap.cuenta_id::text, 'lawang'))::int,
         min(ap.alta),
         jsonb_agg(jsonb_build_object(
           'funnel', ap.funnel, 'origen', ap.origen, 'ref_id', ap.ref_id,
           'fuente', ap.fuente, 'alta', ap.alta,
           'nombre', ap.lead_nombre, 'proyecto', ap.lead_proyecto) order by ap.alta nulls last)
    from ap
   group by ap.huella
  having count(distinct coalesce(ap.cuenta_id::text, 'lawang')) >= 2
   order by min(ap.alta) desc nulls last;
end $$;

revoke execute on function public.traza_cuentas_listar(), public.traza_cuenta_estado(uuid,boolean,date),
                           public.traza_cuenta_borrar(uuid), public.traza_coincidencias_listar()
  from public, anon;
grant execute on function public.traza_cuentas_listar(), public.traza_cuenta_estado(uuid,boolean,date),
                          public.traza_cuenta_borrar(uuid), public.traza_coincidencias_listar()
  to authenticated;

-- ── cron: cada 6 h. Si no hay cuentas activas, la Edge no hace nada. ──────────
select cron.unschedule('trazabilidad-ghl') where exists (select 1 from cron.job where jobname = 'trazabilidad-ghl');
select cron.schedule('trazabilidad-ghl', '23 */6 * * *', $cron$
  select net.http_post(
    url     := 'https://vtulllundrfennhjddhc.supabase.co/functions/v1/trazabilidad-ghl',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'X-Cron-Secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_trazabilidad')),
    body    := '{"accion":"sincronizar"}'::jsonb,
    timeout_milliseconds := 120000);
$cron$);
