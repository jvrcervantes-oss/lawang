-- Metadatos editables por campana de Meta Ads del panel del estudio: donde estan alojados
-- los leads y notas para el agente que los atiende. Los rellena el dueno desde el panel;
-- el id de campana es el mismo id real de Meta (META_CAMPANAS en server.py), no un id propio.
-- RLS ON sin ninguna politica = cero acceso para anon/authenticated (mismo patron ya
-- verificado en axisworks_cuentas/axisworks_facturas); solo entra el service_role del panel.
create table public.axisworks_meta_campanas (
  campaign_id text primary key,
  leads_url text,
  notas text,
  updated_at timestamptz not null default now()
);

comment on table public.axisworks_meta_campanas is
  'Enlace a los leads y notas por campana de Meta Ads, editable desde el panel. Fuente para la vista de agente (/a/<testigo>).';

alter table public.axisworks_meta_campanas enable row level security;

insert into public.axisworks_meta_campanas (campaign_id, leads_url, notas) values
  ('52575467035308', 'https://sumbahills.lawangproperties.com/leads', null);;
