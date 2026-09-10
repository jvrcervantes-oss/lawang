-- destructivo-ok: el UPDATE que ve el guardrail es el DO UPDATE de un ON CONFLICT(lead_id)
-- -- por clave primaria, afecta como mucho a 1 fila (EST-32: el guardrail no distingue
-- ON CONFLICT DO UPDATE de un update masivo, hallazgo ya registrado en pendientes).

-- CRM de leads — closers reales, 10-sep-2026.
-- Revision previa: Bots + Seguridad + Legal (hallazgos recogidos en contexto/pendientes.md
-- y en CEO/revisiones/estado.json). Permiso NUEVO 'closers': quien hace la llamada de
-- venta por Google Meet no es lo mismo que quien movio la tarjeta en el pipeline
-- (lead_estado.responsable) -- son roles distintos y pueden ser personas distintas.

-- 1. QUIEN ES EL CLOSER DE UN LEAD --------------------------------------------------
-- Un lead tiene UN closer a la vez (unique en lead_id): la llamada de venta la lleva
-- una persona, no un turno rotativo hoy. Reasignar es UPDATE, no una fila nueva --
-- si algun dia hace falta historial de reasignaciones, se anade lead_closer_log
-- igual que lead_estado tiene su lead_estado_log, no se mezcla aqui.
create table if not exists public.lead_closer (
  lead_id      uuid primary key references public.leads(id) on delete cascade,
  closer_email text not null,
  asignado_por text not null,
  asignado_en  timestamptz not null default now()
);
alter table public.lead_closer enable row level security;

create policy "closers ven su propia asignacion, admin todas" on public.lead_closer
  for select to authenticated using (
    public.es_admin() or closer_email = (select auth.email())
  );
-- Nadie escribe a mano: solo la funcion SECURITY DEFINER de abajo.

-- 2. INSIGHTS DE FATHOM.AI, SIN CONECTAR TODAVIA ------------------------------------
-- El owner no tiene cuenta de Fathom.ai (10-sep-2026): esta tabla queda vacia hasta
-- que exista y se conecte el webhook receptor (Edge Function aparte, fathom-webhook).
-- Dato mas sensible que toca el CRM: voz de un lead real transcrita, con presupuesto y
-- objeciones. RLS por closer asignado, NUNCA `authenticated` a secas (hallazgo
-- Seguridad #1 de la revision previa).
create table if not exists public.fathom_call_insights (
  id                  uuid primary key default gen_random_uuid(),
  lead_id             uuid not null references public.leads(id) on delete cascade,
  closer_email        text,
  resumen             text,
  objeciones          jsonb not null default '[]'::jsonb,
  proximos_pasos      jsonb not null default '[]'::jsonb,
  recording_url       text,
  fathom_recording_id text unique,
  procesado_en        timestamptz not null default now()
);
create index if not exists fathom_call_insights_lead_idx on public.fathom_call_insights(lead_id);
alter table public.fathom_call_insights enable row level security;

create policy "closer asignado o admin lee los insights de su lead" on public.fathom_call_insights
  for select to authenticated using (
    public.es_admin()
    or exists (
      select 1 from public.lead_closer lc
       where lc.lead_id = fathom_call_insights.lead_id
         and lc.closer_email = (select auth.email())
    )
  );
-- Sin policy de insert/update/delete para authenticated: solo el service_role del
-- webhook receptor escribe aqui (bypassa RLS por diseno), igual que R13 escribe en
-- `leads` sin policy de escritura para nadie mas.

-- 3. FUNCIONES ------------------------------------------------------------------------
-- Asignar closer: revalida 'closers' (no 'leads' -- ver ficha de la herramienta) y
-- sella quien asigna. Un lead se reasigna con la misma llamada (upsert por PK).
create or replace function public.crm_lead_asignar_closer(p_lead uuid, p_closer_email text)
returns table (lead_id uuid, closer_email text, asignado_por text, asignado_en timestamptz)
language plpgsql volatile security definer set search_path to ''
as $$
declare
  v_quien text := coalesce((select auth.email()), '');
  v_closer text := btrim(coalesce(p_closer_email, ''));
begin
  if not public.puede('closers') then
    raise exception 'Sin permiso para asignar closers' using errcode = 'PT403';
  end if;
  if v_quien = '' then
    raise exception 'Sesion sin identidad' using errcode = 'PT403';
  end if;
  if v_closer = '' then
    raise exception 'closer_email vacio' using errcode = 'PT400';
  end if;
  if not exists (select 1 from public.usuarios u where u.email = v_closer and u.activo) then
    raise exception 'Ese email no es un usuario activo de la intranet' using errcode = 'PT404';
  end if;
  if not exists (select 1 from public.leads l where l.id = p_lead) then
    raise exception 'Ese lead no existe' using errcode = 'PT404';
  end if;

  insert into public.lead_closer (lead_id, closer_email, asignado_por, asignado_en)
       values (p_lead, v_closer, v_quien, now())
  on conflict (lead_id) do update
    set closer_email = excluded.closer_email,
        asignado_por = excluded.asignado_por,
        asignado_en  = excluded.asignado_en;

  return query select lc.lead_id, lc.closer_email, lc.asignado_por, lc.asignado_en
    from public.lead_closer lc where lc.lead_id = p_lead;
end;
$$;

-- Leer los insights de Fathom de UN lead. Nunca en listado general -- solo por id,
-- y solo si quien llama es su closer o admin (la RLS de arriba ya lo filtraria, pero
-- se revalida aqui tambien porque esta funcion es SECURITY DEFINER y bypassa RLS).
create or replace function public.crm_lead_fathom(p_lead uuid)
returns table (
  id uuid, resumen text, objeciones jsonb, proximos_pasos jsonb,
  recording_url text, procesado_en timestamptz
)
language plpgsql stable security definer set search_path to ''
as $$
declare
  v_quien text := coalesce((select auth.email()), '');
  v_puede boolean;
begin
  v_puede := public.es_admin() or exists (
    select 1 from public.lead_closer lc
     where lc.lead_id = p_lead and lc.closer_email = v_quien
  );
  if not v_puede then
    raise exception 'Sin permiso para ver las llamadas de este lead' using errcode = 'PT403';
  end if;
  return query
    select f.id, f.resumen, f.objeciones, f.proximos_pasos, f.recording_url, f.procesado_en
      from public.fathom_call_insights f
     where f.lead_id = p_lead
     order by f.procesado_en desc;
end;
$$;

revoke execute on function public.crm_lead_asignar_closer(uuid, text) from public, anon;
revoke execute on function public.crm_lead_fathom(uuid) from public, anon;
grant execute on function public.crm_lead_asignar_closer(uuid, text) to authenticated;
grant execute on function public.crm_lead_fathom(uuid) to authenticated;;
