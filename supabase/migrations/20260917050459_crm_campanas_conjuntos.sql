-- CRM de leads — detalle por conjunto de anuncios (objetivo, targeting real, rendimiento).
-- Mismo motivo que axisworks_meta_targeting_historial: el ESTUDIO escribe, Lawang solo lee
-- por funcion. Esta es una tabla de ESTADO (una fila por adset, se REEMPLAZA entera en cada
-- vuelta del vigilante), no un historial append-only -- lo que la intranet necesita es "como
-- esta ahora", no "como ha ido cambiando" (eso ya lo cubre axisworks_meta_targeting_historial
-- para R8.1, y esta tabla no le pisa el hueco: dueños distintos, ver contexto/patrones_tecnicos.md
-- "El dato tiene un dueño"). `publico`/`geo` van ya en texto legible (no el JSON crudo de Meta):
-- lo calcula el vigilante con las mismas funciones (_publico/_geo_nombres) que ya usa el panel
-- de AxisWorks, para no inventar una segunda lectura del mismo targeting.
create table if not exists public.axisworks_meta_campanas_conjuntos (
  adset_id       text primary key,
  campaign_id    text not null,
  cliente        text not null,
  campana_nombre text,
  adset_nombre   text,
  objetivo       text,             -- objective de la CAMPAÑA (OUTCOME_LEADS...), no del adset
  status         text,             -- lo que el operador puso (ACTIVE/PAUSED)
  effective_status text,           -- lo que Meta esta haciendo de verdad
  daily_budget   numeric,
  moneda         text,
  age_min        int,
  age_max        int,
  geo            text[],           -- nombres legibles: ciudades, regiones, paises
  publico        jsonb,            -- lista de bloques de criterios (Y entre bloques, O dentro)
  gasto_14d      numeric,
  leads_14d      int,
  clics_14d      int,
  actualizado_en timestamptz not null default now()
);

alter table public.axisworks_meta_campanas_conjuntos enable row level security;
-- Mismo patron que el resto de axisworks_meta_*: RLS on + 0 politicas. Solo el vigilante
-- (service_role, bypassa RLS) escribe; Lawang lee por la funcion de abajo, nunca la tabla.

create or replace function public.crm_campanas_conjuntos()
returns table (
  adset_id text, campaign_id text, cliente text, campana_nombre text, adset_nombre text,
  objetivo text, status text, effective_status text, daily_budget numeric, moneda text,
  age_min int, age_max int, geo text[], publico jsonb,
  gasto_14d numeric, leads_14d int, clics_14d int, actualizado_en timestamptz
)
language sql stable security definer set search_path to ''
as $$
  select c.adset_id, c.campaign_id, c.cliente, c.campana_nombre, c.adset_nombre,
         c.objetivo, c.status, c.effective_status, c.daily_budget, c.moneda,
         c.age_min, c.age_max, c.geo, c.publico,
         c.gasto_14d, c.leads_14d, c.clics_14d, c.actualizado_en
    from public.axisworks_meta_campanas_conjuntos c
   where public.puede('leads')
     and c.cliente in ('Lawang · Bali', 'Lawang · Sumba Hills',
                       'Lawang · Australia', 'Lawang · sin uso')
   order by c.campaign_id, (c.effective_status = 'ACTIVE') desc, c.gasto_14d desc nulls last;
$$;

revoke execute on function public.crm_campanas_conjuntos() from public, anon;
grant execute on function public.crm_campanas_conjuntos() to authenticated;
