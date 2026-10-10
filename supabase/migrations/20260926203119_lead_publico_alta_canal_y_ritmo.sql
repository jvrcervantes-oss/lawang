-- Reconstruida el 10-oct-2026 desde supabase_migrations.schema_migrations.statements (version y nombre exactos; ya APLICADA en produccion, no se vuelve a aplicar). Su cambio ya esta fundido en: 20260927172000_lead_publico_alta.sql
create or replace function public.lead_publico_alta(p_email text, p_name text default null, p_whatsapp text default null,
                                                    p_source text default null, p_project text default null,
                                                    p_ip text default null)
returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_tal text := btrim(coalesce(p_email, ''));
  v_source text := case when btrim(coalesce(p_source, '')) in ('sumba-hills-qr', 'sumbahills-web', 'sumbahills-brochure')
                        then btrim(p_source) else 'sumbahills-desconocido' end;
begin
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
end $$;
revoke all on function public.lead_publico_alta(text, text, text, text, text, text) from public, authenticated;
grant execute on function public.lead_publico_alta(text, text, text, text, text, text) to anon, service_role;;
