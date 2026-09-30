-- INVERSA de la limpieza de superficie del 30-sep-2026 (migraciones 20260930100100..100400). NO es una migracion:
-- se aplica a mano solo si hay que deshacer. Las tablas estaban a 0 filas, asi que recrearlas es fiel.
-- (crm_lead_mover y crm_lead_accion_poner: sus versiones ANTERIORES estan en su ultima migracion previa en supabase/migrations
--  y en git; abajo va lo que se borro.)

-- Tablas
create table public.payments (
  id uuid not null default gen_random_uuid() primary key,
  reservation_id uuid not null references public.reservations(id) on delete cascade,
  amount numeric(12,2) not null, currency text not null default 'EUR', due_date date, paid_at timestamptz,
  status text not null default 'pending' check (status = any (array['pending','paid','overdue','cancelled'])),
  method text, reference text, created_at timestamptz not null default now());
alter table public.payments enable row level security;

create table public.investor_deck_verificaciones (
  id uuid not null default gen_random_uuid() primary key, email text not null, codigo_hash text not null,
  intentos integer not null default 0, usado boolean not null default false,
  expira_at timestamptz not null, creado_at timestamptz not null default now());
create index investor_deck_verif_email_idx on public.investor_deck_verificaciones using btree (lower(email), creado_at desc);
alter table public.investor_deck_verificaciones enable row level security;

create table public.lead_closer (
  lead_id uuid not null primary key references public.leads(id) on delete cascade,
  closer_email text not null, asignado_por text not null, asignado_en timestamptz not null default now());
alter table public.lead_closer enable row level security;

create table public.fathom_call_insights (
  id uuid not null default gen_random_uuid() primary key,
  lead_id uuid not null references public.leads(id) on delete cascade,
  closer_email text, resumen text, objeciones jsonb not null default '[]'::jsonb,
  proximos_pasos jsonb not null default '[]'::jsonb, recording_url text,
  fathom_recording_id text unique, procesado_en timestamptz not null default now());
create index fathom_call_insights_lead_idx on public.fathom_call_insights using btree (lead_id);
alter table public.fathom_call_insights enable row level security;

create table public.contrato_documentos (
  id uuid not null default gen_random_uuid() primary key,
  contrato_id uuid not null references public.contratos(id) on delete cascade,
  doc_type text not null default 'signed_contract', storage_path text not null,
  matched_by text not null check (matched_by = any (array['numero_exacto','nombre_exacto','nombre_confirmado_usuario'])),
  uploaded_at timestamptz not null default now());
alter table public.contrato_documentos enable row level security;

-- Funciones borradas (definiciones tal cual estaban; con sus permisos de entonces: execute a authenticated)
CREATE OR REPLACE FUNCTION public._sc_visible(p_tabla text, p_id uuid)
 RETURNS boolean LANGUAGE sql STABLE SET search_path TO ''
AS $function$
  select case p_tabla
    when 'clients'   then exists (select 1 from public.clients   where id = p_id)
    when 'facturas'  then exists (select 1 from public.facturas  where id = p_id)
    when 'contratos' then exists (select 1 from public.contratos where id = p_id)
    else false end
$function$;

CREATE OR REPLACE FUNCTION public.crm_lead_fathom(p_lead uuid)
 RETURNS TABLE(id uuid, resumen text, objeciones jsonb, proximos_pasos jsonb, recording_url text, procesado_en timestamp with time zone)
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.modelo_ficha_guarda(p_id uuid, p_cambios jsonb, p_precios jsonb, p_techos jsonb, p_extras jsonb)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
declare r jsonb := '{}'::jsonb;
begin
  if not public.es_admin() then raise exception 'Los modelos los edita administración' using errcode = '42501'; end if;
  if p_cambios is not null and p_cambios <> '{}'::jsonb then perform public.modelo_guarda(p_id, p_cambios); end if;
  if p_precios is not null and p_precios <> '{}'::jsonb then r := public.modelo_precios_guarda(p_id, p_precios); end if;
  if p_techos is not null and jsonb_typeof(p_techos) = 'array' and jsonb_array_length(p_techos) > 0 then perform public.modelo_techos_guarda(p_id, p_techos); end if;
  if p_extras is not null and jsonb_typeof(p_extras) = 'array' and jsonb_array_length(p_extras) > 0 then perform public.modelo_extras_guarda(p_id, p_extras); end if;
  return r || jsonb_build_object('ok', true, 'contratos_no_firmados_min', public._modelo_contratos_no_firmados(p_id));
end $function$;

-- OJO: modelo_precio_construccion era la FUGA. Solo restaurarla si se le pone un gate (es_admin() o puede('modelos')).
CREATE OR REPLACE FUNCTION public.modelo_precio_construccion(p_modelo_id uuid, p_proyecto_id uuid DEFAULT NULL::uuid)
 RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  select coalesce(
    (select mv.precio_construccion from public.modelos_villa mv
      where mv.modelo_id = p_modelo_id and mv.proyecto_id = p_proyecto_id
        and mv.precio_construccion is not null),
    (select m.precio_construccion from public.modelos m where m.id = p_modelo_id)
  )
$function$;

-- Permisos revocados a authenticated/anon/public sin borrar la funcion:
grant execute on function public.borrar_unidad(uuid) to authenticated;
grant execute on function public.tipo_vivienda_alta(text, text) to authenticated;
