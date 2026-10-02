-- Corrección de 20261002053848 pedida por el revisor-codigo (2-oct-2026), antes de encender el reintento.
-- 1) El gemelo (mismo email y canal a ±3 min) se buscaba solo entre filas SIN huella. Un alta que entra sin p_creado
--    (el lead.php de 6 argumentos que sigue en producción hasta que salga el nuevo, o cualquier llamada futura sin
--    fecha) guarda una huella hecha con el now() de la base; el CSV lleva el date('c') de PHP, que puede caer en otro
--    segundo. El reintento de reconcilia.php no casaba ni por huella ni como gemelo (la fila ya tenía huella) y
--    entraba DUPLICADO. Medido en rojo contra la función anterior: alta sin fecha + reintento con 1 s menos → n=2.
--    Ahora el gemelo vale tenga o no huella; si ya la tiene no se pisa, solo se responde «ya está».
-- 2) El comentario de leads_borrados decía «sin PII»: una huella sha256 de segundo|email|canal se puede revertir
--    probando candidatos, es un seudónimo. Y borrar del CRM no borra la fila del CSV del servidor.
create or replace function public.lead_publico_alta(p_email text, p_name text DEFAULT NULL::text, p_whatsapp text DEFAULT NULL::text,
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
  v_gemelo_ref text;
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

  -- El mismo alta ya está (mismo email y canal a ±3 min), tenga o no huella: «hecho». Si no la tenía, se le estampa.
  select l.id, l.ref into v_gemelo, v_gemelo_ref
    from public.leads l
   where lower(l.email) = v_email and l.source = v_source
     and l.created_at between v_creado - interval '3 minutes' and v_creado + interval '3 minutes'
   order by abs(extract(epoch from l.created_at - v_creado))
   limit 1
   for update;
  if v_gemelo is not null then
    if v_gemelo_ref is null then
      update public.leads set ref = v_ref where id = v_gemelo;
    end if;
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

-- create or replace conserva los permisos, pero se reafirman y se comprueban igual que en 20261002053848.
revoke all on function public.lead_publico_alta(text, text, text, text, text, text, timestamptz)
  from public, anon, authenticated, service_role;
grant execute on function public.lead_publico_alta(text, text, text, text, text, text, timestamptz) to anon;

comment on table public.leads_borrados is
  'Huellas (leads.ref) de leads borrados del CRM, para que el reintento de Sumba Hills no los resucite. Una huella es un seudónimo (sha256 de segundo|email|canal, reversible probando candidatos), no un dato anónimo. Borrar del CRM no borra la fila de private/leads.csv del servidor de Sumba Hills.';

do $$
declare v_acl text;
begin
  if (select count(*) from pg_proc where proname = 'lead_publico_alta' and pronamespace = 'public'::regnamespace) <> 1 then
    raise exception 'lead_publico_alta: tiene que quedar UNA firma';
  end if;
  select proacl::text into v_acl from pg_proc where proname = 'lead_publico_alta' and pronamespace = 'public'::regnamespace;
  if v_acl ~ '(^|[{,])=X/' or v_acl ~ 'authenticated=' or v_acl ~ 'service_role=' then
    raise exception 'lead_publico_alta: permisos de más: %', v_acl;
  end if;
  if not has_function_privilege('anon', 'public.lead_publico_alta(text, text, text, text, text, text, timestamptz)', 'EXECUTE') then
    raise exception 'lead_publico_alta: el formulario público perdería su puerta';
  end if;
end $$;
