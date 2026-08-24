alter table public.proyectos
  add column if not exists parcela_master_m2 numeric;

comment on column public.proyectos.parcela_master_m2 is
  'Superficie BRUTA de la parcela master en m2 (el terreno entero, no la subparcela que se vende).';
;
