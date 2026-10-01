-- AXW-64 FASE 2 — APLICADA el 28-sep-2026 03:23 UTC como supabase/migrations/20260928032303_axw64_lead_secreto_fase2_exige.sql
-- (tras el alta real «PRUEBA ESTUDIO» con «secreto valido» en el log). Lo de abajo es el relato original de cuando estaba
-- preparada; la migración aplicada es la del directorio de migraciones. Texto original:
-- AXW-64 FASE 2 — PREPARADO, NO APLICADO (28-sep-2026). NO es una migración todavía: se aplica con
-- apply_migration (nombre axw64_lead_secreto_fase2_exige) y entonces se copia a supabase/migrations/ con la
-- versión que devuelva, SOLO cuando:
--   1. SumbaHills/api/lead.php con la cabecera x-lead-secreto está publicado (push + webhook), y
--   2. public_html/sumbahills/private/lead-secreto.php está subido al hosting, y
--   3. un alta REAL del formulario deja en el log de Postgres «lead_publico_alta: secreto valido»
--      (MCP get_logs service=postgres, o query_logs buscando ese texto).
-- Aplicarla antes deja el CRM sin leads de Sumba Hills (siguen llegando al CSV del servidor y al correo).
-- Prueba sin rastro después: contracts/sql/prueba_lead_publico_alta.sql fijando request.headers con un secreto
-- incorrecto -> 42501.

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

