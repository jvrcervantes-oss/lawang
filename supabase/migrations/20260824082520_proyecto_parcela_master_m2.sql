-- Superficie BRUTA de la parcela MASTER de cada proyecto, en m2 (encargo del
-- cliente, 24-ago-2026). Mismo terreno que ya tiene su código en
-- `parcela_master` (20260817112306_proyectos_parcela_master.sql) -- esto es
-- su superficie, no un dato nuevo sin relación. Nullable: hoy la mayoría de
-- proyectos no lo tienen medido.
alter table public.proyectos
  add column if not exists parcela_master_m2 numeric;

comment on column public.proyectos.parcela_master_m2 is
  'Superficie BRUTA de la parcela master en m2 (el terreno entero, no la subparcela que se vende).';
