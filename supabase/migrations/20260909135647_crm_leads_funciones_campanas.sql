-- CRM de leads — pantallas de campañas y automatismos.
-- Las tablas `axisworks_meta_*` son del ESTUDIO y no tienen columna de cliente: el
-- nombre de campaña es texto libre. El dia que el vigilante de B2K o BaliBest escriba
-- ahi, sus filas apareceran solas en la pantalla de Lawang si esto se sirviera como
-- tabla. Por eso se sirve por funcion y con la lista de campañas escrita a mano.
-- Tampoco sale la columna `detalle`: lleva el tope mensual de gasto del estudio, los
-- nombres de las variables internas del vigilante y los presupuestos diarios en crudo.

create or replace function public.crm_campanas()
returns table (
  campaign_id text, cliente text, nombre text, moneda text,
  gasto numeric, impresiones bigint, clics bigint, leads integer,
  gasto_7d numeric, leads_7d integer, ultimo date
)
language sql stable security definer set search_path to ''
as $$
  select i.campaign_id,
         max(i.cliente),
         max(i.nombre),
         max(i.moneda),
         sum(i.gasto),
         sum(i.impresiones),
         sum(i.clics),
         sum(i.leads)::int,
         sum(i.gasto) filter (where i.fecha >= current_date - 7),
         (sum(i.leads) filter (where i.fecha >= current_date - 7))::int,
         max(i.fecha)
    from public.axisworks_meta_insights_dia i
   where public.puede('leads')
     and i.cliente in ('Lawang · Bali', 'Lawang · Sumba Hills',
                       'Lawang · Australia', 'Lawang · sin uso')
   group by i.campaign_id;
$$;

-- La serie semanal: leads recibidos frente a lo invertido. Los leads salen de `leads`
-- (dato propio de Lawang, completo desde el 10-ago) y el gasto del snapshot, que empieza
-- el dia que el vigilante lo siembre. La grafica tiene que poder decir "aqui no hay
-- gasto todavia" en vez de dibujar un cero, que se lee como "no se gasto nada".
create or replace function public.crm_serie_semanal(p_semanas int default 8)
returns table (semana date, leads bigint, gasto numeric)
language sql stable security definer set search_path to ''
as $$
  with rango as (
    select generate_series(
             date_trunc('week', current_date)::date - ((greatest(p_semanas,1) - 1) * 7),
             date_trunc('week', current_date)::date, '7 days')::date as semana
  )
  select r.semana,
         (select count(*) from public.leads l
           where date_trunc('week', l.created_at)::date = r.semana),
         (select sum(i.gasto) from public.axisworks_meta_insights_dia i
           where date_trunc('week', i.fecha)::date = r.semana
             and i.cliente in ('Lawang · Bali', 'Lawang · Sumba Hills',
                               'Lawang · Australia', 'Lawang · sin uso'))
    from rango r
   where public.puede('leads')
   order by r.semana;
$$;

-- Lo que los automatismos del estudio han hecho de verdad sobre las campañas de Lawang.
-- Solo lectura, y sin los numeros internos: cuando, que campaña, que accion y un motivo
-- en lenguaje llano.
create or replace function public.crm_automatismos(p_limite int default 60)
returns table (cuando timestamptz, campana text, accion text, motivo text)
language sql stable security definer set search_path to ''
as $$
  select a.cuando, a.campana, a.accion, a.motivo
    from public.axisworks_meta_vigilancia_acciones a
   where public.puede('leads')
     and a.campana in ('Lawang · Bali', 'Lawang · Sumba Hills',
                       'Lawang · Australia', 'Lawang · sin uso')
   order by a.cuando desc
   limit greatest(1, least(coalesce(p_limite, 60), 200));
$$;

revoke execute on function public.crm_campanas() from public, anon;
revoke execute on function public.crm_serie_semanal(int) from public, anon;
revoke execute on function public.crm_automatismos(int) from public, anon;
grant execute on function public.crm_campanas() to authenticated;
grant execute on function public.crm_serie_semanal(int) to authenticated;
grant execute on function public.crm_automatismos(int) to authenticated;;
