-- Alta pública de leads por RPC (27-sep-2026, cierre global de escrituras). Hasta hoy `anon` podía hacer INSERT libre
-- en `leads` (policy `with check (true)`) con CUALQUIER columna: también meta_lead_id, campaign_id, adset_id, ad_id y
-- form_id. Cualquiera con la clave pública podía fabricar leads atribuidos a una campaña, y el vigilante de Meta Ads
-- decide presupuestos con esas cifras. El único llamador legítimo es SumbaHills/api/lead.php (formulario del folleto).
-- Esta RPC acepta SOLO los campos del formulario, valida y limita el ritmo; los de Meta los escribe solo el servidor.
-- Tras publicar el lead.php nuevo, 20260927172500 quita el INSERT directo de anon.
create or replace function public.lead_publico_alta(p_email text, p_name text default null, p_whatsapp text default null,
                                                    p_source text default null, p_project text default null,
                                                    p_ip text default null)
returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_tal text := btrim(coalesce(p_email, ''));   -- se guarda como lo escribió (lead.php hacía lo mismo)
begin
  if v_email !~ '^[^@[:space:]]{1,64}@[^@[:space:]]+\.[^@[:space:]]{2,}$' or length(v_email) > 200 then
    raise exception 'Email no válido' using errcode = '22023';
  end if;
  -- ritmo: el mismo email, como mucho 3 altas por hora; todo el formulario, 300 por hora (un bot llenaría el CRM)
  if (select count(*) from public.leads l where lower(l.email) = v_email and l.created_at > now() - interval '1 hour') >= 3
     or (select count(*) from public.leads l where l.meta_lead_id is null and l.created_at > now() - interval '1 hour') >= 300 then
    raise exception 'Demasiadas altas seguidas: prueba más tarde' using errcode = '54000';
  end if;
  insert into public.leads (email, name, whatsapp, source, project, ip)
  values (v_tal,
          nullif(left(btrim(regexp_replace(coalesce(p_name, ''), '[[:cntrl:]]', ' ', 'g')), 200), ''),
          nullif(left(regexp_replace(coalesce(p_whatsapp, ''), '[^0-9+]', '', 'g'), 40), ''),
          nullif(left(btrim(coalesce(p_source, '')), 200), ''),
          nullif(left(btrim(coalesce(p_project, '')), 200), ''),
          nullif(left(btrim(coalesce(p_ip, '')), 64), ''));
  return true;
end $$;
revoke all on function public.lead_publico_alta(text, text, text, text, text, text) from public, authenticated;
grant execute on function public.lead_publico_alta(text, text, text, text, text, text) to anon, service_role;
