-- CRM /v4/: crm_leads daba 500 (57014, statement_timeout de 8 s de authenticated) — 28-sep-2026.
-- Por qué: la vista lead_sugerencia cruzaba cada lead con cada contrato firmado y sacaba los
--   identificadores del comprador de `contratos.datos` (≈522 kB de media, TOAST) por PAREJA
--   lead×contrato: 132 × 76 descomprimidos del JSON entero, varias veces cada uno. Con 132 leads
--   ya iba a 4,5–8,6 s por carga; al pasar de 8 s, 500. Misma familia que la lentitud TOAST de
--   `datos` (memoria reference_lawang_datos_jsonb_toast_lentitud).
-- Arreglo: los identificadores se calculan UNA vez al escribir el contrato, en una columna
--   generada (la función ya es IMMUTABLE y solo escriben postgres/service_role, que la ejecutan),
--   y la vista lee esa columna. Mismas filas, mismas columnas: crm_leads no cambia.
-- La columna no expone nada nuevo: authenticated ya lee `datos`, que contiene lo mismo.

alter table public.contratos
  add column if not exists identificadores text[]
  generated always as (public.contrato_identificadores(datos)) stored;

create or replace view public.lead_sugerencia with (security_invoker = on) as
 select l.id as lead_id,
        case
            when bool_or(e.etapa = 'contrato') then 'contrato'
            when bool_or(e.etapa = 'reserva') then 'reserva'
            else null::text
        end as etapa,
    min(c.numero) as contrato_numero
   from public.leads l
     join public.contratos c on coalesce(c.bloqueado, false) = true
     join lateral unnest(c.identificadores) ident(ident) on true
     join public.contrato_tipo_etapa e on e.tipo = c.tipo and e.etapa <> 'ninguna'
  where nullif(btrim(l.email), '') is not null
    and lower(btrim(ident.ident)) = lower(btrim(l.email))
    and not exists (select 1 from public.lead_contrato k where k.lead_id = l.id)
  group by l.id;
