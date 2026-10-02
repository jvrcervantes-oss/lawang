-- destructivo-ok: drop de la firma de 6 argumentos de lead_publico_alta (se sustituye por la de 7 en la misma transacción) y drop del trigger de tumbas antes de recrearlo; no borra filas.
-- Reintento de la réplica de leads de Sumba Hills (2-oct-2026, owner: «reintento automático»).
-- Por qué: SumbaHills/api/lead.php guarda el lead en su CSV y lo copia al CRM UNA vez. Supabase dio 522 del
--   30-sep 22:40 al 1-oct ~03:10 UTC y un lead del QR (1-oct 01:17 UTC) se quedó solo en el CSV; el fallo fue a un
--   error_log que nadie lee y lo descubrió el owner. Ahora api/reconcilia.php (cron de Hostinger) vuelve a mandar lo
--   que falte, y la base tiene que aceptar un reintento SIN duplicar y con la fecha ORIGINAL.
-- Revisión previa #200 (seguridad, datos, deploy) plegada:
--   · `ref` lo calcula la base (fecha del alta + email + canal ya normalizado); no se acepta de quien llama.
--   · UNIQUE normal en `ref` (un índice parcial no vale como destino de ON CONFLICT: 42P10). Los NULL no chocan.
--   · `recibido_en` = hora REAL de llegada, que nadie puede elegir: el tope anti-ráfaga cuenta por ella. Si contara por
--     `created_at`, mandar `p_creado` en el pasado saltaría el tope.
--   · `p_creado` fuera de [now()-45 d, now()+10 min] se RECHAZA (LP001); cambiarlo por now() haría pasar un lead viejo
--     por nuevo y el cruce de ±3 min no casaría con nada → duplicado.
--   · Filas de antes de esta migración (sin ref): el reintento las reconoce por email+canal a ±3 min y les estampa el
--     ref en vez de insertar.
--   · Lo que se borra del CRM a propósito (pruebas, spam, petición UU PDP) deja su ref en `leads_borrados` y no resucita.
--   · Una sola firma: drop de la de 6 argumentos en la misma transacción (con las dos vivas PostgREST no elige: PGRST203).
--     `p_creado` es DEFAULT NULL, así que el lead.php de hoy (6 argumentos) sigue entrando mientras sale el nuevo.
--   · Solo `anon` la ejecuta (lead.php y reconcilia.php usan la clave publicable); service_role no tiene llamador.
-- Códigos que lee reconcilia.php: 42501 secreto (configuración) · 22023 email · LP001 fecha fuera de rango ·
--   LP002 cuarta alta del mismo email en la hora de su alta (definitivos) · 54000 ráfaga real (pasajero).

-- 1) Columnas nuevas de leads
alter table public.leads add column if not exists ref text;
alter table public.leads add constraint leads_ref_key unique (ref);
alter table public.leads add column if not exists recibido_en timestamptz;
update public.leads set recibido_en = created_at where recibido_en is null;
alter table public.leads alter column recibido_en set default now();
alter table public.leads alter column recibido_en set not null;
comment on column public.leads.ref is
  'Huella del alta (sha256 de segundo del alta|email|canal) que calcula lead_publico_alta. Hace idempotente el reintento de SumbaHills/api/reconcilia.php. NULL en leads de Meta y en los de antes del 2-oct-2026.';
comment on column public.leads.recibido_en is
  'Cuándo llegó de verdad a la base (no lo elige quien llama). created_at es la hora del alta, que en un reintento es anterior.';

-- 2) Tumbas: un lead borrado a propósito no vuelve por el reintento. Solo la huella, sin datos personales.
create table if not exists public.leads_borrados (
  ref text primary key,
  borrado_en timestamptz not null default now()
);
comment on table public.leads_borrados is
  'Huellas (leads.ref) de leads borrados del CRM, para que el reintento de Sumba Hills no los resucite. Sin PII.';
alter table public.leads_borrados enable row level security;
revoke all on public.leads_borrados from public, anon, authenticated;

create or replace function public.leads_tumba_al_borrar()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if old.ref is not null then
    insert into public.leads_borrados (ref) values (old.ref) on conflict (ref) do nothing;
  end if;
  return old;
end $function$;
revoke all on function public.leads_tumba_al_borrar() from public, anon, authenticated, service_role;

drop trigger if exists trg_leads_tumba_al_borrar on public.leads;
create trigger trg_leads_tumba_al_borrar after delete on public.leads
  for each row execute function public.leads_tumba_al_borrar();

-- 3) La RPC, con una sola firma
drop function if exists public.lead_publico_alta(text, text, text, text, text, text);

create function public.lead_publico_alta(p_email text, p_name text DEFAULT NULL::text, p_whatsapp text DEFAULT NULL::text,
                                         p_source text DEFAULT NULL::text, p_project text DEFAULT NULL::text,
                                         p_ip text DEFAULT NULL::text, p_creado timestamptz DEFAULT NULL)
 returns boolean
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_tal text := btrim(coalesce(p_email, ''));
  v_source text := case when btrim(coalesce(p_source, '')) in ('sumba-hills-qr', 'sumbahills-web', 'sumbahills-brochure')
                        then btrim(p_source) else 'sumbahills-desconocido' end;
  v_cab text := nullif(nullif(current_setting('request.headers', true), ''), '{}')::json ->> 'x-lead-secreto';
  v_ok boolean := v_cab is not null and encode(sha256(convert_to(v_cab, 'UTF8')), 'hex') =
                  (select s.decrypted_secret from vault.decrypted_secrets s where s.name = 'lead_publico_alta_secreto_sha256');
  v_creado timestamptz := date_trunc('second', coalesce(p_creado, now()));
  v_ref text;
  v_gemelo uuid;
begin
  -- AXW-64 fase 2: sin el secreto del formulario no hay alta. El error no dice qué faltó ni lleva el valor.
  if not coalesce(v_ok, false) then
    raise log 'lead_publico_alta: rechazada, sin secreto valido (AXW-64)';
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' or length(v_email) > 254 then
    raise exception 'Email no válido' using errcode = '22023';
  end if;
  if v_creado > now() + interval '10 minutes' or v_creado < now() - interval '45 days' then
    raise exception 'Fecha de alta fuera de rango' using errcode = 'LP001';
  end if;

  v_ref := encode(sha256(convert_to(extract(epoch from v_creado)::bigint::text || '|' || v_email || '|' || v_source, 'UTF8')), 'hex');

  -- Ya está en el CRM, o se borró a propósito: «hecho», sin insertar.
  if exists (select 1 from public.leads l where l.ref = v_ref)
     or exists (select 1 from public.leads_borrados b where b.ref = v_ref) then
    return true;
  end if;

  -- Copia de antes del ref (o la que entró sin él): mismo email y canal a ±3 min → se le estampa la huella.
  select l.id into v_gemelo
    from public.leads l
   where l.ref is null and lower(l.email) = v_email and l.source = v_source
     and l.created_at between v_creado - interval '3 minutes' and v_creado + interval '3 minutes'
   order by abs(extract(epoch from l.created_at - v_creado))
   limit 1
   for update;
  if v_gemelo is not null then
    update public.leads set ref = v_ref where id = v_gemelo;
    return true;
  end if;

  -- Ráfaga real: cuenta por la hora de llegada, que nadie elige. Pasajero: dentro de una hora puede entrar.
  if (select count(*) from public.leads l where lower(l.email) = v_email and l.recibido_en > now() - interval '1 hour') >= 3 then
    raise exception 'Demasiadas altas seguidas: prueba más tarde' using errcode = '54000';
  end if;
  -- Cuarta alta del mismo email en la hora de SU alta: definitivo. Un escaneo que se rechazó en directo sigue
  -- rechazado cuando lo reintenta reconcilia.php.
  if (select count(*) from public.leads l where lower(l.email) = v_email
         and l.created_at between v_creado - interval '1 hour' and v_creado) >= 3 then
    raise exception 'Demasiadas altas del mismo email en esa hora' using errcode = 'LP002';
  end if;

  insert into public.leads (email, name, whatsapp, source, project, ip, created_at, ref)
  values (v_tal,
          nullif(left(btrim(regexp_replace(coalesce(p_name, ''), '[[:cntrl:]]', ' ', 'g')), 200), ''),
          nullif(left(regexp_replace(coalesce(p_whatsapp, ''), '[^0-9+]', '', 'g'), 40), ''),
          v_source,
          nullif(left(btrim(coalesce(p_project, '')), 200), ''),
          nullif(left(btrim(coalesce(p_ip, '')), 64), ''),
          v_creado,
          v_ref)
  on conflict (ref) do nothing;
  return true;
end $function$;

revoke all on function public.lead_publico_alta(text, text, text, text, text, text, timestamptz)
  from public, anon, authenticated, service_role;
grant execute on function public.lead_publico_alta(text, text, text, text, text, text, timestamptz) to anon;

-- 4) Comprobaciones: si algo no queda como debe, no se aplica nada.
do $$
declare v_acl text;
begin
  if exists (select 1 from pg_proc where proname = 'lead_publico_alta' and pronamespace = 'public'::regnamespace and pronargs <> 7)
     or (select count(*) from pg_proc where proname = 'lead_publico_alta' and pronamespace = 'public'::regnamespace) <> 1 then
    raise exception 'lead_publico_alta: tiene que quedar UNA firma (7 argumentos)';
  end if;
  select proacl::text into v_acl from pg_proc where proname = 'lead_publico_alta' and pronamespace = 'public'::regnamespace;
  if v_acl ~ '(^|[{,])=X/' or v_acl ~ 'authenticated=' or v_acl ~ 'service_role=' then
    raise exception 'lead_publico_alta: permisos de más: %', v_acl;
  end if;
  if not has_function_privilege('anon', 'public.lead_publico_alta(text, text, text, text, text, text, timestamptz)', 'EXECUTE') then
    raise exception 'lead_publico_alta: el formulario público perdería su puerta';
  end if;
  if not exists (select 1 from vault.secrets where name = 'lead_publico_alta_secreto_sha256') then
    raise exception 'AXW-64: falta el hash en Vault';
  end if;
  if has_table_privilege('anon', 'public.leads_borrados', 'SELECT') or has_table_privilege('authenticated', 'public.leads_borrados', 'SELECT')
     or has_table_privilege('anon', 'public.leads', 'INSERT') or has_table_privilege('authenticated', 'public.leads', 'INSERT') then
    raise exception 'leads/leads_borrados: anon o authenticated tienen permisos';
  end if;
end $$;
