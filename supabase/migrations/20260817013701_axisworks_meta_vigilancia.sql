-- Estado del vigilante de campañas del panel de AxisWorks (freno de Meta Ads, 17-ago-2026).
-- Vive en Supabase y no en disco porque el sistema de ficheros de Railway es EFIMERO: se
-- borra en cada redespliegue, y el estudio redespliega en cada push. Con el estado en
-- disco, `pausados` se vaciaria y el freno podria volver a pausar un conjunto que el owner
-- acababa de reactivar a mano, y `formularios` se vaciaria dejando la regla del formulario
-- nuevo muda para siempre (su primera pasada no avisa a proposito).
-- RLS on + CERO politicas, mismo patron que axisworks_cuentas / axisworks_facturas /
-- axisworks_meta_campanas: nadie con la clave publicable lo ve; solo la service key del
-- panel, que salta RLS por diseño.
create table if not exists public.axisworks_meta_vigilancia (
  id          text primary key,
  doc         jsonb not null default '{}'::jsonb,
  updated_at  timestamptz not null default now()
);

alter table public.axisworks_meta_vigilancia enable row level security;

comment on table public.axisworks_meta_vigilancia is
  'Estado del vigilante de campañas de Meta del panel de AxisWorks: que conjuntos pauso el freno, que formularios conocia y que avisos ya se mandaron. Una sola fila (id=estado). Escrito solo por infraestructura/panel-web/server.py con la service key.';;
