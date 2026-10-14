-- Huecos y solapes en la frontera 31-oct / 1-nov-2026 (migración comisiones_regla_1nov). SOLO LECTURA: no necesita válvula.
-- Para cada una de las 12 condiciones cerradas el 31-oct se ejecuta la MISMA selección que hace el motor
-- (comisiones_evaluar_contrato) para su alcance (empresa / equipo / nivel / proyecto, closer genérico) el 31-oct y el
-- 1-nov. Correcto = el 31-oct elige la vieja y el 1-nov la sucesora (ni hueco: nada elegido; ni solape: otra).
-- Segunda parte: las condiciones de un closer concreto (0 %) siguen ganando el 1-nov para ese closer.
-- Devuelve filas SOLO cuando algo está mal.
with pares(viejo, nuevo) as (values
  ('22de941a-7d34-4894-8b79-cafbe05d1d56'::uuid, 'c0a11010-1101-4a10-8000-000000000001'::uuid),
  ('4a1c0fe1-f3b1-49b7-a513-328939f0ec1b', 'c0a11010-1101-4a10-8000-000000000002'),
  ('ac9f7557-dbf6-44a4-8ae2-fa31c8d68153', 'c0a11010-1101-4a10-8000-000000000003'),
  ('eab39fea-b874-43dd-87a6-eec94c34efd1', 'c0a11010-1101-4a10-8000-000000000004'),
  ('4a1036e7-58d0-4b81-b5fd-ab0de41dcee1', 'c0a11010-1101-4a10-8000-000000000005'),
  ('3f774dde-e4f1-4086-85f9-c3942acc06ae', 'c0a11010-1101-4a10-8000-000000000006'),
  ('491d8acd-182a-4906-916d-433940a376e5', 'c0a11010-1101-4a10-8000-000000000007'),
  ('c7ac56ca-c0a4-4e76-82bb-6086eccdb4c9', 'c0a11010-1101-4a10-8000-000000000008'),
  ('ddb805c1-335a-409b-9ad7-93ba78bd9619', 'c0a11010-1101-4a10-8000-000000000009'),
  ('57f7369f-3801-4f77-9091-d87fd7db0268', 'c0a11010-1101-4a10-8000-000000000010'),
  ('286adb02-4369-4a39-94a7-6e7735440a40', 'c0a11010-1101-4a10-8000-000000000011'),
  ('bbca7a81-f529-4be9-99d6-feed49228009', 'c0a11010-1101-4a10-8000-000000000012')
), k as (
  select p.viejo, p.nuevo, c.empresa, c.equipo_id, c.nivel, c.proyecto_id from pares p join public.condiciones_comision c on c.id = p.viejo
), elige as (
  select k.*, f.dia,
         (select c.id from public.condiciones_comision c
           where c.empresa = k.empresa
             and c.equipo_id is not distinct from k.equipo_id
             and c.nivel = k.nivel
             and (c.proyecto_id = k.proyecto_id or c.proyecto_id is null)
             and c.closer_email is null
             and (c.activo or c.vigente_hasta is not null)
             and c.vigente_desde <= f.dia and (c.vigente_hasta is null or c.vigente_hasta >= f.dia)
           order by (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
           limit 1) as elegida
    from k cross join (values (date '2026-10-31'), (date '2026-11-01')) f(dia)
)
select 'frontera' as que, empresa, equipo_id, nivel, dia, elegida,
       case when dia = date '2026-10-31' then viejo else nuevo end as esperada
  from elige
 where elegida is distinct from case when dia = date '2026-10-31' then viejo else nuevo end
union all
-- las de un closer concreto ganan el 1-nov para ese closer (estándar: el motor ordena primero closer_email; equipo:
-- busca primero la del closer)
select 'closer propio', p.empresa, p.equipo_id, p.nivel, date '2026-11-01',
       (select c.id from public.condiciones_comision c
         where c.empresa = p.empresa and c.equipo_id is not distinct from p.equipo_id and c.nivel = p.nivel
           and (c.activo or c.vigente_hasta is not null)
           and c.vigente_desde <= date '2026-11-01' and (c.vigente_hasta is null or c.vigente_hasta >= date '2026-11-01')
           and (c.proyecto_id is null)
           and (c.closer_email is null or lower(c.closer_email) = lower(p.closer_email))
         order by (c.closer_email is not null) desc, (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
         limit 1),
       p.id
  from public.condiciones_comision p
 where p.closer_email is not null and p.activo and p.vigente_hasta is null
   and p.id <> (select c.id from public.condiciones_comision c
                 where c.empresa = p.empresa and c.equipo_id is not distinct from p.equipo_id and c.nivel = p.nivel
                   and (c.activo or c.vigente_hasta is not null)
                   and c.vigente_desde <= date '2026-11-01' and (c.vigente_hasta is null or c.vigente_hasta >= date '2026-11-01')
                   and c.proyecto_id is null
                   and (c.closer_email is null or lower(c.closer_email) = lower(p.closer_email))
                 order by (c.closer_email is not null) desc, (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
                 limit 1);
