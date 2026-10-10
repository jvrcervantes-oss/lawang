-- Foto de encargos para panel.axisworks.studio/mapa (S1 del encargo panel_visual_encargos, 10-oct-2026).
-- Dueño del dato: el estudio (tools/mapa_snapshot.py lo proyecta de los encargos; esto es copia de solo
-- lectura para el panel, se rehace en cada arranque y aterrizaje). Mismo patron que axisworks_cuentas:
-- RLS on, CERO politicas, revoke a anon/authenticated; solo la service key del backend escribe.
-- Verificado 10-oct con has_table_privilege: anon y authenticated sin select ni insert.
create table if not exists public.axisworks_panel_snapshot (
  id          text primary key check (id = 'estado'),
  doc         jsonb not null default '{}'::jsonb,
  data_at     timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
alter table public.axisworks_panel_snapshot enable row level security;
revoke all on public.axisworks_panel_snapshot from anon, authenticated, public;
comment on table public.axisworks_panel_snapshot is 'Foto de los encargos del estudio para panel.axisworks.studio/mapa (S1 panel visual, 10-oct-2026). Una sola fila (id=estado). Proyeccion de lista blanca hecha por tools/mapa_snapshot.py, que es el unico escritor (service key, desde el arranque y al aterrizar). RLS sin politicas y sin permisos para anon/authenticated: ni lectura ni escritura con la clave publica; el panel lo lee por backend. data_at = hora del ultimo dato.';;
