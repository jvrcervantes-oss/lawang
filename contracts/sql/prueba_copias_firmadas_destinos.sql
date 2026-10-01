-- AXW-127 (1-oct-2026): invariantes de copias_firmadas_destinos (SQL) frente a destinosFirmado (TS, firma-submit).
-- SOLO LECTURA: se puede correr en producción sin transacción. Cada columna debe dar 0. Hasta que exista un test que cruce las
-- dos listas con contratos de casos límite, `copias_firmadas_modo` solo se enciende con esto en verde.
with cs as (select id from public.contratos where pdf_firmado_path is not null and pdf_firmado_hash is not null),
d as (select cs.id, x.* from cs cross join lateral public.copias_firmadas_destinos(cs.id) with ordinality as x(email, nombre, estudio, equipo, elegible, ord)),
fuentes as (
  select cs.id, lower(btrim(coalesce(c.datos->'fields'->>'adq1_email',''))) em from cs join public.contratos c on c.id = cs.id
   where btrim(coalesce(c.datos->'fields'->>'adq1_nombre','')) <> ''
  union select cs.id, lower(btrim(coalesce(e->>'email',''))) from cs join public.contratos c on c.id = cs.id
   cross join lateral jsonb_array_elements(case when jsonb_typeof(c.datos->'compradores') = 'array' then c.datos->'compradores' else '[]'::jsonb end) e
   where btrim(coalesce(e->>'nombre','')) <> ''
  union select f.contrato_id, lower(btrim(coalesce(f.firmante_email,''))) from public.contrato_firmas f join cs on cs.id = f.contrato_id where f.estado = 'firmado'),
valid as (select * from fuentes where em ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$')
select
  (select count(*) from (select id from d group by id having count(*) filter (where estudio) <> 1) z)                            as sin_un_estudio,
  (select count(*) from (select id, lower(email) from d group by 1, 2 having count(*) > 1) z)                                    as duplicados,
  (select count(*) from valid v where not exists (select 1 from d where d.id = v.id and lower(d.email) = v.em))                  as fuente_sin_destino,
  (select count(*) from d where not estudio and not exists (select 1 from valid v where v.id = d.id and v.em = lower(d.email))) as destino_sin_fuente,
  (select count(*) from d where ord = 1 and not estudio)                                                                         as estudio_no_primero;
