-- Dos reflejos generados para que los listados no abran el jsonb de 70 MB.
-- Medido: el panel de contratos tardaba 4.249 ms por leer `nombre_contrato`
-- desde `datos` — un campo que ademas esta vacio en los 112 contratos.
-- Porques completos en proyectos/Lawang/contracts/sql/columnas_baratas_de_contratos.sql
alter table public.contratos
  add column if not exists nombre_contrato text
    generated always as (datos->'fields'->>'nombre_contrato') stored;

alter table public.contratos
  add column if not exists parcela_codigo text
    generated always as (datos->'fields'->>'parcela_codigo') stored;

comment on column public.contratos.nombre_contrato is
  'Reflejo generado de datos.fields.nombre_contrato. Existe para que los listados no tengan que descomprimir el jsonb (70 MB en 112 filas): leerlo de datos costaba 4,2 s.';
comment on column public.contratos.parcela_codigo is
  'Reflejo generado de datos.fields.parcela_codigo (puede ser una LISTA: «A4, A5»). Mismo motivo que nombre_contrato. La verdad del enlace sigue siendo unidades.contrato_id, no este texto.';;
