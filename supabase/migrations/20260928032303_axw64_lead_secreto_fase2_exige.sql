-- AXW-64 FASE 2 (28-sep-2026): lead_publico_alta EXIGE el secreto x-lead-secreto que manda SumbaHills/api/lead.php.
-- Aplicada tras el alta real «PRUEBA ESTUDIO» (28-sep 03:21 UTC) que dejó «lead_publico_alta: secreto valido» en el
-- log de Postgres. Sin el secreto: 42501 «No autorizado» (no dice qué faltó ni lleva el valor). En la base solo vive
-- su SHA-256 (Vault, lead_publico_alta_secreto_sha256); el valor, solo en private/lead-secreto.php del hosting.
create or replace function public.lead_publico_alta(p_email text, p_name text DEFAULT NULL::text, p_whatsapp text DEFAULT NULL::text, p_source text DEFAULT NULL::text, p_project text DEFAULT NULL::text, p_ip text DEFAULT NULL::text)
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
begin
  -- AXW-64 fase 2: sin el secreto del formulario no hay alta. El error no dice qué faltó ni lleva el valor.
  if not coalesce(v_ok, false) then
    raise log 'lead_publico_alta: rechazada, sin secreto valido (AXW-64)';
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' or length(v_email) > 254 then
    raise exception 'Email no válido' using errcode = '22023';
  end if;
  if (select count(*) from public.leads l where lower(l.email) = v_email and l.created_at > now() - interval '1 hour') >= 3 then
    raise exception 'Demasiadas altas seguidas: prueba más tarde' using errcode = '54000';
  end if;
  insert into public.leads (email, name, whatsapp, source, project, ip)
  values (v_tal,
          nullif(left(btrim(regexp_replace(coalesce(p_name, ''), '[[:cntrl:]]', ' ', 'g')), 200), ''),
          nullif(left(regexp_replace(coalesce(p_whatsapp, ''), '[^0-9+]', '', 'g'), 40), ''),
          v_source,
          nullif(left(btrim(coalesce(p_project, '')), 200), ''),
          nullif(left(btrim(coalesce(p_ip, '')), 64), ''));
  return true;
end $function$;

do $$
begin
  if not has_function_privilege('anon', 'public.lead_publico_alta(text, text, text, text, text, text)', 'EXECUTE') then
    raise exception 'AXW-64: el formulario público perdería su puerta';
  end if;
  if has_function_privilege('authenticated', 'public.lead_publico_alta(text, text, text, text, text, text)', 'EXECUTE') then
    raise exception 'AXW-64: authenticated no debe ejecutarla';
  end if;
  if not exists (select 1 from vault.secrets where name = 'lead_publico_alta_secreto_sha256') then
    raise exception 'AXW-64: falta el hash en Vault';
  end if;
end $$;;
