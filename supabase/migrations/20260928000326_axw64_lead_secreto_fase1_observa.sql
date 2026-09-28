-- AXW-64 fase 1 (28-sep-2026, owner: opción B «secreto entre formulario y base»). MODO OBSERVA: no cambia qué
-- altas se aceptan. lead_publico_alta mira la cabecera `x-lead-secreto` que manda SumbaHills/api/lead.php y deja
-- en el log de Postgres si llegó un secreto válido o no (RAISE LOG: va al log del servidor, nunca al cliente, y
-- nunca lleva el valor). La fase 2 (exigirlo) se aplica cuando el log muestre un alta real con «secreto valido»:
-- SQL preparado en contracts/sql/axw64_fase2_exige_secreto.sql.
--
-- En la base NO vive el secreto: solo su SHA-256, en Vault. El valor está únicamente en
-- public_html/sumbahills/private/lead-secreto.php del hosting (fuera de git).
select vault.create_secret('7304783f9bd5e1ef2bd3552e902b17b1b53a4dc8b2ab66b79fe878ad78d628c6',
                           'lead_publico_alta_secreto_sha256',
                           'SHA-256 del secreto que manda SumbaHills/api/lead.php en x-lead-secreto (AXW-64)')
 where not exists (select 1 from vault.secrets where name = 'lead_publico_alta_secreto_sha256');

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
  -- AXW-64 fase 1: solo se observa (nunca el valor).
  if coalesce(v_ok, false) then
    raise log 'lead_publico_alta: secreto valido';
  else
    raise log 'lead_publico_alta: sin secreto valido (modo observa, AXW-64)';
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
end $$;
