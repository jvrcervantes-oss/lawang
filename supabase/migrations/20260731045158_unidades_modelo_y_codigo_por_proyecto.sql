alter table public.unidades add column if not exists modelo text;
alter table public.unidades drop constraint if exists unidades_codigo_key;
alter table public.unidades drop constraint if exists unidades_proyecto_codigo_key;
alter table public.unidades add constraint unidades_proyecto_codigo_key unique (proyecto, codigo);;
